--!strict
-- ReplicatedStorage.Shared.Minigames.Bowling.Shots
-- The bowling camera's shots as pure numbers (the client turns them into a CFrame): behind the bowler while
-- aiming; behind the ball as it runs down the lane; ONE cut, a moment before the ball arrives, to a low
-- three-quarter view of the pins that is held through the pinfall; then "done", which tells the client to hand
-- the camera back (Client/Minigames/MinigameClient releases CameraRig and refreshes the player's own camera).
-- The shot is timed from the throw itself (RollScript), not from guessed timers, so a slow ball, a fast one
-- and a gutter ball all cut at the right moment. Every eye position is inside the room.
-- Lane frame: x across from the lane centre (bowler's right +), d down-lane from the foul line, y up.
-- Pure; Lune-tested (tests/unit/bowling_shots.spec.luau).
-- Interface: aim(offset, angle) -> Shot; between() -> Shot (the pinsetter working, your next ball to come);
--   roll(script, t) -> Shot { ex, ey, ed, lx, ly, ld, fov, phase "follow" | "pins" | "done" }; cutTime(script);
--   doneTime(script); LEAD, HOLD

local AlleyLayout = require("../../Attractions/AlleyLayout")
local RollScript = require("./RollScript")

local Shots = {}

Shots.LEAD = 0.45 -- the cut to the pins comes this long before the ball arrives
Shots.HOLD = 1.0 -- how long the pin shot stays after everything has stopped
Shots.FOLLOW_BACK = 7 -- studs behind the ball
Shots.FOLLOW_UP = 2.6
Shots.PIN_EYE = { x = 1.7, y = 2.5, d = 49.5 } -- low, a little to the right, short of the masking unit
Shots.PIN_LOOK = { x = 0, y = 0.7, d = AlleyLayout.HEAD_D + 1.6 }

export type Shot = {
	ex: number,
	ey: number,
	ed: number,
	lx: number,
	ly: number,
	ld: number,
	fov: number,
	phase: string,
}

-- Behind and above the bowler, looking down the line of the throw.
function Shots.aim(offset: number, angle: number): Shot
	return {
		ex = math.clamp(offset, -1, 1) * 0.8,
		ey = 5.6,
		ed = -12.5,
		lx = math.tan(angle) * 30,
		ly = 0.4,
		ld = 38,
		fov = 50,
		phase = "aim",
	}
end

-- Between your two balls: the same place, looking at the deck while the pinsetter works.
function Shots.between(): Shot
	return { ex = 0, ey = 5.6, ed = -12.5, lx = 0, ly = 0.4, ld = 50, fov = 50, phase = "between" }
end

function Shots.cutTime(script: RollScript.Script): number
	return math.max(0, script.tImpact - Shots.LEAD)
end

function Shots.doneTime(script: RollScript.Script): number
	return script.tEnd + Shots.HOLD
end

local function pinShot(phase: string): Shot
	local e, l = Shots.PIN_EYE, Shots.PIN_LOOK
	return { ex = e.x, ey = e.y, ed = e.d, lx = l.x, ly = l.y, ld = l.d, fov = 42, phase = phase }
end

-- The shot t seconds into a throw.
function Shots.roll(script: RollScript.Script, t: number): Shot
	if t >= Shots.doneTime(script) then
		return pinShot("done")
	end
	local bx, by, bd = RollScript.ball(script, math.max(0, t))
	if bx == nil or t >= Shots.cutTime(script) then
		return pinShot("pins")
	end
	-- riding behind the ball, never ahead of it and never back through the bowler
	local ed = math.max(bd - Shots.FOLLOW_BACK, -12.5)
	return {
		ex = bx * 0.6,
		ey = math.max(by, 0) + Shots.FOLLOW_UP,
		ed = ed,
		lx = bx,
		ly = 0.5,
		ld = bd + 12,
		fov = 55,
		phase = "follow",
	}
end

return Shots
