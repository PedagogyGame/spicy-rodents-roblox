--!strict
-- StarterPlayer.StarterPlayerScripts.Client.UI.TouchButtons
-- The touch screen's buttons for the keys (owner D40: tablet and phone players can do what keyboard players do). One
-- bar in the right thumb's corner, round and see-through, around (never over) Roblox's jump button, the TRICK button
-- (UI/AirTrickButton), GET OFF (UI/RideHint), STAND (World/SeatGetUp) and the Menu button. Shown only on a touch
-- screen while the last input was not a keyboard, mouse or gamepad; a button shows only while its key does something
-- for this body (shows()): at most five action buttons and three small toggles.
-- Every press is the key's own: InputMap.tap(key) (the sampler's edge and the E / V / F handlers) or InputMap.hold
-- (held keys: the handbrake, the drone's up and down; RUN and SNEAK stay held until tapped again). No server code.
-- Already on touch elsewhere: moving (the thumbstick), a person's jump (Roblox's button), the air trick, RIDE / GET
-- OFF / LAND, SIT and STASH in a branch nook, STAND from a seat, prompts (doors, items, shops, the computer: Roblox's
-- ProximityPrompt is tapped), the kite's arrows, the Menu and keys panel buttons.
-- LEAP sits where the stock jump button would: animals have no Humanoid, so Roblox shows none for them.
-- Cost: 17 small buttons made once; one look ten times a second (a vehicle scan four times a second).
-- Interface: BUTTONS; ACTION_SLOTS; TOGGLE_SLOTS; LEAP_SLOT; AVOID; MAX_ACTIONS; MAX_TOGGLES;
--   shows(ctx) -> (actions: { string }, toggles: { string }) (pure); contextOf(clientState, telescope, inMinigame)
--   -> Context (pure); start(opts) -> stop()
-- No side effects on require.

local InputMap = require("../Input/InputMap")

local TouchButtons = {}

