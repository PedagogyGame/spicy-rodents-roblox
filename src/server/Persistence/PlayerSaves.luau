--!strict
-- ServerScriptService.Server.Persistence.PlayerSaves
-- The live server's saved profiles: one session-locked profile per player (Persistence/ProfileStore over the
-- engine's DataStore, key Profiles.key(userId) in the store named STORE), loaded when the player joins, saved
-- when something in it changes, on a period while they play, and released when they leave or the server shuts
-- down (BindToClose: closeAll). What goes into the profile is the caller's (Boot/Game hands it Cosmetics/Wardrobe,
-- which writes only the clothing: owner D16 #25); this module only keeps the profile and its lock honest.
-- A player's session is in one of these states (status(player); Boot/Game shows it as the player attribute
-- ClothesSaved):
--   loading   the profile is on its way (play goes on meanwhile; nothing waits on it)
--   saved     the profile is held: a change is written at once (and retried), the rest on the autosave period
--   unsaved   the load failed (DataStore errors, or another server still holds a live lock past the waits): the
--             player is told once, play goes on, and the load is retried with backoff (RETRY_FIRST doubling to
--             RETRY_MAX) for as long as they stay; when it lands, `loaded` merges what changed here meanwhile
--   lost      another server took the lock (ours lapsed): nothing is written again by this server; told once
--   corrupt   the record could not be read (a newer schema than this build, or broken): never written over;
--             told once
--   off       saving is off on this server (no DataStore: Studio without "Enable Studio Access to API
--             Services", or an unpublished place); said once in the log, and to a player when it matters
-- A save that fails after ProfileStore's own retries is tried again every SAVE_RETRY seconds; the player is told
-- once that saving is slow and once more when it has caught up. Nothing a player has is taken away by a failure:
-- the live state is the caller's, on this server, whatever the store does.
-- Every DataStore call runs in its own thread (deps.spawn: task.spawn in the engine) through one queue per
-- player, so two writes for the same key never overlap, a rejoin's load waits for the leave's release, and a
-- frame never waits on a DataStore. In Lune deps.spawn runs the job at once, so specs are synchronous.
-- Interface: new(deps) -> Saves; Saves:join(player); Saves:leave(player); Saves:dirty(player);
--   Saves:data(player) -> ProfileSchema.Data? (only while `saved`); Saves:status(player) -> State?;
--   Saves:step(now); Saves:closeAll(timeoutSeconds?) (yields until every release is done or the time is up);
--   Saves:busy() -> boolean; STORE; WORDS; offError(err) -> boolean (pure)
-- No engine but what deps hands in; no side effects on require.

local ProfileSchema = require("./ProfileSchema")
local ProfileStore = require("./ProfileStore")

export type State = "loading" | "saved" | "unsaved" | "lost" | "corrupt" | "off"

export type Deps = {
	store: ProfileStore.DataStoreLike?, -- nil: saving is off
	jobId: string,
	now: () -> number, -- a wall clock every server shares (os.time)
	sleep: (seconds: number) -> (),
	spawn: (fn: () -> ()) -> (), -- runs a job off the caller's thread (task.spawn)
	tell: (player: any, words: string) -> (),
	-- the profile arrived: merge what this server already has for the player into `data`; true if it changed
	-- `data` (then it is saved at once)
	loaded: (player: any, data: ProfileSchema.Data) -> boolean,
	changed: ((player: any, state: State) -> ())?, -- the session's state moved (Boot/Game: an attribute)
	log: ((line: string) -> ())?,
	warn: ((line: string) -> ())?,
	-- ProfileStore's options (its DEFAULTS when nil)
	leaseSeconds: number?,
	autosaveSeconds: number?,
	retries: number?,
	backoffSeconds: number?,
	lockWaits: number?,
	lockWaitSeconds: number?,
}

type Session = {
	player: any,
	id: number,
	state: State,
	profile: ProfileStore.Profile?,
	left: boolean,
	loadQueued: boolean,
	saveQueued: boolean,
	failing: boolean, -- a save failed and has not caught up (the player was told)
	nextSaveAt: number,
	nextLoadAt: number,
	loadDelay: number,
	told: { [string]: boolean? },
}

type Queue = { jobs: { () -> () }, running: boolean }

export type Saves = {
	deps: Deps,
	profiles: ProfileStore.Store?,
	sessions: { [number]: Session },
	queues: { [number]: Queue },
	join: (self: Saves, player: any) -> (),
	leave: (self: Saves, player: any) -> (),
	dirty: (self: Saves, player: any) -> (),
	data: (self: Saves, player: any) -> ProfileSchema.Data?,
	status: (self: Saves, player: any) -> State?,
	step: (self: Saves, now: number) -> (),
	closeAll: (self: Saves, timeoutSeconds: number?) -> (),
	busy: (self: Saves) -> boolean,
}

local PlayerSaves = {}

PlayerSaves.STORE = "Profiles" -- the DataStore's name (keys "p_<userId>": Persistence/Profiles.key)
PlayerSaves.RETRY_FIRST = 15 -- seconds before a failed load is tried again (doubled each time)
PlayerSaves.RETRY_MAX = 240
PlayerSaves.SAVE_RETRY = 30 -- seconds between tries of a save that failed
PlayerSaves.CLOSE_SECONDS = 25 -- BindToClose: Roblox gives a closing server 30 s

PlayerSaves.WORDS = table.freeze({
	unsaved = "Your saved clothes have not loaded yet. Play on: we keep trying, and nothing you buy is lost.",
	back = "Your saved clothes are back.",
	slow = "Saving your clothes is slow right now. Play on: we keep trying, and nothing you have is lost.",
	caughtUp = "Your clothes are saved.",
	lost = "Your clothes were opened on another server, so changes made here stay on this server.",
	corrupt = "Your saved clothes could not be read on this server. They are left as they were.",
})

-- An error that means this server can never reach the DataStore (Studio without API access, an unpublished place):
-- no point retrying.
function PlayerSaves.offError(err: any): boolean
	local s = string.lower(tostring(err))
	return string.find(s, "studioaccesstoapisnotallowed", 1, true) ~= nil
		or string.find(s, "studio access to api", 1, true) ~= nil
		or string.find(s, "publish this place", 1, true) ~= nil
end

local function keyOf(player: any): number
	return player.UserId :: number
end

local function profileKey(id: number): string
	return `p_{id}` -- (Persistence/Profiles.key)
end

local function setState(self: Saves, s: Session, state: State)
	if s.state == state then
		return
	end
	s.state = state
	if self.deps.changed and not s.left then
		self.deps.changed(s.player, state)
	end
end

local function tellOnce(self: Saves, s: Session, what: string)
	if s.told[what] or s.left then
		return
	end
	s.told[what] = true
	self.deps.tell(s.player, (PlayerSaves.WORDS :: any)[what])
end

local function say(self: Saves, line: string)
	local log = self.deps.log
	if log then
		log(`[PlayerSaves] {line}`)
	else
		print(`[PlayerSaves] {line}`)
	end
end

local function shout(self: Saves, line: string)
	local w = self.deps.warn
	if w then
		w(`[PlayerSaves] {line}`)
	else
		warn(`[PlayerSaves] {line}`)
	end
end

-- one queue per player: jobs run one after another on a spawned thread
local function enqueue(self: Saves, id: number, job: () -> ())
	local q = self.queues[id]
	if q == nil then
		q = { jobs = {}, running = false }
		self.queues[id] = q
	end
	local queue = q :: Queue
	table.insert(queue.jobs, job)
	if queue.running then
		return
	end
	queue.running = true
	self.deps.spawn(function()
		while #queue.jobs > 0 do
			local nextJob = table.remove(queue.jobs, 1) :: () -> ()
			local ok, err = pcall(function()
				nextJob()
			end)
			if not ok then
				shout(self, `a job for {id} failed: {err}`)
			end
		end
		queue.running = false
		if self.queues[id] == queue then
			self.queues[id] = nil
		end
	end)
end

local function saveJob(self: Saves, s: Session)
	s.saveQueued = false
	local profile = s.profile
	if s.state ~= "saved" or profile == nil or s.left then
		return
	end
	local ok, err = profile:save()
	local now = self.deps.now()
	if ok then
		if s.failing then
			s.failing = false
			s.told.slow = nil
			tellOnce(self, s, "caughtUp")
			s.told.caughtUp = nil
		end
		return
	end
	if err == "lost" then
		setState(self, s, "lost")
		shout(self, `{s.id}: the lock was taken by another server; nothing more is written here`)
		tellOnce(self, s, "lost")
		return
	end
	s.failing = true
	s.nextSaveAt = now + PlayerSaves.SAVE_RETRY
	shout(self, `{s.id}: save failed ({err}); trying again in {PlayerSaves.SAVE_RETRY} s`)
	tellOnce(self, s, "slow")
end

local function queueSave(self: Saves, s: Session)
	if s.saveQueued or s.state ~= "saved" then
		return
	end
	s.saveQueued = true
	enqueue(self, s.id, function()
		saveJob(self, s)
	end)
end

local function loadJob(self: Saves, s: Session)
	s.loadQueued = false
	if s.left or (s.state ~= "loading" and s.state ~= "unsaved") then
		return
	end
	local store = self.profiles :: ProfileStore.Store
	local retry = s.state == "unsaved"
	local profile, status, detail = store:load(profileKey(s.id))
	if profile == nil then
		if status == "corrupt" then
			setState(self, s, "corrupt")
			shout(self, `{s.id}: the saved record could not be read ({detail}); it is left as it is`)
			tellOnce(self, s, "corrupt")
			return
		end
		if status == "error" and PlayerSaves.offError(detail) then
			setState(self, s, "off")
			shout(self, `saving is off on this server: {detail}`)
			return
		end
		setState(self, s, "unsaved")
		s.nextLoadAt = self.deps.now() + s.loadDelay
		shout(self, `{s.id}: the profile did not load ({status}: {detail}); trying again in {s.loadDelay} s`)
		s.loadDelay = math.min(s.loadDelay * 2, PlayerSaves.RETRY_MAX)
		tellOnce(self, s, "unsaved")
		return
	end
	local p = profile :: ProfileStore.Profile
	if s.left then
		p:release() -- they went while it loaded: hand the lock straight back
		return
	end
	s.profile = p
	if status == "stolen" then
		say(self, `{s.id}: took over a lapsed lock from {detail}`)
	end
	setState(self, s, "saved")
	local changed = self.deps.loaded(s.player, p.data)
	if retry then
		tellOnce(self, s, "back")
	end
	if changed then
		p:markDirty()
		queueSave(self, s)
	end
end

local function queueLoad(self: Saves, s: Session)
	if s.loadQueued then
		return
	end
	s.loadQueued = true
	enqueue(self, s.id, function()
		loadJob(self, s)
	end)
end

local function releaseJob(self: Saves, s: Session)
	local profile = s.profile
	if profile and s.state == "saved" then
		profile:markDirty()
		local ok, err = profile:release()
		if not ok then
			shout(self, `{s.id}: release failed ({err}); the lock lapses in its lease`)
		end
	end
	s.profile = nil
end

function PlayerSaves.new(deps: Deps): Saves
	local self = {
		deps = deps,
		profiles = if deps.store
			then ProfileStore.new(deps.store, {
				jobId = deps.jobId,
				now = deps.now,
				sleep = deps.sleep,
				leaseSeconds = deps.leaseSeconds,
				autosaveSeconds = deps.autosaveSeconds,
				retries = deps.retries,
				backoffSeconds = deps.backoffSeconds,
				lockWaits = deps.lockWaits,
				lockWaitSeconds = deps.lockWaitSeconds,
			})
			else nil,
		sessions = {},
		queues = {},
	} :: Saves
	if deps.store == nil then
		shout(
			self,
			"saving is off on this server (no DataStore: in Studio, Game Settings > Security > Enable Studio Access to API Services)"
		)
	end

	function self.join(me: Saves, player: any)
		local id = keyOf(player)
		local old = me.sessions[id]
		if old and not old.left then
			return
		end
		local s: Session = {
			player = player,
			id = id,
			state = if me.profiles then "loading" else "off",
			profile = nil,
			left = false,
			loadQueued = false,
			saveQueued = false,
			failing = false,
			nextSaveAt = 0,
			nextLoadAt = 0,
			loadDelay = PlayerSaves.RETRY_FIRST,
			told = {},
		}
		me.sessions[id] = s
		if me.deps.changed then
			me.deps.changed(player, s.state)
		end
		if me.profiles then
			queueLoad(me, s)
		end
	end

	function self.leave(me: Saves, player: any)
		local id = keyOf(player)
		local s = me.sessions[id]
		if s == nil or s.left then
			return
		end
		s.left = true
		me.sessions[id] = nil
		enqueue(me, id, function()
			releaseJob(me, s)
		end)
	end

	function self.dirty(me: Saves, player: any)
		local s = me.sessions[keyOf(player)]
		if s and s.state == "saved" and s.profile then
			(s.profile :: ProfileStore.Profile):markDirty()
			queueSave(me, s)
		end
	end

	function self.data(me: Saves, player: any): ProfileSchema.Data?
		local s = me.sessions[keyOf(player)]
		if s and s.state == "saved" and s.profile then
			return (s.profile :: ProfileStore.Profile).data
		end
		return nil
	end

	function self.status(me: Saves, player: any): State?
		local s = me.sessions[keyOf(player)]
		return if s then s.state else nil
	end

	function self.step(me: Saves, now: number)
		local autosave = if me.profiles then me.profiles.autosave else math.huge
		for _, s in me.sessions do
			if s.state == "saved" and s.profile then
				local p = s.profile :: ProfileStore.Profile
				if s.failing then
					if now >= s.nextSaveAt then
						queueSave(me, s)
					end
				elseif now - p.lastSaveAt >= autosave then
					queueSave(me, s) -- (renews the lease too)
				end
			elseif s.state == "unsaved" and now >= s.nextLoadAt then
				queueLoad(me, s)
			end
		end
	end

	function self.busy(me: Saves): boolean
		return next(me.queues) ~= nil
	end

	function self.closeAll(me: Saves, timeoutSeconds: number?)
		local players = {}
		for _, s in me.sessions do
			table.insert(players, s.player)
		end
		for _, player in players do
			me:leave(player)
		end
		local limit = timeoutSeconds or PlayerSaves.CLOSE_SECONDS
		local waited = 0
		while me:busy() and waited < limit do
			me.deps.sleep(0.25)
			waited += 0.25
		end
		if me:busy() then
			shout(me, `closing with saves still running after {limit} s`)
		end
	end

	return self
end

return PlayerSaves
