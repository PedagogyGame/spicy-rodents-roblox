--!strict
-- The air hockey port against the owner's own JavaScript (AER / 01, docs/reference/air_hockey/physics.js):
-- tools/games/air_hockey/golden.js ran his game through rail shots, post hits, goals, serves, two driven hands,
-- a hand against the computer at each difficulty from either end, and whole matches to seven, and wrote every
-- input and the states they led to into tests/golden/air_hockey.json. The same inputs replayed through
-- Shared/Minigames/AirHockey/Sim must give every recorded state to 1e-9 (they are read back bit-exactly with
-- PreciseJson; in practice the port agrees to the last bit, and the spec holds it to that).
local fs = require("@lune/fs")
local Sim = require("@shared/Minigames/AirHockey/Sim")
local PreciseJson = require("@tests/lib/PreciseJson")

local EPS = 1e-9

return function(t)
	local golden: any = nil
	local function load(): any
		if golden == nil then
			golden = PreciseJson.decode(fs.readFile("tests/golden/air_hockey.json"))
		end
		return golden
	end

	local function replay(case: any): (number, number, number)
		local s = Sim.new()
		s.difficulty = case.difficulty or 1
		local setup = case.setup or {}
		if setup.puck then
			s.px, s.py = setup.puck[1], setup.puck[2]
		end
		if setup.velocity then
			s.vx, s.vy = setup.velocity[1], setup.velocity[2]
		end
		if setup.countdown ~= nil then
			s.countdown = setup.countdown
		end
		if setup.score then
			s.score0, s.score1 = setup.score[1], setup.score[2]
		end
		if setup.paddle0 then
			s.p0x, s.p0y, s.t0x, s.t0y = setup.paddle0[1], setup.paddle0[2], setup.paddle0[1], setup.paddle0[2]
		end
		if setup.paddle1 then
			s.p1x, s.p1y, s.t1x, s.t1y = setup.paddle1[1], setup.paddle1[2], setup.paddle1[1], setup.paddle1[2]
		end
		local nextInput, nextState = 1, 1
		local states, exact, worst = 0, 0, 0
		for tick = 0, case.ticks - 1 do
			while case.inputs[nextInput] and case.inputs[nextInput][1] == tick do
				local input = case.inputs[nextInput]
				nextInput += 1
				if input[2] < 0 then
					if s.countdown > 0 then
						Sim.serve(s)
					end
				else
					Sim.setTarget(s, input[2], input[3], input[4])
				end
			end
			Sim.tick(s, case.dt, case.human, case.computer)
			local want = case.states[nextState]
			if want and want[1] == tick + 1 then
				nextState += 1
				states += 1
				local got = {
					s.px,
					s.py,
					s.vx,
					s.vy,
					s.p0x,
					s.p0y,
					s.p1x,
					s.p1y,
					s.score0,
					s.score1,
					s.countdown,
					s.hitSerial,
					s.goalSerial,
					s.winner,
					s.serveSide,
					s.lastGoal,
				}
				local same = true
				for i, v in got do
					local d = math.abs(v - want[i + 1])
					if d > worst then
						worst = d
					end
					if d ~= 0 then
						same = false
					end
					if not (d <= EPS) then
						error(`{case.name}: tick {tick + 1}, value {i}: {v} is not his {want[i + 1]} (off by {d})`)
					end
				end
				if same then
					exact += 1
				end
			end
		end
		t.eq(nextInput, #case.inputs + 1, `{case.name}: every input was used`)
		t.eq(nextState, #case.states + 1, `{case.name}: every state was checked`)
		return states, exact, worst
	end

	t.test("the drag of one step is exp's own value, here and in his JavaScript", function()
		t.eq(Sim.DECAY, load().decay)
		t.eq(math.exp(-Sim.DRAG * Sim.STEP), Sim.DECAY)
	end)

	local function group(prefix: string, what: string, least: number)
		t.test(`golden: {what} match his JavaScript to 1e-9`, function()
			local cases, states, exact, worst = 0, 0, 0, 0
			for _, case in load().cases do
				if string.sub(case.name, 1, #prefix) == prefix then
					local n, e, w = replay(case)
					cases += 1
					states += n
					exact += e
					worst = math.max(worst, w)
				end
			end
			t.truthy(cases >= least, `{cases} cases of {what}`)
			-- the port is the same arithmetic in the same order: every state is his to the last bit
			t.eq(exact, states, `{what}: {exact} of {states} states bit for bit (worst {worst})`)
		end)
	end
	group("rails", "fast rail shots", 12)
	group("post", "goal post hits", 20)
	group("goal", "goals, the slot's side walls and the seventh goal", 11)
	group("mallet", "a still mallet and a strike", 2)
	group("serve", "the countdown and the serve", 2)
	group("two people", "two driven hands, the computer off", 2)
	group("computer", "a hand against the computer at each difficulty, either end", 6)
	group("match", "whole matches to seven", 2)

	t.test("golden: the matches were played to the end, by both routes", function()
		local won = {}
		for _, case in load().cases do
			local last = case.states[#case.states]
			if last[15] >= 0 then
				won[case.name] = `{last[10]}-{last[11]}`
			end
		end
		t.eq(won["match: to seven against the hard computer"], "0-7")
		t.eq(won["match: to seven, the person never moves"], "7-0")
		t.eq(won["two people: seed 2, a long rally"], "7-2")
		t.eq(won["goal: the seventh ends the match"], "7-3")
	end)
end
