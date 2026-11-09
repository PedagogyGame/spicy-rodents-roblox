--!strict
-- Routes/Curve golden tests (spike S3; BUILD_PLAN §6.2 "Routes/*", §6.3).
-- (1) tests/golden/curves.json: 200 harvested routes rebuilt with npm three@0.160.1 (lengths at 200
--     divisions, getUtoTmapping, getPoint, getPointAt, getTangentAt, getSpacedPoints).
-- (2) data/harvest/routes.json + route_samples.json: every one of the 1,332 routes, the game's own
--     `curve.getSpacedPoints(max(20, ceil(3L)))` samples, within 0.01 u (0.025 st) as the plan demands.
-- Everything here is in HTML units: the curve maths is unit-agnostic.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Curve = require("@shared/Routes/Curve")

local function dist(a: Curve.Vec3, b: { number }): number
	local dx, dy, dz = a.x - b[1], a.y - b[2], a.z - b[3]
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

return function(t)
	local golden = serde.decode("json", fs.readFile("tests/golden/curves.json"))

	t.test("golden curves.json: 200 routes, 200-division length tables match to 1e-9", function()
		t.eq(golden.count, 200)
		local maxLenDiff = 0
		for _, rec in golden.routes do
			local curve = Curve.fromArrays(rec.points)
			t.eq(curve.arcLengthDivisions, rec.arcLengthDivisions, rec.name)
			local lengths = curve:getLengths()
			t.eq(#lengths, #rec.lengths200, rec.name)
			for i, l in rec.lengths200 do
				maxLenDiff = math.max(maxLenDiff, math.abs(lengths[i] - l))
			end
			maxLenDiff = math.max(maxLenDiff, math.abs(curve:getLength() - rec.length))
		end
		print(`      curves.json max |length table diff| = {maxLenDiff}`)
		t.truthy(maxLenDiff <= 1e-9, `max length diff {maxLenDiff}`)
	end)

	t.test("golden curves.json: getSpacedPoints within 0.01 u (steps from the harvest rule)", function()
		local maxDiff = 0
		for _, rec in golden.routes do
			local curve = Curve.fromArrays(rec.points)
			t.eq(Curve.sampleSteps(rec.length), rec.steps, rec.name)
			local pts = curve:getSpacedPoints(rec.steps)
			t.eq(#pts, #rec.spacedPoints, rec.name)
			for i, p in rec.spacedPoints do
				maxDiff = math.max(maxDiff, dist(pts[i], p))
			end
		end
		print(`      curves.json max spaced-point deviation = {maxDiff} u`)
		t.truthy(maxDiff <= 0.01, `max deviation {maxDiff} u`)
	end)

	t.test("golden curves.json: getUtoTmapping, getPoint, getPointAt, getTangentAt at 31 parameters", function()
		local maxT, maxP, maxPA, maxTan = 0, 0, 0, 0
		for _, rec in golden.routes do
			local curve = Curve.fromArrays(rec.points)
			for _, at in rec.at do
				maxT = math.max(maxT, math.abs(curve:getUtoTmapping(at.t) - at.u2t))
				maxP = math.max(maxP, dist(curve:getPoint(at.t), at.point))
				maxPA = math.max(maxPA, dist(curve:getPointAt(at.t), at.pointAt))
				maxTan = math.max(maxTan, dist(curve:getTangentAt(at.t), at.tangentAt))
			end
		end
		print(`      u->t {maxT}, point {maxP} u, pointAt {maxPA} u, tangentAt {maxTan}`)
		t.truthy(maxT <= 1e-9, `u->t {maxT}`)
		t.truthy(maxP <= 1e-9, `getPoint {maxP}`)
		t.truthy(maxPA <= 1e-9, `getPointAt {maxPA}`)
		t.truthy(maxTan <= 1e-6, `getTangentAt {maxTan}`)
	end)

	t.test("all 1,332 harvested routes: samples within 0.01 u of data/harvest/route_samples.json", function()
		local routes = serde.decode("json", fs.readFile("data/harvest/routes.json")).routes
		local samples = serde.decode("json", fs.readFile("data/harvest/route_samples.json")).samples
		t.eq(#routes, 1332)
		t.eq(#samples, 1332)
		local byId: { [number]: { { number } } } = {}
		for _, entry in samples do
			byId[entry[1]] = entry[2]
		end
		local maxDiff, maxLenDiff, total = 0, 0, 0
		for _, rec in routes do
			local curve = Curve.fromArrays(rec.points)
			maxLenDiff = math.max(maxLenDiff, math.abs(curve:getLength() - rec.length))
			-- sampleCount comes from the harvest record (w0_check §6.6), never recomputed from our length.
			local pts = curve:getSpacedPoints(rec.sampleCount - 1)
			local expected = byId[rec.id]
			t.eq(#pts, #expected, `route {rec.id} sample count`)
			for i, p in expected do
				maxDiff = math.max(maxDiff, dist(pts[i], p))
			end
			total += #pts
		end
		print(`      1,332 routes / {total} samples: max deviation {maxDiff} u, max |length diff| {maxLenDiff} u`)
		t.eq(total, 81613, "spatial-index sample total")
		t.truthy(maxDiff <= 0.01, `max deviation {maxDiff} u`)
	end)

	t.test("Curve.new rejects fewer than 2 points and non-finite coordinates (addRoute L295-301)", function()
		t.fails(function()
			Curve.new({ Curve.vec3(0, 0, 0) })
		end, "at least 2")
		t.fails(function()
			Curve.new({ Curve.vec3(0, 0, 0), Curve.vec3(0 / 0, 1, 1) })
		end, "non%-finite")
		t.fails(function()
			Curve.new({ Curve.vec3(0, 0, 0), Curve.vec3(math.huge, 1, 1) })
		end, "non%-finite")
	end)

	t.test("repeated control points take the three.js safety path (dt1 -> 1)", function()
		local curve = Curve.new({ Curve.vec3(0, 0, 0), Curve.vec3(0, 0, 0), Curve.vec3(1, 0, 0) })
		local p = curve:getPointAt(1)
		t.near(p.x, 1, 1e-9)
		t.truthy(curve:getLength() > 0)
	end)
end
