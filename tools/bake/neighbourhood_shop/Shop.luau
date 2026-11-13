--!strict
-- tools/bake/neighbourhood_shop/Shop: the shell of the owner's Neighbourhood Shop (brief addendum D12), baked as
-- parts around his own interior and roof, which are uploaded Models loaded at boot (Server/Assets/ShopArt,
-- generated/ShopArt). Everything here is in the venue's local frame (tools/bake/alley/Kit: X across the
-- frontage, Y up from the shop floor, D into the building; the front is at -D), 3 studs to his metre.
--   Shell      brick side and back walls and gable ends up to the underside of his roof's deck, teal corner
--              pilasters and a fascia band carrying the sign THE NEIGHBOURHOOD SHOP (its letters glow; three
--              gooseneck lamps over it), the transom over his open
--              door, the attic closed behind the fascia and the back, an opaque backing slab over his ceiling
--              (Realistic lighting leaks through thin shells), the concrete plinth, a paved forecourt to the
--              sidewalk and three steps up to the door.
--   Colliders  invisible: his metadata's floors, walls, dividers, partitions and the two counters; the office's
--              side wall (his mesh; his metadata leaves it out); plain boxes round the floor-standing furniture
--              (generated/ShopArt.FURNITURE); the shopfront either side of the doorway; his roof proxies.
--   Occluders  opaque boxes just inside his walls and lintels: the camera stops at them (it ignores invisible parts).
--   Lamps      a warm PointLight under each of his six pendant shades and the desk lamp, one over the door, and
--              a soft unshadowed fill under each room's ceiling.
--   TerrainCarve  the inside of the shell, carved to air at boot (the ground is 0.5 below the floor at the back).
-- The model carries Venue, ArtShop, ArtRoof (asset ids) and ArtPivot (the frame's CFrame) for the loader.
-- Interface: build(kit, parent, venue, art) -> Model; underside(art, d) -> y; topside(art, d) -> y; SIGN, WALL,
--   INNER_X, INNER_D, FRONT_D, PILASTER_D, FASCIA_D, CEILING_TOP, HEADER_TOP, SIDEWALK (dimensions)
-- No side effects on require. Lune only (@lune/roblox through the Kit).

local Kit = require("../alley/Kit")

local Shop = {}

Shop.WALL = 1.0 -- the shell's cladding, outside his 0.72-stud walls (Roblox: at least 1 stud against light leaks)
Shop.INNER_X = 21.72 -- his side walls' outer faces
Shop.INNER_D = 18.72 -- his back wall's outer face
Shop.FRONT_D = -18.27 -- his shopfront's outer face (the piers)
Shop.PILASTER_D = -19.0 -- the corner pilasters' front faces
Shop.FASCIA_D = -19.33 -- the fascia band's front face
Shop.CEILING_TOP = 13.02 -- the top of his ceiling slab (ROOF_Removable)
Shop.HEADER_TOP = 12.6 -- the top of his shopfront (the window headers)
Shop.SIDEWALK = -1.8 -- the forecourt's top: the sidewalk's (ground + 0.225) below the floor
Shop.SIGN = "THE NEIGHBOURHOOD SHOP"

local BRICK = { 132, 82, 66 }
local CONCRETE = { 156, 152, 144 }
local PAVING = { 172, 168, 160 }
local TEAL = { 93, 142, 137 } -- his TealPaint (the shopfront)
local DARK_WOOD = { 118, 87, 60 } -- his DarkWood (the window frames)
local CREAM = { 240, 228, 196 }
local LAMP = { 255, 206, 150 }
local IRON = { 47, 54, 54 } -- his BlackIron
local INVISIBLE = { collide = true, transparency = 1, shadow = false }

-- The underside of his roof deck above local depth d (the deck on that side of the ridge), studs above the floor.
function Shop.underside(art: any, d: number): number
	local deck = art.roof.decks[1]
	for _, k in art.roof.decks do
		if (k.centre[3] >= 0) == (d >= 0) then
			deck = k
		end
	end
	local c, up, t = deck.centre, deck.up, deck.size[2]
	return c[2] + (-t / 2 - (d - c[3]) * up[3]) / up[2]
end

-- The top of his roof deck (under the shingles) above local depth d.
function Shop.topside(art: any, d: number): number
	local deck = art.roof.decks[1]
	for _, k in art.roof.decks do
		if (k.centre[3] >= 0) == (d >= 0) then
			deck = k
		end
	end
	return Shop.underside(art, d) + deck.size[2] / deck.up[2]
end

-- An oriented box from generated/ShopArt (centre, size along right/up/back, all in X, Y, D) as a local CFrame
-- rotation (the Kit's frame is Roblox's at yaw 0: Z = -D).
local function rotOf(kit: Kit.Kit, b: any): any
	local V = kit.roblox.Vector3
	local function rv(v: { number }): any
		return V.new(v[1], v[2], -v[3])
	end
	return kit.roblox.CFrame.fromMatrix(V.new(0, 0, 0), rv(b.right), rv(b.up), rv(b.back))
end

function Shop.build(kit: Kit.Kit, parent: any, venue: any, art: any): any
	local roblox = kit.roblox
	local root = kit:model(parent, venue.id)
	root.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Atomic
	root.LevelOfDetail = roblox.Enum.ModelLevelOfDetail.SLIM
	root:SetAttribute("Venue", venue.id)
	root:SetAttribute("ArtShop", tostring(art.assets.shop.id))
	root:SetAttribute("ArtRoof", tostring(art.assets.roof.id))
	root:SetAttribute("ArtPivot", kit:cf(0, 0, 0))
	root:SetAttribute("Scale", art.scale)
	local start = kit.count

	local W, IX, ID = Shop.WALL, Shop.INNER_X, Shop.INNER_D
	local OX, OD = IX + W, ID + W
	local ground = venue.ground.min - venue.floorY -- the lowest ground under the footprint, below the floor
	local base = ground - 1.0
	local wallTop = Shop.underside(art, OD) - 0.02
	local apex = Shop.underside(art, 0) - 0.02
	local door = art.doorway

	-- shell
	local shell = kit:model(root, "Shell")
	kit:box(shell, "Plinth", -OX - 0.3, OX + 0.3, base, -0.72, Shop.PILASTER_D - 0.3, OD + 0.3, CONCRETE, "Concrete")
	for _, s in { -1, 1 } do
		local side = if s > 0 then "East" else "West"
		kit:box(shell, `{side}Wall`, s * IX, s * OX, -0.72, wallTop, Shop.FRONT_D, OD, BRICK, "Brick")
		for _, half in { -1, 1 } do
			kit:wedge(
				shell,
				`{side}Gable{if half > 0 then "Back" else "Front"}`,
				s * (IX + W / 2),
				wallTop + (apex - wallTop) / 2,
				half * OD / 2,
				W,
				apex - wallTop,
				OD,
				BRICK,
				"Brick",
				{ rot = if half > 0 then nil else roblox.CFrame.Angles(0, math.pi, 0) }
			)
		end
		kit:box(
			shell,
			`{side}Pilaster`,
			s * art.front.x1,
			s * OX,
			-0.72,
			Shop.HEADER_TOP,
			Shop.PILASTER_D,
			Shop.FRONT_D,
			TEAL,
			"SmoothPlastic"
		)
	end
	kit:box(shell, "BackWall", -IX, IX, -0.72, wallTop, ID, OD, BRICK, "Brick")
	kit:box(
		shell,
		"Fascia",
		-OX,
		OX,
		Shop.HEADER_TOP,
		Shop.underside(art, Shop.FASCIA_D) - 0.03,
		Shop.FASCIA_D,
		Shop.FRONT_D,
		TEAL,
		"SmoothPlastic"
	)
	kit:box(
		shell,
		"AtticFront",
		-IX,
		IX,
		Shop.CEILING_TOP,
		Shop.underside(art, -17.67) - 0.03,
		Shop.FRONT_D,
		-17.67,
		BRICK,
		"Brick"
	)
	kit:box(shell, "AtticBack", -IX, IX, Shop.CEILING_TOP, Shop.underside(art, 18.0) - 0.03, 18.0, ID, BRICK, "Brick")
	kit:box(
		shell,
		"CeilingBacking",
		-IX,
		IX,
		Shop.CEILING_TOP,
		Shop.CEILING_TOP + 1,
		-17.67,
		18.0,
		CONCRETE,
		"Concrete"
	)
	kit:box(shell, "Transom", door.x0, door.x1, door.top, Shop.HEADER_TOP, Shop.FRONT_D, -17.73, TEAL, "SmoothPlastic")
	kit:box(shell, "Threshold", door.x0, door.x1, -0.72, 0, -18.4, -17.6, DARK_WOOD, "Wood")

	-- the sign on the fascia
	local fasciaTop = Shop.underside(art, Shop.FASCIA_D) - 0.03
	local board = kit:box(
		shell,
		"SignBoard",
		-15.6,
		15.6,
		Shop.HEADER_TOP + 0.15,
		fasciaTop - 0.15,
		Shop.FASCIA_D - 0.2,
		Shop.FASCIA_D,
		DARK_WOOD,
		"Wood"
	)
	local gui = kit:gui(board, "Back", 40)
	kit:label(
		gui,
		{ Text = Shop.SIGN, TextColor = CREAM, Font = "Merriweather", Size = { 0.96, 0.8 }, Pos = { 0.02, 0.1 } }
	)
	-- three gooseneck lamps over the board (its letters glow on their own: LightInfluence 0); they light the
	-- teal fascia at night, from a stud and a half out in front of it
	local signY = (Shop.HEADER_TOP + fasciaTop) / 2
	for i, x in { -10, 0, 10 } do
		local head = kit:at(
			shell,
			"SignLamp",
			x,
			fasciaTop + 0.35,
			Shop.FASCIA_D - 1.5,
			0.5,
			0.35,
			0.5,
			IRON,
			"Metal",
			{ collide = false, shadow = false }
		)
		head.CFrame = roblox.CFrame.lookAt(
			kit:cf(x, fasciaTop + 0.35, Shop.FASCIA_D - 1.5).Position,
			kit:cf(x, signY, Shop.FASCIA_D).Position
		)
		kit:light(head, "SpotLight", {
			Name = `SignLight{i}`,
			Color = LAMP,
			Brightness = 2,
			Range = 6,
			Angle = 80,
			Face = "Front",
			Shadows = false,
		})
		kit:rod(
			shell,
			"SignLampArm",
			x,
			fasciaTop - 0.3,
			Shop.FASCIA_D,
			x,
			fasciaTop + 0.35,
			Shop.FASCIA_D - 1.4,
			0.12,
			IRON,
			"Metal"
		)
	end

	-- forecourt and steps: from the sidewalk up to his threshold
	local front = venue.site.d0
	kit:box(
		shell,
		"Forecourt",
		-OX - 0.3,
		OX + 0.3,
		base,
		Shop.SIDEWALK,
		front,
		Shop.PILASTER_D - 0.3,
		PAVING,
		"Concrete"
	)
	local sx0, sx1 = door.x0 - 0.9, door.x1 + 0.9
	kit:box(shell, "Landing", sx0, sx1, base, -0.05, -20.3, Shop.FRONT_D, CONCRETE, "Concrete")
	kit:box(shell, "Step1", sx0, sx1, base, -0.65, -21.3, -20.3, CONCRETE, "Concrete")
	kit:box(shell, "Step2", sx0, sx1, base, -1.25, -22.3, -21.3, CONCRETE, "Concrete")

	-- colliders
	local cols = kit:model(root, "Colliders")
	for _, c in art.colliders do
		kit:at(
			cols,
			c.name,
			c.centre[1],
			c.centre[2],
			c.centre[3],
			c.size[1],
			c.size[2],
			c.size[3],
			CONCRETE,
			"SmoothPlastic",
			INVISIBLE
		)
	end
	local fd0, fd1 = -18.33, -17.67
	kit:box(
		cols,
		"FrontWall",
		art.front.x0,
		door.x0,
		0,
		Shop.HEADER_TOP,
		fd0,
		fd1,
		CONCRETE,
		"SmoothPlastic",
		INVISIBLE
	)
	kit:box(
		cols,
		"FrontWall",
		door.x1,
		art.front.x1,
		0,
		Shop.HEADER_TOP,
		fd0,
		fd1,
		CONCRETE,
		"SmoothPlastic",
		INVISIBLE
	)
	for _, b in art.roof.colliders do
		kit:at(
			cols,
			b.name,
			b.centre[1],
			b.centre[2],
			b.centre[3],
			b.size[1],
			b.size[2],
			b.size[3],
			CONCRETE,
			"SmoothPlastic",
			{ collide = true, transparency = 1, shadow = false, rot = rotOf(kit, b) }
		)
	end

	-- the camera's occluders: opaque boxes just inside his walls and lintels (generated/ShopArt.occluders), which
	-- collide so that the default camera and CameraRig stop at them; hidden in his meshes, the walls if they fail
	local occ = kit:model(root, "Occluders")
	for _, c in art.occluders do
		kit:at(
			occ,
			c.name,
			c.centre[1],
			c.centre[2],
			c.centre[3],
			c.size[1],
			c.size[2],
			c.size[3],
			c.colour,
			"SmoothPlastic",
			{ collide = true, shadow = false }
		)
	end

	-- lamps
	local lamps = kit:model(root, "Lamps")
	local hidden = { collide = false, query = false, transparency = 1, shadow = false }
	for i, l in art.lamps do
		local desk = l.kind == "desk"
		local p =
			kit:at(lamps, `Lamp{i}`, l.at[1], l.at[2] - 0.35, l.at[3], 0.3, 0.3, 0.3, LAMP, "SmoothPlastic", hidden)
		-- his three big retail shades cast shadows; the three small ones and the desk lamp do not (the engine
		-- pays for every shadowed light in view)
		local big = (l.size and l.size[1] or 0) > 1.2
		kit:light(p, "PointLight", {
			Color = LAMP,
			Brightness = if desk then 0.8 else 1.3,
			Range = if desk then 9 else 20,
			Shadows = big and not desk,
		})
	end
	-- a soft fill under each room's ceiling: the pendants light downward from inside their shades, and the
	-- engine's lighting has no bounce, so without it the ceiling, beams and upper walls stay dark at night
	for _, c in art.colliders do
		local room = string.match(c.name, "^(%a+)Floor$")
		if room then
			local f = kit:at(
				lamps,
				`{room}Fill`,
				c.centre[1],
				Shop.HEADER_TOP - 2.1,
				c.centre[3],
				0.3,
				0.3,
				0.3,
				LAMP,
				"SmoothPlastic",
				hidden
			)
			kit:light(f, "PointLight", {
				Color = LAMP,
				Brightness = 0.45,
				Range = math.min(30, math.max(c.size[1], c.size[3]) * 0.8),
				Shadows = false,
			})
		end
	end
	local porch = kit:at(
		lamps,
		"PorchLamp",
		(door.x0 + door.x1) / 2,
		Shop.HEADER_TOP - 0.4,
		Shop.FASCIA_D - 0.6,
		0.3,
		0.3,
		0.3,
		LAMP,
		"SmoothPlastic",
		hidden
	)
	kit:light(porch, "PointLight", { Color = LAMP, Brightness = 1, Range = 16, Shadows = false })

	-- the inside of the shell, carved to air at boot (Server/Assets/ShopArt)
	local carve = kit:folder(root, "TerrainCarve")
	kit:box(carve, "Inside", -IX, IX, -0.75, Shop.CEILING_TOP, -18.2, ID, { 255, 0, 0 }, "SmoothPlastic", hidden)

	root:SetAttribute("Parts", kit.count - start)
	return root
end

return Shop
