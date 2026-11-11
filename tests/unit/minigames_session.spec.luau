--!strict
-- Minigames/Session (BUILD_PLAN §1.1 rule 13, D28): seats, the lobby, start, turn order through the rules,
-- the idle-turn clock, players who leave mid-game, the end card and play-again; plus the fortune machine
-- (one seat: it starts on the spot; no money ever).
local Bowling = require("@shared/Minigames/MinigameRules/Bowling")
local Darts = require("@shared/Minigames/MinigameRules/Darts")
local FortuneMachine = require("@shared/Minigames/MinigameRules/FortuneMachine")
local Session = require("@shared/Minigames/Session")

return function(t)
	t.test("lobby: first join opens it; others join; it starts on the clock or on demand; full is refused", function()
		local s = Session.new(Bowling, { lobbySeconds = 10, turnSeconds = 30 })
		t.eq(s.phase, "idle")
		local ok, _, seat = Session.join(s, "a", "Ann", 0)
		t.truthy(ok)
		t.eq(seat, 1)
		t.eq(s.phase, "lobby")
		t.truthy(Session.join(s, "b", "Bob", 1))
		t.truthy(Session.join(s, "c", "Cat", 2))
		t.truthy(Session.join(s, "d", "Dee", 3))
		local full, why = Session.join(s, "e", "Eve", 4)
		t.falsy(full)
		t.truthy(string.find(why :: string, "full", 1, true) ~= nil)
		t.eq(Session.leave(s, "c", 5), 3)
		t.eq(#s.seats, 3)
		local events = Session.step(s, 9)
		t.eq(#events, 0)
		events = Session.step(s, 10)
		t.eq(events[1].kind, "start")
		t.eq(s.phase, "playing")
		t.eq(Session.turnKey(s), "a")
		local late, lateWhy = Session.join(s, "z", "Zed", 11)
		t.falsy(late)
		t.truthy(string.find(lateWhy :: string, "in progress", 1, true) ~= nil)
		-- start on demand
		local s2 = Session.new(Bowling, { lobbySeconds = 10 })
		Session.join(s2, "a", "Ann", 0)
		t.truthy(Session.start(s2, 1))
		t.eq(s2.phase, "playing")
	end)

	t.test("turns follow the rules; only the turn's player may act; the server rolls for the lane", function()
		local s = Session.new(Bowling, { lobbySeconds = 0 })
		Session.join(s, "a", "Ann", 0)
		t.eq(s.phase, "playing") -- lobby 0: starts on the first join
		local ok = Session.apply(s, "server", "roll", { 7 }, 1)
		t.truthy(ok)
		t.truthy(Session.apply(s, "server", "roll", { 2 }, 2))
		t.eq(Bowling.total((s.game :: any).state.rolls[1]), 9)
		t.falsy(Session.apply(s, "nobody", "roll", { 1 }, 3))
	end)

	t.test("idle turns are played out; two in a row takes the player off; the game still ends", function()
		local s = Session.new(Bowling, { lobbySeconds = 0, turnSeconds = 30, maxTimeouts = 2 })
		Session.join(s, "a", "Ann", 0)
		Session.step(s, 0)
		local events = Session.step(s, 31)
		t.eq(events[1].kind, "timeout")
		t.deepEq((s.game :: any).state.rolls[1], { 0, 0 })
		events = Session.step(s, 62)
		local kinds = {}
		for _, e in events do
			table.insert(kinds, e.kind)
		end
		t.truthy(table.find(kinds, "removed") ~= nil)
		t.eq(s.phase, "idle", "nobody left: the table resets")
	end)

	t.test("a player who walks away mid-game: their frames are played out and the others finish", function()
		local s = Session.new(Bowling, { lobbySeconds = 5, turnSeconds = 0 })
		Session.join(s, "a", "Ann", 0)
		Session.join(s, "b", "Bob", 0)
		Session.start(s, 1)
		Session.step(s, 1)
		Session.leave(s, "a", 2)
		Session.step(s, 2)
		t.eq(Session.turnKey(s), "b")
		local guard = 0
		while s.phase == "playing" and guard < 100 do
			guard += 1
			t.truthy(Session.apply(s, "server", "roll", { 10 }, 3))
			Session.step(s, 3)
		end
		t.eq(s.phase, "done")
		local r = s.result :: any
		t.eq(r.scores[2], 300)
		t.eq(r.scores[1], 0)
		t.eq(r.winner, 2)
		-- play again with the player still seated, then the card times out
		t.truthy(Session.again(s, 10))
		t.eq(#s.seats, 1)
		t.eq(s.phase, "playing")
		Session.reset(s)
		t.eq(s.phase, "idle")
	end)

	t.test("darts lobby: mode chosen before the start sticks; view carries seats and the board", function()
		local s = Session.new(Darts, { lobbySeconds = 5 })
		Session.join(s, "a", "Ann", 0)
		t.truthy(Session.apply(s, "a", "mode", { "cricket" }, 1))
		t.falsy(Session.apply(s, "a", "mode", { "pool" }, 1))
		Session.start(s, 2)
		t.eq((s.game :: any).state.mode, "cricket")
		local v = Session.view(s, 2)
		t.eq(v.phase, "playing")
		t.eq(v.game.mode, "cricket")
		t.eq(v.seats[1].name, "Ann")
		t.eq(v.turn, 1)
	end)

	t.test("fortune machine: one seat starts on the spot; a pull is a card, never money", function()
		local s = Session.new(FortuneMachine, { turnSeconds = 0, doneSeconds = 3 })
		Session.join(s, "a", "Ann", 0)
		t.eq(s.phase, "playing")
		t.truthy(Session.apply(s, "a", "pull", nil, 0.5))
		t.eq(s.phase, "done")
		local r = s.result :: any
		t.eq(r.cents, 0)
		t.eq(#r.reels, 3)
		t.truthy(type(r.line) == "string" and #r.line > 0)
		t.truthy(r.kind == "fortune" or r.kind == "taunt" or r.kind == "omen")
		local events = Session.step(s, 4)
		t.eq(events[1].kind, "done")
		t.eq(events[2].kind, "reset")
		-- many pulls: all three card kinds appear, all lines non-empty
		local kinds: { [string]: boolean } = {}
		local g = FortuneMachine.init(1, 99)
		for _ = 1, 600 do
			FortuneMachine.input(g, 1, "pull")
			local res = FortuneMachine.result(g) :: any
			kinds[res.kind] = true
			t.truthy(#res.line > 0)
			t.eq(res.cents, 0)
		end
		t.truthy(kinds.fortune and kinds.taunt and kinds.omen)
	end)
	t.test("leaving at the end card keeps every sheet under its own name", function()
		local s = Session.new(Bowling, { lobbySeconds = 5, turnSeconds = 0, doneSeconds = 30 })
		Session.join(s, "a", "Ann", 0)
		Session.join(s, "b", "Bob", 0)
		Session.start(s, 1)
		-- Ann bowls a perfect game, Bob never hits a pin
		local guard = 0
		while s.phase == "playing" and guard < 100 do
			guard += 1
			local pins = if Session.turnKey(s) == "a" then 10 else 0
			t.truthy(Session.apply(s, "server", "roll", { pins }, 2))
			Session.step(s, 2)
		end
		t.eq(s.phase, "done")
		t.eq((s.result :: any).scores[1], 300)
		t.eq((s.result :: any).scores[2], 0)
		-- Ann presses Leave on the end card first
		t.eq(Session.leave(s, "a", 3), 1)
		t.eq(s.phase, "done", "Bob still has the card")
		t.eq(Session.seatOf(s, "a"), nil)
		t.eq(Session.seatOf(s, "b"), 2, "Bob keeps the seat his sheet is numbered by")
		local v = Session.view(s, 3)
		t.eq(v.seats[2].name, "Bob")
		t.eq(v.game.seats[2].total, 0, "Bob's sheet is still Bob's")
		t.eq(v.seats[1].name, "Ann")
		t.eq(v.seats[1].gone, true)
		t.eq(v.game.seats[1].total, 300)
		t.eq(v.result.scores[2], 0)
		-- play again seats only who stayed
		t.truthy(Session.again(s, 4))
		t.eq(#s.seats, 1)
		t.eq(s.names[1], "Bob")
		t.eq(Session.seatOf(s, "b"), 1)
		-- the last one off the end card empties the table
		local s2 = Session.new(Bowling, { lobbySeconds = 0, turnSeconds = 0 })
		Session.join(s2, "a", "Ann", 0)
		for _ = 1, 12 do
			Session.apply(s2, "server", "roll", { 10 }, 1)
		end
		t.eq(s2.phase, "done")
		Session.leave(s2, "a", 2)
		t.eq(s2.phase, "idle")
		t.eq(#s2.seats, 0)
	end)

	t.test("the end of a game is announced exactly once, however it ended", function()
		-- ended by the last input (the usual way): step says "done" once, later "reset"
		local s = Session.new(Bowling, { lobbySeconds = 0, turnSeconds = 60, doneSeconds = 30 })
		Session.join(s, "a", "Ann", 0)
		Session.step(s, 0)
		for _ = 1, 12 do
			t.truthy(Session.apply(s, "server", "roll", { 10 }, 1))
		end
		t.eq(s.phase, "done")
		local kinds = {}
		for _, e in Session.step(s, 1.1) do
			table.insert(kinds, e.kind)
		end
		t.deepEq(kinds, { "done" })
		t.eq(#Session.step(s, 2), 0, "not said twice")
		t.eq(Session.step(s, 40)[1].kind, "reset")
		-- ended by skipped turns: also once
		local s2 = Session.new(Bowling, { lobbySeconds = 5, turnSeconds = 0 })
		Session.join(s2, "a", "Ann", 0)
		Session.join(s2, "b", "Bob", 0)
		Session.start(s2, 1)
		for _ = 1, 20 do
			Session.apply(s2, "server", "roll", { 0 }, 1)
			Session.step(s2, 1)
			if s2.phase == "playing" and Session.turnKey(s2) == "a" then
				break
			end
		end
		Session.leave(s2, "a", 2)
		local dones = 0
		for i = 1, 60 do
			if s2.phase == "playing" then
				Session.apply(s2, "server", "roll", { 0 }, 2 + i)
			end
			for _, e in Session.step(s2, 2 + i * 0.01) do
				if e.kind == "done" then
					dones += 1
				end
			end
		end
		t.eq(s2.phase, "done")
		t.eq(dones, 1)
		-- play again: the next game's end is announced too
		t.truthy(Session.again(s2, 10))
		t.eq(s2.doneTold, false)
	end)
end
