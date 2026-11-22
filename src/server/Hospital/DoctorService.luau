--!strict
-- ServerScriptService.Server.Hospital.DoctorService
-- The doctors (owner D30: "(doctors) can also drive the ambulances as a role and job at the hospital when they are
-- present to pick up bite victims. However, if they do not do so properly they get demoted back to human"). The rules
-- are Shared/Hospital/DoctorRules; this applies them to the town, over injected deps (Lune drives it on the real town,
-- tests/unit/doctor_service.spec.luau):
--   * A player who picks Doctor from the menu is put on the hospital rung as a doctor by Boot/Game (RoleService.take)
--     and joins here (`joined`); picking something else, leaving or being knocked out is `left`.
--   * The call: Infection/InfectionService offers a patient queued for an ambulance (`call`, its opts.doctorCall) and a
--     free doctor gets it (DoctorRules.chooseDoctor), with a parked ambulance kept for them (TrafficService
--     reserveResponder). No doctor free, or no ambulance parked: false, and the computer's ambulances go as before.
--   * The ambulances: the three responders parked on the hospital road. E beside one (Actors/DeviceService asks
--     `borrow`): a doctor takes it (TrafficService borrowResponder: out of the fleet and out of sight) and drives the
--     player vehicle `spawn` draws in its place, with its lights flashing; anyone else is told only doctors drive them.
--     An ambulance left at the bays goes back at once, one left anywhere else after a while with nobody near it
--     (DoctorRules.shouldReturn: `despawn`, TrafficService returnResponder); never one whose doctor is still on a call.
--   * The job (DoctorRules.step, every `step`): loading beside the patient (InfectionService doctorLoad), unloading at
--     the hospital's doors or the ambulance bays (doctorUnload: the hospital's own flow treats and cures them), the pay
--     and the fetch's rank points (RoleService report "doctor.delivered": through the wallet), the warning, and the
--     demotion (RoleService demote; doctorRelease: the computer's ambulances take the case over; the reputation in the
--     background hears of it through deps.reputation).
--   * The client is told through `tell` (PlayNet Event payloads: kind "doctor", text, banner?) and `show` (the call on
--     screen: the phase and where the patient is, nil when there is no call; Boot/Game writes the player attributes
--     DoctorJob and DoctorCall that Client/UI/PlayMenu draws as the BITE VICTIM or HOSPITAL marker and its line).
-- Nothing a client says is believed: who is a doctor is RoleService's, where the ambulance and the patient are is the
-- server's own, and pay comes only from an unload the hospital accepted.
-- Interface: new(deps) -> Doctors { joined(player), left(player), isDoctor(player) -> boolean, jobOf(player) -> Job?,
--   call(caseId, x, z) -> boolean, borrow(player, x, z, reach) -> (deviceId?, reason?), step(), doctors() -> { player },
--   borrowed() -> { [deviceId]: Loan } }
-- No side effects on require.

local Import = require("../Import")
local DoctorRules = Import.shared("Hospital/DoctorRules") :: typeof(require("../../shared/Hospital/DoctorRules"))

-- (exported types do not cross the Import shim: restated loosely)
type Job = { [string]: any }
type Params = { [string]: any }

export type Pose = { x: number, z: number, speed: number, driver: number? }

