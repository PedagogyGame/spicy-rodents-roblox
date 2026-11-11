--!strict
-- ReplicatedStorage.Shared.Actors.HeroAssets
-- The uploaded skinned hero models the game may show in place of the part-built puppets: asset ids, the
-- height of the game's root over the model's feet, each region's SurfaceAppearance mode (and a stock tint,
-- when one is not baked into the colour map), and the sockets to add under the bones. WRITTEN BY
-- tools/blender/heroes/hero_assets_luau.py FROM data/art/heroes.json (publish.py fills that file on
-- upload); tests/unit/hero_art.spec.luau fails when the two disagree.
-- Interface: SPECIES: { [templateName]: Entry } (templateName: "squirrel" | "rodent");
--   CLIPS: { [rig]: { [clipName]: Clip } } (rig "squirrel": Idle, Walk, Run, Climb, Wire, Leap, Pounce, Bite, Stalk).

export type Region = { alphaMode: string, tint: string? }
export type Socket = { bone: string, offset: { number } }
export type Clip = { id: string, length: number, loop: boolean }
export type Entry = {
	assetId: number,
	hipHeight: number,
	regions: { [string]: Region },
	sockets: { [string]: Socket },
}

local HeroAssets = {}

HeroAssets.SPECIES = {
	squirrel = {
		assetId = 76531525066511,
		hipHeight = 0.9,
		regions = {
			Body = { alphaMode = "Overlay" },
			Eyes = { alphaMode = "Overlay" },
			FurCards = { alphaMode = "Transparency" },
			Pattern = { alphaMode = "Overlay" },
		},
		sockets = {
			ChestCenter = { bone = "Chest", offset = { 0, -0.13, 0.04 } },
			HeadSocket = { bone = "Head", offset = { 0, 0.24, -0.12 } },
			MouthSocket = { bone = "Jaw", offset = { 0, 0.02, -0.24 } },
			TailTip = { bone = "Tail8", offset = { 0, -0.03, 0.18 } },
		},
	},
	rodent = {
		assetId = 140106981482488,
		hipHeight = 0.9,
		regions = {
			Blood = { alphaMode = "Transparency" },
			Body = { alphaMode = "Overlay" },
			Eyes = { alphaMode = "Overlay" },
			FurCards = { alphaMode = "Transparency" },
			Pattern = { alphaMode = "Overlay" },
		},
		sockets = {
			ChestCenter = { bone = "Chest", offset = { 0, -0.13, 0.04 } },
			HeadSocket = { bone = "Head", offset = { 0, 0.24, -0.12 } },
			MouthSocket = { bone = "Jaw", offset = { 0, 0.02, -0.24 } },
			TailTip = { bone = "Tail8", offset = { 0, -0.03, 0.18 } },
		},
	},
} :: { [string]: Entry }

-- The squirrel rig's animation clips (the rodent shares them): asset id, seconds, whether it loops.
HeroAssets.CLIPS = {
	squirrel = {
		Bite = { id = "rbxassetid://80748279389978", length = 2.0667, loop = false },
		Climb = { id = "rbxassetid://124697817757826", length = 0.6, loop = true },
		Idle = { id = "rbxassetid://131290508281628", length = 3.0, loop = true },
		Leap = { id = "rbxassetid://102733473426026", length = 0.7667, loop = false },
		Pounce = { id = "rbxassetid://125262543371003", length = 0.9667, loop = false },
		Run = { id = "rbxassetid://90468448447985", length = 0.4667, loop = true },
		Stalk = { id = "rbxassetid://87730756983478", length = 1.2, loop = true },
		Walk = { id = "rbxassetid://80734625038082", length = 0.8, loop = true },
		Wire = { id = "rbxassetid://75735754293305", length = 1.0, loop = true },
	},
} :: { [string]: { [string]: Clip } }

return HeroAssets
