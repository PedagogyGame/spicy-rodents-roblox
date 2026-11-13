--!strict
-- Minigames/Pool/Furniture: the cue tables as furniture, the one source the bake, the server and the clients
-- read (C18): a table point to the world and back at any yaw, a home of its own for every potted ball, a
-- stance outside the table behind the ball, and the names the server and the clients find parts by.
local Furniture = require("@shared/Minigames/Pool/Furniture")
local Tables = require("@shared/Minigames/Pool/Tables")

return function(t)
	local pool, bumper = Tables.eightBall(), Tables.bumper()

	t.test("a table point goes to the world and back, at any yaw of the site", function()
		local station = { x = 12.5, d = -7.25 }
		for _, yaw in { 0, math.pi / 2, 2.1, -math.pi } do
			local place = { x = 300, z = -120, floorY = 4, yaw = yaw }
			local wx, wy, wz = Furniture.world(place, station, 1.3, 0.17, -4.2)
			local x, y, z = Furniture.fromWorld(place, station, wx, wy, wz)
			t.near(x, 1.3, 1e-9)
			t.near(y, 0.17, 1e-9)
			t.near(z, -4.2, 1e-9)
			t.near(wy, place.floorY + Furniture.BED_Y + 0.17, 1e-9)
		end
	end)

	t.test("POOL-S5 every potted ball has a home of its own, under the rail, never on the cloth", function()
		local _, hl = Furniture.outer(pool)
		local seen: { [string]: boolean } = {}
		for id = 1, 15 do
			local x, y, z = Furniture.home(pool, id)
			local key = `{x},{z}`
			t.falsy(seen[key], `ball {id} shares a home`)
			seen[key] = true
			t.truthy(y < 0 and z > hl, `ball {id} lies in the tray outside the foot rail`)
		end
		local _, bl = Furniture.outer(bumper)
		for id = 1, 10 do
			local _, y, z = Furniture.home(bumper, id)
			t.truthy(y < 0 and math.abs(z) > bl, `bumper ball {id} lies in a tray outside an end rail`)
			-- a side's balls go to the end they are shot at (red, 1 to 5: the foot end)
			t.eq(z > 0, id <= 5)
		end
		-- the cue ball (or a ball kept out of the game) is out of sight inside the table
		local _, cy = Furniture.off(pool, 0)
		t.truthy(cy < -Furniture.WELL_DEPTH)
	end)

	t.test("POOL-S2 a player stands behind the ball on the line of the shot, on the ring outside the table", function()
		local hw, hl = Furniture.outer(pool)
		for _, case in { { 0, -2, 0 }, { 1.5, 3.8, 2.4 }, { -2.2, 0.1, -1.2 }, { 0, 0, math.pi / 2 } } do
			local x, z, angle = case[1], case[2], case[3]
			local sx, sz = Furniture.stand(pool, x, z, angle)
			t.truthy(math.abs(sx) > hw - 1e-9 or math.abs(sz) > hl - 1e-9, "outside the table")
			t.truthy(math.abs(sx) <= hw + Furniture.STAND + 1e-9 and math.abs(sz) <= hl + Furniture.STAND + 1e-9)
			-- behind the ball: the shot's line runs from the stance through the ball
			local dx, dz = math.sin(angle), math.cos(angle)
			local bx, bz = x - sx, z - sz
			t.truthy(bx * dx + bz * dz > 0, "the ball is ahead of the player")
			t.near(bx * dz - bz * dx, 0, 1e-6, "on the line")
		end
	end)

	t.test("names the server and the clients find: one model per table, a ball by its number", function()
		t.eq(Furniture.modelName("pool", 2), "Pool2")
		t.eq(Furniture.modelName("bumper_pool", 1), "BumperPool")
		t.eq(Furniture.ballName(0), "CueBall")
		t.eq(Furniture.ballName(11), "Ball11")
		local rgb, striped = Furniture.ballColor("eightball", 11)
		t.truthy(striped)
		t.deepEq(rgb, Furniture.POOL_COLORS[3])
		t.eq(#Furniture.sights(pool), 18)
		t.eq(#Furniture.sights(bumper), 0)
	end)
end
