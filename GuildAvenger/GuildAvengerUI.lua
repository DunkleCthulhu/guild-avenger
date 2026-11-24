local addonName, addon = ...
local L = addon.Text
local panel, dialog, review, toast, download, minimapButton, soundWindow
local statsWindow, commentWindow, settingsWindow, bugReport
local offers = {}
local rowCount, mainRowCount, rowHeight, rowGap = 7, 7, 42, 4
local highPrioritySound = "Interface\\AddOns\\GuildAvenger\\Sounds\\HighPriority.ogg"
local bookIcon = "Interface\\Icons\\INV_Misc_Book_11"

local color = {
    border = { 0.36, 0.29, 0.18, 1 },
    panel = { 0.11, 0.095, 0.073, 0.98 },
    inset = { 0.059, 0.052, 0.04, 1 },
    button = { 0.20, 0.13, 0.14, 1 },
    row = { 0.125, 0.108, 0.086, 1 },
    rowAlt = { 0.095, 0.082, 0.067, 1 },
    rowSelected = { 0.21, 0.16, 0.10, 1 },
    red = { 1, 0.28, 0.26, 1 },
    gold = { 0.95, 0.75, 0.50, 1 },
    muted = { 0.79, 0.73, 0.63, 1 },
    white = { 0.98, 0.93, 0.90, 1 },
}

local function fill(parent, tint, inset, depth)
    local texture = parent:CreateTexture(nil, "BACKGROUND", nil, depth)
    texture:SetPoint("TOPLEFT", inset, -inset)
    texture:SetPoint("BOTTOMRIGHT", -inset, inset)
    texture:SetColorTexture(unpack(tint))
    return texture
end

local function styleRow(row, index)
    fill(row, index % 2 == 0 and color.inset or color.panel, 0, 0)
    local rule = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    rule:SetPoint("BOTTOMLEFT", 0, 1)
    rule:SetPoint("BOTTOMRIGHT", 0, 1)
    rule:SetHeight(1)
    rule:SetColorTexture(0.56, 0.43, 0.25, 0.28)
end

local function label(parent, font, tint, text)
    local result = parent:CreateFontString(nil, "OVERLAY", font)
    result:SetTextColor(unpack(tint))
    result:SetText(text or "")
    return result
end

local function maskCircle(parent, texture)
    local mask = parent:CreateMaskTexture()
    mask:SetAllPoints(texture)
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    texture:AddMaskTexture(mask)
    return mask
end

local function button(parent, title, width, callback, template)
    local control = CreateFrame("Button", nil, parent, template or "UIPanelButtonTemplate")
    control:SetSize(width, 27)
    control:SetText(title)
    control.label = control:GetFontString()
    if callback then
        control:SetScript("OnClick", callback)
    end
    return control
end

local function enabled(control, state)
    control:SetEnabled(state)
    control:SetAlpha(state and 1 or 0.43)
end

local function input(parent, width, limit)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, 30)
    box:SetFontObject(GameFontHighlight)
    box:SetAutoFocus(false)
    box:SetMaxBytes(limit)
    box:SetTextInsets(8, 8, 0, 0)
    box:EnableMouse(true)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    fill(box, color.border, 0, -2)
    fill(box, color.inset, 1, -1)
    return box
end

local windowBackdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 22,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

local function window(name, width, height, strata)
    local root = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    root:Hide()
    root:SetPoint("CENTER")
    root:SetSize(width, height)
    root:SetFrameStrata(strata)
    root:SetClampedToScreen(true)
    root:EnableMouse(true)
    root:SetBackdrop(windowBackdrop)
    return root
end

local function showComment(text, title)
    if not commentWindow then
        local root = window("GuildAvengerComment", 500, 200, "FULLSCREEN_DIALOG")
        root:SetFrameLevel(32)
        tinsert(UISpecialFrames, "GuildAvengerComment")
        root.title = label(root, "GameFontNormalLarge", color.gold)
        root.title:SetPoint("TOPLEFT", 20, -16)
        root.title:SetWidth(460)
        root.title:SetMaxLines(1)
        root.title:SetJustifyH("LEFT")
        root.text = label(root, "GameFontHighlight", color.white)
        root.text:SetPoint("TOPLEFT", 20, -47)
        root.text:SetWidth(460)
        root.text:SetJustifyH("LEFT")
        root.text:SetWordWrap(true)
        root.text:SetNonSpaceWrap(true)
        button(root, L("close"), 90, function() root:Hide() end):SetPoint("BOTTOMRIGHT", -19, 13)
        commentWindow = root
    end
    commentWindow.title:SetText(title or L("note"))
    commentWindow.text:SetText(text)
    commentWindow:Show()
end

local function commentPreview(parent, text, width, lines, fullText)
    text:SetWidth(width - 17)
    text:SetWordWrap(true)
    text:SetNonSpaceWrap(true)
    text:SetMaxLines(lines)
    local control = CreateFrame("Button", nil, parent)
    control:SetPoint("TOPLEFT", text, "TOPLEFT")
    control:SetSize(width, lines * 13)
    label(control, "GameFontHighlightSmall", color.gold, "…"):SetPoint("TOPRIGHT", 0, -1)
    control:SetScript("OnClick", function()
        if fullText then showComment(fullText()) else showComment(text:GetText()) end
    end)
    return control
end

local function status(text, success, message)
    text:SetTextColor(unpack(success and color.muted or color.red))
    text:SetText(message or "")
end

local function metadata(entry)
    local author = entry.author ~= "" and entry.author or L("unknownAuthor")
    if entry.addedAt > 0 then
        return author .. "  /  " .. date("%d.%m.%Y %H:%M", entry.addedAt)
    end
    return author
end

local function lastSeen(entry)
    local seen = entry.seen
    if not seen then return end
    local zone = seen.zone and seen.zone ~= "" and (" · " .. seen.zone) or ""
    return L("lastSeen", date("%d.%m %H:%M", seen.at), zone)
end

local function selectionSize(selection)
    local count = 0
    for _ in pairs(selection) do count = count + 1 end
    return count
end

local function manualName()
    local name = panel.name:GetText()
    return name ~= panel.prefilledName and name:match("%S") and name or nil
end

local function updateAddLabels()
    local manual = manualName()
    local targetGuild = not manual and not panel.editing and addon.EnemyEntry("target", "G")
    panel.submit.label:SetText(panel.editing and L("save") or (manual and L("addCharacter") or L("addTarget")))
    panel.guild.label:SetText(targetGuild and L("guildFromTarget") or L("addGuild"))
end

local function searchText(value)
    local text = addon.SearchLower(value)
    return (text:gsub("’", "'"):gsub("ʼ", "'"):gsub("[ \t\r\n_%-]+", " "):match("^ *(.-) *$"))
end

local function renderRows()
    local slider = panel.scroll
    local offset = math.floor(slider:GetValue())
    for index, row in ipairs(panel.rows) do
        local entry = panel.entries[offset + index]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            local key = addon.RecordKey(entry)
            local selected = panel.selected[key] == true
            row.check:SetChecked(selected)
            row.border:SetColorTexture(unpack(selected and color.gold or color.border))
            row.background:SetColorTexture(unpack(selected and color.rowSelected or row.tint))
            row.name:SetText(entry.kind == "G" and L("guildNameLabel", entry.name) or entry.name)
            row.name:SetTextColor(unpack(entry.kind == "G" and color.gold or color.white))
            row.note:SetText(entry.note)
            local guildStatus = entry.kind == "G" and addon.GuildWatchStatus(key, entry.name)
            row.metadata:SetText((guildStatus and L(guildStatus)) or lastSeen(entry)
                or (addon.IsPendingEntry(entry) and L("pendingVerification") or metadata(entry)))
            row.deaths:SetText(("%d"):format(entry.deaths))
            row.priority.label:SetText(entry.high and L("high") or L("normal"))
            row.priority.label:SetTextColor(unpack(entry.high and color.gold or color.muted))
        end
    end
end

