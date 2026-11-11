local addonName = ...

local defaults = {
    enabled = true,
    sound = true,
}

local db
local warned = false
local scanPending = false
local scanAllowAlert = false
local repeatTimer
local warningToken = 0
local SetupOptions

local alert = CreateFrame("Frame", "BuffFoodAlertFrame", UIParent)
alert:SetSize(260, 42)
alert:SetPoint("TOP", UIParent, "TOP", 0, -100)
alert:SetFrameStrata("HIGH")
alert:Hide()

local background = alert:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints()
background:SetColorTexture(0.03, 0.04, 0.06, 0.88)

local accent = alert:CreateTexture(nil, "BORDER")
accent:SetPoint("TOPLEFT")
accent:SetPoint("BOTTOMLEFT")
accent:SetWidth(4)
local _, playerClass = UnitClass("player")
local classColor = playerClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[playerClass]
if classColor then
    accent:SetColorTexture(classColor.r, classColor.g, classColor.b, 1)
else
    accent:SetColorTexture(1, 1, 1, 1)
end

local text = alert:CreateFontString(nil, "ARTWORK", "GameFontNormal")
text:SetPoint("CENTER")
text:SetTextColor(1, 0.15, 0.15)
text:SetText("Well Fed Buff Missing")

local close = CreateFrame("Button", nil, alert)
close:SetSize(26, 26)
close:SetPoint("TOPRIGHT", -3, -1)
close:SetFrameLevel(alert:GetFrameLevel() + 2)
local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
closeText:SetAllPoints()
closeText:SetText("X")
closeText:SetTextColor(0.8, 0.8, 0.8)
close:SetScript("OnClick", function()
    warningToken = warningToken + 1
    alert:Hide()
end)

local function Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffBuff Food Alert:|r " .. message)
    end
end

local function HasFoodBuff()
    -- Forever uses the modern aura API. The name-based lookup is important:
    -- different food items can apply different spell IDs, but their active
    -- buff is still named "Well Fed".
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", "Well Fed", "HELPFUL")
        if ok and aura then return true end
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for index = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
            if not ok or not aura then break end
            local name = aura.name
            if type(name) == "string" and name:lower():find("well fed", 1, true) then
                return true
            end
        end
    end

    return false
end

local function ShowWarning()
    if InCombatLockdown and InCombatLockdown() then return end
    warningToken = warningToken + 1
    local token = warningToken
    alert:Show()
    C_Timer.After(6, function()
        if token == warningToken then alert:Hide() end
    end)
    if db.sound and PlaySound then
        PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or "RaidWarning")
    end
end

local function StopRepeating()
    if repeatTimer then
        repeatTimer:Cancel()
        repeatTimer = nil
    end
end

local function Scan()
    local allowAlert = scanAllowAlert
    scanAllowAlert = false
    scanPending = false
    if not db then SetupOptions() end
    if not db.enabled then return end

    local hasFood = HasFoodBuff()
    if hasFood then
        warned = false
        StopRepeating()
        warningToken = warningToken + 1
        alert:Hide()
    elseif not warned then
        if not allowAlert then return end
        warned = true
        ShowWarning()
    end
end

local function QueueScan(allowAlert)
    if allowAlert then scanAllowAlert = true end
    if scanPending then return end
    scanPending = true
    C_Timer.After(0.2, Scan)
end

SetupOptions = function()
    db = BUFF_FOOD_ALERT_DB or {}
    db.enabled = true
    if db.sound == nil then db.sound = defaults.sound end
end

SLASH_BUFFFOODALERT1 = "/bfa"
SlashCmdList.BUFFFOODALERT = function(message)
    message = (message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if message == "on" then
        db.enabled = true
        warned = false
        Print("enabled.")
        QueueScan()
    elseif message == "off" then
        db.enabled = false
        StopRepeating()
        alert:Hide()
        Print("disabled.")
    elseif message == "sound" then
        db.sound = not db.sound
        Print("sound " .. (db.sound and "enabled." or "disabled."))
    elseif message == "test" then
        ShowWarning()
    else
        Print("/bfa on, /bfa off, /bfa sound, or /bfa test")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("PLAYER_ALIVE")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and unit ~= "player" then return end
    if event == "PLAYER_REGEN_DISABLED" then
        alert:Hide()
        warned = false
        return
    end
    if event == "ADDON_LOADED" then
        SetupOptions()
    elseif event == "PLAYER_LOGIN" then
        SetupOptions()
    end
    QueueScan(event == "PLAYER_REGEN_ENABLED")
end)

-- Do not rely only on login events. Forever can finish restoring the player
-- after those events, so perform a delayed startup scan as well.
SetupOptions()
C_Timer.After(2, function() Scan() end)
