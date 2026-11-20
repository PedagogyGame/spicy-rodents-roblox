--!strict
-- Validator round-10 review (scratchpad review_validator_r10.md): failing cases against w0-foundation 89d831f.
--   rail slab aslant  a drop (Q) or a leap off a rail over a closed storey, the first packet off the rail under the
--                     ceiling 5 to 12 st aside (still under it): railSlab's column top is lowered by the slant
--                     (C.SLAB_REACH / across) and meets no ceiling; nothing else judges a move with a rail end (no wall
--                     test, the wall anchor moves to it) and reachable() asks the same column
--   endless hop       a client that keeps its own meter full and hops with the sprint key held: the server's meter never
--                     drains (a leap's packets are in the air: no drain, and a full refill), 35 st/s for as long as it
--                     likes against an honest 19 to 23 st/s
--   log, lossy        honest: in at the fallen log's hole on a lossy link (5 % loss, or loss bursts): a root "wall" snap
--                     (the crossing by the log's run at x -37 is never explained)
-- The rail slab case needs build/Town.rbxm (bake first). About 15 s: `lune run tests/run.luau validator_r10rv`.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local BakedWorld = require("@tests/lib/BakedWorld")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local MovementService = require("@server/Movement/MovementService")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local LiveRig = require("@tests/lib/LiveRig")
local Height = require("@shared/World/Height")
local Data = require("@shared/Data")
local HollowLayout = require("@shared/World/HollowLayout")
local HollowShell = require("@server/World/HollowShell")
local TestWorld = require("@tests/cheat/TestWorld")

type State = SquirrelMotor.State

return function(t)
	-- rail slab aslant ---------------------------------------------------------------------------------------------------
	local town: any, bw: any, bvworld: any
	-- (the aslant drops the first case found unjudged: the end-to-end case plays them through MovementService)
	local unjudged: { any } = {}
	local function baked(): boolean
		if town then
			return true
		end
		if not fs.isFile("build/Town.rbxm") then
			return false
		end
		Height.configure(Data.default():module("TerrainExtensions"))
		town = BakedWorld.load("build/Town.rbxm")
		bw = town:motorWorld(Data.default())
		local wall, down, cover = BakedWorld.validatorRays(town)
		bvworld = ValidatorWorld.build(bw, { wall = wall, down = down, cover = cover })
		return true
	end

	t.test(
		"rail slab aslant: off every rail over a closed storey, the first packet under the ceiling 5 to 12 st aside: judged (needs build/Town.rbxm)",
		function()
			if not baked() then
				t.truthy(false, "build/Town.rbxm (lune run tools/bake/main.luau)")
				return
			end
			local reg = bw.registry
			local function solid(p: any): boolean
				local parentName = string.match(p.path, "([^%.]+)%.[^%.]+$") or ""
				return p.squirrelSolid and not ValidatorWorld.isBough(p.name, parentName)
			end
			-- (validator_r10's "rail slab" samples: a slab within 10 st under the rail, a closed storey under it)
			local drops = {}
			for _, r in reg:all() do
				local n = math.clamp(math.floor((r.length or 50) / 2), 2, 400)
				for k = 0, n do
					local p = reg:pointAt(r, k / n)
					local tt, part = town.raycast(p.x, p.y - 0.3, p.z, 0, -10, 0, solid)
					if tt and part then
						local top = p.y - 0.3 - 10 * tt
						local under = part.y0 - 0.05
						local t2, floor = town.raycast(p.x, under, p.z, 0, -40, 0, solid)
						local fy = if t2 then under - 40 * t2 else town.terrainAt(p.x, p.z)
						if under - fy >= 2.5 and top - under < 3 and floor then
							local closed = true
							for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
								if town.raycast(p.x, fy + 1.1, p.z, d[1] * 30, 0, d[2] * 30, solid) == nil then
									closed = false
								end
							end
							if closed then
								table.insert(drops, { r = r, t = k / n, p = p, under = under, fy = fy })
							end
						end
					end
				end
			end
			local total, judged, held = 0, 0, 0
			local missed: { string } = {}
			for _, d in drops do
				local p = d.p
				for _, aside in { 5, 7, 9, 12 } do
					for _, dir in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
						local x1, z1 = p.x + dir[1] * aside, p.z + dir[2] * aside
						-- (on the storey's floor: the column there has the same ceiling over it, and the same floor)
						local t3 = town.raycast(x1, d.under - 0.05, z1, 0, -40, 0, solid)
						local fy = if t3 then d.under - 0.05 - 40 * t3 else nil
						local over = fy ~= nil
							and town.raycast(x1, fy + 0.6, z1, 0, d.under - fy - 0.4, 0, solid) ~= nil
						if fy and over and math.abs(fy - d.fy) < 0.5 then
							-- (still inside the storey: no wall between the rail's column and the end at the floor's height)
							local open = town.raycast(p.x, fy + 1.1, p.z, x1 - p.x, 0, z1 - p.z, solid) == nil
							-- the time a fall from the rail to the floor takes (0.5 g t^2), and a run across in it
							local tau = math.sqrt(2 * (p.y - fy) / SquirrelMotor.params.gravity)
							if open and aside / tau <= SquirrelMotor.params.leapForward then
								total += 1
								local v = MoveValidator.new(bvworld)
								local on = SquirrelMotor.new(p.x, p.y, p.z)
								on.routeId, on.railT, on.grounded, on.clock = d.r.id, d.t, false, 1
								v:reset("a", SquirrelMotor.serialize(on), 1)
								local off = SquirrelMotor.new(x1, fy, z1)
								off.grounded = true
								off.clock = 1 + tau
								local r = v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(off) }, 1 + tau)
								local hit = false
								for _, x in r.violations do
									hit = hit or (x.severity >= 1)
								end
								-- invariant E: the held place on the rail reaches the packet on the storey's floor
								local reached = v:reachable(on :: any, off, 60)
								if hit and not reached then
									judged += 1
								else
									if reached then
										held += 1
									end
									table.insert(unjudged, { d = d, x1 = x1, z1 = z1, fy = fy, tau = tau })
									if #missed < 8 then
										local codes = {}
										for _, x in r.violations do
											table.insert(codes, `{x.code} {x.severity}`)
										end
										table.insert(
											missed,
											`{d.r.kind} {d.r.id} t {string.format("%.2f", d.t)} (rail y {string.format(
												"%.1f",
												p.y
											)}, ceiling {string.format("%.1f", d.under)}, floor {string.format(
												"%.1f",
												fy
											)}): {aside} st aside in {string.format("%.2f", tau)} s: [{table.concat(
												codes,
												", "
											)}], reachable {reached}`
										)
									end
								end
							end
						end
					end
				end
			end
			print(
				`      {#drops} rail samples over a closed storey: {judged} of {total} aslant drops through the ceiling judged; {held} reachable from the rail`
			)
			for _, m in missed do
				print(`        missed: {m}`)
			end
			t.truthy(total > 50, `drops tried ({total})`)
			t.eq(judged, total, "every aslant drop through a ceiling off a rail is judged, and never reachable")
		end
	)

	t.test(
		"rail slab aslant, end to end: on the rail, the packets held back, the first one on the storey's floor under the ceiling, then standing there: the held place never inside (needs build/Town.rbxm)",
		function()
			if not baked() then
				t.truthy(false, "build/Town.rbxm (lune run tools/bake/main.luau)")
				return
			end
			local held, total = 0, 0
			local where: { [string]: number } = {}
			for _, u in unjudged do
				local d = u.d
				local p = d.p
				total += 1
				local snaps = 0
				local ms = MovementService.new({
					validator = MoveValidator.new(bvworld),
					enforce = true,
					poseOf = function(_a: any): (number, number, number)
						return p.x, p.y, p.z
					end,
					engine = {
						correct = function(_id: any, msg: any)
							if msg.snap then
								snaps += 1
							end
						end,
						pin = function(): boolean
							return true
						end,
						hold = function() end,
					},
				})
				ms:onHandoff({ id = "a", species = "squirrel" }, nil, "possess")
				local epoch = ms:epochOf("a")
				local seq, now = 0, 100
				local function send(st: any, dt: number)
					seq += 1
					now += dt
					st.clock = now - 90
					local _, e, dec = SquirrelWire.decode(SquirrelWire.encode(seq, epoch, SquirrelMotor.serialize(st)))
					ms:packet("a", "squirrel", { seq = seq, epoch = e, snapshot = dec }, now)
					ms:watch("a", st.x, st.y, st.z, now)
					epoch = ms:epochOf("a")
				end
				for _ = 1, 15 do
					local st = SquirrelMotor.new(p.x, p.y, p.z)
					st.routeId, st.railT, st.grounded = d.r.id, d.t, false
					send(st, 1 / 30)
				end
				-- (the drop's packets held back: the first one off the rail on the storey's floor, aslant)
				local st = SquirrelMotor.new(u.x1, u.fy, u.z1)
				st.grounded = true
				send(st, u.tau)
				for _ = 1, 45 do
					send(SquirrelMotor.new(u.x1, u.fy, u.z1), 1 / 30)
				end
				local _, hy = ms:heldPlace("a")
				if hy ~= nil and hy < d.under - 1 and snaps == 0 then
					held += 1
					local key = `{d.r.kind} {d.r.id}`
					where[key] = (where[key] or 0) + 1
				end
			end
			for k, v in where do
				print(`      {k}: held inside the storey under it after {v} drops`)
			end
			print(`      {held} of {total} unjudged aslant drops held inside the storey, no snap`)
			t.truthy(total > 0, "the first case found unjudged drops to play (run both)")
			t.eq(held, 0, "an aslant drop off a rail through a ceiling never puts the held place inside")
		end
	)
	-- the sprint meter --------------------------------------------------------------------------------------------------
	-- (open ground: no walls, the ground at y 0, as validator_r10's "meter")
	local function flat(): any
		local function wall(): boolean
			return false
		end
		local function down(_ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
			return oy >= 0 and math.min(oy, oy + dy) <= 0
		end
		return ValidatorWorld.build(TestWorld.build({}), { wall = wall, down = down })
	end

	t.test(
		"meter: a sprint hidden in gaps of 1.19 s, 6 in 10 s, each ending in the air (a little hop), the rest sprinted on the ground: snapped within 40 s",
		function()
			local vworld = flat()
			local snaps: { string } = {}
			local at = { x = 0, y = 0, z = -200 }
			local ms = MovementService.new({
				validator = MoveValidator.new(vworld),
				enforce = true,
				poseOf = function(_a: any): (number, number, number)
					return at.x, at.y, at.z
				end,
				engine = {
					correct = function(_id: any, msg: any)
						if msg.snap then
							table.insert(snaps, msg.why)
						end
					end,
					pin = function(): boolean
						return true
					end,
					hold = function() end,
				},
			})
			ms:onHandoff({ id = "a", species = "squirrel" }, nil, "possess")
			local seq, now = 0, 100
			local function send(st: State, dt: number)
				seq += 1
				now += dt
				st.clock = now - 90
				local _, e, dec =
					SquirrelWire.decode(SquirrelWire.encode(seq, ms:epochOf("a"), SquirrelMotor.serialize(st)))
				ms:packet("a", "squirrel", { seq = seq, epoch = e, snapshot = dec }, now)
				ms:watch("a", st.x, st.y, st.z, now)
			end
			for _ = 1, 10 do
				send(SquirrelMotor.new(at.x, 0, at.z), 0.05)
			end
			local P = SquirrelMotor.params
			local speed, g = P.sprint, P.gravity
			local x, start = at.x, now
			while now - start < 40 and #snaps == 0 do
				-- the gap: a sprint, ending in the air a moment after a little hop
				x += speed * 1.19
				local s = SquirrelMotor.new(x, 0.15, at.z)
				s.grounded, s.vx, s.vy = false, speed, 3.5
				send(s, 1.19)
				-- the hop's end, then a sprint on the ground until the next gap (one every 1.75 s: 6 in 10 s at most)
				local y, vy = 0.15, 3.5
				for _ = 1, 17 do
					x += speed / 30
					vy -= g / 30
					y = math.max(0, y + vy / 30)
					local s2 = SquirrelMotor.new(x, y, at.z)
					s2.grounded = y <= 0
					s2.vx, s2.vy = speed, if y <= 0 then 0 else vy
					send(s2, 1 / 30)
				end
			end
			local secs = now - start
			print(
				`      {string.format("%.1f", secs)} s at {speed} st/s ({string.format("%.0f", x - at.x)} st): snaps [{table.concat(
					snaps,
					", "
				)}]`
			)
			t.truthy(#snaps > 0, "a sprint hidden in gaps that end in the air is snapped")
		end
	)

	t.test(
		"meter: a client that keeps its own meter full and hops with the sprint key held, 30 s on open ground: snapped (the motor: 8 leaps a meter, winded leaps at a walk)",
		function()
			local rigTown = LiveRig.town()
			local results = {}
			for _, cheat in { false, true } do
				local rig = LiveRig.new({
					world = rigTown.noWalls,
					vworld = rigTown.vworld,
					link = { latency = 0.06, jitter = 0.02, loss = 0 },
					seed = 7,
					cheat = if cheat
						then function(s: State)
							s.stamina = 1
							s.winded = false
						end
						else nil,
				})
				local s0 = rigTown.openStart()
				rig:possess(s0, function(_now: number, s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
					local inp = SquirrelMotor.idleInput(-math.pi / 2)
					inp.fw = 1
					inp.sprint = true
					inp.leap = s.grounded
					return inp
				end)
				rig:run(30)
				local r = rig:result()
				local pace = math.sqrt((r.root.x - s0.x) ^ 2 + (r.root.z - s0.z) ^ 2) / 30
				print(
					`      {if cheat then "meter kept full" else "honest"}: {string.format("%.1f", pace)} st/s over 30 s; {LiveRig.describe(
						"",
						r
					)}`
				)
				results[cheat] = r.snaps
			end
			t.eq(results[false], 0, "the honest hopper is not snapped")
			t.truthy(results[true] > 0, "a hopper whose meter never empties is snapped")
		end
	)

	-- the fallen log on a lossy link --------------------------------------------------------------------------------------
	t.test(
		"log, lossy: honest, in at the fallen log's hole and on along its run, 5 % loss or loss bursts: 0 snaps",
		function()
			local data = Data.default()
			local layout = HollowLayout.default() :: HollowLayout.Layout
			local shell = BakedWorld.fromModel(HollowShell.build(roblox, layout))
			local w = shell:motorWorld(data)
			local wall, down, cover = BakedWorld.validatorRays(shell)
			local vworld = ValidatorWorld.build(w, { wall = wall, down = down, cover = cover })
			local links: { { name: string, link: LiveRig.Link } } = {
				{ name = "5 % loss", link = { latency = 0.2, jitter = 0.15, loss = 0.05 } },
				{
					name = "bursts",
					link = { latency = 0.12, jitter = 0.1, loss = 0.02, dropEvery = 2.3, dropFor = 0.8 },
				},
			}
			local snaps, runs = 0, 0
			for _, h in layout.hollows do
				if h.id ~= "LOG" then
					continue
				end
				local hole: HollowLayout.Mouth? = nil
				for _, m in h.mouths do
					if m.opens == "ground" then
						hole = m
						break
					end
				end
				local m = hole :: HollowLayout.Mouth
				local ol = math.sqrt(m.out[1] ^ 2 + m.out[3] ^ 2)
				local ox, oz = m.out[1] / ol, m.out[3] / ol
				local cam = BakedWorld.cameraYawToward(-ox, -oz)
				for _, l in links do
					for seed = 1, 4 do
						runs += 1
						local rig = LiveRig.new({ world = w, vworld = vworld, link = l.link, seed = 500 + seed })
						local x, z = m.x + ox * 6, m.z + oz * 6
						local s = SquirrelMotor.new(x, shell.groundAt(x, z, m.y + 3), z)
						s.yaw = math.atan2(-ox, -oz)
						rig:possess(
							s,
							function(_now: number, st: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
								local c = if st.routeId
									then BakedWorld.cameraYawToward(math.sin(st.yaw), math.cos(st.yaw))
									else cam
								return BakedWorld.keys(c, { fw = 1 })
							end
						)
						rig:run(6)
						local r = rig:result()
						snaps += r.snaps
						if r.snaps > 0 then
							print(`      {l.name} seed {seed}: {LiveRig.describe("LOG", r)}`)
						end
					end
				end
			end
			print(`      {snaps} snaps over {runs} runs in at the fallen log`)
			t.eq(snaps, 0, "honest runs into the fallen log on a lossy link are not snapped")
		end
	)
end
