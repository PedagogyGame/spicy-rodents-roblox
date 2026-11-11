--!strict
-- ReplicatedStorage.Shared.Minigames.Pool.Cue
-- The cue: what a player (or a computer player) gives, and the strike it makes. A shot is four numbers:
--   angle  radians round the ball, 0 pointing up the table (+z, to the foot end), positive toward +x
--   power  0..1, the share of the hold (it rises once: a soft shot is chosen on purpose)
--   tipX   -1..1, where the tip meets the ball, left to right as the shooter sees it (side spin)
--   tipY   -1..1, bottom to top (draw to follow)
-- The tip can reach TIP_MAX of a radius from the centre (beyond that a real tip slips off); a tip offset is
-- clamped to that circle. The strike is what a level cue does to a ball: speed along the aim, roll of
-- 2.5 x height (0.4 of a radius up is a natural roll, the centre is a stun shot, below it is draw) and side
-- spin of 2.5 x offset. Inside the SURE band the ball goes exactly where it was aimed; above it (a smash)
-- the delivery wanders by a small seeded error, so the hardest shots are a little wild (POOL-P9).
-- preview() is the aim line: it runs the SAME table model up to the first thing the ball meets and a
-- moment past it, so the ghost ball, the object ball's line and the cue ball's line (which bends with
-- follow and draw) are what the shot will really do; the lines are short, so potting stays a skill.
-- Pure; Lune-tested (tests/unit/pool_cue.spec.luau).
-- Interface: constants; speed(power) -> studs/s; powerFor(speed) -> power; clampTip(x, y) -> (x, y);
--   strike(id, angle, power, tipX, tipY, seed?) -> Shot.Strike; preview(table, spots, id, angle, power,
--   tipX, tipY) -> Preview; dirOf(angle) -> (x, z); angleOf(x, z) -> angle

local Physics = require("./Physics")
local Rng = require("../../Util/Rng")
local Shot = require("./Shot")
local Tables = require("./Tables")

local Cue = {}