export type Deps = {
	infection: any, -- Infection/InfectionService (doctorCase, doctorLoad, doctorUnload, doctorRelease)
	traffic: any, -- Traffic/TrafficService (parkedResponders, reserveResponder, unreserve, borrowResponder, ...)
	roles: any?, -- Roles/RoleService (roleOf, report, demote); nil: nobody is a doctor
	now: () -> number, -- seconds
	drops: { { number } }, -- where a patient is unloaded: the hospital doors, the ambulance bays (studs, {x, z})
	bodyAt: (player: any) -> (number?, number?), -- where the doctor's body stands
	spawn: (x: number, z: number, yaw: number) -> any, -- the player ambulance drawn for a borrowed responder: its id
	despawn: (id: any) -> (), -- that vehicle gone (its driver let out first)
	poseOf: (id: any) -> Pose?, -- where it is, how fast, who drives (a UserId)
	tell: (player: any, payload: { [string]: any }) -> (),
	show: (player: any, job: { phase: string, x: number, z: number }?) -> (),
	onDemoted: ((player: any, words: string) -> ())?, -- Boot/Game: out of the ambulance, a townsperson on screen
	reputation: ((player: any, kind: string, severity: number) -> ())?,
	where: ((x: number, z: number) -> string?)?, -- a district's name for the call
	nearestPlayer: ((x: number, z: number) -> number)?, -- studs to the nearest player's body (an ambulance left there)
	params: Params?, -- DoctorRules.params() override (tests)
}

-- a borrowed responder: the fleet vehicle, the player vehicle drawn for it, the doctor who took it, when it was left
export type Loan = { vehicle: any, device: any, by: number, leftAt: number }

type Doctor = {
	player: any,
	id: number,
	freeSince: number,
	job: Job?,
	reserved: any?, -- the parked responder kept for this doctor's call
}

export type Doctors = {
	joined: (self: Doctors, player: any) -> (),
	left: (self: Doctors, player: any) -> (),
	isDoctor: (self: Doctors, player: any) -> boolean,
	jobOf: (self: Doctors, player: any) -> Job?,
	call: (self: Doctors, caseId: any, x: number, z: number) -> boolean,
	borrow: (self: Doctors, player: any, x: number, z: number, reach: number) -> (any?, string?),
	step: (self: Doctors) -> (),
	doctors: (self: Doctors) -> { any },
	borrowed: (self: Doctors) -> { [any]: Loan },
}

local DoctorService = {}

