--!strict
-- The pure parts of pinball's glue (the model's own specs are tests/unit/pinball_*.spec.luau of the model):
--   * Pinball/Wire: a snapshot of a replay crosses the wire as plain data (lists without gaps, records keyed by
--     strings) and comes back the same game: fed the same log afterwards, the copy and the original end on the
--     same tick, score and Replay.sum;
--   * Pinball/Cabinet: the machines stand where AlleyLayout puts them (the Spec's stations too); point() is
--     Layout.cabinetPoint set down at the machine; the camera shows the whole playfield, both flippers and the
--     plunger on every screen shape from 4:3 to a wide phone, from over the lockdown bar;
--   * Client Pinball/Hands: every device holds a button at once, a tap between two frames still lasts a tick,
--     the analogue plunger.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Bot = require("@shared/Minigames/Pinball/Bot")
local Cabinet = require("@shared/Minigames/Pinball/Cabinet")
local Games = require("@shared/Minigames/Games")
local InputLog = require("@shared/Minigames/Pinball/InputLog")
local Layout = require("@shared/Minigames/Pinball/Layout")
local Machine = require("@shared/Minigames/Pinball/Machine")
local Replay = require("@shared/Minigames/Pinball/Replay")
local Tables = require("@shared/Minigames/Pinball/Tables")
local Wire = require("@shared/Minigames/Pinball/Wire")
local Hands = require("@client/Minigames/Pinball/Hands")

-- is a value what a RemoteEvent carries faithfully? (tests/lib/MinigameRig.wire's rule)
local function plain(v: any, path: string): (boolean, string?)
	if type(v) ~= "table" then
		local k = type(v)
		return k == "number" or k == "string" or k == "boolean", path
	end
	local n = #v
	for k, x in v do
		if type(k) == "number" then
			if k < 1 or k > n or k % 1 ~= 0 then
				return false, `{path}: a list with a gap`
			end
		elseif type(k) ~= "string" or n > 0 then
			return false, `{path}: a list mixed with names`
		end
		local ok, why = plain(x, `{path}.{k}`)
		if not ok then
			return false, why
		end
	end
	return true
end

-- a game played by the computer player for `ticks`, recording its log in segments
local function played(id: string, ticks: number, seed: number): (any, { { number } })
	local r = Replay.new(id, seed, 2)
	local rec = Replay.recorder(r)
	local bot = Bot.new(1, seed)
	local segs: { { number } } = {}
	local tbl = Tables.need(id)
	for _ = 1, ticks do
		if Replay.over(r) then
			break
		end
		local seg = Replay.live(r, rec, Bot.step(bot, tbl, r.m))
		if seg then
			table.insert(segs, seg)
		end
	end
	return r, segs
end

return function(t)
	t.test("a snapshot is plain data and comes back the same game, which goes on exactly as the original", function()
		for _, id in Tables.IDS do
			-- the original and the server's replay of the same log
			local _, segs = played(id, 240 * 40, 17)
			local server = Replay.new(id, 17, 2)
			local half = #segs // 2
			for i = 1, half do
				Replay.follow(server, server.m.up, segs[i])
			end
			local plainSnap = Wire.snapshot(server)
			t.truthy(plain(plainSnap, "snap"))
			local copy = Wire.restore(plainSnap)
			t.truthy(copy ~= nil)
			t.eq(Replay.sum(copy :: any), Replay.sum(server))
			for i = half + 1, #segs do
				local a = Replay.follow(server, server.m.up, segs[i])
				local b = Replay.follow(copy :: any, (copy :: any).m.up, segs[i])
				t.eq(a, b)
			end
			t.eq((copy :: any).tick, server.tick, id)
			t.eq(Replay.sum(copy :: any), Replay.sum(server), id)
			t.deepEq((copy :: any).m.scores, server.m.scores)
		end
		-- a table that is neither a list nor a record survives too, and a stranger is not a snapshot
		local odd = { [1] = "a", [3] = "c", name = "x", [true :: any] = 1 }
		local back = Wire.decode(Wire.encode(odd))
		t.eq(back[1], "a")
		t.eq(back[3], "c")
		t.eq(back.name, "x")
		t.truthy(plain(Wire.encode(odd), "odd"))
		t.eq(Wire.restore({ id = "pinball_nowhere", m = {}, tick = 0 }), nil)
		t.eq(Wire.restore("snap"), nil)
	end)

	t.test("the log a live machine cuts always fits one message and unpacks to itself", function()
		local _, segs = played("pinball_space", 240 * 30, 5)
		t.truthy(#segs > 100)
		for _, seg in segs do
			local a, b, packed = InputLog.pack(seg)
			t.truthy(#packed <= InputLog.WIRE_CHARS)
			t.deepEq(InputLog.unpack(a, b, packed), seg)
		end
	end)

	t.test("the machines stand where the floor plan puts them; the stations are the Spec's, one per machine", function()
		local stations = {}
		for _, st in Games.stations({ bowling_alley = { x = 0, z = 0, floorY = 0, yaw = 0 } }) do
			if st.game == "pinball" then
				table.insert(stations, st)
			end
		end
		t.eq(#stations, #AlleyLayout.PINBALLS)
		for i, st in stations do
			local x, d = Cabinet.at(i)
			t.eq(x, AlleyLayout.PINBALLS[i].x)
			t.eq(d, AlleyLayout.PINBALL_D)
			t.eq(st.x, x)
			t.eq(st.variant, AlleyLayout.PINBALLS[i].theme)
			t.eq(st.label, Tables.need(Tables.forVariant(st.variant) :: string).title)
			-- the prompt stands in front of the cabinet, within reach of where the player stands
			local sx, sd = Cabinet.stance(i)
			t.truthy(math.abs(st.d - sd) < 3 and math.abs(st.x - sx) < 1)
			-- the player faces the machine (-D), so the playfield's right (x up to WIDTH) is on the alley's -X side
			local leftX = Cabinet.point(i, 0, 1, 0)
			local rightX = Cabinet.point(i, Layout.WIDTH, 1, 0)
			t.truthy(rightX < leftX, "the shooter lane is on the player's right")
			-- point() is Layout.cabinetPoint at the machine
			local across, up, along = Layout.cabinetPoint(0.3, 2.1, 0.05)
			local X, Y, D = Cabinet.point(i, 0.3, 2.1, 0.05)
			t.near(X, x - across, 1e-9)
			t.near(Y, Cabinet.PF_Y + up, 1e-9)
			t.near(D, d + Cabinet.PF_D - along, 1e-9)
		end
	end)

	t.test(
		"the camera: over the lockdown bar, the whole playfield, both flippers and the plunger in the picture on any screen",
		function()
			local tbl = Tables.need("pinball_rodent")
			local c = tbl.c
			for _, aspect in { 4 / 3, 16 / 10, 16 / 9, 19.5 / 9 } do
				local v = Cabinet.camera(2, aspect)
				local ex, ey, ez = v.eye[1], v.eye[2], v.eye[3]
				local fx, fy, fz = v.target[1] - ex, v.target[2] - ey, v.target[3] - ez
				local n = math.sqrt(fx * fx + fy * fy + fz * fz)
				fx, fy, fz = fx / n, fy / n, fz / n
				-- right = forward x up(0,1,0) (in X, Y, D the camera looks toward -D: its right is +X)
				local half = math.rad(v.fov / 2)
				local function visible(x: number, y: number, h: number): boolean
					local X, Y, D = Cabinet.point(2, x, y, h)
					local px, py, pz = X - ex, Y - ey, D - ez
					local depth = px * fx + py * fy + pz * fz
					-- up in the picture: the component along the camera's up (perpendicular to forward, in the X=0 plane)
					local ux, uy, uz = 0, fz * fz + fx * fx, -fy * fz
					local un = math.sqrt(uy * uy + uz * uz)
					uy, uz = uy / un, uz / un
					local upward = py * uy + pz * uz + px * ux
					local side = px
					return depth > 0
						and math.abs(upward) / depth <= math.tan(half) + 1e-6
						and math.abs(side) / depth <= math.tan(half) * aspect + 1e-6
				end
				for _, corner in
					{ { 0, 0 }, { Layout.WIDTH, 0 }, { 0, Layout.LENGTH }, { Layout.WIDTH, Layout.LENGTH } }
				do
					t.truthy(visible(corner[1], corner[2], 0), `corner {corner[1]}, {corner[2]} at {aspect}`)
				end
				for i = 1, c.nFlip do
					t.truthy(visible(c.fpx[i], c.fpy[i], 0), `flipper {i}`)
				end
				t.truthy(visible(tbl.def.plunger.x, tbl.def.plunger.y, 0), "the plunger's ball")
				-- the eye is above and in front of the lockdown bar, a person's height off the floor
				local _, pd = Cabinet.at(2)
				t.truthy(ez > pd + Cabinet.BODY.front, "in front of the cabinet")
				t.truthy(ey > 4.4 and ey < 5.6, `eye height {ey}`)
				t.truthy(v.fov > 40 and v.fov < 80, `field of view {v.fov}`)
			end
		end
	)

	t.test(
		"the hands: any device holds a button, a tap between two frames lasts one tick, the plunger by hand",
		function()
			local BTN = Machine.BTN
			local h = Hands.new()
			Hands.press(h, "LeftShift", BTN.LEFT)
			Hands.press(h, "finger", BTN.LEFT)
			Hands.release(h, "LeftShift", BTN.LEFT)
			t.eq(bit32.band(Hands.buttons(h), BTN.LEFT), BTN.LEFT, "the finger still holds it")
			Hands.release(h, "finger", BTN.LEFT)
			t.eq(Hands.buttons(h), 0)
			-- a tap: down and up before the next tick is played
			Hands.press(h, "D", BTN.RIGHT)
			Hands.release(h, "D", BTN.RIGHT)
			t.eq(Hands.buttons(h), BTN.RIGHT, "the tap is played for one tick")
			t.eq(Hands.buttons(h), 0, "and only one")
			-- the analogue plunger: how far the hand has pulled it
			Hands.pull(h, "stick", 0.5)
			t.eq(Machine.pullOf(Hands.buttons(h)), 16)
			Hands.pull(h, "strip", 1)
			t.eq(Machine.pullOf(Hands.buttons(h)), Machine.PULL_LEVELS)
			Hands.pull(h, "strip", nil)
			Hands.pull(h, "stick", 0)
			t.eq(Hands.buttons(h), 0, "let go: the rod flies")
			-- every key on the checklist (PIN-C1, C2) is a button
			for _, key in
				{ "LeftShift", "A", "Left", "RightShift", "D", "Right", "Space", "S", "Down", "Z", "X", "W", "Up" }
			do
				t.truthy(Hands.KEYS[key] ~= nil, key)
			end
			for _, b in { "ButtonL1", "ButtonL2", "ButtonR1", "ButtonR2", "ButtonA" } do
				t.truthy(Hands.PAD[b] ~= nil, b)
			end
		end
	)
end
