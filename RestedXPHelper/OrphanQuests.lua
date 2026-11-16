local _, Helper = ...
local queued
local requested = {}
local dungeonDB, dungeonIDs

function Helper.GetOrphanSettings()
    RestedXPHelperDB = RestedXPHelperDB or {}
    return RestedXPHelperDB
end

function Helper.ResetOrphanDescriptionRequests()
    requested = {}
end

function Helper.IsDungeonQuest(questID)
    local tagID
    if C_QuestLog and C_QuestLog.GetQuestTagInfo then
        local tag = C_QuestLog.GetQuestTagInfo(questID)
        if tag and not (issecretvalue and issecretvalue(tag)) then tagID = tag.tagID end
    elseif GetQuestTagInfo then
        tagID = GetQuestTagInfo(questID)
    end
    if not (issecretvalue and issecretvalue(tagID)) then
        local tags = Enum and Enum.QuestTag or {}
        -- Native Classic quest types: Dungeon 81 and Heroic dungeon 85.
        if tagID == (tags.Dungeon or 81) or tagID == (tags.Heroic or 85) then return true end
    end
    -- Forever has custom dungeon quests whose native tag may be missing.
    local dj = _G.ForeverDungeonJournal_NS
    local db = dj and dj.DB
    if db ~= dungeonDB or not dungeonIDs then
        dungeonDB, dungeonIDs = db, {}
        for _, dungeon in pairs(db or {}) do
            for _, quest in ipairs(dungeon.quests or {}) do
                local id = Helper.QuestID(quest.id)
                if id then dungeonIDs[id] = true end
            end
        end
    end
    return dungeonIDs[questID] == true
end

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

function Helper.GetOrphanQuests(excludeDungeons)
    if excludeDungeons == nil then excludeDungeons = Helper.GetOrphanSettings().excludeDungeonQuests == true end
    local status = Helper.GetGuideIndexStatus()
    if not status.ready then
        if status.failed > 0 and not status.pending then
            return {}, "Some RXP guides could not be read. Use Rescan guides to try again."
        end
        return {}, "Waiting for the full RXP guide scan to finish..."
    end
    local quests, seen, hiddenDungeons = {}, {}, 0
    local zone = "Other quests"
    for logIndex = 1, LogSize() do
        local info = Entry(logIndex)
        if info and IsPublic(info.isHeader) and info.isHeader then
            if IsPublic(info.title) and type(info.title) == "string" and info.title ~= "" then
                zone = Helper.CleanText(info.title)
            else zone = "Other quests" end
        elseif info and IsPublic(info.isHeader) and not info.isHeader then
            local id = Helper.QuestID(info.questID)
            if id and not seen[id] and not Helper.IsQuestInAnyGuide(id) then
                seen[id] = true
                local dungeon = Helper.IsDungeonQuest(id)
                if excludeDungeons and dungeon then
                    hiddenDungeons = hiddenDungeons + 1
                else
                    local description, objectives = Description(logIndex, id)
                    quests[#quests + 1] = {
                        id = id,
                        title = IsPublic(info.title) and type(info.title) == "string" and info.title or ("Quest " .. id),
                        level = IsPublic(info.level) and type(info.level) == "number" and info.level or nil,
                        description = description,
                        objectives = objectives,
                        canAbandon = CanAbandon(id),
                        zone = zone,
                        isDungeon = dungeon,
                    }
                end
            end
        end
    end
    table.sort(quests, function(a, b)
        if a.zone ~= b.zone then return a.zone < b.zone end
        if a.title == b.title then return a.id < b.id end
        return a.title < b.title
    end)
    return quests, nil, hiddenDungeons
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
    local window = _G.RestedXPHelperOrphanFrame
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

local events = CreateFrame("Frame")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_DATA_LOAD_RESULT")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function()
    local window = _G.RestedXPHelperOrphanFrame
    if not window or not window:IsShown() or queued then return end
    queued = true
    C_Timer.After(0.1, function() queued = false; Helper.RefreshOrphanWindow() end)
end)
