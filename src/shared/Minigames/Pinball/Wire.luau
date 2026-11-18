--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Wire
-- What the pinball glue sends besides the input log itself (the log is InputLog.pack's three arguments).
-- A whole replay (Replay.clone: the machine, its physics, every rule sheet) crosses the wire as a SNAPSHOT when
-- a copy has to be put right: a watcher who walks up in the middle of a game, the player's own machine when the
-- server says it drifted, everyone after the server played a ball by itself (a skip, a retired player, a ball
-- that fell too far behind: Replay's epoch). A RemoteEvent carries only plain data: lists without gaps and
-- records with string keys, never the two mixed. A replay is nearly that already; encode() makes sure: a dense
-- list stays a list, a record keyed by strings stays a record, and any other table (sparse, mixed, keyed by
-- numbers that are not 1..n) is carried as { [KEYS] = keys, [VALS] = values }. decode() undoes it, so
-- decode(encode(r)) is the same replay, bit for bit (numbers travel as doubles).
-- Pure; Lune-tested (tests/unit/pinball_wire.spec.luau).
-- Interface: encode(value) -> plain data; decode(plain) -> value; snapshot(replay) -> plain (a clone, encoded);
--   restore(plain) -> Replay.State? (nil if it is not a snapshot of a known table); KEYS, VALS

local Replay = require("./Replay")
local Tables = require("./Tables")

local Wire = {}

Wire.KEYS = "~k"
Wire.VALS = "~v"

local function kindOf(t: { [any]: any }): string
	local n = #t
	local count = 0
	local strings = true
	for k in t do
		count += 1
		if type(k) ~= "string" or k == Wire.KEYS or k == Wire.VALS then
			strings = false
		end
	end
	if count == 0 then
		return "list"
	end
	if count == n then
		return "list"
	end
	if strings and n == 0 then
		return "record"
	end
	return "pairs"
end

function Wire.encode(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local kind = kindOf(v)
	if kind == "list" then
		local out = table.create(#v)
		for i = 1, #v do
			out[i] = Wire.encode(v[i])
		end
		return out
	elseif kind == "record" then
		local out = {}
		for k, x in v do
			out[k] = Wire.encode(x)
		end
		return out
	end
	local keys, vals = {}, {}
	for k, x in v do
		table.insert(keys, k)
		table.insert(vals, Wire.encode(x))
	end
	return { [Wire.KEYS] = keys, [Wire.VALS] = vals }
end

function Wire.decode(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local keys, vals = v[Wire.KEYS], v[Wire.VALS]
	if type(keys) == "table" and type(vals) == "table" then
		local out = {}
		for i, k in keys do
			out[k] = Wire.decode(vals[i])
		end
		return out
	end
	local out = {}
	for k, x in v do
		out[k] = Wire.decode(x)
	end
	return out
end

function Wire.snapshot(r: Replay.State): any
	return Wire.encode(Replay.clone(r))
end

-- restore(plain): the replay a snapshot stands for, or nil when it is not one (wrong shape, unknown table).
function Wire.restore(plain: any): Replay.State?
	if type(plain) ~= "table" then
		return nil
	end
	local r = Wire.decode(plain)
	if type(r.id) ~= "string" or Tables.get(r.id) == nil or type(r.m) ~= "table" or type(r.tick) ~= "number" then
		return nil
	end
	return r :: Replay.State
end

return Wire
