--!strict
-- tools/bake/sewers/Kit: part helpers for the storm drains' bake (tools/bake/sewers.luau). Everything is placed in
-- a frame: a CFrame whose X is across (left of the way along), Y up and Z along a run (Kit.frame builds one from a
-- point and a direction), so a sloping or diagonal run is drawn with the same code as a level one. Lune only
-- (@lune/roblox Instances). Studs.
-- Interface: new(roblox) -> Kit; Kit.frame(origin {x,y,z}, along {x,y,z}) -> CFrame (Y = world up made square to
--   `along`, X = Y x Z); Kit:box(parent, name, frame, x0, x1, y0, y1, z0, z1, colour, material, opts?) -> Part;
--   Kit:at(parent, name, cframe, size {x,y,z}, colour, material, opts?) -> Part; Kit:cyl(parent, name, frame, a, b,
--   diameter, colour, material, opts?) (a cylinder from local point a to b); Kit:model(parent, name, attrs?);
--   Kit:folder(parent, name); Kit:light(parent, class, props) -> light (Enabled false); Kit:attach(part, name,
--   cframe) -> Attachment; Kit:label(part, face, text, props) -> SurfaceGui; Kit.count (parts made)
-- Defaults: anchored, CanCollide true, CanQuery = CanCollide, CanTouch false, smooth surfaces. opts.visual makes a
-- part that nothing collides with, queries or touches (dressing, bars, glow).

export type Opts = {
	collide: boolean?,
	query: boolean?,
	shadow: boolean?,
	transparency: number?,
	reflectance: number?,
	shape: string?, -- PartType name ("Cylinder", "Ball")
	class: string?, -- "Part" (default) | "WedgePart"
	visual: boolean?, -- no collision, query or touch
	attrs: { [string]: any }?,
}

local Kit = {}
Kit.__index = Kit

export type Kit = typeof(setmetatable({} :: { roblox: any, count: number }, Kit))

function Kit.new(roblox: any): Kit
	return setmetatable({ roblox = roblox, count = 0 }, Kit)
end

local function unit(x: number, y: number, z: number): (number, number, number)
	local l = math.sqrt(x * x + y * y + z * z)
	return x / l, y / l, z / l
end

-- A frame at `origin` running along `along`: Z along, Y world up made square to it, X = Y x Z (the left).
function Kit.frame(
	self: Kit,
	origin: { x: number, y: number, z: number },
	along: { x: number, y: number, z: number }
): any
	local V = self.roblox.Vector3
	local zx, zy, zz = unit(along.x, along.y, along.z)
	-- up made square to the run
	local k = zy
	local ux, uy, uz = unit(-k * zx, 1 - k * zy, -k * zz)
	-- X = Y x Z
	local xx, xy, xz = uy * zz - uz * zy, uz * zx - ux * zz, ux * zy - uy * zx
	return self.roblox.CFrame.fromMatrix(
		V.new(origin.x, origin.y, origin.z),
		V.new(xx, xy, xz),
		V.new(ux, uy, uz),
		V.new(zx, zy, zz)
	)
end

function Kit.color(self: Kit, c: { number }): any
	return self.roblox.Color3.fromRGB(c[1], c[2], c[3])
end

function Kit.model(self: Kit, parent: any, name: string, attrs: { [string]: any }?): any
	local m = self.roblox.Instance.new("Model")
	m.Name = name
	if attrs then
		for k, v in attrs do
			m:SetAttribute(k, v)
		end
	end
	m.Parent = parent
	return m
end

function Kit.folder(self: Kit, parent: any, name: string): any
	local f = self.roblox.Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function Kit.at(
	self: Kit,
	parent: any,
	name: string,
	cframe: any,
	size: { number },
	colour: { number },
	material: string,
	opts: Opts?
): any
	local o: Opts = opts or {}
	local Enum = self.roblox.Enum
	local p = self.roblox.Instance.new(o.class or "Part")
	p.Name = name
	p.Anchored = true
	local collide = if o.visual then false elseif o.collide == nil then true else o.collide
	p.CanCollide = collide
	p.CanQuery = if o.visual then false elseif o.query == nil then collide else o.query
	p.CanTouch = false
	p.CastShadow = if o.shadow == nil then true else o.shadow
	if o.shape then
		p.Shape = (Enum.PartType :: any)[o.shape]
	end
	p.Size = self.roblox.Vector3.new(size[1], size[2], size[3])
	p.CFrame = cframe
	p.Color = self:color(colour)
	p.Material = (Enum.Material :: any)[material]
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.transparency then
		p.Transparency = o.transparency
	end
	if o.reflectance then
		p.Reflectance = o.reflectance
	end
	if o.attrs then
		for k, v in o.attrs do
			p:SetAttribute(k, v)
		end
	end
	p.Parent = parent
	self.count += 1
	return p
