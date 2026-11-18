--!strict
-- The paintball match model (Shared/Minigames/Paintball/Rules; checklist PB-2, PB-6, PB-7, PB-14), driven
-- the two ways the game drives it: through the real Session (seats taken and left, the clock, the end) as
-- the framework does, and directly (sync, drain, fire, tag, assign, tune) as the service does. The service's
-- order is kept by `tick`: sync to the shared clock, then the Session's own step.
local Session = require("@shared/Minigames/Session")
local Minigame = require("@shared/Minigames/Minigame")
local Clock = require("@shared/Minigames/Paintball/Clock")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Rules = require("@shared/Minigames/Paintball/Rules")
local Spec = require("@shared/Minigames/Paintball/Spec")
local Wire = require("@shared/Minigames/Paintball/Wire")

local R = Contract.Rules
local F = Contract.FEEL
local BIT = Wire.BIT
local T0 = 5000 -- the shared clock when a case starts (nothing in the model may assume it counts from 0)

type Match = { s: Session.Session, state: Rules.State, now: number, events: { Contract.Event } }

local function bot(name: string): any
	return { ai = true, name = name }
end

-- A match as the framework starts one: `people` join first, bots fill to `seats`. Synced at T0.
local function newMatch(people: number, seats: number): Match
	local s = Session.new(Rules, Spec.session)
	for i = 1, people do
		assert(Session.join(s, `p{i}`, `Person {i}`, T0))
	end
	local state = (s.game :: Minigame.Game).state :: Rules.State
	Rules.sync(state, T0)
	for i = people + 1, seats do
		assert(Session.join(s, bot(`b{i}`), `Bot {i}`, T0))
	end
	return { s = s, state = state, now = T0, events = {} }
end

-- One server step at `now`, in the service's order; the events it drained are kept on the match.
local function tick(m: Match, now: number): { Contract.Event }
	m.now = now
	Rules.sync(m.state, now)
	local drained = Rules.drain(m.state)
	for _, e in drained do
		table.insert(m.events, e)
	end
	Session.step(m.s, now)
	return drained
end

local function run(m: Match, to: number, dt: number?)
	local step = dt or 0.05
	while m.now + step <= to + 1e-9 do
		tick(m, m.now + step)
	end
end

local function kinds(events: { Contract.Event }, kind: string): { Contract.Event }
	local out = {}
	for _, e in events do
		if e.kind == kind then
			table.insert(out, e)
		end
	end
	return out
end

-- to the first moment of "live" with everybody's protection over
local function goLive(m: Match)
	run(m, T0 + R.briefingSecs + F.protectSecs + 0.2)
	assert(m.state.phase == "live", "the match is live")
end

