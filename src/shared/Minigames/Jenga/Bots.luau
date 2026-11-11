--!strict
-- ReplicatedStorage.Shared.Minigames.Jenga.Bots
-- The computer players (checklist "SOLO / COMPUTER / PLAYERS"; C3): three named players of different nerve, and
-- the careful hand that plays an idle person's turn for them (JEN-R5). They play through the SAME inputs a
-- person has, one decision every twentieth of a second: they knock on blocks to feel them (tap), draw one
-- (pull, sample by sample, with their own speed and wander), give up on it if the tower starts to go and they
-- still can (release), and set it down (place). They never touch the tower's state.
-- What skill changes:
--   * how many blocks they knock on before choosing, and how often they misread a knock,
--   * whether they LOOK at what taking the block would leave standing (the stability judgement on a copy of
--     the tower): the weakest often does not, and takes the second block from a level,
--   * how fast and how straight they draw, and how soon their nerve makes them let go,
--   * how squarely and gently they set the block down, and whether they choose the place that keeps the top
--     balanced.
-- A bot always finds a move: if every block it knocked on looks bad it takes the least bad, so a game with
-- computer players always reaches its end (the tower falls).
-- A brain is plain data (a counter and a seed give its random stream), so a game with bots replays exactly.
-- Pure; Lune-tested (tests/unit/jenga_bots.spec.luau).
-- Interface: AI = { { name, skill } }; SKILLS; skillOf(name) -> skill; new(skill, seed) -> Brain;
--   act(brain, tower, phase, dt) -> (verb?, args?); judge(tower, level, slot) -> margin after taking it (or -1)

local Rng = require("../../Util/Rng")
local Layout = require("./Layout")
local Physics = require("./Physics")
local Stability = require("./Stability")
local Tower = require("./Tower")

local Bots = {}

export type Skill = {
	taps: number, -- blocks knocked on before choosing
	misjudge: number, -- chance a knock is misread
	look: number, -- chance it checks what taking the block would leave
	slow: number, -- studs/s on a block that carries weight
	fast: number, -- studs/s on a loose one
	wobble: number, -- studs the hand wanders off the line
	placeErr: number, -- studs off square when setting down
	dropLo: number, -- studs/s it comes down at, least and most
	dropHi: number,
	nerve: number, -- lets go when the tower is this near to going (0..1), if it still may
	calm: number, -- waits until the tower rocks less than this (0..1) before choosing a block
	think: number, -- seconds before the first knock
	pushMiddle: boolean, -- pushes a middle block through instead of dragging it
	bestSlot: boolean, -- chooses the place on top that keeps the tower best balanced
}

Bots.SKILLS = {
	easy = {
		taps = 5,
		misjudge = 0.25,
		look = 0.6,
		slow = 1.8,
		fast = 3.5,
		wobble = 0.12,
		placeErr = 0.14,
		dropLo = 1.5,
		dropHi = 4.5,
		nerve = 0.5,
		calm = 0.12,
		think = 0.5,
		pushMiddle = false,
		bestSlot = false,
	},
	normal = {
		taps = 8,
		misjudge = 0.08,
		look = 0.95,
		slow = 0.9,
		fast = 2.0,
		wobble = 0.05,
		placeErr = 0.05,
		dropLo = 0.4,
		dropHi = 1.6,
		nerve = 0.35,
		calm = 0.03,
		think = 0.8,
		pushMiddle = true,
		bestSlot = false,
	},
	sharp = {
		taps = 14,
		misjudge = 0.02,
		look = 1,
		slow = 0.45,
		fast = 1.4,
		wobble = 0.012,
		placeErr = 0.012,
		dropLo = 0,
		dropHi = 0.3,
		nerve = 0.2,
		calm = 0.005,
		think = 1.0,
		pushMiddle = true,
		bestSlot = true,
	},
	-- an idle person's turn (JEN-R5): a loose block, drawn with ordinary care
	idle = {
		taps = 6,
		misjudge = 0,
		look = 1,
		slow = 0.9,
		fast = 1.2,
		wobble = 0.03,
		placeErr = 0.02,
		dropLo = 0.4,
		dropHi = 0.6,
		nerve = 2,
		calm = 0.03,
		think = 0.3,
		pushMiddle = true,
		bestSlot = false,
	},
} :: { [string]: Skill }

