--!strict
-- ServerScriptService.Server.Rides.SkyLiftService
-- The sky lift's server half (brief v2 line 250 "A sky lift up a slight hill to a hilltop restaurant"; §15 "no
-- controls, no score, you get on and it happens"; §14 "Boarding the sky-lift gondola ... switches to first person
-- automatically; the toggle remains"). The cabins are never sent over the network: every client draws them from
-- the shared clock (Shared/Rides/SkyLift, the one source of truth). This service only holds the people in them.
--   * Publishes the lift's epoch once (ReplicatedStorage attribute SkyLift.EPOCH_ATTRIBUTE; an existing one is
--     kept, the DayClock pattern) and carves the boot terrain out of every TerrainCarve folder under the F4 bake.
--   * A gate prompt at each station (E; attribute Door = true so E belongs to the prompt and not to a car):
--     "Ride the sky lift to the Lookout" at the base, "Ride the sky lift down to town" at the summit. Whoever
--     presses it is booked a seat in the next cabin with room (four to a cabin) and told "Next cabin in N s"; the
--     board over the gate counts down and the gate's arm lifts while a cabin's doors are open. Walking more than
--     WANDER studs from the gate gives the place up, with words. Refusals always say why: animals, drivers,
--     players in a game, a patient (Town.canRide); a full cabin is not a refusal (you get the next one).
--   * Boarding happens at SkyLift.nextDeparture's boardAt (the cabin is beside the platform, doors open): the
--     body's root is anchored, the Humanoid is seated on one of 24 server Seats (cabin c, seat k; invisible, no
--     collision) and both are moved every step to SkyLift.seat; the body carries attribute Ride = "c/k" (the
--     client re-places every body with a Ride attribute onto its own drawing of the cabin before each frame); the
--     player gets DeviceGranted { device = "ride", kind = "gondola", ... } (first person on boarding; V still
--     toggles: Client/Camera/CameraPolicy) and the player attribute OnRide = "sky_lift".
--   * At arriveAt the body stands on its seat's own spot of the far platform (SkyLift.alightSpot: four spots,
--     apart from each other and clear of the walls) facing away from the cabin, its root unanchored and handed
--     back to its player, DeviceReleased("ride_end"), and the notice "Welcome to the Lookout" or "Back in town".
--   * A rider whose player leaves (or takes another body) mid-ride: the body is held (Town.hold: its brain stays
--     suspended and the service keeps placing it on its seat) until the far platform, where it is handed to its
--     brain standing on the platform. Never dropped in mid-air, never woken in a cabin.
--   * The Lookout (f3_hilltop): a free telescope (E: the client takes the camera toward the town, a narrow field of
--     view; payload kind "telescope") and the counter (E: the hilltop lunch, served to a table as a small prop
--     that clears itself after LUNCH_SECS; one per player). Until the wallet lands it is free, with the line
--     "On the house today". THE ONE CHARGE GOES HERE when it does: Town.charge (see `counter`), LUNCH_CENTS = 10
--     under the name "hilltop_lunch" (an EconomyRules.PRICES entry of the same name).
-- Sounds: named cue points only (Sound instances with empty ids, never synthesised): CUES.
-- Engine only inside the functions; no side effects on require. Steppable: step() reads the clock it was given.
-- The joiner's one line in Boot/Game.start (after the attractions, so `canRide` can see the games):
--   local skylift = SkyLiftService.start({ game = { possession = possession, runtime = rt, devices = devices,
--     fire = fire, attractions = function() return attractions end }, heartbeat = o.heartbeat ~= false,
--     terrain = o.terrain ~= false })
--   and then: skylift.step() in Game's step when heartbeat == false, skylift.stop() in stop(), and
--   `skylift:busy(player)` wherever riding must refuse something (vehicles, minigames, picking a new body).
-- Interface: start(opts) -> Service (+ stop); new(opts) -> Service; gameTown(parts) -> Town;
--   publishEpoch(rs, now) -> epoch; carve(root) -> count;
--   Service:press(player, station) -> (ok, why?); Service:telescope(player) -> (ok, why?);
--   Service:counter(player) -> (ok, why?); Service:lookOff(player); focusPoint() -> Vector3;
--   Service:step(); Service:gone(player); Service:busy(player) ->
--   "waiting" | "riding" | nil; Service:time() -> lift seconds; Service:counts() -> { waiting, riding, held,
--   booked, seated, lunches }; Service:stop(); constants WANDER, PROMPT_DISTANCE, BOARD_GRACE, MISSED,
--   ROOT_ABOVE_SEAT, STEP_BACK, LUNCH_CENTS, LUNCH_SECS, TELESCOPE_FOV, WORDS, CUES, FOLDER

local Import = require("../Import")
local AlleyLayout = Import.shared("Attractions/AlleyLayout") :: typeof(require("../../shared/Attractions/AlleyLayout"))
local Data = Import.shared("Data") :: typeof(require("../../shared/Data"))
local PlayerVehicles =
	Import.shared("Vehicles/PlayerVehicles") :: typeof(require("../../shared/Vehicles/PlayerVehicles"))
local PossessionState =
	Import.shared("Actors/PossessionState") :: typeof(require("../../shared/Actors/PossessionState"))
local SkyLift = Import.shared("Rides/SkyLift") :: typeof(require("../../shared/Rides/SkyLift"))

local SkyLiftService = {}
SkyLiftService.__index = SkyLiftService

SkyLiftService.FOLDER = "SkyLiftService" -- the service's own parts (gate posts, seats, lunches) under opts.parent
SkyLiftService.WANDER = 14 -- studs from the gate before a waiting player's place is given up
SkyLiftService.PROMPT_DISTANCE = 8
SkyLiftService.BOARD_GRACE = 0.3 -- a booking stands until this long before the cabin's doors close (boardGrace)
SkyLiftService.OPEN_LEAD = 1.5 -- the platform screen's leaves open this long before a cabin's board time
SkyLiftService.CLOSE_LEAD = 0.8 -- ... and start to close this long before its doors do
SkyLiftService.LEAF_RATE = 1.25 -- of the leaves' travel a second
SkyLiftService.BOARDING_SHOW = 4 -- the board says NOW BOARDING from this long before the board time
SkyLiftService.OPENING = 4 -- the platform screen's opening (tools/bake/skylift Station.OPENING, Summit.OPENING)
SkyLiftService.MISSED = 3 -- a booking this far behind the clock (a server hitch) is moved to the next cabin
-- a seated R15's root over the seat's top: the one number the client draws riders with too
-- (Client/Rides/SkyLiftView.SIT_ROOT = Client/Animation/AnimationDriver.SIT_SEAT; a spec keeps them equal)
SkyLiftService.ROOT_ABOVE_SEAT = 1.35
SkyLiftService.STEP_BACK = 3 -- (no bake) the gate post stands this far back from the board point
SkyLiftService.LUNCH_CENTS = 10 -- the hilltop lunch, once a wallet exists (EconomyRules.PRICES.hilltop_lunch)
SkyLiftService.LUNCH_SECS = 240 -- a served lunch clears itself after this long
SkyLiftService.TELESCOPE_FOV = 15 -- degrees
-- the Lookout's life (review: "the lift and the Lookout are always deserted"): townspeople on outings, a host
SkyLiftService.SIGHT = 300 -- studs: a body only appears or vanishes where no player is this near
SkyLiftService.OUTING_MAX = 4 -- townspeople away on outings at once (riding, or seated at the Lookout)
SkyLiftService.OUTING_GAP = 45 -- seconds between new outings
SkyLiftService.OUTING_GROUP = 2 -- at most this many go up together
SkyLiftService.DINE_MIN = 150 -- seconds at a Lookout table
SkyLiftService.DINE_MAX = 300
SkyLiftService.HOST_AFTER = 20 -- seconds after the start before the host is fetched to the counter
SkyLiftService.ORPHAN_LAPS = 3 -- a left-behind body rides at most this many more legs before it is let off
SkyLiftService.TELESCOPE_REACH = 1300 -- studs out along the telescope's line: where the streaming focus goes
SkyLiftService.TELESCOPE_MAX = 180 -- seconds: a look longer than this is ended by the server
SkyLiftService.LOOK_REMOTE = "SkyLiftLook" -- ReplicatedStorage RemoteEvent: the client says "off" on stepping back
SkyLiftService.ARM_OPEN = math.rad(80) -- the gate arm lifts this far while a cabin's doors are open
SkyLiftService.ARM_RATE = 1.5 -- of the swing a second
SkyLiftService.TABLE_TOP = 2.8 -- the Lookout's tables (tools/bake/lookout table4: top 2.6..2.8)
SkyLiftService.PLATE_SPOTS = table.freeze({
	table.freeze({ -1.3, 0 }),
	table.freeze({ 1.3, 0 }),
	table.freeze({ 0, -1.3 }),
	table.freeze({ 0, 1.3 }),
})

