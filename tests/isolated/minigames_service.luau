--!strict
-- tests/isolated/minigames_service.luau: cases for tests/unit/minigames_service.spec.luau, run in their own
-- Lune process (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Server/Minigames/MinigameService with real BowlingLane hardware on that fake engine: the bowling glue end to
-- end, which no cloud check can show from here. A person joins a lane, starts, and bowls real throws through
-- the input path: the server decides each one, announces its script to everyone, moves the ball and pins,
-- scores what fell, runs the pinsetter and hands the ball back. Covered: a whole game alone; a gutter ball;
-- the thrower leaving mid-roll (never scored against the next bowler); an idle turn on a half-finished frame
-- (the next bowler gets ten fresh pins); a game against a computer; a squirrel on the lane (knocked into the
-- gutter, the throw counts); refusals that always say why; an abandoned throw.
-- Interface: return function(t) (the spec shape)
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Bowling = require("@shared/Minigames/MinigameRules/Bowling")
local Intruders = require("@shared/Minigames/Bowling/Intruders")
local PartPose = require("@shared/Minigames/Bowling/PartPose")
local RollScript = require("@shared/Minigames/Bowling/RollScript")
local MinigameService = require("@server/Minigames/MinigameService")
local FakeEngine = require("@tests/lib/FakeEngine")
local roblox = require("@lune/roblox")

local PLACE: AlleyLayout.Place = { x = 120, z = -40, floorY = 18, yaw = 0.3 }
local LANE = "bowling_lane_3"
local POCKET = { 0.165, 0, 0.7, 0 } -- offset, angle, power, spin: a quarter stud right of the head pin
local THIN = { 0.5, 0, 0.7, 0 }
local GUTTER = { 1, 0.1, 0.7, 0 }

local function v3(x: number, y: number, z: number): any
	return roblox.CFrame.new(x, y, z)
end

-- the parts BowlingLane looks for, where the bake puts them
local function buildAlley(): any
	local root = FakeEngine.new("Model", "BowlingAlley")
	local lanes = FakeEngine.new("Folder", "Lanes")
	lanes.Parent = root
	for lane = 1, AlleyLayout.LANES do
		local lm = FakeEngine.model(`Lane{lane}`, v3(0, 0, 0), lanes)
		local rx, ry, rd = AlleyLayout.rackSlot(lane)
		FakeEngine.part("Ball", v3(AlleyLayout.toWorld(PLACE, rx, ry, rd)), lm)
		local pins = FakeEngine.new("Folder", "Pins")
		pins.Parent = lm
		for n = 1, 10 do
			local px, pd = AlleyLayout.pinLocal(lane, n)
			local home = v3(AlleyLayout.toWorld(PLACE, px, 0.45, pd))
			local pm = FakeEngine.model(`Pin{n}`, home, pins)
			FakeEngine.part("Body", home, pm)
			FakeEngine.part("Head", home + roblox.Vector3.new(0, 0.84, 0), pm)
		end
		local sx = AlleyLayout.laneX(lane)
		local sweepAt = v3(AlleyLayout.toWorld(PLACE, sx, AlleyLayout.MASK_BOTTOM + 0.4, AlleyLayout.DECK_START - 0.05))
		FakeEngine.part("Sweep", sweepAt, lm)
		FakeEngine.part("SweepEdge", sweepAt, lm)
	end
	return root
end

type World = {
	svc: any,
	root: any,
	all: { any }, -- what was sent to every client
	animals: { any },
	knocks: { any },
	handler: ((player: any, payload: any) -> ())?,
}

local function world(seed: number?): World
	local w: World = { svc = nil, root = buildAlley(), all = {}, animals = {}, knocks = {}, handler = nil }
	local net = {
		on = function(_self: any, _name: string, fn: (player: any, payload: any) -> ())
			w.handler = fn
		end,
		fire = function(_self: any, _player: any, _name: string, _payload: any) end,
		fireAll = function(_self: any, _name: string, payload: any)
			table.insert(w.all, payload)
		end,
	}
	w.svc = MinigameService.new({
		root = w.root,
		place = PLACE,
		net = net,
		prompts = false,
		seed = seed or 5,
		canPlay = function(p: any): (boolean, string?)
			if p.animal then
				return false, "Only people can play"
			end
			return true
		end,
		bodyOf = function(_p: any): any
			return nil
		end,
		animals = function(): { any }
			return w.animals
		end,
		knock = function(id: any, x: number, y: number, z: number, text: string)
			table.insert(w.knocks, { id = id, x = x, y = y, z = z, text = text })
			for _, a in w.animals do
				if a.id == id then
					a.x, a.y, a.z = x, y, z
				end
			end
		end,
	})
	return w
end

local function stub(name: string): any
	return { Name = name, UserId = #name, events = {} }
end

local function step(w: World, seconds: number, dt: number?)
	local d = dt or 0.1
	for _ = 1, math.ceil(seconds / d) do
		w.svc:step(d)
	end
end

local function input(w: World, p: any, verb: string, args: { any }?): (boolean, string?)
	return w.svc:input(p, { gameId = LANE, seat = 1, verb = verb, args = args or {} })
end

local function lane(w: World): any
	return w.svc.stations[LANE].hw
end

local function untilReady(w: World, limit: number?)
	local t = 0
	while not lane(w):ready() and t < (limit or 20) do
		w.svc:step(0.1)
		t += 0.1
	end
end

local function last(p: any, kind: string, pred: ((e: any) -> boolean)?): any
	for i = #p.events, 1, -1 do
		local e = p.events[i]
		if e.kind == kind and (pred == nil or pred(e)) then
			return e
		end
	end
	return nil
end

local function count(p: any, kind: string): number
	local n = 0
	for _, e in p.events do
		if e.kind == kind then
			n += 1
		end
	end
	return n
end

local function seated(w: World, players: { any }): any
	for _, p in players do
		assert(w.svc:join(p, LANE))
	end
	assert(input(w, players[1], "start"))
	step(w, 0.2)
	return w.svc:sessionOf(LANE)
end

local function rolls(s: any, seat: number): { number }
	return s.game.state.rolls[seat]
end

return function(t)
	t.test("a whole game alone with real throws: decided, announced, drawn, scored, re-racked, summed up", function()
		FakeEngine.with(function()
			local w = world()
			local p = stub("Ann")
			t.truthy(w.svc:join(p, LANE))
			t.eq(w.svc:sessionOf(LANE).phase, "lobby")
			t.truthy(last(p, "joined") ~= nil)
			t.truthy(input(w, p, "start"))
			local s = w.svc:sessionOf(LANE)
			t.eq(s.phase, "playing")
			step(w, 0.2)
			local hw = lane(w)
			local ball = hw.ball
			local rack = ball.CFrame.Position
			local head = hw.pins[1].model
			-- pinned on the server: never simulated, never in the way; and stamped for client playback
			t.truthy(head:FindFirstChild("Body").Anchored)
			t.eq(head:FindFirstChild("Body").CanCollide, false)
			t.truthy(head:GetAttribute(PartPose.HOME) ~= nil)
			t.truthy(ball:GetAttribute(PartPose.RACK) ~= nil)
			local balls, total, guard = 0, 0, 0
			local sawBallOnLane, sawTilt, sawSweep = false, false, false
			local sweepHome = hw.sweepPart.CFrame.Position
			while s.phase == "playing" and guard < 40 do
				guard += 1
				t.truthy(hw:ready(), "the lane is ready for each ball")
				local before = #w.all
				local ok, why = input(w, p, "release", POCKET)
				t.truthy(ok, why)
				balls += 1
				-- announced at once, to everyone, as a playable script; and to the seated stub too
				t.eq(#w.all, before + 1)
				local roll = w.all[#w.all]
				t.eq(roll.kind, "roll")
				t.eq(roll.lane, 3)
				t.eq(roll.seat, 1)
				t.eq(roll.name, "Ann")
				local script, bad = RollScript.check(roll.script)
				t.truthy(script ~= nil, bad)
				t.truthy(last(p, "roll") ~= nil and last(p, "roll").script == roll.script)
				local events = count(p, "event")
				-- while it rolls: the ball leaves the rack and runs the lane, pins tip
				local tt = 0
				while not hw:ready() and tt < 20 do
					w.svc:step(0.05)
					tt += 0.05
					local _, _, d = AlleyLayout.toLocal(PLACE, ball.CFrame.X, ball.CFrame.Y, ball.CFrame.Z)
					if d > 20 and d < 50 then
						sawBallOnLane = true
					end
					if hw.pins[1].last[4] > 1 then
						sawTilt = true
					end
					if (hw.sweepPart.CFrame.Position - sweepHome).Magnitude > 3 then
						sawSweep = true
					end
				end
				t.truthy(tt < 12, `a ball took {tt} s from hand to hand`)
				-- scored exactly what the script knocked down, with words
				local banner = last(p, "event", function(e)
					return e.pins ~= nil
				end)
				t.truthy(count(p, "event") > events)
				t.eq(banner.pins, (script :: any).down)
				t.truthy(type(banner.text) == "string" and #banner.text > 3)
				total += banner.pins
				-- the ball is back on its rack, the bar is back up
				t.truthy((ball.CFrame.Position - rack).Magnitude < 0.01, "the ball came home")
				t.truthy((hw.sweepPart.CFrame.Position - sweepHome).Magnitude < 0.01)
			end
			t.truthy(
				sawBallOnLane and sawTilt and sawSweep,
				"the ball ran the lane, the head pin tipped, the bar swept"
			)
			t.eq(s.phase, "done")
			local mine = rolls(s, 1)
			t.eq(#mine, balls)
			local sum = 0
			for _, r in mine do
				sum += r
			end
			t.eq(sum, total, "every pin that fell is on the sheet, and nothing else")
			t.eq(s.result.scores[1], Bowling.total(mine))
			t.truthy(s.result.scores[1] >= 120, `ten frames of pocket balls scored {s.result.scores[1]}`)
			-- the end: a banner with the score, the state says done, the lane shows ten for the next game
			local over = last(p, "event", function(e)
				return e.over == true
			end)
			t.eq(over.text, `Final score: {s.result.scores[1]}`)
			t.eq(last(p, "state").view.phase, "done")
			t.eq(hw:standingCount(), 10)
			for n = 1, 10 do
				local pin = hw.pins[n]
				t.truthy((pin.model:GetPivot().Position - pin.home.Position).Magnitude < 1e-3, `pin {n} is on its spot`)
				t.eq(pin.model:FindFirstChild("Body").Transparency, 0)
			end
			-- play again from the end card
			t.truthy(input(w, p, "again"))
			t.eq(s.phase, "playing")
			t.deepEq(rolls(s, 1), {})
		end)
	end)

	t.test("a gutter ball scores nothing and is called one; the pins never moved", function()
		FakeEngine.with(function()
			local w = world()
			local p = stub("Ann")
			local s = seated(w, { p })
			t.truthy(input(w, p, "release", GUTTER))
			t.eq(w.all[#w.all].script.flags.gutter, true)
			untilReady(w)
			local banner = last(p, "event", function(e)
				return e.pins ~= nil
			end)
			t.eq(banner.text, "Gutter ball")
			t.eq(banner.pins, 0)
			t.deepEq(rolls(s, 1), { 0 })
			t.eq(lane(w):standingCount(), 10)
			t.eq(s.game.state.ballOf[1], 2, "still the same frame: the second ball")
		end)
	end)

	t.test("the thrower leaves while the ball rolls: the next bowler's sheet is untouched and gets ten pins", function()
		FakeEngine.with(function()
			local w = world()
			local ann, bob = stub("Ann"), stub("Bob")
			local s = seated(w, { ann, bob })
			t.truthy(input(w, ann, "release", POCKET))
			step(w, 0.5)
			w.svc:leave(ann, "left")
			t.truthy(last(ann, "left") ~= nil)
			untilReady(w)
			t.deepEq(rolls(s, 2), {}, "Bob has not bowled: Ann's ball is not on his sheet")
			t.deepEq(rolls(s, 1), { 0, 0 }, "Ann's frame was played out as misses")
			t.eq(s.game.rules.turn(s.game.state), 2)
			local told = last(bob, "event", function(e)
				return e.ok == false
			end)
			t.truthy(told ~= nil and string.find(told.text, "does not count", 1, true) ~= nil, "and Bob is told")
			t.eq(lane(w):standingCount(), 10)
			-- Bob's own throw is his
			t.truthy(input(w, bob, "release", POCKET))
			local down = w.all[#w.all].script.down
			untilReady(w)
			t.eq(rolls(s, 2)[1], down)
		end)
	end)

	t.test(
		"an idle turn on a half-finished frame: the frame is skipped and the next bowler gets ten fresh pins",
		function()
			FakeEngine.with(function()
				local w = world()
				local ann, bob = stub("Ann"), stub("Bob")
				local s = seated(w, { ann, bob })
				t.truthy(input(w, ann, "release", THIN))
				local first = w.all[#w.all].script
				t.truthy(first.down > 0 and first.down < 10, `the thin ball took {first.down}`)
				untilReady(w)
				t.eq(lane(w):standingCount(), 10 - first.down)
				-- the state every second carries the turn clock the screen counts down
				step(w, 2)
				local st = last(ann, "state")
				t.truthy(st.view.turnLeft ~= nil and st.view.turnLeft <= 60 and st.view.turnLeft >= 55)
				t.eq(st.ready, true)
				-- Ann walks off to get a drink
				step(w, 61, 0.5)
				local told = last(bob, "event", function(e)
					return string.find(tostring(e.text), "took too long", 1, true) ~= nil
				end)
				t.truthy(told ~= nil)
				t.deepEq(rolls(s, 1), { first.down, 0 })
				t.eq(s.game.rules.turn(s.game.state), 2)
				untilReady(w)
				t.eq(lane(w):standingCount(), 10, "the pinsetter set a full rack for Bob")
				t.truthy(input(w, bob, "release", POCKET))
				local script = w.all[#w.all].script
				for n = 1, 10 do
					t.eq(script.mask[n], true)
				end
				untilReady(w)
				t.eq(rolls(s, 2)[1], script.down)
			end)
		end
	)

	t.test(
		"against a computer: it bowls its own frames with real throws, announced like anyone's, and scores",
		function()
			FakeEngine.with(function()
				local w = world(9)
				local p = stub("Ann")
				t.truthy(w.svc:join(p, LANE))
				local okAi, whyAi = input(w, p, "addai")
				t.truthy(okAi, whyAi)
				local s = w.svc:sessionOf(LANE)
				t.eq(#s.seats, 2)
				t.truthy(s.seats[2].ai and s.seats[2].skill == "normal")
				t.eq(s.names[2], "Bowlbot (computer)")
				t.truthy(input(w, p, "start"))
				local late, lateWhy = input(w, p, "addai")
				t.falsy(late)
				t.truthy(string.find(lateWhy :: string, "lobby", 1, true) ~= nil)
				local guard, aiRolls = 0, 0
				local seen = #w.all
				while s.phase == "playing" and guard < 4000 do
					guard += 1
					w.svc:step(0.1)
					if s.phase == "playing" and s.game.rules.turn(s.game.state) == 1 and lane(w):ready() then
						t.truthy(input(w, p, "release", POCKET))
					end
					for i = seen + 1, #w.all do
						local m = w.all[i]
						if m.kind == "roll" and m.seat == 2 then
							aiRolls += 1
							t.truthy(RollScript.check(m.script) ~= nil)
							t.eq(m.name, "Bowlbot (computer)")
						end
					end
					seen = #w.all
				end
				t.eq(s.phase, "done")
				local theirs = rolls(s, 2)
				t.eq(#theirs, aiRolls, "every computer ball was a real, announced throw")
				t.truthy(#theirs >= 11)
				t.truthy(
					s.result.scores[2] >= 60 and s.result.scores[2] < 290,
					`the computer scored {s.result.scores[2]}`
				)
				t.truthy(s.result.scores[1] >= 120)
				local over = last(p, "event", function(e)
					return e.over == true
				end)
				t.truthy(
					string.find(over.text, "wins with", 1, true) ~= nil or string.find(over.text, "tie", 1, true) ~= nil
				)
				-- the human leaves: a table of only computers resets
				w.svc:leave(p, "left")
				step(w, 0.3)
				t.eq(s.phase, "idle")
			end)
		end
	)

	t.test("a squirrel on the lane is knocked into the gutter, everyone is told, and the throw still counts", function()
		FakeEngine.with(function()
			local w = world()
			local p = stub("Ann")
			local s = seated(w, { p })
			local lx = AlleyLayout.laneX(3)
			local function at(X: number, Y: number, D: number, id: string, kind: string): any
				local x, y, z = AlleyLayout.toWorld(PLACE, X, Y, D)
				return { id = id, kind = kind, x = x, y = y, z = z }
			end
			w.animals = {
				at(lx + 0.3, 0.5, 30, "sq1", "squirrel"), -- right in the ball's way
				at(lx + AlleyLayout.PITCH + 0.3, 0.5, 30, "sq2", "squirrel"), -- the same spot on the next lane
				at(lx, -2, 30, "sq3", "rodent"), -- in the ball-return duct under the lane
			}
			t.truthy(input(w, p, "release", POCKET), "an animal on the lane never holds up a throw")
			local script = w.all[#w.all].script
			untilReady(w)
			t.eq(#w.knocks, 1)
			local k = w.knocks[1]
			t.eq(k.id, "sq1")
			t.eq(k.text, Intruders.TEXT.animal)
			local X, _, D = AlleyLayout.toLocal(PLACE, k.x, k.y, k.z)
			t.near(math.abs(X - lx), Intruders.GUTTER_X, 1e-3, "into the gutter of its own lane")
			t.truthy(D < 30 and D > 0)
			local told = last(p, "event", function(e)
				return e.intruder == true
			end)
			t.truthy(told ~= nil)
			t.truthy(string.find(told.text, "A squirrel", 1, true) ~= nil)
			t.truthy(string.find(told.text, "The throw counts", 1, true) ~= nil)
			t.eq(rolls(s, 1)[1], script.down, "the pinfall is exactly what the throw earned")
			t.truthy(script.down >= 7)
			-- the Spicy Rodent sitting among the pins when the bar comes down is pushed off too
			w.knocks = {}
			w.animals = { at(lx - 0.4, 0.5, 57, "rod", "rodent") }
			if s.phase == "playing" and lane(w):ready() then
				t.truthy(input(w, p, "release", GUTTER))
				untilReady(w)
				t.eq(#w.knocks, 1)
				t.eq(w.knocks[1].id, "rod")
				t.eq(w.knocks[1].text, Intruders.TEXT.animalSwept)
				local rodentTold = last(p, "event", function(e)
					return e.intruder == true and string.find(e.text, "The Spicy Rodent", 1, true) ~= nil
				end)
				t.truthy(rodentTold ~= nil)
			end
		end)
	end)

	t.test("nothing is refused silently: every refusal has words, and reaches the player through the net", function()
		FakeEngine.with(function()
			local w = world()
			local ann, bob, cat = stub("Ann"), stub("Bob"), stub("Cat")
			local nut = stub("Nut")
			nut.animal = true
			local okNut, whyNut = w.svc:join(nut, LANE)
			t.falsy(okNut)
			t.eq(whyNut, "Only people can play")
			t.eq(last(nut, "refused").text, "Only people can play")
			local s = seated(w, { ann, bob })
			local function refused(p: any, verb: string, args: { any }?): string
				local ok, why = input(w, p, verb, args)
				t.falsy(ok, `{verb} should be refused`)
				t.truthy(type(why) == "string" and #(why :: string) > 8, `{verb}: a refusal needs words`)
				return why :: string
			end
			t.eq(refused(bob, "release", POCKET), "Not your turn yet")
			t.truthy(string.find(refused(cat, "release", POCKET), "walk up and press E", 1, true) ~= nil)
			t.truthy(input(w, ann, "release", POCKET))
			t.eq(refused(ann, "release", POCKET), "Wait for the pinsetter and the ball")
			refused(ann, "tilt")
			refused(ann, "start")
			local okJoin, whyJoin = w.svc:join(cat, LANE)
			t.falsy(okJoin)
			t.truthy(string.find(whyJoin :: string, "in progress", 1, true) ~= nil)
			-- through the net handler the player is sent the words and which input it was
			local handler = w.handler :: (player: any, payload: any) -> ()
			handler(ann, { gameId = LANE, seat = 1, verb = "release", args = POCKET })
			local r = last(ann, "refused")
			t.eq(r.text, "Wait for the pinsetter and the ball")
			t.eq(r.verb, "release")
			t.eq(r.station, LANE)
			handler(ann, "nonsense")
			t.truthy(#last(ann, "refused").text > 8)
			-- after the game
			untilReady(w)
			w.svc:leave(bob, "left")
			local guard = 0
			while s.phase == "playing" and guard < 400 do
				guard += 1
				if lane(w):ready() then
					input(w, ann, "release", GUTTER)
				end
				step(w, 0.5, 0.25)
			end
			t.eq(s.phase, "done")
			t.truthy(string.find(refused(ann, "release", POCKET), "game is over", 1, true) ~= nil)
		end)
	end)

	t.test(
		"a throw cut short (the bowler walks off alone): the lane is whole at once and clients are told to stop",
		function()
			FakeEngine.with(function()
				local w = world()
				local p = stub("Ann")
				local s = seated(w, { p })
				t.truthy(input(w, p, "release", POCKET))
				step(w, 2.2) -- the ball is among the pins
				local hw = lane(w)
				t.falsy(hw:ready())
				w.svc:leave(p, "left")
				t.eq(s.phase, "idle")
				t.truthy(hw:ready())
				t.eq(hw:standingCount(), 10)
				local cut = w.all[#w.all]
				t.eq(cut.kind, "rack")
				t.eq(cut.lane, 3)
				t.eq(#cut.mask, 10)
				for n = 1, 10 do
					t.eq(cut.mask[n], true)
					t.truthy((hw.pins[n].model:GetPivot().Position - hw.pins[n].home.Position).Magnitude < 1e-3)
				end
				t.truthy((hw.ball.CFrame.Position - hw.rackCF.Position).Magnitude < 1e-3)
				-- nothing stale turns up later, and the lane is open for the next game
				step(w, 8)
				t.eq(s.phase, "idle")
				local q = stub("Bob")
				t.truthy(w.svc:join(q, LANE))
				t.truthy(input(w, q, "start"))
				step(w, 0.2)
				t.truthy(input(w, q, "release", POCKET))
			end)
		end
	)
end
