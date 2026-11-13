--!strict
-- The storm drains as cover, on the real town AI headless (BRIEF_ADDENDUM D8; brief v2 §8 "refuges between bites";
-- Server/World/SewerService over AI/TownAI's cover and Shared/World/SewerLayout):
--   down a pipe nobody sees or hears the rodent (a crowd round the crossing for a simulated minute), in the open over
--   the same spot it is seen at once; the fox does not hunt it; the crowd's fears (InfectionService) leave it out;
--   the computer's own animals never go down
--   seen going down a grate: the bystanders who saw it say a drain line (never more than C.speakers, and the town's
--   speech limits hold); an officer who saw it runs to the grate, stands over it facing it for sewer.stakeoutSecs,
--   says "It went down the drain!" and goes back to the beat; nobody goes to the other end
--   a body let go in a pipe comes back at the nearest mouth of that pipe, on its feet, facing out
--   the rodent heals there at the hollow rate only while fed; the re-entry mouth, the fashion stand's home and the
--   alligator's line (a sound and a line, no asset)
-- The perception golden (tests/unit/perception_spotted, 3,010 vectors) is untouched: Actors/Perception is not changed.
local Data = require("@shared/Data")
local SewerLayout = require("@shared/World/SewerLayout")
local SpeechRules = require("@shared/Speech/SpeechRules")
local Lines = require("@shared/Speech/Lines")
local Tunables = require("@shared/Config/Tunables")
local Common = require("@server/Actors/Brains/Common")
local Fox = require("@server/Actors/Brains/Fox")
local TownAI = require("@server/AI/TownAI")
local InfectionService = require("@server/Infection/InfectionService")
local SewerService = require("@server/World/SewerService")

local DT = 1 / 60
local SIDEWALK = 30.25 -- studs: the core sidewalks' lane line off the road centre (12.1 u)

type Rig = {
	world: TownAI.World,
	svc: SewerService.Service,
	attrs: { [number]: { [string]: any } },
	events: { TownAI.Event },
	rodent: any,
	step: (n: number, each: (() -> ())?) -> (),
}

return function(t)
	local data = Data.default()
	local layout = SewerLayout.default() :: SewerLayout.Layout
	local rail: any = nil

	local function seeded(seed: number): () -> number
		local a = seed
		return function(): number
			a = (a * 1103515245 + 12345) % 2147483648
			return a / 2147483648
		end
	end

	local function rig(opts: { humans: number?, fox: number?, speech: any?, focus: { number }? }?): Rig
		local o = opts or {}
		local world = TownAI.build({
			data = data,
			seed = 1,
			humans = o.humans or 90,
			squirrels = 3,
			deer = 0,
			fox = o.fox or 0,
			rail = rail,
		})
		rail = world.rail
		local focus = o.focus or { 0, 0 }
		TownAI.setFocus(world, function()
			return { { x = focus[1], z = focus[2] } }
		end)
		local r = { world = world, attrs = {}, events = {} } :: any
		r.svc = SewerService.new({
			world = world,
			layout = layout,
			speech = o.speech,
			rand = seeded(7),
			setAttr = function(id: number, name: string, value: any)
				r.attrs[id] = r.attrs[id] or {}
				r.attrs[id][name] = value
			end,
		})
		TownAI.listen(world, function(ev: TownAI.Event)
			table.insert(r.events, ev)
		end)
		for _, a in world.actors do
			if a.variant == "spicy" then
				r.rodent = a
			end
		end
		r.step = function(n: number, each: (() -> ())?)
			for _ = 1, n do
				if each then
					each()
				end
				TownAI.stepFrame(world, DT)
			end
		end
		return r :: Rig
	end

	-- a body a player holds: out of the AI, wherever the test puts it
	local function hold(world: TownAI.World, a: any, x: number, y: number, z: number)
		if not world.possessed[a.id] then
			TownAI.suspend(world, a.id)
		end
		a.x, a.y, a.z = x, y, z
		a.speed = 0
	end

	-- a person put somewhere by the possession seam (they adopt the nearest lane from there)
	local function put(world: TownAI.World, a: any, x: number, z: number, faceX: number, faceZ: number)
		TownAI.suspend(world, a.id)
		TownAI.resume(world, a.id, x, world.ctx.groundAt(x, z) + a.hip, z, Common.yawOf(faceX - x, faceZ - z))
	end

	local function kindOf(world: TownAI.World, a: any): string
		local b = world.brains[a.id]
		return if b then b.kind else ""
	end

	local function people(world: TownAI.World, kind: string): { any }
		local out = {}
		for _, a in world.actors do
			if a.species == "human" and a.post ~= "rider" and kindOf(world, a) == kind then
				table.insert(out, a)
			end
		end
		return out
	end

	-- 30 townspeople on the four core sidewalks round the Main Street / Centre Street crossing
	local function crowd(world: TownAI.World): number
		local walkers = people(world, "Pedestrian")
		local n = math.min(30, #walkers)
		for i = 1, n do
			local a = walkers[i]
			local side = (i - 1) % 4
			local u = -45 + 90 * ((i - 1) // 4) / 7
			local x, z
			if side == 0 then
				x, z = u, SIDEWALK
			elseif side == 1 then
				x, z = u, -SIDEWALK
			elseif side == 2 then
				x, z = SIDEWALK, u
			else
				x, z = -SIDEWALK, u
			end
			put(world, a, x, z, 0, 0)
		end
		return n
	end

	local function spotsOf(r: Rig, id: number): number
		local n = 0
		for _, ev in r.events do
			if ev.kind == "spotted" and ev.other == id then
				n += 1
			end
		end
		return n
	end

	local chamber = layout.chambers[1]
	local function crossing(): (number, number, number)
		return chamber.crossing.x, chamber.crossing.y, chamber.crossing.z
	end

	t.test(
		"down the drain nobody sees it: 30 people round the crossing, 3,600 frames, no spot; in the open, seen",
		function()
			local r = rig()
			local world = r.world
			local rodent = r.rodent
			t.truthy(crowd(world) >= 30, "a crowd of 30")
			local cx, cy, cz = crossing()
			t.eq(layout.contains(cx, cy + rodent.hip, cz), "sewer.crossroads", "the crossing is in P1's chamber")
			r.step(3600, function()
				hold(world, rodent, cx, cy + rodent.hip, cz)
			end)
			t.eq(TownAI.covered(world, rodent.id), "sewer.crossroads")
			t.eq(r.svc:underground(rodent.id), "sewer.crossroads")
			t.eq(spotsOf(r, rodent.id), 0, "spots of the rodent under the crossing")
			-- the same rodent straight up in the road, half a stud off the ground: seen within 2 s
			local seenAt: number? = nil
			for f = 1, 120 do
				hold(world, rodent, 0, 0.5, 0)
				TownAI.stepFrame(world, DT)
				if seenAt == nil and spotsOf(r, rodent.id) > 0 then
					seenAt = f
				end
			end
			t.truthy(seenAt ~= nil, "spotted within 120 frames in the open")
			print(`      in the open: first spot after {seenAt} frames`)
			t.eq(TownAI.covered(world, rodent.id), nil)
			-- nothing the computer runs ever went down: the only actor the cover ever hid is the held rodent
			for _, ev in r.events do
				if ev.kind == "covered" then
					t.eq(ev.id, rodent.id, "only the held rodent was hidden")
				end
			end
		end
	)

	t.test("the fox: hunts the rodent in the open, not under the street; the crowd's fears leave it out", function()
		local r = rig()
		local world = r.world
		local rodent = r.rodent
		local cx, cy, cz = crossing()
		local foxActor = Common.newActor(99999, "fox", "fox", "Fox", cx + 20, cz + 10, 1)
		local brain = Fox.new(foxActor, { originX = cx + 20, originZ = cz + 10 })
		local infection = InfectionService.new({ world = world, data = data })
		local function think(): any
			brain:think(0.1, world.ctx)
			return foxActor.intent
		end
		-- under the street
		r.step(3, function()
			hold(world, rodent, cx, cy + rodent.hip, cz)
		end)
		t.eq(r.svc:underground(rodent.id), "sewer.crossroads")
		local under = think()
		t.near(under.turnRate, 1.5, 1e-9, "roaming, not hunting")
		t.falsy(table.find(infection:feared(), rodent), "nobody fears a rodent under the street")
		local n = world.grid:query(cx, cz, 30, world.ctx.queryBuffer)
		for i = 1, n do
			t.neq(world.ctx.queryBuffer[i], rodent.id, "not in the threat grid")
		end
		-- the same spot up on the road
		r.step(3, function()
			hold(world, rodent, cx, 0.5, cz)
		end)
		t.eq(r.svc:underground(rodent.id), nil)
		local open = think()
		t.near(open.turnRate, 7, 1e-9, "hunting")
		t.near(open.heading, Common.yawOf(cx - foxActor.x, cz - foxActor.z), 1e-6, "at the rodent")
		t.truthy(table.find(infection:feared(), rodent) ~= nil, "feared in the open")
	end)

	t.test("seen going down: two bystanders remark, the officer watches the grate 15 s, says so, goes back", function()
		local m = layout.mouth("P1.NW") :: SewerLayout.Mouth
		local r = rig({ focus = { m.x, m.z } })
		local world = r.world
		local rodent = r.rodent
		local officer = people(world, "Officer")[1]
		t.truthy(officer ~= nil, "an officer")
		-- the officer 12 studs west of the grate, looking at it; four people near it too
		put(world, officer, m.x - 12, m.z + 2, m.x, m.z)
		local walkers = people(world, "Pedestrian")
		for i = 1, 4 do
			put(world, walkers[i], m.x + 4 + i, m.z + 3, m.x, m.z)
		end
		local lost: { SewerService.Lost } = {}
		local unlisten = TownAI.listen(world, function(ev: TownAI.Event)
			if ev.kind == "covered" then
				lost = r.svc:lost()
			end
		end)
		-- on the grate, then down the shaft
		r.step(2, function()
			hold(world, rodent, m.x, m.y + rodent.hip, m.z)
		end)
		t.eq(r.svc:underground(rodent.id), nil, "standing on the grate is not underground")
		r.step(1, function()
			hold(world, rodent, m.x, m.y - 3, m.z)
		end)
		unlisten()
		t.eq(r.svc:underground(rodent.id), "sewer.crossroads")
		t.eq(#lost, 1, "one report")
		local report = lost[1]
		t.eq(report.mouth, "P1.NW")
		t.truthy(table.find(report.witnesses, officer.id) ~= nil, "the officer saw it")
		t.deepEq(report.officers, { officer.id })
		local spoke = 0
		for _, w in report.witnesses do
			local say = (r.attrs[w] or {}).Say
			if say then
				t.truthy(table.find(Lines.GROUPS.drain, say) ~= nil, `a drain line ("{say}")`)
				spoke += 1
			end
		end
		t.truthy(spoke >= 1 and spoke <= SewerService.C.speakers, `{spoke} bystanders spoke`)
		-- the officer runs to the grate, stands there facing it, then goes back to the beat
		local arrivedAt: number? = nil
		local spot: { number }? = nil
		local leftAt: number? = nil
		local secs = Tunables.get("sewer.stakeoutSecs")
		local drift, worstFacing = 0, 0
		local nearestOtherEnd = math.huge
		local frames = math.ceil((secs + 12) / DT)
		for f = 1, frames do
			hold(world, rodent, m.x, m.y - 3, m.z)
			TownAI.stepFrame(world, DT)
			local now = f * DT
			if arrivedAt == nil and (r.attrs[officer.id] or {}).Say == "It went down the drain!" then
				arrivedAt = now
			end
			if arrivedAt and spot == nil and officer.speed < 0.05 then
				spot = { officer.x, officer.z }
			end
			if spot and leftAt == nil then
				local moved = math.sqrt((officer.x - spot[1]) ^ 2 + (officer.z - spot[2]) ^ 2)
				if moved > 1 then
					leftAt = now
				elseif now < (arrivedAt :: number) + secs - 0.3 then
					drift = math.max(drift, moved)
					local face = Common.yawOf(m.x - officer.x, m.z - officer.z)
					worstFacing = math.max(worstFacing, math.abs(Common.angleDelta(officer.yaw, face)))
				end
			end
			for _, other in layout.mouthsOf("P1") do
				if other.id ~= m.id then
					nearestOtherEnd =
						math.min(nearestOtherEnd, math.sqrt((officer.x - other.x) ^ 2 + (officer.z - other.z) ^ 2))
				end
			end
		end
		local s = spot or { math.huge, math.huge }
		local standDist = math.sqrt((s[1] - m.x) ^ 2 + (s[2] - m.z) ^ 2)
		print(
			`      officer: line at {arrivedAt} s, {standDist} st from the grate, left at {leftAt} s, drift {drift} st, facing within {math.deg(
				worstFacing
			)} deg`
		)
		t.truthy(arrivedAt ~= nil and (arrivedAt :: number) < 4, "at the grate within 4 s, saying the line")
		t.truthy(math.abs(standDist - SewerService.C.standOff) < 1, "standing beside the grate")
		t.truthy(drift < 0.2, "holding still")
		t.truthy(worstFacing < math.rad(10), "facing the grate")
		t.truthy(leftAt ~= nil, "went back to the beat")
		local held = (leftAt :: number) - (arrivedAt :: number)
		t.truthy(held >= secs - 0.2 and held <= secs + 3, `held {held} s`)
		t.truthy(nearestOtherEnd > 40, "never went toward another mouth of the pipe")
	end)

	t.test("the town's speech limits hold: a full window silences the bystanders; the officer still says it", function()
		local m = layout.mouth("P1.SE") :: SewerLayout.Mouth
		local speech = SpeechRules.new()
		local r = rig({ focus = { m.x, m.z }, speech = speech })
		local world = r.world
		local rodent = r.rodent
		local walkers = people(world, "Pedestrian")
		for i = 1, 6 do
			put(world, walkers[i], m.x - 3 - i, m.z - 3, m.x, m.z)
		end
		local officer = people(world, "Officer")[1]
		put(world, officer, m.x + 10, m.z - 2, m.x, m.z)
		-- three lines just said in town (the window is townBurst per townWindowS)
		local burst = Tunables.get("speech.townBurst")
		for i = 1, burst do
			SpeechRules.request(speech, world.now, -i, "bitten", function()
				return 0
			end, { force = true })
		end
		r.step(2, function()
			hold(world, rodent, m.x, m.y + rodent.hip, m.z)
		end)
		r.step(1, function()
			hold(world, rodent, m.x, m.y - 3, m.z)
		end)
		local report = r.svc:lost()[1]
		t.truthy(#report.witnesses >= 3, `{#report.witnesses} saw it`)
		for _, w in report.witnesses do
			if w ~= officer.id then
				t.eq((r.attrs[w] or {}).Say, nil, "quiet: the town window is full")
			end
		end
		r.step(300, function()
			hold(world, rodent, m.x, m.y - 3, m.z)
		end)
		t.eq((r.attrs[officer.id] or {}).Say, "It went down the drain!", "the officer's line is forced")
		-- an ordinary squirrel going down the same grate: people may remark, the police do not come
		local other: any = nil
		for _, a in world.actors do
			if a.species == "squirrel" and a.variant == "normal" then
				other = a
			end
		end
		r.step(2, function()
			hold(world, other, m.x, m.y + other.hip, m.z)
		end)
		r.step(1, function()
			hold(world, other, m.x, m.y - 3, m.z)
		end)
		local last = r.svc:lost()
		t.eq(last[#last].actor, other.id)
		t.eq(#last[#last].officers, 0, "no stakeout for an ordinary squirrel")
	end)

	t.test("let go in a pipe: the AI takes the body at that pipe's nearest mouth, standing, facing out", function()
		local r = rig()
		local world = r.world
		local rodent = r.rodent
		-- in the middle of P2 (under the river), nearer the east end
		local pass = (layout.pipe("P2") :: SewerLayout.Pipe).passages[1]
		local pts = pass.points
		local a, b = pts[2], pts[#pts - 1]
		local x, y, z = a.x + (b.x - a.x) * 0.7, a.y + (b.y - a.y) * 0.7 + rodent.hip, a.z + (b.z - a.z) * 0.7
		t.eq(layout.contains(x, y, z), "sewer.culvert")
		r.step(2, function()
			hold(world, rodent, x, y, z)
		end)
		t.eq(r.svc:underground(rodent.id), "sewer.culvert")
		TownAI.resume(world, rodent.id, x, y, z)
		local best: SewerLayout.Mouth? = nil
		for _, mm in layout.mouthsOf("P2") do
			if best == nil or (mm.x - x) ^ 2 + (mm.z - z) ^ 2 < (best.x - x) ^ 2 + (best.z - z) ^ 2 then
				best = mm
			end
		end
		local m = best :: SewerLayout.Mouth
		t.eq(m.id, "P2.E")
		t.near(rodent.x, m.x, 1e-9)
		t.near(rodent.z, m.z, 1e-9)
		t.near(rodent.y, m.y + rodent.hip, 1e-9, "standing on the street")
		t.near(rodent.yaw, math.atan2(m.out.x, m.out.z), 1e-9, "facing out")
		r.step(1)
		t.eq(r.svc:underground(rodent.id), nil, "in the open again")
		t.eq(r.events[#r.events].kind, "uncovered")
		-- let go in the open: left where it is
		TownAI.suspend(world, rodent.id)
		TownAI.resume(world, rodent.id, 10, 2, 20)
		t.near(rodent.x, 10, 1e-9)
		t.near(rodent.z, 20, 1e-9)
	end)

	t.test(
		"refuge: the rodent heals at the hollow rate in a pipe only while fed; re-entry, the stand, the alligator",
		function()
			local r = rig()
			local world = r.world
			local rodent = r.rodent
			local svc = r.svc
			local cx, cy, cz = crossing()
			local hollow = Tunables.get("rodent.regenHollow")
			t.eq(svc:healRate(rodent.id, true), 0, "not in the open")
			t.eq(svc:idleWarning(rodent.id), nil)
			r.step(2, function()
				hold(world, rodent, cx, cy + rodent.hip, cz)
			end)
			t.truthy(svc:isRefuge(rodent.id))
			t.eq(svc:healRate(rodent.id, true), hollow, "fed: the hollow rate")
			t.eq(svc:healRate(rodent.id, false), 0, "unfed: nothing")
			t.near(svc:heal(rodent.id, 50, 100, 10, true), 50 + hollow * 10, 1e-9)
			t.eq(svc:heal(rodent.id, 99.99, 100, 10, true), 100, "never above full")
			t.eq(svc:heal(rodent.id, 0, 100, 10, true), 0, "the dead stay dead")
			t.eq(svc:heal(rodent.id, 50, 100, 10, false), 50)
			-- fed means a bite within a game day
			local day = Tunables.get("rodent.fedWindowDays") * Tunables.get("clock.realSecondsPerDay")
			t.truthy(SewerService.fed(100, 100 + day - 1))
			t.falsy(SewerService.fed(100, 100 + day + 1))
			t.falsy(SewerService.fed(nil, 5))
			-- an ordinary squirrel down there is hidden but does not heal like the rodent
			local other: any = nil
			for _, a in world.actors do
				if a.variant == "normal" then
					other = a
				end
			end
			r.step(2, function()
				hold(world, rodent, cx, cy + rodent.hip, cz)
				hold(world, other, cx + 1, cy + other.hip, cz)
			end)
			t.truthy(svc:isRefuge(other.id))
			t.eq(svc:healRate(other.id, true), 0)
			-- the alligator: a line and a cue name, no asset
			local w = svc:idleWarning(rodent.id) :: SewerService.Warning
			t.eq(w.predator, "small alligator")
			t.eq(w.text, "A low hiss and a ripple in the sewer water.")
			t.eq(w.cue, "sewer.hiss")
			for name, id in SewerService.CUES do
				t.eq(id, "", `{name} has no asset yet`)
			end
			-- the re-entry mouth after a death at the crossing: far enough, nobody near it
			local m = svc:reentry(0, 0) :: SewerLayout.Mouth
			t.truthy(m ~= nil)
			t.truthy(math.sqrt(m.x ^ 2 + m.z ^ 2) >= SewerLayout.C.reentryMin, "away from the death")
			for _, a in world.actors do
				if a.species == "human" then
					t.truthy((a.x - m.x) ^ 2 + (a.z - m.z) ^ 2 >= SewerLayout.C.reentryClear ^ 2, "nobody at the mouth")
				end
			end
			-- the fashion stand's new home: on the floor of P1's chamber
			local stand = svc:fashionStand() :: SewerLayout.Anchor
			t.eq(stand.kind, "fashionStand")
			t.eq(stand.space, "sewer.crossroads")
			t.eq(layout.contains(stand.x, stand.y + 0.5, stand.z), "sewer.crossroads")
			t.near(stand.y, chamber.y, 1e-9, "on the chamber floor")
			-- stop: nothing hides any more
			svc:stop()
			r.step(1, function()
				hold(world, rodent, cx, cy + rodent.hip, cz)
			end)
			t.eq(TownAI.covered(world, rodent.id), nil)
		end
	)
end
