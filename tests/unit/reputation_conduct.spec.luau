--!strict
-- Owner D30 (2026-11-22): "make reputation metrics occur in the background ... if a person kicks it at another player or
-- winds up and throws it at another player, their reputation score goes down, or practically runs over people, same
-- thing, but do not mark this or score this often, only in extreme situations ... it should just show you that, then go
-- away, not be a constant meter, but be checkable with money".
--   conduct   the rules (Shared/Reputation/Conduct): a single accident never counts; three hard ball hits in 30 s, or
--             one from a wind-up up close; three people run over in a minute, or the same one twice in 30 s; a rest
--             after each so it is rare; reported acts by severity; the slow recovery; the words
--   service   Server/Reputation/ReputationService: by UserId, the attribute only when it changes, the notice only on a
--             drop and only to that player, recovery worked out when read, a rejoin keeps it
--   door      Shared/Reputation/Reputation.report: nothing bound is a quiet false; bound, it counts; never errors
--   ladder    Roles/RoleService reads the queue's reputation term from the service and sends the Ladder's events to it
local Conduct = require("@shared/Reputation/Conduct")
local Reputation = require("@shared/Reputation/Reputation")
local ReputationService = require("@server/Reputation/ReputationService")
local RoleService = require("@server/Roles/RoleService")

local C = Conduct.C

local function stub(id: number): any
	return { UserId = id, Name = `p{id}` }
end

