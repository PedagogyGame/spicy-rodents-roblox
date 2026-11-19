--!strict
-- ServerScriptService.Server.Foraging.ForageService
-- Nut foraging on the server (owner D16 #22 "build next"; brief v2 §7; Shared/Foraging/NutSpots and ForageRules):
--   * The spots: every NutSpots spot holds its kind's nuts and grows them back on the game clock (ForageRules.regrow,
--     once a second). start() lays each spot's acorns on the ground under Workspace.NutSpots (a Model per spot with
--     attributes Nuts, Kind and Near; one acorn shown per nut there).
--   * Pick-ups are the server's alone: no remote asks for one. Ten times a second (C.look) each player's squirrel is
--     looked for at the spots where the server holds it: opts.placeOf(id), the place of its last accepted motor
--     packet when that one was clean (Boot/Game: Movement/MovementService.motorOf), never the root its client moves
--     (no packet yet, or a flagged one, picks nothing up). Within ForageRules reach of a spot with nuts, with room in
--     its paws and C.gap since its last nut, it picks one up: HollowService.carry (the carried count lives there:
--     the body carries the nuts, and the hollow deposit reads it), then opts.onPick (the body's PickAt stamp for the
--     dip, the HUD). With its paws full there it is told once (opts.onFull) until it leaves the spot.
--   * The computer's squirrels (lightly: ForageRules C.ai*): every C.aiEvery seconds, one in reach of a spot eats a
--     nut there (opts.onPick with ai = true; nothing carried), and one that near a spot with nuts may be sent to its
--     route's nearest point to nibble (its brain's "bait" event). Their place is the AI world's (the server's own).
--   * The Spicy Rodent picks nothing up (ForageRules.forages).
-- Interface: new(opts) -> Service; start(opts) -> Service (new, and the acorns in the workspace); Service:step(dt,
--   now) (every frame is fine: it keeps its own pace); :left(spotId) -> number; :spotAt(x, y, z) -> Spot? (the spot
--   whose reach holds the point); :stop(); C (the acorn's look)
-- Studs. Engine calls only in start/stop and the acorns' visibility. No side effects on require.

local Import = require("../Import")
local ForageRules = Import.shared("Foraging/ForageRules") :: typeof(require("../../shared/Foraging/ForageRules"))
local NutSpots = Import.shared("Foraging/NutSpots") :: typeof(require("../../shared/Foraging/NutSpots"))
local Tunables = Import.shared("Config/Tunables") :: typeof(require("../../shared/Config/Tunables"))
local TownAI = require("../AI/TownAI")

-- (the exported types do not cross the Import cast)
type Spot = typeof(NutSpots.SPOTS[1])
type SpotState = typeof(ForageRules.newSpot(0, 0))

local ForageService = {}
ForageService.__index = ForageService

-- an acorn: a nut and its cap (two plain parts, no shadow, no collision, no queries), the pile on a ring round the
-- spot's middle
ForageService.C = table.freeze({
	nut = { size = 0.5, color = { 150, 98, 52 } },
	cap = { height = 0.16, size = 0.52, color = { 96, 68, 42 } },
	ring = 0.45, -- studs from the middle to each acorn of a pile (the first one in the middle)
})

export type Opts = {
	world: TownAI.World,
	hollows: any, -- Foraging/HollowService (carry(id, n) -> taken; carried(id) -> n)
	-- the feet of a player's squirrel where the server holds it (nil: nowhere it trusts: no pick-up)
	placeOf: (id: number) -> (number?, number?, number?),
	groundAt: (x: number, z: number) -> number,
	day: () -> number, -- fractional game days
	spots: { Spot }?, -- default NutSpots.SPOTS
	onPick: ((id: number, spot: Spot, held: number, ai: boolean) -> ())?,
	onFull: ((id: number, spot: Spot) -> ())?,
	show: ((spot: Spot, left: number) -> ())?, -- a spot's count changed (start wires the acorns)
	rng: (() -> number)?,
	-- start only
	parent: any?, -- default workspace
}

export type Service = typeof(setmetatable(
	{} :: {
		world: TownAI.World,
		hollows: any,
		placeOf: (id: number) -> (number?, number?, number?),
		day: () -> number,
		spots: { Spot },
		state: { [string]: SpotState },
		y: { [string]: number },
		squirrels: { any },
		last: { [number]: number },
		full: { [number]: string },
		onPick: (id: number, spot: Spot, held: number, ai: boolean) -> (),
		onFull: (id: number, spot: Spot) -> (),
		show: (spot: Spot, left: number) -> (),
		rng: () -> number,
		lookAcc: number,
		aiAcc: number,
		growAcc: number,
		root: any?,
		parts: number,
		picks: { player: number, ai: number },
	},
	ForageService
))

function ForageService.new(opts: Opts): Service
	local spots = opts.spots or NutSpots.SPOTS
	local day = opts.day()
	local state, ys = {}, {}
	for _, s in spots do
		state[s.id] = ForageRules.newSpot(NutSpots.stockOf(s), day)
		ys[s.id] = opts.groundAt(s.x, s.z)
	end
	-- the town's squirrels are fixed bodies (never destroyed): the list once
	local squirrels = {}
	for _, a in opts.world.actors do
		if a.species == "squirrel" then
			table.insert(squirrels, a)
		end
	end
	local seed = 7
	return setmetatable({
		world = opts.world,
		hollows = opts.hollows,
		placeOf = opts.placeOf,
		day = opts.day,
		spots = spots,
		state = state,
		y = ys,
		squirrels = squirrels,
		last = {},
		full = {},
		onPick = opts.onPick or function() end,
		onFull = opts.onFull or function() end,
		show = opts.show or function() end,
		rng = opts.rng or function(): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end,
		lookAcc = 0,
		aiAcc = 0,
		growAcc = 0,
		root = nil,
		parts = 0,
		picks = { player = 0, ai = 0 },
	}, ForageService)
end

function ForageService.left(self: Service, spotId: string): number
	local s = self.state[spotId]
	return if s then s.left else 0
end

-- the spot whose reach holds a player's squirrel's feet at (x, y, z), the one with nuts first
function ForageService.spotAt(self: Service, x: number, y: number, z: number): Spot?
	local C = ForageRules.C
	local found: Spot? = nil
	for _, s in self.spots do
		if ForageRules.inReach(s.x, self.y[s.id], s.z, x, y, z, C.reach, C.rise) then
			if self.state[s.id].left > 0 then
				return s
			end
			found = found or s
		end
	end
	return found
end

local function pick(self: Service, id: number, s: Spot, now: number, day: number, ai: boolean)
	if not ForageRules.take(self.state[s.id], NutSpots.stockOf(s), day) then
		return
	end
	self.last[id] = now
	local held = 0
	if ai then
		self.picks.ai += 1
	else
		self.hollows:carry(id, 1)
		held = self.hollows:carried(id)
		self.picks.player += 1
	end
	self.show(s, self.state[s.id].left)
	self.onPick(id, s, held, ai)
end

-- the players' squirrels, where the server holds each
local function lookPlayers(self: Service, now: number, day: number)
	local max = Tunables.get("forage.carryMax")
	local gap = ForageRules.C.gap
	for _, a in self.squirrels do
		local id = a.id
		if not self.world.possessed[id] or not ForageRules.forages(a.species, a.variant) then
			self.full[id] = nil
			continue
		end
		local x, y, z = self.placeOf(id)
		local s = if x and y and z then self:spotAt(x, y, z) else nil
		if s == nil or self.state[s.id].left < 1 then
			self.full[id] = nil
			continue
		end
		if self.hollows:carried(id) >= max then
			if self.full[id] ~= s.id then
				self.full[id] = s.id
				self.onFull(id, s)
			end
			continue
		end
		self.full[id] = nil
		if ForageRules.ready(self.last[id], now, gap) then
			pick(self, id, s, now, day, false)
		end
	end
end

-- the computer's squirrels: eat at a spot in reach; perhaps head for one near
local function lookAI(self: Service, now: number, day: number)
	local C = ForageRules.C
	for _, a in self.squirrels do
		local id = a.id
		if self.world.possessed[id] or not ForageRules.forages(a.species, a.variant) then
			continue
		end
		local feet = a.y - (a.hip or 0)
		local best: Spot?, bestD = nil, math.huge
		for _, s in self.spots do
			if self.state[s.id].left < 1 then
				continue
			end
			local dx, dz = a.x - s.x, a.z - s.z
			local d = dx * dx + dz * dz
			if d < bestD then
				best, bestD = s, d
			end
		end
		if best == nil then
			return -- (nothing left anywhere)
		end
		local s = best :: Spot
		if ForageRules.inReach(s.x, self.y[s.id], s.z, a.x, feet, a.z, C.aiReach, C.aiRise) then
			if ForageRules.ready(self.last[id], now, C.aiEvery) then
				pick(self, id, s, now, day, true)
				local brain = self.world.brains[id]
				if brain then
					brain:onEvent({ type = "bait", x = s.x, z = s.z, untilTime = self.world.now + C.aiNibble })
				end
			end
		elseif bestD <= C.aiNotice * C.aiNotice and self.rng() < C.aiChance then
			local brain = self.world.brains[id]
			if brain then
				brain:onEvent({ type = "bait", x = s.x, z = s.z, untilTime = self.world.now + C.aiNibble * 2 })
			end
		end
	end
end

function ForageService.step(self: Service, dt: number, now: number)
	self.lookAcc += dt
	self.aiAcc += dt
	self.growAcc += dt
	local day: number? = nil
	if self.growAcc >= 1 then
		self.growAcc = 0
		day = self.day()
		for _, s in self.spots do
			local st = self.state[s.id]
			if ForageRules.regrow(st, NutSpots.stockOf(s), NutSpots.regrowDaysOf(s), day :: number) then
				self.show(s, st.left)
			end
		end
	end
	if self.lookAcc >= ForageRules.C.look then
		self.lookAcc = 0
		day = day or self.day()
		lookPlayers(self, now, day :: number)
	end
	if self.aiAcc >= ForageRules.C.aiEvery then
		self.aiAcc = 0
		day = day or self.day()
		lookAI(self, now, day :: number)
	end
end

-- start: the service, and each spot's acorns on the ground (one shown per nut there)
function ForageService.start(opts: Opts): Service
	local acorns: { [string]: { { any } } } = {}
	local models: { [string]: any } = {}
	local userShow = opts.show
	opts = table.clone(opts)
	opts.show = function(spot: Spot, left: number)
		local m = models[spot.id]
		if m then
			m:SetAttribute("Nuts", left)
		end
		local list = acorns[spot.id]
		if list then
			for i, pair in list do
				local t = if i <= left then 0 else 1
				pair[1].Transparency, pair[2].Transparency = t, t
			end
		end
		if userShow then
			userShow(spot, left)
		end
	end
	local self = ForageService.new(opts)
	local C = ForageService.C
	local root = Instance.new("Folder")
	root.Name = "NutSpots"
	local function part(name: string, size: Vector3, cf: CFrame, color: { number }, shape: Enum.PartType): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.CFrame = cf
		p.Color = Color3.fromRGB(color[1], color[2], color[3])
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
		return p
	end
	for _, s in self.spots do
		local m = Instance.new("Model")
		m.Name = s.id
		m:SetAttribute("Kind", s.kind)
		m:SetAttribute("Near", s.near)
		local y = self.y[s.id]
		local stock = NutSpots.stockOf(s)
		local list = {}
		for i = 1, stock do
			local a = (i - 2) * 2 * math.pi / math.max(1, stock - 1) + #s.id
			local r = if i == 1 then 0 else C.ring
			local x, z = s.x + math.sin(a) * r, s.z + math.cos(a) * r
			local tilt = CFrame.Angles(0, a, 0.25 * ((i % 3) - 1))
			local nut = part(
				"Nut",
				Vector3.new(C.nut.size, C.nut.size, C.nut.size),
				CFrame.new(x, y + C.nut.size / 2, z) * tilt,
				C.nut.color,
				Enum.PartType.Ball
			)
			local cap = part(
				"Cap",
				Vector3.new(C.cap.height, C.cap.size, C.cap.size),
				CFrame.new(x, y + C.nut.size * 0.85, z) * tilt * CFrame.Angles(0, 0, math.pi / 2),
				C.cap.color,
				Enum.PartType.Cylinder
			)
			nut.Parent, cap.Parent = m, m
			table.insert(list, { nut, cap })
			self.parts += 2
		end
		acorns[s.id] = list
		models[s.id] = m
		m:SetAttribute("Nuts", self.state[s.id].left)
		m.Parent = root
	end
	root.Parent = opts.parent or workspace
	self.root = root
	return self
end

function ForageService.stop(self: Service)
	if self.root then
		self.root:Destroy()
		self.root = nil
	end
end

return ForageService
