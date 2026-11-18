--!strict
-- ReplicatedStorage.Shared.Avatar.PeopleAssets
-- The rounded townspeople (tools/blender/people): the six uploaded Models and the rig the game puts them on.
-- WRITTEN BY tools/blender/people/publish.py FROM data/art/people.json; tests/unit/people_art.spec.luau fails
-- when the two disagree. An asset id of 0 is not uploaded: Server/Assets/PeopleArt then leaves every stock body
-- as it is.
-- Positions are studs in Roblox axes (+Y up, the person faces -Z): a part's `center` is relative to the
-- HumanoidRootPart's centre in the rest pose; a joint's c0 and c1 are its pivot relative to the centres of part0
-- and part1 (Motor6D C0 = CFrame.new(c0), C1 = CFrame.new(c1)); an attachment's `position` and an extra's or a
-- headwear item's `offset` are relative to the centre of the part it is on or welded to. A tint is a look key
-- (skin, shirt, pants, hair, cap) or a fixed "#rrggbb".
-- Interface: ASSETS; ROOT; BUILDS; OUTFITS; HEAD; HEADWEAR; ROLES.
-- Pure data. No side effects on require.

export type Vec = { number }
export type Part = { center: Vec, size: Vec, tris: number }
export type Joint = { part0: string, part1: string, c0: Vec, c1: Vec }
export type Attachment = { part: string, position: Vec }
export type Extra = { weldTo: string, offset: Vec, tint: string, tris: number, size: Vec }
export type Build = {
	parts: { [string]: Part },
	joints: { [string]: Joint },
	attachments: { [string]: Attachment },
	extras: { [string]: Extra },
	triangles: { [string]: number },
}
export type Outfit = { label: string, tints: { [string]: string }, extras: { string } }
export type Head = { tint: string, faces: { string }, expressions: { string } }
export type Headwear = { kind: string, offset: Vec, size: Vec, tint: string, tris: number, underCap: boolean? }
export type Role = { outfits: { string }, face: string, hat: string?, hair: { string } }

local PeopleAssets = {}

PeopleAssets.ASSETS =
	{ bodyBroad = 0, bodySlim = 0, faces = 0, head = 0, headwear = 0, outfits = 0 } :: { [string]: number }

PeopleAssets.ROOT = { height = 5.5, hipHeight = 2, name = "HumanoidRootPart", size = { 2, 2, 1 } }

