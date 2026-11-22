--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Controllers.Human
-- W0 (spike S2) human controller on a possessed R15 body. Movement is Roblox's own Humanoid
-- controller (the default PlayerModule drives Humanoid:Move); this module adds the handoff:
-- the body keeps the AI's last move direction for up to `holdSeconds` (0.75 s) or until the first
-- input (BUILD_PLAN §1.5 step 5), so the stride carries on, and disables the Dead state on the
-- owning client (Humanoid states are evaluated by the network owner) so nothing local can kill it.
-- Measures input-to-response latency for the S2 checklist. Shift sprints (WalkSpeed 16 -> SPRINT;
-- the owning client's WalkSpeed is what the Humanoid simulates; first playable build).
-- A minigame may change the pace for a moment (a crouch, a lunge, a dive): the body's "MoveScale" attribute
-- multiplies the speed (0 to 2) and "NoSprint" switches Shift off. This module writes WalkSpeed every frame, so
-- those attributes are the only way to change it; MinigameClient sets them (ClientGame.Ctx.pace) and clears
-- them when the game closes.
-- No side effects on require.
-- A soda or an ice cream bar from the corner store (Server/Items/ItemWorld "treat") sets the body attributes TreatUntil
-- (server time) and TreatScale: until then the pace is that much faster (treat()).
-- Bumped by one of the town's shared little vehicles (owner D29; Server/Vehicles/RideBumps through Boot/Game): the server
-- writes the body's Knock (a Vector3: the slide's x, the seconds down, the slide's z), KnockFall and KnockAt (server
-- time, the trigger). The body is pushed along the slide (a small hop with it on a fall); a fall tips it over that way
-- (PlatformStand: the body goes over as a whole) and it lies there for the seconds, then gets up (GettingUp); a stagger
-- only pushes. The controls are off meanwhile. Never a death (Dead stays off), never a ragdoll.
-- Interface: start(body, payload, metrics) -> stop(); speed(sprint, scale?, noSprint?) -> studs per second;
--   treat(untilTime?, scale?, now) -> multiplier; knock(knock?, fall?, at?, now) -> Push? (pure);
--   WALK; SPRINT; MAX_SCALE; KNOCK

export type Metrics = { [string]: any }

local Human = {}

-- Owner 2026-11-10: people a slight bit faster, and they never run out of the ability to run (no
-- stamina here); the squirrel walks at 18 and sprints at 33 in bursts (SquirrelMotor.params).
Human.WALK = 17
Human.SPRINT = 28
Human.MAX_SCALE = 2

-- The corner store's sugar rush: TreatScale (at most 1.25) until TreatUntil, else 1.
function Human.treat(untilTime: any, scale: any, now: number): number
	if type(untilTime) ~= "number" or type(scale) ~= "number" or now >= untilTime then
		return 1
	end
	return math.clamp(scale, 1, 1.25)
end

-- The walking speed this frame: Shift sprints unless the game on screen has switched it off, and the game's
-- scale multiplies whichever it is (anything that is not a number between 0 and MAX_SCALE counts as 1 or is
-- clamped: an attribute is whatever somebody wrote).
function Human.speed(sprint: boolean, scale: any, noSprint: any): number
	local k = if type(scale) == "number" and scale == scale then math.clamp(scale, 0, Human.MAX_SCALE) else 1
	return (if sprint and noSprint ~= true then Human.SPRINT else Human.WALK) * k
end

-- The knock (owner D29): the slide's speed is its length over `slide` seconds; a fall hops `hop` studs/s up and turns
-- over at `tip` rad/s; a knock older than `fresh` seconds when it arrives is not played (a body handed over later).
Human.KNOCK = table.freeze({ slide = 0.35, hop = 7, tip = 5, fresh = 1.5, minSecs = 0.3, maxSecs = 4 })

export type Push = { vx: number, vy: number, vz: number, fall: boolean, secs: number, tipX: number, tipZ: number }

-- knock(knock, fall, at, now): what a fresh Knock attribute does to the body: its push (studs/s), whether it falls,
-- how long the controls are off, and the axis it tips over about (horizontal, square to the push). nil when there is
-- none, it is stale, or it is not a knock at all (an attribute is whatever somebody wrote).
function Human.knock(knock: any, fall: any, at: any, now: number): Push?
	if typeof(knock) ~= "Vector3" or type(at) ~= "number" or now - at > Human.KNOCK.fresh or now < at - 1 then
		return nil
	end
	local K = Human.KNOCK
	local k = knock :: Vector3
	local dx, dz = k.X, k.Z
	if dx ~= dx or dz ~= dz then
		return nil
	end
	local falls = fall == true
	return {
		vx = dx / K.slide,
		vy = if falls then K.hop else 0,
		vz = dz / K.slide,
		fall = falls,
		secs = math.clamp(if k.Y == k.Y then k.Y else 0, K.minSecs, K.maxSecs),
		tipX = dz,
		tipZ = -dx,
	}
