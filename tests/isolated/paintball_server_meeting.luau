--!strict
-- tests/isolated/paintball_server_meeting.luau: THE TWO HALVES ON ONE WIRE, for tests/unit/paintball_server.spec.luau
-- (run in its own Lune process: tests/lib/Isolated). The server lane's scripted clients are the server
-- lane's reading of what a client sends; the client lane's cases play a server of their own reading. Here
-- nobody reads for anybody: the client lane's own headless cores (Client/Minigames/Paintball/SeatCore and
-- ShowCore: the seat that gates a click, predicts the magazine and sends Wire.Move and Wire.Fire, and the show
-- it draws its picture of the match from) sit behind one of the kit's connections, at 80, 150 and 300 ms
-- there and back with jitter and one unreliable packet in twenty lost each way, and the real
-- PaintballService judges what they send, through the real Shared/Net and the real framework. The player behind them is the case: it pushes the stick, holds sprint and crouch, jumps and
-- presses fire; the body moves at the pace the seat hands the framework (ctx.pace), as the engine would move it.
-- What is held:
--   * the seat takes its slot, its team and its placement from what the service sends;
--   * walking, sprinting, crouching and a jump: not one of the seat's Moves is refused;
--   * mashing the trigger: EVERY BALL THE CLIENT LET GO IS A BALL ON THE SERVER (no click the seat's own gates
--     passed is refused), and at rest the pips are the server's magazine;
--   * a click while sprinting leaves when the marker is up, and is a shot;
--   * the seat's ball tags a body it was aimed at, and the seat is told; tagged in its turn it stops sending,
--     and comes back placed anew with a full magazine, its Moves accepted again.
-- THIS RUNS BY ITSELF ONCE THE CLIENT LANE'S CORES ARE IN THE TREE (it looks for their files on disk; in the
-- server lane's own tree they are not there, the one case here says so and passes, and nothing is proven; with
-- PAINTBALL_JOINED=1 that line is a failure, and a core whose file is there but does not load is always one). It leans
-- on the client lane's own names (SeatCore.new, Seat.input / step / onState / onMessage / onRefused and the
-- fields you, team, place, out, fired, mag, hitAt; ShowCore.new, Show.onWatch / onSnap / onShots / onSplats /
-- step): if those move, this case is the first to say so, and it is the server lane's to mend.
-- With the real match model when there is one (the joined tree), else the lane's scripted one.
-- Interface: return function(t) (the spec shape)
local Arena = require("@shared/Minigames/Paintball/Arena")
local Body = require("@shared/Minigames/Paintball/Body")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Rules = require("@shared/Minigames/Paintball/Rules")
local Wire = require("@shared/Minigames/Paintball/Wire")
local BufferCodec = require("@shared/Util/BufferCodec")
local Rig = require("@tests/lib/MinigameRig")
local PaintballRig = require("@tests/lib/PaintballRig")
local Kit = require("@tests/isolated/paintball_server_kit")

local R = Contract.Rules
local FRAME = 1 / 60

-- the client lane's cores, if they are in this tree. Decided by the files on disk (Kit.laneBuilt): a core that
-- is there must load and have its `new`, or the case fails with why.
local SEAT_FILE = "src/client/Minigames/Paintball/SeatCore.luau"
local SHOW_FILE = "src/client/Minigames/Paintball/ShowCore.luau"
local function cores(): (any, any)
	local function ask(file: string, path: string): any
		if not Kit.laneBuilt(file) then
			return nil
		end
		local module = (require :: any)(path)
		assert(type(module) == "table" and type(module.new) == "function", `{path} has no new()`)
		return module
	end
	return ask(SEAT_FILE, "@client/Minigames/Paintball/SeatCore"),
		ask(SHOW_FILE, "@client/Minigames/Paintball/ShowCore")
end

-- Is the match model the real one? By the file (Kit.laneBuilt); a real one that errors fails the case.
local function realModel(): boolean
	if not Kit.laneBuilt("src/shared/Minigames/Paintball/Rules.luau") then
		return false
	end
	local state = Rules.init(2, 1)
	Rules.sync(state, 1000)
	Rules.step(state, 0)
	Rules.sync(state, 1000 + R.briefingSecs + 1)
	Rules.step(state, 0.1)
	assert(state.phase == "live", `the real match model did not go live after its briefing (phase {state.phase})`)
	return true
end

