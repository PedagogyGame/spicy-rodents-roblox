--!strict
-- StarterPlayerScripts.Client.World.SeatGetUp
-- Getting up from THE GILDED ACORN's seats (Server/Attractions/LoungeService sits a person with R on a seat's
-- prompt): jump gets up as from any Seat, and so does moving (W, A, S, D, the stick, the touch thumbstick:
-- Shared/Attractions/LoungeClassic.standUp), which an engine Seat does not do on its own. Only seats that carry
-- LoungeClassic.SEAT_ATTRIBUTE: a car's seat or the sky lift's is left alone.
-- Interface: start(ctx) -> Handle { step(), stop() }; ctx = { current: () -> Model?, heartbeat: boolean? (default
--   true: step on RunService.Heartbeat), move: (() -> Vector3)? (default: the PlayerModule's move vector) }
-- Engine only inside the functions; no side effects on require.

local Import = require("../Import")
local LoungeClassic =
	Import.shared("Attractions/LoungeClassic") :: typeof(require("../../shared/Attractions/LoungeClassic"))

local SeatGetUp = {}

export type Handle = { step: () -> boolean, stop: () -> () }

local function moveVector(): () -> Vector3
	local ctl: any = nil
	return function(): Vector3
		if ctl == nil then
			pcall(function()
				local ps = (game:GetService("Players").LocalPlayer :: any).PlayerScripts :: Instance
				local pm = ps:FindFirstChild("PlayerModule")
				ctl = if pm then (require :: any)(pm):GetControls() else nil
			end)
		end
		local ok, v = pcall(function()
			return ctl:GetMoveVector()
		end)
		return if ok and typeof(v) == "Vector3" then v else Vector3.zero
	end
end

function SeatGetUp.start(ctx: { current: () -> Model?, heartbeat: boolean?, move: (() -> Vector3)? }): Handle
	local move: () -> Vector3 = if ctx.move then ctx.move else moveVector()
	-- one look a frame: is the body this player holds on a lounge seat, and is the player moving? (true: got up)
	local function step(): boolean
		local body = ctx.current()
		local hum = body and body:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		if hum == nil or seat == nil or seat:GetAttribute(LoungeClassic.SEAT_ATTRIBUTE) == nil then
			return false
		end
		local v = move()
		if LoungeClassic.standUp(v.X, v.Z, false) then
			hum.Jump = true -- (the engine's own way off a Seat, as the jump key)
			return true
		end
		return false
	end
	local conn: RBXScriptConnection? = nil
	if ctx.heartbeat ~= false then
		conn = game:GetService("RunService").Heartbeat:Connect(function()
			step()
		end)
	end
	return {
		step = step,
		stop = function()
			if conn then
				conn:Disconnect()
			end
		end,
	}
end

return SeatGetUp
