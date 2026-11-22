--!strict
-- ReplicatedStorage.Shared.Work.Errands
-- The bank errands, pure (owner D30: "outside of which there are tasks or other optional errands, deliver such and
-- such to such and such place or person. At which point, it pays to know your way around town"; and the penalty:
-- "if ... the errand delivery person steals the item, or places it in their home and does not bring it back, in the
-- event they can't find the drop off spot, they should get penalized by losing 100 spicy bucks").
--   * DESTINATIONS: real places and real townspeople of the town (the cast's residents at their houses' doors), each
--     with the spot a parcel is handed over at (world studs, on foot, clear of every road and building:
--     tests/unit/work_errands.spec). The place is NAMED, never marked on the map or the screen.
--   * ITEMS: what is carried (a parcel, a letter, flowers, a cake box, a book): its words and its look (the prop
--     Server/Work/ErrandService puts in the carrier's hand).
--   * offer(bankId, from, rand) -> Errand: a destination at least MIN_DISTANCE from the board, an item that suits it,
--     the words ("Take this parcel to Pepper's Corner Store."), the pay (pay(distance): Tunables work.errandBaseCents
--     plus errandCentsPer100 for every 100 studs, at most errandMaxCents) and the time it may take (limit(distance):
--     the straight distance at an easy walk, errandPace, plus errandSlackSecs: generous on foot, the way round
--     included).
--   * start(errand, now) -> Run; step(run, now, at?, atHome, dt) -> what happened this step, at most one of:
--       "delivered"  within DROP studs of the spot: paid (the server pays errand.cents);
--       "close"      the first time within CLOSE studs: a gentle "you're close" (once an errand);
--       "expired"    past the time limit with it still in hand (checked first: late at the spot is late): kept
--                    (the penalty);
--       "kept_home"  in their own home with it for errandHomeSecs in all: kept (the penalty);
--     handBack(run): handed back at any bank's board (they could not find it): over, nothing owed either way.
--     Leaving the server with it is the server's to call kept (ErrandService: PlayerRemoving). left(run, now) ->
--     seconds left; pay(distance), limit(distance), duration(secs) -> "5 minutes"; CLOSE(), DROP() (the tunables).
-- Pure; studs and seconds. No side effects on require.

local Tunables = require("../Config/Tunables")

local Errands = {}

Errands.MIN_DISTANCE = 200 -- studs from the board: never an errand to the house next door

export type Destination = {
	id: string,
	name: string, -- as said: "Pepper's Corner Store", "the Victorian house south-west of the old town crossroads"
	x: number,
	z: number,
	people: { string }?, -- townspeople at this door (a person errand names one of them)
}

-- stylua: ignore
Errands.DESTINATIONS = table.freeze({
	{ id = "peppers", name = "Pepper's Corner Store", x = 963, z = 55 },
	{ id = "neighbourhood_shop", name = "the Neighbourhood Shop", x = 674.7, z = 48.5 },
	{ id = "gilded_acorn", name = "the Gilded Acorn lounge", x = 1487, z = -327 },
	{ id = "bowling", name = "the bowling alley's front doors", x = 1322, z = -344 },
	{ id = "grill", name = "the Chili Pepper Grill", x = 1185, z = -160.2 },
	{ id = "clock_tower", name = "the clock tower in the Quay Market", x = 2627.5, z = 66.2 },
	{ id = "galleria", name = "the Bellwether Galleria's front doors", x = 2755, z = 704 },
	{ id = "sky_lift", name = "the sky lift's station at the foot of Lookout Hill", x = -753.6, z = -907.4 },
	{ id = "police", name = "the West Topeka police station", x = -1275, z = -222.8 },
	{ id = "fuel_west", name = "the Westside fuel station", x = -992.5, z = 535.2 },
	{ id = "storage", name = "Westside Storage", x = -1282.5, z = 427.8 },
	-- the cast's residents (data/authored/cast: homeLot), at their front doors round the old town crossroads
	{ id = "victorian", name = "the Victorian house south-west of the old town crossroads", x = -140, z = -110.5,
	  people = { "Mrs. Abbott", "Donna", "Frank" } },
	{ id = "bungalow", name = "the bungalow south-east of the old town crossroads", x = 127.5, z = -124.5,
	  people = { "Helen", "Marty", "Tessa" } },
	{ id = "brick_house", name = "the brick house north-west of the old town crossroads", x = -132.5, z = 104.5,
	  people = { "Ruth", "Calvin", "Oliver" } },
	{ id = "blue_cottage", name = "the blue cottage north-east of the old town crossroads", x = 145, z = 119,
	  people = { "Molly", "Diana", "Sam" } },
} :: { Destination })

export type Item = {
	id: string,
	this: string, -- "this parcel"
	the: string, -- "the parcel"
	size: { number }, -- the prop (studs)
	color: { number }, -- RGB 0-255
	person: boolean?, -- something one brings to a person (flowers, a cake)
	place: boolean?, -- something one takes to a place
}

-- stylua: ignore
Errands.ITEMS = table.freeze({
	{ id = "parcel", this = "this parcel", the = "the parcel", size = { 1.3, 0.9, 1.0 }, color = { 176, 132, 86 }, person = true, place = true },
	{ id = "letter", this = "this letter", the = "the letter", size = { 0.9, 0.1, 0.6 }, color = { 240, 236, 222 }, person = true, place = true },
	{ id = "flowers", this = "these flowers", the = "the flowers", size = { 0.6, 1.4, 0.6 }, color = { 214, 96, 140 }, person = true },
	{ id = "cake", this = "this cake box", the = "the cake box", size = { 1.2, 0.7, 1.2 }, color = { 246, 196, 206 }, person = true },
	{ id = "book", this = "this book", the = "the book", size = { 0.8, 1.1, 0.25 }, color = { 128, 40, 44 }, place = true, person = true },
} :: { Item })

export type Errand = {
	bank: string,
	dest: Destination,
	person: string?,
	item: Item,
	words: string, -- "Take this parcel to Pepper's Corner Store."
	to: string, -- "Pepper's Corner Store" or "Mrs. Abbott at the Victorian house ..."
	distance: number,
	cents: number,
	secs: number,
}

export type Run = {
	errand: Errand,
	startedAt: number,
	dueAt: number,
	homeSecs: number,
	closeSaid: boolean,
	over: string?, -- set once it has ended: "delivered", "expired", "kept_home", "returned", "left"
}

local function num(path: string, default: number): number
	local v = Tunables.get(path)
	return if type(v) == "number" and v == v then v else default
end

function Errands.CLOSE(): number
	return num("work.errandCloseStuds", 45)
end

function Errands.DROP(): number
	return num("work.errandDropStuds", 9)
end

-- Whole cents for an errand of this many studs.
function Errands.pay(distance: number): number
	local base = num("work.errandBaseCents", 4)
	local per = num("work.errandCentsPer100", 1)
	local most = num("work.errandMaxCents", 30)
	return math.floor(math.clamp(base + per * math.max(0, distance) / 100, 0, most))
end

-- Seconds an errand of this many studs may take: the distance at an easy walk, plus the slack.
function Errands.limit(distance: number): number
	return math.ceil(
		math.max(0, distance) / math.max(0.5, num("work.errandPace", 5)) + num("work.errandSlackSecs", 120)
	)
end

-- "5 minutes" / "1 minute" / "45 seconds"
function Errands.duration(secs: number): string
	if secs < 90 then
		return `{math.max(1, math.floor(secs + 0.5))} seconds`
	end
	local m = math.floor(secs / 60 + 0.5)
	return if m == 1 then "1 minute" else `{m} minutes`
end

-- An errand from this bank's board at `from` ({x, z}): a destination far enough away, an item that suits it.
function Errands.offer(bankId: string, from: { number }, rand: () -> number): Errand
	local list: { Destination } = {}
	for _, d in Errands.DESTINATIONS do
		if math.sqrt((d.x - from[1]) ^ 2 + (d.z - from[2]) ^ 2) >= Errands.MIN_DISTANCE then
			table.insert(list, d)
		end
	end
	assert(#list > 0, "Errands.offer: no destination far enough")
	local dest = list[math.clamp(math.floor(rand() * #list) + 1, 1, #list)]
	local person: string? = nil
	if dest.people and #dest.people > 0 then
		person = dest.people[math.clamp(math.floor(rand() * #dest.people) + 1, 1, #dest.people)]
	end
	local items: { Item } = {}
	for _, it in Errands.ITEMS do
		if (person and it.person) or (person == nil and it.place) then
			table.insert(items, it)
		end
	end
	local item = items[math.clamp(math.floor(rand() * #items) + 1, 1, #items)]
	local distance = math.sqrt((dest.x - from[1]) ^ 2 + (dest.z - from[2]) ^ 2)
	local to = if person then `{person} at {dest.name}` else dest.name
	local verb = if person then "Bring" else "Take"
	return {
		bank = bankId,
		dest = dest,
		person = person,
		item = item,
		words = `{verb} {item.this} to {to}.`,
		to = to,
		distance = distance,
		cents = Errands.pay(distance),
		secs = Errands.limit(distance),
	}
end

function Errands.start(errand: Errand, now: number): Run
	return { errand = errand, startedAt = now, dueAt = now + errand.secs, homeSecs = 0, closeSaid = false, over = nil }
end

-- One step of a run: `at` is where the carrier stands ({x, z}; nil: not in a body that can carry it), atHome
-- whether that is inside their own home. Returns what happened (see the header), or nil.
function Errands.step(run: Run, now: number, at: { number }?, atHome: boolean, dt: number): string?
	if run.over then
		return nil
	end
	local e = run.errand
	if now > run.dueAt then
		run.over = "expired"
		return "expired"
	end
	if at then
		local d = math.sqrt((at[1] - e.dest.x) ^ 2 + (at[2] - e.dest.z) ^ 2)
		if d <= Errands.DROP() then
			run.over = "delivered"
			return "delivered"
		end
		if atHome then
			run.homeSecs += math.max(0, dt)
			if run.homeSecs >= num("work.errandHomeSecs", 20) then
				run.over = "kept_home"
				return "kept_home"
			end
		end
		if not run.closeSaid and d <= Errands.CLOSE() then
			run.closeSaid = true
			return "close"
		end
	end
	return nil
end

-- Handed back at a bank's board: over, nothing owed either way.
function Errands.handBack(run: Run)
	run.over = run.over or "returned"
end

-- Seconds left (0 when past due).
function Errands.left(run: Run, now: number): number
	return math.max(0, run.dueAt - now)
end

return Errands
