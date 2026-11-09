--!strict
-- tests/cheat/Rng: a seeded mulberry32 (the v5.4 `rng(seed)`, reference/v5_4_game.js L80-89) for the
-- harness, so every simulation is reproducible from its seed. Shared/Util/Rng (W1) will replace it.

local Rng = {}

export type Rng = { next: () -> number, range: (a: number, b: number) -> number, state: () -> number }

local MASK = 0xFFFFFFFF

local function imul(a: number, b: number): number
	-- 32-bit integer multiply modulo 2^32, done in halves to stay exact in doubles
	local aHi, aLo = math.floor(a / 0x10000), a % 0x10000
	local bHi, bLo = math.floor(b / 0x10000), b % 0x10000
	local lo = aLo * bLo
	local mid = (aHi * bLo + aLo * bHi) % 0x10000
	return (lo + mid * 0x10000) % 0x100000000
end

function Rng.new(seed: number): Rng
	local a = bit32.band(math.floor(seed), MASK)
	local function next(): number
		a = (a + 0x6D2B79F5) % 0x100000000
		local t = a
		t = imul(bit32.bxor(t, bit32.rshift(t, 15)), bit32.bor(t, 1))
		t = bit32.bxor(t, (t + imul(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61))) % 0x100000000)
		return bit32.bxor(t, bit32.rshift(t, 14)) / 4294967296
	end
	return {
		next = next,
		range = function(lo: number, hi: number): number
			return lo + (hi - lo) * next()
		end,
		state = function(): number
			return a
		end,
	}
end

return Rng
