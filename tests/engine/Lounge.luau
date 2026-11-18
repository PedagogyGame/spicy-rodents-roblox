--!strict
-- ServerStorage.EngineTests.Lounge (CI place only; injected with --inject ci.project.json or a saved version)
-- THE GILDED ACORN's door, guards and bar on a server with no clients, as plain results (brief v2 "Lounge one";
-- addendum D14). Server/Attractions/LoungeService is started on its own with a stub Town (PlayerLike stubs with a
-- purse and a pass, bodies built here, a stand-in for the bake's staff) and a clock this check moves:
--   pass      a person with the pass presses the door: just inside, facing the room, CameraZone lockFirstPerson,
--             Lounge = the venue, "Welcome"
--   no pass   a person without it is told "Members only." and the offer; not moved, no first person
--   buy       with 25c the podium sells the pass (20c gone) and the person is inside; with 7c it is refused with
--             the wallet's words, nothing taken, still outside
--   squirrel  a squirrel's press is refused with words; on the forecourt, on the steps, on the landing or in the
--             room the guards knock it out (once per body, the nearest guard steps in and back); on Bowl Lane, on
--             the roof or along the front away from the entry nobody touches it
--   drink     inside, each of the four drinks: charged its price only when it is in the hand, sipped SIPS times
--             (the cup up at the face and back down), then "All gone."; a second order while holding one, and an
--             order from outside, are refused with words and take nothing
--   leave     the door from inside: back on the landing facing the street, first person released, the drink gone
--   swap      a body let in whose player picks a new one loses first person and is put out on the landing
--   leaver    a player who leaves the game while inside with a drink: nothing left behind, the body put out
-- play() takes its parts as arguments, so the Lune suite runs this same flow on the fake engine
-- (tests/isolated/lounge_service.luau): the check is itself checked before a cloud run is spent on it.
-- Interface: run() -> Result (engine only); play(deps) -> Result { ok, failures, numbers }
--   deps = { Service, LoungeClassic, EconomyRules, AlleyLayout, makeBody(name, cf) -> Model,
--     makeModel(name, cf, parent) -> Model (with a PrimaryPart), folder() -> Instance }

local LoungeFlow = {}

export type Deps = {
	Service: any,
	LoungeClassic: any,
	EconomyRules: any,
	AlleyLayout: any,
	makeBody: (name: string, cf: CFrame) -> any,
	makeModel: (name: string, cf: CFrame, parent: any) -> any,
	folder: (name: string) -> any,
}

function LoungeFlow.play(deps: Deps): { [string]: any }
	local Service, LC, ER, AL = deps.Service, deps.LoungeClassic, deps.EconomyRules, deps.AlleyLayout
	local failures: { string } = {}
	local numbers: { [string]: any } = {}
	local function check(cond: any, what: string)
		if not cond then
			table.insert(failures, what)
		end
	end
	local venue: any = nil
	local clock = 0
	-- the venue's frame, from the service (it reads generated/Expansion itself)
	local squirrels: { any } = {}
	local knocked: { any } = {}

	local function newPlayer(name: string, species: string, cents: number, pass: boolean, cf: CFrame): any
		local p =
			{ Name = name, species = species, cents = cents, pass = pass, events = {}, body = deps.makeBody(name, cf) }
		return p
	end
	local function told(p: any): string
		local e = p.events[#p.events]
		return if e then e else ""
	end
	local town = {
		speciesOf = function(p: any): string?
			return if p.gone then nil else p.species
		end,
		bodyOf = function(p: any): any?
			return if p.gone then nil else p.body
		end,
		moveTo = function(p: any, cf: CFrame)
			p.body:PivotTo(cf + Vector3.new(0, Service.STAND, 0))
		end,
		evict = function(body: any, cf: CFrame)
			body:PivotTo(cf + Vector3.new(0, Service.STAND, 0))
		end,
		pass = {
			has = function(p: any): boolean
				return p.pass
			end,
			buy = function(p: any): (boolean, string)
				local spec = ER.pass(ER.PASS)
				if p.pass then
					return false, spec.has
				elseif p.cents < spec.cents then
					return false, `You need {spec.cents}c; you have {p.cents}c.`
				end
				p.cents -= spec.cents
				p.pass = true
				return true, spec.bought
			end,
			offer = function(): (number, number, string)
				local spec = ER.pass(ER.PASS)
				return spec.cents, spec.days, spec.offer
			end,
		},
		buy = function(p: any, id: string, deliver: () -> (boolean?, string?)): (boolean, string)
			local price = ER.price(id)
			if price == nil then
				return false, "That is not for sale yet."
			elseif p.cents < price then
				return false, `You need {price}c; you have {p.cents}c.`
			end
			local ok, why = deliver()
			if ok ~= true then
				return false, why or "Sorry."
			end
			p.cents -= price
			return true, `Paid {price}c for {id}.`
		end,
		tell = function(p: any, text: string)
			table.insert(p.events, text)
		end,
		squirrels = function(): { any }
			return squirrels
		end,
		knockOut = function(actor: any)
			table.insert(knocked, actor)
		end,
	}
	-- a stand-in for the bake's staff: two guards on their posts and the bartender
	local root = deps.folder("f3_lounge_classic")
	local staff = deps.folder("Staff")
	staff.Parent = root
	local okV, v = pcall(Service._venue, LC.VENUE)
	if not okV then
		return { ok = false, failures = { `no venue: {v}` }, numbers = numbers }
	end
	venue = v
	local exp = LC.placeOf(venue)
	local function world(x: number, y: number, d: number): Vector3
		local wx, wy, wz = AL.toWorld(exp, x, y, d)
		return Vector3.new(wx, wy, wz)
	end
	for k, g in LC.GUARD_POSTS do
		deps.makeModel(`Guard{k}`, CFrame.new(world(g.x, 0.5, g.d)), staff)
	end
	deps.makeModel("Bartender", CFrame.new(world(0, 2.9, 20)), staff)
	local svc = Service.new({
		town = town,
		root = root,
		parent = deps.folder("LoungeCheck"),
		now = function(): number
			return clock
		end,
	})
	local function step(seconds: number)
		local n = math.max(1, math.floor(seconds / 0.1 + 0.5))
		for _ = 1, n do
			clock += 0.1
			svc:step(0.1)
		end
	end
	local function localOf(body: any): (number, number, number)
		local p = body:GetPivot().Position
		return AL.toLocal(exp, p.X, p.Y - Service.STAND, p.Z)
	end
	local street = CFrame.new(world(0, -2.4 + Service.STAND, -30))

	-- pass
	local a = newPlayer("WithPass", "human", 0, true, street)
	local ok = svc:enter(a)
	local x, _, d = localOf(a.body)
	check(ok, "pass: the door refused a person with the pass")
	check(math.abs(x - LC.DOOR_INSIDE.x) < 0.01 and math.abs(d - LC.DOOR_INSIDE.d) < 0.01, `pass: put at {x}, {d}`)
	check(LC.inside(x, 0, d), "pass: not inside the room")
	local look = a.body:GetPivot().LookVector
	local into = world(0, 0, 1) - world(0, 0, 0)
	check(look:Dot(into) > 0.99, "pass: not facing the room")
	check(a.body:GetAttribute("CameraZone") == LC.ZONE, "pass: no first person")
	check(a.body:GetAttribute(LC.ATTRIBUTE) == LC.VENUE, "pass: no Lounge attribute")
	check(told(a) == LC.WORDS.welcome, `pass: told "{told(a)}"`)
	check(svc:isInside(a), "pass: the service does not hold it inside")

	-- no pass
	local b = newPlayer("NoPass", "human", 0, false, street)
	ok = svc:enter(b)
	check(not ok, "no pass: let in")
	check(string.find(told(b), LC.WORDS.membersOnly, 1, true) == 1, `no pass: told "{told(b)}"`)
	check(string.find(told(b), "both lounges", 1, true) ~= nil, "no pass: not offered the pass")
	check(b.body:GetAttribute("CameraZone") == nil, "no pass: first person outside")
	x, _, d = localOf(b.body)
	check(math.abs(d + 30) < 0.01, "no pass: moved")

	-- buy
	local c = newPlayer("Buyer", "human", 25, false, street)
	local okB, words = svc:buyPass(c)
	check(okB and c.pass and c.cents == 5, `buy: {words}, {c.cents}c left`)
	check(svc:isInside(c), "buy: not let in after buying")
	local poor = newPlayer("Poor", "human", 7, false, street)
	okB, words = svc:buyPass(poor)
	check(not okB and poor.cents == 7 and not poor.pass, "buy: sold to a person with 7c")
	check(string.find(words, "You need", 1, true) ~= nil, `buy: refused with "{words}"`)
	check(not svc:isInside(poor), "buy: the poor one is inside")

	-- squirrel at the door
	local sq = newPlayer("Squirrel", "squirrel", 100, true, street)
	ok = svc:enter(sq)
	check(not ok and told(sq) == LC.WORDS.squirrel, `squirrel: "{told(sq)}"`)
	local fox = newPlayer("Fox", "fox", 0, true, street)
	ok = svc:enter(fox)
	check(not ok and told(fox) == LC.WORDS.animals, `fox: "{told(fox)}"`)
	okB = svc:buyPass(sq)
	check(not okB and sq.cents == 100, "squirrel: sold a pass")

	-- the guards: every guarded spot and every spot in the room, one body each; nowhere else
	local guardHome = staff:FindFirstChild("Guard1"):GetPivot()
	local tried, struck, spared, wrong = 0, 0, 0, 0
	local spots: { { number } } = {}
	for gx = -10, 10, 5 do
		for _, gd in { -32, -30, -28.5, -27, -25, -23 } do
			table.insert(spots, { gx, -2.4, gd, 1 })
		end
	end
	for gx = -20, 20, 10 do
		for gd = -20, 24, 11 do
			table.insert(spots, { gx, 0, gd, 1 })
		end
	end
	for _, s in { { 0, -5, -40 }, { 0, 14.2, 0 }, { 20, -3, -30 }, { -30, -3, 0 }, { 0, -3, 32 } } do
		table.insert(spots, { s[1], s[2], s[3], 0 })
	end
	for i, s in spots do
		table.clear(knocked)
		local actor = { id = `sq{i}` }
		local p = world(s[1], s[2], s[3])
		table.clear(squirrels)
		table.insert(squirrels, { actor = actor, x = p.X, y = p.Y, z = p.Z })
		step(0.3)
		tried += 1
		local hit = #knocked == 1 and knocked[1] == actor
		if s[4] == 1 then
			if hit then
				struck += 1
			else
				table.insert(failures, `guards: no knock-out at X {s[1]} Y {s[2]} D {s[3]}`)
			end
		elseif #knocked > 0 then
			wrong += 1
			table.insert(failures, `guards: knocked out a squirrel at X {s[1]} Y {s[2]} D {s[3]}`)
		else
			spared += 1
		end
	end
	-- the same body standing there is struck once until the cooldown, and the guard is back home after
	table.clear(knocked)
	local stay = { id = "stay" }
	local sp = world(-3, -2.4, -30) -- nearer Guard1
	table.clear(squirrels)
	table.insert(squirrels, { actor = stay, x = sp.X, y = sp.Y, z = sp.Z })
	step(0.3)
	local moved = (staff:FindFirstChild("Guard1"):GetPivot().Position - guardHome.Position).Magnitude
	check(moved > 0.5 and moved <= Service.LUNGE + 1e-3, `guards: the nearest guard stepped {moved} studs`)
	step(1.2)
	check(#knocked == 1, `guards: one body struck {#knocked} times in 1.5 s`)
	table.clear(squirrels)
	step(1.0)
	local back = (staff:FindFirstChild("Guard1"):GetPivot().Position - guardHome.Position).Magnitude
	check(back < 1e-3, `guards: a guard is {back} studs from his post after a strike`)
	numbers.guards = { tried = tried, struck = struck, spared = spared, wrong = wrong, lunge = moved }

	-- drinks: each of the four, sipped to the end
	local drinker = newPlayer("Drinker", "human", 100, true, street)
	svc:enter(drinker)
	local spent = 0
	for _, dr in LC.DRINKS do
		local before = drinker.cents
		local okO, w = svc:order(drinker, dr.id)
		check(okO, `drink: {dr.id} refused: {w}`)
		local price = ER.price(dr.id)
		check(before - drinker.cents == price, `drink: {dr.id} cost {before - drinker.cents}c, price {price}c`)
		spent += before - drinker.cents
		local model = drinker.body:FindFirstChild("LoungeDrink")
		check(model ~= nil, `drink: no {dr.id} in the hand`)
		local again = drinker.cents
		local okAgain = svc:order(drinker, "coffee")
		check(not okAgain and drinker.cents == again and told(drinker) == LC.WORDS.holding, "drink: a second order")
		local sips = 0
		local up = false
		for _ = 1, math.ceil((LC.SIPS * LC.SIP_EVERY + 3) / 0.1) do
			step(0.1)
			local vessel = model and model.PrimaryPart
			local weld = vessel and vessel:FindFirstChild("Hold")
			local nowUp = weld ~= nil and weld.C0.Position.Y > 1
			if nowUp and not up then
				sips += 1
			end
			up = nowUp
		end
		check(sips == LC.SIPS, `drink: {dr.id} sipped {sips} times`)
		check(drinker.body:FindFirstChild("LoungeDrink") == nil, `drink: {dr.id} still in the hand`)
		check(told(drinker) == LC.WORDS.finished, `drink: {dr.id} ended with "{told(drinker)}"`)
	end
	numbers.drinks = { spent = spent }
	local outside = newPlayer("Outside", "human", 50, true, street)
	local okOut = svc:order(outside, "coffee")
	check(not okOut and outside.cents == 50 and told(outside) == LC.WORDS.notInside, "drink: sold outside")

	-- leave, with a drink in the hand
	svc:order(drinker, "hot_cocoa")
	check(svc:leave(drinker), "leave: refused")
	x, _, d = localOf(drinker.body)
	check(math.abs(d - LC.DOOR_OUTSIDE.d) < 0.01 and not LC.inside(x, 0, d), `leave: put at {x}, {d}`)
	check(drinker.body:GetPivot().LookVector:Dot(into) < -0.99, "leave: not facing the street")
	check(drinker.body:GetAttribute("CameraZone") == nil, "leave: still first person")
	check(drinker.body:GetAttribute(LC.ATTRIBUTE) == nil, "leave: still Lounge")
	check(drinker.body:FindFirstChild("LoungeDrink") == nil, "leave: the drink went out with them")
	check(told(drinker) == LC.WORDS.goodbye, `leave: "{told(drinker)}"`)

	-- swap: a body let in, then found outside (a new body) loses first person at the next look
	local e = newPlayer("Swapper", "human", 0, true, street)
	svc:enter(e)
	local old = e.body
	e.body = deps.makeBody("Swapper2", street)
	step(0.5)
	check(old:GetAttribute("CameraZone") == nil and not svc:isInside(e), "swap: the old body keeps first person")
	check(not svc:inRoom(old), "swap: the old body is shut in the room")
	x, _, d = localOf(old)
	check(math.abs(d - LC.DOOR_OUTSIDE.d) < 0.01, `swap: the old body put at {x}, {d}`)

	-- leaver
	local f = newPlayer("Leaver", "human", 30, true, street)
	svc:enter(f)
	svc:order(f, "green_tea")
	f.gone = true
	svc:gone(f)
	step(0.5)
	local counts = svc:counts()
	numbers.counts = counts
	check(not svc:isInside(f), "leaver: still inside")
	check(not svc:inRoom(f.body), "leaver: the body is shut in the room")
	check(f.body:GetAttribute("CameraZone") == nil, "leaver: the body keeps first person")
	check(f.body:FindFirstChild("LoungeDrink") == nil, "leaver: the drink is left behind")
	check(counts.drinks == 0, `leaver: {counts.drinks} drinks left`)
	svc:stop()
	return { ok = #failures == 0, failures = failures, numbers = numbers }
end

function LoungeFlow.run(): { [string]: any }
	local ServerScriptService = game:GetService("ServerScriptService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local server = ServerScriptService:WaitForChild("Server")
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local holder = Instance.new("Folder")
	holder.Name = "LoungeCheckBodies"
	holder.Parent = workspace
	local function makeModel(name: string, cf: CFrame, parent: any): any
		local m = Instance.new("Model")
		m.Name = name
		local root = Instance.new("Part")
		root.Name = if parent == holder then "HumanoidRootPart" else "Root"
		root.Size = Vector3.new(2, 2, 1)
		root.Anchored = true
		root.CanCollide = false
		root.Parent = m
		m.PrimaryPart = root
		m:PivotTo(cf)
		m.Parent = parent
		return m
	end
	local deps: Deps = {
		Service = (require :: any)(server:WaitForChild("Attractions"):WaitForChild("LoungeService")),
		LoungeClassic = (require :: any)(shared:WaitForChild("Attractions"):WaitForChild("LoungeClassic")),
		EconomyRules = (require :: any)(shared:WaitForChild("Economy"):WaitForChild("EconomyRules")),
		AlleyLayout = (require :: any)(shared:WaitForChild("Attractions"):WaitForChild("AlleyLayout")),
		makeBody = function(name: string, cf: CFrame): any
			return makeModel(name, cf, holder)
		end,
		makeModel = makeModel,
		folder = function(name: string): any
			local f = Instance.new("Folder")
			f.Name = name
			f.Parent = holder
			return f
		end,
	}
	local ok, result = pcall(LoungeFlow.play, deps)
	holder:Destroy()
	if not ok then
		return { ok = false, failures = { `error: {result}` }, numbers = {} }
	end
	return result
end

return LoungeFlow
