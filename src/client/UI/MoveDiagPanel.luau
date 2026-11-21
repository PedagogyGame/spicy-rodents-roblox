--!strict
-- StarterPlayer.StarterPlayerScripts.Client.UI.MoveDiagPanel
-- The owner's movement diagnostics on screen (Shared/Movement/MoveDiag): a small plain-text panel, top left, off until
-- F8 is pressed, for the place's owner only (and anybody in Studio's own play test). It shows what the server's
-- movement validator counted in the last second (Net "Move.Diag", sent to the owner once a second: packets in and
-- taken, flags by code, snaps, pins, validator errors, what judging costs) and this client's own side
-- (Controllers/MotorHealth: packets sent a second, motor step errors; its frames a second). Nothing here changes play.
-- Cost: one TextLabel; while hidden a frame counter only; while shown its text is set twice a second.
-- Interface: start(opts?) -> Handle { toggle(), shown() -> boolean, stop() }?; isOwner(player) -> boolean;
--   text(report?, client?) -> string (pure); REFRESH
-- No side effects on require.

local Import = require("../Import")
local MoveDiag = Import.shared("Movement/MoveDiag") :: typeof(require("../../shared/Movement/MoveDiag"))
local MotorHealth = require("../Controllers/MotorHealth")

local MoveDiagPanel = {}

MoveDiagPanel.REFRESH = 0.5 -- seconds between two writes of the panel's text

export type Handle = { toggle: () -> (), shown: () -> boolean, stop: () -> () }

-- The place's owner, or Studio's own play test (the rule the server sends by: Boot/Game.placeOwner).
function MoveDiagPanel.isOwner(player: any): boolean
	local ok, yes = pcall(function(): boolean
		if game:GetService("RunService"):IsStudio() then
			return true
		end
		return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
	end)
	return ok and yes == true
end

-- The panel's text (pure): the server's report and the client's own numbers, one line each.
function MoveDiagPanel.text(report: any, client: any): string
	return table.concat(MoveDiag.lines(report, client), "\n")
end

-- start(opts?): the panel for this player, nil for anyone but the owner. opts.parent: the gui's parent (default
-- PlayerGui); opts.net: the Net folder (default ReplicatedStorage.Net).
function MoveDiagPanel.start(opts: { parent: Instance?, net: Instance? }?): Handle?
	local o: { parent: Instance?, net: Instance? } = opts or {}
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")
	local player = Players.LocalPlayer
	if not MoveDiagPanel.isOwner(player) then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MoveDiag"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Enabled = false
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Position = UDim2.fromOffset(8, 8)
	label.Size = UDim2.fromOffset(430, 10)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.35
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Code
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.Text = ""
	label.Parent = gui
	gui.Parent = o.parent or player:WaitForChild("PlayerGui")

	local report: any = nil
	local conns: { RBXScriptConnection } = {}
	local net = o.net or game:GetService("ReplicatedStorage"):WaitForChild("Net", 10)
	local remote = if net then net:FindFirstChild("Move.Diag") else nil
	if remote then
		table.insert(
			conns,
			(remote :: any).OnClientEvent:Connect(function(r: any)
				if type(r) == "table" then
					report = r
				end
			end)
		)
	end
	-- frames a second and packets sent a second, over each REFRESH
	local frames, since, fps, sentRate = 0, os.clock(), 0, 0
	local sentWas = MotorHealth.read().sent
	table.insert(
		conns,
		RunService.RenderStepped:Connect(function()
			frames += 1
			local now = os.clock()
			local span = now - since
			if span < MoveDiagPanel.REFRESH then
				return
			end
			local health = MotorHealth.read()
			fps, sentRate = frames / span, (health.sent - sentWas) / span
			frames, since, sentWas = 0, now, health.sent
			if gui.Enabled then
				label.Text = MoveDiagPanel.text(
					report,
					{ fps = fps, sent = sentRate, errors = health.errors, firstError = health.firstError }
				)
			end
		end)
	)
	local function toggle()
		gui.Enabled = not gui.Enabled
		if gui.Enabled then
			local health = MotorHealth.read()
			label.Text = MoveDiagPanel.text(
				report,
				{ fps = fps, sent = sentRate, errors = health.errors, firstError = health.firstError }
			)
		end
	end
	table.insert(
		conns,
		UserInputService.InputBegan:Connect(function(io: InputObject)
			-- (F8 is free in the Roblox client; taken even while a text box has the focus: a function key types nothing)
			if io.KeyCode == (Enum.KeyCode :: any)[MoveDiag.KEY] then
				toggle()
			end
		end)
	)
	return {
		toggle = toggle,
		shown = function(): boolean
			return gui.Enabled
		end,
		stop = function()
			for _, c in conns do
				c:Disconnect()
			end
			gui:Destroy()
		end,
	}
end

return MoveDiagPanel
