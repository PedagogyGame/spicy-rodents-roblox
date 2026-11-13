--!strict
-- ServerStorage.EngineTests.PaintballFlow (CI place only; injected with --inject ci.project.json or a saved version)
-- A whole paintball match on a server with no clients, bots only (brief v2 §13; checklist PB-6, PB-12, PB-14,
-- PB-15), as plain results. One PlayerLike stub buys a pass and joins at the arena door (a match needs one
-- person or the framework closes the table) and stands in its spawn room for the whole of it, looking a
-- little to one side and the other (a person who neither moves, turns nor fires for a minute of live play is
-- taken off), its pose handed to the service twenty times a second as its client would send it; the bots
-- play. What is checked:
--   the pass     no seat without one; the desk sells it once and seats nobody
--   the roster   one person and seven bots, four a side; everybody placed in a spawn room, the person's own
--                body moved there and put in the bodies' collision group
--   the match    the briefing, then live: snapshots twenty a second, the bots' balls (the watch goes on,
--                up to `ballWait` more seconds, until the first: the real brains take their time to find
--                each other in five storeys, and those of the person's side keep her company, so with her in
--                her room half of them stay near it), tags that add up to
--                the scores; a click from inside the spawn room refused with its reason; one scripted tag
--                (MinigameService:debug(station, "tag", by, id)) heard with the new score, and that slot
--                back in play after its respawn time
--   the end      the clock run out (debug "end"): the end banner, the card in the state, the door shut to a
--                newcomer with "The next match starts in N s."
--   rolling on   the next match begins by itself with the person still seated, four a side again
--   leaving      the person leaves: the table closes, the body stands in the lobby in its own collision
--                group, the audience is told, and the arena costs nothing more
-- and what the service's step cost while the match was live (Stats: the whole step and its three shares; in the
-- engine, opts.holdCost, its average and 95th centile held to Contract.COST.totalMs and its worst to a quarter of
-- a frame), and the refusals of the run by the rule that refused them (Stats.movesRefusedBy, shotsRefusedBy).
-- TIME IS REAL HERE: the match is slaved to the clock clients share (workspace:GetServerTimeNow), so the
-- briefing takes its ten seconds; the whole flow is one to three minutes. play() takes any MinigameService and a
-- `step(seconds)` that moves the world on by that long, so the Lune suite runs this same flow on the fake
-- engine first (tests/isolated/paintball_server_fire: there with the server lane's scripted match model and
-- scripted bots, since the real ones are other lanes'; tests/isolated/paintball_server_joined: with the real
-- ones, once the lanes are joined); the check is itself checked before a cloud run is spent on it.
-- Interface: run() -> Result (engine only: boots Server/Boot/Game); play(svc, deps, opts) -> Result { ok,
--   failures, numbers }; walk(svc, deps, opts) -> Result and runWalk() -> Result (THE WALK, below); AIR

local PaintballFlow = {}

PaintballFlow.AIR = 4 -- Wire.BIT.air (pinned equal in tests/isolated/paintball_server_fire)

export type Deps = { Arena: any, Contract: any, Clock: any }
export type Opts = {
	players: { any }, -- two PlayerLike stubs { UserId, Name, events }: one to play, one to be refused
	step: (seconds: number) -> (), -- move the world on (the shared clock with it)
	positionOf: ((player: any) -> (number?, number?, number?))?, -- a player's body's root, world studs
	groupOf: ((player: any) -> string?)?, -- the collision group its body is in
	liveSeconds: number?, -- how long the bots are watched playing (default 12)
	ballWait: number?, -- how much longer the watch goes on for the bots' first ball (default 120)
	-- hold the step's cost to the contract (the engine run: yes; under Lune the numbers are reported only, a
	-- shared machine's scheduler being in them: tests/unit/paintball_server_cost.spec says why)
	holdCost: boolean?,
}

