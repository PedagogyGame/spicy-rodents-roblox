// Save-free engine tests (S1 fallback, verified 2026-11-09): a Luau Execution task may create
// ModuleScripts, set their Source and require them. This module turns a Rojo project file into a
// bootstrap that rebuilds the code tree inside the task's DataModel before the test script runs,
// so engine suites can run against ANY existing place version (even the stock version 1) while a
// real save is unavailable. Content files (.rbxm, .model.json) are skipped; project `$properties`
// are applied with pcall (read-only ones such as Players.MaxPlayers are recorded, not fatal).
import fs from "node:fs";
import path from "node:path";

const IGNORE_FILE = /(\.spec\.luau$|^README\.md$|^\.gitkeep$)/;

function classAndName(entry) {
	if (entry.endsWith(".server.luau")) return ["Script", entry.slice(0, -".server.luau".length)];
	if (entry.endsWith(".client.luau")) return ["LocalScript", entry.slice(0, -".client.luau".length)];
	if (entry.endsWith(".luau")) return ["ModuleScript", entry.slice(0, -".luau".length)];
	return [null, null];
}

function walkDir(dir, instPath, out, skipped) {
	const entries = fs.readdirSync(dir, { withFileTypes: true });
	const hasInit = entries.some((e) => e.isFile() && e.name === "init.luau");
	const hasInitServer = entries.some((e) => e.isFile() && e.name === "init.server.luau");
	const hasInitClient = entries.some((e) => e.isFile() && e.name === "init.client.luau");
	let cls = "Folder";
	let source;
	if (hasInit) {
		cls = "ModuleScript";
		source = fs.readFileSync(path.join(dir, "init.luau"), "utf8");
	} else if (hasInitServer) {
		cls = "Script";
		source = fs.readFileSync(path.join(dir, "init.server.luau"), "utf8");
	} else if (hasInitClient) {
		cls = "LocalScript";
		source = fs.readFileSync(path.join(dir, "init.client.luau"), "utf8");
	}
	out.push({ p: instPath, c: cls, s: source });
	for (const e of entries) {
		if (IGNORE_FILE.test(e.name)) continue;
		const full = path.join(dir, e.name);
		if (e.isDirectory()) {
			walkDir(full, [...instPath, e.name], out, skipped);
		} else if (e.isFile()) {
			if (e.name.startsWith("init.")) continue;
			const [c, name] = classAndName(e.name);
			if (!c) {
				skipped.push(full);
				continue;
			}
			out.push({ p: [...instPath, name], c, s: fs.readFileSync(full, "utf8") });
		}
	}
}

function resolvePath(spec) {
	if (typeof spec === "string") return { dir: spec, optional: false };
	if (spec && typeof spec.optional === "string") return { dir: spec.optional, optional: true };
	return null;
}

export function buildTree(projectFile) {
	const project = JSON.parse(fs.readFileSync(projectFile, "utf8"));
	const root = path.dirname(path.resolve(projectFile));
	const instances = [];
	const properties = [];
	const skipped = [];

	function walkNode(node, instPath) {
		const spec = resolvePath(node.$path);
		if (instPath.length > 0 && !spec) {
			// A container node: keep an existing instance of any class (e.g. the built-in
			// StarterPlayer.StarterPlayerScripts) unless the project names a class explicitly.
			instances.push({ p: instPath, c: node.$className || "Folder", k: node.$className ? undefined : true });
		}
		if (spec) {
			const dir = path.resolve(root, spec.dir);
			if (fs.existsSync(dir) && fs.statSync(dir).isDirectory()) {
				walkDir(dir, instPath, instances, skipped);
			} else if (!spec.optional) {
				throw new Error(`project path ${spec.dir} does not exist`);
			}
		}
		if (node.$properties && instPath.length === 1) {
			for (const [k, v] of Object.entries(node.$properties)) properties.push({ service: instPath[0], name: k, value: v });
		}
		for (const [k, child] of Object.entries(node)) {
			if (!k.startsWith("$") && child && typeof child === "object") walkNode(child, [...instPath, k]);
		}
	}
	for (const [k, child] of Object.entries(project.tree)) {
		if (!k.startsWith("$") && child && typeof child === "object") walkNode(child, [k]);
	}
	// Service roots themselves are never created (GetService), only their descendants.
	const filtered = instances.filter((i) => i.p.length > 1);
	return { instances: filtered, properties, skipped, name: project.name };
}

function longBracket(payload) {
	let eq = "=";
	while (payload.includes(`]${eq}]`)) eq += "=";
	return eq;
}

// Returns the Luau bootstrap followed by the user's script. The user script's top-level return is
// the task's return value.
export function wrapScript(projectFile, userScript) {
	const tree = buildTree(projectFile);
	const payload = JSON.stringify({ instances: tree.instances, properties: tree.properties });
	const eq = longBracket(payload);
	const bootstrap = `-- [inject bootstrap] rebuilds the Rojo tree of ${path.basename(projectFile)} (${tree.instances.length} instances) inside this task.
do
	local HttpService = game:GetService("HttpService")
	local data = HttpService:JSONDecode([${eq}[${payload}]${eq}])
	local function ensure(pathParts)
		local current = game:GetService(pathParts[1])
		for i = 2, #pathParts do
			local child = current:FindFirstChild(pathParts[i])
			if not child then
				child = Instance.new("Folder")
				child.Name = pathParts[i]
				child.Parent = current
			end
			current = child
		end
		return current
	end
	local created, replaced = 0, 0
	for _, inst in data.instances do
		local parent = ensure({ table.unpack(inst.p, 1, #inst.p - 1) })
		local name = inst.p[#inst.p]
		local existing = parent:FindFirstChild(name)
		if existing and inst.k then
			-- container node without an explicit class: keep whatever exists
			continue
		end
		if existing and existing.ClassName ~= inst.c then
			existing:Destroy()
			existing = nil
			replaced += 1
		elseif existing and inst.c == "Folder" then
			-- keep: a folder created by ensure() or an existing container
			continue
		end
		local obj = existing or Instance.new(inst.c)
		obj.Name = name
		if inst.s then
			obj.Source = inst.s
		end
		if not existing then
			obj.Parent = parent
			created += 1
		else
			replaced += 1
		end
	end
	local propertyFailures = {}
	for _, prop in data.properties do
		local ok, err = pcall(function()
			local service = game:GetService(prop.service)
			local value = prop.value
			local current = service[prop.name]
			if typeof(current) == "EnumItem" then
				value = (current.EnumType :: any)[value]
			end
			service[prop.name] = value
		end)
		if not ok then
			table.insert(propertyFailures, prop.service .. "." .. prop.name .. ": " .. tostring(err))
		end
	end
	local marker = game:GetService("ServerStorage"):FindFirstChild("EngineTests")
	if not marker then
		marker = Instance.new("Folder")
		marker.Name = "EngineTests"
		marker.Parent = game:GetService("ServerStorage")
	end
	marker:SetAttribute("Injected", true)
	marker:SetAttribute("InjectedPropertyFailures", HttpService:JSONEncode(propertyFailures))
	print(string.format("[inject] %d instances created, %d replaced, %d property failure(s)", created, replaced, #propertyFailures))
end
`;
	return { script: `${bootstrap}\n${userScript}`, tree };
}
