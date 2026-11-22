--!strict
-- tests/isolated/reputation_ui.luau: cases for tests/unit/reputation_ui.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Owner D30: reputation "should just show you that, then go away, not be a constant meter, but be checkable with money,
-- in paused and or side screen". The real Server/Reputation/ReputationService writing the Player attribute and the
-- notice through the game's channel, and the real Client/UI/WalletHud drawing it beside the money only while the role
-- menu (M, the pause screen) is open.
-- Interface: return function(t) (the spec shape)
local ReputationService = require("@server/Reputation/ReputationService")
local Reputation = require("@shared/Reputation/Reputation")
local WalletHud = require("@client/UI/WalletHud")
local FakeEngine = require("@tests/lib/FakeEngine")
local roblox = require("@lune/roblox")

return function(t)
	t.test(
		"the server: the attribute at join, the drop's notice to that player alone, Reputation.report bound",
		function()
			FakeEngine.with(function()
				local Players = (game :: any):GetService("Players")
				local me = Players.LocalPlayer
				local sent: { { any } } = {}
				local s = ReputationService.start({
					fire = function(player: any, payload: { [string]: any })
						table.insert(sent, { player, payload })
					end,
					players = false,
				})
				s.join(me)
				t.eq(me:GetAttribute(ReputationService.ATTRIBUTE), 0)
				t.truthy(Reputation.bound())
				t.eq(Reputation.report(me, "errand_theft", 2), true)
				t.eq(me:GetAttribute("Reputation"), -10)
				t.eq(#sent, 1)
				t.eq(sent[1][1], me)
				t.eq(sent[1][2].kind, "notice", "the brief toast every notice uses (a few seconds, then gone)")
				t.eq(sent[1][2].text, "Reputation down: you kept an errand's delivery for yourself (now Fair)")
				Reputation.bind(nil)
			end)
		end
	)

	t.test(
		"the side screen: the reputation line by the balance only while the menu is open; it follows changes",
		function()
			FakeEngine.with(function()
				local player = (game :: any):GetService("Players").LocalPlayer
				local heartbeat = (game :: any):GetService("RunService").Heartbeat
				local camera = (workspace :: any).CurrentCamera
				rawset(camera, "ViewportSize", roblox.Vector2.new(1920, 1080))
				player:SetAttribute("Cents", 300)
				player:SetAttribute("Reputation", 0)
				local hud = WalletHud.start({ daySeconds = 720 })
				heartbeat.fire(1 / 60)
				t.truthy(hud.balance.Visible)
				t.falsy(hud.standing.Visible, "no constant meter on the HUD")
				t.truthy(
					hud.standing.LayoutOrder > hud.pass.LayoutOrder
						and hud.standing.LayoutOrder < hud.balance.LayoutOrder
				)
				local play = FakeEngine.new("ScreenGui", WalletHud.MENU_GUI)
				play.Parent = player:FindFirstChild("PlayerGui")
				local menu = FakeEngine.new("Frame", WalletHud.MENU)
				menu.Visible = true
				menu.Parent = play
				heartbeat.fire(1 / 60)
				t.truthy(hud.standing.Visible, "checkable with the money while paused")
				t.eq(hud.standing.Text, "Reputation  Good (0)")
				player:SetAttribute("Reputation", -12)
				t.eq(hud.standing.Text, "Reputation  Fair (-12)")
				menu.Visible = false
				heartbeat.fire(1 / 60)
				t.falsy(hud.standing.Visible, "gone with the menu")
				hud.stop()
			end)
		end
	)
end
