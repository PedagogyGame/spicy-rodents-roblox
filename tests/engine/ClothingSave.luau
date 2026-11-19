--!strict
-- ServerStorage.EngineTests.ClothingSave (CI place only; ci.project.json)
-- Owner D16 #25 in the real engine: the live clothing save (Server/Persistence/PlayerSaves + Server/Cosmetics/
-- Wardrobe) against a real DataStore, two simulated servers on one key: server A loads a player, gives the alley
-- shirt (written at once, worn), server B is kept out while A holds the lock (unsaved, play goes on, its own purchase
-- kept), A leaves (released), B's retry loads and merges, B closes (BindToClose path: closeAll). The stored record
-- holds the clothing and nothing else changed from the template. Real task.spawn and task.wait, os.time.
-- Writes only keys under the "ci-clothes-" DataStore; nothing touches the game's "Profiles" store. Returns JSON.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

local server = ServerScriptService:WaitForChild("Server")
local persistence = server:WaitForChild("Persistence")
local PlayerSaves = (require :: any)(persistence:WaitForChild("PlayerSaves"))
local ProfileSchema = (require :: any)(persistence:WaitForChild("ProfileSchema"))
local Wardrobe = (require :: any)(server:WaitForChild("Cosmetics"):WaitForChild("Wardrobe"))

local Probe = {}

local SHIRT = "alley_shirt"

local function waitIdle(saves: any, limit: number): number
	local t0 = os.clock()
	while saves:busy() and os.clock() - t0 < limit do
		task.wait(0.1)
	end
	return os.clock() - t0
end

local function newServer(store: any, jobId: string, told: { string })
	local sv: any = {}
	sv.saves = PlayerSaves.new({
		store = store,
		jobId = jobId,
		now = os.time,
		sleep = function(s: number)
			task.wait(s)
		end,
		spawn = function(fn: () -> ())
			task.spawn(fn)
		end,
		tell = function(_player: any, words: string)
			table.insert(told, `{jobId}: {words}`)
		end,
		loaded = function(player: any, data: any): boolean
			return sv.wardrobe:loaded(player, data)
		end,
		leaseSeconds = 60,
		lockWaits = 1,
		lockWaitSeconds = 1,
		retries = 2,
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

function Probe.run(): { [string]: any }
	local out: { [string]: any } = { suite = "ClothingSave", placeId = game.PlaceId, placeVersion = game.PlaceVersion }
	local okStore, store = pcall(function()
		return DataStoreService:GetDataStore("ci-clothes-probe")
	end)
	if not okStore then
		out.ok = false
		out.err = tostring(store)
		return out
	end
	-- a fresh user id per run, so a run never meets an earlier run's record
	local userId = -math.random(1, 2 ^ 30)
	local player = { UserId = userId }
	local key = `p_{userId}`
	local told: { string } = {}
	local a = newServer(store, "ci-A", told)
	local b = newServer(store, "ci-B", told)
	local steps: { [string]: any } = { key = key }

	a.saves:join(player)
	steps.loadA = { seconds = waitIdle(a.saves, 30), status = a.saves:status(player) }
	task.wait(PlayerSaves.WRITE_GAP) -- (a purchase is written at once only once the load's write is a gap old)
	local gave, note = a.wardrobe:give(player, SHIRT)
	steps.giveA = { ok = gave, note = note, seconds = waitIdle(a.saves, 30) }
	local afterA = store:GetAsync(key)
	steps.storedAfterGive = {
		owned = afterA and afterA.data.wardrobe[SHIRT] == true,
		worn = afterA and afterA.data.worn.shirt,
		lockedBy = afterA and afterA.meta.lock and afterA.meta.lock.jobId,
	}

	b.saves:join(player)
	steps.loadBWhileHeld = { seconds = waitIdle(b.saves, 60), status = b.saves:status(player) }
	local gaveB, noteB = b.wardrobe:give(player, "paintball_garb_set")
	steps.giveBWhileHeld = { ok = gaveB, note = noteB }

	a.wardrobe:leave(player)
	a.saves:leave(player)
	steps.releaseA = { seconds = waitIdle(a.saves, 30) }

	b.saves:step(os.time() + PlayerSaves.RETRY_FIRST)
	steps.retryB = { seconds = waitIdle(b.saves, 60), status = b.saves:status(player) }
	b.saves:closeAll(25)
	local final = store:GetAsync(key)
	local template = ProfileSchema.template()
	local untouched = final ~= nil
	if final then
		for k, v in template :: any do
			if
				k ~= "wardrobe"
				and k ~= "worn"
				and HttpService:JSONEncode(final.data[k]) ~= HttpService:JSONEncode(v)
			then
				untouched = false
			end
		end
	end
	steps.final = {
		wardrobe = final and final.data.wardrobe,
		worn = final and final.data.worn,
		lockCleared = final ~= nil and final.meta.lock == nil,
		writes = final and final.meta.writes,
		onlyClothing = untouched,
	}
	steps.told = told
	pcall(function()
		store:RemoveAsync(key)
	end)
	out.steps = steps
	out.pass = {
		loadsAndSaves = steps.loadA.status == "saved" and steps.storedAfterGive.owned == true,
		wornSaved = steps.storedAfterGive.worn == SHIRT,
		lockKeepsSecondServerOut = steps.loadBWhileHeld.status == "unsaved" and gaveB == true,
		retryMerges = steps.retryB.status == "saved",
		bothServersClothes = final ~= nil
			and final.data.wardrobe[SHIRT] == true
			and final.data.wardrobe.paintball_garb_set == true,
		releasedAtClose = steps.final.lockCleared,
		onlyClothingSaved = untouched,
	}
	local all = true
	for _, v in out.pass do
		all = all and v == true
	end
	out.ok = all
	return out
end

return Probe
