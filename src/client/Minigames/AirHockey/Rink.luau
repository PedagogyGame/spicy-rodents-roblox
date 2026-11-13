--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.AirHockey.Rink
-- The air hockey table on this screen: the puck and the two mallets of the baked table
-- (Workspace.Attractions.<alley>.GamesRoom.AirHockey), moved every rendered frame, and the match as a BYSTANDER
-- sees it. The server sends everyone near the table the referee's stream (Shared/Minigames/AirHockey/Wire:
-- fifteen messages a second at most); a Replica replays it tick by tick through the same simulation, a little
-- behind the newest tick (DELAY) and at the pace of this screen's own frames, drawn between ticks: the puck
-- glides at any frame rate and is exactly the server's puck, a moment ago. It simulates nothing of its own.
-- When the local player sits down at the table their controller (Client/Minigames/AirHockey/Controller) takes
-- the drawing over (take / give) and shows them their own prediction instead: show() is the one place the parts
-- are written. The parts are found lazily and may be missing (streaming, a place without the table): then
-- nothing is drawn and nothing breaks. A table nobody has heard from for IDLE seconds is let go (the render
-- step is unbound when no table is being watched).
-- Sound: every contact and goal of the replay is a named cue (cue(), also used by the controller).
-- Interface: get(station, place?) -> Rink; push(rink, msg) (a stream message for that station); rest(rink) (the
--   table has reset: the pieces go home); take(rink) / give(rink); show(rink, px, py, ax, ay, bx, by) (model metres); cue(sim, hit, goal, served, mine?) ;
--   watching() -> number of tables being drawn here; reset() (specs); DELAY; IDLE; BIND

local Import = require("../../Import")
local Layout =
	Import.shared("Minigames/AirHockey/Layout") :: typeof(require("../../../shared/Minigames/AirHockey/Layout"))
local Replica =
	Import.shared("Minigames/AirHockey/Replica") :: typeof(require("../../../shared/Minigames/AirHockey/Replica"))
local Sim = Import.shared("Minigames/AirHockey/Sim") :: typeof(require("../../../shared/Minigames/AirHockey/Sim"))
local MinigameSounds = require("../MinigameSounds")

local Rink = {}

Rink.DELAY = 36 -- ticks a bystander's view runs behind the newest tick received (0.15 s)
Rink.IDLE = 2 -- seconds without a message before a watched table is let go
Rink.BIND = "SpicyAirHockeyRink"

export type Rink = {
	station: string,
	place: any?,
	replica: any,
	at: number, -- the tick the view is at (fractional)
	prev: { number },
	cur: { number },
	parts: any?,
	seated: boolean, -- the local player's controller is drawing
	silent: number, -- seconds of frames since the last message came
	watching: boolean,
}

local rinks: { [string]: Rink } = {}
local bound = false

-- The table's moving pieces as they are on this client now (nil while they have not streamed in).
local function find(): any
	local att = workspace:FindFirstChild("Attractions")
	local site: Instance? = nil
	for _, m in if att then att:GetChildren() else {} do
		if m:GetAttribute("Site") == Layout.SITE then
			site = m
		end
	end
	local room = site and site:FindFirstChild("GamesRoom")
	local model = room and room:FindFirstChild(Layout.MODEL)
	local puck = model and model:FindFirstChild(Layout.PUCK)
	local glacier = model and model:FindFirstChild(Layout.MALLETS[0])
	local ember = model and model:FindFirstChild(Layout.MALLETS[1])
	if puck == nil or glacier == nil or ember == nil then
		return nil
	end
	return { puck = puck, glacier = glacier, ember = ember }
end

function Rink.get(station: string, place: any?): Rink
	local rink = rinks[station]
	if rink == nil then
		rink = {
			station = station,
			place = place,
			replica = Replica.new(),
			at = 0,
			prev = { 0, 0, 0, -0.8, 0, 0.8 },
			cur = { 0, 0, 0, -0.8, 0, 0.8 },
			parts = nil,
			seated = false,
			silent = 0,
			watching = false,
		}
		rinks[station] = rink
	end
	if place ~= nil then
		rink.place = place
	end
	return rink
end

-- The pieces slid to where the match has them (model metres).
function Rink.show(rink: Rink, px: number, py: number, ax: number, ay: number, bx: number, by: number)
	local place = rink.place
	if place == nil then
		return
	end
	local parts = rink.parts
	if parts == nil or parts.puck.Parent == nil then
		parts = find()
		rink.parts = parts
		if parts == nil then
			return
		end
	end
	-- (a piece's pivot is on its own axis: it is slid across the bed, its height and its turn left as they are.
	-- Never from a remembered "home": the server moves these same parts, so where one is now says nothing)
	local function slide(piece: any, x: number, y: number)
		local wx, _, wz = Layout.toWorld(place, x, y)
		local pivot = piece:GetPivot()
		piece:PivotTo(pivot + Vector3.new(wx - pivot.Position.X, 0, wz - pivot.Position.Z))
	end
	slide(parts.puck, px, py)
	slide(parts.glacier, ax, ay)
	slide(parts.ember, bx, by)
end

