--!strict
-- ServerScriptService.Server.Roles.RoleService
-- Executes Ladder transitions (BUILD_PLAN §1.4, §1.5 "Join", "The 49-slot server", §3.7; Addendum B4;
-- D34). Extends spike S2's minimum (onJoin/onLeave/admittedCount keep their contract):
--   onJoin(player): the 50th arrival is kicked BEFORE any body or profile is touched and never counts;
--     everyone else joins as a lowest-rank townsperson and possesses the body `pickBody(player, "human")`.
--   onLeave(player): release first (§1.5 "Release"), then the Ladder's leave row; a scarce slot left
--     behind is offered at once.
--   report(event): Ladder.resolve + apply; vacated scarce slots are offered in the same step.
--   Offers: one live offer per rung, candidates in Ladder order, Accept / Deer / Fox / Stay, offerTimeout
--     per candidate, offerCascade candidates, then a retry after offerRetry with fresh candidates.
--   step(now): offer timeouts and the idle release (warn afkWarnSecs before afkSecs; input() cancels).
--   forceRole (Role Lab): moves a player to any rung, logging when that exceeds the rung's cap.
-- Body changes go through Possession:swap (rule 12: Possession's onHandoff wires SweptCollision and
-- MoveValidator). Pure Luau over injected deps, so Lune drives it with PlayerLike stubs.
-- No side effects on require.
-- Interface: new(deps) -> Roles; Roles:onJoin(player) -> JoinResult, onLeave(player), admittedCount(),
--            report(event) -> {Transition}, roleOf(player) -> (rung?, subrole?), stats(player), queue(rung),
--            reply(player, offerId, choice) -> (ok, err?), offers(), input(player, now?), step(now),
--            forceRole(player, rung) -> (ok, overCap), resetSession(winnerId?), member(userId), ctx()

local Import = require("../Import")
local Ladder = Import.shared("Roles/Ladder") :: typeof(require("../../shared/Roles/Ladder"))
local Wallet = Import.shared("Economy/Wallet") :: typeof(require("../../shared/Economy/Wallet"))
local ReputationRules =
	Import.shared("Reputation/ReputationRules") :: typeof(require("../../shared/Reputation/ReputationRules"))
local Log = Import.shared("Util/Log") :: typeof(require("../../shared/Util/Log"))

-- Exported types do not cross the Import shim (rule 1), so the Ladder shapes are restated loosely.
type Transition = { [string]: any }
type LadderPlayer = {
	id: any,
	rung: string,
	subrole: string?,
	stats: { [string]: any },
	infected: boolean?,
	noOffers: boolean?,
	remembered: { [string]: any }?,
}
type Offer = { [string]: any }
type Ctx = { [string]: any }
type Stats = { [string]: any }
type Purse = {
	cents: number,
	history: { any },
	credit: (any, number, string) -> (boolean, string?),
	debit: (any, number, string) -> (boolean, string?),
}

export type JoinResult = "admitted" | "possessed" | "kicked"

export type Deps = {
	possession: any, -- Server/Actors/Possession Service (possess, release, swap)
	pickBody: (player: any, rung: string?) -> any?, -- an Actor for the rung, or nil when none is free
	maxPlayers: number?, -- test override; default Ladder.server.maxPlayers (49)
	kick: ((player: any, message: string) -> ())?, -- default player:Kick(message)
	now: (() -> number)?, -- seconds (default os.clock)
	notify: ((player: any, kind: string, data: any) -> ())?, -- offers, idle warnings, toasts
	onTransition: ((t: Transition) -> ())?, -- InfectionService, PoliceService, HUD hooks
}

export type Member = LadderPlayer & { player: any, purse: Purse, jailedUntil: number? }

export type LiveOffer = {
	id: string,
	offer: Offer,
	index: number, -- current candidate
	sentAt: number,
	retryAt: number?, -- set once the cascade is exhausted
}

