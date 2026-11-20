--!strict
-- Validator round 9 (the round-8 review's findings and invariant E): the fixer's greedy attack cases, each change at 2 to
-- 60 packets a second, the client's clock at 0.8 to 1.2 times real time, and role re-picks (a release and a retake every
-- 1.5 s: two picks, Game.PICK_COOLDOWN 0.75 s each):
--   grace   a client that ignores walls, handed the body beside a closed room (within the streamed radius) or 66 st from
--           it (past it): the held place, the snap target and every release place never inside;
--   long    one long packet through the room's wall after a silence, then clean packets inside: never held inside, and
--           a release lets the body go outside;
--   creep   moves each shorter than a chord (0.05 st) through the wall at 0.3 to 1.4 st/s, re-picked or not (a hole the
--           fixer found: no wall test judged such a move);
--   E       one packet of each doubt (a hair over the speed cap, a long line round a wall's end, a gap too long to judge,
--           a grounded claim with no floor): the held place never moves to it, and moves on with the next clean packet
--           the held place reaches;
--   sink    a grounded claim sinking under the hospital's and the police station's roofs by steps of 0.01 to 0.59 st, then
--           a fall from rest: judged at every rate (needs build/Town.rbxm);
--   meter   a client sprinting on credit, re-picked every 1.5 s: the grant never fuller than the meter left, and still
--           flagged;
--   reseat  a plain squirrel let go on the street over every enclosed run (the drains, the hollows, the ball returns):
--           never re-seated inside one, the scan's cost (needs build/Town.rbxm).
-- About 40 s: `lune run tests/run.luau validator_r9`.
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local MoveValidator = require("@server/Movement/MoveValidator")
local MovementService = require("@server/Movement/MovementService")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local TestWorld = require("@tests/cheat/TestWorld")
local BakedWorld = require("@tests/lib/BakedWorld")
local RailWorld = require("@shared/Movement/RailWorld")
local RouteAdapter = require("@server/AI/RouteAdapter")
local Squirrel = require("@server/Actors/Brains/Squirrel")
local Height = require("@shared/World/Height")
local Data = require("@shared/Data")
local fs = require("@lune/fs")

type State = SquirrelMotor.State
type V3 = { x: number, y: number, z: number }

local P = SquirrelMotor.params
local RATES = { 2, 5, 10, 20, 30, 60 }
local CLOCKS = { 0.8, 1, 1.2 }

-- a closed room 20 x 20 st (walls 1 st thick, 14 high), x 0..20, z -10..10, no door
local ROOM: { TestWorld.Box } = {
	{ minX = -1, maxX = 0, minZ = -11, maxZ = 11, top = 14 },
	{ minX = 20, maxX = 21, minZ = -11, maxZ = 11, top = 14 },
	{ minX = -1, maxX = 21, minZ = -11, maxZ = -10, top = 14 },
	{ minX = -1, maxX = 21, minZ = 10, maxZ = 11, top = 14 },
}

local function inside(x: number, z: number): boolean
	return x > 0 and x < 20 and z > -10 and z < 10
end

local function worldOf(boxes: { TestWorld.Box }): (any, any)
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

