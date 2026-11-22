--!strict
-- ReplicatedStorage.Shared.Foraging.NutSpots
-- Where squirrels find nuts in the town (brief v2 §7 "Foraging and territory"; owner D16 #22 "build next"; BUILD_PLAN
-- §1.4 Foraging): 61 spots on open ground, each holding a few nuts that grow back on the game clock. Every spot is a
-- data entry (id, kind, x, z in studs, what it is near); its ground height is the terrain's (World/Height), which the
-- spec holds to the baked town's ground there. Four kinds (KINDS: how many nuts a spot holds when full, and the game
-- days one nut takes to grow back):
--   tree     under the town's acorn oaks (v5.4's ten oaks with acorns, wildlife_foraging §6.2): three spots round each
--            of the six with open ground under them (BUR OAK, Villa Oak South, the four Westside shade oaks; the two
--            Shop Oaks stand in sidewalks, Estate Oak South 1 inside the mansion, the Treehouse Oak under its house);
--            and one under each of twelve of the D34 woods' nut trees in the town (data/woods.json: two walnuts,
--            chestnuts, hickories, hazels, white and pin oaks; near = "<LABEL> woods <i>", the woods tree's index)
--   yard     the yards: v4.1's five gardens and five bird feeders, v5.4's three garden plots, two feeders and two
--            compost bins (wildlife_foraging §11.4, §11.6; the places, not the props)
--   park     v4.1's ten nut caches (§11.2) and the Tabasco garden in the park
--   premium  beside the two premium hollows (data/hollows.json premiumForage: H1's garden and feeder, H2's feeder): a
--            big pile that takes about a game week to grow back (brief v2 §7: "raided about once per in-game week")
-- Each spot was found by searching outward from its v4.1 / v5.4 place for ground that is level and clear of every
-- building, road, path, fence, trunk, collider, river and hollow hole, with nothing low over it
-- (tests/unit/nut_spots.spec.luau holds each to that against the baked town).
-- Interface: SPOTS; KINDS; byId(id) -> Spot?; stockOf(spot) -> number; regrowDaysOf(spot) -> number
-- Pure data. No side effects on require.

local NutSpots = {}

export type Spot = { id: string, kind: string, x: number, z: number, near: string }
export type Kind = { stock: number, regrowDays: number }

NutSpots.KINDS = table.freeze({
	tree = table.freeze({ stock = 3, regrowDays = 1 / 3 }), -- a nut every 4 real minutes (a game day is 12)
	yard = table.freeze({ stock = 2, regrowDays = 1 / 2 }), -- every 6
	park = table.freeze({ stock = 2, regrowDays = 1 / 3 }),
	premium = table.freeze({ stock = 6, regrowDays = 7 / 6 }), -- the whole pile again in a game week
} :: { [string]: Kind })

