--!strict
-- tools/anim/build_clip: clip JSON -> KeyframeSequence .rbxm (BUILD_PLAN D11, spike S7).
--   lune run tools/anim/build_clip.luau <clip.json> <out.rbxm>
-- Prints the summary (keyframes, duration, pose names, markers) as JSON on stdout.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local KeyframeBuilder = require("./KeyframeBuilder")

local input, output = process.args[1], process.args[2]
if input == nil or output == nil then
	print("usage: lune run tools/anim/build_clip.luau <clip.json> <out.rbxm>")
	process.exit(2)
end

local clip = serde.decode("json", fs.readFile(input)) :: KeyframeBuilder.Clip
local seq = KeyframeBuilder.build(clip)
fs.writeFile(output, roblox.serializeModel({ seq }))
local summary = KeyframeBuilder.summarize(seq)
print(serde.encode("json", {
	input = input,
	output = output,
	bytes = #fs.readFile(output),
	name = summary.name,
	keyframes = summary.keyframes,
	duration = summary.duration,
	poseNames = summary.poseNames,
	markers = summary.markers,
}, false))
