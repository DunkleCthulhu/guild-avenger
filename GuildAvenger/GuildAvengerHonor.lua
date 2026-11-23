local _, addon = ...

local patterns
local recentLines, lineOrder, nextSlot = {}, {}, 1

local function literal(text)
    return (text:gsub("(%p)", "%%%1"))
end

local function killPattern(template, honorArgument)
    if not addon.IsText(template) or template == "" then return end
    local parts, cursor = { "^" }, 1
    local argument, captures = 0, 0
    local victimCapture, honorCapture
    while true do
        local marker = template:find("%%", cursor)
        parts[#parts + 1] = literal(template:sub(cursor, marker and marker - 1 or #template))
        if not marker then break end
        local rest = template:sub(marker)
        if rest:sub(1, 2) == "%%" then
            parts[#parts + 1] = "%%"
            cursor = marker + 2
        else
            local token, position, kind = rest:match("^(%%(%d+)%$([sd]))")
            if not token then
                token, kind = rest:match("^(%%([sd]))")
            end
            if not token then return end
            argument = argument + 1
            local index = tonumber(position) or argument
            captures = captures + 1
            parts[#parts + 1] = kind == "d" and "(%d+)" or "(.-)"
            if index == 1 and kind == "s" then victimCapture = captures end
            if index == honorArgument and kind == "d" then honorCapture = captures end
            cursor = marker + #token
        end
    end
    if not victimCapture or not honorCapture then return end
    parts[#parts + 1] = "$"
    return { pattern = table.concat(parts), victim = victimCapture, honor = honorCapture }
end

local function honorPatterns()
    local formats = {}
    local function add(template, honorArgument)
        local format = killPattern(template, honorArgument)
        if format then formats[#formats + 1] = format end
    end
    add(COMBATLOG_HONORGAIN, 3)
    add(COMBATLOG_HONORGAIN_NO_RANK, 2)
    add(COMBATLOG_HONORGAIN_EXHAUSTION1, 3)
    add(COMBATLOG_HONORGAIN_NO_RANK_EXHAUSTION1, 2)
    return formats
end

local function killAward(message)
    patterns = patterns or honorPatterns()
    for _, format in ipairs(patterns) do
        local fields = { message:match(format.pattern) }
        local victim, honor = fields[format.victim], tonumber(fields[format.honor])
        if victim and honor then
            victim = victim:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local linkedName = victim:match("^|Hplayer:([^:|]+)[^|]*|h.-|h$")
            return linkedName or victim, honor
        end
    end
end

function addon.OnHonorGain(message, lineID)
    if not addon.IsText(message) or #message > 1024 then return end
    local trackLine = addon.Ordinary(lineID) and type(lineID) == "number" and lineID > 0
    if trackLine and recentLines[lineID] then return end
    local victim, honor = killAward(message)
    if not victim or honor <= 0 or honor > 2147483647 or not addon.IsHonorTarget(victim) then return end
    if not addon.RecordHonor(honor) or not trackLine then return end
    local oldest = lineOrder[nextSlot]
    if oldest then recentLines[oldest] = nil end
    recentLines[lineID], lineOrder[nextSlot] = true, lineID
    nextSlot = nextSlot % 256 + 1
end
