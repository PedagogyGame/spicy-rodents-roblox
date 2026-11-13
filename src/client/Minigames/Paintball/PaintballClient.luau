--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Paintball.PaintballClient
-- The paintball client (checklist PB-1, PB-2, PB-4, PB-7, PB-8, PB-9; brief v2 §14): everything behind
-- paintball's ClientGame in the minigame framework (Client/Minigames/Games/Paintball hands the
-- framework's `watch` and `new` to this module): first person, the marker, firing and reloading with
-- a predicted ball, sprint and crouch, the HUD, the other bodies, balls and splats, the sounds.
-- OWNED BY THE CLIENT LANE, with the whole of Client/Minigames/Paintball/. `watch`, `new`, `link`
-- and the methods keep the names and signatures of the contract's stub. It does not edit Camera/,
-- Controllers/, Input/, Possession/, UI/ or the framework (MinigameClient, ClientGame, MinigameUI).
-- THE FILES OF THIS FOLDER
--   Tuning     the one table of the client's feel numbers, each with what it does to the hands
--   ShowCore   the show, headless: puppets, balls, the two splat pools, cues, the predicted ball
--   SeatCore   the seat, headless: the gates and the held click, the magazine, sprint and crouch,
--              the pose stream, placements, tagged out and back
--   World      the show drawn (puppets, balls, splats; the real bodies hidden; the cues played)
--   Self       the player's own body: its pose, the eye, the lock, placements, the curtains
--   Marker     the marker in view
--   Hud        the crosshair, the pips, the clock and scores, the feed, the scoreboard, touch buttons
--   Controls   keyboard and mouse, gamepad, touch: each device's keys into Seat.input
--   this file  joins them: one show on a screen, one seat, ONE render step that runs the show, then
--              the seat, then draws (so the seat's ball is tested against this frame's puppets)
--
-- TWO PARTS, because a player in the lobby watches a match they are not in.
--   THE SHOW   what anyone in the audience sees: every slot as a puppet, the balls, the splats, the
--              sounds in space. It starts when the server says "paintball_watch" (ClientGame.watch
--              calls watch(msg, place) for it, seated or not) and ends on "paintball_unwatch". There
--              is one show on a screen; it listens to the three stream remotes through the Link.
--   THE SEAT   what a player in the match adds: new(ctx) is the framework's controller for the game
--              (made when the server says "joined", stopped however the game closes). It sends the
--              pose and the click, predicts, draws the marker and the HUD.
-- THE CORE IS HEADLESS: both parts are state machines fed by messages, stream buffers and the
-- player's actions, with the clock, the Link and everything on screen injected (Deps), so the lane
-- proves them under Lune; what touches Instances sits behind `screen` (Deps.screen: nil is the real
-- screen wherever there is an engine and none under bare Lune; false is headless everywhere).
-- THE FEEL: every number of Contract.FEEL the client uses (the ball's speed and drop, the fire
-- interval, the reload, the sprint multiple, the crouch time) is THIS MATCH'S, from "paintball_watch"
-- (show.feel) and the Extras of "state" (seat.feel); never Contract.FEEL or Shared/Paintball/Config.
-- The seat's Magazine is rebuilt when the feel it was built with changes.
--
-- WHAT IT DOES, AND WITH WHICH PART OF THE CONTRACT (Shared/Minigames/Paintball)
--   the frame    Arena.placeOf(place) with the site's place (ClientGame.Ctx.place for the seat, the
--                `place` handed to watch for the show) puts the arena in the world: Arena.toWorld /
--                toLocal. Everything on the wire is in the arena frame.
--   first person the seat sets its own body's "CameraZone" attribute to "lockFirstPerson" while the
--                game is open, and clears it in stop(): the existing Client/Possession and
--                Camera/CameraPolicy then lock first person and release it. Seen through that
--                camera: the marker, its sway and dip, the crosshair, the sprint widening of view
--                (FieldOfView). The camera's CFrame is written in ONE case only, THE TURN OF THE LOOK.
--   a placement  the server put YOUR body somewhere: "paintball_respawn" with id = you (the
--                briefing, your join, back from being out, a change of side) or "paintball_correct".
--                In this order, in the frame the message arrives: (1) pivot your own body to the
--                placed feet point and yaw yourself (you are its network owner; the message and the
--                server's own teleport do not arrive in a fixed order, and a Move must never carry the
--                new placement number from the old place); (2) seat.place = msg.place, which every
--                Move from now on carries; (3) FOR A RESPAWN ONLY, THE TURN OF THE LOOK: ctx.camera(a
--                CFrame at your eye looking along the placed yaw, level, nil, true) for one rendered
--                frame, then
--                ctx.releaseCamera(): the stock first-person camera carries on from the CFrame it
--                finds, so you come back looking out of the spawn room, not at the wall you were
--                tagged against. (That the stock camera does carry on from it is to be seen once in
--                Studio; if it does not, the lane leaves step 3 out and nothing else changes.) A
--                correction never turns the look: it comes mid-fight with the yaw of the last pose the
--                server took (up to a second old), and the player's own yaw and pitch are kept.
--                Nothing else here writes the camera's CFrame (the rig fails a case that does so
--                outside a hold). (4) for a respawn: the predicted magazine is full with no reload
--                running, the sprint ramp is 0, the legs are yours again (ctx.controls(true)), and
--                you are protected until msg.at.
--   moving       the body is the possessed R15 Humanoid body under the stock controls. The pace goes
--                through ctx.pace(Body.pace(crouch, k, feel), false) every frame (the framework's own
--                Shift is off); k is the sprint ramp of Body, "sprint and the marker": up over
--                Body.SPRINT_RAMP_SECS while sprint is wanted and the body stands, to 0 AT ONCE when
--                it is not, on a fire press, on a crouch and on being tagged.
--                Humanoid.JumpHeight = Body.JUMP_HEIGHT while seated, put back in stop(). Crouch is
--                the crouch fraction eased with Body.crouchStep(c, want, dt, feel) and the camera
--                lowered to Body.eye(crouch) with Humanoid.CameraOffset; nothing about the Humanoid's
--                collision changes. Clock.SEND_HZ times a second: Wire.Move through the Link (t =
--                the shared clock in the frame it is sampled, the REAL feet point through
--                Arena.toLocal, yaw and pitch from the camera's look through Arena.dirToLocal and
--                Body.yawPitch, BIT.crouch = crouch is wanted, BIT.sprint = k > 0, BIT.air, and
--                place). No Move is sent before your first placement (seat.place = 0: you are still at
--                the arena door) nor while you are tagged out.
--   firing       one click, one ball, never hitscan. A fire press asks for a ball; it leaves in the
--                first frame in which ALL of these hold (each is the client's side of Contract.MARGIN,
--                stricter than the server's, so the server never refuses a ball that was drawn):
--                  the phase is "live" (and now >= the briefing's endsAt + MARGIN.gate);
--                  you are not out, and now >= the `at` of your last respawn + MARGIN.gate;
--                  k has been 0 for Body.SPRINT_FIRE_DELAY (the press itself drops k to 0);
--                  your feet are not inside a spawn room nor within MARGIN.room of one
--                  (Arena.inRoom(room, x, y + 0.1, z, MARGIN.room), both rooms);
--                  Magazine.fire(mag, now) says yes.
--                A PRESS THAT CANNOT LEAVE AT ONCE IS HELD when all that stands in its way is the fire
--                interval, a reload with no more than MARGIN.click left, or the sprint delay: it
--                leaves in the first frame it may, stamped with that frame's time. One press is held
--                (a later press replaces it); it is dropped if anything else comes to stand in its
--                way. So six clicks a second fire four balls, not three. A press with the magazine
--                empty or reloading for longer than that is the dry click and nothing else.
--                When the ball leaves: shot += 1 (from 1); send Wire.Fire (shot, vt =
--                Clock.viewTime(show.view, now), ft = now, origin = Body.eyePoint of your own feet and
--                crouch, the unit look) and in the same frame draw the ball: Ballistics.position with
--                the feel's speed and drop from the eye line. EVERY FRAME ITS STEP IS TESTED the way
--                the server tests it: arena.sweep, and Hit.body against every puppet of the OTHER
--                team where it is drawn this frame, passing over a puppet whose bits say out or safe
--                and one drawn inside its own spawn room. The first thing along the step ends the
--                ball. On a wall: your splat is drawn there AT ONCE (predicted). On a puppet: a small
--                puff of paint and nothing else: the hit marker, the hit sound, the score and the
--                splat on the body wait for "paintball_tag".
--                "paintball_ack" { shot, ok, rounds, reloadAt }: THE PIPS are ack.rounds minus the
--                balls you have sent since that shot; a reload the server reports is taken over
--                (reloadAt). ok = false: that ball, if it still flies, and its predicted splat are
--                removed, and the why is shown. The Extras of "state" (rounds, reloadAt, shot) are
--                applied once, on the first "state" after joining, never again.
--                R reloads: ctx.send("reload", { now }), predicted with Magazine.reload.
--   tagged out   "paintball_tag" with id = you: the legs are taken (ctx.controls(false)), k is 0, a
--                held press is dropped, Moves stop. The HUD says who tagged you (the name of slot
--                `by`), points to where from (the direction to by's puppet), and counts down to `at`;
--                the louder sound, a splat on the goggles. Your placement ("paintball_respawn" for
--                you) ends it.
--   other bodies every slot but its own is a PUPPET the show builds and moves, people and bots alike,
--                drawn at Clock.viewTime(view, now) by straight-line interpolation between the two
--                snapshots either side (Wire.decodeSnap, Wire.between; held at the newest, never run
--                ahead; Clock.observe on each arrival); its bits are those of the OLDER of the two.
--                A puppet never collides and is not found by a raycast. BIT.out: the raised hand for a
--                second, then the puppet is not drawn until the bit clears. The replicated REAL
--                bodies of the people in the match are hidden on this screen while the show is on
--                (LocalTransparencyModifier): "paintball_watch" lists who is in which slot, and a
--                person's `user` is the DriverUserId attribute of the body to hide. So nobody is drawn
--                twice and what is aimed at is what the server rewinds to. While seated, the parts
--                named Arena.CURTAIN .. (the other team) have CanCollide set true on this screen
--                (Arena, "curtains"), and false again in stop().
--   balls        Wire.Shot records: other slots' balls (never your own: you drew it), drawn with
--                Ballistics from their birth time with the feel's drop, with the marker's pop at the
--                origin (muffled through a floor).
--   splats       Wire.Splat records, kept in TWO POOLS exactly as Wire says (the walls' newest
--                Rules.splatPool by seq; each slot's newest Rules.bodySplats; a slot's emptied when
--                its occupant changes in "paintball_watch"; both emptied when the match number
--                changes, in "paintball_watch" and in every snapshot's head). Wall splats at the point
--                on the face; body splats on the puppet's part (Body.partAt) at the Wire.fromBody
--                offset; team colours from Contract.TEAMS, a few shapes and sizes picked from the ball
--                id. A wall record with by = you REPLACES your nearest predicted splat within 1.5
--                studs instead of adding a second; a predicted splat that no record has replaced
--                after a second is removed.
--   sounds       your marker's pop on your own click; others' from Shot records; a splat from Splat
--                records; the reload rattle of your own from your prediction and of every other slot
--                from the rising edge of BIT.reload in the snapshots (the server sends
--                "paintball_reload" to the reloader alone); "paintball_tag": the hit marker and hit
--                sound when `by` is you, the louder one when `id` is you.
--   HUD          five pips, the reload, the clock counted down from view.game.endsAt, both scores
--                (from "paintball_tag" as they come, put right by "state"), the tagged-out and
--                protection timers, "safe" while you stand in your own spawn room, the controls card
--                in the briefing, the scoreboard (with it Leave and Change sides: ctx.setButtons; the
--                bar is empty while playing, so the mouse stays the look), the framework's end card at
--                the end (ClientGame.endCard).
-- THE CONTROLS, PER DEVICE (fixed here; the lane's input code turns each into Seat.input calls, and
-- reads the keys itself: of the framework's, only Q and gamepad B are taken, by the game's `keys`)
--   keyboard and mouse   WASD move, the mouse looks, left button fire, R reload, Space jump; Shift
--                sprints while HELD; C or Left Ctrl crouches while HELD; G shows the scoreboard while
--                HELD, and with it the Leave and Change sides buttons.
--   gamepad      sticks move and look, R2 fire, X reload, A jump; B crouch is a TOGGLE (a hold would
--                take the thumb off the look); L3 sprint is a TOGGLE that ends on a fire press, on a
--                crouch and when the stick is let go; View (ButtonSelect) shows the scoreboard while
--                HELD, and while it is held Y leaves and DPad Up changes sides (the board says so).
--                View is also the engine's switch into picking buttons with the pad: that is off while
--                seated, and a pick is let go while the board is held and in live play (Controls).
--                Sprint runs only with the stick (or the keys) pushed ahead (Tuning.sprintCone).
--   touch        the thumbstick moves, a drag on the right half looks; sprint starts on a FULL push
--                of the stick and lasts until the stick comes back under half way, a fire press or a
--                crouch; FIRE at the lower right DOES NOT SINK ITS TOUCH (a drag that starts on it
--                turns the view, so a thumb can track and fire) and a second FIRE sits above the
--                stick for the left thumb; RELOAD; CROUCH is a TOGGLE; SCORES opens and closes the
--                scoreboard, which carries Leave and Change sides. (That a non-sinking button leaves
--                the drag to the stock camera is to be seen once on a device; if it does not, the
--                left FIRE is the one to use while tracking.)
--   Seat.input(action, down): "crouch", "sprint" and "scores" are STATES (down = it is wanted now:
--   the device code turns a toggle into the state); "fire", "reload", "leave" and "side" are PRESSES
--   (down = true). "leave" sends the framework's "leave"; "side" sends the verb "side".
-- Interface: watch(msg, place) -> Show? (the framework's `watch`); new(ctx, deps?) -> Seat (the
--   framework's `new`); show() -> Show? (the one on this screen); link() -> Link? (the engine's:
--   written, not a stub);
--   types Link, Action, Deps, Show, Seat

local Import = require("../../Import")
local ArenaData: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.ArenaData)) =
	Import.shared("Minigames/Paintball/ArenaData")
local ClientGame = require("../ClientGame")
local Controls = require("./Controls")
local Hud = require("./Hud")
local Marker = require("./Marker")
local SeatCore = require("./SeatCore")
local SelfPort = require("./Self")
local ShowCore = require("./ShowCore")
local Tuning = require("./Tuning")
local World = require("./World")

type Arena = typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Arena).T.Arena)

