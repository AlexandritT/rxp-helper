local _, Helper = ...
local window
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Flat suite-style surfaces, a grouped navigator and a readable quest inspector.
-- The host UI supplies the accent/font; no Blizzard window or button chrome.
function Helper.GetOrphanTheme()
    local t = {
        background = { r = 0.055, g = 0.061, b = 0.068 },
        panel = { r = 0.043, g = 0.049, b = 0.055 },
        accent = { r = 0.25, g = 0.76, b = 0.73 },
        text = { r = 0.91, g = 0.93, b = 0.94 },
        muted = { r = 0.62, g = 0.66, b = 0.69 },
        source = "Standalone",
    }
    local eui = _G.EllesmereUI
    local elv = _G.ElvUI and _G.ElvUI[1]
    if eui and type(eui.GetAccentColor) == "function" then
        local r, g, b = eui.GetAccentColor()
        t.accent = { r = r, g = g, b = b }
        t.background = eui.DARK_BG or t.background
        t.panel = { r = t.background.r * 0.76, g = t.background.g * 0.76, b = t.background.b * 0.76 }
        if eui.GetFontPath then
            local ok, font = pcall(eui.GetFontPath)
            if ok then t.font = font end
        end
        t.source = "EllesmereUI"
    elseif elv then
        t.accent = elv.db and elv.db.general and elv.db.general.valuecolor or t.accent
        local bg = elv.media and elv.media.backdropcolor
        if bg then t.background = { r = bg[1] or bg.r, g = bg[2] or bg.g, b = bg[3] or bg.b } end
        t.font = elv.media and elv.media.normFont
        t.source = "ElvUI"
    end
    return t
end

local function Surface(frame, color, border)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = border and WHITE or nil, edgeSize = border and 1 or nil })
    frame:SetBackdropColor(color.r, color.g, color.b, 1)
    if border then frame:SetBackdropBorderColor(1, 1, 1, 0.12) end
end

local function Label(parent, size, color, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local font = window.theme.font or fs:GetFont()
    fs:SetFont(font, size, "")
    fs:SetTextColor(color.r, color.g, color.b, 1)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    if width then fs:SetWidth(width) end
    return fs
end

local function Button(parent, text, width, action, danger)
    local t = window.theme
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, 32)
    Surface(button, t.panel, true)
    button.label = Label(button, 12, t.text)
    button.label:SetPoint("CENTER")
    button.label:SetText(text)
    button:SetScript("OnClick", action)
    button:SetScript("OnEnter", function(self)
        if not self:IsEnabled() then return end
        local c = danger and { r = 0.95, g = 0.45, b = 0.43 } or t.accent
        self:SetBackdropColor(c.r * 0.14, c.g * 0.14, c.b * 0.14, 1)
        self:SetBackdropBorderColor(c.r, c.g, c.b, 0.55)
        self.label:SetTextColor(c.r, c.g, c.b)
    end)
    button:SetScript("OnLeave", function(self)
        Surface(self, t.panel, true)
        self.label:SetTextColor(t.text.r, t.text.g, t.text.b)
    end)
    button:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    button:SetScript("OnDisable", function(self) self:SetAlpha(0.35) end)
    return button
end

local function Scroll(parent, width)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width - 14, 1)
    scroll:SetScrollChild(content)
    scroll.content = content
    scroll.range = 0
    local bar = CreateFrame("Slider", nil, scroll)
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -1, -2)
    bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", -1, 2)
    bar:SetWidth(4)
    bar:SetOrientation("VERTICAL")
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    bar:SetThumbTexture(WHITE)
    bar:GetThumbTexture():SetSize(4, 34)
    local c = window.theme.accent
    bar:GetThumbTexture():SetVertexColor(c.r, c.g, c.b, 0.55)
    bar:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)
    bar:SetValue(0)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        bar:SetValue(math.max(0, math.min(self.range, self:GetVerticalScroll() - delta * 38)))
    end)
    function scroll:SetContentHeight(height)
        content:SetHeight(math.max(1, height))
        self.range = math.max(0, height - self:GetHeight())
        bar:SetMinMaxValues(0, self.range)
        bar:SetValue(math.min(self:GetVerticalScroll(), self.range))
        bar:SetShown(self.range > 0)
    end
    function scroll:ResetScroll() bar:SetValue(0) end
    return scroll
