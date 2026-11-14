--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Paintball.SeatCore
-- THE SEAT, HEADLESS (checklist PB-1, PB-2, PB-7, PB-9; the procedure is the header of
-- PaintballClient, beside this file): a player in the match as a state machine. Messages, the
-- player's actions and one call a frame go in; Wire.Move, Wire.Fire and the verbs come out, and the
-- state the marker and the HUD are drawn from is left in plain fields. Everything that touches an
-- Instance (the player's own body, the camera's offset, the curtains) is behind the Port it is handed,
-- so the whole of it runs under Lune.
--   firing     a press leaves as a ball in the first frame every client gate holds (the phase with
--              MARGIN.gate, not out, protection + gate, the sprint delay, both spawn rooms + MARGIN.room,
--              the magazine); a press only the fire interval, a nearly finished reload or the sprint
--              delay objects to is HELD and leaves the instant it may; anything else drops it. WHILE THE
--              TRIGGER IS HELD DOWN (the mouse button, R2, a finger left on FIRE: input("fire", false) lets
--              it go) the marker fires at its own rate (Tuning.holdRepeats): each time a ball has left and the next press would
--              be let go or held, a new one is held, so five balls leave a fire interval apart and the
--              reload follows (and when the reload is nearly done the trigger still down fires on). A held
--              trigger never sounds the dry click again and again: only a press does. The
--              ball is predicted on the show from the very numbers that went on the wire (the f32
--              origin and direction, the f64 birth time), so the server's ball and this one are the
--              same curve.
--   the pips   the predicted Magazine, put right by "paintball_ack" (its rounds minus the balls sent
--              since), by a respawn, and once by the first "state".
--   moving     the sprint ramp k (up over Body.SPRINT_RAMP_SECS while sprint is wanted, the body stands
--              and the stick is pushed ahead, within Tuning.sprintCone; to 0 at once otherwise) and the crouch fraction c
--              (Body.crouchStep), handed to ctx.pace and to the eye every frame; Wire.Move
--              Clock.SEND_HZ times a second, never before the first placement nor while out.
--   the origin THE SERVER JUDGES A BALL'S ORIGIN AGAINST THE POSES IT HAS BEEN TOLD (Contract, "the origin":
--              the eye over the slot's own pose at the fire time, between the eye heights of the crouch
--              fraction it keeps and of where the newest Move's crouch bit is heading, 0.4 either way, and
--              the jump's height more while the newest Move says "in the air"). A pose stream of twenty a
--              second leaves it up to 50 ms behind an eye that moves 9 studs a second through a crouch and
--              a body that leaves the floor at 28, so a shot in the first moment of standing up from behind
--              a rail, or of a jump, would be refused after its ball was drawn (found against the real
--              service: two balls in a hundred and sixty). Three things, all the client's own, close that:
--              (1) A CLICK CARRIES ITS POSE: in the frame a ball leaves, a Move with the click's own stamp
--              goes first, so "the pose at the fire time" is the very pose the ball left from; (2) A
--              CHANGE OF STANCE IS TOLD AT ONCE: the crouch key going down or up, and the feet leaving the
--              floor, send a Move in that frame and not at the stream's next turn (a few a second at most,
--              inside the remote's rate); (3) AFTER A QUICK DOUBLE CHANGE (a tap of crouch: down and up
--              inside Tuning.tapWindow) the server's own crouch fraction may be on the far side of the
--              client's, so a click then waits, as it waits for the fire interval, until the eye is within
--              the server's 0.4 of where it is going. A single change holds nothing: the pop-up shot over
--              a rail leaves the instant the click is made.
--   placements pivot the body and take the number; a respawn also turns the look for one frame and gives
--              a full magazine, the legs back and the protection. A correction leaves the look alone: the
--              player's own yaw and pitch are kept (the server's yaw is the last pose it took, up to a second old).
--   idle       the seat counts idleness AS THE SERVER DOES (PaintballService, "idleness": the pose has
--              stayed within 0.5 studs and 0.05 rad of where the count began and no ball has left, over
--              live play; a respawn moves that pose, a correction does not, and neither restarts the
--              count; being tagged out does not stop it), with a fifth more on the bounds, so a tremble of the mouse that the
--              server does not count never hushes the warning: the HUD says so no later than the server
--              would act (Rules.idleSecs).
-- Interface: new(ctx, opts) -> Seat; floorOf(y) -> 1..FLOORS; relative(floors) -> words; types Port, Opts, Seat, Feed. Seat: the framework's controller
--   (onState, onMessage, onRefused, stop) plus input(action, down), step(dt) and the fields below.

local Import = require("../../Import")
local ArenaModule: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Arena)) =
	Import.shared("Minigames/Paintball/Arena")
local Body: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Body)) =
	Import.shared("Minigames/Paintball/Body")
local BufferCodec: typeof(require(game.ReplicatedStorage.Shared.Util.BufferCodec)) = Import.shared("Util/BufferCodec")
local Clock: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Clock)) =
	Import.shared("Minigames/Paintball/Clock")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local Magazine: typeof(require(game.ReplicatedStorage.Shared.Paintball.Magazine)) = Import.shared("Paintball/Magazine")
local Wire: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Wire)) =
	Import.shared("Minigames/Paintball/Wire")
local ClientGame = require("../ClientGame")
local ShowCore = require("./ShowCore")
local Tuning = require("./Tuning")

type Arena = typeof(ArenaModule.T.Arena)
type Feel = typeof(Contract.T.Feel)
type SlotView = typeof(Contract.T.SlotView)
type Mag = typeof(Magazine.new(1, 1, 1))

