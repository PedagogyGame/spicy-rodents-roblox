--!strict
-- ReplicatedStorage.Shared.Minigames.Jenga.Fall
-- The collapse as one script (checklist JEN-P7): the SERVER builds it the moment Physics says the tower has
-- gone, and every client plays the same table back at its own frame rate, so everybody sees the same blocks
-- land in the same places. Nothing is rolled about WHETHER or WHERE it fails: that comes from the tower
-- (`tower.fallen`: the joint that gave way and the side it went over); the seed only scatters the tumbling.
-- What happens: the part above the failed joint tips as one body about the edge it went over, slowly at first
-- (a tall thing hangs before it goes), then faster; it breaks up from the top as it goes (a level lets go
-- when the tip is steeper than its grip); each freed block flies, tumbling, hits the table or the deck boards
-- (or the stump of the tower, which it glances off), bounces a little, slides and stops lying flat. Resting
-- blocks are nudged apart so none lies inside another, and a block crowded off the table drops to the deck.
-- Everything below the failed joint stays standing where it was.
-- A block's path is a short list of segments, 12 numbers each: t, kind, x, y, z, vx, vy, vz, yaw, yawRate,
-- tum, tumRate. Kinds: 0 riding the tipping part (drawn by turning its start point about the hinge by the
-- tip angle), 1 flying (closed form under gravity), 2 sliding to rest (eased toward the next segment, its
-- height kept exactly on the surface), 3 at rest. `tum` is the turn about the script's hinge axis.
-- Table frame as Layout. Pure; Lune-tested (tests/unit/jenga_fall.spec.luau).
-- Interface: build(tower, seed) -> Script; pose(script, index, t) -> (x, y, z, yaw, tum); axis(script) ->
--   (nx, nz); lowest(script, yaw, tum) -> half height; cues(script) -> { { t, name, volume } }; check(any) ->
--   (Script?, why?); size(script) -> numbers carried; restackPose(script, index, t) -> (x, y, z, yaw, tum);
--   restackTime() -> seconds; SEG, VERSION

local Rng = require("../../Util/Rng")
local Layout = require("./Layout")
local Stability = require("./Stability")
local Tower = require("./Tower")

local Fall = {}

Fall.VERSION = 1
Fall.SEG = 12
Fall.STEP = 1 / 120 -- the builder's own step (the script is closed-form between events)
Fall.TIP_KEY = 1 / 30 -- spacing of the tip-angle keys
Fall.BREAK = 0.34 -- rad: the lowest level of the tipping part lets go at about this tip
Fall.BREAK_PER_LEVEL = 0.012 -- each level above lets go this much sooner
Fall.BREAK_MIN = 0.07
Fall.RESTITUTION = 0.3
Fall.SCRUB = 0.62 -- sideways speed kept through a bounce
Fall.V_REST = 1.3 -- studs/s: a bounce slower than this is the last
Fall.MAX_BOUNCES = 4
Fall.SLIDE_MU = 0.5
Fall.STUMP_KEEP = 1.05 -- resting blocks keep this far from the middle of a standing stump
Fall.EDGE_KEEP = 0.35 -- blocks on the deck keep this far outside the table
Fall.REST_PAUSE = 0.4 -- seconds after the last block stops before the script is over
Fall.RESTACK_STEP = 0.07 -- seconds between blocks when the tower is put back
Fall.RESTACK_FLY = 0.45

local T, W, L = Layout.BLOCK_T, Layout.BLOCK_W, Layout.BLOCK_L
local G = Layout.GRAVITY
local SEG = Fall.SEG

export type BlockPath = { id: number, s: { number } }
export type Cue = { t: number, name: string, volume: number }
export type Script = {
	v: number,
	level: number, -- the joint that failed (levels up to this one stand)
	ux: number, -- the way it fell (unit, table frame)
	uz: number,
	hx: number, -- the hinge: a point on the edge it went over
	hy: number,
	hz: number,
	tip: { number }, -- the tip angle every TIP_KEY seconds from t = 0
	blocks: { BlockPath },
	cues: { Cue },
	tEnd: number,
}

-- Half the height of a lying or tumbling block: how far its middle is above the lowest point of it.
local function lowestOf(ux: number, uz: number, yaw: number, tum: number): number
	local c, s = math.cos(yaw), math.sin(yaw)
	-- the block's half extent along the fall direction (its length runs along (c, s))
	local r = math.abs(c * ux + s * uz) * (L / 2) + math.abs(-s * ux + c * uz) * (W / 2)
	return math.abs(math.cos(tum)) * (T / 2) + math.abs(math.sin(tum)) * r
