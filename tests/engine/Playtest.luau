--!strict
-- ServerStorage.EngineTests.Playtest (CI place only; injected with --inject ci.project.json)
-- The skeptical playtester's smoke of the first playable build (W1 playtest, docs/waves/W1.md): no
-- screen, so it checks what the owner would hit first. Every menu choice goes through the PlayNet.Pick
-- handler itself (Game.remotes.Pick, the function the RemoteEvent is connected to) with PlayerLike
-- stubs, from a fresh player (possess) and from a held body (swap), and asserts per role: the client
-- gets a "picked" event, the body is the player's Character, it is unanchored (it can move), a person
-- has a working Humanoid, a person does not spawn inside town geometry and has ground under the feet,
-- the AI no longer moves the held body, the help panel has keys for the role, police/drone stand within
-- reach of the right device (E picks the nearest free one). Plus: a junk choice is refused (not an
-- error), F through the Kick handler, and every client ModuleScript requires without error.
-- Interface: run(opts?) -> Result (JSON-friendly)

local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local server = ServerScriptService:WaitForChild("Server")
local Game = (require :: any)(server:WaitForChild("Boot"):WaitForChild("Game"))
local Possession = (require :: any)(server:WaitForChild("Actors"):WaitForChild("Possession"))

local Playtest = {}

local REACH = 16 -- DeviceService.REACH

