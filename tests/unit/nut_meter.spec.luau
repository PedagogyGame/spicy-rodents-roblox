--!strict
-- The nut meter on screen (Client/UI/NutMeter; owner D16 #22): what it says for each state the server writes (hidden
-- while the player is not a squirrel; the carried count, amber when full; the tree held and how full; the hollow it
-- is in, grey when another's; a short hint for what to do next, and none when there is nothing to say), the "+1" and
-- "stored 9" beside the count, and where it goes: beside the health bar on a wide screen, in the top-left corner on a
-- phone, clear of the status line, the health bar, the toasts and the touch wallet either way.
local NutMeter = require("@client/UI/NutMeter")
local WalletHud = require("@client/UI/WalletHud")

return function(t)
	t.test("hidden unless the server says the player's squirrel forages", function()
		t.falsy(NutMeter.look({}).visible)
		t.falsy(NutMeter.look({ NutsCarried = 3 }).visible, "no NutsMax: the rodent, a person, the menu")
		t.falsy(NutMeter.look({ NutsMax = "9" }).visible, "a number or nothing")
	end)

	t.test("what it says: the count, the tree, the hollow it is in, the hint", function()
		local none = NutMeter.look({ NutsCarried = 0, NutsMax = 9, NutTree = "", NutStore = 0, NutInside = "" })
		t.truthy(none.visible)
		t.eq(none.count, "0/9")
		t.eq(none.tree, "", "no bar without a tree")
		t.eq(none.hint, "Find nuts: oaks, yards, the park")
		local some = NutMeter.look({ NutsCarried = 4, NutsMax = 9, NutTree = "", NutInside = "" })
		t.eq(some.count, "4/9")
		t.eq(some.hint, "Run them into a hollow tree")
		local full = NutMeter.look({ NutsCarried = 9, NutsMax = 9, NutTree = "", NutInside = "" })
		t.eq(full.countColor[1], 255)
		t.truthy(full.countColor[3] < 100, "amber when full")
		local home = NutMeter.look({ NutsCarried = 0, NutsMax = 9, NutTree = "H4", NutStore = 0.623, NutInside = "" })
		t.eq(home.tree, "H4")
		t.near(home.fill, 0.623, 1e-9)
		t.eq(home.percent, "62%")
		t.eq(home.hint, nil, "nothing to say")
		local going = NutMeter.look({ NutsCarried = 5, NutsMax = 9, NutTree = "H4", NutStore = 0.7, NutInside = "" })
		t.eq(going.hint, "Take them home to H4")
		local fullHome = NutMeter.look({ NutsCarried = 9, NutsMax = 9, NutTree = "H4", NutStore = 0.7 })
		t.eq(fullHome.hint, "Take them home to H4")
		local free = NutMeter.look({ NutsCarried = 9, NutsMax = 9, NutTree = "", NutInside = "H7|0.45|free" })
		t.eq(free.tree, "H7")
		t.eq(free.percent, "45%")
		t.eq(free.hint, "Nobody's: fill to 70% to claim")
		local mine =
			NutMeter.look({ NutsCarried = 0, NutsMax = 9, NutTree = "H7", NutStore = 0.8, NutInside = "H7|0.8|yours" })
		t.eq(mine.hint, "Your tree: nuts go in")
		local taken = NutMeter.look({ NutsCarried = 3, NutsMax = 9, NutTree = "H4", NutInside = "H9|0.92|taken" })
		t.eq(taken.tree, "H9", "the hollow it is in, over its own")
		t.eq(taken.fillColor[1], taken.fillColor[2], "grey")
		t.eq(taken.hint, "Not yours: you keep your nuts")
		local junk = NutMeter.look({ NutsCarried = 2, NutsMax = 9, NutInside = "H9|lots|free", NutStore = "x" })
		t.eq(junk.tree, "", "a malformed attribute shows nothing")
		for _, l in { none, some, home, free, mine, taken } do
			t.truthy(l.hint == nil or #(l.hint :: string) <= 32, `short enough for the pill: {l.hint}`)
		end
	end)

	t.test("beside the count: +1 for each nut, stored 9 into a tree, nothing for a knock-out", function()
		t.eq(NutMeter.flash(nil, 0, ""), nil, "the first draw says nothing")
		t.eq(NutMeter.flash(3, 4, ""), "+1")
		t.eq(NutMeter.flash(4, 4, ""), nil)
		t.eq(NutMeter.flash(9, 0, "H4|0.8|yours"), "stored 9")
		t.eq(NutMeter.flash(9, 0, ""), nil, "dropped (knocked out): the death message says so")
	end)

	t.test(
		"where: beside the health bar on a wide screen, top left on a phone; clear of the rest of the HUD",
		function()
			-- UI/PlayMenu: status 70 % wide at 52..80 down; health bar 300 wide at 84..100; toast 90 % wide from 108
			local function overlaps(a: { number }, b: { number }): boolean
				return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
			end
			for _, size in { { 1920, 1080 }, { 1280, 720 }, { 1024, 768 }, { 667, 375 }, { 568, 320 }, { 844, 390 } } do
				local w = size[1]
				local ax, sx, ox, oy = NutMeter.place(w)
				local left = sx * w + ox - ax * NutMeter.WIDTH
				local pill = { left, oy, left + NutMeter.WIDTH, oy + NutMeter.HEIGHT }
				local short = { left, oy, left + NutMeter.WIDTH, oy + 26 }
				t.truthy(pill[1] >= 8 and pill[3] <= w - 8, `{w}: on the screen`)
				local status = { w * 0.15, 52, w * 0.85, 80 }
				local hp = { w / 2 - 150, 84, w / 2 + 150, 100 }
				t.falsy(overlaps(pill, status), `{w}: the status line`)
				t.falsy(overlaps(pill, hp), `{w}: the health bar`)
				if w >= NutMeter.WIDE then
					t.truthy(pill[1] > hp[3], `{w}: right of the health bar`)
					t.falsy(
						overlaps(short, { w * 0.05, 108, w * 0.95, 144 }),
						`{w}: without a hint, clear of the toasts`
					)
				else
					t.eq(pill[2], 8, `{w}: top left`)
					t.falsy(overlaps(pill, { w * 0.05, 108, w * 0.95, 144 }), `{w}: the toasts`)
					-- the wallet on a touch screen hangs from the top right at WalletHud.TOUCH_TOP
					t.truthy(pill[4] <= WalletHud.TOUCH_TOP, `{w}: above the touch wallet`)
				end
			end
		end
	)
end
