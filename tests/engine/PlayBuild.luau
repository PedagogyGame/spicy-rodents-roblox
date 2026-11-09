--!strict
-- ServerStorage.EngineTests.PlayBuild (CI place only; injected with --inject ci.project.json)
-- Scripted smoke of the first playable build (owner directive 2026-11-09) in the real engine through
-- Open Cloud Luau Execution: Server/Boot/Game boots the whole game (lighting, terrain, data, traffic,
-- 102 bodies, possession, roles, devices, PlayNet) with a PlayerLike stub instead of a real player
-- (Luau Execution has no players, no physics and no Heartbeat: frames are stepped by hand). Then the
-- menu's five picks, the rodent biting a person (Power +100/+130, the victim flees), two kicks
-- knocking the rodent out (health 100 -> 45 -> 0, released, back to the AI at full health), a scripted
-- dart-out in front of a moving car (RUN OVER through the server's swept test), police beside a patrol
-- car and the possession ledger check.
-- Interface: run(opts?) -> Result (JSON-friendly)

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local server = ServerScriptService:WaitForChild("Server")
local Game = (require :: any)(server:WaitForChild("Boot"):WaitForChild("Game"))
local Possession = (require :: any)(server:WaitForChild("Actors"):WaitForChild("Possession"))

local PlayBuild = {}

function PlayBuild.run(_opts: { [string]: any }?): { [string]: any }
	local failures: { string } = {}
	local numbers: { [string]: any } = {}
	local function check(cond: boolean, msg: string)
		if not cond then
			table.insert(failures, msg)
		end
	end
	local engine = Possession.engine()
	engine.streamAround = function() end
	engine.setOwner = function(_root: any, _player: any?) end
	engine.setCharacter = function(player: any, model: any?)
		player.Character = model
	end

	local t0 = os.clock()
	local G = Game.start({ players = false, engine = engine, heartbeat = false })
	numbers.bootSeconds = os.clock() - t0
	numbers.timings = G.timings
	local rt = G.runtime
	local world = rt.world
	local possession = rt.possession

	-- boot -------------------------------------------------------------------------------------------
	check(ReplicatedStorage:GetAttribute("BootReady") == true, "BootReady not set")
	check(ReplicatedStorage:GetAttribute("BootProgress") == 1, "BootProgress not 1")
	local Lighting = game:GetService("Lighting")
	-- the preset owns the time of day (Task A moved golden hour to 16:00): compare with it, not a literal
	local LightingPreset = (require :: any)(
		ReplicatedStorage:WaitForChild("Shared"):WaitForChild("World"):WaitForChild("LightingPreset")
	)
	local wantClock = LightingPreset.GOLDEN.clockTime :: number
	check(math.abs(Lighting.ClockTime - wantClock) < 0.01, `ClockTime {Lighting.ClockTime} (preset {wantClock})`)
	check(Lighting:FindFirstChildOfClass("Atmosphere") ~= nil, "no Atmosphere")
	local town = workspace:FindFirstChild("Town")
	local townParts = 0
	if town then
		for _, d in town:GetDescendants() do
			if d:IsA("BasePart") then
				townParts += 1
			end
		end
	end
	numbers.townParts = townParts
	check(townParts > 5000, `Workspace.Town has {townParts} parts`)
	local hit = workspace:Raycast(Vector3.new(30, 300, 30), Vector3.new(0, -600, 0))
	numbers.groundHit = if hit then hit.Instance:GetFullName() else "nothing"
	check(hit ~= nil, "nothing under (30, 30)")
	check(ReplicatedStorage:FindFirstChild("PlayNet") ~= nil, "no PlayNet")
	check(ReplicatedStorage:FindFirstChild("Net") ~= nil, "no Net")
	local net = ReplicatedStorage:FindFirstChild("Net")
	check(net ~= nil and net:FindFirstChild("VehiclePoses") ~= nil, "no VehiclePoses remote")

	-- the town is alive -----------------------------------------------------------------------------
	local walkers = 0
	local start: { [number]: Vector3 } = {}
	for _, a in world.actors do
		if a.species == "human" and (a.post == "townsperson" or a.post == "rider") then
			walkers += 1
		end
		start[a.id] = Vector3.new(a.x, 0, a.z)
	end
	numbers.walkers = walkers
	check(walkers >= 30, `{walkers} sidewalk walkers`)
	numbers.vehicles = #G.traffic.vehicles
	check(#G.traffic.vehicles >= 20, `{#G.traffic.vehicles} AI vehicles`)
	local vStart: { [number]: Vector3 } = {}
	for _, v in G.traffic.vehicles do
		vStart[v.id] = Vector3.new(v.x, 0, v.z)
	end
	local frames = 300
	local tf = os.clock()
	for _ = 1, frames do
		G.step(1 / 30)
	end
	numbers.frameMs = (os.clock() - tf) * 1000 / frames
	local movedPeople, movedCars = 0, 0
	for _, a in world.actors do
		if a.species == "human" and (Vector3.new(a.x, 0, a.z) - start[a.id]).Magnitude > 2 then
			movedPeople += 1
		end
	end
	for _, v in G.traffic.vehicles do
		if (Vector3.new(v.x, 0, v.z) - vStart[v.id]).Magnitude > 10 then
			movedCars += 1
		end
	end
	numbers.movedPeople10s = movedPeople
	numbers.movedCars10s = movedCars
	check(movedPeople >= 20, `only {movedPeople} people moved in 10 s`)
	check(movedCars >= 10, `only {movedCars} cars moved in 10 s`)

	-- the menu: every pick possesses a real body ----------------------------------------------------
	local player: { [string]: any } = { UserId = 4242, Name = "Smoke", Character = nil, attrs = {} }
	local function pick(choice: string): boolean
		G.stateOf(player).lastPick = -math.huge
		local ok, why = G.pick(player, choice)
		if not ok then
			table.insert(failures, `pick {choice}: {why}`)
		end
		return ok
	end
	local picks: { [string]: string } = {}
	for _, choice in { "townsperson", "squirrel", "police", "drone", "rodent" } do
		if pick(choice) then
			local a = possession:actorOf(player)
			picks[choice] = if a then `{a.species}/{a.variant or "-"}` else "none"
			check(a ~= nil and player.Character == a.body, `{choice}: Character is not the body`)
		end
	end
	numbers.picks = picks
	check(picks.rodent == "squirrel/spicy", `rodent pick gave {picks.rodent}`)
	check(picks.squirrel == "squirrel/normal", `squirrel pick gave {picks.squirrel}`)
	check(player.attrs.Health == 100, `rodent health {player.attrs.Health}`)

	-- the rodent bites a person ---------------------------------------------------------------------
	local rodent = possession:actorOf(player)
	local victim = nil
	for _, a in world.actors do
		if a.species == "human" and a.post == "townsperson" then
			victim = rt.byTownId[a.id]
			break
		end
	end
	if rodent and victim then
		local vr = (victim.body :: Model).PrimaryPart :: BasePart
		local spot = vr.Position + Vector3.new(1.5, -1, 0)
		rodent.body:PivotTo(CFrame.new(spot))
		for _ = 1, 4 do
			G.step(1 / 30)
		end
		numbers.bites = player.attrs.Bites
		numbers.powerAfterBite = player.attrs.Power
		check(player.attrs.Bites == 1, `bites {player.attrs.Bites}`)
		check(player.attrs.Power == 100 or player.attrs.Power == 130, `power {player.attrs.Power}`)
		local vt = nil
		for id, act in rt.byTownId do
			if act == victim then
				vt = id
			end
		end
		local brain = if vt then world.brains[vt] else nil
		numbers.victimState = if brain then brain.state else "?"
		check(brain ~= nil and brain.state == "flee", `victim state {numbers.victimState}`)
		check((victim.body :: Model):FindFirstChild("Shout", true) ~= nil, "no shout over the victim")
	else
		table.insert(failures, "no rodent or victim for the bite")
	end

	-- two kicks knock the (AI) rodent out -----------------------------------------------------------
	pick("townsperson")
	local me = possession:actorOf(player)
	local rodentActor = nil
	for _, a in world.actors do
		local act = rt.byTownId[a.id]
		if act.variant == "spicy" then
			rodentActor = act
		end
	end
	if me and rodentActor then
		local rp = ((rodentActor.body :: Model).PrimaryPart :: BasePart).Position
		local from = rp + Vector3.new(0, 0, -3)
		me.body:PivotTo(CFrame.lookAt(from, Vector3.new(rp.X, from.Y, rp.Z)))
		G.stateOf(player).lastKick = -math.huge
		local k1 = G.kick(player)
		numbers.healthAfterKick1 = G.health(rodentActor.id)
		G.stateOf(player).lastKick = -math.huge
		local k2 = G.kick(player)
		numbers.healthAfterKick2 = G.health(rodentActor.id)
		check(k1 == true and k2 == true, `kicks {k1} {k2}`)
		check(numbers.healthAfterKick1 == 45, `after one kick {numbers.healthAfterKick1}`)
		check(numbers.healthAfterKick2 == 100, "a knocked-out rodent comes back to the AI with full health")
	else
		table.insert(failures, "no kicker or rodent")
	end

	-- RUN OVER: the held rodent darts in front of a moving car -------------------------------------------
	pick("rodent")
	local held = possession:actorOf(player)
	local runOver = false
	local hitBy = nil
	G.traffic.RunOver:connect(function(actorId: any, vehicle: any)
		if held and actorId == held.id then
			runOver = true
			hitBy = vehicle.name
		end
	end)
	local tries = 0
	if held then
		for _, v in G.traffic.vehicles do
			if runOver or tries >= 6 then
				break
			end
			if v.visible and v.speed > 8 then
				tries += 1
				local px, pz = v.x, v.z
				G.step(1 / 30)
				local dx, dz = v.x - px, v.z - pz
				local m = math.sqrt(dx * dx + dz * dz)
				if m > 0.05 then
					local fx, fz = dx / m, dz / m
					local ahead = 6 + 1.4 + v.speed / 30
					local x, z = v.x + fx * ahead, v.z + fz * ahead
					local gy = G.traffic.heightAt(x, z)
					local size = (held.body :: Model):GetExtentsSize()
					held.body:PivotTo(CFrame.new(x - fz * 10, gy + size.Y * 0.5, z + fx * 10))
					G.step(1 / 30)
					held.body:PivotTo(CFrame.new(x, gy + size.Y * 0.5, z))
					for _ = 1, 20 do
						G.step(1 / 30)
						if runOver then
							break
						end
					end
				end
			end
		end
	end
	numbers.runOverTries = tries
	numbers.runOverBy = hitBy
	check(runOver, `no run-over after {tries} dart-outs`)
	if runOver then
		check(possession:actorOf(player) == nil, "run over but still holding the body")
		check(player.attrs.PlayRole == nil, "run over but PlayRole still set")
	end

	-- police beside a patrol car --------------------------------------------------------------------
	if pick("police") then
		local a = possession:actorOf(player)
		local best = math.huge
		for id, model in rt.devices.models do
			if string.sub(id, 1, 4) == "car_" and model.PrimaryPart then
				best = math.min(best, (model.PrimaryPart.Position - a.body:GetPivot().Position).Magnitude)
			end
		end
		numbers.policeToCar = best
		check(best < 16, `police officer {best} studs from the nearest patrol car (reach 16)`)
	end

	local okLedger, errors = possession:check()
	check(okLedger, `possession ledger: {table.concat(errors, "; ")}`)
	numbers.movement = G.movement:stats()
	numbers.traffic = G.traffic:stats()
	G.stop()
	return { ok = #failures == 0, failures = failures, numbers = numbers }
end

return PlayBuild
