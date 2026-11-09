--!strict
-- ReplicatedStorage.Shared.Roles.Ladder
-- THE promotion ladder, stated once (BUILD_PLAN §3.7; brief v2 §4-§6, §8, §10, §11, §13, §13a, §15;
-- Addendum A1-A2, B4; D34). No other module restates slots, scores, transitions or the numbers they use
-- (tests/unit/ladder.spec.luau scans src/ for MaxPlayers/maxPlayers assignments, invariant 20).
-- Pure: resolve(event, ctx) returns transitions; Server/Roles/RoleService applies them.
--
-- Rank policies (how a transition sets standing; applyRank):
--   lowest            human queue terms earned by play reset (activeMinutes, kicks, questScore) and the
--                     queue drop cleared; money and reputation stay the player's (they are held, not
--                     earned rank: brief v2 §13a "queue rank = money plus reputation").
--   lowestUninfected  squirrel standing reset (nuts 0, stink 0, not infected).
--   remembered        the human stats snapshot taken when the player left the human rung (side exits,
--   rememberedHuman   squirrels), restored.
--   keep              unchanged (staff losing a slot on the idle release).
-- Interface: server, humanSlots, rungs, subroles, sideExits, params, rules; total(); admits(n);
--            slots(rung, ctx); held(ctx, rung); policeSlots(performance); score(rung, stats);
--            rankOrder(rung, players) -> {id}; keyHolders(subrole, players) -> {id}; candidates(take, players,
--            exclude?) -> {id}; applyRank(policy, stats, remembered?) -> stats; resolve(event, ctx) -> {Transition};
--            vacated(transitions, ctx) -> {rung}

local EconomyRules = require("../Economy/EconomyRules")
local GigRules = require("../Gigs/GigRules")

local Ladder = {}

-- Addendum B4: the place stays at 50; admit turns the 50th arrival away before any body or profile.
Ladder.server = table.freeze({ maxPlayers = 49, liveServerSize = 50 })
Ladder.FULL_MESSAGE = "This town is full (49 players). Please try another server."
-- brief v2 §5: 35 human-species player slots INCLUDING hospital and police (decision 28).
Ladder.humanSlots = table.freeze({ total = 35 })

-- stylua: ignore start
Ladder.rungs = table.freeze({
	human    = { tier = 1, species = "human", playerSlots = "humanSlots - tier2Held", label = "Townsperson" },
	hospital = { tier = 2, species = "human", playerSlots = 5, prestige = 2.1, label = "Hospital staff" },
	police   = { tier = 2, species = "human", playerSlots = { start = 5, max = 8 }, prestige = 2.0, label = "Police" },
	squirrel = { tier = 3, species = "squirrel", playerSlots = 7, label = "Squirrel" },
	rodent   = { tier = 4, species = "squirrel", variant = "spicy", playerSlots = 1, aiWhenUnheld = true, label = "Spicy rodent" },
})
Ladder.subroles = table.freeze({
	driver      = { parent = "police", slots = 2, pick = "topTwoByRank", handOver = "whenParked" },          -- A1
	drone       = { parent = "police", slots = 1, unlock = "upgrade:drone" },                               -- brief §10
	humanDriver = { parent = "human", slots = 2, pick = "topTwoByRank", handOver = "whenParked",
	                vehicles = { "pickup", "suv" }, undocumented = true },                                   -- brief v2 §15
})
Ladder.sideExits = table.freeze({
	deer = { species = "deer", playerSlots = 5, label = "Deer" },                -- brief v2 §5
	fox  = { species = "fox", playerSlots = 1, hidden = true, label = "Fox" },   -- Easter egg
})
-- 35 + 7 + 1 + 5 + 1 = 49 = maxPlayers (brief v2 §5).

