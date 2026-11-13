--!strict
-- ReplicatedStorage.Shared.Minigames.Pool.Cloth
-- One ball alone on the cloth, in closed form. A ball carries its place (x, z), its velocity v, its ROLL q
-- (the velocity its spin about the level axes is rolling it toward: a ball rolling naturally has q = v, a
-- stunned ball has q = 0, a drawn ball has q pointing back at the cue) and its SIDE spin s (the speed of its
-- equator, positive counter-clockwise seen from above with x to the right and z up the page: right-hand
-- english). While v and q differ the ball SLIDES: the cloth pushes against the slip u = v - q with a constant
-- force, so v changes by -A_SLIDE and q by +2.5 A_SLIDE along the slip until they meet (after
-- |u| / 3.5 A_SLIDE seconds, at v = (5 v + 2 q) / 7). That one rule is follow, draw, stun and the curve of a
-- cue ball after a cut. Then it ROLLS straight and slows at A_ROLL until it stops; it never stops dead and
-- never creeps. Side spin dies at A_SPIN on its own. A ball over a hole (mode 2) is in the air: it keeps its
-- velocity and falls.
-- advance() uses only + - * / and sqrt, so the same call gives the same bytes on every machine, and it is
-- exact for any dt: stepping a ball in pieces and in one go agree, which is why a shot's script can store a
-- ball's state only when something hits it (Shot) and still be drawn at any frame rate.
-- Pure; Lune-tested (tests/unit/pool_cloth.spec.luau).
-- Interface: constants; Ball; new(id, x, z) -> Ball; copy(b) -> Ball; advance(b, dt); energy(b) -> number;
--   rollDistance(v) -> studs a rolling ball travels before it stops; speedFor(distance) -> the rolling speed
--   that travels it; REST / CLOTH / AIR / DOWN / OFF (modes)

local Cloth = {}

Cloth.G = 58.4 -- studs/s^2: gravity at this table's scale (a 0.17 stud ball is a 2.25 inch ball)
Cloth.A_SLIDE = 11.7 -- studs/s^2: a sliding ball (cloth friction 0.2)
Cloth.A_ROLL = 0.9 -- studs/s^2: a rolling ball (a slow bar cloth: a table-length roll takes about 5 s)
Cloth.A_SPIN = 3.2 -- studs/s^2: side spin dying on the cloth

Cloth.REST = 0
Cloth.CLOTH = 1
Cloth.AIR = 2 -- over a pocket or a cup, falling
Cloth.DOWN = 3 -- pocketed
Cloth.OFF = 4 -- not on the table this shot

export type Ball = {
	id: number,
	x: number,
	z: number,
	vx: number,
	vz: number,
	qx: number,
	qz: number,
	s: number,
	y: number, -- 0 on the cloth; negative while falling into a hole
	mode: number,
	hole: number, -- the hole it is over or down (0: none)
}

function Cloth.new(id: number, x: number, z: number): Ball
	return { id = id, x = x, z = z, vx = 0, vz = 0, qx = 0, qz = 0, s = 0, y = 0, mode = 0, hole = 0 }
end

function Cloth.copy(b: Ball): Ball
	return table.clone(b)
end

local A_SLIDE, A_ROLL, A_SPIN, G = Cloth.A_SLIDE, Cloth.A_ROLL, Cloth.A_SPIN, Cloth.G
local SLIP_EPS = 1e-9

-- Move one ball dt seconds on with nothing in its way.
function Cloth.advance(b: Ball, dt: number)
	local mode = b.mode
	if mode == 2 then
		-- in the air over a hole: it left the rim with no downward speed, so its fall is free fall from there
		b.x += b.vx * dt
		b.z += b.vz * dt
		local vy = math.sqrt(-2 * G * b.y)
		b.y -= vy * dt + 0.5 * G * dt * dt
		return
	elseif mode ~= 1 then
		return
	end
	local s = b.s
	if s > 0 then
		s -= A_SPIN * dt
		b.s = if s < 0 then 0 else s
	elseif s < 0 then
		s += A_SPIN * dt
		b.s = if s > 0 then 0 else s
	end
	local vx, vz = b.vx, b.vz
	local ux, uz = vx - b.qx, vz - b.qz
	local u = math.sqrt(ux * ux + uz * uz)
	if u > SLIP_EPS then
		local tau = u / (3.5 * A_SLIDE)
		local h = if dt < tau then dt else tau
		local ax, az = -A_SLIDE * ux / u, -A_SLIDE * uz / u
		b.x += vx * h + 0.5 * ax * h * h
		b.z += vz * h + 0.5 * az * h * h
		vx += ax * h
		vz += az * h
		if dt < tau then
			b.vx, b.vz = vx, vz
			b.qx -= 2.5 * ax * h
			b.qz -= 2.5 * az * h
			return
		end
		dt -= h
	end
	-- rolling
	b.qx, b.qz = vx, vz
	local v = math.sqrt(vx * vx + vz * vz)
	if v <= 0 then
		b.vx, b.vz = 0, 0
		b.mode = 0
		b.s = 0
		return
	end
	local stop = v / A_ROLL
	if dt >= stop then
		local dist = 0.5 * v * stop
		b.x += dist * vx / v
		b.z += dist * vz / v
		b.vx, b.vz, b.qx, b.qz = 0, 0, 0, 0
		b.mode = 0
		b.s = 0
		return
	end
	local dist = v * dt - 0.5 * A_ROLL * dt * dt
	local k = (v - A_ROLL * dt) / v
	b.x += dist * vx / v
	b.z += dist * vz / v
	vx *= k
	vz *= k
	b.vx, b.vz, b.qx, b.qz = vx, vz, vx, vz
end

-- Kinetic energy per unit mass: 1/2 v^2 for the motion and 1/5 (q^2 + s^2) for the spin of a solid ball.
function Cloth.energy(b: Ball): number
	if b.mode ~= 1 and b.mode ~= 2 then
		return 0
	end
	return 0.5 * (b.vx * b.vx + b.vz * b.vz) + 0.2 * (b.qx * b.qx + b.qz * b.qz + b.s * b.s)
end

function Cloth.rollDistance(v: number): number
	return v * v / (2 * A_ROLL)
end

function Cloth.speedFor(distance: number): number
	return math.sqrt(2 * A_ROLL * math.max(distance, 0))
end

return Cloth
