--!strict
-- tests/isolated/alley_roof_client.luau: cases for tests/unit/alley_roof_client_engine.spec.luau, run in their own
-- Lune process (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- The alley roof run on the squirrel's own screen, on that fake engine (BRIEF_ADDENDUM D9, lane L6):
--   * Client/UI/SneakMeter follows the player attributes the server writes (Server/Attractions/RafterService):
--     hidden until RafterMeter is set, the eye filling with it, "They're watching: creep (hold Ctrl) or get back in
--     the vent" once it is well filled, "Spotted!" while RafterSeen, hidden again when the server clears them, and
--     gone on stop();
--   * the held squirrel's controller (Client/Controllers/Squirrel.start, driven by render steps) with W held toasts
--     "Jump now to reach the branch" at the house ridge's west end and "Q: drop onto the roof" at the end of the
--     bough over the games wing, once each however long W is held there;
--   * server to screen: Server/Attractions/RafterService's attributes on the player drive the eye, a creep filling
--     it a little and a walk in front of a townsperson ending in "Spotted!".
-- Interface: return function(t) (the spec shape)
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AlleyRoof = require("@shared/Attractions/AlleyRoof")
local RafterService = require("@server/Attractions/RafterService")
local Registry = require("@shared/Routes/Registry")
local SpatialIndex = require("@shared/Routes/SpatialIndex")
local Graph = require("@shared/Routes/Graph")
local SneakMeter = require("@client/UI/SneakMeter")
local Squirrel = require("@client/Controllers/Squirrel")
local FakeEngine = require("@tests/lib/FakeEngine")
local roblox = require("@lune/roblox")

local PLACE = { x = 1300, z = -420, floorY = 16.5, yaw = 0 }

local function find(root: any, name: string): any
	for _, d in root:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end

return function(t)
	t.test("SneakMeter follows RafterMeter and RafterSeen: hidden, filling, watched words, Spotted!, gone", function()
		FakeEngine.with(function()
			FakeEngine.classes({ gui = { "CanvasGroup" } })
			local player = FakeEngine.new("Player", "Owner")
			FakeEngine.new("PlayerGui", "PlayerGui").Parent = player
			local h = SneakMeter.start({ player = player })
			local gui = h.gui
			t.eq(gui.Parent, player:FindFirstChild("PlayerGui"))
			t.eq(gui.Enabled, false, "off the rafters: nothing on screen")
			local fill, words, shout = find(gui, "Fill"), find(gui, "Words"), find(gui, "Shout")
			-- the server starts watching: the eye shows, a little filled, no words
			player:SetAttribute("RafterMeter", 0.1)
			player:SetAttribute("RafterSeen", false)
			t.eq(gui.Enabled, true)
			t.near(fill.Size.Y.Scale, 0.1, 1e-6)
			t.eq(words.Visible, false)
			t.eq(shout.Visible, false)
			-- they are watching
			player:SetAttribute("RafterMeter", 0.6)
			t.near(fill.Size.Y.Scale, 0.6, 1e-6)
			t.eq(words.Visible, true)
			t.eq(words.Text, "They're watching: creep (hold Ctrl) or get back in the vent")
			-- creeping, it eases to 0.3: the words stay until it calms under 0.25
			player:SetAttribute("RafterMeter", 0.3)
			t.eq(words.Visible, true, "held")
			player:SetAttribute("RafterMeter", 0.2)
			t.eq(words.Visible, false, "calm again")
			-- spotted
			player:SetAttribute("RafterMeter", 1)
			player:SetAttribute("RafterSeen", true)
			t.eq(shout.Visible, true)
			t.eq(shout.Text, "Spotted!")
			t.near(fill.Size.Y.Scale, 1, 1e-6)
			t.eq(words.Text, "They're watching: creep (hold Ctrl) or get back in the vent")
			local red = fill.BackgroundColor3
			t.truthy(red.R > red.G * 2, "a red eye")
			-- lost, then off the rafters: the server clears both
			player:SetAttribute("RafterSeen", false)
			player:SetAttribute("RafterMeter", 0.5)
			t.eq(shout.Visible, false)
			player:SetAttribute("RafterMeter", nil)
			player:SetAttribute("RafterSeen", nil)
			t.eq(gui.Enabled, false)
			h.stop()
			t.eq(gui.Parent, nil, "stop takes it away")
			player:SetAttribute("RafterMeter", 0.4) -- (no longer listened to)
		end)
	end)

	t.test("the squirrel controller toasts the hints at the ridge's end and the bough's end, once each", function()
		FakeEngine.with(function()
			local ws = FakeEngine.workspace()
			ws.Gravity = 196.2
			local registry = Registry.fromRecords(AlleyRoof.records(PLACE) :: any)
			local index = SpatialIndex.build(registry)
			local rail =
				{ registry = registry, index = index, graph = Graph.build(registry, index, nil), trampolines = {} }
			local world = {
				rail = function(): any
					return rail
				end,
				groundAt = function(): number
					return -100
				end,
				blocked = function(): boolean
					return false
				end,
			}
			local function run(routeId: number, u0: number, seconds: number): { string }
				local p = registry:pointAt(registry:get(routeId) :: Registry.Route, u0)
				local goal = registry:pointAt(registry:get(routeId) :: Registry.Route, 1)
				local cf = roblox.CFrame.new(p.x, p.y + 0.6, p.z)
				local body = FakeEngine.model("sq", cf, nil)
				local root = FakeEngine.part("Root", cf, body)
				root.AssemblyMass = 1
				body.PrimaryPart = root
				body:SetAttribute("HipHeight", 0.6)
				local toasts: { string } = {}
				-- W held, the camera looking at the route's end
				local input = {
					sample = function(_self: any, _yaw: number): { [string]: any }
						local at = root.Position
						return {
							fw = 1,
							side = 0,
							sprint = false,
							focus = false,
							cameraYaw = math.atan2(-(goal.x - at.X), -(goal.z - at.Z)),
							leap = false,
							drop = false,
							grab = false,
							choose = 0,
							pounce = false,
							nightVision = false,
						}
					end,
				}
				local route = registry:get(routeId) :: Registry.Route
				local stop = Squirrel.start(
					body,
					{ snapshot = { brain = { routeId = routeId, s = u0 * route.length, dir = 1 } }, holdSeconds = 0 },
					{},
					{
						world = world,
						input = input,
						toast = function(text: string)
							table.insert(toasts, text)
						end,
					}
				)
				for _ = 1, math.ceil(seconds * 60) do
					FakeEngine.renderStep(1 / 60)
				end
				stop()
				return toasts
			end
			local ridge = run(AlleyRoof.RIDGE, 0.8, 4)
			t.eq(table.concat(ridge, " | "), "Jump now to reach the branch", "the ridge, W held 4 s")
			local bough = run(AlleyRoof.BOUGH, 0.85, 4)
			t.eq(table.concat(bough, " | "), "Q: drop onto the roof", "the bough, W held 4 s")
		end)
	end)

	t.test("server to screen: RafterService's attributes drive the eye, from creeping to 'Spotted!'", function()
		FakeEngine.with(function()
			FakeEngine.classes({ gui = { "CanvasGroup" } })
			local player = FakeEngine.new("Player", "Owner")
			FakeEngine.new("PlayerGui", "PlayerGui").Parent = player
			local meter = SneakMeter.start({ player = player })
			local function at(X: number, Y: number, D: number): any
				local x, y, z = AlleyLayout.toWorld(PLACE, X, Y, D)
				return roblox.CFrame.new(x, y, z)
			end
			local function model(name: string, cf: any, hip: number): any
				local m = FakeEngine.model(name, cf, nil)
				local root = FakeEngine.part("Root", cf, m)
				m.PrimaryPart = root
				m:SetAttribute("HipHeight", hip)
				return m
			end
			-- a townsperson on lane 17's approach facing the pins, the squirrel on chord 9120 ahead of them
			local eyeAt = at(AlleyLayout.laneX(17), 3, -6)
			local person =
				model("p", roblox.CFrame.lookAt(eyeAt.Position, eyeAt.Position + roblox.Vector3.new(0, 0, -1)), 3)
			local X = AlleyLayout.laneX(17)
			local sq = model("sq", at(X, AlleyRoof.CHORD.y1 + 0.6, 16.5), 0.6)
			local clock = 0
			local svc = RafterService.new({
				town = {
					bodies = function(): { any }
						return {
							{ id = "p", kind = "human", model = person },
							{ id = "sq", kind = "squirrel", model = sq, player = player },
						}
					end,
					send = function() end,
				},
				now = function(): number
					return clock
				end,
				canSee = function(): boolean
					return true
				end,
				rand = function(): number
					return 0
				end,
			})
			local fill, shout = find(meter.gui, "Fill"), find(meter.gui, "Shout")
			-- to and fro over lanes 15 to 18, in front of them
			local dir = -1
			local function go(seconds: number, speed: number)
				for _ = 1, math.ceil(seconds * 30) do
					clock += 1 / 30
					X += dir * speed / 30
					if X < AlleyLayout.laneX(15) or X > AlleyRoof.BOOT.x0 then
						X = math.clamp(X, AlleyLayout.laneX(15), AlleyRoof.BOOT.x0)
						dir = -dir
					end
					sq.PrimaryPart.CFrame = at(X, AlleyRoof.CHORD.y1 + 0.6, 16.5)
					svc:step(1 / 30)
				end
			end
			go(3, 3) -- creeping
			t.eq(meter.gui.Enabled, true, "the eye is up on the rafters")
			t.truthy(
				fill.Size.Y.Scale > 0 and fill.Size.Y.Scale < 0.35,
				`a creep fills it a little ({fill.Size.Y.Scale})`
			)
			t.eq(shout.Visible, false)
			go(4, 18) -- walking
			t.eq(shout.Visible, true, "Spotted!")
			t.eq(shout.Text, "Spotted!")
			svc:stop()
			t.eq(meter.gui.Enabled, false, "the server cleared it: the eye goes")
			meter.stop()
		end)
	end)
end
