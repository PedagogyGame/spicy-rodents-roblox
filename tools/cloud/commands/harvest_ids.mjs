// harvest_ids (W0 stub): the plan's `cloud/harvest_ids` reads a place version (normally the Art
// Inbox, where the owner imports skinned rigs) through Luau Execution and returns the asset IDs
// (MeshId, TextureID, SurfaceAppearance maps, animation IDs, package ids) as JSON for
// data/assets/manifest.json (BUILD_PLAN §4.3 item 2, S8b). The task script below is the intended
// payload; the command runs it only with --run, and that path is exercised in W1 with S8.
import { createTask, waitForTask, getTaskLogs } from "../lib/openCloud.mjs";
import { resolvePlace } from "../lib/config.mjs";
import { parseArgs, out, die } from "../lib/cli.mjs";

export const HARVEST_SCRIPT = `
-- harvest_ids: walk the place and collect every asset reference (read-only).
local out = { meshes = {}, textures = {}, surfaceAppearances = {}, animations = {}, packages = {} }
for _, inst in game:GetDescendants() do
	if inst:IsA("MeshPart") then
		table.insert(out.meshes, { path = inst:GetFullName(), meshId = inst.MeshId, textureId = inst.TextureID })
	elseif inst:IsA("SurfaceAppearance") then
		table.insert(out.surfaceAppearances, { path = inst:GetFullName(), color = inst.ColorMap, normal = inst.NormalMap, roughness = inst.RoughnessMap, metalness = inst.MetalnessMap })
	elseif inst:IsA("Animation") then
		table.insert(out.animations, { path = inst:GetFullName(), animationId = inst.AnimationId })
	elseif inst:IsA("Decal") or inst:IsA("Texture") then
		table.insert(out.textures, { path = inst:GetFullName(), texture = inst.Texture })
	elseif inst:IsA("PackageLink") then
		table.insert(out.packages, { path = inst:GetFullName(), packageId = inst.PackageId, version = inst.VersionNumber })
	end
end
out.placeVersion = game.PlaceVersion
return out
`;

export default async function harvestIds(argv) {
	const { flags } = parseArgs(argv);
	const place = resolvePlace(flags.place || "art_inbox");
	if (!flags.run) {
		out({
			status: "stub",
			message: "harvest_ids is a W0 stub. Pass --run --version <v> to execute the read-only harvest task against a place version (Art Inbox by default). Exercised in W1 with spike S8(b).",
			place,
			script: HARVEST_SCRIPT.trim(),
		});
		return 0;
	}
	if (!flags.version) die("--version <placeVersion> is required with --run", 2);
	const { task } = await createTask({ placeId: place.id, version: flags.version, script: HARVEST_SCRIPT, label: "harvest_ids" });
	const finished = await waitForTask(task.path);
	const logs = await getTaskLogs(task.path);
	out({ state: finished.state, error: finished.error, result: finished.output?.results?.[0], logs });
	return finished.state === "COMPLETE" ? 0 : 1;
}
