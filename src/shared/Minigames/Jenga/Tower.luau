--!strict
-- ReplicatedStorage.Shared.Minigames.Jenga.Tower
-- The whole state of a giant Jenga tower as plain data, and the questions about its STRUCTURE (checklist
-- JEN-R1, JEN-R2): which blocks are where, which may be taken, where a block in hand may go. Nothing here
-- moves; Stability judges the state and Physics steps it. There is no hidden state: everything a tower will do
-- next follows from this table (the cached analysis `an` is derived and can be thrown away), so two machines
-- holding the same table play the same game, and encode() gives its exact bytes for the determinism specs.
-- What is remembered (JEN-P1, JEN-P5):
--   * each block's seeded thickness error `dt` (which blocks carry the weight follows from these),
--   * each block's slide along its own length (`along`) and sideways (`across`) from square in its slot,
--   * each level's shift against the level under it (`shiftX`, `shiftZ`): dragged and rocked towers creep,
--   * the rocking of the part above every level (`psiX`, `omX`, `psiZ`, `omZ`: lean in radians and its rate,
--     stored at index level + 1 for the joint on top of that level; index 1 is the joint on the table).
-- Pure; Lune-tested (tests/unit/jenga_tower.spec.luau).
-- Interface: new(seed) -> Tower; clone(tower) -> Tower; levelsOf(tower) -> (levels, completeLevels);
--   highestComplete(tower) -> level; blockAt(tower, level, slot) -> Block?; countIn(tower, level) -> number;
--   legal(tower, level, slot) -> (boolean, why?); building(tower) -> (level, { free slots });
--   touch(tower) (marks the analysis stale); emit(tower, kind, a, b); drain(tower) -> { Event };
--   snapshot(tower) -> Snapshot; restore(snapshot) -> Tower; encode(tower) -> string; THICK_VAR

local Rng = require("../../Util/Rng")
local Layout = require("./Layout")

local Tower = {}

Tower.THICK_VAR = 0.004 -- studs: a block is this much thicker or thinner than nominal at most (seeded)
Tower.COMMIT = Layout.BLOCK_L / 3 -- a block slid this far is yours (JEN-R3)

export type Block = {
	id: number,
	level: number, -- 0: not in the tower (in a hand, or fallen)
	slot: number, -- 1..3 across the level
	along: number, -- slide along its own length from square, studs (+ toward +X on odd levels, +Z on even)
	across: number, -- sideways drift in its slot
	dt: number, -- thickness error
}

-- Where and how a tower failed: the joint on top of `level` (0 = on the table) gave way toward sign * dir.
export type Failure = { level: number, dir: string, sign: number, why: string }

export type Event = { step: number, kind: string, a: number, b: number }

export type Tower = {
	seed: number,
	step: number, -- fixed steps taken
	blocks: { Block },
	levels: { { number } }, -- levels[k][slot] = block id, or 0 for a gap
	shiftX: { number },
	shiftZ: { number },
	psiX: { number },
	omX: { number },
	psiZ: { number },
	omZ: { number },
	-- the hand (Physics)
	held: number, -- id of the block being slid, 0 for none
	push: boolean, -- pushed through from the far end (true) or dragged by the near end (false)
	goal: number, -- where the player wants the block (its `along`): the last sample
	hand: number, -- where the hand is: it follows the goal no faster than a hand can move
	handLat: number, -- how far the hand has wandered off the block's line
	sliding: boolean,
	inHand: number, -- id of the block that is out and waiting to be placed, 0 for none
	moved: number, -- blocks taken out so far
	fallen: Failure?,
	rev: number, -- goes up whenever a block leaves or joins a level
	stale: boolean,
	an: any, -- Stability.Analysis cache (derived)
	events: { Event },
}

function Tower.new(seed: number): Tower
	local rng = Rng.new(seed)
	local blocks: { Block } = {}
	local levels: { { number } } = {}
	local id = 0
	for level = 1, Layout.START_LEVELS do
		local row = {}
		for slot = 1, Layout.PER_LEVEL do
			id += 1
			blocks[id] = {
				id = id,
				level = level,
				slot = slot,
				along = 0,
				across = 0,
				dt = (rng.next() * 2 - 1) * Tower.THICK_VAR,
			}
			row[slot] = id
		end
		levels[level] = row
	end
	local n = Layout.START_LEVELS
	return {
		seed = seed,
		step = 0,
		blocks = blocks,
		levels = levels,
		shiftX = table.create(n, 0),
		shiftZ = table.create(n, 0),
		psiX = table.create(n, 0),
		omX = table.create(n, 0),
		psiZ = table.create(n, 0),
		omZ = table.create(n, 0),
		held = 0,
		push = false,
		goal = 0,
		hand = 0,
		handLat = 0,
		sliding = false,
		inHand = 0,
		moved = 0,
		fallen = nil,
		rev = 1,
		stale = true,
		an = nil,
		events = {},
	}
