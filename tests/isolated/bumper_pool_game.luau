--!strict
-- tests/isolated/bumper_pool_game.luau: cases for tests/unit/bumper_pool_game.spec.luau, run in their own Lune
-- process (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Bumper pool played through all of its glue at once on tests/lib/MinigameRig: the real MinigameService with
-- bumper pool's Table (Server/Minigames/Pool/CueTable around the baked balls) and the real MinigameClient with
-- MinigameUI, Pool/CueController and Pool/Playback. The player's hands are tests/pool/PoolRig's (the mouse on the
-- top view, the cue-ball picture and the power bar, in pixels); other people are PlayerLike stubs who play what
-- Pool/Computer would play. Nothing here knows where the table stands: every position comes from
-- Attractions/AlleyLayout through the game's own Spec at run time.
-- Interface: return function(t) (the spec shape)
local BumperPool = require("@shared/Minigames/Pool/BumperPool")
local Computer = require("@shared/Minigames/Pool/Computer")
local Cue = require("@shared/Minigames/Pool/Cue")
local Furniture = require("@shared/Minigames/Pool/Furniture")
local Shot = require("@shared/Minigames/Pool/Shot")
local Tables = require("@shared/Minigames/Pool/Tables")
local Wire = require("@shared/Minigames/Pool/Wire")
local Playback = require("@client/Minigames/Pool/Playback")
local BumperPoolFlow = require("@tests/engine/BumperPoolFlow")
local PoolRig = require("@tests/pool/PoolRig")
local Rig = require("@tests/lib/MinigameRig")
local roblox = require("@lune/roblox")

local ID = "bumper_pool_1"
local Key = roblox.Enum.KeyCode
local TABLE = Tables.bumper()

local function opts(extra: { [string]: any }?): { [string]: any }
	local o: { [string]: any } = { furnish = PoolRig.furnish, stand = PoolRig.stand(ID) }
	for k, v in extra or {} do
		o[k] = v
	end
	return o
end

-- Every ball on this screen where the rules have it, once the table is still.
local function atRest(t: any, w: any, label: string)
	local state = PoolRig.state(w, ID)
	for _, s in state.spots do
		local bx, bz, by = PoolRig.ball(w, ID, s.id)
		t.near(bx, s.x, 1e-3, `{label}: ball {s.id} rests`)
		t.near(bz, s.z, 1e-3)
		t.near(by, TABLE.ballR, 1e-3)
	end
end

-- A stub's turn: what Pool/Computer would play, sent as that person's inputs.
local function stubTurn(w: any, who: any, seat: number, level: number, seed: number)
	local state = PoolRig.state(w, ID)
	for _, input in Computer.bumper(state, seat, level, seed) do
		local ok, why = Rig.input(w, who, ID, input.verb, input.args)
		assert(ok, `{who.Name}'s {input.verb} was refused: {why}`)
	end
end

local function start(w: any, extra: string?)
	Rig.press(w, ID)
	Rig.run(w, 0.3)
	if extra then
		Rig.click(w, extra)
		Rig.run(w, 0.2)
	end
	Rig.click(w, "Start now")
	Rig.run(w, 0.5)
end

return function(t)
	t.test(
		"practice: the prompt, the marked ball first, every ball picked by hand, five down to the end card",
		function()
			Rig.play(function(w)
				PoolRig.clock(w)
				t.eq(Rig.prompt(w, ID).ActionText, "Play bumper pool")
				Rig.press(w, ID)
				Rig.run(w, 0.3)
				t.truthy(Rig.has(Rig.texts(w.gui), "Bumper pool - Bumper pool"), Rig.screen(w))
				t.truthy(Rig.button(w.gui, "+ Bumper Bob (easy)"), Rig.screen(w))
				Rig.click(w, "Start now")
				Rig.run(w, 0.5)
				local session = w.svc:sessionOf(ID)
				t.eq(session.phase, "playing")
				local state = PoolRig.state(w, ID)
				t.eq(state.seats, 1)
				t.eq(state.phase, "play", "no opening against nobody")
				local c = PoolRig.controller(ID)
				t.eq(c.phase, "aim")
				t.eq(c.sel, 1, "the marked ball first")
				t.truthy(string.find(Rig.screen(w), "Pick a ball", 1, true), Rig.screen(w))
				-- the other side's five are out of sight inside the table
				for id = 6, 10 do
					local _, _, y = PoolRig.ball(w, ID, id)
					t.truthy(y < -0.5, `ball {id} is hidden`)
				end
				-- R and the number keys pick among my balls; the cue first points at my cup (the foot end)
				Rig.key(Key.R, true)
				Rig.key(Key.R, false)
				t.eq(c.sel, 2)
				Rig.key(Key.Four, true)
				Rig.key(Key.Four, false)
				t.eq(c.sel, 4)
				local s4 = c.byId[4]
				local cup = TABLE.holes[2]
				t.near(c.angle, Cue.angleOf(cup.x - s4.x, cup.z - s4.z), 1e-9)
				Rig.key(Key.One, true)
				Rig.key(Key.One, false)
				t.eq(c.sel, 1)
				local guard = 0
				while session.phase == "playing" and guard < 80 do
					guard += 1
					t.truthy(PoolRig.settle(w, ID))
					if session.phase ~= "playing" then
						break
					end
					t.truthy(
						Rig.untilTrue(w, 3, function()
							return c.phase == "aim"
						end),
						`phase {c.phase}`
					)
					local before = state.shotNo
					PoolRig.play(w, c, Computer.bumper(state, 1, 3, 20 + guard))
					t.truthy(
						Rig.untilTrue(w, 2, function()
							return PoolRig.station(w, ID).tbl.pending ~= nil or state.shotNo > before
						end),
						`my strike never reached the table: {tostring(w.toasts[#w.toasts])}`
					)
					local sent = Rig.last(w.sent, "shoot")
					t.eq(BumperPool.sideOf(sent.args[1]), 1, "only my own balls")
					t.truthy(PoolRig.settle(w, ID))
					atRest(t, w, `shot {state.shotNo}`)
				end
				t.eq(session.phase, "done", `five not down in {guard} shots`)
				t.eq(state.sunk[1], 5)
				-- the sunk balls are in the tray at the foot end, each in its own place
				for id = 1, 5 do
					local hx, hy, hz = Furniture.home(TABLE, id)
					local bx, bz, by = PoolRig.ball(w, ID, id)
					t.near(bx, hx, 1e-3, `ball {id} home`)
					t.near(bz, hz, 1e-3)
					t.near(by, hy, 1e-3)
				end
				Rig.run(w, 1)
				local screen = Rig.screen(w)
				t.truthy(string.find(screen, "All five are down: sank all five in", 1, true), screen)
				t.truthy(Rig.button(w.gui, "Play again"), screen)
			end, opts())
		end
	)

	t.test("against the computer: the opening is two strikes played together, then a whole game to the end", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			start(w, "+ Bank-Shot Betty (medium)")
			local session = w.svc:sessionOf(ID)
			t.eq(session.phase, "playing")
			t.eq(session.names[2], "Bank-Shot Betty (computer)")
			local state = PoolRig.state(w, ID)
			local st = PoolRig.station(w, ID)
			local c = PoolRig.controller(ID)
			t.eq(state.phase, "opening")
			t.eq(c.phase, "aim")
			t.eq(c.sel, 1)
			t.truthy(string.find(Rig.screen(w), "cushion on your RIGHT", 1, true), Rig.screen(w))
			-- the cue first points at the bank off the cushion on my right (+x for the red side)
			local dx = math.sin(c.angle)
			t.truthy(dx > 0.2, `the opening aim leans right ({dx})`)
			-- my opening strike stands, and nothing plays until hers is in
			local shots = Rig.count(w.got, "bumper_pool_shot")
			PoolRig.play(w, c, Computer.bumper(state, 1, 3, 5))
			Rig.run(w, 0.4)
			t.eq(Rig.count(w.got, "bumper_pool_shot"), shots, "the table waits for the second strike")
			t.truthy(state.pending[1], "my strike is in")
			t.truthy(string.find(Rig.screen(w), "waiting for Bank-Shot Betty", 1, true), Rig.screen(w))
			t.truthy(
				Rig.untilTrue(w, 12, function()
					return Rig.count(w.got, "bumper_pool_shot") > shots
				end),
				"the computer never struck its opening shot"
			)
			local msg = Rig.last(w.got, "bumper_pool_shot")
			local script = assert(Wire.decode(msg.text))
			t.eq(#script.strikes, 12, "two strikes in one run (six numbers each)")
			t.near(msg.lead, 1.0, 1e-6, "the computer's cue comes back for a second first")
			-- mid-shot, both marked balls run on my screen where the script has them
			Rig.run(w, msg.lead + 0.5)
			local now = assert(Playback.now(ID))
			for _, id in { 1, 6 } do
				local i = assert(Shot.indexOf(script, id))
				local x, z, _, m = Shot.pose(script, i, math.min(now, script.tEnd))
				if m ~= 3 then
					local bx, bz = PoolRig.ball(w, ID, id)
					t.near(bx, x, 1e-3, `ball {id}`)
					t.near(bz, z, 1e-3)
				end
			end
			t.truthy(PoolRig.settle(w, ID))
			t.eq(state.phase, "play")
			atRest(t, w, "after the opening")
			-- the rest of the game, turn by turn
			local mine, theirs, guard = 0, 0, 0
			while session.phase == "playing" and guard < 200 do
				guard += 1
				t.truthy(PoolRig.settle(w, ID))
				if session.phase ~= "playing" then
					break
				end
				if BumperPool.turn(state) == 1 then
					t.truthy(
						Rig.untilTrue(w, 3, function()
							return c.phase == "aim"
						end),
						`phase {c.phase}`
					)
					local before = state.shotNo
					PoolRig.play(w, c, Computer.bumper(state, 1, 3, 50 + guard))
					t.truthy(
						Rig.untilTrue(w, 2, function()
							return st.tbl.pending ~= nil or state.shotNo > before
						end),
						`my strike never reached the table: {tostring(w.toasts[#w.toasts])}`
					)
					mine += 1
				else
					local before = state.shotNo
					t.truthy(
						Rig.untilTrue(w, 15, function()
							return st.tbl.pending ~= nil or state.shotNo > before or session.phase ~= "playing"
						end),
						"the computer never played"
					)
					theirs += 1
				end
				t.truthy(PoolRig.settle(w, ID))
				atRest(t, w, `shot {state.shotNo}`)
			end
			t.eq(session.phase, "done", `the game did not end in {guard} turns`)
			t.truthy(mine >= 3 and theirs >= 1, `{mine} of mine, {theirs} of hers`)
			Rig.run(w, 1)
			local screen = Rig.screen(w)
			t.truthy(string.find(screen, "wins:", 1, true), screen)
			t.truthy(string.find(screen, "BANKS", 1, true), screen)
			t.truthy(#w.sent < (mine + 1) * 6 + 20, `{#w.sent} messages for {mine} shots`)
		end, opts())
	end)

	t.test(
		"two people: both strike the opening, played together; the other's shots play on my screen; he leaves and forfeits",
		function()
			Rig.play(function(w)
				PoolRig.clock(w)
				local bob = Rig.stub("Bob")
				Rig.press(w, ID)
				Rig.run(w, 0.3)
				t.truthy(w.svc:join(bob, ID))
				Rig.click(w, "Start now")
				Rig.run(w, 0.5)
				local session = w.svc:sessionOf(ID)
				local state = PoolRig.state(w, ID)
				local c = PoolRig.controller(ID)
				t.eq(session.names[2], "Bob")
				-- I strike my opening shot first; it stands, and Bob's strike starts the table
				t.eq(c.phase, "aim")
				local shots = Rig.count(w.got, "bumper_pool_shot")
				PoolRig.play(w, c, Computer.bumper(state, 1, 3, 10))
				Rig.run(w, 0.4)
				t.eq(Rig.count(w.got, "bumper_pool_shot"), shots)
				t.eq(c.phase, "off")
				t.truthy(string.find(Rig.screen(w), "waiting for Bob", 1, true), Rig.screen(w))
				stubTurn(w, bob, 2, 2, 9)
				t.truthy(
					Rig.untilTrue(w, 2, function()
						return Rig.count(w.got, "bumper_pool_shot") > shots
					end),
					"the opening never played"
				)
				t.eq(Rig.last(w.got, "bumper_pool_shot").seat, 2)
				t.truthy(Rig.last(bob.events, "bumper_pool_shot"), "Bob is sent the shot too")
				t.truthy(PoolRig.settle(w, ID))
				atRest(t, w, "the opening")
				-- a few turns each way
				local guard, bobs = 0, 0
				while bobs < 2 and guard < 40 and session.phase == "playing" do
					guard += 1
					t.truthy(PoolRig.settle(w, ID))
					if BumperPool.turn(state) == 1 then
						t.truthy(Rig.untilTrue(w, 3, function()
							return c.phase == "aim"
						end))
						PoolRig.play(w, c, Computer.bumper(state, 1, 2, 60 + guard))
					else
						Rig.run(w, 0.3)
						t.eq(c.phase, "off")
						stubTurn(w, bob, 2, 1, 80 + guard)
						bobs += 1
					end
					t.truthy(PoolRig.settle(w, ID))
					atRest(t, w, `shot {state.shotNo}`)
				end
				t.eq(session.phase, "playing", "(the seeds give a game still on after Bob's second shot)")
				w.svc:leave(bob, "left")
				Rig.run(w, 0.5)
				t.eq(session.phase, "done")
				t.eq(state.winner, 1)
				t.eq(state.how, "left")
				Rig.run(w, 0.5)
				local screen = Rig.screen(w)
				t.truthy(string.find(screen, "Ann wins: Bob left the table.", 1, true), screen)
				local board = PoolRig.board(w, ID)
				t.truthy(string.find(board, "BUMPER POOL", 1, true), board)
				t.truthy(string.find(board, "Ann (red): ", 1, true), board)
				t.truthy(string.find(board, "Games won: Ann 1", 1, true), board)
			end, opts())
		end
	)

	t.test("the gamepad picks the ball with the D-pad and strikes with R2; touch has its own button", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			start(w)
			local c = PoolRig.controller(ID)
			t.eq(c.sel, 1)
			Rig.key(Key.DPadRight, true)
			Rig.key(Key.DPadRight, false)
			t.eq(c.sel, 2)
			Rig.key(Key.DPadLeft, true)
			Rig.key(Key.DPadLeft, false)
			Rig.key(Key.DPadLeft, true)
			Rig.key(Key.DPadLeft, false)
			t.eq(c.sel, 5, "round my five")
			Rig.key(Key.ButtonR2, true)
			Rig.run(w, 0.4)
			Rig.key(Key.ButtonR2, false)
			local sent = Rig.last(w.sent, "shoot")
			t.eq(sent.args[1], 5)
			t.truthy(sent.args[3] > 0.15 and sent.args[3] < 0.4, `power {sent.args[3]}`)
			t.truthy(PoolRig.settle(w, ID))
		end, opts())
	end)

	t.test("the server check's flow (tests/engine/BumperPoolFlow) passes on this service", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			local ann, bob = Rig.stub("Ann"), Rig.stub("Bob")
			local out = BumperPoolFlow.play(w.svc, {
				BumperPool = BumperPool,
				Computer = Computer,
				Tables = Tables,
				Wire = Wire,
				Furniture = Furniture,
			}, {
				players = { ann, bob },
				step = function(seconds: number)
					Rig.run(w, seconds)
				end,
			})
			t.truthy(out.ok, table.concat(out.failures, "; "))
			t.eq(out.numbers.hardware, 1, "the flow saw the table's balls")
			t.truthy(out.numbers.gameShots >= 4, `{out.numbers.gameShots} shots in the game against Bumper Bob`)
		end, opts({ stand = { site = "bowling_alley", x = -20, y = 3, d = -40 } }))
	end)
end
