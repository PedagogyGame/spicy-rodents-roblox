--!strict
-- StarterPlayer.StarterPlayerScripts.Client.World.SewerAmbience
-- What the storm drains feel like from inside, on this client only (BRIEF_ADDENDUM D8; the pipes are
-- Shared/World/SewerLayout, run on the enclosed-run contract Shared/Routes/Enclosure; lane S3 of the sewer plan).
-- While the body this player holds is a squirrel (or the Spicy Rodent) inside a drain, and for C.linger seconds
-- after it comes out:
--   * the look: a cooler, darker grade (ColorCorrectionEffect "SewerGrade") and a short depth of field
--     (DepthOfFieldEffect "SewerFocus"), both parented to the CURRENT CAMERA and eased in and out. Nothing here
--     writes a Lighting property (the D7 preset, World/Sky and NightVision own those): local means only.
--   * the light: that space's lamps and grate beams in the bake (Workspace.Sewers) switched on, shadows on the two
--     nearest lamps only; every light is put back exactly as the bake left it on the way out. The water's textures
--     scroll along the flow.
--   * the sound: SoundService.AmbientReverb = SewerPipe (restored exactly on the way out) and the named cues below.
--   * the words: a place name at the top of the screen ("UNDERGROUND · STORM DRAIN 1 CROSSROADS"), and the key
--     to press: "E: down the drain" on a grate (only where E really goes in: on it, facing in), "W: climb out" in
--     the top of a shaft; the controller's refusals reworded for a drain (filter: "No room to jump down here").
-- Sound cues (SewerAmbience.CUES, cue -> asset id). NOTHING IS UPLOADED AND NOTHING PLAYS YET: every id is empty, so
-- play() is silent and only counted; filling an id in (docs/AUDIO_BUDGET.md, Sewers) makes it sound.
--   sewer.grateIn / grateOut   going down / coming up out of a mouth
--   sewer.rung                 every C.rungStep studs climbed or descended in a shaft
--   sewer.footEcho             every C.echoStride studs run along a passage (the echo of the footfall)
--   sewer.drip                 at random, every C.drip[1] to C.drip[2] seconds, at a cue point near the body
--   sewer.trickle (loop)       the water channel, in a brick drain (P1, P3)
--   sewer.riverHum (loop)      the river overhead, in the dry culvert (P2)
--   sewer.streetMurmur (loop)  within C.murmurRadius of a mouth, from below
--   sewer.hiss                 the small alligator (v5.4's idle predator for the sewer: a sound and a line, nothing
--                              to see): still for C.hissAfter seconds underground; the toast is HISS_LINE
--   sewer.carOverhead, sewer.trolleyOverhead   named, not fired yet (they need the traffic poses over a pipe)
-- Who goes down: squirrels and the Spicy Rodent (a person, the fox or a deer never sees the prompt and is never
-- "inside"). Computer squirrels are not this client's business.
-- Interface (pure): C; CUES; HISS_LINE; placeName(pipe) -> string; canGoDown(species?, variant?) -> boolean;
--   shaftAt(layout, x, y, z) -> Mouth?; prompt(layout, view) -> string?; grade(level) -> { brightness, contrast,
--   saturation, tint }; focus(level) -> { far, distance, radius }; reword(text, underground) -> string;
--   cuePoints(layout) -> { CuePoint }; loopFor(layout, space) -> cue?
-- Engine: start(ctx) -> Handle; ctx = { current: () -> Model?, state: (() -> { species: string? })?,
--   toast: ((text, seconds?) -> ())?, layout: Layout?, root: Instance? (default Workspace.Sewers),
--   gui: Instance? (default the PlayerGui), seed: number? }
--   Handle = { step(dt), space() -> string?, prompt() -> string?, place() -> string?, level() -> number,
--   filter(text) -> text, counts() -> { [cue]: number }, loops() -> { [cue]: boolean }, stop() }
--   start binds step to RunService.RenderStepped; the joiner calls it from Client/Main (with PossessionClient's
--   current and state, and the menu's toast) and passes every toast through handle.filter.
-- No side effects on require.

local Import = require("../Import")
local SewerLayout = Import.shared("World/SewerLayout") :: typeof(require("../../shared/World/SewerLayout"))
local Enclosure = Import.shared("Routes/Enclosure") :: typeof(require("../../shared/Routes/Enclosure"))
local Ladder = Import.shared("Roles/Ladder") :: typeof(require("../../shared/Roles/Ladder"))
local Rng = Import.shared("Util/Rng") :: typeof(require("../../shared/Util/Rng"))
local Squirrel = require("../Controllers/Squirrel")

-- (the shared module comes through Import, so its exported types are taken from what its functions return)
type Layout = typeof(SewerLayout.new((nil :: any) :: any))
type Mouth = typeof(((nil :: any) :: Layout).mouths[1])
type Pipe = typeof(((nil :: any) :: Layout).pipes[1])

local SewerAmbience = {}

SewerAmbience.C = {
	linger = 0.3, -- s: the inside look and sound hold this long after the body leaves a drain's volume
	ease = 6, -- per second: how fast the look comes in and goes
	near = 3.5, -- studs (level) from a mouth point within which the way in is explained
	climbWindow = 6, -- studs under the street: the top of a shaft, where "W: climb out" shows
	descending = -1.0, -- studs/s: going down a shaft faster than this is not climbing out
	rungStep = 1.0, -- studs of shaft per rung
	echoStride = 2.75, -- studs run per footfall echo (half v5.4's 5.5-stud bound)
	drip = { 2, 6 }, -- s between drips, at random
	murmurRadius = 8, -- studs (level) from a mouth within which the street is heard
	shadowLamps = 2, -- the nearest this many lamps cast shadows
	lampEvery = 0.25, -- s between re-sorting the lamps by distance
	rescanEvery = 2.0, -- s between looking for the space's lights again (streaming brings them in late)
	still = 0.2, -- studs/s: slower than this is standing still (for the alligator)
	hissAfter = Ladder.params.afkSecs - Ladder.params.afkWarnSecs, -- s still underground before the hiss (D34's
	-- warning, v5.4's idle predator)
	cueSpacing = 12, -- studs between cue points along a passage
	maxLog = 64, -- the last cue firings kept for a developer (and the specs)
}

SewerAmbience.CUES = {
	["sewer.grateIn"] = "",
	["sewer.grateOut"] = "",
	["sewer.rung"] = "",
	["sewer.footEcho"] = "",
	["sewer.drip"] = "",
	["sewer.trickle"] = "",
	["sewer.riverHum"] = "",
	["sewer.streetMurmur"] = "",
	["sewer.hiss"] = "",
	["sewer.carOverhead"] = "",
	["sewer.trolleyOverhead"] = "",
} :: { [string]: string }

SewerAmbience.HISS_LINE = "A low hiss and a ripple in the sewer water…"

local PROMPT = {
	down = "E: down the drain",
	face = "Face the opening's way (%s), then E: down the drain",
	step = "Step onto the %s: E goes down the drain",
	climb = "W: climb out",
}

-- the controller's refusals (Controllers/Squirrel hint reasons) as they read in a drain
local REWORD: { [string]: string } = {
	noRoom = "No room to jump down here: run on to a grate (W at the top climbs out)",
	noTransfer = "Nothing to grab down here: run on to a grate (W at the top climbs out)",
	nothingNear = "Nothing to grab down here: run on to a grate (W at the top climbs out)",
}

-- The place name at the top of the screen for a pipe ("UNDERGROUND · STORM DRAIN 1 CROSSROADS").
function SewerAmbience.placeName(pipe: Pipe): string
	return `UNDERGROUND · {pipe.sign}`
end

-- Who can go down a drain (the survey's default: squirrels and the Spicy Rodent only).
function SewerAmbience.canGoDown(species: string?, variant: string?): boolean
	return species == "squirrel" or species == "rodent" or variant == "spicy"
end

-- The mouth whose shaft holds (x, y, z) (below the street's skin, above the passage's floor), or nil.
function SewerAmbience.shaftAt(layout: Layout, x: number, y: number, z: number): Mouth?
	local skin = SewerLayout.C.streetSkin
	for _, m in layout.mouths do
		local s = m.shaft
		local half = s.inside / 2
		if math.abs(x - s.cx) <= half and math.abs(z - s.cz) <= half and y < s.top - skin and y >= s.bottom - 1 then
			return m
		end
	end
	return nil
end

local COMPASS = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" }
-- (world: north = +z, east = +x)
local function compass(dx: number, dz: number): string
	local a = math.atan2(dx, dz) -- 0 north, pi/2 east
	local i = math.floor(a / (math.pi / 4) + 0.5) % 8
	return COMPASS[i + 1]
end

export type View = {
	x: number,
	y: number, -- the feet
	z: number,
	fx: number, -- the way the body faces (level, any length)
	fz: number,
	vy: number, -- studs/s, up
	canGo: boolean, -- a squirrel or the rodent
	space: string?, -- SewerLayout.contains at the feet
}

-- What to press here (nil: nothing to say). On a mouth: E goes in exactly where the motor takes it in (Enclosure
-- rule 1 for a body facing the way it stands: within the mouth's reach, within C.rise of its height, not more than
-- C.behind past it, facing in within acos(C.intoDot)); near one, how to get there. In the top C.climbWindow studs of
-- a shaft and not dropping: W climbs out.
function SewerAmbience.prompt(layout: Layout, view: View): string?
	if not view.canGo then
		return nil
	end
	local EC = Enclosure.C
	if view.space then
		local m = SewerAmbience.shaftAt(layout, view.x, view.y, view.z)
		if m and view.y >= m.shaft.top - SewerAmbience.C.climbWindow and view.vy >= SewerAmbience.C.descending then
			return PROMPT.climb
		end
		return nil
	end
	local m, level = layout.nearestMouth(view.x, view.z, SewerAmbience.C.near)
	if m == nil or math.abs(view.y - m.y) > EC.rise + 0.5 then
		return nil
	end
	local dx, dz = view.x - m.x, view.z - m.z
	local past = dx * m.out.x + dz * m.out.z < -EC.behind
	if level > m.reach or past or math.abs(view.y - m.y) > EC.rise then
		return string.format(PROMPT.step, m.kind)
	end
	local fl = math.sqrt(view.fx * view.fx + view.fz * view.fz)
	if fl > 1e-6 and -(view.fx * m.out.x + view.fz * m.out.z) / fl >= EC.intoDot then
		return PROMPT.down
	end
	return string.format(PROMPT.face, compass(-m.out.x, -m.out.z))
end

-- The colour grade at `level` (0 outside, 1 inside): darker, cooler, a little flatter, never black.
function SewerAmbience.grade(
	level: number
): { brightness: number, contrast: number, saturation: number, tint: { number } }
	local l = math.clamp(level, 0, 1)
	return {
		brightness = -0.1 * l,
		contrast = 0.12 * l,
		saturation = -0.3 * l,
		tint = { 255 - 40 * l, 255 - 25 * l, 255 - 30 * l },
	}
end

-- The depth of field at `level`: what is past a few pipe lengths softens, so the tunnel reads close.
function SewerAmbience.focus(level: number): { far: number, distance: number, radius: number }
	local l = math.clamp(level, 0, 1)
	return { far = 0.35 * l, distance = 6, radius = 18 }
end

local reasonText: { [string]: string }? = nil
-- The controller's toast for a hint, as it reads in a drain (`underground`), else unchanged.
function SewerAmbience.reword(text: string, underground: boolean): string
	if not underground then
		return text
	end
	local map = reasonText
	if map == nil then
		local built: { [string]: string } = {}
		for reason, said in REWORD do
			local generic = Squirrel.feedback({}, { { kind = "hint", reason = reason } }, true)
			if generic then
				built[generic] = said
			end
		end
		reasonText = built
		map = built
	end
	return (map :: { [string]: string })[text] or text
end

export type CuePoint = { cue: string, space: string, pipe: string, x: number, y: number, z: number }

-- The water loop of a space: trickle where its section has a channel, the river's hum in the dry culvert.
function SewerAmbience.loopFor(layout: Layout, space: string): string?
	for _, p in layout.pipes do
		if p.space == space then
			local section = layout.data.sections[p.section]
			return if section and section.water ~= nil then "sewer.trickle" else "sewer.riverHum"
		end
	end
	return nil
end

-- The named cue points: drips and the water loop every C.cueSpacing studs along each passage (on its axis at the
-- walkway's height), the street's murmur at the top of every shaft. Where a sound plays once ids exist.
function SewerAmbience.cuePoints(layout: Layout): { CuePoint }
	local out: { CuePoint } = {}
	for _, p in layout.pipes do
		local loop = SewerAmbience.loopFor(layout, p.space) or "sewer.trickle"
		for _, pass in p.passages do
			local pts = pass.points
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2 + (b.z - a.z) ^ 2)
				local n = math.max(1, math.floor(len / SewerAmbience.C.cueSpacing))
				for k = 0, n - 1 do
					local f = (k + 0.5) / n
					local x, y, z = a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, a.z + (b.z - a.z) * f
					table.insert(out, { cue = "sewer.drip", space = p.space, pipe = p.id, x = x, y = y + 3, z = z })
					table.insert(out, { cue = loop, space = p.space, pipe = p.id, x = x, y = y, z = z })
				end
			end
		end
	end
	for _, m in layout.mouths do
		table.insert(
			out,
			{ cue = "sewer.streetMurmur", space = m.space, pipe = m.pipe, x = m.shaft.cx, y = m.y, z = m.shaft.cz }
		)
	end
	return out
end

-- Engine part ---------------------------------------------------------------------------------------------------------

export type Handle = {
	step: (dt: number) -> (),
	space: () -> string?,
	prompt: () -> string?,
	place: () -> string?,
	level: () -> number,
	filter: (text: string) -> string,
	counts: () -> { [string]: number },
	loops: () -> { [string]: boolean? },
	log: () -> { { cue: string, x: number, y: number, z: number } },
	stop: () -> (),
}

export type Context = {
	current: () -> Model?,
	state: (() -> { [string]: any })?,
	toast: ((text: string, seconds: number?) -> ())?,
	layout: Layout?,
	root: Instance?,
	gui: Instance?,
	seed: number?,
}

type Saved = { enabled: boolean, shadows: boolean? }

local function lightPosition(light: Instance): Vector3?
	local parent = light.Parent
	if parent == nil then
		return nil
	end
	if parent:IsA("BasePart") then
		return (parent :: BasePart).Position
	elseif parent:IsA("Attachment") then
		return (parent :: Attachment).WorldPosition
	end
	return nil
end

-- the space an instance of the bake belongs to: its own Space attribute, else the nearest ancestor's, else an
-- ancestor named after the space or its pipe
local function spaceOfInstance(inst: Instance, stop: Instance, names: { [string]: string }): string?
	local node: Instance? = inst
	while node and node ~= stop do
		local s = node:GetAttribute("Space")
		if type(s) == "string" then
			return s
		end
		local byName = names[node.Name]
		if byName then
			return byName
		end
		node = node.Parent
	end
	return nil
end

function SewerAmbience.start(ctx: Context): Handle
	local C = SewerAmbience.C
	local layout = ctx.layout or SewerLayout.default()
	local RunService = game:GetService("RunService")
	local SoundService = game:GetService("SoundService")
	local rng = Rng.new(ctx.seed or 1911)

	local pipeBySpace: { [string]: Pipe } = {}
	local names: { [string]: string } = {}
	local points: { CuePoint } = {}
	if layout then
		for _, p in layout.pipes do
			pipeBySpace[p.space] = p
			names[p.space] = p.space
			names[p.id] = p.space
		end
		points = SewerAmbience.cuePoints(layout)
	end

	-- the words on screen
	local gui = Instance.new("ScreenGui")
	gui.Name = "SewerHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Enabled = true
	local function label(name: string, anchorY: number, scaleY: number, offsetY: number, size: number): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.AnchorPoint = Vector2.new(0.5, anchorY)
		l.Position = UDim2.new(0.5, 0, scaleY, offsetY)
		l.Size = UDim2.fromOffset(520, size + 10)
		l.BackgroundTransparency = 0.4
		l.BackgroundColor3 = Color3.fromRGB(14, 18, 16)
		l.TextColor3 = Color3.fromRGB(226, 232, 214)
		l.TextSize = size
		l.Font = Enum.Font.GothamBold
		l.TextWrapped = true
		l.Text = ""
		l.Visible = false
		l.Parent = gui
		return l
	end
	local placeLabel = label("Place", 0, 0, 10, 16)
	local promptLabel = label("Prompt", 1, 0.7, 0, 18)
	local guiParent = ctx.gui
	if guiParent == nil then
		local player = game:GetService("Players").LocalPlayer
		guiParent = if player then player:FindFirstChild("PlayerGui") else nil
	end
	gui.Parent = guiParent

	-- the look (camera post effects, made on first use)
	local gradeFx: ColorCorrectionEffect? = nil
	local focusFx: DepthOfFieldEffect? = nil
	local function effects(): (ColorCorrectionEffect, DepthOfFieldEffect)
		if gradeFx == nil or focusFx == nil then
			local camera = workspace.CurrentCamera
			local g = Instance.new("ColorCorrectionEffect")
			g.Name = "SewerGrade"
			g.Enabled = false
			g.Parent = camera
			local f = Instance.new("DepthOfFieldEffect")
			f.Name = "SewerFocus"
			f.Enabled = false
			f.NearIntensity = 0
			f.Parent = camera
			gradeFx, focusFx = g, f
		end
		return gradeFx :: ColorCorrectionEffect, focusFx :: DepthOfFieldEffect
	end

	-- sounds: counted always, played only with an id
	local counts: { [string]: number } = {}
	local log: { { cue: string, x: number, y: number, z: number } } = {}
	local looping: { [string]: boolean? } = {}
	local loopSounds: { [string]: Sound } = {}
	local function play(cue: string, at: Vector3?)
		counts[cue] = (counts[cue] or 0) + 1
		local p = at or Vector3.new(0, 0, 0)
		table.insert(log, { cue = cue, x = p.X, y = p.Y, z = p.Z })
		if #log > C.maxLog then
			table.remove(log, 1)
		end
		local id = SewerAmbience.CUES[cue]
		if id == nil or id == "" then
			return
		end
		local s = Instance.new("Sound")
		s.Name = `Sewer_{cue}`
		s.SoundId = id
		s.Volume = 0.6
		s.Parent = SoundService
		s.Ended:Once(function()
			s:Destroy()
		end)
		s:Play()
	end
	local function loop(cue: string, on: boolean)
		if (looping[cue] == true) == on then
			return
		end
		looping[cue] = if on then true else nil
		if on then
			counts[cue] = (counts[cue] or 0) + 1
		end
		local id = SewerAmbience.CUES[cue]
		if on and id ~= nil and id ~= "" then
			local s = Instance.new("Sound")
			s.Name = `Sewer_{cue}`
			s.SoundId = id
			s.Looped = true
			s.Volume = 0.4
			s.Parent = SoundService
			s:Play()
			loopSounds[cue] = s
		elseif not on and loopSounds[cue] then
			(loopSounds[cue] :: Sound):Destroy()
			loopSounds[cue] = nil
		end
	end

	-- the bake's lights and flowing textures of the space this body is in
	local lights: { Light } = {}
	local savedLights: { [Light]: Saved } = {}
	local flows: { Texture } = {}
	local function scan(space: string)
		table.clear(lights)
		table.clear(flows)
		local root = ctx.root or workspace:FindFirstChild("Sewers")
		if root == nil then
			return
		end
		for _, d in root:GetDescendants() do
			local isLight = d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight")
			local isFlow = d:IsA("Texture") and type(d:GetAttribute("Flow")) == "number"
			if (isLight or isFlow) and spaceOfInstance(d, root, names) == space then
				if isLight then
					local l = d :: Light
					table.insert(lights, l)
					if savedLights[l] == nil then
						local shadows = if d:IsA("PointLight") or d:IsA("SpotLight") then (d :: any).Shadows else nil
						savedLights[l] = { enabled = l.Enabled, shadows = shadows }
					end
					l.Enabled = true
				else
					table.insert(flows, d :: Texture)
				end
			end
		end
	end
	local function shadowNearest(at: Vector3)
		local ranked: { { light: Light, d: number } } = {}
		-- (only PointLights cast the lamps' shadows; the beams keep what the bake gave them)
		for _, l in lights do
			if l:IsA("PointLight") then
				local p = lightPosition(l)
				if p then
					table.insert(ranked, { light = l :: Light, d = (p - at).Magnitude })
				end
			end
		end
		table.sort(ranked, function(a, b)
			return a.d < b.d
		end)
		for i, r in ranked do
			(r.light :: any).Shadows = i <= C.shadowLamps
		end
	end
	local function restoreLights()
		for l, s in savedLights do
			l.Enabled = s.enabled
			if s.shadows ~= nil then
				(l :: any).Shadows = s.shadows
			end
		end
		table.clear(savedLights)
		table.clear(lights)
		table.clear(flows)
	end

	-- state
	local current: string? = nil -- the space the inside look and sound are for (nil outside)
	local lastInside: string? = nil
	local sinceInside = math.huge
	local level = 0
	local promptText: string? = nil
	local savedReverb: any = nil
	local lastBody: Model? = nil
	local lastPos: Vector3? = nil
	local echoRun, rungRun = 0, 0
	local dripIn = rng.range(C.drip[1], C.drip[2])
	local stillFor, hissed = 0, false
	local lampClock, scanClock, clock = 0, 0, 0

	local function nearestPoint(cue: string, space: string, at: Vector3): Vector3
		local best, bestD = at, math.huge
		for _, p in points do
			if p.cue == cue and p.space == space then
				local d = (p.x - at.X) ^ 2 + (p.y - at.Y) ^ 2 + (p.z - at.Z) ^ 2
				if d < bestD then
					best, bestD = Vector3.new(p.x, p.y, p.z), d
				end
			end
		end
		return best
	end

	local function enter(space: string, at: Vector3)
		current = space
		savedReverb = SoundService.AmbientReverb
		SoundService.AmbientReverb = Enum.ReverbType.SewerPipe
		scan(space)
		shadowNearest(at)
		play("sewer.grateIn", at)
		local water = if layout then SewerAmbience.loopFor(layout, space) else nil
		if water then
			loop(water, true)
		end
		echoRun, rungRun, stillFor, hissed = 0, 0, 0, false
		lampClock, scanClock = 0, 0
	end

	local function leave(at: Vector3?)
		if current == nil then
			return
		end
		current = nil
		SoundService.AmbientReverb = savedReverb
		savedReverb = nil
		restoreLights()
		for cue in table.clone(looping) do
			loop(cue, false)
		end
		play("sewer.grateOut", at)
	end

	local function setLabel(l: TextLabel, text: string?)
		local want = text or ""
		if l.Text ~= want then
			l.Text = want
		end
		local show = want ~= ""
		if l.Visible ~= show then
			l.Visible = show
		end
	end

	local function step(dt: number)
		clock += dt
		local body = ctx.current()
		if body ~= lastBody then
			-- a new body (or none): whatever the last one was in ends now
			leave(lastPos)
			lastBody, lastPos, lastInside, sinceInside = body, nil, nil, math.huge
		end
		local root = if body then body.PrimaryPart else nil
		local here: string? = nil
		local view: View? = nil
		local feetPos: Vector3? = nil
		if layout and body and root then
			local p = root.Position
			local hip = body:GetAttribute("HipHeight")
			local feet = p.Y - (if type(hip) == "number" then hip else 0)
			feetPos = Vector3.new(p.X, feet, p.Z)
			local st: { [string]: any } = if ctx.state then ctx.state() else {}
			local species = st.species or body:GetAttribute("Species")
			local variant = body:GetAttribute("Variant")
			local can = SewerAmbience.canGoDown(
				if type(species) == "string" then species else nil,
				if type(variant) == "string" then variant else nil
			)
			here = if can then layout.contains(p.X, feet, p.Z) else nil
			local look = root.CFrame.LookVector
			local vy = if lastPos and dt > 0 then (feet - lastPos.Y) / dt else 0
			view = { x = p.X, y = feet, z = p.Z, fx = look.X, fz = look.Z, vy = vy, canGo = can, space = here }
		end
		if here then
			lastInside, sinceInside = here, 0
		else
			sinceInside += dt
		end
		local want = if here then here elseif sinceInside < C.linger then lastInside else nil
		if want ~= current then
			leave(feetPos or lastPos)
			if want and feetPos then
				enter(want, feetPos)
			end
		end

		-- the look eases toward inside or out
		local target = if current then 1 else 0
		if level ~= target then
			level += (target - level) * (1 - math.exp(-dt * C.ease))
			if math.abs(target - level) < 0.01 then
				level = target
			end
			local g, f = effects()
			local gr = SewerAmbience.grade(level)
			g.Brightness, g.Contrast, g.Saturation = gr.brightness, gr.contrast, gr.saturation
			g.TintColor = Color3.fromRGB(math.round(gr.tint[1]), math.round(gr.tint[2]), math.round(gr.tint[3]))
			local fo = SewerAmbience.focus(level)
			f.FarIntensity, f.FocusDistance, f.InFocusRadius = fo.far, fo.distance, fo.radius
			g.Enabled = level > 0
			f.Enabled = level > 0
		end

		if current and feetPos and layout then
			local space = current :: string
			-- lights: rescan for what streamed in, re-rank the shadows; the water flows
			scanClock += dt
			if scanClock >= C.rescanEvery then
				scanClock = 0
				scan(space)
			end
			lampClock += dt
			if lampClock >= C.lampEvery then
				lampClock = 0
				shadowNearest(feetPos)
			end
			for _, tex in flows do
				local speed = tex:GetAttribute("Flow") :: number
				local tile = if tex.StudsPerTileU > 0 then tex.StudsPerTileU else 1
				tex.OffsetStudsU = (tex.OffsetStudsU + speed * dt) % tile
			end
			-- footfalls, rungs, drips, the street, the alligator
			local moved, climbed = 0, 0
			if lastPos then
				moved = math.sqrt((feetPos.X - lastPos.X) ^ 2 + (feetPos.Z - lastPos.Z) ^ 2)
				climbed = math.abs(feetPos.Y - lastPos.Y)
			end
			local shaft = SewerAmbience.shaftAt(layout, feetPos.X, feetPos.Y, feetPos.Z)
			if shaft then
				rungRun += climbed
				if rungRun >= C.rungStep then
					rungRun %= C.rungStep
					play("sewer.rung", feetPos)
				end
			elseif here then
				echoRun += moved
				if echoRun >= C.echoStride then
					echoRun %= C.echoStride
					play("sewer.footEcho", feetPos)
				end
			end
			dripIn -= dt
			if dripIn <= 0 then
				dripIn = rng.range(C.drip[1], C.drip[2])
				play("sewer.drip", nearestPoint("sewer.drip", space, feetPos))
			end
			local _, toMouth = layout.nearestMouth(feetPos.X, feetPos.Z, C.murmurRadius)
			loop("sewer.streetMurmur", toMouth <= C.murmurRadius)
			local speed = if dt > 0 then (moved + climbed) / dt else 0
			if speed < C.still then
				stillFor += dt
			else
				stillFor, hissed = 0, false
			end
			if stillFor >= C.hissAfter and not hissed then
				hissed = true
				play("sewer.hiss", nearestPoint(SewerAmbience.loopFor(layout, space) or "sewer.drip", space, feetPos))
				if ctx.toast then
					ctx.toast(SewerAmbience.HISS_LINE, 4)
				end
			end
		end
		lastPos = feetPos

		promptText = if layout and view then SewerAmbience.prompt(layout, view) else nil
		setLabel(promptLabel, promptText)
		local pipe = if current then pipeBySpace[current :: string] else nil
		setLabel(placeLabel, if pipe then SewerAmbience.placeName(pipe) else nil)
	end

	local conn = RunService.RenderStepped:Connect(step)
	return {
		step = step,
		space = function(): string?
			return current
		end,
		prompt = function(): string?
			return promptText
		end,
		place = function(): string?
			return if current and pipeBySpace[current] then SewerAmbience.placeName(pipeBySpace[current]) else nil
		end,
		level = function(): number
			return level
		end,
		filter = function(text: string): string
			return SewerAmbience.reword(text, current ~= nil)
		end,
		counts = function(): { [string]: number }
			return counts
		end,
		loops = function(): { [string]: boolean? }
			return looping
		end,
		log = function(): { { cue: string, x: number, y: number, z: number } }
			return log
		end,
		stop = function()
			conn:Disconnect()
			leave(lastPos)
			if gradeFx then
				gradeFx:Destroy()
			end
			if focusFx then
				focusFx:Destroy()
			end
			gradeFx, focusFx = nil, nil
			gui:Destroy()
		end,
	}
end

return SewerAmbience
