--!strict
-- tests/isolated/whack_a_mole_server.luau: cases for tests/unit/whack_server.spec.luau, run in their own Lune
-- process (tests/lib/Isolated) because they install the fake engine.
-- Whack-a-mole's server half (Server/Minigames/Games/WhackAMole) in the real MinigameService on tests/lib/
-- MinigameRig, played by PlayerLike stubs who strike from what they were sent (the stream of moles) with stamps on
-- the shared clock: a whole round scored by the server alone; junk, early, future and stale strikes refused with
-- words and nothing scored; a strike that arrives late but was made in time; a watcher who walks up mid-round; a
-- second player turned away; a leaver; the scripted outcomes the engine check uses.
-- Interface: return function(t) (the spec shape)
local Layout = require("@shared/Minigames/WhackAMole/Layout")
local Round = require("@shared/Minigames/WhackAMole/Round")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local FakeEngine = require("@tests/lib/FakeEngine")
local Rig = require("@tests/lib/MinigameRig")
local roblox = require("@lune/roblox")

local SITE = "bowling_alley"
local ID = "whack_a_mole_1"

local function furnish(roots: { [string]: any }, places: { [string]: any })
	local room = FakeEngine.new("Folder", "GamesRoom")
	room.Parent = roots[SITE]
	local X, Y, D = Layout.toSite(0, Layout.DECK.top, 0)
	FakeEngine.model("WhackAMole", roblox.CFrame.new(AlleyLayout.toWorld(places[SITE], X, Y, D)), room)
end

-- (the rig's player stands well away: these cases are the stubs')
local function opts(): Rig.Opts
	return { furnish = furnish, stand = { site = SITE, x = 60, y = 3, d = 0 } }
end

local function stamp(): number
	return workspace:GetServerTimeNow()
end

local function tbl(w: Rig.World): any
	return w.svc.stations[ID].tbl
end

-- a stub's view of the round, from what it was sent: start, and the moles by id
local function seen(stub: any): (number?, { [number]: any })
	local start: number? = nil
	local moles: { [number]: any } = {}
	local g = 0
	for _, m in stub.events do
		if m.kind == "whack_round" then
			start, g = m.start, m.g
			table.clear(moles)
			for _, r in m.rises do
				moles[r.id] = r
			end
		elseif m.kind == "whack_rise" and m.g == g then
			moles[m.id] = m
		end
	end
	return start, moles
end

-- a person beside the cabinet (world studs), for the service's people()
local function near(w: Rig.World, stub: any, dx: number)
	local X, Y, D = Layout.toSite(dx, 3, Layout.STAND.w)
	local x, y, z = AlleyLayout.toWorld(w.places[SITE], X, Y, D)
	table.insert(w.people, { key = stub, name = stub.Name, x = x, y = y, z = z })
end

-- play a whole round as a stub: every mole is struck `delay` seconds into its rise (the stamp is when it was
-- struck); returns the strikes it made
local function playRound(w: Rig.World, stub: any, delay: number, every: number?): number
	local struck: { [number]: boolean } = {}
	local made = 0
	local n = 0
	Rig.untilTrue(w, Round.READY + Round.SECONDS + 3, function(): boolean
		local start, moles = seen(stub)
		if start then
			local now = stamp() - start
			for id, m in moles do
				if not struck[id] and now >= m.at + delay then
					struck[id] = true
					n += 1
					if every == nil or n % every == 0 then
						local ok = Rig.input(w, stub, ID, "whack", { m.hole, stamp() })
						if ok then
							made += 1
						end
					end
				end
			end
		end
		return Rig.last(stub.events, "whack_over") ~= nil
	end)
	return made
end

