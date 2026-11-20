--!strict
-- Clothing saving's guards (owner D16 #25), from the review of feat/save-clothing (review/save-clothing cacfaf0:
-- the first five cases failed there) and its fixes: the DataStore budget (a desk press only marks the profile; one
-- write per player per WRITE_GAP; a server-wide bucket), the session id kept across a player's retries (a lost load
-- reply never locks them out), only an absent key is a new player (anything else unreadable is never written
-- over), a body handed between two wearers inside one sweep, the shutdown inside BindToClose's window, "off" at
-- once, a purchase made while unsaved saved on the way out, a same-server rejoin taking the saved worn choice, and
-- that only the clothing in a record is ever changed.
local roblox = require("@lune/roblox")
local ProfileSchema = require("@server/Persistence/ProfileSchema")
local MockDataStore = require("@server/Persistence/MockDataStore")
local PlayerSaves = require("@server/Persistence/PlayerSaves")
local Wardrobe = require("@server/Cosmetics/Wardrobe")
local GiftShop = require("@server/Cosmetics/GiftShop")
local Clothing = require("@shared/Items/Clothing")

local SHIRT = "alley_shirt"

local function clock()
	local c = { t = 1_700_000_000 }
	return c, function(): number
		return c.t
	end, function(s: number)
		c.t += s
	end
end

-- one simulated server, as in clothing_save.spec (synchronous spawn: each DataStore call completes in turn)
local function server(store: any, jobId: string, now: () -> number, sleep: (number) -> ()): any
	local sv: any = { told = {} }
	sv.saves = PlayerSaves.new({
		store = store,
		jobId = jobId,
		now = now,
		sleep = sleep,
		spawn = function(fn: () -> ())
			fn()
		end,
		tell = function(player: any, words: string)
			sv.told[player.UserId] = sv.told[player.UserId] or {}
			table.insert(sv.told[player.UserId], words)
		end,
		loaded = function(player: any, data: any): boolean
			return sv.wardrobe:loaded(player, data)
		end,
		pending = function(player: any): boolean
			return sv.wardrobe:pending(player)
		end,
		log = function(_line: string) end,
		warn = function(_line: string) end,
		lockWaits = 1,
		lockWaitSeconds = 5,
		retries = 2,
		backoffSeconds = 1,
	})
	sv.wardrobe = Wardrobe.new({
		saves = sv.saves,
		bodyOf = function(_player: any): (any?, string?)
			return nil, "human"
		end,
		players = function(): { any }
			return {}
		end,
	})
	return sv
end

-- A tiny discrete-event scheduler for the shutdown case: spawn makes a coroutine, sleep yields it (a fake clock
-- moves to the next wake), so a load's lock wait, a slow DataStore call and closeAll's polling run side by side as
-- they do in the engine.
local function sim(): any
	local S: any = { t = 1_700_000_000, threads = {}, current = nil }
	function S.now(): number
		return S.t
	end
	function S.spawn(fn: () -> ())
		table.insert(S.threads, { co = coroutine.create(fn), wake = S.t })
	end
	function S.sleep(seconds: number)
		if S.current ~= nil and coroutine.running() == S.current then
			coroutine.yield(seconds)
		else
			S.t += seconds
		end
	end
	function S.run(untilT: number)
		while #S.threads > 0 do
			table.sort(S.threads, function(a: any, b: any): boolean
				return a.wake < b.wake
			end)
			local th = S.threads[1]
			if th.wake > untilT then
				break
			end
			S.t = math.max(S.t, th.wake)
			S.current = th.co
			local ok, seconds = coroutine.resume(th.co)
			S.current = nil
			assert(ok, seconds)
			if coroutine.status(th.co) == "dead" then
				table.remove(S.threads, 1)
			else
				th.wake = S.t + (seconds or 0)
			end
		end
	end
	return S
end

