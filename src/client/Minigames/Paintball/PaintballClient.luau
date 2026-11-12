--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Paintball.PaintballClient
-- The paintball client (checklist PB-1, PB-2, PB-4, PB-7, PB-8, PB-9; brief v2 §14): everything behind
-- paintball's ClientGame in the minigame framework (Client/Minigames/Games/Paintball hands the
-- framework's `watch` and `new` to this module): first person, the marker, firing and reloading with
-- a predicted ball, sprint and crouch, the HUD, the other bodies, balls and splats, the sounds.
-- OWNED BY THE CLIENT LANE, with the whole of Client/Minigames/Paintball/. THIS IS A STUB: `watch`,
-- `new`, `link` and the methods keep their names and signatures; the lane writes the bodies and adds
-- its own files in this folder. It does not edit Camera/, Controllers/, Input/, Possession/, UI/ or
-- the framework (MinigameClient, ClientGame, MinigameUI).
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
-- proves them under Lune; what touches Instances sits behind `screen`.
--
-- WHAT IT DOES, AND WITH WHICH PART OF THE CONTRACT (Shared/Minigames/Paintball)
--   the frame    Arena.placeOf(place) with the site's place (ClientGame.Ctx.place for the seat, the
--                `place` handed to watch for the show) puts the arena in the world: Arena.toWorld /
--                toLocal. Everything on the wire is in the arena frame.
--   first person the seat sets its own body's "CameraZone" attribute to "lockFirstPerson" while the
--                game is open, and clears it in stop(): the existing Client/Possession and
--                Camera/CameraPolicy then lock first person and release it. Nothing here writes the
--                camera's CFrame (the framework's rule; the rig fails a case that does). Seen through
--                that camera: the marker, its sway and dip, the crosshair, the sprint widening of
--                view (FieldOfView).
--   moving       the body is the possessed R15 Humanoid body under the stock controls. The pace goes
--                through ctx.pace(Body.pace(crouch, k), false) every frame (k ramps 0..1 over
--                Body.SPRINT_RAMP_SECS while Shift or L3 is held; the framework's own Shift is off);
--                Humanoid.JumpHeight = Body.JUMP_HEIGHT while seated, put back in stop(). Crouch (C,
--                Left Ctrl, gamepad B) is the crouch fraction eased with Body.crouchStep and the
--                camera lowered to Body.eye(crouch) with Humanoid.CameraOffset; nothing about the
--                Humanoid's collision changes. Clock.SEND_HZ times a second: Wire.Move through the
--                Link (the feet point through Arena.toLocal, yaw and pitch from the camera's look
--                through Arena.dirToLocal and Body.yawPitch, the bits).
--   firing       one click, one ball, never hitscan: Magazine.fire on its own Magazine at now = the
--                shared clock; if it fires, send Wire.Fire (shot counter, vt = Clock.viewTime, ft =
--                now, origin = Body.eyePoint, the unit look) and in the same frame draw the ball flying
--                Ballistics.position from the eye line, stopping where arena.sweep says a wall is. No
--                fire while sprinting or for Body.SPRINT_FIRE_DELAY after, while reloading (a dry
--                click), out, protected, or outside "live". "paintball_ack" corrects the magazine if
--                the server disagreed. R reloads: ctx.send("reload", { now }), predicted with
--                Magazine.reload.
--   other bodies every slot but its own is a PUPPET the show builds and moves, people and bots alike,
--                drawn at Clock.viewTime(view, now) by straight-line interpolation between the two
--                snapshots either side (Wire.decodeSnap, Wire.between; held at the newest, never run
--                ahead; Clock.observe on each arrival). The replicated real bodies of the people in
--                the match are hidden on this screen while the show is on (LocalTransparencyModifier;
--                "paintball_watch" lists who is in which slot), so nobody is drawn twice and what is
--                aimed at is what the server rewinds to.
--   balls        Wire.Shot records: other slots' balls, drawn with Ballistics from their birth time,
--                with the marker's pop at the origin (muffled through a floor).
--   splats       Wire.Splat records: wall splats at the point on the face, the newest
--                Rules.splatPool kept by seq; body splats on the puppet's part (Body.partAt) at the
--                Wire.fromBody offset, kept until the match ends; team colours from Contract.TEAMS, a
--                few shapes and sizes picked from the ball id. All cleared when the match number
--                changes (in "paintball_watch", and in every snapshot's head).
--   the word     "paintball_tag": the hit marker and hit sound when `by` is you, the louder one and a
--                splat on the goggles when `id` is you; "paintball_respawn", "paintball_correct":
--                where the server put a body.
--   HUD          five pips, the reload, the clock counted down from view.game.endsAt, both scores,
--                the tagged-out and protection timers, the controls card in the briefing, the
--                scoreboard on a held key that is not Tab (with it, a Leave button: ctx.setButtons;
--                the bar is empty while playing, so the mouse stays the look), the framework's end
--                card at the end (ClientGame.endCard).
-- Interface: watch(msg, place) -> Show? (the framework's `watch`); new(ctx, deps?) -> Seat (the
--   framework's `new`); show() -> Show? (the one on this screen); link() -> Link? (the engine's:
--   written, not a stub);
--   types Link, Action, Deps, Show, Seat

local Import = require("../../Import")
local ArenaData: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.ArenaData)) =
	Import.shared("Minigames/Paintball/ArenaData")
