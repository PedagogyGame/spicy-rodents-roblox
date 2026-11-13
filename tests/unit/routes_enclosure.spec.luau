--!strict
-- Shared/Routes/Enclosure: the contract for enclosed squirrel runs (hollow trees, the ball return; BRIEF_ADDENDUM
-- D6). The record's rules (validate, validateSet), the runtime spec (fromRecord, mouthAt, endMouth, inside,
-- hidden, zone, headroom), the transfer rule (allows), the Registry carrying it, and the attractions schema
-- accepting it. The motor's rules on enclosed routes are in movement_enclosure.spec.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Enclosure = require("@shared/Routes/Enclosure")
local Registry = require("@shared/Routes/Registry")
local Schema = require("../../tools/compile/lib/Schema")

local function rec(over: { [string]: any }?): { [string]: any }
	local r: { [string]: any } = {
		id = "test.duct",
		mouths = {
			{ t = 0, opens = "ground", name = "grille" },
			{ t = 1, opens = "ledge", name = "rack" },
		},
	}
	for k, v in over or {} do
		r[k] = v
	end
	return r
end

local function has(errs: { string }, word: string): boolean
	for _, e in errs do
		if string.find(e, word, 1, true) then
			return true
		end
	end
	return false
end

return function(t)
	t.test("validate: a tunnel needs an enclosure, and only a tunnel may carry one", function()
		t.eq(#Enclosure.validate(rec(), "tunnel"), 0)
		t.truthy(has(Enclosure.validate(nil, "tunnel"), "needs an enclosure"))
		t.truthy(has(Enclosure.validate(rec(), "bridge"), "only a route of kind"))
		t.eq(#Enclosure.validate(nil, "bridge"), 0, "an open route is untouched")
	end)

	t.test("validate: mouths, links, clearance and crawl are checked field by field", function()
		local function errs(over: { [string]: any }): { string }
			return Enclosure.validate(rec(over), "tunnel")
		end
		t.truthy(has(errs({ id = "" }), "enclosure.id"))
		t.truthy(has(errs({ mouths = { { t = 1.5, opens = "ground" } } }), ".t must be in [0, 1]"))
		t.truthy(has(errs({ mouths = { { t = 0, opens = "door" } } }), ".opens must be"))
		t.truthy(has(errs({ mouths = { { t = 0.5, opens = "air" } } }), "part-way mouth needs out"))
		t.eq(#errs({ mouths = { { t = 0.5, opens = "air", out = { 1, 0, 0 } } } }), 0)
		t.truthy(has(errs({ mouths = { { t = 0.5, opens = "air", out = { 1, 1, 0 } } } }), "unit vector"))
		t.truthy(has(errs({ mouths = { { t = 1, opens = "link" } } }), "needs links"))
		t.truthy(
			has(errs({ mouths = { { t = 1, opens = "link", links = { { route = 3, t = 0, dir = 0 } } } } }), "dir")
		)
		t.eq(#errs({ mouths = { { t = 1, opens = "link", links = { { route = 3, t = 0, dir = 1 } } } } }), 0)
		t.truthy(has(errs({ width = 1.2 }), "enclosure.width"))
		t.truthy(has(errs({ height = 1.4 }), "use crawl"))
		t.eq(#errs({ crawl = { { 0.2, 0.4, 1.35 } } }), 0)
		t.truthy(has(errs({ crawl = { { 0.2, 0.4, 1.0 } } }), "crawl"))
		t.truthy(has(errs({ crawl = { { 0.4, 0.2, 1.4 } } }), "crawl"))
		t.truthy(has(errs({ atEnd = { route = 2, t = 2, dir = 1 } }), "atEnd"))
	end)

	t.test("validateSet: links name real routes, end links stay inside, every enclosure has a way in", function()
		local a = {
			id = 1,
			kind = "tunnel",
			length = 20,
			enclosure = rec({ atEnd = { route = 2, t = 0, dir = 1 }, mouths = { { t = 0, opens = "ground" } } }),
		}
		local b = { id = 2, kind = "tunnel", length = 10, enclosure = { id = "test.duct" } }
		t.eq(#Enclosure.validateSet({ a, b }), 0)
		local c = { id = 3, kind = "tunnel", length = 10, enclosure = { id = "test.other" } }
		t.truthy(has(Enclosure.validateSet({ a, b, c }), "has no mouth"))
		local d = {
			id = 4,
			kind = "tunnel",
			length = 10,
			enclosure = rec({ id = "test.d", atEnd = { route = 1, t = 0, dir = 1 } }),
		}
		t.truthy(has(Enclosure.validateSet({ a, b, d }), "leads out of enclosure"))
		local e = {
			id = 5,
			kind = "tunnel",
			length = 10,
			enclosure = rec({
				id = "test.e",
				mouths = { { t = 1, opens = "link", links = { { route = 77, t = 0, dir = 1 } } } },
			}),
		}
		t.truthy(has(Enclosure.validateSet({ e }), "does not exist"))
		t.eq(#Enclosure.validateSet({ e }, { [77] = true }), 0, "a harvested route outside may be named")
		local f = {
			id = 6,
			kind = "tunnel",
			length = 2,
			enclosure = rec({ id = "test.f" }),
		}
		t.truthy(has(Enclosure.validateSet({ f }), "overlap"))
	end)

	t.test("fromRecord: defaults, mouth windows, inside, hidden, zone and headroom", function()
		local spec = Enclosure.fromRecord(rec({ crawl = { { 0.4, 0.6, 1.3 } } }) :: any)
		t.eq(spec.id, "test.duct")
		t.falsy(spec.climb)
		t.truthy(spec.hidden)
		t.eq(spec.width, Enclosure.C.width)
		t.eq(spec.height, Enclosure.C.height)
		t.eq(#spec.mouths, 2)
		t.eq(spec.mouths[1].reach, Enclosure.C.reach)
		local route = { id = 1, kind = "tunnel", length = 40, enclosure = spec }
		-- a 1.2-stud window at each end of a 40-stud route
		t.eq((Enclosure.mouthAt(spec, 40, 0.02) :: any).name, "grille")
		t.eq(Enclosure.mouthAt(spec, 40, 0.04), nil)
		t.eq((Enclosure.endMouth(spec, 40, false) :: any).name, "rack")
		t.falsy(Enclosure.inside(route, 0.01))
		t.truthy(Enclosure.inside(route, 0.5))
		t.truthy(Enclosure.hidden(route, 0.5))
		t.eq(Enclosure.zone(route), "test.duct")
		t.eq(Enclosure.zone({ id = 2, kind = "bridge", length = 5 }), nil)
		local h, crawl = Enclosure.headroom(spec, 0.5)
		t.eq(h, 1.3)
		t.truthy(crawl)
		h, crawl = Enclosure.headroom(spec, 0.1)
		t.eq(h, Enclosure.C.height)
		t.falsy(crawl)
		local open = { id = 3, kind = "branch", length = 9 }
		t.falsy(Enclosure.inside(open, 0.5))
		t.falsy(Enclosure.hidden(open, 0.5))
	end)

	t.test("allows: open routes always; one enclosure always; across a wall only at a mouth that names it", function()
		local inside = Enclosure.fromRecord({
			id = "hollow.T",
			mouths = {
				{ t = 0, opens = "ground" },
				{ t = 0.5, opens = "link", out = { 1, 0, 0 }, links = { { route = 20, t = 0.02, dir = 1 } } },
			},
		})
		local shaft = { id = 10, kind = "tunnel", length = 30, enclosure = inside }
		local landing = {
			id = 11,
			kind = "tunnel",
			length = 4,
			enclosure = Enclosure.fromRecord({ id = "hollow.T" }),
		}
		local bough = { id = 20, kind = "branch", length = 12 }
		local trunk = { id = 21, kind = "trunk", length = 40 }
		local other = { id = 22, kind = "branch", length = 12 }
		t.truthy(Enclosure.allows(bough, 0.5, other, 0.5), "two open routes")
		t.truthy(Enclosure.allows(shaft, 0.3, landing, 0.5), "within one enclosure")
		t.truthy(Enclosure.allows(shaft, 0.5, bough, 0.02), "out through the knothole that names the bough")
		t.truthy(Enclosure.allows(bough, 0.02, shaft, 0.5), "in through it")
		t.falsy(Enclosure.allows(shaft, 0.3, bough, 0.02), "not through the bark away from the knothole")
		t.falsy(Enclosure.allows(trunk, 0.4, shaft, 0.5), "the outside trunk is not named")
		t.falsy(Enclosure.allows(shaft, 0.5, trunk, 0.4))
		t.falsy(Enclosure.allows(shaft, 0.01, trunk, 0.0), "a ground mouth names nothing")
		local otherHollow = {
			id = 30,
			kind = "tunnel",
			length = 10,
			enclosure = Enclosure.fromRecord({ id = "hollow.U", mouths = { { t = 0, opens = "ground" } } }),
		}
		t.falsy(Enclosure.allows(shaft, 0.01, otherHollow, 0.0), "two enclosures never meet unless a mouth says")
	end)

	t.test("the Registry carries the enclosure on a tunnel and refuses a broken one", function()
		local function route(id: number, kind: string, enclosure: any): any
			return {
				id = id,
				name = `r{id}`,
				kind = kind,
				points = { { 0, 0, 0 }, { 0, 0, 10 } },
				length = 10,
				surfaceRadius = 0,
				enclosure = enclosure,
			}
		end
		local reg = Registry.fromRecords({ route(1, "tunnel", rec()), route(2, "bridge", nil) })
		local a = reg:get(1) :: Registry.Route
		t.truthy(a.enclosure ~= nil)
		t.eq((a.enclosure :: Enclosure.Spec).id, "test.duct")
		t.eq((reg:get(2) :: Registry.Route).enclosure, nil)
		t.fails(function()
			Registry.fromRecords({ route(3, "tunnel", nil) }):all()
		end, "needs an enclosure")
		t.fails(function()
			Registry.fromRecords({ route(4, "branch", rec()) }):all()
		end, "only a route of kind")
	end)

	t.test("the attractions schema accepts an enclosed route and refuses a malformed one", function()
		local schema = serde.decode("json", fs.readFile("tools/compile/schema/attractions.schema.json"))
		local doc = serde.decode("json", fs.readFile("data/attractions.json"))
		doc["$schema"] = nil
		local routes = doc.attractions[1].routes
		table.insert(routes, {
			id = 9990,
			name = "schema probe",
			kind = "tunnel",
			surfaceRadius = 0,
			points = { { 0, -3, 70 }, { 0, -3, 60 } },
			enclosure = {
				id = "probe",
				climb = false,
				width = 1.7,
				height = 2.4,
				crawl = { { 0.2, 0.3, 1.3 } },
				atEnd = { route = 9991, t = 0, dir = 1 },
				mouths = {
					{ t = 0, opens = "ground", out = { 0, 0, 1 }, reach = 1.2, rise = 1, name = "grille" },
					{ t = 0.5, opens = "link", out = { 1, 0, 0 }, links = { { route = 9002, t = 0.5, dir = -1 } } },
				},
			},
		})
		t.eq(#Schema.validate(schema, doc), 0)
		routes[#routes].enclosure.mouths[1].opens = "door"
		t.truthy(#Schema.validate(schema, doc) > 0, "unknown opens refused")
		routes[#routes].enclosure.mouths[1].opens = "ground"
		routes[#routes].enclosure.colour = "red"
		t.truthy(#Schema.validate(schema, doc) > 0, "unknown field refused")
	end)
end
