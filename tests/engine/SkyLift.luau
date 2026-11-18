--!strict
-- ServerStorage.EngineTests.SkyLift (CI place only; injected with --inject ci.project.json or a saved version)
-- The sky lift's rider flow on a server with no clients, as plain results (brief v2 line 250; §15 "you get on
-- and it happens"; §14 first person on boarding). Server/Rides/SkyLiftService is started on its own with a stub
-- Town (PlayerLike stubs, bodies built here) and a clock this check moves, so the timetable is exact and nothing
-- waits on the wall clock. Checked against Shared/Rides/SkyLift's timetable:
--   up       a person presses the base gate, is told when, boards when the cabin's doors are open (the device
--            grant says ride / gondola / first person; the body is anchored on its seat with Ride = "c/k") and
--            is on the summit platform, back in their own hands, with "Welcome to the Lookout", within 2 s of
--            boardAt + rideTime
--   down     the same from the summit: "Back in town"
--   refusals a squirrel and a driver are refused with words; nobody is booked
--   full     five people at once: four in one cabin, the fifth told it is full and put in the next
--   walk     someone who walks away from the gate loses the place, with words
--   orphan   a rider whose player leaves mid-ride stays on the seat (held) and is handed to its brain on the far
--            platform, standing
--   soak     200 random boardings and leaves: afterwards no booking, rider, waiter or seat is left
-- play() takes the service module and a body maker, so the Lune suite runs this same flow on the fake engine
-- (tests/isolated/skylift_service.luau): the check is itself checked before a cloud run is spent on it.
-- Interface: run() -> Result (engine only); play(Service, makeBody, SkyLift) -> Result { ok, failures, numbers };
--   stubTown(world) -> Town; newWorld(Service, makeBody, SkyLift, opts?) -> World

local SkyLiftFlow = {}

export type World = {
	clock: number,
	svc: any,
	Service: any,
	SkyLift: any,
	makeBody: (name: string, cf: CFrame) -> any,
	holds: { [any]: { places: number, freed: { number }? } },
	players: { any },
	rs: any,
	parent: any,
}

-- A PlayerLike stub: what the service sends it lands in `events` ({ kind, text?, value?, at }).
function SkyLiftFlow.player(w: World, name: string, species: string, cf: CFrame): any
	local p = {
		Name = name,
		UserId = 7000 + #w.players + 1,
		species = species,
		driving = false,
		gone = false,
		events = {},
		attrs = {},
		body = w.makeBody(name, cf),
	}
	function p.SetAttribute(self: any, k: string, v: any)
		self.attrs[k] = v
	end
	function p.GetAttribute(self: any, k: string): any
		return self.attrs[k]
	end
	table.insert(w.players, p)
	return p
end

function SkyLiftFlow.stubTown(w: World): any
	local W = w.Service.WORDS
	local function log(p: any, e: { [string]: any })
		e.at = w.clock
		table.insert(p.events, e)
	end
	return {
		canRide = function(p: any): (boolean, string?)
			if p.species ~= "human" then
				return false, W.animal
			end
			if p.driving then
				return false, "Get out of the vehicle first (E)"
			end
			return true, nil
		end,
		speciesOf = function(p: any): string?
			return p.species
		end,
		bodyOf = function(p: any): any?
			return if p.gone then nil else p.body
		end,
		notify = function(p: any, text: string)
			log(p, { kind = "notice", text = text })
		end,
		refuse = function(p: any, text: string)
			log(p, { kind = "refused", text = text })
		end,
		send = function(p: any, payload: { [string]: any })
			log(p, table.clone(payload))
		end,
		grant = function(p: any, payload: { [string]: any })
			log(p, { kind = "deviceGranted", value = payload })
		end,
		release = function(p: any, why: string)
			log(p, { kind = "deviceReleased", value = why })
		end,
		hold = function(body: any): any
			local rec = { places = 0, freed = nil :: { number }? }
			w.holds[body] = rec
			return {
				place = function(x: number, y: number, z: number, yaw: number)
					rec.places += 1
					body:PivotTo(CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0))
				end,
				free = function(x: number, y: number, z: number, yaw: number)
					rec.freed = { x, y, z, yaw, w.clock }
					body:PivotTo(CFrame.new(x, y + 3, z) * CFrame.Angles(0, yaw, 0))
				end,
			}
		end,
		standOffset = function(_body: any): number
			return 3
		end,
		players = function(): { any }
			local out = {}
			for _, p in w.players do
				if not p.gone then
					table.insert(out, p)
				end
			end
			return out
		end,
	}