Cue.MIN_SPEED = 0.8 -- studs/s: the softest touch
Cue.MAX_SPEED = 46 -- studs/s: a full break (17 mph at this table's scale)
Cue.CURVE = 1.5 -- speed rises as power ^ CURVE: half the hold is a third of the speed
Cue.TIP_MAX = 0.5 -- of a radius
Cue.SURE = 0.9 -- up to this power the delivery is exact
Cue.WILD_ANGLE = 0.0105 -- radians (0.6 degrees): the most a full smash strays
Cue.WILD_TIP = 0.12 -- and how far the tip can land from where it was aimed
Cue.PREVIEW_T = 12 -- seconds the preview follows a ball that meets nothing
Cue.PREVIEW_AFTER = 0.3 -- seconds past the first contact
Cue.PREVIEW_POINTS = 6 -- places on the cue ball's line after the contact

export type Preview = {
	kind: "ball" | "cushion" | "post" | "hole" | "none",
	t: number, -- seconds to the first contact
	gx: number, -- the ghost ball: where the struck ball is when it first meets something
	gz: number,
	target: number, -- the ball it meets (kind "ball"), else -1
	ox: number, -- the object ball's line (unit; 0, 0 when there is none)
	oz: number,
	speed: number, -- the object ball's speed off the contact
	path: { number }, -- flat x, z: the struck ball's own line after the contact
}

function Cue.speed(power: number): number
	local p = math.clamp(power, 0, 1)
	return Cue.MIN_SPEED + (Cue.MAX_SPEED - Cue.MIN_SPEED) * p ^ Cue.CURVE
end

function Cue.powerFor(speed: number): number
	local f = (speed - Cue.MIN_SPEED) / (Cue.MAX_SPEED - Cue.MIN_SPEED)
	return math.clamp(f, 0, 1) ^ (1 / Cue.CURVE)
end

function Cue.clampTip(x: number, y: number): (number, number)
	if x ~= x or y ~= y then
		return 0, 0
	end
	local d = math.sqrt(x * x + y * y)
	if d > 1 then
		return x / d, y / d
	end
	return x, y
end

function Cue.dirOf(angle: number): (number, number)
	return math.sin(angle), math.cos(angle)
end

function Cue.angleOf(x: number, z: number): number
	return math.atan2(x, z)
end

-- The strike a cue makes. `seed` matters only above the SURE band.
function Cue.strike(id: number, angle: number, power: number, tipX: number, tipY: number, seed: number?): Shot.Strike
	local p = math.clamp(power, 0, 1)
	local tx, ty = Cue.clampTip(tipX, tipY)
	if p > Cue.SURE and seed ~= nil then
		local rng = Rng.new(seed)
		local wild = (p - Cue.SURE) / (1 - Cue.SURE)
		-- two draws each: small errors are common, the full error is rare
		angle += wild * Cue.WILD_ANGLE * 0.5 * (rng.range(-1, 1) + rng.range(-1, 1))
		tx += wild * Cue.WILD_TIP * 0.5 * (rng.range(-1, 1) + rng.range(-1, 1))
		ty += wild * Cue.WILD_TIP * 0.5 * (rng.range(-1, 1) + rng.range(-1, 1))
		tx, ty = Cue.clampTip(tx, ty)
	end
	local v = Cue.speed(p)
	local dx, dz = Cue.dirOf(angle)
	local roll = 2.5 * Cue.TIP_MAX * ty * v
	return {
		id = id,
		vx = v * dx,
		vz = v * dz,
		qx = roll * dx,
		qz = roll * dz,
		s = 2.5 * Cue.TIP_MAX * tx * v,
	}
end

local EV = Physics.EV
local ES = Physics.EVENT_STRIDE
local KS = Physics.KEY_STRIDE

-- The aim line for a shot, from the same model that will play it.
function Cue.preview(
	tb: Tables.Table,
	spots: { Tables.Spot },
	id: number,
	angle: number,
	power: number,
	tipX: number,
	tipY: number
): Preview
	local w = Physics.world(tb, spots)
	local st = Cue.strike(id, angle, power, tipX, tipY, nil)
	Physics.strike(w, id, st.vx, st.vz, st.qx, st.qz, st.s)
	local me = 0
	for i, b in w.balls do
		if b.id == id then
			me = i
		end
	end
	local ball = w.balls[me]
	local out: Preview = {
		kind = "none",
		t = 0,
		gx = ball.x,
		gz = ball.z,
		target = -1,
		ox = 0,
		oz = 0,
		speed = 0,
		path = {},
	}
	local ev = w.events
	local seen = 0
	local hitAt = -1
	local moving = true
	while moving and w.t < Cue.PREVIEW_T do
		moving = Physics.step(w)
		while hitAt < 0 and seen < #ev do
			local t, kind, a, b = ev[seen + 1], ev[seen + 2], ev[seen + 3], ev[seen + 4]
			seen += ES
			local mine = a == id or (kind == EV.ball and b == id)
			if mine and kind ~= EV.drop then
				hitAt = t
				out.t = t
				out.kind = if kind == EV.ball
					then "ball"
					elseif kind == EV.cushion or kind == EV.jaw then "cushion"
					elseif kind == EV.post then "post"
					else "hole"
				-- the struck ball's key point at that moment is the ghost ball
				local k = w.keys[me]
				for o = #k - KS + 1, 1, -KS do
					if k[o] <= t then
						out.gx, out.gz = k[o + 1], k[o + 2]
						break
					end
				end
				if kind == EV.ball then
					local other = if a == id then b else a
					out.target = other
					for j, ob in w.balls do
						if ob.id == other then
							local ko = w.keys[j]
							for o = #ko - KS + 1, 1, -KS do
								if ko[o] <= t then
									local vx, vz = ko[o + 3], ko[o + 4]
									local sp = math.sqrt(vx * vx + vz * vz)
									if sp > 0 then
										out.ox, out.oz, out.speed = vx / sp, vz / sp, sp
									end
									break
								end
							end
						end
					end
				end
			end
		end
		if hitAt >= 0 then
			-- a few places on the struck ball's own line after the contact
			local every = Cue.PREVIEW_AFTER / Cue.PREVIEW_POINTS
			if w.t >= hitAt + every * (#out.path / 2 + 1) then
				table.insert(out.path, ball.x)
				table.insert(out.path, ball.z)
			end
			if #out.path >= Cue.PREVIEW_POINTS * 2 or ball.mode ~= 1 then
				break
			end
		end
	end
	if hitAt < 0 then
		out.t = w.t
		out.gx, out.gz = ball.x, ball.z
	end
	return out
end

return Cue
