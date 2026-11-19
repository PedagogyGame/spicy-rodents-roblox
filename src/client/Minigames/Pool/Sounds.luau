--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Pool.Sounds
-- The cue-sports sounds, one set for eight-ball (Games/Pool, "pool.<cue>") and bumper pool (Games/BumperPool,
-- "bumper_pool.<cue>"): the cues Pool/Playback and Pool/CueController fire (Shot.cues: strike, click, crack,
-- cushion, jaw, post, rim, drop, home; chalk at a turn's start). Every sound is from Roblox's licensed library
-- (ProSoundEffects' billiards recordings) or Roblox's own (its pinball set: a ball running home along metal
-- tracks); nothing uploaded (docs/AUDIO_BUDGET.md "Pool and bumper pool"). A cue a game never fires (bumper pool's
-- break and pocket jaws, eight-ball's rubber posts) has its sound all the same.
-- Interface: IDS (cue -> "rbxassetid://<n>"); set(prefix) -> { ["<prefix>.<cue>"]: id }
-- Pure; no side effects on require.

local Sounds = {}

Sounds.IDS = table.freeze({
	chalk = "rbxassetid://9125460155", -- Coral Scrape: small pieces rubbed together, thin, gritty
	strike = "rbxassetid://9113441098", -- Billiards, ball hits and rolls, with the cue stick
	click = "rbxassetid://9113440232", -- Billiard Balls, ball hits and rolls
	crack = "rbxassetid://9113441694", -- Billiards, break and rack up, ball hits
	cushion = "rbxassetid://9113440925", -- Billiards, ball bounces off the bumpers, soft hit and roll
	jaw = "rbxassetid://9113442163", -- Billiards, balls shot into pockets, clattery
	post = "rbxassetid://9113440927", -- Billiards, off the bumpers (bumper pool's rubber posts)
	rim = "rbxassetid://9113441345", -- Billiards Balls, rolling on the table, soft plunky hits
	drop = "rbxassetid://9113442190", -- Billiards, balls into pockets
	home = "rbxassetid://16480554578", -- Roblox Pinball, rolling on metal tracks (the ball's run to the tray)
}) :: { [string]: string }

function Sounds.set(prefix: string): { [string]: string }
	local out: { [string]: string } = {}
	for cue, id in Sounds.IDS do
		out[`{prefix}.{cue}`] = id
	end
	return out
end

return Sounds
