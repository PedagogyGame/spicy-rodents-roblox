--!strict
-- tests/isolated/paintball_contract.luau: cases for tests/unit/paintball_contract.spec.luau, run in their own
-- Lune process (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Paintball in the minigame framework, with the stubs every lane starts from: the real MinigameService and
-- MinigameClient (tests/lib/MinigameRig), paintball's Spec, Table and ClientGame from the registries, and
-- paintball's own remotes beside them (tests/lib/PaintballRig). FROZEN with the contract: no lane edits this
-- file. Each case holds whatever the stubs become: the seams it proves are the ones the lanes share.
-- Interface: return function(t) (the spec shape)
local Arena = require("@shared/Minigames/Paintball/Arena")
local Clock = require("@shared/Minigames/Paintball/Clock")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Wire = require("@shared/Minigames/Paintball/Wire")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local BufferCodec = require("@shared/Util/BufferCodec")
local PaintballClient = require("@client/Minigames/Paintball/PaintballClient")
local PaintballRig = require("@tests/lib/PaintballRig")
local Rig = require("@tests/lib/MinigameRig")

return function(t)
	t.test(
		"the arena's station and the pass desk's prompt stand on the baked site; the Table has its furniture and the Port",
		function()
			local wires = PaintballRig.new()
			Rig.play(function(w)
				PaintballRig.attach(wires, w)
				local st = w.svc.stations[Contract.STATION]
				t.truthy(st ~= nil and st.session ~= nil, "the arena's station has a Session")
				t.eq(st.session.rules.def.game, Contract.GAME)
				t.eq(st.session.rules.def.seats, Contract.Rules.slots)
				t.falsy(st.broken)
				local tbl = PaintballRig.table(w)
				t.truthy(tbl ~= nil and tbl.hw ~= nil, "the Table found the arena's model")
				t.eq(tbl.hw.Name, Arena.MODEL)
				t.truthy(tbl.service.port == wires.port, "the service took the Port it was handed")
				t.isType(wires.handlers["Paintball.Move"], "function")
				t.isType(wires.handlers["Paintball.Fire"], "function")
				-- the arena's place is the site's, moved to the arena_origin anchor
				local place = tbl.service.place
				local ox, oy, oz =
					AlleyLayout.toWorld(PaintballRig.PLACE, Arena.ORIGIN.x, Arena.ORIGIN.y, Arena.ORIGIN.d)
				t.deepEq({ place.x, place.y, place.z, place.yaw }, { ox, oy, oz, PaintballRig.PLACE.yaw })
				-- two prompts: the door's own, and the desk's, which is only a way in
				local door, desk = Rig.prompt(w, Contract.STATION), Rig.prompt(w, Contract.DESK)
				t.truthy(door ~= nil and desk ~= nil)
				t.eq(w.svc.stations[Contract.DESK].joins, Contract.STATION)
				t.eq(w.svc.stations[Contract.DESK].session, nil)
				local gx, gy, gz = Arena.toWorld(place, Arena.GATE.x, Arena.GATE.y + 3, Arena.GATE.z)
				local at = w.svc.stations[Contract.STATION].anchor
				t.near(at.X, gx, 1e-6)
				t.near(at.Y, gy, 1e-6)
				t.near(at.Z, gz, 1e-6)
				PaintballRig.run(wires, w, 0.5)
				t.eq(#w.got, 0, "nothing is said to a player who has pressed nothing")
			end, PaintballRig.opts(wires))
		end
	)

	t.test("a site without the arena's model: the Table is inert and binds no remote", function()
		local wires = PaintballRig.new()
		Rig.play(function(w)
			PaintballRig.attach(wires, w)
			local tbl = PaintballRig.table(w)
			t.truthy(tbl ~= nil)
			t.eq(tbl.hw, nil)
			t.eq(tbl.service.port, nil)
			t.eq(next(wires.handlers), nil, "no remote was listened on")
			Rig.press(w, Contract.STATION)
			PaintballRig.run(wires, w, 0.5)
			t.eq(w.client.active(), nil)
			t.truthy(Rig.last(w.got, "refused") ~= nil, "a join is refused with words")
		end, PaintballRig.opts(wires, { furnish = function() end }))
	end)

	t.test(
		"the stream: a pose the client fires reaches the service decoded and late; a snapshot it fires reaches the client",
		function()
			local wires = PaintballRig.new({ lag = 4 })
			Rig.play(function(w)
				PaintballRig.attach(wires, w)
				local service = PaintballRig.table(w).service
				local link = PaintballClient.link()
				t.truthy(link ~= nil, "the client finds paintball's remotes under ReplicatedStorage.Net")
				local snaps: { any } = {}
				local undo = (link :: PaintballClient.Link).listen("Paintball.Snap", function(payload: any)
					table.insert(snaps, { frame = w.frames, payload = payload })
				end)
				-- up: SEND_HZ poses a second for a second, every one carried
				local sent = 0
				for frame = 1, 60 do
					if frame % (60 // Clock.SEND_HZ) == 0 then
						sent += 1
						local rec = {
							t = Rig.SERVER_TIME + w.frames / 60,
							seq = sent,
							x = 1.5,
							y = 14,
							z = -20.25,
							yaw = 1,
							pitch = -0.5,
							bits = Wire.BIT.crouch,
						}
						(link :: PaintballClient.Link).send("Paintball.Move", BufferCodec.encode(Wire.Move, rec))
					end
					PaintballRig.frame(wires, w)
				end
				PaintballRig.run(wires, w, 0.2)
				t.eq(sent, Clock.SEND_HZ)
				local heard = wires.heard["Paintball.Move"]
				t.eq(#heard, sent, "every pose reached the service's handler, through Net")
				t.eq(heard[1].z, -20.25)
				t.eq(heard[sent].seq, sent)
				t.truthy(Wire.has(heard[1].bits, Wire.BIT.crouch), "the stance rides on the pose")
				t.near(heard[1].pitch, -0.5, 1e-4)
				-- down: a snapshot, as the service will send it, arrives `lag` frames later as the same bytes
				local bodies = { { id = 1, x = 3, y = 0, z = 4, yaw = 0, pitch = 0, crouch = 1, bits = Wire.BIT.safe } }
				local at = w.frames
				service.port.fire(w.player, "Paintball.Snap", Wire.encodeSnap(Rig.SERVER_TIME + 1, 7, 2, bodies))
				PaintballRig.run(wires, w, 0.2)
				t.eq(#snaps, 1)
				t.eq(
					snaps[1].frame - at,
					4 - 1,
					"it is there for the frame drawn `lag` frames after the step that sent it"
				)
				local time, seq, match, got = Wire.decodeSnap(snaps[1].payload)
				t.eq(time, Rig.SERVER_TIME + 1)
				t.eq(seq, 7)
				t.eq(match, 2)
				t.eq(got[1].crouch, 1)
				t.eq(#wires.got["Paintball.Snap"], 1)
				undo()
				-- a stub (another person) is sent its streams in stub.streams
				local bob = Rig.stub("Bob")
				service.port.fire(bob, "Splat", Wire.pack(Wire.Splat, {}))
				t.eq(#bob.streams.Splat, 1)
				-- and a stub's pose goes straight through Net to the service
				local rec = { t = 0, seq = 1, x = 0, y = 0, z = 0, yaw = 0, pitch = 0, bits = 0 }
				t.truthy(PaintballRig.send(wires, bob, "Paintball.Move", rec))
				t.eq(#wires.heard["Paintball.Move"], sent + 1)
				rec.x = 0 / 0
				t.deepEq({ PaintballRig.send(wires, bob, "Paintball.Move", rec) }, { false, "non-finite" })
				-- (Net says so in the log, once; a case fails on a logged warning, and this one was asked for)
				t.eq(#w.warnings, 1)
				table.clear(w.warnings)
			end, PaintballRig.opts(wires))
		end
	)

	t.test(
		"the audience: paintball_watch sent to a player who is not seated starts the show with the site's place; unwatch ends it",
		function()
			local wires = PaintballRig.new()
			Rig.play(function(w)
				PaintballRig.attach(wires, w)
				local service = PaintballRig.table(w).service
				t.eq(PaintballClient.show(), nil)
				local watch = {
					kind = "paintball_watch",
					match = 3,
					slots = { { id = 1, team = 1, name = "Ada", bot = false } },
					now = Rig.SERVER_TIME,
				}
				t.truthy(Wire.checkMessage(watch))
				service.ctx.send(w.player, watch)
				PaintballRig.run(wires, w, 0.3)
				t.eq(w.client.active(), nil, "the player is in no game")
				local show = PaintballClient.show() :: PaintballClient.Show
				t.truthy(show ~= nil, "the show is on")
				t.eq(show.match, 3)
				t.deepEq(show.place, PaintballRig.PLACE)
				service.ctx.send(w.player, { kind = "paintball_unwatch" })
				PaintballRig.run(wires, w, 0.3)
				t.eq(PaintballClient.show(), nil)
			end, PaintballRig.opts(wires))
		end
	)
end
