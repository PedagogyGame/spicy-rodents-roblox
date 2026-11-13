--!strict
-- ServerScriptService.Server.Minigames.Paintball.BotCheck
-- The paintball bots' own check for a real server (checklist PB-10, PB-15), runnable under Luau
-- Execution and under Lune alike: no Instances, no remotes, no players. It answers what the headless
-- matches of tools/games/paintball/bots cannot: what Bots.step COSTS IN THE ENGINE with the fifteen
-- bots the budget is written for (Contract.COST.botsMs at COST.atBots), and that the bots' modules
-- load and play there. It is a small match loop of its own (the match-and-bots lane's, not the
-- service's): the real Rules driven directly, fifteen bots and one seat nobody plays, balls flown
-- with Ballistics against arena.sweep and Hit.body, bodies judged where they are now.
-- A failure is one of: the mean cost over the budget; nobody tagged; a bot's ball refused by
-- Bots.judge, the service's own judge (off its look or eye, from a spawn room, sprinting, or refused
-- by the match); a bot that never left its spawn room or stood still for STILL_LIMIT; a step a
-- person's body could not have taken (through a box, off the walking surface, into the other team's
-- spawn room, or further than Body.speed allows for its crouch and sprint bit: the rules a person's
-- pose is held to, with none of a person's tolerances).
-- The task script that sends it is tools/games/paintball/bots/engine_check.luau.
-- Interface: run(opts?) -> Result; types Opts, Result

local Import = require("../../Import")
local ArenaModule: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Arena)) =
	Import.shared("Minigames/Paintball/Arena")
local ArenaData: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.ArenaData)) =
	Import.shared("Minigames/Paintball/ArenaData")
local Ballistics: typeof(require(game.ReplicatedStorage.Shared.Paintball.Ballistics)) =
	Import.shared("Paintball/Ballistics")
local Body: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Body)) =
	Import.shared("Minigames/Paintball/Body")
local Clock: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Clock)) =
	Import.shared("Minigames/Paintball/Clock")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local Hit: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Hit)) =
	Import.shared("Minigames/Paintball/Hit")
local Rules: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Rules)) =
	Import.shared("Minigames/Paintball/Rules")
local Wire: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Wire)) =
	Import.shared("Minigames/Paintball/Wire")
local BotNav = require("./BotNav")
local Bots = require("./Bots")

type Pose = typeof(Contract.T.Pose)

export type Opts = {
	seconds: number?, -- of live play (default 120)
	bots: number?, -- default Contract.COST.atBots
	seed: number?,
}

export type Result = {
	ok: boolean,
	failures: { string },
	numbers: {
		bots: number,
		ticks: number,
		botsMs: number, -- Bots.step, mean milliseconds a tick while live
		botsMsWorst: number,
		overBudget: number, -- the share of ticks over Contract.COST.botsMs
		budgetMs: number,
		shots: number,
		tags: number,
		refused: number,
		legs: number, -- steps a person's body could not have taken
		stillWorst: number, -- seconds
		neverLeft: number, -- bots that never left their spawn room
	},
}

type Ball = {
	by: number,
	team: number,
	born: number,
	age: number,
	ox: number,
	oy: number,
	oz: number,
	vx: number,
	vy: number,
	vz: number,
}

local STILL_LIMIT = 25

local BotCheck = {}

