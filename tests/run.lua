-- Run from the repository root with Lua 5.1+ or Fengari.
local passed = 0
local function check(value, message)
    assert(value, message)
    passed = passed + 1
end
local function loadAddonFile(path, namespace)
    assert(loadfile("RestedXPHelper/" .. path))("RestedXPHelper", namespace)
end

local Helper = {}
loadAddonFile("Index.lua", Helper)
local function guide(key, name, elements)
    return {
        key = key, name = name, group = "RestedXP Forever Guide (A)",
        subgroup = "Dungeon routes", steps = { { elements = elements or {} } },
    }
end
local index = {}
local first = guide("first", "17-18 Deadmines", {
    { tag = "accept", questId = 167 },
    { tag = "complete", questId = 167 },
    { tag = "turnin", questId = -168 },
    { tag = "collect", id = 12345, questId = 214 },
    { tag = "daily", ids = { 100, 101 } },
    { tag = "turninmultiple", ids = { 101, 102 } },
    { tag = "goto", questId = 999 },
    { tag = "collect", id = 888 },
})
first.steps[2] = { elements = { { tag = "turnin", questId = 167 } } }
check(Helper.IndexGuide(index, first), "parsed guide indexed")
check(#Helper.GetMatches(index, 167) == 1, "repeated objectives deduplicate guide")
check(table.concat(Helper.GetMatches(index, 167)[1].steps, ",") == "1,2", "steps deduplicate and sort")
check(index[168] ~= nil and index[-168] == nil, "negative optional quest IDs normalize")
check(index[214] ~= nil and index[12345] == nil, "collection quest uses quest ID, not item ID")
check(index[100] and index[101] and index[102], "daily and multiple quest IDs indexed")
check(not index[999] and not index[888], "non-quest references and items ignored")
check(Helper.QuestID("167") == 167 and not Helper.QuestID(0)
    and not Helper.QuestID("garbage") and not Helper.QuestID(1.5), "invalid quest IDs rejected")
check(#Helper.GetMatches(index, nil) == 0, "empty lookup safe")
local second = guide("second", "16-20 Westfall", { { tag = "accept", questId = 167 } })
second.displayname = "|cffff0000Exact guide title|r"
Helper.IndexGuide(index, second)
check(#Helper.GetMatches(index, 167) == 2, "all matching guides retained")
check(Helper.GetMatches(index, 167)[2].guide.name == "Exact guide title", "display name used without color codes")
second.disabled = true
check(not Helper.IndexGuide({}, second), "disabled guides excluded")
second.disabled, second.internal = nil, true
check(not Helper.IndexGuide({}, second), "internal helpers excluded")
check(not Helper.IndexGuide({}, { name = "Lazy" }), "unparsed guide safely skipped")
check(Helper.GroupKey({ group = "internal", groupdisplayname = "|cffff0000*Displayed grouping|r" })
    == "Displayed grouping", "grouping follows RXP display name without priority prefix")

-- A small WoW API mock exercises event timing, post-hooks, pooled rows and
-- tooltips. Production code runs unchanged in this environment.
local queue, frames = {}, {}
local clock, combat, altDown = 0, false, false
local function newFrame(parent)
    local f = { parent = parent, shown = true, scripts = {}, level = 1, children = {} }
    if parent then parent.children[#parent.children + 1] = f end
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:SetWidth(w) self.width = w end
    function f:SetHeight(h) self.height = h end
    function f:GetWidth() return self.width or 610 end
    function f:GetHeight() return self.height or 320 end
    function f:ClearAllPoints() end
    function f:SetText(text) self.text = text end
    function f:GetText() return self.text end
    function f:GetStringHeight()
        return 14 * math.max(1, math.ceil(#(self.text or "") / math.max(1, (self.width or 610) / 7)))
    end
    function f:CreateFontString() return newFrame() end
    function f:SetJustifyH() end
    function f:SetWordWrap() end
    function f:SetColorTexture() end
    function f:SetEnabled(enabled) self.enabled = enabled end
    function f:SetFrameStrata() end
    function f:SetClampedToScreen() end
    function f:SetMovable() end
    function f:RegisterForDrag() end
    function f:SetScrollChild(child) self.scrollChild = child end
    function f:SetVerticalScroll(offset) self.scrollOffset = offset end
    function f:GetVerticalScroll() return self.scrollOffset or 0 end
    function f:SetFrameLevel(level) self.level = level end
    function f:GetFrameLevel() return self.level end
    function f:EnableMouse(value) self.mouse = value end
    function f:SetPropagateMouseClicks(value) self.propagates = value end
    function f:SetPoint(...) self.point = { ... } end
    function f:SetAllPoints() end
    function f:SetTexture(value) self.texture = value end
    function f:CreateTexture() return newFrame() end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:HookScript(name, fn)
        local previous = self.scripts[name]
        self.scripts[name] = function(...)
            if previous then previous(...) end
            fn(...)
        end
    end
    function f:RegisterEvent() end
    function f:GetChildren() return (unpack or table.unpack)(self.children) end
    function f:IsShown() return self.shown end
    function f:IsForbidden() return self.forbidden end
    function f:ClearLines()
        self.lines = {}
        if self.scripts.OnTooltipCleared then self.scripts.OnTooltipCleared(self) end
    end
    function f:AddLine(line) self.lines[#self.lines + 1] = line end
    function f:SetHyperlink(link)
        self:ClearLines()
        self:AddLine("Original quest content: " .. link)
        self:Show()
    end
    function f:SetQuestPartyProgress(id)
        self:ClearLines()
        self:AddLine("Original quest objectives")
        self:Show()
        return true
    end
    f.SetQuestByID, f.SetQuestLogTitle = f.SetQuestPartyProgress, f.SetQuestPartyProgress
    function f:Show() self.shown = true end
    function f:Hide()
        if not self.shown then return end
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    frames[#frames + 1] = f
    return f
end
CreateFrame = function(_, name, parent, template)
    local frame = newFrame(parent)
    if name then _G[name] = frame end
    if template == "BasicFrameTemplateWithInset" then frame.TitleText = newFrame() end
    return frame
end
C_Timer = { After = function(delay, callback)
    queue[#queue + 1] = { at = clock + delay, callback = callback }
end }
InCombatLockdown = function() return combat end
IsAltKeyDown = function() return altDown end
IsLoggedIn = function() return true end
DEFAULT_CHAT_FRAME = { messages = {}, AddMessage = function(self, message)
    self.messages[#self.messages + 1] = message
end }
SlashCmdList = {}
GameTooltip = newFrame()
function GameTooltip:SetOwner(owner) self.owner = owner end
function GameTooltip:GetOwner() return self.owner end
ItemRefTooltip = newFrame()
local function containsLine(text, tooltip)
    for _, line in ipairs((tooltip or GameTooltip).lines) do if line == text then return true end end
    return false
end
local function countLine(text, tooltip)
    local count = 0
    for _, line in ipairs((tooltip or GameTooltip).lines) do if line == text then count = count + 1 end end
    return count
end
Enum = { TooltipDataType = { Quest = 1, Unit = 2, Item = 3 }, TooltipDataLineType = { QuestTitle = 17 } }
local dataCallback
TooltipDataProcessor = { AllTypes = 0, AddTooltipPostCall = function(_, callback) dataCallback = callback end }
C_QuestLog = { GetInfo = function(logIndex)
    return { questID = 167, isHeader = logIndex == 4 }
end }
local questieMap = { ShowOnTooltip = function(icon, tooltip)
    tooltip.questOrder = icon.quests
    tooltip.npcAndObjectOrder = icon.givers
    tooltip._Rebuild = function(frame)
        frame:ClearLines()
        frame:AddLine("Questie original content")
    end
    tooltip:_Rebuild()
    tooltip:Show()
end }
local questieTips = { RegisterNativeQuestTooltip = function() end }
QuestieLoader = { ImportModule = function(_, name)
    return name == "MapIconTooltip" and questieMap or questieTips
end }
hooksecurefunc = function(object, name, callback)
    local original = object[name]
    object[name] = function(...)
        local result = original(...)
        callback(...)
        return result
    end
end
local function flush()
    local calls = 0
    while #queue > 0 do
        table.sort(queue, function(a, b) return a.at < b.at end)
        local nextCall = table.remove(queue, 1)
        clock = nextCall.at
        nextCall.callback()
        calls = calls + 1
        assert(calls < 1000, "timer loop")
    end
end

local lazy = guide("lazy", "17-18 Deadmines", { { tag = "accept", questId = 167 } })
local selected = { key = "selected", group = lazy.group, progress = 42 }
local fetches, processes = 0, 0
RXP = {
    guides = { lazy = { key = "lazy", name = lazy.name, group = lazy.group } },
    currentGuide = selected,
    FetchGuide = function(self, metadata)
        fetches = fetches + 1
        if fetches == 1 then return metadata end -- hardcore decompression pass
        self.guides.lazy = lazy
        return lazy
    end,
    ProcessGuideTable = function(source)
        processes = processes + 1
        -- Simulate RXP's #include expansion. This quest exists only in the
        -- expanded route, so indexing raw elements would miss it.
        local processed = guide(source.key, source.name, source.key == "lazy" and {
            { tag = "accept", questId = 167 }, { tag = "turnin", questId = 168 },
        } or source.steps[1].elements)
        processed.group, processed.groupdisplayname = source.group, source.groupdisplayname
        return processed
    end,
    AddGuide = function(g) RXP.guides[g.key] = g; return true end,
    RemoveGuide = function(key) RXP.guides[key] = nil end,
    ReloadGuide = function() end,
    LoadGuide = function(self, current) self.currentGuide = current end,
}
local originalRefreshes = 0
local djNamespace = {
    MarkLostQuestRows = function() originalRefreshes = originalRefreshes + 1 end,
}
ForeverDungeonJournalFrame = newFrame()
ForeverDungeonJournalFrame.questContent = newFrame(ForeverDungeonJournalFrame)
local row = newFrame(ForeverDungeonJournalFrame.questContent)
row.questID, row.name = 167, {}
row.chainRows = { newFrame(row), newFrame(row) }
row.chainRows[1].step = { id = 168 }
row.chainRows[2].step = { id = 167, itemStep = true }
local oldClick = function() end
row:SetScript("OnClick", oldClick)

loadAddonFile("Core.lua", Helper)
local driver = frames[#frames]
loadAddonFile("QuestTooltips.lua", Helper)
driver.scripts.OnEvent(driver, "PLAYER_LOGIN")
GameTooltip:SetHyperlink("quest:167:15")
check(not containsLine("RestedXP Guides"), "tooltip before first scan preserves base content")
flush()
check(fetches == 2, "lazy hardcore guide fetched in two passes")
check(processes == 1, "RXP expands route includes before indexing")
check(RXP.currentGuide == selected and selected.progress == 42, "indexing preserves selected guide and progress")
check(#Helper.GetQuestMatches(167) == 1, "index works without Dungeon Journal installed")
check(containsLine("17-18 Deadmines"), "open tooltip gains guide information when scan completes")
ForeverDungeonJournal_NS = djNamespace
driver.scripts.OnEvent(driver, "ADDON_LOADED")
ForeverDungeonJournal_NS.MarkLostQuestRows({ row }, {})
check(originalRefreshes == 1, "journal's original refresh function retained")
check(row.rxpHelperMarker and row.rxpHelperMarker:IsShown(), "main quest gets marker")
check(row.chainRows[1].rxpHelperMarker:IsShown(), "included prerequisite gets marker")
check(not row.chainRows[2].rxpHelperMarker, "item steps do not get quest markers")
check(row.scripts.OnClick == oldClick and row.rxpHelperMarker.propagates, "quest row click behavior preserved")
local marker = row.rxpHelperMarker
marker.scripts.OnEnter(marker)
check(containsLine("17-18 Deadmines") and containsLine("RestedXP Forever Guide (A)"), "hover shows exact guide and group")
check(containsLine("Steps: 1"), "hover shows guide step")
marker.scripts.OnLeave(marker)
check(not GameTooltip:IsShown(), "leaving marker hides owned tooltip")

row.questID = 9999
ForeverDungeonJournal_NS.MarkLostQuestRows({ row }, {})
check(not marker:IsShown(), "pooled row hides stale marker for unrelated quest")
row.questID, row.fdjRPGHidden = 167, true
ForeverDungeonJournal_NS.MarkLostQuestRows({ row }, {})
check(not marker:IsShown() and not row.chainRows[1].rxpHelperMarker:IsShown(), "RPG mystery rows reveal no guide hints")
row.fdjRPGHidden = nil
ForeverDungeonJournal_NS.MarkLostQuestRows({ row }, {})
marker.scripts.OnEnter(marker)
row.questID = 168
ForeverDungeonJournal_NS.MarkLostQuestRows({ row }, {})
check(containsLine("Quest ID: 168"), "hover tooltip refreshes when row is reused")
local someoneElse = newFrame()
GameTooltip:SetOwner(someoneElse)
marker.scripts.OnLeave(marker)
check(GameTooltip:GetOwner() == someoneElse and GameTooltip:IsShown(), "leaving does not hide another addon's tooltip")

GameTooltip:SetHyperlink("quest:167:15")
check(containsLine("Original quest content: quest:167:15") and containsLine("17-18 Deadmines"), "quest link preserves content and appends guide info")
check(containsLine("RestedXP Forever Guide (A)") and containsLine("Steps: 1"), "quest tooltip includes group and steps")
dataCallback(GameTooltip, { type = Enum.TooltipDataType.Quest, id = 167 })
check(countLine("RestedXP Guides") == 1, "native setter and data callback do not duplicate guide section")
GameTooltip:SetHyperlink("item:167")
check(not containsLine("RestedXP Guides"), "reused item tooltip has no stale guide section")
ItemRefTooltip:SetHyperlink("|cffffff00|Hquest:167:15|h[Oh Brother...]|h|r")
check(containsLine("17-18 Deadmines", ItemRefTooltip), "clicked chat quest links supported")
GameTooltip:SetQuestLogTitle(3)
check(containsLine("Quest ID: 167"), "quest log index resolves to quest ID")
GameTooltip:SetQuestLogTitle(4)
check(not containsLine("RestedXP Guides"), "quest log headers excluded")
local modern = newFrame()
modern:ClearLines()
modern:AddLine("Native title")
dataCallback(modern, { type = Enum.TooltipDataType.Quest, id = 168 })
check(containsLine("17-18 Deadmines", modern), "modern quest data pipeline supported")
modern:ClearLines()
dataCallback(modern, { type = Enum.TooltipDataType.Unit, lines = { { type = 17, id = 168 } } })
check(not containsLine("RestedXP Guides", modern), "quest objective mob tooltips have no guide info")
altDown = true
dataCallback(modern, { type = Enum.TooltipDataType.Unit, id = 167, lines = { { type = 17, id = 168 } } })
check(not containsLine("RestedXP Guides", modern), "Alt never adds guide info to objective mobs")
Helper.RefreshQuestTooltips(true)
check(not containsLine("RestedXP Guides", modern), "tooltip refresh never restores guide info on mobs")
altDown = false
modern:ClearLines()
dataCallback(modern, { type = Enum.TooltipDataType.Quest, lines = { { type = 17, id = 168 } } })
check(containsLine("Quest ID: 168", modern), "QuestTitle rows still supported in actual quest tooltips")
modern:Hide()
modern:ClearLines()
modern:AddLine("Native title")
dataCallback(modern, { type = Enum.TooltipDataType.Item, id = 167 })
check(not containsLine("RestedXP Guides", modern), "item IDs never treated as quest IDs")
modern.forbidden = true
dataCallback(modern, { type = 1, id = 167 })
check(not containsLine("RestedXP Guides", modern), "forbidden tooltips untouched")
modern.forbidden = nil
local secret = {}
issecretvalue = function(value) return value == secret end
dataCallback(modern, { type = 1, id = secret })
dataCallback(modern, secret)
check(not containsLine("RestedXP Guides", modern), "secret quest IDs and payloads ignored")
issecretvalue = nil
questieMap.ShowOnTooltip({ quests = { [167] = true }, givers = {} }, GameTooltip)
check(containsLine("Questie original content") and containsLine("17-18 Deadmines"), "Questie objective map tooltip augmented")
GameTooltip:_Rebuild()
check(countLine("RestedXP Guides") == 1, "Questie modifier redraw retains exactly one guide section")
questieMap.ShowOnTooltip({ quests = {}, givers = { NPC = { quest = { questId = 168 } } } }, GameTooltip)
check(containsLine("Quest ID: 168"), "Questie available quest givers supported")
questieMap.ShowOnTooltip({ quests = {}, givers = {} }, GameTooltip)
check(not containsLine("RestedXP Guides"), "Questie unrelated pin has no stale guide info")
local tracker = newFrame()
questieTips.RegisterNativeQuestTooltip(tracker)
tracker:SetQuestPartyProgress(167)
check(containsLine("17-18 Deadmines", tracker), "late-created Questie tracker tooltip supported")

local foreign = guide("foreign", "Survival route", {
    { tag = "accept", questId = 167 }, { tag = "accept", questId = 900 },
})
foreign.group = "RestedXP Survival Guide (A)"
local chapter = guide("chapter", "Next chapter in current grouping", { { tag = "turnin", questId = 167 } })
RXP.AddGuide(foreign)
RXP.AddGuide(chapter)
flush()
check(#Helper.GetQuestMatches(167) == 2, "default includes every matching chapter within current grouping")
check(#Helper.GetQuestMatches(900) == 0, "default excludes quests from other groupings")
GameTooltip:SetHyperlink("quest:167:15")
check(containsLine("17-18 Deadmines") and containsLine(chapter.name) and not containsLine(foreign.name),
    "default quest tooltip hides other groupings")
local filteredHeight = #GameTooltip.lines
modern.currentData = { type = Enum.TooltipDataType.Quest, id = 167 }
function modern:RebuildFromTooltipInfo()
    self:ClearLines()
    self:AddLine("Native title")
    dataCallback(self, self.currentData)
    self:Show()
end
modern:RebuildFromTooltipInfo()
local foreignRow = newFrame(ForeverDungeonJournalFrame.questContent)
foreignRow.questID, foreignRow.name = 900, {}
foreignRow.chainRows = { newFrame(foreignRow) }
foreignRow.chainRows[1].step = { id = 900 }
ForeverDungeonJournal_NS.MarkLostQuestRows({ row, foreignRow }, {})
check(not foreignRow.rxpHelperMarker and not foreignRow.chainRows[1].rxpHelperMarker,
    "DJ quest and prerequisite markers hidden outside current grouping")
altDown = true
driver.scripts.OnEvent(driver, "MODIFIER_STATE_CHANGED", "LALT")
check(containsLine(foreign.name) and #GameTooltip.lines > filteredHeight,
    "holding Alt expands an already-open quest tooltip to all groupings")
check(countLine("RestedXP Guides") == 1 and containsLine("Original quest content: quest:167:15"),
    "Alt refresh preserves native content and avoids duplicate guide blocks")
check(containsLine(foreign.name, modern) and containsLine("Native title", modern),
    "modern data tooltip rebuilds with Alt without copying native lines")
check(containsLine(foreign.name, ItemRefTooltip), "Alt expands an already-open chat quest tooltip")
check(foreignRow.rxpHelperMarker:IsShown() and foreignRow.chainRows[1].rxpHelperMarker:IsShown(),
    "Alt reveals DJ quest and prerequisite markers from other groupings")
altDown = false
driver.scripts.OnEvent(driver, "MODIFIER_STATE_CHANGED", "LALT")
check(not containsLine(foreign.name) and #GameTooltip.lines == filteredHeight,
    "releasing Alt shrinks the open tooltip back to its original size")
check(not containsLine(foreign.name, modern) and not containsLine(foreign.name, ItemRefTooltip),
    "modern and chat quest tooltips collapse on Alt release")
check(not foreignRow.rxpHelperMarker:IsShown() and not foreignRow.chainRows[1].rxpHelperMarker:IsShown(),
    "releasing Alt hides out-of-group DJ markers")
questieMap.ShowOnTooltip({ quests = { [167] = true }, givers = {} }, GameTooltip)
altDown = true
driver.scripts.OnEvent(driver, "MODIFIER_STATE_CHANGED", "RALT")
check(containsLine(foreign.name) and containsLine("Questie original content"),
    "right Alt expands an open Questie map tooltip")
altDown = false
driver.scripts.OnEvent(driver, "MODIFIER_STATE_CHANGED", "RALT")
check(not containsLine(foreign.name) and countLine("RestedXP Guides") == 1,
    "Questie tooltip collapses without stale or duplicate guide sections")
check(not containsLine(foreign.name, tracker), "open tracker tooltip returns to current grouping")
GameTooltip:SetHyperlink("quest:167:15")
local beforeSwitch = processes
RXP:LoadGuide({ key = "foreign-selected", group = foreign.group })
check(containsLine(foreign.name) and not containsLine(chapter.name),
    "switching current grouping refreshes the open tooltip immediately")
check(foreignRow.rxpHelperMarker:IsShown() and not row.rxpHelperMarker:IsShown(),
    "switching groupings refreshes DJ marker visibility")
check(processes == beforeSwitch, "changing grouping reuses index instead of reparsing guides")
RXP:LoadGuide(nil)
check(#Helper.GetQuestMatches(167) == 0 and not containsLine("RestedXP Guides"),
    "no selected guide means no default guide sections")
altDown = true
driver.scripts.OnEvent(driver, "MODIFIER_STATE_CHANGED", "LALT")
check(#Helper.GetQuestMatches(167) == 3 and containsLine(foreign.name),
    "Alt shows all guides even with no current grouping")
altDown = false
RXP:LoadGuide(selected)
driver.scripts.OnEvent(driver, "MODIFIER_STATE_CHANGED", "LALT")
RXP.RemoveGuide("foreign")
RXP.RemoveGuide("chapter")
flush()

combat = true
RXP.RemoveGuide("lazy")
flush()
check(marker:IsShown(), "combat defers rescan")
combat = false
driver.scripts.OnEvent(driver, "PLAYER_REGEN_ENABLED")
flush()
check(not marker:IsShown(), "deleted guide removes markers after combat")
lazy.steps = { { elements = { { tag = "accept", questId = 167 } } } }
RXP.AddGuide(lazy)
flush()
check(marker:IsShown(), "newly imported guide refreshes markers")

-- Replacing the registry without AddGuide occurs when RXP restores imports.
RXP.guides = {}
driver.scripts.OnUpdate(driver, 2.1)
flush()
check(not marker:IsShown(), "registry replacement invalidates old matches")
SlashCmdList.RESTEDXPHELPER("quest 167")
check(DEFAULT_CHAT_FRAME.messages[#DEFAULT_CHAT_FRAME.messages]:find("0 matching guides", 1, true), "diagnostic lookup reports current index")

-- Parsing failure must leave other guides available and finish the scan.
RXP.FetchGuide = function() error("fixture parse failure") end
RXP.ProcessGuideTable = function(g) return g end
RXP.AddGuide({ key = "bad", name = "Broken", group = "Test" })
RXP.AddGuide(lazy)
flush()
SlashCmdList.RESTEDXPHELPER("")
check(DEFAULT_CHAT_FRAME.messages[#DEFAULT_CHAT_FRAME.messages - 1]:find("1 guides unavailable", 1, true), "parse failures reported without stopping other guides")
check(#DEFAULT_CHAT_FRAME.messages > 0, "diagnostics available")

StaticPopupDialogs, UISpecialFrames = {}, {}
local popup, abandoned, selectedQuest, abandonTarget = nil, {}, 167, nil
StaticPopup_Show = function(key, title, _, data) popup = { key = key, title = title, data = data } end
loadAddonFile("OrphanQuests.lua", Helper)
local orphanEvents = frames[#frames]
local orphanList, orphanReason = Helper.GetOrphanQuests()
check(#orphanList == 0 and orphanReason:find("could not be read", 1, true), "failed guide scan never produces false orphan results")
RXP.RemoveGuide("bad")
local otherGroup = guide("orphan-test-other", "Another grouping", { { tag = "accept", questId = 777 } })
otherGroup.group = "RestedXP Survival Guide (A)"
RXP.AddGuide(otherGroup)
flush()
local log = {
    { title = "Collapsed zone", isHeader = true, isCollapsed = true },
    { questID = 167, title = "Guide quest", level = 20 },
    { questID = 777, title = "Other grouping quest", level = 20 },
    { questID = 901, title = "Unlisted alpha", level = 21 },
    { questID = 902, title = "Unlisted beta", level = 22 },
    { questID = 901, title = "Unlisted alpha", level = 21 },
    { questID = 903, level = 23 },
}
C_QuestLog.GetNumQuestLogEntries = function() return #log end
C_QuestLog.GetInfo = function(i) return log[i] end
C_QuestLog.GetSelectedQuest = function() return selectedQuest end
C_QuestLog.SetSelectedQuest = function(id) selectedQuest = id end
C_QuestLog.CanAbandonQuest = function(id) return id ~= 902 end
C_QuestLog.SetAbandonQuest = function() abandonTarget = selectedQuest end
C_QuestLog.GetAbandonQuest = function() return abandonTarget end
C_QuestLog.AbandonQuest = function()
    abandoned[#abandoned + 1] = abandonTarget
    for i = #log, 1, -1 do if log[i].questID == abandonTarget then table.remove(log, i) end end
end
GetQuestLogQuestText = function(i)
    if log[i].questID == 901 then return string.rep("Full native quest description. ", 20), "Collect 8 samples." end
    return "Description for " .. tostring(log[i].questID)
end
orphanList, orphanReason = Helper.GetOrphanQuests()
check(not orphanReason and #orphanList == 3, "orphan list excludes headers, duplicates and all guide groupings")
check(orphanList[1].title == "Quest 903", "unloaded title has stable quest ID fallback")
check(orphanList[2].id == 901 and orphanList[2].description:find("Full native quest description", 1, true)
    and orphanList[2].objectives == "Collect 8 samples.", "orphan list includes native description and objectives")
check(not orphanList[3].canAbandon and selectedQuest == 167, "non-abandonable quests remain listed and description reads preserve selection")
altDown = true
check(#Helper.GetOrphanQuests() == 3, "orphan detection ignores Alt filtering")
altDown = false
SlashCmdList.RESTEDXPHELPER("orphan")
local orphanWindow = _G.RestedXPHelperOrphanFrame
check(SLASH_RESTEDXPHELPER3 == "/rxh" and orphanWindow:IsShown(), "/rxh orphan opens the quest list")
check(#orphanWindow.rows == 3 and orphanWindow.rows[2].description:GetText():find("Collect 8 samples.", 1, true), "window renders quest descriptions and objectives")
check(not orphanWindow.rows[3].abandon.enabled, "unavailable abandon action is disabled")
check(UISpecialFrames[#UISpecialFrames] == "RestedXPHelperOrphanFrame", "Escape can close orphan window")
orphanWindow.rows[2].abandon.scripts.OnClick()
check(popup and popup.data.questID == 901 and #abandoned == 0, "Abandon button asks for confirmation without removing quest")
local confirmedData = popup.data
local nowMatched = guide("now-matched", "New guide", { { tag = "accept", questId = 901 } })
RXP.AddGuide(nowMatched)
flush()
StaticPopupDialogs[popup.key].OnAccept(nil, confirmedData)
check(#abandoned == 0, "confirmation rechecks quest has not gained a guide")
RXP.RemoveGuide("now-matched")
flush()
Helper.ConfirmAbandonOrphan(901)
table.insert(log, 2, { questID = 904, title = "Newly accepted quest" })
StaticPopupDialogs[popup.key].OnAccept(nil, popup.data)
check(abandoned[1] == 901 and #abandoned == 1 and selectedQuest == 167, "confirmation resolves moved quest by ID and restores previous selection")
local found901 = false
for _, quest in ipairs(Helper.GetOrphanQuests()) do if quest.id == 901 then found901 = true end end
check(not found901, "abandoned quest disappears from refreshed list")
local ok = Helper.AbandonOrphanQuest(167)
check(not ok and #abandoned == 1, "guide quests cannot be abandoned through orphan action")
ok = Helper.AbandonOrphanQuest(901)
check(not ok and #abandoned == 1, "stale quest action cannot abandon another quest")
ok = Helper.AbandonOrphanQuest(902)
check(not ok and #abandoned == 1, "client refusal prevents abandoning protected quest")
combat = true
ok = Helper.AbandonOrphanQuest(904)
Helper.RefreshOrphanWindow()
check(not ok and #abandoned == 1, "combat disables quest abandonment")
combat = false
C_QuestLog.GetAbandonQuest = function() return 999 end
ok = Helper.AbandonOrphanQuest(904)
check(not ok and #abandoned == 1 and selectedQuest == 167, "wrong native abandonment target is rejected and selection restored")
C_QuestLog.GetAbandonQuest = function() return abandonTarget end
Helper.RequestGuideRescan()
orphanList, orphanReason = Helper.GetOrphanQuests()
ok = Helper.AbandonOrphanQuest(904)
check(#orphanList == 0 and orphanReason and not ok and #abandoned == 1, "pending scan blocks orphan classification and abandonment")
flush()
table.insert(log, { questID = 905, title = "Accepted after opening" })
orphanEvents.scripts.OnEvent(orphanEvents, "QUEST_LOG_UPDATE")
flush()
check(orphanWindow.status:GetText():find("4 quests", 1, true), "open orphan list refreshes when quest log changes")
RXP.RemoveGuide("orphan-test-other")
flush()

print("PASS: " .. passed .. " checks")
