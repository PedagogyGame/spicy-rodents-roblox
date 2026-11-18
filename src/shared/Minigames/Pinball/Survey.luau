--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Survey
-- A table surveyed for dead spots (checklist PIN-P3 "never sticks or jitters in a corner"). A pinball playfield
-- must have nowhere a ball can come to rest by itself: with the flippers down, a ball let go anywhere it can
-- get to has to roll on and drain. A notch where a post stands on the end of a gentle wall, a pocket behind a
-- ramp, a step where a guide meets a flipper: each of those holds a ball that arrives with no speed left, and
-- the player then waits for the machine's ball search. This module finds them, so the tables are laid out by
-- measurement (tools/games/pinball/calibrate.luau prints the count) and held to it (the specs demand none).
--   * reachable(): every spot a ball's centre can get to from the middle of the table, on a grid: a flood
--     fill over the places where the ball overlaps no wall, post, target or bumper. (The space behind a
--     target bank or inside a slingshot is closed and is not reached.) The fill itself walks a grid twice as
--     fine as the one it reports, so it finds its way down every lane a ball can roll into (a lane 1.4 balls
--     across leaves the ball's centre a corridor of a twentieth of a stud); the spots it reports are every
--     other one, GRID apart.
--   * drop(): a ball let go at one spot on a live table with nobody at the buttons: it drains, or comes to
--     rest (a dead spot), or is still moving after the time allowed (batted round a loop for ever).
--   * rests(): drop() from every nth reachable spot outside the shooter lane (a ball does rest on the plunger).
-- Pure; Lune-tested (tests/unit/pinball_pockets.spec.luau).
-- Interface: GRID; free(table, x, y) -> boolean (a ball centred here overlaps nothing solid);
--   reachable(table, grid?) -> { number } (x, y pairs); drop(table, x, y, vx, seconds) ->
--   ("drained" | "rest" | "moving", x, y, ticks); rests(table, every?, seconds?) -> Report

local Layout = require("./Layout")
local Machine = require("./Machine")
local Physics = require("./Physics")

local Survey = {}

Survey.GRID = 0.04 -- studs between surveyed spots
Survey.SECONDS = 40 -- a ball that has not drained from anywhere in this long is going round for ever
Survey.OFFSET = 0.0037 -- the grid is laid a hair off the round numbers a table is drawn on (the crown of a post is an exact balance)

export type Report = {
	spots: number, -- reachable spots on the grid
	tried: number,
	drained: number,
	rest: { number }, -- x, y pairs: where a ball came to rest by itself
	moving: { number }, -- x, y pairs: where a ball was let go that never drained and never rested
	slowest: number, -- seconds the slowest drain took
}

local R = Layout.BALL_R

-- does a ball centred here overlap nothing that is solid?
local function clear(c: Layout.Compiled, x: number, y: number): boolean
	for i = 1, c.nSeg do
		if c.sKind[i] ~= Layout.SEG_GATE then
			local ax, ay, dx, dy = c.sx[i], c.sy[i], c.sdx[i], c.sdy[i]
			local t = ((x - ax) * dx + (y - ay) * dy) * c.sInv[i]
			if t < 0 then
				t = 0
			elseif t > 1 then
				t = 1
			end
			local qx, qy = x - (ax + dx * t), y - (ay + dy * t)
			if qx * qx + qy * qy < R * R then
				return false
			end
		end
	end
	for i = 1, #c.cx do
		local rr = R + c.cr[i]
		local qx, qy = x - c.cx[i], y - c.cy[i]
		if qx * qx + qy * qy < rr * rr then
			return false
		end
	end
	return true
end

-- free(table, x, y): a ball centred here overlaps nothing solid (it is a place a ball can be).
function Survey.free(tbl: Machine.Table, x: number, y: number): boolean
	return clear(tbl.c, x, y)
end

-- reachable(table, grid): the grid spots a ball's centre can get to from the middle of the playfield.
function Survey.reachable(tbl: Machine.Table, grid: number?): { number }
	local c = tbl.c
	local spacing = grid or Survey.GRID
	local g = spacing / 2 -- the fill walks twice as fine as it reports
	local w, h = math.floor(Layout.WIDTH / g), math.floor(Layout.LENGTH / g)
	local seen: { [number]: boolean } = {}
	local out: { number } = {}
	local stack = { 2 * math.floor(Layout.XC / spacing), 2 * math.floor(1.7 / spacing) }
	while #stack > 0 do
		local iy = table.remove(stack) :: number
		local ix = table.remove(stack) :: number
		local key = iy * 4096 + ix
		if seen[key] or ix < 0 or iy < 0 or ix > w or iy > h then
			continue
		end
		seen[key] = true
		local x, y = ix * g + Survey.OFFSET, iy * g + Survey.OFFSET
		if y < c.drainY + 0.1 or not clear(c, x, y) then
			continue
		end
		if ix % 2 == 0 and iy % 2 == 0 then
			table.insert(out, x)
			table.insert(out, y)
		end
		-- the four neighbours (a step is much less than a ball across, so no wall is stepped over)
		local n = #stack
		stack[n + 1], stack[n + 2] = ix + 1, iy
		stack[n + 3], stack[n + 4] = ix - 1, iy
		stack[n + 5], stack[n + 6] = ix, iy + 1
		stack[n + 7], stack[n + 8] = ix, iy - 1
	end
	return out
end

local ev: { number } = {}

-- drop(table, x, y, vx, seconds): let one ball go here, moving sideways at vx, with nobody at the buttons.
function Survey.drop(
	tbl: Machine.Table,
	x: number,
	y: number,
	vx: number,
	seconds: number?
): ("drained" | "rest" | "moving", number, number, number)
	local c = tbl.c
	local s = Physics.new(c, 1)
	Physics.addBall(s, x, y, vx, 0)
	local b = s.balls[1]
	local ticks = math.floor((seconds or Survey.SECONDS) * Physics.HZ)
	for tick = 1, ticks do
		table.clear(ev)
		Physics.step(c, s, false, false, ev)
		if b.mode == Physics.GONE then
			return "drained", b.x, b.y, tick
		elseif b.asleep then
			return "rest", b.x, b.y, tick
		end
	end
	return "moving", b.x, b.y, ticks
end

-- rests(table, every, seconds): drop a ball from every nth reachable spot of the playfield proper.
function Survey.rests(tbl: Machine.Table, every: number?, seconds: number?): Report
	local spots = Survey.reachable(tbl)
	local step = math.max(1, every or 1)
	local count = #spots // 2
	local report: Report = { spots = count, tried = 0, drained = 0, rest = {}, moving = {}, slowest = 0 }
	local laneTop = tbl.def.plunger.laneTop
	local n = 0
	for i = 1, #spots, 2 do
		local x, y = spots[i], spots[i + 1]
		if x > Layout.FIELD_X1 and y < laneTop then
			continue -- the shooter lane: a ball there rolls back onto the plunger, as it should
		end
		n += 1
		if n % step ~= 0 then
			continue
		end
		-- let go still, or with a little sideways speed either way, in turn
		local vx = (n // step % 3 - 1) * 0.7
		local what, bx, by, ticks = Survey.drop(tbl, x, y, vx, seconds)
		report.tried += 1
		if what == "drained" then
			report.drained += 1
			report.slowest = math.max(report.slowest, ticks / Physics.HZ)
		elseif what == "rest" then
			table.insert(report.rest, bx)
			table.insert(report.rest, by)
		else
			table.insert(report.moving, x)
			table.insert(report.moving, y)
		end
	end
	return report
end

return Survey
