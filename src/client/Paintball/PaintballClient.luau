--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Paintball.PaintballClient
-- The paintball client (checklist PB-1, PB-2, PB-4, PB-7, PB-8, PB-9; brief v2 §14): first person, the
-- marker, firing and reloading with a predicted ball, sprint and crouch, the HUD, the other bodies,
-- balls and splats, the sounds, the end card.
-- OWNED BY THE CLIENT LANE, with the whole of Client/Paintball/. THIS IS A STUB: `new`, `start` and
-- the Client's methods keep their names and signatures; the lane writes the bodies and adds its own
-- files in this folder. It does not edit Camera/, Controllers/, Input/, Possession/, UI/ or Minigames/.
--
-- THE CORE IS HEADLESS: new(deps) is a state machine fed by the four server remotes and the player's
-- actions, with the clock, the outgoing remotes and everything on screen injected (deps), so the lane
-- proves it under Lune; start() is the thin engine wiring.
--
-- WHAT IT DOES, AND WITH WHICH PART OF THE CONTRACT (Shared/Paintball):
--   in and out   "joined" (Wire State) makes it a player, "watch" a watcher, "left" / "unwatch" end
--                that. As a player it sends its pose Clock.SEND_HZ times a second (Wire.Move, arena
--                frame: Arena.toLocal of the real body's feet point with the `place` from "joined";
--                yaw and pitch from the camera's look through Arena.dirToLocal and Body.yawPitch).
--   first person the server sets the body's CameraZone attribute to "lockFirstPerson"; the existing
--                Client/Possession and Camera/CameraPolicy then lock first person and release it when
--                the attribute is cleared. This lane adds only what is seen through that camera: the
--                marker, its sway and dip, the crosshair, the sprint widening of view.
--   moving       the body is the possessed R15 Humanoid body under the stock controls. This lane sets
--                Humanoid.WalkSpeed = Body.speed(crouch, sprinting) (with the Body.SPRINT_RAMP_SECS
--                ramp) in RunService.PreSimulation, which runs after Controllers/Human's own
--                RenderStepped write in the same frame, so that file is not edited; JumpHeight =
--                Body.JUMP_HEIGHT; both put back on leaving. Crouch (C or Left Ctrl) is the crouch
--                fraction eased with Body.crouchStep and the camera lowered to Body.eye(crouch) with
--                Humanoid.CameraOffset; nothing about the Humanoid's collision changes.
--   firing       one click, one ball, never hitscan: Magazine.fire on its own Magazine at now = server
--                time; if it fires, send Wire.Fire (shot counter, vt = Clock.viewTime, ft = now, origin
--                = Body.eyePoint, the unit look) and in the same frame draw the ball flying
--                Ballistics.position from the eye line, stopping where arena.sweep says a wall is. No
--                fire while sprinting or for Body.SPRINT_FIRE_DELAY after, while reloading (a dry
--                click), out, protected, or outside "live". The "ack" corrects the magazine if the
--                server disagreed. R reloads (Cmd "reload", predicted with Magazine.reload).
--   other bodies every slot but its own is a PUPPET it builds and moves itself, people and bots alike,
--                drawn at Clock.viewTime(view, now) by straight-line interpolation between the two
--                snapshots either side (Wire.decodeSnap; held at the newest, never run ahead;
--                Clock.observe on each arrival). The replicated real bodies of the people in the match
--                are hidden on this screen while it is in the audience (LocalTransparencyModifier), so
--                nobody is drawn twice and what is aimed at is what the server rewinds to.
--   balls        Wire.Shot records: other slots' balls, drawn with Ballistics from their birth time,
--                with the marker's pop at the origin (muffled through a floor).
--   splats       Wire.Splat records (and the buffer in "joined" / "watch"): wall splats at the point
--                on the face, the newest Rules.splatPool kept by seq; body splats on the puppet's part
--                (Body.partAt) at the Wire.fromBody offset, kept until the match ends; team colours
--                from Contract.TEAMS, a few shapes and sizes picked from the ball id. All cleared when
--                matchId changes.
--   the word     "tag": the hit marker and hit sound when `by` is you, the louder one and a splat on
--                the goggles when `id` is you; "respawn", "correct": where the server put a body.
--   HUD          five pips, the reload, the clock counted down from match.endsAt, both scores, the
--                tagged-out and protection timers, the controls card in the briefing, the scoreboard
--                on a held key that is not Tab, the end card ("end"), a deliberate Leave (Cmd "leave").
-- Interface: new(deps) -> Client; start(opts?) -> stop (engine wiring); Client:onState(msg);
--   onSnap(buffer); onShots(buffer); onSplats(buffer); input(action, down); step(dt); stop()

local Import = require("../Import")
local ArenaData: typeof(require(game.ReplicatedStorage.Shared.Paintball.ArenaData)) =
	Import.shared("Paintball/ArenaData")
local Clock: typeof(require(game.ReplicatedStorage.Shared.Paintball.Clock)) = Import.shared("Paintball/Clock")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Paintball.Contract)) = Import.shared("Paintball/Contract")
local Magazine: typeof(require(game.ReplicatedStorage.Shared.Paintball.Magazine)) = Import.shared("Paintball/Magazine")

