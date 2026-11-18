--!strict
-- Minigames/WhackAMole/Layout and Spec: the owner's cabinet at his size (1 / 0.28 studs a metre, about 7.7 studs
-- tall like the pinball cabinets), and its place in the games room: its own floor for the player and the people
-- watching, inside the room and clear of every other table's floor, the room's fixtures, the doorways, the staff
-- posts and a body's width off every staff route (the same tests AlleyLayout's own tables and fixtures meet,
-- tests/unit/attractions_alley.spec.luau; AlleyLayout is read, not edited).
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Layout = require("@shared/Minigames/WhackAMole/Layout")
local Spec = require("@shared/Minigames/WhackAMole/Spec")
local Test = require("../lib/Test")

return function(t: Test.T)
	t.test("his size: 7.7 studs tall, the deck about 4 up, five holes inside the deck with room between", function()
		t.near(Layout.SIGN.v1, 2.16 / 0.28, 1e-9)
		t.truthy(Layout.SIGN.v1 > 7.5 and Layout.SIGN.v1 < 7.9, `{Layout.SIGN.v1} studs tall`)
		t.truthy(Layout.DECK.top > 3.8 and Layout.DECK.top < 4.1)
		t.eq(#Layout.HOLES, 5)
		local d = Layout.DECK
		for i, h in Layout.HOLES do
			local outer = d.lipR + d.lipTube
			t.truthy(math.abs(h[1]) + outer < d.insertHalfU, `hole {i} inside the deck across`)
			t.truthy(h[2] - outer > d.insertW0 and h[2] + outer < d.insertW1, `hole {i} inside the deck front to back`)
			for j = i + 1, 5 do
				local o = Layout.HOLES[j]
				t.truthy(math.sqrt((h[1] - o[1]) ^ 2 + (h[2] - o[2]) ^ 2) > 2 * outer, `holes {i} and {j} apart`)
			end
		end
		-- back row 1, 2, 3 from the player's left; front row 4, 5
		t.truthy(Layout.HOLES[1][1] < Layout.HOLES[2][1] and Layout.HOLES[2][1] < Layout.HOLES[3][1])
		t.truthy(Layout.HOLES[4][2] < Layout.HOLES[1][2], "4 and 5 nearer the player")
		-- a raised mole's head clears the deck; at rest it is below it
		local m = Layout.MOLE
		t.truthy(m.topV < Layout.DECK.top, "hidden at rest")
		t.truthy(m.headV + m.pop > Layout.DECK.top, "the head's middle is above the deck when it is up")
		t.truthy(m.bodyV - m.bodyHalfV + m.pop < Layout.DECK.top, "the body's foot stays in the well")
		t.truthy(m.bodyR < Layout.DECK.holeR and m.headR < Layout.DECK.holeR, "a mole fits its hole")
	end)

	t.test("the frames: the player's left is +X, the sign is toward the wall, the deck faces into the room", function()
		local X1 = Layout.toSite(Layout.HOLES[1][1], 0, 0)
		local X3 = Layout.toSite(Layout.HOLES[3][1], 0, 0)
		t.truthy(X1 > X3, "hole 1 is on +X: the left of a player who faces -D")
		local _, _, Dsign = Layout.toSite(0, 0, Layout.SIGN.w1)
		local _, _, Dfront = Layout.toSite(0, 0, Layout.DECK.w0)
		t.truthy(Dsign < Dfront)
		t.near(Dsign, AlleyLayout.GAME_ROOM_D0 + 1, 1e-9, "one stud off the front wall, like the pinball machines")
		local u, v, w = Layout.toCabinet(Layout.toSite(1.5, 2.5, -3.5))
		t.near(u, 1.5, 1e-9)
		t.near(v, 2.5, 1e-9)
		t.near(w, -3.5, 1e-9)
	end)

	t.test("its floor in the games room: clear of the tables, fixtures, doorways, posts and staff routes", function()
		local L = AlleyLayout
		local g = L.zone("games_room")
		local a = Layout.STANDING
		t.truthy(a.x0 >= g.x0 and a.x1 <= g.x1 and a.d0 >= g.d0 and a.d1 <= g.d1, "inside the room")
		local function over(b: { x0: number, x1: number, d0: number, d1: number }, pad: number): boolean
			return math.min(a.x1, b.x1) - math.max(a.x0, b.x0) > -pad
				and math.min(a.d1, b.d1) - math.max(a.d0, b.d0) > -pad
		end
		for _, s in L.standing() do
			t.falsy(over(s, -0.01), `on {s.id}'s floor`)
		end
		for _, f in L.GAMES_FIXTURES do
			t.falsy(over(f, -0.01), `on the {f.id}`)
		end
		for _, o in L.OPENINGS do
			if o.axis == "d" and o.at == L.GAME_ROOM_X0 then
				t.falsy(a.x0 < g.x0 + 4 and math.min(a.d1, o.b) - math.max(a.d0, o.a) > -0.5, `in {o.id}`)
			end
		end
		for _, p in L.POSTS do
			t.falsy(p.x > a.x0 - 1 and p.x < a.x1 + 1 and p.d > a.d0 - 1 and p.d < a.d1 + 1, `on post {p.id}`)
		end
		for id, pts in L.ROUTES do
			for i = 2, #pts do
				local p, q = pts[i - 1], pts[i]
				for k = 0, 40 do
					local X = p[1] + (q[1] - p[1]) * k / 40
					local D = p[2] + (q[2] - p[2]) * k / 40
					local near = X > a.x0 - 1.05 and X < a.x1 + 1.05 and D > a.d0 - 1.05 and D < a.d1 + 1.05
					t.falsy(near, `in the way of route {id} at X {X} D {D}`)
				end
			end
		end
		-- the cabinet and its mallet are on its own floor, the player's spot and the prompt in front of it
		local function inside(X: number, D: number): boolean
			return X >= a.x0 and X <= a.x1 and D >= a.d0 and D <= a.d1
		end
		for _, c in
			{
				{ Layout.BODY.halfU, Layout.SIGN.w1 },
				{ -Layout.SIGN.halfU, Layout.DECK.w0 },
				{ Layout.MALLET.rest[1] + Layout.MALLET.headLen, Layout.MALLET.rest[3] },
				{ Layout.STAND.u, Layout.STAND.w },
			}
		do
			local X, _, D = Layout.toSite(c[1], 0, c[2])
			t.truthy(inside(X, D), `({c[1]}, {c[2]}) on its floor`)
		end
		local X, _, D = Layout.toSite(Layout.STAND.u, 0, Layout.STAND.w)
		t.truthy(L.floorAt(X, D) ~= nil, "the player stands on the floor")
	end)

	t.test("the station: one prompt in front of the cabinet, on the alley only, within reach of the player", function()
		t.eq(#Spec.stations({}), 0)
		local list = Spec.stations({ bowling_alley = { x = 0, z = 0, floorY = 0, yaw = 0 } })
		t.eq(#list, 1)
		local st = list[1]
		t.eq(st.game, "whack_a_mole")
		t.eq(st.site, "bowling_alley")
		local X, _, D = Layout.toSite(Layout.STAND.u, 0, Layout.STAND.w)
		t.truthy(math.sqrt((st.x - X) ^ 2 + (st.d - D) ^ 2) < (st.reach or 70) - 4, "standing to play is in reach")
		local a = Layout.STANDING
		t.truthy(st.x > a.x0 and st.x < a.x1 and st.d > a.d0 and st.d < a.d1)
	end)

	t.test("the camera: the deck, the five holes and both windows on screens from 4:3 to a wide phone", function()
		for _, aspect in { 4 / 3, 16 / 10, 16 / 9, 19.5 / 9, 21 / 9 } do
			local eye, look, fov = Layout.camera(aspect)
			t.truthy(fov > Layout.FOV_MIN - 1e-9 and fov < Layout.FOV_MAX, `fov {fov} at {aspect}`)
			t.truthy(eye[2] > Layout.SIGN.v1 and eye[3] < Layout.DECK.w0, "from above and behind the player's head")
			t.truthy(look[2] > Layout.DECK.top)
			local half = math.tan(math.rad(fov) / 2)
			local points = Layout.framePoints()
			for i = 1, 5 do
				local u, v, w = Layout.hole(i)
				table.insert(points, { u, v + Layout.MOLE.pop, w })
			end
			for _, p in points do
				local x, y, z = Layout.inCamera(p)
				t.truthy(z > 0, "ahead of the eye")
				t.truthy(math.abs(y) / z < half and math.abs(x) / z < half * aspect, `({p[1]}, {p[2]}, {p[3]}) in view`)
			end
		end
	end)
end
