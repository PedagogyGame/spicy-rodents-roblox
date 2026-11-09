--!strict
-- Server/Roles/RoleService + RoleLab + Client/RoleLab (BUILD_PLAN §4.4 #4): join and leave under the
-- 49 cap, offers with timeouts, cascades and retries, the promotion chain, the idle release (D34),
-- forceRole and the Lab's "Become X", and a 200-step scripted churn holding the slot invariants.
local Ladder = require("@shared/Roles/Ladder")
local Log = require("@shared/Util/Log")
local RoleLab = require("@server/Roles/RoleLab")
local RoleLabClient = require("@client/RoleLab/RoleLabClient")
local RoleService = require("@server/Roles/RoleService")
local Rng = require("@shared/Util/Rng")

local function world()
	local now = 0
	local bodies = 0
	local notes = {}
	local possession = {
		by = {},
		possess = function(self, p, a)
			self.by[p.UserId] = a
			return true
		end,
		release = function(self, p)
			self.by[p.UserId] = nil
		end,
		swap = function(self, p, a)
			self.by[p.UserId] = a
			return true
		end,
		actorOf = function(self, p)
			return self.by[p.UserId]
		end,
	}
	local roles = RoleService.new({
		possession = possession,
		pickBody = function(_p, rung)
			bodies += 1
			return { id = `{rung or "human"}_{bodies}`, rung = rung }
		end,
		kick = function(p, msg)
			p.kicked = msg
		end,
		now = function()
			return now
		end,
		notify = function(p, kind, data)
			table.insert(notes, { to = p.UserId, kind = kind, data = data })
		end,
	})
	local players = {}
	local function join(id: number, stats: { [string]: any }?)
		local p = { UserId = id }
		players[id] = p
		local r = roles:onJoin(p)
		local m = roles:member(id)
		if m and stats then
			for k, v in stats do
				(m.stats :: any)[k] = v
			end
		end
		return p, r
	end
	return {
		roles = roles,
		possession = possession,
		notes = notes,
		players = players,
		join = join,
		setNow = function(t)
			now = t
		end,
	}
end

local RANKED = Ladder.params.rankGateDays

local function lastOffer(notes, id)
	for i = #notes, 1, -1 do
		if notes[i].to == id and notes[i].kind == "offer" then
			return notes[i].data
		end
	end
	return nil
end

return function(t)
	t.test(
		"join: 49 possessed as lowest-rank townspeople; the 50th kicked with no body; a leave frees a place",
		function()
			local w = world()
			for i = 1, 49 do
				local _, r = w.join(i)
				t.eq(r, "possessed")
				t.eq(w.roles:roleOf({ UserId = i }), "human")
			end
			local p50, r50 = w.join(50)
			t.eq(r50, "kicked")
			t.eq(p50.kicked, Ladder.FULL_MESSAGE)
			t.eq(w.roles:member(50), nil)
			t.eq(w.possession:actorOf(p50), nil)
			t.eq(w.roles:admittedCount(), 49)
			w.roles:onLeave({ UserId = 3 })
			t.eq(w.roles:admittedCount(), 48)
			local _, again = w.join(51)
			t.eq(again, "possessed")
		end
	)

	t.test("rodent slot: offer to the top squirrel, accept; its squirrel slot is offered on", function()
		local w = world()
		w.join(1, { activeGameDays = RANKED })
		w.join(2, { activeGameDays = RANKED })
		w.join(3, { activeGameDays = RANKED, activeMinutes = 100 })
		w.roles:forceRole(w.players[1], "squirrel")
		w.roles:forceRole(w.players[2], "squirrel")
		w.roles:member(1).stats.nuts = 10
		w.roles:member(2).stats.nuts = 30
		w.roles:report({ kind = "slot.open", rung = "rodent" })
		local o = lastOffer(w.notes, 2)
		t.truthy(o ~= nil)
		t.deepEq({ w.roles:reply(w.players[1], o.id, "accept") }, { false, "not your offer" })
		t.truthy(w.roles:reply(w.players[2], o.id, "accept"))
		t.eq(w.roles:roleOf(w.players[2]), "rodent")
		t.truthy(w.possession:actorOf(w.players[2]).rung == "rodent")
		-- the squirrel slot 2 left is offered to the best human
		local o2 = lastOffer(w.notes, 3)
		t.truthy(o2 ~= nil and o2.rung == "squirrel")
		t.truthy(w.roles:reply(w.players[3], o2.id, "accept"))
		t.eq(w.roles:roleOf(w.players[3]), "squirrel")
		t.truthy(w.roles:member(3).remembered ~= nil) -- human standing remembered
	end)

	t.test("offers time out down the cascade, then retry after offerRetry", function()
		local w = world()
		for i = 1, 4 do
			w.join(i, { activeGameDays = RANKED, activeMinutes = i * 10 })
		end
		w.roles:report({ kind = "slot.open", rung = "hospital" })
		t.truthy(lastOffer(w.notes, 4) ~= nil)
		w.setNow(15)
		w.roles:step(15)
		t.truthy(lastOffer(w.notes, 3) ~= nil)
		local o3 = lastOffer(w.notes, 3)
		t.truthy(w.roles:reply(w.players[3], o3.id, "stay"))
		t.truthy(lastOffer(w.notes, 2) ~= nil)
		w.setNow(31)
		w.roles:step(31) -- 2 times out: cascade of 3 exhausted
		t.truthy(w.roles:offers().hospital.retryAt ~= nil)
		local before = #w.notes
		w.roles:step(31 + Ladder.params.offerRetry)
		t.truthy(#w.notes > before) -- a fresh offer went out
		t.eq(w.notes[#w.notes].to, 4)
	end)

	t.test("side exit from an offer: deer instead, then back at the remembered rank", function()
		local w = world()
		w.join(1, { activeGameDays = RANKED, activeMinutes = 80, kicks = 2 })
		w.roles:report({ kind = "slot.open", rung = "hospital" })
		local o = lastOffer(w.notes, 1)
		t.truthy(w.roles:reply(w.players[1], o.id, "deer"))
		t.eq(w.roles:roleOf(w.players[1]), "deer")
		w.roles:report({ kind = "sideExit.leave", player = 1 })
		t.eq(w.roles:roleOf(w.players[1]), "human")
		t.eq(w.roles:stats(w.players[1]).activeMinutes, 80)
		t.eq(w.roles:member(1).remembered, nil)
	end)

	t.test(
		"rodent killed by a townsperson: killer becomes a squirrel, rodent lowest human, slot offered at once",
		function()
			Log.capture()
			local w = world()
			w.join(1, { activeGameDays = RANKED, activeMinutes = 500 }) -- rodent
			w.join(2, { activeGameDays = RANKED }) -- killer
			w.join(3, { activeGameDays = RANKED }) -- squirrel next in line
			w.roles:forceRole(w.players[1], "rodent")
			w.roles:forceRole(w.players[3], "squirrel")
			w.roles:member(3).stats.nuts = 5
			w.roles.squirrelBodiesFree = 3
			local ts = w.roles:report({ kind = "rodent.killed", by = "human", killer = 2 })
			t.eq(w.roles:roleOf(w.players[2]), "squirrel")
			t.eq(w.roles:roleOf(w.players[1]), "human")
			t.eq(w.roles:stats(w.players[1]).activeMinutes, 0)
			local offered = false
			for _, tr in ts do
				if tr.offer and tr.offer.rung == "rodent" then
					offered = true
					t.eq(tr.offer.candidates[1], 3)
				end
			end
			t.truthy(offered)
			Log.setSink()
		end
	)

	t.test("idle release (D34): warning at 750 s, input cancels, release at 780 s to the remembered rank", function()
		local w = world()
		w.join(1, { activeGameDays = RANKED, activeMinutes = 60 })
		w.roles:forceRole(w.players[1], "squirrel")
		w.roles:step(749)
		t.eq(#w.notes, 0)
		w.roles:step(750)
		t.eq(w.notes[1].kind, "idleWarning")
		w.roles:input(w.players[1], 760)
		t.eq(w.notes[2].kind, "idleCancel")
		w.roles:step(1539)
		t.eq(w.roles:roleOf(w.players[1]), "squirrel")
		w.roles:step(1540)
		t.eq(w.roles:roleOf(w.players[1]), "human")
		t.eq(w.roles:stats(w.players[1]).activeMinutes, 60)
		-- an idle townsperson is left alone
		w.join(2)
		w.roles:step(5000)
		t.eq(w.roles:roleOf(w.players[2]), "human")
	end)

	t.test("kicks, work and gigs land in stats and the purse", function()
		local w = world()
		w.join(1, { activeGameDays = RANKED })
		w.roles:report({ kind = "kick.landed", player = 1, target = "rodent" })
		local s = w.roles:stats(w.players[1]) :: any
		t.eq(s.kicks, 1)
		t.eq(s.questScore, 25)
		t.eq(s.reputation, 4)
		w.roles:report({ kind = "work.completed", player = 1, class = "standard", pay = 6 })
		w.roles:report({ kind = "gig.completed", player = 1, gig = "mow", quality = 1 })
		t.eq(w.roles:member(1).purse.cents, 6 + 3 + 2)
		t.eq(s.cents, 11)
	end)

	t.test("keys: the top two officers drive; jail revokes until served", function()
		local w = world()
		for i = 1, 3 do
			w.join(i, { activeGameDays = RANKED })
			w.roles:forceRole(w.players[i], "police")
			w.roles:member(i).stats.adminPerformance = i * 10
		end
		w.roles:refreshKeys()
		t.deepEq({ w.roles:roleOf(w.players[3]) }, { "police", "driver" })
		t.deepEq({ w.roles:roleOf(w.players[1]) }, { "police" })
		w.roles:report({ kind = "traffic.repeatOffence", player = 3 })
		t.deepEq({ w.roles:roleOf(w.players[3]) }, { "police" })
		w.roles:step(46)
		w.roles:refreshKeys()
		t.deepEq({ w.roles:roleOf(w.players[3]) }, { "police", "driver" })
	end)

	t.test("forceRole: any rung, over-cap logged; Role Lab gates on dev", function()
		local records = Log.capture()
		local w = world()
		w.join(1)
		w.join(2)
		local ok, over = w.roles:forceRole(w.players[1], "rodent")
		t.truthy(ok)
		t.falsy(over)
		ok, over = w.roles:forceRole(w.players[2], "rodent")
		t.truthy(ok and over)
		t.truthy(#records >= 1)
		t.deepEq({ w.roles:forceRole(w.players[2], "dragon") }, { false, false })
		local lab = RoleLab.new(w.roles, {
			isDev = function(p)
				return p.UserId == 1
			end,
		})
		t.deepEq({ lab:command(w.players[2], "become", { "fox" }) }, { false, "dev only" })
		t.truthy((lab:command(w.players[1], "become", { "fox" })))
		t.eq(w.roles:roleOf(w.players[1]), "fox")
		t.truthy((lab:command(w.players[1], "stat", { "cents", 500 })))
		t.eq(w.roles:member(1).purse.cents, 500)
		t.truthy((lab:command(w.players[1], "event", { "kick.landed", "target", "rodent" })))
		t.eq(w.roles:stats(w.players[1]).kicks, 1)
		local okPerf, ts = lab:command(w.players[1], "perf", { 300 })
		t.truthy(okPerf)
		t.eq(ts[1].value, 7)
		t.truthy((lab:command(w.players[1], "tune", { "squirrel.walk", 9 })))
		local _, diff = lab:command(w.players[1], "export", {})
		t.eq(diff[1].path, "squirrel.walk")
		t.truthy((lab:command(w.players[1], "tune", { "squirrel.walk", 8 })))
		t.falsy((lab:command(w.players[1], "become", { "dragon" })))
		t.falsy((lab:command(w.players[1], "fly", {})))
		local _, state = lab:command(w.players[1], "state", {})
		t.eq(state.rung, "fox")
		lab:command(w.players[1], "reset", {})
		t.eq(w.roles:roleOf(w.players[1]), "human")
		Log.setSink()
	end)

	t.test("client Role Lab model: a Become button per rung and side exit", function()
		local m = RoleLabClient.model()
		t.eq(#m, #RoleLab.RUNGS + 2)
		for i, rung in RoleLab.RUNGS do
			t.eq(m[i].cmd, "become")
			t.eq(m[i].args[1], rung)
		end
	end)

	t.test("churn: 200 scripted joins, promotions and leaves keep the cap and the slot counts", function()
		Log.capture()
		local w = world()
		local r = Rng.new(2026)
		local nextId = 1
		local live: { number } = {}
		local now = 0
		for step = 1, 200 do
			now += 3
			w.setNow(now)
			local roll = r.next()
			if roll < 0.45 or #live == 0 then
				local p, res = w.join(nextId, { activeGameDays = RANKED, activeMinutes = r.int(0, 300) })
				if res ~= "kicked" then
					table.insert(live, nextId)
				else
					t.eq(p.kicked, Ladder.FULL_MESSAGE)
				end
				nextId += 1
			elseif roll < 0.6 then
				local i = r.int(1, #live)
				w.roles:onLeave({ UserId = live[i] })
				table.remove(live, i)
			elseif roll < 0.75 then
				w.roles:report({ kind = "slot.open", rung = r.pick({ "rodent", "squirrel", "hospital", "police" }) })
			elseif roll < 0.9 then
				-- whoever holds an offer answers it
				for _, lo in w.roles:offers() do
					local who = lo.offer.candidates[lo.index]
					if who and not lo.retryAt and w.players[who] and w.roles:member(who) then
						w.roles:reply(w.players[who], lo.id, r.pick({ "accept", "stay", "deer" }))
					end
				end
			else
				w.roles:report({ kind = "rodent.died" })
			end
			w.roles:step(now)
			-- invariants
			t.truthy(w.roles:admittedCount() <= Ladder.server.maxPlayers, `step {step}`)
			t.eq(w.roles:admittedCount(), #live, `step {step} members`)
			local ctx = w.roles:ctx()
			for _, rung in { "rodent", "squirrel", "hospital", "deer", "fox" } do
				t.truthy(Ladder.held(ctx, rung) <= Ladder.slots(rung, ctx), `step {step} {rung}`)
			end
		end
		t.truthy(nextId > 60)
		Log.setSink()
	end)
end
