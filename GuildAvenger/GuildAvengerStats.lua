local _, addon = ...
local L = addon.Text
local prefix = "GuildAvStats1"
local maxCount = 2147483647
local journalLimit = 100
local heldDeath, latestDeath, sendTicker, lastRequest, lastReply

local function isNumber(value)
    return addon.Ordinary(value) and type(value) == "number"
end

local function playerGUID(guid)
    if not addon.IsText(guid) or #guid > 40 then return end
    local realm, id = guid:match("^Player%-(%d+)%-(%x+)$")
    if realm then return ("Player-%s-%s"):format(realm, id:upper()) end
end

local function guildData()
    local scope = addon.Scope()
    if not scope or scope == "local" or not IsInGuild() then return end
    local guilds = GuildAvengerDB.stats.guilds
    if not guilds[scope] then guilds[scope] = { own = {}, peers = {} } end
    return guilds[scope], scope
end

local function ownScore()
    local guild, scope = guildData()
    local key, name = addon.UnitName("player")
    if not guild or not key then return end
    if not guild.own[key] then guild.own[key] = { kills = 0, enemies = {} } end
    return guild.own[key], scope, key, name
end

local function currentWeek(timestamp)
    return math.floor(((timestamp or GetServerTime()) + 3 * 86400) / (7 * 86400))
end
addon.CurrentWeek = currentWeek

local function weeklyKills(score, week)
    return score.week == week and score.weeklyKills or 0
end

local function weeklyHonor(score, week)
    return score.honorWeek == week and score.weeklyHonor or 0
end

function addon.InitStats()
    GuildAvengerDB.stats = GuildAvengerDB.stats or { journals = {}, guilds = {} }
    GuildAvengerDB.stats.honorJournals = GuildAvengerDB.stats.honorJournals or {}
    C_ChatInfo.RegisterAddonMessagePrefix(prefix)
end

function addon.IsOwnKillingBlow(guid)
    if not addon.IsText(guid) then return false end
    local character, pet = UnitGUID("player"), UnitGUID("pet")
    return (addon.IsText(character) and guid == character) or (addon.IsText(pet) and guid == pet)
end

function addon.RecordRevenge()
    local score = ownScore()
    if not score then return end
    score.kills = math.min(maxCount, score.kills + 1)
    local week = currentWeek()
    score.weeklyKills = math.min(maxCount, weeklyKills(score, week) + 1)
    score.week = week
    addon.RefreshStats()
end

function addon.RecordHonor(amount)
    local score = ownScore()
    if not score then return end
    local week = currentWeek()
    score.honor = math.min(maxCount, (score.honor or 0) + amount)
    score.weeklyHonor = math.min(maxCount, weeklyHonor(score, week) + amount)
    score.honorWeek = week
    return true
end

local function journal(bucket)
    local guid = playerGUID(UnitGUID("player"))
    if not guid then return end
    local journals = GuildAvengerDB.stats[bucket or "journals"]
    if not journals[guid] then journals[guid] = {} end
    return journals[guid]
end

local function rememberEvent(rows, event)
    table.insert(rows, 1, event)
    if #rows > journalLimit then table.remove(rows) end
end

function addon.RecordHonorEvent(victim, amount, reason, raced)
    local rows = journal("honorJournals")
    if rows then
        rememberEvent(rows, { at = GetServerTime(), victim = victim, amount = amount, reason = reason, raced = raced })
    end
    addon.RefreshStats()
end

