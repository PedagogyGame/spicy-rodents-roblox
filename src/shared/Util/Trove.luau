--!strict
-- ReplicatedStorage.Shared.Util.Trove
-- Cleanup bag: collects functions, connections (anything with Disconnect/disconnect), instances or
-- objects with Destroy/destroy, and cleans them in reverse order once (BUILD_PLAN §1.4 Util).
-- Interface: new() -> Trove; add(item) -> item; clean(); count()

export type Trove = {
	add: <T>(self: Trove, item: T) -> T,
	clean: (self: Trove) -> (),
	count: (self: Trove) -> number,
	_items: { any },
}

local Trove = {}

local function cleanup(item: any)
	local kind = typeof(item)
	if kind == "function" then
		item()
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "table" then
		if type(item.disconnect) == "function" then
			item:disconnect()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.destroy) == "function" then
			item:destroy()
		elseif type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.clean) == "function" then
			item:clean()
		end
	end
end

function Trove.new(): Trove
	local t = { _items = {} } :: Trove
	function t.add<T>(self: Trove, item: T): T
		table.insert(self._items, item)
		return item
	end
	function t.clean(self: Trove)
		local items = self._items
		self._items = {}
		for i = #items, 1, -1 do
			cleanup(items[i])
		end
	end
	function t.count(self: Trove): number
		return #self._items
	end
	return t
end

return Trove