export type Roles = {
	deps: Deps,
	admitted: { [number]: boolean },
	admittedN: number,
	kicked: number,
	members: { [number]: Member },
	policePerformance: number,
	droneUnlocked: boolean,
	rodentInfectedShare: number,
	squirrelBodiesFree: number,
	live: { [string]: LiveOffer }, -- by rung
	lastInput: { [number]: number },
	warned: { [number]: boolean },
	log: any,
	history: { Transition },
	onJoin: (self: Roles, player: any) -> JoinResult,
	onLeave: (self: Roles, player: any) -> (),
	admittedCount: (self: Roles) -> number,
	ctx: (self: Roles) -> Ctx,
	member: (self: Roles, userId: number) -> Member?,
	report: (self: Roles, event: { [string]: any }) -> { Transition },
	roleOf: (self: Roles, player: any) -> (string?, string?),
	stats: (self: Roles, player: any) -> Stats?,
	queue: (self: Roles, rung: string) -> { any },
	offers: (self: Roles) -> { [string]: LiveOffer },
	reply: (self: Roles, player: any, offerId: string, choice: string) -> (boolean, string?),
	input: (self: Roles, player: any, now: number?) -> (),
	step: (self: Roles, now: number) -> (),
	forceRole: (self: Roles, player: any, rung: string) -> (boolean, boolean),
	resetSession: (self: Roles, winner: number?) -> { Transition },
	refreshKeys: (self: Roles) -> (),
}

local RoleService = {}

local HUMAN_SPECIES = { human = true, hospital = true, police = true } :: { [string]: boolean }
local SCARCE = { rodent = true, squirrel = true, deer = true, fox = true, hospital = true, police = true } :: {
	[string]: boolean,
}

local offerSeq = 0

