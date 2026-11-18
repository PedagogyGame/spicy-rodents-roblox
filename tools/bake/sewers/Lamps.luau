--!strict
-- tools/bake/sewers/Lamps: the storm drains' lights, every one baked disabled (the client lane S3 turns on the
-- lights of the space the local squirrel is in; the game's Lighting settings are never touched).
--   build(kit, parent, pipe, anchors, covered)   one invisible "Lamps" part per pipe holding an Attachment per lamp
--        anchor ("Lamp", attributes Space and Kind = "lamp") with a warm PointLight (the owner's suggested range,
--        5.5 m, doubled: the client turns shadows on for the nearest two). Where a lamp is not inside one of the
--        owner's modules (covered(anchor) false), a small caged bulkhead on the wall shows where the light comes
--        from; inside a module his own fixture is there.
--   spot(kit, part, name, cframe, space, kind, props?)   a disabled SpotLight on an Attachment of `part`, facing the
--        frame's -Z (the chamber's ceiling light, the light grates)
-- Interface: build(...) -> number of lamps; spot(...) -> Attachment

local Kit = require("./Kit")

local Lamps = {}

Lamps.WARM = { 255, 210, 154 } -- the art pack's #ffd29a
Lamps.COOL = { 155, 217, 219 } -- #9bd9db
Lamps.RANGE = 11
Lamps.BRIGHTNESS = 1.1

function Lamps.build(
	kit: Kit.Kit,
	parent: any,
	pipe: any,
	anchors: { any },
	covered: (anchor: any) -> boolean,
	housings: any
): number
	local r = kit.roblox
	local CF, V = r.CFrame, r.Vector3
	local list = {}
	for _, a in anchors do
		if a.kind == "lamp" and a.pipe == pipe.id then
			table.insert(list, a)
		end
	end
	if #list == 0 then
		return 0
	end
	local first = list[1]
	local holder = kit:at(
		parent,
		"Lamps",
		CF.new(first.x, first.y, first.z),
		{ 0.2, 0.2, 0.2 },
		{ 0, 0, 0 },
		"SmoothPlastic",
		{ visual = true, transparency = 1, shadow = false, attrs = { Space = pipe.space } }
	)
	for i, a in list do
		local cool = pipe.section == "dry" and i % 2 == 0
		local at = kit:attach(holder, "Lamp", CF.new(a.x, a.y, a.z))
		at:SetAttribute("Space", pipe.space)
		at:SetAttribute("Kind", "lamp")
		kit:light(at, "PointLight", {
			Brightness = Lamps.BRIGHTNESS,
			Range = Lamps.RANGE,
			Color = kit:color(if cool then Lamps.COOL else Lamps.WARM),
			Shadows = false,
		})
		if not covered(a) then
			-- a caged bulkhead on the wall, its back to the wall (facing = into the passage)
			local f = a.facing
			local cf = CF.lookAt(V.new(a.x, a.y, a.z), V.new(a.x + f.x, a.y, a.z + f.z))
			kit:at(
				housings,
				"LampHousing",
				cf * CF.new(0, 0, 0.33),
				{ 0.5, 0.26, 0.2 },
				{ 44, 46, 48 },
				"Metal",
				{ visual = true }
			)
			kit:at(
				housings,
				"LampGlass",
				cf * CF.new(0, 0, 0.2),
				{ 0.36, 0.16, 0.1 },
				if cool then Lamps.COOL else Lamps.WARM,
				"Neon",
				{ visual = true, shadow = false }
			)
		end
	end
	return #list
end

function Lamps.spot(
	kit: Kit.Kit,
	part: any,
	name: string,
	cframe: any,
	space: string,
	kind: string,
	props: { [string]: any }?
): any
	local at = kit:attach(part, name, cframe)
	at:SetAttribute("Space", space)
	at:SetAttribute("Kind", kind)
	local p: { [string]: any } = {
		Brightness = 1.3,
		Range = 14,
		Angle = 75,
		Face = kit.roblox.Enum.NormalId.Front,
		Color = kit:color(Lamps.WARM),
		Shadows = false,
	}
	for k, v in props or {} do
		p[k] = v
	end
	kit:light(at, "SpotLight", p)
	return at
end

return Lamps
