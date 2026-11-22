--!strict
-- Owner D30: the bank errands as Server/Work/ErrandService runs them (no engine: stub bodies, the real wallet and
-- the real penalty). offer at a board (named, with the time and the pay), carried visibly in the hand of the body
-- held now (off while not a person, back on after), one at a time, "you're close" once, delivered and paid at the
-- spot, a minute's reminder, hand back with two presses (nothing either way), and the three ways to keep it (late,
-- at home, leaving the server) each costing the S$100 penalty through the wallet with a reputation report.
local Credits = require("@server/Economy/Credits")
local Penalties = require("@server/Work/Penalties")
local ErrandService = require("@server/Work/ErrandService")
local Errands = require("@shared/Work/Errands")
local PenaltyRules = require("@shared/Work/PenaltyRules")

type Body = { pos: { number }, held: { any } }

local function rig(rand: { number }?)
	local clock = 0
	local wallet = Credits.new({ log = function() end, warn = function() end })
	local reports: { string } = {}
	local pen = Penalties.new({
		wallet = wallet,
		report = function(_p: any, kind: string)
			table.insert(reports, kind)
		end,
		warn = function() end,
	})
	local bodies: { [any]: Body? } = {}
	local person: { [any]: boolean } = {}
	local told: { [any]: { string } } = {}
	local homes: { [any]: string } = {}
	local i = 0
	local svc = ErrandService.new({
		wallet = wallet,
		penalties = pen,
		bodyOf = function(p: any): any?
			return bodies[p]
		end,
		isPerson = function(p: any): boolean
			return person[p] == true
		end,
		notify = function(p: any, text: string)
			told[p] = told[p] or {}
			table.insert(told[p], text)
		end,
		now = function(): number
			return clock
		end,
		rand = function(): number
			i += 1
			local r = rand or { 0.1 }
			return r[(i - 1) % #r + 1]
		end,
		posOf = function(body: any): { number }?
			return body.pos
		end,
		homeOf = function(p: any): string?
			return homes[p]
		end,
		inside = function(lotId: string, x: number, z: number): boolean
			return lotId == "home" and math.abs(x - 5000) < 20 and math.abs(z - 5000) < 20
		end,
		attach = function(body: any, item: any): any
			local prop = { item = item.id, on = body }
			table.insert(body.held, prop)
			return prop
		end,
		detach = function(prop: any)
			local list = prop.on.held
			local k = table.find(list, prop)
			if k then
				table.remove(list, k)
			end
		end,
	})
	local function join(id: number, cents: number): any
		local p = { UserId = id, Name = `P{id}`, events = {} }
		wallet.join(p)
		wallet.add(p, cents, "wages")
		bodies[p] = { pos = { 0, 0 }, held = {} }
		person[p] = true
		return p
	end
	local function advance(secs: number)
		local n = math.ceil(secs / 0.25)
		for _ = 1, n do
			clock += 0.25
			svc:step(0.25)
		end
	end
	local function last(p: any): string
		local list = told[p] or {}
		return list[#list] or ""
	end
	return {
		svc = svc,
		wallet = wallet,
		reports = reports,
		bodies = bodies,
		person = person,
		homes = homes,
		join = join,
		advance = advance,
		last = last,
		clock = function(): number
			return clock
		end,
	}
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

return function(t)
	t.test("offer: a person at a board is given one, named with its time and pay; the thing in their hand", function()
		local r = rig()
		local p = r.join(1, 0)
		local ok, text = r.svc:press(p, "south_quay")
		t.truthy(ok)
		local run = r.svc:runOf(p)
		t.truthy(run ~= nil)
		local e = run.errand
		t.truthy(has(text :: string, e.words), text)
		t.truthy(has(text :: string, Errands.duration(e.secs)), "the time")
		t.truthy(has(text :: string, "pays"), "the pay")
		t.eq(#r.bodies[p].held, 1, "carried in the hand")
		t.eq(r.bodies[p].held[1].item, e.item.id)
		-- one at a time: pressing again says what is carried, and takes nothing new
		r.advance(1)
		local ok2, text2 = r.svc:press(p, "market")
		t.falsy(ok2)
		t.truthy(has(text2 :: string, e.to), text2)
		t.eq(r.svc:runOf(p), run)
		-- a squirrel is not given one
		local q = r.join(2, 0)
		r.person[q] = false
		local ok3, text3 = r.svc:press(q, "market")
		t.falsy(ok3)
		t.eq(text3, ErrandService.WORDS.notPerson)
		t.eq(r.svc:runOf(q), nil)
	end)

	t.test("deliver: you're close once, handed over at the spot, paid through the wallet", function()
		local r = rig()
		local p = r.join(1, 0)
		r.svc:press(p, "north_quay")
		local e = r.svc:runOf(p).errand
		local before = r.wallet.balance(p)
		r.bodies[p].pos = { e.dest.x + 30, e.dest.z }
		r.advance(0.5)
		t.truthy(has(r.last(p), "You're close"), r.last(p))
		r.bodies[p].pos = { e.dest.x + 3, e.dest.z }
		r.advance(0.5)
		t.eq(r.svc:runOf(p), nil, "over")
		t.eq(r.wallet.balance(p), before + e.cents)
		t.truthy(has(r.last(p), "Delivered"), r.last(p))
		t.eq(#r.bodies[p].held, 0, "out of their hand")
		local h = r.wallet.purse(p).history
		t.eq(h[#h].why, ErrandService.PAY_WHY)
	end)

	t.test("carry: off the hand while not a person, back on the body held after; the clock runs on", function()
		local r = rig()
		local p = r.join(1, 0)
		r.svc:press(p, "market")
		local first = r.bodies[p]
		r.person[p] = false
		r.advance(1)
		t.eq(#first.held, 0, "a squirrel holds no parcel")
		r.person[p] = true
		r.bodies[p] = { pos = { 0, 0 }, held = {} }
		r.advance(1)
		t.eq(#r.bodies[p].held, 1, "back in the hand of the new body")
		t.eq(#first.held, 0)
	end)

	t.test("hand back: two presses at a board, no pay and no penalty", function()
		local r = rig()
		local p = r.join(1, 20000)
		r.svc:press(p, "market")
		r.advance(2)
		local ok1 = r.svc:press(p, "south_quay")
		t.falsy(ok1, "the first press only says")
		r.advance(1)
		local ok2, text = r.svc:press(p, "south_quay")
		t.truthy(ok2)
		t.truthy(has(text :: string, "No pay, no penalty"), text)
		t.eq(r.svc:runOf(p), nil)
		t.eq(r.wallet.balance(p), 20300, "nothing taken, nothing paid")
		t.eq(#r.reports, 0)
		-- a held key does nothing
		t.eq(select(2, r.svc:press(p, "market")), nil, "too soon after the hand back")
		r.advance(1)
		t.eq(select(2, r.svc:press(p, "market")) ~= nil, true, "a new errand")
		t.eq(select(2, r.svc:press(p, "market")), nil, "too soon after")
	end)

	t.test("kept: late, at home too long, or out of the server: S$100 through the wallet and a report", function()
		-- late (a reminder a minute before)
		local r = rig()
		local p = r.join(1, 25000)
		r.svc:press(p, "market")
		local e = r.svc:runOf(p).errand
		r.bodies[p].pos = { e.dest.x + 900, e.dest.z }
		r.advance(e.secs - 30)
		t.truthy(has(r.last(p), "One minute left"), r.last(p))
		r.advance(40)
		t.eq(r.svc:runOf(p), nil)
		t.eq(r.wallet.balance(p), 25300 - PenaltyRules.penalty())
		t.eq(r.reports[1], "errand_stolen")
		t.eq(#r.bodies[p].held, 0)
		-- at home: a short pass through is not kept; staying is
		local r2 = rig()
		local q = r2.join(2, 25000)
		r2.homes[q] = "home"
		r2.svc:press(q, "market")
		r2.bodies[q].pos = { 5000, 5000 }
		r2.advance(10)
		r2.bodies[q].pos = { 4000, 4000 }
		r2.advance(30)
		t.truthy(r2.svc:runOf(q) ~= nil, "ten seconds at home is not keeping it")
		r2.bodies[q].pos = { 5000, 5000 }
		r2.advance(11)
		t.eq(r2.svc:runOf(q), nil, "kept at home")
		t.eq(r2.wallet.balance(q), 25300 - PenaltyRules.penalty())
		-- out of the server with it
		local r3 = rig()
		local s = r3.join(3, 4000)
		r3.svc:press(s, "north_quay")
		r3.svc:leave(s)
		t.eq(r3.svc:runOf(s), nil)
		t.eq(r3.wallet.balance(s), 0, "all of it, never below nothing")
		t.eq(r3.reports[1], "errand_stolen")
		-- a player who leaves with nothing in hand loses nothing
		local u = r3.join(4, 4000)
		r3.svc:leave(u)
		t.eq(r3.wallet.balance(u), 4300)
	end)
end
