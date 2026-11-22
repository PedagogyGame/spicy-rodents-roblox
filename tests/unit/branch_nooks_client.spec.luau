--!strict
-- The D34 branch nooks in play: the knot-hole stash on the server (Server/Foraging/BranchStash: per player, from the
-- cup only, where the server holds the body), the held squirrel's keys and pose (Client/World/BranchNookClient: E at a
-- knot-hole, R to sit by the seat rules, getting up by SeatGetUp's hooks, the nodules' settle) and what is drawn
-- (Client/World/BranchNookArt: few parts, none solid, the feet on them), with the part counts for the report.
local roblox = require("@lune/roblox")
local Data = require("@shared/Data")
local BranchNookArt = require("@client/World/BranchNookArt")
local BranchNookClient = require("@client/World/BranchNookClient")
local BranchNooks = require("@shared/World/BranchNooks")
local BranchStash = require("@server/Foraging/BranchStash")
local SeatRules = require("@shared/World/SeatRules")
local Tunables = require("@shared/Config/Tunables")

return function(t)
	local d = Data.default()
	local reg = d:routes()
	local nooks = BranchNooks.new(d:module("BranchNooks") :: any)
	local firstNook, firstHangout = nil, nil
	for _, p in nooks.places do
		if p.kind == "nook" and firstNook == nil then
			firstNook = p
		elseif p.kind == "hangout" and firstHangout == nil then
			firstHangout = p
		end
	end
	local nook = firstNook :: BranchNooks.Place
	local hangout = firstHangout :: BranchNooks.Place

	-- the nut carrying, as Foraging/HollowService keeps it
	local function fakeHollows(): any
		local held: { [number]: number } = {}
		return {
			held = held,
			carried = function(_self: any, id: number): number
				return held[id] or 0
			end,
			carry = function(_self: any, id: number, n: number): number
				local cur = held[id] or 0
				local taken = math.max(0, math.min(n, Tunables.get("forage.carryMax") - cur))
				held[id] = cur + taken
				return taken
			end,
			drop = function(_self: any, id: number)
				held[id] = nil
			end,
		}
	end

	t.test("the stash: E in the cup stores what is carried and takes it back; per player; from the cup only", function()
		local hollows = fakeHollows()
		local places: { [number]: { number } } = {}
		local clock = 0
		local stash = BranchStash.new({
			nooks = nooks,
			hollows = hollows,
			placeOf = function(id: number): (number?, number?, number?)
				local p = places[id]
				if p == nil then
					return nil, nil, nil
				end
				return p[1], p[2], p[3]
			end,
			keyOf = function(id: number): string
				return if id == 1 or id == 3 then "player 7" else "player 9"
			end,
			now = function(): number
				return clock
			end,
		})
		local cup = nook.at
		places[1] = { cup[1], cup[2], cup[3] }
		hollows.held[1] = 5
		local r = stash:use(1, nook.route)
		t.truthy(r.ok and r.word == "stored" and r.moved == 5 and r.inside == 5, r.text)
		t.eq(hollows:carried(1), 0)
		t.eq(stash:list("player 7"), `{nook.route}=5`)
		-- too soon again: refused quietly
		local again = stash:use(1, nook.route)
		t.eq(again.word, "gap")
		clock += 1
		-- another player in the same cup has their own hole: empty
		places[2] = { cup[1], cup[2], cup[3] }
		t.eq(stash:use(2, nook.route).word, "empty")
		t.eq(stash:stored("player 9", nook.route), 0)
		-- empty paws: take them out (up to what a squirrel carries)
		clock += 1
		local took = stash:use(1, nook.route)
		t.truthy(took.ok and took.word == "took" and took.moved == 5 and took.inside == 0, took.text)
		t.eq(hollows:carried(1), 5)
		t.eq(stash:list("player 7"), "")
		-- full: the hole keeps C.capacity, the rest stays carried
		local cap = BranchStash.C.capacity
		local max = Tunables.get("forage.carryMax")
		local filled = 0
		for _ = 1, 10 do
			clock += 1
			hollows.held[1] = max
			local res = stash:use(1, nook.route)
			filled = res.inside
			if res.word == "full" then
				break
			end
		end
		t.eq(filled, cap)
		t.eq(stash:stored("player 7", nook.route), cap)
		-- the same player in another body (keyOf): the same holes
		clock += 1
		places[3] = { cup[1], cup[2], cup[3] }
		hollows.held[3] = 0
		local other = stash:use(3, nook.route)
		t.truthy(other.word == "took" and other.moved == math.min(cap, max), other.text)
		-- from the bough at the way in, a climber on the trunk, nowhere held, or a nook that is not: refused
		clock += 1
		local start = reg:pointAt(reg:get(nook.route) :: any, 0)
		places[1] = { start.x, start.y, start.z }
		t.eq(stash:use(1, nook.route).word, "far")
		clock += 1
		places[1] = nil :: any
		t.eq(stash:use(1, nook.route).word, "far")
		clock += 1
		places[1] = { cup[1], cup[2], cup[3] }
		t.eq(stash:use(1, hangout.route).word, "none")
		clock += 1
		t.eq(stash:use(1, "not a route" :: any).word, "none")
	end)

	-- a motor state on a route at t
	local function at(routeId: number, tt: number): any
		local r = reg:get(routeId) :: any
		local p = reg:pointAt(r, tt)
		return { routeId = routeId, railT = tt, x = p.x, y = p.y, z = p.z }
	end
	local function keys(fields: { [string]: any }?): any
		local f = { fw = 0, side = 0, leap = false, grab = false, drop = false, pounce = false, trick = false }
		for k, v in fields or {} do
			f[k] = v
		end
		return f
	end

	t.test("the held squirrel: E at the knot-hole is the stash's, never the motor's grab; the hints", function()
		local sent: { number } = {}
		BranchNookClient.reset()
		BranchNookClient.use(nooks, function(routeId: number)
			table.insert(sent, routeId)
		end)
		local f = keys({ grab = true })
		BranchNookClient.frame(at(nook.route, 1), f, reg, 10)
		t.eq(f.grab, false, "E went to the knot-hole")
		t.eq(sent[1], nook.route)
		t.truthy(BranchNookClient.hints().stash ~= nil, "E  stash shows")
		-- at the way in on the bough, E stays the motor's (it takes the nook), and the hint says so
		local g = keys({ grab = true })
		BranchNookClient.frame(at(nook.parent, nook.parentT), g, reg, 11)
		t.eq(g.grab, true)
		t.eq(#sent, 1)
		t.eq(BranchNookClient.hints().line, BranchNookClient.WORDS.nook)
		-- passing on at a run, the line stays a moment
		local tt = math.min(1, nook.parentT + 3 / (reg:get(nook.parent) :: any).length)
		BranchNookClient.frame(at(nook.parent, tt), keys({ fw = 1 }), reg, 11.5)
		t.eq(BranchNookClient.hints().line, BranchNookClient.WORDS.nook)
		BranchNookClient.frame(at(nook.parent, tt), keys({ fw = 1 }), reg, 13.5)
		t.eq(BranchNookClient.hints().line, nil)
		-- the counts the server sends show in the hint
		t.eq(BranchNookClient.parseCounts(`{nook.route}=4,20002=1`)[nook.route], 4)
		BranchNookClient.reset()
	end)

	t.test(
		"sitting by the seat rules: R sits a still squirrel in a cup or on a ledge; up by a key, a move or STAND",
		function()
			BranchNookClient.reset()
			BranchNookClient.use(nooks, function() end)
			local now = 100
			-- running, R does nothing
			t.truthy(BranchNookClient.press("R"))
			t.eq(BranchNookClient.frame(at(hangout.route, 0.9), keys({ fw = 1 }), reg, now), false)
			-- not on the ledge's seat stretch: nothing
			BranchNookClient.press("R")
			t.eq(BranchNookClient.frame(at(hangout.route, 0.1), keys(), reg, now), false)
			-- still on the ledge: seated, and the motor gets no keys
			t.truthy(BranchNookClient.frame(at(hangout.route, 0.9), keys(), reg, now) == false)
			BranchNookClient.press("R")
			t.eq(BranchNookClient.frame(at(hangout.route, 0.9), keys(), reg, now), true)
			t.eq(BranchNookClient.perch(), hangout)
			local f = keys({ leap = true, grab = true })
			t.eq(BranchNookClient.frame(at(hangout.route, 0.9), f, reg, now + 0.05), true)
			t.eq(f.leap, false)
			t.eq(f.grab, false)
			-- the drawn body settles onto its haunches, facing out of the crook
			local drop, pitch, turn = 0, 0, 0
			local yaw = math.atan2(hangout.out[1], hangout.out[2]) + 1.5
			for _ = 1, 60 do
				local _l, _r, dd, pp, tu = BranchNookClient.draw(at(hangout.route, 0.9), reg, 1 / 60, yaw)
				drop, pitch, turn = dd, pp, tu
			end
			t.near(drop, BranchNookClient.C.sitDrop, 1e-3)
			t.near(pitch, BranchNookClient.C.sitPitch, 1e-3)
			t.near(turn, -1.5, 1e-2)
			-- the press that sat it down reaches SeatGetUp too: it does not get it up again at once
			t.eq(BranchNookClient.perchUp(now + 0.1), false)
			-- SeatGetUp's get-up (a stand key, a move, STAND): up, and that press is not a leap
			t.eq(BranchNookClient.perchUp(now + 1), true)
			t.eq(BranchNookClient.perch(), nil)
			local g = keys({ leap = true })
			t.eq(BranchNookClient.frame(at(hangout.route, 0.9), g, reg, now + 1.05), false)
			t.eq(g.leap, false, "the get-up's Space is not a leap")
			local h = keys({ leap = true })
			BranchNookClient.frame(at(hangout.route, 0.9), h, reg, now + 1.5)
			t.eq(h.leap, true, "a leap after that is")
			-- R again within the grace: not seated again
			BranchNookClient.press("R")
			t.eq(BranchNookClient.frame(at(hangout.route, 0.9), keys(), reg, now + 1 + SeatRules.GRACE / 2), false)
			BranchNookClient.press("R")
			t.eq(BranchNookClient.frame(at(hangout.route, 0.9), keys(), reg, now + 1 + SeatRules.GRACE + 0.1), true)
			-- moved off the route (a correction): no longer seated
			t.eq(BranchNookClient.frame(at(hangout.parent, 0.5), keys(), reg, now + 3), false)
			-- a nook's cup is a seat too, and its stash works while seated
			local sent = 0
			BranchNookClient.use(nooks, function()
				sent += 1
			end)
			BranchNookClient.press("R")
			t.eq(BranchNookClient.frame(at(nook.route, 1), keys(), reg, now + 5), true)
			BranchNookClient.frame(at(nook.route, 1), keys({ grab = true }), reg, now + 5.1)
			t.eq(sent, 1)
			t.truthy(SeatRules.standKey("R") and SeatRules.standKey("Space"), "the seat rules' keys get it up")
			BranchNookClient.reset()
		end
	)

	t.test("what is drawn: few parts a tree, none solid or queried, the feet on the cup and the ledge", function()
		local totals = { parts = 0, nooks = 0, stashes = 0, hangouts = 0, spurs = 0 }
		local most, trees = 0, 0
		local seen: { [number]: boolean } = {}
		for _, p in nooks.places do
			if seen[p.trunk] then
				continue
			end
			seen[p.trunk] = true
			trees += 1
			local model, report = BranchNookArt.build(roblox :: any, nooks, reg, p.trunk)
			local n = 0
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					n += 1
					t.eq(part.Anchored, true)
					t.eq(part.CanCollide, false, part.Name)
					t.eq(part.CanQuery, false, part.Name)
					t.eq(part.CanTouch, false, part.Name)
					t.eq(part.CastShadow, false, part.Name)
				end
			end
			t.eq(n, report.parts)
			local P = BranchNookArt.PARTS
			t.eq(
				report.parts,
				report.nooks * P.nook + report.stashes * P.stash + report.hangouts * P.hangout + report.spurs * P.spur
			)
			most = math.max(most, report.parts)
			for k, v in report :: any do
				(totals :: any)[k] += v
			end
			-- the feet in the cup stand on its floor; on the ledge, on its moss
			for _, q in nooks.tree(p.trunk) do
				local feetY = q.at[2] + BranchNooks.C.lift
				if q.kind == "nook" then
					local floor = model:FindFirstChild(`Nook{q.route}_floor`) :: any
					t.near(floor.CFrame.Position.Y + floor.Size.X / 2, feetY, 1e-3)
				elseif q.kind == "hangout" then
					local moss = model:FindFirstChild(`Hangout{q.route}_moss3`) :: any
					local r = reg:get(q.route) :: any
					local e = reg:pointAt(r, BranchNookArt.C.hangoutAt[3])
					t.near(moss.CFrame.Position.Y + moss.Size.X / 2, e.y + BranchNooks.C.lift + 0.01, 1e-3)
				end
			end
		end
		t.truthy(most <= 70, `a tree's nooks draw in {most} parts at the most`)
		-- the nodules of one tree, capped; acorns for a full stash
		local folder = roblox.Instance.new("Folder")
		local boughs = {}
		for _, rec in d:forks() do
			if rec.trunk == nook.trunk then
				for _, f in rec.forks do
					table.insert(boughs, reg:get(f.branch))
				end
			end
		end
		local knots = BranchNookArt.nodules(roblox :: any, reg, boughs, nook.trunk, folder, 60)
		t.truthy(knots > 0 and knots <= 60, `{knots} knots`)
		t.eq(BranchNookArt.acorns(roblox :: any, nook, 12, folder), BranchNookArt.C.acorns)
		print(
			`      {trees} trees: {totals.parts} parts in all if every tree were drawn ({totals.nooks} nooks, {totals.stashes} stashes, {totals.hangouts} hangouts, {totals.spurs} spurs); at most {most} a tree; drawn only near the camera, never baked`
		)
	end)
end
