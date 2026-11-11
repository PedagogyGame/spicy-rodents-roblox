--!strict
-- ReplicatedStorage.Shared.Actors.HeroAssets
-- The uploaded skinned hero models the game may show in place of the part-built puppets: asset ids, the
-- height of the game's root over the model's feet, each region's SurfaceAppearance mode and stock tint,
-- and the sockets to add under the bones. WRITTEN FROM data/art/heroes.json (tools/blender/heroes/publish.py
-- fills that file on upload); tests/unit/hero_art.spec.luau fails when the two disagree. To swap in new
-- art: upload, then rewrite this table from the JSON (the spec prints what differs).
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
		assetId = 116513654149636,
		hipHeight = 0.9,
		regions = {
			Body = { alphaMode = "TintMask", tint = "#c27442" },
			Eyes = { alphaMode = "Overlay" },
			FurCards = { alphaMode = "Transparency", tint = "#c27442" },
			Pattern = { alphaMode = "TintMask", tint = "#f5d8ac" },
		},
		sockets = {
			ChestCenter = { bone = "Chest", offset = { 0, -0.13, 0.04 } },
			HeadSocket = { bone = "Head", offset = { 0, 0.24, -0.12 } },
			MouthSocket = { bone = "Jaw", offset = { 0, 0.02, -0.24 } },
			TailTip = { bone = "Tail8", offset = { 0, -0.03, 0.18 } },
		},
	},
	rodent = {
		assetId = 138576770823082,
		hipHeight = 0.9,
		regions = {
			Blood = { alphaMode = "Transparency" },
			Body = { alphaMode = "TintMask", tint = "#663d2c" },
			Eyes = { alphaMode = "Overlay" },
			FurCards = { alphaMode = "Transparency", tint = "#663d2c" },
			Pattern = { alphaMode = "TintMask", tint = "#987559" },
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
		Bite = { id = "rbxassetid://107543483770582", length = 2.0667, loop = false },
		Climb = { id = "rbxassetid://106748373386847", length = 0.6, loop = true },
		Idle = { id = "rbxassetid://114052541887620", length = 3.0, loop = true },
		Leap = { id = "rbxassetid://86002579743514", length = 0.7667, loop = false },
		Pounce = { id = "rbxassetid://106395010025022", length = 0.9667, loop = false },
		Run = { id = "rbxassetid://75567975955833", length = 0.4667, loop = true },
		Stalk = { id = "rbxassetid://107478850422829", length = 1.2, loop = true },
		Walk = { id = "rbxassetid://100972548402656", length = 0.8, loop = true },
		Wire = { id = "rbxassetid://112948511637029", length = 1.0, loop = true },
	},
} :: { [string]: { [string]: Clip } }

return HeroAssets
