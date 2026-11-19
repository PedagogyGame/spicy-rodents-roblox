--!strict
-- The corner store's 22 items in use (Shared/Items/ItemRules says what each does; Server/Items/ItemService
-- applies it over fake deps that record what reaches the world): ownership, people only, cooldowns, uses used
-- up, and each item's effect, simplest first.
local ItemRules = require("@shared/Items/ItemRules")
local ItemService = require("@server/Items/ItemService")
local Inventory = require("@server/Items/Inventory")
local Common = require("@server/Actors/Brains/Common")
local Squirrel = require("@server/Actors/Brains/Squirrel")
local Human = require("@client/Controllers/Human")
local SquirrelController = require("@client/Controllers/Squirrel")
local ItemWorld = require("@server/Items/ItemWorld")
local PossessionState = require("@shared/Actors/PossessionState")
local FakeEngine = require("@tests/lib/FakeEngine")
local TownAI = require("@server/AI/TownAI")
local Data = require("@shared/Data")

type Rig = {
	svc: ItemService.Service,
	inv: Inventory.Inventory,
	player: any,
	clock: number,
	night: boolean,
	zone: string?,
	species: string?,
	about: { ItemService.Target },
	acts: { { [string]: any } },
	told: { string },
	refused: { string },
}

local function rig(): Rig
	local r: Rig = {
		player = { UserId = 7 },
		clock = 100,
		night = false,
		zone = nil,
		species = "human",
		about = {},
		acts = {},
		told = {},
		refused = {},
	} :: any
	r.inv = Inventory.new()
	r.svc = ItemService.new({
		inventory = r.inv,
		now = function(): number
			return r.clock
		end,
		pose = function(_p: any): ItemService.Pose?
			return { x = 0, y = 3, z = 0, lx = 0, lz = 1 } -- facing +Z
		end,
		speciesOf = function(_p: any): string?
			return r.species
		end,
		night = function(): boolean
			return r.night
		end,
		zoneAt = function(_x: number, _z: number): string?
			return r.zone
		end,
		nearby = function(x: number, z: number, radius: number): { ItemService.Target }
			local out = {}
			for _, t in r.about do
				if (t.x - x) ^ 2 + (t.z - z) ^ 2 <= radius * radius then
					table.insert(out, t)
				end
			end
			return out
		end,
		filter = function(_p: any, text: string): string?
			return (string.gsub(text, "badword", "#######"))
		end,
		notify = function(_p: any, words: string)
			table.insert(r.told, words)
		end,
		refuse = function(_p: any, words: string)
			table.insert(r.refused, words)
		end,
		act = function(_p: any, effect: { [string]: any }, targets: { ItemService.Target }?): boolean?
			local e = table.clone(effect)
			e.targets = targets
			table.insert(r.acts, e)
			return true
		end,
	})
	return r
end

local function kinds(r: Rig): { string }
	local out = {}
	for _, a in r.acts do
		table.insert(out, a.kind)
	end
	return out
end

local function use(r: Rig, id: string, payload: any?): (boolean, string?)
	r.clock += 10 -- past any cooldown
	return r.svc:use(r.player, id, payload)
end

