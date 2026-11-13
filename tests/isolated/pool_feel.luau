--!strict
-- tests/isolated/pool_feel.luau: cases for tests/unit/pool_feel.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- How the cue tables feel to the one at the table, on tests/lib/MinigameRig (the real service and the real
-- client with Pool/CueController and Pool/Playback): the eye down the cue is never in your own head, the view
-- stays down the cue until the tip has met the ball and then rises (the break cuts to the top), the cue comes
-- through as you let go, the other player's aim is seen as they line up, the winning shot's replay has the
-- screen to itself, the aim keys and fingers have a fine touch, and the How-to-play card fits its panel.
-- Interface: return function(t) (the spec shape)
local Cue = require("@shared/Minigames/Pool/Cue")
local Tables = require("@shared/Minigames/Pool/Tables")
local BumperPoolClient = require("@client/Minigames/Games/BumperPool")
local CueController = require("@client/Minigames/Pool/CueController")
local PoolClient = require("@client/Minigames/Games/Pool")
local Playback = require("@client/Minigames/Pool/Playback")
local FakeEngine = require("@tests/lib/FakeEngine")
local PoolRig = require("@tests/pool/PoolRig")
local Rig = require("@tests/lib/MinigameRig")
local roblox = require("@lune/roblox")

local ID = "pool_1"
local Key = roblox.Enum.KeyCode
local TABLE = Tables.eightBall()
local HEAD = 1.5 -- a person's head above their root part, and its radius
local HEAD_R = 0.6

local function opts(extra: { [string]: any }?): { [string]: any }
	local o: { [string]: any } = { furnish = PoolRig.furnish, stand = PoolRig.stand(ID) }
	for k, v in extra or {} do
		o[k] = v
	end
	return o
end

-- My body's head, as this screen draws it: a part of the body that is seen (the rig's body is only its root
-- part; this one is added, seen, before the game opens).
local function headOf(w: any): any
	local head = w.body:FindFirstChild("Head")
	if head == nil then
		head = FakeEngine.part("Head", w.body.PrimaryPart.CFrame, w.body)
		head.LocalTransparencyModifier = 0
	end
	return head
end

-- Ann at pool table 1 against Bob (a stub), and her controller.
local function twoPlayers(w: any): (any, any)
	headOf(w)
	local bob = Rig.stub("Bob")
	Rig.press(w, ID)
	Rig.run(w, 0.3)
	assert(w.svc:join(bob, ID))
	Rig.click(w, "Start now")
	Rig.run(w, 0.5)
	return PoolRig.controller(ID), bob
end

local function layout(w: any, spots: { any }, fields: { [string]: any })
	local ok, why = w.svc:debug(ID, "layout", spots, fields)
	assert(ok, why)
	Rig.run(w, 0.5)
end

local function bodyHidden(w: any): boolean
	return headOf(w).LocalTransparencyModifier >= 1
end

local function camPos(): any
	return workspace.CurrentCamera.CFrame.Position
end

-- How many lines a card's text takes in a panel this many characters wide (word-wrapped).
local function wrapped(lines: { string }, width: number): number
	local n = 0
	for _, line in lines do
		local len, rows = 0, 1
		for word in string.gmatch(line, "%S+") do
			local add = if len == 0 then #word else len + 1 + #word
			if add > width and len > 0 then
				rows += 1
				len = #word
			else
				len = add
			end
		end
		n += rows
	end
	return n
end

