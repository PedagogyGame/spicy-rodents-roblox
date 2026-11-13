-- SERVER ONLY, session-only credits. The server owns values and authorizes every mutation.
-- Do not connect Credit or Spend directly to a client RemoteEvent.
local Players = game:GetService("Players")
local WalletService = {}
WalletService.__index = WalletService

local function validAmount(n)
    return typeof(n) == "number" and n == n and n >= 1 and n <= 100000000
        and math.floor(n) == n
end

function WalletService.new(startingCredits)
    startingCredits = startingCredits or 0
    assert(typeof(startingCredits) == "number" and startingCredits >= 0
        and math.floor(startingCredits) == startingCredits
        and startingCredits == startingCredits and startingCredits <= 1000000000, "invalid initial balance")
    local self = setmetatable({
        start = startingCredits, balances = {}, usedTransactions = {},
        playerRemovingConnection = nil
    }, WalletService)
    self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
        self.balances[player] = nil
        self.usedTransactions[player] = nil
    end)
    return self
end

function WalletService:_ensure(player)
    assert(typeof(player) == "Instance" and player:IsA("Player"), "expected Player")
    if self.balances[player] == nil then
        self.balances[player] = self.start
        self.usedTransactions[player] = {}
        player:SetAttribute("SpicyWalletCredits", self.start)
    end
end

function WalletService:GetBalance(player)
    self:_ensure(player)
    return self.balances[player]
end

-- transactionKey must be unique per awarded/charged action, e.g., "paintball-123-award".
function WalletService:_change(player, amount, transactionKey, reason)
    self:_ensure(player)
    if not validAmount(math.abs(amount)) then return false, "invalid amount" end
    if typeof(transactionKey) ~= "string" or #transactionKey < 1 or #transactionKey > 120 then
        return false, "invalid transaction key"
    end
    if self.usedTransactions[player][transactionKey] then return false, "duplicate transaction" end
    local nextAmount = self.balances[player] + amount
    if nextAmount < 0 then return false, "insufficient credits" end
    if nextAmount > 1000000000 then return false, "balance limit" end
    self.usedTransactions[player][transactionKey] = true
    self.balances[player] = nextAmount
    player:SetAttribute("SpicyWalletCredits", nextAmount)
    return true, nextAmount
end

function WalletService:Credit(player, amount, transactionKey, reason)
    if not validAmount(amount) then return false, "invalid amount" end
    return self:_change(player, amount, transactionKey, reason)
end

function WalletService:Spend(player, amount, transactionKey, reason)
    if not validAmount(amount) then return false, "invalid amount" end
    return self:_change(player, -amount, transactionKey, reason)
end

function WalletService:Destroy()
    if self.playerRemovingConnection then self.playerRemovingConnection:Disconnect() end
    table.clear(self.balances)
    table.clear(self.usedTransactions)
end
return WalletService
