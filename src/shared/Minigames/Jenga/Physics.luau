--!strict
-- ReplicatedStorage.Shared.Minigames.Jenga.Physics
-- The tower in motion, in fixed steps of DT with nothing hidden: the same tower and the same inputs give the
-- same tower on every machine (checklist JEN-P3, JEN-P4, JEN-P5, JEN-P6, JEN-P8; C1). No Roblox physics.
-- THE HAND. A grabbed block is joined to the player's hand by a short spring (an arm is not rigid). Friction
-- on the block's two faces is what the weight on it makes it (Stability's `load`): a loose block follows the
-- hand at once; a snug one holds until the spring is stretched past its static friction, then lets go and
-- catches again (it comes out in jerks, with a creak each time); a block that carries more than a hand can
-- pull only creeps, a hair at a time, with the whole of that pull going into the tower. Rough timber drags harder the faster it is dragged, so a yank pulls much harder
-- on the tower than a slow draw. Whatever the hand pulls with goes into the tower at that block's height, as
-- does any sideways wandering of the hand (less when the block is pushed through from the far end with a
-- fingertip, and less for a middle block guided by both neighbours). A block that carries most of its level
-- takes the levels above along with it, and those small shifts stay.
-- THE ROCKING. The part of the tower above each joint is a tall heavy body standing on the patch Stability
-- found. It sits on a full, stiff contact until the turning force on it moves the centre of pressure to the
-- patch's edge; then it lifts and rocks about that edge, slowly, the way a tall thing does, hanging near the
-- point where its weight is over the edge. If the weight goes past the edge the tower falls there (Fall draws
-- it); if not it drops back, loses speed in the knock, walks a hair sideways (remembered) and settles. Every
-- joint in both directions is judged every step. A tower nobody touches has no force on it and does not move
-- at all, for ever.
-- Pure; Lune-tested (tests/unit/jenga_physics.spec.luau).
-- Interface: DT; feel(tower, level, slot) -> Feel?; tap(tower, level, slot) -> Feel?; grab(tower, level,
--   slot, push) -> (ok, why?); drag(tower, along, lateral); letGo(tower) -> (ok, why?); step(tower);
--   run(tower, seconds); settle(tower, maxSeconds) -> seconds; place(tower, slot, along, across, speed) ->
--   (ok, why?); danger(tower) -> 0..1; atRest(tower) -> boolean; energy(tower) -> number; the constants below

local Layout = require("./Layout")
local Stability = require("./Stability")
local Tower = require("./Tower")

local Physics = {}

Physics.RATE = 60
Physics.DT = 1 / Physics.RATE

Physics.MU_K = 0.30 -- sliding friction of timber on timber at a crawl
Physics.MU_S = 0.42 -- static friction: what must be overcome to start a block
Physics.V_REF = 1.5 -- studs/s: sliding friction doubles at this speed (rough faces catch)
Physics.KH = 1800 -- the arm's spring, force per stud of stretch
Physics.MAX_FORCE = 15 * Layout.GRAVITY -- the hardest a hand pulls: fifteen block-weights
Physics.MAX_HAND_SPEED = 8 -- studs/s
Physics.PULL_JAM = 1.15 -- dragging by the near end lifts it and jams the far end: more friction than a push
Physics.PUSH_LATERAL = 0.4 -- a fingertip pushing on the end face passes on this much of the hand's wander
Physics.MIDDLE_GUIDE = 0.6 -- a middle block between two neighbours passes on this much of it
Physics.SLOP = 0.03 -- studs a held block can be pulled sideways in its slot
Physics.LAT_MAX = 0.3 -- studs of wander that count
Physics.SHEAR_LO = 0.5 -- a block carrying more than this share of its level starts to take the levels above
Physics.SHEAR_HI = 0.85 -- with it; at this share they go all the way with it
Physics.MICRO = 0.04 -- and any carrying block creeps the levels above by this much of its travel x share
Physics.STUCK_CREEP = 0.05 -- studs/s: a block too tight to slide still creeps under a hand's full pull
Physics.CREAK_LOAD = 1.5 -- block-weights of load before a starting block creaks
Physics.ZETA_E = 0.25 -- damping of the chatter on a full contact
Physics.ZETA_R = 0.02 -- damping while rocked up on an edge
Physics.HIT = 0.85 -- speed kept (beyond the geometric loss) when a rocking stack knocks back down
Physics.WALK = 0.03 -- studs a stack walks sideways per rad/s of that knock (remembered)
Physics.TAP = 6 -- the knock of a tap on a fully tight block (impulse, block-mass x studs/s)
Physics.HAND_MASS = 8 -- a block set down hard has the hand behind it (block-masses)
Physics.DROP_MAX = 6 -- studs/s
Physics.PLACE_ALONG = Layout.BLOCK_W / 2 -- a placed block may sit this far off square, along and across
Physics.PLACE_ACROSS = 0.08
Physics.PSI_SLEEP = 2e-5
Physics.OM_SLEEP = 2e-4
Physics.LOOSE_LOAD = 0.5 -- block-weights: carrying less than this is loose

