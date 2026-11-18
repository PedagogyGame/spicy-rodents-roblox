--!strict
-- ServerScriptService.Server.Minigames.Games.Paintball
-- Paintball's server half on the minigame framework (Server/Minigames/ServerGame; brief v2 §13): the
-- Table of the arena's station, which is the paintball service (Server/Minigames/Paintball/
-- PaintballService: the match loop, the remotes, hits, splats, the roster, the audience, the pass)
-- with each of the framework's hooks handed to it. The service's header says what every hook does.
-- OWNED BY THE SERVER LANE (the registry's stub: its line in Server/Minigames/ServerGames exists).
-- On a site without the baked arena (every other game's test, a half-baked place) the service is
-- inert and so is this Table: hw = nil, nothing stepped, nothing sent, and a join is refused with
-- "The arena is closed.".
-- Interface: a ServerGame { game = "paintball", new(ctx) -> Table }; Table.hw is the arena's model;
--   Table.service is the PaintballService (specs and the engine check reach it)

local PaintballService = require("../Paintball/PaintballService")
local ServerGame = require("../ServerGame")

local function new(ctx: ServerGame.Ctx): ServerGame.Table
	local service = PaintballService.new(ctx)
	local tbl: ServerGame.Table = {
		hw = service.hw,
		join = function(_self: any, player: any, via: ServerGame.StationDef): (boolean, string?)
			return service:join(player, via)
		end,
		joined = function(_self: any, player: any, seat: number?, via: ServerGame.StationDef)
			service:joined(player, seat, via)
		end,
		command = function(_self: any, player: any, verb: string, args: { any }): (boolean, boolean?, string?)
			return service:command(player, verb, args)
		end,
		input = function(_self: any, player: any, seat: number, verb: string, args: { any }): (boolean?, string?)
			return service:input(player, seat, verb, args)
		end,
		step = function(_self: any, dt: number)
			service:step(dt)
		end,
		event = function(_self: any, e: ServerGame.Event)
			service:event(e)
		end,
		state = function(_self: any, player: any, seat: number?): { [string]: any }?
			return service:state(player, seat)
		end,
		inPlay = function(_self: any, player: any, body: Model?): boolean
			return service:inPlay(player, body)
		end,
		screen = function(_self: any, view: { [string]: any })
			service:screen(view)
		end,
		sig = function(_self: any, view: { [string]: any }): any
			return service:sig(view)
		end,
		prompt = function(_self: any): (string?, string?)
			return service:prompt()
		end,
		doneText = function(_self: any, view: { [string]: any }): string?
			return service:doneText(view)
		end,
		debug = function(_self: any, ...: any): (boolean, string?)
			return service:debug(...)
		end,
	}
	local open = tbl :: any
	open.service = service
	return tbl
end

return { game = "paintball", new = new }
