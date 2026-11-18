--!strict
-- ReplicatedStorage.Shared.Minigames.WhackAMole.Layout
-- Where the whack-a-mole cabinet stands in the bowling alley's games room and the size of every part of it that
-- the game, the bake and the client agree on: one place, so what is drawn is where the mallet lands.
-- The numbers are the owner's model (docs/reference/whack_a_mole/Whack_A_Mole.glb), measured with
-- tools/games/whack_a_mole/measure.py and turned into studs at 1 / 0.28 per metre (the pinball cabinets' scale:
-- the cabinet stands about 7.7 studs tall).
-- Two frames:
--   the cabinet's own: u across (+u is the owner's +X, the player's right), v up from the floor, w into the
--     cabinet (+w is the owner's +Y, toward the sign; the player stands at -w). Studs. The owner's metres are
--     m(x) studs.
--   the alley's site frame (Attractions/AlleyLayout: X across, Y up, D into the site): the cabinet stands with
--     its back to the games room's front wall, to the right of the pinball row, facing into the room (+D), so
--     X = AT.x - u and D = AT.d - w (a half turn: the player, looking toward -D, has -X on the right).
-- The floor it keeps for the player and for people watching (STANDING) is clear of every other table's floor,
-- the room's fixtures, the staff posts and routes and the doorways (tests/unit/whack_layout.spec.luau, against
-- AlleyLayout's own lists; AlleyLayout is not edited).
-- Pure. Interface: M_TO_STUDS; m(metres) -> studs; AT { x, d }; toSite(u, v, w) -> (X, Y, D); toCabinet(X, Y, D)
--   -> (u, v, w); HOLES { { u, w } } (1, 2, 3 the back row left to right, 4, 5 the front); hole(i) -> (u, v, w)
--   (the middle of the hole at the deck's face); DECK { ... }; MOLE { ... }; SIGN { ... }; WINDOWS { score,
--   time }; MALLET { ... }; PLATE (the FREE PLAY plate); BODY (the cabinet's box); STANDING { x0, x1, d0, d1 };
--   STAND { u, w } (where the player stands); PROMPT { u, v, w }; COLORS (name -> sRGB); NAMES; EYE, LOOK,
--   camera(aspect) -> (eye, look, fov); framePoints(); inCamera(p) -> (x, y, z)

local AlleyLayout = require("../../Attractions/AlleyLayout")

local Layout = {}

Layout.M_TO_STUDS = 1 / 0.28

function Layout.m(metres: number): number
	return metres * Layout.M_TO_STUDS
end
local m = Layout.m

-- The cabinet's back is one stud off the front wall, like the pinball machines'; its middle is AT.
local BACK_W = 0.607 -- metres: the back of the sign's timber case (the cabinet's deepest point)
Layout.AT = {
	x = 124,
	d = AlleyLayout.GAME_ROOM_D0 + 1 + m(BACK_W),
}

function Layout.toSite(u: number, v: number, w: number): (number, number, number)
	return Layout.AT.x - u, v, Layout.AT.d - w
end

function Layout.toCabinet(X: number, Y: number, D: number): (number, number, number)
	return Layout.AT.x - X, Y, Layout.AT.d - D
end

-- The five holes, measured (metres): the back row 1, 2, 3 at +0.205, the front row 4, 5 at -0.275. The keys 1-5
-- are these numbers, as on the owner's deck.
local HOLES_M = { { -0.47, 0.205 }, { 0, 0.205 }, { 0.47, 0.205 }, { -0.245, -0.275 }, { 0.245, -0.275 } }
Layout.HOLES = {} :: { { number } }
for i, h in HOLES_M do
	Layout.HOLES[i] = { m(h[1]), m(h[2]) }
end

-- The deck: solid timber with a leather insert, holes cut through both, a brass rail round the edge.
Layout.DECK = {
	top = m(1.113), -- the leather's face (where a hole's middle is)
	timberBottom = m(0.998),
	timberTop = m(1.103),
	halfU = m(0.81),
	w0 = m(-0.565),
	w1 = m(0.565),
	insertHalfU = m(0.765),
	insertW0 = m(-0.522),
	insertW1 = m(0.512),
	railTop = m(1.123),
	holeR = m(0.145), -- the cut
	lipR = m(0.153), -- the polished brass lip's middle line (a torus of tube radius lipTube)
	lipTube = m(0.012),
	wellFloor = m(0.54), -- the dark floor of each well
}

function Layout.hole(i: number): (number, number, number)
	local h = Layout.HOLES[i]
	return h[1], Layout.DECK.top, h[2]
end