return function(t)
	-- Every E press at the gift shop desk (owned shirt: on, off, on ...) was an immediate UpdateAsync: a held E /
	-- autoclicker / fireproximityprompt loop at 4 presses a second was 240 UpdateAsync a minute from ONE player,
	-- against the whole server's allowance of 60 + 10 x players a minute. Now a change only marks the profile and
	-- the 1 Hz step writes it once its last write is WRITE_GAP (6 s) old: a burst costs a couple of writes. (No
	-- press cooldown here: deps.now is absent, so this is the save rule alone.)
	t.test("a client cannot flood the DataStore budget by toggling the shirt at the desk", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local sv = server(store, "A", now, sleep)
		local p = { UserId = 41 }
		sv.saves:join(p)
		sv.wardrobe:give(p, SHIRT)
		local deps: GiftShop.Deps = {
			wallet = {
				buy = function(_p: any, _id: string, _deliver: any): (boolean, string)
					return false, "not used: the shirt is owned"
				end,
			},
			wardrobe = sv.wardrobe,
			speciesOf = function(_p: any): string?
				return "human"
			end,
			present = function(_p: any): boolean
				return true
			end,
			tell = function(_p: any, _w: string) end,
		}
		local before = store.calls.updates
		for _ = 1, 40 do -- ten seconds of presses, four a second
			GiftShop.press(deps, p)
			c.t += 0.25
			sv.saves:step(now())
		end
		local used = store.calls.updates - before
		t.truthy(used <= 3, `40 presses in 10 s cost {used} UpdateAsync calls (expected at most ~1 per 6 s per key)`)
	end)

	-- An ambiguous load failure (UpdateAsync committed the lock, then the reply was lost: the case
	-- MockDataStore calls commitThenError, specced for saves but not for loads) leaves this server's OWN lock in the
	-- record for the whole lease (180 s). Each retry makes a new session id, finds that live lock and waits, so the
	-- player was "unsaved" here for three minutes on a transient error. Now one session id per player per
	-- server ("<jobId>:<userId>") is kept across the retries, so the next try takes its own lock back at once.
	t.test("a load whose reply was lost does not lock the player out of their own server", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local sv = server(store, "A", now, sleep)
		local p = { UserId = 42 }
		store:fail("commitThenError", 3) -- 1 try + 2 retries: each committed, each reply lost
		sv.saves:join(p)
		t.eq(sv.saves:status(p), "unsaved")
		t.truthy(store:peek("p_42").meta.lock ~= nil, "(the lost replies left this server's lock in the record)")
		c.t += PlayerSaves.RETRY_FIRST
		sv.saves:step(now())
		t.eq(sv.saves:status(p), "saved", "the first retry should take back this server's own lock")
	end)

	-- (Same cause.) The player gives up and hops: the leave of an unsaved session released nothing, so the orphan
	-- lock (whose jobId is A, still alive) held the next server off for the rest of the lease. Now the leave clears
	-- a lock bearing this player's session on this server (and nothing else).
	t.test("after a lost load reply, leaving does not leave the next server waiting out the lease", function()
		local store = MockDataStore.new()
		local _c, now, sleep = clock()
		local a = server(store, "A", now, sleep)
		local p = { UserId = 43 }
		store:fail("commitThenError", 3)
		a.saves:join(p)
		a.saves:leave(p)
		local b = server(store, "B", now, sleep)
		b.saves:join(p)
		t.eq(b.saves:status(p), "saved", "A left no live session behind its lock")
	end)

	-- "Never written over: a broken record" held for a newer schema, but not for a record whose `data` is missing
	-- or has no `schema`: those were read as a new player or as a v0 { cents } shape and replaced by a template, the
	-- owned clothing dropped. (Nothing wrote the live "Profiles" store before v1, so there is no v0 and the v0 path
	-- is gone.) Only an absent key is a new player; anything else unreadable is "corrupt": play goes on unsaved, the
	-- player told once, the record never written.
	t.test("a record that is not a profile is left as it is, never replaced by a template", function()
		local store = MockDataStore.new()
		local _c, now, sleep = clock()
		store.data.p_44 = { data = { wardrobe = { [SHIRT] = true }, worn = { shirt = SHIRT } }, meta = { writes = 3 } }
		store.data.p_45 = "a string, not a profile"
		store.data.p_46 = { cents = 7 } -- a top-level record of no shape this game ever wrote
		local a = server(store, "A", now, sleep)
		local broken, junk, v0 = { UserId = 44 }, { UserId = 45 }, { UserId = 46 }
		a.saves:join(broken)
		a.saves:join(junk)
		a.saves:join(v0)
		t.eq(a.saves:status(broken), "corrupt", "a data table without schema")
		t.deepEq(store:peek("p_44").data.wardrobe, { [SHIRT] = true }, "its clothing is not wiped")
		t.eq(a.saves:status(junk), "corrupt", "a non-table record")
		t.eq(store:peek("p_45"), "a string, not a profile")
		t.eq(a.saves:status(v0), "corrupt", "a record without data")
		t.deepEq(store:peek("p_46"), { cents = 7 })
		-- told once; buying goes on, unsaved; nothing is written on step, autosave or leave
		t.eq(#a.told[44], 1)
		t.eq(a.told[44][1], PlayerSaves.WORDS.corrupt)
		local ok, note = a.wardrobe:give(broken, SHIRT)
		t.truthy(ok)
		t.eq(note, Wardrobe.WORDS.corrupt)
		local writes = store.calls.writes
		a.saves:step(now() + 1000)
		for _, p in { broken, junk, v0 } do
			a.wardrobe:leave(p)
			a.saves:leave(p)
		end
		t.eq(store.calls.writes, writes, "never written over")
		t.eq(store:peek("p_44").meta.writes, 3)
	end)

	-- Two players who both wear the shirt hand one body over inside one sweep (A releases townsperson P, B picks P
	-- from the menu before the next 1 Hz sweep). If B was swept first, B's dress recorded A's navy as P's "own"
	-- colour, and when B let go P stayed navy for good. Now the sweep undresses every entry whose body or look
	-- changed before it dresses any. Both orders are held.
	t.test("a body handed between two shirt wearers inside one sweep gets its own colour back", function()
		local Instance, Color3 = roblox.Instance, roblox.Color3
		local body = Instance.new("Model")
		local torso = Instance.new("Part")
		torso.Name = "UpperTorso"
		torso.Color = Color3.fromRGB(200, 10, 10)
		torso.Parent = body
		local store = MockDataStore.new()
		local _c, now, sleep = clock()
		local sv = server(store, "A", now, sleep)
		local ann, bob = { UserId = 47 }, { UserId = 48 }
		local holds: { [any]: any } = { [ann] = body }
		sv.wardrobe.deps.bodyOf = function(p: any): (any?, string?)
			local b = holds[p]
			return b, if b then "human" else nil
		end
		sv.wardrobe.deps.rgb = Color3.fromRGB
		local order: { any } = { ann }
		sv.wardrobe.deps.players = function(): { any }
			return order
		end
		for _, p in { ann, bob } do
			sv.saves:join(p)
			sv.wardrobe:give(p, SHIRT)
		end
		sv.wardrobe:sweep() -- Ann's shirt on P
		t.eq(math.floor(torso.Color.R * 255 + 0.5), 40)
		-- Ann lets go of P and Bob takes it before the next sweep; the server lists Bob first
		holds[ann], holds[bob] = nil, body
		order = { bob, ann }
		sv.wardrobe:sweep()
		t.eq(math.floor(torso.Color.R * 255 + 0.5), 40, "Bob holds P and wears the shirt: it shows")
		holds[bob] = nil
		sv.wardrobe:sweep()
		t.eq(math.floor(torso.Color.R * 255 + 0.5), 200, "nobody holds P: its own shirt colour is back")
	end)

	-- PASSES (a guard: clothing_save's "threads" case leaves before the load job starts, so a leave while the load's
	-- UpdateAsync is in flight was never exercised; dropping PlayerSaves' `p:release()` after such a load passed every
	-- spec and would leave a 180 s lock behind a quick leave).
	t.test("holds: a leave while the load is in flight hands the lock straight back", function()
		local store = MockDataStore.new()
		local _c, now, sleep = clock()
		local p = { UserId = 50 }
		local sv: any = nil
		local left = false
		local real = store.UpdateAsync
		store.UpdateAsync = function(self: any, key: string, fn: any): (any, any)
			if not left then
				left = true
				sv.saves:leave(p) -- (the player goes while the DataStore call is out)
			end
			return real(self, key, fn)
		end
		sv = server(store, "A", now, sleep)
		sv.saves:join(p)
		t.truthy(store:peek("p_50") ~= nil, "(the load wrote the record)")
		t.eq(store:peek("p_50").meta.lock, nil, "released as soon as the load came back")
		t.falsy(sv.saves:busy())
	end)

	-- Bought while the profile was loading, and gone before the load came back: the release that hands the lock
	-- straight back carries the purchase.
	t.test("a purchase made while loading is in the record when the player leaves before the load returns", function()
		local store = MockDataStore.new()
		local _c, now, sleep = clock()
		local p = { UserId = 58 }
		local sv: any = nil
		local left = false
		local real = store.UpdateAsync
		store.UpdateAsync = function(self: any, key: string, fn: any): (any, any)
			if not left then
				left = true
				sv.wardrobe:give(p, SHIRT) -- (bought while the load is out)
				sv.wardrobe:leave(p)
				sv.saves:leave(p)
			end
			return real(self, key, fn)
		end
		sv = server(store, "A", now, sleep)
		sv.saves:join(p)
		local rec = store:peek("p_58")
		t.eq(rec.meta.lock, nil, "handed straight back")
		t.eq(rec.data.wardrobe[SHIRT], true, "with the purchase")
		t.eq(rec.data.worn.shirt, SHIRT)
		t.falsy(sv.saves:busy())
	end)

	-- PASSES (a guard the builder's spec lacks: it compares against the template, whose other fields are all empty,
	-- so a change that reset them would go unseen). A record holding money, receipts, items, reputation and stats
	-- goes through load, a purchase, an autosave and a release with every non-clothing field exactly as it was.
	t.test("holds: a full record's non-clothing fields are untouched by load, buy, autosave and release", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local rec = ProfileSchema.template() :: any
		rec.schema = 1
		rec.worn = nil
		rec.wallet.cents = 1234
		rec.receipts = {
			ids = { "r1" },
			byId = { r1 = { productId = 9, cents = 100, at = 5, playerId = 49 } },
		}
		rec.inventory = { kite = 2 }
		rec.reputation = 17
		rec.stats = { bites = 3 }
		rec.wardrobe = { future_hat = true }
		store.data.p_49 = { data = rec, meta = { writes = 1 } }
		local a = server(store, "A", now, sleep)
		local p = { UserId = 49 }
		a.saves:join(p)
		a.wardrobe:give(p, SHIRT)
		c.t += 31
		a.saves:step(now())
		a.saves:leave(p)
		local out = store:peek("p_49").data
		t.eq(out.schema, 2)
		t.eq(out.wallet.cents, 1234)
		t.deepEq(out.receipts, rec.receipts)
		t.deepEq(out.inventory, { kite = 2 })
		t.eq(out.reputation, 17)
		t.deepEq(out.stats, { bites = 3 })
		t.deepEq(out.wardrobe, { future_hat = true, [SHIRT] = true })
		t.deepEq(out.worn, { shirt = SHIRT })
		t.eq(Clothing.isClothing("future_hat"), false, "(an id this build does not know survives)")
	end)

	-- The desk's own cooldown: a press within GiftShop.COOLDOWN of the last counts for nothing and says nothing.
	t.test("the desk ignores a press within its cooldown, without words", function()
		local store = MockDataStore.new()
		local _c, now, sleep = clock()
		local sv = server(store, "A", now, sleep)
		local p = { UserId = 51 }
		sv.saves:join(p)
		sv.wardrobe:give(p, SHIRT)
		local deskT = 0
		local said = 0
		local deps: GiftShop.Deps = {
			wallet = {
				buy = function(_p: any, _id: string, _deliver: any): (boolean, string)
					return false, "not used"
				end,
			},
			wardrobe = sv.wardrobe,
			speciesOf = function(_p: any): string?
				return "human"
			end,
			present = function(_p: any): boolean
				return true
			end,
			tell = function(_p: any, _w: string)
				said += 1
			end,
			now = function(): number
				return deskT
			end,
		}
		local counted = 0
		for _ = 1, 20 do -- two seconds of presses, ten a second
			if GiftShop.press(deps, p) then
				counted += 1
			end
			deskT += 0.1
		end
		t.eq(counted, 4, "one press counts every COOLDOWN (0.5 s)")
		t.eq(said, 4, "an ignored press puts nothing on the screen")
	end)

	-- The server-wide budget. Roblox allows a server 60 + 10 x players UpdateAsync a minute (360 with 30 players).
	-- Saves (changes, purchases, autosaves) take tokens from a bucket refilled at half of that (180 a minute with
	-- 30 players, at most BURST in hand); loads and releases have the other half. Thirty players each toggling the
	-- shirt four times a second for five minutes: each player's own gap alone would allow 10 writes a minute (300),
	-- the bucket holds the whole server to 180 a minute plus the burst, and every last choice is saved soon after.
	t.test("thirty players flooding the desk stay inside the server's DataStore budget", function()
		local allowance, saves = PlayerSaves.budgetPerMinute(30)
		t.eq(allowance, 360)
		t.eq(saves, 180)
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local sv = server(store, "A", now, sleep)
		local players = {}
		for i = 1, 30 do
			local p = { UserId = 1000 + i }
			table.insert(players, p)
			sv.saves:join(p)
			sv.wardrobe:give(p, SHIRT)
		end
		local loads = store.calls.updates
		t.eq(loads, 30, "one load each; the purchases wait for their gap")
		local perMinute: { number } = {}
		for second = 1, 300 do
			for _ = 1, 4 do
				for _, p in players do
					if sv.wardrobe:worn(p, "shirt") then
						sv.wardrobe:takeOff(p, "shirt")
					else
						sv.wardrobe:wear(p, SHIRT)
					end
				end
				c.t += 0.25
			end
			local before = store.calls.updates
			sv.saves:step(now())
			local minute = math.floor((second - 1) / 60) + 1
			perMinute[minute] = (perMinute[minute] or 0) + store.calls.updates - before
		end
		for minute, n in perMinute do
			t.truthy(n <= saves + PlayerSaves.BURST, `minute {minute}: {n} saves (bucket {saves} + burst)`)
			t.truthy(n + loads <= allowance, `minute {minute}: {n} saves + {loads} loads inside {allowance}`)
		end
		t.truthy(perMinute[5] >= saves - 2, `the bucket is used, not starved: {perMinute[5]} in minute 5`)
		-- every player's latest choice is in the store within a few steps once the presses stop
		for _ = 1, 12 do
			c.t += 1
			sv.saves:step(now())
		end
		for _, p in players do
			local rec = store:peek(`p_{p.UserId}`).data
			t.eq(rec.worn.shirt, sv.wardrobe:worn(p, "shirt"), `player {p.UserId}'s last choice is saved`)
		end
	end)

	t.test("the other order: the first wearer swept first also gives the body its own colour back", function()
		local Instance, Color3 = roblox.Instance, roblox.Color3
		local body = Instance.new("Model")
		local torso = Instance.new("Part")
		torso.Name = "UpperTorso"
		torso.Color = Color3.fromRGB(200, 10, 10)
		torso.Parent = body
		local store = MockDataStore.new()
		local _c, now, sleep = clock()
		local sv = server(store, "A", now, sleep)
		local ann, bob = { UserId = 52 }, { UserId = 53 }
		local holds: { [any]: any } = { [ann] = body }
		sv.wardrobe.deps.bodyOf = function(p: any): (any?, string?)
			local b = holds[p]
			return b, if b then "human" else nil
		end
		sv.wardrobe.deps.rgb = Color3.fromRGB
		sv.wardrobe.deps.players = function(): { any }
			return { ann, bob }
		end
		for _, p in { ann, bob } do
			sv.saves:join(p)
			sv.wardrobe:give(p, SHIRT)
		end
		sv.wardrobe:sweep()
		holds[ann], holds[bob] = nil, body
		sv.wardrobe:sweep()
		t.eq(math.floor(torso.Color.R * 255 + 0.5), 40, "Bob's shirt shows")
		t.eq(body:GetAttribute("Wearing"), SHIRT)
		holds[bob] = nil
		sv.wardrobe:sweep()
		t.eq(math.floor(torso.Color.R * 255 + 0.5), 200)
		t.eq(body:GetAttribute("Wearing"), nil)
	end)

	-- BindToClose gives 30 s. A release used to have 4 retries (1+2+4+8 s of backoff) and could queue behind a load
	-- sitting in its lock waits (4 x 4 s). Now closeAll drops queued loads and saves, tells the store it is closing
	-- (one retry per call, lock waits and backoff sleeps cut short) and releases everyone.
	t.test("shutdown: the releases fit in the close window, even behind a load's lock wait and a slow store", function()
		for _, slow in { false, true } do
			local S = sim()
			local store = MockDataStore.new()
			local latency = if slow then 3 else 0.5
			local real = store.UpdateAsync
			local calls: { [string]: number } = {}
			store.UpdateAsync = function(self: any, key: string, fn: any): (any, any)
				calls[key] = (calls[key] or 0) + 1
				S.sleep(latency)
				return real(self, key, fn)
			end
			-- another server holds p_62 (the player hopped here and that one is slow to let go)
			local held = ProfileSchema.template() :: any
			held.wardrobe = { [SHIRT] = true }
			store.data.p_62 = {
				data = held,
				meta = { lock = { jobId = "B", session = "B:62", expires = S.t + 1000 }, writes = 5 },
			}
			local sv: any = {}
			sv.saves = PlayerSaves.new({
				store = store,
				jobId = "A",
				now = S.now,
				sleep = S.sleep,
				spawn = S.spawn,
				tell = function(_p: any, _w: string) end,
				loaded = function(player: any, data: any): boolean
					return sv.wardrobe:loaded(player, data)
				end,
				log = function(_line: string) end,
				warn = function(_line: string) end,
			}) -- (ProfileStore's real defaults: 4 retries, 4 lock waits of 4 s)
			sv.wardrobe = Wardrobe.new({
				saves = sv.saves,
				bodyOf = function(_p: any): (any?, string?)
					return nil, "human"
				end,
				players = function(): { any }
					return {}
				end,
			})
			local p1, p2, p3 = { UserId = 61 }, { UserId = 62 }, { UserId = 63 }
			sv.saves:join(p1)
			sv.saves:join(p2)
			S.run(S.t + latency + 0.5)
			t.eq(sv.saves:status(p1), "saved")
			t.eq(sv.saves:status(p2), "loading", "(p2 is early in a 4 s lock wait)")
			sv.wardrobe:give(p1, SHIRT)
			if slow then
				store:fail("throttle", 100) -- the store fails every call from here on, three seconds each
			end
			sv.saves:join(p3)
			S.run(S.t) -- (its load is in flight when the server closes)
			local start = S.t
			local p2Calls = calls.p_62
			local doneAt: number? = nil
			S.spawn(function()
				sv.saves:closeAll()
				doneAt = S.t
			end)
			S.run(math.huge)
			t.truthy(doneAt, "closeAll returned")
			local took = (doneAt :: number) - start
			t.falsy(sv.saves:busy(), "every release finished inside the window")
			t.truthy(took < PlayerSaves.CLOSE_SECONDS, `closeAll took {took} s`)
			t.eq(store:peek("p_62").meta.lock.jobId, "B", "the other server's lock is never touched")
			t.eq(calls.p_62, p2Calls, "a lock wait cut short by the shutdown makes no further call")
			if slow then
				-- the in-flight load gives up (no retry), then its maybe-lock is cleared with one retry: 3 calls
				t.truthy(took <= 3 * latency + 2, `a failing store: {took} s`)
				t.eq(calls.p_63, 3)
			else
				t.truthy(took <= 2, `not behind the lock wait: {took} s`)
				t.eq(store:peek("p_61").meta.lock, nil, "released")
				t.eq(store:peek("p_61").data.wardrobe[SHIRT], true, "with the latest change")
				t.eq(store:peek("p_63").meta.lock, nil, "the load that landed after the close is handed back")
			end
			t.truthy((calls.p_61 or 0) <= 3, `p_61: {calls.p_61} calls (a load, a release and one retry)`)
		end
	end)

	-- Studio with API access off: the error is fatal to ProfileStore, so the state is "off" after one call, not
	-- after the whole retry budget (5 calls, about 15 s of backoff in the engine).
	t.test("saving off is known after one call", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local n = 0
		store.UpdateAsync = function(_self: any, _k: string, _f: any): (any, any)
			n += 1
			error("StudioAccessToApisNotAllowed: Studio access to APIs is not allowed")
		end
		local start = c.t
		local sv = server(store, "A", now, sleep)
		local p = { UserId = 54 }
		sv.saves:join(p)
		t.eq(sv.saves:status(p), "off")
		t.eq(n, 1)
		t.eq(c.t, start, "no backoff slept")
	end)

	-- A purchase made while the profile is "unsaved" (another server still held the lock) is saved on the way out
	-- when the lock is free by then; when it is not, nothing is written over the other server's record.
	t.test("a purchase made while unsaved is saved when the player leaves, if the lock is free by then", function()
		local store = MockDataStore.new()
		local _c, now, sleep = clock()
		local b = server(store, "B", now, sleep)
		local a = server(store, "A", now, sleep)
		local p, q = { UserId = 55 }, { UserId = 56 }
		b.saves:join(p)
		b.saves:join(q)
		a.saves:join(p)
		a.saves:join(q)
		t.eq(a.saves:status(p), "unsaved")
		local ok, note = a.wardrobe:give(p, SHIRT)
		t.truthy(ok)
		t.eq(note, Wardrobe.WORDS.unsaved)
		a.wardrobe:give(q, SHIRT)
		b.saves:leave(p) -- B lets go of p, still holds q
		a.wardrobe:leave(p)
		a.saves:leave(p)
		t.eq(store:peek("p_55").data.wardrobe[SHIRT], true, "saved on the way out")
		t.eq(store:peek("p_55").meta.lock, nil, "and handed back")
		local writes = store:peek("p_56").meta.writes
		a.wardrobe:leave(q)
		a.saves:leave(q)
		t.eq(store:peek("p_56").meta.lock.jobId, "B", "B's lock stands")
		t.eq(store:peek("p_56").meta.writes, writes, "nothing written over B's record")
		t.eq(store:peek("p_56").data.wardrobe[SHIRT], nil)
	end)

	-- A worn choice changed here while unsaved and never saved does not come back on a rejoin to this server over
	-- the choice saved since (on another server).
	t.test("a same-server rejoin takes the saved worn choice, not last visit's unsaved one", function()
		local store = MockDataStore.new()
		local _c, now, sleep = clock()
		local b = server(store, "B", now, sleep)
		local a = server(store, "A", now, sleep)
		local p = { UserId = 57 }
		b.saves:join(p)
		b.wardrobe:give(p, SHIRT)
		a.saves:join(p) -- B still holds the lock
		t.eq(a.saves:status(p), "unsaved")
		a.wardrobe:give(p, SHIRT) -- (bought again here: it is on)
		a.wardrobe:takeOff(p, "shirt") -- and off, here, unsaved
		a.wardrobe:leave(p)
		a.saves:leave(p) -- the last look finds B's lock: nothing saved
		b.wardrobe:leave(p)
		b.saves:leave(p) -- B saves the shirt worn
		t.eq(store:peek("p_57").data.worn.shirt, SHIRT)
		a.wardrobe:join(p)
		a.saves:join(p)
		t.eq(a.saves:status(p), "saved")
		t.eq(a.wardrobe:worn(p, "shirt"), SHIRT, "the saved choice")
		t.truthy(a.wardrobe:owns(p, SHIRT))
	end)
end
