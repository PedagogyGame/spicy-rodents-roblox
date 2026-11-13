--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Paintball.Hud
-- The paintball HUD (checklist PB-2, PB-7; brief v2 §13: "a match timer, scoreboard and end card"): what a
-- player in the match reads without looking for it, and nothing in the middle of the view but the
-- crosshair. It decides nothing: every frame it shows what SeatCore holds.
--   the crosshair  four arms and a dot; the arms stand wider and dimmer whenever a press would not
--                  leave as a ball this instant (the marker down, reloading, protected, in a spawn
--                  room): the gap is the "not ready" light. The hit marker is an X over it, shown
--                  only when the server said you tagged someone.
--   the top        both scores in the teams' colours either side of the clock, yours underlined
--   the pips       five, at the bottom; a bar that fills through the reload
--   the status     one line under the crosshair, by priority: tagged out (by whom, the count back),
--                  protected, safe in your own room, the last refusal
--   tagged         a tick on a ring round the crosshair pointing at where the ball came from, and
--                  paint on the goggles that clears over Tuning.goggleSecs
--   the feed       who tagged whom, top right, a few lines, each a few seconds
--   the briefing   the framework's own How-to-play card is the controls card (shown through the
--                  briefing, put away when the match goes live; H brings it back), the side you are
--                  on, and the count to the start
--   the scoreboard held on G / View / SCORES: both sides, tags and times out; with it a button the
--                  size of a pixel that is Modal, which is what frees a first-person mouse to press
--                  Leave and Change sides
--   the end card   the framework's (ClientGame.endCard); this adds the WBLW bulletin's awards beside it
--   touch          FIRE at the lower right as a plain Frame (it does not sink its touch: a drag that
--                  starts on it still turns the view; Controls reads the touch itself), a second FIRE
--                  on the left, RELOAD, CROUCH, SCORES
-- Its own ScreenGui ("PaintballHud" under PlayerGui), destroyed by stop().
-- Interface: new(seat, ctx, tuning?) -> Hud { gui, touch, step(dt), stop(), fireRect() -> (x0, y0, x1, y1) }

local Import = require("../../Import")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local ClientGame = require("../ClientGame")
local SeatCore = require("./SeatCore")
local Tuning = require("./Tuning")

export type Hud = {
	gui: ScreenGui,
	touch: { [string]: GuiObject }, -- FireRight (a Frame), FireLeft, Reload, Crouch, Scores (buttons); empty without touch
	step: (self: Hud, dt: number) -> (),
	stop: (self: Hud) -> (),
	fireRect: (self: Hud) -> (number, number, number, number),
}

local Hud = {}

local R = Contract.Rules
local WHITE = { 245, 245, 245 }
local NAVY = { 16, 20, 44 }
local ROWS = R.teamMax

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function teamRgb(team: number): { number }
	local t = Contract.TEAMS[team]
	return if t then t.color else WHITE
end

