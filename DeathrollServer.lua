local AIO = AIO or require("AIO")
local DRHandlers = {}
AIO.AddHandlers("AIODeathRoll", DRHandlers)
local DR = {}
local ADDON_NAME = "AIODeathRoll"
local COINAGE_MAX = 2147483647
local PLAYER_EVENT_ON_COMMAND  = 42 -- (event, player, command, chatHandler) - player is nil if command used from console. Can return false
local MAIL_STATIONERY_GM = 61
local State = { -- server-side state
    PENDING = 1,
    PROGRESS = 2,
    COMPLETED = 3,
    NOTREFUNDED = 4,
    REFUNDCHALLENGER = 8,
    REFUNDTARGET = 16,
    --  = 32,
}

DR.Config = {
    removeGoldAtStart = true, -- default: true
    customDbName = 'ac_eluna',
    enableDB = true, -- default: true, should be used with removeGoldAtStart enabled, saves games that are in progress so any crashes will refund players on startup
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
    startRollMin = 1000, -- default: 1000
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

-- find games that are in progress and cancel them
local function OnLoadSetGamesInProgressToRefund()
    local queryUpdate = string.format("UPDATE `%s`.`deathroll` SET `status`=%d WHERE `status` = %d;", DR.Config.customDbName, State.NOTREFUNDED, State.PROGRESS)
    CharDBQuery(queryUpdate)
end

local function eq(guid1, guid2)
    return tostring(guid1) == tostring(guid2)
end

local function HandleRefund(player)
    -- .refund
    -- grab games where status State.NOTREFUNDED
    local playerGUID = player:GetGUID()
    local querySelect = string.format("SELECT id, challengerGUID, targetGUID, wager, status FROM `%s`.`deathroll` WHERE `status` & %d;", DR.Config.customDbName, State.NOTREFUNDED)
    local Query = CharDBQuery(querySelect)
    local gamesNotYetRefunded = {}
    if Query then
        repeat
            local id = Query:GetInt32(0)
            local challengerGUID = Query:GetUInt64(1)
            local targetGUID = Query:GetUInt64(2)
            local wager = Query:GetInt32(3)
            local status = Query:GetInt32(4)
            table.insert(gamesNotYetRefunded, 1, {id=id, challenger = challengerGUID, target = targetGUID, wager = wager, status = status})
        until not Query:NextRow()
    end
    -- refund gold to players
    if DR.Config.removeGoldAtStart then
        for i, game in ipairs(gamesNotYetRefunded) do
            local target = GetPlayerByGUID(game.target)
            local wager = game.wager
            if target and (game.status == State.NOTREFUNDED or game.status == (State.NOTREFUNDED+State.REFUNDCHALLENGER)) then
                local queryUpdate = string.format("UPDATE `%s`.`deathroll` SET `status`=`status`|%d WHERE `id` = %d;", DR.Config.customDbName, State.REFUNDTARGET, game.id)
                CharDBExecute(queryUpdate)
                DoPayoutGold(target, wager)
                AIO.Handle(target, ADDON_NAME, "Refund", wager)
            end
            local challenger = GetPlayerByGUID(game.challenger)
            if challenger and (game.status == State.NOTREFUNDED or game.status == (State.NOTREFUNDED+State.REFUNDTARGET)) then
                local queryUpdate = string.format("UPDATE `%s`.`deathroll` SET `status`=`status`|%d WHERE `id` = %d;", DR.Config.customDbName, State.REFUNDCHALLENGER, game.id)
                CharDBExecute(queryUpdate)
                DoPayoutGold(challenger, wager)
                AIO.Handle(challenger, ADDON_NAME, "Refund", wager)
            end
        end
    end
    -- delete game if everyone is refunded
    if #gamesNotYetRefunded > 0 then
        local queryDelete = string.format("DELETE FROM `%s`.`deathroll` WHERE `status`=(4|8|16);", DR.Config.customDbName)
        CharDBExecute(queryDelete)
    end
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
                    -- update db
                    if DR.Config.enableDB then
                        local queryUpdate = string.format("UPDATE `%s`.`deathroll` SET `status`=%d WHERE `challengerGUID`=%s AND `targetGUID`=%s AND `status`=%d;",
                            DR.Config.customDbName, State.COMPLETED, tostring(game.challenger), tostring(game.target), State.PROGRESS)
                        CharDBExecute(queryUpdate)
                    end
                    table.insert(toBeRemoved, i)
                end
            elseif game.state == State.PENDING or game.state == State.PROGRESS then
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
                        -- update game in db
                        if DR.Config.enableDB then
                            local queryUpdate = string.format("UPDATE `%s`.`deathroll` SET `status`=%d WHERE `challengerGUID`=%s AND `targetGUID`=%s AND `status`=%d;",
                                DR.Config.customDbName, State.COMPLETED, tostring(game.challenger), tostring(game.target), State.PROGRESS)
                            CharDBExecute(queryUpdate)
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
        -- table.remove(games, toBeRemoved[i])
        games[i].state = State.COMPLETED
    end
end

local function FindGame(playerGUID)
    for i, game in ipairs(games) do
        if game and (eq(game.target,  playerGUID) or eq(game.challenger, playerGUID)) and game.state ~= State.COMPLETED then
            return i
        end
    end
    return 0
end

function DRHandlers.Roll(player)
    local playerGUID = player:GetGUID()
    local i = FindGame(playerGUID)
    if not i then
        PrintError("No game foud!")
        return
    end
    local game = games[i]
    -- do roll
    local maxRoll = game.rolls and game.rolls[1].result or game.startRoll
    local rollResult = math.random(1,maxRoll)
    local roll = { -- only store valid rolls
        player = playerGUID,
        result = rollResult,
        max = maxRoll,
        time = GetCurrTime(),
    }
    AIO.Handle(player, ADDON_NAME, "YouRolled", rollResult, maxRoll)
    -- add roll
    if not game.rolls then
        -- first roll
        games[i].rolls = {roll}
    else
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
        -- table.remove(games, i)
        games[i].state = State.COMPLETED
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
    -- Check if target self
    if eq(playerGUID, targetGUID) then
        AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "Cannot challenge yourself!")
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
    -- table.remove(games, i)
    games[i].state = State.COMPLETED
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
    if game == nil then
        AIO.Handle(player, ADDON_NAME, "ChallengeRequestDenied", "No game found to accept!")
        return
    end
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
    -- insert game into db
    if DR.Config.enableDB then
        local queryInsert = string.format("INSERT INTO `%s`.`deathroll` (`challengerGUID`, `targetGUID`, `wager`, `status`) VALUES (%d, %s, %s, %d);",
            DR.Config.customDbName, tostring(game.challenger), tostring(game.target), game.wager, State.PROGRESS)
        CharDBExecute(queryInsert)
    end
