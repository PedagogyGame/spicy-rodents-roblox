--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.MinigameSounds
-- Sound cues for the minigames. Each game brings its own cues (ClientGame.sounds: cue -> asset id) and the
-- registry (Client/Minigames/ClientGames) adds them here. NOTHING IS UPLOADED AND NOTHING PLAYS YET: every cue's
-- asset id is empty, so play() is silent. What exists is the timing: a bowling throw's script carries its cue
-- points (the release, the roll, each clatter of pins, a gutter, the ball dropping into the pit) and
-- BowlingPlayback calls play() at those moments, so when the licensed sounds are chosen (docs/AUDIO_BUDGET.md)
-- they only need their ids filled in in the game's own file. Bowling's cues keep their bare names; a new
-- game's are "<game>.<cue>" so that two games can never mean different sounds by one name.
-- Interface: play(cue, volume?) -> bool (true only if a real sound was started); CUES (cue -> asset id, "" =
--   none yet); add(cues) (a game's own); counts() -> { [cue]: times asked } (so a developer can see the cues fire)

local MinigameSounds = {}

MinigameSounds.CUES = {} :: { [string]: string }

local asked: { [string]: number } = {}

function MinigameSounds.add(cues: { [string]: string })
	for cue, id in cues do
		MinigameSounds.CUES[cue] = id
	end
end

function MinigameSounds.counts(): { [string]: number }
	return asked
end

function MinigameSounds.play(cue: string, volume: number?): boolean
	asked[cue] = (asked[cue] or 0) + 1
	local id = MinigameSounds.CUES[cue]
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