-- The client's link to paintball's own remotes (Wire.REMOTES).
--   send    a buffer up: "Paintball.Move" (Wire.Move), "Paintball.Fire" (Wire.Fire)
--   listen  hear a buffer coming down: "Paintball.Snap", "Paintball.Shot", "Splat"; returns the undo
export type Link = SeatCore.Link

-- What the player can do (see THE CONTROLS). "crouch", "sprint" and "scores" are states; the rest
-- are presses.
export type Action = SeatCore.Action

export type Deps = {
	now: (() -> number)?, -- the shared clock; default workspace:GetServerTimeNow() (ClientGame.Ctx.stamp)
	link: Link?, -- default link(); nil: nothing is sent and no stream is heard
	arena: Arena?, -- default ArenaData.build()
	-- everything that touches Instances: nil = the real screen where there is an engine (none under
	-- bare Lune); false = headless; a SeatCore.Port = a spec's own stand-in for the player's body
	screen: any?,
	tuning: typeof(Tuning.T)?, -- default Tuning
}

-- The show: the match as anyone in the audience sees it (ShowCore.Show: arena, match, feel, place,
-- view, onWatch, onSnap, onShots, onSplats, step, stop, and what it draws).
export type Show = ShowCore.Show

-- The seat: the framework's controller for a player in the match, and what the input code drives
-- (SeatCore.Seat: ctx, you, feel, mag, shot, place, onState, onMessage, onRefused, input, step, stop).
export type Seat = SeatCore.Seat

