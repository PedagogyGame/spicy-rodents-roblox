--!strict
-- tools/bake/alley/Kit: part helpers for baking an attraction in its own local frame (Shared/Attractions/
-- AlleyLayout: X across, Y up from the floor, D down the lane). Every helper takes local coordinates and
-- writes world CFrames (yaw about Y from the placement). Lune only (@lune/roblox Instances).
-- Interface: new(roblox, place) -> Kit; Kit:box(parent, name, x0, x1, y0, y1, d0, d1, color, material, opts?);
--   Kit:at(parent, name, cx, cy, cd, sx, sy, sd, color, material, opts?) (opts.rot = local rotation CFrame);
--   Kit:cyl(parent, name, cx, cy, cd, length, diameter, axis, color, material, opts?); Kit:ball(...);
--   Kit:wedge(...); Kit:cf(cx, cy, cd, rot?) -> CFrame; Kit:model(parent, name) -> Model; Kit:folder(...);
--   Kit:light(part, class, props); Kit:gui(part, face, ppS) -> SurfaceGui; Kit:label(gui, props) -> TextLabel;
--   Kit:holes(x0, x1, d0, d1, holes) -> rects (rectangle minus axis-aligned holes); Kit.count

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")

export type Opts = {
	collide: boolean?, -- default true
	query: boolean?, -- default = collide
	touch: boolean?, -- default false
	shadow: boolean?, -- default true
	transparency: number?,
	reflectance: number?,
	rot: any?, -- local rotation (CFrame) applied about the part centre
	shape: string?, -- PartType name
	class: string?, -- "Part" (default) | "WedgePart" | "CornerWedgePart"
	group: string?, -- CollisionGroup
	anchored: boolean?, -- default true
	massless: boolean?,
	attrs: { [string]: any }?,
}

local Kit = {}
Kit.__index = Kit

export type Kit = typeof(setmetatable(
	{} :: { roblox: any, place: AlleyLayout.Place, yawCF: any, count: number, materials: { [string]: any } },
	Kit
))

function Kit.new(roblox: any, place: AlleyLayout.Place): Kit
	local self = setmetatable({
		roblox = roblox,
		place = place,
		yawCF = roblox.CFrame.Angles(0, place.yaw, 0),
		count = 0,
		materials = {},
	}, Kit)
	return self
end

function Kit.color(self: Kit, c: { number }): any
	return self.roblox.Color3.fromRGB(c[1], c[2], c[3])
end

-- World CFrame of a local point (plus an optional local rotation).
function Kit.cf(self: Kit, cx: number, cy: number, cd: number, rot: any?): any
	local x, y, z = AlleyLayout.toWorld(self.place, cx, cy, cd)
	local base = self.roblox.CFrame.new(x, y, z) * self.yawCF
	if rot then
		return base * rot
	end
	return base
end

function Kit.model(self: Kit, parent: any, name: string): any
	local m = self.roblox.Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function Kit.folder(self: Kit, parent: any, name: string): any
	local f = self.roblox.Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function apply(self: Kit, p: any, name: string, color: { number }, material: string, opts: Opts?)
	local o: Opts = opts or {}
	local Enum = self.roblox.Enum
	p.Name = name
	p.Anchored = if o.anchored == false then false else true
	local collide = if o.collide == nil then true else o.collide
	p.CanCollide = collide
	p.CanQuery = if o.query == nil then collide else o.query
	p.CanTouch = o.touch == true
	p.CastShadow = if o.shadow == nil then true else o.shadow
	p.Color = self:color(color)
	p.Material = (Enum.Material :: any)[material]
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.transparency then
		p.Transparency = o.transparency
	end
	if o.reflectance then
		p.Reflectance = o.reflectance
	end
	if o.group then
		p.CollisionGroup = o.group
	end
	if o.massless then
		p.Massless = true
	end
	if o.attrs then
		for k, v in o.attrs do
			p:SetAttribute(k, v)
		end
	end
	self.count += 1
end

-- Axis-aligned (in the local frame) box from bounds.
function Kit.box(
	self: Kit,
	parent: any,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	d0: number,
	d1: number,
	color: { number },
	material: string,
	opts: Opts?
): any
	return self:at(
		parent,
		name,
		(x0 + x1) / 2,
		(y0 + y1) / 2,
		(d0 + d1) / 2,
		math.abs(x1 - x0),
		math.abs(y1 - y0),
		math.abs(d1 - d0),
		color,
		material,
		opts
	)
end

-- A part centred at a local point; size along (X, Y, D) before the optional local rotation.
function Kit.at(
	self: Kit,
	parent: any,
	name: string,
	cx: number,
	cy: number,
	cd: number,
	sx: number,
	sy: number,
	sd: number,
	color: { number },
	material: string,
	opts: Opts?
): any
	local o: Opts = opts or {}
	local p = self.roblox.Instance.new(o.class or "Part")
	if o.shape then
		p.Shape = (self.roblox.Enum.PartType :: any)[o.shape]
	end
	p.Size = self.roblox.Vector3.new(math.max(sx, 0.001), math.max(sy, 0.001), math.max(sd, 0.001))
	p.CFrame = self:cf(cx, cy, cd, o.rot)
	apply(self, p, name, color, material, o)
	p.Parent = parent
	return p
end