export type Link = {
	send: (remote: string, payload: buffer) -> (),
	listen: (remote: string, fn: (payload: any) -> ()) -> () -> (),
}

export type Action = "fire" | "reload" | "crouch" | "sprint" | "scores" | "leave" | "side"

-- Everything of the player's own that is an Instance, in the arena frame. Every member may be nil
-- (a spec hands in the ones it watches).
--   pose      the REAL feet point, the unit look, and whether the body is off the floor; nil: no body
--   push      how hard the stick or the keys are pushed, 0..1
--   forward   how much of that push is straight ahead, -1 (back) .. 1, in the view's own frame
--   place     pivot the body to a feet point and yaw (a placement)
--   look      begin the one-frame turn of the look: a camera hold at this eye point along this yaw
--   muzzle    where the marker's muzzle is drawn (the ball is drawn leaving it)
--   eye       the eye's height against a standing eye (0 standing, negative crouched or dipping)
--   fov       degrees the view is widened by
--   curtains  the team whose curtains are solid on this screen (nil: none)
--   lock      first person on (the CameraZone attribute) and the match's jump height; off puts both back
--   user      this player's UserId (0: not known): how the seat finds its slot in "paintball_watch"
export type Port = {
	pose: (() -> (number?, number, number, number, number, number, boolean))?,
	push: (() -> number)?,
	forward: (() -> number)?,
	place: ((x: number, y: number, z: number, yaw: number) -> ())?,
	look: ((x: number, y: number, z: number, yaw: number) -> ())?,
	muzzle: (() -> (number?, number, number))?,
	eye: ((offset: number) -> ())?,
	fov: ((extra: number) -> ())?,
	curtains: ((team: number?) -> ())?,
	lock: ((on: boolean) -> ())?,
	user: (() -> number)?,
}

export type Opts = {
	now: () -> number,
	link: Link?,
	arena: Arena,
	port: Port?,
	show: () -> ShowCore.Show?,
	tuning: typeof(Tuning.T)?,
}

export type Feed = { text: string, at: number, team: number, mine: boolean }

