--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Pool.Playback
-- Draws a shot at a cue-sport table on this screen (pool's two tables and the bumper pool table). The server
-- runs the table model the moment the cue strikes and sends one script to everyone (Shared/Minigames/Pool/
-- Shot, as Wire text); this module plays that script back on the table's baked balls every rendered frame:
--   the cue's stroke first (a cue is drawn behind each struck ball, back as far as the shot's power and then
--     through the ball: `lead` seconds, so a watcher and a computer player's opponent see the shot coming);
--   every ball where the script has it at that instant (Shot.pose is exact at any frame rate), turning as its
--     roll and side spin say (Pool/Roll: the numbers and stripes go round, follow rolls on, draw spins back);
--   a ball that goes down drops into the pocket's well, is out of sight for a moment and then rolls along
--     the tray to its own place (Furniture.home), so the trays always show the game;
--   the sound cue points of the script (Shot.cues: strike, click, crack, cushion, jaw, post, drop, rim) and
--     "home" when a ball reaches its tray, handed to `onCue`.
-- It simulates nothing, so no two screens can disagree and what is seen is what is scored. The last write is
-- the layout the rules judged (`after`, sent with the script: the script's rest, with a potted 8 back on its
-- spot or a scratched cue ball on the head spot) and every other ball at home, which is exactly where the
-- server lays the balls when the shot is judged (Server/Minigames/Pool/Hardware uses the same Furniture and
-- Roll), so nothing pops when playback lets go and no screen keeps a ball where the rules do not. If the table is not on this client (streamed out) nothing is played.
-- A slow replay (opts.speed under 1: the winning shot of a game, played again) is the same drawing on a slower
-- clock: every pose, stroke and sound at its own moment of the script.
-- Another player lining a shot up is drawn too: their cue behind their ball, eased toward what they last told
-- (aim), until the stroke takes over.
-- Interface: play(place, def, script, opts { lead?, onCue?, speed?, after?, away? }) -> bool (after: flat
--   { id, x, z ... } where the rules lay the balls once the shot is judged; away: { ids } out of sight); stop(stationId) (cut short: nothing
--   more is written); set(place, def, table, flat { id, x, z ... }, away { ids }?, fresh?) (lay the balls out:
--   a new rack, a shot that did not count); put(place, def, table, id, x, z) (one ball on the cloth: the cue
--   ball in the hand); playing(stationId) -> bool; now(stationId) -> seconds since the strike (negative
--   during the stroke), or nil; find(def) -> the table's Model?; ballAt(def, id) -> Vector3?; TAIL, HIDE,
--   FOLLOW; aim(place, def, msg) (another player's cue as they aim); aiming(stationId) -> bool; AIM_STALE,
--   AIM_EASE; clock (os.clock; a test swaps it). def = the station's StationDef (id, game, site, index, x, d)

local Import = require("../../Import")
local AlleyLayout =
	Import.shared("Attractions/AlleyLayout") :: typeof(require("../../../shared/Attractions/AlleyLayout"))
local Cue = Import.shared("Minigames/Pool/Cue") :: typeof(require("../../../shared/Minigames/Pool/Cue"))
local Furniture =
	Import.shared("Minigames/Pool/Furniture") :: typeof(require("../../../shared/Minigames/Pool/Furniture"))
local Roll = Import.shared("Minigames/Pool/Roll") :: typeof(require("../../../shared/Minigames/Pool/Roll"))
local Shot = Import.shared("Minigames/Pool/Shot") :: typeof(require("../../../shared/Minigames/Pool/Shot"))
local Tables = Import.shared("Minigames/Pool/Tables") :: typeof(require("../../../shared/Minigames/Pool/Tables"))
local Stick = require("./Stick")

local Playback = {}

Playback.TAIL = 0.6 -- seconds the final pose is held (the server judges the shot 0.25 s after its end)
Playback.HIDE = 0.3 -- seconds a potted ball is out of sight before it rolls into its tray
Playback.FOLLOW = 0.4 -- seconds the cue is still drawn after the strike
Playback.BIND = "SpicyPoolPlayback"
Playback.clock = os.clock

export type Def = { id: string, game: string, site: string, index: number?, x: number, d: number, [string]: any }
type Stroke = {
	id: number,
	x: number, -- where the struck ball lies
	z: number,
	dx: number, -- the shot's line
	dz: number,
	back: number, -- how far the cue is drawn back
	tipX: number,
	tipY: number,
	stick: any?,
}
type Entry = {
	place: any,
	def: Def,
	table: any,
	script: any,
	t0: number, -- the clock at the strike
	lead: number,
	tOver: number, -- seconds after the strike at which playback lets go
	yaw: CFrame,
	balls: { [number]: Model },
	rots: { [number]: { number } },
	steps: { [number]: number },
	dropAt: { [number]: number },
	dropX: { [number]: number },
	cues: { { any } },
	cueAt: number,
	onCue: ((name: string, volume: number) -> ())?,
	strokes: { Stroke },
	speed: number, -- 1, or less for a slow replay (script seconds per second)
	after: { [number]: { number } }?, -- where the rules lay each ball on the cloth once the shot is judged
	away: { [number]: boolean }, -- balls kept out of sight once it is judged (the rest are at home)
}

local active: { [string]: Entry } = {}
-- shots at tables that are not on this client yet: taken up if the table arrives while they still run
local waiting: { [string]: { place: any, def: Def, script: any, opts: { [string]: any }, t0: number, ends: number } } =
	{}
local bound = false
-- another player lining a shot up (their "aim", relayed by the server): the cue drawn behind their ball here
type Aim = {
	place: any,
	def: Def,
	ball: number,
	angle: number, -- as last told
	power: number,
	tipX: number,
	tipY: number,
	shown: { number }, -- angle, power, tipX, tipY as drawn: eased toward the last told, at any frame rate
	at: number, -- the clock when it was last told
	stick: any,
}
local aims: { [string]: Aim } = {}
local lastStep: number? = nil

local function unaim(id: string)
	local a = aims[id]
	if a then
		a.stick:destroy()
		aims[id] = nil
	end
end

local function siteModel(site: string): Instance?
	local att = workspace:FindFirstChild("Attractions")
	for _, m in if att then att:GetChildren() else {} do
		if m:GetAttribute("Site") == site then
			return m
		end
	end
	return nil
end

-- The table's Model as it is on this client right now (nil while it is streamed out).
function Playback.find(def: Def): Instance?
	local root = siteModel(def.site)
	local room = root and root:FindFirstChild("GamesRoom")
	return room and room:FindFirstChild(Furniture.modelName(def.game, def.index))
end

local function ballsOf(model: Instance?): { [number]: Model }
	local out: { [number]: Model } = {}
	if model then
		for id = 0, 15 do
			local m = model:FindFirstChild(Furniture.ballName(id))
			if m and m:IsA("Model") then
				out[id] = m
			end
		end
	end
	return out
end

local function yawOf(place: any): CFrame
	return CFrame.Angles(0, AlleyLayout.yawOf(place), 0)
end

-- How a ball is turned now, read off its Model (the table's own frame: Pool/Roll).
local function rotOf(m: Model, yaw: CFrame): { number }
	local _, _, _, a, b, c, d, e, f, g, h, i = (yaw:Inverse() * m:GetPivot().Rotation):GetComponents()
	local rot = { a, b, c, d, e, f, g, h, i }
	Roll.tidy(rot)
	return rot
end

local function frameOf(place: any, def: Def, yaw: CFrame, x: number, y: number, z: number, r: { number }): CFrame
	local wx, wy, wz = Furniture.world(place, def, x, y, z)
	return CFrame.new(wx, wy, wz) * yaw * CFrame.new(0, 0, 0, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
end

local function point(place: any, def: Def, x: number, y: number, z: number): Vector3
	local wx, wy, wz = Furniture.world(place, def, x, y, z)
	return Vector3.new(wx, wy, wz)
end

-- The cue for one strike, t seconds from the strike (negative: the stroke is on its way).
local function drawStroke(e: Entry, s: Stroke, t: number)
	if t < -e.lead or t > Playback.FOLLOW then
		if s.stick then
			s.stick:destroy()
			s.stick = nil
		end
		return
	end
	local stick: any = s.stick
	if stick == nil then
		stick = Stick.new()
		s.stick = stick
	end
	local r = e.table.ballR
	local rest = Furniture.CUE_REST
	local gap: number
	local alpha = 1
	if t < 0 then
		local u = (t + e.lead) / e.lead -- 0 .. 1 over the lead
		if e.lead < 0.4 then
			-- a person has already drawn the cue back: it only comes through
			gap = s.back * (1 - u * u)
		elseif u < 0.55 then
			local k = u / 0.55
			gap = rest + (s.back - rest) * (k * k * (3 - 2 * k))
		elseif u < 0.8 then
			gap = s.back
		else
			local k = (u - 0.8) / 0.2
			gap = s.back * (1 - k * k)
		end
	else
		-- through the ball a little way, then it is lifted away
		local k = t / Playback.FOLLOW
		gap = -math.min(0.35, t * 3)
		alpha = 1 - k * k
	end
	local wdx, wdz = Furniture.dir(e.place, s.dx, s.dz)
	local level = Vector3.new(wdx, 0, wdz)
	local right = Vector3.new(-wdz, 0, wdx) -- the shooter's right
	local toward = (level * math.cos(Furniture.CUE_PITCH) - Vector3.new(0, math.sin(Furniture.CUE_PITCH), 0)).Unit
	local at = point(e.place, e.def, s.x, r, s.z)
		+ right * (s.tipX * Cue.TIP_MAX * r)
		+ Vector3.new(0, s.tipY * Cue.TIP_MAX * r, 0)
	stick:pose(at - toward * (r + gap), toward, alpha)
end

-- Returns true so that pcall(write, ...) has a second value to hand back whether it failed or not.
local function write(e: Entry, t: number): boolean
	local script = e.script
	local tb = e.table
	local r = tb.ballR
	local tt = math.min(t, script.tEnd)
	for i, id in script.ids do
		local m = e.balls[id] :: Model?
		if m == nil or m.Parent == nil or #script.tracks[i] == 0 then
			continue
		end
		local x, z, y, mode = Shot.pose(script, i, tt)
		local px, py, pz = x, r + y, z
		local rot = e.rots[id]
		if mode == 3 then
			local since = t - (e.dropAt[id] or tt) - Playback.HIDE
			if since > 0 then
				local hx, hy, hz = Furniture.off(tb, id, false)
				if id ~= 0 then
					local gx = Furniture.homeGate(tb, id, e.dropX[id] or 0)
					local k = math.clamp(since / Furniture.TRAY_ROLL, 0, 1)
					hx = gx + (hx - gx) * (1 - (1 - k) * (1 - k))
				end
				px, py, pz = hx, hy, hz
			end
		else
			local steps = Roll.steps(math.max(tt, 0))
			if steps > e.steps[id] then
				Roll.advance(rot, script, i, e.steps[id], steps)
				e.steps[id] = steps
			end
			rot = Roll.at(rot, script, i, steps, tt)
		end
		m:PivotTo(frameOf(e.place, e.def, e.yaw, px, py, pz, rot))
	end
	for _, s in e.strokes do
		drawStroke(e, s, t)
	end
	return true
end

local function release(e: Entry)
	for _, s in e.strokes do
		if s.stick then
			s.stick:destroy()
			s.stick = nil
		end
	end
end

-- The shot's end: every ball where the rules have laid it once the shot is judged (`after`, sent with the
-- script: a re-spotted 8, a scratched cue ball back on the head spot, a practice ball put back by its cup), and
-- every other ball at home in the tray or out of sight; a script with no `after` ends where it stopped. Each
-- ball the script moved is turned on to the end of its roll. (Returns true so that pcall(finish, ...) has a
-- second value to hand back either way.)
local function finish(e: Entry): boolean
	release(e)
	local script = e.script
	local tb = e.table
	local at: { [number]: { number } } = {}
	if e.after then
		at = e.after
	else
		for k = 1, #script.rest, 3 do
			at[script.rest[k]] = { script.rest[k + 1], script.rest[k + 2] }
		end
	end
	local last = Roll.steps(script.tEnd)
	for i, id in script.ids do
		local rot = e.rots[id]
		if rot and #script.tracks[i] > 0 and e.dropAt[id] == nil and last > e.steps[id] then
			Roll.advance(rot, script, i, e.steps[id], last)
			e.steps[id] = last
		end
	end
	for id, m in e.balls do
		if m.Parent == nil then
			continue
		end
		local index = Shot.indexOf(script, id)
		local moved = index ~= nil and #script.tracks[index] > 0
		if e.after == nil and not moved then
			continue
		end
		local rot = e.rots[id]
		Roll.tidy(rot)
		local spot = at[id]
		if spot then
			m:PivotTo(frameOf(e.place, e.def, e.yaw, spot[1], tb.ballR, spot[2], rot))
		else
			local x, y, z = Furniture.off(tb, id, e.away[id] == true)
			m:PivotTo(frameOf(e.place, e.def, e.yaw, x, y, z, rot))
		end
	end
	return true
end

-- (defined below play's helpers: a shot waiting for its table is begun from the frame step)
local begin: (place: any, def: Def, script: any, o: { [string]: any }, t0: number) -> Entry?

local drawAims: (now: number, dt: number) -> ()

local function step()
	local now = Playback.clock()
	local dt = math.clamp(now - (lastStep or now), 0, 0.25)
	lastStep = now
	drawAims(now, dt)
	for id, wt in waiting do
		if now >= wt.ends then
			-- (the shot ended before the table reached this client: the server's own layout of it is what arrives)
			waiting[id] = nil
		else
			local e = begin(wt.place, wt.def, wt.script, wt.opts, wt.t0)
			if e then
				waiting[id] = nil
				active[id] = e
			end
		end
	end
	for id, e in active do
		local t = (now - e.t0) * e.speed
		local ok, err = pcall(write, e, t)
		if not ok then
			warn(`Pool playback: {id}: {err}`)
			release(e)
			active[id] = nil
			continue
		end
		while e.cueAt <= #e.cues and e.cues[e.cueAt][1] <= t do
			local cue = e.cues[e.cueAt]
			e.cueAt += 1
			if e.onCue then
				pcall(e.onCue, cue[2], cue[3])
			end
		end
		if t >= e.tOver then
			local done, why = pcall(finish, e)
			if not done then
				warn(`Pool playback: {id}: {why}`)
			end
			active[id] = nil
		end
	end
	if next(active) == nil and next(waiting) == nil and next(aims) == nil and bound then
		lastStep = nil
		bound = false
		game:GetService("RunService"):UnbindFromRenderStep(Playback.BIND)
	end
end

-- play: start drawing a shot at a table. Returns false (and plays nothing) when the table is not on this
-- client. A shot still playing at that table is brought to its end first.
-- The entry for a shot whose strike is (or was) at t0 on Playback.clock, on the balls as they are now; nil when
-- the table is not on this client.
function begin(place: any, def: Def, script: any, o: { [string]: any }, t0: number): Entry?
	local balls = ballsOf(Playback.find(def))
	if next(balls) == nil then
		return nil
	end
	local lead = math.clamp(tonumber(o.lead) or 0, 0, 5)
	local pace = math.clamp(tonumber(o.speed) or 1, 0.1, 1)
	local tb = Tables.byId(script.table)
	local yaw = yawOf(place)
	local rots: { [number]: { number } } = {}
	local steps: { [number]: number } = {}
	for id, m in balls do
		rots[id] = rotOf(m, yaw)
		steps[id] = 0
	end
	local dropAt: { [number]: number } = {}
	local dropX: { [number]: number } = {}
	local cues: { { any } } = {}
	for _, c in Shot.cues(script) do
		table.insert(cues, { c.t, c.name, c.volume })
	end
	local tOver = script.tEnd + Playback.TAIL
	for _, p in Shot.pots(script) do
		if dropAt[p.ball] == nil then
			dropAt[p.ball] = p.t
			local hole = tb.holes[p.hole]
			dropX[p.ball] = if hole then hole.x else 0
			if p.ball ~= 0 then
				local home = p.t + Playback.HIDE + Furniture.TRAY_ROLL
				table.insert(cues, { home, "home", 0.5 })
				tOver = math.max(tOver, home + 0.1)
			end
		end
	end
	table.sort(cues, function(a, b)
		return a[1] < b[1]
	end)
	-- where the rules lay the balls once the shot is judged (flat id, x, z; and the ids kept out of sight)
	local after: { [number]: { number } }? = nil
	if type(o.after) == "table" then
		local laid: { [number]: { number } } = {}
		local flat = o.after :: { any }
		for k = 1, #flat - 2, 3 do
			local id, x, z = flat[k], flat[k + 1], flat[k + 2]
			if type(id) == "number" and type(x) == "number" and type(z) == "number" then
				laid[id] = { x, z }
			end
		end
		after = laid
	end
	local away: { [number]: boolean } = {}
	if type(o.away) == "table" then
		for _, id in o.away :: { any } do
			if type(id) == "number" then
				away[id] = true
			end
		end
	end
	local strokes: { Stroke } = {}
	local st = script.strikes
	for k = 1, #st, 6 do
		local id, vx, vz, qx, qz, s = st[k], st[k + 1], st[k + 2], st[k + 3], st[k + 4], st[k + 5]
		local speed = math.sqrt(vx * vx + vz * vz)
		local i = Shot.indexOf(script, id)
		if speed > 0 and i then
			local dx, dz = vx / speed, vz / speed
			local spin = 2.5 * Cue.TIP_MAX * speed
			table.insert(strokes, {
				id = id,
				x = script.start[i * 2 - 1],
				z = script.start[i * 2],
				dx = dx,
				dz = dz,
				back = Furniture.CUE_REST + Furniture.CUE_BACK * Cue.powerFor(speed),
				tipX = math.clamp(s / spin, -1, 1),
				tipY = math.clamp((qx * dx + qz * dz) / spin, -1, 1),
				stick = nil,
			})
		end
	end
	-- (a shot taken up part way through, by a client the table has only now reached: its sounds so far are past)
	local tNow = (Playback.clock() - t0) * pace
	local cueAt = 1
	while cueAt <= #cues and cues[cueAt][1] < tNow do
		cueAt += 1
	end
	return {
		place = place,
		def = def,
		table = tb,
		script = script,
		t0 = t0,
		lead = lead,
		tOver = tOver,
		yaw = yaw,
		balls = balls,
		rots = rots,
		steps = steps,
		dropAt = dropAt,
		dropX = dropX,
		cues = cues,
		cueAt = cueAt,
		onCue = o.onCue,
		strokes = strokes,
		speed = pace,
		after = after,
		away = away,
	}
end

local function bind()
	-- (bound afresh with every shot: a binding is never assumed to have outlived what it was bound in)
	local RunService = game:GetService("RunService")
	if bound then
		RunService:UnbindFromRenderStep(Playback.BIND)
	end
	bound = true
	-- before the camera's own step, so a shot that follows the balls sees this frame's balls
	RunService:BindToRenderStep(Playback.BIND, Enum.RenderPriority.Camera.Value - 1, step)
end

-- play: start drawing a shot at a table. A shot still playing at that table is brought to its end first. When
-- the table is not on this client (streamed out: the player is across the building) nothing is drawn now and
-- false is returned, but the shot is kept: if the table arrives while the shot is still running (the player
-- walks up mid-shot), it is taken up at the moment it has reached, and played on from there.
function Playback.play(place: any, def: Def, script: any, opts: { [string]: any }?): boolean
	local old = active[def.id]
	if old then
		pcall(finish, old)
		active[def.id] = nil
	end
	waiting[def.id] = nil
	unaim(def.id)
	if place == nil then
		return false
	end
	local o: { [string]: any } = opts or {}
	local t0 = Playback.clock() + math.clamp(tonumber(o.lead) or 0, 0, 5)
	local e = begin(place, def, script, o, t0)
	if e == nil then
		local pace = math.clamp(tonumber(o.speed) or 1, 0.1, 1)
		waiting[def.id] =
			{ place = place, def = def, script = script, opts = o, t0 = t0, ends = t0 + script.tEnd / pace }
		bind()
		return false
	end
	active[def.id] = e
	bind()
	return true
end

-- Another player's cue as they aim, drawn behind their ball and eased toward what they last told (eight times
-- a second), so it swings smoothly at any frame rate. A cue not told of for AIM_STALE seconds is put away.
Playback.AIM_STALE = 1.5
Playback.AIM_EASE = 14 -- the drawn cue closes this share of its gap a second (exponentially)

function drawAims(now: number, dt: number)
	for id, a in aims do
		local m = ballsOf(Playback.find(a.def))[a.ball] :: Model?
		if now - a.at > Playback.AIM_STALE or active[id] ~= nil or m == nil then
			unaim(id)
			continue
		end
		local k = 1 - math.exp(-Playback.AIM_EASE * dt)
		local sh = a.shown
		-- (the angle the short way round)
		local da = (a.angle - sh[1] + math.pi) % (2 * math.pi) - math.pi
		sh[1] += da * k
		sh[2] += (a.power - sh[2]) * k
		sh[3] += (a.tipX - sh[3]) * k
		sh[4] += (a.tipY - sh[4]) * k
		local tb = Tables.byId(if a.def.game == "bumper_pool" then "bumper" else "eightball")
		local r = tb.ballR
		local dx, dz = Cue.dirOf(sh[1])
		local wdx, wdz = Furniture.dir(a.place, dx, dz)
		local level = Vector3.new(wdx, 0, wdz)
		local right = Vector3.new(-wdz, 0, wdx)
		local toward = (level * math.cos(Furniture.CUE_PITCH) - Vector3.new(0, math.sin(Furniture.CUE_PITCH), 0)).Unit
		local at = (m :: Model):GetPivot().Position
			+ right * (sh[3] * Cue.TIP_MAX * r)
			+ Vector3.new(0, sh[4] * Cue.TIP_MAX * r, 0)
		a.stick:pose(at - toward * (r + Furniture.CUE_REST + Furniture.CUE_BACK * sh[2]), toward, 1)
	end
end

-- aim: another player's cue as they line a shot up (msg = their "aim": ball, angle, power, tipX, tipY).
function Playback.aim(place: any, def: Def, msg: { [string]: any })
	if place == nil or active[def.id] ~= nil then
		return
	end
	local ball, angle = tonumber(msg.ball), tonumber(msg.angle)
	if ball == nil or angle == nil then
		return
	end
	local a = aims[def.id]
	local power = math.clamp(tonumber(msg.power) or 0, 0, 1)
	local tipX = math.clamp(tonumber(msg.tipX) or 0, -1, 1)
	local tipY = math.clamp(tonumber(msg.tipY) or 0, -1, 1)
	if a == nil or a.ball ~= ball then
		unaim(def.id)
		a = {
			place = place,
			def = def,
			ball = ball,
			angle = angle,
			power = power,
			tipX = tipX,
			tipY = tipY,
			shown = { angle, power, tipX, tipY },
			at = Playback.clock(),
			stick = Stick.new(),
		}
		aims[def.id] = a
	end
	local aim = a :: Aim
	aim.angle, aim.power, aim.tipX, aim.tipY = angle, power, tipX, tipY
	aim.at = Playback.clock()
	if not bound then
		bind()
	end
end

-- aiming(stationId) -> is another player's cue drawn at that table now?
function Playback.aiming(stationId: string): boolean
	return aims[stationId] ~= nil
end

-- stop: a shot was cut short (the table emptied, the shooter left): nothing more of it is written.
function Playback.stop(stationId: string)
	waiting[stationId] = nil
	unaim(stationId)
	local e = active[stationId]
	if e then
		release(e)
		active[stationId] = nil
	end
end

-- set: lay the table's balls out on this screen as the game has them: `flat` is id, x, z for every ball on
-- the cloth; every other ball is at home (or out of sight if `away` lists it). fresh = true turns every ball
-- back the way it was baked (a new rack).
function Playback.set(place: any, def: Def, tb: any, flat: { number }, away: { number }?, fresh: boolean?)
	if place == nil then
		return
	end
	local balls = ballsOf(Playback.find(def))
	local yaw = yawOf(place)
	local on: { [number]: boolean } = {}
	local function rotFor(m: Model): { number }
		return if fresh then Roll.identity() else rotOf(m, yaw)
	end
	for k = 1, #flat - 2, 3 do
		local id = flat[k]
		local m = balls[id]
		on[id] = true
		if m then
			m:PivotTo(frameOf(place, def, yaw, flat[k + 1], tb.ballR, flat[k + 2], rotFor(m)))
		end
	end
	for id, m in balls do
		if not on[id] then
			local x, y, z = Furniture.off(tb, id, away ~= nil and table.find(away, id) ~= nil)
			m:PivotTo(frameOf(place, def, yaw, x, y, z, rotFor(m)))
		end
	end
end

-- put: one ball on the cloth at (x, z) (the cue ball following the hand that places it).
function Playback.put(place: any, def: Def, tb: any, id: number, x: number, z: number)
	local m = ballsOf(Playback.find(def))[id]
	if m and place then
		local yaw = yawOf(place)
		m:PivotTo(frameOf(place, def, yaw, x, tb.ballR, z, rotOf(m, yaw)))
	end
end

function Playback.ballAt(def: Def, id: number): Vector3?
	local m = ballsOf(Playback.find(def))[id]
	return if m then m:GetPivot().Position else nil
end

function Playback.playing(stationId: string): boolean
	return active[stationId] ~= nil
end

function Playback.now(stationId: string): number?
	local e = active[stationId]
	return if e then (Playback.clock() - e.t0) * e.speed else nil
end

return Playback
