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
-- `game:GetService` gives a RunService whose BindToRenderStep callbacks and RenderStepped signal the test
-- fires itself (renderStep), a UserInputService with InputBegan / InputEnded / InputChanged signals the test
-- fires (input) and a few settable facts (the mouse, a focused text box), an HttpService that can JSONEncode,
-- and empty stand-ins for anything else. workspace.CurrentCamera is a fake camera with a viewport.
-- Interface: new(className, name?, props?) -> Instance; install(); uninstall(); with(fn); part(name, cframe,
--   parent?) -> Part; model(name, pivot, parent?) -> Model; isInstance(v); workspace() -> the fake Workspace;
--   renderStep(dt) (call every bound render step and RenderStepped); bound() -> how many render steps are
--   bound; signal() -> { Connect, fire }; uis() -> the fake UserInputService; input(kind "began" | "ended" |
--   "changed", io, processed?) (fire an input event; io = { KeyCode?, UserInputType, Delta?, Position? })

local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

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

local GLOBALS = { "Vector3", "Vector2", "CFrame", "Color3", "UDim2", "Enum", "Instance", "workspace", "typeof", "game" }
local saved: { [string]: any } = {}
local installed = false
local renderSteps: { [string]: (dt: number) -> () } = {}
local fakeWorkspace: any = nil
local fakeUis: any = nil
local renderStepped: any = nil

function FakeEngine.workspace(): any
	return fakeWorkspace
end

-- Fire every render step a module bound (in no particular order).
function FakeEngine.renderStep(dt: number)
	for _, fn in table.clone(renderSteps) do
		fn(dt)
	end
	if renderStepped then
		renderStepped.fire(dt)
	end
end

function FakeEngine.bound(): number
	local n = 0
	for _ in renderSteps do
		n += 1
	end
	return n
end

-- A signal: Connect(fn) -> { Disconnect }, and fire(...) for the test.
function FakeEngine.signal(): any
	local handlers: { any } = {}
	local sig = {}
	function sig.Connect(_self: any, fn: (...any) -> ()): any
		table.insert(handlers, fn)
		return {
			Disconnect = function()
				local i = table.find(handlers, fn)
				if i then
					table.remove(handlers, i)
				end
			end,
		}
	end
	function sig.fire(...: any)
		for _, fn in table.clone(handlers) do
			fn(...)
		end
	end
	function sig.count(): number
		return #handlers
	end
	return sig
end

function FakeEngine.uis(): any
	return fakeUis
end

-- Fire an input event as the engine would: kind "began" | "ended" | "changed".
function FakeEngine.input(kind: string, io: { [string]: any }, processed: boolean?)
	local event = {
		KeyCode = io.KeyCode or { Name = "Unknown" },
		UserInputType = io.UserInputType or roblox.Enum.UserInputType.Keyboard,
		Delta = io.Delta or roblox.Vector3.new(0, 0, 0),
		Position = io.Position or roblox.Vector3.new(0, 0, 0),
	}
	local sig = if kind == "began"
		then fakeUis.InputBegan
		elseif kind == "ended" then fakeUis.InputEnded
		else fakeUis.InputChanged
	sig.fire(event, processed == true)
end

local function fakeGame(): any
	renderStepped = FakeEngine.signal()
	fakeUis = {
		InputBegan = FakeEngine.signal(),
		InputEnded = FakeEngine.signal(),
		InputChanged = FakeEngine.signal(),
		MouseBehavior = roblox.Enum.MouseBehavior.Default,
		MouseEnabled = true,
		TouchEnabled = false,
		KeyboardEnabled = true,
		mouse = roblox.Vector2.new(960, 540), -- the test moves this
		focused = nil, -- a focused text box (anything non-nil) means the player is typing
		GetMouseLocation = function(self: any): any
			return self.mouse
		end,
		GetFocusedTextBox = function(self: any): any
			return self.focused
		end,
		GetGamepadState = function(_self: any, _pad: any): { any }
			return {}
		end,
	}
	local services: { [string]: any } = {
		UserInputService = fakeUis,
		RunService = {
			RenderStepped = renderStepped,
			BindToRenderStep = function(_self: any, name: string, _priority: number, fn: (dt: number) -> ())
				renderSteps[name] = fn
			end,
			UnbindFromRenderStep = function(_self: any, name: string)
				renderSteps[name] = nil
			end,
		},
		HttpService = {
			JSONEncode = function(_self: any, value: any): string
				return serde.encode("json", value)
			end,
		},
	}
	return {
		GetService = function(_self: any, name: string): any
			local svc = services[name]
			if svc == nil then
				svc = FakeEngine.new(name, name)
				services[name] = svc
			end
			return svc
		end,
	}
end

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
	env.Vector2 = roblox.Vector2
	env.UDim2 = roblox.UDim2
	env.Color3 = roblox.Color3
	env.Enum = roblox.Enum
	env.Instance = { new = FakeEngine.new }
	fakeWorkspace = FakeEngine.new("Workspace", "Workspace")
	local camera = FakeEngine.new("Camera", "Camera")
	rawset(camera, "ViewportSize", roblox.Vector2.new(1920, 1080))
	rawset(camera, "CFrame", roblox.CFrame.new(0, 0, 0))
	rawset(camera, "FieldOfView", 70)
	camera.Parent = fakeWorkspace
	rawset(fakeWorkspace, "CurrentCamera", camera)
	env.workspace = fakeWorkspace
	env.game = fakeGame()
	table.clear(renderSteps)
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
	table.clear(renderSteps)
	fakeWorkspace = nil
	fakeUis = nil
	renderStepped = nil
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
