--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Paintball.Tuning
-- THE ONE TABLE OF THE PAINTBALL CLIENT'S FEEL (checklist PB-1, PB-2, PB-8, PB-9). Every number the
-- client's hands, eyes and ears meet that the contract does not already fix sits here, each with what
-- turning it does. Nothing else in Client/Minigames/Paintball holds a feel number of its own.
-- WHAT IS NOT HERE, AND WHY: the numbers both sides must agree on are the match's own feel table
-- (Contract.FEEL: ball speed and drop, fire interval, reload, sprint multiple, crouch time, respawn,
-- protection: the server tells them to every client and the owner turns them with the service's
-- debug("tune", key, value)), the body's (Body: eye heights, the sprint ramp, the 0.15 s before the
-- marker is back up, the jump) and the margins between the client's gates and the server's
-- (Contract.MARGIN). A client that changed one of those alone would be refused or corrected.
-- THE COST OF SPRINTING, in one place: while the sprint ramp is above 0 the marker is down and cannot
-- fire; it is back up Body.SPRINT_FIRE_DELAY (0.15 s) after the sprint ends; a fire press ends the
-- sprint (and is held until the marker is up, so the click is never lost); a crouch ends it; the view
-- widens and bobs harder (sprintFov, bobSprint), and every step is loud to everyone near (stepLoud).
-- There is no stamina bar: the price is paid in readiness and noise, not in a meter.
-- Pure data. Interface: the table; Tuning.T (its type witness)

