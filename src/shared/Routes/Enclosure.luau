--!strict
-- ReplicatedStorage.Shared.Routes.Enclosure
-- The one mechanic for enclosed squirrel runs: a hollow tree's inside, the bowling alley's ball return, and
-- any later pipe, vent or log (brief v2 §3 and §13a; BRIEF_ADDENDUM D6: "that same mechanics or physics
-- should allow us to run through that ball return"). Pure data and rules: no engine calls, no geometry
-- beyond the numbers passed in. Motion (Routes/Motion) does the geometry, SquirrelMotor applies the rules,
-- SquirrelMotor.envelope (the server MoveValidator) checks them.
--
-- THE CONTRACT
-- A route of kind "tunnel" (Enclosure.KIND) carries an `enclosure` record; no other kind may. It moves like a
-- level run: W goes the way the view looks (as on a bough or a bridge), never a tree climb, unless the record
-- says `climb = true` (a shaft inside a trunk: W climbs toward t = 1, the route authored from its foot up).
-- Record fields (world coordinates in compiled records; data/attractions.json writes `out`, `up`, `upAt` and
-- `cavity` in the building's local frame and tools/compile turns them; the hollow trees' compile does the same
-- from the tree's frame):
--   id      string   the enclosure: shared by every route of one tunnel or one hollow ("alley.return.2", "hollow.H2")
--   climb   boolean? a wall to climb (default false); needs `up` (or `upAt`): which side the wall is
--   mouths  { Mouth }? where the inside meets the outside (below); a route with none is reached by links only
--   atStart / atEnd  { route, t, dir }? authored end links to the next INSIDE route of the same enclosure: running
--           off that end goes on along `route` from `t`, travelling `dir` x sign(W/S) (+1 toward its t = 1)
--   forks   { {t, route, toT, dir, name?} }? authored junctions part-way along the route to another inside route
--           of the same enclosure (a hideout off a shaft, a side passage): A/D picks one ahead (like a junction on
--           a bough), W carries the body onto it as it passes; E takes one within C.linkWindow of the body
--   Inside one enclosure, ONLY these connect routes (end links, forks, and mouths whose links name an inside route):
--   a junction inside is never guessed, and nothing reaches across the wood between two passages of one tree.
--   width, height  the section the enclosure gives the body (studs; defaults 1.7 x 1.8). The body needs
--           Enclosure.BODY (1.6 wide, 1.7 high: Actors/RigSpec squirrel hitbox); headroom down to
--           BODY.crawlHeight (1.3) is allowed only inside a declared crawl.
--   crawl   { {t0, t1, height} }? stretches where the headroom is low: the body crouches there.
--   up      {x, y, z}? the section's up for the whole route (unit): the direction the headroom is measured along,
--           the body's back; width is across the line square to it. On a climb it points from the wall the body
--           clings to toward its back (into the cavity): the belly faces -up.
--   upAt    { {t, x, y, z} }? the same per stretch (sorted by t; interpolated between, held past the ends).
--           Default when neither is given (Motion.section): world up squared to the line; where the line is
--           steeper than C.steep the last up it had, carried along from t = 0 (the clearance sweep's rule).
--   cavity  { axis = {x, z}, radius, bottom?, top? }? a round chamber the route lies in (a trunk's hollow): its
--           vertical axis, inner radius and the heights it spans; the inside camera stays within it.
--   hidden  boolean? (default true) a body inside and away from a mouth is out of sight of people.
-- A mouth:
--   t       where on the route (0 or 1 at an end; part-way for a knothole in the side)
--   opens   "ground": onto standable ground. Walk in heading into it; running out of an end mouth steps
--                     out onto the ground on its feet, still running; E at a part-way one steps out.
--           "ledge":  onto a ledge or above a floor (the ball return's hood over the rack). Running out of an
--                     end mouth stops with the head out ("lip"): Space or a click leaps out along `out`, Q
--                     drops out, S (or W with the view turned round) goes back in.
--           "air":    high in a trunk with nothing outside to stand on: as "ledge".
--           "link":   hands over to other routes (`links`, in order): running out of an end mouth runs on along
--                     links[1]; at a part-way mouth E takes links[1] and A/D can pick one as for a fork.
--                     Transfers between the enclosed route at this mouth and the listed routes are allowed (both
--                     ways); no other route can reach in.
--   out     {x, y, z}? unit vector pointing outside; required part-way. At an end it defaults to the heading of
--           links[1] (a "link" mouth) or the route's own direction out of that end, level. Whatever it resolves to
--           must lean out at least C.minOutLevel horizontally (Motion.enclosureErrors): a vertical shaft's top needs
--           one. A launch never falls back to the body's facing.
--   reach   studs (default 1.2): how near the mouth point (level) the body must be to get in
--   rise    studs (default 1.0): how far above or below the mouth point the body may stand to get in
--   window  studs: how far along the route the body counts as "at the mouth" (where Space, Q, a click or E work).
--           At an end it runs inward only (default C.endWindow 0.3: the head is out, not the body); part-way
--           it runs both ways (default `reach`).
--   depth   studs (default 0): from the route's point at t, along `out`, to the outside face of the opening (the
--           bark's thickness at a knothole the route passes inside the trunk). A launch starts at
--           Motion.launchPoint: the face plus C.clear (half the body and a hair), never inside the shell.
--   hop     st/s? Space and a click out of this mouth are a short hop at this horizontal speed (vertical `hopUp`,
--           default C.hopUp) instead of a full leap or pounce: the pop out at the rack lands by it.
--   links   { {route, t, dir} }? for "link" (allowed on the others too: the routes that meet it outside)
--   name    string? ("grille", "rack", "knothole 2")
--
-- THE RULES (Motion and SquirrelMotor; every one applies only to routes that carry `enclosure`, so every other
-- route behaves exactly as before):
--   1. Getting in: only at a mouth that opens ground, ledge or air, with the body within `reach` of the mouth
--      point (level; `rise` of its height), not more than C.behind (half the body) past it on the inside, and
--      moving into it (dot >= C.intoDot with the inward direction): walking, falling, leaping or pouncing (the
--      flight's swept path counts, and going in ends the attack). No pull from a distance: the walk-in grab, E's
--      off-rail search and the air-catch never take an enclosed route. The body is eased onto the mouth like a
--      rail transfer (never a jump). E at a mouth with the body facing in goes in the same way. From a rail,
--      only through a "link" (rule 5).
--   2. Inside and away from a mouth there is no launching and no grabbing in or out: Space, a click and Q do
--      nothing (event hint "noRoom"); E, A/D and the end-of-route switch never pass a wall, floor or bark.
--   3. At a mouth the way out is stated: Space, a click and Q launch from the outside face along `out` (Q with a
--      small push, C.dropPush); at an end mouth W runs out as `opens` says (step out on the ground, stop at the
--      lip, or run on along the link); at a part-way mouth E takes the link or steps out.
--   4. At an end without a mouth the authored end link is taken (the same key keeps going); with neither it is a
--      dead end. One event per arrival ("railEnd", "lip"), never one per frame. At a lip or a dead end a turned
--      view with W held turns back at once.
--   5. Transfers (E, A/D, end-of-route) between an enclosed route and any other: only where an authored record
--      connects the pair at those points (Enclosure.allows): an end link, a fork, or a mouth whose `links` name
--      the other route (either side may name it), with each enclosed side at that connection. Searches skip what
--      it refuses, so E near a hollow tree still finds the bough it found before.
--   6. A turn-back inside is allowed (S, or W with the view turned round when stopped), as on any level route.
-- What "inside" means for other systems: Enclosure.inside(route, t) is true on an enclosed route away from its
-- mouths; Enclosure.zone(route) is the enclosure id (the client's CameraZone is "tunnel" whenever it is set);
-- Enclosure.hidden(route, t) is inside and `hidden`; Motion.section gives the body's frame and headroom at t;
-- `cavity` bounds an inside camera. Nut storage (later) will be stations at a t on an enclosed route.
-- Interface: KIND, BODY, C, validate(rec, kind), validateSet(records, known?), fromRecord(rec), windowOf(mouth),
--   mouthAt(spec, length, t), mouthNear(spec, length, t, slack), endMouth(spec, length, atStart),
--   endLink(spec, atStart), inside(route, t), hidden(route, t), zone(route), headroom(spec, t), upAt(spec, t),
--   names(mouth, routeId), connects(a, aT, b, bT, slackA?, slackB?), allows(from, fromT, to, toT, slackFrom?,
--   slackTo?), linked(a, b), exits(spec, length)

local Curve = require("./Curve")

local Enclosure = {}

export type Vec3 = Curve.Vec3

-- As written in a route record (data files and generated modules).
export type LinkRecord = { route: number, t: number, dir: number }
export type ForkRecord = { t: number, route: number, toT: number, dir: number, name: string? }
export type MouthRecord = {
	t: number,
	opens: string,
	out: { number }?,
	reach: number?,
	rise: number?,
	window: number?,
	depth: number?,
	hop: number?,
	hopUp: number?,
	links: { LinkRecord }?,
	name: string?,
}
export type CavityRecord = { axis: { number }, radius: number, bottom: number?, top: number? }
export type Record = {
	id: string,
	climb: boolean?,
	mouths: { MouthRecord }?,
	atStart: LinkRecord?,
	atEnd: LinkRecord?,
	forks: { ForkRecord }?,
	width: number?,
	height: number?,
	crawl: { { number } }?,
	hidden: boolean?,
	up: { number }?,
	upAt: { { number } }?,
	cavity: CavityRecord?,
}

-- As the Registry carries it on a Route.
export type Link = { route: number, t: number, dir: number }
export type Fork = { t: number, route: number, toT: number, dir: number, name: string? }
export type Mouth = {
	t: number,
	opens: string,
	out: Vec3?,
	reach: number,
	rise: number,
	window: number,
	depth: number,
	hop: number?,
	hopUp: number,
	links: { Link },
	name: string?,
}
export type Crawl = { t0: number, t1: number, height: number }
export type UpKey = { t: number, up: Vec3 }
export type Cavity = { x: number, z: number, radius: number, bottom: number?, top: number? }
export type Spec = {
	id: string,
	climb: boolean,
	mouths: { Mouth },
	atStart: Link?,
	atEnd: Link?,
	forks: { Fork },
	width: number,
	height: number,
	crawl: { Crawl },
	hidden: boolean,
	up: Vec3?,
	upAt: { UpKey },
	cavity: Cavity?,
}

-- Anything shaped like a route (Registry.Route has these and more).
export type RouteLike = { id: number, kind: string, length: number, enclosure: Spec? }

-- A way off an enclosed route part-way along it that A/D may pick and E or W may take (Enclosure.exits).
export type Exit = { t: number, route: number, toT: number, dir: number, mouth: Mouth? }

Enclosure.KIND = "tunnel"
Enclosure.OPENS = { ground = true, ledge = true, air = true, link = true }

-- The animal's clearance (Actors/RigSpec squirrel and Spicy Rodent hitbox: capsule radius 0.8, height 1.7).
Enclosure.BODY = { width = 1.6, height = 1.7, crawlHeight = 1.3 }

Enclosure.C = {
	reach = 1.2, -- default mouth reach (level), studs
	rise = 1.0, -- default vertical tolerance at a mouth, studs
	intoDot = 0.5, -- moving into a mouth: cos 60 degrees with the inward direction
	behind = 0.8, -- the body may stand this far past the mouth point (inside) and still count as outside it: half
	-- the body, so a body pressed into the opening (its nose in, its middle at most half a body past) still gets in
	endWindow = 0.3, -- default window of an end mouth, inward from the end (the head out, not the body)
	clear = 0.9, -- a launch starts this far outside the opening's face (half the body's width and 0.1)
	dropPush = 3.0, -- Q at a mouth: this horizontal speed out along `out`, so the drop clears the opening
	hopUp = 8.6, -- default vertical speed of a mouth's `hop` (a pounce's base lift)
	linkWindow = 1.2, -- an end link or a fork connects within this many studs of its point on either route
	forkAhead = 6.0, -- A/D offers the forks and part-way link mouths up to this far ahead along the travel
	minOutLevel = 0.3, -- a mouth's resolved `out` leans out at least this much horizontally
	steep = 0.97, -- |tangent . world up| above which the default section up carries on from before
	width = 1.7, -- default section width
	height = 1.8, -- default section headroom
	unitTol = 0.02, -- |out| within 1 +- this
}

local function link(rec: LinkRecord): Link
	return { route = rec.route, t = rec.t, dir = if rec.dir < 0 then -1 else 1 }
end

local function unit(x: number, y: number, z: number): Vec3
	local l = math.sqrt(x * x + y * y + z * z)
	if l < 1e-9 then
		return Curve.vec3(0, 1, 0)
	end
	return Curve.vec3(x / l, y / l, z / l)
end

local function isEnd(t: number): boolean
	return t <= 0 or t >= 1
end

-- fromRecord(rec): the runtime spec (defaults filled, vectors as Vec3). The record must have passed validate.
function Enclosure.fromRecord(rec: Record): Spec
	local mouths: { Mouth } = {}
	local mouthRecs: { MouthRecord } = rec.mouths or {}
	for _, m in mouthRecs do
		local linkRecs: { LinkRecord } = m.links or {}
		local links: { Link } = {}
		for _, l in linkRecs do
			table.insert(links, link(l))
		end
		local out: Vec3? = nil
		if m.out then
			out = Curve.vec3(m.out[1], m.out[2], m.out[3])
		end
		local reach = m.reach or Enclosure.C.reach
		table.insert(mouths, {
			t = m.t,
			opens = m.opens,
			out = out,
			reach = reach,
			rise = m.rise or Enclosure.C.rise,
			window = m.window or (if isEnd(m.t) then Enclosure.C.endWindow else reach),
			depth = m.depth or 0,
			hop = m.hop,
			hopUp = m.hopUp or Enclosure.C.hopUp,
			links = links,
			name = m.name,
		})
	end
	local crawl: { Crawl } = {}
	local crawlRecs: { { number } } = rec.crawl or {}
	for _, c in crawlRecs do
		table.insert(crawl, { t0 = c[1], t1 = c[2], height = c[3] })
	end
	local forks: { Fork } = {}
	local forkRecs: { ForkRecord } = rec.forks or {}
	for _, f in forkRecs do
		table.insert(forks, { t = f.t, route = f.route, toT = f.toT, dir = if f.dir < 0 then -1 else 1, name = f.name })
	end
	local upAt: { UpKey } = {}
	local upRecs: { { number } } = rec.upAt or {}
	for _, u in upRecs do
		table.insert(upAt, { t = u[1], up = unit(u[2], u[3], u[4]) })
	end
	table.sort(upAt, function(a: UpKey, b: UpKey): boolean
		return a.t < b.t
	end)
	local cavity: Cavity? = nil
	local cr = rec.cavity
	if cr then
		cavity = { x = cr.axis[1], z = cr.axis[2], radius = cr.radius, bottom = cr.bottom, top = cr.top }
	end
	return {
		id = rec.id,
		climb = rec.climb == true,
		mouths = mouths,
		atStart = if rec.atStart then link(rec.atStart) else nil,
		atEnd = if rec.atEnd then link(rec.atEnd) else nil,
		forks = forks,
		width = rec.width or Enclosure.C.width,
		height = rec.height or Enclosure.C.height,
		crawl = crawl,
		hidden = rec.hidden ~= false,
		up = if rec.up then unit(rec.up[1], rec.up[2], rec.up[3]) else nil,
		upAt = upAt,
		cavity = cavity,
	}
end

local function isNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function checkLink(errs: { string }, where: string, l: any)
	if type(l) ~= "table" then
		table.insert(errs, `{where}: a link is a table`)
		return
	end
	if not isNumber(l.route) or l.route % 1 ~= 0 then
		table.insert(errs, `{where}: link route must be an integer id`)
	end
	if not isNumber(l.t) or l.t < 0 or l.t > 1 then
		table.insert(errs, `{where}: link t must be in [0, 1]`)
	end
	if l.dir ~= 1 and l.dir ~= -1 then
		table.insert(errs, `{where}: link dir must be 1 or -1`)
	end
end

local function checkUnit(errs: { string }, where: string, o: any, first: number)
	if type(o) ~= "table" or not isNumber(o[first]) or not isNumber(o[first + 1]) or not isNumber(o[first + 2]) then
		table.insert(errs, `{where} must be {"{"}x, y, z{"}"}`)
		return
	end
	local x, y, z = o[first], o[first + 1], o[first + 2]
	local len = math.sqrt(x * x + y * y + z * z)
	if math.abs(len - 1) > Enclosure.C.unitTol then
		table.insert(errs, `{where} must be a unit vector (length {len})`)
	end
end

-- validate(rec, kind): the errors in one route's record (empty when valid). `rec` is the route's `enclosure`
-- field (nil when absent); `kind` the route's kind. Shared by the compilers and the Registry.
function Enclosure.validate(rec: any, kind: string): { string }
	local errs: { string } = {}
	if rec == nil then
		if kind == Enclosure.KIND then
			table.insert(errs, `a route of kind "{Enclosure.KIND}" needs an enclosure record`)
		end
		return errs
	end
	if kind ~= Enclosure.KIND then
		table.insert(errs, `only a route of kind "{Enclosure.KIND}" may carry an enclosure (kind {kind})`)
	end
	if type(rec) ~= "table" then
		table.insert(errs, "enclosure must be a table")
		return errs
	end
	if type(rec.id) ~= "string" or rec.id == "" then
		table.insert(errs, "enclosure.id must be a non-empty string")
	end
	if rec.climb ~= nil and type(rec.climb) ~= "boolean" then
		table.insert(errs, "enclosure.climb must be a boolean")
	end
	if rec.climb == true and rec.up == nil and rec.upAt == nil then
		table.insert(errs, "enclosure.climb needs up (or upAt): which side the wall is")
	end
	if rec.hidden ~= nil and type(rec.hidden) ~= "boolean" then
		table.insert(errs, "enclosure.hidden must be a boolean")
	end
	local height = if isNumber(rec.height) then rec.height else Enclosure.C.height
	if rec.width ~= nil and (not isNumber(rec.width) or rec.width < Enclosure.BODY.width) then
		table.insert(errs, `enclosure.width must be at least the body's {Enclosure.BODY.width}`)
	end
	if rec.height ~= nil and (not isNumber(rec.height) or rec.height < Enclosure.BODY.height) then
		table.insert(errs, `enclosure.height must be at least the body's {Enclosure.BODY.height} (use crawl)`)
	end
	for i, c in rec.crawl or {} do
		if
			type(c) ~= "table"
			or not isNumber(c[1])
			or not isNumber(c[2])
			or not isNumber(c[3])
			or c[1] < 0
			or c[2] > 1
			or c[1] >= c[2]
		then
			table.insert(errs, `enclosure.crawl[{i}] must be {"{"}t0, t1, height{"}"} with 0 <= t0 < t1 <= 1`)
		elseif c[3] < Enclosure.BODY.crawlHeight or c[3] > height then
			table.insert(
				errs,
				`enclosure.crawl[{i}] height {c[3]} must be between the crawl's {Enclosure.BODY.crawlHeight} and the headroom {height}`
			)
		end
	end
	for _, side in { "atStart", "atEnd" } do
		local l = rec[side]
		if l ~= nil then
			checkLink(errs, `enclosure.{side}`, l)
		end
	end
	for i, f in rec.forks or {} do
		local where = `enclosure.forks[{i}]`
		if type(f) ~= "table" then
			table.insert(errs, `{where} must be a table`)
			continue
		end
		if not isNumber(f.t) or f.t < 0 or f.t > 1 then
			table.insert(errs, `{where}.t must be in [0, 1]`)
		end
		checkLink(errs, where, { route = f.route, t = f.toT, dir = f.dir })
	end
	if rec.up ~= nil then
		checkUnit(errs, "enclosure.up", rec.up, 1)
	end
	for i, u in rec.upAt or {} do
		if type(u) ~= "table" or not isNumber(u[1]) or u[1] < 0 or u[1] > 1 then
			table.insert(errs, `enclosure.upAt[{i}] must be {"{"}t, x, y, z{"}"} with t in [0, 1]`)
		else
			checkUnit(errs, `enclosure.upAt[{i}]`, u, 2)
		end
	end
	if rec.cavity ~= nil then
		local c = rec.cavity
		if
			type(c) ~= "table"
			or type(c.axis) ~= "table"
			or not isNumber(c.axis[1])
			or not isNumber(c.axis[2])
			or not isNumber(c.radius)
			or c.radius <= 0
			or (c.bottom ~= nil and not isNumber(c.bottom))
			or (c.top ~= nil and not isNumber(c.top))
		then
			table.insert(errs, "enclosure.cavity must be { axis = {x, z}, radius > 0, bottom?, top? }")
		end
	end
	for i, m in rec.mouths or {} do
		local where = `enclosure.mouths[{i}]`
		if type(m) ~= "table" then
			table.insert(errs, `{where} must be a table`)
			continue
		end
		if not isNumber(m.t) or m.t < 0 or m.t > 1 then
			table.insert(errs, `{where}.t must be in [0, 1]`)
		end
		if not Enclosure.OPENS[m.opens] then
			table.insert(errs, `{where}.opens must be ground, ledge, air or link (got {tostring(m.opens)})`)
		end
		for _, field in { "reach", "window", "hop" } do
			local v = m[field]
			if v ~= nil and (not isNumber(v) or v <= 0) then
				table.insert(errs, `{where}.{field} must be a positive number`)
			end
		end
		for _, field in { "rise", "depth", "hopUp" } do
			local v = m[field]
			if v ~= nil and (not isNumber(v) or v < 0) then
				table.insert(errs, `{where}.{field} must be a non-negative number`)
			end
		end
		local atEnd = isNumber(m.t) and (m.t == 0 or m.t == 1)
		if m.out ~= nil then
			checkUnit(errs, `{where}.out`, m.out, 1)
		elseif not atEnd then
			table.insert(errs, `{where}: a part-way mouth needs out`)
		end
		if m.opens == "link" and (type(m.links) ~= "table" or #m.links == 0) then
			table.insert(errs, `{where}: a link mouth needs links`)
		end
		for j, l in m.links or {} do
			checkLink(errs, `{where}.links[{j}]`, l)
		end
	end
	return errs
end

-- the stretch of the route (studs from t = 0) a mouth's window covers
local function span(t: number, window: number, length: number): (number, number)
	if t <= 0 then
		return 0, window
	elseif t >= 1 then
		return length - window, length
	end
	return t * length - window, t * length + window
end

-- validateSet(routes): the errors across a set of route records { id, kind, length?, enclosure? } (one building's
-- or one tree's): links and forks name routes of the set or `known` ids, end links and forks stay inside their
-- enclosure, every enclosure has a way in from outside, and two mouths of one route do not overlap.
function Enclosure.validateSet(routes: { any }, known: { [number]: boolean }?): { string }
	local errs: { string } = {}
	local byId: { [number]: any } = {}
	for _, r in routes do
		byId[r.id] = r
	end
	local opens: { [string]: boolean } = {}
	local ids: { [string]: boolean } = {}
	for _, r in routes do
		local e = r.enclosure
		if type(e) ~= "table" then
			continue
		end
		for _, err in Enclosure.validate(e, r.kind) do
			table.insert(errs, `route {r.id}: {err}`)
		end
		if type(e.id) ~= "string" then
			continue
		end
		ids[e.id] = true
		local inner: { { string | number } } = {}
		for _, side in { "atStart", "atEnd" } do
			local l = e[side]
			if type(l) == "table" then
				table.insert(inner, { side, l.route })
			end
		end
		for i, f in e.forks or {} do
			if type(f) == "table" then
				table.insert(inner, { `fork {i}`, f.route })
			end
		end
		for _, pair in inner do
			local what, id = pair[1], pair[2] :: number
			local to = byId[id]
			if not to then
				table.insert(errs, `route {r.id}: {what} names route {id}, not in the set`)
			elseif type(to.enclosure) ~= "table" or to.enclosure.id ~= e.id then
				table.insert(errs, `route {r.id}: {what} leads out of enclosure {e.id} (use a link mouth)`)
			end
		end
		local mouths = e.mouths or {}
		for i, m in mouths do
			if type(m) ~= "table" then
				continue
			end
			if m.opens == "ground" or m.opens == "ledge" or m.opens == "air" or m.opens == "link" then
				opens[e.id] = true
			end
			for _, l in m.links or {} do
				if type(l) == "table" and not byId[l.route] and not (known and known[l.route]) then
					table.insert(errs, `route {r.id}: mouth {i} links route {l.route}, which does not exist`)
				end
			end
			for j = i + 1, #mouths do
				local n = mouths[j]
				if type(n) == "table" and isNumber(m.t) and isNumber(n.t) and isNumber(r.length) then
					local wm = m.window or (if isEnd(m.t) then Enclosure.C.endWindow else m.reach or Enclosure.C.reach)
					local wn = n.window or (if isEnd(n.t) then Enclosure.C.endWindow else n.reach or Enclosure.C.reach)
					local a0, a1 = span(m.t, wm, r.length)
					local b0, b1 = span(n.t, wn, r.length)
					if a0 <= b1 and b0 <= a1 then
						table.insert(errs, `route {r.id}: mouths {i} and {j} overlap`)
					end
				end
			end
		end
	end
	for id in ids do
		if not opens[id] then
			table.insert(errs, `enclosure {id} has no mouth: nothing can get in`)
		end
	end
	return errs
end

-- the distance (studs) along the route from t to the mouth (an end mouth's window can only lie inward of it)
local function gapTo(m: Mouth, length: number, t: number): number
	return math.abs(t - m.t) * length
end

-- mouthAt(spec, length, t): the mouth whose window holds t (the nearest when two would), or nil.
function Enclosure.mouthAt(spec: Spec, length: number, t: number): Mouth?
	return Enclosure.mouthNear(spec, length, t, 0)
end

-- mouthNear(spec, length, t, slack): as mouthAt with every window widened by `slack` studs (the validator: how far
-- the body could have run along the route between two packets).
function Enclosure.mouthNear(spec: Spec, length: number, t: number, slack: number): Mouth?
	local best: Mouth? = nil
	local bestGap = math.huge
	for _, m in spec.mouths do
		local gap = gapTo(m, length, t)
		if gap <= m.window + slack + 1e-9 and gap < bestGap then
			best, bestGap = m, gap
		end
	end
	return best
end

-- windowOf(mouth): the studs along the route the body counts as at it.
function Enclosure.windowOf(m: Mouth): number
	return m.window
end

-- endMouth(spec, length, atStart): the mouth at that end of the route (its window holds the end), or nil.
function Enclosure.endMouth(spec: Spec, length: number, atStart: boolean): Mouth?
	return Enclosure.mouthAt(spec, length, if atStart then 0 else 1)
end

-- endLink(spec, atStart): the authored end link at that end, or nil.
function Enclosure.endLink(spec: Spec, atStart: boolean): Link?
	return if atStart then spec.atStart else spec.atEnd
end

-- inside(route, t): on an enclosed route and away from its mouths.
function Enclosure.inside(route: RouteLike, t: number): boolean
	local spec = route.enclosure
	return spec ~= nil and Enclosure.mouthAt(spec, route.length, t) == nil
end

-- hidden(route, t): inside and out of sight of people.
function Enclosure.hidden(route: RouteLike, t: number): boolean
	local spec = route.enclosure
	return spec ~= nil and spec.hidden and Enclosure.mouthAt(spec, route.length, t) == nil
end

-- zone(route): the enclosure id, or nil off an enclosed route. The client sets CameraZone "tunnel" whenever it is
-- not nil (Client/Controllers/Squirrel), so every enclosed run gets the inside camera.
function Enclosure.zone(route: RouteLike?): string?
	local spec = if route then route.enclosure else nil
	return if spec then spec.id else nil
end

-- headroom(spec, t): the headroom at t and whether the body crawls there.
function Enclosure.headroom(spec: Spec, t: number): (number, boolean)
	for _, c in spec.crawl do
		if t >= c.t0 and t <= c.t1 then
			return c.height, true
		end
	end
	return spec.height, false
end

-- upAt(spec, t): the authored section up at t (unit; `upAt` interpolated, else `up`), or nil where the default
-- applies (Motion.section).
function Enclosure.upAt(spec: Spec, t: number): Vec3?
	local keys = spec.upAt
	local n = #keys
	if n == 0 then
		return spec.up
	end
	if t <= keys[1].t then
		return keys[1].up
	end
	if t >= keys[n].t then
		return keys[n].up
	end
	for i = 1, n - 1 do
		local a, b = keys[i], keys[i + 1]
		if t >= a.t and t <= b.t then
			local f = if b.t > a.t then (t - a.t) / (b.t - a.t) else 0
			return unit(a.up.x + (b.up.x - a.up.x) * f, a.up.y + (b.up.y - a.up.y) * f, a.up.z + (b.up.z - a.up.z) * f)
		end
	end
	return keys[n].up
end

-- names(mouth, routeId): does the mouth's links list name the route?
function Enclosure.names(mouth: Mouth, routeId: number): boolean
	for _, l in mouth.links do
		if l.route == routeId then
			return true
		end
	end
	return false
end

-- exits(spec, length): the authored ways off the route part-way along it, in t order: its forks and the first link of
-- each part-way link mouth (A/D picks among them; E or passing W takes one).
function Enclosure.exits(spec: Spec, _length: number): { Exit }
	local out: { Exit } = {}
	for _, f in spec.forks do
		table.insert(out, { t = f.t, route = f.route, toT = f.toT, dir = f.dir, mouth = nil })
	end
	for _, m in spec.mouths do
		if not isEnd(m.t) and #m.links > 0 then
			local l = m.links[1]
			table.insert(out, { t = m.t, route = l.route, toT = l.t, dir = l.dir, mouth = m })
		end
	end
	table.sort(out, function(a: Exit, b: Exit): boolean
		return a.t < b.t
	end)
	return out
end

-- connects(a, aT, b, bT, slackA?, slackB?): does `a`'s own record connect it to `b` at those points? An end link or a
-- fork (within C.linkWindow of its point on both routes), or a mouth of `a` whose window holds aT and whose links
-- name `b` (when `b` is enclosed too: at one of b's mouths, or, same enclosure, within C.linkWindow of the link's t).
-- `slackA` / `slackB` (studs) widen the windows (the validator's reach between packets).
function Enclosure.connects(
	a: RouteLike,
	aT: number,
	b: RouteLike,
	bT: number,
	slackA: number?,
	slackB: number?
): boolean
	local spec = a.enclosure
	if spec == nil then
		return false
	end
	local sa, sb = slackA or 0, slackB or 0
	local w = Enclosure.C.linkWindow
	local function near(at: number, t: number, length: number, slack: number): boolean
		return math.abs(at - t) * length <= w + slack + 1e-9
	end
	local function endLink(l: Link?, at: number): boolean
		return l ~= nil and l.route == b.id and near(aT, at, a.length, sa) and near(bT, l.t, b.length, sb)
	end
	if endLink(spec.atStart, 0) or endLink(spec.atEnd, 1) then
		return true
	end
	for _, f in spec.forks do
		if f.route == b.id and near(aT, f.t, a.length, sa) and near(bT, f.toT, b.length, sb) then
			return true
		end
	end
	local other = b.enclosure
	for _, m in spec.mouths do
		if gapTo(m, a.length, aT) > m.window + sa + 1e-9 then
			continue
		end
		for _, l in m.links do
			if l.route ~= b.id then
				continue
			end
			if other == nil then
				return true
			elseif other.id == spec.id then
				if near(bT, l.t, b.length, sb) then
					return true
				end
			elseif Enclosure.mouthNear(other, b.length, bT, sb) ~= nil then
				return true
			end
		end
	end
	return false
end

-- allows(from, fromT, to, toT): may a body pass from `from` at fromT to `to` at toT (a transfer, a junction,
-- an end-of-route switch)? Rule 5. Two open routes: always (the old rules decide). Otherwise only where either
-- side's record connects the pair at those points (Enclosure.connects): one enclosure is NOT enough.
-- `slackFrom` / `slackTo` (studs, default 0) widen the windows on either side (the validator's reach).
function Enclosure.allows(
	from: RouteLike,
	fromT: number,
	to: RouteLike,
	toT: number,
	slackFrom: number?,
	slackTo: number?
): boolean
	if from.enclosure == nil and to.enclosure == nil then
		return true
	end
	return Enclosure.connects(from, fromT, to, toT, slackFrom, slackTo)
		or Enclosure.connects(to, toT, from, fromT, slackTo, slackFrom)
end

-- linked(a, b): does either route's enclosure record name the other (an end link, a fork or a mouth's link)? The
-- validator prices such a transfer as a declared junction, whatever the gap the Graph sees (Enclosure.allows still
-- decides whether it happened at the connection).
function Enclosure.linked(a: RouteLike, b: RouteLike): boolean
	for _, pair in { { a, b }, { b, a } } do
		local spec, other = pair[1].enclosure, pair[2]
		if spec then
			if (spec.atStart and spec.atStart.route == other.id) or (spec.atEnd and spec.atEnd.route == other.id) then
				return true
			end
			for _, f in spec.forks do
				if f.route == other.id then
					return true
				end
			end
			for _, m in spec.mouths do
				if Enclosure.names(m, other.id) then
					return true
				end
			end
		end
	end
	return false
end

return Enclosure
