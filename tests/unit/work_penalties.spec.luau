--!strict
-- Owner D30 (2026-11-22): "if an ambulence driver ignores bite victim that needs to be picked up, or if the errand
-- delivery person steals the item, or places it in their home and does not bring it back ... they should get penalized
-- by losing 100 spicy bucks, and the doctor, gets demoted to lowest townsperson station's money level".
--   rules      Shared/Work/PenaltyRules: the fine is S$100, never more than there is (no debt anywhere); the lowest
--              townsperson's money is the least any townsperson holds (the pocket money with none); a doctor's
--              money comes down to it after the fine, and a penalty never gives money
--   wallet     Server/Work/Penalties through the town's wallet (Economy/Credits): logged with its reason, shown, a
--              reputation report (pcall'd: a failing one leaves the money penalty standing)
--   homes      Shared/World/PlayerHomes: every player has a house, the same one every time; inside its footprint
local Credits = require("@server/Economy/Credits")
local Penalties = require("@server/Work/Penalties")
local PenaltyRules = require("@shared/Work/PenaltyRules")
local PlayerHomes = require("@shared/World/PlayerHomes")
local Data = require("@shared/Data")

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
		t.eq(reports[1][2], "errand_stolen")
		t.truthy(reports[1][3] > 0 and reports[1][3] <= 1)
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
		t.eq(reports[1][2], "ambulance_ignored")
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

	t.test("homes: a house each, the same every time; inside its footprint; a claim system decides first", function()
		local data = Data.default()
		local homes = PlayerHomes.homes()
		t.truthy(#homes >= 20, `{#homes} houses`)
		for _, id in homes do
			t.eq(data:lot(id).type, "house")
		end
		local a = PlayerHomes.homeOf(player(123456))
		t.eq(PlayerHomes.homeOf(player(123456)), a, "the same house every time")
		t.eq(PlayerHomes.homeOf(123456), a, "by UserId")
		local lot = PlayerHomes.lotOf(a :: string) :: PlayerHomes.Lot
		t.truthy(PlayerHomes.inside(a :: string, lot.x, lot.z))
		t.truthy(PlayerHomes.inside(a :: string, lot.x + lot.hw - 0.1, lot.z))
		t.falsy(PlayerHomes.inside(a :: string, lot.x + lot.hw + 3, lot.z))
		t.truthy(PlayerHomes.inside(a :: string, lot.x + lot.hw + 3, lot.z, 4), "grown")
		local seen: { [string]: boolean } = {}
		for id = 1, 200 do
			seen[PlayerHomes.homeOf(id) :: string] = true
		end
		local n = 0
		for _ in seen do
			n += 1
		end
		t.eq(n, #homes, "every house is somebody's")
		PlayerHomes.setResolver(function(p: any): string?
			return if p.UserId == 7 then "core_house_0_victorian" else nil
		end)
		t.eq(PlayerHomes.homeOf(player(7)), "core_house_0_victorian")
		t.eq(PlayerHomes.homeOf(player(123456)), a, "the resolver's nil falls back")
		PlayerHomes.setResolver(nil)
		t.eq(PlayerHomes.homeOf(nil), nil)
	end)
end
