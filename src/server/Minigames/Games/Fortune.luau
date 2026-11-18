--!strict
-- ServerScriptService.Server.Minigames.Games.Fortune
-- Madame Acorna's server half on the minigame framework (Server/Minigames/ServerGame; brief v2 §13a): the Table
-- around the FortuneCabinet in the bowling alley's fern corner. Every press of the prompt is a pull of the
-- lever: a fresh one-seat game whose single input is the pull, and whose result is the card (a fortune, a
-- taunt or a Grand Omen; never money). While the reels of the last pull are still turning the next is refused
-- with words; a card someone else left on the table belongs to whoever pulls now ("left", why "next").
-- "again" and "pull" from the seated player are the same press. The player is sent a "fortune" message: the
-- reels, the line, the kind of card, and how long the reels take.
-- Interface: a ServerGame { game = "fortune_machine", new(ctx) -> Table }; Table.hw is the FortuneCabinet

local Import = require("../../Import")
local Session = Import.shared("Minigames/Session") :: typeof(require("../../../shared/Minigames/Session"))
local FortuneCabinet = require("../FortuneCabinet")
local ServerGame = require("../ServerGame")

local Fortune = {}
Fortune.__index = Fortune

local function new(ctx: ServerGame.Ctx): ServerGame.Table
	local self = setmetatable({}, Fortune) :: any
	self.ctx = ctx
	local games = ctx.root and (ctx.root :: Instance):FindFirstChild("GamesRoom")
	self.hw = FortuneCabinet.new({ model = games and games:FindFirstChild("Fortune") })
	return self
end

function Fortune.join(self: any, player: any): (boolean, string?)
	local ctx = self.ctx
	local s = ctx.session
	if self.hw:busy() then
		return false, "Madame Acorna is still reading the last palm: one moment"
	end
	if s.phase ~= "idle" then
		-- someone else's card is on the table; it belongs to whoever pulls now
		for _, p in ctx.seated() do
			if p ~= player then
				ctx.leave(p, "next")
			end
		end
		Session.reset(s)
	end
	return true
end

function Fortune.joined(self: any, player: any, _seat: number?)
	local ctx = self.ctx
	local s = ctx.session
	local ok = ctx.apply(player, "pull", nil)
	if not ok then
		return
	end
	local r = s.result
	if r then
		self.hw:pull(r)
	end
	ctx.send(player, {
		kind = "fortune",
		station = ctx.station.id,
		reels = r and r.reels,
		line = r and r.line,
		card = r and r.kind,
		reveal = FortuneCabinet.SHOW_SECONDS,
	})
end

function Fortune.command(self: any, player: any, verb: string, _args: { any }): (boolean, boolean?, string?)
	if verb == "again" or verb == "pull" then
		local ok, why = self.ctx.join(player)
		return true, ok, why
	end
	return false
end

function Fortune.step(self: any, dt: number)
	self.hw:step(dt)
end

-- (the fortune teller's card is its own ending)
function Fortune.doneText(_self: any, _view: { [string]: any }): string?
	return ""
end

local entry: ServerGame.ServerGame = { game = "fortune_machine", new = new }

return entry
