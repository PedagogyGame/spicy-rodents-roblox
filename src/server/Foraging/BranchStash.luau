--!strict
-- ServerScriptService.Server.Foraging.BranchStash
-- The knot-hole stashes in the branch nooks (owner D34: "the points where the branches are can have stash places off to
-- the side"; Shared/World/BranchNooks puts one beside every nook's cup, on every climbable tree). A stash spot of the
-- nut system (brief v2 §7; Foraging/HollowService holds what a squirrel carries): E in the cup puts in everything the
-- squirrel carries, up to C.capacity a hole; E with empty paws takes nuts out, up to forage.carryMax carried. Per
-- player, as the hollows' claims are (the key is opts.keyOf: Boot/Game's "player <UserId>"), so every player has their
-- own nuts in every hole and nobody takes another's; kept for the server's life (not saved), like the hollows' meters.
-- Proximity only, and the server's: the squirrel must be in the cup where the server holds it (opts.placeOf: Boot/Game,
-- MovementService.heldPlace in its strict mode, never the root its client moves): within BranchNooks.C.stashReach of
-- the nook's far end. The client (Client/World/BranchNookClient) shows "E  stash" there and sends the nook's route id
-- over PlayNet.Stash; anything else (no such nook, too far, no place held, asked again within C.gap) is refused.
-- Interface: new(opts) -> Service; Service:use(id, routeId) -> Result; :stored(key, routeId) -> n; :list(key) -> string
--   ("route=n,route=n": the player's non-empty holes, for the client's acorns); :clear(key); WORDS; C.
--   Result = { ok: boolean, word: string (WORDS key), moved: number, inside: number, carried: number, text: string }
-- Pure: no engine calls. No side effects on require.

local Import = require("../Import")
local BranchNooks = Import.shared("World/BranchNooks") :: typeof(require("../../shared/World/BranchNooks"))
local Tunables = Import.shared("Config/Tunables") :: typeof(require("../../shared/Config/Tunables"))

-- (the exported types do not cross the Import cast)
type Nooks = typeof(BranchNooks.new(nil))

local BranchStash = {}
BranchStash.__index = BranchStash

BranchStash.C = table.freeze({
	capacity = 12, -- nuts a knot-hole holds for one player
	gap = 0.25, -- seconds between one player's uses
	slack = 0.35, -- studs over BranchNooks.C.stashReach the server allows (a packet's lag)
})

BranchStash.WORDS = table.freeze({
	stored = "You tuck %d nut%s into the knot-hole (%d inside).",
	took = "You take %d nut%s out of your stash (%d left inside).",
	empty = "Your stash here is empty. Bring nuts and press E to keep them here.",
	full = "This knot-hole is full (%d nuts).",
	paws = "Your paws are full (%d nuts). Press E again with empty paws to take some out.",
	far = "Step right into the nook to reach the knot-hole.",
	none = "There is no stash here.",
})

type Who = string | number

export type Result = { ok: boolean, word: string, moved: number, inside: number, carried: number, text: string }

export type Opts = {
	nooks: Nooks,
	-- the nut carrying (Foraging/HollowService: carry(id, n) -> taken; carried(id) -> n; drop(id))
	hollows: any,
	placeOf: (id: number) -> (number?, number?, number?), -- the server's place for the body (nil: none it trusts)
	keyOf: (id: number) -> Who,
	now: (() -> number)?,
}

export type Service = typeof(setmetatable(
	{} :: {
		nooks: Nooks,
		hollows: any,
		placeOf: (id: number) -> (number?, number?, number?),
		keyOf: (id: number) -> Who,
		now: () -> number,
		holes: { [string]: { [number]: number } }, -- key (as text) -> route -> nuts
		last: { [string]: number },
	},
	BranchStash
))

function BranchStash.new(opts: Opts): Service
	return setmetatable({
		nooks = opts.nooks,
		hollows = opts.hollows,
		placeOf = opts.placeOf,
		keyOf = opts.keyOf,
		now = opts.now or os.clock,
		holes = {},
		last = {},
	}, BranchStash)
end

local function plural(n: number): string
	return if n == 1 then "" else "s"
end

function BranchStash.stored(self: Service, key: Who, routeId: number): number
	local mine = self.holes[tostring(key)]
	return if mine then mine[routeId] or 0 else 0
end

-- list(key): "route=n,route=n" over the player's holes with nuts in, in route order ("" for none)
function BranchStash.list(self: Service, key: Who): string
	local mine = self.holes[tostring(key)]
	if mine == nil then
		return ""
	end
	local ids = {}
	for id, n in mine do
		if n > 0 then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	local parts = {}
	for _, id in ids do
		table.insert(parts, `{id}={mine[id]}`)
	end
	return table.concat(parts, ",")
end

function BranchStash.clear(self: Service, key: Who)
	self.holes[tostring(key)] = nil
	self.last[tostring(key)] = nil
end

-- use(id, routeId): squirrel body `id` (its town id) presses E at the stash of nook `routeId`
function BranchStash.use(self: Service, id: number, routeId: any): Result
	local key = self.keyOf(id)
	local k = tostring(key)
	local function result(ok: boolean, word: string, moved: number, inside: number, text: string): Result
		return { ok = ok, word = word, moved = moved, inside = inside, carried = self.hollows:carried(id), text = text }
	end
	local p = if type(routeId) == "number" then self.nooks.place(routeId) else nil
	if p == nil or p.stash == nil then
		return result(false, "none", 0, 0, BranchStash.WORDS.none)
	end
	local t = self.now()
	local prev = self.last[k]
	if prev and t - prev < BranchStash.C.gap then
		return result(false, "gap", 0, self:stored(key, p.route), "")
	end
	self.last[k] = t
	local x, y, z = self.placeOf(id)
	local reach = BranchNooks.C.stashReach + BranchStash.C.slack
	if x == nil or y == nil or z == nil then
		return result(false, "far", 0, self:stored(key, p.route), BranchStash.WORDS.far)
	end
	local a = p.at
	if (x - a[1]) ^ 2 + (y - a[2]) ^ 2 + (z - a[3]) ^ 2 > reach * reach then
		return result(false, "far", 0, self:stored(key, p.route), BranchStash.WORDS.far)
	end
	local mine = self.holes[k]
	if mine == nil then
		mine = {}
		self.holes[k] = mine
	end
	local inside = mine[p.route] or 0
	local held = self.hollows:carried(id)
	local cap = BranchStash.C.capacity
	if held > 0 then
		local put = math.min(held, cap - inside)
		if put <= 0 then
			return result(false, "full", 0, inside, string.format(BranchStash.WORDS.full, cap))
		end
		-- (the carried count lives in the hollows: drop it all, then carry back what did not fit)
		self.hollows:drop(id)
		if held - put > 0 then
			self.hollows:carry(id, held - put)
		end
		mine[p.route] = inside + put
		return result(
			true,
			"stored",
			put,
			inside + put,
			string.format(BranchStash.WORDS.stored, put, plural(put), inside + put)
		)
	end
	if inside <= 0 then
		return result(false, "empty", 0, 0, BranchStash.WORDS.empty)
	end
	local want = math.min(inside, Tunables.get("forage.carryMax"))
	local took = self.hollows:carry(id, want)
	if took <= 0 then
		return result(false, "paws", 0, inside, string.format(BranchStash.WORDS.paws, Tunables.get("forage.carryMax")))
	end
	mine[p.route] = inside - took
	return result(
		true,
		"took",
		took,
		inside - took,
		string.format(BranchStash.WORDS.took, took, plural(took), inside - took)
	)
end

return BranchStash
