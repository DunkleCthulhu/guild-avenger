local _, addon = ...
local panel, dialog, review, toast, download, minimapButton, soundWindow
local statsWindow, commentWindow
local offers = {}
local rowCount, mainRowCount, rowHeight = 7, 6, 51
local highPrioritySound = "Interface\\AddOns\\ForeverWatch\\Sounds\\HighPriority.ogg"
local bookIcon = "Interface\\Icons\\INV_Misc_Book_11"

local color = {
    border = { 0.36, 0.29, 0.18, 1 },
    panel = { 0.11, 0.095, 0.073, 0.98 },
    inset = { 0.059, 0.052, 0.04, 1 },
    button = { 0.20, 0.13, 0.14, 1 },
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

local function showComment(text)
    if not commentWindow then
        local root = window("GrudgeBookComment", 500, 174, "FULLSCREEN_DIALOG")
        root:SetFrameLevel(32)
        tinsert(UISpecialFrames, "GrudgeBookComment")
        label(root, "GameFontNormalLarge", color.gold, "Коментар"):SetPoint("TOPLEFT", 20, -16)
        root.text = label(root, "GameFontHighlight", color.white)
        root.text:SetPoint("TOPLEFT", 20, -47)
        root.text:SetWidth(460)
        root.text:SetJustifyH("LEFT")
        root.text:SetWordWrap(true)
        root.text:SetNonSpaceWrap(true)
        button(root, "Закрити", 90, function() root:Hide() end):SetPoint("BOTTOMRIGHT", -19, 13)
        commentWindow = root
    end
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
    control:SetScript("OnClick", function() showComment(fullText and fullText() or text:GetText()) end)
    return control
end

local function status(text, success, message)
    text:SetTextColor(unpack(success and color.muted or color.red))
    text:SetText(message or "")
end

local function metadata(entry)
    local author = entry.author ~= "" and entry.author or "Автор невідомий"
    if entry.addedAt > 0 then
        return author .. "  /  " .. date("%d.%m.%Y %H:%M", entry.addedAt)
    end
    return author
end

local function lastSeen(entry)
    local seen = entry.seen
    if not seen then return end
    local zone = seen.zone and seen.zone ~= "" and (" · " .. seen.zone) or ""
    return "Бачили " .. date("%d.%m %H:%M", seen.at) .. zone
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
    panel.submit.label:SetText(panel.editing and "Зберегти" or (manual and "Додати" or "Додати ціль"))
    panel.guild.label:SetText(manual and "Додати гільдію" or "Гільдія з цілі")
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
            row.check:SetChecked(panel.selected[key] == true)
            row.name:SetText(entry.kind == "G" and "Гільдія: " .. entry.name or entry.name)
            row.note:SetText(entry.note)
            row.comment:SetShown(entry.note ~= "")
            row.metadata:SetText(lastSeen(entry) or (entry.pending and "Очікує підтвердження WoW" or metadata(entry)))
            row.deaths:SetText(("%d"):format(entry.deaths))
            row.priority.label:SetText(entry.high and "Високий" or "Звичайний")
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
    local query = addon.LowerName(panel.search:GetText():match("^%s*(.-)%s*$"))
    for _, entry in ipairs(allEntries) do
        present[addon.RecordKey(entry)] = true
        local matches = query == "" or addon.LowerName(entry.name):find(query, 1, true) or addon.LowerName(entry.note):find(query, 1, true)
        if matches and (not panel.filterKind or panel.filterKind == entry.kind) and (not panel.filterHigh or entry.high) then
            panel.entries[#panel.entries + 1] = entry
        end
    end
    for key in pairs(panel.selected) do
        if not present[key] then panel.selected[key] = nil end
    end
    local selected = selectionSize(panel.selected)
    panel.count:SetText(("Записи: %d / %d"):format(#panel.entries, #allEntries))
    panel.selectAll:SetChecked(#allEntries > 0 and selected == #allEntries)
    panel.selectAll:SetEnabled(#allEntries > 0)
    panel.selectionCount:SetText(selected > 0 and tostring(selected) or "")
    enabled(panel.deleteSelected, selected > 0)
    local ready = scope ~= nil
    panel.name:SetEnabled(ready and not panel.editing)
    panel.note:SetEnabled(ready)
    enabled(panel.submit, ready)
    enabled(panel.share, ready and scope ~= "local")
    panel.share.label:SetText(selected > 0 and ("Поділитися (%d)"):format(selected) or "Поділитися переліком")
    panel.clearSelection:SetShown(selected > 0)
    updateAddLabels()
    panel.cancel:SetShown(panel.editing ~= nil)
    panel.guild:SetShown(not panel.editing)
    enabled(panel.guild, ready)
    panel.empty:SetText(ready and (#allEntries > 0 and "За цим фільтром записів немає" or "Книга порожня")
        or "Завантаження гільдії…")
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
                status(panel.status, false, "Введіть повне ім’я персонажа або виберіть ворога ціллю.")
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
    local value = GrudgeBookDB.sound[key]
    check:SetChecked(value == true or (value == nil and checkedByDefault))
    check:SetScript("OnClick", function(self)
        GrudgeBookDB.sound[key] = self:GetChecked() == true
    end)
end

local sounds = {
    { "RAID_WARNING", "Рейд-тривога" },
    { "RAID_BOSS_EMOTE_WARNING", "Попередження рейдового боса" },
    { "READY_CHECK", "Перевірка готовності" },
    { "ALARM_CLOCK_WARNING_1", "Будильник 1" },
    { "ALARM_CLOCK_WARNING_3", "Будильник 3" },
    { "UI_BNET_TOAST", "Сповіщення Battle.net" },
    { "MAP_PING", "Пінг на карті" },
    { "IG_QUEST_LOG_OPEN", "Журнал завдань" },
}

local function playAlertSound(high)
    local choice = GrudgeBookDB.sound[high and "highSound" or "normalSound"]
    local kit = choice and SOUNDKIT[choice]
    if kit then
        PlaySound(kit, "Master")
    elseif not (high and PlaySoundFile and PlaySoundFile(highPrioritySound, "Master")) then
        PlaySound(high and SOUNDKIT.RAID_BOSS_EMOTE_WARNING or SOUNDKIT.RAID_WARNING, "Master")
    end
end

local function soundPicker(root, y, high)
    local setting = high and "highSound" or "normalSound"
    local title = high and "Високий пріоритет" or "Звичайний пріоритет"
    label(root, "GameFontHighlightSmall", color.muted, title):SetPoint("TOPLEFT", 20, y)
    local dropdown = CreateFrame("DropdownButton", nil, root, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", 20, y - 16)
    dropdown:SetWidth(278)
    dropdown:SetupMenu(function(_, menu)
        local function isSelected(choice)
            return GrudgeBookDB.sound[setting] == choice
        end
        local function selectSound(choice)
            GrudgeBookDB.sound[setting] = choice
        end
        local default = high and "Типовий · висхідний сигнал" or "Типовий · рейд-тривога"
        menu:CreateRadio(default, function() return not SOUNDKIT[GrudgeBookDB.sound[setting] or ""] end,
            function() selectSound(nil) end)
        for _, sound in ipairs(sounds) do
            if SOUNDKIT[sound[1]] then menu:CreateRadio(sound[2], isSelected, selectSound, sound[1]) end
        end
    end)
    button(root, "Прослухати", 104, function() playAlertSound(high) end):SetPoint("LEFT", dropdown, "RIGHT", 10, 0)
end

function addon.PromptSounds()
    if not soundWindow then
        local root = window("GrudgeBookSounds", 436, 247, "FULLSCREEN_DIALOG")
        tinsert(UISpecialFrames, "GrudgeBookSounds")
        label(root, "GameFontNormalLarge", color.gold, "Звуки GrudgeBook"):SetPoint("TOPLEFT", 20, -17)
        soundPicker(root, -51, false)
        soundPicker(root, -108, true)
        soundOption(root, 20, -169, "Персонажі", "P", true)
        soundOption(root, 121, -169, "Гільдії", "G", true)
        soundOption(root, 196, -169, "Лише високий пріоритет", "highOnly", false)
        button(root, "Готово", 90, function() root:Hide() end):SetPoint("BOTTOMRIGHT", -19, 15)
        soundWindow = root
    end
    soundWindow:Show()
end

local function createFilters(root)
    local titles, kinds = { "Усі", "Персонажі", "Гільдії" }, { false, "P", "G" }
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
    root.priorityFilter = checkbox(root, 448, -174, "Лише високий пріоритет")
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
    root.selectAll = checkbox(toolbar, 7, -3, "Позначити всі")
    root.selectionCount = label(toolbar, "GameFontHighlightSmall", color.gold)
    root.selectionCount:SetPoint("LEFT", 112, 0)
    root.deleteSelected = button(toolbar, "Вилучити позначені", 147, function() confirmBulkRemoval() end)
    root.deleteSelected:SetPoint("LEFT", 141, 0)
    root.deleteSelected:SetHeight(23)
    label(toolbar, "GameFontHighlightSmall", color.muted, "Пріоритет"):SetPoint("LEFT", 315, 0)
    label(toolbar, "GameFontHighlightSmall", color.muted, "Смерті"):SetPoint("LEFT", 395, 0)
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
    local root = window("GrudgeBookPanel", 662, 622, "DIALOG")
    root:SetMovable(true)
    root.rows, root.entries, root.selected = {}, {}, {}
    tinsert(UISpecialFrames, "GrudgeBookPanel")
    local header = CreateFrame("Frame", nil, root)
    header:SetPoint("TOPLEFT", 20, -12)
    header:SetPoint("TOPRIGHT", -57, -12)
    header:SetHeight(34)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() root:StartMoving() end)
    header:SetScript("OnDragStop", function() root:StopMovingOrSizing() end)
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT")
    icon:SetTexture(bookIcon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    label(header, "GameFontNormalLarge", color.gold, "GrudgeBook"):SetPoint("LEFT", 29, 0)
    root.count = label(header, "GameFontHighlightSmall", color.muted)
    root.count:SetPoint("RIGHT")
    root.search = input(root, 210, addon.NoteLimit)
    root.search:SetPoint("LEFT", header, "LEFT", 201, 0)
    local hint = label(root.search, "GameFontHighlightSmall", color.muted, "Пошук за ім’ям або коментарем")
    hint:SetPoint("LEFT", 8, 0)
    root.search:SetScript("OnTextChanged", function(self)
        hint:SetShown(self:GetText() == "")
        root.scroll:SetValue(0)
        addon.RefreshUI()
    end)
    root.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local close = CreateFrame("Button", nil, root, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() root:Hide() end)

    label(root, "GameFontHighlightSmall", color.muted, "Повне ім’я персонажа або назва гільдії"):SetPoint("TOPLEFT", 20, -57)
    root.name = input(root, 518, addon.NameLimit)
    root.name:SetPoint("TOPLEFT", 20, -74)
    root.submit = button(root, "Додати ціль", 96, submit)
    root.submit:SetPoint("LEFT", root.name, "RIGHT", 8, 0)
    label(root, "GameFontHighlightSmall", color.muted, "Коментар (необов’язково)"):SetPoint("TOPLEFT", 20, -116)
    root.note = input(root, 518, addon.NoteLimit)
    root.note:SetPoint("TOPLEFT", 20, -133)
    root.cancel = button(root, "Скасувати", 96, function()
        resetForm()
        addon.RefreshUI()
        status(root.status, true, "")
    end)
    root.cancel:SetPoint("LEFT", root.note, "RIGHT", 8, 0)
    root.guild = button(root, "Гільдія з цілі", 96, submitGuild)
    root.guild:SetPoint("LEFT", root.note, "RIGHT", 8, 0)
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
    list:SetHeight(mainRowCount * rowHeight + 4)
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
        row:SetPoint("TOPLEFT", 2, -2 - (index - 1) * rowHeight)
        row:SetPoint("TOPRIGHT", -16, -2 - (index - 1) * rowHeight)
        row:SetHeight(rowHeight - 1)
        fill(row, index % 2 == 0 and color.inset or color.panel, 0, 0)
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(24, 24)
        row.check:SetPoint("LEFT", 5, 0)
        row.check:SetScript("OnClick", function(self)
            local key = addon.RecordKey(row.entry)
            root.selected[key] = self:GetChecked() and true or nil
            addon.RefreshUI()
        end)
        row.name = label(row, "GameFontHighlight", color.white)
        row.name:SetPoint("TOPLEFT", 34, -5)
        row.name:SetWidth(286)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.note = label(row, "GameFontHighlightSmall", color.muted)
        row.note:SetPoint("TOPLEFT", 34, -20)
        row.note:SetJustifyH("LEFT")
        row.comment = commentPreview(row, row.note, 286, 1)
        row.metadata = label(row, "GameFontHighlightSmall", color.muted)
        row.metadata:SetPoint("TOPLEFT", 34, -34)
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
        local remove = button(row, "Вилучити", 75, function()
            local entry = row.entry
            if panel.editing == entry then
                resetForm()
            end
            status(root.status, addon.Delete(entry.name, entry.kind, entry))
        end)
        remove:SetPoint("RIGHT", -7, 0)
        button(row, "Коментар", 78, function()
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
    root.soundSettings = button(root, "Звуки…", 96, addon.PromptSounds)
    root.soundSettings:SetPoint("TOPLEFT", 20, -554)
    button(root, "Статистика", 110, function() addon.OpenStats() end):SetPoint("LEFT", root.soundSettings, "RIGHT", 8, 0)
    root.share = button(root, "Поділитися переліком", 159, function() addon.PromptShare() end)
    root.share:SetPoint("BOTTOMRIGHT", -20, 18)
    root.clearSelection = button(root, "Зняти вибір", 105, function()
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
    local tab = root.selectedTab
    local rows = addon.StatsRows(tab, root.weekly)
    local pages = math.max(1, math.ceil(#rows / statsPageSize))
    root.page = math.max(1, math.min(root.page, pages))
    for index, row in ipairs(root.rows) do
        local position = (root.page - 1) * statsPageSize + index
        local record = rows[position]
        row.record = record
        row.add:SetShown(record ~= nil and tab == 3)
        row:SetShown(record ~= nil)
        if record and tab == 1 then
            row.name:SetText(record.killer or "Невідомий нападник")
            row.count:SetText(date("%d.%m %H:%M", record.at))
            local place = record.zone and record.zone ~= "" and record.zone or "Невідома локація"
            if record.area and record.area ~= "" and record.area ~= place then place = place .. " · " .. record.area end
            if record.x then place = place .. ("  %.1f, %.1f"):format(record.x * 100, record.y * 100) end
            row.detail:SetText(place)
        elseif record then
            row.name:SetText(("%d.  %s"):format(position, record.name))
            row.count:SetText(tostring(record.count))
            row.detail:SetText(tab == 2 and "Останні удари по цілях Книги Образ" or "Останні удари по гільдійцях")
        end
    end
    root.empty:SetShown(#rows == 0)
    root.week:SetShown(tab == 2)
    root.week.label:SetText(root.weekly and "Цього тижня" or "За весь час")
    root.pagination:SetText(("%d / %d"):format(root.page, pages))
    enabled(root.back, root.page > 1)
    enabled(root.next, root.page < pages)
    root.share:SetChecked(addon.StatsSharing())
    local scope = addon.Scope()
    local inGuild = IsInGuild() and scope ~= nil and scope ~= "local"
    enabled(root.request, inGuild)
    root.share:SetEnabled(inGuild)
end

local function createStats()
    local root = window("GrudgeBookStats", 540, 532, "FULLSCREEN_DIALOG")
    root.page, root.rows, root.Tabs = 1, {}, {}
    root.minTabWidth = 100
    tinsert(UISpecialFrames, "GrudgeBookStats")
    label(root, "GameFontNormalLarge", color.gold, "Статистика GrudgeBook"):SetPoint("TOPLEFT", 20, -18)
    local close = CreateFrame("Button", nil, root, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() root:Hide() end)
    local titles = { "Мої смерті", "Месники", "Вороги" }
    for index, title in ipairs(titles) do
        local tab = CreateFrame("Button", nil, root, "PanelTopTabButtonTemplate")
        root.Tabs[index] = tab
        tab:SetID(index)
        tab:SetText(title)
        tab:SetScript("OnClick", function(self)
            PanelTemplates_SetTab(root, self:GetID())
            root.page = 1
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
    root.empty = label(list, "GameFontHighlight", color.muted, "Поки немає записів")
    root.empty:SetPoint("CENTER")
    for index = 1, statsPageSize do
        local row = CreateFrame("Frame", nil, list)
        row:SetPoint("TOPLEFT", 2, -2 - (index - 1) * 44)
        row:SetPoint("TOPRIGHT", -2, -2 - (index - 1) * 44)
        row:SetHeight(42)
        fill(row, index % 2 == 0 and color.inset or color.panel, 0, 0)
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
        row.count = label(row, "GameFontHighlight", color.gold)
        row.count:SetPoint("TOPRIGHT", -10, -6)
        row.add = button(row, "До книги", 83, function()
            local ok, message = addon.AddRankedEnemy(row.record.guid)
            status(root.status, ok, message)
        end)
        row.add:SetPoint("RIGHT", -61, -3)
        row.add:SetHeight(22)
        row.add:Hide()
        root.rows[index] = row
    end
    root.week = button(root, "За весь час", 120, function()
        root.weekly = not root.weekly
        root.page = 1
        addon.RefreshStats()
    end)
    root.week:SetPoint("TOPRIGHT", -20, -53)
    root.back = button(root, "Назад", 73, function() root.page = root.page - 1; addon.RefreshStats() end)
    root.back:SetPoint("TOPLEFT", 20, -407)
    root.pagination = label(root, "GameFontHighlightSmall", color.muted)
    root.pagination:SetPoint("LEFT", root.back, "RIGHT", 8, 0)
    root.next = button(root, "Далі", 73, function() root.page = root.page + 1; addon.RefreshStats() end)
    root.next:SetPoint("TOPLEFT", 149, -407)
    root.share = checkbox(root, 20, -445, "Ділитися підсумками з гільдією")
    root.share:SetScript("OnClick", function(self) addon.SetStatsSharing(self:GetChecked()) end)
    root.request = button(root, "Оновити рейтинг", 128, function() root.status:SetText(addon.RequestStats()) end)
    root.request:SetPoint("TOPRIGHT", -20, -442)
    root.status = label(root, "GameFontHighlightSmall", color.muted, "Гільдія бачить тільки підсумки. Журнал і координати локальні.")
    root.status:SetPoint("BOTTOMLEFT", 20, 23)
    root.status:SetWidth(500)
    root.status:SetJustifyH("LEFT")
    root.status:SetMaxLines(2)
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
    local root = CreateFrame("Button", "GrudgeBookMinimapButton", Minimap)
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

    local angle = GrudgeBookDB.minimapAngle or math.rad(225)
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
        GameTooltip:SetText("GrudgeBook")
        GameTooltip:AddLine("Клік або /gb — відкрити книгу\nПеретягування — перемістити значок", 1, 1, 1)
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
        GrudgeBookDB.minimapAngle = angle
    end)
    Minimap:HookScript("OnSizeChanged", place)
    place()
end

function addon.PromptDownload(url, description)
    if not download then
        local root = window("GrudgeBookDownload", 520, 158, "FULLSCREEN_DIALOG")
        root:SetFrameLevel(30)
        tinsert(UISpecialFrames, "GrudgeBookDownload")
        label(root, "GameFontNormalLarge", color.gold, "Завантаження GrudgeBook"):SetPoint("TOPLEFT", 18, -15)
        root.description = label(root, "GameFontHighlight", color.white)
        root.description:SetPoint("TOPLEFT", 18, -43)
        root.description:SetWidth(484)
        root.description:SetJustifyH("LEFT")
        root.field = input(root, 484, 200)
        root.field:SetPoint("TOPLEFT", 18, -79)
        root.field:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        root.field:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        label(root, "GameFontHighlightSmall", color.muted, "Ctrl+C — скопіювати посилання"):SetPoint("BOTTOMLEFT", 18, 21)
        button(root, "Закрити", 90, function() root:Hide() end):SetPoint("BOTTOMRIGHT", -18, 13)
        root:SetScript("OnHide", function() root.field:ClearFocus() end)
        download = root
    end
    download.description:SetText(description)
    download.field:SetText(url)
    download:Show()
    download.field:SetFocus()
    download.field:HighlightText()
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
    local root = window("GrudgeBookDialog", 428, 190, "FULLSCREEN_DIALOG")
    tinsert(UISpecialFrames, "GrudgeBookDialog")
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
    root.publish = button(root, "У чат гільдії", 125, function()
        local ok, message = root.publishAction()
        if ok then
            root:Hide()
            addon.Say(message)
        else
            status(root.status, false, message)
        end
    end)
    root.publish:SetPoint("BOTTOMLEFT", 18, 13)
    root.removals = checkbox(root, 18, -309, "Запропонувати вилучені записи")
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
    dialog.cancel.label:SetText(options.cancel or "Скасувати")
    dialog.autocomplete = options.autocomplete
    dialog:SetHeight(options.autocomplete and (options.removals and 365 or 339) or 190)
    dialog.status:ClearAllPoints()
    dialog.status:SetPoint("TOPLEFT", 18, options.autocomplete and -278 or -118)
    dialog.publish:SetShown(options.autocomplete == true)
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

confirmBulkRemoval = function()
    local selection, scope = {}, addon.Scope()
    for _, entry in ipairs(addon.Entries()) do
        local key = addon.RecordKey(entry)
        if panel.selected[key] then selection[key] = entry end
    end
    local count = selectionSize(selection)
    if count == 0 then return end
    openDialog({
        title = "Вилучити позначені записи?",
        text = ("З Книги Образ буде вилучено записів: %d."):format(count),
        confirm = "Вилучити",
        action = function()
            local removed = addon.DeleteSelection(selection, scope)
            return removed > 0, removed > 0 and ("Вилучено записів: %d."):format(removed) or "Вибір або гільдія змінилися."
        end,
    })
end

submitGuild = function()
    local name, note = manualName(), panel.note:GetText()
    local _, targetGuild = addon.EnemyEntry("target", "G")
    if not name and targetGuild then
        local ok, message = addon.Add("", note, "target", "G")
        finishForm(ok, message, targetGuild, "G")
        return
    end
    openDialog({
        title = "Додати гільдію вручну",
        text = "Назва гільдії",
        value = name, limit = addon.NameLimit, confirm = "Додати",
        action = function(guild)
            if not guild:match("%S") then return false, "Введіть назву гільдії." end
            local ok, message = addon.Add(guild, note, nil, "G")
            if ok then finishForm(ok, message, guild, "G") end
            return ok, message
        end,
    })
end

function addon.PromptShare()
    local _, target = addon.UnitName("target")
    addon.UpdateScope()
    local scope = addon.Scope()
    local selection
    if panel and panel.scope == scope and next(panel.selected) then
        selection = {}
        for key in pairs(panel.selected) do selection[key] = true end
    end
    local function send(action, input)
        if not addon.UpdateScope() or addon.Scope() ~= scope then
            return false, "Гільдія змінилася. Відкрийте передавання ще раз."
        end
        local removals = dialog.removals:IsShown() and dialog.removals:GetChecked()
        if input then return action(input, selection, removals) end
        return action(selection, removals)
    end
    addon.RefreshRoster()
    openDialog({
        title = "Поділитися переліком",
        text = (selection and ("Вибрано записів: %d"):format(selectionSize(selection)) or "Увесь список")
            .. "\nІм’я та прізвище гільдійця",
        value = target, limit = addon.NameLimit, confirm = "Надіслати", autocomplete = true,
        removals = not selection and scope ~= nil and scope ~= "local" and #addon.RemovalProposals() > 0,
        action = function(input) return send(addon.Share, input) end,
        publishAction = function() return send(addon.Publish) end,
    })
end

function addon.PromptGuild(unit)
    local _, name = addon.EnemyEntry(unit, "G")
    if not name then
        local message = "Виберіть ворога, чию гільдію видно."
        if panel and panel:IsShown() then
            status(panel.status, false, message)
        else
            addon.Say(message)
        end
        return
    end
    openDialog({
        title = "Внести гільдію в Книгу Образ",
        text = name .. "\nКоментар (необов’язково)",
        limit = addon.NoteLimit, confirm = "Додати",
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
            local title = record.kind == "G" and "Гільдія: " .. record.name or record.name
            row.name:SetText((change.new and "+ " or change.removed and "− " or "") .. title)
            local priority = record.high and "Високий" or "Звичайний"
            row.priority:SetText(change.removed and "Вилучити" or
                (change.changedPriority and (record.high and "↑ " or "↓ ") .. priority) or
                (change.higherPriority and "↑ Високий") or priority)
            row.priority:SetTextColor(unpack(change.removed and color.red or record.high and color.gold or color.muted))
            local note = record.note ~= "" and record.note or "Без коментаря"
            row.detail:SetText(change.changedNote and "Нова причина · " .. note or note)
            row.comment:SetShown(record.note ~= "" or change.changedNote == true)
            row.author:SetText((record.author ~= "" and record.author or "Автор невідомий")
                .. (record.deaths > 0 and (" · Смерті: %d"):format(record.deaths) or ""))
        end
    end
    local selected = selectionSize(offer.selected)
    review.count:SetText(("Позначено %d з %d"):format(selected, #offer.changes))
    enabled(review.confirm, selected > 0)
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
    local root = window("GrudgeBookReview", 516, 560, "FULLSCREEN_DIALOG")
    local reviewRowHeight = 52
    root.rows = {}
    tinsert(UISpecialFrames, "GrudgeBookReview")
    label(root, "GameFontNormalLarge", color.gold, "Імпорт Книги Образ"):SetPoint("TOPLEFT", 18, -15)
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
    root.empty = label(list, "GameFontHighlight", color.muted, "Нових записів або оновлень немає.")
    root.empty:SetPoint("CENTER")
    for index = 1, rowCount do
        local row = CreateFrame("Frame", nil, list)
        row:SetPoint("TOPLEFT", 2, -2 - (index - 1) * reviewRowHeight)
        row:SetPoint("TOPRIGHT", -17, -2 - (index - 1) * reviewRowHeight)
        row:SetHeight(reviewRowHeight - 1)
        fill(row, index % 2 == 0 and color.inset or color.panel, 0, 0)
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
            if change.changedNote then
                local before = change.oldNote ~= "" and change.oldNote or "Без коментаря"
                local after = change.record.note ~= "" and change.record.note or "Без коментаря"
                return "Було\n" .. before .. "\n\nПропонують\n" .. after
            end
            return change.record.note
        end)
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
    button(root, "Позначити всі", 110, function() selectAll(true) end):SetPoint("BOTTOMLEFT", 18, 15)
    button(root, "Зняти всі", 83, function() selectAll(false) end):SetPoint("BOTTOMLEFT", 135, 15)
    root.confirm = button(root, "Прийняти", 102, function()
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
    root.cancel = button(root, "Відхилити", 102, function() root:Hide() end)
    root.cancel:SetPoint("RIGHT", root.confirm, "LEFT", -7, 0)
    root:SetScript("OnHide", function()
        root.offer = nil
        C_Timer.After(0, presentOffer)
    end)
    return root
end

presentOffer = function()
    if #offers == 0 or (dialog and dialog:IsShown()) or (review and review:IsShown()) then
        return
    end
    if not review then review = createReview() end
    local offer = table.remove(offers, 1)
    table.sort(offer.changes, function(left, right) return left.record.name < right.record.name end)
    offer.selected = {}
    review.offer = offer
    review.sender:SetText("Відправник: " .. offer.sender)
    review.summary:SetText(("Нові: %d · Оновлення: %d · На вилучення: %d"):format(offer.added, offer.updated, offer.removed or 0))
    review.empty:SetShown(#offer.changes == 0)
    local maximum = math.max(0, #offer.changes - rowCount)
    review.scroll:SetMinMaxValues(0, maximum)
    review.scroll:SetValue(0)
    review.scroll:SetShown(maximum > 0)
    selectAll(true, true)
    review:Show()
end

function addon.OfferImport(sender, added, updated, changes, accept, removed)
    if #offers < 10 then
        offers[#offers + 1] = { sender = sender, added = added, updated = updated, changes = changes, accept = accept, removed = removed }
        presentOffer()
    end
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
            rootDescription:CreateButton("Внести в Книгу Образ", function()
                openDialog({
                    title = "Внести в Книгу Образ",
                    text = name .. "\nКоментар (необов’язково)",
                    limit = addon.NoteLimit, confirm = "Додати",
                    action = function(note) return addon.Add(name, note, unit) end,
                })
            end)
            if addon.EnemyEntry(unit, "G") then
                rootDescription:CreateButton("Внести гільдію в Книгу Образ", function() addon.PromptGuild(unit) end)
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
    control:SetAttribute("_onstate-grudgecombat", [[
        if newstate == "combat" then self:Hide() end
    ]])
    RegisterStateDriver(control, "grudgecombat", "[combat] combat; safe")
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
        targetButton = secured("У ціль", 70)
        targetButton:SetAttribute("type", "macro")
        if C_Ping and C_Ping.IsPingSystemEnabled then
            pingButton = secured("Пінг небезпеки", 132)
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
    local saved = GrudgeBookDB.alertPosition
    root:ClearAllPoints()
    if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number" then
        root:SetPoint("CENTER", UIParent, "BOTTOMLEFT", saved.x * UIParent:GetWidth(), saved.y * UIParent:GetHeight())
    else
        root:SetPoint("TOP", UIParent, "TOP", 0, -42)
    end
end

local function createAlert()
    local root = window("GrudgeBookAlert", alertWidth, alertHeight, "HIGH")
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
        GrudgeBookDB.alertPosition = {
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
    root.priority = label(root, "GameFontHighlightSmall", color.gold, "Високий")
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
    if not toast then
        toast = createAlert()
    end
    cancelAlertTimer()
    alertName = not preview and entry.name or nil
    portraitUnit = entry.unit
    toast.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    refreshAlertPortrait()
    toast.name:SetText(entry.name)
    toast:SetBackdropBorderColor(unpack(entry.high and urgentBorder or alertBorder))
    toast.note:SetText(entry.note)
    toast.comment:SetShown(entry.note ~= "")
    toast.priority:SetShown(entry.high == true)
    toast:Show()
    refreshAlertButtons()
    local sound = GrudgeBookDB.sound
    if preview or (sound[entry.kind] ~= false and (not sound.highOnly or entry.high)) then
        playAlertSound(entry.high)
    end
    if not alertMoving then
        expiration = C_Timer.NewTimer(12, addon.CloseAlert)
    end
end
