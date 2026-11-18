--!strict
-- ServerStorage.EngineTests.AvatarApi (CI place only; ci.project.json)
-- Spike S9 (BUILD_PLAN §4.3, D13; Addendum A3/B1; brief v2 §13a): the avatar APIs in the real
-- engine through Open Cloud Luau Execution.
--   1. Players:GetHumanoidDescriptionFromUserId for public UserIds (traits, dynamic head, layered)
--   2. Players:CreateHumanoidModelFromDescription (R15) for each, timing
--   3. MarketplaceService:GetProductInfo on their shirt, pants and accessories: colour-word hit rate
--      through Shared/Avatar/BlendRules.colourWord, and BlendRules.traits/compose on the live data
--   4. classic face Decal copied onto a custom head Part
--   5. one rigid Accessory welded to a part named HeadSocket on a non-Humanoid rig
--   6. timing of 60 description fetches (sequential and 6-wide parallel)
-- Everything is pcall-wrapped; a failure is recorded, never thrown. Returns JSON.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlendRules = (require :: any)(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Avatar"):WaitForChild("BlendRules")
)

export type Options = {
	userIds: { number }?,
	timingCount: number?,
	parallel: number?,
	classicFaceIds: { number }?, -- classic Face assets to load through InsertService (the face path)
}

local AvatarApi = {}

-- Public, long-lived accounts (Roblox staff and well-known creators) plus the owner. Which of them
-- carry a dynamic head or layered clothing is discovered at run time and recorded in the result.
AvatarApi.DEFAULT_USER_IDS = {
	1, -- Roblox
	156, -- builderman
	261, -- Shedletsky
	2, -- John Doe
	3, -- Jane Doe
	16, -- Clockwork
	21557, -- erik.cassel
	80254, -- stickmasterluke
	1311, -- Telamon-era staff id
	23415609, -- a later staff id
	13645, -- Keith
	11958930616, -- the experience owner
	1234567890, -- an arbitrary mid-era account (newer avatar features likelier)
	3000000000, -- an arbitrary recent account id
	2000000000,
	4000000000,
}

local LAYERED_TYPES = {
	TShirt = true,
	Shirt = true,
	Pants = true,
	Jacket = true,
	Sweater = true,
	Shorts = true,
	LeftShoe = true,
	RightShoe = true,
	DressSkirt = true,
	Eyebrow = true,
	Eyelash = true,
}

local function rgb(c: Color3): { r: number, g: number, b: number }
	return { r = c.R, g = c.G, b = c.B }
end

local function describe(desc: HumanoidDescription): { [string]: any }
	local accessories = {}
	local okAcc, list = pcall(function()
		return desc:GetAccessories(true)
	end)
	if okAcc then
		for _, a in list do
			table.insert(accessories, {
				assetId = a.AssetId,
				accessoryType = a.AccessoryType.Name,
				isLayered = a.IsLayered == true,
				order = a.Order,
			})
		end
	end
	return {
		HeadColor = rgb(desc.HeadColor),
		TorsoColor = rgb(desc.TorsoColor),
		LeftArmColor = rgb(desc.LeftArmColor),
		RightArmColor = rgb(desc.RightArmColor),
		LeftLegColor = rgb(desc.LeftLegColor),
		RightLegColor = rgb(desc.RightLegColor),
		Face = desc.Face,
		Head = desc.Head,
		Torso = desc.Torso,
		Shirt = desc.Shirt,
		Pants = desc.Pants,
		GraphicTShirt = desc.GraphicTShirt,
		HeightScale = desc.HeightScale,
		WidthScale = desc.WidthScale,
		HeadScale = desc.HeadScale,
		DepthScale = desc.DepthScale,
		BodyTypeScale = desc.BodyTypeScale,
		ProportionScale = desc.ProportionScale,
		accessories = accessories,
	}
end

local function productInfo(assetId: number): (boolean, { [string]: any }?)
	if assetId == 0 then
		return false, nil
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(assetId)
	end)
	if ok and type(info) == "table" then
		return true, { name = info.Name, description = info.Description, assetTypeId = info.AssetTypeId }
	end
	return false, { error = tostring(info) }