local T, W, L = Layout.BLOCK_T, Layout.BLOCK_W, Layout.BLOCK_L
local G = Layout.GRAVITY
local DT = Physics.DT

-- What a tap tells you about a block (JEN-R3): free to taste, and true.
export type Feel = {
	kind: string, -- "loose" | "snug" | "tight"
	load: number, -- block-weights resting on it
	share: number, -- its part of the weight above its level, 0..1
	give: number, -- 0..1: how freely it jiggles (1 = rattles)
	hollow: boolean, -- the knock: hollow when loose, dull when it carries weight
	stuck: boolean, -- no hand could start it
}

-- The force pressing a block's two faces: the load on top, and that load plus its own weight underneath.
local function friction(an: Stability.Analysis, id: number, push: boolean): number
	local nf = 2 * an.load[id] + G
	if not push then
		nf *= Physics.PULL_JAM
	end
	return nf
end

function Physics.feel(tw: Tower.Tower, level: number, slot: number): Feel?
	local b = Tower.blockAt(tw, level, slot)
	if not b then
		return nil
	end
	local an = Stability.ensure(tw)
	local load = an.load[b.id] / G
	local share = an.share[b.id]
	local start = Physics.MU_S * (2 * an.load[b.id] + G)
	local kind = "snug"
	if load <= Physics.LOOSE_LOAD then
		kind = "loose"
	elseif share >= 0.6 or start >= 0.5 * Physics.MAX_FORCE then
		kind = "tight"
	end
	return {
		kind = kind,
		load = load,
		share = share,
		give = 1 / (1 + load / 4),
		hollow = kind == "loose",
		stuck = start >= Physics.MAX_FORCE,
	}
end

-- Add a sideways impulse (block-mass x studs/s) at height y to every stack it is part of.
local function knock(tw: Tower.Tower, an: Stability.Analysis, level: number, jx: number, jz: number)
	local y = (level - 0.5) * T
	for i = 0, math.min(level, an.n) - 1 do
		local arm = y - i * T
		local a = 2 * i + 1
		if jx ~= 0 and an.active[a] then
			tw.omX[i + 1] += jx * arm / an.inertia[a]
		end
		if jz ~= 0 and an.active[a + 1] then
			tw.omZ[i + 1] += jz * arm / an.inertia[a + 1]
		end
	end
end

-- tap(level, slot): knock on a block to feel it. Costs nothing on a loose block; a tight one passes the knock
-- on to the tower.
function Physics.tap(tw: Tower.Tower, level: number, slot: number): Feel?
	if tw.fallen then
		return nil
	end
	local f = Physics.feel(tw, level, slot)
	local b = Tower.blockAt(tw, level, slot)
	if not f or not b then
		return nil
	end
	local an = Stability.ensure(tw)
	local j = Physics.TAP * math.min(1, f.load / 8)
	if Layout.alongX(level) then
		knock(tw, an, level, j, 0)
	else
		knock(tw, an, level, 0, j)
	end
	Tower.emit(tw, "tap", b.id, f.give)
	return f
end

function Physics.grab(tw: Tower.Tower, level: number, slot: number, push: boolean): (boolean, string?)
	local ok, why = Tower.legal(tw, level, slot)
	if not ok then
		return false, why
	end
	if tw.inHand ~= 0 then
		return false, "you have a block in hand"
	end
	local b = Tower.blockAt(tw, level, slot) :: Tower.Block
	if tw.held ~= 0 and tw.held ~= b.id then
		return false, "one block at a time"
	end
	if tw.held == b.id then
		return true
	end
	tw.held = b.id
	tw.push = push
	tw.goal = b.along
	tw.hand = b.along
	tw.handLat = 0
	tw.sliding = false
	return true
end

-- drag(along, lateral): where the player's hand now wants the block along its length (studs from square, the
-- sign is the side it comes out of), and how far the hand has wandered off the block's line.
function Physics.drag(tw: Tower.Tower, along: number, lateral: number)
	if tw.held == 0 or along ~= along or lateral ~= lateral then
		return
	end
	tw.goal = math.clamp(along, -L - 0.2, L + 0.2)
	tw.handLat = math.clamp(lateral, -Physics.LAT_MAX, Physics.LAT_MAX)
