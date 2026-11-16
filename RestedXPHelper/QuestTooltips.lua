local _, Helper = ...
local states = setmetatable({}, { __mode = "k" })
local hookedModules = setmetatable({}, { __mode = "k" })

local function IsPublic(value)
    return not (issecretvalue and issecretvalue(value))
end

local function IsUsable(tooltip)
    return tooltip and not (tooltip.IsForbidden and tooltip:IsForbidden())
end

local function Reset(tooltip)
    local state = states[tooltip]
    if state then state.added, state.quests = {}, {} end
end

local function Append(tooltip, value, show)
    if not IsUsable(tooltip) then return end
    local id = Helper.QuestID(value)
    if not id then return end
    Helper.HookQuestTooltip(tooltip)
    local state = states[tooltip]
    state.quests[id] = true
    if state.added[id] then return end
    if #Helper.GetQuestMatches(id) == 0 then return end
    tooltip:AddLine(" ")
    if Helper.AddGuideLines(tooltip, id) then
        state.added[id] = true
        -- Data processor callbacks run before native layout. Legacy setters
        -- and Questie finish layout first, so Show recalculates their height.
        if show and tooltip:IsShown() then tooltip:Show() end
    end
end

local function FromHyperlink(tooltip, link)
    if not IsPublic(link) or type(link) ~= "string" then return end
    local id = link:match("^quest:(%d+)") or link:match("|Hquest:(%d+)")
    if id then Append(tooltip, id, true) end
end

local function FromLogIndex(tooltip, logIndex)
    if not IsPublic(logIndex) or type(logIndex) ~= "number" then return end
    local id
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(logIndex)
        if IsPublic(info) and info and IsPublic(info.isHeader) and not info.isHeader then
            id = info.questID
        end
    elseif GetQuestLogTitle then
        local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(logIndex)
        if IsPublic(isHeader) and not isHeader then id = questID end
    end
    Append(tooltip, id, true)
end

function Helper.HookQuestTooltip(tooltip)
    if not IsUsable(tooltip) or states[tooltip] then return end
    states[tooltip] = { added = {}, quests = {} }
    if tooltip.HookScript then
        tooltip:HookScript("OnTooltipCleared", Reset)
        tooltip:HookScript("OnHide", Reset)
    end
    -- The native data pipeline and legacy methods can both run for the same
    -- tooltip. Track appended quest IDs until that tooltip's content clears.
    for name, callback in pairs({
        SetHyperlink = FromHyperlink,
        SetQuestLogTitle = FromLogIndex,
        SetQuestByID = function(frame, id) Append(frame, id, true) end,
        SetQuestPartyProgress = function(frame, id) Append(frame, id, true) end,
    }) do
        if type(tooltip[name]) == "function" then hooksecurefunc(tooltip, name, callback) end
    end
end

function Helper.RefreshQuestTooltips()
    -- A tooltip opened during the first scan gains its guide block when ready.
    for tooltip, state in pairs(states) do
        if IsUsable(tooltip) and tooltip:IsShown() then
            for id in pairs(state.quests) do Append(tooltip, id, true) end
        end
    end
end

local function FromTooltipData(tooltip, data)
    if not IsUsable(tooltip) or not IsPublic(data) or type(data) ~= "table" then return end
    local types = Enum and Enum.TooltipDataType or {}
    if IsPublic(data.type) and data.type ~= nil
        and (data.type == types.Quest or data.type == types.QuestPartyProgress) then
        Append(tooltip, data.id, false)
    end
    -- Some native quest tooltips expose the ID on QuestTitle rows instead.
    local questTitle = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle
    if questTitle and IsPublic(data.lines) and type(data.lines) == "table" then
        for _, line in ipairs(data.lines) do
            if IsPublic(line) and type(line) == "table" and IsPublic(line.type)
                and line.type == questTitle then Append(tooltip, line.id, false) end
        end
    end
end

local function FromQuestieMap(tooltip)
    if not IsUsable(tooltip) then return end
    Helper.HookQuestTooltip(tooltip)
    -- These tables contain the quests actually rendered in a clustered pin's
    -- tooltip. An icon's data.Id may be an NPC or object ID, so don't use it.
    for id in pairs(tooltip.questOrder or {}) do Append(tooltip, id, true) end
    for _, quests in pairs(tooltip.npcAndObjectOrder or {}) do
        for _, quest in pairs(quests) do Append(tooltip, quest.questId, true) end
    end
end

function Helper.ConnectQuestieTooltips()
    local loader = _G.QuestieLoader
    if not loader or type(loader.ImportModule) ~= "function" then return end
    local map = loader:ImportModule("MapIconTooltip")
    if type(map.ShowOnTooltip) == "function" and not hookedModules[map] then
        hookedModules[map] = true
        hooksecurefunc(map, "ShowOnTooltip", function(_, tooltip)
            FromQuestieMap(tooltip)
            -- Questie recreates _Rebuild when the pin changes; its modifier
            -- key redraws need the guide block appended again after rendering.
            local state = states[tooltip]
            if state and type(tooltip._Rebuild) == "function" and state.rebuild ~= tooltip._Rebuild then
                hooksecurefunc(tooltip, "_Rebuild", FromQuestieMap)
                state.rebuild = tooltip._Rebuild
            end
        end)
    end
    local tips = loader:ImportModule("QuestieTooltips")
    if type(tips.RegisterNativeQuestTooltip) == "function" and not hookedModules[tips] then
        hookedModules[tips] = true
        hooksecurefunc(tips, "RegisterNativeQuestTooltip", Helper.HookQuestTooltip)
    end
    Helper.HookQuestTooltip(_G.QuestieTrackerQuestTooltip)
end

Helper.HookQuestTooltip(_G.GameTooltip)
Helper.HookQuestTooltip(_G.ItemRefTooltip)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
    and TooltipDataProcessor.AllTypes ~= nil then
    TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, FromTooltipData)
end
Helper.ConnectQuestieTooltips()

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function() Helper.ConnectQuestieTooltips() end)
