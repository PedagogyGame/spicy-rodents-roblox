--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Pinball.Dmd
-- The dot-matrix display on the player's own screen (as Pinball FX and Zen put one over the table): from the
-- player's eye over the lockdown bar the cabinet's backglass is above the picture, so everything it says is
-- said here too, drawn every frame from the frame the player is looking at (their own live machine, or the
-- other player's ball they follow): the score of the player up (ACORN ATTACK's as its reels show it), the ball
-- and the player, and the callout with its value (SKILL SHOT, BALL SAVED, EXTRA BALL, JACKPOT, the bonus
-- counting out with its multiplier). Between callouts it says what to shoot for (the table's rule line). A TILT
-- WARNING and a TILT are red and flash: the one thing a player must not miss, and the sounds are not in yet.
-- Engine-light: a Frame with three labels, written only when what they say changes.
-- Interface: new(parent) -> Dmd; place(d, x, y, w, h) (pixels of the parent); draw(d, tbl, frame, m?, opts?)
--   (opts: { score? (the reels' number), clock? (seconds, for the flashing) }); show(d, on); destroy(d);
--   texts(d) -> { score, info, say } (as drawn); RED; AMBER; FLASH_HZ

local Import = require("../../Import")
local HighScores =
	Import.shared("Minigames/Pinball/HighScores") :: typeof(require("../../../shared/Minigames/Pinball/HighScores"))
local Machine =
	Import.shared("Minigames/Pinball/Machine") :: typeof(require("../../../shared/Minigames/Pinball/Machine"))

local Dmd = {}

Dmd.AMBER = { 255, 150, 40 }
Dmd.RED = { 255, 56, 40 }
Dmd.FLASH_HZ = 4

local SAY = Machine.SAY
local PHASE = Machine.PHASE

export type Dmd = {
	frame: Frame,
	score: TextLabel,
	info: TextLabel,
	say: TextLabel,
	shown: { [string]: any },
}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

function Dmd.new(parent: Instance): Dmd
	local frame = Instance.new("Frame")
	frame.Name = "PinballDMD"
	frame.BackgroundColor3 = Color3.fromRGB(14, 8, 4)
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(70, 44, 20)
	stroke.Thickness = 2
	stroke.Parent = frame
	local function line(name: string, y: number, h: number, font: Enum.Font): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.03, y)
		l.Size = UDim2.fromScale(0.94, h)
		l.Font = font
		l.TextScaled = true
		l.TextWrapped = true
		l.TextColor3 = rgb(Dmd.AMBER)
		l.Text = ""
		l.Parent = frame
		return l
	end
	return {
		frame = frame,
		score = line("Score", 0.04, 0.4, Enum.Font.Arcade),
		info = line("Info", 0.46, 0.2, Enum.Font.Arcade),
		say = line("Say", 0.68, 0.28, Enum.Font.Arcade),
		shown = {},
	}
end

function Dmd.place(d: Dmd, x: number, y: number, w: number, h: number)
	d.frame.Position = UDim2.fromOffset(x, y)
	d.frame.Size = UDim2.fromOffset(w, h)
end

function Dmd.show(d: Dmd, on: boolean)
	if d.frame.Visible ~= on then
		d.frame.Visible = on
	end
end

local function set(d: Dmd, label: TextLabel, key: string, text: string, color: { number })
	if d.shown[key] ~= text then
		d.shown[key] = text
		label.Text = text
	end
	local ck = key .. ":c"
	if d.shown[ck] ~= color then
		d.shown[ck] = color
		label.TextColor3 = rgb(color)
	end
end

-- draw(d, tbl, f, m, opts): one frame of the game (a Stream frame) and, when there is one, the machine it came
-- from (for the rule line and the bonus count).
function Dmd.draw(d: Dmd, tbl: any, f: any, m: any?, opts: { [string]: any }?)
	local o: { [string]: any } = opts or {}
	local up = f.up or 1
	local players = #f.scores
	set(d, d.score, "score", HighScores.commas(o.score or f.scores[up] or 0), Dmd.AMBER)
	local info
	if f.phase == PHASE.OVER then
		info = "GAME OVER"
	else
		info = `BALL {f.ball or 1}   PLAYER {up}{if players > 1 then ` OF {players}` else ""}`
		if f.saveOn and not f.tilted then
			info ..= "   SAVE"
		end
	end
	set(d, d.info, "info", info, Dmd.AMBER)
	local say, color = "", Dmd.AMBER
	local flash = ((o.clock or os.clock()) * Dmd.FLASH_HZ) % 1 < 0.5
	if f.tilted then
		say, color = "TILT", Dmd.RED
	elseif f.say ~= 0 then
		say = tbl.sheet.text[f.say] or Machine.TEXT[f.say] or ""
		if f.say == SAY.TILT_WARNING then
			color = Dmd.RED
		elseif f.say == SAY.BONUS and m and m.phase == PHASE.BONUS and (m.bonusMult or 1) > 1 then
			say = `BONUS {HighScores.commas(m.bonusBase or 0)} X {m.bonusMult}`
		elseif f.sayValue and f.sayValue > 0 and f.say ~= SAY.SHOOT_AGAIN then
			say ..= `  {HighScores.commas(f.sayValue)}`
		end
	elseif m and f.phase == PHASE.PLAY and m.sheets and m.sheets[m.up] then
		say = tbl.sheet.status(m, m.sheets[m.up])
	end
	set(d, d.say, "say", say, color)
	-- red words flash (the words stay; only their brightness goes)
	local dim = if color == Dmd.RED and not flash then 0.65 else 0
	if d.shown.dim ~= dim then
		d.shown.dim = dim
		d.say.TextTransparency = dim
	end
end

function Dmd.texts(d: Dmd): { string }
	return { d.score.Text, d.info.Text, d.say.Text }
end

function Dmd.destroy(d: Dmd)
	d.frame:Destroy()
end

return Dmd