Bots.AI = {
	{ name = "Steady Freddie", skill = "normal" },
	{ name = "Timber Tess", skill = "easy" },
	{ name = "Old Splinter", skill = "sharp" },
}

Bots.TAP_GAP = 0.3 -- seconds between knocks
Bots.PLACE_WAIT = 0.7 -- seconds with the block in hand before setting it down
Bots.LEAD = 0.4 -- studs the hand runs ahead of a block that resists, at most
Bots.STUCK = 2.5 -- seconds without progress before it gives a block up (if it still may)
Bots.TIGHT = 6 -- block-weights a dull knock counts for, on top of the load it tells of
Bots.STRAIN = 4 -- and how much a pull that strains the tower counts
Bots.SAFE = 0.6 -- how much a thin margin counts against a block, against a block-weight of load

function Bots.skillOf(name: string): string
	for _, a in Bots.AI do
		if string.find(name, a.name, 1, true) then
			return a.skill
		end
	end
	return "normal"
end

export type Brain = {
	skill: string,
	seed: number,
	n: number, -- random draws taken
	stage: string, -- "start" | "think" | "tap" | "pull" | "place" | "placed"
	t: number,
	queue: { number }, -- blocks still to knock on (level * 4 + slot)
	tapped: number,
	est: { [number]: number }, -- what each knock seemed to say: block-weights of load
	bad: { [number]: boolean }, -- given up on
	target: number,
	sign: number,
	push: boolean,
	speed: number,
	goal: number,
	phase: number,
	lastAlong: number,
	stuckFor: number,
	giveUps: number,
	margin: number, -- the tower's margin when it took hold
	slot: number,
}

function Bots.new(skill: string, seed: number): Brain
	return {
		skill = if Bots.SKILLS[skill] then skill else "normal",
		seed = seed,
		n = 0,
		stage = "start",
		t = 0,
		queue = {},
		tapped = 0,
		est = {},
		bad = {},
		target = 0,
		sign = 1,
		push = false,
		speed = 1,
		goal = 0,
		phase = 0,
		lastAlong = 0,
		stuckFor = 0,
		giveUps = 0,
		margin = 0,
		slot = 0,
	}
end

local function draw(brain: Brain): number
	brain.n += 1
	return Rng.new(brain.seed * 31 + brain.n * 7919).next()
end

-- judge(tower, level, slot): the smallest margin anywhere in the tower once that block is gone, or -1 if it
-- would not stand. What a careful player sees by looking.
function Bots.judge(tw: Tower.Tower, level: number, slot: number): number
	local b = Tower.blockAt(tw, level, slot)
	if not b then
		return -1
	end
	local c = Tower.clone(tw)
	c.levels[level][slot] = 0
	c.blocks[b.id].level = 0
	local an = Stability.analyse(c)
	return if an.ok then an.margin else -1
end

local function legalKeys(tw: Tower.Tower): { number }
	local keys = {}
	local top = Tower.highestComplete(tw)
	for level = 1, top - 1 do
		for slot = 1, Layout.PER_LEVEL do
			if tw.levels[level][slot] ~= 0 then
				table.insert(keys, level * 4 + slot)
			end
		end
	end
	return keys
end

