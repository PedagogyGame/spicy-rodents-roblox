--!strict
-- tests/isolated/bowling_playback.luau: cases for tests/unit/bowling_playback.spec.luau, run in their own
-- Lune process (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Client/Minigames/BowlingPlayback against the server's lane on the same fake parts: the client draws a throw
-- from the server's script and must finish exactly where the server has the pins and the ball (otherwise they
-- would pop when playback hands back); every pin of the rack is written every frame (so the server's coarser
-- copy never shows through); pins in the pit are hidden locally and unhidden at the end; cues fire in order;
-- a cut-short throw restores the rack; a lane that is not there plays nothing and binds nothing.
-- Interface: return function(t) (the spec shape)
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local PartPose = require("@shared/Minigames/Bowling/PartPose")
local PinModel = require("@shared/Minigames/Bowling/PinModel")
local RollScript = require("@shared/Minigames/Bowling/RollScript")
local LaneCycle = require("@shared/Minigames/Bowling/LaneCycle")
local BowlingLane = require("@server/Minigames/BowlingLane")
local BowlingPlayback = require("@client/Minigames/BowlingPlayback")
local FakeEngine = require("@tests/lib/FakeEngine")
local roblox = require("@lune/roblox")

local PLACE: AlleyLayout.Place = { x = -60, z = 210, floorY = 6, yaw = -1.1 }
local LANE = 4

local function at(x: number, y: number, z: number): any
	return roblox.CFrame.new(x, y, z)
end

-- Workspace.Attractions.BowlingAlley.Lanes.Lane4 as the bake lays it out; the server's lane stamps it
local function buildLane(): (any, any)
	local attractions = FakeEngine.new("Folder", "Attractions")
	attractions.Parent = FakeEngine.workspace()
	local alley = FakeEngine.new("Model", "BowlingAlley")
	alley.Parent = attractions
	local lanes = FakeEngine.new("Folder", "Lanes")
	lanes.Parent = alley
	local lm = FakeEngine.model(`Lane{LANE}`, at(0, 0, 0), lanes)
	local rx, ry, rd = AlleyLayout.rackSlot(LANE)
	FakeEngine.part("Ball", at(AlleyLayout.toWorld(PLACE, rx, ry, rd)), lm)
	local pins = FakeEngine.new("Folder", "Pins")
	pins.Parent = lm
	for n = 1, 10 do
		local px, pd = AlleyLayout.pinLocal(LANE, n)
		local home = at(AlleyLayout.toWorld(PLACE, px, 0.45, pd)) * roblox.CFrame.Angles(0, 0.4 * n, 0)
		local pm = FakeEngine.model(`Pin{n}`, home, pins)
		FakeEngine.part("Body", home, pm)
	end
	local server = BowlingLane.new({ lane = LANE, model = lm, place = PLACE })
	return lm, server
end

local function snapshot(lm: any): { any }
	local out = { lm:FindFirstChild("Ball").CFrame }
	for n = 1, 10 do
		out[n + 1] = lm:FindFirstChild("Pins"):FindFirstChild(`Pin{n}`):GetPivot()
	end
	return out
end

local function same(a: any, b: any): number
	local d = a:Inverse() * b
	return d.Position.Magnitude + (d.LookVector - roblox.Vector3.new(0, 0, -1)).Magnitude
end

