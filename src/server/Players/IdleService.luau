--!strict
-- ServerScriptService.Server.Players.IdleService
-- The idle kick (owner D38; the rules and what counts as input: Shared/Players/IdleRules). Boot/Game makes one and
-- steps it once a second; every piece of input evidence calls touch(player): the client's "still here" ping
-- (PlayNet.Here), the PlayNet presses, the Net remotes in IdleRules.INTENT, chat, and a held squirrel's motor packets
-- that show a key down (IdleRules.motorActive). A player is first seen by step (joined: the clock starts then) and
-- forgotten by leave (PlayerRemoving).
-- Each step, for every player: the verdict by the time since their last input and their role NOW (opts.spicy): "warn"
-- sends the quiet notice once (opts.tell(player, { kind = "idle", text, secs })), "kick" removes them (opts.kick with
-- IdleRules.kickText); back to "ok" (input, or a role with a longer limit) clears a notice still showing
-- (opts.tell(player, { kind = "idle", clear = true })).
-- Cost: one table read and a subtraction a player a second; touch is one assignment.
-- Interface: new(opts) -> Service; :touch(player); :step(); :leave(player); :idleFor(player) -> seconds?.
-- Pure: the engine is opts' (players, now, spicy, tell, kick). No side effects on require.

local Import = require("../Import")
local IdleRules = Import.shared("Players/IdleRules") :: typeof(require("../../shared/Players/IdleRules"))

local IdleService = {}
IdleService.__index = IdleService

export type Opts = {
	players: () -> { any }, -- the players in the server now
	now: () -> number, -- seconds (any steady clock)
	spicy: (player: any) -> boolean, -- the player is the Spicy Rodent now
	tell: (player: any, msg: { [string]: any }) -> (), -- one PlayNet event to the player (the "idle" notice)
	kick: (player: any, text: string) -> (),
	enabled: (() -> boolean)?, -- Config/Flags idleKick (default on)
}

type Seen = { last: number, warned: boolean }

export type Service = typeof(setmetatable(
	{} :: {
		opts: Opts,
		seen: { [any]: Seen },
	},
	IdleService
))

function IdleService.new(opts: Opts): Service
	return setmetatable({ opts = opts, seen = {} }, IdleService)
end

-- touch: the player pressed something (any evidence); a notice still showing is cleared
function IdleService.touch(self: Service, player: any)
	local s = self.seen[player]
	if s == nil then
		self.seen[player] = { last = self.opts.now(), warned = false }
		return
	end
	s.last = self.opts.now()
	if s.warned then
		s.warned = false
		self.opts.tell(player, { kind = "idle", clear = true })
	end
end

function IdleService.leave(self: Service, player: any)
	self.seen[player] = nil
end

function IdleService.idleFor(self: Service, player: any): number?
	local s = self.seen[player]
	return if s then self.opts.now() - s.last else nil
end

-- step: once a second or slower
function IdleService.step(self: Service)
	if self.opts.enabled and not self.opts.enabled() then
		return
	end
	local now = self.opts.now()
	for _, player in self.opts.players() do
		local s = self.seen[player]
		if s == nil then
			self.seen[player] = { last = now, warned = false }
			continue
		end
		local spicy = self.opts.spicy(player)
		local v = IdleRules.verdict(s.last, now, spicy)
		if v == "kick" then
			self.seen[player] = nil
			self.opts.kick(player, IdleRules.kickText(spicy))
		elseif v == "warn" then
			if not s.warned then
				s.warned = true
				local secs = math.max(1, math.ceil(IdleRules.left(s.last, now, spicy)))
				self.opts.tell(player, { kind = "idle", text = IdleRules.warnText(spicy), secs = secs })
			end
		elseif s.warned then
			s.warned = false
			self.opts.tell(player, { kind = "idle", clear = true })
		end
	end
end

return IdleService