-- Choose among the blocks it has knocked on: least load, and (if it looks) the most left standing.
local function choose(brain: Brain, tw: Tower.Tower)
	local S = Bots.SKILLS[brain.skill]
	local best, bestScore = 0, math.huge
	for key, est in brain.est do
		local level, slot = key // 4, key % 4
		if not brain.bad[key] and Tower.legal(tw, level, slot) then
			local score = est + draw(brain) * 0.01
			if draw(brain) < S.look then
				local margin = Bots.judge(tw, level, slot)
				score += if margin <= 0 then 1000 else Bots.SAFE / (margin + 0.03)
				-- and whether the pull it takes would rock the tower
				local strain = Physics.strain(tw, level, slot, S.pushMiddle and slot == 2)
				score += if strain >= 1 then 40 + strain else Bots.STRAIN * strain
			end
			if score < bestScore then
				best, bestScore = key, score
			end
		end
	end
	if best == 0 or (bestScore >= 1000 and #brain.queue > 0) then
		-- nothing it knocked on will do
		if #brain.queue > 0 then
			brain.tapped = math.max(0, brain.tapped - 3) -- knock on a few more
			brain.stage = "tap"
			return
		end
		if best == 0 then
			local keys = legalKeys(tw)
			best = keys[1] or 0
			for _, key in keys do
				if not brain.bad[key] then
					best = key
					break
				end
			end
		end
	end
	local level, slot = best // 4, best % 4
	local b = Tower.blockAt(tw, level, slot)
	brain.target = best
	brain.stage = "pull"
	brain.stuckFor = 0
	brain.margin = Stability.margin(tw)
	if b then
		brain.goal = b.along
		brain.lastAlong = b.along
		brain.sign = if math.abs(b.along) > 0.02
			then (if b.along > 0 then 1 else -1)
			elseif draw(brain) < 0.5 then 1
			else -1
		brain.push = S.pushMiddle and slot == 2
		local load = brain.est[best] or 0
		brain.speed = if load <= 2 * Physics.LOOSE_LOAD then S.fast else S.slow
	end
end

-- The place on top that leaves the tower best balanced.
local function bestSlot(tw: Tower.Tower, free: { number }, level: number): number
	local best, bestMargin = free[1], -math.huge
	for _, slot in free do
		local c = Tower.clone(tw)
		if level > #c.levels then
			c.levels[level] = { 0, 0, 0 }
			c.shiftX[level], c.shiftZ[level] = 0, 0
			c.psiX[level], c.omX[level], c.psiZ[level], c.omZ[level] = 0, 0, 0, 0
		end
		local b = c.blocks[c.inHand]
		b.level, b.slot, b.along, b.across = level, slot, 0, 0
		c.levels[level][slot] = b.id
		local an = Stability.analyse(c)
		local margin = if an.ok then an.margin else -1
		if margin > bestMargin + 1e-9 then
			best, bestMargin = slot, margin
		end
	end
	return best
end

-- act(brain, tower, phase, dt): the bot's input for this twentieth of a second, if it has one. `phase` is the
-- rules' phase for its turn: "draw", "place" or "settle".
function Bots.act(brain: Brain, tw: Tower.Tower, phase: string, dt: number): (string?, { any }?)
	local S = Bots.SKILLS[brain.skill]
	if tw.fallen then
		return nil
	end
	if phase == "draw" then
		if tw.inHand ~= 0 then
			return nil
		end
		if (brain.stage == "start" or brain.stage == "placed") and tw.held ~= 0 then
			-- taking over a turn with a block already on the move
			local b = tw.blocks[tw.held]
			if math.abs(b.along) < Tower.COMMIT then
				return "release", {}
			end
			brain.target = b.level * 4 + b.slot
			brain.margin = Stability.margin(tw)
			brain.stage = "pull"
			brain.goal = b.along
			brain.lastAlong = b.along
			brain.stuckFor = 0
			brain.sign = if b.along > 0 then 1 else -1
			brain.push = tw.push
			brain.speed = S.slow
			return nil
		end
		if brain.stage == "start" or brain.stage == "placed" then
			brain.stage = "think"
			brain.t = 0
			brain.tapped = 0
			brain.est = {}
			brain.queue = legalKeys(tw)
			-- knock on them in its own order
			for k = #brain.queue, 2, -1 do
				local j = 1 + math.floor(draw(brain) * k)
				brain.queue[k], brain.queue[j] = brain.queue[j], brain.queue[k]
			end
		end
		if brain.stage == "think" then
			brain.t += dt
			if brain.t >= S.think then
				brain.stage = "tap"
				brain.t = Bots.TAP_GAP
			end
			return nil
		end
		if brain.stage == "tap" then
			brain.t += dt
			if brain.t < Bots.TAP_GAP then
				return nil
			end
			brain.t = 0
			if #brain.queue > 0 and brain.tapped < S.taps then
				local key = table.remove(brain.queue) :: number
				local level, slot = key // 4, key % 4
				local f = Physics.feel(tw, level, slot)
				if f then
					-- what the knock says: the weight on it, and worse if it is one of the blocks holding
					-- its level up (a dull knock)
					local est = f.load + (if f.kind == "tight" then Bots.TIGHT else 0)
					if draw(brain) < S.misjudge then
						est = draw(brain) * 6 -- a knock misread: it could be anything
					end
					brain.est[key] = est
					brain.tapped += 1
					return "tap", { level, slot }
				end
				return nil
			end
			brain.stage = "choose"
		end
		if brain.stage == "choose" then
			-- never reach into a tower that is still rocking (the weakest waits least)
			if Physics.danger(tw) > S.calm then
				return nil
			end
			choose(brain, tw)
			return nil
		end
		if brain.stage == "pull" then
			local level, slot = brain.target // 4, brain.target % 4
			local b = Tower.blockAt(tw, level, slot)
			if not b then
				brain.stage = "choose"
				return nil
			end
			if math.abs(b.along - brain.lastAlong) < 0.004 then
				brain.stuckFor += dt
			else
				brain.stuckFor = 0
			end
			brain.lastAlong = b.along
			if math.abs(b.along) < Tower.COMMIT and brain.giveUps < 2 then
				-- its nerve: the tower rocking, or visibly coming along with the block
				local margin = Stability.margin(tw)
				local alarm = math.max(Physics.danger(tw), 1 - margin / math.max(brain.margin, 1e-3))
				if alarm > S.nerve or brain.stuckFor > Bots.STUCK then
					brain.bad[brain.target] = true
					brain.giveUps += 1
					brain.stage = "choose"
					return "release", {}
				end
			end
			brain.goal += brain.sign * brain.speed * dt
			brain.goal = math.clamp(brain.goal, b.along - Bots.LEAD, b.along + Bots.LEAD)
			brain.phase += dt * 7
			local lateral = S.wobble * (math.sin(brain.phase) + (draw(brain) - 0.5))
			local args: { any } = { level, slot, brain.goal, lateral, brain.push }
			return "pull", args
		end
		return nil
	elseif phase == "place" then
		if tw.inHand == 0 then
			return nil
		end
		if brain.stage ~= "place" then
			brain.stage = "place"
			brain.t = 0
			local level, free = Tower.building(tw)
			if S.bestSlot then
				brain.slot = bestSlot(tw, free, level)
			elseif table.find(free, 2) and draw(brain) < 0.5 then
				brain.slot = 2
			else
				brain.slot = free[1 + math.floor(draw(brain) * #free)]
			end
		end
		brain.t += dt
		if brain.t < Bots.PLACE_WAIT then
			return nil
		end
		brain.stage = "placed"
		brain.giveUps = 0
		brain.bad = {}
		local along = (draw(brain) - 0.5) * 2 * S.placeErr
		local across = (draw(brain) - 0.5) * S.placeErr
		local speed = S.dropLo + (S.dropHi - S.dropLo) * draw(brain)
		return "place", { brain.slot, along, across, speed }
	end
	return nil
end

return Bots
