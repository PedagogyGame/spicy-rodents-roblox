--!strict
-- ServerScriptService.Server.Persistence.ProfileSchema
-- The versioned DataStore profile (BUILD_PLAN D26, risk 24; spike S15): the wallet in integer cents,
-- the receipt ledger, the wardrobe (clothing owned) and what is worn (slot -> id), the item inventory,
-- reputation and lifetime stats. Pure: a template, forward migrations and a validator so a corrupt or
-- future record is never written over. What the live game writes today is only `wardrobe` and `worn`
-- (owner D16 #25: clothing carries over, nothing else; Server/Cosmetics/Wardrobe); the other fields keep
-- whatever the record holds.
-- v2 (19 November): adds `worn`.
-- Interface: VERSION, template() -> Data, migrate(raw) -> (Data?, err?), validate(data) -> (ok, err?)

export type ReceiptEntry = { productId: number, cents: number, at: number, playerId: number }
export type Data = {
	schema: number,
	wallet: { cents: number },
	receipts: { ids: { string }, byId: { [string]: ReceiptEntry } },
	wardrobe: { [string]: boolean },
	worn: { [string]: string },
	inventory: { [string]: number },
	reputation: number,
	stats: { [string]: number },
}

local ProfileSchema = {}

ProfileSchema.VERSION = 2

function ProfileSchema.template(): Data
	return {
		schema = ProfileSchema.VERSION,
		wallet = { cents = 0 },
		receipts = { ids = {}, byId = {} },
		wardrobe = {},
		worn = {},
		inventory = {},
		reputation = 0,
		stats = {},
	}
end

local function isWhole(v: any): boolean
	return type(v) == "number" and v == v and v >= 0 and math.floor(v) == v
end

function ProfileSchema.validate(data: any): (boolean, string?)
	if type(data) ~= "table" then
		return false, "not a table"
	end
	if data.schema ~= ProfileSchema.VERSION then
		return false, `schema {tostring(data.schema)}`
	end
	if type(data.wallet) ~= "table" or not isWhole(data.wallet.cents) then
		return false, "wallet"
	end
	local r = data.receipts
	if type(r) ~= "table" or type(r.ids) ~= "table" or type(r.byId) ~= "table" then
		return false, "receipts"
	end
	for _, id in r.ids do
		if type(id) ~= "string" or type(r.byId[id]) ~= "table" then
			return false, "receipt index"
		end
	end
	if
		type(data.wardrobe) ~= "table"
		or type(data.worn) ~= "table"
		or type(data.inventory) ~= "table"
		or type(data.stats) ~= "table"
	then
		return false, "collections"
	end
	for slot, id in data.worn do
		if type(slot) ~= "string" or type(id) ~= "string" then
			return false, "worn"
		end
	end
	for id, v in data.wardrobe do
		if type(id) ~= "string" or type(v) ~= "boolean" then
			return false, "wardrobe"
		end
	end
	if type(data.reputation) ~= "number" then
		return false, "reputation"
	end
	return true, nil
end

-- nil (a new player) -> template; schema 0 (the pre-S15 shape { cents = n }) -> v1; v1 -> v2 (nothing
-- worn); a newer schema than this build knows is refused so an old server never truncates a newer record.
function ProfileSchema.migrate(raw: any): (Data?, string?)
	if raw == nil then
		return ProfileSchema.template(), nil
	end
	if type(raw) ~= "table" then
		return nil, "not a table"
	end
	local schema = raw.schema or 0
	if type(schema) ~= "number" then
		return nil, "bad schema"
	end
	if schema > ProfileSchema.VERSION then
		return nil, `schema {schema} is newer than {ProfileSchema.VERSION}`
	end
	local data: any = raw
	if schema == 0 then
		local fresh = ProfileSchema.template()
		fresh.wallet.cents = if isWhole(raw.cents) then raw.cents else 0
		data = fresh -- (already the present shape)
		schema = ProfileSchema.VERSION
	end
	if schema == 1 then
		data = table.clone(data)
		data.worn = {}
		data.schema = 2
	end
	-- fill fields added after a record was written (none yet; kept for the pattern)
	local template = ProfileSchema.template() :: any
	for k, v in template do
		if data[k] == nil then
			data[k] = v
		end
	end
	local ok, err = ProfileSchema.validate(data)
	if not ok then
		return nil, err
	end
	return data :: Data, nil
end

function ProfileSchema.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value :: any do
		out[k] = ProfileSchema.deepCopy(v)
	end
	return out :: any
end

return ProfileSchema
