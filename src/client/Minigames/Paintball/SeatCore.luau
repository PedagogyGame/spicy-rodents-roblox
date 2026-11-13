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
--              delay objects to is HELD and leaves the instant it may; anything else drops it. The
--              ball is predicted on the show from the very numbers that went on the wire (the f32
--              origin and direction, the f64 birth time), so the server's ball and this one are the
--              same curve.
--   the pips   the predicted Magazine, put right by "paintball_ack" (its rounds minus the balls sent
--              since), by a respawn, and once by the first "state".
--   moving     the sprint ramp k (up over Body.SPRINT_RAMP_SECS while sprint is wanted, the body stands
--              and the stick is pushed; to 0 at once otherwise) and the crouch fraction c
--              (Body.crouchStep), handed to ctx.pace and to the eye every frame; Wire.Move
--              Clock.SEND_HZ times a second, never before the first placement nor while out.
--   placements pivot the body, take the number, turn the look for one frame, and for a respawn a full
--              magazine, the legs back and the protection.
-- Interface: new(ctx, opts) -> Seat; types Port, Opts, Seat, Feed. Seat: the framework's controller
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
--   place     pivot the body to a feet point and yaw (a placement)
--   look      begin the one-frame turn of the look: a camera hold at this eye point along this yaw
--   muzzle    where the marker's muzzle is drawn (the ball is drawn leaving it)
--   eye       the eye's height against a standing eye (0 standing, negative crouched or dipping)
--   fov       degrees the view is widened by
--   curtains  the team whose curtains are solid on this screen (nil: none)
--   lock      first person on (the CameraZone attribute) and the match's jump height; off puts both back
export type Port = {
	pose: (() -> (number?, number, number, number, number, number, boolean))?,
	push: (() -> number)?,
	place: ((x: number, y: number, z: number, yaw: number) -> ())?,
	look: ((x: number, y: number, z: number, yaw: number) -> ())?,
	muzzle: (() -> (number?, number, number))?,
	eye: ((offset: number) -> ())?,
	fov: ((extra: number) -> ())?,
	curtains: ((team: number?) -> ())?,
	lock: ((on: boolean) -> ())?,
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
	inRoom: boolean, -- standing in your own spawn room
	legs: boolean, -- false while the legs are taken
	-- the HUD's own
	board: boolean, -- the scoreboard is asked for
	feed: { Feed },
	hitAt: number, -- the server said you tagged someone
	goggleAt: number, -- you were tagged
	note: string,
	noteAt: number,
	now: number, -- the shared clock of the last step
	onState: (self: Seat, msg: { [string]: any }) -> (),
	onMessage: (self: Seat, msg: { [string]: any }, watched: any?) -> (),
	onRefused: (self: Seat, msg: { [string]: any }) -> (),
	input: (self: Seat, action: Action, down: boolean) -> (),
	step: (self: Seat, dt: number) -> (),
	stop: (self: Seat) -> (),
	live: (self: Seat, now: number) -> boolean,
	ready: (self: Seat, now: number) -> boolean, -- would a press leave as a ball this instant?
	markerUp: (self: Seat, now: number) -> number, -- 0 down (sprinting) .. 1 up
	reloading: (self: Seat, now: number) -> number?, -- 0..1 through the running reload; nil: none
}

local SeatCore = {}

