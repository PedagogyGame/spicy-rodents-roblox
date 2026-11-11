--!strict
-- Minigames/Jenga: Layout, Tower and Stability (checklist JEN-R1, JEN-R2, JEN-P1, JEN-P2, JEN-P5, JEN-P6): the
-- tower is four feet of 54 blocks; which blocks may be taken and where a block in hand goes; which blocks carry
-- the weight and which carry none (and that this changes as blocks leave); standing or falling worked out from
-- what is left of every level; crookedness counted; what a client draws.
local Layout = require("@shared/Minigames/Jenga/Layout")
local Physics = require("@shared/Minigames/Jenga/Physics")
local Stability = require("@shared/Minigames/Jenga/Stability")
local Tower = require("@shared/Minigames/Jenga/Tower")

local G = Layout.GRAVITY
local W, L, T = Layout.BLOCK_W, Layout.BLOCK_L, Layout.BLOCK_T

local function take(tw: Tower.Tower, level: number, slot: number)
	local id = tw.levels[level][slot]
	assert(id ~= 0, "no block there")
	tw.levels[level][slot] = 0
	tw.blocks[id].level = 0
	Tower.touch(tw)
end

-- a tower whose blocks are all exactly the same thickness (so the load is shared evenly)
local function uniform(): Tower.Tower
	local tw = Tower.new(1)
	for _, b in tw.blocks do
		b.dt = 0
	end
	Tower.touch(tw)
	return tw
end

