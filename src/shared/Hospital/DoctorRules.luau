--!strict
-- ReplicatedStorage.Shared.Hospital.DoctorRules
-- The doctor's job (owner D30: "(doctors) can also drive the ambulances as a role and job at the hospital when they are
-- present to pick up bite victims. However, if they do not do so properly they get demoted back to human"), as pure
-- rules: facts in, effects out. Server/Hospital/DoctorService applies them to the town.
--
--   called --(in an ambulance: set off)--> enroute --(the patient aboard)--> loaded --(stopped at the hospital)--> done
--
-- A call: a bite victim has collapsed and the hospital is called (Infection/InfectionService "call"); when a doctor is
-- free the call is theirs (chooseDoctor) instead of the computer's ambulances. Loading: the doctor's ambulance stops
-- beside the patient (loadReach, at stopSpeed or slower), or, parked within carryReach, the doctor walks up to them
-- (footReach: a patient in a fenced yard). Unloading: the ambulance stopped within unloadReach of the hospital doors
-- or the ambulance bays; the hospital's own flow then treats and cures the patient, and the doctor is paid.
-- NOT DOING IT PROPERLY: a lapse is time with no headway: from the call until they are in an ambulance, and after that
-- while their ambulance is not getting nearer its goal (the patient, then the hospital) by progressStep (out of it,
-- parked, or driving the wrong way). One warning per lapse at warnSecs ("Bite victim waiting: head there now or you
-- will lose the job"), the demotion at demoteSecs; then the computer's ambulances take the case over. A call that is
-- still not reached after jobMaxSecs, headway or not, is handed to the computer's ambulances with no demotion. A case
-- that is no longer the doctor's (the patient stood up, a player took the body, the case closed) ends the job, no
-- blame and no pay.
-- Ambulances the doctors leave about go back to their bays (shouldReturn): at once when left at the bays, else after
-- returnSecs with no player within returnNear.
-- Interface: params() -> Params (Config/Tunables doctor.*); WORDS; REPUTATION; newJob(caseId, now) -> Job;
--   step(job, now, facts, params) -> { Effect }; atPatient(facts, params) -> boolean; chooseDoctor({ Free }) -> id?;
--   shouldReturn(now, leftAt, fromBay, nearestPlayer, params) -> boolean; callWords(where?) -> string;
--   paidWords(cents) -> string
-- Pure. No side effects on require.

local Tunables = require("../Config/Tunables")

local DoctorRules = {}

export type Params = {
	patientCents: number,
	warnSecs: number,
	demoteSecs: number,
	jobMaxSecs: number,
	progressStep: number,
	loadReach: number,
	footReach: number,
	carryReach: number,
	stopSpeed: number,
	unloadReach: number,
	bayReach: number,
	returnSecs: number,
	returnNear: number,
}

export type Job = {
	case: any, -- the patient's case id (Infection/InfectionService: the TownAI actor id)
	phase: string, -- called | enroute | loaded | done
	calledAt: number,
	loadedAt: number?,
	lastProgress: number,
	best: number, -- the nearest the ambulance has been to its goal in this phase (studs)
	warned: boolean, -- this lapse's warning is given
}

-- What the server knows this step. Distances in studs; nil: not known (no ambulance).
export type Facts = {
	gone: boolean?, -- the case is no longer this doctor's (stood down, taken by a player, closed)
	aboard: boolean?, -- the patient is in the doctor's ambulance
	inAmbulance: boolean?, -- the doctor sits in an ambulance
	ambDist: number?, -- the doctor's ambulance to its goal: the patient, or (aboard) the hospital
	ambSpeed: number?, -- studs/s
	footDist: number?, -- the doctor's own body to the patient
}

export type Effect = { kind: string, key: string?, fetchSecs: number? }

export type Free = { id: any, freeSince: number, inAmbulance: boolean? }

-- What the doctor reads (plain words; the client adds the way to the goal under the status line).
DoctorRules.WORDS = table.freeze({
	call = "Bite victim{where}! Take an ambulance (E beside one on the hospital road) and drive there: follow the BITE VICTIM marker.",
	setOff = "On your way. Stop beside the patient to load them.",
	loaded = "Patient aboard. Drive to the hospital doors and stop there.",
	warnCalled = "Bite victim waiting: head there now or you will lose the job.",
	warnLoaded = "Your patient needs the hospital: drive there now or you will lose the job.",
	demotedIgnored = "You ignored a bite victim: you are not a doctor any more. Another ambulance has gone for them.",
	demotedAbandoned = "You abandoned your patient: you are not a doctor any more. The hospital has taken them in.",
	tooSlow = "That took too long: another ambulance has gone for the patient. You are still a doctor.",
	over = "The call is over: the patient is being looked after.",
	full = "Every doctor's place at the hospital is taken (5 of 5). Pick another body.",
	doctorsOnly = "Only doctors drive the ambulances. Pick Doctor from the menu (M).",
	noAmbulance = "Every ambulance is out on a call. Wait by the hospital road for one to come back.",
	picked = "You are a doctor. Wait for a call by the ambulances on the hospital road; a call shows on your screen.",
}) :: { [string]: string }

-- What the reputation in the background hears of a doctor's demotion (owner D30; D30 H4 owns the reputation and
-- decides what this kind is worth: this only names it).
DoctorRules.REPUTATION = table.freeze({ kind = "ignoredBiteVictim", severity = 1 })

