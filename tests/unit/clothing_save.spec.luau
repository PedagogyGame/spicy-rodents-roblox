--!strict
-- Clothing carries over between servers (owner D16 #25): Shared/Items/Clothing (what counts, the saved shape),
-- Server/Persistence/PlayerSaves (the live server's session-locked profiles over ProfileStore, on MockDataStore and a
-- fake clock shared by the "servers"), Server/Cosmetics/Wardrobe (only the clothing is written) and
-- Server/Cosmetics/GiftShop (the alley shirt, through the real wallet). Failures: a failing load, a failing save, a
-- lock held by another server, a lost lock, a newer record, no DataStore, a leave while loading, a rejoin while
-- releasing, the shutdown.
local roblox = require("@lune/roblox")
local Clothing = require("@shared/Items/Clothing")
local ItemRules = require("@shared/Items/ItemRules")
local EconomyRules = require("@shared/Economy/EconomyRules")
local ProfileSchema = require("@server/Persistence/ProfileSchema")
local MockDataStore = require("@server/Persistence/MockDataStore")
local PlayerSaves = require("@server/Persistence/PlayerSaves")
local Wardrobe = require("@server/Cosmetics/Wardrobe")
local GiftShop = require("@server/Cosmetics/GiftShop")
local Credits = require("@server/Economy/Credits")

local SHIRT = "alley_shirt"

-- a fake wall clock shared by the "servers"; sleep advances it
local function clock()
	local c = { t = 1_700_000_000 }
	return c, function(): number
		return c.t
	end, function(s: number)
		c.t += s
	end
end

type Server = {
	saves: any,
	wardrobe: any,
	told: { [number]: { string } },
	attrs: { [number]: { [string]: any } },
	jobs: { () -> () }?, -- deferred spawn: run by hand
	players: { any },
}

-- One simulated server: PlayerSaves + Wardrobe on `store`. `deferred` keeps spawned jobs until run(server).
local function server(store: any, jobId: string, now: () -> number, sleep: (number) -> (), deferred: boolean?): Server
	local sv: Server = { saves = nil, wardrobe = nil, told = {}, attrs = {}, jobs = nil, players = {} }
	if deferred then
		sv.jobs = {}
	end
	sv.saves = PlayerSaves.new({
		store = store,
		jobId = jobId,
		now = now,
		sleep = sleep,
		spawn = function(fn: () -> ())
			if sv.jobs then
				table.insert(sv.jobs, fn)
			else
				fn()
			end
		end,
		tell = function(player: any, words: string)
			sv.told[player.UserId] = sv.told[player.UserId] or {}
			table.insert(sv.told[player.UserId], words)
		end,
		loaded = function(player: any, data: any): boolean
			return sv.wardrobe:loaded(player, data)
		end,
		changed = function(player: any, state: string)
			sv.attrs[player.UserId] = sv.attrs[player.UserId] or {}
			sv.attrs[player.UserId].ClothesSaved = state
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
			return sv.players
		end,
		setAttr = function(player: any, name: string, value: any)
			sv.attrs[player.UserId] = sv.attrs[player.UserId] or {}
			sv.attrs[player.UserId][name] = value
		end,
	})
	return sv
end

local function run(sv: Server)
	local jobs = sv.jobs :: { () -> () }
	while #jobs > 0 do
		table.remove(jobs, 1)()
	end
end

local function told(sv: Server, player: any, words: string): boolean
	for _, w in sv.told[player.UserId] or {} do
		if w == words then
			return true
		end
	end
	return false
end

local function saved(store: any, id: number): any
	local rec = store:peek(`p_{id}`)
	return if rec then rec.data else nil
end

return function(t)
	t.test("what counts as clothing: the alley shirt and the paintball garb, each sellable by the wallet", function()
		t.truthy(Clothing.isClothing(SHIRT))
		t.truthy(Clothing.isClothing("paintball_garb_set"))
		for _, d in Clothing.CATALOG do
			t.truthy(EconomyRules.item(d.id), `{d.id} has a price and a name`)
			t.truthy(table.find(Clothing.SLOTS, d.slot), d.id)
		end
		for id in Clothing.NOT_CLOTHING do
			t.falsy(Clothing.isClothing(id), id)
		end
		-- none of the corner store's 22 items is clothing: they all stay on the server they were bought on
		for _, d in ItemRules.CATALOG do
			t.falsy(Clothing.isClothing(d.id), d.id)
		end
		t.falsy(Clothing.isClothing(nil))
		t.falsy(Clothing.isClothing("coffee"))
	end)

	t.test("the saved shape: only wardrobe and worn are written; a newer build's clothing is kept", function()
		local data = ProfileSchema.template() :: any
		data.wardrobe = { [SHIRT] = true, future_hat = true }
		data.worn = { shirt = SHIRT, hat = "future_hat", pants = "not_owned" }
		local w = Clothing.fromSaved(data)
		t.truthy(Clothing.owns(w, "future_hat"))
		t.eq(Clothing.wornIn(w, "hat"), "future_hat") -- (a slot this build has, an id it does not: kept)
		t.eq(Clothing.wornIn(w, "pants"), nil) -- not owned: not worn
		Clothing.takeOff(w, "shirt")
		local before = ProfileSchema.deepCopy(data)
		Clothing.toSaved(w, data)
		t.deepEq(data.wardrobe, { [SHIRT] = true, future_hat = true })
		t.deepEq(data.worn, { hat = "future_hat" })
		for k, v in before do
			if k ~= "wardrobe" and k ~= "worn" then
				t.deepEq(data[k], v, k)
			end
		end
		t.truthy((ProfileSchema.validate(data)))
		-- wear refuses what is not owned or not clothing
		local e = Clothing.empty()
		t.deepEq({ Clothing.wear(e, SHIRT) }, { false, "not owned" })
		t.deepEq({ Clothing.wear(e, "kite") }, { false, "not clothing" })
	end)

	t.test("schema v2: a v1 record keeps its wardrobe and gains an empty worn; v0 still migrates", function()
		local v1 = {
			schema = 1,
			wallet = { cents = 5 },
			receipts = { ids = {}, byId = {} },
			wardrobe = { [SHIRT] = true },
			inventory = {},
			reputation = 0,
			stats = {},
		}
		local d = ProfileSchema.migrate(v1) :: any
		t.eq(d.schema, 2)
		t.deepEq(d.worn, {})
		t.deepEq(d.wardrobe, { [SHIRT] = true })
		t.eq(v1.worn, nil, "the raw record is not changed in place")
		t.eq((ProfileSchema.migrate({ cents = 7 }) :: any).wallet.cents, 7)
		local bad = ProfileSchema.migrate({ schema = 2, worn = { shirt = 3 } })
		t.eq(bad, nil)
	end)

	t.test("bought on one server, worn on the next; money and other items are not saved", function()
		local store = MockDataStore.new()
		local _c, now, sleep = clock()
		local a = server(store, "A", now, sleep)
		local ann = { UserId = 11 }
		a.saves:join(ann)
		t.eq(a.saves:status(ann), "saved")
		t.eq(a.attrs[11].ClothesSaved, "saved")
		local ok, note = a.wardrobe:give(ann, SHIRT)
		t.truthy(ok)
		t.eq(note, nil) -- saved: nothing to add to the shop's words
		local rec = saved(store, 11)
		t.deepEq(rec.wardrobe, { [SHIRT] = true }, "written at once, not at the next autosave")
		t.deepEq(rec.worn, { shirt = SHIRT })
		t.eq(a.attrs[11].Clothes, SHIRT)
		-- nothing else in the record moved from the template (D16 #25: only clothing carries over)
		local template = ProfileSchema.template() :: any
		for k, v in template do
			if k ~= "wardrobe" and k ~= "worn" then
				t.deepEq(rec[k], v, k)
			end
		end
		a.wardrobe:takeOff(ann, "shirt")
		t.deepEq(saved(store, 11).worn, {})
		a.wardrobe:wear(ann, SHIRT)
		a.wardrobe:leave(ann)
		a.saves:leave(ann)
		t.eq(store:peek("p_11").meta.lock, nil, "released on leave")
		-- another server
		local b = server(store, "B", now, sleep)
		b.saves:join(ann)
		t.eq(b.saves:status(ann), "saved")
		t.truthy(b.wardrobe:owns(ann, SHIRT))
		t.eq(b.wardrobe:worn(ann, "shirt"), SHIRT)
		t.eq(b.attrs[11].Clothes, SHIRT)
	end)

	t.test("another server still holds the lock: play on, told once, bought here is merged when it loads", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a = server(store, "A", now, sleep)
		local b = server(store, "B", now, sleep)
		local bo = { UserId = 12 }
		a.saves:join(bo)
		a.wardrobe:give(bo, "paintball_garb_set")
		-- (the player hops: B starts loading while A has not yet released)
		b.saves:join(bo)
		t.eq(b.saves:status(bo), "unsaved")
		t.truthy(told(b, bo, PlayerSaves.WORDS.unsaved))
		local ok, note = b.wardrobe:give(bo, SHIRT)
		t.truthy(ok, "a failing DataStore never undoes a purchase")
		t.eq(note, Wardrobe.WORDS.unsaved)
		t.truthy(b.wardrobe:owns(bo, SHIRT))
		a.saves:leave(bo)
		-- not before the retry time
		b.saves:step(now())
		t.eq(b.saves:status(bo), "unsaved")
		c.t += PlayerSaves.RETRY_FIRST
		b.saves:step(now())
		t.eq(b.saves:status(bo), "saved")
		t.truthy(told(b, bo, PlayerSaves.WORDS.back))
		local rec = saved(store, 12)
		t.deepEq(rec.wardrobe, { [SHIRT] = true, paintball_garb_set = true }, "both servers' clothes")
		t.deepEq(rec.worn, { shirt = SHIRT, suit = "paintball_garb_set" })
		t.eq(#b.told[12], 2, "told once that it was late and once that it is back")
	end)

	t.test("a load that keeps failing is retried with backoff, and stops when the player leaves", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a = server(store, "A", now, sleep)
		local cy = { UserId = 13 }
		store:fail("error", 3) -- 1 try + 2 retries
		a.saves:join(cy)
		t.eq(a.saves:status(cy), "unsaved")
		store:fail("throttle", 3)
		c.t += PlayerSaves.RETRY_FIRST
		a.saves:step(now())
		t.eq(a.saves:status(cy), "unsaved")
		c.t += PlayerSaves.RETRY_FIRST -- the second wait is doubled: not yet
		local updates = store.calls.updates
		a.saves:step(now())
		t.eq(store.calls.updates, updates)
		c.t += PlayerSaves.RETRY_FIRST
		a.saves:step(now())
		t.eq(a.saves:status(cy), "saved")
		t.eq(#a.told[13], 2, "told once, not at every retry")
		a.saves:leave(cy)
		t.eq(store:peek("p_13").meta.lock, nil)
	end)

	t.test("a save that fails is retried; the player is told once and told when it catches up", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a = server(store, "A", now, sleep)
		local di = { UserId = 14 }
		a.saves:join(di)
		store:fail("error", 3)
		local ok, note = a.wardrobe:give(di, SHIRT)
		t.truthy(ok)
		t.eq(note, nil)
		t.eq(saved(store, 14).wardrobe[SHIRT], nil)
		t.truthy(told(a, di, PlayerSaves.WORDS.slow))
		t.truthy(a.wardrobe:owns(di, SHIRT), "still theirs on this server")
		a.saves:step(now()) -- not yet
		t.eq(saved(store, 14).wardrobe[SHIRT], nil)
		c.t += PlayerSaves.SAVE_RETRY
		a.saves:step(now())
		t.eq(saved(store, 14).wardrobe[SHIRT], true)
		t.truthy(told(a, di, PlayerSaves.WORDS.caughtUp))
		-- an ambiguous failure (written, then the reply lost) is safe to write again
		store:fail("commitThenError", 1)
		a.wardrobe:takeOff(di, "shirt")
		t.deepEq(saved(store, 14).worn, {})
	end)

	t.test("the autosave renews the lease; a lost lock is never written over", function()
		local store = MockDataStore.new()
		local c, now, sleep = clock()
		local a = server(store, "A", now, sleep)
		local ed = { UserId = 15 }
		a.saves:join(ed)
		local writes = store.calls.writes
		c.t += 30
		a.saves:step(now())
		t.eq(store.calls.writes, writes + 1, "autosave")
		-- A stalls past its lease (a frozen server): B takes the lapsed lock
		c.t += 200
		local b = server(store, "B", now, sleep)
		b.saves:join(ed)
		t.eq(b.saves:status(ed), "saved")
		b.wardrobe:give(ed, SHIRT)
		-- A wakes up and tries to save its own change: refused, told, never written
		local ok, note = a.wardrobe:give(ed, "paintball_garb_set")
		t.truthy(ok)
		t.eq(note, Wardrobe.WORDS.lost) -- (the save ran at once and met B's lock)
		t.eq(a.saves:status(ed), "lost")
		t.truthy(told(a, ed, PlayerSaves.WORDS.lost))
		t.eq(saved(store, 15).wardrobe.paintball_garb_set, nil)
		local _, later = a.wardrobe:wear(ed, "paintball_garb_set")
		t.eq(later, Wardrobe.WORDS.lost)
		a.saves:leave(ed) -- the release writes nothing either
		t.deepEq(saved(store, 15).wardrobe, { [SHIRT] = true })
		t.eq(store:peek("p_15").meta.lock.jobId, "B")
	end)

	t.test("a newer or broken record is never written over", function()
		local store = MockDataStore.new()
		local _c, now, sleep = clock()
		store.data.p_16 = { data = { schema = 99, wardrobe = { x = true } }, meta = { writes = 4 } }
		local a = server(store, "A", now, sleep)
		local fi = { UserId = 16 }
		a.saves:join(fi)
		t.eq(a.saves:status(fi), "corrupt")
		t.truthy(told(a, fi, PlayerSaves.WORDS.corrupt))
		local ok, note = a.wardrobe:give(fi, SHIRT)
		t.truthy(ok)
		t.eq(note, Wardrobe.WORDS.corrupt)
		a.saves:step(now() + 1000)
		a.saves:leave(fi)
		t.eq(store:peek("p_16").data.schema, 99)
		t.eq(store:peek("p_16").meta.writes, 4)
	end)

	t.test("no DataStore (Studio without API access): saving is off, play and buying go on", function()
		local _c, now, sleep = clock()
		local a = server(nil, "A", now, sleep)
		local gi = { UserId = 17 }
		a.saves:join(gi)
		t.eq(a.saves:status(gi), "off")
		local ok, note = a.wardrobe:give(gi, SHIRT)
		t.truthy(ok)
		t.eq(note, Wardrobe.WORDS.off)
		a.saves:step(now() + 1000)
		a.saves:closeAll()
		-- a store that answers with Studio's "API access is off" error: off at once, never retried
		local store = MockDataStore.new()
		store.UpdateAsync = function(_self: any, _k: string, _f: any): (any, any)
			error("StudioAccessToApisNotAllowed: Studio access to APIs is not allowed")
		end
		local b = server(store, "B", now, sleep)
		b.saves:join(gi)
		t.eq(b.saves:status(gi), "off")
		t.eq(b.told[17], nil, "said in the log, not on the screen")
	end)

	t.test("threads: a leave while loading hands the lock back; a rejoin waits for the release", function()
		local store = MockDataStore.new()
		local _c, now, sleep = clock()
		local a = server(store, "A", now, sleep, true)
		local hu = { UserId = 18 }
		a.saves:join(hu)
		t.eq(a.saves:status(hu), "loading")
		-- bought before the profile arrived: kept, and merged when it does
		local ok, note = a.wardrobe:give(hu, SHIRT)
		t.truthy(ok)
		t.eq(note, Wardrobe.WORDS.loading)
		run(a)
		t.eq(a.saves:status(hu), "saved")
		t.deepEq(saved(store, 18).wardrobe, { [SHIRT] = true })
		-- leave and rejoin before the release has run: one queue, in order
		a.saves:leave(hu)
		a.saves:join(hu)
		t.eq(a.saves:status(hu), "loading")
		t.truthy(a.saves:busy())
		run(a)
		t.eq(a.saves:status(hu), "saved")
		t.eq(store:peek("p_18").meta.lock.jobId, "A")
		-- a leave before the load ran: nothing is loaded, no lock is left behind
		local iv = { UserId = 19 }
		a.saves:join(iv)
		a.saves:leave(iv)
		run(a)
		t.eq(store:peek("p_19"), nil)
		t.falsy(a.saves:busy())
	end)

	t.test("shutdown: closeAll releases everyone", function()
		local store = MockDataStore.new()
		local _c, now, sleep = clock()
		local a = server(store, "A", now, sleep)
		local ps = { { UserId = 21 }, { UserId = 22 }, { UserId = 23 } }
		for _, p in ps do
			a.saves:join(p)
			a.wardrobe:give(p, SHIRT)
		end
		a.saves:closeAll()
		for _, p in ps do
			local rec = store:peek(`p_{p.UserId}`)
			t.eq(rec.meta.lock, nil)
			t.eq(rec.data.wardrobe[SHIRT], true)
			t.eq(a.saves:status(p), nil)
		end
	end)

	t.test("the gift shop sells the shirt once through the wallet, then puts it on and takes it off", function()
		local store = MockDataStore.new()
		local _c, now, sleep = clock()
		local a = server(store, "A", now, sleep)
		local wallet = Credits.new({
			tell = function(_p: any, _w: string) end,
			log = function(_l: string) end,
			warn = function(_l: string) end,
		})
		local jo = { UserId = 24, Name = "jo" }
		local species = "human"
		wallet.join(jo)
		a.saves:join(jo)
		local said: { string } = {}
		local deps: GiftShop.Deps = {
			wallet = wallet,
			wardrobe = a.wardrobe,
			speciesOf = function(_p: any): string?
				return species
			end,
			present = function(_p: any): boolean
				return true
			end,
			tell = function(_p: any, words: string)
				table.insert(said, words)
			end,
		}
		local before = wallet.balance(jo)
		local ok, words = GiftShop.press(deps, jo)
		t.truthy(ok, words)
		t.eq(said[#said], words, "said on the player's screen")
		t.eq(wallet.balance(jo), before - (EconomyRules.price(SHIRT) :: number))
		t.truthy(string.find(words, "every server", 1, true), words)
		t.eq(a.wardrobe:worn(jo, "shirt"), SHIRT)
		t.eq(saved(store, 24).wardrobe[SHIRT], true)
		-- owned: the desk takes it off and puts it on, for nothing
		t.deepEq({ GiftShop.press(deps, jo) }, { true, GiftShop.WORDS.off })
		t.eq(a.wardrobe:worn(jo, "shirt"), nil)
		t.deepEq({ GiftShop.press(deps, jo) }, { true, GiftShop.WORDS.on })
		t.eq(wallet.balance(jo), before - (EconomyRules.price(SHIRT) :: number))
		-- an animal is turned away
		species = "squirrel"
		t.deepEq({ GiftShop.press(deps, jo) }, { false, GiftShop.WORDS.animal })
		-- short of money: the wallet's words, nothing given
		species = "human"
		local kim = { UserId = 25, Name = "kim" }
		wallet.join(kim)
		wallet.spend(kim, wallet.balance(kim) - 3, "something else")
		local paid = GiftShop.press(deps, kim)
		t.falsy(paid)
		t.falsy(a.wardrobe:owns(kim, SHIRT))
		t.eq(wallet.balance(kim), 3)
	end)

	t.test("the look: the shirt's colour on the body's shirt parts, put back when it comes off", function()
		local Instance, Color3 = roblox.Instance, roblox.Color3
		local body = Instance.new("Model")
		local torso = Instance.new("Part")
		torso.Name = "UpperTorso"
		torso.Color = Color3.fromRGB(200, 10, 10)
		torso.Parent = body
		local def = Clothing.def(SHIRT) :: any
		local undo = Wardrobe.dress(body, def, Color3.fromRGB) :: () -> ()
		t.truthy(undo)
		local c = torso.Color
		t.eq(math.floor(c.R * 255 + 0.5), def.color[1])
		t.eq(body:GetAttribute("Wearing"), SHIRT)
		undo()
		t.eq(math.floor(torso.Color.R * 255 + 0.5), 200)
		t.eq(body:GetAttribute("Wearing"), nil)
		-- a rounded townsperson: the parts tinted "shirt", not the torso by name
		local sleeve = Instance.new("Part")
		sleeve.Name = "LeftUpperArm"
		sleeve:SetAttribute("PeopleTint", "shirt")
		sleeve.Parent = body
		local undo2 = Wardrobe.dress(body, def, Color3.fromRGB) :: () -> ()
		t.eq(math.floor(sleeve.Color.B * 255 + 0.5), def.color[3])
		t.eq(math.floor(torso.Color.R * 255 + 0.5), 200)
		undo2()
		-- the sweep: on the held body, off when the player moves to another (or a squirrel)
		local store = MockDataStore.new()
		local _c, now, sleep = clock()
		local sv = server(store, "A", now, sleep)
		local lee = { UserId = 26 }
		sv.players = { lee }
		local held, kind = body, "human"
		sv.wardrobe.deps.bodyOf = function(_p: any): (any?, string?)
			return held, kind
		end
		sv.wardrobe.deps.rgb = Color3.fromRGB
		sv.saves:join(lee)
		sv.wardrobe:give(lee, SHIRT)
		sv.wardrobe:sweep()
		t.eq(body:GetAttribute("Wearing"), SHIRT)
		kind = "squirrel"
		sv.wardrobe:sweep()
		t.eq(body:GetAttribute("Wearing"), nil)
		kind = "human"
		sv.wardrobe:sweep()
		t.eq(body:GetAttribute("Wearing"), SHIRT)
		sv.wardrobe:leave(lee)
		t.eq(body:GetAttribute("Wearing"), nil)
		t.eq(math.floor(torso.Color.R * 255 + 0.5), 200)
	end)
end
