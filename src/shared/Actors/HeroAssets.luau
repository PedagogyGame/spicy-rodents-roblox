--!strict
-- ReplicatedStorage.Shared.Actors.HeroAssets
-- The uploaded skinned hero models the game may show in place of the part-built puppets: asset ids, the
-- height of the game's root over the model's feet, each region's SurfaceAppearance mode and stock tint,
-- and the sockets to add under the bones. WRITTEN FROM data/art/heroes.json (tools/blender/heroes/publish.py
-- fills that file on upload); tests/unit/hero_art.spec.luau fails when the two disagree. To swap in new
-- art: upload, then rewrite this table from the JSON (the spec prints what differs).
-- Interface: SPECIES: { [templateName]: Entry } (templateName: "squirrel" | "rodent").

export type Region = { alphaMode: string, tint: string? }
export type Socket = { bone: string, offset: { number } }
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

return HeroAssets
