--!strict
-- ServerScriptService.Server.Jobs.JobService
-- Jobs a townsperson takes at the bowling alley and at the top of the sky lift (owner D30; the rules are
-- Shared/Work/TownJobs: read its header for how work pays and what a duty is). The server decides everything:
--   * A prompt at each job's post ("Work here", the job's title): a townsperson (the Ladder's human rung) in a
--     person's body takes the job if it has a free slot (TownJobs.SLOTS); pressing it again clocks off. One job at
--     a time. The first duty is named on their screen, and each next one as the last is done.
--   * Every in-game hour with a duty done is paid that job's wage for the hour through the existing pay path:
--     roles:report({ kind = "work.completed", player = UserId, pay = EconomyRules.wage(job, 1), class =
--     TownJobs.CLASS }) (Roles/RoleService pays it into the wallet under "work"); with no roles, wallet.add.
--   * An hour with nothing done pays nothing (said); TownJobs.IDLE_HOURS of them in a row end the shift, as do
--     leaving the server, becoming something other than a person, or leaving the townsperson rung.
--   * Presses closer than PRESS_GAP are ignored.
-- Cost: one prompt part per job (three); step() every STEP_PERIOD looks at the workers on shift (at most six).
-- Engine only through deps (defaults use the engine); no side effects on require.
-- Interface: new(deps) -> Service { press(player, jobId) -> (ok, words), step(dt), leave(player), shiftOf(player),
--   stop() }; start(deps) -> Service (prompts, Heartbeat, PlayerRemoving); PRESS_GAP, STEP_PERIOD, WORDS, FOLDER

local Import = require("../Import")
local TownJobs = Import.shared("Work/TownJobs") :: typeof(require("../../shared/Work/TownJobs"))
local EconomyRules = Import.shared("Economy/EconomyRules") :: typeof(require("../../shared/Economy/EconomyRules"))
local Bank = Import.shared("Economy/Bank") :: typeof(require("../../shared/Economy/Bank"))

local JobService = {}
JobService.__index = JobService

JobService.PRESS_GAP = 0.6
JobService.STEP_PERIOD = 0.25
JobService.PROMPT_DISTANCE = 8
JobService.FOLDER = "TownJobs"

JobService.WORDS = table.freeze({
	notTownsperson = "Only townspeople take these jobs",
	notPerson = "Pick a person from the menu first (M)",
	full = "Both %s places are taken: try again later",
	other = "You already work as %s: clock off there first",
	started = "You work as %s at %s: %s an in-game hour while you keep at it. First: %s.",
	next = "Done. Next: %s.",
	paid = "+%s for an hour as %s.",
	unpaid = "Nothing done this hour, so no pay. Next: %s.",
	ended = "You clocked off as %s.",
	idle = "You stopped working as %s (nothing done for a while).",
})

export type Deps = {
	roles: any?, -- Roles/RoleService (roleOf, report); nil: wallet.add pays, anyone may work
	wallet: any?, -- Economy/Credits (the fallback pay)
	bodyOf: (player: any) -> any?,
	isPerson: (player: any) -> boolean,
	notify: (player: any, text: string) -> (),
	gameHours: () -> number, -- the game clock in in-game hours
	now: (() -> number)?,
	posOf: ((body: any) -> { number }?)?, -- x, y, z (default: the Model's pivot)
	data: any?,
}

local function enginePos(body: any): { number }?
	if typeof(body) ~= "Instance" or not body:IsA("Model") then
		return nil
	end
	local ok, cf = pcall(function()
		return (body :: Model):GetPivot()
	end)
	return if ok then { cf.Position.X, cf.Position.Y, cf.Position.Z } else nil
end

local function userId(player: any): any
	local ok, id = pcall(function()
		return (player :: any).UserId
	end)
	return if ok and id ~= nil then id else player
end

function JobService.new(deps: Deps): any
	local self = setmetatable({}, JobService) :: any
	self.deps = deps
	self.now = deps.now or os.clock
	self.posOf = deps.posOf or enginePos
	self.shifts = {} :: { [any]: any } -- player -> TownJobs.Shift
	self.duties = {} :: { [string]: { any } }
	for _, job in TownJobs.JOBS do
		self.duties[job.id] = TownJobs.duties(job, deps.data)
	end
	self.lastPress = {} :: { [any]: number }
	self.acc = 0
	self.stopped = false
	self.conns = {} :: { any }
	self.parts = {} :: { any }
	return self
end

function JobService.shiftOf(self: any, player: any): any?
	return self.shifts[player]
end

local function townsperson(self: any, player: any): boolean
	local roles = (self.deps :: Deps).roles
	if roles == nil then
		return true
	end
	local ok, rung = pcall(roles.roleOf, roles, player)
	return ok and rung == "human"
end

function JobService._end(self: any, player: any, fmt: string)
	local s = self.shifts[player]
	if s then
		self.shifts[player] = nil
		pcall(function()
			(player :: any):SetAttribute("Job", nil)
		end)
		self.deps.notify(player, string.format(fmt, s.job.title))
	end
end

function JobService.press(self: any, player: any, jobId: string): (boolean, string?)
	local deps = self.deps :: Deps
	local now = self.now()
	local last = self.lastPress[player]
	if last and now - last < JobService.PRESS_GAP then
		return false, nil
	end
	self.lastPress[player] = now
	local job = TownJobs.byId(jobId)
	if job == nil then
		return false, nil
	end
	local W = JobService.WORDS
	local mine = self.shifts[player]
	if mine then
		if mine.job.id == jobId then
			self:_end(player, W.ended)
			return true, string.format(W.ended, job.title)
		end
		local text = string.format(W.other, string.lower(mine.job.title))
		deps.notify(player, text)
		return false, text
	end
	local why: string? = nil
	if not deps.isPerson(player) or deps.bodyOf(player) == nil then
		why = W.notPerson
	elseif not townsperson(self, player) then
		why = W.notTownsperson
	else
		local n = 0
		for _, s in self.shifts do
			if s.job.id == jobId then
				n += 1
			end
		end
		if n >= TownJobs.SLOTS then
			why = string.format(W.full, string.lower(job.title))
		end
	end
	if why then
		deps.notify(player, why)
		return false, why
	end
	local shift = TownJobs.start(job, self.duties[jobId], deps.gameHours())
	self.shifts[player] = shift
	pcall(function()
		(player :: any):SetAttribute("Job", job.id)
	end)
	local text = string.format(
		W.started,
		string.lower(job.title),
		job.where,
		Bank.amount(EconomyRules.wage(job.id, 1)),
		TownJobs.next(shift).label
	)
	deps.notify(player, text)
	return true, text
end

function JobService._pay(self: any, player: any, job: any)
	local deps = self.deps :: Deps
	local cents = EconomyRules.wage(job.id, 1)
	local paid = false
	if deps.roles then
		local ok = pcall(function()
			deps.roles:report({ kind = "work.completed", player = userId(player), pay = cents, class = TownJobs.CLASS })
		end)
		paid = ok
	elseif deps.wallet then
		paid = deps.wallet.add(player, cents, "work")
	end
	if paid then
		deps.notify(player, string.format(JobService.WORDS.paid, Bank.amount(cents), string.lower(job.title)))
	end
end

function JobService.step(self: any, dt: number?)
	if self.stopped then
		return
	end
	self.acc += dt or JobService.STEP_PERIOD
	if self.acc < JobService.STEP_PERIOD then
		return
	end
	local span = self.acc
	self.acc = 0
	local deps = self.deps :: Deps
	local W = JobService.WORDS
	local hour = deps.gameHours()
	for player, shift in table.clone(self.shifts) :: { [any]: any } do
		if not deps.isPerson(player) or not townsperson(self, player) then
			self:_end(player, W.ended)
			continue
		end
		local body = deps.bodyOf(player)
		local at = if body then self.posOf(body) else nil
		local what = TownJobs.step(shift, hour, at, span)
		if what == "paid" then
			self:_pay(player, shift.job)
		elseif what == "unpaid" then
			deps.notify(player, string.format(W.unpaid, TownJobs.next(shift).label))
		elseif what == "idle" then
			self:_end(player, W.idle)
		elseif what == "duty" then
			deps.notify(player, string.format(W.next, TownJobs.next(shift).label))
		end
	end
end

function JobService.leave(self: any, player: any)
	self.shifts[player] = nil
	self.lastPress[player] = nil
end

function JobService.stop(self: any)
	self.stopped = true
	for _, c in self.conns do
		c:Disconnect()
	end
	table.clear(self.conns)
	for _, p in self.parts do
		pcall(function()
			p:Destroy()
		end)
	end
	table.clear(self.parts)
	table.clear(self.shifts)
end

-- The job posts in the world: an invisible post at each job's first duty with its E prompt (Door = true).
function JobService._build(self: any, parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = JobService.FOLDER
	folder.Parent = parent
	table.insert(self.parts, folder)
	for _, job in TownJobs.JOBS do
		local at = TownJobs.post(job, self.deps.data)
		local post = Instance.new("Part")
		post.Name = `JobPost_{job.id}`
		post.Anchored = true
		post.CanCollide = false
		post.CanQuery = false
		post.CanTouch = false
		post.Transparency = 1
		post.Size = Vector3.new(0.4, 0.4, 0.4)
		post.CFrame = CFrame.new(at[1], at[2] + 3, at[3])
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "JobPrompt"
		prompt.ActionText = "Work here"
		prompt.ObjectText = `{job.title} ({Bank.amount(EconomyRules.wage(job.id, 1))} an hour)`
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = JobService.PROMPT_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("Door", true)
		prompt:SetAttribute("Job", job.id)
		prompt.Parent = post
		local id = job.id
		table.insert(
			self.conns,
			prompt.Triggered:Connect(function(player: Player)
				local ok, err = pcall(self.press, self, player, id)
				if not ok then
					warn(`[Jobs] press failed: {err}`)
				end
			end)
		)
		post.Parent = folder
	end
end

function JobService.start(deps: Deps & { heartbeat: boolean?, parent: Instance? }): any
	local self = JobService.new(deps)
	self:_build(deps.parent or workspace)
	if deps.heartbeat ~= false then
		table.insert(
			self.conns,
			game:GetService("RunService").Heartbeat:Connect(function(dt: number)
				local ok, err = pcall(self.step, self, dt)
				if not ok then
					warn(`[Jobs] step failed: {err}`)
				end
			end)
		)
	end
	table.insert(
		self.conns,
		game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
			self:leave(player)
		end)
	)
	return self
end

return JobService
