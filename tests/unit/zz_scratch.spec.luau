--!nocheck
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local Colliders = require("@shared/World/Colliders")
local HospitalLayout = require("@shared/Infection/HospitalLayout")
local TownAI = require("@server/AI/TownAI")
local TrafficService = require("@server/Traffic/TrafficService")
local InfectionService = require("@server/Infection/InfectionService")
return function(t)
	t.test("scratch", function()
		local data = Data.default()
		local world = TownAI.build({ data = data, seed = 1, squirrels = 3, deer = 0, fox = 0 })
		local traffic =
			TrafficService.new({ lanes = data:lanes(), roads = data:roads(), heightAt = Height.at, seed = 7 })
		local svc = InfectionService.new({ world = world, traffic = traffic, data = data })
		for _ = 1, 100 do
			TownAI.stepFrame(world, 0.2)
		end
		local layout = svc.layout
		print("entrance", layout.entrance[1], layout.entrance[2], "outside", layout.outside[1], layout.outside[2])
		print("reception", layout.reception[1], layout.reception[2])
		print("home", svc.home[1], svc.home[2], "tail1", svc.tail[1][1], svc.tail[1][2])
		local colliders = svc.colliders
		for _, a in world.actors do
			if a.species == "human" then
				local brain = world.brains[a.id]
				local route, len = svc:walkRoute(a.x, a.z)
				local post = brain.points and brain.points[1]
				local r2, l2
				if post then
					r2, l2 = svc:walkRoute(post[1], post[2])
				end
				local inB = Colliders.pointIn(colliders, a.x, a.z, Height.at(a.x, a.z) + 3) ~= nil
				local onG = HospitalLayout.contains(layout, a.x, a.z, 60)
				if not route or (post and not r2) then
					print(
						string.format(
							"%-14s %3d %-10s at (%6.0f,%6.0f) inBuilding=%s grounds=%s route=%s post=(%s,%s) postRoute=%s",
							a.post,
							a.id,
							brain.kind,
							a.x,
							a.z,
							tostring(inB),
							tostring(onG),
							route and math.floor(len) or "nil",
							post and math.floor(post[1]) or "-",
							post and math.floor(post[2]) or "-",
							r2 and math.floor(l2) or "nil"
						)
					)
				end
			end
		end
		local Nav = require("@server/Actors/Nav")
		local nav = world.nav
		local goal = svc.tail[1]
		local function diag(x, z, label)
			local list = {}
			for i, st in nav.strips do
				local sx, sz
				if st.axis == "z" then
					sx, sz = st.coord, math.clamp(z, st.min, st.max)
				else
					sx, sz = math.clamp(x, st.min, st.max), st.coord
				end
				table.insert(list, { i = i, d = math.sqrt((sx - x) ^ 2 + (sz - z) ^ 2), x = sx, z = sz })
			end
			table.sort(list, function(a, b)
				return a.d < b.d
			end)
			local out = {}
			for k = 1, 6 do
				local c = list[k]
				local ok = false
				for _, nodeId in nav.stripNodes[c.i] do
					local n = nav.nodes[nodeId]
					local path = Nav.path(nav, n.x, n.z, goal[1], goal[2])
					if path then
						local last = path[#path - 1] or path[#path]
						if math.abs(last[1] - goal[1]) + math.abs(last[2] - goal[2]) <= 1 then
							ok = true
						end
					end
				end
				local clear = not Colliders.blocked(colliders, x, z, c.x, c.z, 1, Height.at(x, z) + 3)
				local st = nav.strips[c.i]
				table.insert(out, string.format("[%d %s d=%.0f len=%.0f path=%s clear=%s]", c.i, st.axis, c.d, st.max - st.min, tostring(ok), tostring(clear)))
			end
			print(label, math.floor(x), math.floor(z), table.concat(out, " "))
		end
		for _, a in world.actors do
			if a.species == "human" then
				local brain = world.brains[a.id]
				local post = brain.kind ~= "Pedestrian" and brain.points and brain.points[1]
				local x, z = a.x, a.z
				if post then
					x, z = post[1], post[2]
				end
				if not svc:walkRoute(x, z) then
					diag(x, z, a.post .. " " .. a.id)
				end
			end
		end
	end)
end
