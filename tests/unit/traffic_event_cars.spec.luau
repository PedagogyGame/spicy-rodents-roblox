--!strict
-- The event cars (the guests' cars at the town's barbecue and softball game, traffic §5.11) stay out of sight until
-- those events are built: the owner found three of them parked in an empty field (2026-11-21). Every other fleet
-- vehicle that shows stands or drives as before.
local TrafficService = require("@server/Traffic/TrafficService")

return function(t)
	t.test("no event car is ever shown; the rest of the fleet is", function()
		local records = require("../../generated/Lanes") :: any
		local roadRecords = require("../../generated/Roads") :: any
		local svc: any = TrafficService.new({ lanes = records, roads = roadRecords, seed = 3 })
		local events, shownOthers = 0, 0
		for _, v in svc.vehicles do
			if v.class == "event" then
				events += 1
			end
		end
		t.eq(events, 6, "three barbecue cars and three softball cars in the fleet")
		for _ = 1, 30 * 180 do
			svc:step(1 / 30, {})
			for _, v in svc.vehicles do
				if v.class == "event" then
					t.truthy(v.visible == false, `{v.name} hidden`)
				end
			end
		end
		for _, v in svc.vehicles do
			if v.class ~= "event" and v.visible ~= false then
				shownOthers += 1
			end
		end
		t.truthy(shownOthers >= 10, `the rest of the fleet shows ({shownOthers})`)
	end)
end