end

-- A box from bounds in a frame (x across, y up, z along).
function Kit.box(
	self: Kit,
	parent: any,
	name: string,
	frame: any,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	colour: { number },
	material: string,
	opts: Opts?
): any
	local cf = frame * self.roblox.CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	return self:at(
		parent,
		name,
		cf,
		{ math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0) },
		colour,
		material,
		opts
	)
end

-- A box of `size` centred on a frame point, turned `roll` radians about the frame's Z (a vault facet).
function Kit.rolled(
	self: Kit,
	parent: any,
	name: string,
	frame: any,
	cx: number,
	cy: number,
	cz: number,
	roll: number,
	size: { number },
	colour: { number },
	material: string,
	opts: Opts?
): any
	local CF = self.roblox.CFrame
	return self:at(parent, name, frame * CF.new(cx, cy, cz) * CF.Angles(0, 0, roll), size, colour, material, opts)
end

-- A cylinder between two frame points (Roblox cylinders lie along their X).
function Kit.cyl(
	self: Kit,
	parent: any,
	name: string,
	frame: any,
	a: { number },
	b: { number },
	diameter: number,
	colour: { number },
	material: string,
	opts: Opts?
): any
	local V, CF = self.roblox.Vector3, self.roblox.CFrame
	local pa = frame * V.new(a[1], a[2], a[3])
	local pb = frame * V.new(b[1], b[2], b[3])
	local len = (pb - pa).Magnitude
	local o: Opts = table.clone(opts or {})
	o.shape = "Cylinder"
	-- lookAt points -Z at pb; turn so the part's X runs along the segment
	local cf = CF.lookAt((pa + pb) / 2, pb) * CF.Angles(0, math.pi / 2, 0)
	return self:at(parent, name, cf, { len, diameter, diameter }, colour, material, o)
end

-- A light (PointLight, SpotLight, SurfaceLight), always baked disabled: the client turns a space's lights on.
function Kit.light(self: Kit, parent: any, class: string, props: { [string]: any }): any
	local l = self.roblox.Instance.new(class)
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Enabled = false
	l.Parent = parent
	return l
end

function Kit.attach(self: Kit, part: any, name: string, cframe: any): any
	local a = self.roblox.Instance.new("Attachment")
	a.Name = name
	a.CFrame = part.CFrame:Inverse() * cframe
	a.Parent = part
	return a
end

-- Text on a part face: a SurfaceGui (PixelsPerStud) with one TextLabel filling it.
function Kit.label(self: Kit, part: any, face: string, text: string, props: { [string]: any }?): any
	local r = self.roblox
	local Enum = r.Enum
	local g = r.Instance.new("SurfaceGui")
	g.Name = "Text"
	g.Face = (Enum.NormalId :: any)[face]
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 1
	g.Parent = part
	local t = r.Instance.new("TextLabel")
	t.Name = "Label"
	t.BackgroundTransparency = 1
	t.Size = r.UDim2.fromScale(1, 1)
	t.Text = text
	t.TextScaled = true
	-- FontFace, not Font: the enum alias does not serialise from Lune (props.Font names an Enum.Font item)
	t.FontFace = r.Font.fromEnum(Enum.Font.Arcade)
	t.TextColor3 = r.Color3.fromRGB(230, 226, 212)
	for k, v in props or {} do
		if k == "Font" then
			t.FontFace = r.Font.fromEnum((Enum.Font :: any)[v])
		else
			(t :: any)[k] = v
		end
	end
	t.Parent = g
	return g
end

return Kit
