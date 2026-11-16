local _, Bridge = ...
_G.RXPDJBridge = Bridge

local LOGO = "Interface\\AddOns\\RXPGuides\\Textures\\rxp_logo-64"
local index, rows = {}, {}
local rxp, journal, registry, building, rebuildRequested
local generation, indexedGuides, failedGuides = 0, 0, 0
local snapshot = {}
local elapsed, registryElapsed = 0, 0
local driver = CreateFrame("Frame")
local RefreshRows, RequestRebuild, TryConnect

local function Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd166RXP DJ Bridge:|r " .. message)
    end
end

local function HideTooltip(marker)
    if GameTooltip and GameTooltip:GetOwner() == marker then GameTooltip:Hide() end
end

local function ShowTooltip(marker)
    if not GameTooltip then return end
    local matches = Bridge.GetMatches(index, marker.questID)
    if #matches == 0 then HideTooltip(marker); return end
    GameTooltip:SetOwner(marker, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("RestedXP Guides", 1, 0.82, 0.25)
    GameTooltip:AddLine("Quest ID: " .. marker.questID, 0.65, 0.65, 0.65)
    for _, match in ipairs(matches) do
        local guide = match.guide
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(guide.name, 1, 1, 1, true)
        if guide.group ~= "" then GameTooltip:AddLine(guide.group, 1, 0.82, 0.25, true) end
        if guide.subgroup ~= "" and guide.subgroup ~= guide.group then
            GameTooltip:AddLine(guide.subgroup, 0.8, 0.8, 0.8, true)
        end
        local steps = {}
        for _, number in ipairs(match.steps) do steps[#steps + 1] = tostring(number) end
        GameTooltip:AddLine("Steps: " .. table.concat(steps, ", "), 0.7, 0.85, 1, true)
    end
    if building then GameTooltip:AddLine("Scanning remaining guides...", 0.7, 0.7, 0.7) end
    GameTooltip:Show()
    marker.tooltipGeneration = generation
end

local function CreateMarker(row, isStep)
    -- A mouse-enabled Frame leaves quest selection clicks with the parent row.
    local marker = CreateFrame("Frame", nil, row)
    marker:SetSize(16, 16)
    marker:SetFrameLevel(row:GetFrameLevel() + 8)
    marker:EnableMouse(true)
    if marker.SetPropagateMouseClicks then marker:SetPropagateMouseClicks(true) end
    local texture = marker:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    texture:SetTexture(LOGO)
    if isStep then
        -- The chain panel's left gutter is free; don't move its title or tick.
        marker:SetPoint("RIGHT", row, "LEFT", -2, 0)
    else
        -- Main rows reserve a 42px gutter for the quest symbol. Keep clear
        -- of the title, chain control, faction icons and turn-in button.
        marker:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -30)
    end
    marker:SetScript("OnEnter", ShowTooltip)
    marker:SetScript("OnLeave", HideTooltip)
    marker:SetScript("OnHide", HideTooltip)
    marker:Hide()
    row.rxpDJMarker = marker
    return marker
end

local function UpdateRow(row, isStep, hidden)
    local id
    if isStep then
        if row.step and not row.step.itemStep then id = Bridge.QuestID(row.step.id) end
    else
        id = Bridge.QuestID(row.questID)
    end
    local marker = row.rxpDJMarker
    local show = not hidden and row:IsShown() and not row.fdjRPGHidden and id and index[id]
    if not show then
        if marker then marker.questID = nil; marker:Hide() end
        return
    end
    if not marker then marker = CreateMarker(row, isStep) end
    local changed = marker.questID ~= id or marker.tooltipGeneration ~= generation
    marker.questID = id
    marker:Show()
    if changed and GameTooltip and GameTooltip:GetOwner() == marker then ShowTooltip(marker) end
end

RefreshRows = function()
    for _, row in ipairs(rows) do
        UpdateRow(row, false)
        for _, stepRow in ipairs(row.chainRows or {}) do
            UpdateRow(stepRow, true, row.fdjRPGHidden or not row:IsShown())
        end
    end
end

local function CaptureRows(buttons)
    rows = buttons or {}
    RefreshRows()
end

local function RememberRegistry()
    registry = rxp.guides
    snapshot = {}
    for key, guide in pairs(registry) do snapshot[key] = guide end
end

local function RegistryChanged()
    if registry ~= rxp.guides then return true end
    for key, guide in pairs(rxp.guides) do
        if snapshot[key] ~= guide then return true end
    end
    for key in pairs(snapshot) do
        if rxp.guides[key] == nil then return true end
    end
    return false
end

local function BuildIndex()
    if building or not rxp or type(rxp.guides) ~= "table" then return end
    rebuildRequested = false
    building = true
    local keys, sourceRegistry = {}, rxp.guides
    for key, guide in pairs(sourceRegistry) do
        if type(guide) == "table" and not guide.internal and not guide.disabled then
            keys[#keys + 1] = key
        end
    end
    local pending, cursor, count, failed = {}, 0, 0, 0

    local function NextGuide()
        -- A guide import can replace the entire registry while we yield.
        if rxp.guides ~= sourceRegistry then
            building = false
            RequestRebuild()
            return
        end
        cursor = cursor + 1
        local key = keys[cursor]
        if key == nil then
            index = pending
            indexedGuides, failedGuides = count, failed
            generation = generation + 1
            building = false
            RememberRegistry()
            RefreshRows()
            if rebuildRequested then RequestRebuild() end
            return
        end
        local guide = sourceRegistry[key]
        if guide and not guide.steps and type(rxp.FetchGuide) == "function" then
            -- FetchGuide parses a lazy guide without selecting it or changing
            -- saved progress. Let RXP handle its own imported guide format.
            local ok, fetched = pcall(rxp.FetchGuide, rxp, guide)
            if ok and fetched and not fetched.steps then
                -- RXP's hardcore cache sometimes needs a decompression pass
                -- before it can parse the guide on the second call.
                ok, fetched = pcall(rxp.FetchGuide, rxp, fetched)
            end
            if ok and fetched then guide = fetched else guide = nil end
        end
        if guide and guide.steps and type(rxp.ProcessGuideTable) == "function" then
            -- RXP expands #include references, label ranges and route settings
            -- here. Index that result under the parent guide's exact name.
            -- This function does not select the guide or advance its progress.
            local ok, processed = pcall(rxp.ProcessGuideTable, guide)
            if ok then guide = processed else guide = nil end
        end
        if guide and Bridge.IndexGuide(pending, guide) then
            count = count + 1
        elseif sourceRegistry[key] then
            failed = failed + 1
        end
        -- Process one guide per callback. Don't parse during combat.
        C_Timer.After(0.01, function()
            if InCombatLockdown and InCombatLockdown() then
                building = false
                rebuildRequested = true
            else
                NextGuide()
            end
        end)
    end
    NextGuide()
end

local rebuildScheduled
RequestRebuild = function()
    rebuildRequested = true
    if building or rebuildScheduled then return end
    rebuildScheduled = true
    C_Timer.After(0.25, function()
        rebuildScheduled = false
        if InCombatLockdown and InCombatLockdown() then return end
        BuildIndex()
    end)
end

TryConnect = function()
    if rxp then return true end
    local candidate, dj = _G.RXP, _G.ForeverDungeonJournal_NS
    if type(candidate) ~= "table" or type(candidate.guides) ~= "table" or not dj
        or type(dj.MarkLostQuestRows) ~= "function" then return false end
    rxp, journal = candidate, dj
    -- This public helper is called at the end of DJ's local RefreshQuestList.
    -- Secure post-hooks preserve DJ's own functions and row click scripts.
    hooksecurefunc(journal, "MarkLostQuestRows", CaptureRows)
    for _, name in ipairs({ "AddGuide", "RemoveGuide", "LoadCachedGuides", "ReloadGuide" }) do
        if type(rxp[name]) == "function" then hooksecurefunc(rxp, name, RequestRebuild) end
    end
    -- Also catch a journal that was already opened before this addon loaded.
    local frame = _G.ForeverDungeonJournalFrame
    if frame and frame.questContent then
        for _, child in ipairs({ frame.questContent:GetChildren() }) do
            if child.questID and child.name then rows[#rows + 1] = child end
        end
    end
    RequestRebuild()
    return true
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("ADDON_LOADED")
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if not TryConnect() then Print("Could not connect to RestedXP and Dungeon Journal.") end
    elseif event == "ADDON_LOADED" then
        if IsLoggedIn and IsLoggedIn() then TryConnect() end
    elseif event == "PLAYER_REGEN_ENABLED" and rebuildRequested then
        RequestRebuild()
    end
end)

driver:SetScript("OnUpdate", function(_, delta)
    if not rxp then return end
    elapsed, registryElapsed = elapsed + delta, registryElapsed + delta
    if elapsed >= 0.2 then
        elapsed = 0
        local frame = _G.ForeverDungeonJournalFrame
        if frame and frame:IsShown() then RefreshRows() end
    end
    if registryElapsed >= 2 then
        registryElapsed = 0
        if not building and not rebuildScheduled and RegistryChanged() then RequestRebuild() end
    end
end)

SLASH_RXPDJBRIDGE1 = "/rxpdj"
SlashCmdList.RXPDJBRIDGE = function(command)
    command = (command or ""):match("^%s*(.-)%s*$")
    if command == "rescan" then
        if TryConnect() then RequestRebuild(); Print("Guide rescan queued.") end
    elseif command:match("^quest%s+%d+$") then
        local id = tonumber(command:match("(%d+)$"))
        local matches = Bridge.GetMatches(index, id)
        Print("Quest " .. id .. ": " .. #matches .. " matching guides.")
        for _, match in ipairs(matches) do Print(match.guide.group .. " / " .. match.guide.name) end
    else
        local quests = 0
        for _ in pairs(index) do quests = quests + 1 end
        Print(indexedGuides .. " guides, " .. quests .. " quests indexed. "
            .. (building and "Scanning... " or "") .. failedGuides .. " guides unavailable.")
        Print("/rxpdj rescan | /rxpdj quest <questID>")
    end
end
