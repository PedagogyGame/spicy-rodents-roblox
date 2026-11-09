--!strict
-- ServerScriptService.Server.Persistence.Profiles
-- The per-player profile facade (BUILD_PLAN §1.4 Telemetry/Profiles row, §3.20, D26; §4.4 #6b): keys a
-- player by UserId ("p_<id>"), loads through ProfileStore (spike S15: session locking, retries, the
-- read-only fallback) over any DataStoreLike: W1 uses the in-memory MemoryStore (Serializer strings);
-- W4 #11 passes DataStoreService:GetDataStore(...). Saves only through ProfileStore, so the lock and
-- lease rules hold in both. No side effects on require.
-- Interface: new(opts) -> Profiles; P:load(player) -> (Data, status); P:data(player) -> Data?;
--            P:save(player) -> (ok, err?); P:locked(player) -> boolean (read-only session);
--            P:release(player) -> (ok, err?); P:step(now); P:releaseAll() (BindToClose)

local MemoryStore = require("./MemoryStore")
local ProfileSchema = require("./ProfileSchema")
local ProfileStore = require("./ProfileStore")

export type Options = {
	store: ProfileStore.DataStoreLike?, -- default: a fresh MemoryStore
	jobId: string?,
	now: (() -> number)?,
	sleep: ((seconds: number) -> ())?,
	leaseSeconds: number?,
	autosaveSeconds: number?,
}

export type Profiles = {
	profiles: ProfileStore.Store,
	loaded: { [number]: ProfileStore.Profile },
	load: (self: Profiles, player: any) -> (ProfileSchema.Data, ProfileStore.Status),
	data: (self: Profiles, player: any) -> ProfileSchema.Data?,
	save: (self: Profiles, player: any) -> (boolean, string?),
	locked: (self: Profiles, player: any) -> boolean,
	release: (self: Profiles, player: any) -> (boolean, string?),
	step: (self: Profiles, now: number) -> (),
	releaseAll: (self: Profiles) -> (),
}

local Profiles = {}

function Profiles.key(userId: number): string
	return `p_{userId}`
end

function Profiles.new(opts: Options?): Profiles
	local o = opts or {}
	local profiles = ProfileStore.new(o.store or MemoryStore.new() :: any, {
		jobId = o.jobId or "lune",
		now = o.now or os.time,
		sleep = o.sleep or function(_s: number) end,
		leaseSeconds = o.leaseSeconds,
		autosaveSeconds = o.autosaveSeconds,
	})
	local p = { profiles = profiles, loaded = {} } :: Profiles

	-- Always returns usable data: on a locked, corrupt or failing record the session is read-only
	-- (gameplay works, nothing is saved, no purchase is granted).
	function p.load(self: Profiles, player: any): (ProfileSchema.Data, ProfileStore.Status)
		local id = player.UserId :: number
		local existing = self.loaded[id]
		if existing then
			return existing.data, "ok"
		end
		local key = Profiles.key(id)
		local profile, status = self.profiles:load(key)
		if not profile then
			profile = ProfileStore.readOnly(self.profiles, key)
		end
		self.loaded[id] = profile :: ProfileStore.Profile
		return (profile :: ProfileStore.Profile).data, status
	end

	function p.data(self: Profiles, player: any): ProfileSchema.Data?
		local profile = self.loaded[player.UserId]
		return if profile then profile.data else nil
	end

	function p.save(self: Profiles, player: any): (boolean, string?)
		local profile = self.loaded[player.UserId]
		if not profile then
			return false, "not loaded"
		end
		if profile.readOnly then
			return false, "read-only"
		end
		profile:markDirty()
		return profile:save()
	end

	function p.locked(self: Profiles, player: any): boolean
		local profile = self.loaded[player.UserId]
		return profile ~= nil and (profile.readOnly or not profile:isActive())
	end

	function p.release(self: Profiles, player: any): (boolean, string?)
		local profile = self.loaded[player.UserId]
		if not profile then
			return true
		end
		self.loaded[player.UserId] = nil
		if profile.readOnly then
			return true
		end
		profile:markDirty()
		return profile:release()
	end

	function p.step(self: Profiles, now: number)
		for _, profile in self.loaded do
			if not profile.readOnly then
				profile:step(now)
			end
		end
	end

	function p.releaseAll(self: Profiles)
		local ids: { number } = {}
		for id in self.loaded do
			table.insert(ids, id)
		end
		for _, id in ids do
			self:release({ UserId = id })
		end
	end

	return p
end

return Profiles
