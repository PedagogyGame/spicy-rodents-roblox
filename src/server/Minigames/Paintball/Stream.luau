--!strict
-- ServerScriptService.Server.Minigames.Paintball.Stream
-- What the paintball service keeps for one PERSON in a match, and the judgment of everything that
-- person's client claims (checklist PB-3, PB-9; Shared/Minigames/Paintball/Contract, "who is trusted
-- for what"; PaintballService, "the remotes"). Pure: no Instances, no remotes, no match model. The
-- service owns the seat, the team and the body; this module owns the stream.
--   a Move    judge(): dropped (an old placement number, an out slot, a bad or old stamp), refused with
--             a Contract.WHY code (inside, height, walls, distance, the body: the first failure wins)
--             or accepted, in which case it becomes the anchor and joins the last Clock.MOVES_KEPT
--   a click   clickOk(): the three of the service's checks that read the Move buffer (the sprint
--             window, the spawn rooms, the origin), all at one time
--   a pose    poseAt(): "the slot's pose at t", the straight line between the two Moves either side
--             of t, held at the newest and at the oldest, the anchor when there are none
-- THE HEIGHT RULE is one function, supportedOrFalling(). The contract words it: a pose no higher than
-- the walking surface under it + Body.JUMP_HEIGHT + TRUST.jumpSlack is SUPPORTED; an unsupported pose
-- is accepted while it does not rise (TRUST.riseSlack above the last accepted pose) and has not been
-- unsupported, by the Moves' own t, for longer than TRUST.fallSecs. Here supported is as written, with
-- one thing added, and unsupported is ONE ENVELOPE in the place of the two clauses:
--   A BODY HAS A FOOTPRINT. Arena.ground is asked about a point, and a body standing at the very edge
--   of a floor or a landing (to look down the atrium, which everybody does) has its feet point past
--   the edge while its feet are still on it. A pose is supported if the surface under it, OR under a
--   point FOOT to any of its four sides, is. Without this an honest player at an edge is refused after
--   fallSecs for as long as they stand there.
--   A FALL IS A HOP AT THE MOST, AND IT MUST FALL. `standY` is the walking surface the body last stood
--   on (within TRUST.groundSlack of it: a body in the air keeps the one it took off from, so a hop
--   taken running down a stair is a hop from the step it left). An unsupported pose, `tau` seconds
--   after the first unsupported Move of its fall, may be no higher than standY + JUMP_HEIGHT +
--   jumpSlack - FALL_FLOOR x tau^2 (a quarter of the engine's gravity: a real fall is four times
--   that), and tau may be no more than fallSecs. So a body may step off an
--   edge and drop, and may RUN AND JUMP off it (the whole arc of a hop from the edge lies under the
--   envelope, with a third of a stud to spare); it may not go higher than a hop, stay level for more
--   than a third of a second, or glide. As written, the hop is refused (its Moves rise, with nothing
--   under them, above the last accepted pose: every running jump off a balcony was three refusals and
--   a yank back to the edge), and a pose may be walked level out over the atrium for the whole of
--   fallSecs (25 studs at a walk, the atrium's 30 at a sprint). (Both reported.)
-- THE BODY RULE (Contract, "the body": a pose within TRUST.bodySlack of the replicated body) is kept
-- sideways always and up-and-down only for a body that stands: the replicated body trails its own
-- client's Moves by the engine's physics replication, and a body dropping down the atrium at 100 studs
-- a second is more than bodySlack behind its Move within a tenth of a second. While a pose is falling,
-- and for LANDING seconds after, the height rule alone judges how high it is.
-- AND NOT AT ALL FOR TRUST.placeGrace AFTER A PLACEMENT. The server has just moved the body (a respawn, a
-- correction), and the body is its player's to simulate: what the server reads of it for the next
-- moments may still be what that client sent before it heard (the contract gives the framework's
-- walk-away check, which reads the same body, the same second for the same reason). A Move with the new
-- placement number was sampled by a client that has heard, at the new place; held to a body the server
-- still reads at the old one it is refused, three of them are a correction, a correction is a
-- placement, and the player is put back again and again for nothing they did. For that second the pose
-- is held to everything else (walls, height, the distance budget from the place the server chose),
-- which is what holds a liar at any time: the body rule adds nothing against one (nobody is shown the
-- body). NOT SEEN ON A REAL SERVER: the fake engine's body is where it is put. (Reported.)
-- A CLICK THAT CAME LATE (lateClickOk). The contract judges a click at f, the fire time held to the
-- shooter's own delay. A click behind a lost packet arrives later than that delay explains: f is then
-- later than the click, the body has walked on, and a strafing shooter's honest shot would be refused
-- ("origin"). A click that fails at f is ALSO judged at its own stamp, but its stamp is believed only
-- for WHERE the shot left from: no further back than lateWindow (the shooter's own delay, a resend's
-- round trip and a floor, at most Clock.MAG_LATE), and WHETHER it could fire is held to f as well (no
-- sprint Move from the click to f, in no spawn room at the click or at f, and the origin's height fits
-- the stance the server holds at f). What a liar gains: a shot from where they really stood up to
-- lateWindow ago, in the stance they still hold, born no earlier than f; a sprinter, a shooter back in
-- its room and a crouched body behind a rail gain nothing. (Reported; found in review: as first built
-- the stamp chose the time of every check, and a back-dated click fired from safety, while sprinting
-- and over a rail from a crouch.)
-- THE CROUCH IS READ FROM THE MOVES' OWN TIMES (settled at the review, 2026-11-13). Every accepted Move
-- carries the crouch fraction at its own t (`c`), eased along the crouch bits by the Moves' stamps: from
-- one Move to the next the fraction goes on towards what the older one asked for, and towards what the
-- newer one asks for from one send interval before the newer one at the most (a change of stance is
-- told at once by an honest client: SeatCore, "the origin"). crouchAt(t) reads that line at any moment,
-- held to the newest bit past the newest Move. The pose history takes its crouch from this line at the
-- very time it takes the feet (Clock.poseTime), and a shot's height is judged against the same line
-- (heightOk), so the shape others shoot at and the eye a ball may leave from are one stance. As first
-- built the fraction was eased once a snapshot tick from whatever bit the newest Move carried, and a
-- shot was allowed the eye of "where that bit is heading": one Move standing between two crouched ones,
-- arriving between two ticks, bought a standing-eye shot over a rail while the shape never rose (found
-- at the review, with the false BIT.air below).
-- THE AIR BIT BUYS HEIGHT ONLY IN THE AIR: a shot's allowance for a hop is given only when the pose at its
-- time is really above the walking surface under it, and never higher than a hop from the surface last
-- stood on. (As first built the bit alone bought it: a crouched body on the floor behind a rail claimed
-- "in the air" and fired from the standing eye.)
-- SILENCE BUYS NO REACH: the walking pace a shot's origin is allowed past the newest Move counts for at
-- most TRUST.moveGap of it (a lost Move or two). As first built half a second of withheld Moves let a
-- body fire from 8 studs out in the open while its puppet and its history stood behind a wall.
-- THE AIM IS THE LOOK (aimOk): a click's direction is held to within TRUST.aimSlack of the look of the
-- click's own Move (stamped with it, sent first) when that has been heard; when it has not, the service turns
-- the shooter's puppet to the shot for a moment, so the ball is seen to leave along the look everyone is
-- shown. As first built a ball could leave at any angle to it, unseen ("silent aim").
-- Interface: new(player, now, placeFrom?) -> Person; restart(person, now); placed(person, x, y, z, yaw,
--   now, feel, stand); judge(person, rec, now, arena, feel, otherRoom?, bx?, by?, bz?) -> (verdict,
--   why?, rule?); RULES; refused(person, now) -> correct; poseAt(person, t) -> (x, y, z, yaw, pitch, bits,
--   newestT); ease(person, t, feel) -> crouch; crouchAt(person, t, feel?) -> crouch; crouchRange(person,
--   t, feel?) -> (least, most); sprinting(person, f) -> boolean; originOk(person, f, ox, oy, oz, sweep,
--   feel, ground?) -> boolean; aimOk(person, f, dx, dy, dz) -> boolean; clickOk(person, f, ox, oy, oz,
--   arena, feel) -> why?; lateWindow(person, rtt?) -> seconds; lateClickOk(person, click, f, ox, oy, oz,
--   arena, feel, now) -> why?; silent(person, now) -> (stale, drop); types Move, Person, Verdict

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
type Ground = (x: number, y: number, z: number) -> number?
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
-- `c` is the crouch fraction at t (see "the crouch is read from the Moves' own times"); `pt`, `pc` and `pb`
-- are the t, crouch fraction and bits of the pose before it (the Move or placement it was judged from), so
-- the line before the oldest Move kept can still be read.
export type Move = {
	t: number,
	x: number,
	y: number,
	z: number,
	yaw: number,
	pitch: number,
	bits: number,
	c: number,
	pt: number,
	pc: number,
	pb: number,
}

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
	crouch: number, -- the crouch fraction the newest snapshot was given (ease)
	lastT: number, -- the t of the last accepted Move
	lastM: number?, -- the magazine time of its last accepted shot
	lastF: number?, -- the fire time (the birth) of its last accepted shot
	shotLook: { t: number, yaw: number, pitch: number }?, -- its last accepted shot: when, and the way it went
	shot: number, -- the counter of its last judged click
	heardAt: number, -- when a Move last got as far as being judged
	out: boolean, -- tagged out: Moves are dropped and the pose is held until the respawn
	-- when its side was changed under it (the "side" verb) while it was in play: the match owes it a
	-- placement in its new side's room, and until that comes (for TRUST.placeGrace at the most) its Moves
	-- are dropped: they are from the room that has just become the other side's
	owedSince: number?,
	fallSince: number?, -- the t of the first unsupported Move of the fall it is in
	standY: number, -- the walking surface the body last stood on (the one a hop or a fall began from)
	fellAt: number, -- the t of the last accepted Move that was falling
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
-- PROVISIONAL (FOOT, FALL_FLOOR, LANDING and the body rule's placeGrace bypass): tuned against scripted bodies
-- on the fake engine, whose replicated body is wherever the client's Move says. None has met a Roblox Humanoid
-- on the stair cores, off an atrium edge or replicated with physics interpolation. tools/cloud/tasks/
-- paintball_walk.luau walks a real R15 body over the whole building and prints the refusals by rule
-- (Stats.movesRefusedBy) when server checks return; until it has run with no correction these numbers are
-- a first guess. (A server with no clients simulates the body itself, so that check holds the height rule
-- and the footprint to real physics; the body rule's replication lag needs a client, a Studio test.)
local FOOT = 1.0 -- studs a feet point may be past an edge its body still stands on
local FALL_FLOOR = 0.25 * 196.2 / 2 -- studs of drop per second squared a fall must at least show
local LANDING = 0.25 -- seconds after a fall in which the replicated body may still be coming down
local SEND = 1 / Clock.SEND_HZ -- the most before the Move that tells it a change of stance is taken to have begun
local CLICK_MOVE = 1 / 120 -- seconds: a Move this near a click's fire time is of the click's own frame
local LOST_FLOOR = 0.2 -- seconds: the least a lost reliable packet waits before it is sent again

local Stream = {}

-- The rules a Move can be refused by (judge's third result; Stats.movesRefusedBy counts by them): outside the
-- volume or inside a box, inside the other team's spawn room, the height rule, a wall between it and the
-- anchor, the distance budget, the replicated body.
Stream.RULES = table.freeze({ "inside", "room", "height", "walls", "speed", "body" })

local function fullBudget(crouch: number, feel: Feel): number
	return Body.speed(crouch, false, feel) * T.speedTolerance * T.speedWindow
end

local function wants(bits: number): boolean
	return Wire.has(bits, BIT.crouch)
end

-- The crouch fraction at time t (older.t <= t <= newerT) on the way from the Move (or placement) `older` to
-- one stamped newerT carrying `newerBits`: towards what older asked for, then, from one send interval before
-- newerT at the most, towards what the newer asks for.
local function between(
	olderT: number,
	olderC: number,
	olderBits: number,
	newerBits: number,
	newerT: number,
	t: number,
	feel: Feel?
): number
	local start = math.max(olderT, newerT - SEND)
	if t <= start then
		return Body.crouchStep(olderC, wants(olderBits), math.max(0, t - olderT), feel)
	end
	local c = Body.crouchStep(olderC, wants(olderBits), math.max(0, start - olderT), feel)
	return Body.crouchStep(c, wants(newerBits), t - start, feel)
end

local function along(older: Move, newerBits: number, newerT: number, t: number, feel: Feel?): number
	return between(older.t, older.c, older.bits, newerBits, newerT, t, feel)
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
		anchor = {
			t = -math.huge,
			x = 0,
			y = 0,
			z = 0,
			yaw = 0,
			pitch = 0,
			bits = 0,
			c = 0,
			pt = -math.huge,
			pc = 0,
			pb = 0,
		},
		up = Clock.newView(),
		budget = 0,
		crouch = 0,
		lastT = -math.huge,
		lastM = nil,
		lastF = nil,
		shotLook = nil,
		shot = 0,
		heardAt = now,
		out = false,
		owedSince = nil,
		fallSince = nil,
		standY = 0,
		fellAt = -math.huge,
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
	person.owedSince = nil
	person.fallSince = nil
	person.fellAt = -math.huge
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
	person.owedSince = nil
	-- (silence is measured from here: a client that was tagged out has sent nothing since the tag, and
	-- is owed the whole of Clock.DROP_SECS to be heard from again, not what the respawn left of it)
	person.heardAt = now
	table.clear(person.moves)
	local bits = if stand then 0 else bit32.band(person.anchor.bits, BIT.crouch)
	local c = if stand then 0 else Stream.crouchAt(person, now, feel)
	-- (its t is the placement's own time: a shot fired before any Move has come is costed from here)
	person.anchor =
		{ t = now, x = x, y = y, z = z, yaw = yaw, pitch = 0, bits = bits, c = c, pt = now, pc = c, pb = bits }
	if stand then
		person.crouch = 0
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
	person.standY = y
	person.fellAt = -math.huge
	table.clear(person.refusals)
end

-- THE HEIGHT RULE (Contract, "height"; the header says where it is not as written). Returns ok, whether
-- the pose is unsupported (falling), and for a supported pose the surface it stands on.
local function supportedOrFalling(
	person: Person,
	arena: Arena,
	t: number,
	x: number,
	y: number,
	z: number
): (boolean, boolean, number)
	local ground = arena.ground(x, y, z)
	if ground == nil or y < ground - T.groundSlack then
		return false, false, 0
	end
	local reach = Body.JUMP_HEIGHT + T.jumpSlack
	if y <= ground + reach then
		return true, false, ground
	end
	-- a body has a footprint: at the very edge of a floor the feet point is past it
	for i = 1, 4 do
		local dx = if i == 1 then FOOT elseif i == 2 then -FOOT else 0
		local dz = if i == 3 then FOOT elseif i == 4 then -FOOT else 0
		local side = arena.ground(x + dx, y, z + dz)
		if side ~= nil and y >= side - T.groundSlack and y <= side + reach then
			return true, false, side
		end
	end
	-- not supported: no higher than a hop from where it last stood, coming down, and not for long
	local since = person.fallSince
	local tau = if since ~= nil then t - since else 0
	if tau > T.fallSecs or y > person.standY + reach - FALL_FLOOR * tau * tau then
		return false, true, 0
	end
	return true, true, 0
end

-- Judge one Move record (Wire.Move, already decoded and checked finite by Shared/Net). `otherRoom` is
-- the other team's spawn room; (bx, by, bz) the replicated body's real feet point in the arena frame,
-- when the engine knows it. Returns the verdict and, for a refusal, the Contract.WHY code and the rule
-- that refused it (Stream.RULES: what Stats counts refusals by, so a real body's refusals say which rule
-- they meet). An accepted Move is taken in here; a refused one is to be handed to refused() by the caller.
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
): (Verdict, string?, string?)
	-- b. not placed yet, tagged out, or sampled before the client knew of its last placement
	if person.place == 0 or person.out or rec.place ~= person.place then
		return "dropped", nil, nil
	end
	-- (its side has just been changed and its new placement has not come yet)
	local owed = person.owedSince
	if owed ~= nil then
		if now - owed <= T.placeGrace then
			return "dropped", nil, nil
		end
		person.owedSince = nil
	end
	-- c. the stream is unreliable and unordered: only a newer stamp, and a believable one
	local t = rec.t
	if t <= person.lastT or t > now + T.clockSlack or t < now - T.moveAge then
		return "dropped", nil, nil
	end
	-- d. it is judged: the upstream delay and the silence are measured from here
	Clock.observe(person.up, t, now)
	person.heardAt = now
	local a = person.anchor
	local x, y, z = rec.x, rec.y, rec.z
	local half = ArenaModule.HALF
	-- e. inside
	if x < -half or x > half or z < -half or z > half or y < -T.groundSlack or y > ArenaModule.HEIGHT then
		return "refused", "wall", "inside"
	end
	local chest = y + ArenaModule.CHEST
	if arena.sweep(x, chest, z, x, chest + 0.01, z) ~= nil then
		return "refused", "wall", "inside"
	end
	if otherRoom ~= nil and ArenaModule.inRoom(otherRoom, x, y + 0.1, z) then
		return "refused", "wall", "room"
	end
	-- height
	local ok, falling, surface = supportedOrFalling(person, arena, t, x, y, z)
	if not ok then
		return "refused", "wall", "height"
	end
	-- walls
	if not ArenaModule.clearPath(arena.sweep, a.x, a.z, x, z, math.max(a.y, y) + ArenaModule.CHEST) then
		return "refused", "wall", "walls"
	end
	-- distance: the budget fills from the Moves' own t, never from arrival (at the pace of the more upright of
	-- the two stances, this Move's and the last one's)
	local c = along(a, rec.bits, t, t, feel)
	local gap = math.min(t - person.lastT, T.moveGap)
	local rate = Body.speed(math.min(a.c, c), Wire.has(rec.bits, BIT.sprint), feel) * T.speedTolerance
	local budget = math.min(person.budget + rate * gap, rate * T.speedWindow)
	local dx, dz = x - a.x, z - a.z
	local step = math.sqrt(dx * dx + dz * dz)
	if step > budget then
		return "refused", "speed", "speed"
	end
	-- the body (sideways always; up and down only for a body that stands; not while the server's own
	-- placement may not have reached the body it reads: see the header)
	if bx ~= nil and by ~= nil and bz ~= nil and now - person.placedAt > T.placeGrace then
		local ex, ey, ez = x - bx, y - by, z - bz
		if falling or t - person.fellAt <= LANDING then
			ey = 0
		end
		if ex * ex + ey * ey + ez * ez > T.bodySlack * T.bodySlack then
			return "refused", "wall", "body"
		end
	end
	-- f. accepted
	local move: Move = {
		t = t,
		x = x,
		y = y,
		z = z,
		yaw = rec.yaw,
		pitch = rec.pitch,
		bits = rec.bits,
		c = c,
		pt = a.t,
		pc = a.c,
		pb = a.bits,
	}
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
		end
		person.fellAt = t
	else
		person.fallSince = nil
		if y <= surface + T.groundSlack then
			person.standY = surface -- (on the ground: a body in a hop keeps the surface it took off from)
		end
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
	return "accepted", nil, nil
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

-- The crouch fraction at time t, read from the Moves' own times (the header): on the line between the two
-- accepted Moves either side of t, held to the newest Move's bit past it (and the placement's when none has
-- come), and at the oldest kept before them all.
function Stream.crouchAt(person: Person, t: number, feel: Feel?): number
	local moves = person.moves
	local n = #moves
	if n == 0 then
		local a = person.anchor
		if t <= a.t then
			return a.c
		end
		return Body.crouchStep(a.c, wants(a.bits), t - a.t, feel)
	end
	local newest = moves[n]
	if t >= newest.t then
		return Body.crouchStep(newest.c, wants(newest.bits), t - newest.t, feel)
	end
	for i = n - 1, 1, -1 do
		local older = moves[i]
		if t >= older.t then
			local newer = moves[i + 1]
			return along(older, newer.bits, newer.t, t, feel)
		end
	end
	local oldest = moves[1]
	if t <= oldest.pt then
		return oldest.pc
	end
	return between(oldest.pt, oldest.pc, oldest.pb, oldest.bits, oldest.t, t, feel)
end

-- The least and the most the crouch fraction is on that line within a send interval either side of t: the
-- stance an honest client's own eye may be in at t (its Moves are sampled up to a send interval apart).
-- The line is straight between its corners, so the ends and the corners inside are enough.
function Stream.crouchRange(person: Person, t: number, feel: Feel?): (number, number)
	local lo, hi = math.huge, -math.huge
	local function at(u: number)
		local c = Stream.crouchAt(person, u, feel)
		lo, hi = math.min(lo, c), math.max(hi, c)
	end
	at(t - SEND)
	at(t)
	at(t + SEND)
	local moves = person.moves
	for _, m in moves do
		for _, u in { m.t, math.max(m.pt, m.t - SEND) } do
			if u > t - SEND and u < t + SEND then
				at(u)
			end
		end
	end
	return lo, hi
end

-- The snapshot whose poses are read at time `t` (Clock.poseTime): the crouch fraction at that same time,
-- which is what the snapshot and the pose history are given.
function Stream.ease(person: Person, t: number, feel: Feel): number
	local c = Stream.crouchAt(person, t, feel)
	person.crouch = c
	return c
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

-- Is a ball leaving from height `oy` one this person's eye could have been at, at time t, over feet at
-- height y (the stance a send interval either side of t: crouchRange)? `air`: the pose is really off the
-- floor, so a hop's height is allowed below the eye, and above it up to a hop from where the body last stood.
local function heightOk(person: Person, t: number, y: number, oy: number, feel: Feel, air: boolean): boolean
	local least, most = Stream.crouchRange(person, t, feel)
	local below, above = T.originSlackY, T.originSlackY
	if air then
		below += Body.JUMP_HEIGHT
		above += math.clamp(person.standY + Body.JUMP_HEIGHT + T.jumpSlack - y, 0, Body.JUMP_HEIGHT)
	end
	return oy >= y + Body.eye(most) - below and oy <= y + Body.eye(least) + above
end

-- Is the pose (feet y, its bits) really in the air: the air bit, and above the walking surface under it?
local function airborne(ground: Ground?, x: number, y: number, z: number, bits: number): boolean
	if not Wire.has(bits, BIT.air) or ground == nil then
		return false
	end
	local g = ground(x, y, z)
	return g ~= nil and y > g + T.groundSlack
end

-- Did a shot leave from this person's own eye at fire time f (Contract, "the origin")? Horizontally within
-- originSlack of the pose at f, and walking pace for however far f lies past the newest Move, counted for no
-- more than TRUST.moveGap ("silence buys no reach"); at a height the stance on the line allows (heightOk;
-- the hop's allowance only when `ground` says the pose is really in the air); and with no wall between.
function Stream.originOk(
	person: Person,
	f: number,
	ox: number,
	oy: number,
	oz: number,
	sweep: Sweep,
	feel: Feel,
	ground: Ground?
): boolean
	local x, y, z, _, _, bitsAt, newestT = Stream.poseAt(person, f)
	local least = Stream.crouchRange(person, f, feel)
	local past = math.clamp(f - newestT, 0, T.moveGap)
	local reach = T.originSlack + Body.speed(least, false, feel) * past
	local dx, dz = ox - x, oz - z
	if dx * dx + dz * dz > reach * reach then
		return false
	end
	if not heightOk(person, f, y, oy, feel, airborne(ground, x, y, z, bitsAt)) then
		return false
	end
	return ArenaModule.clearPath(sweep, x, z, ox, oz, oy)
end

-- Does a click's direction (dx, dy, dz, any length) agree with the look this person's Moves showed (the
-- header, "the aim is the look")? An honest client sends a Move stamped with its click, carrying the very look
-- the ball leaves along: when that Move has been heard, the direction must be within TRUST.aimSlack of it.
-- When it has not (lost, or overtaken by the reliable click), nothing here refuses the shot: a flick between
-- two Moves of the stream cannot be told from a lie, so the service SHOWS it instead (the puppet is turned to
-- the shot: PaintballService, "the snapshot"), and a ball is never seen to leave a puppet looking elsewhere.
function Stream.aimOk(person: Person, f: number, dx: number, dy: number, dz: number): boolean
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	if len < 1e-9 then
		return false
	end
	local heard = false
	for _, m in person.moves do
		if math.abs(m.t - f) < CLICK_MOVE then
			heard = true
			local lx, ly, lz = Body.look(m.yaw, m.pitch)
			local cosine = math.clamp((lx * dx + ly * dy + lz * dz) / len, -1, 1)
			if math.acos(cosine) <= T.aimSlack then
				return true
			end
		end
	end
	-- (the click's own frame was heard and the ball does not leave along its look: refused)
	return not heard
end

local function inEitherRoom(arena: Arena, x: number, y: number, z: number): boolean
	local rooms = arena.spawnRooms
	return ArenaModule.inRoom(rooms[1], x, y + 0.1, z) or ArenaModule.inRoom(rooms[2], x, y + 0.1, z)
end

-- The three things a click is judged on from the shooter's own stream, all at the contract's fire time
-- f (PaintballService.onFire c, d, e): the sprint window, the spawn rooms, the origin. Returns the
-- Contract.WHY code of the first that refuses it, or nil.
function Stream.clickOk(
	person: Person,
	f: number,
	ox: number,
	oy: number,
	oz: number,
	arena: Arena,
	feel: Feel
): string?
	if Stream.sprinting(person, f) then
		return "sprint"
	end
	local x, y, z = Stream.poseAt(person, f)
	if inEitherRoom(arena, x, y, z) then
		return "safe"
	end
	if not Stream.originOk(person, f, ox, oy, oz, arena.sweep, feel, arena.ground) then
		return "origin"
	end
	return nil
end

-- How far before its arrival a late click may be judged at its own stamp (the header, "a click that
-- came late"): its own delay up, the round trip a lost packet waits before it is sent again (2 up), the
-- engine's floor on that wait (LOST_FLOOR) and the stamping tolerance; never more than Clock.MAG_LATE.
-- A shooter on a fast connection is held to a short window: 0.275 s at no delay, 0.395 at 80 ms. With
-- `rtt`, the round trip the server measures itself (Clock, "the round trip"), the way up is taken to be no
-- longer than that: a client that back-dates its Moves to look slow buys nothing here.
function Stream.lateWindow(person: Person, rtt: number?): number
	local up = person.up.lag or 0
	if rtt ~= nil then
		up = math.min(up, rtt)
	end
	return math.min(Clock.MAG_LATE, 3 * up + LOST_FLOOR + Clock.REWIND_TOLERANCE)
end

-- A click that failed at f, judged again at its own stamp `click` (earlier than f; the caller holds it
-- inside lateWindow). The stamp says only WHERE the shot left from; WHETHER the shooter could fire is
-- held to f as well, so a liar who back-dates a click buys an origin and nothing else:
--   sprint  refused if any Move in (click - SPRINT_FIRE_DELAY + MARGIN.sprint, f] carries BIT.sprint:
--           the marker was down at the click, or has been since (a sprinter cannot fire by naming a
--           moment before the sprint);
--   room    refused if the pose at the click OR at f is inside a spawn room (a shooter who has walked
--           back into its room, where it cannot be hit, cannot fire from the doorway it just left);
--   origin  the eye over the pose at the click, in the stance of the line then (originOk);
--   stance  and the origin's height above that pose must ALSO fit the stance on the line at f: a
--           shooter crouched behind a rail cannot fire over it from the standing eye of a moment ago.
-- The cost to an honest player: a click behind a lost packet that is followed, inside that packet's
-- delay, by a sprint or a crouch is refused (the press is lost, never a wrong ball).
function Stream.lateClickOk(
	person: Person,
	click: number,
	f: number,
	ox: number,
	oy: number,
	oz: number,
	arena: Arena,
	feel: Feel,
	now: number
): string?
	local after = click - Body.SPRINT_FIRE_DELAY + Contract.MARGIN.sprint
	for _, move in person.moves do
		if move.t > after and move.t <= f and Wire.has(move.bits, BIT.sprint) then
			return "sprint"
		end
	end
	local x, y, z, _, _, bitsC = Stream.poseAt(person, click)
	local fx, fy, fz = Stream.poseAt(person, f)
	if inEitherRoom(arena, x, y, z) or inEitherRoom(arena, fx, fy, fz) then
		return "safe"
	end
	if not Stream.originOk(person, click, ox, oy, oz, arena.sweep, feel, arena.ground) then
		return "origin"
	end
	if not heightOk(person, f, y, oy, feel, airborne(arena.ground, x, y, z, bitsC)) then
		return "origin"
	end
	local _ = now
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
