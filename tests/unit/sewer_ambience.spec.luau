--!strict
-- The storm drains felt from inside, on the client (Client/World/SewerAmbience; lane S3 of the sewer plan). Here, the
-- pure part against the real motor on the pipes' stand-in (tests/lib/SewerStandIn on tests/lib/BakedWorld):
--   "E: down the drain" shows exactly where E takes the body down (every mouth, a ring of places and facings)
--   "W: climb out" shows in the top of a shaft on the way out of every run, never on the way down or in a passage
--   the controller's refusals inside a drain (Space, Q, a click, E: the motor's hints) read as a drain's
--   the place names, the cue points inside their pipes, every cue named in docs/AUDIO_BUDGET.md with no id yet
-- The engine part (the look, the lamps, the reverb, the words on screen and the cues over whole runs, Lighting never
-- touched) is in tests/isolated/sewer_ambience.luau, run in its own Lune process (tests/lib/Isolated says why); each
-- of its cases is reported here as its own test.
local fs = require("@lune/fs")
local Data = require("@shared/Data")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SewerLayout = require("@shared/World/SewerLayout")
local SewerAmbience = require("@client/World/SewerAmbience")
local SquirrelController = require("@client/Controllers/Squirrel")
local BakedWorld = require("@tests/lib/BakedWorld")
local Isolated = require("@tests/lib/Isolated")
local SewerStandIn = require("@tests/lib/SewerStandIn")

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
			fx = math.sin(s.yaw),
			fz = math.cos(s.yaw),
			vy = vy or 0,
			canGo = canGo ~= false,
			space = layout.contains(s.x, s.y, s.z),
		}
	end

	t.test("'E: down the drain' shows exactly where E goes down: every mouth, a ring of places and facings", function()
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
						local _, events = SquirrelMotor.step(s, BakedWorld.keys(0, { grab = true }), 1 / 60, w)
						local entered = s.routeId ~= nil and layout.spaceOf(s.routeId) == m.space
						local where = `{m.id} r {r} a {k} facing {f}`
						t.eq(
							text == "E: down the drain",
							entered,
							`{where}: says "{tostring(text)}", went down {entered}`
						)
						if entered then
							went += 1
						end
						if r <= 2.5 and text == nil then
							-- within C.near of a mouth something is always said (how to get in)
							t.truthy(r > SewerAmbience.C.near, `{where}: nothing said`)
						end
						if text then
							said += 1
						end
						local _ = events
					end
				end
			end
		end
		t.truthy(went >= 8 * 10, `went down from {went} places`)
		t.truthy(said > went, "near a mouth but not on it facing in, the way in is explained")
	end)

	t.test("a person, the fox or a deer is never told to go down a drain", function()
		for _, m in layout.mouths do
			local s = SquirrelMotor.new(m.x, m.y, m.z)
			s.yaw = math.atan2(-m.out.x, -m.out.z)
			t.eq(SewerAmbience.prompt(layout, viewOf(s, 0, true)), "E: down the drain", m.id)
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

	t.test("every cue is named in docs/AUDIO_BUDGET.md and none has a sound yet (nothing uploaded)", function()
		local doc = fs.readFile("docs/AUDIO_BUDGET.md")
		local n = 0
		for cue, id in SewerAmbience.CUES do
			n += 1
			t.eq(id, "", `{cue}: no asset id yet`)
			t.truthy(string.find(doc, "`" .. cue .. "`", 1, true) ~= nil, `{cue} is in docs/AUDIO_BUDGET.md`)
		end
		t.eq(n, 11)
	end)

	t.test("the look: nothing at all outside, darker, cooler and closer inside, never black", function()
		local g0, g1 = SewerAmbience.grade(0), SewerAmbience.grade(1)
		t.eq(g0.brightness, 0)
		t.eq(g0.contrast, 0)
		t.eq(g0.saturation, 0)
		t.eq(g0.tint[1] + g0.tint[2] + g0.tint[3], 765)
		t.truthy(g1.brightness < 0 and g1.brightness > -0.25, "darker, not black")
		t.truthy(g1.tint[3] > g1.tint[1], "cooler (more blue than red)")
		t.eq(SewerAmbience.focus(0).far, 0)
		t.truthy(SewerAmbience.focus(1).far > 0, "the far end softens")
	end)

	Isolated.register(t, "tests/isolated/sewer_ambience")
end
