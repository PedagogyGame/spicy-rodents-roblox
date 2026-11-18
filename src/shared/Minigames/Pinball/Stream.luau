--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Stream
-- What a client draws a pinball machine from (as bowling's RollScript is what it draws a roll from). The model
-- ticks 240 times a second; a screen shows 60. read() takes one Frame out of a machine: where each ball is,
-- how far each flipper is up, which drop targets are down, how the spinners stand, how far the plunger is
-- pulled, every lamp, the display. A frame is all a drawer needs; it never reads the machine itself.
--   * The player's own machine and a watcher's replay both call read() once per screen frame.
--   * blend() gives the frame between two frames, for a drawer that is fed frames slower than it draws.
--   * pack() squeezes a frame into a short list of whole numbers and unpack() opens it again (positions to a
--     thousandth of a stud), for anyone who is sent frames and does not run the model (the backglass of a
--     machine far across the room, a spectator who walked up mid-ball and has no log to replay yet).
-- The cues (sounds, callouts) are the other half of the stream: Machine.step appends them to its out list.
-- Pure; Lune-tested (tests/unit/pinball_replay.spec.luau).
-- Interface: read(table, machine, into?) -> Frame; blend(a, b, alpha, into?) -> Frame;
--   pack(table, frame) -> { number }; unpack(table, packed, into?) -> Frame;
--   ballAt(frame, i) -> (across, up, along) in the cabinet's own frame (Layout.cabinetPoint)

local Layout = require("./Layout")
local Machine = require("./Machine")
local Physics = require("./Physics")

local Stream = {}

export type Frame = {
	tick: number,
	phase: number, -- Machine.PHASE
	up: number,
	ball: number,
	scores: { number },
	nBalls: number,
	balls: { number }, -- x, y, h for each ball that is on the table (playfield studs)
	flippers: { number }, -- radians, per flipper
	drops: { boolean }, -- per target number: a drop target that is down
	spin: { number }, -- per spinner: the fraction of a turn it stands at
	pull: number, -- the plunger, 0..1
	lamps: { number }, -- 0 dark, 1 lit, 2 flashing
	say: number, -- the callout on the display (0: none)
	sayValue: number,
	saveOn: boolean,
	tilted: boolean,
	bob: number, -- the tilt bob's swing, 0..Machine.BOB_LIMIT
}

local function blank(): Frame
	return {
		tick = 0,
		phase = Machine.PHASE.PLAY,
		up = 1,
		ball = 1,
		scores = {},
		nBalls = 0,
		balls = {},
		flippers = {},
		drops = {},
		spin = {},
		pull = 0,
		lamps = {},
		say = 0,
		sayValue = 0,
		saveOn = false,
		tilted = false,
		bob = 0,
	}
end

function Stream.read(tbl: Machine.Table, m: Machine.State, into: Frame?): Frame
	local f = into or blank()
	local phys = m.phys
	local c = tbl.c
	f.tick = phys.tick
	f.phase = m.phase
	f.up = m.up
	f.ball = m.ball
	for i = 1, m.players do
		f.scores[i] = m.scores[i]
	end
	local n = 0
	for _, b in phys.balls do
		if b.mode ~= Physics.GONE then
			f.balls[n * 3 + 1] = b.x
			f.balls[n * 3 + 2] = b.y
			f.balls[n * 3 + 3] = b.z
			n += 1
		end
	end
	for i = #f.balls, n * 3 + 1, -1 do
		f.balls[i] = nil
	end
	f.nBalls = n
	for i = 1, c.nFlip do
		f.flippers[i] = phys.fa[i]
	end
	for i = 1, #tbl.def.targets do
		f.drops[i] = phys.drop[i] == true
	end
	for k, id in c.spinners do
		f.spin[k] = phys.spinA[id]
	end
	f.pull = m.pull / tbl.def.plunger.pullTicks
	Machine.lamps(tbl, m, f.lamps)
	f.say = if m.sayLeft > 0 or m.phase == Machine.PHASE.OVER then m.say else 0
	f.sayValue = m.sayValue
	f.saveOn = m.saveLeft > 0
	f.tilted = m.tilted
	f.bob = m.bob
	return f
end

-- blend(a, b, alpha, into): the frame a share alpha of the way from a to b. What moves is blended (balls
-- that are in both frames, flippers, the plunger, the spinners the short way round); the rest is b's.
function Stream.blend(a: Frame, b: Frame, alpha: number, into: Frame?): Frame
	local f = into or blank()
	f.tick, f.phase, f.up, f.ball = b.tick, b.phase, b.up, b.ball
	f.say, f.sayValue, f.saveOn, f.tilted = b.say, b.sayValue, b.saveOn, b.tilted
	f.nBalls = b.nBalls
	for i = 1, #b.scores do
		f.scores[i] = b.scores[i]
	end
	local same = a.nBalls == b.nBalls
	for k = 0, b.nBalls - 1 do
		-- a ball that jumped (fed to the plunger, kicked off a ramp's end) is not slid across the table; the
		-- others are blended all the same (each ball is judged by itself)
		local i = k * 3 + 1
		local slide = same
		if slide then
			local dx = b.balls[i] - a.balls[i]
			local dy = b.balls[i + 1] - a.balls[i + 1]
			slide = dx * dx + dy * dy <= 0.25
		end
		for j = i, i + 2 do
			local to = b.balls[j]
			local from = if slide then a.balls[j] else to
			f.balls[j] = from + (to - from) * alpha
		end
	end

	for i = #f.balls, b.nBalls * 3 + 1, -1 do
		f.balls[i] = nil
	end
	for i = 1, #b.flippers do
		local from = a.flippers[i] or b.flippers[i]
		f.flippers[i] = from + (b.flippers[i] - from) * alpha
	end
	for i = 1, #b.drops do
		f.drops[i] = b.drops[i]
	end
	for i = 1, #b.spin do
		local from = a.spin[i] or b.spin[i]
		local d = b.spin[i] - from
		if d > 0.5 then
			d -= 1
		elseif d < -0.5 then
			d += 1
		end
		f.spin[i] = (from + d * alpha) % 1
	end
	f.pull = a.pull + (b.pull - a.pull) * alpha
	f.bob = a.bob + (b.bob - a.bob) * alpha
	for i = 1, #b.lamps do
		f.lamps[i] = b.lamps[i]
	end
	return f
end

local LAMPS_PER_NUMBER = 20 -- three states each: 3^20 fits a whole number easily

local function round(v: number): number
	return math.floor(v + 0.5)
end

-- pack(table, frame): whole numbers only. Layout: tick, flags (phase, save, tilt), up, ball, say, sayValue,
-- pull (0..255), bob (0..255), ball count, then x, y, h per ball in thousandths; then per flipper its angle in
-- ten-thousandths of a radian above -pi; then the drop targets as bits; the spinners in 1/256 turns; the lamps
-- twenty to a number in base three; the scores.
function Stream.pack(tbl: Machine.Table, f: Frame): { number }
	local out: { number } = {
		f.tick,
		f.phase + (if f.saveOn then 4 else 0) + (if f.tilted then 8 else 0),
		f.up,
		f.ball,
		f.say,
		f.sayValue,
		round(math.clamp(f.pull, 0, 1) * 255),
		round(math.clamp(f.bob / Machine.BOB_LIMIT, 0, 1) * 255),
		f.nBalls,
	}
	for i = 1, f.nBalls * 3 do
		table.insert(out, round(f.balls[i] * 1000))
	end
	for i = 1, tbl.c.nFlip do
		table.insert(out, round((f.flippers[i] + math.pi) * 10000))
	end
	local bits = 0
	for i = #tbl.def.targets, 1, -1 do
		bits = bits * 2 + (if f.drops[i] then 1 else 0)
	end
	table.insert(out, bits)
	for k = 1, #tbl.c.spinners do
		table.insert(out, round((f.spin[k] or 0) * 256) % 256)
	end
	local nLamps = #tbl.def.lamps
	for first = 1, nLamps, LAMPS_PER_NUMBER do
		local v = 0
		for i = math.min(first + LAMPS_PER_NUMBER - 1, nLamps), first, -1 do
			v = v * 3 + (f.lamps[i] or 0)
		end
		table.insert(out, v)
	end
	for i = 1, #f.scores do
		table.insert(out, f.scores[i])
	end
	return out
end

function Stream.unpack(tbl: Machine.Table, p: { number }, into: Frame?): Frame
	local f = into or blank()
	f.tick = p[1]
	local flags = p[2]
	f.phase = flags % 4
	f.saveOn = flags % 8 >= 4
	f.tilted = flags % 16 >= 8
	f.up, f.ball, f.say, f.sayValue = p[3], p[4], p[5], p[6]
	f.pull = p[7] / 255
	f.bob = p[8] / 255 * Machine.BOB_LIMIT
	f.nBalls = p[9]
	local at = 9
	for i = 1, f.nBalls * 3 do
		at += 1
		f.balls[i] = p[at] / 1000
	end
	for i = #f.balls, f.nBalls * 3 + 1, -1 do
		f.balls[i] = nil
	end
	for i = 1, tbl.c.nFlip do
		at += 1
		f.flippers[i] = p[at] / 10000 - math.pi
	end
	at += 1
	local bits = p[at]
	for i = 1, #tbl.def.targets do
		f.drops[i] = bits % 2 == 1
		bits //= 2
	end
	for k = 1, #tbl.c.spinners do
		at += 1
		f.spin[k] = p[at] / 256
	end
	local nLamps = #tbl.def.lamps
	for first = 1, nLamps, LAMPS_PER_NUMBER do
		at += 1
		local v = p[at]
		for i = first, math.min(first + LAMPS_PER_NUMBER - 1, nLamps) do
			f.lamps[i] = v % 3
			v //= 3
		end
	end
	local seat = 0
	for i = at + 1, #p do
		seat += 1
		f.scores[seat] = p[i]
	end
	return f
end

-- ballAt(frame, i): ball i in the cabinet's own frame, for the part that draws it.
function Stream.ballAt(f: Frame, i: number): (number, number, number)
	local k = (i - 1) * 3
	return Layout.cabinetPoint(f.balls[k + 1], f.balls[k + 2], f.balls[k + 3] + Layout.BALL_R)
end

return Stream