end

-- letGo(): give up on the block in hand. Allowed until it is a third of the way out (JEN-R3); it stays where
-- it was left.
function Physics.letGo(tw: Tower.Tower): (boolean, string?)
	if tw.held == 0 then
		return false, "nothing held"
	end
	local b = tw.blocks[tw.held]
	if math.abs(b.along) >= Tower.COMMIT then
		return false, "it is yours now"
	end
	tw.held = 0
	tw.sliding = false
	tw.handLat = 0
	return true
end

local impactSpeed, impactSide = 0, 0

-- One joint, one direction, one step. Returns the new lean and rate and what happened: 0 nothing, 1 it knocked
-- back down onto its full contact, 2 it fell toward +, 3 it fell toward -.
local function rock(
	an: Stability.Analysis,
	j: number,
	h: number,
	weight: number,
	psi: number,
	om: number,
	ext: number
): (number, number, number)
	local kap, bL, bR, inertia = an.kap[j], an.bL[j], an.bR[j], an.inertia[j]
	local co = kap * psi
	local up = false
	if co > bR then
		co = bR
		up = true
	elseif co < -bL then
		co = -bL
		up = true
	end
	local damp
	if up then
		damp = 2 * Physics.ZETA_R * math.sqrt(weight * h * inertia)
	else
		damp = 2 * Physics.ZETA_E * inertia * Stability.OMEGA
	end
	local torque = ext - weight * (co - h * psi)
	om = (om + torque / inertia * DT) / (1 + damp / inertia * DT)
	local was = psi
	psi += om * DT
	if psi * h >= bR then
		return psi, om, 2
	elseif psi * h <= -bL then
		return psi, om, 3
	end
	if up then
		local co2 = kap * psi
		if co2 < bR and co2 > -bL then
			local b = if was > 0 then bR else bL
			impactSpeed = math.abs(om)
			impactSide = if was > 0 then 1 else -1
			om *= math.max(0.3, 1 - 1.5 * b * b / (b * b + h * h)) * Physics.HIT
			return psi, om, 1
		end
	end
	return psi, om, 0
end

local function fall(tw: Tower.Tower, f: Tower.Failure)
	tw.fallen = f
	tw.held = 0
	tw.sliding = false
	Tower.emit(tw, "fall", f.level, f.sign * (if f.dir == "x" then 1 else 2))
end

