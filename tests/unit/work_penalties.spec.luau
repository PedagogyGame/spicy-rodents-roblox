--!strict
-- Owner D30 (2026-11-22): "if an ambulence driver ignores bite victim that needs to be picked up, or if the errand
-- delivery person steals the item, or places it in their home and does not bring it back ... they should get penalized
-- by losing 100 spicy bucks, and the doctor, gets demoted to lowest townsperson station's money level".
--   rules      Shared/Work/PenaltyRules: the fine is S$100, never more than there is (no debt anywhere); the lowest
--              townsperson's money is the least any townsperson holds (the pocket money with none); a doctor's
--              money comes down to it after the fine, and a penalty never gives money
--   wallet     Server/Work/Penalties through the town's wallet (Economy/Credits): logged with its reason, shown, a
--              reputation report (pcall'd: a failing one leaves the money penalty standing)
--   homes      the errands' doors are outside every player's home (Shared/World/PlayerHomes)
local Credits = require("@server/Economy/Credits")
local Penalties = require("@server/Work/Penalties")
local PenaltyRules = require("@shared/Work/PenaltyRules")
local PlayerHomes = require("@shared/World/PlayerHomes")
local Errands = require("@shared/Work/Errands")

local function player(id: number): any
	return { UserId = id, Name = `P{id}`, events = {} }
end

local function lastNotice(p: any): string?
	for i = #p.events, 1, -1 do
		if p.events[i].kind == "notice" then
			return p.events[i].text
		end
	end
	return nil
end

-- a town wallet, players joined with pocket money and topped up to `cents`, and roles that hold their rungs
local function town(rows: { { id: number, cents: number, rung: string } })
	local wallet = Credits.new({ log = function() end, warn = function() end })
	local members: { [number]: any } = {}
	local players: { [number]: any } = {}
	for _, r in rows do
		local p = player(r.id)
		wallet.join(p)
		local have = wallet.balance(p)
		if r.cents > have then
			wallet.add(p, r.cents - have, "wages")
		elseif r.cents < have then
			wallet.purse(p):debit(have - r.cents, "spent")
		end
		members[r.id] = { rung = r.rung, purse = wallet.purse(p) }
		players[r.id] = p
	end
	local reports: { { any } } = {}
	local pen = Penalties.new({
		wallet = wallet,
		roles = { members = members },
		report = function(p: any, kind: string, severity: number)
			table.insert(reports, { p, kind, severity })
		end,
		warn = function() end,
	})
	return wallet, players, pen, reports
end

return function(t)
	t.test("rules: S$100, never more than there is; the lowest townsperson's money; never gives money", function()
		t.eq(PenaltyRules.penalty(), 10000, "S$100.00")
		t.eq(PenaltyRules.fine(25000), 10000)
		t.eq(PenaltyRules.fine(3000), 3000, "no debt: what there is")
		t.eq(PenaltyRules.fine(0), 0)
		t.eq(PenaltyRules.townLevel({ 2000, 700, 9000 }, 300), 700)
		t.eq(PenaltyRules.townLevel({}, 300), 300, "no townsperson: a newcomer's pocket money")
		local fine, down, after = PenaltyRules.ambulance(50000, 700)
		t.eq(fine, 10000)
		t.eq(down, 39300)
		t.eq(after, 700)
		fine, down, after = PenaltyRules.ambulance(10500, 700)
		t.eq(fine, 10000)
		t.eq(down, 0, "already under the level after the fine")
		t.eq(after, 500)
		fine, down, after = PenaltyRules.ambulance(200, 700)
		t.eq(fine, 200)
		t.eq(down, 0)
		t.eq(after, 0, "never raised to the level")
	end)

	t.test("wallet: an errand's parcel kept costs S$100 through the wallet, said and reported", function()
		local wallet, players, pen, reports = town({
			{ id = 1, cents = 25000, rung = "human" },
			{ id = 2, cents = 4200, rung = "human" },
		})
		t.eq(pen.errandStolen(players[1], "the parcel for Pepper's Corner Store"), 10000)
		t.eq(wallet.balance(players[1]), 15000)
		local h = wallet.purse(players[1]).history
		t.eq(h[#h].why, PenaltyRules.WHY.errand)
		t.eq(h[#h].delta, -10000)
		t.truthy(string.find(lastNotice(players[1]) or "", "S$100.00 taken", 1, true) ~= nil, lastNotice(players[1]))
		t.eq(reports[1][2], "errand_theft")
		t.eq(reports[1][3], 2, "severity 2 of 3")
		-- less than the fine: all of it, never below nothing
		t.eq(pen.errandStolen(players[2]), 4200)
		t.eq(wallet.balance(players[2]), 0)
		t.eq(pen.errandStolen(players[2]), 0, "nothing left to take")
		t.eq(wallet.balance(players[2]), 0)
	end)

	t.test("wallet: a doctor who ignored a bite victim: the fine, then down to the poorest townsperson", function()
		local wallet, players, pen, reports = town({
			{ id = 10, cents = 50000, rung = "hospital" },
			{ id = 11, cents = 2000, rung = "human" },
			{ id = 12, cents = 700, rung = "human" },
			{ id = 13, cents = 0, rung = "squirrel" }, -- not a townsperson: not the level
			{ id = 14, cents = 9000, rung = "police" },
		})
		local fine, down = pen.ambulanceIgnored(players[10])
		t.eq(fine, 10000)
		t.eq(down, 39300)
		t.eq(wallet.balance(players[10]), 700)
		local h = wallet.purse(players[10]).history
		t.eq(h[#h - 1].why, PenaltyRules.WHY.ambulance)
		t.eq(h[#h].why, PenaltyRules.WHY.level)
		t.truthy(string.find(lastNotice(players[10]) or "", "lowest townsperson", 1, true) ~= nil)
		t.eq(#reports, 0, "the doctors' work reports the reputation, not this")
		t.eq(wallet.balance(players[11]), 2000, "nobody else's money moves")
		-- alone in town: down to a newcomer's pocket money
		local w2, p2, pen2 = town({ { id = 20, cents = 40000, rung = "hospital" } })
		pen2.ambulanceIgnored(p2[20])
		t.eq(w2.balance(p2[20]), 300)
	end)

	t.test("wallet: a reputation report that fails leaves the penalty standing; before install nothing", function()
		local wallet = Credits.new({ log = function() end, warn = function() end })
		local p = player(5)
		wallet.join(p)
		wallet.add(p, 20000, "wages")
		local pen = Penalties.new({
			wallet = wallet,
			report = function()
				error("no reputation yet")
			end,
			warn = function() end,
		})
		t.eq(pen.errandStolen(p), 10000)
		t.eq(wallet.balance(p), 10300)
		-- with no reputation module and no deps.report: the default looks and finds none, quietly
		local plain = Penalties.new({ wallet = wallet, warn = function() end })
		t.eq(plain.errandStolen(p), 10000)
		t.eq(wallet.balance(p), 300)
		t.eq(Penalties.ambulanceIgnored(player(99)), 0, "nothing installed: nothing taken")
		Penalties.install({ wallet = wallet, warn = function() end })
		t.eq(Penalties.errandStolen(p), 300, "the installed instance")
	end)

	t.test("hook: a doctor demoted for an ignored bite victim pays; other demotions and rules do not", function()
		local wallet = Credits.new({ log = function() end, warn = function() end })
		local doc, cop = player(30), player(31)
		for _, p in { doc, cop } do
			wallet.join(p)
			wallet.add(p, 30000, "wages")
		end
		local seen = 0
		local roles = {
			deps = {
				onTransition = function()
					seen += 1
				end,
			},
			members = {
				[30] = { player = doc, rung = "human", purse = wallet.purse(doc) },
				[31] = { player = cop, rung = "human", purse = wallet.purse(cop) },
			},
		}
		Penalties.install({ wallet = wallet, roles = roles, warn = function() end })
		Penalties.hook(roles)
		roles.deps.onTransition({ rule = "role.demote", player = 31, why = "kept missing the station" })
		roles.deps.onTransition({ rule = "work.completed", player = 30, pay = 3 })
		t.eq(wallet.balance(doc), 30300, "not an ambulance demotion")
		t.eq(wallet.balance(cop), 30300)
		roles.deps.onTransition({ rule = "role.demote", player = 30, why = "ignored a bite victim" })
		t.eq(wallet.balance(doc), 20300, "fined; already at the other townsperson's level or under")
		t.eq(seen, 3, "the hook already there still runs")
		roles.deps.onTransition({ rule = "role.demote", player = 31, why = "abandoned a patient" })
		t.eq(wallet.balance(cop), 20300, "fined, then down to the doctor's 20300")
	end)

	t.test("homes: a door an errand is handed over at is outside every home (delivering is never keeping)", function()
		-- (Shared/World/PlayerHomes is the stock-options work's: four furnished houses, one per player by where they
		-- first appear; the errands ask homeOf and inside)
		for _, d in Errands.DESTINATIONS do
			for _, h in PlayerHomes.HOMES do
				t.falsy(PlayerHomes.inside(h.lot, d.x, d.z), `{d.id} is inside {h.lot}`)
			end
		end
		local p = { UserId = 7, attrs = {} :: { [string]: any } }
		function p.GetAttribute(self: any, k: string): any
			return self.attrs[k]
		end
		p.attrs[PlayerHomes.ATTRIBUTE] = "core_house_0_victorian"
		t.eq(PlayerHomes.homeOf(p), "core_house_0_victorian")
		t.truthy(PlayerHomes.inside("core_house_0_victorian", -140, -132.5))
	end)
end
