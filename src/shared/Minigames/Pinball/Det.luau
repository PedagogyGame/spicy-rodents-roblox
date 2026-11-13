--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Det
-- Sine and cosine that give the SAME bits on every machine. The pinball model runs live on the player's
-- machine and is replayed by the server from the input log (checklist PIN-P6, C1), so every operation in it
-- must round identically everywhere: + - * / and sqrt do (IEEE 754), the C library's sin and cos do not. These
-- two are built from + - * / and floor alone: the angle is folded to within a quarter turn and a fixed Taylor
-- polynomial is evaluated in a fixed order. They agree with math.sin and math.cos to about 1e-15 for the
-- angles a pinball table uses (a few turns at most).
-- Pure; Lune-tested (tests/unit/pinball_physics.spec.luau).
-- Interface: sin(x), cos(x), PI, HALF_PI, rad(degrees)

local Det = {}

Det.PI = 3.141592653589793
Det.HALF_PI = 1.5707963267948966

local HALF_PI = Det.HALF_PI

local function sinPoly(r: number): number
	local r2 = r * r
	local p = 1 - r2 / 210
	p = 1 - r2 / 156 * p
	p = 1 - r2 / 110 * p
	p = 1 - r2 / 72 * p
	p = 1 - r2 / 42 * p
	p = 1 - r2 / 20 * p
	p = 1 - r2 / 6 * p
	return r * p
end

local function cosPoly(r: number): number
	local r2 = r * r
	local p = 1 - r2 / 182
	p = 1 - r2 / 132 * p
	p = 1 - r2 / 90 * p
	p = 1 - r2 / 56 * p
	p = 1 - r2 / 30 * p
	p = 1 - r2 / 12 * p
	return 1 - r2 / 2 * p
end

function Det.sin(x: number): number
	local k = math.floor(x / HALF_PI + 0.5)
	local r = x - k * HALF_PI
	local q = k % 4
	if q == 0 then
		return sinPoly(r)
	elseif q == 1 then
		return cosPoly(r)
	elseif q == 2 then
		return -sinPoly(r)
	end
	return -cosPoly(r)
end

function Det.cos(x: number): number
	local k = math.floor(x / HALF_PI + 0.5)
	local r = x - k * HALF_PI
	local q = k % 4
	if q == 0 then
		return cosPoly(r)
	elseif q == 1 then
		return -sinPoly(r)
	elseif q == 2 then
		return -cosPoly(r)
	end
	return sinPoly(r)
end

function Det.rad(degrees: number): number
	return degrees * Det.PI / 180
end

return Det
