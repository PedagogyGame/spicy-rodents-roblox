--!strict
-- tests/isolated/minigame_client.luau: cases for tests/unit/minigame_client.spec.luau, run in their own Lune
-- process (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Client/Minigames/MinigameClient with the real MinigameUI, BowlingClient and BowlingPlayback, fed the
-- messages a server sends during a bowling game (built from the real Session, rules and roll script): joined,
-- state every second, a throw's script, banners, a refusal, a damaged script, the end card, leaving. Nothing
-- here can show how it looks; it shows that every screen element is built and updated without an error, that
-- the words are the right ones, that the scorecard is not rebuilt when nothing changed, that the buttons and
-- keys send what they say, and that the camera and controls are always handed back.
-- Interface: return function(t) (the spec shape)
local Bowling = require("@shared/Minigames/MinigameRules/Bowling")
local Session = require("@shared/Minigames/Session")
local PinModel = require("@shared/Minigames/Bowling/PinModel")
local Referee = require("@shared/Minigames/Bowling/Referee")
local RollScript = require("@shared/Minigames/Bowling/RollScript")
local BowlingClient = require("@client/Minigames/BowlingClient")
local BowlingPlayback = require("@client/Minigames/BowlingPlayback")
local MinigameClient = require("@client/Minigames/MinigameClient")
local MinigameSounds = require("@client/Minigames/MinigameSounds")
local FakeEngine = require("@tests/lib/FakeEngine")
local roblox = require("@lune/roblox")

local STATION = "bowling_lane_3"
local Key = roblox.Enum.KeyCode
local Kind = roblox.Enum.UserInputType

type Rig = {
	client: any,
	input: any, -- the Minigame.Input remote (what the client sent is in input.fired)
	state: any, -- the Minigame.State remote (fire state.OnClientEvent.fire(msg))
	toasts: { string },
	refreshed: number,
	species: string,
	gui: any,
	player: any,
	session: any,
}

local function rig(): Rig
	local rs = (game :: any):GetService("ReplicatedStorage")
	local net = FakeEngine.new("Folder", "Net")
	net.Parent = rs
	local input = FakeEngine.new("RemoteEvent", "Minigame.Input")
	input.Parent = net
	local state = FakeEngine.new("RemoteEvent", "Minigame.State")
	state.Parent = net
	local r: Rig = {
		client = nil,
		input = input,
		state = state,
		toasts = {},
		refreshed = 0,
		species = "human",
		gui = nil,
		player = (game :: any):GetService("Players").LocalPlayer,
		session = Session.new(Bowling, { lobbySeconds = 8, turnSeconds = 60, doneSeconds = 30 }),
	}
	r.client = MinigameClient.start({
		state = function()
			return { species = r.species, device = nil }
		end,
		current = function(): any
			return nil
		end,
		toast = function(text: string)
			table.insert(r.toasts, text)
		end,
		refreshCamera = function()
			r.refreshed += 1
		end,
	})
	r.gui = r.player:FindFirstChild("PlayerGui"):FindFirstChild("MinigameUI")
	return r
end

local function send(r: Rig, msg: { [string]: any })
	r.state.OnClientEvent.fire(msg)
end

-- the clock the bowling controller and playback read: it only moves when frames() runs
local clockNow = 1000
local function fakeClock(): number
	return clockNow
end

local function frames(seconds: number)
	BowlingClient.clock = fakeClock
	BowlingPlayback.clock = fakeClock
	for _ = 1, math.max(1, math.floor(seconds * 60 + 0.5)) do
		clockNow += 1 / 60
		FakeEngine.renderStep(1 / 60)
	end
end

-- the "state" message the server would send to seat `you` right now
local function stateMsg(r: Rig, you: number, ready: boolean, now: number): { [string]: any }
	return {
		kind = "state",
		station = STATION,
		game = "bowling",
		label = "Lane 3",
		lane = 3,
		you = you,
		ready = ready,
		view = Session.view(r.session, now),
	}
end

local function texts(root: any): { string }
	local out = {}
	for _, d in root:GetDescendants() do
		if
			(d.ClassName == "TextLabel" or d.ClassName == "TextButton")
			and type(d.Text) == "string"
			and d.Text ~= ""
		then
			table.insert(out, d.Text)
		end
	end
	return out
end

local function has(list: { string }, needle: string): boolean
	for _, s in list do
		if string.find(s, needle, 1, true) then
			return true
		end
	end
	return false
end

local function button(root: any, text: string): any
	for _, d in root:GetDescendants() do
		if d.ClassName == "TextButton" and d.Text == text then
			return d
		end
	end
	return nil
end

local function lastSent(r: Rig): any
	local fired = r.input.fired
	return if fired and #fired > 0 then fired[#fired][1] else nil
end

local function key(code: any, down: boolean)
	FakeEngine.input(if down then "began" else "ended", { KeyCode = code, UserInputType = Kind.Keyboard }, false)
end

return function(t)
	t.test(
		"a bowling game from the first message to the end card: every screen piece is built, with the right words",
		function()
			FakeEngine.with(function()
				local r = rig()
				t.truthy(r.gui ~= nil, "the interface exists")
				t.eq(r.gui.Enabled, false)
				t.eq(r.client.active(), nil)
				-- seated: the help card, the lobby buttons, a line that says what happened
				send(r, { kind = "joined", station = STATION, game = "bowling", label = "Lane 3", lane = 3, seat = 1 })
				t.eq(r.gui.Enabled, true)
				t.eq(r.client.active(), STATION)
				t.eq(r.player:GetAttribute("InMinigame"), STATION)
				t.truthy(has(r.toasts, "You joined Lane 3"))
				local all = texts(r.gui)
				t.truthy(has(all, "Bowling - Lane 3"))
				t.truthy(has(all, "Z / X or mouse wheel"), "the help card lists the keys")
				t.truthy(button(r.gui, "Start now") ~= nil and button(r.gui, "Add a computer") ~= nil)
				t.truthy(button(r.gui, "Leave (Q)") ~= nil)
				-- the lobby
				Session.join(r.session, "me", "Ann", 0)
				Session.join(r.session, "bot", "Bowlbot (computer)", 0)
				send(r, stateMsg(r, 1, true, 1))
				t.truthy(has(texts(r.gui), "Starting in 7"))
				button(r.gui, "Add a computer").Activated.fire()
				t.eq(lastSent(r).verb, "addai")
				key(Key.Space, true)
				t.eq(lastSent(r).verb, "start", "Space starts the lobby")
				t.eq(lastSent(r).gameId, STATION)
				-- the game starts: my turn, lane ready
				Session.start(r.session, 2)
				Session.step(r.session, 2)
				send(r, { kind = "event", station = STATION, text = "Game on!", big = true })
				t.truthy(has(texts(r.gui), "Game on!"))
				send(r, stateMsg(r, 1, true, 3))
				frames(0.3)
				local card = r.gui:FindFirstChild("Scorecard")
				t.truthy(has(texts(card), "Ann (you)"))
				t.truthy(has(texts(card), "Bowlbot (computer)"))
				t.truthy(has(texts(card), "TOTAL"))
				t.truthy(has(texts(r.gui), "Your turn"))
				t.truthy(r.gui:FindFirstChild("Clock").Visible, "the turn clock is on screen")
				t.truthy(r.gui:FindFirstChild("Hook").Visible, "so is the hook indicator")
				t.truthy(has(texts(r.gui), "HOOK: straight"))
				t.eq(
					workspace.CurrentCamera.CameraType,
					roblox.Enum.CameraType.Scriptable,
					"the aiming shot has the camera"
				)
				t.eq(button(r.gui, "Start now"), nil, "mid-game the only button is Leave")
				-- the scorecard is not rebuilt by the once-a-second state when nothing changed
				local firstRow = card:GetChildren()[2]
				send(r, stateMsg(r, 1, true, 4))
				send(r, stateMsg(r, 1, true, 5))
				t.truthy(card:GetChildren()[2] == firstRow, "same scorecard instances")
				-- hold Space, let go: one release goes to the server; the meter shows its band and words meanwhile
				key(Key.Space, true)
				frames(1.0)
				t.truthy(r.gui:FindFirstChild("Meter").Visible)
				t.truthy(has(texts(r.gui), "let go in the green"))
				key(Key.Space, false)
				local rel = lastSent(r)
				t.eq(rel.verb, "release")
				t.eq(#rel.args, 4)
				t.eq(r.gui:FindFirstChild("Meter").Visible, false)
				-- the server refuses it (say the pinsetter was not done): the words show, and I can throw again
				send(r, {
					kind = "refused",
					text = "Wait for the pinsetter and the ball",
					verb = "release",
					station = STATION,
				})
				t.truthy(has(r.toasts, "Wait for the pinsetter"))
				key(Key.Space, true)
				frames(1.0)
				key(Key.Space, false)
				t.eq(#r.input.fired, 4, "a second release went out")
				-- the throw: its script arrives, the strike banner, the scorecard changes
				local script =
					RollScript.build({ offset = 0.165, angle = 0, power = 0.7, spin = 0 }, PinModel.fullRack(), 5)
				send(r, { kind = "roll", station = STATION, lane = 3, seat = 1, name = "Ann", script = script })
				send(r, stateMsg(r, 1, false, 6))
				frames(1.0)
				local verdict = Referee.score(r.session, { pins = script.down, seat = 1, flags = script.flags }, 7)
				Session.step(r.session, 7)
				send(r, {
					kind = "event",
					station = STATION,
					text = verdict.text,
					big = verdict.big,
					pins = verdict.pins,
					mark = verdict.mark,
				})
				t.truthy(has(texts(r.gui), "STRIKE!"))
				send(r, stateMsg(r, 1, false, 7))
				t.truthy(card:GetChildren()[2] ~= firstRow, "the scorecard was rebuilt for the new mark")
				t.truthy(has(texts(card), "X"))
				t.truthy(has(texts(r.gui), "Bowlbot (computer) is bowling"))
				t.truthy(
					(MinigameSounds.counts().strike or 0) >= 1,
					"the strike cue fired (silent: no sound is uploaded)"
				)
				-- the camera comes back once the pin shot is over, however long that takes
				frames(8)
				t.truthy(r.refreshed >= 1, "my own camera was handed back")
				-- a damaged script and an unknown lane never break the handler
				send(r, { kind = "roll", station = STATION, lane = 3, seat = 2, script = { v = 1 } })
				send(r, { kind = "roll", station = "bowling_lane_5", lane = 5, seat = 1, script = script })
				send(r, { kind = "rack", station = STATION, lane = 3, mask = PinModel.fullRack() })
				send(r, stateMsg(r, 1, false, 8))
				-- play it out: the end card
				local guard = 0
				while r.session.phase == "playing" and guard < 60 do
					guard += 1
					local turn = Session.turn(r.session)
					Referee.score(r.session, { pins = if turn == 1 then 10 else 7, seat = turn }, 9)
					Session.step(r.session, 9)
				end
				t.eq(r.session.phase, "done")
				send(r, { kind = "event", station = STATION, text = "Ann wins with 300!", big = true, over = true })
				send(r, stateMsg(r, 1, true, 10))
				local over = r.gui:FindFirstChild("Summary")
				t.truthy(over.Visible, "the end card is up")
				local words = texts(over)
				t.truthy(has(words, "GAME OVER"))
				t.truthy(has(words, "Ann wins with 300!"))
				t.truthy(has(words, "Ann (you)"))
				t.truthy(has(words, "300"))
				t.truthy(has(words, "STRIKES") and has(words, "SPARES") and has(words, "MISSES"))
				t.truthy(has(words, "The lane resets in 29 s"))
				send(r, stateMsg(r, 1, true, 20))
				t.truthy(has(texts(over), "The lane resets in 19 s"), "the countdown runs")
				button(over, "Play again").Activated.fire()
				t.eq(lastSent(r).verb, "again")
				button(over, "Leave (Q)").Activated.fire()
				t.eq(lastSent(r).verb, "leave")
				t.truthy(button(r.gui:FindFirstChild("Scorecard").Parent, "Play again") ~= nil)
				-- the server takes me off the lane: everything closes, with words
				send(r, { kind = "left", station = STATION, why = "left" })
				t.eq(r.gui.Enabled, false)
				t.eq(r.client.active(), nil)
				t.eq(r.player:GetAttribute("InMinigame"), nil)
				t.eq(over.Visible, false)
				t.truthy(has(r.toasts, "You left the game"))
				t.eq(FakeEngine.bound(), 0, "no camera or playback step is left bound")
			end)
		end
	)

	t.test(
		"leaving mid-aim hands back the camera and the controls; Q asks to leave; every way off the lane has words",
		function()
			FakeEngine.with(function()
				local r = rig()
				send(r, { kind = "joined", station = STATION, game = "bowling", label = "Lane 3", lane = 3, seat = 1 })
				Session.join(r.session, "me", "Ann", 0)
				Session.start(r.session, 1)
				Session.step(r.session, 1)
				send(r, stateMsg(r, 1, true, 2))
				frames(0.3)
				t.eq(workspace.CurrentCamera.CameraType, roblox.Enum.CameraType.Scriptable)
				key(Key.Q, true)
				t.eq(lastSent(r).verb, "leave")
				local before = r.refreshed
				send(r, {
					kind = "left",
					station = STATION,
					why = "not a person",
					text = "You were taken out of the game. Only people can play",
				})
				t.eq(r.refreshed, before + 1, "the camera goes back to the player's own")
				t.eq(FakeEngine.bound(), 0)
				t.truthy(has(r.toasts, "You were taken out of the game"))
				t.eq(r.gui.Enabled, false)
				-- the other reasons each say something
				for _, why in { "idle", "too far", "finished" } do
					send(
						r,
						{ kind = "joined", station = STATION, game = "bowling", label = "Lane 3", lane = 3, seat = 1 }
					)
					local n = #r.toasts
					send(r, { kind = "left", station = STATION, why = why })
					t.truthy(#r.toasts > n, `leaving because "{why}" says something`)
					t.truthy(#r.toasts[#r.toasts] > 15)
				end
				-- a refusal while not in any game (the lane was in use) still shows its words
				send(
					r,
					{ kind = "refused", text = "a game is in progress: wait for it to finish or try another table" }
				)
				t.truthy(has(r.toasts, "a game is in progress"))
				-- a throw on a lane I am only watching is handled without a game open
				local script =
					RollScript.build({ offset = 0, angle = 0, power = 0.7, spin = 0 }, PinModel.fullRack(), 2)
				send(r, { kind = "roll", station = "bowling_lane_1", lane = 1, seat = 1, script = script })
				send(r, { kind = "rack", station = "bowling_lane_1", lane = 1, mask = PinModel.fullRack() })
				t.eq(r.client.active(), nil)
			end)
		end
	)
end