-- The client lane's seat and show behind one of the kit's connections, and the player's body in front of
-- them. From here on EVERY frame of the kit (kit.frame, and so kit.run, kit.walk, kit.untilTrue) is a frame
-- of this client too: the body moves, the game steps, the show and the seat step. m.walk(x, z) pushes the
-- stick until the body is there.
local function meet(kit: Kit.Kit, c: Kit.Client, SeatCore: any, ShowCore: any): { [string]: any }
	c.auto = false -- (the seat sends its own Moves)
	local me = { x = 0, y = 0, z = 0, yaw = 0, pitch = 0, air = false, push = 0, pace = 1, floor = 0 }
	local m: { [string]: any } = { me = me, sounds = {}, verbs = {} }
	local show = ShowCore.new({ arena = kit.arena, now = kit.now })
	local ctx: any = {
		station = Contract.STATION,
		game = Contract.GAME,
		label = "Paintball match",
		place = nil,
		ui = nil,
		send = function(verb: string, args: { any }?)
			table.insert(m.verbs, verb)
			kit.later(c.up, function()
				Rig.input(kit.w, c.stub, Contract.STATION, verb, args or {})
			end)
		end,
		camera = function() end,
		releaseCamera = function() end,
		controls = function(_on: boolean) end,
		-- (the framework sets the body's walking speed to the town's walk times this)
		pace = function(scale: number?, _sprint: boolean?)
			me.pace = scale or 1
		end,
		stamp = kit.now,
		setButtons = function(_list: any) end,
		toast = function(_text: string) end,
		body = function(): any
			return nil
		end,
		sound = function(cue: string, _volume: number?): boolean
			table.insert(m.sounds, cue)
			return false
		end,
	}
	local seat = SeatCore.new(ctx, {
		now = kit.now,
		arena = kit.arena,
		link = {
			send = function(remote: string, payload: buffer)
				local rec = BufferCodec.decode(if remote == "Paintball.Move" then Wire.Move else Wire.Fire, payload)
				-- (a Move is unreliable: it may be lost, and late by its own jitter; a click is reliable and in order)
				if remote == "Paintball.Move" and c.lose > 0 and c.rand() < c.lose then
					return
				end
				local extra = if remote == "Paintball.Move" and c.jitter > 0
					then math.floor(c.rand() * (c.jitter + 1))
					else 0
				kit.later(c.up + extra, function()
					PaintballRig.send(kit.wires, c.stub, remote, rec)
				end)
			end,
			listen = function(): () -> ()
				return function() end
			end,
		},
		show = function(): any
			return show
		end,
		port = {
			pose = function(): (number?, number, number, number, number, number, boolean)
				local cp = math.cos(me.pitch)
				return me.x, me.y, me.z, -math.sin(me.yaw) * cp, math.sin(me.pitch), -math.cos(me.yaw) * cp, me.air
			end,
			push = function(): number
				return me.push
			end,
			place = function(x: number, y: number, z: number, _yaw: number)
				me.x, me.y, me.z, me.floor, me.air = x, y, z, y, false
				m.jumpAt = nil
			end,
			look = function(_x: number, _y: number, _z: number, yaw: number)
				me.yaw, me.pitch = yaw, 0
			end,
			user = function(): number
				return c.stub.UserId
			end,
		},
	})
	m.seat, m.show = seat, show
	-- everything the connection hears, as the framework would hand it on
	c.onHear = function(msg: any)
		local kind = msg.kind
		if kind == "state" then
			seat:onState(msg)
		elseif kind == "refused" then
			seat:onRefused(msg)
		elseif kind == "paintball_watch" then
			show:onWatch(msg, nil)
			seat:onMessage(msg, show)
		elseif kind == "event" or (type(kind) == "string" and string.sub(kind, 1, 10) == "paintball_") then
			if kind ~= "paintball_unwatch" then
				seat:onMessage(msg, show)
			end
		end
	end
	c.onStream = function(remote: string, payload: buffer)
		if remote == "Paintball.Snap" then
			show:onSnap(payload)
		elseif remote == "Paintball.Shot" then
			show:onShots(payload)
		else
			show:onSplats(payload)
		end
	end

	local V, G = math.sqrt(2 * 196.2 * Body.JUMP_HEIGHT), 196.2
	local inner = kit.frame
	function kit.frame()
		-- the body: towards where the stick is pushed, at the pace the seat has set
		local target = m.target
		if target ~= nil then
			local dx, dz = target.x - me.x, target.z - me.z
			local d = math.sqrt(dx * dx + dz * dz)
			if d < 1e-6 then
				m.target = nil
				me.push = 0
			else
				me.push = 1
				local step = math.min(d, Body.WALK * me.pace * FRAME)
				me.x += dx / d * step
				me.z += dz / d * step
			end
		else
			me.push = 0
		end
		-- a hop
		local jumpAt = m.jumpAt
		if jumpAt ~= nil then
			local tau = kit.now() - jumpAt
			local y = me.floor + V * tau - G / 2 * tau * tau
			if y <= me.floor then
				me.y, me.air, m.jumpAt = me.floor, false, nil
			else
				me.y, me.air = y, true
			end
		end
		-- the server's copy of the body is where the client has it (unless the server has just moved it and
		-- the client has not heard)
		local body = c.stub.body
		if body.teleports == c.teleportsHeard then
			body.x, body.y, body.z = Arena.toWorld(kit.place, me.x, me.y, me.z)
		end
		inner()
		show:step(FRAME)
		seat:step(FRAME)
	end
	function m.walk(x: number, z: number)
		m.target = { x = x, z = z }
		for _ = 1, 3600 do
			if m.target == nil then
				break
			end
			kit.frame()
		end
	end
	function m.jump()
		m.jumpAt = kit.now()
	end
	function m.press()
		seat:input("fire", true)
		seat:input("fire", false)
	end
	return m
