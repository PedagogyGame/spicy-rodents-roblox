--!strict
-- tests/isolated/lounge_seats.luau: cases for tests/unit/lounge_seats.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Sitting in THE GILDED ACORN (Server/Attractions/LoungeService, Client/World/SeatGetUp) on that fake engine: a
-- Seat with a "Sit" prompt on every place in LoungeClassic.SEATS; only a person the door let in sits, on a free
-- seat; a seated person is inside for the room's sweep whatever the pivot says; a drink is ordered and sipped
-- seated; the door gets a seated person up first; moving gets up (a lounge seat only), as jump does.
-- Owner D32 ("sitting down traps you and you can't actually leave... get back up with another button push"): the
-- server gets a seated person up (Server/World/SeatStand, PlayNet.StandUp) at the seat's stand spot; the seat key
-- pressed again (the nearest free stool's prompt) gets them up instead of moving them along, and the same press cannot
-- sit them down again for SeatRules.GRACE; the client asks with R, Space, the gamepad's A or Y, a move or the STAND
-- button, never while typing, at most once every SeatRules.REPEAT; a lawn chair's sitter gets up the same way; a
-- vehicle's seat (no stand spot) is never touched.
-- Interface: return function(t) (the spec shape)
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local LoungeClassic = require("@shared/Attractions/LoungeClassic")
local LoungeService = require("@server/Attractions/LoungeService")
local SeatGetUp = require("@client/World/SeatGetUp")
local SeatStand = require("@server/World/SeatStand")
local SeatRules = require("@shared/World/SeatRules")
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
			-- (as the engine: the weld gone, the Humanoid sits nowhere and the seat is free)
			local sat = self
			rawset(w, "Destroy", function(weld: any)
				weld.Parent = nil
				if hum.SeatPart == sat then
					hum.SeatPart = nil
				end
				if sat.Occupant == hum then
					sat.Occupant = nil
				end
			end)
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

	-- the body's feet in the venue frame and its facing (venue X, D)
	local function feetOf(svc: any, b: any): (number, number, number, number, number)
		local cf = b:GetPivot()
		local p = cf.Position
		local x, y, d = AlleyLayout.toLocal(svc.place, p.X, p.Y - 3, p.Z)
		local ahead = p + cf.LookVector
		local ax, _, ad = AlleyLayout.toLocal(svc.place, ahead.X, ahead.Y, ahead.Z)
		return x, y, d, ax - x, ad - d
	end

	t.test("D32: every seat's stand spot: its StandOffset is LoungeClassic.standSpot, on the floor", function()
		FakeEngine.with(function()
			local svc = svcWith({})
			for i, seat in svc.seats do
				local st = LoungeClassic.SEATS[i]
				local off = seat:GetAttribute(SeatRules.STAND_ATTRIBUTE)
				t.eq(typeof(off), "Vector3", st.id)
				local w = seat.CFrame:PointToWorldSpace(off)
				local x, y, d = AlleyLayout.toLocal(svc.place, w.X, w.Y, w.Z)
				local sx, sd = LoungeClassic.standSpot(st)
				t.near(x, sx, 1e-3, `{st.id} across`)
				t.near(d, sd, 1e-3, `{st.id} along`)
				t.near(y, 0, 1e-3, `{st.id}: on the floor`)
				t.truthy(LoungeClassic.inside(sx, 0, sd), `{st.id}: in the room`)
			end
			svc:stop()
		end)
	end)

	t.test("D32: the seat key again gets a seated person up (never along the bar); no sitting again at once", function()
		FakeEngine.with(function()
			local ann = { species = "human", pass = true }
			local svc = svcWith({ ann })
			ann.body = body("Ann", roblox.CFrame.new(svc:world(0, 3, -30)))
			svc:enter(ann)
			local hum = ann.body:FindFirstChildOfClass("Humanoid")
			for _, id in { "stool4", "booth2b1", "club3a", "armchair2" } do
				local i = indexOf(id)
				local st = LoungeClassic.SEATS[i]
				svc.seatPrompts[i].Triggered.fire(ann)
				t.eq(svc:seatOf(ann.body), i, `{id}: sat`)
				-- R again: the nearest free seat's prompt (a neighbour), pressed while seated
				local other = if i > 1 then i - 1 else i + 1
				svc.seatPrompts[other].Triggered.fire(ann)
				t.eq(svc:seatOf(ann.body), nil, `{id}: up, not moved to the next seat`)
				t.eq(hum.Sit, false)
				t.eq(svc.seats[i]:FindFirstChild("SeatWeld"), nil, `{id}: the weld is gone`)
				local x, y, d, fx, fd = feetOf(svc, ann.body)
				local sx, sd = LoungeClassic.standSpot(st)
				t.near(x, sx, 1e-3, `{id}: standing at its spot`)
				t.near(d, sd, 1e-3)
				t.near(y, 0, 1e-3, `{id}: feet on the floor`)
				t.near(fx, st.fx, 1e-3, `{id}: facing the seat's way`)
				t.near(fd, st.fd, 1e-3)
				t.truthy(svc:inRoom(ann.body) and svc:isInside(ann), `{id}: still in the room`)
				-- the same press reaching a seat's prompt a moment later does not sit them again
				svc.seatPrompts[other].Triggered.fire(ann)
				t.eq(svc:seatOf(ann.body), nil, `{id}: not straight back down`)
				svc._advance(SeatRules.GRACE + 0.01)
			end
			-- after the grace a seat's prompt sits them as ever
			svc.seatPrompts[indexOf("stool2")].Triggered.fire(ann)
			t.eq(svc:seatOf(ann.body), indexOf("stool2"))
			svc:stop()
		end)
	end)

	t.test(
		"D32: PlayNet.StandUp gets up from a lounge seat or a lawn chair; a vehicle's seat is never touched",
		function()
			FakeEngine.with(function()
				local ann = { species = "human", pass = true }
				local svc = svcWith({ ann })
				ann.body = body("Ann", roblox.CFrame.new(svc:world(0, 3, -30)))
				svc:enter(ann)
				local clock = 0
				local stand = SeatStand.handler({
					bodyOf = function(p: any): any?
						return p.body
					end,
					first = function(p: any): boolean
						return svc:stand(p)
					end,
					now = function(): number
						return clock
					end,
				})
				t.eq(stand(ann), false, "standing: nothing to do")
				clock += 1
				svc:sit(ann, indexOf("booth3a2"))
				t.truthy(stand(ann), "up from the booth")
				t.eq(svc:seatOf(ann.body), nil)
				local x, _, d = feetOf(svc, ann.body)
				t.near(x, -LoungeClassic.STAND_BOOTH_X, 1e-3, "out at the booth's open end")
				t.near(d, LoungeClassic.SEATS[indexOf("booth3a2")].d, 1e-3)
				-- asked again at once (a key held): not counted twice
				svc._advance(SeatRules.GRACE + 0.01)
				clock += 1
				svc:sit(ann, indexOf("club1b"))
				t.eq(stand(ann), true)
				clock += 0.01
				svc:sit(ann, indexOf("club1b"))
				t.eq(svc:seatOf(ann.body), nil, "inside the grace: not sat again")
				t.eq(stand(ann), false, "a second ask inside REPEAT / 2 is dropped")
				-- a lawn chair (Server/Items/ItemWorld: anchored, sat in by Seat:Sit, a stand spot in front)
				local bob = { species = "human" }
				bob.body = body("Bob", roblox.CFrame.new(0, 3, 0))
				local chair =
					FakeEngine.part("Seat", roblox.CFrame.new(10, 1, 10) * roblox.CFrame.Angles(0, math.pi / 2, 0))
				rawset(chair, "ClassName", "Seat")
				chair:SetAttribute(SeatRules.STAND_ATTRIBUTE, roblox.Vector3.new(0, -1.0, -2.3))
				local bhum = bob.body:FindFirstChildOfClass("Humanoid")
				bhum.SeatPart = chair
				local weld = FakeEngine.new("Weld", "SeatWeld")
				weld.Parent = chair
				clock += 1
				t.truthy(stand(bob), "up from the lawn chair")
				t.eq(bhum.Sit, false)
				t.eq(chair:FindFirstChild("SeatWeld"), nil, "its weld gone")
				local p = bob.body:GetPivot()
				local want = chair.CFrame:PointToWorldSpace(roblox.Vector3.new(0, -1.0, -2.3))
				t.near(
					(p.Position - (want + roblox.Vector3.new(0, 3, 0))).Magnitude,
					0,
					1e-3,
					"in front of it, standing"
				)
				-- a vehicle's DriverSeat: no stand spot, E's business (Server/Actors/DeviceService)
				local car = FakeEngine.part("DriverSeat", roblox.CFrame.new(50, 2, 50))
				rawset(car, "ClassName", "Seat")
				local cw = FakeEngine.new("Weld", "SeatWeld")
				cw.Parent = car
				bhum.SeatPart = car
				bhum.Sit = true
				clock += 1
				t.eq(stand(bob), false, "a driver is not got up here")
				t.eq(bhum.Sit, true)
				t.truthy(car:FindFirstChild("SeatWeld"), "the car's weld stays")
				svc:stop()
			end)
		end
	)

	t.test("D32 SeatGetUp: R, Space, the pad's A or Y, a move or STAND ask; never typing; once per REPEAT", function()
		FakeEngine.with(function()
			local b = body("Me", roblox.CFrame.new(0, 3, 0))
			local hum = b:FindFirstChildOfClass("Humanoid")
			local asks, toasts = 0, {}
			local clock = 0
			local h = SeatGetUp.start({
				current = function()
					return b
				end,
				heartbeat = false,
				move = function()
					return roblox.Vector3.new(0, 0, 0)
				end,
				request = function()
					asks += 1
				end,
				toast = function(text: string)
					table.insert(toasts, text)
				end,
				now = function(): number
					return clock
				end,
			})
			local gui = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
			local screen = gui and gui:FindFirstChild("SeatStand")
			t.truthy(screen, "the STAND button's screen")
			local key = function(name: string)
				FakeEngine.input("began", { KeyCode = (roblox.Enum.KeyCode :: any)[name] })
			end
			h.step()
			t.eq(screen.Enabled, false, "standing: no STAND")
			key("R")
			t.eq(asks, 0, "standing: R is the seat prompt's, nothing here")
			-- seated on a lounge seat
			local seat = FakeEngine.new("Seat", "Seat_stool1")
			seat:SetAttribute(LoungeClassic.SEAT_ATTRIBUTE, "stool1")
			seat:SetAttribute(SeatRules.STAND_ATTRIBUTE, roblox.Vector3.new(0, -2.46, 2.5))
			hum.SeatPart = seat
			h.step()
			t.eq(screen.Enabled, true, "seated: STAND shows")
			t.eq(#toasts, 1, "told how to get up")
			h.step()
			t.eq(#toasts, 1, "once per sitting")
			for _, name in { "R", "Space", "ButtonA", "ButtonY" } do
				clock += SeatRules.REPEAT + 0.01
				hum.Jump = false
				key(name)
				t.eq(hum.Jump, true, `{name}: the engine's jump too`)
			end
			t.eq(asks, 4, "each stand key asked")
			key("R")
			t.eq(asks, 4, "not twice inside REPEAT")
			clock += SeatRules.REPEAT + 0.01
			key("E")
			key("W")
			t.eq(asks, 4, "E (vehicles, drinks) and a bare W press are not stand keys (a move is, through step)")
			FakeEngine.uis().focused = true
			key("R")
			t.eq(asks, 4, "typing: nothing")
			FakeEngine.uis().focused = nil
			screen:FindFirstChild("Stand").Activated.fire()
			t.eq(asks, 5, "the STAND button")
			-- a lawn chair (a stand spot, no lounge id) is a seat one gets up from too; a car's is not
			local chair = FakeEngine.new("Seat", "Seat")
			chair:SetAttribute(SeatRules.STAND_ATTRIBUTE, roblox.Vector3.new(0, -1, -2.3))
			hum.SeatPart = chair
			clock += SeatRules.REPEAT + 0.01
			t.truthy(h.press("Space"), "a lawn chair")
			hum.SeatPart = FakeEngine.new("Seat", "DriverSeat")
			clock += SeatRules.REPEAT + 0.01
			t.eq(h.press("R"), false, "a car's seat: no")
			h.step()
			t.eq(screen.Enabled, false, "no STAND in a car (the vehicles' own button is UI/RideHint's)")
			h.stop()
			t.eq(gui:FindFirstChild("SeatStand"), nil, "the screen goes with it")
		end)
	end)
end
