--!strict
-- The live squirrel validator in the enclosed runs and up high (tests/lib/LiveRig over tests/lib/BakedWorld): the
-- storm drains at the pipe pace (Tunables sewer.speedMult 1.25, sewer.sprintMult 1.04), every hollow tree and the
-- fallen log, the bowling alley's ball returns (every pair), its roof route (the yard house's ridge, the leap to the
-- bough, the vent, the rafters and the light rails), each run by the real motor with scripted keys through a 300 ms
-- link with jitter, loss and held-up bursts, judged by the server with enforcement on and the live wall and floor rays
-- over the baked parts (the bough cylinders looked past, as on the server). Every run: 0 snaps.
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AlleyRoof = require("@shared/Attractions/AlleyRoof")
local Data = require("@shared/Data")
local HollowLayout = require("@shared/World/HollowLayout")
local SewerLayout = require("@shared/World/SewerLayout")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local HollowShell = require("@server/World/HollowShell")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local BakedWorld = require("@tests/lib/BakedWorld")
local LiveRig = require("@tests/lib/LiveRig")
local SewerStandIn = require("@tests/lib/SewerStandIn")

local FAST = process.env.SPICY_FAST ~= nil

type State = SquirrelMotor.State

-- the live rays over a baked world: walls are colliding parts the squirrel's queries meet, past the bough cylinders,
-- never the terrain; floors are those parts or the terrain
local function rays(baked: BakedWorld.World): (ValidatorWorld.Ray, ValidatorWorld.Ray)
	local function solid(p: BakedWorld.Part): boolean
		if not p.squirrelSolid then
			return false
		end
		local parentName = string.match(p.path, "([^%.]+)%.[^%.]+$") or ""
		return not ValidatorWorld.isBough(p.name, parentName)
	end
	local function colliding(p: BakedWorld.Part): boolean
		return p.squirrelSolid
	end
	local function wall(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): boolean
		return baked.raycast(ox, oy, oz, dx, dy, dz, solid) ~= nil
	end
	local function down(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): boolean
		if baked.raycast(ox, oy, oz, dx, dy, dz, colliding) ~= nil then
			return true
		end
		local g = baked.terrainAt(ox, oz)
		return g >= oy + dy and g <= oy
	end
	return wall, down
end

local LINKS: { { name: string, link: LiveRig.Link } } = {
	{ name = "300 ms", link = { latency = 0.3, jitter = 0.15, loss = 0.02 } },
	{ name = "held-up bursts", link = { latency = 0.1, jitter = 0.1, loss = 0.02, holdEvery = 3, holdFor = 0.5 } },
}

local function follow(st: State): number
	return BakedWorld.cameraYawToward(math.sin(st.yaw), math.cos(st.yaw))
end

-- runs one scripted body through every link; returns nothing, asserts 0 snaps
local function play(
	t: any,
	name: string,
	world: SquirrelMotor.World,
	vworld: any,
	start: () -> State,
	keys: LiveRig.Keys,
	seconds: number,
	check: ((State) -> (boolean, string))?,
	via: { number }? -- routes the run must have used
)
	for i, l in LINKS do
		if FAST and i > 1 then
			break
		end
		local rig = LiveRig.new({ world = world, vworld = vworld, link = l.link, seed = 40 + i })
		rig:possess(start(), keys)
		rig:run(seconds)
		local r = rig:result()
		print(
			`      {LiveRig.describe(name .. " (" .. l.name .. ")", r)}; {string.format("%.4f", r.serverMsPerTick)} ms/tick`
		)
		for _, v in r.violations do
			print(`      VIOLATION {v}`)
		end
		t.eq(r.snaps, 0, `{name} ({l.name}): snaps`)
		t.truthy(r.accepted > seconds * 8, `{name} ({l.name}): packets judged ({r.accepted})`)
		if check and r.client then
			local ok, why = check(r.client)
			t.truthy(ok, `{name} ({l.name}): {why}`)
		end
		for _, id in via or {} do
			t.truthy(r.visited[id], `{name} ({l.name}): ran route {id}`)
		end
	end
end

