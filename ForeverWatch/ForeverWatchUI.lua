local _, addon = ...
local panel
local pageSize = 6

local colors = {
    border = { 0.23, 0.33, 0.37, 1 },
    panel = { 0.055, 0.08, 0.10, 0.98 },
    inset = { 0.035, 0.055, 0.07, 1 },
    button = { 0.11, 0.17, 0.20, 1 },
    selected = { 0.09, 0.26, 0.25, 1 },
    accent = { 0.34, 0.84, 0.74, 1 },
    muted = { 0.59, 0.69, 0.73, 1 },
    error = { 1, 0.66, 0.48, 1 },
    white = { 0.91, 0.95, 0.96, 1 },
}

local function fill(frame, color, inset, depth)
    local texture = frame:CreateTexture(nil, "BACKGROUND", nil, depth)
    texture:SetPoint("TOPLEFT", inset, -inset)
    texture:SetPoint("BOTTOMRIGHT", -inset, inset)
    texture:SetColorTexture(unpack(color))
    return texture
end

local function label(parent, font, color)
    local text = parent:CreateFontString(nil, "OVERLAY", font)
    text:SetTextColor(unpack(color))
    return text
end

local function button(parent, width, height, title, action, color, template)
    local control = CreateFrame("Button", nil, parent, template)
    control:SetSize(width, height)
    control.background = fill(control, color or colors.button, 0, 0)
    local hover = control:CreateTexture()
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.09)
    control:SetHighlightTexture(hover)

    local text = label(control, "GameFontHighlight", colors.white)
    text:SetPoint("CENTER")
    text:SetText(title)
    control.label = text
    if action then
        control:SetScript("OnClick", action)
    end
    return control
end

local function setButtonEnabled(control, enabled)
    control:SetEnabled(enabled)
    control:SetAlpha(enabled and 1 or 0.4)
end

local function editBox(parent, width, maxBytes)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, 32)
    box:SetFontObject(GameFontHighlight)
    box:SetTextInsets(9, 9, 0, 0)
    box:SetAutoFocus(false)
    box:SetMaxBytes(maxBytes)
    box:EnableMouse(true)
    fill(box, colors.border, 0, -2)
    fill(box, colors.inset, 1, -1)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

local function setStatus(ok, message)
    panel.status:SetTextColor(unpack(ok and colors.muted or colors.error))
    panel.status:SetText(message or "")
end

local function clearForm()
    panel.editing = nil
    panel.input:SetText("")
    panel.input:ClearFocus()
    panel.note:SetText("")
    panel.note:ClearFocus()
end

