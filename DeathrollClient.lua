local AIO = AIO or require("AIO")
if AIO.AddAddon() then
   return
end
local DR = {}
local ADDON_NAME = "AIODeathRoll"
local COINAGE_MAX = 2147483647
local START_ROLL_MAX = 10000
local ITEM_ID_EOF = 49426
local width = 200

local DRHandlers = {}
AIO.AddHandlers(ADDON_NAME, DRHandlers)

DR.Config = {
    currency = "gold", -- [item, gold]
    itemId = ITEM_ID_EOF, -- if using "item" as currency
    -- startRollMin = 1000,
    startRollMin = 2,
    startRollIncrement = 100,
	strings = {
        targetMustBePlayer = "Target must be a Player!",
		insufficientFunds = "You don't have enough to play",
        addonMsgPrefix = "|TInterface/ICONS/Achievement_BG_killingblow_30:14:14:2:0|t|cfffff800DeathRoll|r",
        betHigherThanMaxBet = "Bet is too high! Max bet is %s", -- %s bet with icon
        betMustBeMinimumAmount = "Bet must be at least 1",
        invalidBetAmount = "Invalid bet amount",
        sentPayoutByMail = "You have too much money! Your recent winnings have been sent by mail",
        spinIsAlreadyInProgress = "Spin is already in progress",
        waitingForServerResponse = "Waiting for server response",
        youAreWinner  = "You've won: ",
        youLost = "No luck. Try again!",
	},
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

local State = {
    IDLE = 0,
    REQUEST = 1,
    RECEIVED = 2,
    PROGRESS = 3,
}

DR.IsItMyTurn = false
DR.state = State.IDLE

-- Create main frame
-- local mainFrame = CreateFrame("Frame", "DeathRollMainFrame", UIParent, "BackdropTemplate")
local mainFrame = CreateFrame("Frame", "DeathRollMainFrame", UIParent)
mainFrame:SetSize(width, 200)
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

wagerInput:SetScript("OnEnterPressed", function(self)
    local betBoxValue = tonumber(self:GetText())
    if betBoxValue then
        local bet = DR.wager
        bet = math.min(betBoxValue*10000, GetMoney())
        bet = math.max(bet, DR.Currency[DR.Config.currency].minimumWager)
        DR.wager = bet
    else
        DR.Currency[DR.Config.currency].SetBetToMin()
    end
    self:SetText(DR.Currency[DR.Config.currency].ToString(DR.wager))
    self:ClearFocus()
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
mainButton:SetText("Challenge")
mainButton:SetNormalFontObject("GameFontNormalLarge")
mainButton:SetHighlightFontObject("GameFontHighlightLarge")

-- Create rolls frame
-- local rollsFrame = CreateFrame("Frame", "DeathRollRollsFrame", UIParent, "BackdropTemplate")
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
    -- if DR.state != State.PROGRESS or not DR.IsItMyTurn then
        -- return
    -- end
    local playerName, rollResult, minRoll, maxRoll = msg:match("^(.+) rolls (%d+) %((%d+)%-(%d+)%)")
    DR.print("OnChatMsgSystem")
    print(playerName)
    print(rollResult)
    print(minRoll)
    print(maxRoll)
    if not (playerName and rollResult and minRoll and maxRoll) then
        return
    end
    if DR.IsItMyTurn and playerName == GetUnitName("player") then
        AIO.Handle(ADDON_NAME, "Rolled", rollResult, minRoll, maxRoll)
        DR.waitingForServerResponse = true
        DR.IsItMyTurn = false
    end
    if playerName and minRoll then
    -- targetName
        local rollText = playerName .. " rolls " .. rollResult .. " (" .. minRoll .. "-" .. maxRoll .. ")"
        UpdateRolls(rollText)
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

-- Show main frame
mainFrame:Show()

local function RequestChallenge()
    if DR.waitingForServerResponse then
        DR.print(DR.Config.strings.waitingForServerResponse)
        return false
    end
    DR.print("RequestToPlay")
    if not UnitIsPlayer("target") then
        DR.print(DR.Config.strings.targetMustBePlayer)
        return false
    end
    local target = UnitName("target") -- DEBUG
    local guid = UnitGUID("target")
    DR.print(target) -- DEBUG
    DR.print(guid) -- DEBUG
    DR.waitingForServerResponse = true
    AIO.Handle(ADDON_NAME, "RequestChallenge", tonumber(guid), DR.wager, DR.startRoll)
end

-- Function to update button text and handle challenge
local function HandleClick()
    DR.print("Handle Click")
    if mainButton:GetText() == "Challenge" then
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
    DR.print(string.format("You have received a challenge from %s for %s (1-%d)\ntype .draccept to accept this challenge!", name, wagerFormatted, startRoll))
    DR.state = State.RECEIVED
    mainFrame:Show()
end

function DRHandlers.ChallengeRequestPending(player, name)
    DR.print("Challenge Request pending!")
    DR.state = State.PENDING
    mainButton:SetText("Roll")
end

function DRHandlers.ChallengeRequestDenied(player, reason)
    DR.print(string.format("Challenge Request denied! %s", reason))
    DR.state = State.IDLE
    DR.waitingForServerResponse = false
end

function DRHandlers.RollMessage(player, reason)
    DR.print(string.format("RollMessage %s", reason))
    DR.waitingForServerResponse = false
    DR.IsItMyTurn = true
end

function DRHandlers.YourTurn(player, maxRoll)
    print("YOUR TURN RECEIVED")
    DR.print(string.format("RollMessage /roll %d", maxRoll))
    DR.IsItMyTurn = true
    DR.waitingForServerResponse = false
end

-- pick a random happy emote from a list
local function GetRandomHappyEmote()
    local happyEmotes = {"CHEER", "LAUGH", "VICTORY", "SALUTE", "DANCE"}
    local randomIndex = math.random(1, #happyEmotes)
    return happyEmotes[randomIndex]
end

function DRHandlers.YouWin(player, wager)
    local wagerFormatted = DR.Currency[DR.Config.currency].ToString(wager)..DR.Currency[DR.Config.currency].txtIcon
    DR.print(string.format("YOU WIN! %s", wagerFormatted))
    DR.IsItMyTurn = false
    DR.waitingForServerResponse = false
    DR.state = State.PENDING
    DoEmote(GetRandomHappyEmote())
end

function DRHandlers.YouLose(player)
    DR.print("YOU LOSE")
    DR.IsItMyTurn = false
    DR.waitingForServerResponse = false
    DR.state = State.PENDING
end

function DRHandlers.StartGame(player, name, wager, startRoll, firstRoll)
    local wagerFormatted = DR.Currency[DR.Config.currency].ToString(wager)..DR.Currency[DR.Config.currency].txtIcon
    local startString
    if firstRoll then
        DR.IsItMyTurn = true
        DR.waitingForServerResponse = false
        startString = string.format("You start first! /roll %d", startRoll)
    else
        DR.IsItMyTurn = false
        DR.waitingForServerResponse = true
        startString = string.format("Waiting for opponent to roll (1-%d)", startRoll)
    end
    DR.print(string.format("Start game against %s for %s (1-%d)!\n%s", name, wagerFormatted, startRoll, startString))
    DR.state = State.PROGRESS
end

