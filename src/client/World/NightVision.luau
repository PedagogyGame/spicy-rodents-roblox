--!strict
-- StarterPlayer.StarterPlayerScripts.Client.World.NightVision
-- The Spicy Rodent's night vision (owner 2026-11-10: "give spicy rodent night vision, the only one who has
-- it, player has to hit button for it"). N toggles it while the player is the rodent; nobody else has it.
-- It is this client's own picture only: the gain is added to what World/Sky writes to Lighting each
-- lighting tick (exposure and the two ambients, scaled by how dark it is, so by day it is a green tint
-- and no more), and a ColorCorrectionEffect "NightVision" gives the green phosphor look. The level eases
-- in and out over a quarter of a second. Nothing here touches the server or any other player.
-- Interface: KEY; gain(level, lamps) -> { exposure, lift } (pure); lit(colour, lift) -> colour (pure);
--   grade(level) -> { brightness, contrast, saturation, tint } (pure); level() -> 0..1 (what Sky reads);
--   start() -> { toggle() -> boolean, set(on), isOn() -> boolean, stop() }
-- No side effects on require.

local NightVision = {}

NightVision.KEY = "N"
NightVision.EASE = 8 -- per second
NightVision.EXPOSURE = 2.1 -- stops of gain on a moonless night
NightVision.AMBIENT = { 150, 185, 150 } -- what the ambients are lifted toward
NightVision.DAY_FLOOR = 0.12 -- by day the gain is this fraction of the night's (the picture must not blow out)

local current = 0

-- The light gain at `level` (0..1) when the street lamps are at `lamps` (0 by day, 1 at night).
function NightVision.gain(level: number, lamps: number): { exposure: number, lift: number }
	local l = math.clamp(level, 0, 1)
	local dark = NightVision.DAY_FLOOR + (1 - NightVision.DAY_FLOOR) * math.clamp(lamps, 0, 1)
	return { exposure = NightVision.EXPOSURE * l * dark, lift = 0.85 * l * dark }
end

-- An ambient colour { r, g, b } (0..255) lifted toward the night-vision ambient by `lift` (0..1).
function NightVision.lit(colour: { number }, lift: number): { number }
	local k = math.clamp(lift, 0, 1)
	local a = NightVision.AMBIENT
	return {
		colour[1] + (a[1] - colour[1]) * k,
		colour[2] + (a[2] - colour[2]) * k,
		colour[3] + (a[3] - colour[3]) * k,
	}
end

-- The green picture at `level`.
function NightVision.grade(
	level: number
): { brightness: number, contrast: number, saturation: number, tint: { number } }
	local l = math.clamp(level, 0, 1)
	return {
		brightness = 0.04 * l,
		contrast = 0.22 * l,
		saturation = -0.75 * l,
		tint = { 255 - 150 * l, 255 - 5 * l, 255 - 135 * l },
	}
end

-- The eased level this client is at now (World/Sky adds NightVision.gain of it to its lighting).
function NightVision.level(): number
	return current
end

export type Handle = {
	toggle: () -> boolean,
	set: (on: boolean) -> (),
	isOn: () -> boolean,
	stop: () -> (),
}

function NightVision.start(): Handle
	local Lighting = game:GetService("Lighting")
	local RunService = game:GetService("RunService")
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "NightVision"
	effect.Enabled = false
	effect.Parent = Lighting
	local on = false
	local conn = RunService.RenderStepped:Connect(function(dt: number)
		local target = if on then 1 else 0
		if current == target then
			return
		end
		current += (target - current) * (1 - math.exp(-dt * NightVision.EASE))
		if math.abs(target - current) < 0.01 then
			current = target
		end
		local g = NightVision.grade(current)
		effect.Brightness = g.brightness
		effect.Contrast = g.contrast
		effect.Saturation = g.saturation
		effect.TintColor = Color3.fromRGB(math.round(g.tint[1]), math.round(g.tint[2]), math.round(g.tint[3]))
		effect.Enabled = current > 0
	end)
	return {
		toggle = function(): boolean
			on = not on
			return on
		end,
		set = function(v: boolean)
			on = v
		end,
		isOn = function(): boolean
			return on
		end,
		stop = function()
			conn:Disconnect()
			effect:Destroy()
			current = 0
		end,
	}
end

return NightVision
