--!strict
-- The live squirrel validator against the third adversarial review (2026-11-18): the pin no other path may undo, a
-- claimed rail at a gate, an honest body taken high in the air, the place before a move under a slow link's round trip,
-- and a pin dropped while the body rides. Each cheat must be snapped; each honest case must not.
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local LiveRig = require("@tests/lib/LiveRig")

type State = SquirrelMotor.State

local town = LiveRig.town()

local function still(_now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
	return SquirrelMotor.idleInput(0)
end

return function(t)
	-- 4. THE PLACE BEFORE A MOVE, WHATEVER THE ENGINE SAYS THE ROUND TRIP IS -----------------------------------------------
	-- After each Reset the root is kept 250 studs off, near nothing, for as long as the round trip read would cover: a
	-- round trip of 6 s (GetNetworkPing reads up to 10) buys no more room or time than one of 1 s (C.PING_MAX)
	for _, ping in { 0.2, 2, 6, 10 } do
		t.test(`cheat: the root 250 studs off after each Reset, the round trip read {ping} s: snapped`, function()
			local s0 = town.openStart()
			local resetAt = {}
			local rig
			rig = LiveRig.new({
				world = town.noWalls,
				vworld = town.vworld,
				link = { latency = 0.1, jitter = 0.05, loss = 0.0 },
				seed = 5,
				pingOf = function(_t: number): number
					return ping
				end,
				rootCheat = function(p: any, now: number)
					for _, at in resetAt do
						if now > at + 0.3 and now < at + 2 * ping + 0.8 then
							p.x = s0.x + 250
						end
					end
				end,
			})
			rig:possess(s0, still)
			for k = 1, 4 do
				local at = 5 + (k - 1) * 15
				rig:at(at, function()
					table.insert(resetAt, at)
					rig:teleport(s0.x, s0.y, s0.z + 40, "reset")
				end)
			end
			rig:run(65)
			local r = rig:result()
			print(`      {LiveRig.describe(`ping {ping}`, r)}`)
			t.truthy((r.reasons.drift or 0) >= 4, `snapped for drift after every Reset ({r.reasons.drift or 0})`)
		end)
	end
end