Ladder.params = {
	w = { money = 1.0, reputation = 1.0, time = 0.25, entourage = 3.0, kick = 15, quest = 1.0 }, -- human queue (§13a, §6, A2)
	rankGateDays = 10,                                          -- in-game days before a human is ranked (§13a)
	wAdmin = { performance = 1.0, quest = 1.0, time = 0.2 },     -- tier-2 rank: performance only, never money (§13a)
	kickEvent = 25,                                             -- rank points per landed kick on the rodent or an infected squirrel (A2)
	rankClass = { minor = 4, standard = 6, major = 10 },
	rankBySpeed = { { 15, 10 }, { 30, 6 }, { 45, 3 } },          -- hospital fetch (A2): {within secs, points}
	offerTimeout = 15, offerCascade = 3, offerRetry = 60,
	recruitCascade = "seniority",
	killerHospitalIf = 0.30,                                    -- share of the town THIS rodent infected (brief §6)
	rodentReentry = 20,
	squirrelInfected = { nutsLostPct = 0.5, queueDrop = 2 },     -- decision 15
	infectedSquirrelHealth = 100, infectedSquirrelKick = 55,
	policeSlots = { [6] = 120, [7] = 260, [8] = 450 },           -- §4.9
	jail = { hitPedestrianSecs = 90, repeatOffenceSecs = 45 },   -- §15 dec 14
	afkSecs = 780, afkWarnSecs = 30,                             -- D34
}

-- One row per brief rule; `id` is what each Transition cites (tests prove every row fires).
local RULES: { { [string]: any } } = {
	{ id = "admit", on = "admit", when = "playersAtMax", kick = "serverFull" },                                -- B4
	{ id = "join", on = "join", to = "human", rank = "lowest" },                                               -- §4, §6
	{ id = "leave", on = "leave", release = true },
	{ id = "afk", on = "afk", rung = "rodent|squirrel|deer|fox|hospital|police|driver|drone|humanDriver", release = true,
	  to = "human", rank = { rodent = "lowest", squirrel = "rememberedHuman", side = "remembered", staff = "keep" } }, -- D34
	{ id = "rodent.died", on = "rodent.died", who = "rodent", to = "human", rank = "lowest" },                -- §6
	{ id = "rodent.died.infected", on = "rodent.died", who = "infectedSquirrels", to = "human", rank = "lowest" }, -- v2 §8
	{ id = "rodent.died.infection", on = "rodent.died", infection = "resetToNewRodent", cureHumans = "instantIfRecentOrEnRoute" }, -- v2 §8
	{ id = "rodent.killed", on = "rodent.killed", by = "human|police|driver", who = "killer",
	  to = { "squirrel:lowestUninfectedIfBodyFree", "hospital:ifRodentInfectedShareAbove(killerHospitalIf)", "police" } }, -- §6; v2 §15
	{ id = "rodent.killed.inHospital", on = "rodent.killed", by = "hospital", where = "inHospital", who = "killer",
	  to = "squirrel", rank = "lowestUninfected", instant = true, extraSlot = true },                         -- §6, §9
	{ id = "squirrel.infected", on = "squirrel.infected", who = "victim", penalty = "squirrelInfected" },       -- §6; dec 15
	{ id = "squirrel.killed", on = "squirrel.killed", by = "human|police|hospital|guard", who = "victim", to = "human", rank = "lowest" }, -- v2 §13a
	{ id = "squirrel.killed.slot", on = "squirrel.killed", bodyRespawns = "healthyFromNest",
	  slotTo = "topRanked:hospitalThenPoliceThenHuman", offer = true },                                        -- v2 §13a
	{ id = "winter.end", on = "winter.end.belowThreshold", who = "squirrel", to = "human", rank = "rememberedHuman" }, -- §12
	{ id = "slot.open.rodent", on = "slot.open", rung = "rodent", take = "topRanked:squirrel", offer = "immediate",
	  ai = "reenterAfter(rodentReentry)", cascade = "offerCascade" },                                          -- §6
	{ id = "slot.open.squirrel", on = "slot.open", rung = "squirrel", take = "topRanked:hospitalThenPoliceThenHuman", offer = true },
	{ id = "slot.open.hospital", on = "slot.open", rung = "hospital", take = "topRanked:human", offer = true },
	{ id = "slot.open.police", on = "slot.open", rung = "police", take = "topRanked:human", offer = true, cascade = "recruitCascade" },
	{ id = "police.performance.tier", on = "police.performance", offer = "police", to = "topRanked:human", cascade = "recruitCascade" }, -- v2 §13a
	{ id = "offer.sideExit", on = "offer.sideExit", to = "deer|fox", remember = "humanRank" },                 -- §5, §11
	{ id = "sideExit.leave", on = "sideExit.leave", to = "human", rank = "remembered" },                       -- §6
	{ id = "kick.landed", on = "kick.landed", target = "rodent|infectedSquirrel", who = "kicker", rankDelta = "kickEvent", reputation = "kick_landed" },
	{ id = "work.completed", on = "work.completed", who = "worker", pay = "fromJobOrGig", rankDelta = "rankClass" }, -- A2
	{ id = "gig.completed", on = "gig.completed", who = "worker", pay = "byQuality", reputation = "byQuality" },  -- v2 §13a
	{ id = "police.performance", on = "police.performance", unlock = "policeSlots" },                          -- §10
	{ id = "upgrade.bought.drone", on = "upgrade.bought", id_ = "drone", requires = "policeSlots=8", unlock = "drone" },
	{ id = "traffic.hitPedestrian", on = "traffic.hitPedestrian", by = "police", keys = "revoke", jail = "hitPedestrianSecs",
	  then_ = { to = "human", rank = "lowest" } },                                                             -- v2 §15 dec 14
	{ id = "traffic.repeatOffence", on = "traffic.repeatOffence", by = "any", jail = "repeatOffenceSecs" },    -- not in offroad
	{ id = "infection.criticalMass", on = "infection.criticalMass", who = "rodentPlayer", winner = true, cinematic = true }, -- §8
	{ id = "session.reset", on = "cinematic.finished|everyoneInfected", all = true, to = "human", rank = "lowest", reset = true,
	  except = { "winnerKeepsRodent", "infectedSquirrelsAliveKeepSquirrel" } },                                -- §8; v2 §13a
}
Ladder.rules = RULES
-- stylua: ignore end

