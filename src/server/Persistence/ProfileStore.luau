--!strict
-- ServerScriptService.Server.Persistence.ProfileStore
-- Session-locked DataStore profiles, ProfileStore-style (BUILD_PLAN D26, risk 24; spike S15). One
-- record per player: { data = ProfileSchema.Data, meta = { lock = { jobId, session, expires }?,
-- writes, updatedAt } }. Every write is an UpdateAsync whose transform checks the lock, so two
-- servers can never both hold a profile: a load waits while another session's lease is live, steals
-- it once the lease has expired (a crashed server), and a save that finds someone else's lock marks
-- the profile lost and writes nothing. Calls retry with exponential backoff; the lease is renewed by
-- every save, and step() autosaves on a period well inside the lease.
-- Pure apart from the injected store, clock and sleep, so Lune drives it with MockDataStore and a
-- fake clock; the engine passes DataStoreService:GetDataStore(...), os.time and task.wait.
-- Interface: new(store, opts) -> Store; Store:load(key) -> (Profile?, status, detail?);
--            Store.readOnly(key) -> Profile; Profile:markDirty() -> revision; Profile:save() -> (ok, err?);
--            Profile:release() -> (ok, err?); Profile:step(now) (autosave + lease renewal);
--            Profile:isActive() -> boolean

local ProfileSchema = require("./ProfileSchema")

export type DataStoreLike = {
	UpdateAsync: (self: any, key: string, transform: (any, any) -> any) -> (any, any),
}

export type Options = {
	jobId: string,
	now: () -> number, -- a wall clock shared by every server (os.time in the engine), seconds
	sleep: (seconds: number) -> (),
	leaseSeconds: number?, -- a lock older than this without renewal is treated as a crashed server's
	autosaveSeconds: number?, -- step() saves (and renews the lease) this often
	retries: number?, -- retries per DataStore call on an error (throttle, 5xx)
	backoffSeconds: number?, -- first retry delay, doubled per retry
	lockWaits: number?, -- how many times load() waits on another live session before giving up
	lockWaitSeconds: number?,
	newSessionId: (() -> string)?,
}

export type Status = "ok" | "stolen" | "locked" | "corrupt" | "error"

export type Profile = {
	key: string,
	data: ProfileSchema.Data,
	session: string,
	readOnly: boolean,
	active: boolean, -- holds the lock; false after release, loss, or for a read-only profile
	lost: boolean, -- another session took the lock (our lease lapsed); never save again
	revision: number, -- bumped by markDirty()
	savedRevision: number, -- the highest revision known to be durable
	lastSaveAt: number,
	saves: number,
	owner: Store,
	markDirty: (self: Profile) -> number,
	save: (self: Profile) -> (boolean, string?),
	release: (self: Profile) -> (boolean, string?),
	step: (self: Profile, now: number) -> (),
	isActive: (self: Profile) -> boolean,
}

export type Store = {
	store: DataStoreLike,
	opts: Options,
	lease: number,
	autosave: number,
	retries: number,
	backoff: number,
	lockWaits: number,
	lockWait: number,
	counter: number,
	load: (self: Store, key: string) -> (Profile?, Status, string?),
}

local ProfileStore = {}

ProfileStore.DEFAULTS = {
	leaseSeconds = 180,
	autosaveSeconds = 30,
	retries = 4,
	backoffSeconds = 1,
	lockWaits = 4,
	lockWaitSeconds = 4,
}

-- pcall `fn` up to retries + 1 times with exponential backoff; returns (ok, lastError)
local function withRetries(self: Store, fn: () -> ()): (boolean, string?)
	local lastErr: string? = nil
	for attempt = 1, self.retries + 1 do
		local ok, err = pcall(fn :: any)
		if ok then
			return true, nil
		end
		lastErr = tostring(err)
		if attempt <= self.retries then
			self.opts.sleep(self.backoff * 2 ^ (attempt - 1))
		end
	end
	return false, lastErr
end

local function lockOf(record: any): any
	if type(record) == "table" and type(record.meta) == "table" then
		return record.meta.lock
	end
	return nil
end

local function writesOf(record: any): number
	if type(record) == "table" and type(record.meta) == "table" and type(record.meta.writes) == "number" then
		return record.meta.writes
	end
	return 0
end