-- A mole at rest (all the way down): the measured parts' bounds, relative to its hole's middle (u, w) and the
-- floor (v). Raised, the whole mole goes up by `pop` (the owner's 0.30 m: the head clears the deck, the body's
-- foot stays in the well).
Layout.MOLE = {
	pop = m(0.30),
	bodyR = m(0.102), -- the body: a spheroid, radius across
	bodyRw = m(0.094), -- radius front to back
	bodyHalfV = m(0.18),
	bodyV = m(0.73), -- its middle, at rest
	headR = m(0.118),
	headRw = m(0.105),
	headHalfV = m(0.114),
	headV = m(0.911),
	topV = m(1.025), -- the top of the head, at rest
	muzzleW = m(-0.083), -- the muzzle and nose sit forward (toward the player)
	noseW = m(-0.122),
	earU = m(0.104),
	earV = m(0.969),
	-- each mole's fur, as the owner coloured them (cocoa, taupe, charcoal, taupe, cocoa)
	fur = { "cocoa", "taupe", "charcoal", "taupe", "cocoa" },
}

-- The body under the deck, and the base it stands on.
Layout.BODY = {
	halfU = m(0.752),
	w0 = m(-0.509),
	w1 = m(0.509),
	v0 = m(0.232),
	v1 = m(1.012),
	plinthHalfU = m(0.785),
	plinthHalfW = m(0.54),
	plinthV0 = m(0.04),
	plinthV1 = m(0.21),
}

-- The sign: a timber case behind the deck with an ebony face, a brass surround, WHACK / A MOLE, and the SCORE
-- and TIME windows whose numbers are live (the client writes them).
Layout.SIGN = {
	halfU = m(0.795),
	w0 = m(0.421),
	w1 = m(BACK_W),
	v0 = m(1.06),
	v1 = m(2.16),
	faceHalfU = m(0.723),
	faceW = m(0.387), -- the ebony face's front
	faceV0 = m(1.153),
	faceV1 = m(2.107),
	titleV = m(1.904), -- WHACK
	title2V = m(1.748), -- A MOLE
	statusV = m(1.271), -- the line under the windows
}

-- The two windows: brass frame, dark glass, a heading and the number (metres measured, studs here).
local function window(uM: number): { [string]: number }
	return {
		u = m(uM),
		v = m(1.476),
		frameW = m(0.52),
		frameH = m(0.24),
		glassW = m(0.484),
		glassH = m(0.206),
		glassFront = m(0.346), -- the glass's face (w), toward the player
		headV = m(1.538),
	}
end
Layout.WINDOWS = { score = window(-0.345), time = window(0.345) }

