--!strict
-- Shared/Net/Net + Schemas (BUILD_PLAN §1.6, §4.4 #1): only declared remotes exist; inbound payloads
-- are schema-checked and token-bucket limited; rejects are counted and dropped, never thrown; buffer
-- streams round-trip at the declared sizes.
local BufferCodec = require("@shared/Util/BufferCodec")
local Log = require("@shared/Util/Log")
local Net = require("@shared/Net/Net")
local Schemas = require("@shared/Net/Schemas")

local function loopback()
	local sent = {}
	local players = { { UserId = 1, x = 0, z = 0 }, { UserId = 2, x = 100, z = 0 }, { UserId = 3, x = 10, z = 5 } }
	local transport = {
		send = function(p, name, payload)
			table.insert(sent, { to = if p then p.UserId else "all", name = name, payload = payload })
		end,
		players = function()
			return players
		end,
		positionOf = function(p)
			return p.x, p.z
		end,
		isDev = function(p)
			return p.UserId == 1
		end,
	}
	return transport, sent, players
end

return function(t)
	t.test("schemas: every remote has a direction; C->S remotes have a payload or layout", function()
		for name, d in Schemas.REMOTES do
			t.truthy(d.dir == "c2s" or d.dir == "s2c", name)
			if d.dir == "c2s" then
				t.truthy(d.payload ~= nil or d.layout ~= nil, name)
				t.truthy((d.rate or 0) > 0, name)
			end
		end
		t.eq(Schemas.MotorState.size, 38) -- §1.6 "about 40 bytes"
		t.eq(Schemas.VehiclePose.size, 13) -- §1.6 "about 13 bytes each"
		t.eq(#Schemas.ACTION_VERBS, 34)
	end)

	t.test("receive: valid actions dispatch; bad ones are dropped and counted", function()
		local rec = Log.capture()
		local tr = loopback()
		local net = Net.new(tr, {
			clock = function()
				return 0
			end,
		})
		local got = {}
		net:on("Action", function(_p, payload)
			table.insert(got, payload.verb)
		end)
		local p = { UserId = 2 }
		t.truthy(net:receive(p, "Action", { verb = "Kick" }, 0))
		t.deepEq({ net:receive(p, "Action", { verb = "Fly" }, 0) }, { false, "schema" })
		t.deepEq({ net:receive(p, "Action", { verb = "Kick", args = { 0 / 0 } }, 0) }, { false, "schema" })
		t.deepEq({ net:receive(p, "Nope", {}, 0) }, { false, "unknown remote" })
		t.deepEq({ net:receive(p, "Notify", {}, 0) }, { false, "unknown remote" }) -- S->C only
		t.deepEq({ net:receive(p, "Lab.Command", { cmd = "become" }, 0) }, { false, "dev only" })
		t.truthy(net:receive({ UserId = 1 }, "Lab.Command", { cmd = "become", args = { "rodent" } }, 0))
		t.deepEq(got, { "Kick" })
		Log.setSink()
		t.truthy(#rec >= 1)
	end)

	t.test("token bucket: burst then rate; refills with time; per player", function()
		Log.capture()
		local net = Net.new((loopback()))
		local p, q = { UserId = 5 }, { UserId = 6 }
		local okCount = 0
		for _ = 1, 40 do
			if net:receive(p, "Action", { verb = "Leap" }, 0) then
				okCount += 1
			end
		end
		t.eq(okCount, 20) -- burst = 2 x 10/s
		t.truthy(net:receive(q, "Action", { verb = "Leap" }, 0))
		t.falsy(net:receive(p, "Action", { verb = "Leap" }, 0.05))
		t.truthy(net:receive(p, "Action", { verb = "Leap" }, 0.1))
		t.truthy((net:stats().rejected.rate or 0) >= 20)
		Log.setSink()
	end)

	t.test("handler errors are caught", function()
		Log.capture()
		local net = Net.new((loopback()))
		net:on("Action", function()
			error("bug")
		end)
		t.deepEq({ net:receive({ UserId = 1 }, "Action", { verb = "Kick" }, 0) }, { false, "handler error" })
		Log.setSink()
	end)

	t.test("Motor.State: buffer of the right size decodes; wrong size or NaN is dropped", function()
		Log.capture()
		local net = Net.new((loopback()))
		local got
		net:on("Motor.State", function(_p, s)
			got = s
		end)
		local b = BufferCodec.encode(Schemas.MotorState, { seq = 7, routeId = 12, s = 0.5, px = 1, py = 2, pz = 3 })
		t.truthy(net:receive({ UserId = 1 }, "Motor.State", b, 0))
		t.eq(got.seq, 7)
		t.eq(got.routeId, 12)
		t.near(got.s, 0.5, 1e-4)
		t.deepEq({ net:receive({ UserId = 1 }, "Motor.State", buffer.create(10), 0) }, { false, "bad buffer" })
		local bad = BufferCodec.encode(Schemas.MotorState, { seq = 1, px = 0 / 0 })
		buffer.writef32(bad, 14, 0 / 0) -- px
		t.deepEq({ net:receive({ UserId = 1 }, "Motor.State", bad, 0) }, { false, "non-finite" })
		Log.setSink()
	end)

	t.test("fire, fireAll, fireNear, stream; undeclared names error", function()
		local tr, sent = loopback()
		local net = Net.new(tr)
		net:fire({ UserId = 1 }, "Notify", { text = "hi" })
		net:fireAll("Clock.Rate", { rate = 40 })
		t.eq(net:fireNear(0, 0, 20, "Telegraph", { kind = "kick" }), 2)
		local b = net:stream(nil, "VehiclePoses", { { id = 1, x = 5, z = 6 }, { id = 2, x = 7, z = 8 } })
		t.eq(buffer.len(b), 26)
		local back = Net.decodeStream(Schemas.VehiclePose, b)
		t.eq(back[2].id, 2)
		t.eq(back[2].z, 8)
		t.eq(#sent, 5)
		t.eq(net:stats().bytes, 26)
		t.fails(function()
			net:fire({ UserId = 1 }, "Undeclared", {})
		end)
		t.fails(function()
			net:fire({ UserId = 1 }, "Action", {})
		end)
	end)
end
