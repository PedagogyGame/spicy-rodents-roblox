--!strict
-- tests/isolated/pinball_client.luau: cases for tests/unit/pinball_client.spec.luau, run in their own Lune
-- process (tests/lib/Isolated) because they install the fake engine.
-- Pinball played through all of its glue at once on tests/lib/MinigameRig: the real MinigameService with the
-- game's Table (Server/Minigames/Games/Pinball) and the model's rules and replay, the real MinigameClient with
-- MinigameUI, the game's Controller, Hands and Cabinet, the fake lagged network with the real Net's schema and
-- rate limit between them, and the three cabinets' moving parts as fake parts under the names the bake gives
-- them (tests/unit/pinball_bake.spec.luau holds the bake to the same names). The player's hands are real key,
-- mouse, gamepad and touch events; in the whole games they are driven by the model's own computer player
-- (Pinball/Bot, NOVICE) reading what this screen shows, so a whole game goes keys -> the player's own machine
-- -> the log -> the server's replay -> the score of record.
-- Other people are PlayerLike stubs who play their balls with a Replay of their own (stubPlay()).
-- Interface: return function(t) (the spec shape)
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Bot = require("@shared/Minigames/Pinball/Bot")
local CabinetLayout = require("@shared/Minigames/Pinball/Cabinet")
local InputLog = require("@shared/Minigames/Pinball/InputLog")
local Machine = require("@shared/Minigames/Pinball/Machine")
local Physics = require("@shared/Minigames/Pinball/Physics")
local Replay = require("@shared/Minigames/Pinball/Replay")
local Tables = require("@shared/Minigames/Pinball/Tables")
local Wire = require("@shared/Minigames/Pinball/Wire")
local PinballFlow = require("@tests/engine/PinballFlow")
local Cabinet = require("@client/Minigames/Pinball/Cabinet")
local Controller = require("@client/Minigames/Pinball/Controller")
local Dmd = require("@client/Minigames/Pinball/Dmd")
local Hands = require("@client/Minigames/Pinball/Hands")
local Reach = require("@client/Minigames/Pinball/Reach")
local Layout = require("@shared/Minigames/Pinball/Layout")
local MinigameSounds = require("@client/Minigames/MinigameSounds")
local FakeEngine = require("@tests/lib/FakeEngine")
local Rig = require("@tests/lib/MinigameRig")
local roblox = require("@lune/roblox")

local SITE = "bowling_alley"
local Key = roblox.Enum.KeyCode
local BTN = Machine.BTN

local function stationOf(index: number): string
	return `pinball_{index}`
end

-- What the bake leaves in the games room, as far as the game looks for it: each machine's moving parts by name.
local function furnish(roots: { [string]: any }, places: { [string]: any })
	Cabinet.reset()
	Controller.current = nil
	table.clear(MinigameSounds.counts())
	local place = places[SITE]
	local room = FakeEngine.new("Folder", "GamesRoom")
	room.Parent = roots[SITE]
	local N = CabinetLayout.NAMES
	for index, p in AlleyLayout.PINBALLS do
		local tbl = Tables.need(Tables.forVariant(p.theme) :: string)
		local function at(X: number, Y: number, D: number): any
			return roblox.CFrame.new(AlleyLayout.toWorld(place, X, Y, D))
		end
		local X, D = CabinetLayout.at(index)
		local model = FakeEngine.model(CabinetLayout.model(index), at(X, CabinetLayout.PF_Y, D), room)
		local function part(name: string): any
			local q = FakeEngine.part(name, at(X, CabinetLayout.PF_Y, D), model)
			q.Color = roblox.Color3.fromRGB(200, 120, 40)
			return q
		end
		for i = 1, CabinetLayout.BALLS do
			part(`{N.ball}{i}`)
		end
		for i = 1, #tbl.def.flippers do
			local f = FakeEngine.model(`{N.flipper}{i}`, at(X, CabinetLayout.PF_Y, D), model)
			f.PrimaryPart = FakeEngine.part("Hub", at(X, CabinetLayout.PF_Y, D), f)
		end
		for i, t in tbl.def.targets do
			if t.kind == "drop" then
				part(`{N.drop}{i}`)
			end
		end
		for k = 1, #tbl.c.spinners do
			part(`{N.spinner}{k}`)
		end
		for i = 1, #tbl.def.lamps do
			part(`{N.lamp}{i}`)
		end
		for i = 1, #tbl.def.bumpers do
			part(`{N.bumper}{i}`)
		end
		for i = 1, #tbl.def.slings do
			part(`{N.sling}{i}`)
		end
		local plunger = FakeEngine.model(N.plunger, at(X, CabinetLayout.PF_Y, D + 2.6), model)
		plunger.PrimaryPart = FakeEngine.part("Rod", at(X, CabinetLayout.PF_Y, D + 2.6), plunger)
		part("Glass")
		local glass = part(N.backglass)
		local gui = FakeEngine.new("SurfaceGui", "Display")
		gui.Parent = glass
		for _, name in { "Title", "Score", "Info", "Say", "Best" } do
			local label = FakeEngine.new("TextLabel", name)
			label.Text = ""
			label.Parent = gui
		end
	end
end

local function opts(index: number, more: { [string]: any }?): Rig.Opts
	local X, D = CabinetLayout.stance(index)
	local o: any = { furnish = furnish, stand = { site = SITE, x = X, y = 3, d = D } }
	for k, v in more or {} do
		o[k] = v
	end
	return o
end

local function tableOf(w: Rig.World, index: number): any
	return w.svc.stations[stationOf(index)].tbl
end

local function sessionOf(w: Rig.World, index: number): any
	return w.svc:sessionOf(stationOf(index))
end

local function label(w: Rig.World, index: number, name: string): string
	local model = w.roots[SITE]:FindFirstChild("GamesRoom"):FindFirstChild(CabinetLayout.model(index))
	return model:FindFirstChild(CabinetLayout.NAMES.backglass):FindFirstChild("Display"):FindFirstChild(name).Text
end

local function ballPart(w: Rig.World, index: number, i: number): any
	local model = w.roots[SITE]:FindFirstChild("GamesRoom"):FindFirstChild(CabinetLayout.model(index))
	return model:FindFirstChild(`{CabinetLayout.NAMES.ball}{i}`)
end

-- The player's hands driven by the model's computer player, through real key presses: each frame it looks at
-- the game this screen is playing and holds the keys it wants (Left Shift, Right Shift, Space).
local KEYS = { [BTN.LEFT] = Key.LeftShift, [BTN.RIGHT] = Key.RightShift, [BTN.PLUNGE] = Key.Space }
local function hand(level: number, seed: number): any
	return { bot = Bot.new(level, seed), down = {} }
end
local function handFrame(h: any)
	local c = Controller.current
	local want = 0
	if c and c.live and c.cab.r then
		want = Bot.step(h.bot, c.cab.tbl, c.cab.r.m)
	end
	for b, code in KEYS do
		local on = bit32.band(want, b) ~= 0
		if on ~= (h.down[b] == true) then
			h.down[b] = on
			Rig.key(code, on)
		end
	end
end

-- Another person at the machine: a PlayerLike stub with a copy of the game of its own, fed what the service
-- sends it (snapshots, relayed segments, a seat that has gone) and playing its own balls live with the computer
-- player's hands, its log sent as the client sends it (InputLog.pack, the sum and the snapshot's number). The
-- stub is on a line as slow as the rig's own (w.lag frames each way, or `lag`): what the service sends it is
-- read that many frames later, and what it sends reaches the service that many frames later, in order.
local function person(name: string, seed: number, lag: number?): any
	return {
		stub = Rig.stub(name),
		read = 0,
		r = nil,
		g = 0,
		v = 0,
		seat = nil,
		bot = Bot.new(1, seed),
		live = false,
		rec = nil,
		tick0 = 0,
		frame0 = 0,
		sent = 0,
		refused = {},
		notes = {},
		lag = lag,
		seenAt = {}, -- event index -> the frame it was sent at
		outbox = {}, -- { at, verb, args }
		stopped = false, -- (stops sending: a line gone dead)
	}
end