local Tuning = {
	-- SENDING AND DRAWING OTHERS -------------------------------------------------------------------
	-- Seconds a snapshot is kept for drawing. Longer than the view lag plus the interpolation, so a
	-- burst of loss still leaves a pair to draw between; more only costs memory.
	snapKeep = 1.0,
	-- How fast a puppet's yaw and pitch chase the snapshot's, 1/s. Low: other players turn like
	-- tankers; high: they snap between the 20 Hz samples. No hit depends on it.
	puppetTurn = 18,
	-- Seconds a tagged puppet stands with its hand up before it is taken away (PB rating: "throws up a
	-- hand and is walked back"). Shorter and a tag reads as a vanish; longer and the dead block a door.
	outHandSecs = 1.0,

	-- THE BALL --------------------------------------------------------------------------------------
	-- Seconds over which your own drawn ball slides from the marker's muzzle onto the true eye line.
	-- 0 draws it from between your eyes (it reads as a laser); too long and it visibly curves.
	muzzleBlend = 0.09,
	-- Seconds a predicted wall splat waits for the server's record before it is taken back.
	predictedSplatSecs = 1.0,
	-- Studs: the server's wall record replaces your predicted splat when it lands this near.
	predictedSplatSnap = 1.5,
	-- Seconds another player's ball may go on flying after the server said what it hit, while the
	-- picture (drawn a view-lag behind) catches up with the verdict.
	ballCatchUp = 0.35,

	-- THE MARKER IN VIEW ----------------------------------------------------------------------------
	-- Where the marker sits in the view: studs right, down and forward of the eye. Further right and
	-- down clears the crosshair; too far and it leaves a phone's screen.
	markerRight = 0.85,
	markerDown = 0.75,
	markerForward = 1.5,
	-- How far the muzzle is in front of the marker's grip, studs: where the drawn ball starts.
	markerLength = 1.6,
	-- How quickly the marker follows the view, 1/s. Low: it floats behind every turn (heavy, drunk);
	-- high: it is bolted to the screen (weightless).
	swayRate = 14,
	-- The most the marker may trail a turn, radians. The cap keeps a fast flick from swinging it off.
	swayMax = 0.09,
	-- The walking bob: studs up and down, cycles per stud walked. More reads as heavier steps.
	bobWalk = 0.035,
	bobSprint = 0.08,
	bobPerStud = 0.11,
	-- Sprinting drops the marker: radians it tips down and studs it sinks at full sprint. This is the
	-- picture of "cannot fire": it must be unmistakable in the corner of the eye.
	sprintTip = 0.75,
	sprintSink = 0.55,
	-- The kick of a shot: studs the marker jumps back and radians it tips up, and how fast it comes
	-- home, 1/s. The view itself never kicks: the crosshair stays where the next ball goes.
	kickBack = 0.22,
	kickUp = 0.07,
	kickRecover = 16,
	-- The reload: radians the marker tips over and how many rattles of the hopper are drawn while it
	-- runs. The rhythm of the five shots and the reload should be readable without the pips.
	reloadTip = 0.55,
	reloadShakes = 5,
	reloadShake = 0.05,

	-- THE EYE ---------------------------------------------------------------------------------------
	-- Degrees the view widens at full sprint, and how fast it follows the ramp, 1/s. A little says
	-- "fast"; much distorts the aim that follows.
	sprintFov = 6,
	fovRate = 10,
	-- Landing: studs the eye dips per stud/s of fall, the most it dips, and how fast it recovers, 1/s.
	-- The dip is the only moment the eye is not exactly Body.eye above the feet.
	landDip = 0.012,
	landDipMax = 0.45,
	landRecover = 9,

	-- SPRINT ----------------------------------------------------------------------------------------
	-- How hard the stick or keys must be pushed for a sprint to run, 0..1. Standing still with Shift
	-- held does not lower the marker.
	sprintMove = 0.3,
	-- Touch: a full push of the stick starts a sprint, and it lasts until the stick is back under this.
	touchSprintOn = 0.95,
	touchSprintOff = 0.5,
	-- Gamepad: the L3 sprint ends when the stick comes back under this.
	padSprintOff = 0.25,

	-- THE HUD ---------------------------------------------------------------------------------------
	-- Seconds the hit marker (the X on the crosshair) stays after the server says you tagged someone.
	hitMarkerSecs = 0.35,
	-- Seconds a line of the feed (who tagged whom) stays, and how many lines show.
	feedSecs = 5,
	feedLines = 4,
	-- Seconds the splat on your goggles takes to clear after you are tagged.
	goggleSecs = 2.5,
	-- Seconds a refusal or a call-out stays under the crosshair.
	noteSecs = 1.6,
	-- Seconds between two dry clicks: a held or mashed trigger on an empty marker ticks, it does not buzz.
	drySecs = 0.18,
	-- The crosshair: its gap and arm length in pixels at rest, and how much wider while the marker
	-- cannot fire (down, reloading, safe): the gap IS the "not ready" light.
	crossGap = 5,
	crossArm = 7,
	crossWide = 9,
	-- Seconds of the briefing left at which the count is shown big in the middle.
	briefCount = 5,

	-- SOUND (cue points only: nothing is synthesised; ids come from the owner's licensed set) -------
	-- Studs at which a cue placed in space has fallen to half and to nothing.
	soundHalf = 28,
	soundFar = 110,
	-- What each floor between you and a sound takes off it (PB-8: "muffled through floors").
	floorMuffle = 0.45,
	-- Volumes, 0..1.
	volFire = 0.7,
	volFireFar = 0.6,
	volSplat = 0.45,
	volTag = 0.9, -- YOU tagged someone: unmistakable
	volTagged = 1.0, -- you were tagged: the loudest thing in the game
	volReload = 0.5,
	volReloadFar = 0.35,
	volDry = 0.5,
	-- Footsteps: studs between two steps walking and sprinting, and how loud each is. Crouched steps
	-- are silent (PB-8), which is the whole point of crouch-walking up on someone.
	stepWalk = 4.2,
	stepSprint = 5.0,
	stepQuiet = 0.22,
	stepLoud = 0.6,

	-- TOUCH -----------------------------------------------------------------------------------------
	-- The buttons, as fractions of the screen (centre x, centre y) and a size in pixels. FIRE at the
	-- lower right does not sink its touch (a drag that starts on it still turns the view).
	touchFire = { 0.86, 0.62, 96 },
	touchFireLeft = { 0.12, 0.42, 76 },
	touchReload = { 0.74, 0.8, 64 },
	touchCrouch = { 0.93, 0.82, 64 },
	touchScores = { 0.93, 0.12, 56 },

	-- SWITCHES --------------------------------------------------------------------------------------
	-- Turn the look to the placement's yaw through a one-frame camera hold (the contract's "turn of
	-- the look"). False leaves the step out: you respawn looking where you last looked. To be seen
	-- once in Studio (the contract's open question).
	turnLook = true,
}

-- The table's type, for code that takes it as a parameter (a test hands in a copy with one number changed).
local T = (nil :: any) :: typeof(Tuning)
local out = Tuning :: typeof(Tuning) & { T: typeof(T) }
out.T = T

return out
