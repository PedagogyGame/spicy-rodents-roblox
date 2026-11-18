--!strict
-- ServerScriptService.Server.Hospital.HospitalService
-- Admissions, beds and the treatment that cures (owner 2026-11-10: "it should always be that they
-- have to go to the hospital to get cured"): a patient is admitted (into a free bed, or a first-come
-- queue when all are taken), treated in the bed for hospital.treatSecs, and is then "done"; the
-- infection service releases them cured and frees the bed. This is the only place a treatment timer
-- runs for an AI patient. Later waves add the stations, the disinfect loop, fetch tasks, performance
-- and upgrades (BUILD_PLAN §1.4: startDisinfect, fetch.offer/pick/deliver, performance, upgrade).
-- Step-driven and pure (no Instances): requiring it starts nothing.
-- Interface: new(opts { beds, treatSecs }) -> Hospital; :admit(id, now) -> bed?; :step(now) -> { id }
--   (patients whose treatment just finished); :stateOf(id) -> "none" | "queued" | "bed" | "done";
--   :bedOf(id) -> bed?; :discharge(id) (frees the bed; also drops a queued patient); :patients() ->
--   { { id, bed?, state } }; :freeBeds() -> n; :stats()

export type Opts = { beds: number, treatSecs: number }

type Patient = { id: any, bed: number?, since: number, done: boolean }

local HospitalService = {}
HospitalService.__index = HospitalService

export type Hospital = typeof(setmetatable(
	{} :: {
		beds: number,
		treatSecs: number,
		byId: { [any]: Patient },
		inBed: { [number]: any }, -- bed index -> patient id
		queue: { any },
		_stats: { admitted: number, treated: number, discharged: number, maxQueue: number },
	},
	HospitalService
))

function HospitalService.new(opts: Opts): Hospital
	return setmetatable({
		beds = math.max(1, math.floor(opts.beds)),
		treatSecs = opts.treatSecs,
		byId = {},
		inBed = {},
		queue = {},
		_stats = { admitted = 0, treated = 0, discharged = 0, maxQueue = 0 },
	}, HospitalService)
end

local function freeBed(self: Hospital): number?
	for bed = 1, self.beds do
		if self.inBed[bed] == nil then
			return bed
		end
	end
	return nil
end

-- admit: the patient's bed, or nil when they have to wait (they keep their place in the queue).
-- Admitting someone twice changes nothing.
function HospitalService.admit(self: Hospital, id: any, now: number): number?
	local already = self.byId[id]
	if already then
		return already.bed
	end
	local p: Patient = { id = id, bed = nil, since = now, done = false }
	self.byId[id] = p
	self._stats.admitted += 1
	local bed = if #self.queue == 0 then freeBed(self) else nil
	if bed then
		p.bed = bed
		self.inBed[bed] = id
	else
		table.insert(self.queue, id)
		self._stats.maxQueue = math.max(self._stats.maxQueue, #self.queue)
	end
	return bed
end

-- step: beds go to the queue in order; a treatment that has run treatSecs is done.
function HospitalService.step(self: Hospital, now: number): { any }
	while #self.queue > 0 do
		local bed = freeBed(self)
		if bed == nil then
			break
		end
		local id = table.remove(self.queue, 1)
		local p = self.byId[id]
		if p then
			p.bed = bed
			p.since = now -- the treatment starts when the bed does
			self.inBed[bed] = id
		end
	end
	local finished = {}
	for bed = 1, self.beds do
		local id = self.inBed[bed]
		local p = if id ~= nil then self.byId[id] else nil
		if p and not p.done and now - p.since >= self.treatSecs then
			p.done = true
			self._stats.treated += 1
			table.insert(finished, id)
		end
	end
	return finished
end

function HospitalService.stateOf(self: Hospital, id: any): string
	local p = self.byId[id]
	if p == nil then
		return "none"
	elseif p.bed == nil then
		return "queued"
	end
	return if p.done then "done" else "bed"
end

function HospitalService.bedOf(self: Hospital, id: any): number?
	local p = self.byId[id]
	return if p then p.bed else nil
end

-- discharge: the patient leaves (cured, or taken off the list); their bed is free at once.
function HospitalService.discharge(self: Hospital, id: any)
	local p = self.byId[id]
	if p == nil then
		return
	end
	self.byId[id] = nil
	if p.bed then
		self.inBed[p.bed] = nil
	else
		local i = table.find(self.queue, id)
		if i then
			table.remove(self.queue, i)
		end
	end
	self._stats.discharged += 1
end

function HospitalService.patients(self: Hospital): { { id: any, bed: number?, state: string } }
	local out = {}
	for id, p in self.byId do
		table.insert(out, { id = id, bed = p.bed, state = self:stateOf(id) })
	end
	table.sort(out, function(a, b)
		return tostring(a.id) < tostring(b.id)
	end)
	return out
end

function HospitalService.freeBeds(self: Hospital): number
	local n = 0
	for bed = 1, self.beds do
		if self.inBed[bed] == nil then
			n += 1
		end
	end
	return n
end

function HospitalService.stats(
	self: Hospital
): { admitted: number, treated: number, discharged: number, maxQueue: number }
	return self._stats
end

return HospitalService
