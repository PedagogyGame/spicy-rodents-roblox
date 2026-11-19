--!strict
-- ReplicatedStorage.Shared.Items.Clothing
-- What counts as clothing, the one kind of thing a player keeps between servers (owner D16 #25: "Clothing carries
-- over between servers; all other items stay in the current server only."), and the pure rules for a wardrobe:
-- what a player owns and what they have on, read from and written into the saved profile (Server/Persistence/
-- ProfileSchema: `wardrobe`, the ids owned, and `worn`, slot -> id). Server/Cosmetics/Wardrobe keeps the live one.
-- CLOTHING (CATALOG): a thing a player buys to wear, one per slot at a time:
--   alley_shirt         the bowling alley's gift shop (Server/Cosmetics/GiftShop): an alley shirt, worn by a person
--   paintball_garb_set  the paintball lobby's garb counter (PB-13): priced in EconomyRules, the counter is not built
-- NOT CLOTHING (NOT_CLOTHING, with the reason; they stay on the server they were bought on, or are not owned at all):
--   lane_shoes          the alley's shoe rental: handed back at the desk, never owned
--   the gift shop's souvenirs (postcard, toy pin, mug), the corner store's 22 items (the umbrella is held, not worn),
--   food and drink, the bowling ball, rides and the pass
--   (also not ours to save: the player's own Roblox avatar, which the avatar blend reads afresh at every join, and the
--   townspeople's role clothes, Shared/Avatar/PeopleLooks, which belong to the body, not the player)
-- The sewer fashion stand (Server/Cosmetics/FashionStand, the prototype's 3 x 10 hats, jackets and trousers) is not
-- built; its pieces join CATALOG when it is, and are saved the same way.
-- A saved id this build does not know (a newer server's clothing) is kept as it is and never dropped or worn here.
-- Interface: CATALOG; SLOTS; NOT_CLOTHING; def(id) -> Def?; isClothing(id) -> boolean;
--   empty() -> Wardrobe; fromSaved(saved) -> Wardrobe; toSaved(w, saved) (writes only saved.wardrobe and saved.worn);
--   merge(saved, here) -> Wardrobe; owns(w, id); wear(w, id) -> (ok, why?); takeOff(w, slot) -> id?;
--   wornIn(w, slot) -> id?; copy(w) -> Wardrobe
-- Pure; no side effects on require.

local Clothing = {}

export type Def = {
	id: string,
	slot: string,
	species: { [string]: boolean }, -- which bodies show it (a squirrel wears no shirt; it stays owned)
	color: { number }?, -- the look: the colour of the worn part (Server/Cosmetics/Wardrobe)
}

-- owned: id -> true; worn: slot -> id; changed: slot -> true for a slot changed on this server (merge keeps it)
export type Wardrobe = { owned: { [string]: boolean }, worn: { [string]: string }, changed: { [string]: boolean } }

Clothing.SLOTS = table.freeze({ "hat", "shirt", "jacket", "pants", "suit" })

local PEOPLE = table.freeze({ human = true })

Clothing.CATALOG = table.freeze({
	table.freeze({ id = "alley_shirt", slot = "shirt", species = PEOPLE, color = table.freeze({ 40, 46, 80 }) }),
	table.freeze({ id = "paintball_garb_set", slot = "suit", species = PEOPLE }),
} :: { Def })

Clothing.NOT_CLOTHING = table.freeze({
	lane_shoes = "a rental, handed back at the shoe desk",
	alley_postcard = "a souvenir",
	alley_pin_toy = "a souvenir",
	alley_mug = "a souvenir",
	bowling_ball = "a bowling ball",
	umbrella = "held, not worn",
} :: { [string]: string })

local byId: { [string]: Def } = {}
local slotSet: { [string]: boolean } = {}
for _, s in Clothing.SLOTS do
	slotSet[s] = true
end
for _, d in Clothing.CATALOG do
	assert(slotSet[d.slot], `Clothing: {d.id} has an unknown slot {d.slot}`)
	byId[d.id] = d
end

function Clothing.def(id: string): Def?
	return byId[id]
end

function Clothing.isClothing(id: any): boolean
	return type(id) == "string" and byId[id] ~= nil
end

function Clothing.empty(): Wardrobe
	return { owned = {}, worn = {}, changed = {} }
end

function Clothing.copy(w: Wardrobe): Wardrobe
	return { owned = table.clone(w.owned), worn = table.clone(w.worn), changed = table.clone(w.changed) }
end

-- The wardrobe in a saved profile. Owned ids are kept whatever they are (a newer build's clothing survives an older
-- server); a worn id is kept only if it is owned and sits in its own slot here (or the slot is one this build does
-- not know, again for a newer build).
function Clothing.fromSaved(saved: any): Wardrobe
	local w = Clothing.empty()
	local owned = if type(saved) == "table" then saved.wardrobe else nil
	if type(owned) == "table" then
		for id, v in owned do
			if type(id) == "string" and v == true then
				w.owned[id] = true
			end
		end
	end
	local worn = if type(saved) == "table" then saved.worn else nil
	if type(worn) == "table" then
		for slot, id in worn do
			if type(slot) == "string" and type(id) == "string" and w.owned[id] then
				local d = byId[id]
				if d == nil or d.slot == slot then
					w.worn[slot] = id
				end
			end
		end
	end
	return w
end

-- Write the wardrobe into a saved profile: its `wardrobe` and `worn` and nothing else (money and every other item
-- stay on this server: D16 #25).
function Clothing.toSaved(w: Wardrobe, saved: any)
	saved.wardrobe = table.clone(w.owned)
	saved.worn = table.clone(w.worn)
end

-- The saved wardrobe and this server's together (a profile that loads late, after the player bought or changed
-- clothes here): everything owned in either; a slot changed here keeps this server's choice, any other slot the
-- saved one.
function Clothing.merge(saved: Wardrobe, here: Wardrobe): Wardrobe
	local out = Clothing.copy(saved)
	for id in here.owned do
		out.owned[id] = true
	end
	for slot in here.changed do
		out.worn[slot] = here.worn[slot]
		out.changed[slot] = true
	end
	return out
end

function Clothing.owns(w: Wardrobe, id: string): boolean
	return w.owned[id] == true
end

function Clothing.wornIn(w: Wardrobe, slot: string): string?
	return w.worn[slot]
end

-- Put on an owned piece of clothing (in its slot, in place of whatever was there).
function Clothing.wear(w: Wardrobe, id: string): (boolean, string?)
	local d = byId[id]
	if d == nil then
		return false, "not clothing"
	end
	if not w.owned[id] then
		return false, "not owned"
	end
	w.worn[d.slot] = id
	w.changed[d.slot] = true
	return true, nil
end

function Clothing.takeOff(w: Wardrobe, slot: string): string?
	local id = w.worn[slot]
	w.worn[slot] = nil
	w.changed[slot] = true
	return id
end

return Clothing