function RoleService.new(deps: Deps): Roles
	local clock = deps.now or os.clock
	local roles = {
		deps = deps,
		admitted = {},
		admittedN = 0,
		kicked = 0,
		members = {},
		policePerformance = 0,
		droneUnlocked = false,
		rodentInfectedShare = 0,
		squirrelBodiesFree = 0,
		live = {},
		lastInput = {},
		warned = {},
		log = Log.new("Roles"),
		history = {},
	} :: Roles

	local function players(self: Roles): { [any]: LadderPlayer }
		return self.members :: any
	end

	function roles.ctx(self: Roles): Ctx
		return {
			players = players(self),
			admitted = self.admittedN,
			policePerformance = self.policePerformance,
			rodentInfectedShare = self.rodentInfectedShare,
			squirrelBodiesFree = self.squirrelBodiesFree,
		}
	end

	function roles.member(self: Roles, userId: number): Member?
		return self.members[userId]
	end

	local function notify(m: Member?, kind: string, data: any)
		if m and deps.notify then
			deps.notify(m.player, kind, data)
		end
	end

	-- Moves a member's body when its rung's species changes (or always for rung changes, so the new
	-- role's body is used); a failed pick leaves the current body (logged).
	local function moveBody(self: Roles, m: Member, rung: string)
		local actor = deps.pickBody(m.player, rung)
		if not actor then
			self.log:every(`nobody:{rung}`, 10, "warn", `no free body for {rung}; {m.id} keeps the current one`)
			return
		end
		if deps.possession:actorOf(m.player) then
			deps.possession:swap(m.player, actor)
		else
			deps.possession:possess(m.player, actor)
		end
	end

	local function setRung(self: Roles, m: Member, to: string, rank: string)
		local from = m.rung
		if HUMAN_SPECIES[from] and not HUMAN_SPECIES[to] then
			m.remembered = table.clone(m.stats) -- the human standing to return to (§6 side exits, winter)
		end
		m.stats = Ladder.applyRank(rank, m.stats, m.remembered)
		if not HUMAN_SPECIES[from] and HUMAN_SPECIES[to] then
			m.remembered = nil
		end
		if to ~= from then
			m.subrole = nil
			m.rung = to
			if to ~= "squirrel" then
				m.infected = nil
			end
			moveBody(self, m, to)
		end
	end

	local resolveAndApply: (self: Roles, event: { [string]: any }) -> { Transition }

	local function openOffer(self: Roles, o: Offer)
		local live = self.live[o.rung]
		if live and not live.retryAt then
			return -- one live offer per rung
		end
		offerSeq += 1
		local id = `{o.rung}#{offerSeq}`
		local lo: LiveOffer = { id = id, offer = o, index = 1, sentAt = clock(), retryAt = nil }
		self.live[o.rung] = lo
		if #o.candidates == 0 then
			lo.retryAt = clock() + o.retry
			return
		end
		notify(
			self.members[o.candidates[1]],
			"offer",
			{ id = id, rung = o.rung, choices = o.choices, timeout = o.timeout }
		)
	end

	local function apply(self: Roles, t: Transition)
		table.insert(self.history, t)
		if #self.history > 200 then
			table.remove(self.history, 1)
		end
		local m = if t.player ~= nil then self.members[t.player] else nil
		if t.kick then
			return
		end
		if m then
			if t.to and not t.refused then
				setRung(self, m, t.to, t.rank or "keep")
			elseif t.rank and not t.to then
				m.stats = Ladder.applyRank(t.rank, m.stats, m.remembered)
			end
			if t.loseSubrole then
				m.subrole = nil
			end
			if t.rankDelta then
				m.stats.questScore = (m.stats.questScore or 0) + t.rankDelta
				if t.rule == "kick.landed" then
					m.stats.kicks = (m.stats.kicks or 0) + 1
				end
			end
			if t.reputation then
				m.stats.reputation = ReputationRules.tick(m.stats.reputation or 0, t.reputation)
			end
			local pay = (t.pay or 0) + (t.tip or 0)
			if pay > 0 then
				m.purse:credit(pay, t.rule)
				m.stats.cents = m.purse.cents
			end
			if t.penalty then
				m.stats.nuts = math.floor((m.stats.nuts or 0) * (1 - t.penalty.nutsLostPct))
				m.stats.queueDrop = (m.stats.queueDrop or 0) + t.penalty.queueDrop
				m.infected = true
			end
			if t.jail then
				m.jailedUntil = clock() + t.jail
			end
			if t.keys == "revoke" then
				m.subrole = nil
			end
		end
		if t.unlock == "policeSlots" then
			self.log:info(`police slots now {t.value}`)
		elseif t.unlock == "drone" then
			self.droneUnlocked = true
		end
		if t.offer then
			openOffer(self, t.offer)
		end
		if deps.onTransition then
			deps.onTransition(t)
		end
	end

	resolveAndApply = function(self: Roles, event: { [string]: any }): { Transition }
		local ctx = self:ctx()
		local ts = Ladder.resolve(event, ctx)
		local vacated = Ladder.vacated(ts, ctx)
		for _, t in ts do
			apply(self, t)
		end
		for _, rung in vacated do
			for _, t in Ladder.resolve({ kind = "slot.open", rung = rung }, self:ctx()) do
				apply(self, t)
				table.insert(ts, t)
			end
		end
		self:refreshKeys()
		return ts
	end

	function roles.report(self: Roles, event: { [string]: any }): { Transition }
		return resolveAndApply(self, event)
	end

	function roles.onJoin(self: Roles, player: any): JoinResult
		local key = player.UserId :: number
		if self.admitted[key] then
			return "admitted"
		end
		local admits = if deps.maxPlayers then self.admittedN < deps.maxPlayers else Ladder.admits(self.admittedN)
		if not admits then
			-- rule "admit" (Addendum B4): before any body or profile is touched
			self.kicked += 1
			if deps.kick then
				deps.kick(player, Ladder.FULL_MESSAGE)
			else
				(player :: Player):Kick(Ladder.FULL_MESSAGE)
			end
			return "kicked"
		end
		self.admitted[key] = true
		self.admittedN += 1
		local m = {
			id = key,
			player = player,
			rung = "human",
			stats = { activeMinutes = 0, activeGameDays = 0, cents = 0, reputation = 0 },
			purse = Wallet.purse(0),
		} :: Member
		self.members[key] = m
		self.lastInput[key] = clock()
		local ts = Ladder.resolve({ kind = "join", player = key }, self:ctx())
		for _, t in ts do
			table.insert(self.history, t)
		end
		local actor = deps.pickBody(player, "human")
		if actor then
			local ok = deps.possession:possess(player, actor)
			if ok then
				return "possessed"
			end
		end
		return "admitted"
	end

	function roles.onLeave(self: Roles, player: any)
		local key = player.UserId :: number
		-- release first, before anything else (also for a kicked player: a no-op)
		deps.possession:release(player, "leave")
		local m = self.members[key]
		if self.admitted[key] then
			self.admitted[key] = nil
			self.admittedN -= 1
		end
		if not m then
			return
		end
		Ladder.resolve({ kind = "leave", player = key }, self:ctx())
		local rung = m.rung
		self.members[key] = nil
		self.lastInput[key] = nil
		self.warned[key] = nil
		if SCARCE[rung] and rung ~= "deer" and rung ~= "fox" then
			for _, t in Ladder.resolve({ kind = "slot.open", rung = rung }, self:ctx()) do
				apply(self, t)
			end
		end
		self:refreshKeys()
	end

	function roles.admittedCount(self: Roles): number
		return self.admittedN
	end

	function roles.roleOf(self: Roles, player: any): (string?, string?)
		local m = self.members[player.UserId]
		if not m then
			return nil, nil
		end
		return m.rung, m.subrole
	end

	function roles.stats(self: Roles, player: any): Stats?
		local m = self.members[player.UserId]
		return if m then m.stats else nil
	end

	function roles.queue(self: Roles, rung: string): { any }
		return Ladder.rankOrder(rung, players(self))
	end

	function roles.offers(self: Roles): { [string]: LiveOffer }
		return self.live
	end

	local function advance(self: Roles, lo: LiveOffer)
		lo.index += 1
		lo.sentAt = clock()
		local nextId = lo.offer.candidates[lo.index]
		if nextId == nil or not self.members[nextId] then
			-- cascade exhausted: the AI keeps the slot; retry later with fresh candidates
			lo.retryAt = clock() + lo.offer.retry
			return
		end
		notify(self.members[nextId], "offer", { id = lo.id, rung = lo.offer.rung, choices = lo.offer.choices })
	end

	function roles.reply(self: Roles, player: any, offerId: string, choice: string): (boolean, string?)
		local key = player.UserId :: number
		local lo: LiveOffer? = nil
		for _, o in self.live do
			if o.id == offerId then
				lo = o
			end
		end
		if not lo or lo.retryAt then
			return false, "no such offer"
		end
		if lo.offer.candidates[lo.index] ~= key then
			return false, "not your offer"
		end
		local m = self.members[key] :: Member
		local rung = lo.offer.rung
		if choice == "accept" then
			local ctx = self:ctx()
			if Ladder.held(ctx, rung) >= Ladder.slots(rung, ctx) then
				self.live[rung] = nil
				return false, "slot taken"
			end
			self.live[rung] = nil
			local fromRung = m.rung
			local rank = if rung == "squirrel" then "lowestUninfected" else "keep"
			local t: Transition = { rule = `offer.accept.{rung}`, player = key, to = rung, rank = rank }
			apply(self, t)
			-- the accepted player's old scarce slot opens in turn (squirrel -> rodent opens a squirrel slot)
			if SCARCE[fromRung] and fromRung ~= "deer" and fromRung ~= "fox" then
				for _, t2 in Ladder.resolve({ kind = "slot.open", rung = fromRung, exclude = { key } }, self:ctx()) do
					apply(self, t2)
				end
			end
			self:refreshKeys()
			return true
		elseif choice == "deer" or choice == "fox" then
			local ts = resolveAndApply(self, { kind = "offer.sideExit", player = key, to = choice })
			if ts[1] and ts[1].refused then
				return false, ts[1].refused
			end
			advance(self, lo)
			return true
		elseif choice == "stay" then
			advance(self, lo)
			return true
		end
		return false, "bad choice"
	end

	function roles.input(self: Roles, player: any, now: number?)
		local key = player.UserId :: number
		self.lastInput[key] = now or clock()
		if self.warned[key] then
			self.warned[key] = nil
			notify(self.members[key], "idleCancel", nil)
		end
	end

	function roles.step(self: Roles, now: number)
		-- offers
		local rungs: { string } = {}
		for r in self.live do
			table.insert(rungs, r)
		end
		table.sort(rungs)
		for _, r in rungs do
			local lo = self.live[r]
			if lo.retryAt then
				if now >= lo.retryAt then
					self.live[r] = nil
					for _, t in Ladder.resolve({ kind = "slot.open", rung = r }, self:ctx()) do
						apply(self, t)
					end
				end
			elseif now - lo.sentAt >= lo.offer.timeout then
				advance(self, lo)
			end
		end
		-- jail time served (keys come back through refreshKeys)
		local ids: { number } = {}
		for id, m in self.members do
			table.insert(ids, id)
			if m.jailedUntil and now >= m.jailedUntil then
				m.jailedUntil = nil
			end
		end
		table.sort(ids)
		-- the idle release (D34)
		for _, id in ids do
			local m = self.members[id]
			if not m or (m.rung == "human" and not m.subrole) then
				continue
			end
			local idle = now - (self.lastInput[id] or now)
			if idle >= Ladder.params.afkSecs then
				self.warned[id] = nil
				self.lastInput[id] = now
				resolveAndApply(self, { kind = "afk", player = id })
			elseif idle >= Ladder.params.afkSecs - Ladder.params.afkWarnSecs and not self.warned[id] then
				self.warned[id] = true
				notify(m, "idleWarning", { secs = Ladder.params.afkSecs - idle })
			end
		end
	end

	-- Role Lab: any rung, regardless of caps (logged when over), through the same setRung path.
	function roles.forceRole(self: Roles, player: any, rung: string): (boolean, boolean)
		local m = self.members[player.UserId]
		if not m then
			return false, false
		end
		local ctx = self:ctx()
		local ok = pcall(Ladder.slots, rung, ctx)
		if not ok then
			return false, false
		end
		local overCap = m.rung ~= rung and Ladder.held(ctx, rung) >= Ladder.slots(rung, ctx)
		if overCap then
			self.log:warn(`forceRole: {m.id} -> {rung} exceeds the cap ({Ladder.slots(rung, ctx)})`)
		end
		apply(self, { rule = "lab.forceRole", player = m.id, to = rung, rank = "keep" })
		self:refreshKeys()
		return true, overCap
	end

	function roles.resetSession(self: Roles, winner: number?): { Transition }
		return resolveAndApply(self, { kind = "cinematic.finished", winner = winner })
	end

	-- Top-two keys (A1 patrol cars; brief v2 §15 pickups and SUVs). The drone stays with its holder.
	function roles.refreshKeys(self: Roles)
		local ps = players(self)
		for _, sub in { "driver", "humanDriver" } do
			local holders = Ladder.keyHolders(sub, ps)
			for _, m in self.members do
				local should = table.find(holders, m.id) ~= nil and not m.jailedUntil
				if should then
					m.subrole = sub
				elseif m.subrole == sub then
					m.subrole = nil
				end
			end
		end
	end

	return roles
end

return RoleService