end

function Tower.clone(tw: Tower): Tower
	local blocks: { Block } = table.create(#tw.blocks)
	for i, b in tw.blocks do
		blocks[i] = { id = b.id, level = b.level, slot = b.slot, along = b.along, across = b.across, dt = b.dt }
	end
	local levels: { { number } } = table.create(#tw.levels)
	for k, row in tw.levels do
		levels[k] = { row[1], row[2], row[3] }
	end
	return {
		seed = tw.seed,
		step = tw.step,
		blocks = blocks,
		levels = levels,
		shiftX = table.clone(tw.shiftX),
		shiftZ = table.clone(tw.shiftZ),
		psiX = table.clone(tw.psiX),
		omX = table.clone(tw.omX),
		psiZ = table.clone(tw.psiZ),
		omZ = table.clone(tw.omZ),
		held = tw.held,
		push = tw.push,
		goal = tw.goal,
		hand = tw.hand,
		handLat = tw.handLat,
		sliding = tw.sliding,
		inHand = tw.inHand,
		moved = tw.moved,
		fallen = tw.fallen,
		rev = tw.rev,
		stale = true,
		an = nil,
		events = {},
	}
end

function Tower.touch(tw: Tower)
	tw.stale = true
end

function Tower.emit(tw: Tower, kind: string, a: number, b: number)
	local ev = tw.events
	if #ev < 256 then
		ev[#ev + 1] = { step = tw.step, kind = kind, a = a, b = b }
	end
end

function Tower.drain(tw: Tower): { Event }
	local ev = tw.events
	tw.events = {}
	return ev
end

function Tower.countIn(tw: Tower, level: number): number
	local row = tw.levels[level]
	if not row then
		return 0
	end
	return (if row[1] ~= 0 then 1 else 0) + (if row[2] ~= 0 then 1 else 0) + (if row[3] ~= 0 then 1 else 0)
end

-- levelsOf: how many levels the tower has, and how many of them are complete (three blocks).
function Tower.levelsOf(tw: Tower): (number, number)
	local n = #tw.levels
	local complete = 0
	for k = 1, n do
		if Tower.countIn(tw, k) == Layout.PER_LEVEL then
			complete += 1
		end
	end
	return n, complete
end

-- The highest level with all three blocks: blocks may only be taken from BELOW it (JEN-R2).
function Tower.highestComplete(tw: Tower): number
	for k = #tw.levels, 1, -1 do
		if Tower.countIn(tw, k) == Layout.PER_LEVEL then
			return k
		end
	end
	return 0
end

function Tower.blockAt(tw: Tower, level: number, slot: number): Block?
	local row = tw.levels[level]
	if not row then
		return nil
	end
	local id = row[slot]
	if id == nil or id == 0 then
		return nil
	end
	return tw.blocks[id]
end

-- legal(level, slot): may this block be taken? (structure only; whose turn it is belongs to Rules)
function Tower.legal(tw: Tower, level: number, slot: number): (boolean, string?)
	if tw.fallen then
		return false, "the tower is down"
	end
	if level ~= math.floor(level) or slot ~= math.floor(slot) or slot < 1 or slot > Layout.PER_LEVEL then
		return false, "no such block"
	end
	if Tower.blockAt(tw, level, slot) == nil then
		return false, "no block there"
	end
	if level >= Tower.highestComplete(tw) then
		return false, "only blocks below the highest complete level"
	end
	return true
end

-- building(): the level a block in hand goes on, and its free slots. A level of three is finished before the
-- next is started (JEN-R2), so this is the top level while it has a gap, otherwise a new level on top.
function Tower.building(tw: Tower): (number, { number })
	local n = #tw.levels
	local free = {}
	if Tower.countIn(tw, n) < Layout.PER_LEVEL then
		local row = tw.levels[n]
		for slot = 1, Layout.PER_LEVEL do
			if row[slot] == 0 then
				table.insert(free, slot)
			end
		end
		return n, free
	end
	return n + 1, { 1, 2, 3 }
end

-- Snapshot: everything a client needs to draw the tower exactly as the server holds it (sent when `rev`
-- changes); the rocking and the block in the hand come in the frames between (View).
export type Snapshot = {
	rev: number,
	seed: number,
	n: number,
	b: { number }, -- per block: level, slot, along, across, dt
	sx: { number },
	sz: { number },
	held: number,
	inHand: number,
	moved: number,
}

function Tower.snapshot(tw: Tower): Snapshot
	local b = table.create(#tw.blocks * 5)
	for i, blk in tw.blocks do
		local o = (i - 1) * 5
		b[o + 1] = blk.level
		b[o + 2] = blk.slot
		b[o + 3] = blk.along
		b[o + 4] = blk.across
		b[o + 5] = blk.dt
	end
	return {
		rev = tw.rev,
		seed = tw.seed,
		n = #tw.levels,
		b = b,
		sx = table.clone(tw.shiftX),
		sz = table.clone(tw.shiftZ),
		held = tw.held,
		inHand = tw.inHand,
		moved = tw.moved,
	}
end

-- restore(snapshot): a tower at rest in that state, or nil with the reason if the table is not a snapshot
-- (a client validates what comes off the wire before drawing it).
function Tower.restore(snap: any): (Tower?, string?)
	if type(snap) ~= "table" or type(snap.b) ~= "table" or type(snap.sx) ~= "table" or type(snap.sz) ~= "table" then
		return nil, "not a snapshot"
	end
	local n = snap.n
	if type(n) ~= "number" or n ~= math.floor(n) or n < 1 or n > Layout.BLOCKS then
		return nil, "levels"
	end
	if #snap.b ~= Layout.BLOCKS * 5 or #snap.sx ~= n or #snap.sz ~= n then
		return nil, "size"
	end
	for _, list in { snap.b, snap.sx, snap.sz } do
		for _, v in list do
			if type(v) ~= "number" or v ~= v or math.abs(v) > 1e4 then
				return nil, "number"
			end
		end
	end
	local tw = Tower.new(0)
	tw.seed = if type(snap.seed) == "number" then snap.seed else 0
	tw.levels = table.create(n)
	for k = 1, n do
		tw.levels[k] = { 0, 0, 0 }
	end
	for i = 1, Layout.BLOCKS do
		local o = (i - 1) * 5
		local level, slot = snap.b[o + 1], snap.b[o + 2]
		if level ~= math.floor(level) or level < 0 or level > n or slot ~= math.floor(slot) or slot < 1 or slot > 3 then
			return nil, "block"
		end
		local blk = tw.blocks[i]
		blk.level, blk.slot, blk.along, blk.across, blk.dt = level, slot, snap.b[o + 3], snap.b[o + 4], snap.b[o + 5]
		if level > 0 then
			if tw.levels[level][slot] ~= 0 then
				return nil, "two blocks in one slot"
			end
			tw.levels[level][slot] = i
		end
	end
	tw.shiftX, tw.shiftZ = table.clone(snap.sx), table.clone(snap.sz)
	tw.psiX, tw.omX = table.create(n, 0), table.create(n, 0)
	tw.psiZ, tw.omZ = table.create(n, 0), table.create(n, 0)
	tw.held = if type(snap.held) == "number" then snap.held else 0
	tw.inHand = if type(snap.inHand) == "number" then snap.inHand else 0
	tw.moved = if type(snap.moved) == "number" then snap.moved else 0
	tw.rev = if type(snap.rev) == "number" then snap.rev else 1
	return tw
end

-- encode(): the exact bytes of the state (every number as a 64-bit float), for "same seed and inputs give the
-- same bytes".
function Tower.encode(tw: Tower): string
	local n = #tw.levels
	local count = 13 + #tw.blocks * 5 + n * 6
	local buf = buffer.create(count * 8)
	local at = 0
	local function put(v: number)
		buffer.writef64(buf, at, v)
		at += 8
	end
	put(tw.seed)
	put(tw.step)
	put(n)
	put(tw.held)
	put(if tw.push then 1 else 0)
	put(tw.goal)
	put(tw.hand)
	put(tw.handLat)
	put(if tw.sliding then 1 else 0)
	put(tw.inHand)
	put(tw.moved)
	put(tw.rev)
	local f = tw.fallen
	put(if f then f.level * 4 + (if f.dir == "x" then 1 else 2) * f.sign else -99)
	for _, b in tw.blocks do
		put(b.level)
		put(b.slot)
		put(b.along)
		put(b.across)
		put(b.dt)
	end
	for k = 1, n do
		put(tw.shiftX[k])
		put(tw.shiftZ[k])
		put(tw.psiX[k])
		put(tw.omX[k])
		put(tw.psiZ[k])
		put(tw.omZ[k])
	end
	return buffer.tostring(buf)
end

return Tower