local PaintballClient = {}

local RENDER_STEP = "SpicyPaintball"

-- What is on this screen. One show and one seat at most; `engine` is the `game` they were made
-- under (a fresh fake engine in the next spec case finds nothing left over from the last).
type Stage = {
	engine: any,
	show: Show?,
	world: World.World?,
	undo: { () -> () }, -- the show's stream listeners
	watched: boolean, -- the server has said "paintball_watch" (not a show the seat made for itself)
	seat: Seat?,
	parts: { { step: (self: any, dt: number) -> () } }, -- the seat's own drawers, in the order they run
	bound: boolean,
}

local function empty(): Stage
	return {
		engine = if game ~= nil then game else nil,
		show = nil,
		world = nil,
		undo = {},
		watched = false,
		seat = nil,
		parts = {},
		bound = false,
	}
end

local stage: Stage = empty()

local function hasEngine(): boolean
	return game ~= nil and workspace ~= nil
end

local function fresh()
	if stage.engine ~= game then
		stage = empty()
	end
end

-- The Link onto the engine's remotes (the folder ReplicatedStorage.Net that the server's Shared/Net
-- makes; tests/lib/PaintballRig puts fakes there). Nil where paintball's remotes are not to be found:
-- the game then runs with no stream, and nothing is sent.
function PaintballClient.link(): Link?
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("Net")
	if folder == nil or folder:FindFirstChild("Paintball.Move") == nil then
		return nil
	end
	return {
		send = function(remote: string, payload: buffer)
			local r = folder:FindFirstChild(remote) :: any
			if r then
				r:FireServer(payload)
			end
		end,
		listen = function(remote: string, fn: (payload: any) -> ()): () -> ()
			local r = folder:FindFirstChild(remote) :: any
			if r == nil then
				return function() end
			end
			local conn = r.OnClientEvent:Connect(fn)
			return function()
				conn:Disconnect()
			end
		end,
	}
