--!strict
-- Bowling's feel (owner D32: "simple, crude ... no way to put any angle or twist ... the aiming wasn't very good"),
-- held over whole throws through the real models (Minigames/Bowling: AimModel, BallPath, PinModel, RollScript,
-- Referee.aimAngle) with a bowler's ordinary small errors (a couple of boards at the pins, a little on the feet):
--   * a hook into the pocket strikes more than a straight ball into the pocket, which strikes far more than a
--     straight ball at the head pin; a straight ball is still a way to strike;
--   * the spin's direction is honoured: a left-hander's hook into the 1-2 pocket is the mirror of a right-hander's
--     into the 1-3, and does as well;
--   * the approach (Minigames/Bowling/Approach): four steps forward, never back, the ball swung back then through to
--     the release at the line, a follow-through, then standing again.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Approach = require("@shared/Minigames/Bowling/Approach")
local PinModel = require("@shared/Minigames/Bowling/PinModel")
local Referee = require("@shared/Minigames/Bowling/Referee")
local RollScript = require("@shared/Minigames/Bowling/RollScript")
local Rng = require("@shared/Util/Rng")

local THROWS = 240
local ERR_ANGLE = 0.003 -- radians either way (0.17 studs, under two boards, at the pins)
local ERR_OFFSET = 0.03 -- of the foul line's half width (half a board)
local POWER = 0.7 -- in the meter's green band: no release error of its own

type Rate = { strike: number, mean: number }

-- THROWS throws at a line: from `offset` with `spin`, aimed so the ball's centre crosses x at the head pin's row,
-- each with a seeded small error in the angle and the stand.
local function rate(offset: number, spin: number, x: number): Rate
	local angle = Referee.aimAngle(offset, POWER, spin, x, AlleyLayout.HEAD_D)
	local rng = Rng.new(77)
	local strikes, down = 0, 0
	for seed = 1, THROWS do
		local a = (rng.next() + rng.next() - 1) * ERR_ANGLE
		local o = (rng.next() + rng.next() - 1) * ERR_OFFSET
		local s = RollScript.build(
			{ offset = offset + o, angle = angle + a, power = POWER, spin = spin },
			PinModel.fullRack(),
			seed
		)
		if s.down == 10 then
			strikes += 1
		end
		down += s.down
	end
	return { strike = strikes / THROWS, mean = down / THROWS }
end

return function(t)
	t.test("a hook into the pocket strikes more than a straight ball; straight at the head pin hardly ever", function()
		local head = rate(0, 0, 0)
		local straight = rate(0.16, 0, 0.25)
		local hook = rate(0.55, -1, 0.27)
		local half = rate(0.5, -0.5, 0.27)
		t.truthy(head.strike < 0.15, `straight at the head pin strikes {head.strike}`)
		t.truthy(straight.strike >= 0.35, `a straight ball into the pocket still strikes: {straight.strike}`)
		t.truthy(
			straight.strike > head.strike + 0.25,
			`straight pocket {straight.strike} against head pin {head.strike}`
		)
		t.truthy(hook.strike > straight.strike + 0.15, `full hook {hook.strike} against straight {straight.strike}`)
		t.truthy(half.strike > straight.strike + 0.05, `half hook {half.strike} against straight {straight.strike}`)
		t.truthy(hook.mean > straight.mean and straight.mean > head.mean)
	end)

	t.test("the spin's direction is honoured: a left-hander's hook into the 1-2 pocket does as well", function()
		local right = rate(0.55, -1, 0.27)
		local left = rate(-0.55, 1, -0.27)
		t.truthy(math.abs(right.strike - left.strike) <= 0.08, `1-3 hook {right.strike}, 1-2 hook {left.strike}`)
		-- and a hook the wrong way (spinning away from the pocket) is no good at all
		local wrong = rate(0.55, 1, 0.27)
		t.truthy(wrong.strike < right.strike - 0.2, `hooking away from the pocket strikes {wrong.strike}`)
	end)

	t.test("the approach: four steps forward, the swing back and through, the release at the line", function()
		local p0 = Approach.pose(0)
		t.eq(p0.d, Approach.START_D)
		t.truthy(Approach.START_D < AlleyLayout.HOOD_D1, "the bowler waits behind the ball return's hood")
		local last = p0.d
		local back, through = false, false
		local n = 120
		for i = 1, n do
			local tt = Approach.TIME * i / n
			local p = Approach.pose(tt)
			t.truthy(p.d >= last - 1e-9, "never a step back")
			last = p.d
			back = back or p.arm < -1
			through = through or (back and p.arm > 0.5)
			t.truthy(p.drop >= 0 and p.drop <= 0.25, "the body never drops much (the humanoid keeps its height)")
		end
		t.truthy(back and through, "the ball went back over the shoulder's line and came through")
		local rel = Approach.pose(Approach.releaseAt())
		t.near(rel.d, Approach.SLIDE_D, 1e-9)
		t.truthy(rel.arm > 0.5, "at the release the arm is swinging through, in front")
		t.truthy(Approach.SLIDE_D < AlleyLayout.FOUL_D - 1, "the slide stops short of the foul line")
		t.truthy(rel.leadKnee < -0.5 and rel.trailHip < -0.4, "the slide: lead knee bent, the other leg behind")
		-- the follow-through rises, then everything eases back to standing
		t.truthy(Approach.pose(Approach.TIME + 0.2).arm > rel.arm)
		local done = Approach.pose(Approach.TIME + Approach.FOLLOW)
		for _, k in { "drop", "arm", "leadHip", "leadKnee", "trailHip", "waist" } do
			t.near((done :: any)[k], 0, 1e-6, `{k} back to standing`)
		end
		-- no jumps anywhere: a pose a frame apart is close
		local prev = Approach.pose(0)
		local tt = 0
		while tt < Approach.TIME + Approach.FOLLOW do
			tt += 1 / 60
			local p = Approach.pose(tt)
			t.truthy(math.abs(p.d - prev.d) < 0.3, `the root at {tt}`)
			t.truthy(math.abs(p.arm - prev.arm) < 0.25, `the arm at {tt}`)
			prev = p
		end
	end)
end