return function(t: any)
	t.test(
		"a whole round: the moles stream to the player, the server judges every strike and keeps the board",
		function()
			Rig.play(function(w: Rig.World)
				local ann = Rig.stub("Ann")
				near(w, ann, 0)
				t.truthy(w.svc:join(ann, ID))
				local round = Rig.last(ann.events, "whack_round")
				t.truthy(round, "the round as it starts")
				t.near(round.start, stamp() + Round.READY, 0.05, "GO on the shared clock")
				t.eq(#round.rises, 0)
				-- nothing before GO, then the stream
				Rig.run(w, Round.READY - 0.3)
				t.eq(Rig.count(ann.events, "whack_rise"), 0)
				local made = playRound(w, ann, 0.2)
				local over = Rig.last(ann.events, "whack_over")
				t.truthy(over)
				local rises = Rig.count(ann.events, "whack_rise")
				t.truthy(rises >= 40, `{rises} moles`)
				t.eq(over.hits, made, "every mole struck in time was a hit")
				t.eq(over.misses, 0)
				t.eq(over.score, made * Round.HIT)
				t.eq(Rig.count(ann.events, "whack_hit"), made)
				t.truthy(over.place >= 1, "a perfect round makes the board")
				t.truthy(over.newBest)
				local model = w.roots[SITE]:FindFirstChild("GamesRoom"):FindFirstChild("WhackAMole")
				t.truthy(string.find(model:GetAttribute("Best"), "Ann", 1, true), "the board on the cabinet")
				local done = Rig.last(ann.events, "event", function(m: any): boolean
					return m.over == true
				end)
				t.truthy(done and string.find(done.text, "TIME!", 1, true), "the end banner")
				-- the prompt said the cabinet was in use; the end card lets go after doneSeconds
				Rig.run(w, 13)
				t.eq(w.svc:sessionOf(ID).phase, "idle")
			end, opts())
		end
	)

	t.test("refused with words, nothing scored: early, junk, from the future, stale, too fast", function()
		Rig.play(function(w: Rig.World)
			local bo = Rig.stub("Bo")
			t.truthy(w.svc:join(bo, ID))
			local ok, why = Rig.input(w, bo, ID, "whack", { 1, stamp() })
			t.falsy(ok)
			t.eq(why, "Wait for GO!")
			Rig.run(w, Round.READY + 2)
			for _, args in { { 1 }, { 1, "now" }, { 1, 0 / 0 }, { 1, math.huge }, { 7, stamp() }, { "x", stamp() } } do
				ok, why = Rig.input(w, bo, ID, "whack", args)
				t.falsy(ok, `{args[1]} {args[2]}`)
				t.truthy(type(why) == "string" and #why > 0)
			end
			ok, why = Rig.input(w, bo, ID, "whack", { 1, stamp() + 1 })
			t.falsy(ok)
			t.eq(why, "That swing did not match the cabinet's clock")
			ok, why = Rig.input(w, bo, ID, "whack", { 1, stamp() - 1 })
			t.falsy(ok)
			t.eq(why, "That swing reached the cabinet too late")
			t.truthy((Rig.input(w, bo, ID, "whack", { 1, stamp() })))
			ok, why = Rig.input(w, bo, ID, "whack", { 2, stamp() })
			t.falsy(ok)
			t.eq(why, "One swing at a time")
			local r = tbl(w):round()
			t.eq(r.strikes, 1, "one strike judged")
			t.eq(r.score, 0)
		end, opts())
	end)

	t.test("lag: a strike made in time but arriving 150 ms later still scores", function()
		Rig.play(function(w: Rig.World)
			local cy = Rig.stub("Cy")
			t.truthy(w.svc:join(cy, ID))
			Rig.untilTrue(w, Round.READY + 2, function(): boolean
				local _, moles = seen(cy)
				return moles[1] ~= nil
			end)
			local start, moles = seen(cy)
			local m = moles[1]
			Rig.untilTrue(w, 2, function(): boolean
				return stamp() - (start :: number) >= m.at + 0.2
			end)
			local swung = stamp()
			Rig.run(w, 0.15)
			local ok, why = Rig.input(w, cy, ID, "whack", { m.hole, swung })
			t.truthy(ok, why)
			local hit = Rig.last(cy.events, "whack_hit")
			t.eq(hit.result, "hit")
			t.eq(hit.score, Round.HIT)
			t.near(hit.at, m.at + 0.2, 0.02, "judged when it was struck")
		end, opts())
	end)

	t.test("watchers: a late arrival sees the round as it stands; a second player is turned away", function()
		Rig.play(function(w: Rig.World)
			local di = Rig.stub("Di")
			t.truthy(w.svc:join(di, ID))
			Rig.run(w, Round.READY + 6)
			local eve = Rig.stub("Eve")
			near(w, eve, 3)
			Rig.run(w, 0.6)
			local snap = Rig.last(eve.events, "whack_round")
			t.truthy(snap, "the round as it stands, for someone walking up")
			t.eq(snap.start, (Rig.last(di.events, "whack_round") :: any).start)
			local before = Rig.count(eve.events, "whack_rise")
			Rig.run(w, 3)
			t.truthy(Rig.count(eve.events, "whack_rise") > before, "and the stream from then on")
			local ok, why = w.svc:join(eve, ID)
			t.falsy(ok)
			t.truthy(string.find(why or "", "in progress", 1, true), why)
			-- a strike by the player is seen by the watcher
			t.truthy(tbl(w):debug("miss"))
			t.eq((Rig.last(eve.events, "whack_hit") :: any).result, "miss")
		end, opts())
	end)

	t.test(
		"a leaver: the round ends where it stands, the people near are told, the next player starts fresh",
		function()
			Rig.play(function(w: Rig.World)
				local fay = Rig.stub("Fay")
				local gus = Rig.stub("Gus")
				near(w, gus, 3)
				t.truthy(w.svc:join(fay, ID))
				Rig.run(w, Round.READY + 5)
				t.truthy(Rig.input(w, fay, ID, "leave"))
				Rig.run(w, 0.1)
				t.eq(w.svc:sessionOf(ID).phase, "idle")
				t.truthy(Rig.last(gus.events, "whack_idle"), "the watcher hears the cabinet is free")
				t.eq(Rig.last(fay.events, "whack_over"), nil, "no end card for a round walked away from")
				t.truthy(w.svc:join(gus, ID))
				local snap = Rig.last(gus.events, "whack_round")
				t.eq(snap.g, 2, "a new round")
				t.eq(snap.score, 0)
			end, opts())
		end
	)

	t.test("scripted outcomes for the engine check go through the player's own path", function()
		Rig.play(function(w: Rig.World)
			local hal = Rig.stub("Hal")
			t.truthy(w.svc:join(hal, ID))
			t.falsy(w.svc:debug(ID, "hit"), "nothing up in the count-in")
			t.truthy(Rig.untilTrue(w, Round.READY + 2, function(): boolean
				return (w.svc:debug(ID, "hit"))
			end))
			t.eq(tbl(w):round().score, Round.HIT)
			Rig.run(w, 0.2)
			t.truthy(w.svc:debug(ID, "miss"))
			t.eq(tbl(w):round().score, Round.HIT - Round.MISS)
			t.falsy(w.svc:debug(ID, "jump"))
		end, opts())
	end)
end
