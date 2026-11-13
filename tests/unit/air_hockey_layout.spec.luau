--!strict
-- Air hockey's place in the world (Shared/Minigames/AirHockey/Layout) and the table the bake builds from it
-- (tools/bake/games/AirHockey), in memory with the same code tools/bake/attractions.luau runs.
--   One source: what is drawn is what is simulated. The cushions' faces, the goal's posts, the puck and the
--   mallets of the baked table are the simulation's own numbers at the pool tables' scale, and the pieces stand
--   where a match starts them.
--   Where it stands: along the back wall of the bowling alley's games room, inside the walls, with a player's
--   standing room at each end, clear of every other game's furniture and of where its players stand, and with
--   an aisle left to walk past.
--   The views: both first-person eyes and the view from above are inside the room and under its ceiling.
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Layout = require("@shared/Minigames/AirHockey/Layout")
local Sim = require("@shared/Minigames/AirHockey/Sim")
local Games = require("@shared/Minigames/Games")
local Bake = require("../../tools/bake/games/AirHockey")
local Kit = require("../../tools/bake/alley/Kit")
local GamesRoom = require("../../tools/bake/alley/GamesRoom")

local FLAT: AlleyLayout.Place = { x = 0, z = 0, floorY = 0, yaw = 0 }
local TURNED: AlleyLayout.Place = { x = 1300, z = -420, floorY = 16.5, yaw = 0.6 }
local K = Layout.SCALE
-- (the engine's vectors are single precision: a baked size or place is good to a tenth of a millimetre)

type Box = { x0: number, x1: number, d0: number, d1: number }

-- the floor a part covers, in the alley's frame (the room is built at FLAT: local X is world X, local D is -Z)
local function floorOf(part: any, into: Box?): Box
	local c, s = part.CFrame, part.Size
	local ex = math.abs(c.RightVector.X) * s.X + math.abs(c.UpVector.X) * s.Y + math.abs(c.LookVector.X) * s.Z
	local ez = math.abs(c.RightVector.Z) * s.X + math.abs(c.UpVector.Z) * s.Y + math.abs(c.LookVector.Z) * s.Z
	local b: Box = into or { x0 = math.huge, x1 = -math.huge, d0 = math.huge, d1 = -math.huge }
	b.x0 = math.min(b.x0, c.Position.X - ex / 2)
	b.x1 = math.max(b.x1, c.Position.X + ex / 2)
	b.d0 = math.min(b.d0, -c.Position.Z - ez / 2)
	b.d1 = math.max(b.d1, -c.Position.Z + ez / 2)
	return b
end

-- how far apart two boxes are on the floor (0: they touch or overlap)
local function gap(a: Box, b: Box): number
	local dx = math.max(a.x0 - b.x1, b.x0 - a.x1, 0)
	local dd = math.max(a.d0 - b.d1, b.d0 - a.d1, 0)
	return math.sqrt(dx * dx + dd * dd)
end

local function builtRoom(): any
	local kit = Kit.new(roblox, FLAT)
	local root = roblox.Instance.new("Model")
	GamesRoom.build(kit, root)
	return root:FindFirstChild("GamesRoom")
end

return function(t)
	t.test(
		"the scale is the pool tables': a 2.54 m bed is their 10.8 stud felt, and the bed is a hand's height",
		function()
			t.near(Layout.SCALE * 2.54, 10.8, 1e-9)
			t.near(Layout.height(Layout.BED_Z), Layout.BED_Y, 1e-9)
			t.near(Layout.height(0), 0, 1e-9)
			-- above the bed a metre is a metre of the table; below it the cabinet is shortened, never stretched
			t.near(Layout.height(Layout.BED_Z + 0.1) - Layout.BED_Y, 0.1 * K, 1e-9)
			t.truthy(Layout.BED_Y / Layout.BED_Z < K, "the cabinet is shortened to this town's table height")
			t.truthy(math.abs(Layout.BED_Y - 3.0) <= 0.25, "about the pool felt's height (3.0)")
		end
	)

	t.test("a point of the table goes to the world and back, wherever the alley stands", function()
		for _, place in { FLAT, TURNED } do
			for _, p in { { 0, 0 }, { 0.3, -0.8 }, { -0.556, 1.106 }, { 0.62, -1.17 } } do
				local wx, wy, wz = Layout.toWorld(place, p[1], p[2])
				local x, y = Layout.fromWorld(place, wx, wz)
				t.near(x, p[1], 1e-9)
				t.near(y, p[2], 1e-9)
				t.near(wy, place.floorY + Layout.BED_Y, 1e-9)
			end
		end
		-- not mirrored: from Glacier's end (looking along +y), the model's +x is to the right
		local ox, _, oz = Layout.toWorld(FLAT, 0, 0)
		local fx, _, fz = Layout.toWorld(FLAT, 0, 1)
		local rx, _, rz = Layout.toWorld(FLAT, 1, 0)
		local forward = roblox.Vector3.new(fx - ox, 0, fz - oz)
		local right = roblox.Vector3.new(rx - ox, 0, rz - oz)
		t.truthy(forward:Cross(roblox.Vector3.new(0, 1, 0)):Dot(right) > 0, "the printed bed is not mirrored")
	end)

	t.test("the baked table is the simulation's table: cushions, goals, posts, puck and mallets", function()
		local room = builtRoom()
		local m = room:FindFirstChild(Layout.MODEL)
		t.truthy(m, "GamesRoom.AirHockey")
		t.truthy(room:FindFirstChild(Layout.MODEL .. "EmberEnd"), "the Ember end's own mat")
		t.truthy(Bake.PARTS > 100 and Bake.PARTS <= 150, `{Bake.PARTS} parts in the table`)
		-- where the cushions' faces are, the puck's centre is turned back one radius before
		local inner: Box = { x0 = -math.huge, x1 = math.huge, d0 = -math.huge, d1 = math.huge }
		local posts, mouths = 0, 0
		for _, part in m:GetChildren() do
			if not part:IsA("BasePart") then
				continue
			end
			local b = floorOf(part)
			local cx, cd = Layout.CENTRE.x, Layout.CENTRE.d
			if part.Name == "SideCushion" then
				if (b.d0 + b.d1) / 2 > cd then
					inner.d1 = math.min(inner.d1, b.d0)
				else
					inner.d0 = math.max(inner.d0, b.d1)
				end
			elseif part.Name == "EndCushion" then
				if (b.x0 + b.x1) / 2 > cx then
					inner.x1 = math.min(inner.x1, b.x0)
				else
					inner.x0 = math.max(inner.x0, b.x1)
				end
				-- each end has two cushions with the goal's width between them
				local nearGoal = math.min(math.abs(b.d0 - cd), math.abs(b.d1 - cd))
				t.near(nearGoal, Sim.GOAL * K, 2e-4, "an end cushion stops at the goal post")
			elseif part.Name == "GoalPost" then
				posts += 1
				local x, y = Layout.fromLocal(part.CFrame.Position.X, -part.CFrame.Position.Z)
				t.near(math.abs(x), Sim.GOAL, 2e-4)
				t.near(math.abs(y), Sim.HALF_LENGTH, 2e-4)
				t.near(part.Size.Y, 2 * Sim.POST_RADIUS * K, 2e-4, "a post's diameter")
			elseif part.Name == "GoalMouth" then
				mouths += 1
				t.truthy(b.d1 - b.d0 <= 2 * Sim.GOAL * K, "the mouth is no wider than the goal")
			elseif part.Name == "Bed" then
				t.near(b.x1 - b.x0, 2 * Sim.HALF_LENGTH * K, 2e-4, "the bed's length")
				t.near(b.d1 - b.d0, 2 * Sim.HALF_WIDTH * K, 2e-4, "the bed's width")
				t.near((b.x0 + b.x1) / 2, cx, 2e-4)
				t.near((b.d0 + b.d1) / 2, cd, 2e-4)
				local top = part.CFrame.Position.Y + part.Size.Y / 2
				t.truthy(top <= Layout.BED_Y and top > Layout.BED_Y - 0.05, "the bed is just under the playing surface")
			end
		end
		t.eq(posts, 4)
		t.eq(mouths, 2)
		t.near(inner.x1 - Layout.CENTRE.x, Sim.HALF_LENGTH * K, 2e-4, "Ember's end cushion")
		t.near(Layout.CENTRE.x - inner.x0, Sim.HALF_LENGTH * K, 2e-4, "Glacier's end cushion")
		t.near(inner.d1 - Layout.CENTRE.d, Sim.HALF_WIDTH * K, 2e-4, "a side cushion")
		t.near(Layout.CENTRE.d - inner.d0, Sim.HALF_WIDTH * K, 2e-4, "the other side cushion")
		-- the pieces: small Models with their pivot on their own axis, standing where a match starts them
		local function piece(name: string, x: number, y: number, radius: number, body: string)
			local p = m:FindFirstChild(name)
			t.truthy(p and p:IsA("Model") and p.PrimaryPart, name)
			-- (a Model with a PrimaryPart pivots on it)
			local at = p.PrimaryPart.CFrame.Position
			local wx, _, wz = Layout.toWorld(FLAT, x, y)
			t.near(at.X, wx, 2e-4, name)
			t.near(at.Z, wz, 2e-4, name)
			local disc = p:FindFirstChild(body)
			t.near(disc.Size.Y, 2 * radius * K, 2e-4, `{name}'s diameter is the simulation's`)
			t.truthy(
				disc.CFrame.Position.Y - disc.Size.X / 2 >= Layout.BED_Y - 1e-3,
				`{name} rides on the bed, not in it`
			)
			for _, part in p:GetChildren() do
				t.eq(part.CanCollide, false, `{name}.{part.Name} is moved by script`)
				t.eq(part.Anchored, true)
			end
		end
		piece(Layout.PUCK, Layout.HOME_PUCK[1], Layout.HOME_PUCK[2], Sim.PUCK_RADIUS, "Disc")
		for side = 0, 1 do
			local home = Layout.HOME_MALLET[side]
			piece(Layout.MALLETS[side], home[1], home[2], Sim.PADDLE_RADIUS, "Base")
		end
		local start = Sim.new()
		t.eq(Layout.HOME_MALLET[0][2], start.p0y)
		t.eq(Layout.HOME_MALLET[1][2], start.p1y)
		-- the board the server writes the score on
		local board = m:FindFirstChild(Layout.SCORE)
		local labels = 0
		for _, d in board:GetDescendants() do
			if d.Name == "Score" and d:IsA("TextLabel") then
				labels += 1
			end
		end
		t.truthy(labels >= 1, "ScoreBoard has its Score label")
		-- and each end's own score, lit in the bed: on the playing surface in that end's corner, clear of the
		-- defensive arc and the touchline, and inside that player's first person view (which the board on the
		-- wall is not) even on a screen as narrow as 4:3
		local sp = Layout.SCORE_PRINT
		for side = 0, 1 do
			local s = if side ~= 0 then 1 else -1
			local plate = m:FindFirstChild(Layout.SCORE_PRINTS[side])
			t.truthy(plate, `{Layout.SCORE_PRINTS[side]} is baked`)
			local found = 0
			for _, d in plate:GetDescendants() do
				if d.Name == "Score" and d:IsA("TextLabel") then
					found += 1
					t.eq(d.Text, "", "blank until a match is on")
				end
			end
			t.eq(found, 1)
			local X, Y, D = Layout.toLocal(sp.x, s * sp.y)
			local at = plate.CFrame.Position
			t.near(at.X, X, 1e-3)
			t.near(at.Z, -D, 1e-3)
			t.truthy(at.Y <= Y + 1e-6 and at.Y > Y - 0.02, "in the bed, under the puck")
			t.truthy(sp.x - sp.w / 2 > 0.29 + 0.02, "clear of the defensive arc")
			t.truthy(sp.x + sp.w / 2 < 0.596 - 0.02, "inside the touchline")
			t.truthy(
				sp.y + sp.h / 2 < Sim.HALF_LENGTH - 0.05 and sp.y - sp.h / 2 > 0.76 + 0.02,
				"between the hash and the end"
			)
			-- through that end's first person camera
			local cam = Layout.camera(side, false)
			local fx, fy, fz = 0 - cam.eye[1], cam.target[2] - cam.eye[2], cam.target[3] - cam.eye[3]
			local fl = math.sqrt(fx * fx + fy * fy + fz * fz)
			fy, fz = fy / fl, fz / fl
			local half = math.tan(math.rad(cam.fov / 2))
			for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
				local px = sp.x + corner[1] * sp.w / 2
				local py = s * sp.y + corner[2] * sp.h / 2
				local vx, vy, vz = px - cam.eye[1], py - cam.eye[2], Layout.BED_Z - cam.eye[3]
				local depth = vy * fy + vz * fz
				-- (the camera's right is the model's x, turned for the Ember end; its up is across the forward)
				local up = (vz * math.abs(fy) - vy * fz * (if fy > 0 then 1 else -1)) / depth
				t.truthy(depth > 0.3, "in front of the eye")
				t.truthy(
					math.abs(up) < half * 0.92,
					`end {side}: the score print is inside the view, top to bottom ({up})`
				)
				t.truthy(math.abs(vx / depth) < half * (4 / 3) * 0.92, `end {side}: and side to side`)
			end
		end
	end)

	t.test(
		"two prompts, one table: each end's is behind its end rail, and the Ember end's joins the Glacier end's",
		function()
			t.eq(#Layout.stations({}), 0, "no alley, no table")
			local stations = Layout.stations({ bowling_alley = FLAT })
			t.eq(#stations, 2)
			t.eq(stations[1].id, Layout.STATION)
			t.eq(stations[1].joins, nil)
			t.eq(stations[2].id, Layout.STATION_EMBER)
			t.eq(stations[2].joins, Layout.STATION)
			for i, st in stations do
				local side = i - 1
				t.eq(Layout.sideOfStation(st.id), side)
				local stand = Layout.standing(side)
				t.truthy(
					st.x > stand.x0 and st.x < stand.x1 and st.d > stand.d0 and st.d < stand.d1,
					"in the standing room"
				)
				local _, y = Layout.fromLocal(st.x, st.d)
				t.truthy(y * (if side == 0 then -1 else 1) > Layout.HALF_LENGTH, "behind that end's rail")
				-- a seated player may move about their end without being taken off
				t.truthy((st.reach or 70) >= 20)
			end
			t.eq(Layout.sideOfStation("pool_1"), nil)
		end
	)

	t.test(
		"where it stands: inside the room, clear of every other game's furniture and players, an aisle left",
		function()
			local room = builtRoom()
			local foot = Layout.footprint()
			local mine: { Box } = { foot, Layout.standing(0), Layout.standing(1) }
			-- inside the walls (the room: AlleyLayout.GAME_ROOM_X0 .. X1 across, FRONT_D .. GAME_ROOM_D1 deep; the
			-- partition and the back wall are 0.3 thick inside)
			for _, b in mine do
				t.truthy(
					b.x0 >= AlleyLayout.GAME_ROOM_X0 + 0.5 and b.x1 <= AlleyLayout.X1 - 0.5,
					"between the side walls"
				)
				t.truthy(
					b.d1 <= AlleyLayout.GAME_ROOM_D1 - 0.5 and b.d0 >= AlleyLayout.FRONT_D + 0.5,
					"inside the back wall"
				)
				-- the openings into the room from the hall (AlleyLayout.OPENINGS): nothing of the table is in front of
				-- them, with 6 studs to spare
				for _, o in AlleyLayout.OPENINGS do
					if o.axis == "d" and o.at == AlleyLayout.GAME_ROOM_X0 and table.find(o.between, "games_room") then
						t.truthy(b.d0 >= o.b + 6 or b.d1 <= o.a - 6, `well clear of the doorway {o.id}`)
					end
				end
			end
			-- what the bake built is inside the footprint and the two standing rooms (the score board and the lamps
			-- are on the wall and the ceiling above head height)
			for _, name in { Layout.MODEL, Layout.MODEL .. "EmberEnd" } do
				for _, part in room:FindFirstChild(name):GetDescendants() do
					if part:IsA("BasePart") and part.CFrame.Position.Y - part.Size.Y / 2 < 6.5 then
						local b = floorOf(part)
						local inside = false
						for _, own in mine do
							if
								b.x0 >= own.x0 - 0.02
								and b.x1 <= own.x1 + 0.02
								and b.d0 >= own.d0 - 0.02
								and b.d1 <= own.d1 + 0.02
							then
								inside = true
							end
						end
						t.truthy(inside, `{part.Name} is outside the table's footprint and standing rooms`)
					end
				end
			end
			-- every other game's furniture in the room: none within 3.5 studs of the table or of where its players
			-- stand (two people can pass between)
			local others = 0
			for _, child in room:GetChildren() do
				if not child:IsA("Model") or string.sub(child.Name, 1, #Layout.MODEL) == Layout.MODEL then
					continue
				end
				others += 1
				local b: Box = { x0 = math.huge, x1 = -math.huge, d0 = math.huge, d1 = -math.huge }
				for _, part in child:GetDescendants() do
					if part:IsA("BasePart") then
						floorOf(part, b)
					end
				end
				for _, own in mine do
					local g = gap(own, b)
					t.truthy(g >= 3.5, `{child.Name} is {g} studs from the air hockey table or its players`)
				end
			end
			t.truthy(
				others >= 8,
				`{others} other pieces of furniture were looked at (pool, bumper pool, darts, pinball, fortune)`
			)
			-- and where every other game's player presses its prompt: none within 4.5 studs
			local prompts = 0
			for _, st in Games.stations({ bowling_alley = FLAT }) do
				if st.site == Layout.SITE and st.game ~= "air_hockey" then
					prompts += 1
					local at: Box = { x0 = st.x, x1 = st.x, d0 = st.d, d1 = st.d }
					for _, own in mine do
						local g = gap(own, at)
						t.truthy(g >= 4.5, `{st.id}'s prompt is {g} studs from the air hockey table or its players`)
					end
				end
			end
			t.truthy(prompts >= 8)
			-- the two ends' players do not stand in each other's way, and each has room for a body
			for side = 0, 1 do
				local s = Layout.standing(side)
				t.truthy(s.x1 - s.x0 >= 2.4 and s.d1 - s.d0 >= 5, "standing room for one person, as wide as the table")
				t.eq(gap(s, foot) < 1.2, true, "a step behind the end rail")
			end
		end
	)

	t.test(
		"the views: his first person from each end, and from above under the ceiling, all inside the room",
		function()
			for side = 0, 1 do
				local s = if side == 0 then -1 else 1
				local fp = Layout.camera(side, false)
				t.eq(fp.fov, 64)
				t.near(fp.eye[2], s * 1.82, 1e-9, "his eye: 1.82 m behind the middle")
				t.near(fp.eye[3], 1.70, 1e-9)
				t.near(fp.target[2], -s * 0.18, 1e-9)
				local above = Layout.camera(side, true)
				for _, v in { fp, above } do
					local X, Y, D = Layout.toLocal(v.eye[1], v.eye[2], v.eye[3])
					t.truthy(X > AlleyLayout.GAME_ROOM_X0 + 0.6 and X < AlleyLayout.X1 - 0.6, `eye X {X}`)
					t.truthy(D < AlleyLayout.GAME_ROOM_D1 - 0.6, `eye D {D}`)
					t.truthy(Y < AlleyLayout.CEILING_Y - 0.5 and Y > Layout.BED_Y + 2, `eye Y {Y}`)
				end
				-- from above the whole bed is in view: the far corner is inside the vertical field of view
				local height = (above.eye[3] - Layout.BED_Z)
				local half = math.tan(math.rad(above.fov / 2)) * height
				t.truthy(half > Sim.HALF_WIDTH + 0.05, "the bed's width fits the screen's height from above")
				t.truthy(half * 16 / 9 > Sim.HALF_LENGTH + 0.1 or half > Sim.HALF_LENGTH, "and its length the screen")
			end
		end
	)

	t.test("his colours: linear to the screen's bytes", function()
		t.eq(Layout.srgb(0), 0)
		t.eq(Layout.srgb(1), 255)
		t.eq(Layout.srgb(0.2140411), 127)
		t.eq(Layout.srgb(2), 255)
	end)
end
