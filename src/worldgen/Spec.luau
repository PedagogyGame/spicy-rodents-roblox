--!strict
-- ServerScriptService.Server.WorldGen.Spec
-- BuildPlan data types and the part/extra helpers every builder family uses (BUILD_PLAN §1.4
-- WorldGen; W1 #7). A BuildPlan is pure data: parts (world-space boxes, cylinders and wedges) plus
-- extras (SurfaceGui signs, ProximityPrompt placeholders, Attachments, Beams). Factory turns it into
-- Instances in Lune or the engine; Bake hashes it (BakeParity).
-- Interface: list() -> PartList; PartList:add(frame, name, mx, my, mz, sx, sy, sz, opts) -> PartSpec;
--   PartList:world(name, spec) ; PartList:extra(ExtraSpec)
-- Pure: no Instances, no side effects on require.

local Geometry = require("./Geometry")

local Spec = {}

export type PartSpec = {
	name: string,
	cx: number,
	cy: number,
	cz: number,
	yaw: number, -- Roblox rotation about +Y (radians), LookVector = (-sin, 0, -cos)
	pitch: number, -- then about the part's own X
	roll: number?, -- then about the part's own Z (cylinders: the axis is local X)
	sx: number,
	sy: number,
	sz: number,
	color: { number },
	material: string,
	canCollide: boolean,
	transparency: number,
	shape: string?, -- "Block" (default) | "Cylinder"
	role: string?, -- Body, Roof, Wall, Floor, Door, Sign, Room, Station, Shelf, Pad, Furniture, Limb, Pipe, Rail, Post, Anchor, Skyline
	canQuery: boolean?, -- default: transparency < 1
	attrs: { [string]: string | number | boolean }?,
}

-- Non-part instances, parented to the named part of the same model.
--   SurfaceGui: text on `face` (Enum.NormalId name) of `part`
--   Prompt:     an Attachment `name` at local `offset` holding a disabled ProximityPrompt placeholder
--   Attachment: `name` at local `offset` with attributes
--   Beam:       between Attachments `a` and `b` of `part`; p0/p1 are their world points (RouteCheck)
export type ExtraSpec = {
	kind: string,
	part: string,
	name: string,
	text: string?,
	face: string?,
	action: string?,
	offset: { number }?,
	a: string?,
	b: string?,
	p0: { number }?,
	p1: { number }?,
	width: number?,
	color: { number }?,
	attrs: { [string]: string | number | boolean }?,
}

export type BuildPlan = {
	kind: string, -- "lot" | "road" | "props" | "lamps" | "skyline"
	id: string,
	category: string,
	lod: string,
	streaming: string,
	attributes: { [string]: string | number | boolean },
	parts: { PartSpec },
	extras: { ExtraSpec }?,
}

export type Opts = {
	color: { number }?,
	material: string?,
	canCollide: boolean?,
	transparency: number?,
	yaw: number?, -- local yaw on top of the frame's
	pitch: number?,
	roll: number?,
	shape: string?,
	role: string?,
	canQuery: boolean?,
	attrs: { [string]: string | number | boolean }?,
}

export type PartList = {
	parts: { PartSpec },
	extras: { ExtraSpec },
	names: { [string]: boolean },
	add: (self: PartList, f: Geometry.Frame, name: string, mx: number, my: number, mz: number, sx: number, sy: number, sz: number, o: Opts?) -> PartSpec,
	world: (self: PartList, spec: PartSpec) -> PartSpec,
	extra: (self: PartList, e: ExtraSpec) -> (),
}

local GREY = { 200, 200, 200 }

local function world(self: PartList, spec: PartSpec): PartSpec
	if self.names[spec.name] then
		error("Spec: duplicate part name " .. spec.name)
	end
	self.names[spec.name] = true
	table.insert(self.parts, spec)
	return spec
end

local function add(
	self: PartList,
	f: Geometry.Frame,
	name: string,
	mx: number,
	my: number,
	mz: number,
	sx: number,
	sy: number,
	sz: number,
	o: Opts?
): PartSpec
	local opts: Opts = o or {}
	local wx, wy, wz = Geometry.point(f, mx, my, mz)
	return world(self, {
		name = name,
		cx = wx,
		cy = wy,
		cz = wz,
		yaw = f.yaw + (opts.yaw or 0),
		pitch = opts.pitch or 0,
		roll = opts.roll,
		sx = math.max(sx, 0.05),
		sy = math.max(sy, 0.05),
		sz = math.max(sz, 0.05),
		color = opts.color or GREY,
		material = opts.material or "SmoothPlastic",
		canCollide = if opts.canCollide == nil then true else opts.canCollide,
		transparency = opts.transparency or 0,
		shape = opts.shape,
		role = opts.role,
		canQuery = opts.canQuery,
		attrs = opts.attrs,
	})
end

local function extra(self: PartList, e: ExtraSpec)
	table.insert(self.extras, e)
end

-- What a builder family gets for one lot (model-local studs: mx across along the model's RightVector,
-- mz toward the back; the front face is at mz = -D/2).
export type LotCtx = {
	lot: any,
	kit: any,
	frame: Geometry.Frame,
	W: number, -- local width (studs) across the front
	D: number, -- local depth (studs)
	seat: number, -- ground height (studs) the lot sits on
	params: { [string]: any },
	list: PartList,
	building: any?, -- generated/Buildings record (Hospital, PoliceStation)
	interior: any?, -- generated/Interiors template (FRB houses)
	attributes: { [string]: string | number | boolean },
}

Spec.SPU = 2.5 -- studs per HTML unit (Config/Units; W1 data stays in HTML units, builders scale here)

function Spec.list(): PartList
	return { parts = {}, extras = {}, names = {}, add = add, world = world, extra = extra } :: PartList
end

return Spec
