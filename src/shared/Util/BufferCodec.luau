--!strict
-- ReplicatedStorage.Shared.Util.BufferCodec
-- Fixed layouts for high-rate streams (BUILD_PLAN §1.6: Motor.State about 40 bytes, VehiclePoses about
-- 13 bytes per vehicle). A layout is an ordered list of { name, kind, lo?, hi? }; `q16` quantises a
-- number in [lo, hi] to a u16 (the route parameter s), `f32` packs positions. Little-endian via the
-- Luau buffer library, so Lune and the engine produce identical bytes. Pure.
-- Interface: layout(fields) -> Layout (with .size); encode(layout, record, buf?, offset?) -> buffer;
--            decode(layout, buf, offset?) -> record; quantize(v, lo, hi) -> u16; dequantize(q, lo, hi)

export type Kind = "u8" | "u16" | "u32" | "i8" | "i16" | "i32" | "f32" | "f64" | "q16"
export type Field = { name: string, kind: Kind, lo: number?, hi: number? }
export type Layout = { fields: { Field }, size: number }

local BufferCodec = {}

local SIZE: { [Kind]: number } = { u8 = 1, u16 = 2, u32 = 4, i8 = 1, i16 = 2, i32 = 4, f32 = 4, f64 = 8, q16 = 2 }

function BufferCodec.layout(fields: { Field }): Layout
	local size = 0
	for _, f in fields do
		local s = SIZE[f.kind]
		assert(s, `BufferCodec: unknown kind {f.kind}`)
		if f.kind == "q16" then
			assert(f.lo and f.hi and f.hi > f.lo, `BufferCodec: q16 field {f.name} needs lo < hi`)
		end
		size += s
	end
	return { fields = fields, size = size }
end

function BufferCodec.quantize(v: number, lo: number, hi: number): number
	if v ~= v then
		return 0
	end
	local q = math.floor((math.clamp(v, lo, hi) - lo) / (hi - lo) * 65535 + 0.5)
	return q
end

function BufferCodec.dequantize(q: number, lo: number, hi: number): number
	return lo + (hi - lo) * q / 65535
end

local function clampInt(v: number, lo: number, hi: number): number
	if v ~= v then
		return 0
	end
	return math.clamp(math.floor(v + 0.5), lo, hi)
end

function BufferCodec.encode(layout: Layout, record: { [string]: any }, buf: buffer?, offset: number?): buffer
	local b = buf or buffer.create(layout.size)
	local o = offset or 0
	for _, f in layout.fields do
		local v = (record[f.name] :: number?) or 0
		local k = f.kind
		if k == "u8" then
			buffer.writeu8(b, o, clampInt(v, 0, 255))
		elseif k == "u16" then
			buffer.writeu16(b, o, clampInt(v, 0, 65535))
		elseif k == "u32" then
			buffer.writeu32(b, o, clampInt(v, 0, 4294967295))
		elseif k == "i8" then
			buffer.writei8(b, o, clampInt(v, -128, 127))
		elseif k == "i16" then
			buffer.writei16(b, o, clampInt(v, -32768, 32767))
		elseif k == "i32" then
			buffer.writei32(b, o, clampInt(v, -2147483648, 2147483647))
		elseif k == "f32" then
			buffer.writef32(b, o, v)
		elseif k == "f64" then
			buffer.writef64(b, o, v)
		else
			buffer.writeu16(b, o, BufferCodec.quantize(v, f.lo :: number, f.hi :: number))
		end
		o += SIZE[k]
	end
	return b
end

function BufferCodec.decode(layout: Layout, b: buffer, offset: number?): { [string]: number }
	local o = offset or 0
	if buffer.len(b) < o + layout.size then
		error("BufferCodec.decode: buffer too short")
	end
	local out: { [string]: number } = {}
	for _, f in layout.fields do
		local k = f.kind
		local v: number
		if k == "u8" then
			v = buffer.readu8(b, o)
		elseif k == "u16" then
			v = buffer.readu16(b, o)
		elseif k == "u32" then
			v = buffer.readu32(b, o)
		elseif k == "i8" then
			v = buffer.readi8(b, o)
		elseif k == "i16" then
			v = buffer.readi16(b, o)
		elseif k == "i32" then
			v = buffer.readi32(b, o)
		elseif k == "f32" then
			v = buffer.readf32(b, o)
		elseif k == "f64" then
			v = buffer.readf64(b, o)
		else
			v = BufferCodec.dequantize(buffer.readu16(b, o), f.lo :: number, f.hi :: number)
		end
		out[f.name] = v
		o += SIZE[k]
	end
	return out
end

return BufferCodec
