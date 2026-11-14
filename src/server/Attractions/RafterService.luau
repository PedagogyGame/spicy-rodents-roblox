--!strict
-- ServerScriptService.Server.Attractions.RafterService
-- The people under the bowling alley's rafters notice a squirrel moving over them (BRIEF_ADDENDUM D9: "the
-- squirrel must practice sneaking through those rafters or will be spotted"; lane L5 of the roof plan). Stepped
-- from the game's step (Boot/Game), it works at TICK (5 Hz):
--   * the squirrels: every squirrel-family body, read from where its body is (Stealth/RafterSense: the rafter or
--     the vent it is on, its speed, a landing); one on no rafter, not in the vent and not in the air of the roof
--     space is not watched;
--   * the people: every person whose root is in the lane hall (AlleyRoof.inHall) looking the way their root faces,
--     eye EYE_OVER_ROOT over it, and the computer bowlers (no bodies: an eye 5.2 up on their lane's approach, facing
--     the pins), so a bowling game against the computer has eyes in it;
--   * line of sight: a ray from the eye to the squirrel's body (RafterWatch.aimPoint) that meets nothing but the
--     beam under the squirrel (a hit within C.beamSlack of the aim point); bodies and parts that take no queries
--     are passed through;
--   * Stealth/RafterWatch decides. On "spotted":
--       - an ordinary squirrel: up to C.speakers of the people who saw it say a "rafters" line (Speech/SpeechRules'
--         pacing, its own state on the server clock), everyone on foot in the hall and on
--         the guard platform is told which lane it is over ("notice"), and the squirrel glows (a Highlight on the
--         body, and the body attribute RafterSeen = the server time it ends) for C.glow seconds. No damage.
--       - the Spicy Rodent: the same with the "spotting" lines (the owner's own line among them), its own words for
--         the callout, and the alarm (Town.alarm): the people in the hall run (the Pedestrian brains' "witness"
--         flee) and the nearest free police officer is sent to the alley's front door ("respond").
--   * the squirrel's own player sees the meter: player attributes RafterMeter (0..1, to two places) and RafterSeen
--     (true while seen) while its squirrel is watched, nil after (Client/UI/SneakMeter draws the eye and the words).
--   * the guard's kick (Combat/PlayRules) does not reach through the vent unit's walls: the service puts the unit
--     and its duct in force as Combat/Cover boxes (covers(place)) while it runs. At the louvre the squirrel is
--     outside them and a kick lands.
-- The Town is what it needs from the game (start(game) builds it from Boot/Game's parts; specs pass a stub).
-- Interface: TICK, C, WORDS, EYE_OVER_ROOT, BOWLER_EYE, DEFAULT_PLACE; new(opts) -> Service; start(game) -> Service;
--   covers(place) -> { Box }; callout(spicy, lane?) -> string; Service:step(dt); Service:stop();
--   Service:meter(id) -> (number, boolean); Service.stats { ticks, spotted, lines, callouts, alarms }
-- No side effects on require.

local Import = require("../Import")
local AlleyLayout = Import.shared("Attractions/AlleyLayout") :: typeof(require("../../shared/Attractions/AlleyLayout"))
local AlleyRoof = Import.shared("Attractions/AlleyRoof") :: typeof(require("../../shared/Attractions/AlleyRoof"))
local RafterWatch = Import.shared("Stealth/RafterWatch") :: typeof(require("../../shared/Stealth/RafterWatch"))
local RafterSense = Import.shared("Stealth/RafterSense") :: typeof(require("../../shared/Stealth/RafterSense"))
local Cover = Import.shared("Combat/Cover") :: typeof(require("../../shared/Combat/Cover"))
local SpeechRules = Import.shared("Speech/SpeechRules") :: typeof(require("../../shared/Speech/SpeechRules"))

local RafterService = {}
RafterService.__index = RafterService

RafterService.TICK = 0.2
RafterService.C = {
	glow = 6, -- seconds a spotted squirrel glows (owner question Q5)
	speakers = 2, -- people who say a line when it is spotted
	beamSlack = 1.2, -- a sight ray stopped this near the squirrel met the beam it stands on
	respond = 60, -- seconds an officer heads for the door
	hip = 0.75, -- a squirrel's root over its soles when the body does not say (HipHeight)
	near = 60, -- studs: bodies further than this outside the alley's footprint are not looked at
}
local C = RafterService.C
RafterService.EYE_OVER_ROOT = 1.6 -- a person's eye over their root (an R15 root is about 3 over the soles)
RafterService.BOWLER_EYE = { y = 5.2, d = -6 } -- a computer bowler on the approach
RafterService.DEFAULT_PLACE = { x = 1300, z = -420, floorY = 16.5, yaw = 0 } -- data/attractions.json's alley
RafterService.GLOW_NAME = "RafterGlow"

RafterService.WORDS = {
	squirrel = "A squirrel in the rafters over lane %d!",
	squirrelAisle = "A squirrel in the rafters over the aisle!",
	rodent = "The Spicy Rodent is in the rafters over lane %d! The police are on their way.",
	rodentAisle = "The Spicy Rodent is in the rafters over the aisle! The police are on their way.",
}

-- (types do not cross Import: Shared/Attractions/AlleyLayout.Place, Stealth/RafterWatch's Observer, Squirrel and Event and
-- Combat/Cover.Box written out as far as this file uses them)
export type Place = { x: number, z: number, floorY: number, yaw: number }
type Observer = { id: string, X: number, Y: number, D: number, faceX: number, faceD: number }
type Squirrel = any
type Event = { kind: string, squirrel: string, observer: string?, lane: number?, X: number?, D: number? }
type Box = any

-- A body the game has: a squirrel ("squirrel", `spicy` for the Spicy Rodent) or a person ("human").
export type Body = {
	id: string,
	kind: string,
	spicy: boolean?,
	model: any, -- the Model: its PrimaryPart is the root; attributes and the glow go on it
	player: any?, -- who holds it (nil: the AI)
}

export type Town = {
	bodies: () -> { Body },
	bowlers: (() -> { number })?, -- lanes where a computer bowler is in a game
	send: (player: any, payload: { [string]: any }) -> (),
	-- the Spicy Rodent's alarm in the AI town: the people in the hall run, an officer comes to the door
	alarm: ((rodent: Body, people: { Body }, doorX: number, doorZ: number) -> ())?,
}

export type Opts = {
	town: Town,
	place: Place?,
	now: () -> number, -- server time (SayAt, the glow's end)
	canSee: ((eye: Vector3, aim: Vector3) -> boolean)?, -- default: a ray in the workspace
	speech: any?, -- a Speech/SpeechRules.State on the same clock as `now` (default: its own)
	rand: (() -> number)?,
}

export type Stats = { ticks: number, spotted: number, lines: number, callouts: number, alarms: number }

-- What one tick gathered, for what a "spotted" does with it.
type Held = { body: Body, X: number, Y: number, D: number }
type TickView = {
	now: number,
	byId: { [string]: Body },
	observers: { Observer },
	saw: { [string]: { [string]: boolean } }, -- squirrel id -> the people who could see it this tick
	heldHumans: { Held },
}

-- The vent unit and its duct as Combat/Cover boxes: the curb and housing (the louvre's face at X 116, the curb's
-- lip at 116.4; the mouth, X 117, is outside), and the duct from the unit through the wall, down the elbow and
-- out of the boot (it stops short of the boot's end, where the chord 9120 begins).
function RafterService.covers(place: Place): { Box }
	local a = AlleyRoof.AHU
	local d, e, b = AlleyRoof.DUCT, AlleyRoof.ELBOW, AlleyRoof.BOOT
	return {
		{
			name = "roof vent unit",
			place = place,
			x0 = a.curb.x0,
			x1 = a.curb.x1,
			y0 = a.curb.y0,
			y1 = a.housing.y1,
			d0 = a.curb.d0,
			d1 = a.curb.d1,
		},
		{
			name = "roof vent duct",
			place = place,
			x0 = b.x0 + 0.4,
			x1 = d.x1,
			y0 = b.y0 - 0.3,
			y1 = math.max(d.y1, e.y1),
			d0 = math.min(d.d0, b.d0),
			d1 = math.max(d.d1, b.d1),
		},
	}
end

-- The words everyone in the hall reads when a squirrel is spotted over `lane` (nil: over an aisle).
function RafterService.callout(spicy: boolean, lane: number?): string
	local W = RafterService.WORDS
	if lane then
		return string.format(if spicy then W.rodent else W.squirrel, lane)
	end
	return if spicy then W.rodentAisle else W.squirrelAisle
end

local function rootOf(model: any): any?
	local ok, root = pcall(function()
		return model.PrimaryPart
	end)
	return if ok then root else nil
end

local function setAttr(target: any, name: string, value: any)
	pcall(function()
		target:SetAttribute(name, value)
	end)
end

local function defaultCanSee(exclude: { Instance }): (eye: Vector3, aim: Vector3) -> boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	return function(eye: Vector3, aim: Vector3): boolean
		local hit = workspace:Raycast(eye, aim - eye, params)
		return hit == nil or (hit.Position - aim).Magnitude <= C.beamSlack
	end
end

function RafterService.new(opts: Opts): any
	local place = opts.place or RafterService.DEFAULT_PLACE
	local self = setmetatable({
		town = opts.town,
		place = place,
		now = opts.now,
		canSee = opts.canSee or defaultCanSee({}),
		speech = opts.speech or SpeechRules.new(),
		rand = opts.rand or math.random,
		sense = RafterSense.new(),
		watch = RafterWatch.new(),
		acc = 0,
		glows = {} :: { [any]: number }, -- model -> server time its glow ends
		shown = {} :: { [any]: { meter: number?, seen: boolean? } }, -- player -> what their attributes say
		covers = {} :: { number },
		stats = { ticks = 0, spotted = 0, lines = 0, callouts = 0, alarms = 0 } :: Stats,
	}, RafterService)
	for _, box in RafterService.covers(place) do
		table.insert(self.covers, Cover.add(box))
	end
	return self
end

-- A world point in the alley's frame.
local function local3(self: any, p: Vector3): (number, number, number)
	return AlleyLayout.toLocal(self.place, p.X, p.Y, p.Z)
end

-- Within C.near of the alley's footprint (X -42..152, D -82..102; tools/compile/lib/Attractions) and its yard
-- (AlleyRoof.ANNEX, to X 212): anyone further off is not looked at.
local function near(X: number, D: number): boolean
	return X >= -42 - C.near and X <= AlleyRoof.ANNEX.x1 + C.near and D >= -82 - C.near and D <= 102 + C.near
end

function RafterService.step(self: any, dt: number)
	self.acc += dt
	if self.acc < RafterService.TICK then
		return
	end
	local tickDt = self.acc
	self.acc = 0
	self:_tick(tickDt)
end

function RafterService._tick(self: any, dt: number)
	self.stats.ticks += 1
	local now = self.now()
	local squirrels: { Squirrel } = {}
	local observers: { Observer } = {}
	local byId: { [string]: Body } = {}
	local heldHumans: { Held } = {}
	local present: { [string]: boolean } = {}
	for _, body in self.town.bodies() do
		local root = rootOf(body.model)
		if root == nil then
			continue
		end
		local X, Y, D = local3(self, root.Position)
		if not near(X, D) then
			continue
		end
		byId[body.id] = body
		if body.kind == "human" then
			local eyeY = Y + RafterService.EYE_OVER_ROOT
			if AlleyRoof.inHall(X, D) then
				local look = root.CFrame.LookVector
				local fx, _, fz = local3(self, root.Position + look)
				table.insert(observers, { id = body.id, X = X, Y = eyeY, D = D, faceX = fx - X, faceD = fz - D })
			end
			if body.player ~= nil then
				table.insert(heldHumans, { body = body, X = X, Y = Y, D = D })
			end
		else
			present[body.id] = true
			local hip = body.model:GetAttribute("HipHeight")
			local feet = Y - (if type(hip) == "number" and hip > 0 then hip else C.hip)
			local s = RafterSense.sense(self.sense, body.id, X, feet, D, dt)
			if s then
				table.insert(squirrels, s)
			end
		end
	end
	for id in self.sense.tracks do
		if not present[id] then
			RafterSense.forget(self.sense, id)
		end
	end
	if self.town.bowlers then
		for _, lane in self.town.bowlers() do
			local e = RafterService.BOWLER_EYE
			table.insert(
				observers,
				{ id = `bowler:{lane}`, X = AlleyLayout.laneX(lane), Y = e.y, D = e.d, faceX = 0, faceD = 1 }
			)
		end
	end
	-- who saw whom this tick (the speakers are among them)
	local saw: { [string]: { [string]: boolean } } = {}
	local function canSee(o: Observer, s: Squirrel): boolean
		local ex, ey, ez = AlleyLayout.toWorld(self.place, o.X, o.Y, o.D)
		local ax, ay, ad = RafterWatch.aimPoint(s)
		local wx, wy, wz = AlleyLayout.toWorld(self.place, ax, ay, ad)
		local seen = self.canSee(Vector3.new(ex, ey, ez), Vector3.new(wx, wy, wz))
		if seen then
			saw[s.id] = saw[s.id] or {}
			saw[s.id][o.id] = true
		end
		return seen
	end
	local events = RafterWatch.step(self.watch, squirrels, observers, nil, dt, canSee)
	for _, e in events do
		local body = byId[e.squirrel]
		if e.kind == "spotted" and body then
			self:_spotted(
				body,
				e,
				{
					now = now,
					byId = byId,
					observers = observers,
					saw = saw,
					heldHumans = heldHumans,
				} :: TickView
			)
		end
	end
	self:_publish(byId)
	for model, ends in self.glows do
		if now >= ends then
			self:_unglow(model)
		end
	end
end

-- A spotted squirrel: the lines, the callout, the glow, and for the Spicy Rodent the alarm.
function RafterService._spotted(self: any, body: Body, e: Event, tick: TickView)
	self.stats.spotted += 1
	local now, observers, heldHumans = tick.now, tick.observers, tick.heldHumans
	local saw = tick.saw[e.squirrel] or {}
	local spicy = body.spicy == true
	self:_glow(body.model, now + C.glow)
	-- the lines: whoever saw most first, then the nearest others who saw it (AI people with a body only)
	local town = self.town
	local people: { [string]: Body } = {}
	for id, b in tick.byId do
		if b.kind == "human" and b.player == nil then
			people[id] = b
		end
	end
	local candidates: { { id: string, d2: number } } = {}
	for _, o in observers do
		if saw[o.id] and people[o.id] then
			local d2 = (o.X - (e.X or 0)) ^ 2 + (o.D - (e.D or 0)) ^ 2
			table.insert(candidates, { id = o.id, d2 = if o.id == e.observer then -1 else d2 })
		end
	end
	table.sort(candidates, function(a, b)
		return a.d2 < b.d2
	end)
	local situation = if spicy then "spotting" else RafterWatch.SITUATION
	local spoken = 0
	for _, c in candidates do
		if spoken >= C.speakers then
			break
		end
		local line = SpeechRules.request(self.speech, now, c.id, situation, self.rand)
		if line then
			local model = people[c.id].model
			setAttr(model, SpeechRules.ATTR.Say, line)
			setAttr(model, SpeechRules.ATTR.SayAt, now)
			spoken += 1
			self.stats.lines += 1
		end
	end
	-- the callout: everyone on foot in the hall or on the guard platform
	local words = RafterService.callout(spicy, e.lane)
	for _, h in heldHumans do
		local onPlatform = AlleyRoof.inPlatform(h.X, h.D) ~= nil and h.Y >= AlleyRoof.WING_ROOF.y - 1
		if AlleyRoof.inHall(h.X, h.D) or onPlatform then
			town.send(h.body.player, { kind = "notice", text = words })
			self.stats.callouts += 1
		end
	end
	if spicy and town.alarm then
		local hall: { Body } = {}
		for _, o in observers do
			if people[o.id] then
				table.insert(hall, people[o.id])
			end
		end
		local en = AlleyLayout.ENTRANCE
		local dx, _, dz = AlleyLayout.toWorld(self.place, (en.x0 + en.x1) / 2, 0, AlleyLayout.FRONT_D - 6)
		town.alarm(body, hall, dx, dz)
		self.stats.alarms += 1
	end
end

function RafterService._glow(self: any, model: any, ends: number)
	self.glows[model] = ends
	setAttr(model, "RafterSeen", ends)
	local ok = pcall(function()
		if model:FindFirstChild(RafterService.GLOW_NAME) then
			return
		end
		local h = Instance.new("Highlight")
		h.Name = RafterService.GLOW_NAME
		h.FillColor = Color3.fromRGB(255, 170, 40)
		h.OutlineColor = Color3.fromRGB(255, 240, 200)
		h.FillTransparency = 0.45
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Parent = model
	end)
	if not ok then
		warn("[RafterService] the glow could not be put on a body")
	end
end

function RafterService._unglow(self: any, model: any)
	self.glows[model] = nil
	setAttr(model, "RafterSeen", nil)
	pcall(function()
		local h = model:FindFirstChild(RafterService.GLOW_NAME)
		if h then
			h:Destroy()
		end
	end)
end

-- The meter on the screen of each player whose squirrel is watched; cleared when it is not.
function RafterService._publish(self: any, byId: { [string]: Body })
	local want: { [any]: { meter: number?, seen: boolean? } } = {}
	for id in self.watch.tracks do
		local body = byId[id]
		if body and body.player ~= nil then
			local m, seen = RafterWatch.meter(self.watch, id)
			want[body.player] = { meter = math.floor(m * 100 + 0.5) / 100, seen = seen }
		end
	end
	for player in self.shown do
		if want[player] == nil then
			want[player] = { meter = nil, seen = nil }
		end
	end
	for player, w in want do
		local had = self.shown[player] or {}
		if had.meter ~= w.meter then
			setAttr(player, "RafterMeter", w.meter)
		end
		if had.seen ~= w.seen then
			setAttr(player, "RafterSeen", w.seen)
		end
		self.shown[player] = if w.meter == nil then nil else w
	end
end

-- meter(id): the watch's meter and seen for a squirrel's body id.
function RafterService.meter(self: any, id: string): (number, boolean)
	return RafterWatch.meter(self.watch, id)
end

function RafterService.stop(self: any)
	for _, key in self.covers do
		Cover.remove(key)
	end
	table.clear(self.covers)
	for model in table.clone(self.glows) do
		self:_unglow(model)
	end
	for player in self.shown do
		setAttr(player, "RafterMeter", nil)
		setAttr(player, "RafterSeen", nil)
	end
	table.clear(self.shown)
end

-- start(game): the service on Boot/Game's parts. game = { possession, runtime (Actors/ActorsRuntime), fire
-- (player, payload), attractions (Server/Attractions: the alley's place and its MinigameService)?, canSee?, now?
-- (specs only: a fake engine has neither raycasts nor a server clock) }. Boot/Game makes it once the alley is open
-- and steps it from its step:
--   local rafters = RafterService.start({ possession = possession, runtime = rt, fire = fire,
--       attractions = attractions })      -- and in step(dt): rafters:step(dt)
function RafterService.start(game: { [string]: any }): any
	local rt = game.runtime
	local possession = game.possession
	local world = rt.world
	local attractions = game.attractions
	local function bodies(): { Body }
		local out: { Body } = {}
		for _, a in world.actors do
			local actor = rt.byTownId[a.id]
			if actor == nil or actor.body == nil then
				continue
			end
			local kind = if actor.species == "human"
				then "human"
				elseif actor.species == "squirrel" or actor.species == "rodent" then "squirrel"
				else nil
			if kind == nil then
				continue
			end
			local driver = possession:controllerOf(actor)
			table.insert(
				out,
				{
					id = actor.id,
					kind = kind,
					spicy = actor.variant == "spicy",
					model = actor.body,
					player = if driver ~= "ai" then driver else nil,
					townId = a.id,
				} :: any
			)
		end
		return out
	end
	local function bowlers(): { number }
		local out = {}
		local mg = attractions and attractions.minigames
		if mg == nil then
			return out
		end
		for _, st in mg:stations() do
			local s = st.session
			if st.game == "bowling" and st.lane and s and s.phase == "playing" then
				for _, key in s.seats do
					if type(key) == "table" and key.ai == true then
						table.insert(out, st.lane)
						break
					end
				end
			end
		end
		return out
	end
	local function alarm(rodent: Body, people: { Body }, doorX: number, doorZ: number)
		local threat = world.actorsById[(rodent :: any).townId]
		for _, p in people do
			local brain = world.brains[(p :: any).townId]
			if threat and brain and brain.kind == "Pedestrian" then
				brain:onEvent({ type = "witness", threat = threat, alert = 10 })
			end
		end
		-- the nearest free officer on foot comes to the door
		local best, bestD = nil, math.huge
		for _, a in world.actors do
			local brain = world.brains[a.id]
			local actor = rt.byTownId[a.id]
			if brain and brain.kind == "Officer" and actor and possession:controllerOf(actor) == "ai" then
				local d = (a.x - doorX) ^ 2 + (a.z - doorZ) ^ 2
				if d < bestD then
					best, bestD = brain, d
				end
			end
		end
		if best then
			best:onEvent({ type = "respond", x = doorX, z = doorZ, untilTime = world.now + C.respond })
		end
	end
	local canSee = game.canSee -- (specs on a fake engine, which has no raycasts)
	if canSee == nil then
		local exclude: { Instance } = {}
		if typeof(rt.bodies) == "Instance" then
			table.insert(exclude, rt.bodies)
		end
		canSee = defaultCanSee(exclude)
	end
	return RafterService.new({
		town = {
			bodies = bodies,
			bowlers = bowlers,
			send = game.fire,
			alarm = alarm,
		},
		place = attractions and attractions.place or nil,
		now = game.now or function(): number
			return workspace:GetServerTimeNow()
		end,
		canSee = canSee,
	})
end

return RafterService
