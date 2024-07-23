local AIO = AIO or require("AIO")
local DRHandlers = {}
AIO.AddHandlers("AIODeathRoll", DRHandlers)
local DR = {}
local ADDON_NAME = "AIODeathRoll"
local COINAGE_MAX = 2147483647
local PLAYER_EVENT_ON_COMMAND  = 42 -- (event, player, command, chatHandler) - player is nil if command used from console. Can return false
local MAIL_STATIONERY_GM = 61

local ADDON_NAME = "AIODeathRoll"

DR.Config = {
    removeGoldAtStart = true, -- default: true
    mail = {
        senderGUID = 1, -- Low GUID of the sender
        stationary = MAIL_STATIONERY_GM,
        -- %s player name
        body = "Greetings %s\n\nWe were unable to add your winnings directly to your character. We have sent it to you via mail instead\n\nThank you for playing!\n\nBest regards,\nDeathRoll",
        subject = "Your Winnings!", -- %s player name
    },
    timedEventDelay = 30000, -- in milliseconds, delay between clean up jobs
    timeOut = 30000, -- in milliseconds, when cleanup job runs, games without rolls for this long will time out
    -- Below need to match client
    startRollMin = 2, -- default: 1000
}

local State = {
    PENDING = 1,
    PROGRESS = 2,
}

local games = {}

local function DoPayoutGold(player, payout)
    if (payout + player:GetCoinage()) > COINAGE_MAX then
        SendMail(DR.Config.mail.subject, string.format(DR.Config.mail.body, player:GetName()),
            player:GetGUIDLow(), DR.Config.mail.senderGUID, DR.Config.mail.stationary, 0, payout)
        AIO.Handle(player, ADDON_NAME, "SentPayoutByMail")
    else
        player:ModifyMoney(payout)
    end
end

local function eq(guid1, guid2)
    return tostring(guid1) == tostring(guid2)
end

-- handle games by time out
local function OnTimedEventCheckTimeout(_, _, _) -- eventId, delay, repeats
    local toBeRemoved = {}
    for i, game in ipairs(games) do
        if game then
            -- check last roll
            if game.state == State.PROGRESS and game.rolls and (#game.rolls > 0) then
                local previousRoll = game.rolls[1]
                local timeDiff = GetTimeDiff(previousRoll.time)
                if timeDiff > DR.Config.timeOut then
                    -- finish game and award last rolled player as winner
                    local player
                    local otherPlayer
                    if (eq(game.target, previousRoll.player)) then
                        player = GetPlayerByGUID(game.target)
                        otherPlayer = GetPlayerByGUID(game.challenger)
                    else
                        player = GetPlayerByGUID(game.challenger)
                        otherPlayer = GetPlayerByGUID(game.target)
                    end
                    local wager = game.wager
                    if DR.Config.removeGoldAtStart then
                        DoPayoutGold(otherPlayer, 2*wager)
                    else
                        DoPayoutGold(otherPlayer, wager)
                        if (player:GetCoinage() < wager) then
                            PrintError("Player did not have enough coinage to pay other player!\nConsider enabling Config.removeGoldAtStart")
                        end
                        player:ModifyMoney(-wager)
                    end
                    AIO.Handle(otherPlayer, ADDON_NAME, "YouWin", wager)
                    AIO.Handle(player, ADDON_NAME, "YouLose", wager)
                    table.insert(toBeRemoved, i)
                end
            else
                local timeDiff = GetTimeDiff(game.time)
                -- check if timeout
                if timeDiff > DR.Config.timeOut then
                    -- cancel game
                    if game.state == State.PROGRESS then
                        -- no winners
                        local player = GetPlayerByGUID(game.target)
                        local otherPlayer = GetPlayerByGUID(game.challenger)
                        if DR.Config.removeGoldAtStart then
                            local wager = game.wager
                            DoPayoutGold(player, wager)
                            DoPayoutGold(otherPlayer, wager)
                            AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "Timeout! Refunded money")
                            AIO.Handle(otherPlayer, ADDON_NAME, "ChallengeRequestDenied", "Timeout! Refunded money")
                        else
                            AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "Timeout!")
                            AIO.Handle(otherPlayer, ADDON_NAME, "ChallengeRequestDenied", "Timeout!")
                        end
                    else
                        local challenger = GetPlayerByGUID(game.challenger)
                        AIO.Handle(challenger, ADDON_NAME, "ChallengeRequestDenied", "Timeout Pending!")
                    end
                    table.insert(toBeRemoved, i)
                end
            end
        end
    end
    -- remove games
    for i = #toBeRemoved, 1, -1 do
        table.remove(games, toBeRemoved[i])
    end
