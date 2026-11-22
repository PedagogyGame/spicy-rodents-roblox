--!strict
-- ReplicatedStorage.Shared.Players.IdleRules
-- Idle players are removed (owner D38, 2026-11-22: "15 minutes of inactivity, should kick you out, for any player, the
-- spicy rodent, 8 minutes"). Inactivity is no input from the player: no key, mouse, touch or gamepad press, no camera
-- turn, no chat, no click on the screen's buttons. Sitting (a seat, a nook's ledge), playing a minigame or driving
-- counts as active while the player still presses things; sitting alone does not. The server decides
-- (Server/Players/IdleService), from:
--   * its own evidence: a remote the player fires on purpose (the PlayNet presses, the Net remotes in INTENT, chat)
--     and a held squirrel's motor packets that show a key down or a click (motorActive);
--   * the client's "still here" ping (Client/Input/StillHere): at most one every C.pingGap seconds, and only when
--     there was input since the last one (pinger, pingDue); while the warning shows, the first input pings at once.
--   A modified client that sends fake pings keeps itself in (accepted: it costs the server one number a ping); one
--   that sends nothing is removed, whatever its body does.
-- The limit is the player's current role's (Tunables idle.anyone; idle.spicyRodent for the player who is the Spicy
-- Rodent now): a role change mid-idle moves the limit, and the time already idle counts. A quiet notice (WORDS.warn,
-- the game's toast) shows idle.warn seconds before; any input clears it. Then Player:Kick with WORDS.kick. Roblox's own
-- 20-minute idle kick is left as it is (ours comes first: TunableMeta keeps both limits under 19 minutes). The place's
-- owner is not exempt (nothing else in the game exempts the owner from a rule of play; Config/Flags idleKick turns the
-- whole kick off).
-- Interface: limit(spicy) -> seconds; verdict(lastInput, now, spicy) -> "ok" | "warn" | "kick"; left(lastInput, now,
--   spicy) -> seconds until the kick; warnText(spicy?) -> string; kickText(spicy) -> string; motorActive(snapshot) ->
--   boolean; counts(inputType, magnitude?) -> boolean (an engine input event the client reports as input);
--   pinger() -> Pinger; input(p, now); pingDue(p, now, warned) -> boolean (true: send one now; marks it sent);
--   INTENT; WORDS; C.
-- Pure. No side effects on require.

local Tunables = require("../Config/Tunables")

local IdleRules = {}

IdleRules.C = table.freeze({
	pingGap = 20, -- seconds between the client's "still here" pings (at most)
	moveSpeed = 0.5, -- studs/s: a squirrel motor's own speed above this is a movement key held (it eases to 0 without)
	stick = 0.25, -- a gamepad stick or trigger moved past this (a resting stick's drift is not a player)
})

-- the engine's input types (Enum.UserInputType names) a phone or a desk reports by itself: never a player's input
local SENSORS = table.freeze({ Accelerometer = true, Gyro = true, None = true } :: { [string]: boolean })

IdleRules.WORDS = table.freeze({
	warn = "Still there? You'll leave the server in %s if you don't move.",
	kick = "You were away for %s, so you left the server. Come back any time!",
})

-- the Net remotes (Net/Schemas) a player fires only by pressing something: each accepted one counts as input
IdleRules.INTENT = table.freeze({
	Action = true,
	["Minigame.Input"] = true,
	["Offer.Reply"] = true,
	["Lab.Command"] = true,
} :: { [string]: boolean })

export type Verdict = "ok" | "warn" | "kick"

function IdleRules.limit(spicy: boolean): number
	return if spicy then Tunables.get("idle.spicyRodent") else Tunables.get("idle.anyone")
end

-- left: seconds of idling still allowed before the kick (0 or less: due)
function IdleRules.left(lastInput: number, now: number, spicy: boolean): number
	return IdleRules.limit(spicy) - (now - lastInput)
end

function IdleRules.verdict(lastInput: number, now: number, spicy: boolean): Verdict
	local left = IdleRules.left(lastInput, now, spicy)
	if left <= 0 then
		return "kick"
	elseif left <= Tunables.get("idle.warn") then
		return "warn"
	end
	return "ok"
end

-- "a minute", "8 minutes", "45 seconds"
local function span(seconds: number): string
	local s = math.max(1, math.floor(seconds + 0.5))
	if s % 60 == 0 then
		local m = s // 60
		return if m == 1 then "a minute" else `{m} minutes`
	end
	return if s == 1 then "a second" else `{s} seconds`
end

function IdleRules.warnText(_spicy: boolean?): string
	return string.format(IdleRules.WORDS.warn, span(Tunables.get("idle.warn")))
end

function IdleRules.kickText(spicy: boolean): string
	return string.format(IdleRules.WORDS.kick, span(IdleRules.limit(spicy)))
end

-- motorActive: a held squirrel's motor snapshot (Movement/SquirrelWire) shows the player pressing something: the
-- motor's own speed (it eases toward the walk only while a movement key is down) or a click riding in the packet
function IdleRules.motorActive(snapshot: { [string]: any }): boolean
	local speed = snapshot.moveSpeed
	if type(speed) == "number" and speed > IdleRules.C.moveSpeed then
		return true
	end
	local click = snapshot.clickSeq
	return type(click) == "number" and click ~= 0
end

-- counts: an input event (UserInputService InputBegan or InputChanged) the client counts as input: any press, a mouse
-- move or wheel (the camera turning counts: the player is there), a touch; a gamepad stick or trigger only past
-- C.stick (`magnitude`: its position's length); never the phone's own motion sensors
function IdleRules.counts(inputType: string, magnitude: number?): boolean
	if SENSORS[inputType] then
		return false
	end
	if string.sub(inputType, 1, 7) == "Gamepad" and magnitude ~= nil then
		return magnitude > IdleRules.C.stick
	end
	return true
end

-- the client's side: input since the last ping, and when the last one went
export type Pinger = { dirty: boolean, sent: number }

function IdleRules.pinger(): Pinger
	return { dirty = false, sent = -math.huge }
end

function IdleRules.input(p: Pinger, _now: number)
	p.dirty = true
end

-- pingDue: send a ping now? Only after input; at most one every C.pingGap seconds, but at once while warned (the
-- first input clears the warning). Marks it sent.
function IdleRules.pingDue(p: Pinger, now: number, warned: boolean): boolean
	if not p.dirty then
		return false
	end
	if not warned and now - p.sent < IdleRules.C.pingGap then
		return false
	end
	p.dirty = false
	p.sent = now
	return true
end

return IdleRules
