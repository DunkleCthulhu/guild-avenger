local _, addon = ...
local L = addon.Text
local prefix = "GuildAvSeason1"
local maxTargets, maxHonor = 1000, 2147483647
local incoming, publisher, lastRequest, lastPublish, lastScore, checkedScope

local scope = addon.GuildScope

function addon.InitSeason()
    GuildAvengerDB.seasons = GuildAvengerDB.seasons or {}
    C_ChatInfo.RegisterAddonMessagePrefix(prefix)
end

function addon.ActiveSeason()
    local guild = scope()
    local season = guild and GuildAvengerDB.seasons[guild]
    if season and season.week == addon.CurrentWeek() then return season end
end

local function send(message)
    return C_ChatInfo.SendAddonMessage(prefix, message, "GUILD")
end

local function justSent(last, guild, interval)
    return last and last.guild == guild and GetTime() - last.at < interval
end

local function publish(season)
    local guild = scope()
    if publisher or not addon.IsGuildLeaderKey(addon.UnitName("player")) or justSent(lastPublish, guild, 12) then return end
    local packets = { ("B\t%d\t%s\t%d"):format(season.week, season.id, season.count) }
    for _, target in pairs(season.targets) do
        packets[#packets + 1] = ("T\t%s\t%s\t%s"):format(season.id, target.kind, target.name)
    end
    lastPublish = {guild = guild, at = GetTime()}
    local index, progress = 1, GetTime()
    publisher = C_Timer.NewTicker(0.25, function()
        if index <= #packets and scope() == guild and addon.ActiveSeason() == season and GetTime() - progress < 60
            and addon.IsGuildLeaderKey(addon.UnitName("player")) then
            local result = send(packets[index])
            local results = Enum.SendAddonMessageResult
            if result == results.AddonMessageThrottle or result == results.ChannelThrottle
                or result == results.AddOnMessageLockdown then return end
            if result == results.Success then
                index, progress = index + 1, GetTime()
                if index <= #packets then return end
            end
        end
        publisher:Cancel()
        publisher = nil
    end)
end

function addon.StartSeason(selection)
    local guild = scope()
    if not guild or not addon.IsGuildLeaderKey(addon.UnitName("player")) then
        return false, L("seasonLeaderOnly")
    end
    if addon.ActiveSeason() then return false, L("seasonLocked") end
    local targets, count = {}, 0
    for _, entry in ipairs(addon.Entries()) do
        local key = addon.RecordKey(entry)
        if (not selection or selection[key]) and addon.EligibleRecord(key, entry) then
            targets[key] = {kind = entry.kind, name = entry.name}
            count = count + 1
        end
    end
    if count == 0 then return false, L("nothingToShare") end
    if count > maxTargets then return false, L("tooManyEntries") end
    local season = {week = addon.CurrentWeek(), id = ("%x"):format(GetServerTime()),
        count = count, targets = targets, scores = {}}
    GuildAvengerDB.seasons[guild] = season
    publish(season)
    addon.RefreshStats()
    return true, L("seasonStarted", count)
end

function addon.RecordSeasonHonor(player, guild, amount)
    local season = addon.ActiveSeason()
    local key, name = addon.UnitName("player")
    if not season or not key or not (season.targets[player] or season.targets[guild]) then return false end
    local previous = season.scores[key]
    season.scores[key] = {name = name, count = math.min(maxHonor, (previous and previous.count or 0) + amount)}
    return true
end

local function publishScore(season, guild)
    local key = addon.UnitName("player")
    local score = key and season.scores[key]
    if not score or not addon.StatsSharing() or justSent(lastScore, guild, 15) then return end
    lastScore = {guild = guild, at = GetTime()}
    C_Timer.After(math.random(4, 20) / 10, function()
        if scope() ~= guild or addon.ActiveSeason() ~= season or not addon.StatsSharing() then return end
        send(("H\t%s\t%d"):format(season.id, season.scores[key].count))
    end)
end

function addon.RequestSeason()
    addon.RefreshRoster()
    local guild = scope()
    if not guild or not addon.IsGuildMember(addon.UnitName("player")) then return false, L("statsRosterRequired") end
    if justSent(lastRequest, guild, 15) then return false, L("statsRequestCooldown") end
    local season = addon.ActiveSeason()
    if send(season and ("Q\t" .. season.id) or "Q") ~= Enum.SendAddonMessageResult.Success then
        return false, L("statsRequestFailed")
    end
    lastRequest = {guild = guild, at = GetTime()}
    if season then
        publishScore(season, guild)
        if addon.IsGuildLeaderKey(addon.UnitName("player")) then publish(season) end
    end
    return true, L("seasonRequestSent")
end

function addon.SeasonRosterReady()
    local guild = scope()
    if not guild or checkedScope == guild or not addon.IsGuildMember(addon.UnitName("player")) then return end
    checkedScope = guild
    if not addon.ActiveSeason() and not addon.IsGuildLeaderKey(addon.UnitName("player")) then
        C_Timer.After(math.random(5, 35) / 10, function()
            if scope() == guild and not addon.ActiveSeason() then addon.RequestSeason() end
        end)
    end
end

local function receiveTargets(message, sender, guild)
    if not addon.IsGuildLeaderKey(sender) or addon.ActiveSeason() then return end
    local week, id, count = message:match("^B\t(%d+)\t([%da-f]+)\t(%d+)$")
    if week then
        week, count = tonumber(week), tonumber(count)
        local created = #id <= 8 and tonumber(id, 16)
        if week ~= addon.CurrentWeek() or count < 1 or count > maxTargets or not created
            or addon.CurrentWeek(created) ~= week or created > GetServerTime() + 5 then return end
        incoming = {guild = guild, week = week, id = id, count = count, sender = sender,
            targets = {}, received = 0, at = GetTime()}
        return
    end
    if not incoming or incoming.guild ~= guild or incoming.sender ~= sender or incoming.week ~= addon.CurrentWeek()
        or GetTime() - incoming.at >= 75 then return end
    local targetID, kind, name = message:match("^T\t([%da-f]+)\t([PG])\t([^\t]+)$")
    if targetID ~= incoming.id then return end
    local key, full = addon.EntryName(name, kind)
    if not key or incoming.targets[key] then return end
    incoming.targets[key] = {kind = kind, name = full}
    incoming.at, incoming.received = GetTime(), incoming.received + 1
    if incoming.received == incoming.count then
        GuildAvengerDB.seasons[guild] = {week = incoming.week, id = incoming.id, count = incoming.count,
            targets = incoming.targets, scores = {}}
        incoming = nil
        send("Q\t" .. targetID)
        addon.RefreshStats()
    end
end

function addon.ReceiveSeason(mark, message, channel, senderName)
    if not addon.IsText(mark) or mark ~= prefix or not addon.IsText(channel) or channel ~= "GUILD"
        or not addon.IsText(message) or #message > 150 then return end
    local sender, name = addon.GuildSender(senderName, true)
    local guild = scope()
    if not guild or not sender or sender == addon.UnitName("player") then return end
    local season = addon.ActiveSeason()
    if message == "Q" then
        if season then publish(season) end
        return
    end
    if not season then
        receiveTargets(message, sender, guild)
        return
    end
    if message == "Q\t" .. season.id then
        publishScore(season, guild)
        return
    end
    local id, amount = message:match("^H\t([%da-f]+)\t(%d+)$")
    amount = tonumber(amount)
    if id ~= season.id or not amount or amount < 1 or amount > maxHonor then return end
    local previous = season.scores[sender]
    if not previous or amount > previous.count then
        season.scores[sender] = {name = name, count = amount}
        addon.RefreshStats()
    end
end

function addon.SeasonRows()
    local season = addon.ActiveSeason()
    local rows = {}
    if not season then return rows end
    for key, score in pairs(season.scores) do
        if key == addon.UnitName("player") or addon.IsGuildMember(key) then rows[#rows + 1] = score end
    end
    table.sort(rows, function(left, right)
        if left.count ~= right.count then return left.count > right.count end
        return addon.LowerName(left.name) < addon.LowerName(right.name)
    end)
    return rows
end

function addon.SeasonTargets()
    local season = addon.ActiveSeason()
    local rows = {}
    if not season then return rows end
    for _, target in pairs(season.targets) do rows[#rows + 1] = target end
    table.sort(rows, function(left, right) return addon.LowerName(left.name) < addon.LowerName(right.name) end)
    return rows
end