end

local function FindGame(playerGUID)
    for i, game in ipairs(games) do
        if game and (eq(game.target,  playerGUID) or eq(game.challenger, playerGUID)) then
            return i
        end
    end
    return 0
end

function DRHandlers.Rolled(player, rollResult, minRoll, maxRoll)
    local playerGUID = player:GetGUID()
    local i = FindGame(playerGUID)
    if not i then
        PrintError("No game foud!")
        return
    end
    local game = games[i]
    -- found game
    local roll = { -- only store valid rolls
        player = playerGUID,
        result = rollResult,
        max = maxRoll,
        time = GetCurrTime(),
    }
    if not game.rolls then
        -- first roll
        -- verify roll
        if not eq(maxRoll, game.startRoll) or not eq(minRoll, 1) then
            AIO.Handle(player, ADDON_NAME, "RollMessage", string.format("Expecting: /roll %d", game.startRoll))
            return
        end
        -- add roll
        games[i].rolls = {roll}
    else
        local previousRoll = game.rolls[1]
        -- verify roll
        if not eq(maxRoll, previousRoll.result) or not eq(minRoll, 1) then
            AIO.Handle(player, ADDON_NAME, "RollMessage", string.format("Expecting: /roll %d", previousRoll.result))
            return
        end
        -- add roll
        table.insert(games[i].rolls, 1, roll)
    end
    -- determine who is other player
    local otherPlayer
    if (eq(game.target, playerGUID)) then
        otherPlayer = GetPlayerByGUID(game.challenger)
    else
        otherPlayer = GetPlayerByGUID(game.target)
    end
    -- end game or continue
    if eq(rollResult, 1) then
        -- end game
        local wager = game.wager
        if DR.Config.removeGoldAtStart then
            DoPayoutGold(otherPlayer, 2*wager)
        else
            DoPayoutGold(otherPlayer, wager)
            if (player:GetCoinage() < wager) then
                PrintError(string.format("%s:%s did not have enough coinage to pay %s!\nConsider enabling Config.removeGoldAtStart", ADDON_NAME, player:GetName(), otherPlayer:GetName()))
            end
            player:ModifyMoney(-wager)
        end
        AIO.Handle(otherPlayer, ADDON_NAME, "YouWin", wager)
        AIO.Handle(player, ADDON_NAME, "YouLose", wager)
        if game.mode == "death" then
            -- player:KillPlayer() -- broken?
            player:Kill(player, false)
        end
        table.remove(games, i)
    else
        -- continue game
        AIO.Handle(otherPlayer, ADDON_NAME, "YourTurn", rollResult)
    end
end

function DRHandlers.RequestChallenge(player, targetGUID, wager, startRoll, mode)
    -- cleanup old games
    OnTimedEventCheckTimeout()
    -- Check if guid is player
    local target = GetPlayerByGUID(targetGUID)
    if not target then
        AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "Target must be player!")
        return
    end
    -- Check if target or player already has game
    local playerGUID = player:GetGUID()
    if FindGame(playerGUID) ~= 0 then
        AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "You already have pending game or are already playing!")
        return
    end
    if FindGame(targetGUID) ~= 0 then
        AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "Target has pending game or is already playing!")
        return
    end
    -- Check startRoll
    if startRoll < DR.Config.startRollMin then
        AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", string.format("Start roll too low, must be atleast %d", DR.Config.startRollMin))
        return
    end
    -- Check balances
    local coinagePlayer = player:GetCoinage()
    if coinagePlayer < wager then
        AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "You do not have enough money!")
        return
    end
    local coinageTarget = target:GetCoinage()
    if coinageTarget < wager then
        AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "Target does not have enough money!")
        return
    end
    -- Check isAlive
    if not player:IsAlive() then
        AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "You are dead!")
        return
    end
    -- Check combat
    if player:IsInCombat() then
        AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "You are in combat!")
        return
    end
    local newGame = {
        challenger = playerGUID,
        target = targetGUID,
        wager = wager,
        startRoll = startRoll,
        state = State.PENDING,
        time = GetCurrTime(),
        mode = mode and mode or "normal",
    }
    table.insert(games, 1, newGame)
    -- minus wager from each player
    AIO.Handle(player, ADDON_NAME, "ChallengeRequestPending", target:GetName())
    AIO.Handle(target, ADDON_NAME, "ChallengeReceived", player:GetName(), wager, startRoll, mode)
