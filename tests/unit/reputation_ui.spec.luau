--!strict
-- Owner D30: reputation "checkable with money, in paused and or side screen", never a constant meter. The menu's line
-- (Client/UI/PlayMenu.standingLine) and the wallet stack's (Client/UI/WalletHud: only while the menu is open); the
-- engine cases (the server's attribute and notice, the stack on a fake engine) are tests/isolated/reputation_ui.luau.
local Isolated = require("@tests/lib/Isolated")
local PlayMenu = require("@client/UI/PlayMenu")
local WalletHud = require("@client/UI/WalletHud")
local fs = require("@lune/fs")

return function(t)
	Isolated.register(t, "tests/isolated/reputation_ui")

	t.test("the pause menu: money and reputation on one line, drawn in the menu's panel on every refresh", function()
		t.eq(PlayMenu.standingLine({ Cents = 300, Reputation = 0 }), "Money  S$3.00   ·   Reputation  Good (0)")
		t.eq(
			PlayMenu.standingLine({ Cents = 12345, Reputation = -30 }),
			"Money  S$123.45   ·   Reputation  Poor (-30)"
		)
		t.eq(PlayMenu.standingLine({}), "Money  --   ·   Reputation  Good (0)", "before the server has written either")
		t.eq(PlayMenu.standingLine({ Cents = "x", Reputation = "y" }), "Money  --   ·   Reputation  Good (0)")
		local src = fs.readFile("src/client/UI/PlayMenu.luau")
		t.truthy(string.find(src, 'Name = "Standing"', 1, true), "a label in the panel")
		t.truthy(string.find(src, "standing.Text = PlayMenu.standingLine(a)", 1, true), "refreshed with the attributes")
	end)

	t.test("the wallet stack: the line only with the menu open, the stack in sight and money to sit by", function()
		t.eq(WalletHud.standingText(5), "Reputation  Good (+5)")
		t.eq(WalletHud.standingText(nil), "Reputation  Good (0)")
		t.truthy(WalletHud.showStanding(true, true, true))
		t.falsy(WalletHud.showStanding(false, true, true), "never on the HUD in play")
		t.falsy(WalletHud.showStanding(true, false, true), "the stack hidden under the menu on a narrow screen")
		t.falsy(WalletHud.showStanding(true, true, false), "no wallet yet")
	end)
end