export type Rung = string
export type Stats = {
	activeMinutes: number?,
	activeGameDays: number?,
	cents: number?,
	reputation: number?,
	entourage: number?,
	kicks: number?,
	questScore: number?,
	adminPerformance: number?,
	nuts: number?,
	cohortMaxNuts: number?,
	stinkPct: number?,
	queueDrop: number?,
}
export type Player = {
	id: any,
	rung: Rung,
	subrole: string?,
	stats: Stats,
	infected: boolean?,
	noOffers: boolean?, -- A2 free roam: "don't offer me promotions"
	remembered: Stats?, -- human stats snapshot while away from the human rung
}
export type Ctx = {
	players: { [any]: Player },
	admitted: number?, -- admit: players already admitted
	policePerformance: number?,
	rodentInfectedShare: number?, -- 0-1, the share of the town THIS rodent infected
	squirrelBodiesFree: number?, -- squirrel bodies with no player (Population)
	offroad: boolean?, -- traffic: the offence happened where police have no jurisdiction
}
export type Offer = {
	rung: Rung,
	candidates: { any },
	timeout: number,
	retry: number,
	cascade: string,
	choices: { string },
	immediate: boolean?,
	aiReentry: number?,
}
export type Transition = {
	rule: string,
	player: any?,
	to: Rung?,
	rank: string?,
	release: boolean?,
	kick: string?,
	admit: boolean?,
	offer: Offer?,
	rankDelta: number?,
	reputation: string?,
	pay: number?,
	tip: number?,
	penalty: { nutsLostPct: number, queueDrop: number }?,
	jail: number?,
	keys: string?,
	unlock: string?,
	value: any?,
	loseSubrole: string?,
	remember: boolean?,
	instant: boolean?,
	extraSlot: boolean?,
	infection: string?,
	cure: string?,
	bodyRespawn: string?,
	winner: boolean?,
	cinematic: boolean?,
	reset: boolean?,
	refused: string?,
}

local P = Ladder.params

-- The brief's arithmetic: 35 + 7 + 1 + 5 + 1.
function Ladder.total(): number
	return Ladder.humanSlots.total
		+ Ladder.rungs.squirrel.playerSlots
		+ Ladder.rungs.rodent.playerSlots
		+ Ladder.sideExits.deer.playerSlots
		+ Ladder.sideExits.fox.playerSlots