function addon.RefreshUI()
    if not panel or not panel:IsShown() then
        return
    end
    local scope = addon.Scope()
    if panel.scope ~= scope then
        panel.scope, panel.editing = scope, nil
        panel.prefilledName = nil
        panel.selected = {}
        panel.name:SetText("")
        panel.note:SetText("")
        panel.scroll:SetValue(0)
    end
    local allEntries = addon.Entries()
    panel.entries = {}
    local present = {}
    local query = searchText(panel.search:GetText())
    for _, entry in ipairs(allEntries) do
        present[addon.RecordKey(entry)] = true
        local matches = query == "" or searchText(entry.name):find(query, 1, true)
            or searchText(entry.note or ""):find(query, 1, true)
        if matches and (not panel.filterKind or panel.filterKind == entry.kind) and (not panel.filterHigh or entry.high) then
            panel.entries[#panel.entries + 1] = entry
        end
    end
    for key in pairs(panel.selected) do
        if not present[key] then panel.selected[key] = nil end
    end
    local selected = selectionSize(panel.selected)
    panel.count:SetText(L("entryCount", #panel.entries, #allEntries))
    panel.selectAll:SetChecked(#allEntries > 0 and selected == #allEntries)
    panel.selectAll:SetEnabled(#allEntries > 0)
    panel.selectionCount:SetText(selected > 0 and tostring(selected) or "")
    enabled(panel.deleteSelected, selected > 0)
    local ready = scope ~= nil
    panel.name:SetEnabled(ready and not panel.editing)
    panel.note:SetEnabled(ready)
    enabled(panel.submit, ready)
    enabled(panel.share, ready and scope ~= "local")
    enabled(panel.pull, ready and scope ~= "local")
    local replies = addon.InboxCount()
    enabled(panel.inbox, replies > 0)
    panel.inbox.label:SetText(L("inboxButton", replies))
    panel.share.label:SetText(selected > 0 and L("shareCount", selected) or L("shareWatchlist"))
    panel.clearSelection:SetShown(selected > 0)
    updateAddLabels()
    panel.cancel:SetShown(panel.editing ~= nil)
    panel.guild:SetShown(not panel.editing)
    enabled(panel.guild, ready)
    panel.empty:SetText(ready and (#allEntries > 0 and L("emptyFilter") or L("emptyList"))
        or L("loadingGuild"))
    panel.empty:SetShown(#panel.entries == 0)
    local maximum = math.max(0, #panel.entries - mainRowCount)
    panel.scroll:SetMinMaxValues(0, maximum)
    panel.scroll:SetValue(math.min(maximum, panel.scroll:GetValue()))
    panel.scroll:SetShown(maximum > 0)
    renderRows()
end

local function resetForm()
    panel.editing = nil
    panel.prefilledName = nil
    panel.name:SetText("")
    panel.note:SetText("")
    panel.name:ClearFocus()
    panel.note:ClearFocus()
end

local function putTarget()
    local _, name = addon.EnemyUnit("target")
    panel.prefilledName = name
    panel.name:SetText(name or "")
    updateAddLabels()
end

local function finishForm(ok, message, name, kind)
    if ok then
        resetForm()
        addon.RefreshUI()
        local key = addon.EntryName(name, kind)
        for index, entry in ipairs(panel.entries) do
            if addon.RecordKey(entry) == key then
                panel.scroll:SetValue(math.max(0, index - mainRowCount))
                break
            end
        end
    end
    status(panel.status, ok, message)
end

local function submit()
    local note = panel.note:GetText()
    local name, kind, ok, message
    if panel.editing then
        name, kind = panel.editing.name, panel.editing.kind
        ok, message = addon.EditNote(name, note, kind, panel.editing)
    else
        name = manualName()
        if name then
            ok, message = addon.Add(name, note)
        else
            local _, target = addon.EnemyUnit("target")
            if not target then
                panel.prefilledName = nil
                panel.name:SetText("")
                panel.name:SetFocus()
                status(panel.status, false, L("enterNameOrTarget"))
                return
            end
            name = target
            ok, message = addon.Add("", note, "target")
        end
    end
    finishForm(ok, message, name, kind)
end

local submitGuild, confirmBulkRemoval

local function checkbox(parent, x, y, title)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(23, 23)
    check:SetPoint("TOPLEFT", x, y)
    label(check, "GameFontHighlightSmall", color.white, title):SetPoint("LEFT", check, "RIGHT", 1, 0)
    return check
end

local function soundOption(parent, x, y, title, key, checkedByDefault)
    local check = checkbox(parent, x, y, title)
    local value = GuildAvengerDB.sound[key]
    check:SetChecked(value == true or (value == nil and checkedByDefault))
    check:SetScript("OnClick", function(self)
        GuildAvengerDB.sound[key] = self:GetChecked() == true
    end)
end

local sounds = {
    { "RAID_WARNING", "soundRaidWarning" },
    { "RAID_BOSS_EMOTE_WARNING", "soundRaidBossEmote" },
    { "READY_CHECK", "soundReadyCheck" },
    { "ALARM_CLOCK_WARNING_1", "soundAlarm1" },
    { "ALARM_CLOCK_WARNING_3", "soundAlarm3" },
    { "UI_BNET_TOAST", "soundBattleNet" },
    { "MAP_PING", "soundMapPing" },
    { "IG_QUEST_LOG_OPEN", "soundQuestLog" },
}

local function playAlertSound(high)
    local choice = GuildAvengerDB.sound[high and "highSound" or "normalSound"]
    local kit = choice and SOUNDKIT[choice]
    if kit then
        PlaySound(kit, "Master")
    elseif not (high and PlaySoundFile and PlaySoundFile(highPrioritySound, "Master")) then
        PlaySound(high and SOUNDKIT.RAID_BOSS_EMOTE_WARNING or SOUNDKIT.RAID_WARNING, "Master")
    end
end

local function soundPicker(root, y, high)
    local setting = high and "highSound" or "normalSound"
    local title = high and L("highPriority") or L("normalPriority")
    label(root, "GameFontHighlightSmall", color.muted, title):SetPoint("TOPLEFT", 20, y)
    local dropdown = CreateFrame("DropdownButton", nil, root, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", 20, y - 16)
    dropdown:SetWidth(278)
    dropdown:SetupMenu(function(_, menu)
        local function isSelected(choice)
            return GuildAvengerDB.sound[setting] == choice
        end
        local function selectSound(choice)
            GuildAvengerDB.sound[setting] = choice
        end
        local default = high and L("defaultHighSound") or L("defaultNormalSound")
        menu:CreateRadio(default, function() return not SOUNDKIT[GuildAvengerDB.sound[setting] or ""] end,
            function() selectSound(nil) end)
        for _, sound in ipairs(sounds) do
            if SOUNDKIT[sound[1]] then menu:CreateRadio(L(sound[2]), isSelected, selectSound, sound[1]) end
        end
    end)
    button(root, L("previewSound"), 104, function() playAlertSound(high) end):SetPoint("LEFT", dropdown, "RIGHT", 10, 0)
end

function addon.PromptSounds()
    if not soundWindow then
        local root = window("GuildAvengerSounds", 436, 247, "FULLSCREEN_DIALOG")
        tinsert(UISpecialFrames, "GuildAvengerSounds")
        label(root, "GameFontNormalLarge", color.gold, L("soundTitle")):SetPoint("TOPLEFT", 20, -17)
        soundPicker(root, -51, false)
        soundPicker(root, -108, true)
        soundOption(root, 20, -169, L("characters"), "P", true)
        soundOption(root, 121, -169, L("guilds"), "G", true)
        soundOption(root, 196, -169, L("highOnly"), "highOnly", false)
        button(root, L("done"), 90, function() root:Hide() end):SetPoint("BOTTOMRIGHT", -19, 15)
        soundWindow = root
    end
    soundWindow:Show()
end

function addon.RefreshSettingsGuild()
    if settingsWindow and settingsWindow:IsShown() then
        settingsWindow.RefreshGuild()
    end
end

function addon.PromptSettings()
    if not settingsWindow then
        local root = window("GuildAvengerSettings", 430, 389, "FULLSCREEN_DIALOG")
        tinsert(UISpecialFrames, "GuildAvengerSettings")
        label(root, "GameFontNormalLarge", color.gold, L("settingsTitle")):SetPoint("TOPLEFT", 20, -17)
        label(root, "GameFontHighlight", color.white, L("language")):SetPoint("TOPLEFT", 20, -55)

        local dropdown = CreateFrame("DropdownButton", nil, root, "WowStyle1DropdownTemplate")
        dropdown:SetPoint("TOPRIGHT", -20, -48)
        dropdown:SetWidth(230)
        local message = label(root, "GameFontHighlightSmall", color.muted, L("languageHint"))
        message:SetPoint("TOPLEFT", 20, -92)
        message:SetPoint("TOPRIGHT", -20, -92)
        message:SetJustifyH("LEFT")

        local reply = checkbox(root, 17, -116, L("autoShareWatchlist"))
        local hint = label(root, "GameFontHighlightSmall", color.muted, L("autoShareWatchlistHint"))
        hint:SetPoint("TOPLEFT", 20, -145)
        hint:SetPoint("TOPRIGHT", -20, -145)
        hint:SetJustifyH("LEFT")
        hint:SetMaxLines(2)

        local attackers = checkbox(root, 17, -186, L("shareAttackerDetails"))
        local attackerHint = label(root, "GameFontHighlightSmall", color.muted, L("shareAttackerDetailsHint"))
        attackerHint:SetPoint("TOPLEFT", 20, -215)
        attackerHint:SetPoint("TOPRIGHT", -20, -215)
        attackerHint:SetJustifyH("LEFT")
        attackerHint:SetMaxLines(3)

        local guildMessage = label(root, "GameFontHighlightSmall", color.muted)
        guildMessage:SetPoint("TOPLEFT", 20, -254)
        guildMessage:SetPoint("TOPRIGHT", -20, -254)
        guildMessage:SetJustifyH("LEFT")
        guildMessage:SetMaxLines(2)
        local rule = root:CreateTexture(nil, "ARTWORK")
        rule:SetPoint("TOPLEFT", 20, -290)
        rule:SetPoint("TOPRIGHT", -20, -290)
        rule:SetHeight(1)
        rule:SetColorTexture(unpack(color.border))
        label(root, "GameFontHighlight", color.gold, L("createdByGuild")):SetPoint("TOPLEFT", 20, -303)
        button(root, L("reportBug"), 148, function() addon.PromptBugReport() end):SetPoint("TOPRIGHT", -20, -295)
        local authors = C_AddOns.GetAddOnMetadata(addonName, "Author") or ""
        local credits = label(root, "GameFontHighlightSmall", color.muted, L("addonCredits", authors))
        credits:SetPoint("TOPLEFT", 20, -323)
        credits:SetPoint("TOPRIGHT", -20, -323)
        credits:SetJustifyH("LEFT")

        local selected = GuildAvengerDB.language
        local scope, identity, privacyReady, savedReply, savedAttackers
        local apply = button(root, L("applySettings"), 235)
        apply:SetPoint("BOTTOMRIGHT", -20, 15)
        button(root, L("cancel"), 90, function() root:Hide() end):SetPoint("BOTTOMLEFT", 20, 15)
        local function sharingChanged()
            return privacyReady and ((reply:GetChecked() == true) ~= savedReply
                or (attackers:GetChecked() == true) ~= savedAttackers)
        end
        local function updateApply()
            local languageChanged = selected ~= GuildAvengerDB.language
            enabled(apply, languageChanged or sharingChanged())
            local reloadNeeded = GuildAvengerDB.language ~= addon.Language()
            message:SetText(L(not languageChanged and reloadNeeded and "languageSaved" or "languageHint"))
        end
        root.RefreshGuild = function()
            local currentScope, currentIdentity = addon.GuildPrivacyIdentity()
            privacyReady = currentScope ~= nil
            if privacyReady and (currentScope ~= scope or currentIdentity ~= identity) then
                scope, identity = currentScope, currentIdentity
                savedReply, savedAttackers = addon.AutoReplyEnabled(), addon.AttackerSharing()
                reply:SetChecked(savedReply)
                attackers:SetChecked(savedAttackers)
            end
            reply:SetEnabled(privacyReady)
            attackers:SetEnabled(privacyReady)
            local hintKey = IsInGuild() and "privacyWaitingGuild" or "privacyNoGuild"
            status(guildMessage, true, L(privacyReady and "privacySettingsHint" or hintKey))
            updateApply()
        end
        apply:SetScript("OnClick", function()
            GuildAvengerDB.language = selected
            if sharingChanged() then
                local ready = addon.UpdateScope()
                local currentScope, currentIdentity = addon.GuildPrivacyIdentity()
                if not ready or currentScope ~= scope or currentIdentity ~= identity then
                    root.RefreshGuild()
                    status(guildMessage, false, L("guildPrivacyChanged"))
                    return
                end
                local nextReply, nextAttackers = reply:GetChecked() == true, attackers:GetChecked() == true
                if nextReply ~= savedReply then addon.SetAutoReply(nextReply) end
                if nextAttackers ~= savedAttackers then addon.SetAttackerSharing(nextAttackers) end
                savedReply, savedAttackers = nextReply, nextAttackers
            end
            if selected ~= addon.Language() then
                updateApply()
            else
                root:Hide()
            end
        end)
        reply:SetScript("OnClick", updateApply)
        attackers:SetScript("OnClick", updateApply)
        root:SetScript("OnShow", function()
            selected = GuildAvengerDB.language
            scope, identity = nil, nil
            reply:SetChecked(false)
            attackers:SetChecked(false)
            addon.UpdateScope()
            addon.ReadRoster()
            addon.RefreshRoster()
            root.RefreshGuild()
            dropdown:GenerateMenu()
        end)
        dropdown:SetupMenu(function(_, menu)
            local function isSelected(language)
                return selected == language
            end
            local function selectLanguage(language)
                selected = language
                updateApply()
            end
            menu:CreateRadio(L("languageEnglish"), isSelected, selectLanguage, "enUS")
            menu:CreateRadio(L("languageUkrainian"), isSelected, selectLanguage, "ukUA")
        end)
        settingsWindow = root
    end
    settingsWindow:Show()
end

local function createFilters(root)
    local titles, kinds = { L("all"), L("characters"), L("guilds") }, { false, "P", "G" }
    root.Tabs = {}
    root.minTabWidth = 88
    for index, title in ipairs(titles) do
        local tab = CreateFrame("Button", nil, root, "PanelTopTabButtonTemplate")
        root.Tabs[index] = tab
        tab:SetID(index)
        tab:SetText(title)
        tab:SetScript("OnClick", function(self)
            local id = self:GetID()
            PanelTemplates_SetTab(root, id)
            root.filterKind = kinds[id]
            root.scroll:SetValue(0)
            addon.RefreshUI()
        end)
    end
    root.Tabs[1]:SetPoint("TOPLEFT", 20, -168)
    PanelTemplates_SetNumTabs(root, #titles)
    PanelTemplates_SetTab(root, 1)
    root.priorityFilter = checkbox(root, 448, -174, L("highOnly"))
    root.priorityFilter:SetScript("OnClick", function(self)
        root.filterHigh = self:GetChecked()
        root.scroll:SetValue(0)
        addon.RefreshUI()
    end)
    local toolbar = CreateFrame("Frame", nil, root)
    toolbar:SetPoint("TOPLEFT", 20, -200)
    toolbar:SetPoint("TOPRIGHT", -20, -200)
    toolbar:SetHeight(30)
    fill(toolbar, color.border, 0, -2)
    fill(toolbar, color.panel, 1, -1)
    root.selectAll = checkbox(toolbar, 7, -3, L("selectAll"))
    root.selectionCount = label(toolbar, "GameFontHighlightSmall", color.gold)
    root.selectionCount:SetPoint("LEFT", 112, 0)
    root.deleteSelected = button(toolbar, L("removeSelected"), 147, function() confirmBulkRemoval() end)
    root.deleteSelected:SetPoint("LEFT", 141, 0)
    root.deleteSelected:SetHeight(23)
    label(toolbar, "GameFontHighlightSmall", color.muted, L("priority")):SetPoint("LEFT", 315, 0)
    label(toolbar, "GameFontHighlightSmall", color.muted, L("deaths")):SetPoint("LEFT", 395, 0)
    root.count = label(toolbar, "GameFontHighlightSmall", color.muted)
    root.count:SetPoint("RIGHT", -9, 0)
    root.selectAll:SetScript("OnClick", function(self)
        root.selected = {}
        if self:GetChecked() then
            for _, entry in ipairs(addon.Entries()) do
                root.selected[addon.RecordKey(entry)] = true
            end
        end
        addon.RefreshUI()
    end)
end

local function createPanel()
    local root = window("GuildAvengerPanel", 662, 648, "DIALOG")
    root:SetMovable(true)
    root.rows, root.entries, root.selected = {}, {}, {}
    tinsert(UISpecialFrames, "GuildAvengerPanel")
    local header = CreateFrame("Frame", nil, root)
    header:SetPoint("TOPLEFT", 20, -12)
    header:SetSize(178, 34)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() root:StartMoving() end)
    header:SetScript("OnDragStop", function() root:StopMovingOrSizing() end)
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT")
    icon:SetTexture(bookIcon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    label(header, "GameFontNormalLarge", color.gold, "Guild Avenger"):SetPoint("TOPLEFT", 29, -2)
    label(header, "GameFontHighlightSmall", color.muted, L("createdByGuild")):SetPoint("BOTTOMLEFT", 29, 1)
    root.search = input(root, 210, addon.NoteLimit)
    root.search:SetTextInsets(8, 30, 0, 0)
    root.search:SetPoint("LEFT", header, "LEFT", 201, 0)
    local hint = label(root.search, "GameFontHighlightSmall", color.muted, L("searchHint"))
    hint:SetPoint("LEFT", 8, 0)
    local clearSearch = button(root.search, "×", 23, function()
        root.search:SetText("")
        root.search:SetFocus()
    end)
    clearSearch:SetHeight(23)
    clearSearch:SetPoint("RIGHT", -3, 0)
    clearSearch:Hide()
    clearSearch:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText(L("clearSearch"))
        GameTooltip:Show()
    end)
    clearSearch:SetScript("OnLeave", function() GameTooltip:Hide() end)
    root.search:SetScript("OnTextChanged", function(self)
        local empty = self:GetText() == ""
        hint:SetShown(empty)
        clearSearch:SetShown(not empty)
        if root.scroll then
            root.scroll:SetValue(0)
            addon.RefreshUI()
        end
    end)
    root.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local close = CreateFrame("Button", nil, root, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() root:Hide() end)
    button(root, L("settings"), 118, addon.PromptSettings):SetPoint("TOPRIGHT", -44, -15)

    label(root, "GameFontHighlightSmall", color.muted, L("nameField")):SetPoint("TOPLEFT", 20, -57)
    root.name = input(root, 398, addon.NameLimit)
    root.name:SetPoint("TOPLEFT", 20, -74)
    root.submit = button(root, L("addTarget"), 104, submit)
    root.submit:SetPoint("LEFT", root.name, "RIGHT", 8, 0)
    root.guild = button(root, L("addGuild"), 104, submitGuild)
    root.guild:SetPoint("LEFT", root.submit, "RIGHT", 8, 0)
    root.cancel = button(root, L("cancel"), 104, function()
        resetForm()
        addon.RefreshUI()
        status(root.status, true, "")
    end)
    root.cancel:SetPoint("LEFT", root.submit, "RIGHT", 8, 0)
    label(root, "GameFontHighlightSmall", color.muted, L("optionalNote")):SetPoint("TOPLEFT", 20, -116)
    root.note = input(root, 622, addon.NoteLimit)
    root.note:SetPoint("TOPLEFT", 20, -133)
    root.name:SetScript("OnEnterPressed", submit)
    root.name:SetScript("OnTextChanged", function(_, userInput)
        if userInput then
            root.prefilledName = nil
            updateAddLabels()
        end
    end)
    root.note:SetScript("OnEnterPressed", submit)
    root.name:SetScript("OnTabPressed", function() root.note:SetFocus() end)
    createFilters(root)

    local list = CreateFrame("Frame", nil, root)
    list:SetPoint("TOPLEFT", 20, -234)
    list:SetPoint("TOPRIGHT", -20, -234)
    list:SetHeight(mainRowCount * (rowHeight + rowGap) + rowGap)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        root.scroll:SetValue(root.scroll:GetValue() - delta)
    end)
    fill(list, color.border, 0, -2)
    fill(list, color.inset, 1, -1)
    root.empty = label(list, "GameFontHighlight", color.muted)
    root.empty:SetPoint("CENTER")
    for index = 1, mainRowCount do
        local row = CreateFrame("Frame", nil, list)
        local y = -rowGap - (index - 1) * (rowHeight + rowGap)
        row:SetPoint("TOPLEFT", 4, y)
        row:SetPoint("TOPRIGHT", -16, y)
        row:SetHeight(rowHeight)
        row.tint = index % 2 == 0 and color.rowAlt or color.row
        row.border = fill(row, color.border, 0, 0)
        row.background = fill(row, row.tint, 1, 1)
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(24, 24)
        row.check:SetPoint("LEFT", 5, 0)
        row.check:SetScript("OnClick", function(self)
            local key = addon.RecordKey(row.entry)
            root.selected[key] = self:GetChecked() and true or nil
            addon.RefreshUI()
        end)
        row.name = label(row, "GameFontHighlight", color.white)
        row.name:SetPoint("TOPLEFT", 34, -4)
        row.name:SetWidth(286)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.note = label(row, "GameFontHighlightSmall", color.muted)
        row.note:SetPoint("TOPLEFT", 34, -17)
        row.note:SetJustifyH("LEFT")
        row.comment = commentPreview(row, row.note, 286, 1, function()
            local entry = row.entry
            local note = entry.note ~= "" and entry.note or L("noNote")
            return note .. "\n\n" .. metadata(entry) .. "\n" .. (lastSeen(entry) or L("neverSeen")), entry.name
        end)
        row.metadata = label(row, "GameFontHighlightSmall", color.muted)
        row.metadata:SetPoint("TOPLEFT", 34, -29)
        row.metadata:SetWidth(286)
        row.metadata:SetJustifyH("LEFT")
        row.metadata:SetWordWrap(false)
        local detail = CreateFrame("Frame", nil, row)
        detail:SetPoint("TOPLEFT", row.metadata, "TOPLEFT")
        detail:SetSize(286, 13)
        detail:EnableMouse(true)
        detail:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:SetText(metadata(row.entry))
            local seen = lastSeen(row.entry)
            if seen then GameTooltip:AddLine(seen, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        detail:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.deaths = label(row, "GameFontNormalLarge", color.gold)
        row.deaths:SetPoint("RIGHT", -183, 0)
        row.priority = button(row, "", 85, function()
            addon.SetPriority(row.entry, not row.entry.high)
        end)
        row.priority:SetPoint("RIGHT", -220, 0)
        local remove = button(row, L("remove"), 75, function()
            local entry = row.entry
            if panel.editing == entry then
                resetForm()
            end
            status(root.status, addon.Delete(entry.name, entry.kind, entry))
        end)
        remove:SetPoint("RIGHT", -7, 0)
        button(row, L("note"), 78, function()
            local entry = row.entry
            panel.editing = entry
            panel.name:SetText(entry.name)
            panel.note:SetText(entry.note)
            addon.RefreshUI()
            panel.note:SetFocus()
        end):SetPoint("RIGHT", remove, "LEFT", -6, 0)
        root.rows[index] = row
    end
    root.scroll = CreateFrame("Slider", nil, list)
    root.scroll:SetPoint("TOPRIGHT", -3, -3)
    root.scroll:SetPoint("BOTTOMRIGHT", -3, 3)
    root.scroll:SetWidth(10)
    root.scroll:SetOrientation("VERTICAL")
    root.scroll:SetMinMaxValues(0, 0)
    root.scroll:SetValueStep(1)
    root.scroll:SetObeyStepOnDrag(true)
    root.scroll:EnableMouse(true)
    fill(root.scroll, color.button, 0, 0)
    local thumb = root.scroll:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(8, 29)
    thumb:SetColorTexture(unpack(color.gold))
    root.scroll:SetThumbTexture(thumb)
    root.scroll:SetScript("OnValueChanged", renderRows)
    root.soundSettings = button(root, L("sounds"), 96, addon.PromptSounds)
    root.soundSettings:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -8)
    local statsButton = button(root, L("statistics"), 110, function() addon.OpenStats() end)
    statsButton:SetPoint("LEFT", root.soundSettings, "RIGHT", 8, 0)
    root.pull = button(root, L("requestWatchlists"), 184, function()
        status(root.status, addon.RequestWatchlists())
    end)
    root.pull:SetPoint("LEFT", statsButton, "RIGHT", 8, 0)
    root.inbox = button(root, L("inboxButton", 0), 184, function() addon.OpenPullInbox() end)
    root.inbox:SetPoint("LEFT", root.pull, "RIGHT", 8, 0)
    root.share = button(root, L("shareWatchlist"), 159, function() addon.PromptShare() end)
    root.share:SetPoint("BOTTOMRIGHT", -20, 18)
    root.clearSelection = button(root, L("clearSelection"), 105, function()
        root.selected = {}
        addon.RefreshUI()
    end)
    root.clearSelection:SetPoint("RIGHT", root.share, "LEFT", -7, 0)
    root.status = label(root, "GameFontHighlightSmall", color.muted)
    root.status:SetPoint("BOTTOMLEFT", 20, 23)
    root.status:SetWidth(340)
    root.status:SetJustifyH("LEFT")
    root.status:SetMaxLines(2)
    root:SetScript("OnShow", addon.RefreshUI)
    root:SetScript("OnHide", function()
        root.name:ClearFocus()
        root.note:ClearFocus()
        root.search:ClearFocus()
    end)
    root:RegisterEvent("PLAYER_TARGET_CHANGED")
    root:SetScript("OnEvent", function(self)
        if self:IsShown() and not self.editing and not manualName() then putTarget() end
    end)
    return root
end

function addon.ToggleUI()
    if not panel then
        panel = createPanel()
    end
    if panel:IsShown() then
        panel:Hide()
        return
    end
    addon.UpdateScope()
    panel:Show()
    if not panel.editing and not manualName() then
        putTarget()
    end
end

local statsPageSize = 7

function addon.RefreshStats()
    if not statsWindow or not statsWindow:IsShown() then return end
    local root = statsWindow
    local tab = root.view or root.selectedTab
    local rows = tab == 7 and addon.SeasonTargets() or addon.StatsRows(tab, root.weekly)
    local season = addon.ActiveSeason()
    local race = tab == 6 or tab == 7
    local title = tab == 5 and "honorJournal" or (race and (tab == 7 and "seasonTargets" or "seasonRace") or "statsTitle")
    root.title:SetText(L(title))
    local pages = math.max(1, math.ceil(#rows / statsPageSize))
    root.page = math.max(1, math.min(root.page, pages))
    for index, row in ipairs(root.rows) do
        local position = (root.page - 1) * statsPageSize + index
        local record = rows[position]
        row.record = record
        row.add:SetShown(record ~= nil and tab == 3)
        row:SetShown(record ~= nil)
        if record and tab == 1 then
            row.name:SetText(record.killer or L("unknownAttacker"))
            row.count:SetText(date("%d.%m %H:%M", record.at))
            local place = record.zone and record.zone ~= "" and record.zone or L("unknownLocation")
            if record.area and record.area ~= "" and record.area ~= place then place = place .. " · " .. record.area end
            if record.x then place = place .. ("  %.1f, %.1f"):format(record.x * 100, record.y * 100) end
            row.detail:SetText(place)
        elseif record and tab == 5 then
            row.name:SetText(record.victim or L("honorUnknownVictim"))
            row.count:SetText("+" .. record.amount)
            row.detail:SetText(date("%d.%m %H:%M", record.at) .. " · " .. L(record.reason)
                .. (record.raced and L("honorRaceSuffix") or ""))
        elseif record and tab == 7 then
            row.name:SetText(record.kind == "G" and L("guildNameLabel", record.name) or record.name)
            row.count:SetText("")
            row.detail:SetText(record.kind == "G" and L("guilds") or L("characters"))
        elseif record then
            row.name:SetText(("%d.  %s"):format(position, record.name))
            row.count:SetText(tostring(record.count))
            local detail = (tab == 2 or tab == 6) and "avengerHonor"
                or (tab == 4 and "avengerKillingBlows" or "enemyKillingBlows")
            row.detail:SetText(L(detail))
        end
    end
    root.empty:SetShown(#rows == 0)
    root.week:SetShown(tab == 2 or tab == 4)
    root.week.label:SetText(root.weekly and L("thisWeek") or L("allTime"))
    root.pagination:SetText(("%d / %d"):format(root.page, pages))
    enabled(root.back, root.page > 1)
    enabled(root.next, root.page < pages)
    root.share:SetChecked(addon.StatsSharing())
    local scope = addon.Scope()
    local inGuild = IsInGuild() and scope ~= nil and scope ~= "local"
    enabled(root.request, inGuild)
    root.request.label:SetText(L(race and "seasonRefresh" or "refreshRankings"))
    root.share:SetEnabled(inGuild)
    root.targets:SetShown(race and season ~= nil)
    root.targets.label:SetText(L(tab == 7 and "seasonRace" or "seasonTargets"))
    root.seasonInfo:SetShown(race)
    root.seasonInfo:SetText(season and L("seasonInfo", season.count) or L("seasonWaiting"))
    root.startSeason:SetShown(race and not season and addon.IsGuildLeaderKey(addon.UnitName("player")))
end

local function createStats()
    local root = window("GuildAvengerStats", 540, 596, "FULLSCREEN_DIALOG")
    root.page, root.rows, root.Tabs = 1, {}, {}
    root.minTabWidth = 100
    tinsert(UISpecialFrames, "GuildAvengerStats")
    root.title = label(root, "GameFontNormalLarge", color.gold, L("statsTitle"))
    root.title:SetPoint("TOPLEFT", 20, -18)
    local close = CreateFrame("Button", nil, root, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() root:Hide() end)
    local titles = { L("myDeaths"), L("avengers"), L("enemies"), L("killingBlows") }
    for index, title in ipairs(titles) do
        local tab = CreateFrame("Button", nil, root, "PanelTopTabButtonTemplate")
        root.Tabs[index] = tab
        tab:SetID(index)
        tab:SetText(title)
        tab:SetScript("OnClick", function(self)
            PanelTemplates_SetTab(root, self:GetID())
            root.page, root.view = 1, nil
            addon.RefreshStats()
        end)
    end
    root.Tabs[1]:SetPoint("TOPLEFT", 20, -50)
    PanelTemplates_SetNumTabs(root, #titles)
    PanelTemplates_SetTab(root, 1)
    local list = CreateFrame("Frame", nil, root)
    list:SetPoint("TOPLEFT", 20, -87)
    list:SetPoint("TOPRIGHT", -20, -87)
    list:SetHeight(statsPageSize * 44 + 4)
    fill(list, color.inset, 0, 0)
    root.empty = label(list, "GameFontHighlight", color.muted, L("noStats"))
    root.empty:SetPoint("CENTER")
    for index = 1, statsPageSize do
        local row = CreateFrame("Frame", nil, list)
        row:SetPoint("TOPLEFT", 2, -2 - (index - 1) * 44)
        row:SetPoint("TOPRIGHT", -2, -2 - (index - 1) * 44)
        row:SetHeight(42)
        styleRow(row, index)
        row.name = label(row, "GameFontHighlight", color.white)
        row.name:SetPoint("TOPLEFT", 10, -5)
        row.name:SetWidth(326)
        row.name:SetJustifyH("LEFT")
        row.name:SetMaxLines(1)
        row.detail = label(row, "GameFontHighlightSmall", color.muted)
        row.detail:SetPoint("TOPLEFT", 10, -23)
        row.detail:SetWidth(476)
        row.detail:SetJustifyH("LEFT")
        row.detail:SetMaxLines(1)
        row.count = label(row, "GameFontNormalLarge", color.gold)
        row.count:SetPoint("TOPRIGHT", -10, -6)
        row.add = button(row, L("addFromRankings"), 83, function()
            local ok, message = addon.AddRankedEnemy(row.record.guid)
            status(root.status, ok, message)
        end)
        row.add:SetPoint("RIGHT", -61, -3)
        row.add:SetHeight(22)
        row.add:Hide()
        root.rows[index] = row
    end
    root.week = button(root, L("allTime"), 120, function()
        root.weekly = not root.weekly
        root.page = 1
        addon.RefreshStats()
    end)
    root.week:SetPoint("TOPRIGHT", -20, -407)
    root.back = button(root, L("previous"), 73, function() root.page = root.page - 1; addon.RefreshStats() end)
    root.back:SetPoint("TOPLEFT", 20, -407)
    root.pagination = label(root, "GameFontHighlightSmall", color.muted)
    root.pagination:SetPoint("LEFT", root.back, "RIGHT", 8, 0)
    root.next = button(root, L("next"), 73, function() root.page = root.page + 1; addon.RefreshStats() end)
    root.next:SetPoint("TOPLEFT", 149, -407)
    root.share = checkbox(root, 20, -445, L("shareStats"))
    root.share:SetScript("OnClick", function(self) addon.SetStatsSharing(self:GetChecked()) end)
    root.request = button(root, L("refreshRankings"), 138, function()
        if root.view == 6 or root.view == 7 then
            status(root.status, addon.RequestSeason())
        else
            root.status:SetText(addon.RequestStats())
        end
    end)
    root.request:SetPoint("TOPRIGHT", -20, -442)
    root.status = label(root, "GameFontHighlightSmall", color.muted, L("statsPrivacy"))
    root.status:SetPoint("BOTTOMLEFT", 20, 23)
    root.status:SetWidth(500)
    root.status:SetJustifyH("LEFT")
    root.status:SetMaxLines(2)
    local function openView(view)
        root.view, root.page = view, 1
        addon.RefreshStats()
    end
    local history = button(root, L("honorJournal"), 145, function() openView(5) end)
    history:SetPoint("TOPLEFT", 20, -480)
    local race = button(root, L("seasonRace"), 151, function() openView(6) end)
    race:SetPoint("LEFT", history, "RIGHT", 8, 0)
    root.targets = button(root, L("seasonTargets"), 150, function()
        openView(root.view == 7 and 6 or 7)
    end)
    root.targets:SetPoint("LEFT", race, "RIGHT", 8, 0)
    root.seasonInfo = label(root, "GameFontHighlightSmall", color.muted)
    root.seasonInfo:SetPoint("TOPLEFT", 20, -522)
    root.seasonInfo:SetWidth(340)
    root.seasonInfo:SetJustifyH("LEFT")
    root.seasonInfo:SetMaxLines(2)
    root.startSeason = button(root, L("seasonStart"), 145, function() addon.PromptSeason() end)
    root.startSeason:SetPoint("TOPRIGHT", -20, -516)
    return root
end

function addon.OpenStats()
    if not statsWindow then statsWindow = createStats() end
    statsWindow:Show()
    addon.RefreshRoster()
    addon.RefreshStats()
end

function addon.InitMinimap()
    if minimapButton or not Minimap then return end
    local root = CreateFrame("Button", "GuildAvengerMinimapButton", Minimap)
    minimapButton = root
    root:SetSize(30, 30)
    root:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    root:RegisterForClicks("LeftButtonUp")
    root:RegisterForDrag("LeftButton")
    local icon = root:CreateTexture(nil, "ARTWORK")
    icon:SetSize(25, 25)
    icon:SetPoint("CENTER")
    icon:SetTexture(bookIcon)
    local mask = maskCircle(root, icon)
    local highlight = root:CreateTexture()
    highlight:SetAllPoints(icon)
    highlight:SetColorTexture(1, 1, 1, 0.24)
    highlight:AddMaskTexture(mask)
    root:SetHighlightTexture(highlight)

    local angle = GuildAvengerDB.minimapAngle or math.rad(225)
    local function place()
        root:ClearAllPoints()
        root:SetPoint("CENTER", Minimap, "CENTER",
            math.cos(angle) * Minimap:GetWidth() / 2, math.sin(angle) * Minimap:GetHeight() / 2)
    end
    local dragged
    root:SetScript("OnMouseDown", function() dragged = false end)
    root:SetScript("OnClick", function()
        if not dragged then addon.ToggleUI() end
    end)
    root:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Guild Avenger")
        GameTooltip:AddLine(L("minimapTooltip"), 1, 1, 1)
        GameTooltip:Show()
    end)
    root:SetScript("OnLeave", function() GameTooltip:Hide() end)
    root:SetScript("OnDragStart", function(self)
        dragged = true
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local x, y = Minimap:GetCenter()
            if not x or not y then return end
            local cursorX, cursorY = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            angle = math.atan2(cursorY / scale - y, cursorX / scale - x)
            place()
        end)
    end)
    root:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        GuildAvengerDB.minimapAngle = angle
    end)
    Minimap:HookScript("OnSizeChanged", place)
    place()
end

local function promptLink(url, title, description)
    if not download then
        local root = window("GuildAvengerDownload", 520, 158, "FULLSCREEN_DIALOG")
        root:SetFrameLevel(30)
        tinsert(UISpecialFrames, "GuildAvengerDownload")
        root.title = label(root, "GameFontNormalLarge", color.gold)
        root.title:SetPoint("TOPLEFT", 18, -15)
        root.description = label(root, "GameFontHighlight", color.white)
        root.description:SetPoint("TOPLEFT", 18, -43)
        root.description:SetWidth(484)
        root.description:SetJustifyH("LEFT")
        root.field = input(root, 484, 200)
        root.field:SetPoint("TOPLEFT", 18, -79)
        root.field:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        root.field:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        label(root, "GameFontHighlightSmall", color.muted, L("copyLink")):SetPoint("BOTTOMLEFT", 18, 21)
        button(root, L("close"), 90, function() root:Hide() end):SetPoint("BOTTOMRIGHT", -18, 13)
        root:SetScript("OnHide", function()
            root.field:ClearFocus()
            root.field:SetText("")
        end)
        download = root
    end
    download.title:SetText(title)
    download.description:SetText(description)
    download.field:SetMaxBytes(#url)
    download.field:SetText(url)
    download:Show()
    download.field:SetFocus()
    download.field:HighlightText()
end

function addon.PromptDownload(url, description)
    promptLink(url, L("downloadTitle"), description)
end

local function issueParameter(text)
    return (text:gsub("([^A-Za-z0-9_.~%-])", function(byte)
        return ("%%%02X"):format(byte:byte())
    end))
end

function addon.PromptBugReport()
    if not bugReport then
        local root = window("GuildAvengerBugReport", 520, 270, "FULLSCREEN_DIALOG")
        root:SetFrameLevel(31)
        tinsert(UISpecialFrames, "GuildAvengerBugReport")
        label(root, "GameFontNormalLarge", color.gold, L("reportBug")):SetPoint("TOPLEFT", 18, -15)
        local instructions = label(root, "GameFontHighlight", color.white, L("bugReportHint"))
        instructions:SetPoint("TOPLEFT", 18, -43)
        instructions:SetWidth(484)
        instructions:SetJustifyH("LEFT")

        local scroll = CreateFrame("ScrollFrame", nil, root, "ScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -97)
        scroll:SetSize(468, 127)
        fill(scroll, color.border, 0, -2)
        fill(scroll, color.inset, 1, -1)
        local field = CreateFrame("EditBox", nil, scroll)
        root.field = field
        field:SetSize(468, 127)
        field:SetFontObject(GameFontHighlight)
        field:SetAutoFocus(false)
        field:SetMultiLine(true)
        field:SetMaxBytes(600)
        field:SetTextInsets(8, 8, 6, 6)
        field:EnableMouse(true)
        scroll:SetScrollChild(field)
        ScrollingEdit_OnLoad(field)
        field:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
        field:SetScript("OnEscapePressed", function() root:Hide() end)

        local function comment()
            return field:GetText():match("^%s*(.-)%s*$")
        end
        local send = button(root, L("send"), 118, function()
            local text = comment()
            if text == "" then return end
            local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
            local body = "Guild Avenger version: " .. version .. "\n\n" .. text
            local url = "https://github.com/DunkleCthulhu/guild-avenger/issues/new?title=Guild%20Avenger%20bug%20report"
                .. "&body=" .. issueParameter(body)
            root:Hide()
            promptLink(url, L("reportBug"), L("bugReportLinkHint"))
        end)
        send:SetPoint("BOTTOMRIGHT", -18, 13)
        button(root, L("cancel"), 100, function() root:Hide() end):SetPoint("RIGHT", send, "LEFT", -8, 0)
        field:SetScript("OnTextChanged", function(self)
            ScrollingEdit_OnTextChanged(self, scroll)
            enabled(send, comment() ~= "")
        end)
        root:SetScript("OnHide", function()
            field:ClearFocus()
            field:SetText("")
        end)
        enabled(send, false)
        bugReport = root
    end
    bugReport:Show()
    bugReport.field:SetFocus()
end

local presentOffer
function addon.RefreshSuggestions()
    if not dialog or not dialog:IsShown() or not dialog.autocomplete then
        return
    end
    local matches = addon.SuggestRecipients(dialog.field:GetText())
    for index, control in ipairs(dialog.suggestions) do
        control.name = matches[index]
        control:SetShown(control.name ~= nil and control.name ~= dialog.field:GetText())
        control.label:SetText(control.name or "")
    end
end

local function submitDialog()
    local action = dialog.action
    if not action then
        return
    end
    local ok, message = action(dialog.field:GetText())
    if ok then
        dialog:Hide()
        if message then addon.Say(message) end
    else
        status(dialog.status, false, message)
    end
end

local function createDialog()
    local root = window("GuildAvengerDialog", 428, 190, "FULLSCREEN_DIALOG")
    tinsert(UISpecialFrames, "GuildAvengerDialog")
    root.title = label(root, "GameFontNormalLarge", color.gold)
    root.title:SetPoint("TOPLEFT", 18, -15)
    root.text = label(root, "GameFontHighlight", color.white)
    root.text:SetPoint("TOPLEFT", 18, -45)
    root.text:SetWidth(392)
    root.text:SetJustifyH("LEFT")
    root.text:SetMaxLines(3)
    root.field = input(root, 392, addon.NoteLimit)
    root.field:SetPoint("TOPLEFT", 18, -85)
    root.field:SetScript("OnEnterPressed", submitDialog)
    root.field:SetScript("OnTextChanged", addon.RefreshSuggestions)
    root.field:SetScript("OnTabPressed", function(self)
        local first = root.suggestions[1]
        if root.autocomplete and first:IsShown() then self:SetText(first.name) end
    end)
    root.suggestions = {}
    for index = 1, 5 do
        local choice = button(root, "", 392, function(self)
            root.field:SetText(self.name)
            root.field:SetFocus()
        end)
        choice:SetPoint("TOPLEFT", 18, -122 - (index - 1) * 29)
        root.suggestions[index] = choice
    end
    root.status = label(root, "GameFontHighlightSmall", color.red)
    root.status:SetPoint("TOPLEFT", 18, -118)
    root.status:SetWidth(392)
    root.status:SetJustifyH("LEFT")
    root.status:SetMaxLines(2)
    root.confirm = button(root, "", 98, submitDialog)
    root.confirm:SetPoint("BOTTOMRIGHT", -18, 13)
    root.cancel = button(root, "", 98, function() root:Hide() end)
    root.cancel:SetPoint("RIGHT", root.confirm, "LEFT", -7, 0)
    root.publish = button(root, L("postInGuildChat"), 125, function()
        local ok, message = root.publishAction()
        if ok then
            root:Hide()
            addon.Say(message)
        else
            status(root.status, false, message)
        end
    end)
    root.publish:SetPoint("BOTTOMLEFT", 18, 13)
    root.revoke = button(root, L("revokeWatchlistLinks"), 175, function()
        status(root.status, addon.RevokeWatchlistLinks())
        enabled(root.revoke, false)
    end)
    root.revoke:SetPoint("BOTTOMLEFT", 18, 48)
    root.removals = checkbox(root, 18, -309, L("suggestRemovals"))
    root:SetScript("OnHide", function()
        root.action = nil
        root.publishAction = nil
        root.field:ClearFocus()
        C_Timer.After(0, presentOffer)
    end)
    return root
end

local function openDialog(options)
    if not dialog then
        dialog = createDialog()
    end
    if dialog:IsShown() or (review and review:IsShown()) then
        return false
    end
    dialog.title:SetText(options.title)
    dialog.text:SetText(options.text)
    dialog.confirm.label:SetText(options.confirm)
    dialog.cancel.label:SetText(options.cancel or L("cancel"))
    dialog.autocomplete = options.autocomplete
    dialog:SetHeight(options.autocomplete and (options.removals and 407 or 381) or 190)
    dialog.status:ClearAllPoints()
    dialog.status:SetPoint("TOPLEFT", 18, options.autocomplete and -278 or -118)
    dialog.publish:SetShown(options.autocomplete == true)
    dialog.revoke:SetShown(options.autocomplete == true)
    enabled(dialog.revoke, options.autocomplete == true and addon.HasWatchlistLinks())
    dialog.removals:SetShown(options.removals == true)
    dialog.removals:SetChecked(false)
    for _, choice in ipairs(dialog.suggestions) do
        choice:Hide()
    end
    dialog.field:SetShown(options.limit ~= nil)
    dialog.field:SetMaxBytes(options.limit or addon.NoteLimit)
    dialog.field:SetText(options.value or "")
    status(dialog.status, true, "")
    dialog.action = options.action
    dialog.publishAction = options.publishAction
    dialog:Show()
    addon.RefreshSuggestions()
    if options.limit then
        dialog.field:SetFocus()
    end
    return true
end

function addon.PromptSeason()
    local scope = addon.Scope()
    local selection
    if panel and panel.scope == scope and next(panel.selected) then
        selection = {}
        for key in pairs(panel.selected) do selection[key] = true end
    end
    openDialog({
        title = L("seasonStart"),
        text = L(selection and "seasonConfirmSelection" or "seasonConfirmAll"),
        confirm = L("start"),
        action = function()
            if not addon.UpdateScope() or addon.Scope() ~= scope then return false, L("guildChanged") end
            return addon.StartSeason(selection)
        end,
    })
end

confirmBulkRemoval = function()
    local selection, scope = {}, addon.Scope()
    for _, entry in ipairs(addon.Entries()) do
        local key = addon.RecordKey(entry)
        if panel.selected[key] then selection[key] = entry end
    end
    local count = selectionSize(selection)
    if count == 0 then return end
    openDialog({
        title = L("confirmBulkRemove"),
        text = L("bulkRemoveDescription", count),
        confirm = L("remove"),
        action = function()
            local removed = addon.DeleteSelection(selection, scope)
            return removed > 0, removed > 0 and L("removedCount", removed) or L("selectionChanged")
        end,
    })
end

submitGuild = function()
    local name, note = manualName(), panel.note:GetText()
    if name then
        local ok, message = addon.Add(name, note, nil, "G")
        finishForm(ok, message, name, "G")
        return
    end
    local _, targetGuild = addon.EnemyEntry("target", "G")
    if targetGuild then
        local ok, message = addon.Add("", note, "target", "G")
        finishForm(ok, message, targetGuild, "G")
        return
    end
    openDialog({
        title = L("addGuildManually"),
        text = L("guildName"),
        limit = addon.NameLimit, confirm = L("add"),
        action = function(guild)
            if not guild:match("%S") then return false, L("enterGuildName") end
            local ok, message = addon.Add(guild, note, nil, "G")
            if ok then finishForm(ok, message, guild, "G") end
            return ok, message
        end,
    })
end

function addon.PromptShare()
    addon.UpdateScope()
    local scope = addon.Scope()
    local selection
    if panel and panel.scope == scope and next(panel.selected) then
        selection = {}
        for key in pairs(panel.selected) do selection[key] = true end
    end
    local function send(action, input)
        if not addon.UpdateScope() or addon.Scope() ~= scope then
            return false, L("guildChanged")
        end
        local removals = dialog.removals:IsShown() and dialog.removals:GetChecked()
        if input then return action(input, selection, removals) end
        return action(selection, removals)
    end
    addon.RefreshRoster()
    local target = addon.ShareTargetName()
    openDialog({
        title = L("shareWatchlist"),
        text = (selection and L("selectedCount", selectionSize(selection)) or L("entireWatchlist"))
            .. "\n" .. L("guildmateFullName"),
        value = target, limit = addon.NameLimit + 64, confirm = L("send"), autocomplete = true,
        removals = not selection and scope ~= nil and scope ~= "local" and #addon.RemovalProposals() > 0,
        action = function(input) return send(addon.Share, input) end,
        publishAction = function() return send(addon.Publish) end,
    })
end

function addon.PromptGuild(unit)
    local _, name = addon.EnemyEntry(unit, "G")
    if not name then
        local message = L("targetGuildNotVisible")
        if panel and panel:IsShown() then
            status(panel.status, false, message)
        else
            addon.Say(message)
        end
        return
    end
    openDialog({
        title = L("addGuildToWatchlist"),
        text = name .. "\n" .. L("optionalNote"),
        limit = addon.NoteLimit, confirm = L("add"),
        action = function(note) return addon.Add(name, note, unit, "G") end,
    })
end

local function renderReview()
    local offer = review.offer
    if not offer then
        return
    end
    local offset = math.floor(review.scroll:GetValue())
    for index, row in ipairs(review.rows) do
        local change = offer.changes[offset + index]
        row.change = change
        row:SetShown(change ~= nil)
        if change then
            local record = change.record
            row.check:SetChecked(offer.selected[change.key] == true)
            local title = record.kind == "G" and L("guildNameLabel", record.name) or record.name
            row.name:SetText((change.new and "+ " or change.removed and "− " or "") .. title)
            local priority = record.high and L("high") or L("normal")
            row.priority:SetText(change.removed and L("remove") or
                (change.changedPriority and (record.high and "↑ " or "↓ ") .. priority) or
                (change.higherPriority and L("promotePriority")) or priority)
            row.priority:SetTextColor(unpack(change.removed and color.red or record.high and color.gold or color.muted))
            local note = record.note ~= "" and record.note or L("noNote")
            row.detail:SetText(change.changedNote and L("proposedNote", note) or note)
            local choices = change.variants and #change.variants or 0
            row.variants:SetShown(choices > 1)
            row.variants.label:SetText(L("noteVariants", choices))
            row.detail:SetWidth(choices > 1 and 302 or 388)
            row.comment:SetWidth(choices > 1 and 319 or 405)
            row.comment:SetShown(record.note ~= "" or change.changedNote == true or change.sources ~= nil)
            local author = change.sources and L("replyAuthors", change.sources)
                or (record.author ~= "" and record.author or L("unknownAuthor"))
            row.author:SetText(author
                .. (record.deaths > 0 and L("deathCountSuffix", record.deaths) or ""))
        end
    end
    local selected = selectionSize(offer.selected)
    review.count:SetText(L("reviewCount", selected, #offer.changes))
    enabled(review.confirm, selected > 0 or (offer.replyCount ~= nil and #offer.changes == 0))
end

local function selectAll(value, additionsAndCountsOnly)
    local offer = review.offer
    for _, change in ipairs(offer.changes) do
        local modifiesRecord = change.removed or change.changedNote or change.changedPriority
        offer.selected[change.key] = value and (not additionsAndCountsOnly or not modifiesRecord) and true or nil
    end
    renderReview()
end

local function createReview()
    local root = window("GuildAvengerReview", 516, 560, "FULLSCREEN_DIALOG")
    local reviewRowHeight = 52
    root.rows = {}
    tinsert(UISpecialFrames, "GuildAvengerReview")
    label(root, "GameFontNormalLarge", color.gold, L("importTitle")):SetPoint("TOPLEFT", 18, -15)
    root.sender = label(root, "GameFontHighlight", color.white)
    root.sender:SetPoint("TOPLEFT", 18, -43)
    root.summary = label(root, "GameFontHighlightSmall", color.muted)
    root.summary:SetPoint("TOPLEFT", 18, -64)
    local list = CreateFrame("Frame", nil, root)
    list:SetPoint("TOPLEFT", 18, -91)
    list:SetPoint("TOPRIGHT", -18, -91)
    list:SetHeight(rowCount * reviewRowHeight + 4)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        root.scroll:SetValue(root.scroll:GetValue() - delta)
    end)
    fill(list, color.inset, 0, 0)
    root.empty = label(list, "GameFontHighlight", color.muted, L("importEmpty"))
    root.empty:SetPoint("CENTER")
    for index = 1, rowCount do
        local row = CreateFrame("Frame", nil, list)
        row:SetPoint("TOPLEFT", 2, -2 - (index - 1) * reviewRowHeight)
        row:SetPoint("TOPRIGHT", -17, -2 - (index - 1) * reviewRowHeight)
        row:SetHeight(reviewRowHeight - 1)
        styleRow(row, index)
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(26, 26)
        row.check:SetPoint("LEFT", 4, 0)
        row.check:SetScript("OnClick", function(self)
            root.offer.selected[row.change.key] = self:GetChecked() and true or nil
            renderReview()
        end)
        row.name = label(row, "GameFontHighlight", color.white)
        row.name:SetPoint("TOPLEFT", 36, -6)
        row.name:SetWidth(324)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.priority = label(row, "GameFontHighlightSmall", color.gold)
        row.priority:SetPoint("TOPRIGHT", -9, -7)
        row.detail = label(row, "GameFontHighlightSmall", color.muted)
        row.detail:SetPoint("TOPLEFT", 36, -22)
        row.detail:SetJustifyH("LEFT")
        row.comment = commentPreview(row, row.detail, 405, 1, function()
            local change = row.change
            local note = change.record.note
            if change.changedNote then
                local before = change.oldNote ~= "" and change.oldNote or L("noNote")
                note = L("noteChange", before, note ~= "" and note or L("noNote"))
            end
            if change.sources then note = note .. "\n\n" .. L("replyAuthors", change.sources) end
            return note, change.record.name
        end)
        row.variants = button(row, "", 95, function(self)
            local change = row.change
            local function choose(variant)
                change.record.note = variant.note
                change.changedNote = change.previous ~= nil and variant.note ~= change.oldNote
                root.offer.selected[change.key] = true
                renderReview()
            end
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(self, function(_, menu)
                    for _, variant in ipairs(change.variants) do
                        local name = variant.note ~= "" and variant.note or L("noNote")
                        menu:CreateRadio(name .. " · " .. variant.authors,
                            function(item) return item.note == change.record.note end, choose, variant)
                    end
                end)
            else
                for index, variant in ipairs(change.variants) do
                    if variant.note == change.record.note then
                        choose(change.variants[index % #change.variants + 1])
                        break
                    end
                end
            end
        end)
        row.variants:SetPoint("TOPRIGHT", -7, -23)
        row.variants:SetHeight(23)
        row.author = label(row, "GameFontHighlightSmall", color.muted)
        row.author:SetPoint("TOPLEFT", 36, -36)
        row.author:SetWidth(405)
        row.author:SetJustifyH("LEFT")
        row.author:SetWordWrap(false)
        root.rows[index] = row
    end
    root.scroll = CreateFrame("Slider", nil, list)
    root.scroll:SetPoint("TOPRIGHT", -3, -3)
    root.scroll:SetPoint("BOTTOMRIGHT", -3, 3)
    root.scroll:SetWidth(10)
    root.scroll:SetOrientation("VERTICAL")
    root.scroll:SetValueStep(1)
    root.scroll:SetObeyStepOnDrag(true)
    root.scroll:EnableMouse(true)
    fill(root.scroll, color.button, 0, 0)
    local thumb = root.scroll:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(8, 29)
    thumb:SetColorTexture(unpack(color.gold))
    root.scroll:SetThumbTexture(thumb)
    root.scroll:SetScript("OnValueChanged", renderReview)
    root.count = label(root, "GameFontHighlightSmall", color.muted)
    root.count:SetPoint("TOPLEFT", 18, -470)
    root.selectNew = button(root, L("selectAllNew"), 145, function()
        for _, change in ipairs(root.offer.changes) do
            if change.new then root.offer.selected[change.key] = true end
        end
        renderReview()
    end)
    root.selectNew:SetPoint("TOPRIGHT", -18, -462)
    button(root, L("selectAll"), 110, function() selectAll(true) end):SetPoint("BOTTOMLEFT", 18, 15)
    button(root, L("clearAll"), 83, function() selectAll(false) end):SetPoint("BOTTOMLEFT", 135, 15)
    root.confirm = button(root, L("accept"), 102, function()
        local offer = root.offer
        local selected = {}
        for _, change in ipairs(offer.changes) do
            if offer.selected[change.key] then
                selected[change.key] = change.proposal or change.record
            end
        end
        root:Hide()
        offer.accept(selected)
    end)
    root.confirm:SetPoint("BOTTOMRIGHT", -18, 15)
    root.cancel = button(root, L("decline"), 102, function() root:Hide() end)
    root.cancel:SetPoint("RIGHT", root.confirm, "LEFT", -7, 0)
    root:SetScript("OnHide", function()
        root.offer = nil
        C_Timer.After(0, presentOffer)
    end)
    return root
end

local function showReview(offer)
    if not review then review = createReview() end
    table.sort(offer.changes, function(left, right) return left.record.name < right.record.name end)
    offer.selected = {}
    review.offer = offer
    review.sender:SetText(offer.replyCount and L("inboxSenders", offer.replyCount) or L("sender", offer.sender))
    review.summary:SetText(L("reviewSummary", offer.added, offer.updated, offer.removed or 0))
    review.selectNew:SetShown(offer.replyCount ~= nil)
    review.confirm.label:SetText(L(offer.replyCount and #offer.changes == 0 and "done" or "accept"))
    review.cancel.label:SetText(L(offer.replyCount and "close" or "decline"))
    review.empty:SetShown(#offer.changes == 0)
    local maximum = math.max(0, #offer.changes - rowCount)
    review.scroll:SetMinMaxValues(0, maximum)
    review.scroll:SetValue(0)
    review.scroll:SetShown(maximum > 0)
    selectAll(true, true)
    review:Show()
end

presentOffer = function()
    if (dialog and dialog:IsShown()) or (review and review:IsShown()) then return end
    while #offers > 0 do
        local queued = table.remove(offers, 1)
        local offer = queued.preview()
        if offer then
            offer.sender = queued.sender
            showReview(offer)
            return
        end
    end
end

function addon.OpenPullInbox()
    if (dialog and dialog:IsShown()) or (review and review:IsShown()) then return end
    local offer = addon.PreviewInbox()
    if offer then showReview(offer) end
end

function addon.OfferImport(sender, preview)
    if #offers >= 10 then return end
    offers[#offers + 1] = {sender = sender, preview = preview}
    presentOffer()
end

local menusRegistered
function addon.InitMenus()
    if menusRegistered or not Menu or not Menu.ModifyMenu then
        return
    end
    menusRegistered = true
    local function addMenuEntry(_, rootDescription, context)
        local unit = context and context.unit
        if not addon.IsText(unit) or (unit ~= "target" and unit ~= "focus") then
            return
        end
        local _, name = addon.EnemyUnit(unit)
        if name then
            rootDescription:CreateButton(L("addToWatchlist"), function()
                openDialog({
                    title = L("addToWatchlist"),
                    text = name .. "\n" .. L("optionalNote"),
                    limit = addon.NoteLimit, confirm = L("add"),
                    action = function(note) return addon.Add(name, note, unit) end,
                })
            end)
            if addon.EnemyEntry(unit, "G") then
                rootDescription:CreateButton(L("addGuildToWatchlist"), function() addon.PromptGuild(unit) end)
            end
        end
    end
    for _, tag in ipairs({ "MENU_UNIT_PLAYER", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS" }) do
        Menu.ModifyMenu(tag, addMenuEntry)
    end
end

local alertName, portraitUnit, expiration, targetButton, pingButton
local alertMoving = false
local alertWidth, alertHeight, alertAlpha = 320, 92, 0.84
local alertBorder = { 0.88, 0.85, 0.76, 1 }
local urgentBorder = { 1, 0.70, 0.36, 1 }

local function secured(labelText, width)
    local control = button(UIParent, labelText, width, nil,
        "UIPanelButtonTemplate,SecureActionButtonTemplate,SecureHandlerStateTemplate")
    control:SetHeight(23)
    control:SetAlpha(alertAlpha)
    control:SetFrameStrata("HIGH")
    control:SetFrameLevel(toast:GetFrameLevel() + 4)
    control:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    control:SetAttribute("_onstate-guildavengercombat", [[
        if newstate == "combat" then self:Hide() end
    ]])
    RegisterStateDriver(control, "guildavengercombat", "[combat] combat; safe")
    return control
end

local function positionAlertButton(control, x, y)
    control:ClearAllPoints()
    control:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
end

local function refreshAlertButtons()
    if InCombatLockdown() then
        return
    end
    local left, bottom = toast:GetLeft(), toast:GetBottom()
    if not alertName or alertMoving or not left or not bottom then
        if targetButton then
            targetButton:Hide()
            if pingButton then
                pingButton:Hide()
            end
        end
        return
    end
    if not targetButton then
        -- Siblings keep the visual alert dismissible while protected buttons are locked.
        targetButton = secured(L("target"), 70)
        targetButton:SetAttribute("type", "macro")
        if C_Ping and C_Ping.IsPingSystemEnabled then
            pingButton = secured(L("dangerPing"), 132)
            pingButton:SetAttribute("type", "macro")
            -- The numeric Warning option works in any client language.
            pingButton:SetAttribute("macrotext", "/ping [@target,harm,nodead] 2")
        end
    end
    local right = left - UIParent:GetLeft() + alertWidth
    local y = bottom - UIParent:GetBottom() + 8
    positionAlertButton(targetButton, right - 218, y)
    targetButton:SetAttribute("macrotext", "/targetexact " .. alertName)
    targetButton:Show()
    if pingButton then
        positionAlertButton(pingButton, right - 141, y)
        local key = addon.PlayerName(alertName)
        pingButton:SetShown(C_Ping.IsPingSystemEnabled() and key ~= nil and key == addon.EnemyUnit("target"))
    end
end

local function cancelAlertTimer()
    if expiration then
        expiration:Cancel()
        expiration = nil
    end
end

function addon.CloseAlert()
    alertName, portraitUnit = nil, nil
    cancelAlertTimer()
    if toast then
        toast:Hide()
        refreshAlertButtons()
    end
end

local function refreshAlertPortrait()
    if not portraitUnit or not SetPortraitTexture then
        return
    end
    if alertName and addon.UnitName(portraitUnit) ~= addon.PlayerName(alertName) then
        return
    end
    local ready = not IsUnitModelReadyForUI or IsUnitModelReadyForUI(portraitUnit)
    if addon.Ordinary(ready) and ready then
        SetPortraitTexture(toast.portrait, portraitUnit, true)
    end
end

local function positionAlert(root)
    local saved = GuildAvengerDB.alertPosition
    root:ClearAllPoints()
    if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number" then
        root:SetPoint("CENTER", UIParent, "BOTTOMLEFT", saved.x * UIParent:GetWidth(), saved.y * UIParent:GetHeight())
    else
        root:SetPoint("TOP", UIParent, "TOP", 0, -42)
    end
end

local function createAlert()
    local root = window("GuildAvengerAlert", alertWidth, alertHeight, "HIGH")
    positionAlert(root)
    root:SetAlpha(alertAlpha)
    root:SetBackdropColor(0.40, 0.34, 0.28, 0.98)
    root:SetMovable(true)
    root:RegisterForDrag("LeftButton")
    root:SetScript("OnDragStart", function(self)
        alertMoving = true
        cancelAlertTimer()
        refreshAlertButtons()
        self:StartMoving()
    end)
    root:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        alertMoving = false
        local x, y = self:GetCenter()
        GuildAvengerDB.alertPosition = {
            x = (x - UIParent:GetLeft()) / UIParent:GetWidth(),
            y = (y - UIParent:GetBottom()) / UIParent:GetHeight(),
        }
        positionAlert(self)
        refreshAlertButtons()
        expiration = C_Timer.NewTimer(12, addon.CloseAlert)
    end)
    root.portrait = root:CreateTexture(nil, "ARTWORK")
    root.portrait:SetPoint("TOPLEFT", 16, -15)
    root.portrait:SetSize(40, 40)
    maskCircle(root, root.portrait)
    local portraitFrame = root:CreateTexture(nil, "OVERLAY")
    portraitFrame:SetAtlas("UI-Frame-Portrait", false)
    portraitFrame:SetPoint("CENTER", root.portrait)
    portraitFrame:SetSize(51, 51)
    root.name = label(root, "GameFontNormalLarge", color.gold)
    root.name:SetPoint("TOPLEFT", 67, -13)
    root.name:SetWidth(221)
    root.name:SetJustifyH("LEFT")
    root.name:SetWordWrap(false)
    root.note = label(root, "GameFontHighlight", color.white)
    root.note:SetPoint("TOPLEFT", 67, -34)
    root.note:SetJustifyH("LEFT")
    root.comment = commentPreview(root, root.note, 236, 2)
    local divider = root:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 67, -59)
    divider:SetPoint("TOPRIGHT", -15, -59)
    divider:SetHeight(1)
    divider:SetColorTexture(0.66, 0.49, 0.25, 0.55)
    root.priority = label(root, "GameFontHighlightSmall", color.gold, L("high"))
    root.priority:SetPoint("BOTTOMLEFT", 15, 14)
    local close = CreateFrame("Button", nil, root, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", addon.CloseAlert)
    root:RegisterEvent("PLAYER_REGEN_ENABLED")
    root:RegisterEvent("PLAYER_TARGET_CHANGED")
    root:RegisterEvent("DISPLAY_SIZE_CHANGED")
    root:RegisterEvent("UI_SCALE_CHANGED")
    root:RegisterEvent("UNIT_PORTRAIT_UPDATE")
    root:RegisterEvent("PORTRAITS_UPDATED")
    root:SetScript("OnEvent", function(self, event, unit)
        if event == "UNIT_PORTRAIT_UPDATE" or event == "PORTRAITS_UPDATED" then
            if event == "PORTRAITS_UPDATED" or (addon.IsText(unit) and unit == portraitUnit) then
                refreshAlertPortrait()
            end
            return
        end
        if not alertMoving and (event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED") then
            positionAlert(self)
        end
        refreshAlertButtons()
    end)
    return root
end

function addon.ShowAlert(entry, preview)
    if not preview and not entry.high and toast and toast:IsShown() and toast.high then return end
    if not toast then
        toast = createAlert()
    end
    cancelAlertTimer()
    alertName = not preview and not entry.grouped and entry.name or nil
    portraitUnit = entry.unit
    toast.high = entry.high
    toast.portrait:SetTexture(entry.grouped and bookIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
    refreshAlertPortrait()
    toast.name:SetText(entry.name)
    toast:SetBackdropBorderColor(unpack(entry.high and urgentBorder or alertBorder))
    toast.note:SetText(entry.note)
    toast.comment:SetShown(entry.note ~= "")
    toast.priority:SetShown(entry.high == true)
    toast:Show()
    refreshAlertButtons()
    local sound = GuildAvengerDB.sound
    if preview or (sound[entry.kind] ~= false and (not sound.highOnly or entry.high)) then
        playAlertSound(entry.high)
    end
    if not alertMoving then
        expiration = C_Timer.NewTimer(12, addon.CloseAlert)
    end
end