export type Context = {
	role: string?, -- "human" | "squirrel" | "rodent" | "quadruped" (nil: no body)
	device: string?, -- "vehicle" | "drone" | "passenger" | "ride"
	telescope: boolean?,
	minigame: boolean?,
	seated: boolean?,
	viewAllowed: boolean?, -- the camera's V toggle (CameraPolicy toggleAllowed)
	night: boolean?,
	nearVehicle: boolean?, -- a vehicle E would get into (not a shared one: RideHint's RIDE has those)
}

-- what each button is: its words and the key it presses (kind: tap; hold while pressed; toggle: held until tapped
-- again; fn: a call)
export type Button = { label: string, key: string?, kind: string }
local BUTTONS: { [string]: Button } = {
	leap = { label = "LEAP", key = "Space", kind = "tap" },
	grab = { label = "GRAB", key = "E", kind = "tap" },
	drop = { label = "DROP", key = "Q", kind = "tap" },
	bite = { label = "BITE", key = "MouseButton1", kind = "tap" },
	feint = { label = "FEINT", key = "F", kind = "tap" },
	kick = { label = "KICK", key = "F", kind = "tap" },
	enter = { label = "IN", key = "E", kind = "tap" },
	brake = { label = "BRAKE", key = "Space", kind = "hold" },
	up = { label = "UP", key = "Space", kind = "hold" },
	down = { label = "DOWN", key = "Q", kind = "hold" },
	back = { label = "BACK", kind = "fn" },
	zoomIn = { label = "+", kind = "fn" },
	zoomOut = { label = "-", kind = "fn" },
	run = { label = "RUN", key = "LeftShift", kind = "toggle" },
	sneak = { label = "SNEAK", key = "LeftControl", kind = "toggle" },
	night = { label = "NIGHT", key = "N", kind = "tap" },
	view = { label = "VIEW", key = "V", kind = "tap" },
}
TouchButtons.BUTTONS = table.freeze(BUTTONS)

TouchButtons.MAX_ACTIONS = 5
TouchButtons.MAX_TOGGLES = 3

-- rectangles in pixels from the screen's bottom-right corner: { right edge r0, left edge r1, bottom b0, top b1 }
export type Rect = { number }
TouchButtons.LEAP_SLOT = { 30, 100, 20, 90 } :: Rect -- (where a phone's jump button is; animals have none)
TouchButtons.ACTION_SLOTS = table.freeze({
	{ 180, 240, 20, 80 },
	{ 180, 240, 170, 230 },
	{ 250, 310, 170, 230 },
	{ 130, 190, 245, 305 },
	{ 250, 310, 245, 305 },
}) :: { Rect }
TouchButtons.TOGGLE_SLOTS = table.freeze({
	{ 250, 306, 20, 50 },
	{ 250, 306, 56, 86 },
	{ 312, 368, 20, 50 },
}) :: { Rect }
-- what the bar keeps clear of: Roblox's jump button (phone, tablet), TRICK, GET OFF / STAND, Menu, a branch nook's bar
-- (centred 120 up on a 667-wide phone)
TouchButtons.AVOID = table.freeze({
	jumpPhone = { 25, 95, 20, 90 },
	jumpTablet = { 50, 170, 90, 210 },
	trick = { 40, 118, 175, 253 },
	getOffStand = { 30, 150, 175, 219 },
	menu = { 12, 142, 96, 136 },
	nookBar = { 154, 514, 120, 160 },
}) :: { [string]: Rect }

-- shows(ctx): the action buttons and the toggles this body has now, most used first
function TouchButtons.shows(ctx: Context): ({ string }, { string })
	local a: { string }, t: { string } = {}, {}
	if ctx.minigame or ctx.seated or ctx.role == nil then
		return a, t -- (a game's own buttons; STAND gets a seated body up; no body: the menu)
	end
	if ctx.telescope then
		return { "back", "zoomIn", "zoomOut" }, t
	end
	local d = ctx.device
	if d == "vehicle" then
		a = { "brake" }
	elseif d == "drone" then
		a = { "up", "down" }
		t = { "run" }
	elseif d == nil then
		local r = ctx.role
		if r == "human" then
			a = { "kick" }
			if ctx.nearVehicle then
				table.insert(a, "enter")
			end
			t = { "run" }
		elseif r == "squirrel" or r == "rodent" then
			a = { "leap", "grab", "drop" }
			t = { "run", "sneak" }
			if r == "rodent" then
				table.insert(a, 2, "bite")
				table.insert(a, "feint")
				if ctx.night then
					table.insert(t, "night")
				end
			end
		else
			a = { "leap" }
			t = { "run" }
		end
	end
	if ctx.viewAllowed and d ~= "drone" and #t < TouchButtons.MAX_TOGGLES then
		table.insert(t, "view")
	end
	return a, t
end

-- contextOf(st, telescope, inMinigame): the bar's context from PossessionClient's state (the engine adds seated,
-- night and nearVehicle)
function TouchButtons.contextOf(st: { [string]: any }, telescope: boolean, inMinigame: any): Context
	local role: string? = nil
	if st.species == "human" then
		role = "human"
	elseif st.variant == "spicy" or st.species == "rodent" then
		role = "rodent"
	elseif st.species == "squirrel" then
		role = "squirrel"
	elseif st.species ~= nil then
		role = "quadruped"
	end
	local decision = st.decision
	return {
		role = role,
		device = st.device,
		telescope = telescope,
		minigame = inMinigame ~= nil and inMinigame ~= false,
		viewAllowed = type(decision) == "table" and decision.toggleAllowed == true,
	}
end

export type Opts = {
	state: () -> Context,
	telescope: (verb: string) -> (),
}

function TouchButtons.start(opts: Opts): () -> ()
	local UIS = game:GetService("UserInputService")
	if not UIS.TouchEnabled then
		return function() end
	end
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local Lighting = game:GetService("Lighting")
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "TouchButtons"
	gui.ResetOnSpawn = false
	local buttons: { [string]: TextButton } = {}
	local toggled: { [string]: boolean } = {}
	local conns: { RBXScriptConnection } = {}
	local fingers: { [InputObject]: string } = {}
	local function release(id: string)
		local def = TouchButtons.BUTTONS[id]
		if def.key and (def.kind == "hold" or def.kind == "toggle") then
			InputMap.hold(def.key, false)
		end
		toggled[id] = nil
		buttons[id].BackgroundTransparency = 0.35
	end
	for id, def in TouchButtons.BUTTONS do
		local b = Instance.new("TextButton")
		b.Name = id
		b.Text = def.label
		b.AnchorPoint = Vector2.new(1, 1)
		b.BackgroundColor3 = Color3.fromRGB(40, 34, 30)
		b.BackgroundTransparency = 0.35
		b.TextColor3 = Color3.fromRGB(250, 240, 220)
		b.TextSize = if def.kind == "toggle" or id == "night" or id == "view" then 13 else 16
		b.FontFace = Font.fromEnum(Enum.Font.GothamBold)
		b.Visible = false
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = b
		b.Parent = gui
		buttons[id] = b
		table.insert(
			conns,
			b.InputBegan:Connect(function(io: InputObject)
				local kind = io.UserInputType
				if kind ~= Enum.UserInputType.Touch and kind ~= Enum.UserInputType.MouseButton1 then
					return
				end
				local key = def.key
				if def.kind == "fn" or key == nil then
					opts.telescope(id)
				elseif def.kind == "hold" then
					fingers[io] = id
					InputMap.hold(key, true)
					InputMap.tap(key)
				elseif def.kind == "toggle" then
					local on = not toggled[id]
					if on then
						toggled[id] = true
					else
						toggled[id] = nil
					end
					InputMap.hold(key, on)
					b.BackgroundTransparency = if on then 0.05 else 0.35
				else
					InputMap.tap(key)
				end
			end)
		)
	end
	local function lifted(io: InputObject)
		local id = fingers[io]
		if id then
			fingers[io] = nil
			InputMap.hold(TouchButtons.BUTTONS[id].key :: string, false)
		end
	end
	table.insert(conns, UIS.InputEnded:Connect(lifted))
	table.insert(conns, UIS.TouchEnded:Connect(lifted))
	local function place(b: TextButton, r: Rect)
		b.Position = UDim2.new(1, -r[1], 1, -r[3])
		b.Size = UDim2.fromOffset(r[2] - r[1], r[4] - r[3])
	end
	local acc, scanAcc, near = 0, 0, false
	local shown = ""
	table.insert(
		conns,
		RunService.Heartbeat:Connect(function(dt: number)
			acc += dt
			scanAcc += dt
			if acc < 0.1 then
				return
			end
			acc = 0
			local ok, last = pcall(function()
				return UIS:GetLastInputType()
			end)
			local keys = ok
				and (
					last == Enum.UserInputType.Keyboard
					or last == Enum.UserInputType.Gamepad1
					or last == Enum.UserInputType.MouseMovement
				)
			local ctx = opts.state()
			local char = player.Character
			local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
			ctx.seated = hum ~= nil and hum.Sit and ctx.device == nil
			local clock = Lighting.ClockTime
			ctx.night = clock < 6.3 or clock > 17.7
			if scanAcc >= 0.25 then
				scanAcc = 0
				near = false
				local folder = workspace:FindFirstChild("Vehicles")
				local root = if char and ctx.role == "human" then char.PrimaryPart else nil
				if folder and root then
					for _, m in folder:GetChildren() do
						if
							m:IsA("Model")
							and m:GetAttribute("Shared") ~= true
							and (m:GetPivot().Position - root.Position).Magnitude <= 16
						then
							near = true
							break
						end
					end
				end
			end
			ctx.nearVehicle = near
			local actions, toggles = TouchButtons.shows(ctx)
			if keys then
				actions, toggles = {}, {}
			end
			local key = table.concat(actions, ",") .. "|" .. table.concat(toggles, ",")
			if key == shown then
				return
			end
			shown = key
			local want: { [string]: Rect } = {}
			local slot = 0
			for _, id in actions do
				if id == "leap" then
					want[id] = TouchButtons.LEAP_SLOT
				elseif slot < TouchButtons.MAX_ACTIONS then
					slot += 1
					want[id] = TouchButtons.ACTION_SLOTS[slot]
				end
			end
			for i, id in toggles do
				if i <= TouchButtons.MAX_TOGGLES then
					want[id] = TouchButtons.TOGGLE_SLOTS[i]
				end
			end
			for io, id in fingers do
				if want[id] == nil then
					lifted(io)
				end
			end
			for id, b in buttons do
				local r = want[id]
				if r then
					place(b, r)
				elseif b.Visible or toggled[id] then
					release(id)
				end
				b.Visible = r ~= nil
			end
		end)
	)
	gui.Parent = player:WaitForChild("PlayerGui")
	return function()
		for _, c in conns do
			c:Disconnect()
		end
		for id in buttons do
			release(id)
		end
		gui:Destroy()
	end
end

return TouchButtons
