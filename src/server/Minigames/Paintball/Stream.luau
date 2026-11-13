--!strict
-- ServerScriptService.Server.Minigames.Paintball.Stream
-- What the paintball service keeps for one PERSON in a match, and the judgment of everything that
-- person's client claims (checklist PB-3, PB-9; Shared/Minigames/Paintball/Contract, "who is trusted
-- for what"; PaintballService, "the remotes"). Pure: no Instances, no remotes, no match model. The
-- service owns the seat, the team and the body; this module owns the stream.
--   a Move    judge(): dropped (an old placement number, an out slot, a bad or old stamp), refused with
--             a Contract.WHY code (inside, height, walls, distance, the body: the first failure wins)
--             or accepted, in which case it becomes the anchor and joins the last Clock.MOVES_KEPT
--   a click   sprinting() and originOk(): the two of the service's checks that read the Move buffer
--   a pose    poseAt(): "the slot's pose at t", the straight line between the two Moves either side
--             of t, held at the newest and at the oldest, the anchor when there are none
-- THE HEIGHT RULE is one function, supportedOrFalling(). As the contract words it: an unsupported pose
-- is accepted while it is no more than TRUST.riseSlack above the last accepted pose and the body has
-- been unsupported no longer than TRUST.fallSecs by the Moves' own t. Two things the contract does not
-- say are added, one for the honest and one against a liar:
--   A BODY HAS A FOOTPRINT. Arena.ground is asked about a point, and a body standing at the very edge
--   of a floor or a landing (to look down the atrium, which everybody does) has its feet point past
--   the edge while its feet are still on it. A pose is supported if the surface under it, OR under a
--   point FOOT to any of its four sides, is. Without this an honest player at an edge is refused after
--   fallSecs for as long as they stand there.
--   A FALL MUST FALL. An unsupported body that is not coming down is flying: after `tau` seconds
--   unsupported it must be at least FALL_FLOOR x tau^2 - FALL_SLACK below where the fall began (a
--   quarter of the engine's gravity: a real fall is four times that). Without this a pose could be
--   walked level out over the atrium for the whole of fallSecs: 25 studs at a walk, the atrium's 30 at
--   a sprint.
-- THE BODY RULE (Contract, "the body": a pose within TRUST.bodySlack of the replicated body) is kept
-- sideways always and up-and-down only for a body that stands: the replicated body trails its own
-- client's Moves by the engine's physics replication, and a body dropping down the atrium at 100 studs
-- a second is more than bodySlack behind its Move within a tenth of a second. While a pose is falling,
-- and for LANDING seconds after, the height rule alone judges how high it is.
-- A CLICK THAT CAME LATE (clickOk). The contract judges a click at f, the fire time held to the
-- shooter's own delay. A click behind a lost packet arrives later than that delay explains: f is then
-- later than the click, the body has walked on, and a strafing shooter's honest shot would be refused
-- ("origin"; "sprint" if they ran on after it). Such a click is ALSO judged at its own stamp, no
-- further back than Clock.MAG_LATE (the bound the contract gives the magazine for the same reason):
-- the sprint window, the spawn rooms, the eye and the stance, all at that one time, from the Moves and
-- the crouch the server itself held then. What a liar gains: a shot from where and how they really
-- stood up to MAG_LATE ago, born no earlier than f. (Reported.)
-- Interface: new(player, now, placeFrom?) -> Person; restart(person, now); placed(person, x, y, z, yaw,
--   now, feel, stand); judge(person, rec, now, arena, feel, otherRoom?, bx?, by?, bz?) -> (verdict,
--   why?); refused(person, now) -> correct; poseAt(person, t) -> (x, y, z, yaw, pitch, bits,
--   newestT); ease(person, tick, feel) -> crouch; crouchAt(person, t) -> crouch; sprinting(person, f)
--   -> boolean; originOk(person, f, ox, oy, oz, sweep, feel, now?) -> boolean; clickOk(person, at, ox,
--   oy, oz, arena, feel, now?) -> why?; silent(person, now) -> (stale, drop); types Move, Person, Verdict

local Import = require("../../Import")
local ArenaModule: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Arena)) =
	Import.shared("Minigames/Paintball/Arena")
local Body: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Body)) =
	Import.shared("Minigames/Paintball/Body")
local Clock: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Clock)) =
	Import.shared("Minigames/Paintball/Clock")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local Wire: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Wire)) =
	Import.shared("Minigames/Paintball/Wire")