return function(t)
	t.test("conduct, ball: soft hits and one hard accident never count; three hard hits in 30 s do", function()
		local b = Conduct.newBook()
		t.eq(Conduct.ball(b, 0, { victim = 1, speed = 20 }), nil, "a toss")
		t.eq(Conduct.ball(b, 1, { victim = 1, speed = C.ball.hardSpeed - 1 }), nil, "just under hard")
		t.eq(Conduct.ball(b, 2, { victim = 1, speed = 50 }), nil, "one hard hit: an accident")
		t.eq(Conduct.ball(b, 40, { victim = 2, speed = 50 }), nil, "a second, long after: still nothing")
		t.eq(Conduct.ball(b, 45, { victim = 3, speed = 50 }), nil, "two in the window")
		local d = Conduct.ball(b, 50, { victim = 3, speed = 50 })
		t.truthy(d ~= nil, "three in the window")
		t.eq((d :: any).kind, "ball")
		t.eq((d :: any).points, C.ball.points)
		t.eq((d :: any).words, "you kept hitting people with the ball")
	end)

	t.test(
		"conduct, ball: a long wind-up thrown hard at someone close counts at once; far or quick does not",
		function()
			local b = Conduct.newBook()
			t.eq(Conduct.ball(b, 0, { victim = 1, speed = 50, windup = 1.2, dist = C.ball.closeRange + 5 }), nil, "far")
			t.eq(
				Conduct.ball(Conduct.newBook(), 0, { victim = 1, speed = 50, windup = 0.2, dist = 5 }),
				nil,
				"a quick kick"
			)
			local d = Conduct.ball(Conduct.newBook(), 0, { victim = 1, speed = 50, windup = 1.0, dist = 6 })
			t.eq(d and d.kind, "ball_close")
			t.eq(
				Conduct.ball(Conduct.newBook(), 0, { victim = 1, speed = 20, windup = 1.0, dist = 6 }),
				nil,
				"wound up but soft"
			)
		end
	)

	t.test("conduct, ball: after it counts, nothing counts for the rest (rare, never a stream)", function()
		local b = Conduct.newBook()
		t.truthy(Conduct.ball(b, 0, { victim = 1, speed = 50, windup = 1, dist = 3 }))
		for i = 1, 10 do
			t.eq(Conduct.ball(b, i, { victim = 1, speed = 60, windup = 1, dist = 3 }), nil, `rest {i}`)
		end
		-- hits in the rest are not remembered: after it, a fresh start
		t.eq(Conduct.ball(b, C.ball.rest + 1, { victim = 1, speed = 50 }), nil)
		t.eq(Conduct.ball(b, C.ball.rest + 2, { victim = 1, speed = 50 }), nil)
		t.truthy(Conduct.ball(b, C.ball.rest + 3, { victim = 1, speed = 50 }))
	end)

	t.test(
		"conduct, run over: crawl bumps and two different people never count; three do; same one twice does",
		function()
			local b = Conduct.newBook()
			t.eq(Conduct.runOver(b, 0, { victim = 1, speed = 4 }), nil, "a crawl")
			t.eq(Conduct.runOver(b, 1, { victim = 1, speed = 4 }), nil, "a crawl, again: never")
			t.eq(Conduct.runOver(b, 2, { victim = 2, speed = 20 }), nil, "one person")
			t.eq(Conduct.runOver(b, 40, { victim = 3, speed = 20 }), nil, "a second person (2 in a minute)")
			local d = Conduct.runOver(b, 55, { victim = 4, speed = 20 })
			t.eq(d and d.kind, "run_over", "three different people in a minute")
			local b2 = Conduct.newBook()
			t.eq(Conduct.runOver(b2, 0, { victim = 7, speed = 15 }), nil)
			t.eq(Conduct.runOver(b2, 45, { victim = 7, speed = 15 }), nil, "the same person, but 45 s later")
			local d2 = Conduct.runOver(b2, 60, { victim = 7, speed = 15 })
			t.eq(d2 and d2.kind, "run_same", "the same person twice within 30 s")
			t.eq(d2 and d2.words, "you went back and ran the same person over")
			t.eq(Conduct.runOver(b2, 61, { victim = 8, speed = 30 }), nil, "resting")
		end
	)

	t.test(
		"conduct, reported: counts at once by severity, rests per kind, aliases, unknown kinds read plainly",
		function()
			local b = Conduct.newBook()
			local d = Conduct.reported(b, 0, "errand_theft", 2)
			t.eq(d and d.points, 10)
			t.eq(d and d.words, "you kept an errand's delivery for yourself")
			t.eq(Conduct.reported(b, 10, "stolen_item", 3), nil, "the same kind (an alias) rests")
			local d2 = Conduct.reported(b, 10, "ignored_victim")
			t.eq(d2 and d2.points, 5, "another kind; severity 1 by default")
			t.eq((Conduct.reported(Conduct.newBook(), 0, "ignored_victim", 9) :: any).points, 15, "clamped to 3")
			t.eq((Conduct.reported(Conduct.newBook(), 0, "something_new") :: any).words, Conduct.KINDS.other)
			t.eq(
				(Conduct.reported(Conduct.newBook(), 0, "ball") :: any).words,
				Conduct.KINDS.other,
				"no borrowed words"
			)
			t.truthy(Conduct.reported(b, C.reported.rest + 1, "errand_theft"), "after the rest")
		end
	)

	t.test("conduct: recovery toward 0, the bands, the words", function()
		t.eq(Conduct.recover(-10, C.recoverSecs - 1), -10)
		t.eq(Conduct.recover(-10, C.recoverSecs * 3), -7)
		t.eq(Conduct.recover(-2, C.recoverSecs * 9), 0, "never past 0")
		t.eq(Conduct.recover(12, 99999), 12, "nothing above 0 changes")
		t.eq(Conduct.band(0), "Good", "everybody starts Good")
		t.eq(Conduct.band(-10), "Fair", "one drop")
		t.eq(Conduct.band(-20), "Fair", "two")
		t.eq(Conduct.band(-30), "Poor", "three")
		t.eq(Conduct.band(40), "Trusted")
		t.eq(Conduct.standing(0), "Good (0)")
		t.eq(Conduct.standing(-10), "Fair (-10)")
		t.eq(Conduct.standing(34), "Trusted (+34)")
		t.eq(Conduct.standing(-500), "Poor (-100)")
		local d = Conduct.ball(Conduct.newBook(), 0, { victim = 1, speed = 50, windup = 1, dist = 3 }) :: any
		t.eq(Conduct.notice(d, -10), "Reputation down: you threw the ball hard at someone up close (now Fair)")
		t.eq(Conduct.menuLine(300, 0), "Money  S$3.00   ·   Reputation  Good (0)")
		t.eq(Conduct.menuLine(nil, nil), "Money  --   ·   Reputation  Good (0)")
		-- mild words only
		for _, w in Conduct.KINDS do
			t.falsy(string.find(string.lower(w), "kill", 1, true), w)
		end
	end)

	t.test(
		"service: quiet accidents, one notice on a drop to that player only, the attribute when it changes",
		function()
			local now = 0
			local told: { { any } } = {}
			local shown: { [any]: number } = {}
			local s = ReputationService.new({
				now = function()
					return now
				end,
				tell = function(p: any, words: string)
					table.insert(told, { p, words })
				end,
				publish = function(p: any, rep: number)
					shown[p.UserId] = rep
				end,
			})
			local a, b = stub(1), stub(2)
			s.join(a)
			s.join(b)
			t.eq(shown[1], 0, "everyone starts at 0, published at join")
			t.eq(s.ball(a, { victim = 2, speed = 50 }), nil)
			now = 5
			t.eq(s.ball(a, { victim = 2, speed = 50 }), nil)
			t.eq(#told, 0, "nothing said for accidents")
			now = 10
			t.truthy(s.ball(a, { victim = 2, speed = 50 }))
			t.eq(#told, 1)
			t.eq(told[1][1], a, "told only to the thrower")
			t.eq(told[1][2], "Reputation down: you kept hitting people with the ball (now Fair)")
			t.eq(shown[1], -10)
			t.eq(shown[2], 0, "the victim's untouched")
			t.eq(s.get(a), -10)
			-- recovery when read: one point per C.recoverSecs, published by step
			now = 10 + C.recoverSecs * 2 + 5
			s.step()
			t.eq(shown[1], -8)
			t.eq(s.get(a), -8)
			-- a quiet rise from the Ladder (a kick on the rodent) is never announced
			s.event(a, "kick_landed")
			t.eq(s.get(a), -4)
			t.eq(#told, 1)
			-- a rejoin (a new Player with the same UserId) finds it as it was
			local a2 = stub(1)
			s.join(a2)
			t.eq(s.get(a2), -4)
			t.eq(shown[1], -4)
		end
	)

	t.test("service: run overs and reports; the part-step of recovery is kept across a change", function()
		local now = 0
		local told = 0
		local s = ReputationService.new({
			now = function()
				return now
			end,
			tell = function()
				told += 1
			end,
		})
		local p = stub(9)
		t.eq(s.runOver(p, { victim = 1, speed = 20 }), nil)
		now = 2
		t.truthy(s.runOver(p, { victim = 1, speed = 20 }), "the same one twice")
		t.eq(s.get(p), -10)
		t.truthy(s.report(p, "errand_theft", 3))
		t.eq(s.get(p), -25)
		t.eq(s.report(p, "errand_theft", 3), false, "resting")
		t.eq(s.report(p, "", 3), false)
		t.eq(told, 2)
		now = 2 + C.recoverSecs * 1.5
		s.event(p, "gig_tip") -- +2 after one step back
		t.eq(s.get(p), -22)
		now = 2 + C.recoverSecs * 2 + 1
		t.eq(s.get(p), -21, "the half step earned before the tip still counts")
		s.import(p, 500)
		t.eq(s.export(p), 100)
	end)

	t.test("door: Reputation.report is a quiet false unbound, counts when bound, never errors", function()
		Reputation.bind(nil)
		t.eq(Reputation.report(stub(1), "errand_theft", 2), false)
		local now = 0
		local s = ReputationService.new({
			now = function()
				return now
			end,
		})
		Reputation.bind(s)
		t.truthy(Reputation.bound())
		t.eq(Reputation.report(stub(1), "errand_theft", 2), true)
		t.eq(s.get(stub(1)), -10)
		t.eq(Reputation.report(nil, "errand_theft"), false)
		Reputation.bind({
			report = function(): boolean
				error("boom")
			end,
		})
		t.eq(Reputation.report(stub(1), "x"), false, "a broken sink never errors in the caller")
		Reputation.bind(nil)
	end)

	t.test("ladder: RoleService's queue term is the service's score, and the Ladder's events go to it", function()
		local now = 0
		local s = ReputationService.new({
			now = function()
				return now
			end,
		})
		local possession = {
			possess = function()
				return true
			end,
			release = function() end,
			swap = function() end,
			actorOf = function()
				return nil
			end,
		}
		local roles = RoleService.new({
			possession = possession,
			pickBody = function()
				return nil
			end,
			kick = function() end,
			reputation = s,
		})
		local p = stub(5)
		roles:onJoin(p)
		t.eq((roles:stats(p) :: any).reputation, 0)
		s.report(p, "ignored_victim", 3)
		t.eq((roles:stats(p) :: any).reputation, -15, "read from the service every time")
		local ctx = roles:ctx()
		t.eq(ctx.players[5].stats.reputation, -15, "and in the queue's context")
		-- a rule's reputation event (a landed kick on the rodent) goes to the service
		roles:report({ kind = "kick.landed", player = 5, target = "rodent" })
		t.eq(s.get(p), -11)
		t.eq((roles:stats(p) :: any).reputation, -11)
	end)
end
