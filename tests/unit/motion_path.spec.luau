--!strict
-- tests/unit/motion_path.spec.luau
-- The offline motion preview (tools/review/motion/Path, written out by tools/review/motion_path.luau):
-- scripted takes of the squirrel through the game's own motor, drawn pose, camera and animation rules.
-- What is pinned: the stand-in tracks behave as AnimationTracks do under AnimationDriver.heroTracks (a
-- change of clip crosses over, a loop wraps, a one-shot holds its end); every take runs, is the same every
-- time, and shows what its title says; the camera stands where CameraRig's orbit starts, behind the body;
-- the clip and its rate are AnimationDriver's own answers; the layers are AnimationDriver.heroLayers'
-- (Animation/Liveliness on both bodies, fed the drawn root as the driver feeds it, and the twitches under
-- it on the Spicy Rodent), so the turning, stopping and leaping takes show the body answering.

local AnimationDriver = require("@client/Animation/AnimationDriver")
local CameraRig = require("@client/Camera/CameraRig")
local Squirrel = require("@client/Controllers/Squirrel")
local HeroAssets = require("@shared/Actors/HeroAssets")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Path = require("@tests/../tools/review/motion/Path")

local H = AnimationDriver.HERO
local CLIPS = HeroAssets.CLIPS.squirrel

