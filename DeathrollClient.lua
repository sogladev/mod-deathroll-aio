local AIO = AIO or require("AIO")
if AIO.AddAddon() then
   return
end
local DR = {}
local ADDON_NAME = "AIODeathRoll"
local COINAGE_MAX = 2147483647
local START_ROLL_MAX = 10000

local DRHandlers = {}
AIO.AddHandlers(ADDON_NAME, DRHandlers)

DR.Config = {
    currency = "gold",
    startRollIncrement = 100,
	strings = {
        challenge = "Challenge",
        waitingOpponent = "Waiting...",
        addonMsgPrefix = "|TInterface/ICONS/Achievement_BG_killingblow_30:14:14:2:0|t|cfffff800DeathRoll|r",
        targetMustBePlayer = "Target must be a Player!",
        waitingForServerResponse = "Waiting for server response",
        gameStartReminder = "You have 30 seconds between each roll! Good luck!",
        youAreWinner  = "You've won: %s", -- %s wager formatted
        youLost = "No luck. You've lost: %s", -- %s wager formatted
	},
    showRollsFrame = false,
    timeBetweenGamesInSeconds = 3, -- after win/lose disable button for this amount
    -- Below need to match server
    startRollMin = 2, -- default: 1000
}

DR.Currency = {
    ["gold"] = {
        icon = "Interface/MoneyFrame/UI-GoldIcon",
        txtIcon = "|TInterface/MoneyFrame/UI-GoldIcon:14:14:2:0|t",
        ToString = function(i) return tostring(math.floor(i/10000)) end, -- copper to gold to string
        minimumWager = 10000,
        SetWagerToMin = function() DR.wager = 10000 end,
    },
}


-- print with addon prefix
function DR.print(message)
    print(DR.Config.strings.addonMsgPrefix .. " " .. message)
end

DR.wager = DR.Currency[DR.Config.currency].minimumWager
DR.startRoll = DR.Config.startRollMin
DR.roll = DR.startRoll
DR.waitingForServerResponse = false
DR.timeBetweenGamesElapsed = 0
DR.finishedGame = false


local State = {
    IDLE = 0,
    REQUEST = 1,
    RECEIVED = 2,
    PROGRESS = 3,
}

DR.isItMyTurn = false
DR.state = State.IDLE

