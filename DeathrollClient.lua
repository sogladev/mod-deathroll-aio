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
    startRollMin = 1000,
    startRollIncrement = 100,
	strings = {
		insufficientFunds = "You don't have enough to play",
        addonMsgPrefix = "|TInterface/MoneyFrame/UI-GoldIcon:14:14:2:0|t|cfffff800SlotMachine|r",
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

DR.wager = DR.Currency[DR.Config.currency].minimumWager
DR.startRoll = DR.Config.startRollMin

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
wagerInput:SetText(DR.wager)
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
local challengeButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
challengeButton:SetSize(140, 40)
challengeButton:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, 20)
challengeButton:SetText("Challenge")
challengeButton:SetNormalFontObject("GameFontNormalLarge")
challengeButton:SetHighlightFontObject("GameFontHighlightLarge")

-- Function to update button text and handle challenge
local function handleChallenge()
    if challengeButton:GetText() == "Challenge" then
        challengeButton:SetText("Roll")
        -- Handle request challenge logic here
    else
        -- Handle roll logic here
    end
end

challengeButton:SetScript("OnClick", handleChallenge)

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
local function updateRolls(newRoll)
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
    local playerName, rollResult, minRoll, maxRoll = msg:match("^(.+) rolls (%d+) %((%d+)%-(%d+)%)")
    if playerName and minRoll then
    -- targetName
        local rollText = playerName .. " rolls " .. rollResult .. " (" .. minRoll .. "-" .. maxRoll .. ")"
        updateRolls(rollText)
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
