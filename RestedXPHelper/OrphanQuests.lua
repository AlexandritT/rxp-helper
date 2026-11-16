local _, Helper = ...
local window, queued
local requested = {}

local function IsPublic(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Entry(logIndex)
    if C_QuestLog and C_QuestLog.GetInfo then return C_QuestLog.GetInfo(logIndex) end
    if GetQuestLogTitle then
        local title, level, _, isHeader, _, _, _, questID = GetQuestLogTitle(logIndex)
        return { title = title, level = level, isHeader = isHeader, questID = questID }
    end
end

local function LogSize()
    local getter = C_QuestLog and C_QuestLog.GetNumQuestLogEntries or GetNumQuestLogEntries
    return getter and getter() or 0
end

local function FindQuest(questID)
    for logIndex = 1, LogSize() do
        local info = Entry(logIndex)
        if info and IsPublic(info.isHeader) and not info.isHeader
            and Helper.QuestID(info.questID) == questID then return info, logIndex end
    end
end

local function CanAbandon(questID)
    if InCombatLockdown and InCombatLockdown() then return false end
    if C_QuestLog and C_QuestLog.CanAbandonQuest then
        local allowed = C_QuestLog.CanAbandonQuest(questID)
        return IsPublic(allowed) and allowed == true
    end
    return true
end

local function Description(logIndex, questID)
    if GetQuestLogQuestText then
        local description, objectives = GetQuestLogQuestText(logIndex)
        if IsPublic(description) and type(description) == "string" and description ~= "" then
            return description, IsPublic(objectives) and objectives or nil
        end
        if IsPublic(objectives) and type(objectives) == "string" and objectives ~= "" then
            return objectives
        end
    end
    if not requested[questID] and C_QuestLog and C_QuestLog.RequestLoadQuestByID then
        requested[questID] = true
        C_QuestLog.RequestLoadQuestByID(questID)
    end
    return "Description is not available yet."
end

function Helper.GetOrphanQuests()
    local status = Helper.GetGuideIndexStatus()
    if not status.ready then
        if status.failed > 0 and not status.pending then
            return {}, "Some RXP guides could not be read. Use Rescan guides to try again."
        end
        return {}, "Waiting for the full RXP guide scan to finish..."
    end
    local quests, seen = {}, {}
    for logIndex = 1, LogSize() do
        local info = Entry(logIndex)
        if info and IsPublic(info.isHeader) and not info.isHeader then
            local id = Helper.QuestID(info.questID)
            if id and not seen[id] and not Helper.IsQuestInAnyGuide(id) then
                seen[id] = true
                local description, objectives = Description(logIndex, id)
                quests[#quests + 1] = {
                    id = id,
                    title = IsPublic(info.title) and type(info.title) == "string" and info.title or ("Quest " .. id),
                    level = IsPublic(info.level) and type(info.level) == "number" and info.level or nil,
                    description = description,
                    objectives = objectives,
                    canAbandon = CanAbandon(id),
                }
            end
        end
    end
    table.sort(quests, function(a, b)
        if a.title == b.title then return a.id < b.id end
        return a.title < b.title
    end)
    return quests
end

local function ValidateAbandon(questID)
    if not Helper.GetGuideIndexStatus().ready then return nil, "Wait for the guide scan to finish." end
    if Helper.IsQuestInAnyGuide(questID) then return nil, "This quest now belongs to an RXP guide." end
    local info, logIndex = FindQuest(questID)
    if not info then return nil, "This quest is no longer in your quest log." end
    if not CanAbandon(questID) then return nil, "This quest cannot be abandoned right now." end
    return logIndex, info
end

local function Message(text)
    if window then window.status:SetText(text) end
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffd166RestedXP Helper:|r " .. text) end
end

function Helper.AbandonOrphanQuest(value)
    local id = Helper.QuestID(value)
    if not id then return false, "Invalid quest ID." end
    local logIndex, reason = ValidateAbandon(id)
    if not logIndex then return false, reason end
    local setTarget = C_QuestLog and C_QuestLog.SetAbandonQuest or SetAbandonQuest
    local abandon = C_QuestLog and C_QuestLog.AbandonQuest or AbandonQuest
    if not setTarget or not abandon then return false, "Quest abandonment is unavailable." end
    local modern = C_QuestLog and C_QuestLog.GetSelectedQuest and C_QuestLog.SetSelectedQuest
    local previous, previousID
    if modern then
        previous = C_QuestLog.GetSelectedQuest()
        C_QuestLog.SetSelectedQuest(id)
    elseif SelectQuestLogEntry and GetQuestLogSelection then
        previous = GetQuestLogSelection()
        local info = previous and previous > 0 and Entry(previous)
        previousID = info and Helper.QuestID(info.questID)
        SelectQuestLogEntry(logIndex)
    else
        return false, "Quest selection is unavailable."
    end
    local ok, result, errorText = pcall(function()
        if modern and Helper.QuestID(C_QuestLog.GetSelectedQuest()) ~= id then
            return false, "The selected quest changed."
        end
        setTarget()
        if C_QuestLog and C_QuestLog.GetAbandonQuest then
            local target = C_QuestLog.GetAbandonQuest()
            if not IsPublic(target) or target ~= id then return false, "The quest abandonment target changed." end
        end
        abandon()
        return true
    end)
    if modern then
        if previous and previous ~= id then C_QuestLog.SetSelectedQuest(previous) end
    elseif previousID and previousID ~= id then
        local _, newIndex = FindQuest(previousID)
        if newIndex then SelectQuestLogEntry(newIndex) end
    elseif previous and previousID ~= id then
        SelectQuestLogEntry(previous)
    end
    if not ok then return false, "The client could not abandon this quest." end
    if not result then return false, errorText end
    if Helper.RefreshOrphanWindow then Helper.RefreshOrphanWindow() end
    return true
end

StaticPopupDialogs.RESTEDXPHELPER_ABANDON_ORPHAN = {
    text = "Abandon '%s'?\n\nQuest progress and quest items may be lost.",
    button1 = ABANDON_QUEST or "Abandon",
    button2 = CANCEL or "Cancel",
    OnAccept = function(_, data)
        if not data then return end
        local ok, reason = Helper.AbandonOrphanQuest(data.questID)
        if not ok then Message(reason) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function Helper.ConfirmAbandonOrphan(value)
    local id = Helper.QuestID(value)
    if not id then return end
    local logIndex, info = ValidateAbandon(id)
    if not logIndex then Message(info); return end
    StaticPopup_Show("RESTEDXPHELPER_ABANDON_ORPHAN", info.title, nil, { questID = id })
end

local function NewRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(610)
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.title:SetPoint("TOPLEFT", 0, 0)
    row.title:SetWidth(492)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(true)
    row.abandon = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.abandon:SetSize(92, 24)
    row.abandon:SetPoint("TOPRIGHT", 0, 3)
    row.abandon:SetText("Abandon")
    row.abandon:SetScript("OnClick", function() Helper.ConfirmAbandonOrphan(row.questID) end)
    row.description = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.description:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -8)
    row.description:SetWidth(610)
    row.description:SetJustifyH("LEFT")
    row.description:SetWordWrap(true)
    row.divider = row:CreateTexture(nil, "ARTWORK")
    row.divider:SetColorTexture(1, 1, 1, 0.12)
    row.divider:SetHeight(1)
    row.divider:SetPoint("BOTTOMLEFT", 0, 4)
    row.divider:SetPoint("BOTTOMRIGHT", 0, 4)
    return row
end

function Helper.RefreshOrphanWindow()
    if not window or not window:IsShown() then return end
    local quests, reason = Helper.GetOrphanQuests()
    if reason then window.status:SetText(reason)
    elseif #quests == 0 then window.status:SetText("All quests in your log belong to an installed RXP guide.")
    else window.status:SetText(#quests .. " quests outside all installed RXP guides") end
    local y = 0
    for i, quest in ipairs(quests) do
        local row = window.rows[i]
        if not row then row = NewRow(window.content); window.rows[i] = row end
        row.questID = quest.id
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, -y)
        local level = quest.level and quest.level > 0 and ("[" .. quest.level .. "] ") or ""
        row.title:SetText(level .. quest.title .. "  |cff888888#" .. quest.id .. "|r")
        local text = quest.description
        if quest.objectives and quest.objectives ~= "" and quest.objectives ~= text then
            text = text .. "\n\n" .. quest.objectives
        end
        row.description:SetText(text)
        row.abandon:SetEnabled(quest.canAbandon)
        row:SetHeight(math.max(24, row.title:GetStringHeight()) + row.description:GetStringHeight() + 28)
        row:Show()
        y = y + row:GetHeight() + 12
    end
    for i = #quests + 1, #window.rows do window.rows[i]:Hide() end
    window.content:SetHeight(math.max(1, y))
    local limit = math.max(0, y - window.scroll:GetHeight())
    if window.scroll:GetVerticalScroll() > limit then window.scroll:SetVerticalScroll(limit) end
end

function Helper.ShowOrphanWindow()
    if not window then
        window = CreateFrame("Frame", "RestedXPHelperOrphanFrame", UIParent, "BasicFrameTemplateWithInset")
        window:SetSize(680, 540)
        window:SetPoint("CENTER")
        window:SetFrameStrata("DIALOG")
        window:SetClampedToScreen(true)
        window:SetMovable(true)
        window:EnableMouse(true)
        window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart", window.StartMoving)
        window:SetScript("OnDragStop", window.StopMovingOrSizing)
        window.TitleText:SetText("RestedXP Helper - Orphan quests")
        window.status = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        window.status:SetPoint("TOPLEFT", 18, -38)
        window.status:SetWidth(640)
        window.status:SetJustifyH("LEFT")
        window.status:SetWordWrap(true)
        local subtitle = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        subtitle:SetPoint("TOPLEFT", 18, -70)
        subtitle:SetText("Current quest log / all guide groupings")
        window.scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
        window.scroll:SetPoint("TOPLEFT", 18, -96)
        window.scroll:SetPoint("BOTTOMRIGHT", -36, 48)
        window.content = CreateFrame("Frame", nil, window.scroll)
        window.content:SetSize(610, 1)
        window.scroll:SetScrollChild(window.content)
        window.rows = {}
        local rescan = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        rescan:SetSize(130, 24)
        rescan:SetPoint("BOTTOMLEFT", 18, 14)
        rescan:SetText("Rescan guides")
        rescan:SetScript("OnClick", function() Helper.RequestGuideRescan() end)
        local refresh = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        refresh:SetSize(90, 24)
        refresh:SetPoint("LEFT", rescan, "RIGHT", 8, 0)
        refresh:SetText("Refresh")
        refresh:SetScript("OnClick", Helper.RefreshOrphanWindow)
        window:SetScript("OnShow", Helper.RefreshOrphanWindow)
        table.insert(UISpecialFrames, "RestedXPHelperOrphanFrame")
    end
    requested = {}
    window.scroll:SetVerticalScroll(0)
    window:Show()
    Helper.RefreshOrphanWindow()
end

local events = CreateFrame("Frame")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_DATA_LOAD_RESULT")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function()
    if not window or not window:IsShown() or queued then return end
    queued = true
    C_Timer.After(0.1, function() queued = false; Helper.RefreshOrphanWindow() end)
end)