end

local function PaintSelection()
    for _, row in ipairs(window.rows) do
        local selected = row.questID == window.selectedID
        row.selected:SetShown(selected)
        row.indicator:SetShown(selected)
    end
end

local function ShowDetail(quest, reason, hidden)
    local detail = window.detail
    if not quest then
        detail.zone:SetText("")
        detail.title:SetText(reason and "Guide data unavailable" or (hidden > 0 and "No quests match the filter" or "No orphan quests"))
        detail.meta:SetText("")
        detail.description:SetText(reason or (hidden > 0 and "All remaining orphan quests are dungeon quests. Turn off the filter to see them."
            or "Every quest in your log belongs to an installed RXP guide."))
        detail.objectiveTitle:Hide()
        detail.objectives:Hide()
        detail.abandon:Hide()
        detail.hint:SetText("")
    else
        detail.zone:SetText(quest.zone)
        detail.title:SetText(quest.title)
        local parts = {}
        if quest.level and quest.level > 0 then parts[#parts + 1] = "Level " .. quest.level end
        if quest.isDungeon then parts[#parts + 1] = "Dungeon" end
        parts[#parts + 1] = "Quest ID " .. quest.id
        detail.meta:SetText(table.concat(parts, " / "))
        detail.description:SetText(quest.description)
        local objectives = quest.objectives and quest.objectives ~= "" and quest.objectives ~= quest.description
        detail.objectiveTitle:SetShown(objectives and true or false)
        detail.objectives:SetShown(objectives and true or false)
        detail.objectives:SetText(objectives and quest.objectives or "")
        detail.abandon:SetEnabled(quest.canAbandon)
        detail.abandon:Show()
        detail.hint:SetText(quest.canAbandon and "Requires confirmation" or "Cannot abandon right now")
    end
    detail.scroll:ClearAllPoints()
    detail.scroll:SetPoint("TOPLEFT", detail.meta, "BOTTOMLEFT", 0, -24)
    detail.scroll:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -22, 66)
    local height = detail.description:GetStringHeight()
    if detail.objectives:IsShown() then
        detail.objectiveTitle:ClearAllPoints()
        detail.objectiveTitle:SetPoint("TOPLEFT", detail.scroll.content, "TOPLEFT", 0, -height - 26)
        detail.objectives:ClearAllPoints()
        detail.objectives:SetPoint("TOPLEFT", detail.objectiveTitle, "BOTTOMLEFT", 0, -10)
        height = height + 26 + detail.objectiveTitle:GetStringHeight() + 10 + detail.objectives:GetStringHeight()
    end
    detail.scroll:SetContentHeight(height + 12)
end

function Helper.SelectOrphanQuest(questID)
    local quest = window and window.questsByID[questID]
    if not quest then return end
    local changed = window.selectedID ~= questID
    window.selectedID = questID
    ShowDetail(quest, nil, window.hiddenDungeons)
    if changed then window.detail.scroll:ResetScroll() end
    PaintSelection()
end

local function NewQuestRow()
    local t = window.theme
    local row = CreateFrame("Button", nil, window.list.content)
    row:SetWidth(294)
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetColorTexture(t.accent.r, t.accent.g, t.accent.b, 0.12)
    row.indicator = row:CreateTexture(nil, "ARTWORK")
    row.indicator:SetPoint("TOPLEFT")
    row.indicator:SetPoint("BOTTOMLEFT")
    row.indicator:SetWidth(1)
    row.indicator:SetColorTexture(t.accent.r, t.accent.g, t.accent.b, 1)
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.04)
    row.hover:Hide()
    row.title = Label(row, 14, t.text, 266)
    row.title:SetPoint("TOPLEFT", 14, -10)
    row.meta = Label(row, 11, t.muted, 266)
    row.meta:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -6)
    row:SetScript("OnClick", function(self) Helper.SelectOrphanQuest(self.questID) end)
    row:SetScript("OnEnter", function(self) self.hover:Show() end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)
    return row