end

-- Rule "admit": true while fewer than maxPlayers are admitted (the 50th arrival is turned away).
function Ladder.admits(admitted: number): boolean
	return admitted < Ladder.server.maxPlayers
end

function Ladder.policeSlots(performance: number?): number
	local perf = performance or 0
	local n = Ladder.rungs.police.playerSlots.start
	for slots = n + 1, Ladder.rungs.police.playerSlots.max do
		local need = P.policeSlots[slots]
		if need and perf >= need then
			n = slots
		end
	end
	return n
end

function Ladder.held(ctx: Ctx, rung: Rung): number
	local n = 0
	for _, p in ctx.players do
		if p.rung == rung then
			n += 1
		end
	end
	return n
end

function Ladder.slots(rung: Rung, ctx: Ctx): number
	if rung == "human" then
		return Ladder.humanSlots.total - Ladder.held(ctx, "hospital") - Ladder.held(ctx, "police")
	elseif rung == "hospital" then
		return Ladder.rungs.hospital.playerSlots
	elseif rung == "police" then
		return Ladder.policeSlots(ctx.policePerformance)
	elseif rung == "squirrel" or rung == "rodent" then
		return (Ladder.rungs :: any)[rung].playerSlots
	elseif rung == "deer" or rung == "fox" then
		return (Ladder.sideExits :: any)[rung].playerSlots
	end
	error(`Ladder.slots: unknown rung {rung}`)
end

local function n(v: number?): number
	return v or 0
end

