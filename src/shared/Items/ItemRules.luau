--!strict
-- ReplicatedStorage.Shared.Items.ItemRules
-- The `Item` contract (BUILD_PLAN §1.4, §3.14; brief v2 §13a): the corner store's 22 items as data
-- (id, price in cents, effect kind) and a pure `use` that turns an item and a context into effects the
-- server applies. W1 ships the contract and ONE implemented effect (the water gun, with the
-- once-per-player 1.3 s rodent stun); every other effect returns { kind = "todo" } until W4's
-- ItemService. No lottery or gambling items, ever (a test enforces it).
-- Interface: CATALOG; def(itemId) -> Def?; use(def, ctx) -> { Effect }; validate(def) -> (ok, err?)

export type Def = { id: string, price: number, effect: string, [string]: any }
export type Ctx = {
	userId: number,
	targetKind: string?, -- "rodent" | "human" | "squirrel" | ...
	targetInRange: boolean?,
	stunUsed: boolean?, -- the profile's waterGunStunUsed (Q11: per player)
}
export type Effect = { kind: string, [string]: any }

local ItemRules = {}

-- stylua: ignore
ItemRules.CATALOG = {
	{ id = "water_gun", price = 6, effect = "squirt", npcReaction = "wet", rodentStunSecs = 1.3, oncePer = "player" },
	{ id = "frisbee", price = 5, effect = "throw" }, { id = "football", price = 6, effect = "throw" },
	{ id = "bubbles", price = 3, effect = "vfx" }, { id = "chalk", price = 2, effect = "write", letters = 20 },
	{ id = "flashlight", price = 6, effect = "spotlight", nightOnly = true }, { id = "umbrella", price = 5, effect = "cosmetic" },
	{ id = "peanuts", price = 4, effect = "bait" }, { id = "bird_seed", price = 40, effect = "bait" },
	{ id = "dog_treats", price = 4, effect = "calm_dog" }, { id = "newspaper", price = 2, effect = "read_and_throw" },
	{ id = "camera", price = 6, effect = "screenshot" }, { id = "duct_tape", price = 4, effect = "patch_bandage" },
	{ id = "whoopee_cushion", price = 15, effect = "seat_trap" }, { id = "harmonica", price = 5, effect = "sound" },
	{ id = "air_horn", price = 5, effect = "startle", radius = 12 }, { id = "soda", price = 4, effect = "stamina" },
	{ id = "ice_cream_bar", price = 5, effect = "stamina" }, { id = "lawn_chair", price = 6, effect = "place_seat" },
	{ id = "radio", price = 8, effect = "playlist" }, { id = "bike_horn", price = 3, effect = "sound" },
	{ id = "kite", price = 60, effect = "ride", ride = "kite" },
} :: { Def }

local byId: { [string]: Def } = {}
for _, d in ItemRules.CATALOG do
	byId[d.id] = d
end

ItemRules.FORBIDDEN_EFFECTS = { lottery = true, gamble = true, scratch_card = true, raffle = true } :: { [string]: boolean }

function ItemRules.def(itemId: string): Def?
	return byId[itemId]
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

-- Pure effect resolution. The stub: the water gun.
function ItemRules.use(d: Def, ctx: Ctx): { Effect }
	if d.id == "water_gun" then
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
	end
	return { { kind = "todo", item = d.id, effect = d.effect } }
end

return ItemRules
