--!strict
-- StarterPlayer.StarterPlayerScripts.Client.UI.Hud
-- The minimal W1 HUD: one line saying what the player is looking at and one saying what to press
-- (the owner-facing build rule in docs/HANDOFF.md §4: say on screen what this is and what to press,
-- show progress while loading, never ignore input silently), plus a transient toast for refusals and
-- the squirrel's sprint meter (a bar that empties while sprinting; red while out of fumes).
-- Interface: start() -> Hud { set(title, hint), toast(text, seconds?), meter(fraction?, winded?) };
--   meterLook(fraction, winded) -> { scale, color = { r, g, b }, label } (pure)
-- No side effects on require.

export type Hud = {
	set: (title: string, hint: string) -> (),
	toast: (text: string, seconds: number?) -> (),
	meter: (fraction: number?, winded: boolean?) -> (), -- nil hides it
}

local Hud = {}

-- How the sprint meter is drawn for a meter at `fraction` (0..1): amber, red while out of fumes (the
-- owner's wording, 2026-11-10).
function Hud.meterLook(fraction: number, winded: boolean): { scale: number, color: { number }, label: string }
	local f = math.clamp(fraction, 0, 1)
	return {
		scale = f,
		color = if winded then { 214, 68, 54 } else { 255, 170, 60 },
		label = if winded then "OUT OF FUMES" else "SPRINT",
	}
end

function Hud.start(): Hud
	local player = game:GetService("Players").LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "SpicyHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	local function label(name: string, y: number, size: number): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.AnchorPoint = Vector2.new(0.5, 1)
		l.Position = UDim2.new(0.5, 0, 1, y)
		l.Size = UDim2.new(0.9, 0, 0, size + 6)
		l.BackgroundTransparency = 0.45
		l.BackgroundColor3 = Color3.new(0, 0, 0)
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextSize = size
		l.Font = Enum.Font.GothamMedium
		l.TextWrapped = true
		l.Text = ""
		l.Parent = gui
		return l
	end
	local title = label("Title", -44, 18)
	local hint = label("Hint", -12, 15)
	local toast = label("Toast", -90, 16)
	toast.Visible = false
	-- sprint meter: a slim bar above the title, hidden until a squirrel body reports one
	local bar = Instance.new("Frame")
	bar.Name = "SprintMeter"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -72)
	bar.Size = UDim2.fromOffset(220, 12)
	bar.BackgroundColor3 = Color3.new(0, 0, 0)
	bar.BackgroundTransparency = 0.45
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local barText = Instance.new("TextLabel")
	barText.Name = "Label"
	barText.Size = UDim2.fromScale(1, 1)
	barText.BackgroundTransparency = 1
	barText.TextColor3 = Color3.new(1, 1, 1)
	barText.TextStrokeTransparency = 0.4
	barText.TextSize = 10
	barText.Font = Enum.Font.GothamBold
	barText.Text = "SPRINT"
	barText.ZIndex = 2
	barText.Parent = bar
	gui.Parent = player:WaitForChild("PlayerGui")
	local toastToken = 0
	return {
		set = function(t: string, h: string)
			title.Text = t
			hint.Text = h
		end,
		toast = function(text: string, seconds: number?)
			toastToken += 1
			local mine = toastToken
			toast.Text = text
			toast.Visible = true
			task.delay(seconds or 2.5, function()
				if toastToken == mine then
					toast.Visible = false
				end
			end)
		end,
		meter = function(fraction: number?, winded: boolean?)
			if fraction == nil then
				bar.Visible = false
				return
			end
			local look = Hud.meterLook(fraction, winded == true)
			fill.Size = UDim2.fromScale(look.scale, 1)
			fill.BackgroundColor3 = Color3.fromRGB(look.color[1], look.color[2], look.color[3])
			barText.Text = look.label
			bar.Visible = true
		end,
	}
end

return Hud