return function(t)
	t.test("the eye down the cue is never in my own head: a ball half a stud off the rail behind the shot", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			local c = twoPlayers(w)
			local r = TABLE.ballR
			layout(w, {
				{ id = 0, x = 0.4, z = -TABLE.halfL + r + 0.5 },
				{ id = 3, x = -1.2, z = 2 },
				{ id = 12, x = 1.1, z = 3 },
			}, { broken = true, inHand = "none", seat = 1 })
			t.eq(c.phase, "aim")
			-- straight up the table: the cushion behind the ball, I stand at the rail behind it
			c.angle = 0
			Rig.run(w, 1)
			local root = w.body.PrimaryPart.Position
			local head = root + roblox.Vector3.new(0, HEAD, 0)
			local eye = camPos()
			t.truthy((eye - head).Magnitude > HEAD_R, `the eye is {(eye - head).Magnitude} from my head's middle`)
			local d = c:_dir(0)
			local ball = c:_point(0.4, r, -TABLE.halfL + r + 0.5)
			local eyeBack = (ball - eye):Dot(d)
			local bodyBack = (ball - root):Dot(d)
			t.truthy(
				eyeBack <= bodyBack - CueController.EYE_CLEAR + 0.01,
				`eye {eyeBack} behind the ball, me {bodyBack}`
			)
			-- I stand to the left of the line, not on it
			local right = roblox.Vector3.new(-d.Z, 0, d.X)
			t.truthy((root - ball):Dot(right) < -0.5, "I stand to the left of the line")
			t.truthy(bodyHidden(w), "my own body is hidden in the cue view")
			-- the top view shows me again; back down the cue hides me
			Rig.key(Key.T, true)
			Rig.key(Key.T, false)
			Rig.run(w, 0.2)
			t.falsy(bodyHidden(w), "seen from the top")
			Rig.key(Key.T, true)
			Rig.key(Key.T, false)
			Rig.run(w, 0.2)
			t.truthy(bodyHidden(w))
			-- up from the shot (V): my body is mine to see again
			Rig.key(Key.V, true)
			Rig.key(Key.V, false)
			Rig.run(w, 0.2)
			t.eq(next(c.bodyHidden), nil, "walking: nothing of my body is hidden by the game")
		end, opts())
	end)

	t.test("the cue comes through as I let go; the view stays down the cue past the contact, then rises", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			local c = twoPlayers(w)
			layout(w, {
				{ id = 0, x = 0, z = -1.5 },
				{ id = 3, x = 0.1, z = 1.2 },
				{ id = 12, x = -1.4, z = 3 },
			}, { broken = true, inHand = "none", seat = 1 })
			t.eq(c.phase, "aim")
			c.angle = Cue.angleOf(0.1, 2.7)
			Rig.run(w, 0.6)
			-- pull the bar and let go
			local sx, sy, sw, sh = c:strip()
			FakeEngine.uis().mouse = roblox.Vector2.new(sx + sw / 2, sy + 4)
			Rig.mouse(true)
			Rig.frame(w)
			FakeEngine.uis().mouse = roblox.Vector2.new(sx + sw / 2, sy + 4 + 0.6 * sh)
			FakeEngine.input("changed", { UserInputType = roblox.Enum.UserInputType.MouseMovement })
			Rig.frame(w)
			local s = c.byId[0]
			local ballAt = c:_point(s.x, TABLE.ballR, s.z)
			local tipBack = (c.stick.tip.CFrame.Position - ballAt).Magnitude
			Rig.mouse(false)
			t.eq(c.phase, "sent")
			local from = assert(c.watchFrom, "the view the rise starts from")
			-- the stroke runs at once on my screen: the tip closes on the ball every frame, and the balls start as
			-- it meets the ball (the table's answer comes back within the stroke on this line)
			local last = tipBack
			local frames = 0
			local released = c.t
			while (Playback.now(ID) or -1) < 0 and frames < 40 do
				Rig.frame(w)
				frames += 1
				if (Playback.now(ID) or -1) < 0 then
					local now = (c.stick.tip.CFrame.Position - ballAt).Magnitude
					t.truthy(now <= last + 1e-6, "the cue only comes forward")
					last = now
					t.truthy(
						(camPos() - from.Position).Magnitude < 1e-3,
						"the view is down the cue while it comes through"
					)
				end
			end
			t.truthy(last < tipBack - 0.5, `the tip came through ({tipBack} -> {last})`)
			t.near(last, TABLE.ballR, 0.05, "and met the ball")
			local took = c.t - released
			t.truthy(math.abs(took - CueController.STROKE) < 2.5 / 60, `the balls start as the tip arrives ({took} s)`)
			t.eq(c.phase, "watch")
			-- down the cue until HOLD_CUE after the contact
			while (Playback.now(ID) or 1) < CueController.HOLD_CUE - 0.02 do
				t.truthy((camPos() - from.Position).Magnitude < 1e-3, "still down the cue at the contact")
				Rig.frame(w)
			end
			-- then a rise: smooth (no frame jumps more than a step of it) and finished after RISE_CAM
			local was = camPos()
			local biggest = 0
			for _ = 1, math.ceil((CueController.RISE_CAM + 0.1) * 60) do
				Rig.frame(w)
				biggest = math.max(biggest, (camPos() - was).Magnitude)
				was = camPos()
			end
			local target = c:_watchCam()
			t.truthy((camPos() - target.Position).Magnitude < 1e-3, "the rise ends on the view of the table")
			local dist = (target.Position - from.Position).Magnitude
			t.truthy(biggest < dist * 0.06, `no frame jumps ({biggest} of {dist})`)
			t.falsy(bodyHidden(w), "my body shows once the view has risen")
			t.truthy(PoolRig.settle(w, ID))
		end, opts())
	end)

	t.test("the break cuts to the top of the table just after the crack, not before", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			local c = twoPlayers(w)
			-- the cue ball in hand behind the head string: set it down, then the break by the bar
			t.eq(c.phase, "place")
			Rig.key(Key.Space, true)
			Rig.key(Key.Space, false)
			Rig.run(w, 0.3)
			t.eq(c.phase, "aim")
			Rig.run(w, 0.5)
			local shots = Rig.count(w.got, "pool_shot")
			PoolRig.pull(w, c, 0.9)
			local from = assert(c.watchFrom, "the view the cut starts from")
			t.truthy(Rig.untilTrue(w, 2, function()
				return Rig.count(w.got, "pool_shot") > shots
			end))
			Rig.frame(w)
			t.truthy(c.watchTop, "a break is watched from the top")
			while (Playback.now(ID) or 1) < CueController.BREAK_CUT - 0.02 do
				t.truthy((camPos() - from.Position).Magnitude < 1e-3, "down the cue until the crack")
				Rig.frame(w)
			end
			Rig.run(w, 0.1)
			local top = c:_topCam()
			t.truthy((camPos() - top.Position).Magnitude < 1e-3, "then the top of the table, as a cut")
			t.truthy(PoolRig.settle(w, ID))
		end, opts())
	end)

	t.test(
		"the other player's aim: their cue swings on my screen as they line up, and gives way to the stroke",
		function()
			Rig.play(function(w)
				PoolRig.clock(w)
				local c, bob = twoPlayers(w)
				layout(w, {
					{ id = 0, x = 0, z = -1.5 },
					{ id = 3, x = 0.1, z = 1.2 },
					{ id = 12, x = -1.4, z = 3 },
				}, { broken = true, inHand = "none", seat = 2 })
				t.eq(c.phase, "off")
				t.truthy(Rig.input(w, bob, ID, "aim", { 0, 0.2, 0.3, 0, 0 }))
				Rig.run(w, 0.2)
				t.truthy(Playback.aiming(ID), "Bob's cue is drawn here")
				-- he swings it round: it follows, eased, never in one jump
				t.truthy(Rig.input(w, bob, ID, "aim", { 0, 1.0, 0.3, 0, 0 }))
				Rig.frame(w)
				Rig.frame(w)
				local tip = workspace.CurrentCamera:FindFirstChild("CueTip")
				t.truthy(tip ~= nil, "a cue is on the screen")
				Rig.run(w, 0.6)
				-- it points along 1.0 now, from behind the cue ball
				local ball = c:_point(0, TABLE.ballR, -1.5)
				local tips = {}
				for _, p in workspace.CurrentCamera:GetChildren() do
					if p.Name == "CueTip" and p.Transparency < 1 then
						table.insert(tips, p)
					end
				end
				t.eq(#tips, 1, "one cue: Bob's")
				local toward = (ball - tips[1].CFrame.Position)
				local d = c:_dir(1.0)
				t.truthy(toward.Unit:Dot(d) > 0.99, "his cue points where he aims")
				-- a turn's aims are not my inputs: nothing of mine was sent
				t.eq(Rig.count(w.sent, "aim"), 0)
				-- his strike: the aim gives way to the stroke, and my camera follows his shot (V: my own camera)
				local inputs = { { verb = "shoot", args = { 1.0, 0.4, 0, 0 } } }
				for _, input in inputs do
					assert(Rig.input(w, bob, ID, input.verb, input.args))
				end
				Rig.run(w, 0.4)
				t.falsy(Playback.aiming(ID), "the stroke has taken over")
				t.truthy(w.held, "my camera follows Bob's shot")
				Rig.key(Key.V, true)
				Rig.key(Key.V, false)
				Rig.run(w, 0.2)
				t.falsy(w.held, "V: my own camera")
				t.truthy(PoolRig.settle(w, ID))
				-- my turn: my aim goes to the server at most eight times a second, and only while it moves
				layout(w, {
					{ id = 0, x = 0, z = -1.5 },
					{ id = 3, x = 0.1, z = 1.2 },
				}, { broken = true, inHand = "none", seat = 1 })
				t.eq(c.phase, "aim")
				Rig.run(w, 0.5)
				local before = Rig.count(w.sent, "aim")
				Rig.key(Key.D, true)
				Rig.run(w, 2)
				Rig.key(Key.D, false)
				local sent = Rig.count(w.sent, "aim") - before
				t.truthy(sent >= 10 and sent <= 17, `{sent} aims in two seconds`)
				Rig.run(w, 0.5)
				local after = Rig.count(w.sent, "aim")
				Rig.run(w, 1)
				t.eq(Rig.count(w.sent, "aim"), after, "nothing is sent while the aim is still")
				t.near(Rig.last(w.sent, "aim").args[2], c.angle, 1e-9, "the last one is where the aim stopped")
				t.truthy(Rig.last(bob.events, "pool_aim"), "and Bob is sent it")
			end, opts())
		end
	)

	t.test(
		"the winning 8, again, slowly: seen from beyond its pocket, with the end card held back until it is over",
		function()
			Rig.play(function(w)
				PoolRig.clock(w)
				local c = twoPlayers(w)
				local hole = TABLE.holes[6]
				local l = math.sqrt(hole.x * hole.x + hole.z * hole.z)
				local dx, dz = -hole.x / l, -hole.z / l
				layout(w, {
					{ id = 0, x = hole.x + dx * 2.4, z = hole.z + dz * 2.4 },
					{ id = 8, x = hole.x + dx * 1.2, z = hole.z + dz * 1.2 },
					{ id = 12, x = -1.4, z = -3 },
				}, { broken = true, inHand = "none", seat = 1, group = { "solids", "stripes" } })
				t.truthy(w.svc:debug(ID, "shoot", { Cue.angleOf(-dx, -dz), 0.35, 0, -0.3, 6 }))
				t.truthy(
					Rig.untilTrue(w, 12, function()
						return Rig.last(w.got, "pool_shot", function(m: any): boolean
							return m.replay == true
						end) ~= nil
					end),
					"the winning shot is played again"
				)
				local state = PoolRig.state(w, ID)
				t.eq(state.how, "eight")
				local summary = w.gui:FindFirstChild("Summary")
				Rig.run(w, 2)
				t.truthy(c.replay ~= nil, "the replay is on")
				t.falsy(summary.Visible, "no end card over the replay")
				t.truthy(w.held, "the camera is the replay's")
				local cf = c:_replayCam()
				t.truthy((camPos() - cf.Position).Magnitude < 0.05, "from beyond the pocket")
				local hp = c:_point(hole.x, 0, hole.z)
				t.truthy((cf.Position - hp).Magnitude < 2, "close to the pocket")
				t.truthy(
					Rig.untilTrue(w, 25, function()
						return c.replay == nil
					end),
					"the replay ends"
				)
				Rig.run(w, 1.5)
				t.truthy(summary.Visible, "the end card, once it is over")
				t.falsy(w.held)
				t.truthy(string.find(Rig.screen(w), "Ann wins", 1, true), Rig.screen(w))
			end, opts())
		end
	)

	t.test("aim keys have a fine touch: a tap is a hair, held they gather speed; a finger has FINE AIM", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			local c = twoPlayers(w)
			layout(w, {
				{ id = 0, x = 0, z = -1.5 },
				{ id = 3, x = 0.1, z = 1.2 },
			}, { broken = true, inHand = "none", seat = 1 })
			local a0 = c.angle
			Rig.key(Key.D, true)
			for _ = 1, 5 do
				Rig.frame(w)
			end
			Rig.key(Key.D, false)
			Rig.frame(w)
			local tap = c.angle - a0
			t.truthy(tap > 0 and tap < 0.01, `an 80 ms tap turns {tap} rad`)
			a0 = c.angle
			Rig.key(Key.D, true)
			Rig.run(w, 1.5)
			Rig.key(Key.D, false)
			t.truthy(c.angle - a0 > 0.8, `held, it gathers speed ({c.angle - a0})`)
			-- L1 held: a tap, then a slow walk
			a0 = c.angle
			Rig.key(Key.ButtonL1, true)
			Rig.run(w, 1.3)
			Rig.key(Key.ButtonL1, false)
			local walked = a0 - c.angle
			t.truthy(walked > 0.03 and walked < 0.08, `L1 held walks the aim ({walked})`)
		end, opts())
	end)

	t.test("touch: FINE AIM or a second finger makes a drag fine; the roll of a lifting finger is not aim", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			local c = twoPlayers(w)
			layout(w, {
				{ id = 0, x = 0, z = -1.5 },
				{ id = 3, x = 0.1, z = 1.2 },
			}, { broken = true, inHand = "none", seat = 1 })
			t.eq(c.phase, "aim")
			-- a plain drag
			local a0 = c.angle
			Rig.touch("a", "began", 400, 300)
			Rig.frame(w)
			Rig.touch("a", "changed", 500, 300)
			Rig.frame(w)
			Rig.touch("a", "ended", 500, 300)
			t.near(c.angle - a0, 100 * CueController.DRAG, 1e-6)
			-- with FINE AIM held
			a0 = c.angle
			local fine = assert(Rig.button(w.gui, "FINE AIM"), Rig.screen(w))
			fine.MouseButton1Down.fire()
			Rig.touch("b", "began", 400, 300)
			Rig.frame(w)
			Rig.touch("b", "changed", 500, 300)
			Rig.frame(w)
			Rig.touch("b", "ended", 500, 300)
			fine.MouseButton1Up.fire()
			t.near(c.angle - a0, 100 * CueController.DRAG * CueController.FINE_DRAG, 1e-6)
			-- two fingers on the cloth: the drag is fine
			a0 = c.angle
			Rig.touch("c", "began", 300, 400)
			Rig.touch("d", "began", 400, 300)
			Rig.frame(w)
			Rig.touch("d", "changed", 500, 300)
			Rig.frame(w)
			Rig.touch("d", "ended", 500, 300)
			Rig.touch("c", "ended", 300, 400)
			t.near(c.angle - a0, 100 * CueController.DRAG * CueController.FINE_DRAG, 1e-6)
			-- a drag, then the finger rolls 3 pixels as it lifts: those 3 pixels do not count
			a0 = c.angle
			Rig.touch("e", "began", 400, 300)
			Rig.frame(w)
			Rig.touch("e", "changed", 480, 300)
			Rig.run(w, 0.3)
			Rig.touch("e", "changed", 483, 300)
			Rig.frame(w)
			Rig.touch("e", "ended", 483, 300)
			t.near(c.angle - a0, 80 * CueController.DRAG, 1e-6)
		end, opts({ touch = true }))
	end)

	t.test("the How-to-play card fits its panel on every device, and shows only that device's controls", function()
		Rig.play(function(_w)
			local device = CueController.device
			for _, game in { PoolClient, BumperPoolClient } do
				local help = assert(game.help, "a How-to-play card")
				local seen: { [string]: string } = {}
				for _, dev in { "keyboard", "gamepad", "touch" } do
					CueController.device = function(): string
						return dev
					end
					local lines = {}
					for _, l in help.how do
						table.insert(lines, l)
					end
					-- (the panel adds a blank line, CONTROLS, a blank line and "H hides this card")
					for _, l in { "", "CONTROLS", "", "H hides this card" } do
						table.insert(lines, l)
					end
					for _, k in help.keys do
						table.insert(lines, k)
					end
					-- about 42 characters a line in the 340-pixel panel at size 15; 20 lines fit (40 to be safe)
					local n = wrapped(lines, 40)
					t.truthy(n <= 20, `{game.game} on {dev}: {n} lines`)
					seen[dev] = table.concat(help.keys, "\n")
				end
				CueController.device = device
				t.falsy(string.find(seen.keyboard, "R2", 1, true), "no gamepad buttons on the keyboard card")
				t.falsy(string.find(seen.keyboard, "DONE", 1, true), "no touch buttons on the keyboard card")
				t.falsy(string.find(seen.gamepad, "Space", 1, true), "no keys on the gamepad card")
				t.falsy(string.find(seen.touch, "Space", 1, true), "no keys on the touch card")
				t.truthy(#help.how <= 2, "a sentence or two on how to play")
			end
		end, opts())
	end)
end