end

export type NewOpts = { start: number?, rs: any?, parent: any?, root: any?, prompts: boolean?, town: any? }

-- A world: the service on a stub Town, an epoch of 1000 and a clock that starts at `start` (lift seconds).
function SkyLiftFlow.newWorld(
	Service: any,
	makeBody: (name: string, cf: CFrame) -> any,
	SkyLift: any,
	opts: NewOpts?
): World
	local o: NewOpts = opts or {}
	local w: World = {
		clock = 1000 + (o.start or 0),
		svc = nil,
		Service = Service,
		SkyLift = SkyLift,
		makeBody = makeBody,
		holds = {},
		players = {},
		rs = o.rs or Instance.new("Folder"),
		parent = o.parent or Instance.new("Folder"),
	}
	w.rs:SetAttribute(SkyLift.EPOCH_ATTRIBUTE, 1000) -- lift time = clock - 1000 (the service keeps an epoch it finds)
	w.svc = Service.new({
		town = o.town or SkyLiftFlow.stubTown(w),
		now = function(): number
			return w.clock
		end,
		rs = w.rs,
		parent = w.parent,
		root = o.root or Instance.new("Folder"),
		prompts = o.prompts == true,
	})
	return w
end

function SkyLiftFlow.step(w: World, seconds: number, dt: number?)
	local d = dt or 0.1
	for _ = 1, math.max(1, math.ceil(seconds / d - 1e-9)) do
		w.clock += d
		w.svc:step(d)
	end
end

-- The stand point by a station's gate (the gate post, on the floor).
function SkyLiftFlow.atGate(w: World, station: string): CFrame
	local at = w.svc.gates[station].at
	local st = w.SkyLift.stations()[station]
	return CFrame.new(at.X, st.platformY + 3, at.Z)
end

local function lastOf(p: any, kind: string): any
	for i = #p.events, 1, -1 do
		if p.events[i].kind == kind then
			return p.events[i]
		end
	end
	return nil
end