end

function Fall.lowest(script: Script, yaw: number, tum: number): number
	return lowestOf(script.ux, script.uz, yaw, tum)
end

-- The axis blocks tumble about: horizontal, square to the fall (a positive tum tips the top toward the fall).
function Fall.axis(script: Script): (number, number)
	return script.uz, -script.ux
end

local function tipAt(tip: { number }, t: number): number
	local f = t / Fall.TIP_KEY
	local i = math.floor(f)
	local n = #tip
	if i + 1 >= n then
		return tip[n]
	end
	local a = tip[i + 1]
	return a + (tip[i + 2] - a) * (f - i)
end

-- Two lying blocks as rectangles in plan: how far must they be moved apart, and which way (0 if they do not
-- touch). Separating axes of two boxes.
local function planOverlap(
	ax: number,
	az: number,
	ayaw: number,
	bx: number,
	bz: number,
	byaw: number
): (number, number, number)
	local dx, dz = bx - ax, bz - az
	if dx * dx + dz * dz > L * L + W * W then
		return 0, 0, 0
	end
	local ac, as = math.cos(ayaw), math.sin(ayaw)
	local bc, bs = math.cos(byaw), math.sin(byaw)
	local hl, hw = L / 2, W / 2
	local best, bnx, bnz = math.huge, 0, 0
	for k = 1, 4 do
		local nx, nz
		if k == 1 then
			nx, nz = ac, as
		elseif k == 2 then
			nx, nz = -as, ac
		elseif k == 3 then
			nx, nz = bc, bs
		else
			nx, nz = -bs, bc
		end
		local ra = math.abs(ac * nx + as * nz) * hl + math.abs(-as * nx + ac * nz) * hw
		local rb = math.abs(bc * nx + bs * nz) * hl + math.abs(-bs * nx + bc * nz) * hw
		local dist = dx * nx + dz * nz
		local pen = ra + rb - math.abs(dist)
		if pen <= 0 then
			return 0, 0, 0
		end
		if pen < best then
			best = pen
			if dist < 0 then
				bnx, bnz = -nx, -nz
			else
				bnx, bnz = nx, nz
			end
		end
	end
	return best, bnx, bnz
end

type Rest = { x: number, z: number, yaw: number, tum: number, deck: boolean, dropped: boolean, moving: boolean }

local function push(
	s: { number },
	t: number,
	kind: number,
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	yaw: number,
	yawRate: number,
	tum: number,
	tumRate: number
)
	local o = #s
	s[o + 1], s[o + 2], s[o + 3], s[o + 4], s[o + 5], s[o + 6] = t, kind, x, y, z, vx
	s[o + 7], s[o + 8], s[o + 9], s[o + 10], s[o + 11], s[o + 12] = vy, vz, yaw, yawRate, tum, tumRate
end