local function frame(name: string, parent: Instance, size: UDim2, pos: UDim2, color: { number }?, alpha: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = rgb(color or NAVY)
	f.BackgroundTransparency = alpha or 0
	f.Parent = parent
	return f
end

local function label(
	name: string,
	parent: Instance,
	size: UDim2,
	pos: UDim2,
	color: { number }?,
	bold: boolean?
): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = pos
	t.Text = ""
	t.TextColor3 = rgb(color or WHITE)
	t.Font = if bold then Enum.Font.GothamBold else Enum.Font.GothamMedium
	t.TextScaled = true
	t.TextStrokeTransparency = 0.5
	t.Parent = parent
	return t
end

local function round(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function clockText(seconds: number): string
	local n = math.max(0, math.ceil(seconds))
	return `{n // 60}:{string.format("%02d", n % 60)}`
end

function Hud.new(seat: SeatCore.Seat, ctx: ClientGame.Ctx, tuning: typeof(Tuning.T)?): Hud
	local tune = tuning or Tuning
	local UIS = game:GetService("UserInputService")
	local player = game:GetService("Players").LocalPlayer
	local camera = workspace.CurrentCamera
	local gui = Instance.new("ScreenGui")
	gui.Name = "PaintballHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 19 -- under the framework's own (its buttons and its end card stay on top)
	gui.Parent = player:WaitForChild("PlayerGui")

	local function set(t: TextLabel, text: string)
		if t.Text ~= text then
			t.Text = text
		end
	end
	local function show(g: GuiObject, on: boolean)
		if g.Visible ~= on then
			g.Visible = on
		end
	end

	-- the crosshair and the hit marker
	local cross = frame("Cross", gui, UDim2.fromOffset(2, 2), UDim2.new(0.5, -1, 0.5, -1), WHITE)
	local arms: { Frame } = {}
	for i = 1, 4 do
		arms[i] = frame(`Arm{i}`, cross, UDim2.fromOffset(2, 2), UDim2.fromOffset(0, 0), WHITE)
	end
	local hit = frame("Hit", gui, UDim2.fromOffset(0, 0), UDim2.fromScale(0.5, 0.5), WHITE, 1)
	for i = 1, 4 do
		local a = frame(`X{i}`, hit, UDim2.fromOffset(3, 12), UDim2.fromOffset(0, 0), WHITE)
		local sx, sy = if i % 2 == 1 then 1 else -1, if i <= 2 then 1 else -1
		a.Position = UDim2.fromOffset(sx * 11 - 1, sy * 11 - 6)
		a.Rotation = if sx * sy > 0 then -45 else 45
	end
	hit.Visible = false

	-- the top: score, clock, score
	local top = frame("Top", gui, UDim2.fromOffset(260, 38), UDim2.new(0.5, -130, 0, 8), NAVY, 0.25)
	round(top, 10)
	local score1 = label("Score1", top, UDim2.fromOffset(70, 30), UDim2.fromOffset(8, 4), teamRgb(1), true)
	local clock = label("Clock", top, UDim2.fromOffset(96, 30), UDim2.fromOffset(82, 4), WHITE, true)
	local score2 = label("Score2", top, UDim2.fromOffset(70, 30), UDim2.fromOffset(182, 4), teamRgb(2), true)
	local mine = frame("Mine", top, UDim2.fromOffset(54, 3), UDim2.fromOffset(16, 33), WHITE)
	local phaseLine = label("Phase", gui, UDim2.fromOffset(520, 24), UDim2.new(0.5, -260, 0, 50), WHITE, true)
	local count =
		label("Count", gui, UDim2.fromOffset(240, 110), UDim2.new(0.5, -120, 0.28, -55), { 255, 214, 92 }, true)

	-- the pips and the reload
	local pips = frame("Pips", gui, UDim2.fromOffset(150, 40), UDim2.new(0.5, -75, 1, -70), NAVY, 1)
	local pip: { Frame } = {}
	for i = 1, R.magazine do
		pip[i] = frame(`Pip{i}`, pips, UDim2.fromOffset(20, 20), UDim2.fromOffset(8 + (i - 1) * 28, 0), WHITE)
		round(pip[i], 10)
	end
	local reloadBar = frame("Reload", pips, UDim2.fromOffset(134, 6), UDim2.fromOffset(8, 26), { 50, 56, 90 })
	local reloadFill = frame("Fill", reloadBar, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), { 255, 214, 92 })
	local reloadText =
		label("ReloadText", pips, UDim2.fromOffset(134, 16), UDim2.fromOffset(8, -20), { 255, 214, 92 }, true)

	-- the status line, the ring's tick, the goggles
	local status = label("Status", gui, UDim2.fromOffset(560, 30), UDim2.new(0.5, -280, 0.5, 70), WHITE, true)
	local tick = frame("TaggedFrom", gui, UDim2.fromOffset(8, 34), UDim2.new(0.5, -4, 0.5, -17), WHITE)
	tick.Visible = false
	local goggles = frame("Goggles", gui, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), WHITE, 1)
	goggles.Visible = false
	local blobs: { Frame } = {}
	for i, at in { { 0.22, 0.3, 300 }, { 0.6, 0.55, 380 }, { 0.72, 0.18, 220 }, { 0.38, 0.72, 260 } } do
		blobs[i] =
			frame(`Blob{i}`, goggles, UDim2.fromOffset(at[3], at[3]), UDim2.new(at[1], -at[3] / 2, at[2], -at[3] / 2))
		round(blobs[i], at[3] // 2)
	end

	-- the feed
	local feed = frame("Feed", gui, UDim2.fromOffset(360, 100), UDim2.new(1, -372, 0, 8), NAVY, 1)
	local lines: { TextLabel } = {}
	for i = 1, tune.feedLines do
		lines[i] = label(`Line{i}`, feed, UDim2.fromOffset(360, 20), UDim2.fromOffset(0, (i - 1) * 23), WHITE, false)
		lines[i].TextXAlignment = Enum.TextXAlignment.Right
	end

	-- the scoreboard
	local board = frame(
		"Board",
		gui,
		UDim2.fromOffset(640, 120 + ROWS * 26),
		UDim2.new(0.5, -320, 0.5, -(120 + ROWS * 26) / 2),
		NAVY,
		0.1
	)
	round(board, 12)
	board.Visible = false
	label("Title", board, UDim2.fromOffset(620, 28), UDim2.fromOffset(10, 8), { 255, 214, 92 }, true).Text =
		"SCOREBOARD"
	local boardHint =
		label("Hint", board, UDim2.fromOffset(620, 20), UDim2.fromOffset(10, 92 + ROWS * 26), { 140, 236, 236 }, false)
	local heads: { TextLabel } = {}
	local rows: { { { name: TextLabel, tags: TextLabel, outs: TextLabel, back: Frame } } } = {}
	for team = 1, 2 do
		local x = 10 + (team - 1) * 315
		heads[team] =
			label(`Head{team}`, board, UDim2.fromOffset(305, 24), UDim2.fromOffset(x, 40), teamRgb(team), true)
		local keys = label(
			`Keys{team}`,
			board,
			UDim2.fromOffset(110, 14),
			UDim2.fromOffset(x + 195, 68),
			{ 140, 236, 236 },
			true
		)
		keys.Text = "TAGS   OUT"
		rows[team] = {}
		for i = 1, ROWS do
			local y = 86 + (i - 1) * 26
			local back =
				frame(`Row{team}_{i}`, board, UDim2.fromOffset(305, 23), UDim2.fromOffset(x, y), { 26, 32, 66 })
			round(back, 5)
			local name = label("Name", back, UDim2.fromOffset(185, 19), UDim2.fromOffset(6, 2), WHITE, false)
			name.TextXAlignment = Enum.TextXAlignment.Left
			rows[team][i] = {
				back = back,
				name = name,
				tags = label("Tags", back, UDim2.fromOffset(46, 19), UDim2.fromOffset(196, 2), { 255, 214, 92 }, true),
				outs = label("Outs", back, UDim2.fromOffset(46, 19), UDim2.fromOffset(250, 2), WHITE, false),
			}
		end
	end

	-- the bulletin's awards, beside the framework's end card
	local awards = frame("Awards", gui, UDim2.fromOffset(300, 200), UDim2.new(0, 12, 0.5, -100), NAVY, 0.1)
	round(awards, 12)
	awards.Visible = false
	label("Channel", awards, UDim2.fromOffset(280, 22), UDim2.fromOffset(10, 8), { 255, 214, 92 }, true).Text =
		"WBLW CHANNEL 7 SPORTS"
	local awardLines: { TextLabel } = {}
	for i = 1, 6 do
		awardLines[i] =
			label(`Award{i}`, awards, UDim2.fromOffset(280, 22), UDim2.fromOffset(10, 12 + i * 26), WHITE, false)
		awardLines[i].TextXAlignment = Enum.TextXAlignment.Left
	end

	-- what frees a first-person mouse while there is something to press
	local modal = Instance.new("TextButton")
	modal.Name = "Modal"
	modal.Text = ""
	modal.BackgroundTransparency = 1
	modal.Size = UDim2.fromOffset(1, 1)
	modal.Position = UDim2.fromOffset(0, 0)
	modal.Modal = true
	modal.Visible = false
	modal.Parent = gui

	-- touch
	local touch: { [string]: GuiObject } = {}
	if UIS.TouchEnabled then
		local layer = frame("Touch", gui, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), NAVY, 1)
		local function at(spec: { number }): (UDim2, UDim2)
			return UDim2.fromOffset(spec[3], spec[3]), UDim2.new(spec[1], -spec[3] / 2, spec[2], -spec[3] / 2)
		end
		local size, pos = at(tune.touchFire)
		-- (a Frame, not a button, and not Active: the touch goes on to the camera as a drag)
		local fire = frame("FireRight", layer, size, pos, { 200, 70, 50 }, 0.35)
		fire.Active = false
		round(fire, tune.touchFire[3] // 2)
		label("Text", fire, UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.3), WHITE, true).Text = "FIRE"
		touch.FireRight = fire
		for _, item in
			{
				{ "FireLeft", "FIRE", tune.touchFireLeft },
				{ "Reload", "RELOAD", tune.touchReload },
				{ "Crouch", "CROUCH", tune.touchCrouch },
				{ "Scores", "SCORES", tune.touchScores },
			} :: { { any } }
		do
			local b = Instance.new("TextButton")
			b.Name = item[1]
			b.Text = item[2]
			b.Size, b.Position = at(item[3])
			b.BackgroundColor3 = if item[1] == "FireLeft" then rgb({ 200, 70, 50 }) else rgb({ 40, 50, 100 })
			b.BackgroundTransparency = 0.35
			b.TextColor3 = rgb(WHITE)
			b.Font = Enum.Font.GothamBold
			b.TextScaled = true
			b.Parent = layer
			round(b, item[3][3] // 2)
			touch[item[1]] = b
		end
	end

	local hud = { gui = gui, touch = touch } :: Hud
	local lastPhase = ""
	local liveSince: number? = nil
	local boardAcc = 1

	function hud.fireRect(_self: Hud): (number, number, number, number)
		local spec = tune.touchFire
		local fire = touch.FireRight
		if fire and typeof(fire.AbsoluteSize) == "Vector2" and fire.AbsoluteSize.X > 0 then
			local p, s = fire.AbsolutePosition, fire.AbsoluteSize
			return p.X, p.Y, p.X + s.X, p.Y + s.Y
		end
		local vp = camera.ViewportSize
		local cx, cy, half = vp.X * spec[1], vp.Y * spec[2], spec[3] / 2
		return cx - half, cy - half, cx + half, cy + half
	end

	local function drawBoard()
		for team = 1, 2 do
			local list = {}
			for _, slot in seat.slots do
				if slot.on and slot.team == team then
					table.insert(list, slot)
				end
			end
			table.sort(list, function(a, b)
				if a.tags ~= b.tags then
					return a.tags > b.tags
				end
				return a.id < b.id
			end)
			local t = Contract.TEAMS[team]
			set(heads[team], `{if t then string.upper(t.name) else ""}   {seat.scores[team] or 0}`)
			for i = 1, ROWS do
				local row = rows[team][i]
				local slot = list[i]
				show(row.back, slot ~= nil)
				if slot then
					local you = slot.id == seat.you
					set(row.name, (seat.names[slot.id] or `Player {slot.id}`) .. (if you then " (you)" else ""))
					set(row.tags, tostring(slot.tags))
					set(row.outs, tostring(slot.outs))
					row.back.BackgroundColor3 = if you then rgb({ 28, 96, 104 }) else rgb({ 26, 32, 66 })
				end
			end
		end
		set(
			boardHint,
			if UIS.TouchEnabled
				then "Leave the match and Change sides: the buttons at the lower left"
				else "Leave the match / Change sides: the buttons at the lower left   (gamepad: Y / D-pad up)"
		)
	end

	-- The framework's end card says "Play again" and "Leave (Q)": in a match that starts itself and keeps Q for
	-- nothing, the first is not there to press and the second is plain "Leave".
	local function dressSummary()
		local ui = ctx.ui
		local card = if ui then ui.summaryFrame else nil
		if card == nil or card.Visible ~= true then
			return
		end
		for _, c in card:GetChildren() do
			if c:IsA("TextButton") then
				if c.Text == "Play again" then
					c.Visible = false
				elseif c.Text == "Leave (Q)" then
					c.Text = "Leave the match"
					c.Position = UDim2.new(0.5, -75, 0, c.Position.Y.Offset)
				end
			end
		end
	end

	function hud.step(_self: Hud, dt: number)
		local now = seat.now
		local phase = seat.phase
		local ended = phase == "ended"
		local starting = phase == "briefing" and now < seat.endsAt
		local ui = ctx.ui
		-- the framework's own pieces: its empty scorecard is put away; its help card is the controls card
		if ui and ui.card and ui.card.Visible ~= false then
			ui.card.Visible = false
		end
		local stage = if starting then "briefing" elseif ended then "ended" else "live"
		if stage ~= lastPhase then
			if ui and ui.helpFrame then
				ui.helpFrame.Visible = stage == "briefing"
			end
			if stage == "live" and lastPhase == "briefing" then
				liveSince = now
			end
			lastPhase = stage
		end

		-- the crosshair
		local aiming = not seat.out and not ended and not seat.board and phase ~= ""
		show(cross, aiming)
		if aiming then
			local ready = seat:ready(now)
			local gap = if ready then tune.crossGap else tune.crossWide
			local arm = tune.crossArm
			local a = if ready then 0 else 0.5
			arms[1].Position, arms[1].Size = UDim2.fromOffset(gap + 1, 0), UDim2.fromOffset(arm, 2)
			arms[2].Position, arms[2].Size = UDim2.fromOffset(-gap - arm + 1, 0), UDim2.fromOffset(arm, 2)
			arms[3].Position, arms[3].Size = UDim2.fromOffset(0, gap + 1), UDim2.fromOffset(2, arm)
			arms[4].Position, arms[4].Size = UDim2.fromOffset(0, -gap - arm + 1), UDim2.fromOffset(2, arm)
			for _, piece in arms do
				piece.BackgroundTransparency = a
			end
		end
		show(hit, now - seat.hitAt < tune.hitMarkerSecs)

		-- the top
		set(score1, tostring(seat.scores[1] or 0))
		set(score2, tostring(seat.scores[2] or 0))
		mine.Position = UDim2.fromOffset(if seat.team == 2 then 190 else 16, 33)
		show(mine, seat.team ~= 0)
		local left = seat.endsAt - now
		if phase == "briefing" and not starting then
			left += R.matchSecs -- live by the clock; the server's own word is on its way
		end
		set(clock, if ended then "FULL TIME" elseif phase == "" then "" else clockText(left))
		clock.TextColor3 = if not starting and not ended and left <= 30 then rgb({ 255, 90, 80 }) else rgb(WHITE)
		local side = Contract.TEAMS[seat.team]
		set(
			phaseLine,
			if starting
				then `BRIEFING   You are {if side then string.upper(side.name) else "?"}   The match starts in {math.ceil(
					left
				)} s`
				else ""
		)
		local since = liveSince
		if starting and left <= tune.briefCount then
			set(count, tostring(math.max(1, math.ceil(left))))
			show(count, true)
		elseif since ~= nil and now - since < 0.9 then
			set(count, "GO!")
			show(count, true)
		else
			show(count, false)
		end

		-- the pips
		local rounds = seat.mag.rounds
		local team = teamRgb(seat.team)
		for i = 1, R.magazine do
			pip[i].BackgroundColor3 = if i <= rounds then rgb(team) else rgb({ 50, 56, 90 })
		end
		local r = seat:reloading(now)
		show(reloadBar, r ~= nil)
		show(reloadText, r ~= nil)
		if r ~= nil then
			reloadFill.Size = UDim2.fromScale(r, 1)
			set(reloadText, "RELOADING")
		end
		show(pips, not ended and phase ~= "")

		-- the status line
		local words = ""
		if seat.out then
			local by = seat.names[seat.outBy] or "someone"
			words = `TAGGED OUT by {by}   back in {math.max(1, math.ceil(seat.outUntil - now))}`
		elseif ended or phase == "" then
			words = ""
		elseif now < seat.safeUntil and not starting then
			words = `PROTECTED  {string.format("%.1f", seat.safeUntil - now)}`
		elseif seat.inRoom then
			words = "SAFE in your spawn room: no firing from here"
		elseif seat.note ~= "" then
			words = seat.note
		end
		set(status, words)

		-- where it came from: a tick on a ring, turned towards the one who tagged you
		local showTick = false
		if seat.out then
			local from = seat.tagFrom
			if from then
				local dx, dz = from.x - seat.x, from.z - seat.z
				if dx * dx + dz * dz > 1 then
					-- the bearing against the look: 0 ahead, positive to the left (a yaw)
					local bearing = math.atan2(-dx, -dz) - seat.yaw
					local sx, sy = -math.sin(bearing), -math.cos(bearing)
					tick.Position = UDim2.new(0.5, sx * 120 - 4, 0.5, sy * 120 - 17)
					tick.Rotation = -math.deg(bearing)
					tick.BackgroundColor3 = rgb(teamRgb(if seat.team == 1 then 2 else 1))
					showTick = true
				end
			end
		end
		show(tick, showTick)
		local wet = (now - seat.goggleAt) / tune.goggleSecs
		show(goggles, wet < 1)
		if wet < 1 then
			local paint = rgb(teamRgb(if seat.team == 1 then 2 else 1))
			for _, b in blobs do
				b.BackgroundColor3 = paint
				b.BackgroundTransparency = 0.15 + 0.85 * wet
			end
		end

		-- the feed
		for i = 1, tune.feedLines do
			local line = seat.feed[i]
			set(lines[i], if line then line.text else "")
			if line then
				lines[i].TextColor3 = if line.mine then rgb({ 255, 214, 92 }) else rgb(teamRgb(line.team))
			end
		end

		-- the scoreboard, and the cursor for what is pressed with it
		local boardOn = seat.board and not ended
		show(board, boardOn)
		if boardOn then
			boardAcc += dt
			if boardAcc >= 0.25 then
				boardAcc = 0
				drawBoard()
			end
		else
			boardAcc = 1
		end
		show(modal, boardOn or ended)

		-- the end: the bulletin's awards, and the framework's card dressed
		local result = seat.result
		local card = if type(result) == "table" then result.card else nil
		local list = if type(card) == "table" and type(card.awards) == "table" then card.awards else nil
		show(awards, ended and list ~= nil and #list > 0)
		if ended then
			if list then
				for i, l in awardLines do
					local award = list[i]
					set(l, if award then `{award.title}: {seat.names[award.id] or "?"}` else "")
				end
			end
			dressSummary()
		end
	end

	function hud.stop(_self: Hud)
		gui:Destroy()
	end

	return hud
end

return Hud
