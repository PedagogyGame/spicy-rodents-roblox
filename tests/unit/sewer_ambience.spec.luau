--!strict
-- The storm drains felt from inside, on the client (Client/World/SewerAmbience; lane S3 of the sewer plan). Here, the
-- pure part against the real motor on the pipes' stand-in (tests/lib/SewerStandIn on tests/lib/BakedWorld):
--   the words on a grate tell the truth: "E: down the drain" exactly where E takes the body down (every mouth, a
--   ring of places and facings: any facing on the grate; anywhere on its opening, and the server agrees), and there W
--   never goes down (a hatch mouth, Enclosure rule 1); a body's width off it, nothing; near one, how to get in; never
--   a compass word (the game's map has east at -x)
--   drain 1's crossing: A / D announced running at it along the arm (the motor keeps a pick made anywhere on it), the
--   arm picked named; which arm was taken
--   "W: climb out" shows in the top of a shaft on the way out of every run, never on the way down or in a passage
--   the controller's refusals inside a drain (Space, Q, a click, E: the motor's hints) read as a drain's
--   the place names, the cue points inside their pipes, every cue named in docs/AUDIO_BUDGET.md with its library sound
-- The engine part (the look, the lamps, the reverb, the words on screen and the cues over whole runs, Lighting never
-- touched) is in tests/isolated/sewer_ambience.luau, run in its own Lune process (tests/lib/Isolated says why); each
-- of its cases is reported here as its own test.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Data = require("@shared/Data")
local Enclosure = require("@shared/Routes/Enclosure")
local Height = require("@shared/World/Height")
local LaneMath = require("@shared/Traffic/LaneMath")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SewerLayout = require("@shared/World/SewerLayout")
local SewerAmbience = require("@client/World/SewerAmbience")
local SquirrelController = require("@client/Controllers/Squirrel")
local BakedWorld = require("@tests/lib/BakedWorld")
local Isolated = require("@tests/lib/Isolated")
local SewerStandIn = require("@tests/lib/SewerStandIn")
local TrafficService = require("@server/Traffic/TrafficService")

type Mouth = SewerLayout.Mouth
type State = SquirrelMotor.State

local RUNS = {
	{ "P1.NW", "P1.SE" },
	{ "P1.NE", "P1.SW" },
	{ "P2.W", "P2.E" },
	{ "P2.E", "P2.W" },
	{ "P3.S", "P3.N" },
	{ "P3.N", "P3.S" },
}

