--!strict
-- tools/review/motion/Path: the squirrel's motion as the game produces it, frame by frame, without the
-- engine (owner 2026-11-11: the squirrel "looks rigid, unalive" from behind, and nobody had seen the
-- sculpted body move as the game moves it). A "take" is a scripted run of key presses at 60 frames a
-- second through the game's own code, in the order a client runs it each frame:
--   1. Controllers/Squirrel: Movement/SquirrelMotor.step (the authoritative point), then
--      Movement/SquirrelVisual.frame (the drawn point, heading, nose-up pitch and lean) and
--      Squirrel.modeOf (ground | trunk | rail | air);
--   2. Camera/CameraRig's orbit: lookStep (the mouse), focusStep (the smoothed point it looks at) and
--      orbitOffset at the distance, elevation and field of view the game starts with (orbitFraming, ORBIT,
--      FOV), behind the body;
--   3. Animation/AnimationDriver: heroClip, heroRate and heroTracks on stand-in tracks (Path.newTracks:
--      what an AnimationTrack does with Play, Stop and AdjustSpeed), then, as its Stepped does, liveSample
--      of the drawn root into Animation/Liveliness (how the body answers its own movement) and heroLayers
--      (that pose, and the Spicy Rodent's twitches under it).
-- Nothing here copies a number of the game's: speeds, turn rates, stride, camera and fades are read from
-- those modules, so a change to any of them shows in the next take. What IS made up here: the key
-- presses of each take (TAKES), the flat ground, and one straight trunk and one sagging wire built as
-- route records the way the motor specs build theirs.
-- tools/review/motion_path.luau writes the takes as JSON; tools/blender/heroes/render_motion.py draws
-- them and motion_metrics.py measures them.
--
-- A frame (all in Roblox axes and studs; frame 0 is the body at rest before the first step):
--   i, t            frame number and seconds
--   pos             the drawn FEET point (the hero model's origin: its SkinRoot)
--   yaw, pitch, roll  the drawn body is CFrame.new(pos) * Angles(0, yaw, 0) * Angles(pitch, 0, roll)
--                   (yaw 0 faces -Z; pitch is nose up; roll is minus SquirrelVisual's lean)
--   rot             the same rotation as nine numbers, row-major (columns: right, up, back)
--   root            the RootPart's centre (HipHeight above the feet along the body's up)
--   speed, cadence  what the animation is told (KinematicPose.moveSpeed, studs/s, and rad/s of stride)
--   groundSpeed     how fast the drawn feet point really moves, studs/s (all three axes)
--   mode, stalk     KinematicPose.mode and stalk
--   clip, clipTime, clipRate  the clip heroClip chose, the seconds into it and its playback speed
--   tracks          every track with weight: { clip, time, weight } (two while one clip crosses to the next)
--   cam, focus      the camera's position and the point it looks at; camYaw its orbit yaw
--   layers          { [bone] = { rx, ry, rz } }: Bone.Transform = clip pose * CFrame.Angles(rx, ry, rz);
--                   three more numbers (the Root) are an offset in studs:
--                   clip pose * CFrame.new(tx, ty, tz) * CFrame.Angles(rx, ry, rz)
--   keys, events    the keys held this frame and the motor's events (leap, land, winded, attach, ...)
--   motor           the authoritative state: x, y, z, yaw (html), grounded, vy, stamina, winded, railT
-- Interface: FPS; VARIANTS; TAKES (ordered), TAKE[name]; simulate(variant, take) -> Take;
--   newTracks(clips) -> Tracks (track(name), advance(dt), prime(name), list()); bodySize(variant) -> x, y, z
-- Pure (Lune only: @lune/roblox supplies CFrame); no side effects on require.

local roblox = require("@lune/roblox")

local AnimationDriver = require("../../../src/client/Animation/AnimationDriver")
local Liveliness = require("../../../src/client/Animation/Liveliness")
local CameraRig = require("../../../src/client/Camera/CameraRig")
local Squirrel = require("../../../src/client/Controllers/Squirrel")
local HeroAssets = require("../../../src/shared/Actors/HeroAssets")
local Curve = require("../../../src/shared/Routes/Curve")
local Graph = require("../../../src/shared/Routes/Graph")
local Motion = require("../../../src/shared/Routes/Motion")
local Registry = require("../../../src/shared/Routes/Registry")
local SpatialIndex = require("../../../src/shared/Routes/SpatialIndex")
local SquirrelMotor = require("../../../src/shared/Movement/SquirrelMotor")
local SquirrelVisual = require("../../../src/shared/Movement/SquirrelVisual")

local CFrame = (roblox :: any).CFrame

local Path = {}

Path.FORMAT = "spicy-motion/1"
Path.FPS = 60
-- The server clock at the start of every take (Creep's twitches are a function of it) and the name the
-- previewed body goes by (ActorsRuntime names bodies <species>_<id>; the name seeds the twitches).
Path.SERVER_TIME = 1000
Path.BODY_NAME = "squirrel_1"
Path.GROUND_Y = 0 -- World/Height is 0 around the origin, where the takes run (SquirrelVisual's trunk pose asks it)

export type Variant = {
	rig: string, -- the body's RigSpec attribute (AnimationDriver.heroLayers)
	hero: string, -- its entry in HeroAssets.SPECIES
	species: string, -- its Species attribute (HeroAssets.CLIPS)
	mesh: { min: { number }, max: { number } }, -- the skinned regions at rest: Roblox axes, studs, feet at 0
}

-- The bounding box of the regions (Body, Pattern, Eyes, FurCards, Blood) at rest, measured on the built
-- heroes (tools/blender/heroes/render_motion.py checks it against the .blend it loads and says so when
-- they have drifted apart). The camera's starting distance comes from the body's size.
Path.VARIANTS = {
	squirrel = {
		rig = "squirrel",
		hero = "squirrel",
		species = "squirrel",
		mesh = { min = { -0.462, -0.026, -1.172 }, max = { 0.441, 1.307, 2.32 } },
	},
	rodent = {
		rig = "rodent",
		hero = "rodent",
		species = "squirrel",
		mesh = { min = { -0.438, -0.013, -1.173 }, max = { 0.427, 1.295, 2.271 } },
	},
} :: { [string]: Variant }

-- Model:GetBoundingBox() of a hero body as Server/Assets/HeroArt leaves it: the regions, the imported
-- root (a 2 x 2 x 1 part centred on the feet, renamed SkinRoot) and the game's own RootPart (HeroArt's
-- ROOT_SIZE, HipHeight above the feet). The box is aligned with the root, so it is this union.
local SKIN_ROOT = { 2, 2, 1 }
local ROOT_SIZE = { 0.66, 0.66, 1.4 } -- Server/Assets/HeroArt.ROOT_SIZE (a server module: not required here)
function Path.bodySize(variant: Variant): (number, number, number)
	local hip = HeroAssets.SPECIES[variant.hero].hipHeight
	local lo = { -SKIN_ROOT[1] / 2, -SKIN_ROOT[2] / 2, -SKIN_ROOT[3] / 2 }
	local hi = { SKIN_ROOT[1] / 2, SKIN_ROOT[2] / 2, SKIN_ROOT[3] / 2 }
	local centre = { 0, hip, 0 }
	for k = 1, 3 do
		lo[k] = math.min(lo[k], variant.mesh.min[k], centre[k] - ROOT_SIZE[k] / 2)
		hi[k] = math.max(hi[k], variant.mesh.max[k], centre[k] + ROOT_SIZE[k] / 2)
	end
	return hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3]
end

-- Stand-in tracks ---------------------------------------------------------------------------------------
-- What AnimationDriver.heroTracks needs of an AnimationTrack, and what the Animator then does with it:
-- Play starts the clip from its beginning and brings its weight up over the fade; Stop takes the weight
-- down over the fade while the clip runs on at its speed; a looping clip wraps; a one-shot that reaches
-- its end stops.
-- Weights move in a straight line. Every hero track has the same priority (Movement), so two tracks
-- mix by their weights.

export type Track = {
	Name: string,
	Length: number,
	Looped: boolean,
	IsPlaying: boolean,
	TimePosition: number,
	Speed: number,
	weight: number,
	target: number,
	fade: number,
	Play: (self: Track, fade: number?) -> (), -- (TimePosition may be set after it: the clip starts there)
	Stop: (self: Track, fade: number?) -> (),
	AdjustSpeed: (self: Track, speed: number) -> (),
}

export type Tracks = {
	tracks: { [string]: Track },
	current: string?,
	track: (self: Tracks, name: string) -> Track,
	prime: (self: Tracks, name: string) -> (),
	advance: (self: Tracks, dt: number) -> (),
	list: (self: Tracks) -> { { clip: string, time: number, weight: number } },
}

local DEFAULT_FADE = 0.1 -- AnimationTrack:Play and :Stop when no fade time is given

local function newTrack(name: string, clip: HeroAssets.Clip): Track
	local t: Track = {
		Name = name,
		Length = clip.length,
		Looped = clip.loop,
		IsPlaying = false,
		TimePosition = 0,
		Speed = 1,
		weight = 0,
		target = 0,
		fade = DEFAULT_FADE,
		Play = function(self: Track, fade: number?)
			self.IsPlaying = true
			self.TimePosition = 0
			self.Speed = 1
			self.target = 1
			self.fade = fade or DEFAULT_FADE
			if self.fade <= 0 then
				self.weight = 1
			end
		end,
		Stop = function(self: Track, fade: number?)
			self.IsPlaying = false
			self.target = 0
			self.fade = fade or DEFAULT_FADE
			if self.fade <= 0 then
				self.weight = 0
			end
		end,
		AdjustSpeed = function(self: Track, speed: number)
			self.Speed = speed
		end,
	}
	return t
end

function Path.newTracks(clips: { [string]: HeroAssets.Clip }): Tracks
	local self: Tracks
	self = {
		tracks = {},
		current = nil,
		track = function(_: Tracks, name: string): Track
			local t = self.tracks[name]
			if t == nil then
				local clip = clips[name] or error(`Path: no clip {name}`)
				t = newTrack(name, clip)
				self.tracks[name] = t
			end
			return t
		end,
		-- the body has been playing this clip for a while (a take starts on a settled pose)
		prime = function(_: Tracks, name: string)
			local t = self:track(name)
			t:Play(0)
			self.current = name
		end,
		advance = function(_: Tracks, dt: number)
			for _, t in self.tracks do
				if t.weight ~= t.target then
					local step = dt / math.max(t.fade, 1e-6)
					if t.target > t.weight then
						t.weight = math.min(t.target, t.weight + step)
					else
						t.weight = math.max(t.target, t.weight - step)
					end
				end
				if t.IsPlaying or t.weight > 0 then
					local at = t.TimePosition + t.Speed * dt
					if t.Looped then
						at %= t.Length
					elseif at >= t.Length then
						at = t.Length
						if t.IsPlaying then
							t:Stop(DEFAULT_FADE)
						end
					end
					t.TimePosition = at
				end
			end
		end,
		list = function(_: Tracks): { { clip: string, time: number, weight: number } }
			local out = {}
			for name, t in self.tracks do
				if t.weight > 0 then
					table.insert(out, { clip = name, time = t.TimePosition, weight = t.weight })
				end
			end
			table.sort(out, function(a, b)
				if a.weight ~= b.weight then
					return a.weight > b.weight
				end
				return a.clip < b.clip
			end)
			return out
		end,
	}
	return self
end

-- Takes -------------------------------------------------------------------------------------------------

export type Keys = {
	fw: number, -- W / S
	side: number, -- D / A
	sprint: boolean, -- Shift
	focus: boolean, -- Ctrl (stalk)
	leap: boolean, -- Space, pressed this frame
	pounce: boolean, -- left click, this frame
	look: number, -- the mouse: radians per second the view turns (right is positive)
}

export type Prop = { [string]: any }

export type TakeDef = {
	name: string,
	title: string,
	seconds: number,
	keys: (t: number, i: number) -> Keys,
	-- route records (studs) the take needs, what the renderer draws for them, and the rail it starts on
	routes: { Registry.RouteRecord }?,
	props: { Prop }?,
	startOn: { routeId: number, t: number }?,
	-- stretches (seconds) the measurements use, by name
	windows: { [string]: { number } },
	-- the frames the review strips show: `count` frames from `at` seconds, every `step` frames; `tall` for
	-- a body that stands on end (the side view is then upright); `large`, the seconds of the three frames
	-- shown larger (a third of the stretch apart when not given)
	strip: { at: number, count: number, step: number, tall: boolean?, large: { number }? },
}

local function keys(over: { [string]: any }?): Keys
	local k: Keys = { fw = 0, side = 0, sprint = false, focus = false, leap = false, pounce = false, look = 0 }
	if over then
		for name, v in over do
			(k :: any)[name] = v
		end
	end
	return k
end

-- true on the one frame whose step contains second `at`
local function pressed(i: number, at: number): boolean
	return i == math.floor(at * Path.FPS + 0.5) + 1
end

local TRUNK = { x = 0, z = -9, radius = 2, height = 34 }
local WIRE = { { 0, 20, 4 }, { 0, 19.4, -16 }, { 0, 19.1, -36 }, { 0, 19.4, -56 }, { 0, 20, -76 } }
-- a quarter turn of the mouse in 0.3 s, to the left and then to the right
local TURN = { rate = 5.2, leftFrom = 0.8, leftTo = 1.1, rightFrom = 1.55, rightTo = 1.85 }

Path.TAKES = {
	{
		name = "walk",
		title = "walk straight for 3 s (W)",
		seconds = 3,
		keys = function(_t: number, _i: number): Keys
			return keys({ fw = 1 })
		end,
		windows = { steady = { 1, 3 } },
		strip = { at = 1.5, count = 16, step = 1 },
	},
	{
		name = "sprint",
		title = "sprint straight until the sprint runs out, then on (W + Shift)",
		seconds = 6,
		keys = function(_t: number, _i: number): Keys
			return keys({ fw = 1, sprint = true })
		end,
		windows = { steady = { 1, 3.8 }, winded = { 4.8, 6 } },
		strip = { at = 1.5, count = 16, step = 1 },
	},
	{
		name = "turn",
		title = "sprint through an S: the mouse swings a quarter turn left, then a quarter turn right",
		seconds = 2.7,
		keys = function(t: number, _i: number): Keys
			local look = 0
			if t >= TURN.leftFrom and t < TURN.leftTo then
				look = -TURN.rate
			elseif t >= TURN.rightFrom and t < TURN.rightTo then
				look = TURN.rate
			end
			return keys({ fw = 1, sprint = true, look = look })
		end,
		windows = { straight = { 0.4, 0.8 }, turning = { 0.8, 2.2 }, left = { 0.8, 1.3 }, right = { 1.55, 2.05 } },
		strip = { at = 0.75, count = 16, step = 5, large = { 0.95, 1.3, 1.7 } },
	},
	{
		name = "stop",
		title = "sprint, let go, stop and stand for 2 s",
		seconds = 3.75,
		keys = function(t: number, _i: number): Keys
			if t < 1.5 then
				return keys({ fw = 1, sprint = true })
			end
			return keys()
		end,
		windows = { stopping = { 1.5, 2 }, idle = { 2, 3.75 } },
		strip = { at = 1.45, count = 16, step = 2, large = { 1.45, 1.6, 2.5 } },
	},
	{
		name = "leap",
		title = "walk, pounce (the short hop, a click), then leap (Space), with both landings",
		seconds = 3.4,
		keys = function(_t: number, i: number): Keys
			return keys({ fw = 1, pounce = pressed(i, 0.7), leap = pressed(i, 1.7) })
		end,
		windows = { hop = { 0.7, 1.1 }, leap = { 1.7, 2.7 } },
		-- larger: the hop in the air, the top of the leap, its landing
		strip = { at = 1.65, count = 16, step = 4, large = { 0.85, 2.15, 2.5833 } },
	},
	{
		name = "climb",
		title = "walk into a trunk and climb it (W)",
		seconds = 3,
		keys = function(_t: number, _i: number): Keys
			return keys({ fw = 1 })
		end,
		routes = {
			{
				id = 1,
				name = "motion preview trunk",
				kind = "trunk",
				points = {
					{ TRUNK.x, Path.GROUND_Y, TRUNK.z },
					{ TRUNK.x, Path.GROUND_Y + TRUNK.height / 3, TRUNK.z },
					{ TRUNK.x, Path.GROUND_Y + TRUNK.height * 2 / 3, TRUNK.z },
					{ TRUNK.x, Path.GROUND_Y + TRUNK.height, TRUNK.z },
				},
				length = TRUNK.height,
				surfaceRadius = TRUNK.radius,
			},
		},
		props = {
			{
				kind = "trunk",
				routeId = 1,
				x = TRUNK.x,
				z = TRUNK.z,
				y0 = Path.GROUND_Y,
				height = TRUNK.height,
				radius = TRUNK.radius,
				-- the bark is where Motion.visualPose takes it to be: radius * (1 - taper * t), never under minRadius
				taper = Motion.C.visualTrunkTaper,
				minRadius = Motion.C.visualTrunkMinR,
			},
		},
		windows = { steady = { 1.3, 2.9 } },
		-- larger: the moment it takes the trunk, then two of the climb
		strip = { at = 1.5, count = 16, step = 1, tall = true, large = { 0.4, 1.5, 1.6667 } },
	},
	{
		name = "wire",
		title = "run along a wire (W), starting on it",
		seconds = 3,
		keys = function(_t: number, _i: number): Keys
			return keys({ fw = 1 })
		end,
		routes = {
			{
				id = 2,
				name = "motion preview wire",
				kind = "wire",
				points = WIRE,
				length = 80, -- (worldOf measures the curve)
				surfaceRadius = 3.375,
			},
		},
		-- as RouteProps draws a wire: a Beam 0.15 studs wide on the route's own curve
		props = { { kind = "wire", routeId = 2, radius = 0.075 } },
		startOn = { routeId = 2, t = 0.05 },
		windows = { steady = { 0.8, 2.9 } },
		strip = { at = 1.5, count = 16, step = 1 },
	},
	{
		name = "stalk",
		title = "stalk straight for 3 s (Ctrl + W)",
		seconds = 3,
		keys = function(_t: number, _i: number): Keys
			return keys({ fw = 1, focus = true })
		end,
		windows = { steady = { 1, 3 } },
		strip = { at = 1.5, count = 16, step = 2 },
	},
} :: { TakeDef }

Path.TAKE = {} :: { [string]: TakeDef }
for _, def in Path.TAKES do
	Path.TAKE[def.name] = def
end

-- Simulation ----------------------------------------------------------------------------------------------

local function round(x: number): number
	local r = math.floor(x * 1e5 + 0.5) / 1e5
	return if r == 0 then 0 else r -- (never -0)
end

local function vec(x: number, y: number, z: number): { x: number, y: number, z: number }
	return { x = round(x), y = round(y), z = round(z) }
end

-- the motor's world for a take: flat ground, no walls, and the take's own routes (each as long as its
-- curve really is, so a rail speed is the speed along it)
local function worldOf(def: TakeDef): SquirrelMotor.World
	local records = {}
	for _, r in def.routes or {} do
		local rec = table.clone(r)
		rec.length = Curve.fromArrays(rec.points):getLength()
		table.insert(records, rec)
	end
	local registry = Registry.fromRecords(records)
	local index = SpatialIndex.build(registry)
	local world: any = {
		registry = registry,
		index = index,
		graph = Graph.build(registry, index, nil),
		trampolines = {},
		groundAt = function(_x: number, _z: number, _refY: number): number
			return Path.GROUND_Y
		end,
	}
	return world
end

export type Take = { [string]: any }

function Path.simulate(variantName: string, takeName: string): Take
	local variant = Path.VARIANTS[variantName] or error(`Path: no variant {variantName}`)
	local def = Path.TAKE[takeName] or error(`Path: no take {takeName}`)
	local dt = 1 / Path.FPS
	local world = worldOf(def)
	local hip = HeroAssets.SPECIES[variant.hero].hipHeight
	local clips = HeroAssets.CLIPS[variant.species]

	-- the body: at rest at the origin, facing -Z (html yaw pi), as Controllers/Squirrel starts one
	local state = SquirrelMotor.new(0, Path.GROUND_Y, 0)
	state.yaw = math.pi
	if def.startOn then
		-- taken over on a rail (the controller resumes an AI squirrel there)
		local route = world.registry:get(def.startOn.routeId) or error("Path: startOn names no route")
		local p = world.registry:pointAt(route, def.startOn.t)
		state.routeId = route.id
		state.railT = def.startOn.t
		state.railDir = 1
		state.grounded = false
		state.x, state.y, state.z = p.x, p.y, p.z
	end
	local visual = SquirrelVisual.new()
	local at = SquirrelMotor.visualPose(state, world)
	visual.x, visual.y, visual.z = at.x, at.y, at.z
	visual.live = true
	visual.yaw = state.yaw
	visual.rail = state.routeId ~= nil

	-- what is drawn: Controllers/Squirrel's root CFrame is this one times CFrame.new(0, hip, 0), and
	-- HeroArt welds the skin's root HipHeight below the root, so this is the hero model's own frame
	local function drawn(): any
		return CFrame.new(visual.x, visual.y, visual.z)
			* CFrame.Angles(0, (visual.yaw or state.yaw) + math.pi, 0)
			* CFrame.Angles(visual.pitch, 0, -visual.lean)
	end

	-- the camera: CameraRig.orbit meeting this body for the first time
	local sx, sy, sz = Path.bodySize(variant)
	local lift, _, _, dist = CameraRig.orbitFraming(sx, sy, sz, false)
	local first = drawn() * CFrame.new(0, hip, 0)
	local look = first.LookVector
	local orbitYaw = math.atan2(-look.X, -look.Z)
	local orbitElev = CameraRig.ORBIT.elev
	local fx, fy, fz = first.Position.X, first.Position.Y + lift, first.Position.Z
	local lx, ly, lz = fx, fy, fz

	-- the animation: the body has been standing for a while
	local player = Path.newTracks(clips)
	player:prime(AnimationDriver.heroClip(Squirrel.modeOf(state.routeId ~= nil, 0, state.grounded), 0, false))
	local seed = AnimationDriver.creepSeed(Path.BODY_NAME)
	-- ... and the driver has been layering Liveliness on it (AnimationDriver's Stepped): what the body is
	-- told is what Controllers/Squirrel publishes as its KinematicPose
	local live = Liveliness.new(seed, variant.rig)
	local function enliven(i: number, mode: string, stalk: boolean)
		local kin = {
			moveSpeed = visual.moveSpeed,
			cadence = visual.cadence,
			climb = visual.climb,
			mode = mode,
			stalk = stalk,
			winded = state.winded,
		}
		local root = drawn() * CFrame.new(0, hip, 0)
		local sample = AnimationDriver.liveSample(root, visual.moveSpeed, mode, kin, Path.SERVER_TIME + i * dt, false)
		Liveliness.frame(live, sample, dt)
	end

	local frames = {}
	local px, py, pz = visual.x, visual.y, visual.z
	local function record(i: number, k: Keys, events: { SquirrelMotor.Event }, mode: string, stalk: boolean)
		local cf = drawn()
		local comps = { cf:GetComponents() }
		local root = (cf * CFrame.new(0, hip, 0)).Position
		local ox, oy, oz = CameraRig.orbitOffset(orbitYaw, orbitElev, 1)
		local current = player:track(player.current :: string)
		local eventNames = {}
		for _, e in events do
			table.insert(eventNames, e.kind)
		end
		local rot = {}
		for j = 4, 12 do
			rot[j - 3] = round(comps[j])
		end
		local tracks = player:list()
		for _, tr in tracks do
			tr.time, tr.weight = round(tr.time), round(tr.weight)
		end
		local layers = {}
		for bone, r in AnimationDriver.heroLayers(variant.rig, Path.SERVER_TIME + i * dt, seed, live) do
			local rounded = {}
			for j, v in r do
				rounded[j] = round(v)
			end
			layers[bone] = rounded
		end
		local moved = math.sqrt((visual.x - px) ^ 2 + (visual.y - py) ^ 2 + (visual.z - pz) ^ 2)
		px, py, pz = visual.x, visual.y, visual.z
		table.insert(frames, {
			i = i,
			t = round(i * dt),
			pos = vec(visual.x, visual.y, visual.z),
			yaw = round((visual.yaw or state.yaw) + math.pi),
			pitch = round(visual.pitch),
			roll = round(-visual.lean),
			rot = rot,
			root = vec(root.X, root.Y, root.Z),
			speed = round(visual.moveSpeed),
			cadence = round(visual.cadence),
			groundSpeed = round(if i == 0 then 0 else moved / dt),
			mode = mode,
			stalk = stalk,
			clip = current.Name,
			clipTime = round(current.TimePosition),
			clipRate = round(current.Speed),
			tracks = tracks,
			cam = vec(fx + ox * dist, fy + oy * dist, fz + oz * dist),
			focus = vec(fx, fy, fz),
			camYaw = round(orbitYaw),
			layers = layers,
			keys = {
				fw = k.fw,
				side = k.side,
				sprint = k.sprint,
				focus = k.focus,
				leap = k.leap,
				pounce = k.pounce,
				look = k.look,
			},
			events = eventNames,
			motor = {
				x = round(state.x),
				y = round(state.y),
				z = round(state.z),
				yaw = round(state.yaw),
				grounded = state.grounded,
				vy = round(state.vy),
				stamina = round(state.stamina),
				winded = state.winded,
				railT = if state.routeId then round(state.railT) else nil,
			},
		})
	end

	enliven(0, Squirrel.modeOf(state.routeId ~= nil, visual.climb, state.grounded, visual.trunk), false)
	record(0, keys(), {}, Squirrel.modeOf(state.routeId ~= nil, visual.climb, state.grounded, visual.trunk), false)
	-- (Controllers/Squirrel's KinematicPose.action and airSeconds: how the body left its surface)
	local action: string?, airSeconds: number? = nil, nil
	local count = math.floor(def.seconds * Path.FPS + 0.5)
	for i = 1, count do
		local k = def.keys((i - 1) / Path.FPS, i)
		-- 1. the controller (Controllers/Squirrel's render step; the camera it reads is last frame's)
		local input: SquirrelMotor.Input = {
			fw = k.fw,
			side = k.side,
			sprint = k.sprint,
			focus = k.focus,
			cameraYaw = orbitYaw,
			cameraPitch = 0.12,
			leap = k.leap,
			drop = false,
			grab = false,
			choose = 0,
			pounce = k.pounce,
		}
		local _, events = SquirrelMotor.step(state, input, dt, world)
		SquirrelVisual.frame(visual, state, world, dt, world.groundAt)
		local mode = Squirrel.modeOf(state.routeId ~= nil, visual.climb, state.grounded, visual.trunk)
		local stalk = state.focus
		local launched, seconds = Squirrel.launch(events :: any, state.vy)
		if launched or mode ~= "air" then
			action, airSeconds = launched, seconds
		end
		-- 2. the camera (CameraRig.orbit's render step)
		orbitYaw, orbitElev = CameraRig.lookStep(orbitYaw, orbitElev, k.look * dt, 0, false)
		local root = (drawn() * CFrame.new(0, hip, 0)).Position
		local tx, ty, tz = root.X, root.Y + lift, root.Z
		fx, fy, fz = CameraRig.focusStep(fx, fy, fz, tx, ty, tz, dt, lx, ly, lz)
		lx, ly, lz = tx, ty, tz
		-- 3. the animation (AnimationDriver's hero branch, then the Animator moves the tracks on)
		local braking = live.accel < -AnimationDriver.HERO.brake
		local want = AnimationDriver.heroClip(mode, visual.moveSpeed, stalk, action, player.current, braking)
		local clip = clips[want]
		player.current = AnimationDriver.heroTracks(
			player.tracks,
			player.current,
			want,
			player:track(want),
			clip.loop,
			AnimationDriver.heroRate(want, visual.moveSpeed, visual.cadence, clip.length, airSeconds),
			AnimationDriver.heroStart(want, action)
		)
		player:advance(dt)
		enliven(i, mode, stalk)
		record(i, k, events, mode, stalk)
	end

	-- what the renderer draws around the body
	local props = {}
	for _, p in def.props or {} do
		local prop = table.clone(p)
		if prop.kind == "wire" then
			-- the route's own curve, as a line of points a stud or so apart
			local route = world.registry:get(prop.routeId) :: Registry.Route
			local n = math.max(8, math.ceil(route.length))
			local points = {}
			for j = 0, n do
				local q = world.registry:pointAt(route, j / n)
				table.insert(points, { round(q.x), round(q.y), round(q.z) })
			end
			prop.points = points
		end
		table.insert(props, prop)
	end
	local clipTable = {}
	for name, c in clips do
		clipTable[name] = { length = c.length, loop = c.loop }
	end
	local stride = def.strip
	local start = math.floor(stride.at * Path.FPS + 0.5)
	local last = start + (stride.count - 1) * stride.step
	local large = {
		start,
		start + math.floor((last - start) / 3 + 0.5),
		start + math.floor((last - start) * 2 / 3 + 0.5),
	}
	if stride.large then
		for j, seconds in stride.large do
			large[j] = math.floor(seconds * Path.FPS + 0.5)
		end
	end
	return {
		format = Path.FORMAT,
		variant = variantName,
		rig = variant.rig,
		take = def.name,
		title = def.title,
		fps = Path.FPS,
		seconds = def.seconds,
		hipHeight = hip,
		bodySize = { round(sx), round(sy), round(sz) },
		mesh = variant.mesh,
		camera = {
			distance = round(dist),
			elevation = CameraRig.ORBIT.elev,
			fov = CameraRig.FOV,
			lift = round(lift),
		},
		ground = { y = Path.GROUND_Y, grid = 1 },
		props = props,
		clips = clipTable,
		windows = def.windows,
		strip = {
			start = start,
			count = stride.count,
			step = stride.step,
			tall = stride.tall == true,
			large = large,
		},
		serverTime = Path.SERVER_TIME,
		bodyName = Path.BODY_NAME,
		frames = frames,
	}
end

return Path