end

local function defaultNow(): number
	return workspace:GetServerTimeNow()
end

-- ONE render step for everything of paintball's on this screen: the show first (this frame's
-- puppets), then the seat (its ball is tested against them), then what is drawn.
local function frame(dt: number)
	local show, seat = stage.show, stage.seat
	if show then
		show:step(dt)
	end
	if seat then
		seat:step(dt)
	end
	for _, piece in stage.parts do
		piece:step(dt)
	end
	local world = stage.world
	if world then
		world:step(dt)
	end
end

local function bind()
	local want = stage.show ~= nil or stage.seat ~= nil
	if not hasEngine() or want == stage.bound then
		return
	end
	stage.bound = want
	local RunService = game:GetService("RunService")
	if want then
		-- (after the camera has moved for the frame: the marker hangs off where the camera IS)
		RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 5, frame)
	else
		RunService:UnbindFromRenderStep(RENDER_STEP)
	end
end

local function openShow(deps: Deps): Show
	local now = deps.now or defaultNow
	local show = ShowCore.new({ arena = deps.arena or ArenaData.build(), now = now, tuning = deps.tuning or Tuning })
	stage.show = show
	local link = deps.link
	if link == nil and hasEngine() then
		link = PaintballClient.link()
	end
	if link then
		table.insert(
			stage.undo,
			link.listen("Paintball.Snap", function(payload: any)
				show:onSnap(payload)
			end)
		)
		table.insert(
			stage.undo,
			link.listen("Paintball.Shot", function(payload: any)
				show:onShots(payload)
			end)
		)
		table.insert(
			stage.undo,
			link.listen("Splat", function(payload: any)
				show:onSplats(payload)
			end)
		)
	end
	if deps.screen == nil and hasEngine() then
		stage.world = World.new(show, deps.tuning)
	end
	local seat = stage.seat
	if seat then
		show.you = seat.you
	end
	bind()
	return show
