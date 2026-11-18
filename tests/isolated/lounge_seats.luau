--!strict
-- tests/isolated/lounge_seats.luau: cases for tests/unit/lounge_seats.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Sitting in THE GILDED ACORN (Server/Attractions/LoungeService, Client/World/SeatGetUp) on that fake engine: a
-- Seat with a "Sit" prompt on every place in LoungeClassic.SEATS; only a person the door let in sits, on a free
-- seat; a seated person is inside for the room's sweep whatever the pivot says; a drink is ordered and sipped
-- seated; the door gets a seated person up first; moving gets up (a lounge seat only), as jump does.
-- Interface: return function(t) (the spec shape)
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local LoungeClassic = require("@shared/Attractions/LoungeClassic")
local LoungeService = require("@server/Attractions/LoungeService")
local SeatGetUp = require("@client/World/SeatGetUp")
local FakeEngine = require("@tests/lib/FakeEngine")
local roblox = require("@lune/roblox")

-- a body with a root and a Humanoid; Seat:Sit on the fake engine sets SeatPart / Occupant and a SeatWeld
local function body(name: string, cf: any): any
	local m = FakeEngine.model(name, cf, nil)
	local root = FakeEngine.part("HumanoidRootPart", cf, m)
	root.Size = roblox.Vector3.new(2, 2, 1)
	m.PrimaryPart = root
	local hum = FakeEngine.new("Humanoid", "Humanoid")
	hum.Parent = m
	return m
end

local function teachSeats(svc: any)
	for _, seat in svc.seats do
		rawset(seat, "Sit", function(self: any, hum: any)
			if hum.SeatPart then
				hum.SeatPart.Occupant = nil
			end
			hum.SeatPart = self
			self.Occupant = hum
			local w = FakeEngine.new("Weld", "SeatWeld")
			w.Parent = self
		end)
	end
end

local function town(log: { any }, bodies: { any }): any
	return {
		speciesOf = function(p: any): string?
			return p.species
		end,
		bodyOf = function(p: any): any?
			return p.body
		end,
		moveTo = function(p: any, cf: any)
			p.body:PivotTo(cf)
		end,
		evict = function(b: any, cf: any)
			b:PivotTo(cf)
		end,
		pass = {
			has = function(p: any): boolean
				return p.pass == true
			end,
			buy = function(): (boolean, string)
				return false, "no"
			end,
			offer = function(): (number, number, string)
				return 20, 5, "offer"
			end,
		},
		buy = function(_p: any, _id: string, deliver: () -> (boolean?, string?)): (boolean, string)
			local ok = deliver()
			return ok == true, if ok then "Here you are." else "no"
		end,
		tell = function(p: any, text: string)
			table.insert(log, { p, text })
		end,
		squirrels = function(): { any }
			return {}
		end,
		knockOut = function(_a: any) end,
		occupants = function(): { any }
			local out = {}
			for _, p in bodies do
				table.insert(out, { body = p.body, player = p })
			end
			return out
		end,
	}
end

local function svcWith(people: { any }, log: { any }?): any
	local now = 0
	local svc = LoungeService.new({
		town = town(log or {}, people),
		parent = FakeEngine.new("Folder", "P"),
		root = FakeEngine.new("Folder", "R"),
		now = function(): number
			return now
		end,
	})
	teachSeats(svc)
	svc._advance = function(dt: number)
		now += dt
		svc:step(dt)
	end
	return svc
end

local function indexOf(id: string): number
	for i, s in LoungeClassic.SEATS do
		if s.id == id then
			return i
		end
	end
	error("no seat " .. id)
end