local function dist(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

function DoctorService.new(deps: Deps): Doctors
	local P = deps.params or DoctorRules.params()
	local list: { [number]: Doctor } = {}
	local loans: { [any]: Loan } = {}

	local function onRung(player: any): boolean
		if deps.roles == nil then
			return false
		end
		local rung, subrole = deps.roles:roleOf(player)
		return rung == "hospital" and subrole == "doctor"
	end

	local function say(d: Doctor, key: string, banner: boolean?)
		deps.tell(d.player, { kind = "doctor", text = DoctorRules.WORDS[key] or key, banner = banner })
	end

	-- the doctor's ambulance: the one they sit in, else the last one they took
	local function loanOf(d: Doctor): (any?, Loan?)
		local best, bestLoan = nil, nil
		for id, loan in loans do
			if loan.by == d.id then
				local pose = deps.poseOf(id)
				if pose and pose.driver == d.id then
					return id, loan
				end
				if bestLoan == nil or loan.leftAt > (bestLoan :: Loan).leftAt then
					best, bestLoan = id, loan
				end
			end
		end
		return best, bestLoan
	end

	local function unreserve(d: Doctor)
		if d.reserved ~= nil then
			deps.traffic:unreserve(d.reserved)
			d.reserved = nil
		end
	end

	local function endJob(d: Doctor)
		d.job = nil
		d.freeSince = deps.now()
		unreserve(d)
		deps.show(d.player, nil)
	end

	local function drop(d: Doctor)
		local job = d.job
		if job then
			deps.infection:doctorRelease(job.case)
		end
		unreserve(d)
		d.job = nil
		deps.show(d.player, nil)
		list[d.id] = nil
	end

	local self: Doctors
	self = {
		joined = function(_s: Doctors, player: any)
			local id = player.UserId :: number
			if list[id] then
				return
			end
			list[id] = { player = player, id = id, freeSince = deps.now(), job = nil, reserved = nil }
			deps.show(player, nil)
		end,

		-- picked something else, left the game, knocked out: the call (if any) goes to the computer's ambulances
		left = function(_s: Doctors, player: any)
			local d = list[player.UserId]
			if d then
				drop(d)
			end
		end,

		isDoctor = function(_s: Doctors, player: any): boolean
			return list[player.UserId] ~= nil and onRung(player)
		end,

		jobOf = function(_s: Doctors, player: any): Job?
			local d = list[player.UserId]
			return if d then d.job else nil
		end,

		call = function(_s: Doctors, caseId: any, x: number, z: number): boolean
			local free = {}
			for id, d in list do
				if d.job == nil and onRung(d.player) then
					local amb = loanOf(d)
					local pose = if amb ~= nil then deps.poseOf(amb) else nil
					table.insert(
						free,
						{ id = id, freeSince = d.freeSince, inAmbulance = pose ~= nil and pose.driver == id }
					)
				end
			end
			local chosen = DoctorRules.chooseDoctor(free)
			if chosen == nil then
				return false
			end
			local d = list[chosen]
			if loanOf(d) == nil then
				-- an ambulance kept for them at the bays; none parked: the computer's go (none free either: it waits)
				local v = deps.traffic:reserveResponder()
				if v == nil then
					return false
				end
				d.reserved = v
			end
			d.job = DoctorRules.newJob(caseId, deps.now())
			local where = if deps.where then deps.where(x, z) else nil
			deps.tell(d.player, { kind = "doctor", text = DoctorRules.callWords(where), banner = true })
			deps.show(d.player, { phase = "called", x = x, z = z })
			return true
		end,

		-- E pressed at (x, z) with nothing of the player fleet's within `reach`: a parked ambulance there? A doctor takes
		-- it (the player vehicle's id: DeviceService seats them in it); anyone else hears why not. Nothing near: nil, nil.
		borrow = function(_s: Doctors, player: any, x: number, z: number, reach: number): (any?, string?)
			local best, bestD = nil, reach
			for _, parked in deps.traffic:parkedResponders() do
				local d = dist(parked.x, parked.z, x, z)
				if d < bestD then
					best, bestD = parked, d
				end
			end
			if best == nil then
				return nil, nil
			end
			local d = list[player.UserId]
			if d == nil or not onRung(player) then
				return nil, DoctorRules.WORDS.doctorsOnly
			end
			local v = best.vehicle
			if v.reserved and v ~= d.reserved then
				-- kept for another doctor's call: this one may take any other parked one
				local other = nil
				for _, parked in deps.traffic:parkedResponders() do
					local pv = parked.vehicle
					if (not pv.reserved or pv == d.reserved) and dist(parked.x, parked.z, x, z) < reach then
						other = parked
					end
				end
				if other == nil then
					return nil, "That ambulance is kept for another doctor's call."
				end
				best = other
				v = other.vehicle
			end
			if not deps.traffic:borrowResponder(v) then
				return nil, DoctorRules.WORDS.noAmbulance
			end
			if d.reserved ~= nil and d.reserved ~= v then
				deps.traffic:unreserve(d.reserved)
			end
			d.reserved = nil
			local id = deps.spawn(best.x, best.z, best.yaw)
			loans[id] = { vehicle = v, device = id, by = d.id, leftAt = deps.now() }
			return id, nil
		end,

		step = function(_s: Doctors)
			local now = deps.now()
			local ids: { number } = {}
			for id in list do
				table.insert(ids, id)
			end
			table.sort(ids)
			for _, id in ids do
				local d = list[id]
				if not onRung(d.player) then
					drop(d) -- (demoted or moved by something else: no longer a doctor)
					continue
				end
				local job = d.job
				if job == nil then
					continue
				end
				local case = deps.infection:doctorCase(job.case)
				local ambId, _loan = loanOf(d)
				local pose = if ambId ~= nil then deps.poseOf(ambId) else nil
				local bx, bz = deps.bodyAt(d.player)
				local facts: { [string]: any } = { gone = case == nil, aboard = case ~= nil and case.aboard }
				if case and pose then
					facts.inAmbulance = pose.driver == id
					facts.ambSpeed = pose.speed
					if case.aboard then
						local near = math.huge
						for _, p in deps.drops do
							near = math.min(near, dist(pose.x, pose.z, p[1], p[2]))
						end
						facts.ambDist = near
					else
						facts.ambDist = dist(pose.x, pose.z, case.x, case.z)
					end
				end
				if case and bx and bz then
					facts.footDist = dist(bx, bz, case.x, case.z)
				end
				for _, e in DoctorRules.step(job :: any, now, facts :: any, P :: any) do
					local kind = e.kind
					if kind == "setOff" or kind == "loaded" then
						say(d, e.key :: string)
					elseif kind == "load" then
						deps.infection:doctorLoad(job.case)
					elseif kind == "unload" then
						if deps.infection:doctorUnload(job.case) and deps.roles then
							deps.roles:report({
								kind = "doctor.delivered",
								player = id,
								pay = P.patientCents,
								fetchSecs = e.fetchSecs,
							})
							deps.tell(d.player, { kind = "doctor", text = DoctorRules.paidWords(P.patientCents) })
						end
						endJob(d)
					elseif kind == "warn" then
						say(d, e.key :: string, true)
					elseif kind == "demote" then
						local key = e.key :: string
						local words = DoctorRules.WORDS[key]
						drop(d)
						if deps.roles then
							deps.roles:demote(d.player, DoctorRules.WHY[key] or key)
						end
						if deps.reputation then
							deps.reputation(d.player, DoctorRules.REPUTATION.kind, DoctorRules.REPUTATION.severity)
						end
						deps.tell(d.player, { kind = "doctor", text = words, banner = true, demoted = true })
						if deps.onDemoted then
							deps.onDemoted(d.player, words)
						end
					elseif kind == "giveBack" then
						deps.infection:doctorRelease(job.case)
						say(d, e.key :: string, true)
						endJob(d)
					elseif kind == "end" then
						say(d, e.key :: string)
						endJob(d)
					end
				end
				-- the call on screen follows the patient (a crowd round them, a walk to the ambulance)
				local still = list[id]
				if still and still.job and case and not case.aboard then
					deps.show(d.player, { phase = still.job.phase, x = case.x, z = case.z })
				elseif still and still.job and case and case.aboard then
					local door = deps.drops[1]
					if door then
						deps.show(d.player, { phase = "loaded", x = door[1], z = door[2] })
					end
				end
			end
			-- the ambulances nobody is using go home
			local busy: { [any]: boolean } = {}
			for _, d in list do
				if d.job then
					local ambId = loanOf(d)
					if ambId ~= nil then
						busy[ambId] = true
					end
				end
			end
			for devId, loan in loans do
				local pose = deps.poseOf(devId)
				if pose == nil then
					loans[devId] = nil
					deps.traffic:returnResponder(loan.vehicle)
					continue
				end
				if pose.driver ~= nil then
					loan.leftAt = now
					continue
				end
				if busy[devId] then
					continue
				end
				local bay = deps.traffic:bayOf(loan.vehicle)
				local fromBay = if bay then dist(pose.x, pose.z, bay.x, bay.z) else 0
				local nearest = math.huge
				for _, d in list do
					local x, z = deps.bodyAt(d.player)
					if x and z then
						nearest = math.min(nearest, dist(pose.x, pose.z, x, z))
					end
				end
				if deps.nearestPlayer then
					nearest = math.min(nearest, deps.nearestPlayer(pose.x, pose.z))
				end
				if DoctorRules.shouldReturn(now, loan.leftAt, fromBay, nearest, P :: any) then
					loans[devId] = nil
					deps.despawn(devId)
					deps.traffic:returnResponder(loan.vehicle)
				end
			end
		end,

		doctors = function(_s: Doctors): { any }
			local out = {}
			for _, d in list do
				table.insert(out, d.player)
			end
			return out
		end,

		borrowed = function(_s: Doctors): { [any]: Loan }
			return loans
		end,
	}
	return self
end

return DoctorService
