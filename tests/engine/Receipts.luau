--!strict
-- ServerStorage.EngineTests.Receipts (CI place only; ci.project.json)
-- Spike S15 (BUILD_PLAN §4.3, D26): does DataStoreService work inside Open Cloud Luau Execution? A
-- GetDataStore + UpdateAsync + GetAsync on a test key in the "ci-" namespace; if it does, the real
-- ProfileStore and the receipt handler run against it: one profile loaded by simulated server A,
-- a receipt delivered twice (credited once, durable before the grant), simulated server B refused
-- while A holds the lock, then B loads after A releases and sees the balance. Returns JSON.
-- Writes only keys under the "ci-s15-" DataStore; nothing touches a production store.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

local server = ServerScriptService:WaitForChild("Server")
local ProfileStore = (require :: any)(server:WaitForChild("Persistence"):WaitForChild("ProfileStore"))
local Receipts = (require :: any)(server:WaitForChild("Economy"):WaitForChild("Receipts"))
local Products = (require :: any)(
	game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Economy"):WaitForChild("Products")
)

local Probe = {}

local function timed(fn: () -> any): (boolean, any, number)
	local t0 = os.clock()
	local ok, v = pcall(fn)
	return ok, v, (os.clock() - t0) * 1000
end

function Probe.run(): { [string]: any }
	local out: { [string]: any } = { suite = "Receipts", placeId = game.PlaceId, placeVersion = game.PlaceVersion }
	local okStore, store, getMs = timed(function()
		return DataStoreService:GetDataStore("ci-s15-probe")
	end)
	out.getDataStore = { ok = okStore, ms = getMs, err = if okStore then nil else tostring(store) }
	if not okStore then
		out.ok = false
		out.dataStoreAvailable = false
		return out
	end
	local budget = {}
	for _, kind in { Enum.DataStoreRequestType.GetAsync, Enum.DataStoreRequestType.UpdateAsync } do
		local okB, v = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(kind)
		end)
		budget[kind.Name] = if okB then v else tostring(v)
	end
	out.budget = budget
	local okUpd, value, updMs = timed(function()
		return store:UpdateAsync("probe", function(old: any)
			local n = if type(old) == "table" and type(old.n) == "number" then old.n else 0
			return { n = n + 1, at = os.time() }
		end)
	end)
	out.updateAsync =
		{ ok = okUpd, ms = updMs, value = if okUpd then value else nil, err = if okUpd then nil else tostring(value) }
	local okGet, got, readMs = timed(function()
		return store:GetAsync("probe")
	end)
	out.getAsync =
		{ ok = okGet, ms = readMs, value = if okGet then got else nil, err = if okGet then nil else tostring(got) }
	out.dataStoreAvailable = okUpd and okGet
	if not out.dataStoreAvailable then
		out.ok = false
		return out
	end

	-- the real ProfileStore and receipt handler on a fresh key
	local key = `ci-s15-u1-{HttpService:GenerateGUID(false)}`
	local tiers = Products.defaults()
	tiers[1].productId = 1
	local catalog = Products.catalog(tiers)
	local function newServer(jobId: string)
		local ps = ProfileStore.new(store, {
			jobId = jobId,
			now = os.time,
			sleep = function(s: number)
				task.wait(s)
			end,
			leaseSeconds = 60,
			lockWaits = 1,
			lockWaitSeconds = 1,
			retries = 2,
		})
		local profiles = {}
		local handler = Receipts.new({
			profileOf = function(id: number)
				return profiles[id]
			end,
			catalog = catalog,
			now = os.time,
		})
		return { ps = ps, profiles = profiles, handler = handler }
	end
	local a, b = newServer("ci-A"), newServer("ci-B")
	local steps: { [string]: any } = { key = key }
	local okA, pa, loadMs = timed(function()
		return a.ps:load(key)
	end)
	steps.loadA = { ok = okA and pa ~= nil, ms = loadMs }
	a.profiles[1] = pa
	local r = { PurchaseId = "ci-receipt-1", PlayerId = 1, ProductId = 1 }
	local _, d1, grantMs = timed(function()
		return a.handler:process(r)
	end)
	local _, d2, dupMs = timed(function()
		return a.handler:process(r)
	end)
	steps.receipt = { first = d1, second = d2, grantMs = grantMs, duplicateMs = dupMs, stats = a.handler.stats }
	local okB, pbOrErr, statusB = pcall(function()
		return b.ps:load(key)
	end)
	steps.loadBWhileHeld = { ok = okB, gotProfile = okB and pbOrErr ~= nil, status = statusB }
	local _, released, relMs = timed(function()
		return pa:release()
	end)
	steps.releaseA = { ok = released, ms = relMs }
	local _, pb2, load2Ms = timed(function()
		return b.ps:load(key)
	end)
	steps.loadBAfterRelease = { ok = pb2 ~= nil, ms = load2Ms, cents = if pb2 then pb2.data.wallet.cents else nil }
	if pb2 then
		pb2:release()
	end
	local stored = store:GetAsync(key)
	steps.stored = {
		cents = stored and stored.data.wallet.cents,
		receipts = stored and #stored.data.receipts.ids,
		lockCleared = stored ~= nil and stored.meta.lock == nil,
		writes = stored and stored.meta.writes,
	}
	pcall(function()
		store:RemoveAsync(key)
	end)
	out.profile = steps
	out.pass = {
		grantedOnce = d1 == "PurchaseGranted" and d2 == "PurchaseGranted" and a.handler.stats.credited == 1,
		lockExcludesSecondServer = okB and pbOrErr == nil and statusB == "locked",
		balanceMovesAfterRelease = steps.loadBAfterRelease.cents == 10000,
		storedOnce = steps.stored.cents == 10000 and steps.stored.receipts == 1 and steps.stored.lockCleared,
	}
	out.ok = out.pass.grantedOnce
		and out.pass.lockExcludesSecondServer
		and out.pass.balanceMovesAfterRelease
		and out.pass.storedOnce
	return out
end

return Probe