-- stylua: ignore
PeopleAssets.BUILDS = {
	broad = {
		attachments = {
			BadgeAttachment = { part = "UpperTorso", position = { -0.38, 0.3231, -0.4004 } },
			BodyBackAttachment = { part = "UpperTorso", position = { 0, 0.1231, 0.5096 } },
			BodyFrontAttachment = { part = "UpperTorso", position = { 0, 0.1231, -0.4104 } },
			ChestRigAttachment = { part = "UpperTorso", position = { 0, 0.1231, -0.4104 } },
			FaceCenterAttachment = { part = "Head", position = { 0, 0.2003, 0.0537 } },
			FaceFrontAttachment = { part = "Head", position = { 0, 0.2003, -0.5663 } },
			HairAttachment = { part = "Head", position = { 0, 0.7903, 0.0537 } },
			HatAttachment = { part = "Head", position = { 0, 0.7903, 0.0537 } },
			LeftCollarAttachment = { part = "UpperTorso", position = { -0.62, 0.8431, 0.0496 } },
			LeftFootAttachment = { part = "LeftFoot", position = { 0.0088, -0.2188, 0.166 } },
			LeftGripAttachment = { part = "LeftHand", position = { 0.0068, -0.0033, 0.0038 } },
			LeftShoulderAttachment = { part = "LeftUpperArm", position = { -0.0012, 0.5604, 0 } },
			MaskAttachment = { part = "Head", position = { 0, 0.0703, -0.5863 } },
			NeckAttachment = { part = "UpperTorso", position = { 0, 0.8231, 0.0496 } },
			PadAttachmentL = { part = "LeftUpperArm", position = { -0.0012, 0.5604, 0 } },
			PadAttachmentR = { part = "RightUpperArm", position = { 0.0012, 0.5604, 0 } },
			RightCollarAttachment = { part = "UpperTorso", position = { 0.62, 0.8431, 0.0496 } },
			RightFootAttachment = { part = "RightFoot", position = { -0.0088, -0.2188, 0.166 } },
			RightGripAttachment = { part = "RightHand", position = { -0.0068, -0.0033, 0.0038 } },
			RightShoulderAttachment = { part = "RightUpperArm", position = { 0.0012, 0.5604, 0 } },
			WaistBackAttachment = { part = "LowerTorso", position = { 0, 0.1251, 0.48 } },
			WaistCenterAttachment = { part = "LowerTorso", position = { 0, 0.1251, 0.02 } },
			WaistFrontAttachment = { part = "LowerTorso", position = { 0, 0.1251, -0.44 } },
		},
		extras = {
			LeftCoatTail = {
				offset = { 0.0037, 0.2899, 0.0042 },
				size = { 0.8577, 0.8366, 0.8514 },
				tint = "shirt",
				tris = 180,
				weldTo = "LeftUpperLeg",
			},
			RightCoatTail = {
				offset = { -0.0037, 0.2899, 0.0042 },
				size = { 0.8577, 0.8366, 0.8514 },
				tint = "shirt",
				tris = 180,
				weldTo = "RightUpperLeg",
			},
			Stethoscope = {
				offset = { -0.0009, 0.4446, -0.1005 },
				size = { 0.8557, 1.0682, 0.9895 },
				tint = "#ffffff",
				tris = 250,
				weldTo = "UpperTorso",
			},
			VNeck = {
				offset = { 0, 0.6552, -0.3433 },
				size = { 0.6033, 0.4549, 0.3756 },
				tint = "skin",
				tris = 44,
				weldTo = "UpperTorso",
			},
		},
		joints = {
			LeftAnkle = {
				c0 = { 0, -0.398, -0.0323 },
				c1 = { 0.0088, 0.0332, 0.166 },
				part0 = "LeftLowerLeg",
				part1 = "LeftFoot",
			},
			LeftElbow = {
				c0 = { -0.0412, -0.3846, 0 },
				c1 = { 0.0036, 0.4363, -0.0049 },
				part0 = "LeftUpperArm",
				part1 = "LeftLowerArm",
			},
			LeftHip = {
				c0 = { -0.5, -0.1249, 0.02 },
				c1 = { -0.0265, 0.3716, -0.0261 },
				part0 = "LowerTorso",
				part1 = "LeftUpperLeg",
			},
			LeftKnee = {
				c0 = { -0.0265, -0.4504, -0.0261 },
				c1 = { 0, 0.528, -0.0323 },
				part0 = "LeftUpperLeg",
				part1 = "LeftLowerLeg",
			},
			LeftShoulder = { c0 = { -1, 0.5861, 0.0496 }, c1 = { -0.0012, 0.3434, 0 }, part0 = "UpperTorso", part1 = "LeftUpperArm" },
			LeftWrist = {
				c0 = { -0.0064, -0.3487, -0.0049 },
				c1 = { -0.0432, 0.2467, 0.0338 },
				part0 = "LeftLowerArm",
				part1 = "LeftHand",
			},
			Neck = { c0 = { 0, 0.8231, 0.0496 }, c1 = { 0, -0.6497, 0.0537 }, part0 = "UpperTorso", part1 = "Head" },
			RightAnkle = {
				c0 = { 0, -0.398, -0.0323 },
				c1 = { -0.0088, 0.0332, 0.166 },
				part0 = "RightLowerLeg",
				part1 = "RightFoot",
			},
			RightElbow = {
				c0 = { 0.0412, -0.3846, 0 },
				c1 = { -0.0036, 0.4363, -0.0049 },
				part0 = "RightUpperArm",
				part1 = "RightLowerArm",
			},
			RightHip = {
				c0 = { 0.5, -0.1249, 0.02 },
				c1 = { 0.0265, 0.3716, -0.0261 },
				part0 = "LowerTorso",
				part1 = "RightUpperLeg",
			},
			RightKnee = {
				c0 = { 0.0265, -0.4504, -0.0261 },
				c1 = { 0, 0.528, -0.0323 },
				part0 = "RightUpperLeg",
				part1 = "RightLowerLeg",
			},
			RightShoulder = { c0 = { 1, 0.5861, 0.0496 }, c1 = { 0.0012, 0.3434, 0 }, part0 = "UpperTorso", part1 = "RightUpperArm" },
			RightWrist = {
				c0 = { 0.0064, -0.3487, -0.0049 },
				c1 = { 0.0432, 0.2467, 0.0338 },
				part0 = "RightLowerArm",
				part1 = "RightHand",
			},
			Root = { c0 = { 0, -1, 0 }, c1 = { 0, -0.1249, 0.02 }, part0 = "HumanoidRootPart", part1 = "LowerTorso" },
			Waist = { c0 = { 0, 0.2751, 0.02 }, c1 = { 0, -0.7769, 0.0496 }, part0 = "LowerTorso", part1 = "UpperTorso" },
		},
		parts = {
			Head = { center = { 0, 1.6497, -0.0537 }, size = { 1.3292, 1.5633, 1.3911 }, tris = 1092 },
			LeftFoot = { center = { -0.5088, -2.7812, -0.166 }, size = { 0.4232, 0.4375, 0.9456 }, tris = 288 },
			LeftHand = { center = { -1.0068, -0.9967, -0.0338 }, size = { 0.3457, 0.6574, 0.3662 }, tris = 225 },
			LeftLowerArm = { center = { -1.0436, -0.4013, 0.0049 }, size = { 0.405, 0.8774, 0.3959 }, tris = 130 },
			LeftLowerLeg = { center = { -0.5, -2.35, 0.0323 }, size = { 0.5434, 1.056, 0.5728 }, tris = 180 },
			LeftUpperArm = { center = { -0.9988, 0.4196, 0 }, size = { 0.4921, 1.1527, 0.4693 }, tris = 180 },
			LeftUpperLeg = { center = { -0.4735, -1.3716, 0.0261 }, size = { 0.7877, 1.444, 0.7786 }, tris = 216 },
			LowerTorso = { center = { 0, -0.8751, -0.02 }, size = { 1.6106, 0.8703, 1.0149 }, tris = 224 },
			RightFoot = { center = { 0.5088, -2.7812, -0.166 }, size = { 0.4232, 0.4375, 0.9456 }, tris = 288 },
			RightHand = { center = { 1.0068, -0.9967, -0.0338 }, size = { 0.3457, 0.6574, 0.3662 }, tris = 225 },
			RightLowerArm = { center = { 1.0436, -0.4013, 0.0049 }, size = { 0.405, 0.8774, 0.3959 }, tris = 130 },
			RightLowerLeg = { center = { 0.5, -2.35, 0.0323 }, size = { 0.5434, 1.056, 0.5728 }, tris = 180 },
			RightUpperArm = { center = { 0.9988, 0.4196, 0 }, size = { 0.4921, 1.1527, 0.4693 }, tris = 180 },
			RightUpperLeg = { center = { 0.4735, -1.3716, 0.0261 }, size = { 0.7877, 1.444, 0.7786 }, tris = 216 },
			UpperTorso = { center = { 0, 0.1769, -0.0496 }, size = { 2.44, 2.0316, 1.098 }, tris = 648 },
		},
		triangles = { body = 4402, largestExtras = 610, largestHair = 418, largestHat = 364, worstCase = 5794 },
	},
	slim = {
		attachments = {
			BadgeAttachment = { part = "UpperTorso", position = { -0.38, 0.3168, -0.4083 } },
			BodyBackAttachment = { part = "UpperTorso", position = { 0, 0.1168, 0.5017 } },
			BodyFrontAttachment = { part = "UpperTorso", position = { 0, 0.1168, -0.4183 } },
			ChestRigAttachment = { part = "UpperTorso", position = { 0, 0.1168, -0.4183 } },
			FaceCenterAttachment = { part = "Head", position = { 0, 0.2003, 0.0537 } },
			FaceFrontAttachment = { part = "Head", position = { 0, 0.2003, -0.5663 } },
			HairAttachment = { part = "Head", position = { 0, 0.7903, 0.0537 } },
			HatAttachment = { part = "Head", position = { 0, 0.7903, 0.0537 } },
			LeftCollarAttachment = { part = "UpperTorso", position = { -0.62, 0.8368, 0.0417 } },
			LeftFootAttachment = { part = "LeftFoot", position = { 0.0081, -0.2188, 0.1681 } },
			LeftGripAttachment = { part = "LeftHand", position = { 0.0065, -0.0155, 0.0019 } },
			LeftShoulderAttachment = { part = "LeftUpperArm", position = { -0.0012, 0.5619, 0 } },
			MaskAttachment = { part = "Head", position = { 0, 0.0703, -0.5863 } },
			NeckAttachment = { part = "UpperTorso", position = { 0, 0.8168, 0.0417 } },
			PadAttachmentL = { part = "LeftUpperArm", position = { -0.0012, 0.5619, 0 } },
			PadAttachmentR = { part = "RightUpperArm", position = { 0.0012, 0.5619, 0 } },
			RightCollarAttachment = { part = "UpperTorso", position = { 0.62, 0.8368, 0.0417 } },
			RightFootAttachment = { part = "RightFoot", position = { -0.0081, -0.2188, 0.1681 } },
			RightGripAttachment = { part = "RightHand", position = { -0.0065, -0.0155, 0.0019 } },
			RightShoulderAttachment = { part = "RightUpperArm", position = { 0.0012, 0.5619, 0 } },
			WaistBackAttachment = { part = "LowerTorso", position = { 0, 0.0905, 0.46 } },
			WaistCenterAttachment = { part = "LowerTorso", position = { 0, 0.0905, 0 } },
			WaistFrontAttachment = { part = "LowerTorso", position = { 0, 0.0905, -0.46 } },
		},
		extras = {
			LeftCoatTail = {
				offset = { 0.0036, 0.2789, 0.0013 },
				size = { 0.8124, 0.802, 0.7734 },
				tint = "shirt",
				tris = 180,
				weldTo = "LeftUpperLeg",
			},
			RightCoatTail = {
				offset = { -0.0036, 0.2789, 0.0013 },
				size = { 0.8124, 0.802, 0.7734 },
				tint = "shirt",
				tris = 180,
				weldTo = "RightUpperLeg",
			},
			Stethoscope = {
				offset = { -0.0008, 0.4402, -0.0647 },
				size = { 0.8581, 1.0647, 0.9041 },
				tint = "#ffffff",
				tris = 250,
				weldTo = "UpperTorso",
			},
			VNeck = {
				offset = { -0.0001, 0.648, -0.318 },
				size = { 0.6039, 0.4563, 0.3013 },
				tint = "skin",
				tris = 44,
				weldTo = "UpperTorso",
			},
		},
		joints = {
			LeftAnkle = {
				c0 = { 0, -0.398, -0.0313 },
				c1 = { 0.0081, 0.0332, 0.1681 },
				part0 = "LeftLowerLeg",
				part1 = "LeftFoot",
			},
			LeftElbow = {
				c0 = { -0.0412, -0.3831, 0 },
				c1 = { 0.0036, 0.4364, -0.0048 },
				part0 = "LeftUpperArm",
				part1 = "LeftLowerArm",
			},
			LeftHip = {
				c0 = { -0.5, -0.1595, 0 },
				c1 = { -0.0436, 0.3779, -0.0257 },
				part0 = "LowerTorso",
				part1 = "LeftUpperLeg",
			},
			LeftKnee = {
				c0 = { -0.0436, -0.4441, -0.0257 },
				c1 = { 0, 0.528, -0.0313 },
				part0 = "LeftUpperLeg",
				part1 = "LeftLowerLeg",
			},
			LeftShoulder = { c0 = { -1, 0.5798, 0.0417 }, c1 = { -0.0012, 0.3449, 0 }, part0 = "UpperTorso", part1 = "LeftUpperArm" },
			LeftWrist = {
				c0 = { -0.0064, -0.3486, -0.0048 },
				c1 = { -0.0435, 0.2345, 0.0319 },
				part0 = "LeftLowerArm",
				part1 = "LeftHand",
			},
			Neck = { c0 = { 0, 0.8168, 0.0417 }, c1 = { 0, -0.6497, 0.0537 }, part0 = "UpperTorso", part1 = "Head" },
			RightAnkle = {
				c0 = { 0, -0.398, -0.0313 },
				c1 = { -0.0081, 0.0332, 0.1681 },
				part0 = "RightLowerLeg",
				part1 = "RightFoot",
			},
			RightElbow = {
				c0 = { 0.0412, -0.3831, 0 },
				c1 = { -0.0036, 0.4364, -0.0048 },
				part0 = "RightUpperArm",
				part1 = "RightLowerArm",
			},
			RightHip = {
				c0 = { 0.5, -0.1595, 0 },
				c1 = { 0.0436, 0.3779, -0.0257 },
				part0 = "LowerTorso",
				part1 = "RightUpperLeg",
			},
			RightKnee = {
				c0 = { 0.0436, -0.4441, -0.0257 },
				c1 = { 0, 0.528, -0.0313 },
				part0 = "RightUpperLeg",
				part1 = "RightLowerLeg",
			},
			RightShoulder = { c0 = { 1, 0.5798, 0.0417 }, c1 = { 0.0012, 0.3449, 0 }, part0 = "UpperTorso", part1 = "RightUpperArm" },
			RightWrist = {
				c0 = { 0.0064, -0.3486, -0.0048 },
				c1 = { 0.0435, 0.2345, 0.0319 },
				part0 = "RightLowerArm",
				part1 = "RightHand",
			},
			Root = { c0 = { 0, -1, 0 }, c1 = { 0, -0.1595, 0 }, part0 = "HumanoidRootPart", part1 = "LowerTorso" },
			Waist = { c0 = { 0, 0.2405, 0 }, c1 = { 0, -0.7832, 0.0417 }, part0 = "LowerTorso", part1 = "UpperTorso" },
		},
		parts = {
			Head = { center = { 0, 1.6497, -0.0537 }, size = { 1.3292, 1.5633, 1.3911 }, tris = 1092 },
			LeftFoot = { center = { -0.5081, -2.7812, -0.1681 }, size = { 0.407, 0.4375, 0.9413 }, tris = 288 },
			LeftHand = { center = { -1.0065, -0.9845, -0.0319 }, size = { 0.3205, 0.6166, 0.3454 }, tris = 225 },
			LeftLowerArm = { center = { -1.0436, -0.4014, 0.0048 }, size = { 0.367, 0.8772, 0.3586 }, tris = 130 },
			LeftLowerLeg = { center = { -0.5, -2.35, 0.0313 }, size = { 0.4957, 1.056, 0.524 }, tris = 180 },
			LeftUpperArm = { center = { -0.9988, 0.4181, 0 }, size = { 0.4415, 1.1058, 0.4212 }, tris = 180 },
			LeftUpperLeg = { center = { -0.4564, -1.3779, 0.0257 }, size = { 0.7408, 1.3721, 0.6959 }, tris = 216 },
			LowerTorso = { center = { 0, -0.8405, 0 }, size = { 1.4882, 0.8009, 0.8258 }, tris = 224 },
			RightFoot = { center = { 0.5081, -2.7812, -0.1681 }, size = { 0.407, 0.4375, 0.9413 }, tris = 288 },
			RightHand = { center = { 1.0065, -0.9845, -0.0319 }, size = { 0.3205, 0.6166, 0.3454 }, tris = 225 },
			RightLowerArm = { center = { 1.0436, -0.4014, 0.0048 }, size = { 0.367, 0.8772, 0.3586 }, tris = 130 },
			RightLowerLeg = { center = { 0.5, -2.35, 0.0313 }, size = { 0.4957, 1.056, 0.524 }, tris = 180 },
			RightUpperArm = { center = { 0.9988, 0.4181, 0 }, size = { 0.4415, 1.1058, 0.4212 }, tris = 180 },
			RightUpperLeg = { center = { 0.4564, -1.3779, 0.0257 }, size = { 0.7408, 1.3721, 0.6959 }, tris = 216 },
			UpperTorso = { center = { 0, 0.1832, -0.0417 }, size = { 2.39, 2.0252, 0.9247 }, tris = 648 },
		},
		triangles = { body = 4402, largestExtras = 610, largestHair = 418, largestHat = 364, worstCase = 5794 },
	},
} :: { [string]: Build }