return function(t)
	t.test("the client finishes a throw exactly where the server has it: no pop when playback hands back", function()
		FakeEngine.with(function()
			local lm, server = buildLane()
			local now = 100
			BowlingPlayback.clock = function()
				return now
			end
			for seed = 1, 6 do
				local params = {
					offset = 0.165 + (seed % 3 - 1) * 0.25,
					angle = 0,
					power = 0.7,
					spin = if seed % 2 == 0 then -0.5 else 0,
				}
				-- the server plays it to the count and its poses are taken
				local ok, why, script = server:release(params, 1, seed)
				t.truthy(ok, why)
				while server.state ~= "counted" do
					server:step(0.05)
				end
				local serverEnd = snapshot(lm)
				server:takeResult()
				server:reset(true)
				local home = snapshot(lm)
				-- the client plays the same script at 60 frames a second on the same kind of parts
				local wire = RollScript.check(script)
				t.truthy(wire ~= nil)
				local cues: { string } = {}
				t.truthy(BowlingPlayback.play(PLACE, LANE, wire, function(name: string, volume: number)
					table.insert(cues, name)
					t.truthy(volume > 0 and volume <= 1)
				end))
				t.eq(FakeEngine.bound(), 1, "one render step bound")
				t.truthy(BowlingPlayback.playing(LANE))
				local pin1 = lm:FindFirstChild("Pins"):FindFirstChild("Pin1")
				local writes0 = rawget(pin1, "_pivots") or 0
				local frames, sawLane, sawHidden = 0, false, false
				local pitPin: any = nil
				for n = 1, 10 do
					if (script.deck :: any).pitT[n] >= 0 then
						pitPin = lm:FindFirstChild("Pins"):FindFirstChild(`Pin{n}`)
					end
				end
				while BowlingPlayback.playing(LANE) and frames < 2000 do
					now += 1 / 60
					frames += 1
					FakeEngine.renderStep(1 / 60)
					local tt = BowlingPlayback.now(LANE)
					if tt and tt > 0.5 and tt < 1.5 then
						local ball = lm:FindFirstChild("Ball").CFrame
						local _, _, d = AlleyLayout.toLocal(PLACE, ball.X, ball.Y, ball.Z)
						sawLane = sawLane or (d > 5 and d < 50)
					end
					if pitPin and pitPin:FindFirstChild("Body").LocalTransparencyModifier == 1 then
						sawHidden = true
					end
				end
				t.truthy(sawLane, "the ball was drawn running down the lane")
				t.near(frames / 60, script.tEnd + BowlingPlayback.TAIL, 0.05, "it plays for the length of the script")
				t.eq(FakeEngine.bound(), 0, "and unbinds when nothing is playing")
				t.eq(BowlingPlayback.now(LANE), nil)
				-- every pin of the rack was written every frame (the server's copy can never show through)
				t.truthy((rawget(pin1, "_pivots") or 0) - writes0 >= frames - 1)
				-- the final poses are the server's
				local clientEnd = snapshot(lm)
				for i = 1, 11 do
					t.truthy(
						same(serverEnd[i], clientEnd[i]) < 2e-3,
						`seed {seed}: part {i} differs by {same(serverEnd[i], clientEnd[i])}`
					)
				end
				if script.down > 0 then
					t.truthy(same(home[2], clientEnd[2]) > 0.1 or script.standing[1], "and the pins really moved")
				end
				-- pins that went into the pit were hidden on this screen, and unhidden once it was over
				if pitPin then
					t.truthy(sawHidden, "a pin in the pit goes out of sight")
					t.eq(pitPin:FindFirstChild("Body").LocalTransparencyModifier, 0)
				end
				-- cues in the script's order
				local want = RollScript.cues(script)
				t.eq(#cues, #want)
				for i, c in want do
					t.eq(cues[i], c[2])
				end
				server:reset(true)
				BowlingPlayback.stop(LANE, PLACE, PinModel.fullRack())
			end
			BowlingPlayback.clock = os.clock
		end)
	end)

	t.test("a throw cut short: playback stops and the lane shows the rack the server has", function()
		FakeEngine.with(function()
			local lm, server = buildLane()
			local now = 5
			BowlingPlayback.clock = function()
				return now
			end
			local home = snapshot(lm)
			local script =
				RollScript.build({ offset = 0.165, angle = 0, power = 0.7, spin = 0 }, PinModel.fullRack(), 3)
			t.truthy(BowlingPlayback.play(PLACE, LANE, script))
			for _ = 1, 150 do
				now += 1 / 60
				FakeEngine.renderStep(1 / 60)
			end
			local mid = snapshot(lm)
			t.truthy(same(home[1], mid[1]) > 1, "the ball is away")
			t.truthy(same(home[2], mid[2]) > 0.1, "the head pin is down")
			BowlingPlayback.stop(LANE, PLACE, PinModel.fullRack())
			t.falsy(BowlingPlayback.playing(LANE))
			local after = snapshot(lm)
			for i = 1, 11 do
				t.truthy(same(home[i], after[i]) < 1e-3, `part {i} is back`)
			end
			for n = 1, 10 do
				t.eq(
					lm:FindFirstChild("Pins"):FindFirstChild(`Pin{n}`):FindFirstChild("Body").LocalTransparencyModifier
						or 0,
					0
				)
			end
			FakeEngine.renderStep(1 / 60)
			t.eq(FakeEngine.bound(), 0)
			-- a second throw replaces one still playing rather than fighting it
			t.truthy(BowlingPlayback.play(PLACE, LANE, script))
			now += 0.5
			FakeEngine.renderStep(1 / 60)
			t.truthy(BowlingPlayback.play(PLACE, LANE, script))
			t.near(BowlingPlayback.now(LANE) :: number, 0, 1e-9)
			t.eq(FakeEngine.bound(), 1)
			BowlingPlayback.stop(LANE)
			t.eq(server:standingCount(), 10)
			BowlingPlayback.clock = os.clock
		end)
	end)

	t.test("a lane that has not streamed in plays nothing, binds nothing and throws nothing", function()
		FakeEngine.with(function()
			local script = RollScript.build({ offset = 0, angle = 0, power = 0.7, spin = 0 }, PinModel.fullRack(), 1)
			t.falsy(BowlingPlayback.play(PLACE, LANE, script))
			t.eq(FakeEngine.bound(), 0)
			t.falsy(BowlingPlayback.playing(LANE))
			BowlingPlayback.stop(LANE, PLACE, PinModel.fullRack())
			t.falsy(BowlingPlayback.play(nil, LANE, script))
			-- pins without the server's stamp (the server has not started the alley) are left alone
			local attractions = FakeEngine.new("Folder", "Attractions")
			attractions.Parent = FakeEngine.workspace()
			local alley = FakeEngine.new("Model", "BowlingAlley")
			alley.Parent = attractions
			local lanes = FakeEngine.new("Folder", "Lanes")
			lanes.Parent = alley
			local lm = FakeEngine.model(`Lane{LANE}`, at(0, 0, 0), lanes)
			local pins = FakeEngine.new("Folder", "Pins")
			pins.Parent = lm
			FakeEngine.model("Pin1", at(1, 2, 3), pins)
			t.falsy(BowlingPlayback.play(PLACE, LANE, script), "no ball and no stamped pins: nothing to play")
		end)
	end)

	t.test("the tip-over axis is level and square to the way the pin falls", function()
		for _, yaw in { 0, 0.7, -2.1, math.pi } do
			local ax, az = PartPose.fallAxis(PLACE, yaw)
			local fx, fz = AlleyLayout.dirToWorld(PLACE, math.sin(yaw), math.cos(yaw))
			t.near(ax * fx + az * fz, 0, 1e-9, "square to the fall")
			t.near(ax * ax + az * az, 1, 1e-9, "a unit axis")
			-- up crossed with the fall direction (so tipping about it by a positive angle falls that way)
			t.near(ax, fz, 1e-9)
			t.near(az, -fx, 1e-9)
		end
		-- the client lets go of the final pose after the server has counted (and written it) and before the
		-- sweep bar starts moving anything
		t.truthy(BowlingPlayback.TAIL > LaneCycle.SETTLE + 0.2, "held until the server's own copy has arrived")
		t.truthy(BowlingPlayback.TAIL < LaneCycle.SETTLE + LaneCycle.PAUSE - 0.3, "released before the pinsetter moves")
		t.eq(PartPose.HOME, "BowlHome")
		t.eq(PartPose.RACK, "BowlRack")
	end)
end