-- stylua: ignore
NutSpots.SPOTS = table.freeze({
	{ id = "tree_bur_oak_1", kind = "tree", x = -79.75, z = -82.5, near = "BUR OAK" },
	{ id = "tree_bur_oak_2", kind = "tree", x = -81.25, z = -86.25, near = "BUR OAK" },
	{ id = "tree_bur_oak_3", kind = "tree", x = -85, z = -87.75, near = "BUR OAK" },
	{ id = "tree_villa_oak_south_1", kind = "tree", x = 942.5, z = -879.75, near = "Villa Oak South" },
	{ id = "tree_villa_oak_south_2", kind = "tree", x = 946.25, z = -881.25, near = "Villa Oak South" },
	{ id = "tree_villa_oak_south_3", kind = "tree", x = 947.75, z = -885, near = "Villa Oak South" },
	{ id = "tree_westside_0_shade_oak_1", kind = "tree", x = -1007.5, z = -589.75, near = "Westside 0 shade oak" },
	{ id = "tree_westside_0_shade_oak_2", kind = "tree", x = -1003.75, z = -591.25, near = "Westside 0 shade oak" },
	{ id = "tree_westside_0_shade_oak_3", kind = "tree", x = -1002.25, z = -595, near = "Westside 0 shade oak" },
	{ id = "tree_westside_2_shade_oak_1", kind = "tree", x = -997.5, z = -284.75, near = "Westside 2 shade oak" },
	{ id = "tree_westside_2_shade_oak_2", kind = "tree", x = -993.75, z = -286.25, near = "Westside 2 shade oak" },
	{ id = "tree_westside_2_shade_oak_3", kind = "tree", x = -992.25, z = -290, near = "Westside 2 shade oak" },
	{ id = "tree_westside_4_shade_oak_1", kind = "tree", x = -997.25, z = 15, near = "Westside 4 shade oak" },
	{ id = "tree_westside_4_shade_oak_2", kind = "tree", x = -998.75, z = 11.25, near = "Westside 4 shade oak" },
	{ id = "tree_westside_4_shade_oak_3", kind = "tree", x = -1002.5, z = 9.75, near = "Westside 4 shade oak" },
	{ id = "tree_westside_6_shade_oak_1", kind = "tree", x = -1007.5, z = 325.25, near = "Westside 6 shade oak" },
	{ id = "tree_westside_6_shade_oak_2", kind = "tree", x = -1003.75, z = 323.75, near = "Westside 6 shade oak" },
	{ id = "tree_westside_6_shade_oak_3", kind = "tree", x = -1002.25, z = 320, near = "Westside 6 shade oak" },
	-- the D34 woods' nut trees in the town (Shared/World/TreeShapes woods: the walnuts, chestnuts, hickories, hazels,
	-- white and pin oaks nearest the middle, two of each): one spot under each, a few studs off its bark
	{ id = "tree_shagbark_hickory_1", kind = "tree", x = -263.25, z = 116, near = "SHAGBARK HICKORY woods 67" },
	{ id = "tree_pin_oak_1", kind = "tree", x = 143.75, z = 266.25, near = "PIN OAK woods 41" },
	{ id = "tree_pin_oak_2", kind = "tree", x = 176.5, z = 248.25, near = "PIN OAK woods 92" },
	{ id = "tree_hazel_1", kind = "tree", x = 270.5, z = 167.5, near = "HAZEL woods 84" },
	{ id = "tree_sweet_chestnut_1", kind = "tree", x = -144.5, z = 344.5, near = "SWEET CHESTNUT woods 77" },
	{ id = "tree_white_oak_1", kind = "tree", x = -198, z = -479, near = "WHITE OAK woods 22" },
	{ id = "tree_hazel_2", kind = "tree", x = -328, z = -575.75, near = "HAZEL woods 33" },
	{ id = "tree_black_walnut_1", kind = "tree", x = 357.75, z = -583.25, near = "BLACK WALNUT woods 27" },
	{ id = "tree_white_oak_2", kind = "tree", x = 162, z = 667, near = "WHITE OAK woods 29" },
	{ id = "tree_shagbark_hickory_2", kind = "tree", x = -649.75, z = -380.25, near = "SHAGBARK HICKORY woods 78" },
	{ id = "tree_sweet_chestnut_2", kind = "tree", x = -524, z = -627.25, near = "SWEET CHESTNUT woods 35" },
	{ id = "tree_black_walnut_2", kind = "tree", x = -256.25, z = -1018.75, near = "BLACK WALNUT woods 74" },
	{ id = "yard_garden_1", kind = "yard", x = 180, z = 155, near = "a garden" },
	{ id = "yard_garden_2", kind = "yard", x = -279, z = 180, near = "a garden" },
	{ id = "yard_garden_3", kind = "yard", x = 267.5, z = 660, near = "a garden" },
	{ id = "yard_garden_4", kind = "yard", x = -585, z = 240, near = "a garden" },
	{ id = "yard_garden_5", kind = "yard", x = 552.5, z = 330, near = "a garden" },
	{ id = "yard_feeder_1", kind = "yard", x = -222.5, z = 175, near = "a bird feeder" },
	{ id = "yard_feeder_2", kind = "yard", x = 220, z = 187.5, near = "a bird feeder" },
	{ id = "yard_feeder_3", kind = "yard", x = -547.5, z = 537.5, near = "a bird feeder" },
	{ id = "yard_feeder_4", kind = "yard", x = 330, z = 832.5, near = "a bird feeder" },
	{ id = "yard_feeder_5", kind = "yard", x = 592.5, z = 770, near = "a bird feeder" },
	{ id = "yard_plot_1", kind = "yard", x = -90, z = 130, near = "a garden plot" },
	{ id = "yard_plot_2", kind = "yard", x = 290, z = -60, near = "a garden plot" },
	{ id = "yard_plot_3", kind = "yard", x = -260, z = -45, near = "a garden plot" },
	{ id = "yard_feeder_v54_1", kind = "yard", x = -495, z = 127, near = "a bird feeder" },
	{ id = "yard_feeder_v54_2", kind = "yard", x = 125, z = -548, near = "a bird feeder" },
	{ id = "yard_compost_1", kind = "yard", x = 567.5, z = -170.5, near = "a compost bin" },
	{ id = "yard_compost_2", kind = "yard", x = -185, z = 504.5, near = "a compost bin" },
	{ id = "park_cache_1", kind = "park", x = -195, z = -220, near = "an old nut cache" },
	{ id = "park_cache_2", kind = "park", x = -277.5, z = 110, near = "an old nut cache" },
	{ id = "park_cache_3", kind = "park", x = 154.25, z = 168.5, near = "an old nut cache" },
	{ id = "park_cache_4", kind = "park", x = 242.5, z = 295, near = "an old nut cache" },
	{ id = "park_cache_5", kind = "park", x = -395, z = 290, near = "an old nut cache" },
	{ id = "park_cache_6", kind = "park", x = -562.5, z = -257.5, near = "an old nut cache" },
	{ id = "park_cache_7", kind = "park", x = -537.5, z = 662.5, near = "an old nut cache" },
	{ id = "park_cache_8", kind = "park", x = -280, z = 965, near = "an old nut cache" },
	{ id = "park_cache_9", kind = "park", x = 297.5, z = 815, near = "an old nut cache" },
	{ id = "park_cache_10", kind = "park", x = 582.5, z = 512.5, near = "an old nut cache" },
	{ id = "park_tabasco", kind = "park", x = 287.5, z = 852.5, near = "the Tabasco garden" },
	{ id = "premium_h1_garden", kind = "premium", x = 180, z = 375, near = "H1's garden" },
	{ id = "premium_h1_feeder", kind = "premium", x = 252.5, z = 317.5, near = "H1's feeder" },
	{ id = "premium_h2_feeder", kind = "premium", x = -112.5, z = 170, near = "H2's feeder" },
} :: { Spot })

local byId: { [string]: Spot } = {}
for _, s in NutSpots.SPOTS do
	byId[s.id] = s
end

function NutSpots.byId(id: string): Spot?
	return byId[id]
end

function NutSpots.stockOf(spot: Spot): number
	local k = NutSpots.KINDS[spot.kind]
	return if k then k.stock else 0
end

function NutSpots.regrowDaysOf(spot: Spot): number
	local k = NutSpots.KINDS[spot.kind]
	return if k then k.regrowDays else math.huge
end

return NutSpots