-- stylua: ignore
PeopleAssets.OUTFITS = {
	coat = {
		extras = { "Stethoscope", "LeftCoatTail", "RightCoatTail" },
		label = "Doctor's coat",
		tints = {
			Head = "skin",
			LeftCoatTail = "shirt",
			LeftFoot = "#5a4334",
			LeftHand = "skin",
			LeftLowerArm = "shirt",
			LeftLowerLeg = "pants",
			LeftUpperArm = "shirt",
			LeftUpperLeg = "pants",
			LowerTorso = "shirt",
			RightCoatTail = "shirt",
			RightFoot = "#5a4334",
			RightHand = "skin",
			RightLowerArm = "shirt",
			RightLowerLeg = "pants",
			RightUpperArm = "shirt",
			RightUpperLeg = "pants",
			Stethoscope = "#ffffff",
			UpperTorso = "shirt",
		},
	},
	guard = {
		extras = {  },
		label = "Guard uniform",
		tints = {
			Head = "skin",
			LeftFoot = "#26262a",
			LeftHand = "skin",
			LeftLowerArm = "skin",
			LeftLowerLeg = "pants",
			LeftUpperArm = "shirt",
			LeftUpperLeg = "pants",
			LowerTorso = "pants",
			RightFoot = "#26262a",
			RightHand = "skin",
			RightLowerArm = "skin",
			RightLowerLeg = "pants",
			RightUpperArm = "shirt",
			RightUpperLeg = "pants",
			UpperTorso = "shirt",
		},
	},
	jacket = {
		extras = {  },
		label = "Zipped jacket",
		tints = {
			Head = "skin",
			LeftFoot = "#8a6a4a",
			LeftHand = "skin",
			LeftLowerArm = "shirt",
			LeftLowerLeg = "pants",
			LeftUpperArm = "shirt",
			LeftUpperLeg = "pants",
			LowerTorso = "pants",
			RightFoot = "#8a6a4a",
			RightHand = "skin",
			RightLowerArm = "shirt",
			RightLowerLeg = "pants",
			RightUpperArm = "shirt",
			RightUpperLeg = "pants",
			UpperTorso = "shirt",
		},
	},
	mime = {
		extras = {  },
		label = "Mime",
		tints = {
			Head = "skin",
			LeftFoot = "#26262a",
			LeftHand = "#f1f1ec",
			LeftLowerArm = "shirt",
			LeftLowerLeg = "pants",
			LeftUpperArm = "shirt",
			LeftUpperLeg = "pants",
			LowerTorso = "pants",
			RightFoot = "#26262a",
			RightHand = "#f1f1ec",
			RightLowerArm = "shirt",
			RightLowerLeg = "pants",
			RightUpperArm = "shirt",
			RightUpperLeg = "pants",
			UpperTorso = "shirt",
		},
	},
	police = {
		extras = {  },
		label = "Police uniform",
		tints = {
			Head = "skin",
			LeftFoot = "#26262a",
			LeftHand = "skin",
			LeftLowerArm = "shirt",
			LeftLowerLeg = "pants",
			LeftUpperArm = "shirt",
			LeftUpperLeg = "pants",
			LowerTorso = "pants",
			RightFoot = "#26262a",
			RightHand = "skin",
			RightLowerArm = "shirt",
			RightLowerLeg = "pants",
			RightUpperArm = "shirt",
			RightUpperLeg = "pants",
			UpperTorso = "shirt",
		},
	},
	scrubs = {
		extras = { "VNeck" },
		label = "Scrubs",
		tints = {
			Head = "skin",
			LeftFoot = "#e6e6e0",
			LeftHand = "skin",
			LeftLowerArm = "skin",
			LeftLowerLeg = "pants",
			LeftUpperArm = "shirt",
			LeftUpperLeg = "pants",
			LowerTorso = "shirt",
			RightFoot = "#e6e6e0",
			RightHand = "skin",
			RightLowerArm = "skin",
			RightLowerLeg = "pants",
			RightUpperArm = "shirt",
			RightUpperLeg = "pants",
			UpperTorso = "shirt",
			VNeck = "skin",
		},
	},
	shirt = {
		extras = {  },
		label = "Short-sleeved shirt",
		tints = {
			Head = "skin",
			LeftFoot = "#5a4334",
			LeftHand = "skin",
			LeftLowerArm = "skin",
			LeftLowerLeg = "pants",
			LeftUpperArm = "shirt",
			LeftUpperLeg = "pants",
			LowerTorso = "pants",
			RightFoot = "#5a4334",
			RightHand = "skin",
			RightLowerArm = "skin",
			RightLowerLeg = "pants",
			RightUpperArm = "shirt",
			RightUpperLeg = "pants",
			UpperTorso = "shirt",
		},
	},
} :: { [string]: Outfit }

