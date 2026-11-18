--!strict
-- Sitting in THE GILDED ACORN: the seats (Shared/Attractions/LoungeClassic.SEATS) are where the bake builds the
-- stools, booths, club chairs and armchairs (tools/bake/lounge_classic/Style and Interior), each inside the room and
-- clear of the others; getting up (standUp). The service's half (Server/Attractions/LoungeService, Client/World/
-- SeatGetUp) runs on a fake engine in tests/isolated/lounge_seats.luau, in its own Lune process (tests/lib/Isolated
-- says why); each case is reported here as its own test.
local LoungeClassic = require("@shared/Attractions/LoungeClassic")
local Style = require("../../tools/bake/lounge_classic/Style")
local Isolated = require("@tests/lib/Isolated")

return function(t)
	t.test("seven stools, four booths of four, eight club chairs, two armchairs; ids unique", function()
		local n: { [string]: number } = {}
		local ids: { [string]: boolean } = {}
		for _, s in LoungeClassic.SEATS do
			n[s.kind] = (n[s.kind] or 0) + 1
			t.falsy(ids[s.id], `id {s.id} twice`)
			ids[s.id] = true
			t.truthy((LoungeClassic.SEAT_WORDS :: any)[s.kind], `words for {s.kind}`)
			t.near(s.fx * s.fx + s.fd * s.fd, 1, 1e-9, "faces one way")
		end
		t.eq(n.stool, 7)
		t.eq(n.booth, 16)
		t.eq(n.club, 8)
		t.eq(n.armchair, 2)
	end)

	t.test("each seat is on the bake's furniture, inside the room, and a person's width from the next", function()
		for _, s in LoungeClassic.SEATS do
			t.truthy(LoungeClassic.inside(s.x, s.y, s.d), `{s.id} inside`)
			if s.kind == "stool" then
				t.near(s.d, Style.STOOLS_D, 1e-9)
				t.near(s.x / Style.STOOL_GAP, math.floor(s.x / Style.STOOL_GAP + 0.5), 1e-9, "on a stool")
				t.near(s.y, 2.38 + 0.36 / 2, 1e-9, "the stool's cushion top")
				t.eq(s.fd, 1, "facing the bar")
			elseif s.kind == "booth" then
				local ax = math.abs(s.x)
				t.truthy(ax > Style.BOOTH_X0 and ax < Style.BOOTH_X1, `{s.id} on its bench`)
				local found = false
				for _, b in Style.BOOTHS do
					local side = (s.d - b[2]) / 2.9
					if math.sign(b[1]) == math.sign(s.x) and math.abs(math.abs(side) - 1) < 1e-9 then
						found = true
						t.near(s.fd, -side, 1e-9, "facing the table")
					end
				end
				t.truthy(found, `{s.id} at a booth`)
				t.near(s.y, 1.7, 1e-9, "the bench's top")
			elseif s.kind == "club" then
				local found = false
				for _, tb in Style.TABLES do
					if math.abs(s.d - tb[2]) < 1e-9 and math.abs(math.abs(s.x - tb[1]) - 2.4) < 1e-9 then
						found = true
						t.eq(s.fx, -math.sign(s.x - tb[1]), "facing the table")
					end
				end
				t.truthy(found, `{s.id} by a table`)
				t.near(s.y, 1.5, 1e-9)
			else
				t.near(math.abs(s.d - Style.FIRE_D), 4.2, 1e-9, "either side of the fire")
				t.near(s.x, Style.INNER_X - 5.5 + 0.2, 1e-9, "the armchair's cushion")
				t.eq(s.fx, 1, "facing the fire")
			end
			for _, o in LoungeClassic.SEATS do
				if o ~= s then
					local dx, dd = o.x - s.x, o.d - s.d
					t.truthy(dx * dx + dd * dd >= 2.4 * 2.4, `{s.id} and {o.id} too close`)
				end
			end
		end
	end)

	t.test("standing up: a jump or a move past the stick's rest", function()
		t.truthy(LoungeClassic.standUp(0, 0, true))
		t.truthy(LoungeClassic.standUp(0, -1, false))
		t.truthy(LoungeClassic.standUp(0.3, 0, false))
		t.falsy(LoungeClassic.standUp(0.1, 0.1, false))
		t.falsy(LoungeClassic.standUp(0, 0, false))
	end)

	Isolated.register(t, "tests/isolated/lounge_seats")
end
