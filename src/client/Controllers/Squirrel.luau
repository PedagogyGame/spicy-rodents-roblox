--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Controllers.Squirrel
-- Controller for a held squirrel (and the rodent, a squirrel actor with Variant "spicy"). The body is
-- kinematic (owner rule 2026-11-09): every render frame Shared/Movement/SquirrelMotor (the v5.4
-- updatePlayer port: ground glue, rails, leap, drop, grab, fork and junction choice, pounce, trampoline)
-- advances the authoritative point from InputMap, Shared/Movement/SquirrelVisual eases the drawn pose
-- after it (v5.4's render layer: 23/s position easing, ground contact under the drawn point, bark-facing
-- nose-up pose on a trunk, lean into turns), and BodyDriver.driveRender writes that pose as the root's
-- CFrame for the frame being drawn. No Humanoid, no physics settling, no root motion: the animation layer
-- reads the motor's speed and stride rate from KinematicPose and only poses the mesh.
-- The rail world (Movement/RailWorld) builds in the background on the client; until it is ready the same
-- motor runs against an empty rail world (ground, leap, walls), and the routes appear under it the first
-- frame they exist, with no second possession needed.
-- Possession carry-over (BUILD_PLAN 1.5 step 5): the motor starts at the rendered pose with the snapshot's
-- heading and momentum; an AI squirrel suspended on a rail (snapshot.brain.routeId, s, dir) resumes on
-- that rail at the same arc position; the AI's direction is held for up to holdSeconds or until the
-- first input.
-- Recovery: the motor is the only authority on where the body is, so the two things that move it from
-- outside are taken in here. A fall into the river puts it on the nearer quay (v5.4 recoverRiverFall,
-- called after the motor step as in L6767). A teleport by the server (the Reset button, the server's own
-- rescue) shows up as a root that is not where the last frame left it; the motor restarts from there
-- instead of writing the old position back over it.
-- Feedback (owner rule: never ignore input silently): E with nothing to grab, Q on the ground and the
-- motor's hints ("climb closer", "too far to jump across") become short toasts through ctx.toast, and so does
-- what a route's own record says to do at its far end (its `hint`: the alley roof's ridge and bough say jump or drop)
-- or on going on from there by itself (its `onwardHint`: out of the alley's vent into the rafters).
-- Sprint is a burst (SquirrelMotor stamina): ctx.meter draws the meter, and running out says so.
-- The server's validator (ctx.link, Controllers/MotorLink): after each step the motor's state goes up twenty times a
-- second; a "Correction" the server sent (a snap-back, a move it made) is taken at the top of the next frame, and the
-- server's own move of the root arriving after it (link:echo) is not taken for a second move.
-- Night vision (World/NightVision) is the Spicy Rodent's alone: N toggles it; an ordinary squirrel
-- pressing N is told so.
-- The water gun's stun (body attribute StunnedUntil, server time; Items/ItemWorld): no input reaches the motor.
-- The air trick (owner D17, redone D18): G, gamepad R1, or on a touch screen UI/AirTrickButton (shown in the air while
-- a press can do something) goes to the motor as `trick`; the move and its time left go to the animation layer
-- (KinematicPose trick, trickLeft: Shared/Movement/AirTrick poses it). After a mid-jump press (the motor's "trick"
-- event, "wiggle") the re-aim is live until the landing: the camera's turn since the press is the aim (aimOf: its yaw
-- either side, its look up = further out, down = nearer in, full at AIM_PITCH). The mouse IS the look on foot
-- (Camera/CameraRig) and the right stick too, so the camera follows the aimed heading and nothing swings it besides;
-- on a touch screen a drag from the button is the aim instead (AirTrickButton.aimOf). UI/AimMarker shows where the
-- flight comes down while the aim is live (this player only). The press is also the burst (owner D20; the motor's own:
-- the flight thrown onto the line the keys steer from the camera, shifted along it and popped); the marker's spot is
-- the motor's landingSpot, which counts what is left of it, and the turn asked goes to the pose (KinematicPose
-- trickTurn).
-- Body attributes it writes for the client's other parts: CameraZone ("tunnel" on an enclosed run) and, on an
-- enclosed run, ExitPicked (the route A or D picked, kept by the motor until it is passed; World/SewerAmbience).
-- The Spicy Rodent's pounce has a wind-up (brief v2 §8; Tunables pounce.windup): the click is sent to the duel at once
-- (ctx.duel("pounce", clock, seq): the tell everyone sees, Server/Combat/CombatService, with the motor clock it was made
-- at and its number; a copy also rides in the motor packets, MotorLink.click, and the server takes whichever arrives first)
-- and the motor's pounce follows windup seconds later on the motor's own clock (the one its packets carry: the server
-- ties the two on it), a move the validator accepts as it always has. A click while the motor is still on its
-- cooldown is not sent.
-- Interface: start(body, payload, metrics, ctx) -> stop(); ctx = { world, input, toast?, meter?, variant?, link?, duel? };
--   windup(pendingAt, clock, pressed, secs, ready) -> (pounceNow, pendingAt?, tell) (pure);
--   nightVisionSays(spicy, on) -> string (pure);
--   feedback(frame, events, onRoute, railT?, routeOf?) -> string? (pure); routeHint(route?, t?) -> string? (pure);
--   cameraZone(route?) -> "tunnel"? (pure); hipOf(body, measured) -> studs;
--   movedFromOutside(gap, speed, frameDt) -> boolean (pure); modeOf(onRoute, climb, grounded, trunk?) ->
--   string (pure); launch(events, vy) -> action?, airSeconds? (pure); stunned(untilTime, now) -> boolean (pure);
--   aimOf(yaw0, pitch0, yaw, pitch) -> (aimYaw, aimReach) (pure); AIM_PITCH
-- No side effects on require.