local function personFrame(w: Rig.World, p: any, id: string)
	local lag = p.lag or w.lag
	local events = p.stub.events
	for i = #p.seenAt + 1, #events do
		p.seenAt[i] = w.frames
	end
	-- what was sent to it on the way in
	while p.read < #events and w.frames - p.seenAt[p.read + 1] >= lag do
		p.read += 1
		local msg = events[p.read]
		if msg.kind == "pinball_sync" then
			p.r = Wire.restore(msg.snap)
			p.g = msg.g
			p.v = msg.v or p.v
			p.live = false
		elseif msg.kind == "pinball" and p.r and msg.g == p.g and not p.live then
			local seg = InputLog.unpack(msg.from, msg.to, msg.packed)
			if seg then
				Replay.follow(p.r, msg.seat, seg)
			end
		elseif msg.kind == "pinball_retire" and msg.g == p.g then
			table.insert(p.notes, msg)
		elseif msg.kind == "state" then
			p.seat = msg.you or p.seat
		elseif msg.kind == "joined" then
			p.seat = msg.seat
		end
	end
	-- what it sent, on the way out
	while p.outbox[1] and p.outbox[1].at <= w.frames do
		local item = table.remove(p.outbox, 1)
		local ok, why = Rig.input(w, p.stub, id, item.verb, item.args)
		if not ok then
			table.insert(p.refused, tostring(why))
		end
	end
	local r = p.r
	if r == nil or p.stopped then
		return
	end
	-- a seat that has gone is passed over from the server's tick on (at once while this copy is ahead of it)
	for i = #p.notes, 1, -1 do
		local note = p.notes[i]
		if p.live or r.tick >= note.tick then
			if r.m.up ~= note.seat then
				Replay.retire(r, note.seat)
			end
			table.remove(p.notes, i)
		end
	end
	local mine = p.seat ~= nil and not Replay.over(r) and r.m.up == p.seat
	if mine and not p.live then
		p.live = true
		p.rec = Replay.recorder(r)
		p.tick0 = r.tick
		p.frame0 = w.frames
	elseif not mine then
		p.live = false
	end
	if p.live then
		local tbl = Tables.need(r.id)
		local due = p.tick0 + (w.frames - p.frame0) * 4
		while r.tick < due do
			local seg = Replay.live(r, p.rec, Bot.step(p.bot, tbl, r.m))
			if seg then
				local a, b, c = InputLog.pack(seg)
				table.insert(p.outbox, { at = w.frames + lag, verb = "log", args = { a, b, c, Replay.sum(r), p.v } })
				p.sent += 1

				if Replay.over(r) or r.m.up ~= p.seat then
					p.live = false
					break
				end
			end
		end
	end
end

-- frames with the hand on the keys (and the other people at their machines), until cond() or the time runs out
local function playFor(
	w: Rig.World,
	seconds: number,
	h: any?,
	cond: (() -> boolean)?,
	people: { any }?,
	id: string?
): boolean
	for _ = 1, math.floor(seconds * 60) do
		if cond and cond() then
			return true
		end
		if h then
			handFrame(h)
		end
		Rig.frame(w)
		for _, p in people or {} do
			personFrame(w, p, id or stationOf(1))
		end
	end
	return cond ~= nil and cond()
end

-- A point of a machine's playfield on the screen (pixels), through the camera as it is.
local function onScreen(w: Rig.World, index: number, x: number, y: number): any
	local X, Y, D = CabinetLayout.point(index, x, y, 0)
	local wx, wy, wz = AlleyLayout.toWorld(w.places[SITE], X, Y, D)
	return (workspace.CurrentCamera:WorldToViewportPoint(roblox.Vector3.new(wx, wy, wz)))
end

-- Every part of the HUD that is drawn now, as rectangles of the screen: { name, x0, y0, x1, y1 } (pixels). The
-- HUD's own frame starts under the top bar (Controller.INSET: the engine's GetGuiInset where there is one).
local function hud(_w: Rig.World): { { any } }
	local ui = Controller.current.ctx.ui
	local size = workspace.CurrentCamera.ViewportSize
	local inset = Controller.INSET
	local gh = size.Y - inset
	local function rect(frame: any): (number, number, number, number)
		local p, z = frame.Position, frame.Size
		local x0 = p.X.Scale * size.X + p.X.Offset
		local y0 = inset + p.Y.Scale * gh + p.Y.Offset
		return x0, y0, x0 + z.X.Scale * size.X + z.X.Offset, y0 + z.Y.Scale * gh + z.Y.Offset
	end
	local out: { { any } } = {}
	if ui.helpFrame.Visible then
		table.insert(out, { "help", rect(ui.helpFrame) })
	end
	if ui.statusLabel.Visible and ui.statusLabel.Text ~= "" then
		table.insert(out, { "status", rect(ui.statusLabel) })
	end
	if ui.clockLabel.Visible then
		table.insert(out, { "clock", rect(ui.clockLabel) })
	end
	if ui.card.Visible then
		table.insert(out, { "card", rect(ui.card) })
	end
	local banner = ui.bannerLabel
	if banner.Text ~= "" and banner.TextTransparency < 1 then
		table.insert(out, { "banner", rect(banner) })
	end
	local dmd = Controller.current.dmd
	if dmd and dmd.frame.Visible then
		table.insert(out, { "dmd", rect(dmd.frame) })
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

-- A person's torso and two arms on a body (the stock R15 rig's joints and offsets, every part where those joints
-- rest it), as far as Pinball/Reach looks at it.
local function armed(body: any): any
	local V, C = roblox.Vector3, roblox.CFrame
	local at = body.PrimaryPart.CFrame
	local function part(n: string, x: number, y: number): any
		return FakeEngine.part(n, at * C.new(x, y, 0), body)
	end
	local function motor(n: string, p0: any, p1: any, c0: any, c1: any)
		local m = FakeEngine.new("Motor6D", n)
		m.Part0, m.Part1, m.C0, m.C1, m.Transform = p0, p1, C.new(c0), C.new(c1), C.new()
		m.Parent = p1
	end
	local lower, torso = part("LowerTorso", 0, -0.8), part("UpperTorso", 0, 0.2)
	motor("Waist", lower, torso, V.new(0, 0.2, 0), V.new(0, -0.8, 0))
	for _, s in { { "Right", 1 }, { "Left", -1 } } do
		local side, k = s[1] :: string, s[2] :: number
		local upper = part(`{side}UpperArm`, 1.5 * k, 0.369)
		local fore = part(`{side}LowerArm`, 1.5 * k, -0.224)
		local palm = part(`{side}Hand`, 1.5 * k, -0.85)
		motor(`{side}Shoulder`, torso, upper, V.new(k, 0.563, 0), V.new(-0.5 * k, 0.394, 0))
		motor(`{side}Elbow`, upper, fore, V.new(0, -0.334, 0), V.new(0, 0.259, 0))
		motor(`{side}Wrist`, fore, palm, V.new(0, -0.501, 0), V.new(0, 0.125, 0))
	end
	return body
end

local function jointOf(body: any, name: string): any
	for _, d in body:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end

-- the lower torso where the body's root has it (the engine's Root joint, solved before Stepped)
local function settleBody(body: any)
	jointOf(body, "Waist").Part0.CFrame = body.PrimaryPart.CFrame * roblox.CFrame.new(0, -0.8, 0)
end

-- Where a body's joints, as they are written now, put its hands, elbows and shoulders, and how its upper torso
-- stands (forward from the lower torso through each joint: Part1 = Part0 * C0 * Transform * C1^-1).
local function armsOf(body: any): any
	local waist = jointOf(body, "Waist")
	local torso = waist.Part0.CFrame * waist.C0 * waist.Transform * waist.C1:Inverse()
	local out: any = { torso = torso }
	for _, side in { "Left", "Right" } do
		local sh, el, wr = jointOf(body, `{side}Shoulder`), jointOf(body, `{side}Elbow`), jointOf(body, `{side}Wrist`)
		local upper = torso * sh.C0 * sh.Transform * sh.C1:Inverse()
		local fore = upper * el.C0 * el.Transform * el.C1:Inverse()
		out[side] = {
			shoulder = (torso * sh.C0).Position,
			elbow = (upper * el.C0).Position,
			hand = (fore * wr.C0 * wr.C1:Inverse()).Position,
		}
	end
	return out
end

