--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Cabinet
-- Where a pinball machine stands in the bowling alley's games room and how it is put together around its
-- playfield: the one place the bake (tools/bake/games/Pinball), the server (Server/Minigames/Games/Pinball) and
-- the client (Client/Minigames/Pinball/*) take the cabinet's numbers from. The playfield itself is Layout's
-- (its size, its pitch, every element on it); the cabinets' places are AlleyLayout's (PINBALLS, PINBALL_D: read
-- here at run time, never copied); everything else is below.
-- Frames. Alley local (X across, Y up, D away from the entrance: AlleyLayout) and the playfield's own (x across
-- from the player's left, y up the table, h above the surface: Layout). The machine's back is against the
-- front wall (low D), its player stands on the +D side facing -D. point(index, x, y, h) is Layout.cabinetPoint
-- set down at the machine: so the bake builds and the client draws exactly where the model simulates. In a
-- part's terms the playfield frame is: origin at the playfield's front left corner (as the player sees it: the
-- player faces -D, so their right is the alley's -X), part X across to the player's right, part Y the surface
-- normal, part Z down the table toward the player, so that point (x, y, h) is the frame * (x, h, -y); the frame
-- is the alley's (after the site's yaw) turned by Angles(0, pi, 0) * Angles(TILT, 0, 0) (YAW_PI, TILT), and a
-- playfield direction (dx, dy) is a turn of turnOf(dx, dy) about the normal.
-- The camera (camera()) is the player's eye over the lockdown bar (or, the second view, leaning out over the
-- glass), worked out so that the whole playfield, both flippers and the plunger are in the picture on any screen
-- from 4:3 to a wide phone, with room kept at the top for the HUD's display when it asks.
-- Pure. Interface: model(index) -> name; at(index) -> (X, D) of the cabinet's middle; TILT; PF_Y; PF_D (the
--   playfield's middle, from PINBALL_D); point(index, x, y, h) -> (X, Y, D); origin(index) -> (X, Y, D);
--   turnOf(dx, dy) -> radians about the playfield normal; BUTTON; button(index, side, hand?, pressed?) -> (X, Y,
--   D) (a flipper button, or the hand on it); ROD_Y0; KNOB; KNOB_H; GRIP_KNOB; knob(index, x, pull, hand?) ->
--   (X, Y, D); BODY (the cabinet's box), BACKBOX, GLASS_H, LEGS;
--   stance(index) -> (X, D) where the player stands; camera(index, aspect?, which?, reserve?) -> { eye, target,
--   fov, aspect } (alley local); EYES (the views); RESERVE; MARGIN; project(view, X, Y, D) -> (u, v, depth) (a
--   point's place in the picture, 0..1 from the top left); NAMES (the parts the client moves); BALLS (ball parts
--   baked); FLIPPER_H; PULL_TRAVEL; DROP_SINK

local AlleyLayout = require("../../Attractions/AlleyLayout")
local Layout = require("./Layout")

local Cabinet = {}

Cabinet.TILT = Layout.TILT_RAD
Cabinet.PF_Y = 3.6 -- height of the middle of the playfield surface above the floor
Cabinet.PF_D = 0.12 -- the playfield's middle stands this far on the player's side of PINBALL_D
Cabinet.GLASS_H = 0.5 -- the glass above the playfield (over the tallest ramp)
Cabinet.RAIL = 0.15 -- the cabinet's side walls beside the playfield
-- the cabinet body, from PINBALL_D and the machine's X: across half-width, front and back, the tub's floor
Cabinet.BODY = { half = Layout.WIDTH / 2 + 0.15, front = 2.65, back = -2.4, floor = 2.45 }
-- the backbox standing on the cabinet's back: its depth (from the back), its foot and top
Cabinet.BACKBOX = { back = -2.45, front = -1.85, y0 = 4.45, y1 = 7.7, half = Layout.WIDTH / 2 + 0.15 }
Cabinet.LEGS = { inset = 0.22, size = 0.22, front = 2.3, back = -2.1 }
Cabinet.STANCE_D = 3.7 -- where the player stands (the body's middle), from PINBALL_D: clear of the plunger's knob
Cabinet.BALLS = 3 -- ball parts baked per machine (a three-ball multiball at most)
Cabinet.FLIPPER_H = 0.07 -- a flipper's height off the playfield; its model's pivot is half way up, on its pivot pin
Cabinet.PULL_TRAVEL = 0.32 -- how far the plunger's rod comes back at a full pull (studs, toward the player)
-- the plunger's rod comes out of the cabinet's front at ROD_Y0 (along the table, in front of the playfield) to
-- its knob, KNOB beyond it, KNOB_H above the surface; the hand pulling it holds it GRIP_KNOB nearer the player
Cabinet.ROD_Y0 = -0.45
Cabinet.KNOB = 0.05
Cabinet.KNOB_H = 0.04
Cabinet.GRIP_KNOB = 0.12
Cabinet.DROP_SINK = 0.16 -- how far a knocked-down drop target sinks below the playfield
-- the flipper buttons, on the outside of the side rails near the front: y along the table, h below the surface,
-- out beyond the rail (the button's middle), how far a button stands out of the cabinet's side (its length) and
-- across (its diameter); where the player's hand rests on it (grip: out from the button's middle, toward the
-- player) and how far a press pushes it in (press)
Cabinet.BUTTON = { y = 0.25, h = -0.16, out = 0.02, length = 0.06, size = 0.1, grip = 0.24, ahead = 0.05, press = 0.05 }

-- The parts the client finds by name (each machine's model is Pinball<index>).
Cabinet.NAMES = {
	ball = "Ball", -- Ball1..BALLS
	flipper = "Flipper", -- Flipper1..n (a Model: the flipper turns about its pivot)
	drop = "Drop", -- Drop<target number> (a drop target: down below the surface when knocked down)
	spinner = "Spinner", -- Spinner<k> (the k-th spinner)
	lamp = "Lamp", -- Lamp<lamp number>
	bumper = "BumperCap", -- BumperCap<bumper number> (lights when it fires)
	sling = "Sling", -- Sling<sling number> (its rubber, flashes when it kicks)
	plunger = "Plunger", -- a Model: the rod and its knob, drawn back by the pull
	backglass = "Backglass", -- the backbox's face, with SurfaceGui "Display"
	playfield = "Playfield",
}

function Cabinet.model(index: number): string
	return `Pinball{index}`
end

-- The machine's middle (X) and PINBALL_D: read from the floor plan every time.
function Cabinet.at(index: number): (number, number)
	local p = AlleyLayout.PINBALLS[index]
	assert(p, `no pinball machine {index}`)
	return p.x, AlleyLayout.PINBALL_D
end

-- A point of the playfield (x, y, h: Layout's frame) in the alley's local frame.
function Cabinet.point(index: number, x: number, y: number, h: number): (number, number, number)
	local px, pd = Cabinet.at(index)
	local across, up, along = Layout.cabinetPoint(x, y, h)
	return px - across, Cabinet.PF_Y + up, pd + Cabinet.PF_D - along
end

-- The playfield's origin (its front left corner as the player sees it, on the surface).
function Cabinet.origin(index: number): (number, number, number)
	return Cabinet.point(index, 0, 0, 0)
end

-- The turn about the playfield's normal that lays a part's X along the playfield direction (dx, dy).
function Cabinet.turnOf(dx: number, dy: number): number
	return math.atan2(dy, dx)
end

-- button(index, side, hand?, pressed?) -> (X, Y, D): the flipper button on a side (0 the player's left, 1 the
-- right): its middle, or with `hand` where the hand that works it is held (out from the button and a little
-- toward the player; pushed in by BUTTON.press when pressed).
function Cabinet.button(index: number, side: number, hand: boolean?, pressed: boolean?): (number, number, number)
	local b = Cabinet.BUTTON
	local out = Cabinet.RAIL + b.out
	local y = b.y
	if hand then
		out += b.grip - (if pressed then b.press else 0)
		y -= b.ahead
	end
	local x = if side == 0 then -out else Layout.WIDTH + out
	return Cabinet.point(index, x, y, b.h)
end

-- knob(index, x, pull, hand?) -> (X, Y, D): the plunger's knob (x: the shooter lane's, the table's plunger.x)
-- drawn back by pull (0..1), or with `hand` where the hand pulling it holds it.
function Cabinet.knob(index: number, x: number, pull: number, hand: boolean?): (number, number, number)
	local y = Cabinet.ROD_Y0 - Cabinet.KNOB - pull * Cabinet.PULL_TRAVEL - (if hand then Cabinet.GRIP_KNOB else 0)
	return Cabinet.point(index, x, y, Cabinet.KNOB_H)
end

-- Where the player stands (the body's middle), facing the machine (-D).
function Cabinet.stance(index: number): (number, number)
	local px, pd = Cabinet.at(index)
	return px, pd + Cabinet.STANCE_D
end

export type View = { eye: { number }, target: { number }, fov: number, aspect: number }

-- The two views (V, the gamepad's D-pad up or VIEW on a touch screen switches): the eye in the playfield's frame
-- (y along the table from its near edge, negative in front of it; h above its surface). "play" stands over the
-- lockdown bar, a tall person's eye looking down the table: high enough that the far end (the bumpers, the top
-- lanes, the skill shot) is not squeezed flat. "high" leans out over the glass: the table nearly from above.
Cabinet.EYES = {
	play = { y = -0.7, h = 3.1 },
	high = { y = 0.9, h = 5.6 },
}
Cabinet.MARGIN = 2 -- degrees kept clear above and below the playfield
-- fractions of the screen's height kept clear of the playfield: the top for the dot-matrix strip, the bottom
-- for the buttons (Client/Minigames/Pinball/Controller's HUD)
Cabinet.RESERVE = { top = 0.12, bottom = 0.02 }

-- project(view, X, Y, D): where an alley-local point stands in a view's picture: u across from the left edge
-- and v down from the top (0..1 of the screen), and its depth in front of the eye (negative: behind it).
function Cabinet.project(view: View, X: number, Y: number, D: number): (number, number, number)
	local e, t = view.eye, view.target
	-- (as world axes: X, Y, and Z = -D)
	local fx, fy, fz = t[1] - e[1], t[2] - e[2], -(t[3] - e[3])
	local n = math.sqrt(fx * fx + fy * fy + fz * fz)
	fx, fy, fz = fx / n, fy / n, fz / n
	-- right = forward x (0, 1, 0); up = right x forward
	local rx, rz = -fz, fx
	local rn = math.sqrt(rx * rx + rz * rz)
	rx, rz = rx / rn, rz / rn
	local ux, uy, uz = -rz * fy, rz * fx - rx * fz, rx * fy
	local dx, dy, dz = X - e[1], Y - e[2], -(D - e[3])
	local depth = dx * fx + dy * fy + dz * fz
	local right = dx * rx + dz * rz
	local up = dx * ux + dy * uy + dz * uz
	local tanV = math.tan(math.rad(view.fov / 2))
	local u = 0.5 + right / depth / (tanV * view.aspect) / 2
	local v = 0.5 - up / depth / tanV / 2
	return u, v, depth
end

-- camera(index, aspect, which?, reserve?): the player's view ("play", or "high"). It looks down the playfield
-- from its eye, pitched and with its field of view chosen so that the near edge sits just above the bottom of
-- the picture and the far end just under its top, less the reserve (fractions of the height kept for the HUD;
-- default RESERVE) (solved exactly: the picture is not linear in the angle), widened on a narrow screen until
-- both front corners fit. aspect is width / height (default 16:9).
function Cabinet.camera(index: number, aspect: number?, which: string?, reserve: { top: number, bottom: number }?): View
	local eyeAt = Cabinet.EYES[which or "play"] or Cabinet.EYES.play
	local ex, ey, ez = Cabinet.point(index, Layout.WIDTH / 2, eyeAt.y, eyeAt.h)
	-- the pitch (up from level, toward -D) of the line to a point of the playfield's centre line
	local function pitch(y: number): number
		local _, Y, D = Cabinet.point(index, Layout.WIDTH / 2, y, 0)
		return math.atan2(Y - ey, ez - D)
	end
	local m = math.rad(Cabinet.MARGIN)
	local lo, hi = pitch(0) - m, pitch(Layout.LENGTH) + m
	local keep = reserve or Cabinet.RESERVE
	local kTop, kBottom = 1 - 2 * keep.top, 1 - 2 * keep.bottom
	-- the pitch c that puts lo at -kBottom and hi at +kTop of the half-height: tan(hi - c) / kTop =
	-- tan(c - lo) / kBottom (the left side falls as c rises, the right side climbs: one crossing)
	local a, b = lo, hi
	for _ = 1, 60 do
		local c = (a + b) / 2
		if math.tan(hi - c) / kTop > math.tan(c - lo) / kBottom then
			a = c
		else
			b = c
		end
	end
	local c = (a + b) / 2
	local tanV = math.tan(c - lo) / kBottom
	-- the width: both front corners inside the picture's sides
	local asp = aspect or 16 / 9
	local fY, fD = math.sin(c), -math.cos(c)
	for _, x in { 0, Layout.WIDTH } do
		local X, Y, D = Cabinet.point(index, x, 0, 0)
		local depth = (Y - ey) * fY + (D - ez) * fD
		local need = math.abs(X - ex) / depth / asp * (1 + m)
		tanV = math.max(tanV, need)
	end
	local tx, ty, tz = ex, ey + fY * 4, ez + fD * 4
	return { eye = { ex, ey, ez }, target = { tx, ty, tz }, fov = math.deg(2 * math.atan(tanV)), aspect = asp }
end

return Cabinet
