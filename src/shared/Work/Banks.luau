--!strict
-- ReplicatedStorage.Shared.Work.Banks
-- The town's banks (owner D30: "place a few banks around town, outside of which there are tasks or other optional
-- errands"). Three bank fronts in Bellwether Quay, the town's old commercial quarter: three of its Tudor townhouses
-- (each name there was painted on two or three of them) now carry BANK on their fascia (data/authored/town/lots
-- bellwether_quay.json params.sign; the town bake draws it, worldgen/Builders/Building.sign). Outside each, an errand
-- board on the quay beside its door (Server/Work/ErrandService builds it and its prompt; Shared/Work/Errands says
-- what it offers).
--   * BANKS: id, the name a player reads, the lot, and where the board stands: OUT studs in front of the lot's
--     front face, ALONG studs along it from the door (to the right, seen from outside), facing out.
--   * board(bank, data?) -> { x, y, z, yaw } (world studs, the ground under it, the Roblox yaw that faces out of
--     the bank); BOARD (its size). tests/unit/work_errands.spec holds every board clear of the roads, the buildings
--     and everything baked on the quay, on the quay's level ground, and the three apart.
-- Pure over Shared/Data (lots) and World/Height; studs. No side effects on require.

local Data = require("../Data")
local Height = require("../World/Height")

local Banks = {}

export type Bank = { id: string, name: string, lot: string, short: string }
export type Board = { x: number, y: number, z: number, yaw: number, nx: number, nz: number }

-- stylua: ignore
Banks.BANKS = table.freeze({
	{ id = "south_quay", name = "the South Quay bank", short = "South Quay bank", lot = "quay_bldg_w_03" },
	{ id = "north_quay", name = "the North Quay bank", short = "North Quay bank", lot = "quay_bldg_w_09" },
	{ id = "market", name = "the Market bank", short = "Market bank", lot = "quay_bldg_m_02" },
} :: { Bank })

Banks.SIGN = "BANK"
Banks.OUT = 4 -- studs in front of the front face (the Tudor shells stand up to 0.9 proud of their lots)
Banks.ALONG = 9 -- studs along the front from the door: beside the display window, clear of the door and its boxes
Banks.BOARD = table.freeze({ w = 2.2, h = 3.0, d = 0.5 }) -- the sandwich board: wide, tall, deep (studs)

local FACE: { [string]: { number } } = { ["+X"] = { 1, 0 }, ["-X"] = { -1, 0 }, ["+Z"] = { 0, 1 }, ["-Z"] = { 0, -1 } }

function Banks.byId(id: string): Bank?
	for _, b in Banks.BANKS do
		if b.id == id then
			return b
		end
	end
	return nil
end

-- Where a bank's errand board stands: world x, z, the ground y there, the Roblox yaw facing out of the bank, and
-- the outward normal.
function Banks.board(bank: Bank, data: any?): Board
	local d = data or Data.default()
	local lot = d:lot(bank.lot)
	assert(lot and lot.footprint, `Banks.board: no lot {bank.lot}`)
	local f = FACE[lot.facing] or { 0, 1 }
	local half = if f[1] ~= 0 then lot.footprint.w / 2 else lot.footprint.d / 2
	-- along the front, to the right as seen from outside (looking back at the facade, -f)
	local ax, az = f[2], -f[1]
	local x = lot.x + f[1] * (half + Banks.OUT) + ax * Banks.ALONG
	local z = lot.z + f[2] * (half + Banks.OUT) + az * Banks.ALONG
	-- (CFrame.Angles(0, yaw, 0).LookVector = (-sin yaw, 0, -cos yaw) = the outward normal: the board's Front faces out)
	return { x = x, y = Height.at(x, z), z = z, yaw = math.atan2(-f[1], -f[2]), nx = f[1], nz = f[2] }
end

return Banks