return function(t)
	t.test("the start: every slot is placed in its team's room, on a point of its own, by the second step", function()
		local m = newMatch(1, 8)
		t.eq(m.state.phase, "briefing")
		t.deepEq(tick(m, T0 + 0.016), {}, "the step that first runs the clock has not told anything yet")
		local placed = tick(m, T0 + 0.033)
		t.eq(#placed, 8)
		local used: { { [number]: boolean } } = { {}, {} }
		local sides = { 0, 0 }
		for i, e in placed do
			t.eq(e.kind, "respawn")
			t.eq(e.id, i)
			local slot = Rules.slot(m.state, i) :: Rules.Slot
			t.eq(e.team, slot.team)
			t.eq(e.spawn, slot.spawn)
			t.truthy((e.spawn :: number) >= 1 and (e.spawn :: number) <= R.teamMax)
			t.falsy(used[slot.team][slot.spawn], "nobody is put on a point somebody else was just put on")
			used[slot.team][slot.spawn] = true
			sides[slot.team] += 1
			t.near(e.at :: number, T0 + 0.016 + F.protectSecs, 1e-9, "at = when its protection ends")
			t.eq(slot.mag.rounds, R.magazine)
			t.eq(slot.owed, nil)
		end
		t.deepEq(sides, { 4, 4 })
		t.deepEq(tick(m, T0 + 0.05), {}, "and it is said once")
		t.eq(Rules.view(m.state).size, 4)
	end)

	t.test("8 v 8: sixteen slots, eight points a room, each used once", function()
		local m = newMatch(2, 16)
		tick(m, T0 + 0.016)
		local placed = tick(m, T0 + 0.033)
		t.eq(#placed, 16)
		local seen: { [string]: boolean } = {}
		for _, e in placed do
			local key = `{e.team}:{e.spawn}`
			t.falsy(seen[key], key)
			seen[key] = true
		end
		t.eq(Rules.view(m.state).size, 8)
		local full = Session.join(m.s, "late", "Late", T0 + 1)
		t.falsy(full, "sixteen seats and no more")
	end)

	t.test(
		"the phases: 10 s of briefing, 480 s live, then the end; each change is one event on the shared clock",
		function()
			local m = newMatch(1, 8)
			run(m, T0 + R.briefingSecs - 0.05)
			t.eq(m.state.phase, "briefing")
			t.eq(m.state.endsAt, T0 + R.briefingSecs)
			t.deepEq({ Rules.canFire(m.state, 1, m.now) }, { false, "phase" } :: { any })
			t.falsy(Rules.canBeHit(m.state, 2, m.now))
			t.falsy(Rules.tag(m.state, 1, 2, m.now), "nobody is tagged in the briefing")
			run(m, T0 + R.briefingSecs + 0.1)
			t.eq(m.state.phase, "live")
			t.eq(m.state.liveAt, T0 + R.briefingSecs)
			t.eq(m.state.endsAt, T0 + R.briefingSecs + R.matchSecs)
			local phases = kinds(m.events, "phase")
			t.eq(#phases, 1)
			t.deepEq(phases[1], { kind = "phase", phase = "live", at = T0 + R.briefingSecs + R.matchSecs } :: any)
			t.eq(Rules.view(m.state).phase, "live")
			t.eq(Rules.result(m.state), nil)
			-- a long server hitch does not stretch the match: the end is where the clock says
			tick(m, T0 + R.briefingSecs + R.matchSecs - 0.01)
			t.eq(m.s.phase, "playing")
			tick(m, T0 + R.briefingSecs + R.matchSecs + 0.3)
			t.eq(m.state.phase, "ended")
			t.eq(m.s.phase, "done", "the Session saw the result in the same step")
			t.eq(
				m.state.endsAt,
				T0 + R.briefingSecs + R.matchSecs + R.endCardSecs,
				"the card counts down to the next match"
			)
			tick(m, m.now + 0.05)
			phases = kinds(m.events, "phase")
			t.eq(#phases, 2)
			t.eq(phases[2].phase, "ended")
			-- nothing fires, tags or reloads on the end card
			t.deepEq({ Rules.fire(m.state, 1, m.now) }, { false, "phase" } :: { any })
			t.deepEq(
				{ Rules.fire(m.state, 1, T0 + R.briefingSecs + 100) },
				{ false, "phase" } :: { any },
				"whatever a click's stamp, nothing is born once the clock has run out"
			)
			t.falsy(Rules.tag(m.state, 1, 2, m.now))
			t.falsy(Rules.reload(m.state, 1, m.now))
			t.falsy(Rules.canBeHit(m.state, 2, m.now))
		end
	)

	t.test(
		"sync: the first shifts every time once; a later one only sets the clock (a hitch moves no magazine)",
		function()
			local state = Rules.init(2, 9)
			Rules.step(state, 3) -- a bare model counts by itself
			t.eq(state.now, 3)
			t.deepEq(Rules.drain(state), {}, "nobody is placed before a first sync: there is nobody to place a body")
			local slot = state.slots[1]
			t.eq(slot.owed, 0)
			Rules.sync(state, 900)
			t.eq(state.now, 900)
			t.eq(state.endsAt, 900 + R.briefingSecs - 3)
			t.eq(state.liveAt, state.endsAt)
			t.eq(slot.since, 897)
			t.eq(slot.owed, 900, "owed from the sync")
			Rules.step(state, 0.1)
			t.eq(state.now, 900, "a synced model adds nothing of its own")
			t.deepEq(Rules.drain(state), {}, "and the step at the instant of the sync has nothing to tell")
			Rules.sync(state, 900.02)
			Rules.step(state, 0.1)
			t.eq(#Rules.drain(state), 2)
			-- live, a shot, then a hitch: the late sync moves neither the magazine nor a respawn time
			Rules.sync(state, 900 + R.briefingSecs)
			Rules.step(state, 0)
			t.eq(state.phase, "live")
			local t1 = state.now
			t.truthy(Rules.fire(state, 1, t1))
			t.truthy(Rules.tag(state, 1, 2, t1))
			local next, outUntil, endsAt = slot.mag.nextFireAt, state.slots[2].outUntil, state.endsAt
			Rules.sync(state, t1 + 0.7)
			t.eq(slot.mag.nextFireAt, next)
			t.eq(state.slots[2].outUntil, outUntil)
			t.eq(state.endsAt, endsAt)
			t.eq(next, t1 + F.fireInterval)
			t.eq(outUntil, t1 + F.respawnSecs)
		end
	)

	t.test("the magazine: five balls a quarter second apart, an automatic reload, R when not full (PB-2)", function()
		local m = newMatch(1, 8)
		goLive(m)
		local state, at = m.state, m.now
		local slot = Rules.slot(state, 1) :: Rules.Slot
		m.events = {}
		t.deepEq({ Rules.canFire(state, 1, at) }, { true, nil } :: { any })
		t.truthy(Rules.fire(state, 1, at))
		t.deepEq({ Rules.fire(state, 1, at + 0.1) }, { false, "fast" } :: { any })
		t.eq(slot.shots, 1, "a refused click is not a shot")
		t.falsy(Rules.reload(state, 2, at), "full: R does nothing")
		-- R at four balls
		t.truthy(Rules.reload(state, 1, at + 0.2))
		t.falsy(Rules.reload(state, 1, at + 0.3), "already reloading")
		t.deepEq({ Rules.canFire(state, 1, at + 0.5) }, { false, "empty" } :: { any })
		t.eq(Rules.bits(state, 1, at + 0.5), BIT.reload)
		t.deepEq({ Rules.canFire(state, 1, at + 0.2 + F.reloadSecs) }, { true, nil } :: { any })
		t.eq(slot.mag.rounds, R.magazine)
		t.eq(Rules.bits(state, 1, at + 0.2 + F.reloadSecs), 0)
		-- five in a row, the fifth starts the reload by itself
		local t5 = at + 0.2 + F.reloadSecs
		for i = 0, 4 do
			t.truthy(Rules.fire(state, 1, t5 + i * F.fireInterval), `ball {i + 1}`)
		end
		t.eq(slot.mag.rounds, 0)
		local last = t5 + 4 * F.fireInterval
		t.deepEq({ Rules.fire(state, 1, last + 0.5) }, { false, "empty" } :: { any })
		t.truthy(Rules.fire(state, 1, last + F.reloadSecs))
		t.eq(slot.shots, 7)
		tick(m, m.now + 0.05)
		local reloads = kinds(m.events, "reload")
		t.eq(#reloads, 2)
		t.deepEq(reloads[1], { kind = "reload", id = 1, at = at + 0.2 + F.reloadSecs } :: any)
		t.deepEq(reloads[2], { kind = "reload", id = 1, at = last + F.reloadSecs } :: any)
		-- the magazine is judged at m, the rest at t: three honest clicks the network bunched are three balls
		local t2 = last + F.reloadSecs + 5
		t.truthy(Rules.fire(state, 2, t2, t2 - 0.5))
		t.truthy(Rules.fire(state, 2, t2, t2 - 0.25))
		t.truthy(Rules.fire(state, 2, t2, t2))
		t.deepEq({ Rules.fire(state, 2, t2, t2) }, { false, "fast" } :: { any })
		-- the Session's own verb reaches the same reload, with t held inside what the clock allows
		tick(m, t2)
		t.truthy(Session.apply(m.s, "p1", "reload", { t2 - 60 }, t2))
		t.near(slot.mag.reloadDoneAt :: number, t2 - Clock.MAG_LATE + F.reloadSecs, 1e-9)
		local ok, why = Session.apply(m.s, "p1", "side", {}, t2)
		t.falsy(ok)
		t.eq(why, Contract.textFor("side"))
	end)

	t.test(
		"a tag: one hit and you are out; a point to the other team; back in 4 s, full and protected (PB-6)",
		function()
			local m = newMatch(1, 8)
			goLive(m)
			local state, at = m.state, m.now
			m.events = {}
			local a, b = Rules.slot(state, 1) :: Rules.Slot, Rules.slot(state, 2) :: Rules.Slot
			t.truthy(a.team ~= b.team)
			t.truthy(Rules.fire(state, 2, at))
			t.truthy(Rules.fire(state, 2, at + 0.25))
			t.truthy(Rules.fire(state, 1, at))
			t.truthy(Rules.canBeHit(state, 2, at + 0.3))
			t.falsy(Rules.tag(state, 1, 3, at + 0.3), "no friendly fire: seats 1 and 3 are one team")
			t.falsy(Rules.tag(state, 1, 1, at + 0.3))
			t.truthy(Rules.tag(state, 1, 2, at + 0.3, at))
			t.deepEq(state.scores, { 1, 0 })
			t.deepEq({ a.tags, a.hits, a.shots }, { 1, 1, 1 })
			t.deepEq({ b.out, b.outAt, b.outUntil, b.outs }, { true, at + 0.3, at + 0.3 + F.respawnSecs, 1 } :: { any })
			t.eq(Rules.bits(state, 2, at + 0.4), BIT.out)
			t.falsy(Rules.canBeHit(state, 2, at + 0.4))
			t.falsy(Rules.tag(state, 1, 2, at + 0.4), "you cannot be tagged twice")
			t.falsy(Rules.reload(state, 2, at + 0.4))
			-- a click made before the tag still counts, whichever packet came first; one made after does not
			t.deepEq({ Rules.fire(state, 2, at + 0.5) }, { false, "out" } :: { any })
			t.truthy(Rules.fire(state, 2, at + 0.29, at + 0.5), "stamped before the tag")
			t.eq(b.mag.rounds, 2)
			-- and its ball is good whatever has become of the shooter: the tagger is tagged by it
			t.truthy(Rules.tag(state, 2, 1, at + 0.6, at + 0.29))
			t.deepEq(state.scores, { 1, 1 })
			t.eq(b.tags, 1)
			tick(m, at + 0.7)
			local tags = kinds(m.events, "tag")
			t.eq(#tags, 2)
			t.deepEq(tags[1], { kind = "tag", by = 1, id = 2, at = at + 0.3 + F.respawnSecs } :: any)
			-- the respawn: at the time said, a full magazine, no reload running, protected for 2 s
			run(m, at + 0.3 + F.respawnSecs - 0.06)
			t.truthy(b.out)
			t.eq(#kinds(m.events, "respawn"), 0)
			run(m, at + 0.3 + F.respawnSecs + 0.1)
			t.falsy(b.out)
			local back = kinds(m.events, "respawn")
			t.eq(#back, 1)
			t.eq(back[1].id, 2)
			t.eq(back[1].team, b.team)
			t.eq(back[1].spawn, b.spawn)
			t.eq(b.mag.rounds, R.magazine, "nobody comes back with the two balls they had left")
			t.eq(b.mag.reloadDoneAt, nil)
			local safe = back[1].at :: number
			t.near(safe, at + 0.3 + F.respawnSecs + F.protectSecs, 0.051)
			t.eq(Rules.bits(state, 2, m.now), BIT.safe)
			t.deepEq({ Rules.fire(state, 2, m.now) }, { false, "safe" } :: { any })
			t.falsy(Rules.canBeHit(state, 2, m.now))
			t.falsy(Rules.tag(state, 3, 2, m.now))
			t.deepEq({ Rules.canFire(state, 2, safe) }, { true, nil } :: { any })
			t.truthy(Rules.canBeHit(state, 2, safe))
			-- a click stamped before the respawn (while it was out) is no shot after it
			t.deepEq({ Rules.fire(state, 2, at + 2, safe) }, { false, "safe" } :: { any })
			-- the view carries the tallies; a tag is not a change of view the Session must be told
			local view = Rules.view(state)
			t.deepEq(view.scores, { 1, 1 })
			t.deepEq(view.slots[1], { id = 1, team = a.team, on = true, tags = 1, outs = 1, shots = 1, hits = 1 })
		end
	)

	t.test("spawn points: the one that has stood empty longest, so a respawn is not where the last one was", function()
		local m = newMatch(1, 8)
		goLive(m)
		local state = m.state
		m.events = {}
		-- team 2's four are tagged one after another, half a second apart
		local victims = { 2, 4, 6, 8 }
		for i, id in victims do
			t.truthy(Rules.tag(state, 1, id, m.now), `tag {id}`)
			if i < #victims then
				run(m, m.now + 0.5)
			end
		end
		run(m, m.now + F.respawnSecs + 0.2)
		local back = kinds(m.events, "respawn")
		t.eq(#back, 4)
		local seen: { [number]: boolean } = {}
		for _, e in back do
			t.falsy(seen[e.spawn :: number], "four respawns, four different points")
			seen[e.spawn :: number] = true
		end
	end)

	t.test("seats: a late joiner and a bot's seat taken by a person; a seat left; the ball of one who left", function()
		local m = newMatch(1, 8)
		goLive(m)
		local state = m.state
		m.events = {}
		-- a friend joins late: a new seat, on the smaller side (level: by the seat), placed and protected
		local ok, _, seat = Session.join(m.s, "p2", "Person 2", m.now)
		t.truthy(ok)
		t.eq(seat, 9)
		local nine = Rules.slot(state, 9) :: Rules.Slot
		t.eq(nine.team, Contract.teamOf(9))
		t.truthy(nine.on)
		t.falsy(Rules.canBeHit(state, 9, m.now), "protected from the moment it is seated")
		t.deepEq({ Rules.canFire(state, 9, m.now) }, { false, "safe" } :: { any })
		t.eq(Rules.bits(state, 9, m.now), BIT.safe)
		local joinedAt = m.now
		t.deepEq(kinds(tick(m, joinedAt + 0.016), "respawn"), {}, "the first step after the join: not yet")
		local placed = kinds(tick(m, joinedAt + 0.033), "respawn")
		t.eq(#placed, 1)
		t.eq(placed[1].id, 9)
		t.near(placed[1].at :: number, joinedAt + 0.016 + F.protectSecs, 1e-9)
		-- the next bot joins the smaller side, which is now the other one
		Session.join(m.s, bot("b10"), "Bot 10", m.now)
		t.eq((Rules.slot(state, 10) :: Rules.Slot).team, 3 - nine.team)
		run(m, m.now + F.protectSecs + 0.2)
		-- seat 2 (a bot) fires and tags, then leaves; a person takes the seat: the side stays, the tally does not
		local two = Rules.slot(state, 2) :: Rules.Slot
		local team2 = two.team
		t.truthy(Rules.fire(state, 2, m.now))
		t.truthy(Rules.tag(state, 2, 1, m.now))
		t.eq(two.tags, 1)
		local born = m.now
		t.truthy(Rules.fire(state, 2, born + F.fireInterval), "a second ball, in flight when the seat changes hands")
		run(m, born + 0.3)
		Session.leave(m.s, m.s.seats[2], m.now)
		t.falsy(two.on)
		t.deepEq({ Rules.canFire(state, 2, m.now) }, { false, "out" } :: { any }, "a seat that is off cannot fire")
		t.falsy(Rules.canBeHit(state, 2, m.now))
		t.eq(Rules.bits(state, 2, m.now), 0)
		-- its ball lands while the seat is empty: the point is its team's, the tag the slot's
		local scores = { state.scores[1], state.scores[2] }
		t.truthy(Rules.tag(state, 2, 3, m.now, born + F.fireInterval))
		t.eq(state.scores[team2], scores[team2] + 1)
		t.eq(two.tags, 2)
		local ok3, _, seat3 = Session.join(m.s, "p3", "Person 3", m.now)
		t.truthy(ok3)
		t.eq(seat3, 2, "the vacated seat first")
		local taken = Rules.slot(state, 2) :: Rules.Slot
		t.eq(taken.team, team2, "the seat keeps its side")
		t.deepEq(
			{ taken.tags, taken.outs, taken.shots, taken.hits },
			{ 0, 0, 0, 0 },
			"a new holder starts from nothing"
		)
		t.eq(taken.since, m.now)
		-- a ball the last holder fired lands now: a point for the team, nothing on the newcomer's row
		run(m, m.now + 0.1)
		t.truthy(Rules.tag(state, 2, 5, m.now, born))
		t.eq(state.scores[team2], scores[team2] + 2)
		t.deepEq({ taken.tags, taken.hits }, { 0, 0 })
		-- the newcomer's own ball is theirs
		run(m, m.now + F.protectSecs + 0.2)
		t.truthy(Rules.fire(state, 2, m.now))
		t.truthy(Rules.tag(state, 2, 7, m.now, m.now))
		t.deepEq({ taken.tags, taken.hits, taken.shots }, { 1, 1, 1 })
	end)

	t.test(
		"sides: assign moves a slot to the other room, keeps its tally and the scores; out, it waits its turn",
		function()
			local m = newMatch(2, 8)
			goLive(m)
			local state = m.state
			m.events = {}
			t.truthy(Rules.tag(state, 2, 1, m.now))
			t.truthy(Rules.tag(state, 1, 4, m.now, m.now - 0.1), "a ball of seat 1's that was already in flight")
			local one = Rules.slot(state, 1) :: Rules.Slot
			-- tagged out, seat 1 changes sides: no placement now, the ordinary respawn into the new room
			t.truthy(Rules.assign(state, 1, 2))
			t.eq(one.team, 2)
			t.eq(one.owed, nil)
			t.deepEq({ one.tags, one.outs }, { 1, 1 })
			t.deepEq(state.scores, { 1, 1 }, "the points stay with the teams that made them")
			run(m, m.now + F.respawnSecs + 0.1)
			local back = kinds(m.events, "respawn")
			t.eq(#back, 2)
			for _, e in back do
				if e.id == 1 then
					t.eq(e.team, 2)
				end
			end
			-- in play, seat 3 changes sides: placed at once (the step after), protected until then and after
			m.events = {}
			local three = Rules.slot(state, 3) :: Rules.Slot
			run(m, m.now + F.protectSecs)
			t.truthy(Rules.canBeHit(state, 3, m.now))
			t.truthy(Rules.assign(state, 3, 2))
			t.falsy(Rules.canBeHit(state, 3, m.now))
			t.deepEq({ Rules.canFire(state, 3, m.now) }, { false, "safe" } :: { any })
			tick(m, m.now + 0.016)
			tick(m, m.now + 0.016)
			local moved = kinds(m.events, "respawn")
			t.eq(#moved, 1)
			t.deepEq({ moved[1].id, moved[1].team }, { 3, 2 } :: { any })
			t.eq(three.mag.rounds, R.magazine)
			t.falsy(Rules.assign(state, 3, 2))
			t.falsy(Rules.assign(state, 3, 3))
			-- now seats 1, 2, 3 are one side: they do not tag each other
			run(m, m.now + F.protectSecs + 0.1)
			t.falsy(Rules.tag(state, 1, 3, m.now))
			t.falsy(Rules.tag(state, 2, 1, m.now))
			t.truthy(Rules.tag(state, 3, 5, m.now))
		end
	)

	t.test("tune: a match is played with its own feel, read everywhere the model uses one", function()
		local s = Session.new(Rules, Spec.session)
		Session.join(s, "p1", "Person 1", T0)
		local state = (s.game :: Minigame.Game).state :: Rules.State
		local feel = Contract.feel({ fireInterval = 0.5, reloadSecs = 3, respawnSecs = 6, protectSecs = 1 })
		Rules.tune(state, feel)
		Rules.sync(state, T0)
		for i = 2, 8 do
			Session.join(s, bot(`b{i}`), `Bot {i}`, T0)
		end
		local m: Match = { s = s, state = state, now = T0, events = {} }
		run(m, T0 + R.briefingSecs + 1.2)
		local at = m.now
		t.truthy(Rules.fire(state, 2, at), "a slot that joined after the tune has the tuned magazine too")
		t.deepEq({ Rules.fire(state, 2, at + 0.3) }, { false, "fast" } :: { any })
		t.truthy(Rules.fire(state, 2, at + 0.5))
		t.truthy(Rules.reload(state, 2, at + 0.6))
		t.eq((Rules.slot(state, 2) :: Rules.Slot).mag.reloadDoneAt, at + 0.6 + 3)
		t.truthy(Rules.tag(state, 2, 1, at + 0.6))
		t.eq((Rules.slot(state, 1) :: Rules.Slot).outUntil, at + 0.6 + 6)
		m.events = {}
		run(m, at + 0.6 + 6 + 0.1)
		local back = kinds(m.events, "respawn")
		t.eq(#back, 1)
		t.near(back[1].at :: number, at + 0.6 + 6 + 1, 0.051, "one second of protection")
		t.deepEq(state.feel, feel)
	end)

	t.test("the end card: the winner, a row a slot most tags first, accuracy, the awards (PB-7)", function()
		local m = newMatch(1, 8)
		goLive(m)
		local state = m.state
		-- seat 1: 6 balls, 3 tags. seat 2: 10 balls, 1 tag. seat 4: 1 ball, 1 tag. seat 3 is tagged 3 times.
		local at = m.now
		local function shots(id: number, n: number)
			local k = 0
			local time = at
			while k < n do
				if Rules.fire(state, id, time) then
					k += 1
				end
				time += 0.05
			end
		end
		shots(1, 6)
		shots(2, 10)
		shots(4, 1)
		at += 30
		run(m, at)
		t.truthy(Rules.tag(state, 1, 2, at))
		t.truthy(Rules.tag(state, 1, 6, at))
		t.truthy(Rules.tag(state, 1, 8, at))
		t.truthy(Rules.tag(state, 4, 3, at))
		run(m, at + 10)
		t.truthy(Rules.tag(state, 2, 3, m.now))
		run(m, m.now + 10)
		t.truthy(Rules.tag(state, 6, 3, m.now, m.now))
		local preview = Rules.card(state)
		t.eq(preview.winner, 0, "three all")
		t.deepEq(preview.scores, { 3, 3 })
		-- seat 7 leaves before the end: no row for an empty seat
		Session.leave(m.s, m.s.seats[7], m.now)
		tick(m, T0 + R.briefingSecs + R.matchSecs - 0.01)
		t.truthy(Rules.tag(state, 5, 4, m.now), "the last second counts")
		tick(m, T0 + R.briefingSecs + R.matchSecs + 0.01)
		local result = Rules.result(state) :: Contract.Result
		t.truthy(result.done)
		t.eq(result.text, "Orange wins 4 - 3")
		local card = result.card
		t.eq(card.winner, 1)
		t.deepEq(card.scores, { 4, 3 })
		t.deepEq(result.winners, { 1, 3, 5 }, "the winning team's seats that are still on")
		t.eq(result.scores[1], 3)
		t.eq(result.scores[7], 0)
		t.eq(#card.rows, 7)
		local order = {}
		for _, row in card.rows do
			table.insert(order, row.id)
		end
		-- most tags first; level on tags, fewer times out first; then the seat
		t.deepEq(order, { 1, 5, 2, 4, 6, 8, 3 })
		t.deepEq(card.rows[1], { id = 1, team = 1, tags = 3, outs = 0, shots = 6, hits = 3, accuracy = 0.5 })
		t.eq(card.rows[3].accuracy, 0.1)
		t.eq(card.rows[4].accuracy, 1)
		t.eq(card.rows[7].accuracy, 0, "no balls, no accuracy")
		local awards: { [string]: number } = {}
		local held: { [number]: string } = {}
		for _, a in card.awards do
			t.eq(awards[a.title], nil, "an award is given once")
			t.eq(held[a.id], nil, `seat {a.id} has {held[a.id]} already: one award a player`)
			awards[a.title] = a.id
			held[a.id] = a.title
		end
		-- handed out in order, each to the best row with none yet
		t.eq(awards["Top Tagger"], 1)
		t.eq(awards["Sharpest Eye"], 2, "seat 1 has its award; seat 4's one ball in one is not five balls")
		t.eq(awards["Clean Overalls"], 5, "never tagged out, and a tag of its own")
		t.eq(awards["Human Canvas"], 3)
		t.eq(awards["Most Paint Wasted"], nil, "nobody left fired ten balls")
		t.eq(awards["Saving It For Later"], 6, "the lowest seat of those left who never fired")
		-- the Session shows it and holds the card for endCardSecs and a spare second
		t.eq(m.s.phase, "done")
		t.truthy(m.s.result == result :: any)
		t.eq(m.s.doneEnds, m.now + R.endCardSecs + R.endCardSpare)
		-- a draw says so, and nobody wins it
		local drawn = newMatch(1, 8)
		goLive(drawn)
		t.truthy(Rules.tag(drawn.state, 1, 2, drawn.now))
		t.truthy(Rules.tag(drawn.state, 4, 3, drawn.now))
		tick(drawn, T0 + R.briefingSecs + R.matchSecs)
		local even = Rules.result(drawn.state) :: Contract.Result
		t.eq(even.text, "A draw, 1 all")
		t.deepEq(even.winners, {})
		t.eq(even.card.winner, 0)
	end)

	t.test(
		"the awards: one a player, so the busiest never sweeps the board; paint wasted is a share, not a pile",
		function()
			-- a card's rows by hand: (id, tags, outs, shots, hits)
			local function card(list: { { number } }): { [string]: number }
				local state = Rules.init(#list, 1)
				for i, r in list do
					local slot = state.slots[i]
					slot.tags, slot.outs, slot.shots, slot.hits = r[1], r[2], r[3], r[4]
				end
				local out: { [string]: number } = {}
				local seen: { [number]: boolean } = {}
				for _, a in Rules.card(state).awards do
					t.eq(seen[a.id], nil, `seat {a.id} twice`)
					seen[a.id] = true
					out[a.title] = a.id
				end
				return out
			end
			-- seat 1 tags most, fires most and misses most, and is tagged most: it is the Top Tagger only
			local a = card({
				{ 12, 9, 120, 12 },
				{ 6, 4, 30, 6 },
				{ 4, 2, 40, 4 },
				{ 3, 7, 60, 3 },
				{ 1, 5, 25, 1 },
				{ 2, 3, 4, 1 },
			})
			t.eq(a["Top Tagger"], 1)
			t.eq(a["Sharpest Eye"], 2, "6 in 30")
			t.eq(a["Clean Overalls"], 3, "tagged out twice: the fewest of those left")
			t.eq(a["Human Canvas"], 4)
			t.eq(a["Most Paint Wasted"], 5, "24 of 25 missed, not seat 1's pile of 108")
			t.eq(a["Saving It For Later"], 6)
			-- the one who fired least and tagged most gets Top Tagger, never Saving It For Later as well
			local b = card({ { 0, 1, 50, 0 }, { 5, 2, 6, 5 }, { 1, 3, 30, 1 } })
			t.eq(b["Top Tagger"], 2)
			t.truthy(b["Saving It For Later"] ~= 2)
			-- two players: two awards, one each
			local c = card({ { 3, 1, 20, 3 }, { 1, 3, 20, 1 } })
			local n = 0
			for _ in c do
				n += 1
			end
			t.eq(n, 2)
		end
	)

	t.test(
		"the next match: again() deals the people new seats and a fresh model; sides are the service's to restore",
		function()
			local m = newMatch(2, 8)
			goLive(m)
			t.truthy(Rules.assign(m.state, 2, 1), "two friends on one side")
			t.truthy(Rules.tag(m.state, 1, 4, m.now))
			tick(m, T0 + R.briefingSecs + R.matchSecs + 0.01)
			t.eq(m.s.phase, "done")
			-- the service takes the bots off and rolls on
			for _, key in m.s.seats do
				if type(key) == "table" then
					Session.leave(m.s, key, m.now)
				end
			end
			t.truthy(Session.again(m.s, m.now))
			local state = (m.s.game :: Minigame.Game).state :: Rules.State
			t.truthy(state ~= m.state)
			t.eq(state.phase, "briefing")
			t.deepEq(state.scores, { 0, 0 })
			t.eq(#state.slots, 2)
			t.deepEq({ state.slots[1].team, state.slots[2].team }, { 1, 2 }, "dealt by seat")
			t.truthy(Rules.assign(state, 2, 1), "and the service puts the friends back together")
			Rules.sync(state, m.now)
			for i = 3, 8 do
				Session.join(m.s, bot(`n{i}`), `Bot {i}`, m.now)
			end
			local sides = { 0, 0 }
			for _, slot in state.slots do
				sides[slot.team] += 1
			end
			t.deepEq(sides, { 4, 4 }, "the bots that fill it level the sides")
			local next: Match = { s = m.s, state = state, now = m.now, events = {} }
			tick(next, m.now + 0.016)
			tick(next, m.now + 0.033)
			local placed = kinds(next.events, "respawn")
			t.eq(#placed, 8, "everybody is placed once, the friend who changed sides in the new side's room")
			t.eq(placed[2].team, 1)
		end
	)

	t.test("the model does not know who is a bot: a person and a bot in the same spot get the same answers", function()
		-- two matches, mirror images: in one seat 1 is the person and seat 2 the bot, in the other the reverse
		local function script(people: { number }): { any }
			local s = Session.new(Rules, Spec.session)
			local order = { 1, 2, 3, 4, 5, 6, 7, 8 }
			for _, seat in order do
				local key: any = if table.find(people, seat) then `p{seat}` else bot(`b{seat}`)
				assert(Session.join(s, key, `Seat {seat}`, T0))
				if seat == 1 then
					Rules.sync((s.game :: Minigame.Game).state, T0)
				end
			end
			local state = (s.game :: Minigame.Game).state :: Rules.State
			local m: Match = { s = s, state = state, now = T0, events = {} }
			local log: { any } = {}
			local function note(...: any)
				table.insert(log, { ... })
			end
			run(m, T0 + 3)
			note(Rules.canFire(state, 1, m.now))
			note(Rules.canFire(state, 2, m.now))
			goLive(m)
			local at = m.now
			for i = 0, 6 do
				note(Rules.fire(state, 1, at + i * 0.2))
				note(Rules.fire(state, 2, at + i * 0.2))
			end
			note(Rules.tag(state, 1, 2, at + 1.5))
			note(Rules.tag(state, 2, 1, at + 1.5))
			note(Rules.fire(state, 2, at + 1.4, at + 3.2))
			note(Rules.fire(state, 2, at + 1.6, at + 3.2))
			run(m, at + 1.5 + F.respawnSecs + 0.1)
			note(Rules.tag(state, 1, 2, m.now))
			note(Rules.bits(state, 2, m.now), Rules.bits(state, 1, m.now))
			note(Rules.view(state))
			for _, e in m.events do
				table.insert(log, e)
			end
			return log
		end
		t.deepEq(script({ 1 }), script({ 2 }))
		t.deepEq(script({ 1 }), script({ 1, 2, 3, 4, 5, 6, 7, 8 }))
		t.deepEq(script({ 1 }), script({}))
	end)

	t.test(
		"a whole match by the clock at the server's rate: 28,800 steps, no event out of order, the times exact",
		function()
			local m = newMatch(1, 8)
			local dt = 1 / Clock.TICK_HZ
			local state = m.state
			local i = 0
			local tagged = 0
			while m.s.phase == "playing" do
				i += 1
				tick(m, T0 + i * dt)
				-- every 0.7 s somebody who may fires, and somebody who may be is tagged by the next seat round
				if state.phase == "live" and i % 42 == 0 then
					local by = (i // 42) % 8 + 1
					local id = by % 8 + 1
					if Rules.fire(state, by, m.now) and Rules.tag(state, by, id, m.now) then
						tagged += 1
					end
				end
			end
			t.near(m.now, T0 + R.briefingSecs + R.matchSecs, dt + 1e-6)
			t.truthy(tagged > 300, `{tagged} tags`)
			local result = Rules.result(state) :: Contract.Result
			t.eq(result.card.scores[1] + result.card.scores[2], tagged)
			local outs, respawns, lastAt = 0, 0, -math.huge
			local owedBack: { [number]: number } = {}
			for _, e in m.events do
				if e.kind == "tag" then
					outs += 1
					local id = e.id :: number
					t.eq(owedBack[id], nil, "nobody is tagged while out")
					owedBack[id] = e.at :: number
					t.truthy((e.at :: number) >= lastAt, "tags are told in order")
					lastAt = e.at :: number
				elseif e.kind == "respawn" then
					respawns += 1
					local id = e.id :: number
					local due = owedBack[id]
					if due ~= nil then
						-- back no sooner than said and within one step of it
						t.truthy((e.at :: number) - F.protectSecs >= due - 1e-9)
						t.truthy((e.at :: number) - F.protectSecs <= due + dt + 1e-9)
						owedBack[id] = nil
					end
				end
			end
			t.eq(outs, tagged)
			local stillOut = 0
			for _, slot in state.slots do
				if slot.out then
					stillOut += 1
				end
			end
			t.eq(
				respawns,
				8 + tagged - stillOut,
				"the eight placements of the start, and one for everybody who came back"
			)
		end
	)
end