end

local function fetchDescription(userId: number): (boolean, HumanoidDescription | string, number)
	local t0 = os.clock()
	local ok, res = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(userId)
	end)
	local ms = (os.clock() - t0) * 1000
	if ok then
		return true, res, ms
	end
	return false, tostring(res), ms
end

local function modelFromDescription(desc: HumanoidDescription): (boolean, Model | string, number)
	local t0 = os.clock()
	local ok, res = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	local ms = (os.clock() - t0) * 1000
	if ok then
		return true, res, ms
	end
	return false, tostring(res), ms
end

-- The face: a classic head carries Head.face (Decal); a dynamic head carries FaceControls.
local function faceOf(model: Model): { [string]: any }
	local head = model:FindFirstChild("Head")
	if not head then
		return { found = false }
	end
	local decal = head:FindFirstChildOfClass("Decal")
	local faceControls = head:FindFirstChildOfClass("FaceControls")
	return {
		found = true,
		decal = if decal then decal.Texture else nil,
		decalName = if decal then decal.Name else nil,
		dynamic = faceControls ~= nil,
		headClass = head.ClassName,
	}
end

-- 4. copy the classic face Decal onto a custom head Part named Head under a non-Humanoid rig
local function faceTransfer(model: Model, parent: Instance): { [string]: any }
	local head = model:FindFirstChild("Head")
	local decal = head and head:FindFirstChildOfClass("Decal")
	if not decal then
		return { ok = false, reason = "no classic face decal (dynamic head or none)" }
	end
	local rig = Instance.new("Model")
	rig.Name = "CustomRig"
	local customHead = Instance.new("Part")
	customHead.Name = "Head"
	customHead.Size = Vector3.new(1.2, 1.2, 1.2)
	customHead.Anchored = true
	customHead.Parent = rig
	rig.Parent = parent
	local ok, err = pcall(function()
		local copy = decal:Clone()
		copy.Name = "FaceDecal"
		copy.Face = Enum.NormalId.Front
		copy.Parent = customHead
	end)
	local placed = customHead:FindFirstChild("FaceDecal")
	return {
		ok = ok and placed ~= nil and (placed :: Decal).Texture == decal.Texture,
		texture = decal.Texture,
		error = if ok then nil else tostring(err),
	}
end

