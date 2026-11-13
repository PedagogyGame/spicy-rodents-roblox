--!strict
-- ReplicatedStorage.Shared.Minigames.Pool.Wire
-- A shot's script as TEXT, for the one message that carries it to every client (Minigame.State; kinds
-- "pool_shot" and "bumper_pool_shot"). Shot.pack makes the script a buffer (a break is about 6 KB); a
-- minigame's messages are plain tables of numbers, booleans and strings (the rule every game keeps to, and
-- what the test rig's network carries), so the buffer travels as base64: letters, digits, + and /, a third
-- longer, and nothing a remote or a log could mangle. decode() refuses anything that is not exactly a packed
-- script (Shot.unpack checks it like any other table off the wire).
-- Pure; Lune-tested (tests/unit/pool_wire.spec.luau).
-- Interface: encode(script) -> string; decode(text) -> (Shot.Script?, why?); toText(buffer) -> string;
--   fromText(text) -> buffer? (nil: not base64)

local Shot = require("./Shot")

local Wire = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local CODE: { [number]: number } = {} -- 6 bits -> the letter's byte
local VALUE: { [number]: number } = {} -- the letter's byte -> 6 bits
for i = 1, 64 do
	local byte = string.byte(ALPHABET, i)
	CODE[i - 1] = byte
	VALUE[byte] = i - 1
end
local PAD = string.byte("=")

function Wire.toText(b: buffer): string
	local n = buffer.len(b)
	local out = buffer.create(((n + 2) // 3) * 4)
	local at = 0
	for i = 0, n - 1, 3 do
		local b1 = buffer.readu8(b, i)
		local b2 = if i + 1 < n then buffer.readu8(b, i + 1) else 0
		local b3 = if i + 2 < n then buffer.readu8(b, i + 2) else 0
		local v = b1 * 65536 + b2 * 256 + b3
		buffer.writeu8(out, at, CODE[v // 262144])
		buffer.writeu8(out, at + 1, CODE[(v // 4096) % 64])
		buffer.writeu8(out, at + 2, if i + 1 < n then CODE[(v // 64) % 64] else PAD)
		buffer.writeu8(out, at + 3, if i + 2 < n then CODE[v % 64] else PAD)
		at += 4
	end
	return buffer.tostring(out)
end

function Wire.fromText(text: string): buffer?
	local n = #text
	if n % 4 ~= 0 then
		return nil
	end
	local pad = 0
	if n > 0 and string.byte(text, n) == PAD then
		pad = if string.byte(text, n - 1) == PAD then 2 else 1
	end
	local size = (n // 4) * 3 - pad
	local out = buffer.create(math.max(size, 0))
	local at = 0
	for i = 1, n, 4 do
		local c1, c2, c3, c4 = string.byte(text, i, i + 3)
		local v1, v2 = VALUE[c1], VALUE[c2]
		local v3 = if c3 == PAD then 0 else VALUE[c3]
		local v4 = if c4 == PAD then 0 else VALUE[c4]
		if v1 == nil or v2 == nil or v3 == nil or v4 == nil then
			return nil
		end
		-- padding only at the very end, and "x=y" is not padding
		if (c3 == PAD or c4 == PAD) and (i + 3 ~= n or (c3 == PAD and c4 ~= PAD)) then
			return nil
		end
		local v = v1 * 262144 + v2 * 4096 + v3 * 64 + v4
		if at < size then
			buffer.writeu8(out, at, v // 65536)
		end
		if at + 1 < size then
			buffer.writeu8(out, at + 1, (v // 256) % 256)
		end
		if at + 2 < size then
			buffer.writeu8(out, at + 2, v % 256)
		end
		at += 3
	end
	return out
end

function Wire.encode(script: Shot.Script): string
	return Wire.toText(Shot.pack(script))
end

function Wire.decode(text: any): (Shot.Script?, string?)
	if type(text) ~= "string" then
		return nil, "not text"
	end
	local b = Wire.fromText(text)
	if b == nil then
		return nil, "not base64"
	end
	return Shot.unpack(b)
end

return Wire
