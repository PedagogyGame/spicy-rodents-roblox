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
			length = 0.5,
			enclosure = rec({ id = "test.f" }),
		}
		t.truthy(has(Enclosure.validateSet({ f }), "overlap"), "two end windows of 0.3 on a 0.5-stud route")
		t.eq(#Enclosure.validateSet({ { id = 7, kind = "tunnel", length = 2, enclosure = rec({ id = "test.g" }) } }), 0)
		-- forks stay inside their enclosure and name routes of the set
		local g = {
			id = 8,
			kind = "tunnel",
			length = 20,
			enclosure = rec({ id = "test.duct", forks = { { t = 0.5, route = 2, toT = 0, dir = 1 } } }),
		}
		t.eq(#Enclosure.validateSet({ g, b }), 0)
		local h = {
			id = 9,
			kind = "tunnel",
			length = 20,
			enclosure = rec({ id = "test.h", forks = { { t = 0.5, route = 2, toT = 0, dir = 1 } } }),
		}
		t.truthy(has(Enclosure.validateSet({ h, b }), "leads out of enclosure"))
		t.truthy(has(Enclosure.validateSet({ h }), "not in the set"))
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
		-- an end mouth's window runs 0.3 studs inward from the end (the head out, not the body)
		t.eq(spec.mouths[1].window, Enclosure.C.endWindow)
		t.eq((Enclosure.mouthAt(spec, 40, 0.007) :: any).name, "grille")
		t.eq(Enclosure.mouthAt(spec, 40, 0.01), nil, "0.4 studs in is inside")
		t.eq((Enclosure.mouthAt(spec, 40, 0.993) :: any).name, "rack")
		t.eq(Enclosure.mouthAt(spec, 40, 0.99), nil)
		-- part-way: `reach` either side by default, or the record's window; depth and hop as written
		local side = Enclosure.fromRecord(rec({
			mouths = {
				{ t = 0.5, opens = "link", out = { 1, 0, 0 }, links = { { route = 2, t = 0, dir = 1 } } },
				{ t = 0.8, opens = "air", out = { 0, 0, 1 }, window = 0.5, depth = 2.1, hop = 9, hopUp = 4 },
			},
		}) :: any)
		t.eq(side.mouths[1].window, Enclosure.C.reach)
		t.eq(side.mouths[1].depth, 0)
		t.eq(side.mouths[1].hop, nil)
		t.eq((Enclosure.mouthAt(side, 40, 0.5 + 1.1 / 40) :: any).t, 0.5)
		t.eq(Enclosure.mouthAt(side, 40, 0.5 + 1.3 / 40), nil)
		t.eq(Enclosure.mouthAt(side, 40, 0.8 + 0.6 / 40), nil)
		t.eq(side.mouths[2].depth, 2.1)
		t.eq(side.mouths[2].hop, 9)
		t.eq(side.mouths[2].hopUp, 4)
		t.eq(Enclosure.mouthNear(side, 40, 0.8 + 0.6 / 40, 0.2), side.mouths[2], "widened by the validator's slack")
		t.eq((Enclosure.endMouth(spec, 40, false) :: any).name, "rack")
		t.falsy(Enclosure.inside(route, 0.005))
		t.truthy(Enclosure.inside(route, 0.01), "0.4 studs in from the grille")
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

	t.test(
		"allows: open routes always; inside one enclosure only what is authored; across a wall only at a mouth that names it",
		function()
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
			local pocket = {
				id = 12,
				kind = "tunnel",
				length = 6,
				enclosure = Enclosure.fromRecord({ id = "hollow.T", atStart = { route = 10, t = 0.3, dir = 1 } }),
			}
			local forked = {
				id = 10,
				kind = "tunnel",
				length = 30,
				enclosure = Enclosure.fromRecord({
					id = "hollow.T",
					mouths = { { t = 0, opens = "ground" } },
					forks = { { t = 0.3, route = 12, toT = 0, dir = 1 } },
				}),
			}
			local bough = { id = 20, kind = "branch", length = 12 }
			local trunk = { id = 21, kind = "trunk", length = 40 }
			local other = { id = 22, kind = "branch", length = 12 }
			t.truthy(Enclosure.allows(bough, 0.5, other, 0.5), "two open routes")
			t.falsy(
				Enclosure.allows(shaft, 0.3, landing, 0.5),
				"one enclosure is not enough: nothing authored joins them"
			)
			t.truthy(Enclosure.allows(forked, 0.3, pocket, 0), "a fork joins them at its point")
			t.truthy(Enclosure.allows(pocket, 0.02, forked, 0.31), "and the pocket's start link back")
			t.falsy(Enclosure.allows(forked, 0.6, pocket, 0), "not 9 studs along from the fork")
			t.falsy(Enclosure.allows(forked, 0.3, pocket, 0.9), "not to the far end of the pocket")
			t.truthy(Enclosure.linked(forked, pocket))
			t.falsy(Enclosure.linked(shaft, landing))
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
		end
	)

	t.test("validate: forks, the section's up, the cavity, a mouth's window, depth and hop", function()
		local function errs(over: { [string]: any }): { string }
			return Enclosure.validate(rec(over), "tunnel")
		end
		t.eq(#errs({ forks = { { t = 0.4, route = 2, toT = 0, dir = 1, name = "hideout" } } }), 0)
		t.truthy(has(errs({ forks = { { t = 0.4, route = 2, toT = 2, dir = 1 } } }), "forks[1]"))
		t.truthy(has(errs({ climb = true }), "climb needs up"), "a climb says which side the wall is")
		t.eq(#errs({ climb = true, up = { 0, 0, -1 } }), 0)
		t.eq(#errs({ climb = true, upAt = { { 0, 0, 0, -1 }, { 1, 1, 0, 0 } } }), 0)
		t.truthy(has(errs({ up = { 0, 2, 0 } }), "enclosure.up must be a unit"))
		t.truthy(has(errs({ upAt = { { 2, 0, 1, 0 } } }), "upAt[1]"))
		t.eq(#errs({ cavity = { axis = { 3, 4 }, radius = 2.5, bottom = 0, top = 30 } }), 0)
		t.truthy(has(errs({ cavity = { axis = { 3 }, radius = 2.5 } }), "cavity"))
		t.truthy(has(errs({ cavity = { axis = { 3, 4 }, radius = 0 } }), "cavity"))
		t.truthy(has(errs({ mouths = { { t = 0, opens = "ground", window = 0 } } }), "window"))
		t.truthy(has(errs({ mouths = { { t = 0, opens = "ground", depth = -1 } } }), "depth"))
		t.truthy(has(errs({ mouths = { { t = 1, opens = "ledge", hop = -2 } } }), "hop"))
		t.eq(#errs({ mouths = { { t = 1, opens = "ledge", hop = 10, hopUp = 8, depth = 0.2, window = 0.4 } } }), 0)
	end)

	t.test("upAt: the authored section up, interpolated between keys and held past them; exits in t order", function()
		local spec = Enclosure.fromRecord(rec({ upAt = { { 0.6, 0, 0, 1 }, { 0.2, 0, 1, 0 } } }) :: any)
		local a = Enclosure.upAt(spec, 0) :: any
		t.eq(a.y, 1, "held before the first key")
		local m = Enclosure.upAt(spec, 0.4) :: any
		t.near(m.y, math.sqrt(0.5), 1e-9)
		t.near(m.z, math.sqrt(0.5), 1e-9)
		t.eq((Enclosure.upAt(spec, 1) :: any).z, 1)
		t.eq(Enclosure.upAt(Enclosure.fromRecord(rec()), 0.5), nil, "none authored: the default applies")
		local whole = Enclosure.fromRecord(rec({ up = { 1, 0, 0 } }) :: any)
		t.eq((Enclosure.upAt(whole, 0.7) :: any).x, 1)
		local exits = Enclosure.exits(
			Enclosure.fromRecord(rec({
				forks = { { t = 0.7, route = 5, toT = 0, dir = 1 } },
				mouths = {
					{ t = 0, opens = "ground" },
					{ t = 0.3, opens = "link", out = { 1, 0, 0 }, links = { { route = 6, t = 0.1, dir = -1 } } },
				},
			}) :: any),
			20
		)
		t.eq(#exits, 2)
		t.eq(exits[1].route, 6)
		t.truthy(exits[1].mouth ~= nil, "a part-way link mouth")
		t.eq(exits[2].route, 5)
		t.eq(exits[2].mouth, nil, "a fork")
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
				forks = { { t = 0.4, route = 9992, toT = 0, dir = 1, name = "side duct" } },
				up = { 0, 1, 0 },
				upAt = { { 0.5, 0, 1, 0 }, { 0.9, 0, 0, 1 } },
				cavity = { axis = { 0, 60 }, radius = 2, bottom = -4, top = 2 },
				mouths = {
					{
						t = 0,
						opens = "ground",
						out = { 0, 0, 1 },
						reach = 1.2,
						rise = 1,
						window = 0.3,
						depth = 0.1,
						name = "grille",
					},
					{ t = 1, opens = "ledge", hop = 10, hopUp = 8.6 },
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