function DoctorRules.params(): Params
	local g = Tunables.get
	return {
		patientCents = g("doctor.patientCents"),
		warnSecs = g("doctor.warnSecs"),
		demoteSecs = g("doctor.demoteSecs"),
		jobMaxSecs = g("doctor.jobMaxSecs"),
		progressStep = g("doctor.progressStep"),
		loadReach = g("doctor.loadReach"),
		footReach = g("doctor.footReach"),
		carryReach = g("doctor.carryReach"),
		stopSpeed = g("doctor.stopSpeed"),
		unloadReach = g("doctor.unloadReach"),
		bayReach = g("doctor.bayReach"),
		returnSecs = g("doctor.returnSecs"),
		returnNear = g("doctor.returnNear"),
	}
end

-- "Bite victim near THE DOCKS! ..." (where: a district's name, or nil)
function DoctorRules.callWords(where: string?): string
	local w = if where and where ~= "" then ` near {where}` else ""
	return (string.gsub(DoctorRules.WORDS.call, "{where}", w))
end

function DoctorRules.paidWords(cents: number): string
	return `Patient brought in: +{cents}c. The nurses take it from here.`
end

function DoctorRules.newJob(caseId: any, now: number): Job
	return {
		case = caseId,
		phase = "called",
		calledAt = now,
		loadedAt = nil,
		lastProgress = now,
		best = math.huge,
		warned = false,
	}
end

-- May the patient be loaded now? The ambulance stopped beside them, or parked near and the doctor on foot beside them.
function DoctorRules.atPatient(f: Facts, p: Params): boolean
	local amb, speed = f.ambDist, f.ambSpeed or 0
	if amb == nil then
		return false
	end
	if amb <= p.loadReach and speed <= p.stopSpeed then
		return true
	end
	local foot = f.footDist
	return not f.inAmbulance and foot ~= nil and foot <= p.footReach and amb <= p.carryReach and speed <= p.stopSpeed
end

local function headway(job: Job, now: number, f: Facts, p: Params)
	local d = f.ambDist
	if d ~= nil and d < job.best - p.progressStep then
		job.best = d
		job.lastProgress = now
		job.warned = false
	end
end

local function begin(job: Job, now: number, phase: string, f: Facts)
	job.phase = phase
	job.lastProgress = now
	job.best = f.ambDist or math.huge
	job.warned = false
end

-- step: one look at the job. The effects, in order: setOff, loaded (toasts), load (ask the hospital to take the
-- patient aboard), unload (bring them in: pay), warn, demote, giveBack (to the computer's ambulances), end.
function DoctorRules.step(job: Job, now: number, f: Facts, p: Params): { Effect }
	local out: { Effect } = {}
	if job.phase == "done" then
		return out
	end
	if f.gone then
		job.phase = "done"
		table.insert(out, { kind = "end", key = "over" })
		return out
	end
	if job.phase == "called" and f.inAmbulance then
		begin(job, now, "enroute", f)
		table.insert(out, { kind = "setOff", key = "setOff" })
	end
	if job.phase ~= "loaded" and f.aboard then
		begin(job, now, "loaded", f)
		job.loadedAt = now
		table.insert(out, { kind = "loaded", key = "loaded" })
	end
	if job.phase ~= "called" then
		headway(job, now, f, p)
	end
	if job.phase == "enroute" and DoctorRules.atPatient(f, p) then
		table.insert(out, { kind = "load" })
	elseif
		job.phase == "loaded"
		and f.ambDist ~= nil
		and f.ambDist <= p.unloadReach
		and (f.ambSpeed or 0) <= p.stopSpeed
	then
		job.phase = "done"
		table.insert(out, { kind = "unload", fetchSecs = (job.loadedAt or now) - job.calledAt })
		return out
	end
	local lapse = now - (if job.phase == "called" then job.calledAt else job.lastProgress)
	local loaded = job.phase == "loaded"
	if lapse >= p.demoteSecs then
		job.phase = "done"
		table.insert(out, { kind = "demote", key = if loaded then "demotedAbandoned" else "demotedIgnored" })
		return out
	elseif lapse >= p.warnSecs and not job.warned then
		job.warned = true
		table.insert(out, { kind = "warn", key = if loaded then "warnLoaded" else "warnCalled" })
	end
	if not loaded and now - job.calledAt >= p.jobMaxSecs then
		job.phase = "done"
		table.insert(out, { kind = "giveBack", key = "tooSlow" })
	end
	return out
end

-- chooseDoctor: who gets a call among the free doctors: one already at the wheel of an ambulance first, then the one
-- free the longest, then the lowest id. nil when nobody is free.
function DoctorRules.chooseDoctor(free: { Free }): any?
	local best: Free? = nil
	for _, d in free do
		if best == nil then
			best = d
		else
			local b = best :: Free
			local da, db = d.inAmbulance == true, b.inAmbulance == true
			if da ~= db then
				if da then
					best = d
				end
			elseif d.freeSince ~= b.freeSince then
				if d.freeSince < b.freeSince then
					best = d
				end
			elseif tostring(d.id) < tostring(b.id) then
				best = d
			end
		end
	end
	return if best then best.id else nil
end

-- shouldReturn: an ambulance nobody sits in, left `fromBay` studs from its bay at `leftAt`, with the nearest player
-- `nearestPlayer` studs away: is it parked back in its bay now?
function DoctorRules.shouldReturn(
	now: number,
	leftAt: number,
	fromBay: number,
	nearestPlayer: number,
	p: Params
): boolean
	if fromBay <= p.bayReach then
		return true
	end
	return now - leftAt >= p.returnSecs and nearestPlayer >= p.returnNear
end

return DoctorRules
