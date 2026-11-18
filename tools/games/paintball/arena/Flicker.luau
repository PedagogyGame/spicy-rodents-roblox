--!strict
-- tools/games/paintball/arena/Flicker: the pairs of boxes that would flicker against each other when drawn.
-- Every box is one part (PartList). Two parts with a face in the same plane, looking the same way, overlapping by
-- more than a sliver, are drawn at the same depth and the engine shows now one, now the other (z-fighting). It
-- does not show when both are the same colour and material, so a pair of the same look is let be; nor where a
-- third box (or the dressing outside the volume: `covers`, six numbers a box in the arena's frame) lies against
-- the shared face and hides it, as the floor hides the undersides of two things standing on it.
-- Pure. Interface: find(plan, covers?) -> { { a, b (box indices), face ("+x" ..), plane, area } }
local ArenaDataPlan = require("../../../../src/shared/Minigames/Paintball/ArenaDataPlan")

local Flicker = {}

export type Pair = { a: number, b: number, face: string, plane: number, area: number }

local SLIVER = 0.02 -- studs: an overlap narrower than this is an edge, not a face
local FACES = { "-x", "-y", "-z", "+x", "+y", "+z" }

function Flicker.find(plan: ArenaDataPlan.Plan, covers: { number }?): { Pair }
	local boxes, looks = plan.boxes, plan.looks
	local n = #plan.kinds
	local out: { Pair } = {}
	-- is the point strictly inside some box, of the plan's or of the covers?
	local function buried(x: number, y: number, z: number): boolean
		for _, list in { boxes, covers or {} } do
			for k = 1, #list, 6 do
				if
					x > list[k]
					and x < list[k + 3]
					and y > list[k + 1]
					and y < list[k + 4]
					and z > list[k + 2]
					and z < list[k + 5]
				then
					return true
				end
			end
		end
		return false
	end
	-- by face and plane: the boxes with a face there
	local byPlane: { [string]: { number } } = {}
	for i = 1, n do
		local k = (i - 1) * 6
		for f = 1, 6 do
			local key = `{f}:{math.floor(boxes[k + f] * 1000 + 0.5)}`
			local list = byPlane[key]
			if list == nil then
				list = {}
				byPlane[key] = list
			end
			table.insert(list, i)
		end
	end
	for key, list in byPlane do
		local f = tonumber(string.sub(key, 1, 1)) :: number
		local axis = (f - 1) % 3 + 1 -- 1 x, 2 y, 3 z
		local u, v = axis % 3 + 1, (axis + 1) % 3 + 1
		for p = 1, #list do
			for q = p + 1, #list do
				local i, j = list[p], list[q]
				if looks[i] ~= looks[j] then
					local a, b = (i - 1) * 6, (j - 1) * 6
					local u0, u1 = math.max(boxes[a + u], boxes[b + u]), math.min(boxes[a + u + 3], boxes[b + u + 3])
					local v0, v1 = math.max(boxes[a + v], boxes[b + v]), math.min(boxes[a + v + 3], boxes[b + v + 3])
					if u1 - u0 > SLIVER and v1 - v0 > SLIVER then
						-- the middle of what they share, a hair outside the face
						local at = { 0, 0, 0 }
						at[axis] = boxes[a + f] + (if f <= 3 then -0.01 else 0.01)
						at[u] = (u0 + u1) / 2
						at[v] = (v0 + v1) / 2
						if not buried(at[1], at[2], at[3]) then
							table.insert(
								out,
								{ a = i, b = j, face = FACES[f], plane = boxes[a + f], area = (u1 - u0) * (v1 - v0) }
							)
						end
					end
				end
			end
		end
	end
	table.sort(out, function(x: Pair, y: Pair): boolean
		if x.a ~= y.a then
			return x.a < y.a
		end
		return x.b < y.b
	end)
	return out
end

return Flicker
