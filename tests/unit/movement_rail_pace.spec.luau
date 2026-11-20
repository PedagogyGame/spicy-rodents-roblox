--!strict
-- Owner D19 (docs/spec/BRIEF_ADDENDUM.md): chains along a rail and climbs up a trunk at a balanced, fun pace. The motor's
-- own sustained paces at 60 fps, W and sprint held, along the river bridge's parapet (1075) and the avenue cable (660)
-- and up the town's tallest trunk (604): Space held (leap, caught by the rail, leap again) and E+Space every 6 frames (a
-- person), 4, 3 and 2 (a macro), in the bands the lead set (along a rail 24-32 st/s, up a trunk 24-28), a macro no
-- faster than a person; plain running unchanged; a leap from rest or after a moment on the rail a full one.
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local TestWorld = require("@tests/cheat/TestWorld")

local P = SquirrelMotor.params

return function(t)
	local tw = TestWorld.build({ boxes = {} })
	local reg = tw.registry

	local function heading(id: number, t0: number): number
		local r = reg:get(id)
		local a, b = reg:pointAt(r, t0), reg:pointAt(r, math.min(1, t0 + 0.05))
		return math.atan2(-(b.x - a.x), -(b.z - a.z))
	end

	-- the pace from t1 to t2 s: along the rail's first heading, or up; mode "walk", "sprint", "space" or "e<k>"
	local function pace(id: number, t0: number, yaw: number, mode: string, t1: number, t2: number, up: boolean): number
		local r = reg:get(id)
		local p = reg:pointAt(r, t0)
		local s = SquirrelMotor.new(p.x, p.y, p.z)
		s.routeId, s.railT, s.grounded, s.clock, s.yaw = id, t0, false, 0, yaw
		local x0, y0, z0 = s.x, s.y, s.z
		local fx, fz = -math.sin(yaw), -math.cos(yaw)
		local function gone(): number
			return if up then s.y - y0 else (s.x - x0) * fx + (s.z - z0) * fz
		end
		local every = tonumber(string.sub(mode, 2)) or 0
		local g1 = 0
		for f = 1, math.floor(t2 * 60 + 0.5) do
			local i = SquirrelMotor.idleInput(yaw)
			i.fw, i.sprint = 1, mode ~= "walk"
			if mode == "space" then
				i.leap = true
			elseif every > 0 then
				i.leap = s.routeId ~= nil or (not s.grounded and f % every == 0)
				i.grab = not s.grounded and s.routeId == nil and f % every == 0
			end
			SquirrelMotor.step(s, i, 1 / 60, tw)
			if f == math.floor(t1 * 60 + 0.5) then
				g1 = gone()
			end
		end
		return (gone() - g1) / (t2 - t1)
	end

	t.test("chains along a rail: 24-32 st/s, a macro no faster than a person, plain running unchanged", function()
		for _, id in { 1075, 660 } do
			local yaw = heading(id, 0.02)
			local function at(mode: string): number
				return pace(id, 0.02, yaw, mode, 1, 9, false)
			end
			local person = at("e6")
			local row = {}
			for _, mode in { "space", "e6", "e4", "e3", "e2" } do
				local v = at(mode)
				table.insert(row, string.format("%s %.1f", mode, v))
				t.truthy(v >= 24 and v <= 32, `route {id}, {mode}: {v} st/s in 24-32`)
				if mode ~= "space" then
					t.truthy(v <= person * 1.05, `route {id}, {mode}: {v} st/s no faster than a person's {person}`)
				end
			end
			local walk, sprint = at("walk"), at("sprint")
			print(
				`      route {id}: {table.concat(row, ", ")}; walk {string.format("%.1f", walk)}, sprint {string.format(
					"%.1f",
					sprint
				)} st/s`
			)
			t.truthy(walk >= 17 and walk <= 18.5, `route {id}: the walk along it as before ({walk})`)
			t.truthy(sprint <= 32, `route {id}: the run along it under the chains' band top ({sprint})`)
		end
	end)

	t.test("up a trunk: 24-28 st/s at every E+Space rhythm", function()
		local r = reg:get(604)
		local t0 = if reg:pointAt(r, 0).y < reg:pointAt(r, 1).y then 0.02 else 0.98
		local row = {}
		for _, mode in { "e6", "e4", "e3", "e2" } do
			local v = pace(604, t0, 0, mode, 0, 2.5, true)
			table.insert(row, string.format("%s %.1f", mode, v))
			t.truthy(v >= 24 and v <= 28, `trunk 604, {mode}: {v} st/s in 24-28`)
		end
		print(`      trunk 604 up: {table.concat(row, ", ")} st/s`)
	end)

	t.test(
		"a leap from rest, or after chainRest on the rail, is a full one; one off the next rail at once is chained",
		function()
			local id = 660
			local yaw = heading(id, 0.3)
			local p = reg:pointAt(reg:get(id), 0.3)
			local s = SquirrelMotor.new(p.x, p.y, p.z)
			s.routeId, s.railT, s.grounded, s.clock, s.yaw = id, 0.3, false, 0, yaw
			local function leap(): number
				-- (no keys but Space: the leap's own carry, the air's drag one frame)
				local i = SquirrelMotor.idleInput(yaw)
				i.leap = true
				SquirrelMotor.step(s, i, 1 / 60, tw)
				return math.sqrt(s.vx * s.vx + s.vz * s.vz)
			end
			local full = leap()
			t.truthy(full >= P.leapForward * 0.95, `a leap from rest: {full} st/s`)
			-- (back onto the cable from that flight, then at once off again)
			local grabbed = false
			for _ = 1, 30 do
				local i = SquirrelMotor.idleInput(yaw)
				i.fw, i.sprint = 1, true
				i.grab = not grabbed and s.routeId == nil and s.railLeapWait <= 0
				SquirrelMotor.step(s, i, 1 / 60, tw)
				if s.routeId ~= nil then
					grabbed = true
					break
				end
			end
			t.truthy(grabbed, "caught the cable again")
			local chained = leap()
			t.truthy(
				chained <= P.leapForward * P.chainCarry * 1.05,
				`a leap off the next rail at once: {chained} st/s (chained {P.leapForward * P.chainCarry})`
			)
			-- (and again after chainRest on the rail: a full one)
			grabbed = false
			for _ = 1, 30 do
				local i = SquirrelMotor.idleInput(yaw)
				i.fw, i.sprint = 1, true
				i.grab = not grabbed and s.routeId == nil and s.railLeapWait <= 0
				SquirrelMotor.step(s, i, 1 / 60, tw)
				if s.routeId ~= nil then
					grabbed = true
					break
				end
			end
			t.truthy(grabbed, "caught the cable a second time")
			for _ = 1, math.ceil(P.chainRest * 60) + 1 do
				SquirrelMotor.step(s, SquirrelMotor.idleInput(yaw), 1 / 60, tw)
			end
			local rested = leap()
			t.truthy(rested >= P.leapForward * 0.95, `a leap after chainRest on the rail: {rested} st/s`)
		end
	)
end
