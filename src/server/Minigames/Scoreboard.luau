--!strict
-- ServerScriptService.Server.Minigames.Scoreboard
-- The working scoreboards (brief v2 §13a): the overhead monitor of each bowling lane and the darts chalkboard
-- are SurfaceGuis the server rewrites from the session view (Minigames/Session.view), so every player in the
-- alley sees the same scores. Bowling: the classic ten-frame sheet (two mark boxes per frame, three in the
-- tenth, the running total under them), up to four bowlers, the bowler up highlighted. Darts: 501 remaining
-- or the cricket marks grid. Engine only inside the functions.
-- Interface: bowling(gui, lane, view); darts(gui, view); idle(gui, title, line)

local Scoreboard = {}

local NAVY = Color3.fromRGB(14, 18, 40)
local CELL = Color3.fromRGB(26, 32, 66)
local LIT = Color3.fromRGB(28, 96, 104)
local GOLD = Color3.fromRGB(255, 214, 92)
local CYAN = Color3.fromRGB(140, 236, 236)
local WHITE = Color3.fromRGB(240, 240, 240)

local function clear(gui: Instance)
	for _, c in gui:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function frame(parent: Instance, x: number, y: number, w: number, h: number, color: Color3?): Frame
	local f = Instance.new("Frame")
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color or CELL
	f.BackgroundTransparency = if color then 0 else 1
	f.Parent = parent
	return f
end

local function text(
	parent: Instance,
	s: string,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3?,
	font: Enum.Font?
): TextLabel
	local t = Instance.new("TextLabel")
	t.Position = UDim2.fromScale(x, y)
	t.Size = UDim2.fromScale(w, h)
	t.BackgroundTransparency = 1
	t.Text = s
	t.TextScaled = true
	t.TextColor3 = color or WHITE
	t.Font = font or Enum.Font.GothamBold
	t.Parent = parent
	return t
end

function Scoreboard.idle(gui: Instance, title: string, line: string)
	clear(gui)
	local root = frame(gui, 0, 0, 1, 1, NAVY)
	text(root, title, 0, 0.08, 1, 0.45, GOLD, Enum.Font.FredokaOne)
	text(root, line, 0.04, 0.6, 0.92, 0.25, CYAN)
end

-- view = Session.view(...) with view.game = Bowling.view(...)
function Scoreboard.bowling(gui: Instance, lane: number, view: { [string]: any })
	clear(gui)
	local root = frame(gui, 0, 0, 1, 1, NAVY)
	local g = view.game
	local phase = view.phase
	local status: string
	if phase == "lobby" then
		status = `STARTING IN {view.lobbyLeft or 0}`
	elseif phase == "done" and view.result then
		local r = view.result
		local w = r.winner and view.seats[r.winner]
		status = if w then `{string.upper(w.name)} WINS: {r.scores[r.winner]}` else "GAME OVER: A TIE"
	elseif phase == "playing" and g and view.turn then
		local s = view.seats[view.turn]
		local gs = g.seats[view.turn]
		status = `FRAME {gs.frame}  {string.upper(s and s.name or "")}`
	else
		status = "OPEN"
	end
	text(root, `LANE {lane}`, 0.01, 0.01, 0.3, 0.14, GOLD, Enum.Font.FredokaOne)
	text(root, status, 0.32, 0.02, 0.67, 0.12, CYAN)
	local rows = #view.seats
	if rows == 0 then
		text(root, "Walk up to the lane and press E to bowl", 0.04, 0.45, 0.92, 0.2, WHITE)
		return
	end
	local rowH = math.min(0.2, 0.82 / rows)
	for s = 1, rows do
		local seat = view.seats[s]
		local gs = if g then g.seats[s] else nil
		local y = 0.17 + (s - 1) * (rowH + 0.005)
		local up = view.turn == s and phase == "playing"
		local row = frame(root, 0.005, y, 0.99, rowH, if up then LIT else CELL)
		local name = seat.name
		if seat.gone then
			name ..= " (left)"
		end
		text(row, name, 0.01, 0.1, 0.16, 0.8, if up then GOLD else WHITE)
		local fx0, fw = 0.18, 0.066
		for f = 1, 10 do
			local cell = frame(row, fx0 + (f - 1) * fw, 0, fw - 0.004, 1, Color3.fromRGB(18, 22, 46))
			local marks = if gs and gs.marks[f] then gs.marks[f] else {}
			local boxes = if f == 10 then 3 else 2
			for b = 1, boxes do
				local m = marks[b] or ""
				local bw = 1 / boxes
				text(
					cell,
					m,
					(b - 1) * bw,
					0.02,
					bw,
					0.48,
					if m == "X" or m == "/" then GOLD else WHITE,
					Enum.Font.Code
				)
			end
			local tot = if gs then gs.totals[f] else ""
			text(cell, tostring(tot or ""), 0, 0.5, 1, 0.48, CYAN)
		end
		text(row, if gs then tostring(gs.total) else "0", 0.85, 0.1, 0.14, 0.8, GOLD, Enum.Font.FredokaOne)
	end
