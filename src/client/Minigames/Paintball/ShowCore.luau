--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Paintball.ShowCore
-- THE SHOW, HEADLESS (checklist PB-1, PB-3, PB-4, PB-8): the match as anyone in the audience sees it,
-- as plain tables with no Instance in sight. PaintballClient feeds it the server's messages and the
-- three stream remotes; World (beside this file) draws what it holds; a spec reads it directly.
--   puppets   every slot the snapshots carry, where it is DRAWN this frame: Wire.between of the two
--             snapshots either side of Clock.viewTime, its bits from the older of the two. That pose is,
--             number for number, the one the server rewinds a shot to (Clock, "the history is the
--             snapshot stream"), so the shooter's own ball is tested against exactly these.
--   balls     every ball in flight on this screen. OTHER slots' come from Shot records and are drawn in
--             VIEW TIME (age = view time - birth), so a ball leaves the marker of the puppet that fired
--             it; they stop on a wall by the arena's own test and on a body when the server's Splat
--             record says so. YOUR OWN is predicted (predict): it flies in REAL time from the click
--             and is tested every step the way the server tests it (arena.sweep, then Hit.body against
--             every opposing body, the first thing along the step winning). Told the click's view time
--             (predict's vt), a step ending at age a tests each body where the snapshots put it at
--             (birth + a) - rewind, the rewind being the click's own (ft - vt) held to Clock.MAX_REWIND
--             as the server holds it: on a slow, jittery link the picture can be further back than the
--             server will rewind, and the puff then goes where the server's verdict will. (Not told it,
--             against every puppet where it is drawn; in a frame longer than a server tick, where it was
--             drawn at each step's own time.)
--   splats    the two pools of Wire, kept exactly as the server keeps them: the walls' newest
--             Rules.splatPool, each slot's newest Rules.bodySplats. A predicted wall splat of your own
--             is replaced by the server's record, or taken back after Tuning.predictedSplatSecs.
--   cues      sounds as cue points with a volume worked out from where the listener stands (distance,
--             and Tuning.floorMuffle for every floor between). A cue with a place keeps it (x, y, z, and
--             the floors between), so the caller plays it FROM there and the ear hears which way it came
--             from; the caller plays and empties the list.
--   puffs     a small burst of paint where your own ball met a puppet (nothing else is claimed there:
--             the hit marker, the sound and the splat on the body wait for the server's word).
-- Everything is in the arena frame and on the shared clock.
-- Pure but for the clock it is handed. Interface: new(opts) -> Show; Show: onWatch(msg, place),
--   onSnap(payload), onShots(payload), onSplats(payload), step(dt), stop(); predict(shot, t0, ox, oy,
--   oz, vx, vy, vz, mx?, my?, mz?) -> Ball (your own ball; m = where the muzzle is drawn); verdict(shot,
--   ok, ball?) (the server's ack); cue(name, volume, x?, y?, z?); teamOf(id) -> number; types Puppet,
--   Ball, Splat, Cue, Puff, Show, Opts

local Import = require("../../Import")
local ArenaModule: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Arena)) =
	Import.shared("Minigames/Paintball/Arena")
local Ballistics: typeof(require(game.ReplicatedStorage.Shared.Paintball.Ballistics)) =
	Import.shared("Paintball/Ballistics")
local Body: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Body)) =
	Import.shared("Minigames/Paintball/Body")
local Clock: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Clock)) =
	Import.shared("Minigames/Paintball/Clock")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local Hit: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Hit)) =
	Import.shared("Minigames/Paintball/Hit")
local Wire: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Wire)) =
	Import.shared("Minigames/Paintball/Wire")
local Tuning = require("./Tuning")

type Arena = typeof(ArenaModule.T.Arena)
type Place = typeof(ArenaModule.T.Place)
type SitePlace = typeof(ArenaModule.T.SitePlace)
type Feel = typeof(Contract.T.Feel)
type SnapBody = typeof(Wire.T.SnapBody)
type Watched = typeof(Wire.T.Watched)
type View = typeof(Clock.newView())

