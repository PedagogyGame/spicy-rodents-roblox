--!strict
-- ReplicatedStorage.Shared.Minigames.Jenga.View
-- What a client draws the tower from (checklist JEN-P8; C10). Two kinds of message, both plain numbers:
--   * a SNAPSHOT (Tower.snapshot) whenever a block leaves or joins a level: the whole tower, about 320 numbers;
--   * a FRAME 20 times a second while anything moves: which block is held and where it has got to, which
--     joints are rocking and by how much, and the levels' shifts when they changed. A quiet tower sends
--     frames of a dozen numbers.
-- The client keeps a mirror tower (Tower.restore), lays each frame over it (apply) and asks for the poses
-- (Stability.poses through `poses`): the same code that judged the tower says where every block is, so
-- everyone sees the tower the server holds. The player who is pulling runs Physics on their own mirror for
-- their own block between frames, and each frame from the server corrects it.
-- Pure; Lune-tested (tests/unit/jenga_rules.spec.luau).
-- Interface: frame(tower, sentKey?) -> Frame; apply(mirror, frame) -> boolean (false: wrong snapshot);
--   check(any) -> (Frame?, why?); size(frame) -> numbers; shiftKey(tower) -> number; poses(tower, out?)

local Layout = require("./Layout")
local Physics = require("./Physics")
local Stability = require("./Stability")
local Tower = require("./Tower")

local View = {}

View.RATE = 20 -- frames a second
View.STEPS = Physics.RATE / View.RATE -- physics steps per frame

export type Frame = {
	rev: number, -- the snapshot this frame lies over
	step: number,
	held: number, -- block id being slid, 0 for none
	along: number,
	across: number,
	hand: number, -- where the hand is along the block's line (it leads a block that resists)
	inHand: number,
	rock: { number }, -- pairs: joint index (2 * level + direction), lean in radians
	key: number, -- changes when any level has shifted
	sx: { number }?, -- every level's shift, sent when the key changed
	sz: { number }?,
	danger: number, -- 0..1, how near the worst joint is to going (the slow beat and the creaks play off this)
}

-- A number that changes whenever any level's shift does.
function View.shiftKey(tw: Tower.Tower): number
	local sum = 0
	for k = 1, #tw.levels do
		sum += tw.shiftX[k] * (k + 0.25) + tw.shiftZ[k] * (k + 0.75)
	end
	return sum
end

-- frame(tower, sentKey): the frame for the tower as it is now. Pass the `key` of the last frame that was
-- sent: the shifts are only included when they have changed since.
function View.frame(tw: Tower.Tower, sentKey: number?): Frame
	local rock = {}
	for k = 1, #tw.levels do
		if tw.psiX[k] ~= 0 then
			table.insert(rock, 2 * (k - 1) + 1)
			table.insert(rock, tw.psiX[k])
		end
		if tw.psiZ[k] ~= 0 then
			table.insert(rock, 2 * (k - 1) + 2)
			table.insert(rock, tw.psiZ[k])
		end
	end
	local key = View.shiftKey(tw)
	local held = tw.held
	local b = if held ~= 0 then tw.blocks[held] else nil
	local out: Frame = {
		rev = tw.rev,
		step = tw.step,
		held = held,
		along = if b then b.along else 0,
		across = if b then b.across else 0,
		hand = if b then tw.hand else 0,
		inHand = tw.inHand,
		rock = rock,
		key = key,
		danger = Physics.danger(tw),
	}
	if key ~= sentKey then
		out.sx = table.clone(tw.shiftX)
		out.sz = table.clone(tw.shiftZ)
	end
	return out
end

-- apply(mirror, frame): lay a frame over the client's mirror of the tower. False when the frame belongs to a
-- different snapshot (the client waits for that snapshot and draws nothing new until then).
function View.apply(tw: Tower.Tower, frame: Frame): boolean
	if frame.rev ~= tw.rev then
		return false
	end
	local n = #tw.levels
	tw.held = frame.held
	tw.inHand = frame.inHand
	tw.step = frame.step
	if frame.held ~= 0 then
		local b = tw.blocks[frame.held]
		if b and b.level > 0 then
			b.along, b.across = frame.along, frame.across
			tw.hand = frame.hand
		end
	end
	local sx, sz = frame.sx, frame.sz
	if sx and sz and #sx == n and #sz == n then
		for k = 1, n do
			tw.shiftX[k], tw.shiftZ[k] = sx[k], sz[k]
		end
	end
	tw.stale = true
	Stability.ensure(tw) -- settle the mirror's resting pose first, so the leans below are drawn as sent
	for k = 1, n do
		tw.psiX[k], tw.omX[k], tw.psiZ[k], tw.omZ[k] = 0, 0, 0, 0
	end
	local rock = frame.rock
	for p = 1, #rock - 1, 2 do
		local j = rock[p]
		local i = math.floor((j - 1) / 2)
		if i >= 0 and i < n then
			if (j - 1) % 2 == 0 then
				tw.psiX[i + 1] = rock[p + 1]
			else
				tw.psiZ[i + 1] = rock[p + 1]
			end
		end
	end
	return true
end

local function isNumber(v: any, limit: number): boolean
	return type(v) == "number" and v == v and math.abs(v) <= limit
end

-- check(any): a table off the wire is a frame only if every part of it is a number in bounds.
function View.check(raw: any): (Frame?, string?)
	if type(raw) ~= "table" then
		return nil, "not a frame"
	end
	for _, key in { "rev", "step", "key" } do
		if not isNumber(raw[key], 1e9) then
			return nil, key
		end
	end
	for _, key in { "held", "inHand" } do
		local v = raw[key]
		if not isNumber(v, Layout.BLOCKS) or v < 0 or v ~= math.floor(v) then
			return nil, key
		end
	end
	for _, key in { "along", "across", "hand", "danger" } do
		if not isNumber(raw[key], 4) then
			return nil, key
		end
	end
	if type(raw.rock) ~= "table" or #raw.rock % 2 ~= 0 or #raw.rock > 4 * Layout.BLOCKS then
		return nil, "rock"
	end
	for p = 1, #raw.rock, 2 do
		local j = raw.rock[p]
		if not isNumber(j, 2 * Layout.BLOCKS) or j < 1 or j ~= math.floor(j) or not isNumber(raw.rock[p + 1], 2) then
			return nil, "rock"
		end
	end
	if raw.sx ~= nil or raw.sz ~= nil then
		if type(raw.sx) ~= "table" or type(raw.sz) ~= "table" or #raw.sx ~= #raw.sz or #raw.sx > Layout.BLOCKS then
			return nil, "shift"
		end
		for k = 1, #raw.sx do
			if not isNumber(raw.sx[k], 4) or not isNumber(raw.sz[k], 4) then
				return nil, "shift"
			end
		end
	end
	return raw :: Frame
end

function View.size(frame: Frame): number
	local sx = frame.sx
	return 9 + #frame.rock + (if sx then 2 * #sx else 0)
end

function View.poses(tw: Tower.Tower, out: { number }?): { number }
	return Stability.poses(tw, out)
end

return View
