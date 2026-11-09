--!strict
-- ReplicatedStorage.Shared.Config.Tunables
-- Every gameplay number with unit, range and source; stud conversion on read; live overrides
-- (BUILD_PLAN §3.8, transcribed). Ladder numbers (score weights, kick reward, offer timeout, the 30 %
-- rule, re-entry delay, police slots, rank gate, jail) live in Roles/Ladder.params, not here.
-- Pure: the engine binder that mirrors leaves onto ReplicatedStorage.TunablesLive attributes (dev
-- only) calls applyOverrides; nothing here touches the engine. No side effects on require.
-- Interface: get(path) (studs for length units), raw(path) (authored units), meta(path) -> {unit, src, default},
--            onChanged(path, fn) -> Connection, applyOverrides(map) -> (applied, errors), diff() -> {Change},
--            reset(), paths()

local Signal = require("../Util/Signal")
local TunableMeta = require("./TunableMeta")

export type Leaf = { v: any, unit: string?, src: string? }
export type Change = { path: string, from: any, to: any }

local Tunables = {}

-- stylua: ignore start
Tunables.tree = {
	clock = { realSecondsPerDay = { v = 72, unit = "s", src = "brief v2 §15 dec 10 (decided)" },
	          weeksPerCycle = { v = 6 }, winterWeek = { v = 6 }, lunarMonthDays = { v = 29.53 },
	          dayCurve = { v = { night = 0.20, sunrise = 0.10, goldenAm = 0.12, day = 0.30, goldenPm = 0.12, sunset = 0.10, blue = 0.06 } } },
	squirrel = { walk = { v = 8.0, unit = "u/s", src = "routes §8.1" }, sprint = { v = 16.8, unit = "u/s" },
	             stalk = { v = 1.65, unit = "u/s" }, gravity = { v = 30, unit = "u/s2" },
	             leapFwd = { v = 16.5, unit = "u/s" }, leapUp = { v = 12.8, unit = "u/s" },
	             grabRadius = { v = 3.4, unit = "u" }, maxTransferGap = { v = 3.15, unit = "u" },
	             autoSwitch = { v = 0.48, unit = "u" }, explicitTransfer = { v = 1.7, unit = "u" },
	             shoulderHeight = { v = 1.2, unit = "st", src = "brief §2; decision 8" },
	             chaseLockRange = { v = 30, unit = "u", src = "brief v2 §8: forward-locked camera while chasing a squirrel" },
	             stalkOnTrunk = { v = false, src = "squirrel_abilities §5.1: stalk never engages on a trunk (rev 4)" } },
	pounce = { cooldown = { v = 0.7, unit = "s" }, window = { v = 0.78, unit = "s" },
	           windup = { v = 0.12, unit = "s", src = "brief §8 (new)" }, recovery = { v = 0.35, unit = "s" },
	           contactHuman = { v = 1.38, unit = "u" }, chanceUnaware = { v = 0.955 }, chanceAware = { v = 0.035 } },
	rodent = { maxHealth = { v = 100 }, kick = { v = 55 }, baton = { v = 50 }, shove = { v = 40 }, defenderMult = { v = 1.5 },
	           drainPerDay = { v = 1, unit = "hp/game day", src = "brief v2 §8" },
	           healOnBite = { v = { human = 10, squirrel = 20 }, unit = "hp", src = "brief v2 §8" },
	           regenStalk = { v = 0.02, unit = "hp/s", src = "D33 rev 4" }, regenHollow = { v = 0.08, unit = "hp/s", src = "D33 rev 4" },
	           fedWindowDays = { v = 1, unit = "game days", src = "D33 rev 4: regen only while fed; the drain only while unfed" },
	           iFrames = { v = 0.6, unit = "s" },
	           fallDamage = { v = 0, src = "routes Q7; v5.4 has none" }, biteDanceEvery = { v = 10, src = "squirrel_abilities §10" },
	           chiliRushPerPepper = { v = 30, unit = "s" }, chiliRushCap = { v = 90, unit = "s" },
	           chiliRushSpeed = { v = 1.6, src = "ground, rail and duct; not while stalking" }, chiliPounceMult = { v = 1.12 },
	           chiliLeapFwd = { v = 18.5, unit = "u/s" }, chiliGaitMult = { v = 1.14 }, chiliEyeEmissive = { v = 1.65 },
	           biteCents = { v = 10, unit = "Spicy cents", src = "v5.4 +10 coins per successful bite (dec 20; rev 4, CR3 VD-3)" },
	           waterGunStunSecs = { v = 1.3, unit = "s", src = "brief v2 §13a; once per player (Q11)" } },
	alert = { radiusU = { v = 40, unit = "u" }, ttl = { v = 90, unit = "s" },
	          kickMult = { v = 1.25, src = "hidden strength boost; must stay below 1.82 (D33)" },
	          swingBias = { v = 2.0, src = "response weights toward swing/kick" },
	          bitePenalty = { v = 0.05, src = "second bite near a fresh one is close to impossible" },
	          policeChaseBlocks = { v = 2 }, policeLeashBlocks = { v = 5 }, blockLenU = { v = "measured from roads.json", src = "Q16" } },
	-- Power numbers live in Rodent/PowerRules.TABLE (brief v2 §15, verbatim v5.4; golden-tested). These
	-- leaves are read-only mirrors for the tuning panel; PowerRules is the authority.
	power = { bitePerson = { v = 100 }, bitePersonHigh = { v = 150 }, highAboveGroundU = { v = 1.6, src = "v5.4 uses absolute Y > 4; Q23" },
	          biteOfficer = { v = 130 }, convertSquirrel = { v = 90 }, batonHit = { v = -19 }, pedestrianKick = { v = -19, src = "v5.4 same function; Q23" },
	          catHit = { v = -12 }, fadeAfterActiveMin = { v = 10 }, fadePct = { v = 0.15, src = "rounded up; repeats" },
	          stages = { v = { feral = 0, rabid = 600, super = 1500 } }, hudMax = { v = 1500 } },
	human = { spotRange = { v = 14.5, unit = "u" }, kickReach = { v = 2.65, unit = "u" }, kickWindup = { v = 0.58, unit = "s" },
	          vigilanteShare = { v = 0.08, src = "brief §8" }, crouchHeightMult = { v = 0.6, src = "paintball crouch" },
	          reportRange = { v = 25, unit = "u", src = "true sighting report (v2 §13a)" },
	          noiseSpeedStalk = { v = 2.5, unit = "u/s", src = "squirrel_abilities §5.2 (rev 4)" },
	          noiseSpeed = { v = 4.7, unit = "u/s", src = "squirrel_abilities §5.2" },
	          sprintStaminaS = { v = 10, unit = "s", src = "D35 (rev 4)" }, staminaRefillS = { v = 15, unit = "s", src = "D35" },
	          sodaSecs = { v = 45, unit = "s", src = "D35: unlimited sprint" }, iceCreamSecs = { v = 30, unit = "s", src = "D35" } },
	infection = { squirrelSharePer = { v = 25 / 7 }, squirrelShareCap = { v = 25 }, matureSecs = { v = 1500 },
	              criticalTown = { v = 50 }, criticalStaffFrac = { v = 0.5 }, criticalPatientFrac = { v = 0.5 },
	              infectedStaffCureMult = { v = 1.5 }, recentBiteSecs = { v = 60, src = "cured instantly on rodent death if bitten within (v2 §8)" },
	              newRodentPct = { v = 0.5, unit = "%", src = "v2 §8: infection resets to the new rodent alone" } },
	outbreak = { cinematicSecs = { v = 25, unit = "s", src = "D31" }, clockRateMult = { v = 40 }, sweepSpeedRamp = { v = { 1.0, 3.0 } },
	             overcastRampS = { v = 8 }, nightFadeS = { v = 6 } },
	hospital = { disinfectSteps = { v = { 1.2, 0.8, 1.2 }, unit = "s" }, fetchTimeout = { v = 45, unit = "s" }, wrongItemPenalty = { v = 10, unit = "s" },
	             aiStaffSpeedMult = { v = 0.7, src = "v2 §5: player staff are faster" } },
	police = { batonWindup = { v = 0.5, unit = "s" }, carMaxSpeed = { v = 16, unit = "u/s" }, radarRange = { v = 48, unit = "u" } },
	drone = { maxAlt = { v = 160, unit = "u" }, speed = { v = 24, unit = "u/s" }, markHold = { v = 0.6, unit = "s" },
	          markRange = { v = 100, unit = "u" }, markSecs = { v = 12, unit = "s" }, markCooldown = { v = 20, unit = "s" },
	          vigilanteRadius = { v = 60, unit = "u" }, deerStartleAlt = { v = 24, unit = "u" } },
	traffic = { tickHz = { v = 30 }, posesHz = { v = 15 }, sweptPad = { v = 0.18, unit = "u" }, yawStep = { v = 0.05, unit = "rad" },
	            teleportSkip = { v = 12, unit = "u" }, sedanBox = { v = { 2.35, 4.45, 2.04 }, unit = "u" },
	            cartMaxSpeed = { v = 7, unit = "u/s" }, bikeMaxSpeed = { v = 9, unit = "u/s" }, jetSkiMaxSpeed = { v = 20, unit = "u/s" },
	            speedingTolerance = { v = 1.15, src = "player law (v2 §15)" },
	            motorcycleBiteContact = { v = 2.0, unit = "u", src = "traffic §5.12 (rev 4)" }, motorcycleBiteDy = { v = 3.2, unit = "u" } },
	forage = { carryMax = { v = 9, src = "brief v2 §3" }, hollowCapacity = { v = 120 }, premiumMult = { v = 2 }, ownThreshold = { v = 0.70 },
	           ownVisitDays = { v = 3, unit = "game days", src = "brief v2 §3 (Q2)" },
	           seasonStockMargin = { v = 1.5, src = "invariant 15" },
	           stinkFillPerMin = { v = 1.2 }, stinkFireMin = { v = 95 }, stinkCost = { v = 30 },
	           stinkRepelRadius = { v = 8, unit = "u" }, stinkRepelSecs = { v = 4, unit = "s" } },
	economy = { minWageCentsPerHour = { v = 2, src = "brief v2 §13a" }, robuxToCents = { v = 400, src = "about 1 R$ = 4 S$" },
	            paintballPassCents = { v = 20 }, paintballPassDays = { v = 5, unit = "game days", src = "Q2" }, garbSetCents = { v = 100 },
	            fashionUnlockLifetimeCents = { v = 150, src = "v5.4's 150 lifetime coins gate the fashion stand (rev 4, CR3 VD-3)" } },
	reputation = { votesPerDay = { v = { up = 5, down = 5 }, unit = "per game day", src = "v2 §13a (Q2)" }, voteWeightClamp = { v = { 0.25, 1.5 } },
	               cafeTickPerHour = { v = 1 }, rankGateDays = { v = "Ladder.params", src = "ladder number; not here" } },
	paintball = { projectileSpeed = { v = 90, unit = "st/s" }, drop = { v = 9.8 }, magazine = { v = 5 }, lagHistorySecs = { v = 1.0 },
	              matchSecs = { v = 480 }, teamSize = { v = { 4, 8 } }, sprintMult = { v = 1.4 } },
	minigames = { inputDelayBudgetMs = { v = 120, src = "S13 pass bar (shooter's local feel)" }, jengaBlocks = { v = 54 }, dartsWobble = { v = 0.04 },
	              labyrinthTiltDegPerS = { v = 25 } },
	lighting = { enableRadius = { v = 180, unit = "st" }, flickerFraction = { v = 0.07 }, maxRealLights = { v = 300, src = "S17" } },
	interior = { doorHold = { v = 3, unit = "s" }, hideNoSight = { v = 2, unit = "s" }, searchPerSpot = { v = 1.5, unit = "s" } },
	recovery = { safeHistory = { v = 3, unit = "s" }, riverToQuay = { v = true, src = "worldgen_districts_art §16" } },
	policeCoord = { tier2Pair = { v = true }, cutoffLookahead = { v = 30, unit = "u" }, perimeterPoints = { v = 3 } },
	ai = { thinkHz = { v = { near = 10, mid = 4, far = 1 } }, lodNear = { v = 150, unit = "st" }, lodMid = { v = 500, unit = "st" }, budgetMs = { v = 4 },
	       arenaBudgetMs = { v = 1.5, src = "S18" } },
	avatar = { maxSat = { v = 0.55 }, valRange = { v = { 0.39, 0.91 } }, furTintCap = { v = 0.30, src = "animals only (Addendum B1)" }, skinTones = { v = 8, src = "fallback only (D22 rev 4)" } },
	-- W1 additions (not in §3.8's listing): the log-only movement layer and the Net token buckets.
	movement = { poseHistorySecs = { v = 1.0, unit = "s", src = "BUILD_PLAN §4.4 #6: the 1 s history the arena rewinds" },
	             humanMaxSpeed = { v = 12, unit = "u/s", src = "W1 log-only cap for non-rail kinds (sprint 16 st/s x tolerance)" } },
}
-- stylua: ignore end

-- Leaves are tables with a `v` field; anything else is a branch.
local function isLeaf(node: any): boolean
	return type(node) == "table" and node.v ~= nil
end

local defaults: { [string]: any } = {}
local leaves: { [string]: Leaf } = {}
local order: { string } = {}

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

local function index(node: { [string]: any }, prefix: string)
	local keys: { string } = {}
	for k in node do
		table.insert(keys, k)
	end
	table.sort(keys)
	for _, k in keys do
		local child = node[k]
		local path = if prefix == "" then k else `{prefix}.{k}`
		if isLeaf(child) then
			leaves[path] = child
			defaults[path] = deepCopy(child.v)
			table.insert(order, path)
		elseif type(child) == "table" then
			index(child, path)
		end
	end
end
index(Tunables.tree, "")

local signals: { [string]: Signal.Signal } = {}

local function leafOf(path: string): Leaf
	local leaf = leaves[path]
	if not leaf then
		error(`Tunables: unknown path '{path}'`, 3)
	end
	return leaf
end

-- Value in engine units (studs for length units). Tables are copies.
function Tunables.get(path: string): any
	local leaf = leafOf(path)
	local v = TunableMeta.toStuds(leaf.v, leaf.unit)
	if type(v) == "table" and v == leaf.v then
		return deepCopy(v)
	end
	return v
end

-- Value as authored (HTML units for "u").
function Tunables.raw(path: string): any
	return deepCopy(leafOf(path).v)
end

function Tunables.meta(path: string): { unit: string?, src: string?, default: any, studs: boolean }
	local leaf = leafOf(path)
	return { unit = leaf.unit, src = leaf.src, default = deepCopy(defaults[path]), studs = TunableMeta.isLength(leaf.unit) }
end

function Tunables.paths(): { string }
	return table.clone(order)
end

function Tunables.onChanged(path: string, fn: (value: any) -> ()): Signal.Connection
	leafOf(path)
	local sig = signals[path]
	if not sig then
		sig = Signal.new()
		signals[path] = sig
	end
	return sig:connect(fn)
end

-- map: { [path] = authored value }. Invalid entries are skipped and reported; valid ones apply.
function Tunables.applyOverrides(map: { [string]: any }): (number, { string })
	local applied, errors = 0, {}
	local keys: { string } = {}
	for k in map do
		table.insert(keys, k)
	end
	table.sort(keys)
	for _, path in keys do
		local leaf = leaves[path]
		if not leaf then
			table.insert(errors, `{path}: unknown path`)
			continue
		end
		local ok, err = TunableMeta.validate(path, leaf, map[path])
		if not ok then
			table.insert(errors, err :: string)
			continue
		end
		leaf.v = deepCopy(map[path])
		applied += 1
		local sig = signals[path]
		if sig then
			sig:fire(Tunables.get(path))
		end
	end
	return applied, errors
end

local function same(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not same(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

-- Every leaf that differs from its default, in path order (the Lab's "Export tuning").
function Tunables.diff(): { Change }
	local out: { Change } = {}
	for _, path in order do
		if not same(leaves[path].v, defaults[path]) then
			table.insert(out, { path = path, from = deepCopy(defaults[path]), to = deepCopy(leaves[path].v) })
		end
	end
	return out
end

-- Back to the authored defaults (tests, Lab "reset tuning"); fires onChanged for changed leaves.
function Tunables.reset()
	local changed = Tunables.diff()
	for _, c in changed do
		leaves[c.path].v = deepCopy(defaults[c.path])
		local sig = signals[c.path]
		if sig then
			sig:fire(Tunables.get(c.path))
		end
	end
end

return Tunables
