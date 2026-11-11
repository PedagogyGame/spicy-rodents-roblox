--!strict
-- ReplicatedStorage.Shared.Minigames.Bowling.Intruders
-- The rule for a squirrel (or the Spicy Rodent) that runs onto a lane during a game: IT CANNOT BREAK THE GAME.
-- The throw is decided by the pin model, which never sees the animal, so a throw always counts and a release is
-- never held up. What the animal gets is bowled over: if the ball's path passes through it, or the pinsetter's
-- sweep bar comes down the deck onto it, it is knocked into the nearer gutter, short of the pins, and both
-- sides are told on screen what happened. People cannot get onto the lanes at all (the bake's LaneGuard).
-- Lane frame: x across from the lane centre (bowler's right +), d down-lane from the foul line, y up.
-- Pure; Lune-tested (tests/unit/bowling_lanecycle.spec.luau).
-- Interface: onLane(x, y, d) -> bool; struck(script, t0, t1, animals { { id, x, y, d } }) -> { Knock { id, x,
--   d } }; swept(d0, d1, animals) -> { Knock }; knockTo(x, d, awayFromX?) -> (x, d); REACH; TEXT

local AlleyLayout = require("../../Attractions/AlleyLayout")
local RollScript = require("./RollScript")

local Intruders = {}

Intruders.REACH = AlleyLayout.BALL_D / 2 + 0.6 -- the ball's radius plus a squirrel's body
Intruders.STEP = 1 / 60 -- how finely the ball's flight is checked
Intruders.GUTTER_X = AlleyLayout.LANE_W / 2 + AlleyLayout.GUTTER_W / 2
Intruders.TEXT = {
	bowlers = "ran onto the lane: the ball knocked it into the gutter. The throw counts.",
	swept = "was on the pin deck: the sweep bar pushed it off. Play goes on.",
	animal = "A bowling ball knocked you off the lane!",
	animalSwept = "The pinsetter's sweep bar pushed you off the pin deck!",
}

export type Animal = { id: any, x: number, y: number, d: number }
export type Knock = { id: any, x: number, d: number }

-- On the playing surface of a lane: the bed, its gutters or the pin deck, between the foul line and the pit,
-- at lane height (not in the ball-return duct underneath, not up on the masking unit).
function Intruders.onLane(x: number, y: number, d: number): boolean
	return math.abs(x) <= AlleyLayout.LANE_W / 2 + AlleyLayout.GUTTER_W
		and y > AlleyLayout.DUCT_CEIL
		and y < 3
		and d > AlleyLayout.FOUL_D + 0.5
		and d < AlleyLayout.PIT_END
end

-- Where a knocked animal ends up: in the gutter on the side away from what hit it, never among the pins.
function Intruders.knockTo(x: number, d: number, awayFromX: number?): (number, number)
	local side = if awayFromX ~= nil and x ~= awayFromX
		then (if x > awayFromX then 1 else -1)
		else (if x >= 0 then 1 else -1)
	return side * Intruders.GUTTER_X, math.clamp(d - 1.5, AlleyLayout.FOUL_D + 2, AlleyLayout.DECK_START - 2.5)
end

-- struck: the animals the ball passes through between script times t0 and t1.
function Intruders.struck(script: RollScript.Script, t0: number, t1: number, animals: { Animal }): { Knock }
	local out: { Knock } = {}
	if script.path == nil or #animals == 0 or t1 <= t0 then
		return out
	end
	local hit: { [any]: boolean } = {}
	local steps = math.max(1, math.ceil((t1 - t0) / Intruders.STEP))
	for i = 0, steps do
		local t = t0 + (t1 - t0) * i / steps
		local bx, _, bd, _, where = RollScript.ball(script, t)
		if bx == nil or where ~= "lane" then
			continue
		end
		for _, a in animals do
			if not hit[a.id] and Intruders.onLane(a.x, a.y, a.d) then
				local dx, dd = a.x - bx, a.d - bd
				if dx * dx + dd * dd <= Intruders.REACH * Intruders.REACH then
					hit[a.id] = true
					local x, d = Intruders.knockTo(a.x, a.d, bx)
					table.insert(out, { id = a.id, x = x, d = d })
				end
			end
		end
	end
	return out
end

-- swept: the animals on the deck that the sweep bar reached as it moved from d0 to d1 at deck level.
function Intruders.swept(d0: number, d1: number, animals: { Animal }): { Knock }
	local out: { Knock } = {}
	local lo, hi = math.min(d0, d1) - 0.4, math.max(d0, d1) + 0.4
	for _, a in animals do
		if Intruders.onLane(a.x, a.y, a.d) and a.y < 1.2 and a.d >= lo and a.d <= hi then
			local x, d = Intruders.knockTo(a.x, a.d, nil)
			table.insert(out, { id = a.id, x = x, d = d })
		end
	end
	return out
end

return Intruders