type Arena = typeof(ArenaModule.T.Arena)
type Room = typeof(ArenaModule.T.Room)
type Feel = typeof(Contract.T.Feel)
type View = typeof(Clock.newView())
type Sweep = (
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number
) -> (number?, number, number, number, number)

-- An accepted pose, as the client sampled it (arena frame; t on the shared clock).
export type Move = { t: number, x: number, y: number, z: number, yaw: number, pitch: number, bits: number }

export type Person = {
	player: any,
	seat: number, -- the slot it holds (the service keeps this right: seats are dealt again at every match)
	place: number, -- the placement number (Wire.nextPlace); 0 until the server first places the body
	placeFrom: number, -- the number the next placement counts on from (it outlives a re-seating)
	placedAt: number, -- when the server last moved the body
	moves: { Move }, -- the last Clock.MOVES_KEPT accepted Moves, oldest first; emptied by every placement
	anchor: Move, -- the last accepted pose (after a placement: the pose the server placed)
	up: View, -- the smoothed delay between a Move's t and its arrival
	budget: number, -- horizontal studs it may still move
	crouch: number, -- the crouch fraction, eased by the service once a snapshot tick
	lastT: number, -- the t of the last accepted Move
	lastM: number?, -- the magazine time of its last accepted shot
	shot: number, -- the counter of its last judged click
	heardAt: number, -- when a Move last got as far as being judged
	out: boolean, -- tagged out: Moves are dropped and the pose is held until the respawn
	fallSince: number?, -- the t of the first unsupported Move of the fall it is in
	fallFromY: number, -- and that Move's height
	fellAt: number, -- the t of the last accepted Move that was falling
	crouchLog: { number }, -- (tick, crouch fraction) pairs of the last CROUCH_KEPT snapshot ticks, oldest first
	refusals: { number }, -- when its recent Moves were refused (inside TRUST.refusalWindow)
	idleAt: number, -- when it last moved, turned or fired
	idleX: number,
	idleY: number,
	idleZ: number,
	idleYaw: number,
	idlePitch: number,
}

export type Verdict = "dropped" | "refused" | "accepted"

local T = Contract.TRUST
local BIT = Wire.BIT
local IDLE_STUDS = 0.5
local IDLE_RAD = 0.05
local FOOT = 1.0 -- studs a feet point may be past an edge its body still stands on
local FALL_FLOOR = 0.25 * 196.2 / 2 -- studs of drop per second squared a fall must at least show
local FALL_SLACK = 0.5
local LANDING = 0.25 -- seconds after a fall in which the replicated body may still be coming down
local CROUCH_KEPT = 14 -- snapshot ticks of crouch kept (0.7 s: past Clock.MAG_LATE and a tick each side)

local Stream = {}

local function fullBudget(crouch: number, feel: Feel): number
	return Body.speed(crouch, false, feel) * T.speedTolerance * T.speedWindow
end

-- A person newly seated. `placeFrom` is the last placement number this player was ever given (so a
-- Move from an earlier seating can never carry the number of a new placement).
function Stream.new(player: any, now: number, placeFrom: number?): Person
	return {
		player = player,
		seat = 0,
		place = 0,
		placeFrom = placeFrom or 0,
		placedAt = -math.huge,
		moves = {},
		anchor = { t = -math.huge, x = 0, y = 0, z = 0, yaw = 0, pitch = 0, bits = 0 },
		up = Clock.newView(),
		budget = 0,
		crouch = 0,
		lastT = -math.huge,
		lastM = nil,
		shot = 0,
		heardAt = now,
		out = false,
		fallSince = nil,
		fallFromY = 0,
		fellAt = -math.huge,
		crouchLog = {},
		refusals = {},
		idleAt = now,
		idleX = 0,
		idleY = 0,
		idleZ = 0,
		idleYaw = 0,
		idlePitch = 0,
	}
end

-- A new match: the placement number, the upstream delay, the magazine time and the shot counter carry
-- on; the rest starts afresh (the first placement of the match follows at once).
function Stream.restart(person: Person, now: number)
	table.clear(person.moves)
	person.budget = 0
	person.crouch = 0
	person.heardAt = now
	person.out = false
	person.fallSince = nil
	person.fellAt = -math.huge
	table.clear(person.crouchLog)
	table.clear(person.refusals)
	person.idleAt = now
end

