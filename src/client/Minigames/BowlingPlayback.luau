--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.BowlingPlayback
-- Draws a bowling throw on this screen. The server decides a throw the moment it is let go and sends one
-- RollScript table to everyone (Net "Minigame.State" kind "roll"); this module plays that table back on the
-- real lane parts every rendered frame: the ball down the lane and into the pit, each pin tipping the way it
-- was pushed and sliding. It simulates nothing (so no two screens can disagree, and what you see is what is
-- scored); it exists because anchored parts moved by the server alone arrive at the network rate and would
-- stutter. While a throw plays, every pin of the rack and the ball are written each frame (the server moves
-- only the ball in flight, coarsely, and that never shows through); the last write is the script's final
-- pose, which is exactly where the server puts everything when it counts the throw (both use
-- Shared/Minigames/Bowling/PartPose); the final pose is held for TAIL seconds so the server's own copy has
-- arrived before this lets go, and then the server's pinsetter takes over. If a lane has not streamed in, or the script is damaged, nothing is played and the
-- server's copy is what shows: a throw can never break on a client.
-- Pins that fall into the pit are hidden with LocalTransparencyModifier (never replicated, reset when the
-- throw ends: by then the server has hidden them itself).
-- Interface: play(place, lane, script, onCue?) -> bool (script already checked by RollScript.check);
--   stop(lane, place?, mask?) (cut a throw short; with a mask, show that rack standing and the ball on its
--   rack); now(lane) -> seconds into the throw being played, or nil; playing(lane) -> bool; TAIL; clock
--   (os.clock; a test swaps it)

local Import = require("../Import")
local PartPose =
	Import.shared("Minigames/Bowling/PartPose") :: typeof(require("../../shared/Minigames/Bowling/PartPose"))
local RollScript =
	Import.shared("Minigames/Bowling/RollScript") :: typeof(require("../../shared/Minigames/Bowling/RollScript"))

local BowlingPlayback = {}

BowlingPlayback.TAIL = 0.6 -- seconds held on the final pose (the server counts 0.25 s after the end and sweeps 0.9 s later)
BowlingPlayback.BIND = "SpicyBowlingPlayback"
BowlingPlayback.clock = os.clock

type PinParts = { model: Model, home: CFrame, parts: { BasePart }, hidden: boolean }
type Entry = {
	place: any,
	lane: number,
	script: any,
	t0: number,
	ball: BasePart?,
	pins: { [number]: PinParts },
	cues: { { any } },
	cueAt: number,
	onCue: ((name: string, volume: number) -> ())?,
}

local active: { [number]: Entry } = {}
local bound = false

local function laneModel(lane: number): Instance?
	local att = workspace:FindFirstChild("Attractions")
	local alley = att and att:FindFirstChild("BowlingAlley")
	local lanes = alley and alley:FindFirstChild("Lanes")
	return lanes and lanes:FindFirstChild(`Lane{lane}`)
end

-- The lane's parts as they are on this client right now (anything missing is simply left out).
local function find(lane: number): (BasePart?, { [number]: PinParts })
	local pins: { [number]: PinParts } = {}
	local model = laneModel(lane)
	if model == nil then
		return nil, pins
	end
	local ball = model:FindFirstChild("Ball")
	local folder = model:FindFirstChild("Pins")
	if folder then
		for n = 1, 10 do
			local pm = folder:FindFirstChild(`Pin{n}`)
			local home = pm and pm:GetAttribute(PartPose.HOME)
			if pm and pm:IsA("Model") and typeof(home) == "CFrame" then
				local parts = {}
				for _, d in pm:GetDescendants() do
					if d:IsA("BasePart") then
						table.insert(parts, d)
					end
				end
				pins[n] = { model = pm, home = home, parts = parts, hidden = false }
			end
		end
	end
	return if ball and ball:IsA("BasePart") then ball else nil, pins
end

