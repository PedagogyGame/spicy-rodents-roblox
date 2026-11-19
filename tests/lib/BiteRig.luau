--!strict
-- tests/lib/BiteRig: the town as Boot/Game runs it round a bite, headless: the real town AI (AI/TownAI, the 102 actors on
-- the real lanes), the real fleet (Traffic/TrafficService, the ambulances among it), the bite-to-hospital sequence
-- (Infection/InfectionService) and the duel (Combat/CombatService), stepped in Boot/Game.step's order (the town, the
-- fleet, the sequence, then the duel every 0.1 s). What a player would see is recorded as it is written: every
-- replicated attribute a body gets (Med, Say and SayAt, the duel's Stance and PounceAt), every toast a player is sent
-- (the sequence's "med" news and the duel's events), and the ambulances' poses.
-- The Spicy Rodent is the town's own rodent actor. `holdRodent()` makes it a player's (its brain stops, the test
-- moves it), as Boot/Game's possession does; `hold(id)` does the same for a townsperson (a player-held victim).
-- With opts.overhead the town's overhead watch runs too (Server/Stealth/OverheadService, wired as Boot/Game wires it:
-- the duel asks it who has spotted the rodent overhead): rig.overhead, rig.gazes[id] (the point a head turns to), the
-- rodent's eye in rig.eye[id] = { meter, seen }.
-- Interface: new(opts?) -> Rig; Rig.step(secs, each?); Rig.runUntil(limit, done, each?) -> boolean;
--   Rig.hold(id); Rig.let(id); Rig.put(id, x, z, yaw?); Rig.near(x, z, post?, skip?) -> actor; Rig.calmNear(x, z, skip?) -> actor; Rig.responders() -> { vehicle };
--   Rig.saidBy(situation) -> { said }; Rig.dice(list) (the sequence's next dice); Rig.lunge(victimId, from?) ->
--   boolean (a player's pounce through the duel); Rig.now(); fields world, traffic, infection, combat (Combat/
--   CombatService, unless opts.duel is false), health, blows, duelNews, motor, attrs, medLog, toasts, said, time
-- Studs throughout.
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local InfectionRules = require("@shared/Infection/InfectionRules")
local Lines = require("@shared/Speech/Lines")
local Rng = require("@shared/Util/Rng")
local TownAI = require("@server/AI/TownAI")
local TrafficService = require("@server/Traffic/TrafficService")
local InfectionService = require("@server/Infection/InfectionService")
local CombatService = require("@server/Combat/CombatService")
local OverheadService = require("@server/Stealth/OverheadService")

local BiteRig = {}

BiteRig.DT = 0.2

export type Said = { id: number, line: string, situation: string?, t: number }

export type Options = {
	seed: number?, -- the dice after `first` (default 1)
	first: { number }?, -- the sequence's first dice (InfectionService's rand): the bite's path and timers
	tune: ((params: any) -> ())?, -- InfectionRules params
	dt: number?,
	duel: boolean?, -- run Combat/CombatService (default true)
	duelRand: (() -> number)?, -- the duel's dice (default: seeded)
	biteRand: (() -> number)?, -- the dice for the bite itself (default: the duel's)
	motorCheck: boolean?, -- the duel asks for the rodent's motor state (rig.motor[id]) before a bite
	overhead: boolean?, -- run Server/Stealth/OverheadService (the people look up at a squirrel overhead), stepped every
	-- rig step as Boot/Game steps it; a held squirrel's route is rig.route[id] (nil: it has sent nothing)
	overheadRand: (() -> number)?, -- its dice (default: seeded)
}

local data: any = nil
local rail: any = nil

local function situationOf(line: string): string?
	for _, s in Lines.SITUATIONS do
		if table.find(Lines.GROUPS[s], line) then
			return s
		end
	end
	return nil
end

function BiteRig.new(opts: Options?): any
	local o = opts or {}
	data = data or Data.default()
	local world = TownAI.build({ data = data, seed = 1, squirrels = 3, deer = 0, fox = 0, rail = rail })
	rail = world.rail
	local traffic = TrafficService.new({ lanes = data:lanes(), roads = data:roads(), heightAt = Height.at, seed = 7 })
	local rng = Rng.new(o.seed or 1)
	local scripted = table.clone(o.first or {})
	local params = InfectionRules.defaults()
	if o.tune then
		o.tune(params)
	end
	local rig = {
		data = data,
		world = world,
		traffic = traffic,
		attrs = {},
		medLog = {},
		toasts = {},
		said = {},
		players = {},
		possessable = {},
		time = 0,
		dt = o.dt or BiteRig.DT,
		rodent = 0,
		combat = nil,
	} :: any
	for _, a in world.actors do
		if a.variant == "spicy" then
			rig.rodent = a.id
		end
	end
	rig.infection = InfectionService.new({
		world = world,
		traffic = traffic,
		data = data,
		params = params,
		rand = function(): number
			if #scripted > 0 then
				return table.remove(scripted, 1) :: number
			end
			return rng.next()
		end,
		controllerOf = function(id: number): string
			return if rig.players[id] then "player" else "ai"
		end,
		driverOf = function(id: number): any?
			return if rig.players[id] then `player{id}` else nil
		end,
		setAttr = function(id: number, name: string, value: any)
			rig.setAttr(id, name, value)
		end,
		setPossessable = function(id: number, value: boolean)
			rig.possessable[id] = value
		end,
		notify = function(id: number, payload: { [string]: any })
			table.insert(
				rig.toasts,
				{ id = id, key = payload.key, kind = payload.kind, text = payload.text, t = rig.time }
			)
		end,
		serverTime = function(): number
			return 5000 + rig.time
		end,
	})
	-- the next dice the sequence rolls (a bite's path and timers), ahead of the seeded ones
	rig.dice = function(list: { number })
		for i, v in list do
			table.insert(scripted, i, v)
		end
	end
	rig.setAttr = function(id: number, name: string, value: any)
		rig.attrs[id] = rig.attrs[id] or {}
		if rig.attrs[id][name] == value then
			return
		end
		rig.attrs[id][name] = value
		if name == "Med" then
			rig.medLog[id] = rig.medLog[id] or {}
			table.insert(rig.medLog[id], if value == nil then "-" else value)
		elseif name == "Say" and type(value) == "string" then
			table.insert(rig.said, { id = id, line = value, situation = situationOf(value), t = rig.time })
		end
	end
	-- the duel, wired as Boot/Game wires it: the held rodent fights; a bite starts the sequence; a blow costs health
	rig.health = {}
	rig.duelNews = {}
	rig.blows = {}
	rig.motor = {}
	if o.duel ~= false then
		local drng = Rng.new((o.seed or 1) + 101)
		rig.combat = CombatService.new({
			world = world,
			infection = rig.infection,
			rand = o.duelRand or function(): number
				return drng.next()
			end,
			biteRand = o.biteRand,
			controllerOf = function(id: number): string
				return if rig.players[id] then "player" else "ai"
			end,
			rodents = function(): { number }
				return if rig.players[rig.rodent] then { rig.rodent } else {}
			end,
			motorOf = if o.motorCheck
				then function(id: number): any
					return rig.motor[id]
				end
				else nil,
			setAttr = function(id: number, name: string, value: any)
				rig.setAttr(id, name, value)
			end,
			notify = function(id: number, payload: { [string]: any })
				table.insert(rig.duelNews, { id = id, what = payload.what, t = rig.time, payload = payload })
			end,
			hurt = function(id: number, amount: number, cause: string, by: number)
				rig.health[id] = math.max(0, (rig.health[id] or 100) - amount)
				table.insert(rig.blows, { id = id, amount = amount, cause = cause, by = by, t = rig.time })
			end,
			bitten = function(victim: number, biter: number)
				rig.infection:bite(victim, biter, "rodentPlayer")
			end,
		})
	end
	rig.route = {}
	rig.gazes = {}
	rig.eye = {}
	if o.overhead then
		local orng = Rng.new((o.seed or 1) + 202)
		rig.overhead = OverheadService.new({
			world = world,
			infection = rig.infection,
			combat = rig.combat,
			motorOf = function(id: number): any
				local r = rig.route[id]
				-- (false: standing on a part's top, no route in its packets)
				return if r == nil then nil else { routeId = if r == false then nil else r, grounded = r == false }
			end,
			setAttr = function(id: number, name: string, value: any)
				rig.setAttr(id, name, value)
			end,
			gaze = function(id: number, x: number?, y: number?, z: number?)
				rig.gazes[id] = if x then { x, y, z } else nil
			end,
			cue = function(id: number, meter: number?, seen: boolean?)
				rig.eye[id] = if meter == nil then nil else { meter = meter, seen = seen }
			end,
			serverTime = function(): number
				return 5000 + rig.time
			end,
			rand = o.overheadRand or function(): number
				return orng.next()
			end,
		})
		if rig.combat then
			rig.combat.opts.overhead = function(person: number, rodent: number): boolean
				return rig.overhead:spotted(person, rodent)
			end
			rig.combat.opts.under = function(person: number, rodent: number): (number?, number?)
				return rig.overhead:spotUnder(person, rodent)
			end
		end
	end
	local people = {}
	local function trafficWorld()
		table.clear(people)
		for _, a in world.actors do
			if a.species == "human" then
				for _, v in traffic.vehicles do
					if v.visible and (v.x - a.x) ^ 2 + (v.z - a.z) ^ 2 < 70 * 70 then
						table.insert(people, {
							kind = "human",
							x = a.x,
							y = a.y - a.hip,
							z = a.z,
							hospital = rig.infection:trafficFlags(a.id),
							visible = (a.lift or 0) == 0,
						})
						break
					end
				end
			end
		end
		return { people = people }
	end
	local duelAcc = 0
	rig.step = function(secs: number, each: (() -> ())?)
		local dt = rig.dt
		for _ = 1, math.max(1, math.floor(secs / dt + 0.5)) do
			rig.time += dt
			TownAI.stepFrame(world, dt)
			traffic:step(dt, trafficWorld())
			rig.infection:step(dt)
			if rig.overhead then
				rig.overhead:step(dt)
			end
			if rig.combat then
				duelAcc += dt
				while duelAcc >= 0.1 - 1e-9 do
					duelAcc -= 0.1
					rig.combat:step(0.1, rig.now())
				end
			end
			if each then
				each()
			end
		end
	end
	rig.runUntil = function(limit: number, done: () -> boolean, each: (() -> ())?): boolean
		local stop = rig.time + limit
		while rig.time < stop do
			if done() then
				return true
			end
			rig.step(rig.dt, each)
		end
		return done()
	end
	-- a player takes the body: its brain stops and the test moves it (Boot/Game's possession)
	rig.hold = function(id: number)
		if not rig.players[id] then
			TownAI.suspend(world, id)
			rig.players[id] = true
		end
	end
	rig.let = function(id: number)
		if rig.players[id] then
			local a = world.actorsById[id]
			rig.players[id] = nil
			TownAI.resume(world, id, a.x, a.y, a.z)
		end
	end
	rig.put = function(id: number, x: number, z: number, yaw: number?)
		local a = world.actorsById[id]
		a.x, a.z = x, z
		a.y = world.ctx.groundAt(x, z) + a.hip
		if yaw then
			a.yaw = yaw
		end
	end
	rig.holdRodent = function()
		rig.hold(rig.rodent)
	end
	-- the nearest person of a post (default townsperson) to (x, z), skipping ids in `skip`
	rig.near = function(x: number, z: number, post: string?, skip: { [number]: boolean }?): any
		local best, bestD = nil, math.huge
		for _, a in world.actors do
			if
				a.species == "human"
				and a.post == (post or "townsperson")
				and not (skip and skip[a.id])
				and not a.infected
			then
				local d = (a.x - x) ^ 2 + (a.z - z) ^ 2
				if d < bestD then
					best, bestD = a, d
				end
			end
		end
		return best
	end
	-- the nearest calm townsperson (no vigilante, nobody wary): the person an ordinary bite is on
	rig.calmNear = function(x: number, z: number, skip: { [number]: boolean }?): any
		local s = table.clone(skip or {})
		while true do
			local a = rig.near(x, z, nil, s)
			if a == nil or rig.combat == nil or rig.combat:temperOf(a.id) == "calm" then
				return a
			end
			s[a.id] = true
		end
	end
	rig.responders = function(): { any }
		local out = {}
		for _, v in traffic.vehicles do
			if v.class == "responder" then
				table.insert(out, v)
			end
		end
		return out
	end
	rig.saidBy = function(situation: string): { Said }
		local out = {}
		for _, s in rig.said do
			if s.situation == situation then
				table.insert(out, s)
			end
		end
		return out
	end
	rig.now = function(): number
		return 5000 + rig.time
	end
	-- A player's pounce at a person: the rodent `from` studs off on the line it stands on (default 8), facing them; the
	-- click (the tell), then the motor's lunge at 31 studs/s after the wind-up, onto them; stepped (a tenth at a time) until the
	-- pounce is over. True when a bite landed.
	rig.lunge = function(victimId: number, from: number?): boolean
		local v = world.actorsById[victimId]
		local r = world.actorsById[rig.rodent]
		rig.holdRodent()
		local dx, dz = r.x - v.x, r.z - v.z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < 1e-3 then
			dx, dz, d = 1, 0, 1
		end
		local ux, uz = dx / d, dz / d
		local f = from or 8
		rig.put(rig.rodent, v.x + ux * f, v.z + uz * f, math.atan2(-ux, -uz))
		local bites = rig.combat:stats().bites
		-- (still recovering from the last pounce: the player clicks again a moment later)
		local ok = rig.combat:rodentAct(rig.rodent, "pounce", rig.now())
		local waitUntil = rig.time + 1.5
		while not ok and rig.time < waitUntil do
			rig.step(0.1)
			rig.put(rig.rodent, v.x + ux * f, v.z + uz * f, math.atan2(-ux, -uz))
			ok = rig.combat:rodentAct(rig.rodent, "pounce", rig.now())
		end
		if not ok then
			return false
		end
		local t0 = rig.time
		local P = rig.combat.P
		rig.motor[rig.rodent] = { age = 0 }
		local stop = t0 + P.pounceWindup + P.pounceWindow + 0.4
		-- (in steps of a tenth, the duel's own: a runner moves 2 studs a step, inside the bite's reach)
		local dt0 = rig.dt
		rig.dt = math.min(dt0, 0.1)
		local bitten = false
		while rig.time < stop and not bitten do
			rig.step(rig.dt, function()
				local into = rig.time - t0 - P.pounceWindup
				if into >= 0 and into <= P.pounceWindow then
					rig.motor[rig.rodent] = { age = 0, launchAgo = into }
					local tx, tz = v.x - r.x, v.z - r.z
					local td = math.sqrt(tx * tx + tz * tz)
					if td > 0.5 then
						local step = math.min(td - 0.5, 31 * rig.dt)
						rig.put(rig.rodent, r.x + tx / td * step, r.z + tz / td * step)
					end
				else
					rig.motor[rig.rodent] = { age = 0 }
				end
			end)
			bitten = rig.combat:stats().bites > bites
		end
		rig.dt = dt0
		return bitten
	end
	-- Boot/Game's bite as it is before the duel: the rodent bites the person it touches, then the sequence starts
	rig.biteNow = function(victimId: number): boolean
		if not rig.infection:biteable(victimId) then
			return false
		end
		return rig.infection:bite(victimId, rig.rodent, "rodentPlayer")
	end
	return rig
end

return BiteRig
