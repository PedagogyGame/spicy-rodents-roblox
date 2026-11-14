--!strict
-- tests/isolated/paintball_server_model.luau: a short SCRIPTED match model for the paintball server lane's
-- cases. The contract's Rules (src/shared/Minigames/Paintball/Rules) is the match-and-bots lane's and is a
-- stub in this lane's base: it seats slots and deals teams, and never fires, tags, respawns or ends. The
-- service cannot be proven against that, so install() puts these functions in the stub's place (the module's
-- table is open) for the length of a case and hands back the undo. It does what the stub's header says the
-- real model does, as plainly as it can be written, and nothing clever: it is the server lane's reading of
-- that header, so a difference between it and the real model is worth a look when the lanes are joined.
--   phases     briefing for Rules.briefingSecs, live for Rules.matchSecs, then ended; a "phase" event each
--   respawn    every slot at the start, a seat that joins, a slot back from being out, a change of side:
--              a "respawn" event, a full magazine, protection for feel.protectSecs
--   fire       phase, out and protection judged at t, the magazine at m; "reload" events
--   tag        only live, the other team, not out, not protected; a point to the shooter's team, the tag to
--              the shooter unless the seat changed hands since the ball was born
--   result     once ended: the winner's seats, the banner, a card
-- Interface: install() -> undo; liveNow(state, now) (cut the briefing short: the match is live from `now`)
local Magazine = require("@shared/Paintball/Magazine")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Rules = require("@shared/Minigames/Paintball/Rules")
local Wire = require("@shared/Minigames/Paintball/Wire")

local R = Contract.Rules
local Model = {}

local PATCHED = {
	"init",
	"step",
	"join",
	"assign",
	"canFire",
	"fire",
	"reload",
	"canBeHit",
	"tag",
	"bits",
	"result",
	"sync",
}

