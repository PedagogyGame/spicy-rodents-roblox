--!strict
-- ReplicatedStorage.Shared.Util.Spring
-- Critically-damped-capable scalar spring stepped in closed form (exact for any dt, so camera and HUD
-- smoothing do not depend on frame rate) (BUILD_PLAN §1.4 Util). Pure.
-- Interface: new(value, speed?, damping?) -> Spring; step(s, dt) -> value; s.target, s.value, s.velocity

export type Spring = { value: number, velocity: number, target: number, speed: number, damping: number }

local Spring = {}

function Spring.new(value: number, speed: number?, damping: number?): Spring
	return { value = value, velocity = 0, target = value, speed = speed or 10, damping = damping or 1 }
end

-- Damped harmonic oscillator x'' = -w^2 (x - target) - 2 z w x', solved analytically over dt.
function Spring.step(s: Spring, dt: number): number
	local w, z = s.speed, s.damping
	local x0 = s.value - s.target
	local v0 = s.velocity
	local x, v
	if z >= 1 - 1e-9 and z <= 1 + 1e-9 then
		local e = math.exp(-w * dt)
		local c = v0 + w * x0
		x = (x0 + c * dt) * e
		v = (c - w * (x0 + c * dt)) * e
	elseif z < 1 then
		local wd = w * math.sqrt(1 - z * z)
		local e = math.exp(-z * w * dt)
		local cs, sn = math.cos(wd * dt), math.sin(wd * dt)
		local b = (v0 + z * w * x0) / wd
		x = e * (x0 * cs + b * sn)
		v = e * ((-z * w) * (x0 * cs + b * sn) + (-x0 * wd * sn + b * wd * cs))
	else
		local r = w * math.sqrt(z * z - 1)
		local r1, r2 = -z * w + r, -z * w - r
		local c2 = (v0 - r1 * x0) / (r2 - r1)
		local c1 = x0 - c2
		local e1, e2 = math.exp(r1 * dt), math.exp(r2 * dt)
		x = c1 * e1 + c2 * e2
		v = c1 * r1 * e1 + c2 * r2 * e2
	end
	s.value = s.target + x
	s.velocity = v
	return s.value
end

return Spring
