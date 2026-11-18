--!strict
-- The live squirrel validator against the third adversarial review (2026-11-18): the pin no other path may undo, a
-- claimed rail at a gate, an honest body taken high in the air, the place before a move under a slow link's round trip,
-- and a pin dropped while the body rides. Each cheat must be snapped; each honest case must not.
local fs = require("@lune/fs")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local BodyPin = require("@server/Movement/BodyPin")
local LiveRig = require("@tests/lib/LiveRig")
local Rng = require("@tests/cheat/Rng")

type State = SquirrelMotor.State

local town = LiveRig.town()

local function still(_now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
	return SquirrelMotor.idleInput(0)
end

-- a body as the engine has it, enough for BodyPin: a root (Anchored, its network owner, attributes; an anchored part's
-- owner cannot be set, as in the engine) and the body's own attributes (Ride)
local function fakeBody(): (any, any)
	local root: any = { Anchored = false, owner = "client", attrs = {}, Parent = true }
	function root.GetAttribute(self: any, k: string): any
		return self.attrs[k]
	end
	function root.SetAttribute(self: any, k: string, v: any)
		self.attrs[k] = v
	end
	function root.SetNetworkOwner(self: any, p: any)
		if self.Anchored then
			error("Network Ownership API cannot be called on Anchored parts")
		end
		self.owner = p or "server"
	end
	local body: any = { PrimaryPart = root, attrs = {} }
	function body.GetAttribute(self: any, k: string): any
		return self.attrs[k]
	end
	return body, root
end

-- the server files whose lines let a body go (an Anchored set to anything but true, a SetNetworkOwner to anyone but the
-- server), each reviewed: none of them may touch a squirrel body the validator keeps
local LET_GO = {
	["src/server/Movement/BodyPin.luau"] = "the rule itself: the pin's own release, and letGo / giveTo that ask first",
	["src/server/Actors/ActorService.luau"] = "a body built, and its mode at the hand-off (the pin follows in that step)",
	["src/server/Actors/Possession.luau"] = "the hand-off's network owner (the pin follows in that step)",
	["src/server/Actors/DeviceService.luau"] = "cars and drones, never a squirrel's body",
	["src/server/AI/Puppets.luau"] = "the AI puppets' limbs",
	["src/server/Avatar/AvatarBlendService.luau"] = "an accessory's handle",
	["src/server/Assets/PeopleArt.luau"] = "the townspeople's dress at boot",
	["src/server/Items/ItemWorld.luau"] = "items",
	["src/server/Items/CornerStore.luau"] = "the store's props",
	["src/server/Minigames/BowlingLane.luau"] = "bowling balls",
}

local function letGoLines(src: string): { string }
	local found = {}
	for line in string.gmatch(src, "[^\n]+") do
		local code = string.match(line, "^%s*(.-)%s*$") :: string
		if string.sub(code, 1, 2) ~= "--" then
			local rhs = string.match(code, "%.Anchored%s*=%s*([^=].*)$")
			local owner = string.match(code, ":SetNetworkOwner%((.-)%)")
			if (rhs and string.sub(rhs, 1, 4) ~= "true") or (owner and owner ~= "nil") then
				table.insert(found, code)
			end
		end
	end
	return found
end

local function luauFiles(dir: string, into: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			luauFiles(path, into)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(into, path)
		end
	end
end

return function(t)
	-- 1. THE PIN: ONLY THE VALIDATOR'S OWN UNPIN HANDS A KEPT BODY BACK ----------------------------------------------------
	t.test(
		"every server line that lets a body go is in a reviewed file; Boot/Game and the sky lift ask BodyPin",
		function()
			local files = {}
			luauFiles("src/server", files)
			local seen = {}
			for _, path in files do
				local lines = letGoLines(fs.readFile(path))
				if #lines > 0 then
					seen[path] = true
					t.truthy(LET_GO[path], `{path} lets a body go ({lines[1]}): route it through Movement/BodyPin`)
				end
			end
			for path in LET_GO do
				t.truthy(seen[path], `{path} is listed but lets nothing go (take it off the list)`)
			end
			local lift = fs.readFile("src/server/Rides/SkyLiftService.luau")
			t.eq(#letGoLines(lift), 0, "the sky lift lets go only through BodyPin")
			local _, asks = string.gsub(lift, "BodyPin%.letGo%(", "")
			t.eq(asks, 2, "the ride's end and the telescope's look ask BodyPin.letGo")
			t.truthy(
				string.find(lift, "BodyPin.giveTo(body.PrimaryPart, player)", 1, true),
				"giveBack asks BodyPin.giveTo"
			)
			t.eq(#letGoLines(fs.readFile("src/server/Boot/Game.luau")), 0, "Boot/Game lets go only through BodyPin")
		end
	)

	t.test("BodyPin: a kept body is let go by nothing but the pin's own release", function()
		local body, root = fakeBody()
		BodyPin.pin(root)
		t.eq(root.Anchored, true)
		t.eq(root.owner, "server")
		t.eq(BodyPin.kept(root), true)
		t.eq(BodyPin.letGo(root, false), false, "the telescope's look or a ride's end: refused")
		t.eq(root.Anchored, true)
		t.eq(BodyPin.giveTo(root, "player"), false, "the sky lift's giveBack: refused")
		t.eq(root.owner, "server")
		body.attrs.Ride = "1/2"
		t.eq(BodyPin.unpin(root, "player", true), false, "not while it rides")
		t.eq(root.Anchored, true)
		body.attrs.Ride = nil
		t.eq(BodyPin.unpin(root, "player", false), true, "the pin's own release")
		t.eq(root.Anchored, false)
		t.eq(root.owner, "player")
		t.eq(BodyPin.kept(root), false)
		-- a body nobody keeps is let go as before
		local _b2, r2 = fakeBody()
		r2.Anchored = true
		t.eq(BodyPin.letGo(r2, false), true)
		t.eq(r2.Anchored, false)
		t.eq(BodyPin.giveTo(r2, "player"), true)
		t.eq(r2.owner, "player")
	end)

	t.test("BodyPin.engine: a hold's timer never hands back a body pinned since (the same body taken again)", function()
		local body, root = fakeBody()
		local actor: any = { id = "a", body = body, possessions = 1 }
		local driver: any = "player"
		local pinned = false
		local timers = {}
		local engine = BodyPin.engine({
			heldBy = function(_id: any): (any?, any?)
				return actor, driver
			end,
			isPinned = function(_id: any): boolean
				return pinned
			end,
			place = function(_body: any, _x: number, _y: number, _z: number) end,
			tell = function(_driver: any, _msg: any) end,
			delay = function(_s: number, fn: () -> ())
				table.insert(timers, fn)
			end,
		})
		-- 1. a plain hold: given back when it ends
		engine.hold("a", 0, 0, 0, 2)
		t.eq(root.Anchored, true)
		table.remove(timers, 1)()
		t.eq(root.Anchored, false, "given back")
		t.eq(root.owner, "player")
		-- 2. held, then the player picks another body and this one again (a new hand-off, pinned) before it ends
		engine.hold("a", 0, 0, 0, 2)
		actor.possessions += 1
		pinned = true
		t.eq(engine.pin("a", true), true)
		table.remove(timers, 1)()
		t.eq(root.Anchored, true, "the hold's timer leaves the pinned body anchored")
		t.eq(root.owner, "server")
		-- (and with the same hand-off token, the pin alone keeps it: the validator says pinned, the root is marked)
		actor.possessions -= 1
		engine.hold("a", 0, 0, 0, 2)
		table.remove(timers, 1)()
		t.eq(root.Anchored, true, "still the server's")
		pinned = false
		root.attrs[BodyPin.C.ATTR] = true
		engine.hold("a", 0, 0, 0, 2)
		table.remove(timers, 1)()
		t.eq(root.Anchored, true, "a root marked kept is never let go by a hold")
		-- 3. two holds back to back: the first one's timer does not give back the second
		t.eq(engine.pin("a", false), true, "the pin's own release")
		t.eq(root.Anchored, false)
		engine.hold("a", 0, 0, 0, 2)
		engine.hold("a", 0, 0, 0, 2)
		table.remove(timers, 1)()
		t.eq(root.Anchored, true, "the second hold still has it")
		table.remove(timers, 1)()
		t.eq(root.Anchored, false, "given back by the second")
		-- 4. the pin's release, refused while it rides; a released body back with the AI loses the mark
		engine.pin("a", true)
		body.attrs.Ride = "1/2"
		t.eq(engine.pin("a", false), false, "kept while it rides")
		t.eq(root.Anchored, true)
		body.attrs.Ride = nil
		t.eq(engine.pin("a", false), true)
		t.eq(root.Anchored, false)
		engine.pin("a", true)
		driver = nil
		t.eq(engine.pin("a", false), true, "back to the AI")
		t.eq(BodyPin.kept(root), false, "no longer marked")
	end)

	t.test(
		"cheat: the pin undone by a path the validator does not know of, never a packet: taken again, snapped",
		function()
			local s0 = town.openStart()
			local rig
			local high, out = 0, 0
			rig = LiveRig.new({
				world = town.noWalls,
				vworld = town.vworld,
				link = { latency = 0.1, jitter = 0.05, loss = 0.02 },
				seed = 41,
				silent = function(_now: number): boolean
					return true
				end,
				rootCheat = function(p: any, now: number)
					local a = now * 100 / 150
					p.x = math.cos(a) * 150
					p.z = math.sin(a) * 150
					p.y = s0.y + (if (now % 10) < 5 then 60 else 0)
				end,
			})
			rig:possess(s0, still)
			-- (Boot/Game's old hold timer: root.Anchored = false and the driver its owner, the validator none the wiser)
			rig:at(1.1, function()
				rig.server.pinned = false
				rig.server.unpinnedAt = 1.1
			end)
			for k = 1, 119 do
				rig:at(k * 0.5, function()
					local root = rig.server.root
					if root.y > s0.y + 30 then
						high += 1
					end
					if math.sqrt((root.x - s0.x) ^ 2 + (root.z - s0.z) ^ 2) > 10 then
						out += 1
					end
				end)
			end
			rig:run(60)
			local r = rig:result()
			print(
				`      {LiveRig.describe("pin undone, never a packet", r)}; the server's body high {high}, away {out}`
			)
			t.truthy((r.reasons.pin or 0) >= 1, "snapped back where it is kept")
			t.eq(rig.server.pinned, true, "taken again")
			t.truthy(out <= 1, `the server's body stays where it is kept ({out} samples away)`)
			t.eq(high, 0, "never up in the air")
		end
	)

	-- 5. A PIN NOT DROPPED WHILE THE BODY RIDES ----------------------------------------------------------------------------
	t.test(
		"honest: the first packet passes the gate as the body boards the sky lift; off it, played on: 0 snaps",
		function()
			local rng = Rng.new(17)
			local s0 = town.openStart()
			local rig = LiveRig.new({
				world = town.world,
				vworld = town.vworld,
				link = { latency = 0.05, jitter = 0, loss = 0 },
				seed = 17,
			})
			-- (the board lands in the moment between the first packet and the next watch: the packet passes the gate while
			-- the body rides, and the engine will not hand it back then)
			local boarded = false
			local packet = rig.movement.packet
			rig.movement.packet = function(self: any, ...: any): any
				if not boarded then
					boarded = true
					rig:board()
				end
				return packet(self, ...)
			end
			rig:possess(s0, town.driven(rng))
			local pinnedOnLift = nil
			rig:at(8, function()
				pinnedOnLift = rig.movement:isPinned(`squirrel_{rig.server.actor}`)
				rig:alight(s0.x + 20, s0.y, s0.z)
			end)
			rig:run(30)
			local r = rig:result()
			print(`      {LiveRig.describe("boarded as the first packet passed", r)}`)
			t.eq(pinnedOnLift, true, "kept pinned while it rode")
			t.eq(rig.server.pinned, false, "handed back off the lift")
			t.eq(rig.movement:isPinned(`squirrel_{rig.server.actor}`), false)
			t.eq(r.snaps, 0, "no snap")
			t.truthy(r.accepted > 300, `packets judged ({r.accepted})`)
		end
	)

	-- 4. THE PLACE BEFORE A MOVE, WHATEVER THE ENGINE SAYS THE ROUND TRIP IS -----------------------------------------------
	-- After each Reset the root is kept 250 studs off, near nothing, for as long as the round trip read would cover: a
	-- round trip of 6 s (GetNetworkPing reads up to 10) buys no more room or time than one of 1 s (C.PING_MAX)
	for _, ping in { 0.2, 2, 6, 10 } do
		t.test(`cheat: the root 250 studs off after each Reset, the round trip read {ping} s: snapped`, function()
			local s0 = town.openStart()
			local resetAt = {}
			local rig
			rig = LiveRig.new({
				world = town.noWalls,
				vworld = town.vworld,
				link = { latency = 0.1, jitter = 0.05, loss = 0.0 },
				seed = 5,
				pingOf = function(_t: number): number
					return ping
				end,
				rootCheat = function(p: any, now: number)
					for _, at in resetAt do
						if now > at + 0.3 and now < at + 2 * ping + 0.8 then
							p.x = s0.x + 250
						end
					end
				end,
			})
			rig:possess(s0, still)
			for k = 1, 4 do
				local at = 5 + (k - 1) * 15
				rig:at(at, function()
					table.insert(resetAt, at)
					rig:teleport(s0.x, s0.y, s0.z + 40, "reset")
				end)
			end
			rig:run(65)
			local r = rig:result()
			print(`      {LiveRig.describe(`ping {ping}`, r)}`)
			t.truthy((r.reasons.drift or 0) >= 4, `snapped for drift after every Reset ({r.reasons.drift or 0})`)
		end)
	end
end