-- The mallet: at rest in its bracket on the player's right; the pivot is the bottom of its handle.
Layout.MALLET = {
	rest = { m(1.12), m(0.42), m(-0.25) }, -- (u, v, w) of the pivot
	handleLen = m(0.57),
	handleR = m(0.024),
	headAt = m(0.60), -- the head's middle, along the handle from the pivot
	headLen = m(0.285),
	headR = m(0.098),
	-- his demonstration's swing: over a hole the pivot is held this far toward the player (-w) and this high,
	-- the handle tipped back RAISED (radians about the cabinet's across axis) and brought down to STRUCK, where
	-- the head is over the hole's middle just above a raised mole's head
	reachW = m(-0.564),
	strikeV = m(1.63),
	raised = math.rad(-50),
	struck = math.rad(-110),
	-- at rest in its bracket: turned about the vertical, then tipped sideways (his rotation (0, -16, -12) deg)
	restYaw = math.rad(-12),
	restTip = math.rad(16),
}

-- The FREE PLAY plate, where the owner's coin door was (no coins, ever: brief v2 §13a, D13 rating).
Layout.PLATE = { v = m(0.55), w = m(-0.539), width = m(0.295), height = m(0.27) }

-- His materials as they look in his preview (sRGB): the baked parts are painted with them, and so are the meshes
-- from his Blender file (src/server/Assets/WhackArt; a MeshPart has one colour). Never green on a mole.
Layout.COLORS = {
	wood = { 132, 26, 32 }, -- oxblood lacquered timber
	black = { 28, 31, 34 }, -- ebony lacquer
	brass = { 201, 154, 74 },
	gold = { 226, 196, 136 }, -- champagne trim
	cream = { 238, 222, 186 }, -- warm ivory enamel
	felt = { 44, 104, 98 }, -- deep petrol leather (the deck, never a mole)
	dark = { 16, 14, 16 }, -- the holes
	amber = { 255, 150, 60 }, -- the score phosphor
	bulb = { 255, 196, 120 },
	cocoa = { 150, 104, 74 },
	taupe = { 156, 132, 114 },
	charcoal = { 96, 86, 82 },
	muzzle = { 222, 176, 140 },
	nose = { 200, 112, 104 },
	eye = { 10, 10, 12 },
	glint = { 240, 232, 200 }, -- the catchlight in a mole's eye
	rubber = { 132, 28, 40 }, -- the mallet's padded head
	handle = { 110, 24, 30 },
} :: { [string]: { number } }

-- The names the bake gives the parts the client moves and writes on (and the art loader keeps).
Layout.NAMES = {
	model = "WhackAMole", -- under the games room
	mole = "Mole", -- Mole1 .. Mole5: a Model each, its pivot at the mole's rest
	mallet = "Mallet", -- a Model, its pivot at the bottom of the handle
	score = "ScoreWindow", -- parts with a SurfaceGui "Display" holding a TextLabel "Value"
	time = "TimeWindow",
	status = "StatusLine",
	display = "Display",
	value = "Value",
}

-- The camera: from above and behind the player's head, looking down at the deck with the sign's windows in
-- view. camera(aspect) -> eye, target (cabinet frame) and the vertical field of view (degrees) that keeps the
-- whole deck, the five holes and both windows on a screen of that shape (width / height), with a margin.
Layout.EYE = { 0, 9.4, -6.6 }
Layout.LOOK = { 0, 4.9, 0.3 }
Layout.FOV_MIN = 40
Layout.FOV_MAX = 80
Layout.FRAME_MARGIN = 1.1

-- the points the camera must show (cabinet frame): the deck's four corners, the windows' corners
function Layout.framePoints(): { { number } }
	local d = Layout.DECK
	local out = {
		{ -d.halfU, d.railTop, d.w0 },
		{ d.halfU, d.railTop, d.w0 },
		{ -d.halfU, d.railTop, d.w1 },
		{ d.halfU, d.railTop, d.w1 },
	}
	for _, win in { Layout.WINDOWS.score, Layout.WINDOWS.time } do
		for _, su in { -1, 1 } do
			for _, sv in { -1, 1 } do
				table.insert(out, { win.u + su * win.frameW / 2, win.v + sv * win.frameH / 2, win.glassFront })
			end
		end
	end
	return out
end

-- a point (cabinet frame) in the camera's own frame: across (right), up, and how far ahead
function Layout.inCamera(p: { number }): (number, number, number)
	local e, t = Layout.EYE, Layout.LOOK
	local fx, fy, fz = t[1] - e[1], t[2] - e[2], t[3] - e[3]
	local fl = math.sqrt(fx * fx + fy * fy + fz * fz)
	fx, fy, fz = fx / fl, fy / fl, fz / fl
	-- right = forward x up (the cabinet frame is u right, v up, w ahead: a player facing +w has +u on the right)
	local rx, ry, rz = fz, 0, -fx
	local rl = math.sqrt(rx * rx + rz * rz)
	rx, rz = rx / rl, rz / rl
	-- up = forward x right (written out for this frame, whose axes u, v, w are left-handed)
	local ux, uy, uz = fy * rz - fz * ry, fz * rx - fx * rz, fx * ry - fy * rx
	local px, py, pz = p[1] - e[1], p[2] - e[2], p[3] - e[3]
	return px * rx + py * ry + pz * rz, px * ux + py * uy + pz * uz, px * fx + py * fy + pz * fz
end

function Layout.camera(aspect: number): ({ number }, { number }, number)
	local need = 0
	for _, p in Layout.framePoints() do
		local x, y, z = Layout.inCamera(p)
		need = math.max(need, math.abs(y) / z, math.abs(x) / (z * aspect))
	end
	local fov = math.deg(2 * math.atan(need * Layout.FRAME_MARGIN))
	return Layout.EYE, Layout.LOOK, math.clamp(fov, Layout.FOV_MIN, Layout.FOV_MAX)
end

-- Where the player stands (a little in front of the deck, in the middle), and the prompt.
Layout.STAND = { u = 0, w = m(-0.565) - 2.4 }
Layout.PROMPT = { u = 0, v = 3, w = m(-0.565) - 1 }
-- Studs from the prompt within which a bystander is sent the round as it goes (the server's ring); a screen
-- further off draws the cabinet at rest instead of a round it is no longer told about.
Layout.WATCH = 40

-- The floor kept for the game: the cabinet with its mallet bracket on the player's right, the player in front,
-- and room either side to stand and watch. In the site frame.
do
	local x0 = Layout.AT.x - m(1.16) - 1 -- the mallet's side (the player's right is -X)
	local x1 = Layout.AT.x + m(0.81) + 1.5
	Layout.STANDING = {
		x0 = x0,
		x1 = x1,
		d0 = AlleyLayout.GAME_ROOM_D0,
		d1 = Layout.AT.d - Layout.STAND.w + 1,
	}
end

return Layout