export type Puppet = {
	id: number,
	team: number, -- 0 until the roster says
	name: string,
	bot: boolean,
	x: number,
	y: number,
	z: number,
	yaw: number,
	pitch: number,
	crouch: number,
	bits: number, -- of the older of the two snapshots drawn between
	shown: boolean, -- drawn this frame (never your own; not while tagged out past the raised hand)
	hand: boolean, -- tagged out: the hand is up
	outAt: number?, -- when its out bit was first drawn
	walked: number, -- studs since its last footstep
	wx: number, -- where it was drawn in the frame before this one (a slow frame flies a ball in several
	wy: number, -- steps, and each is tested against the body where it was drawn at that step's own time)
	wz: number,
	wc: number,
}

export type Ball = {
	key: number, -- unique on this screen
	ball: number, -- the server's ball id (your own: -1 until the ack)
	by: number,
	team: number,
	own: boolean,
	shot: number, -- your own: the click's counter
	t0: number,
	ox: number,
	oy: number,
	oz: number,
	vx: number,
	vy: number,
	vz: number,
	age: number, -- how far along its flight it has been tested and drawn
	x: number,
	y: number,
	z: number,
	mx: number, -- your own: the offset from the eye line to the muzzle it is drawn leaving
	my: number,
	mz: number,
	born: boolean, -- it has been drawn (its pop has been heard)
	verdict: { [string]: number }?, -- another's: the server's Splat record, waiting for the picture
	verdictAt: number,
	splat: number?, -- your own: the key of the predicted wall splat it left
	-- your own: how far back the server will judge it (Clock.stamp's rewind, as far as the client can tell:
	-- its fire time less its view time, held to Clock.MAX_REWIND); nil: tested against the bodies as drawn
	rewind: number?,
}

export type Splat = {
	key: number, -- unique on this screen (a record: its seq; a predicted one: negative)
	seq: number,
	ball: number,
	by: number,
	body: number, -- 0: on the building
	team: number,
	face: number,
	x: number, -- on the building: the point; on a body: the offset in the body's frame (Wire.fromBody)
	y: number,
	z: number,
	predicted: boolean,
	at: number, -- when it appeared on this screen
	shot: number, -- a predicted one: the click that made it
}

-- x, y, z: where the sound is, in the arena frame (nil: nowhere in particular); floors: how many floors lie
-- between it and the listener (its volume has paid for them already; the caller may also dull it)
export type Cue = { cue: string, volume: number, x: number?, y: number?, z: number?, floors: number? }
export type Puff = { x: number, y: number, z: number, team: number }
type Snap = { t: number, bodies: { [number]: SnapBody } }

export type Opts = {
	arena: Arena,
	now: () -> number,
	tuning: typeof(Tuning.T)?,
}

export type Show = {
	arena: Arena,
	match: number,
	feel: Feel,
	place: SitePlace?, -- the site's place, as the framework told it
	frame: Place?, -- the arena's own (Arena.placeOf(place))
	view: View,
	vt: number, -- the view time of the frame last drawn
	you: number, -- the slot of the player at this screen; 0: only watching
	slots: { [number]: Watched },
	puppets: { [number]: Puppet },
	balls: { Ball },
	walls: { Splat }, -- oldest first
	bodies: { [number]: { Splat } }, -- by slot, oldest first
	version: number, -- counts every change to the splats (the drawer redraws when it moves)
	cues: { Cue },
	puffs: { Puff },
	listener: { x: number, y: number, z: number }?, -- where the sounds are heard from; nil: full volume
	onWatch: (self: Show, msg: { [string]: any }, place: SitePlace?) -> (),
	onSnap: (self: Show, payload: any) -> (),
	onShots: (self: Show, payload: any) -> (),
	onSplats: (self: Show, payload: any) -> (),
	step: (self: Show, dt: number) -> (),
	stop: (self: Show) -> (),
	predict: (
		self: Show,
		shot: number,
		t0: number,
		ox: number,
		oy: number,
		oz: number,
		vx: number,
		vy: number,
		vz: number,
		mx: number?,
		my: number?,
		mz: number?,
		vt: number?
	) -> Ball,
	verdict: (self: Show, shot: number, ok: boolean, ball: number?) -> (),
	cue: (self: Show, name: string, volume: number, x: number?, y: number?, z: number?) -> (),
	teamOf: (self: Show, id: number) -> number,
}

local ShowCore = {}

local R = Contract.Rules
local BIT = Wire.BIT
local STEP = 1 / Clock.TICK_HZ -- a ball is flown in steps no longer than the server's own
local MAX_CUES = 64

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- the angle a fraction f of the way from a to b, the short way round
local function turn(a: number, b: number, f: number): number
	return wrap(a + wrap(b - a) * f)
end

function ShowCore.new(opts: Opts): Show
	local arena = opts.arena
	local now = opts.now
	local tuning = opts.tuning or Tuning
	local snaps: { Snap } = {} -- oldest first
	local keys = 0
	local predictedKeys = 0
	local matchByte = 0

	local show = {
		arena = arena,
		match = 0,
		feel = Contract.feel(),
		place = nil,
		frame = nil,
		view = Clock.newView(),
		vt = -math.huge,
		you = 0,
		slots = {},
		puppets = {},
		balls = {},
		walls = {},
		bodies = {},
		version = 0,
		cues = {},
		puffs = {},
		listener = nil,
	} :: Show

	-- A sound as a cue point with its volume here: full at the listener, half at Tuning.soundHalf,
	-- nothing past soundFar, and floorMuffle taken off for every floor between.
	function show.cue(self: Show, name: string, volume: number, x: number?, y: number?, z: number?)
		local v = volume
		local ear = self.listener
		local floors: number? = nil
		if ear and x and y and z then
			local dx, dy, dz = x - ear.x, y - ear.y, z - ear.z
			local d = math.sqrt(dx * dx + dy * dy + dz * dz)
			if d >= tuning.soundFar then
				return
			end
			local k = d / tuning.soundHalf
			v /= 1 + k * k
			local between = math.abs(y // ArenaModule.FLOOR_HEIGHT - ear.y // ArenaModule.FLOOR_HEIGHT)
			v *= tuning.floorMuffle ^ between
			floors = between
		end
		if v < 0.02 then
			return
		end
		if #self.cues >= MAX_CUES then
			table.remove(self.cues, 1)
		end
		table.insert(self.cues, { cue = name, volume = math.min(1, v), x = x, y = y, z = z, floors = floors })
	end

	function show.teamOf(self: Show, id: number): number
		local slot = self.slots[id]
		return if slot then slot.team else 0
	end

	local function changed(self: Show)
		self.version += 1
	end

	local function clearPaint(self: Show)
		table.clear(self.walls)
		table.clear(self.bodies)
		table.clear(self.balls)
		table.clear(self.puffs)
		changed(self)
	end

	-- THE SPLATS: two pools, as Wire says.
	local function addRecord(self: Show, rec: { [string]: number }, quiet: boolean)
		local splat: Splat = {
			key = rec.seq,
			seq = rec.seq,
			ball = rec.ball,
			by = rec.by,
			body = rec.body,
			team = rec.team,
			face = rec.face,
			x = rec.x,
			y = rec.y,
			z = rec.z,
			predicted = false,
			at = now(),
			shot = 0,
		}
		local replaced = false
		local pool: { Splat }
		local cap: number
		if rec.body == 0 then
			pool, cap = self.walls, R.splatPool
			if rec.by == self.you and self.you ~= 0 then
				-- the server's record takes the place of the nearest predicted splat of your own
				local best, bestD = 0, tuning.predictedSplatSnap
				for i, s in pool do
					if s.predicted then
						local dx, dy, dz = s.x - rec.x, s.y - rec.y, s.z - rec.z
						local d = math.sqrt(dx * dx + dy * dy + dz * dz)
						if d <= bestD then
							best, bestD = i, d
						end
					end
				end
				if best > 0 then
					table.remove(pool, best)
					replaced = true
				end
			end
		else
			local list = self.bodies[rec.body]
			if list == nil then
				list = {}
				self.bodies[rec.body] = list
			end
			pool, cap = list, R.bodySplats
		end
		-- in seq order, no record twice (the batch on coming in may overlap what has arrived since)
		local at = #pool + 1
		for i = #pool, 1, -1 do
			local s = pool[i]
			if not s.predicted then
				if s.seq == rec.seq then
					return
				elseif s.seq < rec.seq then
					break
				end
				at = i
			end
		end
		table.insert(pool, at, splat)
		-- the pool holds the newest `cap` RECORDS (a predicted splat is not one, and is not counted)
		local n = 0
		for _, s in pool do
			if not s.predicted then
				n += 1
			end
		end
		local i = 1
		while n > cap and i <= #pool do
			if pool[i].predicted then
				i += 1
			else
				table.remove(pool, i)
				n -= 1
			end
		end
		changed(self)
		if not quiet and not replaced then
			if rec.body == 0 then
				self:cue("paintball.splat", tuning.volSplat, rec.x, rec.y, rec.z)
			else
				local p = self.puppets[rec.body]
				if p then
					self:cue("paintball.splat", tuning.volSplat, p.x, p.y + rec.y, p.z)
				end
			end
		end
	end

	local function removeBall(self: Show, ball: Ball)
		local i = table.find(self.balls, ball)
		if i then
			table.remove(self.balls, i)
		end
	end

	local function removeSplatKey(self: Show, key: number)
		for i, s in self.walls do
			if s.key == key then
				table.remove(self.walls, i)
				changed(self)
				return
			end
		end
	end

	function show.onWatch(self: Show, msg: { [string]: any }, place: SitePlace?)
		if place ~= nil then
			self.place = place
			self.frame = ArenaModule.placeOf(place)
		end
		if type(msg.match) == "number" and msg.match ~= self.match then
			-- a new match: every splat and every ball goes
			self.match = msg.match
			matchByte = msg.match % 256
			clearPaint(self)
		end
		if type(msg.feel) == "table" then
			self.feel = Contract.feel(msg.feel)
		end
		if type(msg.slots) == "table" then
			local was = self.slots
			local slots: { [number]: Watched } = {}
			for _, s in msg.slots :: { Watched } do
				slots[s.id] = s
			end
			-- a slot's paint goes with its occupant (another user, another name, a bot for a person)
			for id, list in self.bodies do
				local a, b = was[id], slots[id]
				if a == nil or b == nil or a.user ~= b.user or a.name ~= b.name or a.bot ~= b.bot then
					if #list > 0 then
						table.clear(list)
						changed(self)
					end
				end
			end
			self.slots = slots
			for id, p in self.puppets do
				local s = slots[id]
				p.team = if s then s.team else 0
				p.name = if s then s.name else ""
				p.bot = s ~= nil and s.bot
			end
		end
	end

	function show.onSnap(self: Show, payload: any)
		local t, _seq, match, bodies = Wire.decodeSnap(payload)
		if t == nil then
			return
		end
		local time = t :: number
		Clock.observe(self.view, time, now())
		if match ~= matchByte then
			-- the match number moved under us (the roster's own message is on its way): no old paint
			matchByte = match
			clearPaint(self)
		end
		local byId: { [number]: SnapBody } = {}
		for _, b in bodies do
			byId[b.id] = b
		end
		local at = #snaps + 1
		while at > 1 and snaps[at - 1].t > time do
			at -= 1
		end
		if at > 1 and snaps[at - 1].t == time then
			return -- the same snapshot twice
		end
		table.insert(snaps, at, { t = time, bodies = byId })
		local newest = snaps[#snaps].t
		while #snaps > 2 and snaps[1].t < newest - tuning.snapKeep do
			table.remove(snaps, 1)
		end
	end

	function show.onShots(self: Show, payload: any)
		for _, rec in Wire.unpack(Wire.Shot, payload) do
			if rec.id == self.you and self.you ~= 0 then
				continue -- your own: you drew it at the click
			end
			local known = false
			for _, b in self.balls do
				if not b.own and b.ball == rec.ball and b.by == rec.id then
					known = true
					break
				end
			end
			if not known then
				keys += 1
				table.insert(self.balls, {
					key = keys,
					ball = rec.ball,
					by = rec.id,
					team = self:teamOf(rec.id),
					own = false,
					shot = 0,
					t0 = rec.t,
					ox = rec.ox,
					oy = rec.oy,
					oz = rec.oz,
					vx = rec.vx,
					vy = rec.vy,
					vz = rec.vz,
					age = 0,
					x = rec.ox,
					y = rec.oy,
					z = rec.oz,
					mx = 0,
					my = 0,
					mz = 0,
					born = false,
					verdict = nil,
					verdictAt = 0,
					splat = nil,
				})
			end
		end
	end

	function show.onSplats(self: Show, payload: any)
		local records = Wire.unpack(Wire.Splat, payload)
		-- (the batch on coming into the audience is the whole of both pools: it is not eight hundred sounds)
		local quiet = #records > 8
		for _, rec in records do
			local flying: Ball? = nil
			for _, b in self.balls do
				if b.by == rec.by and b.ball == rec.ball then
					flying = b
					break
				end
			end
			if flying and flying.own then
				-- the server ended your ball where your own test did not: its word stands
				removeBall(self, flying)
				local key = flying.splat
				if key then
					removeSplatKey(self, key)
				end
				addRecord(self, rec, quiet)
			elseif flying and flying.born then
				-- another's ball, still in the air on this screen (it is drawn a view-lag behind): the
				-- record waits until the picture gets there
				flying.verdict = rec
				flying.verdictAt = now()
			else
				if flying then
					removeBall(self, flying)
				end
				addRecord(self, rec, quiet)
			end
		end
	end

	function show.predict(
		self: Show,
		shot: number,
		t0: number,
		ox: number,
		oy: number,
		oz: number,
		vx: number,
		vy: number,
		vz: number,
		mx: number?,
		my: number?,
		mz: number?,
		vt: number?
	): Ball
		keys += 1
		local ball: Ball = {
			key = keys,
			ball = -1, -- (not known until the ack)
			by = self.you,
			team = self:teamOf(self.you),
			own = true,
			shot = shot,
			t0 = t0,
			ox = ox,
			oy = oy,
			oz = oz,
			vx = vx,
			vy = vy,
			vz = vz,
			age = 0,
			x = ox + (mx or 0),
			y = oy + (my or 0),
			z = oz + (mz or 0),
			mx = mx or 0,
			my = my or 0,
			mz = mz or 0,
			born = true,
			verdict = nil,
			verdictAt = 0,
			splat = nil,
			rewind = if vt then math.clamp(t0 - vt, 0, Clock.MAX_REWIND) else nil,
		}
		table.insert(self.balls, ball)
		return ball
	end

	-- The server's ack of your click: refused, and the ball and the splat it left are taken back;
	-- accepted, and they learn the ball's id.
	function show.verdict(self: Show, shot: number, ok: boolean, ballId: number?)
		for _, b in table.clone(self.balls) do
			if b.own and b.shot == shot then
				if ok then
					b.ball = ballId or -1
				else
					removeBall(self, b)
				end
			end
		end
		for i = #self.walls, 1, -1 do
			local s = self.walls[i]
			if s.predicted and s.shot == shot then
				if ok then
					-- (its shape is picked from the ball's id, as the server's record's will be: drawn
					-- afresh under a new key, so the record that replaces it looks the same)
					s.ball = ballId or -1
					predictedKeys -= 1
					s.key = predictedKeys
				else
					table.remove(self.walls, i)
				end
				changed(self)
			end
		end
	end

	-- May your ball tag this body? (The server skips the same bodies: PaintballService, "balls".)
	local function canTag(
		self: Show,
		id: number,
		side: number,
		bits: number,
		x: number,
		y: number,
		z: number,
		team: number
	): boolean
		if id == self.you or side == 0 or side == team then
			return false
		end
		if Wire.has(bits, BIT.out) or Wire.has(bits, BIT.safe) then
			return false
		end
		local room = arena.spawnRooms[side]
		return not (room ~= nil and ArenaModule.inRoom(room, x, y + 0.1, z))
	end

	-- ... where it is drawn
	local function hittable(self: Show, p: Puppet, team: number): boolean
		return canTag(self, p.id, p.team, p.bits, p.x, p.y, p.z, team)
	end

	-- The two snapshots the stream holds round server time `at` (the older at or before it; held at the
	-- first and at the newest), as the server's own history is read (Clock, "the history is the snapshot
	-- stream").
	local function around(at: number): (Snap?, Snap?)
		for i = #snaps, 1, -1 do
			if snaps[i].t <= at then
				return snaps[i], snaps[i + 1] or snaps[i]
			end
		end
		return snaps[1], snaps[1]
	end

	local function endOnWall(
		self: Show,
		ball: Ball,
		x: number,
		y: number,
		z: number,
		nx: number,
		ny: number,
		nz: number
	)
		removeBall(self, ball)
		if ball.own then
			-- your splat, at once: the server's record will take its place
			predictedKeys -= 1
			table.insert(self.walls, {
				key = predictedKeys,
				seq = 0,
				ball = ball.ball,
				by = ball.by,
				body = 0,
				team = ball.team,
				face = Wire.faceOf(nx, ny, nz),
				x = x,
				y = y,
				z = z,
				predicted = true,
				at = now(),
				shot = ball.shot,
			})
			changed(self)
			self:cue("paintball.splat", tuning.volSplat, x, y, z)
		elseif ball.verdict then
			addRecord(self, ball.verdict, false)
		end
	end

	-- One ball up to `age`: flown in steps no longer than the server's, each tested as the server
	-- tests it. `span` is how long this frame was: a frame longer than a server tick (a phone at 30
	-- frames a second) flies your ball in several steps, and a step that ended part of a frame ago is
	-- tested against each body where it was drawn THEN (between the last frame's picture and this
	-- one's), as the server tests each of its ticks against the bodies of that tick. Returns false when
	-- the ball ended.
	local function fly(self: Show, ball: Ball, age: number, span: number): boolean
		local g = self.feel.ballDrop
		local sweep = arena.sweep
		while ball.age < age do
			local a0 = ball.age
			local a1 = math.min(age, a0 + STEP)
			if a1 > R.ballTtl then
				a1 = R.ballTtl
			end
			if a1 <= a0 then
				break
			end
			local p0x, p0y, p0z = Ballistics.position(ball.ox, ball.oy, ball.oz, ball.vx, ball.vy, ball.vz, g, a0)
			local p1x, p1y, p1z = Ballistics.position(ball.ox, ball.oy, ball.oz, ball.vx, ball.vy, ball.vz, g, a1)
			local best, nx, ny, nz = sweep(p0x, p0y, p0z, p1x, p1y, p1z)
			local struck: Puppet? = nil
			local hx, hy, hz = 0, 0, 0
			local tagged = false
			if ball.own and ball.rewind ~= nil then
				-- tested where the SERVER will test it: each body at (birth + age) - rewind, read from
				-- the snapshots, with the rewind the server will allow (a slow, jittery connection's
				-- picture can be further back than Clock.MAX_REWIND, and the server judges at the limit)
				local at = ball.t0 + a1 - ball.rewind
				local older, newer = around(at)
				if older and newer then
					for id, pa in older.bodies do
						local pb = newer.bodies[id] or pa
						local x, y, z, crouch = Wire.between(pa, older.t, pb, newer.t, at)
						if canTag(self, id, self:teamOf(id), pa.bits, x, y, z, ball.team) then
							local s, sx, sy, sz = Hit.body(sweep, p0x, p0y, p0z, p1x, p1y, p1z, x, y, z, crouch)
							-- (a tie goes to the wall: Hit, rule 4)
							if s ~= nil and (best == nil or s < best) then
								best, tagged, hx, hy, hz = s, true, sx, sy, sz
							end
						end
					end
				end
			elseif ball.own then
				local back = if span > 0 then math.clamp((age - a1) / span, 0, 1) else 0
				for _, p in self.puppets do
					if hittable(self, p, ball.team) then
						local s, x, y, z = Hit.body(
							sweep,
							p0x,
							p0y,
							p0z,
							p1x,
							p1y,
							p1z,
							p.x + (p.wx - p.x) * back,
							p.y + (p.wy - p.y) * back,
							p.z + (p.wz - p.z) * back,
							p.crouch + (p.wc - p.crouch) * back
						)
						-- (a tie goes to the wall: Hit, rule 4)
						if s ~= nil and (best == nil or s < best) then
							best, struck, hx, hy, hz = s, p, x, y, z
						end
					end
				end
			else
				local rec = ball.verdict
				local p = if rec and rec.body ~= 0 then self.puppets[rec.body] else nil
				if p then
					local low, high, r = Body.capsule(p.crouch)
					local s = Hit.capsule(p0x, p0y, p0z, p1x, p1y, p1z, p.x, p.y + low, p.y + high, p.z, r)
					if s ~= nil and (best == nil or s <= best) then
						best, struck = s, p
					end
				end
			end
			if struck or tagged then
				removeBall(self, ball)
				if ball.own then
					-- a puff, and no more: the marker, the sound and the splat wait for the server
					table.insert(self.puffs, { x = hx, y = hy, z = hz, team = ball.team })
				elseif ball.verdict then
					addRecord(self, ball.verdict, false)
				end
				return false
			elseif best ~= nil then
				local s = best :: number
				endOnWall(self, ball, p0x + (p1x - p0x) * s, p0y + (p1y - p0y) * s, p0z + (p1z - p0z) * s, nx, ny, nz)
				return false
			end
			ball.age = a1
			ball.x, ball.y, ball.z = p1x, p1y, p1z
			if a1 >= R.ballTtl then
				removeBall(self, ball)
				if ball.verdict then
					addRecord(self, ball.verdict, false)
				end
				return false
			end
		end
		return true
	end

	function show.step(self: Show, dt: number)
		local t = now()
		local vt = Clock.viewTime(self.view, t)
		self.vt = vt
		-- THE PUPPETS, at the view time: between the snapshot at or before it and the next one
		local a: Snap? = nil
		local b: Snap? = nil
		for i = #snaps, 1, -1 do
			if snaps[i].t <= vt then
				a = snaps[i]
				b = snaps[i + 1]
				break
			end
		end
		if a == nil then
			a = snaps[1] -- the view is still before the first snapshot: held at it
		end
		local older = a
		if older then
			local newer: Snap = b or older
			local k = 1 - math.exp(-tuning.puppetTurn * dt)
			for id, pa in older.bodies do
				local pb = newer.bodies[id] or pa
				local x, y, z, crouch = Wire.between(pa, older.t, pb, newer.t, vt)
				local f = if newer.t > older.t then math.clamp((vt - older.t) / (newer.t - older.t), 0, 1) else 0
				local yaw, pitch = turn(pa.yaw, pb.yaw, f), pa.pitch + (pb.pitch - pa.pitch) * f
				local p = self.puppets[id]
				if p == nil then
					local slot = self.slots[id]
					p = {
						id = id,
						team = if slot then slot.team else 0,
						name = if slot then slot.name else "",
						bot = slot ~= nil and slot.bot,
						x = x,
						y = y,
						z = z,
						yaw = yaw,
						pitch = pitch,
						crouch = crouch,
						bits = 0,
						shown = false,
						hand = false,
						outAt = nil,
						walked = 0,
						wx = x,
						wy = y,
						wz = z,
						wc = crouch,
					}
					self.puppets[id] = p
				else
					-- footsteps: loud running, soft walking, silent crouched or in the air (PB-8)
					local dx, dz = x - p.x, z - p.z
					local moved = math.sqrt(dx * dx + dz * dz)
					if moved < 6 and id ~= self.you and not Wire.has(pa.bits, BIT.air) then
						p.walked += moved
						local sprint = Wire.has(pa.bits, BIT.sprint)
						if p.walked >= (if sprint then tuning.stepSprint else tuning.stepWalk) then
							p.walked = 0
							if crouch < 0.5 then
								self:cue(
									"paintball.step",
									if sprint then tuning.stepLoud else tuning.stepQuiet,
									x,
									y,
									z
								)
							end
						end
					end
					p.yaw = turn(p.yaw, yaw, k)
					p.pitch += (pitch - p.pitch) * k
				end
				p.wx, p.wy, p.wz, p.wc = p.x, p.y, p.z, p.crouch
				p.x, p.y, p.z, p.crouch = x, y, z, crouch
				local was = p.bits
				p.bits = pa.bits
				if Wire.has(p.bits, BIT.reload) and not Wire.has(was, BIT.reload) and id ~= self.you then
					self:cue("paintball.reload", tuning.volReloadFar, x, y, z)
				end
				if Wire.has(p.bits, BIT.out) then
					if p.outAt == nil then
						p.outAt = t
					end
					p.hand = t - (p.outAt :: number) < tuning.outHandSecs
					p.shown = p.hand and id ~= self.you
				else
					p.outAt = nil
					p.hand = false
					p.shown = id ~= self.you
				end
			end
			for id in self.puppets do
				if older.bodies[id] == nil then
					self.puppets[id] = nil
				end
			end
		end
		-- THE BALLS
		for _, ball in table.clone(self.balls) do
			if ball.own then
				local age = t - ball.t0
				if fly(self, ball, age, dt) then
					-- drawn leaving the muzzle, sliding onto the true line
					local blend = math.max(0, 1 - ball.age / tuning.muzzleBlend)
					ball.x += ball.mx * blend
					ball.y += ball.my * blend
					ball.z += ball.mz * blend
				end
			else
				local age = vt - ball.t0
				if age >= 0 and not ball.born then
					ball.born = true
					self:cue("paintball.fire_far", tuning.volFireFar, ball.ox, ball.oy, ball.oz)
				end
				if ball.team == 0 then
					ball.team = self:teamOf(ball.by)
				end
				local alive = true
				if age > 0 then
					alive = fly(self, ball, age, dt)
				end
				local rec = ball.verdict
				if alive and rec and t - ball.verdictAt > tuning.ballCatchUp then
					removeBall(self, ball)
					addRecord(self, rec, false)
				elseif alive and t - ball.t0 > R.ballTtl + 1 then
					removeBall(self, ball) -- never drawn, or its end was lost: gone
				end
			end
		end
		-- a predicted splat the server never confirmed is taken back
		for i = #self.walls, 1, -1 do
			local s = self.walls[i]
			if s.predicted and t - s.at > tuning.predictedSplatSecs then
				table.remove(self.walls, i)
				changed(self)
			end
		end
	end

	function show.stop(self: Show)
		table.clear(snaps)
		table.clear(self.puppets)
		table.clear(self.slots)
		table.clear(self.cues)
		clearPaint(self)
	end

	return show
end

return ShowCore
