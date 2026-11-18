--!strict
-- tests/isolated/paintball_server_silent.luau: A SERVICE THAT SAYS NOTHING, for cases that play the server
-- themselves (it is not a cases file: nothing registers it). The paintball contract gave every lane a stub
-- PaintballService that seats nobody, places nobody and sends nothing, and told the client lane to build its
-- isolated cases on it: "the case plays the server: it fires snapshots, shots and splats through the rig's
-- port and sends paintball_* messages through the stub service's ctx; to open the seat it replaces the stub
-- service's join". ONCE THE LANES ARE JOINED that stub is gone: the real service is in its place, and it
-- answers a seat by itself (it places the player, sends the roster, snapshots and corrections, drops her when
-- she is silent), so the case and the service both speak and the case's picture is no longer the one it
-- scripted. install() puts the stub's silence back for the length of a case and hands back the undo:
-- PaintballService.new still builds the real service (the arena, the place, the port bound, `match`, `feel`,
-- `ctx`: everything a case reads from it), and every hook, the loop and both remotes then do what the stub's
-- did, which is nothing:
--   join       refused with "The arena is closed." (a case puts its own in its place, as before)
--   joined, step, event, screen, onMove, onFire    nothing
--   input      refused ("phase"); command: the framework's table verbs refused, as in the real one
--   state      Contract.Extras with a full magazine and the service's `match` and `feel`
--   inPlay     true; sig: false; prompt and doneText as the real one; debug: "tune" only
-- A case of the client lane: `local undo = Silent.install()` before MinigameRig.play, `undo()` after it
-- (tests/isolated/paintball_client.luau, in `play`, beside the ArenaData.build it already swaps).
-- tests/isolated/paintball_server.luau holds this to being silent, and the real service to being back
-- after the undo.
-- Interface: install() -> undo
local Contract = require("@shared/Minigames/Paintball/Contract")
local PaintballService = require("@server/Minigames/Paintball/PaintballService")

local Silent = {}

function Silent.install(): () -> ()
	local open = PaintballService :: any
	local real = open.new
	open.new = function(ctx: any, deps: any): any
		local service = real(ctx, deps)
		local stats = service:stats()
		service.join = function(): (boolean, string?)
			return false, Contract.textFor("closed")
		end
		service.joined = function() end
		service.command = function(_self: any, _player: any, verb: string): (boolean, boolean?, string?)
			if verb == "start" or verb == "again" or verb == "addai" or verb == "mode" then
				return true, false, Contract.textFor("phase")
			end
			return false, nil, nil
		end
		service.input = function(): (boolean?, string?)
			return false, Contract.textFor("phase")
		end
		service.step = function()
			stats.steps += 1
		end
		service.event = function() end
		service.state = function(self: any): any
			return {
				match = self.match,
				bots = {},
				rounds = Contract.Rules.magazine,
				reloadAt = 0,
				shot = 0,
				feel = self.feel,
			}
		end
		service.inPlay = function(): boolean
			return true
		end
		service.screen = function() end
		service.sig = function(): any
			return false
		end
		service.debug = function(self: any, what: any, key: any, value: any): (boolean, string?)
			if what == "tune" then
				local feel, why = Contract.tuned(self.feel, tostring(key), value)
				if feel == nil then
					return false, why
				end
				self.feel = feel
				return true, nil
			end
			return false, Contract.textFor("closed")
		end
		-- (the port's handlers ask the service by name each time, so these silence the remotes too)
		service.onMove = function() end
		service.onFire = function() end
		return service
	end
	return function()
		open.new = real
	end
end

return Silent