local function posedNow(body: any): boolean
	local I = roblox.CFrame.new()
	return jointOf(body, "LeftShoulder").Transform ~= I
		or jointOf(body, "RightShoulder").Transform ~= I
		or jointOf(body, "Waist").Transform ~= I
end

return function(t)
	t.test(
		"a whole game alone: walk up, E, Space starts, three balls played with the keys on this screen's own machine, the server's replay agrees to the point, the end card and the board",
		function()
			Rig.play(function(w)
				local ID = stationOf(1)
				Rig.run(w, 0.1)
				t.eq(Rig.prompt(w, ID).ObjectText, "ACORN ATTACK - open (alone or with friends)")
				t.eq(Rig.prompt(w, ID).ActionText, "Play")
				Rig.press(w, ID)
				Rig.run(w, 0.3)
				t.eq(w.client.active(), ID)
				t.truthy(Rig.has(Rig.texts(w.gui), "ACORN ATTACK"), Rig.screen(w))
				t.eq(sessionOf(w, 1).phase, "lobby")
				-- Space starts at once (the controller sends it, once)
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.run(w, 0.4)
				t.eq(sessionOf(w, 1).phase, "playing")
				t.eq(Rig.count(w.sent, "start"), 1)
				local c = Controller.current
				t.truthy(c and c.live, "this player's ball is played here")
				t.eq(Cabinet.hearFrom(c.cab), nil, "the player's own machine is heard flat")
				t.truthy(w.held, "the camera is on the playfield")
				t.eq(Rig.prompt(w, ID).ActionText, "In use")
				t.eq(Rig.prompt(w, ID).ObjectText, "ACORN ATTACK - in use by Ann: watch the ball")
				t.eq(w.controls[#w.controls], false, "the legs are the machine's")
				-- the whole game, the hand on the keys
				local h = hand(1, 11)
				local ended = playFor(w, 600, h, function()
					return sessionOf(w, 1).phase == "done"
				end)
				t.truthy(ended, "the game ended")
				local view = w.svc:sessionOf(ID)
				local result = view.result
				t.truthy(result ~= nil)
				-- the score of record is the server's replay; this screen's copy came to the same game
				local server = tableOf(w, 1):replay()
				t.truthy(server ~= nil and Replay.over(server))
				local mine = c.cab.r
				t.eq(mine.m.scores[1], server.m.scores[1], "this screen and the server agree to the point")
				t.eq(result.scores[1], server.m.scores[1])
				t.truthy(result.scores[1] > 0, `a game scores something ({result.scores[1]})`)
				t.eq(result.fair, true, "played in time: the game may take a place on the board")
				-- ten messages a second at most, never a message a frame
				local logs = Rig.count(w.sent, "log")
				local seconds = server.tick / 240
				t.truthy(logs <= seconds * 11.5 + 5, `{logs} log messages in {seconds} s of play`)
				t.truthy(logs >= seconds * 5, `{logs} log messages in {seconds} s of play`)
				-- the end card, the camera and the legs back, the board on the cabinet
				Rig.run(w, 0.3)
				t.truthy(Rig.has(Rig.texts(w.gui), "Play again"), Rig.screen(w))
				t.falsy(w.held, "the camera is the player's again")
				local best = w.roots[SITE]:FindFirstChild("GamesRoom"):FindFirstChild("Pinball1"):GetAttribute("Best")
				t.truthy(type(best) == "string" and string.find(best, "OLD OAK", 1, true) ~= nil, tostring(best))
				-- sounds were asked for by name, the machine's own set
				local counts = MinigameSounds.counts()
				t.truthy((counts["pinball.acorn.flip_up"] or 0) > 0, "flipper sounds")
				t.truthy((counts["pinball.acorn.drain"] or 0) > 0, "drain sounds")
				Rig.key(Key.Q, true)
				Rig.run(w, 0.3)
				t.eq(w.client.active(), nil)
			end, opts(1))
		end
	)

	t.test(
		"two players take a ball each in turn: the camera and the legs are given back while the other plays, the screen follows the other's ball half a second behind, every copy ends on the server's score",
		function()
			Rig.play(function(w)
				local ID = stationOf(3)
				local bob = person("Bob", 5)
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				t.truthy(w.svc:join(bob.stub, ID))
				Rig.run(w, 0.3)
				t.eq(#sessionOf(w, 3).seats, 2)
				t.truthy(Rig.has(Rig.texts(w.gui), "2 of 4 players"), Rig.screen(w))
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.run(w, 0.4)
				t.eq(sessionOf(w, 3).phase, "playing")
				local h = hand(1, 3)
				local c = Controller.current
				local ups: { number } = {}
				local followed, released, behind = 0, 0, 0
				local server = tableOf(w, 3):replay()
				local ok = playFor(w, 900, h, function()
					local r = tableOf(w, 3):replay()
					if r and ups[#ups] ~= r.m.up and not Replay.over(r) then
						table.insert(ups, r.m.up)
					end
					if c.cab.r and c.cab.r.m.up == 2 and not c.live and c.cab.r.m.phase == Machine.PHASE.PLAY then
						-- Bob's ball on Ann's screen: drawn a little behind the newest tick she has
						followed += 1
						if not w.held then
							released += 1
						end
						if c.cab.newest - c.cab.at >= 60 then
							behind += 1
						end
					end
					return sessionOf(w, 3).phase == "done"
				end, { bob }, ID)
				t.truthy(ok, "the game ended")
				t.truthy(#ups >= 5, `the ball went from one player to the other: {table.concat(ups, " ")}`)
				t.eq(ups[1], 1)
				t.eq(ups[2], 2)
				t.truthy(followed > 60, "Bob's ball was drawn on Ann's screen")
				t.eq(released, followed, "Ann had her own camera while Bob played")
				t.truthy(behind > followed * 0.7, `drawn half a second behind ({behind} of {followed} frames)`)
				server = tableOf(w, 3):replay()
				local result = sessionOf(w, 3).result
				for seat = 1, 2 do
					t.eq(c.cab.r.m.scores[seat], server.m.scores[seat], `Ann's copy, seat {seat}`)
					t.eq(bob.r.m.scores[seat], server.m.scores[seat], `Bob's copy, seat {seat}`)
					t.eq(result.scores[seat], server.m.scores[seat])
				end
				t.eq(#bob.refused, 0, table.concat(bob.refused, ", "))
				t.eq(result.fair, true)
			end, opts(3))
		end
	)

	t.test(
		"a late watcher is sent the game as it stands and sees the same ball; walking off puts the cabinet to rest; the machine idle again runs its attract show",
		function()
			Rig.play(function(w)
				local ID = stationOf(2)
				local bob = person("Bob", 9)
				-- Ann stands well away; Bob plays
				Rig.walkTo(w, SITE, 60, 3, 0)
				t.truthy(w.svc:join(bob.stub, ID))
				Rig.run(w, 0.2)
				t.truthy(Rig.input(w, bob.stub, ID, "start"))
				playFor(w, 8, nil, nil, { bob }, ID)
				t.eq(Rig.count(w.got, "pinball"), 0, "nothing is sent to someone across the alley")
				t.eq(Rig.count(w.got, "pinball_sync"), 0)
				-- Ann walks up: she is sent the game as it stands, then every segment
				local X, D = CabinetLayout.stance(2)
				Rig.walkTo(w, SITE, X + 2, 3, D + 3)
				playFor(w, 1.5, nil, nil, { bob }, ID)
				t.eq(Rig.count(w.got, "pinball_sync"), 1, "the late watcher's snapshot")
				t.truthy(Rig.count(w.got, "pinball") > 5, "and the segments after it")
				local cab = Cabinet.get(ID)
				t.truthy(cab.awake and cab.mode == "follow")
				-- Bob's machine is heard from the cabinet, not flat in Ann's ears
				local from = Cabinet.hearFrom(cab)
				local under = from
				while under ~= nil and under.Name ~= "Pinball2" do
					under = under.Parent
				end
				t.truthy(under ~= nil, "heard from the machine")
				local graze = Cabinet.loudness(Machine.CUE.WALL, 1, 1.3)
				local slam = Cabinet.loudness(Machine.CUE.WALL, 1, Physics.MAX_SPEED)
				t.truthy(graze < slam * 0.25, `a graze ({graze}) is quieter than a slam ({slam})`)
				local _, p1 = Cabinet.loudness(Machine.CUE.BUMPER, 1, 1)
				local _, p2 = Cabinet.loudness(Machine.CUE.BUMPER, 2, 1)
				local _, p3 = Cabinet.loudness(Machine.CUE.BUMPER, 3, 1)
				t.truthy(p1 ~= p2 and p2 ~= p3 and p1 ~= p3, "each bumper its own pitch")
				-- she sees the same game: her copy and the server's agree tick for tick
				playFor(w, 10, nil, nil, { bob }, ID)
				local server = tableOf(w, 2):replay()
				t.truthy(cab.r ~= nil)
				local probe = Replay.clone(server)
				t.truthy(cab.r.tick <= probe.tick)
				t.eq(cab.newest, cab.r.tick)
				-- the drawn ball is the kept frame's ball, a little behind
				local seen = 0
				for i = 1, 30 do
					Rig.frame(w)
					personFrame(w, bob, ID)
					local f = cab.frame
					if f and f.nBalls > 0 and i > 2 then
						local part = ballPart(w, 2, 1)
						t.eq(part.Transparency, 0)
						seen += 1
					end
				end
				t.truthy(seen > 0, "a ball was drawn")
				t.truthy(label(w, 2, "Title") == "SPICY RODENT", label(w, 2, "Title"))
				t.truthy(string.find(label(w, 2, "Info"), "BALL", 1, true) ~= nil, label(w, 2, "Info"))
				-- a watcher's copy cannot say it missed something: it is sent the game afresh now and then
				playFor(w, 5, nil, nil, { bob }, ID)
				t.eq(Rig.count(w.got, "pinball_sync"), 2, "sent the game again after WATCH_AGAIN")
				-- Bob leaves: the machine is idle and the people near it are told; the attract show runs
				w.svc:leave(bob.stub, "left")
				Rig.run(w, 0.5)
				t.eq(sessionOf(w, 2).phase, "idle")
				t.truthy(Rig.count(w.got, "pinball_idle") >= 1)
				t.eq(cab.mode, "idle")
				local before = label(w, 2, "Score")
				Rig.run(w, 4.5)
				t.truthy(label(w, 2, "Score") ~= before or label(w, 2, "Info") ~= "", "the backglass turns its pages")
			end, opts(2))
		end
	)

	t.test(
		"a player who leaves mid-game: their balls are passed over and their score kept, the others carry on from the server's game; the last to leave lets the machine go",
		function()
			Rig.play(function(w)
				local ID = stationOf(1)
				local bob = person("Bob", 21)
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				t.truthy(w.svc:join(bob.stub, ID))
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.run(w, 0.4)
				local h = hand(1, 8)
				-- play until it is Bob's ball, then Bob goes
				t.truthy(playFor(w, 300, h, function()
					local r = tableOf(w, 1):replay()
					return r ~= nil and r.m.up == 2 and r.m.ballTicks > 240
				end, { bob }, ID))
				local syncs = Rig.count(w.got, "pinball_sync")
				local bobScore = tableOf(w, 1):replay().m.scores[2]
				w.svc:leave(bob.stub, "left")
				Rig.run(w, 0.5)
				t.truthy(
					Rig.count(w.got, "pinball_sync") > syncs,
					"Ann was put right: the server played Bob's ball out"
				)
				local r = tableOf(w, 1):replay()
				t.truthy(r.m.gone[2])
				t.eq(r.m.scores[2], bobScore, "Bob's score is kept")
				-- Ann plays on alone to the end
				t.truthy(playFor(w, 600, h, function()
					return sessionOf(w, 1).phase == "done"
				end))
				local c = Controller.current
				t.eq(c.cab.r.m.scores[1], tableOf(w, 1):replay().m.scores[1])
				t.eq(sessionOf(w, 1).result.scores[2], bobScore)
				-- Ann walks away from the end card: the machine lets her go and resets
				local X, D = CabinetLayout.stance(1)
				Rig.walkTo(w, SITE, X, 3, D + 30)
				Rig.run(w, 0.5)
				t.eq(w.client.active(), nil)
			end, opts(1))
		end
	)

	t.test(
		"a slow line and a hiccup on it: a fifth of a second each way, then a second's hold-up across the end of a ball; the segments that arrive ahead of the server's clock wait and are fed again, nothing is lost and the game stays fair",
		function()
			Rig.play(function(w)
				local ID = stationOf(1)
				Rig.press(w, ID)
				Rig.run(w, 0.5)
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.run(w, 1)
				local h = hand(1, 31)
				local c = Controller.current
				-- to the end of the first ball on this screen, then the line holds everything up for a second
				t.truthy(playFor(w, 300, h, function()
					return c.cab.r.m.phase == Machine.PHASE.BONUS
				end))
				w.lag = 60
				t.truthy(playFor(w, 30, h, function()
					return c.cab.r.m.phase == Machine.PHASE.PLAY and c.cab.r.m.ballTicks > 30
				end))
				w.lag = 12
				t.truthy(playFor(w, 600, h, function()
					return sessionOf(w, 1).phase == "done"
				end))
				local server = tableOf(w, 1):replay()
				t.eq(c.cab.r.m.scores[1], server.m.scores[1])
				t.eq(sessionOf(w, 1).result.fair, true)
				t.eq(tableOf(w, 1).waited, 0, "nothing ran ahead: one player's balls are one stretch of their clock")
				t.eq(#tableOf(w, 1).pending, 0)
			end, opts(1, { lag = 12 }))
		end
	)

	t.test(
		"this screen's copy drifts from the server's (a sum that does not agree): it is sent the server's game and carries on from it, once",
		function()
			Rig.play(function(w)
				local ID = stationOf(1)
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.run(w, 0.4)
				local h = hand(1, 4)
				playFor(w, 6, h)
				local c = Controller.current
				local syncs = Rig.count(w.got, "pinball_sync")
				local rolled = c.rolled
				c.cab.r.m.scores[1] += 7 -- (a copy that has come apart from the server's)
				local back, last = 0, c.cab.r.tick
				playFor(w, 3, h, function()
					if c.live then
						if c.cab.r.tick < last then
							back += 1
						end
						last = c.cab.r.tick
					end
					return false
				end)
				t.eq(Rig.count(w.got, "pinball_sync"), syncs + 1, "one snapshot put it right")
				t.eq(Rig.last(w.got, "pinball_sync").why, "drift")
				t.eq(c.rolled, rolled + 1, "this player's own hands were played again on the server's game")
				t.eq(back, 0, "and the ball never went back in time")
				t.truthy(tableOf(w, 1).stale > 0, "the segments cut before the snapshot arrived were dropped quietly")
				t.truthy(playFor(w, 600, h, function()
					return sessionOf(w, 1).phase == "done"
				end))
				t.eq(c.cab.r.m.scores[1], tableOf(w, 1):replay().m.scores[1])
				t.eq(Rig.count(w.got, "pinball_sync"), syncs + 1, "and no more were needed")
			end, opts(1, { lag = 9 }))
		end
	)

	t.test(
		"a squirrel lands on the cabinet: the glass is thumped (half a nudge, said on the backglass), once for one landing",
		function()
			local animals: { any } = {}
			Rig.play(
				function(w)
					local ID = stationOf(1)
					Rig.press(w, ID)
					Rig.run(w, 0.2)
					Rig.key(Key.Space, true)
					Rig.key(Key.Space, false)
					Rig.run(w, 0.4)
					local h = hand(1, 4)
					playFor(w, 5, h)
					local X, D = CabinetLayout.at(1)
					local x, y, z = AlleyLayout.toWorld(w.places[SITE], X, CabinetLayout.PF_Y + 0.6, D)
					table.insert(animals, { id = 1, kind = "squirrel", x = x, y = y, z = z })
					playFor(w, 1.5, h)
					t.eq(Rig.count(w.got, "pinball_thump"), 1)
					local said = Rig.last(w.got, "event", function(m: any): boolean
						return string.find(tostring(m.text), "thumped the glass", 1, true) ~= nil
					end)
					t.truthy(said ~= nil, "the words were sent")
					t.truthy(Rig.has(Rig.texts(w.gui), "thumped the glass"), Rig.screen(w))
					table.clear(animals)
					playFor(w, 2, h)
					local r = tableOf(w, 1):replay()
					t.falsy(r.m.tilted, "a thump never tilts")
					local syncs = Rig.count(w.got, "pinball_sync")
					-- the thump went into the log where the server granted it: the two games are one to the end
					t.truthy(playFor(w, 900, h, function()
						return sessionOf(w, 1).phase == "done"
					end))
					t.eq(Controller.current.cab.r.m.scores[1], tableOf(w, 1):replay().m.scores[1])
					t.eq(Rig.count(w.got, "pinball_sync"), syncs, "no resync was needed")
					t.eq(#w.broken, 0)
				end,
				opts(1, {
					lag = 9,
					service = {
						animals = function(): { any }
							return animals
						end,
					},
				})
			)
		end
	)

	t.test(
		"at 150 ms each way: a waiting player who leaves during your ball changes nothing on your screen (no rewind, no snapshot, nothing you pressed is lost); their balls are passed over",
		function()
			Rig.play(function(w)
				local ID = stationOf(1)
				local bob = person("Bob", 21)
				Rig.press(w, ID)
				Rig.run(w, 0.3)
				t.truthy(w.svc:join(bob.stub, ID))
				Rig.run(w, 0.3)
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.run(w, 0.5)
				local h = hand(1, 8)
				local c = Controller.current
				t.truthy(playFor(w, 60, h, function()
					return c.live and c.cab.r.m.ballTicks > 1200
				end, { bob }, ID))
				local syncs = Rig.count(w.got, "pinball_sync")
				w.svc:leave(bob.stub, "left")
				local back, last = 0, c.cab.r.tick
				playFor(w, 3, h, function()
					if c.live then
						if c.cab.r.tick < last then
							back += 1
						end
						last = c.cab.r.tick
					end
					return false
				end)
				t.eq(back, 0, "the ball never went back")
				t.eq(Rig.count(w.got, "pinball_sync"), syncs, "no snapshot")
				t.truthy(c.cab.r.m.gone[2], "Ann's copy passes Bob over")
				t.truthy(playFor(w, 900, h, function()
					return sessionOf(w, 1).phase == "done"
				end))
				local server = tableOf(w, 1)
				t.eq(c.cab.r.m.scores[1], server:replay().m.scores[1], "the server's game is Ann's")
				t.eq(server.stale, 0, "nothing she sent was dropped")
				t.eq(Rig.count(w.got, "pinball_sync"), syncs, "to the end")
				t.eq(sessionOf(w, 1).result.fair, true)
			end, opts(1, { lag = 9 }))
		end
	)

	t.test(
		"at 150 ms each way, a two-and-a-half second stall in the middle of a ball (nothing crosses the line, then it all arrives at once): the ball, the next ball and the place on the board are kept",
		function()
			Rig.play(function(w)
				local ID = stationOf(2)
				Rig.press(w, ID)
				Rig.run(w, 0.3)
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.run(w, 0.6)
				local h = hand(1, 12)
				local c = Controller.current
				t.truthy(playFor(w, 60, h, function()
					return c.live and c.cab.r.m.ballTicks > 900
				end))
				local server = tableOf(w, 2)
				table.clear(server.board.entries) -- (a board with room: any fair score takes a place)
				local ball = server:replay().m.ball
				local syncs = Rig.count(w.got, "pinball_sync")
				-- the stall
				local lag = w.lag
				w.lag = 1e6
				playFor(w, 2.5, h)
				t.eq(server:replay().m.ball, ball, "the server did not take the ball while nothing arrived")
				w.lag = lag
				for _, list in { w.up, w.down } do
					for _, m in list do
						if m.at > w.frames + lag then
							m.at = w.frames + 1
						end
					end
				end
				playFor(w, 2, h)
				local r = server:replay()
				t.eq(r.epoch, 0, "the server never played by itself")
				t.falsy(r.late)
				t.eq(Rig.count(w.got, "pinball_sync"), syncs, "no snapshot was needed")
				t.truthy(playFor(w, 900, h, function()
					return sessionOf(w, 2).phase == "done"
				end))
				t.eq(c.cab.r.m.scores[1], server:replay().m.scores[1])
				t.eq(sessionOf(w, 2).result.fair, true)
				Rig.run(w, 0.4)
				local state = Rig.last(w.got, "state")
				t.eq(state and state.place, 1, "a place on the machine's board")
			end, opts(2, { lag = 9 }))
		end
	)

	t.test(
		"a watcher who walks up during the end card sees the game that has just ended (its score and GAME OVER), not the attract show",
		function()
			Rig.play(function(w)
				local ID = stationOf(3)
				local bob = person("Bob", 3)
				Rig.walkTo(w, SITE, 60, 3, 0)
				t.truthy(w.svc:join(bob.stub, ID))
				Rig.run(w, 0.2)
				t.truthy(Rig.input(w, bob.stub, ID, "start"))
				playFor(w, 6, nil, nil, { bob }, ID)
				for _ = 1, 3 do
					t.truthy(w.svc:debug(ID, "drain"))
					playFor(w, 0.5, nil, nil, { bob }, ID)
				end
				t.eq(sessionOf(w, 3).phase, "done")
				local X, D = CabinetLayout.stance(3)
				Rig.walkTo(w, SITE, X + 2, 3, D + 3)
				playFor(w, 2, nil, nil, { bob }, ID)
				local idle = 0
				for _, m in w.got do
					if m.kind == "pinball_idle" and m.station == ID then
						idle += 1
					end
				end
				t.eq(idle, 0, "not told the machine is idle")
				t.truthy(Rig.last(w.got, "pinball_sync") ~= nil, "sent the game that ended")
				t.truthy(Rig.last(w.got, "pinball_over") ~= nil, "and its board")
				t.eq(label(w, 3, "Info"), "GAME OVER")
				t.eq(label(w, 3, "Title"), "SPACE SQUIRREL")
			end, opts(3))
		end
	)

	t.test("a player who leaves the ball on the plunger for a minute is taken off and the machine reset", function()
		Rig.play(function(w)
			local ID = stationOf(1)
			Rig.press(w, ID)
			Rig.run(w, 0.2)
			Rig.key(Key.Space, true)
			Rig.key(Key.Space, false)
			Rig.run(w, 0.4)
			t.eq(sessionOf(w, 1).phase, "playing")
			Rig.run(w, 62)
			t.eq(w.client.active(), nil)
			t.truthy(Rig.has(w.toasts, "nothing was pressed for a minute"), table.concat(w.toasts, " | "))
			t.eq(sessionOf(w, 1).phase, "idle")
		end, opts(1))
	end)

	t.test(
		"every hand on the machine: the mouse buttons, a gamepad's triggers and bumpers, A and the right stick for the plunger, the left stick and Z X W for a nudge; a click on a button of the bar flips nothing",
		function()
			Rig.play(function(w)
				local ID = stationOf(1)
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.run(w, 0.4)
				local c = Controller.current
				local tbl = c.cab.tbl
				local Kind = roblox.Enum.UserInputType
				local function up(i: number): boolean
					return c.cab.r.m.phys.fa[i] > tbl.c.frest[i] + 0.5
				end
				local function pad(code: any, down: boolean)
					FakeEngine.input(
						if down then "began" else "ended",
						{ KeyCode = code, UserInputType = Kind.Gamepad1 }
					)
				end
				local function stick(code: any, x: number, y: number)
					FakeEngine.input("changed", {
						KeyCode = code,
						UserInputType = Kind.Gamepad1,
						Position = roblox.Vector3.new(x, y, 0),
					})
				end
				-- the mouse: left button the left flipper, right button the right
				Rig.mouse(true)
				FakeEngine.input("began", { UserInputType = Kind.MouseButton2 })
				Rig.run(w, 0.1)
				t.truthy(up(1) and up(2), "both flippers up from the mouse")
				Rig.mouse(false)
				FakeEngine.input("ended", { UserInputType = Kind.MouseButton2 })
				Rig.run(w, 0.3)
				t.falsy(up(1) or up(2), "and down again")
				-- a click the interface took (a button) is not a flip
				Rig.mouse(true, true)
				Rig.run(w, 0.1)
				t.falsy(up(1))
				Rig.mouse(false, true)
				-- gamepad: L2 and R1
				pad(Key.ButtonL2, true)
				pad(Key.ButtonR1, true)
				Rig.run(w, 0.1)
				t.truthy(up(1) and up(2), "triggers and bumpers")
				pad(Key.ButtonL2, false)
				pad(Key.ButtonR1, false)
				Rig.run(w, 0.3)
				-- the right stick pulled half way down draws the rod half way; let go and the ball flies
				stick(Key.Thumbstick2, 0, -0.5)
				Rig.run(w, 0.5)
				local pull = c.cab.r.m.pull / tbl.def.plunger.pullTicks
				t.near(pull, 0.5, 0.05, "the rod follows the stick")
				stick(Key.Thumbstick2, 0, 0)
				Rig.run(w, 0.2)
				t.eq(c.cab.r.m.pull, 0, "launched")
				t.truthy((MinigameSounds.counts()["pinball.acorn.plunge"] or 0) >= 1)
				-- nudges: Z, then the left stick flicked to the side
				local nudges = MinigameSounds.counts()["pinball.acorn.nudge"] or 0
				Rig.key(Key.Z, true)
				Rig.run(w, 0.05)
				Rig.key(Key.Z, false)
				Rig.run(w, 0.3)
				stick(Key.Thumbstick1, 0.95, 0)
				Rig.run(w, 0.05)
				stick(Key.Thumbstick1, 0, 0)
				Rig.run(w, 0.3)
				t.eq((MinigameSounds.counts()["pinball.acorn.nudge"] or 0) - nudges, 2, "two nudges")
				t.eq(#w.broken, 0)
			end, opts(1))
		end
	)

	t.test(
		"touch: the left and right halves of the screen are the flippers, both at once, a thumb that slides across stays its own flipper; the strip at the bottom right pulls the plunger as far as it is dragged; NUDGE",
		function()
			Rig.play(function(w)
				local ID = stationOf(2)
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				Rig.click(w, "Start (Space)")
				Rig.run(w, 0.4)
				local c = Controller.current
				t.truthy(c and c.live)
				local tbl = c.cab.tbl
				local function up(i: number): boolean
					return c.cab.r.m.phys.fa[i] > tbl.c.frest[i] + 0.5
				end
				-- the plunger strip: a finger at the bottom right dragged down a quarter of the screen
				Rig.touch("pull", "began", 1800, 700)
				Rig.touch("pull", "changed", 1800, 700 + 1080 * 0.3 * 0.8)
				Rig.run(w, 0.8)
				t.near(c.cab.r.m.pull / tbl.def.plunger.pullTicks, 0.8, 0.05)
				t.falsy(up(2), "the plunger finger is not the right flipper")
				Rig.touch("pull", "ended", 1800, 700 + 1080 * 0.24)
				Rig.run(w, 0.2)
				t.eq(c.cab.r.m.pull, 0, "launched")
				-- both thumbs
				Rig.touch("l", "began", 300, 600)
				Rig.touch("r", "began", 1500, 600)
				Rig.run(w, 0.1)
				t.truthy(up(1) and up(2))
				-- the left thumb slides across the middle: still the left flipper; lifting the right drops only it
				Rig.touch("l", "changed", 1200, 600)
				Rig.touch("r", "ended", 1500, 600)
				Rig.run(w, 0.3)
				t.truthy(up(1))
				t.falsy(up(2))
				Rig.touch("l", "ended", 1200, 600)
				Rig.run(w, 0.3)
				t.falsy(up(1))
				-- NUDGE on the touch bar
				local nudges = MinigameSounds.counts()["pinball.rodent.nudge"] or 0
				local b = Rig.button(w.gui, "NUDGE")
				b.MouseButton1Down.fire()
				Rig.run(w, 0.1)
				b.MouseButton1Up.fire()
				Rig.run(w, 0.2)
				t.eq((MinigameSounds.counts()["pinball.rodent.nudge"] or 0) - nudges, 1)
			end, opts(2, { touch = true }))
		end
	)

	t.test(
		"the server check's own flow (tests/engine/PinballFlow) passes here: solo, two by turns with a leaver, a ball the server plays out, clean ends",
		function()
			Rig.play(function(w)
				local svc = w.svc
				local result = PinballFlow.play(svc, {
					Replay = Replay,
					InputLog = InputLog,
					Bot = Bot,
					Wire = Wire,
					Tables = Tables,
				}, {
					players = { Rig.stub("Ann"), Rig.stub("Bob") },
					step = function(seconds: number)
						for _ = 1, math.max(1, math.ceil(seconds / 0.1 - 1e-6)) do
							svc:step(0.1)
						end
					end,
				})
				t.eq(table.concat(result.failures, "\n"), "")
				t.truthy(result.ok)
				t.truthy(result.numbers.soloScore > 0)
			end, opts(2))
		end
	)

	-- THE SCREEN ------------------------------------------------------------------------------------------------

	for _, screen in
		{
			{ 1920, 1080, false },
			{ 1280, 720, false },
			{ 1024, 768, false },
			{ 844, 390, true },
			{ 2340, 1080, true },
			{ 1024, 768, true },
		}
	do
		local w0, h0, touch = screen[1], screen[2], screen[3]
		t.test(
			`{w0} by {h0}{if touch then " touch" else ""}: no part of the HUD lies over the table (every point of the playfield, the flippers, the plunger and the bumpers), in either view, with a banner up; the display is up`,
			function()
				Rig.play(function(w)
					rawset(workspace.CurrentCamera, "ViewportSize", roblox.Vector2.new(w0, h0))
					local ID = stationOf(2)
					Rig.press(w, ID)
					Rig.run(w, 0.3)
					Rig.click(w, "Start (Space)")
					Rig.run(w, 0.5)
					local c = Controller.current
					t.truthy(c and c.live)
					local tbl = c.cab.tbl
					for _, which in { "play", "high" } do
						if c.view ~= which then
							Rig.key(Key.V, true)
							Rig.key(Key.V, false)
							Rig.run(w, 1)
						end
						t.eq(c.view, which)
						c.say("SOMETHING THUMPED THE GLASS!", true)
						Rig.run(w, 0.1)
						local rects = hud(w)
						local names = {}
						for _, r in rects do
							table.insert(names, r[1])
						end
						local list = table.concat(names, " ")
						t.truthy(string.find(list, "dmd", 1, true) ~= nil, list)
						t.truthy(string.find(list, "card", 1, true) ~= nil, list)
						t.truthy(string.find(list, "banner", 1, true) ~= nil, list)
						t.truthy(string.find(list, "buttons", 1, true) ~= nil, list)
						if touch then
							t.truthy(string.find(list, "touch", 1, true) ~= nil, list)
						end
						local points: { { any } } = {}
						for i = 0, 12 do
							for j = 0, 24 do
								table.insert(points, { i / 12 * Layout.WIDTH, j / 24 * Layout.LENGTH, `({i}, {j})` })
							end
						end
						for i = 1, tbl.c.nFlip do
							table.insert(points, { tbl.c.fpx[i], tbl.c.fpy[i], `flipper {i}` })
						end
						table.insert(points, { tbl.def.plunger.x, tbl.def.plunger.y, "plunger" })
						for i, b in tbl.def.bumpers do
							table.insert(points, { b.x, b.y, `bumper {i}` })
						end
						for _, p in points do
							local q = onScreen(w, 2, p[1], p[2])
							t.truthy(
								q.X >= 0 and q.X <= w0 and q.Y >= 0 and q.Y <= h0,
								`{which}: {p[3]} on the screen ({q.X}, {q.Y})`
							)
							for _, r in rects do
								local inside = q.X > r[2] and q.X < r[4] and q.Y > r[3] and q.Y < r[5]
								t.falsy(inside, `{which}: the {r[1]} lies over {p[3]} at ({q.X}, {q.Y})`)
							end
						end
					end
					-- the status line never carries words over the table while the ball is in play
					t.falsy(c.ctx.ui.statusLabel.Visible and c.ctx.ui.statusLabel.Text ~= "", Rig.screen(w))
				end, opts(2, { touch = touch }))
			end
		)
	end

	t.test(
		"the display: score, ball and player; BALL SAVED and TILT WARNING (red) on the frame the model raises them, with what to shoot for between callouts",
		function()
			Rig.play(function(w)
				local ID = stationOf(1)
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.run(w, 0.4)
				local c = Controller.current
				local d = c.dmd
				t.truthy(d.frame.Visible, "the display is up while the game is on")
				local texts = Dmd.texts(d)
				t.truthy(string.find(texts[2], "BALL 1", 1, true) ~= nil, texts[2])
				t.truthy(texts[3] ~= "", "what to shoot for, or the plunger's words")
				-- launch, then nudge until the bob warns: the very frame the machine raises it, the display says it
				Rig.key(Key.Space, true)
				Rig.run(w, 1)
				Rig.key(Key.Space, false)
				Rig.run(w, 1)
				local warned = false
				for _ = 1, 40 do
					for _, k in { Key.Z, Key.X, Key.W } do
						Rig.key(k, true)
						Rig.frame(w)
						Rig.key(k, false)
						for _ = 1, 9 do
							Rig.frame(w)
							local m = c.cab.r.m
							if m.say == Machine.SAY.TILT_WARNING and m.sayLeft > 0 and not warned then
								warned = true
								local said = Dmd.texts(d)[3]
								t.truthy(string.find(said, "TILT WARNING", 1, true) ~= nil, said)
								local col = d.say.TextColor3
								t.truthy(col.R > 0.9 and col.G < 0.4, "in red")
							end
						end
					end
					if warned then
						break
					end
				end
				t.truthy(warned, "a tilt warning came")
				-- a ball saved: said on the display the frame it is
				local m = c.cab.r.m
				Machine.callout(m, {}, Machine.SAY.BALL_SAVED, 0)
				Rig.frame(w)
				t.eq(Dmd.texts(d)[3], "BALL SAVED")
			end, opts(1))
		end
	)

	t.test(
		"touch: a thumb resting at the bottom right is the right flipper all through a ball; it pulls the plunger only while the ball waits on it",
		function()
			Rig.play(function(w)
				local ID = stationOf(3)
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				Rig.click(w, "Start (Space)")
				Rig.run(w, 0.4)
				local c = Controller.current
				local tbl = c.cab.tbl
				local function up(i: number): boolean
					return c.cab.r.m.phys.fa[i] > tbl.c.frest[i] + 0.5
				end
				-- the ball waits on the plunger: the right thumb dragged down pulls it, and launches it
				t.truthy(Machine.resting(tbl, c.cab.r.m) > 0)
				Rig.touch("r", "began", 1700, 810)
				Rig.touch("r", "changed", 1700, 810 + 1080 * 0.25)
				Rig.run(w, 0.8)
				t.truthy(c.cab.r.m.pull > 0, "pulled")
				Rig.touch("r", "ended", 1700, 1060)
				Rig.run(w, 1)
				t.eq(Machine.resting(tbl, c.cab.r.m), 0, "launched")
				-- mid-ball: every resting place of the right thumb is the right flipper
				for _, at in { { 1728, 810 }, { 1650, 900 }, { 1820, 750 }, { 1500, 600 } } do
					Rig.touch("r2", "began", at[1], at[2])
					Rig.run(w, 0.1)
					t.truthy(up(2), `a thumb at {at[1]}, {at[2]}`)
					Rig.touch("r2", "ended", at[1], at[2])
					Rig.run(w, 0.3)
				end
				-- a tap on Leave mid-game does not end it: it asks for a second
				Rig.click(w, "Leave")
				Rig.run(w, 0.2)
				t.eq(w.client.active(), ID, "still playing")
				t.truthy(Rig.has(Rig.texts(w.gui), "Tap Leave again to leave"), Rig.screen(w))
				t.truthy(Rig.has(Rig.texts(w.gui), "Tap again to leave"), Rig.screen(w))
				Rig.click(w, "Tap again to leave")
				Rig.run(w, 0.4)
				t.eq(w.client.active(), nil, "the second tap leaves")
			end, opts(3, { touch = true }))
		end
	)

	t.test(
		"keys: Q once in a game asks again, twice leaves; keys pressed while it is not your ball are not kept for it; a mouse click down and up inside one frame is a whole flip",
		function()
			Rig.play(function(w)
				local ID = stationOf(1)
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.run(w, 0.4)
				local c = Controller.current
				local tbl = c.cab.tbl
				-- a click that went down and up between two frames (a trackpad's tap): the flipper goes all the way up
				local Kind = roblox.Enum.UserInputType
				local top = -math.huge
				FakeEngine.input("began", { UserInputType = Kind.MouseButton1 })
				FakeEngine.input("ended", { UserInputType = Kind.MouseButton1 })
				for _ = 1, 6 do
					Rig.frame(w)
					top = math.max(top, c.cab.r.m.phys.fa[1])
				end
				t.near(top, tbl.c.fup[1], 0.05, "a whole stroke")
				-- Q once: not gone, asked to press again; after the wait, Q once again asks again
				Rig.key(Key.Q, true)
				Rig.key(Key.Q, false)
				Rig.run(w, 0.2)
				t.eq(w.client.active(), ID)
				t.truthy(Rig.has(Rig.texts(w.gui), "Press Q again to leave"), Rig.screen(w))
				Rig.run(w, 3)
				Rig.key(Key.Q, true)
				Rig.key(Key.Q, false)
				Rig.run(w, 0.2)
				t.eq(w.client.active(), ID, "a second press long after the first is a first again")
				-- not this player's ball: keys walk the body and nothing is kept
				c.live = false
				Rig.key(Key.W, true)
				Rig.key(Key.A, true)
				Rig.frame(w)
				t.eq(Hands.held(c.hands), 0, "nothing held for the next ball")
				t.eq(c.hands.latched, 0)
				Rig.key(Key.W, false)
				Rig.key(Key.A, false)
				c.live = true
				Rig.key(Key.Q, true)
				Rig.key(Key.Q, false)
				Rig.frame(w)
				Rig.key(Key.Q, true)
				Rig.key(Key.Q, false)
				Rig.run(w, 0.4)
				t.eq(w.client.active(), nil, "twice leaves")
			end, opts(1))
		end
	)

	for _, fps in { 144, 60 } do
		t.test(
			`your own ball drawn at {fps} frames a second with uneven frames: it moves the same distance for the same time (blended between ticks), never one tick then two`,
			function()
				Rig.play(function(w)
					local ID = stationOf(1)
					Rig.press(w, ID)
					Rig.run(w, 0.2)
					Rig.key(Key.Space, true)
					Rig.key(Key.Space, false)
					Rig.run(w, 0.4)
					local c = Controller.current
					-- a full pull, and the ball flies up the shooter lane
					Rig.key(Key.Space, true)
					Rig.run(w, 1.2)
					Rig.key(Key.Space, false)
					local seed = fps
					local function jitter(): number
						seed = (seed * 1103515245 + 12345) % 2147483648
						return seed / 2147483648
					end
					local worst = 0
					local samples = 0
					local was: any = nil
					for _ = 1, math.floor(fps * 0.2) do
						local dt = (1 / fps) * (1 + (jitter() - 0.5) * 0.1)
						FakeEngine.renderStep(dt)
						local f = c.drawn
						local b = c.cab.r.m.phys.balls[1]
						if f and f.nBalls > 0 and b then
							local x, y = f.balls[1], f.balls[2]
							local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
							-- (frames where the ball met something, and turned, are left out)
							local straight = was ~= nil and (b.vx * was[3] + b.vy * was[4]) / (speed * was[5]) > 0.995
							if straight and speed > 5 then
								local step = math.sqrt((x - was[1]) ^ 2 + (y - was[2]) ^ 2)
								local want = speed * dt
								worst = math.max(worst, math.abs(step - want) / want)
								samples += 1
							end
							was = { x, y, b.vx, b.vy, math.max(speed, 1e-6) }
						end
					end
					t.truthy(samples >= 6, `{samples} frames of a fast ball`)
					t.truthy(worst < 0.15, `the step was off by {math.floor(worst * 100)}% at worst`)
				end, opts(1))
			end
		)
	end

	t.test(
		"two players: while Bob plays, Ann stands at her own spot beside the cabinet, not in his place; her body and the glass are not drawn on her screen while her ball is live",
		function()
			Rig.play(function(w)
				local ID = stationOf(1)
				local bob = person("Bob", 5)
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				t.truthy(w.svc:join(bob.stub, ID))
				Rig.run(w, 0.3)
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.run(w, 0.4)
				local c = Controller.current
				t.truthy(c.live)
				local glass =
					w.roots[SITE]:FindFirstChild("GamesRoom"):FindFirstChild("Pinball1"):FindFirstChild("Glass")
				t.eq(glass.LocalTransparencyModifier, 1, "the glass is not drawn over the ball")
				t.eq(w.body.PrimaryPart.LocalTransparencyModifier, 1, "nor her own body under the eye")
				local h = hand(1, 3)
				t.truthy(playFor(w, 300, h, function()
					return c.cab.r ~= nil and c.cab.r.m.up == 2 and not c.live
				end, { bob }, ID))
				Rig.run(w, 0.1)
				t.truthy((w.body.PrimaryPart.LocalTransparencyModifier or 0) < 1, "drawn again")
				t.truthy((glass.LocalTransparencyModifier or 0) < 1)
				local X, D = CabinetLayout.stance(1)
				local x, _, z = AlleyLayout.toWorld(w.places[SITE], X, 0, D)
				local p = w.body.PrimaryPart.Position
				local off = roblox.Vector3.new(p.X - x, 0, p.Z - z).Magnitude
				t.truthy(off > 1.5, `Ann stepped aside ({off} studs from the stance)`)
				-- her ball again: back at the cabinet
				t.truthy(playFor(w, 300, h, function()
					return c.live
				end, { bob }, ID))
				p = w.body.PrimaryPart.Position
				t.truthy(roblox.Vector3.new(p.X - x, 0, p.Z - z).Magnitude < 0.2, "at the stance")
			end, opts(1))
		end
	)

	t.test(
		"the end card: a score that takes first place says NEW HIGH SCORE and a personal best; the best bonus is a column",
		function()
			Rig.play(function(w)
				local ID = stationOf(1)
				Rig.press(w, ID)
				Rig.run(w, 0.2)
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				Rig.run(w, 0.4)
				table.clear(tableOf(w, 1).board.entries) -- (a board with room: the first fair score is first)
				local h = hand(1, 11)
				t.truthy(playFor(w, 600, h, function()
					return sessionOf(w, 1).phase == "done"
				end))
				Rig.run(w, 0.5)
				local screen = Rig.screen(w)
				t.truthy(Rig.has(Rig.texts(w.gui), "NEW HIGH SCORE ON ACORN ATTACK"), screen)
				t.truthy(Rig.has(Rig.texts(w.gui), "A NEW PERSONAL BEST"), screen)
				t.truthy(Rig.has(Rig.texts(w.gui), "BEST BONUS"), screen)
				t.eq(Rig.last(w.got, "state").place, 1)
				t.eq(Rig.last(w.got, "state").newBest, true)
			end, opts(1))
		end
	)

	t.test(
		"PIN-S2: the person playing has both hands on the flipper buttons, leaning in; a hand presses in with its flipper and the right one pulls the plunger's knob; a bystander at a spot is left alone; at the end the Animator has the joints again",
		function()
			Rig.play(function(w)
				local V = roblox.Vector3
				local ID = stationOf(1)
				local place = w.places[SITE]
				local folder = FakeEngine.new("Folder", "Bodies")
				folder.Parent = workspace
				w.body.Parent = folder
				armed(w.body)
				-- Carl watches from the first spot beside the cabinet
				local X, D = CabinetLayout.stance(1)
				local spot = Controller.SPOTS[1]
				local cx, cy, cz = AlleyLayout.toWorld(place, X + spot.x, 3, D + spot.d)
				local carl = FakeEngine.model("Carl", roblox.CFrame.new(cx, cy, cz), folder)
				carl.PrimaryPart = FakeEngine.part("HumanoidRootPart", roblox.CFrame.new(cx, cy, cz), carl)
				armed(carl)
				local function frames(n: number)
					for _ = 1, n do
						Rig.frame(w)
						settleBody(w.body)
						settleBody(carl)
						Cabinet.reach(Rig.DT)
					end
				end
				local function world(x: number, y: number, z: number): any
					return V.new(AlleyLayout.toWorld(place, x, y, z))
				end
				Rig.press(w, ID)
				frames(12)
				t.eq(posedNow(w.body), false, "nobody reaches for the buttons in the lobby")
				Rig.key(Key.Space, true)
				Rig.key(Key.Space, false)
				frames(25)
				-- Space held: the plunger comes back and the right hand is on its knob
				Rig.key(Key.Space, true)
				frames(30)
				local c = Controller.current
				t.truthy(c and c.live, "her ball is live")
				local cab = c.cab
				local f = cab.drawn
				t.truthy(f.pull > 0.3, `the plunger is drawn back ({f.pull})`)
				local a = armsOf(w.body)
				local knob = world(CabinetLayout.knob(1, cab.tbl.def.plunger.x, f.pull, true))
				t.truthy(
					(a.Right.hand - knob).Magnitude < 0.03,
					`the right hand is on the knob ({(a.Right.hand - knob).Magnitude})`
				)
				local left0 = world(CabinetLayout.button(1, 0, true, false))
				t.truthy((a.Left.hand - left0).Magnitude < 0.03, "the left hand on its button")
				Rig.key(Key.Space, false)
				frames(90)
				-- in play: both hands on the buttons, the body leant in over the lockdown bar, the elbows hanging
				a = armsOf(w.body)
				for side = 0, 1 do
					local arm = if side == 0 then a.Left else a.Right
					local target = world(CabinetLayout.button(1, side, true, false))
					local button = world(CabinetLayout.button(1, side))
					t.truthy(
						(arm.hand - target).Magnitude < 0.03,
						`hand {side} is {(arm.hand - target).Magnitude} from its grip`
					)
					t.truthy((arm.hand - button).Magnitude < 0.35, "and that is at the button")
					local along = (arm.elbow - arm.shoulder):Dot((arm.hand - arm.shoulder).Unit)
					local onLine = arm.shoulder + (arm.hand - arm.shoulder).Unit * along
					t.truthy(arm.elbow.Y <= onLine.Y + 1e-3, "the elbow does not stick up")
					t.near((arm.elbow - arm.shoulder).Magnitude, 0.883, 2e-3, "the arm keeps its length")
				end
				local lean = math.acos(math.clamp(a.torso.UpVector.Y, -1, 1))
				t.truthy(lean > 0.05 and lean <= Reach.LEAN_MAX + 1e-6, `leant in a little ({lean} rad)`)
				local toward = world(X, 3, D - 1) - world(X, 3, D)
				t.truthy(a.torso.UpVector:Dot(toward.Unit) > 0.05, "toward the machine")
				t.eq(posedNow(carl), false, "Carl at his spot keeps his arms")
				-- the left flipper held: the left hand pushes its button in
				Rig.key(Key.LeftShift, true)
				frames(20)
				a = armsOf(w.body)
				local pressed = world(CabinetLayout.button(1, 0, true, true))
				t.truthy((a.Left.hand - pressed).Magnitude < 0.03, "the left hand has pressed in")
				t.truthy((a.Left.hand - left0).Magnitude > CabinetLayout.BUTTON.press * 0.8)
				local right0 = world(CabinetLayout.button(1, 1, true, false))
				t.truthy((a.Right.hand - right0).Magnitude < 0.03, "the right hand still rests on its button")
				Rig.key(Key.LeftShift, false)
				frames(20)
				t.truthy((armsOf(w.body).Left.hand - left0).Magnitude < 0.03, "and lets go")
				-- she leaves: the joints are the Animator's again
				Rig.key(Key.Q, true)
				Rig.key(Key.Q, false)
				frames(3)
				Rig.key(Key.Q, true)
				Rig.key(Key.Q, false)
				frames(30)
				t.eq(posedNow(w.body), false, "let go when the game is left")
				-- a body with one arm (or none: an animal) is never posed
				local stump = FakeEngine.model("Stump", roblox.CFrame.new(0, 3, 0), nil)
				t.eq(Reach.hands(stump), nil)
			end, opts(1))
		end
	)
end