-- build(tower, seed): the script for a tower that Physics has declared fallen.
function Fall.build(tw: Tower.Tower, seed: number): Script
	local f: Tower.Failure = tw.fallen or { level = 0, dir = "x", sign = 1, why = "balance" }
	local rng = Rng.new(seed)
	local an = Stability.analyse(tw) -- a fresh look, without disturbing the tower's own cache
	local saveAn, saveStale = tw.an, tw.stale
	tw.an, tw.stale = an, false
	local poses = Stability.poses(tw)
	tw.an, tw.stale = saveAn, saveStale

	local i = math.clamp(f.level, 0, an.n - 1)
	local d = if f.dir == "x" then 1 else 2
	local j = 2 * i + d
	local ux, uz = 0, 0
	if d == 1 then
		ux = f.sign
	else
		uz = f.sign
	end
	local lo, hi = an.lo[j], an.hi[j]
	if lo > hi then -- the level is gone: hinge on the middle of what is below
		lo, hi = 0, 0
	end
	local edge = if f.sign > 0 then hi else lo
	local hy = i * T
	local hx = if d == 1 then edge else an.sx[math.max(i, 1)]
	local hz = if d == 2 then edge else an.sz[math.max(i, 1)]

	-- the tipping part as one body about the hinge
	local mass = math.max(an.mass[i + 1], 1)
	local height = math.max(an.h[i + 1], T / 2)
	local uc = (an.base[j] - edge) * f.sign -- its centre along the fall direction, from the hinge
	local inertia = math.max(an.inertia[j], 0.2)
	local theta = (if d == 1 then tw.psiX[i + 1] else tw.psiZ[i + 1]) * f.sign
	local omega = (if d == 1 then tw.omX[i + 1] else tw.omZ[i + 1]) * f.sign
	theta = math.clamp(theta, 0, 0.5)
	omega = math.clamp(omega, 0.12, 3)
	local tip = { theta }
	local tipRate = { omega }
	local tEndTip = 3.0
	do
		local t, nextKey = 0, Fall.TIP_KEY
		while t < tEndTip do
			local arm = uc * math.cos(theta) + height * math.sin(theta)
			omega += G * mass * math.max(arm, 0.004) / inertia * Fall.STEP
			omega = math.min(omega, 7)
			theta += omega * Fall.STEP
			t += Fall.STEP
			if t >= nextKey - 1e-9 then
				table.insert(tip, theta)
				table.insert(tipRate, omega)
				nextKey += Fall.TIP_KEY
			end
			if theta > Fall.BREAK + 0.25 then
				break
			end
		end
	end
	-- the keys are the turn since the start (the drawn tower already shows the lean it started from)
	for k = #tip, 1, -1 do
		tip[k] -= tip[1]
	end
	local function rateAt(t: number): number
		local k = math.clamp(math.floor(t / Fall.TIP_KEY + 0.5) + 1, 1, #tipRate)
		return tipRate[k]
	end

	local paths: { BlockPath } = {}
	local rests: { Rest } = {}
	local lastImpact: { { number } } = {} -- per block: t, x, z, yaw, tum, vx, vz, surfaceY
	local cues: { Cue } = { { t = 0, name = "tip", volume = 1 } }
	local stumpY = i * T
	local hasStump = i >= 1
	local stumpX, stumpZ = an.sx[math.max(i, 1)], an.sz[math.max(i, 1)]
	local half = Layout.TABLE_HALF

	local function ground(x: number, z: number, bottom: number): number
		if hasStump and math.abs(x - stumpX) < L / 2 and math.abs(z - stumpZ) < L / 2 and bottom > stumpY - 0.2 then
			return stumpY
		end
		if math.abs(x) <= half and math.abs(z) <= half and bottom > -0.25 then
			return 0
		end
		return -Layout.TABLE_H
	end

	for id = 1, #tw.blocks do
		local b = tw.blocks[id]
		local o = (id - 1) * 6
		local s: { number } = {}
		local inHand = b.level == 0
		local x, y, z, yaw = poses[o + 1], poses[o + 2], poses[o + 3], poses[o + 4]
		if inHand then
			-- the block out of the tower (in the loser's hand, or pulled clear): it is let go above the top
			x, y, z, yaw = hx + ux * 0.3, an.n * T + 1.0, hz + uz * 0.3, 0
		end
		if not inHand and b.level <= i then
			-- the stump: it stays exactly as it stood
			push(s, 0, 3, x, y, z, 0, 0, 0, yaw, 0, 0, 0)
			rests[id] = { x = x, z = z, yaw = yaw, tum = 0, deck = false, dropped = false, moving = false }
		else
			-- when it lets go
			local tRel = 0
			local vx, vy, vz = 0, 0, 0
			local tum, tumRate = 0, 0
			if not inHand then
				local rel = Fall.BREAK - Fall.BREAK_PER_LEVEL * (b.level - i - 1) + (rng.next() - 0.5) * 0.08
				rel = math.max(rel, Fall.BREAK_MIN)
				push(s, 0, 0, x, y, z, 0, 0, 0, yaw, 0, 0, 0)
				local k = 1
				while k < #tip and tip[k] < rel do
					k += 1
				end
				tRel = (k - 1) * Fall.TIP_KEY
				local th = tip[k]
				local w = rateAt(tRel) * (0.8 + rng.next() * 0.3)
				local du = (x - hx) * ux + (z - hz) * uz
				local dn = (x - hx) * uz - (z - hz) * ux
				local dy = y - hy
				local c, sn = math.cos(th), math.sin(th)
				local ru = du * c + dy * sn
				local ry = -du * sn + dy * c
				x = hx + ru * ux + dn * uz
				z = hz + ru * uz - dn * ux
				y = hy + ry
				local vu = w * ry
				vy = -w * ru
				local vn = (rng.next() - 0.5) * 1.6
				vx = vu * ux + vn * uz
				vz = vu * uz - vn * ux
				tum = th
				tumRate = w * (0.7 + rng.next() * 0.9)
			else
				vx, vz = ux * 0.6, uz * 0.6
				tumRate = 2 + rng.next() * 2
			end
			local yawRate = (rng.next() - 0.5) * 4
			-- fly and bounce
			local t = tRel
			local bounces = 0
			local firstHit = true
			push(s, t, 1, x, y, z, vx, vy, vz, yaw, yawRate, tum, tumRate)
			local surface = 0
			local guard = 0
			while guard < 2400 do
				guard += 1
				local nvy = vy - G * Fall.STEP
				local nx, ny, nz = x + vx * Fall.STEP, y + (vy + nvy) * 0.5 * Fall.STEP, z + vz * Fall.STEP
				local nyaw, ntum = yaw + yawRate * Fall.STEP, tum + tumRate * Fall.STEP
				local bottomWas = y - lowestOf(ux, uz, yaw, tum)
				local bottom = ny - lowestOf(ux, uz, nyaw, ntum)
				local gy = ground(nx, nz, bottomWas)
				if bottom <= gy and nvy < 0 then
					-- it has hit: put it exactly on the surface at the fraction of the step where it touched
					local frac = math.clamp((bottomWas - gy) / math.max(bottomWas - bottom, 1e-6), 0, 1)
					local dt = Fall.STEP * frac
					t += dt
					x, z = x + vx * dt, z + vz * dt
					yaw, tum = yaw + yawRate * dt, tum + tumRate * dt
					local vHit = vy - G * dt
					y = gy + lowestOf(ux, uz, yaw, tum)
					local speed = math.abs(vHit)
					if firstHit or speed > 2.5 then
						table.insert(cues, { t = t, name = "clack", volume = math.clamp(speed / 12, 0.1, 1) })
						firstHit = false
					end
					bounces += 1
					vy = -vHit * Fall.RESTITUTION
					vx *= Fall.SCRUB
					vz *= Fall.SCRUB
					tumRate *= 0.55
					yawRate *= 0.5
					local onStump = gy == stumpY and hasStump
					if onStump then
						-- glance off the stump, outward
						local ox, oz = x - stumpX, z - stumpZ
						local len = math.sqrt(ox * ox + oz * oz)
						if len < 0.05 then
							ox, oz, len = ux, uz, 1
						end
						vx += ox / len * 2.2
						vz += oz / len * 2.2
						vy = math.max(vy, 1.6)
					end
					local offTable = gy == 0 and bounces < 8
					if offTable then
						-- would its slide carry it over the table edge? then it goes on tumbling
						local vh2 = vx * vx + vz * vz
						local reach = vh2 / (2 * Fall.SLIDE_MU * G)
						local vh = math.sqrt(vh2)
						if vh > 1e-3 then
							local ex, ez = x + vx / vh * reach, z + vz / vh * reach
							offTable = math.abs(ex) > half or math.abs(ez) > half
						else
							offTable = false
						end
						if offTable then
							vy = math.max(vy, 0.9)
						end
					end
					if not onStump and not offTable and (vy < Fall.V_REST or bounces >= Fall.MAX_BOUNCES) then
						surface = gy
						break
					end
					push(s, t, 1, x, y, z, vx, vy, vz, yaw, yawRate, tum, tumRate)
				else
					t += Fall.STEP
					x, y, z, vy, yaw, tum = nx, ny, nz, nvy, nyaw, ntum
				end
			end
			-- where its slide ends, lying flat
			local vh = math.sqrt(vx * vx + vz * vz)
			local reach = math.min(vh * vh / (2 * Fall.SLIDE_MU * G), 1.6)
			local rx, rz = x, z
			if vh > 1e-3 then
				rx, rz = x + vx / vh * reach, z + vz / vh * reach
			end
			rx = math.clamp(rx, -Layout.RAIL, Layout.RAIL)
			rz = math.clamp(rz, -Layout.RAIL, Layout.RAIL)
			local onDeck = surface < -0.01
			if not onDeck then
				rx = math.clamp(rx, -half + 0.02, half - 0.02)
				rz = math.clamp(rz, -half + 0.02, half - 0.02)
			end
			local restTum = math.floor(tum / math.pi + 0.5) * math.pi
			lastImpact[id] = { t, x, z, yaw, tum, vh, yawRate }
			rests[id] = {
				x = rx,
				z = rz,
				yaw = yaw + yawRate * 0.15,
				tum = restTum,
				deck = onDeck,
				dropped = false,
				moving = true,
			}
		end
		paths[id] = { id = id, s = s }
	end

	-- nudge the resting blocks apart (and off the stump, and out from under the table)
	local n = #tw.blocks
	local function constrain(r: Rest)
		if r.deck then
			local keep = half + Fall.EDGE_KEEP
			if math.abs(r.x) < keep and math.abs(r.z) < keep then
				-- push out through the nearer side
				if keep - math.abs(r.x) < keep - math.abs(r.z) then
					r.x = if r.x >= 0 then keep else -keep
				else
					r.z = if r.z >= 0 then keep else -keep
				end
			end
			r.x = math.clamp(r.x, -Layout.RAIL, Layout.RAIL)
			r.z = math.clamp(r.z, -Layout.RAIL, Layout.RAIL)
		else
			if hasStump then
				local ox, oz = r.x - stumpX, r.z - stumpZ
				local len = math.sqrt(ox * ox + oz * oz)
				if len < Fall.STUMP_KEEP then
					if len < 1e-3 then
						ox, oz, len = ux, uz, 1
					end
					r.x = stumpX + ox / len * Fall.STUMP_KEEP
					r.z = stumpZ + oz / len * Fall.STUMP_KEEP
				end
			end
			r.x = math.clamp(r.x, -half + 0.02, half - 0.02)
			r.z = math.clamp(r.z, -half + 0.02, half - 0.02)
		end
	end
	local function relax(passes: number): number
		local left = 0
		for _ = 1, passes do
			left = 0
			for a = 1, n do
				local ra = rests[a]
				if ra.moving then
					for b = a + 1, n do
						local rb = rests[b]
						if rb.moving and ra.deck == rb.deck then
							local pen, nx, nz = planOverlap(ra.x, ra.z, ra.yaw, rb.x, rb.z, rb.yaw)
							if pen > 0 then
								left += 1
								local p = pen * 0.5 + 0.004
								ra.x -= nx * p
								ra.z -= nz * p
								rb.x += nx * p
								rb.z += nz * p
							end
						end
					end
					constrain(ra)
				end
			end
			if left == 0 then
				break
			end
		end
		return left
	end
	for a = 1, n do
		if rests[a].moving then
			constrain(rests[a])
		end
	end
	local left = relax(60)
	local rounds = 0
	while left > 0 and rounds < 40 do
		rounds += 1
		-- the table is too crowded: the block nearest an edge that still overlaps another goes over it
		local pick, pickGap = 0, math.huge
		for a = 1, n do
			local ra = rests[a]
			if ra.moving and not ra.deck then
				for b = 1, n do
					local rb = rests[b]
					if b ~= a and rb.moving and not rb.deck then
						local pen = planOverlap(ra.x, ra.z, ra.yaw, rb.x, rb.z, rb.yaw)
						if pen > 0 then
							local gap = half - math.max(math.abs(ra.x), math.abs(ra.z))
							if gap < pickGap then
								pick, pickGap = a, gap
							end
							break
						end
					end
				end
			end
		end
		if pick == 0 then
			-- only the deck is crowded: it is big, keep spreading
			left = relax(60)
		else
			local r = rests[pick]
			r.deck = true
			r.dropped = true
			constrain(r)
			left = relax(60)
		end
	end

	-- the last segments: slide to rest (over the edge first, for a block crowded off the table)
	local tEnd = #tip * Fall.TIP_KEY
	for id = 1, n do
		local r = rests[id]
		local li = lastImpact[id]
		if r.moving and li then
			local s = paths[id].s
			local t, x, z, yaw, tum, vh = li[1], li[2], li[3], li[4], li[5], li[6]
			local surfaceY = if r.deck then -Layout.TABLE_H else 0
			local restY = surfaceY + T / 2
			local restTum = r.tum
			if r.dropped then
				-- slide to the table edge, tip over it, land on the deck
				local ex = math.clamp(r.x, -half, half)
				local ez = math.clamp(r.z, -half, half)
				local ox, oz = r.x - ex, r.z - ez
				local len = math.sqrt(ox * ox + oz * oz)
				if len < 1e-3 then
					ox, oz, len = ux, uz, 1
				end
				local slide = 0.3
				local flight = math.sqrt(2 * Layout.TABLE_H / G)
				local flatTum = math.floor(tum / math.pi + 0.5) * math.pi
				push(s, t, 2, x, lowestOf(ux, uz, yaw, tum), z, 0, 0, 0, yaw, 0, tum, 0)
				t += slide
				push(
					s,
					t,
					1,
					ex,
					T / 2,
					ez,
					ox / len * (len / flight),
					0,
					oz / len * (len / flight),
					r.yaw,
					0,
					flatTum,
					math.pi / flight
				)
				t += flight
				restTum = flatTum + math.pi
				r.tum = restTum
				table.insert(cues, { t = t, name = "clack", volume = 0.5 })
			else
				local dx, dz = r.x - x, r.z - z
				local dist = math.sqrt(dx * dx + dz * dz)
				local dur = math.clamp(if vh > 0.2 then 2 * dist / vh else 0.3, 0.25, 0.9)
				push(s, t, 2, x, surfaceY + lowestOf(ux, uz, yaw, tum), z, 0, 0, 0, yaw, 0, tum, 0)
				t += dur
			end
			push(s, t, 3, r.x, restY, r.z, 0, 0, 0, r.yaw, 0, restTum, 0)
			tEnd = math.max(tEnd, t)
		end
	end

	-- the clatter: at most one cue every 30 ms, loudest kept
	table.sort(cues, function(a, b)
		return a.t < b.t
	end)
	local kept: { Cue } = {}
	for _, c in cues do
		local last = kept[#kept]
		if last and c.name == "clack" and last.name == "clack" and c.t - last.t < 0.03 then
			last.volume = math.max(last.volume, c.volume)
		else
			table.insert(kept, c)
		end
	end
	table.insert(kept, { t = tEnd, name = "settle", volume = 0.5 })

	return {
		v = Fall.VERSION,
		level = i,
		ux = ux,
		uz = uz,
		hx = hx,
		hy = hy,
		hz = hz,
		tip = tip,
		blocks = paths,
		cues = kept,
		tEnd = tEnd + Fall.REST_PAUSE,
	}
end

-- pose(script, index, t): where block `index` (its id) is at time t: position, yaw, and its turn about the
-- script's hinge axis. A client draws CFrame.new(x, y, z) * fromAxisAngle((nx, 0, nz), tum) * Angles(0, yaw, 0).
function Fall.pose(script: Script, index: number, t: number): (number, number, number, number, number)
	local s = script.blocks[index].s
	local count = #s / SEG
	local k = count
	for c = 2, count do
		if s[(c - 1) * SEG + 1] > t then
			k = c - 1
			break
		end
	end
	local o = (k - 1) * SEG
	local t0, kind = s[o + 1], s[o + 2]
	local x, y, z, yaw, tum = s[o + 3], s[o + 4], s[o + 5], s[o + 9], s[o + 11]
	local dt = math.max(t - t0, 0)
	if kind == 0 then
		local th = tipAt(script.tip, t)
		local ux, uz = script.ux, script.uz
		local du = (x - script.hx) * ux + (z - script.hz) * uz
		local dn = (x - script.hx) * uz - (z - script.hz) * ux
		local dy = y - script.hy
		local c, sn = math.cos(th), math.sin(th)
		local ru = du * c + dy * sn
		return script.hx + ru * ux + dn * uz, script.hy - du * sn + dy * c, script.hz + ru * uz - dn * ux, yaw, th
	elseif kind == 1 then
		return x + s[o + 6] * dt,
			y + s[o + 7] * dt - 0.5 * G * dt * dt,
			z + s[o + 8] * dt,
			yaw + s[o + 10] * dt,
			tum + s[o + 12] * dt
	elseif kind == 2 and k < count then
		local p = o + SEG
		local dur = math.max(s[p + 1] - t0, 1e-3)
		local u = math.min(dt / dur, 1)
		local e = 1 - (1 - u) * (1 - u)
		local nyaw = yaw + (s[p + 9] - yaw) * e
		local ntum = tum + (s[p + 11] - tum) * e
		-- sliding on a surface (the next segment starts on it): the height is exactly what keeps the block's
		-- lowest point on that surface
		local surfaceY = s[p + 4] - lowestOf(script.ux, script.uz, s[p + 9], s[p + 11])
		return x + (s[p + 3] - x) * e,
			surfaceY + lowestOf(script.ux, script.uz, nyaw, ntum),
			z + (s[p + 5] - z) * e,
			nyaw,
			ntum
	end
	return x, y, z, yaw, tum
end

function Fall.cues(script: Script): { Cue }
	return script.cues
end

function Fall.size(script: Script): number
	local total = 12 + #script.tip + #script.cues * 3
	for _, b in script.blocks do
		total += 1 + #b.s
	end
	return total
end

local function isNumber(v: any, limit: number): boolean
	return type(v) == "number" and v == v and math.abs(v) <= limit
end

-- check(any): a table off the wire is a script only if every part of it is in bounds; a client plays nothing
-- that fails this.
function Fall.check(raw: any): (Script?, string?)
	if type(raw) ~= "table" or raw.v ~= Fall.VERSION then
		return nil, "version"
	end
	for _, key in { "level", "ux", "uz", "hx", "hy", "hz", "tEnd" } do
		if not isNumber(raw[key], 1000) then
			return nil, key
		end
	end
	if raw.tEnd < 0 or raw.tEnd > 30 then
		return nil, "tEnd"
	end
	if type(raw.tip) ~= "table" or #raw.tip < 1 or #raw.tip > 400 then
		return nil, "tip"
	end
	for _, v in raw.tip do
		if not isNumber(v, 10) then
			return nil, "tip"
		end
	end
	if type(raw.blocks) ~= "table" or #raw.blocks ~= Layout.BLOCKS then
		return nil, "blocks"
	end
	local far = Layout.RAIL + L
	for index, b in raw.blocks do
		if type(b) ~= "table" or b.id ~= index or type(b.s) ~= "table" then
			return nil, "block"
		end
		local count = #b.s
		if count < SEG or count % SEG ~= 0 or count > SEG * 16 then
			return nil, "segments"
		end
		local last = -1
		for k = 1, count do
			if not isNumber(b.s[k], 1000) then
				return nil, "number"
			end
		end
		for c = 0, count / SEG - 1 do
			local o = c * SEG
			local t, kind = b.s[o + 1], b.s[o + 2]
			if t < last or t > 30 or (kind ~= 0 and kind ~= 1 and kind ~= 2 and kind ~= 3) then
				return nil, "segment"
			end
			last = t
			if math.abs(b.s[o + 3]) > far or math.abs(b.s[o + 5]) > far or b.s[o + 4] > 40 then
				return nil, "out of the deck"
			end
		end
		if b.s[count - SEG + 2] ~= 3 then
			return nil, "no rest"
		end
	end
	if type(raw.cues) ~= "table" or #raw.cues > 400 then
		return nil, "cues"
	end
	for _, c in raw.cues do
		if type(c) ~= "table" or not isNumber(c.t, 30) or type(c.name) ~= "string" or not isNumber(c.volume, 1) then
			return nil, "cue"
		end
	end
	return raw :: Script
end

-- Putting the tower back, level by level, for Play again: block `index` leaves where the collapse left it and
-- flies in an arc to its place in a fresh tower (block ids 1..54 fill levels 1..18 in order).
function Fall.restackTime(): number
	return Layout.BLOCKS * Fall.RESTACK_STEP + Fall.RESTACK_FLY
end

function Fall.restackPose(script: Script, index: number, t: number): (number, number, number, number, number)
	local s = script.blocks[index].s
	local o = #s - SEG
	local x0, y0, z0, yaw0, tum0 = s[o + 3], s[o + 4], s[o + 5], s[o + 9], s[o + 11]
	local level = math.floor((index - 1) / 3) + 1
	local slot = (index - 1) % 3 + 1
	local x1, y1, z1 = Layout.slotCentre(level, slot)
	local yaw1 = if Layout.alongX(level) then 0 else math.pi / 2
	local u = math.clamp((t - (index - 1) * Fall.RESTACK_STEP) / Fall.RESTACK_FLY, 0, 1)
	local e = u * u * (3 - 2 * u)
	-- the shortest way round for the yaw (a block looks the same turned half round)
	local dyaw = (yaw1 - yaw0) % math.pi
	if dyaw > math.pi / 2 then
		dyaw -= math.pi
	end
	local tum1 = math.floor(tum0 / math.pi + 0.5) * math.pi
	local hop = 4 * u * (1 - u) * 1.2
	return x0 + (x1 - x0) * e, y0 + (y1 - y0) * e + hop, z0 + (z1 - z0) * e, yaw0 + dyaw * e, tum0 + (tum1 - tum0) * e
end

return Fall
