--!strict
-- tests/isolated/air_hockey_client.luau: cases for tests/unit/air_hockey_client.spec.luau, run in their own Lune
-- process (tests/lib/Isolated) because they install the fake engine.
-- Air hockey played through all of its glue at once on tests/lib/MinigameRig: the real MinigameService with the
-- game's Table and referee, the real MinigameClient with MinigameUI, the game's Controller and Rink, the fake
-- lagged network with the real Net's schema and rate limit between them, and the table's hardware as fake
-- parts. The player's mouse is moved in pixels and the fake camera turns a pixel into a ray, so a strike goes
-- mouse -> the bed under the pointer -> the player's own simulation -> the log -> the referee -> the score.
-- What the player is SHOWN is read back from the puck and mallet parts after each frame and compared with what
-- the referee decided for that instant (the referee's stream, replayed afterwards tick by tick).
-- Other people are PlayerLike stubs with a Seat of their own driven here (bot()).
-- Interface: return function(t) (the spec shape)
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Layout = require("@shared/Minigames/AirHockey/Layout")
local Referee = require("@shared/Minigames/AirHockey/Referee")
local Replica = require("@shared/Minigames/AirHockey/Replica")
local Rules = require("@shared/Minigames/AirHockey/Rules")
local Seat = require("@shared/Minigames/AirHockey/Seat")
local Sim = require("@shared/Minigames/AirHockey/Sim")
local Wire = require("@shared/Minigames/AirHockey/Wire")
local Controller = require("@client/Minigames/AirHockey/Controller")
local Rink = require("@client/Minigames/AirHockey/Rink")
local MinigameSounds = require("@client/Minigames/MinigameSounds")
local AirHockeyFlow = require("@tests/engine/AirHockeyFlow")
local FakeEngine = require("@tests/lib/FakeEngine")
local Rig = require("@tests/lib/MinigameRig")
local Line = require("../../tools/games/air_hockey/Line")
local roblox = require("@lune/roblox")

local ID, EMBER = Layout.STATION, Layout.STATION_EMBER
local SITE = Layout.SITE
local Key = roblox.Enum.KeyCode

-- What the bake leaves in the games room, as far as the game looks for it.
local function furnish(roots: { [string]: any }, places: { [string]: any })
	-- (each case from nothing: no table remembered from the case before)
	Rink.reset()
	Controller.current = nil
	table.clear(MinigameSounds.counts())
	local place = places[SITE]
	local room = FakeEngine.new("Folder", "GamesRoom")
	room.Parent = roots[SITE]
	local function at(x: number, y: number, z: number): any
		return roblox.CFrame.new(Layout.toWorld(place, x, y, z))
	end
	local model = FakeEngine.model(Layout.MODEL, at(0, 0, 0.9), room)
	local function piece(name: string, x: number, y: number)
		local m = FakeEngine.model(name, at(x, y, 0.915), model)
		m.PrimaryPart = FakeEngine.part("Base", at(x, y, 0.915), m)
	end
	piece(Layout.PUCK, 0, 0)
	piece(Layout.MALLETS[0], 0, -0.8)
	piece(Layout.MALLETS[1], 0, 0.8)
	local board = FakeEngine.part(Layout.SCORE, at(-0.9, 0, 2), model)
	local gui = FakeEngine.new("SurfaceGui", "Gui")
	gui.Parent = board
	local label = FakeEngine.new("TextLabel", "Score")
	label.Text = ""
	label.Parent = gui
	-- (each end's own score, lit in the bed)
	for side = 0, 1 do
		local plate = FakeEngine.part(
			Layout.SCORE_PRINTS[side],
			at(Layout.SCORE_PRINT.x, (side * 2 - 1) * Layout.SCORE_PRINT.y, 0.9),
			model
		)
		local top = FakeEngine.new("SurfaceGui", "Gui")
		top.Parent = plate
		local print = FakeEngine.new("TextLabel", "Score")
		print.Text = ""
		print.Parent = top
	end
end

-- what an end's score print in the bed reads
local function printed(w: Rig.World, side: number): string
	local model = w.roots[SITE]:FindFirstChild("GamesRoom"):FindFirstChild(Layout.MODEL)
	return model:FindFirstChild(Layout.SCORE_PRINTS[side]):FindFirstChild("Gui"):FindFirstChild("Score").Text
end

local function opts(more: { [string]: any }?): Rig.Opts
	local X, D = Layout.stance(0)
	local o: any = { furnish = furnish, stand = { site = SITE, x = X, y = 3, d = D } }
	for k, v in more or {} do
		o[k] = v
	end
	return o
end

local function tableOf(w: Rig.World): any
	return w.svc.stations[ID].tbl
end

-- who is a person in the match on a table: "0" Glacier against the computer, "1" Ember, "2" both
local function Referee_mode(tbl: any): string?
	return Referee.mode(tbl.ref)
end

local function nowTick(w: Rig.World): number
	local ref = tableOf(w).ref
	return (Rig.SERVER_TIME + w.frames / 60 - ref.t0) / Sim.STEP
end

-- where a piece of the hardware stands, in the model's metres
local function where(w: Rig.World, name: string): (number, number)
	local piece = w.roots[SITE]:FindFirstChild("GamesRoom"):FindFirstChild(Layout.MODEL):FindFirstChild(name)
	local p = piece:GetPivot().Position
	return Layout.fromWorld(w.places[SITE], p.X, p.Z)
end

-- the pointer put over a point of the bed (through the camera as it is)
local function point(w: Rig.World, x: number, y: number)
	local wx, wy, wz = Layout.toWorld(w.places[SITE], x, y)
	local px = workspace.CurrentCamera:WorldToViewportPoint(roblox.Vector3.new(wx, wy, wz))
	FakeEngine.uis().mouse = roblox.Vector2.new(px.X, px.Y)
end

-- Another person: a stub with a Seat of their own, fed what the service sends the stub and sending its log back.
local function bot(_w: Rig.World, name: string, hand: any): any
	return { stub = Rig.stub(name), seat = nil, read = 0, hand = hand, refused = {} }
end

local function botFrame(w: Rig.World, b: any)
	local events = b.stub.events
	while b.read < #events do
		b.read += 1
		local msg = events[b.read]
		if msg.kind == "air_hockey_seat" and msg.again then
			if b.seat then
				Seat.resume(b.seat, msg.from)
			end
		elseif msg.kind == "air_hockey_seat" then
			b.seat = Seat.new(msg.side)
			Seat.begin(b.seat, msg.g, msg.from)
		elseif msg.kind == "air_hockey_press" and b.seat then
			Seat.pressed(b.seat, msg.tick)
		elseif msg.kind == "air_hockey" and b.seat then
			Seat.push(b.seat, msg)
		elseif msg.kind == "left" then
			b.seat = nil
		end
	end
	local seat = b.seat
	if seat == nil or seat.replica.game == nil or tableOf(w).ref == nil then
		return
	end
	if seat.ready and b.hand then
		local x, y, serve = b.hand(seat.side, seat.pred, seat.tick)
		Seat.aim(seat, x, y)
		if serve then
			Seat.serve(seat)
		end
	end
	Seat.relax(seat, Rig.DT)
	Seat.step(seat, (Rig.SERVER_TIME + w.frames / 60 - seat.replica.t0) / Sim.STEP, function(from, to, strings)
		local args: { any } = { from, to }
		for _, s in strings do
			table.insert(args, s)
		end
		local ok, why = Rig.input(w, b.stub, ID, "log", args)
		if not ok then
			table.insert(b.refused, tostring(why))
		end
	end)
end

-- Frames of the whole game with the local player's hand on the mouse (hand: where their hand wants to be, given
-- what their own screen shows) and any bots; every frame's drawn puck and mallets are kept in `shown`.
local function play(w: Rig.World, seconds: number, hand: any?, bots: { any }?, shown: { any }?, stop: (() -> boolean)?)
	for _ = 1, math.floor(seconds * 60 + 0.5) do
		if stop and stop() then
			return
		end
		local c = Controller.current
		if hand and c and c.seat and c.seat.ready then
			local x, y = hand(c.seat.side, c.seat.pred, c.seat.tick)
			point(w, x, y)
		end
		Rig.frame(w)
		for _, b in bots or {} do
			botFrame(w, b)
		end
		if shown and tableOf(w).ref then
			local px, py = where(w, Layout.PUCK)
			local ax, ay = where(w, Layout.MALLETS[0])
			local bx, by = where(w, Layout.MALLETS[1])
			local seat = c and c.seat
			table.insert(shown, { nowTick(w), px, py, ax, ay, bx, by, seat and seat.puckAt, seat and seat.farAt })
		end
	end
end

-- What the referee decided, tick by tick, from the stream the client was sent (and, as the second result, how
-- many times the puck was let go in it).
local function truth(w: Rig.World): ({ [number]: { number } }, number)
	local r = Replica.new()
	local out: { [number]: { number } } = {}
	local serves = 0
	for _, msg in w.got do
		if msg.kind == "air_hockey" then
			Replica.push(r, msg)
			out[r.tick] = out[r.tick] or { r.sim.px, r.sim.py, r.sim.p0x, r.sim.p0y, r.sim.p1x, r.sim.p1y }
			Replica.step(r, nil, function(sim: any, tick: number, _hit: boolean, _goal: boolean, served: boolean)
				out[tick] = { sim.px, sim.py, sim.p0x, sim.p0y, sim.p1x, sim.p1y }
				if served then
					serves += 1
				end
			end)
		end
	end
	return out, serves
end

-- A point of the bed on the screen (pixels), through the camera as it is.
local function onScreen(w: Rig.World, x: number, y: number): any
	local wx, wy, wz = Layout.toWorld(w.places[SITE], x, y)
	return (workspace.CurrentCamera:WorldToViewportPoint(roblox.Vector3.new(wx, wy, wz)))
end

-- Every part of the HUD that is drawn now, as rectangles of the screen: { name, x0, y0, x1, y1 } (pixels).
local function hud(): { { any } }
	local ui = Controller.current.ctx.ui
	local size = workspace.CurrentCamera.ViewportSize
	local out: { { any } } = {}
	local function rect(frame: any): (number, number, number, number)
		local p, z = frame.Position, frame.Size
		local x0 = p.X.Scale * size.X + p.X.Offset
		local y0 = p.Y.Scale * size.Y + p.Y.Offset
		return x0, y0, x0 + z.X.Scale * size.X + z.X.Offset, y0 + z.Y.Scale * size.Y + z.Y.Offset
	end
	if ui.helpFrame.Visible then
		table.insert(out, { "help", rect(ui.helpFrame) })
	end
	if ui.statusLabel.Visible and ui.statusLabel.Text ~= "" then
		table.insert(out, { "status", rect(ui.statusLabel) })
	end
	if ui.card.Visible then
		table.insert(out, { "card", rect(ui.card) })
	end
	-- a bar is as wide as its buttons (laid out from its left edge, 8 pixels apart)
	for _, bar in { { "buttons", ui.buttonBar }, { "touch", ui.touchBar } } do
		local x0, y0, _, y1 = rect(bar[2])
		local width = 0
		for _, child in bar[2]:GetChildren() do
			if child:IsA("TextButton") then
				width += child.Size.X.Offset + 8
			end
		end
		if width > 0 and bar[2].Visible ~= false then
			table.insert(out, { bar[1], x0, y0, x0 + width - 8, y1 })
		end
	end
	return out
end

-- The part of the HUD that lies over a point of the bed (model metres), if any.
local function covered(w: Rig.World, x: number, y: number): string?
	local p = onScreen(w, x, y)
	for _, r in hud() do
		if p.X >= r[2] and p.X <= r[4] and p.Y >= r[3] and p.Y <= r[5] then
			return `{r[1]} ({r[2]}, {r[3]} to {r[4]}, {r[5]}) lies over the bed at {x}, {y} (pixel {p.X}, {p.Y})`
		end
	end
	return nil
end

-- How far what was shown is from what was decided for the same tick (metres): the worst and the mean, for the
-- puck (1), Glacier's mallet (2) and Ember's (3).
local function apart(shown: { any }, decided: { [number]: { number } }): ({ number }, { number }, number)
	local worst, sum, n = { 0, 0, 0 }, { 0, 0, 0 }, 0
	for _, s in shown do
		local tick = math.floor(s[1] + 0.5)
		local d = decided[tick]
		if d and math.abs(s[1] - tick) < 1e-6 then
			n += 1
			for i = 1, 3 do
				local dx, dy = s[2 * i] - d[2 * i - 1], s[2 * i + 1] - d[2 * i]
				local e = math.sqrt(dx * dx + dy * dy)
				worst[i] = math.max(worst[i], e)
				sum[i] += e
			end
		end
	end
	return worst, { sum[1] / math.max(n, 1), sum[2] / math.max(n, 1), sum[3] / math.max(n, 1) }, n
end

-- Against a person the far end is drawn a moment ago (Seat): how far the puck and the far mallet shown were
-- from what the referee decided for the moments they were drawn at (metres, mean and worst), and how late those
-- moments were (seconds, mean).
local function apartDrawn(shown: { any }, decided: { [number]: { number } }, far: number): { [string]: number }
	local function at(tickTime: number): { number }?
		local t0 = math.floor(tickTime)
		local a, b = decided[t0], decided[t0 + 1]
		local f = tickTime - t0
		if a == nil or (b == nil and f > 0) then
			return nil
		end
		if f == 0 or b == nil then
			return a
		end
		local out = {}
		for i = 1, 6 do
			out[i] = a[i] + (b[i] - a[i]) * f
		end
		if math.abs(b[1] - a[1]) + math.abs(b[2] - a[2]) > 0.2 then
			out[1], out[2] = if f < 0.5 then a[1] else b[1], if f < 0.5 then a[2] else b[2]
		end
		return out
	end
	local out = { n = 0, puck = 0, puckWorst = 0, mallet = 0, malletWorst = 0, puckLate = 0, farLate = 0 }
	for _, s in shown do
		local p, m = s[8] and at(s[8]), s[9] and at(s[9])
		if p and m then
			out.n += 1
			local e = math.sqrt((s[2] - p[1]) ^ 2 + (s[3] - p[2]) ^ 2)
			out.puck += e
			out.puckWorst = math.max(out.puckWorst, e)
			e = math.sqrt((s[4 + far * 2] - m[3 + far * 2]) ^ 2 + (s[5 + far * 2] - m[4 + far * 2]) ^ 2)
			out.mallet += e
			out.malletWorst = math.max(out.malletWorst, e)
			out.puckLate += (s[1] - s[8]) / 240
			out.farLate += (s[1] - s[9]) / 240
		end
	end
	for _, k in { "puck", "mallet", "puckLate", "farLate" } do
		out[k] /= math.max(out.n, 1)
	end
	return out
end

-- (positions pass through the engine's single-precision vectors a thousand studs from the origin)
local EXACT = 2e-4

local function seatedNames(w: Rig.World): string
	local names = {}
	for _, key in w.svc:_seated(w.svc.stations[ID]) do
		table.insert(names, if key == w.player then "Ann" else tostring(key.Name))
	end
	return table.concat(names, ", ")
end

return function(t)
	t.test("walk up, the lobby, and a whole match against the computer: the screen is the referee's match", function()
		Rig.play(function(w)
			local session = w.svc:sessionOf(ID)
			local tbl = tableOf(w)
			local prompt, far = Rig.prompt(w, ID), Rig.prompt(w, EMBER)
			t.truthy(tbl.hw ~= nil, "the Table found the table")
			t.eq(prompt.ActionText, "Play air hockey")
			t.eq(prompt.ObjectText, "Air hockey (Glacier end) - open (alone, with friends, or against a computer)")
			t.eq(far.ObjectText, "Air hockey (Ember end) - open (alone, with friends, or against a computer)")
			t.eq(tbl.hw.labels[1].Text, "AIR HOCKEY  ·  FIRST TO 7")
			-- E at the Glacier end
			Rig.press(w, ID)
			Rig.run(w, 0.3)
			t.eq(w.client.active(), ID)
			local all = Rig.texts(w.gui)
			t.truthy(Rig.has(all, "Air hockey"), Rig.screen(w))
			t.truthy(
				Rig.has(all, "Knock the puck into the far goal. First to seven wins."),
				"how to play, in a sentence"
			)
			t.truthy(Rig.has(all, "Mouse  your mallet follows it"))
			t.truthy(Rig.has(all, "Starting in"), Rig.screen(w))
			t.truthy(Rig.has(all, "otherwise the computer plays it"))
			for _, text in { "Start (Space)", "Lounge (easy)", "> Club (medium)", "Pro (hard)", "Leave (Q)" } do
				t.truthy(Rig.button(w.gui, text), `the lobby's button "{text}": {Rig.screen(w)}`)
			end
			t.eq(prompt.ActionText, "Join")
			-- at the table: your end's view at once, and your legs are the table's
			t.eq(w.held, true)
			t.eq(w.controls[#w.controls], false)
			local view = Layout.camera(0, false)
			local eye = roblox.Vector3.new(Layout.toWorld(w.places[SITE], view.eye[1], view.eye[2], view.eye[3]))
			t.truthy(
				(workspace.CurrentCamera.CFrame.Position - eye).Magnitude < 0.01,
				"first person from the Glacier end"
			)
			t.eq(workspace.CurrentCamera.FieldOfView, 64)
			-- the hard one, then Space
			Rig.click(w, "Pro (hard)")
			Rig.run(w, 0.3)
			t.truthy(Rig.button(w.gui, "> Pro (hard)"), Rig.screen(w))
			-- (Space hammered, as players do: the second and third are on their way with the first)
			for _ = 1, 3 do
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.frame(w)
			end
			Rig.run(w, 0.3)
			t.eq(session.phase, "playing")
			t.eq(seatedNames(w), "Ann, Pro (computer)")
			t.eq(tbl.ref.sim.difficulty, Sim.DIFFICULTY.hard)
			t.eq(Rig.count(w.sent, "start"), 1, "Space started the lobby once")
			t.eq(#w.toasts, 1, "the only words so far are the welcome: " .. table.concat(w.toasts, " | "))
			t.truthy(tbl.ref.sim.countdown > 0, "and none of them was a serve: the countdown runs")
			t.truthy(Rig.button(w.gui, "View (V)") and Rig.button(w.gui, "Leave (Q)"), Rig.screen(w))
			t.truthy(Rig.has(Rig.texts(w.gui), "READY WHEN YOU ARE."), Rig.screen(w))
			t.eq(prompt.ActionText, "Take the computer's end")
			t.eq(far.ActionText, "Take the computer's end")
			t.eq(far.ObjectText, "Air hockey (Ember end)")
			-- the whole match, the hand on the mouse
			local shown = {}
			local hand = Line.hands.chaser(1)
			local t0 = w.frames
			play(w, 400, hand, nil, shown, function()
				return session.phase == "done"
			end)
			t.eq(session.phase, "done", "the match was played to seven")
			play(w, 1, nil, nil, nil)
			local seconds = (w.frames - t0) / 60
			local r = session.result
			local sim = tbl.ref.sim
			t.eq(math.max(sim.score0, sim.score1), 7)
			t.deepEq(r.score, { sim.score0, sim.score1 })
			t.eq(r.winner, if sim.winner == 0 then 1 else 2)
			-- what was on the screen all match long was the referee's match
			local worst, _, n = apart(shown, truth(w))
			t.truthy(n > 600, `{n} frames compared`)
			t.truthy(worst[1] < EXACT, `the puck shown was the referee's puck (worst {worst[1]} m)`)
			t.truthy(worst[2] < EXACT and worst[3] < EXACT, `and both mallets ({worst[2]}, {worst[3]})`)
			local seat = Controller.current.seat
			t.eq(seat.resims, 0, "nothing was ever corrected")
			t.eq(seat.replica.desyncs, 0)
			-- the log: about ten messages a second, never one a frame (the rig fails a dropped one by itself)
			local logs = Rig.count(w.sent, "log")
			t.truthy(logs / seconds > 8 and logs / seconds < 10.5, `{logs / seconds} log messages a second`)
			-- the end: his words, the score on the wall and on the card
			local a, b = sim.score0, sim.score1
			all = Rig.texts(w.gui)
			t.truthy(Rig.has(all, if sim.winner == 0 then "MATCH WON." else "WELL PLAYED."), Rig.screen(w))
			t.truthy(Rig.has(all, "Play again") and Rig.has(all, "Leave"), Rig.screen(w))
			t.eq(tbl.hw.labels[1].Text, `GLACIER  {a}  :  {b}  EMBER`)
			-- and lit in the bed at each end, that end's own goals first (the wall is out of a player's view)
			t.eq(printed(w, 0), `{a} : {b}`)
			t.eq(printed(w, 1), `{b} : {a}`)
			local over = Rig.last(w.got, "event", function(m)
				return m.over == true
			end)
			t.eq(
				over.text,
				`{if sim.winner == 0 then "Ann" else "Pro (computer)"} wins {math.max(a, b)}-{math.min(a, b)}`
			)
			-- sound: every cue point fired, none has an asset yet
			local counts = MinigameSounds.counts()
			t.truthy((counts["air_hockey.strike"] or 0) > 10, "strikes")
			t.truthy((counts["air_hockey.rail"] or 0) > 5, "rails")
			t.eq((counts["air_hockey.goal_for"] or 0) + (counts["air_hockey.goal_against"] or 0), a + b)
			t.eq(counts["air_hockey.goal_for"] or 0, a, "a goal for is heard as one")
			-- the serve is heard each time the puck is let go: once to start, once after every goal but the last
			local _, serves = truth(w)
			t.eq(serves, a + b)
			t.eq(counts["air_hockey.serve"] or 0, serves, "one serve cue for each serve")
			-- and the winner hears the winner's cue (the table's word, not this screen's guess)
			t.eq(counts["air_hockey.win"] or 0, if sim.winner == 0 then 1 else 0)
			t.eq(counts["air_hockey.lose"] or 0, if sim.winner == 0 then 0 else 1)
			for cue, id in MinigameSounds.CUES do
				if string.sub(cue, 1, 11) == "air_hockey." then
					t.eq(id, "", cue)
				end
			end
			-- Leave: the camera and the legs come back
			Rig.click(w, "Leave (Q)")
			Rig.run(w, 0.5)
			t.eq(w.client.active(), nil)
			t.eq(w.held, false)
			t.eq(w.controls[#w.controls], true)
			t.eq(Controller.current, nil)
			t.eq(session.phase, "idle")
			local px, py = where(w, Layout.PUCK)
			t.truthy(math.abs(px) < 1e-3 and math.abs(py) < 1e-3, "the table is put to rest")
		end, opts())
	end)

	t.test("the Ember end: its prompt is that end; mouse, keys, a stick, V and Space", function()
		Rig.play(function(w)
			local session = w.svc:sessionOf(ID)
			Rig.press(w, EMBER)
			Rig.run(w, 0.3)
			t.eq(w.client.active(), ID, "the far prompt seats you at the same table")
			local joined = Rig.last(w.got, "joined")
			t.eq(joined.via, EMBER)
			-- the lobby already looks from the end that was asked for
			local view = Layout.camera(1, false)
			local eye = roblox.Vector3.new(Layout.toWorld(w.places[SITE], view.eye[1], view.eye[2], view.eye[3]))
			t.truthy(
				(workspace.CurrentCamera.CFrame.Position - eye).Magnitude < 0.01,
				"first person from the Ember end"
			)
			Rig.click(w, "Start (Space)")
			Rig.run(w, 0.4)
			t.eq(session.phase, "playing")
			local tbl = tableOf(w)
			t.eq(tbl.sideOf[w.player], 1)
			t.eq(Referee_mode(tbl), "1")
			t.eq(session.game.state.sideOf[1], 1)
			local sim = tbl.ref.sim
			-- Space lets the puck go before the countdown is out
			t.truthy(sim.countdown > 0)
			Rig.key(Key.Space, true)
			Rig.key(Key.Space, false)
			Rig.run(w, 0.3)
			t.eq(sim.countdown, 0, "served at once")
			t.eq(Rig.count(w.sent, "start"), 1, "Space was a serve this time, not a start")
			t.eq(MinigameSounds.counts()["air_hockey.serve"], 1, "and the serve was heard, once")
			-- she stands on the mat at her end, facing down the table
			local root = w.body.PrimaryPart
			local X, D = Layout.stance(1)
			local at = roblox.Vector3.new(AlleyLayout.toWorld(w.places[SITE], X, 0, D))
			local flat = roblox.Vector3.new(root.Position.X - at.X, 0, root.Position.Z - at.Z)
			t.truthy(flat.Magnitude < 1, `the body is {flat.Magnitude} studs from the Ember end's mat`)
			-- the mouse: the mallet goes to the bed under the pointer, at once on this screen
			local x1, y1 = where(w, Layout.MALLETS[1])
			point(w, 0.3, 0.5)
			Rig.frame(w)
			local x2, y2 = where(w, Layout.MALLETS[1])
			t.near(
				y1,
				Sim.PADDLE_RADIUS,
				2e-3,
				"(the pointer began over the far half: the mallet waits at the centre line)"
			)
			t.truthy(x2 > x1 and y2 > y1, `in that very frame the mallet is on its way ({x1}, {y1} to {x2}, {y2})`)
			Rig.run(w, 0.6)
			x2, y2 = where(w, Layout.MALLETS[1])
			t.near(x2, 0.3, 2e-3)
			t.near(y2, 0.5, 2e-3)
			t.near(sim.p1x, 0.3, 2e-3, "and the referee's mallet followed")
			-- a pointer over the other half: the mallet stops at the centre line
			point(w, 0.1, -0.6)
			Rig.run(w, 0.8)
			x2, y2 = where(w, Layout.MALLETS[1])
			t.near(y2, Sim.PADDLE_RADIUS, 2e-3)
			-- keys: D is your right (the Ember end looks back down the table), W is away from you
			local uis = FakeEngine.uis()
			Rig.run(w, 0.3)
			local kx, ky = where(w, Layout.MALLETS[1])
			Rig.key(Key.D, true)
			Rig.run(w, 0.25)
			Rig.key(Key.D, false)
			Rig.key(Key.S, true)
			Rig.run(w, 0.25)
			Rig.key(Key.S, false)
			Rig.run(w, 0.4)
			x2, y2 = where(w, Layout.MALLETS[1])
			t.near(x2 - kx, -Controller.KEY_SPEED * 0.25, 0.02, "D: 1.8 m/s to the player's right")
			t.near(y2 - ky, Controller.KEY_SPEED * 0.25, 0.02, "S: toward the player")
			-- Shift held: the keys push as fast as the mallet goes
			Rig.key(Key.LeftShift, true)
			Rig.key(Key.A, true)
			Rig.run(w, 0.2)
			Rig.key(Key.A, false)
			Rig.key(Key.LeftShift, false)
			Rig.run(w, 0.4)
			local fx = where(w, Layout.MALLETS[1])
			t.near(fx - x2, Sim.HUMAN_SPEED * 0.2, 0.03, "Shift + A: 3.5 m/s to the player's left")
			x2, y2 = where(w, Layout.MALLETS[1])
			-- typing in chat: W, A, S and D are letters, and the mallet stays where it is
			uis.focused = {}
			Rig.key(Key.D, true)
			Rig.key(Key.W, true)
			Rig.run(w, 0.3)
			Rig.key(Key.D, false)
			Rig.key(Key.W, false)
			uis.focused = nil
			Rig.run(w, 0.2)
			local tx, ty = where(w, Layout.MALLETS[1])
			t.near(tx, x2, 1e-4, "typing a d did not move the mallet")
			t.near(ty, y2, 1e-4, "nor a w")
			t.near(sim.p1x, x2, 1e-3, "and the referee's mallet stayed with it")
			-- a gamepad's left stick
			-- (held right over: the mallet drawn runs at a mallet's own top speed, as the mouse's does)
			rawset(uis, "GetGamepadState", function(): { any }
				return { { KeyCode = Key.Thumbstick1, Position = roblox.Vector3.new(0, 1, 0) } }
			end)
			Rig.run(w, 0.05)
			local _, ya = where(w, Layout.MALLETS[1])
			Rig.frame(w)
			Rig.frame(w)
			Rig.frame(w)
			local _, yb = where(w, Layout.MALLETS[1])
			t.near((ya - yb) * 20, Sim.HUMAN_SPEED, 0.05, "a stick held over moves the drawn mallet at 3.5 m/s")
			rawset(uis, "GetGamepadState", function(): { any }
				return {}
			end)
			Rig.run(w, 0.4)
			local sx, sy = where(w, Layout.MALLETS[1])
			t.near(sy - y2, -Controller.STICK_SPEED * 0.1, 0.03, "the stick pushed away from the player")
			t.near(sx, x2, 0.01)
			t.eq(Controller.STICK_SPEED, Sim.HUMAN_SPEED)
			-- half over: a quarter of the way up the curve, for placing a block; inside the dead zone: nothing
			local hx, hy = Controller.stick(0, 0.15 + 0.85 / 2)
			t.near(hy, Sim.HUMAN_SPEED / 4, 1e-9)
			t.eq(hx, 0)
			t.eq(select(2, Controller.stick(0.1, 0.1)), 0)
			-- V: from above, your end at the bottom; again: back
			Rig.key(Key.V, true)
			Rig.key(Key.V, false)
			Rig.run(w, 1)
			local above = Layout.camera(1, true)
			local up = roblox.Vector3.new(Layout.toWorld(w.places[SITE], above.eye[1], above.eye[2], above.eye[3]))
			t.truthy((workspace.CurrentCamera.CFrame.Position - up).Magnitude < 0.05, "the view from above")
			t.truthy(up.Y < w.places[SITE].floorY + AlleyLayout.CEILING_Y, "under the ceiling")
			Rig.run(w, 1.5) -- (the camera glides to the new view: point once it is there)
			point(w, -0.2, 0.9)
			Rig.run(w, 0.8)
			x2, y2 = where(w, Layout.MALLETS[1])
			t.near(x2, -0.2, 3e-3, "the pointer steers through the view from above too")
			t.near(y2, 0.9, 3e-3)
			-- the view changes under a pointer that is held still: the mallet goes to the point now under it
			local pointer = uis.mouse
			Rig.click(w, "View (V)")
			Rig.run(w, 2.5)
			t.truthy((workspace.CurrentCamera.CFrame.Position - eye).Magnitude < 0.05, "and back to first person")
			t.eq(uis.mouse, pointer, "(the mouse did not move)")
			local mx, my = where(w, Layout.MALLETS[1])
			local under = onScreen(w, mx, my)
			t.truthy(
				math.abs(under.X - pointer.X) < 3 and math.abs(under.Y - pointer.Y) < 3,
				`after the change of view the mallet is under the still pointer ({under.X}, {under.Y} against {pointer.X}, {pointer.Y})`
			)
			-- a goal is said once: the banner has the words, the status line keeps the score
			t.truthy(w.svc:debug(ID, "goal", 1))
			Rig.run(w, 0.4)
			local said = 0
			for _, text in Rig.texts(w.gui) do
				if string.find(text, "SHOT", 1, true) or string.find(text, "SCORES", 1, true) then
					said += 1
				end
			end
			t.eq(said, 1, "the goal's words are on the screen once: " .. Rig.screen(w))
			t.truthy(Rig.has(Rig.texts(w.gui), "You 1 : "), "the status line keeps the score: " .. Rig.screen(w))
			-- typing in chat moves nothing
			uis.focused = {}
			Rig.key(Key.V, true)
			Rig.key(Key.V, false)
			Rig.run(w, 0.5)
			t.truthy((workspace.CurrentCamera.CFrame.Position - eye).Magnitude < 0.05)
			uis.focused = nil
			t.eq(#w.toasts, 1, "nothing was refused: " .. table.concat(w.toasts, " | "))
		end, opts({ stand = { site = SITE, x = select(1, Layout.stance(1)), y = 3, d = select(2, Layout.stance(1)) } }))
	end)

	t.test("touch: a finger dragged anywhere moves the mallet as far as the finger; a tap serves", function()
		Rig.play(function(w)
			Rig.press(w, ID)
			Rig.run(w, 0.3)
			Rig.click(w, "Start (Space)")
			Rig.run(w, 0.4)
			local sim = tableOf(w).ref.sim
			t.truthy(sim.countdown > 0)
			local all = Rig.texts(w.gui)
			t.truthy(Rig.has(all, "HELP") and Rig.has(all, "View") and Rig.has(all, "Leave"), Rig.screen(w))
			t.truthy(Rig.has(all, "Tap to serve"), Rig.screen(w))
			-- the help card was put away as the match began (it lies over the player's half); HELP brings it back
			local ui = Controller.current.ctx.ui
			t.eq(ui.helpFrame.Visible, false, "the help card is put away on a touch screen")
			local help = Rig.button(w.gui, "HELP")
			help.MouseButton1Down.fire()
			help.MouseButton1Up.fire()
			t.eq(ui.helpFrame.Visible, true)
			help.MouseButton1Down.fire()
			help.MouseButton1Up.fire()
			t.eq(ui.helpFrame.Visible, false)
			-- a drag: the mallet's place on the screen moves by the finger's pixels
			local cam = workspace.CurrentCamera
			local function malletAt(): any
				local x, y = where(w, Layout.MALLETS[0])
				return cam:WorldToViewportPoint(roblox.Vector3.new(Layout.toWorld(w.places[SITE], x, y)))
			end
			Rig.run(w, 0.3)
			local before = malletAt()
			Rig.touch(1, "began", 300, 800)
			for i = 1, 20 do
				Rig.touch(1, "changed", 300 + i * 10, 800 - i * 4)
				Rig.frame(w)
			end
			Rig.touch(1, "ended", 500, 720)
			Rig.run(w, 0.6)
			local after = malletAt()
			t.near(after.X - before.X, 200, 3, "200 pixels right")
			t.near(after.Y - before.Y, -80, 3, "80 pixels up")
			local function served(): boolean
				for _, m in w.sent do
					if m.verb == "log" and string.find(tostring(m.args[3]), "!", 1, true) then
						return true
					end
				end
				return false
			end
			t.eq(served(), false, "a drag is not a serve")
			-- a second finger does not take the mallet over
			Rig.touch(1, "began", 600, 700)
			Rig.touch(2, "began", 100, 100)
			Rig.touch(2, "changed", 900, 900)
			Rig.run(w, 0.3)
			local still = malletAt()
			t.near(still.X, after.X, 2)
			Rig.touch(2, "ended", 900, 900)
			Rig.touch(1, "ended", 600, 700)
			Rig.run(w, 0.3)
			t.eq(served(), false, "a long press is not a tap")
			-- a tap serves: the next countdown (a scripted goal starts one) is cut short
			t.truthy(w.svc:debug(ID, "goal", 1))
			Rig.run(w, 0.5)
			t.truthy(sim.countdown > 0.5, "a goal: the countdown runs")
			Rig.touch(3, "began", 640, 400)
			Rig.frame(w)
			Rig.touch(3, "ended", 640, 400)
			Rig.run(w, 0.3)
			t.eq(sim.countdown, 0, "the tap served")
			t.eq(served(), true)
		end, opts({ touch = true }))
	end)

	for _, ms in { 0, 80, 150 } do
		local lag = math.floor(ms / 1000 * 60 + 0.5)
		t.test(
			`against the computer at {ms} ms each way: the mallet is the hand and the puck is the referee's`,
			function()
				Rig.play(function(w)
					Rig.press(w, ID)
					Rig.run(w, 0.3 + lag / 30)
					Rig.click(w, "Start (Space)")
					Rig.run(w, 0.5 + lag / 30)
					local shown = {}
					play(w, 25, Line.hands.chaser(1.2), nil, shown)
					local worst, _, n = apart(shown, truth(w))
					t.truthy(n > 1000, `{n} frames compared`)
					t.truthy(worst[1] < EXACT, `puck: worst {worst[1]} m`)
					t.truthy(worst[2] < EXACT, `own mallet: worst {worst[2]} m`)
					t.truthy(worst[3] < EXACT, `the computer's mallet: worst {worst[3]} m`)
					t.eq(Controller.current.seat.resims, 0)
					-- the hand is never late, whatever the line: in the very frame the pointer moves, the mallet
					-- shown has gone that frame's ticks toward it at its own speed
					local x0, y0 = where(w, Layout.MALLETS[0])
					point(w, x0, y0)
					Rig.run(w, 0.5)
					x0, y0 = where(w, Layout.MALLETS[0])
					point(w, if x0 > 0 then -0.5 else 0.5, y0)
					Rig.frame(w)
					local x1 = where(w, Layout.MALLETS[0])
					local travel = math.abs(x1 - x0)
					t.truthy(
						travel > 2.5 * Sim.HUMAN_SPEED / 240 and travel < 4.5 * Sim.HUMAN_SPEED / 240,
						`in the same frame the mallet has gone {travel} m (three or four ticks at 3.5 m/s)`
					)
				end, opts({ lag = lag }))
			end
		)
	end

	t.test("a person takes the computer's end mid-match, and the computer takes it back when they leave", function()
		Rig.play(function(w)
			local session = w.svc:sessionOf(ID)
			Rig.press(w, ID)
			Rig.run(w, 0.3)
			Rig.click(w, "Start (Space)")
			Rig.run(w, 0.4)
			local tbl = tableOf(w)
			local hand = Line.hands.chaser(1)
			play(w, 4, hand)
			t.eq(seatedNames(w), "Ann, Club (computer)")
			-- Bob presses the Glacier end's prompt, which Ann has: he is given the computer's end and told so
			local bob = bot(w, "Bob", Line.hands.chaser(1.5))
			local ok, why = w.svc:join(bob.stub, ID)
			t.truthy(ok, why)
			t.eq(seatedNames(w), "Ann, Bob")
			t.eq(Referee_mode(tbl), "2")
			t.eq(tbl.sideOf[bob.stub], 1)
			local seatMsg = Rig.last(bob.stub.events, "air_hockey_seat")
			t.eq(seatMsg.side, 1)
			t.eq(seatMsg.from, tbl.ref.n, "his log starts at the tick the match has reached")
			t.truthy(Rig.last(bob.stub.events, "event").text == "You play the Ember end")
			local shown = {}
			play(w, 8, hand, { bob }, shown)
			t.eq(#bob.refused, 0, table.concat(bob.refused, "; "))
			t.eq(bob.seat.replica.desyncs, 0)
			t.eq(Controller.current.seat.replica.desyncs, 0)
			t.eq(Controller.current.seat.mode, "2")
			t.truthy(tbl.ref.got[1] > seatMsg.from + 1500, "Bob's hand is in the match")
			local worst = apart(shown, truth(w))
			t.truthy(worst[2] < EXACT, `Ann's own mallet is still exactly her hand ({worst[2]} m)`)
			t.truthy(Rig.has(Rig.texts(w.gui), "first to 7"), Rig.screen(w))
			-- a third person finds both ends taken
			local carol = Rig.stub("Carol")
			ok, why = w.svc:join(carol, EMBER)
			t.eq(ok, false)
			t.eq(why, "Both ends are taken: watch this one, or wait for the next match")
			-- Bob leaves: the computer has the Ember end again, and Ann is told
			w.svc:leave(bob.stub, "left")
			play(w, 1, hand)
			t.eq(seatedNames(w), "Ann, Club (computer)")
			t.eq(Referee_mode(tbl), "0")
			t.truthy(Rig.has(Rig.texts(w.gui), "Bob left: the computer takes the Ember end"), Rig.screen(w))
			local resims = Controller.current.seat.resims
			shown = {}
			play(w, 6, hand, nil, shown)
			t.eq(session.phase, "playing")
			t.eq(Controller.current.seat.resims, resims, "alone with the computer again: nothing is corrected")
			t.eq(Controller.current.seat.replica.desyncs, 0)
			worst = apart(shown, truth(w))
			t.truthy(worst[1] < EXACT, `and the screen is the referee's match again ({worst[1]} m)`)
		end, opts())
	end)

	t.test("two people from the lobby: both ends, a hand each; one stops answering, one leaves", function()
		Rig.play(function(w)
			local session = w.svc:sessionOf(ID)
			Rig.press(w, ID)
			Rig.run(w, 0.3)
			local bob = bot(w, "Bob", Line.hands.chaser(1.5))
			t.truthy(w.svc:join(bob.stub, ID), "Bob joins the lobby, by the Glacier prompt too")
			Rig.run(w, 0.3)
			t.truthy(Rig.has(Rig.texts(w.gui), "Both ends are taken"), Rig.screen(w))
			Rig.click(w, "Start (Space)")
			Rig.run(w, 0.3)
			local tbl = tableOf(w)
			t.eq(seatedNames(w), "Ann, Bob")
			t.eq(Referee_mode(tbl), "2", "no computer")
			t.eq(tbl.sideOf[w.player], 0)
			t.eq(tbl.sideOf[bob.stub], 1)
			t.eq(Rig.last(bob.stub.events, "event").text, "That end was taken: you play the Ember end")
			local hand = Line.hands.chaser(1)
			local shown = {}
			play(w, 20, hand, { bob }, shown)
			t.eq(#bob.refused, 0, table.concat(bob.refused, "; "))
			t.truthy(tbl.ref.sim.hitSerial > 10, "a rally")
			local worst, mean = apart(shown, truth(w))
			t.truthy(worst[2] < EXACT, `Ann's own mallet is her hand ({worst[2]} m)`)
			t.truthy(mean[1] < 0.2, `the puck on Ann's screen is {mean[1]} m from the referee's on average`)
			local logs = Rig.count(w.sent, "log")
			t.truthy(logs / 20 > 12 and logs / 20 < 15.5, `{logs / 20} log messages a second against a person`)
			-- Bob's game stops answering: after the idle time he is taken off and the computer has his end
			local n = tbl.ref.n
			play(w, 7.5, hand)
			t.truthy(tbl.ref.n > n + 240 * 6, "the match did not wait for him")
			t.eq(seatedNames(w), "Ann, Club (computer)")
			local left = Rig.last(bob.stub.events, "left")
			t.eq(left.why, "idle")
			t.eq(left.text, "You were taken off the air hockey table: your game stopped answering")
			t.eq(Referee_mode(tbl), "0")
			-- Ann presses Q in the middle: her camera and legs are back, and with nobody left the table rests
			Rig.key(Key.Q, true)
			Rig.key(Key.Q, false)
			Rig.run(w, 0.5)
			t.eq(w.client.active(), nil)
			t.eq(w.held, false)
			t.eq(w.controls[#w.controls], true)
			t.eq(session.phase, "idle")
			t.eq(tbl.ref, nil)
			local px, py = where(w, Layout.PUCK)
			t.truthy(math.abs(px) < 1e-3 and math.abs(py) < 1e-3)
			t.eq(Rig.prompt(w, ID).ActionText, "Play air hockey")
		end, opts())
	end)

	for _, ms in { 0, 80, 150 } do
		local lag = math.floor(ms / 1000 * 60 + 0.5)
		t.test(
			`against a person at {ms} ms each way: your mallet is your hand, the far end is the referee's a moment ago`,
			function()
				Rig.play(function(w)
					Rig.press(w, ID)
					Rig.run(w, 0.3 + lag / 30)
					-- (Bob presses his serve button during every countdown, as people do: between two people the
					-- puck is let go a moment after the press, so Ann's screen has heard of it before it moves)
					local chase = Line.hands.chaser(2)
					local pressed = 0
					local bob = bot(w, "Bob", function(side: number, sim: any, tick: number): (number, number, boolean)
						local x, y = chase(side, sim, tick)
						local press = sim.countdown > 0.6 and sim.countdown < 1.0
						if press then
							pressed += 1
						end
						return x, y, press
					end)
					t.truthy(w.svc:join(bob.stub, EMBER))
					Rig.click(w, "Start (Space)")
					Rig.run(w, 0.5 + lag / 30)
					local tbl = tableOf(w)
					t.eq(Referee_mode(tbl), "2")
					local shown = {}
					play(w, 20, Line.hands.chaser(1), { bob }, shown, function()
						return tbl.ref == nil or Referee.over(tbl.ref)
					end)
					t.eq(#bob.refused, 0, table.concat(bob.refused, "; "))
					local seat = Controller.current.seat
					t.eq(seat.replica.desyncs, 0)
					local decided = truth(w)
					local worst = apart(shown, decided)
					t.truthy(worst[2] < EXACT, `Ann's own mallet is her hand, now ({worst[2]} m)`)
					local d = apartDrawn(shown, decided, 1)
					t.truthy(d.n > 600, `{d.n} frames compared`)
					t.truthy(d.malletWorst < 1e-3, `the far mallet drawn is the referee's (worst {d.malletWorst} m)`)
					t.truthy(
						d.puckWorst < 1e-3,
						`the puck drawn is the referee's ({d.puck} m on average, worst {d.puckWorst}; {tbl.ref.cuts} ticks cut)`
					)
					-- how late the far end is: this line's round trip, the other hand's segment, a frame or two
					t.truthy(d.farLate < (2 * ms + 150) / 1000, `the far mallet is drawn {d.farLate} s late`)
					t.truthy(d.farLate > 2 * ms / 1000, "(and no earlier than the line allows)")
					t.truthy(d.puckLate < d.farLate, `the puck {d.puckLate} s on average (now in Ann's own half)`)
					t.truthy((MinigameSounds.counts()["air_hockey.strike"] or 0) > 3, "strikes are heard")
					-- Bob's early serves were serves (the countdown was cut short), and each was heard once
					t.truthy(pressed > 0, "Bob pressed his serve button")
					local _, serves = truth(w)
					local goals = tbl.ref.sim.score0 + tbl.ref.sim.score1
					t.truthy(serves >= 1 and serves >= goals, `{serves} serves, {goals} goals`)
					local heard = MinigameSounds.counts()["air_hockey.serve"] or 0
					t.truthy(math.abs(heard - serves) <= 1, `{heard} serve cues for {serves} serves`)
				end, opts({ lag = lag }))
			end
		)
	end

	t.test("someone walking up late watches the same match; it is not sent to someone far away", function()
		Rig.play(function(w)
			-- Bob plays the computer; Ann is at the other end of the building
			local bob = bot(w, "Bob", Line.hands.chaser(1))
			t.truthy(w.svc:join(bob.stub, ID))
			t.truthy(Rig.input(w, bob.stub, ID, "start"))
			local tbl = tableOf(w)
			play(w, 6, nil, { bob })
			t.truthy(tbl.ref.n > 1000)
			t.eq(Rig.count(w.got, "air_hockey"), 0, "nothing is sent to someone far from the table")
			t.eq(Rink.watching(), 0)
			-- she walks up to the table (not to a prompt): from the next look around she is sent the match
			local X, D = Layout.stance(0)
			Rig.walkTo(w, SITE, X - 2, 3, D + 6)
			local shown = {}
			play(w, 6, nil, { bob }, shown)
			t.truthy(Rig.count(w.got, "air_hockey") > 40)
			t.eq(Rink.watching(), 1)
			t.eq(w.client.active(), nil, "watching is not playing")
			t.eq(w.held, false, "and takes nobody's camera")
			-- what she sees is the referee's puck of a moment ago, moving every frame
			local decided = truth(w)
			local late, moved, n = 0, 0, 0
			for i = 31, #shown do
				local s, before = shown[i], shown[i - 1]
				local best = math.huge
				for back = 0, 2 * Rink.DELAY do
					local d = decided[math.floor(s[1] + 0.5) - back]
					if d then
						local e = math.abs(s[2] - d[1]) + math.abs(s[3] - d[2])
						if e < best then
							best, late = e, math.max(late, if e < 1e-3 then back else 0)
						end
					end
				end
				n += 1
				t.truthy(best < 0.03, `frame {i}: the puck shown is {best} m from any recent tick of the referee's`)
				if math.abs(s[2] - before[2]) + math.abs(s[3] - before[3]) > 1e-6 then
					moved += 1
				end
			end
			t.truthy(n > 300)
			-- a goal, the countdown, the serve: a bystander hears the puck let go
			local heard = MinigameSounds.counts()["air_hockey.serve"] or 0
			t.truthy(w.svc:debug(ID, "goal", 0))
			play(w, 2.5, nil, { bob })
			t.truthy((MinigameSounds.counts()["air_hockey.goal"] or 0) >= 1, "a bystander hears the goal")
			t.truthy((MinigameSounds.counts()["air_hockey.serve"] or 0) > heard, "and the puck let go after it")
			t.truthy(late <= 2 * Rink.DELAY, `never more than {late} ticks behind`)
			t.truthy(moved > n * 0.75, `the puck moved on {moved} of {n} frames (it rests during the countdowns)`)
			-- Bob leaves: the table rests, the stream stops, and a little later nothing is being drawn
			w.svc:leave(bob.stub, "left")
			play(w, 3.5, nil, nil)
			t.eq(tbl.ref, nil)
			t.eq(Rink.watching(), 0, "the watcher's render step is let go")
			local px, py = where(w, Layout.PUCK)
			t.truthy(math.abs(px) < 1e-3 and math.abs(py) < 1e-3, "and the puck is where the server rested it")
		end, opts({ stand = { site = SITE, x = -20, y = 3, d = -40 } }))
	end)

	t.test("every other way off the table: Q in the lobby, walking away, play again, the card running out", function()
		Rig.play(function(w)
			local session = w.svc:sessionOf(ID)
			local tbl = tableOf(w)
			-- Q in the lobby
			Rig.press(w, ID)
			Rig.run(w, 0.3)
			t.eq(session.phase, "lobby")
			-- (Q twice: the second is on its way with the first, and is not refused with words)
			Rig.key(Key.Q, true)
			Rig.key(Key.Q, false)
			Rig.frame(w)
			Rig.key(Key.Q, true)
			Rig.key(Key.Q, false)
			Rig.run(w, 0.4)
			t.eq(session.phase, "idle")
			t.eq(w.client.active(), nil)
			t.eq(w.held, false)
			t.eq(Rig.count(w.sent, "leave"), 1, "leave was sent once")
			t.eq(Rig.has(w.toasts, "You are not at that game"), false, table.concat(w.toasts, " | "))
			-- the lobby runs out by itself: the match starts, the computer at the other end
			Rig.press(w, ID)
			Rig.run(w, 8.6)
			t.eq(session.phase, "playing")
			t.eq(seatedNames(w), "Ann, Club (computer)")
			-- a scripted last goal: the referee scores it through the simulation's own goal line
			t.truthy(w.svc:debug(ID, "score", 6, 0))
			t.truthy(w.svc:debug(ID, "goal", 0))
			play(w, 2, Line.hands.still)
			t.eq(session.phase, "done")
			t.deepEq(session.result.score, { 7, 0 })
			t.truthy(Rig.has(Rig.texts(w.gui), "MATCH WON."), Rig.screen(w))
			-- Play again: the same people, a new match at once
			-- (clicked twice, and Space hammered on top: one new match, and nothing refused)
			local games = tbl.games
			Rig.click(w, "Play again")
			Rig.frame(w)
			Rig.click(w, "Play again")
			Rig.key(Key.Space, true)
			Rig.key(Key.Space, false)
			Rig.run(w, 0.5)
			t.eq(Rig.has(w.toasts, "not finished"), false, table.concat(w.toasts, " | "))
			t.eq(Rig.has(w.toasts, "already"), false, table.concat(w.toasts, " | "))
			-- (and the table itself takes a second again or start that crosses the first without words: the end
			-- card's own buttons are not this controller's)
			t.truthy(Rig.input(w, w.player, ID, "again"))
			t.truthy(Rig.input(w, w.player, ID, "start"))
			t.eq(session.phase, "playing")
			t.eq(tbl.games, games + 1)
			t.eq(seatedNames(w), "Ann, Club (computer)")
			t.eq(Controller.current.seat.game, tbl.games)
			play(w, 3, Line.hands.chaser(1))
			t.eq(Controller.current.seat.replica.desyncs, 0)
			t.eq(tbl.ref.sim.score0 + tbl.ref.sim.score1, 0)
			-- the card running out: lose 7-0 by script, read nothing, and the table frees itself with words
			t.truthy(w.svc:debug(ID, "score", 0, 6))
			t.eq(w.svc:debug(ID, "score", 7, 0), false, "a scripted score cannot end a match")
			t.eq(w.svc:debug(ID, "goal", 2), false)
			t.truthy(w.svc:debug(ID, "goal", 1))
			play(w, 2, Line.hands.still)
			t.eq(session.phase, "done")
			t.truthy(Rig.has(Rig.texts(w.gui), "WELL PLAYED."), Rig.screen(w))
			Rig.run(w, 21)
			t.eq(session.phase, "idle")
			t.eq(w.client.active(), nil)
			t.truthy(Rig.has(w.toasts, "That match is over and the table is free"), table.concat(w.toasts, " | "))
			t.eq(w.held, false)
			-- walking away from a match (a body moved by something else: the legs are the table's)
			Rig.press(w, ID)
			Rig.run(w, 0.3)
			Rig.click(w, "Start (Space)")
			Rig.run(w, 1)
			t.eq(session.phase, "playing")
			Rig.walkTo(w, SITE, -10, 3, -20)
			Rig.run(w, 0.5)
			t.eq(w.client.active(), nil)
			t.truthy(Rig.has(w.toasts, "You walked away from the game"), table.concat(w.toasts, " | "))
			t.eq(session.phase, "idle")
			t.eq(tbl.ref, nil)
			-- an animal cannot play
			w.species = "squirrel"
			Rig.walkTo(w, SITE, select(1, Layout.stance(0)), 3, select(2, Layout.stance(0)))
			Rig.press(w, ID)
			Rig.run(w, 0.3)
			t.eq(session.phase, "idle")
			t.truthy(Rig.has(w.toasts, "Only people can play here"))
		end, opts())
	end)

	t.test("E from beside the table: you are stood on the mat at your end, out of your own view", function()
		Rig.play(
			function(w)
				Rig.press(w, ID)
				Rig.run(w, 0.3)
				local root = w.body.PrimaryPart
				local X, D = Layout.stance(0)
				local mat = roblox.Vector3.new(AlleyLayout.toWorld(w.places[SITE], X, 0, D))
				local flat = roblox.Vector3.new(root.Position.X - mat.X, 0, root.Position.Z - mat.Z)
				t.truthy(flat.Magnitude < 1, `the body is {flat.Magnitude} studs from the mat (it was 7 away)`)
				local box = Layout.standing(0)
				local lx, _, ld = AlleyLayout.toLocal(w.places[SITE], root.Position.X, 0, root.Position.Z)
				t.truthy(lx >= box.x0 and lx <= box.x1 and ld >= box.d0 and ld <= box.d1, "inside the standing room")
				-- facing down the table
				local centre = roblox.Vector3.new(Layout.toWorld(w.places[SITE], 0, 0))
				local to = roblox.Vector3.new(centre.X - root.Position.X, 0, centre.Z - root.Position.Z).Unit
				t.truthy(root.CFrame.LookVector:Dot(to) > 0.99, "facing the table")
				-- and nowhere in the first-person view: not the middle of the body, not the head, not a shoulder
				local cam = workspace.CurrentCamera
				for _, offset in { { 0, 0, 0 }, { 0, 2, 0 }, { 1.5, 1, 0 }, { -1.5, 1, 0 }, { 0, -2.5, 0 } } do
					local q = root.CFrame:PointToWorldSpace(roblox.Vector3.new(offset[1], offset[2], offset[3]))
					local _, inView = cam:WorldToViewportPoint(q)
					t.eq(inView, false, `the body ({offset[1]}, {offset[2]}) is not in the player's own view`)
				end
				-- the match starts and is played from there: the body is not moved again, and stays in reach
				Rig.click(w, "Start (Space)")
				play(w, 3, Line.hands.chaser(1))
				t.eq(w.svc:sessionOf(ID).phase, "playing")
				local flat2 = roblox.Vector3.new(root.Position.X - mat.X, 0, root.Position.Z - mat.Z)
				t.truthy(flat2.Magnitude < 1)
			end,
			opts({
				stand = {
					site = SITE,
					x = select(1, Layout.stance(0)) + 2,
					y = 3,
					d = select(2, Layout.stance(0)) - 6.5,
				},
			})
		)
	end)

	for _, screen in { { 844, 390 }, { 667, 375 } } do
		t.test(`a {screen[1]} by {screen[2]} phone: from above, and no part of the HUD lies over the bed`, function()
			Rig.play(function(w)
				rawset(workspace.CurrentCamera, "ViewportSize", roblox.Vector2.new(screen[1], screen[2]))
				Rig.press(w, ID)
				Rig.run(w, 0.3)
				local ui = Controller.current.ctx.ui
				t.eq(Controller.short(), true)
				t.eq(ui.helpFrame.Visible, true, "the help card is up in the lobby, to be read")
				local above = Layout.camera(0, true)
				local up = roblox.Vector3.new(Layout.toWorld(w.places[SITE], above.eye[1], above.eye[2], above.eye[3]))
				t.truthy((workspace.CurrentCamera.CFrame.Position - up).Magnitude < 0.05, "a phone opens from above")
				Rig.click(w, "Start (Space)")
				Rig.run(w, 0.4)
				t.eq(ui.helpFrame.Visible, false, "and is put away as the match starts")
				local sim = tableOf(w).ref.sim
				t.truthy(sim.countdown > 0)
				t.truthy(Rig.has(Rig.texts(w.gui), "Tap to serve"), Rig.screen(w))
				-- a tap serves; from then on nothing lies over any part of the bed: both goals, both mallets'
				-- reach, the corners
				Rig.touch(1, "began", 400, 200)
				Rig.frame(w)
				Rig.touch(1, "ended", 400, 200)
				Rig.run(w, 0.4)
				t.eq(sim.countdown, 0, "the tap served")
				t.eq(ui.statusLabel.Visible, false, "the status line is only up while the puck waits")
				local rects = {}
				for _, r in hud() do
					table.insert(rects, r[1])
				end
				t.deepEq(rects, { "card", "buttons", "touch" })
				local size = workspace.CurrentCamera.ViewportSize
				for i = 0, 20 do
					for j = 0, 40 do
						local x = -Sim.HALF_WIDTH + i / 20 * 2 * Sim.HALF_WIDTH
						local y = -Sim.HALF_LENGTH + j / 40 * 2 * Sim.HALF_LENGTH
						local why = covered(w, x, y)
						t.eq(why, nil, why)
						local q = onScreen(w, x, y)
						t.truthy(
							q.X >= 0 and q.X <= size.X and q.Y >= 0 and q.Y <= size.Y,
							"the whole bed is on the screen"
						)
					end
				end
				-- the finger still moves the mallet, from above
				local before = onScreen(w, where(w, Layout.MALLETS[0]))
				Rig.touch(2, "began", 100, 300)
				for i = 1, 10 do
					Rig.touch(2, "changed", 100 + i * 3, 300 - i * 2)
					Rig.frame(w)
				end
				Rig.touch(2, "ended", 130, 280)
				Rig.run(w, 0.5)
				local after = onScreen(w, where(w, Layout.MALLETS[0]))
				t.near(after.X - before.X, 30, 2)
				t.near(after.Y - before.Y, -20, 2)
				-- View swaps to first person and back
				Rig.click(w, "View")
				Rig.run(w, 2.5)
				local first = Layout.camera(0, false)
				local eye = roblox.Vector3.new(Layout.toWorld(w.places[SITE], first.eye[1], first.eye[2], first.eye[3]))
				t.truthy((workspace.CurrentCamera.CFrame.Position - eye).Magnitude < 0.05)
			end, opts({ touch = true }))
		end)
	end

	t.test("a full screen: the HUD leaves the bed alone in first person, and the card is in its corner", function()
		Rig.play(function(w)
			Rig.press(w, ID)
			Rig.run(w, 0.3)
			Rig.click(w, "Start (Space)")
			Rig.run(w, 2)
			t.eq(Controller.small(), false)
			t.eq(Controller.current.ctx.ui.helpFrame.Visible, true, "with a keyboard the card stays until H")
			local hidden = 0
			for i = 0, 20 do
				for j = 0, 40 do
					if
						covered(
							w,
							-Sim.HALF_WIDTH + i / 20 * 2 * Sim.HALF_WIDTH,
							-Sim.HALF_LENGTH + j / 40 * 2 * Sim.HALF_LENGTH
						)
					then
						hidden += 1
					end
				end
			end
			t.truthy(
				hidden <= 0.02 * 21 * 41,
				`{hidden} of {21 * 41} points of the bed are under the HUD at 1920 by 1080`
			)
			t.eq(covered(w, 0, Sim.HALF_LENGTH), nil, "the far goal is in sight")
		end, opts())
	end)

	t.test("a lost part of the log is asked for again: the match goes on, exact, and nobody is told off", function()
		Rig.play(function(w)
			local session = w.svc:sessionOf(ID)
			Rig.press(w, ID)
			Rig.run(w, 0.3)
			Rig.click(w, "Start (Space)")
			Rig.run(w, 0.4)
			local tbl = tableOf(w)
			local hand = Line.hands.chaser(1)
			local shown = {}
			play(w, 3, hand, nil, shown)
			-- one message of the log never arrives
			local lost = false
			for i, m in w.up do
				if m.payload.verb == "log" then
					table.remove(w.up, i)
					lost = true
					break
				end
			end
			if not lost then
				-- (none on the way this frame: the next one sent is the one lost)
				local sent = Rig.count(w.sent, "log")
				Rig.untilTrue(w, 1, function()
					return Rig.count(w.sent, "log") > sent
				end)
				for i, m in w.up do
					if m.payload.verb == "log" then
						table.remove(w.up, i)
						lost = true
						break
					end
				end
			end
			t.truthy(lost, "a log message was lost on the way")
			local toasts = #w.toasts
			play(w, 6, hand, nil, shown)
			t.eq(session.phase, "playing", "she was not taken off")
			t.eq(#w.toasts, toasts, "no words about it: " .. table.concat(w.toasts, " | "))
			t.truthy(nowTick(w) - tbl.ref.n < 96, `the referee is {nowTick(w) - tbl.ref.n} ticks behind the clock`)
			local again = Rig.last(w.got, "air_hockey_seat", function(m)
				return m.again == true
			end)
			t.truthy(again, "the table asked for the log again")
			-- and nothing of her hand was lost: the whole match on her screen is still the referee's, uncorrected
			local seat = Controller.current.seat
			t.eq(seat.resims, 0)
			t.eq(seat.replica.desyncs, 0)
			local worst, _, n = apart(shown, truth(w))
			t.truthy(n > 400)
			t.truthy(worst[1] < EXACT and worst[2] < EXACT, `puck {worst[1]} m, mallet {worst[2]} m`)
		end, opts())
	end)

	t.test(
		"a line that stalls for three seconds and then delivers everything at once: a handful of messages",
		function()
			Rig.play(function(w)
				local session = w.svc:sessionOf(ID)
				Rig.press(w, ID)
				Rig.run(w, 0.3)
				Rig.click(w, "Start (Space)")
				Rig.run(w, 0.4)
				local tbl = tableOf(w)
				local hand = Line.hands.chaser(1)
				play(w, 3, hand)
				-- nothing gets through either way for three seconds
				local release = w.frames + 180
				local sentBefore = Rig.count(w.sent, "log")
				for _ = 1, 180 do
					for _, m in w.up do
						m.at = math.max(m.at, release)
					end
					for _, m in w.down do
						m.at = math.max(m.at, release)
					end
					play(w, 1 / 60, hand)
				end
				local queued = Rig.count(w.sent, "log") - sentBefore
				t.truthy(
					queued <= 16,
					`{queued} log messages were queued in the stall (the Net lets 40 through at once and drops the rest)`
				)
				-- the worst case all the same: two of them are dropped as the queue is delivered
				local dropped = 0
				for i = #w.up, 1, -1 do
					if w.up[i].payload.verb == "log" and dropped < 2 and i % 2 == 0 then
						table.remove(w.up, i)
						dropped += 1
					end
				end
				local toasts = #w.toasts
				play(w, 4, hand)
				t.eq(session.phase, "playing")
				t.eq(#w.toasts, toasts, table.concat(w.toasts, " | "))
				t.truthy(nowTick(w) - tbl.ref.n < 96, `the referee is {nowTick(w) - tbl.ref.n} ticks behind the clock`)
				t.eq(Controller.current.seat.replica.desyncs, 0)
				local logs = Rig.count(w.sent, "log")
				play(w, 2, hand)
				t.truthy(Rig.count(w.sent, "log") - logs >= 18, "and the log is back to ten messages a second")
			end, opts())
		end
	)

	t.test("against a person: a lost part of the log is mended there too, and her mallet is hers again", function()
		Rig.play(function(w)
			local session = w.svc:sessionOf(ID)
			Rig.press(w, ID)
			Rig.run(w, 0.3)
			local bob = bot(w, "Bob", Line.hands.chaser(1.5))
			t.truthy(w.svc:join(bob.stub, EMBER))
			Rig.click(w, "Start (Space)")
			Rig.run(w, 0.4)
			local tbl = tableOf(w)
			local hand = Line.hands.chaser(1)
			play(w, 3, hand, { bob })
			local lost = Rig.untilTrue(w, 1, function()
				botFrame(w, bob)
				for i, m in w.up do
					if m.payload.verb == "log" then
						table.remove(w.up, i)
						return true
					end
				end
				return false
			end)
			t.truthy(lost)
			local toasts = #w.toasts
			play(w, 2, hand, { bob })
			local shown = {}
			play(w, 6, hand, { bob }, shown)
			t.eq(session.phase, "playing")
			t.eq(seatedNames(w), "Ann, Bob", "nobody was taken off")
			t.eq(#w.toasts, toasts, table.concat(w.toasts, " | "))
			t.eq(#bob.refused, 0)
			local worst = apart(shown, truth(w))
			t.truthy(worst[2] < EXACT, `Ann's mallet on her screen is the referee's again ({worst[2]} m)`)
			t.truthy(tbl.ref.got[0] > nowTick(w) - 96, "her log is up to the clock")
		end, opts())
	end)

	t.test("against a person on a line too slow for a live match (400 ms each way): she is told so", function()
		Rig.play(function(w)
			local Game = require("@server/Minigames/Games/AirHockey")
			Rig.press(w, ID)
			Rig.run(w, 1.2)
			local bob = bot(w, "Bob", Line.hands.chaser(1.5))
			t.truthy(w.svc:join(bob.stub, EMBER))
			Rig.click(w, "Start (Space)")
			Rig.run(w, 1.2)
			local tbl = tableOf(w)
			t.eq(Referee_mode(tbl), "2")
			play(w, 10, Line.hands.chaser(1), { bob })
			t.truthy(tbl.ref.cut[0] > 240, `{tbl.ref.cut[0]} ticks were played without her hand`)
			t.eq(tbl.ref.cut[1], 0, "none without his")
			local told = Rig.last(w.got, "event", function(m)
				return m.text == Game.SLOW_WORDS
			end)
			t.truthy(told, "she is told her connection is too slow for a live match")
			t.eq(
				Rig.last(bob.stub.events, "event", function(m)
					return m.text == Game.SLOW_WORDS
				end),
				nil,
				"he is not"
			)
			local times = 0
			for _, m in w.got do
				if m.kind == "event" and m.text == Game.SLOW_WORDS then
					times += 1
				end
			end
			t.truthy(times <= 2, `told {times} times in ten seconds, not on every tick`)
		end, opts({ lag = 24 }))
	end)

	-- The animal rule (the common bar's C12): a squirrel on the table never spoils a match.
	do
		local beasts: { any } = {}
		local knocks: { any } = {}
		local service = {
			animals = function(): { any }
				return beasts
			end,
			knock = function(id: any, x: number, y: number, z: number, text: string)
				table.insert(knocks, { id = id, x = x, y = y, z = z, text = text })
				for _, a in beasts do
					if a.id == id then
						a.x, a.y, a.z = x, y, z
					end
				end
			end,
		}
		t.test(
			"a squirrel on the table: the puck or a mallet knocks it to the floor, both are told, and the match is untouched",
			function()
				table.clear(beasts)
				table.clear(knocks)
				Rig.play(function(w)
					local session = w.svc:sessionOf(ID)
					local place = w.places[SITE]
					local function beast(id: string, kind: string, x: number, y: number, up: number): any
						local wx, wy, wz = Layout.toWorld(place, x, y)
						return { id = id, kind = kind, x = wx, y = wy + up, z = wz }
					end
					-- before anyone plays, a squirrel may sit on the table: nothing is looked for, nothing is sent
					table.insert(beasts, beast("early", "squirrel", 0, 0, 0.5))
					Rig.run(w, 1)
					t.eq(#knocks, 0, "an idle table is anybody's")
					table.clear(beasts)
					Rig.press(w, ID)
					Rig.run(w, 0.3)
					Rig.click(w, "Start (Space)")
					Rig.run(w, 0.4)
					t.eq(session.phase, "playing")
					local tbl = tableOf(w)
					-- one under the table on the floor, one on the floor beside it, one standing on the Ember
					-- end's home, where that mallet is, and the Spicy Rodent out in the middle of this half
					local floor = Layout.BED_Y - 0.5
					table.insert(beasts, beast("under", "squirrel", 0.2, -0.5, -floor))
					local ax, ay, az = Layout.aisle(place, 0)
					table.insert(beasts, { id = "beside", kind = "squirrel", x = ax, y = ay, z = az })
					table.insert(beasts, beast("on", "squirrel", 0.05, 0.8, 0.5))
					table.insert(beasts, beast("rod", "rodent", -0.35, -0.45, 0.5))
					local shown = {}
					play(w, 0.5, Line.hands.still, nil, shown)
					t.eq(#knocks, 1, "the one the mallet stands on is knocked off at once")
					t.eq(knocks[1].id, "on")
					t.eq(knocks[1].text, "The air hockey table is in play: you were knocked off it")
					local x, y = Layout.onTable(place, knocks[1].x, knocks[1].y, knocks[1].z)
					t.truthy(x == nil and y == nil, "it lands off the table...")
					local _, Y, D = AlleyLayout.toLocal(place, knocks[1].x, knocks[1].y, knocks[1].z)
					t.truthy(Y < 1 and D < Layout.footprint().d0 - 1, "...on the floor, on the room's side")
					local told = Rig.last(w.got, "event", function(m)
						return m.intruder == true
					end)
					t.eq(told.text, "A squirrel was on the table: knocked clear. The match goes on")
					t.truthy(Rig.has(Rig.texts(w.gui), "A squirrel was on the table"), Rig.screen(w))
					-- the Spicy Rodent sits where the puck will come: the hand goes for the puck until it is hit
					play(w, 30, Line.hands.pointer(0.02), nil, shown, function()
						return #knocks >= 2
					end)
					t.eq(#knocks, 2, "the puck or the mallet reached the Spicy Rodent")
					t.eq(knocks[2].id, "rod")
					play(w, 3, Line.hands.pointer(0.02), nil, shown)
					told = Rig.last(w.got, "event", function(m)
						return m.intruder == true
					end)
					t.eq(told.text, "The Spicy Rodent was on the table: knocked clear. The match goes on")
					t.eq(#knocks, 2, "the one under the table and the one beside it are left alone")
					-- and nothing an animal did was ever in the match: the screen is still the referee's, bit for bit
					local worst, _, n = apart(shown, truth(w))
					t.truthy(n > 100)
					t.truthy(
						worst[1] < EXACT and worst[2] < EXACT and worst[3] < EXACT,
						`{worst[1]} {worst[2]} {worst[3]}`
					)
					t.eq(Controller.current.seat.resims, 0)
					t.eq(Controller.current.seat.replica.desyncs, 0)
					t.eq(session.phase, "playing")
					t.truthy(tbl.ref.n > 240 * 3)
				end, opts({ service = service }))
			end
		)
	end

	-- Being bitten at the table (the common bar's C13): the body is taken, the game lets go at once.
	t.test(
		"bitten at the table: the camera and legs come back at once with the reason, and the computer takes the end",
		function()
			Rig.play(function(w)
				local session = w.svc:sessionOf(ID)
				-- against the computer: the table is nobody's afterwards
				Rig.press(w, ID)
				Rig.run(w, 0.3)
				Rig.click(w, "Start (Space)")
				play(w, 3, Line.hands.chaser(1))
				t.eq(session.phase, "playing")
				t.eq(w.held, true)
				w.svc:leave(w.player, "bitten", "You were bitten: you left the air hockey table")
				Rig.run(w, 0.3)
				t.eq(w.client.active(), nil, "the game let go")
				t.eq(w.held, false, "the camera is the player's again")
				t.eq(w.controls[#w.controls], true, "and so are their legs")
				t.truthy(
					Rig.has(w.toasts, "You were bitten: you left the air hockey table"),
					table.concat(w.toasts, " | ")
				)
				t.eq(Controller.current, nil, "nothing of the game is left running")
				t.eq(session.phase, "idle", "alone against the computer: the table is free")
				local tbl = tableOf(w)
				t.eq(tbl.ref, nil)
				local px, py = where(w, Layout.PUCK)
				t.near(px, 0, 1e-4)
				t.near(py, 0, 1e-4, "the puck is back on the spot")
				-- against a person: she is bitten, he plays on against the computer without a break
				Rig.press(w, ID)
				Rig.run(w, 0.3)
				local bob = bot(w, "Bob", Line.hands.chaser(1.5))
				t.truthy(w.svc:join(bob.stub, ID))
				Rig.run(w, 0.3)
				Rig.click(w, "Start (Space)")
				play(w, 4, Line.hands.chaser(1), { bob })
				tbl = tableOf(w)
				t.eq(Referee_mode(tbl), "2")
				local n = tbl.ref.n
				w.svc:leave(w.player, "bitten", "You were bitten: you left the air hockey table")
				for _ = 1, 180 do
					Rig.frame(w)
					botFrame(w, bob)
				end
				t.eq(w.client.active(), nil)
				t.eq(w.held, false)
				t.eq(w.controls[#w.controls], true)
				t.eq(session.phase, "playing", "his match goes on")
				t.eq(seatedNames(w), "Club (computer), Bob")
				t.eq(Referee_mode(tbl), "1", "the computer has her end")
				t.truthy(tbl.ref.n > n + 240 * 2, "without a break")
				t.eq(#bob.refused, 0, table.concat(bob.refused, "; "))
				t.eq(bob.seat.replica.desyncs, 0)
				t.eq(Rig.last(bob.stub.events, "event").text, "Ann left: the computer takes the Glacier end")
			end, opts())
		end
	)

	t.test("the server check's flow (tests/engine/AirHockeyFlow) passes on this service", function()
		Rig.play(function(w)
			local ann, bob = Rig.stub("Ann"), Rig.stub("Bob")
			local out = AirHockeyFlow.play(w.svc, { Seat = Seat, Sim = Sim, Layout = Layout }, {
				players = { ann, bob },
				step = function(seconds: number)
					Rig.run(w, seconds)
				end,
				stamp = function(): number
					return workspace:GetServerTimeNow()
				end,
			})
			t.truthy(out.ok, table.concat(out.failures, "; "))
			t.truthy(out.numbers.ticks > 240 * 4, `{out.numbers.ticks} ticks decided`)
			t.eq(out.numbers.winner, 0)
			t.eq(out.numbers.hardware, 1, "the flow saw the table's hardware")
		end, opts({ stand = { site = SITE, x = -20, y = 3, d = -40 } }))
	end)

	t.test("the layout the rig stood the table on is the bake's (one source: Layout)", function()
		t.eq(#Layout.stations({ bowling_alley = { x = 0, z = 0, floorY = 0, yaw = 0 } }), 2)
		t.eq(Rules.computerFor("hard"), "Pro")
		t.eq(Wire.SEGMENT_SOLO, 24)
	end)
end