SkyLiftService.WORDS = table.freeze({
	upAction = "Ride the sky lift to the Lookout",
	downAction = "Ride the sky lift down to town",
	gateObject = "SKY LIFT (free)",
	fullCabin = "That cabin is full: yours is the next one, in %d s",
	telescopeAction = "Look through the telescope",
	telescopeObject = "Free telescope",
	counterAction = "Order the hilltop lunch",
	counterFree = "Counter: on the house today",
	counterPaid = "Counter: lunch 10 cents",
	noBody = "Pick a person from the menu first (M)",
	animal = "Only people ride the sky lift. Animals take the trail up the hill",
	waiting = "You are already waiting: next cabin in %d s (walk away to give up your place)",
	riding = "You are on the sky lift: you get off at the other end",
	booked = "Next cabin in %d s. Wait by the gate",
	full = "That cabin is full: you are on the next one, in %d s. Wait by the gate",
	now = "Your cabin is here: step in",
	walkedAway = "You walked away from the sky lift gate: your place is given up",
	missed = "You missed that cabin: next one in %d s",
	upArrive = "Welcome to the Lookout",
	downArrive = "Back in town",
	telescopeAnimal = "The telescope is for people",
	telescopeText = "The town through the telescope. Move the mouse to look around; E or Q to step back",
	counterAnimal = "The counter only serves people",
	lunchFree = "On the house today: your lunch is on %s",
	lunchPaid = "Lunch, 10 cents: it is on %s",
	lunchAlready = "Your lunch is already on %s",
	lunchNoRoom = "Every table is taken: try again in a minute",
	lunchNoMoney = "Lunch is 10 cents: not enough money",
	notNear = "Walk up to the gate first",
	gaveUp = "Your place on the sky lift is given up: %s",
})

-- named cue points (empty ids: the owner uploads; docs/AUDIO_BUDGET.md). The server plays only these three; the
-- cabin's own cues (CableHum, DoorsOpen, DoorsClose, TowerClunk, WindAtHeight) are the client's (lane 5).
SkyLiftService.CUES = table.freeze({
	bell = "SkyLift.StationBell", -- on each gate post, when a cabin's doors open there
	counter = "SkyLift.CounterBell", -- on the counter post, when a lunch is served
	telescope = "SkyLift.TelescopeClick", -- on the telescope post, when someone looks through it
})

