--!strict
-- ReplicatedStorage.Shared.Rides.SkyLiftCountry
-- What stands on the farmland under the sky lift's line that a walker cannot pass (tools/bake/skylift/Countryside
-- draws it; World/WalkWay keeps the town's people off it), and the shelter on Lift Road (SHELTER): the hedgerows round the fields, the two dry-stone walls
-- across the line, the paddock's rails, and the farm's barn, silo, farmhouse and hay bales, and the lift's
-- maintenance hut. All in the line's own frame (frame(): u studs along the centre line from the base station's
-- mouth toward the summit, v studs to the right of a cabin going up) as the bake lays them out; the bake reads the
-- same numbers from here. The field strips, the lane and the trail are surfaces (walked on); the brook and the
-- pond do not collide; the trees' trunks are trees.
-- Interface: frame() -> (bx, bz, ux, uz, rx, rz); at(u, v) -> (x, z); LINES { u0, v0, u1, v1, w } (a wall along a
--   line, w thick); BLOCKS { u, v, yaw, w, d } (a footprint w across and d deep, turned yaw from the line); hut()
--   -> (u, v) (the maintenance hut's centre, beside the farm lane under tower 3)
-- Pure (the lift's stations and towers from Shared/Rides/SkyLift); studs.

local SkyLift = require("./SkyLift")

local SkyLiftCountry = {}

-- the hedgerows: between the fields and the line, and at the fields' two ends
-- (h: height, lift: the middle's height over the ground, as the bake draws them)
SkyLiftCountry.HEDGES = table.freeze({
	table.freeze({ u0 = 108, v0 = -32, u1 = 340, v1 = -32, w = 2.4, h = 3.2, lift = 2.3 }),
	table.freeze({ u0 = 108, v0 = -34, u1 = 108, v1 = -154, w = 2.6, h = 3.2, lift = 2.6 }),
	table.freeze({ u0 = 340, v0 = -34, u1 = 340, v1 = -154, w = 2.6, h = 3.2, lift = 2.6 }),
})
-- the dry-stone walls across the line
SkyLiftCountry.WALLS = table.freeze({
	table.freeze({ u0 = 92, v0 = -30, u1 = 92, v1 = 66, w = 1.3, h = 2.2, lift = 1.5 }),
	table.freeze({ u0 = 520, v0 = -96, u1 = 520, v1 = 50, w = 1.3, h = 2.2, lift = 1.5 }),
})
-- the paddock: its corners (posts every 15 and two rails a side)
SkyLiftCountry.PADDOCK = table.freeze({ u0 = 412, u1 = 470, v0 = -78, v1 = -112 })
-- the farm's buildings and its hay: centre, turn from the line, width (across) and depth
SkyLiftCountry.BARN = table.freeze({ u = 400, v = -120, yaw = 0, w = 26, d = 15 })
SkyLiftCountry.SILO = table.freeze({ u = 372, v = -128, r = 3.5 })
SkyLiftCountry.FARMHOUSE = table.freeze({ u = 436, v = -150, yaw = math.pi / 2, w = 14, d = 11 })
SkyLiftCountry.HAY = table.freeze({ u0 = 420, du = 9, n = 4, v = -128, dv = -4, r = 1.4 })
SkyLiftCountry.HUT = table.freeze({ du = 27, v = -18, w = 8, d = 6 }) -- du: along the line past tower 3
-- the trees (owner D35: every tree climbable; Shared/World/TreeShapes grows a trunk route in each): the hedgerow oaks
-- (18-24 tall, crowns 12-16 across) and the orchard's apples, three rows of four beyond the trail (9-11 tall, crowns
-- 7-8.5 across): (u, v) as the bake stands them (its heights and crowns are seeded there)
SkyLiftCountry.OAKS = table.freeze({ { 108, -32 }, { 193, -32 }, { 265, -32 }, { 340, -96 }, { 108, -150 } })
SkyLiftCountry.ORCHARD = table.freeze((function()
	local out = {}
	for i = 0, 3 do
		for j = 0, 2 do
			table.insert(out, table.freeze({ 205 + i * 22 + (j % 2) * 8, 112 + j * 20 }))
		end
	end
	return out
end)())
-- the roofed bench with the map board on Lift Road's east verge (world studs; tools/bake/skylift/Signs builds it):
-- a box `half` studs each way round its spot
SkyLiftCountry.SHELTER = table.freeze({ x = -690.6, z = -712, half = 4.5 })

export type Line = { u0: number, v0: number, u1: number, v1: number, w: number, h: number?, lift: number? }
export type Block = { u: number, v: number, yaw: number, w: number, d: number }

function SkyLiftCountry.frame(): (number, number, number, number, number, number)
	local st = SkyLift.stations()
	local bx, bz = st.base.mouth.x, st.base.mouth.z
	local dx, dz = st.summit.mouth.x - bx, st.summit.mouth.z - bz
	local l = math.sqrt(dx * dx + dz * dz)
	local ux, uz = dx / l, dz / l
	return bx, bz, ux, uz, -uz, ux
end

function SkyLiftCountry.at(u: number, v: number): (number, number)
	local bx, bz, ux, uz, rx, rz = SkyLiftCountry.frame()
	return bx + ux * u + rx * v, bz + uz * u + rz * v
end

-- the hut's centre in the line's frame (tower 3's distance along the line, plus HUT.du)
function SkyLiftCountry.hut(): (number, number)
	local t3 = SkyLift.towers()[3]
	local bx, bz, ux, uz = SkyLiftCountry.frame()
	local u3 = (t3.x - bx) * ux + (t3.z - bz) * uz
	return u3 + SkyLiftCountry.HUT.du, SkyLiftCountry.HUT.v
end

-- everything a walker cannot pass, as lines and blocks
function SkyLiftCountry.obstacles(): ({ Line }, { Block })
	local lines: { Line } = {}
	for _, l in SkyLiftCountry.HEDGES do
		table.insert(lines, l)
	end
	for _, l in SkyLiftCountry.WALLS do
		table.insert(lines, l)
	end
	local p = SkyLiftCountry.PADDOCK
	local corners = { { p.u0, p.v0 }, { p.u1, p.v0 }, { p.u1, p.v1 }, { p.u0, p.v1 } }
	for i = 1, 4 do
		local a, b = corners[i], corners[i % 4 + 1]
		table.insert(lines, { u0 = a[1], v0 = a[2], u1 = b[1], v1 = b[2], w = 0.6 })
	end
	local blocks: { Block } = {
		SkyLiftCountry.BARN,
		SkyLiftCountry.FARMHOUSE,
		{ u = SkyLiftCountry.SILO.u, v = SkyLiftCountry.SILO.v, yaw = 0, w = 7, d = 7 },
	}
	local h = SkyLiftCountry.HAY
	for k = 0, h.n - 1 do
		table.insert(
			blocks,
			{ u = h.u0 + k * h.du, v = h.v + (k % 2) * h.dv, yaw = 0, w = 2 * h.r + 1, d = 2 * h.r + 1 }
		)
	end
	local hu, hv = SkyLiftCountry.hut()
	table.insert(blocks, { u = hu, v = hv, yaw = 0, w = SkyLiftCountry.HUT.w, d = SkyLiftCountry.HUT.d })
	return lines, blocks
end

return SkyLiftCountry