function PaintballFlow.play(svc: any, deps: Deps, opts: Opts): { [string]: any }
	local failures: { string } = {}
	local numbers: { [string]: any } = {}
	local Arena, Contract, Clock = deps.Arena, deps.Contract, deps.Clock
	local R = Contract.Rules
	local function check(cond: any, msg: string): boolean
		if not cond then
			table.insert(failures, msg)
			return false
		end
		return true
	end
	local p1, p2 = opts.players[1], opts.players[2]
	local door, desk = Contract.STATION, Contract.DESK
	local st = svc.stations[door]
	if st == nil or st.tbl == nil or st.hw == nil then
		return {
			ok = false,
			failures = { "there is no paintball arena here (the station, or the baked arena model, is missing)" },
			numbers = numbers,
		}
	end
	local session = st.session
	local service = st.tbl.service
	local stats = service:stats()
	local place = service.place
	local function last(p: any, kind: string, pred: ((m: any) -> boolean)?): any
		for i = #p.events, 1, -1 do
			local m = p.events[i]
			if m.kind == kind and (pred == nil or pred(m)) then
				return m
			end
		end
		return nil
	end
	local function count(p: any, kind: string): number
		local n = 0
		for _, m in p.events do
			if m.kind == kind then
				n += 1
			end
		end
		return n
	end
	local function stateOf(): any
		return session.game and session.game.state
	end
	local function sides(): (number, number, number, number)
		local one, two, people, bots = 0, 0, 0, 0
		local state = stateOf()
		for seat, key in session.seats do
			if not session.gone[seat] then
				if state.slots[seat].team == 1 then
					one += 1
				else
					two += 1
				end
				if type(key) == "table" and key.ai then
					bots += 1
				else
					people += 1
				end
			end
		end
		return one, two, people, bots
	end

	-- the person's client, as far as the server can tell: its pose twenty times a second from where the
	-- server last placed it
	local seq = 0
	local samples: { [string]: { number } } = { stepMs = {}, ballsMs = {}, botsMs = {}, restMs = {} }
	local sampling = false
	local function tend(seconds: number, untilTrue: (() -> boolean)?): boolean
		local slice = 1 / Clock.SEND_HZ
		for _ = 1, math.max(1, math.ceil(seconds / slice - 1e-6)) do
			if untilTrue and untilTrue() then
				return true
			end
			local seat = session.phase ~= "idle" and service.ctx.seatOf(p1)
			local placed = seat
				and last(p1, "paintball_respawn", function(m: any): boolean
					return m.id == seat
				end)
			local fixed = last(p1, "paintball_correct")
			if fixed and placed and fixed.place > placed.place then
				placed = fixed
			end
			if placed then
				seq += 1
				service:onMove(p1, {
					t = service.ctx.stamp(),
					seq = seq % 65536,
					x = placed.x,
					y = placed.y,
					z = placed.z,
					-- (she looks about: nobody who is there stands like a statue for a minute)
					yaw = placed.yaw + 0.3 * math.sin(service.ctx.stamp() * 0.7),
					pitch = 0,
					bits = 0,
					place = placed.place,
				})
			end
			opts.step(slice)
			if sampling then
				for name, list in samples do
					table.insert(list, stats[name])
				end
			end
		end
		return untilTrue ~= nil and untilTrue()
	end

	-- 1. the pass
	local ok, why = svc:join(p1, door)
	check(not ok and why == Contract.textFor("pass"), `without a pass the door said: {tostring(why)}`)
	check(session.phase == "idle", "nobody is seated without a pass")
	ok, why = svc:join(p1, desk)
	check(not ok and why == Contract.textFor("bought"), `the desk said: {tostring(why)}`)
	check(session.phase == "idle", "the desk seats nobody")
	ok, why = svc:join(p1, desk)
	check(not ok and why == Contract.textFor("has_pass"), `the desk, asked twice, said: {tostring(why)}`)

	-- 2. the roster
	ok, why = svc:join(p1, door)
	check(ok, `the door refused a pass holder: {tostring(why)}`)
	if not ok then
		return { ok = false, failures = failures, numbers = numbers }
	end
	tend(0.3)
	check(session.phase == "playing", `the session is {session.phase}`)
	local one, two, people, bots = sides()
	check(people == 1 and bots == 2 * R.teamMin - 1, `{people} person and {bots} bots at the start`)
	check(one == R.teamMin and two == R.teamMin, `sides of {one} and {two}`)
	local seat = service.ctx.seatOf(p1)
	check(last(p1, "joined") ~= nil, "the person was told it is seated")
	local watch = last(p1, "paintball_watch")
	check(watch ~= nil and #watch.slots == 2 * R.teamMin and watch.match == 1, "the audience was told the roster")
	check(count(p1, "paintball_respawn") >= 2 * R.teamMin, "every slot was placed")
	local mine = last(p1, "paintball_respawn", function(m: any): boolean
		return m.id == seat
	end)
	if check(mine ~= nil and mine.place >= 1, "the person's placement is numbered") then
		local team = stateOf().slots[seat].team
		check(
			Arena.inRoom(service.arena.spawnRooms[team], mine.x, mine.y + 0.1, mine.z),
			"placed in its own spawn room"
		)
		if opts.positionOf then
			local wx, wy, wz = opts.positionOf(p1)
			if check(wx ~= nil, "the person has a body") then
				local x, y, z = Arena.toLocal(place, wx, wy, wz)
				check(
					math.abs(x - mine.x) < 1 and math.abs(z - mine.z) < 1 and y - mine.y > 0 and y - mine.y < 6,
					`the body stands at {x}, {y}, {z}; it was placed at {mine.x}, {mine.y}, {mine.z}`
				)
			end
		end
		if opts.groupOf then
			check(opts.groupOf(p1) == Contract.COLLISION_GROUP, "the body is in the match's collision group")
		end
	end
	local state1 = last(p1, "state")
	check(
		state1 ~= nil and state1.match == 1 and type(state1.feel) == "table" and state1.rounds == R.magazine,
		"the state carries the match, the feel and a full magazine"
	)
	check(state1 ~= nil and state1.view.game.phase == "briefing", "the match opens with the briefing")

	-- 3. the briefing ends
	local live = tend(R.briefingSecs + 3, function(): boolean
		return stateOf() ~= nil and stateOf().phase == "live"
	end)
	check(live, "the match never went live")
	tend(1.2)
	local stateLive = last(p1, "state")
	check(stateLive ~= nil and stateLive.view.game.phase == "live", "the seated were told it is live")

	-- 4. the bots play
	local snaps, ballsWere = stats.snapshots, stats.balls
	local watchFrom = service.ctx.stamp()
	sampling = true
	tend(opts.liveSeconds or 12)
	-- (and on, until the first ball: see the header)
	if stats.balls == ballsWere then
		tend(opts.ballWait or 120, function(): boolean
			return stats.balls > ballsWere
		end)
		tend(1)
	end
	sampling = false
	local watchFor = service.ctx.stamp() - watchFrom
	numbers.liveSeconds = watchFor
	numbers.snapshots = stats.snapshots - snaps
	numbers.balls = stats.balls - ballsWere
	numbers.tags = stats.tags
	check(
		numbers.snapshots >= watchFor * Clock.SNAP_HZ * 0.8,
		`{numbers.snapshots} snapshots in {watchFor} s (the rate is {Clock.SNAP_HZ} a second)`
	)
	check(numbers.balls > 0, `no bot fired a ball in {watchFor} s of live play`)
	local state = stateOf()
	check(state.scores[1] + state.scores[2] == stats.tags, "the scores are the tags")
	check(count(p1, "paintball_tag") == stats.tags, "every tag was told to the seated")
	for name, list in samples do
		local sum, worst = 0, 0
		for _, v in list do
			sum += v
			worst = math.max(worst, v)
		end
		local sorted = table.clone(list)
		table.sort(sorted)
		numbers[name] = {
			avg = if #list > 0 then sum / #list else 0,
			p95 = if #sorted > 0 then sorted[math.max(1, math.ceil(#sorted * 0.95))] else 0,
			max = worst,
		}
	end
	-- PB-15 in the engine: the arena's whole step (balls, bots and the rest) beside the town, while the bots
	-- play. The average and the 95th centile are held to the contract's 1.5 ms (a frame of the arena that the
	-- town never notices); the worst single step to a quarter of a 60 Hz frame (one collector or scheduler
	-- hitch may land in it; a step that takes longer than that is a hitch players see)
	local step = numbers.stepMs
	check(not opts.holdCost or #samples.stepMs > 0, "no step was measured while the bots played")
	if opts.holdCost then
		check(
			step.avg <= Contract.COST.totalMs,
			`the arena's step averages {step.avg} ms while the bots play; the contract's budget is {Contract.COST.totalMs}`
		)
		check(
			step.p95 <= Contract.COST.totalMs,
			`the arena's step has a 95th centile of {step.p95} ms; the contract's budget is {Contract.COST.totalMs}`
		)
		check(step.max <= 1000 / 60 / 4, `the arena's worst step took {step.max} ms`)
	end
	check(
		stats.movesRefused == 0 and stats.corrections == 0,
		"the person, standing where she was put, was never refused"
	)
	check(session.phase == "playing" and service.ctx.seatOf(p1) == seat, "the person is still in her seat")
	-- a click from inside the spawn room
	service:onFire(p1, {
		shot = 1,
		vt = service.ctx.stamp() - Clock.INTERP_SECS,
		ft = service.ctx.stamp(),
		ox = mine.x,
		oy = mine.y + 4.5,
		oz = mine.z,
		dx = 1,
		dy = 0,
		dz = 0,
	})
	local ack = last(p1, "paintball_ack")
	check(
		ack ~= nil and ack.shot == 1 and ack.ok == false and ack.why == "safe",
		`a click from the spawn room: {ack and tostring(ack.why)}`
	)

	-- 5. a scripted tag: a bot of each side that can be tagged this instant
	local by: number?, id: number? = nil, nil
	for attempt = 1, 40 do
		state = stateOf()
		local now = service.ctx.stamp()
		by, id = nil, nil
		for slotId, slot in state.slots do
			if slot.on and slotId ~= seat and session.rules.canBeHit(state, slotId, now) then
				if slot.team == 1 and by == nil then
					by = slotId
				elseif slot.team == 2 and id == nil then
					id = slotId
				end
			end
		end
		if by ~= nil and id ~= nil then
			break
		end
		tend(0.25)
		numbers.tagAttempts = attempt
	end
	if check(by ~= nil and id ~= nil, "no pair of bots could be tagged (all out or protected for ten seconds)") then
		local tagsWere, scoreWas = stats.tags, state.scores[1]
		local tagged, said = svc:debug(door, "tag", by, id)
		check(tagged, `the scripted tag was refused: {tostring(said)}`)
		local tag = last(p1, "paintball_tag")
		check(stats.tags == tagsWere + 1, "the tag was counted")
		check(
			tag ~= nil and tag.by == by and tag.id == id and tag.scores[1] == scoreWas + 1,
			"the tag was told with the new score"
		)
		local feel = state.feel
		local back = tend(feel.respawnSecs + feel.protectSecs + 2, function(): boolean
			return session.rules.canBeHit(stateOf(), id, service.ctx.stamp())
		end)
		check(back, "the tagged slot never came back into play")
	end

	-- 6. the clock runs out
	local endsWere = count(p1, "event")
	check((svc:debug(door, "end")), "the scripted end was refused")
	local done = tend(3, function(): boolean
		return session.phase == "done"
	end)
	check(done, `after the clock ran out the session is {session.phase}`)
	tend(1.2)
	check(count(p1, "event") > endsWere, "no end banner")
	local final = last(p1, "state")
	local result = final and final.view.result
	check(type(result) == "table" and type(result.text) == "string", "the end card is in the state")
	numbers.banner = result and result.text
	numbers.scores = { stateOf().scores[1], stateOf().scores[2] }
	ok, why = svc:join(p2, door)
	check(
		not ok and type(why) == "string" and string.find(why, "The next match starts in", 1, true) ~= nil,
		`a newcomer at the end card was told: {tostring(why)}`
	)
	check(session.phase == "done" and service.ctx.seatOf(p1) == seat, "the end card was left alone")

	-- 7. rolling on
	local rolled = tend(R.endCardSecs + 4, function(): boolean
		return session.phase == "playing" and service.match == 2
	end)
	check(rolled, `the next match did not begin by itself (the session is {session.phase})`)
	tend(1.2)
	one, two, people, bots = sides()
	check(people == 1 and one == R.teamMin and two == R.teamMin, `the second match has sides of {one} and {two}`)
	local again = last(p1, "paintball_respawn", function(m: any): boolean
		return m.id == service.ctx.seatOf(p1)
	end)
	check(again ~= nil and mine ~= nil and again.place ~= mine.place, "the person was placed anew for the second match")
	local state2 = last(p1, "state")
	check(state2 ~= nil and state2.match == 2 and state2.view.game.phase == "briefing", "and told of it")

	-- 8. leaving
	local steps
	svc:leave(p1, "left")
	opts.step(0.3)
	steps = stats.steps
	check(session.phase == "idle", `with nobody left the session is {session.phase}`)
	check(last(p1, "left") ~= nil, "the person was told it left")
	check(last(p1, "paintball_unwatch") ~= nil, "the audience was told the arena is empty")
	if opts.positionOf then
		local wx, wy, wz = opts.positionOf(p1)
		if wx ~= nil then
			local x, y, z = Arena.toLocal(place, wx, wy, wz)
			check(not Arena.inVolume(x, y, z), `after leaving the body is still in the arena, at {x}, {y}, {z}`)
		end
	end
	if opts.groupOf then
		check(
			opts.groupOf(p1) ~= Contract.COLLISION_GROUP,
			"after leaving the body is still in the match's collision group"
		)
	end
	opts.step(1)
	check(stats.steps == steps, "an empty arena is still being stepped")
	numbers.stats = {
		steps = stats.steps,
		snapshots = stats.snapshots,
		balls = stats.balls,
		tags = stats.tags,
		movesAccepted = stats.movesAccepted,
		movesRefused = stats.movesRefused,
		movesDropped = stats.movesDropped,
		shotsRefused = stats.shotsRefused,
		corrections = stats.corrections,
		-- by what refused them (Stream.RULES for a Move, Contract.WHY for a click)
		movesRefusedBy = table.clone(stats.movesRefusedBy or {}),
		shotsRefusedBy = table.clone(stats.shotsRefusedBy or {}),
	}
	return { ok = #failures == 0, failures = failures, numbers = numbers }
end

-- THE WALK (PaintballFlow.walk; Server/Minigames/Paintball/Stream, "provisional"): the movement rules held to a
-- body that moves as bodies move. The service judges a person's Moves against the height rule (the
-- footprint at an edge, the hop-and-fall envelope) and the body rule (the replicated body within
-- TRUST.bodySlack), all tuned against scripted bodies. Here one person, with a pass, joins and, once the match
-- is live, walks the building on its own navigation graph: out of the spawn room, up and down the stairs to
-- every storey, to the atrium's side of each and up against its rail, and stands at the rail for
-- `standSeconds`. Its Moves are sampled from ITS OWN BODY as its client would sample them (the feet point,
-- the heading, in the air or not) twenty times a second, and the service reads the same body for the body
-- rule. In the engine (runWalk) the body is the town's own R15 Humanoid, walked with Humanoid:MoveTo on a
-- server with no clients (so it is the server's to simulate): stairs, ledges and the rail are met by the
-- engine's own physics. The bots are told to stand still for the walk (Bots.step answers nothing): this is
-- about movement, and a tag would send the person back to its room halfway.
-- Held: no correction; every refusal is reported by the rule that refused it (Stats.movesRefusedBy); each
-- storey reached; how many nodes of the route the body could not reach in time.
-- opts: player (seated by the walk; it is given a pass at the desk first), step(seconds), drive(player, wx,
--   wy, wz, dt) (move towards a world point: the engine's MoveTo, or a scripted body), feetOf(player) -> world
--   feet point, airOf(player) -> boolean, standSeconds (default 10), nodeSeconds (default: the leg at a walk,
--   twice over, and 3 more)
export type WalkOpts = {
	player: any,
	step: (seconds: number) -> (),
	drive: (player: any, wx: number, wy: number, wz: number, dt: number) -> (),
	feetOf: (player: any) -> (number?, number?, number?),
	airOf: ((player: any) -> boolean)?,
	standSeconds: number?,
	nodeSeconds: number?,
}

function PaintballFlow.walk(svc: any, deps: Deps, opts: WalkOpts): { [string]: any }
	local failures: { string } = {}
	local numbers: { [string]: any } = {}
	local Arena, Contract, Clock = deps.Arena, deps.Contract, deps.Clock
	local function check(cond: any, msg: string): boolean
		if not cond then
			table.insert(failures, msg)
			return false
		end
		return true
	end
	local p = opts.player
	local door = Contract.STATION
	local st = svc.stations[door]
	if st == nil or st.tbl == nil or st.hw == nil then
		return { ok = false, failures = { "there is no paintball arena here" }, numbers = numbers }
	end
	local session = st.session
	local service = st.tbl.service
	local stats = service:stats()
	local arena, place = service.arena, service.place
	local function last(kind: string, pred: ((m: any) -> boolean)?): any
		for i = #p.events, 1, -1 do
			local m = p.events[i]
			if m.kind == kind and (pred == nil or pred(m)) then
				return m
			end
		end
		return nil
	end

	svc:join(p, Contract.DESK)
	local ok, why = svc:join(p, door)
	if not check(ok, `the door refused the walker: {tostring(why)}`) then
		return { ok = false, failures = failures, numbers = numbers }
	end
	-- the walker's client: its own body's pose, twenty times a second, with the placement number it was given
	local seq = 0
	local heading = 0
	local function placement(): number
		local seat = service.ctx.seatOf(p)
		local placed = seat and last("paintball_respawn", function(m: any): boolean
			return m.id == seat
		end)
		local fixed = last("paintball_correct")
		local n = if placed then placed.place else 0
		if fixed and fixed.place > n then
			n = fixed.place
		end
		return n
	end
	local function send()
		local wx, wy, wz = opts.feetOf(p)
		if wx == nil or wy == nil or wz == nil then
			return
		end
		local x, y, z = Arena.toLocal(place, wx, wy, wz)
		seq += 1
		service:onMove(p, {
			t = service.ctx.stamp(),
			seq = seq % 65536,
			x = x,
			y = y,
			z = z,
			yaw = heading,
			pitch = 0,
			bits = if opts.airOf and opts.airOf(p) then PaintballFlow.AIR else 0,
			place = placement(),
		})
	end
	local slice = 1 / Clock.SEND_HZ
	local function tend(seconds: number, toward: { number }?)
		for _ = 1, math.max(1, math.ceil(seconds / slice - 1e-6)) do
			if toward ~= nil then
				opts.drive(p, toward[1], toward[2], toward[3], slice)
			end
			send()
			opts.step(slice)
		end
	end

	-- live at once, with the bots standing still (see the header)
	tend(0.5)
	local state = session.game and session.game.state
	if not check(state ~= nil, "no match began") then
		return { ok = false, failures = failures, numbers = numbers }
	end
	svc:debug(door, "end") -- (the briefing's clock runs out: play begins)
	tend(0.5)
	check(state.phase == "live", `the match is {state.phase}, not live`)
	tend(state.feel.protectSecs + 0.5)

	-- the route: from the node nearest the body, by the building's own links, to a node on each storey and to
	-- the atrium's side of each, and home again
	local nodes, links = arena.nodes, arena.links
	local seat = service.ctx.seatOf(p)
	local team = if seat and state.slots[seat] then state.slots[seat].team else 0
	local around: { [number]: { number } } = {}
	for _, link in links do
		around[link.a] = around[link.a] or {}
		around[link.b] = around[link.b] or {}
		table.insert(around[link.a], link.b)
		table.insert(around[link.b], link.a)
	end
	local function nearest(): number?
		local wx, wy, wz = opts.feetOf(p)
		if wx == nil or wy == nil or wz == nil then
			return nil
		end
		local x, y, z = Arena.toLocal(place, wx, wy, wz)
		-- (the nearest the body can walk straight to: a node behind a wall is not where to start from)
		local best, bestD = nil, math.huge
		local chest = Arena.CHEST
		for _, n in nodes do
			local d = (n.x - x) ^ 2 + ((n.y - y) * 4) ^ 2 + (n.z - z) ^ 2
			if d < bestD and arena.sweep(x, y + chest, z, n.x, n.y + chest, n.z) == nil then
				best, bestD = n.id, d
			end
		end
		return best
	end
	local function pathTo(from: number, goal: (n: any) -> boolean): { number }?
		local cameFrom: { [number]: number } = { [from] = 0 }
		local queue, head = { from }, 1
		while head <= #queue do
			local at = queue[head]
			head += 1
			if at ~= from and goal(nodes[at]) then
				local path = {}
				local n = at
				while n ~= 0 do
					table.insert(path, 1, n)
					n = cameFrom[n]
				end
				return path
			end
			local list: { number } = around[at] or {}
			for _, to in list do
				local node = nodes[to]
				-- (never through the other team's room: the walker would be refused there, rightly)
				if cameFrom[to] == nil and (node.team == 0 or node.team == team) then
					cameFrom[to] = at
					table.insert(queue, to)
				end
			end
		end
		return nil
	end
	local reached: { [number]: boolean } = {}
	local stuck = 0
	local stuckAt: { string } = {}
	local walked = 0
	local function follow(path: { number })
		for i = 1, #path do -- (from the node nearest the body: it is near it, not on it)
			local n = nodes[path[i]]
			local wx, wy, wz = Arena.toWorld(place, n.x, n.y, n.z)
			local fx, _, fz = opts.feetOf(p)
			local leg = if fx then math.sqrt((wx - fx) ^ 2 + (wz - (fz :: number)) ^ 2) else 10
			local limit = opts.nodeSeconds or (2 * leg / 17 + 3)
			local spent = 0
			while spent < limit do
				local x, _, z = opts.feetOf(p)
				if x ~= nil and math.sqrt((wx - x) ^ 2 + (wz - (z :: number)) ^ 2) < 1.5 then
					break
				end
				if x ~= nil then
					heading = math.atan2(-(wx - x), -(wz - (z :: number)))
				end
				tend(slice, { wx, wy, wz })
				spent += slice
			end
			if spent >= limit then
				stuck += 1
				local x, y, z = opts.feetOf(p)
				if x ~= nil and y ~= nil and z ~= nil then
					local lx, ly, lz = Arena.toLocal(place, x, y, z)
					table.insert(
						stuckAt,
						string.format(
							"node %d (%s, storey %d, at %.1f %.1f %.1f) from %.1f %.1f %.1f",
							n.id,
							n.kind,
							n.floor,
							n.x,
							n.y,
							n.z,
							lx,
							ly,
							lz
						)
					)
				end
				return
			end
			walked += 1
			reached[n.floor] = true
		end
	end
	local side = Arena.ATRIUM + Arena.ATRIUM_SIDE
	for floor = 0, Arena.FLOORS - 1 do
		for _, goal in
			{
				function(n: any): boolean
					return n.floor == floor and n.team == 0 and n.kind ~= "stair"
				end,
				function(n: any): boolean
					return n.floor == floor and n.team == 0 and math.abs(n.x) <= side and math.abs(n.z) <= side
				end,
			}
		do
			local from = nearest()
			local path = from and pathTo(from, goal)
			if path ~= nil then
				follow(path)
			end
		end
		-- at the atrium's side: walk on towards the axis until the rail (or the edge) stops the body
		local wx, wy, wz = Arena.toWorld(place, 0, floor * Arena.FLOOR_HEIGHT, 0)
		tend(1.5, { wx, wy, wz })
	end
	-- stand at the rail of the top storey's atrium, looking down
	tend(opts.standSeconds or 10)
	numbers.storeys = 0
	for _ in reached do
		numbers.storeys += 1
	end
	numbers.nodesWalked = walked
	numbers.nodesStuck = stuck
	numbers.stuckAt = stuckAt
	numbers.corrections = stats.corrections
	numbers.movesAccepted = stats.movesAccepted
	numbers.movesRefused = stats.movesRefused
	numbers.movesRefusedBy = table.clone(stats.movesRefusedBy or {})
	check(stats.corrections == 0, `an honest body was corrected {stats.corrections} times`)
	check(numbers.storeys == Arena.FLOORS, `the walk reached {numbers.storeys} of {Arena.FLOORS} storeys`)
	check(stats.movesAccepted > 0, "no Move of the walker was accepted")
	svc:leave(p, "left")
	opts.step(0.3)
	return { ok = #failures == 0, failures = failures, numbers = numbers }
end

-- The engine's side of both checks: the game booted on a server with no clients, two PlayerLike stubs that
-- have each picked a townsperson (an R15 body that the server simulates), and a step that moves the world on
-- in real time. nil and words when the place has no attractions.
local function boot(): (any, string?, number?)
	local ServerScriptService = game:GetService("ServerScriptService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local server = ServerScriptService:WaitForChild("Server")
	local Game = (require :: any)(server:WaitForChild("Boot"):WaitForChild("Game"))
	local Possession = (require :: any)(server:WaitForChild("Actors"):WaitForChild("Possession"))
	local paintball = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Minigames"):WaitForChild("Paintball")
	local deps: Deps = {
		Arena = (require :: any)(paintball:WaitForChild("Arena")),
		Contract = (require :: any)(paintball:WaitForChild("Contract")),
		Clock = (require :: any)(paintball:WaitForChild("Clock")),
	}

	local engine = Possession.engine()
	engine.streamAround = function() end
	engine.setOwner = function(_root: any, _player: any?) end
	engine.setCharacter = function(player: any, model: any?)
		player.Character = model
	end
	local t0 = os.clock()
	local G = Game.start({ players = false, engine = engine, heartbeat = false })
	local bootSeconds = os.clock() - t0
	local A = G.attractions
	if A == nil then
		G.stop()
		return nil, "Game.attractions is missing (is Workspace.Attractions in the place?)", bootSeconds
	end
	local players: { any } = {}
	local setup: { string } = {}
	for i, name in { "Ann", "Bob" } do
		local p = { UserId = 5400 + i, Name = name, Character = nil, attrs = {}, events = {} }
		G.stateOf(p).lastPick = -math.huge
		local ok, why = G.pick(p, "townsperson")
		if not ok then
			table.insert(setup, `{name} could not pick a townsperson: {tostring(why)}`)
		end
		players[i] = p
	end
	local function bodyOf(player: any): any
		local actor = G.runtime.possession:actorOf(player)
		return actor and actor.body
	end
	return {
		G = G,
		A = A,
		deps = deps,
		players = players,
		setup = setup,
		bootSeconds = bootSeconds,
		bodyOf = bodyOf,
		server = server,
		-- the match runs on the clock clients share: the world is moved on in real time, a frame at a time
		step = function(seconds: number)
			local left = seconds
			while left > 0 do
				local dt = RunService.Heartbeat:Wait()
				A.step(math.min(dt, 0.1))
				left -= dt
			end
		end,
	},
		nil,
		bootSeconds
end

function PaintballFlow.run(): { [string]: any }
	local b, words, bootSeconds = boot()
	if b == nil then
		return { ok = false, failures = { words }, numbers = { bootSeconds = bootSeconds } }
	end
	local bodyOf = b.bodyOf
	local result = PaintballFlow.play(b.A.minigames, b.deps, {
		players = b.players,
		holdCost = true,
		step = b.step,
		positionOf = function(player: any): (number?, number?, number?)
			local body = bodyOf(player)
			local root = body and body.PrimaryPart
			if root == nil then
				return nil, nil, nil
			end
			return root.Position.X, root.Position.Y, root.Position.Z
		end,
		groupOf = function(player: any): string?
			local body = bodyOf(player)
			local root = body and body.PrimaryPart
			return root and root.CollisionGroup
		end,
	})
	for _, f in b.setup do
		table.insert(result.failures, 1, f)
	end
	result.ok = #result.failures == 0
	result.numbers.bootSeconds = b.bootSeconds
	b.G.stop()
	return result
end

-- The walk in the engine (see "THE WALK"): Ann's own R15 body, walked by its Humanoid, the bots standing still.
function PaintballFlow.runWalk(): { [string]: any }
	local b, words, bootSeconds = boot()
	if b == nil then
		return { ok = false, failures = { words }, numbers = { bootSeconds = bootSeconds } }
	end
	local folder = b.server:WaitForChild("Minigames"):WaitForChild("Paintball")
	local Bots = (require :: any)(folder:WaitForChild("Bots"))
	local RealEngine = (require :: any)(folder:WaitForChild("RealEngine"))
	local hands = RealEngine.new()
	local stepWas = Bots.step
	Bots.step = function(): { any }
		return {}
	end
	local bodyOf = b.bodyOf
	local function humanoidOf(player: any): any
		local body = bodyOf(player)
		return body and body:FindFirstChildOfClass("Humanoid")
	end
	local ok, result = pcall(PaintballFlow.walk, b.A.minigames, b.deps, {
		player = b.players[1],
		step = b.step,
		drive = function(player: any, wx: number, wy: number, wz: number)
			local humanoid = humanoidOf(player)
			if humanoid then
				humanoid:MoveTo(Vector3.new(wx, wy, wz))
			end
		end,
		feetOf = function(player: any): (number?, number?, number?)
			local body = bodyOf(player)
			if body == nil then
				return nil, nil, nil
			end
			return hands.positionOf(body)
		end,
		airOf = function(player: any): boolean
			local humanoid = humanoidOf(player)
			if humanoid == nil then
				return false
			end
			local state = humanoid:GetState()
			return state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
		end,
	})
	Bots.step = stepWas
	if not ok then
		result = { ok = false, failures = { tostring(result) }, numbers = {} }
	end
	for _, f in b.setup do
		table.insert(result.failures, 1, f)
	end
	result.ok = #result.failures == 0
	result.numbers.bootSeconds = b.bootSeconds
	b.G.stop()
	return result
end

return PaintballFlow
