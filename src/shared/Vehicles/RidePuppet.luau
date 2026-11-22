--!strict
-- ReplicatedStorage.Shared.Vehicles.RidePuppet
-- The bikes and novelty rides drawn from shaped parts, in the cars' style (Traffic/VehiclePuppet: plain parts,
-- cylinders and balls, no meshes), and the people who ride them (owner playtest 2026-11-19: "i saw bikes and
-- things that were basic colors, like earlier builds").
--   rider(slot, index?)  the town's eight street riders (AI/TownAI: data/population.json nonHumanoid, 6 novelty
--                        riders and 2 motorcyclists): slot 1 Marcel the Mime on his tall unicycle, juggling; slots
--                        2-6 the five kids on bicycles in helmets (v5.4 cast: body x0.76, bicycle x0.82, the cast's
--                        frame and helmet colours, a basket on two of them); slots 7-8 the two motorcyclists on
--                        motor scooters in their jackets and open helmets. A slot past 8 starts the list again,
--                        recoloured from the townsperson palette by `index`.
--   bicycle(opts)        a parked bicycle alone (the player's bike in Server/Actors/DeviceService, a kid's bike in a
--                        yard): drawn into a kit standing on `ground`, `scale` x the adult bike.
--   sharedRide(kind)     the town's shared moped (the riders' motor scooter) and stand-up electric scooter (owner D29).
-- The riders are part-built and stay so: they have no Humanoid and no R15 joints (Actors/BodyFactory), so the rounded
-- townspeople's art (Assets/PeopleArt) cannot be put on them. They are dressed instead in what that art would give them:
-- Avatar/PeopleLooks' colours, hair style and hat for the role (mime or townsperson), and the same round build (a ball
-- head with eyes, a rounded body, round hands), seated in a riding pose a walking R15 clip could not give. The cast
-- riders wear the cast's own shirts; where a shirt reads as skin (Avatar/RolePalettes.readsAsSkin: Ellie's orange,
-- Riley's khaki, Morgan's brown-grey jacket) the shoulders under the chin are a darker shade of it, so the head does
-- not run into the body.
-- A rider faces -Z (RigSpec). Its root is the old rider's: an invisible 1 x 1 x 1 HumanoidRootPart 2.2 studs above the
-- ground, the only part that can be queried or touched; every other part is welded to it and collides with nothing.
-- Only the big parts (the body, the head, the tyres) cast shadows.
-- Interface: rider(slot, index?) -> PartBuilder.ModelSpec; RIDERS; ROOT_HEIGHT; drawBicycle(kit, opts) -> Anchors;
--   drawRider(kit, slot, seat, hands, feet, lean, prefix) -> parts drawn;
--   newKit(ground) -> Kit; bicycle(opts?) -> PartBuilder.ModelSpec (root = the bike's own box, for a parked bike);
--   sharedRide(kind, opts) -> PartBuilder.ModelSpec (a shared moped or electric scooter, owner D29); BOARD_TOP
-- Pure. No side effects on require.

local PartBuilder = require("../Avatar/PartBuilder")
local PeopleLooks = require("../Avatar/PeopleLooks")
local RolePalettes = require("../Avatar/RolePalettes")

export type Rgb = PartBuilder.Rgb
type Part = PartBuilder.PartSpec
export type V = { number } -- x, y, z (studs; y above the ground)

-- A ride being drawn: its parts so far and the root's height above the ground (every helper below takes heights
-- ABOVE THE GROUND and turns them into the root's frame).
export type Kit = { parts: { Part }, ground: number }

-- Where a rider meets the ride: the top of the saddle (or seat), the hand holds and the two feet.
export type Anchors = { seat: V, hands: { V }, feet: { V } }

export type Rider = {
	name: string,
	ride: "unicycle" | "bicycle" | "scooter",
	role: string, -- PeopleLooks role (the colours, hair and hat it gives)
	body: number, -- body scale (a kid is 0.76)
	bike: number, -- ride scale
	skin: string,
	shirt: string,
	frame: string, -- the ride's paint
	helmet: string?, -- a helmet in this colour (none: the role's hat, or hair)
	hair: string?, -- a PeopleAssets hair style in place of the role's pick
	basket: boolean?,
	src: string,
}

local hex = PartBuilder.hex

local RidePuppet = {}

RidePuppet.ROOT_HEIGHT = 2.2 -- the root above the ground (the old part-built rider's)
RidePuppet.YOKE = 0.7 -- the shoulders' shade of a shirt that reads as skin

local function shade(c: Rgb, f: number): Rgb
	return { r = c.r * f, g = c.g * f, b = c.b * f }
end

-- The cast (data/authored/cast/cast.json, v5.4 L12199-12249 and L9563): skin, shirt or jacket, the ride's paint and
-- the helmet. Pants and hair come from PeopleLooks (the townsperson palette), as for anyone else in town.
-- stylua: ignore
RidePuppet.RIDERS = table.freeze({
	{ name = "Marcel the Mime", ride = "unicycle", role = "mime", body = 1, bike = 1, skin = "#dbc3a8", shirt = "#ededeb", frame = "#a92831", src = "marcel_the_mime" },
	{ name = "Ellie", ride = "bicycle", role = "townsperson", body = 0.76, bike = 0.82, skin = "#e6b995", shirt = "#e69a54", frame = "#405979", helmet = "#ef9e58", hair = "Hair_bun", basket = true, src = "ellie" },
	{ name = "Theo", ride = "bicycle", role = "townsperson", body = 0.76, bike = 0.82, skin = "#b78364", shirt = "#70b6dd", frame = "#b65e53", helmet = "#64a2cf", src = "theo" },
	{ name = "Jules", ride = "bicycle", role = "townsperson", body = 0.76, bike = 0.82, skin = "#a5785c", shirt = "#d79cc2", frame = "#59826d", helmet = "#ce719f", src = "jules" },
	{ name = "Avery", ride = "bicycle", role = "townsperson", body = 0.76, bike = 0.82, skin = "#e6b995", shirt = "#66b495", frame = "#a58b4d", helmet = "#68aa8d", basket = true, src = "avery_l12249" },
	{ name = "Riley", ride = "bicycle", role = "townsperson", body = 0.76, bike = 0.82, skin = "#b78364", shirt = "#b5a06e", frame = "#405979", helmet = "#b98b55", hair = "Hair_bun", src = "riley" },
	{ name = "Morgan Rider", ride = "scooter", role = "townsperson", body = 1, bike = 1, skin = "#c99a77", shirt = "#5f554c", frame = "#9f3632", helmet = "#e9e4d8", src = "morgan_rider" },
	{ name = "Alex Rider", ride = "scooter", role = "townsperson", body = 1, bike = 1, skin = "#ba896c", shirt = "#3b5b6d", frame = "#324f68", helmet = "#e9e4d8", src = "alex_rider" },
} :: { Rider })

-- Colours the cast does not choose.
local FIXED = {
	tyre = "#1d1e20",
	rimDisc = "#4f5358", -- the wheel's inside: the dark between the spokes
	spoke = "#c9cdd1",
	chrome = "#c4c9cc",
	bar = "#2a2d31",
	saddle = "#2a2624",
	shoe = "#2f3431",
	eye = "#1d1a1a",
	basket = "#b38b58",
	glove = "#f1f1ec", -- the mime's (PeopleAssets mime: hands #f1f1ec)
	paint = "#f1efe8", -- the mime's painted face
	beret = "#202020", -- PeopleAssets Hat_beret
	stripe = "#24252b",
	scarf = "#a92831",
	head = "#fff3b5",
	tail = "#c53227",
	visor = "#26282c",
	juggle = { "#f44336", "#e8d761", "#55a9dc", "#7ebf80" }, -- the cast's four balls
}

function RidePuppet.newKit(ground: number): Kit
	return { parts = {}, ground = ground }
end

local function put(k: Kit, p: Part): Part
	table.insert(k.parts, p)
	return p
end

local function at(k: Kit, p: V): { number }
	return { p[1], p[2] + k.ground, p[3] }
end

local function add3(a: V, b: V): V
	return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end

local function scale3(a: V, s: number): V
	return { a[1] * s, a[2] * s, a[3] * s }
end

-- a cylinder from a to b (heights above the ground) of radius r: local X is turned onto b - a (roll a quarter turn
-- takes X to Y, pitch leans Y toward +Z, yaw swings that round Y; PartBuilder applies yaw * pitch * roll)
local function seg(k: Kit, name: string, a: V, b: V, r: number, c: Rgb, material: string?): Part
	local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	local h = math.sqrt(dx * dx + dz * dz)
	return put(k, {
		name = name,
		size = { len, r * 2, r * 2 },
		pos = at(k, { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2 }),
		roll = math.pi / 2,
		pitch = math.atan2(h, dy),
		yaw = math.atan2(dx, dz),
		color = c,
		shape = "Cylinder",
		material = material,
	})
end

-- a cylinder across the ride (axis X), `w` wide, of radius r, centred at p
local function across(k: Kit, name: string, p: V, w: number, r: number, c: Rgb, material: string?): Part
	return put(
		k,
		{ name = name, size = { w, r * 2, r * 2 }, pos = at(k, p), color = c, shape = "Cylinder", material = material }
	)
end

local function ball(k: Kit, name: string, p: V, d: number, c: Rgb): Part
	return put(k, { name = name, size = { d, d, d }, pos = at(k, p), color = c, shape = "Ball" })
end

local function block(k: Kit, name: string, p: V, size: V, c: Rgb, material: string?): Part
	return put(k, { name = name, size = { size[1], size[2], size[3] }, pos = at(k, p), color = c, material = material })
end

-- A spoked wheel on axle `p` (axis X): the tyre, a dark disc inside it, `pairs` bright bars through the hub (two
-- spokes each, wider than the tyre so they show on both faces) and the hub. The tyre carries `name` (the joint name).
local function wheel(k: Kit, name: string, p: V, r: number, w: number, pairs: number)
	local tyre = across(k, name, p, w, r, hex(FIXED.tyre))
	tyre.castShadow = true
	across(k, `{name}Rim`, p, w + 0.03, r - 0.13 * math.max(r, 0.6), hex(FIXED.rimDisc))
	for i = 1, pairs do
		put(k, {
			name = `{name}Spokes{i}`,
			size = { w + 0.07, 0.05, (r - 0.12) * 2 },
			pos = at(k, p),
			pitch = (i - 0.5) * math.pi / pairs,
			color = hex(FIXED.spoke),
			material = "Metal",
		})
	end
	across(k, `{name}Hub`, p, w + 0.12, math.max(0.08, r * 0.12), hex(FIXED.chrome), "Metal")
end

-- The bicycle at `scale` (1 = an adult's: 0.92-stud wheels 3.1 studs apart), the front wheel toward -Z, drawn from
-- 21 parts (22 with a basket): two spoked wheels, the diamond frame in the paint colour (seat, top, down tube, chain
-- and seat stays), the chrome fork, the stem and bar, a saddle, the chainring and the cranks.
-- spokes: bars of spokes per wheel (2 by default; a parked bike in a yard draws 1)
type BikeOpts = { scale: number?, frame: string?, basket: boolean?, spokes: number? }
function RidePuppet.drawBicycle(k: Kit, opts: BikeOpts?): Anchors
	local o: BikeOpts = opts or {}
	local s = o.scale or 1
	local paint = hex(o.frame or "#405979")
	local chrome = hex(FIXED.chrome)
	local R = 0.92 * s
	local rear: V, front: V = { 0, R, 1.55 * s }, { 0, R, -1.55 * s }
	local bb: V = { 0, 0.78 * s, 0.15 * s }
	local seatTop: V = { 0, 2.18 * s, 0.6 * s }
	local headTop: V, headFoot: V = { 0, 2.05 * s, -1.0 * s }, { 0, 1.55 * s, -1.15 * s }
	local barAt: V = { 0, 2.42 * s, -1.02 * s }
	wheel(k, "WheelF", front, R, 0.16 * s, o.spokes or 2)
	wheel(k, "WheelB", rear, R, 0.16 * s, o.spokes or 2)
	local tube = 0.075 * s
	seg(k, "SeatTube", bb, seatTop, tube, paint)
	seg(k, "TopTube", { 0, 1.95 * s, 0.53 * s }, headTop, tube, paint)
	seg(k, "DownTube", bb, headFoot, tube * 1.15, paint)
	seg(k, "ChainStay", bb, rear, tube * 0.8, paint)
	seg(k, "SeatStay", { 0, 1.92 * s, 0.53 * s }, rear, tube * 0.8, paint)
	seg(k, "Fork", headFoot, front, tube * 0.9, chrome, "Metal")
	seg(k, "Stem", headFoot, barAt, tube * 1.1, paint)
	across(k, "Bars", barAt, 1.3 * s, 0.06 * s, hex(FIXED.bar))
	block(
		k,
		"Saddle",
		{ 0, seatTop[2] + 0.07 * s, seatTop[3] + 0.05 * s },
		{ 0.42 * s, 0.16 * s, 0.8 * s },
		hex(FIXED.saddle)
	)
	across(k, "Chainring", bb, 0.1 * s, 0.32 * s, chrome, "Metal")
	-- the cranks: one bar through the bottom bracket, its ends the two pedals (left up and forward, right down and back)
	local crankUp: V, crankDown: V =
		{ -0.45 * s, bb[2] + 0.3 * s, bb[3] - 0.18 * s }, { 0.45 * s, bb[2] - 0.3 * s, bb[3] + 0.18 * s }
	seg(k, "Cranks", crankUp, crankDown, 0.05 * s, hex(FIXED.bar), "Metal")
	if o.basket then
		block(k, "Basket", { 0, 2.28 * s, -1.5 * s }, { 0.8 * s, 0.5 * s, 0.62 * s }, hex(FIXED.basket), "Wood")
	end
	return {
		seat = { 0, seatTop[2] + 0.15 * s, seatTop[3] + 0.05 * s },
		hands = { { -0.55 * s, barAt[2], barAt[3] }, { 0.55 * s, barAt[2], barAt[3] } },
		feet = { crankUp, crankDown },
	}
end

-- The mime's tall unicycle: one big spoked wheel (eight spokes), a chrome fork and post, the saddle, the cranks.
local function drawUnicycle(k: Kit, frame: Rgb): Anchors
	local R = 1.05
	local axle: V = { 0, R, 0 }
	local chrome = hex(FIXED.chrome)
	wheel(k, "WheelF", axle, R, 0.18, 4)
	local crown = 2 * R + 0.3
	for _, sx in { -1, 1 } do
		seg(k, if sx < 0 then "ForkL" else "ForkR", { sx * 0.2, R, 0 }, { sx * 0.17, crown, 0 }, 0.05, chrome, "Metal")
	end
	block(k, "Crown", { 0, crown, 0 }, { 0.5, 0.14, 0.22 }, frame)
	local seatY = 3.2
	seg(k, "Post", { 0, crown, 0 }, { 0, seatY - 0.08, 0 }, 0.07, frame)
	block(k, "Saddle", { 0, seatY, 0.02 }, { 0.42, 0.16, 0.76 }, hex(FIXED.saddle))
	local up: V, down: V = { -0.5, R + 0.32, -0.16 }, { 0.5, R - 0.32, 0.16 }
	seg(k, "Cranks", up, down, 0.05, hex(FIXED.bar), "Metal")
	return { seat = { 0, seatY + 0.08, 0.02 }, hands = {}, feet = { up, down } }
end

-- A motor scooter: two small wheels, a rounded rear cowl in the paint, a floorboard, a leg shield, the column and
-- bar with its headlamp, a mudguard, the seat and a tail light (15 parts).
local function drawScooter(k: Kit, paint: Rgb): Anchors
	local R = 0.52
	local chrome, dark = hex(FIXED.chrome), hex("#3a3d42")
	local rear: V, front: V = { 0, R, 1.25 }, { 0, R, -1.4 }
	across(k, "WheelF", front, 0.3, R, hex(FIXED.tyre)).castShadow = true
	across(k, "WheelB", rear, 0.34, R, hex(FIXED.tyre)).castShadow = true
	across(k, "HubF", front, 0.36, R * 0.55, chrome, "Metal")
	across(k, "HubB", rear, 0.4, R * 0.55, chrome, "Metal")
	block(k, "Floor", { 0, 0.55, -0.2 }, { 0.74, 0.16, 1.2 }, dark)
	block(k, "Cowl", { 0, 0.98, 0.95 }, { 0.9, 0.8, 1.2 }, paint).castShadow = true
	put(k, {
		name = "CowlTop",
		size = { 1.2, 0.9, 0.9 },
		pos = at(k, { 0, 1.38, 0.95 }),
		yaw = math.pi / 2,
		color = paint,
		shape = "Cylinder",
	})
	block(k, "Seat", { 0, 1.86, 0.85 }, { 0.62, 0.2, 1.0 }, hex(FIXED.saddle))
	block(k, "Shield", { 0, 1.15, -0.86 }, { 0.86, 1.25, 0.16 }, paint)
	seg(k, "Column", { 0, 1.6, -0.9 }, { 0, 2.38, -1.02 }, 0.1, paint)
	across(k, "Bars", { 0, 2.42, -1.02 }, 1.2, 0.07, chrome, "Metal")
	put(k, {
		name = "Headlamp",
		size = { 0.12, 0.34, 0.34 },
		pos = at(k, { 0, 2.28, -1.14 }),
		yaw = math.pi / 2,
		color = hex(FIXED.head),
		shape = "Cylinder",
		material = "Neon",
	})
	block(k, "Mudguard", { 0, 1.02, -1.4 }, { 0.36, 0.14, 0.8 }, paint)
	seg(k, "Fork", front, { 0, 1.55, -1.0 }, 0.07, chrome, "Metal")
	block(k, "TailLight", { 0, 1.32, 1.57 }, { 0.34, 0.14, 0.06 }, hex(FIXED.tail), "Neon")
	return {
		seat = { 0, 1.96, 0.75 },
		hands = { { -0.55, 2.42, -1.02 }, { 0.55, 2.42, -1.02 } },
		feet = { { -0.24, 0.66, -0.45 }, { 0.24, 0.66, -0.3 } },
	}
end

-- Where the knee goes: thigh and shin `len` long from the hip joint to the foot, bent forward (-Z) and up.
local function knee(hip: V, foot: V, len: number): V
	local d: V = { foot[1] - hip[1], foot[2] - hip[2], foot[3] - hip[3] }
	local dist = math.sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3])
	local reach = math.min(dist, 2 * len - 1e-3)
	local half = reach / 2
	local h = math.sqrt(math.max(0, len * len - half * half))
	local u = scale3(d, 1 / math.max(dist, 1e-6))
	local ny, nz = -u[3], u[2] -- the perpendicular in the Y-Z plane that points forward for a leg hanging down
	local nl = math.sqrt(ny * ny + nz * nz)
	if nl < 1e-6 then
		ny, nz, nl = 0, -1, 1
	end
	return { hip[1] + u[1] * half, hip[2] + u[2] * half + ny / nl * h, hip[3] + u[3] * half + nz / nl * h }
end

type Pose = {
	seat: V, -- top of the saddle
	lean: number, -- the body's lean forward (radians)
	hands: { V }, -- left, right (empty: hands up, juggling)
	feet: { V },
}

-- The rounded rider: a round pelvis and body, round shoulders, a big round head with two eyes, the hair or a helmet
-- or the role's hat, straight arms to the bar with round hands, bent legs to the pedals and shoes. 18 to 22 parts.
local function drawFigure(k: Kit, dress: PeopleLooks.Dress, r: Rider, pose: Pose)
	local s = r.body
	local c = dress.colours
	local mime = r.role == "mime"
	local skin = if mime then hex(FIXED.paint) else c.skin
	local hip: V = { pose.seat[1], pose.seat[2] + 0.3 * s, pose.seat[3] }
	local up: V = { 0, math.cos(pose.lean), -math.sin(pose.lean) }
	across(k, "Pelvis", hip, 1.0 * s, 0.36 * s, c.pants)
	local shoulder = add3(hip, scale3(up, 1.25 * s))
	seg(k, "Torso", add3(hip, scale3(up, 0.1 * s)), add3(hip, scale3(up, 1.2 * s)), 0.5 * s, c.shirt).castShadow = true
	-- the shoulders meet the head: a shirt that reads as skin is darker there (RidePuppet.YOKE of it)
	local yoke = if not mime and RolePalettes.readsAsSkin(c.shirt, skin)
		then shade(c.shirt, RidePuppet.YOKE)
		else c.shirt
	across(k, "Shoulders", shoulder, 1.25 * s, 0.33 * s, yoke)
	if mime then
		-- the striped top: two dark bands round the body, and the red scarf at the neck
		for i, t in { 0.45, 0.8 } do
			seg(
				k,
				`Stripe{i}`,
				add3(hip, scale3(up, t * s)),
				add3(hip, scale3(up, (t + 0.13) * s)),
				0.52 * s,
				hex(FIXED.stripe)
			)
		end
		seg(
			k,
			"Scarf",
			add3(shoulder, scale3(up, 0.18 * s)),
			add3(shoulder, scale3(up, 0.38 * s)),
			0.36 * s,
			hex(FIXED.scarf)
		)
	end
	local head = add3(shoulder, add3(scale3(up, 0.2 * s), { 0, 0.62 * s, 0 }))
	ball(k, "Head", head, 1.3 * s, skin).castShadow = true
	for _, sx in { -1, 1 } do
		ball(
			k,
			if sx < 0 then "EyeL" else "EyeR",
			add3(head, { sx * 0.22 * s, 0.08 * s, -0.6 * s }),
			0.15 * s,
			hex(FIXED.eye)
		)
	end
	-- hair: a ball a little bigger than the head, set up and back so the face shows; long styles hang lower
	local style = r.hair or dress.hair or "Hair_short"
	local long = style == "Hair_bob" or style == "Hair_long" or style == "Hair_curly"
	local hairAt = add3(head, if long then { 0, 0.04 * s, 0.14 * s } else { 0, 0.12 * s, 0.11 * s })
	ball(k, "Hair", hairAt, (if long then 1.42 else 1.36) * s, c.hair)
	if r.helmet then
		ball(k, "Helmet", add3(head, { 0, 0.36 * s, 0.12 * s }), 1.44 * s, hex(r.helmet))
		block(k, "Visor", add3(head, { 0, 0.5 * s, -0.66 * s }), { 1.0 * s, 0.08 * s, 0.36 * s }, hex(FIXED.visor))
	elseif dress.hat == "Hat_beret" then
		put(k, {
			name = "Beret",
			size = { 0.3 * s, 1.22 * s, 1.22 * s },
			pos = at(k, add3(head, { 0.16 * s, 0.6 * s, 0.1 * s })),
			roll = math.pi / 2,
			pitch = 0.32,
			yaw = math.pi / 2,
			color = hex(FIXED.beret),
			shape = "Cylinder",
		})
	elseif style == "Hair_bun" then
		ball(k, "Bun", add3(head, { 0, 0.62 * s, 0.42 * s }), 0.5 * s, c.hair)
	elseif style == "Hair_ponytail" then
		seg(
			k,
			"Ponytail",
			add3(head, { 0, 0.3 * s, 0.68 * s }),
			add3(head, { 0, -0.35 * s, 0.82 * s }),
			0.17 * s,
			c.hair
		)
	end
	-- arms to the hand holds (the juggler's up and forward), round hands
	local hands = pose.hands
	if #hands == 0 then
		hands = {
			add3(shoulder, { -0.55 * s, 0.35 * s, -1.0 * s }),
			add3(shoulder, { 0.55 * s, 0.35 * s, -1.0 * s }),
		}
	end
	local handColour = if mime then hex(FIXED.glove) else c.skin
	for i, sx in { -1, 1 } do
		local side = if sx < 0 then "L" else "R"
		local from = add3(shoulder, { sx * 0.6 * s, -0.05 * s, 0 })
		seg(k, `Arm{side}`, from, hands[i], 0.19 * s, c.shirt)
		ball(k, `Hand{side}`, hands[i], 0.38 * s, handColour)
	end
	-- legs bent to the pedals (thigh and shin 1.0 x body scale), shoes on the pedals
	local len = 1.0 * s
	for i, sx in { -1, 1 } do
		local side = if sx < 0 then "L" else "R"
		local hipJoint = add3(hip, { sx * 0.28 * s, -0.04 * s, 0 })
		local foot = pose.feet[i]
		local ankle = add3(foot, { 0, 0.14 * s, 0.04 * s })
		local kn = knee(hipJoint, ankle, len)
		seg(k, `Thigh{side}`, hipJoint, kn, 0.25 * s, c.pants)
		seg(k, `Shin{side}`, kn, ankle, 0.21 * s, c.pants)
		block(k, `Shoe{side}`, add3(foot, { 0, 0.05 * s, -0.1 * s }), { 0.36 * s, 0.26 * s, 0.66 * s }, hex(FIXED.shoe))
	end
	if mime then
		-- the four juggling balls on their arcs above the hands
		local arc: { V } =
			{ { -0.62, 0.9, -1.05 }, { -0.22, 1.55, -1.15 }, { 0.24, 1.35, -1.15 }, { 0.62, 0.7, -1.05 } }
		for i, p in arc do
			ball(k, `Ball{i}`, add3(shoulder, scale3(p, s)), 0.34 * s, hex(FIXED.juggle[i]))
		end
	end
end

-- Every part's shadow is off unless a drawing helper switched it on (castShadow = true above).
local function shadows(parts: { Part })
	for _, p in parts do
		if p.castShadow == nil then
			p.castShadow = false
		end
	end
end

-- The joints: a tyre turns on a Motor6D named after it (WheelF, WheelB: the old rider's), the rest is welded.
local function joints(parts: { Part }, root: string): { PartBuilder.JointSpec }
	local out: { PartBuilder.JointSpec } = {}
	for i = 2, #parts do
		local name: string = parts[i].name
		local motor = name == "WheelF" or name == "WheelB"
		table.insert(out, {
			name = if motor then name else `{name}Weld`,
			kind = if motor then "Motor6D" else "Weld",
			part0 = root,
			part1 = name,
		})
	end
	return out
end

-- The rider in town slot `slot` (1-8; past 8 the list starts again, recoloured from the palette by `index`).
-- Who rides in slot `slot` and what they wear (a slot past 8 recoloured from the palette by `index`).
local function dressFor(slot: number, index: number?): (Rider, PeopleLooks.Dress, number)
	local n = #RidePuppet.RIDERS
	local i = math.max(1, math.floor(slot))
	local r = RidePuppet.RIDERS[(i - 1) % n + 1]
	local lap = (i - 1) // n
	local skin, shirt = hex(r.skin), hex(r.shirt)
	local who = index or i
	if lap > 0 then
		-- a stranger past the cast: the palette's colours, never a shirt that reads as bare skin
		local look = RolePalettes.look("townsperson", who)
		skin, shirt = look.skin, RolePalettes.clothed(look.shirt, look.skin, who)
	end
	return r, PeopleLooks.dress(r.role, who, { skin = skin, shirt = shirt }), who
end

-- drawRider(kit, slot, seat, hands, feet, lean, prefix): slot's rider alone, seated on someone else's ride (a traffic
-- motorcycle: Traffic/VehiclePuppet), each part's name after `prefix`. Returns how many parts it drew.
function RidePuppet.drawRider(
	k: Kit,
	slot: number,
	seat: V,
	hands: { V },
	feet: { V },
	lean: number,
	prefix: string
): number
	local r, dress = dressFor(slot)
	local first = #k.parts + 1
	drawFigure(k, dress, r, { seat = seat, lean = lean, hands = hands, feet = feet })
	local drawnParts = {}
	for i = first, #k.parts do
		k.parts[i].name = prefix .. k.parts[i].name
		table.insert(drawnParts, k.parts[i])
	end
	shadows(drawnParts)
	return #k.parts - first + 1
end

function RidePuppet.rider(slot: number, index: number?): PartBuilder.ModelSpec
	local r, dress, who = dressFor(slot, index)
	local k = RidePuppet.newKit(-RidePuppet.ROOT_HEIGHT)
	put(k, {
		name = "HumanoidRootPart",
		size = { 1, 1, 1 },
		pos = { 0, 0, 0 },
		color = dress.colours.shirt,
		transparency = 1,
	})
	local paint = hex(r.frame)
	local anchors: Anchors
	local lean: number
	if r.ride == "unicycle" then
		anchors, lean = drawUnicycle(k, paint), 0.04
	elseif r.ride == "scooter" then
		anchors, lean = drawScooter(k, paint), 0.12
	else
		anchors, lean = RidePuppet.drawBicycle(k, { scale = r.bike, frame = r.frame, basket = r.basket }), 0.36
	end
	drawFigure(k, dress, r, { seat = anchors.seat, lean = lean, hands = anchors.hands, feet = anchors.feet })
	shadows(k.parts)
	return {
		name = `Rider_{who}`,
		species = "human",
		primary = "HumanoidRootPart",
		parts = k.parts,
		joints = joints(k.parts, "HumanoidRootPart"),
		attachments = {},
		attributes = { RideKind = r.ride, RiderName = r.name },
	}
end

-- A parked bicycle on its own: the root is the bike's box (`size`, centred), drawn standing on the box's floor.
export type BicycleOpts = { scale: number?, frame: string?, basket: boolean?, size: V?, name: string? }
function RidePuppet.bicycle(opts: BicycleOpts?): PartBuilder.ModelSpec
	local o: BicycleOpts = opts or {}
	local s = o.scale or 1
	local size: V = o.size or { 1.3 * s, 2.5 * s, 4.98 * s }
	local k = RidePuppet.newKit(-size[2] / 2)
	put(k, {
		name = "RootPart",
		size = { size[1], size[2], size[3] },
		pos = { 0, 0, 0 },
		color = hex(o.frame or "#405979"),
		transparency = 1,
	})
	RidePuppet.drawBicycle(k, { scale = s, frame = o.frame, basket = o.basket })
	shadows(k.parts)
	k.parts[1].castShadow = nil
	return {
		name = o.name or "Bicycle",
		species = "car",
		primary = "RootPart",
		parts = k.parts,
		joints = joints(k.parts, "RootPart"),
		attachments = {},
		attributes = { RideKind = "bicycle" },
	}
end

-- A stand-up electric scooter (owner D29), the front toward -Z, 12 parts: two small solid wheels with hubs, a low
-- board (the dark grip top `Board` the rider stands on, over a trim in the paint), a rear mudguard, the chrome fork,
-- the tall stem in the paint, a T bar, a headlamp and a tail light. The board's top is BOARD_TOP over the ground.
RidePuppet.BOARD_TOP = 0.5
local function drawEScooter(k: Kit, paint: Rgb): Anchors
	local R = 0.36
	local chrome, dark = hex(FIXED.chrome), hex("#2f3236")
	local rear: V, front: V = { 0, R, 1.2 }, { 0, R, -1.25 }
	across(k, "WheelF", front, 0.22, R, hex(FIXED.tyre)).castShadow = true
	across(k, "WheelB", rear, 0.24, R, hex(FIXED.tyre)).castShadow = true
	across(k, "HubF", front, 0.27, R * 0.5, chrome, "Metal")
	across(k, "HubB", rear, 0.29, R * 0.5, chrome, "Metal")
	local top = RidePuppet.BOARD_TOP
	block(k, "Board", { 0, top - 0.06, -0.02 }, { 0.6, 0.12, 2.1 }, dark)
	block(k, "Trim", { 0, top - 0.17, -0.02 }, { 0.66, 0.12, 2.2 }, paint)
	block(k, "Mudguard", { 0, 2 * R + 0.05, 1.25 }, { 0.28, 0.06, 0.72 }, paint)
	local head: V = { 0, 0.62, -1.18 }
	seg(k, "Fork", front, head, 0.05, chrome, "Metal")
	local barAt: V = { 0, 3.0, -1.02 }
	seg(k, "Stem", head, { 0, barAt[2] - 0.05, barAt[3] }, 0.07, paint)
	across(k, "Bars", barAt, 1.05, 0.05, hex(FIXED.bar))
	put(k, {
		name = "Headlamp",
		size = { 0.1, 0.22, 0.22 },
		pos = at(k, { 0, 2.55, -1.12 }),
		yaw = math.pi / 2,
		color = hex(FIXED.head),
		shape = "Cylinder",
		material = "Neon",
	})
	block(k, "TailLight", { 0, 2 * R + 0.1, 1.6 }, { 0.22, 0.08, 0.05 }, hex(FIXED.tail), "Neon")
	return {
		seat = { 0, top, 0 },
		hands = { { -0.45, barAt[2], barAt[3] }, { 0.45, barAt[2], barAt[3] } },
		feet = { { -0.15, top, 0.1 }, { 0.15, top, -0.2 } },
	}
end

-- A parked ride of the town's shared ones (owner D29): the root is the ride's own box (`size`, centred), the ride drawn
-- standing on the box's floor: "moped" a small motor scooter (the street riders' scooter: 15 parts), "escooter" the
-- stand-up electric scooter (12 parts). `paint` its colour.
export type SharedRideOpts = { paint: string?, size: V, name: string? }
function RidePuppet.sharedRide(kind: "moped" | "escooter", opts: SharedRideOpts): PartBuilder.ModelSpec
	local size = opts.size
	local paint = hex(opts.paint or "#405979")
	local k = RidePuppet.newKit(-size[2] / 2)
	put(k, {
		name = "RootPart",
		size = { size[1], size[2], size[3] },
		pos = { 0, 0, 0 },
		color = paint,
		transparency = 1,
	})
	if kind == "moped" then
		drawScooter(k, paint)
	else
		drawEScooter(k, paint)
	end
	shadows(k.parts)
	k.parts[1].castShadow = nil
	return {
		name = opts.name or kind,
		species = "car",
		primary = "RootPart",
		parts = k.parts,
		joints = joints(k.parts, "RootPart"),
		attachments = {},
		attributes = { RideKind = kind },
	}
end

return RidePuppet
