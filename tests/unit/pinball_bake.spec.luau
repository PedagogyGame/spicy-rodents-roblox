--!strict
-- The three pinball machines as tools/bake/games/Pinball bakes them (the same code tools/bake/attractions.luau
-- runs), built in memory at the alley's real place and measured against the model they are drawn from:
--   * every part the client moves is there under the name it looks for (Shared/Minigames/Pinball/Cabinet.NAMES,
--     the names tests/isolated/pinball_client.luau furnishes its fake cabinets with), one per element;
--   * where they stand is where the model simulates: a flipper's pivot part is exactly where the client turns
--     it about (the playfield's frame through Cabinet), each ball, lamp, bumper and drop target on its spot of
--     the Layout, set down at the machine Cabinet.at puts it (AlleyLayout.PINBALLS, never a number of its own);
--   * the playfield's pitch: the back of the playfield is higher than the front, by Layout.TILT_RAD;
--   * each machine stays inside its part budget (Bake.BUDGET) and inside the floor the plan keeps for the
--     machines (AlleyLayout.standing "pinball"), and the people's side of it, where the player stands, is clear.
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Cabinet = require("@shared/Minigames/Pinball/Cabinet")
local Games = require("@shared/Minigames/Games")
local Layout = require("@shared/Minigames/Pinball/Layout")
local Tables = require("@shared/Minigames/Pinball/Tables")
local Bake = require("../../tools/bake/games/Pinball")
local Kit = require("../../tools/bake/alley/Kit")

local PLACE: AlleyLayout.Place = { x = 40, z = -90, floorY = 12, yaw = 0.6 }

local function count(model: any): number
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- the playfield's frame in the world, as the client builds it (Client/Minigames/Pinball/Cabinet.frameOf)
local function frameOf(index: number): any
	local X, Y, D = Cabinet.origin(index)
	local x, y, z = AlleyLayout.toWorld(PLACE, X, Y, D)
	return roblox.CFrame.new(x, y, z)
		* roblox.CFrame.Angles(0, PLACE.yaw, 0)
		* roblox.CFrame.Angles(0, math.pi, 0)
		* roblox.CFrame.Angles(Cabinet.TILT, 0, 0)
end

local function world(index: number, x: number, y: number, h: number): any
	local X, Y, D = Cabinet.point(index, x, y, h)
	return roblox.Vector3.new(AlleyLayout.toWorld(PLACE, X, Y, D))
end

return function(t)
	local kit = Kit.new(roblox, PLACE)
	local room = roblox.Instance.new("Model")
	room.Name = "GamesRoom"
	local built: { [number]: any } = {}
	for _, st in Games.stations({ bowling_alley = PLACE }) do
		if st.game == "pinball" then
			Bake.build(kit, room, st, nil)
			built[st.index :: number] = room:FindFirstChild(Cabinet.model(st.index :: number))
		end
	end

	t.test("three machines, each lean: every one inside the budget (the parts are printed)", function()
		local total = 0
		for index = 1, #AlleyLayout.PINBALLS do
			local m = built[index]
			t.truthy(m ~= nil, `Pinball{index}`)
			local n = count(m)
			total += n
			print(`  pinball machine {index} ({m:GetAttribute("Theme")}): {n} parts`)
			t.truthy(n <= Bake.BUDGET, `machine {index}: {n} parts, over {Bake.BUDGET}`)
		end
		t.truthy(total <= 3 * Bake.BUDGET)
	end)

	t.test("every part the client moves is there, by the name it looks for", function()
		local N = Cabinet.NAMES
		for index, m in built do
			local tbl = Tables.need(m:GetAttribute("Table"))
			local def = tbl.def
			for i = 1, Cabinet.BALLS do
				t.truthy(m:FindFirstChild(`{N.ball}{i}`), `ball {i}`)
			end
			for i = 1, #def.flippers do
				local f = m:FindFirstChild(`{N.flipper}{i}`)
				t.truthy(f and f:IsA("Model") and f.PrimaryPart ~= nil, `flipper {i} of {index}`)
			end
			for i, target in def.targets do
				t.eq(m:FindFirstChild(`{N.drop}{i}`) ~= nil, target.kind == "drop", `target {i}`)
			end
			for k = 1, #tbl.c.spinners do
				t.truthy(m:FindFirstChild(`{N.spinner}{k}`), `spinner {k}`)
			end
			for i = 1, #def.lamps do
				t.truthy(m:FindFirstChild(`{N.lamp}{i}`), `lamp {i}`)
			end
			for i = 1, #def.bumpers do
				t.truthy(m:FindFirstChild(`{N.bumper}{i}`), `bumper {i}`)
			end
			for i = 1, #def.slings do
				t.truthy(m:FindFirstChild(`{N.sling}{i}`), `sling {i}`)
			end
			local plunger = m:FindFirstChild(N.plunger)
			t.truthy(plunger and plunger.PrimaryPart ~= nil)
			local display = m:FindFirstChild(N.backglass):FindFirstChild("Display")
			for _, name in { "Title", "Score", "Info", "Say", "Best" } do
				t.truthy(display:FindFirstChild(name), name)
			end
			t.eq(display:FindFirstChild("Title").Text, tbl.title)
		end
	end)

	t.test(
		"what is drawn is what is simulated: flippers, balls, lamps, bumpers and targets on the model's spots",
		function()
			for index, m in built do
				local tbl = Tables.need(m:GetAttribute("Table"))
				local def, c = tbl.def, tbl.c
				local pf = frameOf(index)
				-- the flipper's pivot part is where the client turns it about
				for i = 1, c.nFlip do
					local a = c.frest[i]
					local dx, dy = c.fmir[i] * math.cos(a), math.sin(a)
					local want = pf
						* roblox.CFrame.new(c.fpx[i], Cabinet.FLIPPER_H / 2, -c.fpy[i])
						* roblox.CFrame.Angles(0, Cabinet.turnOf(dx, dy), 0)
					local hub = m:FindFirstChild(`Flipper{i}`).PrimaryPart.CFrame
					t.truthy((hub.Position - want.Position).Magnitude < 1e-4, `flipper {i} pivot`)
					t.truthy((hub.XVector - want.XVector).Magnitude < 1e-4, `flipper {i} points along its bat`)
					-- and its X runs from the pin to the tip the physics knows
					local tip =
						world(index, c.fpx[i] + dx * c.flen[i], c.fpy[i] + dy * c.flen[i], Cabinet.FLIPPER_H / 2)
					local along = (tip - hub.Position).Unit
					t.truthy(along:Dot(hub.XVector) > 0.9999, `flipper {i}: the bat's direction`)
				end
				-- the ball on the plunger
				local p = def.plunger
				local ball = m:FindFirstChild("Ball1").CFrame.Position
				t.truthy((ball - world(index, p.x, p.y, Layout.BALL_R)).Magnitude < 1e-4)
				t.truthy(
					(ball - (pf * roblox.CFrame.new(p.x, Layout.BALL_R, -p.y)).Position).Magnitude < 1e-4,
					"the client's frame puts the ball on the same spot"
				)
				for i, l in def.lamps do
					local lamp = m:FindFirstChild(`Lamp{i}`).CFrame.Position
					t.truthy((lamp - world(index, l.x, l.y, 0.003)).Magnitude < 1e-3, `lamp {i}`)
				end
				for i, b in def.bumpers do
					local cap = m:FindFirstChild(`BumperCap{i}`).CFrame.Position
					t.truthy((cap - world(index, b.x, b.y, 0.18)).Magnitude < 1e-3, `bumper {i}`)
				end
				for i, target in def.targets do
					if target.kind == "drop" then
						local d = m:FindFirstChild(`Drop{i}`)
						local mid = world(index, (target.x1 + target.x2) / 2, (target.y1 + target.y2) / 2, 0.06)
						t.truthy((d.CFrame.Position - mid).Magnitude < 1e-3, `drop target {i}`)
						-- it sinks along its own Y: the playfield's normal
						t.truthy(d.CFrame.YVector:Dot(pf.YVector) > 0.9999)
					end
				end
				-- the pitch: the back of the playfield is higher than the front by the model's tilt
				local front, back = world(index, 1.2, 0, 0), world(index, 1.2, Layout.LENGTH, 0)
				t.near(back.Y - front.Y, Layout.LENGTH * math.sin(Layout.TILT_RAD), 1e-6)
				t.truthy(pf.YVector.Y > 0.99, "the playfield faces up")
			end
		end
	)

	t.test(
		"the machines stand where the floor plan puts them, inside the floor it keeps for them, with the player's side clear",
		function()
			local zone: any = nil
			for _, z in AlleyLayout.standing() do
				if z.id == "pinball" then
					zone = z
				end
			end
			t.truthy(zone ~= nil)
			for index, m in built do
				local px, pd = Cabinet.at(index)
				t.eq(px, AlleyLayout.PINBALLS[index].x)
				t.eq(pd, AlleyLayout.PINBALL_D)
				local sx, sd = Cabinet.stance(index)
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") then
						local X, _, D =
							AlleyLayout.toLocal(PLACE, d.CFrame.Position.X, d.CFrame.Position.Y, d.CFrame.Position.Z)
						t.truthy(
							X >= zone.x0 and X <= zone.x1 and D >= zone.d0 and D <= zone.d1,
							`{d.Name} at {X}, {D}`
						)
						-- nothing of the cabinet reaches the spot the player stands on
						t.truthy(D < sd - 0.5 or math.abs(X - sx) > 1.5, `{d.Name} is in the player's way`)
					end
				end
			end
		end
	)

	t.test(
		"the art: each table's story painted by its own lamps (ACORN's letters, RODENT's heat ladder, SPACE's countdown), a ground behind each backglass, the glass smooth and nearly clear, the light over the top lanes soft",
		function()
			local want = {
				acorn = { "A", "C", "O", "R", "N", "THE HOARD", "FILL THE HOARD BEFORE WINTER" },
				rodent = { "S", "P", "I", "C", "Y", "CALM", "FERAL", "RABID", "SUPER", "THE WIRE", "THE BITE" },
				space = { "F", "U", "E", "L", "3", "2", "1", "LAUNCH", "LOCK", "COUNTDOWN TO MULTIBALL" },
			}
			for _, m in built do
				local theme = m:GetAttribute("Theme")
				local art = m:FindFirstChild(Cabinet.NAMES.playfield):FindFirstChild("Art")
				t.truthy(art ~= nil, `{theme}: the playfield is painted`)
				local words: { [string]: boolean } = {}
				for _, l in art:GetChildren() do
					words[l.Text] = true
					-- every word lies on the board
					local p, z = l.Position, l.Size
					t.truthy(p.X.Scale >= -0.01 and p.X.Scale + z.X.Scale <= 1.01, `{theme}: {l.Text} across`)
					t.truthy(p.Y.Scale >= -0.01 and p.Y.Scale + z.Y.Scale <= 1.01, `{theme}: {l.Text} along`)
				end
				for _, word in want[theme] do
					t.truthy(words[word], `{theme}: "{word}" is painted`)
				end
				local ground = m:FindFirstChild(Cabinet.NAMES.backglass):FindFirstChild("Art")
				t.truthy(ground and ground:FindFirstChild("Ground"), `{theme}: the backglass has its ground`)
				local glass = m:FindFirstChild("Glass")
				t.truthy(glass.Material ~= roblox.Enum.Material.Glass, "no Glass material (it bends the view)")
				t.truthy(glass.Transparency >= 0.9, "nearly clear")
				local light = m:FindFirstChild("Backbox"):FindFirstChildOfClass("SpotLight")
				t.truthy(light and light.Brightness <= 0.6, "a soft light")
			end
		end
	)
end
