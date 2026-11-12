--!strict
-- ReplicatedStorage.Shared.Minigames.Paintball.Clock
-- Time in the paintball contract (checklist PB-1, PB-3): the rates, and how a shot is stamped by the
-- client and clamped by the server for lag compensation. FROZEN: no lane edits this file.
--
-- ONE CLOCK. Every paintball time (on the wire, in the match model, in the bots, in the pose
-- histories) is THE SHARED CLOCK in seconds: the minigame framework's ctx.stamp() on both sides, which
-- is workspace:GetServerTimeNow() in the engine (Roblox keeps the client's copy within a few
-- milliseconds) and the rig's own in the Lune tests. No message carries a client-local time and there
-- is no clock sync of our own. The framework's OTHER clock, the service's ctx.now() (seconds of
-- stepping since boot), is never put on the wire, never handed to Rules, Bots or a pose history and
-- never compared with a stamp: paintball reads it only to see how long the end card has been up. The
-- match model (Rules) is told the shared clock once a match (Rules.sync) and counts on from there
-- with the steps the Session hands it; the service puts it right again if it strays SYNC_SLACK.
--
-- THE RATES. The server steps balls and bots every Heartbeat (TICK_HZ nominal, with the real dt). It
-- sends one snapshot of every body SNAP_HZ times a second, and the client sends its own pose SEND_HZ
-- times a second.
--
-- THE HISTORY IS THE SNAPSHOT STREAM. This is the rule that makes hits agree with what the shooter
-- saw. At each snapshot tick the server (1) takes each body's pose, (2) quantises it exactly as the
-- snapshot carries it (Wire.quantPose), (3) pushes that quantised pose into the body's pose history
-- (Server/Paintball/PoseHistory, HISTORY_SECS long at SNAP_HZ) stamped with the snapshot's time, and
-- (4) sends the snapshot with that same time. A client draws every other body at its VIEW TIME by
-- straight-line interpolation between the two snapshots either side of it (held at the newest, never
-- run ahead), which is exactly what PoseHistory.sample does on the server. So when a shot says "I was
-- looking at view time vt", the server's rewound bodies are, number for number, the bodies that were
-- on the shooter's screen. Bots and people are the same here: both are drawn only from snapshots.
--
-- VIEW TIME. The client keeps `lag`, how far behind the server's clock its newest snapshot arrives
-- (observe), and draws at now - lag - INTERP_SECS (viewTime): two snapshot intervals back, so one lost
-- snapshot never leaves it without a pair to interpolate. View time never runs backwards.
--
-- A SHOT carries two stamps: ft, the server time of the click, and vt, the view time on screen at the
-- click. The server (stamp) clamps both and gets:
--   fire time  f = ft held inside [now - MAX_LATE, now] and never before this shooter's last shot. The
--              magazine is judged at f, not at arrival, so two honest shots 0.25 s apart are never
--              refused because the network bunched them, and nobody gains more than one early ball.
--   late       now - f: how long the ball has already been flying on the shooter's screen. The server
--              flies its ball forward by that much at once, against the bodies of those past moments,
--              so the verdict reaches the shooter one upstream delay sooner.
--   rewind     f - vt held inside [0, MAX_REWIND], and inside the server's own estimate +/-
--              REWIND_TOLERANCE when it has one (half the measured round trip + INTERP_SECS). Through
--              the whole flight the ball at age a is tested against bodies at time (f + a) - rewind,
--              which is what Projectiles.step does with `now - ball.rewind`.
-- A client that lies about vt can move its targets by at most REWIND_TOLERANCE of their motion.
--
-- SILENCE. A player whose move stream stops for STALE_SECS keeps the last pose it sent: it stands
-- still, can be hit, and cannot fire. After DROP_SECS it is taken out of the match and a bot takes the
-- slot (the framework's ctx.leave with why "dropped"; Contract, decision 9).
-- Interface: constants; newView() -> View; observe(view, snapTime, now); viewTime(view, now) -> t;
--   stamp(now, vt, ft, lastFt?, estimate?) -> (f, late, rewind, clamped)

local Config = require("../../Paintball/Config")

export type View = { lag: number?, last: number }

local Clock = {}

Clock.TICK_HZ = 60 -- the server's step (Heartbeat): balls, bots, the match clock
Clock.SNAP_HZ = 20 -- snapshots of every body, server to audience; also the pose history's rate
Clock.SEND_HZ = 20 -- the client's own pose, client to server
Clock.INTERP_SECS = 0.1 -- two snapshot intervals
Clock.HISTORY_SECS = Config.historySecs -- 1.0
Clock.MAX_REWIND = Config.maxRewindSecs -- 0.4
Clock.MAX_LATE = 0.25 -- the most a shot's fire time may trail its arrival
Clock.REWIND_TOLERANCE = 0.075 -- the S18 timestamp tolerance round the server's own estimate
Clock.STALE_SECS = 0.5 -- move stream silent this long: the body holds its pose and cannot fire
Clock.DROP_SECS = 5 -- silent this long: out of the match, a bot takes the slot
Clock.SYNC_SLACK = 0.1 -- Rules' own count may stray this far from the shared clock before it is put right
Clock.AUDIENCE_SECS = 0.5 -- how often the server looks who is near enough to be in the audience

function Clock.newView(): View
	return { lag = nil, last = -math.huge }
end

-- Call for every snapshot that arrives: `snapTime` is its stamp, `now` the client's server time.
-- The lag rises quickly (a late packet must not leave the view ahead of the data) and falls slowly.
function Clock.observe(view: View, snapTime: number, now: number)
	local lag = math.max(0, now - snapTime)
	local held = view.lag
	if held == nil then
		view.lag = lag
	elseif lag > held then
		view.lag = held + (lag - held) * 0.5
	else
		view.lag = held + (lag - held) * 0.05
	end
end

-- The server time the client should be drawing other bodies at; never decreases.
function Clock.viewTime(view: View, now: number): number
	local t = now - (view.lag or 0) - Clock.INTERP_SECS
	if t < view.last then
		t = view.last
	end
	view.last = t
	return t
end

-- The server's reading of a shot's two stamps. `lastFt` is the fire time of this shooter's last
-- accepted shot, `estimate` the server's own figure for the shooter's view delay (nil: none).
-- Returns the fire time, how late the ball is, the rewind, and whether the rewind was clamped.
function Clock.stamp(
	now: number,
	vt: number,
	ft: number,
	lastFt: number?,
	estimate: number?
): (number, number, number, boolean)
	local f = math.clamp(ft, now - Clock.MAX_LATE, now)
	if lastFt ~= nil and f < lastFt then
		f = math.min(lastFt, now)
	end
	local lo, hi = 0, Clock.MAX_REWIND
	if estimate ~= nil then
		lo = math.max(lo, estimate - Clock.REWIND_TOLERANCE)
		hi = math.max(lo, math.min(hi, estimate + Clock.REWIND_TOLERANCE))
	end
	local want = f - vt
	local rewind = math.clamp(want, lo, hi)
	return f, now - f, rewind, rewind ~= want
end

return Clock