-- Scores (§3.7). Squirrel: 90 % nuts held now (relative to the cohort's best), 10 % stink gland.
-- Tier 2: performance, quests and time; money is never a term. Human queue: unranked before the gate.
function Ladder.score(rung: Rung, s: Stats): number
	if rung == "squirrel" or rung == "rodent" then
		return 0.9 * (n(s.nuts) / math.max(1, n(s.cohortMaxNuts))) + 0.1 * (n(s.stinkPct) / 100)
	end
	if rung == "hospital" or rung == "police" then
		local a = P.wAdmin
		return n(s.adminPerformance) * a.performance + n(s.questScore) * a.quest + n(s.activeMinutes) * a.time
	end
	if n(s.activeGameDays) < P.rankGateDays then
		return -math.huge -- "unranked"
	end
	local w = P.w
	return n(s.activeMinutes) * w.time
		+ EconomyRules.queueMoney(n(s.cents)) * w.money
		+ n(s.reputation) * w.reputation
		+ n(s.entourage) * w.entourage
		+ n(s.kicks) * w.kick
		+ n(s.questScore) * w.quest
end

local function idLess(a: any, b: any): boolean
	return tostring(a) < tostring(b)
end

-- Players on `rung`, best first: score, then seniority (activeMinutes), then id; a squirrel's
-- infection queue drop moves it down that many places afterwards. Unranked humans come last.
function Ladder.rankOrder(rung: Rung, players: { [any]: Player }): { any }
	local list: { Player } = {}
	for _, p in players do
		if p.rung == rung then
			table.insert(list, p)
		end
	end
	local scores: { [any]: number } = {}
	for _, p in list do
		scores[p.id] = Ladder.score(rung, p.stats)
	end
	table.sort(list, function(a, b)
		local sa, sb = scores[a.id], scores[b.id]
		if sa ~= sb then
			return sa > sb
		end
		local ma, mb = n(a.stats.activeMinutes), n(b.stats.activeMinutes)
		if ma ~= mb then
			return ma > mb
		end
		return idLess(a.id, b.id)
	end)
	local ids: { any } = {}
	for _, p in list do
		table.insert(ids, p.id)
	end
	-- apply queue drops, worst-dropped last so moves do not interfere
	for _, p in list do
		local drop = n(p.stats.queueDrop)
		if drop > 0 then
			local i = table.find(ids, p.id) :: number
			table.remove(ids, i)
			table.insert(ids, math.min(#ids + 1, i + drop), p.id)
		end
	end
	return ids
end

function Ladder.isRanked(p: Player): boolean
	return Ladder.score(p.rung, p.stats) > -math.huge
end

-- Top two by rank on the subrole's parent rung (A1 patrol cars; brief v2 §15 pickups and SUVs).
function Ladder.keyHolders(subrole: string, players: { [any]: Player }): { any }
	local def = (Ladder.subroles :: any)[subrole]
	assert(def, `Ladder.keyHolders: unknown subrole {subrole}`)
	local out = {}
	for _, id in Ladder.rankOrder(def.parent, players) do
		if #out >= def.slots then
			break
		end
		if Ladder.isRanked(players[id]) then
			table.insert(out, id)
		end
	end
	return out
end

local function eligible(p: Player, exclude: { [any]: boolean }?): boolean
	if p.noOffers or (exclude and exclude[p.id]) then
		return false
	end
	return Ladder.isRanked(p)
end

-- Ordered offer candidates for a `take` expression; truncated to offerCascade.
function Ladder.candidates(take: string, players: { [any]: Player }, exclude: { [any]: boolean }?): { any }
	local out: { any } = {}
	local function addFrom(rung: Rung, filter: ((p: Player) -> boolean)?)
		for _, id in Ladder.rankOrder(rung, players) do
			local p = players[id]
			if eligible(p, exclude) and (not filter or filter(p)) and not table.find(out, id) then
				table.insert(out, id)
			end
		end
	end
	if take == "topRanked:squirrel" then
		addFrom("squirrel", function(p)
			return not p.infected
		end)
	elseif take == "topRanked:hospitalThenPoliceThenHuman" then
		addFrom("hospital")
		addFrom("police")
		addFrom("human")
	elseif take == "topRanked:human" then
		addFrom("human")
	elseif take == "seniority:human" then
		-- §13a police recruitment: the top-ranked human first, then by time served
		local ranked: { any } = {}
		for _, id in Ladder.rankOrder("human", players) do
			if eligible(players[id], exclude) then
				table.insert(ranked, id)
			end
		end
		if #ranked > 0 then
			table.insert(out, ranked[1])
			table.remove(ranked, 1)
			table.sort(ranked, function(a, b)
				local ma, mb = n(players[a].stats.activeMinutes), n(players[b].stats.activeMinutes)
				if ma ~= mb then
					return ma > mb
				end
				return idLess(a, b)
			end)
			for _, id in ranked do
				table.insert(out, id)
			end
		end
	else
		error(`Ladder.candidates: unknown take {take}`)
	end
	while #out > P.offerCascade do
		table.remove(out)
	end
	return out
end

local function copyStats(s: Stats?): Stats
	return table.clone(s or {}) :: Stats
end

function Ladder.applyRank(policy: string, stats: Stats, remembered: Stats?): Stats
	if policy == "keep" then
		return copyStats(stats)
	elseif policy == "lowest" then
		local s = copyStats(stats)
		s.activeMinutes = 0
		s.kicks = 0
		s.questScore = 0
		s.queueDrop = 0
		return s
	elseif policy == "lowestUninfected" then
		local s = copyStats(stats)
		s.nuts = 0
		s.stinkPct = 0
		s.queueDrop = 0
		return s
	elseif policy == "remembered" or policy == "rememberedHuman" then
		local s = copyStats(stats)
		if remembered then
			for k, v in remembered :: any do
				(s :: any)[k] = v
			end
		end
		return s
	end
	error(`Ladder.applyRank: unknown policy {policy}`)
end

local function offer(rung: Rung, take: string, players: { [any]: Player }, exclude: { [any]: boolean }?): Offer
	local isRodent = rung == "rodent"
	local isPolice = rung == "police"
	local choices = { "accept", "deer", "fox", "stay" }
	return {
		rung = rung,
		candidates = Ladder.candidates(if isPolice then "seniority:human" else take, players, exclude),
		timeout = P.offerTimeout,
		retry = P.offerRetry,
		cascade = if isPolice then P.recruitCascade else "offerCascade",
		choices = choices,
		immediate = isRodent or nil,
		aiReentry = if isRodent then P.rodentReentry else nil,
	}
end

local SLOT_TAKE: { [string]: string } = {
	rodent = "topRanked:squirrel",
	squirrel = "topRanked:hospitalThenPoliceThenHuman",
	hospital = "topRanked:human",
	police = "topRanked:human",
}

local function findRung(ctx: Ctx, rung: Rung): Player?
	for _, p in ctx.players do
		if p.rung == rung then
			return p
		end
	end
	return nil
end

local function sortedPlayers(ctx: Ctx): { Player }
	local list: { Player } = {}
	for _, p in ctx.players do
		table.insert(list, p)
	end
	table.sort(list, function(a, b)
		return idLess(a.id, b.id)
	end)
	return list
end

local function rodentDied(ctx: Ctx, out: { Transition })
	local rodent = findRung(ctx, "rodent")
	if rodent then
		table.insert(out, { rule = "rodent.died", player = rodent.id, to = "human", rank = "lowest", release = true })
	end
	for _, p in sortedPlayers(ctx) do
		if p.rung == "squirrel" and p.infected then
			table.insert(
				out,
				{ rule = "rodent.died.infected", player = p.id, to = "human", rank = "lowest", release = true }
			)
		end
	end
	table.insert(
		out,
		{ rule = "rodent.died.infection", infection = "resetToNewRodent", cure = "instantIfRecentOrEnRoute" }
	)
end

local STAFF = { hospital = true, police = true }
local SIDE = { deer = true, fox = true }

type Handler = (event: { [string]: any }, ctx: Ctx, out: { Transition }) -> ()

local handlers: { [string]: Handler } = {}

handlers["admit"] = function(event, ctx, out)
	if Ladder.admits(ctx.admitted or 0) then
		table.insert(out, { rule = "admit", player = event.player, admit = true })
	else
		table.insert(out, { rule = "admit", player = event.player, kick = Ladder.FULL_MESSAGE })
	end
end

handlers["join"] = function(event, _ctx, out)
	table.insert(out, { rule = "join", player = event.player, to = "human", rank = "lowest" })
end

handlers["leave"] = function(event, _ctx, out)
	table.insert(out, { rule = "leave", player = event.player, release = true })
end

-- D34: the idle release. A plain townsperson is left alone.
handlers["afk"] = function(event, ctx, out)
	local p = ctx.players[event.player]
	if not p then
		return
	end
	local rank: string?
	if p.rung == "rodent" then
		rank = "lowest"
	elseif p.rung == "squirrel" then
		rank = "rememberedHuman"
	elseif SIDE[p.rung] then
		rank = "remembered"
	elseif STAFF[p.rung] then
		rank = "keep"
	end
	if rank then
		table.insert(
			out,
			{ rule = "afk", player = p.id, release = true, to = "human", rank = rank, loseSubrole = p.subrole }
		)
	elseif p.subrole then
		-- a human driver idle with the keys: loses the key, stays a townsperson
		table.insert(
			out,
			{ rule = "afk", player = p.id, release = true, to = p.rung, rank = "keep", loseSubrole = p.subrole }
		)
	end
end

handlers["rodent.died"] = function(_event, ctx, out)
	rodentDied(ctx, out)
end

handlers["rodent.killed"] = function(event, ctx, out)
	local by = event.by
	local killer = if event.killer ~= nil then ctx.players[event.killer] else nil
	if by == "squirrel" then
		return -- brief §6: a regular squirrel cannot kill the spicy rodent
	end
	if killer and by == "hospital" and event.inHospital then
		table.insert(out, {
			rule = "rodent.killed.inHospital",
			player = killer.id,
			to = "squirrel",
			rank = "lowestUninfected",
			instant = true,
			extraSlot = true,
		})
	elseif killer and (by == "human" or by == "police" or by == "driver" or by == "hospital") then
		local options: { Rung } = {}
		if (ctx.squirrelBodiesFree or 0) > 0 then
			table.insert(options, "squirrel")
		end
		if (ctx.rodentInfectedShare or 0) > P.killerHospitalIf then
			table.insert(options, "hospital")
		end
		table.insert(options, "police")
		local chosen, extra = nil, false
		for _, r in options do
			if r == killer.rung or Ladder.held(ctx, r) < Ladder.slots(r, ctx) then
				chosen = r
				break
			end
		end
		if not chosen then
			chosen, extra = options[#options], true -- the brief promotes regardless; over cap until a slot frees
		end
		local tr: Transition = {
			rule = "rodent.killed",
			player = killer.id,
			to = chosen,
			rank = if chosen == "squirrel" then "lowestUninfected" else "keep",
		}
		if killer.rung == "human" and chosen == "squirrel" then
			tr.remember = true
		end
		if extra then
			tr.extraSlot = true
		end
		table.insert(out, tr)
	end
	rodentDied(ctx, out)
end

handlers["squirrel.infected"] = function(event, ctx, out)
	local p = ctx.players[event.victim]
	if p and p.rung == "squirrel" then
		table.insert(out, { rule = "squirrel.infected", player = p.id, penalty = table.clone(P.squirrelInfected) })
	end
end

handlers["squirrel.killed"] = function(event, ctx, out)
	local by = event.by
	if not (by == "human" or by == "police" or by == "hospital" or by == "guard") then
		return
	end
	if not event.infected then
		return -- only infected squirrels can be killed (brief v2 §13a)
	end
	local victim = if event.victim ~= nil then ctx.players[event.victim] else nil
	local exclude: { [any]: boolean } = {}
	if victim then
		exclude[victim.id] = true
		table.insert(
			out,
			{ rule = "squirrel.killed", player = victim.id, to = "human", rank = "lowest", release = true }
		)
	end
	table.insert(out, {
		rule = "squirrel.killed.slot",
		bodyRespawn = "healthyFromNest",
		offer = offer("squirrel", SLOT_TAKE.squirrel, ctx.players, exclude),
	})
end

handlers["winter.end.belowThreshold"] = function(event, ctx, out)
	local ids = table.clone(event.players or {})
	table.sort(ids, idLess)
	for _, id in ids do
		local p = ctx.players[id]
		if p and p.rung == "squirrel" then
			table.insert(
				out,
				{ rule = "winter.end", player = id, to = "human", rank = "rememberedHuman", release = true }
			)
		end
	end
end

handlers["slot.open"] = function(event, ctx, out)
	local rung = event.rung
	local take = SLOT_TAKE[rung]
	if not take then
		return
	end
	local exclude: { [any]: boolean } = {}
	for _, id in event.exclude or {} do
		exclude[id] = true
	end
	table.insert(out, { rule = `slot.open.{rung}`, offer = offer(rung, take, ctx.players, exclude) })
end

handlers["police.performance"] = function(event, ctx, out)
	local before = Ladder.policeSlots(event.previous)
	local after = Ladder.policeSlots(event.performance)
	if after > before then
		table.insert(out, { rule = "police.performance", unlock = "policeSlots", value = after })
		table.insert(out, { rule = "police.performance.tier", offer = offer("police", SLOT_TAKE.police, ctx.players) })
	end
end

handlers["upgrade.bought"] = function(event, ctx, out)
	if event.id ~= "drone" then
		return
	end
	if Ladder.policeSlots(ctx.policePerformance) >= Ladder.rungs.police.playerSlots.max then
		table.insert(out, { rule = "upgrade.bought.drone", unlock = "drone" })
	else
		table.insert(out, { rule = "upgrade.bought.drone", refused = "requires policeSlots=8" })
	end
end

handlers["offer.sideExit"] = function(event, ctx, out)
	local p = ctx.players[event.player]
	local to = event.to
	if not p or not SIDE[to] then
		return
	end
	if Ladder.held(ctx, to) >= Ladder.slots(to, ctx) then
		table.insert(out, { rule = "offer.sideExit", player = p.id, refused = "full" })
		return
	end
	table.insert(out, { rule = "offer.sideExit", player = p.id, to = to, rank = "keep", remember = true })
end

handlers["sideExit.leave"] = function(event, ctx, out)
	local p = ctx.players[event.player]
	if p and SIDE[p.rung] then
		table.insert(out, { rule = "sideExit.leave", player = p.id, to = "human", rank = "remembered", release = true })
	end
end

handlers["kick.landed"] = function(event, _ctx, out)
	if event.target == "rodent" or event.target == "infectedSquirrel" then
		table.insert(
			out,
			{ rule = "kick.landed", player = event.player, rankDelta = P.kickEvent, reputation = "kick_landed" }
		)
	end
end

handlers["work.completed"] = function(event, _ctx, out)
	local delta = P.rankClass[event.class or "standard"] or 0
	if event.fetchSecs then
		for _, row in P.rankBySpeed do
			if event.fetchSecs <= row[1] then
				delta += row[2]
				break
			end
		end
	end
	table.insert(out, { rule = "work.completed", player = event.player, pay = event.pay or 0, rankDelta = delta })
end

handlers["gig.completed"] = function(event, _ctx, out)
	local payout = GigRules.payout(event.gig, event.quality)
	table.insert(out, {
		rule = "gig.completed",
		player = event.player,
		pay = payout.cents,
		tip = payout.tip,
		reputation = payout.reputationEvent,
	})
end

handlers["traffic.hitPedestrian"] = function(event, ctx, out)
	local p = ctx.players[event.player]
	if p and p.rung == "police" then
		table.insert(out, {
			rule = "traffic.hitPedestrian",
			player = p.id,
			keys = "revoke",
			jail = P.jail.hitPedestrianSecs,
			to = "human",
			rank = "lowest",
			loseSubrole = p.subrole,
		})
	end
end

handlers["traffic.repeatOffence"] = function(event, ctx, out)
	if ctx.offroad then
		return -- no jurisdiction off-road (brief v2 §15)
	end
	table.insert(out, { rule = "traffic.repeatOffence", player = event.player, jail = P.jail.repeatOffenceSecs })
end

handlers["infection.criticalMass"] = function(_event, ctx, out)
	local rodent = findRung(ctx, "rodent")
	table.insert(out, {
		rule = "infection.criticalMass",
		player = if rodent then rodent.id else nil,
		winner = true,
		cinematic = true,
	})
end

local function sessionReset(event: { [string]: any }, ctx: Ctx, out: { Transition })
	for _, p in sortedPlayers(ctx) do
		local keep = (p.rung == "rodent" and event.winner == p.id) or (p.rung == "squirrel" and p.infected)
		if keep then
			table.insert(out, { rule = "session.reset", player = p.id, to = p.rung, rank = "keep", reset = true })
		else
			local tr: Transition =
				{ rule = "session.reset", player = p.id, to = "human", rank = "lowest", reset = true }
			if p.rung ~= "human" then
				tr.release = true
			end
			table.insert(out, tr)
		end
	end
end
handlers["cinematic.finished"] = sessionReset
handlers["everyoneInfected"] = sessionReset

-- Pure: the transitions an event causes, in a deterministic order.
function Ladder.resolve(event: { [string]: any }, ctx: Ctx): { Transition }
	local out: { Transition } = {}
	local h = handlers[event.kind]
	if not h then
		error(`Ladder.resolve: unknown event {tostring(event.kind)}`)
	end
	h(event, ctx, out)
	return out
end

-- Scarce rungs a set of transitions leaves without its player and which no transition already
-- offers (RoleService resolves slot.open for each at once; the rodent's offer is immediate).
function Ladder.vacated(transitions: { Transition }, ctx: Ctx): { Rung }
	local offered: { [string]: boolean } = {}
	for _, t in transitions do
		if t.offer then
			offered[t.offer.rung] = true
		end
	end
	local out: { Rung } = {}
	for _, t in transitions do
		local p = if t.player ~= nil then ctx.players[t.player] else nil
		if p and t.to and t.to ~= p.rung and SLOT_TAKE[p.rung] and not offered[p.rung] then
			table.insert(out, p.rung)
		end
	end
	return out
end

Ladder.EVENTS = {} :: { string }
for k in handlers do
	table.insert(Ladder.EVENTS, k)
end
table.sort(Ladder.EVENTS)

return Ladder
