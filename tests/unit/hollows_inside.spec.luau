--!strict
-- Inside the hollow trees as a player sees them (owner D33, from inside H1: "I would like for the view to be more
-- verticle within the tree trunk with the option to run out on those branches ... more textured gnarliness inside the
-- hollow part, but also grainularity"). From within, the trees' bark meshes are not drawn, so the shell
-- (Server/World/HollowShell over Shared/World/HollowLayout) is all there is between a squirrel and the town:
--   the wall is closed: level rays out from the middle line and from off it, at every height from the floor to the
--   roof and every 3 degrees round, all meet a stave, but at the holes, and each hole's opening is no wider than the
--   window and a stave either side (a hole up a trunk is open: its peek looks out through it);
--   the wall wears its tree's bark (the staves, floor and roof each a Grain texture of that tree's own colour map), the
--   staves are many and each its own shade, some dark streaks; the knots are rounded (a crown on the big ones); the
--   climb's ledges are round shelves, not planks; no knot hangs off the wall;
--   the view rests up the hollow: along every run, the eye at rest is below the head looking up (or out of the eyes in
--   a shaft too narrow to stand behind), and neither at rest nor turned any way is the wall ever between the eye and
--   the middle line (the camera never looks through it); the wall, floor and roof are never faded;
--   a hint at every hole up a trunk: Space out onto the branch;
--   the cost: the baked town's parts and the shell's together within the 27,000 part budget.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Data = require("@shared/Data")
local HollowLayout = require("@shared/World/HollowLayout")
local HollowShell = require("@server/World/HollowShell")
local CameraRig = require("@client/Camera/CameraRig")
local Squirrel = require("@client/Controllers/Squirrel")

type Piece = HollowLayout.Piece

-- where a ray (o + d s, s in [0, len]) first meets a Block piece (its slabs), or nil
local function hitBlock(pc: Piece, o: { number }, d: { number }, len: number): number?
	local xv, yv = pc.xv, pc.yv
	local zv = { xv[2] * yv[3] - xv[3] * yv[2], xv[3] * yv[1] - xv[1] * yv[3], xv[1] * yv[2] - xv[2] * yv[1] }
	local lo, hi = 0, len
	for i, ax in { xv, yv, zv } do
		local h = pc.size[i] / 2
		local e = ax[1] * (pc.p[1] - o[1]) + ax[2] * (pc.p[2] - o[2]) + ax[3] * (pc.p[3] - o[3])
		local f = ax[1] * d[1] + ax[2] * d[2] + ax[3] * d[3]
		if math.abs(f) < 1e-9 then
			if math.abs(e) > h then
				return nil
			end
		else
			local a, b = (e - h) / f, (e + h) / f
			if a > b then
				a, b = b, a
			end
			lo, hi = math.max(lo, a), math.min(hi, b)
			if lo > hi then
				return nil
			end
		end
	end
	return lo
end