-- One durable write of the profile's data; `keepLock` false clears the lock (release).
local function write(profile: Profile, keepLock: boolean): (boolean, string?)
	local self = profile.owner
	local rev = profile.revision
	local snapshot = ProfileSchema.deepCopy(profile.data)
	local outcome = "none"
	local ok, err = withRetries(self, function()
		self.store:UpdateAsync(profile.key, function(old: any, _info: any): any
			local lock = lockOf(old)
			if lock == nil or lock.session ~= profile.session then
				outcome = "lost"
				return nil
			end
			outcome = "written"
			local now = self.opts.now()
			return {
				data = snapshot,
				meta = {
					lock = if keepLock
						then { jobId = self.opts.jobId, session = profile.session, expires = now + self.lease }
						else nil,
					writes = writesOf(old) + 1,
					updatedAt = now,
				},
			}
		end)
	end)
	if outcome == "lost" then
		profile.active = false
		profile.lost = true
		return false, "lost"
	end
	if not ok then
		return false, err
	end
	profile.savedRevision = math.max(profile.savedRevision, rev)
	profile.lastSaveAt = self.opts.now()
	profile.saves += 1
	return true, nil
end

local ProfileMethods = {}

function ProfileMethods.markDirty(self: Profile): number
	self.revision += 1
	return self.revision
end

function ProfileMethods.save(self: Profile): (boolean, string?)
	if not self.active then
		return false, if self.lost then "lost" elseif self.readOnly then "read-only" else "released"
	end
	return write(self, true)
end

function ProfileMethods.release(self: Profile): (boolean, string?)
	if not self.active then
		return false, "inactive"
	end
	local ok, err = write(self, false)
	self.active = false
	return ok, err
end

function ProfileMethods.step(self: Profile, now: number)
	if self.active and now - self.lastSaveAt >= self.owner.autosave then
		write(self, true)
	end
end

function ProfileMethods.isActive(self: Profile): boolean
	return self.active and not self.lost and not self.readOnly
end

local function newProfile(owner: Store, key: string, data: ProfileSchema.Data, session: string): Profile
	return {
		key = key,
		data = data,
		session = session,
		readOnly = false,
		active = true,
		lost = false,
		revision = 0,
		savedRevision = 0,
		lastSaveAt = owner.opts.now(),
		saves = 0,
		owner = owner,
		markDirty = ProfileMethods.markDirty,
		save = ProfileMethods.save,
		release = ProfileMethods.release,
		step = ProfileMethods.step,
		isActive = ProfileMethods.isActive,
	}
end

local function load(self: Store, key: string): (Profile?, Status, string?)
	self.counter += 1
	local session = if self.opts.newSessionId
		then self.opts.newSessionId()
		else `{self.opts.jobId}:{self.counter}:{math.floor(self.opts.now() * 1000)}`
	for wait = 0, self.lockWaits do
		local outcome: Status = "error"
		local loaded: ProfileSchema.Data? = nil
		local detail: string? = nil
		local ok, err = withRetries(self, function()
			self.store:UpdateAsync(key, function(old: any, _info: any): any
				local now = self.opts.now()
				local lock = lockOf(old)
				if
					lock ~= nil
					and lock.session ~= session
					and type(lock.expires) == "number"
					and lock.expires > now
				then
					outcome = "locked"
					detail = tostring(lock.jobId)
					return nil
				end
				local data, merr = ProfileSchema.migrate(if type(old) == "table" then old.data else nil)
				if data == nil then
					outcome = "corrupt"
					detail = merr
					return nil
				end
				outcome = if lock ~= nil and lock.session ~= session then "stolen" else "ok"
				detail = if outcome == "stolen" then tostring(lock.jobId) else nil
				loaded = data
				return {
					data = data,
					meta = {
						lock = { jobId = self.opts.jobId, session = session, expires = now + self.lease },
						writes = writesOf(old) + 1,
						updatedAt = now,
					},
				}
			end)
		end)
		if not ok then
			return nil, "error", err
		end
		if outcome == "locked" then
			if wait < self.lockWaits then
				self.opts.sleep(self.lockWait)
				continue
			end
			return nil, "locked", detail
		end
		if outcome == "corrupt" or loaded == nil then
			return nil, outcome, detail
		end
		return newProfile(self, key, loaded :: ProfileSchema.Data, session), outcome, detail
	end
	return nil, "error", "unreachable"
end

function ProfileStore.new(store: DataStoreLike, opts: Options): Store
	local d = ProfileStore.DEFAULTS
	return {
		store = store,
		opts = opts,
		lease = opts.leaseSeconds or d.leaseSeconds,
		autosave = opts.autosaveSeconds or d.autosaveSeconds,
		retries = opts.retries or d.retries,
		backoff = opts.backoffSeconds or d.backoffSeconds,
		lockWaits = opts.lockWaits or d.lockWaits,
		lockWait = opts.lockWaitSeconds or d.lockWaitSeconds,
		counter = 0,
		load = load,
	}
end

-- A session whose profile could not be loaded (D14/D26 fallback): gameplay works, nothing is saved,
-- no Robux purchase is granted (ProcessReceipt answers NotProcessedYet and Roblox retries later).
function ProfileStore.readOnly(store: Store, key: string): Profile
	local profile = newProfile(store, key, ProfileSchema.template(), "read-only")
	profile.readOnly = true
	profile.active = false
	return profile
end

return ProfileStore
