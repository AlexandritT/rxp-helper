local _, Bridge = ...

local questTags = {
    accept = true, turnin = true, complete = true, collect = true,
    daily = true, dailyturnin = true, acceptmultiple = true,
    turninmultiple = true, acceptmap = true,
}
local multipleTags = {
    daily = true, dailyturnin = true, acceptmultiple = true, turninmultiple = true,
}

function Bridge.QuestID(value)
    local id = tonumber(value)
    if not id or id == 0 or id ~= math.floor(id) then return nil end
    return math.abs(id)
end

function Bridge.CleanText(value)
    if type(value) ~= "string" then return "" end
    return (value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|T.-|t", ""):gsub("|A.-|a", ""))
end

-- Read RXP's parsed elements, never guide text or quest titles. RXP has
-- already applied faction, class, race and quest-ID conversions here.
function Bridge.IndexGuide(index, guide)
    if type(guide) ~= "table" or guide.disabled or guide.internal
        or not guide.name or type(guide.steps) ~= "table" then return false end

    local group = Bridge.CleanText(guide.groupdisplayname or guide.group)
    local name = Bridge.CleanText(guide.displayname or guide.name)
    local record = {
        key = guide.key or ((guide.group or "") .. "||" .. guide.name),
        name = name,
        group = group,
        subgroup = Bridge.CleanText(guide.subgroup),
    }

    local function AddQuest(value, stepNumber)
        local id = Bridge.QuestID(value)
        if not id then return end
        local matches = index[id]
        if not matches then matches = {}; index[id] = matches end
        local match = matches[record.key]
        if not match then
            match = { guide = record, steps = {}, stepSet = {} }
            matches[record.key] = match
        end
        if not match.stepSet[stepNumber] then
            match.stepSet[stepNumber] = true
            match.steps[#match.steps + 1] = stepNumber
        end
    end

    for stepNumber, step in ipairs(guide.steps) do
        for _, element in ipairs(step.elements or {}) do
            if questTags[element.tag] then
                AddQuest(element.questId, stepNumber)
                if multipleTags[element.tag] and type(element.ids) == "table" then
                    for _, id in ipairs(element.ids) do AddQuest(id, stepNumber) end
                end
            end
        end
    end
    return true
end

function Bridge.GetMatches(index, questID)
    local matches = {}
    for _, match in pairs(index[Bridge.QuestID(questID)] or {}) do
        matches[#matches + 1] = match
    end
    table.sort(matches, function(a, b)
        local x, y = a.guide, b.guide
        if x.group ~= y.group then return x.group < y.group end
        if x.subgroup ~= y.subgroup then return x.subgroup < y.subgroup end
        if x.name ~= y.name then return x.name < y.name end
        return x.key < y.key
    end)
    return matches
end
