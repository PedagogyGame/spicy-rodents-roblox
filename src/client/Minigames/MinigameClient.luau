--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.MinigameClient
-- The minigame framework's client half (BUILD_PLAN §1.3 client frame, D28; brief v2 §13a, §15): walk up to a
-- lane, the dartboard or Madame Acorna and press E (the ProximityPrompts are the server's); the server seats you
-- and this opens the game: MinigameUI (how to play, controls, scorecard, banners, meter, Leave / Start now /
-- Play again), the game's controller (Minigames/BowlingClient, DartsClient; the fortune teller is a short
-- show), the game's camera (a scripted camera while it is your go; your own camera and legs back between
-- turns) and Q to leave. People only: the prompts are switched off on this screen while you are an animal or
-- in a vehicle, and while you are already playing; E then never also asks for a vehicle (PossessionClient
-- checks the "PromptVisible" / "InMinigame" attributes this sets on the local player).
-- Net: Minigame.Input { gameId, seat, verb, args } out; Minigame.State in (joined, state, event, dart, fortune,
-- left, refused; and for bowling "roll": one throw's script, sent to everyone and played back on the lane's
-- parts by BowlingPlayback whether or not you are in that game, and "rack": a throw was cut short).
-- Bowling extras here: the scorecard is rebuilt only when it changes, the end card (ranked scores, strikes,
-- spares, misses, Play again / Leave, the reset countdown), and a refusal is handed to the controller so a
-- refused throw puts the bowler straight back to aiming.
-- Interface: start(opts) -> Client { active() -> stationId? }; opts = { state: () -> { species, device },
--   current: () -> Model?, toast: (text, seconds?) -> (), refreshCamera: () -> (), flushInput: (() -> ())? }
-- Every game here follows three rules of the main client: its own camera shots sit between CameraRig.hold(true)
-- and CameraRig.hold(false) (camera() / releaseCamera() below), or the orbit camera would overwrite them; its
-- panels ask for the cursor through MinigameUI (CameraRig.wantCursor); and at each hand-over of the keys
-- (a game opens, a game closes, a controller's turn begins) pending input is flushed.

local Import = require("../Import")
local AlleyLayout = Import.shared("Attractions/AlleyLayout") :: typeof(require("../../shared/Attractions/AlleyLayout"))
local Data = Import.shared("Data") :: typeof(require("../../shared/Data"))
local InputMap = require("../Input/InputMap")
local CameraRig = require("../Camera/CameraRig")
local MinigameUI = require("../UI/MinigameUI")
local BowlingClient = require("./BowlingClient")
local BowlingPlayback = require("./BowlingPlayback")
local DartsClient = require("./DartsClient")
local MinigameSounds = require("./MinigameSounds")
local Referee = Import.shared("Minigames/Bowling/Referee") :: typeof(require("../../shared/Minigames/Bowling/Referee"))
local RollScript =
	Import.shared("Minigames/Bowling/RollScript") :: typeof(require("../../shared/Minigames/Bowling/RollScript"))

local MinigameClient = {}

local FORTUNE_HELP = {
	how = {
		"Madame Acorna reads your fortune for free: no coins, no prizes, never any money.",
		"Three of a kind on the reels is a Grand Omen.",
	},
	keys = { "E  pull the lever again", "Q  walk away" },
}

local CAMERA_BIND = "SpicyMinigameCamera"

function MinigameClient.start(opts: { [string]: any }): any
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local UIS = game:GetService("UserInputService")
	local PPS = game:GetService("ProximityPromptService")
	local player = Players.LocalPlayer
	local net = ReplicatedStorage:WaitForChild("Net", 30)
	local inputR = net and net:WaitForChild("Minigame.Input", 10) :: RemoteEvent?
	local stateR = net and net:WaitForChild("Minigame.State", 10) :: RemoteEvent?
	if inputR == nil or stateR == nil then
		warn("MinigameClient: Net Minigame remotes missing; the alley's games are off on this screen")
		return {
			active = function()
				return nil
			end,
		}
	end
	local ui = MinigameUI.new()
	local place: { x: number, z: number, floorY: number, yaw: number }? = nil -- AlleyLayout.Place
	pcall(function()
		local mod = Data.default():module("Attractions") :: any
		local a = mod and mod.attractions and mod.attractions[1]
		if a then
			place = { x = a.place.x, z = a.place.z, floorY = a.place.floorY, yaw = a.place.yaw }
		end
	end)

	local active: { [string]: any }? = nil -- { station, game, seat, controller }
	local camOn = false
	local camCF: CFrame? = nil
	local camFov = 70
	local defaultFov = workspace.CurrentCamera.FieldOfView

	local function send(verb: string, args: { any }?)
		local a = active
		if a == nil then
			return
		end
		(inputR :: RemoteEvent):FireServer({ gameId = a.station, seat = a.seat or 1, verb = verb, args = args or {} })
	end

	local camSnap = false
	local function camera(cf: CFrame, fov: number?, snap: boolean?)
		camCF = cf
		camFov = fov or 70
		camSnap = camSnap or snap == true
		if not camOn then
			camOn = true
			CameraRig.hold(true) -- the orbit camera stops writing while the game's own shot is up
			RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 2, function()
				local c = workspace.CurrentCamera
				if camCF then
					c.CameraType = Enum.CameraType.Scriptable
					if camSnap then
						-- a cut between shots: no swoop
						camSnap = false
						c.CFrame = camCF
						c.FieldOfView = camFov
					else
						c.CFrame = c.CFrame:Lerp(camCF, 0.35)
						c.FieldOfView = c.FieldOfView + (camFov - c.FieldOfView) * 0.25
					end
				end
			end)
		end
	end
	local function releaseCamera()
		if camOn then
			camOn = false
			camCF = nil
			RunService:UnbindFromRenderStep(CAMERA_BIND)
			CameraRig.hold(false)
			workspace.CurrentCamera.FieldOfView = defaultFov
			if opts.refreshCamera then
				opts.refreshCamera()
			else
				workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
			end
		end
	end
	local controlsOff = false
	local function controls(on: boolean)
		controlsOff = not on
		InputMap.setCharacterControls(on)
	end

	local lastButtons = ""
	local function setButtons(list: { { string } })
		-- the same buttons again (every state message) leave the bar alone
		local ids = {}
		for _, b in list do
			table.insert(ids, b[1] .. "=" .. b[2])
		end
		local sig = table.concat(ids, ",")
		if sig == lastButtons and ui:isOpen() then
			return
		end
		lastButtons = sig
		ui:buttons(list, function(id: string)
			if id == "leave" then
				send("leave")
			elseif id == "start" then
				send("start")
			elseif id == "addai" then
				send("addai")
			elseif id == "again" then
				send("again")
			elseif id == "501" or id == "cricket" then
				send("mode", { id })
			end
		end)
	end

	-- The keys change hands when a game opens and when it closes. A press made on the other side must not fire
	-- on this one (the Space that bowled is not a jump; an E from the walk up is not a pull of the lever).
	local function flushInput()
		if opts.flushInput then
			opts.flushInput()
		end
	end

	local lastCard = ""
	local function close()
		local a = active
		active = nil
		lastButtons = ""
		lastCard = ""
		ui:summary(nil)
		player:SetAttribute("InMinigame", nil)
		if a and a.controller then
			a.controller:stop()
		end
		releaseCamera()
		if controlsOff then
			controls(true)
		end
		ui:close()
		flushInput()
	end

	local function open(msg: { [string]: any })
		if active then
			close()
		end
		flushInput()
		local p = place
		active = { station = msg.station, game = msg.game, seat = msg.seat, lane = msg.lane }
		player:SetAttribute("InMinigame", msg.station)
		local ctx = {
			place = p,
			lane = msg.lane,
			ui = ui,
			send = send,
			camera = camera,
			releaseCamera = releaseCamera,
			controls = controls,
			setButtons = setButtons,
			toast = opts.toast,
			body = function(): Model?
				return opts.current()
			end,
		}
		if msg.game == "bowling" and p then
			ui:open("bowling", `Bowling - {msg.label}`, BowlingClient.HELP);
			(active :: any).controller = BowlingClient.new(ctx)
			setButtons({ { "start", "Start now" }, { "addai", "Add a computer" }, { "leave", "Leave (Q)" } })
		elseif msg.game == "darts" and p then
			ui:open("darts", "Darts", DartsClient.HELP);
			(active :: any).controller = DartsClient.new(ctx)
			setButtons({
				{ "501", "501" },
				{ "cricket", "Cricket" },
				{ "addai", "+ Computer" },
				{ "start", "Start" },
				{ "leave", "Leave (Q)" },
			})
		elseif msg.game == "fortune_machine" then
			ui:open("fortune", "Madame Acorna", FORTUNE_HELP)
			setButtons({ { "again", "Pull again" }, { "leave", "Walk away (Q)" } })
		else
			ui:open(msg.game, tostring(msg.label), { how = { "" }, keys = { "Q  leave" } })
			setButtons({ { "leave", "Leave (Q)" } })
		end
		opts.toast(`You joined {msg.label}. Q leaves.`, 3)
	end

	stateR.OnClientEvent:Connect(function(msg: { [string]: any })
		-- (pcall of a function that returns nothing still returns the error on failure; the checker
		-- counts one value)
		local ok, err = (pcall :: any)(function()
			local kind = msg.kind
			local a = active
			if kind == "joined" then
				open(msg)
			elseif kind == "refused" then
				-- never silent: the words on screen, and the controller learns its input did not go in
				opts.toast(tostring(msg.text), 4)
				if a and a.controller and a.controller.onRefused then
					a.controller:onRefused(msg)
				end
			elseif kind == "roll" then
				-- a bowling throw on ANY lane (you may only be watching): play the server's script on the
				-- lane's parts. A damaged script is not played; the server's own copy of the motion shows.
				local script, why = RollScript.check(msg.script)
				local lane = tonumber(msg.lane)
				if script == nil or lane == nil then
					warn(`MinigameClient: a bowling throw could not be played ({why})`)
				else
					BowlingPlayback.play(place, lane, script, MinigameSounds.play)
				end
				-- the bowler is told either way: the server HAS counted this throw, so their controller must
				-- stop waiting for an answer (with no script it simply does not ride the camera behind the ball)
				if a and msg.station == a.station and a.controller and a.controller.onRoll then
					a.controller:onRoll(msg, if lane then script else nil)
				end
			elseif kind == "rack" then
				local lane = tonumber(msg.lane)
				if lane and type(msg.mask) == "table" then
					BowlingPlayback.stop(lane, place, msg.mask)
				end
			elseif a == nil or msg.station ~= a.station then
				return
			elseif kind == "state" then
				a.seat = msg.you or a.seat
				local view = msg.view
				a.phase = view.phase
				-- the scorecard is only rebuilt when what it shows has changed (state arrives every second)
				local sig = ""
				pcall(function()
					local g = view.game
					sig = game:GetService("HttpService"):JSONEncode({
						view.phase,
						view.turn,
						view.seats,
						g and g.seats,
						g and g.mode,
						view.mode,
						msg.you,
					})
				end)
				if sig == "" or sig ~= lastCard then
					lastCard = sig
					if a.game == "bowling" then
						ui:scoreBowling(view, msg.you)
					elseif a.game == "darts" then
						ui:scoreDarts(view, msg.you)
					end
				end
				if a.controller then
					a.controller:onState(msg)
				end
				-- (as two flags: tested in the branches themselves, the checker takes the first test's
				-- failing for "it is the fortune machine" and objects to the second)
				local fortune, bowling = a.game == "fortune_machine", a.game == "bowling"
				if view.phase == "done" and not fortune then
					setButtons({ { "again", "Play again" }, { "leave", "Leave (Q)" } })
				elseif view.phase == "playing" and bowling then
					setButtons({ { "leave", "Leave (Q)" } })
				end
				-- bowling's end card: ranked scores and what to press, with the reset counting down
				if a.game == "bowling" and view.phase == "done" then
					ui:summary(Referee.summary(view), msg.you, view.doneLeft, function()
						send("again")
					end, function()
						send("leave")
					end)
				else
					ui:summary(nil)
				end
			elseif kind == "event" then
				ui:banner(tostring(msg.text), msg.big == true)
				if msg.mark == "X" then
					MinigameSounds.play("strike", 1)
				elseif msg.mark == "/" then
					MinigameSounds.play("spare", 1)
				end
			elseif kind == "dart" then
				ui:banner(tostring(msg.text), msg.event == "checkout" or msg.event == "win" or msg.event == "bust")
			elseif kind == "fortune" then
				-- the show: the camera on the cabinet while the reels spin, then the printed card
				local p = place
				if p then
					local f = AlleyLayout.FORTUNE
					local eye = Vector3.new(AlleyLayout.toWorld(p, f.x - 3.6, 5.2, f.d - 3.6))
					local look = Vector3.new(AlleyLayout.toWorld(p, f.x, 3.4, f.d))
					camera(CFrame.lookAt(eye, look), 45)
				end
				ui:status("The reels are spinning...")
				local reveal = tonumber(msg.reveal) or 2.5
				task.delay(reveal, function()
					local title = if msg.card == "omen"
						then "A GRAND OMEN"
						elseif msg.card == "taunt" then "THE MACHINE SAYS"
						else "YOUR FORTUNE"
					ui:card(title, tostring(msg.line or ""), 8)
					ui:status("Pull again (E) or walk away (Q)")
					releaseCamera()
				end)
			elseif kind == "left" then
				if a.game == "fortune_machine" and msg.why == "finished" then
					-- keep the card up a moment; the cabinet frees itself for the next pull
					player:SetAttribute("InMinigame", nil)
					active = nil
					task.delay(5, function()
						if active == nil then
							ui:close()
						end
					end)
				else
					close()
					if type(msg.text) == "string" and msg.text ~= "" then
						opts.toast(msg.text, 4)
					elseif msg.why == "idle" then
						opts.toast("You were taken off the lane: two turns in a row went unplayed", 4)
					elseif msg.why == "too far" then
						opts.toast("You walked away from the game", 3)
					elseif msg.why == "not a person" then
						opts.toast("You were taken out of the game", 3)
					elseif msg.why == "finished" then
						opts.toast("That game is over and the lane has reset. Press E at a lane to play again.", 4)
					elseif msg.why == "left" then
						opts.toast("You left the game", 2)
					end
				end
			end
		end)
		if not ok then
			warn(`MinigameClient: {err}`)
		end
	end)

	-- Q leaves, H toggles the help card, Space starts a lobby early
	UIS.InputBegan:Connect(function(io: InputObject, processed: boolean)
		if InputMap.ignore(io, processed) then
			return
		end
		local a = active
		if a == nil then
			return
		end
		local k = io.KeyCode
		if k == Enum.KeyCode.Q or k == Enum.KeyCode.ButtonB then
			send("leave")
		elseif k == Enum.KeyCode.H then
			ui:toggleHelp()
		elseif k == Enum.KeyCode.E and a.game == "fortune_machine" then
			send("again")
		elseif k == Enum.KeyCode.Space and a.phase == "lobby" then
			send("start")
		end
	end)

	-- prompts: people only, not while playing; record whether one is on screen (E then is the prompt's)
	local shown: { [ProximityPrompt]: boolean } = {}
	PPS.PromptShown:Connect(function(prompt: ProximityPrompt)
		if prompt:GetAttribute("Minigame") ~= nil or prompt:GetAttribute("Door") ~= nil then
			shown[prompt] = true
			player:SetAttribute("PromptVisible", true)
		end
	end)
	PPS.PromptHidden:Connect(function(prompt: ProximityPrompt)
		shown[prompt] = nil
		if next(shown) == nil then
			player:SetAttribute("PromptVisible", nil)
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < 0.3 then
			return
		end
		acc = 0
		local st = opts.state()
		local person = st.species == "human" and st.device == nil
		local att = workspace:FindFirstChild("Attractions")
		local alley = att and att:FindFirstChild("BowlingAlley")
		local folder = alley and alley:FindFirstChild("MinigamePrompts")
		if folder then
			for _, part in folder:GetChildren() do
				local prompt = part:FindFirstChildOfClass("ProximityPrompt")
				if prompt then
					local want = person and active == nil
					if prompt.Enabled ~= want then
						prompt.Enabled = want
					end
				end
			end
		end
		-- the push-bar doors are for people too (a squirrel's E is its grab)
		local doors = alley and alley:FindFirstChild("Doors")
		if doors then
			for _, d in doors:GetDescendants() do
				if d:IsA("ProximityPrompt") and d.Enabled ~= person then
					d.Enabled = person
				end
			end
		end
		-- the possession changed under us (picked another body): the server drops the seat; mirror it
		if active and not person then
			send("leave")
		end
	end)

	return {
		active = function(): string?
			return if active then active.station else nil
		end,
	}
end

return MinigameClient