function Physics.step(tw: Tower.Tower)
	if tw.fallen then
		return
	end
	local an = Stability.ensure(tw)
	if not an.ok then
		fall(tw, an.fail :: Tower.Failure)
		return
	end
	local n = an.n
	local fX, fZ, kHeld = 0, 0, 0
	if tw.held ~= 0 then
		local b = tw.blocks[tw.held]
		local k = b.level
		kHeld = k
		local reach = Physics.MAX_HAND_SPEED * DT
		tw.hand += math.clamp(tw.goal - tw.hand, -reach, reach)
		local nf = friction(an, b.id, tw.push)
		local stretch = tw.hand - b.along
		local s = if stretch >= 0 then 1 else -1
		local a = math.abs(stretch)
		local fh = math.min(Physics.KH * a, Physics.MAX_FORCE)
		local kin = Physics.MU_K * nf
		local moved = 0
		if tw.sliding or fh > Physics.MU_S * nf then
			moved = (fh - kin) / (Physics.KH + kin / (Physics.V_REF * DT))
			if moved <= 0 then
				moved = 0
				tw.sliding = false
			else
				if not tw.sliding then
					tw.sliding = true
					if an.load[b.id] > Physics.CREAK_LOAD * G then
						Tower.emit(tw, "creak", b.id, an.load[b.id] / G)
					end
				end
				if moved > a then
					moved = a
				end
				fh = math.min(Physics.KH * (a - moved), Physics.MAX_FORCE)
			end
		end
		if moved == 0 and fh >= 0.98 * Physics.MAX_FORCE then
			-- stuck fast with the hand pulling as hard as it can: it is worried out a hair at a time
			moved = Physics.STUCK_CREEP * DT
			if tw.step % 30 == 0 then
				Tower.emit(tw, "creak", b.id, an.load[b.id] / G)
			end
		end
		if moved > 0 then
			b.along += s * moved
			local share = an.share[b.id]
			local carry = math.clamp((share - Physics.SHEAR_LO) / (Physics.SHEAR_HI - Physics.SHEAR_LO), 0, 1)
				+ Physics.MICRO * share
			if carry > 0 and k < n then
				local d = s * moved * math.min(carry, 1)
				if Layout.alongX(k) then
					tw.shiftX[k + 1] += d
				else
					tw.shiftZ[k + 1] += d
				end
			end
			tw.stale = true
		end
		local w = tw.handLat
		local cap = Physics.MU_S * nf
		local fl = math.clamp(Physics.KH * w, -cap, cap)
		if tw.push then
			fl *= Physics.PUSH_LATERAL
		end
		local row = tw.levels[k]
		if b.slot == 2 and row[1] ~= 0 and row[3] ~= 0 then
			fl *= Physics.MIDDLE_GUIDE
		end
		local want = math.clamp(w, -Physics.SLOP, Physics.SLOP)
		if b.across ~= want then
			local diff = want - b.across
			b.across = if math.abs(diff) < 1e-4 then want else b.across + diff * 0.25
			tw.stale = true
		end
		if Layout.alongX(k) then
			fX, fZ = s * fh, fl
		else
			fX, fZ = fl, s * fh
		end
		if math.abs(b.along) >= L then
			-- clear of the tower: it is in the player's hand now
			row[b.slot] = 0
			b.level = 0
			b.along, b.across = 0, 0
			tw.held = 0
			tw.sliding = false
			tw.handLat = 0
			tw.inHand = b.id
			tw.moved += 1
			tw.rev += 1
			tw.stale = true
			Tower.emit(tw, "out", b.id, k)
		end
	end

	local psiX, omX, psiZ, omZ = tw.psiX, tw.omX, tw.psiZ, tw.omZ
	local active, mass, height = an.active, an.mass, an.h
	local yF = (kHeld - 0.5) * T
	local sleepP, sleepO = Physics.PSI_SLEEP, Physics.OM_SLEEP
	for i = 0, n - 1 do
		local idx = i + 1
		local arm = if i < kHeld then yF - i * T else 0
		local j = 2 * i + 1
		if active[j] then
			local psi, om = psiX[idx], omX[idx]
			local ext = fX * arm
			if psi ~= 0 or om ~= 0 or ext ~= 0 then
				local what
				psi, om, what = rock(an, j, height[idx], G * mass[idx], psi, om, ext)
				if what >= 2 then
					psiX[idx], omX[idx] = psi, om
					fall(tw, { level = i, dir = "x", sign = if what == 2 then 1 else -1, why = "sway" })
					break
				elseif what == 1 then
					tw.shiftX[idx] += Physics.WALK * impactSpeed * impactSide
					tw.stale = true
					if impactSpeed > 0.05 then
						Tower.emit(tw, "clunk", i, impactSpeed)
					end
				elseif ext == 0 and math.abs(psi) < sleepP and math.abs(om) < sleepO then
					psi, om = 0, 0
				end
				psiX[idx], omX[idx] = psi, om
			end
		end
		j += 1
		if active[j] then
			local psi, om = psiZ[idx], omZ[idx]
			local ext = fZ * arm
			if psi ~= 0 or om ~= 0 or ext ~= 0 then
				local what
				psi, om, what = rock(an, j, height[idx], G * mass[idx], psi, om, ext)
				if what >= 2 then
					psiZ[idx], omZ[idx] = psi, om
					fall(tw, { level = i, dir = "z", sign = if what == 2 then 1 else -1, why = "sway" })
					break
				elseif what == 1 then
					tw.shiftZ[idx] += Physics.WALK * impactSpeed * impactSide
					tw.stale = true
					if impactSpeed > 0.05 then
						Tower.emit(tw, "clunk", i, impactSpeed)
					end
				elseif ext == 0 and math.abs(psi) < sleepP and math.abs(om) < sleepO then
					psi, om = 0, 0
				end
				psiZ[idx], omZ[idx] = psi, om
			end
		end
	end
	tw.step += 1
end

function Physics.run(tw: Tower.Tower, seconds: number)
	for _ = 1, math.floor(seconds * Physics.RATE + 0.5) do
		Physics.step(tw)
	end
end

-- atRest(): nothing rocking and no block on the move.
function Physics.atRest(tw: Tower.Tower): boolean
	if tw.sliding then
		return false
	end
	for i = 1, #tw.levels do
		if tw.psiX[i] ~= 0 or tw.omX[i] ~= 0 or tw.psiZ[i] ~= 0 or tw.omZ[i] ~= 0 then
			return false
		end
	end
	return true
end

