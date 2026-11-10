--!strict
-- tests/isolated/bowling_client.luau: cases for tests/unit/bowling_client.spec.luau, run in their own Lune
-- process (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Client/Minigames/BowlingClient driven by fake input and fake frames: a turn from the server's "your turn"
-- to the camera handed back. Aim with the keys and the mouse, the meter, one "release" sent; the throw
-- camera follows the ball, cuts once to the pins and is released when the frame is over; a refused throw and
-- a throw the server never answers both hand the controls back with words; typing in chat moves nothing; a
-- click on a button is not a throw; the second ball keeps the line; stop() cleans up.
-- Interface: return function(t) (the spec shape)
local AimModel = require("@shared/Minigames/Bowling/AimModel")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local PinModel = require("@shared/Minigames/Bowling/PinModel")
local RollScript = require("@shared/Minigames/Bowling/RollScript")
local Shots = require("@shared/Minigames/Bowling/Shots")
local BowlingClient = require("@client/Minigames/BowlingClient")
local FakeEngine = require("@tests/lib/FakeEngine")
local roblox = require("@lune/roblox")

local PLACE: AlleyLayout.Place = { x = 10, z = 20, floorY = 4, yaw = 0.2 }
local Key = roblox.Enum.KeyCode
local Kind = roblox.Enum.UserInputType

type Rig = {
	bowler: any,
	sent: { any },
	shots: { any },
	released: number,
	controls: { boolean },
	toasts: { string },
	ui: { [string]: any },
	now: number,
}

local function rig(): Rig
	local r: Rig = { bowler = nil, sent = {}, shots = {}, released = 0, controls = {}, toasts = {}, ui = {}, now = 50 }
	local ui = {
		touched = nil :: any,
		meterValue = nil :: number?,
		meterSweet = nil :: any,
		meterText = nil :: string?,
		hookNotch = nil :: number?,
		clockLeft = nil :: number?,
		clockWarning = nil :: string?,
		statusText = "",
	}
	function ui.touch(_self: any, list: any, down: any, up: any)
		ui.touched = { list = list, down = down, up = up }
	end
	function ui.meter(_self: any, value: number?, sweet: any, text: string?)
		ui.meterValue, ui.meterSweet, ui.meterText = value, sweet, text
	end
	function ui.hook(_self: any, notch: number?)
		ui.hookNotch = notch
	end
	function ui.clock(_self: any, left: number?, warning: string?)
		ui.clockLeft, ui.clockWarning = left, warning
	end
	function ui.status(_self: any, text: string)
		ui.statusText = text
	end
	r.ui = ui
	BowlingClient.clock = function()
		return r.now
	end
	r.bowler = BowlingClient.new({
		lane = 2,
		place = PLACE,
		ui = ui,
		send = function(verb: string, args: { any })
			table.insert(r.sent, { verb = verb, args = args })
		end,
		camera = function(cf: any, fov: number, cut: boolean?)
			table.insert(r.shots, { cf = cf, fov = fov, cut = cut == true })
		end,
		releaseCamera = function()
			r.released += 1
		end,
		controls = function(on: boolean)
			table.insert(r.controls, on)
		end,
		toast = function(text: string)
			table.insert(r.toasts, text)
		end,
		body = function(): any
			return nil
		end,
	})
	return r
end

local function frames(r: Rig, seconds: number)
	local n = math.max(1, math.floor(seconds * 60 + 0.5))
	for _ = 1, n do
		r.now += 1 / 60
		FakeEngine.renderStep(1 / 60)
	end
end

local function state(r: Rig, turn: number, ready: boolean, phase: string?)
	r.bowler:onState({
		you = 1,
		ready = ready,
		view = {
			phase = phase or "playing",
			turn = turn,
			turnLeft = 60,
			seats = { { name = "Ann" }, { name = "Bob" } },
		},
	})
end

local function key(code: any, down: boolean, processed: boolean?)
	FakeEngine.input(if down then "began" else "ended", { KeyCode = code, UserInputType = Kind.Keyboard }, processed)
end

local function dots(): number
	local n = 0
	for _, c in FakeEngine.workspace().CurrentCamera:GetChildren() do
		if c.Name == "AimDot" then
			n += 1
		end
	end
	return n
end

return function(t)
	t.test(
		"a turn: your controls are taken, you aim, the meter runs, one release goes out with what you aimed",
		function()
			FakeEngine.with(function()
				local r = rig()
				t.eq(#r.ui.touched.list, 7, "touch gets step, aim, hook and bowl buttons")
				frames(r, 0.2)
				t.eq(#r.shots, 0, "not your turn: your own camera is left alone")
				state(r, 1, true)
				t.deepEq(r.controls, { false })
				frames(r, 0.2)
				t.truthy(string.find(r.ui.statusText, "Your turn", 1, true) ~= nil)
				t.truthy(string.find(r.ui.statusText, "Z/X", 1, true) ~= nil)
				t.truthy(#r.shots > 5, "the aiming shot is up")
				t.truthy(dots() >= 12, `{dots()} aim dots on the lane`)
				t.eq(r.ui.hookNotch, 0)
				t.truthy(r.ui.clockLeft ~= nil and r.ui.clockLeft <= 60 and r.ui.clockLeft > 59)
				t.eq(r.ui.clockWarning, nil)
				-- step right, aim left, hook
				key(Key.D, true, true) -- (the control module marks WASD processed: a key still counts)
				frames(r, 0.5)
				key(Key.D, false)
				t.near(r.bowler.aim.offset, 0.5 * AimModel.STEP_RATE, 0.02)
				key(Key.Left, true)
				frames(r, 0.5)
				key(Key.Left, false)
				t.near(r.bowler.aim.angle, -0.5 * AimModel.AIM_RATE, 0.002)
				key(Key.Z, true)
				key(Key.Z, false)
				frames(r, 0.05)
				t.eq(r.ui.hookNotch, -1)
				FakeEngine.input("changed", { UserInputType = Kind.MouseWheel, Position = roblox.Vector3.new(0, 0, 1) })
				frames(r, 0.05)
				t.eq(r.ui.hookNotch, 0, "the wheel turns the hook back")
				-- the mouse moves across the screen: the angle follows it
				FakeEngine.uis().mouse = roblox.Vector2.new(1920 * 0.75, 500)
				frames(r, 0.05)
				t.near(r.bowler.aim.angle, AimModel.MAX_ANGLE * 0.5, 1e-6)
				-- hold Space: the meter runs with its green band and its words; let go at 0.7
				key(Key.Space, true, true)
				frames(r, AimModel.POWER_PERIOD * 0.7)
				t.near(r.ui.meterValue :: number, 0.7, 0.02)
				t.deepEq(r.ui.meterSweet, AimModel.SWEET)
				t.truthy(string.find(r.ui.meterText :: string, "green", 1, true) ~= nil)
				key(Key.Space, false)
				t.eq(#r.sent, 1)
				t.eq(r.sent[1].verb, "release")
				t.near(r.sent[1].args[1], r.bowler.aim.offset, 1e-9)
				t.near(r.sent[1].args[2], AimModel.MAX_ANGLE * 0.5, 1e-6)
				t.near(r.sent[1].args[3], 0.7, 0.02)
				t.eq(r.sent[1].args[4], 0)
				-- nothing more goes out while that one is unanswered
				key(Key.Space, true)
				frames(r, 0.2)
				key(Key.Space, false)
				t.eq(#r.sent, 1)
				r.bowler:stop()
				BowlingClient.clock = os.clock
			end)
		end
	)

	t.test(
		"the throw: the camera rides behind the ball, cuts once to the pins, and is handed back when the frame is over",
		function()
			FakeEngine.with(function()
				local r = rig()
				state(r, 1, true)
				frames(r, 0.1)
				key(Key.Space, true)
				frames(r, 1.0)
				key(Key.Space, false)
				t.eq(#r.sent, 1)
				local script =
					RollScript.build({ offset = 0.165, angle = 0, power = 0.7, spin = 0 }, PinModel.fullRack(), 5)
				t.eq(script.down, 10, "(a strike, so the frame ends with this ball)")
				r.shots = {}
				r.bowler:onRoll({ seat = 1 }, script)
				t.eq(dots(), 0, "the aim line goes away")
				state(r, 1, false) -- the lane is busy
				frames(r, Shots.cutTime(script) - 0.1)
				local follow = #r.shots
				t.truthy(follow > 30)
				local cutsBefore = 0
				for _, s in r.shots do
					if s.cut then
						cutsBefore += 1
					end
				end
				-- (the first roll frame is a change of shot from aiming: that one cut is right)
				t.truthy(cutsBefore <= 1)
				frames(r, 0.3)
				local cuts = 0
				for i = follow + 1, #r.shots do
					if r.shots[i].cut then
						cuts += 1
					end
				end
				t.eq(cuts, 1, "one cut to the pins")
				-- the server counts the strike and the turn passes while the pin shot is still up
				state(r, 2, false)
				t.eq(r.released, 0, "the pin shot holds through the pinfall")
				frames(r, Shots.doneTime(script) - Shots.cutTime(script))
				t.eq(r.released, 1, "then your own camera comes back")
				t.deepEq(r.controls, { false, true }, "and your legs")
				local n = #r.shots
				frames(r, 1)
				t.eq(#r.shots, n, "nothing writes the camera after the hand-back")
				t.eq(r.released, 1)
				r.bowler:stop()
				BowlingClient.clock = os.clock
			end)
		end
	)

	t.test("the second ball: the pinsetter shot between balls, then aiming again on the same line", function()
		FakeEngine.with(function()
			local r = rig()
			state(r, 1, true)
			key(Key.A, true)
			frames(r, 0.4)
			key(Key.A, false)
			local offset = r.bowler.aim.offset
			key(Key.Space, true)
			frames(r, 1.0)
			key(Key.Space, false)
			local script = RollScript.build({ offset = 0.5, angle = 0, power = 0.7, spin = 0 }, PinModel.fullRack(), 4)
			t.truthy(script.down < 10)
			r.bowler:onRoll({ seat = 1 }, script)
			state(r, 1, false)
			frames(r, Shots.doneTime(script) + 0.2)
			t.eq(r.released, 0, "still your frame: the camera stays with the lane")
			r.shots = {}
			frames(r, 0.2)
			t.truthy(#r.shots > 5, "the between-balls shot")
			-- the lane is set: aim again, the line kept
			state(r, 1, true)
			frames(r, 0.2)
			t.truthy(AimModel.canAim(r.bowler.aim))
			t.near(r.bowler.aim.offset, offset, 1e-9)
			t.truthy(dots() >= 12)
			key(Key.Space, true)
			frames(r, 0.9)
			key(Key.Space, false)
			t.eq(#r.sent, 2)
			r.bowler:stop()
			BowlingClient.clock = os.clock
		end)
	end)

	t.test("a refused throw, and one the server never answers, both hand the controls straight back", function()
		FakeEngine.with(function()
			local r = rig()
			state(r, 1, true)
			key(Key.Space, true)
			frames(r, 1.0)
			key(Key.Space, false)
			t.eq(#r.sent, 1)
			r.bowler:onRefused({ verb = "release", text = "Wait for the pinsetter and the ball" })
			t.truthy(AimModel.canAim(r.bowler.aim))
			key(Key.Space, true)
			frames(r, 1.0)
			key(Key.Space, false)
			t.eq(#r.sent, 2, "the next hold-and-release throws again")
			-- this one is never answered (dropped by a rate limit, a lost packet)
			frames(r, BowlingClient.SEND_TIMEOUT + 0.2)
			t.truthy(AimModel.canAim(r.bowler.aim))
			t.eq(#r.toasts, 1)
			t.truthy(string.find(r.toasts[1], "did not reach", 1, true) ~= nil)
			key(Key.Space, true)
			frames(r, 1.0)
			key(Key.Space, false)
			t.eq(#r.sent, 3)
			-- a refusal of something else (Start now in mid-game) does not disturb a throw on its way
			r.bowler:onRefused({ verb = "start", text = "already playing" })
			t.eq(r.bowler.aim.phase, "sent")
			r.bowler:stop()
			BowlingClient.clock = os.clock
		end)
	end)

	t.test(
		"typing in chat moves nothing; a click on a button is not a throw; no throw when it is not your ball",
		function()
			FakeEngine.with(function()
				local r = rig()
				state(r, 1, true)
				frames(r, 0.1)
				FakeEngine.uis().focused = {} -- the chat bar has focus
				key(Key.D, true, true)
				key(Key.Z, true, true)
				key(Key.Space, true, true)
				frames(r, 1.0)
				key(Key.Space, false, true)
				t.eq(r.bowler.aim.offset, 0)
				t.eq(r.bowler.aim.notch, 0)
				t.eq(#r.sent, 0)
				FakeEngine.uis().focused = nil
				key(Key.D, false)
				-- a click the interface took (the Leave button)
				FakeEngine.input("began", { UserInputType = Kind.MouseButton1 }, true)
				frames(r, 0.5)
				FakeEngine.input("ended", { UserInputType = Kind.MouseButton1 }, true)
				t.eq(#r.sent, 0)
				-- a click on the lane is a throw
				FakeEngine.input("began", { UserInputType = Kind.MouseButton1 }, false)
				frames(r, 0.9)
				FakeEngine.input("ended", { UserInputType = Kind.MouseButton1 }, false)
				t.eq(#r.sent, 1)
				-- Bob's turn: Space does nothing here, the status line says whose go it is
				local r2 = rig()
				state(r2, 2, true)
				key(Key.Space, true)
				frames(r2, 0.5)
				key(Key.Space, false)
				t.eq(#r2.sent, 0)
				t.truthy(string.find(r2.ui.statusText, "Bob is bowling", 1, true) ~= nil)
				t.eq(#r2.shots, 0)
				t.eq(#r2.controls, 0, "a waiting bowler keeps their own legs and camera")
				r.bowler:stop()
				r2.bowler:stop()
				BowlingClient.clock = os.clock
			end)
		end
	)

	t.test("the turn clock counts down on screen and warns before the skip; stop() cleans up", function()
		FakeEngine.with(function()
			local r = rig()
			state(r, 1, true)
			frames(r, 0.5)
			t.near(r.ui.clockLeft :: number, 59.5, 0.05)
			r.bowler:onState({
				you = 1,
				ready = true,
				view = { phase = "playing", turn = 1, turnLeft = 12, seats = { { name = "Ann" } } },
			})
			frames(r, 1.5)
			t.near(r.ui.clockLeft :: number, 10.5, 0.05)
			t.eq(r.ui.clockWarning, "Bowl within 11 seconds or your turn is skipped")
			t.truthy(dots() > 0)
			r.bowler:stop()
			t.eq(dots(), 0)
			t.eq(r.ui.meterValue, nil)
			t.eq(r.ui.hookNotch, nil)
			t.eq(r.ui.clockLeft, nil)
			local shots = #r.shots
			frames(r, 0.5)
			t.eq(#r.shots, shots, "nothing runs after stop")
			-- touch buttons do what the keys do
			local r2 = rig()
			state(r2, 1, true)
			r2.ui.touched.down("hookR")
			r2.ui.touched.down("right")
			frames(r2, 0.5)
			r2.ui.touched.up("right")
			t.eq(r2.bowler.aim.notch, 1)
			t.truthy(r2.bowler.aim.offset > 0.4)
			r2.ui.touched.down("bowl")
			frames(r2, 1.0)
			r2.ui.touched.up("bowl")
			t.eq(#r2.sent, 1)
			t.eq(r2.sent[1].args[4], 0.5)
			r2.bowler:stop()
			BowlingClient.clock = os.clock
		end)
	end)
end
