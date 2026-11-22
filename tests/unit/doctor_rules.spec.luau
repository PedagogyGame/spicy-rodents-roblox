--!strict
-- Shared/Hospital/DoctorRules (owner D30): the doctor's job as pure rules: the call, setting off, loading beside the
-- patient (or on foot from a parked ambulance), unloading at the hospital, the warning and the demotion for no headway,
-- the hand-back of a call that takes too long, a case taken away, who gets a call, and the ambulances going home.
local DoctorRules = require("@shared/Hospital/DoctorRules")
local Tunables = require("@shared/Config/Tunables")

local function kinds(effects: { DoctorRules.Effect }): string
	local out = {}
	for _, e in effects do
		table.insert(out, e.kind)
	end
	return table.concat(out, ",")
end

return function(t)
	local P = DoctorRules.params()

	t.test("params read Config/Tunables doctor.*; the words are mild and say what to do", function()
		t.eq(P.patientCents, Tunables.get("doctor.patientCents"))
		t.eq(P.demoteSecs, 90)
		t.truthy(P.warnSecs < P.demoteSecs, "the warning comes first")
		t.truthy(P.demoteSecs < P.jobMaxSecs)
		t.truthy(string.find(DoctorRules.WORDS.warnCalled, "Bite victim waiting: head there now", 1, true) ~= nil)
		t.eq(
			DoctorRules.callWords("THE DOCKS"),
			"Bite victim near THE DOCKS! Take an ambulance (E beside one on the hospital road) and drive there: follow the BITE VICTIM marker."
		)
		t.truthy(string.find(DoctorRules.callWords(nil), "Bite victim! Take", 1, true) ~= nil)
		t.eq(DoctorRules.paidWords(25), "Patient brought in: +25c. The nurses take it from here.")
		for key, line in DoctorRules.WORDS do
			local l = string.lower(line)
			for _, bad in { "damn", "hell", "blood", "kill", "dead" } do
				t.truthy(not string.find(l, bad, 1, true), `{key}: mild`)
			end
		end
	end)

	t.test("a full run: called, set off, headway, stopped beside the patient, aboard, stopped at the doors", function()
		local job = DoctorRules.newJob(42, 100)
		t.eq(job.phase, "called")
		t.eq(kinds(DoctorRules.step(job, 105, { inAmbulance = false }, P)), "")
		local e = DoctorRules.step(job, 110, { inAmbulance = true, ambDist = 600, ambSpeed = 0 }, P)
		t.eq(kinds(e), "setOff")
		t.eq(job.phase, "enroute")
		-- driving nearer: headway every look
		for i = 1, 10 do
			t.eq(
				kinds(
					DoctorRules.step(job, 110 + i * 5, { inAmbulance = true, ambDist = 600 - i * 55, ambSpeed = 40 }, P)
				),
				""
			)
		end
		-- beside the patient but still rolling: not yet
		t.eq(kinds(DoctorRules.step(job, 161, { inAmbulance = true, ambDist = 12, ambSpeed = 20 }, P)), "")
		t.eq(kinds(DoctorRules.step(job, 162, { inAmbulance = true, ambDist = 12, ambSpeed = 1 }, P)), "load")
		-- the hospital took them aboard (the next look's fact): the goal is the hospital now
		e = DoctorRules.step(job, 163, { inAmbulance = true, aboard = true, ambDist = 700, ambSpeed = 0 }, P)
		t.eq(kinds(e), "loaded")
		t.eq(job.phase, "loaded")
		t.eq(job.loadedAt, 163)
		t.eq(
			kinds(DoctorRules.step(job, 200, { inAmbulance = true, aboard = true, ambDist = 30, ambSpeed = 30 }, P)),
			""
		)
		e = DoctorRules.step(job, 201, { inAmbulance = true, aboard = true, ambDist = 25, ambSpeed = 2 }, P)
		t.eq(kinds(e), "unload")
		t.eq(e[1].fetchSecs, 63, "from the call to the patient aboard")
		t.eq(job.phase, "done")
		t.eq(kinds(DoctorRules.step(job, 400, { inAmbulance = false }, P)), "", "a done job says nothing more")
	end)

	t.test("loading on foot: parked within carryReach, the doctor beside the patient", function()
		local job = DoctorRules.newJob(1, 0)
		DoctorRules.step(job, 1, { inAmbulance = true, ambDist = 300, ambSpeed = 0 }, P)
		local f = { inAmbulance = false, ambDist = 50, ambSpeed = 0, footDist = 4 }
		t.truthy(DoctorRules.atPatient(f, P))
		t.eq(kinds(DoctorRules.step(job, 20, f, P)), "load")
		t.truthy(not DoctorRules.atPatient({ inAmbulance = false, ambDist = 200, ambSpeed = 0, footDist = 4 }, P))
		t.truthy(not DoctorRules.atPatient({ inAmbulance = true, ambDist = 50, ambSpeed = 0, footDist = 4 }, P))
		t.truthy(not DoctorRules.atPatient({ inAmbulance = false, footDist = 1 }, P), "no ambulance at all")
	end)

	t.test("ignoring the call: one warning at warnSecs, the demotion at demoteSecs", function()
		local job = DoctorRules.newJob(7, 0)
		t.eq(kinds(DoctorRules.step(job, 59, {}, P)), "")
		local w = DoctorRules.step(job, 60, {}, P)
		t.eq(kinds(w), "warn")
		t.eq(w[1].key, "warnCalled")
		t.eq(kinds(DoctorRules.step(job, 75, {}, P)), "", "one warning, not one a look")
		local d = DoctorRules.step(job, 90, {}, P)
		t.eq(kinds(d), "demote")
		t.eq(d[1].key, "demotedIgnored")
		t.eq(job.phase, "done")
	end)

	t.test("no headway after setting off (parked, out of it, the wrong way) is a lapse; headway ends it", function()
		local job = DoctorRules.newJob(7, 0)
		DoctorRules.step(job, 10, { inAmbulance = true, ambDist = 500, ambSpeed = 0 }, P)
		-- driving away from the patient for a minute: warned
		t.eq(kinds(DoctorRules.step(job, 40, { inAmbulance = true, ambDist = 600, ambSpeed = 50 }, P)), "")
		t.eq(kinds(DoctorRules.step(job, 70, { inAmbulance = true, ambDist = 900, ambSpeed = 50 }, P)), "warn")
		-- turned round: headway, the lapse is over (a later lapse gets its own warning)
		t.eq(kinds(DoctorRules.step(job, 80, { inAmbulance = true, ambDist = 480, ambSpeed = 50 }, P)), "")
		t.eq(job.warned, false)
		t.eq(kinds(DoctorRules.step(job, 140, { inAmbulance = false, ambDist = 480, ambSpeed = 0 }, P)), "warn")
		t.eq(kinds(DoctorRules.step(job, 170, { inAmbulance = false, ambDist = 480, ambSpeed = 0 }, P)), "demote")
	end)

	t.test("abandoning a loaded patient: warned, then demoted (the hospital takes them in)", function()
		local job = DoctorRules.newJob(7, 0)
		DoctorRules.step(job, 5, { inAmbulance = true, ambDist = 100, ambSpeed = 0 }, P)
		DoctorRules.step(job, 20, { inAmbulance = true, aboard = true, ambDist = 800, ambSpeed = 0 }, P)
		local w = DoctorRules.step(job, 80, { inAmbulance = false, aboard = true, ambDist = 800, ambSpeed = 0 }, P)
		t.eq(w[1].key, "warnLoaded")
		local d = DoctorRules.step(job, 110, { inAmbulance = false, aboard = true, ambDist = 800, ambSpeed = 0 }, P)
		t.eq(kinds(d), "demote")
		t.eq(d[1].key, "demotedAbandoned")
	end)

	t.test(
		"a call not reached by jobMaxSecs goes to the computer's ambulances, no demotion; a lost case ends it",
		function()
			local job = DoctorRules.newJob(7, 0)
			DoctorRules.step(job, 1, { inAmbulance = true, ambDist = 5000, ambSpeed = 40 }, P)
			local d = 5000
			local last = {}
			for s = 2, P.jobMaxSecs, 2 do
				d -= 12
				last = DoctorRules.step(job, s, { inAmbulance = true, ambDist = d, ambSpeed = 40 }, P)
				if job.phase == "done" then
					break
				end
			end
			t.eq(kinds(last), "giveBack")
			t.eq(last[1].key, "tooSlow")
			local j2 = DoctorRules.newJob(8, 0)
			local e = DoctorRules.step(j2, 3, { gone = true }, P)
			t.eq(kinds(e), "end")
			t.eq(j2.phase, "done")
		end
	)

	t.test("chooseDoctor: at the wheel first, then the longest free, then the id; nobody free: nil", function()
		t.eq(DoctorRules.chooseDoctor({}), nil)
		t.eq(DoctorRules.chooseDoctor({ { id = 3, freeSince = 10 }, { id = 2, freeSince = 5 } }), 2)
		t.eq(DoctorRules.chooseDoctor({ { id = 3, freeSince = 10, inAmbulance = true }, { id = 2, freeSince = 5 } }), 3)
		t.eq(DoctorRules.chooseDoctor({ { id = 9, freeSince = 5 }, { id = 2, freeSince = 5 } }), 2)
	end)

	t.test("shouldReturn: parked at the bays at once; elsewhere after returnSecs with nobody near", function()
		t.truthy(DoctorRules.shouldReturn(0, 0, 10, 0, P))
		t.truthy(not DoctorRules.shouldReturn(P.returnSecs - 1, 0, 400, 500, P))
		t.truthy(not DoctorRules.shouldReturn(P.returnSecs, 0, 400, 20, P), "a player beside it")
		t.truthy(DoctorRules.shouldReturn(P.returnSecs, 0, 400, 500, P))
	end)
end