-- settle(maxSeconds): step until the tower is at rest or down; returns how long that took.
function Physics.settle(tw: Tower.Tower, maxSeconds: number): number
	local steps = 0
	local most = math.floor(maxSeconds * Physics.RATE + 0.5)
	while steps < most and not tw.fallen do
		Physics.step(tw)
		steps += 1
		if not tw.stale and Physics.atRest(tw) then
			break
		end
	end
	return steps * DT
end

-- place(slot, along, across, speed): set the block in hand on top (JEN-P4). `along` and `across` are how far
-- off square it is put, `speed` how hard it comes down (0 = set down gently).
function Physics.place(tw: Tower.Tower, slot: number, along: number, across: number, speed: number): (boolean, string?)
	if tw.fallen then
		return false, "the tower is down"
	end
	if tw.inHand == 0 then
		return false, "no block in hand"
	end
	if along ~= along or across ~= across or speed ~= speed then
		return false, "args"
	end
	local level, free = Tower.building(tw)
	if table.find(free, slot) == nil then
		return false, "that place is taken"
	end
	local an = Stability.ensure(tw)
	local n = #tw.levels
	if level > n then
		tw.levels[level] = { 0, 0, 0 }
		tw.shiftX[level], tw.shiftZ[level] = 0, 0
		tw.psiX[level], tw.omX[level], tw.psiZ[level], tw.omZ[level] = 0, 0, 0, 0
	end
	local b = tw.blocks[tw.inHand]
	b.level = level
	b.slot = slot
	b.along = math.clamp(along, -Physics.PLACE_ALONG, Physics.PLACE_ALONG)
	b.across = math.clamp(across, -Physics.PLACE_ACROSS, Physics.PLACE_ACROSS)
	tw.levels[level][slot] = b.id
	local v = math.clamp(speed, 0, Physics.DROP_MAX)
	if v > 0 then
		local sx = an.sx[math.min(level, n)]
		local sz = an.sz[math.min(level, n)]
		local off = (slot - 2) * W + b.across
		local px, pz
		if Layout.alongX(level) then
			px, pz = sx + b.along, sz + off
		else
			px, pz = sx + off, sz + b.along
		end
		local jolt = Physics.HAND_MASS * v
		for i = 0, math.min(level, n) - 1 do
			local a = 2 * i + 1
			if an.active[a] then
				tw.omX[i + 1] += jolt * (px - an.base[a]) / an.inertia[a]
			end
			if an.active[a + 1] then
				tw.omZ[i + 1] += jolt * (pz - an.base[a + 1]) / an.inertia[a + 1]
			end
		end
	end
	tw.inHand = 0
	tw.rev += 1
	tw.stale = true
	Tower.emit(tw, "place", b.id, v)
	return true
end

-- danger(): 0 when nothing rocks, 1 when some part of the tower has its weight right over the edge.
function Physics.danger(tw: Tower.Tower): number
	if tw.fallen then
		return 1
	end
	local an = Stability.ensure(tw)
	local worst = 0
	for i = 0, an.n - 1 do
		local h = an.h[i + 1]
		for d = 1, 2 do
			local j = 2 * i + d
			if an.active[j] then
				local psi = if d == 1 then tw.psiX[i + 1] else tw.psiZ[i + 1]
				if psi ~= 0 then
					local r = if psi > 0 then psi * h / an.bR[j] else -psi * h / an.bL[j]
					worst = if r > worst then r else worst
				end
			end
		end
	end
	return math.min(worst, 1)
end

-- energy(): the rocking energy in the tower (kinetic plus what it takes to lean each stack to where it is),
-- for the specs: with nobody touching it this never grows.
function Physics.energy(tw: Tower.Tower): number
	local an = Stability.ensure(tw)
	local sum = 0
	for i = 0, an.n - 1 do
		local h, weight = an.h[i + 1], G * an.mass[i + 1]
		for d = 1, 2 do
			local j = 2 * i + d
			if an.active[j] then
				local psi = if d == 1 then tw.psiX[i + 1] else tw.psiZ[i + 1]
				local om = if d == 1 then tw.omX[i + 1] else tw.omZ[i + 1]
				local kap = an.kap[j]
				local b = if psi > 0 then an.bR[j] else an.bL[j]
				local x = math.abs(psi)
				local edge = b / kap
				local u = if x <= edge then 0.5 * kap * x * x else 0.5 * b * edge + b * (x - edge)
				sum += 0.5 * an.inertia[j] * om * om + weight * (u - 0.5 * h * x * x)
			end
		end
	end
	return sum
end

return Physics