end

local CRICKET_ROWS = { "20", "19", "18", "17", "16", "15", "25" }
local function cricketMark(n: number): string
	if n <= 0 then
		return ""
	elseif n == 1 then
		return "/"
	elseif n == 2 then
		return "X"
	end
	return "(X)"
end

function Scoreboard.darts(gui: Instance, view: { [string]: any })
	clear(gui)
	local root = frame(gui, 0, 0, 1, 1, Color3.fromRGB(30, 40, 34))
	local chalk = Color3.fromRGB(236, 236, 220)
	local g = view.game
	local mode = (g and g.mode) or view.mode or "501"
	local title = if mode == "cricket" then "CRICKET" else "501"
	local status = ""
	if view.phase == "lobby" then
		status = `starting in {view.lobbyLeft or 0}`
	elseif view.phase == "done" and view.result then
		local w = view.result.winner and view.seats[view.result.winner]
		status = if w then `{w.name} wins!` else "game over"
	elseif g and view.turn then
		local s = view.seats[view.turn]
		status = `{s and s.name or ""} - dart {g.dart}  round {g.round}`
	end
	text(root, title, 0.02, 0.02, 0.4, 0.14, chalk, Enum.Font.PermanentMarker)
	text(root, status, 0.42, 0.03, 0.56, 0.12, Color3.fromRGB(236, 220, 120), Enum.Font.PermanentMarker)
	local n = #view.seats
	if n == 0 then
		text(root, "walk up and press E", 0.05, 0.4, 0.9, 0.2, chalk, Enum.Font.PermanentMarker)
		return
	end
	if mode == "cricket" and g then
		local colW = 0.8 / n
		for i = 1, n do
			text(root, view.seats[i].name, 0.18 + (i - 1) * colW, 0.18, colW, 0.1, chalk, Enum.Font.PermanentMarker)
			text(
				root,
				tostring(g.seats[i].score),
				0.18 + (i - 1) * colW,
				0.88,
				colW,
				0.1,
				Color3.fromRGB(236, 220, 120),
				Enum.Font.PermanentMarker
			)
		end
		for r, label in CRICKET_ROWS do
			local y = 0.28 + (r - 1) * 0.085
			text(root, if label == "25" then "B" else label, 0.02, y, 0.14, 0.08, chalk, Enum.Font.PermanentMarker)
			for i = 1, n do
				text(
					root,
					cricketMark(g.seats[i].marks[label] or 0),
					0.18 + (i - 1) * colW,
					y,
					colW,
					0.08,
					chalk,
					Enum.Font.PermanentMarker
				)
			end
		end
	else
		for i = 1, n do
			local y = 0.2 + (i - 1) * 0.19
			local score = if g then tostring(g.seats[i].score) else "501"
			local darts = if g and g.seats[i].darts then table.concat(g.seats[i].darts, " ") else ""
			local up = view.turn == i
			text(
				root,
				(if up then "> " else "") .. view.seats[i].name,
				0.02,
				y,
				0.42,
				0.15,
				chalk,
				Enum.Font.PermanentMarker
			)
			text(root, score, 0.45, y, 0.25, 0.15, Color3.fromRGB(236, 220, 120), Enum.Font.PermanentMarker)
			text(root, darts, 0.7, y + 0.02, 0.28, 0.11, chalk, Enum.Font.PermanentMarker)
		end
	end
end

return Scoreboard
