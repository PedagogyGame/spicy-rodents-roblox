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
-- the script's own rest (and each potted ball's home), which is exactly where the server lays the balls when
-- the shot is judged (Server/Minigames/Pool/Hardware uses the same Furniture and Roll), so nothing pops when
-- playback lets go. If the table is not on this client (streamed out) nothing is played.
-- Interface: play(place, def, script, opts { lead?, onCue? }) -> bool; stop(stationId) (cut short: nothing
--   more is written); set(place, def, table, flat { id, x, z ... }, away { ids }?, fresh?) (lay the balls out:
--   a new rack, a shot that did not count); put(place, def, table, id, x, z) (one ball on the cloth: the cue
--   ball in the hand); playing(stationId) -> bool; now(stationId) -> seconds since the strike (negative
--   during the stroke), or nil; find(def) -> the table's Model?; ballAt(def, id) -> Vector3?; TAIL, HIDE,
--   FOLLOW; clock (os.clock; a test swaps it). def = the station's StationDef (id, game, site, index, x, d)

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
}

local active: { [string]: Entry } = {}
local bound = false

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

-- The script's own end: every ball it moved at rest where it stopped, or at home. (Returns true so that
-- pcall(finish, ...) has a second value to hand back either way.)
local function finish(e: Entry): boolean
	release(e)
	local script = e.script
	local tb = e.table
	local rest: { [number]: { number } } = {}
	for k = 1, #script.rest, 3 do
		rest[script.rest[k]] = { script.rest[k + 1], script.rest[k + 2] }
	end
	local last = Roll.steps(script.tEnd)
	for i, id in script.ids do
		local m = e.balls[id] :: Model?
		if m == nil or m.Parent == nil or #script.tracks[i] == 0 then
			continue
		end
		local rot = e.rots[id]
		if e.dropAt[id] == nil and last > e.steps[id] then
			Roll.advance(rot, script, i, e.steps[id], last)
			e.steps[id] = last
		end
		Roll.tidy(rot)
		local at = rest[id]
		if at then
			m:PivotTo(frameOf(e.place, e.def, e.yaw, at[1], tb.ballR, at[2], rot))
		else
			local x, y, z = Furniture.off(tb, id, false)
			m:PivotTo(frameOf(e.place, e.def, e.yaw, x, y, z, rot))
		end
	end
	return true
end

local function step()
	local now = Playback.clock()
	for id, e in active do
		local t = now - e.t0
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
	if next(active) == nil and bound then
		bound = false
		game:GetService("RunService"):UnbindFromRenderStep(Playback.BIND)
	end
end

-- play: start drawing a shot at a table. Returns false (and plays nothing) when the table is not on this
-- client. A shot still playing at that table is brought to its end first.
function Playback.play(place: any, def: Def, script: any, opts: { [string]: any }?): boolean
	local old = active[def.id]
	if old then
		pcall(finish, old)
		active[def.id] = nil
	end
	if place == nil then
		return false
	end
	local balls = ballsOf(Playback.find(def))
	if next(balls) == nil then
		return false
	end
	local o: { [string]: any } = opts or {}
	local lead = math.clamp(tonumber(o.lead) or 0, 0, 5)
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
	active[def.id] = {
		place = place,
		def = def,
		table = tb,
		script = script,
		t0 = Playback.clock() + lead,
		lead = lead,
		tOver = tOver,
		yaw = yaw,
		balls = balls,
		rots = rots,
		steps = steps,
		dropAt = dropAt,
		dropX = dropX,
		cues = cues,
		cueAt = 1,
		onCue = o.onCue,
		strokes = strokes,
	}
	-- (bound afresh with every shot: a binding is never assumed to have outlived what it was bound in)
	local RunService = game:GetService("RunService")
	if bound then
		RunService:UnbindFromRenderStep(Playback.BIND)
	end
	bound = true
	-- before the camera's own step, so a shot that follows the balls sees this frame's balls
	RunService:BindToRenderStep(Playback.BIND, Enum.RenderPriority.Camera.Value - 1, step)
	return true
end

-- stop: a shot was cut short (the table emptied, the shooter left): nothing more of it is written.
function Playback.stop(stationId: string)
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
	return if e then Playback.clock() - e.t0 else nil
end

return Playback