return function(t)
	t.test("JEN-R1 layout: 54 blocks, 18 levels of three, each across the one below, four feet tall", function()
		t.eq(Layout.BLOCKS, 54)
		t.eq(Layout.START_LEVELS * Layout.PER_LEVEL, 54)
		t.near(L, 3 * W, 1e-9, "three widths make a square")
		-- 3.8 studs to the metre: four feet is 1.2192 m
		t.near(Layout.TOWER_H / 3.8, 1.2192, 0.03, "four feet")
		t.truthy(Layout.alongX(1) and not Layout.alongX(2) and Layout.alongX(3), "levels alternate")
		local x, y, z = Layout.slotCentre(1, 3)
		t.near(x, 0, 1e-9)
		t.near(y, T / 2, 1e-9)
		t.near(z, W, 1e-9)
		x, y, z = Layout.slotCentre(2, 1)
		t.near(x, -W, 1e-9)
		t.near(y, 1.5 * T, 1e-9)
		t.near(z, 0, 1e-9)
		-- the tower fits the table with room for a fallen block, and four people stand round it
		t.truthy(Layout.TABLE_HALF > L, "table")
		for i = 1, 4 do
			local sx, sz = Layout.seat(i)
			t.near(math.sqrt(sx * sx + sz * sz), Layout.STAND, 1e-9)
		end
		local wx, wy, wz = Layout.toWorld({ x = 85, y = 2.7, z = 60, yaw = 0 }, 1, 2, 3)
		t.near(wx, 86, 1e-9)
		t.near(wy, 4.7, 1e-9)
		t.near(wz, 63, 1e-9)

		local tw = Tower.new(7)
		t.eq(#tw.blocks, 54)
		t.eq(#tw.levels, 18)
		local levels, complete = Tower.levelsOf(tw)
		t.eq(levels, 18)
		t.eq(complete, 18)
		for _, b in tw.blocks do
			t.truthy(math.abs(b.dt) <= Tower.THICK_VAR, "thickness error in bounds")
		end
		-- the seed decides the timber: same seed, same tower; another seed, another tower
		t.eq(Tower.encode(Tower.new(7)), Tower.encode(tw))
		t.neq(Tower.encode(Tower.new(8)), Tower.encode(tw))
	end)

	t.test("JEN-R2 which blocks may be taken, and where a block in hand goes", function()
		local tw = Tower.new(3)
		t.eq(Tower.highestComplete(tw), 18)
		t.truthy(Tower.legal(tw, 17, 1), "below the highest complete level")
		t.truthy(Tower.legal(tw, 1, 2))
		local ok, why = Tower.legal(tw, 18, 2)
		t.falsy(ok, "not from the highest complete level")
		t.truthy(why ~= nil)
		t.falsy((Tower.legal(tw, 19, 1)))
		t.falsy((Tower.legal(tw, 5, 4)))
		t.falsy((Tower.legal(tw, 5.5, 1)))
		-- a complete top: the block in hand starts a new level, anywhere on it
		local level, free = Tower.building(tw)
		t.eq(level, 19)
		t.eq(#free, 3)
		-- an unfinished top is finished first, and the level under it is then the highest complete one
		take(tw, 10, 1)
		tw.inHand = 28
		t.truthy(Physics.place(tw, 2, 0, 0, 0))
		level, free = Tower.building(tw)
		t.eq(level, 19)
		t.deepEq(free, { 1, 3 })
		t.eq(Tower.highestComplete(tw), 18)
		t.falsy((Tower.legal(tw, 19, 2)), "never from the unfinished top")
		t.falsy((Tower.legal(tw, 18, 2)), "nor from the highest complete level under it")
		t.truthy(Tower.legal(tw, 17, 2))
		t.falsy((Tower.legal(tw, 10, 1)), "a gap is not a block")
	end)

	t.test("JEN-P1 the load on every level adds up, and some blocks carry it while some carry none", function()
		local looseTotal = 0
		for seed = 1, 20 do
			local tw = Tower.new(seed)
			local an = Stability.ensure(tw)
			t.truthy(an.ok, "a fresh tower stands")
			for level = 1, 17 do
				local sum, most = 0, 0
				for slot = 1, 3 do
					local id = tw.levels[level][slot]
					sum += an.load[id]
					most = math.max(most, an.share[id])
					t.truthy(an.load[id] >= 0, "blocks only push")
					if an.load[id] < Physics.LOOSE_LOAD * G then
						looseTotal += 1
					end
				end
				-- everything above this level rests on its three blocks, no more and no less
				t.near(sum, G * 3 * (18 - level), 1e-6 * sum, `seed {seed} level {level}`)
				t.truthy(most > 0.34, "somebody carries more than a fair third")
			end
			-- the top level carries nothing
			for slot = 1, 3 do
				t.eq(an.load[tw.levels[18][slot]], 0)
			end
		end
		-- about a fifth of the 51 are loose on a fresh tower (statistical band on fixed seeds)
		local mean = looseTotal / 20
		t.truthy(mean > 6 and mean < 18, `loose blocks per fresh tower {mean}`)
		-- with timber all the same thickness, a centred weight is shared evenly
		local tw = uniform()
		local an = Stability.ensure(tw)
		for slot = 1, 3 do
			t.near(an.share[tw.levels[9][slot]], 1 / 3, 1e-6)
		end
	end)

	t.test("JEN-P1 what a tap tells is the truth, and it changes as blocks leave", function()
		local tw = Tower.new(1)
		local an = Stability.ensure(tw)
		-- find a level with a loose block and a block that carries
		local found = false
		for level = 2, 16 do
			local looseSlot, carrySlot = 0, 0
			for slot = 1, 3 do
				local f = Physics.feel(tw, level, slot) :: Physics.Feel
				t.near(f.load * G, an.load[tw.levels[level][slot]], 1e-9)
				if f.kind == "loose" and f.load == 0 then
					looseSlot = slot
					t.truthy(f.hollow and f.give > 0.9, "a loose block rattles and knocks hollow")
				elseif f.kind == "tight" then
					carrySlot = slot
					t.truthy(not f.hollow and f.give < 0.9, "a tight block knocks dull")
				end
			end
			if looseSlot ~= 0 and carrySlot ~= 0 and not found then
				-- take a carrying block from that level: the weight has to go somewhere
				local before = an.load[tw.levels[level][looseSlot]]
				local c = Tower.clone(tw)
				take(c, level, carrySlot)
				local an2 = Stability.ensure(c)
				if an2.ok then
					found = true
					t.eq(before, 0)
					t.truthy(an2.load[c.levels[level][looseSlot]] > G, "the loose block now carries weight")
					t.eq((Physics.feel(c, level, looseSlot) :: Physics.Feel).hollow, false)
				end
			end
		end
		t.truthy(found, "seed 1 has a level whose loose block takes up the load")
		t.eq(Physics.feel(tw, 30, 1), nil)
	end)

	t.test("JEN-P2 two side blocks or the middle alone hold; one side block does not", function()
		-- the middle alone: stands, with half a block's width to spare on each side
		local tw = uniform()
		take(tw, 5, 1)
		take(tw, 5, 3)
		local ok = Stability.stands(tw)
		t.truthy(ok, "the middle alone holds")
		t.near(Stability.margin(tw), W / 2, 1e-6, "margin of half a width")
		-- two side blocks: stands, as wide as ever
		tw = uniform()
		take(tw, 5, 2)
		t.truthy((Stability.stands(tw)))
		t.near(Stability.margin(tw), L / 2, 1e-6)
		-- a side and the middle: stands; the spare is half a width on the side with nothing under it, less
		-- the hair the level above has tipped that way
		tw = uniform()
		take(tw, 5, 1)
		t.truthy((Stability.stands(tw)))
		t.near(Stability.margin(tw), W / 2, 0.02)
		t.truthy(Stability.margin(tw) < W / 2, "it leans toward the gap")
		-- one side block alone: the weight above is not over it. Level 5 runs along X, so it goes over in Z,
		-- toward the side with nothing under it
		for _, left in { 3, 1 } do
			tw = uniform()
			take(tw, 5, 2)
			take(tw, 5, 4 - left)
			local stands, fail = Stability.stands(tw)
			t.falsy(stands, "one side block does not hold")
			local f = fail :: Tower.Failure
			t.eq(f.dir, "z")
			t.eq(f.sign, if left == 3 then -1 else 1)
			t.truthy(f.level == 4 or f.level == 5, "it fails at that level")
			t.eq(f.why, "balance")
		end
		-- on an even level the same thing happens in X
		tw = uniform()
		take(tw, 8, 2)
		take(tw, 8, 1)
		local stands, fail = Stability.stands(tw)
		t.falsy(stands)
		t.eq((fail :: Tower.Failure).dir, "x")
		-- a level with nothing left: gone
		tw = uniform()
		take(tw, 6, 1)
		take(tw, 6, 2)
		take(tw, 6, 3)
		stands, fail = Stability.stands(tw)
		t.falsy(stands)
		t.eq((fail :: Tower.Failure).why, "gone")
	end)

	t.test("JEN-P2 the margin is the weight above against what is left, at every level", function()
		local tw = uniform()
		local an = Stability.ensure(tw)
		for i = 0, 17 do
			t.eq(an.mass[i + 1], 54 - 3 * i, "blocks above each joint")
			for d = 1, 2 do
				local j = Stability.at(i, d)
				t.near(an.bL[j], L / 2, 1e-9)
				t.near(an.bR[j], L / 2, 1e-9)
				t.near(an.base[j], 0, 1e-9)
			end
		end
		t.near(an.h[1], Layout.TOWER_H / 2, 1e-9, "the whole tower's centre is half way up")
		-- only the joint under and over the thin level lose margin, and only across its blocks
		take(tw, 7, 1)
		take(tw, 7, 3)
		an = Stability.ensure(tw)
		t.near(an.bR[Stability.at(6, 2)], W / 2, 1e-9)
		t.near(an.bR[Stability.at(7, 2)], W / 2, 1e-9)
		t.near(an.bR[Stability.at(6, 1)], L / 2, 1e-9)
		t.near(an.bR[Stability.at(3, 2)], L / 2, 1e-9)
		t.eq(an.marginJoint == 6 or an.marginJoint == 7, true)
	end)

	t.test("JEN-P5 crookedness counts: shifted levels and off-centre blocks eat the margin", function()
		local tw = uniform()
		local fresh = Stability.margin(tw)
		-- everything from level 11 up has crept 0.3 studs toward +X
		tw.shiftX[11] = 0.3
		Tower.touch(tw)
		local an = Stability.ensure(tw)
		t.truthy(an.ok)
		t.near(an.bR[Stability.at(10, 1)], L / 2 - 0.3, 0.01, "the joint under the shift")
		t.truthy(an.bR[Stability.at(10, 1)] < L / 2 - 0.3, "and the off-centre weight tips it a hair further")
		t.near(an.base[Stability.at(0, 1)], 0.3 * 24 / 54, 0.01, "the whole tower's weight has moved")
		t.truthy(Stability.margin(tw) < fresh - 0.25)
		-- far enough and the top is no longer over the bottom
		tw.shiftX[11] = 0.7
		Tower.touch(tw)
		local stands, fail = Stability.stands(tw)
		t.falsy(stands)
		local f = fail :: Tower.Failure
		t.eq(f.level, 10)
		t.eq(f.dir, "x")
		t.eq(f.sign, 1)
		-- a thin level and a small shift together fail where neither does alone
		tw = uniform()
		take(tw, 6, 1)
		take(tw, 6, 3)
		t.truthy((Stability.stands(tw)))
		tw.shiftX[12] = 0.25 * 54 / 21 -- the weight above level 6 moves a quarter of a stud... level 6 runs along Z
		Tower.touch(tw)
		t.falsy((Stability.stands(tw)), "the lean and the thin level together")
		-- a top block set down off square moves the weight too
		tw = uniform()
		tw.blocks[54].along = 0.2
		Tower.touch(tw)
		an = Stability.ensure(tw)
		t.near(an.base[Stability.at(17, 2)], 0.2 / 3, 1e-3)
		-- an unfinished top level puts its weight to one side
		tw = uniform()
		take(tw, 18, 2)
		take(tw, 18, 3)
		an = Stability.ensure(tw)
		t.near(an.base[Stability.at(17, 1)], -W, 1e-3)
		t.truthy(an.ok)
	end)

	t.test("JEN-P5 thickness makes each tower lean in its own way, and the lean is in the judgement", function()
		local leans = {}
		for seed = 1, 6 do
			local tw = Tower.new(seed)
			local an = Stability.ensure(tw)
			local p = Stability.poses(tw)
			local o = (54 - 1) * 6
			local lean = math.sqrt(p[o + 5] ^ 2 + p[o + 6] ^ 2)
			t.truthy(lean > 1e-4 and lean < 0.05, `seed {seed} leans {lean} rad`)
			table.insert(leans, lean)
			-- the weight's resting place at the bottom joint is off centre by what the levels above lean
			local off = math.sqrt(an.base[1] ^ 2 + an.base[2] ^ 2)
			t.truthy(off > 1e-5 and off < 0.1, `seed {seed} off centre {off}`)
			t.truthy(an.margin < L / 2 and an.margin > L / 2 - 0.1)
		end
		t.neq(leans[1], leans[2])
		-- no lean without thickness errors
		local an = Stability.ensure(uniform())
		for j = 1, 36 do
			t.eq(an.tilt[j], 0)
		end
	end)

	t.test("poses: every block where its slot says, and a rocking joint moves only what is above it", function()
		local tw = uniform()
		local p = Stability.poses(tw)
		t.eq(#p, 54 * 6)
		for id = 1, 54 do
			local b = tw.blocks[id]
			local x, y, z = Layout.slotCentre(b.level, b.slot)
			local o = (id - 1) * 6
			t.near(p[o + 1], x, 1e-9)
			t.near(p[o + 2], y, 1e-9)
			t.near(p[o + 3], z, 1e-9)
			t.near(p[o + 4], if Layout.alongX(b.level) then 0 else math.pi / 2, 1e-9)
			t.eq(p[o + 5], 0)
			t.eq(p[o + 6], 0)
		end
		-- lean the part above level 6 by 0.02 rad toward +X
		take(tw, 6, 1)
		take(tw, 6, 3)
		Stability.ensure(tw)
		tw.psiX[7] = 0.02
		p = Stability.poses(tw)
		for id = 1, 54 do
			local b = tw.blocks[id]
			if b.level > 0 then
				local x = Layout.slotCentre(b.level, b.slot)
				local o = (id - 1) * 6
				if b.level <= 6 then
					t.near(p[o + 1], x, 1e-9, "below the joint nothing moves")
					t.eq(p[o + 5], 0)
				else
					t.near(p[o + 1] - x, 0.02 * (Layout.levelY(b.level) - 6 * T), 1e-9, "above it leans")
					t.near(p[o + 5], 0.02, 1e-12)
					t.truthy(p[o + 2] > Layout.levelY(b.level), "and lifts on the edge it leans over")
				end
			else
				t.eq(p[(id - 1) * 6 + 2], -1)
			end
		end
	end)

	t.test("snapshot and restore: the client's mirror is the server's tower, byte for byte", function()
		local tw = Tower.new(11)
		take(tw, 4, 2)
		tw.shiftX[9] = 0.01
		tw.blocks[20].along = 0.12
		tw.inHand = tw.blocks[11].id
		tw.rev = 5
		Tower.touch(tw)
		local snap = Tower.snapshot(tw)
		t.eq(#snap.b, 54 * 5)
		local mirror = Tower.restore(snap) :: Tower.Tower
		t.truthy(mirror)
		t.eq(mirror.rev, 5)
		tw.step = 0
		t.eq(Tower.encode(mirror), Tower.encode(tw))
		t.deepEq(Stability.poses(mirror), Stability.poses(tw))
		-- a table that is not a snapshot is refused, with the reason
		local bad, why = Tower.restore({ b = {}, sx = {}, sz = {}, n = 18 })
		t.eq(bad, nil)
		t.truthy(why)
		t.eq((Tower.restore("nonsense")), nil)
		snap.b[2] = 7 -- slot 7
		t.eq((Tower.restore(snap)), nil)
		snap.b[2] = 1
		snap.b[7] = 1 -- two blocks in level 1 slot 1
		t.eq((Tower.restore(snap)), nil)
	end)
end
