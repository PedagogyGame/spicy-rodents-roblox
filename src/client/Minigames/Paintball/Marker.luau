--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Paintball.Marker
-- The marker in view (checklist PB-1, PB-2, PB-9; "generic and even silly-looking, but it must shoot
-- right"): a toy paintball marker hung off the camera at the lower right, four local parts with a fat
-- hopper in your team's colour. It never decides anything: it shows what SeatCore holds, so that the
-- rhythm of the five shots is readable out of the corner of the eye.
--   at rest     to the right of and below the eye, its barrel toed in onto the crosshair's line
--   a turn      it trails the view a little and catches up (Tuning.swayRate, swayMax)
--   walking     it bobs with the distance walked, harder at a sprint
--   sprinting   it tips down and sinks: the picture of "cannot fire". It comes back up over
--               Body.SPRINT_FIRE_DELAY, the very time the seat waits, so "up" means "may fire"
--   a shot      it jumps back and up and comes home; the VIEW never kicks
--   reloading   it tips over and the hopper rattles through the reload, and rights itself as the
--               magazine fills
--   protected   it is see-through, as every protected player is drawn: it cannot fire yet
--   out         it is put away
-- It only READS the camera's CFrame (its parts are placed from it every frame) and tells Self where
-- its muzzle is, which is where your own ball is drawn leaving from.
-- Interface: new(seat, self, tuning?) -> Marker { step(dt), stop(), model }; pose(seat, now, state,
--   tuning) is the pure part (the marker's offset from the camera as six numbers), for a spec

local Import = require("../../Import")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local SeatCore = require("./SeatCore")
local SelfPort = require("./Self")
local Tuning = require("./Tuning")

export type Marker = {
	model: Instance,
	down: number, -- 0 up .. 1 fully down, as drawn
	step: (self: Marker, dt: number) -> (),
	stop: (self: Marker) -> (),
}

local Marker = {}

-- How far the marker is lowered for the sprint (0..1), how far it is tipped over for the reload (0..1,
-- with the rattle added), and the shot's kick (0..1), from the seat as it stands at `now`. Pure.
function Marker.pose(seat: SeatCore.Seat, now: number, tuning: typeof(Tuning.T)): (number, number, number, number)
	local down = if seat.out
		then 1
		elseif seat.k > 0 then math.min(1, seat.k * tuning.markerDropGain)
		else 1 - seat:markerUp(now)
	local tip, rattle = 0, 0
	local r = seat:reloading(now)
	if r ~= nil then
		-- over in the first sixth, back in the last
		tip = math.min(1, r * 6, (1 - r) * 6)
		rattle = math.sin(r * tuning.reloadShakes * 2 * math.pi) * tip
	end
	local kick = math.exp(-tuning.kickRecover * math.max(0, now - seat.firedAt))
	return down, tip, rattle, kick
end

function Marker.new(seat: SeatCore.Seat, port: SelfPort.Self, tuning: typeof(Tuning.T)?): Marker
	local tune = tuning or Tuning
	local camera = workspace.CurrentCamera
	local model = Instance.new("Model")
	model.Name = "PaintballMarker"

	local function piece(name: string, size: Vector3, rgb: { number }): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Size = size
		p.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
		p.Parent = model
		return p
	end
	local body = piece("Body", Vector3.new(0.3, 0.42, 1.0), { 60, 190, 90 })
	local barrel = piece("Barrel", Vector3.new(0.16, 0.16, tune.markerLength - 0.5), { 40, 42, 52 })
	local grip = piece("Grip", Vector3.new(0.22, 0.55, 0.26), { 40, 42, 52 })
	local hopper = piece("Hopper", Vector3.new(0.62, 0.62, 0.62), { 255, 255, 255 })
	hopper.Shape = Enum.PartType.Ball
	model.Parent = camera

	local swayYaw, swayPitch = 0, 0
	local lastLook: Vector3? = nil
	local lastX, lastZ = seat.x, seat.z
	local phase = 0
	local team = -1
	local ghost = false

	local marker = { model = model, down = 0 } :: Marker

	function marker.step(self: Marker, dt: number)
		local now = seat.now
		-- tagged out: put away
		local want = if seat.out then nil else camera
		if model.Parent ~= want then
			model.Parent = want
		end
		if team ~= seat.team then
			team = seat.team
			local t = Contract.TEAMS[team]
			local c = if t then t.color else { 255, 255, 255 }
			hopper.Color = Color3.fromRGB(c[1], c[2], c[3])
		end
		-- protected: the ghost of a marker (it cannot fire, and says so)
		local safe = seat:protected(now) ~= nil
		if safe ~= ghost then
			ghost = safe
			for _, p in { body, barrel, grip, hopper } do
				p.Transparency = if safe then tune.markerGhost else 0
			end
		end
		local cf = camera.CFrame
		-- a turn of the view leaves the marker behind for a moment
		local look = cf.LookVector
		local was = lastLook
		lastLook = look
		if was then
			local turned = was:Cross(look)
			swayYaw += turned.Y
			swayPitch += (look.Y - was.Y)
		end
		local ease = math.exp(-tune.swayRate * dt)
		swayYaw = math.clamp(swayYaw * ease, -tune.swayMax, tune.swayMax)
		swayPitch = math.clamp(swayPitch * ease, -tune.swayMax, tune.swayMax)
		-- the bob, by distance walked
		local dx, dz = seat.x - lastX, seat.z - lastZ
		lastX, lastZ = seat.x, seat.z
		local moved = math.sqrt(dx * dx + dz * dz)
		if moved < 6 and not seat.air then
			phase += moved * tune.bobPerStud * 2 * math.pi
		end
		local amp = tune.bobWalk + (tune.bobSprint - tune.bobWalk) * seat.k
		local bobY = math.sin(phase) * amp
		local bobX = math.cos(phase / 2) * amp * 0.5
		local down, tip, rattle, kick = Marker.pose(seat, now, tune)
		-- (the lowering eases both ways: a tap of Shift does not snap it)
		self.down += (down - self.down) * (1 - math.exp(-tune.markerEase * dt))
		local d = self.down
		local toe = math.atan2(tune.markerRight, tune.markerConverge) -- the barrel points at the crosshair's line out there
		local at = cf
			* CFrame.new(
				tune.markerRight + bobX,
				-tune.markerDown + bobY - d * tune.sprintSink - tip * tune.reloadSink,
				-tune.markerForward + kick * tune.kickBack
			)
			* CFrame.Angles(
				-d * tune.sprintTip + kick * tune.kickUp - swayPitch + rattle * tune.reloadShake,
				toe - swayYaw + d * tune.sprintSwing,
				-tip * tune.reloadTip
			)
		body.CFrame = at
		barrel.CFrame = at * CFrame.new(0, 0.06, -(0.5 + (tune.markerLength - 0.5) / 2))
		grip.CFrame = at * CFrame.new(0, -0.42, 0.25) * CFrame.Angles(0.25, 0, 0)
		hopper.CFrame = at * CFrame.new(0, 0.48 + rattle * 0.03, 0.05)
		port.muzzleAt = (at * CFrame.new(0, 0.06, -tune.markerLength)).Position
	end

	function marker.stop(_self: Marker)
		port.muzzleAt = nil
		model:Destroy()
	end

	return marker
end

return Marker
