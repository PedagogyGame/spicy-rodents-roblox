--!strict
-- tests/isolated/lounge_service.luau: cases for tests/unit/lounge_service.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Server/Attractions/LoungeService on that fake engine: the engine check's own flow (tests/engine/Lounge: a person
-- with and without the pass, buying it, a squirrel trying every way in and the guards, the four drinks, leaving,
-- a new body, a leaver), the prompts and their E wiring, where the posts stand, and the Town built from the game.
-- Interface: return function(t) (the spec shape)
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local EconomyRules = require("@shared/Economy/EconomyRules")
local LoungeClassic = require("@shared/Attractions/LoungeClassic")
local LoungeService = require("@server/Attractions/LoungeService")
local LoungeFlow = require("@tests/engine/Lounge")
local LoungeMusic = require("@client/World/LoungeMusic")
local LoungeArt = require("@server/Assets/LoungeArt")
local LoungeArtData = require("@shared/Attractions/LoungeArt")
local FakeEngine = require("@tests/lib/FakeEngine")
local roblox = require("@lune/roblox")

local function makeModel(name: string, cf: any, parent: any): any
	local m = FakeEngine.model(name, cf, parent)
	local root = FakeEngine.part(if parent == nil then "HumanoidRootPart" else "Root", cf, m)
	root.Size = roblox.Vector3.new(2, 2, 1)
	m.PrimaryPart = root
	return m
end

local function deps(): any
	return {
		Service = LoungeService,
		LoungeClassic = LoungeClassic,
		EconomyRules = EconomyRules,
		AlleyLayout = AlleyLayout,
		makeBody = function(name: string, cf: any): any
			return makeModel(name, cf, nil)
		end,
		makeModel = makeModel,
		folder = function(name: string): any
			return FakeEngine.new("Folder", name)
		end,
	}
end

local function stubTown(log: { any }): any
	return {
		speciesOf = function(p: any): string?
			return p.species
		end,
		bodyOf = function(p: any): any?
			return p.body
		end,
		moveTo = function(p: any, cf: any)
			p.body:PivotTo(cf)
		end,
		evict = function(body: any, cf: any)
			body:PivotTo(cf)
		end,
		pass = {
			has = function(p: any): boolean
				return p.pass == true
			end,
			buy = function(_p: any): (boolean, string)
				return false, "no"
			end,
			offer = function(): (number, number, string) -- owner D31: the wallet's S$2.00 pass
				return 200, 5, "A pass is S$2.00 for five in-game days of paintball and both lounges."
			end,
		},
		buy = function(_p: any, _id: string, _deliver: any): (boolean, string)
			return false, "no"
		end,
		tell = function(p: any, text: string)
			table.insert(log, { p, text })
		end,
		squirrels = function(): { any }
			return {}
		end,
		knockOut = function(_a: any) end,
	}
end