-- A held squirrel driven straight at the service: `rate` packets a second, its clock `k` times real time, its moves
-- by its own clock (a greedy client: it goes on from wherever the server puts it), its root where it is (the watch at
-- each packet), and the picks: release (Possession: the body let go at the held place, the AI's from then on) and
-- possess (the gate where the AI holds it).
type Driver = {
	ms: any,
	now: number,
	clock: number,
	seq: number,
	x: number,
	y: number,
	z: number,
	epoch: number,
	place: V3,
	releases: { V3 },
	packet: (self: Driver, st: State?, quiet: boolean?) -> any,
	tick: (self: Driver, vx: number, vz: number, rate: number, k: number) -> any,
	possess: (self: Driver) -> (),
	release: (self: Driver) -> V3?,
	held: (self: Driver) -> V3?,
}

local function driver(vworld: any, start: V3): Driver
	local d: any = {
		now = 100,
		clock = 5,
		seq = 0,
		x = start.x,
		y = start.y,
		z = start.z,
		epoch = 0,
		place = table.clone(start),
		releases = {},
	}
	d.ms = MovementService.new({
		validator = MoveValidator.new(vworld),
		enforce = true,
		poseOf = function(_actor: any): (number, number, number)
			return d.place.x, d.place.y, d.place.z
		end,
		engine = {
			correct = function(_id: any, msg: any)
				d.x, d.y, d.z, d.epoch = msg.x, msg.y, msg.z, msg.epoch
			end,
			pin = function(_id: any, _on: boolean): boolean
				return true
			end,
			hold = function(_id: any, x: number, y: number, z: number, _s: number)
				d.x, d.y, d.z = x, y, z
			end,
		},
	})
	function d.packet(self: Driver, st: State?, _quiet: boolean?): any
		local s = st or SquirrelMotor.new(self.x, self.y, self.z)
		if st == nil then
			s.grounded = true
		end
		s.clock = self.clock
		self.seq += 1
		local _, e, dec = SquirrelWire.decode(SquirrelWire.encode(self.seq, self.epoch, SquirrelMotor.serialize(s)))
		local v = self.ms:packet("a", "squirrel", { seq = self.seq, epoch = e, snapshot = dec }, self.now)
		self.ms:watch("a", self.x, self.y, self.z, self.now)
		return v
	end
	-- one packet's time: the client moves (vx, vz) by its own clock and sends where it is
	function d.tick(self: Driver, vx: number, vz: number, rate: number, k: number): any
		self.now += 1 / rate
		self.clock += k / rate
		self.x += vx * k / rate
		self.z += vz * k / rate
		local s = SquirrelMotor.new(self.x, self.y, self.z)
		s.grounded, s.vx, s.vz = true, vx, vz
		return self:packet(s)
	end
	function d.possess(self: Driver)
		self.ms:onHandoff({ id = "a", species = "squirrel" }, nil, "possess")
		self.epoch = self.ms:epochOf("a")
		self.x, self.y, self.z = self.place.x, self.place.y, self.place.z
	end
	function d.release(self: Driver): V3?
		local x, y, z = self.ms:heldPlace("a")
		local at: V3? = nil
		if x and y and z then
			at = { x = x, y = y, z = z }
			self.place = at :: V3
			table.insert(self.releases, at :: V3)
		end
		self.ms:onHandoff({ id = "a", species = "squirrel" }, nil, "release")
		return at
	end
	function d.held(self: Driver): V3?
		local x, y, z = self.ms:heldPlace("a")
		return if x and y and z then { x = x, y = y, z = z } else nil
	end
	return d :: Driver
end

local function reasons(ms: any): string
	local list = {}
	for k, v in ms:stats().reasons do
		table.insert(list, `{k}={v}`)
	end
	table.sort(list)
	return table.concat(list, " ")
end

return function(t)
	-- grace ------------------------------------------------------------------------------------------------------------
	t.test(
		"grace: a client that ignores walls, handed the body by a closed room or 66 st from it, re-picked",
		function()
			local _, vworld = worldOf(ROOM)
			local g = TestWorld.STAND_HEIGHT
			local rows = {}
			local bad = 0
			local cases = 0
			for _, mode in { "near", "far", "far, no re-pick" } do
				local far = mode ~= "near"
				for _, rate in RATES do
					for _, k in CLOCKS do
						cases += 1
						local d = driver(vworld, { x = if far then -66 else -3, y = g, z = 0 })
						d:possess()
						local inHeld, inRel = 0, 0
						local speed = if far then P.sprint else P.walk
						local t0 = d.now
						local pickAt = if mode == "far, no re-pick" then math.huge else t0 + 1.5
						while d.now - t0 < 9 do
							if d.now >= pickAt then
								-- (a role re-pick: released, 0.75 s with another role, taken back)
								local rel = d:release()
								if rel and inside(rel.x, rel.z) then
									inRel += 1
								end
								d.now += 0.75
								d.clock += 0.75 * k
								d:possess()
								pickAt = d.now + 1.5
							end
							d:tick(speed, 0, rate, k)
							local h = d:held()
							if h and inside(h.x, h.z) then
								inHeld += 1
							end
						end
						if inHeld + inRel > 0 then
							bad += 1
						end
						if k == 1 and (rate == 2 or rate == 20 or rate == 60) then
							table.insert(
								rows,
								string.format(
									"%s %d/s: held inside %d ticks, released inside %d; %s",
									mode,
									rate,
									inHeld,
									inRel,
									reasons(d.ms)
								)
							)
						end
					end
				end
			end
			for _, r in rows do
				print(`      {r}`)
			end
			print(`      {cases - bad} of {cases} cases never held nor released inside`)
			t.eq(bad, 0, "the held place and every release place stay outside the closed room")
		end
	)

	-- long -------------------------------------------------------------------------------------------------------------
	t.test("long: one long packet through a wall after a silence, then clean packets inside, then a release", function()
		local _, vworld = worldOf(ROOM)
		local g = TestWorld.STAND_HEIGHT
		local bad, cases = 0, 0
		local rows = {}
		for _, gap in { 0.25, 0.35, 0.5, 0.7 } do
			for _, rate in RATES do
				for _, k in CLOCKS do
					cases += 1
					local d = driver(vworld, { x = -2.5, y = g, z = 0 })
					d:possess()
					for _ = 1, rate do
						d:tick(0, 0, rate, k)
					end
					-- (the silence, then one packet 6 st on, inside)
					d.now += gap
					d.clock += gap * k
					d.x += 6
					d:tick(0, 0, rate, k)
					local after = d:held()
					local inHeld = 0
					for _ = 1, 2 * rate do
						d:tick(2, 0, rate, k)
						local h = d:held()
						if h and inside(h.x, h.z) then
							inHeld += 1
						end
					end
					local rel = d:release()
					local inRel = rel ~= nil and inside(rel.x, rel.z)
					if inHeld > 0 or inRel or (after and inside(after.x, after.z)) then
						bad += 1
						table.insert(
							rows,
							string.format(
								"INSIDE gap %.2f s, %d/s, clock x%.1f: held inside %d ticks, released inside %s; %s",
								gap,
								rate,
								k,
								inHeld,
								tostring(inRel),
								reasons(d.ms)
							)
						)
					end
					if k == 1 and rate == 20 then
						table.insert(
							rows,
							string.format(
								"gap %.2f s at 20/s: held inside %d ticks, released at %.1f, %.1f; %s",
								gap,
								inHeld,
								if rel then rel.x else 0 / 0,
								if rel then rel.z else 0 / 0,
								reasons(d.ms)
							)
						)
					end
				end
			end
		end
		for _, r in rows do
			print(`      {r}`)
		end
		print(`      {cases - bad} of {cases} cases never held nor released inside`)
		t.eq(bad, 0, "never held inside, never let go inside")
	end)

	-- creep ------------------------------------------------------------------------------------------------------------
	-- (found by the fixer: a move shorter than a chord, 0.05 st, is judged by no wall test, so a creep of under 0.05 st a
	-- packet walked through any wall, and a snap or a retake let the next packet step in again: MoveValidator's creep)
	t.test("creep: moves each shorter than a chord through a wall, with and without re-picks", function()
		local _, vworld = worldOf(ROOM)
		local g = TestWorld.STAND_HEIGHT
		local bad, cases = 0, 0
		local rows = {}
		for _, repick in { false, true } do
			for _, rate in { 20, 30, 60 } do
				for _, speed in { 0.3, 0.9, 1.4 } do
					for _, k in CLOCKS do
						cases += 1
						local d = driver(vworld, { x = -2.2, y = g, z = 0 })
						d:possess()
						local inHeld, inRel = 0, 0
						local t0 = d.now
						local pickAt = if repick then t0 + 1.5 else math.huge
						while d.now - t0 < 20 do
							if d.now >= pickAt then
								local rel = d:release()
								if rel and inside(rel.x, rel.z) then
									inRel += 1
								end
								d.now += 0.75
								d.clock += 0.75 * k
								d:possess()
								pickAt = d.now + 1.5
							end
							d:tick(speed, 0, rate, k)
							local h = d:held()
							-- (more than a chord into the wall, or past it: a move shorter than a chord is no line to judge)
							if h and h.x > -1 + ValidatorWorld.C.MIN_CHORD then
								inHeld += 1
							end
						end
						if inHeld + inRel > 0 then
							bad += 1
						end
						if k == 1 and speed == 0.9 then
							table.insert(
								rows,
								string.format(
									"%s %d/s at %.1f st/s: held a chord into the wall or past it %d ticks; %s",
									if repick then "re-picked" else "plain",
									rate,
									speed,
									inHeld,
									reasons(d.ms)
								)
							)
						end
					end
				end
			end
		end
		for _, r in rows do
			print(`      {r}`)
		end
		print(`      {cases - bad} of {cases} cases never held more than a chord into the wall, nor past it`)
		t.eq(bad, 0, "a creep never takes the held place into a wall")
	end)

	-- E ----------------------------------------------------------------------------------------------------------------
	t.test("E: a packet of each doubt never becomes the held place; the next clean one it reaches does", function()
		-- a wall 2 st thick from z 0 to 6 at x 10..12 (its south end open: a way round it)
		local WALL: { TestWorld.Box } = { { minX = 10, maxX = 12, minZ = 0, maxZ = 6, top = 14 } }
		local _, vworld = worldOf(WALL)
		local g = TestWorld.STAND_HEIGHT
		local cap = SquirrelMotor.groundCap(false) * SquirrelMotor.envelopeParams.speedTol
		local rows = {}
		local moved, advanced = 0, 0
		local kinds = {
			-- a hair over the speed cap (a violation too small to flag)
			speed = function(d: Driver): State
				d.now += 0.05
				d.clock += 0.05
				d.x += 0.5
				local s = SquirrelMotor.new(d.x, d.y, d.z)
				s.grounded, s.vx = true, cap * 1.001
				return s
			end,
			-- one long packet round the wall's open end (its straight line through the wall: a third, a corner)
			corner = function(d: Driver): State
				d.now += 0.35
				d.clock += 0.35
				d.x, d.z = 14, 1
				local s = SquirrelMotor.new(d.x, d.y, d.z)
				s.grounded = true
				return s
			end,
			-- a gap too long to judge move by move, clean as a whole
			resync = function(d: Driver): State
				d.now += 0.7
				d.clock += 0.7
				d.x -= 4
				local s = SquirrelMotor.new(d.x, d.y, d.z)
				s.grounded = true
				return s
			end,
			-- grounded with no floor under the feet (a whole flag: snapped back to the held place)
			float = function(d: Driver): State
				d.now += 0.05
				d.clock += 0.05
				local s = SquirrelMotor.new(d.x, d.y + 1, d.z)
				s.grounded = true
				return s
			end,
		}
		for _, name in { "speed", "corner", "resync", "float" } do
			local d = driver(vworld, { x = 8, y = g, z = 5 })
			d:possess()
			for _ = 1, 20 do
				d:tick(0, 0, 20, 1)
			end
			local before = d:held() :: V3
			local v = d:packet(kinds[name](d))
			local mid = d:held() :: V3
			local still = math.abs(mid.x - before.x) < 1e-6 and math.abs(mid.z - before.z) < 1e-6
			if not still then
				moved += 1
			end
			-- then clean packets on
			local after = mid
			for _ = 1, 10 do
				d:tick(1, 0, 20, 1)
				after = d:held() :: V3
			end
			local on = math.abs(after.x - mid.x) > 0.1
			if on then
				advanced += 1
			end
			local codes = {}
			for _, x in v.violations do
				table.insert(codes, x.code .. "=" .. string.format("%.3g", x.severity))
			end
			table.insert(
				rows,
				string.format(
					"%s (%s%s): held %s; after 10 clean packets %s (%.1f, %.1f); %s",
					name,
					table.concat(codes, " "),
					if v.resync then " resync" else "",
					if still then "kept" else "MOVED",
					if on then "on" else "kept",
					after.x,
					after.z,
					reasons(d.ms)
				)
			)
		end
		for _, r in rows do
			print(`      {r}`)
		end
		t.eq(moved, 0, "no doubtful packet becomes the held place")
		t.eq(advanced, 4, "the next clean packets the held place reaches are held")
	end)

	-- sink -------------------------------------------------------------------------------------------------------------
	t.test("sink: grounded claims sinking under two roofs by 0.01 to 0.59 st a packet, then a fall: judged", function()
		if not fs.isFile("build/Town.rbxm") then
			t.truthy(false, "build/Town.rbxm (lune run tools/bake/main.luau)")
			return
		end
		Height.configure(Data.default():module("TerrainExtensions"))
		local town = BakedWorld.load("build/Town.rbxm")
		local w = town:motorWorld(Data.default())
		local wall, down, cover = BakedWorld.validatorRays(town)
		local vworld = ValidatorWorld.build(w, { wall = wall, down = down, cover = cover })
		local cases, judged = 0, 0
		local deepest = 0
		for _, path in { "Lots.hospital_main.Roof", "Lots.west_police_station.Roof" } do
			local roof: any = nil
			for _, p in town.parts do
				if p.path == path then
					roof = p
				end
			end
			if roof == nil then
				continue
			end
			local cx, cz = (roof.x0 + roof.x1) / 2, (roof.z0 + roof.z1) / 2
			local top = town.groundAt(cx, cz, roof.y1 + 1)
			local under = town.groundAt(cx, cz, roof.y0 - 1.6)
			for _, rate in { 2, 10, 30, 60 } do
				for _, step in { 0.01, 0.049, 0.3, 0.59 } do
					cases += 1
					local v = MoveValidator.new(vworld)
					local s0 = SquirrelMotor.new(cx, top, cz)
					s0.grounded, s0.clock = true, 1
					v:accept("a", { seq = 0, snapshot = SquirrelMotor.serialize(s0) }, 1)
					local seq, now, n = 0, 1, 0
					-- (the deepest a grounded claim got under the top with no violation yet)
					local clean = top
					local function send(st: State)
						seq += 1
						now += 1 / rate
						st.clock = now
						local found =
							v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(st) }, now).violations
						n += #found
						if n == 0 and st.grounded then
							clean = math.min(clean, st.y)
						end
					end
					for _ = 1, rate do
						local st = SquirrelMotor.new(cx, top, cz)
						st.grounded = true
						send(st)
					end
					local y = top
					while y - step > top - 1.49 do
						y -= step
						local st = SquirrelMotor.new(cx, y, cz)
						st.grounded = true
						send(st)
					end
					local t0 = now
					while true do
						local tt = now + 1 / rate - t0
						local fy = y - 0.5 * P.gravity * tt * tt
						local st = SquirrelMotor.new(cx, math.max(fy, under), cz)
						if fy <= under then
							st.grounded = true
							send(st)
							break
						end
						st.grounded, st.vy = false, -P.gravity * tt
						send(st)
					end
					if n > 0 then
						judged += 1
					end
					deepest = math.max(deepest, top - clean)
				end
			end
		end
		Height.configure(nil)
		print(
			`      {judged} of {cases} sinks judged; the deepest a grounded claim got under a roof's top unjudged: {string.format(
				"%.2f",
				deepest
			)} st (ValidatorWorld.C.SLAB_ON {ValidatorWorld.C.SLAB_ON})`
		)
		t.eq(judged, cases, "every sink judged")
		t.truthy(deepest <= ValidatorWorld.C.SLAB_ON + 1e-6, "never deeper than SLAB_ON under a top unjudged")
	end)

	-- meter ------------------------------------------------------------------------------------------------------------
	t.test("meter: a client sprinting on credit, re-picked every 1.5 s, gains no meter by it", function()
		local _, vworld = worldOf({})
		local g = TestWorld.STAND_HEIGHT
		local rows = {}
		local fuller = 0
		local flagged: { [string]: number } = {}
		for _, repick in { false, true } do
			local d = driver(vworld, { x = -400, y = g, z = 40 })
			d:possess()
			local t0 = d.now
			local pickAt = t0 + 1.5
			local runs = 0
			while d.now - t0 < 20 do
				if repick and d.now >= pickAt then
					local validator = d.ms.deps.validator
					local left = validator._marks["a"]
					local leftMeter, leftAt = if left then left.stamina else 1, if left then left.staminaAt else d.now
					d:release()
					d.now += 0.75
					d.clock += 0.75
					d:possess()
					local granted = d.ms:meterOf("a", d.now)
					local most = math.min(1, math.max(0, leftMeter + (d.now - leftAt) / P.sprintRefill))
					if granted > most + 1e-6 then
						fuller += 1
					end
					runs += 1
					pickAt = d.now + 1.5
				end
				d:tick(P.sprint, 0, 20, 1)
			end
			local st = d.ms:stats().reasons
			flagged[if repick then "repick" else "plain"] = st.stamina or 0
			table.insert(
				rows,
				`{if repick then `re-picked {runs} times` else "never re-picked"}: stamina snaps {st.stamina or 0}; {reasons(
					d.ms
				)}`
			)
		end
		for _, r in rows do
			print(`      {r}`)
		end
		t.eq(fuller, 0, "a grant is never fuller than the meter left, refilled since")
		t.truthy(flagged.repick > 0, "sprinting on credit is still flagged when re-picked")
	end)

	-- reseat -----------------------------------------------------------------------------------------------------------
	t.test(
		"reseat: a body let go on the street over any enclosed run is never put inside it; the scan's cost",
		function()
			if not fs.isFile("build/Town.rbxm") then
				t.truthy(false, "build/Town.rbxm (lune run tools/bake/main.luau)")
				return
			end
			Height.configure(Data.default():module("TerrainExtensions"))
			local town = BakedWorld.load("build/Town.rbxm")
			local wall, _down, cover = BakedWorld.validatorRays(town)
			local rail = RailWorld.get(Data.default(), Height.at)
			local routes = RouteAdapter.new(rail)
			local reach = ValidatorWorld.railReach(wall, cover)
			local spots, intoEnclosed, unreached = 0, 0, 0
			local scanMs, raysMs = 0, 0
			for _, r in rail.registry:all() do
				if (r :: any).enclosure == nil then
					continue
				end
				local pts = rail.registry:samples(r)
				for i = 1, #pts, 8 do
					local p = pts[i]
					local gy = town.groundAt(p.x, p.z, p.y + 40)
					if gy < p.y + 1 then
						continue -- (nothing over it: an open mouth)
					end
					spots += 1
					local c0 = os.clock()
					Squirrel.reseat(routes, p.x, gy, p.z, nil)
					scanMs += (os.clock() - c0) * 1000
					c0 = os.clock()
					local got, s = Squirrel.reseat(routes, p.x, gy, p.z, reach)
					raysMs += (os.clock() - c0) * 1000
					if got then
						if routes.enclosed(got.id) then
							intoEnclosed += 1
						else
							local q = rail.registry:pointAt(rail.registry:get(got.id) :: any, s / got.length)
							if not reach(p.x, gy, p.z, q.x, q.y, q.z) then
								unreached += 1
							end
						end
					end
				end
			end
			Height.configure(nil)
			print(
				string.format(
					"      %d spots over enclosed runs: %d re-seated inside one, %d on a rail the rays do not reach (the fallback); the index scan %.3f ms a release, with the rays %.3f ms (Lune)",
					spots,
					intoEnclosed,
					unreached,
					scanMs / math.max(spots, 1),
					raysMs / math.max(spots, 1)
				)
			)
			t.truthy(spots > 100, "spots tried")
			t.eq(intoEnclosed, 0, "never into an enclosed run")
			t.truthy(scanMs / math.max(spots, 1) < 0.1, "the index scan under 0.1 ms a release")
		end
	)
end