end

local function OnCommand(event, player, command)
    if command == "dr" then
        AIO.Handle(player, ADDON_NAME, "ShowFrame")
        return false
    end
    if command == "drroll" then
        DRHandlers.Roll(player)
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
    if command == "drrefund" then
        PrintInfo(string.format("%s:OnCommand .drrefund by account-name (%d-%s)", ADDON_NAME, player:GetAccountId(), player:GetName()))
        HandleRefund(player)
        return false
    end
end

RegisterPlayerEvent(PLAYER_EVENT_ON_COMMAND, OnCommand)
CreateLuaEvent(OnTimedEventCheckTimeout, DR.Config.timedEventDelay, 0) -- infinite

if DR.Config.enableDB then
    -- Create database and table if not exists
    CharDBQuery('CREATE DATABASE IF NOT EXISTS `' .. DR.Config.customDbName .. '`;');
    CharDBQuery('CREATE TABLE IF NOT EXISTS `' .. DR.Config.customDbName .. '`.`deathroll` ( `id` INT UNSIGNED auto_increment NOT NULL, `challengerGUID` VARCHAR(100) NOT NULL, `targetGUID` VARCHAR(100) NOT NULL, `wager` INTEGER NOT NULL, `status` INTEGER DEFAULT 0 NULL, `time` TIMESTAMP DEFAULT CURRENT_TIMESTAMP NULL, CONSTRAINT `id` PRIMARY KEY (`id`)) AUTO_INCREMENT=1;')
    OnLoadSetGamesInProgressToRefund()
end