end

function Helper.SetExcludeDungeonQuests(exclude)
    Helper.GetOrphanSettings().excludeDungeonQuests = exclude == true
    if window then
        window.filter.checked = exclude == true
        window.filter.indicator:SetShown(exclude == true)
        window.list:ResetScroll()
        Helper.RefreshOrphanWindow()
    end
end

function Helper.RefreshOrphanWindow()
    if not window or not window:IsShown() then return end
    local quests, reason, hidden = Helper.GetOrphanQuests()
    hidden = hidden or 0
    window.hiddenDungeons = hidden
    window.questsByID = {}
    local counts, zones = {}, 0
    for _, quest in ipairs(quests) do
        window.questsByID[quest.id] = quest
        if not counts[quest.zone] then counts[quest.zone] = 0; zones = zones + 1 end
        counts[quest.zone] = counts[quest.zone] + 1
    end
    window.status:SetText(reason or "Quests outside all installed RXP guide groupings")
    window.count:SetText(#quests .. " quests / " .. zones .. " zones" .. (hidden > 0 and (" / " .. hidden .. " dungeon hidden") or ""))
    local y, zone, headers = 0, nil, 0
    for i, quest in ipairs(quests) do
        if zone ~= quest.zone then
            zone = quest.zone
            headers = headers + 1
            local header = window.headers[headers]
            if not header then
                header = CreateFrame("Frame", nil, window.list.content)
                header:SetWidth(294)
                header.title = Label(header, 12, window.theme.accent, 250)
                header.title:SetPoint("TOPLEFT", 14, -10)
                header.count = Label(header, 11, window.theme.muted)
                header.count:SetPoint("TOPRIGHT", -12, -10)
                window.headers[headers] = header
            end
            if i > 1 then y = y + 16 end
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", 0, -y)
            header.title:SetText(zone)
            header.count:SetText(tostring(counts[zone]))
            header:SetHeight(math.max(32, header.title:GetStringHeight() + 18))
            header:Show()
            y = y + header:GetHeight()
        end
        local row = window.rows[i]
        if not row then row = NewQuestRow(); window.rows[i] = row end
        row.questID = quest.id
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row.title:SetText(quest.title)
        row.meta:SetText((quest.level and quest.level > 0 and ("Level " .. quest.level) or "Quest") .. (quest.isDungeon and " / Dungeon" or ""))
        row:SetHeight(math.max(58, row.title:GetStringHeight() + 34))
        row:Show()
        y = y + row:GetHeight() + 2
    end
    for i = #quests + 1, #window.rows do window.rows[i]:Hide() end
    for i = headers + 1, #window.headers do window.headers[i]:Hide() end
    window.list:SetContentHeight(y + 8)
    local selected = window.questsByID[window.selectedID]
    if not selected and not reason then selected = quests[1]; window.selectedID = selected and selected.id end
    ShowDetail(selected, reason, hidden)
    PaintSelection()
end

function Helper.ShowOrphanWindow()
    if not window then
        window = CreateFrame("Frame", "RestedXPHelperOrphanFrame", UIParent, "BackdropTemplate")
        window.theme = Helper.GetOrphanTheme()
        local t = window.theme
        window:SetSize(1040, 660)
        window:SetPoint("CENTER")
        window:SetFrameStrata("DIALOG")
        window:SetClampedToScreen(true)
        window:SetMovable(true)
        Surface(window, t.background, true)
        if UIParent and UIParent.GetWidth then
            window:SetScale(math.min(1, (UIParent:GetWidth() - 48) / 1040, (UIParent:GetHeight() - 48) / 660))
        end
        local drag = CreateFrame("Frame", nil, window)
        drag:SetPoint("TOPLEFT")
        drag:SetPoint("TOPRIGHT")
        drag:SetHeight(86)
        drag:EnableMouse(true)
        drag:RegisterForDrag("LeftButton")
        drag:SetScript("OnDragStart", function() window:StartMoving() end)
        drag:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
        local title = Label(window, 24, t.text)
        title:SetPoint("TOPLEFT", 28, -26)
        title:SetText("Orphan quests")
        window.status = Label(window, 12, t.muted, 900)
        window.status:SetPoint("TOPLEFT", 28, -61)
        window.close = Button(window, "Close", 66, function() window:Hide() end)
        window.close:SetPoint("TOPRIGHT", -24, -26)
        window.filter = CreateFrame("Button", nil, window)
        window.filter:SetSize(234, 28)
        window.filter:SetPoint("TOPLEFT", 28, -99)
        local box = CreateFrame("Frame", nil, window.filter, "BackdropTemplate")
        box:SetSize(16, 16)
        box:SetPoint("LEFT")
        Surface(box, t.panel, true)
        window.filter.indicator = box:CreateTexture(nil, "ARTWORK")
        window.filter.indicator:SetSize(8, 8)
        window.filter.indicator:SetPoint("CENTER")
        window.filter.indicator:SetColorTexture(t.accent.r, t.accent.g, t.accent.b)
        local filterLabel = Label(window.filter, 13, t.text)
        filterLabel:SetPoint("LEFT", box, "RIGHT", 10, 0)
        filterLabel:SetText("Exclude dungeon quests")
        window.filter.checked = Helper.GetOrphanSettings().excludeDungeonQuests == true
        window.filter.indicator:SetShown(window.filter.checked)
        window.filter:SetScript("OnClick", function(self) Helper.SetExcludeDungeonQuests(not self.checked) end)
        window.count = Label(window, 12, t.muted)
        window.count:SetPoint("TOPRIGHT", -28, -106)
        window.left = CreateFrame("Frame", nil, window, "BackdropTemplate")
        window.left:SetPoint("TOPLEFT", 24, -144)
        window.left:SetSize(322, 444)
        Surface(window.left, t.panel)
        window.list = Scroll(window.left, 308)
        window.list:SetPoint("TOPLEFT", 8, -8)
        window.list:SetSize(308, 428)
        window.detail = CreateFrame("Frame", nil, window)
        local detail = window.detail
        detail:SetPoint("TOPLEFT", 364, -144)
        detail:SetSize(652, 444)
        detail.zone = Label(detail, 12, t.accent, 600)
        detail.zone:SetPoint("TOPLEFT", 18, -12)
        detail.title = Label(detail, 22, t.text, 600)
        detail.title:SetPoint("TOPLEFT", detail.zone, "BOTTOMLEFT", 0, -12)
        detail.meta = Label(detail, 12, t.muted, 600)
        detail.meta:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -10)
        detail.scroll = Scroll(detail, 612)
        detail.description = Label(detail.scroll.content, 14, t.text, 590)
        detail.description:SetPoint("TOPLEFT")
        detail.description:SetSpacing(4)
        detail.objectiveTitle = Label(detail.scroll.content, 14, t.accent, 590)
        detail.objectiveTitle:SetText("Objectives")
        detail.objectives = Label(detail.scroll.content, 14, t.text, 590)
        detail.objectives:SetSpacing(4)
        detail.abandon = Button(detail, "Abandon quest", 138, function() Helper.ConfirmAbandonOrphan(window.selectedID) end, true)
        detail.abandon:SetPoint("BOTTOMRIGHT", -22, 12)
        detail.hint = Label(detail, 11, t.muted)
        detail.hint:SetPoint("BOTTOMLEFT", 18, 22)
        local rescan = Button(window, "Rescan guides", 128, function() Helper.RequestGuideRescan() end)
        rescan:SetPoint("BOTTOMLEFT", 24, 20)
        local refresh = Button(window, "Refresh", 86, Helper.RefreshOrphanWindow)
        refresh:SetPoint("LEFT", rescan, "RIGHT", 10, 0)
        local scope = Label(window, 11, t.muted)
        scope:SetPoint("BOTTOMRIGHT", -28, 30)
        scope:SetText("RestedXP Helper / all guide groupings")
        window.rows, window.headers, window.questsByID = {}, {}, {}
        window:SetScript("OnShow", Helper.RefreshOrphanWindow)
        table.insert(UISpecialFrames, "RestedXPHelperOrphanFrame")
    end
    Helper.ResetOrphanDescriptionRequests()
    window:Show()
    Helper.RefreshOrphanWindow()
end
