--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.MinigameSounds
-- Placeholder sound cues for the minigames. NOTHING IS UPLOADED AND NOTHING PLAYS YET: every cue's asset id is
-- empty, so play() is silent. What exists is the timing: a bowling throw's script carries its cue points (the
-- release, the roll, each clatter of pins, a gutter, the ball dropping into the pit) and BowlingPlayback calls
-- play() at those moments, so when the licensed sounds are chosen (docs/AUDIO_BUDGET.md) they only need their
-- ids filled in here.
-- Interface: play(cue, volume?) -> bool (true only if a real sound was started); CUES (cue -> asset id, "" =
--   none yet); counts() -> { [cue]: times asked } (so a developer can see the cues fire)

local MinigameSounds = {}

MinigameSounds.CUES = {
	release = "", -- the ball leaves the hand
	roll = "", -- the rumble down the lane (looped until the pins or the pit)
	gutter = "", -- the ball drops into the channel
	pin = "", -- one clatter of pins
	pit = "", -- the ball thumps into the pit
	strike = "", -- the call
	spare = "",
	sweep = "", -- the pinsetter
}

local asked: { [string]: number } = {}

function MinigameSounds.counts(): { [string]: number }
	return asked
end

function MinigameSounds.play(cue: string, volume: number?): boolean
	asked[cue] = (asked[cue] or 0) + 1
	local id = (MinigameSounds.CUES :: { [string]: string })[cue]
	if id == nil or id == "" then
		return false
	end
	local sound = Instance.new("Sound")
	sound.Name = `Minigame_{cue}`
	sound.SoundId = id
	sound.Volume = math.clamp(volume or 0.6, 0, 1)
	sound.Parent = game:GetService("SoundService")
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	return true
end

return MinigameSounds
