--!strict
-- The paintball client's two headless cores (src/client/Minigames/Paintball/ShowCore and SeatCore) under plain
-- Lune: the player's actions and the server's messages in, what is sent and what is drawn out. No engine here
-- (tests/isolated/paintball_client.luau plays the same client through the framework on the fake engine); the
-- bench, its small building and the server's messages are tests/isolated/paintball_client_kit.luau. Every
-- message a case hands the client passes Wire.checkMessage, every stream buffer is made by Wire's own encoders,
-- and every click the client sends is judged here the way the contract says a server judges it.
local Kit = require("@tests/isolated/paintball_client_kit")
local Ballistics = require("@shared/Paintball/Ballistics")
local Magazine = require("@shared/Paintball/Magazine")
local Arena = require("@shared/Minigames/Paintball/Arena")
local Body = require("@shared/Minigames/Paintball/Body")
local Clock = require("@shared/Minigames/Paintball/Clock")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Hit = require("@shared/Minigames/Paintball/Hit")
local Wire = require("@shared/Minigames/Paintball/Wire")
local Hud = require("@client/Minigames/Paintball/Hud")
local Marker = require("@client/Minigames/Paintball/Marker")
local Tuning = require("@client/Minigames/Paintball/Tuning")

local R = Contract.Rules
local F = Contract.FEEL
local M = Contract.MARGIN
local BIT = Wire.BIT
local DT = Kit.DT

local function press(b: Kit.Bench)
	b.seat:input("fire", true)
	b.seat:input("fire", false)
end