end

-- KeyCode names (Enum is not available under Lune, where the skeleton test requires this module)
local MOVE_KEYS: { [string]: boolean } = {
	W = true,
	A = true,
	S = true,
	D = true,
	Up = true,
	Down = true,
	Left = true,
	Right = true,
	Space = true,
	Thumbstick1 = true,
}

local function controls(): any?
	local Players = game:GetService("Players")
	local ok, mod = pcall(function()
		local ps = (Players.LocalPlayer :: any).PlayerScripts :: Instance
		return (require :: any)(ps:WaitForChild("PlayerModule", 5)):GetControls()
	end)
	return if ok then mod else nil
end

function Human.start(body: Model, payload: { [string]: any }, metrics: Metrics): () -> ()
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	local root = body.PrimaryPart
	if humanoid == nil or root == nil then
		return function() end
	end
	local hum = humanoid :: Humanoid
	local rootPart = root :: BasePart
	hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	hum.WalkSpeed = Human.WALK

	local snap = payload.snapshot
	local dir = Vector3.new(snap.vx, 0, snap.vz)
	local hold = dir.Magnitude > 0.1
	dir = if hold then dir.Unit else Vector3.zero
	local holdUntil = os.clock() + payload.holdSeconds
	local ctl = controls()
	if hold and ctl then
		ctl:Disable()
	end
	local inputAt: number? = nil
	local inputVel = Vector3.zero

	local function endHold()
		if hold then
			hold = false
			if ctl then
				ctl:Enable()
			end
		end
	end

	-- bumped by a shared vehicle (owner D29): pushed, maybe over, controls off until `knockedUntil` (os.clock)
	local knockedUntil = 0
	local function getUp()
		if knockedUntil > 0 then
			knockedUntil = 0
			if hum.PlatformStand then
				hum.PlatformStand = false
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
			if ctl and not hold then
				ctl:Enable()
			end
		end
	end
	local function onKnock()
		local push = Human.knock(
			body:GetAttribute("Knock"),
			body:GetAttribute("KnockFall"),
			body:GetAttribute("KnockAt"),
			workspace:GetServerTimeNow()
		)
		if push == nil or hum.SeatPart ~= nil then
			return
		end
		endHold()
		if ctl then
			ctl:Disable()
		end
		hum:Move(Vector3.zero)
		rootPart.AssemblyLinearVelocity = Vector3.new(push.vx, push.vy, push.vz)
		if push.fall then
			hum.PlatformStand = true
			local axis = Vector3.new(push.tipX, 0, push.tipZ)
			if axis.Magnitude > 1e-3 then
				rootPart.AssemblyAngularVelocity = axis.Unit * Human.KNOCK.tip
			end
		end
		knockedUntil = os.clock() + push.secs
	end

	local conns = {}
	table.insert(conns, body:GetAttributeChangedSignal("KnockAt"):Connect(onKnock))
	table.insert(
		conns,
		UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
			if MOVE_KEYS[input.KeyCode.Name] or input.UserInputType == Enum.UserInputType.Touch then
				if inputAt == nil then
					inputAt = os.clock()
					inputVel = rootPart.AssemblyLinearVelocity
				end
				endHold()
			end
		end)
	)
	table.insert(
		conns,
		RunService.RenderStepped:Connect(function()
			if knockedUntil > 0 and os.clock() >= knockedUntil then
				getUp()
			end
			local sprint = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			hum.WalkSpeed = Human.speed(sprint, body:GetAttribute("MoveScale"), body:GetAttribute("NoSprint"))
				* Human.treat(
					body:GetAttribute("TreatUntil"),
					body:GetAttribute("TreatScale"),
					workspace:GetServerTimeNow()
				)
			if hold then
				if os.clock() >= holdUntil then
					endHold()
				else
					hum:Move(dir, false)
				end
			end
			local t0 = inputAt
			if t0 and metrics.inputToMoveMs == nil then
				if (rootPart.AssemblyLinearVelocity - inputVel).Magnitude > 1 then
					metrics.inputToMoveMs = math.floor((os.clock() - t0) * 1000 + 0.5)
				elseif os.clock() - t0 > 2 then
					inputAt = nil -- the input did not change motion (e.g. already walking that way)
				end
			end
		end)
	)
	return function()
		getUp()
		endHold()
		for _, c in conns do
			c:Disconnect()
		end
	end
end

return Human