local function hide(pin: PinParts, on: boolean)
	if pin.hidden == on then
		return
	end
	pin.hidden = on
	for _, p in pin.parts do
		p.LocalTransparencyModifier = if on then 1 else 0
	end
end

-- Returns true so that pcall(write, ...) has a second value to hand back whether it failed or not.
local function write(e: Entry, t: number): boolean
	local script = e.script
	local ball = e.ball
	if ball and ball.Parent then
		local x, y, d, turn = RollScript.ball(script, t)
		if x ~= nil then
			ball.CFrame = PartPose.ball(e.place, e.lane, x, y, d, turn)
		end
	end
	for n, pin in e.pins do
		if script.mask[n] and pin.model.Parent then
			local x, y, d, tilt, yaw, hidden = RollScript.pin(script, n, t)
			hide(pin, hidden)
			pin.model:PivotTo(PartPose.pin(e.place, pin.home, n, x, y, d, tilt, yaw))
		end
	end
	return true
end

local function finish(e: Entry)
	for _, pin in e.pins do
		hide(pin, false)
	end
end

local function step()
	local now = BowlingPlayback.clock()
	for lane, e in active do
		local t = now - e.t0
		local tEnd = e.script.tEnd
		local ok, err = pcall(write, e, math.min(t, tEnd))
		if not ok then
			warn(`BowlingPlayback: lane {lane}: {err}`)
			finish(e)
			active[lane] = nil
			continue
		end
		while e.cueAt <= #e.cues and e.cues[e.cueAt][1] <= t do
			local cue = e.cues[e.cueAt]
			e.cueAt += 1
			if e.onCue then
				pcall(e.onCue, cue[2], cue[3])
			end
		end
		if t >= tEnd + BowlingPlayback.TAIL then
			finish(e)
			active[lane] = nil
		end
	end
	if next(active) == nil and bound then
		bound = false
		game:GetService("RunService"):UnbindFromRenderStep(BowlingPlayback.BIND)
	end
end

-- play: start drawing a throw on a lane. Returns false (and plays nothing) when the lane is not on this client.
function BowlingPlayback.play(
	place: any,
	lane: number,
	script: any,
	onCue: ((name: string, volume: number) -> ())?
): boolean
	local old = active[lane]
	if old then
		finish(old)
		active[lane] = nil
	end
	if place == nil then
		return false
	end
	local ball, pins = find(lane)
	if ball == nil and next(pins) == nil then
		return false
	end
	active[lane] = {
		place = place,
		lane = lane,
		script = script,
		t0 = BowlingPlayback.clock(),
		ball = ball,
		pins = pins,
		cues = RollScript.cues(script),
		cueAt = 1,
		onCue = onCue,
	}
	if not bound then
		bound = true
		-- before the camera's own step, so a shot that follows the ball sees this frame's ball
		game:GetService("RunService"):BindToRenderStep(BowlingPlayback.BIND, Enum.RenderPriority.Camera.Value - 1, step)
	end
	return true
end

-- stop: a throw was cut short (the table emptied, the game ended, the lane was reset). With a mask the lane is
-- shown as the server now has it: those pins standing on their spots, the ball on its rack.
function BowlingPlayback.stop(lane: number, place: any?, mask: { boolean }?)
	local e = active[lane]
	if e then
		finish(e)
		active[lane] = nil
	end
	if place == nil or mask == nil then
		return
	end
	local ball, pins = find(lane)
	for n, pin in pins do
		if mask[n] == true then
			pin.model:PivotTo(pin.home)
		end
	end
	local rack = ball and ball:GetAttribute(PartPose.RACK)
	if ball and typeof(rack) == "CFrame" then
		ball.CFrame = rack
	end
end

function BowlingPlayback.now(lane: number): number?
	local e = active[lane]
	return if e then BowlingPlayback.clock() - e.t0 else nil
end

function BowlingPlayback.playing(lane: number): boolean
	return active[lane] ~= nil
end

return BowlingPlayback
