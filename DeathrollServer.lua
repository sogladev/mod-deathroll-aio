local AIO = AIO or require("AIO")
local DRHandlers = {}
AIO.AddHandlers("AIODeathRoll", DRHandlers)
local DR = {}
local ADDON_NAME = "AIODeathRoll"
local COINAGE_MAX = 2147483647
local PLAYER_EVENT_ON_COMMAND  = 42 -- (event, player, command, chatHandler) - player is nil if command used from console. Can return false

local ADDON_NAME = "AIODeathRoll"

function DRHandlers.StartPlay(player, bet)
    -- PrintInfo("DRHandlers.StartPlay received")
    -- local symbol1, symbol2, symbol3 = GenerateSymbols()
    -- local validBet = SM.Currency[SM.Config.currency].VerifyAmount(player, bet)
    -- if not validBet then
    --     return
    -- end
    -- -- calculate payout
    -- local payout = CalculatePayout(bet, symbol1, symbol2, symbol3)
    -- local guid = player:GetGUID()
    -- -- save game to db
    -- if payout > 0 or not SM.Config.server.saveOnlyWinnerstoDb then
    --     local combination = string.format('%s-%s-%s', symbol1, symbol2, symbol3)
    --     local query = string.format("INSERT INTO `%s`.`slot_machine` (accountId, combination, bet, payout, paid) VALUES(%d, '%s', %d, %d, %d);",
    --         SM.Config.server.customDbName,
    --         player:GetAccountId(), combination, bet, payout, (payout > 0) and 0 or 1)
    --     CharDBExecute(query)
    -- end
    -- SM.Currency[SM.Config.currency].TakePayment(player, bet)
    -- AIO.Handle(player, ADDON_NAME, "StartSpin", symbol1, symbol2, symbol3, bet)
end

local function OnCommand(event, player, command)
    if command == "dr" then
        AIO.Handle(player, ADDON_NAME, "ShowFrame")
        return false
    end
end

RegisterPlayerEvent(PLAYER_EVENT_ON_COMMAND, OnCommand)
