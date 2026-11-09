--!strict
-- ReplicatedStorage.Shared.Traffic.Boxes
-- The logical box of every vehicle kind (traffic.md §2, §9; BUILD_PLAN D9), in studs.
-- Interface: Boxes.BOXES { [kind] = {width, length, height} }, Boxes.get(kind), Boxes.FATAL { [kind] = bool }
--
-- One table for the fatal test (Server/Traffic/SweptCollision), the AI fleet (Traffic/AICarMotor) and the
-- placeholder vehicles (Traffic/VehiclePuppet): the puppet body IS the logical box, so what a player sees
-- is exactly what kills (W1 #9 "placeholder vehicles at the true logical boxes"). HTML units x 2.5.
-- Motorcycles are not in the v5.4 fatal fleet (traffic.md §5.12) and stay out of it here (FATAL false).

local Units = require("../Config/Units")

export type Box = { width: number, length: number, height: number }

local st = Units.st

local Boxes = {}

local function box(w: number, l: number, h: number): Box
	return table.freeze({ width = st(w), length = st(l), height = st(h) })
end

-- stylua: ignore
Boxes.BOXES = table.freeze({
	sedan = box(2.35, 4.45, 2.04),          -- makeCar (traffic §2.1, L6081, L15764)
	patrol_car = box(2.35, 4.45, 2.04),     -- makeCar body (§2.2)
	ambulance = box(2.35, 4.45, 2.04),      -- makeCar body (§5.8, §5.9)
	delivery_van = box(3.0, 5.9, 3.65),     -- §2.3
	ice_cream_van = box(3.35, 6.55, 3.58),  -- §2.4
	trolley = box(3.5, 11.0, 4.12),         -- §2.5
	dump_truck = box(3.35, 8.9, 4.12),      -- §2.6
	rv = box(3.2, 8.7, 4.3),                -- §2.6
	cart = box(1.6, 3.0, 1.9),              -- brief v2 golf cart (Q8), placeholder until VehicleKinds
	motorcycle = box(0.7, 2.1, 1.5),        -- §2.7 (not fatal)
}) :: { [string]: Box }

Boxes.FATAL = table.freeze({
	sedan = true,
	patrol_car = true,
	ambulance = true,
	delivery_van = true,
	ice_cream_van = true,
	trolley = true,
	dump_truck = true,
	rv = true,
	cart = true,
	motorcycle = false,
}) :: { [string]: boolean }

function Boxes.get(kind: string): Box
	return Boxes.BOXES[kind] or error(`Boxes: unknown vehicle kind {kind}`)
end

return Boxes
