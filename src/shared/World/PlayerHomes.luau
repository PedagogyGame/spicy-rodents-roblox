--!strict
-- ReplicatedStorage.Shared.World.PlayerHomes
-- Every player who walks the town as a person has a home (owner D30, 2026-11-22: "players can access their computers
-- at home"): one of the town's four furnished houses, the one nearest to where they first appear as a person on this
-- server. It is decided once and kept for as long as the server runs (leaving and coming back finds the same home); a
-- new server decides afresh. Several players may share a house: its one desk computer serves each of them their own
-- saved Spicy Stock Options (Server/Economy/StockOptions). The server writes the home's lot id to the player
-- attribute ATTRIBUTE, so the server and the player's own screen read it the same way (homeOf).
-- The computer is the monitor on the house's desk (WorldGen/Builders/Interior: the study's or the den's desk, or the
-- one it adds to the bedroom); `computer` is the monitor's centre in world studs, checked against the bake plan by
-- tests/unit/stock_options.spec.luau, and `desk` the root part's name inside Workspace.Town.<lot>.
-- Other features (D30 errands: "places it in their home") use homeOf and inside(lotId, x, z).
-- Interface: HOMES; ATTRIBUTE; REACH; lot(id) -> Home?; nearest(x, z) -> Home; homeOf(player) -> lot id?;
--   inside(lotId, x, z) -> boolean; atComputer(lotId, x, y, z) -> boolean; new() -> Registry
--   { assign(key, x, z) -> lot id (the first call decides), of(key) -> lot id? }
-- Pure; no side effects on require.

export type Home = {
	lot: string, -- the lot id (generated/Lots, Workspace.Town)
	name: string, -- what a player reads: "the blue cottage"
	room: string, -- the room the computer stands in
	desk: string, -- the desk's root part ("<desk>_Monitor" is the screen)
	computer: { number }, -- the monitor's centre, world studs { x, y, z }
	x: number, -- the lot's centre and half extents (the house's footprint), world studs
	z: number,
	hw: number,
	hd: number,
}

export type Registry = {
	homes: { [any]: string },
	assign: (self: Registry, key: any, x: number, z: number) -> string,
	of: (self: Registry, key: any) -> string?,
}

local PlayerHomes = {}

PlayerHomes.ATTRIBUTE = "Home" -- the player attribute holding their home's lot id
PlayerHomes.REACH = 10 -- studs from a body to the monitor's centre: close enough to use the computer

PlayerHomes.HOMES = table.freeze({
	{
		lot = "core_house_0_victorian",
		name = "the Victorian house",
		room = "bedroom",
		desk = "Furniture_bedroom_desk",
		computer = { -150.465, 4.075, -135.4275 },
		x = -140,
		z = -132.5,
		hw = 22.55,
		hd = 19.475,
	},
	{
		lot = "core_house_1_bungalow",
		name = "the bungalow",
		room = "den",
		desk = "Furniture_den_desk",
		computer = { 119.14, 4.075, -158.14 },
		x = 127.5,
		z = -147.5,
		hw = 24.6,
		hd = 20.5,
	},
	{
		lot = "core_house_2_brick",
		name = "the brick house",
		room = "study",
		desk = "Furniture_study_desk",
		computer = { -111.35, 4.075, 141.23 },
		x = -132.5,
		z = 127.5,
		hw = 22.55,
		hd = 20.5,
	},
	{
		lot = "core_house_3_blue_cottage",
		name = "the blue cottage",
		room = "bedroom",
		desk = "Furniture_bedroom_desk",
		computer = { 141.775, 4.075, 142.825 },
		x = 145,
		z = 140,
		hw = 21.525,
		hd = 18.45,
	},
} :: { Home })

local BY_LOT: { [string]: Home } = {}
for _, h in PlayerHomes.HOMES do
	BY_LOT[h.lot] = h
end

function PlayerHomes.lot(id: string): Home?
	return BY_LOT[id]
end

-- The home nearest to (x, z) by its footprint's centre (the first in HOMES on a tie).
function PlayerHomes.nearest(x: number, z: number): Home
	local best, bestD = PlayerHomes.HOMES[1], math.huge
	for _, h in PlayerHomes.HOMES do
		local dx, dz = h.x - x, h.z - z
		local d = dx * dx + dz * dz
		if d < bestD then
			best, bestD = h, d
		end
	end
	return best
end

-- The player's home (the attribute the server writes), on the server or on their own screen.
function PlayerHomes.homeOf(player: any): string?
	local ok, v = pcall(function(): any
		return player:GetAttribute(PlayerHomes.ATTRIBUTE)
	end)
	if ok and type(v) == "string" and BY_LOT[v] then
		return v
	end
	return nil
end

-- Is (x, z) inside the house on this lot (its footprint)?
function PlayerHomes.inside(lotId: string, x: number, z: number): boolean
	local h = BY_LOT[lotId]
	return h ~= nil and math.abs(x - h.x) <= h.hw and math.abs(z - h.z) <= h.hd
end

-- Is a body at (x, y, z) close enough to use this home's computer?
function PlayerHomes.atComputer(lotId: string, x: number, y: number, z: number): boolean
	local h = BY_LOT[lotId]
	if h == nil then
		return false
	end
	local c = h.computer
	local dx, dy, dz = x - c[1], y - c[2], z - c[3]
	return dx * dx + dy * dy + dz * dz <= PlayerHomes.REACH * PlayerHomes.REACH
end

-- The server's record of who lives where: the first assign for a key decides its home, for as long as it is kept.
function PlayerHomes.new(): Registry
	local reg = { homes = {} } :: Registry
	function reg.assign(self: Registry, key: any, x: number, z: number): string
		local have = self.homes[key]
		if have then
			return have
		end
		local lot = PlayerHomes.nearest(x, z).lot
		self.homes[key] = lot
		return lot
	end
	function reg.of(self: Registry, key: any): string?
		return self.homes[key]
	end
	return reg
end

return PlayerHomes
