--!strict
-- tools/bake/games/WhackAMole: the owner's whack-a-mole cabinet in the bowling alley's games room
-- (docs/reference/whack_a_mole; docs/owner/DELIVERY_2026-11-18.md), built once for its station through the bake
-- registry (tools/bake/GameBakes) from plain parts at the places and sizes of his model's parts, as measured
-- from his GLB (Shared/Minigames/WhackAMole/Layout, in studs at 1 / 0.28 a metre: 7.7 studs tall). Nothing here
-- is a number of the cabinet's own that the game reads: Layout is the one source, and the rest of the owner's
-- metres below are his build script's, for parts that only dress the cabinet.
-- What is built (WhackAMole, a Model under the games room; the cabinet frame is Layout's):
--   Shell: the plinth and its feet, the oxblood body with its ebony front panel, brass trim and fluting, the
--     ebony side insets with their brass borders and gold ribs, the deck (timber with a petrol leather insert,
--     brass edge rails, each hole a dark mouth in a brass lip, its number beside it), the sign's timber case,
--     brass surround and ebony face (THE MIDNIGHT ARCADE, WHACK, A MOLE, the deco bars), the warm bulbs, the
--     mallet's bracket, and a FREE PLAY plate where his coin door was (no coins, ever). MIDNIGHT AMUSEMENTS is
--     written on the front panel.
--   Mole1..5: a Model each (its PrimaryPart the body, at rest inside the deck), the friendly mole of his model
--     in his fur colours (cocoa, taupe, charcoal, taupe, cocoa): body, head, muzzle, rosy nose, ears, eyes,
--     teeth and paws. The client lifts each by Layout.MOLE.pop as the round has it.
--   Mallet: a Model whose PrimaryPart "Pivot" is the bottom of the handle, laid in its bracket as his model
--     rests it; the client swings it.
--   ScoreWindow, TimeWindow, StatusLine: the sign's windows and the line under them, each with a SurfaceGui
--     "Display" holding the TextLabel "Value" the clients write (amber digits).
-- Spheroids are a block with a sphere mesh (one part each). The deck, the body, the plinth and the sign collide;
-- every trim, the moles and the mallet do not.
-- COST: 149 parts (85 shell, 55 moles, 6 mallet, 3 windows; tests/unit/whack_bake.spec.luau prints it and holds it under
-- BUDGET), no textures, no lights; the lettering is SurfaceGui text. The meshes from his Blender file replace the
-- shell, the moles and the mallet when they are uploaded (src/server/Assets/WhackArt).
-- Interface: { build(kit, parent, station, venue) }; BUDGET; COLORS (= Layout.COLORS)

local Layout = require("../../../src/shared/Minigames/WhackAMole/Layout")

local Bake = {}
Bake.BUDGET = 160 -- parts at most (a pinball machine's budget)

Bake.COLORS = Layout.COLORS -- (his materials as they look in his preview: Layout keeps them for the art loader too)
local C = Bake.COLORS
local m = Layout.m

function Bake.build(kit: any, parent: any, station: any, _venue: any?)
	if station.joins then
		return
	end
	local roblox = kit.roblox
	local CFrame = roblox.CFrame
	local N = Layout.NAMES
	local root = kit:model(parent, N.model)
	local shell = kit:model(root, "Shell")
	-- the cabinet frame's turn in the site's (a half turn: +u is the site's -X, +w its -D)
	local HALF = CFrame.Angles(0, math.pi, 0)

	-- a box between two corners of the cabinet frame
	local function box(
		into: any,
		name: string,
		u0: number,
		u1: number,
		v0: number,
		v1: number,
		w0: number,
		w1: number,
		color: { number },
		material: string,
		collide: boolean?
	): any
		local X0, _, D0 = Layout.toSite(u0, 0, w0)
		local X1, _, D1 = Layout.toSite(u1, 0, w1)
		return kit:box(into, name, X0, X1, v0, v1, D0, D1, color, material, { collide = collide == true })
	end
	-- the same in his metres: centre and size
	local function mbox(
		into: any,
		name: string,
		cu: number,
		cv: number,
		cw: number,
		su: number,
		sv: number,
		sw: number,
		color: { number },
		material: string,
		collide: boolean?
	): any
		return box(
			into,
			name,
			m(cu - su / 2),
			m(cu + su / 2),
			m(cv - sv / 2),
			m(cv + sv / 2),
			m(cw - sw / 2),
			m(cw + sw / 2),
			color,
			material,
			collide
		)
	end
	-- an upright spheroid (a block with a sphere mesh), centre and full size in studs
	local function spheroid(
		into: any,
		name: string,
		u: number,
		v: number,
		w: number,
		su: number,
		sv: number,
		sw: number,
		color: { number },
		material: string?
	): any
		local X, Y, D = Layout.toSite(u, v, w)
		local p = kit:at(into, name, X, Y, D, su, sv, sw, color, material or "SmoothPlastic", { collide = false })
		local mesh = roblox.Instance.new("SpecialMesh")
		mesh.MeshType = roblox.Enum.MeshType.Sphere
		mesh.Parent = p
		return p
	end
	-- a cylinder along "X" (across), "Y" (up) or "D" (front to back), centre in studs
	local function cyl(
		into: any,
		name: string,
		u: number,
		v: number,
		w: number,
		length: number,
		diameter: number,
		axis: string,
		color: { number },
		material: string,
		collide: boolean?
	): any
		local X, Y, D = Layout.toSite(u, v, w)
		return kit:cyl(into, name, X, Y, D, length, diameter, axis, color, material, { collide = collide == true })
	end
	local function text(
		gui: any,
		words: string,
		x: number,
		y: number,
		w: number,
		h: number,
		color: { number },
		font: string
	)
		kit:label(gui, { Text = words, TextColor = color, Font = font, Pos = { x, y }, Size = { w, h } })
	end

	-- the plinth and its feet ------------------------------------------------------------------------------
	local B = Layout.BODY
	box(
		shell,
		"Plinth",
		-B.plinthHalfU,
		B.plinthHalfU,
		B.plinthV0,
		B.plinthV1,
		-B.plinthHalfW,
		B.plinthHalfW,
		C.black,
		"SmoothPlastic",
		true
	)
	mbox(shell, "PlinthReveal", 0, 0.216, 0, 1.50, 0.018, 1.015, C.brass, "Metal")
	for _, fu in { -0.6, 0.6 } do
		for _, fw in { -0.39, 0.39 } do
			cyl(shell, "Foot", m(fu), m(0.047), m(fw), m(0.085), m(0.124), "Y", C.black, "SmoothPlastic")
		end
	end

	-- the body: four walls round the hollow the moles drop into --------------------------------------------------
	box(shell, "Front", -m(0.715), m(0.715), B.v0, B.v1, B.w0, -m(0.437), C.wood, "SmoothPlastic", true)
	box(shell, "Rear", -m(0.715), m(0.715), B.v0, B.v1, m(0.437), B.w1, C.wood, "SmoothPlastic", true)
	box(shell, "SideLeft", -B.halfU, -m(0.68), B.v0, B.v1, -m(0.475), m(0.475), C.wood, "SmoothPlastic", true)
	box(shell, "SideRight", m(0.68), B.halfU, B.v0, B.v1, -m(0.475), m(0.475), C.wood, "SmoothPlastic", true)
	-- the front panel: ebony inset, brass frame, the art deco fluting, MIDNIGHT AMUSEMENTS
	local panel = mbox(shell, "FrontPanel", 0, 0.64, -0.5145, 1.21, 0.58, 0.025, C.black, "SmoothPlastic")
	local panelGui = kit:gui(panel, "Front", 60)
	text(panelGui, "MIDNIGHT", 0.3, 0.27, 0.4, 0.07, C.gold, "Merriweather")
	text(panelGui, "A M U S E M E N T S", 0.4, 0.37, 0.2, 0.025, C.cream, "Gotham")
	for _, z in { 0.34, 0.94 } do
		mbox(shell, "PanelTrim", 0, z, -0.532, 1.24, 0.014, 0.012, C.brass, "Metal")
	end
	for _, x in { -0.615, 0.615 } do
		mbox(shell, "PanelTrim", x, 0.64, -0.532, 0.014, 0.59, 0.012, C.brass, "Metal")
	end
	for _, x in { -0.51, -0.46, -0.41, 0.41, 0.46, 0.51 } do
		local h = if math.abs(x) > 0.49 then 0.25 elseif math.abs(x) > 0.44 then 0.33 else 0.41
		mbox(shell, "Flute", x, 0.64, -0.536, 0.009, h, 0.009, C.brass, "Metal")
	end
	-- FREE PLAY, where his coin door was
	local P = Layout.PLATE
	box(
		shell,
		"PlateSurround",
		-P.width / 2,
		P.width / 2,
		P.v - P.height / 2,
		P.v + P.height / 2,
		-m(0.553),
		-m(0.525),
		C.brass,
		"Metal"
	)
	local plate = box(
		shell,
		"Plate",
		-m(0.132),
		m(0.132),
		P.v - m(0.1185),
		P.v + m(0.1185),
		-m(0.564),
		-m(0.55),
		C.black,
		"SmoothPlastic"
	)
	local plateGui = kit:gui(plate, "Front", 80)
	text(plateGui, "FREE", 0.1, 0.18, 0.8, 0.3, C.cream, "GothamBold")
	text(plateGui, "PLAY", 0.1, 0.52, 0.8, 0.3, C.cream, "GothamBold")
	-- the sides: an ebony inset in a brass border, three gold ribs
	for _, side in { -1, 1 } do
		local x = side * 0.716
		local out = side * 0.037
		mbox(shell, "SideInset", x + out, 0.62, 0, 0.012, 0.56, 0.68, C.black, "SmoothPlastic")
		for _, y in { -0.34, 0.34 } do
			mbox(shell, "SideBorder", x + side * 0.047, 0.62, y, 0.008, 0.57, 0.012, C.brass, "Metal")
		end
		for _, z in { 0.337, 0.903 } do
			mbox(shell, "SideBorder", x + side * 0.047, z, 0, 0.008, 0.012, 0.69, C.brass, "Metal")
		end
		for _, y in { -0.24, 0, 0.24 } do
			mbox(shell, "SideRib", x + side * 0.046, 0.62, y, 0.009, 0.37, 0.008, C.gold, "Metal")
		end
	end

	-- the deck ------------------------------------------------------------------------------------------------
	local Dk = Layout.DECK
	box(shell, "Deck", -Dk.halfU, Dk.halfU, Dk.timberBottom, Dk.timberTop, Dk.w0, Dk.w1, C.wood, "SmoothPlastic", true)
	-- (turned a half turn with the cabinet, so the numbers on its top read the right way up to the player:
	-- a Top face's SurfaceGui has its top edge toward the part's -Z and its right along +X)
	local lu, lw = 0, (Dk.insertW0 + Dk.insertW1) / 2
	local LX, _, LD = Layout.toSite(lu, 0, lw)
	local leather = kit:at(
		shell,
		"DeckLeather",
		LX,
		(Dk.timberTop + Dk.top) / 2,
		LD,
		2 * Dk.insertHalfU,
		Dk.top - Dk.timberTop,
		Dk.insertW1 - Dk.insertW0,
		C.felt,
		"Fabric",
		{ collide = true, rot = HALF }
	)
	for _, x in { -0.778, 0.778 } do
		mbox(shell, "DeckRail", x, 1.118, -0.005, 0.009, 0.011, 1.055, C.brass, "Metal")
	end
	for _, y in { -0.532, 0.522 } do
		mbox(shell, "DeckRail", 0, 1.118, y, 1.56, 0.011, 0.009, C.brass, "Metal")
	end
	-- each hole: a brass lip standing just proud of the leather, the dark mouth on it, its number on the leather
	local numbers = kit:gui(leather, "Top", 40)
	local spanU = 2 * Dk.insertHalfU
	local spanW = Dk.insertW1 - Dk.insertW0
	for i = 1, 5 do
		local hu, hv, hw = Layout.hole(i)
		local lip = 2 * (Dk.lipR + Dk.lipTube)
		cyl(shell, `Lip{i}`, hu, hv + m(0.008) / 2, hw, m(0.008), lip, "Y", C.brass, "Metal")
		cyl(shell, `Hole{i}`, hu, hv + m(0.009), hw, m(0.002), 2 * Dk.holeR, "Y", C.dark, "SmoothPlastic")
		-- (on the turned leather the gui's left edge is the cabinet's -u and its top edge the sign's side, +w)
		local nu, nw = hu, hw - m(0.196)
		local fx = (nu + Dk.insertHalfU) / spanU
		local fy = (Dk.insertW1 - nw) / spanW
		text(numbers, tostring(i), fx - 0.02, fy - 0.025, 0.04, 0.05, C.cream, "GothamBold")
	end

	-- the sign ------------------------------------------------------------------------------------------------
	local S = Layout.SIGN
	box(shell, "SignCase", -S.halfU, S.halfU, S.v0, S.v1, S.w0, S.w1, C.wood, "SmoothPlastic", true)
	box(shell, "SignSurround", -m(0.743), m(0.743), m(1.133), m(2.127), m(0.403), m(0.421), C.brass, "Metal")
	local face = box(
		shell,
		"SignFace",
		-S.faceHalfU,
		S.faceHalfU,
		S.faceV0,
		S.faceV1,
		S.faceW,
		m(0.407),
		C.black,
		"SmoothPlastic"
	)
	local faceGui = kit:gui(face, "Front", 50)
	local faceH = S.faceV1 - S.faceV0
	local function row(v: number, h: number): (number, number)
		return (S.faceV1 - v - h / 2) / faceH, h / faceH
	end
	local y, h = row(m(2.036), m(0.04))
	text(faceGui, "T H E   M I D N I G H T   A R C A D E", 0.25, y, 0.5, h, C.gold, "Gotham")
	y, h = row(S.titleV, m(0.15))
	text(faceGui, "WHACK", 0.2, y, 0.6, h, C.cream, "Merriweather")
	y, h = row(S.title2V, m(0.125))
	text(faceGui, "A MOLE", 0.25, y, 0.5, h, C.cream, "Merriweather")
	for _, x in { -0.56, 0.56 } do
		for _, z in { 1.80, 1.86, 1.92 } do
			mbox(shell, "DecoBar", x, z, 0.374, 0.09, 0.007, 0.008, C.brass, "Metal")
		end
	end
	mbox(shell, "Divider", 0, 1.652, 0.375, 1.20, 0.008, 0.008, C.brass, "Metal")
	-- the warm bulbs down both sides and along the top
	for _, x in { -0.678, 0.678 } do
		for _, z in { 1.27, 1.41, 1.55, 1.69, 1.83, 1.97 } do
			spheroid(shell, "Bulb", m(x), m(z), m(0.36), m(0.03), m(0.03), m(0.022), C.bulb, "Neon")
		end
	end
	for _, x in { -0.45, -0.225, 0, 0.225, 0.45 } do
		spheroid(shell, "Bulb", m(x), m(2.092), m(0.371), m(0.024), m(0.024), m(0.02), C.bulb, "Neon")
	end
	-- the windows: a brass frame, dark glass, the heading and the number the clients write
	for key, name in { score = N.score, time = N.time } do
		local W = Layout.WINDOWS[key]
		box(
			shell,
			`{name}Frame`,
			W.u - W.frameW / 2,
			W.u + W.frameW / 2,
			W.v - W.frameH / 2,
			W.v + W.frameH / 2,
			m(0.362),
			m(0.386),
			C.brass,
			"Metal"
		)
		local glass = box(
			root,
			name,
			W.u - W.glassW / 2,
			W.u + W.glassW / 2,
			W.v - W.glassH / 2,
			W.v + W.glassH / 2,
			W.glassFront,
			m(0.361),
			C.dark,
			"Glass"
		)
		local gui = kit:gui(glass, "Front", 60)
		gui.Name = N.display
		local head = (W.v + W.glassH / 2 - W.headV) / W.glassH
		text(gui, if key == "score" then "SCORE" else "TIME", 0.35, head - 0.08, 0.3, 0.14, C.cream, "Gotham")
		local value = kit:label(gui, {
			Text = if key == "score" then "000" else "45",
			TextColor = C.amber,
			Font = "GothamBold",
			Pos = { 0.2, 0.32 },
			Size = { 0.6, 0.55 },
		})
		value.Name = N.value
	end
	-- the line under the windows (his FIVE HOLES / ONE GOOD TIME): the round's words while one is on
	local status = box(
		root,
		N.status,
		-m(0.45),
		m(0.45),
		S.statusV - m(0.025),
		S.statusV + m(0.025),
		m(0.383),
		m(0.386),
		C.black,
		"SmoothPlastic"
	)
	status.Transparency = 1
	local statusGui = kit:gui(status, "Front", 80)
	statusGui.Name = N.display
	local line = kit:label(statusGui, { Text = "FREE PLAY  -  PRESS E", TextColor = C.gold, Font = "GothamBold" })
	line.Name = N.value

	-- the mallet's bracket, on the player's right
	mbox(shell, "MalletBracket", 0.865, 0.92, -0.25, 0.25, 0.045, 0.10, C.brass, "Metal")

	-- the moles ------------------------------------------------------------------------------------------------
	local M = Layout.MOLE
	for i = 1, 5 do
		local hu, _, hw = Layout.hole(i)
		local fur = C[M.fur[i]] or C.cocoa
		local mole = kit:model(root, `{N.mole}{i}`)
		local body = spheroid(mole, "Body", hu, M.bodyV, hw, 2 * M.bodyR, 2 * M.bodyHalfV, 2 * M.bodyRw, fur)
		spheroid(mole, "Head", hu, M.headV, hw, 2 * M.headR, 2 * M.headHalfV, 2 * M.headRw, fur)
		spheroid(mole, "Muzzle", hu, m(0.884), hw + M.muzzleW, m(0.156), m(0.094), m(0.076), C.muzzle)
		spheroid(mole, "Nose", hu, m(0.902), hw + M.noseW, m(0.06), m(0.04), m(0.044), C.nose)
		for _, side in { -1, 1 } do
			spheroid(mole, "Ear", hu + side * M.earU, M.earV, hw + m(0.008), m(0.05), m(0.062), m(0.044), fur)
			spheroid(
				mole,
				"Eye",
				hu + side * m(0.044),
				m(0.944),
				hw - m(0.089),
				m(0.026),
				m(0.03),
				m(0.018),
				C.eye,
				"Glass"
			)
			spheroid(mole, "Paw", hu + side * m(0.075), m(0.817), hw - m(0.068), m(0.064), m(0.05), m(0.06), C.muzzle)
		end
		box(
			mole,
			"Teeth",
			hu - m(0.02),
			hu + m(0.02),
			m(0.8565),
			m(0.8735),
			hw - m(0.1235),
			hw - m(0.1105),
			C.cream,
			"SmoothPlastic"
		)
		mole.PrimaryPart = body
	end

	-- the mallet, at rest in its bracket: built about its pivot (the handle's foot), handle along its +Y --------
	local MA = Layout.MALLET
	local X, Y, D = Layout.toSite(MA.rest[1], MA.rest[2], MA.rest[3])
	local pivotCF = kit:cf(X, Y, D, HALF * CFrame.Angles(0, MA.restYaw, 0) * CFrame.Angles(0, 0, MA.restTip))
	local mallet = kit:model(root, N.mallet)
	local function piece(
		name: string,
		offset: { number },
		length: number,
		diameter: number,
		alongY: boolean,
		color: { number },
		material: string
	): any
		local p = kit:at(
			mallet,
			name,
			0,
			0,
			0,
			length,
			diameter,
			diameter,
			color,
			material,
			{ collide = false, shape = "Cylinder" }
		)
		local turn = if alongY then CFrame.Angles(0, 0, math.pi / 2) else CFrame.new()
		p.CFrame = pivotCF * CFrame.new(offset[1], offset[2], offset[3]) * turn
		return p
	end
	local pivot = kit:at(
		mallet,
		"Pivot",
		0,
		0,
		0,
		0.05,
		0.05,
		0.05,
		C.handle,
		"SmoothPlastic",
		{ collide = false, transparency = 1, shadow = false }
	)
	pivot.CFrame = pivotCF
	piece("Handle", { 0, MA.handleLen / 2, 0 }, MA.handleLen, 2 * MA.handleR, true, C.handle, "Wood")
	piece("Collar", { 0, m(0.49), 0 }, m(0.065), m(0.066), true, C.brass, "Metal")
	piece("MalletHead", { 0, MA.headAt, 0 }, MA.headLen, 2 * MA.headR, false, C.rubber, "SmoothPlastic")
	for _, side in { -1, 1 } do
		piece("Face", { side * m(0.15), MA.headAt, 0 }, m(0.026), m(0.18), false, C.cream, "SmoothPlastic")
	end
	mallet.PrimaryPart = pivot
end

return Bake
