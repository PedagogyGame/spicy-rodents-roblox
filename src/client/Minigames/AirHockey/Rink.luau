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
-- Sound: every contact, serve and goal of the replay is a named cue (cue(), also used by the controller).
-- THE PEOPLE PLAYING REACH FOR THEIR MALLETS (Client/Minigames/AirHockey/Reach): whoever stands in an end's
-- standing room while a person plays that end has their right arm aimed at that end's mallet as this screen
-- draws it, and leans toward it. It is worked out here on every screen from the mallets shown (nothing is sent
-- for it); the bodies are looked for under Workspace.Bodies a few times a second; the joints are written in
-- RunService.Stepped, after the Animator, only while a table is being drawn here. The local player's own arm is
-- left alone while they play (their body is out of their own view, and an arm across it would not be).
-- Interface: get(station, place?) -> Rink; push(rink, msg) (a stream message for that station); rest(rink) (the
--   table has reset: the pieces go home); take(rink) / give(rink); show(rink, px, py, ax, ay, bx, by) (model metres); cue(sim, hit, goal, served, mine?);
--   playing(rink, mode, own?) (the seated controller's word: which ends people play, Referee.mode, and the
--   end that is the local player's); reach() (the Stepped step: every arm aimed; specs call it themselves);
--   contact(what, speed) (one contact's sound);
--   watching() -> number of tables being drawn here; reset() (specs); DELAY; IDLE; BIND; LOOK

local Import = require("../../Import")
local Layout =
	Import.shared("Minigames/AirHockey/Layout") :: typeof(require("../../../shared/Minigames/AirHockey/Layout"))
local Replica =
	Import.shared("Minigames/AirHockey/Replica") :: typeof(require("../../../shared/Minigames/AirHockey/Replica"))
local Sim = Import.shared("Minigames/AirHockey/Sim") :: typeof(require("../../../shared/Minigames/AirHockey/Sim"))
local MinigameSounds = require("../MinigameSounds")
local Reach = require("./Reach")

local Rink = {}

Rink.DELAY = 36 -- ticks a bystander's view runs behind the newest tick received (0.15 s)
Rink.IDLE = 2 -- seconds without a message before a watched table is let go
Rink.BIND = "SpicyAirHockeyRink"
Rink.LOOK = 0.5 -- seconds between two looks for who stands at each end

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
	hands: { number }, -- the two mallets as last shown (ax, ay, bx, by), and how many reach steps ago
	stale: number,
	mode: string, -- which ends people play ("0", "1", "2": Referee.mode)
	own: number?, -- the end the local player plays here
	arms: { [number]: Reach.Arm }, -- the arm aimed at each end's mallet
	lookedAt: number,
}

local rinks: { [string]: Rink } = {}
local bound = false
local stepped: any = nil -- the Stepped connection, while a table is being drawn here

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
			hands = { 0, -0.8, 0, 0.8 },
			stale = math.huge,
			mode = "",
			own = nil,
			arms = {},
			lookedAt = -math.huge,
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
	local h = rink.hands
	h[1], h[2], h[3], h[4] = ax, ay, bx, by
	rink.stale = 0
end

-- Every arm at a table let go: the Animator has the joints again.
local function letGo(rink: Rink)
	for side, arm in rink.arms do
		Reach.rest(arm)
		rink.arms[side] = nil
	end
end

-- Who stands at each end a person plays: of the bodies inside that end's standing room, the nearest to its
-- stance that has an arm to reach with (a squirrel on the mat has none). The body already reaching is kept
-- unless someone with an arm stands nearer.
local function look(rink: Rink, place: any)
	local folder = workspace:FindFirstChild("Bodies")
	for side = 0, 1 do
		local found: { { body: any, d: number } } = {}
		if folder ~= nil and side ~= rink.own and (rink.mode == "2" or rink.mode == tostring(side)) then
			local sx, sy = Layout.fromLocal(Layout.stance(side))
			local wx, _, wz = Layout.toWorld(place, sx, sy)
			for _, body in folder:GetChildren() do
				local root: any = if body:IsA("Model") then (body :: any).PrimaryPart else nil
				if root ~= nil then
					local p = root.Position
					if Layout.standingAt(place, p.X, p.Z) == side then
						table.insert(found, { body = body, d = (p.X - wx) ^ 2 + (p.Z - wz) ^ 2 })
					end
				end
			end
			table.sort(found, function(a, b)
				return a.d < b.d
			end)
		end
		local held = rink.arms[side]
		local arm: Reach.Arm? = nil
		for _, f in found do
			if held ~= nil and held.body == f.body then
				arm = held
			else
				arm = Reach.arm(f.body)
			end
			if arm ~= nil then
				break
			end
		end
		if held ~= nil and held ~= arm then
			Reach.rest(held)
		end
		rink.arms[side] = arm :: any
	end
end

-- The Stepped step (after the Animator has written the joints): every arm aimed at its mallet as last shown.
function Rink.reach()
	local now = os.clock()
	for _, rink in rinks do
		local place = rink.place
		rink.stale += 1
		if place == nil or rink.stale > 3 or not (rink.seated or rink.watching) then
			-- (nothing has been drawn at this table for a few frames)
			letGo(rink)
			continue
		end
		if now - rink.lookedAt >= Rink.LOOK or now < rink.lookedAt then
			rink.lookedAt = now
			look(rink, place)
		end
		local h = rink.hands
		for side, arm in rink.arms do
			if arm.body.Parent == nil then
				rink.arms[side] = nil
			else
				local wx, wy, wz = Layout.toWorld(place, h[side * 2 + 1], h[side * 2 + 2], Layout.GRIP_Z)
				Reach.pose(arm, Vector3.new(wx, wy, wz))
			end
		end
	end
end

-- The reach step runs only while a table is being drawn on this screen.
local function settle()
	local busy = false
	for _, rink in rinks do
		if rink.seated or rink.watching then
			busy = true
		else
			letGo(rink)
		end
	end
	if busy and stepped == nil then
		local signal = (game:GetService("RunService") :: any).Stepped
		if signal ~= nil then
			stepped = signal:Connect(function()
				Rink.reach()
			end)
		end
	elseif not busy and stepped ~= nil then
		stepped:Disconnect()
		stepped = nil
	end
end

-- The seated controller's word, each frame: which ends people play, and which is the local player's.
function Rink.playing(rink: Rink, mode: string, own: number?)
	rink.mode = mode
	rink.own = own
end

-- The sound of one contact: what the puck met (Sim.HIT_*) and how hard (metres a second along the normal).
function Rink.contact(what: number, speed: number)
	local volume = math.clamp(0.25 + speed / Sim.MAX_SPEED * 0.75, 0, 1)
	if what >= Sim.HIT_MALLET then
		MinigameSounds.play("air_hockey.strike", volume)
	elseif what == Sim.HIT_POST then
		MinigameSounds.play("air_hockey.post", volume)
	else
		MinigameSounds.play("air_hockey.rail", volume)
	end
end

-- The sound of one tick: what the puck met and how hard, a serve, a goal. `mine` is the end the listener plays
-- (nil for a bystander).
function Rink.cue(sim: any, hit: boolean, goal: boolean, served: boolean, mine: number?)
	if hit then
		Rink.contact(sim.hitWhat, sim.hitSpeed)
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
			settle()
			continue
		end
		any = true
		rink.mode, rink.own = r.mode, nil
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
		Replica.step(r, whole + 1, function(sim: any, _tick: number, hit: boolean, goal: boolean, served: boolean)
			keep(rink, sim)
			Rink.cue(sim, hit, goal, served, nil)
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
	settle()
	if not bound then
		bound = true
		game:GetService("RunService"):BindToRenderStep(Rink.BIND, Enum.RenderPriority.Last.Value, frame)
	end
end

-- The local player's controller draws this table from now on (their own prediction)...
function Rink.take(rink: Rink)
	rink.seated = true
	letGo(rink)
	rink.lookedAt = -math.huge
	settle()
end

-- ...and hands it back: the next stream message starts a bystander's view afresh.
function Rink.give(rink: Rink)
	rink.seated = false
	rink.own = nil
	rink.replica = Replica.new()
	settle()
end

-- The server's word that the table is at rest: the pieces go home on this screen too (it moved them itself, so
-- the server's own move of them would not show), and nothing is drawn until the next match.
function Rink.rest(rink: Rink)
	rink.replica = Replica.new()
	rink.watching = false
	settle()
	if not rink.seated then
		local hp, hm = Layout.HOME_PUCK, Layout.HOME_MALLET
		Rink.show(rink, hp[1], hp[2], hm[0][1], hm[0][2], hm[1][1], hm[1][2])
	end
end

-- Every table forgotten and the render step let go (the specs start each case from nothing).
function Rink.reset()
	for _, rink in rinks do
		letGo(rink)
	end
	table.clear(rinks)
	settle()
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
