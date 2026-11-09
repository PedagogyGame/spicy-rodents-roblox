--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Camera.CameraPolicy
-- Which camera mode a body, vehicle or zone demands (BUILD_PLAN §1.4 Camera/CameraPolicy, §4.4 #5;
-- brief v2 §14): animals third person (no first person); humans third person with a free
-- first-person toggle; vehicles and the gondola first person on entry with the toggle kept;
-- LockFirstPerson zones (paintball arena, both lounges) locked first person; the squirrel chase
-- forward-locked; the drone feed while piloting; the outbreak pull-out overrides everything.
-- Pure (no Instances), so Lune tests it; CameraRig applies the result.
-- Interface: modeFor(ctx) -> Decision; MODES
-- No side effects on require.

export type Ctx = {
	species: string?, -- the possessed body's species ("human", "squirrel", "fox", "deer"); nil = none
	vehicle: string?, -- VehicleKinds id while driving, or "gondola"
	drone: boolean?, -- piloting the drone
	zone: string?, -- "lockFirstPerson" inside the arena and the lounges
	chase: boolean?, -- squirrel chase lock (a pursuer is on this squirrel)
	outbreak: boolean?, -- the outbreak cinematic's pull-out
	firstPersonToggle: boolean?, -- the player's toggle (V); honoured only where allowed
}

export type Decision = {
	mode: "overview"
		| "humanThird"
		| "humanFirst"
		| "animalThird"
		| "chaseLock"
		| "vehicleFirst"
		| "vehicleThird"
		| "lockFirst"
		| "drone"
		| "outbreak",
	firstPerson: boolean,
	toggleAllowed: boolean,
	subject: "body" | "vehicle" | "drone" | "none",
}

local CameraPolicy = {}

CameraPolicy.MODES = table.freeze({
	"overview",
	"humanThird",
	"humanFirst",
	"animalThird",
	"chaseLock",
	"vehicleFirst",
	"vehicleThird",
	"lockFirst",
	"drone",
	"outbreak",
})

function CameraPolicy.modeFor(ctx: Ctx): Decision
	if ctx.outbreak then
		return { mode = "outbreak", firstPerson = false, toggleAllowed = false, subject = "none" }
	end
	if ctx.drone then
		return { mode = "drone", firstPerson = true, toggleAllowed = false, subject = "drone" }
	end
	if ctx.species == nil then
		return { mode = "overview", firstPerson = false, toggleAllowed = false, subject = "none" }
	end
	if ctx.species == "human" then
		if ctx.zone == "lockFirstPerson" then
			return { mode = "lockFirst", firstPerson = true, toggleAllowed = false, subject = "body" }
		end
		if ctx.vehicle then
			-- first person on entry; the toggle flips to the chase view behind the vehicle
			if ctx.firstPersonToggle == false then
				return { mode = "vehicleThird", firstPerson = false, toggleAllowed = true, subject = "vehicle" }
			end
			return { mode = "vehicleFirst", firstPerson = true, toggleAllowed = true, subject = "vehicle" }
		end
		if ctx.firstPersonToggle then
			return { mode = "humanFirst", firstPerson = true, toggleAllowed = true, subject = "body" }
		end
		return { mode = "humanThird", firstPerson = false, toggleAllowed = true, subject = "body" }
	end
	-- animals: third person only; the squirrel chase locks the camera forward
	if ctx.chase and (ctx.species == "squirrel" or ctx.species == "rodent") then
		return { mode = "chaseLock", firstPerson = false, toggleAllowed = false, subject = "body" }
	end
	return { mode = "animalThird", firstPerson = false, toggleAllowed = false, subject = "body" }
end

return CameraPolicy
