--!strict
-- ReplicatedStorage.Shared.Items.ItemRules
-- The `Item` contract (BUILD_PLAN §1.4, §3.14; brief v2 §13a): the corner store's 22 items as data
-- (id, price in cents, effect kind) and a pure `use` that turns an item and a context into effects the
-- server applies (Server/Items/ItemService). No lottery or gambling items, ever (a test enforces it).
-- What each one does when its owner uses it (a click, a tap or the gamepad's trigger with it in hand):
--   water gun   a squirt ahead: a person hit is wet and reacts; the first time a given player's squirt hits the
--               rodent it is stunned 1.3 s (once per player, ever on this server)
--   frisbee, football   thrown ahead in an arc; whoever picks it up (or catches it) has it; the newspaper too,
--               once read
--   bubbles     a stream of bubbles for a few seconds (30 blows to a bottle)
--   chalk       asks for up to 20 letters and writes them on the ground (filtered like any player's text)
--   flashlight  on and off; a strong beam at night, hardly anything by day
--   umbrella    opens and closes over its holder
--   peanuts, bird seed   a pile put down: nearby squirrels come to it (bird seed also brings birds); used up
--   dog treats  a nearby dog is calmed (it stops barking at squirrels for a while); three to a box. NOT ON SALE
--               (onSale = false) until the town has dogs: Wildlife/YardHazards is still a stub, so a treat could
--               never do anything; the store neither shelves nor sells it (Shared/Items/Basket, the bake)
--   newspaper   the first use reads it (a headline); the next throws it
--   camera      a screenshot on its owner's screen (24 shots to a disposable camera)
--   duct tape   a strip of tape on whatever is in front (ten strips to a roll)
--   whoopee cushion   put down; the next person to step on it sets it off
--   harmonica, bike horn   a sound for everyone near
--   air horn    a blast that startles people and squirrels within its radius
--   soda, ice cream bar   a sugar rush: a faster pace for a while (used up)
--   lawn chair  set down and sat in, anywhere; folded back up with E
--   radio       on and off: plays the stock-library playlist (RADIO_PLAYLIST: cue names)
--   kite        flown in the park or on the beach (KITE_ZONES), nowhere else
-- Interface: CATALOG; def(itemId) -> Def?; onSale(itemId) -> boolean; use(def, ctx) -> { Effect };
--   validate(def) -> (ok, err?); cut(text, n);
--   USES (uses to one bought, nil: it lasts); COOLDOWN (seconds between uses); CUES; RADIO_PLAYLIST; HEADLINES;
--   KITE_ZONES; FORBIDDEN_EFFECTS
-- Pure; no side effects on require.

local Tunables = require("../Config/Tunables")

export type Def = { id: string, price: number, effect: string, [string]: any }
export type Ctx = {
	userId: number,
	targetKind: string?, -- "rodent" | "human" | "squirrel" | ...
	targetInRange: boolean?,
	stunUsed: boolean?, -- the profile's waterGunStunUsed (Q11: per player)
	on: boolean?, -- a toggle's state now (flashlight, umbrella, radio)
	night: boolean?, -- the town's clock says night
	read: boolean?, -- this newspaper has been read
	text: string?, -- the chalk's words (already filtered by the server)
	zone: string?, -- where its holder stands, for the kite: "park" | "beach" | nil
	uses: number?, -- uses so far of the one in hand
}
export type Effect = { kind: string, [string]: any }

local ItemRules = {}

-- stylua: ignore
ItemRules.CATALOG = {
	{ id = "water_gun", price = 6, effect = "squirt", npcReaction = "wet", rodentStunSecs = 1.3, oncePer = "player", range = 14 },
	{ id = "frisbee", price = 5, effect = "throw", speed = 38, lift = 0.35 }, { id = "football", price = 6, effect = "throw", speed = 44, lift = 0.5 },
	{ id = "bubbles", price = 3, effect = "vfx", secs = 4 }, { id = "chalk", price = 2, effect = "write", letters = 20 },
	{ id = "flashlight", price = 6, effect = "spotlight", nightOnly = true }, { id = "umbrella", price = 5, effect = "cosmetic" },
	{ id = "peanuts", price = 4, effect = "bait", radius = 40, secs = 45 }, { id = "bird_seed", price = 40, effect = "bait", radius = 60, secs = 90, birds = 3 },
	{ id = "dog_treats", price = 4, effect = "calm_dog", radius = 12, secs = 120, onSale = false }, { id = "newspaper", price = 2, effect = "read_and_throw", speed = 30, lift = 0.4 },
	{ id = "camera", price = 6, effect = "screenshot" }, { id = "duct_tape", price = 4, effect = "patch_bandage", reach = 6 },
	{ id = "whoopee_cushion", price = 15, effect = "seat_trap" }, { id = "harmonica", price = 5, effect = "sound" },
	{ id = "air_horn", price = 5, effect = "startle", radius = 12 }, { id = "soda", price = 4, effect = "stamina", scale = 1.15 },
	{ id = "ice_cream_bar", price = 5, effect = "stamina", scale = 1.15 }, { id = "lawn_chair", price = 6, effect = "place_seat" },
	{ id = "radio", price = 8, effect = "playlist" }, { id = "bike_horn", price = 3, effect = "sound" },
	{ id = "kite", price = 60, effect = "ride", ride = "kite" },
} :: { Def }

local byId: { [string]: Def } = {}
for _, d in ItemRules.CATALOG do
	byId[d.id] = d
end

ItemRules.FORBIDDEN_EFFECTS =
	{ lottery = true, gamble = true, scratch_card = true, raffle = true } :: { [string]: boolean }

-- Uses to one bought (nil: it lasts): the server takes the item away after the last.
-- stylua: ignore
ItemRules.USES = table.freeze({
	bubbles = 30, chalk = 1, peanuts = 1, bird_seed = 1, dog_treats = 3, newspaper = 2, camera = 24, duct_tape = 10,
	soda = 1, ice_cream_bar = 1,
} :: { [string]: number })

-- Seconds between two uses by one player (a horn is not a machine gun).
-- stylua: ignore
ItemRules.COOLDOWN = table.freeze({
	water_gun = 0.6, frisbee = 0.5, football = 0.5, bubbles = 1.0, chalk = 2, flashlight = 0.3, umbrella = 0.5,
	peanuts = 1, bird_seed = 1, dog_treats = 2, newspaper = 0.6, camera = 1.5, duct_tape = 1, whoopee_cushion = 1,
	harmonica = 2.5, air_horn = 5, soda = 1, ice_cream_bar = 1, lawn_chair = 1, radio = 0.5, bike_horn = 0.8, kite = 2,
} :: { [string]: number })

-- Sound cue names (Sound instances with empty ids, never uploads: docs/AUDIO_BUDGET.md lists them).
ItemRules.CUES = table.freeze({
	water_gun = "Items.WaterGun",
	harmonica = "Items.Harmonica",
	bike_horn = "Items.BikeHorn",
	air_horn = "Items.AirHorn",
	bubbles = "Items.Bubbles",
	camera = "Items.CameraClick",
	duct_tape = "Items.TapeRip",
	whoopee_cushion = "Items.Whoopee",
	soda = "Items.SodaFizz",
	ice_cream_bar = "Items.Wrapper",
	newspaper = "Items.PaperRustle",
	lawn_chair = "Items.ChairUnfold",
	flashlight = "Items.Click",
	umbrella = "Items.UmbrellaOpen",
	frisbee = "Items.Throw",
	football = "Items.Throw",
	chalk = "Items.Chalk",
	peanuts = "Items.Scatter",
	bird_seed = "Items.Scatter",
	dog_treats = "Items.Crunch",
	kite = "Items.KiteWind",
})

-- The radio's playlist: stock-library tracks by cue name (the ids are chosen from Roblox's licensed library and
-- filled in by the lead: docs/AUDIO_BUDGET.md; never uploaded).
ItemRules.RADIO_PLAYLIST = table.freeze({
	"Radio.Oldies1",
	"Radio.Oldies2",
	"Radio.SoftRock",
	"Radio.Country",
	"Radio.Jazz",
	"Radio.Weather",
})

-- What the newspaper says (mild, local, a little silly).
ItemRules.HEADLINES = table.freeze({
	"RED SQUIRREL SEEN AGAIN NEAR MAIN STREET",
	"BOWLING ALLEY OPENS EIGHTEEN LANES",
	"SKY LIFT: THE VIEW IS WORTH THE WAIT",
	"MAYOR: KEEP YOUR PEANUTS TO YOURSELF",
	"LOCAL MAN STILL LOOKING FOR HIS KITE",
	"HOSPITAL SAYS: IF BITTEN, COME STRAIGHT IN",
})

-- Where a kite flies: the park and the beach (the server answers which one its holder is in).
ItemRules.KITE_ZONES = table.freeze({ "park", "beach" })

function ItemRules.def(itemId: string): Def?
	return byId[itemId]
end

-- Whether the store shelves and sells it (a def with onSale = false waits for what it needs in the town).
function ItemRules.onSale(itemId: string): boolean
	local d = byId[itemId]
	return d ~= nil and d.onSale ~= false
end

function ItemRules.validate(d: Def): (boolean, string?)
	if type(d.id) ~= "string" or d.id == "" then
		return false, "id"
	end
	if type(d.price) ~= "number" or d.price < 0 or math.floor(d.price) ~= d.price then
		return false, `{d.id}: price must be whole cents`
	end
	if type(d.effect) ~= "string" or ItemRules.FORBIDDEN_EFFECTS[d.effect] then
		return false, `{d.id}: effect not allowed`
	end
	return true
end

-- The first `n` letters of `text` (code points, so a letter of several bytes is never cut in half; invalid UTF-8
-- gives "").
function ItemRules.cut(text: string, n: number): string
	local len = utf8.len(text)
	if len == nil then
		return ""
	end
	if len <= n then
		return text
	end
	return string.sub(text, 1, (utf8.offset(text, n + 1) :: number) - 1)
end

local function cue(d: Def): Effect
	return { kind = "sound", cue = ItemRules.CUES[d.id] }
end

-- Pure effect resolution: what using `d` does in `ctx`. Every list's first effect is the main one.
function ItemRules.use(d: Def, ctx: Ctx): { Effect }
	local id = d.id
	if id == "water_gun" then
		if not ctx.targetInRange then
			return { { kind = "squirt", hit = false } }
		end
		if ctx.targetKind == "rodent" then
			if ctx.stunUsed then
				return { { kind = "squirt", hit = true, wet = true } }
			end
			return {
				{ kind = "squirt", hit = true, wet = true },
				{ kind = "stun", target = "rodent", secs = d.rodentStunSecs },
				{ kind = "markStunUsed", userId = ctx.userId },
			}
		end
		return { { kind = "squirt", hit = true, wet = true, react = d.npcReaction } }
	elseif d.effect == "throw" then
		return { { kind = "throw", item = id, speed = d.speed, lift = d.lift }, cue(d) }
	elseif id == "newspaper" then
		if not ctx.read then
			local n = #ItemRules.HEADLINES
			local headline = ItemRules.HEADLINES[(ctx.userId + (ctx.uses or 0)) % n + 1]
			return { { kind = "read", headline = headline }, cue(d) }
		end
		return { { kind = "throw", item = id, speed = d.speed, lift = d.lift } }
	elseif id == "bubbles" then
		return { { kind = "vfx", vfx = "bubbles", secs = d.secs }, cue(d) }
	elseif id == "chalk" then
		if ctx.text == nil or ctx.text == "" then
			return { { kind = "askText", item = id, max = d.letters } }
		end
		return { { kind = "write", text = ItemRules.cut(ctx.text, d.letters) }, cue(d) }
	elseif id == "flashlight" then
		local on = not ctx.on
		return {
			{ kind = "light", on = on, strong = ctx.night == true },
			cue(d),
		}
	elseif id == "umbrella" then
		return { { kind = "open", on = not ctx.on }, cue(d) }
	elseif d.effect == "bait" then
		return {
			{ kind = "bait", item = id, radius = d.radius, secs = d.secs, birds = d.birds or 0 },
			cue(d),
		}
	elseif id == "dog_treats" then
		return { { kind = "calm_dog", radius = d.radius, secs = d.secs }, cue(d) }
	elseif id == "camera" then
		return { { kind = "screenshot", left = (ItemRules.USES.camera or 0) - (ctx.uses or 0) - 1 }, cue(d) }
	elseif id == "duct_tape" then
		return { { kind = "tape", reach = d.reach }, cue(d) }
	elseif id == "whoopee_cushion" then
		return { { kind = "place", prop = "whoopee_cushion" } }
	elseif id == "harmonica" or id == "bike_horn" then
		return { cue(d) }
	elseif id == "air_horn" then
		return { cue(d), { kind = "startle", radius = d.radius } }
	elseif d.effect == "stamina" then
		local secs = Tunables.get(if id == "soda" then "human.sodaSecs" else "human.iceCreamSecs")
		return { { kind = "treat", secs = secs, scale = d.scale }, cue(d) }
	elseif id == "lawn_chair" then
		return { { kind = "place", prop = "lawn_chair", sit = true }, cue(d) }
	elseif id == "radio" then
		return { { kind = "playlist", on = not ctx.on, tracks = ItemRules.RADIO_PLAYLIST } }
	elseif id == "kite" then
		if ctx.zone == nil or not table.find(ItemRules.KITE_ZONES, ctx.zone) then
			return { { kind = "refuse", words = "Kites fly in the park or on the beach." } }
		end
		return { { kind = "kite", zone = ctx.zone, on = not ctx.on }, cue(d) }
	end
	return { { kind = "todo", item = d.id, effect = d.effect } }
end

return ItemRules