-- The server's magazine, judged at each click's own stamp (Clock.stamp's m is ft for a click that is not late).
local function serverAccepts(fires: { { [string]: number } }, feel: Contract.Feel?): (boolean, number)
	local f = feel or F
	local mag = Magazine.new(R.magazine, f.fireInterval, f.reloadSecs)
	for i, rec in fires do
		if not Magazine.fire(mag, rec.ft) then
			return false, i
		end
	end
	return true, 0
end

return function(t)
	t.test("the tuning table: one table, every entry a number, a switch or a touch button", function()
		local n = 0
		for key, value in Tuning :: { [string]: any } do
			if key ~= "T" then
				n += 1
				local kind = type(value)
				t.truthy(kind == "number" or kind == "boolean" or kind == "table", key)
				if kind == "table" then
					t.eq(#value, 3, `{key} is a touch button: x, y, size`)
				end
			end
		end
		t.truthy(n >= 50, "the feel is in the table, not scattered")
		-- the dip is the only thing between the eye and Body.eye, and it can never lift a crouched eye over a rail
		t.truthy(Tuning.landDipMax < 1)
		t.truthy(Tuning.muzzleBlend < 0.2, "the drawn ball is on the true line within a fifth of a second")
	end)

	t.test("touch: the buttons are on the screen, clear of each other and of the stock jump button", function()
		-- the stock jump button (the PlayerModule's TouchJump): 70 px on a small screen, 120 on a large one
		for _, screen in
			{
				{ name = "a phone", w = 844, h = 390, jump = { 844 - 95, 390 - 90, 70 } },
				{ name = "a small phone", w = 667, h = 375, jump = { 667 - 95, 375 - 90, 70 } },
				{ name = "a tablet", w = 1180, h = 820, jump = { 1180 - 170, 820 - 210, 120 } },
			}
		do
			local rects: { { any } } = { { "the jump button", screen.jump[1], screen.jump[2], screen.jump[3] } }
			for _, key in { "touchFire", "touchFireLeft", "touchReload", "touchCrouch", "touchScores" } do
				local spec = (Tuning :: any)[key] :: { number }
				local x, y = screen.w * spec[1] - spec[3] / 2, screen.h * spec[2] - spec[3] / 2
				t.truthy(
					x >= 0 and y >= 0 and x + spec[3] <= screen.w and y + spec[3] <= screen.h,
					`{key} is on {screen.name}`
				)
				table.insert(rects, { key, x, y, spec[3] })
			end
			for i = 1, #rects do
				for j = i + 1, #rects do
					local a, b = rects[i], rects[j]
					local apart = a[2] + a[4] <= b[2]
						or b[2] + b[4] <= a[2]
						or a[3] + a[4] <= b[3]
						or b[3] + b[4] <= a[3]
					t.truthy(apart, `{a[1]} and {b[1]} do not overlap on {screen.name}`)
				end
			end
			-- FIRE is under the right thumb, SCORES is clear of the clock in the middle and the feed on the right
			t.truthy(Tuning.touchFire[1] > 0.6 and Tuning.touchFireLeft[1] < 0.3)
			local scores = Tuning.touchScores
			t.truthy(screen.w * scores[1] + scores[3] / 2 <= screen.w / 2 - 130, "SCORES is left of the clock")
		end
	end)

	t.test(
		"the HUD on every screen, a small phone to 4K: every piece on the screen, none on another or under a thumb",
		function()
			local function apart(a: Hud.Rect, b: Hud.Rect): boolean
				return a.x + a.w <= b.x + 1e-6
					or b.x + b.w <= a.x + 1e-6
					or a.y + a.h <= b.y + 1e-6
					or b.y + b.h <= a.y + 1e-6
			end
			local screens: { { any } } = {
				-- name, wide, tall, touch (a phone's HUD has the height left under Roblox's top bar)
				{ "an old small phone", 568, 320, true },
				{ "a small phone", 667, 375, true },
				{ "a small phone under the top bar", 667, 339, true },
				{ "a phone", 844, 390, true },
				{ "a phone under the top bar", 844, 332, true },
				{ "a big phone", 932, 430, true },
				{ "a small tablet", 1024, 768, true },
				{ "a tablet", 1180, 820, true },
				{ "a window dragged small", 800, 600, false },
				{ "a small laptop", 1280, 720, false },
				{ "a laptop", 1366, 768, false },
				{ "a laptop with a touch screen", 1366, 768, true },
				{ "a monitor", 1920, 1080, false },
				{ "a wide monitor", 2560, 1080, false },
				{ "4K", 3840, 2160, false },
			}
			for _, screen in screens do
				local name, vw, vh, touch = screen[1], screen[2], screen[3], screen[4]
				local lay = Hud.layout(vw, vh, touch, Tuning, 16)
				local r = lay.rects
				t.truthy(lay.scale >= Tuning.hudSmallest, `{name}: never smaller than words can be read`)
				t.truthy(20 * lay.scale >= 13.9, `{name}: a line of the feed is {20 * lay.scale} px tall`)
				t.truthy(lay.aim >= 1, `{name}: the crosshair is never scaled down`)
				-- on the screen, all of it
				for key, rect in r do
					t.truthy(
						rect.x >= -1e-6
							and rect.y >= -1e-6
							and rect.x + rect.w <= vw + 1e-6
							and rect.y + rect.h <= vh + 1e-6,
						`{name}: {key} is on the screen ({rect.x}, {rect.y}, {rect.w} x {rect.h})`
					)
				end
				-- what is up while playing: none on another, none under a thumb (or the stock jump button)
				local playing = { "Top", "Feed", "Pips", "Status", "Phase" }
				local thumbs: { [string]: Hud.Rect } = {}
				if touch then
					for _, key in { "FireRight", "FireLeft", "Reload", "Crouch", "Scores" } do
						t.truthy(r[key] ~= nil, `{name}: {key}`)
						thumbs[key] = r[key]
					end
					local small = math.min(vw, vh) <= 500
					local size = if small then 70 else 120
					thumbs.Jump = if small
						then { x = vw - 95, y = vh - 90, w = size, h = size }
						else { x = vw - 170, y = vh - 210, w = size, h = size }
				end
				for i, a in playing do
					for j = i + 1, #playing do
						t.truthy(apart(r[a], r[playing[j]]), `{name}: {a} and {playing[j]} do not overlap`)
					end
					for key, thumb in thumbs do
						t.truthy(apart(r[a], thumb), `{name}: {a} is not under {key}`)
					end
				end
				-- the briefing's line is clear of the top bar, the pips and every button
				t.truthy(apart(r.Phase, r.Top), `{name}: the briefing's line is under the top bar`)
				t.truthy(apart(r.Phase, r.Pips))
				for key, thumb in thumbs do
					t.truthy(apart(r.Phase, thumb), `{name}: the briefing's line is not under {key}`)
				end
				-- the crosshair's own space: nothing of the HUD within a sixteenth of the screen's height of the middle
				local keep = vh * 0.06
				local middle = { x = vw / 2 - keep, y = vh / 2 - keep, w = 2 * keep, h = 2 * keep }
				for _, key in { "Top", "Feed", "Pips", "Status", "Phase" } do
					t.truthy(apart(r[key], middle), `{name}: {key} keeps out of the middle of the view`)
				end
				-- the end: every line of the card on the screen (checked above), the awards beside or under it
				t.truthy(lay.card > 0.35, `{name}: the end card is fitted at {lay.card}`)
				t.truthy(lay.awards > 0, `{name}: there is room for the bulletin's awards`)
				t.truthy(apart(r.Awards, r.Card), `{name}: the awards are not on the end card`)
				-- the scoreboard and the controls card fit
				t.truthy(lay.board > 0.6 and lay.help > 0.6, `{name}: board {lay.board}, help {lay.help}`)
			end
			-- the screen it was drawn for is as it was drawn: nothing moved on a monitor
			local desk = Hud.layout(1920, 1080, false, Tuning, 16)
			t.eq(desk.scale, 1)
			t.eq(desk.feedY, 8, "the feed beside the top bar")
			t.eq(desk.statusY, 70)
			t.eq(desk.statusW, 560)
			t.eq(desk.card, 1, "the framework's card as the framework draws it")
			t.eq(desk.help, 1)
			t.eq(desk.awards, 1)
			t.eq(desk.rects.Awards.x, 12)
			t.eq(Hud.layout(3840, 2160, false).scale, 2, "4K is not a HUD for ants")
			-- a phone: one size for all of it; the feed under the top bar; the status clear of the thumbs
			local phone = Hud.layout(667, 375, true, Tuning, 16)
			t.near(phone.scale, 667 / Tuning.hudFitWide, 1e-9)
			t.truthy(phone.feedY > 8, "the feed has dropped under the top bar")
			t.truthy(phone.card < 1 and phone.help < 1)
			-- a phone held upright is not what this is drawn for, but nothing leaves the screen
			local up = Hud.layout(390, 844, true, Tuning, 16)
			for key, rect in up.rects do
				t.truthy(
					rect.x >= -1e-6
						and rect.x + rect.w <= 390 + 1e-6
						and rect.y >= -1e-6
						and rect.y + rect.h <= 844 + 1e-6,
					`upright: {key} is on the screen`
				)
			end
			t.truthy(up.board < 1, "the scoreboard is fitted to the narrow screen")
		end
	)

	t.test("one click, one ball: Wire.Fire with both stamps, the eye as origin, the unit look; and a pop", function()
		local b = Kit.playing()
		local at = b.now()
		b.seat:input("fire", true)
		local fires = Kit.fires(b)
		t.eq(#fires, 1, "it left in the frame of the click")
		local rec = fires[1]
		t.eq(rec.shot, 1)
		t.eq(rec.ft, at, "ft is the shared clock at the click")
		t.near(rec.ft - rec.vt, Clock.INTERP_SECS, 1e-9, "vt is the view time on screen (no snapshot yet: no lag)")
		t.near(rec.ox, 0, 1e-6)
		t.near(rec.oy, Body.STAND_EYE, 1e-6, "the ball leaves from the eye, not from the marker")
		t.near(rec.oz, 30, 1e-6)
		t.near(math.sqrt(rec.dx ^ 2 + rec.dy ^ 2 + rec.dz ^ 2), 1, 1e-6)
		t.near(rec.dz, -1, 1e-6)
		t.eq(Kit.cues(b, "paintball.fire"), 1)
		t.eq(#b.show.balls, 1, "and it is drawn at once")
		t.truthy(b.show.balls[1].own)
		t.eq(b.seat.mag.rounds, R.magazine - 1)
		-- a tap is one ball (the button held down fires on: the next case)
		b.seat:input("fire", false)
		Kit.run(b, 1)
		t.eq(#Kit.fires(b), 1)
	end)

	t.test("the predicted ball is the server's ball: the same curve from the numbers on the wire", function()
		local b = Kit.playing()
		b.pose.pitch = 0.2
		b.pose.yaw = 0.3
		Kit.frame(b)
		press(b)
		local rec = Kit.fires(b)[1]
		local ball = b.show.balls[1]
		-- the server: born at f = ft at the claimed origin, velocity = the unit direction x the feel's speed
		local len = math.sqrt(rec.dx ^ 2 + rec.dy ^ 2 + rec.dz ^ 2)
		local vx, vy, vz = rec.dx / len * F.ballSpeed, rec.dy / len * F.ballSpeed, rec.dz / len * F.ballSpeed
		local worst = 0
		for _ = 1, 20 do
			Kit.frame(b)
			if b.show.balls[1] ~= ball then
				break
			end
			local age = b.now() - rec.ft
			local x, y, z = Ballistics.position(rec.ox, rec.oy, rec.oz, vx, vy, vz, F.ballDrop, age)
			worst = math.max(worst, math.abs(ball.x - x), math.abs(ball.y - y), math.abs(ball.z - z))
		end
		t.truthy(ball.age > 0.2, "it flew")
		t.truthy(worst < 1e-6, `the two balls agree to a millionth of a stud (worst {worst})`)
		-- travel and slight drop (PB-1): 45 studs in 0.3 s, 0.9 studs low
		local z45, y45 =
			select(3, Ballistics.position(0, 0, 0, 0, 0, -F.ballSpeed, F.ballDrop, 0.3)),
			select(2, Ballistics.position(0, 0, 0, 0, 0, -F.ballSpeed, F.ballDrop, 0.3))
		t.near(z45, -45, 1e-9)
		t.near(y45, -0.882, 1e-9)
	end)

	t.test("the ball is drawn leaving the muzzle and is on the true line within Tuning.muzzleBlend", function()
		local b = Kit.bench()
		local seat = b.seat
		Kit.watch(b)
		Kit.state(b)
		Kit.place(b)
		Kit.frame(b, 2)
		-- (the bench's port has no muzzle: hand the show one directly, as the seat does)
		local ball = b.show:predict(9, b.now(), 0, 4.5, 30, 0, 0, -90, 0.8, -0.7, -1.5)
		t.near(ball.x, 0.8, 1e-9)
		t.near(ball.y, 3.8, 1e-9)
		Kit.frame(b)
		t.truthy(ball.x > 0 and ball.x < 0.8, "sliding onto the line")
		Kit.run(b, Tuning.muzzleBlend)
		t.near(ball.x, 0, 1e-9)
		t.near(ball.y, 4.5 - 0.5 * F.ballDrop * ball.age ^ 2, 1e-9)
		t.eq(seat.shot, 0)
	end)

	t.test("six clicks a second fire four balls, each one the server's magazine accepts", function()
		local b = Kit.playing()
		local start = b.now()
		for f = 0, 59 do
			if f % 10 == 0 then
				press(b)
			end
			Kit.frame(b)
		end
		local fires = Kit.fires(b)
		local inFirstSecond = 0
		for _, rec in fires do
			if rec.ft < start + 0.999 then
				inFirstSecond += 1
			end
		end
		t.eq(inFirstSecond, 4, "a press the fire interval objects to is held, not lost (three without the hold)")
		for i = 2, #fires do
			t.truthy(fires[i].ft - fires[i - 1].ft >= F.fireInterval - 1e-9, "never faster than the marker")
			t.truthy(fires[i].ft - fires[i - 1].ft < F.fireInterval + 2 * DT, "and the instant it may")
		end
		t.truthy(serverAccepts(fires))
	end)

	t.test("five shots, then the marker reloads by itself; a press on an empty marker is the dry click", function()
		local b = Kit.playing()
		local seat = b.seat
		for _ = 1, 5 do
			press(b)
			Kit.run(b, F.fireInterval + 0.02)
		end
		local fires = Kit.fires(b)
		t.eq(#fires, 5)
		t.eq(seat.mag.rounds, 0)
		t.near(
			seat.mag.reloadDoneAt :: number,
			fires[5].ft + F.reloadSecs,
			1e-9,
			"the reload began when the fifth left"
		)
		t.eq(Kit.cues(b, "paintball.reload"), 1, "the rattle")
		t.truthy((seat:reloading(b.now()) :: number) > 0)
		t.falsy(seat:ready(b.now()))
		-- a press now: dry, and nothing else
		press(b)
		Kit.frame(b)
		t.eq(#Kit.fires(b), 5)
		t.eq(seat.held, nil, "not held: the reload has more than MARGIN.click to run")
		t.eq(Kit.cues(b, "paintball.dry"), 1)
		-- mashing ticks, it does not buzz
		for _ = 1, 6 do
			press(b)
			Kit.frame(b)
		end
		t.truthy(Kit.cues(b, "paintball.dry") <= 2)
		-- a press in the last MARGIN.click of the reload is held and leaves the instant the magazine is full
		local done = seat.mag.reloadDoneAt :: number
		while b.now() < done - M.click + 0.03 do
			Kit.frame(b)
		end
		press(b)
		t.truthy(seat.held ~= nil, "held")
		Kit.run(b, 0.3)
		fires = Kit.fires(b)
		t.eq(#fires, 6)
		t.truthy(fires[6].ft >= done and fires[6].ft < done + 2 * DT)
		t.eq(seat.mag.rounds, R.magazine - 1)
		t.truthy(serverAccepts(fires), "the server's magazine agrees with every one")
	end)

	t.test("the trigger held down fires at the marker's rate: five balls, the reload, then on again", function()
		-- (found at the review: a held mouse button, R2 or finger on FIRE fired one ball and then nothing)
		local b = Kit.playing()
		local seat = b.seat
		seat:input("fire", true)
		Kit.run(b, 2)
		local fires = Kit.fires(b)
		t.eq(#fires, 5, "five balls in two seconds from a full magazine")
		for i = 2, #fires do
			t.truthy(fires[i].ft - fires[i - 1].ft >= F.fireInterval - 1e-9, "never faster than the marker")
			t.truthy(fires[i].ft - fires[i - 1].ft < F.fireInterval + 2 * DT, "and the instant it may")
		end
		t.truthy(seat.mag.reloadDoneAt ~= nil, "the reload follows by itself")
		t.eq(Kit.cues(b, "paintball.dry"), 0, "holding through the reload is not the dry click")
		-- still held when the reload is done: it fires on
		local done = seat.mag.reloadDoneAt :: number
		Kit.run(b, done - b.now() + 0.1)
		fires = Kit.fires(b)
		t.eq(#fires, 6)
		t.truthy(fires[6].ft >= done and fires[6].ft < done + 2 * DT)
		t.truthy(serverAccepts(fires), "the server's magazine agrees with every one")
		-- let go: nothing more
		seat:input("fire", false)
		Kit.run(b, 1)
		t.eq(#Kit.fires(b), 6)
		t.eq(seat.held, nil)
		-- the switch puts back "holding does not repeat"
		local tuning = table.clone(Tuning)
		tuning.holdRepeats = false
		local c = Kit.playing({ tuning = tuning })
		c.seat:input("fire", true)
		Kit.run(c, 2)
		t.eq(#Kit.fires(c), 1)
	end)

	t.test(
		"R reloads when not full: the verb with its stamp, the rattle, no fire meanwhile; a refusal undoes it",
		function()
			local b = Kit.playing()
			local seat = b.seat
			b.seat:input("reload", true)
			t.eq(#b.verbs, 0, "a full magazine: R does nothing and sends nothing")
			press(b)
			Kit.run(b, 0.3)
			local at = b.now()
			seat:input("reload", true)
			t.eq(#b.verbs, 1)
			t.eq(b.verbs[1].verb, "reload")
			t.eq(b.verbs[1].args[1], at)
			t.eq(Kit.cues(b, "paintball.reload"), 1)
			seat:input("reload", true)
			t.eq(#b.verbs, 1, "not twice")
			press(b)
			Kit.frame(b)
			t.eq(#Kit.fires(b), 1, "no firing while reloading")
			Kit.run(b, F.reloadSecs)
			t.eq(seat.mag.rounds, R.magazine)
			-- the server says the reload did not happen
			press(b)
			Kit.run(b, 0.3)
			seat:input("reload", true)
			t.truthy(seat.mag.reloadDoneAt ~= nil)
			seat:onRefused({ kind = "refused", verb = "reload", text = "Not now." })
			t.eq(seat.mag.reloadDoneAt, nil)
			t.eq(seat.mag.rounds, R.magazine - 1)
		end
	)

	t.test(
		"a click while sprinting ends the sprint and fires 0.15 s later; no sprint Move is stamped inside it",
		function()
			local b = Kit.playing()
			local seat = b.seat
			seat:input("sprint", true)
			Kit.run(b, 0.5)
			t.eq(seat.k, 1, "at full sprint")
			t.eq(seat:markerUp(b.now()), 0, "the marker is down")
			t.falsy(seat:ready(b.now()))
			local at = b.now()
			press(b)
			t.eq(seat.k, 0, "the press itself drops the ramp to 0")
			t.eq(#Kit.fires(b), 0, "held")
			Kit.run(b, 0.3)
			local fires = Kit.fires(b)
			t.eq(#fires, 1, "the click was not lost")
			t.truthy(fires[1].ft >= at + Body.SPRINT_FIRE_DELAY - 1e-9)
			t.truthy(fires[1].ft < at + Body.SPRINT_FIRE_DELAY + 2 * DT, "the first frame it may")
			-- the server's rule: no accepted Move with the sprint bit later than f - SPRINT_FIRE_DELAY + MARGIN.sprint
			local sprintMoves = 0
			for _, move in Kit.moves(b) do
				if Wire.has(move.bits, BIT.sprint) and move.t < fires[1].ft then
					sprintMoves += 1
					t.truthy(
						move.t <= fires[1].ft - Body.SPRINT_FIRE_DELAY,
						"the bit was cleared in the frame of the press"
					)
				end
			end
			t.truthy(sprintMoves >= 8, "the sprint was told to the server while it ran")
		end
	)

	t.test(
		"sprint accelerates over the ramp, widens the view, stops at once; standing still or crouched there is none",
		function()
			local b = Kit.playing()
			local seat = b.seat
			t.near(b.paces[#b.paces].scale :: number, 1, 1e-9)
			t.eq(b.paces[#b.paces].sprint, false, "the framework's own Shift is off: the ramp is paintball's")
			seat:input("sprint", true)
			Kit.frame(b, 6)
			local mid = b.paces[#b.paces].scale :: number
			t.truthy(mid > 1.05 and mid < F.sprintMult - 0.05, "ramping")
			t.truthy(b.fov > 0 and b.fov < Tuning.sprintFov)
			Kit.run(b, Body.SPRINT_RAMP_SECS)
			t.near(b.paces[#b.paces].scale :: number, F.sprintMult, 1e-9, "full sprint is the feel's multiple")
			t.near(b.fov, Tuning.sprintFov, 1e-9)
			seat:input("sprint", false)
			Kit.frame(b)
			t.near(b.paces[#b.paces].scale :: number, 1, 1e-9, "no ramp down")
			t.eq(b.fov, 0)
			-- the stick let go: no sprint, and the marker stays up
			seat:input("sprint", true)
			b.push = 0
			Kit.run(b, 0.4)
			t.eq(seat.k, 0)
			t.eq(seat:markerUp(b.now()), 1)
			-- crouching ends a sprint, and a crouching body does not sprint
			b.push = 1
			Kit.run(b, 0.4)
			t.eq(seat.k, 1)
			seat:input("crouch", true)
			t.eq(seat.k, 0, "at once")
			Kit.run(b, 0.4)
			t.eq(seat.k, 0)
			t.near(b.paces[#b.paces].scale :: number, 0.5, 1e-9, "crouched: half pace")
		end
	)

	t.test("crouch: the eye sinks to 0.6 of its height in crouchSecs, under the rail; standing it is over", function()
		local b = Kit.playing()
		local seat = b.seat
		t.eq(b.eye, 0, "standing: the stock eye, nothing moved")
		t.truthy(Body.eye(0) > Arena.RAIL_HEIGHT, "a standing eye sees over an atrium rail")
		seat:input("crouch", true)
		Kit.frame(b, 6)
		t.truthy(b.eye < -0.5 and b.eye > -1.5, "sinking smoothly, not snapping")
		Kit.run(b, F.crouchSecs)
		t.near(seat.c, 1, 1e-9)
		t.near(b.eye, Body.CROUCH_EYE - Body.STAND_EYE, 1e-9)
		t.truthy(Body.STAND_EYE + b.eye < Arena.RAIL_HEIGHT, "a crouched eye is under the rail")
		-- the ball leaves from the crouched eye, and the pose says so
		press(b)
		local rec = Kit.fires(b)[1]
		t.near(rec.oy, Body.CROUCH_EYE, 1e-6)
		local moves = Kit.moves(b)
		t.truthy(Wire.has(moves[#moves].bits, BIT.crouch))
		-- and back up as quickly: peeking over the rail is a tap
		seat:input("crouch", false)
		Kit.run(b, F.crouchSecs + 0.02)
		t.eq(seat.c, 0)
		t.eq(b.eye, 0)
		-- a faster crouch is the match's to say
		Kit.state(b, { feel = { crouchSecs = 0.1 } })
		seat:input("crouch", true)
		Kit.frame(b, 7)
		t.eq(seat.c, 1)
	end)

	t.test("landing dips the eye a little and it comes back; the dip never claims a ball's origin", function()
		local b = Kit.playing()
		b.pose.air = true
		b.pose.y = 2
		Kit.frame(b)
		for _ = 1, 10 do
			b.pose.y -= 0.2
			Kit.frame(b)
		end
		b.pose.air = false
		b.pose.y = 0
		Kit.frame(b)
		t.truthy(b.eye < -0.05 and b.eye >= -Tuning.landDipMax, `a dip ({b.eye})`)
		press(b)
		t.near(Kit.fires(b)[1].oy, Body.STAND_EYE, 1e-6, "the origin is Body.eye over the feet, dip or no dip")
		Kit.run(b, 0.8)
		t.truthy(b.eye > -0.01, "recovered")
	end)

	t.test("the gates: no ball is drawn that a contract-following server would refuse", function()
		-- the briefing: nothing until its end + MARGIN.gate, then the first frame
		local b = Kit.bench()
		Kit.watch(b)
		local ends = b.now() + 0.5
		Kit.state(b, { phase = "briefing", endsAt = ends })
		Kit.place(b, { at = b.now() + 0.2 })
		for _ = 1, 40 do
			local early = b.now() < ends
			press(b)
			Kit.frame(b)
			if early then
				t.eq(b.seat.held, nil, "a press in the briefing is dropped, not held")
			end
		end
		local fires = Kit.fires(b)
		t.truthy(#fires >= 1, "live by the clock, before the server's own word arrives")
		t.truthy(fires[1].ft >= ends + M.gate, `not before the briefing's end + the gate ({fires[1].ft - ends})`)
		t.truthy(fires[1].ft < ends + M.gate + 2 * DT)

		-- a briefing cut short (the owner's debug("end") at the playtest: the server goes live nine seconds
		-- before the end it announced): the server's word stands from when it is heard, and the marker is
		-- not left dead until the old briefing would have run out. (Found against the real service.)
		b = Kit.bench()
		Kit.watch(b)
		Kit.state(b, { phase = "briefing", endsAt = b.now() + 10 })
		Kit.place(b, { at = b.now() - 1 })
		Kit.run(b, 1)
		press(b)
		Kit.frame(b)
		t.eq(#Kit.fires(b), 0, "still the briefing")
		local heard = b.now()
		Kit.state(b, { phase = "live", endsAt = heard + R.matchSecs })
		t.truthy(b.seat:live(heard + M.gate), "live on the server's word")
		t.falsy(b.seat:live(heard), "less the gate")
		Kit.frame(b, 3)
		press(b)
		Kit.frame(b)
		t.eq(#Kit.fires(b), 1, "the click fires, nine seconds before the old briefing's end")
		t.eq(Kit.cues(b, "paintball.go"), 1, "and the horn sounded")

		-- protection: nothing until `at` + MARGIN.gate
		b = Kit.playing()
		local safe = b.now() + 0.4
		Kit.place(b, { at = safe })
		for _ = 1, 40 do
			press(b)
			Kit.frame(b)
		end
		fires = Kit.fires(b)
		t.truthy(#fires >= 1)
		t.truthy(fires[1].ft >= safe + M.gate)
		t.truthy(b.seat.note ~= "" or #fires > 0)

		-- the spawn rooms, both, and MARGIN.room round them
		for _, case in
			{
				{ x = -50, fires = false, inRoom = true, note = "No firing from a spawn room" }, -- inside your own
				-- outside the door, inside the margin: not in the room, and the words say so
				{ x = -44 + M.room - 0.1, fires = false, note = "Too close to a spawn room to fire" },
				{ x = -44 + M.room + 0.1, fires = true },
				-- beside the other team's
				{ x = 44 - M.room + 0.1, fires = false, note = "Too close to a spawn room to fire" },
				{ x = 44 - M.room - 0.1, fires = true },
			}
		do
			b = Kit.playing()
			Kit.place(b, { x = case.x, z = 0 })
			Kit.frame(b)
			t.eq(b.seat.inRoom, case.inRoom == true, `x = {case.x}: in your own room`)
			t.eq(b.seat.nearRoom, not case.fires, `x = {case.x}: too close to fire, known before the click`)
			press(b)
			Kit.frame(b)
			t.eq(#Kit.fires(b) == 1, case.fires, `x = {case.x}`)
			if not case.fires then
				t.eq(b.seat.note, case.note, "and the HUD says why, truly")
			end
		end
		t.truthy(Kit.playing().seat.inRoom == false)

		-- the end of the match: nothing from MARGIN.gate before endsAt
		b = Kit.bench()
		Kit.watch(b)
		local over = b.now() + 0.3
		Kit.state(b, { phase = "live", endsAt = over })
		Kit.place(b)
		for _ = 1, 60 do
			press(b)
			Kit.frame(b)
		end
		for _, rec in Kit.fires(b) do
			t.truthy(rec.ft < over - M.gate + 1e-9)
		end
		-- and nothing at all before the first placement (the body is still at the arena door)
		b = Kit.bench()
		Kit.watch(b)
		Kit.state(b)
		press(b)
		Kit.run(b, 0.5)
		t.eq(#Kit.fires(b), 0)
		t.eq(#Kit.moves(b), 0, "nor a pose")
	end)

	t.test("one press is held: a later one replaces it, and anything else in its way drops it", function()
		local b = Kit.playing()
		local seat = b.seat
		press(b)
		Kit.frame(b, 3)
		press(b)
		local first = seat.held
		t.truthy(first ~= nil)
		Kit.frame(b, 3)
		press(b)
		t.truthy(seat.held ~= first, "the later press took its place")
		Kit.run(b, 0.3)
		t.eq(#Kit.fires(b), 2, "one ball for the two held presses")
		-- held, and then tagged: dropped
		press(b)
		Kit.frame(b, 2)
		press(b)
		t.truthy(seat.held ~= nil)
		Kit.message(b, {
			kind = "paintball_tag",
			by = 2,
			id = 1,
			ball = 7,
			scores = { 0, 1 },
			tags = 1,
			outs = 1,
			at = b.now() + F.respawnSecs,
			x = 0,
			y = 3,
			z = 30,
		})
		t.eq(seat.held, nil)
		Kit.run(b, 0.5)
		t.eq(#Kit.fires(b), 2, "no ball from a tagged player")
	end)

	t.test("the pips do not roll back when an ack arrives with balls in flight", function()
		local b = Kit.playing()
		local seat = b.seat
		for _ = 1, 3 do
			press(b)
			Kit.run(b, F.fireInterval + 0.02)
		end
		t.eq(seat.mag.rounds, 2)
		-- the server's word on the FIRST click only now: its magazine stood at 4 after it
		Kit.message(b, { kind = "paintball_ack", shot = 1, ok = true, ball = 40, rounds = 4 })
		t.eq(seat.mag.rounds, 2, "4 as the server had it, minus the two balls sent since")
		Kit.message(b, { kind = "paintball_ack", shot = 2, ok = true, ball = 41, rounds = 3 })
		Kit.message(b, { kind = "paintball_ack", shot = 3, ok = true, ball = 42, rounds = 2 })
		t.eq(seat.mag.rounds, 2)
		-- the Extras of a later "state" are never applied again
		Kit.state(b, { rounds = 5, shot = 0 })
		t.eq(seat.mag.rounds, 2)
		-- a refused click gives the ball back, takes its picture away and says why
		Kit.run(b, 1)
		press(b)
		t.eq(seat.mag.rounds, 1)
		t.eq(#b.show.balls, 1)
		Kit.message(b, { kind = "paintball_ack", shot = 4, ok = false, why = "origin", rounds = 2 })
		t.eq(seat.mag.rounds, 2)
		t.eq(#b.show.balls, 0, "the refused ball is gone")
		t.eq(seat.note, Contract.textFor("origin"))
		-- a reload the server reports is taken over
		local at = b.now() + 1.2
		Kit.message(b, { kind = "paintball_ack", shot = 4, ok = true, rounds = 0, reloadAt = at })
		t.eq(seat.mag.rounds, 0)
		t.eq(seat.mag.reloadDoneAt, at)
	end)

	t.test(
		"an ack and a reload: R pressed after a click is not undone by that click's ack; a refused fifth ball is",
		function()
			local b = Kit.playing()
			local seat = b.seat
			press(b)
			Kit.run(b, 0.1)
			seat:input("reload", true)
			local done = seat.mag.reloadDoneAt
			t.truthy(done ~= nil)
			-- the ack of the click before the R: the server had not heard of the reload yet
			Kit.message(b, { kind = "paintball_ack", shot = 1, ok = true, ball = 3, rounds = 4 })
			t.eq(seat.mag.reloadDoneAt, done, "the reload runs on: no flicker, no second rattle")
			t.eq(Kit.cues(b, "paintball.reload"), 1)
			-- the server's own word on the reload moves its end
			Kit.message(b, { kind = "paintball_reload", id = 1, at = (done :: number) + 0.05 })
			t.eq(seat.mag.reloadDoneAt, (done :: number) + 0.05)
			t.eq(Kit.cues(b, "paintball.reload"), 1)
			Kit.run(b, F.reloadSecs + 0.2)
			t.eq(seat.mag.rounds, R.magazine)
			-- five balls; the server refuses the fifth: the automatic reload it began is not running
			for shot = 1, 5 do
				press(b)
				Kit.run(b, F.fireInterval + 0.02)
				if shot < 5 then
					Kit.message(
						b,
						{ kind = "paintball_ack", shot = shot + 1, ok = true, ball = shot, rounds = 5 - shot }
					)
				end
			end
			t.eq(seat.mag.rounds, 0)
			t.truthy(seat.mag.reloadDoneAt ~= nil)
			Kit.message(b, { kind = "paintball_ack", shot = 6, ok = false, why = "stale", rounds = 1 })
			t.eq(seat.mag.rounds, 1, "the ball is back")
			t.eq(seat.mag.reloadDoneAt, nil)
			-- a reload the server starts that the client did not predict rattles when it is told
			Kit.message(b, { kind = "paintball_reload", id = 1, at = b.now() + 1 })
			t.eq(Kit.cues(b, "paintball.reload"), 3)
		end
	)

	t.test("the first state after joining sets the magazine once (a late joiner into a running reload)", function()
		local b = Kit.bench()
		Kit.watch(b)
		local at = b.now() + 1
		Kit.state(b, { rounds = 0, reloadAt = at, shot = 12 })
		t.eq(b.seat.mag.rounds, 0)
		t.eq(b.seat.mag.reloadDoneAt, at)
		Kit.state(b, { rounds = 3 })
		t.eq(b.seat.mag.rounds, 0, "only once")
	end)

	t.test(
		"the pose stream: SEND_HZ a second, the real feet point, the look, the bits and the placement obeyed",
		function()
			local b = Kit.playing()
			local before = #Kit.moves(b)
			b.pose.x, b.pose.yaw, b.pose.pitch = 3, 0.5, -0.25
			Kit.run(b, 1)
			local moves = Kit.moves(b)
			t.truthy(math.abs(#moves - before - Clock.SEND_HZ) <= 1, `{#moves - before} poses in a second`)
			local last = moves[#moves]
			t.near(last.x, 3, 1e-6)
			t.near(last.z, 30, 1e-6)
			t.near(last.yaw, 0.5, 1e-3)
			t.near(last.pitch, -0.25, 1e-3)
			t.eq(last.place, 1)
			t.eq(last.bits, 0)
			for i = 2, #moves do
				t.truthy(moves[i].t > moves[i - 1].t, "each later than the last, on the shared clock")
				t.eq(moves[i].seq, moves[i - 1].seq + 1)
			end
			-- in a jump the feet point is off the floor and the air bit says so
			b.pose.y, b.pose.air = 1.5, true
			Kit.frame(b, 4)
			moves = Kit.moves(b)
			t.near(moves[#moves].y, 1.5, 1e-6)
			t.truthy(Wire.has(moves[#moves].bits, BIT.air))
		end
	)

	t.test("a click carries its pose, and a change of stance is told at once, not at the stream's next turn", function()
		local b = Kit.playing()
		-- a click: a Move with the click's own stamp goes up before the Fire
		Kit.frame(b, 2) -- (the last of them a frame in which no Move was due)
		local before = #Kit.moves(b)
		press(b)
		Kit.frame(b)
		local fire = Kit.fires(b)[1]
		local moves = Kit.moves(b)
		t.eq(#moves, before + 1, "one Move with the click")
		t.eq(moves[#moves].t, fire.ft, "stamped as the click is: the pose at the fire time is the pose it left from")
		t.near(moves[#moves].y + Body.STAND_EYE, fire.oy, 1e-6)
		for i = 2, #moves do
			t.truthy(moves[i].t > moves[i - 1].t, "no two Moves carry one stamp")
		end
		-- the crouch key: the Move that says so goes in the very next frame, whenever the last one went
		Kit.run(b, 1)
		b = Kit.playing()
		Kit.frame(b)
		before = #Kit.moves(b)
		b.seat:input("crouch", true)
		Kit.frame(b)
		moves = Kit.moves(b)
		t.eq(#moves, before + 1)
		t.truthy(Wire.has(moves[#moves].bits, BIT.crouch), "the server hears of the crouch a frame after the key")
		b.seat:input("crouch", false)
		Kit.frame(b)
		moves = Kit.moves(b)
		t.eq(#moves, before + 2)
		t.falsy(Wire.has(moves[#moves].bits, BIT.crouch), "and of standing up")
		-- the feet leave the floor
		Kit.run(b, 1)
		before = #Kit.moves(b)
		b.pose.y, b.pose.air = 0.4, true
		Kit.frame(b)
		moves = Kit.moves(b)
		t.truthy(#moves >= before + 1)
		t.truthy(Wire.has(moves[#moves].bits, BIT.air), "a jump is told in its first frame")
		b.pose.y, b.pose.air = 0, false
		-- however the keys are mashed the stream stays inside the remote's rate (thirty a second, forty-five at once)
		b = Kit.playing()
		for i = 1, 240 do
			b.seat:input("crouch", i % 2 == 0) -- thirty changes a second
			b.pose.air = i % 3 == 0
			if i % 4 == 0 then
				press(b)
			end
			Kit.frame(b)
		end
		moves = Kit.moves(b)
		local rate, burst = 30, 45
		local tokens = burst
		for i, move in moves do
			if i > 1 then
				tokens = math.min(burst, tokens + (move.t - moves[i - 1].t) * rate)
			end
			tokens -= 1
			t.truthy(tokens >= 0, `Move {i} would be dropped by Net's rate limit`)
		end
	end)

	t.test(
		"the origin: crouching, standing, tapping crouch and jumping with clicks at every moment, no ball leaves from where a to-the-letter server would refuse it; at 0, 150 and 300 ms, and with the click's own Move lost",
		function()
			-- The server's side of "the origin", to the letter of the contract: its own crouch fraction eased
			-- once a snapshot tick from the crouch bit of the newest Move it has; the slot's pose at the fire
			-- time read from the Moves it has (between the two either side, held at the newest); the eye
			-- between the two eye heights, originSlackY either way, the jump's height more while the newest
			-- Move says "in the air". A Move sent at t arrives `lat` later, as the Fire does.
			local T = Contract.TRUST
			local function judge(moves: { { [string]: number } }, fire: { [string]: number }, lat: number): boolean
				local arrives = fire.ft + lat
				local c = 0
				local at = 1 -- the next Move to arrive
				local newest: { [string]: number }? = nil
				local tick = moves[1].t
				while tick <= arrives do
					while at <= #moves and moves[at].t + lat <= tick do
						newest = moves[at]
						at += 1
					end
					if newest then
						c = Body.crouchStep(c, Wire.has(newest.bits, BIT.crouch), 1 / Clock.SNAP_HZ, F)
					end
					tick += 1 / Clock.SNAP_HZ
				end
				while at <= #moves and moves[at].t + lat <= arrives do
					newest = moves[at]
					at += 1
				end
				assert(newest, "the server has a Move")
				-- the pose at f
				local y = newest.y
				for i = at - 1, 2, -1 do
					local a, z = moves[i - 1], moves[i]
					if a.t <= fire.ft and fire.ft <= z.t then
						local k = if z.t > a.t then (fire.ft - a.t) / (z.t - a.t) else 1
						y = a.y + (z.y - a.y) * k
						break
					end
				end
				local eyeA = Body.eye(c)
				local eyeB = Body.eye(if Wire.has(newest.bits, BIT.crouch) then 1 else 0)
				local slack = T.originSlackY + (if Wire.has(newest.bits, BIT.air) then Body.JUMP_HEIGHT else 0)
				return fire.oy >= y + math.min(eyeA, eyeB) - slack and fire.oy <= y + math.max(eyeA, eyeB) + slack
			end
			local seed = 12345
			local function rnd(): number
				seed = (seed * 1103515245 + 12345) % 2147483648
				return seed / 2147483648
			end
			local total, popUps = 0, 0
			for _, case in
				{
					{ lat = 0, lost = false },
					{ lat = 0.075, lost = false },
					{ lat = 0.15, lost = false },
					{ lat = 0.075, lost = true },
					{ lat = 0.15, lost = true },
				}
			do
				local b = Kit.playing()
				local crouched = false
				local tapLeft = 0 -- frames until a tap's second half
				local jump: number? = nil -- seconds into a jump
				local sinceFlip = 1
				for _ = 1, 45 * 60 do
					-- a jump as the engine throws a body: 28 studs/s up against 196.2, two studs high
					if jump ~= nil then
						jump += b.dt
						local y = 28 * jump - 98.1 * jump * jump
						if y <= 0 then
							jump = nil
							b.pose.y, b.pose.air = 0, false
						else
							b.pose.y, b.pose.air = y, true
						end
					elseif rnd() < 0.006 then
						jump = 0
					end
					-- the crouch key: held for a while, let go, and now and then tapped
					sinceFlip += b.dt
					if tapLeft > 0 then
						tapLeft -= 1
						if tapLeft == 0 then
							crouched = not crouched
							b.seat:input("crouch", crouched)
							sinceFlip = 0
						end
					elseif sinceFlip > 0.3 and rnd() < 0.02 then
						crouched = not crouched
						b.seat:input("crouch", crouched)
						sinceFlip = 0
						if rnd() < 0.4 then
							tapLeft = 1 + math.floor(rnd() * 8) -- back again within nine frames
						end
					end
					-- clicks at every moment, and on purpose in the first moments of a change (the pop-up shot)
					if rnd() < 0.05 or (sinceFlip < 0.2 and rnd() < 0.3) then
						press(b)
					end
					Kit.frame(b)
				end
				local moves = Kit.moves(b)
				local fires = Kit.fires(b)
				if case.lost then
					-- every click's own Move never arrives: the stance told at once must do by itself
					local stamps: { [number]: boolean } = {}
					for _, fire in fires do
						stamps[fire.ft] = true
					end
					local kept = {}
					for _, move in moves do
						if not stamps[move.t] then
							table.insert(kept, move)
						end
					end
					moves = kept
				end
				t.truthy(#fires >= 60, `{#fires} balls`)
				for i, fire in fires do
					total += 1
					local eye = fire.oy - b.pose.y
					if eye > Body.CROUCH_EYE + 0.45 and eye < Body.STAND_EYE - 0.45 then
						popUps += 1
					end
					t.truthy(
						judge(moves, fire, case.lat),
						`ball {i} at {case.lat * 2000} ms round trip{if case.lost then ", its own Move lost" else ""}: the origin {fire.oy} would be refused`
					)
				end
			end
			-- (and the guard is not a ban: plenty of balls left from an eye in the middle of its travel)
			t.truthy(popUps >= 20, `{popUps} of {total} balls left in mid-crouch`)
		end
	)

	t.test(
		"a placement: the body is pivoted first, so no Move carries a new placement number from the old place",
		function()
			local b = Kit.playing()
			local seat = b.seat
			b.pose.x = 12 -- walked off
			Kit.run(b, 0.3)
			Kit.message(b, { kind = "paintball_correct", x = 5, y = 0, z = 20, yaw = 1.5, why = "wall", place = 2 })
			t.eq(seat.place, 2)
			t.deepEq(b.placed[#b.placed], { x = 5, y = 0, z = 20, yaw = 1.5 }, "the client pivots its own body")
			t.eq(seat.note, Contract.textFor("wall"))
			Kit.run(b, 0.3)
			local old, new = 0, 0
			for _, move in Kit.moves(b) do
				if move.place == 2 then
					new += 1
					t.near(move.x, 5, 1e-6, "from the new place")
					t.near(move.z, 20, 1e-6)
				else
					old += 1
					t.eq(move.place, 1)
				end
			end
			t.truthy(old > 0 and new > 0)
			-- a correction never turns the look: no camera hold, the player's own aim kept
			t.eq(b.cameras, 1, "the first placement's hold only")
			t.eq(b.releases, 1)
			-- the look of a respawn is turned to the placement's yaw through ONE frame of camera hold, then let go
			Kit.place(b, { x = 0, z = 30, yaw = 0.7 })
			Kit.frame(b, 3)
			t.eq(b.cameras, 2, "one hold for the first placement, one for the respawn")
			t.eq(b.releases, 2)
			t.near(b.looks[#b.looks].yaw, 0.7, 1e-9)
			t.near(b.looks[#b.looks].y, Body.STAND_EYE, 1e-9, "from the eye")
			-- the switch for a Studio that says the stock camera does not carry on from it
			local tuning = table.clone(Tuning) :: any
			tuning.turnLook = false
			local c = Kit.playing({ tuning = tuning })
			t.eq(c.cameras, 0)
			t.eq(c.seat.place, 1, "and nothing else changes")
		end
	)

	t.test(
		"a correction mid-fight keeps the player's aim: no camera hold, the yaw and the pitch are left alone",
		function()
			-- (the server's correction carries the yaw of the last pose it took, up to a second old: turning the view
			-- to it, levelled, would snap a player aiming up and to the left at someone round to face away)
			local b = Kit.playing()
			local seat = b.seat
			Kit.run(b, 0.3)
			local holds, looks = b.cameras, #b.looks
			b.pose.yaw, b.pose.pitch = 1.2, 0.35
			Kit.frame(b)
			Kit.message(b, { kind = "paintball_correct", x = 2, y = 0, z = 28, yaw = 0.2, why = "speed", place = 2 })
			Kit.frame(b, 3)
			t.eq(b.cameras, holds, "no camera hold")
			t.eq(#b.looks, looks, "the look is not turned")
			t.eq(b.held, false)
			t.near(b.pose.yaw, 1.2, 1e-9, "the player's own yaw")
			t.near(b.pose.pitch, 0.35, 1e-9, "and pitch")
			t.near(seat.yaw, 1.2, 1e-6)
			t.near(seat.pitch, 0.35, 1e-6)
			t.deepEq(b.placed[#b.placed], { x = 2, y = 0, z = 28, yaw = 0.2 }, "the body is still put back")
			t.eq(seat.place, 2)
			local moves = Kit.moves(b)
			local last = moves[#moves]
			t.eq(last.place, 2)
			t.near(last.pitch, 0.35, 1e-3, "and the stream carries the aim the player kept")
		end
	)

	t.test("a placement that arrives before the seat knows its slot is kept and obeyed", function()
		-- (a client that cannot find itself in the roster: it learns its slot from "state" alone)
		local b = Kit.bench({ user = 0 })
		Kit.watch(b)
		Kit.message(b, { kind = "paintball_respawn", id = 2, x = 50, y = 0, z = 0, yaw = 0, at = b.now(), place = 0 })
		Kit.message(
			b,
			{ kind = "paintball_respawn", id = 1, x = -50, y = 0, z = 4, yaw = 0.5, at = b.now(), place = 1 }
		)
		t.eq(b.seat.place, 0)
		Kit.state(b, { phase = "briefing", endsAt = b.now() + 10 })
		t.eq(b.seat.place, 1)
		t.near(b.pose.x, -50, 1e-9)
		-- the roster names every slot's user: with it the seat knows its slot before any "state"
		b = Kit.bench()
		Kit.watch(b)
		t.eq(b.seat.you, 1, "found by its UserId")
		t.eq(b.seat.team, 1)
		t.eq(b.show.you, 1)
		Kit.message(
			b,
			{ kind = "paintball_respawn", id = 1, x = -50, y = 0, z = 4, yaw = 0.5, at = b.now(), place = 1 }
		)
		t.eq(b.seat.place, 1, "obeyed at once")
	end)

	t.test(
		"a new match deals the seats again: nobody else's placement is obeyed, whichever message comes first",
		function()
			local roster = {
				{ id = 1, team = 1, name = "Bea", bot = false, user = 13 },
				{ id = 2, team = 2, name = "Ann", bot = false, user = 11 },
				{ id = 3, team = 1, name = "Rusty", bot = true, user = 0 },
				{ id = 4, team = 2, name = "Static", bot = true, user = 0 },
			}
			local seats =
				{ { name = "Bea" }, { name = "Ann" }, { name = "Rusty (computer)" }, { name = "Static (computer)" } }
			local slots = {}
			for id = 1, 4 do
				slots[id] =
					{ id = id, team = if id % 2 == 1 then 1 else 2, on = true, tags = 0, outs = 0, shots = 0, hits = 0 }
			end
			for _, order in { "roster first", "placements first" } do
				local b = Kit.playing()
				local seat = b.seat
				Kit.run(b, 0.5)
				Kit.state(b, { phase = "ended", done = true })
				t.eq(seat.phase, "ended")
				-- the next match: Ann is dealt seat 2 (the person who held seat 1 left; Bea sits there now), on teal
				local function placements()
					-- Bea's, at seat 1 (Ann's old number), with a placement number that could be Ann's next
					Kit.message(b, {
						kind = "paintball_respawn",
						id = 1,
						x = -52,
						y = 0,
						z = 0,
						yaw = 0,
						at = b.now() + 2,
						place = 2,
					})
					Kit.message(b, {
						kind = "paintball_respawn",
						id = 2,
						x = 52,
						y = 0,
						z = 2,
						yaw = 3,
						at = b.now() + 2,
						place = 2,
					})
				end
				if order == "roster first" then
					Kit.watch(b, roster, { match = 2 })
					placements()
				else
					placements()
					t.eq(seat.place, 1, `{order}: not obeyed while the end card is up`)
					t.near(b.pose.x, 0, 1e-9)
					Kit.watch(b, roster, { match = 2 })
				end
				Kit.state(
					b,
					{ you = 2, phase = "briefing", endsAt = b.now() + 10, match = 2, seats = seats, slots = slots }
				)
				t.eq(seat.you, 2, order)
				t.eq(seat.team, 2, order)
				t.eq(seat.place, 2, order)
				t.near(b.pose.x, 52, 1e-9, `{order}: in teal's room, not in Bea's place`)
				t.near(b.pose.z, 2, 1e-9)
				t.eq(b.curtains[#b.curtains], 1, "the curtains that are shut to you changed with the side")
				t.eq(b.show.you, 2)
				Kit.run(b, 0.3)
				local moves = Kit.moves(b)
				t.eq(moves[#moves].place, 2)
				t.near(moves[#moves].x, 52, 1e-6)
			end
		end
	)

	t.test(
		"tagged out: the legs are taken, the pose stream stops, the HUD knows who; the respawn gives it all back",
		function()
			local b = Kit.playing()
			local seat = b.seat
			for _ = 1, 4 do
				press(b)
				Kit.run(b, 0.27)
			end
			t.eq(seat.mag.rounds, 1)
			seat:input("sprint", true)
			Kit.run(b, 0.3)
			local at = b.now() + F.respawnSecs
			local tag = {
				kind = "paintball_tag",
				by = 2,
				id = 1,
				ball = 7,
				scores = { 0, 1 },
				tags = 1,
				outs = 1,
				at = at,
				x = 0,
				y = 3,
				z = 30,
			}
			Kit.message(b, tag)
			t.truthy(seat.out)
			t.eq(seat.outBy, 2)
			t.eq(seat.outUntil, at)
			t.deepEq(b.controls, { false }, "ctx.controls(false)")
			t.eq(seat.k, 0, "the sprint is over")
			t.eq(Kit.cues(b, "paintball.tagged"), 1, "the louder sound")
			t.eq(Kit.cues(b, "paintball.tag"), 0)
			t.deepEq(seat.scores, { 0, 1 })
			t.eq(seat.slots[1].outs, 1)
			t.eq(seat.slots[2].tags, 1)
			t.truthy(string.find(seat.feed[#seat.feed].text, "Cy tagged Ann", 1, true))
			local sent = #Kit.moves(b)
			Kit.run(b, 1)
			t.eq(#Kit.moves(b), sent, "no Move while out")
			press(b)
			Kit.frame(b)
			t.eq(#Kit.fires(b), 4)
			-- back: in the spawn room, a full magazine, protected
			local safe = b.now() + F.protectSecs
			Kit.place(b, { x = -52, z = 0, yaw = -1.2, at = safe, place = 2 })
			t.falsy(seat.out)
			t.deepEq(b.controls, { false, true })
			t.eq(seat.mag.rounds, R.magazine, "nobody comes back with the one ball they had left")
			t.eq(seat.mag.reloadDoneAt, nil)
			t.eq(seat.safeUntil, safe)
			Kit.run(b, 0.2)
			t.truthy(seat.inRoom, "safe in your own room")
			t.truthy(#Kit.moves(b) > sent, "the stream is back")
			local moves = Kit.moves(b)
			t.eq(moves[#moves].place, 2)
		end
	)

	t.test(
		"tagged in the last seconds: the end card gives the legs back and sends no pose; the next match makes you whole",
		function()
			local b = Kit.playing()
			local seat = b.seat
			Kit.message(b, {
				kind = "paintball_tag",
				by = 2,
				id = 1,
				ball = 7,
				scores = { 0, 1 },
				tags = 1,
				outs = 1,
				at = b.now() + F.respawnSecs,
				x = 0,
				y = 3,
				z = 30,
			})
			t.deepEq(b.controls, { false })
			Kit.run(b, 1)
			-- the clock runs out before the respawn: no placement is coming for fifteen seconds
			Kit.state(b, { phase = "ended", done = true })
			t.eq(seat.phase, "ended")
			t.deepEq(b.controls, { false, true }, "people may walk at the end card, the tagged too")
			local sent = #Kit.moves(b)
			b.pose.x = 5
			Kit.run(b, 1)
			t.eq(#Kit.moves(b), sent, "still out to the server: it would drop the poses, so none is sent")
			t.eq(Kit.cues(b, "paintball.step"), 0, "(and nobody hears the walk)")
			-- a tag that lands as the card comes up takes nobody's legs
			Kit.message(b, {
				kind = "paintball_tag",
				by = 4,
				id = 1,
				ball = 9,
				scores = { 0, 2 },
				tags = 1,
				outs = 2,
				at = b.now() + F.respawnSecs,
				x = 0,
				y = 3,
				z = 30,
			})
			t.deepEq(b.controls, { false, true })
			-- the next match: the roster, then the placement
			Kit.watch(b, nil, { match = 2 })
			Kit.state(b, { phase = "briefing", endsAt = b.now() + R.briefingSecs, match = 2 })
			Kit.place(b, { x = -52, z = 0, at = b.now() + R.briefingSecs, place = 2 })
			t.falsy(seat.out)
			t.deepEq(b.controls, { false, true }, "the legs were back already: not given twice")
			Kit.run(b, 0.3)
			t.truthy(#Kit.moves(b) > sent, "the stream is back")
		end
	)

	t.test("YOU tagged someone: the hit marker and the hit sound come on the server's word and never before", function()
		local b = Kit.playing()
		local seat = b.seat
		Kit.snap(b, { Kit.body(2, 0, 0, 0) }, b.now() - 0.3)
		Kit.snap(b, { Kit.body(2, 0, 0, 0) }, b.now())
		Kit.run(b, 0.2)
		press(b)
		Kit.run(b, 0.6)
		t.eq(#b.show.balls, 0, "the ball ended on the puppet")
		t.eq(#b.show.puffs, 1, "with a puff")
		t.eq(seat.hitAt, -math.huge, "no marker yet")
		t.eq(Kit.cues(b, "paintball.tag"), 0, "no sound yet")
		t.deepEq(seat.scores, { 0, 0 })
		t.eq(#b.show.walls, 0)
		Kit.message(b, {
			kind = "paintball_tag",
			by = 1,
			id = 2,
			ball = 3,
			scores = { 1, 0 },
			tags = 1,
			outs = 1,
			at = b.now() + 4,
			x = 0,
			y = 4,
			z = 1.2,
		})
		t.eq(seat.hitAt, b.now())
		t.eq(Kit.cues(b, "paintball.tag"), 1)
		t.eq(seat.note, "You tagged Cy", "and who it was, in words under the crosshair")
		t.deepEq(seat.scores, { 1, 0 })
		t.eq(seat.slots[1].tags, 1)
		t.falsy(seat.out)
	end)

	t.test(
		"the predicted ball stops on an opposing puppet, and passes a team-mate, a safe one and an out one",
		function()
			local function shootAt(more: { [string]: any }?, id: number?): Kit.Bench
				local b = Kit.playing()
				local who = id or 2
				for i = 3, 0, -1 do
					Kit.snap(b, { Kit.body(who, 0, 0, 0, more) }, b.now() - i * 0.05)
				end
				Kit.run(b, 0.2)
				t.truthy(b.show.puppets[who] ~= nil, "the puppet is drawn")
				press(b)
				Kit.run(b, 0.4)
				return b
			end
			local b = shootAt()
			t.eq(#b.show.puffs, 1)
			t.near(b.show.puffs[1].z, Body.HIT_RADIUS, 0.01, "at the entry point")
			t.eq(#b.show.balls, 0)
			-- a team-mate: the ball flies on (it is still in the air a quarter of a second later)
			b = shootAt(nil, 3)
			t.eq(#b.show.puffs, 0)
			t.eq(#b.show.balls, 1)
			-- protected, tagged out, in its own spawn room, crouched behind a rail: all passed
			b = shootAt({ bits = BIT.safe })
			t.eq(#b.show.puffs, 0)
			b = shootAt({ bits = BIT.out })
			t.eq(#b.show.puffs, 0)
			b = Kit.playing()
			Kit.place(b, { x = 30, z = 0, yaw = -math.pi / 2 }) -- looking east at team 2's room
			Kit.snap(b, { Kit.body(2, 50, 0, 0) }, b.now() - 0.2)
			Kit.snap(b, { Kit.body(2, 50, 0, 0) }, b.now())
			Kit.run(b, 0.2)
			press(b)
			Kit.run(b, 0.4)
			t.eq(#b.show.puffs, 0, "a body in its own room cannot be hit")
			-- the rail: a crouched body behind it is wholly hidden from a level ball; standing it is not
			for _, case in { { crouch = 1, hit = false }, { crouch = 0, hit = true } } do
				b = Kit.playing()
				Kit.snap(b, { Kit.body(2, 0, 0, 8.5, { crouch = case.crouch }) }, b.now() - 0.2)
				Kit.snap(b, { Kit.body(2, 0, 0, 8.5, { crouch = case.crouch }) }, b.now())
				Kit.run(b, 0.2)
				press(b)
				Kit.run(b, 0.4)
				t.eq(#b.show.puffs == 1, case.hit, `crouch {case.crouch}`)
			end
		end
	)

	t.test(
		"a wall: your splat is drawn at once; the server's record replaces it; an unconfirmed one is taken back",
		function()
			local b = Kit.playing()
			press(b)
			Kit.run(b, 1)
			t.eq(#b.show.balls, 0)
			t.eq(#b.show.walls, 1, "drawn the frame the ball met the wall")
			local mine = b.show.walls[1]
			t.truthy(mine.predicted)
			t.near(mine.z, -40, 1e-6, "on the wall's face")
			t.eq(mine.face, Wire.FACE.pz)
			t.eq(mine.team, 1)
			t.eq(Kit.showCues(b, "paintball.splat"), 1)
			-- the server's record of the same ball, a little off (its ball met a quantised world)
			b.show:onSplats(Wire.pack(Wire.Splat, {
				{
					seq = 1,
					ball = 5,
					by = 1,
					body = 0,
					team = 1,
					face = Wire.FACE.pz,
					x = mine.x + 0.3,
					y = mine.y - 0.2,
					z = -40,
				},
			}))
			t.eq(#b.show.walls, 1, "replaced, not doubled")
			t.falsy(b.show.walls[1].predicted)
			t.eq(b.show.walls[1].seq, 1)
			t.eq(Kit.showCues(b, "paintball.splat"), 1, "and not heard twice")
			Kit.run(b, 2)
			t.eq(#b.show.walls, 1, "a record stays for the match")
			-- a predicted splat the server never confirms
			Kit.run(b, F.reloadSecs)
			press(b)
			Kit.run(b, 0.9)
			t.eq(#b.show.walls, 2)
			Kit.run(b, Tuning.predictedSplatSecs + 0.1)
			t.eq(#b.show.walls, 1, "taken back")
			-- a record of your own that lands far from the prediction is its own splat
			press(b)
			Kit.run(b, 0.9)
			b.show:onSplats(Wire.pack(Wire.Splat, {
				{ seq = 2, ball = 6, by = 1, body = 0, team = 1, face = Wire.FACE.pz, x = 20, y = 8, z = -40 },
			}))
			t.eq(#b.show.walls, 3)
			-- a refused click takes its ball's splat back too
			Kit.message(b, { kind = "paintball_ack", shot = 3, ok = false, why = "fast", rounds = 3 })
			t.eq(#b.show.walls, 2)
		end
	)

	t.test(
		"the splats: two pools exactly as the wire says; a slot's clear with its occupant, all with the match",
		function()
			local b = Kit.bench()
			Kit.watch(b)
			local records = {}
			for seq = 1, R.splatPool + 30 do
				table.insert(
					records,
					{ seq = seq, ball = seq % 60000, by = 2, body = 0, team = 2, face = 1, x = 0, y = seq % 10, z = 0 }
				)
			end
			for seq = 1, R.bodySplats + 6 do
				table.insert(
					records,
					{ seq = 1000 + seq, ball = seq, by = 2, body = 3, team = 2, face = 0, x = 0.5, y = 3, z = -1 }
				)
			end
			table.insert(records, { seq = 2000, ball = 1, by = 1, body = 2, team = 1, face = 0, x = 0, y = 2, z = 1 })
			b.show:onSplats(Wire.pack(Wire.Splat, records))
			t.eq(#b.show.walls, R.splatPool, "the walls' newest 400")
			t.eq(b.show.walls[1].seq, 31, "the oldest replaced")
			t.eq(#b.show.bodies[3], R.bodySplats, "each slot's newest 24")
			t.eq(b.show.bodies[3][1].seq, 1007)
			t.eq(#b.show.bodies[2], 1)
			t.eq(#b.show.cues, 0, "the batch on coming in is not eight hundred sounds")
			-- the same records again (the join batch overlapping the live stream): nothing doubles
			b.show:onSplats(Wire.pack(Wire.Splat, { records[#records], records[40] }))
			t.eq(#b.show.bodies[2], 1)
			t.eq(#b.show.walls, R.splatPool)
			-- slot 3 changes hands (a bot for a person); slot 2 keeps its occupant
			local version = b.show.version
			Kit.watch(b, {
				{ id = 1, team = 1, name = "Ann", bot = false, user = 11 },
				{ id = 2, team = 2, name = "Cy", bot = false, user = 12 },
				{ id = 3, team = 1, name = "Gaffer", bot = true, user = 0 },
				{ id = 4, team = 2, name = "Rusty", bot = true, user = 0 },
			})
			t.eq(#b.show.bodies[3], 0, "nobody wears the last one's paint")
			t.eq(#b.show.bodies[2], 1)
			t.eq(#b.show.walls, R.splatPool)
			t.truthy(b.show.version > version, "the drawer is told")
			-- a change of side is not a change of occupant
			Kit.watch(b, {
				{ id = 1, team = 1, name = "Ann", bot = false, user = 11 },
				{ id = 2, team = 1, name = "Cy", bot = false, user = 12 },
				{ id = 3, team = 2, name = "Gaffer", bot = true, user = 0 },
				{ id = 4, team = 2, name = "Rusty", bot = true, user = 0 },
			})
			t.eq(#b.show.bodies[2], 1)
			-- a new match: everything goes, by "paintball_watch" or by a snapshot's head, whichever is first
			Kit.watch(b, nil, { match = 2 })
			t.eq(#b.show.walls, 0)
			t.eq(next(b.show.bodies), nil)
			b.show:onSplats(Wire.pack(Wire.Splat, { records[1] }))
			t.eq(#b.show.walls, 1)
			b.show:onSnap(Wire.encodeSnap(b.now(), 1, 3, {}))
			t.eq(#b.show.walls, 0, "the snapshot's match number moved")
		end
	)

	t.test("puppets are drawn at the view time between two snapshots, bits from the older; never your own", function()
		local b = Kit.bench()
		Kit.watch(b)
		Kit.state(b)
		local t0 = b.now()
		-- a body walking +x at 10 studs/s, crouching from the third snapshot on; snapshots arrive 30 ms late
		for i = 0, 10 do
			local at = t0 + i * 0.05
			while b.now() < at + 0.03 do
				Kit.frame(b)
			end
			Kit.snap(b, {
				Kit.body(1, 0, 0, 30),
				Kit.body(
					2,
					i * 0.5,
					0,
					0,
					{ crouch = if i >= 3 then 1 else 0, bits = if i >= 3 then BIT.crouch else 0 }
				),
			}, at)
		end
		Kit.frame(b)
		local p = b.show.puppets[2]
		t.truthy(p ~= nil)
		local vt = b.show.vt
		t.truthy(vt < b.now() - Clock.INTERP_SECS, "the view runs behind by the lag and two snapshot intervals")
		t.truthy(vt > b.now() - 0.2)
		-- the server's own arithmetic for the same instant
		local i = math.floor((vt - t0) / 0.05 + 1e-9)
		local a = Kit.body(2, i * 0.5, 0, 0)
		local c = Kit.body(2, (i + 1) * 0.5, 0, 0)
		local qa = { Wire.quantPose(a.x, 0, 0, 0) }
		local qc = { Wire.quantPose(c.x, 0, 0, 0) }
		a.x, c.x = qa[1], qc[1]
		local x = Wire.between(a, t0 + i * 0.05, c, t0 + (i + 1) * 0.05, vt)
		t.near(p.x, x, 1e-9, "Wire.between of the two snapshots either side: the pose the server rewinds to")
		t.truthy(Wire.has(p.bits, BIT.crouch))
		t.eq(p.team, 2)
		t.eq(p.name, "Cy")
		t.truthy(p.shown)
		t.falsy(b.show.puppets[1].shown, "your own slot is never drawn")
		-- the stream stops: held at the newest, never run ahead
		Kit.run(b, 0.5)
		t.near(b.show.puppets[2].x, qc[1] * 0 + ({ Wire.quantPose(5, 0, 0, 0) })[1], 1e-9)
		-- a slot that leaves the snapshots leaves the screen
		Kit.snap(b, { Kit.body(1, 0, 0, 30) })
		Kit.run(b, 0.3)
		t.eq(b.show.puppets[2], nil)
	end)

	t.test("a tagged puppet throws up a hand for a second and is then not drawn until it is back", function()
		local b = Kit.bench()
		Kit.watch(b)
		local function feed(bits: number, seconds: number)
			for _ = 1, math.floor(seconds * 20) do
				Kit.snap(b, { Kit.body(2, 5, 0, 5, { bits = bits }) })
				Kit.frame(b, 3)
			end
		end
		feed(0, 0.5)
		t.truthy(b.show.puppets[2].shown)
		feed(BIT.out, 0.5)
		t.truthy(b.show.puppets[2].hand, "the hand is up")
		t.truthy(b.show.puppets[2].shown)
		feed(BIT.out, Tuning.outHandSecs)
		t.falsy(b.show.puppets[2].shown, "walked back: not drawn")
		feed(BIT.safe, 0.5)
		t.truthy(b.show.puppets[2].shown, "back, protected")
		t.falsy(b.show.puppets[2].hand)
	end)

	t.test(
		"other slots' balls come from Shot records, drawn in view time from the marker that fired; never your own twice",
		function()
			local b = Kit.playing()
			Kit.snap(b, { Kit.body(2, 0, 0, 0) }, b.now() - 0.1)
			Kit.snap(b, { Kit.body(2, 0, 0, 0) })
			Kit.frame(b, 2)
			local born = b.now()
			b.show:onShots(Wire.pack(Wire.Shot, {
				{ ball = 9, id = 2, t = born, ox = 0, oy = 4.5, oz = 0, vx = 60, vy = 0, vz = 0 },
				{ ball = 10, id = 1, t = born, ox = 0, oy = 4.5, oz = 30, vx = 0, vy = 0, vz = -90 },
			}))
			t.eq(#b.show.balls, 1, "your own Shot record is passed over: you drew that ball at the click")
			local ball = b.show.balls[1]
			t.eq(ball.team, 2)
			Kit.frame(b, 2)
			t.falsy(ball.born, "the view has not reached its birth yet")
			t.eq(Kit.showCues(b, "paintball.fire_far"), 0)
			Kit.run(b, 0.2)
			t.truthy(ball.born)
			t.eq(Kit.showCues(b, "paintball.fire_far"), 1, "the marker's pop, at the origin")
			t.near(ball.x, 60 * (b.show.vt - born), 1e-6, "age = view time - birth: it left the puppet's marker")
			t.near(ball.y, 4.5 - 0.5 * F.ballDrop * (b.show.vt - born) ^ 2, 1e-6)
			-- the same record again (an unreliable stream may repeat): one ball
			b.show:onShots(
				Wire.pack(
					Wire.Shot,
					{ { ball = 9, id = 2, t = born, ox = 0, oy = 4.5, oz = 0, vx = 60, vy = 0, vz = 0 } }
				)
			)
			t.eq(#b.show.balls, 1)
			-- the server says it ended on the east wall... there is none at x = 60 but the slab's edge: let it fly out
			Kit.run(b, R.ballTtl + 0.5)
			t.eq(#b.show.balls, 0, "gone after its time")
		end
	)

	t.test("another's ball stops where the wall is; the server's splat is shown when the picture gets there", function()
		local b = Kit.playing()
		local born = b.now()
		b.show:onShots(
			Wire.pack(Wire.Shot, { { ball = 4, id = 2, t = born, ox = 0, oy = 5, oz = 0, vx = 0, vy = 0, vz = -90 } })
		)
		Kit.run(b, 0.2)
		t.eq(#b.show.balls, 1)
		-- the verdict arrives while the ball is still in the air on this screen
		local hitY = 5 - 0.5 * F.ballDrop * (40 / 90) ^ 2
		b.show:onSplats(Wire.pack(Wire.Splat, {
			{ seq = 8, ball = 4, by = 2, body = 0, team = 2, face = Wire.FACE.pz, x = 0, y = hitY, z = -40 },
		}))
		t.eq(#b.show.walls, 0, "not before the ball")
		Kit.run(b, 0.5)
		t.eq(#b.show.balls, 0)
		t.eq(#b.show.walls, 1)
		t.eq(b.show.walls[1].seq, 8)
		-- a record for a ball this screen never drew (its Shot was lost) shows at once
		b.show:onSplats(Wire.pack(Wire.Splat, {
			{ seq = 9, ball = 77, by = 2, body = 0, team = 2, face = Wire.FACE.pz, x = 3, y = 3, z = -40 },
		}))
		t.eq(#b.show.walls, 2)
	end)

	t.test(
		"sounds in space: nearer is louder, a floor between muffles, far away is silent; reload rattles from the bit",
		function()
			local b = Kit.bench()
			Kit.watch(b)
			b.show.listener = { x = 0, y = 4.5, z = 0 }
			b.show:cue("paintball.fire_far", 0.6, 5, 4.5, 0)
			b.show:cue("paintball.fire_far", 0.6, 50, 4.5, 0)
			b.show:cue("paintball.fire_far", 0.6, 5, 4.5 + Arena.FLOOR_HEIGHT, 0)
			b.show:cue("paintball.fire_far", 0.6, 500, 4.5, 0)
			t.eq(#b.show.cues, 3, "past Tuning.soundFar nothing is asked for")
			t.truthy(b.show.cues[1].volume > b.show.cues[2].volume * 2)
			t.truthy(b.show.cues[3].volume < b.show.cues[1].volume * 0.5, "through the ceiling")
			table.clear(b.show.cues)
			-- the rising edge of BIT.reload, and footsteps: loud running, soft walking, silent crouched
			local function walk(bits: number, crouch: number, seconds: number)
				for i = 1, math.floor(seconds * 20) do
					local last = b.show.puppets[2]
					local x = (if last then last.x else 0) + 0.6
					Kit.snap(b, { Kit.body(2, x, 0, 4, { bits = bits, crouch = crouch }) })
					Kit.frame(b, 3)
					local _ = i
				end
			end
			walk(0, 0, 1)
			local soft = Kit.showCues(b, "paintball.step")
			t.truthy(soft >= 1)
			t.eq(Kit.showCues(b, "paintball.reload"), 0)
			table.clear(b.show.cues)
			walk(BIT.reload + BIT.sprint, 0, 1)
			t.eq(Kit.showCues(b, "paintball.reload"), 1, "once, on the rising edge")
			t.truthy(Kit.showCues(b, "paintball.step") >= 1)
			table.clear(b.show.cues)
			walk(BIT.crouch, 1, 1)
			t.eq(Kit.showCues(b, "paintball.step"), 0, "crouched steps are silent")
		end
	)

	t.test(
		"a cue placed in space keeps where it was and the floors between, so the screen plays it from there",
		function()
			local b = Kit.playing()
			b.show.listener = { x = 0, y = Body.STAND_EYE, z = 30 }
			table.clear(b.show.cues)
			b.show:cue("paintball.step", 0.6, -10, 0, 40)
			b.show:cue("paintball.step", 0.6, -10, Arena.FLOOR_HEIGHT + 1, 40)
			b.show:cue("paintball.over", 0.8)
			local level, up, flat = b.show.cues[1], b.show.cues[2], b.show.cues[3]
			t.deepEq({ level.x, level.y, level.z, level.floors }, { -10, 0, 40, 0 }, "where it was, on your floor")
			t.deepEq({ up.x, up.y, up.z, up.floors }, { -10, Arena.FLOOR_HEIGHT + 1, 40, 1 }, "a floor up")
			t.truthy(
				up.volume <= level.volume * Tuning.floorMuffle + 1e-9,
				"and quieter for the floor (and the distance)"
			)
			t.eq(flat.x, nil, "a cue with no place is played as it is")
			t.eq(flat.volume, 0.8)
		end
	)

	t.test("your own footsteps: running loud, walking soft, crouched silent", function()
		local b = Kit.playing()
		local function walk(seconds: number, speed: number)
			for _ = 1, math.floor(seconds * 60) do
				b.pose.x += speed * DT
				Kit.frame(b)
			end
		end
		walk(1, Body.WALK)
		local n = Kit.cues(b, "paintball.step")
		t.truthy(n >= 3 and n <= 5, `{n} steps in a second of walking`)
		t.eq(b.sounds[#b.sounds].volume, Tuning.stepQuiet)
		b.seat:input("sprint", true)
		walk(1, Body.SPRINT)
		t.eq(b.sounds[#b.sounds].volume, Tuning.stepLoud)
		b.seat:input("sprint", false)
		b.seat:input("crouch", true)
		local before = Kit.cues(b, "paintball.step")
		walk(1.5, Body.CROUCH_SPEED)
		t.truthy(Kit.cues(b, "paintball.step") - before <= 1, "silent once down")
	end)

	t.test(
		"the bar: empty while playing; Leave and Change sides with the scoreboard and through the briefing",
		function()
			local b = Kit.bench()
			Kit.watch(b)
			Kit.state(b, { phase = "briefing", endsAt = b.now() + 10 })
			t.deepEq(b.buttons[#b.buttons], { { "leave", "Leave the match" }, { "side", "Change sides" } })
			b.seat:input("side", true)
			t.eq(b.verbs[#b.verbs].verb, "side", "in the briefing the verb goes")
			Kit.state(b, { phase = "live" })
			t.deepEq(b.buttons[#b.buttons], {}, "the mouse is the look")
			Kit.place(b)
			Kit.run(b, 0.5)
			local n = #b.verbs
			b.seat:input("leave", true)
			t.eq(#b.verbs, n, "no Leave by a slip in the middle of a fight")
			b.seat:input("scores", true)
			t.truthy(b.seat.board)
			t.eq(#b.buttons[#b.buttons], 2)
			b.seat:input("leave", true)
			t.eq(b.verbs[#b.verbs].verb, "leave")
			b.seat:input("scores", false)
			t.deepEq(b.buttons[#b.buttons], {})
			-- at the end card the framework's own bar stands; no press fires
			local count = #b.buttons
			Kit.state(b, { phase = "ended", done = true })
			t.eq(#b.buttons, count)
			b.seat:input("fire", true)
			Kit.frame(b)
			t.eq(#Kit.fires(b), 0)
		end
	)

	t.test("the match's feel is the client's: interval, reload and ball speed come with the state", function()
		local b = Kit.bench()
		Kit.watch(b, nil, { feel = { ballSpeed = 150 } })
		local feel = Contract.feel({ fireInterval = 0.5, reloadSecs = 1, ballSpeed = 150 })
		Kit.state(b, { feel = feel })
		Kit.place(b)
		Kit.frame(b, 2)
		for _ = 1, 40 do
			press(b)
			Kit.frame(b, 6)
		end
		local fires = Kit.fires(b)
		t.truthy(#fires >= 6)
		for i = 2, 5 do
			t.truthy(fires[i].ft - fires[i - 1].ft >= 0.5 - 1e-9)
		end
		t.truthy(serverAccepts(fires, feel))
		t.near(fires[6].ft - fires[5].ft, 1, 3 * DT, "the feel's reload")
		local ball = b.show.balls[#b.show.balls]
		t.near(math.sqrt(ball.vx ^ 2 + ball.vy ^ 2 + ball.vz ^ 2), 150, 1e-3)
	end)

	t.test(
		"the marker in view shows the rhythm: down for the sprint and up again in 0.15 s, a kick, a tip for the reload",
		function()
			local b = Kit.playing()
			local seat = b.seat
			local down, tip, _, kick = Marker.pose(seat, b.now(), Tuning)
			t.eq(down, 0, "up and ready")
			t.eq(tip, 0)
			t.truthy(kick < 1e-6)
			seat:input("sprint", true)
			Kit.run(b, 0.2)
			down = Marker.pose(seat, b.now(), Tuning)
			t.eq(down, 1, "down well before the ramp is full: the picture of cannot fire")
			seat:input("sprint", false)
			Kit.frame(b)
			down = Marker.pose(seat, b.now(), Tuning)
			t.truthy(down > 0.8, "it does not snap up")
			Kit.run(b, Body.SPRINT_FIRE_DELAY / 2)
			down = Marker.pose(seat, b.now(), Tuning)
			t.near(
				down,
				1 - (b.now() - seat.sprintEndedAt) / Body.SPRINT_FIRE_DELAY,
				1e-9,
				"rising with the delay the seat waits"
			)
			t.truthy(down > 0.2 and down < 0.8)
			Kit.run(b, Body.SPRINT_FIRE_DELAY)
			down = Marker.pose(seat, b.now(), Tuning)
			t.eq(down, 0, "up means may fire")
			t.truthy(seat:ready(b.now()))
			-- a shot kicks and comes home; the fifth tips the marker over for the reload, rattling
			press(b)
			_, _, _, kick = Marker.pose(seat, b.now(), Tuning)
			t.eq(kick, 1)
			Kit.run(b, 0.3)
			_, _, _, kick = Marker.pose(seat, b.now(), Tuning)
			t.truthy(kick < 0.02)
			for _ = 1, 4 do
				press(b)
				Kit.run(b, 0.27)
			end
			Kit.run(b, F.reloadSecs / 2 - 0.27)
			local rattled = 0
			for _ = 1, 12 do
				Kit.frame(b)
				local _, over, rattle = Marker.pose(seat, b.now(), Tuning)
				t.eq(over, 1, "tipped right over through the middle of the reload")
				rattled = math.max(rattled, math.abs(rattle))
			end
			t.truthy(rattled > 0.5, "the hopper rattles")
			Kit.run(b, F.reloadSecs / 2)
			_, tip = Marker.pose(seat, b.now(), Tuning)
			t.eq(tip, 0, "righted as the magazine fills")
			-- tagged out: put away
			Kit.message(b, {
				kind = "paintball_tag",
				by = 2,
				id = 1,
				ball = 1,
				scores = { 0, 1 },
				tags = 1,
				outs = 1,
				at = b.now() + 4,
				x = 0,
				y = 3,
				z = 30,
			})
			down = Marker.pose(seat, b.now(), Tuning)
			t.eq(down, 1)
		end
	)

	t.test("the owner's tuning: /pb and its words; the server's answer is in the feed and the note", function()
		local OwnerTune = require("@client/Minigames/Paintball/OwnerTune")
		t.deepEq({ OwnerTune.parse("/pb ballSpeed 150") }, { "ballSpeed", 150 })
		t.deepEq({ OwnerTune.parse("/pb   rewind 0.3 ") }, { "rewind", 0.3 })
		t.deepEq({ OwnerTune.parse("/pb") }, { "", nil })
		t.deepEq({ OwnerTune.parse("/pb botSkill fast") }, { "botSkill", nil })
		local b = Kit.playing()
		Kit.message(b, { kind = "paintball_tuned", text = "Ball speed: 150 -> 120, from the next match" })
		t.eq(b.seat.note, "Ball speed: 150 -> 120, from the next match")
		t.eq(b.seat.feed[#b.seat.feed].text, "Ball speed: 150 -> 120, from the next match")
	end)

	t.test("a bot's call-out reaches its own side's feed; stop() puts everything back", function()
		local b = Kit.playing()
		Kit.message(b, { kind = "paintball_say", id = 3, line = "floor", n = 3 })
		Kit.message(b, { kind = "paintball_say", id = 4, line = "reloading" })
		t.eq(#b.seat.feed, 1)
		t.truthy(string.find(b.seat.feed[1].text, "Bea: They are on 3!", 1, true))
		Kit.run(b, Tuning.feedSecs + 0.1)
		t.eq(#b.seat.feed, 0)
		t.deepEq(b.locks, { true }, "first person is locked from the moment the seat opens")
		t.deepEq(b.curtains, { 2 }, "the other team's curtains are solid on this screen")
		b.seat:input("crouch", true)
		Kit.run(b, 0.3)
		b.seat:stop()
		t.deepEq(b.locks, { true, false })
		t.eq(b.curtains[#b.curtains], false)
		t.eq(b.eye, 0)
		t.eq(b.fov, 0)
		t.eq(b.paces[#b.paces].scale, nil)
	end)

	t.test("sprint runs ahead only: S or a sideways push with Shift never sprints, W and the diagonal ramp", function()
		local b = Kit.playing()
		local seat = b.seat
		seat:input("sprint", true)
		b.heading = math.pi -- S + Shift: backpedalling
		Kit.run(b, 0.6)
		t.eq(seat.k, 0, "no backpedalling at a sprint")
		t.near(b.paces[#b.paces].scale :: number, 1, 1e-9, "at the walking pace")
		b.heading = math.pi / 2 -- D + Shift: strafing
		Kit.run(b, 0.6)
		t.eq(seat.k, 0, "no strafing at a sprint")
		b.heading = math.pi / 4 -- W + D: the diagonal
		Kit.run(b, 0.05)
		t.truthy(seat.k > 0 and seat.k < 1, "the diagonal ramps")
		Kit.run(b, 0.6)
		t.eq(seat.k, 1)
		b.heading = math.pi -- turning back drops it at once
		Kit.frame(b)
		t.eq(seat.k, 0)
		b.heading = 0 -- W + Shift
		Kit.frame(b)
		t.truthy(seat.k > 0, "W ramps")
		Kit.run(b, 0.6)
		t.eq(seat.k, 1)
		t.near(b.paces[#b.paces].scale :: number, F.sprintMult, 1e-9)
	end)

	t.test(
		"Shift held through a click: the ball is seen to leave, then the sprint picks up by itself; the whole cost",
		function()
			local b = Kit.playing()
			local seat = b.seat
			seat:input("sprint", true)
			Kit.run(b, 0.5)
			local at = b.now()
			press(b)
			Kit.run(b, 1)
			local fires = Kit.fires(b)
			t.eq(#fires, 1)
			local ft = fires[1].ft
			-- no pose says "sprinting" between the press and Tuning.sprintAfterShot after the ball left: the
			-- click is on its way before the first pose that carries the bit again
			local back: number? = nil
			for _, move in Kit.moves(b) do
				if Wire.has(move.bits, BIT.sprint) and move.t > at then
					back = back or move.t
				end
			end
			t.truthy(back ~= nil, "Shift was held all along: the sprint came back by itself")
			t.truthy((back :: number) >= ft + Tuning.sprintAfterShot - 1e-9, "not before the shot has been seen")
			t.truthy((back :: number) < ft + Tuning.sprintAfterShot + 1 / Clock.SEND_HZ + 2 * DT)
			t.eq(seat.k, 1, "and is at full pace again")
			-- what a shot costs a sprinter, start to finish: the marker up, the shot seen, the ramp
			local cost = Body.SPRINT_FIRE_DELAY + Tuning.sprintAfterShot + Body.SPRINT_RAMP_SECS
			t.truthy(cost < 0.6, `a sprinter who fires is back at full pace in {cost} s`)
			-- with the number at 0 the sprint is back the very next frame (it is the table's to turn)
			local tuned = table.clone(Tuning)
			tuned.sprintAfterShot = 0
			b = Kit.playing({ tuning = tuned })
			b.seat:input("sprint", true)
			Kit.run(b, 0.5)
			press(b)
			Kit.run(b, Body.SPRINT_FIRE_DELAY + 3 * DT)
			t.eq(#Kit.fires(b), 1)
			t.truthy(b.seat.k > 0)
		end
	)

	t.test(
		"the rhythm is heard: a click when the magazine is full again, the horn when the match goes live, back from out",
		function()
			local b = Kit.playing()
			local seat = b.seat
			for _ = 1, 5 do
				press(b)
				Kit.run(b, F.fireInterval + 0.02)
			end
			t.eq(Kit.cues(b, "paintball.reload"), 1, "the rattle as the fifth ball leaves")
			t.eq(Kit.cues(b, "paintball.ready"), 0)
			Kit.run(b, F.reloadSecs)
			t.eq(Kit.cues(b, "paintball.ready"), 1, "the click that says full again")
			Kit.run(b, 1)
			t.eq(Kit.cues(b, "paintball.ready"), 1, "once")
			-- R: the same two sounds
			press(b)
			Kit.run(b, 0.3)
			seat:input("reload", true)
			Kit.run(b, F.reloadSecs + 0.1)
			t.eq(Kit.cues(b, "paintball.reload"), 2)
			t.eq(Kit.cues(b, "paintball.ready"), 2)
			-- a reload the server did not start ends without it
			press(b)
			Kit.run(b, 0.3)
			seat:input("reload", true)
			seat:onRefused({ kind = "refused", verb = "reload", text = "Not now." })
			Kit.run(b, F.reloadSecs + 0.1)
			t.eq(Kit.cues(b, "paintball.ready"), 2)

			-- the horn, for a seat that stood through the briefing: by the clock, once
			b = Kit.bench()
			Kit.watch(b)
			local ends = b.now() + 0.5
			Kit.state(b, { phase = "briefing", endsAt = ends })
			Kit.place(b, { at = ends + F.protectSecs })
			Kit.run(b, 0.4)
			t.eq(Kit.cues(b, "paintball.go"), 0)
			Kit.run(b, 0.3)
			t.eq(Kit.cues(b, "paintball.go"), 1)
			Kit.state(b, { phase = "live", endsAt = ends + R.matchSecs })
			Kit.run(b, 0.5)
			t.eq(Kit.cues(b, "paintball.go"), 1, "the server's own word does not sound it again")
			t.eq(Kit.cues(Kit.playing(), "paintball.go"), 0, "somebody who joins a running match hears none")

			-- tagged out and back: protected for as long as the server says, and it is heard
			b = Kit.playing()
			seat = b.seat
			t.eq(Kit.cues(b, "paintball.back"), 0, "not for the first placement")
			t.eq(seat:protected(b.now()), nil)
			Kit.message(b, {
				kind = "paintball_tag",
				by = 2,
				id = 1,
				ball = 7,
				scores = { 0, 1 },
				tags = 1,
				outs = 1,
				at = b.now() + F.respawnSecs,
				x = 0,
				y = 3,
				z = 30,
			})
			Kit.run(b, 0.5)
			t.eq(seat:protected(b.now()), nil, "out is not protected: it is out")
			Kit.place(b, { at = b.now() + F.protectSecs })
			t.eq(Kit.cues(b, "paintball.back"), 1)
			t.near(seat:protected(b.now()) :: number, F.protectSecs, 1e-9)
			Kit.run(b, 1)
			t.near(seat:protected(b.now()) :: number, F.protectSecs - 1, 1e-6, "counting down")
			Kit.run(b, F.protectSecs - 1 + 0.05)
			t.eq(seat:protected(b.now()), nil)

			-- full time: the whistle, once, however often the state is told
			t.eq(Kit.cues(b, "paintball.over"), 0)
			Kit.state(b, { phase = "ended", done = true })
			Kit.state(b, { phase = "ended", done = true })
			t.eq(Kit.cues(b, "paintball.over"), 1)
			-- (a seat that opens onto an end card heard no match and hears no whistle)
			local late = Kit.bench()
			Kit.state(late, { phase = "ended", done = true })
			t.eq(Kit.cues(late, "paintball.over"), 0)
		end
	)

	t.test("between two shots only the marker's rhythm waits; the marker down or reloading is a real block", function()
		local b = Kit.playing()
		local seat = b.seat
		t.truthy(seat:ready(b.now()))
		t.eq(seat:rhythm(b.now()), false, "ready is not waiting")
		press(b)
		Kit.frame(b)
		t.eq(#Kit.fires(b), 1)
		t.eq(seat:ready(b.now()), false)
		t.eq(seat:rhythm(b.now()), true, "the fire interval: the next ball goes down the middle all the same")
		Kit.run(b, F.fireInterval)
		t.truthy(seat:ready(b.now()))
		seat:input("sprint", true)
		Kit.run(b, 0.3)
		t.truthy(seat.k > 0)
		t.eq(seat:rhythm(b.now()), false, "the marker down is a real block")
		seat:input("sprint", false)
		Kit.run(b, 0.5)
		seat:input("reload", true)
		Kit.frame(b)
		t.truthy(seat:reloading(b.now()) ~= nil)
		t.eq(seat:rhythm(b.now()), false, "and so is a reload")
	end)

	t.test(
		"the server's idle deadline falls while you are tagged out: the countdown is on screen all through",
		function()
			local b = Kit.playing()
			local seat = b.seat
			Kit.run(b, R.idleSecs - Tuning.idleWarn + 1.5) -- the warning is up, 13.5 s left
			local deadline = b.now() + (seat:idle(b.now()) :: number)
			-- tagged with a long wait (the owner may tune the respawn to 10 s): the deadline lands inside it
			Kit.message(b, {
				kind = "paintball_tag",
				by = 2,
				id = 1,
				ball = 3,
				scores = { 0, 1 },
				tags = 1,
				outs = 1,
				at = deadline + 2,
				x = 0,
				y = 3,
				z = 30,
			})
			t.truthy(seat.out)
			while b.now() < deadline - 0.05 do
				Kit.frame(b)
				local left = seat:idle(b.now())
				t.truthy(left ~= nil, "the countdown never goes away while out")
				t.near(left :: number, deadline - b.now(), 1e-6, "and it is the server's deadline")
			end
		end
	)

	t.test(
		"standing idle: the seat warns before the server would take the player off; moving, turning or firing is being there",
		function()
			local b = Kit.playing()
			local seat = b.seat
			t.eq(seat:idle(b.now()), nil)
			Kit.run(b, R.idleSecs - Tuning.idleWarn - 1)
			t.eq(seat:idle(b.now()), nil, "not yet")
			Kit.run(b, 2)
			local left = seat:idle(b.now()) :: number
			t.truthy(
				left ~= nil and left <= Tuning.idleWarn and left > Tuning.idleWarn - 2,
				"the warning, counting down"
			)
			Kit.run(b, 3)
			t.truthy((seat:idle(b.now()) :: number) < left - 2.9)
			-- a tremble the server does not count (it wants half a stud, or a twentieth of a radian) does not
			-- hush the warning: the screen is never later than the server
			b.pose.yaw += 0.04
			b.pose.x += 0.3
			Kit.frame(b)
			t.truthy(seat:idle(b.now()) ~= nil, "a tremble is not being there")
			-- nor does being tagged out and placed again: the server's count runs through both
			left = seat:idle(b.now()) :: number
			Kit.message(b, {
				kind = "paintball_tag",
				by = 2,
				id = 1,
				ball = 3,
				scores = { 0, 1 },
				tags = 1,
				outs = 1,
				at = b.now() + 2,
				x = 0,
				y = 3,
				z = 30,
			})
			Kit.run(b, 1)
			-- the warning stays up while out: the server's deadline can fall inside the wait
			local whileOut = seat:idle(b.now())
			t.truthy(whileOut ~= nil and whileOut < left - 0.9, "still counting down while tagged out")
			-- (the body put somewhere else while it waits, the view turned: no Move goes, the server sees none)
			b.pose.z += 6
			b.pose.yaw += 0.5
			Kit.run(b, 1)
			Kit.place(b, { x = -52, z = 2, yaw = 1, at = b.now() })
			Kit.frame(b, 3)
			t.truthy((seat:idle(b.now()) :: number) < left - 1.9, "out and back, and still counting down")
			-- a correction is not a respawn: the server judges the next Move from where the body was put back
			-- against the pose its count began at, so a body put back a stud away has moved, here as there
			Kit.message(b, {
				kind = "paintball_correct",
				x = -51,
				y = b.pose.y,
				z = 2,
				yaw = 1,
				why = "wall",
				place = Wire.nextPlace(seat.place),
			})
			Kit.frame(b, 3)
			t.eq(seat:idle(b.now()), nil, "put back a stud away is a move")
			Kit.run(b, R.idleSecs - Tuning.idleWarn + 1)
			-- a turn of the view is being there
			b.pose.yaw += 0.1
			Kit.frame(b)
			t.eq(seat:idle(b.now()), nil)
			-- so is a step, and so is a ball
			Kit.place(b, { x = 0, z = 30, at = b.now() })
			Kit.frame(b, 3)
			b.pose.yaw = 0
			Kit.frame(b)
			Kit.run(b, R.idleSecs - Tuning.idleWarn + 1)
			t.truthy(seat:idle(b.now()) ~= nil)
			b.pose.x += 1
			Kit.frame(b)
			t.eq(seat:idle(b.now()), nil)
			Kit.run(b, R.idleSecs - Tuning.idleWarn + 1)
			t.truthy(seat:idle(b.now()) ~= nil)
			press(b)
			Kit.frame(b)
			t.eq(seat:idle(b.now()), nil)
			-- the briefing does not count: the server counts live play
			b = Kit.bench()
			Kit.watch(b)
			Kit.state(b, { phase = "briefing", endsAt = b.now() + 200 })
			Kit.place(b)
			Kit.run(b, R.idleSecs + 5)
			t.eq(b.seat:idle(b.now()), nil)
		end
	)

	t.test(
		"the predicted ball and the server's ball agree: walls to a hundredth of a stud, bodies 95 % of the time, at 150 ms and at 30, 60 and 144 frames a second, and over a jittery link at 150 and 300 ms",
		function()
			-- A server that follows the contract to the letter, for one click: the stamps through Clock.stamp, the
			-- ball flown tick by tick from f, each step against the building (arena.sweep) and against the body
			-- where the snapshot stream puts it at (f + age) - rewind (Clock, "the history is the snapshot
			-- stream"), by Hit.body, a tie to the wall.
			type Shot = { kind: string, x: number, y: number, z: number }
			local TICK = 1 / Clock.TICK_HZ
			local function serverBall(
				arena: Arena.Arena,
				history: { { t: number, body: any } },
				rec: { [string]: number },
				arrival: number,
				up: number,
				feel: Contract.Feel
			): Shot
				local f, _late, rewind = Clock.stamp(arrival, rec.vt, rec.ft, nil, up)
				local len = math.sqrt(rec.dx ^ 2 + rec.dy ^ 2 + rec.dz ^ 2)
				local vx, vy, vz =
					rec.dx / len * feel.ballSpeed, rec.dy / len * feel.ballSpeed, rec.dz / len * feel.ballSpeed
				local function poseAt(time: number): (number, number, number, number)
					for i = #history, 1, -1 do
						if history[i].t <= time then
							local a, b = history[i], history[i + 1] or history[i]
							return Wire.between(a.body, a.t, b.body, b.t, time)
						end
					end
					local first = history[1].body
					return first.x, first.y, first.z, first.crouch
				end
				-- (its ticks are its own: off the client's frames by a few milliseconds)
				local nextTick = (math.floor((f - Kit.SERVER_TIME - 0.004) / TICK) + 1) * TICK + Kit.SERVER_TIME + 0.004
				local a0 = 0
				while a0 < R.ballTtl do
					local a1 = math.min(nextTick - f, R.ballTtl)
					local p0x, p0y, p0z = Ballistics.position(rec.ox, rec.oy, rec.oz, vx, vy, vz, feel.ballDrop, a0)
					local p1x, p1y, p1z = Ballistics.position(rec.ox, rec.oy, rec.oz, vx, vy, vz, feel.ballDrop, a1)
					local best = arena.sweep(p0x, p0y, p0z, p1x, p1y, p1z)
					local x, y, z, crouch = poseAt(f + a1 - rewind)
					local s, hx, hy, hz = Hit.body(arena.sweep, p0x, p0y, p0z, p1x, p1y, p1z, x, y, z, crouch)
					if s ~= nil and (best == nil or s < best) then
						return { kind = "body", x = hx, y = hy, z = hz }
					elseif best ~= nil then
						return {
							kind = "wall",
							x = p0x + (p1x - p0x) * best,
							y = p0y + (p1y - p0y) * best,
							z = p0z + (p1z - p0z) * best,
						}
					end
					a0 = a1
					nextTick += TICK
				end
				return { kind = "none", x = 0, y = 0, z = 0 }
			end

			local feel = Contract.feel({ reloadSecs = 0.5 })
			local seed = 20261113
			local function rand(): number
				seed = (seed * 1103515245 + 12345) % 2147483648
				return seed / 2147483648
			end
			-- the jitter of a link (its own seed: the aim of the steady cases is not moved by it)
			local jseed = 4111
			local function jitter(width: number): number
				if width <= 0 then
					return 0
				end
				jseed = (jseed * 1103515245 + 12345) % 2147483648
				return (jseed / 2147483648 * 2 - 1) * width
			end
			-- the opponent: walking east and west along z = 4 beyond the rail, ducking behind it now and then
			local function target(time: number): (number, number)
				local tau = time - Kit.SERVER_TIME
				return 12 * math.sin(1.3 * tau), math.clamp(math.sin(0.9 * tau) * 4 - 2, 0, 1)
			end
			local total, worstWall, worstBody = 0, 0, 0
			for _, case in
				{
					{ dt = 1 / 60, lag = 0, shots = 150 },
					{ dt = 1 / 60, lag = 0.075, shots = 150 },
					{ dt = 1 / 30, lag = 0.075, shots = 150 },
					{ dt = 1 / 144, lag = 0.075, shots = 150 },
					-- a jittery link: each snapshot, each pose and each click on its way a random time, so the
					-- client's view lag and the server's `up` (both Clock.observe: quick up, slow down) sit near
					-- the top of the band; at 300 ms the picture is further back than Clock.MAX_REWIND
					{ dt = 1 / 60, lag = 0.075, jitter = 0.025, shots = 150 },
					{ dt = 1 / 60, lag = 0.15, jitter = 0.03, shots = 150 },
					{ dt = 1 / 30, lag = 0.15, jitter = 0.03, shots = 150 },
				}
			do
				local b = Kit.bench({ dt = case.dt })
				Kit.watch(b, nil, { feel = feel })
				Kit.state(b, { phase = "live", feel = feel, endsAt = b.now() + 5000 })
				Kit.place(b)
				local history: { { t: number, body: any } } = {}
				local buffers: { buffer } = {}
				local taken, delivered = 0, 0
				local spread = (case :: any).jitter or 0
				local arrives: { number } = {} -- when each snapshot reaches the client
				local pending: { number } = {}
				-- one frame of the client's, with the server's snapshots reaching it `lag` late
				local function frame()
					b.frames += 1
					local now = b.now()
					while Kit.SERVER_TIME + taken / Clock.SNAP_HZ <= now do
						local time = Kit.SERVER_TIME + taken / Clock.SNAP_HZ
						local x, crouch = target(time)
						local buf =
							Wire.encodeSnap(time, taken, b.show.match, { Kit.body(2, x, 0, 4, { crouch = crouch }) })
						local _, _, _, bodies = Wire.decodeSnap(buf)
						taken += 1
						history[taken] = { t = time, body = bodies[1] } -- (as the wire carries it: quantised)
						buffers[taken] = buf
						arrives[taken] = time + math.max(0, case.lag + jitter(spread))
						table.insert(pending, taken)
					end
					-- (in the order they arrive, which a jittery link does not keep)
					for i = #pending, 1, -1 do
						if arrives[pending[i]] <= now then
							delivered += 1
							b.show:onSnap(buffers[pending[i]])
							table.remove(pending, i)
						end
					end
					b.show:step(b.dt)
					b.seat:step(b.dt)
				end
				for _ = 1, math.ceil(1 / case.dt) do
					frame()
				end
				local seen: { Shot } = {}
				local flight = 26 / feel.ballSpeed
				for n = 1, case.shots do
					for _ = 1, math.ceil(1 / case.dt) do
						if b.seat:ready(b.now()) then
							break
						end
						frame() -- (the marker's own rhythm: the interval, and the reload after every fifth)
					end
					-- aim somewhere round where the opponent will be drawn when the ball gets there: on it, beside
					-- it, over its head, into the rail in front of it
					local x = target(b.now() + flight - case.lag - Clock.INTERP_SECS)
					local ax, ay = x + (rand() - 0.5) * 4, 3.3 + rand() * 2.9
					b.pose.yaw, b.pose.pitch = Body.yawPitch(ax - 0, ay - Body.STAND_EYE, 4 - 30)
					local puffs = #b.show.puffs
					press(b)
					for _ = 1, math.ceil(1 / case.dt) do
						if #Kit.fires(b) >= n then
							break
						end
						frame()
					end
					t.eq(#Kit.fires(b), n, "the ball left")
					for _ = 1, math.ceil(2 / case.dt) do
						local flying = false
						for _, ball in b.show.balls do
							flying = flying or ball.own
						end
						if not flying then
							break
						end
						frame()
					end
					local shot = Kit.fires(b)[n].shot
					local mine: Shot = { kind = "none", x = 0, y = 0, z = 0 }
					if #b.show.puffs > puffs then
						local puff = b.show.puffs[#b.show.puffs]
						mine = { kind = "body", x = puff.x, y = puff.y, z = puff.z }
					else
						for _, splat in b.show.walls do
							if splat.predicted and splat.shot == shot then
								mine = { kind = "wall", x = splat.x, y = splat.y, z = splat.z }
							end
						end
					end
					seen[n] = mine
				end
				for _ = 1, math.ceil(2 / case.dt) do
					frame()
				end
				-- the server's verdict on every click, each `lag` late on its way up (and with the jitter, each pose
				-- a random time on its way, the server's `up` fed through Clock.observe as the service feeds it,
				-- and a click arriving with the pose it carries)
				local fires = Kit.fires(b)
				local poses: { { t: number, at: number } } = {}
				for _, move in Kit.moves(b) do
					table.insert(poses, { t = move.t, at = move.t + math.max(0, case.lag + jitter(spread)) })
				end
				table.sort(poses, function(p: { t: number, at: number }, q: { t: number, at: number }): boolean
					return p.at < q.at
				end)
				local function upAt(rec: { [string]: number }): (number, number)
					if spread <= 0 then
						return rec.ft + case.lag, case.lag
					end
					local arrival = rec.ft + case.lag
					for _, pose in poses do
						if pose.t == rec.ft then
							arrival = pose.at
						end
					end
					local view = Clock.newView()
					for _, pose in poses do
						if pose.at > arrival then
							break
						end
						Clock.observe(view, pose.t, pose.at)
					end
					return arrival, view.lag or case.lag
				end
				local agree, kinds = 0, { body = 0, wall = 0, none = 0 }
				for n, mine in seen do
					local rec = fires[n]
					local arrival, up = upAt(rec)
					local theirs = serverBall(b.arena, history, rec, arrival, up, feel)
					kinds[theirs.kind] += 1
					if mine.kind == theirs.kind then
						agree += 1
						local d = math.sqrt((mine.x - theirs.x) ^ 2 + (mine.y - theirs.y) ^ 2 + (mine.z - theirs.z) ^ 2)
						if mine.kind == "wall" then
							worstWall = math.max(worstWall, d)
						elseif mine.kind == "body" then
							worstBody = math.max(worstBody, d)
						end
					end
				end
				total += #seen
				print(
					`      {math.floor(1 / case.dt + 0.5)} fps, {math.floor(case.lag * 2000 + 0.5)} ms round trip{if spread
							> 0
						then ` (each way +/- {math.floor(spread * 1000 + 0.5)} ms)`
						else ""}: {agree} of {#seen} balls end as the server's do ({kinds.body} on the body, {kinds.wall} on the building, {kinds.none} spent)`
				)
				t.truthy(
					kinds.body >= #seen * 0.2 and kinds.wall >= #seen * 0.15,
					"the aim was spread over body and building"
				)
				t.truthy(agree >= #seen * 0.95, `{agree} of {#seen} agree (PB-3: at least 95 %)`)
			end
			t.truthy(total >= 1050)
			print(
				`      worst distance between the two ends: {string.format("%.4f", worstWall)} studs on a wall, {string.format(
					"%.3f",
					worstBody
				)} on a body`
			)
			t.truthy(worstWall < 0.01, "on the building the predicted splat is where the server's record will be")
			t.truthy(worstBody < Tuning.predictedSplatSnap, "and on a body, inside the tolerance")
		end
	)

	t.test("the engine check (the lane's task for the real engine) runs its cores part here and holds", function()
		-- (the task script finds the engine missing under Lune, loads the client's files off the disk and
		-- says the engine's own facts were not asked: what is proved here is that the task itself is sound)
		local report = (require :: any)("../../tools/games/paintball/client/engine_check")
		t.eq(report.suite, "PaintballClientEngine")
		t.eq(#report.failures, 0, table.concat(report.failures, " | "))
		t.truthy(report.ok)
		t.eq(#report.notes, 1)
		t.truthy(string.find(report.notes[1], "no engine here", 1, true))
		local splat = report.numbers.predictedSplat
		t.near(splat.z, -40, 1e-3, "the predicted ball ended on the wall")
		t.near(splat.y, splat.wantY, 1e-3, "as low as Ballistics says")
		t.truthy(splat.wantY < Body.STAND_EYE - 2, "having dropped on the way")
		t.near(report.numbers.pace.sprint, F.sprintMult, 1e-6)
		t.near(report.numbers.pace.eye, Body.CROUCH_EYE - Body.STAND_EYE, 1e-6)
		t.truthy(report.numbers.puppetLagStuds > 0.5, "the puppet is drawn in the past")
	end)
end