-- Create main frame
-- local mainFrame = CreateFrame("Frame", "DeathRollMainFrame", UIParent, "BackdropTemplate")
local mainFrame = CreateFrame("Frame", "DeathRollMainFrame", UIParent)
mainFrame:SetSize(200, 200)
mainFrame:SetBackdrop({
    bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
mainFrame:SetBackdropColor(0, 0, 0, 1)
-- mainFrame: title
mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY")
mainFrame.title:SetFontObject("GameFontNormalMed3")
mainFrame.title:SetPoint("TOP", mainFrame, "TOP", 0, -15)
mainFrame.title:SetText("Death Roll")
mainFrame:SetPoint("CENTER")
mainFrame:SetToplevel(true)
mainFrame:SetClampedToScreen(true)
-- mainFrame: Enable dragging
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
mainFrame:SetScript("OnHide", mainFrame.StopMovingOrSizing)
mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
-- This enables saving of the position of the frame over reload of the UI or restarting game
AIO.SavePosition(mainFrame)

-- mainFrame: Close button
local closeButton = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
closeButton:SetPoint("LEFT", mainFrame.title, "RIGHT", 25, 0)
closeButton:SetScript("OnClick", function(self)
    mainFrame:Hide()
end)

-- mainFrame: wager input
local wagerInput = CreateFrame("EditBox", "WagerInput", mainFrame, "InputBoxTemplate")
wagerInput:SetAutoFocus(false)
wagerInput:SetNumeric(true)
wagerInput:SetMaxLetters(6)
wagerInput:SetTextInsets(0, 18, 0, 0)
wagerInput:SetJustifyH("CENTER")
wagerInput:SetPoint("TOP", mainFrame.title, "TOP", 0, -40)
wagerInput:SetSize(65, 25)
wagerInput:SetText(DR.Currency[DR.Config.currency].ToString(DR.wager))

local function UpdateWagerFromInput()
    local betBoxValue = tonumber(wagerInput:GetText())
    if betBoxValue then
        local bet = DR.wager
        bet = math.min(betBoxValue*10000, GetMoney())
        bet = math.max(bet, DR.Currency[DR.Config.currency].minimumWager)
        DR.wager = bet
    else
        DR.Currency[DR.Config.currency].SetBetToMin()
    end
    wagerInput:SetText(DR.Currency[DR.Config.currency].ToString(DR.wager))
    wagerInput:ClearFocus()
end

wagerInput:SetScript("OnEnterPressed", function()
    UpdateWagerFromInput()
end)
-- mainFrame: wager min button
local wagerMin = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
wagerMin:SetText("Min")
wagerMin:SetNormalFontObject("GameFontNormalSmall")
wagerMin:SetHighlightFontObject("GameFontNormalSmall")
wagerMin:SetPoint("RIGHT", wagerInput, "LEFT", -5, 0)
wagerMin:SetPushedTextOffset(0, 0)
wagerMin:SetSize(32, 20)
wagerMin:SetScript("OnClick", function()
    DR.wager = DR.Currency[DR.Config.currency].minimumWager
    wagerInput:SetText(DR.Currency[DR.Config.currency].ToString(DR.wager))
end)
-- mainFrame: wager increment button
local wagerIncrement = CreateFrame("Button", nil, mainFrame)
wagerIncrement:SetNormalTexture("Interface/ChatFrame/UI-ChatIcon-ScrollUp-Up")
wagerIncrement:SetHighlightTexture("Interface/Buttons/UI-Common-MouseHilight")
wagerIncrement:SetPushedTexture("Interface/ChatFrame/UI-ChatIcon-ScrollUp-Down")
wagerIncrement:SetDisabledTexture("Interface/ChatFrame/UI-ChatIcon-ScrollUp-Disabled")
wagerIncrement:SetPoint("LEFT", wagerInput, "RIGHT", 0, 0)
wagerIncrement:SetSize(25, 25)
wagerIncrement:SetScript("OnClick", function()
    local betBoxValue = tonumber(wagerInput:GetText())
    if betBoxValue then
        local bet = DR.wager
        bet = math.min(bet+10000, GetMoney())
        DR.wager = bet
    else
        DR.wager = DR.Currency[DR.Config.currency].minimumWager
    end
    wagerInput:SetText(DR.Currency[DR.Config.currency].ToString(DR.wager))
end)

-- mainFrame: wager input gold texture
local wagerInputGold = wagerInput:CreateTexture(nil, "OVERLAY")
wagerInputGold:SetTexture(DR.Currency[DR.Config.currency].icon)
wagerInputGold:SetPoint("RIGHT", -6, 0)
wagerInputGold:SetSize(13, 13)
-- mainFrame: wager input texture
local wagerText = mainFrame:CreateFontString(nil, "OVERLAY")
wagerText:SetFontObject("GameFontNormal")
wagerText:SetPoint("BOTTOM", wagerInput, "CENTER", -5, 15)
wagerText:SetText("Bet")

-- mainFrame: start roll input
local startInput = CreateFrame("EditBox", "StartInput", mainFrame, "InputBoxTemplate")
startInput:SetAutoFocus(false)
startInput:SetNumeric(true)
startInput:SetMaxLetters(5)
startInput:SetTextInsets(0, 13, 0, 0)
startInput:SetJustifyH("CENTER")
startInput:SetPoint("TOP", wagerInput, "BOTTOM", 0, -25)
startInput:SetSize(65, 25)
startInput:SetMaxLetters(5)
startInput:SetText(DR.startRoll)
startInput:SetScript("OnEnterPressed", function(self)
    local betBoxValue = tonumber(self:GetText())
    if betBoxValue then
        local bet = DR.wager
        bet = math.max(betBoxValue, DR.Config.startRollMin)
        bet = math.min(bet, START_ROLL_MAX)
        DR.startRoll = bet
    else
       DR.startRoll = DR.Config.startRollMin
    end
    self:SetText(tostring(DR.startRoll))
    self:ClearFocus()
end)
-- mainFrame: set roll minus
local startMin = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
startMin:SetPoint("RIGHT", startInput, "LEFT", -8, 0)
startMin:SetText("-")
startMin:SetHighlightFontObject("GameFontNormalSmall")
startMin:SetSize(25, 25)
startMin:SetScript("OnClick", function()
    local betBoxValue = tonumber(startInput:GetText())
    if betBoxValue then
        local bet = DR.startRoll
        bet = math.max(bet-DR.Config.startRollIncrement, DR.Config.startRollMin)
        DR.startRoll = bet
    else
        DR.startRoll = DR.Config.startRollMin
    end
    startInput:SetText(tostring(DR.startRoll))
end)
-- mainFrame: set roll plus
local startPlus = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
startPlus:SetPoint("LEFT", startInput, "RIGHT", 2, 0)
startPlus:SetText("+")
startPlus:SetHighlightFontObject("GameFontNormalSmall")
startPlus:SetSize(25, 25)
startPlus:SetScript("OnClick", function()
    local betBoxValue = tonumber(startInput:GetText())
    if betBoxValue then
        local bet = DR.startRoll
        bet = math.min(bet+DR.Config.startRollIncrement, START_ROLL_MAX)
        DR.startRoll = bet
    else
        DR.startRoll = DR.Config.startRollMin
    end
    startInput:SetText(tostring(DR.startRoll))
end)
-- mainFrame: set roll text
local startText = mainFrame:CreateFontString(nil, "OVERLAY")
startText:SetFontObject("GameFontNormal")
startText:SetPoint("BOTTOM", startInput, "CENTER", -5, 15)
startText:SetText("Start Roll")

-- mainFrame: Challenge button
local mainButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
mainButton:SetSize(140, 40)
mainButton:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, 20)
mainButton:SetText(DR.Config.strings.challenge)
mainButton:SetNormalFontObject("GameFontNormalLarge")
mainButton:SetHighlightFontObject("GameFontHighlightLarge")

if (DR.Config.showRollsFrame) then
-- Create rolls frame
local rollsFrame = CreateFrame("Frame", "DeathRollRollsFrame", mainFrame)
rollsFrame:SetSize(240, 120)
rollsFrame:SetPoint("TOP", mainFrame, "BOTTOM", 0, -10)
rollsFrame:SetBackdrop({
    bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
rollsFrame:SetBackdropColor(0, 0, 0, 1)

rollsFrame.title = rollsFrame:CreateFontString(nil, "OVERLAY")
rollsFrame.title:SetFontObject("GameFontNormalMed3")
rollsFrame.title:SetPoint("TOP", rollsFrame, "TOP", 0, -15)
rollsFrame.title:SetText("Rolls")

-- Rolls text
local rollsText = rollsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
rollsText:SetPoint("TOP", rollsFrame.title, 2, -10)
rollsText:SetSize(200, 90)
rollsText:SetJustifyH("LEFT")
rollsText:SetText("Rolls will be shown here")
end -- end RollsFrame

-- Function to update rolls
local function UpdateRolls(newRoll)
    local text = rollsText:GetText()
    local lines = {strsplit("\n", text)}
    if #lines >= 5 then
        table.remove(lines, 1)
    end
    table.insert(lines, newRoll)
    rollsText:SetText(table.concat(lines, "\n"))
end

-- Function to handle system chat messages and detect rolls
local function OnChatMsgSystem(self, event, msg)
    if DR.state ~= State.PROGRESS or not DR.isItMyTurn then
        return
    end
    local playerName, rollResult, minRoll, maxRoll = msg:match("^(.+) rolls (%d+) %((%d+)%-(%d+)%)")
    if not (playerName and rollResult and minRoll and maxRoll) then
        return
    end
    if DR.isItMyTurn and playerName == GetUnitName("player") then
        AIO.Handle(ADDON_NAME, "Rolled", rollResult, minRoll, maxRoll)
        DR.waitingForServerResponse = true
        DR.isItMyTurn = false
        mainButton:SetText(DR.Config.strings.waitingOpponent)
        mainButton:Disable()
    end
    if (DR.Config.showRollsFrame) then
        if playerName and minRoll then
            local rollText = playerName .. " rolls " .. rollResult .. " (" .. minRoll .. "-" .. maxRoll .. ")"
            UpdateRolls(rollText)
        end
    end
end

-- Set a single OnEvent handler for both events
mainFrame:SetScript("OnEvent", function(self, event, msg, ...)
    if event == "CHAT_MSG_SYSTEM" then
        self:OnChatMsgSystem(event, msg)
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- self:OnPlayerRegenDisabled(...)
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- self:OnPlayerRegenEnabled(...)
    end
end)
-- Register event for system chat messages
mainFrame:RegisterEvent("CHAT_MSG_SYSTEM")
mainFrame:SetScript("OnEvent", OnChatMsgSystem)

local function RequestChallenge()
    UpdateWagerFromInput()
    if DR.waitingForServerResponse then
        DR.print(DR.Config.strings.waitingForServerResponse)
        return false
    end
    DR.print("RequestToPlay")
    if not UnitIsPlayer("target") then
        DR.print(DR.Config.strings.targetMustBePlayer)
        return false
    end
    local guid = UnitGUID("target")
    DR.waitingForServerResponse = true
    AIO.Handle(ADDON_NAME, "RequestChallenge", tonumber(guid), DR.wager, DR.startRoll)
end

-- Function to update button text and handle challenge
local function HandleClick()
    wagerInput:ClearFocus()
    startInput:ClearFocus()
    if mainButton:GetText() == DR.Config.strings.challenge then
        DR.print("Handle Challenge")
        RequestChallenge()
    else
        DR.print("Handle Roll")
        RandomRoll(1, DR.roll)
    end
end

mainButton:SetScript("OnClick", HandleClick)

-- Handlers
function DRHandlers.ShowFrame(player)
    mainFrame:Show()
end

function DRHandlers.ChallengeReceived(player, name, wager, startRoll)
    local wagerFormatted = DR.Currency[DR.Config.currency].ToString(wager)..DR.Currency[DR.Config.currency].txtIcon
    DR.print(string.format("You have received a challenge from %s for %s (1-%d)\ntype .dra to accept or .drd to decline this challenge!", name, wagerFormatted, startRoll))
    DR.state = State.RECEIVED
    mainFrame:Show()
end

function DRHandlers.ChallengeRequestPending(player, name)
    DR.print(string.format("Challenge Request to %s pending!", name))
    DR.state = State.PENDING
    mainButton:SetText(DR.Config.strings.waitingOpponent)
    mainButton:Disable()
end

function DRHandlers.ChallengeRequestDenied(player, reason)
    DR.print(string.format("Challenge Request denied! %s", reason))
    DR.SetStateToIdle()
end

function DRHandlers.RollMessage(player, reason)
    DR.print(string.format("RollMessage %s", reason))
    DR.waitingForServerResponse = false
    DR.isItMyTurn = true
    mainButton:Enable()
end

function DRHandlers.YourTurn(player, maxRoll)
    DR.print(string.format("Your opponent rolled %s", maxRoll))
    DR.print(string.format("/roll %d", maxRoll))
    DR.isItMyTurn = true
    DR.waitingForServerResponse = false
    DR.roll = maxRoll
    mainButton:SetText("Roll "..maxRoll)
    mainButton:Enable()
end

-- pick a random happy emote from a list
local function GetRandomHappyEmote()
    local happyEmotes = {"CHEER", "LAUGH", "VICTORY", "SALUTE", "DANCE"}
    local randomIndex = math.random(1, #happyEmotes)
    return happyEmotes[randomIndex]
end

function DRHandlers.YouWin(player, wager)
    local wagerFormatted = DR.Currency[DR.Config.currency].ToString(wager)..DR.Currency[DR.Config.currency].txtIcon
    DR.isItMyTurn = false
    DR.waitingForServerResponse = false
    mainButton:SetText("Won")
    mainButton:Disable()
    DR.print(string.format(DR.Config.strings.youAreWinner, wagerFormatted))
    DoEmote(GetRandomHappyEmote())
    DR.finishedGame = true
end

-- Function to pick a random sad emote from a list
local function GetRandomSadEmote()
    local sadEmotes = {"CRY", "SIGH", "SURRENDER", "LAYDOWN", "CONGRATULATE"} -- Add more sad emotes as needed
    local randomIndex = math.random(1, #sadEmotes)
    return sadEmotes[randomIndex]
end

function DRHandlers.YouLose(player, wager)
    local wagerFormatted = DR.Currency[DR.Config.currency].ToString(wager)..DR.Currency[DR.Config.currency].txtIcon
    DR.isItMyTurn = false
    DR.waitingForServerResponse = false
    mainButton:SetText("Lost")
    mainButton:Disable()
    DR.print(string.format(DR.Config.strings.youLost, wagerFormatted))
    DoEmote(GetRandomSadEmote())
    DR.finishedGame = true
end

mainFrame:SetScript("OnUpdate", function(self, dt)
        if DR.finishedGame then
            DR.timeBetweenGamesElapsed = DR.timeBetweenGamesElapsed + dt
            if (DR.timeBetweenGamesElapsed >= DR.Config.timeBetweenGamesInSeconds) then
                DR.timeBetweenGamesElapsed = 0
                DR.SetStateToIdle()
            end
        end
end)

function DRHandlers.StartGame(player, name, wager, startRoll, firstRoll)
    local wagerFormatted = DR.Currency[DR.Config.currency].ToString(wager)..DR.Currency[DR.Config.currency].txtIcon
    local startString
    DR.roll = tonumber(startRoll)
    -- Disable inputs
    wagerMin:Disable()
    wagerIncrement:Disable()
    wagerInput:ClearFocus()
    startInput:ClearFocus()
    wagerInput:EnableMouse(false)
    startInput:EnableMouse(false)
    startPlus:Disable()
    startMin:Disable()
    if firstRoll then
        DR.isItMyTurn = true
        DR.waitingForServerResponse = false
        startString = string.format("You start first! /roll %d", startRoll)
        mainButton:SetText("Roll "..startRoll)
        mainButton:Enable()
    else
        -- challengee
        wagerInput:SetText(DR.Currency[DR.Config.currency].ToString(wager))
        startInput:SetText(startRoll)
        DR.startRoll = tonumber(startRoll)
        DR.isItMyTurn = false
        DR.waitingForServerResponse = true
        startString = string.format("Waiting for opponent to roll (1-%d)", startRoll)
        mainButton:SetText(DR.Config.strings.waitingOpponent)
        mainButton:Disable()
    end
    DR.print(string.format("Starting game against %s for %s (1-%d)!", name, wagerFormatted, startRoll))
    DR.print(DR.Config.strings.gameStartReminder)
    DR.print(startString)
    DR.state = State.PROGRESS
end

-- Show main frame
mainFrame:Show() -- remove for release

function DR.SetStateToIdle()
    -- Enable inputs
    wagerInput:ClearFocus()
    startInput:ClearFocus()
    wagerInput:EnableMouse(true)
    startInput:EnableMouse(true)
    wagerMin:Enable()
    wagerIncrement:Enable()
    startPlus:Enable()
    startMin:Enable()
    mainButton:SetText(DR.Config.strings.challenge)
    mainButton:Enable()
    DR.state = State.IDLE
    DR.waitingForServerResponse = false
    DR.finishedGame = false
end
