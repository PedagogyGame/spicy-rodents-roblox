--!strict
-- tests/isolated/pool_game.luau: cases for tests/unit/pool_game.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Eight-ball played through all of its glue at once on tests/lib/MinigameRig: the real MinigameService with
-- pool's Table (Server/Minigames/Pool/CueTable around the baked balls) and the real MinigameClient with
-- MinigameUI, Pool/CueController and Pool/Playback, joined by the rig's lagged network. The player's hands are
-- tests/pool/PoolRig's: the mouse on the top view, the cue-ball picture and the power bar, in pixels.
-- Nothing here knows where a table stands: every position comes from Attractions/AlleyLayout through the
-- game's own Spec at run time.
-- Interface: return function(t) (the spec shape)
local Computer = require("@shared/Minigames/Pool/Computer")
local EightBall = require("@shared/Minigames/Pool/EightBall")
local Furniture = require("@shared/Minigames/Pool/Furniture")
local Shot = require("@shared/Minigames/Pool/Shot")
local Tables = require("@shared/Minigames/Pool/Tables")
local Wire = require("@shared/Minigames/Pool/Wire")
local Playback = require("@client/Minigames/Pool/Playback")
local PoolRig = require("@tests/pool/PoolRig")
local Rig = require("@tests/lib/MinigameRig")
local roblox = require("@lune/roblox")

local ID = "pool_1"
local Key = roblox.Enum.KeyCode

local function opts(extra: { [string]: any }?): { [string]: any }
	local o: { [string]: any } = { furnish = PoolRig.furnish, stand = PoolRig.stand(ID) }
	for k, v in extra or {} do
		o[k] = v
	end
	return o
end