local Clock: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Clock)) =
	Import.shared("Minigames/Paintball/Clock")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local Magazine: typeof(require(game.ReplicatedStorage.Shared.Paintball.Magazine)) = Import.shared("Paintball/Magazine")
local ClientGame = require("../ClientGame")

type Arena = typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Arena).T.Arena)
type Mag = typeof(Magazine.new(1, 1, 1))
type View = typeof(Clock.newView())

-- The client's link to paintball's own remotes (Wire.REMOTES).
--   send    a buffer up: "Paintball.Move" (Wire.Move), "Paintball.Fire" (Wire.Fire)
--   listen  hear a buffer coming down: "Paintball.Snap", "Paintball.Shot", "Splat"; returns the undo
export type Link = {
	send: (remote: string, payload: buffer) -> (),
	listen: (remote: string, fn: (payload: any) -> ()) -> () -> (),
}

-- What the player can do. "fire" and "reload" act on press; the rest are held (down = true / false).
export type Action = "fire" | "reload" | "crouch" | "sprint" | "scores" | "leave"

export type Deps = {
	now: (() -> number)?, -- the shared clock; default workspace:GetServerTimeNow() (ClientGame.Ctx.stamp)
	link: Link?, -- default link(); nil: nothing is sent and no stream is heard
	arena: Arena?, -- default ArenaData.build()
	screen: any?, -- the lane's own port to everything that touches Instances; nil = headless
}

-- The show: the match as anyone in the audience sees it.
export type Show = {
	arena: Arena,
	match: number, -- the match being shown; 0 before the first "paintball_watch"
	place: ClientGame.Place?, -- the site's place, as the framework told it
	view: View,
	onWatch: (self: Show, msg: { [string]: any }, place: ClientGame.Place?) -> (),
	onSnap: (self: Show, payload: any) -> (), -- a Paintball.Snap buffer (Wire.decodeSnap)
	onShots: (self: Show, payload: any) -> (), -- a Paintball.Shot buffer (Wire.unpack(Wire.Shot, payload))
	onSplats: (self: Show, payload: any) -> (), -- a Splat buffer (Wire.unpack(Wire.Splat, payload))
	step: (self: Show, dt: number) -> (),
	stop: (self: Show) -> (),
}

-- The seat: the framework's controller for a player in the match (a ClientGame.Controller), and what
-- the lane's own input code drives.
export type Seat = {
	ctx: ClientGame.Ctx,
	you: number, -- this player's slot id; 0 until the first "state"
	mag: Mag, -- the predicted magazine
	shot: number, -- the counter sent with each Fire
	onState: (self: Seat, msg: { [string]: any }) -> (), -- the framework's "state": view.game, Extras
	onMessage: (self: Seat, msg: { [string]: any }, watched: any?) -> (), -- paintball's kinds (Wire.KINDS)
	onRefused: (self: Seat, msg: { [string]: any }) -> (),
	input: (self: Seat, action: Action, down: boolean) -> (),
	step: (self: Seat, dt: number) -> (), -- one frame
	stop: (self: Seat) -> (),
}

local PaintballClient = {}

local current: Show? = nil

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

local function newShow(deps: Deps): Show
	local show = {
		arena = deps.arena or ArenaData.build(),
		match = 0,
		place = nil,
		view = Clock.newView(),
	} :: Show

	function show.onWatch(self: Show, msg: { [string]: any }, place: ClientGame.Place?)
		self.place = place
		if type(msg.match) == "number" then
			self.match = msg.match
		end
	end

	function show.onSnap(_self: Show, _payload: any) end

	function show.onShots(_self: Show, _payload: any) end

	function show.onSplats(_self: Show, _payload: any) end

	function show.step(_self: Show, _dt: number) end

	function show.stop(_self: Show) end

	return show
end

-- The show on this screen, if one is on.
function PaintballClient.show(): Show?
	return current
end

-- The framework's `watch`: called for "paintball_watch" and "paintball_unwatch" whether or not the
-- player is seated. Returns the show (nil once it has ended); the framework hands that to the
-- seat's onMessage as `watched`.
function PaintballClient.watch(msg: { [string]: any }, place: ClientGame.Place?, deps: Deps?): Show?
	if msg.kind == "paintball_unwatch" then
		local ended = current
		current = nil
		if ended then
			ended:stop()
		end
		return nil
	end
	local show: Show = current or newShow(deps or {})
	current = show
	show:onWatch(msg, place)
	return show
end

-- The framework's `new`: the controller for a seat in the match.
function PaintballClient.new(ctx: ClientGame.Ctx, _deps: Deps?): Seat
	local R = Contract.Rules
	local seat = {
		ctx = ctx,
		you = 0,
		mag = Magazine.new(R.magazine, R.fireInterval, R.reloadSecs),
		shot = 0,
	} :: Seat

	function seat.onState(self: Seat, msg: { [string]: any })
		if type(msg.you) == "number" then
			self.you = msg.you
		end
	end

	function seat.onMessage(_self: Seat, _msg: { [string]: any }, _watched: any?) end

	function seat.onRefused(_self: Seat, _msg: { [string]: any }) end

	function seat.input(_self: Seat, _action: Action, _down: boolean) end

	function seat.step(_self: Seat, _dt: number) end

	function seat.stop(_self: Seat) end

	return seat
end

return PaintballClient
