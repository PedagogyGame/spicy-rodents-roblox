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
-- Record fields (world coordinates in compiled records; data/attractions.json writes `out` in the building's
-- local frame and tools/compile turns it; the hollow trees' compile does the same from the tree's frame):
--   id      string   the enclosure: shared by every route of one tunnel or one hollow ("alley.return.2", "hollow.H2")
--   climb   boolean? a wall to climb (default false)
--   mouths  { Mouth }? where the inside meets the outside (below); a route with none is reached by end links only
--   atStart / atEnd  { route, t, dir }? authored end links: running off that end of the route goes on along
--           `route` from `t`, travelling `dir` (+1 toward its t = 1). A junction inside is never guessed.
--   width, height  the section the enclosure gives the body (studs; defaults 1.7 x 1.8). The body needs
--           Enclosure.BODY (1.6 wide, 1.7 high: Actors/RigSpec squirrel hitbox); headroom down to
--           BODY.crawlHeight (1.3) is allowed only inside a declared crawl.
--   crawl   { {t0, t1, height} }? stretches where the headroom is low: the body crouches there.
--   hidden  boolean? (default true) a body inside and away from a mouth is out of sight of people.
-- A mouth:
--   t       where on the route (0 or 1 at an end; part-way for a knothole in the side)
--   opens   "ground": onto standable ground. Walk in heading into it; running out of an end mouth steps
--                     out onto the ground on its feet, still running.
--           "ledge":  onto a ledge or above a floor (the ball return's hood over the rack). Running out of an
--                     end mouth stops with the head out ("lip"): Space or a click leaps out along `out`, Q
--                     drops out, S goes back in.
--           "air":    high in a trunk with nothing outside to stand on: as "ledge".
--           "link":   hands over to other routes (`links`, in order): running out of an end mouth runs on along
--                     links[1]; at a part-way mouth E takes links[1]. Transfers between the enclosed route at
--                     this mouth and the listed routes are allowed (both ways); no other route can reach in.
--   out     {x, y, z}? unit vector pointing outside; required part-way; at an end it defaults to the route's own
--           direction out of that end, level
--   reach   studs (default 1.2): how near the mouth point the body must be to get in, and how far along the
--           route the mouth extends either side of t (the body is "at the mouth" inside that window)
--   rise    studs (default 1.0): how far above or below the mouth point the body may stand to get in
--   links   { {route, t, dir} }? for "link" (allowed on the others too: the routes that meet it outside)
--   name    string? ("grille", "rack", "knothole 2")
--
-- THE RULES (Motion and SquirrelMotor; every one applies only to routes that carry `enclosure`, so every other
-- route behaves exactly as before):
--   1. Getting in: only at a mouth that opens ground, ledge or air, with the body within `reach` of the mouth
--      point (and `rise` of its height), on the outside of it, and moving into it (dot >= C.intoDot with the
--      inward direction). No pull from a distance: the walk-in grab, E's off-rail search and the air-catch never
--      take an enclosed route. The body is eased onto the mouth like a rail transfer (never a jump). E at a mouth
--      with the body facing in goes in the same way. From a rail, only through a "link" (rule 5).
--   2. Inside and away from a mouth there is no launching and no grabbing in or out: Space, a click and Q do
--      nothing (event hint "noRoom"); E, A/D and the end-of-route switch never pass a wall, floor or bark.
--   3. At a mouth the way out is stated: Space, a click and Q launch along `out`; at an end mouth W runs out as
--      `opens` says (step out on the ground, stop at the lip, or run on along the link).
--   4. At an end without a mouth the authored end link is taken (the same key keeps going); with neither it is a
--      dead end. One event per arrival ("railEnd", "lip"), never one per frame.
--   5. Transfers (E, A/D, end-of-route) between an enclosed route and any other: allowed within one enclosure;
--      otherwise only at a mouth of the enclosed side whose `links` name the other route (either side may name
--      it). Enclosure.allows decides; searches skip what it refuses, so E near a hollow tree still finds the
--      bough it found before.
--   6. A turn-back inside is allowed (S, or W with the view turned round when stopped), as on any level route.
-- What "inside" means for other systems: Enclosure.inside(route, t) is true on an enclosed route away from its
-- mouths; Enclosure.zone(route) is the enclosure id (the camera's zone); Enclosure.hidden(route, t) is inside
-- and `hidden`. Nut storage (later) will be stations at a t on an enclosed route.
-- Interface: KIND, BODY, C, validate(rec, kind), validateSet(records), fromRecord(rec), mouthAt(spec, length, t),
--   mouthNear(spec, length, t, slack), endMouth(spec, length, atStart), endLink(spec, atStart), inside(route, t),
--   hidden(route, t), zone(route), headroom(spec, t), allows(from, fromT, to, toT, slackFrom?, slackTo?),
--   names(mouth, routeId), linked(a, b)

local Curve = require("./Curve")

local Enclosure = {}

export type Vec3 = Curve.Vec3

-- As written in a route record (data files and generated modules).
export type LinkRecord = { route: number, t: number, dir: number }
export type MouthRecord = {
	t: number,
	opens: string,
	out: { number }?,
	reach: number?,
	rise: number?,
	links: { LinkRecord }?,
	name: string?,
}
export type Record = {
	id: string,
	climb: boolean?,
	mouths: { MouthRecord }?,
	atStart: LinkRecord?,
	atEnd: LinkRecord?,
	width: number?,
	height: number?,
	crawl: { { number } }?,
	hidden: boolean?,
}

-- As the Registry carries it on a Route.
export type Link = { route: number, t: number, dir: number }
export type Mouth = {
	t: number,
	opens: string,
	out: Vec3?,
	reach: number,
	rise: number,
	links: { Link },
	name: string?,
}
export type Crawl = { t0: number, t1: number, height: number }
export type Spec = {
	id: string,
	climb: boolean,
	mouths: { Mouth },
	atStart: Link?,
	atEnd: Link?,
	width: number,
	height: number,
	crawl: { Crawl },
	hidden: boolean,
}

-- Anything shaped like a route (Registry.Route has these and more).
export type RouteLike = { id: number, kind: string, length: number, enclosure: Spec? }

Enclosure.KIND = "tunnel"
Enclosure.OPENS = { ground = true, ledge = true, air = true, link = true }

-- The animal's clearance (Actors/RigSpec squirrel and Spicy Rodent hitbox: capsule radius 0.8, height 1.7).
Enclosure.BODY = { width = 1.6, height = 1.7, crawlHeight = 1.3 }

Enclosure.C = {
	reach = 1.2, -- default mouth reach and half-window, studs
	rise = 1.0, -- default vertical tolerance at a mouth, studs
	intoDot = 0.5, -- moving into a mouth: cos 60 degrees with the inward direction
	behind = 0.25, -- the body may stand this far past the mouth point (inside) and still count as outside it
	width = 1.7, -- default section width
	height = 1.8, -- default section headroom
	unitTol = 0.02, -- |out| within 1 +- this
}

local function link(rec: LinkRecord): Link
	return { route = rec.route, t = rec.t, dir = if rec.dir < 0 then -1 else 1 }
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
		table.insert(mouths, {
			t = m.t,
			opens = m.opens,
			out = out,
			reach = m.reach or Enclosure.C.reach,
			rise = m.rise or Enclosure.C.rise,
			links = links,
			name = m.name,
		})
	end
	local crawl: { Crawl } = {}
	local crawlRecs: { { number } } = rec.crawl or {}
	for _, c in crawlRecs do
		table.insert(crawl, { t0 = c[1], t1 = c[2], height = c[3] })
	end
	return {
		id = rec.id,
		climb = rec.climb == true,
		mouths = mouths,
		atStart = if rec.atStart then link(rec.atStart) else nil,
		atEnd = if rec.atEnd then link(rec.atEnd) else nil,
		width = rec.width or Enclosure.C.width,
		height = rec.height or Enclosure.C.height,
		crawl = crawl,
		hidden = rec.hidden ~= false,
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
		if m.reach ~= nil and (not isNumber(m.reach) or m.reach <= 0) then
			table.insert(errs, `{where}.reach must be a positive number`)
		end
		if m.rise ~= nil and (not isNumber(m.rise) or m.rise < 0) then
			table.insert(errs, `{where}.rise must be a non-negative number`)
		end
		local atEnd = isNumber(m.t) and (m.t == 0 or m.t == 1)
		if m.out ~= nil then
			local o = m.out
			if type(o) ~= "table" or not isNumber(o[1]) or not isNumber(o[2]) or not isNumber(o[3]) then
				table.insert(errs, `{where}.out must be {"{"}x, y, z{"}"}`)
			else
				local len = math.sqrt(o[1] * o[1] + o[2] * o[2] + o[3] * o[3])
				if math.abs(len - 1) > Enclosure.C.unitTol then
					table.insert(errs, `{where}.out must be a unit vector (length {len})`)
				end
			end
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

-- validateSet(routes): the errors across a set of route records { id, kind, enclosure? } (one building's or
-- one tree's): links name routes of the set or `known` ids, end links stay inside their enclosure, every
-- enclosure has a way in from outside, and two mouths of one route do not overlap.
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
		for _, side in { "atStart", "atEnd" } do
			local l = e[side]
			if type(l) == "table" then
				local to = byId[l.route]
				if not to then
					table.insert(errs, `route {r.id}: {side} names route {l.route}, not in the set`)
				elseif type(to.enclosure) ~= "table" or to.enclosure.id ~= e.id then
					table.insert(errs, `route {r.id}: {side} leads out of enclosure {e.id} (use a link mouth)`)
				end
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
					local gap = math.abs(m.t - n.t) * r.length
					if gap < (m.reach or Enclosure.C.reach) + (n.reach or Enclosure.C.reach) then
						table.insert(errs, `route {r.id}: mouths {i} and {j} overlap ({gap} studs apart)`)
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
		local gap = math.abs(t - m.t) * length
		if gap <= m.reach + slack + 1e-9 and gap < bestGap then
			best, bestGap = m, gap
		end
	end
	return best
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

-- zone(route): the enclosure id (the camera's zone), or nil off an enclosed route.
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

-- names(mouth, routeId): does the mouth's links list name the route?
function Enclosure.names(mouth: Mouth, routeId: number): boolean
	for _, l in mouth.links do
		if l.route == routeId then
			return true
		end
	end
	return false
end

-- allows(from, fromT, to, toT): may a body pass from `from` at fromT to `to` at toT (a transfer, a junction,
-- an end-of-route switch)? Rule 5. Two open routes: always (the old rules decide). Within one enclosure:
-- always. Otherwise each enclosed side must be at one of its mouths, and the pair must be named by a mouth's
-- links on either side.
-- `slackFrom` / `slackTo` (studs, default 0) widen the mouth windows on either side (the validator's reach).
function Enclosure.allows(
	from: RouteLike,
	fromT: number,
	to: RouteLike,
	toT: number,
	slackFrom: number?,
	slackTo: number?
): boolean
	local a, b = from.enclosure, to.enclosure
	if a == nil and b == nil then
		return true
	end
	if a ~= nil and b ~= nil and a.id == b.id then
		return true
	end
	local ma = if a then Enclosure.mouthNear(a, from.length, fromT, slackFrom or 0) else nil
	local mb = if b then Enclosure.mouthNear(b, to.length, toT, slackTo or 0) else nil
	if (a ~= nil and ma == nil) or (b ~= nil and mb == nil) then
		return false
	end
	return (ma ~= nil and Enclosure.names(ma, to.id)) or (mb ~= nil and Enclosure.names(mb, from.id))
end

-- linked(a, b): does either route's enclosure record name the other (an authored end link or a mouth's link)?
-- The validator prices such a transfer as a declared junction, whatever the gap the Graph sees.
function Enclosure.linked(a: RouteLike, b: RouteLike): boolean
	for _, pair in { { a, b }, { b, a } } do
		local spec, other = pair[1].enclosure, pair[2]
		if spec then
			if (spec.atStart and spec.atStart.route == other.id) or (spec.atEnd and spec.atEnd.route == other.id) then
				return true
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
