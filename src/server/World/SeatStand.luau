--!strict
-- ServerScriptService.Server.World.SeatStand
-- Getting a seated person up, on the server (owner D32: "make sure that when we're sitting down, we can get back up
-- with another button push"; the rules: Shared/World/SeatRules). A seat that carries SeatRules.STAND_ATTRIBUTE (the
-- lounge's 33, a lawn chair) is left by the server: its SeatWeld goes, Sit is cleared, and the body stands at the
-- seat's stand spot facing the way the seat faces. The sitter's client asks over PlayNet.StandUp (Client/World/
-- SeatGetUp: the seat key again, the jump key, a move, the touch screen's STAND), never more often than
-- SeatRules.REPEAT / 2 per player. A seat without the attribute (a vehicle's, the sky lift's) is not touched here.
-- Interface: stand(body) -> the Seat got up from, or nil; standHeight(body) -> studs (the standing pivot over the
--   feet); handler(opts) -> (player) -> boolean (the remote's handler: opts.bodyOf(player) -> Model?, opts.first
--   ((player) -> boolean)? (another service's own seats first: the lounge's), opts.now (() -> number)?)
-- Engine only inside the functions; no side effects on require.

local Import = require("../Import")
local SeatRules = Import.shared("World/SeatRules") :: typeof(require("../../shared/World/SeatRules"))

local SeatStand = {}

-- The standing pivot over the feet: an R15's root sits its HipHeight plus half its own height over the ground.
function SeatStand.standHeight(body: any): number
	local ok, h = pcall(function(): number?
		local hum = body:FindFirstChildOfClass("Humanoid")
		local root = body.PrimaryPart
		if hum and root and type(hum.HipHeight) == "number" and hum.HipHeight > 0 then
			return hum.HipHeight + root.Size.Y / 2
		end
		return nil
	end)
	return if ok and h then h else 3
end

-- stand(body): the body's Humanoid sits on a seat it may get up from: up, and standing at the seat's spot.
function SeatStand.stand(body: any): any?
	if body == nil then
		return nil
	end
	local hum = body:FindFirstChildOfClass("Humanoid")
	local seat = if hum then hum.SeatPart else nil
	if seat == nil then
		return nil
	end
	local offset = seat:GetAttribute(SeatRules.STAND_ATTRIBUTE)
	if typeof(offset) ~= "Vector3" then
		return nil
	end
	local weld = seat:FindFirstChild("SeatWeld")
	hum.Sit = false
	if weld then
		weld:Destroy()
	end
	local cf = seat.CFrame :: CFrame
	local feet = cf:PointToWorldSpace(offset :: Vector3)
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	body:PivotTo(CFrame.lookAt(feet, feet + flat) + Vector3.new(0, SeatStand.standHeight(body), 0))
	return seat
end

-- The PlayNet.StandUp handler: true when the player's body got up.
function SeatStand.handler(opts: {
	bodyOf: (player: any) -> any?,
	first: ((player: any) -> boolean)?,
	now: (() -> number)?,
}): (player: any) -> boolean
	local now = opts.now or os.clock
	local last: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any
	return function(player: any): boolean
		local t = now()
		local prev = last[player]
		if prev and t - prev < SeatRules.REPEAT / 2 then
			return false
		end
		last[player] = t
		local first = opts.first
		if first and first(player) then
			return true
		end
		return SeatStand.stand(opts.bodyOf(player)) ~= nil
	end
end

return SeatStand