local Import = require("../Import")
local SquirrelMotor = Import.shared("Movement/SquirrelMotor") :: typeof(require("../../shared/Movement/SquirrelMotor"))
local SquirrelVisual =
	Import.shared("Movement/SquirrelVisual") :: typeof(require("../../shared/Movement/SquirrelVisual"))
local RailWorld = Import.shared("Movement/RailWorld") :: typeof(require("../../shared/Movement/RailWorld"))
local Recovery = Import.shared("Movement/Recovery") :: typeof(require("../../shared/Movement/Recovery"))
local Units = Import.shared("Config/Units") :: typeof(require("../../shared/Config/Units"))
local Enclosure = Import.shared("Routes/Enclosure") :: typeof(require("../../shared/Routes/Enclosure"))
local PossessionState =
	Import.shared("Actors/PossessionState") :: typeof(require("../../shared/Actors/PossessionState"))
local BodyDriver = require("./BodyDriver")
local KinematicPose = require("./KinematicPose")
local NightVision = require("../World/NightVision")
local AirTrickButton = require("../UI/AirTrickButton")
local AimMarker = require("../UI/AimMarker")
local AirTrick = Import.shared("Movement/AirTrick") :: typeof(require("../../shared/Movement/AirTrick"))

local Tunables = Import.shared("Config/Tunables") :: typeof(require("../../shared/Config/Tunables"))

local Squirrel = {}

-- radians of camera pitch for the whole re-aim out (looking up) or in (looking down)
Squirrel.AIM_PITCH = math.rad(15)

-- The re-aim the camera asks for, from its yaw and pitch at the wiggle's press to now: the turn either side (wrapped;
-- the motor holds it to trickAimYaw) and the look up or down as -1 in .. 1 out.
function Squirrel.aimOf(yaw0: number, pitch0: number, yaw: number, pitch: number): (number, number)
	local turn = (yaw - yaw0 + math.pi) % (2 * math.pi) - math.pi
	return turn, math.clamp((pitch - pitch0) / Squirrel.AIM_PITCH, -1, 1)
end

-- The rodent's wind-up: a press starts it (tell: send it to the duel) when the motor is ready; the pounce goes to the
-- motor `secs` later; presses during a wind-up are ignored.
function Squirrel.windup(
	pendingAt: number?,
	clock: number,
	pressed: boolean,
	secs: number,
	ready: boolean
): (boolean, number?, boolean)
	if pendingAt ~= nil then
		if clock >= pendingAt then
			return true, nil, false
		end
		return false, pendingAt, false
	end
	if pressed and ready then
		if secs <= 0 then
			return true, nil, true
		end
		return false, clock + secs, true
	end
	return false, nil, false
end

local HINTS: { [string]: string } = {
	climbCloser = "Climb closer to the fork, then press E",
	noTransfer = "Nothing to grab within reach: get right under a branch or wire",
	nothingNear = "Nothing to grab here: run into a tree, pole or downspout to climb",
	junctionAhead = "Junction ahead: A or D picks the way",
	-- inside an enclosed run (Shared/Routes/Enclosure) away from its openings
	noRoom = "No room to jump in here: run on to an opening",
}

