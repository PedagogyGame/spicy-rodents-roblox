--!strict
-- Adversarial review, round 7 (the validator at w0-foundation 8b6e6ed, invariant C): failing cases.
--   release  giving a body up reads its root (Actors/Possession.releaseNow: actors:poseOf, the model's pivot), which
--            the client writes and the server watches only fifteen times a second; the computer's brain takes the
--            body there, and a retake carries the governor's history to wherever that is (MoveValidator.takeOver /
--            relocate: "the body was put there"). A root written far off between two watches, a swap to another
--            body and the same body taken back: a teleport no rule judges.
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local MoveValidator = require("@server/Movement/MoveValidator")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local TestWorld = require("@tests/cheat/TestWorld")
local LiveRig = require("@tests/lib/LiveRig")

type State = SquirrelMotor.State

local function worldWith(boxes: { TestWorld.Box }): (any, any)
	local world = TestWorld.build({ boxes = boxes })
	local function wall(ox: number, oy: number, oz: number, dx: number, _dy: number, dz: number): boolean
		return TestWorld.segmentCrossesBox(boxes, ox, oz, ox + dx, oz + dz, oy)
	end
	local function down(_ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
		local lo = oy + dy
		return lo <= 0 and oy >= 0
	end
	return world, ValidatorWorld.build(world, { wall = wall, down = down })
end

local function dist(a: { x: number, y: number, z: number }, b: { x: number, y: number, z: number }): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

return function(t)
	-- release ----------------------------------------------------------------------------------------------------------
	t.test(
		"release: a root written 600 st off between two watches, the body swapped away and taken back: it stays there",
		function()
			local world, vworld = worldWith({})
			local far: { x: number, y: number, z: number }? = nil
			local cheating = false
			local rig: any
			rig = LiveRig.new({
				world = world,
				vworld = vworld,
				link = { latency = 0.05, jitter = 0, loss = 0 },
				seed = 3,
				-- (the client's own root, written where it likes; its motor and its packets stay at home)
				rootCheat = function(p: { x: number, y: number, z: number }, _now: number, _s: State)
					local f = far
					if cheating and f then
						p.x, p.y, p.z = f.x, f.y, f.z
					end
				end,
			})
			local function idle(_now: number): SquirrelMotor.Input
				return SquirrelMotor.idleInput(0)
			end
			rig:possess(SquirrelMotor.new(0, world.groundHeight, 0), idle)
			rig:run(3)
			local start = table.clone(rig.server.root)
			local startAt = rig.t
			local snapsBefore = rig:result().snaps
			far = { x = start.x + 600, y = world.groundHeight, z = start.z }
			cheating = true
			-- a frame in which the server's root reads the client's write (between two watches: Boot/Game.watchSquirrels
			-- runs fifteen times a second; the swap's own yield, Possession.possess's streamAround, ends in any frame)
			local released: { x: number, y: number, z: number }? = nil
			for _ = 1, 400 do
				rig:run(0.002)
				local r = rig.server.root
				if far and math.abs(r.x - (far :: any).x) < 1 then
					released = table.clone(r)
					break
				end
			end
			t.truthy(released ~= nil, "the server's root read the client's write between two watches")
			local rel = released :: { x: number, y: number, z: number }
			-- Possession.releaseNow (a pick of another body: swap): x, y, z = actors:poseOf(actor) (GetPivot, the root),
			-- then brain.resume(x, y, z): the computer takes the body where the root is
			rig:release()
			cheating = false
			-- Game.PICK_COOLDOWN later the same body is picked again (the one Spicy Rodent; for a squirrel, the
			-- lowest-numbered free one, Actors/ActorsRuntime.pickFree): Possession.possessNow, the gate at its pose
			rig:run(0.75)
			rig.server.count -= 1 -- (the same body: rig:possess takes the next number)
			rig:possess(SquirrelMotor.new(rel.x, rel.y, rel.z), idle)
			rig:run(3)
			local r = rig:result()
			local elapsed = rig.t - startAt
			local b = MoveValidator.new(vworld):governorBounds(false)
			local bound = b.vh * elapsed + b.dh
			local moved = dist(start, r.root)
			print(
				string.format(
					"      the root %.0f st from where the server last held it, %.1f s later (the governor's most %.0f); snaps %d (before the cheat %d)",
					moved,
					elapsed,
					bound,
					r.snaps,
					snapsBefore
				)
			)
			t.truthy(
				moved <= bound,
				`a release and a retake moved the body {math.floor(moved)} st in {elapsed} s, the governor's most {bound}`
			)
		end
	)

	-- knock ------------------------------------------------------------------------------------------------------------
	t.test(
		"knock: a root written inside the paintball station between two watches: the server puts the body out on its street",
		function()
			-- Boot/Game's `animals` (the minigames' list of squirrels) reads every body's root, a held one's too; the
			-- paintball service's audience pass (every Clock.AUDIENCE_SECS) puts any animal found inside the station on
			-- the street in front of it (PaintballService: knock -> Boot/Game movedBody -> MovementService.teleported,
			-- "knocked": the governor's history carried there, the jump itself never judged). A bowling lane in play and
			-- a pool shot knock an animal off the same way, from the same list.
			local world, vworld = worldWith({})
			local station = { x = 600, y = world.groundHeight, z = 0 } -- (inside the station's volume)
			local street = { x = 600, y = world.groundHeight, z = 40 } -- (Paintball STREET: in front of the annex)
			local cheating = false
			local rig: any
			rig = LiveRig.new({
				world = world,
				vworld = vworld,
				link = { latency = 0.05, jitter = 0, loss = 0 },
				seed = 5,
				rootCheat = function(p: { x: number, y: number, z: number }, _now: number, _s: State)
					if cheating then
						p.x, p.y, p.z = station.x, station.y, station.z
					end
				end,
			})
			rig:possess(SquirrelMotor.new(0, world.groundHeight, 0), function(_now: number): SquirrelMotor.Input
				return SquirrelMotor.idleInput(0)
			end)
			rig:run(3)
			local start = table.clone(rig.server.root)
			local startAt = rig.t
			cheating = true
			local knocked = false
			for _ = 1, 400 do
				rig:run(0.002)
				local r = rig.server.root
				if math.abs(r.x - station.x) < 1 and math.abs(r.z - station.z) < 1 then
					-- (the pass finds an animal inside: knock(id, street) -> PivotTo, movedBody)
					cheating = false
					rig:teleport(street.x, street.y, street.z, "knocked")
					knocked = true
					break
				end
			end
			t.truthy(knocked, "the pass read the client's root inside the station")
			rig:run(3)
			local r = rig:result()
			local elapsed = rig.t - startAt
			local b = MoveValidator.new(vworld):governorBounds(false)
			local bound = b.vh * elapsed + b.dh
			local moved = dist(start, r.root)
			print(
				string.format(
					"      the root %.0f st from where the server last held it, %.1f s later (the governor's most %.0f); snaps %d",
					moved,
					elapsed,
					bound,
					r.snaps
				)
			)
			t.truthy(moved <= bound, `a knock moved the body {math.floor(moved)} st in {elapsed} s, the most {bound}`)
		end
	)
end
