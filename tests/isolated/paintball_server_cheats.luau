--!strict
-- tests/isolated/paintball_server_cheats.luau: what a modified client tried at the review (2026-11-13), each
-- now refused, against the whole service on the fake engine (tests/isolated/paintball_server_kit). Every case
-- is one of the netcode reviewer's probes, which as first built went through:
--   A  crouched behind a rail, the air bit claimed on the floor bought a standing-eye shot over it
--   B  half a second of withheld Moves let a body fire from 7.5 studs out in the open while its puppet and
--      its history stood behind a wall
--   C  three clicks back-dated in one packet after a pause were balls born together
--   D  a ball fired straight behind the look the Moves show, the puppet never turned to it
--   E  one Move standing between two crouched ones bought a standing-eye shot while the shape stayed low
--   F  Moves stamped early on a fast link bought the slow link's rewind (a hit on where a runner was 0.3 s ago)
--   H  standing still a moment, then one Move ten studs on
-- ONLY IN AN ISOLATED RUN (it needs the rig).
local Arena = require("@shared/Minigames/Paintball/Arena")
local Body = require("@shared/Minigames/Paintball/Body")
local Kit = require("@tests/isolated/paintball_server_kit")

local function teamOf(kit: Kit.Kit, c: Kit.Client): number
	return kit.state().slots[c.seat].team
end

local function people(kit: Kit.Kit, names: { string }, copts: { { [string]: any } }?): ...Kit.Client
	local out: { Kit.Client } = {}
	for i, name in names do
		local c = kit.client(name, if copts then copts[i] else nil)
		assert(kit.join(c))
		kit.run(0.1)
		out[i] = c
	end
	kit.run(0.5)
	for i, c in out do
		assert(teamOf(kit, c) == (if i % 2 == 1 then 1 else 2), `{c.name} is on the wrong side for this case`)
	end
	kit.live()
	return table.unpack(out)
end

local function ack(kit: Kit.Kit, c: Kit.Client, shot: number): any
	kit.untilTrue(1, function(): boolean
		return c.acks[shot] ~= nil
	end)
	return c.acks[shot] or error(`{c.name} heard no ack for shot {shot}`)
end

local function tagged(c: Kit.Client, by: number): boolean
	for _, tg in c.tags do
		if tg.by == by and tg.id == c.seat then
			return true
		end
	end
	return false
end