end

local function HandleDeclineChallenge(player)
    -- cleanup old games
    OnTimedEventCheckTimeout()
    local targetGUID = player:GetGUID()
    local i = FindGame(targetGUID)
    if not i then
        AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "No game found to decline!")
        return
    end
    local game = games[i]
    -- send deny request to both players
    local challenger = GetPlayerByGUID(game.challenger)
    AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "Challenge was declined!")
    AIO.Handle(challenger, ADDON_NAME, "ChallengeRequestDenied", "Challenge was declined!")
    -- remove game
    table.remove(games, i)
end

local function HandleAcceptChallenge(player)
    -- cleanup old games
    OnTimedEventCheckTimeout()
    local targetGUID = player:GetGUID()
    local i = FindGame(targetGUID)
    if not i then
        AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "No game found to accept!")
        return
    end
    local game = games[i]
    -- check if challenger exists
    local challenger = GetPlayerByGUID(game.challenger)
    if not challenger then
        PrintError(string.format("%s:GetPlayerByGUID of challenger failed!", ADDON_NAME))
        AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "Could not find challenger!")
        return
    end
    -- Check isAlive
    if not (challenger:IsAlive() and player:IsAlive()) then
        AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "One of the players is dead!")
        AIO.Handle(challenger, ADDON_NAME, "ChallengeRequestDenied", "One of the players is dead!")
        return
    end
    -- Check combat
    if challenger:IsInCombat() or player:IsInCombat() then
        AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "One of the players is in combat!")
        AIO.Handle(challenger, ADDON_NAME, "ChallengeRequestDenied", "One of the players is in combat!")
        return
    end
    -- Check balances
    local coinagePlayer = player:GetCoinage()
    if coinagePlayer < game.wager then
        AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "Challengee does not have enough money!")
        AIO.Handle(challenger, ADDON_NAME, "ChallengeRequestDenied", "Challengee does not have enough money!")
        return
    end
    local coinageTarget = challenger:GetCoinage()
    if coinageTarget < game.wager then
        AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "Challenger does not have enough money!")
        AIO.Handle(challenger, ADDON_NAME, "ChallengeRequestDenied", "Challengee does not have enough money!")
        return
    end
    -- send accepted request to both players
    AIO.Handle(player, ADDON_NAME, "StartGame", challenger:GetName(), game.wager, game.startRoll, false) -- rolls second
    AIO.Handle(challenger, ADDON_NAME, "StartGame", player:GetName(), game.wager, game.startRoll, true) -- rolls first
    -- start game
    games[i].time = GetCurrTime()
    games[i].state = State.PROGRESS
    if DR.Config.removeGoldAtStart then
        challenger:ModifyMoney(-game.wager)
        player:ModifyMoney(-game.wager)
    end
end

local function OnCommand(event, player, command)
    if command == "dr" then
        AIO.Handle(player, ADDON_NAME, "ShowFrame")
        return false
    end
    if command == "dra" then
        HandleAcceptChallenge(player)
        return false
    end
    if command == "drd" then
        HandleDeclineChallenge(player)
        return false
    end
end

RegisterPlayerEvent(PLAYER_EVENT_ON_COMMAND, OnCommand)
CreateLuaEvent(OnTimedEventCheckTimeout, DR.Config.timedEventDelay, 0) -- infinite
