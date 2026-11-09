--!strict
-- ServerScriptService.Server.Actors.Brains.Staff
-- Staff circuit brain, minimal W0 version (spike S5): hospital staff, ambulance crews, attraction
-- staff and the precinct guard walk a short loop of local waypoints around a station and pause at
-- each (hospital_police_infection §5.3: advance within 0.75 u, pause 0.24 s staff / 0.48 patients;
-- the patient circuit shape station -> +(dir 2.6, -0.65) -> +(dir 2.1, -2.8) -> +(0, -2.0), start index
-- i % 4, initial pause 0.4 + (i % 3) 0.3). Pace 1.4 u/s is a W0 tunable (the spec names none).
-- Interface: new(actor, params), think, suspend, resume, onEvent. Pure; studs via Config/Units.

local Import = require("../../AI/Import")
local Units = Import.shared("Config/Units") :: typeof(require("../../../shared/Config/Units"))
local Common = require("./Common")

export type Params = {
	stationX: number, -- studs
	stationZ: number,
	index: number, -- staff member index (circuit direction and phase)
	patient: boolean?,
	circuit: { { number } }?, -- optional explicit local circuit (studs offsets)
}

type Brain = Common.Brain & {
	actor: Common.Actor,
	params: Params,
	points: { { number } }, -- absolute (x, z)
	target: number,
	pause: number,
}

local Staff = {}

local REACH = Units.st(0.75)
local PAUSE_STAFF, PAUSE_PATIENT = 0.24, 0.48
local PACE = Units.st(1.4)

local Methods = {}
Methods.__index = Methods

function Methods.think(self: Brain, dt: number, _ctx: Common.Ctx)
	local actor = self.actor
	local intent = actor.intent
	local p = self.points[self.target]
	local d = Common.dist2d(actor.x, actor.z, p[1], p[2])
	if self.pause > 0 then
		self.pause = math.max(0, self.pause - dt)
		intent.mode = "stand"
		return
	end
	if d < REACH then
		self.target = self.target % #self.points + 1
		self.pause = if self.params.patient then PAUSE_PATIENT else PAUSE_STAFF
		intent.mode = "stand"
		return
	end
	intent.mode = "walk"
	intent.tx, intent.tz = p[1], p[2]
	intent.laneAxis = nil
	intent.speed = PACE
	intent.turnRate = 6
	intent.damp = 8
end

function Methods.suspend(self: Brain): Common.Snapshot
	return { target = self.target, pause = self.pause }
end

function Methods.resume(self: Brain, snapshot: Common.Snapshot)
	self.target = snapshot.target or 1
	self.pause = snapshot.pause or 0
end

function Methods.onEvent(self: Brain, evt: { [string]: any })
	if evt.type == "pause" then
		self.pause = math.max(self.pause, evt.seconds or 1)
	end
end

function Staff.new(actor: Common.Actor, params: Params): Common.Brain
	local i = params.index
	local dir = if i % 2 == 1 then 1 else -1
	local st = Units.st
	local localCircuit = params.circuit
		or {
			{ 0, 0 },
			{ dir * st(2.6), -st(0.65) },
			{ dir * st(2.1), -st(2.8) },
			{ 0, -st(2.0) },
		}
	local points = {}
	for _, lp in localCircuit do
		table.insert(points, { params.stationX + lp[1], params.stationZ + lp[2] })
	end
	local start = (i % #points) + 1
	local self = setmetatable({
		kind = "Staff",
		actor = actor,
		params = params,
		points = points,
		target = start,
		pause = 0.4 + (i % 3) * 0.3,
	}, Methods)
	actor.x, actor.z = points[start][1], points[start][2]
	return (self :: any) :: Common.Brain
end

return Staff
