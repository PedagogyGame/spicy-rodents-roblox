local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local TownAI = require("@server/AI/TownAI")
local TrafficService = require("@server/Traffic/TrafficService")
local RoadSquirrels = require("@server/Wildlife/RoadSquirrels")
local data = Data.default()
local world = TownAI.build({ data = data, seed = 1 })
local traffic = TrafficService.new({ lanes = data:lanes(), roads = data:roads(), heightAt = Height.at, seed = 7 })
local t0 = os.clock()
local n = TownAI.setRoad(world, function()
	return traffic:cars()
end)
print("sites", n, "ms", (os.clock() - t0) * 1000)
local road = RoadSquirrels.new({ world = world })
local squirrels = {}
for _, a in world.actors do
	if a.species == "squirrel" and a.variant == "normal" then
		table.insert(squirrels, a)
	end
end
TownAI.setFocus(world, function()
	local out = {}
	for _, a in squirrels do
		table.insert(out, { x = a.x, z = a.z })
	end
	return out
end)
local hits = 0
traffic.RunOver:connect(function(id, v)
	hits += 1
	local ok = road:hit(id)
	local a = world.actorsById[id]
	local b = world.brains[id]
	print(string.format("  t=%.1f hit squirrel %d by %s (%s) flat=%s", world.now, id, v.name, v.kind, tostring(ok)))
end)
local list = {}
local dt = 1 / 30
local phases = {}
local started, careless, dashes = 0, 0, 0
local was = {}
local minutes = 60
local wall = os.clock()
for frame = 1, minutes * 60 * 30 do
	TownAI.stepFrame(world, dt)
	table.clear(list)
	for _, a in squirrels do
		local b = world.brains[a.id]
		local c = b.cross
		local ph = if c then c.phase else nil
		if ph ~= was[a.id] then
			if ph == "down" then
				started += 1
			elseif ph == "dash" then
				dashes += 1
				if c.careless then
					careless += 1
				end
			end
			if ph then
				phases[ph] = (phases[ph] or 0) + 1
			end
			was[a.id] = ph
		end
		if a.crossing then
			table.insert(list, { id = a.id, x = a.x, y = a.y - a.hip, z = a.z })
		end
	end
	traffic:step(dt, { squirrels = list })
	road:step(dt)
end
print("wall s", os.clock() - wall)
print("minutes", minutes, "started", started, "dashes", dashes, "careless", careless, "hits", hits)
for k, v in phases do
	print("  phase", k, v)
end
local st = road:stats()
print("stats", st.hits, st.flat, st.spared, st.back, "down now", road:down())
