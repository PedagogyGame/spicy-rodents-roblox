--!strict
-- tests/lib/BiteRig: the town as Boot/Game runs it round a bite, headless: the real town AI (AI/TownAI, the 102 actors on
-- the real lanes), the real fleet (Traffic/TrafficService, the ambulances among it), the bite-to-hospital sequence
-- (Infection/InfectionService) and the duel (Combat/CombatService), stepped in Boot/Game.step's order (the town, the
-- fleet, the sequence, then the duel every 0.1 s). What a player would see is recorded as it is written: every
-- replicated attribute a body gets (Med, Say and SayAt, the duel's Stance and PounceAt), every toast a player is sent
-- (the sequence's "med" news and the duel's events), and the ambulances' poses.
-- The Spicy Rodent is the town's own rodent actor. `holdRodent()` makes it a player's (its brain stops, the test
-- moves it), as Boot/Game's possession does; `hold(id)` does the same for a townsperson (a player-held victim).
-- Interface: new(opts?) -> Rig; Rig.step(secs, each?); Rig.runUntil(limit, done, each?) -> boolean;
--   Rig.hold(id); Rig.let(id); Rig.put(id, x, z, yaw?); Rig.near(x, z, post?, skip?) -> actor; Rig.responders() -> { vehicle };
--   Rig.saidBy(situation) -> { said }; Rig.dice(list) (the sequence's next dice); fields world, traffic, infection, combat, attrs, medLog, toasts, said, time
-- Studs throughout.
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local InfectionRules = require("@shared/Infection/InfectionRules")
local Lines = require("@shared/Speech/Lines")
local Rng = require("@shared/Util/Rng")
local TownAI = require("@server/AI/TownAI")
local TrafficService = require("@server/Traffic/TrafficService")
local InfectionService = require("@server/Infection/InfectionService")

local BiteRig = {}

BiteRig.DT = 0.2

export type Said = { id: number, line: string, situation: string?, t: number }

export type Options = {
	seed: number?, -- the dice after `first` (default 1)
	first: { number }?, -- the sequence's first dice (InfectionService's rand): the bite's path and timers
	tune: ((params: any) -> ())?, -- InfectionRules params
	dt: number?,
	combat: ((rig: any) -> any)?, -- builds the duel for this rig (nil: no duel; bites go through rig.biteNow)
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
	if o.combat then
		rig.combat = o.combat(rig)
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
			if rig.combat then
				duelAcc += dt
				while duelAcc >= 0.1 - 1e-9 do
					duelAcc -= 0.1
					rig.combat:step(0.1, 5000 + rig.time)
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