-- What the service asks of the rest of the game. gameTown builds it from Boot/Game's objects; specs pass stubs.
export type Hold = {
	-- put the held body's pivot here (x, y, z; Roblox yaw: CFrame.Angles(0, yaw, 0))
	place: (x: number, y: number, z: number, yaw: number) -> (),
	-- stand it on the floor at (x, y, z) facing yaw and give it back to its brain
	free: (x: number, y: number, z: number, yaw: number) -> (),
}
export type Town = {
	canRide: (player: any) -> (boolean, string?),
	speciesOf: (player: any) -> string?,
	bodyOf: (player: any) -> any?, -- the Model the player holds
	notify: (player: any, text: string) -> (),
	refuse: (player: any, text: string) -> (),
	send: (player: any, payload: { [string]: any }) -> (), -- any other event (the telescope)
	grant: (player: any, payload: { [string]: any }) -> (), -- PossessionNet.DeviceGranted
	release: (player: any, why: string) -> (), -- PossessionNet.DeviceReleased
	hold: (body: any) -> Hold?, -- the player let go of this body mid-ride: keep its brain asleep
	-- an AI townsperson out of every player's sight (`sight` studs), free to go on an outing; nil: none now
	recruit: ((sight: number) -> any?)?,
	-- where a body taken out of the town goes back to (a sidewalk at the town's end of Lift Road): x, y, z
	home: ((body: any) -> (number, number, number))?,
	standOffset: ((body: any) -> number)?, -- pivot height over the floor when standing (default 3)
	charge: ((player: any, cents: number, why: string) -> (boolean, string?))?, -- nil: lunch is on the house
	-- the telescope's streaming (lane 8): point the player's ReplicationFocus at `pos` (nil: back to the body), and
	-- stream the ground round `pos` back in, then call `done` (it may yield: the engine's is spawned)
	focus: ((player: any, pos: Vector3?) -> ())?,
	streamAround: ((player: any, pos: Vector3, done: () -> ()) -> ())?,
	players: (() -> { any })?, -- everyone in the game (stepping into an open cabin seats them); nil: nobody
	giveBack: ((player: any, body: any) -> ())?, -- hand the root's network ownership back (engine default)
}
-- Boot/Game's own objects, from which gameTown builds a Town
export type GameParts = {
	possession: any,
	runtime: any, -- Actors/ActorsRuntime (world, byTownId)
	devices: any?, -- Actors/DeviceService (fleet)
	fire: (player: any, payload: { [string]: any }) -> (), -- the PlayNet Event (kinds notice, refused, ...)
	attractions: (() -> any?)?, -- Attractions/AttractionService (minigames: stationOf)
	net: Instance?, -- ReplicatedStorage.PossessionNet (default: found there)
}
export type Opts = {
	town: Town?,
	game: GameParts?, -- used when town is not given
	rs: Instance?, -- where the epoch attribute goes (default ReplicatedStorage)
	now: (() -> number)?, -- server time (default workspace:GetServerTimeNow)
	root: Instance?, -- the bake (default Workspace.Expansion.F4): gates, arms, next-cabin boards, carves
	parent: Instance?, -- where the service's own folder goes (default workspace)
	rand: (() -> number)?, -- [0, 1) (outings' table time); default math.random
	prompts: boolean?, -- default true
	heartbeat: boolean?, -- start(): step on Heartbeat (default true)
	terrain: boolean?, -- start(): carve (default true)
	players: boolean?, -- start(): PlayerRemoving (default true)
}

type Place = { x: number, z: number, floorY: number, yaw: number } -- AlleyLayout.Place
type Booking = { [number]: any } -- seat -> who
type Waiter = {
	player: any,
	station: string,
	other: string,
	cabin: number,
	seat: number,
	boardAt: number,
	arriveAt: number,
	key: string,
}
type Ride = {
	player: any?, -- nil once the player has let go of the body
	body: any,
	station: string,
	other: string,
	cabin: number,
	seat: number,
	boardAt: number,
	arriveAt: number,
	key: string,
	seatPart: any,
	root: any?,
	wasAnchored: boolean,
	hold: Hold?,
	orphaned: boolean, -- its player let go of it (hold may still be nil when the game could not hold it)
	outing: boolean?, -- a townsperson on an outing to the Lookout (no player ever held it)
	laps: number?, -- legs a left-behind body has ridden on, waiting to be let off out of sight
}
type Diner = { body: any, hold: Hold, chair: number, untilT: number }
type Gate = {
	station: string,
	post: any,
	at: Vector3,
	prompt: any?,
	bell: any?,
	arm: any?,
	armHome: CFrame?,
	armSide: number, -- +1: hinged at the arm's +X end (the base's gate), -1: at its -X end (the summit's)
	armFrac: number,
	labels: { any },
	text: string?,
	open: boolean,
	leaves: { { part: any, home: CFrame, slide: Vector3 } }, -- the platform screen's leaves at the opening
	leafFrac: number,
	told: { [any]: number }, -- player -> the board time they were last told it was full
}
type Lunch = { player: any, table: string, spot: number, model: any, until_: number }

local function otherOf(station: string): string
	return if station == "base" then "summit" else "base"
end

local function isInstance(v: any): boolean
	return typeof(v) == "Instance"
end

-- Where a lunch can go: the Lookout's table anchors (dining room first, then the terrace).
local TABLES = { "table_1", "table_2", "table_3", "table_4", "terrace_1", "terrace_2", "terrace_3", "terrace_4" }
local function tableWords(id: string): string
	local k = string.match(id, "(%d)$") or "?"
	if string.sub(id, 1, 7) == "terrace" then
		return `terrace table {k}`
	end
	return `table {k} by the window`
end

local function venueOf(id: string): any
	local exp = Data.default():module("Expansion") :: any
	for _, v in exp.venues do
		if v.id == id then
			return v
		end
	end
	error("SkyLiftService: no venue " .. id)
end

SkyLiftService._venue = venueOf -- (specs)

local function placeOf(v: any): Place
	return { x = v.position.x, z = v.position.z, floorY = v.floorY, yaw = v.yaw }
end

local function anchorAt(v: any, id: string): { number }?
	for _, a in v.anchors do
		if a.id == id then
			return a.at
		end
	end
	return nil
end

-- Publish the lift's epoch once (keep an existing one: a second server script, or a restart of the service).
function SkyLiftService.publishEpoch(rs: Instance, now: number): number
	local had = rs:GetAttribute(SkyLift.EPOCH_ATTRIBUTE)
	if type(had) == "number" then
		return had
	end
	rs:SetAttribute(SkyLift.EPOCH_ATTRIBUTE, now)
	return now
end

-- Fill every TerrainCarve box under the bake with air (the Lookout's floor sits 0.6 over the crown; voxels stand
-- up to a stud over the analytic ground). Returns how many boxes.
function SkyLiftService.carve(root: Instance): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d.Name == "TerrainCarve" then
			for _, p in d:GetChildren() do
				if p:IsA("BasePart") then
					local part = p :: BasePart
					workspace.Terrain:FillBlock(part.CFrame, part.Size, Enum.Material.Air)
					n += 1
				end
			end
		end
	end
	return n
end

local function newPart(className: string, name: string, size: Vector3, cf: CFrame, parent: any): any
	local p = Instance.new(className :: any) :: any
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Parent = parent
	return p
end

local function cue(parent: any, name: string): any
	local s = Instance.new("Sound") :: any
	s.Name = name
	s.SoundId = "" -- a cue point: the owner uploads (docs/AUDIO_BUDGET.md)
	s.Parent = parent
	return s
end

local function play(sound: any)
	if sound then
		pcall(function()
			if sound.SoundId ~= "" then
				sound:Play()
			end
		end)
	end
end

function SkyLiftService.new(opts: Opts): any
	local self = setmetatable({}, SkyLiftService) :: any
	self.town = assert(opts.town, "SkyLiftService.new: opts.town") :: Town
	self.now = opts.now or function(): number
		return workspace:GetServerTimeNow()
	end
	local rs = opts.rs or game:GetService("ReplicatedStorage")
	self.epoch = SkyLiftService.publishEpoch(rs, self.now())
	self.waiters = {} :: { [any]: Waiter }
	self.rides = {} :: { Ride }
	self.riderOf = {} :: { [any]: Ride } -- player -> their ride
	self.bookings = {} :: { [string]: Booking }
	self.lunches = {} :: { Lunch }
	self.looking = {} :: { [any]: { root: any?, wasAnchored: boolean, since: number } }
	self.diners = {} :: { Diner }
	self.outingCount = 0 -- bodies away on outings (riding or dining)
	self.lastOuting = -math.huge
	self.started = self.now()
	self.host = nil :: { body: any, hold: Hold }?
	self.rand = opts.rand or math.random
	self.conns = {} :: { any }
	self.stopped = false
	self.boardClock = -math.huge

	local parent = opts.parent or workspace
	local old = parent:FindFirstChild(SkyLiftService.FOLDER)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder") :: any
	folder.Name = SkyLiftService.FOLDER
	folder.Parent = parent
	self.folder = folder

	-- the 24 seats: invisible, never collide or answer raycasts; moved only while someone is in them
	local seatFolder = Instance.new("Folder") :: any
	seatFolder.Name = "Seats"
	seatFolder.Parent = folder
	self.seats = {} :: { { any } }
	for c = 1, SkyLift.CABINS do
		self.seats[c] = {}
		for k = 1, SkyLift.SEATS do
			local x, y, z, yaw = SkyLift.seat(c, k, 0)
			local s = newPart(
				"Seat",
				`Cabin{c}Seat{k}`,
				Vector3.new(1.6, 0.2, 1.6),
				CFrame.new(x, y - 0.1, z) * CFrame.Angles(0, yaw, 0),
				seatFolder
			)
			s.Transparency = 1
			pcall(function()
				s.Disabled = true -- nobody sits by touching it: the service seats riders
			end)
			self.seats[c][k] = s
		end
	end
	local lunchFolder = Instance.new("Folder") :: any
	lunchFolder.Name = "Lunches"
	lunchFolder.Parent = folder
	self.lunchFolder = lunchFolder

	-- the bake's gates (BoardGate pillars with Gate = "board", Station = base | summit), when it is there
	local root = opts.root
	if root == nil then
		local exp = workspace:FindFirstChild("Expansion")
		root = exp and exp:FindFirstChild("F4")
	end
	local baked: { [string]: any } = {}
	if root then
		for _, d in (root :: Instance):GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Gate") == "board" then
				local st = d:GetAttribute("Station")
				if st == "base" or st == "summit" then
					baked[st :: string] = d
				end
			end
		end
	end
	self.root = root

	local stations = SkyLift.stations()
	self.gates = {} :: { [string]: Gate }
	for _, station in SkyLift.STATIONS do
		local st = (stations :: any)[station]
		local pillar = baked[station]
		local at: Vector3
		if pillar then
			at = (pillar :: any).CFrame.Position + Vector3.new(0, 0.6, 0)
		else
			-- no bake: by the board point, STEP_BACK back from the door, at chest height
			at = Vector3.new(
				st.board.x + SkyLiftService.STEP_BACK * math.sin(st.boardYaw),
				st.platformY + 3,
				st.board.z + SkyLiftService.STEP_BACK * math.cos(st.boardYaw)
			)
		end
		local post = newPart("Part", `GatePost_{station}`, Vector3.new(0.4, 0.4, 0.4), CFrame.new(at), folder)
		post.Transparency = 1
		post:SetAttribute("SkyLift", "gate")
		post:SetAttribute("Station", station)
		local gate: Gate = {
			station = station,
			post = post,
			at = at,
			prompt = nil,
			bell = cue(post, SkyLiftService.CUES.bell),
			arm = nil,
			armHome = nil,
			armSide = 1,
			armFrac = 0,
			labels = {},
			text = nil,
			open = false,
			leaves = {},
			leafFrac = 0,
			told = {},
		}
		if pillar then
			local holder = (pillar :: any).Parent
			local arm = holder and holder:FindFirstChild("BoardGateArm")
			if arm and arm:IsA("BasePart") then
				gate.arm = arm
				gate.armHome = (arm :: any).CFrame
				-- the bake's HingeX is in the venue's frame: which end of the arm is it?
				local hingeX = arm:GetAttribute("HingeX")
				if type(hingeX) == "number" then
					local p = (arm :: any).CFrame.Position
					local lx = AlleyLayout.toLocal(placeOf(venueOf(st.venue)), p.X, p.Y, p.Z)
					gate.armSide = if hingeX >= lx then 1 else -1
				end
			end
			local board = holder and holder:FindFirstChild("NextCabinBoard")
			if board then
				for _, d in board:GetDescendants() do
					if d.Name == "Next" and d:IsA("TextLabel") then
						table.insert(gate.labels, d)
					end
				end
			end
		end
		self.gates[station] = gate
	end
	-- the platform screens' leaves (ScreenDoor = station, Slide = their open offset in world studs)
	if root then
		for _, d in (root :: Instance):GetDescendants() do
			local st = if d:IsA("BasePart") then d:GetAttribute("ScreenDoor") else nil
			local slide = d:GetAttribute("Slide")
			if (st == "base" or st == "summit") and typeof(slide) == "Vector3" then
				table.insert(
					self.gates[st :: string].leaves,
					{ part = d, home = (d :: any).CFrame, slide = slide :: Vector3 }
				)
			end
		end
	end

	-- the Lookout: telescope and counter posts, from the venue's anchors
	local top = venueOf(stations.summit.venue)
	local place = placeOf(top)
	self.lookout = place
	self.lookoutVenue = top
	local tel = anchorAt(top, "telescope") or { 15, 0, -44 }
	local tx, ty, tz = AlleyLayout.toWorld(place, tel[1], 4.4, tel[3])
	self.telescopePost = newPart("Part", "TelescopePost", Vector3.new(0.4, 0.4, 0.4), CFrame.new(tx, ty, tz), folder)
	self.telescopePost.Transparency = 1
	self.telescopeCue = cue(self.telescopePost, SkyLiftService.CUES.telescope)
	-- the eye at the eyepiece (the head's back, toward the building), looking out along the venue's front (-D)
	-- and 6 degrees down, as the bake tips the head
	local ex, ey, ez = AlleyLayout.toWorld(place, tel[1], 4.86, tel[3] + 1.2)
	local lx, ly, lz = AlleyLayout.toWorld(place, tel[1], 4.86 - 100 * math.tan(math.rad(6)), tel[3] - 100)
	self.telescopeView = { eye = { ex, ey, ez }, look = { lx, ly, lz } }
	local ca = anchorAt(top, "counter") or { 35, 0, 12 }
	local cx, cy, cz = AlleyLayout.toWorld(place, ca[1], 3.9, ca[3] - 1.6)
	self.counterPost = newPart("Part", "CounterPost", Vector3.new(0.4, 0.4, 0.4), CFrame.new(cx, cy, cz), folder)
	self.counterPost.Transparency = 1
	self.counterCue = cue(self.counterPost, SkyLiftService.CUES.counter)
	-- the chairs round every table (tools/bake/lookout table4: 2.7 out on each side, facing the table, the seat's
	-- top 1.5 up) and the host's spot by the counter (anchor host)
	self.chairs = {} :: { { x: number, y: number, z: number, yaw: number } }
	for _, id in TABLES do
		local a = anchorAt(top, id)
		if a then
			for _, f in { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } } do
				local sx, sy, sz = AlleyLayout.toWorld(place, a[1] + f[1] * 2.7, 1.5, a[3] + f[2] * 2.7)
				local mx, _, mz = AlleyLayout.toWorld(place, a[1], 1.5, a[3])
				table.insert(self.chairs, { x = sx, y = sy, z = sz, yaw = math.atan2(-(mx - sx), -(mz - sz)) })
			end
		end
	end
	local ha = anchorAt(top, "host") or { 15, 0, -18 }
	local hx, hy, hz = AlleyLayout.toWorld(place, ha[1], 0, ha[3])
	self.hostSpot = { x = hx, y = hy, z = hz, yaw = place.yaw + math.pi }
	self.tables = {} :: { { id: string, x: number, d: number } }
	for _, id in TABLES do
		local a = anchorAt(top, id)
		if a then
			table.insert(self.tables, { id = id, x = a[1], d = a[3] })
		end
	end

	if opts.prompts ~= false then
		self:_prompts()
	end
	return self
end

local function prompt(post: any, action: string, object: string, kind: string): any
	local att = Instance.new("Attachment") :: any
	att.Name = "PromptPoint"
	att.Parent = post
	local p = Instance.new("ProximityPrompt") :: any
	p.Name = "SkyLiftPrompt"
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.HoldDuration = 0
	p.MaxActivationDistance = SkyLiftService.PROMPT_DISTANCE
	p.RequiresLineOfSight = false
	p:SetAttribute("Door", true) -- E belongs to the prompt, not to the vehicles (Client/Minigames/MinigameClient)
	p:SetAttribute("SkyLift", kind)
	p.Parent = att
	return p
end

function SkyLiftService._prompts(self: any)
	local W = SkyLiftService.WORDS
	local function guard(name: string, fn: (player: any) -> ()): (player: any) -> ()
		return function(player: any)
			local ok, err = pcall(function()
				fn(player)
			end)
			if not ok then
				warn(`[SkyLift] {name} failed: {err}`)
			end
		end
	end
	for station, gate in self.gates :: { [string]: Gate } do
		local p =
			prompt(gate.post, if station == "base" then W.upAction else W.downAction, W.gateObject, `gate_{station}`)
		gate.prompt = p
		table.insert(
			self.conns,
			p.Triggered:Connect(guard("gate", function(player: any)
				self:press(player, station)
			end))
		)
	end
	local tp = prompt(self.telescopePost, W.telescopeAction, W.telescopeObject, "telescope")
	table.insert(
		self.conns,
		tp.Triggered:Connect(guard("telescope", function(player: any)
			self:telescope(player)
		end))
	)
	self.telescopePrompt = tp
	local cp =
		prompt(self.counterPost, W.counterAction, if self.town.charge then W.counterPaid else W.counterFree, "counter")
	table.insert(
		self.conns,
		cp.Triggered:Connect(guard("counter", function(player: any)
			self:counter(player)
		end))
	)
	self.counterPrompt = cp
end

-- The lift's clock (Shared/Rides/SkyLift: t = server time - epoch).
function SkyLiftService.time(self: any): number
	return SkyLift.clock(self.now(), self.epoch)
end

function SkyLiftService.busy(self: any, player: any): string?
	if self.riderOf[player] then
		return "riding"
	elseif self.waiters[player] then
		return "waiting"
	end
	return nil
end

local function pivotOf(body: any): Vector3?
	local ok, cf = pcall(function()
		return body:GetPivot()
	end)
	return if ok and cf then (cf :: CFrame).Position else nil
end

local function distXZ(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- The first departure from `station` at or after `from` with a free seat: cabin, seat, boardAt, arriveAt, key,
-- and whether it is not the first one (the first was full).
function SkyLiftService._book(
	self: any,
	station: string,
	from: number
): (number, number, number, number, string, boolean)
	local tq = from
	local skipped = false
	for _ = 1, 4 * SkyLift.CABINS do
		local cabin, boardAt, arriveAt = SkyLift.nextDeparture(station, tq)
		local key = `{station}:{math.floor(boardAt * 10 + 0.5)}`
		local booking = self.bookings[key]
		for k = 1, SkyLift.SEATS do
			if booking == nil or booking[k] == nil then
				return cabin, k, boardAt, arriveAt, key, skipped
			end
		end
		skipped = true
		tq = boardAt + 0.05
	end
	error("SkyLiftService: no seat in the next 24 cabins")
end

function SkyLiftService._take(self: any, key: string, seat: number, who: any)
	local booking = self.bookings[key]
	if booking == nil then
		booking = {}
		self.bookings[key] = booking
	end
	booking[seat] = who
end

function SkyLiftService._free(self: any, key: string, seat: number)
	local booking = self.bookings[key]
	if booking then
		booking[seat] = nil
		if next(booking) == nil then
			self.bookings[key] = nil
		end
	end
end

-- How long after a cabin's board time a booking for it still stands: until just before its doors close (a friend
-- who presses E while the doors are still open joins the cabin in front of them).
function SkyLiftService.boardGrace(station: string): number
	local st = (SkyLift.stations() :: any)[station]
	return (st.doorsCloseSigma - st.boardSigma) % SkyLift.period() - SkyLiftService.BOARD_GRACE
end

-- The opening at `station`'s board point: the board time of the cabin it serves (the one at or coming to the
-- door), and whether the screen's leaves are open for it now (OPEN_LEAD before that time until CLOSE_LEAD before
-- its doors close).
function SkyLiftService.window(station: string, t: number): (number, boolean, number)
	local after = SkyLiftService.boardGrace(station) + SkyLiftService.BOARD_GRACE - SkyLiftService.CLOSE_LEAD
	local cabin, b = SkyLift.nextDeparture(station, t - after)
	return b, t >= b - SkyLiftService.OPEN_LEAD, cabin
end

-- E at a gate. Books the next cabin with room and says when; never silent.
function SkyLiftService.press(self: any, player: any, station: string): (boolean, string?)
	local ok, text = self:_press(player, station, false)
	return ok, text
end

-- (quiet: a step into the opening; the caller says what happened)
function SkyLiftService._press(self: any, player: any, station: string, quiet: boolean): (boolean, string?, Waiter?)
	local W = SkyLiftService.WORDS
	local town = self.town :: Town
	local function no(text: string): (boolean, string?, Waiter?)
		town.refuse(player, text)
		return false, text, nil
	end
	if station ~= "base" and station ~= "summit" then
		return no("No such station")
	end
	local t = self:time()
	if self.riderOf[player] then
		return no(W.riding)
	end
	local w = self.waiters[player]
	if w then
		local text = string.format(W.waiting, math.max(0, math.ceil(w.boardAt - t)))
		town.notify(player, text)
		return false, text
	end
	local body = town.bodyOf(player)
	if body == nil then
		return no(W.noBody)
	end
	local ok, why = town.canRide(player)
	if not ok then
		return no(why or W.animal)
	end
	local gate = (self.gates :: { [string]: Gate })[station]
	local at = pivotOf(body)
	if at and distXZ(at, gate.at) > SkyLiftService.WANDER then
		return no(W.notNear)
	end
	local cabin, seat, boardAt, arriveAt, key, skipped = self:_book(station, t - SkyLiftService.boardGrace(station))
	local waiter: Waiter = {
		player = player,
		station = station,
		other = otherOf(station),
		cabin = cabin,
		seat = seat,
		boardAt = boardAt,
		arriveAt = arriveAt,
		key = key,
	}
	self:_take(key, seat, player)
	self.waiters[player] = waiter
	pcall(function()
		player:SetAttribute("SkyLiftBoardAt", boardAt + self.epoch) -- server time: a HUD can count it down
	end)
	local secs = math.max(0, math.ceil(boardAt - t))
	local text = if secs <= 0
		then W.now
		elseif skipped then string.format(W.full, secs)
		else string.format(W.booked, secs)
	if not quiet then
		town.notify(player, text)
	end
	return true, text, waiter
end

-- Where a body stands relative to `station`'s opening: in front of it (or stepped through it) and within its width.
function SkyLiftService.inOpening(station: string, pos: Vector3): boolean
	local st = (SkyLift.stations() :: any)[station]
	local dx, dz = pos.X - st.board.x, pos.Z - st.board.z
	local y = st.boardYaw
	local toward = dx * -math.sin(y) + dz * -math.cos(y) -- toward the cabin
	local along = dx * math.cos(y) + dz * -math.sin(y)
	return toward >= -1
		and toward <= SkyLift.PLATFORM_OFFSET + 0.5
		and math.abs(along) <= SkyLiftService.OPENING / 2 + 0.3
		and math.abs(pos.Y - (st.platformY + 3)) <= 4
end

-- Whoever stands in an opening while its leaves are open is seated in that cabin at once if it has room (booked
-- through the same path as E), and is told plainly when it is full.
function SkyLiftService._stepIns(self: any, t: number)
	local town = self.town :: Town
	local list = town.players
	if list == nil then
		return
	end
	local okList, players = pcall(list)
	if not okList or type(players) ~= "table" then
		return
	end
	local W = SkyLiftService.WORDS
	for station, gate in self.gates :: { [string]: Gate } do
		local b, open = SkyLiftService.window(station, t)
		if not open then
			table.clear(gate.told)
			continue
		end
		for _, player in players do
			if self.riderOf[player] then
				continue
			end
			local body = town.bodyOf(player)
			local at = if body then pivotOf(body) else nil
			if at == nil or not SkyLiftService.inOpening(station, at) then
				continue
			end
			local w = self.waiters[player]
			if w == nil then
				local ok, _, nw = self:_press(player, station, true)
				w = if ok then nw else nil
				if not ok then
					gate.told[player] = b -- (refused with its words: once per cabin)
				end
			end
			if w and w.station == station then
				if math.abs(w.boardAt - b) < 0.05 then
					self:_board(w, t)
				elseif gate.told[player] ~= b then
					gate.told[player] = b
					town.notify(player, string.format(W.fullCabin, math.max(0, math.ceil(w.boardAt - t))))
				end
			end
		end
	end
end

function SkyLiftService._unwait(self: any, w: Waiter, text: string?)
	self.waiters[w.player] = nil
	self:_free(w.key, w.seat)
	pcall(function()
		w.player:SetAttribute("SkyLiftBoardAt", nil)
	end)
	if text then
		self.town.refuse(w.player, text)
	end
end

local function seatCFrames(cabin: number, seat: number, t: number): (CFrame, CFrame, number, number, number, number)
	local x, y, z, yaw = SkyLift.seat(cabin, seat, t)
	local turn = CFrame.Angles(0, yaw, 0)
	return CFrame.new(x, y - 0.1, z) * turn,
		CFrame.new(x, y + SkyLiftService.ROOT_ABOVE_SEAT, z) * turn,
		x,
		y + SkyLiftService.ROOT_ABOVE_SEAT,
		z,
		yaw
end

local function humanoidOf(body: any): any
	local ok, h = pcall(function()
		return body:FindFirstChildOfClass("Humanoid")
	end)
	return if ok then h else nil
end

function SkyLiftService._board(self: any, w: Waiter, t: number)
	local town = self.town :: Town
	local player = w.player
	local body = town.bodyOf(player)
	if body == nil then
		self:_unwait(w, SkyLiftService.WORDS.noBody)
		return
	end
	self.waiters[player] = nil
	pcall(function()
		player:SetAttribute("SkyLiftBoardAt", nil)
	end)
	local seatPart = self.seats[w.cabin][w.seat]
	local seatCf, rootCf = seatCFrames(w.cabin, w.seat, t)
	local root = body.PrimaryPart
	local ride: Ride = {
		player = player,
		body = body,
		station = w.station,
		other = w.other,
		cabin = w.cabin,
		seat = w.seat,
		boardAt = w.boardAt,
		arriveAt = w.arriveAt,
		key = w.key,
		seatPart = seatPart,
		root = root,
		wasAnchored = if root then root.Anchored == true else false,
		hold = nil,
		orphaned = false,
	}
	self:_take(w.key, w.seat, ride)
	seatPart.CFrame = seatCf
	if root then
		root.Anchored = true
	end
	body:PivotTo(rootCf)
	local hum = humanoidOf(body)
	if hum then
		pcall(function()
			seatPart.Disabled = false
			seatPart:Sit(hum)
		end)
	end
	body:SetAttribute("Ride", `{w.cabin}/{w.seat}`)
	pcall(function()
		player:SetAttribute("OnRide", SkyLift.RIDE_ID)
	end)
	table.insert(self.rides, ride)
	self.riderOf[player] = ride
	town.grant(player, {
		device = "ride",
		kind = "gondola", -- Client/Camera/CameraPolicy: first person on boarding, V toggles
		ride = SkyLift.RIDE_ID,
		firstPerson = true,
		cabin = w.cabin,
		seat = w.seat,
		from = w.station,
		to = w.other,
		boardAt = w.boardAt, -- lift clock (ReplicatedStorage SkyLiftEpoch)
		arriveAt = w.arriveAt,
	})
end

local function unseat(ride: Ride)
	local hum = humanoidOf(ride.body)
	pcall(function()
		if hum then
			hum.Sit = false
		end
		local weld = ride.seatPart:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		ride.seatPart.Disabled = true
	end)
end

-- The player let go of a riding body (left the game, took another body): keep it on its seat, brain asleep.
function SkyLiftService._orphan(self: any, ride: Ride)
	local player = ride.player
	ride.player = nil
	ride.orphaned = true
	if player ~= nil then
		if self.riderOf[player] == ride then
			self.riderOf[player] = nil
		end
		pcall(function()
			player:SetAttribute("OnRide", nil)
		end)
		if (not isInstance(player)) or (player :: any).Parent ~= nil then
			-- still in the game with another body: their screen leaves the ride (no words: they chose it)
			pcall(self.town.release, player, "ride_left")
		end
	end
	local ok, h = pcall(self.town.hold, ride.body)
	ride.hold = if ok then h else nil
	if not ok then
		warn(`[SkyLift] hold failed: {h}`)
	end
end

function SkyLiftService._move(self: any, ride: Ride, t: number)
	-- (gone() cleared the player: hold now, after Possession has let the body go; or they took another body)
	if not ride.orphaned and (ride.player == nil or self.town.bodyOf(ride.player) ~= ride.body) then
		self:_orphan(ride)
	end
	local seatCf, rootCf, x, y, z, yaw = seatCFrames(ride.cabin, ride.seat, t)
	ride.seatPart.CFrame = seatCf
	if ride.hold then
		ride.hold.place(x, y, z, yaw)
	else
		ride.body:PivotTo(rootCf)
	end
end

function SkyLiftService._alight(self: any, ride: Ride)
	local town = self.town :: Town
	-- this seat's own spot on the far platform, facing away from the cabin (four riders never share one)
	local x, y, z, yaw = SkyLift.alightSpot(ride.other, ride.seat)
	if not ride.orphaned and (ride.player == nil or town.bodyOf(ride.player) ~= ride.body) then
		self:_orphan(ride)
	end
	if ride.hold and ride.orphaned and not ride.outing and self:_rideOn(ride) then
		-- (left behind with a player watching the platform: it rides on, still seated, and returns)
		return
	end
	unseat(ride)
	pcall(function()
		ride.body:SetAttribute("Ride", nil)
	end)
	if ride.hold and ride.outing and ride.other == "summit" and self:_dine(ride) then
		-- (an outing at the top: seated at a Lookout table; _dine took it off the ride)
		pcall(function()
			ride.body:SetAttribute("Ride", "dine")
		end)
	elseif ride.hold then
		local free = ride.hold.free
		local fx, fy, fz, fyaw = x, y, z, yaw
		local home = self.town.home
		if home and not self:_seen(Vector3.new(x, y, z)) then
			-- out of everyone's sight: back to the town's end of Lift Road, not a long walk from the hill
			local okH, hx, hy, hz = pcall(home, ride.body)
			if okH and type(hx) == "number" and not self:_seen(Vector3.new(hx, hy, hz)) then
				fx, fy, fz = hx, hy, hz
			end
		end
		local ok, err = pcall(function()
			free(fx, fy, fz, fyaw)
		end)
		if not ok then
			warn(`[SkyLift] free failed: {err}`)
		end
		if ride.outing then
			self.outingCount = math.max(0, self.outingCount - 1)
		end
	else
		local offset = 3
		if town.standOffset then
			local ok, o = pcall(town.standOffset, ride.body)
			if ok and type(o) == "number" then
				offset = o
			end
		end
		ride.body:PivotTo(CFrame.new(x, y + offset, z) * CFrame.Angles(0, yaw, 0))
		if ride.root then
			ride.root.Anchored = ride.wasAnchored
		end
		local player = ride.player
		if player ~= nil then
			if town.giveBack then
				pcall(town.giveBack, player, ride.body)
			end
			self.riderOf[player] = nil
			pcall(function()
				player:SetAttribute("OnRide", nil)
			end)
			town.release(player, "ride_end")
			local W = SkyLiftService.WORDS
			town.notify(player, if ride.other == "summit" then W.upArrive else W.downArrive)
		end
	end
	self:_free(ride.key, ride.seat)
	local i = table.find(self.rides, ride)
	if i then
		table.remove(self.rides, i)
	end
end

-- The player left the game: a waiting place is given up; a ride carries on with the body held (next step).
function SkyLiftService.gone(self: any, player: any)
	self:lookOff(player)
	local w = self.waiters[player]
	if w then
		self:_unwait(w, nil)
	end
	local ride = self.riderOf[player]
	if ride then
		self.riderOf[player] = nil
		ride.player = nil
	end
	for i = #self.lunches, 1, -1 do
		local l = self.lunches[i]
		if l.player == player then
			pcall(function()
				l.model:Destroy()
			end)
			table.remove(self.lunches, i)
		end
	end
end

-- What the board over a gate says at t: NOW BOARDING from BOARDING_SHOW before a cabin's board time until its
-- doors close; otherwise the seconds to the next one, or that it is full (every seat booked).
function SkyLiftService.boardText(self: any, station: string, t: number): string
	local b = SkyLiftService.window(station, t)
	if t >= b - SkyLiftService.BOARDING_SHOW then
		return "NOW BOARDING"
	end
	local _, boardAt = SkyLift.nextDeparture(station, t)
	local key = `{station}:{math.floor(boardAt * 10 + 0.5)}`
	local booking = self.bookings[key]
	local taken = 0
	for _ in booking or {} do
		taken += 1
	end
	if taken >= SkyLift.SEATS then
		return "NEXT CABIN FULL"
	end
	return `NEXT CABIN {math.max(0, math.ceil(boardAt - t))} s`
end

-- The gates' furniture: the next-cabin board (whole seconds), the screen's leaves and the arm (open while a cabin
-- stands at the opening) and the bell when a cabin's doors open there.
function SkyLiftService._furniture(self: any, t: number, dt: number)
	local openAt: { [string]: boolean } = {}
	for i = 1, SkyLift.CABINS do
		local _, _, _, _, phase, open = SkyLift.cabin(i, t)
		if open then
			openAt[phase] = true
		end
	end
	for station, gate in self.gates :: { [string]: Gate } do
		local open = openAt[station] == true
		if open and not gate.open then
			play(gate.bell)
		end
		gate.open = open
		local b, windowOpen = SkyLiftService.window(station, t)
		if #gate.labels > 0 then
			local text = SkyLiftService.boardText(self, station, t)
			if text ~= gate.text then
				gate.text = text
				for _, l in gate.labels do
					l.Text = text
				end
			end
		end
		-- the screen's leaves at the opening and the gate's arm: open for the cabin at the door, shut otherwise
		local leafTarget = if windowOpen then 1 else 0
		local lf = gate.leafFrac
		local nlf = lf + math.clamp(leafTarget - lf, -dt * SkyLiftService.LEAF_RATE, dt * SkyLiftService.LEAF_RATE)
		if nlf ~= lf then
			gate.leafFrac = nlf
			local e = nlf * nlf * (3 - 2 * nlf)
			for _, leaf in gate.leaves do
				leaf.part.CFrame = leaf.home + leaf.slide * e
			end
		end
		local _ = b
		local arm, home = gate.arm, gate.armHome
		if arm and home then
			local target = if windowOpen then 1 else 0
			local f = gate.armFrac
			local nf = f + math.clamp(target - f, -dt * SkyLiftService.ARM_RATE, dt * SkyLiftService.ARM_RATE)
			if nf ~= f then
				gate.armFrac = nf
				local e = nf * nf * (3 - 2 * nf)
				-- turned about the hinge end (the pillar side: the bake's HingeX), the free end swinging up
				local side = gate.armSide
				local hinge = CFrame.new(side * (arm :: any).Size.X / 2, 0, 0)
				local turn = CFrame.Angles(0, 0, -side * e * SkyLiftService.ARM_OPEN)
				arm.CFrame = home * hinge * turn * hinge:Inverse()
			end
		end
	end
end

-- One step: waiting players (gave up? boarding?), riders (on their seats; arrived?), the gates, the lunches.
function SkyLiftService.step(self: any, dt: number?)
	if self.stopped then
		return
	end
	local town = self.town :: Town
	local W = SkyLiftService.WORDS
	local t = self:time()
	local list: { Waiter } = {}
	for _, w in self.waiters :: { [any]: Waiter } do
		table.insert(list, w)
	end
	for _, w in list do
		local body = town.bodyOf(w.player)
		local ok: boolean, why: string? = true, nil
		if body == nil then
			ok, why = false, W.noBody
		else
			ok, why = town.canRide(w.player)
		end
		local at = if body then pivotOf(body) else nil
		if not ok then
			self:_unwait(w, string.format(W.gaveUp, why or "you cannot ride now"))
		elseif at and distXZ(at, self.gates[w.station].at) > SkyLiftService.WANDER then
			self:_unwait(w, W.walkedAway)
		elseif t - w.boardAt > SkyLiftService.MISSED then
			-- (a hitch: the cabin left without them) the next one with room
			self:_free(w.key, w.seat)
			local cabin, seat, boardAt, arriveAt, key = self:_book(w.station, t)
			w.cabin, w.seat, w.boardAt, w.arriveAt, w.key = cabin, seat, boardAt, arriveAt, key
			self:_take(key, seat, w.player)
			town.notify(w.player, string.format(W.missed, math.max(0, math.ceil(boardAt - t))))
		elseif t >= w.boardAt then
			self:_board(w, t)
		end
	end
	local nowS = self.now()
	for player, look in table.clone(self.looking) do
		local l = look :: { root: any?, wasAnchored: boolean, since: number }
		local body = town.bodyOf(player)
		if nowS - l.since > SkyLiftService.TELESCOPE_MAX or body == nil or (l.root and body.PrimaryPart ~= l.root) then
			self:lookOff(player)
		end
	end
	local okIn, errIn = pcall(self._stepIns, self, t)
	if not okIn then
		warn(`[SkyLift] step-ins failed: {errIn}`)
	end
	local okLife, errLife = pcall(self._life, self, t)
	if not okLife then
		warn(`[SkyLift] the Lookout's life failed: {errLife}`)
	end
	for i = #self.rides, 1, -1 do
		local ride = self.rides[i]
		local ok, err = pcall(function()
			if t >= ride.arriveAt then
				self:_alight(ride)
			else
				self:_move(ride, t)
			end
		end)
		if not ok then
			warn(`[SkyLift] rider step failed: {err}`)
		end
	end
	self:_furniture(t, dt or 1 / 60)
	local now = self.now()
	for i = #self.lunches, 1, -1 do
		local l = self.lunches[i]
		if now >= l.until_ then
			pcall(function()
				l.model:Destroy()
			end)
			table.remove(self.lunches, i)
		end
	end
end

-- Is any player's body within `radius` (default SIGHT) of pos?
function SkyLiftService._seen(self: any, pos: Vector3, radius: number?): boolean
	local town = self.town :: Town
	local list = town.players
	if list == nil then
		return false
	end
	local ok, players = pcall(list)
	if not ok or type(players) ~= "table" then
		return false
	end
	local r = radius or SkyLiftService.SIGHT
	for _, p in players do
		local body = town.bodyOf(p)
		local at = if body then pivotOf(body) else nil
		if at and (at - pos).Magnitude < r then
			return true
		end
	end
	return false
end

-- A held body on the seat of a cabin at `station`'s door, booked through _book and _take like a player.
function SkyLiftService._seatHeld(self: any, body: any, hold: Hold, station: string, t: number, outing: boolean): Ride?
	local cabin, seat, boardAt, arriveAt, key = self:_book(station, t - SkyLiftService.boardGrace(station))
	local b = SkyLiftService.window(station, t)
	if math.abs(boardAt - b) > 0.05 then
		return nil -- the cabin at the door is full
	end
	local ride: Ride = {
		player = nil,
		body = body,
		station = station,
		other = otherOf(station),
		cabin = cabin,
		seat = seat,
		boardAt = boardAt,
		arriveAt = arriveAt,
		key = key,
		seatPart = self.seats[cabin][seat],
		root = body.PrimaryPart,
		wasAnchored = false,
		hold = hold,
		orphaned = true,
		outing = outing,
		laps = 0,
	}
	self:_take(key, seat, ride)
	pcall(function()
		body:SetAttribute("Ride", `{cabin}/{seat}`)
	end)
	table.insert(self.rides, ride)
	self:_move(ride, t)
	return ride
end

-- An outing arrives at the top: seated at a free Lookout chair (nobody standing on it) for a few minutes.
function SkyLiftService._dine(self: any, ride: Ride): boolean
	local taken: { [number]: boolean } = {}
	for _, d in self.diners :: { Diner } do
		taken[d.chair] = true
	end
	local n = #self.chairs
	if n == 0 or ride.hold == nil then
		return false
	end
	local start = math.floor(self.rand() * n)
	for k = 0, n - 1 do
		local i = (start + k) % n + 1
		local c = self.chairs[i]
		if not taken[i] and not self:_seen(Vector3.new(c.x, c.y, c.z), 2) then
			local hold = ride.hold :: Hold
			hold.place(c.x, c.y + SkyLiftService.ROOT_ABOVE_SEAT, c.z, c.yaw)
			local secs = SkyLiftService.DINE_MIN + (SkyLiftService.DINE_MAX - SkyLiftService.DINE_MIN) * self.rand()
			table.insert(self.diners, { body = ride.body, hold = hold, chair = i, untilT = self.now() + secs })
			return true
		end
	end
	return false
end

-- A left-behind body arriving where a player can see the platform: it stays in its seat for the way back (the
-- same cabin comes round to the board point), at most ORPHAN_LAPS legs; false when it must get off here.
function SkyLiftService._rideOn(self: any, ride: Ride): boolean
	local st = (SkyLift.stations() :: any)[ride.other]
	if not self:_seen(Vector3.new(st.alight.x, st.platformY, st.alight.z)) then
		return false
	end
	if (ride.laps or 0) >= SkyLiftService.ORPHAN_LAPS then
		return false
	end
	local cabin, boardAt, arriveAt = SkyLift.nextDeparture(ride.other, ride.arriveAt)
	if cabin ~= ride.cabin then
		return false
	end
	local key = `{ride.other}:{math.floor(boardAt * 10 + 0.5)}`
	local booking = self.bookings[key]
	if booking and booking[ride.seat] ~= nil then
		return false
	end
	self:_free(ride.key, ride.seat)
	ride.station, ride.other = ride.other, ride.station
	ride.boardAt, ride.arriveAt, ride.key = boardAt, arriveAt, key
	ride.laps = (ride.laps or 0) + 1
	self:_take(key, ride.seat, ride)
	return true
end

-- The Lookout's life, once a step: the host at the counter, townspeople going up for a meal and coming down.
function SkyLiftService._life(self: any, t: number)
	local town = self.town :: Town
	local recruit = town.recruit
	if recruit == nil then
		return
	end
	local now = self.now()
	-- the host, fetched once, out of sight, to stand by the counter
	local hs = self.hostSpot
	if self.host == nil and now - self.started >= SkyLiftService.HOST_AFTER then
		if not self:_seen(Vector3.new(hs.x, hs.y, hs.z)) then
			local body = recruit(SkyLiftService.SIGHT)
			local hold = if body then town.hold(body) else nil
			if body and hold then
				local offset = if town.standOffset then town.standOffset(body) else 3
				hold.place(hs.x, hs.y + offset, hs.z, hs.yaw)
				self.host = { body = body, hold = hold }
			end
		end
	end
	-- diners whose meal is over take the next cabin down, when nobody is by their table or the boarding gate
	local downB, downOpen = SkyLiftService.window("summit", t)
	local st = SkyLift.stations().summit
	local gateSeen = self:_seen(Vector3.new(st.board.x, st.platformY, st.board.z), 60)
	for i = #self.diners, 1, -1 do
		local d = self.diners[i]
		local c = self.chairs[d.chair]
		if now >= d.untilT and downOpen and t <= downB + 1 and not gateSeen then
			if not self:_seen(Vector3.new(c.x, c.y, c.z), 60) then
				local ride = self:_seatHeld(d.body, d.hold, "summit", t, true)
				if ride then
					table.remove(self.diners, i)
				end
			end
		end
	end
	-- a new outing: one or two townspeople into the cabin at the base's door, out of every player's sight
	local upB, upOpen = SkyLiftService.window("base", t)
	if
		upOpen
		and t <= upB + 1
		and self.outingCount < SkyLiftService.OUTING_MAX
		and now - self.lastOuting >= SkyLiftService.OUTING_GAP
	then
		local base = SkyLift.stations().base
		if not self:_seen(Vector3.new(base.board.x, base.platformY, base.board.z)) then
			self.lastOuting = now
			local group = math.min(
				SkyLiftService.OUTING_GROUP,
				SkyLiftService.OUTING_MAX - self.outingCount,
				1 + math.floor(self.rand() * SkyLiftService.OUTING_GROUP)
			)
			for _ = 1, group do
				local body = recruit(SkyLiftService.SIGHT)
				local hold = if body then town.hold(body) else nil
				if body == nil or hold == nil then
					break
				end
				if self:_seatHeld(body, hold, "base", t, true) then
					self.outingCount += 1
				else
					hold.free(base.board.x, base.platformY, base.board.z, base.boardYaw) -- (no room after all)
					break
				end
			end
		end
	end
end

-- Where the telescope's streaming focus goes: TELESCOPE_REACH out along its line, on the town's ground.
function SkyLiftService.focusPoint(self: any): Vector3
	local v = self.telescopeView
	local dx, dz = v.look[1] - v.eye[1], v.look[3] - v.eye[3]
	local l = math.sqrt(dx * dx + dz * dz)
	local r = SkyLiftService.TELESCOPE_REACH
	return Vector3.new(v.eye[1] + dx / l * r, 20, v.eye[3] + dz / l * r)
end

-- The telescope's look begins: the body is anchored where it stands (the ground under it may stream out) and the
-- player's streaming follows the town the telescope looks at, so the real houses, trees, cars and people load.
function SkyLiftService._lookOn(self: any, player: any)
	local town = self.town :: Town
	if self.looking[player] or town.focus == nil then
		return
	end
	local body = town.bodyOf(player)
	local root = body and body.PrimaryPart
	local was = if root then root.Anchored == true else false
	if root then
		root.Anchored = true
	end
	self.looking[player] = { root = root, wasAnchored = was, since = self.now() }
	pcall(town.focus :: any, player, self:focusPoint())
end

-- The look ends (the client stepped back, the time ran out, the player left or took another body): the focus goes
-- back to the body, the Lookout streams back in round it, and only then is the body let go.
function SkyLiftService.lookOff(self: any, player: any)
	local town = self.town :: Town
	local l = self.looking[player]
	if l == nil then
		return
	end
	self.looking[player] = nil
	if town.focus then
		pcall(town.focus :: any, player, nil)
	end
	local function release()
		if l.root then
			pcall(function()
				l.root.Anchored = l.wasAnchored
			end)
		end
	end
	local post = self.telescopePost
	local at = if post then (post :: any).Position else nil
	if town.streamAround and at then
		local ok = pcall(town.streamAround :: any, player, at, release)
		if not ok then
			release()
		end
	else
		release()
	end
end

-- E at the telescope: the client takes the camera toward the town (Client/Rides/Telescope, lane 5).
function SkyLiftService.telescope(self: any, player: any): (boolean, string?)
	local W = SkyLiftService.WORDS
	local town = self.town :: Town
	if town.bodyOf(player) == nil then
		town.refuse(player, W.noBody)
		return false, W.noBody
	end
	if town.speciesOf(player) ~= "human" then
		town.refuse(player, W.telescopeAnimal)
		return false, W.telescopeAnimal
	end
	local v = self.telescopeView
	play(self.telescopeCue)
	self:_lookOn(player)
	town.send(player, {
		kind = "telescope",
		eye = v.eye,
		look = v.look,
		fov = SkyLiftService.TELESCOPE_FOV,
		text = W.telescopeText,
	})
	return true, nil
end

local function lunchModel(parent: any, x: number, y: number, z: number, yaw: number): any
	local m = Instance.new("Model") :: any
	m.Name = "Lunch"
	local turn = CFrame.Angles(0, yaw, 0)
	local flat = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder's axis is X: stand it up
	local function part(name: string, size: Vector3, cf: CFrame, rgb: { number }, cyl: boolean, material: string)
		local p = newPart("Part", name, size, cf, m)
		p.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
		pcall(function()
			p.Material = (Enum.Material :: any)[material]
			p.CastShadow = false
			if cyl then
				p.Shape = Enum.PartType.Cylinder
			end
		end)
		return p
	end
	local base = CFrame.new(x, y, z) * turn
	part(
		"Plate",
		Vector3.new(0.08, 1.1, 1.1),
		base * CFrame.new(0, 0.04, 0) * flat,
		{ 238, 236, 228 },
		true,
		"SmoothPlastic"
	)
	part(
		"Sandwich",
		Vector3.new(0.7, 0.28, 0.45),
		base * CFrame.new(-0.05, 0.22, 0),
		{ 214, 168, 104 },
		false,
		"SmoothPlastic"
	)
	part(
		"Cup",
		Vector3.new(0.4, 0.32, 0.32),
		base * CFrame.new(0.42, 0.2, -0.42) * flat,
		{ 250, 250, 246 },
		true,
		"SmoothPlastic"
	)
	m.Parent = parent
	return m
end

-- E at the counter: the hilltop lunch, served to a table (a small prop that clears itself). Free with a line until a
-- wallet exists; when one does, Town.charge takes LUNCH_CENTS here under "hilltop_lunch".
function SkyLiftService.counter(self: any, player: any): (boolean, string?)
	local W = SkyLiftService.WORDS
	local town = self.town :: Town
	local function no(text: string): (boolean, string?)
		town.refuse(player, text)
		return false, text
	end
	if town.bodyOf(player) == nil then
		return no(W.noBody)
	end
	if town.speciesOf(player) ~= "human" then
		return no(W.counterAnimal)
	end
	for _, l in self.lunches :: { Lunch } do
		if l.player == player then
			local text = string.format(W.lunchAlready, tableWords(l.table))
			town.notify(player, text)
			return false, text
		end
	end
	-- the table with the fewest lunches on it (dining room first), and a free place at it
	local best: { id: string, x: number, d: number }? = nil
	local bestN, bestSpot = math.huge, 0
	for _, tb in self.tables do
		local used: { [number]: boolean } = {}
		local n = 0
		for _, l in self.lunches :: { Lunch } do
			if l.table == tb.id then
				used[l.spot] = true
				n += 1
			end
		end
		if n < bestN and n < #SkyLiftService.PLATE_SPOTS then
			for k = 1, #SkyLiftService.PLATE_SPOTS do
				if not used[k] then
					best, bestN, bestSpot = tb, n, k
					break
				end
			end
		end
	end
	if best == nil then
		return no(W.lunchNoRoom)
	end
	local paid = false
	if town.charge then
		local ok, why = town.charge(player, SkyLiftService.LUNCH_CENTS, "hilltop_lunch")
		if not ok then
			return no(why or W.lunchNoMoney)
		end
		paid = true
	end
	local spot = SkyLiftService.PLATE_SPOTS[bestSpot]
	local place = self.lookout :: Place
	local px, py, pz = AlleyLayout.toWorld(place, best.x + spot[1], SkyLiftService.TABLE_TOP, best.d + spot[2])
	-- the plate faces the chair it is in front of (the sandwich toward the sitter)
	local cx, _, cz = AlleyLayout.toWorld(place, best.x, 0, best.d)
	local yaw = math.atan2(-(px - cx), -(pz - cz)) + math.pi
	local model = lunchModel(self.lunchFolder, px, py, pz, yaw)
	model:SetAttribute("Table", best.id)
	table.insert(self.lunches, {
		player = player,
		table = best.id,
		spot = bestSpot,
		model = model,
		until_ = self.now() + SkyLiftService.LUNCH_SECS,
	})
	play(self.counterCue)
	local text = string.format(if paid then W.lunchPaid else W.lunchFree, tableWords(best.id))
	town.notify(player, text)
	return true, text
end

function SkyLiftService.counts(self: any): { [string]: number }
	local waiting, riding, held, booked, seated = 0, 0, 0, 0, 0
	for _ in self.waiters do
		waiting += 1
	end
	for _, r in self.rides :: { Ride } do
		if r.orphaned then
			held += 1
		else
			riding += 1
		end
	end
	for _, b in self.bookings do
		for _ in b do
			booked += 1
		end
	end
	for c = 1, SkyLift.CABINS do
		for k = 1, SkyLift.SEATS do
			local ok, d = pcall(function()
				return self.seats[c][k].Disabled
			end)
			if ok and d == false then
				seated += 1
			end
		end
	end
	return {
		waiting = waiting,
		riding = riding,
		held = held,
		booked = booked,
		seated = seated,
		lunches = #self.lunches,
		outings = self.outingCount,
		diners = #self.diners,
		host = if self.host then 1 else 0,
	}
end

-- Stop: everyone waiting is let go; riders are put straight onto their far platform (nobody is left in the air).
function SkyLiftService.stop(self: any)
	if self.stopped then
		return
	end
	for _, w in table.clone(self.waiters) :: { [any]: Waiter } do
		self:_unwait(w, nil)
	end
	for i = #self.rides, 1, -1 do
		pcall(self._alight, self, self.rides[i])
	end
	for player in table.clone(self.looking) do
		pcall(self.lookOff, self, player)
	end
	-- the diners and the host back to their brains where they are (the summit platform for the diners)
	local st = SkyLift.stations().summit
	for _, d in self.diners :: { Diner } do
		pcall(function()
			d.body:SetAttribute("Ride", nil)
			d.hold.free(st.alight.x, st.platformY, st.alight.z, st.alightYaw + math.pi)
		end)
	end
	table.clear(self.diners)
	if self.host then
		local hs = self.hostSpot
		pcall(self.host.hold.free, hs.x, hs.y, hs.z, hs.yaw)
		self.host = nil
	end
	self.stopped = true
	for _, c in self.conns do
		c:Disconnect()
	end
	table.clear(self.conns)
end

-- A standing body's pivot over its feet (ActorService.groundOffset: the bounding box); 3 when it cannot be measured.
local function standOffset(body: any): number
	local ActorService = require("../Actors/ActorService")
	local ok, o = pcall(ActorService.groundOffset, body)
	return if ok and type(o) == "number" then o else 3
end

-- The Town from Boot/Game's objects (engine only).
function SkyLiftService.gameTown(parts: GameParts): Town
	local possession = parts.possession
	local rt = parts.runtime
	local fire = parts.fire
	local function actorOf(player: any): any?
		return possession:actorOf(player)
	end
	local function netRemote(name: string): RemoteEvent?
		local folder = parts.net or game:GetService("ReplicatedStorage"):FindFirstChild(PossessionState.NET.folder)
		local r = folder and folder:FindFirstChild(name)
		return if r and r:IsA("RemoteEvent") then r else nil
	end
	local function toClient(player: any, remoteName: string, kind: string, value: any)
		if isInstance(player) then
			local r = netRemote(remoteName)
			if r and (player :: Instance).Parent ~= nil then
				r:FireClient(player :: Player, value)
			end
		elseif type(player) == "table" and type(player.events) == "table" then
			table.insert(player.events, { kind = kind, value = value }) -- PlayerLike stub (engine checks)
		end
	end
	return {
		canRide = function(player: any): (boolean, string?)
			local actor = actorOf(player)
			if actor == nil then
				return false, SkyLiftService.WORDS.noBody
			end
			if actor.species ~= "human" then
				return false, SkyLiftService.WORDS.animal
			end
			local devices = parts.devices
			if
				devices
				and type(player.UserId) == "number"
				and PlayerVehicles.vehicleOf(devices.fleet, player.UserId)
			then
				return false, "Get out of the vehicle first (E)"
			end
			local a = parts.attractions and parts.attractions()
			local mg = a and a.minigames
			if mg and mg:stationOf(player) then
				return false, "Leave your game first"
			end
			local body = actor.body :: Model
			if body:GetAttribute("Med") ~= nil then
				return false, "Not while you are unwell: get to the hospital"
			end
			return true, nil
		end,
		speciesOf = function(player: any): string?
			local actor = actorOf(player)
			return if actor then actor.species else nil
		end,
		bodyOf = function(player: any): any?
			local actor = actorOf(player)
			return if actor then actor.body else nil
		end,
		notify = function(player: any, text: string)
			fire(player, { kind = "notice", text = text })
		end,
		refuse = function(player: any, text: string)
			fire(player, { kind = "refused", text = text })
		end,
		send = function(player: any, payload: { [string]: any })
			fire(player, payload)
		end,
		grant = function(player: any, payload: { [string]: any })
			toClient(player, PossessionState.NET.DeviceGranted, "deviceGranted", payload)
		end,
		release = function(player: any, why: string)
			toClient(player, PossessionState.NET.DeviceReleased, "deviceReleased", why)
		end,
		hold = function(body: any): Hold?
			-- the AI actor behind this body: suspended (no brain, no motor) while the service places it
			local TownAI = require("../AI/TownAI")
			local world = rt.world
			local townId: number? = nil
			for id, actor in rt.byTownId do
				if actor.body == body then
					townId = id
					break
				end
			end
			if townId == nil then
				return nil
			end
			local id = townId :: number
			local actor = rt.byTownId[id]
			local a = world.actorsById[id]
			local offset = standOffset(body)
			actor.possessable = false
			TownAI.suspend(world, id)
			return {
				place = function(x: number, y: number, z: number, yaw: number)
					-- ActorsRuntime draws an AI body's pivot at a.y - a.hip + offset, facing robloxYaw(a.yaw)
					a.x, a.z = x, z
					a.y = y + a.hip - offset
					a.yaw = yaw - math.pi
					a.speed = 0
				end,
				free = function(x: number, y: number, z: number, yaw: number)
					actor.possessable = true
					if possession:controllerOf(actor) == "ai" then
						TownAI.resume(world, id, x, y + a.hip, z, yaw - math.pi)
					end
				end,
			}
		end,
		standOffset = standOffset,
		recruit = function(sight: number): any?
			local world = rt.world
			local spots: { Vector3 } = {}
			for _, p in game:GetService("Players"):GetPlayers() do
				local c = p.Character
				local r = c and c.PrimaryPart
				if r then
					table.insert(spots, r.Position)
				end
			end
			local list = world.actors
			local n = #list
			local start = math.random(1, math.max(1, n))
			for k = 0, n - 1 do
				local a = list[(start + k - 1) % n + 1]
				local actor = rt.byTownId[a.id]
				if
					actor
					and a.species == "human"
					and a.post == "townsperson"
					and actor.possessable ~= false
					and possession:controllerOf(actor) == "ai"
					and actor.body:GetAttribute("Med") == nil
					and actor.body:GetAttribute("Ride") == nil
				then
					local far = true
					for _, q in spots do
						if (q.X - a.x) ^ 2 + (q.Z - a.z) ^ 2 < sight * sight then
							far = false
							break
						end
					end
					if far then
						return actor.body
					end
				end
			end
			return nil
		end,
		home = function(_body: any): (number, number, number)
			-- the sidewalk where Lift Road meets the westside street (tools/bake/skylift/Approach)
			local x, z = -697.5, -630
			local Height = Import.shared("World/Height") :: any
			local ok, y = pcall(Height.at, x, z)
			return x, if ok and type(y) == "number" then y else 0, z
		end,
		giveBack = function(player: any, body: any)
			if isInstance(player) and body.PrimaryPart then
				(body.PrimaryPart :: BasePart):SetNetworkOwner(player :: Player)
			end
		end,
		charge = nil, -- the wallet (feat/wallet): Credits' charge(player, cents, why) goes here when it lands
		players = function(): { any }
			return game:GetService("Players"):GetPlayers()
		end,
		focus = function(player: any, pos: Vector3?)
			if not isInstance(player) then
				return
			end
			local folder = workspace:FindFirstChild(SkyLiftService.FOLDER)
			local mark = folder and folder:FindFirstChild(`Focus_{(player :: Player).UserId}`)
			if pos == nil then
				(player :: Player).ReplicationFocus = nil
				if mark then
					mark:Destroy()
				end
				return
			end
			if mark == nil and folder then
				mark =
					newPart("Part", `Focus_{(player :: Player).UserId}`, Vector3.new(1, 1, 1), CFrame.new(pos), folder)
				mark.Transparency = 1
			end
			if mark then
				(mark :: BasePart).CFrame = CFrame.new(pos);
				(player :: Player).ReplicationFocus = mark :: BasePart
			end
		end,
		streamAround = function(player: any, pos: Vector3, done: () -> ())
			task.spawn(function()
				if isInstance(player) and (player :: Instance).Parent ~= nil then
					pcall(function()
						(player :: Player):RequestStreamAroundAsync(pos, 8)
					end)
				end
				done()
			end)
		end,
	}
end

-- Start in the game: the epoch, the carves, the service, its Heartbeat step and PlayerRemoving.
function SkyLiftService.start(opts: Opts): any
	local o: Opts = table.clone(opts)
	if o.town == nil then
		local parts = o.game
		assert(parts ~= nil, "SkyLiftService.start: opts.town or opts.game")
		o.town = SkyLiftService.gameTown(parts)
	end
	if o.root == nil then
		local exp = workspace:FindFirstChild("Expansion")
		o.root = exp and exp:FindFirstChild("F4")
	end
	if o.root == nil then
		warn(
			"[SkyLift] Workspace.Expansion.F4 missing (run lune run tools/bake/skylift.luau and rebuild): the lift runs with plain prompts and no gates"
		)
	end
	local carved = 0
	if o.terrain ~= false and o.root then
		local ok, err = pcall(function()
			carved = SkyLiftService.carve(o.root :: Instance)
		end)
		if not ok then
			warn(`[SkyLift] terrain carve failed: {err}`)
		end
	end
	local svc = SkyLiftService.new(o)
	svc.carved = carved
	if o.players ~= false then
		table.insert(
			svc.conns,
			game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
				svc:gone(player)
			end)
		)
	end
	if o.players ~= false then
		-- the client's word that the telescope is down (Client/Main: Telescope's onChange(false))
		local rs = o.rs or game:GetService("ReplicatedStorage")
		local ev = rs:FindFirstChild(SkyLiftService.LOOK_REMOTE)
		if ev == nil then
			ev = Instance.new("RemoteEvent")
			ev.Name = SkyLiftService.LOOK_REMOTE
			ev.Parent = rs
		end
		table.insert(
			svc.conns,
			(ev :: RemoteEvent).OnServerEvent:Connect(function(player: Player, what: any)
				if what == "off" then
					pcall(svc.lookOff, svc, player)
				end
			end)
		)
	end
	if o.heartbeat ~= false then
		table.insert(
			svc.conns,
			game:GetService("RunService").Heartbeat:Connect(function(dt: number)
				local ok, err = pcall(svc.step, svc, math.min(dt, 0.1))
				if not ok then
					warn(`[SkyLift] step failed: {err}`)
				end
			end)
		)
	end
	print(
		`[SkyLift] running: {SkyLift.CABINS} cabins, a ride {math.floor(SkyLift.rideTime("base") + 0.5)} s, epoch {svc.epoch}, {carved} terrain carves`
	)
	return svc
end

return SkyLiftService
