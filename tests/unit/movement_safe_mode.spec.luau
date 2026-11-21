--!strict
-- The movement validator's SAFE MODE (Server/Movement/MovementService with enforcement off: the live game since
-- 2026-11-21, Server/Main): whatever the validator does, honest play goes on. No pin, no snap, no hold, no correction
-- of the driver; every reader gets the newest packet's place (or the root once the packets stop); a validator that
-- throws or takes too long is caught, counted and benched; the numbers the owner's panel shows add up
-- (Shared/Movement/MoveDiag, Client/Controllers/MotorHealth).
local MovementService = require("@server/Movement/MovementService")
local MoveValidator = require("@server/Movement/MoveValidator")
local ActorsRuntime = require("@server/Actors/ActorsRuntime")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local MoveDiag = require("@shared/Movement/MoveDiag")
local Schemas = require("@shared/Net/Schemas")
local Log = require("@shared/Util/Log")
local MotorHealth = require("@client/Controllers/MotorHealth")
local MoveDiagPanel = require("@client/UI/MoveDiagPanel")
local PlayMenu = require("@client/UI/PlayMenu")
local BiteRig = require("@tests/lib/BiteRig")
local TestWorld = require("@tests/cheat/TestWorld")

local C = MovementService.C

local function shot(x: number, z: number, clock: number, edit: ((s: any) -> ())?): any
	local s = SquirrelMotor.new(x, 0, z)
	s.clock = clock
	if edit then
		edit(s)
	end
	return SquirrelMotor.serialize(s)
end

