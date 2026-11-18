--!strict
-- tests/isolated/whack_a_mole_client.luau: cases for tests/unit/whack_client.spec.luau, run in their own Lune
-- process (tests/lib/Isolated) because they install the fake engine.
-- Whack-a-mole played through all of its glue at once on tests/lib/MinigameRig: the real MinigameService with
-- the game's Table, the real MinigameClient with MinigameUI, the game's Controller and Cabinet, the fake lagged
-- network with the real Net's schema and rate limit between them, and the cabinet's moving parts as fake parts
-- under the names the bake gives them (Layout.NAMES; tests/unit/whack_bake.spec.luau holds the bake to them).
-- The player's hands are real key, mouse, gamepad and touch events, aimed from what this screen shows (the
-- moles as Cabinet draws them, through the camera the game set); other people are PlayerLike stubs.
-- Interface: return function(t) (the spec shape)
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Layout = require("@shared/Minigames/WhackAMole/Layout")
local Round = require("@shared/Minigames/WhackAMole/Round")
local Cabinet = require("@client/Minigames/WhackAMole/Cabinet")
local Controller = require("@client/Minigames/WhackAMole/Controller")
local MinigameSounds = require("@client/Minigames/MinigameSounds")
local FakeEngine = require("@tests/lib/FakeEngine")
local Rig = require("@tests/lib/MinigameRig")
local roblox = require("@lune/roblox")

local SITE = "bowling_alley"
local ID = "whack_a_mole_1"
local Key = roblox.Enum.KeyCode
local N = Layout.NAMES
local KEYS = { Key.One, Key.Two, Key.Three, Key.Four, Key.Five }
local PADS = { Key.DPadLeft, Key.DPadUp, Key.DPadRight, Key.ButtonL1, Key.ButtonR1 }

-- the cabinet frame as world CFrames, as the bake places the parts
local function at(place: any, u: number, v: number, w: number): any
	local X, Y, D = Layout.toSite(u, v, w)
	return roblox.CFrame.new(AlleyLayout.toWorld(place, X, Y, D))
end

local function furnish(roots: { [string]: any }, places: { [string]: any })
	Cabinet.reset()
	Controller.current = nil
	table.clear(MinigameSounds.counts())
	local place = places[SITE]
	local room = FakeEngine.new("Folder", "GamesRoom")
	room.Parent = roots[SITE]
	local model = FakeEngine.model(N.model, at(place, 0, Layout.DECK.top, 0), room)
	for i, h in Layout.HOLES do
		local m = FakeEngine.model(`{N.mole}{i}`, at(place, h[1], 0, h[2]), model)
		FakeEngine.part("Head", at(place, h[1], Layout.MOLE.headV, h[2]), m)
	end
	local M = Layout.MALLET
	local mallet = FakeEngine.model(N.mallet, at(place, M.rest[1], M.rest[2], M.rest[3]), model)
	FakeEngine.part("Head", at(place, M.rest[1], M.rest[2] + M.headAt, M.rest[3]), mallet)
	for _, name in { N.score, N.time, N.status } do
		local part = FakeEngine.part(name, at(place, 0, 5, 1), model)
		local gui = FakeEngine.new("SurfaceGui", N.display)
		gui.Parent = part
		local label = FakeEngine.new("TextLabel", N.value)
		label.Text = ""
		label.Parent = gui
	end
end

local function opts(more: { [string]: any }?): Rig.Opts
	local X, _, D = Layout.toSite(Layout.STAND.u, 0, Layout.STAND.w)
	local o: any = { furnish = furnish, stand = { site = SITE, x = X, y = 3, d = D } }
	for k, v in more or {} do
		o[k] = v
	end
	return o
end

local function cabModel(w: Rig.World): any
	return w.roots[SITE]:FindFirstChild("GamesRoom"):FindFirstChild(N.model)
end

local function window(w: Rig.World, name: string): string
	return cabModel(w):FindFirstChild(name):FindFirstChild(N.display):FindFirstChild(N.value).Text
end

local function moleY(w: Rig.World, hole: number): number
	return cabModel(w):FindFirstChild(`{N.mole}{hole}`):GetPivot().Position.Y
end

local function tbl(w: Rig.World): any
	return w.svc.stations[ID].tbl
end

-- a mole on this screen that can be hit now and has been up `after` seconds, or nil
local function upNow(cab: any, after: number): number?
	local t = Cabinet.roundTime(cab)
	if t == nil then
		return nil
	end
	for hole = 1, Round.HOLES do
		if Cabinet.hittable(cab, hole, t) and Cabinet.hittable(cab, hole, t - after) then
			return hole
		end
	end
	return nil