-- The hint for arriving at the far end of `route` at `t` (pure; nil: nothing to say there): the route record's own
-- `hint`. Only the far end (t = 1) has one: the other end leads on.
function Squirrel.routeHint(route: { hint: string? }?, t: number?): string?
	if route == nil or t == nil or t < 0.5 then
		return nil
	end
	return route.hint
end

-- The camera zone for the route the body is on (pure): "tunnel" on any enclosed run (Shared/Routes/Enclosure.zone:
-- the ball return, a hollow tree's inside, whatever its origin), so CameraPolicy puts the camera inside with it; nil
-- elsewhere.
function Squirrel.cameraZone(route: any?): string?
	return if Enclosure.zone(route) ~= nil then "tunnel" else nil
end

-- What to tell the player about this frame's verbs (pure; nil = nothing to say). `frame` is the
-- InputMap sample, `events` the motor's events, `onRoute` whether the body is on a rail now, `railT` where
-- along it, `routeOf(id)` the route record of an id (a route with something to do at its far end says so on
-- arriving there: routeHint; one whose far end carries on by itself says its onwardHint on the way out).
function Squirrel.feedback(
	frame: { [string]: any },
	events: { { [string]: any } },
	onRoute: boolean,
	railT: number?,
	routeOf: ((id: number) -> any)?
): string?
	local function route(id: number?): any
		return if id ~= nil and routeOf then routeOf(id) else nil
	end
	for _, e in events do
		if e.kind == "hint" and e.reason and HINTS[e.reason] then
			return HINTS[e.reason]
		end
		if e.kind == "railEnd" then
			local said = Squirrel.routeHint(route(e.routeId), railT)
			if said then
				return said
			end
		end
		if e.kind == "autoSwitch" then
			local from = route(e.fromRouteId)
			if from and from.onwardHint then
				return from.onwardHint
			end
		end
		if e.kind == "winded" then
			return "Out of fumes: sprint comes back in a few seconds"
		end
		if e.kind == "lip" then
			-- the head out of an enclosed run's opening (the ball return's hood over the rack, a knothole)
			return "Space jumps out, click pounces, Q drops, S goes back in"
		end
	end
	local attached = false
	for _, e in events do
		local k = e.kind
		if k == "attach" or k == "transfer" or k == "forkTaken" or k == "branchHop" or k == "junctionChosen" then
			attached = true
		end
	end
	if frame.grab and not attached and not onRoute then
		return "Nothing to grab here: run into a tree, pole or downspout to climb"
	end
	if frame.drop and not onRoute then
		return "Q lets go of a branch: you are already on the ground"
	end
	return nil
end

-- What pressing N says: `spicy` whether this body is the Spicy Rodent, `on` the state after the press.
function Squirrel.nightVisionSays(spicy: boolean, on: boolean): string
	if not spicy then
		return "Only the Spicy Rodent has night vision"
	end
	return if on then "Night vision on (N turns it off)" else "Night vision off"
end

-- The root's height above the soles: the body's HipHeight attribute, else the measured gap (clamped).
function Squirrel.hipOf(body: Model, measured: number): number
	local hip = body:GetAttribute("HipHeight")
	if type(hip) == "number" and hip > 0 then
		return hip
	end
	return math.clamp(measured, 0.1, 3)
end

-- Whether a root found `gap` studs from where the last frame wrote it was moved by someone else. Physics
-- carries the body at the written velocity between frames (twice that is allowed for an uneven frame);
-- beyond that and a little slack it is a teleport.
Squirrel.OUTSIDE_SLACK = 2
function Squirrel.movedFromOutside(gap: number, speed: number, frameDt: number): boolean
	return gap > Squirrel.OUTSIDE_SLACK + speed * math.max(frameDt, 0) * 2
end

-- Whether the body is stunned now (the water gun: its StunnedUntil attribute, server time, against `now`):
-- the motor then gets no input at all, so the body stands (or falls, or rolls to a stop) as if nothing were
-- pressed, which the server's MoveValidator already takes as honest. Pure.
function Squirrel.stunned(untilTime: any, now: number): boolean
	return type(untilTime) == "number" and now < untilTime
end