return function(t)
	local data = Data.default()
	local layout = SewerLayout.default() :: SewerLayout.Layout
	local baked = SewerStandIn.world(layout)
	local w = baked:motorWorld(data)

	local function mouth(id: string): Mouth
		return layout.mouth(id) :: Mouth
	end
	local function viewOf(s: State, vy: number?, canGo: boolean?): SewerAmbience.View
		return {
			x = s.x,
			y = s.y,
			z = s.z,
			vy = vy or 0,
			canGo = canGo ~= false,
			space = layout.contains(s.x, s.y, s.z),
		}
	end

	local P = SewerAmbience.PROMPT
	-- W held with the view toward (dx, dz) for up to `frames`: did the body go down this mouth's pipe?
	local function walksIn(x: number, z: number, yaw: number, dx: number, dz: number, m: Mouth, frames: number): boolean
		local s = SquirrelMotor.new(x, baked.groundAt(x, z, m.y + 3), z)
		s.yaw = yaw
		local tr = BakedWorld.drive(w, s, frames, function(): SquirrelMotor.Input
			return BakedWorld.keys(BakedWorld.cameraYawToward(dx, dz), { fw = 1 })
		end, {
			stop = function(st: State): boolean
				return st.routeId ~= nil
			end,
		})
		local _ = tr
		return s.routeId ~= nil and layout.spaceOf(s.routeId) == m.space
	end

	t.test(
		"the words on a grate tell the truth: E where E goes down (any facing); walking onto it never does",
		function()
			local said, went = 0, 0
			for _, m in layout.mouths do
				for _, r in { 0, 0.5, 1.0, 1.4, 1.7, 2.5 } do
					for k = 0, 7 do
						local a = k * math.pi / 4
						local x, z = m.x + r * math.sin(a), m.z + r * math.cos(a)
						for f = 0, 7 do
							local s = SquirrelMotor.new(x, baked.groundAt(x, z, m.y + 3), z)
							s.yaw = f * math.pi / 4 + 0.1
							local text = SewerAmbience.prompt(layout, viewOf(s))
							SquirrelMotor.step(s, BakedWorld.keys(0, { grab = true }), 1 / 60, w)
							local entered = s.routeId ~= nil and layout.spaceOf(s.routeId) == m.space
							local where = `{m.id} r {r} a {k} facing {f}`
							t.eq(text == P.down, entered, `{where}: says "{tostring(text)}", went down {entered}`)
							if entered then
								went += 1
								-- and W there, the view toward the opening, does not take it down (a hatch: E only)
								t.falsy(
									walksIn(x, z, f * math.pi / 4 + 0.1, -m.out.x, -m.out.z, m, 30),
									`{where}: W stays up`
								)
							end
							if text then
								said += 1
								for _, word in { "north", "south", "east", "west" } do
									t.truthy(
										string.find(text, word, 1, true) == nil,
										`{where}: no compass word ("{text}")`
									)
								end
							elseif r <= 2.5 then
								-- within C.near of a mouth something is always said (how to get in)
								t.truthy(r > SewerAmbience.C.near, `{where}: nothing said`)
							end
						end
					end
				end
			end
			t.truthy(went >= 8 * 3 * 8 * 8, `went down from {went} places, every facing`)
			t.truthy(said > went, "near a mouth but not on it, the way in is explained")
		end
	)

	t.test("the whole grate takes E and says so; a body's width off it neither goes down nor is told to", function()
		local n, off = 0, 0
		for _, m in layout.mouths do
			local o = m.opening
			-- a 7 x 7 grid over the opening, 0.3 in from its edges, every facing: E goes down, the words say so and the
			-- server accepts the step
			for i = 0, 6 do
				for j = 0, 6 do
					local x = o.x0 + 0.3 + (o.x1 - o.x0 - 0.6) * i / 6
					local z = o.z0 + 0.3 + (o.z1 - o.z0 - 0.6) * j / 6
					local s = SquirrelMotor.new(x, baked.groundAt(x, z, m.y + 3), z)
					s.yaw = (i * 7 + j) * math.pi / 4 + 0.1
					local where = `{m.id} at ({x}, {z})`
					t.eq(SewerAmbience.prompt(layout, viewOf(s)), P.down, where)
					local before = SquirrelMotor.clone(s)
					SquirrelMotor.step(s, BakedWorld.keys(0, { grab = true }), 1 / 60, w)
					t.eq(s.routeId, m.route, `{where}: E goes down`)
					t.eq(#SquirrelMotor.envelope(before, s, 1 / 60, w, false), 0, `{where}: the server agrees`)
					n += 1
				end
			end
			-- 0.5 studs past the margin off each edge and corner (the rung-side frame included): nothing
			local d = Enclosure.C.hatchMargin + 0.5
			local cx, cz = (o.x0 + o.x1) / 2, (o.z0 + o.z1) / 2
			for _, q in
				{
					{ o.x0 - d, cz },
					{ o.x1 + d, cz },
					{ cx, o.z0 - d },
					{ cx, o.z1 + d },
					{ o.x0 - d * 0.71, o.z0 - d * 0.71 },
					{ o.x1 + d * 0.71, o.z1 + d * 0.71 },
				}
			do
				local s = SquirrelMotor.new(q[1], baked.groundAt(q[1], q[2], m.y + 3), q[2])
				s.yaw = math.atan2(cx - q[1], cz - q[2])
				local where = `{m.id} off at ({q[1]}, {q[2]})`
				t.truthy(SewerAmbience.prompt(layout, viewOf(s)) ~= P.down, where)
				SquirrelMotor.step(s, BakedWorld.keys(0, { grab = true }), 1 / 60, w)
				t.truthy(s.routeId == nil or layout.spaceOf(s.routeId) ~= m.space, `{where}: E does not go down`)
				off += 1
			end
		end
		t.eq(n, 8 * 49)
		t.eq(off, 8 * 6)
	end)

	t.test("a person, the fox or a deer is never told to go down a drain", function()
		for _, m in layout.mouths do
			local s = SquirrelMotor.new(m.x, m.y, m.z)
			s.yaw = math.atan2(-m.out.x, -m.out.z)
			t.eq(SewerAmbience.prompt(layout, viewOf(s, 0, true)), P.down, m.id)
			t.eq(SewerAmbience.prompt(layout, viewOf(s, 0, false)), nil, m.id)
		end
		t.truthy(SewerAmbience.canGoDown("squirrel", nil))
		t.truthy(SewerAmbience.canGoDown("rodent", nil))
		t.truthy(SewerAmbience.canGoDown("squirrel", "spicy"))
		for _, who in { "human", "fox", "deer" } do
			t.truthy(not SewerAmbience.canGoDown(who, nil), who)
		end
	end)

	t.test("'W: climb out' shows in the top of the shaft on the way out of every run, never on the way down", function()
		for _, run in RUNS do
			local a, b = mouth(run[1]), mouth(run[2])
			local s = SquirrelMotor.new(a.x, baked.groundAt(a.x, a.z, a.y + 3), a.z)
			s.yaw = math.atan2(-a.out.x, -a.out.z)
			local cam = BakedWorld.cameraYawToward(b.x - a.x, b.z - a.z)
			local lastY = s.y
			local climbSaid, downSaid, passageSaid, streetSaid = 0, 0, 0, 0
			BakedWorld.drive(w, s, 60 * 40, function(f: number): SquirrelMotor.Input
				return BakedWorld.keys(cam, if f == 1 then { grab = true } else { fw = 1 })
			end, {
				stop = function(st: State, f: number): boolean
					local vy = (st.y - lastY) * 60
					lastY = st.y
					local text = SewerAmbience.prompt(layout, viewOf(st, vy))
					local inShaft = SewerAmbience.shaftAt(layout, st.x, st.y, st.z)
					if text == "W: climb out" then
						if inShaft == nil then
							passageSaid += 1
						elseif inShaft.id == a.id then
							downSaid += 1
						else
							climbSaid += 1
						end
					end
					if st.routeId == nil and f > 2 and text == "W: climb out" then
						streetSaid += 1
					end
					return f > 2 and st.routeId == nil
				end,
			})
			local name = `{run[1]} to {run[2]}`
			t.truthy(climbSaid >= 10, `{name}: said in the far shaft {climbSaid} frames`)
			t.eq(downSaid, 0, `{name}: never on the way down`)
			t.eq(passageSaid, 0, `{name}: never along a passage`)
			t.eq(streetSaid, 0, `{name}: never on the street`)
			t.truthy(layout.nearestMouth(s.x, s.z, 2) == b, `{name}: came out at {run[2]}`)
		end
	end)

	t.test("inside, every key the motor refuses reads as a drain's refusal (Space, Q, a click, E)", function()
		local reg = w.registry
		for _, r in layout.routes do
			local route = reg:get(r.id) :: any
			for _, key in { "leap", "drop", "pounce", "grab" } do
				local q = reg:pointAt(route, 0.4)
				local s = SquirrelMotor.new(q.x, q.y, q.z)
				s.grounded = false
				s.routeId, s.railT, s.railDir = r.id, 0.4, 1
				local frame = { [key] = true }
				local _, events = SquirrelMotor.step(s, BakedWorld.keys(0, frame), 1 / 60, w)
				local generic = SquirrelController.feedback(frame, events :: any, true)
				t.truthy(generic ~= nil, `{r.id} {key}: the controller says something`)
				local said = SewerAmbience.reword(generic :: string, true)
				t.truthy(string.find(said, "down here", 1, true) ~= nil, `{r.id} {key}: "{said}"`)
				t.truthy(string.find(said, "grate", 1, true) ~= nil, `{r.id} {key}: says where the way out is`)
				t.eq(SewerAmbience.reword(generic :: string, false), generic, `{r.id} {key}: unchanged above`)
			end
		end
		local other = "Junction ahead: A or D picks the way"
		t.eq(SewerAmbience.reword(other, true), other, "everything else is left as it is")
	end)

	t.test("place names, cue points inside their pipes, the water loop per pipe", function()
		for _, p in layout.pipes do
			local name = SewerAmbience.placeName(p)
			t.truthy(string.sub(name, 1, 11) == "UNDERGROUND", name)
			t.truthy(string.find(name, p.sign, 1, true) ~= nil, name)
		end
		t.eq(SewerAmbience.loopFor(layout, "sewer.crossroads"), "sewer.trickle")
		t.eq(SewerAmbience.loopFor(layout, "sewer.bowllane"), "sewer.trickle")
		t.eq(SewerAmbience.loopFor(layout, "sewer.culvert"), "sewer.riverHum")
		t.eq(SewerAmbience.loopFor(layout, "nowhere"), nil)
		local per: { [string]: number } = {}
		for _, c in SewerAmbience.cuePoints(layout) do
			t.truthy(SewerAmbience.CUES[c.cue] ~= nil, `{c.cue} is a named cue`)
			per[c.space .. " " .. c.cue] = (per[c.space .. " " .. c.cue] or 0) + 1
			if c.cue == "sewer.streetMurmur" then
				t.truthy(layout.contains(c.x, c.y, c.z) == nil, "the street's murmur is at street level")
			else
				t.eq(layout.contains(c.x, c.y, c.z), c.space, `{c.cue} at ({c.x}, {c.y}, {c.z}) is inside its pipe`)
			end
		end
		t.eq(per["sewer.crossroads sewer.streetMurmur"], 4)
		t.truthy((per["sewer.culvert sewer.riverHum"] or 0) >= 20, "the culvert hums along its length")
		t.eq(per["sewer.culvert sewer.trickle"], nil, "the culvert is dry")
		t.truthy((per["sewer.bowllane sewer.drip"] or 0) >= 20, "Bowl Lane drips along its length")
	end)

	t.test("every cue is named in docs/AUDIO_BUDGET.md and has a library sound and a volume (none silent)", function()
		local doc = fs.readFile("docs/AUDIO_BUDGET.md")
		local n = 0
		for cue, id in SewerAmbience.CUES do
			n += 1
			t.truthy(string.match(id, "^rbxassetid://%d+$") ~= nil, `{cue}: a library asset id`)
			t.truthy(
				string.find(doc, string.match(id, "%d+") or "?", 1, true) ~= nil,
				`{cue}: its id is in docs/AUDIO_BUDGET.md`
			)
			local v = SewerAmbience.VOLUME[cue]
			t.truthy(type(v) == "number" and v > 0 and v <= 1, `{cue}: a volume`)
			t.truthy(string.find(doc, "`" .. cue .. "`", 1, true) ~= nil, `{cue} is in docs/AUDIO_BUDGET.md`)
		end
		t.eq(n, 11)
		-- the per-stride and per-stud cues are kept under the one-off ones
		t.truthy(SewerAmbience.VOLUME["sewer.footEcho"] < SewerAmbience.VOLUME["sewer.grateIn"])
		t.truthy(SewerAmbience.VOLUME["sewer.rung"] < SewerAmbience.VOLUME["sewer.grateIn"])
	end)

	t.test("the look: nothing at all outside, darker, cooler and closer inside, never black", function()
		local g0, g1 = SewerAmbience.grade(0), SewerAmbience.grade(1)
		t.eq(g0.brightness, 0)
		t.eq(g0.contrast, 0)
		t.eq(g0.saturation, 0)
		t.eq(g0.tint[1] + g0.tint[2] + g0.tint[3], 765)
		t.truthy(g1.brightness < 0 and g1.brightness >= -0.03, "darker by the tint, not by an added black")
		t.truthy(
			math.min(g1.tint[1], g1.tint[2], g1.tint[3]) >= 0.75 * 255,
			"the tint keeps three quarters of the light"
		)
		t.truthy(g1.tint[3] > g1.tint[1], "cooler (more blue than red)")
		t.eq(SewerAmbience.focus(0).far, 0)
		t.truthy(SewerAmbience.focus(1).far > 0, "the far end softens")
	end)

	t.test("the arm of drain 1 a point lies along", function()
		for _, m in layout.mouthsOf("P1") do
			local ch = layout.chambers[1]
			local x, z = ch.crossing.x + (m.x - ch.crossing.x) * 0.3, ch.crossing.z + (m.z - ch.crossing.z) * 0.3
			t.eq(SewerAmbience.armAt(layout, x, z), m, m.id)
		end
	end)

	t.test("drain 1's crossing: A / D announced running at it along the arm, and the arm picked named", function()
		local reg = w.registry
		local ch = layout.chambers[1]
		for _, r in layout.routes do
			local route = reg:get(r.id) :: any
			if layout.spaceOf(r.id) ~= "sewer.crossroads" then
				continue
			end
			local spec = route.enclosure :: Enclosure.Spec
			local side = spec.forks[1]
			local sideMouth: Mouth? = nil
			for _, m in layout.mouths do
				if m.route == side.route then
					sideMouth = m
				end
			end
			local pickedText = string.format(P.crossingPicked, (sideMouth :: Mouth).name)
			local aheadSeen, pickedSeen = 0, 0
			for i = 0, 400 do
				local tt = i / 400
				local q = reg:pointAt(route, tt)
				local q2 = reg:pointAt(route, math.min(1, tt + 0.0025))
				local view: SewerAmbience.View = {
					x = q.x,
					y = q.y,
					z = q.z,
					vy = 0,
					canGo = true,
					space = layout.contains(q.x, q.y, q.z),
					mx = q2.x - q.x,
					mz = q2.z - q.z,
				}
				local text = SewerAmbience.prompt(layout, view)
				local d = math.sqrt((q.x - ch.crossing.x) ^ 2 + (q.z - ch.crossing.z) ^ 2)
				if text == P.crossingAhead then
					aheadSeen += 1
					t.truthy(d <= SewerAmbience.C.crossingHint, `{r.id} t {tt}: ahead at {d}`)
					-- the arm A or D picked (the motor keeps it): named instead
					local picked: SewerAmbience.View = table.clone(view)
					picked.picked = side.route
					t.eq(SewerAmbience.prompt(layout, picked), pickedText, `{r.id} t {tt}: the pick named`)
					pickedSeen += 1
				end
				-- running away from the crossing: nothing about it
				local back: SewerAmbience.View = table.clone(view)
				back.mx, back.mz = -view.mx :: number, -view.mz :: number
				back.picked = side.route
				local bt = SewerAmbience.prompt(layout, back)
				t.truthy(bt ~= P.crossingAhead and bt ~= pickedText, `{r.id} t {tt}: not running at it`)
			end
			-- along the level run of the arm (the shaft's foot is 2 studs from the end wall, 25 or more from the
			-- crossing), all of it
			t.truthy(aheadSeen >= 150 and pickedSeen == aheadSeen, `{r.id}: announced along the arm ({aheadSeen})`)
		end
	end)

	t.test("just come up out of a drain: nothing said about going back down for C.promptHold", function()
		for _, m in layout.mouths do
			local s = SquirrelMotor.new(m.x, m.y, m.z)
			s.yaw = math.atan2(-m.out.x, -m.out.z)
			local v = viewOf(s)
			v.since = 0.2
			t.eq(SewerAmbience.prompt(layout, v), nil, `{m.id}: just out`)
			v.since = SewerAmbience.C.promptHold + 0.1
			t.eq(SewerAmbience.prompt(layout, v), P.down, `{m.id}: a moment later`)
		end
	end)

	t.test("the lamps on: the nearest within the radius, at most the cap", function()
		local pts = {}
		for i = 1, 30 do
			table.insert(pts, roblox.Vector3.new(i * 12, 0, 0))
		end
		local on = SewerAmbience.litLamps(pts :: any, roblox.Vector3.new(100, 0, 0) :: any, 40, 8)
		t.truthy(#on <= 8 and #on >= 6, `{#on} on`)
		for _, i in on do
			t.truthy(math.abs(pts[i].X - 100) <= 40)
		end
		t.eq(#SewerAmbience.litLamps(pts :: any, roblox.Vector3.new(100, 0, 0), 40, 3), 3)
		t.eq(#SewerAmbience.litLamps(pts :: any, roblox.Vector3.new(5000, 0, 0), 40, 8), 0)
	end)

	-- a point on pipe `id`'s line (its first passage, `f` of the way along its second segment) and the level
	-- direction across it there
	local function onPipe(id: string, f: number): (number, number, number, number, number)
		local pass = (layout.pipe(id) :: any).passages[1]
		local a, b = pass.points[2], pass.points[3]
		local dx, dz = b.x - a.x, b.z - a.z
		local l = math.sqrt(dx * dx + dz * dz)
		return a.x + dx * f, a.y + (b.y - a.y) * f, a.z + dz * f, -dz / l, dx / l
	end
	-- a vehicle `off` studs across the pipe's line at that point, a street's height over it
	local function car(id: string, kind: string, x: number, y: number, z: number, nx: number, nz: number, off: number)
		return { id = id, kind = kind, x = x + nx * off, y = y + 12, z = z + nz * off }
	end

	t.test("overhead: a car coming over the body's pipe fires once; the pipe's gap; the trolley its own cue", function()
		local x, y, z, nx, nz = onPipe("P1", 0.5)
		local body = { x = x, z = z }
		local st = SewerAmbience.newOverhead()
		-- the cues fired at this look, joined
		local function look(now: number, vs: { SewerAmbience.Vehicle }): string
			local out = {}
			for _, f in SewerAmbience.overhead(layout, "sewer.crossroads", body, vs, st, now) do
				table.insert(out, f.cue)
				t.eq(f.pipe, "P1")
				t.truthy(math.abs(f.x - x) < 1 and math.abs(f.z - z) < 1, "placed on the pipe under the car")
			end
			return table.concat(out, ",")
		end
		local cue = "sewer.carOverhead"
		-- a car crossing over the arm: 20 studs off, over it, past it, away again
		t.eq(look(0, { car("Ghost_1", "sedan", x, y, z, nx, nz, -20) }), "", "not over yet")
		t.eq(look(0.1, { car("Ghost_1", "sedan", x, y, z, nx, nz, -2) }), cue, "over it: the cue")
		t.eq(look(0.2, { car("Ghost_1", "sedan", x, y, z, nx, nz, 2) }), "", "still over it: once")
		t.eq(look(0.3, { car("Ghost_1", "sedan", x, y, z, nx, nz, 20) }), "", "gone")
		-- a second car a second later: within the pipe's gap
		t.eq(look(1.0, { car("Ghost_2", "rv", x, y, z, nx, nz, 20) }), "")
		t.eq(look(1.1, { car("Ghost_2", "rv", x, y, z, nx, nz, 0) }), "", "within C.overheadGap of the last")
		-- the trolley has its own cue and gap
		t.eq(look(1.2, { car("Ghost_13", "trolley", x, y, z, nx, nz, -20) }), "")
		t.eq(look(1.3, { car("Ghost_13", "trolley", x, y, z, nx, nz, -3) }), "sewer.trolleyOverhead")
		-- after the gap a car comes over again
		local later = 0.1 + SewerAmbience.C.overheadGap[cue]
		t.eq(look(later, { car("Ghost_3", "sedan", x, y, z, nx, nz, 15) }), "")
		t.eq(look(later + 0.1, { car("Ghost_3", "sedan", x, y, z, nx, nz, 1) }), cue, "after the gap")
		t.eq(SewerAmbience.overheadCue("motorcycle"), cue)
		t.eq(SewerAmbience.overheadCue("trolley"), "sewer.trolleyOverhead")
	end)

	t.test("overhead: nothing for a car parked over it, hidden, far off, over another pipe, or outside", function()
		local x, y, z, nx, nz = onPipe("P1", 0.5)
		local body = { x = x, z = z }
		local function fires(
			space: string?,
			frames: { { SewerAmbience.Vehicle } },
			from: { x: number, z: number }?
		): number
			local st = SewerAmbience.newOverhead()
			local n = 0
			for i, vs in frames do
				n += #SewerAmbience.overhead(layout, space, from or body, vs, st, i * 0.1)
			end
			return n
		end
		local parked = car("Ghost_1", "sedan", x, y, z, nx, nz, 0)
		t.eq(fires("sewer.crossroads", { { parked }, { parked }, { parked } }), 0, "already there: it is not passing")
		-- a ghost the view hides parks far under the map (Traffic/Ghost.HIDDEN_Y)
		local hidden = { id = "Ghost_2", kind = "sedan", x = x, y = -500, z = z }
		local away = car("Ghost_2", "sedan", x, y, z, nx, nz, 20)
		t.eq(fires("sewer.crossroads", { { away }, { hidden } }), 0, "hidden")
		-- the body further along the pipe than C.overheadNear from where the car comes over
		local far = SewerAmbience.C.overheadNear + 5
		local farBody = { x = x - nz * far, z = z + nx * far }
		local over = { { away }, { car("Ghost_2", "sedan", x, y, z, nx, nz, 0) } }
		t.eq(fires("sewer.crossroads", over), 1, "(the same crossing, heard from near)")
		t.eq(fires("sewer.crossroads", over, farBody), 0, "too far from the body")
		-- the same crossing heard from drain 3, and with the body out on the street
		t.eq(fires("sewer.bowllane", over), 0, "over another pipe")
		t.eq(fires(nil, over), 0, "outside")
		local st = SewerAmbience.newOverhead()
		SewerAmbience.overhead(layout, "sewer.crossroads", body, { away }, st, 0)
		t.truthy(st.over["Ghost_2"] == false, "seen, not over")
		SewerAmbience.overhead(layout, nil, nil, { away }, st, 0.1)
		t.eq(next(st.over), nil, "outside: what was seen is forgotten")
	end)

	t.test(
		"overhead in the town: the cars' lanes cross drains 1 and 3, the trolley's track drain 3, none the culvert",
		function()
			local svc =
				TrafficService.new({ lanes = data:lanes(), roads = data:roads(), heightAt = Height.at, seed = 3 })
			local C = SewerAmbience.C
			-- every lane sampled every stud, both ways: does a vehicle on it come over each pipe (within reach of its line,
			-- the street over the walkway)?
			local crosses: { [string]: { [string]: boolean } } = {}
			for laneId, lane in svc.lanes do
				if not LaneMath.isVehicleLane(laneId) then
					continue
				end
				for _, dir in { 1, -1 } do
					local len = LaneMath.length(lane, dir)
					for s = 0, len, 1 do
						local p = LaneMath.pointAt(lane, s, dir)
						for _, pipe in layout.pipes do
							local st = SewerAmbience.newOverhead()
							local v = { id = "v", kind = "sedan", x = p.x, y = Height.at(p.x, p.z), z = p.z }
							-- (seen once away from it, then here: over() is what the cue needs)
							SewerAmbience.overhead(layout, pipe.space, { x = p.x, z = p.z }, { v }, st, 0)
							st.over.v = false
							if #SewerAmbience.overhead(layout, pipe.space, { x = p.x, z = p.z }, { v }, st, 1) > 0 then
								crosses[pipe.id] = crosses[pipe.id] or {}
								crosses[pipe.id][laneId] = true
							end
						end
					end
				end
			end
			local function names(id: string): string
				local out = {}
				for l in crosses[id] or {} do
					table.insert(out, l)
				end
				table.sort(out)
				return table.concat(out, ", ")
			end
			print(`      drain 1 under: {names("P1")}`)
			print(`      drain 3 under: {names("P3")}`)
			t.truthy(crosses.P1 ~= nil, "a car comes over drain 1")
			t.truthy(crosses.P3 ~= nil and crosses.P3.trolley_track, "the trolley comes over drain 3")
			t.eq(crosses.P2, nil, "nothing drives over the culvert (under the river)")
			t.truthy(C.overheadReach > 0 and C.overheadNear >= C.overheadReach)
		end
	)

	Isolated.register(t, "tests/isolated/sewer_ambience")
end