-- stylua: ignore
PeopleAssets.HEAD = {
	expressions = { "calm", "worried", "frightened" },
	faces = { "plain", "mime" },
	tint = "skin",
} :: Head

-- stylua: ignore
PeopleAssets.HEADWEAR = {
	Hair_balding = {
		kind = "hair",
		offset = { 0, 0.274, 0.2521 },
		size = { 1.2603, 0.759, 0.9714 },
		tint = "hair",
		tris = 144,
		underCap = true,
	},
	Hair_bob = {
		kind = "hair",
		offset = { 0, 0.2663, 0.0958 },
		size = { 1.389, 1.202, 1.4188 },
		tint = "hair",
		tris = 374,
		underCap = false,
	},
	Hair_bun = {
		kind = "hair",
		offset = { 0, 0.3869, 0.1288 },
		size = { 1.2565, 0.985, 1.2168 },
		tint = "hair",
		tris = 326,
		underCap = true,
	},
	Hair_curly = {
		kind = "hair",
		offset = { 0, 0.4031, 0.1166 },
		size = { 1.4296, 1.0984, 1.3959 },
		tint = "hair",
		tris = 286,
		underCap = false,
	},
	Hair_long = {
		kind = "hair",
		offset = { 0, 0.1235, 0.1248 },
		size = { 1.3532, 1.4677, 1.38 },
		tint = "hair",
		tris = 418,
		underCap = false,
	},
	Hair_parted = {
		kind = "hair",
		offset = { 0, 0.3926, 0.0852 },
		size = { 1.2965, 1.0183, 1.3439 },
		tint = "hair",
		tris = 286,
		underCap = false,
	},
	Hair_ponytail = {
		kind = "hair",
		offset = { 0, 0.3395, 0.2123 },
		size = { 1.2664, 1.0646, 1.4121 },
		tint = "hair",
		tris = 382,
		underCap = true,
	},
	Hair_short = {
		kind = "hair",
		offset = { 0, 0.3799, 0.1132 },
		size = { 1.2668, 0.9765, 1.258 },
		tint = "hair",
		tris = 286,
		underCap = true,
	},
	Hat_beret = {
		kind = "hat",
		offset = { 0.006, 0.7403, 0.122 },
		size = { 1.2428, 0.4399, 1.4481 },
		tint = "#202020",
		tris = 224,
	},
	Hat_cap = {
		kind = "hat",
		offset = { 0, 0.6421, -0.0295 },
		size = { 1.5083, 0.5096, 1.7472 },
		tint = "cap",
		tris = 364,
	},
} :: { [string]: Headwear }

