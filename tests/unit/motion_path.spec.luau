--!strict
-- tests/unit/motion_path.spec.luau
-- The offline motion preview (tools/review/motion/Path, written out by tools/review/motion_path.luau):
-- scripted takes of the squirrel through the game's own motor, drawn pose, camera and animation rules.
-- What is pinned: the stand-in tracks behave as AnimationTracks do under AnimationDriver.heroTracks (a
-- change of clip crosses over, a loop wraps, a one-shot holds its end); every take runs, is the same every
-- time, and shows what its title says; the camera stands where CameraRig's orbit starts, behind the body;
-- the clip and its rate are AnimationDriver's own answers; the layers are AnimationDriver.heroLayers'
-- (none on the squirrel, the twitches on the Spicy Rodent).

local AnimationDriver = require("@client/Animation/AnimationDriver")
local CameraRig = require("@client/Camera/CameraRig")
local HeroAssets = require("@shared/Actors/HeroAssets")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Path = require("@tests/../tools/review/motion/Path")

local H = AnimationDriver.HERO
local CLIPS = HeroAssets.CLIPS.squirrel

return function(t: any)
	local dt = 1 / Path.FPS

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
	end)

	t.test("stand-in tracks: a one-shot is frozen on its last pose, and starts again from its beginning", function()
		local p = Path.newTracks(CLIPS)
		p:prime("Run")
		for _ = 1, 120 do
			p.current = AnimationDriver.heroTracks(p.tracks, p.current, "Leap", p:track("Leap"), false, 1)
			p:advance(dt)
		end
		local leap = p:track("Leap")
		t.eq(leap.IsPlaying, true, "held, not ended")
		t.eq(leap.Speed, 0)
		t.truthy(leap.TimePosition >= CLIPS.Leap.length - H.holdEnd and leap.TimePosition < CLIPS.Leap.length)
		t.eq(leap.weight, 1)
		-- back to the run and into the air again
		p.current = AnimationDriver.heroTracks(p.tracks, p.current, "Run", p:track("Run"), true, 1)
		p:advance(dt)
		p.current = AnimationDriver.heroTracks(p.tracks, p.current, "Leap", p:track("Leap"), false, 1)
		t.eq(leap.TimePosition, 0)
		t.eq(leap.Speed, 1)
		-- left alone at full speed a one-shot ends and fades away
		local q = Path.newTracks(CLIPS)
		q:track("Leap"):Play(0)
		for _ = 1, 80 do
			q:advance(dt)
		end
		t.eq(q:track("Leap").IsPlaying, false)
		t.eq(q:track("Leap").weight, 0)
	end)

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
				t.eq(next(f.layers), nil, "nothing is layered on the squirrel")
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
		t.eq(final.clip, "Idle")
		t.truthy(final.speed < 0.01 and final.groundSpeed < 0.01)
		t.eq(#final.tracks, 1)
	end)

	t.test("leap: a hop and a leap, each in the air on the Leap clip, each landing", function()
		local take = Path.simulate("squirrel", "leap")
		local events = {}
		local highest, airFrames = 0, 0
		for _, f in take.frames do
			for _, e in f.events do
				table.insert(events, e)
			end
			highest = math.max(highest, f.pos.y)
			if f.mode == "air" then
				airFrames += 1
				t.eq(f.clip, "Leap")
				t.truthy(f.clipTime <= CLIPS.Leap.length)
			end
		end
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
		-- the drawn feet point stands off the bark by a little, on the side it came from (+Z)
		local barkR = math.max(trunk.minRadius, trunk.radius * (1 - trunk.taper * last.motor.railT))
		local off = last.pos.z - trunk.z - barkR
		t.truthy(off > 0.1 and off < 0.6, `{off} studs off the bark`)
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
		local seed = AnimationDriver.creepSeed(Path.BODY_NAME)
		for _, i in { 0, 37, 180 } do
			local frame = rodent.frames[i + 1]
			local want = AnimationDriver.heroLayers("rodent", Path.SERVER_TIME + i * dt, seed)
			local n = 0
			for bone, r in want do
				n += 1
				local got = frame.layers[bone]
				t.truthy(got ~= nil, `layer on {bone}`)
				for k = 1, 3 do
					t.near(got[k], r[k], 1e-5)
				end
			end
			local m = 0
			for _ in frame.layers do
				m += 1
			end
			t.eq(m, n)
			t.truthy(n >= 5, "head, jaw, ears and spine at least")
		end
		-- the body under the layers moves exactly as the squirrel's does
		local squirrel = Path.simulate("squirrel", "walk")
		t.deepEq(rodent.frames[100].pos, squirrel.frames[100].pos)
		t.eq(rodent.frames[100].clipTime, squirrel.frames[100].clipTime)
	end)
end
