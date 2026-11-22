--!strict
-- ServerScriptService.Server.Persistence.PlayerSaves
-- The live server's saved profiles: one session-locked profile per player (Persistence/ProfileStore over the
-- engine's DataStore, key Profiles.key(userId) in the store named STORE), loaded when the player joins, saved
-- a few seconds after something in it changes, on a period while they play, and released when they leave or the
-- server shuts down (BindToClose: closeAll). What goes into the profile is the caller's (Boot/Game hands it
-- Cosmetics/Wardrobe, which writes only the clothing: owner D16 #25); this module only keeps the profile, its lock
-- and the server's DataStore budget honest.
-- MONEY AND RECEIPTS: when they are saved, they go into the profile this module holds (data(player), dirty), never
-- through Persistence/Profiles.new or Economy/Receipts' own ProfileStore: those would take a second session lock
-- on the same key from the same server, and the two would lock each other out. Real money (Economy/StockOptions:
-- a Robux receipt, a withdrawal) does not wait for step(): saveNow(player, opts?) puts one write in that player's
-- queue at once and yields until it is done, for at most SAVE_NOW_WAIT seconds; true only when a write holding every
-- change made before the call has landed. It takes a token from the bucket: a withdrawal only takes one that is
-- there (else (false, "budget") at once, nothing queued); a receipt (opts.receipt: Robux already paid) may take the
-- bucket down to -DEBT and waits (within SAVE_NOW_WAIT) for it to refill past that, so real money can never starve
-- the autosaves for long. (false, "slow") means the write is still queued or running and may yet land:
-- opts.settle(ok, why) is then called from the player's queue once it is done (before any later job of theirs,
-- their leave's release included), so a caller that must not guess (Economy/StockOptions' withdrawal) can wait.
-- A player's session is in one of these states (status(player); Boot/Game shows it as the player attribute
-- ClothesSaved):
--   loading   the profile is on its way (play goes on meanwhile; nothing waits on it)
--   saved     the profile is held: a change marks it dirty and step() writes it (see WRITES below)
--   unsaved   the load failed (DataStore errors, or another server still holds a live lock past the waits): the
--             player is told once, play goes on, and the load is retried with backoff (RETRY_FIRST doubling to
--             RETRY_MAX) for as long as they stay; when it lands, `loaded` merges what changed here meanwhile
--   lost      another server took the lock (ours lapsed): nothing is written again by this server; told once
--   corrupt   the record could not be read (a newer schema than this build, or not a profile at all): never
--             written over; play goes on unsaved; told once
--   off       saving is off on this server (no DataStore: Studio without "Enable Studio Access to API
--             Services", or an unpublished place); said once in the log, and to a player when it matters
-- WRITES (the DataStore's per-server allowance is 60 + 10 x players UpdateAsync a minute, 360 with 30 players):
--   * a change (dirty) only marks the profile; step() (1 Hz) writes a dirty profile once its last write is
--     WRITE_GAP (6 s) old, so one player costs at most 10 writes a minute whatever their client does;
--   * a purchase (dirty(player, true)) is written at once if that player's gap and the budget allow, else by step;
--   * the autosave writes a clean profile every 30 s (it renews the 180 s lease);
--   * every one of those takes a token from a server-wide bucket refilled at BUDGET_SHARE (half) of the
--     allowance, 30 + 5 x players a minute (180 with 30 players; at most BURST saved up), the stalest profile
--     first; loads (one per join) and releases (one per leave) take none and have the other half.
-- One session id per player per server ("<jobId>:<userId>") is used by every load, retry and release, so a load
-- whose reply was lost (the lock written, the answer gone) is taken back by the next try at once, and a leave
-- clears such an orphan lock. A player who leaves before their profile loaded, with something bought or changed
-- here, gets one last look: if the lock is free, the profile is loaded, merged and released (else it stays here).
-- A save that fails after ProfileStore's own retries is tried again every SAVE_RETRY seconds; the player is told
-- once that saving is slow and once more when it has caught up. Nothing a player has is taken away by a failure:
-- the live state is the caller's, on this server, whatever the store does.
-- Every DataStore call runs in its own thread (deps.spawn: task.spawn in the engine) through one queue per
-- player, so two writes for the same key never overlap, a rejoin's load waits for the leave's release, and a
-- frame never waits on a DataStore. In Lune deps.spawn runs the job at once, so specs are synchronous.
-- Shutdown (closeAll): every session is left, so queued loads and saves do nothing (each release writes the latest
-- data), and the store is told it is closing (one retry per call, no lock waits): the releases fit in CLOSE_SECONDS.
-- Interface: new(deps) -> Saves; Saves:join(player); Saves:leave(player); Saves:dirty(player, purchase?);
--   Saves:data(player) -> ProfileSchema.Data? (only while `saved`); Saves:profileOf(userId) -> Profile? (the same,
--   by UserId: Economy/Receipts); Saves:saveNow(player, opts?) -> (ok, err?) (yields; opts { receipt?, settle? }); Saves:status(player) -> State?;
--   Saves:step(now); Saves:closeAll(timeoutSeconds?) (yields until every release is done or the time is up);
--   Saves:busy() -> boolean; STORE; WORDS; WRITE_GAP; BUDGET_SHARE; BURST; DEBT; budgetPerMinute(players) (pure);
--   offError(err) -> boolean (pure)
-- No engine but what deps hands in; no side effects on require.

local ProfileSchema = require("./ProfileSchema")
local ProfileStore = require("./ProfileStore")

export type State = "loading" | "saved" | "unsaved" | "lost" | "corrupt" | "off"

export type Deps = {
	store: ProfileStore.DataStoreLike?, -- nil: saving is off
	jobId: string, -- unique per server (game.JobId; a fresh id per Studio session)
	now: () -> number, -- a wall clock every server shares (os.time)
	sleep: (seconds: number) -> (),
	spawn: (fn: () -> ()) -> (), -- runs a job off the caller's thread (task.spawn)
	tell: (player: any, words: string) -> (),
	-- the profile arrived: merge what this server already has for the player into `data`; true if it changed
	-- `data` (then it is written on the next step)
	loaded: (player: any, data: ProfileSchema.Data) -> boolean,
	-- something changed here that is not in a profile yet (a player who leaves unsaved gets one last look)
	pending: ((player: any) -> boolean)?,
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
	session: string, -- the lock's session id: one per player per server, kept across retries and rejoins
	state: State,
	profile: ProfileStore.Profile?,
	left: boolean,
	finished: boolean, -- the leave's work is done (released, or handed back when the load came in)
	loadQueued: boolean,
	saveQueued: boolean,
	mayHoldLock: boolean, -- a load failed ambiguously: our lock may be in the record
	failing: boolean, -- a save failed and has not caught up (the player was told)
	lastWriteAt: number, -- when the last write of this profile went out (the load included)
	nextSaveAt: number,
	nextLoadAt: number,
	loadDelay: number,
	told: { [string]: boolean? },
}

type Queue = { jobs: { () -> () }, running: boolean }

-- saveNow's options: `receipt` (a Robux purchase: may go into the bucket's bounded debt); `settle(ok, why)`, called
-- once a write that saveNow gave up waiting for ("slow") is done
export type SaveNowOpts = {
	receipt: boolean?,
	settle: ((ok: boolean, why: string?) -> ())?,
}

export type Saves = {
	deps: Deps,
	profiles: ProfileStore.Store?,
	sessions: { [number]: Session },
	queues: { [number]: Queue },
	closing: boolean,
	tokens: number,
	tokensAt: number,
	join: (self: Saves, player: any) -> (),
	leave: (self: Saves, player: any) -> (),
	dirty: (self: Saves, player: any, purchase: boolean?) -> (),
	data: (self: Saves, player: any) -> ProfileSchema.Data?,
	profileOf: (self: Saves, userId: number) -> ProfileStore.Profile?,
	saveNow: (self: Saves, player: any, opts: SaveNowOpts?) -> (boolean, string?),
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
PlayerSaves.WRITE_GAP = 6 -- seconds: at most one write of a player's profile this often (changes, purchases)
PlayerSaves.BUDGET_SHARE = 0.5 -- of the server's UpdateAsync allowance, for saves (loads and releases: the rest)
PlayerSaves.BURST = 10 -- saves the bucket can hold in hand
PlayerSaves.SAVE_NOW_WAIT = 20 -- seconds saveNow waits for its write before it answers (false, "slow")
PlayerSaves.DEBT = 5 -- tokens a receipt's saveNow may take the bucket below zero (nothing else goes into debt)

PlayerSaves.WORDS = table.freeze({
	unsaved = "Your saved clothes have not loaded yet. Play on: we keep trying, and nothing you buy is lost.",
	back = "Your saved clothes are back.",
	slow = "Saving your clothes is slow right now. Play on: we keep trying, and nothing you have is lost.",
	caughtUp = "Your clothes are saved.",
	lost = "Your clothes were opened on another server, so changes made here stay on this server.",
	corrupt = "Your saved clothes could not be read on this server. They are left as they were.",
})

-- The DataStore's UpdateAsync allowance for one server a minute, and the share of it saves may use.
function PlayerSaves.budgetPerMinute(players: number): (number, number)
	local allowance = 60 + 10 * players
	return allowance, allowance * PlayerSaves.BUDGET_SHARE
end

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

-- the server-wide bucket of saves: refilled at BUDGET_SHARE of 60 + 10 x players a minute, at most BURST in hand
local function refill(self: Saves, now: number)
	local players = 0
	for _ in self.sessions do
		players += 1
	end
	local _, perMinute = PlayerSaves.budgetPerMinute(players)
	local elapsed = math.max(0, now - self.tokensAt)
	self.tokens = math.min(PlayerSaves.BURST, self.tokens + elapsed * perMinute / 60)
	self.tokensAt = now
end

local function spend(self: Saves): boolean
	if self.tokens < 1 then
		return false
	end
	self.tokens -= 1
	return true
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

-- (the caller has taken a token from the bucket)
local function queueSave(self: Saves, s: Session, now: number)
	if s.saveQueued or s.state ~= "saved" then
		return
	end
	s.saveQueued = true
	s.lastWriteAt = now
	enqueue(self, s.id, function()
		saveJob(self, s)
	end)
end

-- Does this held profile want a write now? A failed save on its retry time; else, once its last write is WRITE_GAP
-- old, a dirty profile or one due its autosave.
local function wantsSave(self: Saves, s: Session, p: ProfileStore.Profile, now: number): boolean
	if s.saveQueued then
		return false
	end
	if s.failing then
		return now >= s.nextSaveAt
	end
	if now - s.lastWriteAt < PlayerSaves.WRITE_GAP then
		return false
	end
	local autosave = (self.profiles :: ProfileStore.Store).autosave
	return p.revision > p.savedRevision or now - p.lastSaveAt >= autosave
end

-- what was changed here merged into a profile that is about to be released (the player has left)
local function mergeLeft(self: Saves, s: Session, p: ProfileStore.Profile)
	local pending = self.deps.pending
	if pending and pending(s.player) then
		self.deps.loaded(s.player, p.data)
		p:markDirty()
	end
end

local function loadJob(self: Saves, s: Session)
	s.loadQueued = false
	if s.left or (s.state ~= "loading" and s.state ~= "unsaved") then
		return
	end
	local store = self.profiles :: ProfileStore.Store
	local retry = s.state == "unsaved"
	local profile, status, detail = store:load(profileKey(s.id), s.session)
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
		if status == "error" then
			s.mayHoldLock = true -- (a write may have landed before the error: our lock, which the next try takes back)
		end
		setState(self, s, "unsaved")
		s.nextLoadAt = self.deps.now() + s.loadDelay
		shout(self, `{s.id}: the profile did not load ({status}: {detail}); trying again in {s.loadDelay} s`)
		s.loadDelay = math.min(s.loadDelay * 2, PlayerSaves.RETRY_MAX)
		tellOnce(self, s, "unsaved")
		return
	end
	local p = profile :: ProfileStore.Profile
	s.mayHoldLock = false
	s.lastWriteAt = self.deps.now()
	if s.left then
		s.finished = true
		mergeLeft(self, s, p)
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
		p:markDirty() -- (written by step once the load's write is WRITE_GAP old)
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

-- the player left before their profile loaded: one last look if something here is not saved (no lock waits; a
-- free lock is taken, the change merged in and the lock handed back), else clear any orphan lock of ours
local function lastLook(self: Saves, s: Session)
	local store = self.profiles
	if store == nil then
		return
	end
	local key = profileKey(s.id)
	local pending = self.deps.pending
	if pending and pending(s.player) then
		local p, status = store:load(key, s.session, 0)
		if p then
			mergeLeft(self, s, p)
			local ok, err = p:release()
			say(self, `{s.id}: saved on the way out ({if ok then "released" else err})`)
			return
		end
		if status ~= "error" then
			return -- (locked by another server, or corrupt: nothing of ours is in the record)
		end
		s.mayHoldLock = true
	end
	if s.mayHoldLock then
		local ok, err = store:unlock(key, s.session)
		if not ok then
			shout(self, `{s.id}: could not clear an unanswered load's lock ({err}); it lapses in its lease`)
		end
	end
end

local function releaseJob(self: Saves, s: Session)
	if s.finished then
		return
	end
	s.finished = true
	local profile = s.profile
	if profile and s.state == "saved" then
		profile:markDirty()
		local ok, err = profile:release()
		if not ok then
			shout(self, `{s.id}: release failed ({err}); the lock lapses in its lease`)
		end
	elseif s.state == "loading" or s.state == "unsaved" then
		lastLook(self, s)
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
				fatal = PlayerSaves.offError, -- saving off: no retries, "off" at once
			})
			else nil,
		sessions = {},
		queues = {},
		closing = false,
		tokens = PlayerSaves.BURST,
		tokensAt = deps.now(),
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
		if (old and not old.left) or me.closing then
			return
		end
		local s: Session = {
			player = player,
			id = id,
			session = `{me.deps.jobId}:{id}`,
			state = if me.profiles then "loading" else "off",
			profile = nil,
			left = false,
			finished = false,
			loadQueued = false,
			saveQueued = false,
			mayHoldLock = false,
			failing = false,
			lastWriteAt = -math.huge,
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

	-- the profile changed: marked dirty, written by step within WRITE_GAP; a purchase goes at once when the
	-- player's gap and the server's budget allow
	function self.dirty(me: Saves, player: any, purchase: boolean?)
		local s = me.sessions[keyOf(player)]
		if s and s.state == "saved" and s.profile then
			local p = s.profile :: ProfileStore.Profile
			p:markDirty()
			if purchase and not me.closing then
				local now = me.deps.now()
				if wantsSave(me, s, p, now) then
					refill(me, now)
					if spend(me) then
						queueSave(me, s, now)
					end
				end
			end
		end
	end

	function self.data(me: Saves, player: any): ProfileSchema.Data?
		local s = me.sessions[keyOf(player)]
		if s and s.state == "saved" and s.profile then
			return (s.profile :: ProfileStore.Profile).data
		end
		return nil
	end

	function self.profileOf(me: Saves, userId: number): ProfileStore.Profile?
		local s = me.sessions[userId]
		if s and s.state == "saved" and s.profile then
			return s.profile
		end
		return nil
	end

	-- one write now, in the player's queue, and wait for it: true once every change made before the call is durable
	function self.saveNow(me: Saves, player: any, opts: SaveNowOpts?): (boolean, string?)
		local s = me.sessions[keyOf(player)]
		if s == nil or s.state ~= "saved" or s.profile == nil then
			return false, if s then s.state else "absent"
		end
		if me.closing then
			return false, "closing"
		end
		local receipt = opts ~= nil and opts.receipt == true
		local settle = if opts then opts.settle else nil
		-- a token: a withdrawal takes one that is there; a receipt may run the bucket down to -DEBT, and waits for
		-- it to refill past that
		local floor = if receipt then -PlayerSaves.DEBT else 0
		local waited = 0
		refill(me, me.deps.now())
		while me.tokens - 1 < floor do
			if not receipt or waited >= PlayerSaves.SAVE_NOW_WAIT then
				return false, "budget"
			end
			me.deps.sleep(0.5)
			waited += 0.5
			refill(me, me.deps.now())
			if s.left or me.closing or s.state ~= "saved" or s.profile == nil then
				return false, if me.closing then "closing" else s.state
			end
		end
		me.tokens -= 1
		local p = s.profile :: ProfileStore.Profile
		local want = p:markDirty()
		s.lastWriteAt = me.deps.now()
		local done, ok, why, gaveUp = false, false, nil :: string?, false
		enqueue(me, s.id, function()
			if p.savedRevision < want then
				if s.state == "saved" and s.profile == p and p:isActive() then
					local wrote, err = p:save()
					if not wrote and err == "lost" then
						setState(me, s, "lost")
						shout(me, `{s.id}: the lock was taken by another server; nothing more is written here`)
						tellOnce(me, s, "lost")
					elseif not wrote then
						shout(me, `{s.id}: an immediate save failed ({err})`)
					end
					why = err
				else
					why = s.state
				end
			end
			ok = p.savedRevision >= want
			done = true
			if gaveUp and settle then
				local late = if ok then nil else why or "failed"
				local called, err = pcall(function()
					settle(ok, late)
				end)
				if not called then
					shout(me, `{s.id}: settling a slow save failed: {err}`)
				end
			end
		end)
		waited = 0
		while not done and waited < PlayerSaves.SAVE_NOW_WAIT do
			me.deps.sleep(0.1)
			waited += 0.1
		end
		if not done then
			gaveUp = true
			return false, "slow"
		end
		return ok, if ok then nil else why or "failed"
	end

	function self.status(me: Saves, player: any): State?
		local s = me.sessions[keyOf(player)]
		return if s then s.state else nil
	end

	function self.step(me: Saves, now: number)
		if me.closing or me.profiles == nil then
			return
		end
		refill(me, now)
		local due: { Session } = {}
		for _, s in me.sessions do
			if s.state == "saved" and s.profile then
				if wantsSave(me, s, s.profile :: ProfileStore.Profile, now) then
					table.insert(due, s)
				end
			elseif s.state == "unsaved" and now >= s.nextLoadAt then
				queueLoad(me, s)
			end
		end
		-- the stalest profile first, while the bucket has tokens; the rest wait for the next step
		table.sort(due, function(a: Session, b: Session): boolean
			return a.lastWriteAt < b.lastWriteAt
		end)
		for _, s in due do
			if not spend(me) then
				break
			end
			queueSave(me, s, now)
		end
	end

	function self.busy(me: Saves): boolean
		return next(me.queues) ~= nil
	end

	function self.closeAll(me: Saves, timeoutSeconds: number?)
		me.closing = true
		if me.profiles then
			me.profiles.closing = true -- one retry per call, no lock waits, sleeps cut short
		end
		-- (a queued load or save then finds its session left and does nothing: each release writes the latest data)
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