-- The server put the body at this pose (a respawn, a correction): a new placement number, the pose is
-- the anchor, the Move buffer is empty. `stand` (a respawn) also stands the body up and fills the budget.
function Stream.placed(
	person: Person,
	x: number,
	y: number,
	z: number,
	yaw: number,
	now: number,
	feel: Feel,
	stand: boolean
)
	local place = Wire.nextPlace(math.max(person.place, person.placeFrom))
	person.place = place
	person.placeFrom = place
	person.placedAt = now
	-- (silence is measured from here: a client that was tagged out has sent nothing since the tag, and
	-- is owed the whole of Clock.DROP_SECS to be heard from again, not what the respawn left of it)
	person.heardAt = now
	table.clear(person.moves)
	local bits = if stand then 0 else bit32.band(person.anchor.bits, BIT.crouch)
	-- (its t is the placement's own time: a shot fired before any Move has come is costed from here)
	person.anchor = { t = now, x = x, y = y, z = z, yaw = yaw, pitch = 0, bits = bits }
	if stand then
		person.crouch = 0
		table.clear(person.crouchLog)
		person.out = false
		-- (a placement is the server's doing: it does not restart the idle clock, but the pose idleness is
		-- measured against is the one the body now stands at)
		person.idleX, person.idleY, person.idleZ, person.idleYaw, person.idlePitch = x, y, z, yaw, 0
	end
	-- A respawn starts with the budget full. A CORRECTION starts with it empty: a client that is refused
	-- and put back would otherwise be handed half a second of free distance every time, and one that
	-- wanted to be refused could outrun a sprint on corrections alone. An honest client loses nothing:
	-- its first Move after the correction fills the budget with that Move's own time.
	person.budget = if stand then fullBudget(person.crouch, feel) else 0
	person.fallSince = nil
	person.fellAt = -math.huge
	table.clear(person.refusals)
end

-- THE HEIGHT RULE (Contract, "height"). Returns ok, and whether the pose is unsupported (falling).
local function supportedOrFalling(
	person: Person,
	arena: Arena,
	t: number,
	x: number,
	y: number,
	z: number
): (boolean, boolean)
	local ground = arena.ground(x, y, z)
	if ground == nil or y < ground - T.groundSlack then
		return false, false
	end
	local reach = Body.JUMP_HEIGHT + T.jumpSlack
	if y <= ground + reach then
		return true, false
	end
	-- a body has a footprint: at the very edge of a floor the feet point is past it
	for i = 1, 4 do
		local dx = if i == 1 then FOOT elseif i == 2 then -FOOT else 0
		local dz = if i == 3 then FOOT elseif i == 4 then -FOOT else 0
		local side = arena.ground(x + dx, y, z + dz)
		if side ~= nil and y >= side - T.groundSlack and y <= side + reach then
			return true, false
		end
	end
	-- not supported: a fall. It may not rise, it may not last, and it must come down
	if y > person.anchor.y + T.riseSlack then
		return false, true
	end
	local since = person.fallSince
	if since ~= nil then
		local tau = t - since
		if tau > T.fallSecs or y > person.fallFromY - (FALL_FLOOR * tau * tau - FALL_SLACK) then
			return false, true
		end
	end
	return true, true
end

-- Judge one Move record (Wire.Move, already decoded and checked finite by Shared/Net). `otherRoom` is
-- the other team's spawn room; (bx, by, bz) the replicated body's real feet point in the arena frame,
-- when the engine knows it. Returns the verdict and, for a refusal, the Contract.WHY code. An accepted
-- Move is taken in here; a refused one is to be handed to refused() by the caller.
function Stream.judge(
	person: Person,
	rec: { [string]: number },
	now: number,
	arena: Arena,
	feel: Feel,
	otherRoom: Room?,
	bx: number?,
	by: number?,
	bz: number?
): (Verdict, string?)
	-- b. not placed yet, tagged out, or sampled before the client knew of its last placement
	if person.place == 0 or person.out or rec.place ~= person.place then
		return "dropped", nil
	end
	-- c. the stream is unreliable and unordered: only a newer stamp, and a believable one
	local t = rec.t
	if t <= person.lastT or t > now + T.clockSlack or t < now - T.moveAge then
		return "dropped", nil
	end
	-- d. it is judged: the upstream delay and the silence are measured from here
	Clock.observe(person.up, t, now)
	person.heardAt = now
	local a = person.anchor
	local x, y, z = rec.x, rec.y, rec.z
	local half = ArenaModule.HALF
	-- e. inside
	if x < -half or x > half or z < -half or z > half or y < -T.groundSlack or y > ArenaModule.HEIGHT then
		return "refused", "wall"
	end
	local chest = y + ArenaModule.CHEST
	if arena.sweep(x, chest, z, x, chest + 0.01, z) ~= nil then
		return "refused", "wall"
	end
	if otherRoom ~= nil and ArenaModule.inRoom(otherRoom, x, y + 0.1, z) then
		return "refused", "wall"
	end
	-- height
	local ok, falling = supportedOrFalling(person, arena, t, x, y, z)
	if not ok then
		return "refused", "wall"
	end
	-- walls
	if not ArenaModule.clearPath(arena.sweep, a.x, a.z, x, z, math.max(a.y, y) + ArenaModule.CHEST) then
		return "refused", "wall"
	end
	-- distance: the budget fills from the Moves' own t, never from arrival
	local gap = math.min(t - person.lastT, T.moveGap)
	local rate = Body.speed(person.crouch, Wire.has(rec.bits, BIT.sprint), feel) * T.speedTolerance
	local budget = math.min(person.budget + rate * gap, rate * T.speedWindow)
	local dx, dz = x - a.x, z - a.z
	local step = math.sqrt(dx * dx + dz * dz)
	if step > budget then
		return "refused", "speed"
	end
	-- the body (sideways always; up and down only for a body that stands: see the header)
	if bx ~= nil and by ~= nil and bz ~= nil then
		local ex, ey, ez = x - bx, y - by, z - bz
		if falling or t - person.fellAt <= LANDING then
			ey = 0
		end
		if ex * ex + ey * ey + ez * ez > T.bodySlack * T.bodySlack then
			return "refused", "wall"
		end
	end
	-- f. accepted
	local move: Move = { t = t, x = x, y = y, z = z, yaw = rec.yaw, pitch = rec.pitch, bits = rec.bits }
	local moves = person.moves
	if #moves >= Clock.MOVES_KEPT then
		table.remove(moves, 1)
	end
	table.insert(moves, move)
	person.anchor = move
	person.lastT = t
	person.budget = budget - step
	if falling then
		if person.fallSince == nil then
			person.fallSince = t
			person.fallFromY = y
		end
		person.fellAt = t
	else
		person.fallSince = nil
	end
	local ix, iy, iz = x - person.idleX, y - person.idleY, z - person.idleZ
	if
		ix * ix + iy * iy + iz * iz > IDLE_STUDS * IDLE_STUDS
		or math.abs(rec.yaw - person.idleYaw) > IDLE_RAD
		or math.abs(rec.pitch - person.idlePitch) > IDLE_RAD
	then
		person.idleAt = now
		person.idleX, person.idleY, person.idleZ = x, y, z
		person.idleYaw, person.idlePitch = rec.yaw, rec.pitch
	end
	return "accepted", nil
end

-- A Move was refused. True when it is the TRUST.refusalsBeforeCorrect-th inside TRUST.refusalWindow:
-- the service then puts the body back on the anchor (placed()).
function Stream.refused(person: Person, now: number): boolean
	local list = person.refusals
	while list[1] ~= nil and now - list[1] > T.refusalWindow do
		table.remove(list, 1)
	end
	table.insert(list, now)
	return #list >= T.refusalsBeforeCorrect
end

-- "The slot's pose at t": position on the straight line between the two Moves either side of t, held
-- at the newest and at the oldest; yaw, pitch and bits of the newer of the two; the anchor when the
-- buffer is empty. The last value is the newest Move's t (the anchor's when there is none).
function Stream.poseAt(person: Person, t: number): (number, number, number, number, number, number, number)
	local moves = person.moves
	local n = #moves
	if n == 0 then
		local a = person.anchor
		return a.x, a.y, a.z, a.yaw, a.pitch, a.bits, a.t
	end
	local newest = moves[n]
	if t >= newest.t then
		return newest.x, newest.y, newest.z, newest.yaw, newest.pitch, newest.bits, newest.t
	end
	for i = n - 1, 1, -1 do
		local older = moves[i]
		if t >= older.t then
			local newer = moves[i + 1]
			local f = (t - older.t) / (newer.t - older.t)
			return older.x + (newer.x - older.x) * f,
				older.y + (newer.y - older.y) * f,
				older.z + (newer.z - older.z) * f,
				newer.yaw,
				newer.pitch,
				newer.bits,
				newest.t
		end
	end
	local oldest = moves[1]
	return oldest.x, oldest.y, oldest.z, oldest.yaw, oldest.pitch, oldest.bits, newest.t
