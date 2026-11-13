--!strict
-- tests/isolated/pool_people.luau: cases for tests/unit/pool_people.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Eight-ball with other people on tests/lib/MinigameRig (the real service with pool's Table, the real client
-- with Pool/CueController and Pool/Playback): a second player at the table and the one who leaves, someone who
-- only watches, a slow line, the idle clock and walking away, and the hands of every device (keyboard and
-- mouse are pool_game's; here the gamepad and the touch screen). Other people are PlayerLike stubs who play
-- what Pool/Computer would play, straight into the service. Nothing here knows where a table stands: every
-- position comes from Attractions/AlleyLayout through the game's own Spec at run time.
-- Interface: return function(t) (the spec shape)
local Computer = require("@shared/Minigames/Pool/Computer")
local EightBall = require("@shared/Minigames/Pool/EightBall")
local Shot = require("@shared/Minigames/Pool/Shot")
local Tables = require("@shared/Minigames/Pool/Tables")
local Wire = require("@shared/Minigames/Pool/Wire")
local CueController = require("@client/Minigames/Pool/CueController")
local Playback = require("@client/Minigames/Pool/Playback")
local FakeEngine = require("@tests/lib/FakeEngine")
local PoolRig = require("@tests/pool/PoolRig")
local Rig = require("@tests/lib/MinigameRig")
local roblox = require("@lune/roblox")

local ID = "pool_1"
local Key = roblox.Enum.KeyCode
local Kind = roblox.Enum.UserInputType
local TABLE = Tables.eightBall()

local function opts(extra: { [string]: any }?): { [string]: any }
	local o: { [string]: any } = { furnish = PoolRig.furnish, stand = PoolRig.stand(ID) }
	for k, v in extra or {} do
		o[k] = v
	end
	return o
end

-- A stub's turn: what Pool/Computer would play, sent as that person's inputs. Returns the inputs.
local function stubTurn(w: any, who: any, level: number, seed: number): { any }
	local state = PoolRig.state(w, ID)
	local inputs = Computer.eightBall(state, level, seed)
	for _, input in inputs do
		local ok, why = Rig.input(w, who, ID, input.verb, input.args)
		assert(ok, `{who.Name}'s {input.verb} was refused: {why}`)
	end
	return inputs
end

-- The balls on this screen are where the script has them at this instant (a ball dropping or rolling home is
-- the playback's own and is left out).
local function onScript(t: any, w: any, script: any, label: string): number
	local now = assert(Playback.now(ID), "nothing is playing")
	local at = math.min(math.max(now, 0), script.tEnd)
	local n = 0
	for i, id in script.ids do
		if #script.tracks[i] > 0 then
			local x, z, _, mode = Shot.pose(script, i, at)
			if mode ~= 3 then
				local bx, bz = PoolRig.ball(w, ID, id)
				t.near(bx, x, 1e-3, `{label}: ball {id} x`)
				t.near(bz, z, 1e-3, `{label}: ball {id} z`)
				n += 1
			end
		end
	end
	return n
end

-- Every ball on this screen where the rules have it, once the table is still.
local function atRest(t: any, w: any, label: string)
	local state = PoolRig.state(w, ID)
	for _, s in state.spots do
		local bx, bz = PoolRig.ball(w, ID, s.id)
		t.near(bx, s.x, 1e-3, `{label}: ball {s.id} rests`)
		t.near(bz, s.z, 1e-3)
	end
end

local function pad(code: any, x: number, y: number)
	FakeEngine.input(
		"changed",
		{ UserInputType = Kind.Gamepad1, KeyCode = code, Position = roblox.Vector3.new(x, y, 0) }
	)
end

local function button(w: any, text: string): any
	local b = Rig.button(w.gui, text)
	assert(b, `no button "{text}": {Rig.screen(w)}`)
	return b
end

-- Seat 1 on the 8 (solids cleared), a few stripes and the 8 up, the cue ball where it lies: a scripted table.
local function onTheEight(w: any)
	local spots = {
		{ id = 0, x = 0, z = -1.5 },
		{ id = 8, x = 0.8, z = 2.6 },
		{ id = 10, x = -1.6, z = 0.5 },
		{ id = 12, x = 1.9, z = -2.4 },
	}
	assert(w.svc:debug(ID, "layout", spots, { broken = true, group = { "solids", "stripes" }, inHand = "none" }))
end

return function(t)
	t.test("two people: a turn each, the other's shot played on my screen; he leaves while his balls roll", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			local bob = Rig.stub("Bob")
			Rig.press(w, ID)
			Rig.run(w, 0.3)
			t.truthy(w.svc:join(bob, ID), "Bob joins the lobby")
			Rig.run(w, 0.3)
			t.truthy(string.find(Rig.screen(w), "Bob", 1, true), Rig.screen(w))
			Rig.click(w, "Start now")
			Rig.run(w, 0.5)
			local session = w.svc:sessionOf(ID)
			t.eq(session.phase, "playing")
			t.eq(session.names[1], "Ann")
			t.eq(session.names[2], "Bob")
			local c = PoolRig.controller(ID)
			local state = PoolRig.state(w, ID)
			local st = PoolRig.station(w, ID)
			t.eq(EightBall.turn(state), 1, "the one who sat down first breaks")
			local bobs, mine = 0, 0
			local guard = 0
			while bobs < 3 and guard < 60 and session.phase == "playing" do
				guard += 1
				t.truthy(PoolRig.settle(w, ID))
				if EightBall.turn(state) == 1 then
					t.truthy(Rig.untilTrue(w, 3, function()
						return c.phase == "aim" or c.phase == "place"
					end))
					PoolRig.play(w, c, Computer.eightBall(state, 3, 40 + guard))
					mine += 1
				else
					-- Bob's go: my legs and camera are my own, nothing of mine is drawn, and his shot plays here
					Rig.run(w, 0.3)
					t.eq(c.phase, "off")
					if c.top then
						-- (the top view I asked for stays up to watch from; T gives my own camera back)
						t.eq(w.held, true)
						Rig.key(Key.T, true)
						Rig.key(Key.T, false)
						Rig.frame(w)
					end
					t.eq(w.controls[#w.controls], true)
					t.eq(w.held, false, "my camera is my own while Bob shoots")
					local got = Rig.count(w.got, "pool_shot")
					stubTurn(w, bob, 2, 70 + guard)
					bobs += 1
					t.truthy(
						Rig.untilTrue(w, 2, function()
							return Rig.count(w.got, "pool_shot") > got
						end),
						"Bob's shot never reached my screen"
					)
					local script = assert(Wire.decode(Rig.last(w.got, "pool_shot").text))
					t.eq(Rig.last(w.got, "pool_shot").seat, 2)
					t.truthy(Rig.last(bob.events, "pool_shot"), "and Bob was sent it too")
					Rig.run(w, 0.8)
					if Playback.playing(ID) and (Playback.now(ID) or 0) < script.tEnd then
						t.truthy(onScript(t, w, script, "Bob's shot") > 0)
					end
				end
				t.truthy(PoolRig.settle(w, ID))
				atRest(t, w, `shot {state.shotNo}`)
			end
			t.truthy(bobs >= 1 and mine >= 1, `{mine} of mine, {bobs} of Bob's`)
			t.eq(session.phase, "playing", "(the seeds give a game that is still on after Bob's third turn)")
			t.eq(bobs, 3)
			-- Bob's turn again, or made his: he strikes and walks off while the balls are still running
			t.truthy(PoolRig.settle(w, ID))
			if EightBall.turn(state) ~= 2 then
				assert(w.svc:debug(ID, "layout", state.spots, { seat = 2, inHand = "anywhere" }))
				Rig.run(w, 0.3)
			end
			stubTurn(w, bob, 1, 999)
			Rig.run(w, 0.4)
			t.truthy(st.tbl.pending, "Bob's shot is rolling")
			w.svc:leave(bob, "left")
			Rig.run(w, 0.5)
			-- he forfeits: I win, in the rules' own words
			t.eq(session.phase, "done")
			t.eq(state.winner, 1)
			t.eq(state.how, "left")
			t.truthy(PoolRig.settle(w, ID))
			Rig.run(w, 0.5)
			local screen = Rig.screen(w)
			t.truthy(string.find(screen, "Ann wins: Bob left the table.", 1, true), screen)
			-- the shot that was rolling does not count: the balls go back to where they lay before it
			t.truthy(
				Rig.has(w.toasts, "That shot's player has left: it does not count."),
				table.concat(w.toasts, " | ")
			)
			atRest(t, w, "after the leaver's shot")
		end, opts())
	end)

	t.test("someone who only watches sees every shot played on the table, and keeps their own camera", function()
		Rig.play(
			function(w)
				PoolRig.clock(w)
				-- Bob plays Side-Pocket Sal; Ann stands by the next table and never presses anything
				local bob = Rig.stub("Bob")
				t.truthy(w.svc:join(bob, ID))
				t.truthy(Rig.input(w, bob, ID, "addai", { "Side-Pocket Sal" }))
				t.truthy(Rig.input(w, bob, ID, "start"))
				Rig.run(w, 0.3)
				local session = w.svc:sessionOf(ID)
				t.eq(session.phase, "playing")
				t.eq(session.names[2], "Side-Pocket Sal (computer)")
				local state = PoolRig.state(w, ID)
				t.eq(Rig.prompt(w, ID).ActionText, "In use")
				local shots, compared = 0, 0
				local guard = 0
				while shots < 4 and guard < 40 and session.phase == "playing" do
					guard += 1
					t.truthy(PoolRig.settle(w, ID))
					local before = Rig.count(w.got, "pool_shot")
					if EightBall.turn(state) == 1 then
						stubTurn(w, bob, 2, 300 + guard)
					end
					-- (the computer plays by itself)
					if
						Rig.untilTrue(w, 12, function()
							return Rig.count(w.got, "pool_shot") > before
						end)
					then
						shots += 1
						local msg = Rig.last(w.got, "pool_shot")
						local script = assert(Wire.decode(msg.text))
						Rig.run(w, msg.lead + 0.6)
						if Playback.playing(ID) and (Playback.now(ID) or 0) < script.tEnd then
							compared += onScript(t, w, script, `watched shot {shots}`)
						end
						t.truthy(PoolRig.settle(w, ID))
						atRest(t, w, `watched shot {shots}`)
					end
					t.eq(w.client.active(), nil, "watching is not playing")
					t.eq(w.held, false, "and takes nobody's camera")
				end
				t.truthy(shots >= 3, `{shots} shots watched`)
				t.truthy(compared > 0, "a ball was caught mid-shot")
				-- a computer takes a moment: its cue comes back on every screen for a second before it strikes
				local theirs = Rig.last(w.got, "pool_shot", function(m: any): boolean
					return m.seat == 2
				end)
				if theirs then
					t.near(theirs.lead, 1.0, 1e-6)
				end
			end,
			opts({
				stand = { site = "bowling_alley", x = PoolRig.stand("pool_2").x, y = 3, d = PoolRig.stand("pool_2").d },
			})
		)
	end)

	t.test(
		"a slow line (150 ms each way): a game against the computer plays on, exact, and nothing is refused",
		function()
			Rig.play(function(w)
				PoolRig.clock(w)
				Rig.press(w, ID)
				Rig.run(w, 0.6)
				Rig.click(w, "+ Chalky (easy)")
				Rig.run(w, 0.6)
				Rig.click(w, "Start now")
				Rig.run(w, 1)
				local session = w.svc:sessionOf(ID)
				t.eq(session.phase, "playing")
				local c = PoolRig.controller(ID)
				local state = PoolRig.state(w, ID)
				local st = PoolRig.station(w, ID)
				local mine = 0
				local guard = 0
				while mine < 4 and guard < 40 and session.phase == "playing" do
					guard += 1
					t.truthy(PoolRig.settle(w, ID))
					Rig.run(w, 0.4)
					if EightBall.turn(state) == 1 then
						t.truthy(
							Rig.untilTrue(w, 3, function()
								return c.phase == "aim" or c.phase == "place"
							end),
							`phase {c.phase}`
						)
						local before = state.shotNo
						PoolRig.play(w, c, Computer.eightBall(state, 3, 500 + guard))
						t.truthy(
							Rig.untilTrue(w, 3, function()
								return st.tbl.pending ~= nil or state.shotNo > before
							end),
							`my strike never reached the table: {tostring(w.toasts[#w.toasts])}`
						)
						mine += 1
					else
						local before = state.shotNo
						t.truthy(Rig.untilTrue(w, 12, function()
							return st.tbl.pending ~= nil or state.shotNo > before or session.phase ~= "playing"
						end))
					end
					t.truthy(PoolRig.settle(w, ID))
					Rig.run(w, 0.4)
					atRest(t, w, `shot {state.shotNo}`)
				end
				t.truthy(mine >= 3, `{mine} shots of mine`)
				for _, words in w.toasts do
					t.eq(string.find(words, "Wait for the balls", 1, true), nil, words)
					t.eq(string.find(words, "Not your turn", 1, true), nil, words)
					t.eq(string.find(words, "cannot go there", 1, true), nil, words)
				end
			end, opts({ lag = 9 }))
		end
	)

	t.test("the idle clock: a shot not played is a foul said in words; two in a row and you are taken off", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			Rig.press(w, ID)
			Rig.run(w, 0.3)
			Rig.click(w, "+ Chalky (easy)")
			Rig.run(w, 0.2)
			Rig.click(w, "Start now")
			Rig.run(w, 0.5)
			local session = w.svc:sessionOf(ID)
			local state = PoolRig.state(w, ID)
			local c = PoolRig.controller(ID)
			t.eq(c.phase, "place")
			-- the clock is shown, and warns before it runs out
			Rig.run(w, 50)
			t.truthy(string.find(Rig.screen(w), "or the shot is lost", 1, true), Rig.screen(w))
			Rig.run(w, 11)
			t.eq(state.last and state.last.foul, "idle")
			t.eq(EightBall.turn(state), 2)
			t.truthy(
				Rig.has(w.toasts, "Ann ran out of time. Chalky (computer) has the ball in hand behind the head string."),
				table.concat(w.toasts, " | ")
			)
			t.eq(c.phase, "off")
			t.eq(w.controls[#w.controls], true, "my legs are mine while the computer breaks")
			-- Chalky breaks; then my turn runs out again and I am taken off: the table rests
			t.truthy(
				Rig.untilTrue(w, 20, function()
					return EightBall.turn(state) == 1 and not PoolRig.station(w, ID).tbl.pending
				end),
				"my turn never came back"
			)
			Rig.run(w, 65)
			t.eq(session.phase, "idle")
			t.eq(w.client.active(), nil)
			t.eq(w.held, false)
			t.truthy(Rig.has(w.toasts, "two shots in a row went unplayed"), table.concat(w.toasts, " | "))
			t.eq(Rig.prompt(w, ID).ActionText, "Play pool")
		end, opts())
	end)

	t.test("walking away from the table ends my game with words, and the table is racked for the next", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			Rig.press(w, ID)
			Rig.run(w, 0.3)
			Rig.click(w, "+ Eight-Ball Edna (hard)")
			Rig.run(w, 0.2)
			Rig.click(w, "Start now")
			Rig.run(w, 0.5)
			local session = w.svc:sessionOf(ID)
			t.eq(session.phase, "playing")
			-- V: my legs back, and off I go
			Rig.key(Key.V, true)
			Rig.key(Key.V, false)
			Rig.run(w, 0.2)
			local c = PoolRig.controller(ID)
			t.eq(c.phase, "walk")
			t.eq(w.controls[#w.controls], true)
			local stand = PoolRig.stand("pool_2")
			Rig.walkTo(w, "bowling_alley", stand.x - 30, 3, stand.d - 30)
			Rig.run(w, 0.6)
			t.eq(w.client.active(), nil)
			t.truthy(Rig.has(w.toasts, "You walked away from the game"), table.concat(w.toasts, " | "))
			t.eq(session.phase, "idle")
			t.eq(w.held, false)
			t.eq(Rig.prompt(w, ID).ActionText, "Play pool")
		end, opts())
	end)

	t.test(
		"gamepad: the stick aims, the right stick spins, R2 draws the cue; the D-pad carries the ball and calls the 8",
		function()
			Rig.play(function(w)
				PoolRig.clock(w)
				Rig.press(w, ID)
				Rig.run(w, 0.3)
				Rig.key(Key.ButtonA, true) -- (A in the lobby is nothing of pool's)
				Rig.key(Key.ButtonA, false)
				Rig.click(w, "Start now")
				Rig.run(w, 0.6)
				local c = PoolRig.controller(ID)
				local state = PoolRig.state(w, ID)
				t.eq(c.phase, "place")
				-- the D-pad carries the cue ball (up the screen in the top view is across the table), A sets it down
				local x0, z0 = c.hand.x, c.hand.z
				Rig.key(Key.DPadUp, true)
				Rig.run(w, 0.3)
				Rig.key(Key.DPadUp, false)
				t.truthy(c.hand.x < x0 - 0.3, `the ball went across ({x0} -> {c.hand.x})`)
				t.near(c.hand.z, z0, 1e-6)
				Rig.key(Key.ButtonA, true)
				Rig.key(Key.ButtonA, false)
				Rig.run(w, 0.4)
				t.eq(c.phase, "aim")
				local placed = Rig.last(w.sent, "place")
				t.near(placed.args[1], c.byId[0].x, 1e-6)
				t.near(state.spots[1].x, placed.args[1], 1e-6, "and the server has it there")
				-- the left stick turns the aim, L1 / R1 nudge it
				local a0 = c.angle
				pad(Key.Thumbstick1, 1, 0)
				Rig.run(w, 0.5)
				pad(Key.Thumbstick1, 0, 0)
				t.truthy(c.angle - a0 > 0.4, `the stick turned the aim by {c.angle - a0}`)
				local a1 = c.angle
				Rig.key(Key.ButtonL1, true)
				Rig.key(Key.ButtonL1, false)
				t.near(c.angle, a1 - CueController.NUDGE, 1e-9)
				-- the right stick sets the spin where it points
				pad(Key.Thumbstick2, 0, -0.6)
				Rig.run(w, 0.1)
				pad(Key.Thumbstick2, 0, 0)
				t.near(c.tipY, -0.6, 1e-6, "draw")
				-- Y: the top view; again: back on the cue
				Rig.key(Key.ButtonY, true)
				Rig.key(Key.ButtonY, false)
				t.truthy(c.top)
				Rig.key(Key.ButtonY, true)
				Rig.key(Key.ButtonY, false)
				t.falsy(c.top)
				-- R2 held: the power rises (the cue is drawn back, the meter shows it); let go: the strike
				Rig.key(Key.ButtonR2, true)
				Rig.run(w, 0.75)
				t.truthy(c.power > 0.4 and c.power < 0.6, `power {c.power}`)
				local aim = c.angle
				Rig.key(Key.ButtonR2, false)
				local sent = Rig.last(w.sent, "shoot")
				t.truthy(sent, "R2 let go strikes")
				t.near(sent.args[1], aim, 1e-9)
				t.truthy(sent.args[2] > 0.4 and sent.args[2] < 0.6)
				t.near(sent.args[4], -0.6, 1e-6)
				t.truthy(PoolRig.settle(w, ID))
				-- on the 8: the D-pad picks the pocket (a ring marks it) and it is called
				onTheEight(w)
				Rig.run(w, 0.6)
				t.eq(c.phase, "aim")
				t.truthy(string.find(Rig.screen(w), "call a pocket first", 1, true), Rig.screen(w))
				Rig.key(Key.DPadRight, true)
				Rig.key(Key.DPadRight, false)
				Rig.run(w, 0.4)
				t.eq(Rig.last(w.sent, "call").args[1], 1)
				t.eq(state.called, 1)
				Rig.key(Key.DPadRight, true)
				Rig.key(Key.DPadRight, false)
				Rig.key(Key.DPadLeft, true)
				Rig.key(Key.DPadLeft, false)
				Rig.key(Key.DPadLeft, true)
				Rig.key(Key.DPadLeft, false)
				Rig.run(w, 0.4)
				t.eq(state.called, 6, "round the six pockets")
				t.truthy(c.parts.ring.Transparency < 1, "a ring marks the called pocket")
				-- the keyboard's numbers and the mouse do it too: 3, then a click on the head right corner
				Rig.key(Key.Three, true)
				Rig.key(Key.Three, false)
				Rig.run(w, 0.3)
				t.eq(state.called, 3)
				PoolRig.top(w, c)
				local hole = TABLE.holes[2]
				PoolRig.click(w, c, hole.x, hole.z)
				Rig.run(w, 0.3)
				t.eq(state.called, 2)
				t.truthy(string.find(Rig.screen(w), "called for", 1, true), Rig.screen(w))
			end, opts())
		end
	)

	t.test("touch: a finger carries the ball in hand, drags the aim, sets the spin; HOLD TO SHOOT strikes", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			Rig.press(w, ID)
			Rig.run(w, 0.3)
			Rig.click(w, "Start now")
			Rig.run(w, 0.6)
			local c = PoolRig.controller(ID)
			local state = PoolRig.state(w, ID)
			t.eq(c.phase, "place")
			t.truthy(string.find(Rig.screen(w), "then DONE", 1, true), Rig.screen(w))
			-- a finger on the cue ball, dragged: the ball follows it, and is set down where it is let go
			local cam = workspace.CurrentCamera
			local function pixel(x: number, z: number): (number, number)
				local wx, wy, wz = require("@shared/Minigames/Pool/Furniture").world(c.place, c.def, x, TABLE.ballR, z)
				local p = cam:WorldToViewportPoint(roblox.Vector3.new(wx, wy, wz))
				return p.X, p.Y
			end
			Rig.run(w, 0.5)
			local hx, hz = c.hand.x, c.hand.z
			local px, py = pixel(hx, hz)
			Rig.touch("ball", "began", px, py)
			Rig.frame(w)
			local qx, qy = pixel(hx + 0.7, hz - 0.2)
			Rig.touch("ball", "changed", qx, qy)
			Rig.frame(w)
			Rig.touch("ball", "ended", qx, qy)
			Rig.run(w, 0.4)
			t.near(c.hand.x, hx + 0.7, 0.02)
			t.near(state.spots[1].x, hx + 0.7, 0.02, "set down on the server")
			button(w, "DONE").MouseButton1Down.fire()
			button(w, "DONE").MouseButton1Up.fire()
			Rig.run(w, 0.3)
			t.eq(c.phase, "aim")
			t.truthy(string.find(Rig.screen(w), "Drag to aim", 1, true), Rig.screen(w))
			-- a finger dragged across the screen turns the aim as far as it went
			local a0 = c.angle
			Rig.touch("aim", "began", 400, 300)
			Rig.frame(w)
			Rig.touch("aim", "changed", 500, 300)
			Rig.frame(w)
			Rig.touch("aim", "ended", 500, 300)
			t.near(c.angle - a0, 100 * CueController.DRAG, 1e-6)
			-- a finger on the cue-ball picture: follow
			local ax, ay, as = c:pad()
			Rig.touch("tip", "began", ax + as / 2, ay + as / 4)
			Rig.touch("tip", "ended", ax + as / 2, ay + as / 4)
			t.truthy(c.tipY > 0.4, `tip {c.tipY}`)
			-- HOLD TO SHOOT (the other thumb, on a button): the aim does not move, and letting go strikes
			local aim = c.angle
			button(w, "HOLD TO SHOOT").MouseButton1Down.fire()
			Rig.run(w, 0.9)
			t.truthy(c.power > 0.5, `power {c.power}`)
			button(w, "HOLD TO SHOOT").MouseButton1Up.fire()
			local sent = Rig.last(w.sent, "shoot")
			t.truthy(sent)
			t.near(sent.args[1], aim, 1e-9)
			t.truthy(sent.args[3] == 0 and sent.args[4] > 0.4)
			t.truthy(PoolRig.settle(w, ID))
			t.eq(state.shotNo, 1)
		end, opts({ touch = true }))
	end)
end
