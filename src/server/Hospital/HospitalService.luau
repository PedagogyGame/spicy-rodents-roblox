--!strict
-- ServerScriptService.Server.Hospital.HospitalService
-- Admissions, stations, the disinfect loop, fetch tasks, performance, upgrades.
-- Interface (BUILD_PLAN §1.4): admit, startDisinfect, fetch.offer/pick/deliver, performance, upgrade
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local HospitalService = {}

HospitalService.__skeleton = true

return HospitalService
