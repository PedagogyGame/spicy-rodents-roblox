--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.WhackAMole.Cabinet
-- The whack-a-mole cabinet on this screen: the baked cabinet in the games room (Workspace.Attractions.<alley>.
-- GamesRoom.WhackAMole; Shared/Minigames/WhackAMole/Layout.NAMES) with its five moles, its mallet and the SCORE,
-- TIME and status windows on the sign drawn every rendered frame from the server's stream, the same for the
-- player and for everyone watching:
--   "whack_round" (the round as it stands: GO on the shared clock, the score, the moles up), "whack_rise" (a mole
--   the server has decided, in round seconds), "whack_hit" (a strike the server took: the mallet swings there,
--   a hit mole drops from where it was, the score), "whack_over" (the end), "whack_idle" (the cabinet is free).
-- SMOOTH AT ANY FRAME RATE: nothing is stepped. Each frame the round's time is read off the shared clock
-- (workspace:GetServerTimeNow() - GO) and every mole's height is Round.height of its rise at that moment (the
-- owner's 0.17 s ease-out rise and 0.21 s drop), the mallet's pose a function of the time since its swing. A mole
-- is only moved when its height changed (an idle cabinet costs a clock read and five compares a frame), and the
-- render step is bound only while a cabinet is awake: a round on, a swing or a drop still moving, and this
-- player's body within SLEEP studs.
-- A ROUND ENDS ON THIS SCREEN'S CLOCK TOO: past its 45 seconds (and Round.GRACE and LATE) it is over here whether
-- or not the end was heard (a watcher who walked out of the server's ring, Layout.WATCH, is sent nothing more),
-- so nothing keeps the render step bound. A cabinet put to sleep because this player walked off past SLEEP
-- forgets its round and is drawn at rest (moles down, the mallet home, FREE PLAY): walking back into the ring,
-- the server sends the round as it stands again; and when the cabinet is free the server tells everyone it sent
-- the round to, so a screen out of the ring at the end shows FREE PLAY too.
-- The player's own strike is drawn at once (swing(): the mallet goes down, and a mole that could be hit on this
-- screen drops as it is struck); the server's word follows and wins (a mole it says was missed comes back up,
-- and so does every mole dropped ahead of its word when it refuses a strike: refused()).
-- The windows: SCORE (three digits), TIME (two digits, the round's seconds left; the count-in shows 45), and the
-- line under them (READY 3 2 1, GO!, NICE! +10, MISS -2, TIME!, and FREE PLAY when nobody plays: no coins, ever).
-- Sound: named cues only, no asset ids (MinigameSounds "whack_a_mole.<cue>": pop as a mole starts up, swing,
-- bonk on a hit, thud on a miss, count and go in the count-in, hurry for each of the last five seconds, over).
-- The parts are found lazily and may be missing (streaming, a place without the cabinet): then nothing is drawn
-- and nothing breaks.
-- Interface: get(station, place?) -> Cab; round(cab, msg); rise(cab, msg); hit(cab, msg); over(cab, msg);
--   idle(cab, msg); refused(cab); card(cab, label?); cardLine(cab) -> string; swing(cab, hole, at) (this player's own strike, at = shared-clock time); take(cab) / release(cab)
--   (the player's own cabinet stays awake wherever the body is); roundTime(cab) -> number?; heightOf(cab, hole,
--   t?) -> 0..1; hittable(cab, hole, t?) -> bool; malletPose(cab, now) -> (u, v, w, rx, ry, rz) (the pivot in the
--   cabinet frame and its turn); cframe(cab, u, v, w) -> CFrame; windows(cab) -> { score, time, status } (the
--   words drawn); step(dt) (the render step; specs call it); reset() (specs); SOUNDS; SLEEP; LATE; BIND; MOVE; DOWN; UP;
--   HOVER; HOME

local Import = require("../../Import")
local AlleyLayout =
	Import.shared("Attractions/AlleyLayout") :: typeof(require("../../../shared/Attractions/AlleyLayout"))
local Layout =
	Import.shared("Minigames/WhackAMole/Layout") :: typeof(require("../../../shared/Minigames/WhackAMole/Layout"))
local Round =
	Import.shared("Minigames/WhackAMole/Round") :: typeof(require("../../../shared/Minigames/WhackAMole/Round"))
local MinigameSounds = require("../MinigameSounds")

local Cabinet = {}

Cabinet.SITE = "bowling_alley"
Cabinet.BIND = "SpicyWhackAMole"
Cabinet.SLEEP = Layout.WATCH + 10 -- studs: a cabinet nobody here plays is not drawn from further than this
Cabinet.LATE = 1 -- seconds after a round's end (and Round.GRACE) by which it is over on this screen anyway
-- the mallet's swing (seconds): over to the hole, down, back up, held over it, then home to the bracket
Cabinet.MOVE = 0.07
Cabinet.DOWN = 0.06
Cabinet.UP = 0.1
Cabinet.HOVER = 1.0
Cabinet.HOME = 0.25
Cabinet.SAY = 0.6 -- seconds a NICE! or a MISS stays on the status line

local CUES = { "pop", "swing", "bonk", "thud", "count", "go", "hurry", "over" }
Cabinet.SOUNDS = {} :: { [string]: string }
for _, cue in CUES do
	Cabinet.SOUNDS[`whack_a_mole.{cue}`] = ""
end

local function sound(cue: string)
	MinigameSounds.play(`whack_a_mole.{cue}`)
end

export type Rise = { id: number, hole: number, at: number, dur: number, hitAt: number?, from: number? }
export type Cab = {
	station: string,
	place: any?,
	g: number, -- the round this cabinet is drawing
	start: number?, -- the shared-clock time of GO
	rises: { [number]: Rise }, -- by id
	byHole: { { Rise } },
	score: number,
	done: boolean, -- the round has ended (TIME!)
	free: boolean, -- nobody plays: FREE PLAY
	predicted: { [number]: boolean }, -- rise id -> this screen dropped it before the server's word
	say: string,
	sayUntil: number,
	mallet: { hole: number, at: number, from: any }?, -- the swing being drawn (at: shared clock)
	malletShown: string, -- (what was last drawn, to move it only when it changes)
	shownH: { number },
	shown: { [string]: string },
	parts: any?,
	findAt: number,
	awake: boolean,
	far: number,
	live: boolean, -- the local player's own cabinet
	cardLabel: TextLabel?, -- the player's card line, written with the sign (card())
	counted: number, -- the count-in's last second sounded
	went: boolean, -- GO sounded
	hurried: number, -- the last of the final seconds sounded
	popped: { [number]: boolean }, -- rise id -> its pop has been sounded (or it was up when this screen came)
}

local cabs: { [string]: Cab } = {}
local bound = false

local function now(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return if ok and type(t) == "number" then t else os.clock()
end

local function blankHoles(): { { Rise } }
	local out = {}
	for i = 1, Round.HOLES do
		out[i] = {}
	end
	return out
end

-- the cabinet's parts as they are on this client now (nil while they have not streamed in)
local function find(_cab: Cab): any
	local att = workspace:FindFirstChild("Attractions")
	local site: Instance? = nil
	for _, m in if att then att:GetChildren() else {} do
		if m:GetAttribute("Site") == Cabinet.SITE then
			site = m
		end
	end
	local room = site and site:FindFirstChild("GamesRoom")
	local N = Layout.NAMES
	local model = room and room:FindFirstChild(N.model)
	if model == nil then
		return nil
	end
	local moles = {}
	for i = 1, Round.HOLES do
		local m = model:FindFirstChild(`{N.mole}{i}`)
		if m and m:IsA("Model") then
			moles[i] = { model = m, base = m:GetPivot() }
		end
	end
	local function label(name: string): TextLabel?
		local part = model:FindFirstChild(name)
		local gui = part and part:FindFirstChild(N.display)
		local value = gui and gui:FindFirstChild(N.value)
		return if value and value:IsA("TextLabel") then value else nil
	end
	local mallet = model:FindFirstChild(N.mallet)
	return {
		model = model,
		moles = moles,
		mallet = if mallet and mallet:IsA("Model") then mallet else nil,
		score = label(N.score),
		time = label(N.time),
		status = label(N.status),
	}
end

local function partsOf(cab: Cab): any
	local p = cab.parts
	if p and p.model.Parent ~= nil then
		return p
	end
	local t = os.clock()
	if t - cab.findAt < 1 then
		return nil
	end
	cab.findAt = t
	cab.parts = find(cab)
	table.clear(cab.shownH)
	cab.malletShown = ""
	table.clear(cab.shown)
	return cab.parts
end

-- The cabinet frame (Layout: u across, v up, w into the cabinet) as a world CFrame: X = u, Y = v, Z = -w.
function Cabinet.cframe(cab: Cab, u: number, v: number, w: number): CFrame
	local place = cab.place
	if place == nil then
		return CFrame.new(u, v, -w)
	end
	local x, y, z = AlleyLayout.toWorld(place, Layout.toSite(0, 0, 0))
	local ux, uz = AlleyLayout.dirToWorld(place, -1, 0)
	local zx, zz = AlleyLayout.dirToWorld(place, 0, 1)
	local frame =
		CFrame.fromMatrix(Vector3.new(x, y, z), Vector3.new(ux, 0, uz), Vector3.new(0, 1, 0), Vector3.new(zx, 0, zz))
	return frame * CFrame.new(u, v, -w)
end

local function bind()
	if bound then
		return
	end
	bound = true
	game:GetService("RunService"):BindToRenderStep(Cabinet.BIND, Enum.RenderPriority.Camera.Value + 1, function(dt)
		Cabinet.step(dt)
	end)
end

local function wake(cab: Cab)
	cab.awake = true
	cab.far = 0
	bind()
end

function Cabinet.get(station: string, place: any?): Cab
	local cab = cabs[station]
	if cab == nil then
		cab = {
			station = station,
			place = place,
			g = 0,
			start = nil,
			rises = {},
			byHole = blankHoles(),
			score = 0,
			done = false,
			free = true,
			predicted = {},
			say = "",
			sayUntil = -math.huge,
			mallet = nil,
			malletShown = "",
			shownH = {},
			shown = {},
			parts = nil,
			findAt = -math.huge,
			awake = false,
			far = 0,
			live = false,
			cardLabel = nil,
			counted = math.huge,
			went = false,
			hurried = math.huge,
			popped = {},
		}
		cabs[station] = cab
	elseif place ~= nil and cab.place == nil then
		cab.place = place
	end
	return cab
end

local function addRise(cab: Cab, r: Rise)
	local was = cab.rises[r.id]
	if was then
		-- (a round message after the rise: the server's word on its hit wins over this screen's guess)
		was.hitAt, was.from = r.hitAt, r.from
		return
	end
	cab.rises[r.id] = r
	local list = cab.byHole[r.hole]
	if list == nil then
		return
	end
	table.insert(list, r)
	table.sort(list, function(a: Rise, b: Rise): boolean
		return a.at < b.at
	end)
end

local function fresh(cab: Cab, g: number)
	cab.g = g
	table.clear(cab.rises)
	cab.byHole = blankHoles()
	table.clear(cab.predicted)
	table.clear(cab.popped)
	cab.score = 0
	cab.done = false
	cab.free = false
	cab.say = ""
	cab.counted = math.huge
	cab.went = false
	cab.hurried = math.huge
end

function Cabinet.round(cab: Cab, msg: { [string]: any })
	if type(msg.g) ~= "number" or type(msg.start) ~= "number" then
		return
	end
	if msg.g ~= cab.g then
		fresh(cab, msg.g)
	end
	cab.start = msg.start
	cab.score = tonumber(msg.score) or 0
	cab.done = msg.done == true
	cab.free = false
	local t = Cabinet.roundTime(cab)
	if t and t > 0.5 then
		-- (walked up mid-round: the count-in and GO are not heard now)
		cab.counted, cab.went = 0, true
	end
	for _, r in (if type(msg.rises) == "table" then msg.rises else {}) do
		if type(r.id) == "number" and type(r.hole) == "number" and type(r.at) == "number" then
			addRise(
				cab,
				{ id = r.id, hole = r.hole, at = r.at, dur = tonumber(r.dur) or 1, hitAt = r.hitAt, from = r.from }
			)
			cab.popped[r.id] = true
		end
	end
	wake(cab)
end

function Cabinet.rise(cab: Cab, msg: { [string]: any })
	if msg.g ~= cab.g or type(msg.id) ~= "number" or type(msg.hole) ~= "number" or type(msg.at) ~= "number" then
		return
	end
	addRise(cab, { id = msg.id, hole = msg.hole, at = msg.at, dur = tonumber(msg.dur) or 1 })
	wake(cab)
end

-- the server took a strike: the mallet swings there (unless this screen swung it already), the score, the words
function Cabinet.hit(cab: Cab, msg: { [string]: any })
	if msg.g ~= cab.g or type(msg.hole) ~= "number" or type(msg.at) ~= "number" then
		return
	end
	local start = cab.start
	local id = msg.id
	local r = if type(id) == "number" then cab.rises[id] else nil
	if msg.result == "hit" and r then
		r.hitAt, r.from = msg.at, msg.from
		cab.predicted[r.id] = nil
	elseif r and cab.predicted[r.id] then
		-- this screen dropped it, the server says it was not a hit: it comes back up
		r.hitAt, r.from = nil, nil
		cab.predicted[r.id] = nil
	end
	cab.score = tonumber(msg.score) or cab.score
	local t = now()
	if msg.result == "hit" then
		cab.say, cab.sayUntil = "NICE!  +10", t + Cabinet.SAY
		sound("bonk")
	elseif msg.result == "miss" then
		cab.say, cab.sayUntil = "MISS  -2", t + Cabinet.SAY
		sound("thud")
	end
	if not cab.live and start then
		local m = cab.mallet
		if m == nil or m.hole ~= msg.hole or math.abs(m.at - (start + msg.at)) > 0.05 then
			Cabinet.swing(cab, msg.hole, start + msg.at, true)
		end
	end
	wake(cab)
end

function Cabinet.over(cab: Cab, msg: { [string]: any })
	if msg.g ~= cab.g then
		return
	end
	cab.done = true
	cab.score = tonumber(msg.score) or cab.score
	sound("over")
	wake(cab)
end

-- the cabinet at rest: no round, the moles down, the mallet home, FREE PLAY
local function forget(cab: Cab)
	cab.free = true
	cab.done = false
	cab.start = nil
	table.clear(cab.rises)
	cab.byHole = blankHoles()
	table.clear(cab.predicted)
	cab.score = 0
	cab.mallet = nil
	cab.sayUntil = -math.huge
end

function Cabinet.idle(cab: Cab, _msg: { [string]: any }?)
	forget(cab)
	wake(cab)
end

-- the server refused one of this player's strikes: what this screen dropped ahead of its word comes back up (every
-- such mole: a later strike that is taken says so again with its own whack_hit)
function Cabinet.refused(cab: Cab)
	for id in cab.predicted do
		local r = cab.rises[id]
		if r then
			r.hitAt, r.from = nil, nil
		end
	end
	table.clear(cab.predicted)
	wake(cab)
end

function Cabinet.take(cab: Cab)
	cab.live = true
	wake(cab)
end

function Cabinet.release(cab: Cab)
	cab.live = false
	cab.cardLabel = nil
end

function Cabinet.roundTime(cab: Cab): number?
	local start = cab.start
	return if start then now() - start else nil
end

-- the rise in a hole at round time t (the last one begun by then), and its height
local function riseAt(cab: Cab, hole: number, t: number): Rise?
	local list = cab.byHole[hole]
	if list == nil then
		return nil
	end
	for i = #list, 1, -1 do
		if list[i].at <= t then
			return list[i]
		end
	end
	return nil
end

function Cabinet.heightOf(cab: Cab, hole: number, at: number?): number
	local t = at or Cabinet.roundTime(cab)
	if t == nil then
		return 0
	end
	local r = riseAt(cab, hole, t)
	return if r then Round.height(r :: any, t) else 0
end

function Cabinet.hittable(cab: Cab, hole: number, at: number?): boolean
	local t = at or Cabinet.roundTime(cab)
	if t == nil then
		return false
	end
	local r = riseAt(cab, hole, t)
	return r ~= nil and Round.hittable(r :: any, t)
end

-- A swing at a hole at shared-clock time `at`. This player's own (watched = nil): a mole this screen sees can be
-- hit drops at once, ahead of the server's word.
function Cabinet.swing(cab: Cab, hole: number, at: number, watched: boolean?)
	local u, v, w, rx, ry, rz = Cabinet.malletPose(cab, at)
	cab.mallet = { hole = hole, at = at, from = { u, v, w, rx, ry, rz } }
	if not watched then
		sound("swing")
		local start = cab.start
		if start then
			local t = at - start
			local r = riseAt(cab, hole, t)
			if r and Round.hittable(r :: any, t) then
				r.hitAt, r.from = t, Round.height(r :: any, t)
				cab.predicted[r.id] = true
			end
		end
	end
	wake(cab)
end

local function rest(): (number, number, number, number, number, number)
	local M = Layout.MALLET
	return M.rest[1], M.rest[2], M.rest[3], 0, M.restYaw, M.restTip
end

local function over(hole: number, angle: number): (number, number, number, number, number, number)
	local M = Layout.MALLET
	local h = Layout.HOLES[hole]
	return h[1], M.strikeV, h[2] + M.reachW, angle, 0, 0
end

local function ease(k: number): number
	k = math.clamp(k, 0, 1)
	return k * k * (3 - 2 * k)
end

local function mix(a: { number }, b: { number }, k: number): (number, number, number, number, number, number)
	local e = ease(k)
	return a[1] + (b[1] - a[1]) * e,
		a[2] + (b[2] - a[2]) * e,
		a[3] + (b[3] - a[3]) * e,
		a[4] + (b[4] - a[4]) * e,
		a[5] + (b[5] - a[5]) * e,
		a[6] + (b[6] - a[6]) * e
end

-- The mallet at shared-clock time `t`: (u, v, w) of the pivot, then the turn about the across axis (the swing),
-- the vertical (its rest) and the front-to-back axis (its tip at rest).
function Cabinet.malletPose(cab: Cab, t: number): (number, number, number, number, number, number)
	local m = cab.mallet
	if m == nil then
		return rest()
	end
	local M = Layout.MALLET
	local s = t - m.at
	local raised = { over(m.hole, M.raised) }
	if s < Cabinet.MOVE then
		return mix(m.from, raised, s / Cabinet.MOVE)
	end
	s -= Cabinet.MOVE
	if s < Cabinet.DOWN then
		return mix(raised, { over(m.hole, M.struck) }, s / Cabinet.DOWN)
	end
	s -= Cabinet.DOWN
	if s < Cabinet.UP then
		return mix({ over(m.hole, M.struck) }, raised, s / Cabinet.UP)
	end
	s -= Cabinet.UP
	if s < Cabinet.HOVER then
		return table.unpack(raised)
	end
	s -= Cabinet.HOVER
	return mix(raised, { rest() }, s / Cabinet.HOME)
end

-- the words on the sign now
function Cabinet.windows(cab: Cab): { score: string, time: string, status: string }
	local t = Cabinet.roundTime(cab)
	local left = Round.SECONDS
	local status = "WHACK A MOLE!"
	if cab.free or t == nil then
		status = "FREE PLAY  -  PRESS E"
	elseif cab.done or t >= Round.SECONDS then
		left = 0
		status = "TIME!"
	elseif t < 0 then
		status = `READY  {math.ceil(-t)}`
	else
		left = Round.SECONDS - t
		if t < 0.6 then
			status = "GO!"
		end
	end
	if not cab.free and now() < cab.sayUntil and not cab.done then
		status = cab.say
	end
	return {
		score = string.format("%03d", math.clamp(cab.score, 0, 999)),
		time = string.format("%02d", math.clamp(math.ceil(left), 0, 99)),
		status = status,
	}
end

local function write(cab: Cab, label: TextLabel?, key: string, text: string)
	if label and cab.shown[key] ~= text then
		cab.shown[key] = text
		label.Text = text
	end
end

-- The player's card line: the score and the seconds left as the sign has them this frame (the server's state,
-- once a second, would trail the sign by up to a second).
function Cabinet.cardLine(cab: Cab): string
	local t = Cabinet.roundTime(cab)
	local words = Cabinet.windows(cab)
	local time = if t and t < 0 and not cab.free then `READY {math.ceil(-t)}` else `TIME {tonumber(words.time)}`
	return `SCORE {cab.score}    {time}`
end

-- card(cab, label?): the card's line is this label from now on, written every frame it changes (nil: none)
function Cabinet.card(cab: Cab, label: TextLabel?)
	cab.cardLabel = label
	cab.shown.card = nil
	if label then
		write(cab, label, "card", Cabinet.cardLine(cab))
	end
end

-- the count-in and the last seconds, heard once each; a mole's pop as it starts up
local function cues(cab: Cab, t: number)
	if cab.free or cab.done then
		return
	end
	if t < 0 then
		local second = math.ceil(-t)
		if second < cab.counted then
			cab.counted = second
			sound("count")
		end
	elseif not cab.went then
		cab.went = true
		sound("go")
	end
	local left = math.ceil(Round.SECONDS - t)
	if t >= 0 and left >= 1 and left <= 5 and left < cab.hurried then
		cab.hurried = left
		sound("hurry")
	end
	for id, r in cab.rises do
		if not cab.popped[id] and r.at <= t then
			cab.popped[id] = true
			if t - r.at < 0.3 then
				sound("pop")
			end
		end
	end
end

-- one cabinet's frame; returns whether anything is still moving (or a round is on)
local function draw(cab: Cab): boolean
	local p = partsOf(cab)
	local t = Cabinet.roundTime(cab)
	local tnow = now()
	if t then
		cues(cab, t)
	end
	local moving = t ~= nil and not cab.free and not cab.done and t < Round.SECONDS + Round.GRACE + Cabinet.LATE
	if p then
		local pop = Layout.MOLE.pop
		for hole, mole in p.moles do
			local h = if t then Cabinet.heightOf(cab, hole, t) else 0
			if cab.shownH[hole] ~= h then
				cab.shownH[hole] = h
				mole.model:PivotTo(mole.base + Vector3.new(0, pop * h, 0))
			end
			if h > 0 then
				moving = true
			end
		end
		local mallet = p.mallet
		if mallet then
			local u, v, w, rx, ry, rz = Cabinet.malletPose(cab, tnow)
			local key = string.format("%.3f %.3f %.3f %.3f %.3f %.3f", u, v, w, rx, ry, rz)
			if key ~= cab.malletShown then
				cab.malletShown = key
				mallet:PivotTo(
					Cabinet.cframe(cab, u, v, w)
						* CFrame.Angles(0, ry, 0)
						* CFrame.Angles(0, 0, rz)
						* CFrame.Angles(rx, 0, 0)
				)
				moving = true
			end
		end
		local words = Cabinet.windows(cab)
		write(cab, p.score, "score", words.score)
		write(cab, p.time, "time", words.time)
		write(cab, p.status, "status", words.status)
	end
	local line = cab.cardLabel
	if line then
		write(cab, line, "card", Cabinet.cardLine(cab))
	end
	local m = cab.mallet
	if m and tnow - m.at < Cabinet.MOVE + Cabinet.DOWN + Cabinet.UP + Cabinet.HOVER + Cabinet.HOME then
		moving = true
	end
	if tnow < cab.sayUntil then
		moving = true
	end
	return moving
end

function Cabinet.step(_dt: number)
	local any = false
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
		local moving = draw(cab)
		-- a cabinet nobody here plays is put to sleep when it has settled, or when this player has walked away
		if not cab.live then
			local far = false
			local at = me
			if at and cab.place then
				-- (from the prompt, as the server measures its ring)
				local P = Layout.PROMPT
				local x, y, z = AlleyLayout.toWorld(cab.place, Layout.toSite(P.u, P.v, P.w))
				far = (at - Vector3.new(x, y, z)).Magnitude > Cabinet.SLEEP
			end
			if far or not moving then
				cab.far += _dt
				if cab.far > 1 then
					if far then
						-- (out of sight of the round: drawn at rest, and told the round again on the way back)
						forget(cab)
						draw(cab)
					end
					cab.awake = false
					continue
				end
			else
				cab.far = 0
			end
		end
		any = true
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
