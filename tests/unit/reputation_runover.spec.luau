--!strict
-- Owner D30: "or practically runs over people, same thing, but do not mark this or score this often, only in extreme
-- situations". Server/Vehicles/RideBumps tells opts.struck of every person a shared vehicle knocks (the ride, the person,
-- its speed); Boot/Game hands that to Reputation/ReputationService.runOver for the rider, where Reputation/Conduct counts
-- only three people in a minute or the same one again within 30 s, at speed. Here RideBumps runs on a bare world (one
-- player's person in the way of a cart), stepped by hand, wired to the real reputation the way Boot/Game wires it.
local RideBumps = require("@server/Vehicles/RideBumps")
local ReputationService = require("@server/Reputation/ReputationService")
local SharedRides = require("@shared/Vehicles/SharedRides")
local fs = require("@lune/fs")

return function(t)
	t.test("a shared vehicle's knock reaches the rider's reputation; only the same person again counts", function()
		local now = 0
		local person = { id = 7, species = "human", x = 0, y = 3, z = 1, hip = 3 }
		local world = {
			actors = { person },
			actorsById = { [7] = person },
			possessed = { [7] = true }, -- a player's person: knocked on their own client (knockHeld)
			brains = {},
			now = 0,
			ctx = {},
		}
		local ride = { id = "cart_1", kind = "cart", x = 0, z = 0, floor = 0, yaw = 0, vx = 0, vz = 15 }
		local rider = { UserId = 99 }
		local told: { string } = {}
		local rep = ReputationService.new({
			now = function()
				return now
			end,
			tell = function(_p: any, words: string)
				table.insert(told, words)
			end,
		})
		local struck: { { any } } = {}
		local knocked = 0
		local bumps = RideBumps.new({
			world = world,
			rides = function()
				return { ride }
			end,
			knockHeld = function()
				knocked += 1
			end,
			struck = function(rideId: string, personId: number, speed: number)
				table.insert(struck, { rideId, personId, speed })
				-- (Boot/Game: the ride's driver, by UserId, then this)
				rep.runOver(rider, { victim = personId, speed = speed })
			end,
		})
		bumps:step(1 / 30)
		t.eq(knocked, 1)
		t.deepEq(struck[1], { "cart_1", 7, 15 })
		t.eq(rep.get(rider), 0, "one knock is an accident")
		-- within the knock's cooldown nothing more happens at all
		now, world.now = 2, 2
		bumps:step(1 / 30)
		t.eq(#struck, 1)
		-- back for the same person after the cooldown, within 30 s: that is no accident
		now, world.now = SharedRides.C.cooldown + 3, SharedRides.C.cooldown + 3
		bumps:step(1 / 30)
		t.eq(#struck, 2)
		t.eq(rep.get(rider), -10)
		t.eq(told[1], "Reputation down: you went back and ran the same person over (now Fair)")
		-- a crawl into someone never reaches the rules as a hard knock
		ride.vz = 4
		now, world.now = 40, 40
		bumps:step(1 / 30)
		t.eq(#struck, 3)
		t.eq(struck[3][3], 4)
		t.eq(rep.get(rider), -10, "a crawl never counts")
	end)

	t.test("Boot/Game wires it: the rider by the vehicle's driver, then the reputation's runOver", function()
		local src = fs.readFile("src/server/Boot/Game.luau")
		t.truthy(string.find(src, "struck = function(rideId: string, personId: number, speed: number)", 1, true))
		t.truthy(string.find(src, "reputation.runOver(rider, { victim = personId, speed = speed })", 1, true))
	end)
end