return function(t)
	t.test("walk up, the prompt, the lobby: a computer opponent by name, and the break is yours", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			local prompt = Rig.prompt(w, ID)
			t.eq(prompt.ActionText, "Play pool")
			Rig.press(w, ID)
			Rig.run(w, 0.3)
			t.truthy(Rig.has(Rig.texts(w.gui), "Pool - Pool table 1"), Rig.screen(w))
			t.truthy(Rig.button(w.gui, "+ Chalky (easy)"), Rig.screen(w))
			Rig.click(w, "+ Eight-Ball Edna (hard)")
			Rig.run(w, 0.3)
			Rig.key(Key.Space, true)
			Rig.key(Key.Space, false)
			Rig.run(w, 0.5)
			local session = w.svc:sessionOf(ID)
			t.eq(session.phase, "playing")
			t.eq(session.names[2], "Eight-Ball Edna (computer)")
			local c = PoolRig.controller(ID)
			-- the break is from behind the head string: the ball is in hand, in the kitchen
			t.eq(c.phase, "place")
			t.truthy(Rig.has(Rig.texts(w.gui), "Your break"), Rig.screen(w))
			-- legs and camera are the table's while I am on the shot
			t.eq(w.controls[#w.controls], false)
			t.truthy(w.held)
		end, opts())
	end)

	t.test("a break through the mouse: the script plays on every ball and lands where the rules have them", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			Rig.press(w, ID)
			Rig.run(w, 0.3)
			Rig.key(Key.Space, true)
			Rig.key(Key.Space, false)
			Rig.run(w, 0.5)
			local c = PoolRig.controller(ID)
			local state = PoolRig.state(w, ID)
			t.eq(state.seats, 1, "alone: practice")
			-- set the cue ball down a little to the right, then break
			PoolRig.carry(w, c, 0.6, Tables.eightBall().headZ - 0.3)
			Rig.key(Key.Space, true)
			Rig.key(Key.Space, false)
			Rig.run(w, 0.3)
			t.eq(c.phase, "aim")
			local placed = Rig.last(w.sent, "place")
			t.near(placed.args[1], 0.6, 1e-3)
			local cue = state.spots[1]
			t.eq(cue.id, 0)
			t.near(cue.x, 0.6, 1e-3)
			-- the aim line and the ghost ball are up
			local apex = state.spots[2]
			local angle = math.atan2(apex.x - cue.x, apex.z - cue.z)
			PoolRig.shoot(w, c, angle, 0.95)
			t.eq(c.phase, "sent")
			local sent = Rig.last(w.sent, "shoot")
			t.near(sent.args[1], angle, 2e-4)
			t.near(sent.args[2], 0.95, 1e-3)
			-- the server tried it, sent the script to everyone and waits: nothing is judged yet
			Rig.run(w, 0.3)
			local st = PoolRig.station(w, ID)
			t.truthy(st.tbl.pending, "a shot is in flight")
			t.eq(state.shotNo, 0, "not judged while the balls roll")
			local shot = Rig.last(w.got, "pool_shot")
			t.truthy(shot and type(shot.text) == "string")
			local script = assert(Wire.decode(shot.text))
			t.eq(c.phase, "watch")
			-- mid-shot: balls on this screen are where the script has them, to the frame
			Rig.run(w, 1)
			local now = assert(Playback.now(ID))
			local moved = 0
			for i, id in script.ids do
				local x, z = Shot.pose(script, i, math.min(now, script.tEnd))
				local bx, bz = PoolRig.ball(w, ID, id)
				if #script.tracks[i] > 0 then
					moved += 1
					local _, _, _, mode = Shot.pose(script, i, math.min(now, script.tEnd))
					if mode ~= 3 then
						t.near(bx, x, 1e-3, `ball {id} x`)
						t.near(bz, z, 1e-3, `ball {id} z`)
					end
				end
			end
			t.truthy(moved >= 10, `{moved} balls moved on the break`)
			-- the end: judged once, the balls where the rules have them, on the server and on this screen
			t.truthy(PoolRig.settle(w, ID))
			t.eq(state.shotNo, 1)
			t.truthy(state.broken)
			local r = Tables.eightBall().ballR
			for _, s in state.spots do
				local bx, bz, by = PoolRig.ball(w, ID, s.id)
				t.near(bx, s.x, 1e-3, `ball {s.id} rests`)
				t.near(bz, s.z, 1e-3)
				t.near(by, r, 1e-3)
				local at = st.hw:position(s.id)
				local sx, _, sz = Furniture.fromWorld(w.places.bowling_alley, PoolRig.def(w, ID), at.X, at.Y, at.Z)
				t.near(sx, s.x, 1e-3, `the server's ball {s.id}`)
				t.near(sz, s.z, 1e-3)
			end
			-- every ball that went down is at home in the tray
			for _, b in state.down do
				local hx, hy, hz = Furniture.home(Tables.eightBall(), b)
				local bx, bz, by = PoolRig.ball(w, ID, b)
				t.near(bx, hx, 1e-3, `ball {b} in the tray`)
				t.near(bz, hz, 1e-3)
				t.near(by, hy, 1e-3)
			end
			t.eq(EightBall.turn(state), 1)
		end, opts())
	end)

	t.test("a whole game against a computer opponent, played by hand to the end card", function()
		Rig.play(function(w)
			PoolRig.clock(w)
			Rig.press(w, ID)
			Rig.run(w, 0.3)
			Rig.click(w, "+ Chalky (easy)")
			Rig.run(w, 0.2)
			Rig.key(Key.Space, true)
			Rig.key(Key.Space, false)
			Rig.run(w, 0.5)
			local c = PoolRig.controller(ID)
			local session = w.svc:sessionOf(ID)
			local state = PoolRig.state(w, ID)
			local st = PoolRig.station(w, ID)
			local mine, theirs, guard = 0, 0, 0
			local sawFoulWords = false
			while session.phase == "playing" and guard < 400 do
				guard += 1
				t.truthy(PoolRig.settle(w, ID), "a shot never finished")
				if session.phase ~= "playing" then
					break
				end
				if EightBall.turn(state) == 1 then
					-- my go: the best computer's choice of shot, played with my own hands
					t.truthy(Rig.untilTrue(w, 3, function()
						return c.phase == "aim" or c.phase == "place"
					end), `my turn never came up on screen (phase {c.phase})`)
					local before = state.shotNo
					PoolRig.play(w, c, Computer.eightBall(state, 3, 7 + guard))
					t.truthy(Rig.untilTrue(w, 2, function()
						return st.tbl.pending ~= nil or state.shotNo > before
					end), `my strike never reached the table: {tostring(w.toasts[#w.toasts])}`)
					mine += 1
				else
					-- the computer's go: it thinks, its cue is drawn back on my screen, it strikes
					local before = state.shotNo
					t.truthy(Rig.untilTrue(w, 12, function()
						return st.tbl.pending ~= nil or state.shotNo > before or session.phase ~= "playing"
					end), "the computer never played")
					theirs += 1
				end
				-- a foul is said in a toast that stays, and on the status line
				if state.last and state.last.event == "foul" and state.last.foul ~= "idle" then
					Rig.run(w, 0.3)
					local words = `Foul: {EightBall.FOUL_TEXT[state.last.foul]}`
					t.truthy(Rig.has(w.toasts, words), `no toast "{words}"`)
					t.truthy(string.find(Rig.screen(w), words, 1, true), Rig.screen(w))
					sawFoulWords = true
				end
			end
			t.eq(session.phase, "done", `the game did not end in {guard} turns`)
			t.truthy(mine > 5 and theirs > 2, `{mine} shots of mine, {theirs} of the computer's`)
			t.truthy(state.done)
			Rig.run(w, 1)
			-- the end card: who won and how, in the rules' own words
			local screen = Rig.screen(w)
			local how = EightBall.HOW_TEXT[state.how]
			t.truthy(string.find(screen, how, 1, true), screen)
			t.truthy(Rig.button(w.gui, "Play again"), screen)
			t.truthy(sawFoulWords or state.fouls[1] + state.fouls[2] == 0, "a foul was never put in words")
			-- nothing was dropped by the Net, nothing warned (the rig fails the case otherwise); few messages went up
			t.truthy(#w.sent < mine * 4 + 20, `{#w.sent} messages for {mine} shots`)
			-- play again: the winner breaks
			local winner = state.winner
			Rig.click(w, "Play again")
			Rig.run(w, 1)
			t.eq(session.phase, "playing")
			local fresh = PoolRig.state(w, ID)
			t.truthy(fresh ~= state)
			t.eq(EightBall.turn(fresh), winner, "the winner breaks the next game")
			t.eq(#fresh.spots, 16)
		end, opts())
	end)
end