local function refresh()
    if not panel or not panel:IsShown() then
        return
    end
    local players, guilds, listID = addon.GetLists()
    if panel.listID ~= listID then
        panel.listID, panel.page = listID, 1
        clearForm()
        setStatus(true, "")
    end
    panel.names = panel.kind == "P" and players or guilds
    panel.lastPage = math.max(1, math.ceil(#panel.names / pageSize))
    panel.page = math.min(panel.page, panel.lastPage)
    panel.players.label:SetText(("Персонажі (%d)"):format(#players))
    panel.guilds.label:SetText(("Гільдії (%d)"):format(#guilds))
    panel.players.background:SetColorTexture(unpack(panel.kind == "P" and colors.selected or colors.button))
    panel.guilds.background:SetColorTexture(unpack(panel.kind == "G" and colors.selected or colors.button))
    panel.inputLabel:SetText(panel.kind == "P" and "Ім’я та прізвище персонажа" or "Назва гільдії")
    if not listID then
        panel.scope:SetText("Підключення до гільдії…")
    elseif listID == "local" then
        panel.scope:SetText("Особистий список")
    else
        panel.scope:SetText("Спільний список гільдії")
    end
    local ready = listID ~= nil
    panel.input:SetEnabled(ready and not panel.editing)
    panel.note:SetEnabled(ready)
    setButtonEnabled(panel.add, ready)
    setButtonEnabled(panel.target, ready and not panel.editing)
    setButtonEnabled(panel.share, ready and listID ~= "local")
    panel.add.label:SetText(panel.editing and "Зберегти" or "Додати")
    panel.cancel:SetShown(panel.editing ~= nil)
    panel.empty:SetShown(#panel.names == 0)
    panel.empty:SetText(ready and "Список порожній" or "Завантаження списку…")

    local start = (panel.page - 1) * pageSize
    for index, row in ipairs(panel.rows) do
        row.entry = panel.names[start + index]
        row:SetShown(row.entry ~= nil)
        row.name:SetText(row.entry and row.entry.name or "")
        row.note:SetText(row.entry and row.entry.note or "")
    end
    local paged = panel.lastPage > 1
    panel.previous:SetShown(paged)
    panel.next:SetShown(paged)
    panel.pageNumber:SetShown(paged)
    setButtonEnabled(panel.previous, panel.page > 1)
    setButtonEnabled(panel.next, panel.page < panel.lastPage)
    panel.pageNumber:SetText(("%d / %d"):format(panel.page, panel.lastPage))
end

addon.RefreshPanel = refresh

local function switchTab(kind)
    if panel.kind == kind then
        return
    end
    panel.kind, panel.page = kind, 1
    clearForm()
    setStatus(true, "")
    refresh()
end

local function changePage(amount)
    local page = panel.page + amount
    if page >= 1 and page <= panel.lastPage then
        panel.page = page
        refresh()
    end
end

local function addToList()
    local input = panel.input:GetText()
    if not input:find("%S") then
        setStatus(false, panel.kind == "P" and "Введіть ім’я та прізвище персонажа." or "Введіть назву гільдії.")
        return
    end
    local ok, message, name = addon.EditEntry(panel.kind, panel.editing or input,
        panel.editing and "note" or "add", panel.note:GetText())
    setStatus(ok, message)
    if ok then
        clearForm()
        for index, entry in ipairs(panel.names) do
            if entry.name == name then
                panel.page = math.ceil(index / pageSize)
                break
            end
        end
        refresh()
    end
end

local function editNote(entry)
    panel.editing = entry.name
    panel.input:SetText(entry.name)
    panel.note:SetText(entry.note or "")
    setStatus(true, "")
    refresh()
    panel.note:SetFocus()
end

local function fillFromTarget()
    local _, name = addon.GetTargetName(panel.kind)
    if name then
        panel.input:SetText(name)
        setStatus(true, "")
    else
        setStatus(false, panel.kind == "P" and "Виберіть доступного персонажа."
            or "Виберіть персонажа, чию гільдію видно.")
    end
end

local function createPanel()
    local frame = CreateFrame("Frame", "ForeverWatchPanel", UIParent)
    frame:Hide()
    frame:SetPoint("CENTER")
    frame:SetSize(552, 548)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame.kind, frame.page, frame.rows = "P", 1, {}
    fill(frame, colors.border, 0, -2)
    fill(frame, colors.panel, 1, -1)
    tinsert(UISpecialFrames, "ForeverWatchPanel")

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 20, -12)
    header:SetPoint("TOPRIGHT", -62, -12)
    header:SetHeight(35)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    local title = label(header, "GameFontNormalLarge", colors.accent)
    title:SetPoint("LEFT")
    title:SetText("Forever Watch")
    frame.scope = label(header, "GameFontHighlightSmall", colors.muted)
    frame.scope:SetPoint("RIGHT")
    local close = button(frame, 28, 28, "×", function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", -16, -15)

    frame.players = button(frame, 138, 29, "", function() switchTab("P") end)
    frame.players:SetPoint("TOPLEFT", 20, -59)
    frame.guilds = button(frame, 120, 29, "", function() switchTab("G") end)
    frame.guilds:SetPoint("LEFT", frame.players, "RIGHT", 6, 0)
    local preview = button(frame, 122, 29, "Тест сигналу", function() addon.PreviewAlert() end)
    preview:SetPoint("TOPRIGHT", -20, -59)

    frame.inputLabel = label(frame, "GameFontHighlightSmall", colors.muted)
    frame.inputLabel:SetPoint("TOPLEFT", 20, -105)
    frame.input = editBox(frame, 320, 96)
    frame.input:SetPoint("TOPLEFT", 20, -123)
    frame.input:SetScript("OnEnterPressed", addToList)
    frame.target = button(frame, 86, 32, "З цілі", fillFromTarget)
    frame.target:SetPoint("LEFT", frame.input, "RIGHT", 8, 0)
    frame.add = button(frame, 90, 32, "Додати", addToList, colors.selected)
    frame.add:SetPoint("LEFT", frame.target, "RIGHT", 8, 0)
    local noteLabel = label(frame, "GameFontHighlightSmall", colors.muted)
    noteLabel:SetPoint("TOPLEFT", 20, -168)
    noteLabel:SetText("Причина (необов’язково)")
    frame.note = editBox(frame, 414, addon.MaxNoteBytes)
    frame.note:SetPoint("TOPLEFT", 20, -186)
    frame.note:SetScript("OnEnterPressed", addToList)
    frame.cancel = button(frame, 90, 32, "Скасувати", function()
        clearForm()
        setStatus(true, "")
        refresh()
    end)
    frame.cancel:SetPoint("LEFT", frame.note, "RIGHT", 8, 0)

    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", 20, -234)
    list:SetPoint("TOPRIGHT", -20, -234)
    list:SetHeight(232)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) changePage(delta > 0 and -1 or 1) end)
    fill(list, colors.inset, 0, 0)
    frame.empty = label(list, "GameFontHighlight", colors.muted)
    frame.empty:SetPoint("CENTER")
    for index = 1, pageSize do
        local row = CreateFrame("Frame", nil, list)
        local y = -2 - (index - 1) * 38
        row:SetPoint("TOPLEFT", 2, y)
        row:SetPoint("TOPRIGHT", -2, y)
        row:SetHeight(37)
        fill(row, index % 2 == 0 and colors.inset or colors.panel, 0, 0)
        local remove = button(row, 76, 24, "Вилучити", function()
            local name = row.entry.name
            if frame.editing == name then
                clearForm()
            end
            setStatus(addon.EditEntry(frame.kind, name, "remove"))
        end)
        remove:SetPoint("RIGHT", -6, 0)
        local edit = button(row, 82, 24, "Редагувати", function() editNote(row.entry) end)
        edit:SetPoint("RIGHT", remove, "LEFT", -6, 0)
        row.name = label(row, "GameFontHighlight", colors.white)
        row.name:SetPoint("TOPLEFT", 10, -5)
        row.name:SetWidth(316)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.note = label(row, "GameFontHighlightSmall", colors.muted)
        row.note:SetPoint("TOPLEFT", 10, -20)
        row.note:SetWidth(316)
        row.note:SetJustifyH("LEFT")
        row.note:SetWordWrap(false)
        frame.rows[index] = row
    end

    frame.next = button(frame, 30, 23, "›", function() changePage(1) end)
    frame.next:SetPoint("TOPRIGHT", -20, -473)
    frame.pageNumber = label(frame, "GameFontHighlightSmall", colors.muted)
    frame.pageNumber:SetPoint("RIGHT", frame.next, "LEFT", -8, 0)
    frame.previous = button(frame, 30, 23, "‹", function() changePage(-1) end)
    frame.previous:SetPoint("RIGHT", frame.pageNumber, "LEFT", -8, 0)
    frame.share = button(frame, 158, 27, "Поширити гільдії", function() setStatus(addon.ShareList()) end)
    frame.share:SetPoint("BOTTOMRIGHT", -20, 15)
    frame.status = label(frame, "GameFontHighlightSmall", colors.muted)
    frame.status:SetPoint("LEFT", frame, "BOTTOMLEFT", 20, 29)
    frame.status:SetPoint("RIGHT", frame.share, "LEFT", -10, 0)
    frame.status:SetJustifyH("LEFT")
    frame.status:SetMaxLines(2)

    frame:SetScript("OnShow", refresh)
    frame:SetScript("OnHide", function()
        frame.input:ClearFocus()
        frame.note:ClearFocus()
    end)
    return frame
end

function addon.TogglePanel()
    if not panel then
        panel = createPanel()
    end
    panel:SetShown(not panel:IsShown())
end

local toast, targetButton, currentTarget, expire
local toastWidth, toastTop = 408, -105

local function refreshTarget()
    if InCombatLockdown() then
        if toast then
            toast.combatHint:SetShown(currentTarget ~= nil)
        end
        return
    end
    if not currentTarget then
        if targetButton then
            targetButton:Hide()
            targetButton:SetAttribute("macrotext", nil)
        end
        return
    end
    toast.combatHint:Hide()
    if not targetButton then
        -- Keep the protected button independent so the alert can be dismissed in combat.
        targetButton = button(UIParent, 90, 26, "У ціль", nil, colors.selected,
            "SecureActionButtonTemplate,SecureHandlerStateTemplate")
        targetButton:SetPoint("TOP", UIParent, "TOP", toastWidth / 2 - 59, toastTop - 67)
        targetButton:SetFrameStrata("HIGH")
        targetButton:SetFrameLevel(toast:GetFrameLevel() + 4)
        targetButton:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        targetButton:SetAttribute("type", "macro")
        targetButton:SetAttribute("_onstate-fwcombat", [[
            if newstate == "combat" then self:Hide() end
        ]])
        RegisterStateDriver(targetButton, "fwcombat", "[combat] combat; safe")
    end
    targetButton:SetAttribute("macrotext", "/targetexact " .. currentTarget)
    targetButton:Show()
end

function addon.CloseAlert()
    currentTarget = nil
    if expire then
        expire:Cancel()
        expire = nil
    end
    if toast then
        toast:Hide()
        refreshTarget()
    end
end

local function createToast()
    local card = CreateFrame("Frame", "ForeverWatchAlert", UIParent)
    card:Hide()
    card:SetPoint("TOP", UIParent, "TOP", 0, toastTop)
    card:SetSize(toastWidth, 108)
    card:SetFrameStrata("HIGH")
    fill(card, colors.border, 0, -2)
    fill(card, colors.panel, 1, -1)
    local stripe = card:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT", 1, -1)
    stripe:SetPoint("BOTTOMLEFT", 1, 1)
    stripe:SetWidth(4)
    stripe:SetColorTexture(unpack(colors.accent))
    local close = button(card, 25, 25, "×", addon.CloseAlert)
    close:SetPoint("TOPRIGHT", -9, -9)
    card.heading = label(card, "GameFontHighlightSmall", colors.accent)
    card.heading:SetPoint("TOPLEFT", 16, -13)
    card.name = label(card, "GameFontNormalLarge", colors.white)
    card.name:SetPoint("TOPLEFT", 16, -32)
    card.name:SetWidth(345)
    card.name:SetJustifyH("LEFT")
    card.name:SetWordWrap(false)
    card.details = label(card, "GameFontHighlightSmall", colors.muted)
    card.details:SetPoint("TOPLEFT", 16, -57)
    card.details:SetWidth(275)
    card.details:SetJustifyH("LEFT")
    card.details:SetMaxLines(3)
    card.combatHint = label(card, "GameFontHighlightSmall", colors.muted)
    card.combatHint:SetPoint("TOPRIGHT", -16, -75)
    card.combatHint:SetText("Ціль після бою")
    card.combatHint:Hide()
    card:RegisterEvent("PLAYER_REGEN_ENABLED")
    card:RegisterEvent("PLAYER_REGEN_DISABLED")
    card:SetScript("OnEvent", refreshTarget)
    return card
end

function addon.ShowAlert(entry, playerName, preview)
    if not toast then
        toast = createToast()
    end
    if expire then
        expire:Cancel()
    end
    currentTarget = playerName
    toast.heading:SetText(preview and "FOREVER WATCH · ПЕРЕВІРКА" or "FOREVER WATCH · ПОРУЧ")
    toast.name:SetText(playerName or entry.name)
    local guild = entry.kind == "G" and "Гільдія «" .. entry.name .. "»" or ""
    local note = entry.note or ""
    toast.details:SetText(guild .. (guild ~= "" and note ~= "" and "\n" or "") .. note)
    toast.combatHint:Hide()
    toast:Show()
    refreshTarget()
    PlaySoundFile("Interface\\AddOns\\ForeverWatch\\Alert.ogg", "Master")
    expire = C_Timer.NewTimer(12, addon.CloseAlert)
end

function addon.PreviewAlert()
    local _, playerName = addon.GetPlayerName()
    addon.ShowAlert({ kind = "P", name = "Forever Watch", note = "Кнопка «У ціль» вибере вашого персонажа." },
        playerName, true)
end