local R = Contract.Rules
local M = Contract.MARGIN
local BIT = Wire.BIT
local SEND = 1 / Clock.SEND_HZ
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
	local turnFrames = 0 -- frames of the look's hold still to run
	local turnLook: { number }? = nil
	local walked = 0
	local fallSpeed = 0
	local lastBar = ""
	local verbAt = -math.huge
	local hasPose = false
	local lookX, lookY, lookZ = 0, 0, -1
	local lastX, lastZ = 0 / 0, 0 / 0
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
		legs = true,
		board = false,
		feed = {},
		hitAt = -math.huge,
		goggleAt = -math.huge,
		note = "",
		noteAt = -math.huge,
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

	local function nearRoom(): boolean
		for _, room in arena.spawnRooms do
			if ArenaModule.inRoom(room, seat.x, seat.y + 0.1, seat.z, M.room) then
				return true
			end
		end
		return false
	end

	-- What stands in a press's way at `now`: nothing ("go"), only the marker's own rhythm ("hold"),
	-- an empty or reloading marker ("dry"), or something else ("drop", with the words to show).
	local function gate(now: number): (string, string?)
		if not seat:live(now) or seat.you == 0 or seat.place == 0 then
			return "drop", nil
		elseif seat.out then
			return "drop", nil
		elseif now < seat.safeUntil + M.gate then
			return "drop", "Protected: you cannot fire yet"
		elseif nearRoom() then
			return "drop", "No firing from a spawn room"
		end
		local mag = seat.mag
		Magazine.update(mag, now)
		local reloading = mag.reloadDoneAt
		if reloading ~= nil then
			return if reloading - now <= M.click then "hold" else "dry", nil
		elseif mag.rounds <= 0 then
			return "dry", nil
		elseif seat.k > 0 or now < seat.sprintEndedAt + Body.SPRINT_FIRE_DELAY then
			return "hold", nil
		elseif now < mag.nextFireAt then
			return "hold", nil
		end
		return "go", nil
	end

	function seat.ready(_self: Seat, now: number): boolean
		return hasPose and (gate(now)) == "go"
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

	local function rattle(now: number)
		seat.reloadFrom = now
		ctx.sound("paintball.reload", tuning.volReload)
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
			link.send("Paintball.Fire", payload)
		end
		table.insert(unacked, shot)
		seat.fired += 1
		seat.firedAt = now
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
				mz
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

	function seat.onState(self: Seat, msg: { [string]: any })
		local now = clock()
		if type(msg.you) == "number" then
			self.you = msg.you
			local show = opts.show()
			if show then
				show.you = msg.you
			end
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
				end
				self.phase, self.endsAt = game.phase, game.endsAt
			end
		end
		if type(view) == "table" then
			self.result = view.result
			if view.phase == "done" then
				self.phase = "ended"
				self.held = nil
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
		bar()
		if self.you ~= 0 and next(early) ~= nil then
			local waiting = early[self.you]
			table.clear(early)
			if waiting and self.place == 0 then
				self:onMessage(waiting, nil)
			end
		end
	end

	local function placed(msg: { [string]: any })
		-- (1) the body, (2) the number, (3) the look
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
		if look and tuning.turnLook then
			local ex, ey, ez = Body.eyePoint(msg.x, msg.y, msg.z, seat.c)
			look(ex, ey, ez, msg.yaw)
			turnLook = { ex, ey, ez, msg.yaw }
			turnFrames = 2
		end
	end

	function seat.onMessage(self: Seat, msg: { [string]: any }, _watched: any?)
		local now = clock()
		local kind = msg.kind
		if kind == "paintball_respawn" then
			if self.you == 0 then
				-- (the roster's "state" is still on its way: kept until it says which slot is yours)
				if type(msg.id) == "number" then
					early[msg.id] = msg
				end
				return
			elseif msg.id ~= self.you then
				return
			end
			placed(msg)
			-- (4) a full magazine with no reload running, the ramp at 0, the legs back, protected
			self.mag.rounds = R.magazine
			self.mag.reloadDoneAt = nil
			table.clear(unacked)
			endSprint(now)
			self.held = nil
			self.out = false
			self.safeUntil = msg.at
			if not self.legs then
				self.legs = true
				ctx.controls(true)
			end
		elseif kind == "paintball_correct" then
			placed(msg)
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
				-- THE hit marker and hit sound: only ever on the server's word
				self.hitAt = now
				ctx.sound("paintball.tag", tuning.volTag)
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
				if self.legs then
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
			Magazine.update(mag, now)
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
		elseif kind == "paintball_say" then
			local slot = self.slots[msg.id]
			if slot and slot.team == self.team and msg.id ~= self.you then
				local line = (Contract.LINES :: { [string]: string })[msg.line]
				if line then
					local text = if msg.line == "floor" then string.format(line, msg.n or 1) else line
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
			if down then
				sample()
				endSprint(now) -- the press itself ends the sprint
				self.held = now
				tryFire(now)
			end
		elseif action == "reload" then
			if down and self:live(now) and not self.out and self.place ~= 0 then
				if Magazine.reload(self.mag, now) then
					ctx.send("reload", { now })
					rattle(now)
				end
			end
		elseif action == "crouch" then
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
			if down and (self.board or self.phase ~= "live") and now - verbAt > 0.3 then
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
		local sprinting = self.wantSprint
			and not self.wantCrouch
			and self.c <= 0
			and self.held == nil
			and not self.out
			and push >= tuning.sprintMove
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
		-- your own room: safe, and no firing
		local room = arena.spawnRooms[self.team]
		self.inRoom = has and room ~= nil and ArenaModule.inRoom(room, self.x, self.y + 0.1, self.z)
		-- a waiting press
		tryFire(now)
		Magazine.update(self.mag, now)
		-- the pose, SEND_HZ times a second
		moveAcc += dt
		if moveAcc >= SEND - 1e-6 then
			moveAcc = math.min(moveAcc - SEND, SEND)
			if has and link and self.place ~= 0 and not self.out and self.you ~= 0 then
				moveSeq = (moveSeq + 1) % 65536
				local bits = (if self.wantCrouch then BIT.crouch else 0)
					+ (if self.k > 0 then BIT.sprint else 0)
					+ (if self.air then BIT.air else 0)
				link.send(
					"Paintball.Move",
					BufferCodec.encode(Wire.Move, {
						t = now,
						seq = moveSeq,
						x = self.x,
						y = self.y,
						z = self.z,
						yaw = self.yaw,
						pitch = self.pitch,
						bits = bits,
						place = self.place,
					})
				)
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
