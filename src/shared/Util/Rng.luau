--!strict
-- ReplicatedStorage.Shared.Util.Rng
-- mulberry32, the v5.4 `rng(seed)` (reference/v5_4_game.js L80-89) ported bit-exactly so seeded
-- scenarios repeat across V8, Lune and the engine (BUILD_PLAN §1.4 Util). Pure.
-- Interface: new(seed) -> Rng; Rng.next() -> [0,1); range(a, b); int(a, b) (inclusive);
--            pick(list); shuffle(list) (in place, Fisher-Yates); state()

local Rng = {}

export type Rng = {
	next: () -> number,
	range: (a: number, b: number) -> number,
	int: (a: number, b: number) -> number,
	pick: <T>(list: { T }) -> T,
	shuffle: <T>(list: { T }) -> { T },
	state: () -> number,
}

-- 32-bit integer multiply modulo 2^32, in 16-bit halves so it stays exact in doubles.
local function imul(a: number, b: number): number
	local aHi, aLo = a // 0x10000, a % 0x10000
	local bHi, bLo = b // 0x10000, b % 0x10000
	local mid = (aHi * bLo + aLo * bHi) % 0x10000
	return (aLo * bLo + mid * 0x10000) % 0x100000000
end

function Rng.new(seed: number): Rng
	local a = math.floor(seed) % 0x100000000
	local function next(): number
		a = (a + 0x6D2B79F5) % 0x100000000
		local t = a
		t = imul(bit32.bxor(t, bit32.rshift(t, 15)), bit32.bor(t, 1))
		t = bit32.bxor(t, (t + imul(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61))) % 0x100000000)
		return bit32.bxor(t, bit32.rshift(t, 14)) / 4294967296
	end
	local self = {} :: Rng
	self.next = next
	function self.range(lo: number, hi: number): number
		return lo + (hi - lo) * next()
	end
	function self.int(lo: number, hi: number): number
		return lo + math.floor(next() * (hi - lo + 1))
	end
	function self.pick<T>(list: { T }): T
		return list[1 + math.floor(next() * #list)]
	end
	function self.shuffle<T>(list: { T }): { T }
		for i = #list, 2, -1 do
			local j = 1 + math.floor(next() * i)
			list[i], list[j] = list[j], list[i]
		end
		return list
	end
	function self.state(): number
		return a
	end
	return self
end

return Rng
