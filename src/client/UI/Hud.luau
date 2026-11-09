--!strict
-- StarterPlayer.StarterPlayerScripts.Client.UI.Hud
-- The minimal W1 HUD: one line saying what the player is looking at and one saying what to press
-- (the owner-facing build rule in docs/HANDOFF.md §4: say on screen what this is and what to press,
-- show progress while loading, never ignore input silently), plus a transient toast for refusals.
-- Interface: start() -> Hud { set(title, hint), toast(text, seconds?) }
-- No side effects on require.

export type Hud = {
	set: (title: string, hint: string) -> (),
	toast: (text: string, seconds: number?) -> (),
}

local Hud = {}

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
	}
end

return Hud