type Arena = typeof(require(game.ReplicatedStorage.Shared.Paintball.Arena).T.Arena)
type Place = typeof(require(game.ReplicatedStorage.Shared.Paintball.Arena).T.Place)
type MatchView = typeof(Contract.T.MatchView)
type Mag = typeof(Magazine.new(1, 1, 1))
type View = typeof(Clock.newView())

-- What the player can do. "fire" and "reload" act on press; the rest are held (down = true / false).
export type Action = "fire" | "reload" | "crouch" | "sprint" | "scores" | "leave"

export type Deps = {
	send: (remote: string, payload: any) -> (), -- Paintball.Move and Paintball.Fire buffers, Paintball.Cmd tables
	now: () -> number, -- server time (workspace:GetServerTimeNow())
	arena: Arena?, -- default ArenaData.build()
	screen: any?, -- the lane's own port to everything that touches Instances; nil = headless
}

export type Client = {
	deps: Deps,
	arena: Arena,
	mode: "out" | "watching" | "playing",
	you: number, -- this player's slot id; 0 when not playing
	match: MatchView?,
	place: Place?,
	mag: Mag,
	view: View,
	shot: number, -- the counter sent with each Fire
	onState: (self: Client, msg: { [string]: any }) -> (),
	onSnap: (self: Client, payload: any) -> (),
	onShots: (self: Client, payload: any) -> (),
	onSplats: (self: Client, payload: any) -> (),
	input: (self: Client, action: Action, down: boolean) -> (),
	step: (self: Client, dt: number) -> (),
	stop: (self: Client) -> (),
}

local PaintballClient = {}

function PaintballClient.new(deps: Deps): Client
	local R = Contract.Rules
	local client = {
		deps = deps,
		arena = deps.arena or ArenaData.build(),
		mode = "out",
		you = 0,
		match = nil,
		place = nil,
		mag = Magazine.new(R.magazine, R.fireInterval, R.reloadSecs),
		view = Clock.newView(),
		shot = 0,
	} :: Client

	-- a Paintball.State message (Wire.STATE)
	function client.onState(_self: Client, _msg: { [string]: any }) end

	-- a Paintball.Snap buffer (Wire.decodeSnap)
	function client.onSnap(_self: Client, _payload: any) end

	-- a Paintball.Shot buffer (Wire.unpack(Wire.Shot, payload))
	function client.onShots(_self: Client, _payload: any) end

	-- a Splat buffer (Wire.unpack(Wire.Splat, payload))
	function client.onSplats(_self: Client, _payload: any) end

	function client.input(_self: Client, _action: Action, _down: boolean) end

	-- one frame
	function client.step(_self: Client, _dt: number) end

	function client.stop(_self: Client) end

	return client
end

export type StartOpts = { screen: any? }

-- Engine wiring, called once by the client's boot when paintball is joined to the game: finds the four
-- server remotes under ReplicatedStorage.Net, binds the keys, the gamepad and the touch buttons, and
-- steps every frame. Returns the function that undoes it. The stub starts nothing.
function PaintballClient.start(_opts: StartOpts?): () -> ()
	return function() end
end

return PaintballClient
