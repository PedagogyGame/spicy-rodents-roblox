--!strict
-- ReplicatedStorage.Shared.Reputation.Conduct
-- When an act is bad enough to cost a player reputation (owner D30, 2026-11-22: "make reputation metrics occur in the
-- background ... if a person kicks it at another player or winds up and throws it at another player, their reputation
-- score goes down, or practically runs over people, same thing, but do not mark this or score this often, only in
-- extreme situations, or only for extreme violations, and it should just show you that, then go away, not be a
-- constant meter, but be checkable with money"). ONE place for every rule of what counts; pure, so the specs drive it.
-- A single accident never counts. What does:
--   ball      the kick ball (Items/ItemWorld) hitting a person HARD (C.ball.hardSpeed at the hit: a gentle toss or a
--             roll is nothing): C.ball.hits hard hits within C.ball.window seconds ("you kept hitting people with
--             the ball"), or one hard hit from a wind-up of C.ball.windupSecs at C.ball.closeRange or nearer ("you threw
--             the ball hard at someone up close": a deliberate throw in someone's face).
--   run over  a shared vehicle (Vehicles/RideBumps) knocking people at C.run.minSpeed or faster (a crawl into
--             someone is nothing): C.run.people different people within C.run.window ("you kept running people
--             over"), or the same person C.run.same times within C.run.sameWindow ("you went back and ran the same
--             person over": nobody does that by accident).
--   reported  another service decides its own act was extreme and says so (Reputation.report(player, kind,
--             severity): H3's errand thief, H1's doctor who ignores a victim): it counts at once, C.reported.points by
--             severity 1..3.
-- After an act has counted, the same kind does not count again for C.<kind>.rest seconds (rest): an outburst costs
-- once, so the notice is rare and never a stream. Hits and knocks during the rest are not even remembered.
-- Reputation itself (Reputation/ReputationRules): [-100, 100], everybody starts at 0. Below 0 it creeps back toward 0
-- by one point every C.recoverSecs while nothing new counts (recover): an outburst is forgiven in time, not at once.
-- The word a player reads (band): Trusted (C.bands.trusted and up), Good (from C.bands.good), Fair (from C.bands.fair),
-- Poor (below); shown with the number: "Good (0)".
-- Interface: C; KINDS; newBook() -> Book; ball(book, now, hit) -> Drop?; runOver(book, now, hit) -> Drop?;
--   reported(book, now, kind, severity?) -> Drop?; recover(rep, quietSecs) -> rep (the steps due after quietSecs);
--   band(rep) -> word; standing(rep) -> "Good (0)"; notice(drop, repAfter) -> words; menuLine(cents, rep) -> words
-- Pure. No side effects on require.

local ReputationRules = require("./ReputationRules")
local Wallet = require("../Economy/Wallet")

local Conduct = {}

-- stylua: ignore
Conduct.C = table.freeze({
	ball = table.freeze({
		hardSpeed = 34, -- studs/s at the hit: a throw or a kick meant to hurt (a toss is ~20, a roll less)
		hits = 3, window = 30, -- three hard hits on people within 30 s
		windupSecs = 0.6, closeRange = 14, -- or one hard hit from a long wind-up at this range or nearer
		points = 10, rest = 120,
	}),
	run = table.freeze({
		minSpeed = 9, -- studs/s: a bump slower than this never counts
		people = 3, window = 60, -- three different people within a minute
		same = 2, sameWindow = 30, -- or the same person twice within 30 s
		points = 10, rest = 120,
	}),
	reported = table.freeze({ points = table.freeze({ 5, 10, 15 }), rest = 60 }),
	recoverSecs = 180, -- below 0, one point back every 3 minutes with nothing new
	bands = table.freeze({ trusted = 30, good = -4, fair = -24 }),
})

-- The words for each kind (what the notice says after "Reputation down: "). A reported kind not listed reads `other`.
-- stylua: ignore
Conduct.KINDS = table.freeze({
	ball = "you kept hitting people with the ball",
	ball_close = "you threw the ball hard at someone up close",
	run_over = "you kept running people over",
	run_same = "you went back and ran the same person over",
	errand_theft = "you kept an errand's delivery for yourself",
	ignored_victim = "you drove past a bite victim who needed you",
	other = "something you did upset the town",
})

-- A reported kind's other spellings (the reporting services may name it either way).
local ALIASES: { [string]: string } = {
	stolen_item = "errand_theft",
	errand_stolen = "errand_theft",
	theft = "errand_theft",
	ignored = "ignored_victim",
	victim_ignored = "ignored_victim",
	ambulance_ignored = "ignored_victim",
}

export type Drop = { kind: string, points: number, words: string }
-- a ball's hit on a person: who, how fast the ball was going, the thrower's wind-up and how far they stood at the throw
export type BallHit = { victim: any, speed: number, windup: number?, dist: number? }
-- a vehicle's knock on a person: who, and the vehicle's speed
export type RunHit = { victim: any, speed: number }

export type Book = {
	balls: { number }, -- times of hard hits still in the window
	runs: { { t: number, victim: any } },
	restUntil: { [string]: number }, -- kind -> the end of its rest
}

function Conduct.newBook(): Book
	return { balls = {}, runs = {}, restUntil = {} }
end

local function resting(book: Book, kind: string, now: number): boolean
	local r = book.restUntil[kind]
	return r ~= nil and now < r
end

local function drop(book: Book, family: string, kind: string, points: number, rest: number, now: number): Drop
	book.restUntil[family] = now + rest
	return { kind = kind, points = points, words = Conduct.KINDS[kind] or Conduct.KINDS.other }
end

-- A hard hit with the kick ball. nil: it does not count (soft, a first accident, or the rest after an outburst).
function Conduct.ball(book: Book, now: number, hit: BallHit): Drop?
	local B = Conduct.C.ball
	if type(hit.speed) ~= "number" or hit.speed < B.hardSpeed or resting(book, "ball", now) then
		return nil
	end
	if (hit.windup or 0) >= B.windupSecs and hit.dist ~= nil and hit.dist <= B.closeRange then
		table.clear(book.balls)
		return drop(book, "ball", "ball_close", B.points, B.rest, now)
	end
	local kept = {}
	for _, t in book.balls do
		if now - t <= B.window then
			table.insert(kept, t)
		end
	end
	table.insert(kept, now)
	book.balls = kept
	if #kept >= B.hits then
		table.clear(book.balls)
		return drop(book, "ball", "ball", B.points, B.rest, now)
	end
	return nil
end

-- A shared vehicle knocking a person. nil: it does not count.
function Conduct.runOver(book: Book, now: number, hit: RunHit): Drop?
	local R = Conduct.C.run
	if type(hit.speed) ~= "number" or hit.speed < R.minSpeed or resting(book, "run", now) then
		return nil
	end
	local kept = {}
	for _, r in book.runs do
		if now - r.t <= R.window then
			table.insert(kept, r)
		end
	end
	table.insert(kept, { t = now, victim = hit.victim })
	book.runs = kept
	local same, people = 0, {}
	local n = 0
	for _, r in kept do
		if r.victim == hit.victim and now - r.t <= R.sameWindow then
			same += 1
		end
		if not people[r.victim] then
			people[r.victim] = true
			n += 1
		end
	end
	if same >= R.same then
		table.clear(book.runs)
		return drop(book, "run", "run_same", R.points, R.rest, now)
	end
	if n >= R.people then
		table.clear(book.runs)
		return drop(book, "run", "run_over", R.points, R.rest, now)
	end
	return nil
end

-- An act another service judged extreme (Reputation.report). severity 1..3 (default 1; clamped, whole).
function Conduct.reported(book: Book, now: number, kind: string, severity: number?): Drop?
	local P = Conduct.C.reported
	local k = ALIASES[kind] or kind
	if resting(book, "reported:" .. k, now) then
		return nil
	end
	local s = math.clamp(math.floor(tonumber(severity) or 1), 1, #P.points)
	local words = if Conduct.KINDS[k]
			and k ~= "ball"
			and k ~= "ball_close"
			and k ~= "run_over"
			and k ~= "run_same"
		then k
		else "other"
	return drop(book, "reported:" .. k, words, P.points[s], P.rest, now)
end

-- Below 0, the points back after `quietSecs` with nothing new counting (never past 0, never above it).
function Conduct.recover(rep: number, quietSecs: number): number
	if rep >= 0 or quietSecs <= 0 then
		return rep
	end
	return math.min(0, rep + math.floor(quietSecs / Conduct.C.recoverSecs))
end

function Conduct.band(rep: number): string
	local b = Conduct.C.bands
	if rep >= b.trusted then
		return "Trusted"
	elseif rep >= b.good then
		return "Good"
	elseif rep >= b.fair then
		return "Fair"
	end
	return "Poor"
end

-- "Good (0)", "Fair (-10)", "Trusted (+34)"
function Conduct.standing(rep: number): string
	local n = math.floor(ReputationRules.clamp(rep) + 0.5)
	local num = if n > 0 then `+{n}` else tostring(n)
	return `{Conduct.band(n)} ({num})`
end

-- The brief notice on the player's own screen: "Reputation down: you kept hitting people with the ball (now Fair)".
function Conduct.notice(d: Drop, repAfter: number): string
	return `Reputation down: {d.words} (now {Conduct.band(repAfter)})`
end

-- The menu's line: money and reputation together. cents nil: the wallet is not open yet.
function Conduct.menuLine(cents: number?, rep: number?): string
	local money = if type(cents) == "number" then Wallet.format(cents) else "--"
	return `Money  {money}   ·   Reputation  {Conduct.standing(rep or 0)}`
end

return Conduct
