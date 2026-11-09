--!strict
-- ServerScriptService.Server.Paintball.Layout
-- The S18 greybox of the TV-station arena (D29; W3c builds the real one): a 120 x 120 stud box of
-- five floors 14 studs apart, a 30 x 30 atrium through floors 1-4, four pillars per floor, outer
-- walls, a roof, and one stairwell per storey in rotating corners. Produces the flat box list the
-- projectile sim collides with and the waypoint graph the bots walk.
-- Interface: build() -> Layout

export type Waypoint = { x: number, z: number }
export type Stair = { floor: number, x0: number, z0: number, x1: number, z1: number } -- floor -> floor + 1
export type Layout = {
	boxes: { number },
	floors: number,
	floorHeight: number,
	half: number,
	atrium: number,
	waypoints: { [number]: { Waypoint } }, -- by floor 0..floors-1
	stairs: { Stair },
}

local Layout = {}

function Layout.build(): Layout
	local floors, h, half, atrium = 5, 14, 60, 15
	local boxes: { number } = {}
	local function box(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number)
		table.insert(boxes, math.min(x0, x1))
		table.insert(boxes, math.min(y0, y1))
		table.insert(boxes, math.min(z0, z1))
		table.insert(boxes, math.max(x0, x1))
		table.insert(boxes, math.max(y0, y1))
		table.insert(boxes, math.max(z0, z1))
	end
	box(-half, -1, -half, half, 0, half) -- ground slab
	for f = 1, floors - 1 do
		local y = f * h
		box(-half, y - 1, -half, half, y, -atrium)
		box(-half, y - 1, atrium, half, y, half)
		box(-half, y - 1, -atrium, -atrium, y, atrium)
		box(atrium, y - 1, -atrium, half, y, atrium)
	end
	box(-half, floors * h, -half, half, floors * h + 1, half) -- roof
	box(-half - 1, -1, -half, -half, floors * h + 1, half)
	box(half, -1, -half, half + 1, floors * h + 1, half)
	box(-half, -1, -half - 1, half, floors * h + 1, -half)
	box(-half, -1, half, half, floors * h + 1, half + 1)
	for f = 0, floors - 1 do
		for _, c in { { -35, -35 }, { 35, -35 }, { 35, 35 }, { -35, 35 } } do
			box(c[1] - 2, f * h, c[2] - 2, c[1] + 2, f * h + h - 1, c[2] + 2)
		end
	end
	local waypoints: { [number]: { Waypoint } } = {}
	for f = 0, floors - 1 do
		local list = {}
		for _, x in { -48, -24, 0, 24, 48 } do
			for _, z in { -48, -24, 0, 24, 48 } do
				if f >= 1 and math.abs(x) <= atrium + 2 and math.abs(z) <= atrium + 2 then
					continue
				end
				table.insert(list, { x = x, z = z })
			end
		end
		waypoints[f] = list
	end
	local corners = { { -52, -52 }, { 52, -52 }, { 52, 52 }, { -52, 52 } }
	local stairs: { Stair } = {}
	for f = 0, floors - 2 do
		local c = corners[f % 4 + 1]
		-- 14 studs up over a 16-stud run along the wall, towards the middle of that wall
		table.insert(stairs, { floor = f, x0 = c[1], z0 = c[2], x1 = c[1] - math.sign(c[1]) * 16, z1 = c[2] })
	end
	return {
		boxes = boxes,
		floors = floors,
		floorHeight = h,
		half = half,
		atrium = atrium,
		waypoints = waypoints,
		stairs = stairs,
	}
end

return Layout