local function textOf(p: any): string
	local e = p.events[#p.events]
	return if e then tostring(e.text or e.value) else ""
end

-- One person rides from `station` to the other end. Adds failures; returns the numbers it measured.
local function rideOnce(w: World, check: (any, string) -> boolean, station: string): { [string]: number }
	local SkyLift = w.SkyLift
	local other = if station == "base" then "summit" else "base"
	local p = SkyLiftFlow.player(w, `Rider_{station}`, "human", SkyLiftFlow.atGate(w, station))
	local ok, why = w.svc:press(p, station)
	check(ok, `{station}: the gate refused a person: {why}`)
	check(lastOf(p, "notice") ~= nil, `{station}: no "next cabin" words`)
	local booked = w.svc.waiters[p]
	check(booked ~= nil, `{station}: not waiting after pressing`)
	if booked == nil then
		return {}
	end
	local boardAt, arriveAt, cabin, seat = booked.boardAt, booked.arriveAt, booked.cabin, booked.seat
	local t0 = w.svc:time()
	check(boardAt - t0 <= SkyLift.period() / SkyLift.CABINS + 1e-6, `{station}: waits longer than one headway`)
	-- until the doors: no grant yet
	while w.svc:time() < boardAt - 0.2 do
		SkyLiftFlow.step(w, 0.1)
	end
	check(lastOf(p, "deviceGranted") == nil, `{station}: granted before the cabin was there`)
	SkyLiftFlow.step(w, 0.4)
	local g = lastOf(p, "deviceGranted")
	check(g ~= nil, `{station}: no device grant at boardAt`)
	local numbers: { [string]: number } = { wait = boardAt - t0 }
	if g then
		local v = g.value
		check(v.device == "ride" and v.kind == "gondola", `{station}: grant is {v.device}/{v.kind}, not ride/gondola`)
		check(v.firstPerson == true, `{station}: first person not asked for`)
		check(v.cabin == cabin and v.seat == seat, `{station}: grant names another seat`)
		local _, _, _, _, phase, open = SkyLift.cabin(cabin, g.at - 1000)
		check(open and phase == station, `{station}: boarded with the doors shut ({phase})`)
	end
	check(p.body:GetAttribute("Ride") == `{cabin}/{seat}`, `{station}: body has no Ride attribute`)
	check(p.attrs.OnRide == SkyLift.RIDE_ID, `{station}: player has no OnRide attribute`)
	check(p.body.PrimaryPart.Anchored == true, `{station}: root not anchored on the seat`)
	check(w.svc:busy(p) == "riding", `{station}: busy() does not say riding`)
	-- mid-ride: on the seat (the service's own pose) at a few times
	local worst = 0
	for _ = 1, 5 do
		SkyLiftFlow.step(w, 7)
		if w.svc:time() < arriveAt then
			local x, y, z = SkyLift.seat(cabin, seat, w.svc:time())
			local pos = p.body:GetPivot().Position
			local d = (pos - Vector3.new(x, y + w.Service.ROOT_ABOVE_SEAT, z)).Magnitude
			worst = math.max(worst, d)
		end
	end
	numbers.seatError = worst
	check(worst < 0.05, `{station}: body {worst} studs off its seat mid-ride`)
	local press2 = w.svc:press(p, station)
	check(press2 == false and string.find(textOf(p), "sky lift", 1, true) ~= nil, `{station}: pressing mid-ride`)
	while w.svc:time() < arriveAt + 0.5 and w.clock < 5000 do
		SkyLiftFlow.step(w, 0.1)
	end
	local r = lastOf(p, "deviceReleased")
	check(r ~= nil and r.value == "ride_end", `{station}: no release at the far end`)
	if r then
		local took = r.at - 1000 - boardAt
		numbers.ride = took
		check(
			math.abs(took - SkyLift.rideTime(station)) <= 2,
			`{station}: ride took {took} s, the timetable says {SkyLift.rideTime(station)}`
		)
	end
	local words = if other == "summit" then w.Service.WORDS.upArrive else w.Service.WORDS.downArrive
	local n = lastOf(p, "notice")
	check(n ~= nil and n.text == words, `{station}: arrival words were "{n and n.text}"`)
	local st = SkyLift.stations()[other]
	local pos = p.body:GetPivot().Position
	local sx, _, sz = SkyLift.alightSpot(other, seat)
	local dAlight = math.sqrt((pos.X - sx) ^ 2 + (pos.Z - sz) ^ 2)
	numbers.fromAlight = dAlight
	check(dAlight < 0.3, `{station}: stood {dAlight} from seat {seat}'s spot on the platform`)
	check(math.abs(pos.Y - (st.platformY + 3)) < 0.1, `{station}: not standing on the platform ({pos.Y})`)
	check(p.body.PrimaryPart.Anchored == false, `{station}: root still anchored after the ride`)
	check(p.body:GetAttribute("Ride") == nil and p.attrs.OnRide == nil, `{station}: ride attributes left behind`)
	check(w.svc:busy(p) == nil, `{station}: still busy after the ride`)
	return numbers
end

function SkyLiftFlow.play(Service: any, makeBody: (name: string, cf: CFrame) -> any, SkyLift: any): { [string]: any }
	local failures: { string } = {}
	local numbers: { [string]: any } = {}
	local function check(cond: any, msg: string): boolean
		if not cond then
			table.insert(failures, msg)
		end
		return cond == true or (cond ~= nil and cond ~= false)
	end
	local function clean(w: World, what: string)
		local c = w.svc:counts()
		check(
			c.waiting == 0 and c.riding == 0 and c.held == 0 and c.booked == 0 and c.seated == 0,
			`{what}: left behind waiting {c.waiting} riding {c.riding} held {c.held} booked {c.booked} seated {c.seated}`
		)
	end

	-- up and down
	do
		local w = SkyLiftFlow.newWorld(Service, makeBody, SkyLift, { start = 3 })
		numbers.up = rideOnce(w, check, "base")
		numbers.down = rideOnce(w, check, "summit")
		clean(w, "up and down")
		w.svc:stop()
	end

	-- refusals: a squirrel, a driver; nothing booked
	do
		local w = SkyLiftFlow.newWorld(Service, makeBody, SkyLift)
		local sq = SkyLiftFlow.player(w, "Squirrel", "squirrel", SkyLiftFlow.atGate(w, "base"))
		local ok, why = w.svc:press(sq, "base")
		check(not ok and lastOf(sq, "refused") ~= nil, "a squirrel was not refused with words")
		check(why == Service.WORDS.animal, `the squirrel was told "{why}"`)
		local dr = SkyLiftFlow.player(w, "Driver", "human", SkyLiftFlow.atGate(w, "base"))
		dr.driving = true
		local ok2, why2 = w.svc:press(dr, "base")
		check(not ok2 and why2 ~= nil and string.find(why2, "vehicle", 1, true) ~= nil, "a driver was not refused")
		local far = SkyLiftFlow.player(w, "Far", "human", SkyLiftFlow.atGate(w, "base") * CFrame.new(40, 0, 0))
		local ok3 = w.svc:press(far, "base")
		check(not ok3 and lastOf(far, "refused") ~= nil, "someone 40 studs from the gate was booked")
		clean(w, "refusals")
		w.svc:stop()
	end

	-- five at once: four in the first cabin, the fifth in the next
	do
		local w = SkyLiftFlow.newWorld(Service, makeBody, SkyLift, { start = 7 })
		local five = {}
		for i = 1, 5 do
			local p = SkyLiftFlow.player(w, `Five{i}`, "human", SkyLiftFlow.atGate(w, "base"))
			w.svc:press(p, "base")
			table.insert(five, p)
		end
		local first = w.svc.waiters[five[1]]
		local fifth = w.svc.waiters[five[5]]
		check(first ~= nil and fifth ~= nil, "five people were not all booked")
		if first and fifth then
			local seats: { [number]: boolean } = {}
			for i = 1, 4 do
				local b = w.svc.waiters[five[i]]
				check(b.cabin == first.cabin and b.boardAt == first.boardAt, `person {i} not in the first cabin`)
				seats[b.seat] = true
			end
			check(seats[1] and seats[2] and seats[3] and seats[4], "the first four do not fill seats 1 to 4")
			check(fifth.cabin ~= first.cabin and fifth.boardAt > first.boardAt, "the fifth shares the full cabin")
			local headway = SkyLift.period() / SkyLift.CABINS
			check(math.abs(fifth.boardAt - first.boardAt - headway) < 1e-6, "the fifth is not on the very next cabin")
			check(string.find(textOf(five[5]), "full", 1, true) ~= nil, "the fifth was not told the cabin was full")
		end
		SkyLiftFlow.step(w, SkyLift.period() / SkyLift.CABINS * 2 + SkyLift.rideTime("base") + 2)
		for i, p in five do
			check(lastOf(p, "deviceReleased") ~= nil, `person {i} of five never arrived`)
		end
		clean(w, "five at once")
		w.svc:stop()
	end

	-- walking away gives the place up
	do
		local w = SkyLiftFlow.newWorld(Service, makeBody, SkyLift, { start = 11 })
		local p = SkyLiftFlow.player(w, "Walker", "human", SkyLiftFlow.atGate(w, "summit"))
		w.svc:press(p, "summit")
		p.body:PivotTo(SkyLiftFlow.atGate(w, "summit") * CFrame.new(Service.WANDER + 6, 0, 0))
		SkyLiftFlow.step(w, 0.2)
		check(w.svc:busy(p) == nil, "a person who walked away is still waiting")
		check(lastOf(p, "refused") ~= nil and lastOf(p, "refused").text == Service.WORDS.walkedAway, "no words")
		clean(w, "walk away")
		w.svc:stop()
	end

	-- a rider whose player leaves mid-ride: held on the seat, handed to the brain on the far platform
	do
		local w = SkyLiftFlow.newWorld(Service, makeBody, SkyLift, { start = 19 })
		local p = SkyLiftFlow.player(w, "Leaver", "human", SkyLiftFlow.atGate(w, "base"))
		w.svc:press(p, "base")
		local b = w.svc.waiters[p]
		if check(b ~= nil, "the leaver was not booked") then
			local arriveAt = b.arriveAt
			while w.svc:time() < b.boardAt + 20 do
				SkyLiftFlow.step(w, 0.1)
			end
			check(lastOf(p, "deviceGranted") ~= nil, "the leaver never boarded")
			p.gone = true
			w.svc:gone(p)
			SkyLiftFlow.step(w, 5)
			local rec = w.holds[p.body]
			check(rec ~= nil and rec.places > 0, "the left body was not held on its seat")
			while w.svc:time() < arriveAt + 0.5 do
				SkyLiftFlow.step(w, 0.1)
			end
			local freed = rec and rec.freed
			check(freed ~= nil, "the left body was never handed to its brain")
			if freed then
				local st = SkyLift.stations().summit
				local sx, _, sz = SkyLift.alightSpot("summit", b.seat)
				local d = math.sqrt((freed[1] - sx) ^ 2 + (freed[3] - sz) ^ 2)
				check(d < 0.3, `the left body was freed {d} from its seat's spot`)
				check(math.abs(freed[2] - st.platformY) < 0.01, "the left body was freed off the platform")
				check(math.abs(freed[5] - 1000 - arriveAt) <= 0.2, "the left body was freed at the wrong time")
				numbers.orphanFreedAt = freed[5] - 1000 - arriveAt
			end
			check(lastOf(p, "deviceReleased") == nil, "a player who left was sent a release")
		end
		clean(w, "orphan")
		w.svc:stop()
	end

	-- soak: 200 random boardings and leaves
	do
		local w = SkyLiftFlow.newWorld(Service, makeBody, SkyLift, { start = 23 })
		local seed = 12345
		local function rnd(n: number): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed % n + 1
		end
		local pool = {}
		for i = 1, 12 do
			local station = if i % 2 == 0 then "base" else "summit"
			local p = SkyLiftFlow.player(w, `Soak{i}`, "human", SkyLiftFlow.atGate(w, station))
			p.station = station
			table.insert(pool, p)
		end
		local presses, granted = 0, 0
		for _ = 1, 200 do
			local p = pool[rnd(#pool)]
			local act = rnd(10)
			if act <= 6 then
				-- back to a gate (the one at the end they are at) and press
				if not w.svc:busy(p) then
					local pos = p.body:GetPivot().Position
					local nearBase = (pos - SkyLiftFlow.atGate(w, "base").Position).Magnitude
						< (pos - SkyLiftFlow.atGate(w, "summit").Position).Magnitude
					local station = if nearBase then "base" else "summit"
					if p.gone then
						-- back in the game: a new body (the old one may still be held in a cabin)
						p.gone = false
						p.body = w.makeBody(p.Name, SkyLiftFlow.atGate(w, station))
					end
					p.body:PivotTo(SkyLiftFlow.atGate(w, station))
					if w.svc:press(p, station) then
						presses += 1
					end
				end
			elseif act <= 8 then
				-- walk off (a waiter gives up their place; a rider is unaffected)
				if w.svc:busy(p) == "waiting" then
					p.body:PivotTo(p.body:GetPivot() * CFrame.new(30, 0, 0))
				end
			else
				-- leave the game and come back later as the same stub (a rider's body is held)
				if not p.gone then
					p.gone = true
					w.svc:gone(p)
				end
			end
			SkyLiftFlow.step(w, rnd(40) * 0.25, 0.25)
		end
		for _, p in pool do
			for _, e in p.events do
				if e.kind == "deviceGranted" then
					granted += 1
				end
			end
		end
		-- long enough for everyone in the air to land
		SkyLiftFlow.step(w, SkyLift.rideTime("base") + SkyLift.period(), 0.25)
		numbers.soak = { presses = presses, granted = granted }
		check(granted > 20, `only {granted} boardings in the soak`)
		clean(w, "soak")
		w.svc:stop()
	end

	return { ok = #failures == 0, failures = failures, numbers = numbers }
end

-- Engine: the service module from the place, bodies as plain Models (a root and a Humanoid) under Workspace.
function SkyLiftFlow.run(): { [string]: any }
	local ServerScriptService = game:GetService("ServerScriptService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local server = ServerScriptService:WaitForChild("Server")
	local Service = (require :: any)(server:WaitForChild("Rides"):WaitForChild("SkyLiftService"))
	local SkyLift = (require :: any)(
		ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rides"):WaitForChild("SkyLift")
	)
	local folder = Instance.new("Folder")
	folder.Name = "SkyLiftCheckBodies"
	folder.Parent = workspace
	local function makeBody(name: string, cf: CFrame): any
		local m = Instance.new("Model")
		m.Name = name
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Anchored = false
		root.CanCollide = false
		root.Parent = m
		m.PrimaryPart = root
		local hum = Instance.new("Humanoid")
		hum.Parent = m
		m:PivotTo(cf)
		m.Parent = folder
		return m
	end
	local t0 = os.clock()
	local ok, result = pcall(SkyLiftFlow.play, Service, makeBody, SkyLift)
	folder:Destroy()
	if not ok then
		return { ok = false, failures = { `the flow threw: {result}` }, numbers = {} }
	end
	result.numbers.seconds = os.clock() - t0
	return result
end

return SkyLiftFlow