end

return function(t)
	local ok, SeatCore, ShowCore = pcall(cores)
	if not ok then
		t.test("the client lane's cores load", function()
			error(SeatCore, 0)
		end)
		return
	end
	if SeatCore == nil or ShowCore == nil then
		Kit.waiting(
			t,
			"the client lane's cores are not in this tree (Client/Minigames/Paintball/SeatCore, ShowCore): the two halves do not meet here"
		)
		return
	end

	for _, rttMs in { 80, 150, 300 } do
		t.test(
			`the meeting at {rttMs} ms, with jitter and one packet in twenty lost: the client lane's own seat and show against the real service: placed, walking, sprinting, crouching and jumping without a refusal; every ball the client lets go is a ball on the server and the pips are its magazine; a click while sprinting; a tag given, a tag taken, and back with a full magazine`,
			function()
				Kit.play(function(kit: Kit.Kit)
					local stats = kit.service:stats()
					local half = rttMs / 1000 / 2 * 60
					local ada =
						kit.client("Ada", { up = math.floor(half), down = math.ceil(half), jitter = 2, lose = 0.05 })
					local bea = kit.client("Bea", { delay = 2 })
					local m = meet(kit, ada, SeatCore, ShowCore)
					local seat, me = m.seat, m.me
					t.truthy((kit.join(ada)))
					t.truthy((kit.join(bea)))
					kit.run(1.5)
					-- the seat knows who it is and where it was put
					t.eq(seat.you, ada.seat, "the seat's slot")
					t.eq(seat.team, kit.state().slots[ada.seat].team, "the seat's team")
					t.eq(seat.team, 1, "Ada plays for team 1 in this case")
					t.truthy(seat.place ~= 0 and seat.place == ada.place, `the seat took placement {ada.place}`)
					local sp = ada.last("paintball_respawn", function(msg: any): boolean
						return msg.id == ada.seat
					end)
					t.near(me.x, sp.x, 1e-6, "the body was pivoted to the spawn point")
					t.near(me.z, sp.z, 1e-6)
					kit.live()
					kit.run(1.5)
					t.eq(seat.phase, "live", "the seat was told the match is live")

					-- out of the room at a walk, a sprint, a crouch, a hop
					m.walk(-34, 0)
					seat:input("sprint", true)
					m.target = { x = -14, z = 0 }
					kit.run(0.5)
					t.truthy(seat.k > 0.9, "the sprint ramp came up")
					t.near(
						me.pace,
						Body.speed(0, true, kit.state().feel) / Body.WALK,
						1e-6,
						"and the body runs at sprint pace"
					)
					m.walk(-14, 0)
					seat:input("sprint", false)
					kit.run(0.3)
					seat:input("crouch", true)
					m.walk(-10, 0)
					t.truthy(seat.c > 0.9, "crouched")
					seat:input("crouch", false)
					kit.run(0.4)
					m.target = { x = -4, z = 0 }
					m.jump()
					kit.run(0.6)
					m.walk(-4, 0)
					kit.run(0.3)
					t.eq(stats.movesRefused, 0, "not one Move of the client's own seat was refused")
					t.eq(stats.corrections, 0)
					t.truthy(stats.movesAccepted > 60, `{stats.movesAccepted} Moves accepted`)
					local pose = kit.service.poses[ada.seat]
					t.truthy(
						math.abs(pose.x - me.x) < 1.5 and math.abs(pose.z - me.z) < 1.5,
						"the server has her where she is"
					)

					-- Bea walks out to stand in the open, twenty-odd studs in front of Ada
					kit.walk(bea, 30, 0)
					kit.walk(bea, 20, 0)
					me.yaw, me.pitch = -math.pi / 2, 0 -- (looking along +x)
					kit.run(0.6)
					t.truthy(m.show.puppets ~= nil, "the show draws the match")

					-- mashing the trigger, six presses a second for two seconds
					local ballsWere = stats.balls
					for i = 1, 120 do
						if i % 10 == 1 then
							m.press()
						end
						kit.frame()
					end
					kit.run(1.0)
					local let = seat.fired
					t.truthy(let >= R.magazine, `the seat let go {let} balls`)
					t.eq(stats.balls - ballsWere, let, "every ball the client let go is a ball on the server")
					t.eq(stats.shotsRefused, 0, "no click the seat's own gates passed was refused")
					-- the first of them was aimed at Bea, standing still: she is tagged, and the seat was told
					local tag = ada.last("paintball_tag", function(msg: any): boolean
						return msg.by == ada.seat and msg.id == bea.seat
					end)
					t.truthy(tag ~= nil, "her ball tagged the body it was aimed at")
					t.truthy(seat.hitAt > 0, "and the seat was told so")
					-- at rest (the reload over) the pips are the server's magazine
					kit.run(kit.state().feel.reloadSecs + 0.5)
					local extras = kit.service:state(ada.stub, ada.seat)
					t.eq(seat.mag.rounds, extras.rounds, "the pips are the server's magazine")
					t.eq(seat.mag.rounds, R.magazine)

					-- a click while sprinting: the press ends the sprint, the ball leaves when the marker is up
					seat:input("sprint", true)
					m.target = { x = 14, z = 0 }
					kit.run(0.5)
					t.truthy(seat.k > 0.9)
					local before = seat.fired
					m.press()
					t.eq(seat.fired, before, "nothing leaves a lowered marker")
					kit.run(0.5)
					seat:input("sprint", false)
					t.eq(seat.fired, before + 1, "it left when the marker came up")
					kit.run(0.5)
					t.eq(stats.balls - ballsWere, seat.fired, "and it is a ball on the server")
					t.eq(stats.shotsRefused, 0)
					m.walk(14, 0)

					-- R with a ball gone: the verb goes up, the server reloads, and the pips are its magazine again
					t.eq(seat.mag.rounds, R.magazine - 1)
					seat:input("reload", true)
					seat:input("reload", false)
					kit.run(0.6)
					t.truthy(table.find(m.verbs, "reload") ~= nil, "the seat sent the reload")
					t.truthy(
						kit.service:state(ada.stub, ada.seat).reloadAt > kit.now(),
						"the server's magazine is reloading"
					)
					kit.run(kit.state().feel.reloadSecs + 0.3)
					t.eq(seat.mag.rounds, R.magazine, "reloaded on the client")
					t.eq(kit.service:state(ada.stub, ada.seat).rounds, R.magazine, "and on the server")
					t.eq(ada.count("refused"), 0, "nothing the seat asked for was refused")

					-- Bea comes back, walks out and tags Ada where she stands
					kit.untilTrue(8, function(): boolean
						return not bea.out
					end)
					t.falsy(bea.out, "Bea is back")
					local placeWas = seat.place
					kit.walk(bea, 34, 0)
					kit.run(2.5) -- (her protection runs out)
					local accepted = stats.movesAccepted
					local dx, dy, dz = bea.aim(me.x, me.y + Arena.CHEST, me.z)
					local shot = bea.fire(dx, dy, dz)
					kit.run(1.0)
					t.truthy(bea.acks[shot] ~= nil and bea.acks[shot].ok, "Bea's click was a shot")
					t.truthy(seat.out, "the seat knows it is tagged out")
					-- tagged out, the seat sends nothing
					accepted = stats.movesAccepted
					local droppedWas = stats.movesDropped
					kit.run(1.0)
					t.truthy(stats.movesDropped - droppedWas <= 2, "tagged out, the seat stops sending")
					-- and comes back: placed anew, a full magazine, its Moves accepted again
					for _ = 1, 8 * 60 do
						if not seat.out then
							break
						end
						kit.frame()
					end
					t.falsy(seat.out, "back in play")
					t.truthy(seat.place ~= placeWas and seat.place == ada.place, "placed anew")
					t.eq(seat.mag.rounds, R.magazine, "with a full magazine")
					local room = kit.arena.spawnRooms[1]
					t.truthy(Arena.inRoom(room, me.x, me.y + 0.1, me.z), "in her own spawn room")
					accepted = stats.movesAccepted
					m.walk(-36, 0)
					t.truthy(stats.movesAccepted - accepted >= 5, "her Moves are accepted again")
					t.eq(stats.movesRefused, 0, "and in all of it not one was refused")
					t.eq(stats.corrections, 0)
					t.eq(stats.shotsRefused, 0)
				end, { realModel = realModel(), arena = Kit.hall() })
			end
		)
	end
end
