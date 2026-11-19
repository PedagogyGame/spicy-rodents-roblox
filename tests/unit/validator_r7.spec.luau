--!strict
-- Validator round 7 (the round-6 review's findings, fixed; invariant C), with greedy attack cases for every allowance
-- that changed, at 2 to 60 packets a second and client clocks x0.8 to x1.2:
--   C        invariant C: nothing the client can trigger starts the displacement governor (or the in-air timer) afresh:
--            a Reset, a hold given back, a knock, giving a body up and taking it back, a river landing all carry its
--            whole history over (MoveValidator.relocate / shift / takeOver), so a burst spent before one is still spent
--            after it
--   river    a river landing is the quay spot of a fall into the water the body could have made from the last accepted
--            place, never two in a row (Recovery.riverEntry): a greedy client claiming landings runs the quay no
--            faster than the governor's pace
--   reset    Reset (Possession.recover) at most once per 3 s, to a place a clean grounded packet stood on a floor, the
--            feet on it (MovementService.safeTarget)
--   grab     a short gap's hidden grab is the motor's own: the nearest sample, one per two motor frames (a greedy that
--            knows the rule climbs no faster than the motor's own E+Space)
--   near     the governor's "near a rail" from the server's own last place, within a quarter second of the pace
--   swing    the governor's clock swing is the base slack, never the ping-widened one
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local Recovery = require("@shared/Movement/Recovery")
local Height = require("@shared/World/Height")
local MoveValidator = require("@server/Movement/MoveValidator")
local MovementService = require("@server/Movement/MovementService")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local TestWorld = require("@tests/cheat/TestWorld")
local Driver = require("@tests/cheat/Driver")
local LiveRig = require("@tests/lib/LiveRig")

type State = SquirrelMotor.State

local S = Height.STUDS_PER_UNIT
local RIVER = Height.RIVER

local function worldWith(boxes: { TestWorld.Box }): (any, any)
	local world = TestWorld.build({ boxes = boxes })
	local function wall(ox: number, oy: number, oz: number, dx: number, _dy: number, dz: number): boolean
		return TestWorld.segmentCrossesBox(boxes, ox, oz, ox + dx, oz + dz, oy)
	end
	local function down(_ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
		local lo = oy + dy
		return lo <= 0 and oy >= 0
	end
	return world, ValidatorWorld.build(world, { wall = wall, down = down })
end

-- the envelope, the field check and the hop switched off for `fn` (the governor and the clock check judge alone)
local function alone(fn: () -> ())
	local fc, env, hop = SquirrelMotor.fieldCheck, SquirrelMotor.envelope, MoveValidator.hop
	SquirrelMotor.fieldCheck = function(_s: any, _w: any): { any }
		return {}
	end :: any
	SquirrelMotor.envelope = function(_prev: any, next: any, _dt: number, _w: any, _b: boolean): any
		return {}, false, nil, { vy = next.vy, xz = math.huge, landed = false, longWall = false }
	end :: any
	MoveValidator.hop = function(): { any }
		return {}
	end :: any
	local ok, err = pcall(fn)
	SquirrelMotor.fieldCheck, SquirrelMotor.envelope, MoveValidator.hop = fc, env, hop
	if not ok then
		error(err, 0)
	end
end

local function count(list: { { code: string } }, code: string): number
	local n = 0
	for _, v in list do
		if v.code == code then
			n += 1
		end
	end
	return n
end

local function tallest(world: any): any
	local best: any = nil
	for _, r in Driver.targetsAround(world, 0, 0, 3000) do
		if best == nil or r.length > best.length then
			best = r
		end
	end
	return best
end

-- the west quay's line at z (studs): where Recovery.riverFall puts a body that fell in from the west
local function quayX(z: number): number
	return (Height.riverCenterU(z / S) - (RIVER.halfWidth + 5)) * S
end

return function(t)
	-- C ----------------------------------------------------------------------------------------------------------------
	t.test(
		"C: a burst spent before a Reset, a hold, a knock or a retake of the body is still spent after it",
		function()
			local _, vworld = worldWith({})
			local rows = {}
			local moves: { [string]: (ms: any, x: number, now: number) -> () } = {
				reset = function(ms: any, x: number, now: number)
					ms:teleported("a", x + 40, 0.45, 0, "reset", now)
				end,
				held = function(ms: any, x: number, now: number)
					ms:teleported("a", x, 0.45, 0, "held", now)
				end,
				knocked = function(ms: any, x: number, now: number)
					ms:teleported("a", x + 12, 0.45, 0, "knocked", now)
				end,
				retake = function(ms: any, _x: number, _now: number)
					ms:onHandoff({ id = "a", species = "squirrel" }, nil, "release")
					ms:onHandoff({ id = "a", species = "squirrel" }, nil, "possess")
				end,
				-- (taken back, and a Reset before its first packet)
				["retake+reset"] = function(ms: any, x: number, now: number)
					ms:onHandoff({ id = "a", species = "squirrel" }, nil, "release")
					ms:onHandoff({ id = "a", species = "squirrel" }, nil, "possess")
					ms:teleported("a", x + 40, 0.45, 0, "reset", now)
				end,
				-- (the control: the round-6 rule, a move the server made starting the governor afresh)
				["afresh (round 6)"] = function(ms: any, x: number, now: number)
					ms:teleported("a", x + 40, 0.45, 0, "reset", now)
					ms.deps.validator:anchor("a", x + 40, 0.45, 0, now, nil)
				end,
			}
			for _, name in { "reset", "held", "knocked", "retake", "retake+reset", "afresh (round 6)" } do
				local where = { x = 0 }
				local ms = MovementService.new({
					validator = MoveValidator.new(vworld),
					enforce = false,
					poseOf = function(_actor: any): (number, number, number)
						return where.x, 0.45, 0
					end,
				})
				ms:onHandoff({ id = "a", species = "squirrel" }, nil, "possess")
				local b = ms.deps.validator:governorBounds(false)
				local seq, clock, now, x = 0, 5, 100, 0
				local flags, after = 0, 0
				local function send(dx: number): { any }
					seq += 1
					clock += 0.05
					now += 0.05
					x += dx
					where.x = x
					local s = SquirrelMotor.new(x, 0.45, 0)
					s.grounded, s.clock = true, clock
					local _, e, dec =
						SquirrelWire.decode(SquirrelWire.encode(seq, ms:epochOf("a"), SquirrelMotor.serialize(s)))
					local v = ms:packet("a", "squirrel", { seq = seq, epoch = e, snapshot = dec }, now)
					return if v and v.violations then v.violations else {}
				end
				alone(function()
					-- (the first packet where the body was handed over)
					flags += count(send(0), "governor")
					-- the governor's pace for 1 s, then the window's one-off nearly all spent at once (clean: within it)
					for _ = 1, 20 do
						flags += count(send(b.vh * 0.05), "governor")
					end
					flags += count(send(b.vh * 0.05 + b.dh * 0.9), "governor")
					-- the move the client can ask for, then the same again from where it was put
					moves[name](ms, x, now)
					local m = ms.deps.validator
					local held = m:last("a")
					x = if held then held.x else x
					if name == "reset" or name == "retake+reset" or name == "afresh (round 6)" then
						x += 40
					elseif name == "knocked" then
						x += 12
					end
					-- (the first packet where the body was put)
					after += count(send(0), "governor")
					for _ = 1, 10 do
						after += count(send(b.vh * 0.05), "governor")
					end
					after += count(send(b.vh * 0.05 + b.dh * 0.9), "governor")
				end)
				table.insert(rows, `{name}: governor flags before the move {flags}, after it {after}`)
				t.eq(flags, 0, `{name}: the first burst is within the one-off`)
				if name == "afresh (round 6)" then
					t.eq(after, 0, "the control: a fresh governor takes the second burst")
				else
					t.truthy(after > 0, `{name}: the second burst, within 3 s of the first, is caught`)
				end
			end
			for _, r in rows do
				print(`      {r}`)
			end
		end
	)

	-- river ------------------------------------------------------------------------------------------------------------
	t.test(
		"river: a greedy client claiming landings and falling back in runs the quay no faster than the governor's pace",
		function()
			-- the bank (the quay's height) west of the quay line, the water's surface beyond: the floors
			local base = TestWorld.build({ boxes = {} })
			local BANK = Recovery.QUAY_Y
			local function down(ox: number, oy: number, oz: number, _dx: number, dy: number, _dz: number): boolean
				local g = if ox <= quayX(oz) + 0.5 then BANK else 0
				return g >= oy + dy and g <= oy
			end
			local vworld = ValidatorWorld.build(base, {
				wall = function(): boolean
					return false
				end,
				down = down,
			})
			local P = SquirrelMotor.params
			local rows, worst = {}, 0
			for _, rate in { 2, 4, 10, 20, 30, 60 } do
				for _, clockRate in { 0.8, 1, 1.2 } do
					local v = MoveValidator.new(vworld)
					local dt = 1 / rate
					local z0 = -100 * S
					local s = SquirrelMotor.new(quayX(z0), BANK, z0)
					s.grounded, s.clock = true, 1
					v:anchor("a", s.x, s.y, s.z, 1, nil)
					v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 1)
					local now, cleanAt, seq, landings, snaps = 1, 1, 1, 0, 0
					local fast = v:fastest("a")
					local walk = SquirrelMotor.groundCap(false) * 0.999
					for _ = 1, rate * 6 do
						seq += 1
						now += dt
						local prev = v:last("a") :: State
						local n = SquirrelMotor.clone(prev)
						n.clock = prev.clock + dt * clockRate
						-- a landing as far along as the rule lets one be, else a step off the quay into the water at the
						-- walk's pace (across first, then along), falling
						local best: number? = nil
						local lo, hi = prev.z, prev.z + fast * dt + 2
						for _ = 1, 24 do
							local mid = (lo + hi) / 2
							local qz = math.clamp(mid, -225 * S, 425 * S)
							local wx = Recovery.riverEntry(
								{ x = prev.x, y = prev.y, z = prev.z, vy = prev.vy, onRail = false },
								quayX(qz),
								BANK,
								qz,
								math.min(dt * clockRate, dt + 0.35, 0.5),
								fast,
								P.gravity,
								SquirrelMotor.envelopeParams.posSlack
							)
							if wx then
								best, lo = qz, mid
							else
								hi = mid
							end
						end
						if best and not (prev.grounded and math.abs(prev.y - BANK) < 0.01) then
							n.x, n.y, n.z = quayX(best), BANK, best
							n.vx, n.vy, n.vz, n.grounded = 0, 0, 0, true
						else
							local edge = (Height.riverCenterU(prev.z / S) - RIVER.halfWidth) * S + 0.5
							local across = math.min(math.max(0, edge - prev.x), walk * dt)
							local along = math.sqrt(math.max(0, (walk * dt) ^ 2 - across * across))
							n.x, n.z = prev.x + across, prev.z + along
							n.vx, n.vz = across / dt, along / dt
							n.vy = prev.vy - P.gravity * dt
							n.y = prev.y + (prev.vy + n.vy) / 2 * dt
							n.grounded = false
						end
						local r = v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(n) }, now)
						if r.ok then
							cleanAt = now
							if r.river then
								landings += 1
							end
						else
							-- (the service snaps it back to the last clean packet, its history kept)
							snaps += 1
							local back = SquirrelMotor.clone(prev)
							v:reset("a", SquirrelMotor.serialize(back), now, seq)
							v:anchor("a", back.x, back.y, back.z, now, cleanAt)
						end
					end
					local last = v:last("a") :: State
					local pace = (last.z - z0) / 6
					worst = math.max(worst, pace)
					table.insert(
						rows,
						string.format(
							"%d/s x%.1f: %.0f st along in 6 s (%.1f st/s), %d landings, %d snaps",
							rate,
							clockRate,
							last.z - z0,
							pace,
							landings,
							snaps
						)
					)
				end
			end
			for _, r in rows do
				print(`      {r}`)
			end
			local b = MoveValidator.new(vworld):governorBounds(false)
			t.truthy(worst <= b.vh, `the quay run at {worst} st/s, the governor's pace {b.vh}`)
		end
	)

	-- reset ------------------------------------------------------------------------------------------------------------
	t.test("reset: Reset puts the feet on the last floor a clean packet stood on, at most once per 3 s", function()
		local world = TestWorld.build()
		local _, vworld = worldWith({})
		local held: { x: number, y: number, z: number }? = nil
		local rig: any
		rig = LiveRig.new({
			world = world,
			vworld = vworld,
			link = { latency = 0.1, jitter = 0.02, loss = 0 },
			seed = 7,
			silent = function(now: number): boolean
				return now >= 3
			end,
			cheat = function(s: State, _i: SquirrelMotor.Input, now: number, _w: any)
				if now >= 3 then
					local h = held or { x = s.x, y = s.y + 20, z = s.z }
					held = h
					s.x, s.y, s.z, s.vx, s.vy, s.vz = h.x, h.y, h.z, 0, 0, 0
				end
			end,
			rootCheat = function(p: { x: number, y: number, z: number }, now: number, _s: State)
				local h = held
				if now >= 3 and h then
					p.x, p.y, p.z = h.x, h.y, h.z
				end
			end,
		})
		rig:possess(SquirrelMotor.new(0, world.groundHeight, 0), function(now: number): SquirrelMotor.Input
			local i = SquirrelMotor.idleInput(0)
			i.fw = if now < 2.5 then 1 else 0
			return i
		end)
		local done, tops = 0, {}
		for k = 0, 15 do
			rig:at(3.5 + k * 0.6, function()
				if rig:reset() then
					done += 1
					table.insert(tops, rig.server.root.y - world.groundHeight)
					local r = rig.server.root
					held = { x = r.x, y = r.y + 20, z = r.z } -- (the client puts it back up at once)
				end
			end)
		end
		rig:run(13)
		local highest = 0
		for _, y in tops do
			highest = math.max(highest, y)
		end
		print(
			`      {done} resets of 16 asked in 9 s; the Reset put the feet at most {string.format("%.2f", highest)} st over the ground`
		)
		t.truthy(done <= 4, `at most once per 3 s ({done})`)
		t.truthy(highest <= 0.2, `the feet on the floor ({highest})`)
	end)

	-- grab -------------------------------------------------------------------------------------------------------------
	t.test(
		"grab: a greedy that knows the one-grab-per-two-frames rule climbs a trunk no faster than E+Space",
		function()
			local world, vworld = worldWith({})
			local trunk = tallest(world)
			local foot = world.registry:foot(trunk)
			local rows, worst = {}, 0
			for _, rate in { 20, 30, 60 } do
				for _, clockRate in { 0.8, 1, 1.2 } do
					local saved = MoveValidator._govern
					MoveValidator._govern = function() end :: any
					local v = MoveValidator.new(vworld)
					local dt = 1 / rate
					local s = SquirrelMotor.new(foot.x + 2.5, world.groundHeight, foot.z)
					s.grounded, s.clock = true, 1
					v:accept("a", { seq = 0, snapshot = SquirrelMotor.serialize(s) }, 1)
					local y0, now, lastGrab, dirty = s.y, 1, nil :: number?, 0
					for i = 1, rate * 2 do
						local prev = v:last("a") :: State
						local cdt = dt * clockRate
						local bestN, bestDy = nil :: State?, -1
						for _, vy in { -5, 0, 20, 35 } do
							local lo, hi = 0, 20
							for _ = 1, 16 do
								local mid = (lo + hi) / 2
								local n = SquirrelMotor.clone(prev)
								n.y, n.vy, n.vx, n.vz, n.grounded, n.routeId, n.clock =
									prev.y + mid, vy, 0, 0, false, nil, prev.clock + cdt
								if #SquirrelMotor.envelope(prev, n, cdt, vworld, false, lastGrab) == 0 then
									lo = mid
								else
									hi = mid
								end
							end
							if lo > bestDy then
								bestDy = lo
								local n = SquirrelMotor.clone(prev)
								n.y, n.vy, n.vx, n.vz, n.grounded, n.routeId, n.clock =
									prev.y + lo, vy, 0, 0, false, nil, prev.clock + cdt
								bestN = n
							end
						end
						local n = bestN :: State
						local _, _, _, judged = SquirrelMotor.envelope(prev, n, cdt, vworld, false, lastGrab)
						if judged.grab then
							lastGrab = judged.grab
						end
						now += dt
						local r = v:accept("a", { seq = i, snapshot = SquirrelMotor.serialize(n) }, now)
						for _, x in r.violations do
							if x.code ~= "clock" then
								dirty += 1
							end
						end
					end
					MoveValidator._govern = saved
					local up = ((v:last("a") :: State).y - y0) / 2
					if dirty == 0 then
						worst = math.max(worst, up)
					end
					table.insert(
						rows,
						string.format("%d/s x%.1f: %.1f st/s up, %d violations", rate, clockRate, up, dirty)
					)
				end
			end
			for _, r in rows do
				print(`      {r}`)
			end
			-- (the motor's own E+Space climbs this trunk at 28.9 st/s; the envelope's launch tolerance 1.1 over it)
			t.truthy(worst <= 28.9 * 1.15, `the greedy climbed at {worst} st/s with the envelope alone`)
		end
	)

	-- near -------------------------------------------------------------------------------------------------------------
	t.test(
		"near: at 2 packets a second, a rise faster than a ledge chain 30 st from any rail is the governor's",
		function()
			local world, vworld = worldWith({})
			local v0 = MoveValidator.new(vworld)
			local b = v0:governorBounds(false)
			-- a place no rail sample is within 30 st of
			local px, pz = 0, 0
			for i = 0, 400 do
				local x, z = (i % 20) * 37 - 370, math.floor(i / 20) * 37 - 370
				if world.index:nearest(x, 20, z, 30) == nil and world.index:nearest(x, 60, z, 30) == nil then
					px, pz = x, z
					break
				end
			end
			-- 3 s at nearly the rate by a rail, then nearly the window's one-off: within the bound by a rail, not by a ledge
			local rate = b.vRail * 0.98
			local flags = 0
			alone(function()
				local v = MoveValidator.new(vworld)
				local s = SquirrelMotor.new(px, 0.45, pz)
				s.clock = 1
				v:anchor("a", px, 0.45, pz, 1, nil)
				v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 1)
				local y = 0.45
				for i = 1, 6 do
					local n = SquirrelMotor.clone(s)
					y += rate * 0.5 + (if i == 6 then b.dv * 0.9 else 0)
					n.y = y
					n.grounded, n.clock = false, 1 + 0.5 * i
					local r = v:accept("a", { seq = i + 1, snapshot = SquirrelMotor.serialize(n) }, 1 + 0.5 * i)
					flags += count(r.violations, "governor")
				end
			end)
			print(
				`      rising at {string.format("%.1f", rate)} st/s for 3 s and {string.format("%.1f", b.dv * 0.9)} st at once, {px}, {pz} (a ledge chain {string.format(
					"%.1f",
					b.vLedge
				)}, by a rail {string.format("%.1f", b.vRail)}): {flags} governor flags`
			)
			t.truthy(flags > 0, "the rise is held to the ledge chain's away from the rails")
		end
	)

	-- swing ------------------------------------------------------------------------------------------------------------
	t.test("swing: a clock run ahead by an inflated ping's swing buys no more than the base slack", function()
		local _, vworld = worldWith({})
		local flags, clockFlags = 0, 0
		alone(function()
			local v = MoveValidator.new(vworld, {
				pingOf = function(_id: any): number
					return 1.5
				end,
			})
			local b = v:governorBounds(false)
			local s = SquirrelMotor.new(0, 0.45, 0)
			s.grounded, s.clock = true, 1
			v:anchor("a", 0, 0.45, 0, 100, nil)
			v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 100)
			-- 4 s at the pace the clock check allows, then 0.8 s with the clock running twice as fast, the body at the
			-- governor's pace by its own clock
			local clock, now, x = 1, 100, 0
			for i = 1, 96 do
				local fast = i > 80
				local cdt = if fast then 0.1 else 0.05
				clock += cdt
				now += 0.05
				x += b.vh * cdt
				local n = SquirrelMotor.new(x, 0.45, 0)
				n.grounded, n.clock = true, clock
				local r = v:accept("a", { seq = i + 1, snapshot = SquirrelMotor.serialize(n) }, now)
				flags += count(r.violations, "governor")
				clockFlags += count(r.violations, "clock")
			end
		end)
		print(`      governor flags {flags}, clock flags {clockFlags}`)
		t.truthy(flags > 0, "the governor holds the lead to the base slack")
	end)
end
