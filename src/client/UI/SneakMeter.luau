--!strict
-- StarterPlayer.StarterPlayerScripts.Client.UI.SneakMeter
-- The squirrel's sneak meter over the bowling alley's lanes (BRIEF_ADDENDUM D9: "the squirrel must practice
-- sneaking through those rafters or will be spotted"; lane L6 of the roof plan): an eye on the squirrel's own
-- screen that fills as the people below grow suspicious, shown only while its squirrel is on a rafter (or in the
-- vent), with what to do about it in words:
--   calm      the eye, filling amber; no words
--   watched   (filled past WATCH, until it falls back under CALM) the eye orange, and "They're watching: creep
--             (hold Ctrl) or get back in the vent"
--   spotted   the eye full and red, "Spotted!" over it, and the same advice under it
-- The server's Attractions/RafterService decides and writes the player attributes RafterMeter (0..1, nil when not
-- watched) and RafterSeen (true while seen); this only draws them.
-- Interface: WORDS; WATCH; CALM; look(meter?, seen?, wasWatched?) -> Look (pure); start(opts?) -> Handle { stop(),
--   gui } (opts.player: whose attributes, default the local player; opts.parent: where the ScreenGui goes, default
--   their PlayerGui)
-- No side effects on require.

local SneakMeter = {}

SneakMeter.WORDS = {
	spotted = "Spotted!",
	watching = "They're watching: creep (hold Ctrl) or get back in the vent",
}
SneakMeter.WATCH = 0.35 -- the eye this full says they are watching ...
SneakMeter.CALM = 0.25 -- ... until it falls back under this

export type Look = {
	visible: boolean,
	state: string, -- "hidden" | "calm" | "watched" | "spotted"
	fill: number, -- 0..1
	color: { number }, -- r, g, b (0..255)
	shout: string?, -- the big word over the eye
	words: string?, -- the line under it
}

local function mix(a: { number }, b: { number }, f: number): { number }
	return {
		math.floor(a[1] + (b[1] - a[1]) * f + 0.5),
		math.floor(a[2] + (b[2] - a[2]) * f + 0.5),
		math.floor(a[3] + (b[3] - a[3]) * f + 0.5),
	}
end

local AMBER, ORANGE, RED = { 236, 196, 70 }, { 245, 130, 40 }, { 214, 52, 44 }

-- look(meter, seen, wasWatched): how the eye is drawn. `wasWatched`: the last look was "watched" (the words stay
-- up until the eye has emptied back under CALM, so they do not flicker at the line).
function SneakMeter.look(meter: number?, seen: boolean?, wasWatched: boolean?): Look
	if meter == nil then
		return { visible = false, state = "hidden", fill = 0, color = AMBER }
	end
	local m = math.clamp(meter, 0, 1)
	if seen then
		return {
			visible = true,
			state = "spotted",
			fill = 1,
			color = RED,
			shout = SneakMeter.WORDS.spotted,
			words = SneakMeter.WORDS.watching,
		}
	end
	local watched = m >= SneakMeter.WATCH or (wasWatched == true and m >= SneakMeter.CALM)
	if watched then
		return {
			visible = true,
			state = "watched",
			fill = m,
			color = mix(ORANGE, RED, (m - SneakMeter.CALM) / (1 - SneakMeter.CALM)),
			words = SneakMeter.WORDS.watching,
		}
	end
	return { visible = true, state = "calm", fill = m, color = mix(AMBER, ORANGE, m / SneakMeter.WATCH) }
end

export type Handle = { stop: () -> (), gui: ScreenGui }

local function frame(name: string, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function round(parent: Instance)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = parent
end

local function label(name: string, parent: Instance, size: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.3
	l.TextSize = size
	l.Font = Enum.Font.GothamBold
	l.TextWrapped = true
	l.Text = ""
	l.Parent = parent
	return l
end

-- start(opts?): the eye on the screen, following the player's RafterMeter and RafterSeen attributes.
export type Opts = { player: Instance?, parent: Instance? }

function SneakMeter.start(opts: Opts?): Handle
	local o: Opts = opts or {}
	local player = o.player or (game:GetService("Players").LocalPlayer :: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SneakMeter"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	-- above the HUD's bottom lines, to the right of the sprint meter
	local box = frame("Box", gui)
	box.AnchorPoint = Vector2.new(0.5, 1)
	box.Position = UDim2.new(0.5, 0, 1, -96)
	box.Size = UDim2.fromOffset(420, 112)
	box.BackgroundTransparency = 1
	local shout = label("Shout", box, 30)
	shout.Size = UDim2.new(1, 0, 0, 34)
	shout.TextColor3 = Color3.fromRGB(255, 90, 70)
	-- the eye: a pill whose inside fills from the bottom, a pupil in the middle (a CanvasGroup clips the fill to the
	-- rounded shape)
	local eye = Instance.new("CanvasGroup")
	eye.Name = "Eye"
	eye.AnchorPoint = Vector2.new(0.5, 0)
	eye.Position = UDim2.new(0.5, 0, 0, 36)
	eye.Size = UDim2.fromOffset(72, 36)
	eye.BackgroundColor3 = Color3.fromRGB(238, 234, 222)
	eye.BorderSizePixel = 0
	eye.Parent = box
	round(eye)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(40, 34, 30)
	stroke.Parent = eye
	local fill = frame("Fill", eye)
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	local pupil = frame("Pupil", eye)
	pupil.AnchorPoint = Vector2.new(0.5, 0.5)
	pupil.Position = UDim2.fromScale(0.5, 0.5)
	pupil.Size = UDim2.fromOffset(14, 14)
	pupil.BackgroundColor3 = Color3.fromRGB(28, 24, 22)
	pupil.ZIndex = 2
	round(pupil)
	local words = label("Words", box, 16)
	words.Position = UDim2.fromOffset(0, 76)
	words.Size = UDim2.new(1, 0, 0, 36)
	gui.Parent = o.parent or player:WaitForChild("PlayerGui")

	local watched = false
	local function draw()
		local m, seen = player:GetAttribute("RafterMeter"), player:GetAttribute("RafterSeen")
		local look = SneakMeter.look(if type(m) == "number" then m else nil, seen == true, watched)
		watched = look.state == "watched"
		gui.Enabled = look.visible
		if not look.visible then
			return
		end
		fill.Size = UDim2.fromScale(1, look.fill)
		fill.BackgroundColor3 = Color3.fromRGB(look.color[1], look.color[2], look.color[3])
		pupil.Size =
			UDim2.fromOffset(if look.state == "spotted" then 18 else 14, if look.state == "spotted" then 18 else 14)
		shout.Text = look.shout or ""
		shout.Visible = look.shout ~= nil
		words.Text = look.words or ""
		words.Visible = look.words ~= nil
	end
	local conns = {
		player:GetAttributeChangedSignal("RafterMeter"):Connect(draw),
		player:GetAttributeChangedSignal("RafterSeen"):Connect(draw),
	}
	draw()
	return {
		gui = gui,
		stop = function()
			for _, c in conns do
				c:Disconnect()
			end
			gui:Destroy()
		end,
	}
end

return SneakMeter
