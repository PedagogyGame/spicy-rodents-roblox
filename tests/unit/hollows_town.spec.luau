--!strict
-- The hollow trees in the baked town (build/Town.rbxm: lune run tools/bake/main.luau; Shared/World/HollowLayout,
-- Server/World/HollowShell): every ground hole and the 8 studs a squirrel runs in on are open ground (nothing of
-- the town in the way, the ground level with the hole), and no piece of a hollow's shell stands in a part of the town.
-- The tunnel camera inside (Client/Camera/CameraRig.tunnelPoint, its rays meeting only the shell, the point held by
-- HollowLayout's keepCamera) along every way in and up, with the town's invisible trunk colliders present: never
-- outside the cavity (the screen showing bark), never in the squirrel's head.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Data = require("@shared/Data")
local HollowLayout = require("@shared/World/HollowLayout")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local HollowShell = require("@server/World/HollowShell")
local CameraRig = require("@client/Camera/CameraRig")
local BakedWorld = require("@tests/lib/BakedWorld")

return function(t)
	local layout = HollowLayout.default() :: HollowLayout.Layout

	t.test("every hole's run-in is open ground, and no shell piece stands in the town", function()
		t.truthy(fs.isFile("build/Town.rbxm"), "build/Town.rbxm (lune run tools/bake/main.luau)")
		local town = BakedWorld.load("build/Town.rbxm")
		for _, h in layout.hollows do
			for _, m in h.mouths do
				if m.opens ~= "ground" then
					continue
				end
				local ol = math.sqrt(m.out[1] ^ 2 + m.out[3] ^ 2)
				local ox, oz = m.out[1] / ol, m.out[3] / ol
				for d = 0, 8, 0.5 do
					local x, z = m.x + ox * d, m.z + oz * d
					local g = town.groundAt(x, z, m.y + 3)
					local b = town.blocker(x, z, g, 0.8)
					t.eq(b and b.path, nil, `{h.id} {m.name}: {d} studs out`)
					t.truthy(math.abs(g - m.y) < 1.5, `{h.id} {m.name}: the ground {d} studs out at {g} (hole {m.y})`)
				end
			end
		end
		for _, h in layout.hollows do
			-- its own tree, or the log's own lot (its marker and the foundation sunk under the ground)
			local own = if h.trunk then `Tree_{h.trunk}.` else "Lots.north_hollow_log."
			for _, pc in h.parts do
				-- (a knothole's oval is on the bark outside; a floor lies on the ground under the bark by design)
				if pc.role == "knothole" or pc.role == "floor" then
					continue
				end
				local x, y, z = pc.p[1], pc.p[2], pc.p[3]
				local xv, yv = pc.xv, pc.yv
				local zv = {
					xv[2] * yv[3] - xv[3] * yv[2],
					xv[3] * yv[1] - xv[1] * yv[3],
					xv[1] * yv[2] - xv[2] * yv[1],
				}
				local hits = town.overlapBox(
					x,
					y,
					z,
					{ xv, yv, zv },
					{ pc.size[1] / 2 - 0.02, pc.size[2] / 2 - 0.02, pc.size[3] / 2 - 0.02 },
					function(p: BakedWorld.Part): boolean
						-- not its own tree (the bark mesh and the invisible trunk colliders round the cavity), nor any
						-- mesh (BakedWorld takes a MeshPart as its whole box: a tree's is its canopy)
						if own and string.find(p.path, own, 1, true) or p.shape == "box" then
							return false
						end
						return p.visible or p.collide
					end
				)
				local names = {}
				for _, p in hits do
					table.insert(names, p.path)
				end
				t.eq(#names, 0, `{h.id} {pc.role}: {table.concat(names, ", ")}`)
			end
		end
	end)
	t.test(
		"the tunnel camera in every hollow stays in the cavity and off the head (trunk colliders present)",
		function()
			local data = Data.default()
			local town = roblox.deserializeModel(fs.readFile("build/Town.rbxm"))[1]
			HollowShell.build(roblox, layout).Parent = town
			local baked = BakedWorld.fromModel(town)
			local w = baked:motorWorld(data)
			-- what the rig's ray meets inside a hollow: the shell's parts only (Workspace.HollowTrees, an Include filter),
			-- and only what is drawn (it passes the log's invisible thresholds)
			local function cast(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number)
				local inside = {}
				for _, p in baked.containing(ox, oy, oz) do
					inside[p] = true
				end
				local tt, part = baked.raycast(ox, oy, oz, dx, dy, dz, function(p: BakedWorld.Part): boolean
					return not inside[p]
						and string.find(p.path, "HollowTrees", 1, true) ~= nil
						and p.visible
						and (p.collide or p.query)
				end)
				if tt and part then
					return ox + dx * tt, oy + dy * tt, oz + dz * tt
				end
				return nil, nil, nil
			end
			-- inside the bark: in the cavity; the log is open at its ends, so there: within its boards, between its ends
			local function inside(h: HollowLayout.Hollow, x: number, y: number, z: number): boolean
				local c = h.cavities[1]
				local a, b = c.a, c.b
				if a and b then
					local ab = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
					local l2 = ab[1] ^ 2 + ab[2] ^ 2 + ab[3] ^ 2
					local tt = ((x - a[1]) * ab[1] + (y - a[2]) * ab[2] + (z - a[3]) * ab[3]) / l2
					local d2 = (a[1] + ab[1] * tt - x) ^ 2 + (a[2] + ab[2] * tt - y) ^ 2 + (a[3] + ab[3] * tt - z) ^ 2
					return tt >= 0 and tt <= 1 and d2 <= c.radius ^ 2
				end
				return layout.within(h, x, y, z)
			end
			for _, h in layout.hollows do
				local m = h.mouths[1]
				for _, mm in h.mouths do
					if mm.opens == "ground" then
						m = mm
					end
				end
				local ol = math.sqrt(m.out[1] ^ 2 + m.out[3] ^ 2)
				local ox, oz = m.out[1] / ol, m.out[3] / ol
				local x, z = m.x + ox * 6, m.z + oz * 6
				local s = SquirrelMotor.new(x, baked.groundAt(x, z, m.y + 3), z)
				local cam = BakedWorld.cameraYawToward(-ox, -oz)
				local frames, outside, inHead = 0, 0, 0
				BakedWorld.drive(w, s, 60 * 20, function(_f: number, st: SquirrelMotor.State): SquirrelMotor.Input
					return BakedWorld.keys(
						if st.routeId then BakedWorld.cameraYawToward(math.sin(st.yaw), math.cos(st.yaw)) else cam,
						{ fw = 1 }
					)
				end, {
					stop = function(st: SquirrelMotor.State): boolean
						local v = SquirrelMotor.visualPose(st, w)
						local hx, hy, hz = v.x, v.y + 0.35, v.z -- the rig's head: the root and 0.35 over
						if layout.contains(hx, hy, hz) == h.space then
							frames += 1
							local cx, cy, cz = CameraRig.tunnelPoint(
								hx,
								hy,
								hz,
								math.sin(st.yaw),
								math.cos(st.yaw),
								cast,
								layout.keepCamera
							)
							if not inside(h, cx, cy, cz) then
								outside += 1
							end
							if (cx - hx) ^ 2 + (cy - hy) ^ 2 + (cz - hz) ^ 2 < 0.6 ^ 2 then
								inHead += 1
							end
						end
						if h.variant == "knothole" then
							return st.routeId == h.routes[1] and st.railT > 0.99
						elseif h.variant == "log" then
							return st.routeId == nil and frames > 0
						end
						return st.routeId ~= nil and layout.spaceOf(st.routeId) == nil -- out at the top
					end,
				})
				t.truthy(frames >= 10, `{h.id}: {frames} frames inside`)
				t.eq(outside, 0, `{h.id}: frames with the camera outside the cavity`)
				t.eq(inHead, 0, `{h.id}: frames with the camera in the squirrel's head`)
			end
		end
	)
end
