--!strict
-- ReplicatedStorage.Shared.Audio.Uploads
-- The game's own audio uploads (owner D16 #36 and #50; docs/AUDIO_BUDGET.md "Uploads"). Every other sound is from
-- Roblox's licensed library or Roblox's own; these are the few with nothing fitting there, made offline as
-- candidates (assets/audio/candidates, tools/audio/make_candidates.py) and uploaded by the lead once heard and
-- approved. Until a slot's id is filled its cue is silent; tools/audio/publish.py --record <slot>=<assetId> fills
-- it here and in the candidates' manifest. Nothing here is synthesised at run time (Roblox has no runtime synthesis).
-- Interface: SLOTS (slot -> { id: "" | "<assetId>", file, cues }); id(slot) -> "rbxassetid://<n>" or "" (not uploaded
--   yet); errors on an unknown slot
-- Pure; no side effects on require.

local Uploads = {}

export type Slot = { id: string, file: string, cues: { string } }

Uploads.SLOTS = table.freeze({
	-- the yard dogs' bark: a friendly medium dog's "woof woof", not a growl (owner #36: a custom upload)
	dog_bark = table.freeze({
		id = "",
		file = "assets/audio/candidates/dog_bark.ogg",
		cues = table.freeze({ "Dogs.Bark" }),
	}),
	-- a bowling ball rumbling down the lane, about 2.5 s, fading as it reaches the pins (none in the library)
	bowling_roll = table.freeze({
		id = "",
		file = "assets/audio/candidates/bowling_roll.ogg",
		cues = table.freeze({ "roll" }),
	}),
}) :: { [string]: Slot }

function Uploads.id(slot: string): string
	local s = Uploads.SLOTS[slot]
	assert(s ~= nil, `Audio/Uploads: no slot {slot}`)
	if s.id == "" then
		return ""
	end
	return `rbxassetid://{s.id}`
end

return Uploads
