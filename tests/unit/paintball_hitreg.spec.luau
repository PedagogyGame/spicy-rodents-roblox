--!strict
-- Shared/Paintball + Server/Paintball (spike S18, D29): magazine and reload, ballistics, the pose
-- ring buffer, the splat pool cap, and the hit-registration harness at 150 ms (>= 95 % agreement
-- with the shooter's view, the plan's criterion).
local Config = require("@shared/Paintball/Config")
local Ballistics = require("@shared/Paintball/Ballistics")
local Magazine = require("@shared/Paintball/Magazine")
local PoseHistory = require("@server/Paintball/PoseHistory")
local Splats = require("@server/Paintball/Splats")
local Projectiles = require("@server/Paintball/Projectiles")
local Harness = require("@server/Paintball/Harness")

local function run(opts: Harness.Opts, frames: number): { [string]: any }
	local h = Harness.new(opts)
	for _ = 1, frames do
		Harness.step(h, 1 / 60)
	end
	return Harness.report(h)
end

return function(t)
	t.test("five shots, fire interval, automatic reload after the last ball", function()
		local m = Magazine.new(5, 0.25, 1.6)
		local now = 0
		for _ = 1, 5 do
			t.truthy(Magazine.fire(m, now))
			t.falsy(Magazine.fire(m, now + 0.1), "fire interval")
			now += 0.25
		end
		t.eq(m.rounds, 0)
		t.truthy(m.reloadDoneAt ~= nil, "auto reload started")
		t.falsy(Magazine.canFire(m, now + 1.0))
		t.truthy(Magazine.canFire(m, 1.0 + 1.6))
		t.eq(m.rounds, 5)
	end)
	t.test(
		"manual reload (R) only when not full; a press during it cancels it and fires; left alone it fills",
		function()
			local m = Magazine.new(5, 0.25, 1.6)
			t.falsy(Magazine.reload(m, 0), "full magazine")
			Magazine.fire(m, 0)
			t.truthy(Magazine.reload(m, 0.3))
			t.truthy(Magazine.fire(m, 1.0), "the paintball review: a press cancels a reload asked for with balls left")
			t.eq(m.reloadDoneAt, nil)
			t.eq(m.rounds, 3)
			t.truthy(Magazine.reload(m, 1.3))
			Magazine.update(m, 3.0)
			t.eq(m.rounds, 5)
		end
	)
	t.test("analytic flight drops 4.9 studs in a second; aim compensates drop", function()
		local _, y, _ = Ballistics.position(0, 10, 0, 90, 0, 0, Config.projectile.drop, 1)
		t.near(y, 10 - 4.9, 1e-9)
		local vx, vy, vz = Ballistics.aim(0, 5, 0, 60, 5, 0, 90, Config.projectile.drop)
		t.near(math.sqrt(vx * vx + vy * vy + vz * vz), 90, 1e-9)
		local tof = 60 / vx
		local _, y2, _ = Ballistics.position(0, 5, 0, vx, vy, vz, Config.projectile.drop, tof)
		t.near(y2, 5, 0.05)
	end)
	t.test("segment vs capsule and box", function()
		t.near(Ballistics.segmentCapsule(-5, 2, 0, 5, 2, 0, 0, 1, 4, 0, 1) :: number, 0.5, 1e-9, "closest approach")
		t.eq(Ballistics.segmentCapsule(-5, 2, 3, 5, 2, 3, 0, 1, 4, 0, 1), nil)
		local s, nx, ny, nz = Ballistics.segmentBox(-5, 1, 0, 5, 1, 0, 1, 0, -1, 2, 2, 1)
		t.near(s :: number, 0.6, 1e-9)
		t.deepEq({ nx, ny, nz }, { -1, 0, 0 })
		t.eq((Ballistics.segmentBox(-5, 5, 0, 5, 5, 0, 1, 0, -1, 2, 2, 1)), nil)
	end)
	t.test("pose history: 1 s ring, interpolated, clamped", function()
		local h = PoseHistory.new(1, 60)
		for f = 0, 180 do
			PoseHistory.push(h, f / 60, f, 0, -f)
		end
		t.eq(h.count, h.cap)
		t.near(PoseHistory.span(h), (h.cap - 1) / 60, 1e-9)
		local x, _, z = PoseHistory.sample(h, 2.5 + 0.5 / 60)
		t.near(x, 150.5, 1e-9)
		t.near(z, -150.5, 1e-9)
		t.eq((PoseHistory.sample(h, 99)), 180)
		t.eq((PoseHistory.sample(h, 0)), 180 - h.cap + 1, "older than the window: the oldest sample")
	end)
	t.test("splat pool never exceeds its cap", function()
		local pool = Splats.new(4)
		for i = 1, 10 do
			Splats.add(pool, i, 0, 0, 0, 1, 0, 1)
		end
		t.eq(Splats.size(pool), 4)
		t.eq(pool.overwritten, 6)
		Splats.clear(pool)
		t.eq(Splats.size(pool), 0)
	end)
	t.test("a rewound ball hits where the target was, not where it is", function()
		local target = { id = 1, team = 1, history = PoseHistory.new(1, 60) }
		local function xAt(time: number): number
			return -10 + 20 * time -- moving +x at 20 studs/s, 20 studs from the shooter
		end
		for f = 0, 60 do
			PoseHistory.push(target.history, f / 60, xAt(f / 60), 0, 20)
		end
		-- the ball needs 14 frames to cover 20 studs; aim where the target was 150 ms before that
		local arrival = 1 + 14 / 60
		local aimX = xAt(arrival - 0.15)
		local sim = Projectiles.new({}, nil)
		local rewound = Projectiles.fire(sim, 2, 0, aimX, 3, 0, 0, 0, 90, 0.15)
		local naive = Projectiles.fire(sim, 2, 0, aimX, 3, 0, 0, 0, 90, 0)
		for f = 61, 90 do
			local now = f / 60
			PoseHistory.push(target.history, now, xAt(now), 0, 20)
			Projectiles.step(sim, now, 1 / 60, { target })
		end
		t.eq(rewound.hitBody, 1)
		t.eq(naive.hitBody, 0)
		local clamped = Projectiles.fire(sim, 2, 0, 0, 3, 0, 0, 0, 90, 5)
		t.eq(clamped.rewind, Config.maxRewindSecs)
	end)
	t.test("harness at 150 ms: >= 95 % agreement over >= 200 shots; splats capped; bodies move", function()
		local r = run({ shooters = 16, bots = 10, rttMs = 150, seed = 18 }, 1200)
		t.truthy(r.shots >= 200, `shots {r.shots}`)
		t.truthy(r.agreement >= 0.95, `agreement {r.agreement}`)
		t.truthy(r.agreement > r.agreementNaive + 0.2, "lag compensation matters at 150 ms")
		t.truthy(r.splats.max <= Config.splatPool)
		t.eq(r.stuckBodies, 0)
		t.truthy(r.autoReloads > 0)
		t.truthy(r.botShots > 0)
	end)
	t.test("harness: estimate-only rewind still meets 95 % at 150 ms with 12 % jitter", function()
		local r = run({ shooters = 16, bots = 10, rttMs = 150, seed = 19, rewindMode = "estimate" }, 1800)
		t.truthy(r.agreement >= 0.95, `agreement {r.agreement}`)
	end)
	-- THE CONTRACT'S CONDITION (Harness, opts.contract): the match's own judgment end to end. The only history
	-- is the 20 Hz quantised snapshot stream; each client draws from the snapshots it was actually sent (5 % of
	-- them lost, each late by half the round trip with 12 % jitter) at its own view time, aims at that, stamps
	-- its click and flies its own ball against what it draws; the server stamps the click with Clock.stamp
	-- and the shooter's measured upstream delay, and judges with Hit.body in the match's own sim. The runners
	-- crouch and stand. Measured where this was written, about 600 shots a run: 99.7 to 100 % at 0 ms, 100 %
	-- at 80 ms, 99.4 to 99.6 % at 150 ms, 99.5 % at 200 ms; without the rewind 48 to 76 %.
	for _, rtt in { 0, 80, 150 } do
		t.test(
			`the contract's condition at {rtt} ms: >= 95 % agreement with the shooter's screen over >= 400 shots, with lost snapshots and crouching runners`,
			function()
				local r = run({ contract = true, shooters = 16, bots = 10, rttMs = rtt, seed = 18, loss = 0.05 }, 1800)
				t.truthy(r.shots >= 400, `shots {r.shots}`)
				t.truthy(r.agreement >= 0.95, `agreement {r.agreement}`)
				t.truthy(
					r.truthHits >= 100 and r.truthHits <= r.shots - 100,
					"hits and misses were both put to the test"
				)
				t.truthy(r.agreement > r.agreementNaive + 0.15, "and the rewind is what does it")
				t.truthy(r.snapshotsLost > 0.03 * r.snapshotsSent, "snapshots were lost on the way")
				t.truthy(r.rewindsClamped <= 2, `{r.rewindsClamped} honest stamps were clamped`)
				t.eq(r.stuckBodies, 0)
				t.truthy(r.botShots > 0)
			end
		)
	end
	t.test(
		"the contract's condition at 300 ms: every stamp is at the edge of MAX_REWIND and clamped, and agreement is still >= 90 %",
		function()
			-- (0.15 s down, the 0.1 s of interpolation and the jitter are past Clock.MAX_REWIND's quarter of a second:
			-- measured 93 to 96 %. That bound is the contract's choice: it is how long after ducking a body can
			-- still be tagged)
			local r = run({ contract = true, shooters = 16, bots = 10, rttMs = 300, seed = 18, loss = 0.05 }, 1800)
			t.truthy(r.shots >= 400, `shots {r.shots}`)
			t.truthy(r.agreement >= 0.9, `agreement {r.agreement}`)
			t.truthy(r.rewindsClamped > r.shots / 2, "the server held the rewind to its bound")
			t.truthy(r.agreement > r.agreementNaive + 0.3)
		end
	)
end