return function(t)
	local data = Data.default()

	t.test("the storm drains, every run, walking and sprinting at the pipe pace: 0 snaps", function()
		local layout = SewerLayout.default() :: SewerLayout.Layout
		local baked = SewerStandIn.world(layout)
		local w = baked:motorWorld(data)
		local wall, down = rays(baked)
		local vworld = ValidatorWorld.build(w, { wall = wall, down = down })
		local runs = { { "P1.NW", "P1.SE" }, { "P2.W", "P2.E" }, { "P3.S", "P3.N" }, { "P3.N", "P3.S" } }
		for _, run in runs do
			local a, b = layout.mouth(run[1]) :: SewerLayout.Mouth, layout.mouth(run[2]) :: SewerLayout.Mouth
			local cam = BakedWorld.cameraYawToward(b.x - a.x, b.z - a.z)
			for _, sprint in { false, true } do
				local entered = false
				play(t, `{run[1]} -> {run[2]}{if sprint then ", sprinting" else ""}`, w, vworld, function(): State
					local s = SquirrelMotor.new(a.x, baked.groundAt(a.x, a.z, 50), a.z)
					s.yaw = math.atan2(-a.out.x, -a.out.z)
					return s
				end, function(now: number, st: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
					if st.routeId ~= nil and layout.spaceOf(st.routeId) ~= nil then
						entered = true
					end
					if not entered and now < 0.6 then
						return BakedWorld.keys(cam, { grab = true })
					end
					return BakedWorld.keys(cam, { fw = 1, sprint = sprint })
				end, 25)
				t.truthy(entered, `{run[1]}: went down the drain`)
			end
		end
	end)

	t.test("every hollow tree and the fallen log: in at the hole, on up its runs: 0 snaps", function()
		local layout = HollowLayout.default() :: HollowLayout.Layout
		local model = HollowShell.build(roblox, layout)
		local baked = BakedWorld.fromModel(model)
		local w = baked:motorWorld(data)
		local wall, down = rays(baked)
		local vworld = ValidatorWorld.build(w, { wall = wall, down = down })
		for _, h in layout.hollows do
			local hole: HollowLayout.Mouth? = nil
			for _, m in h.mouths do
				if m.opens == "ground" then
					hole = m
					break
				end
			end
			local m = hole :: HollowLayout.Mouth
			local ol = math.sqrt(m.out[1] ^ 2 + m.out[3] ^ 2)
			local ox, oz = m.out[1] / ol, m.out[3] / ol
			local cam = BakedWorld.cameraYawToward(-ox, -oz)
			local inside = false
			play(t, h.id, w, vworld, function(): State
				local x, z = m.x + ox * 6, m.z + oz * 6
				local s = SquirrelMotor.new(x, baked.groundAt(x, z, m.y + 3), z)
				s.yaw = math.atan2(-ox, -oz)
				return s
			end, function(now: number, st: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
				if st.routeId and (w.registry:get(st.routeId) :: any).enclosure then
					inside = true
				end
				-- in and on, then about a third of the time back the other way
				local back = now % 9 > 6
				return BakedWorld.keys(if st.routeId then follow(st) else cam, { fw = if back then -1 else 1 })
			end, if FAST then 8 else 14)
			t.truthy(inside, `{h.id}: went in`)
		end
	end)

	t.test("the bowling alley: every ball return, the roof route, the vent, the rafters: 0 snaps", function()
		local baked, place = BakedWorld.bakeAlley()
		local w = baked:motorWorld(data)
		local wall, down = rays(baked)
		local vworld = ValidatorWorld.build(w, { wall = wall, down = down })
		local reg = w.registry
		local function camAlong(dX: number, dD: number): number
			local dx, dz = AlleyLayout.dirToWorld(place, dX, dD)
			return BakedWorld.cameraYawToward(dx, dz)
		end
		local function standing(X: number, D: number, Y: number, dX: number, dD: number): State
			local x, _, z = AlleyLayout.toWorld(place, X, 0, D)
			local s = SquirrelMotor.new(x, baked.groundAt(x, z, place.floorY + Y), z)
			local dx, dz = AlleyLayout.dirToWorld(place, dX, dD)
			s.yaw = math.atan2(dx, dz)
			return s
		end
		local function onRoute(id: number, tt: number): State
			local r = reg:get(id) :: any
			local q = reg:pointAt(r, tt)
			local q2 = reg:pointAt(r, math.min(1, tt + 0.02))
			local s = SquirrelMotor.new(q.x, q.y, q.z)
			s.grounded = false
			s.routeId, s.railT, s.railDir = id, tt, 1
			s.yaw = math.atan2(q2.x - q.x, q2.z - q.z)
			return s
		end
		local pairs = if FAST then { 1, AlleyLayout.PAIRS } else nil
		for p = 1, AlleyLayout.PAIRS do
			if pairs and p ~= pairs[1] and p ~= pairs[2] then
				continue
			end
			local px = AlleyLayout.pairX(p)
			local cam = camAlong(0, -1)
			play(
				t,
				`ball return {p}`,
				w,
				vworld,
				function(): State
					return standing(px, 92, AlleyLayout.ALLEY_Y + 1, 0, -1)
				end,
				function(_now: number, st: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
					return BakedWorld.keys(if st.routeId then follow(st) else cam, { fw = 1 })
				end,
				10,
				function(st: State): (boolean, string)
					return st.routeId == 9000 + 2 * p or st.routeId == nil, `ended on {st.routeId}`
				end
			)
		end
		-- the ridge to its west end, Space onto the bough, along it (Q at the parapet), on
		play(t, "the yard house's ridge, the leap to the bough", w, vworld, function(): State
			return onRoute(AlleyRoof.RIDGE, 0.6)
		end, function(now: number, st: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
			local cam = follow(st)
			if now > 2 and now < 2.1 then
				return BakedWorld.keys(cam, { fw = 1, leap = true })
			end
			return BakedWorld.keys(cam, { fw = 1, drop = now > 6 and now < 6.1 })
		end, 12, nil, { AlleyRoof.RIDGE, AlleyRoof.BOUGH })
		-- the vent from the louvre to the boot, onto the chord and along the rafters, sneaking by turns
		play(t, "the vent and the rafters", w, vworld, function(): State
			return onRoute(AlleyRoof.VENT, 0.2)
		end, function(now: number, st: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
			return BakedWorld.keys(follow(st), { fw = 1, focus = now % 6 > 3, side = if now % 10 > 8 then 1 else 0 })
		end, 16, nil, { AlleyRoof.VENT, AlleyRoof.FIRST_RAFTER })
		for _, id in { AlleyRoof.FIRST_RAFTER, AlleyRoof.FIRST_RAFTER + 10, AlleyRoof.LAST_RAFTER } do
			if reg:get(id) then
				play(t, `rafter {id}, sprinting, a leap now and then`, w, vworld, function(): State
					return onRoute(id, 0.1)
				end, function(now: number, st: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
					return BakedWorld.keys(follow(st), { fw = 1, sprint = true, leap = now % 4 > 3.9 })
				end, 10)
			end
		end
	end)
end
