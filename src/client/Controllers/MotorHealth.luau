--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Controllers.MotorHealth
-- The client's own counters for the movement diagnostics (UI/MoveDiagPanel, the owner's F8 panel): how many motor
-- packets went up (PossessionClient's send), and the errors a controller's frame step threw (Controllers/BodyDriver
-- catches them; a step that fails every frame is a body that does not move, and a warning a frame is itself a lag):
-- the count, the first one's text, and whether to print this one (at most one line every WARN_EVERY seconds).
-- Also the force that cancels gravity (antiGravityForce): the assembly's mass reads as infinite while the server
-- holds the body anchored, and a force sized from that flings the body the moment it is let go.
-- Interface: sent(); fault(err, now?) -> boolean (print it?); read() -> { sent, errors, firstError? };
--   reset(); finiteMass(assemblyMass, partsMass) -> number; WARN_EVERY; TEXT
-- Pure. No side effects on require.

local MotorHealth = {}

MotorHealth.WARN_EVERY = 5
MotorHealth.TEXT = 160

local state = { sent = 0, errors = 0, firstError = nil :: string?, warnedAt = -math.huge }

function MotorHealth.sent()
	state.sent += 1
end

-- fault(err, now?): a controller's step failed -> whether to print it (the first, then one every WARN_EVERY seconds)
function MotorHealth.fault(err: any, now: number?): boolean
	state.errors += 1
	if state.firstError == nil then
		state.firstError = string.sub(tostring(err), 1, MotorHealth.TEXT)
	end
	local t = now or os.clock()
	if t - state.warnedAt >= MotorHealth.WARN_EVERY then
		state.warnedAt = t
		return true
	end
	return false
end

function MotorHealth.read(): { sent: number, errors: number, firstError: string? }
	return { sent = state.sent, errors = state.errors, firstError = state.firstError }
end

function MotorHealth.reset()
	state.sent, state.errors, state.firstError, state.warnedAt = 0, 0, nil, -math.huge
end

-- finiteMass(assemblyMass, partsMass): the mass the anti-gravity force is sized from. The engine gives an anchored
-- assembly an infinite AssemblyMass (a body the server holds: the validator's pin or hold, the sky lift, the
-- telescope); then the parts' own mass (`partsMass`: the root's GetMass and its connected parts'), else none.
function MotorHealth.finiteMass(assemblyMass: any, partsMass: any): number
	local function ok(m: any): boolean
		return type(m) == "number" and m == m and m > 0 and m < math.huge
	end
	if ok(assemblyMass) then
		return assemblyMass
	end
	return if ok(partsMass) then partsMass else 0
end

return MotorHealth
