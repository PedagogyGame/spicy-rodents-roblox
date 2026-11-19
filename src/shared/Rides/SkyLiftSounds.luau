--!strict
-- ReplicatedStorage.Shared.Rides.SkyLiftSounds
-- The sky lift's and the Lookout's sounds (docs/AUDIO_BUDGET.md "Sky lift and the Lookout"): every cue's library
-- sound (ProSoundEffects, Roblox's licensed library; nothing uploaded, nothing synthesised), how loud it plays and
-- how far it carries, and when a cabin's own cues happen (pure, so a spec can check them).
--   Server/Rides/SkyLiftService plays the station bell, the counter bell and the telescope click from its posts, and
--     keeps the Lookout's three loops (LOOKOUT_LOOPS: the fire, the dining room, the terrace) on posts of their own;
--   Client/Rides/SkyLiftView hangs the cabin's own on each local cabin: the cable hum and the wind (loops; the wind
--     louder the higher the cabin), the doors opening and closing, and the clunk as the grip passes a tower;
--   Client/Rides/Telescope clicks as the view goes in and out.
-- Interface: CUES (cue -> "rbxassetid://<n>"); VOLUME (cue -> 0..1); REACH (cue -> RollOffMaxDistance, studs);
--   LOOKOUT_LOOPS ({ cue, at = { x, y, d } } in the Lookout venue's frame); windVolume(height) -> 0..1;
--   heightOver(x, y, z) -> studs over the ground (a straight slope between the stations' floors);
--   events(i, t0, t1) -> { cue } (cabin i's door and tower cues between two clock times, in order); TOWER_NEAR
-- Pure; no side effects on require.

local SkyLift = require("./SkyLift")

local SkyLiftSounds = {}

SkyLiftSounds.CUES = table.freeze({
	["SkyLift.StationBell"] = "rbxassetid://9113118168", -- Amtrak Superliner 1: a call-to-conductor chime
	["SkyLift.CounterBell"] = "rbxassetid://9125485591", -- Desk Bell, counter service (as the lounge's)
	["SkyLift.TelescopeClick"] = "rbxassetid://9113076465", -- Airstream Door Latch 5: a lever click and snap
	["Telescope.Click"] = "rbxassetid://9113076465", -- the same click, on the looker's own screen
	["SkyLift.CableHum"] = "rbxassetid://9112777363", -- Elevator Room 2: motors run, a steady hum (58 s loop)
	["SkyLift.DoorsOpen"] = "rbxassetid://9113059828", -- Air Chuff 2: a hydraulic, pneumatic air burst
	["SkyLift.DoorsClose"] = "rbxassetid://9113059926", -- Air Chuff 4
	["SkyLift.TowerClunk"] = "rbxassetid://9117951840", -- Pulley Rotating Movement 3: wheels turning, soft clicks
	["SkyLift.WindAtHeight"] = "rbxassetid://9113287001", -- Barstow Wind 3: light, blustery, a low howl (27 s)
	["Lookout.Fireplace"] = "rbxassetid://9112780193", -- Fireplace, crackly, constant burning flame (36 s loop)
	["Lookout.DiningRoom"] = "rbxassetid://9112769536", -- Dining Jesuits 1: plates, cutlery, a murmur (39 s)
	["Lookout.TerraceWind"] = "rbxassetid://9114057104", -- Desert Wind: whistley, light gusts (37 s)
}) :: { [string]: string }

SkyLiftSounds.VOLUME = table.freeze({
	["SkyLift.StationBell"] = 0.5,
	["SkyLift.CounterBell"] = 0.5,
	["SkyLift.TelescopeClick"] = 0.5,
	["Telescope.Click"] = 0.4,
	["SkyLift.CableHum"] = 0.25,
	["SkyLift.DoorsOpen"] = 0.5,
	["SkyLift.DoorsClose"] = 0.5,
	["SkyLift.TowerClunk"] = 0.45,
	["SkyLift.WindAtHeight"] = 0.4, -- at its highest (windVolume)
	["Lookout.Fireplace"] = 0.45,
	["Lookout.DiningRoom"] = 0.2,
	["Lookout.TerraceWind"] = 0.25,
}) :: { [string]: number }

-- how far each is heard (a Sound's RollOffMaxDistance): the cabin's own reach only round the cabin
SkyLiftSounds.REACH = table.freeze({
	["SkyLift.StationBell"] = 80,
	["SkyLift.CounterBell"] = 40,
	["SkyLift.TelescopeClick"] = 30,
	["Telescope.Click"] = 30,
	["SkyLift.CableHum"] = 30,
	["SkyLift.DoorsOpen"] = 40,
	["SkyLift.DoorsClose"] = 40,
	["SkyLift.TowerClunk"] = 60,
	["SkyLift.WindAtHeight"] = 25,
	["Lookout.Fireplace"] = 25,
	["Lookout.DiningRoom"] = 35,
	["Lookout.TerraceWind"] = 40,
}) :: { [string]: number }

-- the Lookout's loops, in its venue frame (tools/bake/lookout/Lookout.luau: the firebox at X 0, D 21.7..22.4; the
-- dining room X -20..50, D -25..25; the terrace X -24..50, D -47..-25), y up from its floor
SkyLiftSounds.LOOKOUT_LOOPS = table.freeze({
	table.freeze({ cue = "Lookout.Fireplace", at = table.freeze({ 0, 1.5, 21.5 }) }),
	table.freeze({ cue = "Lookout.DiningRoom", at = table.freeze({ 20, 4, 0 }) }),
	table.freeze({ cue = "Lookout.TerraceWind", at = table.freeze({ 13, 4, -36 }) }),
})

SkyLiftSounds.WIND_LOW = 15 -- studs over the ground (the platforms): no wind below this
SkyLiftSounds.WIND_HIGH = 120 -- full wind at this height and over
SkyLiftSounds.TOWER_NEAR = SkyLift.STRAND + 3 -- studs in plan from a tower's centre: the grip is at its sheaves

-- How loud the wind round a cabin is at `height` studs over the ground below it.
function SkyLiftSounds.windVolume(height: number): number
	local u = math.clamp((height - SkyLiftSounds.WIND_LOW) / (SkyLiftSounds.WIND_HIGH - SkyLiftSounds.WIND_LOW), 0, 1)
	return SkyLiftSounds.VOLUME["SkyLift.WindAtHeight"] * u
end

-- How high a cabin at (x, y, z) is over the ground under it, near enough for the wind: the ground taken as a
-- straight slope from the base station's floor to the summit's, by how far along the line (in plan) it is.
function SkyLiftSounds.heightOver(x: number, y: number, z: number): number
	local st = SkyLift.stations()
	local a, b = st.base.wheel, st.summit.wheel
	local dx, dz = b.x - a.x, b.z - a.z
	local len2 = dx * dx + dz * dz
	local u = if len2 > 0 then math.clamp(((x - a.x) * dx + (z - a.z) * dz) / len2, 0, 1) else 0
	return y - (st.base.floorY + (st.summit.floorY - st.base.floorY) * u)
end

local function nearTower(x: number, z: number): number?
	local r2 = SkyLiftSounds.TOWER_NEAR * SkyLiftSounds.TOWER_NEAR
	for _, tw in SkyLift.towers() do
		if (x - tw.x) ^ 2 + (z - tw.z) ^ 2 <= r2 then
			return tw.index
		end
	end
	return nil
end

-- Cabin i's own cues between clock times t0 and t1 (t1 > t0, a frame or so apart): the doors starting to open
-- (doorFrac leaves 0), the doors shut (doorFrac back to 0), the grip reaching a tower. Empty for a jump of the
-- clock over a second (a snap: nothing is played for what was skipped).
function SkyLiftSounds.events(i: number, t0: number, t1: number): { string }
	local out: { string } = {}
	if t1 <= t0 or t1 - t0 > 1 then
		return out
	end
	local f0, f1 = SkyLift.doorFrac(i, t0), SkyLift.doorFrac(i, t1)
	if f0 == 0 and f1 > 0 then
		table.insert(out, "SkyLift.DoorsOpen")
	elseif f0 > 0 and f1 == 0 then
		table.insert(out, "SkyLift.DoorsClose")
	end
	local x0, _, z0 = SkyLift.cabin(i, t0)
	local x1, _, z1 = SkyLift.cabin(i, t1)
	local a, b = nearTower(x0, z0), nearTower(x1, z1)
	if b ~= nil and a ~= b then
		table.insert(out, "SkyLift.TowerClunk")
	end
	return out
end

return SkyLiftSounds
