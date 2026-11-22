--!strict
-- Server/Hospital/DoctorService on the real town (owner D30), wired as Boot/Game wires it: the town AI, the fleet with
-- its three responder ambulances, the bite-to-hospital sequence (tests/lib/BiteRig), Roles/RoleService (a doctor on the
-- hospital rung, the purse) and a stand-in for the player vehicles (Actors/DeviceService: an ambulance's pose the test
-- drives). A full run (the call, the ambulance borrowed, the drive, loading beside the patient, unloading at the doors,
-- the cure, the pay and the rank points), the computer's ambulances when there is no doctor, the warning and the
-- demotion for a call ignored and for a patient abandoned (the computer's ambulances or the hospital take the case
-- over and the patient is cured all the same), nothing for a non-doctor, and the ambulances going back to their bays.
local BiteRig = require("@tests/lib/BiteRig")
local DoctorRules = require("@shared/Hospital/DoctorRules")
local Ladder = require("@shared/Roles/Ladder")
local DoctorService = require("@server/Hospital/DoctorService")
local RoleService = require("@server/Roles/RoleService")
local TrafficService = require("@server/Traffic/TrafficService")

type Vehicle = { x: number, z: number, yaw: number, speed: number, driver: number? }

-- the town round a bite with the doctors wired in
local function town(seed: number): any
	local h: any = {}
	h.rig = BiteRig.new({
		duel = false,
		seed = seed,
		doctorCall = function(id: number, x: number, z: number): boolean
			return h.doctors ~= nil and h.doctors:call(id, x, z)
		end,
	})
	local rig = h.rig
	local possession = {
		by = {},
		possess = function(self, p, a)
			self.by[p.UserId] = a
			return true
		end,
		release = function(self, p)
			self.by[p.UserId] = nil
		end,
		swap = function(self, p, a)
			self.by[p.UserId] = a
			return true
		end,
		actorOf = function(self, p)
			return self.by[p.UserId]
		end,
	}
	local bodies = 0
	h.roles = RoleService.new({
		possession = possession,
		pickBody = function(_p, rung)
			bodies += 1
			return { id = `{rung or "human"}_{bodies}` }
		end,
	})
	h.body = {} :: { [number]: { number } }
	h.vehicles = {} :: { [string]: Vehicle }
	h.told = {} :: { { to: number, text: string, banner: boolean?, demoted: boolean? } }
	h.shown = {} :: { [number]: any }
	h.demoted = {} :: { [number]: string }
	h.reputation = {} :: { { number | string } }
	local layout = rig.infection.layout
	h.door = { layout.entrance[1], layout.entrance[2] }
	local spawned = 0
	h.doctors = DoctorService.new({
		infection = rig.infection,
		traffic = rig.traffic,
		roles = h.roles,
		now = function(): number
			return rig.time
		end,
		drops = { h.door, rig.traffic:responderHome() },
		bodyAt = function(p: any): (number?, number?)
			local b = h.body[p.UserId]
			if b then
				return b[1], b[2]
			end
			return nil, nil
		end,
		spawn = function(x: number, z: number, yaw: number): any
			spawned += 1
			local id = `ambulance_{spawned}`
			h.vehicles[id] = { x = x, z = z, yaw = yaw, speed = 0, driver = nil }
			return id
		end,
		despawn = function(id: any)
			h.vehicles[id] = nil
		end,
		poseOf = function(id: any): any
			local v = h.vehicles[id]
			return if v then { x = v.x, z = v.z, speed = v.speed, driver = v.driver } else nil
		end,
		tell = function(p: any, payload: { [string]: any })
			table.insert(
				h.told,
				{ to = p.UserId, text = payload.text, banner = payload.banner, demoted = payload.demoted }
			)
		end,
		show = function(p: any, job: any)
			h.shown[p.UserId] = job
		end,
		onDemoted = function(p: any, words: string)
			h.demoted[p.UserId] = words
		end,
		reputation = function(p: any, kind: string, severity: number)
			table.insert(h.reputation, { p.UserId, kind, severity })
		end,
	})
	h.players = {}
	function h.join(id: number): any
		local p = { UserId = id }
		h.players[id] = p
		h.roles:onJoin(p)
		return p
	end
	function h.doctor(id: number): any
		local p = h.join(id)
		local ok = h.roles:take(p, "hospital")
		assert(ok, "a doctor's slot")
		h.doctors:joined(p)
		-- standing beside the first ambulance in its bay (Boot/Game puts a new doctor there)
		local parked = rig.traffic:parkedResponders()[1]
		h.body[id] = { parked.x + 4, parked.z }
		return p
	end
	-- E beside the nearest parked ambulance: the player vehicle's id, seated (DeviceService does the seating)
	function h.press(p: any): (any?, string?)
		local b = h.body[p.UserId]
		local id, why = h.doctors:borrow(p, b[1], b[2], 16)
		if id ~= nil then
			h.vehicles[id].driver = p.UserId
		end
		return id, why
	end
	-- each step the test's vehicle drives straight at `goal` and stops there; the body rides along
	function h.drive(p: any, vid: any, goal: { number }, speed: number)
		local v = h.vehicles[vid]
		local dx, dz = goal[1] - v.x, goal[2] - v.z
		local d = math.sqrt(dx * dx + dz * dz)
		local step = speed * rig.dt
		if d <= step then
			v.x, v.z, v.speed = goal[1], goal[2], 0
		else
			v.x, v.z, v.speed = v.x + dx / d * step, v.z + dz / d * step, speed
		end
		if v.driver == p.UserId then
			h.body[p.UserId] = { v.x, v.z }
		end
	end
	function h.step(secs: number, each: (() -> ())?)
		rig.step(secs, function()
			if each then
				each()
			end
			h.doctors:step()
		end)
	end
	-- a calm townsperson far from the hospital, bitten: collapses at once (the dice), the call comes a few seconds later
	function h.bite(): number
		rig.step(10)
		local victim = rig.calmNear(h.door[1] + 700, h.door[2] + 300)
		rig.dice({ 0, 0 })
		assert(rig.infection:bite(victim.id, rig.rodent, "rodentPlayer"), "a new case")
		return victim.id
	end
	function h.toldTo(id: number, needle: string): boolean
		for _, m in h.told do
			if m.to == id and string.find(m.text, needle, 1, true) then
				return true
			end
		end
		return false
	end
	return h
