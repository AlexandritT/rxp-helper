-- Run from the repository root with Lua 5.1+ or Fengari.
local passed = 0
local function check(value, message)
    assert(value, message)
    passed = passed + 1
end
local function loadAddonFile(path, namespace)
    assert(loadfile("RXPDJBridge/" .. path))("RXPDJBridge", namespace)
end

local Bridge = {}
loadAddonFile("Index.lua", Bridge)
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
check(Bridge.IndexGuide(index, first), "parsed guide indexed")
check(#Bridge.GetMatches(index, 167) == 1, "repeated objectives deduplicate guide")
check(table.concat(Bridge.GetMatches(index, 167)[1].steps, ",") == "1,2", "steps deduplicate and sort")
check(index[168] ~= nil and index[-168] == nil, "negative optional quest IDs normalize")
check(index[214] ~= nil and index[12345] == nil, "collection quest uses quest ID, not item ID")
check(index[100] and index[101] and index[102], "daily and multiple quest IDs indexed")
check(not index[999] and not index[888], "non-quest references and items ignored")
check(Bridge.QuestID("167") == 167 and not Bridge.QuestID(0)
    and not Bridge.QuestID("garbage") and not Bridge.QuestID(1.5), "invalid quest IDs rejected")
check(#Bridge.GetMatches(index, nil) == 0, "empty lookup safe")
local second = guide("second", "16-20 Westfall", { { tag = "accept", questId = 167 } })
second.displayname = "|cffff0000Exact guide title|r"
Bridge.IndexGuide(index, second)
check(#Bridge.GetMatches(index, 167) == 2, "all matching guides retained")
check(Bridge.GetMatches(index, 167)[2].guide.name == "Exact guide title", "display name used without color codes")
second.disabled = true
check(not Bridge.IndexGuide({}, second), "disabled guides excluded")
second.disabled, second.internal = nil, true
check(not Bridge.IndexGuide({}, second), "internal helpers excluded")
check(not Bridge.IndexGuide({}, { name = "Lazy" }), "unparsed guide safely skipped")

-- A small WoW API mock exercises event timing, post-hooks, pooled rows and
-- tooltips. Production code runs unchanged in this environment.
local queue, frames = {}, {}
local clock, combat = 0, false
local function newFrame(parent)
    local f = { parent = parent, shown = true, scripts = {}, level = 1, children = {} }
    if parent then parent.children[#parent.children + 1] = f end
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:SetFrameLevel(level) self.level = level end
    function f:GetFrameLevel() return self.level end
    function f:EnableMouse(value) self.mouse = value end
    function f:SetPropagateMouseClicks(value) self.propagates = value end
    function f:SetPoint(...) self.point = { ... } end
    function f:SetAllPoints() end
    function f:SetTexture(value) self.texture = value end
    function f:CreateTexture() return newFrame() end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:RegisterEvent() end
    function f:GetChildren() return (unpack or table.unpack)(self.children) end
    function f:IsShown() return self.shown end
    function f:Show() self.shown = true end
    function f:Hide()
        if not self.shown then return end
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    frames[#frames + 1] = f
    return f
end
CreateFrame = function(_, _, parent) return newFrame(parent) end
C_Timer = { After = function(delay, callback)
    queue[#queue + 1] = { at = clock + delay, callback = callback }
end }
InCombatLockdown = function() return combat end
IsLoggedIn = function() return true end
DEFAULT_CHAT_FRAME = { messages = {}, AddMessage = function(self, message)
    self.messages[#self.messages + 1] = message
end }
SlashCmdList = {}
GameTooltip = newFrame()
function GameTooltip:SetOwner(owner) self.owner = owner end
function GameTooltip:GetOwner() return self.owner end
function GameTooltip:ClearLines() self.lines = {} end
function GameTooltip:AddLine(line) self.lines[#self.lines + 1] = line end
local function containsLine(text)
    for _, line in ipairs(GameTooltip.lines) do if line == text then return true end end
    return false
end
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
local selected = { key = "selected", progress = 42 }
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
        return guide(source.key, source.name, {
            { tag = "accept", questId = 167 }, { tag = "turnin", questId = 168 },
        })
    end,
    AddGuide = function(g) RXP.guides[g.key] = g; return true end,
    RemoveGuide = function(key) RXP.guides[key] = nil end,
    ReloadGuide = function() end,
}
local originalRefreshes = 0
ForeverDungeonJournal_NS = {
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

loadAddonFile("Bridge.lua", Bridge)
local driver = frames[#frames]
driver.scripts.OnEvent(driver, "PLAYER_LOGIN")
flush()
check(fetches == 2, "lazy hardcore guide fetched in two passes")
check(processes == 1, "RXP expands route includes before indexing")
check(RXP.currentGuide == selected and selected.progress == 42, "indexing preserves selected guide and progress")
ForeverDungeonJournal_NS.MarkLostQuestRows({ row }, {})
check(originalRefreshes == 1, "journal's original refresh function retained")
check(row.rxpDJMarker and row.rxpDJMarker:IsShown(), "main quest gets marker")
check(row.chainRows[1].rxpDJMarker:IsShown(), "included prerequisite gets marker")
check(not row.chainRows[2].rxpDJMarker, "item steps do not get quest markers")
check(row.scripts.OnClick == oldClick and row.rxpDJMarker.propagates, "quest row click behavior preserved")
local marker = row.rxpDJMarker
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
check(not marker:IsShown() and not row.chainRows[1].rxpDJMarker:IsShown(), "RPG mystery rows reveal no guide hints")
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
SlashCmdList.RXPDJBRIDGE("quest 167")
check(DEFAULT_CHAT_FRAME.messages[#DEFAULT_CHAT_FRAME.messages]:find("0 matching guides", 1, true), "diagnostic lookup reports current index")

-- Parsing failure must leave other guides available and finish the scan.
RXP.FetchGuide = function() error("fixture parse failure") end
RXP.ProcessGuideTable = function(g) return g end
RXP.AddGuide({ key = "bad", name = "Broken", group = "Test" })
RXP.AddGuide(lazy)
flush()
SlashCmdList.RXPDJBRIDGE("")
check(DEFAULT_CHAT_FRAME.messages[#DEFAULT_CHAT_FRAME.messages - 1]:find("1 guides unavailable", 1, true), "parse failures reported without stopping other guides")
check(#DEFAULT_CHAT_FRAME.messages > 0, "diagnostics available")

print("PASS: " .. passed .. " checks")
