--!strict
-- Review of feat/save-clothing (owner D16 #25): cases the builder's clothing_save.spec does not hold. The ones
-- marked FAILS fail on the reviewed code (review/save-clothing); the last one passes and guards the rule that only
-- the clothing in a record is ever changed.
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

return function(t)
	-- FAILS. Every E press at the gift shop desk (owned shirt: on, off, on ...) is an immediate UpdateAsync. A held
	-- E / autoclicker / fireproximityprompt loop at 4 presses a second is 240 UpdateAsync a minute from ONE player,
	-- against the whole server's budget of 60 + 10 x players a minute (360 with 30 players, of which the autosave
	-- already takes 60). Expected: changes coalesce (a dirty flag the step writes at most every few seconds per
	-- key, or a per-player press cooldown), so a burst costs a couple of writes.
	t.test("FAILS: a client cannot flood the DataStore budget by toggling the shirt at the desk", function()
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

	-- FAILS. An ambiguous load failure (UpdateAsync committed the lock, then the reply was lost: the case
	-- MockDataStore calls commitThenError, specced for saves but not for loads) leaves this server's OWN lock in the
	-- record for the whole lease (180 s). Each retry makes a new session id, finds that live lock and waits, so the
	-- player is "unsaved" here for three minutes on a transient error. Expected: a lock this server wrote (its own
	-- jobId, or the same session reused across a player's retries) is taken back at once.
	t.test("FAILS: a load whose reply was lost does not lock the player out of their own server", function()
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

	-- FAILS (same cause). The player gives up and hops: the leave of an unsaved session releases nothing, so the
	-- orphan lock (whose jobId is A, still alive) holds the next server off for the rest of the lease.
	t.test("FAILS: after a lost load reply, leaving does not leave the next server waiting out the lease", function()
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

	-- FAILS. "Never written over: a broken record" holds for a newer schema, but not for a record whose `data` is
	-- missing or has no `schema`: ProfileStore.load passes old.data (nil for a non-table or a top-level record) to
	-- ProfileSchema.migrate, which reads nil as a new player and a table without `schema` as the v0 { cents } shape;
	-- both are replaced by an empty template and written, the owned clothing dropped. (Nothing has written the live
	-- "Profiles" store before this branch, so no such record exists yet; this guards the rule for any future writer
	-- or hand edit.) Expected: only an absent key is a new player; anything else unreadable is "corrupt".
	t.test("FAILS: a record that is not a profile is left as it is, never replaced by a template", function()
		local store = MockDataStore.new()
		local _c, now, sleep = clock()
		store.data.p_44 = { data = { wardrobe = { [SHIRT] = true }, worn = { shirt = SHIRT } }, meta = { writes = 3 } }
		store.data.p_45 = "a string, not a profile"
		store.data.p_46 = { cents = 7 } -- the v0 shape ProfileSchema.migrate says it still reads
		local a = server(store, "A", now, sleep)
		local broken, junk, v0 = { UserId = 44 }, { UserId = 45 }, { UserId = 46 }
		a.saves:join(broken)
		a.saves:join(junk)
		a.saves:join(v0)
		t.eq(a.saves:status(broken), "corrupt", "a data table without schema")
		t.deepEq(store:peek("p_44").data.wardrobe, { [SHIRT] = true }, "its clothing is not wiped")
		t.eq(a.saves:status(junk), "corrupt", "a non-table record")
		t.eq(store:peek("p_45"), "a string, not a profile")
		local v0data = a.saves:data(v0)
		t.eq(v0data and v0data.wallet.cents, 7, "a top-level v0 record keeps its cents through load")
	end)

	-- FAILS. Two players who both wear the shirt hand one body over inside one sweep (A releases townsperson P, B
	-- picks P from the menu before the next 1 Hz sweep). If B is swept first, B's dress records A's navy as P's
	-- "own" colour; A's undo then puts the real colour back under B (B's shirt no longer shows, and the sweep never
	-- re-dresses because B's look key is unchanged); when B lets go, B's undo paints P navy for good: a townsperson
	-- left in the shirt with nobody wearing it. Expected: the body's own colour survives any handover order (e.g.
	-- record it once per body, or undress every changed entry before dressing any).
	t.test("FAILS: a body handed between two shirt wearers inside one sweep gets its own colour back", function()
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
		local order = { ann }
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
end
