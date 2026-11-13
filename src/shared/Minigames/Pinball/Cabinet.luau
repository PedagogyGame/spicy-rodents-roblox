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
-- The camera (camera()) is the player's eye over the lockdown bar, worked out so that the whole playfield, both
-- flippers and the plunger are in the picture on any screen from 4:3 to a wide phone.
-- Pure. Interface: model(index) -> name; at(index) -> (X, D) of the cabinet's middle; TILT; PF_Y; PF_D (the
--   playfield's middle, from PINBALL_D); point(index, x, y, h) -> (X, Y, D); origin(index) -> (X, Y, D);
--   turnOf(dx, dy) -> radians about the playfield normal; BODY (the cabinet's box), BACKBOX, GLASS_H, LEGS;
--   stance(index) -> (X, D) where the player stands; camera(index, aspect?) -> { eye, target, fov } (alley
--   local); NAMES (the parts the client moves); BALLS (ball parts baked); FLIPPER_H; PULL_TRAVEL; DROP_SINK

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
Cabinet.DROP_SINK = 0.16 -- how far a knocked-down drop target sinks below the playfield

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

-- Where the player stands (the body's middle), facing the machine (-D).
function Cabinet.stance(index: number): (number, number)
	local px, pd = Cabinet.at(index)
	return px, pd + Cabinet.STANCE_D
end

export type View = { eye: { number }, target: { number }, fov: number }

local EYE = { x = Layout.WIDTH / 2, y = -0.8, h = 1.8 } -- in the playfield's frame: over the lockdown bar
local MARGIN = 3.5 -- degrees kept clear above and below the playfield

-- camera(index, aspect): the player's view. It looks down the playfield from over the lockdown bar, aimed
-- between the playfield's near and far ends, the field of view just wide enough for both (and, on a narrow
-- screen, for its width too). aspect is width / height (default 16:9).
function Cabinet.camera(index: number, aspect: number?): View
	local ex, ey, ez = Cabinet.point(index, EYE.x, EYE.y, EYE.h)
	local function dir(x: number, y: number): (number, number, number)
		local X, Y, D = Cabinet.point(index, x, y, 0)
		local a, b, c = X - ex, Y - ey, D - ez
		local n = math.sqrt(a * a + b * b + c * c)
		return a / n, b / n, c / n
	end
	-- the pitch of the line to the near edge and to the far end (the top of the arch)
	local _, nb, nc = dir(EYE.x, 0)
	local _, fb, fc = dir(EYE.x, Layout.LENGTH)
	local near = math.atan2(nb, math.abs(nc))
	local far = math.atan2(fb, math.abs(fc))
	local mid = (near + far) / 2
	local half = (far - near) / 2 + math.rad(MARGIN)
	-- the width: a front corner seen from the eye must fit inside the horizontal half-angle
	local X0, Y0, D0 = Cabinet.point(index, 0, 0, 0)
	local ax, ay, ad = X0 - ex, Y0 - ey, D0 - ez
	-- (in the camera's own frame: forward along (0, sin mid, -cos mid), up along (0, cos mid, sin mid))
	local fwd = ay * math.sin(mid) - ad * math.cos(mid)
	local side = math.abs(ax)
	local needH = math.atan2(side, fwd) + math.rad(MARGIN)
	local asp = aspect or 16 / 9
	local halfFromWidth = math.atan(math.tan(needH) / asp)
	half = math.max(half, halfFromWidth)
	local tx, ty, tz = ex, ey + math.sin(mid) * 4, ez - math.cos(mid) * 4
	return { eye = { ex, ey, ez }, target = { tx, ty, tz }, fov = math.deg(half * 2) }
end

return Cabinet