return function(t: any)
	local dt = 1 / Path.FPS

	t.test("the held body's mode and the clip crossover are the game's own (Squirrel.modeOf, HERO)", function()
		t.eq(Squirrel.modeOf(false, 0, true), "ground")
		t.eq(Squirrel.modeOf(false, 0, false), "air")
		t.eq(Squirrel.modeOf(true, 0.2, false), "rail")
		t.eq(Squirrel.modeOf(true, 0.5, false), "rail")
		t.eq(Squirrel.modeOf(true, 0.51, false), "trunk", "leaving a trunk, while most of the climb pose still shows")
		t.eq(Squirrel.modeOf(true, 1, true), "trunk")
		t.eq(Squirrel.modeOf(true, 0, false, true), "trunk", "on a trunk from the moment it is taken")
		t.eq(Squirrel.modeOf(true, 0.2, false, false), "rail")
		t.eq(Squirrel.modeOf(false, 0, true, true), "ground")
		-- how the motor's events sent the body up, and for how long gravity says
		local g = SquirrelMotor.params.gravity
		local action, seconds = Squirrel.launch({ { kind = "winded" }, { kind = "leap" } }, 30)
		t.eq(action, "leap")
		t.near(seconds :: number, 60 / g, 1e-9)
		action, seconds = Squirrel.launch({ { kind = "pounce" } }, 8)
		t.eq(action, "pounce")
		t.near(seconds :: number, 16 / g, 1e-9)
		action, seconds = Squirrel.launch({ { kind = "land" } }, -20)
		t.eq(action, nil)
		t.eq(seconds, nil)
		t.eq((Squirrel.launch({}, 5)), nil)
		-- the crossover the driver has always used (a change here changes what every body shows)
		t.eq(H.fade, 0.15)
		t.eq(H.refade, 0.1)
		t.eq(H.holdEnd, 0.06)
	end)

	t.test("stand-in tracks: a change of clip crosses over in HERO.fade and both run on meanwhile", function()
		local p = Path.newTracks(CLIPS)
		p:prime("Idle")
		t.eq(p.current, "Idle")
		t.eq(p:track("Idle").weight, 1)
		t.eq(p:track("Idle").IsPlaying, true)
		-- the driver asks for Run
		p.current = AnimationDriver.heroTracks(p.tracks, p.current, "Run", p:track("Run"), true, 2)
		t.eq(p.current, "Run")
		t.eq(p:track("Idle").IsPlaying, false, "the old clip is stopped")
		t.eq(p:track("Run").TimePosition, 0, "the new one starts at its beginning")
		p:advance(dt)
		t.near(p:track("Run").weight, dt / H.fade, 1e-12)
		t.near(p:track("Idle").weight, 1 - dt / H.fade, 1e-12)
		t.near(p:track("Run").TimePosition, 2 * dt, 1e-12, "at the rate asked")
		t.near(p:track("Idle").TimePosition, dt, 1e-12, "the fading clip keeps running")
		local list = p:list()
		t.eq(#list, 2)
		t.eq(list[1].clip, "Idle", "heaviest first")
		t.near(list[1].weight + list[2].weight, 1, 1e-12)
		for _ = 1, 20 do
			p.current = AnimationDriver.heroTracks(p.tracks, p.current, "Run", p:track("Run"), true, 2)
			p:advance(dt)
		end
		t.eq(p:track("Run").weight, 1)
		t.eq(p:track("Idle").weight, 0)
		t.eq(#p:list(), 1)
		-- a loop wraps at its length
		local at = p:track("Run").TimePosition
		t.truthy(at >= 0 and at < CLIPS.Run.length, `Run at {at}`)
		t.near(at, (21 * 2 * dt) % CLIPS.Run.length, 1e-9)
		-- it stands: the gait is held where it is as Idle comes in (its legs do not run on under it)
		p.current = AnimationDriver.heroTracks(p.tracks, p.current, "Idle", p:track("Idle"), true, 1)
		t.eq(p:track("Run").IsPlaying, false)
		t.eq(p:track("Run").Speed, 0)
		p:advance(dt)
		t.eq(p:track("Run").TimePosition, at)
		t.near(p:track("Run").weight, 1 - dt / H.fade, 1e-12)
		-- ... and runs again from its beginning at the rate asked
		p.current = AnimationDriver.heroTracks(p.tracks, p.current, "Run", p:track("Run"), true, 2)
		t.eq(p:track("Run").TimePosition, 0)
		t.eq(p:track("Run").Speed, 2)
	end)

	t.test(
		"stand-in tracks: a leap starts where it is told, is held where it comes down, and lands as it fades",
		function()
			local p = Path.newTracks(CLIPS)
			p:prime("Run")
			local air = H.air.Leap
			local from = AnimationDriver.heroStart("Leap", "leap")
			t.eq(from, air.launch, "a leap starts at its take-off: the body is already in the air")
			t.eq(AnimationDriver.heroStart("Leap", nil), air.fall, "a fall further in")
			t.eq(AnimationDriver.heroStart("Pounce", "pounce"), H.air.Pounce.launch)
			t.eq(AnimationDriver.heroStart("Run", nil), 0)
			p.current = AnimationDriver.heroTracks(p.tracks, p.current, "Leap", p:track("Leap"), false, 1, from)
			local leap = p:track("Leap")
			t.eq(leap.TimePosition, from)
			for _ = 1, 120 do
				p:advance(dt)
				p.current = AnimationDriver.heroTracks(p.tracks, p.current, "Leap", p:track("Leap"), false, 1, from)
			end
			t.eq(leap.IsPlaying, true, "held, not ended")
			t.eq(leap.Speed, 0)
			t.truthy(leap.TimePosition >= air.land and leap.TimePosition < air.land + 2 * dt, "held on the reach")
			t.eq(leap.weight, 1)
			-- it lands: the run comes in, and the leap runs on through its landing keys as it fades
			local held = leap.TimePosition
			p.current = AnimationDriver.heroTracks(p.tracks, p.current, "Run", p:track("Run"), true, 1, 0)
			t.eq(leap.IsPlaying, false)
			t.eq(leap.Speed, H.landRate)
			p:advance(dt)
			t.near(leap.TimePosition, held + H.landRate * dt, 1e-9)
			t.near(leap.weight, 1 - dt / H.fade, 1e-9)
			-- into the air again: from the take-off again
			p.current = AnimationDriver.heroTracks(p.tracks, p.current, "Leap", p:track("Leap"), false, 1, from)
			t.eq(leap.TimePosition, from)
			t.eq(leap.Speed, 1)
			-- a one-shot that carries no body through the air is held at its end (the bite)
			local b = Path.newTracks(CLIPS)
			b:prime("Run")
			for _ = 1, 200 do
				b.current = AnimationDriver.heroTracks(b.tracks, b.current, "Bite", b:track("Bite"), false, 1)
				b:advance(dt)
			end
			local bite = b:track("Bite")
			t.eq(bite.Speed, 0)
			t.truthy(bite.TimePosition >= CLIPS.Bite.length - H.holdEnd and bite.TimePosition < CLIPS.Bite.length)
			-- left alone at full speed a one-shot ends and fades away
			local q = Path.newTracks(CLIPS)
			q:track("Leap"):Play(0)
			for _ = 1, 80 do
				q:advance(dt)
			end
			t.eq(q:track("Leap").IsPlaying, false)
			t.eq(q:track("Leap").weight, 0)
		end
	)

	t.test("the camera's first distance comes from the body's size, as CameraRig.orbit takes it", function()
		for name, variant in Path.VARIANTS do
			local sx, sy, sz = Path.bodySize(variant)
			t.eq(sx, 2, "the imported root is the widest thing")
			t.near(sy, variant.mesh.max[2] + 1, 1e-9, "from the bottom of the imported root to the top of the fur")
			t.near(sz, variant.mesh.max[3] - variant.mesh.min[3], 1e-9, "nose to tail tip")
			local lift, _, _, dist = CameraRig.orbitFraming(sx, sy, sz, false)
			local take = Path.simulate(name, "walk")
			t.near(take.camera.distance, dist, 1e-4)
			t.near(take.camera.lift, lift, 1e-4)
			t.eq(take.camera.fov, CameraRig.FOV)
			t.eq(take.camera.elevation, CameraRig.ORBIT.elev)
			t.eq(take.hipHeight, HeroAssets.SPECIES[variant.hero].hipHeight)
		end
	end)

	t.test(
		"walk: 3 s at 60 frames a second, straight, the camera behind; the clip and rate are the driver's",
		function()
			local take = Path.simulate("squirrel", "walk")
			t.eq(take.format, Path.FORMAT)
			t.eq(take.fps, 60)
			t.eq(#take.frames, 181)
			local first, last = take.frames[1], take.frames[181]
			t.eq(first.i, 0)
			t.eq(first.clip, "Idle")
			t.eq(first.speed, 0)
			t.near(last.t, 3, 1e-9)
			t.near(last.speed, SquirrelMotor.params.walk, 1e-3)
			t.near(last.groundSpeed, SquirrelMotor.params.walk, 1e-2, "the drawn point moves at the motor's speed")
			t.truthy(
				last.pos.z < -50 and math.abs(last.pos.x) < 1e-3 and last.pos.y == 0,
				"straight ahead (-Z) on the ground"
			)
			for _, f in take.frames do
				-- behind and above: the camera is on the +Z side of the body, at the framing distance from its focus
				t.truthy(f.cam.z > f.pos.z + 10 and f.cam.y > f.pos.y + 4, `camera behind at frame {f.i}`)
				local d = math.sqrt((f.cam.x - f.focus.x) ^ 2 + (f.cam.y - f.focus.y) ^ 2 + (f.cam.z - f.focus.z) ^ 2)
				t.near(d, take.camera.distance, 1e-3)
				-- Liveliness is layered on it; running straight on the flat there is no turn in it
				t.truthy(f.layers.Root ~= nil and f.layers.Tail8 ~= nil, `layers at frame {f.i}`)
				-- (nothing but the small swing of the "weave" manner of running, when that is on)
				t.truthy(math.abs(f.layers.Spine2[2]) <= 0.04, "no bend from turning")
				t.eq(f.layers.Head[3], 0, "no roll")
				t.eq(f.layers.Jaw, nil, "the jaw is the Spicy Rodent's to twitch")
				t.eq(f.mode, "ground")
				-- the root is HipHeight above the feet (the body is level)
				t.near(f.root.y - f.pos.y, take.hipHeight, 1e-4)
			end
			-- at the walk speed the body gallops: the Run clip at the motor's cadence
			t.eq(last.clip, AnimationDriver.heroClip("ground", last.speed, false))
			t.eq(last.clip, "Run")
			t.near(last.clipRate, AnimationDriver.heroRate("Run", last.speed, last.cadence, CLIPS.Run.length), 1e-4)
			t.eq(#last.tracks, 1)
			t.eq(last.tracks[1].weight, 1)
			-- the clip's clock moves by its rate each frame, wrapping at its length
			local a, b = take.frames[150], take.frames[151]
			t.near((a.clipTime + b.clipRate * dt) % CLIPS.Run.length, b.clipTime, 1e-4)
			-- the same every time
			local again = Path.simulate("squirrel", "walk")
			t.deepEq(again.frames[97], take.frames[97])
			t.deepEq(again.strip, take.strip)
			t.eq(take.strip.count, 16)
			t.truthy(take.strip.start + (take.strip.count - 1) * take.strip.step <= 180)
		end
	)

	t.test("every take runs to its end and its strip and windows lie inside it", function()
		local names = {}
		for _, def in Path.TAKES do
			table.insert(names, def.name)
			local take = Path.simulate("squirrel", def.name)
			local n = #take.frames
			t.eq(n, math.floor(def.seconds * Path.FPS + 0.5) + 1, def.name)
			local s = take.strip
			t.truthy(s.count >= 12 and s.count <= 16, `{def.name}: {s.count} frames in the strip`)
			t.truthy(s.start >= 0 and s.start + (s.count - 1) * s.step <= n - 1, `{def.name}: strip inside the take`)
			t.eq(#s.large, 3)
			for _, w in take.windows do
				t.truthy(w[1] >= 0 and w[2] <= def.seconds and w[1] < w[2], `{def.name}: window`)
			end
			for _, f in take.frames do
				local sum = 0
				for _, tr in f.tracks do
					sum += tr.weight
				end
				-- one clip, or two crossing over, make up the whole pose; a third that was cut short while
				-- it was still coming in leaves a little of the rest pose showing for a few frames
				t.truthy(sum > 0.7 and sum <= 1 + 1e-4, `{def.name}: track weights {sum} at frame {f.i}`)
			end
			local settled = take.frames[n].tracks
			t.eq(#settled, 1, `{def.name}: one clip at the end`)
			t.eq(settled[1].weight, 1)
		end
		t.eq(table.concat(names, " "), "walk sprint turn stop leap climb wire stalk")
	end)

	t.test("sprint runs out; the S turns left then right; a stop ends standing", function()
		local sprint = Path.simulate("squirrel", "sprint")
		local windedAt: number? = nil
		for _, f in sprint.frames do
			if table.find(f.events, "winded") then
				windedAt = f.t
			end
		end
		t.truthy(windedAt and math.abs(windedAt - SquirrelMotor.params.sprintSeconds) < 0.1, `winded at {windedAt}`)
		t.near(sprint.frames[200].speed, SquirrelMotor.params.sprint, 1e-2)
		t.near(sprint.frames[361].speed, SquirrelMotor.params.walk, 1e-2, "then on at a walk")
		t.eq(sprint.frames[200].clipRate, H.maxRate, "the sprint's stride is faster than the clip may play")

		local turn = Path.simulate("squirrel", "turn")
		local minX, maxRoll, minRoll = 0, 0, 0
		for _, f in turn.frames do
			minX = math.min(minX, f.pos.x)
			maxRoll = math.max(maxRoll, f.roll)
			minRoll = math.min(minRoll, f.roll)
		end
		local last = turn.frames[#turn.frames]
		t.truthy(minX < -15, "it swung left (-X)")
		t.near(math.cos(last.yaw), 1, 0.02, "and came back to its first heading")
		t.truthy(maxRoll > 0.08 and minRoll < -0.08, `it leaned into both turns ({maxRoll}, {minRoll})`)
		-- the camera turned with the mouse and is still behind the body's travel at the end
		t.near(math.cos(last.camYaw), 1, 1e-6)
		t.truthy(last.cam.z > last.pos.z + 10)

		local stop = Path.simulate("squirrel", "stop")
		local final = stop.frames[#stop.frames]
		-- a run that is braking keeps to its run until it stands: no walk on the way down
		for _, f in stop.frames do
			t.truthy(f.t < 1 or f.clip ~= "Walk", `Walk at {f.t} s of the stop`)
		end
		t.eq(final.clip, "Idle")
		t.truthy(final.speed < 0.01 and final.groundSpeed < 0.01)
		t.eq(#final.tracks, 1)
	end)

	t.test(
		"a stop from a run or a sprint, let go anywhere in the bound, ends the bound with its feet under it",
		function()
			-- the stop take with the keys let go at other moments (the take itself is one moment of a sprint)
			local def = Path.TAKE.stop
			local keys = def.keys
			local S = H.settle
			local worstEarly, worstLate = S.at, S.at
			for _, sprint in { true, false } do
				for k = 0, 13 do
					local release = 1.5 + k / 60
					def.keys = function(time: number, i: number)
						local held = keys(if time < release then 0 else 10, i)
						held.sprint = held.sprint and sprint
						return held
					end
					local take = Path.simulate("squirrel", "stop")
					local runEnds: number? = nil
					for _, f in take.frames do
						if f.t >= release then
							t.truthy(f.clip ~= "Walk", `Walk at {f.t} s (let go at {release}, sprint {sprint})`)
							for _, tr in f.tracks do
								if tr.clip == "Run" then
									runEnds = tr.time
								end
							end
						end
					end
					t.eq(take.frames[#take.frames].clip, "Idle")
					-- where the run was left: between the fore paws' landing and the gathered pose, from where
					-- the cross to Idle keeps every paw at the ground (in flight it hung there and its legs
					-- went a quarter of a stud under on the way down)
					local ends = runEnds :: number
					worstEarly, worstLate = math.min(worstEarly, ends), math.max(worstLate, ends)
				end
			end
			def.keys = keys
			print(`      the run is left between {worstEarly} and {worstLate} s of its bound (gathered at {S.at})`)
			t.truthy(worstEarly >= 0.04, `left at {worstEarly}`)
			t.truthy(worstLate <= S.at + S.slack + 0.005, `left at {worstLate}`)
		end
	)

	t.test("leap: the hop on the Pounce clip and the leap on the Leap clip, each paced to its landing", function()
		local take = Path.simulate("squirrel", "leap")
		local events = {}
		local highest, airFrames = 0, 0
		local lastAir: { [string]: any } = {}
		local landedOn: { [string]: number } = {}
		for i, f in take.frames do
			for _, e in f.events do
				table.insert(events, e)
			end
			highest = math.max(highest, f.pos.y)
			if f.mode == "air" then
				airFrames += 1
				-- the click's hop is a pounce, Space's is a leap; each starts at its take-off
				local name = if f.t < 1.5 then "Pounce" else "Leap"
				t.eq(f.clip, name)
				local air = H.air[name]
				t.truthy(f.clipTime >= air.launch and f.clipTime <= air.land + 0.03, `{name} at {f.clipTime}`)
				t.truthy(f.clipRate > 0, "not frozen in the air: it is paced to the flight")
				lastAir[name] = f
			elseif take.frames[i - 1] and take.frames[i - 1].mode == "air" then
				landedOn[take.frames[i - 1].clip] = take.frames[i - 1].clipTime
			end
		end
		-- each comes down at its landing key, give or take a frame or two of the motor's own landing
		t.near(landedOn.Pounce, H.air.Pounce.land, 0.06)
		t.near(landedOn.Leap, H.air.Leap.land, 0.04)
		t.near(
			lastAir.Leap.clipRate,
			(H.air.Leap.land - H.air.Leap.launch) / (2 * 31.25 / SquirrelMotor.params.gravity),
			0.02
		)
		t.eq(table.concat(events, " "), "pounce land leap land")
		t.truthy(highest > 0.85 * SquirrelMotor.leapApex() and highest <= SquirrelMotor.leapApex(), `apex {highest}`)
		t.truthy(airFrames > 55, `{airFrames} frames in the air`)
		t.eq(take.frames[#take.frames].mode, "ground")
	end)

	t.test("climb and wire: the fake trunk is mounted and climbed nose up; the wire is run level", function()
		local climb = Path.simulate("squirrel", "climb")
		local last = climb.frames[#climb.frames]
		t.eq(last.mode, "trunk")
		t.eq(last.clip, "Climb")
		t.truthy(last.pitch > 1.3, `nose up ({last.pitch})`)
		t.truthy(last.pos.y > 20, "well up the trunk")
		local trunk = climb.props[1]
		t.eq(trunk.kind, "trunk")
		-- the drawn feet point (the soles) is on the bark, on the side it came from (+Z)
		local barkR = math.max(trunk.minRadius, trunk.radius * (1 - trunk.taper * last.motor.railT))
		local off = last.pos.z - trunk.z - barkR
		t.truthy(off > -0.02 and off < 0.1, `{off} studs off the bark`)
		t.near(last.pos.x, trunk.x, 1e-3)

		local wire = Path.simulate("squirrel", "wire")
		local w = wire.props[1]
		t.eq(w.kind, "wire")
		t.truthy(#w.points > 40)
		local f = wire.frames[#wire.frames]
		t.eq(f.mode, "rail")
		t.eq(f.clip, "Wire")
		t.eq(f.pitch, 0)
		t.truthy(f.pos.z < -40 and math.abs(f.pos.x) < 1e-3)
		t.truthy(f.pos.y > 19 and f.pos.y < 20.7, "on the wire")
	end)

	t.test("stalk creeps on the Stalk clip; the Spicy Rodent's layers are heroLayers at that moment", function()
		local stalk = Path.simulate("squirrel", "stalk")
		local f = stalk.frames[#stalk.frames]
		t.eq(f.stalk, true)
		t.eq(f.clip, "Stalk")
		t.near(f.speed, SquirrelMotor.params.stalk, 1e-3)

		local rodent = Path.simulate("rodent", "walk")
		local squirrel = Path.simulate("squirrel", "walk")
		local seed = AnimationDriver.creepSeed(Path.BODY_NAME)
		for _, i in { 0, 37, 180 } do
			local frame = rodent.frames[i + 1]
			-- what only Creep moves is Creep's at that moment; what only Liveliness moves is what the
			-- squirrel, moving the same way, is given
			local creep = AnimationDriver.heroLayers("rodent", Path.SERVER_TIME + i * dt, seed)
			local plain = squirrel.frames[i + 1].layers
			t.near(frame.layers.Jaw[1], creep.Jaw[1], 1e-5)
			t.near(frame.layers.EarL[3] - (if plain.EarL then plain.EarL[3] else 0), creep.EarL[3], 1e-5)
			t.near(frame.layers.Head[3] - plain.Head[3], creep.Head[3], 1e-5, "(a walk is too slow to calm the head)")
			t.deepEq(frame.layers.Root, plain.Root)
			t.deepEq(frame.layers.Hips, plain.Hips)
			t.eq(#frame.layers.Root, 6, "the root carries its offset")
			t.eq(#frame.layers.Head, 3)
			local n = 0
			for _ in frame.layers do
				n += 1
			end
			t.truthy(n >= 19, "root, hips, spine, neck, head, jaw, ears and tail")
		end
		-- the body under the layers moves exactly as the squirrel's does
		t.deepEq(rodent.frames[100].pos, squirrel.frames[100].pos)
		t.eq(rodent.frames[100].clipTime, squirrel.frames[100].clipTime)
	end)

	t.test(
		"the takes show the body answering: a turn bends it, a stop dips it, a leap pitches and squashes it",
		function()
			local function col(frames: { any }, bones: { string }, k: number): { number }
				local out = {}
				for i, f in frames do
					local s = 0
					for _, b in bones do
						local r = f.layers[b]
						s += if r then r[k] or 0 else 0
					end
					out[i] = s
				end
				return out
			end
			local SPINE = { "Spine1", "Spine2", "Spine3", "Chest" }
			local TAIL = { "Tail1", "Tail2", "Tail3", "Tail4", "Tail5", "Tail6", "Tail7", "Tail8" }
			for _, variant in { "squirrel", "rodent" } do
				-- the S: a quarter turn to the left from 0.8 s (yaw rises), then one to the right from 1.55 s
				local turn = Path.simulate(variant, "turn").frames
				local bend, head, tail = col(turn, SPINE, 2), col(turn, { "Neck", "Head" }, 2), col(turn, TAIL, 2)
				local left, right = 1 + math.floor(1.05 * Path.FPS), 1 + math.floor(1.8 * Path.FPS)
				t.truthy(bend[left] > 0.25 and bend[right] < -0.25, `{variant}: the spine bends into each turn`)
				t.truthy(
					turn[left].layers.Hips[2] < -0.05 and turn[right].layers.Hips[2] > 0.05,
					"the pelvis the other way"
				)
				if variant == "squirrel" then
					t.truthy(head[left] > 0.15 and head[right] < -0.15, "the head turns further in")
				end
				-- the tail is left behind (to the left of a body turning left), most of all after the spine
				local tailMost, tailAt, bendMost, bendAt = 0, 0, 0, 0
				for i = 1, 1 + math.floor(1.5 * Path.FPS) do
					if tail[i] < tailMost then
						tailMost, tailAt = tail[i], i
					end
					if bend[i] > bendMost then
						bendMost, bendAt = bend[i], i
					end
				end
				t.truthy(tailMost < -0.5, `{variant}: the tail trails {tailMost} rad`)
				t.truthy(tailAt > bendAt, "after the spine")
				t.truthy(col(turn, SPINE, 3)[left] > 0.05, "the shoulders bank into it")

				-- the stop: sprint let go at 1.5 s
				local stop = Path.simulate(variant, "stop").frames
				local pitch, lift = col(stop, { "Root" }, 1), col(stop, TAIL, 1)
				local dip, raised, rebound = 0, 0, 0
				for i = 1 + math.floor(1.5 * Path.FPS), #stop do
					dip = math.min(dip, pitch[i])
					raised = math.min(raised, lift[i])
					if dip < -0.1 then
						rebound = math.max(rebound, pitch[i])
					end
				end
				t.truthy(dip < -0.1, `{variant}: the nose dips {dip} rad`)
				t.truthy(rebound > 0.01, `and comes back past level ({rebound})`)
				t.truthy(raised < -0.5, `the tail is thrown up {raised} rad`)
				t.near(pitch[#stop], 0, 5e-3, "and it stands level in the end")

				-- the leap: Space at 1.7 s, down again at about 2.55 s
				local leap = Path.simulate(variant, "leap").frames
				local up, down, sink = 0, 0, 0
				for _, f in leap do
					local rx = f.layers.Root[1]
					if f.mode == "air" and f.t > 1.7 then
						up, down = math.max(up, rx), math.min(down, rx)
					elseif f.t > 2.5 then
						sink = math.min(sink, f.layers.Root[5])
					end
				end
				t.truthy(up > 0.15 and down < -0.15, `{variant}: nose up {up} rising, nose down {down} falling`)
				t.truthy(sink < -0.05, `the landing sinks it {sink} studs`)
			end
		end
	)
end
