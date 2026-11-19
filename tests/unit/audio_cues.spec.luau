--!strict
-- No silent sounds (owner D16 #36, #50; docs/AUDIO_BUDGET.md): every cue the game names has a sound. A cue's id
-- is a library or Roblox sound ("rbxassetid://<n>") or a sound shipped with every client ("rbxasset://sounds/..."),
-- except the few that are the game's own uploads (Shared/Audio/Uploads): those are empty only until the lead
-- uploads them, each with its candidate made and checked (assets/audio/candidates). The upload count stays within
-- the plan (at most UPLOAD_PLAN this month; B3), and docs/AUDIO_BUDGET.md records every library id chosen and every
-- upload slot. A static pass over src/ finds any other sound left empty.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Uploads = require("@shared/Audio/Uploads")
local SkyLiftSounds = require("@shared/Rides/SkyLiftSounds")
local SkyLift = require("@shared/Rides/SkyLift")
local LoungeClassic = require("@shared/Attractions/LoungeClassic")
local ItemRules = require("@shared/Items/ItemRules")
local ItemWorld = require("@server/Items/ItemWorld")
local CornerStore = require("@server/Items/CornerStore")
local LoungeService = require("@server/Attractions/LoungeService")
local CombatService = require("@server/Combat/CombatService")
local YardHazards = require("@server/Wildlife/YardHazards")
local SewerService = require("@server/World/SewerService")
local SkyLiftService = require("@server/Rides/SkyLiftService")
local SewerAmbience = require("@client/World/SewerAmbience")
local ClientGames = require("@client/Minigames/ClientGames")
local MinigameSounds = require("@client/Minigames/MinigameSounds")

local UPLOAD_PLAN = 12 -- uploads planned at most (40 a month working, at least 50 kept for the owner's other games)

-- the cue -> upload slot of every cue that waits for an upload
local function uploadCues(): { [string]: string }
	local out: { [string]: string } = {}
	for slot, s in Uploads.SLOTS do
		for _, cue in s.cues do
			out[cue] = slot
		end
	end
	return out
end

local function heard(id: string): boolean
	return string.match(id, "^rbxassetid://%d+$") ~= nil or string.match(id, "^rbxasset://sounds/[%w_%-%.]+$") ~= nil
end

return function(t)
	local waiting = uploadCues()

	-- every table of the game's sounds, by where it lives
	local function tables(): { [string]: { [string]: string } }
		local jazz: { [string]: string } = {}
		for _, j in LoungeClassic.JAZZ do
			jazz[j.cue] = j.id
		end
		local sky: { [string]: string } = {}
		for _, name in SkyLiftService.CUES do
			sky[name] = SkyLiftSounds.CUES[name] or ""
		end
		return {
			["Server/Items/ItemWorld SOUNDS"] = ItemWorld.SOUNDS,
			["Server/Items/CornerStore SOUNDS"] = CornerStore.SOUNDS,
			["Server/Attractions/LoungeService SOUND_IDS"] = LoungeService.SOUND_IDS,
			["Shared/Attractions/LoungeClassic JAZZ"] = jazz,
			["Server/Combat/CombatService SOUNDS"] = CombatService.SOUNDS,
			["Server/Wildlife/YardHazards SOUNDS"] = YardHazards.SOUNDS,
			["Server/World/SewerService CUES"] = SewerService.CUES,
			["Client/World/SewerAmbience CUES"] = SewerAmbience.CUES,
			["Shared/Rides/SkyLiftSounds CUES"] = SkyLiftSounds.CUES,
			["Server/Rides/SkyLiftService CUES"] = sky,
			["Client/Minigames (every game's sounds)"] = MinigameSounds.CUES,
		}
	end

	t.test("no cue is silent: a sound for each, or an upload slot waiting for the lead", function()
		assert(#ClientGames.LIST >= 13, "the client's games are registered")
		local n, slots = 0, 0
		for where, list in tables() do
			for cue, id in list do
				n += 1
				if id == "" and waiting[cue] then
					slots += 1
				else
					t.truthy(heard(id), `{where}: {cue} has a sound (got "{id}")`)
				end
			end
		end
		t.truthy(n >= 180, `{n} cues checked`)
		-- every cue an item names is in the item table
		for _, cue in ItemRules.CUES do
			t.truthy(ItemWorld.SOUNDS[cue] ~= nil, `{cue} has a row`)
		end
		-- the server's hiss is the client's
		t.eq(SewerService.CUES["sewer.hiss"], SewerAmbience.CUES["sewer.hiss"])
	end)

	t.test("the uploads: few, each with a checked candidate in the manifest, none recorded without a file", function()
		local manifest = serde.decode("json", fs.readFile("assets/audio/candidates/manifest.json"))
		local bySlot: { [string]: any } = {}
		for _, c in manifest.candidates do
			bySlot[c.slot] = c
		end
		local count = 0
		for slot, s in Uploads.SLOTS do
			count += 1
			local c = bySlot[slot]
			t.truthy(c ~= nil, `{slot} has a candidate in the manifest`)
			if c then
				t.eq(c.file, s.file, `{slot}: the same file`)
				t.truthy(fs.isFile(s.file), `{s.file} is there`)
				t.truthy(c.channels == 1 and c.seconds > 0 and c.seconds <= 7, `{slot}: mono, short`)
				t.truthy(type(c.licence) == "string" and #c.licence > 0, `{slot}: its licence is recorded`)
				t.truthy(type(c.how) == "string" and #c.how > 0, `{slot}: how it was made is recorded`)
				t.eq(#c.cues, #s.cues)
				-- an id in the game is the id in the manifest (tools/audio/publish.py --record writes both)
				t.eq(s.id, c.assetId or "", `{slot}: the game's id is the manifest's`)
			end
			t.eq(Uploads.id(slot), if s.id == "" then "" else `rbxassetid://{s.id}`)
		end
		t.eq(count, manifest.uploadsPlanned)
		t.truthy(count >= 1 and count <= UPLOAD_PLAN, `{count} uploads planned (at most {UPLOAD_PLAN})`)
		-- the custom bark is one of them (owner #36)
		t.eq(waiting["Dogs.Bark"], "dog_bark")
		t.eq(YardHazards.SOUNDS["Dogs.Bark"], Uploads.id("dog_bark"))
	end)

	t.test("docs/AUDIO_BUDGET.md records every library id chosen and every upload slot", function()
		local doc = fs.readFile("docs/AUDIO_BUDGET.md")
		for where, list in tables() do
			for cue, id in list do
				local num = string.match(id, "^rbxassetid://(%d+)$")
				if num then
					t.truthy(string.find(doc, num, 1, true) ~= nil, `{where}: {cue}'s id {num} is in the doc`)
				end
			end
		end
		for slot in Uploads.SLOTS do
			t.truthy(string.find(doc, "`" .. slot .. "`", 1, true) ~= nil, `the upload slot {slot} is in the doc`)
		end
	end)

	t.test("nothing under src/ leaves a sound empty outside the upload slots", function()
		local bad: { string } = {}
		local function scan(dir: string)
			for _, name in fs.readDir(dir) do
				local path = `{dir}/{name}`
				if fs.isDir(path) then
					scan(path)
				elseif string.sub(name, -5) == ".luau" then
					local n = 0
					for line in string.gmatch(fs.readFile(path), "[^\n]*") do
						n += 1
						-- an empty asset literal, a Sound given an empty literal id, or an empty-id fill loop
						if
							string.find(line, '"rbxassetid://"', 1, true)
							or string.match(line, 'SoundId%s*=%s*""')
							or string.match(line, 'SOUNDS%b[]%s*=%s*""')
						then
							table.insert(bad, `{path}:{n}: {line}`)
						end
					end
				end
			end
		end
		scan("src")
		t.eq(#bad, 0, table.concat(bad, "\n"))
	end)

	t.test("the sky lift's cabin cues: doors open and shut once a station, a clunk at each tower", function()
		local open, shut, clunk = 0, 0, 0
		local period = 0
		-- one whole loop of cabin 1 at 30 frames a second
		local dt = 1 / 30
		local t0 = 0
		local towers = #SkyLift.towers()
		local _, _, _, _, phase0 = SkyLift.cabin(1, 0)
		local seen = { phase0 }
		while period < 2 do
			local t1 = t0 + dt
			for _, e in SkyLiftSounds.events(1, t0, t1) do
				if e == "SkyLift.DoorsOpen" then
					open += 1
				elseif e == "SkyLift.DoorsClose" then
					shut += 1
				elseif e == "SkyLift.TowerClunk" then
					clunk += 1
				end
			end
			local _, _, _, _, phase = SkyLift.cabin(1, t1)
			if phase ~= seen[#seen] then
				table.insert(seen, phase)
				if phase == phase0 then
					period += 1
				end
			end
			t0 = t1
		end
		-- two loops: each station's doors open and shut twice; every tower passed on both strands, twice
		t.truthy(open >= 3 and open <= 4, `{open} openings`)
		t.truthy(shut >= 3 and shut <= 4, `{shut} closings`)
		t.truthy(clunk >= 2 * towers and clunk <= 4 * towers + 2, `{clunk} clunks for {towers} towers`)
		-- a jump of the clock plays nothing
		t.eq(#SkyLiftSounds.events(1, 0, 30), 0)
		-- the wind: none low, full high
		t.eq(SkyLiftSounds.windVolume(0), 0)
		t.near(SkyLiftSounds.windVolume(500), SkyLiftSounds.VOLUME["SkyLift.WindAtHeight"], 1e-9)
		for name in SkyLiftSounds.CUES do
			t.truthy(SkyLiftSounds.VOLUME[name] ~= nil and SkyLiftSounds.REACH[name] ~= nil, `{name}: volume, reach`)
		end
		for _, l in SkyLiftSounds.LOOKOUT_LOOPS do
			t.truthy(SkyLiftSounds.CUES[l.cue] ~= nil, l.cue)
		end
	end)
end