return function(t)
	t.test(
		"a Seat and a Sit prompt (its own key, Door, near) on every place; never sat on by walking into it",
		function()
			FakeEngine.with(function()
				local svc = svcWith({})
				t.eq(#svc.seats, #LoungeClassic.SEATS)
				t.eq(#svc.seatPrompts, #LoungeClassic.SEATS)
				for i, seat in svc.seats do
					local st = LoungeClassic.SEATS[i]
					t.eq(seat.ClassName, "Seat")
					t.eq(seat.CanTouch, false, "no sitting by touch")
					t.eq(seat.CanCollide, false)
					t.eq(seat.Anchored, true)
					t.eq(seat:GetAttribute(LoungeClassic.SEAT_ATTRIBUTE), st.id)
					-- where it stands: the seat's top on the place, facing the way the sitter faces
					local top = seat.CFrame.Position + roblox.Vector3.new(0, 0.1, 0)
					local x, y, d = AlleyLayout.toLocal(svc.place, top.X, top.Y, top.Z)
					t.near(x, st.x, 1e-3)
					t.near(y, st.y, 1e-3)
					t.near(d, st.d, 1e-3)
					local p = svc.seatPrompts[i]
					t.eq(p.ActionText, "Sit")
					t.eq(p.ObjectText, (LoungeClassic.SEAT_WORDS :: any)[st.kind])
					t.eq(p:GetAttribute("Door"), true)
					t.eq(p:GetAttribute("Lounge"), "sit")
					t.eq(p.KeyboardKeyCode, (roblox.Enum.KeyCode :: any)[LoungeService.SEAT_KEY])
					t.eq(p.GamepadKeyCode, (roblox.Enum.KeyCode :: any)[LoungeService.SEAT_PAD])
					t.eq(p.MaxActivationDistance, LoungeService.SEAT_DISTANCE)
				end
				svc:stop()
			end)
		end
	)

	t.test("only a person the door let in sits, on a free seat; a taken seat's prompt is off", function()
		FakeEngine.with(function()
			local ann = { species = "human", pass = true }
			local bob = { species = "human", pass = true }
			local svc = svcWith({})
			ann.body = body("Ann", roblox.CFrame.new(svc:world(0, 3, -30)))
			bob.body = body("Bob", roblox.CFrame.new(svc:world(0, 3, -30)))
			local stool = indexOf("stool4")
			t.eq((svc:sit(ann, stool)), false, "outside: no seat")
			svc:enter(ann)
			svc:enter(bob)
			t.truthy(svc:sit(ann, stool))
			t.eq(svc:seatOf(ann.body), stool)
			t.eq(svc:counts().seated, 1)
			local ok, why = svc:sit(bob, stool)
			t.eq(ok, false)
			t.eq(why, "taken")
			svc._advance(LoungeService.TICK)
			t.eq(svc.seatPrompts[stool].Enabled, false, "taken: no prompt")
			t.truthy(svc:sit(bob, indexOf("booth1a1")), "another seat")
			-- Ann gets up (the engine clears the seat): its prompt comes back
			ann.body:FindFirstChildOfClass("Humanoid").SeatPart = nil
			svc.seats[stool].Occupant = nil
			svc._advance(LoungeService.TICK)
			t.eq(svc.seatPrompts[stool].Enabled, true)
			-- the prompt itself sits the one who pressed it
			svc.seatPrompts[indexOf("club1a")].Triggered.fire(ann)
			t.eq(svc:seatOf(ann.body), indexOf("club1a"))
			-- a squirrel (never let in anyway) does not sit
			local sq = { species = "squirrel", body = body("Sq", roblox.CFrame.new(svc:world(0, 3, 0))) }
			t.eq((svc:sit(sq, indexOf("armchair1"))), false)
			svc:stop()
		end)
	end)

	t.test("a seated person is inside: the sweep and the misses never put them out, whatever the pivot", function()
		FakeEngine.with(function()
			local ann = { species = "human", pass = false } -- let in once; the sweep would put a passless one out
			local people = { ann }
			local log = {}
			local svc = svcWith(people, log)
			ann.body = body("Ann", roblox.CFrame.new(svc:world(0, 3, -30)))
			ann.pass = true
			svc:enter(ann)
			ann.pass = false
			svc:sit(ann, indexOf("booth4b2"))
			-- the seated pivot, low on a booth: put it anywhere odd (below the floor line the walls are read at)
			ann.body:PivotTo(roblox.CFrame.new(svc:world(23.5, -2, 6)))
			t.truthy(svc:inRoom(ann.body), "seated: in the room")
			for _ = 1, 2 * LoungeService.MISSES + 2 do
				svc._advance(LoungeService.TICK)
			end
			t.truthy(svc:isInside(ann), "still let in")
			t.eq(svc:seatOf(ann.body), indexOf("booth4b2"), "still seated")
			for _, l in log do
				t.neq(l[2], LoungeClassic.WORDS.membersOnly, "never put out")
			end
			-- every seat's own place is inside the room for a standing body too
			for _, st in LoungeClassic.SEATS do
				t.truthy(LoungeClassic.inside(st.x, st.y, st.d), st.id)
			end
			svc:stop()
		end)
	end)

	t.test("a drink is ordered and sipped seated; the door gets a seated person up before moving them", function()
		FakeEngine.with(function()
			local ann = { species = "human", pass = true }
			local svc = svcWith({ ann })
			ann.body = body("Ann", roblox.CFrame.new(svc:world(0, 3, -30)))
			svc:enter(ann)
			svc:sit(ann, indexOf("stool1"))
			local ok = svc:order(ann, "coffee")
			t.truthy(ok, "ordered from the stool")
			t.truthy(ann.body:FindFirstChild("LoungeDrink"), "in the hand")
			svc._advance(LoungeClassic.SIP_EVERY + 0.01)
			t.eq(svc.drinks[ann].sips, LoungeClassic.SIPS - 1, "sipped seated")
			t.eq(svc:seatOf(ann.body), indexOf("stool1"), "still seated after a sip")
			-- leave: up first, then out on the landing
			local hum = ann.body:FindFirstChildOfClass("Humanoid")
			local seat = svc.seats[indexOf("stool1")]
			t.truthy(seat:FindFirstChild("SeatWeld"))
			t.truthy(svc:leave(ann))
			t.eq(hum.Sit, false, "got up")
			t.eq(seat:FindFirstChild("SeatWeld"), nil, "the weld is gone, so the body can move")
			local p = ann.body:GetPivot().Position
			local _, _, d = AlleyLayout.toLocal(svc.place, p.X, p.Y, p.Z)
			t.near(d, LoungeClassic.DOOR_OUTSIDE.d, 1e-3, "on the landing")
			svc:stop()
		end)
	end)

	-- ProximityPrompt's one per key: of the enabled prompts within reach that share a key, the nearest shows
	t.test("standing at the bar, the drinks' key shows a drink, never a stool; seated on a stool, too", function()
		FakeEngine.with(function()
			local svc = svcWith({})
			local prompts = {}
			for _, post in svc.counterPosts do
				local att = post:FindFirstChildOfClass("Attachment")
				table.insert(
					prompts,
					{ p = att:FindFirstChildOfClass("ProximityPrompt"), at = post.Position, drink = true }
				)
			end
			for i, seat in svc.seats do
				table.insert(prompts, { p = svc.seatPrompts[i], at = seat.Position, drink = false })
			end
			-- a property the fake engine leaves unset has the engine's default (Enabled; the gamepad's X)
			local DEFAULTS = { Enabled = true, GamepadKeyCode = roblox.Enum.KeyCode.ButtonX }
			local function prop(p: any, name: string): any
				local v = p[name]
				return if v == nil then (DEFAULTS :: any)[name] else v
			end
			local drinkKey = prop(prompts[1].p, "KeyboardKeyCode")
			local drinkPad = prop(prompts[1].p, "GamepadKeyCode")
			local seatKey = (roblox.Enum.KeyCode :: any)[LoungeService.SEAT_KEY]
			t.truthy(drinkKey ~= seatKey, "the seats' key is not the drinks'")
			t.truthy(drinkPad ~= (roblox.Enum.KeyCode :: any)[LoungeService.SEAT_PAD], "nor on the gamepad")
			-- what shows for a key at a root: the nearest enabled prompt in reach sharing it
			local function shown(root: any, field: string, key: any): any?
				local best, bd = nil, math.huge
				for _, q in prompts do
					local dist = (q.at - root).Magnitude
					if
						prop(q.p, "Enabled")
						and prop(q.p, field) == key
						and dist <= q.p.MaxActivationDistance
						and dist < bd
					then
						best, bd = q, dist
					end
				end
				return best
			end
			-- every standing spot in front of the bar (a body's root 3 over the floor), not inside a stool
			local spots, drinks, stools = 0, 0, 0
			for d = 9.0, 12.31, 0.3 do
				for x = -12, 12 do
					local clear = true
					for _, st in LoungeClassic.SEATS do
						if st.kind == "stool" and math.abs(st.x - x) < 1.9 and math.abs(st.d - d) < 1.9 then
							clear = false
						end
					end
					if clear then
						spots += 1
						local root = svc:world(x, 3, d)
						for field, key in { KeyboardKeyCode = drinkKey, GamepadKeyCode = drinkPad } do
							local q = shown(root, field, key)
							t.truthy(q == nil or q.drink, `({x}, {d}) {field}: a drink or nothing`)
							if q and field == "KeyboardKeyCode" then
								drinks += 1
							end
						end
						if shown(root, "KeyboardKeyCode", seatKey) then
							stools += 1
						end
					end
				end
			end
			t.truthy(drinks > spots * 0.6, `a drink offered at {drinks} of {spots} spots`)
			t.truthy(stools > spots * 0.6, `a stool offered at {stools} of {spots} spots`)
			-- seated on each stool (hips a stud over the seat; its own prompt off): a drink shows
			for i, st in LoungeClassic.SEATS do
				if st.kind == "stool" then
					svc.seatPrompts[i].Enabled = false
					local q = shown(svc:world(st.x, st.y + 1, st.d), "KeyboardKeyCode", drinkKey)
					t.truthy(q and q.drink, `{st.id}: a drink within reach`)
					svc.seatPrompts[i].Enabled = true
				end
			end
			svc:stop()
		end)
	end)

	t.test("SeatGetUp: moving gets up from a lounge seat only, past the stick's rest", function()
		FakeEngine.with(function()
			local b = body("Me", roblox.CFrame.new(0, 3, 0))
			local hum = b:FindFirstChildOfClass("Humanoid")
			local v = roblox.Vector3.new(0, 0, 0)
			local h = SeatGetUp.start({
				current = function()
					return b
				end,
				heartbeat = false,
				move = function()
					return v
				end,
			})
			t.eq(h.step(), false, "standing: nothing")
			local seat = FakeEngine.new("Seat", "Seat_stool1")
			seat:SetAttribute(LoungeClassic.SEAT_ATTRIBUTE, "stool1")
			hum.SeatPart = seat
			t.eq(h.step(), false, "seated, still")
			v = roblox.Vector3.new(0.1, 0, 0.1)
			t.eq(h.step(), false, "a stick at rest is not a move")
			v = roblox.Vector3.new(0, 0, -1)
			t.eq(h.step(), true, "W gets up")
			t.eq(hum.Jump, true)
			-- a car's seat (no lounge attribute) is left alone
			hum.Jump = false
			hum.SeatPart = FakeEngine.new("VehicleSeat", "DriveSeat")
			t.eq(h.step(), false)
			t.eq(hum.Jump, false)
			h.stop()
		end)
	end)
end