-- Cylinder along a local axis ("X", "Y" or "D").
function Kit.cyl(
	self: Kit,
	parent: any,
	name: string,
	cx: number,
	cy: number,
	cd: number,
	length: number,
	diameter: number,
	axis: string,
	color: { number },
	material: string,
	opts: Opts?
): any
	local CFrame = self.roblox.CFrame
	local rot
	if axis == "Y" then
		rot = CFrame.Angles(0, 0, math.pi / 2)
	elseif axis == "D" then
		rot = CFrame.Angles(0, math.pi / 2, 0)
	else
		rot = CFrame.new()
	end
	local o: Opts = table.clone(opts or {})
	if o.rot then
		rot = o.rot * rot
	end
	o.rot = rot
	o.shape = "Cylinder"
	return self:at(parent, name, cx, cy, cd, length, diameter, diameter, color, material, o)
end

function Kit.ball(
	self: Kit,
	parent: any,
	name: string,
	cx: number,
	cy: number,
	cd: number,
	diameter: number,
	color: { number },
	material: string,
	opts: Opts?
): any
	local o: Opts = table.clone(opts or {})
	o.shape = "Ball"
	return self:at(parent, name, cx, cy, cd, diameter, diameter, diameter, color, material, o)
end

-- WedgePart: full bottom and back (+Z = local -D) faces, slope rising toward local -D unless rotated.
function Kit.wedge(
	self: Kit,
	parent: any,
	name: string,
	cx: number,
	cy: number,
	cd: number,
	sx: number,
	sy: number,
	sd: number,
	color: { number },
	material: string,
	opts: Opts?
): any
	local o: Opts = table.clone(opts or {})
	o.class = "WedgePart"
	return self:at(parent, name, cx, cy, cd, sx, sy, sd, color, material, o)
end

-- A round rod (cylinder) between two local points.
function Kit.rod(
	self: Kit,
	parent: any,
	name: string,
	x0: number,
	y0: number,
	d0: number,
	x1: number,
	y1: number,
	d1: number,
	diameter: number,
	color: { number },
	material: string,
	opts: Opts?
): any
	local CFrame = self.roblox.CFrame
	local a = self:cf(x0, y0, d0).Position
	local b = self:cf(x1, y1, d1).Position
	local len = (b - a).Magnitude
	local o: Opts = table.clone(opts or {})
	o.shape = "Cylinder"
	if o.collide == nil then
		o.collide = false
	end
	local p = self:at(parent, name, 0, 0, 0, len, diameter, diameter, color, material, o)
	p.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
	return p
end

function Kit.light(self: Kit, part: any, class: string, props: { [string]: any }): any
	local l = self.roblox.Instance.new(class)
	for k, v in props do
		if k == "Color" then
			l.Color = self:color(v)
		elseif k == "Face" then
			l.Face = (self.roblox.Enum.NormalId :: any)[v]
		else
			(l :: any)[k] = v
		end
	end
	l.Parent = part
	return l
end

-- A SurfaceGui on a part face (PixelsPerStud sizing).
function Kit.gui(self: Kit, part: any, face: string, pps: number?): any
	local Enum = self.roblox.Enum
	local g = self.roblox.Instance.new("SurfaceGui")
	g.Face = (Enum.NormalId :: any)[face]
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = pps or 50
	g.LightInfluence = 0
	g.Brightness = 1.5
	g.Parent = part
	return g
end

function Kit.label(self: Kit, gui: any, props: { [string]: any }): any
	local r = self.roblox
	local t = r.Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = r.UDim2.fromScale(1, 1)
	t.TextScaled = true
	-- FontFace, not Font: the enum alias does not serialise from Lune
	t.FontFace = r.Font.fromEnum(r.Enum.Font.GothamBold)
	t.TextColor3 = self:color({ 255, 255, 255 })
	for k, v in props do
		if k == "TextColor" then
			t.TextColor3 = self:color(v)
		elseif k == "Bg" then
			t.BackgroundTransparency = 0
			t.BackgroundColor3 = self:color(v)
		elseif k == "Font" then
			t.FontFace = r.Font.fromEnum((r.Enum.Font :: any)[v])
		elseif k == "Pos" then
			t.Position = r.UDim2.fromScale(v[1], v[2])
		elseif k == "Size" then
			t.Size = r.UDim2.fromScale(v[1], v[2])
		else
			(t :: any)[k] = v
		end
	end
	t.Parent = gui
	return t
end

-- Rectangle [x0,x1] x [d0,d1] minus axis-aligned holes { {x0, x1, d0, d1} }: non-overlapping rectangles
-- covering the rest (guillotine split, hole by hole).
function Kit.holes(_self: Kit, x0: number, x1: number, d0: number, d1: number, holes: { { number } }): { { number } }
	local rects = { { x0, x1, d0, d1 } }
	for _, h in holes do
		local nextRects = {}
		for _, r in rects do
			local ix0, ix1 = math.max(r[1], h[1]), math.min(r[2], h[2])
			local id0, id1 = math.max(r[3], h[3]), math.min(r[4], h[4])
			if ix0 >= ix1 - 1e-6 or id0 >= id1 - 1e-6 then
				table.insert(nextRects, r)
			else
				-- left and right strips (full depth), then front and back between them
				if ix0 > r[1] + 1e-6 then
					table.insert(nextRects, { r[1], ix0, r[3], r[4] })
				end
				if ix1 < r[2] - 1e-6 then
					table.insert(nextRects, { ix1, r[2], r[3], r[4] })
				end
				if id0 > r[3] + 1e-6 then
					table.insert(nextRects, { ix0, ix1, r[3], id0 })
				end
				if id1 < r[4] - 1e-6 then
					table.insert(nextRects, { ix0, ix1, id1, r[4] })
				end
			end
		end
		rects = nextRects
	end
	return rects
end

return Kit