return function(t)
	t.test("the rules: every one of the 22 does something (no todo left but none), and nothing is a gamble", function()
		for _, def in ItemRules.CATALOG do
			t.truthy(ItemRules.validate(def))
			local fx = ItemRules.use(def, { userId = 1, zone = "park", text = "hi", targetInRange = false })
			t.truthy(#fx >= 1, def.id)
			t.truthy(fx[1].kind ~= "todo", `{def.id} does nothing yet`)
			t.truthy(ItemRules.COOLDOWN[def.id] ~= nil, `{def.id}: a cooldown`)
			if fx[1].kind == "sound" or (fx[2] and fx[2].kind == "sound") then
				local s = if fx[1].kind == "sound" then fx[1] else fx[2]
				t.truthy(type(s.cue) == "string" and string.find(s.cue, "^Items%.") ~= nil, `{def.id}: a cue name`)
			end
		end
		for id in ItemRules.USES do
			t.truthy(ItemRules.def(id) ~= nil, id)
		end
		-- every cue has its row for the lead to fill (a library sound's id), and none is filled with an upload here
		for _, cue in ItemRules.CUES do
			t.truthy(ItemWorld.SOUNDS[cue] ~= nil, `{cue}: no row in ItemWorld.SOUNDS`)
		end
		for _, cue in ItemRules.RADIO_PLAYLIST do
			t.truthy(ItemWorld.SOUNDS[cue] ~= nil, `{cue}: no row in ItemWorld.SOUNDS`)
		end
	end)

	t.test("the inventory: one Tool per kind owned, gone with the last, made again while more are owned", function()
		local tools: { [string]: number } = {}
		local inv = Inventory.new({
			makeTool = function(_p: any, id: string): any
				tools[id] = (tools[id] or 0) + 1
				return id
			end,
			toolsOf = function(_p: any, id: string): { any }
				local out = {}
				for _ = 1, tools[id] or 0 do
					table.insert(out, {
						Destroy = function()
							tools[id] -= 1
						end,
					})
				end
				return out
			end,
		})
		local p = { UserId = 3 }
		inv.add(p, "frisbee")
		inv.add(p, "frisbee")
		t.eq(inv.count(p, "frisbee"), 2)
		t.eq(tools.frisbee, 1, "one Tool for two frisbees")
		-- one thrown (its Tool went with it): the other is in hand again
		tools.frisbee = 0
		t.truthy(inv.take(p, "frisbee"))
		t.eq(tools.frisbee, 1)
		t.truthy(inv.take(p, "frisbee"))
		t.eq(tools.frisbee, 0, "none left: no Tool")
		t.eq(inv.take(p, "frisbee"), false)
		t.eq(inv.export(p).frisbee, nil)
	end)

	t.test("only an owner who is a person, with a body, uses it; a cooldown between uses", function()
		local r = rig()
		t.eq(r.svc:use(r.player, "harmonica"), false)
		t.eq(r.refused[#r.refused], ItemService.WORDS.notOwned)
		r.inv.add(r.player, "harmonica")
		r.species = "squirrel"
		t.eq(use(r, "harmonica"), false)
		t.eq(r.refused[#r.refused], ItemService.WORDS.animal)
		r.species = nil
		t.eq(use(r, "harmonica"), false)
		r.species = "human"
		t.truthy(use(r, "harmonica"))
		t.eq(r.svc:use(r.player, "harmonica"), false, "pressed again at once: too soon")
		t.eq(#kinds(r), 1)
		t.eq(r.acts[1].cue, "Items.Harmonica")
		t.eq(r.inv.count(r.player, "harmonica"), 1, "a harmonica lasts")
	end)

	t.test("soda and ice cream: a sugar rush for D35's seconds, then gone", function()
		local r = rig()
		r.inv.add(r.player, "soda")
		r.inv.add(r.player, "ice_cream_bar")
		t.truthy(use(r, "soda"))
		t.eq(r.acts[1].kind, "treat")
		t.eq(r.acts[1].secs, 45)
		t.truthy(r.acts[1].scale > 1 and r.acts[1].scale <= 1.2)
		t.eq(r.inv.count(r.player, "soda"), 0, "drunk")
		t.truthy(use(r, "ice_cream_bar"))
		t.eq(r.acts[3].secs, 30)
		t.eq(r.inv.count(r.player, "ice_cream_bar"), 0)
	end)

	t.test(
		"harmonica, bike horn, air horn: sounds; the air horn startles people and squirrels within 12 only",
		function()
			local r = rig()
			for _, id in { "bike_horn", "air_horn" } do
				r.inv.add(r.player, id)
			end
			r.about = {
				{ kind = "human", id = 1, x = 5, y = 0, z = 5 },
				{ kind = "squirrel", id = 2, x = -8, y = 0, z = 0 },
				{ kind = "rodent", id = 3, x = 0, y = 0, z = 11 },
				{ kind = "human", id = 4, x = 30, y = 0, z = 0 },
			}
			t.truthy(use(r, "bike_horn"))
			t.eq(r.acts[1].cue, "Items.BikeHorn")
			t.truthy(use(r, "air_horn"))
			t.eq(r.acts[2].cue, "Items.AirHorn")
			t.eq(r.acts[3].kind, "startle")
			local ids = {}
			for _, tg in r.acts[3].targets do
				ids[tg.id] = true
			end
			t.truthy(ids[1] and ids[2] and ids[3])
			t.eq(ids[4], nil, "30 studs off: not startled")
			t.eq(r.inv.count(r.player, "air_horn"), 1)
		end
	)

	t.test("umbrella, flashlight, radio: toggles; the flashlight strong only at night; the radio's playlist", function()
		local r = rig()
		for _, id in { "umbrella", "flashlight", "radio" } do
			r.inv.add(r.player, id)
		end
		t.truthy(use(r, "umbrella"))
		t.eq(r.acts[1].on, true)
		t.truthy(use(r, "umbrella"))
		t.eq(r.acts[3].on, false)
		t.truthy(use(r, "flashlight"))
		t.eq(r.acts[5].kind, "light")
		t.eq(r.acts[5].strong, false, "by day")
		t.truthy(use(r, "flashlight"))
		r.night = true
		t.truthy(use(r, "flashlight"))
		t.eq(r.acts[9].on, true)
		t.eq(r.acts[9].strong, true, "at night")
		t.truthy(use(r, "radio"))
		local last = r.acts[#r.acts]
		t.eq(last.kind, "playlist")
		t.eq(last.on, true)
		t.eq(#last.tracks, #ItemRules.RADIO_PLAYLIST)
		for _, cue in last.tracks do
			t.truthy(string.find(cue, "^Radio%.") ~= nil, cue)
		end
	end)

	t.test("bubbles: a few seconds of bubbles, thirty to a bottle", function()
		local r = rig()
		r.inv.add(r.player, "bubbles")
		for _ = 1, ItemRules.USES.bubbles - 1 do
			t.truthy(use(r, "bubbles"))
		end
		t.eq(r.inv.count(r.player, "bubbles"), 1)
		t.truthy(use(r, "bubbles"))
		t.eq(r.inv.count(r.player, "bubbles"), 0, "the bottle is empty")
		t.eq(r.acts[1].kind, "vfx")
		t.eq(r.acts[1].vfx, "bubbles")
	end)

	t.test(
		"newspaper: read first (a headline), thrown next; frisbee and football leave the hand when thrown",
		function()
			local r = rig()
			for _, id in { "newspaper", "frisbee", "football" } do
				r.inv.add(r.player, id)
			end
			t.truthy(use(r, "newspaper"))
			t.eq(r.acts[1].kind, "read")
			t.truthy(table.find(ItemRules.HEADLINES, r.acts[1].headline) ~= nil)
			t.eq(r.inv.count(r.player, "newspaper"), 1)
			t.truthy(use(r, "newspaper"))
			t.eq(r.acts[3].kind, "throw")
			t.eq(r.inv.count(r.player, "newspaper"), 0)
			t.truthy(use(r, "frisbee"))
			t.eq(r.acts[4].kind, "throw")
			t.eq(r.acts[4].item, "frisbee")
			t.eq(r.inv.count(r.player, "frisbee"), 0, "in the air (still its buyer's: Items/Lending)")
			t.truthy(use(r, "football"))
			t.eq(r.inv.count(r.player, "football"), 0)
		end
	)

	t.test("peanuts and bird seed: bait for the squirrels near enough, used up; bird seed brings birds", function()
		local r = rig()
		r.inv.add(r.player, "peanuts")
		r.inv.add(r.player, "bird_seed")
		r.about = {
			{ kind = "squirrel", id = 1, x = 10, y = 0, z = 0 },
			{ kind = "squirrel", id = 2, x = 50, y = 0, z = 0 },
			{ kind = "human", id = 3, x = 5, y = 0, z = 0 },
		}
		t.truthy(use(r, "peanuts"))
		t.eq(r.acts[1].kind, "bait")
		t.eq(#r.acts[1].targets, 1, "only the squirrel within 40")
		t.eq(r.acts[1].birds, 0)
		t.eq(r.inv.count(r.player, "peanuts"), 0)
		t.truthy(use(r, "bird_seed"))
		t.eq(#r.acts[3].targets, 2, "bird seed reaches 60")
		t.truthy(r.acts[3].birds > 0)
	end)

	t.test("dog treats: a dog near is calmed (three to a box); with no dog about, words and nothing used", function()
		local r = rig()
		r.inv.add(r.player, "dog_treats")
		t.eq(use(r, "dog_treats"), false)
		t.eq(r.refused[#r.refused], ItemService.WORDS.noDog)
		r.about = { { kind = "dog", id = 9, x = 4, y = 0, z = 0 } }
		for _ = 1, 3 do
			t.truthy(use(r, "dog_treats"))
		end
		t.eq(r.inv.count(r.player, "dog_treats"), 0)
		t.eq(r.acts[1].targets[1].id, 9)
	end)

	t.test("chalk: asks for words, writes them filtered, at most 20 letters, one stick", function()
		local r = rig()
		r.inv.add(r.player, "chalk")
		t.truthy(use(r, "chalk"))
		t.eq(r.acts[1].kind, "askText")
		t.eq(r.acts[1].max, 20)
		t.eq(r.inv.count(r.player, "chalk"), 1, "asking uses nothing")
		t.eq(use(r, "chalk", { text = "this is far too long for one stick" }), false)
		t.eq(use(r, "chalk", { text = "   " }), false)
		t.truthy(use(r, "chalk", { text = " hi badword " }))
		t.eq(r.acts[2].kind, "write")
		t.eq(r.acts[2].text, "hi #######")
		t.eq(r.inv.count(r.player, "chalk"), 0)
	end)

	t.test(
		"camera: a screenshot, 24 to a camera; duct tape: ten strips; whoopee cushion and lawn chair set down",
		function()
			local r = rig()
			for _, id in { "camera", "duct_tape", "whoopee_cushion", "lawn_chair" } do
				r.inv.add(r.player, id)
			end
			for _ = 1, 24 do
				t.truthy(use(r, "camera"))
			end
			t.eq(r.inv.count(r.player, "camera"), 0)
			t.eq(r.acts[1].kind, "screenshot")
			for _ = 1, 10 do
				t.truthy(use(r, "duct_tape"))
			end
			t.eq(r.inv.count(r.player, "duct_tape"), 0)
			r.acts = {}
			t.truthy(use(r, "whoopee_cushion"))
			t.eq(r.acts[1].kind, "place")
			t.eq(r.acts[1].prop, "whoopee_cushion")
			t.eq(r.inv.count(r.player, "whoopee_cushion"), 0, "it is on the ground now")
			t.truthy(use(r, "lawn_chair"))
			t.eq(r.acts[2].prop, "lawn_chair")
			t.eq(r.acts[2].sit, true)
		end
	)

	t.test("water gun: people get wet; the rodent is stunned 1.3 s the first time per player, never again", function()
		local r = rig()
		r.inv.add(r.player, "water_gun")
		t.truthy(use(r, "water_gun"))
		t.eq(r.acts[1].hit, false, "nobody ahead")
		r.about = { { kind = "human", id = 1, x = 0, y = 0, z = 8 } }
		t.truthy(use(r, "water_gun"))
		t.eq(r.acts[2].hit, true)
		t.eq(r.acts[2].react, "wet")
		r.about = {
			{ kind = "rodent", id = 2, x = 0.5, y = 0, z = 10 },
			{ kind = "human", id = 3, x = 10, y = 0, z = 0 }, -- off to the side: not in the squirt
		}
		t.truthy(use(r, "water_gun"))
		local stun = nil
		for _, a in r.acts do
			if a.kind == "stun" then
				stun = a
			end
		end
		t.truthy(stun ~= nil)
		t.eq(stun.secs, 1.3)
		t.eq(stun.targets[1].id, 2)
		local n = #r.acts
		t.truthy(use(r, "water_gun"))
		for i = n + 1, #r.acts do
			t.truthy(r.acts[i].kind ~= "stun", "once per player")
		end
		-- another player's first hit still stuns
		local r2 = rig()
		r2.player = { UserId = 8 }
		r2.inv.add(r2.player, "water_gun")
		r2.about = r.about
		t.truthy(use(r2, "water_gun"))
		t.truthy(table.find(kinds(r2), "stun") ~= nil)
	end)

	t.test(
		"a squirrel baited: along its route to the point nearest the pile, waits there; a startle ends it, away from it",
		function()
			local route = {
				id = 1,
				kind = "ground",
				length = 40,
				points = { { 0, 0, 0 }, { 40, 0, 0 } },
				links = {},
			}
			local routes = {
				routes = { route },
				byId = function(_id: number): any
					return route
				end,
			}
			local actor = Common.newActor(1, "squirrel", "normal", "Squirrel", 5, 0, 0.9)
			local brain = Squirrel.new(actor, {
				routes = routes :: any,
				rng = function(): number
					return 0.5
				end,
				startRoute = 1,
			})
			local c: any = {
				now = 0,
				rng = function(): number
					return 0.5
				end,
				groundAt = function(): number
					return 0
				end,
			}
			actor.intent.s = 5
			-- a pile 30 studs off the route: not worth leaving it for
			brain:onEvent({ type = "bait", x = 20, z = 30, untilTime = 60 })
			brain:think(0.1, c)
			t.eq((brain :: any).bait, nil, "not taken")
			-- a pile 3 studs off the route at x 25: it heads for s 25 and stops there
			brain:onEvent({ type = "bait", x = 25, z = 3, untilTime = 60 })
			c.now = 1
			brain:think(0.1, c)
			t.eq(actor.intent.dir, 1)
			t.truthy(actor.intent.speed > 0)
			actor.intent.s = 25.2
			brain:think(0.1, c)
			t.eq(actor.intent.speed, 0, "nibbling")
			actor.intent.s = 30
			brain:think(0.1, c)
			t.eq(actor.intent.dir, -1, "back to it")
			-- a startle ends it; so does time
			brain:onEvent({ type = "startle" })
			actor.intent.s = 25
			c.now = 2
			brain:think(0.1, c)
			t.truthy(actor.intent.speed > 0, "off it runs")
			-- a startle from somewhere: it runs along its route away from it, whichever way it was going
			actor.intent.s, actor.intent.dir = 25, 1
			brain:onEvent({ type = "startle", x = 30, z = 2 })
			t.eq(actor.intent.dir, -1, "away from a fright ahead")
			brain:onEvent({ type = "startle", x = 10, z = -2 })
			t.eq(actor.intent.dir, 1, "away from one behind")
			brain:onEvent({ type = "bait", x = 25, z = 3, untilTime = 3 })
			c.now = 4
			brain:think(0.1, c)
			t.eq((brain :: any).bait, nil, "its time is up")
		end
	)

	t.test("the sugar rush on a person's pace: the scale until the time, at most 1.25, then nothing", function()
		t.eq(Human.treat(nil, nil, 10), 1)
		t.eq(Human.treat(20, 1.15, 10), 1.15)
		t.eq(Human.treat(20, 1.15, 20), 1)
		t.eq(Human.treat(20, 3, 10), 1.25)
		t.eq(Human.treat(20, 0.5, 10), 1)
	end)

	t.test("kite: flies in the park and on the beach only, and comes back down", function()
		local r = rig()
		r.inv.add(r.player, "kite")
		t.eq(use(r, "kite"), false)
		t.truthy(string.find(r.refused[#r.refused], "park", 1, true) ~= nil)
		for _, z in { "park", "beach" } do
			r.zone = z
			t.truthy(use(r, "kite"))
			local a = r.acts[#r.acts - 1]
			t.eq(a.kind, "kite")
			t.eq(a.zone, z)
			t.eq(a.on, true)
			t.truthy(use(r, "kite"))
			t.eq(r.acts[#r.acts - 1].on, false, "reeled in")
		end
		t.eq(r.inv.count(r.player, "kite"), 1, "a kite lasts")
		-- the zones themselves: the plan's two kite rectangles
		local Expansion = require("../../generated/Expansion") :: any
		t.eq(ItemService.kiteZoneAt(Expansion.zones, 0, 900), "park")
		t.eq(ItemService.kiteZoneAt(Expansion.zones, 500, 1300), "beach")
		t.eq(ItemService.kiteZoneAt(Expansion.zones, 957, 84), nil, "not in the store")
	end)
	t.test("a body change puts the toggles away: what was on is off, and the next use switches it on", function()
		local r = rig()
		for _, id in { "flashlight", "radio", "umbrella", "soda" } do
			r.inv.add(r.player, id)
		end
		use(r, "flashlight")
		use(r, "radio")
		t.truthy(r.svc:state(r.player, "flashlight").on and r.svc:state(r.player, "radio").on)
		t.eq(table.concat(r.svc:putAway(r.player), ","), "flashlight,radio")
		t.falsy(r.svc:state(r.player, "flashlight").on)
		t.falsy(r.svc:state(r.player, "radio").on)
		r.acts = {}
		use(r, "flashlight")
		t.eq(r.acts[1].kind, "light")
		t.eq(r.acts[1].on, true, "one press after the change switches it on")
		t.eq(#r.svc:putAway(r.player), 1)
		t.eq(#r.svc:putAway(r.player), 0, "nothing left on")
	end)
	t.test("a player's rodent stunned: a deadline on the body its client obeys; never anchored, no timer", function()
		local body = FakeEngine.model("Rodent", nil)
		local root = FakeEngine.part("Root", nil, body)
		body.PrimaryPart = root
		ItemWorld.stunBody(body, 500, 1.3)
		t.eq(body:GetAttribute(PossessionState.ATTR.StunnedUntil), 501.3)
		t.eq(root.Anchored, false, "the body stays its client's (anchoring froze only the server's copy)")
		t.truthy(SquirrelController.stunned(body:GetAttribute(PossessionState.ATTR.StunnedUntil), 501.2), "held still")
		t.falsy(
			SquirrelController.stunned(body:GetAttribute(PossessionState.ATTR.StunnedUntil), 501.3),
			"free at the deadline"
		)
		t.falsy(SquirrelController.stunned(nil, 0), "never stunned")
		ItemWorld.stunBody(body, 500.5, 0.2) -- (a shorter, later stun never cuts one short)
		t.eq(body:GetAttribute(PossessionState.ATTR.StunnedUntil), 501.3)
	end)
	t.test(
		"the air horn's startle is a timed flee: a sprint for 3 to 6 s, then the squirrel's ordinary life",
		function()
			local route = { id = 1, kind = "ground", length = 40, points = { { 0, 0, 0 }, { 40, 0, 0 } }, links = {} }
			local routes = {
				routes = { route },
				byId = function(_id: number): any
					return route
				end,
			}
			local actor = Common.newActor(1, "squirrel", "normal", "Squirrel", 5, 0, 0.9)
			local rng = function(): number
				return 0.5
			end
			local brain = Squirrel.new(actor, { routes = routes :: any, rng = rng, startRoute = 1 })
			local c: any = {
				now = 0,
				rng = rng,
				groundAt = function(): number
					return 0
				end,
			}
			local function live(from: number, to: number): (number, number, number?)
				local idle, sprinting, lastSprint = 0, 0, nil
				for i = from, to do
					c.now = i * 0.1
					brain:think(0.1, c)
					if actor.intent.speed == 0 then
						idle += 1
					elseif (brain :: any).sprint then
						sprinting += 1
						lastSprint = c.now
					end
				end
				return idle, sprinting, lastSprint
			end
			local idleBefore = live(1, 6000)
			t.truthy(idleBefore > 0, "an ordinary squirrel pauses now and then")
			brain:onEvent({ type = "startle" })
			t.truthy((brain :: any).sprint and actor.intent.speed > 0, "off at a sprint at once")
			local _, sprinting, lastSprint = live(6001, 6100)
			t.truthy(sprinting >= 30, "sprints at least 3 s")
			t.truthy(lastSprint ~= nil and (lastSprint :: number) <= 600 + 6.1, "and no longer than 6 s")
			local idleAfter = live(6101, 12000)
			t.truthy(
				idleAfter > idleBefore / 2,
				`back to its ordinary pauses ({idleAfter} idle ticks against {idleBefore})`
			)
			t.truthy((brain :: any).runUntil < math.huge, "never a flee for ever")
		end
	)
	t.test(
		"the computer's rodent stunned: its own brain stands it still, and a player taking it meanwhile is safe",
		function()
			local world = TownAI.build({ data = Data.default(), seed = 3 })
			local id: number? = nil
			for _, a in world.actors do
				if a.species == "squirrel" and a.variant == "spicy" then
					id = a.id
				end
			end
			assert(id, "the town has its rodent")
			local a = world.actorsById[id]
			local brain = world.brains[id]
			local c: any = {
				now = 10,
				rng = function(): number
					return 0.5
				end,
			}
			brain:onEvent({ type = "stun", untilTime = 11.3 }) -- ItemWorld: world.now + 1.3
			brain:think(0.1, c)
			t.eq(a.intent.speed, 0, "stands")
			t.eq(a.intent.tx, a.x)
			t.falsy(world.possessed[id], "never Possession's suspend")
			t.truthy(world.scheduler.byId[id] ~= nil, "still the AI's")
			-- a player takes it inside the 1.3 s and lets go after: Possession's suspend and resume alone, no error
			TownAI.suspend(world, id)
			local ok, err = pcall(function()
				TownAI.resume(world, id, a.x, a.y, a.z)
			end)
			t.truthy(ok, `release: {err}`)
			t.falsy(world.possessed[id])
			c.now = 11.4
			brain:think(0.1, c)
			t.truthy(a.intent.speed > 0 or a.intent.tx ~= a.x, "off again once the stun is over")
		end
	)
	t.test(
		"chalk: words typed straight after the ask are written; two sends while the filter works write once",
		function()
			local r = rig()
			r.inv.add(r.player, "chalk")
			r.clock += 10
			t.truthy(r.svc:use(r.player, "chalk"), "the box asked for")
			r.clock += 1.5 -- "hi" and Enter in a second and a half (the chalk's cooldown is 2 s)
			t.truthy(r.svc:use(r.player, "chalk", { text = "hi" }), "written, not dropped")
			t.eq(r.acts[#r.acts - 1].kind, "write")
			-- a second stick: two sends at once while TextService yields
			local r2 = rig()
			r2.inv.add(r2.player, "chalk")
			local waiting: { thread } = {}
			r2.svc.deps.filter = function(_p: any, text: string): string?
				table.insert(waiting, coroutine.running())
				coroutine.yield()
				return text
			end
			r2.clock += 10
			local c1 = coroutine.create(function()
				return r2.svc:use(r2.player, "chalk", { text = "one" })
			end)
			local c2 = coroutine.create(function()
				return r2.svc:use(r2.player, "chalk", { text = "two" })
			end)
			coroutine.resume(c1)
			local _, ok2 = coroutine.resume(c2)
			t.eq(ok2, false, "the second send is refused at once")
			t.eq(r2.refused[#r2.refused], ItemService.WORDS.chalkBusy, "with words")
			for _, co in waiting do
				coroutine.resume(co)
			end
			local writes = 0
			for _, a in r2.acts do
				if a.kind == "write" then
					writes += 1
				end
			end
			t.eq(writes, 1, "one stick, one writing")
			t.eq(r2.inv.count(r2.player, "chalk"), 0)
		end
	)

	t.test("chalk cuts by letters, never through one: ItemRules.cut", function()
		t.eq(ItemRules.cut("hello", 3), "hel")
		t.eq(ItemRules.cut("hi", 20), "hi")
		local accented = string.rep("\u{E9}", 25) -- two bytes each
		local cut = ItemRules.cut(accented, 20)
		t.eq(utf8.len(cut), 20)
		t.eq(#cut, 40, "whole letters")
		t.eq(ItemRules.cut("\xff\xfe", 5), "", "not UTF-8: nothing")
		local fx = ItemRules.use(ItemRules.def("chalk") :: any, { userId = 1, text = accented })
		t.eq(utf8.len(fx[1].text), 20, "the writing is valid text of 20 letters")
	end)
	t.test("lawn chairs: one each (a second folds the first), and one left empty folds itself up", function()
		local chairs = ItemWorld.chairs()
		local a, b = { UserId = 1 }, { UserId = 2 }
		local chairA1, chairA2, chairB = {}, {}, {}
		t.eq(chairs.place(a, chairA1, 0), nil)
		t.eq(chairs.place(b, chairB, 0), nil, "everyone has their own")
		t.eq(chairs.place(a, chairA2, 5), chairA1, "a's second chair folds the first")
		t.eq(chairs.chairOf(a), chairA2)
		t.eq(#chairs.owners(), 2)
		local empty = ItemWorld.CHAIR.emptySecs
		t.truthy(empty >= 60 and empty <= 600, "a few minutes")
		t.falsy(chairs.tick(a, false, 5 + empty - 1), "not yet")
		t.truthy(chairs.tick(a, false, 5 + empty), "empty long enough: folds")
		-- sat in: the clock starts again when the sitter gets up
		t.falsy(chairs.tick(b, true, empty * 2))
		t.falsy(chairs.tick(b, false, empty * 2 + 1))
		t.falsy(chairs.tick(b, false, empty * 3), "(empty since it was left)")
		t.truthy(chairs.tick(b, false, empty * 3 + 1))
		chairs.remove(a, chairA1) -- (only the chair named)
		t.eq(chairs.chairOf(a), chairA2)
		chairs.remove(a)
		t.eq(chairs.chairOf(a), nil)
		t.eq(#chairs.owners(), 1)
		t.truthy(ItemWorld.CHAIR.promptClear >= 4, "kept clear of the shelves, the till and the doors")
	end)
	t.test("a flashlight switched on by day brightens at dusk and dims at dawn while it stays on", function()
		t.truthy(ItemWorld.isNight(5.9) and ItemWorld.isNight(19.5) and ItemWorld.isNight(23))
		t.falsy(ItemWorld.isNight(6) or ItemWorld.isNight(12) or ItemWorld.isNight(19.4))
		local dayB, dayR = ItemWorld.beamFor(false)
		local nightB, nightR = ItemWorld.beamFor(true)
		t.truthy(nightB > dayB and nightR > dayR)
		local torch = FakeEngine.part("Handle", nil, nil)
		local beam = FakeEngine.new("SpotLight", "Beam", { Enabled = true, Brightness = dayB, Range = dayR })
		beam.Parent = torch
		local off = FakeEngine.new("SpotLight", "Beam", { Enabled = false, Brightness = dayB, Range = dayR })
		off.Parent = torch
		local lit: { [any]: boolean } = { [beam] = true, [off] = true }
		t.eq(ItemWorld.relight(lit, true), 1, "the one on")
		t.eq(beam.Brightness, nightB, "dusk: strong")
		t.eq(beam.Range, nightR)
		t.eq(off.Brightness, dayB, "one switched off is left alone")
		t.eq(lit[off], nil, "and leaves the set")
		t.eq(ItemWorld.relight(lit, false), 1)
		t.eq(beam.Brightness, dayB, "dawn: faint again")
		beam.Parent = nil -- (its Tool gone)
		t.eq(ItemWorld.relight(lit, true), 0)
		t.eq(next(lit), nil, "nothing left to watch")
	end)
end