function BotCheck.run(opts: Opts?): Result
	local o: Opts = opts or {}
	local seconds = o.seconds or 120
	local count = math.clamp(o.bots or Contract.COST.atBots, 2, Contract.Rules.slots - 1)
	local arena = ArenaData.build()
	local bots = Bots.new(arena, { seed = o.seed or 1 })
	local nav = bots.nav
	local dt = 1 / Clock.TICK_HZ
	local now = 500
	-- seat 1 is held by nobody who plays (it stands in its spawn room); the bots take the rest
	local state = Rules.init(1, o.seed or 1)
	Rules.sync(state, now)
	local who: { [number]: number } = {}
	for seat = 2, count + 1 do
		Rules.join(state, seat)
		who[seat] = Contract.BOTS[(seat - 2) % #Contract.BOTS + 1].skill
	end
	local poses: { [number]: Pose } = {}
	Bots.sync(bots, state, who, poses, now)
	local balls: { Ball } = {}
	local heard: { Bots.Heard } = {}
	local failures: { string } = {}
	local shots, tags, refused = 0, 0, 0
	local spent, worst, over, ticks = 0, 0, 0, 0
	local left: { [number]: boolean } = {}
	local stillAt: { [number]: { t: number, x: number, z: number } } = {}
	local stillWorst = 0
	local legs = 0
	local legsFirst = ""
	local stood: { [number]: { x: number, y: number, z: number, crouch: number } } = {}
	local endAt = now + Contract.Rules.briefingSecs + seconds
	local budget = Contract.COST.botsMs
	while now < endAt do
		now += dt
		Rules.sync(state, now)
		for _, e in Rules.drain(state) do
			if e.kind == "respawn" and e.id ~= nil and e.team ~= nil and e.spawn ~= nil then
				local sp = arena.spawns[e.team][e.spawn]
				local pose = poses[e.id]
				if pose == nil then
					pose = { x = 0, y = 0, z = 0, yaw = 0, pitch = 0, crouch = 0, bits = 0 }
					poses[e.id] = pose
				end
				pose.x, pose.y, pose.z, pose.yaw, pose.pitch, pose.crouch, pose.bits = sp.x, sp.y, sp.z, sp.yaw, 0, 0, 0
				stillAt[e.id] = { t = now, x = sp.x, z = sp.z }
				stood[e.id] = { x = sp.x, y = sp.y, z = sp.z, crouch = 0 }
				if who[e.id] ~= nil then
					Bots.place(bots, e.id, pose, now)
				end
			end
		end
		local told = heard
		heard = {}
		local t0 = os.clock()
		local commands = Bots.step(bots, state, poses, told, now, dt)
		local ms = (os.clock() - t0) * 1000
		if state.phase == "live" then
			ticks += 1
			spent += ms
			worst = math.max(worst, ms)
			if ms > budget then
				over += 1
			end
		end
		-- the legs: each bot's step, held to what a person's pose is held to
		for id in who do
			local pose = poses[id]
			local was = stood[id]
			local slot = state.slots[id]
			if pose == nil or was == nil then
				continue
			end
			local x, y, z = pose.x, pose.y, pose.z
			local flat = math.sqrt((x - was.x) ^ 2 + (z - was.z) ^ 2)
			local chest = y + ArenaModule.CHEST
			local ground = arena.ground(x, y + 0.6, z)
			local most = if slot.out or state.phase ~= "live"
				then 0
				else Body.speed(was.crouch, Wire.has(pose.bits, Wire.BIT.sprint), state.feel) * dt
			local why: string? = nil
			if not ArenaModule.inVolume(x, y, z) or arena.sweep(x, chest, z, x, chest + 0.01, z) ~= nil then
				why = "inside a box or out of the building"
			elseif ArenaModule.inRoom(arena.spawnRooms[3 - slot.team], x, y, z) then
				why = "in the other team's spawn room"
			elseif ground == nil or math.abs(y - ground) > 0.05 then
				why = "off the walking surface"
			elseif
				flat > 0
				and not ArenaModule.clearPath(arena.sweep, was.x, was.z, x, z, math.max(was.y, y) + ArenaModule.CHEST)
			then
				why = "through a box"
			elseif flat > most + 1e-6 then
				why = "too far for its pace"
			end
			if why ~= nil then
				legs += 1
				if legsFirst == "" then
					legsFirst = string.format("seat %d, %s, at (%.1f, %.1f, %.1f)", id, why, x, y, z)
				end
			end
			was.x, was.y, was.z, was.crouch = x, y, z, pose.crouch
		end
		for _, cmd in commands do
			if cmd.kind == "reload" then
				Rules.reload(state, cmd.id, now)
			elseif cmd.kind == "fire" then
				-- the service's judge of a bot's ball (Bots.judge: along its own look, from its eye,
				-- not from a spawn room, not sprinting, and the match agrees)
				local pose = poses[cmd.id]
				local vx, vy, vz = cmd.vx or 0, cmd.vy or 0, cmd.vz or 0
				if Bots.judge(bots, state, cmd.id, pose, cmd, now) then
					shots += 1
					local ox, oy, oz = cmd.ox or 0, cmd.oy or 0, cmd.oz or 0
					table.insert(balls, {
						by = cmd.id,
						team = state.slots[cmd.id].team,
						born = now,
						age = 0,
						ox = ox,
						oy = oy,
						oz = oz,
						vx = vx,
						vy = vy,
						vz = vz,
					})
					table.insert(
						heard,
						{ kind = "born", id = cmd.id, x = ox, y = oy, z = oz, vx = vx, vy = vy, vz = vz }
					)
				else
					refused += 1
				end
			end
		end
		-- the balls
		local drop = state.feel.ballDrop
		for i = #balls, 1, -1 do
			local ball = balls[i]
			local t1 = ball.age + dt
			local ax, ay, az = Ballistics.position(ball.ox, ball.oy, ball.oz, ball.vx, ball.vy, ball.vz, drop, ball.age)
			local bx, by, bz = Ballistics.position(ball.ox, ball.oy, ball.oz, ball.vx, ball.vy, ball.vz, drop, t1)
			local best: number? = arena.sweep(ax, ay, az, bx, by, bz)
			local struck: number? = nil
			local hx, hy, hz = 0, 0, 0
			for id, slot in state.slots do
				local pose = poses[id]
				if
					pose == nil
					or not slot.on
					or slot.team == ball.team
					or not Rules.canBeHit(state, id, now)
					or BotNav.roomOf(nav, pose.x, pose.y, pose.z) == slot.team
				then
					continue
				end
				local s, px, py, pz = Hit.body(arena.sweep, ax, ay, az, bx, by, bz, pose.x, pose.y, pose.z, pose.crouch)
				if s ~= nil and (best == nil or s < best) then
					best, struck, hx, hy, hz = s, id, px, py, pz
				end
			end
			if best == nil then
				ball.age = t1
				if t1 >= Contract.Rules.ballTtl then
					table.remove(balls, i)
				end
				continue
			end
			table.remove(balls, i)
			if struck == nil then
				hx, hy, hz = ax + (bx - ax) * best, ay + (by - ay) * best, az + (bz - az) * best
			end
			table.insert(heard, { kind = "ended", id = ball.by, x = hx, y = hy, z = hz })
			if struck ~= nil and Rules.tag(state, ball.by, struck, now, ball.born) then
				tags += 1
				table.insert(heard, { kind = "tag", id = struck, by = ball.by, x = hx, y = hy, z = hz })
			end
		end
		Rules.step(state, dt)
		-- who has left its room, and who is standing about
		if state.phase == "live" then
			for id in who do
				local pose = poses[id]
				local slot = state.slots[id]
				local mark = stillAt[id]
				if pose == nil or mark == nil then
					continue
				end
				local outside = BotNav.roomOf(nav, pose.x, pose.y, pose.z) == 0
				if outside then
					left[id] = true
				end
				if slot.out or not outside or (pose.x - mark.x) ^ 2 + (pose.z - mark.z) ^ 2 > 9 then
					mark.t, mark.x, mark.z = now, pose.x, pose.z
				else
					stillWorst = math.max(stillWorst, now - mark.t)
				end
			end
		end
	end
	local neverLeft = 0
	for id in who do
		if not left[id] then
			neverLeft += 1
		end
	end
	local mean = if ticks > 0 then spent / ticks else 0
	if mean > budget then
		table.insert(
			failures,
			string.format("Bots.step cost %.3f ms a tick with %d bots: over the %.1f ms budget", mean, count, budget)
		)
	end
	if tags == 0 then
		table.insert(failures, `nobody was tagged in {seconds} s`)
	end
	if refused > 0 then
		table.insert(
			failures,
			`{refused} of the bots' balls were refused by the judge (off their look or eye, from a spawn room, sprinting, or by the match)`
		)
	end
	if neverLeft > 0 then
		table.insert(failures, `{neverLeft} bots never left their spawn room`)
	end
	if legs > 0 then
		table.insert(failures, `{legs} steps a person's body could not have taken; the first: {legsFirst}`)
	end
	if stillWorst > STILL_LIMIT then
		table.insert(failures, string.format("a bot stood still for %.0f s", stillWorst))
	end
	return {
		ok = #failures == 0,
		failures = failures,
		numbers = {
			bots = count,
			ticks = ticks,
			botsMs = mean,
			botsMsWorst = worst,
			overBudget = if ticks > 0 then over / ticks else 0,
			budgetMs = budget,
			shots = shots,
			tags = tags,
			refused = refused,
			legs = legs,
			stillWorst = stillWorst,
			neverLeft = neverLeft,
		},
	}
end

return BotCheck
