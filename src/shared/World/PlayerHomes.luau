--!strict
-- ReplicatedStorage.Shared.World.PlayerHomes
-- Which house in town is a player's home (owner D30: "players can access their computers at home" and "places it in
-- their home"). A SHARED SEAM of the D30 work (feat/stock-options puts the home computer in it, feat/town-work asks
-- whether an errand's parcel was taken home): whoever needs it first writes it, the other merges; this is the
-- smallest form that does both jobs, with a hook for a fuller one.
--   * HOMES are the town's houses (the lots of type "house" in Shared/Data's generated/Lots, by id, sorted): the
--     same list on every server.
--   * homeOf(player) -> lot id: a resolver set with setResolver (a claim system, when there is one) decides first;
--     otherwise the player's UserId picks a house from HOMES (UserId mod the count), so a player has the same home
--     on every server, with no saving. Two players can share a house (49 players, 31 houses): each calls it home.
--   * lotOf(id) -> { x, z, hw, hd } the house's footprint (world studs; w along X and d along Z, World/Colliders'
--     convention); inside(id, x, z, pad?) -> boolean: a point within the footprint (grown by pad).
-- Pure over Shared/Data (data defaults to Data.default()); no side effects on require.

local Data = require("../Data")

local PlayerHomes = {}

export type Lot = { id: string, x: number, z: number, hw: number, hd: number }

local cache: { ids: { string }, byId: { [string]: Lot } }? = nil
local resolver: ((player: any) -> string?)? = nil

local function load(data: any?): { ids: { string }, byId: { [string]: Lot } }
	if data == nil and cache ~= nil then
		return cache :: any
	end
	local d = data or Data.default()
	local ids: { string } = {}
	local byId: { [string]: Lot } = {}
	for _, lot in d:lots() do
		local fp = lot.footprint
		if lot.type == "house" and fp then
			table.insert(ids, lot.id)
			byId[lot.id] = { id = lot.id, x = lot.x, z = lot.z, hw = fp.w / 2, hd = fp.d / 2 }
		end
	end
	table.sort(ids)
	local out = { ids = ids, byId = byId }
	if data == nil then
		cache = out
	end
	return out
end

-- The houses that can be a home, in a fixed order.
function PlayerHomes.homes(data: any?): { string }
	return load(data).ids
end

-- A claim system (or a spec) decides first; nil from it falls back to the UserId's house. nil clears it.
function PlayerHomes.setResolver(fn: ((player: any) -> string?)?)
	resolver = fn
end

local function userIdOf(player: any): number?
	if type(player) == "number" then
		return player
	end
	local ok, id = pcall(function()
		return (player :: any).UserId
	end)
	return if ok and type(id) == "number" then id else nil
end

-- The lot id of this player's home, or nil (no houses, or nothing that names the player).
function PlayerHomes.homeOf(player: any, data: any?): string?
	if resolver then
		local ok, id = pcall(resolver :: any, player)
		if ok and type(id) == "string" then
			return id
		end
	end
	local ids = load(data).ids
	local uid = userIdOf(player)
	if uid == nil or #ids == 0 then
		return nil
	end
	return ids[(math.abs(math.floor(uid)) % #ids) + 1]
end

function PlayerHomes.lotOf(id: string, data: any?): Lot?
	return load(data).byId[id]
end

-- Is (x, z) within the house's footprint (grown by pad studs)?
function PlayerHomes.inside(id: string, x: number, z: number, pad: number?, data: any?): boolean
	local lot = load(data).byId[id]
	if lot == nil then
		return false
	end
	local p = pad or 0
	return math.abs(x - lot.x) <= lot.hw + p and math.abs(z - lot.z) <= lot.hd + p
end

return PlayerHomes