function Playtest.run(_opts: { [string]: any }?): { [string]: any }
	local failures: { string } = {}
	local numbers: { [string]: any } = {}
	local function check(cond: boolean, msg: string)
		if not cond then
			table.insert(failures, msg)
		end
	end

	-- 1. every client module requires (server context: LocalPlayer is nil, so this proves only that
	-- nothing runs on require; the Main LocalScript is the only client script) ----------------------------
	local client = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	client = client and client:FindFirstChild("Client")
	check(client ~= nil, "no StarterPlayerScripts.Client")
	local PlayMenu: any = nil
	if client then
		local required, scripts = 0, {}
		for _, d in client:GetDescendants() do
			if d:IsA("ModuleScript") then
				local ok, mod = pcall(require, d)
				if ok then
					required += 1
					if d.Name == "PlayMenu" then
						PlayMenu = mod
					end
				else
					table.insert(failures, `client require {d:GetFullName()}: {mod}`)
				end
			elseif d:IsA("LocalScript") or d:IsA("Script") then
				table.insert(scripts, d.Name)
			end
		end
		numbers.clientModules = required
		numbers.clientScripts = scripts
		check(#scripts == 1 and scripts[1] == "Main", `client scripts: {table.concat(scripts, ", ")} (want only Main)`)
	end

	-- 2. boot -----------------------------------------------------------------------------------------
	local engine = Possession.engine()
	engine.streamAround = function() end
	engine.setOwner = function(_root: any, _player: any?) end
	engine.setCharacter = function(player: any, model: any?)
		player.Character = model
	end
	local G = Game.start({ players = false, engine = engine, heartbeat = false })
	local rt = G.runtime
	local possession = rt.possession
	for _ = 1, 30 do
		G.step(1 / 30)
	end

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { rt.bodies, workspace.Terrain }
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { rt.bodies }

	local function stub(id: number): { [string]: any }
		return { UserId = id, Name = `Tester{id}`, Character = nil, attrs = {}, events = {} }
	end

	local function nearestDevice(pos: Vector3): (string?, number)
		local best, bestD = nil, math.huge
		for id, model in rt.devices.models do
			local r = model.PrimaryPart
			if r then
				local d = (r.Position - pos).Magnitude
				if d < bestD then
					best, bestD = id, d
				end
			end
		end
		return best, bestD
	end

	local EXPECT = {
		rodent = "squirrel/spicy",
		squirrel = "squirrel/normal",
		townsperson = "human",
		police = "human",
		drone = "human",
	}
	local report: { [string]: any } = {}

	local function tryRole(player: { [string]: any }, choice: string, label: string)
		G.stateOf(player).lastPick = -math.huge
		table.clear(player.events)
		G.remotes.Pick(player, choice)
		local last = player.events[#player.events]
		local r: { [string]: any } = {}
		report[label] = r
		if last == nil or last.kind ~= "picked" or last.role ~= choice then
			table.insert(failures, `{label}: client got {if last then `{last.kind} {last.text or ""}` else "nothing"}`)
			return
		end
		local actor = possession:actorOf(player)
		if actor == nil then
			table.insert(failures, `{label}: picked but holds no body`)
			return
		end
		local body = actor.body :: Model
		local root = body.PrimaryPart :: BasePart
		local got = if actor.species == "human" then "human" else `{actor.species}/{actor.variant or "-"}`
		r.body = got
		check(got == EXPECT[choice], `{label}: got a {got}`)
		check(player.Character == body, `{label}: Character is not the body`)
		check(root ~= nil and not root.Anchored, `{label}: body root anchored (cannot move)`)
		check(player.attrs.PlayRole == choice, `{label}: PlayRole {player.attrs.PlayRole}`)
		if PlayMenu then
			local lines = PlayMenu.helpLines(choice, nil)
			check(#lines >= 3, `{label}: help panel has {#lines} lines`)
			check(PlayMenu.statusLine(player.attrs) ~= PlayMenu.statusLine({}), `{label}: status line empty`)
		end
		-- the AI must not move a held body (no physics in Luau Execution: it should stay put)
		local before = root.Position
		for _ = 1, 15 do
			G.step(1 / 30)
		end
		r.driftStuds = (root.Position - before).Magnitude
		check(r.driftStuds < 0.01, `{label}: held body moved {r.driftStuds} studs by the server`)
		if actor.species == "human" then
			local hum = body:FindFirstChildOfClass("Humanoid")
			check(hum ~= nil, `{label}: person has no Humanoid`)
			if hum then
				r.walkSpeed = hum.WalkSpeed
				check(hum.WalkSpeed > 0 and not hum.PlatformStand, `{label}: Humanoid cannot walk`)
			end
			-- inside geometry? (the box from 0.6 above the feet to the top)
			local cf, size = body:GetBoundingBox()
			local box = Vector3.new(size.X * 0.8, math.max(0.5, size.Y - 0.6), size.Z * 0.8)
			local hits = workspace:GetPartBoundsInBox(cf * CFrame.new(0, 0.3, 0), box, overlap)
			local solid = {}
			for _, p in hits do
				if p.CanCollide and p.Transparency < 1 then
					table.insert(solid, p:GetFullName())
				end
			end
			r.insideGeometry = solid
			check(#solid == 0, `{label}: spawned inside {table.concat(solid, ", ")}`)
			local down = workspace:Raycast(root.Position, Vector3.new(0, -40, 0), rayParams)
			r.groundGap = if down then root.Position.Y - down.Position.Y else "none"
			check(down ~= nil and root.Position.Y - down.Position.Y < size.Y + 2, `{label}: ground gap {r.groundGap}`)
		end
		if choice == "police" or choice == "drone" then
			local id, d = nearestDevice(root.Position)
			r.nearestDevice = id
			r.deviceStuds = d
			local want = if choice == "drone" then "drone_" else "car_"
			check(id ~= nil and string.sub(id, 1, #want) == want, `{label}: E would take {id}, not a {want}`)
			check(d < REACH, `{label}: {d} studs from the {id} (reach {REACH})`)
		end
	end

	-- a fresh player (possess) picks every role, then a second player (swap order reversed)
	local a = stub(9001)
	for _, choice in { "police", "townsperson", "squirrel", "drone", "rodent" } do
		tryRole(a, choice, `A.{choice}`)
	end
	-- a second player: the town has one Spicy Rodent (A holds it), so B is refused with a clear line
	local b = stub(9002)
	G.remotes.Pick(b, "rodent")
	local refusal = b.events[#b.events]
	numbers.secondRodent = if refusal then `{refusal.kind}: {refusal.text}` else "nothing"
	check(
		refusal ~= nil and refusal.kind == "refused" and string.find(refusal.text, "Spicy Rodent", 1, true) ~= nil,
		`second rodent: {numbers.secondRodent}`
	)
	for _, choice in { "drone", "squirrel", "townsperson", "police" } do
		tryRole(b, choice, `B.{choice}`)
	end
	-- same choice twice keeps the body
	local held = possession:actorOf(b)
	tryRole(b, "police", "B.police.again")
	check(possession:actorOf(b) == held, "picking the same role again changed the body")
	numbers.roles = report

	-- a real join (RoleService.onJoin, the Ladder's lowest rung) hands a person before the menu
	local c = stub(9003)
	local okJoin, joined = pcall(function()
		return rt.roles:onJoin(c)
	end)
	local jb = possession:actorOf(c)
	numbers.join = if okJoin then `{joined}: {if jb then jb.species else "no body"}` else `error {joined}`
	check(okJoin and jb ~= nil and jb.species == "human", `join: {numbers.join}`)
	if jb then
		local root = (jb.body :: Model).PrimaryPart :: BasePart
		check(not root.Anchored and c.Character == jb.body, "join: the joined person cannot move")
		tryRole(c, "squirrel", "C.squirrel.afterJoin")
	end

	-- junk choices are refused, not errors
	G.stateOf(a).lastPick = -math.huge
	table.clear(a.events)
	G.remotes.Pick(a, "dragon")
	G.remotes.Pick(a, { 1, 2 })
	local refused = 0
	for _, e in a.events do
		if e.kind == "refused" then
			refused += 1
		end
	end
	numbers.junkRefused = refused
	-- (the server fires "refused" only for a known choice it could not grant; junk gets nothing)
	check(refused == 0 or refused == 2, `junk choices: {refused} refusals`)

	-- F (Kick handler) as a person with nobody in front: a "kick" miss reaches the client
	G.stateOf(b).lastKick = -math.huge
	table.clear(b.events)
	G.remotes.Kick(b)
	local k = b.events[1]
	numbers.kickEvent = if k then `{k.kind} hit={k.hit}` else "none"
	check(k ~= nil and k.kind == "kick", `F as police gave {numbers.kickEvent}`)

	local okLedger, errors = possession:check()
	check(okLedger, `possession ledger: {table.concat(errors, "; ")}`)
	G.stop()
	return { ok = #failures == 0, failures = failures, numbers = numbers }
end

return Playtest
