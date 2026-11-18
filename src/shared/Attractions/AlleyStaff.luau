--!strict
-- ReplicatedStorage.Shared.Attractions.AlleyStaff
-- The bowling alley's employees (BRIEF_ADDENDUM D5: "a few other hyper smart sophisticated employees that are npcs
-- and constantly doing different stuff"): who they are and the work each one does, on a schedule, in the alley's
-- own frame (Shared/Attractions/AlleyLayout: X across, D down the lane). Each employee walks a loop of STOPS; a
-- stop with `hold` > 0 is a piece of work: the employee stands there `hold` seconds facing `face` doing `act`
-- (the body's Task attribute: Client/Animation/AnimationDriver.taskPose poses a kneel); a stop with hold 0 is a
-- waypoint on the way. Every leg between two stops is a leg of AlleyLayout.ROUTES (or runs along one of the alley's
-- own lines named below), so it never meets a wall, a counter or a game's table; every stop is on a floor, in one of
-- the employee's rooms, and never in a lane's ball path (from the foul line to the pit): tests/unit/alley_staff.
--   shoe_clerk      the shoe rental: takes a pair at the desk, fetches a size from the cubbies, sprays the returns
--                   at the spray bench, puts them back in their cubby;
--   mechanic        the back corridor: the bench, then along behind the machines to a lane's pinsetter, kneels at
--                   it, the next, back to the bench and the spare pins (MECHANIC_LANES, in turn);
--   cleaner         the hall: dust-mops the back of the approaches from lane 1 to lane 18 and back (APPROACH_MOP: on
--                   the approaches' back edge, behind every bowler's run-up, clear of the settees), then wipes the
--                   house balls on the west aisle's shelves;
--   front_desk      the snack bar and the lobby: the till, the grill, the fridge, the pass, and out to greet at the
--                   lobby's welcome spot;
--   games_attendant the games room: the arch, the floor, polishing the cabinets at the front, racking at the back.
-- A player may take over any of them like any other person (Server/Actors/Possession): the body is a town person.
-- Interface: EMPLOYEES; MECHANIC_LANES; APPROACH_MOP; ACTS; employee(id) -> Employee; shift(place, employee) ->
--   { WorldStop } (world studs, the loop in order); floorAt(place, x, z) -> y? (the floor under a world point inside
--   the building's walls); inside(place, x, z) -> boolean; insideLocal(X, D) -> boolean; placeOf(data) -> Place?
--   (the alley's placement in Shared/Data's generated/Attractions, nil when the data has none)
-- Pure; studs. No side effects on require.

local AlleyLayout = require("./AlleyLayout")

local AlleyStaff = {}

export type Stop = { x: number, d: number, hold: number, act: string?, face: { number }? }
export type Employee = { id: string, title: string, rooms: { string }, stops: { Stop } }
export type WorldStop = { x: number, z: number, hold: number, act: string?, yaw: number? }

-- What an act looks like (the Task attribute's values).
AlleyStaff.ACTS = table.freeze({
	serve = "at a counter, facing the customer",
	fetch = "taking something off a shelf",
	spray = "spraying a returned pair of shoes",
	shelve = "putting a pair back in its cubby",
	collect = "taking returned shoes at the window",
	repair = "at the workbench",
	kneel = "kneeling at a pinsetter",
	mop = "dust-mopping the approach",
	cook = "at the grill",
	greet = "greeting at the door",
	polish = "polishing a cabinet",
	rack = "racking the balls",
	watch = "keeping an eye on the room",
})

AlleyStaff.MECHANIC_LANES = { 3, 11, 16, 7 } -- the pinsetters the mechanic tends, in turn
AlleyStaff.APPROACH_MOP = AlleyLayout.APPROACH_D + 0.6 -- D of the mop's line: the approaches' back edge
AlleyStaff.MACHINE_WALK = 69.5 -- D of the walk behind the machines (AlleyLayout.ROUTES.machines)

local L = AlleyLayout

local function stop(x: number, d: number, hold: number?, act: string?, face: { number }?): Stop
	return { x = x, d = d, hold = hold or 0, act = act, face = face }
end

local function mechanic(): { Stop }
	local s = {
		stop(-7, 76.5, 8, "repair", { 0, 1 }),
		stop(-15.5, 74),
		stop(-22.5, 72),
		stop(-15.5, AlleyStaff.MACHINE_WALK),
	}
	for _, lane in AlleyStaff.MECHANIC_LANES do
		local p = L.machinePost(lane)
		table.insert(s, stop(p.x, p.d, 9, "kneel", p.face))
	end
	table.insert(s, stop(-15.5, AlleyStaff.MACHINE_WALK))
	table.insert(s, stop(-22.5, 72))
	table.insert(s, stop(-15.5, 74))
	table.insert(s, stop(9, 76.5, 5, "fetch", { 0, 1 }))
	return s
end

local function cleaner(): { Stop }
	local d = AlleyStaff.APPROACH_MOP
	local s = { stop(-22.5, -36), stop(-22.5, d, 2, "mop", { 1, 0 }) }
	-- along the back of the approaches, a stroke at every pair's middle, to the far side and back
	for p = 1, L.PAIRS do
		table.insert(s, stop(L.pairX(p), d, 3, "mop", { 1, 0 }))
	end
	table.insert(s, stop(97, d, 2, "mop", { -1, 0 }))
	for p = L.PAIRS, 1, -1 do
		table.insert(s, stop(L.pairX(p), d, 3, "mop", { -1, 0 }))
	end
	table.insert(s, stop(-22.5, d, 2, "mop", { 0, -1 }))
	-- and a wipe of the house balls on the west aisle wall on the way back
	table.insert(s, stop(-22.5, -6, 6, "polish", { -1, 0 }))
	return s
end

AlleyStaff.EMPLOYEES = table.freeze({
	{
		id = "shoe_clerk",
		title = "Shoe counter clerk",
		rooms = { "shoe_rental" },
		stops = {
			stop(10.5, -57, 6, "serve", { 1, 0 }),
			stop(1, -62, 5, "fetch", { -1, 0 }),
			stop(10.5, -57, 5, "serve", { 1, 0 }),
			stop(8, -51, 4, "collect", { 0, 1 }),
			stop(3, -55, 6, "spray", { -1, 0 }),
			stop(1, -62, 4, "shelve", { -1, 0 }),
		},
	},
	{ id = "mechanic", title = "Lane mechanic", rooms = { "back_corridor" }, stops = mechanic() },
	{
		id = "cleaner",
		title = "Cleaner",
		rooms = { "left_aisle", "approaches", "right_aisle", "concourse" },
		stops = cleaner(),
	},
	{
		id = "front_desk",
		title = "Snack bar and front desk",
		rooms = { "snack_bar", "concourse", "lobby" },
		stops = {
			stop(62, -51.5, 7, "serve", { 0, 1 }),
			stop(70, -65, 8, "cook", { 0, -1 }),
			stop(85, -62, 4, "fetch", { 1, 0 }),
			stop(82.5, -50, 4, "serve", { 0, 1 }),
			stop(82.5, -44),
			stop(86, -36),
			stop(70, -36),
			stop(37, -36),
			stop(22, -36),
			stop(22, -52, 8, "greet", { 0, -1 }),
			stop(22, -36),
			stop(37, -36),
			stop(70, -36),
			stop(86, -36),
			stop(82.5, -44),
			stop(82.5, -50),
			stop(82.5, -52.5), -- clear of the counter's end on the way back to the till
		},
	},
	{
		id = "games_attendant",
		title = "Games room attendant",
		rooms = { "games_room" },
		stops = {
			stop(106, -39, 5, "watch", { 1, 0 }),
			stop(122, -26, 5, "watch", { 0, 1 }),
			stop(122, -56),
			stop(136, -60, 7, "polish", { 0, -1 }),
			stop(122, -56),
			stop(122, 2),
			stop(132, 12),
			stop(132, 22, 7, "rack", { 0, 1 }),
			stop(132, 12),
			stop(122, 2),
			stop(122, -26),
		},
	},
} :: { Employee })

function AlleyStaff.employee(id: string): Employee
	for _, e in AlleyStaff.EMPLOYEES do
		if e.id == id then
			return e
		end
	end
	error(`AlleyStaff: no employee {id}`)
end

-- A local facing (dX, dD) as the HTML yaw a body takes (0 faces +Z).
local function yawOf(place: AlleyLayout.Place, face: { number }): number
	local dx, dz = L.dirToWorld(place, face[1], face[2])
	return math.atan2(dx, dz)
end

-- The bowling alley's placement (generated/Attractions), or nil when the data has none.
function AlleyStaff.placeOf(data: any): AlleyLayout.Place?
	local ok, mod = pcall(function()
		return data:module("Attractions")
	end)
	for _, a in (if ok and mod and mod.attractions then mod.attractions else {}) :: { any } do
		if a.id == "bowling_alley" and a.place then
			return a.place
		end
	end
	return nil
end

-- The employee's loop in world studs.
function AlleyStaff.shift(place: AlleyLayout.Place, e: Employee): { WorldStop }
	local out: { WorldStop } = {}
	for _, s in e.stops do
		local x, _, z = L.toWorld(place, s.x, 0, s.d)
		table.insert(out, {
			x = x,
			z = z,
			hold = s.hold,
			act = s.act,
			yaw = if s.face then yawOf(place, s.face) else nil,
		})
	end
	return out
end

-- Inside the building's walls (the hall and the games room), in the alley's frame.
function AlleyStaff.insideLocal(X: number, D: number): boolean
	local hall = X >= L.X0 and X <= L.HALL_X1 and D >= L.FRONT_D and D <= L.REAR_WALL_D
	local wing = X >= L.HALL_X1 and X <= L.X1 and D >= L.GAME_ROOM_D0 and D <= L.GAME_ROOM_D1
	return hall or wing
end

-- The same in world studs.
function AlleyStaff.inside(place: AlleyLayout.Place, x: number, z: number): boolean
	local X, _, D = L.toLocal(place, x, 0, z)
	return AlleyStaff.insideLocal(X, D)
end

-- The floor's height under a world point inside the building (nil outside its walls).
function AlleyStaff.floorAt(place: AlleyLayout.Place, x: number, z: number): number?
	if not AlleyStaff.inside(place, x, z) then
		return nil
	end
	local X, _, D = L.toLocal(place, x, 0, z)
	local y = L.floorAt(X, D)
	return if y then place.floorY + y else nil
end

return AlleyStaff
