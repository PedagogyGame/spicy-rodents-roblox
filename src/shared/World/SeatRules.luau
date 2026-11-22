--!strict
-- ReplicatedStorage.Shared.World.SeatRules
-- Getting up from a seat a person sits on (owner D32, 2026-11-22, THE GILDED ACORN: sitting down "traps you and you
-- can't actually leave... make sure that when we're sitting down, we can get back up with another button push").
-- A seat a person may sit on and get up from (the lounge's 33, a lawn chair) carries STAND_ATTRIBUTE: where its sitter
-- stands when they get up (the feet, in the seat's own frame: clear of the chair, the stool, the booth's table). The
-- engine's own way off a Seat (a jump on the sitting client) cannot be trusted with them: they are anchored, and the
-- jump of a body welded to an anchored part may never reach the server, which made the SeatWeld; and in the lounge the
-- seat key (R) pressed again sat the person on the next stool instead. So getting up is the server's
-- (Server/World/SeatStand, PlayNet.StandUp): the weld goes, the body stands at that spot, and for GRACE seconds the same
-- press cannot sit them down again. The client (Client/World/SeatGetUp) asks with any of KEYS (the seat key again,
-- the jump key, the gamepad's A or Y), a move of the stick or W A S D, or the touch screen's STAND button.
-- The vehicles' seats and the sky lift's are not these: E gets out of a vehicle (Server/Actors/DeviceService), and
-- the sky lift's cabin takes its riders to the platform.
-- Interface: STAND_ATTRIBUTE; REMOTE; GRACE; REPEAT; KEYS; standKey(keyName) -> boolean; standPoint(px, pz, lookX,
--   lookZ, ox, oz) -> x, z (the stand spot's ground position from a seat's position and facing and its offset)
-- Pure. No side effects on require.

local SeatRules = {}

SeatRules.STAND_ATTRIBUTE = "StandOffset" -- Vector3 on a Seat: its sitter's feet when they stand (seat frame)
SeatRules.REMOTE = "StandUp" -- ReplicatedStorage.PlayNet RemoteEvent: the sitter asks to stand
SeatRules.GRACE = 0.6 -- seconds after getting up in which a seat's prompt does not sit the same person again
SeatRules.REPEAT = 0.3 -- seconds between the client's asks while a key is held or the stick pushed

-- the keys that get a seated person up: R (the lounge's seat key, owner "another button push"), Space and the
-- gamepad's A (the jump), the gamepad's Y (the seat key on a pad)
SeatRules.KEYS = table.freeze({ R = true, Space = true, ButtonA = true, ButtonY = true })

function SeatRules.standKey(keyName: string): boolean
	return SeatRules.KEYS[keyName] == true
end

-- The stand spot on the ground from a seat at (px, pz) facing (lookX, lookZ) (level) and the offset (ox, oz) in the
-- seat's frame (X right, Z back, as a Roblox CFrame): right = (-lookZ, lookX), back = (-lookX, -lookZ).
function SeatRules.standPoint(
	px: number,
	pz: number,
	lookX: number,
	lookZ: number,
	ox: number,
	oz: number
): (number, number)
	return px - lookZ * ox - lookX * oz, pz + lookX * ox - lookZ * oz
end

return SeatRules