-- stylua: ignore
PeopleAssets.ROLES = {
	doctor = {
		face = "plain",
		hair = { "Hair_short", "Hair_parted", "Hair_bob", "Hair_bun", "Hair_balding", "Hair_ponytail" },
		outfits = { "coat" },
	},
	driver = {
		face = "plain",
		hair = { "Hair_short", "Hair_balding", "Hair_ponytail", "Hair_bun" },
		hat = "Hat_cap",
		outfits = { "police" },
	},
	guard = {
		face = "plain",
		hair = { "Hair_short", "Hair_balding", "Hair_bun", "Hair_ponytail" },
		hat = "Hat_cap",
		outfits = { "guard" },
	},
	mime = {
		face = "mime",
		hair = { "Hair_short", "Hair_parted", "Hair_bob" },
		hat = "Hat_beret",
		outfits = { "mime" },
	},
	nurse = {
		face = "plain",
		hair = { "Hair_bun", "Hair_ponytail", "Hair_bob", "Hair_short", "Hair_curly" },
		outfits = { "scrubs" },
	},
	officer = {
		face = "plain",
		hair = { "Hair_short", "Hair_ponytail", "Hair_bun", "Hair_balding" },
		hat = "Hat_cap",
		outfits = { "police" },
	},
	orderly = {
		face = "plain",
		hair = { "Hair_short", "Hair_curly", "Hair_parted", "Hair_ponytail" },
		outfits = { "scrubs" },
	},
	townsperson = {
		face = "plain",
		hair = { "Hair_short", "Hair_parted", "Hair_bob", "Hair_ponytail", "Hair_curly", "Hair_bun", "Hair_balding", "Hair_long" },
		outfits = { "shirt", "jacket" },
	},
} :: { [string]: Role }

return PeopleAssets
