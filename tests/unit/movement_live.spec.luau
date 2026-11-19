--!strict
-- The squirrel validator in the live game (spike S3; Boot/Game.movement): Boot/Game builds its movement service with a
-- MoveValidator over the town's own rails (Shared/Data: the harvest, the alley's ball returns and roof route, the
-- storm drains, the hollow trees) and the baked town's walls and floors (Server/Movement/ValidatorWorld); the wire the
-- client's packets come up on (Shared/Movement/SquirrelWire, Net "Squirrel.State") carries every field it judges.
local fs = require("@lune/fs")
local Data = require("@shared/Data")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local Schemas = require("@shared/Net/Schemas")
local Game = require("@server/Boot/Game")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")

local function never(): boolean
	return false
end

return function(t)
	t.test("Boot/Game.movement: the service has a validator over the town's rails, walls and floors", function()
		local m = Game.movement({
			data = Data.default(),
			wall = function(_ox, _oy, _oz, _dx, _dy, _dz)
				return false
			end,
			down = function(_ox, _oy, _oz, _dx, _dy, _dz)
				return true
			end,
		})
		local v = m.deps.validator
		t.truthy(v, "a validator")
		local w = v.world
		t.truthy(w.crosses, "walls")
		t.truthy(w.floorBelow, "floors")
		-- the enclosed runs are on it: a storm drain, a hollow tree, the alley's routes
		t.truthy(w.registry:get(9301), "drain 9301")
		t.truthy(w.registry:get(9411), "hollow 9411")
		local alley = 0
		for _, r in w.registry:all() do
			if r.enclosure and r.id < 9301 then
				alley += 1
			end
		end
		t.truthy(alley > 0, "the alley's enclosed routes")
		-- a squirrel packet goes through it: a 30-stud jump in one tick is a violation
		local s = SquirrelMotor.new(0, 0.45, 0)
		s.clock = 1
		m:packet("squirrel_1", "squirrel", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 10)
		s.clock += 1 / 20
		s.x += 30
		local verdict = m:packet("squirrel_1", "squirrel", { seq = 2, snapshot = SquirrelMotor.serialize(s) }, 10.05)
		t.eq(verdict.ok, false)
	end)

	t.test("Boot/Game.start builds its movement with Game.movement (the validator), never without", function()
		local src = fs.readFile("src/server/Boot/Game.luau")
		local _, calls = string.gsub(src, "MovementService%.new%(", "")
		t.eq(calls, 1, "MovementService.new once, inside Game.movement")
		t.truthy(string.find(src, "return MovementService.new({ swept = deps.swept, validator = validator", 1, true))
		t.truthy(string.find(src, "local movement = Game.movement({", 1, true))
		-- the clock check knows each driver's round trip (a latency that drops is no time hack)
		t.truthy(string.find(src, "movement.deps.validator.pingOf = function", 1, true), "pingOf wired")
		t.truthy(string.find(src, ":GetNetworkPing()", 1, true), "from the engine's own measure")
		-- the root is watched fifteen times a second (walls between samples stay inside one chord)
		t.truthy(string.find(src, "if watchAcc < 1 / 15 then", 1, true), "watched at 15 Hz")
		-- a new squirrel body is the server's until its driver's first packet passes the gate
		t.truthy(string.find(src, "movement.deps.engine = BodyPin.engine({", 1, true), "engine.pin wired (BodyPin)")
		t.truthy(
			string.find(src, "return movement:isPinned(actorId)", 1, true),
			"a hold never gives back a pinned body"
		)
		-- a body a game moves itself (the paintball arena) is told to the validator
		t.truthy(
			string.find(src, "moved = function(body: any, why: string)\n\t\t\t\tmovedBody(body, why)", 1, true),
			"moved wired"
		)
		local pb = fs.readFile("src/server/Minigames/Paintball/PaintballService.luau")
		t.truthy(string.find(pb, 'moved(body, "paintball")', 1, true), "the arena tells every move")
	end)

	t.test("SquirrelWire: every field the validator reads crosses the wire", function()
		local s = SquirrelMotor.new(123.25, 4.5, -987.125)
		s.vx, s.vy, s.vz = 3.5, -2.25, 1.5
		s.routeId, s.railT, s.railDir = 812, 0.3125, -1
		s.grounded = false
		s.clock = 1234.5678
		s.stamina, s.winded = 0.5, true
		s.bridge = { fx = 1, fy = 2, fz = 3, tx = 4, ty = 5, tz = 6, elapsed = 0.125, duration = 0.25 }
		local b = SquirrelWire.encode(77, 3, SquirrelMotor.serialize(s))
		t.eq(buffer.len(b), Schemas.SquirrelState.size)
		t.eq(Schemas.SquirrelState.size, 167)
		local seq, epoch, snap = SquirrelWire.decode(b)
		t.eq(seq, 77)
		t.eq(epoch, 3)
		local back = SquirrelMotor.deserialize(snap)
		t.eq(back.x, 123.25)
		t.eq(back.z, -987.125)
		t.eq(back.clock, 1234.5678)
		t.eq(back.routeId, 812)
		t.eq(back.railT, 0.3125)
		t.eq(back.railDir, -1)
		t.eq(back.grounded, false)
		t.eq(back.winded, true)
		t.eq(back.pendingFork, nil)
		t.truthy(back.bridge)
		t.eq((back.bridge :: any).duration, 0.25)
		-- and the remote is declared with its layout
		local d = Schemas.REMOTES["Squirrel.State"]
		t.eq(d.dir, "c2s")
		t.eq(d.layout, Schemas.SquirrelState)
		t.eq(Schemas.REMOTES.Correction.dir, "s2c")
	end)

	t.test(
		"ValidatorWorld.crosses: a wall stops all six rays; a fence leapt over, a corner, a long gap do not",
		function()
			-- a wall along x = 0 from z = -10 to 10, 6 studs tall; a fence along x = 5, 1.4 tall
			local function wallAt(xw: number, top: number): ValidatorWorld.Ray
				return function(ox, oy, oz, dx, _dy, dz)
					if oy > top or oz + dz < -10 or oz > 10 then
						return false
					end
					return (ox - xw) * (ox + dx - xw) <= 0 and dx ~= 0
				end
			end
			local crossWall = ValidatorWorld.crosses(wallAt(0, 6))
			t.eq(crossWall(-1, 0, 1, 0, 0, 0, 0), true, "through the wall")
			t.eq(crossWall(-1, 0, -0.2, 0, 0, 0, 0), false, "short of it")
			t.eq(crossWall(-3, 0, 3, 0, 0, 0, 0), false, "longer than MAX_CHORD: not judged")
			t.eq(crossWall(-1, 9.9, 1, 9.9, 0, 0, 0), false, "at the wall's end a side ray goes round")
			local crossFence = ValidatorWorld.crosses(wallAt(5, 1.4))
			t.eq(crossFence(4, 0, 6, 0, 0, 0, 0.5), false, "a leap clears a fence")
			local _ = never
		end
	)
end
