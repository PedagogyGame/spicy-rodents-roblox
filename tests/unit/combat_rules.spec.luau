--!strict
-- Shared/Combat/CombatRules, Combat/Duel and Combat/VigilanteRules (brief v2 §8 "Combat dynamics", "Vigilantes",
-- "Health and house defenders", "Bite aftermath"): temperaments fixed by id, the vigilante share kept on AI bodies,
-- the bite by the person's phase (into a raised arm or a kick it does not land), strikes, damage, the zig-zag, and a
-- person's phases from a tell to a strike.
local CombatRules = require("@shared/Combat/CombatRules")
local Duel = require("@shared/Combat/Duel")
local VigilanteRules = require("@shared/Combat/VigilanteRules")
local Tunables = require("@shared/Config/Tunables")

return function(t)
	local P = CombatRules.params()

	t.test("temperaments: fixed by the id; about duel.waryShare wary; tough only with a vigilante flag", function()
		local wary, n = 0, 10000
		for id = 1, n do
			local a = CombatRules.temperament(id, false)
			t.eq(CombatRules.temperament(id, false), a, "the same every time")
			t.truthy(a ~= "tough")
			if a == "wary" then
				wary += 1
			end
		end
		t.near(wary / n, P.waryShare, 0.02, "the wary share")
		t.eq(CombatRules.temperament(7, true), "tough")
		local nv = CombatRules.nerve(P, 7, "tough")
		t.truthy(nv >= 0.85 and nv <= 1)
		t.truthy(CombatRules.nerve(P, 7, "calm") < 0.45)
	end)

	t.test(
		"vigilantes: round(8 % of the humans), on AI bodies only, kept where they are, moved off a possessed body",
		function()
			t.eq(Tunables.get("human.vigilanteShare"), 0.08)
			local humans = {}
			for id = 1, 72 do
				table.insert(humans, { id = id, ai = true })
			end
			local flags = VigilanteRules.rebalance(humans, {}, 0.08)
			local function count(f: { [any]: boolean }): number
				local c = 0
				for _ in f do
					c += 1
				end
				return c
			end
			t.eq(count(flags), 6, "round(0.08 x 72)")
			t.deepEq(VigilanteRules.rebalance(humans, {}, 0.08), flags, "the same people every server")
			-- a player takes a vigilante: the flag moves to another AI body; the others stay
			local taken = next(flags)
			for _, h in humans do
				if h.id == taken then
					h.ai = false
				end
			end
			local after = VigilanteRules.rebalance(humans, flags, 0.08)
			t.eq(count(after), 6)
			t.eq(after[taken], nil, "never on a player's body")
			for id in flags do
				if id ~= taken then
					t.truthy(after[id], "the other flags stay put")
				end
			end
			-- the town shrinks: still round(8 %)
			local few = {}
			for id = 1, 12 do
				table.insert(few, { id = id, ai = true })
			end
			t.eq(count(VigilanteRules.rebalance(few, after, 0.08)), 1)
			t.eq(count(VigilanteRules.rebalance({}, after, 0.08)), 0)
		end
	)

	t.test("the bite by phase: open lands most, a raised arm almost never, a raised leg or a kick never", function()
		for _, temper in CombatRules.TEMPERS do
			local unaware = CombatRules.biteChance(P, temper, "unaware", false)
			local open = CombatRules.biteChance(P, temper, "open", false)
			local guard = CombatRules.biteChance(P, temper, "guard", false)
			t.eq(CombatRules.biteChance(P, temper, "windup", false), 0, "into a raised leg or a kick")
			t.truthy(unaware > open and open > guard, temper)
			t.truthy(guard <= 0.05, "into a raised arm it does not land")
			t.near(CombatRules.biteChance(P, temper, "open", true), open * P.bitePenalty, 1e-9, "near a fresh bite")
		end
		t.truthy(
			CombatRules.biteChance(P, "tough", "unaware", false) < CombatRules.biteChance(P, "calm", "unaware", false),
			"a tough person resists a bite even unaware"
		)
		t.eq(CombatRules.biteChance(P, "tough", "guard", false), 0)
		t.near(CombatRules.biteChance(P, "calm", "unaware", false), Tunables.get("pounce.chanceUnaware"), 1e-9)
	end)

	t.test(
		"strikes: a tough person lands more; zig-zag dodges, a committed lunge does not; recovering is worse",
		function()
			local base = { zigzag = 0, committed = false, recovering = false, counter = false, boosted = false }
			local calm = CombatRules.strikeChance(P, "calm", base)
			local tough = CombatRules.strikeChance(P, "tough", base)
			t.truthy(tough > calm)
			local zz = table.clone(base)
			zz.zigzag = 1
			t.near(CombatRules.strikeChance(P, "tough", zz), tough - P.zigzagMiss, 1e-9)
			zz.committed = true
			t.near(CombatRules.strikeChance(P, "tough", zz), tough, 1e-9, "a lunge that meets a kick is hit (D-28)")
			local rec = table.clone(base)
			rec.recovering = true
			t.truthy(CombatRules.strikeChance(P, "calm", rec) > calm)
			local all = { zigzag = 0, committed = true, recovering = true, counter = true, boosted = true }
			t.truthy(CombatRules.strikeChance(P, "tough", all) <= 0.97, "never certain")
		end
	)

	t.test("damage: kick 55, two kill; the hidden boost stays below the one-kick line; defenders 1.5x", function()
		t.eq(CombatRules.damage(P, "kick", false), 55)
		local h, dead = CombatRules.applyDamage(100, 55)
		t.eq(h, 45)
		t.falsy(dead)
		h, dead = CombatRules.applyDamage(h, 55)
		t.eq(h, 0)
		t.truthy(dead)
		local boosted = CombatRules.damage(P, "kick", true)
		t.near(boosted, 55 * 1.25, 1e-9)
		t.truthy(boosted < P.maxHealth, "one kick never kills, boosted or not")
		t.near(CombatRules.damage(P, "kick", false, true), 82.5, 1e-9, "a house defender")
		t.truthy(CombatRules.damage(P, "swing", false) < 55)
		t.eq(CombatRules.damage(P, "baton", false), 50)
	end)

	t.test("weights: vigilantes never flee; near a fresh bite everyone swings and kicks more", function()
		for _, boosted in { false, true } do
			t.eq(CombatRules.weights(P, "tough", 1, boosted, false).flee, 0)
		end
		local function fightShare(w: { [string]: number }): number
			local total = 0
			for _, r in CombatRules.RESPONSES do
				total += w[r]
			end
			return (w.swing + w.kick) / total
		end
		for _, temper in CombatRules.TEMPERS do
			local nv = CombatRules.nerve(P, 3, temper)
			t.truthy(
				fightShare(CombatRules.weights(P, temper, nv, true, false))
					> fightShare(CombatRules.weights(P, temper, nv, false, false)),
				`{temper}: far more likely to swing near a bite`
			)
		end
		t.truthy(
			fightShare(CombatRules.weights(P, "tough", 1, false, false))
				> fightShare(CombatRules.weights(P, "calm", 0.25, false, false))
		)
		local w = CombatRules.weights(P, "calm", 0.25, false, false)
		t.eq(CombatRules.pick(w, 0), "flee")
		t.eq(CombatRules.pick(w, 0.9999), "kick")
	end)

	t.test("zig-zag: a straight run and a slow weave read 0; quick reversals across the line read 1", function()
		local straight, weave, slow = {}, {}, {}
		for i = 0, 15 do
			local tt = i * 0.1
			table.insert(straight, { t = tt, x = 0, z = tt * 30 })
			table.insert(weave, { t = tt, x = (if i % 2 == 0 then 2 else -2), z = tt * 25 })
			table.insert(slow, { t = tt, x = math.sin(tt) * 0.3, z = tt * 25 })
		end
		t.eq(CombatRules.zigzag(P, straight, 0, 1, 1.5), 0)
		t.eq(CombatRules.zigzag(P, slow, 0, 1, 1.5), 0)
		t.eq(CombatRules.zigzag(P, weave, 0, 1, 1.5), 1)
		t.eq(CombatRules.zigzag(P, {}, 0, 1, 1.5), 0)
	end)

	t.test("a person's duel: a tell, the reaction window, the response; a read feint is countered at once", function()
		local seq = {}
		local function dice(list: { number }): () -> number
			seq = table.clone(list)
			return function(): number
				return if #seq > 0 then table.remove(seq, 1) :: number else 0.99
			end
		end
		local function view(now: number, dist: number, tell: number?, feint: boolean?): Duel.View
			return {
				now = now,
				dt = 0.1,
				dist = dist,
				dy = 0,
				seen = true,
				tell = tell,
				tellFeint = feint,
				committed = false,
				recovering = false,
				zigzag = 0,
				boosted = false,
			}
		end
		-- a vigilante squares up on sight and closes in; never runs
		local g = Duel.new(P, 1, "tough", 1)
		local out = Duel.think(P, g, view(0, 20), dice({ 0 }))
		t.eq(g.phase, "ready")
		t.eq(out.move, "approach")
		t.eq(out.stance, "squared", "the vigilante's tell")
		t.eq(Duel.bitePhase(g, 0), "guard")
		-- a pounce's tell 8 studs off: the arm is already up (guardUp 1), then the response (dice: kick)
		out = Duel.think(P, g, view(2, 8, 2), dice({ 0.99, 0.99, 0.0, 0.99 }))
		t.eq(g.phase, "startle")
		t.eq(Duel.bitePhase(g, 2.05), "guard", "a vigilante's reaction window is shut")
		out = Duel.think(P, g, view(2 + P.react.tough, 8, 2), dice({ 0.99 }))
		t.truthy(out.reacted ~= nil and out.reacted ~= "flee", `reacted {out.reacted}`)
		-- a calm person caught unready: open until they react
		local c = Duel.new(P, 2, "calm", 0.25)
		Duel.think(P, c, view(0, 25), dice({ 0.99 })) -- (the dice say: do not run)
		t.eq(c.phase, "ready")
		Duel.think(P, c, view(0.1, 9, 0.1), dice({ 0.5, 0.0 }))
		t.eq(c.phase, "startle")
		t.eq(Duel.bitePhase(c, 0.2), "open", "the reaction window")
		t.eq(Duel.bitePhase(c, 0.1 + P.react.calm + 0.01), "guard")
		-- a feint read by a vigilante: a counter at once, quicker and longer
		local v = Duel.new(P, 3, "tough", 1)
		Duel.think(P, v, view(0, 9), dice({ 0 }))
		out = Duel.think(P, v, view(1, 9, 1, true), dice({ 0 }))
		t.truthy(out.read)
		t.eq(v.phase, "windup")
		t.truthy(v.counter)
		t.near(v.untilT - 1, P.windup.tough * P.counterWindupMult, 1e-9)
		t.eq(Duel.reach(P, v), P.kickReach + P.counterLunge)
		t.eq(Duel.bitePhase(v, 1.05), "windup", "a raised leg: no bite lands")
		-- the blow: in reach and the dice say yes
		out = Duel.think(P, v, view(1 + P.windup.tough * P.counterWindupMult, 7, 1, true), dice({ 0 }))
		t.truthy(out.strike ~= nil and out.strike.hit and out.strike.counter)
		t.eq(v.phase, "recover")
		t.eq(Duel.bitePhase(v, 1.25), "open", "after the blow: the opening")
	end)

	t.test(
		"the link: a bite is judged against the person as the rodent's player saw them; a blow at nothing opens longer",
		function()
			local function view(now: number, dist: number, tell: number?): Duel.View
				return {
					now = now,
					dt = 0.1,
					dist = dist,
					dy = 0,
					seen = true,
					tell = tell,
					tellFeint = false,
					committed = false,
					recovering = false,
					zigzag = 0,
					boosted = false,
				}
			end
			local zero = function(): number
				return 0
			end
			local high = function(): number
				return 0.99
			end
			-- a vigilante kicks at a rodent out of reach: overbalanced for whiffRecover, longer than after a near miss
			local g = Duel.new(P, 1, "tough", 1)
			Duel.think(P, g, view(0, 20), zero)
			Duel.think(P, g, view(0.1, 8), zero) -- (coming into reach: the dice say strike)
			t.eq(g.phase, "windup")
			local now = 0.1
			while g.phase == "windup" do
				now += 0.1
				Duel.think(P, g, view(now, 30), high)
			end
			t.eq(g.phase, "recover")
			t.near(g.untilT - now, P.whiffRecover.tough, 1e-9)
			t.truthy(P.whiffRecover.tough > P.recover.tough)
			-- the recovery ends; a round trip later the player still saw it: a bite then is judged open
			local opened = now
			while g.phase == "recover" do
				now += 0.1
				Duel.think(P, g, view(now, 12), high)
			end
			t.eq(Duel.bitePhase(g, now), "guard", "squared up again on the server")
			t.eq(Duel.bitePhaseAt(g, now, 0.1, nil), "open", "the player, 100 ms behind, still sees the opening")
			t.eq(Duel.bitePhaseAt(g, now, 0, nil), "guard", "no link, no rewind")
			t.truthy(now - opened >= P.whiffRecover.tough - 1e-9)
			-- but the reaction window to the pounce's own tell is the server's: a slow link buys no more of it
			local c = Duel.new(P, 2, "calm", 0.25)
			Duel.think(P, c, view(0, 25), high)
			local tell = 0.1
			Duel.think(P, c, view(0.1, 9, tell), function(): number
				return 0.5
			end)
			t.eq(c.phase, "startle")
			local tt = 0.1
			while c.phase == "startle" do
				tt += 0.1
				Duel.think(P, c, view(tt, 9, tell), high)
			end
			t.eq(Duel.bitePhaseAt(c, tt, 0.1, tell), Duel.bitePhase(c, tt), "the reaction to this pounce: as it is now")
			-- contact along the move: a pounce passes through in one step and still touches
			t.near(Duel.sweep(-3, 0, 3, 0, 0, 1), 1, 1e-9)
			t.near(Duel.sweep(0, 0, 0, 0, 3, 4), 5, 1e-9)
		end
	)
end
