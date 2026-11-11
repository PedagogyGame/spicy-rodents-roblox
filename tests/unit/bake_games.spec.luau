--!strict
-- tools/bake/GameBakes, the bake registry of minigames, in memory (the same code tools/bake/attractions.luau
-- runs): every line is a registered game; the games room's tables and machines are built through it, one per
-- station; and a game that builds on an expansion venue gets that venue's site Model, in the venue's own
-- frame, with the Site and Origin attributes the server reads (Server/Attractions/AttractionService.sites),
-- while a game with no builder leaves no site behind.
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Games = require("@shared/Minigames/Games")
local GameBakes = require("../../tools/bake/GameBakes")
local Kit = require("../../tools/bake/alley/Kit")

local ALLEY: AlleyLayout.Place = { x = 40, z = -90, floorY = 12, yaw = 0.6 }
local COURT: AlleyLayout.Place = { x = 1526, z = -376, floorY = 7.2, yaw = 0 }
local CLINIC: AlleyLayout.Place = { x = 1100, z = -690, floorY = 5.3, yaw = math.pi }

return function(t)
	t.test("every line of the bake registry is a registered game; the alley's three have builders", function()
		for game in GameBakes.LIST do
			t.truthy(Games.get(game) ~= nil, `GameBakes lists {game}, which has no Spec`)
		end
		for _, game in { "pool", "bumper_pool", "pinball" } do
			t.truthy(GameBakes.has(game), game)
		end
		t.falsy(GameBakes.has("bowling"), "the lanes are part of the alley itself")
		t.falsy(GameBakes.build("no_such_game", nil, nil, nil, nil))
	end)

	t.test("the games room: one build per station, under the names the room has always had", function()
		local kit = Kit.new(roblox, ALLEY)
		local room = roblox.Instance.new("Model")
		room.Name = "GamesRoom"
		for _, st in Games.stations({ bowling_alley = ALLEY }) do
			if GameBakes.has(st.game) then
				t.truthy(GameBakes.build(st.game, kit, room, st, nil), st.id)
			end
		end
		for _, name in { "Pool1", "Pool2", "BumperPool", "Pinball1", "Pinball2", "Pinball3" } do
			local m = room:FindFirstChild(name)
			t.truthy(m ~= nil and m:IsA("Model"), name)
		end
		t.eq(#room:GetChildren(), 6)
		t.truthy(kit.count > 100, `{kit.count} parts`)
	end)

	t.test(
		"a game that builds on a venue gets the venue's site Model in the venue's frame; one that does not, nothing",
		function()
			local folder = roblox.Instance.new("Folder")
			local calls: { any } = {}
			local list = {
				test_court = {
					build = function(kit: any, parent: any, station: any, venue: any)
						table.insert(calls, { kit = kit, parent = parent, station = station, venue = venue })
						local m = kit:model(parent, "Court")
						kit:box(m, "Floor", -12, 12, -0.5, 0, station.d - 24, station.d + 24, { 200, 180, 140 }, "Wood")
						kit:ball(m, "Ball", station.x, 3, station.d, 0.6, { 20, 60, 200 }, "SmoothPlastic")
					end,
				},
				test_scoreboard = {
					build = function(kit: any, parent: any, station: any, _venue: any)
						table.insert(calls, { kit = kit, parent = parent, station = station })
						kit:box(parent, "Board", 10, 14, 8, 10, 40, 40.2, { 20, 20, 20 }, "SmoothPlastic")
					end,
				},
				test_unbuilt = {},
			}
			local stations = {
				{
					id = "court_1",
					game = "test_court",
					label = "Court",
					site = "f3_racquet_club",
					x = 0,
					y = 0,
					d = 18,
				},
				{
					id = "board_1",
					game = "test_scoreboard",
					label = "Board",
					site = "f3_racquet_club",
					x = 12,
					y = 0,
					d = 40,
				},
				{ id = "maze_1", game = "test_unbuilt", label = "Maze", site = "f2_doctor", x = 8, y = 2.6, d = -10.5 },
				-- (a station in the alley is the alley's own bake's, and a game nobody listed has no builder)
				{ id = "alley_1", game = "test_court", label = "Alley", site = "bowling_alley", x = 0, y = 0, d = 0 },
				{ id = "ghost_1", game = "test_ghost", label = "Ghost", site = "f2_doctor", x = 0, y = 0, d = 0 },
			}
			local places = { bowling_alley = ALLEY, f3_racquet_club = COURT, f2_doctor = CLINIC }
			local venues = {
				f3_racquet_club = { id = "f3_racquet_club", name = "Bellwether Racquet Club" },
				f2_doctor = { id = "f2_doctor" },
			}
			local out = GameBakes.venueSites(roblox, folder, stations, places, venues, list :: any)
			t.eq(out.sites, 1)
			t.deepEq(out.built, { "court_1", "board_1" })
			t.eq(out.parts, 3)
			-- one Model, named after the venue, carrying what the server reads
			t.eq(#folder:GetChildren(), 1)
			local site = folder:FindFirstChild("f3_racquet_club") :: any
			t.truthy(site ~= nil and site:IsA("Model"))
			t.eq(site:GetAttribute("Site"), "f3_racquet_club")
			t.eq(site:GetAttribute("OriginX"), COURT.x)
			t.eq(site:GetAttribute("OriginZ"), COURT.z)
			t.eq(site:GetAttribute("FloorY"), COURT.floorY)
			t.eq(site:GetAttribute("Yaw"), COURT.yaw)
			t.eq(folder:FindFirstChild("f2_doctor"), nil, "nothing was built at the clinic, so it is not a site")
			-- both games built into the same site Model with the same Kit, in the venue's frame
			t.eq(#calls, 2)
			t.truthy(calls[1].parent == site and calls[2].parent == site and calls[1].kit == calls[2].kit)
			t.eq(calls[1].station.id, "court_1")
			t.eq(calls[1].venue.name, "Bellwether Racquet Club")
			local ball = (site:FindFirstChild("Court") :: any):FindFirstChild("Ball")
			local wx, wy, wz = AlleyLayout.toWorld(COURT, 0, 3, 18)
			t.truthy(
				(ball.CFrame.Position - roblox.Vector3.new(wx, wy, wz)).Magnitude < 1e-3,
				"the ball is at the anchor"
			)
			t.near(wz, -394, 1e-6, "local (0, 18) on the racquet club is world z -394")
			t.truthy(site:FindFirstChild("Board") ~= nil)
		end
	)
end
