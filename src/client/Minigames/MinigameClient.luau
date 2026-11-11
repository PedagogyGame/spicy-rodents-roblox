--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.MinigameClient
-- The minigame framework's client half (BUILD_PLAN §1.3 client frame, D28; brief v2 §13, §15), and it names no
-- game: walk up to a station (a lane, the dartboard, a table, a court) and press E (the ProximityPrompts are the
-- server's); the server seats you and this opens the game from the registry (Client/Minigames/ClientGames; what
-- a game may supply is in Client/Minigames/ClientGame): MinigameUI with the game's help card, buttons, scorecard
-- and end card, the game's controller, the game's camera (a scripted camera while it is your go; your own
-- camera and legs back between turns) and Q to leave. People only: the prompts are switched off on this screen
-- while you are an animal or in a vehicle, and while you are already playing; E then never also asks for a
-- vehicle (PossessionClient checks the "PromptVisible" / "InMinigame" attributes this sets on the local player).
-- Net: Minigame.Input { gameId, seat, verb, args } out; Minigame.State in. The framework's own kinds: joined
-- (opens the game; carries the station's site and place), state (scorecard, buttons, end card, the controller's
-- onState), event (a banner), left (closes it, always with words), refused (words on screen; the controller's
-- onRefused, so a refused input puts the player straight back in control). Every other kind is the game's own:
-- one a game lists in `kinds` was sent to EVERYONE and goes to that game's `watch` whether or not you are in
-- it (a bowling throw is played back on the lane you are only watching), and then, like any other kind of the
-- station you are at, to the controller's onMessage.
-- Interface: start(opts) -> Client { active() -> stationId? }; opts = { state: () -> { species, device },
--   current: () -> Model?, toast: (text, seconds?) -> (), refreshCamera: () -> (), flushInput: (() -> ())? }
-- Every game here follows three rules of the main client: its own camera shots sit between CameraRig.hold(true)
-- and CameraRig.hold(false) (camera() / releaseCamera() below), or the orbit camera would overwrite them; its
-- panels ask for the cursor through MinigameUI (CameraRig.wantCursor); and at each hand-over of the keys
-- (a game opens, a game closes, a controller's turn begins) pending input is flushed.

local Import = require("../Import")
local Data = Import.shared("Data") :: typeof(require("../../shared/Data"))
local Games = Import.shared("Minigames/Games") :: typeof(require("../../shared/Minigames/Games"))
local Sites = Import.shared("Minigames/Sites") :: typeof(require("../../shared/Minigames/Sites"))
local InputMap = require("../Input/InputMap")
local CameraRig = require("../Camera/CameraRig")
local MinigameUI = require("../UI/MinigameUI")
local ClientGame = require("./ClientGame")
local ClientGames = require("./ClientGames")
local MinigameSounds = require("./MinigameSounds")

local MinigameClient = {}

type Place = ClientGame.Place

local CAMERA_BIND = "SpicyMinigameCamera"
local PLAIN_HELP = { how = { "" }, keys = { "Q  leave" } }
local LEAVE = { "leave", "Leave (Q)" }
-- what a player taken off a table reads when neither the server nor the game has its own words
local IDLE_WORDS = "You were taken out of the game: two turns in a row went unplayed"
local FINISHED_WORDS = "That game is over and the table has reset. Press E there to play again."

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
		warn("MinigameClient: Net Minigame remotes missing; the minigames are off on this screen")
		return {
			active = function()
				return nil
			end,
		}
	end
	local ui = MinigameUI.new()

	-- Where each site stands: told by the server when you join; before that (a throw on a lane you are only
	-- watching) read from the site's baked model, or failing that from the compiled data, the bowling alley
	-- first and the expansion venues only if asked for.
	local learned: { [string]: Place } = {}
	local alleySites: { [string]: Place }? = nil
	local allSites: { [string]: Place }? = nil
	local stationSite: { [string]: string } = {}
	local function dataSites(expansion: boolean): { [string]: Place }
		local out: { [string]: Place } = {}
		pcall(function()
			out = Sites.fromData(Data.default(), expansion)
		end)
		return out
	end
	local function sitePlace(site: string): Place?
		if learned[site] then
			return learned[site]
		end
		-- the site's baked model says where it stands (the bake writes Site and the Origin attributes on it)
		local att = workspace:FindFirstChild("Attractions")
		for _, m in if att then att:GetChildren() else {} do
			if m:GetAttribute("Site") == site then
				local x, z = m:GetAttribute("OriginX"), m:GetAttribute("OriginZ")
				local floorY, yaw = m:GetAttribute("FloorY"), m:GetAttribute("Yaw")
				if
					type(x) == "number"
					and type(z) == "number"
					and type(floorY) == "number"
					and type(yaw) == "number"
				then
					local p: Place = { x = x, z = z, floorY = floorY, yaw = yaw }
					learned[site] = p
					return p
				end
			end
		end
		local near = alleySites or dataSites(false)
		alleySites = near
		if near[site] then
			return near[site]
		end
		local all = allSites or dataSites(true)
		allSites = all
		return all[site]
	end
	local function siteOf(station: string): string?
		if stationSite[station] == nil then
			local near = alleySites or dataSites(false)
			alleySites = near
			for _, def in Games.stations(near) do
				stationSite[def.id] = def.site
			end
			if stationSite[station] == nil then
				local all = allSites or dataSites(true)
				allSites = all
				for _, def in Games.stations(all) do
					stationSite[def.id] = def.site
				end
			end
		end
		return stationSite[station]
	end
	local function placeOf(msg: { [string]: any }): Place?
		local site = msg.site
		local told = Sites.place(msg)
		if told then
			if type(site) == "string" then
				learned[site] = told
			end
			return told
		end
		if type(site) ~= "string" and type(msg.station) == "string" then
			site = siteOf(msg.station)
		end
		return if type(site) == "string" then sitePlace(site) else nil
	end

	local active: { [string]: any }? = nil -- { station, game, seat, controller, cg, modes, phase }
	local lingering: any = nil -- the controller of a game whose card is still up after the server let go
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
			-- a button's id is the verb it sends; one of the lobby's choices is sent as the mode
			local a = active
			local modes = a and a.modes
			if type(modes) == "table" and table.find(modes, id) then
				send("mode", { id })
			else
				send(id)
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

	local function endLinger()
		local c = lingering
		lingering = nil
		if c then
			c:stop()
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
		endLinger()
		flushInput()
		local p = placeOf(msg)
		local cg = ClientGames.get(msg.game)
		local spec = Games.get(msg.game)
		local a: { [string]: any } = {
			station = msg.station,
			game = msg.game,
			seat = msg.seat,
			lane = msg.lane,
			cg = cg,
			modes = spec and spec.rules and spec.rules.MODES,
			computers = spec ~= nil and spec.computers ~= nil and #spec.computers > 0,
		}
		active = a
		player:SetAttribute("InMinigame", msg.station)
		local label = tostring(msg.label)
		local ctx: ClientGame.Ctx = {
			station = msg.station,
			game = msg.game,
			label = label,
			place = p,
			lane = msg.lane,
			index = msg.index or msg.lane,
			variant = msg.variant,
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
			sound = MinigameSounds.play,
		}
		-- (a game whose controller needs to know where its station stands is not opened without that)
		if cg and (p ~= nil or cg.placeless == true or cg.new == nil) then
			local title = if cg.title then cg.title(msg) else (spec and spec.title) or label
			ui:open(msg.game, title, cg.help or PLAIN_HELP)
			if cg.new then
				a.controller = cg.new(ctx)
			end
			setButtons((cg.buttons and cg.buttons("joined", nil)) or { LEAVE })
		else
			ui:open(msg.game, label, PLAIN_HELP)
			setButtons({ LEAVE })
		end
		opts.toast(`You joined {msg.label}. Q leaves.`, 3)
	end

	stateR.OnClientEvent:Connect(function(msg: { [string]: any })
		-- (pcall of a function that returns nothing still returns the error on failure; the checker
		-- counts one value)
		local ok, err = (pcall :: any)(function()
			local kind = msg.kind
			local a = active
			local owner = if type(kind) == "string" then ClientGames.ownerOf(kind) else nil
			if kind == "joined" then
				open(msg)
			elseif kind == "refused" then
				-- never silent: the words on screen, and the controller learns its input did not go in
				opts.toast(tostring(msg.text), 4)
				if a and a.controller and a.controller.onRefused then
					a.controller:onRefused(msg)
				end
			elseif owner then
				-- a game's message to everyone (you may only be watching): the game shows it; the player
				-- seated at that station hears of it too (their controller must stop waiting for an answer)
				local watched = if owner.watch then owner.watch(msg, placeOf(msg)) else nil
				if a and msg.station == a.station and a.controller and a.controller.onMessage then
					a.controller:onMessage(msg, watched)
				end
			elseif a == nil or msg.station ~= a.station then
				return
			elseif kind == "state" then
				a.seat = msg.you or a.seat
				local view = msg.view
				local cg = a.cg :: ClientGame.ClientGame?
				a.phase = view.phase
				-- the scorecard is only rebuilt when what it shows has changed (state arrives every second)
				local sig = ""
				pcall(function()
					local g = view.game
					-- (no holes: a nil in the middle of a list is where an encoder may stop reading it)
					sig = game:GetService("HttpService"):JSONEncode({
						view.phase,
						view.turn or false,
						view.seats,
						(g and g.seats) or false,
						view.mode or false,
						msg.you or false,
						(cg and cg.cardSig and cg.cardSig(view)) or false,
					})
				end)
				if sig == "" or sig ~= lastCard then
					lastCard = sig
					if cg and cg.card then
						ui:clearCard()
						cg.card(ui.card, view, msg.you, MinigameUI.kit)
					end
				end
				if a.controller and a.controller.onState then
					a.controller:onState(msg)
				end
				local list: { { string } }? = nil
				if cg and cg.buttons then
					list = cg.buttons(view.phase, view)
				elseif view.phase == "lobby" then
					-- a game with no buttons of its own gets the framework's
					list = { { "start", "Start now" } }
					if a.computers then
						table.insert(list, { "addai", "Add a computer" })
					end
					table.insert(list, LEAVE)
				elseif view.phase == "done" then
					list = { { "again", "Play again" }, LEAVE }
				else
					list = { LEAVE }
				end
				if list then
					setButtons(list)
				end
				-- the end card: ranked scores and what to press, with the reset counting down
				local sum = if cg and cg.endCard and view.phase == "done" then cg.endCard(view, msg.you) else nil
				if sum then
					ui:summary(sum, msg.you, view.doneLeft, function()
						send("again")
					end, function()
						send("leave")
					end)
				else
					ui:summary(nil)
				end
			elseif kind == "event" then
				ui:banner(tostring(msg.text), msg.big == true)
				if a.controller and a.controller.onMessage then
					a.controller:onMessage(msg, nil)
				end
			elseif kind == "left" then
				local cg = a.cg :: ClientGame.ClientGame?
				if cg and cg.linger and msg.why == "finished" then
					-- keep the card up a moment; the station frees itself for the next player
					player:SetAttribute("InMinigame", nil)
					lingering = a.controller
					active = nil
					task.delay(cg.linger, function()
						if active == nil then
							endLinger()
							ui:close()
						end
					end)
				else
					close()
					local words = cg and cg.words
					if type(msg.text) == "string" and msg.text ~= "" then
						opts.toast(msg.text, 4)
					elseif msg.why == "idle" then
						opts.toast((words and words.idle) or IDLE_WORDS, 4)
					elseif msg.why == "too far" then
						opts.toast("You walked away from the game", 3)
					elseif msg.why == "not a person" then
						opts.toast("You were taken out of the game", 3)
					elseif msg.why == "finished" then
						opts.toast((words and words.finished) or FINISHED_WORDS, 4)
					elseif msg.why == "left" then
						opts.toast("You left the game", 2)
					end
				end
			elseif a.controller and a.controller.onMessage then
				-- a kind of the game's own
				a.controller:onMessage(msg, nil)
			end
		end)
		if not ok then
			warn(`MinigameClient: {err}`)
		end
	end)

	-- Q leaves, H toggles the help card, Space starts a lobby early; a game may add keys of its own
	UIS.InputBegan:Connect(function(io: InputObject, processed: boolean)
		if InputMap.ignore(io, processed) then
			return
		end
		local a = active
		if a == nil then
			return
		end
		local k = io.KeyCode
		local cg = a.cg :: ClientGame.ClientGame?
		local own = cg and cg.keys and cg.keys[k.Name]
		if k == Enum.KeyCode.Q or k == Enum.KeyCode.ButtonB then
			send("leave")
		elseif k == Enum.KeyCode.H then
			ui:toggleHelp()
		elseif own then
			send(own)
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
		-- every baked place with games in it (the bowling alley, the venues) keeps its prompts in its own folder
		local att = workspace:FindFirstChild("Attractions")
		for _, site in if att then att:GetChildren() else {} do
			local folder = site:FindFirstChild("MinigamePrompts")
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
			local doors = site:FindFirstChild("Doors")
			if doors then
				for _, d in doors:GetDescendants() do
					if d:IsA("ProximityPrompt") and d.Enabled ~= person then
						d.Enabled = person
					end
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