return function(t)
	t.test("A: crouched behind a rail, the air bit claimed on the floor buys no standing-eye shot over it", function()
		Kit.play(function(kit)
			local ada, bea = people(kit, { "Ada", "Bea" })
			kit.walk(bea, 20, 0)
			kit.walk(ada, -2.5, 0)
			ada.crouch = true
			kit.run(0.6)
			t.near(kit.service.poses[ada.seat].crouch, 1, 1e-6)
			ada.fixedLook = true
			ada.air = true -- claimed, never off the floor
			kit.run(0.3)
			local ex, ey, ez = ada.x, ada.y + Body.STAND_EYE, ada.z
			local dx, dy, dz = 20 - ex, 3 - ey, 0 - ez
			local len = math.sqrt(dx * dx + dy * dy + dz * dz)
			ada.yaw, ada.pitch = Body.yawPitch(dx, dy, dz)
			kit.run(0.1)
			local a = ack(kit, ada, ada.fire(dx / len, dy / len, dz / len, { ox = ex, oy = ey, oz = ez }))
			t.deepEq({ a.ok, a.why }, { false, "origin" })
			kit.run(0.6)
			t.falsy(tagged(bea, ada.seat))
		end, { arena = Kit.hall({ rail = true, room2 = 30 }) })
	end)

	t.test("B: a client that withholds its Moves cannot fire from somewhere its puppet never went", function()
		Kit.play(function(kit)
			local ada, bea = people(kit, { "Ada", "Bea" })
			kit.walk(bea, -10, 10)
			kit.walk(ada, -32, -6)
			-- (she looks Bea's way first, so that only where the shot left from is in question)
			ada.fixedLook = true
			ada.yaw, ada.pitch = Body.yawPitch(ada.aim(-10, 3, 10))
			kit.run(0.3)
			ada.silent = true
			kit.walk(ada, -32, 1.5) -- 7.5 studs out into the open, unseen (0.44 s at a walk)
			local frozen = kit.service.poses[ada.seat]
			t.near(frozen.z, -6, 0.01, "the server still has her behind the wall")
			local dx, dy, dz = ada.aim(-10, 3, 10)
			local a = ack(kit, ada, ada.fire(dx, dy, dz))
			t.falsy(a.ok, "a shot from the open")
			-- (held for the Moves that would say where she was, which never come: stale by then, or else not hers)
			t.truthy(a.why == "origin" or a.why == "stale", tostring(a.why))
			kit.run(0.6)
			t.falsy(tagged(bea, ada.seat))
		end, { arena = Kit.hall({ wall = true }) })
	end)

	t.test("C: three clicks back-dated in one packet after a pause are never balls born together", function()
		Kit.play(function(kit)
			local ada, bea = people(kit, { "Ada", "Bea" })
			kit.walk(ada, -36, -2)
			kit.run(1)
			local now = kit.now()
			local before = #bea.shots
			for i, ft in { now - 0.5, now - 0.25, now } do
				ada.fire(1, 0, (i - 2) * 0.03, { ft = ft })
			end
			kit.run(1)
			local births = {}
			for i = before + 1, #bea.shots do
				table.insert(births, bea.shots[i].t)
			end
			t.truthy(#births >= 2, `{#births} balls`)
			table.sort(births)
			for i = 2, #births do
				t.truthy(
					births[i] - births[i - 1] >= kit.state().feel.fireInterval - 0.05 - 1e-6,
					`balls {i - 1} and {i} born {births[i] - births[i - 1]} s apart`
				)
			end
		end)
	end)

	t.test(
		"D: a ball fired behind the look its own Move shows is refused; with no Move of its own, it is shown",
		function()
			Kit.play(function(kit)
				local ada = people(kit, { "Ada", "Bea" })
				kit.walk(ada, -36, -2)
				ada.fixedLook = true
				ada.yaw = Body.yawPitch(-1, 0, 0)
				kit.run(0.5)
				-- the click's own Move says she looks west; the ball goes east
				ada.move()
				local a = ack(kit, ada, ada.fire(1, 0, 0))
				t.deepEq({ a.ok, a.why }, { false, "origin" })
				-- the same ball with no Move of its own (the silent aim): it stands, and every screen is shown her
				-- puppet turned the way it went
				kit.run(0.3)
				local b = ack(kit, ada, ada.fire(1, 0, 0))
				t.truthy(b.ok)
				local east = Body.yawPitch(1, 0, 0)
				local shown = false
				for _ = 1, 20 do
					kit.frame()
					local drawn = kit.service.poses[ada.seat]
					if math.abs(drawn.yaw - east) < 0.05 then
						shown = true
					end
				end
				t.truthy(shown, "her puppet is turned to the shot")
				-- and a ball along her look is a shot
				kit.run(0.3)
				ada.move()
				t.truthy(ack(kit, ada, ada.fire(-1, 0, 0)).ok)
			end)
		end
	)

	t.test("E: one Move standing between two crouched ones buys no standing-eye shot over the rail", function()
		Kit.play(function(kit)
			local ada, bea = people(kit, { "Ada", "Bea" })
			kit.walk(bea, 20, 0)
			kit.walk(ada, -2.5, 0)
			ada.crouch = true
			kit.run(0.6)
			ada.fixedLook = true
			local ex, ey, ez = ada.x, ada.y + Body.STAND_EYE, ada.z
			local dx, dy, dz = 20 - ex, 3 - ey, 0 - ez
			local len = math.sqrt(dx * dx + dy * dy + dz * dz)
			ada.yaw, ada.pitch = Body.yawPitch(dx, dy, dz)
			ada.crouch = false
			ada.move()
			local s = ada.fire(dx / len, dy / len, dz / len, { ox = ex, oy = ey, oz = ez })
			kit.frame()
			ada.crouch = true
			ada.move()
			local a = ack(kit, ada, s)
			t.deepEq({ a.ok, a.why }, { false, "origin" })
			kit.run(0.6)
			t.falsy(tagged(bea, ada.seat))
		end, { arena = Kit.hall({ rail = true, room2 = 30 }) })
	end)

	for _, back in { 0, 0.2 } do
		t.test(
			`F: Moves stamped {back} s early on a fast link buy no rewind: a click at where a runner was 0.3 s ago misses`,
			function()
				Kit.play(function(kit)
					local ada = kit.client("Ada")
					local bea = kit.client("Bea")
					local orig = ada.move
					ada.move = function(over: any): any
						local rec = { t = kit.now() - back }
						for k, v in over or {} do
							rec[k] = v
						end
						return orig(rec)
					end
					assert(kit.join(ada))
					kit.run(0.1)
					assert(kit.join(bea))
					kit.run(0.6)
					kit.live()
					kit.walk(bea, -16, 10)
					kit.walk(ada, -36, 0)
					kit.run(0.5)
					local passed: number? = nil
					for _ = 1, 120 do
						bea.z -= Body.WALK / 60
						kit.frame()
						if passed == nil and bea.z <= 0 then
							passed = kit.now()
						end
						if passed ~= nil and kit.now() >= passed + 0.3 then
							break
						end
					end
					local now = kit.now()
					local dx, dy, dz = ada.aim(-16, 3, 0)
					ada.fire(dx, dy, dz, if back > 0 then { ft = now - 0.25, vt = now - 0.5 } else { vt = now - 0.3 })
					for _ = 1, 40 do
						bea.z -= Body.WALK / 60
						kit.frame()
					end
					t.falsy(tagged(bea, ada.seat), "where she was 0.3 s ago is not where she is")
				end)
			end
		)
	end

	t.test("H: standing still a moment buys no ten-stud jump in one Move, nor a shot from where it landed", function()
		Kit.play(function(kit)
			local ada = people(kit, { "Ada", "Bea" })
			kit.walk(ada, -36, -10)
			kit.run(0.7)
			ada.auto = false
			ada.x += 9.5
			ada.move()
			kit.run(0.1)
			local stats = kit.service:stats()
			t.truthy(stats.movesRefused >= 1, "the jump is refused")
			t.near(kit.service.poses[ada.seat].x, -36, 0.01, "and she is drawn where she was")
			local a = ack(kit, ada, ada.fire(1, 0, 0))
			t.falsy(a.ok, "nor is there a shot from where it landed")
			local _ = Arena
		end)
	end)

	t.test(
		"the owner's tuning: only the owner may; the words say what changed; out of range is refused with its range",
		function()
			Kit.play(function(kit)
				local ada, bea = people(kit, { "Ada", "Bea" })
				local Contract = require("@shared/Minigames/Paintball/Contract")
				local function tune(c: Kit.Client, args: { any }): (boolean, string?)
					return kit.w.svc:input(c.stub, { gameId = Contract.STATION, verb = "tune", args = args })
				end
				local was = kit.service.feel.ballSpeed
				t.deepEq({ tune(ada, { "ballSpeed", 120 }) }, { true, nil })
				t.eq(kit.service.feel.ballSpeed, 120, "for the next match")
				t.eq(kit.state().feel.ballSpeed, was, "the match in play keeps its own")
				kit.run(0.2)
				local said = ada.last("paintball_tuned")
				t.truthy(said ~= nil, "the owner is told")
				t.eq(said.text, `Ball speed: {was} -> 120, from the next match`)
				t.deepEq({ tune(bea, { "ballSpeed", 200 }) }, { false, "Only the place's owner can tune paintball." })
				t.eq(kit.service.feel.ballSpeed, 120)
				t.deepEq({ tune(ada, { "ballSpeed", 500 }) }, { false, "ballSpeed must be a number from 80 to 200" })
				t.eq((tune(ada, { "botSkill", -0.2 })), true)
				t.eq((tune(ada, { "gravity", 1 })), false)
				t.eq((tune(ada, { "" })), true)
				kit.run(0.2)
				t.truthy(string.find(ada.last("paintball_tuned").text, "ballSpeed 120", 1, true) ~= nil)
			end, {
				paintball = {
					owner = function(player: any): boolean
						return player.Name == "Ada"
					end,
				},
			})
		end
	)

	t.test(
		"PB-11: a squirrel in the lobby annex or the arena is put out on the street; one outside is left alone",
		function()
			local knocked: { { [string]: any } } = {}
			local critters: { { [string]: any } } = {}
			Kit.play(function(kit)
				people(kit, { "Ada", "Bea" })
				local place = kit.place
				local lx, ly, lz = Arena.toWorld(place, -14, 0, 75) -- in the annex, by the pass desk
				local ox, oy, oz = Arena.toWorld(place, 0, 0, 130) -- out on the street
				table.insert(critters, { id = "sq1", kind = "squirrel", x = lx, y = ly + 0.5, z = lz })
				table.insert(critters, { id = "sq2", kind = "squirrel", x = ox, y = oy + 0.5, z = oz })
				kit.run(1.2)
				t.truthy(#knocked >= 1)
				for _, k in knocked do
					t.eq(k.id, "sq1", "only the one inside")
					local x, _, z = Arena.toLocal(place, k.x, k.y, k.z)
					t.truthy(z > Arena.HALF + 31 and math.abs(x) < 5, "put out in front of the door")
					t.truthy(string.find(k.text, "for people", 1, true) ~= nil)
				end
			end, {
				service = {
					animals = function(): { { [string]: any } }
						return critters
					end,
					knock = function(id: any, x: number, y: number, z: number, text: string)
						table.insert(knocked, { id = id, x = x, y = y, z = z, text = text })
					end,
				},
			})
		end
	)
end
