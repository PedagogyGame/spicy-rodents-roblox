--!strict
-- ServerScriptService.Server.Foraging.HollowService
-- The hollow trees and the fallen log on the server (brief v2 §3 "Hollow trees", §8 "the rodent therefore needs
-- refuges between bites: hollows, the sewer, poles and trees"; BRIEF_ADDENDUM D6). Their insides are enclosed routes
-- (Shared/World/HollowLayout over Shared/Routes/Enclosure; the motor runs them); this is what being in one means:
--   * The shell: start() builds every hollow's inside as plain parts (World/HollowShell) under Workspace.HollowTrees.
--   * Cover: a squirrel whose body is in a hollow's cavity (HollowLayout.contains) is out of AI/TownAI's threat grid
--     (the computer's squirrel only on one of that hollow's own runs: its point is its route's line, and a trunk's
--     line, the axis, runs up through the cavity while it climbs the bark outside)
--     (TownAI.addCover, as the storm drains), so people do not see or hear it, the fox does not hunt it, the crowd's
--     fears leave it out. A body let go inside is put at the hole, standing, facing out. Each hollow's cavities are a
--     Combat/Cover shape while the service runs, so a kick or a bite does not reach through the bark either way.
--   * No bites from cover and the rodent's rest: mayBite is false inside; the Spicy Rodent heals inside at the hollow
--     rate (Tunables rodent.regenHollow) while fed (World/SewerService.fed), as in a drain.
--   * The nut meter and the claim (Shared/Foraging/HollowClaim; Tunables forage.*): each claimable hollow keeps a
--     meter. A squirrel carries at most forage.carryMax nuts (carry: what a future forage source hands it); while it
--     is inside a hollow that is unclaimed or its own it brings what it carries in (deposit) and counts as visiting
--     (inside another's claimed tree it keeps them). The squirrel that lifts the meter to forage.ownThreshold, having
--     brought forage.keepMargin of it itself, owns the tree while the meter stays above the threshold less that margin
--     and it visits at least once every forage.ownVisitDays game days; the meter decays forage.meterDecayPerDay of
--     capacity a game day. Proximity only: no ritual, no animation. The log is a hiding place, never claimed.
--   * Who claims: opts.keyOf(body id) (Boot/Game: the player driving it, else the computer's body), so a player's
--     claim stays the player's when they let the body go, and the computer that takes the body back does not hold
--     it. Nuts are carried by the body: they drop when it changes hands or is knocked out (drop).
--   * The claim shown on the tree: the hollow's model in Workspace.HollowTrees carries Meter (0-1), Owner (the
--     owner's key as text, or ""), OwnerName and Claimed, and a small pennant by the ground hole shows while it is
--     claimed.
-- What is not here (no system to hang it on yet): nut sources (gardens, feeders, trash: Foraging/ForageService) and
-- their finite stock per season, theft from an unclaimed tree (HollowClaim.withdraw is the rule), the winter
-- survival check (Seasons/SeasonService), the squirrel rank's nut count (Roles/Ladder reads stats.nuts).
-- Interface: new(opts) -> Service (pure but for the cover); start(opts) -> Service (new, then the shell in the
--   workspace); Service: :step(day) (once a second is plenty: deposits, visits, decay, lapses, the tree's
--   attributes); :carry(id, n) -> taken; :carried(id) -> n; :drop(id) (the carried nuts are lost: a knock-out; the
--   body changing hands drops them by itself); :meter(hollowId) -> 0..1; :owner(hollowId) -> key?; :inside(id) ->
--   hollowId?; :mayBite(id); :isRefuge(id);
--   :healRate(id, fed); :heal(id, health, maxHealth, dt, fed); :surface(x, y, z) -> (x, y, z, yaw)?; :stop(); C;
--   under(layout, world, x, y, z, actor?) -> space? (the cover test)
-- Studs and the HTML yaw (Brains/Common). Engine calls only in start and the tree's attributes. No side effects on
-- require.

local Import = require("../Import")
local HollowClaim = Import.shared("Foraging/HollowClaim") :: typeof(require("../../shared/Foraging/HollowClaim"))
local HollowLayout = Import.shared("World/HollowLayout") :: typeof(require("../../shared/World/HollowLayout"))
local Tunables = Import.shared("Config/Tunables") :: typeof(require("../../shared/Config/Tunables"))
local Cover = Import.shared("Combat/Cover") :: typeof(require("../../shared/Combat/Cover"))
local TownAI = require("../AI/TownAI")
local HollowShell = require("../World/HollowShell")

type Layout = typeof(HollowLayout.new(nil :: any))
type Hollow = typeof(((nil :: any) :: Layout).hollows[1])
type Claim = typeof(HollowClaim.new())
type Who = string | number -- (Shared/Foraging/HollowClaim.Who)

local HollowService = {}
HollowService.__index = HollowService

HollowService.C = {
	pennant = { size = { 0.08, 0.9, 1.3 }, lift = 2.6, color = { 214, 120, 52 } }, -- the claim flag by the hole
}

export type Opts = {
	world: TownAI.World,
	layout: Layout?, -- default HollowLayout.default()
	cover: boolean?, -- default true (the threat grid's cover and the Combat/Cover shapes)
	-- the tree's attributes and pennant: called with (hollowId, attrs) whenever they change (start wires the models)
	show: ((hollowId: string, attrs: { [string]: any }) -> ())?,
	-- who a body's claims belong to (default: the body's id); a player's key keeps the claim theirs
	keyOf: ((id: number) -> Who)?,
	nameOf: ((key: Who) -> string?)?, -- a claimant's shown name (a player's), nil for the computer's
	-- the feet of a player's squirrel where the server holds it (Boot/Game: its last clean accepted motor packet); when
	-- given, a player's squirrel brings nuts in and visits by that place, never by the root its client moves (nil: it
	-- is in no hollow). The computer's squirrels by the AI world's own place, as before
	placeOf: ((id: number) -> (number?, number?, number?))?,
	-- start only
	parent: any?, -- default workspace
}

export type Service = typeof(setmetatable(
	{} :: {
		world: TownAI.World,
		layout: Layout,
		claims: { [string]: Claim },
		carrying: { [number]: number },
		carrier: { [number]: Who }, -- who held the body when it picked its nuts up
		shown: { [string]: string },
		show: (hollowId: string, attrs: { [string]: any }) -> (),
		keyOf: (id: number) -> Who,
		nameOf: (key: Who) -> string?,
		placeOf: ((id: number) -> (number?, number?, number?))?,
		uncover: () -> (),
		root: any?,
		parts: number,
	},
	HollowService
))

local function hollowOfSpace(layout: Layout, space: string?): Hollow?
	if space == nil then
		return nil
	end
	for _, h in layout.hollows do
		if h.space == space then
			return h
		end
	end
	return nil
end

function HollowService.new(opts: Opts): Service
	local layout = opts.layout or HollowLayout.default()
	assert(layout, "HollowService: no hollow layout (generated/HollowTrees.luau is not compiled)")
	local self = setmetatable({
		world = opts.world,
		layout = layout,
		claims = {},
		carrying = {},
		carrier = {},
		shown = {},
		show = opts.show or function() end,
		keyOf = opts.keyOf or function(id: number): Who
			return id
		end,
		nameOf = opts.nameOf or function(): string?
			return nil
		end,
		placeOf = opts.placeOf,
		uncover = function() end,
		root = nil,
		parts = 0,
	}, HollowService)
	for _, h in layout.hollows do
		if h.claimable then
			self.claims[h.id] = HollowClaim.new()
		end
	end
	if opts.cover ~= false then
		local world = opts.world
		local uncoverAI = TownAI.addCover(world, {
			under = function(x: number, y: number, z: number, actor: any?): string?
				return HollowService.under(layout, world, x, y, z, actor)
			end,
			surface = function(x: number, y: number, z: number): (number?, number?, number?, number?)
				return self:surface(x, y, z)
			end,
		})
		local keys = {}
		for _, h in layout.hollows do
			table.insert(
				keys,
				Cover.addShape({
					name = `hollow {h.id}`,
					test = function(x: number, y: number, z: number): boolean
						return layout.within(h, x, y, z)
					end,
				})
			)
		end
		self.uncover = function()
			uncoverAI()
			for _, key in keys do
				Cover.remove(key)
			end
		end
	end
	return self
end

-- under: the hollow space hiding a body at (x, y, z) (TownAI's cover test). A player's body is where it is drawn;
-- the computer's squirrel on a route is hidden only on that hollow's own runs (on the outside trunk its point, the
-- trunk's axis, is inside the cavity test)
function HollowService.under(layout: Layout, world: TownAI.World, x: number, y: number, z: number, actor: any?): string?
	local space = layout.contains(x, y, z)
	if space == nil or actor == nil or world.possessed[actor.id] then
		return space
	end
	local intent = actor.intent
	if intent and intent.mode == "rail" and layout.spaceOf(intent.routeId) ~= space then
		return nil
	end
	return space
end

-- start: the service and the shell in the workspace, each tree's model showing its meter and claim
function HollowService.start(opts: Opts): Service
	local models: { [string]: any } = {}
	local pennants: { [string]: any } = {}
	local self: Service
	local userShow = opts.show
	opts = table.clone(opts)
	opts.show = function(hollowId: string, attrs: { [string]: any })
		local m = models[hollowId]
		if m then
			for k, v in attrs do
				m:SetAttribute(k, v)
			end
		end
		local p = pennants[hollowId]
		if p then
			p.Transparency = if attrs.Claimed then 0 else 1
		end
		if userShow then
			userShow(hollowId, attrs)
		end
	end
	self = HollowService.new(opts)
	local root, report = HollowShell.build(
		{ Instance = Instance, CFrame = CFrame, Vector3 = Vector3, Color3 = Color3, Enum = Enum },
		self.layout,
		nil
	)
	local C = HollowService.C.pennant
	for _, h in self.layout.hollows do
		local m = root:FindFirstChild(h.id)
		models[h.id] = m
		if m and h.claimable then
			local hole = h.mouths[1]
			local ol = math.sqrt(hole.out[1] ^ 2 + hole.out[3] ^ 2)
			local ox, oz = hole.out[1] / ol, hole.out[3] / ol
			-- beside the hole, on the bark side of it, at a squirrel's eye and a little more
			local p = Instance.new("Part")
			p.Name = "ClaimPennant"
			p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
			p.Size = Vector3.new(C.size[1], C.size[2], C.size[3])
			p.Color = Color3.fromRGB(C.color[1], C.color[2], C.color[3])
			p.Material = Enum.Material.Fabric
			p.Transparency = 1
			local at = Vector3.new(hole.x - ox * 1.2 + oz * 1.4, hole.y + C.lift, hole.z - oz * 1.2 - ox * 1.4)
			p.CFrame = CFrame.lookAt(at, at + Vector3.new(oz, 0, -ox))
			p.Parent = m
			pennants[h.id] = p
		end
	end
	root.Parent = opts.parent or workspace
	self.root = root
	self.parts = report.parts
	return self
end

-- carry: squirrel `id` picks up n nuts (never more than forage.carryMax held); how many it took
function HollowService.carry(self: Service, id: number, n: number): number
	local key = self.keyOf(id)
	if self.carrier[id] ~= key then
		self:drop(id) -- (the body changed hands since it picked them up)
	end
	local held, taken = HollowClaim.carry(self.carrying[id] or 0, n, Tunables.get("forage.carryMax"))
	self.carrying[id] = held
	self.carrier[id] = key
	return taken
end

function HollowService.carried(self: Service, id: number): number
	return self.carrying[id] or 0
end

function HollowService.drop(self: Service, id: number)
	self.carrying[id] = nil
	self.carrier[id] = nil
end

-- the hollow whose cavity hides squirrel `id` (as of the last AI frame), nil in the open or down a drain
function HollowService.inside(self: Service, id: number): string?
	local h = hollowOfSpace(self.layout, TownAI.covered(self.world, id))
	return if h then h.id else nil
end

function HollowService.meter(self: Service, hollowId: string): number
	local c = self.claims[hollowId]
	local h = self.layout.hollow(hollowId)
	if c == nil or h == nil then
		return 0
	end
	return HollowClaim.meter(c, h.meter.capacity)
end

function HollowService.owner(self: Service, hollowId: string): Who?
	local c = self.claims[hollowId]
	return if c then c.owner else nil
end

-- spaceOf(actor): the hollow space a squirrel brings its nuts into: a player's by where the server holds it (placeOf),
-- the computer's by the AI world's cover
function HollowService.spaceOf(self: Service, actor: any): string?
	if self.placeOf and self.world.possessed[actor.id] then
		local x, y, z = self.placeOf(actor.id)
		return if x and y and z then self.layout.contains(x, y + (actor.hip or 0), z) else nil
	end
	return TownAI.covered(self.world, actor.id)
end

-- step(day): every squirrel inside a claimable hollow brings in what it carries and visits; then each hollow's decay
-- and lapse as of `day` (fractional game days), and its attributes when they changed
function HollowService.step(self: Service, day: number)
	local ownAt = Tunables.get("forage.ownThreshold")
	local margin = Tunables.get("forage.keepMargin")
	for _, actor in self.world.actors do
		if actor.species ~= "squirrel" or actor.variant == "spicy" then
			continue -- (the Spicy Rodent rests in any hollow but claims none)
		end
		local key = self.keyOf(actor.id)
		if self.carrying[actor.id] and self.carrier[actor.id] ~= key then
			self:drop(actor.id) -- the body changed hands: what it carried is gone
		end
		local h = hollowOfSpace(self.layout, HollowService.spaceOf(self, actor))
		local c = if h then self.claims[h.id] else nil
		if h and c then
			local held = self.carrying[actor.id] or 0
			if held > 0 then
				self.carrying[actor.id] = held - HollowClaim.deposit(c, key, held, day, h.meter.capacity, ownAt, margin)
			else
				HollowClaim.visit(c, key, day)
			end
		end
	end
	for _, h in self.layout.hollows do
		local c = self.claims[h.id]
		if c == nil then
			continue
		end
		HollowClaim.update(
			c,
			day,
			h.meter.capacity,
			ownAt,
			Tunables.get("forage.ownVisitDays"),
			Tunables.get("forage.meterDecayPerDay"),
			margin
		)
		local meter = math.floor(HollowClaim.meter(c, h.meter.capacity) * 100 + 0.5) / 100
		local attrs = {
			Meter = meter,
			Owner = if c.owner ~= nil then tostring(c.owner) else "",
			OwnerName = if c.owner then self.nameOf(c.owner) or "a squirrel" else "",
			Claimed = c.owner ~= nil,
		}
		local key = `{attrs.Meter}|{attrs.Owner}|{attrs.OwnerName}`
		if self.shown[h.id] ~= key then
			self.shown[h.id] = key
			self.show(h.id, attrs)
		end
	end
end

function HollowService.mayBite(self: Service, id: number): boolean
	return self:inside(id) == nil
end

function HollowService.isRefuge(self: Service, id: number): boolean
	return self:inside(id) ~= nil
end

-- hp per second the body heals here: the hollow rate for the Spicy Rodent inside while fed, else 0
function HollowService.healRate(self: Service, id: number, fed: boolean): number
	local actor = self.world.actorsById[id]
	if actor == nil or actor.variant ~= "spicy" or not fed or not self:isRefuge(id) then
		return 0
	end
	return Tunables.get("rodent.regenHollow")
end

function HollowService.heal(
	self: Service,
	id: number,
	health: number,
	maxHealth: number,
	dt: number,
	fed: boolean
): number
	if health <= 0 or health >= maxHealth then
		return health
	end
	return math.min(maxHealth, health + self:healRate(id, fed) * dt)
end

-- surface(x, y, z): where a body let go inside is put: its hollow's nearest ground mouth, facing out
function HollowService.surface(self: Service, x: number, y: number, z: number): (number?, number?, number?, number?)
	local h = hollowOfSpace(self.layout, self.layout.contains(x, y, z))
	if h == nil then
		return nil, nil, nil, nil
	end
	local best, bd = nil, math.huge
	for _, m in h.mouths do
		if m.opens == "ground" then
			local d = (m.x - x) ^ 2 + (m.z - z) ^ 2
			if d < bd then
				best, bd = m, d
			end
		end
	end
	if best == nil then
		return nil, nil, nil, nil
	end
	return best.x, best.y, best.z, math.atan2(best.out[1], best.out[3])
end

function HollowService.stop(self: Service)
	self.uncover()
	self.uncover = function() end
	if self.root then
		self.root:Destroy()
		self.root = nil
	end
end

return HollowService