end

-- where a mole's head is on the screen now
local function onScreen(cab: any, hole: number): (number, number)
	local h = Layout.HOLES[hole]
	local c = Cabinet.cframe(cab, h[1], Layout.MOLE.headV + Layout.MOLE.pop * Cabinet.heightOf(cab, hole), h[2])
	local p = workspace.CurrentCamera:WorldToViewportPoint(c.Position)
	return p.X, p.Y
end

local function click(x: number, y: number)
	local Kind = roblox.Enum.UserInputType
	FakeEngine.input("began", { UserInputType = Kind.MouseButton1, Position = roblox.Vector3.new(x, y, 0) })
	FakeEngine.input("ended", { UserInputType = Kind.MouseButton1, Position = roblox.Vector3.new(x, y, 0) })
end

local function press(code: any)
	Rig.key(code, true)
	Rig.key(code, false)
end

-- the player plays a whole round, striking every mole it sees `after` seconds into its rise with `hit(hole)`
local function play(w: Rig.World, after: number, hit: (hole: number) -> ())
	local struck: { [number]: boolean } = {}
	Rig.untilTrue(w, Round.READY + Round.SECONDS + 3, function(): boolean
		local c = Controller.current
		if c then
			local hole = upNow(c.cab, after)
			local t = Cabinet.roundTime(c.cab)
			if hole and t then
				local list = c.cab.byHole[hole]
				local r = list[#list]
				if r and not struck[r.id] then
					struck[r.id] = true
					hit(hole)
				end
			end
		end
		return w.svc:sessionOf(ID).phase == "done"
	end)
end

return function(t: any)
	t.test(
		"a whole round on the keys: the camera over the deck, the moles and windows live, the server's score",
		function()
			Rig.play(function(w: Rig.World)
				Rig.press(w, ID)
				Rig.run(w, 0.3)
				local c = Controller.current
				t.truthy(c, "the controller is open")
				t.truthy(w.held, "the camera is the game's")
				t.eq(w.controls[#w.controls], false, "the legs are the game's")
				t.eq(window(w, N.time), "45", "the count-in shows the whole round")
				t.truthy(string.find(window(w, N.status), "READY", 1, true))
				-- a key in the count-in sends nothing
				press(Key.One)
				Rig.run(w, 0.1)
				t.eq(Rig.count(w.sent, "whack"), 0, "nothing before GO")
				-- the camera frames the deck: every hole's middle is on the screen
				Rig.run(w, 0.5)
				local cam = workspace.CurrentCamera
				for hole = 1, 5 do
					local h = Layout.HOLES[hole]
					local p, vis = cam:WorldToViewportPoint(Cabinet.cframe(c.cab, h[1], Layout.DECK.top, h[2]).Position)
					t.truthy(
						vis and p.X > 0 and p.X < cam.ViewportSize.X and p.Y > 0 and p.Y < cam.ViewportSize.Y,
						`hole {hole}`
					)
				end
				-- a mole rises on this screen: its part goes up by the pop
				local rose = false
				local y0 = {}
				for hole = 1, 5 do
					y0[hole] = moleY(w, hole)
				end
				play(w, 0.12, function(hole: number)
					press(KEYS[hole])
					rose = rose or moleY(w, hole) > y0[hole] + Layout.MOLE.pop * 0.5
				end)
				t.truthy(rose, "the mole's part rose")
				local r = tbl(w):round()
				t.truthy(r.hits >= 30, `{r.hits} hits`)
				t.eq(r.misses, 0, "every key was struck at a mole the server agrees was up")
				t.eq(r.score, r.hits * Round.HIT)
				Rig.run(w, 0.3)
				t.eq(window(w, N.score), string.format("%03d", r.score), "the SCORE window")
				t.eq(window(w, N.time), "00")
				t.eq(window(w, N.status), "TIME!")
				t.truthy(Rig.has(Rig.texts(w.gui), `{r.score} points`), Rig.screen(w))
				t.truthy(Rig.has(Rig.texts(w.gui), "Play again"))
				t.truthy((MinigameSounds.counts()["whack_a_mole.bonk"] or 0) >= r.hits, "a bonk for each hit")
				t.truthy((MinigameSounds.counts()["whack_a_mole.pop"] or 0) > 0)
				-- every mole is down again
				for hole = 1, 5 do
					t.near(moleY(w, hole), y0[hole], 1e-6)
				end
				-- play again, then leave: everything given back
				Rig.click(w, "Play again")
				Rig.run(w, 0.5)
				t.eq(w.svc:sessionOf(ID).phase, "playing")
				Rig.key(Key.Q, true)
				Rig.run(w, 0.3)
				t.eq(Controller.current, nil)
				t.falsy(w.held)
				t.eq(w.controls[#w.controls], true)
			end, opts())
		end
	)

	t.test(
		"mouse and touch: a click on a raised mole hits it, on an empty hole misses, off the deck does nothing",
		function()
			Rig.play(function(w: Rig.World)
				Rig.press(w, ID)
				Rig.run(w, 0.3)
				local c = Controller.current
				Rig.untilTrue(w, Round.READY + 3, function(): boolean
					return upNow(c.cab, 0.1) ~= nil
				end)
				local hole = upNow(c.cab, 0.1) :: number
				click(onScreen(c.cab, hole))
				Rig.run(w, 0.3)
				t.eq(Rig.count(w.sent, "whack"), 1)
				t.eq((Rig.last(w.sent, "whack") :: any).args[1], hole, "the mole under the pointer")
				t.eq(tbl(w):round().hits, 1)
				-- an empty hole: its mouth on the deck
				local empty = 1
				while Cabinet.heightOf(c.cab, empty) > 0 do
					empty += 1
				end
				local h = Layout.HOLES[empty]
				local p = workspace.CurrentCamera:WorldToViewportPoint(
					Cabinet.cframe(c.cab, h[1], Layout.DECK.top, h[2]).Position
				)
				click(p.X, p.Y)
				Rig.run(w, 0.3)
				t.eq(Rig.count(w.sent, "whack"), 2)
				t.eq(tbl(w):round().misses, 1)
				-- the top corner of the screen (the sign, the wall): nothing is sent
				click(4, 4)
				Rig.run(w, 0.3)
				t.eq(Rig.count(w.sent, "whack"), 2)
				-- a tap is a click
				Rig.untilTrue(w, 3, function(): boolean
					return upNow(c.cab, 0.1) ~= nil
				end)
				local next = upNow(c.cab, 0.1) :: number
				local x, y = onScreen(c.cab, next)
				Rig.touch("f", "began", x, y)
				Rig.touch("f", "ended", x, y)
				Rig.run(w, 0.3)
				t.eq((Rig.last(w.sent, "whack") :: any).args[1], next)
				t.eq(tbl(w):round().hits, 2)
			end, opts())
		end
	)

	t.test("gamepad: the D-pad's left, up and right are the back row, the shoulders the front row", function()
		Rig.play(function(w: Rig.World)
			Rig.press(w, ID)
			Rig.run(w, Round.READY + 0.5)
			for hole, code in PADS do
				press(code)
				Rig.run(w, 0.15)
				t.eq((Rig.last(w.sent, "whack") :: any).args[1], hole)
			end
			press(Key.ButtonL2)
			Rig.run(w, 0.15)
			t.eq((Rig.last(w.sent, "whack") :: any).args[1], 4, "a trigger is its shoulder's hole")
		end, opts())
	end)

	t.test(
		"one mallet: mashing every key sends no more than one strike per MIN_GAP, and the wire drops none",
		function()
			Rig.play(function(w: Rig.World)
				Rig.press(w, ID)
				Rig.run(w, Round.READY + 0.5)
				for _ = 1, 120 do
					for _, code in KEYS do
						press(code)
					end
					Rig.frame(w)
				end
				local n = Rig.count(w.sent, "whack")
				t.truthy(n <= math.ceil(2 / Round.MIN_GAP) + 1, `{n} strikes in two seconds`)
				t.truthy(n >= 15)
				t.eq(#w.broken, 0)
			end, opts())
		end
	)

	t.test("a watcher: the moles and the windows move on this screen while a stub plays", function()
		Rig.play(function(w: Rig.World)
			local ann = Rig.stub("Ann")
			t.truthy(w.svc:join(ann, ID))
			local y0 = {}
			for hole = 1, 5 do
				y0[hole] = moleY(w, hole)
			end
			local rose = false
			Rig.untilTrue(w, Round.READY + 8, function(): boolean
				for hole = 1, 5 do
					rose = rose or moleY(w, hole) > y0[hole] + 0.3
				end
				return rose
			end)
			t.truthy(rose, "a mole rose on the watcher's screen")
			t.eq(Controller.current, nil, "nothing opened: only watching")
			t.truthy(w.svc:debug(ID, "miss"))
			Rig.run(w, 0.2)
			t.truthy(string.find(window(w, N.status), "MISS", 1, true), window(w, N.status))
			t.truthy(tonumber(window(w, N.time)) ~= nil)
		end, opts())
	end)
end
