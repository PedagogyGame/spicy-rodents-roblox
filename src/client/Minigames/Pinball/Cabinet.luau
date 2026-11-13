--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Pinball.Cabinet
-- A pinball machine on this screen: the baked cabinet in the games room (Workspace.Attractions.<alley>.GamesRoom.
-- Pinball<index>) with its ball, flippers, drop targets, spinners, plunger, lamps and backglass moved every
-- rendered frame from the model's own stream (Shared/Minigames/Pinball/Stream), and the game as a BYSTANDER
-- sees it. Three ways a cabinet is drawn:
--   * live: the local player's ball. Their controller (Client/Minigames/Pinball/Controller) steps the machine
--     itself, tick by tick at the clock's pace, and hands each frame to show(): nothing waits for the server;
--   * follow: someone else's ball (or the local player's turn has not come). The server relays every segment
--     of the log it has taken ("pinball"); it is played at once on this screen's copy of the game
--     (Replay.follow, in pieces of CHUNK ticks so that a frame is kept every CHUNK ticks) and drawn DELAY ticks
--     behind the newest, blended between kept frames, at the pace of this screen's own frames: smooth at any
--     frame rate, and the real ball. A snapshot ("pinball_sync") puts the copy right (a watcher who walks up,
--     the server having played by itself);
--   A player who leaves while it is not their ball is passed over at the next hand-over ("pinball_retire": the
--     copy applies it once it has reached the server's tick, or at once if it is the live copy, ahead of it);
--   * idle: the attract show (Pinball/Attract: the lamp figures and the backglass pages, a pure function of the
--     shared clock, so every screen shows the same), the best scores (the cabinet's "Best" attribute, which
--     the server writes) and the flippers at rest.
-- Sounds are named cue points (MinigameSounds "pinball.<variant>.<cue>", one set per machine, no asset ids yet)
-- fired as the drawing passes them; a bumper's cap and a slingshot's rubber flash when they fire.
-- The parts are found lazily and may be missing (streaming, a place without the cabinet): then nothing is drawn
-- and nothing breaks. A cabinet is drawn only while it is awake (a message about it came, and this player's
-- body is within SLEEP studs); the render step is unbound when none is.
-- Interface: get(station, place?, index?, tableId?) -> Cab; sync(cab, msg) -> bool; segment(cab, msg) -> bool;
--   retire(cab, msg) (a seat that has gone, from a tick on);
--   rebase(cab); idle(cab); over(cab, msg); show(cab, frame, dt?) (the controller's live frames); cue(cab, cue, a, b) (one
--   cue: its sound and its flash); CUE_NAMES; cueName(variant, cue) -> string; SOUNDS (every cue name, for the
--   game's sounds); step(dt) (the render step; specs call it); reset() (specs); awake() -> number; DELAY;
--   CHUNK; SLEEP; BIND; KEEP

local Import = require("../../Import")
local Attract =
	Import.shared("Minigames/Pinball/Attract") :: typeof(require("../../../shared/Minigames/Pinball/Attract"))
local CabinetLayout =
	Import.shared("Minigames/Pinball/Cabinet") :: typeof(require("../../../shared/Minigames/Pinball/Cabinet"))
local HighScores =
	Import.shared("Minigames/Pinball/HighScores") :: typeof(require("../../../shared/Minigames/Pinball/HighScores"))
local InputLog =
	Import.shared("Minigames/Pinball/InputLog") :: typeof(require("../../../shared/Minigames/Pinball/InputLog"))
local Layout = Import.shared("Minigames/Pinball/Layout") :: typeof(require("../../../shared/Minigames/Pinball/Layout"))
local Machine =
	Import.shared("Minigames/Pinball/Machine") :: typeof(require("../../../shared/Minigames/Pinball/Machine"))
local Physics =
	Import.shared("Minigames/Pinball/Physics") :: typeof(require("../../../shared/Minigames/Pinball/Physics"))
local Replay = Import.shared("Minigames/Pinball/Replay") :: typeof(require("../../../shared/Minigames/Pinball/Replay"))
local Stream = Import.shared("Minigames/Pinball/Stream") :: typeof(require("../../../shared/Minigames/Pinball/Stream"))
local Tables = Import.shared("Minigames/Pinball/Tables") :: typeof(require("../../../shared/Minigames/Pinball/Tables"))
local Wire = Import.shared("Minigames/Pinball/Wire") :: typeof(require("../../../shared/Minigames/Pinball/Wire"))
local AlleyLayout =
	Import.shared("Attractions/AlleyLayout") :: typeof(require("../../../shared/Attractions/AlleyLayout"))
local MinigameSounds = require("../MinigameSounds")

local Cabinet = {}

Cabinet.DELAY = 120 -- ticks a follower's drawing runs behind the newest tick received (half a second)
Cabinet.CHUNK = 4 -- ticks between two kept frames of a followed game (one screen frame at 60 a second)
Cabinet.KEEP = 2400 -- ticks of kept frames (ten seconds)
Cabinet.SLEEP = 70 -- studs from the camera beyond which a cabinet nobody here plays stops being drawn
Cabinet.BIND = "SpicyPinballCabinets"
Cabinet.FLASH = 0.12 -- seconds a bumper cap or a slingshot stays lit after it fires
Cabinet.SITE = "bowling_alley"
Cabinet.REEL_CLACK = 0.06 -- seconds between two clacks of the score reels

-- the cue names, by Machine.CUE number ("bumper", "flip_up", ...)
Cabinet.CUE_NAMES = {} :: { [number]: string }
for name, code in Machine.CUE do
	Cabinet.CUE_NAMES[code] = string.lower(name)
end
function Cabinet.cueName(variant: string, cue: number): string
	return `pinball.{variant}.{Cabinet.CUE_NAMES[cue] or tostring(cue)}`
end
-- every sound this game may ask for, one set per machine (asset ids all empty for now)
Cabinet.SOUNDS = {} :: { [string]: string }
for variant in Tables.VARIANTS do
	for code in Cabinet.CUE_NAMES do
		Cabinet.SOUNDS[Cabinet.cueName(variant, code)] = ""
	end
	Cabinet.SOUNDS[`pinball.{variant}.reel`] = "" -- ACORN ATTACK's score reels clacking round
end

-- how loud each cue is (0..1); a cue not listed is 0.5
local VOLUME: { [number]: number } = {
	[Machine.CUE.FLIP_UP] = 0.55,
	[Machine.CUE.FLIP_DOWN] = 0.3,
	[Machine.CUE.BUMPER] = 0.8,
	[Machine.CUE.SLING] = 0.7,
	[Machine.CUE.DRAIN] = 0.6,
	[Machine.CUE.TILT] = 0.9,
	[Machine.CUE.GAME_OVER] = 0.8,
	[Machine.CUE.JINGLE] = 0.8,
	[Machine.CUE.BONUS_TICK] = 0.35,
	[Machine.CUE.WALL] = 0.25,
	[Machine.CUE.POST] = 0.3,
}

export type Cab = {
	station: string,
	index: number,
	variant: string,
	place: any?,
	tableId: string,
	tbl: any,
	parts: any?,
	findAt: number,
	r: any, -- the copy of the game this screen follows (or plays: the controller's)
	g: number, -- the game it belongs to
	frames: { { any } }, -- kept frames: { tick, Frame }
	cues: { { number } }, -- cues not yet heard: { tick, cue, a, b }
	at: number, -- the tick being drawn
	newest: number,
	mode: string, -- "idle" | "follow"
	live: boolean, -- the local player's controller draws it
	mine: number?, -- the local player's seat at it (the controller sets it)
	awake: boolean,
	far: number, -- seconds the camera has been beyond SLEEP
	clock: number,
	flash: { [any]: number }, -- part -> seconds left lit
	shown: { [string]: any }, -- what the backglass and the lamps show now (written only when it changes)
	reel: number, -- the score the reels show (ACORN ATTACK's count up to the real one)
	clackAt: number,
	board: { string },
	out: { number },
	frame: any,
	lampsIdle: { number },
	notes: { any }, -- seats retired, waiting for this copy to reach the server's tick: { seat, tick }
}

local cabs: { [string]: Cab } = {}
local bound = false

local function sharedTick(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return math.floor((if ok and type(t) == "number" then t else os.clock()) * Physics.HZ)
end

-- the cabinet's parts as they are on this client now (nil while they have not streamed in)
local function find(cab: Cab): any
	local att = workspace:FindFirstChild("Attractions")
	local site: Instance? = nil
	for _, m in if att then att:GetChildren() else {} do
		if m:GetAttribute("Site") == Cabinet.SITE then
			site = m
		end
	end
	local room = site and site:FindFirstChild("GamesRoom")
	local model = room and room:FindFirstChild(CabinetLayout.model(cab.index))
	if model == nil then
		return nil
	end
	local N = CabinetLayout.NAMES
	local function kids(prefix: string, n: number): { [number]: any }
		local out = {}
		for i = 1, n do
			out[i] = model:FindFirstChild(`{prefix}{i}`)
		end
		return out
	end
	local def = cab.tbl.def
	local parts: any = {
		model = model,
		balls = kids(N.ball, CabinetLayout.BALLS),
		flippers = kids(N.flipper, #def.flippers),
		drops = kids(N.drop, #def.targets),
		spinners = kids(N.spinner, #cab.tbl.c.spinners),
		lamps = kids(N.lamp, #def.lamps),
		bumpers = kids(N.bumper, #def.bumpers),
		slings = kids(N.sling, #def.slings),
		plunger = model:FindFirstChild(N.plunger),
		glass = model:FindFirstChild("Glass"), -- (not drawn on the player's own screen while their ball is live)
		labels = {},
		home = {}, -- part -> its baked CFrame (drops, spinners, the plunger: moved from where the bake put them)
		colour = {}, -- lamp part -> its baked colour
	}
	for _, list in { parts.drops, parts.spinners } do
		for _, p in list do
			parts.home[p] = p.CFrame
		end
	end
	if parts.plunger then
		parts.home[parts.plunger] = parts.plunger:GetPivot()
	end
	for _, p in parts.lamps do
		parts.colour[p] = p.Color
	end
	local glass = model:FindFirstChild(N.backglass)
	local display = glass and glass:FindFirstChild("Display")
	if display then
		for _, l in display:GetChildren() do
			parts.labels[l.Name] = l
		end
	end
	return parts
end

-- the playfield's frame in the world (Shared/Minigames/Pinball/Cabinet): point (x, y, h) is frame * (x, h, -y)
local function frameOf(cab: Cab): CFrame?
	local place = cab.place
	if place == nil then
		return nil
	end
	local X, Y, D = CabinetLayout.origin(cab.index)
	local x, y, z = AlleyLayout.toWorld(place, X, Y, D)
	return CFrame.new(x, y, z)
		* CFrame.Angles(0, place.yaw, 0)
		* CFrame.Angles(0, math.pi, 0)
		* CFrame.Angles(CabinetLayout.TILT, 0, 0)
end

local function setText(cab: Cab, name: string, text: string)
	if cab.shown[name] == text then
		return
	end
	cab.shown[name] = text
	local parts = cab.parts
	local label = parts and parts.labels[name]
	if label then
		label.Text = text
	end
end

-- the backglass: the title, the score of the player up, the ball and the player, the callout, everyone's scores
local function backglass(cab: Cab, f: any, dt: number)
	local tbl = cab.tbl
	local m = cab.r and cab.r.m
	local up = f.up or 1
	local score = f.scores[up] or 0
	if cab.variant == "acorn" then
		-- score reels: the drums count up to the score, a digit at a time
		if cab.reel > score then
			cab.reel = score
		elseif cab.reel < score then
			local step = math.max(10, (score - cab.reel) * math.min(1, dt * 6))
			cab.reel = math.min(score, cab.reel + math.floor(step / 10 + 0.5) * 10)
			-- (a clack every REEL_CLACK seconds while the drums turn, not one a frame)
			if cab.clock - cab.clackAt >= Cabinet.REEL_CLACK then
				cab.clackAt = cab.clock
				MinigameSounds.play(`pinball.{cab.variant}.reel`, 0.25)
			end
		end
		score = cab.reel
	end
	setText(cab, "Title", tbl.title)
	setText(cab, "Score", HighScores.commas(score))
	local players = if m then m.players else #f.scores
	local info
	if f.phase == Machine.PHASE.OVER then
		info = "GAME OVER"
	elseif f.tilted then
		info = "TILT"
	else
		info = `BALL {f.ball}   PLAYER {up}{if players > 1 then ` OF {players}` else ""}`
	end
	setText(cab, "Info", info)
	local say = ""
	if f.say ~= 0 then
		say = tbl.sheet.text[f.say] or Machine.TEXT[f.say] or ""
		if f.sayValue and f.sayValue > 0 and f.say ~= Machine.SAY.TILT_WARNING then
			say ..= `  {HighScores.commas(f.sayValue)}`
		end
	elseif m and f.phase == Machine.PHASE.PLAY then
		say = tbl.sheet.status(m, m.sheets[m.up])
	end
	setText(cab, "Say", say)
	if players > 1 then
		local list = {}
		for i = 1, players do
			table.insert(list, `{if i == up then ">" else ""}P{i} {HighScores.commas(f.scores[i] or 0)}`)
		end
		setText(cab, "Best", table.concat(list, "   "))
	else
		setText(cab, "Best", "FREE PLAY")
	end
end

local function lampsShow(cab: Cab, lamps: { number })
	local parts = cab.parts
	if parts == nil then
		return
	end
	local blink = (cab.clock * 4) % 1 < 0.5
	for i, p in parts.lamps do
		local v = lamps[i] or 0
		local lit = v == 1 or (v == 2 and blink)
		local key = `L{i}`
		if cab.shown[key] ~= lit then
			cab.shown[key] = lit
			local base = parts.colour[p]
			if lit then
				p.Material = Enum.Material.Neon
				p.Color = base
			else
				p.Material = Enum.Material.SmoothPlastic
				p.Color = Color3.new(base.R * 0.3, base.G * 0.3, base.B * 0.3)
			end
		end
	end
end

-- Pose every moving part from a frame of the stream.
function Cabinet.show(cab: Cab, f: any, dt: number?)
	local step = dt or 0
	cab.clock += step
	local parts = cab.parts
	if parts == nil or parts.model.Parent == nil then
		if cab.clock - cab.findAt < 0.5 and parts == nil then
			return
		end
		cab.findAt = cab.clock
		parts = find(cab)
		cab.parts = parts
		table.clear(cab.shown)
		if parts == nil then
			return
		end
	end
	local pf = frameOf(cab)
	if pf == nil then
		return
	end
	local c = cab.tbl.c
	-- the balls
	for i, part in parts.balls do
		if i <= f.nBalls then
			local k = (i - 1) * 3
			part.CFrame = pf * CFrame.new(f.balls[k + 1], f.balls[k + 3] + Layout.BALL_R, -f.balls[k + 2])
			if part.Transparency ~= 0 then
				part.Transparency = 0
			end
		elseif part.Transparency ~= 1 then
			part.Transparency = 1
		end
	end
	-- the flippers turn about their pivots
	for i, model in parts.flippers do
		local a = f.flippers[i] or c.frest[i]
		local dx, dy = c.fmir[i] * math.cos(a), math.sin(a)
		model:PivotTo(
			pf
				* CFrame.new(c.fpx[i], CabinetLayout.FLIPPER_H / 2, -c.fpy[i])
				* CFrame.Angles(0, CabinetLayout.turnOf(dx, dy), 0)
		)
	end
	-- drop targets: down below the surface when knocked down
	for i, part in parts.drops do
		local down = f.drops[i] == true
		local key = `D{i}`
		if cab.shown[key] ~= down then
			cab.shown[key] = down
			local home = parts.home[part]
			part.CFrame = if down then home * CFrame.new(0, -CabinetLayout.DROP_SINK, 0) else home
		end
	end
	-- spinners turn about their own long axis
	for k, part in parts.spinners do
		local home = parts.home[part]
		part.CFrame = home * CFrame.Angles((f.spin[k] or 0) * math.pi * 2, 0, 0)
	end
	-- the plunger: the rod drawn back toward the player (its part's +Z: the rod lies along the playfield)
	local plunger = parts.plunger
	if plunger then
		plunger:PivotTo(parts.home[plunger] * CFrame.new(0, 0, (f.pull or 0) * CabinetLayout.PULL_TRAVEL))
	end
	-- the lamps, and what has just fired
	lampsShow(cab, f.lamps)
	for part, left in cab.flash do
		local now = left - step
		if now <= 0 then
			cab.flash[part] = nil
			part.Material = Enum.Material.SmoothPlastic
		else
			cab.flash[part] = now
		end
	end
	backglass(cab, f, step)
end

-- One cue: its sound, and the part it lights.
function Cabinet.cue(cab: Cab, cue: number, a: number, _b: number)
	MinigameSounds.play(Cabinet.cueName(cab.variant, cue), VOLUME[cue] or 0.5)
	local parts = cab.parts
	if parts == nil then
		return
	end
	local part = nil
	if cue == Machine.CUE.BUMPER then
		part = parts.bumpers[a]
	elseif cue == Machine.CUE.SLING then
		part = parts.slings[a]
	end
	if part then
		part.Material = Enum.Material.Neon
		cab.flash[part] = Cabinet.FLASH
	end
end

local function blank(cab: Cab): any
	if cab.r then
		return Stream.read(cab.tbl, cab.r.m)
	end
	local m = Machine.new(cab.tbl, 1, 1)
	local f = Stream.read(cab.tbl, m)
	f.nBalls = 0
	table.clear(f.balls)
	return f
end

local function wake(cab: Cab)
	cab.awake = true
	cab.far = 0
	if not bound then
		bound = true
		game:GetService("RunService"):BindToRenderStep(Cabinet.BIND, Enum.RenderPriority.Camera.Value + 2, function(dt)
			Cabinet.step(dt)
		end)
	end
end

function Cabinet.get(station: string, place: any?, index: number?, tableId: string?): Cab
	local cab = cabs[station]
	if cab == nil then
		local i = index or tonumber(string.match(station, "(%d+)$")) or 1
		local id = tableId
		if id == nil then
			local theme = AlleyLayout.PINBALLS[i] and AlleyLayout.PINBALLS[i].theme
			id = Tables.forVariant(theme) or Tables.IDS[1]
		end
		local tbl = Tables.need(id :: string)
		local variant = "acorn"
		for v, tid in Tables.VARIANTS do
			if tid == tbl.id then
				variant = v
			end
		end
		cab = {
			station = station,
			index = i,
			variant = variant,
			place = place,
			tableId = tbl.id,
			tbl = tbl,
			parts = nil,
			findAt = -math.huge,
			r = nil,
			g = 0,
			frames = {},
			cues = {},
			at = 0,
			newest = 0,
			mode = "idle",
			live = false,
			mine = nil,
			awake = false,
			far = 0,
			clock = 0,
			flash = {},
			shown = {},
			reel = 0,
			clackAt = -math.huge,
			board = {},
			out = {},
			frame = nil,
			lampsIdle = {},
			notes = {},
		}
		cabs[station] = cab
	end
	if place ~= nil then
		cab.place = place
	end
	return cab :: Cab
end

local function keep(cab: Cab)
	local r = cab.r
	if r == nil then
		return
	end
	table.insert(cab.frames, { r.tick, Stream.read(cab.tbl, r.m) })
	cab.newest = r.tick
	while #cab.frames > Cabinet.KEEP / Cabinet.CHUNK do
		table.remove(cab.frames, 1)
	end
end

-- the seats that have gone, from the server's tick on (the live copy is ahead of the server: at once). A seat
-- that is up on this copy at that tick would be a copy that has come apart: left for the snapshot that follows.
local function applyNotes(cab: Cab)
	local r = cab.r
	if r == nil then
		return
	end
	for i = #cab.notes, 1, -1 do
		local note = cab.notes[i]
		if cab.live or r.tick >= note.tick then
			if r.m.up ~= note.seat or r.m.gone[note.seat] then
				Replay.retire(r, note.seat)
			end
			table.remove(cab.notes, i)
		end
	end
end

-- retire(cab, msg): a seat that was not up has gone for good ("pinball_retire" { g, seat, tick }).
function Cabinet.retire(cab: Cab, msg: { [string]: any })
	local seat, tick = tonumber(msg.seat), tonumber(msg.tick)
	if cab.r == nil or msg.g ~= cab.g or seat == nil or tick == nil then
		return
	end
	table.insert(cab.notes, { seat = seat, tick = tick })
	applyNotes(cab)
end

-- sync(cab, msg): a snapshot of the game as the server has it. True if it was taken.
function Cabinet.sync(cab: Cab, msg: { [string]: any }): boolean
	local r = Wire.restore(msg.snap)
	if r == nil or r.id ~= cab.tableId then
		return false
	end
	cab.r = r
	cab.g = tonumber(msg.g) or 0
	cab.mode = "follow"
	table.clear(cab.frames)
	table.clear(cab.cues)
	keep(cab)
	cab.at = r.tick
	applyNotes(cab)
	wake(cab)
	return true
end

-- rebase(cab): the copy as it stands is where the drawing goes on from (the local player's ball has ended
-- on this screen and the cabinet follows the next one)
function Cabinet.rebase(cab: Cab)
	table.clear(cab.frames)
	table.clear(cab.cues)
	keep(cab)
	cab.at = cab.newest
	cab.mode = if cab.r then "follow" else "idle"
end

-- the cues of one followed piece, kept to be heard when the drawing passes them
local function keepCues(cab: Cab, tick: number)
	local out = cab.out
	for i = 1, #out, 3 do
		table.insert(cab.cues, { tick, out[i], out[i + 1], out[i + 2] })
	end
	table.clear(out)
end

-- segment(cab, msg): a segment of the log the server took. Played on this screen's copy at once (unless the
-- local player's controller is playing it live: the server never relays a player's own segments to them).
-- False when it does not follow on from the copy (a snapshot will come).
function Cabinet.segment(cab: Cab, msg: { [string]: any }): boolean
	local r = cab.r
	if r == nil or msg.g ~= cab.g or cab.live then
		return false
	end
	local seg = InputLog.unpack(msg.from, msg.to, msg.packed)
	local seat = tonumber(msg.seat)
	if seg == nil or seat == nil or seg[1] ~= r.tick then
		return false
	end
	applyNotes(cab)
	wake(cab)
	-- in pieces of CHUNK ticks, so that a frame is kept every CHUNK ticks
	local from, to = seg[1], seg[2]
	local pairsAt = 3
	local a = from
	while a < to do
		local b = math.min(a + Cabinet.CHUNK, to)
		local piece: { number } = { a, b }
		while pairsAt < #seg and from + seg[pairsAt] <= b do
			table.insert(piece, from + seg[pairsAt] - a)
			table.insert(piece, seg[pairsAt + 1])
			pairsAt += 2
		end
		local before = r.tick
		local ok = Replay.follow(r, seat, piece, cab.out)
		keepCues(cab, r.tick)
		if not ok or r.tick == before then
			break
		end
		keep(cab)
		if r.tick < b then
			break -- (the ball changed hands inside this piece: the rest of the segment is not this ball's)
		end
		a = b
	end
	return true
end

-- idle(cab): the machine is free: the attract show.
function Cabinet.idle(cab: Cab)
	cab.mode = "idle"
	cab.r = nil
	cab.g = 0
	table.clear(cab.frames)
	table.clear(cab.cues)
	table.clear(cab.notes)
	cab.reel = 0
	wake(cab)
end

function Cabinet.over(cab: Cab, msg: { [string]: any })
	if type(msg.board) == "table" then
		cab.board = msg.board
	end
end

-- the attract show on an idle machine
local function attract(cab: Cab, dt: number)
	local tick = sharedTick()
	local f = cab.frame or blank(cab)
	cab.frame = f
	f.nBalls = 0
	Attract.lamps(cab.tbl, tick, cab.lampsIdle)
	f.lamps = cab.lampsIdle
	Cabinet.show(cab, f, dt)
	if cab.parts == nil then
		return
	end
	local n = (tick // Attract.PAGE_TICKS) % Attract.PAGES
	local page = Attract.page(cab.tbl, tick)
	local lines = page.lines
	if n == 1 then
		local best = cab.parts.model:GetAttribute("Best")
		if type(best) == "string" and best ~= "" then
			lines = string.split(best, "\n")
		elseif #cab.board > 0 then
			lines = cab.board
		end
	end
	setText(cab, "Title", cab.tbl.title)
	setText(cab, "Score", page.title)
	setText(cab, "Info", lines[1] or "")
	setText(cab, "Say", lines[2] or "")
	setText(cab, "Best", table.concat(lines, "  ", 3))
end

-- a followed game, drawn DELAY ticks behind the newest frame kept
local function follow(cab: Cab, dt: number)
	local frames = cab.frames
	if #frames == 0 then
		return
	end
	local target = cab.newest - Cabinet.DELAY
	local at = cab.at
	if at < target - 2 * Physics.HZ or at > cab.newest then
		at = math.max(frames[1][1], target)
	else
		local catch = math.clamp((target - at) / Physics.HZ, -0.25, 0.25)
		at += dt * Physics.HZ * (1 + catch)
	end
	at = math.clamp(at, frames[1][1], cab.newest)
	cab.at = at
	-- the two kept frames either side
	local lo, hi = frames[1], frames[#frames]
	for i = #frames, 1, -1 do
		if frames[i][1] <= at then
			lo = frames[i]
			hi = frames[math.min(i + 1, #frames)]
			break
		end
	end
	local f
	if hi[1] > lo[1] then
		cab.frame = Stream.blend(lo[2], hi[2], (at - lo[1]) / (hi[1] - lo[1]), cab.frame)
		f = cab.frame
	else
		f = lo[2]
	end
	-- the cues the drawing has passed
	local cues = cab.cues
	local heard = 0
	for _, c in cues do
		if c[1] > at then
			break
		end
		heard += 1
		Cabinet.cue(cab, c[2], c[3], c[4])
	end
	for _ = 1, heard do
		table.remove(cues, 1)
	end
	Cabinet.show(cab, f, dt)
end

function Cabinet.step(dt: number)
	local any = false
	-- where this player is (their body; no body, no sleep)
	local me: Vector3? = nil
	pcall(function()
		local char = (game:GetService("Players").LocalPlayer :: any).Character
		local root = char and char.PrimaryPart
		if root then
			me = root.Position
		end
	end)
	for _, cab in cabs do
		if not cab.awake then
			continue
		end
		-- a cabinet nobody here plays, which this player has walked away from, is put to sleep
		local at = me
		if not cab.live and at and cab.place then
			local X, _, D = CabinetLayout.at(cab.index)
			local x, y, z = AlleyLayout.toWorld(cab.place, X, CabinetLayout.PF_Y, D)
			if (at - Vector3.new(x, y, z)).Magnitude > Cabinet.SLEEP then
				cab.far += dt
				if cab.far > 2 then
					cab.awake = false
					continue
				end
			else
				cab.far = 0
			end
		end
		any = true
		if cab.live then
			continue
		end
		if cab.mode == "follow" and cab.r then
			follow(cab, dt)
		else
			attract(cab, dt)
		end
	end
	if not any and bound then
		bound = false
		game:GetService("RunService"):UnbindFromRenderStep(Cabinet.BIND)
	end
end

function Cabinet.awake(): number
	local n = 0
	for _, cab in cabs do
		if cab.awake then
			n += 1
		end
	end
	return n
end

function Cabinet.reset()
	table.clear(cabs)
	if bound then
		bound = false
		pcall(function()
			game:GetService("RunService"):UnbindFromRenderStep(Cabinet.BIND)
		end)
	end
end

return Cabinet
