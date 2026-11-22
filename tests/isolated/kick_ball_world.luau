--!strict
-- tests/isolated/kick_ball_world.luau: cases for tests/unit/kick_ball.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Server/Items/ItemWorld on that fake engine with the real Items/Inventory and the real Reputation/ReputationService:
-- the corner store's kick ball (owner D30) kicked and thrown, a hard hit knocking a person a little and reported, a soft
-- one caught as before, the thrower never hit by their own ball, one of the computer's people flinching, F by a ball on
-- the ground, and three hard hits in a short while costing the thrower reputation once.
-- Interface: return function(t) (the spec shape)
local FakeEngine = require("@tests/lib/FakeEngine")
local ItemWorld = require("@server/Items/ItemWorld")
local Inventory = require("@server/Items/Inventory")
local ReputationService = require("@server/Reputation/ReputationService")
local KickBall = require("@shared/Items/KickBall")
local roblox = require("@lune/roblox")

type Rig = {
	world: any,
	inv: any,
	rep: any,
	pip: any,
	sam: any,
	kim: any,
	aiBody: any,
	told: { [string]: { string } },
	clock: number,
}

local AI_ID = 50

local function rig(): Rig
	FakeEngine.events({ "Touched" })
	-- selene: allow(deprecated)
	local env = getfenv(0) :: any
	env.RaycastParams = {
		new = function(): any
			return {}
		end,
	}
	env.OverlapParams = env.RaycastParams
	env.Color3 = roblox.Color3
	env.PhysicalProperties = roblox.PhysicalProperties
	local Players = game:GetService("Players")
	rawset(game:GetService("Debris"), "AddItem", function() end)
	rawset(workspace, "GetServerTimeNow", function()
		return 77
	end)
	rawset(workspace, "Gravity", 196.2)
	rawset(workspace, "Raycast", function(_self: any, from: any, _dir: any, _params: any): any
		return { Position = roblox.Vector3.new(from.X, 0, from.Z) }
	end)
	rawset(workspace, "GetPartBoundsInRadius", function(): { any }
		return {}
	end)
	local r: Rig = { told = {}, clock = 1000 } :: any
	local byBody: { [any]: any } = {}
	local actors: { [any]: any } = {}
	local byTownId: { [any]: any } = {}
	local worldActors: { any } = {}
	rawset(Players, "GetPlayers", function(self: any): { any }
		local out = {}
		for _, c in self:GetChildren() do
			if c.ClassName == "Player" and c.Name ~= "LocalPlayer" then
				table.insert(out, c)
			end
		end
		return out
	end)
	rawset(Players, "GetPlayerFromCharacter", function(_self: any, body: any): any
		return if body then byBody[body] else nil
	end)
	-- a person standing at (x, z), facing -Z (the CFrame's own look), their root 3 studs over the ground
	local function person(name: string, id: number, x: number, z: number): any
		local p = FakeEngine.new("Player", name)
		rawset(p, "UserId", id)
		rawset(p, "DisplayName", name)
		p.Parent = Players
		FakeEngine.new("Backpack", "Backpack").Parent = p
		local body = FakeEngine.model(name .. "Body", roblox.CFrame.new(x, 3, z), workspace)
		local root = FakeEngine.part("HumanoidRootPart", roblox.CFrame.new(x, 3, z), body)
		rawset(root, "FindFirstAncestorOfClass", function(_self: any, _class: string): any
			return body
		end)
		body.PrimaryPart = root
		byBody[body] = p
		rawset(p, "Character", body)
		local actor = { species = "human", body = body }
		actors[p] = actor
		byTownId[id] = actor
		table.insert(worldActors, { id = id, species = "human", x = x, y = 3, z = z })
		r.told[name] = {}
		return p
	end
	local function tool(name: string, attrs: { [string]: any }): any
		local t = FakeEngine.new("Tool", name)
		for k, v in attrs do
			t:SetAttribute(k, v)
		end
		local h = FakeEngine.part("Handle", roblox.CFrame.new(0, 3, 0), t)
		rawset(h, "SetNetworkOwner", function() end)
		rawset(h, "AssemblyMass", 1)
		return t
	end
	r.inv = Inventory.new({
		makeTool = function(player: any, itemId: string): any?
			local bp = player:FindFirstChildOfClass("Backpack")
			if bp == nil or player.Parent ~= Players then
				return nil
			end
			local t = tool(itemId, { ItemId = itemId })
			t.Parent = bp
			return t
		end,
		toolsOf = function(player: any, itemId: string): { any }
			local out = {}
			for _, holder in { player:FindFirstChildOfClass("Backpack"), player.Character } do
				for _, c in (if holder then holder:GetChildren() else {}) :: { any } do
					if c:IsA("Tool") and c:GetAttribute("ItemId") == itemId then
						table.insert(out, c)
					end
				end
			end
			return out
		end,
	})
	-- Pip throws toward -Z; Sam stands 10 ahead of him, Kim off to the side, one of the computer's people 20 ahead
	r.pip = person("Pip", 11, 0, 0)
	r.sam = person("Sam", 12, 0, -10)
	r.kim = person("Kim", 13, 30, 0)
	r.aiBody = FakeEngine.model("AiBody", roblox.CFrame.new(0, 3, -20), workspace)
	byTownId[AI_ID] = { species = "human", body = r.aiBody }
	table.insert(worldActors, { id = AI_ID, species = "human", x = 0, y = 3, z = -20 })
	r.rep = ReputationService.new({
		now = function(): number
			return r.clock
		end,
		tell = function(p: any, words: string)
			table.insert(r.told[p.Name], words)
		end,
	})
	r.world = ItemWorld.start({
		inventory = r.inv,
		possession = {
			actorOf = function(_self: any, p: any): any
				return if p.Character then actors[p] else nil
			end,
		},
		runtime = { world = { actors = worldActors, brains = {} }, byTownId = byTownId },
		fire = function(p: any, msg: any)
			table.insert(r.told[p.Name], msg.text)
		end,
		heartbeat = false,
		now = function(): number
			return r.clock
		end,
		reputation = r.rep,
		lendTool = function(player: any, itemId: string, ownerName: string, use: (any?) -> ()): any?
			local bp = player:FindFirstChildOfClass("Backpack")
			if bp == nil then
				return nil
			end
			local lent = tool(`{ownerName}'s {itemId}`, { LentItem = itemId, LentFrom = ownerName })
			lent.Activated:Connect(function()
				use(nil)
			end)
			lent.Parent = bp
			return lent
		end,
	})
	return r
end

local function lying(): any?
	local folder = workspace:FindFirstChild("CornerStoreItems")
	return folder and folder:FindFirstChild("Thrown_kick_ball")
end

local function ballOf(model: any): any
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			return d
		end
	end
	error("no part")
end

local function promptOf(model: any): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" then
			return d
		end
	end
	error("no prompt")
end

local function last(r: Rig, name: string): string?
	local list = r.told[name]
	return list[#list]
end

-- Pip sends his ball: a press held `windup` seconds (nil: a click)
local function send(r: Rig, windup: number?): any
	r.world.service:state(r.pip, "kick_ball").last = -1e9 -- (past the cooldown)
	assert(r.world.use(r.pip, "kick_ball", if windup then { windup = windup } else nil), "Pip sent the ball")
	return ballOf(lying())
end

-- the ball flies on to (x, y, z) at `speed` toward -Z, and the frame's check runs
local function flyTo(r: Rig, ball: any, x: number, y: number, z: number, speed: number)
	ball.CFrame = roblox.CFrame.new(x, y, z)
	ball.AssemblyLinearVelocity = roblox.Vector3.new(0, 0, -speed)
	r.world.sweep()
end

return function(t)
	t.test("in hand: a click kicks it low and fast from the feet; a held press throws it from the hand", function()
		FakeEngine.with(function()
			local r = rig()
			r.inv.add(r.pip, "kick_ball")
			local kicked = send(r, nil)
			t.near(kicked.AssemblyLinearVelocity.Magnitude, KickBall.C.kickSpeed, 1e-4)
			local kickedY = kicked.Position.Y
			t.truthy(kicked.AssemblyLinearVelocity.Z < 0, "the way Pip faces")
			t.truthy(kicked.CustomPhysicalProperties ~= nil, "a light, bouncy rubber ball")
			t.eq(r.inv.count(r.pip, "kick_ball"), 0, "in the air")
			t.eq(promptOf(lying()).ObjectText, "Pip's kick ball", "still Pip's")
			promptOf(lying()).Triggered.fire(r.pip)
			t.eq(r.inv.count(r.pip, "kick_ball"), 1, "picked back up")
			local thrown = send(r, 1.2)
			t.near(thrown.AssemblyLinearVelocity.Magnitude, KickBall.C.throwMax, 1e-4)
			t.near(thrown.Position.Y - kickedY, 3.7, 1e-4, "a kick leaves from the foot, a throw from the hand")
		end)
	end)

	t.test(
		"a hard hit knocks a person a little (never a fall), once per flight; the thrower hears nothing yet",
		function()
			FakeEngine.with(function()
				local r = rig()
				r.inv.add(r.pip, "kick_ball")
				local ball = send(r, nil)
				flyTo(r, ball, 0, 1, -12, 45) -- through Sam at z = -10
				local body = r.sam.Character
				t.truthy(body:GetAttribute("Knock") ~= nil, "knocked")
				t.eq(body:GetAttribute("KnockFall"), false, "a stagger, never a fall")
				t.eq(body:GetAttribute("KnockAt"), 77)
				local k = body:GetAttribute("Knock")
				t.near(k.Y, KickBall.C.staggerSecs, 1e-6)
				t.truthy(k.Z < 0, "along the ball's way")
				t.eq(last(r, "Sam"), "Ouch! A ball hit you.")
				body:SetAttribute("KnockAt", nil)
				flyTo(r, ball, 0, 1, -9, 45) -- (back through Sam on a bounce)
				t.eq(body:GetAttribute("KnockAt"), nil, "the same flight does not hit Sam twice")
				t.eq(r.rep.get(r.pip), 0, "one hard hit is an accident")
				-- on to one of the computer's people: the arms come up
				flyTo(r, ball, 0, 1, -22, 45)
				t.eq(r.aiBody:GetAttribute("Gesture"), "flinch")
			end)
		end
	)

	t.test("soft balls are caught, never knock; the thrower is never hit by their own ball", function()
		FakeEngine.with(function()
			local r = rig()
			r.inv.add(r.pip, "kick_ball")
			local ball = send(r, 0.5) -- a gentle wind-up
			flyTo(r, ball, 0, 2, -12, 15)
			t.eq(r.sam.Character:GetAttribute("Knock"), nil, "too soft to knock")
			ball.Touched.fire(r.sam.Character.PrimaryPart)
			t.eq(lying(), nil, "Sam caught it")
			t.truthy(string.find(last(r, "Sam") or "", "Caught Pip's kick ball", 1, true) ~= nil)
			-- a hard ball's Touched is no catch
			r.inv.add(r.pip, "kick_ball")
			local hard = send(r, nil)
			hard.AssemblyLinearVelocity = roblox.Vector3.new(0, 0, -45)
			hard.Touched.fire(r.kim.Character.PrimaryPart)
			t.truthy(lying() ~= nil, "a hard ball knocks, it is not caught")
			-- back through Pip himself
			hard.CFrame = roblox.CFrame.new(0, 1, -3)
			r.world.sweep()
			flyTo(r, hard, 0, 1, 3, 45)
			t.eq(r.pip.Character:GetAttribute("Knock"), nil, "never by your own ball")
		end)
	end)

	t.test(
		"F by a ball on the ground: kicked if in reach and in front, still its buyer's, its ground time again",
		function()
			FakeEngine.with(function()
				local r = rig()
				r.inv.add(r.pip, "kick_ball")
				local ball = send(r, nil)
				-- it comes to rest just in front of Kim (who faces -Z)
				ball.CFrame = roblox.CFrame.new(30, 0.5, -2)
				ball.AssemblyLinearVelocity = roblox.Vector3.new(0, 0, 0)
				r.world.sweep()
				r.clock += 50
				t.truthy(r.world.kickLoose(r.kim), "kicked")
				t.near(ball.AssemblyLinearVelocity.Magnitude, KickBall.C.kickSpeed, 1e-4)
				t.truthy(ball.AssemblyLinearVelocity.Z < 0)
				t.eq(promptOf(lying()).ObjectText, "Pip's kick ball", "still Pip's")
				r.clock += 30
				r.world.step()
				t.truthy(lying() ~= nil, "its 60 s on the ground started again at the kick")
				-- behind Kim, or too far: nothing
				ball.CFrame = roblox.CFrame.new(30, 0.5, 2)
				t.falsy(r.world.kickLoose(r.kim), "behind")
				ball.CFrame = roblox.CFrame.new(30, 0.5, -9)
				t.falsy(r.world.kickLoose(r.kim), "out of reach")
				-- a ground kick into someone counts as the kicker's hit
				ball.CFrame = roblox.CFrame.new(0, 0.5, -8.5)
				ball.AssemblyLinearVelocity = roblox.Vector3.new(0, 0, 0)
				r.world.sweep()
				local samBody = r.sam.Character
				samBody.PrimaryPart.CFrame = roblox.CFrame.new(0, 3, -6)
				t.truthy(r.world.kickLoose(r.sam))
				flyTo(r, ball, 0, 1, -21, 45)
				t.eq(r.aiBody:GetAttribute("Gesture"), "flinch", "Sam's kick met the computer's person")
			end)
		end
	)

	t.test("reputation: three hard hits on people within 30 s cost the thrower once, told to them alone", function()
		FakeEngine.with(function()
			local r = rig()
			for i = 1, 3 do
				r.inv.add(r.pip, "kick_ball")
				local ball = send(r, nil)
				flyTo(r, ball, 0, 1, -12, 45)
				r.clock += 5
				promptOf(lying()).Triggered.fire(r.pip) -- (picked back up)
				if i < 3 then
					t.eq(r.rep.get(r.pip), 0, `hit {i}: nothing yet`)
				end
			end
			t.eq(r.rep.get(r.pip), -10)
			t.eq(last(r, "Pip"), "Reputation down: you kept hitting people with the ball (now Fair)")
			for _, w in r.told.Sam do
				t.falsy(string.find(w, "Reputation", 1, true), "Sam is told nothing of Pip's reputation")
			end
			t.eq(r.rep.get(r.sam), 0)
		end)
	end)
end
