--!strict
-- probe (not committed): the honest motor's E+Space climb up every open trunk of the town (W and up held, Space on the
-- trunk, E and Space every `every` frames in the air), sent every `per` frames: violations by code
local process = require("@lune/process")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local TestWorld = require("@tests/cheat/TestWorld")
local MovementService = require("@server/Movement/MovementService")
local SquirrelWire = require("@shared/Movement/SquirrelWire")

type State = SquirrelMotor.State

local function list(k: string, d: { number }): { number }
	local s = process.env[k]
	if s == nil or s == "" then
		return d
	end
	local out = {}
	for w in string.gmatch(s, "[^,]+") do
		table.insert(out, tonumber(w) :: number)
	end
	return out
end

return function(t)
	t.test("trunk climbs", function()
		local tw = TestWorld.build({ boxes = {} })
		local vworld = ValidatorWorld.build(tw, {
			wall = function()
				return false
			end,
			down = function(_ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
				return oy >= 0 and math.min(oy, oy + dy) <= 0
			end,
		})
		local reg = tw.registry
		local trunks = {}
		for _, r in reg:all() do
			if r.kind == "trunk" and r.enclosure == nil then
				local a, b = reg:pointAt(r, 0), reg:pointAt(r, 1)
				if math.abs(b.y - a.y) > 12 then
					table.insert(trunks, r)
				end
			end
		end
		table.sort(trunks, function(a: any, b: any)
			return a.id < b.id
		end)
		local MAXT = tonumber(process.env.MAXT or "1000") :: number
		local EVERY = list("EVERY", { 2, 3, 4, 6 })
		local PER = list("PER", { 3, 6, 15 })
		local YAWS = tonumber(process.env.YAWS or "4") :: number
		local SECS = tonumber(process.env.SECS or "2.5") :: number
		local total, judged, runs = 0, 0, 0
		local codes: { [string]: number } = {}
		local worst: { string } = {}
		local perTrunk: { [number]: number } = {}
		local snaps = 0
		local firstSnaps: { string } = {}
		local snapWhy: { [string]: number } = {}
		local ONLY = tonumber(process.env.ONLY or "")
		local YONLY = tonumber(process.env.YONLY or "")
		for ti, r in trunks do
			if ti > MAXT then
				break
			end
			if ONLY and r.id ~= ONLY then
				continue
			end
			local a, b = reg:pointAt(r, 0), reg:pointAt(r, 1)
			local t0 = if a.y < b.y then 0.03 else 0.97
			for _, every in EVERY do
				for _, per in PER do
					for yi = 0, YAWS - 1 do
						if YONLY and yi ~= YONLY then
							continue
						end
						runs += 1
						local yaw = yi * 2 * math.pi / YAWS
						local v = MoveValidator.new(vworld)
						local seq = 0
						local p = reg:pointAt(r, t0)
						local s = SquirrelMotor.new(p.x, p.y, p.z)
						s.routeId, s.railT, s.grounded, s.clock, s.yaw = r.id, t0, false, 0, yaw
						local sent: { State } = {}
						local function feed(): any
							table.insert(sent, SquirrelMotor.clone(s))
							seq += 1
							return v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, s.clock + 1)
						end
						feed()
						for f = 1, math.floor(SECS * 60) do
							local i = SquirrelMotor.idleInput(yaw)
							i.fw, i.sprint, i.up = 1, true, 1
							i.leap = s.routeId ~= nil or (not s.grounded and f % every == 0)
							i.grab = s.routeId == nil and not s.grounded and f % every == 0
							SquirrelMotor.step(s, i, 1 / 60, tw)
							if process.env.FTRACE then
								print(string.format("        f %d (%.2f, %.2f, %.2f) v (%.1f, %.1f, %.1f) %s %s", f, s.x, s.y, s.z, s.vx, s.vy, s.vz, tostring(s.routeId), if s.grounded then "G" else "A"))
							end
							if f % per == 0 then
								local res = feed()
								if process.env.FTRACE then
									local hl = v._actors.a.last
									print(string.format("          HELD y %.2f vy %.2f (sent y %.2f vy %.2f) lastGrab %s", hl.y, hl.vy, s.y, s.vy, tostring(v._marks.a.lastGrab)))
									for _, x in res.violations do
										print("          VIOL " .. x.code .. " " .. x.detail)
									end
								end
								judged += 1
								for _, x in res.violations do
									total += 1
									perTrunk[r.id] = (perTrunk[r.id] or 0) + 1
									local c = x.code or "?"
									codes[c] = (codes[c] or 0) + 1
									if #worst < 15 then
										table.insert(
											worst,
											`trunk {r.id} every {every} per {per} yaw {yi} f {f} y {string.format("%.1f", s.y)}: {c} {x.detail}`
										)
									end
								end
							end
						end
						if process.env.SNAP then
							local val = MoveValidator.new(vworld)
							local snappedThis = false
							local at = { x = sent[1].x, y = sent[1].y, z = sent[1].z }
							local ms = MovementService.new({
								validator = val,
								enforce = true,
								poseOf = function(_a: any): (number, number, number)
									return at.x, at.y, at.z
								end,
								engine = {
									correct = function(_id: any, msg: any)
										if msg.snap then
											if not snappedThis then
												snaps += 1
												snapWhy[msg.why] = (snapWhy[msg.why] or 0) + 1
												snappedThis = true
												if #firstSnaps < (tonumber(process.env.NSNAP or "12") :: number) then
													table.insert(firstSnaps, `trunk {r.id} every {every} per {per} yaw {yi}: {msg.why}`)
												end
											end
										end
									end,
									pin = function(): boolean
										return true
									end,
									hold = function() end,
								},
							})
							ms:onHandoff({ id = "a", species = "squirrel" }, nil, "possess")
							for q, st in sent do
								local now = st.clock + 100
								local _, e, dec = SquirrelWire.decode(SquirrelWire.encode(q, ms:epochOf("a"), SquirrelMotor.serialize(st)))
								ms:packet("a", "squirrel", { seq = q, epoch = e, snapshot = dec }, now)
								at.x, at.y, at.z = st.x, st.y, st.z
								ms:watch("a", st.x, st.y, st.z, now)
							end
						end
					end
				end
			end
		end
		local sw = {}
		for k, n in snapWhy do
			table.insert(sw, `{k} {n}`)
		end
		print(`      climbs snapped {snaps} [{table.concat(sw, ", ")}]`)
		for _, w in firstSnaps do
			print("        snap: " .. w)
		end
		local l = {}
		for k, n in codes do
			table.insert(l, `{k} {n}`)
		end
		local pt = {}
		for id, n in perTrunk do
			table.insert(pt, `{id}:{n}`)
		end
		print(`      {math.min(#trunks, MAXT)} trunks, {runs} climbs: violations {total} in {judged} packets [{table.concat(l, ", ")}] trunks [{table.concat(pt, " ")}]`)
		for _, w in worst do
			print("        " .. w)
		end
	end)
end
