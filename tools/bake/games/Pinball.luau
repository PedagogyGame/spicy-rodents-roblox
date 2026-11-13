--!strict
-- tools/bake/games/Pinball: the three pinball machines in the bowling alley's games room (brief v2 §13a: "three
-- pinball machines, distinct themes, real flipper physics"), built once per station through the bake registry
-- (tools/bake/GameBakes) from the model itself: every rail, guide, post, bumper, slingshot, flipper, target,
-- spinner, gate, kick-out hole, ramp and lamp is where the machine's own Layout (Shared/Minigames/Pinball/
-- TableAcorn, TableSpicy, TableSpace) puts it, set down on the cabinet by Shared/Minigames/Pinball/Cabinet (the
-- playfield's frame, the cabinet's body and backbox, the cabinet's place from AlleyLayout.PINBALLS and
-- PINBALL_D). Nothing here is a number of the playfield's own: what is drawn is what is simulated.
-- Each machine is a cabinet in its own colours on four legs (the back pair longer: that is the playfield's
-- pitch), side rails, a lockdown bar, the glass, a coin door that only says FREE PLAY (no coin is taken, ever),
-- two flipper buttons, the playfield with its apron and title, and the backbox with its backglass (SurfaceGui
-- "Display": Title, Score, Info, Say, Best, which the clients write).
-- The parts the client moves are named (Cabinet.NAMES): Ball1..3, Flipper<i> (a Model whose pivot part "Hub" sits
-- on the pivot pin, half a flipper's height up), Drop<i> (target number), Spinner<k>, Lamp<i>, BumperCap<i>,
-- Sling<i>, the Plunger model (its "Rod" lies along the playfield) and the Backglass. Everything on the
-- playfield is anchored and does not collide (people collide with the cabinet's body only).
-- Lean: a polyline of the model (the arch's 50 pieces) is drawn simplified to within SIMPLIFY studs (a third of
-- the ball's radius), and the posts too small to see over their own guides (the lane dividers' caps) are left
-- to the guides. COST: about 140 parts a machine (the spec tests/unit/pinball_bake.spec.luau prints each and holds
-- them under BUDGET).
-- Interface: { build(kit, parent, station, venue) }; THEMES; BUDGET; SIMPLIFY

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Cabinet = require("../../../src/shared/Minigames/Pinball/Cabinet")
local Layout = require("../../../src/shared/Minigames/Pinball/Layout")
local Tables = require("../../../src/shared/Minigames/Pinball/Tables")

local Bake = {}
Bake.BUDGET = 160 -- parts a machine at most
Bake.SIMPLIFY = 0.02 -- studs: how far a drawn guide may stray from the model's (a third of the ball's radius)

type RGB = { number }
export type Theme = {
	body: RGB, -- the cabinet
	trim: RGB, -- its rails and the backbox's edges
	field: RGB, -- the playfield's paint
	apron: RGB,
	plastic: RGB, -- lane guides, slingshot bodies, ramps
	bumper: RGB,
	cap: RGB,
	target: RGB,
	glow: RGB, -- the backbox's light strip
	legs: RGB,
	art: RGB, -- the backglass's ground
	ink: RGB, -- its lettering
	font: string,
	material: string, -- the cabinet's finish
}

-- Three machines, three looks: an old electro-mechanical in walnut and brass, a hot one in red and black, a
-- space one in deep blue and silver.
Bake.THEMES = {
	acorn = {
		body = { 118, 74, 40 },
		trim = { 196, 160, 92 },
		field = { 206, 172, 112 },
		apron = { 120, 60, 30 },
		plastic = { 230, 150, 50 },
		bumper = { 170, 60, 30 },
		cap = { 255, 236, 180 },
		target = { 240, 200, 60 },
		glow = { 255, 180, 60 },
		legs = { 190, 170, 120 },
		art = { 60, 34, 18 },
		ink = { 255, 214, 120 },
		font = "Bodoni",
		material = "Wood",
	},
	rodent = {
		body = { 30, 22, 26 },
		trim = { 200, 30, 30 },
		field = { 150, 26, 22 },
		apron = { 24, 20, 22 },
		plastic = { 255, 120, 30 },
		bumper = { 255, 200, 40 },
		cap = { 255, 240, 200 },
		target = { 255, 90, 40 },
		glow = { 255, 70, 30 },
		legs = { 40, 40, 44 },
		art = { 20, 8, 8 },
		ink = { 255, 110, 50 },
		font = "FredokaOne",
		material = "SmoothPlastic",
	},
	space = {
		body = { 26, 30, 80 },
		trim = { 190, 200, 220 },
		field = { 22, 34, 90 },
		apron = { 30, 36, 70 },
		plastic = { 120, 220, 255 },
		bumper = { 150, 120, 255 },
		cap = { 220, 240, 255 },
		target = { 120, 255, 160 },
		glow = { 140, 120, 255 },
		legs = { 170, 176, 190 },
		art = { 8, 10, 30 },
		ink = { 140, 230, 255 },
		font = "SciFi",
		material = "SmoothPlastic",
	},
} :: { [string]: Theme }

local LAMP: { [string]: RGB } = {
	red = { 255, 60, 50 },
	green = { 80, 255, 110 },
	amber = { 255, 170, 40 },
	yellow = { 255, 236, 70 },
	orange = { 255, 130, 30 },
	white = { 255, 250, 235 },
	blue = { 80, 150, 255 },
}
local RUBBER = { 245, 245, 240 }
local CHROME = { 205, 208, 214 }
local DARK = { 24, 24, 26 }

-- what each wall material is drawn as: thickness, height
local WALL: { [string]: { t: number, h: number, color: string } } = {
	wood = { t = 0.06, h = 0.2, color = "trim" },
	metal = { t = 0.022, h = 0.11, color = "chrome" },
	plastic = { t = 0.045, h = 0.1, color = "plastic" },
	rubber = { t = 0.035, h = 0.08, color = "rubber" },
}

-- Douglas-Peucker: the polyline's points kept so that none is further than eps from the drawn line
local function simplify(pts: { number }, eps: number): { number }
	local n = #pts // 2
	if n <= 2 then
		return pts
	end
	local keep = table.create(n, false)
	keep[1], keep[n] = true, true
	local function rec(a: number, b: number)
		local ax, ay = pts[a * 2 - 1], pts[a * 2]
		local bx, by = pts[b * 2 - 1], pts[b * 2]
		local dx, dy = bx - ax, by - ay
		local len = math.sqrt(dx * dx + dy * dy)
		local worst, at = 0, 0
		for i = a + 1, b - 1 do
			local px, py = pts[i * 2 - 1] - ax, pts[i * 2] - ay
			local d = if len < 1e-9 then math.sqrt(px * px + py * py) else math.abs(px * dy - py * dx) / len
			if d > worst then
				worst, at = d, i
			end
		end
		if worst > eps then
			keep[at] = true
			rec(a, at)
			rec(at, b)
		end
	end
	rec(1, n)
	local out = {}
	for i = 1, n do
		if keep[i] then
			table.insert(out, pts[i * 2 - 1])
			table.insert(out, pts[i * 2])
		end
	end
	return out
end

local function machine(kit: any, parent: any, index: number, variant: string)
	local CFrame = kit.roblox.CFrame
	local Vector3 = kit.roblox.Vector3
	local tbl = Tables.need(Tables.forVariant(variant) :: string)
	local def = tbl.def
	local th = Bake.THEMES[variant]
	local m = kit:model(parent, Cabinet.model(index))
	m:SetAttribute("Theme", variant)
	m:SetAttribute("Table", tbl.id)
	local px, pd = Cabinet.at(index)
	local W, L = Layout.WIDTH, Layout.LENGTH
	-- the playfield's frame (Cabinet's header): X to the player's right, Y the normal, Z toward the player
	local TILT = CFrame.Angles(0, math.pi, 0) * CFrame.Angles(Cabinet.TILT, 0, 0)
	local loose = { collide = false, query = false, shadow = false }
	local N = Cabinet.NAMES

	-- a part in the playfield's frame: centred at (x, y, h), sized (across, normal, along) before a turn about the
	-- normal that lays its X along a playfield direction
	local function on(
		into: any,
		name: string,
		x: number,
		y: number,
		h: number,
		sx: number,
		sy: number,
		sz: number,
		turn: number,
		color: RGB,
		material: string,
		opts: { [string]: any }?
	): any
		local X, Y, D = Cabinet.point(index, x, y, h)
		local o = table.clone(opts or loose)
		o.rot = TILT * CFrame.Angles(0, turn, 0) * (o.rot or CFrame.new())
		return kit:at(into, name, X, Y, D, sx, sy, sz, color, material, o)
	end
	-- a cylinder standing on the playfield (its axis the normal)
	local function post(
		into: any,
		name: string,
		x: number,
		y: number,
		h0: number,
		h1: number,
		r: number,
		color: RGB,
		material: string,
		opts: { [string]: any }?
	): any
		local o = table.clone(opts or loose)
		o.shape = "Cylinder"
		o.rot = CFrame.Angles(0, 0, math.pi / 2)
		return on(into, name, x, y, (h0 + h1) / 2, h1 - h0, r * 2, r * 2, 0, color, material, o)
	end
	-- a bar along a segment of the playfield
	local function bar(
		into: any,
		name: string,
		x1: number,
		y1: number,
		x2: number,
		y2: number,
		t: number,
		h: number,
		lift: number,
		color: RGB,
		material: string,
		extend: number?
	): any
		local dx, dy = x2 - x1, y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		return on(
			into,
			name,
			(x1 + x2) / 2,
			(y1 + y2) / 2,
			lift + h / 2,
			len + (extend or t),
			h,
			t,
			Cabinet.turnOf(dx, dy),
			color,
			material
		)
	end

	-- THE CABINET (in the playfield's frame: its body is pitched with the playfield, the back legs are longer)
	local body = Cabinet.BODY
	local R = Cabinet.RAIL
	local below = 0.85 -- the body's depth under the playfield
	local G = Cabinet.GLASS_H
	local solid = { collide = true }
	local finish = th.material
	on(m, "Body", W / 2, L / 2 - 0.08, -below + 0.06, W + 2 * R, 0.12, L + 0.36, 0, th.body, finish, solid)
	for side = 0, 1 do
		local x = if side == 0 then -R / 2 else W + R / 2
		on(
			m,
			"SideRail",
			x,
			L / 2 - 0.08,
			(G + 0.05 - below) / 2,
			R,
			G + 0.05 + below,
			L + 0.36,
			0,
			th.body,
			finish,
			solid
		)
		-- the flipper buttons, on the outside of the rails near the front
		local bx = if side == 0 then -R - 0.02 else W + R + 0.02
		on(m, "FlipperButton", bx, 0.25, -0.16, 0.06, 0.1, 0.1, 0, { 230, 40, 40 }, "SmoothPlastic", {
			collide = false,
			query = false,
			shadow = false,
			shape = "Cylinder",
		})
	end
	on(
		m,
		"FrontWall",
		W / 2,
		-0.21,
		(G + 0.05 - below) / 2,
		W + 2 * R,
		G + 0.05 + below,
		0.12,
		0,
		th.body,
		finish,
		solid
	)
	on(m, "BackWall", W / 2, L + 0.04, (G - below) / 2, W + 2 * R, G + below, 0.08, 0, th.body, finish, solid)
	on(m, "LockdownBar", W / 2, -0.21, G + 0.08, W + 2 * R + 0.04, 0.05, 0.13, 0, CHROME, "Metal", solid)
	on(m, "Glass", W / 2, L / 2, G, W, 0.02, L, 0, { 200, 225, 235 }, "Glass", {
		collide = false,
		query = false,
		shadow = false,
		transparency = 0.88,
	})
	-- the playfield board, its apron and the machine's name across it
	on(m, N.playfield, W / 2, L / 2 - 0.08, -0.03, W, 0.06, L + 0.16, 0, th.field, "SmoothPlastic", solid)
	local apronTop = def.drainY + 0.1
	local apron = on(
		m,
		"Apron",
		Layout.XC,
		apronTop / 2 - 0.08,
		0.03,
		1.5,
		0.06,
		apronTop + 0.16,
		math.pi,
		th.apron,
		"SmoothPlastic"
	)
	local ag = kit:gui(apron, "Top", 120)
	kit:label(ag, { Text = tbl.title, TextColor = th.ink, Font = th.font, Size = { 1, 0.8 }, Pos = { 0, 0.1 } })
	-- the coin door: no coin goes in (free play, always)
	local fX, fY, fD = Cabinet.point(index, W / 2, -0.28, -below / 2)
	local door = kit:at(m, "CoinDoor", fX, fY - 0.05, fD + 0.01, 0.7, 0.55, 0.03, { 60, 60, 66 }, "Metal", {
		collide = false,
		rot = TILT,
	})
	kit:label(kit:gui(door, "Back", 80), {
		Text = "FREE PLAY",
		TextColor = { 80, 255, 120 },
		Font = "Arcade",
		Size = { 0.8, 0.25 },
		Pos = { 0.1, 0.12 },
	})
	-- the legs: from the floor to the body's corners (the back pair longer)
	local legs = Cabinet.LEGS
	for _, corner in { { -1, -0.05 }, { 1, -0.05 }, { -1, L - 0.25 }, { 1, L - 0.25 } } do
		local x = if corner[1] < 0 then -R + legs.inset else W + R - legs.inset
		local X, Y, D = Cabinet.point(index, x, corner[2], -below)
		kit:box(
			m,
			"Leg",
			X - legs.size / 2,
			X + legs.size / 2,
			0,
			Y,
			D - legs.size / 2,
			D + legs.size / 2,
			th.legs,
			"Metal"
		)
	end
	-- the backbox on the cabinet's back, its backglass facing the player
	local bb = Cabinet.BACKBOX
	local box = kit:box(
		m,
		"Backbox",
		px - bb.half,
		px + bb.half,
		bb.y0,
		bb.y1,
		pd + bb.back,
		pd + bb.front - 0.06,
		th.body,
		finish
	)
	-- a soft light down over the playfield from the backbox's foot (the lamps under a real backbox)
	kit:light(box, "SpotLight", { Face = "Bottom", Range = 7, Brightness = 1.2, Angle = 70, Color = th.glow })
	local glass = kit:box(
		m,
		N.backglass,
		px - bb.half + 0.12,
		px + bb.half - 0.12,
		bb.y0 + 0.15,
		bb.y1 - 0.15,
		pd + bb.front - 0.06,
		pd + bb.front,
		th.art,
		"SmoothPlastic",
		{ collide = false }
	)
	kit:box(
		m,
		"BackboxTrim",
		px - bb.half,
		px + bb.half,
		bb.y1 - 0.12,
		bb.y1,
		pd + bb.front - 0.06,
		pd + bb.front + 0.02,
		th.glow,
		"Neon",
		{ collide = false }
	)
	local g = kit:gui(glass, "Front", 60)
	g.Name = "Display"
	local function line(name: string, text: string, y: number, h: number, color: RGB, font: string)
		local l = kit:label(g, { Text = text, TextColor = color, Font = font, Size = { 0.94, h }, Pos = { 0.03, y } })
		l.Name = name
	end
	line("Title", tbl.title, 0.03, 0.2, th.ink, th.font)
	line("Score", "FREE PLAY", 0.26, 0.24, { 255, 255, 255 }, "Arcade")
	line("Info", "1 TO 4 PLAYERS", 0.52, 0.1, th.ink, "GothamBold")
	line("Say", "", 0.64, 0.16, { 255, 240, 200 }, "GothamBold")
	line("Best", "", 0.83, 0.12, th.ink, "GothamBold")

	-- THE PLAYFIELD (everything at the model's own numbers)
	local colours = { trim = th.trim, chrome = CHROME, plastic = th.plastic, rubber = RUBBER }
	for wi, w in def.walls do
		local look = WALL[w.mat] or WALL.metal
		local pts = simplify(w.pts, Bake.SIMPLIFY)
		for i = 1, #pts - 3, 2 do
			local x1, y1, x2, y2 = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
			local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
			if len >= 0.03 then
				local mat = if w.mat == "metal" then "Metal" elseif w.mat == "wood" then finish else "SmoothPlastic"
				bar(m, `Wall{wi}`, x1, y1, x2, y2, look.t, look.h, 0, colours[look.color], mat)
			end
		end
	end
	for _, p in def.posts do
		if p.r >= 0.02 then
			post(
				m,
				"Post",
				p.x,
				p.y,
				0,
				if p.mat == "rubber" then 0.11 else 0.14,
				p.r,
				if p.mat == "rubber" then RUBBER else CHROME,
				if p.mat == "rubber" then "SmoothPlastic" else "Metal"
			)
		end
	end
	for i, b in def.bumpers do
		post(m, "Bumper", b.x, b.y, 0, 0.16, b.r, th.bumper, "SmoothPlastic")
		post(m, `{N.bumper}{i}`, b.x, b.y, 0.16, 0.2, b.r * 0.85, th.cap, "SmoothPlastic")
	end
	for i, s in def.slings do
		bar(m, `{N.sling}{i}`, s.x1, s.y1, s.x2, s.y2, 0.035, 0.09, 0, RUBBER, "SmoothPlastic")
	end
	for i, t in def.targets do
		local name = if t.kind == "drop" then `{N.drop}{i}` else `Standup{i}`
		bar(m, name, t.x1, t.y1, t.x2, t.y2, 0.03, 0.12, 0, th.target, "SmoothPlastic", 0)
	end
	for k, n in tbl.c.spinners do
		local s = def.sensors[tbl.c.nRef[n]]
		local dx, dy = s.x2 - s.x1, s.y2 - s.y1
		local len = math.sqrt(dx * dx + dy * dy)
		on(
			m,
			`{N.spinner}{k}`,
			(s.x1 + s.x2) / 2,
			(s.y1 + s.y2) / 2,
			0.1,
			len,
			0.1,
			0.008,
			Cabinet.turnOf(dx, dy),
			CHROME,
			"Metal"
		)
	end
	for _, gte in def.gates do
		bar(m, "Gate", gte.x1, gte.y1, gte.x2, gte.y2, 0.012, 0.05, 0.05, CHROME, "Metal")
	end
	for _, sc in def.saucers do
		post(m, "Saucer", sc.x, sc.y, 0, 0.004, sc.r + Layout.BALL_R, DARK, "SmoothPlastic")
	end
	-- ramps: a plate along each piece of the rail, at its height
	for ri, rail in def.rails do
		local pts = rail.pts
		for i = 1, #pts - 5, 3 do
			local x1, y1, h1 = pts[i], pts[i + 1], pts[i + 2]
			local x2, y2, h2 = pts[i + 3], pts[i + 4], pts[i + 5]
			-- (in the playfield's part frame: X across, Y the normal, Z down the table)
			local v = Vector3.new(x2 - x1, h2 - h1, -(y2 - y1))
			local len = v.Magnitude
			local look = CFrame.lookAt(Vector3.new(0, 0, 0), v)
			local X, Y, D = Cabinet.point(index, (x1 + x2) / 2, (y1 + y2) / 2, (h1 + h2) / 2 - 0.01)
			kit:at(m, `Ramp{ri}`, X, Y, D, Layout.BALL_R * 2 + 0.06, 0.02, len + 0.02, th.plastic, "SmoothPlastic", {
				collide = false,
				query = false,
				shadow = false,
				transparency = 0.35,
				rot = TILT * look,
			})
		end
	end
	for i, l in def.lamps do
		post(m, `{N.lamp}{i}`, l.x, l.y, 0, 0.006, 0.05, LAMP[l.colour] or LAMP.white, "SmoothPlastic")
	end
	-- the flippers: a hub on the pin, the bat and its tip; the model turns about the pin
	local c = tbl.c
	for i = 1, c.nFlip do
		local fm = kit:model(m, `{N.flipper}{i}`)
		local a = c.frest[i]
		local dx, dy = c.fmir[i] * math.cos(a), math.sin(a)
		local turn = Cabinet.turnOf(dx, dy)
		local h = Cabinet.FLIPPER_H
		-- (the pivot part's own frame is the flipper's: on the pin, X along the bat, Y the normal; it is not seen)
		local hub = on(fm, "Hub", c.fpx[i], c.fpy[i], h / 2, 0.02, 0.02, 0.02, turn, RUBBER, "SmoothPlastic", {
			collide = false,
			query = false,
			shadow = false,
			transparency = 1,
		})
		fm.PrimaryPart = hub
		post(fm, "Pin", c.fpx[i], c.fpy[i], 0, h, c.frb[i], RUBBER, "SmoothPlastic")
		local len = c.flen[i]
		local tx, ty = c.fpx[i] + dx * len, c.fpy[i] + dy * len
		bar(fm, "Bat", c.fpx[i], c.fpy[i], tx, ty, c.frb[i] + c.frt[i], h, 0, RUBBER, "SmoothPlastic", 0)
		post(fm, "Tip", tx, ty, 0, h, c.frt[i], { 230, 60, 50 }, "SmoothPlastic")
	end
	-- the balls (the first on the plunger; the others hidden there until a multiball)
	local p = def.plunger
	for i = 1, Cabinet.BALLS do
		local X, Y, D = Cabinet.point(index, p.x, p.y, Layout.BALL_R)
		kit:ball(m, `{N.ball}{i}`, X, Y, D, Layout.BALL_R * 2, CHROME, "Metal", {
			collide = false,
			query = false,
			transparency = if i == 1 then 0 else 1,
			rot = TILT,
		})
	end
	-- the plunger: its rod along the shooter lane, through the front wall to the knob
	local pm = kit:model(m, N.plunger)
	local rodY0, rodY1 = -0.45, p.y - Layout.BALL_R
	local rod = on(pm, "Rod", p.x, (rodY0 + rodY1) / 2, 0.04, 0.035, 0.035, rodY1 - rodY0, 0, CHROME, "Metal")
	pm.PrimaryPart = rod
	on(pm, "Knob", p.x, rodY0 - 0.05, 0.04, 0.11, 0.11, 0.1, 0, { 230, 40, 40 }, "SmoothPlastic")
end

function Bake.build(kit: any, parent: any, station: any, _venue: any?)
	if station.joins then
		return
	end
	assert(AlleyLayout.PINBALLS[station.index], `no pinball machine {station.index}`)
	machine(kit, parent, station.index, station.variant)
end

return Bake
