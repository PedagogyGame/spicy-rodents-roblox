--!strict
-- ReplicatedStorage.Shared.Work.TownJobs
-- Jobs a townsperson can take at the bowling alley and at the top of the sky lift (owner D30: "Jobs can also be found
-- at the bowling alley, or at the top of the sky lift"), pure.
-- How work paid before this: nothing paid a player for work. Roles/Ladder has the rule ("work.completed": pay from the
-- job, a rank class) and Roles/RoleService pays it into the town's wallet under "work"; Economy/EconomyRules has the
-- wages per in-game hour (the minimum 2 cents; Tunables economy.minWageCentsPerHour says the same) and wage(job,
-- hours); Server/Jobs/JobService was an empty stub; the alley's employees and the Lookout's host are the computer's
-- people on their rounds (Attractions/AlleyStaff, Rides/LookoutLife). These jobs use all of it:
--   * JOBS: the shoe desk and the lanes at the alley (the shoe clerk's and the cleaner's own work stops: on the
--     alley's floors, clear of every wall and lane: tests/unit/alley_staff), and the Lookout attendant at the top of
--     the sky lift (stops on the Lookout's way on foot: the counter, the tables, the terrace, the telescope).
--   * A duty is a stop the worker stands at for its `hold` seconds (the server sees where their body is); duties come
--     in turn, each named ("Next: the spray bench in the shoe rental"), never marked.
--   * PAY: every in-game hour on shift in which the worker finished at least one duty is paid that job's wage for an
--     hour (EconomyRules.wage(job, 1); the wage is in EconomyRules.WAGES.jobs), reported as Ladder "work.completed"
--     (RoleService pays it). An hour with no duty done pays nothing and says so; IDLE_HOURS such hours in a row end
--     the shift.
--   * Who: a townsperson (the Ladder's human rung) in a person's body, at most SLOTS per job at once.
-- Interface: JOBS; byId(id); duties(job, data?) -> { Duty } (world studs); post(job, data?) -> { x, y, z } (the
--   prompt); start(job, duties, hour) -> Shift; step(shift, hour, at?, dt) -> event? ("duty" | "paid" | "unpaid" |
--   "idle"), with shift.paidHour set on "paid"; next(shift) -> Duty; SLOTS, NEAR, IDLE_HOURS, CLASS
-- Pure; studs. No side effects on require.

local AlleyLayout = require("../Attractions/AlleyLayout")
local AlleyStaff = require("../Attractions/AlleyStaff")
local LookoutLife = require("../Rides/LookoutLife")
local Data = require("../Data")

local TownJobs = {}

TownJobs.SLOTS = 2 -- players on one job at once
TownJobs.NEAR = 3.5 -- studs from a duty's spot (plan) that count as at it
TownJobs.HEIGHT = 6 -- ... and studs above or below it (the right floor)
TownJobs.IDLE_HOURS = 3 -- in-game hours in a row with no duty done end the shift
-- the Ladder's work.completed rank class: none (the pay counts toward the queue through the money term already)
TownJobs.CLASS = "shift"

export type Duty = { x: number, y: number, z: number, hold: number, label: string }
export type Job = {
	id: string, -- also the wage's key (EconomyRules.WAGES.jobs)
	title: string,
	venue: string, -- "alley" | "lookout"
	where: string, -- said when the job is taken
}

-- stylua: ignore
TownJobs.JOBS = table.freeze({
	{ id = "shoe_desk", title = "Shoe desk attendant", venue = "alley", where = "the shoe rental at the bowling alley" },
	{ id = "lane_attendant", title = "Lane attendant", venue = "alley", where = "the lanes at the bowling alley" },
	{ id = "lookout_attendant", title = "Lookout attendant", venue = "lookout", where = "the Lookout at the top of the sky lift" },
} :: { Job })

-- what each alley act is, as a duty's words
-- stylua: ignore
local ACT_WORDS: { [string]: string } = {
	serve = "the shoe desk", fetch = "the shoe cubbies", collect = "the returns window", spray = "the spray bench",
	shelve = "the shoe cubbies", mop = "dust-mop the back of the approaches", polish = "wipe the house balls on the west aisle shelves",
}
-- the Lookout attendant's duties: a node of Rides/LookoutLife, how long, and the words
-- stylua: ignore
local LOOKOUT: { { any } } = {
	{ "b_36", 5, "the counter" },
	{ "f_8", 4, "the window side of table 2" },
	{ "t_m6", 4, "terrace table 1" },
	{ "telescope", 4, "the telescope" },
	{ "r_29", 4, "the rail side of terrace table 3" },
	{ "b_m6", 4, "the fireside side of table 1" },
}

function TownJobs.byId(id: string): Job?
	for _, j in TownJobs.JOBS do
		if j.id == id then
			return j
		end
	end
	return nil
end

local function lookoutPlace(data: any): AlleyLayout.Place
	for _, v in (data:module("Expansion") :: any).venues do
		if v.id == "f3_hilltop" then
			return { x = v.position.x, z = v.position.z, floorY = v.floorY, yaw = v.yaw }
		end
	end
	error("TownJobs: no f3_hilltop venue")
end

-- The job's duties in turn (world studs).
function TownJobs.duties(job: Job, data: any?): { Duty }
	local d = data or Data.default()
	local out: { Duty } = {}
	if job.venue == "alley" then
		local place = AlleyStaff.placeOf(d)
		assert(place, "TownJobs: no bowling alley in the data")
		local employee = AlleyStaff.employee(if job.id == "shoe_desk" then "shoe_clerk" else "cleaner")
		local seen: { [string]: boolean } = {}
		for _, s in AlleyStaff.shift(place :: any, employee) do
			if s.hold > 0 then
				local key = `{math.floor(s.x * 2)},{math.floor(s.z * 2)}`
				local y = AlleyStaff.floorAt(place :: any, s.x, s.z) or place.floorY
				-- (the cleaner's strokes along the approaches: every other one, and the same spot only once)
				if not seen[key] then
					seen[key] = true
					table.insert(out, {
						x = s.x,
						y = y,
						z = s.z,
						hold = math.max(3, s.hold),
						label = ACT_WORDS[s.act or ""] or "the next job",
					})
				end
			end
		end
		if job.id == "lane_attendant" then
			local thin: { Duty } = {}
			for i, u in out do
				if i % 3 == 1 or u.label ~= ACT_WORDS.mop then
					table.insert(thin, u)
				end
			end
			out = thin
		end
	else
		local place = lookoutPlace(d)
		for _, row in LOOKOUT do
			local n = LookoutLife.NODES[row[1]]
			local x, y, z = AlleyLayout.toWorld(place, n[1], n[3], n[2])
			table.insert(out, { x = x, y = y, z = z, hold = row[2], label = row[3] })
		end
	end
	return out
end

-- Where the job is taken (its prompt): its first duty's spot.
function TownJobs.post(job: Job, data: any?): { number }
	local first = TownJobs.duties(job, data)[1]
	return { first.x, first.y, first.z }
end

export type Shift = {
	job: Job,
	duties: { Duty },
	i: number, -- the duty to do next
	held: number, -- seconds at it so far
	hour: number, -- the in-game hour being worked (floor of the game clock's hours)
	doneThisHour: number,
	idle: number, -- hours in a row with nothing done
	done: number, -- duties done in all
	paidHour: number?, -- the hour the last "paid" was for
}

-- `hour`: the game clock in in-game hours (fractional; Time/Clock's seconds / 3600).
function TownJobs.start(job: Job, duties: { Duty }, hour: number): Shift
	return {
		job = job,
		duties = duties,
		i = 1,
		held = 0,
		hour = math.floor(hour),
		doneThisHour = 0,
		idle = 0,
		done = 0,
		paidHour = nil,
	}
end

function TownJobs.next(shift: Shift): Duty
	return shift.duties[shift.i]
end

-- One step: `at` is where the worker's body stands (x, y, z; nil: not in a person's body). Returns at most one event:
--   "paid"    an in-game hour ended with a duty done in it (shift.paidHour is that hour: pay it);
--   "unpaid"  an hour ended with none done (no pay); "idle" when IDLE_HOURS such hours in a row: the shift ends;
--   "duty"    the duty in hand is done (shift.i has moved on to the next).
function TownJobs.step(shift: Shift, hour: number, at: { number }?, dt: number): string?
	local h = math.floor(hour)
	if h > shift.hour then
		local worked = shift.doneThisHour > 0
		local was = shift.hour
		shift.hour = h
		shift.doneThisHour = 0
		if worked then
			shift.idle = 0
			shift.paidHour = was
			return "paid"
		end
		shift.idle += h - was
		return if shift.idle >= TownJobs.IDLE_HOURS then "idle" else "unpaid"
	end
	local duty = shift.duties[shift.i]
	if at and duty then
		local near = math.sqrt((at[1] - duty.x) ^ 2 + (at[3] - duty.z) ^ 2) <= TownJobs.NEAR
			and math.abs(at[2] - duty.y) <= TownJobs.HEIGHT
		if near then
			shift.held += math.max(0, dt)
			if shift.held >= duty.hold then
				shift.held = 0
				shift.done += 1
				shift.doneThisHour += 1
				shift.i = shift.i % #shift.duties + 1
				return "duty"
			end
		else
			shift.held = 0
		end
	end
	return nil
end

return TownJobs
