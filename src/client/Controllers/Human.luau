--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Controllers.Human
-- W0 (spike S2) human controller on a possessed R15 body. Movement is Roblox's own Humanoid
-- controller (the default PlayerModule drives Humanoid:Move); this module adds the handoff:
-- the body keeps the AI's last move direction for up to `holdSeconds` (0.75 s) or until the first
-- input (BUILD_PLAN §1.5 step 5), so the stride carries on, and disables the Dead state on the
-- owning client (Humanoid states are evaluated by the network owner) so nothing local can kill it.
-- Measures input-to-response latency for the S2 checklist.
-- No side effects on require.
-- Interface: start(body, payload, metrics) -> stop()

local Import = require("../Import")
local PossessionState =
	Import.shared("Actors/PossessionState") :: typeof(require("../../shared/Actors/PossessionState"))

export type Metrics = { [string]: any }

local Human = {}

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

function Human.start(body: Model, payload: PossessionState.GrantPayload, metrics: Metrics): () -> ()
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

	local conns = {}
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
		endHold()
		for _, c in conns do
			c:Disconnect()
		end
	end
end

return Human
