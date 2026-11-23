local _, addon = ...
local panel, dialog, review, toast
local offers = {}
local rowCount, rowHeight = 7, 51

local color = {
    border = { 0.39, 0.24, 0.24, 1 },
    panel = { 0.10, 0.075, 0.082, 0.98 },
    inset = { 0.064, 0.049, 0.054, 1 },
    button = { 0.20, 0.13, 0.14, 1 },
    primary = { 0.36, 0.15, 0.16, 1 },
    red = { 1, 0.28, 0.26, 1 },
    gold = { 0.95, 0.75, 0.50, 1 },
    muted = { 0.79, 0.68, 0.69, 1 },
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

local function button(parent, title, width, callback, primary, template)
    local control = CreateFrame("Button", nil, parent, template)
    control:SetSize(width, 27)
    fill(control, primary and color.primary or color.button, 0, 0)
    local hover = control:CreateTexture()
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.12)
    control:SetHighlightTexture(hover)
    control.label = label(control, "GameFontHighlight", color.white, title)
    control.label:SetPoint("CENTER")
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

local function window(name, width, height, strata)
    local root = CreateFrame("Frame", name, UIParent)
    root:Hide()
    root:SetPoint("CENTER")
    root:SetSize(width, height)
    root:SetFrameStrata(strata)
    root:SetClampedToScreen(true)
    root:EnableMouse(true)
    fill(root, color.border, 0, -2)
    fill(root, color.panel, 1, -1)
    return root
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

