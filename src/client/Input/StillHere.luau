--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Input.StillHere
-- The client's "still here" ping for the idle kick (owner D38; the rules: Shared/Players/IdleRules; the server decides:
-- Server/Players/IdleService). Any input this player makes (UserInputService: a press of any kind, typing in the chat,
-- a click on the screen's buttons, the mouse turning the camera, a touch, a gamepad stick past its drift; a key held
-- down) marks the pinger; once a second, a ping goes up (PlayNet.Here) when IdleRules.pingDue says so: at most one
-- every IdleRules.C.pingGap seconds, never without input since the last one. While the server's warning shows (warn),
-- the first input clears it on this screen and pings at once.
-- Cost: one flag set an input event; one check a second.
-- Interface: start(opts) -> Api { warn(on: boolean) (the server's notice is up / cleared), stop() }.
-- Engine only inside start. No side effects on require.

local Import = require("../Import")
local IdleRules = Import.shared("Players/IdleRules") :: typeof(require("../../shared/Players/IdleRules"))

local StillHere = {}

export type Opts = {
	send: () -> (), -- the ping (PlayNet.Here:FireServer())
	clear: () -> (), -- take the notice off this screen
}

export type Api = { warn: (on: boolean) -> (), stop: () -> () }

function StillHere.start(opts: Opts): Api
	local UIS = game:GetService("UserInputService")
	local p = IdleRules.pinger()
	local warned = false
	local running = true
	local function poke()
		local now = os.clock()
		IdleRules.input(p, now)
		if warned then
			warned = false
			opts.clear()
			if IdleRules.pingDue(p, now, true) then
				opts.send()
			end
		end
	end
	local conns = {
		UIS.InputBegan:Connect(function(io: InputObject)
			if IdleRules.counts(io.UserInputType.Name, nil) then
				poke()
			end
		end),
		UIS.InputChanged:Connect(function(io: InputObject)
			if IdleRules.counts(io.UserInputType.Name, io.Position.Magnitude) then
				poke()
			end
		end),
	}
	task.spawn(function()
		while running do
			task.wait(1)
			if #UIS:GetKeysPressed() > 0 then
				IdleRules.input(p, os.clock()) -- (a key held down is a player there)
			end
			if IdleRules.pingDue(p, os.clock(), false) then
				opts.send()
			end
		end
	end)
	return {
		warn = function(on: boolean)
			warned = on
			-- (input made since the last ping answers the warning at once)
			if on and IdleRules.pingDue(p, os.clock(), true) then
				warned = false
				opts.clear()
				opts.send()
			end
		end,
		stop = function()
			running = false
			for _, c in conns do
				c:Disconnect()
			end
		end,
	}
end

return StillHere