-- the walls of a hollow (its staves and its holes' linings) with their height spans, for quick rays
type Wall = { pc: Piece, y0: number, y1: number }
local function wallOf(h: HollowLayout.Hollow): { Wall }
	local out: { Wall } = {}
	for _, pc in h.parts do
		if pc.role == "liner" or pc.role == "rim" then
			local y0, y1 = math.huge, -math.huge
			for _, c in HollowLayout.corners(pc) do
				y0, y1 = math.min(y0, c[2]), math.max(y1, c[2])
			end
			table.insert(out, { pc = pc, y0 = y0, y1 = y1 })
		end
	end
	return out
end

local function blocked(walls: { Wall }, o: { number }, d: { number }, len: number): boolean
	local ylo, yhi = math.min(o[2], o[2] + d[2] * len), math.max(o[2], o[2] + d[2] * len)
	for _, w in walls do
		if w.y1 >= ylo and w.y0 <= yhi and hitBlock(w.pc, o, d, len) then
			return true
		end
	end
	return false
end

return function(t)
	local data = Data.default()
	local reg = data:routes()
	local layout = HollowLayout.default() :: HollowLayout.Layout
	local S = HollowLayout.C.stave

	t.test("the wall is closed round every hollow tree but at its holes, each no wider than its window", function()
		local rays, open = 0, 0
		for _, h in layout.hollows do
			if h.trunk == nil then
				continue
			end
			local tr = HollowLayout.trunk(reg :: any, h.trunk :: number)
			local walls = wallOf(h)
			local bottom, top = math.huge, -math.huge
			for _, c in h.cavities do
				bottom, top = math.min(bottom, c.bottom), math.max(top, c.top)
			end
			-- the openings: each mouth's bearing, its heights and the widest it may be (half its chord at the staves)
			local opens = {}
			for _, m in h.mouths do
				local hh = m.y - tr.foot.y
				if m.opens == "ground" then
					table.insert(opens, {
						b = tr.bearingOf(m.x, m.z, bottom - tr.foot.y),
						y0 = -math.huge,
						y1 = bottom + S.door + 0.1,
						half = S.doorWide / 2 + S.width * (1 + S.lap) + 0.1,
					})
				else
					table.insert(opens, {
						b = tr.bearingOf(m.x, m.z, hh),
						y0 = m.y + S.sill - 0.1,
						y1 = m.y + S.head + 0.1,
						half = S.window / 2 + 0.75 * S.width * (1 + S.lap) + 0.1,
					})
				end
			end
			local misses = {}
			local y = bottom + 0.1
			while y < top - 0.1 do
				local hh = y - tr.foot.y
				local ax, _, az = tr.axisAt(hh)
				local bark = tr.bark(hh)
				for _, off in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } } do
					local o = { ax + off[1], y, az + off[2] }
					for deg = 0, 357, 3 do
						local dx, dz = math.sin(math.rad(deg)), math.cos(math.rad(deg))
						-- (out to the bark: where the ray crosses 0.85 of it, the bearing it leaves by)
						local px, pz = o[1] - ax, o[3] - az
						local b = px * dx + pz * dz
						local c = px * px + pz * pz - bark * bark
						local len = -b + math.sqrt(b * b - c)
						rays += 1
						if blocked(walls, o, { dx, 0, dz }, len) then
							continue
						end
						local cc = px * px + pz * pz - (0.85 * bark) ^ 2
						local s = -b + math.sqrt(math.max(0, b * b - cc))
						local qb = tr.bearingOf(o[1] + dx * s, o[3] + dz * s, hh)
						local ok = false
						for _, op in opens do
							local ri = 0.85 * bark
							local half = math.deg(math.asin(math.min(1, op.half / ri)))
							local db = math.abs((qb - op.b + 180) % 360 - 180)
							ok = ok or (y >= op.y0 and y <= op.y1 and db <= half)
						end
						if ok then
							open += 1
						else
							table.insert(
								misses,
								string.format("y %.1f bearing %d from (%d, %d)", hh, deg, off[1], off[2])
							)
						end
					end
				end
				y += 0.35
			end
			t.eq(#misses, 0, `{h.id}: open to the town at {table.concat(misses, "; ", 1, math.min(#misses, 8))}`)
		end
		print(string.format("      %d rays, %d out through a hole", rays, open))
		t.truthy(open > 0, "the holes are open")
	end)

	t.test("every hole up a trunk is an opening in the wall: the peek looks out through it", function()
		local n = 0
		for _, h in layout.hollows do
			if h.trunk == nil then
				continue
			end
			local walls = wallOf(h)
			for _, m in h.mouths do
				if m.opens == "ground" then
					continue
				end
				n += 1
				local ol = math.sqrt(m.out[1] ^ 2 + m.out[3] ^ 2)
				local d = { m.out[1] / ol, 0, m.out[3] / ol }
				for _, up in { 0.4, 0.9, 1.4 } do
					local o = { m.x - d[1] * 0.3, m.y + up, m.z - d[3] * 0.3 }
					t.truthy(not blocked(walls, o, d, (m.depth or 1) + 0.5), `{h.id} {m.name}: {up} over the line`)
				end
				local ex, ey, ez, vx, vy, vz = CameraRig.peekView(m :: any, 0, 0)
				t.truthy(not blocked(walls, { ex, ey, ez }, { vx, vy, vz }, 6), `{h.id} {m.name}: the peek looks out`)
			end
		end
		t.eq(n, 8, "the holes up the trunks")
	end)

	t.test("grain and gnarl: bark on the wall, many staves of many shades, rounded knots, round shelves", function()
		local maps = HollowShell.barkMaps(data:module("TreeArt"))
		local model, report = HollowShell.build(roblox, layout, nil, { bark = maps })
		local h1 = layout.hollow("H1") :: HollowLayout.Hollow
		t.eq(maps[h1.trunk :: number], "rbxassetid://92078120539660", "H1 wears the elm's bark")
		local m1 = model:FindFirstChild("H1") :: any
		local textured, liners = 0, 0
		for _, p in m1:GetChildren() do
			if string.find(p.Name, "^liner") then
				liners += 1
				local g = p:FindFirstChild("Grain")
				if g and g:IsA("Texture") and g.Face == roblox.Enum.NormalId.Front then
					textured += 1
				end
			end
		end
		t.truthy(liners >= 60, `H1's staves ({liners})`)
		t.eq(textured, liners, "every stave wears the bark on its inside face")
		local trees = 0
		for _, h in layout.hollows do
			trees += if h.trunk then 1 else 0
		end
		t.truthy(report.textures >= liners + 2 * trees, `{report.textures} textures`)
		-- the staves: each its own shade, some streaks; the knots: the big ones crowned; the shelves round
		local tones, streaks, crowned, shelves, planks = {}, 0, 0, 0, 0
		local bosses: { Piece } = {}
		for _, pc in h1.parts do
			if pc.role == "liner" then
				tones[string.format("%.2f", pc.tone or 0)] = true
				streaks += if (pc.tone or 0) <= -0.99 then 1 else 0
			elseif pc.role == "burl" then
				table.insert(bosses, pc)
			elseif pc.role == "tread" then
				shelves += if pc.shape == "Cylinder" then 1 else 0
				planks += if pc.shape == "Block" then 1 else 0
			end
		end
		local shades = 0
		for _ in tones do
			shades += 1
		end
		for _, a in bosses do
			for _, b in bosses do
				-- (a crown: on its boss's axis, narrower, its face further in)
				if a ~= b and b.size[2] < a.size[2] and (a.p[2] - b.p[2]) ^ 2 < 1e-6 then
					crowned += 1
				end
			end
		end
		print(
			string.format(
				"      H1: %d staves in %d shades (%d streaks), %d knots (%d crowned), %d round shelves",
				liners,
				shades,
				streaks,
				#bosses,
				crowned,
				shelves
			)
		)
		t.truthy(shades >= 30 and streaks >= 3, "the staves vary, with dark streaks")
		t.truthy(crowned >= 2, "big knots are rounded")
		t.truthy(shelves >= 60 and planks == 0, "the climb runs on round shelves")
		-- no knot stands off the wall: each reaches back to the staves' faces round it
		local tr = HollowLayout.trunk(reg :: any, h1.trunk :: number)
		for _, pc in bosses do
			local hh = pc.p[2] - tr.foot.y
			local ax, _, az = tr.axisAt(hh)
			local back = math.sqrt((pc.p[1] - ax) ^ 2 + (pc.p[3] - az) ^ 2) + pc.size[1] / 2
			local face = math.huge
			for _, w in wallOf(h1) do
				if w.pc.role == "liner" and hh + tr.foot.y >= w.y0 and hh + tr.foot.y <= w.y1 then
					local px, pz = w.pc.p[1] - ax, w.pc.p[3] - az
					face = math.min(face, math.sqrt(px * px + pz * pz) - w.pc.size[3] / 2)
				end
			end
			t.truthy(back >= face - 0.35, `a knot at {hh} stops {face - back} short of the wall`)
		end
	end)

	t.test("the view rests up the hollow, and the wall is never between the eye and the middle", function()
		local H = CameraRig.HOLLOW
		local rested, first, looks = 0, 0, 0
		for _, h in layout.hollows do
			if h.trunk == nil then
				continue
			end
			local tr = HollowLayout.trunk(reg :: any, h.trunk :: number)
			local walls = wallOf(h)
			for _, rid in h.routes do
				local r = reg:get(rid) :: any
				for k = 0, 40 do
					local p = reg:pointAt(r, k / 40)
					local d = reg:tangentAt(r, math.clamp(k / 40, 0.01, 0.99))
					local dl = math.sqrt(d.x * d.x + d.z * d.z)
					local lx, lz = if dl > 0.05 then d.x / dl else 0, if dl > 0.05 then d.z / dl else 1
					local hx, hy, hz = p.x, p.y + 0.7, p.z
					if layout.contains(hx, hy, hz) ~= h.space then
						continue
					end
					local mx, mz = nil :: number?, nil :: number?
					for _, c in h.cavities do
						if hy >= c.bottom - 0.5 and hy <= c.top then
							mx, mz = c.x, c.z
						end
					end
					for _, yaw in { 0, 1.2, math.pi, -2 } do
						for _, pitch in { H.rest, H.pitchMin, 0, H.pitchMax } do
							local ex, ey, ez, vx, vy, vz, fp =
								CameraRig.hollowView(hx, hy, hz, lx, lz, yaw, pitch, layout.keepCamera, mx, mz)
							looks += 1
							if yaw == 0 and pitch == H.rest then
								if fp then
									first += 1
								else
									rested += 1
									t.truthy(ey < hy, `{h.id} {rid} t {k / 40}: the eye at rest below the head`)
								end
								t.truthy(vy >= math.sin(H.rest) - 1e-6, "looking up the hollow")
							end
							-- the wall is not between the middle line and the eye, nor between the eye and the head
							local hh = ey - tr.foot.y
							local ax, _, az = tr.axisAt(hh)
							local o = { ax, ey, az }
							local to = { ex - ax, 0, ez - az }
							local tl = math.sqrt(to[1] ^ 2 + to[3] ^ 2)
							if tl > 1e-3 then
								t.truthy(
									not blocked(walls, o, { to[1] / tl, 0, to[3] / tl }, tl),
									`{h.id} {rid} t {k / 40} yaw {yaw} pitch {pitch}: the eye beyond the wall`
								)
							end
							-- (a head still in the ground hole's opening, walking in, is in the wall itself)
							local eh = { hx - ex, hy - ey, hz - ez }
							local el = math.sqrt(eh[1] ^ 2 + eh[2] ^ 2 + eh[3] ^ 2)
							local headIn = false
							for _, c in h.cavities do
								headIn = headIn
									or (
										hy >= c.bottom
										and hy <= c.top
										and (hx - c.x) ^ 2 + (hz - c.z) ^ 2 <= c.radius ^ 2
									)
							end
							if el > 1e-3 and headIn then
								t.truthy(
									not blocked(walls, { ex, ey, ez }, { eh[1] / el, eh[2] / el, eh[3] / el }, el),
									`{h.id} {rid} t {k / 40}: the wall between the eye and the head`
								)
							end
							local _ = vx + vz
						end
					end
				end
			end
		end
		print(string.format("      %d looks; at rest %d behind and below, %d out of the eyes", looks, rested, first))
		t.truthy(rested > 100, "behind and below the squirrel, looking up")
		-- the wall, the floor and the roof are never faded; the growths in the way may be
		for _, name in { "liner3", "floor1", "roof9", "log2", "knothole4" } do
			t.truthy(not CameraRig.fades(name), name)
		end
		for _, name in { "tread12", "root40", "burl7", "rim3", "shelf2" } do
			t.truthy(CameraRig.fades(name), name)
		end
	end)

	t.test("a hint at every hole up a trunk: Space out onto the branch", function()
		local n = 0
		for _, h in layout.hollows do
			for _, m in h.mouths do
				local said = Squirrel.holeHint(m :: any)
				if m.opens == "ground" then
					t.eq(said, nil, `{h.id} ground hole`)
				else
					n += 1
					t.truthy(said and string.find(said, "Space: out onto the branch", 1, true), `{h.id} {m.name}`)
					-- (said where the body is: the same lookup the camera's peek uses)
					local at = layout.peekAt(m.x, m.y, m.z)
					t.truthy(at and at.route == m.route and at.t == m.t, `{h.id} {m.name}: found from the climb`)
				end
			end
		end
		t.eq(n, 8)
		t.eq(Squirrel.holeHint(nil), nil)
	end)

	t.test("the cost: the town's parts and the shell's within the part budget", function()
		t.truthy(fs.isFile("build/Town.rbxm"), "build/Town.rbxm (lune run tools/bake/main.luau)")
		local town = roblox.deserializeModel(fs.readFile("build/Town.rbxm"))[1]
		local baked = town:GetAttribute("PartCount") :: number
		local _, report = HollowShell.build(roblox, layout)
		local cyl = 0
		for _, h in layout.hollows do
			for _, pc in h.parts do
				cyl += if pc.shape == "Cylinder" then 1 else 0
			end
		end
		print(
			string.format(
				"      the town %d parts, the hollows' shell %d (%d cylinders), %d lights: %d",
				baked,
				report.parts,
				cyl,
				report.lights,
				baked + report.parts
			)
		)
		t.truthy(baked + report.parts <= 27000, "within 27,000 parts")
	end)
end
