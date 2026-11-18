--!strict
-- ReplicatedStorage.Shared.Net.Schemas
-- THE client-server surface in one file (BUILD_PLAN §1.6). Each remote: direction, reliability, the
-- inbound token-bucket rate (C->S only), and the payload schema (Util/Schema) or a buffer layout
-- (Util/BufferCodec). Net refuses to fire or receive anything not declared here. Pure data.
-- The verbs of Minigame.Input are the minigame registry's (Minigames/Games.verbs: the service's own, the common
-- ones, and whatever each game's Spec lists): a new game's verbs reach the wire by being in its Spec.
-- Interface: REMOTES { [name] = Def }; ACTION_VERBS; layouts MotorState, VehiclePose

local Games = require("../Minigames/Games")
local BufferCodec = require("../Util/BufferCodec")
local Schema = require("../Util/Schema")

export type Def = {
	dir: "c2s" | "s2c",
	reliable: boolean,
	rate: number?, -- tokens per second (C->S)
	burst: number?, -- bucket size (default 2 x rate, at least 2)
	payload: Schema.Schema?, -- table payloads
	layout: BufferCodec.Layout?, -- buffer payloads
	devOnly: boolean?,
}

local Schemas = {}

-- stylua: ignore
Schemas.ACTION_VERBS = {
	"Pounce", "Feint", "Strike", "Kick", "Leap", "Interact", "Stink", "Lunge", "Graze", "Mark", "Siren",
	"EnterVehicle", "ExitVehicle", "Launch", "Dock", "Ticket", "Treat", "Fetch", "Choose", "Backup", "Buy",
	"Contribute", "Wish", "Equip", "UseItem", "Throw", "Taunt", "Report", "Gig", "Mischief", "Board", "Alight",
	"Sit", "Vote",
}

-- 38 bytes (§1.6: "seq, client time, mode, routeId (u16), s (u16 quantised), dir, pos, vel").
Schemas.MotorState = BufferCodec.layout({
	{ name = "seq", kind = "u32" },
	{ name = "clientTime", kind = "f32" },
	{ name = "mode", kind = "u8" },
	{ name = "routeId", kind = "u16" },
	{ name = "s", kind = "q16", lo = 0, hi = 1 },
	{ name = "dir", kind = "i8" },
	{ name = "px", kind = "f32" },
	{ name = "py", kind = "f32" },
	{ name = "pz", kind = "f32" },
	{ name = "vx", kind = "f32" },
	{ name = "vy", kind = "f32" },
	{ name = "vz", kind = "f32" },
})

-- 13 bytes per vehicle (§1.6 VehiclePoses): yaw and speed pre-quantised to bytes by the sender.
Schemas.VehiclePose = BufferCodec.layout({
	{ name = "id", kind = "u16" },
	{ name = "x", kind = "f32" },
	{ name = "z", kind = "f32" },
	{ name = "yaw", kind = "u8" },
	{ name = "speed", kind = "u8" },
	{ name = "bits", kind = "u8" },
})

local id = Schema.str({ max = 64 })
local args = Schema.opt(Schema.arr(
	Schema.custom(function(v: any): boolean
		local t = type(v)
		if t == "number" then
			return v == v and v ~= math.huge and v ~= -math.huge
		end
		return (t == "string" and #v <= 200) or t == "boolean"
	end, "scalar argument"),
	8
))

-- stylua: ignore
Schemas.REMOTES = {
	["Motor.State"] = { dir = "c2s", reliable = false, rate = 20, burst = 30, layout = Schemas.MotorState },
	Action = { dir = "c2s", reliable = true, rate = 10, payload = Schema.rec({ verb = Schema.enum(Schemas.ACTION_VERBS), target = Schema.opt(id), args = args }) },
	["Minigame.Input"] = { dir = "c2s", reliable = true, rate = 20, payload = Schema.rec({ gameId = id, seat = Schema.num({ min = 1, max = 16, int = true }),
		verb = Schema.enum(Games.verbs()), args = args }) },
	["Offer.Reply"] = { dir = "c2s", reliable = true, rate = 1, burst = 2, payload = Schema.rec({ offerId = id, choice = Schema.enum({ "accept", "deer", "fox", "stay" }) }) },
	["Lab.Command"] = { dir = "c2s", reliable = true, rate = 5, devOnly = true, payload = Schema.rec({ cmd = Schema.str({ max = 32 }), args = args }) },
	["Possession.Granted"] = { dir = "s2c", reliable = true },
	["Possession.Revoked"] = { dir = "s2c", reliable = true },
	Correction = { dir = "s2c", reliable = true },
	ActionResult = { dir = "s2c", reliable = true },
	Telegraph = { dir = "s2c", reliable = false },
	VehiclePoses = { dir = "s2c", reliable = false },
	["Hud.State"] = { dir = "s2c", reliable = true },
	["Map.Markers"] = { dir = "s2c", reliable = true },
	Radar = { dir = "s2c", reliable = false },
	Notify = { dir = "s2c", reliable = true },
	["Offer.Show"] = { dir = "s2c", reliable = true },
	["Minigame.State"] = { dir = "s2c", reliable = true },
	["Outbreak.Start"] = { dir = "s2c", reliable = true },
	["Clock.Rate"] = { dir = "s2c", reliable = true },
	["Lab.State"] = { dir = "s2c", reliable = true, devOnly = true },
} :: { [string]: Def }

-- Paintball's own remotes (the one game that has any: Shared/Minigames/Paintball/Wire says why) are declared
-- with the rest of its contract, with their rates and byte layouts, and merged here: Paintball.Move and
-- Paintball.Fire (client to server), Paintball.Snap, Paintball.Shot and Splat (server to client).
for name, def in require("../Minigames/Paintball/Wire").REMOTES do
	Schemas.REMOTES[name] = def
end

return Schemas
