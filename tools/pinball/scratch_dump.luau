-- scratch: dump a table def (and an optional ball trace) as JSON for the picture script
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Layout = require("../../src/shared/Minigames/Pinball/Layout")
local Physics = require("../../src/shared/Minigames/Pinball/Physics")

local name = process.args[1] or "TableAcorn"
local out = process.args[2] or "/tmp/dump.json"
local mode = process.args[3] or "none"
local T = require("../../src/shared/Minigames/Pinball/" .. name) :: any
local def = T.def
local c = Layout.compile(def)
local traces = {}
if mode == "plunge" then
	for _, pull in { 0.1, 0.3, 0.5, 0.7, 0.9, 1.0 } do
		local s = Physics.new(c, 1)
		local p = def.plunger
		local bi = Physics.addBall(s, p.x, p.y, 0, 0)
		local ev = {}
		for _ = 1, 120 do
			Physics.step(c, s, false, false, ev)
		end
		local b = s.balls[bi]
		Physics.launch(s, bi, p.vMin + (p.vMax - p.vMin) * pull)
		local tr = {}
		for i = 1, 240 * 20 do
			Physics.step(c, s, false, false, ev)
			if i % 4 == 0 then
				table.insert(tr, b.x)
				table.insert(tr, b.y)
			end
			if b.mode == Physics.GONE or b.asleep then
				break
			end
		end
		table.insert(traces, tr)
	end
end
if mode == "fan" then
	local function clone<T>(v: T): T
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v :: any do
			out[k] = clone(x)
		end
		return out :: any
	end
	for side = 1, 2 do
		local s0 = Physics.new(c, 1)
		local ev = {}
		local x0 = if side == 1 then 0.25 else 2 * Layout.XC - 0.25
		Physics.addBall(s0, x0, 1.3, 0, 0)
		for _ = 1, 240 * 6 do
			Physics.step(c, s0, side == 1, side == 2, ev)
			if s0.balls[1].asleep then
				break
			end
		end
		for d = 40, 230, 12 do
			local s = clone(s0)
			local b = s.balls[1]
			for _ = 1, d do
				Physics.step(c, s, false, false, ev)
			end
			local tr = {}
			for i = 1, 300 do
				Physics.step(c, s, side == 1, side == 2, ev)
				if i % 2 == 0 then
					table.insert(tr, b.x)
					table.insert(tr, b.y)
				end
				if b.mode ~= 0 then
					break
				end
			end
			table.insert(traces, tr)
		end
	end
end
local d = {
	walls = def.walls,
	posts = def.posts,
	bumpers = def.bumpers,
	slings = def.slings,
	flippers = def.flippers,
	targets = def.targets,
	sensors = def.sensors,
	gates = def.gates,
	saucers = def.saucers,
	rails = def.rails,
	lamps = def.lamps,
	plunger = def.plunger,
	traces = traces,
}
fs.writeFile(out, serde.encode("json", d))
print("wrote", out)
