--!strict
-- StarterPlayer.StarterPlayerScripts.Client.UI.AimMarker
-- The air trick's landing marker (owner D18: "super subtle and small please, light sky blue perhaps, non-invasive"):
-- while the held squirrel's re-aim is live, a small flat disc lies where the flight comes down, faint and light sky
-- blue, with no text, no glow and no shadow; only this player sees it (it lives under the camera, which does not
-- replicate). It fades in and out over FADE seconds. One part, made once a body; a frame's work is one CFrame and one
-- transparency write while it shows. The landing is the motor's own (SquirrelMotor.landingIn: two ground looks).
-- Interface: SIZE, THICK, COLOR, SHOWN (its transparency at full), FADE; fade(cur, want, dt) -> transparency (pure);
--   start() -> Handle { set(x?, y?, z?, dt), stop() }  (x nil: fade out)
-- No side effects on require.

local AimMarker = {}

AimMarker.SIZE = 1.2 -- studs across (a squirrel is about 2.5 long)
AimMarker.THICK = 0.05
AimMarker.COLOR = { 150, 205, 240 } -- light sky blue
AimMarker.SHOWN = 0.72 -- transparency when fully shown (28 % opaque)
AimMarker.FADE = 0.15 -- seconds to fade in or out

-- the transparency `dt` seconds on from `cur` toward shown (want) or hidden (not want)
function AimMarker.fade(cur: number, want: boolean, dt: number): number
	local stepBy = (1 - AimMarker.SHOWN) * dt / AimMarker.FADE
	if want then
		return math.max(AimMarker.SHOWN, cur - stepBy)
	end
	return math.min(1, cur + stepBy)
end

export type Handle = {
	set: (x: number?, y: number?, z: number?, dt: number) -> (),
	stop: () -> (),
}

function AimMarker.start(): Handle
	local p = Instance.new("Part")
	p.Name = "AirTrickAim"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(AimMarker.THICK, AimMarker.SIZE, AimMarker.SIZE)
	p.Color = Color3.fromRGB(AimMarker.COLOR[1], AimMarker.COLOR[2], AimMarker.COLOR[3])
	p.Material = Enum.Material.SmoothPlastic
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = workspace.CurrentCamera
	local shown = 1
	return {
		set = function(x: number?, y: number?, z: number?, dt: number)
			local want = x ~= nil and y ~= nil and z ~= nil
			shown = AimMarker.fade(shown, want, dt)
			if want then
				-- (a cylinder's axis is its X: lay it flat, a hair over the ground)
				p.CFrame = CFrame.new(x :: number, (y :: number) + 0.06, z :: number) * CFrame.Angles(0, 0, math.pi / 2)
			end
			if p.Transparency ~= shown then
				p.Transparency = shown
			end
		end,
		stop = function()
			p:Destroy()
		end,
	}
end

return AimMarker
