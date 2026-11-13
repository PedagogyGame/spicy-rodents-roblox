--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Pinball.Hands
-- What the player's hands hold on a pinball machine, from every device at once, as the one number a tick the
-- model takes (Machine.buttons: the BTN bits and an analogue plunger pull). Each button is held while any
-- source holds it (Left Shift and the left half of the screen are both the left flipper; letting go of one
-- while the other holds keeps it up). A press is latched until the next tick has been played, so a tap that
-- goes down and up between two frames still raises the flipper for one tick (a press of 1 tick lifts it 1%
-- of its swing: a flick, as on a real machine). Pure (no engine): the controller feeds it the engine's events.
-- The keys (checklist PIN-C1..C3):
--   left flipper   Left Shift, A, Left arrow; the left mouse button; L1 or L2; a finger on the left half
--   right flipper  Right Shift, D, Right arrow; the right mouse button; R1 or R2; a finger on the right half
--   plunger        hold Space, S or Down (or A on a gamepad) to pull, let go to launch; the right stick pulled
--                  down, or a finger dragged down the strip at the bottom right, pull it as far as the hand goes
--   nudge          Z (from the left), X (from the right), W or Up (forward); the left stick flicked; NUDGE
-- Interface: new() -> Hands; press(h, source, bit); release(h, source, bit); pull(h, source, amount 0..1 | nil);
--   buttons(h) -> number (and consumes the latched presses); held(h) -> bits; clear(h); KEYS (key name -> bit);
--   MOUSE; PAD (gamepad button name -> bit); STICK_PULL_DEAD; STICK_NUDGE; STICK_RESET

local Import = require("../../Import")
local Machine =
	Import.shared("Minigames/Pinball/Machine") :: typeof(require("../../../shared/Minigames/Pinball/Machine"))

local Hands = {}

local BTN = Machine.BTN

Hands.KEYS = {
	LeftShift = BTN.LEFT,
	A = BTN.LEFT,
	Left = BTN.LEFT,
	RightShift = BTN.RIGHT,
	D = BTN.RIGHT,
	Right = BTN.RIGHT,
	Space = BTN.PLUNGE,
	S = BTN.PLUNGE,
	Down = BTN.PLUNGE,
	Z = BTN.NUDGE_L,
	X = BTN.NUDGE_R,
	W = BTN.NUDGE_UP,
	Up = BTN.NUDGE_UP,
} :: { [string]: number }
Hands.MOUSE = { MouseButton1 = BTN.LEFT, MouseButton2 = BTN.RIGHT } :: { [string]: number }
Hands.PAD = {
	ButtonL1 = BTN.LEFT,
	ButtonL2 = BTN.LEFT,
	ButtonR1 = BTN.RIGHT,
	ButtonR2 = BTN.RIGHT,
	ButtonA = BTN.PLUNGE,
} :: { [string]: number }
Hands.STICK_PULL_DEAD = 0.12 -- the right stick pulled down less than this is not a pull
Hands.STICK_NUDGE = 0.85 -- the left stick pushed this far (from near the middle) is a nudge
Hands.STICK_RESET = 0.4 -- and must come back inside this before it nudges again

export type Hands = {
	sources: { [number]: { [any]: boolean } }, -- bit -> the sources holding it
	latched: number, -- bits pressed since the last tick played
	pulls: { [any]: number }, -- analogue plunger hands: source -> 0..1
}

function Hands.new(): Hands
	return { sources = {}, latched = 0, pulls = {} }
end

function Hands.press(h: Hands, source: any, b: number)
	local set = h.sources[b]
	if set == nil then
		set = {}
		h.sources[b] = set
	end
	set[source] = true
	h.latched = bit32.bor(h.latched, b)
end

function Hands.release(h: Hands, source: any, b: number)
	local set = h.sources[b]
	if set then
		set[source] = nil
	end
end

-- pull(h, source, amount): an analogue hand on the plunger (nil or 0: let go)
function Hands.pull(h: Hands, source: any, amount: number?)
	if amount == nil or amount <= 0 then
		h.pulls[source] = nil
	else
		h.pulls[source] = math.clamp(amount, 0, 1)
	end
end

function Hands.held(h: Hands): number
	local bits = 0
	for b, set in h.sources do
		if next(set) ~= nil then
			bits = bit32.bor(bits, b)
		end
	end
	return bits
end

-- buttons(h): the number for the next tick. The latched presses are spent.
function Hands.buttons(h: Hands): number
	local bits = bit32.bor(Hands.held(h), h.latched)
	h.latched = 0
	local pull = 0
	for _, v in h.pulls do
		pull = math.max(pull, v)
	end
	return Machine.buttons(bits, pull)
end

function Hands.clear(h: Hands)
	table.clear(h.sources)
	table.clear(h.pulls)
	h.latched = 0
end

return Hands