-- The sound of one tick: what the puck met and how hard, a serve, a goal. `mine` is the end the listener plays
-- (nil for a bystander).
function Rink.cue(sim: any, hit: boolean, goal: boolean, served: boolean, mine: number?)
	if hit then
		local volume = math.clamp(0.25 + sim.hitSpeed / Sim.MAX_SPEED * 0.75, 0, 1)
		if sim.hitWhat >= Sim.HIT_MALLET then
			MinigameSounds.play("air_hockey.strike", volume)
		elseif sim.hitWhat == Sim.HIT_POST then
			MinigameSounds.play("air_hockey.post", volume)
		else
			MinigameSounds.play("air_hockey.rail", volume)
		end
	end
	if served then
		MinigameSounds.play("air_hockey.serve", 0.5)
	end
	if goal then
		if mine == nil then
			MinigameSounds.play("air_hockey.goal", 0.8)
		elseif sim.lastGoal == mine then
			MinigameSounds.play("air_hockey.goal_for", 0.9)
		else
			MinigameSounds.play("air_hockey.goal_against", 0.9)
		end
	end
end

local function keep(rink: Rink, sim: any)
	local p, c = rink.prev, rink.cur
	p[1], p[2], p[3], p[4], p[5], p[6] = c[1], c[2], c[3], c[4], c[5], c[6]
	c[1], c[2], c[3], c[4], c[5], c[6] = sim.px, sim.py, sim.p0x, sim.p0y, sim.p1x, sim.p1y
end

local function frame(dt: number)
	local any = false
	for _, rink in rinks do
		if not rink.watching then
			continue
		end
		local r = rink.replica
		rink.silent += dt
		if rink.seated or (rink.silent > Rink.IDLE and r.tick >= r.head) then
			rink.watching = false
			continue
		end
		any = true
		-- the view's own clock: this screen's frames, held DELAY ticks behind the newest tick known
		-- (once the stream has stopped, the view runs on to its end)
		local want = if rink.silent > 0.4 then r.head else r.head - Rink.DELAY
		rink.at += dt / Sim.STEP
		if math.abs(rink.at - want) > 2 * Rink.DELAY then
			rink.at = want
		else
			rink.at += (want - rink.at) * math.min(1, dt * 2)
		end
		rink.at = math.clamp(rink.at, r.tick - 1, r.head)
		local whole = math.floor(rink.at)
		Replica.step(r, whole + 1, function(sim: any, _tick: number, hit: boolean, goal: boolean)
			keep(rink, sim)
			Rink.cue(sim, hit, goal, false, nil)
		end)
		local f = math.clamp(rink.at - (r.tick - 1), 0, 1)
		local p, c = rink.prev, rink.cur
		local px, py = p[1] + (c[1] - p[1]) * f, p[2] + (c[2] - p[2]) * f
		if math.abs(c[1] - p[1]) + math.abs(c[2] - p[2]) > 0.2 then
			-- (put back on its spot within this tick: nobody slides it there)
			if f < 0.5 then
				px, py = p[1], p[2]
			else
				px, py = c[1], c[2]
			end
		end
		Rink.show(
			rink,
			px,
			py,
			p[3] + (c[3] - p[3]) * f,
			p[4] + (c[4] - p[4]) * f,
			p[5] + (c[5] - p[5]) * f,
			p[6] + (c[6] - p[6]) * f
		)
	end
	if not any and bound then
		bound = false
		game:GetService("RunService"):UnbindFromRenderStep(Rink.BIND)
	end
end

function Rink.push(rink: Rink, msg: any)
	local r = rink.replica
	local jumps = r.jumps
	if not Replica.push(r, msg) then
		return
	end
	rink.silent = 0
	if r.jumps ~= jumps then
		-- taken as it stands: the view starts there
		rink.at = r.tick
		keep(rink, r.sim)
		keep(rink, r.sim)
	end
	if rink.seated then
		return
	end
	rink.watching = true
	if not bound then
		bound = true
		game:GetService("RunService"):BindToRenderStep(Rink.BIND, Enum.RenderPriority.Last.Value, frame)
	end
end

-- The local player's controller draws this table from now on (their own prediction)...
function Rink.take(rink: Rink)
	rink.seated = true
end

-- ...and hands it back: the next stream message starts a bystander's view afresh.
function Rink.give(rink: Rink)
	rink.seated = false
	rink.replica = Replica.new()
end

-- The server's word that the table is at rest: the pieces go home on this screen too (it moved them itself, so
-- the server's own move of them would not show), and nothing is drawn until the next match.
function Rink.rest(rink: Rink)
	rink.replica = Replica.new()
	rink.watching = false
	if not rink.seated then
		local hp, hm = Layout.HOME_PUCK, Layout.HOME_MALLET
		Rink.show(rink, hp[1], hp[2], hm[0][1], hm[0][2], hm[1][1], hm[1][2])
	end
end

-- Every table forgotten and the render step let go (the specs start each case from nothing).
function Rink.reset()
	table.clear(rinks)
	if bound then
		bound = false
		game:GetService("RunService"):UnbindFromRenderStep(Rink.BIND)
	end
end

function Rink.watching(): number
	local n = 0
	for _, rink in rinks do
		if rink.watching then
			n += 1
		end
	end
	return n
end

return Rink
