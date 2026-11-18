--!strict
-- StarterPlayer.StarterPlayerScripts.Client.World.LoungeMusic
-- THE GILDED ACORN's jazz (brief v2 "Lounge one": "Stock licensed jazz from Roblox's music library, 1920s feel"),
-- on this client only and only inside: while the body this player holds carries the Lounge attribute (set by
-- Server/Attractions/LoungeService when it lets the body in, cleared at the door), one local Sound plays the
-- playlist Shared/Attractions/LoungeClassic.JAZZ in order, the next track when one ends, faded in and out over
-- FADE seconds. NOTHING PLAYS YET: every id is empty (cue names only; the lead fills them from the library and
-- never uploads), so the playlist is silent and the handle says so.
-- Interface: FADE; start(ctx) -> Handle; ctx = { current: () -> Model?, parent: Instance? (default SoundService) };
--   Handle = { step(dt), inside() -> boolean, track() -> string? (the cue playing), level() -> number, stop() }
--   start binds step to RunService.Heartbeat; the joiner calls it from Client/Main with PossessionClient's current.
-- Engine only inside the functions; no side effects on require.

local Import = require("../Import")
local LoungeClassic =
	Import.shared("Attractions/LoungeClassic") :: typeof(require("../../shared/Attractions/LoungeClassic"))

local LoungeMusic = {}

LoungeMusic.FADE = 1.5 -- seconds

export type Handle = {
	step: (dt: number) -> (),
	inside: () -> boolean,
	track: () -> string?,
	level: () -> number,
	stop: () -> (),
}

function LoungeMusic.start(ctx: { current: () -> Model?, parent: Instance?, heartbeat: boolean? }): Handle
	local sound = Instance.new("Sound")
	sound.Name = "LoungeJazz"
	sound.Looped = false
	sound.Volume = 0
	sound.Parent = ctx.parent or game:GetService("SoundService")
	local index = 0 -- the playlist's current track (0: none yet)
	local level = 0 -- 0..1, the fade
	local isInside = false
	local cue: string? = nil
	local function nextTrack()
		local i = LoungeClassic.nextTrack(LoungeClassic.JAZZ, index)
		if i == nil then
			cue = nil
			return
		end
		index = i
		local t = LoungeClassic.JAZZ[i]
		cue = t.cue
		sound.SoundId = t.id
		sound.TimePosition = 0
		sound:Play()
	end
	local ended = sound.Ended:Connect(function()
		if isInside then
			nextTrack()
		end
	end)
	local function step(dt: number)
		local body = ctx.current()
		local now = body ~= nil and body:GetAttribute(LoungeClassic.ATTRIBUTE) ~= nil
		if now and not isInside and not sound.Playing then
			nextTrack()
		end
		isInside = now
		local target = if now then 1 else 0
		local stepBy = dt / LoungeMusic.FADE
		level = if target > level then math.min(target, level + stepBy) else math.max(target, level - stepBy)
		sound.Volume = LoungeClassic.JAZZ_VOLUME * level
		if level <= 0 and sound.Playing then
			sound:Stop()
			cue = nil
		end
	end
	local conn: RBXScriptConnection? = nil
	if ctx.heartbeat ~= false then
		conn = game:GetService("RunService").Heartbeat:Connect(step)
	end
	return {
		step = step,
		inside = function(): boolean
			return isInside
		end,
		track = function(): string?
			return cue
		end,
		level = function(): number
			return level
		end,
		stop = function()
			if conn then
				conn:Disconnect()
			end
			ended:Disconnect()
			sound:Destroy()
		end,
	}
end

return LoungeMusic