export type Seat = {
	ctx: ClientGame.Ctx,
	you: number,
	team: number, -- 0 until the first "state"
	feel: Feel,
	mag: Mag,
	shot: number,
	place: number,
	-- the match as last told
	match: number,
	phase: string, -- "" before the first "state", then the match's own phase
	endsAt: number,
	scores: { number },
	slots: { SlotView },
	names: { [number]: string },
	bots: { boolean },
	-- the body
	x: number,
	y: number,
	z: number,
	yaw: number,
	pitch: number,
	air: boolean,
	k: number, -- the sprint ramp
	c: number, -- the crouch fraction
	dip: number, -- the landing dip of the eye, studs
	wantSprint: boolean,
	wantCrouch: boolean,
	sprintEndedAt: number,
	-- firing
	held: number?, -- a press waiting for the marker: when it was made
	trigger: boolean, -- the fire button is held down: the marker fires at its own rate (see "firing")
	autoHeld: boolean, -- the press waiting is the held trigger's, not a press: letting go drops it
	firedAt: number, -- the last ball left (the marker's kick)
	fired: number, -- balls let go since the seat opened
	reloadFrom: number, -- when the running reload began (the marker's tip)
	dryAt: number,
	-- out and back
	out: boolean,
	outUntil: number,
	outBy: number,
	tagFrom: { x: number, y: number, z: number }?, -- where the one who tagged you stood (as drawn)
	result: any?, -- view.result at the end card (Contract.Result)
	safeUntil: number, -- the protection of the last respawn ends
	floor: number, -- the storey you stand on, 1..Arena.FLOORS (0: no body yet), shown under the clock
	inRoom: boolean, -- standing in your own spawn room
	nearRoom: boolean, -- in or within MARGIN.room of either spawn room: no ball may leave from here
	legs: boolean, -- false while the legs are taken
	-- the HUD's own
	board: boolean, -- the scoreboard is asked for
	feed: { Feed },
	hitAt: number, -- the server said you tagged someone
	goggleAt: number, -- you were tagged
	note: string,
	noteAt: number,
	activeAt: number, -- the player last moved, turned or fired (or the match was not live for them)
	now: number, -- the shared clock of the last step
	onState: (self: Seat, msg: { [string]: any }) -> (),
	onMessage: (self: Seat, msg: { [string]: any }, watched: any?) -> (),
	onRefused: (self: Seat, msg: { [string]: any }) -> (),
	input: (self: Seat, action: Action, down: boolean) -> (),
	step: (self: Seat, dt: number) -> (),
	stop: (self: Seat) -> (),
	live: (self: Seat, now: number) -> boolean,
	ready: (self: Seat, now: number) -> boolean, -- would a press leave as a ball this instant?
	-- only the marker's own rhythm (the fire interval, or the eye settling after a tap of crouch) keeps a
	-- press from leaving this instant: it is held and leaves by itself the moment it may
	rhythm: (self: Seat, now: number) -> boolean,
	markerUp: (self: Seat, now: number) -> number, -- 0 down (sprinting) .. 1 up
	reloading: (self: Seat, now: number) -> number?, -- 0..1 through the running reload; nil: none
	protected: (self: Seat, now: number) -> number?, -- seconds of protection left; nil: none
	idle: (self: Seat, now: number) -> number?, -- seconds until an idle player is taken off; nil: no warning due
}

local SeatCore = {}

-- The storey (1..Arena.FLOORS) feet at height y stand on.
function SeatCore.floorOf(y: number): number
	return math.clamp(math.floor(y / ArenaModule.FLOOR_HEIGHT + 0.5) + 1, 1, ArenaModule.FLOORS)
end

-- A floor call-out said from where the reader stands: "this floor", "one up", "two down".
function SeatCore.relative(diff: number): string
	if diff == 0 then
		return "this floor"
	end
	local words = { "one", "two", "three", "four" }
	local n = words[math.abs(diff)] or tostring(math.abs(diff))
	return `{n} {if diff > 0 then "up" else "down"}`
end

local R = Contract.Rules
local M = Contract.MARGIN
local BIT = Wire.BIT
local SEND = 1 / Clock.SEND_HZ
-- Idleness, the server's bounds (the prose of PaintballService, "idleness": 0.5 studs, 0.05 rad) and a fifth
-- more: the client never thinks its player moved when the server does not.
local IDLE_STUDS = 0.6
local IDLE_RAD = 0.06
-- Moves sent ahead of the stream's turn for a change of stance: at most TELL_MOST at once, refilled at
-- TELL_RATE a second. With the stream's twenty and a ball's own Move (at most one a fire interval) the remote
-- stays inside Shared/Net's thirty a second however the keys are mashed.
local TELL_MOST = 3
local TELL_RATE = 3
local LEAVE = { "leave", "Leave the match" }
local SIDE = { "side", "Change sides" }

function SeatCore.new(ctx: ClientGame.Ctx, opts: Opts): Seat
	local arena = opts.arena
	local clock = opts.now
	local link = opts.link
	local port: Port = opts.port or {}
	local tuning = opts.tuning or Tuning
	local feel = Contract.feel()

	local unacked: { number } = {} -- the clicks sent and not yet answered, oldest first
	local firstState = true
	local briefEnds: number? = nil -- the end of the briefing this seat saw (the gate of "live")
	local moveAcc = SEND
	local moveSeq = 0
	local lastMoveT = -math.huge -- the stamp of the last Move sent (two never carry the same one)
	local tell = false -- a Move is owed at once: the stance changed, the feet left the floor
	local tellBudget = TELL_MOST -- how many such Moves may still go (it refills: the remote has a rate)
	local flipLast, flipPrev = -math.huge, -math.huge -- when the crouch key last changed, and the time before
	local turnFrames = 0 -- frames of the look's hold still to run
	local turnLook: { number }? = nil
	local walked = 0
	local fallSpeed = 0
	local lastBar = ""
	local verbAt = -math.huge
	local hasPose = false
	local lookX, lookY, lookZ = 0, 0, -1
	local lastX, lastZ = 0 / 0, 0 / 0
	local idleX, idleY, idleZ, idleYaw, idlePitch = 0, 0, 0, 0, 0
	local wasLive = false
	local early: { [number]: { [string]: any } } = {} -- placements that came before this seat knew its slot

	local seat = {
		ctx = ctx,
		you = 0,
		team = 0,
		feel = feel,
		mag = Magazine.new(R.magazine, feel.fireInterval, feel.reloadSecs),
		shot = 0,
		place = 0,
		match = 0,
		phase = "",
		endsAt = 0,
		scores = { 0, 0 },
		slots = {},
		names = {},
		bots = {},
		x = 0,
		y = 0,
		z = 0,
		yaw = 0,
		pitch = 0,
		air = false,
		k = 0,
		c = 0,
		dip = 0,
		wantSprint = false,
		wantCrouch = false,
		sprintEndedAt = -math.huge,
		held = nil,
		trigger = false,
		autoHeld = false,
		floor = 0,
		firedAt = -math.huge,
		fired = 0,
		reloadFrom = -math.huge,
		dryAt = -math.huge,
		out = false,
		outUntil = 0,
		outBy = 0,
		tagFrom = nil,
		result = nil,
		safeUntil = -math.huge,
		inRoom = false,
		nearRoom = false,
		legs = true,
		board = false,
		feed = {},
		hitAt = -math.huge,
		goggleAt = -math.huge,
		note = "",
		noteAt = -math.huge,
		activeAt = clock(),
		now = clock(),
	} :: Seat

	local function say(text: string, now: number)
		seat.note = text
		seat.noteAt = now
	end

	local function nameOf(id: number): string
		return seat.names[id] or `Player {id}`
	end

	local function feedLine(text: string, team: number, mine: boolean, now: number)
		table.insert(seat.feed, { text = text, at = now, team = team, mine = mine })
		while #seat.feed > tuning.feedLines do
			table.remove(seat.feed, 1)
		end
	end

	-- the body as it is this instant
	local function sample(): boolean
		local pose = port.pose
		if pose == nil then
			return hasPose
		end
		local x, y, z, dx, dy, dz, air = pose()
		if x == nil then
			return false
		end
		seat.x, seat.y, seat.z, seat.air = x, y, z, air
		lookX, lookY, lookZ = dx, dy, dz
		seat.yaw, seat.pitch = Body.yawPitch(dx, dy, dz)
		hasPose = true
		return true
	end

	local function endSprint(now: number)
		if seat.k > 0 then
			seat.k = 0
			seat.sprintEndedAt = now
		end
	end

	-- The match is live for this client: the server said so, or the briefing it was told the end of
	-- is over; in both cases MARGIN.gate inside the times the server named.
	function seat.live(self: Seat, now: number): boolean
		if self.phase == "live" then
			return (briefEnds == nil or now >= briefEnds + M.gate) and now < self.endsAt - M.gate
		elseif self.phase == "briefing" then
			return now >= self.endsAt + M.gate and now < self.endsAt + R.matchSecs - M.gate
		end
		return false
	end

	-- The magazine brought up to `now`. A reload that has run its time ends here and nowhere else, so
	-- the click that says "full again" is heard exactly once.
	local function settle(now: number)
		local mag = seat.mag
		local was = mag.reloadDoneAt
		Magazine.update(mag, now)
		if was ~= nil and mag.reloadDoneAt == nil then
			ctx.sound("paintball.ready", tuning.volReady)
		end
	end

	-- In (or, with `margin`, within that of) either team's spawn room.
	local function nearRoom(margin: number?): boolean
		for _, room in arena.spawnRooms do
			if ArenaModule.inRoom(room, seat.x, seat.y + 0.1, seat.z, margin) then
				return true
			end
		end
		return false
	end

	-- What stands in a press's way at `now`: nothing ("go"), a wait it is held through ("hold"; the third
	-- value true when that is only the marker's own rhythm: the fire interval, or the eye settling after a
	-- tap of crouch), an empty or reloading marker ("dry"), or something else ("drop", with the words to show).
	local function gate(now: number): (string, string?, boolean?)
		if not seat:live(now) or seat.you == 0 or seat.place == 0 then
			return "drop", nil
		elseif seat.out then
			return "drop", nil
		elseif now < seat.safeUntil + M.gate then
			return "drop", "Protected: you cannot fire yet"
		elseif nearRoom(M.room) then
			-- (the words tell the truth: a step outside the door is still too close)
			return "drop", if nearRoom() then "No firing from a spawn room" else "Too close to a spawn room to fire"
		end
		local mag = seat.mag
		settle(now)
		local reloading = mag.reloadDoneAt
		if reloading ~= nil and not mag.manual then
			return if reloading - now <= M.click then "hold" else "dry", nil
		elseif mag.rounds <= 0 then
			return "dry", nil
		elseif seat.k > 0 or now < seat.sprintEndedAt + Body.SPRINT_FIRE_DELAY then
			return "hold", nil
		elseif now < mag.nextFireAt then
			return "hold", nil, true
		elseif now - flipPrev < tuning.tapWindow then
			-- a quick double change of stance (see the header, "the origin"): the eye must be within the
			-- server's slack of where it is going before a ball may leave from it
			local going = Body.eye(if seat.wantCrouch then 1 else 0)
			if math.abs(Body.eye(seat.c) - going) > Contract.TRUST.originSlackY - tuning.tapSlack then
				return "hold", nil, true
			end
		end
		return "go", nil
	end

	function seat.ready(_self: Seat, now: number): boolean
		return hasPose and (gate(now)) == "go"
	end

	function seat.rhythm(_self: Seat, now: number): boolean
		local verdict, _, rhythm = gate(now)
		return hasPose and verdict == "hold" and rhythm == true
	end

	-- 0 while the sprint has the marker down, 1 when it is up and may fire.
	function seat.markerUp(self: Seat, now: number): number
		if self.k > 0 then
			return 0
		end
		return math.clamp((now - self.sprintEndedAt) / Body.SPRINT_FIRE_DELAY, 0, 1)
	end

	function seat.reloading(self: Seat, now: number): number?
		local done = self.mag.reloadDoneAt
		if done == nil or now >= done then
			return nil
		end
		local span = math.max(1e-3, done - self.reloadFrom)
		return math.clamp(1 - (done - now) / span, 0, 1)
	end

	-- Seconds of the respawn's protection still to run (cannot be hit, cannot fire); nil when there is
	-- none: before the first placement, while out, at the end card.
	function seat.protected(self: Seat, now: number): number?
		if self.place == 0 or self.out or self.phase == "ended" or self.phase == "" or now >= self.safeUntil then
			return nil
		end
		return self.safeUntil - now
	end

	-- Seconds until the server takes this player off for standing idle (Rules.idleSecs of live play
	-- without moving, turning or firing), once that is Tuning.idleWarn or less away; nil otherwise.
	-- Tagged out too: the server's count does not stop for it, so neither does the warning.
	function seat.idle(self: Seat, now: number): number?
		if self.place == 0 or not self:live(now) then
			return nil
		end
		local left = R.idleSecs - (now - self.activeAt)
		return if left <= tuning.idleWarn then math.max(0, left) else nil
	end

	local function rattle(now: number)
		seat.reloadFrom = now
		ctx.sound("paintball.reload", tuning.volReload)
	end

	-- The pose as it stands, up the link, stamped `now`. False when there is none to send (no body, no
	-- placement yet, tagged out) or one with this stamp has gone already.
	local function sendPose(now: number): boolean
		if not (hasPose and link and seat.place ~= 0 and not seat.out and seat.you ~= 0) or now <= lastMoveT then
			return false
		end
		lastMoveT = now
		moveSeq = (moveSeq + 1) % 65536
		local bits = (if seat.wantCrouch then BIT.crouch else 0)
			+ (if seat.k > 0 then BIT.sprint else 0)
			+ (if seat.air then BIT.air else 0)
		link.send(
			"Paintball.Move",
			BufferCodec.encode(Wire.Move, {
				t = now,
				seq = moveSeq,
				x = seat.x,
				y = seat.y,
				z = seat.z,
				yaw = seat.yaw,
				pitch = seat.pitch,
				bits = bits,
				place = seat.place,
			})
		)
		return true
	end

	-- A ball leaves. Returns false when it could not (no body to fire from).
	local function fire(now: number): boolean
		if not sample() then
			return false
		end
		local mag = seat.mag
		if not Magazine.fire(mag, now) then
			return false
		end
		seat.shot = seat.shot % 65535 + 1
		local shot = seat.shot
		local show = opts.show()
		local vt = if show then Clock.viewTime(show.view, now) else now - Clock.INTERP_SECS
		local ox, oy, oz = Body.eyePoint(seat.x, seat.y, seat.z, seat.c)
		local payload = BufferCodec.encode(Wire.Fire, {
			shot = shot,
			vt = vt,
			ft = now,
			ox = ox,
			oy = oy,
			oz = oz,
			dx = lookX,
			dy = lookY,
			dz = lookZ,
		})
		if link then
			-- the click carries its pose: the server reads "the pose at the fire time" from this very Move
			if sendPose(now) then
				moveAcc = 0
			end
			link.send("Paintball.Fire", payload)
		end
		table.insert(unacked, shot)
		seat.fired += 1
		seat.firedAt = now
		seat.activeAt = now
		ctx.sound("paintball.fire", tuning.volFire)
		if show then
			-- the ball the server will fly, from the very numbers on the wire
			local sent = BufferCodec.decode(Wire.Fire, payload)
			local len = math.sqrt(sent.dx * sent.dx + sent.dy * sent.dy + sent.dz * sent.dz)
			local speed = seat.feel.ballSpeed / math.max(len, 1e-9)
			local mx, my, mz = 0, 0, 0
			local muzzle = port.muzzle
			if muzzle then
				local px, py, pz = muzzle()
				if px ~= nil then
					mx, my, mz = px - sent.ox, py - sent.oy, pz - sent.oz
				end
			end
			show:predict(
				shot,
				sent.ft,
				sent.ox,
				sent.oy,
				sent.oz,
				sent.dx * speed,
				sent.dy * speed,
				sent.dz * speed,
				mx,
				my,
				mz,
				sent.vt
			)
		end
		if mag.reloadDoneAt ~= nil then
			rattle(now) -- the fifth ball: the reload starts by itself
		end
		return true
	end

	-- A waiting press: let it go, keep it, or drop it.
	local function tryFire(now: number)
		if seat.held == nil then
			return
		end
		local verdict, words = gate(now)
		if verdict == "go" then
			seat.held = nil
			fire(now)
		elseif verdict == "dry" then
			seat.held = nil
			if now - seat.dryAt >= tuning.drySecs then
				seat.dryAt = now
				ctx.sound("paintball.dry", tuning.volDry)
			end
		elseif verdict == "drop" then
			seat.held = nil
			if words then
				say(words, now)
			end
		end
	end

	local function bar()
		-- Leave and Change sides with the scoreboard and through the briefing; nothing while playing
		-- (the mouse is the look); the framework's own Leave at the end card
		if seat.phase == "ended" or seat.phase == "" then
			lastBar = ""
			return
		end
		local want = seat.board or seat.phase == "briefing"
		local sig = if want then "on" else "off"
		if sig ~= lastBar then
			lastBar = sig
			ctx.setButtons(if want then { LEAVE, SIDE } else {})
		end
	end

	local function rebuildMag(next: Feel)
		local was = seat.feel
		seat.feel = next
		if was.fireInterval ~= next.fireInterval or was.reloadSecs ~= next.reloadSecs then
			local old = seat.mag
			local mag = Magazine.new(R.magazine, next.fireInterval, next.reloadSecs)
			mag.rounds, mag.nextFireAt, mag.reloadDoneAt = old.rounds, old.nextFireAt, old.reloadDoneAt
			seat.mag = mag
		end
	end

	local function setTeam(team: number)
		if team ~= seat.team then
			seat.team = team
			local curtains = port.curtains
			if curtains then
				curtains(if team == 1 then 2 elseif team == 2 then 1 else nil)
			end
		end
	end

	local iAm: (id: number, team: number?) -> ()
	local flush: (now: number) -> ()

	function seat.onState(self: Seat, msg: { [string]: any })
		local now = clock()
		local was = self.phase
		if type(msg.you) == "number" and msg.you ~= self.you then
			iAm(msg.you, nil)
		end
		if type(msg.feel) == "table" then
			rebuildMag(Contract.feel(msg.feel))
		end
		if type(msg.bots) == "table" then
			self.bots = msg.bots
		end
		if type(msg.match) == "number" and msg.match ~= self.match then
			self.match = msg.match
			table.clear(self.feed)
			briefEnds = nil
		end
		local view = msg.view
		local game = if type(view) == "table" then view.game else nil
		if type(game) == "table" then
			if type(view.seats) == "table" then
				local names: { [number]: string } = {}
				for id, s in view.seats :: { any } do
					if type(s) == "table" and type(s.name) == "string" then
						names[id] = s.name
					end
				end
				self.names = names
			end
			if type(game.slots) == "table" then
				self.slots = game.slots
				local mine = self.slots[self.you]
				if mine then
					setTeam(mine.team)
				end
			end
			if type(game.scores) == "table" then
				self.scores = { game.scores[1] or 0, game.scores[2] or 0 }
			end
			if type(game.phase) == "string" and type(game.endsAt) == "number" then
				if game.phase == "briefing" then
					briefEnds = game.endsAt
				elseif game.phase == "live" and briefEnds ~= nil and now < briefEnds then
					-- live before the briefing this seat was told of was due to end: it was cut short (the
					-- owner's debug("end") at a playtest). The server's word stands, from the moment it is
					-- heard: a marker that waited out a briefing nobody is in would be dead for ten seconds.
					briefEnds = now
				end
				self.phase, self.endsAt = game.phase, game.endsAt
			end
		end
		if type(view) == "table" then
			self.result = view.result
			if view.phase == "done" then
				if was ~= "ended" and was ~= "" then
					ctx.sound("paintball.over", tuning.volGo) -- full time: the whistle
				end
				self.phase = "ended"
				self.held = nil
				-- the end card: people may walk about (the contract). Somebody tagged in the last seconds
				-- has no respawn coming until the next match, so their legs come back here. (They stay
				-- `out` for the stream's sake: the server drops an out slot's Moves until it places them.)
				if not self.legs then
					self.legs = true
					ctx.controls(true)
				end
			end
		end
		if firstState then
			firstState = false
			-- the server's magazine, once: a client with clicks in flight never takes it
			if #unacked == 0 and type(msg.rounds) == "number" then
				self.mag.rounds = math.clamp(msg.rounds, 0, R.magazine)
				local at = msg.reloadAt
				if type(at) == "number" and at > now then
					self.mag.reloadDoneAt = at
					self.reloadFrom = at - self.feel.reloadSecs
				else
					self.mag.reloadDoneAt = nil
					if type(at) == "number" and at > 0 then
						self.mag.rounds = R.magazine
					end
				end
			end
		end
		if self.phase ~= "ended" then
			flush(now)
		end
		bar()
	end

	-- `turn`: a respawn turns the look to the placed yaw; a correction never does (it comes mid-fight, with the
	-- yaw of the last pose the server took, up to a second old: turning to it would snap the aim away and level)
	local function placed(msg: { [string]: any }, turn: boolean)
		-- (1) the body, (2) the number, (3) the look (a respawn's only)
		local place = port.place
		if place then
			place(msg.x, msg.y, msg.z, msg.yaw)
		end
		seat.place = msg.place
		seat.x, seat.y, seat.z = msg.x, msg.y, msg.z
		moveAcc = SEND -- the server hears of the new place in the next frame
		walked = 0
		fallSpeed = 0
		local look = port.look
		if turn and look and tuning.turnLook then
			local ex, ey, ez = Body.eyePoint(msg.x, msg.y, msg.z, seat.c)
			look(ex, ey, ez, msg.yaw)
			turnLook = { ex, ey, ez, msg.yaw }
			turnFrames = 2
		end
	end

	-- This seat is slot `id`: told by "state" (msg.you), and sooner by "paintball_watch", which names
	-- every slot's user. The seats are dealt again at every new match, and the roster's message is the
	-- one the server sends before it places anybody.
	iAm = function(id: number, team: number?)
		seat.you = id
		local show = opts.show()
		if show then
			show.you = id
		end
		if team then
			setTeam(team)
		end
	end

	-- A placement of your own that makes you whole: (4) a full magazine with no reload running, the
	-- ramp at 0, the legs back, protected.
	local function respawned(msg: { [string]: any }, now: number)
		placed(msg, true)
		-- (the server's doing, as the server lane does it: a respawn moves the pose idleness is measured
		-- from and does not restart the count; a correction moves neither, so the body's next Move from
		-- where it was put back is judged against the pose the count began at, here as there)
		idleX, idleY, idleZ, idleYaw, idlePitch = msg.x, msg.y, msg.z, msg.yaw, 0
		seat.mag.rounds = R.magazine
		seat.mag.reloadDoneAt = nil
		table.clear(unacked)
		endSprint(now)
		seat.held = nil
		if seat.out then
			ctx.sound("paintball.back", tuning.volBack)
		end
		seat.out = false
		seat.safeUntil = msg.at
		if not seat.legs then
			seat.legs = true
			ctx.controls(true)
		end
	end

	-- The placements kept while the slot was not known: yours is obeyed, the rest are dropped.
	flush = function(now: number)
		if seat.you ~= 0 and next(early) ~= nil then
			local waiting = early[seat.you]
			table.clear(early)
			if waiting then
				respawned(waiting, now)
			end
		end
	end

	function seat.onMessage(self: Seat, msg: { [string]: any }, _watched: any?)
		local now = clock()
		local kind = msg.kind
		if kind == "paintball_watch" then
			local me = if port.user then port.user() else 0
			if me ~= 0 and type(msg.slots) == "table" then
				for _, slot in msg.slots :: { any } do
					if slot.user == me and slot.bot ~= true then
						if slot.id ~= self.you or slot.team ~= self.team then
							iAm(slot.id, slot.team)
						end
						flush(now)
						break
					end
				end
			end
		elseif kind == "paintball_respawn" then
			if self.you == 0 or self.phase == "ended" then
				-- This seat does not know its slot yet (the roster is on its way), or still has the end
				-- card up: nobody is placed during an end card, so this is the NEXT match's, whose seats
				-- are dealt afresh. Kept until the roster or the state of that match says which is yours.
				if type(msg.id) == "number" then
					early[msg.id] = msg
				end
			elseif msg.id == self.you then
				respawned(msg, now)
			end
		elseif kind == "paintball_correct" then
			placed(msg, false)
			say(Contract.textFor(tostring(msg.why)), now)
		elseif kind == "paintball_tag" then
			if type(msg.scores) == "table" then
				self.scores = { msg.scores[1] or 0, msg.scores[2] or 0 }
			end
			local by, id = self.slots[msg.by], self.slots[msg.id]
			if by then
				by.tags = msg.tags
			end
			if id then
				id.outs = msg.outs
			end
			local mine = msg.by == self.you or msg.id == self.you
			feedLine(`{nameOf(msg.by)} tagged {nameOf(msg.id)}`, if by then by.team else 0, mine, now)
			if msg.by == self.you then
				-- THE hit marker and hit sound: only ever on the server's word (and who it was, in words)
				self.hitAt = now
				ctx.sound("paintball.tag", tuning.volTag)
				say(`You tagged {nameOf(msg.id)}`, now)
			end
			if msg.id == self.you then
				self.out = true
				self.outUntil = msg.at
				self.outBy = msg.by
				local show = opts.show()
				local from = if show then show.puppets[msg.by] else nil
				self.tagFrom = if from then { x = from.x, y = from.y, z = from.z } else nil
				self.goggleAt = now
				self.held = nil
				endSprint(now)
				if self.legs and self.phase ~= "ended" then
					self.legs = false
					ctx.controls(false)
				end
				ctx.sound("paintball.tagged", tuning.volTagged)
			end
		elseif kind == "paintball_ack" then
			-- the balls sent since that click are still the client's own to count
			local at = table.find(unacked, msg.shot)
			if at then
				for _ = 1, at do
					table.remove(unacked, 1)
				end
			end
			local since = #unacked
			local rounds = msg.rounds
			local reloadAt: number? = msg.reloadAt
			if reloadAt ~= nil and now >= reloadAt then
				rounds, reloadAt = R.magazine, nil
			end
			local mag = self.mag
			settle(now)
			if since == 0 then
				if reloadAt ~= nil then
					-- a reload the server reports is taken over
					if mag.reloadDoneAt == nil then
						self.reloadFrom = now
					end
					mag.rounds = rounds
					mag.reloadDoneAt = reloadAt
				elseif mag.reloadDoneAt == nil then
					mag.rounds = rounds
				elseif msg.ok ~= true and rounds > 0 and mag.rounds == 0 then
					-- the automatic reload began on a ball the server did not let go: it is not running
					mag.rounds = rounds
					mag.reloadDoneAt = nil
				end
				-- (a reload of the player's own, pressed since that click, runs on: "paintball_reload"
				-- or a refusal of the verb says what became of it)
			elseif mag.reloadDoneAt == nil then
				mag.rounds = math.max(0, rounds - since)
			end
			local show = opts.show()
			if show then
				show:verdict(msg.shot, msg.ok == true, msg.ball)
			end
			if msg.ok ~= true then
				say(Contract.textFor(tostring(msg.why)), now)
			end
		elseif kind == "paintball_reload" then
			if msg.id == self.you and type(msg.at) == "number" and msg.at > now then
				if self.mag.reloadDoneAt == nil then
					rattle(now)
				end
				self.mag.reloadDoneAt = msg.at
			end
		elseif kind == "paintball_tuned" then
			-- the owner's tuning, in words (OwnerTune; only the owner is sent this)
			local text = tostring(msg.text)
			say(text, now)
			feedLine(text, self.team, true, now)
		elseif kind == "paintball_say" then
			local slot = self.slots[msg.id]
			if slot and slot.team == self.team and msg.id ~= self.you then
				local line = (Contract.LINES :: { [string]: string })[msg.line]
				if line then
					local text = if msg.line == "floor" then string.format(line, msg.n or 1) else line
					if msg.line == "floor" and self.floor > 0 and msg.n ~= nil then
						-- said from where the reader stands: up or down, and how far (the review)
						text ..= ` ({SeatCore.relative(msg.n - self.floor)})`
					end
					feedLine(`{nameOf(msg.id)}: {text}`, slot.team, false, now)
				end
			end
		end
	end

	function seat.onRefused(self: Seat, msg: { [string]: any })
		-- (the words are on screen already) a reload the server did not start is not running
		if msg.verb == "reload" and self.mag.rounds > 0 then
			self.mag.reloadDoneAt = nil
		end
	end

	function seat.input(self: Seat, action: Action, down: boolean)
		local now = clock()
		if action == "fire" then
			self.trigger = down
			if not down and self.autoHeld then
				self.held = nil -- (the trigger let go before its next ball: nothing more leaves)
			end
			self.autoHeld = false
			if down then
				sample()
				endSprint(now) -- the press itself ends the sprint
				self.held = now
				tryFire(now)
			end
		elseif action == "reload" then
			if down and self:live(now) and not self.out and self.place ~= 0 then
				settle(now)
				if Magazine.reload(self.mag, now) then
					ctx.send("reload", { now })
					rattle(now)
				end
			end
		elseif action == "crouch" then
			if down ~= self.wantCrouch then
				flipPrev, flipLast = flipLast, now
				tell = true
			end
			self.wantCrouch = down
			if down then
				endSprint(now)
			end
		elseif action == "sprint" then
			self.wantSprint = down
		elseif action == "scores" then
			self.board = down
			bar()
		elseif action == "leave" or action == "side" then
			-- with the scoreboard, in the briefing and at the end card: never by a slip in the middle of a fight
			if down and (self.board or self.phase ~= "live") and now - verbAt > tuning.verbSecs then
				verbAt = now
				ctx.send(action)
			end
		end
	end

	function seat.step(self: Seat, dt: number)
		local now = clock()
		self.now = now
		-- the turn of the look: one rendered frame, then the stock camera has it back. (The hold is
		-- asked for again in its first frame: whichever of this step and the framework's own camera
		-- step runs first, the framework's writes the placed CFrame as a cut both times and never eases.)
		if turnFrames > 0 then
			turnFrames -= 1
			local again = turnLook
			if turnFrames == 0 then
				turnLook = nil
				ctx.releaseCamera()
			elseif again and port.look then
				port.look(again[1], again[2], again[3], again[4])
			end
		end
		local show = opts.show()
		if show then
			show.you = self.you
		end
		local wasAir, wasY = self.air, self.y
		local has = sample()
		if has and self.air and not wasAir then
			tell = true -- the feet left the floor: the server allows the jump's height only once it is told
		end
		-- the landing dip
		if has and dt > 0 then
			local vy = (self.y - wasY) / dt
			if self.air then
				fallSpeed = math.max(0, -vy)
			elseif wasAir then
				self.dip = math.min(tuning.landDipMax, self.dip + fallSpeed * tuning.landDip)
				fallSpeed = 0
			end
		end
		self.dip *= math.exp(-tuning.landRecover * dt)
		-- crouch, then the sprint ramp (a crouching body does not sprint)
		self.c = Body.crouchStep(self.c, self.wantCrouch and not self.out, dt, self.feel)
		local push = if port.push then port.push() else 1
		-- a sprint runs only AHEAD, within Tuning.sprintCone of the way the view faces: no backpedalling or
		-- strafing away from a fight at sprint pace
		local ahead = if port.forward then port.forward() else push
		local sprinting = self.wantSprint
			and not self.wantCrouch
			and self.c <= 0
			and self.held == nil
			and not self.out
			and push >= tuning.sprintMove
			and ahead >= push * math.cos(tuning.sprintCone)
			and now >= self.firedAt + tuning.sprintAfterShot
		if sprinting then
			self.k = math.min(1, self.k + dt / Body.SPRINT_RAMP_SECS)
		else
			endSprint(now)
		end
		ctx.pace(Body.pace(self.c, self.k, self.feel), false)
		if port.eye then
			port.eye(Body.eye(self.c) - Body.STAND_EYE - self.dip)
		end
		if port.fov then
			port.fov(tuning.sprintFov * self.k)
		end
		-- your own storey (a stair's middle landing counts as the floor it is nearer)
		if has then
			self.floor = SeatCore.floorOf(self.y)
		end
		-- your own room: safe, and no firing
		local room = arena.spawnRooms[self.team]
		self.inRoom = has and room ~= nil and ArenaModule.inRoom(room, self.x, self.y + 0.1, self.z)
		self.nearRoom = has and nearRoom(M.room)
		-- the match goes live under a player who stood through its briefing: the horn
		local liveNow = self.place ~= 0 and self:live(now)
		if liveNow and not wasLive and briefEnds ~= nil then
			ctx.sound("paintball.go", tuning.volGo)
		end
		wasLive = liveNow
		-- idle: moving, turning and firing are what the server counts as being there. Not while out: no Move
		-- is sent then, so the server sees none of it (and the body may be put anywhere while it waits)
		if has and not self.out then
			local ix, iy, iz = self.x - idleX, self.y - idleY, self.z - idleZ
			local moved = ix * ix + iy * iy + iz * iz > IDLE_STUDS * IDLE_STUDS
			local turned = math.abs(self.yaw - idleYaw) > IDLE_RAD or math.abs(self.pitch - idlePitch) > IDLE_RAD
			if moved or turned then
				idleX, idleY, idleZ, idleYaw, idlePitch = self.x, self.y, self.z, self.yaw, self.pitch
				self.activeAt = now
			end
		end
		if not liveNow then
			self.activeAt = now -- (the server counts live play only)
		end
		-- the trigger held down: the next ball is pressed for as soon as the marker would take it (a press
		-- the magazine would only answer with the dry click, or that something else drops, is not made)
		if self.trigger and tuning.holdRepeats and self.held == nil then
			local verdict = gate(now)
			if verdict == "go" or verdict == "hold" then
				self.held = now
				self.autoHeld = true
			end
		end
		-- a waiting press
		tryFire(now)
		settle(now)
		-- the pose, SEND_HZ times a second; at once, ahead of its turn, when the stance changed
		moveAcc += dt
		tellBudget = math.min(TELL_MOST, tellBudget + dt * TELL_RATE)
		if tell and tellBudget >= 1 then
			tell = false
			if sendPose(now) then
				tellBudget -= 1
				moveAcc = 0
			end
		elseif moveAcc >= SEND - 1e-6 then
			moveAcc = math.min(moveAcc - SEND, SEND)
			tell = false
			if has then
				sendPose(now)
			end
		end
		-- your own footsteps: loud running, soft walking, silent crouched
		if has and not self.air and not self.out then
			local dx, dz = self.x - lastX, self.z - lastZ
			local moved = math.sqrt(dx * dx + dz * dz)
			if moved == moved and moved < 6 then
				walked += moved
				local stride = if self.k > 0 then tuning.stepSprint else tuning.stepWalk
				if walked >= stride then
					walked = 0
					if self.c < 0.5 then
						ctx.sound("paintball.step", if self.k > 0 then tuning.stepLoud else tuning.stepQuiet)
					end
				end
			end
		end
		lastX, lastZ = self.x, self.z
		-- the feed and the note fade by themselves
		while self.feed[1] and now - self.feed[1].at > tuning.feedSecs do
			table.remove(self.feed, 1)
		end
		if self.note ~= "" and now - self.noteAt > tuning.noteSecs then
			self.note = ""
		end
		bar()
	end

	function seat.stop(self: Seat)
		if turnFrames > 0 then
			turnFrames = 0
			ctx.releaseCamera()
		end
		self.held = nil
		self.trigger = false
		if not self.legs then
			self.legs = true
			ctx.controls(true)
		end
		if port.curtains then
			port.curtains(nil)
		end
		if port.eye then
			port.eye(0)
		end
		if port.fov then
			port.fov(0)
		end
		if port.lock then
			port.lock(false)
		end
		ctx.pace(nil, nil)
	end

	if port.lock then
		port.lock(true)
	end
	return seat
end

return SeatCore
