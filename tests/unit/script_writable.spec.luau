--!strict
-- tests/unit/script_writable.spec.luau
-- A live game script may not write every property the engine has: some need the Plugin or Open Cloud
-- capability. The cloud checks (Luau Execution) hold that capability, so such a write passes them and
-- then stops a real server at boot (Terrain.Decoration, 2026-11-10: "lacking capability
-- PluginOrOpenCloud"). This scans src for member assignments to a property that no script may write
-- on the engine classes the game touches. Such a property belongs in the project files ($properties).

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

-- written inside pcall for the bake under Lune, where they do work (Factory.part)
local ALLOWED: { [string]: { [string]: boolean } } = {
	["src/worldgen/Factory.luau"] = { MeshId = true, InitialSize = true, DoubleSided = true, CollisionFidelity = true },
}
-- not writable by a script on one class, writable on another with the same name: always checked
local WATCH = { "MeshId", "CollisionFidelity", "RenderFidelity", "Technology", "StreamingEnabled" }

local CORE = {
	"Workspace",
	"Terrain",
	"Lighting",
	"BasePart",
	"Part",
	"MeshPart",
	"Model",
	"Player",
	"Players",
	"Humanoid",
	"SurfaceAppearance",
	"Sound",
	"SoundService",
	"Decal",
	"Texture",
	"Instance",
	"Camera",
	"StarterPlayer",
	"StarterGui",
	"UnionOperation",
	"TriangleMeshPart",
	"PVInstance",
	"Attachment",
	"Beam",
	"ParticleEmitter",
	"Atmosphere",
	"Sky",
	"Clouds",
	"ScreenGui",
	"GuiObject",
	"Animator",
	"AnimationTrack",
	"Animation",
	"Bone",
	"Motor6D",
	"Weld",
	"WeldConstraint",
	"RemoteEvent",
	"UnreliableRemoteEvent",
	"MaterialService",
	"MaterialVariant",
	"SpecialMesh",
	"ProximityPrompt",
	"PointLight",
	"SpotLight",
	"SurfaceLight",
	"Highlight",
	"BillboardGui",
	"SurfaceGui",
	"TextLabel",
	"ImageLabel",
	"VehicleSeat",
	"Seat",
	"Folder",
	"DataModel",
	"WedgePart",
	"TextChatService",
	"PhysicsService",
}

local function forbidden(): { [string]: string }
	local db = roblox.getReflectionDatabase()
	local writable: { [string]: boolean } = {}
	local blocked: { [string]: string } = {}
	local core: { [string]: boolean } = {}
	for _, n in CORE do
		core[n] = true
	end
	for _, className in db:GetClassNames() do
		local class = db:GetClass(className)
		if class then
			for name, p in class.Properties do
				local s = tostring(p.Scriptability)
				if s == "ReadWrite" or s == "Custom" or s == "Write" then
					writable[name] = true
				elseif core[className] then
					blocked[name] = className
				end
			end
		end
	end
	local out: { [string]: string } = {}
	for name, className in blocked do
		if not writable[name] then
			out[name] = className
		end
	end
	for _, name in WATCH do
		out[name] = out[name] or blocked[name] or "watched"
	end
	return out
end

local function luauFiles(dir: string, out: { string })
	for _, n in fs.readDir(dir) do
		local p = `{dir}/{n}`
		if fs.isDir(p) then
			luauFiles(p, out)
		elseif n:match("%.luau$") then
			table.insert(out, p)
		end
	end
end

return function(t: any)
	t.test("the reflection database knows what stopped the server", function()
		local f = forbidden()
		t.eq(f.Decoration, "Terrain", "Terrain.Decoration is not script-writable")
		t.truthy(f.GrassLength ~= nil, "Terrain.GrassLength is not script-writable")
		t.truthy(f.Anchored == nil and f.CFrame == nil and f.Name == nil, "ordinary properties are writable")
	end)

	t.test("no game script assigns a property that only a plugin or Open Cloud may write", function()
		local f = forbidden()
		local files: { string } = {}
		luauFiles("src", files)
		t.truthy(#files > 200, `scanned {#files} files`)
		local found: { string } = {}
		for _, path in files do
			local allowed = ALLOWED[path] or {}
			local i = 0
			for line in (fs.readFile(path) .. "\n"):gmatch("(.-)\n") do
				i += 1
				if not line:match("^%s*%-%-") then
					for name in line:gmatch("%.([A-Z]%w+)%s*=[^=]") do
						if f[name] and not allowed[name] then
							table.insert(found, `{path}:{i}: .{name} (not script-writable on {f[name]})`)
						end
					end
				end
			end
		end
		t.eq(table.concat(found, "\n"), "", "forbidden writes")
	end)

	t.test("the grass blades are switched off in the place file, in every project", function()
		local serde = require("@lune/serde")
		for _, project in { "default.project.json", "ci.project.json", "build.project.json" } do
			local tree = serde.decode("json", fs.readFile(project)).tree
			local terrain = tree.Workspace.Terrain
			t.truthy(terrain ~= nil and terrain["$className"] == "Terrain", `{project}: Workspace.Terrain`)
			t.eq(terrain["$properties"].Decoration, false, `{project}: Terrain.Decoration`)
		end
	end)
end