end

local function closeShow()
	local show = stage.show
	if show == nil then
		return
	end
	for _, undo in stage.undo do
		undo()
	end
	table.clear(stage.undo)
	local world = stage.world
	stage.world = nil
	if world then
		world:stop()
	end
	stage.show = nil
	stage.watched = false
	show:stop()
	bind()
end

-- The show on this screen, if one is on.
function PaintballClient.show(): Show?
	fresh()
	return stage.show
end

-- The seat on this screen, if the player is in the match.
function PaintballClient.seat(): Seat?
	fresh()
	return stage.seat
end

-- The framework's `watch`: called for "paintball_watch" and "paintball_unwatch" whether or not the
-- player is seated. Returns the show (nil once it has ended); the framework hands that to the
-- seat's onMessage as `watched`.
function PaintballClient.watch(msg: { [string]: any }, place: ClientGame.Place?, deps: Deps?): Show?
	fresh()
	if msg.kind == "paintball_unwatch" then
		stage.watched = false
		if stage.seat ~= nil then
			-- (a seat keeps its show until it closes: its own ball and splats live there)
			return stage.show
		end
		closeShow()
		return nil
	end
	local show: Show = stage.show or openShow(deps or {})
	stage.watched = true
	show:onWatch(msg, place)
	return show
end

