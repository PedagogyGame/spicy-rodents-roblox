--!strict
-- ReplicatedStorage.Shared.Minigames.MinigameRules.Pool8Ball
-- Eight-ball rules for the two pool tables in the bowling alley's games room (brief v2 §13a; BUILD_PLAN §3.16
-- "pool and bumper pool (8-ball rules, fouls)"). This build ships the rules, ready for the table (the physics
-- table, the cue's aim and power, and the prompt that opens it come in a later build: the prompt says so). A
-- shot is reported by the table as the server verb "shot" { firstHit, pocketed (comma list), scratch, rail }:
--   the break: any legal break keeps the table open; the 8 on the break is spotted again
--   groups: the first legal pot after the break gives that player solids (1-7) or stripes (9-15)
--   fouls: scratch, hitting nothing, hitting the other group (or the 8 early) first, or no rail and no pot after
--          contact -> the other player has ball in hand
--   the 8: pocketed after clearing your group with no foul wins; pocketed early or with a foul loses
--   a legal pot of your own ball keeps the turn; anything else passes it
-- Pure; Lune-tested (tests/unit/minigames_pool.spec.luau).
-- Interface: the Minigame.Rules shape plus turn(state), view(state), skipTurn(state), groupOf(ball) -> string

local Pool8Ball = {}

Pool8Ball.def = {
	game = "pool",
	title = "Eight-ball",
	class = "shared_table",
	seats = 2,
	authority = "server",
	money = "none",
}
Pool8Ball.verbs = { shot = true }
Pool8Ball.serverVerbs = { shot = true }

export type State = {
	seats: number,
	seat: number,
	group: { [number]: string? }, -- seat -> "solids" | "stripes"
	onTable: { [number]: boolean }, -- 1..15
	broken: boolean,
	ballInHand: boolean,
	done: boolean,
	winner: number?,
	shots: number,
	lastShot: { [string]: any }?,
}

function Pool8Ball.groupOf(ball: number): string
	if ball >= 1 and ball <= 7 then
		return "solids"
	elseif ball >= 9 and ball <= 15 then
		return "stripes"
	elseif ball == 8 then
		return "eight"
	end
	return "cue"
end

function Pool8Ball.init(seats: number, _seed: number): State
	local onTable = {}
	for b = 1, 15 do
		onTable[b] = true
	end
	return {
		seats = seats,
		seat = 1,
		group = {},
		onTable = onTable,
		broken = false,
		ballInHand = true,
		done = false,
		winner = nil,
		shots = 0,
		lastShot = nil,
	}
end

local function other(state: State, seat: number): number
	return if state.seats < 2 then seat else (seat % state.seats) + 1
end

local function cleared(state: State, seat: number): boolean
	local g = state.group[seat]
	if g == nil then
		return false
	end
	for b = 1, 15 do
		if b ~= 8 and state.onTable[b] and Pool8Ball.groupOf(b) == g then
			return false
		end
	end
	return true
end

function Pool8Ball.turn(state: State): number?
	return if state.done then nil else state.seat
end

-- shot(state, firstHit, pocketed, scratch, rail) -> event: "foul" | "continue" | "pass" | "win" | "lose"
function Pool8Ball.shot(state: State, firstHit: number, pocketed: { number }, scratch: boolean, rail: boolean): string
	local seat = state.seat
	local opp = other(state, seat)
	local mine = state.group[seat]
	local breakShot = not state.broken
	state.shots += 1
	state.broken = true
	state.ballInHand = false
	-- on the 8 means the group was cleared before this shot (the last ball and the 8 together lose)
	local onEight = cleared(state, seat)
	local eight = false
	local ownPot = false
	local anyPot = #pocketed > 0
	for _, b in pocketed do
		if b == 8 then
			eight = true
		elseif b >= 1 and b <= 15 then
			state.onTable[b] = false
			if mine and Pool8Ball.groupOf(b) == mine then
				ownPot = true
			end
		end
	end
	-- was the first contact legal?
	local legalFirst: boolean
	if firstHit == 0 then
		legalFirst = false
	elseif breakShot or mine == nil then
		legalFirst = firstHit ~= 8 or breakShot
	elseif onEight then
		legalFirst = firstHit == 8
	else
		legalFirst = Pool8Ball.groupOf(firstHit) == mine
	end
	local foul = scratch or not legalFirst or (not anyPot and not rail and not breakShot)
	local event: string
	if eight then
		if breakShot then
			-- spotted again; the break otherwise stands
			state.onTable[8] = true
			event = if foul then "foul" else (if anyPot and #pocketed > 1 then "continue" else "pass")
		elseif onEight and not foul and mine ~= nil then
			state.done, state.winner = true, seat
			event = "win"
		else
			state.done, state.winner = true, if state.seats > 1 then opp else nil
			event = "lose"
		end
	else
		-- groups go to the first legal pot after the break
		if mine == nil and not breakShot and not foul and anyPot then
			local g = Pool8Ball.groupOf(pocketed[1])
			if g == "solids" or g == "stripes" then
				state.group[seat] = g
				if state.seats > 1 then
					state.group[opp] = if g == "solids" then "stripes" else "solids"
				end
				mine = g
				ownPot = true
			end
		end
		if foul then
			event = "foul"
		elseif ownPot or (breakShot and anyPot) or (mine == nil and anyPot) then
			event = "continue"
		else
			event = "pass"
		end
	end
	if not state.done then
		if event == "foul" then
			state.seat = opp
			state.ballInHand = true
		elseif event == "pass" then
			state.seat = opp
		end
	end
	state.lastShot = { seat = seat, event = event, pocketed = pocketed, scratch = scratch }
	return event
end

function Pool8Ball.input(state: State, seat: number, verb: string, args: { any }?): (boolean, string?)
	if verb ~= "shot" then
		return false, "verb"
	end
	if state.done then
		return false, "game over"
	end
	if seat ~= state.seat then
		return false, "not your turn"
	end
	local a = args or {}
	local firstHit = tonumber(a[1]) or 0
	local pocketed: { number } = {}
	if type(a[2]) == "string" then
		for n in string.gmatch(a[2], "%d+") do
			local b = tonumber(n) :: number
			if b >= 1 and b <= 15 and (state.onTable[b] or b == 8) then
				table.insert(pocketed, b)
			end
		end
	end
	Pool8Ball.shot(state, firstHit, pocketed, a[3] == true, a[4] == true)
	return true
end

function Pool8Ball.skipTurn(state: State)
	if not state.done then
		state.seat = other(state, state.seat)
		state.ballInHand = true
	end
end

function Pool8Ball.result(state: State): { [string]: any }?
	if not state.done then
		return nil
	end
	local scores: { [number]: number } = {}
	for s = 1, state.seats do
		local left = 0
		local g = state.group[s]
		for b = 1, 15 do
			if g and b ~= 8 and state.onTable[b] and Pool8Ball.groupOf(b) == g then
				left += 1
			end
		end
		scores[s] = 7 - left
	end
	return { done = true, scores = scores, winner = state.winner }
end

function Pool8Ball.view(state: State): { [string]: any }
	local onTable = {}
	for b = 1, 15 do
		if state.onTable[b] then
			table.insert(onTable, b)
		end
	end
	return {
		kind = "pool",
		turn = if state.done then nil else state.seat,
		groups = { state.group[1], state.group[2] },
		onTable = onTable,
		ballInHand = state.ballInHand,
		done = state.done,
		winner = state.winner,
		lastShot = state.lastShot,
	}
end

return Pool8Ball
