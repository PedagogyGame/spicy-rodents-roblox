--!strict
-- Owner D30: "Jobs can also be found at the bowling alley, or at the top of the sky lift".
--   duties   the shoe desk, the lanes (the alley employees' own work stops, on the alley's floor) and the Lookout
--            attendant (on the Lookout's way on foot), each named; wages in EconomyRules above the minimum
--   shift    a duty is done by standing at it its seconds; an hour with a duty done is paid, an hour without is
--            not, three idle hours end the shift
--   pay      paid through the existing path: Ladder "work.completed" (pay, no rank points), RoleService's wallet
--   service  Server/Jobs/JobService: townspeople only, people only, two to a job, one job at a time, clock off
local TownJobs = require("@shared/Work/TownJobs")
local EconomyRules = require("@shared/Economy/EconomyRules")
local Ladder = require("@shared/Roles/Ladder")
local AlleyStaff = require("@shared/Attractions/AlleyStaff")
local Data = require("@shared/Data")
local JobService = require("@server/Jobs/JobService")

return function(t)
	t.test("duties: three jobs, every duty named and on its floor; wages above the minimum", function()
		local data = Data.default()
		local alley = AlleyStaff.placeOf(data) :: any
		t.eq(#TownJobs.JOBS, 3)
		for _, job in TownJobs.JOBS do
			local duties = TownJobs.duties(job)
			t.truthy(#duties >= 4, `{job.id}: {#duties} duties`)
			for _, d in duties do
				t.truthy(d.label ~= "" and d.label ~= "the next job", `{job.id}: a duty with no words`)
				t.truthy(d.hold >= 3)
				if job.venue == "alley" then
					t.truthy(AlleyStaff.inside(alley, d.x, d.z), `{job.id}: {d.label} outside the alley`)
				else
					t.near(d.y, 116, 1e-6, "on the Lookout's floor")
				end
			end
			t.truthy(EconomyRules.wage(job.id, 1) > EconomyRules.WAGES.minimum, `{job.id} pays the minimum`)
		end
	end)

	t.test("shift: duties by standing at them; an hour with one is paid, without is not; idle ends it", function()
		local job = TownJobs.byId("lookout_attendant") :: TownJobs.Job
		local duties = TownJobs.duties(job)
		local s = TownJobs.start(job, duties, 10.2)
		local d1 = duties[1]
		t.eq(TownJobs.step(s, 10.3, { d1.x + 20, d1.y, d1.z }, 10), nil, "not there")
		t.eq(TownJobs.step(s, 10.3, { d1.x + 1, d1.y, d1.z }, d1.hold - 1), nil, "not long enough")
		t.eq(TownJobs.step(s, 10.4, { d1.x + 1, d1.y, d1.z }, 1), "duty")
		t.eq(TownJobs.next(s), duties[2])
		t.eq(TownJobs.step(s, 10.4, { d1.x, d1.y + 20, d1.z }, 1), nil, "another floor")
		t.eq(TownJobs.step(s, 11.01, nil, 1), "paid")
		t.eq(s.paidHour, 10)
		t.eq(TownJobs.step(s, 12.01, nil, 1), "unpaid")
		t.eq(TownJobs.step(s, 13.01, nil, 1), "unpaid")
		t.eq(TownJobs.step(s, 14.01, nil, 1), "idle")
	end)

	t.test("pay: Ladder work.completed carries the wage and no rank points", function()
		local out = Ladder.resolve(
			{ kind = "work.completed", player = 1, pay = EconomyRules.wage("shoe_desk", 1), class = TownJobs.CLASS },
			{ players = {} }
		)
		t.eq(out[1].pay, 500) -- owner D31: S$5.00 an in-game hour
		t.eq(out[1].rankDelta, 0)
		t.eq(EconomyRules.payWhy(out[1].rule), "work")
	end)

	t.test("service: townspeople only, people only, two to a job, one job at a time, paid hourly, clock off", function()
		local hours = 5.0
		local clock = 0
		local rung: { [any]: string } = {}
		local person: { [any]: boolean } = {}
		local bodies: { [any]: { number } } = {}
		local reports: { any } = {}
		local told: { [any]: string } = {}
		local svc = JobService.new({
			roles = {
				roleOf = function(_self: any, p: any): string?
					return rung[p]
				end,
				report = function(_self: any, e: any)
					table.insert(reports, e)
				end,
			},
			bodyOf = function(p: any): any?
				return bodies[p]
			end,
			isPerson = function(p: any): boolean
				return person[p] == true
			end,
			notify = function(p: any, text: string)
				told[p] = text
			end,
			gameHours = function(): number
				return hours
			end,
			now = function(): number
				return clock
			end,
			posOf = function(b: any): { number }?
				return b
			end,
		})
		local function new(id: number, r: string): any
			local p = { UserId = id }
			rung[p], person[p], bodies[p] = r, true, { 0, 0, 0 }
			return p
		end
		local a, b, c, cop = new(1, "human"), new(2, "human"), new(3, "human"), new(4, "police")
		t.falsy((svc:press(cop, "shoe_desk")), "the police are not townspeople")
		t.truthy((svc:press(a, "shoe_desk")))
		t.truthy((svc:press(b, "shoe_desk")))
		t.falsy((svc:press(c, "shoe_desk")), "two to a job")
		clock += 1
		t.falsy((svc:press(a, "lane_attendant")), "one job at a time")
		-- a does the first duty, the hour turns: paid through the roles
		local d = svc:shiftOf(a).duties[1]
		bodies[a] = { d.x, d.y, d.z }
		for _ = 1, math.ceil(d.hold / 0.25) + 1 do
			svc:step(0.25)
		end
		t.eq(svc:shiftOf(a).done, 1)
		hours = 6.01
		svc:step(0.25)
		t.eq(#reports, 1, "b did nothing and is not paid")
		t.eq(reports[1].kind, "work.completed")
		t.eq(reports[1].player, 1)
		t.eq(reports[1].pay, 500) -- owner D31: S$5.00 an in-game hour
		-- a squirrel is off shift
		person[b] = false
		svc:step(0.25)
		t.eq(svc:shiftOf(b), nil)
		-- clock off with the same prompt
		clock += 1
		t.truthy((svc:press(a, "shoe_desk")))
		t.eq(svc:shiftOf(a), nil)
		t.truthy(string.find(told[a], "clocked off", 1, true) ~= nil)
	end)
end
