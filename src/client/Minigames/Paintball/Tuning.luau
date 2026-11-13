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
-- sprint (and is held until the marker is up, so the click is never lost) and the sprint does not pick
-- up again until sprintAfterShot after the ball has left; a crouch ends it; the view widens and bobs
-- harder (sprintFov, bobSprint), and every step is loud to everyone near (stepLoud).
-- And it runs only ahead (sprintCone): nobody backpedals or strafes out of a fight at sprint pace.
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
	-- The streak behind a ball: seconds of its flight it is long (2.7 studs at 90 studs/s) and how
	-- see-through it is (0 solid .. 1 gone). None and a ball is a dot the eye loses at speed; long and
	-- solid and it reads as a beam, which a paintball is not.
	ballStreak = 0.03,
	ballStreakFade = 0.45,

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
	-- The reload: radians the marker tips over, studs it sinks, and how many rattles of the hopper are
	-- drawn while it runs. The rhythm of the five shots and the reload should be readable without the pips.
	reloadTip = 0.55,
	reloadSink = 0.12,
	reloadShakes = 5,
	reloadShake = 0.05,
	-- The share of the reload the marker takes to tip over, and again to right itself at the end. The
	-- righting is the tell that the next ball is nearly there: shorter and it snaps, longer and the
	-- marker looks ready before it is.
	reloadTipShare = 1 / 6,
	-- How quickly the marker goes down and comes up, 1/s (a tap of Shift does not snap it), how early in
	-- the sprint's ramp it is fully down (3: down by a third of the ramp), and radians it swings in
	-- across the body when down.
	markerEase = 30,
	markerDropGain = 3,
	sprintSwing = 0.5,
	-- Studs out at which the barrel's line meets the crosshair's. Nearer toes the marker in harder.
	markerConverge = 40,
	-- How see-through the marker is while you are protected (0 solid .. 1 gone), and every puppet that
	-- cannot be hit (protected, in its own spawn room, tagged): "cannot fire, cannot be hit" has one look.
	markerGhost = 0.6,

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

	-- A TAP OF CROUCH -------------------------------------------------------------------------------
	-- Seconds inside which two changes of the crouch key count as a tap (down and straight up again, or
	-- the other way). After one the server's own idea of how far you are crouched may be on the far side
	-- of yours, so a click then waits until your eye is within tapSlack studs short of the 0.4 the server
	-- allows of where it is going: under a tenth of a second, and never for a plain crouch or a plain
	-- stand. Shorter than a slow connection's round trip plus the crouch itself and a ball fired through a
	-- tap can be refused after it was drawn; longer only makes a slow crouch-spam fire a hair later.
	tapWindow = 0.6,
	tapSlack = 0.05,

	-- SPRINT ----------------------------------------------------------------------------------------
	-- How hard the stick or keys must be pushed for a sprint to run, 0..1. Standing still with Shift
	-- held does not lower the marker.
	sprintMove = 0.3,
	-- Radians either side of straight ahead within which a push may sprint (0.87: about 50 degrees, so
	-- W with A or D sprints on the diagonal; straight sideways or back never does). Wider and a player
	-- strafes or backpedals out of a fight at sprint pace, paying only the lowered marker; narrower and a
	-- stick held a little off true drops the sprint.
	sprintCone = 0.87,
	-- Touch: a full push of the stick starts a sprint, and it lasts until the stick is back under this.
	touchSprintOn = 0.95,
	touchSprintOff = 0.5,
	-- Gamepad: the L3 sprint ends when the stick comes back under this.
	padSprintOff = 0.25,
	-- Seconds after a ball leaves before a held sprint picks up again. The marker is seen to fire and
	-- kick before it drops, and the click is on its way to the server before the first pose that says
	-- "sprinting" again. 0 drops the marker in the frame after the shot; much more and Shift feels dead.
	sprintAfterShot = 0.12,

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
	-- Seconds the reload's word and bar flash after a dry click: the eye is told what the ear was.
	dryFlashSecs = 0.14,
	-- THE SIZE OF THE HUD. It is drawn for a screen hudFitWide by hudFitTall; on a smaller one (a phone)
	-- the whole of it shrinks together, never below hudSmallest (under that, words stop being read); on
	-- one larger than hudBigWide by hudBigTall it grows, so 4K is not a HUD for ants. The crosshair
	-- never shrinks and the touch buttons never change: a thumb is the same size on every phone.
	hudFitWide = 900,
	hudFitTall = 480,
	hudSmallest = 0.7,
	hudBigWide = 1920,
	hudBigTall = 1080,
	-- The crosshair: its gap and arm length in pixels at rest, and how much wider while the marker
	-- cannot fire (down, reloading, safe): the gap IS the "not ready" light.
	crossGap = 5,
	crossArm = 7,
	crossWide = 9,
	-- How see-through the crosshair goes between two shots (the fire interval), 0 solid .. 1 gone: a hint
	-- of the marker's rhythm, never the "not ready" look (a click then is held and leaves by itself).
	crossRhythmFade = 0.25,
	-- Seconds of the briefing left at which the count is shown big in the middle, and seconds "GO!" stays.
	briefCount = 5,
	goSecs = 0.9,
	-- Seconds left at which the clock turns red.
	clockRed = 30,
	-- Pixels from the crosshair to the tick that points at whoever tagged you.
	tagRing = 120,
	-- Protection after a respawn: pixels of the border drawn round the screen in your team's colour
	-- while it lasts (with a bar that drains), and how fast the border breathes, cycles a second.
	shieldEdge = 10,
	shieldPulse = 2,
	-- Seconds before the server would take an idle player off (Contract.Rules.idleSecs without moving,
	-- turning or firing) at which the HUD starts to say so.
	idleWarn = 15,
	-- Seconds between two presses of Leave or Change sides that both count (a double press is one).
	verbSecs = 0.3,
	-- Seconds the controls card stays up for somebody who joins a match already running (it is up
	-- through the whole briefing for everyone else; H shows and hides it at any time).
	cardSecs = 6,

	-- SOUND (cue points only: nothing is synthesised; ids come from the owner's licensed set) -------
	-- Studs at which a cue placed in space has fallen to half and to nothing. (The fall is the client's own;
	-- the engine only gives the sound its direction: it is played from where it happened with no roll-off of
	-- the engine's inside soundFar, so footsteps behind you on the left are heard behind you on the left.)
	soundHalf = 28,
	soundFar = 110,
	-- What each floor between you and a sound takes off it (PB-8: "muffled through floors").
	floorMuffle = 0.45,
	-- Decibels of treble (and half as much of the middle) each floor between takes off a sound placed in
	-- space, so a fight through the ceiling is a thud, not a quieter crack. More: a floor sounds like concrete.
	floorTreble = 12,
	-- Seconds after which a sound placed in space is cleared away even if the engine never says it ended
	-- (an id that failed to load). Longer than the longest cue; it only bounds what is left lying about.
	cueLife = 5,
	-- Volumes, 0..1.
	volFire = 0.7,
	volFireFar = 0.6,
	volSplat = 0.45,
	volTag = 0.9, -- YOU tagged someone: unmistakable
	volTagged = 1.0, -- you were tagged: the loudest thing in the game
	volReload = 0.5,
	volReloadFar = 0.35,
	volDry = 0.5,
	volReady = 0.45, -- the magazine is full again: the click that says "go"
	volGo = 0.8, -- the match goes live
	volBack = 0.6, -- you are back from being tagged out
	-- Footsteps: studs between two steps walking and sprinting, and how loud each is. Crouched steps
	-- are silent (PB-8), which is the whole point of crouch-walking up on someone.
	stepWalk = 4.2,
	stepSprint = 5.0,
	stepQuiet = 0.22,
	stepLoud = 0.6,

	-- PAINT -----------------------------------------------------------------------------------------
	-- A splat's size on a wall, studs across (one of three, picked from the ball's id so every screen
	-- draws the same), how much smaller it is on a body, and how long the puff lasts where your own ball
	-- met a puppet.
	splatSmall = 1.3,
	splatMid = 1.7,
	splatBig = 2.2,
	splatOnBody = 0.55,
	puffSecs = 0.25,
	-- Studs at which another player's name tag stops being drawn.
	nameTagFar = 70,

	-- TOUCH -----------------------------------------------------------------------------------------
	-- The buttons, as fractions of the screen (centre x, centre y) and a size in pixels. FIRE on the
	-- right does not sink its touch (a drag that starts on it still turns the view). THE LOWER RIGHT
	-- CORNER IS LEFT ALONE: the stock jump button lives there (70 px on a phone, 120 on a tablet), and
	-- so is the lower left below FIRE, which is the thumbstick's. SCORES sits left of the clock, clear
	-- of the feed on the right and of Roblox's own buttons in the top left corner.
	touchFire = { 0.8, 0.52, 96 },
	touchFireLeft = { 0.12, 0.42, 76 },
	touchReload = { 0.7, 0.84, 64 },
	touchCrouch = { 0.94, 0.48, 64 },
	touchScores = { 0.24, 0.1, 56 },

	-- SWITCHES --------------------------------------------------------------------------------------
	-- Turn the look to the placement's yaw through a one-frame camera hold (the contract's "turn of
	-- the look"). False leaves the step out: you respawn looking where you last looked. To be seen
	-- once in Studio (the contract's open question).
	turnLook = true,
	-- Open the crosshair over the fire interval between two shots too, as well as for the real blockers.
	-- False (the default): every ball goes exactly down the middle, and a crosshair that blooms after a shot
	-- tells the hands it is less accurate, which it is not.
	crossBloom = false,
}

-- The table's type, for code that takes it as a parameter (a test hands in a copy with one number changed).
local T = (nil :: any) :: typeof(Tuning)
local out = Tuning :: typeof(Tuning) & { T: typeof(T) }
out.T = T

return out
