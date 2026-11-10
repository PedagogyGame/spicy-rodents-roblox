--!strict
-- ServerScriptService.Server.Actors.Brains.Directive
-- An order that overrides a human brain for a while (the bite-to-hospital sequence, owner 2026-11-10):
-- the Pedestrian, Staff and Officer brains each keep one Directive state and ask it first on every
-- think; while it is active the brain's own behaviour (walking the lane, the circuit, spotting and
-- fleeing) is off, and when it ends the brain carries on from where the person now stands.
--   down    stay put (a patient on the ground, a patient in a bed); `face` turns them to a point.
--   hidden  stay put, out of sight (a patient in the ambulance; the service also sinks the body).
--   route   walk the waypoints in order at `speed` with no lane lock; `after` says what then:
--           "clear" (the default: the brain resumes) or "stand" (wait there for the next order).
--           `stagger` makes the pace uneven (a sick person walking in).
--   hold    walk straight to (x, z) at `speed`, then stand facing (faceX, faceZ): a bystander.
--   nil     clear the order.
-- Kinematic like everything else here: it only writes the actor's intent; Movement/HumanAIMotor moves
-- the body. A brain may think as rarely as once a second (LOD), so a waypoint counts as reached within
-- REACH and the motor stops exactly on it in between.
-- Interface: new() -> State; set(state, evt); active(state) -> boolean; think(state, actor, dt, ctx)
--   -> boolean (true while the order holds); takeReleased(state) -> boolean (true once after an order
--   ended); snapshot(state) -> table; restore(state, snap); REACH
-- Pure; studs. No side effects on require.

local Common = require("./Common")

export type State = {
	mode: string?, -- nil | "down" | "hidden" | "route" | "hold"
	points: { { number } },
	index: number,
	speed: number,
	after: string, -- "clear" | "stand"
	stagger: boolean,
	done: boolean, -- route walked, or hold spot reached
	x: number,
	z: number,
	faceX: number?,
	faceZ: number?,
	released: boolean, -- an order ended since the brain last asked
	seq: number, -- bumped by every set (callers match an order to its completion)
}

local Directive = {}

Directive.REACH = 2 -- studs

function Directive.new(): State
	return {
		mode = nil,
		points = {},
		index = 1,
		speed = 0,
		after = "clear",
		stagger = false,
		done = false,
		x = 0,
		z = 0,
		faceX = nil,
		faceZ = nil,
		released = false,
		seq = 0,
	}
end

-- set(state, evt): evt.mode names the order (nil clears). Fields per mode are in the header.
function Directive.set(state: State, evt: { [string]: any })
	local mode = evt.mode
	local had = state.mode ~= nil
	state.seq += 1
	state.done = false
	state.faceX, state.faceZ = evt.faceX, evt.faceZ
	if mode == "route" and type(evt.points) == "table" and #evt.points > 0 then
		state.mode = "route"
		state.points = evt.points
		state.index = 1
		state.speed = evt.speed or 8
		state.after = if evt.after == "stand" then "stand" else "clear"
		state.stagger = evt.stagger == true
	elseif mode == "hold" then
		state.mode = "hold"
		state.x, state.z = evt.x, evt.z
		state.speed = evt.speed or 8
	elseif mode == "down" or mode == "hidden" then
		state.mode = mode
	else
		state.mode = nil
		if had then
			state.released = true
		end
	end
end

function Directive.active(state: State): boolean
	return state.mode ~= nil
end

-- takeReleased: true once after an order ended (the brain then finds its way back to its own life).
function Directive.takeReleased(state: State): boolean
	if state.released then
		state.released = false
		return true
	end
	return false
end

local function stand(actor: Common.Actor, faceX: number?, faceZ: number?)
	local intent = actor.intent
	intent.mode = "stand"
	intent.speed = 0
	intent.laneAxis, intent.laneCoord = nil, nil
	if faceX and faceZ and (math.abs(faceX - actor.x) + math.abs(faceZ - actor.z)) > 0.5 then
		intent.heading = Common.yawOf(faceX - actor.x, faceZ - actor.z)
	else
		intent.heading = 0 -- the motor leaves the yaw alone
	end
end

local function walk(actor: Common.Actor, x: number, z: number, speed: number)
	local intent = actor.intent
	intent.mode = "walk"
	intent.tx, intent.tz = x, z
	intent.laneAxis, intent.laneCoord = nil, nil
	intent.speed = speed
	intent.turnRate = 6
	intent.damp = 8
end

-- think: writes the intent for the active order. Returns false when there is none (the brain thinks).
function Directive.think(state: State, actor: Common.Actor, _dt: number, ctx: Common.Ctx): boolean
	local mode = state.mode
	if mode == nil then
		return false
	end
	if mode == "down" or mode == "hidden" then
		stand(actor, state.faceX, state.faceZ)
		return true
	end
	if mode == "hold" then
		if Common.dist2d(actor.x, actor.z, state.x, state.z) < Directive.REACH then
			state.done = true
			stand(actor, state.faceX, state.faceZ)
		else
			walk(actor, state.x, state.z, state.speed)
		end
		return true
	end
	-- route
	local points = state.points
	while state.index <= #points do
		local p = points[state.index]
		if Common.dist2d(actor.x, actor.z, p[1], p[2]) >= Directive.REACH then
			break
		end
		state.index += 1
	end
	if state.index > #points then
		state.done = true
		if state.after == "stand" then
			stand(actor, state.faceX, state.faceZ)
			return true
		end
		state.mode = nil
		state.released = true
		return false
	end
	local p = points[state.index]
	local speed = state.speed
	if state.stagger then
		-- an uneven pace: slows to about half and picks up again every few seconds
		speed *= 0.55 + 0.45 * math.abs(math.sin(ctx.now * 0.9 + actor.id))
	end
	walk(actor, p[1], p[2], speed)
	return true
end

function Directive.snapshot(state: State): { [string]: any }
	return {
		mode = state.mode,
		points = state.points,
		index = state.index,
		speed = state.speed,
		after = state.after,
		stagger = state.stagger,
		done = state.done,
		x = state.x,
		z = state.z,
		faceX = state.faceX,
		faceZ = state.faceZ,
		seq = state.seq,
	}
end

function Directive.restore(state: State, snap: { [string]: any }?)
	if type(snap) ~= "table" then
		return
	end
	local s = snap :: { [string]: any }
	state.mode = s.mode
	state.points = s.points or {}
	state.index = s.index or 1
	state.speed = s.speed or 0
	state.after = s.after or "clear"
	state.stagger = s.stagger == true
	state.done = s.done == true
	state.x, state.z = s.x or 0, s.z or 0
	state.faceX, state.faceZ = s.faceX, s.faceZ
	state.seq = s.seq or state.seq
end

return Directive