end

local function respondersOut(rig: any): number
	local n = 0
	for _, v in rig.traffic.vehicles do
		if v.class == "responder" and v.phase ~= "idle" and v.phase ~= "borrowed" then
			n += 1
		end
	end
	return n
end

return function(t)
	t.test(
		"the fleet: an ambulance kept for a doctor is passed by; borrowed it is out of sight; back in its bay",
		function()
			local Data = require("@shared/Data")
			local data = Data.default()
			local traffic = TrafficService.new({ lanes = data:lanes(), roads = data:roads(), seed = 3 })
			t.eq(#traffic:parkedResponders(), 3)
			local kept = traffic:reserveResponder()
			t.truthy(kept ~= nil)
			t.eq(traffic:responderIdle(), 2)
			local home = traffic:responderHome() :: { number }
			local sent = {}
			for _ = 1, 3 do
				local v = traffic:dispatchResponder({ home[1] + 400, home[2] })
				if v then
					table.insert(sent, v)
				end
			end
			t.eq(#sent, 2, "the kept one is never sent")
			t.truthy(table.find(sent, kept) == nil)
			local bay = traffic:bayOf(kept) :: any
			t.near(kept.x, bay.x, 1e-6)
			t.truthy(traffic:borrowResponder(kept))
			t.eq(kept.phase, "borrowed")
			t.eq(kept.visible, false)
			t.eq(kept.reserved, nil)
			t.eq(traffic:borrowResponder(kept), false, "not twice")
			traffic:step(2)
			t.eq(kept.phase, "borrowed", "the motor leaves it alone")
			kept.x, kept.z = 0, 0
			traffic:returnResponder(kept)
			t.eq(kept.phase, "idle")
			t.eq(kept.visible, true)
			t.near(kept.x, bay.x, 1e-6)
			t.near(kept.z, bay.z, 1e-6)
			traffic:unreserve(kept)
			t.eq(kept.reserved, nil)
		end
	)

	t.test(
		"a full run: the call, an ambulance at E, the drive, loaded beside the patient, in at the doors, cured, paid",
		function()
			local h = town(41)
			local rig = h.rig
			local doc = h.doctor(1)
			t.truthy(h.doctors:isDoctor(doc))
			local purse = (h.roles:member(1) :: any).purse
			local cents0 = purse.cents
			local score0 = h.roles:member(1).stats.questScore or 0
			local victim = h.bite()
			-- the call is the doctor's: no computer ambulance goes, one is kept at the bays for them
			t.truthy(
				rig.runUntil(30, function()
					return h.doctors:jobOf(doc) ~= nil
				end, function()
					h.doctors:step()
				end),
				"the doctor is called"
			)
			local calledAt = rig.time
			t.truthy(h.toldTo(1, "Bite victim"), "the call on screen")
			t.eq(h.shown[1].phase, "called")
			t.eq(rig.infection:doctorCase(victim) ~= nil, true)
			t.eq(rig.traffic:responderIdle(), 2, "one ambulance kept for the doctor")
			-- E beside the ambulance: borrowed out of the fleet, the player's one drawn in its place
			local vid = h.press(doc)
			t.truthy(vid ~= nil, "E takes the ambulance")
			local borrowed = 0
			for _, v in rig.traffic.vehicles do
				if v.phase == "borrowed" then
					borrowed += 1
					t.eq(v.visible, false, "the fleet's one is out of sight")
				end
			end
			t.eq(borrowed, 1)
			-- drive to the patient and stop beside them
			local case = rig.infection:doctorCase(victim)
			local beside = { case.x + 8, case.z }
			local loadedAt = rig.time
			t.truthy(
				rig.runUntil(120, function()
					local c = rig.infection:doctorCase(victim)
					return c ~= nil and c.aboard
				end, function()
					h.drive(doc, vid, beside, 40)
					h.doctors:step()
					loadedAt = rig.time
				end),
				"loaded beside the patient"
			)
			t.eq(rig.infection:stateOf(victim), "transit")
			h.step(0.2) -- (the doctor's next look sees them aboard)
			t.truthy(h.toldTo(1, "Patient aboard"))
			t.eq(h.shown[1].phase, "loaded")
			-- to the hospital doors
			t.truthy(
				rig.runUntil(120, function()
					return h.doctors:jobOf(doc) == nil
				end, function()
					h.drive(doc, vid, { h.door[1] + 10, h.door[2] }, 40)
					h.doctors:step()
				end),
				"unloaded at the doors"
			)
			t.eq(purse.cents, cents0 + DoctorRules.params().patientCents, "paid through the purse (the wallet)")
			t.truthy(
				(h.roles:member(1).stats.questScore or 0) >= score0 + Ladder.params.rankClass.standard,
				"rank points"
			)
			t.truthy(h.toldTo(1, "Patient brought in"))
			t.eq(h.shown[1], nil, "no call on screen")
			-- the hospital's own flow: a bed, the treatment, the cure
			t.truthy(
				rig.runUntil(120, function()
					return rig.infection:stateOf(victim) == nil
				end, function()
					h.doctors:step()
				end),
				"cured"
			)
			t.eq(rig.infection:stats().cured, 1)
			t.eq(rig.infection:stats().dispatched, 0, "no computer ambulance went")
			t.eq(rig.infection:stats().doctorRuns, 1)
			t.eq(#h.reputation, 0)
			print(
				`      the patient aboard {math.floor(loadedAt - calledAt + 0.5)} s after the call; in at the doors, cured, paid {DoctorRules.params().patientCents}c`
			)
			-- parked back at the bays and out: the fleet's ambulance is back in its bay, in view
			local loan = h.doctors:borrowed()[vid]
			local home = rig.traffic:bayOf(loan.vehicle)
			rig.runUntil(60, function()
				return h.vehicles[vid] ~= nil and h.vehicles[vid].x == home.x and h.vehicles[vid].z == home.z
			end, function()
				h.drive(doc, vid, { home.x, home.z }, 40)
			end)
			h.vehicles[vid].driver = nil
			h.step(1)
			t.eq(h.vehicles[vid], nil, "the player vehicle is gone")
			t.eq(loan.vehicle.phase, "idle")
			t.eq(loan.vehicle.visible, true)
			t.eq(rig.traffic:responderIdle(), 3)
		end
	)

	t.test(
		"no doctor: the computer's ambulances exactly as before; a non-doctor gets no call and no ambulance",
		function()
			local h = town(42)
			local rig = h.rig
			local walker = h.join(5)
			h.body[5] = { 0, 0 }
			local victim = h.bite()
			t.truthy(
				rig.runUntil(40, function()
					return rig.infection:stats().dispatched >= 1
				end),
				"a computer ambulance goes"
			)
			t.eq(rig.infection:doctorCase(victim), nil)
			t.eq(rig.infection:stats().doctorCalls, 0)
			-- a townsperson at an ambulance: told why not, nothing borrowed
			local parked = rig.traffic:parkedResponders()[1]
			local id, why = h.doctors:borrow(walker, parked.x + 3, parked.z, 16)
			t.eq(id, nil)
			t.eq(why, DoctorRules.WORDS.doctorsOnly)
			t.eq(next(h.doctors:borrowed()), nil)
			-- nothing near an ambulance: nothing said (E is someone else's then)
			t.deepEq({ h.doctors:borrow(walker, 0, 0, 16) }, {})
			t.truthy(
				rig.runUntil(400, function()
					return rig.infection:stateOf(victim) == nil
				end),
				"cured by the computer's ambulance"
			)
		end
	)

	t.test(
		"a call ignored: one warning, then demoted to the human rung; the computer's ambulance takes the case over",
		function()
			local h = town(43)
			local rig = h.rig
			local doc = h.doctor(1)
			local victim = h.bite()
			rig.runUntil(30, function()
				return h.doctors:jobOf(doc) ~= nil
			end, function()
				h.doctors:step()
			end)
			local calledAt = rig.time
			t.truthy(h.doctors:jobOf(doc) ~= nil, "called")
			local warnedAt, demotedAt = nil, nil
			rig.runUntil(120, function()
				return demotedAt ~= nil
			end, function()
				h.doctors:step()
				if warnedAt == nil and h.toldTo(1, "Bite victim waiting: head there now") then
					warnedAt = rig.time
				end
				if demotedAt == nil and h.demoted[1] ~= nil then
					demotedAt = rig.time
				end
			end)
			t.truthy(warnedAt ~= nil and demotedAt ~= nil, "warned, then demoted")
			t.near((warnedAt :: number) - calledAt, 60, 1)
			t.near((demotedAt :: number) - calledAt, 90, 1)
			t.eq(h.roles:roleOf(doc), "human", "back to the human rung")
			t.eq(h.roles:member(1).stats.questScore, 0, "at its lowest rank")
			t.truthy(string.find(h.demoted[1], "not a doctor any more", 1, true) ~= nil)
			t.eq(#h.reputation, 1)
			t.eq(h.reputation[1][2], DoctorRules.REPUTATION.kind)
			t.truthy(not h.doctors:isDoctor(doc))
			t.eq(rig.traffic:responderIdle(), 3, "the kept ambulance is free again")
			t.truthy(
				rig.runUntil(30, function()
					return rig.infection:stats().dispatched >= 1
				end),
				"a computer ambulance goes at once"
			)
			t.truthy(
				rig.runUntil(400, function()
					return rig.infection:stateOf(victim) == nil
				end),
				"the patient is cured all the same"
			)
			-- a demoted player is never called again
			t.eq(h.doctors:call(victim, 0, 0), false)
		end
	)

	t.test(
		"a loaded patient abandoned: warned, demoted, the hospital takes them in; the ambulance goes home later",
		function()
			local h = town(44)
			local rig = h.rig
			local doc = h.doctor(1)
			local victim = h.bite()
			rig.runUntil(30, function()
				return h.doctors:jobOf(doc) ~= nil
			end, function()
				h.doctors:step()
			end)
			local vid = h.press(doc)
			local c = rig.infection:doctorCase(victim)
			local beside = { c.x + 6, c.z }
			rig.runUntil(120, function()
				local cc = rig.infection:doctorCase(victim)
				return cc ~= nil and cc.aboard
			end, function()
				h.drive(doc, vid, beside, 40)
				h.doctors:step()
			end)
			t.eq(rig.infection:stateOf(victim), "transit")
			-- out of the ambulance and away on foot
			h.vehicles[vid].driver = nil
			h.body[1] = { beside[1] + 50, beside[2] }
			rig.runUntil(120, function()
				return h.demoted[1] ~= nil
			end, function()
				h.doctors:step()
			end)
			t.truthy(h.toldTo(1, "Your patient needs the hospital"), "the warning first")
			t.truthy(string.find(h.demoted[1] or "", "abandoned your patient", 1, true) ~= nil)
			t.eq(h.roles:roleOf(doc), "human")
			t.truthy(
				rig.runUntil(120, function()
					return rig.infection:stateOf(victim) == nil
				end, function()
					h.doctors:step()
				end),
				"taken in and cured"
			)
			-- the ambulance left on the street goes back to its bay once nobody is near it
			h.body[1] = nil
			t.truthy(
				rig.runUntil(DoctorRules.params().returnSecs + 5, function()
					return h.vehicles[vid] == nil
				end, function()
					h.doctors:step()
				end),
				"back in its bay"
			)
			t.eq(rig.traffic:responderIdle(), 3)
			t.eq(respondersOut(rig), 0)
		end
	)
end