return function(t)
	t.test(
		"the engine check's own flow passes here (pass, no pass, buy, squirrels, drinks, leave, swap, leaver)",
		function()
			FakeEngine.with(function()
				local result = LoungeFlow.play(deps())
				if not result.ok then
					error(table.concat(result.failures, "\n"))
				end
				local g = result.numbers.guards
				t.truthy(g.struck >= 40, `{g.struck} struck`)
				t.eq(g.wrong, 0)
				t.eq(g.spared, 8)
				t.eq(result.numbers.drinks.spent, 100 + 120 + 80 + 60) -- owner D31: prices x10
			end)
		end
	)

	t.test(
		"prompts: the door both ways, the podium's pass and the four drinks with prices, E (a seat R) with Door = true",
		function()
			FakeEngine.with(function()
				local log = {}
				local parent = FakeEngine.new("Folder", "P")
				local svc =
					LoungeService.new({ town = stubTown(log), parent = parent, root = FakeEngine.new("Folder", "R") })
				local kinds: { [string]: any } = {}
				for _, d in parent:GetDescendants() do
					if d.ClassName == "ProximityPrompt" then
						kinds[d:GetAttribute("Lounge")] = d
						t.eq(d:GetAttribute("Door"), true)
						-- (the seats' "Sit" has its own key: tests/isolated/lounge_seats)
						local key = if d:GetAttribute("Lounge") == "sit" then LoungeService.SEAT_KEY else "E"
						t.eq(d.KeyboardKeyCode, (roblox.Enum.KeyCode :: any)[key])
						t.eq(d.HoldDuration, 0)
					end
				end
				t.eq(kinds.enter.ActionText, "Go in")
				t.eq(kinds.enter.ObjectText, "THE GILDED ACORN")
				t.eq(kinds.leave.ActionText, "Leave")
				-- the door's two prompts need a line of sight: the solid leaves keep each to its own side
				t.eq(kinds.enter.RequiresLineOfSight, true)
				t.eq(kinds.leave.RequiresLineOfSight, true)
				t.eq(kinds.coffee.RequiresLineOfSight, false)
				-- the podium's too: from just inside the door wall it is within reach (3.9 studs), through the wall
				t.eq(kinds.pass.RequiresLineOfSight, true)
				t.eq(kinds.pass.ActionText, "Buy a pass")
				-- owner D31: prices x10, written as the wallet writes them
				t.eq(kinds.pass.ObjectText, "S$2.00 for 5 in-game days")
				t.eq(kinds.hot_cocoa.ActionText, "Hot cocoa (S$1.00)")
				t.eq(kinds.coffee.ActionText, "Coffee (S$1.20)")
				t.eq(kinds.green_tea.ActionText, "Green tea (80c)")
				t.eq(kinds.snow_cone.ActionText, "Snow cone (60c)")
				-- E at the door: a person with the pass goes in
				local body = makeModel("Ann", roblox.CFrame.new(svc:world(0, 3, -30)), nil)
				local ann = { species = "human", pass = true, body = body }
				kinds.enter.Triggered.fire(ann)
				t.truthy(svc:isInside(ann))
				kinds.leave.Triggered.fire(ann)
				-- leaving from outside does nothing (only someone the door let in leaves through it)
				local before = body:GetPivot()
				t.eq(svc:leave(ann), false)
				t.eq(body:GetPivot(), before)
				t.truthy(not svc:isInside(ann))
				-- a handler that throws is contained
				kinds.coffee.Triggered.fire(nil)
				svc:stop()
			end)
		end
	)

	t.test(
		"the posts: the door's on either side of the leaves, the podium on the landing, the orders on the bar",
		function()
			FakeEngine.with(function()
				local svc =
					LoungeService.new({ town = stubTown({}), prompts = false, root = FakeEngine.new("Folder", "R") })
				local function loc(p: any): (number, number, number)
					local w = p.CFrame.Position
					return AlleyLayout.toLocal(svc.place, w.X, w.Y, w.Z)
				end
				local _, _, d = loc(svc.outsidePost)
				t.truthy(d < -22 and d > LoungeClassic.DOOR_OUTSIDE.d, `outside post at D {d}`)
				_, _, d = loc(svc.insidePost)
				t.truthy(d > -21 and d < LoungeClassic.DOOR_INSIDE.d, `inside post at D {d}`)
				local x, y, pd = loc(svc.podiumPost)
				t.truthy(LoungeClassic.guarded(x, 0, pd) and y > 3.5, "the podium post")
				for _, p in svc.counterPosts do
					local cx, cy, cd = loc(p)
					t.truthy(cx > LoungeClassic.COUNTER.x0 and cx < LoungeClassic.COUNTER.x1, `order post X {cx}`)
					t.truthy(
						cd < LoungeClassic.COUNTER.d and cd > LoungeClassic.COUNTER.d - 1 and cy > 3.35,
						"order post"
					)
				end
				svc:stop()
			end)
		end
	)

	t.test(
		"the Town from the game: the wallet's pass and buy, the body moved standing, kill with cause guard",
		function()
			FakeEngine.with(function()
				local body = makeModel("Bo", roblox.CFrame.new(0, 0, 0), nil)
				local actor = { species = "human", body = body }
				local killed: { any } = {}
				local bought: { any } = {}
				local wallet = {
					pass = {
						has = function()
							return true
						end,
						buy = function()
							return true, "ok"
						end,
						offer = function()
							return 20, 5, "offer"
						end,
					},
					buy = function(p: any, id: string, _deliver: any): (boolean, string)
						table.insert(bought, { p, id })
						return true, "Paid"
					end,
					tell = function() end,
				}
				local held = makeModel("Held", roblox.CFrame.new(0, 0, 0), nil)
				local record = { id = 7, x = 0, y = 0, z = 0, hip = 2 }
				local nut = makeModel("Nut", roblox.CFrame.new(0, 0, 0), nil)
				local far = makeModel("Far", roblox.CFrame.new(0, 0, 0), nil)
				local brain = { species = "human", body = held }
				local runtime = {
					byTownId = {
						[7] = brain,
						[8] = actor,
						[9] = { species = "squirrel", body = nut },
						[10] = { species = "human", body = far },
					},
					world = {
						actorsById = { [7] = record },
						actors = {
							record,
							{ id = 8, x = 3, y = 0, z = 0, hip = 2 },
							{ id = 9, x = 1, y = 0, z = 1, hip = 1 },
							{ id = 10, x = 100, y = 0, z = 0, hip = 2 },
						},
					},
				}
				local town = LoungeService.gameTown({
					runtime = runtime,
					possession = {
						actorOf = function(_self: any, p: any): any
							return if p == "P" then actor else nil
						end,
						controllerOf = function(_self: any, a: any): any
							return if a == actor then "P" else "ai"
						end,
					},
					wallet = wallet,
					squirrels = function(): { any }
						return { { actor = "s", x = 1, y = 2, z = 3 } }
					end,
					kill = function(a: any, cause: string)
						table.insert(killed, { a, cause })
					end,
				})
				t.eq(town.speciesOf("P"), "human")
				t.eq(town.bodyOf("P"), body)
				t.eq(town.speciesOf("Q"), nil)
				t.eq(town.pass, wallet.pass)
				town.moveTo("P", roblox.CFrame.new(10, 20, 30))
				t.near(body:GetPivot().Position.Y, 20 + LoungeService.STAND, 1e-6)
				t.eq(
					select(
						1,
						town.buy("P", "coffee", function()
							return true
						end)
					),
					true
				)
				t.eq(bought[1][2], "coffee")
				town.knockOut("s")
				t.eq(killed[1][1], "s")
				t.eq(killed[1][2], "guard")
				t.eq(#town.squirrels(), 1)
				-- the bodies near a point that are not squirrel-family, with their holders (nil: a computer's)
				local near = town.occupants(0, 0, 10)
				t.eq(#near, 2)
				local holders: { [any]: any } = {}
				for _, o in near do
					holders[o.body] = o.player or "computer"
				end
				t.eq(holders[held], "computer")
				t.eq(holders[body], "P")
				-- a body is moved itself, standing, and through its world record too (feet = y - hip): a computer
				-- brain draws it from the record, a player still holding it (a leaver) from the body
				town.evict(held, roblox.CFrame.new(5, 6, 7))
				t.eq(record.x, 5)
				t.eq(record.y, 8)
				t.eq(record.z, 7)
				t.near(held:GetPivot().Position.Y, 6 + LoungeService.STAND, 1e-6)
				t.near(held:GetPivot().Position.X, 5, 1e-6)
				-- one with no record is moved itself, standing
				town.evict(body, roblox.CFrame.new(1, 2, 3))
				t.near(body:GetPivot().Position.Y, 2 + LoungeService.STAND, 1e-6)
			end)
		end
	)

	t.test(
		"a leaver whose body its player still holds when the lounge hears of it: the body is out, not shut in",
		function()
			FakeEngine.with(function()
				local svc0 =
					LoungeService.new({ town = stubTown({}), prompts = false, root = FakeEngine.new("Folder", "R") })
				local inRoom = roblox.CFrame.new(svc0:world(5, LoungeService.STAND, 0))
				svc0:stop()
				local x = makeModel("X", inRoom, nil)
				local actor = { species = "human", body = x }
				local record = { id = 7, x = 0, y = 0, z = 0, hip = 2 }
				local held = true
				local town = LoungeService.gameTown({
					runtime = { byTownId = { [7] = actor }, world = { actorsById = { [7] = record }, actors = {} } },
					possession = {
						actorOf = function(_self: any, p: any): any
							return if held and p == "P" then actor else nil
						end,
						controllerOf = function(_self: any, _a: any): any
							return if held then "P" else "ai"
						end,
					},
					wallet = {
						pass = {
							has = function()
								return true
							end,
							buy = function()
								return true, ""
							end,
							offer = function()
								return 20, 5, ""
							end,
						},
						buy = function()
							return true, ""
						end,
						tell = function() end,
					},
					squirrels = function(): { any }
						return {}
					end,
					kill = function() end,
				})
				local svc = LoungeService.new({ town = town, prompts = false, root = FakeEngine.new("Folder", "R") })
				t.truthy(svc:enter("P"))
				t.truthy(svc:inRoom(x))
				svc:gone("P") -- PlayerRemoving reaches the lounge before the runtime lets the body go
				t.truthy(not svc:inRoom(x), "the leaver's body is still in the room")
				-- the runtime then lets it go: its brain resumes from the body's own pose
				held = false
				local p = x:GetPivot().Position
				record.x, record.y, record.z = p.X, p.Y, p.Z
				svc:step(0.1)
				t.truthy(not svc:inRoom(x))
				t.eq(svc:counts().inside, 0)
				svc:stop()
			end)
		end
	)

	t.test(
		"the jazz (client): heard only while the body carries Lounge, faded in and out; the playlist from its first track",
		function()
			FakeEngine.with(function()
				local body = makeModel("Me", roblox.CFrame.new(0, 0, 0), nil)
				local parent = FakeEngine.new("Folder", "SoundService")
				local h = LoungeMusic.start({
					current = function(): any
						return body
					end,
					parent = parent,
					heartbeat = false,
				})
				local sound = parent:FindFirstChild("LoungeJazz")
				t.truthy(sound ~= nil)
				h.step(0.5)
				t.eq(h.inside(), false)
				t.eq(sound.Volume, 0)
				body:SetAttribute(LoungeClassic.ATTRIBUTE, LoungeClassic.VENUE)
				for _ = 1, 20 do
					h.step(0.1)
				end
				t.eq(h.inside(), true)
				t.eq(h.level(), 1)
				t.near(sound.Volume, LoungeClassic.JAZZ_VOLUME, 1e-9)
				t.eq(h.track(), "Lounge.Jazz1") -- the playlist starts at its first track
				t.eq(sound.SoundId, LoungeClassic.JAZZ[1].id)
				body:SetAttribute(LoungeClassic.ATTRIBUTE, nil)
				for _ = 1, 20 do
					h.step(0.1)
				end
				t.eq(h.inside(), false)
				t.eq(h.level(), 0)
				t.eq(sound.Volume, 0)
				h.stop()
			end)
		end
	)

	t.test(
		"the Blender pieces' loader: nothing without an id; with one, each piece in place and the parts hidden",
		function()
			FakeEngine.with(function()
				local place = LoungeClassic.placeOf(LoungeService._venue(LoungeClassic.VENUE))
				local root = FakeEngine.new("Model", LoungeClassic.VENUE)
				local interior = FakeEngine.new("Model", "Interior")
				interior.Parent = root
				for _, n in LoungeArtData.REPLACES do
					local p = FakeEngine.part(n, roblox.CFrame.new(0, 0, 0), interior)
					p.CanCollide = n == "BarFront"
				end
				local keep = FakeEngine.part("Stage", roblox.CFrame.new(0, 0, 0), interior)
				local bare = table.clone(LoungeArtData) :: any
				bare.ASSET_ID = "" -- (as before the upload)
				local report = LoungeArt.install(root, place, bare)
				t.eq(report.loaded, false)
				t.eq(report.why, "no asset id")
				t.eq(root:FindFirstChild("Art"), nil)
				-- a stand-in for the uploaded Model: every piece by name, and one stray
				local data = table.clone(LoungeArtData) :: any
				data.ASSET_ID = "123"
				local asked: number? = nil
				report = LoungeArt.install(root, place, data, {
					load = function(id: number): any
						asked = id
						local asset = FakeEngine.new("Model", "Asset")
						local m = FakeEngine.new("Model", "Lounge")
						m.Parent = asset
						for _, p in LoungeArtData.PIECES do
							FakeEngine.new("MeshPart", p.name).Parent = m
						end
						FakeEngine.new("MeshPart", "Stray").Parent = m
						return asset
					end,
				})
				t.eq(asked, 123)
				t.eq(report.loaded, true)
				t.eq(report.pieces, #LoungeArtData.PIECES)
				t.eq(report.unknown, 1)
				t.eq(report.hidden, #LoungeArtData.REPLACES)
				local art = root:FindFirstChild("Art")
				t.truthy(art ~= nil)
				for _, p in LoungeArtData.PIECES do
					local m = art:FindFirstChild(p.name)
					t.truthy(m ~= nil, p.name)
					local x, y, z = AlleyLayout.toWorld(place, p.centre[1], p.centre[2], p.centre[3])
					t.near(m.CFrame.Position.X, x, 1e-3)
					t.near(m.CFrame.Position.Y, y, 1e-3)
					t.near(m.CFrame.Position.Z, z, 1e-3)
					t.eq(m.CanCollide, false)
					t.eq(m.Anchored, true)
				end
				t.eq(interior:FindFirstChild("BarFront").Transparency, 1)
				t.eq(interior:FindFirstChild("BarFront").CanCollide, true)
				t.eq(keep.Transparency, 0)
				-- a second install does nothing
				t.eq(LoungeArt.install(root, place, data).why, "already installed")
			end)
		end
	)
end
