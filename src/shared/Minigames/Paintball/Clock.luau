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
-- never compared with a stamp: paintball reads it only to see how long the end card has been up.
-- THE MATCH MODEL IS SLAVED TO THE SHARED CLOCK: the service calls Rules.sync(state, ctx.stamp()) on
-- "start" and at the top of every step, and Rules.step then moves the phases and the respawns up to
-- that time and no further. The model never counts a clock of its own from the steps it is handed
-- (the framework clamps a long server frame to 0.1 s, so a count would fall behind at every hitch and
-- every magazine and respawn time, which are set from shared-clock stamps, would be judged late).
--
-- THE RATES. The server steps balls and bots every Heartbeat (TICK_HZ nominal, with the real dt). It
-- sends one snapshot of every body SNAP_HZ times a second, and the client sends its own pose SEND_HZ
-- times a second.
--
-- THE HISTORY IS THE SNAPSHOT STREAM. This is the rule that makes hits agree with what the shooter
-- saw. At each snapshot tick T the server (1) takes each body's pose, (2) quantises it exactly as the
-- snapshot carries it (Wire.quantPose), (3) pushes that quantised pose into the body's pose history
-- (Server/Paintball/PoseHistory, HISTORY_SECS long at SNAP_HZ) stamped T, and (4) sends the snapshot
-- with that same T. A client draws every other body at its VIEW TIME by straight-line interpolation
-- between the two snapshots either side of it (held at the newest, never run ahead), which is exactly
-- what PoseHistory.sample does on the server. So when a shot says "I was looking at view time vt",
-- the server's rewound bodies are, number for number, the bodies that were on the shooter's screen.
-- Bots and people are the same here: both are drawn only from snapshots.
-- WHICH POSE IS "A BODY'S POSE" AT TICK T (step 1).
--   a bot      its present pose (the brain moves it every tick).
--   a person   NOT the last Move that happened to arrive (Moves come 50 ms apart with jitter, a 30 fps
--              phone sends them 33 or 67 ms apart: some ticks would see none and some two, and the
--              puppet would stand and then jump, a hit radius at a time). The server keeps the last
--              MOVES_KEPT accepted Moves of each person with their own t and keeps `up`, the smoothed
--              delay between a Move's t and its arrival (observe, on a View of its own per person). The
--              pose at tick T is the straight line between the two Moves either side of
--              poseTime(up, T) = T - up - one send interval, held at the newest (yaw, pitch and the
--              bits are the newer Move's; the crouch FRACTION is the server's own). One send interval
--              back, there is nearly always a Move on each side, so the puppet moves evenly. That
--              value is what is quantised, pushed and sent, so the keystone above still holds.
--
-- VIEW TIME. The client keeps `lag`, how far behind the server's clock its newest snapshot arrives
-- (observe), and draws at now - lag - INTERP_SECS (viewTime): two snapshot intervals back, so one lost
-- snapshot never leaves it without a pair to interpolate. View time never runs backwards.
--
-- A SHOT carries two stamps: ft, the server time of the click, and vt, the view time on screen at the
-- click. The server (stamp) is also given `up`, the shooter's own smoothed upstream delay (above: it
-- always has one, because a slot whose Moves have stopped cannot fire), and gets:
--   magazine time  m = ft held inside [now - MAG_LATE, now + clockSlack] and never before this
--              shooter's last m. The MAGAZINE is judged at m, so honest shots a fire interval apart
--              are never refused "too fast" however the network bunched them, or delayed the first.
--              (What a liar gains: after MAG_LATE without firing, at most MAG_LATE / fireInterval
--              balls born together: two extra at the default feel.)
--   fire time  f = ft held inside [now - lateMax, now], lateMax = min(MAX_LATE, up + REWIND_TOLERANCE).
--              The ball is BORN at f, and phase, out and protection are judged at f (Rules.fire).
--              A client that always claims the oldest fire time it may is bound by its own measured
--              delay: at most REWIND_TOLERANCE of free flight (under 7 studs), not MAX_LATE's 22.
--   late       now - f: how long the ball has already been flying on the shooter's screen. The server
--              flies its ball forward by that much at once, against the bodies of those past moments,
--              so the verdict reaches the shooter one upstream delay sooner.
--   rewind     f - vt held inside [0, MAX_REWIND], and inside (up + INTERP_SECS) +/- REWIND_TOLERANCE:
--              the server's own estimate of how far behind the shooter's picture was, taking the way
--              down to be as long as the way up. Through the whole flight the ball at age a is tested
--              against bodies at time (f + a) - rewind, which is what Projectiles.step does with
--              `now - ball.rewind`. `clamped` says the claim was outside those bounds (Stats counts
--              them: a connection whose two ways differ by more than the tolerance shows up there).
-- A client that lies about vt can move its targets by at most REWIND_TOLERANCE of their motion. (A
-- client that back-dates its Moves as well, to raise `up`, has made itself a slow connection in every
-- respect, its own body drawn that much later too; MAX_LATE and MAX_REWIND are what bound that, as
-- they bound a truly slow one.)
-- MAX_REWIND is 0.25 s, not the S18 core's 0.4: it covers a steady 300 ms round trip (0.15 down + the
-- interpolation), and it is how long after ducking behind a rail a body can still be tagged by what a
-- slow shooter saw. A JITTERY 300 ms link sits near the top of its band (observe rises fast and falls
-- slowly), so there about 90 % of shots agree with the shooter's screen, not 95 %: 0.3 s would mend it,
-- at the price of shots landing later behind cover. The owner's call at the playtest
-- (PaintballService debug("rewind", s) tries it on one server; the client's drawing keeps this number).
--
-- SILENCE. A player whose move stream stops for STALE_SECS keeps the last pose it sent: it stands
-- still, can be hit, and cannot fire. After DROP_SECS it is taken out of the match and a bot takes the
-- slot (the framework's ctx.leave with why "dropped"; Contract, decision 9). A player who is connected
-- but has not moved, turned or fired for Contract.Rules.idleSecs of "live" goes the same way ("idle").
-- Interface: constants; newView() -> View; observe(view, stampTime, now); viewTime(view, now) -> t;
--   poseTime(up, now) -> t; stamp(now, vt, ft, lastM?, up?) -> (f, late, rewind, clamped, m)

local Config = require("../../Paintball/Config")
local Contract = require("./Contract")

-- A smoothed delay: on a client, how late snapshots arrive (the view); on the server, how late one
-- person's Moves arrive (`up`).
export type View = { lag: number?, last: number }

local Clock = {}

Clock.TICK_HZ = 60 -- the server's step (Heartbeat): balls, bots, the match clock
Clock.SNAP_HZ = 20 -- snapshots of every body, server to audience; also the pose history's rate
Clock.SEND_HZ = 20 -- the client's own pose, client to server
Clock.INTERP_SECS = 0.1 -- two snapshot intervals
Clock.HISTORY_SECS = Config.historySecs -- 1.0
Clock.MAX_REWIND = 0.25 -- the furthest back a ball is judged (the S18 core's 0.4 is its harness's own)
Clock.MAX_LATE = 0.25 -- the most a ball's birth may trail its arrival
Clock.MAG_LATE = 0.5 -- the most a shot's magazine time may trail its arrival
Clock.REWIND_TOLERANCE = 0.075 -- the S18 timestamp tolerance round the server's own estimate
Clock.MOVES_KEPT = 12 -- accepted Moves the server keeps per person (0.6 s: past MAX_LATE and any `up`)
Clock.STALE_SECS = 0.5 -- move stream silent this long: the body holds its pose and cannot fire
Clock.DROP_SECS = 5 -- silent this long: out of the match, a bot takes the slot
Clock.AUDIENCE_SECS = 0.5 -- how often the server looks who is near enough to be in the audience

function Clock.newView(): View
	return { lag = nil, last = -math.huge }
end

-- Call for every stamped message that arrives: `stampTime` is its stamp (a snapshot's t on a client, a
-- Move's t on the server), `now` the shared clock at arrival. The lag rises quickly (a late packet
-- must not leave the view ahead of the data) and falls slowly.
function Clock.observe(view: View, stampTime: number, now: number)
	local lag = math.max(0, now - stampTime)
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

-- The time a person's pose is read from its Move buffer at for the snapshot tick `now` (the server;
-- `up` is that person's own View, fed by observe with each accepted Move); never decreases.
function Clock.poseTime(up: View, now: number): number
	local t = now - (up.lag or 0) - 1 / Clock.SEND_HZ
	if t < up.last then
		t = up.last
	end
	up.last = t
	return t
end

-- The server's reading of a shot's two stamps. `lastM` is the magazine time of this shooter's last
-- accepted shot, `up` its smoothed upstream delay in seconds (the lag of its Moves' View; nil: none,
-- which only a spec meets). Returns the fire time, how late the ball is, the rewind, whether the
-- rewind was clamped, and the magazine time.
function Clock.stamp(
	now: number,
	vt: number,
	ft: number,
	lastM: number?,
	up: number?
): (number, number, number, boolean, number)
	local lateMax = Clock.MAX_LATE
	local lo, hi = 0, Clock.MAX_REWIND
	if up ~= nil then
		lateMax = math.min(lateMax, up + Clock.REWIND_TOLERANCE)
		local estimate = up + Clock.INTERP_SECS
		lo = math.max(lo, estimate - Clock.REWIND_TOLERANCE)
		hi = math.max(lo, math.min(hi, estimate + Clock.REWIND_TOLERANCE))
	end
	local f = math.clamp(ft, now - lateMax, now)
	local m = math.clamp(ft, now - Clock.MAG_LATE, now + Contract.TRUST.clockSlack)
	if lastM ~= nil and m < lastM then
		m = lastM
	end
	local want = f - vt
	local rewind = math.clamp(want, lo, hi)
	return f, now - f, rewind, rewind ~= want, m
end

return Clock
