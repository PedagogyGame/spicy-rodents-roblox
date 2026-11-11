--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Games.Fortune
-- Madame Acorna's client half on the minigame framework (Client/Minigames/ClientGame; brief v2 §13a): a short
-- show. On "fortune" the camera goes to the cabinet while the reels spin, then the printed card comes up (a
-- fortune, a taunt or a Grand Omen) and the camera is handed back. E pulls the lever again; the card stays up a
-- moment after the cabinet has freed itself for the next player (linger).
-- Interface: a ClientGame.ClientGame

local Import = require("../../Import")
local AlleyLayout =
	Import.shared("Attractions/AlleyLayout") :: typeof(require("../../../shared/Attractions/AlleyLayout"))
local ClientGame = require("../ClientGame")

local function new(ctx: ClientGame.Ctx): ClientGame.Controller
	return {
		onMessage = function(_self: any, msg: { [string]: any }, _watched: any?)
			if msg.kind ~= "fortune" then
				return
			end
			-- the show: the camera on the cabinet while the reels spin, then the printed card
			local p = ctx.place
			if p then
				local f = AlleyLayout.FORTUNE
				local eye = Vector3.new(AlleyLayout.toWorld(p, f.x - 3.6, 5.2, f.d - 3.6))
				local look = Vector3.new(AlleyLayout.toWorld(p, f.x, 3.4, f.d))
				ctx.camera(CFrame.lookAt(eye, look), 45)
			end
			ctx.ui:status("The reels are spinning...")
			local reveal = tonumber(msg.reveal) or 2.5
			task.delay(reveal, function()
				local title = if msg.card == "omen"
					then "A GRAND OMEN"
					elseif msg.card == "taunt" then "THE MACHINE SAYS"
					else "YOUR FORTUNE"
				ctx.ui:paper(title, tostring(msg.line or ""), 8)
				ctx.ui:status("Pull again (E) or walk away (Q)")
				ctx.releaseCamera()
			end)
		end,
		stop = function(_self: any) end,
	}
end

local entry: ClientGame.ClientGame = {
	game = "fortune_machine",
	help = {
		how = {
			"Madame Acorna reads your fortune for free: no coins, no prizes, never any money.",
			"Three of a kind on the reels is a Grand Omen.",
		},
		keys = { "E  pull the lever again", "Q  walk away" },
	},
	title = function(_msg: { [string]: any }): string
		return "Madame Acorna"
	end,
	buttons = function(phase: string, _view: { [string]: any }?): { { string } }?
		if phase == "joined" then
			return { { "again", "Pull again" }, { "leave", "Walk away (Q)" } }
		end
		return nil
	end,
	keys = { E = "again" },
	new = new,
	placeless = true,
	linger = 5,
}

return entry