-- The framework's `new`: the controller for a seat in the match.
function PaintballClient.new(ctx: ClientGame.Ctx, deps: Deps?): Seat
	fresh()
	local d: Deps = deps or {}
	local now = d.now or ctx.stamp
	-- a player in the match always has a show (the server's "paintball_watch" is on its way)
	local show: Show = stage.show or openShow(d)
	if ctx.place ~= nil and show.frame == nil then
		show:onWatch({}, ctx.place)
	end
	local real = d.screen == nil and hasEngine()
	local port: SelfPort.Self? = nil
	if real then
		port = SelfPort.new(ctx, function()
			local on = stage.show
			return if on then on.frame else nil
		end, d.tuning)
	end
	local link = d.link
	if link == nil and hasEngine() then
		link = PaintballClient.link()
	end
	local seat = SeatCore.new(ctx, {
		now = now,
		link = link,
		arena = show.arena,
		port = port or (if type(d.screen) == "table" then d.screen else nil),
		show = function(): Show?
			return stage.show
		end,
		tuning = d.tuning,
	})
	stage.seat = seat
	local closers: { () -> () } = {}
	if port then
		local body = port
		local marker = Marker.new(seat, body, d.tuning)
		local hud = Hud.new(seat, ctx, d.tuning)
		local controls = Controls.new(seat, hud, body, d.tuning)
		-- the keys' states first, the body's own easing, then what is drawn from the seat
		stage.parts = {
			controls,
			{
				step = function(_self: any, dt: number)
					body.step(dt)
				end,
			},
			marker,
			hud,
		}
		closers = {
			function()
				controls:stop()
			end,
			function()
				marker:stop()
			end,
			function()
				hud:stop()
			end,
		}
	end
	-- stop(): the framework's, however the game closes. Everything of the seat's goes; the show stays
	-- for as long as the server keeps this screen in the audience.
	local stopCore = seat.stop
	local stopped = false
	seat.stop = function(self: Seat)
		if stopped then
			return
		end
		stopped = true
		for _, close in closers do
			close()
		end
		stopCore(self)
		if stage.seat == self then
			stage.seat = nil
			stage.parts = {}
			local on = stage.show
			if on then
				on.you = 0
				if not stage.watched then
					closeShow()
				end
			end
			bind()
		end
	end
	bind()
	return seat
end

return PaintballClient