-- What the held body is doing, for a rig that plays clips (KinematicPose.mode): on a rail it is on a
-- "trunk" from the moment it takes one (`trunk`: SquirrelVisual's; the nose comes up over the next half
-- second, and it should not trot a wire meanwhile) and while more than half of the climb pose still shows
-- after it leaves one (SquirrelVisual's `climb`), else running a "rail"; off one it is on the "ground" or
-- in the "air". Pure: the offline motion preview (tools/review/motion) asks the same question.
function Squirrel.modeOf(onRoute: boolean, climb: number, grounded: boolean, trunk: boolean?): string
	if onRoute then
		return if trunk or climb > 0.5 then "trunk" else "rail"
	end
	return if grounded then "ground" else "air"
end

-- How this frame's motor events sent the body into the air, for a rig that plays clips
-- (KinematicPose.action, airSeconds): "leap" or "pounce", and the seconds until gravity brings it back
-- down to the height it left (`vy`: its vertical speed after the launch, studs/s). nil: nothing did.
function Squirrel.launch(events: { { [string]: any } }, vy: number): (string?, number?)
	for _, e in events do
		if e.kind == "leap" or e.kind == "pounce" then
			return e.kind, 2 * math.max(vy, 0) / SquirrelMotor.params.gravity
		end
	end
	return nil, nil
end

function Squirrel.start(
	body: Model,
	payload: { [string]: any },
	metrics: { [string]: any },
	ctx: { [string]: any }
): () -> ()
	local root = body.PrimaryPart
	if root == nil then
		return function() end
	end
	local world = ctx.world
	local input = ctx.input
	local rw = world.rail()
	local railLive = rw ~= nil
	local first = rw or RailWorld.empty()
	local motorWorld = {
		registry = first.registry,
		index = first.index,
		graph = first.graph,
		trampolines = first.trampolines,
		groundAt = world.groundAt,
		blocked = world.blocked,
		blockedCore = world.blockedCore,
		blockedHalf = world.blockedHalf,
		wallsFrom = world.wallsFrom,
		clamp = world.clamp,
	}
	local function routeOf(id: number): any
		return motorWorld.registry:get(id)
	end
	local pos = root.Position
	local ground = world.groundAt(pos.X, pos.Z, pos.Y)
	-- the root's height above the soles is the body's own HipHeight (PuppetSpec), not the gap to the
	-- ground at the handoff: a squirrel taken on a trunk or in the air is nowhere near the ground
	local hip = Squirrel.hipOf(body, pos.Y - ground)
	local feet = pos.Y - hip
	local snap = payload.snapshot or {}
	local state = SquirrelMotor.new(pos.X, ground, pos.Z)
	state.yaw = (snap.yaw or 0) + math.pi
	state.vx, state.vz = snap.vx or 0, snap.vz or 0
	-- the sprint meter as the server has it (the grant's: the body's last driver left it so; the server's validator holds
	-- this driver to the same meter, Movement/MoveValidator.meterOf)
	if type(payload.stamina) == "number" and payload.stamina == payload.stamina then
		state.stamina = math.clamp(payload.stamina, 0, 1)
		state.winded = payload.winded == true
	end
	local b = snap.brain
	if railLive and b and b.routeId and b.routeId ~= 0 then
		local route = motorWorld.registry:get(b.routeId)
		if route and route.length > 0 then
			state.routeId = b.routeId
			state.railT = math.clamp((b.s or 0) / route.length, 0, 1)
			state.railDir = if (b.dir or 1) >= 0 then 1 else -1
			state.grounded = false
		end
	end
	if state.routeId == nil and feet - ground > SquirrelMotor.params.glueMin then
		-- taken in the air (or off a rail that is not built yet): fall from where the body is drawn
		state.y = feet
		state.grounded = false
	end
	local link = ctx.link
	if link then
		state.clock = link:resumeClock() -- (the server's validator reads a clock that never runs back)
	end
	-- the drawn pose starts exactly where the body is drawn now and eases onto the motor from there
	local visual = SquirrelVisual.new()
	visual.x, visual.y, visual.z = pos.X, feet, pos.Z
	visual.live = true
	visual.yaw = state.yaw
	local kin: KinematicPose.Pose = { moveSpeed = 0, cadence = 0, climb = 0 }
	KinematicPose.set(body, kin)

	local holdUntil = os.clock() + (payload.holdSeconds or 0.75)
	local holding = state.routeId ~= nil or math.abs(state.vx) + math.abs(state.vz) > 0.1
	local last, lastSpeed = pos, 0
	local lastSaid, lastText = -math.huge, ""
	local shownStamina, shownWinded = -1, false
	local spicy = (ctx.variant or payload.variant or body:GetAttribute("Variant")) == "spicy"
	local windupSecs = Tunables.get("pounce.windup")
	local pounceAt: number? = nil
	local vision: NightVision.Handle? = nil
	local trickButton: AirTrickButton.Handle? = nil
	if game:GetService("UserInputService").TouchEnabled then
		trickButton = AirTrickButton.start()
	end
	-- the re-aim: the camera at the wiggle's press (nil: no aim live), and its marker
	local aimFrom: { yaw: number, pitch: number }? = nil
	local marker = AimMarker.start()
	local function cameraPitch(): number
		return math.asin(math.clamp(workspace.CurrentCamera.CFrame.LookVector.Y, -1, 1))
	end
	local stopDrive = BodyDriver.driveRender(root, function(frameDt: number)
		local dt = math.min(frameDt, 0.08)
		if not railLive and state.routeId == nil then
			local built = world.rail()
			if built then
				motorWorld.registry, motorWorld.index = built.registry, built.index
				motorWorld.graph, motorWorld.trampolines = built.graph, built.trampolines
				-- Motion caches the trunk feet of the registry it first saw on the world table
				local cache: any = motorWorld
				cache._trunkFeet = nil
				railLive = true
			end
		end
		-- a correction from the server's validator: a snap-back's state restored, or the place it moved the body to
		if link and link:apply(state, os.clock()) then
			visual.live = false
			holding = false
		end
		local at = root.Position
		if
			Squirrel.movedFromOutside((at - last).Magnitude, lastSpeed, frameDt)
			and not (link and link:echo(at.X, at.Y, at.Z, hip, os.clock()))
		then
			-- moved by the server: restart the motor where the body now is, and cut the drawn point to it
			local g = world.groundAt(at.X, at.Z, at.Y)
			local soles = at.Y - hip
			local air = soles - g > SquirrelMotor.params.glueMin
			SquirrelMotor.place(state, at.X, if air then soles else g, at.Z, not air)
			visual.live = false
			holding = false
		end
		local f = input:sample(BodyDriver.cameraYawHtml())
		if f.nightVision then
			local nowOn = false
			if spicy then
				local h = vision or NightVision.start()
				vision = h
				nowOn = h.toggle()
			end
			if ctx.toast then
				ctx.toast(Squirrel.nightVisionSays(spicy, nowOn), 2)
			end
		end
		local mi = {
			fw = f.fw,
			side = f.side,
			sprint = f.sprint,
			focus = f.focus,
			cameraYaw = f.cameraYaw,
			cameraPitch = 0.12,
			leap = f.leap,
			drop = f.drop,
			grab = f.grab,
			choose = if state.routeId then f.choose else 0,
			pounce = f.pounce,
			trick = f.trick or (trickButton ~= nil and trickButton.consume()),
			aimYaw = nil :: number?,
			aimReach = nil :: number?,
		}
		local from = aimFrom
		if from and state.trickKind == 2 and not state.grounded then
			local dx: number?, dy: number? = nil, nil
			if trickButton then
				dx, dy = trickButton.drag()
			end
			if dx and dy then
				mi.aimYaw, mi.aimReach = AirTrickButton.aimOf(dx, dy, SquirrelMotor.params.trickAimYaw)
			else
				mi.aimYaw, mi.aimReach = Squirrel.aimOf(from.yaw, from.pitch, f.cameraYaw, cameraPitch())
			end
		end
		if spicy then
			local now, pend, tell = Squirrel.windup(pounceAt, state.clock, f.pounce, windupSecs, state.cooldown <= 0)
			pounceAt = pend
			mi.pounce = now
			if tell then
				local seq = if link then link:click(state.clock) else nil
				if ctx.duel then
					ctx.duel("pounce", state.clock, seq)
				end
			end
		end
		local any = f.fw ~= 0 or f.side ~= 0 or f.leap or f.drop or f.grab or f.pounce or mi.trick
		if any then
			holding = false
		elseif holding and os.clock() < holdUntil then
			-- keep the AI's stride: forward along the current heading (camera behind the body)
			mi.fw = 1
			mi.cameraYaw = state.yaw + math.pi
		end
		-- (the server clock is read only for a body that has ever been stunned)
		local stunnedUntil = body:GetAttribute(PossessionState.ATTR.StunnedUntil)
		if stunnedUntil ~= nil and Squirrel.stunned(stunnedUntil, workspace:GetServerTimeNow()) then
			mi = SquirrelMotor.idleInput(f.cameraYaw)
			holding = false
		end
		local wasOnRoute = state.routeId ~= nil
		local _, events = SquirrelMotor.step(state, mi, dt, motorWorld :: any)
		for _, e in events do
			metrics.lastEvent = e.kind
			if e.kind == "trick" and e.reason == "wiggle" then
				aimFrom = { yaw = f.cameraYaw, pitch = cameraPitch() }
				-- (the twitch's seed, as the server dates it from this flight's packets: AirTrick.pressOf)
				kin.trickSeed = AirTrick.seedOf(AirTrick.pressOf(state.clock, state.trickTime))
				kin.trickTurn = state.trickTurn
			end
		end
		local aiming = aimFrom ~= nil and state.trickKind == 2 and not state.grounded and state.routeId == nil
		if not aiming then
			aimFrom = nil
		end
		-- (the marker: where the flight comes down, while the aim is live)
		local mx, my, mz = nil, nil, nil
		if aiming then
			local lx, lz, land = SquirrelMotor.landingSpot(state, motorWorld :: any)
			if lx and lz and land and land < 5 then
				mx, mz = lx, lz
				my = world.groundAt(lx, lz, state.y)
			end
		end
		marker.set(mx, my, mz, dt)
		if state.routeId == nil then
			local rx, ry, rz = Recovery.riverFall(state.x, state.y, state.z)
			if rx and ry and rz then
				SquirrelMotor.place(state, rx, ry, rz, true)
				metrics.lastEvent = "riverRecover"
				if link then
					link:urgent() -- (the server's validator sees the quay spot itself)
				end
			end
		end
		if link then
			link:tick(state)
		end
		local say = if ctx.toast
			then Squirrel.feedback(f :: any, events :: any, wasOnRoute, state.railT, routeOf)
			else nil
		local t = os.clock()
		if say and t - lastSaid > 1.5 and (say ~= lastText or t - lastSaid > 8) then
			lastSaid, lastText = t, say
			ctx.toast(say, 2.5)
		end
		if ctx.meter and (math.abs(state.stamina - shownStamina) > 0.004 or state.winded ~= shownWinded) then
			shownStamina, shownWinded = state.stamina, state.winded
			ctx.meter(state.stamina, state.winded)
		end
		-- any enclosed run (the ball return, a hollow tree's inside): the camera rides low behind (CameraPolicy zone)
		local zone = Squirrel.cameraZone(if state.routeId then motorWorld.registry:get(state.routeId) else nil)
		if body:GetAttribute("CameraZone") ~= zone then
			body:SetAttribute("CameraZone", zone)
		end
		-- on an enclosed run, the way off it A or D picked (kept by the motor until it is passed): World/SewerAmbience
		-- names it at drain 1's crossing
		local picked = if zone ~= nil then state.selectedJunction else nil
		if body:GetAttribute("ExitPicked") ~= picked then
			body:SetAttribute("ExitPicked", picked)
		end
		-- what is drawn: the eased pose, about the feet point (yaw, then nose-up pitch and lean, then the hip)
		local snapped = SquirrelVisual.frame(visual, state, motorWorld :: any, dt, world.groundAt)
		kin.moveSpeed, kin.cadence, kin.climb = visual.moveSpeed, visual.cadence, visual.climb
		kin.mode = Squirrel.modeOf(state.routeId ~= nil, visual.climb, state.grounded, visual.trunk)
		kin.stalk = state.focus
		kin.winded = state.winded
		kin.trick, kin.trickLeft = state.trickKind, state.trickTime
		kin.trickAimYaw, kin.trickAimReach = state.aimYaw, state.aimReach
		if trickButton then
			trickButton.set(AirTrickButton.shows(state :: any))
		end
		local action, airSeconds = Squirrel.launch(events :: any, state.vy)
		if action or kin.mode ~= "air" then
			kin.action, kin.airSeconds = action, airSeconds
		end
		local cf = Units.yawCFrame(visual.yaw or state.yaw, Vector3.new(visual.x, visual.y, visual.z))
			* CFrame.Angles(visual.pitch, 0, -visual.lean)
			* CFrame.new(0, hip, 0)
		local p = cf.Position
		local vel = if snapped or dt <= 0 then Vector3.zero else (p - last) / dt
		last, lastSpeed = p, vel.Magnitude
		return cf, vel
	end)
	return function()
		stopDrive()
		KinematicPose.clear(body)
		if ctx.meter then
			ctx.meter(nil)
		end
		if vision then
			vision.stop() -- the next body, and the menu, see the town as everyone else does
		end
		if trickButton then
			trickButton.stop()
		end
		marker.stop()
	end
end

return Squirrel