-- when each State went live (not a field of the contract's State)
local liveAt: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any

local function emit(state: Rules.State, e: Contract.Event)
	table.insert(state.events, e)
end

local function respawn(state: Rules.State, slot: Rules.Slot, now: number)
	slot.out = false
	slot.safeUntil = now + state.feel.protectSecs
	slot.mag = Magazine.new(R.magazine, state.feel.fireInterval, state.feel.reloadSecs)
	slot.spawn = (slot.id - 1) // 2 % R.teamMax + 1
	emit(state, { kind = "respawn", id = slot.id, team = slot.team, spawn = slot.spawn, at = slot.safeUntil })
end

function Model.liveNow(state: Rules.State, now: number)
	state.phase = "live"
	state.endsAt = now + R.matchSecs
	liveAt[state] = now
	emit(state, { kind = "phase", phase = "live", at = state.endsAt })
end

function Model.install(): () -> ()
	local open = Rules :: any
	local was: { [string]: any } = {}
	for _, name in PATCHED do
		was[name] = open[name]
	end

	open.init = function(seats: number, seed: number): Rules.State
		local state = was.init(seats, seed) :: Rules.State
		for _, slot in state.slots do
			respawn(state, slot, state.now)
		end
		return state
	end

	open.sync = function(state: Rules.State, stamp: number)
		local first = not state.synced
		local before = state.now
		was.sync(state, stamp)
		if first and liveAt[state] ~= nil then
			liveAt[state] += stamp - before
		end
	end

	open.step = function(state: Rules.State, dt: number)
		if not state.synced then
			state.now += dt
		end
		local now = state.now
		if state.phase == "briefing" and now >= state.endsAt then
			Model.liveNow(state, state.endsAt)
		end
		if state.phase == "live" and now >= state.endsAt then
			state.phase = "ended"
			state.endsAt += R.endCardSecs
			emit(state, { kind = "phase", phase = "ended", at = state.endsAt })
		end
		if state.phase == "live" then
			for _, slot in state.slots do
				if slot.on and slot.out and now >= slot.outUntil then
					respawn(state, slot, slot.outUntil)
				end
			end
		end
	end

	open.join = function(state: Rules.State, seat: number)
		was.join(state, seat)
		respawn(state, state.slots[seat], state.now)
	end

	open.assign = function(state: Rules.State, id: number, team: number): boolean
		if not was.assign(state, id, team) then
			return false
		end
		local slot = state.slots[id]
		if not slot.out then
			respawn(state, slot, state.now) -- (a slot that is out gets it, for its new side, when it comes back)
		end
		return true
	end

	local function judge(state: Rules.State, id: number, t: number, m: number?): (boolean, string?)
		local slot = state.slots[id]
		local live = liveAt[state]
		if slot == nil or not slot.on or state.phase ~= "live" or live == nil or t < live then
			return false, "phase"
		end
		if slot.out and t >= slot.outAt then
			return false, "out"
		end
		if t < slot.safeUntil then
			return false, "safe"
		end
		local at = m or t
		Magazine.update(slot.mag, at)
		if slot.mag.reloadDoneAt ~= nil or slot.mag.rounds <= 0 then
			return false, "empty"
		end
		if at < slot.mag.nextFireAt then
			return false, "fast"
		end
		return true, nil
	end
	open.canFire = judge

	open.fire = function(state: Rules.State, id: number, t: number, m: number?): (boolean, string?)
		local ok, why = judge(state, id, t, m)
		if not ok then
			return false, why
		end
		local slot = state.slots[id]
		Magazine.fire(slot.mag, m or t)
		slot.shots += 1
		if slot.mag.reloadDoneAt ~= nil then
			emit(state, { kind = "reload", id = id, at = slot.mag.reloadDoneAt })
		end
		return true, nil
	end

	open.reload = function(state: Rules.State, id: number, t: number): boolean
		local slot = state.slots[id]
		if slot == nil or not slot.on or slot.out or state.phase == "ended" then
			return false
		end
		if not Magazine.reload(slot.mag, t) then
			return false
		end
		emit(state, { kind = "reload", id = id, at = slot.mag.reloadDoneAt })
		return true
	end

	open.canBeHit = function(state: Rules.State, id: number, now: number): boolean
		local slot = state.slots[id]
		return slot ~= nil and slot.on and state.phase == "live" and not slot.out and now >= slot.safeUntil
	end

	open.tag = function(state: Rules.State, by: number, id: number, now: number, born: number?): boolean
		local shooter, victim = state.slots[by], state.slots[id]
		if shooter == nil or victim == nil or shooter.team == victim.team or not open.canBeHit(state, id, now) then
			return false
		end
		victim.out = true
		victim.outAt = now
		victim.outUntil = now + state.feel.respawnSecs
		victim.outs += 1
		state.scores[shooter.team] += 1
		if shooter.since <= (born or now) then
			shooter.tags += 1
			shooter.hits += 1
		end
		emit(state, { kind = "tag", by = by, id = id, at = victim.outUntil })
		return true
	end

	open.bits = function(state: Rules.State, id: number, now: number): number
		local slot = state.slots[id]
		local bits = 0
		if slot == nil then
			return 0
		end
		if slot.out then
			bits += Wire.BIT.out
		end
		if now < slot.safeUntil then
			bits += Wire.BIT.safe
		end
		local done = slot.mag.reloadDoneAt
		if done ~= nil and now < done then
			bits += Wire.BIT.reload
		end
		return bits
	end

	open.result = function(state: Rules.State): Contract.Result?
		if state.phase ~= "ended" then
			return nil
		end
		local one, two = state.scores[1], state.scores[2]
		local winner = if one > two then 1 elseif two > one then 2 else 0
		local scores: { [number]: number } = {}
		local winners: { number } = {}
		local rows: { Contract.CardRow } = {}
		for id, slot in state.slots do
			scores[id] = slot.tags
			if slot.on then
				if slot.team == winner then
					table.insert(winners, id)
				end
				table.insert(rows, {
					id = id,
					team = slot.team,
					tags = slot.tags,
					outs = slot.outs,
					shots = slot.shots,
					hits = slot.hits,
					accuracy = if slot.shots > 0 then slot.hits / slot.shots else 0,
				})
			end
		end
		return {
			done = true,
			scores = scores,
			winners = winners,
			text = if winner == 0
				then `A draw, {one} all`
				else `{Contract.TEAMS[winner].name} wins {math.max(one, two)} - {math.min(one, two)}`,
			card = { winner = winner, scores = { one, two }, rows = rows, awards = {} },
		}
	end

	return function()
		for _, name in PATCHED do
			open[name] = was[name]
		end
	end
end

return Model
