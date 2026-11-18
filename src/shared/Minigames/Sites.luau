--!strict
-- ReplicatedStorage.Shared.Minigames.Sites
-- Where the places with minigames in them stand, read from the compiled data (Minigames/Games explains a site):
-- the attractions baked on their own (generated/Attractions: the bowling alley, id "bowling_alley") and the
-- expansion venues (generated/Expansion.venues: "f3_racquet_club", ...). Every one is a Place in AlleyLayout's
-- frame. The server takes its sites from the baked models themselves (their Origin attributes, written by the
-- bake from this same data: Server/Attractions/AttractionService); this is for a client that has not been told
-- (a watcher who never joined), for the bake and for specs.
-- Pure given a Data (Shared/Data). Interface: fromData(data, expansion?) -> { [site]: Place } (expansion false
--   leaves the venues out: generated/Expansion is large, and a caller that only wants the alley need not load it);
--   place(record) -> Place? (a compiled record's `place`)

local GameSpec = require("./GameSpec")

local Sites = {}

function Sites.place(record: any): GameSpec.Place?
	local p = type(record) == "table" and record.place
	if
		type(p) == "table"
		and type(p.x) == "number"
		and type(p.z) == "number"
		and type(p.floorY) == "number"
		and type(p.yaw) == "number"
	then
		return { x = p.x, z = p.z, floorY = p.floorY, yaw = p.yaw }
	end
	return nil
end

function Sites.fromData(data: any, expansion: boolean?): { [string]: GameSpec.Place }
	local out: { [string]: GameSpec.Place } = {}
	local function take(list: any)
		if type(list) ~= "table" then
			return
		end
		for _, record in list do
			local p = Sites.place(record)
			if p and type(record.id) == "string" then
				out[record.id] = p
			end
		end
	end
	local attractions = data:module("Attractions") :: any
	take(attractions and attractions.attractions)
	if expansion ~= false then
		local exp = data:module("Expansion") :: any
		take(exp and exp.venues)
	end
	return out
end

return Sites