local function renderRows()
    local slider = panel.scroll
    local offset = math.floor(slider:GetValue())
    for index, row in ipairs(panel.rows) do
        local entry = panel.entries[offset + index]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            row.name:SetText(entry.kind == "G" and "Гільдія: " .. entry.name or entry.name)
            row.note:SetText(entry.note)
            row.metadata:SetText(metadata(entry))
            row.deaths:SetText(entry.kind == "G" and "-" or ("%d"):format(entry.deaths))
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
        panel.name:SetText("")
        panel.note:SetText("")
        panel.scroll:SetValue(0)
    end
    panel.entries = addon.Entries()
    panel.count:SetText(("Записів у книзі: %d"):format(#panel.entries))
    local ready = scope ~= nil
    panel.name:SetEnabled(ready and not panel.editing)
    panel.note:SetEnabled(ready)
    enabled(panel.submit, ready)
    enabled(panel.share, ready and scope ~= "local")
    panel.submit.label:SetText(panel.editing and "Зберегти" or "Додати")
    panel.cancel:SetShown(panel.editing ~= nil)
    panel.guild:SetShown(not panel.editing)
    enabled(panel.guild, ready)
    panel.empty:SetText(ready and "Книга порожня" or "Завантаження гільдії…")
    panel.empty:SetShown(#panel.entries == 0)
    local maximum = math.max(0, #panel.entries - rowCount)
    panel.scroll:SetMinMaxValues(0, maximum)
    panel.scroll:SetValue(math.min(maximum, panel.scroll:GetValue()))
    panel.scroll:SetShown(maximum > 0)
    renderRows()
end

local function resetForm()
    panel.editing = nil
    panel.name:SetText("")
    panel.note:SetText("")
    panel.name:ClearFocus()
    panel.note:ClearFocus()
end

local function putTarget()
    local _, name = addon.EnemyUnit("target")
    if not name then
        return false
    end
    panel.name:SetText(name)
    return true
end

local function submit()
    local name, note = panel.name:GetText(), panel.note:GetText()
    if name:match("^%s*$") then
        if putTarget() then
            panel.note:SetFocus()
        else
            status(panel.status, false, "Виберіть ворога або введіть його повне ім’я.")
        end
        return
    end
    local ok, message
    if panel.editing then
        ok, message = addon.EditNote(panel.editing.name, note, panel.editing.kind)
    else
        ok, message = addon.Add(name, note)
    end
    if ok then
        resetForm()
        addon.RefreshUI()
        local key = addon.PlayerName(name)
        for index, entry in ipairs(panel.entries) do
            if addon.PlayerName(entry.name) == key then
                panel.scroll:SetValue(math.max(0, index - rowCount))
                break
            end
        end
    end
    status(panel.status, ok, message)
end

local function createPanel()
    local root = window("GrudgeBookPanel", 604, 608, "DIALOG")
    root:SetMovable(true)
    root.rows, root.entries = {}, {}
    tinsert(UISpecialFrames, "GrudgeBookPanel")
    local header = CreateFrame("Frame", nil, root)
    header:SetPoint("TOPLEFT", 20, -12)
    header:SetPoint("TOPRIGHT", -57, -12)
    header:SetHeight(34)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() root:StartMoving() end)
    header:SetScript("OnDragStop", function() root:StopMovingOrSizing() end)
    label(header, "GameFontNormalLarge", color.gold, "GrudgeBook"):SetPoint("LEFT")
    root.count = label(header, "GameFontHighlightSmall", color.muted)
    root.count:SetPoint("RIGHT")
    button(root, "×", 27, function() root:Hide() end):SetPoint("TOPRIGHT", -17, -15)

    label(root, "GameFontHighlightSmall", color.muted, "Повне ім’я персонажа"):SetPoint("TOPLEFT", 20, -57)
    root.name = input(root, 464, addon.NameLimit)
    root.name:SetPoint("TOPLEFT", 20, -74)
    root.submit = button(root, "Додати", 92, submit, true)
    root.submit:SetPoint("LEFT", root.name, "RIGHT", 8, 0)
    label(root, "GameFontHighlightSmall", color.muted, "Коментар (необов’язково)"):SetPoint("TOPLEFT", 20, -116)
    root.note = input(root, 464, addon.NoteLimit)
    root.note:SetPoint("TOPLEFT", 20, -133)
    root.cancel = button(root, "Скасувати", 92, function()
        resetForm()
        addon.RefreshUI()
        status(root.status, true, "")
    end)
    root.cancel:SetPoint("LEFT", root.note, "RIGHT", 8, 0)
    root.guild = button(root, "Гільдія з цілі", 92, function() addon.PromptGuild("target") end)
    root.guild:SetPoint("LEFT", root.note, "RIGHT", 8, 0)
    root.name:SetScript("OnEnterPressed", submit)
    root.note:SetScript("OnEnterPressed", submit)
    root.name:SetScript("OnTabPressed", function() root.note:SetFocus() end)

    local list = CreateFrame("Frame", nil, root)
    list:SetPoint("TOPLEFT", 20, -190)
    list:SetPoint("TOPRIGHT", -20, -190)
    list:SetHeight(rowCount * rowHeight + 4)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        root.scroll:SetValue(root.scroll:GetValue() - delta)
    end)
    fill(list, color.inset, 0, 0)
    root.empty = label(list, "GameFontHighlight", color.muted)
    root.empty:SetPoint("CENTER")
    for index = 1, rowCount do
        local row = CreateFrame("Frame", nil, list)
        row:SetPoint("TOPLEFT", 2, -2 - (index - 1) * rowHeight)
        row:SetPoint("TOPRIGHT", -16, -2 - (index - 1) * rowHeight)
        row:SetHeight(rowHeight - 1)
        fill(row, index % 2 == 0 and color.inset or color.panel, 0, 0)
        row.name = label(row, "GameFontHighlight", color.white)
        row.name:SetPoint("TOPLEFT", 9, -5)
        row.name:SetWidth(286)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.note = label(row, "GameFontHighlightSmall", color.muted)
        row.note:SetPoint("TOPLEFT", 9, -20)
        row.note:SetWidth(286)
        row.note:SetJustifyH("LEFT")
        row.note:SetWordWrap(false)
        row.metadata = label(row, "GameFontHighlightSmall", color.muted)
        row.metadata:SetPoint("TOPLEFT", 9, -34)
        row.metadata:SetWidth(286)
        row.metadata:SetJustifyH("LEFT")
        row.metadata:SetWordWrap(false)
        row.deaths = label(row, "GameFontNormalLarge", color.gold)
        row.deaths:SetPoint("RIGHT", -183, 0)
        local remove = button(row, "Вилучити", 75, function()
            local entry = row.entry
            if panel.editing == entry then
                resetForm()
            end
            status(root.status, addon.Delete(entry.name, entry.kind))
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
    label(root, "GameFontHighlightSmall", color.muted, "Смерті"):SetPoint("TOPLEFT", 339, -175)
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
    root.share = button(root, "Поділитися переліком", 159, function() addon.PromptShare() end)
    root.share:SetPoint("BOTTOMRIGHT", -20, 18)
    root.status = label(root, "GameFontHighlightSmall", color.muted)
    root.status:SetPoint("BOTTOMLEFT", 20, 23)
    root.status:SetWidth(390)
    root.status:SetJustifyH("LEFT")
    root.status:SetMaxLines(2)
    root:SetScript("OnShow", addon.RefreshUI)
    root:SetScript("OnHide", function()
        root.name:ClearFocus()
        root.note:ClearFocus()
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
    if not panel.editing and panel.name:GetText() == "" then
        putTarget()
    end
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
    root.confirm = button(root, "", 98, submitDialog, true)
    root.confirm:SetPoint("BOTTOMRIGHT", -18, 13)
    root.cancel = button(root, "", 98, function() root:Hide() end)
    root.cancel:SetPoint("RIGHT", root.confirm, "LEFT", -7, 0)
    root.publish = button(root, "У чат гільдії", 125, function()
        local ok, message = addon.Publish()
        if ok then
            root:Hide()
            addon.Say(message)
        else
            status(root.status, false, message)
        end
    end)
    root.publish:SetPoint("BOTTOMLEFT", 18, 13)
    root:SetScript("OnHide", function()
        root.action = nil
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
    dialog:SetHeight(options.autocomplete and 339 or 190)
    dialog.status:ClearAllPoints()
    dialog.status:SetPoint("TOPLEFT", 18, options.autocomplete and -278 or -118)
    dialog.publish:SetShown(options.autocomplete == true)
    for _, choice in ipairs(dialog.suggestions) do
        choice:Hide()
    end
    dialog.field:SetShown(options.limit ~= nil)
    dialog.field:SetMaxBytes(options.limit or addon.NoteLimit)
    dialog.field:SetText(options.value or "")
    status(dialog.status, true, "")
    dialog.action = options.action
    dialog:Show()
    addon.RefreshSuggestions()
    if options.limit then
        dialog.field:SetFocus()
    end
    return true
end

function addon.PromptShare()
    local _, target = addon.UnitName("target")
    addon.RefreshRoster()
    openDialog({
        title = "Поділитися переліком",
        text = "Ім’я та прізвище гільдійця",
        value = target, limit = addon.NameLimit, confirm = "Надіслати", autocomplete = true,
        action = addon.Share,
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
            row.name:SetText(record.kind == "G" and "Гільдія: " .. record.name or record.name)
            local detail = not change.new and ("Смерті: %d"):format(record.deaths) or record.note
            row.detail:SetText(detail)
        end
    end
    local selected = 0
    for _ in pairs(offer.selected) do selected = selected + 1 end
    review.count:SetText(("Позначено %d з %d"):format(selected, #offer.changes))
    enabled(review.confirm, selected > 0)
end

local function selectAll(value)
    local offer = review.offer
    for _, change in ipairs(offer.changes) do
        offer.selected[change.key] = value and true or nil
    end
    renderReview()
end

local function createReview()
    local root = window("GrudgeBookReview", 516, 511, "FULLSCREEN_DIALOG")
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
    list:SetHeight(rowCount * 45 + 4)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        root.scroll:SetValue(root.scroll:GetValue() - delta)
    end)
    fill(list, color.inset, 0, 0)
    root.empty = label(list, "GameFontHighlight", color.muted, "Нових записів або лічильників до оновлення немає.")
    root.empty:SetPoint("CENTER")
    for index = 1, rowCount do
        local row = CreateFrame("Frame", nil, list)
        row:SetPoint("TOPLEFT", 2, -2 - (index - 1) * 45)
        row:SetPoint("TOPRIGHT", -17, -2 - (index - 1) * 45)
        row:SetHeight(44)
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
        row.name:SetWidth(405)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.detail = label(row, "GameFontHighlightSmall", color.muted)
        row.detail:SetPoint("TOPLEFT", 36, -23)
        row.detail:SetWidth(405)
        row.detail:SetJustifyH("LEFT")
        row.detail:SetWordWrap(false)
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
    root.count:SetPoint("TOPLEFT", 18, -418)
    button(root, "Позначити всі", 110, function() selectAll(true) end):SetPoint("BOTTOMLEFT", 18, 15)
    button(root, "Зняти всі", 83, function() selectAll(false) end):SetPoint("BOTTOMLEFT", 135, 15)
    root.confirm = button(root, "Прийняти", 102, function()
        local offer = root.offer
        local selected = {}
        for _, change in ipairs(offer.changes) do
            if offer.selected[change.key] then
                selected[change.key] = change.record
            end
        end
        root:Hide()
        offer.accept(selected)
    end, true)
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
    review.summary:SetText(("Нових записів: %d. Оновлень лічильника: %d."):format(offer.added, offer.updated))
    review.empty:SetShown(#offer.changes == 0)
    local maximum = math.max(0, #offer.changes - rowCount)
    review.scroll:SetMinMaxValues(0, maximum)
    review.scroll:SetValue(0)
    review.scroll:SetShown(maximum > 0)
    selectAll(true)
    review:Show()
end

function addon.OfferImport(sender, added, updated, changes, accept)
    if #offers < 10 then
        offers[#offers + 1] = { sender = sender, added = added, updated = updated, changes = changes, accept = accept }
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

local alertName, expiration, targetButton, skullButton
local alertWidth, alertOffset = 458, 105

local function secured(labelText, width, x)
    local control = button(UIParent, labelText, width, nil, true,
        "SecureActionButtonTemplate,SecureHandlerStateTemplate")
    control:SetPoint("CENTER", UIParent, "CENTER", x, alertOffset - 43)
    control:SetFrameStrata("HIGH")
    control:SetFrameLevel(toast:GetFrameLevel() + 4)
    control:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    control:SetAttribute("_onstate-grudgecombat", [[
        if newstate == "combat" then self:Hide() end
    ]])
    RegisterStateDriver(control, "grudgecombat", "[combat] combat; safe")
    return control
end

local function refreshAlertButtons()
    if InCombatLockdown() then
        return
    end
    if not alertName then
        if targetButton then
            targetButton:Hide()
            skullButton:Hide()
        end
        return
    end
    if not targetButton then
        -- Siblings keep the visual alert dismissible while protected buttons are locked.
        targetButton = secured("У ціль", 78, 78)
        targetButton:SetAttribute("type", "macro")
        skullButton = secured("Череп", 78, 167)
        skullButton:SetAttribute("type", "raidtarget")
        skullButton:SetAttribute("unit", "target")
        skullButton:SetAttribute("marker", 8)
        skullButton:SetAttribute("action", "set")
    end
    targetButton:SetAttribute("macrotext", "/targetexact " .. alertName)
    targetButton:Show()
    local key = addon.PlayerName(alertName)
    skullButton:SetShown(key ~= nil and key == addon.EnemyUnit("target"))
end

function addon.CloseAlert()
    alertName = nil
    if expiration then
        expiration:Cancel()
        expiration = nil
    end
    if toast then
        toast:Hide()
        refreshAlertButtons()
    end
end

local function createAlert()
    local root = window("GrudgeBookAlert", alertWidth, 132, "HIGH")
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 0, alertOffset)
    local stripe = root:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT", 1, -1)
    stripe:SetPoint("BOTTOMLEFT", 1, 1)
    stripe:SetWidth(5)
    stripe:SetColorTexture(unpack(color.red))
    root.heading = label(root, "GameFontHighlightSmall", color.red)
    root.heading:SetPoint("TOPLEFT", 17, -12)
    root.name = label(root, "GameFontNormalHuge", color.red)
    root.name:SetPoint("TOPLEFT", 17, -29)
    root.name:SetWidth(400)
    root.name:SetJustifyH("LEFT")
    root.name:SetWordWrap(false)
    root.note = label(root, "GameFontHighlight", color.white)
    root.note:SetPoint("TOPLEFT", 17, -60)
    root.note:SetWidth(419)
    root.note:SetJustifyH("LEFT")
    root.note:SetMaxLines(2)
    button(root, "×", 26, addon.CloseAlert):SetPoint("TOPRIGHT", -10, -9)
    root:RegisterEvent("PLAYER_REGEN_ENABLED")
    root:RegisterEvent("PLAYER_TARGET_CHANGED")
    root:SetScript("OnEvent", refreshAlertButtons)
    return root
end

function addon.ShowAlert(entry, preview)
    if not toast then
        toast = createAlert()
    end
    if expiration then
        expiration:Cancel()
    end
    alertName = not preview and entry.name or nil
    toast.heading:SetText(preview and "ПЕРЕВІРКА ТРИВОГИ" or "GRUDGEBOOK / ВОРОГ ПОРУЧ")
    toast.name:SetText(entry.name)
    toast.note:SetText(entry.note)
    toast:Show()
    refreshAlertButtons()
    PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    expiration = C_Timer.NewTimer(12, addon.CloseAlert)
end