end

-- The snapshot tick `tick`: the crouch fraction takes one step towards what the newest Move's crouch bit
-- asks for (Body.crouchStep over one snapshot interval), and the step is logged.
function Stream.ease(person: Person, tick: number, feel: Feel): number
	local moves = person.moves
	local newest = if #moves > 0 then moves[#moves].bits else person.anchor.bits
	local c = Body.crouchStep(person.crouch, Wire.has(newest, BIT.crouch), 1 / Clock.SNAP_HZ, feel)
	person.crouch = c
	local log = person.crouchLog
	if #log >= 2 * CROUCH_KEPT then
		table.remove(log, 1)
		table.remove(log, 1)
	end
	table.insert(log, tick)
	table.insert(log, c)
	return c
end

-- The crouch fraction the server held at time t: that of the newest logged tick at or before t, the
-- oldest logged when t is before them all, the present one when nothing is logged.
function Stream.crouchAt(person: Person, t: number): number
	local log = person.crouchLog
	local n = #log
	if n == 0 then
		return person.crouch
	end
	for i = n - 1, 1, -2 do
		if log[i] <= t then
			return log[i + 1]
		end
	end
	return log[2]
end

-- Was the marker down at fire time f? A Move stamped inside (f - SPRINT_FIRE_DELAY + MARGIN.sprint, f]
-- carries BIT.sprint. (A Move stamped after f says nothing of the click: sprint may begin again the
-- frame after the ball has left, and an unreliable Move may overtake the reliable click.)
function Stream.sprinting(person: Person, f: number): boolean
	local after = f - Body.SPRINT_FIRE_DELAY + Contract.MARGIN.sprint
	for _, move in person.moves do
		if move.t > after and move.t <= f and Wire.has(move.bits, BIT.sprint) then
			return true
		end
	end
	return false
