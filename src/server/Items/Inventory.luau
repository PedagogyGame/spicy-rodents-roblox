--!strict
-- ServerScriptService.Server.Items.Inventory
-- What a player owns from the corner store (the game had no inventory: this is the smallest one that does the
-- job). The server's record is the truth: counts per item id per player (by UserId), for as long as this server
-- runs, like the wallet (Persistence/ProfileSchema has an `inventory` field of the same shape for when profiles
-- are saved: export(player) is it). Each owned thing is also a Roblox Tool in the player's Backpack, so the
-- engine's own hotbar shows it and equips it (1-9 / a click, a tap, the gamepad's bumpers): the Tool is only the
-- face, built by deps.makeTool (Server/Items/CornerStore clones the shelf's model into it), and a lost Tool (a new
-- body) is made again by refresh(player).
-- Interface: new(deps) -> Inventory { add(player, id, n?) -> count, take(player, id) -> boolean (one used up),
--   count(player, id) -> number, list(player) -> { [id]: count }, export(player) -> { [id]: count },
--   refresh(player) (every owned thing has its Tool), forget(player) }
-- Engine only through deps; no side effects on require.

local Inventory = {}

export type Deps = {
	-- a Tool for this item in this player's Backpack (nil: no engine, as in a spec; the record still counts)
	makeTool: ((player: any, itemId: string) -> any?)?,
	-- the Tools this player has now for this item (in the Backpack and in the hand)
	toolsOf: ((player: any, itemId: string) -> { any })?,
}

export type Inventory = {
	add: (player: any, itemId: string, n: number?) -> number,
	take: (player: any, itemId: string) -> boolean,
	count: (player: any, itemId: string) -> number,
	list: (player: any) -> { [string]: number },
	export: (player: any) -> { [string]: number },
	refresh: (player: any) -> (),
	forget: (player: any) -> (),
}

local function keyOf(player: any): any
	if type(player) == "table" and player.UserId ~= nil then
		return player.UserId
	end
	local ok, id = pcall(function()
		return (player :: any).UserId
	end)
	return if ok and id ~= nil then id else player
end

function Inventory.new(deps: Deps?): Inventory
	local d: Deps = deps or {}
	local owned: { [any]: { [string]: number } } = {}

	local function tools(player: any, itemId: string): { any }
		return if d.toolsOf then d.toolsOf(player, itemId) else {}
	end

	local self: Inventory
	self = {
		add = function(player: any, itemId: string, n: number?): number
			local k = keyOf(player)
			local mine = owned[k] or {}
			owned[k] = mine
			mine[itemId] = (mine[itemId] or 0) + (n or 1)
			self.refresh(player)
			return mine[itemId]
		end,
		take = function(player: any, itemId: string): boolean
			local mine = owned[keyOf(player)]
			if mine == nil or (mine[itemId] or 0) <= 0 then
				return false
			end
			mine[itemId] -= 1
			if mine[itemId] <= 0 then
				mine[itemId] = nil
			end
			-- one Tool fewer when the last of them is used up
			if (mine[itemId] or 0) == 0 then
				for _, t in tools(player, itemId) do
					pcall(function()
						t:Destroy()
					end)
				end
			end
			return true
		end,
		count = function(player: any, itemId: string): number
			local mine = owned[keyOf(player)]
			return if mine then mine[itemId] or 0 else 0
		end,
		list = function(player: any): { [string]: number }
			return table.clone(owned[keyOf(player)] or {})
		end,
		export = function(player: any): { [string]: number }
			return table.clone(owned[keyOf(player)] or {})
		end,
		refresh = function(player: any)
			local mine = owned[keyOf(player)]
			if mine == nil or d.makeTool == nil then
				return
			end
			for itemId, n in mine do
				if n > 0 and #tools(player, itemId) == 0 then
					d.makeTool(player, itemId)
				end
			end
		end,
		forget = function(player: any)
			owned[keyOf(player)] = nil
		end,
	}
	return self
end

return Inventory
