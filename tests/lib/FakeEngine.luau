--!strict
-- tests/lib/FakeEngine.luau: just enough of the Roblox engine for a Lune spec to run server glue that moves
-- parts (the cloud checks cannot be run from here, and they have no clients or physics anyway). Datatypes
-- (Vector3, CFrame, Color3, Enum) are Lune's real ones; instances are small Luau tables with the handful of
-- members the glue uses: a tree (Parent, FindFirstChild, GetChildren, GetDescendants, IsA, Destroy, Clone),
-- attributes, properties as plain fields, Position from CFrame, and Model:GetPivot / PivotTo that carry the
-- model's parts along. No events, no physics, no replication.
-- The engine globals exist only between install() and uninstall(): use `FakeEngine.with(function() ... end)`.
-- ONLY IN AN ISOLATED RUN (tests/lib/Isolated, cases under tests/isolated/): install() reaches the globals
-- through getfenv, which switches off Luau's fast paths for everything that runs afterwards in the process.
-- Interface: new(className, name?, props?) -> Instance; install(); uninstall(); with(fn); part(name, cframe,
--   parent?) -> Part; model(name, pivot, parent?) -> Model; isInstance(v)

local roblox = require("@lune/roblox")

local FakeEngine = {}

local BASE_PARTS: { [string]: boolean } = { Part = true, MeshPart = true, WedgePart = true }

local Inst = {}

local function isInstance(v: any): boolean
	return type(v) == "table" and getmetatable(v) == Inst
end
FakeEngine.isInstance = isInstance

local methods: { [string]: any } = {}

Inst.__index = function(self: any, key: any): any
	local m = methods[key]
	if m ~= nil then
		return m
	end
	if key == "Parent" then
		return rawget(self, "_parent")
	elseif key == "Position" then
		local cf = rawget(self, "CFrame")
		return if cf then cf.Position else nil
	elseif key == "PrimaryPart" then
		return rawget(self, "_primary")
	end
	return nil
end

Inst.__newindex = function(self: any, key: any, value: any)
	if key == "Parent" then
		local old = rawget(self, "_parent")
		if old then
			local list = rawget(old, "_children")
			local i = table.find(list, self)
			if i then
				table.remove(list, i)
			end
		end
		rawset(self, "_parent", value)
		if value then
			table.insert(rawget(value, "_children"), self)
		end
	elseif key == "PrimaryPart" then
		rawset(self, "_primary", value)
	else
		rawset(self, key, value)
	end
end

function methods.FindFirstChild(self: any, name: string): any
	for _, c in rawget(self, "_children") do
		if c.Name == name then
			return c
		end
	end
	return nil
end

function methods.FindFirstChildOfClass(self: any, class: string): any
	for _, c in rawget(self, "_children") do
		if c.ClassName == class then
			return c
		end
	end
	return nil
end

function methods.GetChildren(self: any): { any }
	return table.clone(rawget(self, "_children"))
end

function methods.GetDescendants(self: any): { any }
	local out = {}
	local function walk(node: any)
		for _, c in rawget(node, "_children") do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end

function methods.IsA(self: any, class: string): boolean
	local own = self.ClassName
	return class == own or class == "Instance" or (class == "BasePart" and BASE_PARTS[own] == true)
end

function methods.SetAttribute(self: any, name: string, value: any)
	rawget(self, "_attrs")[name] = value
end

function methods.GetAttribute(self: any, name: string): any
	return rawget(self, "_attrs")[name]
end

function methods.Destroy(self: any)
	self.Parent = nil
	for _, c in table.clone(rawget(self, "_children")) do
		c:Destroy()
	end
end

function methods.Clone(self: any): any
	local copy = FakeEngine.new(self.ClassName, self.Name)
	for k, v in self do
		if type(k) == "string" and string.sub(k, 1, 1) ~= "_" then
			rawset(copy, k, v)
		end
	end
	for k, v in rawget(self, "_attrs") do
		rawget(copy, "_attrs")[k] = v
	end
	for _, c in rawget(self, "_children") do
		c:Clone().Parent = copy
	end
	return copy
end

-- A model's pivot: its own stored frame (set by FakeEngine.model). PivotTo carries every part along.
function methods.GetPivot(self: any): any
	return rawget(self, "_pivot") or roblox.CFrame.new(0, 0, 0)
end

function methods.PivotTo(self: any, cf: any)
	local old = self:GetPivot()
	local delta = cf * old:Inverse()
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") and rawget(d, "CFrame") then
			rawset(d, "CFrame", delta * rawget(d, "CFrame"))
		end
	end
	rawset(self, "_pivot", cf)
	rawset(self, "_pivots", (rawget(self, "_pivots") or 0) + 1)
end

function methods.GetFullName(self: any): string
	local parent = rawget(self, "_parent")
	return if parent then parent:GetFullName() .. "." .. self.Name else self.Name
end

function FakeEngine.new(className: string, name: string?, props: { [string]: any }?): any
	local self = setmetatable({ _children = {}, _attrs = {}, _parent = nil }, Inst) :: any
	rawset(self, "ClassName", className)
	rawset(self, "Name", name or className)
	if BASE_PARTS[className] then
		rawset(self, "Transparency", 0)
		rawset(self, "Anchored", false)
		rawset(self, "CanCollide", true)
		rawset(self, "CanTouch", true)
		rawset(self, "CanQuery", true)
		rawset(self, "CFrame", roblox.CFrame.new(0, 0, 0))
		rawset(self, "Size", roblox.Vector3.new(1, 1, 1))
	end
	for k, v in props or {} do
		self[k] = v
	end
	return self
end

function FakeEngine.part(name: string, cf: any, parent: any?): any
	local p = FakeEngine.new("Part", name)
	rawset(p, "CFrame", cf)
	p.Parent = parent
	return p
end

function FakeEngine.model(name: string, pivot: any, parent: any?): any
	local m = FakeEngine.new("Model", name)
	rawset(m, "_pivot", pivot)
	m.Parent = parent
	return m
end

local GLOBALS = { "Vector3", "CFrame", "Color3", "Enum", "Instance", "workspace", "typeof" }
local saved: { [string]: any } = {}
local installed = false

-- install: the engine globals appear (for modules that look them up when their functions run).
function FakeEngine.install()
	if installed then
		return
	end
	installed = true
	-- selene: allow(deprecated)
	local env = getfenv(0) :: any
	local realTypeof = typeof
	for _, g in GLOBALS do
		saved[g] = env[g]
	end
	env.Vector3 = roblox.Vector3
	env.CFrame = roblox.CFrame
	env.Color3 = roblox.Color3
	env.Enum = roblox.Enum
	env.Instance = { new = FakeEngine.new }
	env.workspace = FakeEngine.new("Workspace", "Workspace")
	env.typeof = function(v: any): string
		return if isInstance(v) then "Instance" else realTypeof(v)
	end
end

function FakeEngine.uninstall()
	if not installed then
		return
	end
	installed = false
	-- selene: allow(deprecated)
	local env = getfenv(0) :: any
	for _, g in GLOBALS do
		env[g] = saved[g]
	end
	table.clear(saved)
end

-- with: run fn with the engine globals in place; they are always taken away again, even if fn throws.
function FakeEngine.with(fn: () -> ())
	FakeEngine.install()
	local ok, err = xpcall(fn, function(e)
		return debug.traceback(tostring(e), 2)
	end)
	FakeEngine.uninstall()
	if not ok then
		error(err, 0)
	end
end

return FakeEngine
