--!strict
-- ServerScriptService.Server.WorldGen.Yield
-- Long engine bakes (WorldBuild: plans, Bake.run, the checks) yield a frame about once a second so
-- the engine's no-yield script timeout (about 10 s) never fires; in Lune (no `script`) it is a no-op,
-- so the bake stays a plain synchronous function there.
-- Interface: breathe(budgetSeconds?) -> ()

local Yield = {}

local last = os.clock()

function Yield.breathe(budget: number?)
	if script ~= nil and os.clock() - last > (budget or 1) then
		task.wait()
		last = os.clock()
	end
end

return Yield