end

-- Did a shot leave from this person's own eye at fire time f (Contract, "the origin")?
-- With `now` (a click judged at its own stamp, earlier than the contract's f: clickOk) the stance is
-- the one the server held when the Moves of that time were arriving: the crouch logged at f + the
-- upstream delay, and where the crouch bit of the Move at f was heading.
function Stream.originOk(
	person: Person,
	f: number,
	ox: number,
	oy: number,
	oz: number,
	sweep: Sweep,
	feel: Feel,
	now: number?
): boolean
	local x, y, z, _, _, bitsAt, newestT = Stream.poseAt(person, f)
	local newestBits = if #person.moves > 0 then person.moves[#person.moves].bits else person.anchor.bits
	local crouch = person.crouch
	if now ~= nil then
		crouch = Stream.crouchAt(person, math.min(now, f + (person.up.lag or 0)))
		newestBits = bitsAt
	end
	local past = math.max(0, f - newestT)
	local reach = T.originSlack + Body.speed(crouch, false, feel) * past
	local dx, dz = ox - x, oz - z
	if dx * dx + dz * dz > reach * reach then
		return false
	end
	local eyeA = Body.eye(crouch)
	local eyeB = Body.eye(if Wire.has(newestBits, BIT.crouch) then 1 else 0)
	local slack = T.originSlackY + (if Wire.has(newestBits, BIT.air) then Body.JUMP_HEIGHT else 0)
	if oy < y + math.min(eyeA, eyeB) - slack or oy > y + math.max(eyeA, eyeB) + slack then
		return false
	end
	return ArenaModule.clearPath(sweep, x, z, ox, oz, oy)
end

-- The three things a click is judged on from the shooter's own stream, all at one time `at`
-- (PaintballService.onFire c, d, e): the sprint window, the spawn rooms, the origin. Returns the
-- Contract.WHY code of the first that refuses it, or nil. `now` is given when `at` is the click's own
-- stamp and not the contract's f (see the header, "a click that came late").
function Stream.clickOk(
	person: Person,
	at: number,
	ox: number,
	oy: number,
	oz: number,
	arena: Arena,
	feel: Feel,
	now: number?
): string?
	if Stream.sprinting(person, at) then
		return "sprint"
	end
	local x, y, z = Stream.poseAt(person, at)
	local rooms = arena.spawnRooms
	if ArenaModule.inRoom(rooms[1], x, y + 0.1, z) or ArenaModule.inRoom(rooms[2], x, y + 0.1, z) then
		return "safe"
	end
	if not Stream.originOk(person, at, ox, oy, oz, arena.sweep, feel, now) then
		return "origin"
	end
	return nil
end

-- Silence (Clock, "silence"): not measured while out, before the first placement, or within
-- TRUST.placeGrace of a placement. Returns (may not fire, is to be taken off).
function Stream.silent(person: Person, now: number): (boolean, boolean)
	if person.place == 0 then
		return true, false
	end
	if person.out or now - person.placedAt <= T.placeGrace then
		return false, false
	end
	local quiet = now - person.heardAt
	return quiet > Clock.STALE_SECS, quiet > Clock.DROP_SECS
end

return Stream