-- a validator that judges as told: `verdict(packet)` its word on each packet (an error thrown there is the validator's)
local function fake(verdict: (packet: any) -> any, faulty: boolean?): any
	local last: any = nil
	local v = { world = {}, accepts = 0 }
	local function maybe()
		if faulty then
			error("engine-only failure in the validator")
		end
	end
	function v.accept(_self: any, _id: any, packet: any, _now: number): any
		v.accepts += 1
		last = packet.snapshot
		return verdict(packet)
	end
	function v.last(): any
		return last
	end
	function v.hasAnchor(): boolean
		return true
	end
	function v.takeOver() end
	function v.reset()
		maybe()
		last = nil
	end
	function v.relocate()
		maybe()
	end
	function v.anchor()
		maybe()
	end
	function v.forget()
		maybe()
	end
	function v.meterOf(): (number, boolean)
		maybe()
		return 0.4, true
	end
	function v.fastest(): number
		return 60
	end
	function v.pingOf(): number?
		return 0.05
	end
	return v
end

local function flagsAll(_packet: any): any
	return {
		ok = false,
		accepted = false, -- (even "not accepted": safe mode takes the packet all the same)
		flagged = true,
		bucket = 9,
		correction = { x = 0, y = 0, z = 0 },
		violations = { { code = "float", severity = 1, detail = "everything" }, { code = "wall", severity = 1 } },
	}
end

-- the game's hands, counted
local function hands(): any
	local h = { pins = 0, holds = 0, snaps = 0, tells = {} :: { any } }
	h.engine = {
		pin = function(_id: any, on: boolean): boolean
			if on then
				h.pins += 1
			end
			return true
		end,
		hold = function()
			h.holds += 1
		end,
		correct = function(_id: any, msg: any)
			table.insert(h.tells, msg)
			if msg.snap then
				h.snaps += 1
			end
		end,
	}
	return h
end

local function service(validator: any, h: any?, clock: (() -> number)?): any
	return MovementService.new({
		validator = validator,
		enforce = false,
		engine = if h then h.engine else nil,
		clock = clock,
		poseOf = function(_actor: any): (number, number, number)
			return 10, 0, 10
		end,
	})
end

local ACTOR = { id = "a", species = "squirrel", mode = "player" }

return function(t)
	t.test(
		"a validator that flags every packet: no pin, no snap, no hold, no correction; every reader has the newest place",
		function()
			Log.capture()
			local h = hands()
			local m = service(fake(flagsAll), h)
			m:onHandoff(ACTOR, {}, "possess")
			t.falsy(m:isPinned("a"), "no pin")
			local epoch = m:epochOf("a")
			local snapped = 0
			for i = 1, 60 do
				local now = 10 + i * 0.05
				m:watch("a", 500, 0, 500, now) -- (a root far from every packet: nothing is judged)
				local r =
					m:packet("a", "squirrel", { seq = i, epoch = epoch, snapshot = shot(10 + i, 20, i * 0.05) }, now)
				t.truthy(r.accepted, "taken")
				t.truthy(r.flagged, "the validator's word is kept for the numbers")
				t.eq(r.correction, nil)
				snapped += if r.snapped then 1 else 0
			end
			Log.setSink()
			t.eq(snapped, 0)
			t.eq(h.pins + h.holds + h.snaps + #h.tells, 0, "the game's hands never used")
			local st = m:stats()
			t.eq(st.snaps + st.holds + st.pins + st.corrections, 0)
			t.eq(st.accepted, 60)
			t.eq(st.flagged, 60)
			t.eq(st.codes.float, 60)
			t.eq(st.codes.wall, 60)
			-- the place: heldPlace (strict too), the runtime's placeOf and heldPoseOf, a Reset's start, the duel's pose
			local x, y, z = m:heldPlace("a")
			t.eq(x, 70)
			t.eq(y, 0)
			t.eq(z, 20)
			t.eq((m:heldPlace("a", true)), 70, "strict mode: the nuts and the hollows")
			local px = ActorsRuntime.placeOf(m, ACTOR, 1.5, nil, 0, function(): (number, number, number)
				return -1, -1, -1
			end)
			t.eq(px, 70, "ActorsRuntime.placeOf")
			local hx, hy = ActorsRuntime.heldPoseOf(m, ACTOR, 1.5)
			t.eq(hx, 70)
			t.eq(hy, 1.5, "the pivot: the feet and the hip")
			local sx = m:safeTarget("a") :: number
			t.truthy(
				sx >= 60 and sx < 70,
				`a Reset goes to a place the newest packets stood ({sx}), never the hand-off`
			)
			local snap, lastAt, _, cleanAt = m:motorOf("a")
			t.eq((snap :: any).x, 70, "the duel's pose")
			t.eq(cleanAt, lastAt, "and it counts as clean: a bite is not kept waiting")
			t.falsy(m:silent("a", 13.05))
		end
	)

	t.test(
		"a validator that throws everywhere: caught, counted, logged at most once per 5 s; play goes on unjudged",
		function()
			local records = Log.capture()
			local t0 = 100
			Log.setClock(function(): number
				return t0
			end)
			local h = hands()
			local m = service(
				fake(function(): any
					error("engine-only failure in the envelope")
				end, true),
				h
			)
			m:onHandoff(ACTOR, {}, "possess") -- (forget throws)
			local epoch = m:epochOf("a")
			for i = 1, 40 do
				t0 = 100 + i * 0.05 -- (two seconds of packets)
				local r = m:packet("a", "squirrel", { seq = i, epoch = epoch, snapshot = shot(i, 5, i * 0.05) }, t0)
				t.truthy(r.accepted and r.ok and r.unjudged, "taken, unjudged")
				t.falsy(r.flagged)
			end
			local st = m:stats()
			t.truthy(st.judgeErrors >= 41, `every failure counted ({st.judgeErrors})`)
			t.eq(st.unjudged, 40)
			t.truthy(
				string.find(st.firstError :: string, "engine-only failure", 1, true),
				"the first error's text is kept"
			)
			t.truthy(#(st.firstError :: string) <= C.FAULT_TEXT)
			local lines = 0
			for _, r in records do
				lines += if string.find(r.msg, "validator failed", 1, true) then 1 else 0
			end
			t.eq(lines, 1, "one log line in two seconds")
			t.eq((m:heldPlace("a")), 40)
			-- every other call into the validator: a teleport, the meter, a ride, a release
			m:teleported("a", 300, 0, 300, "reset", t0)
			t.eq((m:heldPlace("a")), 300, "the game's own move stands")
			t.eq(#h.tells, 1, "and its driver is told of it (no snap)")
			t.falsy(h.tells[1].snap)
			local stamina, winded = m:meterOf("a", t0)
			t.eq(stamina, 1)
			t.falsy(winded)
			m:suspend("a", true)
			m:suspend("a", false)
			m:onHandoff(ACTOR, nil, "release")
			Log.setClock(nil)
			Log.setSink()
		end
	)

	t.test("the judging budget: two packets over 2 ms in a second bench that body's judging for 5 s", function()
		Log.capture()
		local cost = 0.003
		local clock = 0
		local validator = fake(function(): any
			clock += cost
			return { ok = true, accepted = true, flagged = false, bucket = 0, violations = {} }
		end)
		local m = service(validator, nil, function(): number
			return clock
		end)
		local function send(i: number, now: number): any
			return m:packet("a", "squirrel", { seq = i, snapshot = shot(i, 0, now) }, now)
		end
		send(1, 1.00)
		t.eq(m:stats().benched, 0, "one slow packet alone is a cold cache")
		send(2, 1.05)
		t.eq(m:stats().benched, 1)
		t.eq(validator.accepts, 2)
		for i = 3, 60 do
			local r = send(i, 1.05 + (i - 2) * 0.05)
			t.truthy(r.accepted and r.unjudged, "taken unjudged while benched")
		end
		t.eq(validator.accepts, 2, "nothing judged for 5 s")
		t.eq((m:heldPlace("a")), 60, "the place goes on")
		cost = 0.0002 -- (the validator is quick again)
		for i = 61, 140 do
			send(i, 1.05 + (i - 2) * 0.05)
		end
		t.truthy(validator.accepts > 30, "judged again after the bench")
		local st = m:stats()
		t.eq(st.benched, 1)
		t.truthy(st.judgeMaxMs >= 2.9 and st.judgeMaxMs <= 3.1, `the worst packet ({st.judgeMaxMs} ms)`)
		t.eq(st.judged, validator.accepts)
		-- another body is judged all the while
		Log.setSink()
	end)

	t.test(
		"epochs and order: a packet sent before a move the server made is dropped; a client that never hears is believed",
		function()
			Log.capture()
			local h = hands()
			local m = service(
				fake(function(): any
					return { ok = true, accepted = true, flagged = false, bucket = 0, violations = {} }
				end),
				h
			)
			m:onHandoff(ACTOR, {}, "possess")
			local e1 = m:epochOf("a")
			t.eq((m:heldPlace("a")), 10, "before any packet: where the body was handed over")
			t.eq((m:heldPlace("a", true)), nil, "strict mode waits for the body's first word")
			m:packet("a", "squirrel", { seq = 5, epoch = e1, snapshot = shot(11, 0, 1) }, 1)
			local late = m:packet("a", "squirrel", { seq = 4, epoch = e1, snapshot = shot(90, 0, 0.9) }, 1.01)
			t.truthy(late.stale and not late.accepted, "overtaken on the way: dropped")
			t.eq((m:heldPlace("a")), 11)
			m:teleported("a", 200, 0, 200, "knock", 2)
			local e2 = m:epochOf("a")
			t.truthy(e2 ~= e1)
			local old = m:packet("a", "squirrel", { seq = 6, epoch = e1, snapshot = shot(12, 0, 2.02) }, 2.05)
			t.truthy(old.stale, "sent before the client knew")
			t.eq((m:heldPlace("a")), 200, "the body is where the server put it")
			local new = m:packet("a", "squirrel", { seq = 7, epoch = e2, snapshot = shot(201, 0, 2.1) }, 2.15)
			t.truthy(new.accepted)
			t.eq((m:heldPlace("a")), 201)
			-- a move whose word never reached the client: its old-epoch packets are believed once the round trips are over
			m:teleported("a", 400, 0, 400, "knock", 3)
			local i = 8
			local taken: number? = nil
			for step = 1, 80 do
				local now = 3 + step * 0.05
				local r = m:packet("a", "squirrel", { seq = i, epoch = e2, snapshot = shot(400 + step, 0, now) }, now)
				i += 1
				if r.accepted and taken == nil then
					taken = now
				end
			end
			t.truthy(taken ~= nil and (taken :: number) > 3 + C.IGNORED and (taken :: number) < 3 + C.IGNORED + 0.3)
			t.eq((m:heldPlace("a")), 480, "never stuck where the server last put it")
			t.truthy(m:stats().believed > 0)
			t.eq(h.snaps + h.holds + h.pins, 0)
			Log.setSink()
		end
	)

	t.test(
		"no packets at all: the root the server sees is the place, and the duel is told to believe its click",
		function()
			local m = service(fake(flagsAll), hands())
			m:onHandoff(ACTOR, {}, "possess")
			t.truthy(m:silent("a", 0), "nothing has come yet")
			for i = 1, 30 do
				m:watch("a", 10 + i, 0, 10, i / 15) -- (the root walks off; no packet ever comes)
			end
			t.eq((m:heldPlace("a")), 40, "the root, as before the live validator")
			t.eq((m:heldPlace("a", true)), 40)
			t.truthy(m:silent("a", 2))
			t.eq(m:stats().snaps, 0)
			-- the packets start: they are the place again
			Log.capture()
			m:packet("a", "squirrel", { seq = 1, snapshot = shot(77, 0, 2) }, 2.1)
			m:watch("a", 40, 0, 10, 2.12)
			Log.setSink()
			t.eq((m:heldPlace("a")), 77)
			t.falsy(m:silent("a", 2.2))
			t.truthy(m:silent("a", 2.1 + C.SAFE_SILENT + 0.1), "and when they stop")
			-- enforcing, nothing of this: never silent, the root is never the held place
			local e = MovementService.new({ validator = fake(flagsAll), enforce = true })
			e:onHandoff(ACTOR, {}, "possess")
			t.falsy(e:silent("a", 5))
		end
	)

	t.test("a pounce is dated by the packet's own attack window, whatever the validator says", function()
		Log.capture()
		local m = service(fake(flagsAll), nil)
		local whole = SquirrelMotor.params.pounceWindow
		for i = 1, 20 do
			m:packet("a", "squirrel", { seq = i, snapshot = shot(i, 0, i * 0.05) }, 50 + i * 0.05)
		end
		local _, _, none = m:motorOf("a")
		t.eq(none, nil, "no pounce yet")
		-- the motor pounced 0.02 s before this packet's clock
		m:packet("a", "squirrel", {
			seq = 21,
			snapshot = shot(21, 0, 1.05, function(s: any)
				s.attackWindow = whole - 0.02
				s.grounded = false
			end),
		}, 51.05)
		local _, lastAt, pounceAt = m:motorOf("a")
		Log.setSink()
		t.truthy(pounceAt ~= nil, "dated")
		t.truthy(math.abs((pounceAt :: number) - (51.05 - 0.02)) < 1e-6, `at the launch ({pounceAt})`)
		t.truthy((pounceAt :: number) <= (lastAt :: number))
	end)

	t.test("the duel: with no packet coming the click alone is the pounce (motorOf's believed)", function()
		local rig = BiteRig.new({
			seed = 4,
			duelRand = function(): number
				return 0
			end,
			motorCheck = true,
		})
		rig.step(20)
		local v = rig.calmNear(0, 0)
		rig.holdRodent()
		rig.put(rig.rodent, v.x + 6, v.z)
		t.truthy(rig.combat:rodentAct(rig.rodent, "pounce", rig.now()))
		rig.motor[rig.rodent] = { age = 0, cleanAge = 0, believed = true }
		rig.step(1.2, function()
			rig.put(rig.rodent, v.x + 0.5, v.z)
		end)
		t.eq(rig.combat:stats().bites, 1, "the bite lands")
		t.truthy(rig.combat:stats().believed > 0)
		t.eq(rig.combat:stats().noMotor, 0)
	end)

	t.test(
		"a real validator in safe mode: an honest run and a teleport cheat are both taken; only the numbers differ",
		function()
			Log.capture()
			local world = TestWorld.build({ boxes = {} })
			local m = MovementService.new({
				validator = MoveValidator.new(world),
				enforce = false,
				-- (the judging budget on a clock that stands still: a loaded machine benches nobody here)
				clock = function(): number
					return 0
				end,
			})
			local s = SquirrelMotor.new(10, world.groundHeight, 10)
			m:teleported("sq", s.x, s.y, s.z, "spawn", 0)
			local inp = SquirrelMotor.idleInput(0)
			inp.fw = 1
			for i = 0, 60 do
				if i > 0 then
					SquirrelMotor.step(s, inp, 1 / 60, world)
				end
				local v = m:packet("sq", "squirrel", { seq = i, snapshot = SquirrelMotor.serialize(s) }, i / 60)
				t.truthy(v.accepted and v.ok, `honest {i}`)
			end
			t.eq(m:stats().flagged, 0)
			local cheat = SquirrelMotor.serialize(s)
			cheat.x = (cheat.x :: number) + 400
			local v = m:packet("sq", "squirrel", { seq = 61, snapshot = cheat }, 1.02)
			Log.setSink()
			t.truthy(v.accepted and v.flagged and not v.snapped)
			t.eq((m:heldPlace("sq")), cheat.x, "believed, as in version 47")
			t.truthy(m:stats().flagged >= 1)
			t.eq(m:stats().snaps, 0)
			t.truthy(next(m:stats().codes) ~= nil, "its violations are counted by code")
		end
	)

	t.test("the owner's numbers: MoveDiag rates, the top five codes, the lines; the client's counters", function()
		local stats: any = {
			packets = 0,
			accepted = 0,
			flagged = 0,
			stale = 0,
			judged = 0,
			judgeMs = 0,
			judgeMaxMs = 0,
			snaps = 0,
			pins = 0,
			holds = 0,
			judgeErrors = 0,
			benched = 0,
			unjudged = 0,
			believed = 0,
			codes = {},
		}
		local meter = MoveDiag.new()
		local first = MoveDiag.sample(meter, stats, 100, false)
		t.eq(first.received, 0, "no rate before a second sample")
		stats.packets, stats.accepted, stats.flagged, stats.stale = 40, 38, 6, 2
		stats.judged, stats.judgeMs, stats.judgeMaxMs = 38, 3.8, 0.9
		stats.judgeErrors, stats.firstError = 3, "packet: boom"
		stats.codes = { float = 9, wall = 4, speed = 4, fly = 1, slab = 2, clock = 7, gate = 0 }
		local r = MoveDiag.sample(meter, stats, 102, false)
		t.eq(r.received, 20)
		t.eq(r.accepted, 19)
		t.eq(r.flagged, 3)
		t.eq(r.stale, 1)
		t.truthy(math.abs(r.judgeAvgMs - 0.1) < 1e-9)
		t.eq(r.judgeMaxMs, 0.9)
		t.eq(#r.top, 5)
		t.eq(r.top[1].code, "float")
		t.eq(r.top[2].code, "clock")
		t.eq(r.top[3].code, "speed", "ties by name")
		t.eq(r.top[4].code, "wall")
		t.eq(r.top[5].code, "slab")
		local text = MoveDiagPanel.text(r, { fps = 59.6, sent = 20, errors = 2, firstError = "step: nil" })
		for _, want in
			{
				"SAFE MODE",
				"20.0 in, 19.0 taken, 1.0 dropped",
				"flagged/s: 3.0",
				"float 9, clock 7, speed 4, wall 4, slab 2",
				"snaps 0   pins 0   holds 0",
				"avg 0.10, max 0.90",
				"validator errors: 3   first: packet: boom",
				"client: 60 fps   packets sent/s: 20.0",
				"client motor errors: 2   first: step: nil",
			}
		do
			t.truthy(string.find(text, want, 1, true), `the panel says "{want}":\n{text}`)
		end
		t.truthy(string.find(MoveDiagPanel.text(MoveDiag.sample(meter, stats, 103, true), nil), "ENFORCING", 1, true))
		t.truthy(string.find(MoveDiagPanel.text(nil, nil), "no word from the server", 1, true))
		-- the remote and the help line
		t.eq(Schemas.REMOTES["Move.Diag"].dir, "s2c")
		local help = table.concat(PlayMenu.helpLines("squirrel", nil, true), "\n")
		t.truthy(string.find(help, "F8: movement diagnostics (owner)", 1, true))
		t.falsy(string.find(table.concat(PlayMenu.helpLines("squirrel", nil), "\n"), "F8", 1, true), "the owner only")
		-- the client's counters: a step that fails every frame prints once every few seconds
		MotorHealth.reset()
		local printed = 0
		for i = 1, 600 do
			printed += if MotorHealth.fault(`step {i} failed`, 10 + i / 60) then 1 else 0
		end
		MotorHealth.sent()
		local health = MotorHealth.read()
		t.eq(printed, 2, "ten seconds of failing frames: two lines")
		t.eq(health.errors, 600)
		t.eq(health.firstError, "step 1 failed")
		t.eq(health.sent, 1)
		MotorHealth.reset()
		-- the anti-gravity force is never sized from an anchored assembly's infinite mass
		t.eq(MotorHealth.finiteMass(3.5, 99), 3.5)
		t.eq(MotorHealth.finiteMass(math.huge, 3.5), 3.5)
		t.eq(MotorHealth.finiteMass(0 / 0, 3.5), 3.5)
		t.eq(MotorHealth.finiteMass(math.huge, math.huge), 0)
	end)

	t.test(
		"the wiring: the live game runs the safe mode, its watch and packets are caught, the owner gets the panel",
		function()
			local fs = require("@lune/fs")
			local main = fs.readFile("src/server/Main.server.luau")
			t.truthy(
				string.find(main, 'Flags.set("moveValidatorEnforce", false)', 1, true),
				"Server/Main switches it off"
			)
			local src = fs.readFile("src/server/Boot/Game.luau")
			t.truthy(
				string.find(src, 'movement:fault("watch", actor.id, err)', 1, true),
				"the watch is caught per body"
			)
			t.truthy(
				string.find(src, "movement:silent(actor.id, t)", 1, true),
				"the duel believes a click with no packets"
			)
			t.truthy(string.find(src, 'net:fire(player, "Move.Diag", report)', 1, true), "the report goes to the owner")
			t.truthy(string.find(src, "Game.placeOwner(player)", 1, true))
			local client = fs.readFile("src/client/Main.client.luau")
			t.truthy(string.find(client, "pcall(MoveDiagPanel.start)", 1, true))
			local driver = fs.readFile("src/client/Controllers/BodyDriver.luau")
			t.falsy(
				string.find(driver, "root.AssemblyMass * workspace.Gravity", 1, true),
				"never the raw assembly mass"
			)
			t.truthy(string.find(driver, "MotorHealth.finiteMass", 1, true))
		end
	)
end
