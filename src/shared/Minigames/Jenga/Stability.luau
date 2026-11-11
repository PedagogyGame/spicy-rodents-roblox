--!strict
-- ReplicatedStorage.Shared.Minigames.Jenga.Stability
-- The judgement of a tower: worked out, never rolled (checklist JEN-P1, JEN-P2, JEN-P5, JEN-P6).
-- For the joint on top of every level (and the one on the table) it finds, from the blocks that are really
-- there and exactly where they have drifted to:
--   * the weight of everything above and where that weight's centre sits (crookedness included: slid blocks,
--     shifted levels and the lean the levels below have given it),
--   * the patch that can hold it: across the lower level's blocks, from the outer edge of its first block to
--     the outer edge of its last (two side blocks or the middle alone hold a centred weight; one side block
--     does not); along them, the span of the upper level's blocks that rest on them,
--   * the MARGIN: how far the weight's centre is inside that patch on each side. No margin, no tower.
--   * which blocks CARRY the weight: the level above is stiff and the blocks are not all the same thickness,
--     so it rests on the proud ones and the others carry little or nothing (a contact solve over each block's
--     two edges; `load` is the force on each block from above, `share` its part of the weight above). A loose
--     block slides out for the asking, a load-bearing one drags the tower with it. As blocks leave, the load
--     moves and the level above tips a hair onto what is left (`tilt`), which is how a tower grows crooked.
--   * what Physics needs to rock the part above each joint: arm, inertia, contact stiffness.
-- Force is in block-weights x Layout.GRAVITY (a block's mass is 1). Joint i is the one on top of level i
-- (i = 0: the table); per-joint, per-direction values are stored at index 2 * i + d (d = 1 for X, 2 for Z).
-- Pure; Lune-tested (tests/unit/jenga_stability.spec.luau).
-- Interface: analyse(tower, into?) -> Analysis; ensure(tower) -> Analysis (cached; keeps the drawn pose
--   continuous when the resting pose changes); stands(tower) -> (boolean, Failure?); margin(tower) -> studs;
--   poses(tower, out?) -> { x, y, z, yaw, leanX, leanZ per block id }; at(i, d) -> index; KBLOCK, OMEGA

local Layout = require("./Layout")
local Tower = require("./Tower")

local Stability = {}

Stability.KBLOCK = 3.0e5 -- how stiffly a block resists being squashed (force per stud), for sharing the load
Stability.OMEGA = 40 -- rad/s: how fast a stack chatters back onto a full contact (sets the contact stiffness)
Stability.PSI_ACTIVE = 0.6 -- stacks that would have to lean further than this to fall are too squat to rock
Stability.TILT_MAX = 0.03 -- rad: the most one level can tip the level above it
Stability.SELF_INERTIA = 0.16 -- a block's own inertia about its middle (mass 1): (L^2 + T^2) / 12

local T, W, L = Layout.BLOCK_T, Layout.BLOCK_W, Layout.BLOCK_L
local HW, HL = W / 2, L / 2
local G = Layout.GRAVITY
local EPS = 1e-6
local HUGE = math.huge

export type Analysis = {
	n: number,
	ok: boolean,
	fail: Tower.Failure?,
	margin: number, -- the smallest margin anywhere, studs
	marginJoint: number,
	load: { number }, -- by block id
	share: { number }, -- by block id
	lo: { number },
	hi: { number },
	base: { number }, -- where the weight above rests when nothing rocks
	tilt: { number }, -- resting lean of the part above this joint (rad, toward +d)
	bL: { number },
	bR: { number },
	inertia: { number },
	kap: { number },
	active: { boolean },
	mass: { number }, -- blocks above joint i, at index i + 1
	h: { number }, -- height of their centre above the joint, at index i + 1
	sx: { number }, -- each level's total shift
	sz: { number },
	prev: { number }, -- the last analysis's tilts (ensure)
}

function Stability.at(i: number, d: number): number
	return 2 * i + d
end

local function newAnalysis(): Analysis
	return {
		n = 0,
		ok = true,
		fail = nil,
		margin = 0,
		marginJoint = 0,
		load = table.create(Layout.BLOCKS, 0),
		share = table.create(Layout.BLOCKS, 0),
		lo = {},
		hi = {},
		base = {},
		tilt = {},
		bL = {},
		bR = {},
		inertia = {},
		kap = {},
		active = {},
		mass = {},
		h = {},
		sx = {},
		sz = {},
		prev = {},
	}
end

-- Scratch for one joint (no allocation per analysis).
local sp, sk, sh, sf = table.create(6, 0), table.create(6, 0), table.create(6, 0), table.create(6, 0)
local sact: { boolean } = table.create(6, false)
local sown = table.create(6, 0)
local ua, ub = table.create(3, 0), table.create(3, 0)
local la, lb, lh, lid = table.create(3, 0), table.create(3, 0), table.create(3, 0), table.create(3, 0)

local function overlap(lo1: number, hi1: number, lo2: number, hi2: number): number
	local lo = if lo1 > lo2 then lo1 else lo2
	local hi = if hi1 < hi2 then hi1 else hi2
	return if hi > lo then hi - lo else 0
end

-- A stiff plate carrying `load` at position e, resting on m springs (position sp, stiffness sk, free height
-- sh) that can only push. Fills sf with each spring's force and returns the plate's slope. False when the load
-- is not over the springs at all.
local function solve(m: number, load: number, e: number): (boolean, number)
	if m == 0 then
		return false, 0
	end
	local lo, hi = HUGE, -HUGE
	for j = 1, m do
		local p = sp[j]
		lo = if p < lo then p else lo
		hi = if p > hi then p else hi
		sact[j] = true
	end
	if e <= lo or e >= hi then
		for j = 1, m do
			sf[j] = 0
		end
		return false, 0
	end
	local phi = 0
	for pass = 1, 8 do
		local Sk, Skp, Skpp, Skh, Skhp = 0, 0, 0, 0, 0
		for j = 1, m do
			if sact[j] then
				local p, k, hgt = sp[j] - e, sk[j], sh[j]
				Sk += k
				Skp += k * p
				Skpp += k * p * p
				Skh += k * hgt
				Skhp += k * hgt * p
			end
		end
		local det = Sk * Skpp - Skp * Skp
		local last = pass == 8
		if det <= 1e-9 * Sk * Sk * W * W then
			-- every spring still pushing is at one spot: fall back to all of them (cannot happen with a load
			-- strictly inside the span unless the numbers are degenerate)
			for j = 1, m do
				sact[j] = true
			end
			last = true
			Sk, Skp, Skpp, Skh, Skhp = 0, 0, 0, 0, 0
			for j = 1, m do
				local p, k, hgt = sp[j] - e, sk[j], sh[j]
				Sk += k
				Skp += k * p
				Skpp += k * p * p
				Skh += k * hgt
				Skhp += k * hgt * p
			end
			det = Sk * Skpp - Skp * Skp
			if det <= 0 then
				return false, 0
			end
		end
		local r1, r2 = Skh - load, Skhp
		local y0 = (r1 * Skpp - r2 * Skp) / det
		phi = (Sk * r2 - Skp * r1) / det
		local changed = false
		local sum = 0
		for j = 1, m do
			local d = sh[j] - y0 - phi * (sp[j] - e)
			local pushing = d > 0
			if pushing ~= sact[j] then
				changed = true
				sact[j] = pushing
			end
			local f = if pushing then sk[j] * d else 0
			sf[j] = f
			sum += f
		end
		if not changed or last then
			if sum > 0 then
				local scale = load / sum
				for j = 1, m do
					sf[j] *= scale
				end
			end
			break
		end
	end
	return true, phi
end

function Stability.analyse(tw: Tower.Tower, into: Analysis?): Analysis
	local an = into or newAnalysis()
	local levels, blocks = tw.levels, tw.blocks
	local n = #levels
	an.n = n
	an.ok = true
	an.fail = nil
	local SX, SZ = an.sx, an.sz
	local sx, sz = 0, 0
	for k = 1, n do
		sx += tw.shiftX[k]
		sz += tw.shiftZ[k]
		SX[k] = sx
		SZ[k] = sz
	end
	local load, share = an.load, an.share
	for id = 1, #blocks do
		load[id] = 0
		share[id] = 0
	end
	local aLo, aHi, aBase, aTilt = an.lo, an.hi, an.base, an.tilt
	local aBL, aBR, aI, aKap, aAct = an.bL, an.bR, an.inertia, an.kap, an.active
	local worst, worstJoint = HUGE, 0
	local failDepth = 0
	local kb = Stability.KBLOCK
	local omega2 = Stability.OMEGA * Stability.OMEGA

	local M, MX, MZ, MY, MYY = 0, 0, 0, 0, 0 -- sums over the levels above joint i
	local leanX, leanZ = 0, 0 -- sum of tilt x mass x height over the joints above
	for i = n - 1, 0, -1 do
		local k = i + 1
		local upRow = levels[k]
		local upX = k % 2 == 1 -- the upper level's blocks run along X
		local yk = (k - 0.5) * T
		local nUp = 0
		for s = 1, 3 do
			local id = upRow[s]
			if id ~= 0 then
				local b = blocks[id]
				local off = (s - 2) * W + b.across
				local bx, bz
				if upX then
					bx, bz = SX[k] + b.along, SZ[k] + off
				else
					bx, bz = SX[k] + off, SZ[k] + b.along
				end
				M += 1
				MX += bx
				MZ += bz
				MY += yk
				MYY += yk * yk
				nUp += 1
				-- in the joint's frame: A is the direction ACROSS the upper blocks, B along them
				if upX then
					ua[nUp], ub[nUp] = bz, bx
				else
					ua[nUp], ub[nUp] = bx, bz
				end
			end
		end
		local yi = i * T
		local h = if M > 0 then MY / M - yi else 0
		local I0 = MYY - 2 * yi * MY + yi * yi * M + M * Stability.SELF_INERTIA
		local weight = G * M
		local eX = if M > 0 then (MX + leanX) / M else 0
		local eZ = if M > 0 then (MZ + leanZ) / M else 0
		-- B (along the upper blocks, across the lower ones) is X when the upper level runs along X
		local eB = if upX then eX else eZ

		local loA, hiA, loB, hiB = HUGE, -HUGE, HUGE, -HUGE
		local tiltB = 0
		if i == 0 then
			-- on the table: every block of level 1 is held along its whole length
			for u = 1, nUp do
				loA = math.min(loA, ua[u] - HW)
				hiA = math.max(hiA, ua[u] + HW)
				loB = math.min(loB, ub[u] - HL)
				hiB = math.max(hiB, ub[u] + HL)
			end
		else
			local lowRow = levels[i]
			local nLow = 0
			for s = 1, 3 do
				local id = lowRow[s]
				if id ~= 0 then
					local b = blocks[id]
					nLow += 1
					local off = (s - 2) * W + b.across
					-- the lower level runs along A: its blocks sit side by side along B
					if upX then
						la[nLow], lb[nLow] = SZ[i] + b.along, SX[i] + off
					else
						la[nLow], lb[nLow] = SX[i] + b.along, SZ[i] + off
					end
					lh[nLow] = b.dt
					lid[nLow] = id
				end
			end
			-- along A: the edges of the upper blocks that rest on something
			local upEndLo, upEndHi = HUGE, -HUGE
			for u = 1, nUp do
				local ov = 0
				for l = 1, nLow do
					ov += overlap(ub[u] - HL, ub[u] + HL, lb[l] - HW, lb[l] + HW)
				end
				if ov > EPS then
					loA = math.min(loA, ua[u] - HW)
					hiA = math.max(hiA, ua[u] + HW)
					upEndLo = math.min(upEndLo, ub[u] - HL)
					upEndHi = math.max(upEndHi, ub[u] + HL)
				end
			end
			-- along B: the edges of the lower blocks that hold something up, as springs
			local lowEndLo, lowEndHi = HUGE, -HUGE
			local m = 0
			for l = 1, nLow do
				local ov = 0
				for u = 1, nUp do
					ov += overlap(la[l] - HL, la[l] + HL, ua[u] - HW, ua[u] + HW)
				end
				if ov > EPS then
					local kEdge = kb * 0.5 * ov / (W * nUp)
					m += 1
					sp[m], sk[m], sh[m], sown[m] = lb[l] - HW, kEdge, lh[l], lid[l]
					m += 1
					sp[m], sk[m], sh[m], sown[m] = lb[l] + HW, kEdge, lh[l], lid[l]
					loB = math.min(loB, lb[l] - HW)
					hiB = math.max(hiB, lb[l] + HW)
					lowEndLo = math.min(lowEndLo, la[l] - HL)
					lowEndHi = math.max(lowEndHi, la[l] + HL)
				end
			end
			loA = math.max(loA, lowEndLo)
			hiA = math.min(hiA, lowEndHi)
			loB = math.max(loB, upEndLo)
			hiB = math.min(hiB, upEndHi)
			if weight > 0 then
				local ok, phi = solve(m, weight, eB)
				if ok then
					for j = 1, m do
						load[sown[j]] += sf[j]
					end
					for l = 1, nLow do
						share[lid[l]] = load[lid[l]] / weight
					end
					tiltB = math.clamp(-phi, -Stability.TILT_MAX, Stability.TILT_MAX)
				end
			end
		end

		-- back to X and Z
		local loX, hiX, loZ, hiZ, tiltX, tiltZ
		if upX then
			loZ, hiZ, loX, hiX, tiltZ, tiltX = loA, hiA, loB, hiB, 0, tiltB
		else
			loX, hiX, loZ, hiZ, tiltX, tiltZ = loA, hiA, loB, hiB, 0, tiltB
		end
		an.mass[k] = M
		an.h[k] = h
		for d = 1, 2 do
			local j = 2 * i + d
			local lo, hi, tilt, e
			if d == 1 then
				lo, hi, tilt, e = loX, hiX, tiltX, eX
			else
				lo, hi, tilt, e = loZ, hiZ, tiltZ, eZ
			end
			local base = e + tilt * h
			local bL, bR = base - lo, hi - base
			aLo[j], aHi[j], aBase[j], aTilt[j] = lo, hi, base, tilt
			aBL[j], aBR[j] = bL, bR
			local least = if bL < bR then bL else bR
			if M > 0 then
				if least < worst then
					worst, worstJoint = least, i
				end
				if least <= 0 and least < failDepth then
					failDepth = least
					an.ok = false
					an.fail = {
						level = i,
						dir = if d == 1 then "x" else "z",
						sign = if bR <= bL then 1 else -1,
						why = if lo > hi then "gone" else "balance",
					}
				end
			end
			local most = math.max(bL, bR, 0)
			local inertia = I0 + M * most * most
			aI[j] = inertia
			aKap[j] = if weight > 0 then inertia * omega2 / weight else 0
			aAct[j] = M > 0 and least > 0 and h > 0 and least / h < Stability.PSI_ACTIVE
		end
		leanX += tiltX * M * h
		leanZ += tiltZ * M * h
	end
	an.margin = if worst == HUGE then 0 else worst
	an.marginJoint = worstJoint
	return an
end

-- ensure(tower): the analysis of the tower as it is now, recomputed only when something moved. When the
-- resting lean of a joint changes (a block left and the level above tipped onto what is left), the part above
-- does not jump there: it is left where it was, off its new rest by the difference, and Physics lets it rock
-- home. A slow change is followed quietly; a sudden one is a clunk and a wobble (JEN-P3).
function Stability.ensure(tw: Tower.Tower): Analysis
	local old: Analysis? = tw.an
	if old and not tw.stale then
		return old
	end
	local had = 0
	if old then
		had = 2 * old.n
		local prev, tilt = old.prev, old.tilt
		for j = 1, had do
			prev[j] = tilt[j]
		end
	end
	local an = Stability.analyse(tw, old)
	tw.an = an
	tw.stale = false
	local n = an.n
	local psiX, psiZ, omX, omZ = tw.psiX, tw.psiZ, tw.omX, tw.omZ
	for i = 0, n - 1 do
		local jx, jz = 2 * i + 1, 2 * i + 2
		if an.active[jx] then
			if jx <= had then
				psiX[i + 1] += an.prev[jx] - an.tilt[jx]
			end
		else
			psiX[i + 1], omX[i + 1] = 0, 0
		end
		if an.active[jz] then
			if jz <= had then
				psiZ[i + 1] += an.prev[jz] - an.tilt[jz]
			end
		else
			psiZ[i + 1], omZ[i + 1] = 0, 0
		end
	end
	return an
end

-- stands(tower): does it hold with nothing moving? (JEN-P2)
function Stability.stands(tw: Tower.Tower): (boolean, Tower.Failure?)
	local an = Stability.ensure(tw)
	return an.ok, an.fail
end

function Stability.margin(tw: Tower.Tower): number
	return Stability.ensure(tw).margin
end

-- poses(tower, out?): where every block is drawn (table frame), rocking and crookedness included: six numbers
-- per block id (x, y, z, yaw, lean toward +X, lean toward +Z; radians). A block that is not in the tower has
-- y = -1. The lean is small: the client tips the block by it about its own middle.
function Stability.poses(tw: Tower.Tower, out: { number }?): { number }
	local an = Stability.ensure(tw)
	local res = out or table.create(Layout.BLOCKS * 6, 0)
	local n = an.n
	local blocks = tw.blocks
	for id = 1, #blocks do
		if blocks[id].level == 0 then
			local o = (id - 1) * 6
			res[o + 1], res[o + 2], res[o + 3], res[o + 4], res[o + 5], res[o + 6] = 0, -1, 0, 0, 0, 0
		end
	end
	local leanX, leanZ, dispX, dispZ, lift = 0, 0, 0, 0, 0
	for k = 1, n do
		local i = k - 1
		local jx, jz = 2 * i + 1, 2 * i + 2
		local px, pz = tw.psiX[k], tw.psiZ[k]
		local tx, tz = an.tilt[jx] + px, an.tilt[jz] + pz
		-- this level's middle is half a block above joint i, and a whole block above the level below
		dispX += T * leanX + 0.5 * T * tx
		dispZ += T * leanZ + 0.5 * T * tz
		leanX += tx
		leanZ += tz
		-- a rocking stack pivots on the edge it leans over, so it rises a little
		if px ~= 0 then
			lift += math.abs(px) * (if px > 0 then an.bR[jx] else an.bL[jx])
		end
		if pz ~= 0 then
			lift += math.abs(pz) * (if pz > 0 then an.bR[jz] else an.bL[jz])
		end
		local row = tw.levels[k]
		local alongX = k % 2 == 1
		local y = (k - 0.5) * T + lift
		for s = 1, 3 do
			local id = row[s]
			if id ~= 0 then
				local b = blocks[id]
				local off = (s - 2) * W + b.across
				local o = (id - 1) * 6
				if alongX then
					res[o + 1] = an.sx[k] + dispX + b.along
					res[o + 3] = an.sz[k] + dispZ + off
					res[o + 4] = 0
				else
					res[o + 1] = an.sx[k] + dispX + off
					res[o + 3] = an.sz[k] + dispZ + b.along
					res[o + 4] = math.pi / 2
				end
				res[o + 2] = y
				res[o + 5] = leanX
				res[o + 6] = leanZ
			end
		end
	end
	return res
end

return Stability