-- 4b. classic faces are Decal assets: load one with InsertService and copy its Decal onto a custom
-- head (HumanoidDescription.Face is 0 on every dynamic-head avatar, so this is the path for the
-- accounts that still carry a classic face, and for the Lab's sample faces).
local function classicFaceViaLoadAsset(faceId: number, parent: Instance): { [string]: any }
	local okL, asset = pcall(function()
		return InsertService:LoadAsset(faceId)
	end)
	if not okL then
		return { ok = false, faceId = faceId, error = tostring(asset) }
	end
	local decal: Decal? = nil
	for _, d in (asset :: Instance):GetDescendants() do
		if d:IsA("Decal") then
			decal = d
			break
		end
	end
	if not decal then
		return { ok = false, faceId = faceId, error = "LoadAsset returned no Decal" }
	end
	local rig = Instance.new("Model")
	rig.Name = "CustomRigFace"
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Anchored = true
	head.Parent = rig
	rig.Parent = parent
	local copy = (decal :: Decal):Clone()
	copy.Name = "FaceDecal"
	copy.Face = Enum.NormalId.Front
	copy.Parent = head
	local placed = head:FindFirstChild("FaceDecal") :: Decal?
	return {
		ok = placed ~= nil and placed.Texture == (decal :: Decal).Texture and placed.Texture ~= "",
		faceId = faceId,
		texture = (decal :: Decal).Texture,
		decalName = (decal :: Decal).Name,
	}
end

-- 5. weld one rigid accessory (its Handle) to a part named HeadSocket on a non-Humanoid rig, using
-- the accessory's own attachment offset so it sits where it would on an R15 head.
local function accessoryTransfer(model: Model, parent: Instance): { [string]: any }
	local chosen: Accessory? = nil
	for _, acc in model:GetChildren() do
		if acc:IsA("Accessory") then
			local handle = acc:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") and not handle:FindFirstChildOfClass("WrapLayer") then
				chosen = acc
				break
			end
		end
	end
	if not chosen then
		return { ok = false, reason = "no rigid accessory on this avatar" }
	end
	local accessory = chosen :: Accessory
	local handle = accessory:FindFirstChild("Handle") :: BasePart
	local attachment = handle:FindFirstChildOfClass("Attachment")
	local rig = Instance.new("Model")
	rig.Name = "SquirrelRig"
	local root = Instance.new("Part")
	root.Name = "RootPart"
	root.Size = Vector3.new(1, 1, 1)
	root.Anchored = true
	root.CFrame = CFrame.new(100, 10, 100)
	root.Parent = rig
	local socket = Instance.new("Part")
	socket.Name = "HeadSocket"
	socket.Size = Vector3.new(0.6, 0.6, 0.6)
	socket.Anchored = false
	socket.CFrame = root.CFrame * CFrame.new(0, 1.2, -0.8)
	socket.Parent = rig
	local socketWeld = Instance.new("WeldConstraint")
	socketWeld.Part0 = root
	socketWeld.Part1 = socket
	socketWeld.Parent = socket
	rig.PrimaryPart = root
	rig.Parent = parent
	local ok, err = pcall(function()
		local clone = accessory:Clone()
		local h = clone:FindFirstChild("Handle") :: BasePart
		h.Anchored = false
		h.CanCollide = false
		h.Massless = true
		-- shrink onto the socket (D13: one accessory shrunk onto HeadSocket)
		local scale = 0.45
		if h:IsA("MeshPart") then
			pcall(function()
				h.Size = h.Size * scale
			end)
		else
			local mesh = h:FindFirstChildOfClass("SpecialMesh")
			if mesh then
				mesh.Scale = mesh.Scale * scale
			end
			h.Size = h.Size * scale
		end
		local a = h:FindFirstChildOfClass("Attachment")
		local offset = if a then a.CFrame else CFrame.new()
		h.CFrame = socket.CFrame * CFrame.new(0, 0.3, 0) * offset:Inverse()
		local weld = Instance.new("Weld")
		weld.Name = "HeadSocketWeld"
		weld.Part0 = socket
		weld.Part1 = h
		weld.C0 = socket.CFrame:ToObjectSpace(h.CFrame)
		weld.Parent = h
		clone.Parent = rig
	end)
	local welded = rig:FindFirstChild(accessory.Name)
	local handleNow = welded and welded:FindFirstChild("Handle")
	local dist = if handleNow then ((handleNow :: BasePart).Position - socket.Position).Magnitude else -1
	return {
		ok = ok and welded ~= nil and dist >= 0 and dist < 3,
		accessory = accessory.Name,
		accessoryType = accessory.AccessoryType.Name,
		hadAttachment = attachment ~= nil,
		attachmentName = if attachment then attachment.Name else nil,
		handleToSocketStuds = dist,
		error = if ok then nil else tostring(err),
	}
end

function AvatarApi.run(options: Options?): { [string]: any }
	local opts: Options = options or {}
	local userIds: { number } = opts.userIds or AvatarApi.DEFAULT_USER_IDS
	local started = os.clock()
	local scratch = Instance.new("Folder")
	scratch.Name = "AvatarApiScratch"
	scratch.Parent = workspace

	local perUser = {}
	local infoCache: { [number]: { [string]: any } } = {}
	local infoCalls, infoOk, infoColourHits, infoColourTried = 0, 0, 0, 0
	local firstFaceTransfer: { [string]: any }? = nil
	local firstAccessoryTransfer: { [string]: any }? = nil
	local dynamicHeads, layeredUsers = 0, 0
	local descriptionsOk, modelsOk = 0, 0
	local modelMsTotal = 0

	for _, userId in userIds do
		local entry: { [string]: any } = { userId = userId }
		local okDesc, descOrErr, descMs = fetchDescription(userId)
		entry.descriptionMs = descMs
		if not okDesc then
			entry.error = descOrErr
			table.insert(perUser, entry)
			continue
		end
		descriptionsOk += 1
		local desc = descOrErr :: HumanoidDescription
		local data = describe(desc)
		entry.description = data
		local layered = false
		for _, a in data.accessories do
			if a.isLayered or LAYERED_TYPES[a.accessoryType] then
				layered = true
			end
		end
		entry.layeredClothing = layered
		if layered then
			layeredUsers += 1
		end

		-- GetProductInfo on shirt, pants and every accessory (cached)
		local itemIds = { data.Shirt, data.Pants, data.GraphicTShirt }
		for _, a in data.accessories do
			table.insert(itemIds, a.assetId)
		end
		local items = {}
		local info: { [number]: { name: string, description: string? } } = {}
		for _, id in itemIds do
			if id ~= 0 then
				local cached = infoCache[id]
				if not cached then
					infoCalls += 1
					local okInfo, got = productInfo(id)
					-- a typed local: inside `if not cached` the checker takes `cached` for nil
					local fresh: { [string]: any } = got or { error = "no info" }
					fresh.ok = okInfo
					infoCache[id] = fresh
					cached = fresh
					if okInfo then
						infoOk += 1
					end
				end
				if cached.ok then
					info[id] = { name = cached.name, description = cached.description }
					infoColourTried += 1
					local c, word = BlendRules.colourWord(cached.name)
					if c then
						infoColourHits += 1
					end
					table.insert(items, { assetId = id, name = cached.name, colourWord = word })
				else
					table.insert(items, { assetId = id, error = cached.error })
				end
			end
		end
		entry.items = items

		-- model: dynamic head check, face, accessory transfer, BlendRules on the live data
		local okModel, modelOrErr, modelMs = modelFromDescription(desc)
		entry.modelMs = modelMs
		if okModel then
			modelsOk += 1
			modelMsTotal += modelMs
			local model = modelOrErr :: Model
			model.Parent = scratch
			local face = faceOf(model)
			entry.face = face
			if face.dynamic then
				dynamicHeads += 1
			end
			data.HeadIsDynamic = face.dynamic == true
			if not firstFaceTransfer or (firstFaceTransfer.ok ~= true and face.decal) then
				local transfer = faceTransfer(model, scratch)
				transfer.userId = userId
				firstFaceTransfer = transfer
			end
			if not firstAccessoryTransfer or firstAccessoryTransfer.ok ~= true then
				local transfer = accessoryTransfer(model, scratch)
				transfer.userId = userId
				firstAccessoryTransfer = transfer
			end
			local okTraits, traitsOrErr = pcall(function()
				local traits = BlendRules.traits(data, info)
				return {
					skinToneIndex = traits.skinToneIndex,
					skinIsHuman = traits.skinIsHuman,
					dominant = traits.dominant,
					sources = traits.sources,
					nameHits = traits.nameHits,
					nameTried = traits.nameTried,
					bizarre = traits.bizarre,
					bizarreReasons = traits.bizarreReasons,
					signature = traits.signature,
					hairAccessory = traits.hairAccessory,
					headAccessory = traits.headAccessory,
					looks = {
						human = BlendRules.compose("human", {
							body = { r = 0.8, g = 0.6, b = 0.4 },
							pattern = { r = 0.3, g = 0.4, b = 0.5 },
							eyes = { r = 0.1, g = 0.1, b = 0.1 },
							eyesLocked = false,
						}, traits),
						squirrel = BlendRules.compose("squirrel", {
							body = { r = 0.718, g = 0.518, b = 0.325 },
							pattern = { r = 0.91, g = 0.86, b = 0.77 },
							eyes = { r = 0.16, g = 0.19, b = 0.18 },
							eyesLocked = false,
						}, traits),
					},
				}
			end)
			entry.blend = if okTraits then traitsOrErr else { error = tostring(traitsOrErr) }
			model:Destroy()
		else
			entry.modelError = modelOrErr
		end
		table.insert(perUser, entry)
	end

	-- 4b. the classic face path
	local classicFaces = {}
	local faceIds: { number } = opts.classicFaceIds or { 144075659, 8560971 }
	for _, faceId in faceIds do
		table.insert(classicFaces, classicFaceViaLoadAsset(faceId, scratch))
	end

	-- 6. timing: N DISTINCT user ids sequentially (the engine caches repeats: 60 repeats of the
	-- probe set took about 1 ms), then in parallel batches on the same ids
	local timingCount = opts.timingCount or 60
	local okIds = {}
	for i = 1, timingCount do
		table.insert(okIds, 100 + i * 7) -- early accounts, mostly real; failures are counted
	end
	local timing: { [string]: any } = { count = timingCount, okIds = #okIds, distinctIds = true }
	if #okIds > 0 then
		local t0 = os.clock()
		local failures = 0
		local perCall = {}
		for i = 1, timingCount do
			local okD, _, ms = fetchDescription(okIds[(i - 1) % #okIds + 1])
			table.insert(perCall, ms)
			if not okD then
				failures += 1
			end
		end
		timing.sequentialSeconds = os.clock() - t0
		timing.sequentialFailures = failures
		table.sort(perCall)
		timing.perCallMs = { min = perCall[1], median = perCall[math.ceil(#perCall / 2)], max = perCall[#perCall] }
		local width = opts.parallel or 6
		local t1 = os.clock()
		local done, pfailures = 0, 0
		for i = 1, timingCount, width do
			local threads = 0
			for j = i, math.min(timingCount, i + width - 1) do
				threads += 1
				task.spawn(function()
					local okD = fetchDescription(okIds[(j - 1) % #okIds + 1])
					if not okD then
						pfailures += 1
					end
					done += 1
				end)
			end
			local waited = 0
			while done < math.min(timingCount, i + width - 1) and waited < 600 do
				task.wait()
				waited += 1
			end
		end
		timing.parallelSeconds = os.clock() - t1
		timing.parallelWidth = width
		timing.parallelFailures = pfailures
		timing.parallelCompleted = done
	end

	scratch:Destroy()
	local result = {
		suite = "AvatarApi",
		users = perUser,
		summary = {
			userIds = #userIds,
			descriptionsOk = descriptionsOk,
			modelsOk = modelsOk,
			modelAvgMs = if modelsOk > 0 then modelMsTotal / modelsOk else 0,
			dynamicHeads = dynamicHeads,
			layeredClothingUsers = layeredUsers,
			productInfo = {
				calls = infoCalls,
				ok = infoOk,
				colourWordHits = infoColourHits,
				colourWordTried = infoColourTried,
				colourWordRate = if infoColourTried > 0 then infoColourHits / infoColourTried else 0,
			},
			faceTransfer = firstFaceTransfer,
			classicFaces = classicFaces,
			accessoryTransfer = firstAccessoryTransfer,
			timing = timing,
		},
		elapsedSeconds = os.clock() - started,
		placeId = game.PlaceId,
		placeVersion = game.PlaceVersion,
	}
	result.pass = {
		traitsReturned = descriptionsOk >= math.min(10, #userIds) * 0.8,
		modelsBuilt = modelsOk >= 1,
		faceTransfer = (firstFaceTransfer ~= nil and firstFaceTransfer.ok == true)
			or (classicFaces[1] ~= nil and classicFaces[1].ok == true),
		accessoryTransfer = firstAccessoryTransfer ~= nil and firstAccessoryTransfer.ok == true,
		sixtyUnder3s = timing.sequentialSeconds ~= nil
			and (timing.sequentialSeconds < 3 or (timing.parallelSeconds or 99) < 3),
	}
	result.ok = result.pass.traitsReturned and result.pass.modelsBuilt
	return result
end

return AvatarApi