local function location(entry)
    entry.zone = addon.Clean(GetRealZoneText(), 140)
    entry.area = addon.Clean(GetSubZoneText(), 140)
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not isNumber(mapID) then return end
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    if not addon.Ordinary(position) or not position then return end
    local x, y = position:GetXY()
    if isNumber(x) and isNumber(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 and (x > 0 or y > 0) then
        entry.x, entry.y = x, y
    end
end

local function lethalHit(when, clock)
    if not C_DeathRecap or not C_DeathRecap.GetRecapEvents then return end
    local ok, hits = pcall(C_DeathRecap.GetRecapEvents)
    if not ok or not addon.Ordinary(hits) or type(hits) ~= "table" then return end
    local latest, time
    for _, hit in ipairs(hits) do
        if addon.Ordinary(hit) and type(hit) == "table" and isNumber(hit.overkill) and hit.overkill >= 0
            and isNumber(hit.timestamp) and (math.abs(hit.timestamp - when) <= 5 or math.abs(hit.timestamp - clock) <= 5)
            and (not time or hit.timestamp > time) then
            latest, time = hit, hit.timestamp
        end
    end
    return latest
end

local function identifyKiller(entry, hit, guid, score)
    local name = addon.Clean(hit.sourceName, addon.NameLimit)
    local flags = hit.sourceFlags
    local hostile = guid and isNumber(flags) and bit.band(flags, 0x40) ~= 0
    if guid and UnitTokenFromGUID then
        local unit = UnitTokenFromGUID(hit.sourceGUID)
        if addon.IsText(unit) then
            local key, full = addon.UnitName(unit)
            name = full or name
            local faction, own = UnitFactionGroup(unit), UnitFactionGroup("player")
            if unit == "player" or (key and addon.IsGuildMember(key))
                or (addon.IsText(faction) and addon.IsText(own) and faction == own) then
                hostile = false
            end
        end
    end
    entry.killer, entry.killerGUID = (name ~= "" and name or nil), guid
    if score and hostile and entry.killer then
        local previous = score.enemies[guid]
        score.enemies[guid] = { name = name, count = math.min(maxCount, (previous and previous.count or 0) + 1) }
    end
end

function addon.RecordOwnDeath()
    if heldDeath then return end
    local deaths = journal()
    if not deaths then return end
    local entry = { at = GetServerTime() }
    local clock = GetTime()
    heldDeath, latestDeath = entry, entry
    location(entry)
    local score = ownScore()
    local delays = { 0.3, 0.6, 1.1 }
    local function readRecap(attempt)
        if latestDeath ~= entry then return end
        local hit = lethalHit(entry.at, clock)
        local guid = hit and playerGUID(hit.sourceGUID)
        if guid and guid ~= playerGUID(UnitGUID("player")) then
            identifyKiller(entry, hit, guid, score)
            rememberEvent(deaths, entry)
            addon.RefreshStats()
        elseif attempt < #delays and heldDeath == entry then
            C_Timer.After(delays[attempt + 1], function() readRecap(attempt + 1) end)
        end
    end
    C_Timer.After(delays[1], function() readRecap(1) end)
end

function addon.ResetOwnDeath()
    local dead = UnitIsDeadOrGhost("player")
    if addon.Ordinary(dead) and dead == false then heldDeath = nil end
end

function addon.StatsSharing()
    local score = ownScore()
    return score and score.share == true or false
end

local function send(message)
    return C_ChatInfo.SendAddonMessage(prefix, message, "GUILD")
end

local function publish()
    local score, scope, key = ownScore()
    if sendTicker or not score or not score.share or not addon.IsGuildMember(key) then return end
    local packets = { ("R\t%d"):format(score.kills) }
    local week = currentWeek()
    if weeklyKills(score, week) > 0 then
        packets[#packets + 1] = ("W\t%d\t%d"):format(week, score.weeklyKills)
    end
    if score.honor and score.honor > 0 then
        packets[#packets + 1] = ("H\t%d\t%d\t%d"):format(score.honor, week, weeklyHonor(score, week))
    end
    for guid, enemy in pairs(score.enemies) do
        packets[#packets + 1] = ("E\t%s\t%d\t%s"):format(guid, enemy.count, enemy.name)
    end
    local index, progressAt = 1, GetTime()
    local function stop()
        sendTicker:Cancel()
        sendTicker = nil
    end
    sendTicker = C_Timer.NewTicker(0.25, function()
        local current, currentScope, currentKey = ownScore()
        if currentScope ~= scope or current ~= score or not current.share or not addon.IsGuildMember(currentKey)
            or GetTime() - progressAt >= 60 then
            stop()
            return
        end
        local results = Enum.SendAddonMessageResult
        local result = send(packets[index])
        if result == results.AddonMessageThrottle or result == results.ChannelThrottle then return end
        index = index + 1
        progressAt = GetTime()
        if result ~= results.Success or index > #packets then stop() end
    end)
end

function addon.SetStatsSharing(enabled)
    local score = ownScore()
    if not score then return end
    score.share = enabled and true or nil
    if enabled then publish() end
end

function addon.RequestStats()
    local score, _, key = ownScore()
    if not score or not addon.IsGuildMember(key) then
        addon.RefreshRoster()
        return L("statsRosterRequired")
    end
    local now = GetTime()
    if lastRequest and now - lastRequest < 20 then return L("statsRequestCooldown") end
    if send("Q") ~= Enum.SendAddonMessageResult.Success then return L("statsRequestFailed") end
    lastRequest = now
    publish()
    return L("statsRequestSent")
end

function addon.ReceiveStats(receivedPrefix, message, channel, sender)
    if not addon.IsText(receivedPrefix) or receivedPrefix ~= prefix
        or not addon.IsText(channel) or channel ~= "GUILD" or not addon.IsText(message) or #message > 180 then return end
    local key, name = addon.PlayerName(sender, true)
    local own, scope, ownKey = ownScore()
    if not own or not key or key == ownKey or not addon.IsGuildMember(key) then return end
    if message == "Q" then
        local now = GetTime()
        if own.share and (not lastReply or now - lastReply >= 45) then
            lastReply = now
            C_Timer.After(math.random(4, 28) / 10, function()
                if addon.Scope() == scope and ownScore() == own then publish() end
            end)
        end
        return
    end
    local kills = tonumber(message:match("^R\t(%d+)$"))
    local week, weekly = message:match("^W\t(%d+)\t(%d+)$")
    week, weekly = tonumber(week), tonumber(weekly)
    local current = currentWeek()
    local validWeek = week == current and weekly and weekly > 0 and weekly <= maxCount
    local honor, honorWeek, honorThisWeek = message:match("^H\t(%d+)\t(%d+)\t(%d+)$")
    honor, honorWeek, honorThisWeek = tonumber(honor), tonumber(honorWeek), tonumber(honorThisWeek)
    local validHonor = honor and honor > 0 and honor <= maxCount and honorThisWeek <= honor and honorWeek <= current
    local guid, amount, enemy = message:match("^E\t([^\t]+)\t(%d+)\t([^\t]+)$")
    guid, amount, enemy = playerGUID(guid), tonumber(amount), addon.Clean(enemy, addon.NameLimit)
    if not (kills and kills <= maxCount) and not validWeek and not validHonor
        and not (guid and amount and amount > 0 and amount <= maxCount and enemy and enemy ~= "") then
        return
    end
    local guild = guildData()
    local peer = guild.peers[key] or { kills = 0, enemies = {} }
    peer.name = name
    if kills then
        peer.kills = math.max(peer.kills, kills)
    elseif validWeek then
        peer.weeklyKills = math.max(weeklyKills(peer, week), weekly)
        peer.week = week
    elseif validHonor then
        peer.honor = math.max(peer.honor or 0, honor)
        if honorWeek == current then
            peer.weeklyHonor = math.max(weeklyHonor(peer, current), honorThisWeek)
            peer.honorWeek = current
        end
    else
        local previous = peer.enemies[guid]
        if not previous or amount >= previous.count then peer.enemies[guid] = { name = enemy, count = amount } end
    end
    guild.peers[key] = peer
    addon.RefreshStats()
end

local function eachScore(include)
    local own, _, ownKey, ownName = ownScore()
    if not own then return end
    include(own, ownName)
    local guild = guildData()
    for key, peer in pairs(guild.peers) do
        if key ~= ownKey and addon.IsGuildMember(key) then include(peer, peer.name) end
    end
end

local function addEnemyScore(total, enemy, guid)
    if not total then return { guid = guid, name = enemy.name, count = enemy.count } end
    if not total.name:find(" ", 1, true) and enemy.name:find(" ", 1, true) then total.name = enemy.name end
    total.count = total.count + enemy.count
    return total
end

function addon.RankedEnemy(guid)
    local key = playerGUID(guid)
    if not key then return end
    local total
    eachScore(function(score)
        local enemy = score.enemies[key]
        if enemy then total = addEnemyScore(total, enemy, key) end
    end)
    return total
end

function addon.EnemyScore(guid)
    local enemy = addon.RankedEnemy(guid)
    return enemy and enemy.count or 0
end

function addon.StatsRows(tab, weekly)
    if tab == 1 then
        local confirmed = {}
        for _, entry in ipairs(journal() or {}) do
            if playerGUID(entry.killerGUID) then confirmed[#confirmed + 1] = entry end
        end
        return confirmed
    end
    if tab == 5 then return journal("honorJournals") or {} end
    if tab == 6 then return addon.SeasonRows() end
    local rows, enemies = {}, {}
    local week = currentWeek()
    eachScore(function(score, name)
        if tab == 2 or tab == 4 then
            local count
            if tab == 2 then
                count = weekly and weeklyHonor(score, week) or (score.honor or 0)
            else
                count = weekly and weeklyKills(score, week) or score.kills
            end
            if count > 0 then rows[#rows + 1] = { name = name, count = count } end
        elseif tab == 3 then
            for guid, enemy in pairs(score.enemies) do
                enemies[guid] = addEnemyScore(enemies[guid], enemy, guid)
            end
        end
    end)
    for _, enemy in pairs(enemies) do rows[#rows + 1] = enemy end
    table.sort(rows, function(left, right)
        if left.count ~= right.count then return left.count > right.count end
        return addon.LowerName(left.name) < addon.LowerName(right.name)
    end)
    return rows
end
