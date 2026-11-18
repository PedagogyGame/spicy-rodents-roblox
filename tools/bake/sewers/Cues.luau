--!strict
-- tools/bake/sewers/Cues: where the storm drains' sounds come from, baked as named points with no sound in them yet
-- (no audio is synthesised or uploaded: HANDOFF rule 6, the 40-50 uploads a month; the client lane S3 plays a cue
-- once its id exists). One invisible "Cues" part per pipe holds an Attachment per point, named after its cue, with
-- attributes Cue (the cue's name), SoundId ("" until audio exists) and Space.
--   sewer.grateIn / sewer.grateOut   at each street mouth (the grate rattles as a squirrel goes down or comes up)
--   sewer.streetMurmur               at each street mouth (the street heard from below)
--   sewer.rung                       half way up each ladder
--   sewer.trickle                    at each outlet's fall of water
--   sewer.drip                       every DRIP_EVERY studs along each passage (the client picks one at random,
--                                    every 2 to 6 s)
--   sewer.riverHum                   P2 under the middle of the river
--   sewer.carOverhead                under the crossing (P1's chamber) and under P3's boulevard light grate
--   sewer.trolleyOverhead            P3 under the trolley's rails
--   sewer.hiss                       the small alligator (v5.4's idle watchdog in the sewer: "A low hiss and a ripple
--                                    in the sewer water"): a sound and a line only, one point per pipe
-- Not baked (they follow the squirrel): sewer.footEcho.
-- Interface: build(kit, parent, pipe, points) -> number of cue points; Cues.NAMES

local Kit = require("./Kit")

local Cues = {}

Cues.NAMES = {
	"sewer.grateIn",
	"sewer.grateOut",
	"sewer.streetMurmur",
	"sewer.rung",
	"sewer.trickle",
	"sewer.drip",
	"sewer.riverHum",
	"sewer.carOverhead",
	"sewer.trolleyOverhead",
	"sewer.hiss",
}
Cues.DRIP_EVERY = 40

export type Point = { cue: string, x: number, y: number, z: number }

function Cues.build(kit: Kit.Kit, parent: any, pipe: any, points: { Point }): number
	if #points == 0 then
		return 0
	end
	local CF = kit.roblox.CFrame
	local p0 = points[1]
	local holder = kit:at(
		parent,
		"Cues",
		CF.new(p0.x, p0.y, p0.z),
		{ 0.2, 0.2, 0.2 },
		{ 0, 0, 0 },
		"SmoothPlastic",
		{ visual = true, transparency = 1, shadow = false, attrs = { Space = pipe.space } }
	)
	for _, p in points do
		local at = kit:attach(holder, p.cue, CF.new(p.x, p.y, p.z))
		at:SetAttribute("Cue", p.cue)
		at:SetAttribute("SoundId", "")
		at:SetAttribute("Space", pipe.space)
	end
	return #points
end

return Cues
