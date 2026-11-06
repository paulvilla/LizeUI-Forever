local addonName = "LizeUI"
local _, ns = ...
local addon = CreateFrame("Frame")
local NavRoute = ns and ns.NavRoute
local Utilities = ns and ns.Utilities

local function initDatabase()
    if type(LizeUIDB) ~= "table" then
        if type(LoadProfilesDB) == "table" then
            LizeUIDB = LoadProfilesDB
        else
            LizeUIDB = {}
        end
    end
    LoadProfilesDB = LizeUIDB
    if LizeUIDB.modifyDialogueUICameraOffset == nil then
        LizeUIDB.modifyDialogueUICameraOffset = false
    end
    if LizeUIDB.dialogueUICameraOffset == nil then
        LizeUIDB.dialogueUICameraOffset = 0
    end
    if LizeUIDB.eliminarBotonIssueReport == nil then
        LizeUIDB.eliminarBotonIssueReport = true
    end
    if LizeUIDB.marcosIconosBuffDebuff == nil then
        LizeUIDB.marcosIconosBuffDebuff = true
    end
    if LizeUIDB.devMode == nil then
        LizeUIDB.devMode = false
    end
    for _, module in ipairs({ NavRoute, Utilities }) do
        if module and module.defaults then
            for key, value in pairs(module.defaults) do
                if LizeUIDB[key] == nil then
                    LizeUIDB[key] = value
                end
            end
        end
    end
    return LizeUIDB
end

local database = setmetatable({}, {
    __index = function(_, k)
        return initDatabase()[k]
    end,
    __newindex = function(_, k, v)
        initDatabase()[k] = v
    end
})

local isAddonLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
local infoInstanciaButton

-- Datos exportados de DB2: MapDifficulty (MapID -> ContentTuningID)
-- Agrega mas instancias aqui cuando las extraigas de la DB2
local mapDifficultyLookup = {
    [2999] = 5256, -- Deadmines
}

-- Datos exportados de DB2: LFGDungeons (ContentTuningID -> Name_Lang)
-- Solo como fallback si GetLFGDungeonInfo no devuelve nada
local lfgDungeonsLookup = {
    [5256] = "Deadmines",
}

local function printMessage(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffLizeUI|r: " .. message)
end

local function importProfile(addonTableName, importFunction, profile, label)
    if not profile then
        printMessage("No se encontro el perfil de " .. label .. ".")
        return
    end

    local addonTable = _G[addonTableName]
    if not addonTable or type(addonTable.OldImportProfile) ~= "function" then
        printMessage(label .. " no esta cargado o no expone su importador.")
        return
    end

    local success, imported, errorMessage = pcall(function()
        local profileData, importError = addonTable.OldImportProfile(profile, "fullProfile")
        if importError then
            return false, importError
        end
        if type(profileData) ~= "table" then
            return false, "el perfil no contiene una configuracion valida"
        end

        local databaseName = addonTableName == "BBP" and "BetterBlizzPlatesDB" or "BetterBlizzFramesDB"
        local database = _G[databaseName] or {}
        for key in pairs(database) do
            database[key] = nil
        end
        for key, value in pairs(profileData) do
            database[key] = value
        end
        _G[databaseName] = database
        return true
    end)
    if not success then
        printMessage("Error al importar " .. label .. ": " .. tostring(imported))
    elseif imported == false then
        printMessage("Error al importar " .. label .. ": " .. tostring(errorMessage or "cadena no valida"))
    else
        printMessage("Perfil de " .. label .. " importado correctamente.")
    end
end

local detailsProfileName = "LizeUI"

local function importDetailsProfile()
    local profile = LoadProfilesDetails
    if not profile then
        printMessage("No se encontro el perfil de Details.")
        return
    end

    local details = _G.Details or _G._detalhes
    if not details or type(details.ImportProfile) ~= "function" then
        printMessage("Details no esta cargado o no expone su importador.")
        return
    end

    -- ImportProfile(cadena, nombre, importarAutoRun, desdePrompt, sobrescribir)
    local success, result = pcall(details.ImportProfile, details, profile, detailsProfileName, false, false, true)
    if not success then
        printMessage("Error al importar Details: " .. tostring(result))
    elseif not result then
        printMessage("Error al importar Details: cadena no valida")
    else
        printMessage("Perfil de Details (" .. detailsProfileName .. ") importado correctamente.")
    end
end

local window = CreateFrame("Frame", "LoadProfilesWindow", UIParent, "PortraitFrameTemplate")
window:SetSize(500, 340)
window:SetPoint("CENTER")
window:SetFrameStrata("DIALOG")
window:SetTitleOffsets(0, 0)
window:SetBorder("HeldBagLayout")
window:SetPortraitTextureSizeAndOffset(38, -5, 0)
window:SetPortraitTextureRaw(133642)
window:SetMovable(true)
window:EnableMouse(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", window.StartMoving)
window:SetScript("OnDragStop", window.StopMovingOrSizing)
window:Hide()

window.title = window.TitleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
window.title:SetPoint("LEFT", window.TitleContainer, "LEFT", 40, 0)
window.title:SetText("LizeUI")
window.CloseButton:SetScript("OnClick", function()
    window:Hide()
end)

local description = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
description:SetPoint("TOP", window, "TOP", 0, -58)
description:SetText("Selecciona una configuracion para importarla")

local function createProfileButton(name, anchor, onClick)
    local button = CreateFrame("Button", nil, window, "SharedButtonTemplate")
    button:SetSize(214, 48)
    button:SetPoint(unpack(anchor))
    button:SetText(name)
    button:SetScript("OnClick", onClick)
    return button
end

createProfileButton("BetterBlizzFrames", { "BOTTOMLEFT", 26, 75 }, function()
    importProfile("BBF", "ImportProfile", LoadProfilesBetterBlizzFrames, "BetterBlizzFrames")
end)

createProfileButton("BetterBlizzPlates", { "BOTTOMRIGHT", -26, 75 }, function()
    importProfile("BBP", "ImportProfile", LoadProfilesBetterBlizzPlater, "BetterBlizzPlates")
end)

createProfileButton("Details", { "BOTTOM", 0, 130 }, importDetailsProfile)

createProfileButton("Reload", { "BOTTOM", 0, 25 }, function()
    database.windowOpened = true
    ReloadUI()
end)

local function createSettingsPanel(name, parent)
    local panel = CreateFrame("Frame")
    panel.name = name
    panel.parent = parent
    panel.OnCommit = function() end
    panel.OnDefault = function() end
    panel.OnRefresh = function() end
    return panel
end

local function createDivider(panel, title, yOffset)
    local leftLine = panel:CreateTexture(nil, "ARTWORK")
    leftLine:SetColorTexture(0.5, 0.5, 0.5, 0.6)
    leftLine:SetHeight(1)
    leftLine:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, yOffset)
    leftLine:SetPoint("RIGHT", panel, "TOP", -55, yOffset)

    local rightLine = panel:CreateTexture(nil, "ARTWORK")
    rightLine:SetColorTexture(0.5, 0.5, 0.5, 0.6)
    rightLine:SetHeight(1)
    rightLine:SetPoint("TOPLEFT", panel, "TOP", 55, yOffset)
    rightLine:SetPoint("RIGHT", panel, "TOPRIGHT", -20, yOffset)

    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOP", panel, "TOP", 0, yOffset + 5)
    label:SetText(title)
end

local function createSettingsButton(panel, text, width, point, onClick)
    local button = CreateFrame("Button", nil, panel, "SharedButtonTemplate")
    button:SetSize(width, 48)
    button:SetPoint(unpack(point))
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function createSettingsCheckbox(panel, text, optionIndex, databaseKey)
    local checkbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    local column = (optionIndex - 1) % 2
    local row = math.floor((optionIndex - 1) / 2)
    checkbox:SetPoint("TOPLEFT", panel, "TOPLEFT", 35 + column * 320, -45 - row * 35)

    local function refresh()
        checkbox:SetChecked(database[databaseKey] == true)
    end
    refresh()

    checkbox:SetScript("OnClick", function(self)
        database[databaseKey] = self:GetChecked()
    end)

    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetFontObject("GameFontNormal")
    label:SetPoint("LEFT", checkbox, "RIGHT", 8, 0)
    label:SetText(text)

    checkbox.Refresh = refresh
    return checkbox
end

local function createSettingsCheckboxCustom(panel, text, point, databaseKey, onToggle)
    local checkbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    checkbox:SetPoint(unpack(point))

    local function refresh()
        checkbox:SetChecked(database[databaseKey] == true)
    end
    refresh()

    checkbox:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()
        database[databaseKey] = isChecked
        if onToggle then
            onToggle(isChecked)
        end
    end)

    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetFontObject("GameFontNormal")
    label:SetPoint("LEFT", checkbox, "RIGHT", 8, 0)
    label:SetText(text)

    checkbox.Refresh = refresh
    return checkbox, label
end

local function createSettingsSlider(panel, name, minVal, maxVal, step, defaultVal, point, databaseKey, onValueChanged, decimals, displayFormat, unsigned)
    decimals = decimals or 0
    displayFormat = displayFormat or "Desplazamiento: %s"

    local slider = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
    slider:SetPoint(unpack(point))
    slider:SetSize(180, 17)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    local lowText = _G[slider:GetName() .. "Low"] or slider.Low
    local highText = _G[slider:GetName() .. "High"] or slider.High
    local titleText = _G[slider:GetName() .. "Text"] or slider.Text

    if lowText then
        lowText:SetText(tostring(minVal))
        lowText:ClearAllPoints()
        lowText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 2, -4)
    end
    if highText then
        highText:SetText((unsigned and "" or "+") .. tostring(maxVal))
        highText:ClearAllPoints()
        highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", -2, -4)
    end

    local valueDisplay = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueDisplay:SetPoint("BOTTOM", slider, "TOP", 0, 4)

    local function formatValue(val)
        if decimals > 0 then
            return string.format("%." .. decimals .. "f", val)
        end
        if val > 0 and not unsigned then
            return "+" .. val
        else
            return tostring(val)
        end
    end

    local isUpdatingValue = false

    local function refresh()
        local currentVal = database[databaseKey]
        if currentVal == nil then
            currentVal = defaultVal
            database[databaseKey] = currentVal
        else
            currentVal = tonumber(currentVal) or defaultVal
        end
        isUpdatingValue = true
        slider:SetValue(currentVal)
        isUpdatingValue = false
        valueDisplay:SetText(string.format(displayFormat, formatValue(currentVal)))
    end
    refresh()

    if titleText then
        titleText:SetText("")
    end

    slider:SetScript("OnValueChanged", function(self, value)
        if decimals > 0 then
            local mult = 10 ^ decimals
            value = math.floor(value * mult + 0.5) / mult
        else
            value = math.floor(value + 0.5)
        end
        if not isUpdatingValue then
            database[databaseKey] = value
        end
        valueDisplay:SetText(string.format(displayFormat, formatValue(value)))
        if onValueChanged and not isUpdatingValue then
            onValueChanged(value)
        end
    end)

    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(self, delta)
        if not self:IsEnabled() then return end
        local cur = self:GetValue()
        local minV, maxV = self:GetMinMaxValues()
        local newV = math.max(minV, math.min(maxV, cur + delta * step))
        self:SetValue(newV)
    end)

    return slider, valueDisplay
end

local function notifyDialogueUI()
    if DialogueUIAPI and type(DialogueUIAPI.UpdateCameraShoulderOffset) == "function" then
        DialogueUIAPI.UpdateCameraShoulderOffset()
    end
end

local function updateIssueReportButton(hidden)
    local frames = {
        "PTR_IssueReporter",
        "PTRIssueReporterAlertFrame",
    }
    for _, name in ipairs(frames) do
        local frame = _G[name]
        if frame then
            if hidden then
                frame:Hide()
                -- Hook para que si el frame intenta mostrarse, se vuelva a ocultar
                if not frame.lizeUIHooked then
                    frame.lizeUIHooked = true
                    hooksecurefunc(frame, "Show", function(self)
                        if database.eliminarBotonIssueReport then
                            self:Hide()
                        end
                    end)
                end
            else
                frame:Show()
            end
        end
    end
end

-- En combate Blizzard marca sus botones nativos de auras como "forbidden":
-- llamar a cualquier metodo sobre ellos desde codigo de addon lanza error.
-- IsForbidden() es el unico metodo permitido desde codigo inseguro.
local function isForbiddenFrame(frame)
    if not frame then return false end
    local ok, forbidden = pcall(function()
        return frame.IsForbidden and frame:IsForbidden() or false
    end)
    return ok and forbidden == true
end

-- Color de los marcos de auras de LizeUI. Sin Dark Mode: gris neutro (buffs)
-- y rojo (debuffs). Con Dark Mode: se oscurecen segun la intensidad elegida
-- (darkModeColor de BBF, 0 = negro, 1 = sin oscurecer). Los debuffs mantienen
-- el tono rojo, con un minimo de brillo para que sigan distinguiendose.
local function getAuraBorderColor(isDebuff)
    local db = BetterBlizzFramesDB
    local dark = db and db.darkModeUi
    local v = dark and ((tonumber(db.darkModeColor)) or 0.20) or nil
    if isDebuff then
        if not v then return 1, 0.15, 0.15 end
        local f = math.max(v, 0.35)
        return f, 0.15 * f, 0.15 * f
    end
    if not v then return 0.75, 0.75, 0.75 end
    v = math.min(v, 0.75)
    return v, v, v
end

local function updateBuffDebuffBorders(enabled)
    -- Asegurar que BBF muestre/oculte los bordes de debuff
    if BetterBlizzFramesDB then
        local changed = false
        if enabled then
            if BetterBlizzFramesDB.removeDebuffColorBorder ~= false then
                BetterBlizzFramesDB.removeDebuffColorBorder = false
                changed = true
            end
        else
            if BetterBlizzFramesDB.removeDebuffColorBorder ~= true then
                BetterBlizzFramesDB.removeDebuffColorBorder = true
                changed = true
            end
        end
        if changed and BBF and BBF.RefreshAllAuraFrames then
            BBF.RefreshAllAuraFrames()
        end
    end

    local function applyBorderToButtonUnsafe(button, isDebuff)
        local anchor = button.bbfIcon or button
        -- Recrear la textura siempre para evitar que atlas/texture se queden pegados
        if button.lizeUIBorder then
            button.lizeUIBorder:Hide()
            button.lizeUIBorder = nil
        end
        local border = button:CreateTexture(nil, "OVERLAY", nil, 7)
        border:SetPoint("CENTER", anchor, "CENTER", 0, 0)
        border:SetAtlas("Adventures-Spell-Border")
        button.lizeUIBorder = border
        button.lizeUIBorder:SetSize(35, 35)
        if isDebuff then
            if enabled then
                if button.Border then button.Border:Hide() end
                if button.bbfDispel then button.bbfDispel:Hide() end
                if button.bbfBorder then button.bbfBorder:Hide() end
            else
                if button.Border then button.Border:Show() end
            end
            -- Debuffs: rojo puro brillante (desaturar primero para quitar tonos oscuros)
            button.lizeUIBorder:SetDesaturated(true)
            button.lizeUIBorder:SetVertexColor(getAuraBorderColor(true))
        else
            -- Buffs: gris neutro (oscurecido si Dark Mode esta activo)
            button.lizeUIBorder:SetDesaturated(BetterBlizzFramesDB and BetterBlizzFramesDB.darkModeUi and true or false)
            button.lizeUIBorder:SetVertexColor(getAuraBorderColor(false))
        end
        -- Recortar el icono para que no se asome por las esquinas redondeadas
        if enabled then
            if button.bbfIcon and not button.lizeUIOldTexCoord then
                button.lizeUIOldTexCoord = {button.bbfIcon:GetTexCoord()}
            end
            if button.bbfIcon then
                button.bbfIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
        else
            if button.bbfIcon and button.lizeUIOldTexCoord then
                local t = button.lizeUIOldTexCoord
                if #t == 4 then
                    button.bbfIcon:SetTexCoord(t[1], t[2], t[3], t[4])
                elseif #t == 8 then
                    button.bbfIcon:SetTexCoord(t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8])
                end
            end
        end
        button.lizeUIBorder:SetShown(enabled)
    end

    local function applyBorderToButton(button, isDebuff)
        if not button or isForbiddenFrame(button) then return end
        -- En combate el boton (y sus hijos, incluida nuestra textura) pueden
        -- quedar prohibidos a mitad de operacion: pcall evita romper el
        -- restyle de BBF; el borde creado fuera de combate sigue visible.
        pcall(applyBorderToButtonUnsafe, button, isDebuff)
    end

    -- Botones nativos legacy (Classic antiguo)
    for i = 1, 32 do
        local btn = _G["BuffButton" .. i]
        if btn then applyBorderToButton(btn, false) end
    end
    for i = 1, 16 do
        local btn = _G["DebuffButton" .. i]
        if btn then applyBorderToButton(btn, true) end
    end

    -- Botones nativos modernos (AuraContainer / mainline backport)
    if BuffFrame and BuffFrame.auraFrames then
        for _, btn in ipairs(BuffFrame.auraFrames) do
            applyBorderToButton(btn, false)
        end
    end
    if DebuffFrame and DebuffFrame.auraFrames then
        for _, btn in ipairs(DebuffFrame.auraFrames) do
            applyBorderToButton(btn, true)
        end
    end

    -- Botones custom de BetterBlizzFrames
    if BBF and BBF.auraHosts then
        for _, key in ipairs({"playerBuffs", "playerDebuffs"}) do
            local host = BBF.auraHosts[key]
            local isDebuff = key == "playerDebuffs"
            if host then
                for _, containerKey in ipairs({"spacer", "blockTop", "blockBottom"}) do
                    local container = host[containerKey]
                    if container and container.bbfStyles then
                        for styleKey in pairs(container.bbfStyles) do
                            local count = container:HasAuraGroup(styleKey) and container:GetAuraGroupFrameCount(styleKey) or 0
                            for i = 1, count do
                                local button = container:GetAuraGroupFrame(styleKey, i)
                                if button then applyBorderToButton(button, isDebuff) end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Limpiar registros de dispel de Blizzard para que no repinte bordes gruesos
    if enabled then
        for i = 1, 16 do
            local btn = _G["DebuffButton" .. i]
            if btn and not isForbiddenFrame(btn) and btn.ClearDispelTypeTextures then
                pcall(btn.ClearDispelTypeTextures, btn)
            end
        end
        if BuffFrame and BuffFrame.auraFrames then
            for _, btn in ipairs(BuffFrame.auraFrames) do
                if btn and not isForbiddenFrame(btn) and btn.ClearDispelTypeTextures then
                    pcall(btn.ClearDispelTypeTextures, btn)
                end
            end
        end
        if DebuffFrame and DebuffFrame.auraFrames then
            for _, btn in ipairs(DebuffFrame.auraFrames) do
                if btn and not isForbiddenFrame(btn) and btn.ClearDispelTypeTextures then
                    pcall(btn.ClearDispelTypeTextures, btn)
                end
            end
        end
        if BBF and BBF.auraHosts and BBF.auraHosts.playerDebuffs then
            local host = BBF.auraHosts.playerDebuffs
            for _, containerKey in ipairs({"spacer", "blockTop", "blockBottom"}) do
                local container = host[containerKey]
                if container and container.bbfStyles then
                    for styleKey in pairs(container.bbfStyles) do
                        local count = container:HasAuraGroup(styleKey) and container:GetAuraGroupFrameCount(styleKey) or 0
                        for i = 1, count do
                            local button = container:GetAuraGroupFrame(styleKey, i)
                            if button and not isForbiddenFrame(button) and button.ClearDispelTypeTextures then
                                pcall(button.ClearDispelTypeTextures, button)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function updateTargetAuraBorders(enabled)
    local function applyTargetBorderUnsafe(button, isDebuff)
        local icon = button.bbfIcon or button.Icon or button.icon
        local anchor = icon or button
        local borderSize = 35
        -- Calcular tamaño una sola vez por botón para evitar que crezca en refrescos
        if not button.lizeUITargetBorderSize then
            local function safeGetSize(obj)
                if not obj or not obj.GetWidth then return nil end
                local w, h = obj:GetWidth(), obj:GetHeight()
                local ok = pcall(function() return (w or 0) + 0, (h or 0) + 0 end)
                if ok and w and h then
                    return math.max(w, h) + 4
                end
                return nil
            end
            local calculated = safeGetSize(icon) or safeGetSize(button)
            button.lizeUITargetBorderSize = calculated or (button.bbfIcon and 35 or 25)
        end
        borderSize = button.lizeUITargetBorderSize

        if button.lizeUITargetBorder then
            button.lizeUITargetBorder:Hide()
            button.lizeUITargetBorder:SetParent(nil)
            button.lizeUITargetBorder = nil
        end

        local border = button:CreateTexture(nil, "ARTWORK", nil, 7)
        border:SetPoint("CENTER", anchor, "CENTER", 0, 0)
        border:SetAtlas("Adventures-Spell-Border")
        button.lizeUITargetBorder = border
        button.lizeUITargetBorder:SetSize(borderSize, borderSize)

        if enabled then
            if button.Border then button.Border:Hide() end
        else
            if button.Border then button.Border:Show() end
        end

        -- Gris neutro (oscurecido segun la intensidad si Dark Mode esta activo)
        button.lizeUITargetBorder:SetDesaturated(BetterBlizzFramesDB and BetterBlizzFramesDB.darkModeUi and true or false)
        button.lizeUITargetBorder:SetVertexColor(getAuraBorderColor(false))

        if enabled then
            if icon and icon.GetTexCoord and not button.lizeUITargetOldTexCoord then
                button.lizeUITargetOldTexCoord = {icon:GetTexCoord()}
            end
            if icon and icon.SetTexCoord then
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
        else
            if icon and button.lizeUITargetOldTexCoord then
                local t = button.lizeUITargetOldTexCoord
                if #t == 4 then
                    icon:SetTexCoord(t[1], t[2], t[3], t[4])
                elseif #t == 8 then
                    icon:SetTexCoord(t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8])
                end
            end
        end

        button.lizeUITargetBorder:SetShown(enabled)
    end

    local function applyTargetBorder(button, isDebuff)
        if not button or isForbiddenFrame(button) then return end
        -- Misma proteccion que en buffs: en combate el boton y sus hijos
        -- pueden quedar prohibidos a mitad de operacion.
        pcall(applyTargetBorderUnsafe, button, isDebuff)
    end

    local targetFrame = TargetFrame
    if not targetFrame then return end

    -- Auras nativas de Blizzard (AuraContainer moderno / mainline backport)
    local auraContainer = targetFrame.GetAuraContainer and targetFrame:GetAuraContainer()
    if auraContainer then
        local buffFrames = auraContainer.buffFrames
        local debuffFrames = auraContainer.debuffFrames

        if buffFrames then
            for _, btn in ipairs(buffFrames) do
                applyTargetBorder(btn, false)
            end
        end
        if debuffFrames then
            for _, btn in ipairs(debuffFrames) do
                applyTargetBorder(btn, true)
            end
        end

        -- Fallback: si no hay arrays separados, iterar hijos
        if not buffFrames and not debuffFrames then
            local children = {auraContainer:GetChildren()}
            for _, btn in ipairs(children) do
                local okChild, isButton = pcall(function()
                    return not isForbiddenFrame(btn) and (btn:IsObjectType("Frame") or btn:IsObjectType("Button"))
                end)
                if okChild and isButton then
                    local isDebuff = btn.auraType == "DEBUFF" or btn.auraType == "HARMFUL"
                    applyTargetBorder(btn, isDebuff)
                end
            end
        end
    end

    -- Auras custom de BetterBlizzFrames
    if BBF and BBF.auraHosts and BBF.auraHosts.target then
        local host = BBF.auraHosts.target
        for _, containerKey in ipairs({"spacer", "blockTop", "blockBottom"}) do
            local container = host[containerKey]
            if container and container.bbfStyles then
                local isDebuff = (containerKey == "blockTop") -- blockTop = harmful/debuffs
                for styleKey in pairs(container.bbfStyles) do
                    local count = container:HasAuraGroup(styleKey) and container:GetAuraGroupFrameCount(styleKey) or 0
                    for i = 1, count do
                        local button = container:GetAuraGroupFrame(styleKey, i)
                        if button then applyTargetBorder(button, isDebuff) end
                    end
                end
            end
        end
    end

    if enabled then
        local auraContainer = targetFrame.GetAuraContainer and targetFrame:GetAuraContainer()
        if auraContainer and auraContainer.debuffFrames then
            for _, btn in ipairs(auraContainer.debuffFrames) do
                if btn and not isForbiddenFrame(btn) and btn.ClearDispelTypeTextures then
                    pcall(btn.ClearDispelTypeTextures, btn)
                end
            end
        end
    end
end

-- Replica de la logica de colores de BBF.DarkmodeFrames para action bars
local function getDarkActionBarColors()
    local v = (BetterBlizzFramesDB and tonumber(BetterBlizzFramesDB.darkModeColor)) or 0.20
    if v == 0 then
        return 0, 0.2
    end
    return v + 0.15, v + 0.25
end

-- BBF instala hooks de SetVertexColor que capturan el color viejo y revierten
-- cualquier cambio posterior. No podemos controlar el orden de la cadena de
-- hooks, asi que este hook programa la correccion para justo despues de que
-- termine la cadena (C_Timer 0) y usa la propia flag "changing" de BBF para
-- neutralizar su hook mientras aplicamos el color actual de la DB.
-- Texturas pendientes de correccion; se procesan todas juntas en UN solo
-- timer por frame como maximo, en vez de un timer por textura.
local darkDirtyTextures = {}
local darkDirtyScheduled = false

local function lizeDarkActionBarHook(self)
    if self.lizeUIDarkChanging then return end
    local db = BetterBlizzFramesDB
    if not db then return end
    if not (db.darkModeUi and db.darkModeActionBars) and not self.lizeUIDarkTinted then return end
    darkDirtyTextures[self] = true
    if darkDirtyScheduled then return end
    darkDirtyScheduled = true
    C_Timer.After(0, function()
        darkDirtyScheduled = false
        local dbNow = BetterBlizzFramesDB
        local on = dbNow and dbNow.darkModeUi and dbNow.darkModeActionBars
        local barColor, birdColor = getDarkActionBarColors()
        for tex in pairs(darkDirtyTextures) do
            darkDirtyTextures[tex] = nil
            tex.lizeUIDarkChanging = true
            tex.changing = true -- neutraliza el hook viejo de BBF
            if on then
                local color = tex.lizeUIDarkBird and birdColor or barColor
                if tex.SetDesaturated then
                    tex:SetDesaturated(true)
                end
                tex:SetVertexColor(color, color, color)
                tex.lizeUIDarkTinted = true
            else
                if tex.SetDesaturated then
                    tex:SetDesaturated(false)
                end
                tex:SetVertexColor(1, 1, 1)
                tex.lizeUIDarkTinted = false
            end
            tex.changing = false
            tex.lizeUIDarkChanging = false
        end
    end)
end

local function refreshDarkActionBarTexture(texture, isBird)
    if not texture or not texture.SetVertexColor then return end
    local ok, forbidden = pcall(function()
        return (issecretvalue and issecretvalue(texture)) or (texture.IsForbidden and texture:IsForbidden()) or false
    end)
    if not ok or forbidden then return end
    local db = BetterBlizzFramesDB
    local on = db and db.darkModeUi and db.darkModeActionBars
    if not on and not texture.lizeUIDarkTinted then return end
    texture.lizeUIDarkBird = isBird and true or false
    if not texture.lizeUIDarkHooked then
        texture.lizeUIDarkHooked = true
        hooksecurefunc(texture, "SetVertexColor", lizeDarkActionBarHook)
    end
    -- Aplica el color directamente neutralizando el hook viejo de BBF con su
    -- propia flag "changing" durante la operacion.
    texture.lizeUIDarkChanging = true
    texture.changing = true
    if on then
        local barColor, birdColor = getDarkActionBarColors()
        local color = isBird and birdColor or barColor
        if texture.SetDesaturated then
            texture:SetDesaturated(true)
        end
        texture:SetVertexColor(color, color, color)
        texture.lizeUIDarkTinted = true
    else
        if texture.SetDesaturated then
            texture:SetDesaturated(false)
        end
        texture:SetVertexColor(1, 1, 1)
        texture.lizeUIDarkTinted = false
    end
    texture.changing = false
    texture.lizeUIDarkChanging = false
end

-- Recorre los mismos frames que BBF.ApplyActionBarArt tine con hook=true
local function syncDarkActionBars()
    if not BetterBlizzFramesDB then return end

    local mainActionBar = _G.MainMenuBar or _G.MainActionBar

    -- Bordes de botones de accion (NormalTexture)
    local buttonPrefixes = {
        "ActionButton",
        "MultiBarBottomLeftButton",
        "MultiBarBottomRightButton",
        "MultiBarRightButton",
        "MultiBarLeftButton",
        "MultiBar5Button",
        "MultiBar6Button",
        "MultiBar7Button",
        "PetActionButton",
        "StanceButton",
    }
    for _, prefix in ipairs(buttonPrefixes) do
        for i = 1, 12 do
            local button = _G[prefix .. i]
            -- API moderna: la textura es un campo del boton (ActionButton1.NormalTexture)
            if button then
                refreshDarkActionBarTexture(button.NormalTexture)
            end
            -- Fallback clientes antiguos: textura global con nombre
            refreshDarkActionBarTexture(_G[prefix .. i .. "NormalTexture"])
        end
    end

    -- Divisores entre botones de la barra principal
    for i = 1, 11 do
        local button = _G["ActionButton" .. i]
        refreshDarkActionBarTexture(button and button.RightDivider)
    end

    -- Arte de la barra principal y grifos (EndCaps)
    if mainActionBar then
        refreshDarkActionBarTexture(mainActionBar.BorderArt)
        if mainActionBar.EndCaps then
            for _, cap in ipairs({mainActionBar.EndCaps.LeftEndCap, mainActionBar.EndCaps.RightEndCap}) do
                -- La cap puede ser una Texture directa o un Frame con .Texture
                refreshDarkActionBarTexture(cap, true)
                refreshDarkActionBarTexture(cap and cap.Texture, true)
                -- O un Frame con regiones Texture sin nombre
                if cap and cap.GetRegions then
                    for _, region in ipairs({cap:GetRegions()}) do
                        if region:IsObjectType("Texture") then
                            refreshDarkActionBarTexture(region, true)
                        end
                    end
                end
            end
        end
    end
    -- Fallback clientes clasicos: texturas globales de los remates
    refreshDarkActionBarTexture(_G["MainMenuBarLeftEndCap"], true)
    refreshDarkActionBarTexture(_G["MainMenuBarRightEndCap"], true)

    -- Botones de bolsas
    local function refreshButtonArt(button, buttonName)
        if not button then return end
        if button.GetNormalTexture then
            local ok, tex = pcall(button.GetNormalTexture, button)
            if ok then refreshDarkActionBarTexture(tex) end
        end
        if button.GetPushedTexture then
            local ok, tex = pcall(button.GetPushedTexture, button)
            if ok then refreshDarkActionBarTexture(tex) end
        end
        if buttonName then
            refreshDarkActionBarTexture(_G[buttonName .. "NormalTexture"])
            refreshDarkActionBarTexture(_G[buttonName .. "PushedTexture"])
        end
        refreshDarkActionBarTexture(button.NormalTexture)
        refreshDarkActionBarTexture(button.PushedTexture)
        refreshDarkActionBarTexture(button.Background)
        refreshDarkActionBarTexture(button.PushedBackground)
    end

    -- Micro menu
    if MicroMenu then
        refreshDarkActionBarTexture(MicroMenu.BorderArt)
    end
    for _, microButtonName in ipairs({
        "CharacterMicroButton", "ProfessionMicroButton", "SpellbookMicroButton",
        "TalentMicroButton", "LegacyMicroButton", "QuestLogMicroButton",
        "GuildMicroButton", "LFDMicroButton", "CollectionsMicroButton",
        "HelpMicroButton", "StoreMicroButton", "MainMenuMicroButton",
    }) do
        local button = _G[microButtonName]
        if button then
            refreshDarkActionBarTexture(button.Background)
            refreshDarkActionBarTexture(button.PushedBackground)
        end
    end

    -- Barra de bolsas
    local function refreshEdgeArt(frame)
        if not frame then return end
        refreshDarkActionBarTexture(frame.TopEdge)
        refreshDarkActionBarTexture(frame.BottomEdge)
        refreshDarkActionBarTexture(frame.Center)
    end
    if BagsBar then
        refreshDarkActionBarTexture(BagsBar.BorderArt)
        refreshEdgeArt(BagsBar)
        for _, child in pairs({BagsBar:GetChildren()}) do
            refreshEdgeArt(child)
            for _, grandChild in pairs({child:GetChildren()}) do
                refreshEdgeArt(grandChild)
            end
        end
    end

    refreshButtonArt(KeyRingButton, "KeyRingButton")
    refreshButtonArt(MainMenuBarBackpackButton, "MainMenuBarBackpackButton")
    refreshButtonArt(CharacterReagentBag0Slot, "CharacterReagentBag0Slot")
    for i = 0, 3 do
        local bagSlotName = "CharacterBag" .. i .. "Slot"
        refreshButtonArt(_G[bagSlotName], bagSlotName)
    end
end

local function applyDarkModeSettings(light)
    if not BetterBlizzFramesDB then return end
    -- El Dark Mode de BBF tambien dibuja marcos en buffs/debuffs (darkModeUiAura,
    -- activo por defecto). Los marcos de auras los gestiona solo la opcion
    -- "Marcos iconos buff / Debuff" de LizeUI, asi que se desactiva siempre.
    local auraBordersRemoved = false
    if BetterBlizzFramesDB.darkModeUiAura ~= false then
        BetterBlizzFramesDB.darkModeUiAura = false
        auraBordersRemoved = true
    end
    if BBF then
        if BBF.UpdateUserDarkModeSettings then
            BBF.UpdateUserDarkModeSettings()
        end
        if BBF.DarkmodeFrames then
            BBF.DarkmodeFrames(true)
        end
        if BetterBlizzFramesDB.darkModeUi then
            if BBF.DarkModeCastbars then
                BBF.DarkModeCastbars()
            end
            -- Estas solo hacen falta al activar/desactivar o en la carga, no en
            -- cada tick del slider (DarkModeUnitframeBorders re-estiliza auras)
            if not light then
                if BBF.DarkModeUnitframeBorders then
                    BBF.DarkModeUnitframeBorders()
                end
                if BBF.CheckForAuraBorders then
                    BBF.CheckForAuraBorders()
                end
                if BBF.updateTotemBorders then
                    BBF.updateTotemBorders()
                end
            end
        end
        -- Limpia los marcos de auras que BBF hubiera creado antes del cambio
        if auraBordersRemoved then
            if BBF.DarkModeUnitframeBorders then
                BBF.DarkModeUnitframeBorders()
            elseif BBF.RefreshAllAuraFrames then
                BBF.RefreshAllAuraFrames()
            end
            if BBF.DarkModeBuffCollapseButton then
                BBF.DarkModeBuffCollapseButton()
            end
        end
    end
    -- Repintar los marcos de auras de LizeUI con el color del Dark Mode.
    -- Si "Marcos iconos buff / Debuff" esta desactivado no hay marcos que tocar.
    if database.marcosIconosBuffDebuff then
        updateBuffDebuffBorders(true)
        updateTargetAuraBorders(true)
    end
    syncDarkActionBars()
end

-- El slider aplica con debounce: solo se refresca la UI cuando el usuario deja
-- de moverlo, evitando decenas de aplicaciones completas por arrastre.
local darkModeApplyTimer
local function queueDarkModeApply()
    if darkModeApplyTimer then
        darkModeApplyTimer:Cancel()
    end
    darkModeApplyTimer = C_Timer.NewTimer(0.15, function()
        darkModeApplyTimer = nil
        applyDarkModeSettings(true)
    end)
end
local function cancelDarkModeApply()
    if darkModeApplyTimer then
        darkModeApplyTimer:Cancel()
        darkModeApplyTimer = nil
    end
end

local function createSettings()
    if not Settings or not Settings.RegisterCanvasLayoutCategory then
        return
    end

    local basePanel = createSettingsPanel("LizeUI")
    createDivider(basePanel, "Edicion WOW Forever", -30)
    local buffCheckbox = createSettingsCheckboxCustom(
        basePanel,
        "Marcos iconos buff / Debuff",
        { "TOPLEFT", basePanel, "TOPLEFT", 35, -45 },
        "marcosIconosBuffDebuff",
        function(isChecked)
            updateBuffDebuffBorders(isChecked)
            updateTargetAuraBorders(isChecked)
        end
    )
    local issueReportCheckbox = createSettingsCheckboxCustom(
        basePanel,
        "Eliminar boton Issue Report",
        { "TOPLEFT", basePanel, "TOPLEFT", 355, -45 },
        "eliminarBotonIssueReport",
        function(isChecked)
            updateIssueReportButton(isChecked)
        end
    )

    -- Dark Mode: lee/escribe directamente la base de datos de BetterBlizzFrames
    local darkModeSlider
    local function updateDarkModeSliderState(enabled)
        if darkModeSlider then
            if enabled then
                darkModeSlider:Enable()
                darkModeSlider:SetAlpha(1.0)
            else
                darkModeSlider:Disable()
                darkModeSlider:SetAlpha(0.5)
            end
        end
    end

    local darkModeCheckbox = CreateFrame("CheckButton", nil, basePanel, "UICheckButtonTemplate")
    darkModeCheckbox:SetPoint("TOPLEFT", basePanel, "TOPLEFT", 35, -80)
    local darkModeCheckboxLabel = basePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    darkModeCheckboxLabel:SetPoint("LEFT", darkModeCheckbox, "RIGHT", 8, 0)
    darkModeCheckboxLabel:SetText("Activar Dark Mode")
    darkModeCheckbox:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked() and true or false
        if BetterBlizzFramesDB then
            BetterBlizzFramesDB.darkModeUi = isChecked
        end
        updateDarkModeSliderState(isChecked)
        cancelDarkModeApply()
        applyDarkModeSettings()
    end)
    darkModeCheckbox.Refresh = function(self)
        self:SetChecked(BetterBlizzFramesDB and BetterBlizzFramesDB.darkModeUi == true)
    end

    darkModeSlider = CreateFrame("Slider", "LizeUIDarkModeIntensitySlider", basePanel, "OptionsSliderTemplate")
    darkModeSlider:SetPoint("TOPLEFT", basePanel, "TOPLEFT", 360, -80)
    darkModeSlider:SetSize(180, 17)
    darkModeSlider:SetMinMaxValues(0, 1)
    darkModeSlider:SetValueStep(0.05)
    darkModeSlider:SetObeyStepOnDrag(true)
    local darkModeSliderLow = _G["LizeUIDarkModeIntensitySliderLow"] or darkModeSlider.Low
    local darkModeSliderHigh = _G["LizeUIDarkModeIntensitySliderHigh"] or darkModeSlider.High
    local darkModeSliderText = _G["LizeUIDarkModeIntensitySliderText"] or darkModeSlider.Text
    if darkModeSliderLow then
        darkModeSliderLow:SetText("0")
        darkModeSliderLow:ClearAllPoints()
        darkModeSliderLow:SetPoint("TOPLEFT", darkModeSlider, "BOTTOMLEFT", 2, -4)
    end
    if darkModeSliderHigh then
        darkModeSliderHigh:SetText("1")
        darkModeSliderHigh:ClearAllPoints()
        darkModeSliderHigh:SetPoint("TOPRIGHT", darkModeSlider, "BOTTOMRIGHT", -2, -4)
    end
    if darkModeSliderText then
        darkModeSliderText:SetText("")
    end
    local darkModeSliderValueDisplay = basePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    darkModeSliderValueDisplay:SetPoint("BOTTOM", darkModeSlider, "TOP", 0, 4)
    local darkModeSliderUpdating = false
    darkModeSlider.Refresh = function(self)
        local currentVal = (BetterBlizzFramesDB and tonumber(BetterBlizzFramesDB.darkModeColor)) or 0.20
        darkModeSliderUpdating = true
        self:SetValue(currentVal)
        darkModeSliderUpdating = false
        darkModeSliderValueDisplay:SetText(string.format("Intensidad: %.2f", currentVal))
    end
    darkModeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 100 + 0.5) / 100
        darkModeSliderValueDisplay:SetText(string.format("Intensidad: %.2f", value))
        if not darkModeSliderUpdating then
            if BetterBlizzFramesDB then
                BetterBlizzFramesDB.darkModeColor = value
            end
            queueDarkModeApply()
        end
    end)
    darkModeSlider:EnableMouseWheel(true)
    darkModeSlider:SetScript("OnMouseWheel", function(self, delta)
        if not self:IsEnabled() then return end
        local cur = self:GetValue()
        local minV, maxV = self:GetMinMaxValues()
        local newV = math.max(minV, math.min(maxV, cur + delta * 0.05))
        self:SetValue(newV)
    end)
    darkModeCheckbox:Refresh()
    darkModeSlider:Refresh()
    updateDarkModeSliderState(BetterBlizzFramesDB and BetterBlizzFramesDB.darkModeUi == true)

    infoInstanciaButton = createSettingsButton(basePanel, "Info Instancia", 214, { "TOP", basePanel, "TOP", 0, -455 }, function()
        -- 1. Obtener datos de instancia y mapa
        local name, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceMapID, lfgDungeonID = GetInstanceInfo()
        local mapID = instanceMapID
        if not mapID or mapID == 0 then
            mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or "N/A"
        end

        -- 2. Obtener ContentTuningID desde MapID
        -- Primero buscamos en la tabla DB2 exportada (MapDifficulty)
        local contentTuningID = mapDifficultyLookup[mapID]
        -- Si no esta hardcodeado, intentamos la API del cliente
        if not contentTuningID and C_Map and C_Map.GetMapContentTuningID then
            contentTuningID = C_Map.GetMapContentTuningID(mapID)
        end
        contentTuningID = contentTuningID or "N/A"

        -- 3. Obtener Name_Lang desde LFGDungeons usando lfgDungeonID
        local nameLang = name or "N/A"
        if lfgDungeonID and lfgDungeonID > 0 and GetLFGDungeonInfo then
            local dungeonName = GetLFGDungeonInfo(lfgDungeonID)
            if dungeonName and dungeonName ~= "" then
                nameLang = dungeonName
            end
        end

        -- Fallback 1: si no hay nombre de dungeon, buscar en tabla LFGDungeons por ContentTuningID
        if (not nameLang or nameLang == "N/A") and contentTuningID ~= "N/A" then
            nameLang = lfgDungeonsLookup[contentTuningID] or nameLang
        end

        -- Fallback 2: si sigue sin haber nombre, usar el nombre del mapa
        if (not nameLang or nameLang == "N/A") and C_Map and C_Map.GetMapInfo then
            local mapInfo = C_Map.GetMapInfo(mapID)
            if mapInfo and mapInfo.name then
                nameLang = mapInfo.name
            end
        end

        printMessage("=== Datos detectados ===")
        printMessage("Name_Lang: " .. nameLang)
        printMessage("MapID: " .. tostring(mapID))
        printMessage("ContentTuningID: " .. tostring(contentTuningID))
        printMessage("lfgDungeonID: " .. tostring(lfgDungeonID or "N/A"))
        printMessage("=== Query BD2 por MapID ===")
        printMessage("SELECT ld.Name_Lang, ld.ContentTuningID, md.MapID")
        printMessage("FROM MapDifficulty md")
        printMessage("LEFT JOIN LFGDungeons ld ON ld.ContentTuningID = md.ContentTuningID")
        printMessage("WHERE md.MapID = " .. tostring(mapID) .. ";")
        printMessage("=== Query BD2 por Nombre ===")
        printMessage("SELECT ld.Name_Lang, ld.ContentTuningID, md.MapID")
        printMessage("FROM LFGDungeons ld")
        printMessage("LEFT JOIN MapDifficulty md ON md.ContentTuningID = ld.ContentTuningID")
        printMessage("WHERE ld.Name_Lang LIKE '%" .. (nameLang or "") .. "%';")
    end)

    createDivider(basePanel, "DialogueUI", -145)

    local dialogueUISlider, dialogueUISliderValDisplay

    local function updateSliderState(enabled)
        if dialogueUISlider then
            if enabled then
                dialogueUISlider:Enable()
                dialogueUISlider:SetAlpha(1.0)
            else
                dialogueUISlider:Disable()
                dialogueUISlider:SetAlpha(0.5)
            end
        end
    end

    local dialogueUICheckbox = createSettingsCheckboxCustom(
        basePanel,
        "Modificar Campo de vision lateral",
        { "TOPLEFT", basePanel, "TOPLEFT", 35, -175 },
        "modifyDialogueUICameraOffset",
        function(isChecked)
            updateSliderState(isChecked)
            notifyDialogueUI()
        end
    )

    dialogueUISlider, dialogueUISliderValDisplay = createSettingsSlider(
        basePanel,
        "LizeUIDialogueUICameraOffsetSlider",
        -20,
        20,
        1,
        0,
        { "TOPLEFT", basePanel, "TOPLEFT", 360, -180 },
        "dialogueUICameraOffset",
        function(val)
            notifyDialogueUI()
        end
    )

    updateSliderState(database.modifyDialogueUICameraOffset == true)

    basePanel.OnRefresh = function()
        if buffCheckbox and buffCheckbox.Refresh then
            buffCheckbox:Refresh()
        end
        if issueReportCheckbox and issueReportCheckbox.Refresh then
            issueReportCheckbox:Refresh()
        end
        if darkModeCheckbox and darkModeCheckbox.Refresh then
            darkModeCheckbox:Refresh()
        end
        if darkModeSlider and darkModeSlider.Refresh then
            darkModeSlider:Refresh()
        end
        updateDarkModeSliderState(BetterBlizzFramesDB and BetterBlizzFramesDB.darkModeUi == true)
        if dialogueUICheckbox and dialogueUICheckbox.Refresh then
            dialogueUICheckbox:Refresh()
        end
        if dialogueUISlider and dialogueUISlider.Refresh then
            dialogueUISlider:Refresh()
        end
        updateSliderState(database.modifyDialogueUICameraOffset == true)
    end

    createDivider(basePanel, "Importaciones", -225)

    local description = basePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    description:SetPoint("TOPLEFT", basePanel, "TOPLEFT", 20, -255)
    description:SetWidth(640)
    description:SetHeight(64)
    description:SetJustifyH("LEFT")
    description:SetJustifyV("TOP")
    description:SetText("LizeUI usa los addons BetterBlizzPlates y BetterBlizzFrames para conseguir una apariencia mejorada, sin cambiar la esencia de WoW Forever.\n\nAquí tienes unos botones para importar directamente las configuraciones que hemos preconfigurado, para que el juego se vea notablemente mejor.")

    createSettingsButton(basePanel, "BetterBlizzFrames", 214, { "TOP", basePanel, "TOP", -110, -340 }, function()
        importProfile("BBF", "ImportProfile", LoadProfilesBetterBlizzFrames, "BetterBlizzFrames")
    end)
    createSettingsButton(basePanel, "BetterBlizzPlates", 214, { "TOP", basePanel, "TOP", 110, -340 }, function()
        importProfile("BBP", "ImportProfile", LoadProfilesBetterBlizzPlater, "BetterBlizzPlates")
    end)
    createSettingsButton(basePanel, "Details", 214, { "TOP", basePanel, "TOP", -110, -400 }, importDetailsProfile)
    createSettingsButton(basePanel, "Reload", 214, { "TOP", basePanel, "TOP", 110, -400 }, function()
        database.windowOpened = true
        ReloadUI()
    end)

    if infoInstanciaButton and not database.devMode then
        infoInstanciaButton:Hide()
    end

    -- Panel de navegacion: ruta de RXPGuides en minimapa y mapa del mundo
    local navPanel = createSettingsPanel("Navegacion RXP", "LizeUI")
    local function refreshNavRoute()
        if NavRoute then NavRoute:Refresh() end
    end
    createDivider(navPanel, "Ruta de navegacion (RXPGuides)", -30)

    local navControls = {}
    local navEnabledCheckbox = createSettingsCheckboxCustom(
        navPanel, "Activar ruta de navegacion",
        { "TOPLEFT", navPanel, "TOPLEFT", 35, -50 },
        "navRouteEnabled",
        function()
            navPanel.UpdateState()
            refreshNavRoute()
        end
    )
    local function addNavCheckbox(text, point, key)
        local checkbox, label = createSettingsCheckboxCustom(navPanel, text, point, key, refreshNavRoute)
        navControls[#navControls + 1] = { widget = checkbox, label = label }
        return checkbox
    end
    local navArrowsCheckbox = addNavCheckbox("Flechas de direccion animadas", { "TOPLEFT", navPanel, "TOPLEFT", 355, -50 }, "navRouteArrows")
    local navMinimapCheckbox = addNavCheckbox("Mostrar en el minimapa", { "TOPLEFT", navPanel, "TOPLEFT", 35, -85 }, "navRouteMinimap")
    local navWorldMapCheckbox = addNavCheckbox("Mostrar en el mapa del mundo", { "TOPLEFT", navPanel, "TOPLEFT", 355, -85 }, "navRouteWorldMap")

    createDivider(navPanel, "Apariencia", -135)

    local navDefaults = NavRoute and NavRoute.defaults or {}
    local function addNavSlider(name, minVal, maxVal, step, key, point, decimals, displayFormat)
        local slider, valueDisplay = createSettingsSlider(
            navPanel, name, minVal, maxVal, step, navDefaults[key] or minVal, point, key,
            refreshNavRoute, decimals, displayFormat, true
        )
        navControls[#navControls + 1] = { widget = slider, label = valueDisplay, isSlider = true }
        return slider
    end
    local navThicknessSlider = addNavSlider("LizeUINavRouteThicknessSlider", 1, 6, 0.5, "navRouteThickness",
        { "TOPLEFT", navPanel, "TOPLEFT", 60, -180 }, 1, "Grosor de linea: %s")
    local navAlphaSlider = addNavSlider("LizeUINavRouteAlphaSlider", 0.2, 1, 0.05, "navRouteAlpha",
        { "TOPLEFT", navPanel, "TOPLEFT", 360, -180 }, 2, "Opacidad: %s")
    local navGraySlider = addNavSlider("LizeUINavRouteGraySlider", 0.3, 1, 0.05, "navRouteGray",
        { "TOPLEFT", navPanel, "TOPLEFT", 60, -245 }, 2, "Tono de gris: %s")
    local navFutureSlider = addNavSlider("LizeUINavRouteFutureSlider", 0, 5, 1, "navRouteFutureSteps",
        { "TOPLEFT", navPanel, "TOPLEFT", 360, -245 }, 0, "Pasos siguientes en la ruta: %s")

    local navStatusText = navPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    navStatusText:SetPoint("TOPLEFT", navPanel, "TOPLEFT", 20, -300)
    navStatusText:SetWidth(640)
    navStatusText:SetJustifyH("LEFT")
    navStatusText:SetJustifyV("TOP")

    local function updateNavStatus()
        local lines = {}
        if isAddonLoaded("RXPGuides") and NavRoute and NavRoute:IsAvailable() then
            lines[#lines + 1] = "|cff7fff7fRXPGuides detectado.|r La ruta sigue el objetivo actual de la guia, sus waypoints y los pasos siguientes (los pasos siguientes se dibujan mas tenues)."
        else
            lines[#lines + 1] = "|cffff5555RXPGuides no esta cargado:|r la ruta de navegacion no se mostrara."
        end
        if isAddonLoaded("RXP_Navigator") then
            lines[#lines + 1] = "|cffffaa33RXP_Navigator esta activo.|r Recomendado desactivarlo: duplica las lineas y modifica los ajustes de la flecha de RXPGuides."
        end
        navStatusText:SetText(table.concat(lines, "\n\n"))
    end

    navPanel.UpdateState = function()
        local enabled = database.navRouteEnabled == true
        for _, control in ipairs(navControls) do
            if enabled then
                control.widget:Enable()
            else
                control.widget:Disable()
            end
            control.widget:SetAlpha(enabled and 1 or 0.5)
            if control.label then control.label:SetAlpha(enabled and 1 or 0.5) end
        end
    end

    local function refreshNavPanel()
        for _, widget in ipairs({ navEnabledCheckbox, navArrowsCheckbox, navMinimapCheckbox, navWorldMapCheckbox,
            navThicknessSlider, navAlphaSlider, navGraySlider, navFutureSlider }) do
            if widget and widget.Refresh then widget:Refresh() end
        end
        navPanel.UpdateState()
        updateNavStatus()
    end

    createSettingsButton(navPanel, "Restablecer valores", 214, { "TOP", navPanel, "TOP", 0, -380 }, function()
        for key, value in pairs(navDefaults) do
            database[key] = value
        end
        refreshNavPanel()
        refreshNavRoute()
    end)

    navPanel.OnRefresh = refreshNavPanel
    navPanel:SetScript("OnShow", refreshNavPanel)
    refreshNavPanel()

    -- Panel de utilidades: tooltip mejorado y automatizaciones (estilo Leatrix Plus)
    local utilPanel = createSettingsPanel("Utilidades", "LizeUI")
    local utilDefaults = Utilities and Utilities.defaults or {}
    local utilRefreshers = {}
    local function refreshTooltipModule()
        if Utilities then Utilities:RefreshTooltip() end
    end
    local function refreshAutomationModule()
        if Utilities then Utilities:RefreshAutomation() end
    end
    local function setControlEnabled(control, enabled)
        if enabled then control.widget:Enable() else control.widget:Disable() end
        control.widget:SetAlpha(enabled and 1 or 0.5)
        if control.label then control.label:SetAlpha(enabled and 1 or 0.5) end
    end

    local COL1, COL2 = 35, 355
    local function addUtilCheckbox(text, x, y, key, onToggle, tooltip)
        local checkbox, label = createSettingsCheckboxCustom(utilPanel, text, { "TOPLEFT", utilPanel, "TOPLEFT", x, y }, key,
            function()
                if onToggle then onToggle() end
                utilPanel.UpdateState()
            end)
        if tooltip then
            checkbox:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(text, 1, 1, 1)
                GameTooltip:AddLine(tooltip, nil, nil, nil, true)
                GameTooltip:Show()
            end)
            checkbox:SetScript("OnLeave", GameTooltip_Hide)
        end
        utilRefreshers[#utilRefreshers + 1] = checkbox
        return { widget = checkbox, label = label }
    end
    local function addUtilSlider(name, minVal, maxVal, step, key, x, y, decimals, displayFormat, onChange)
        local slider, valueDisplay = createSettingsSlider(utilPanel, name, minVal, maxVal, step, utilDefaults[key] or minVal,
            { "TOPLEFT", utilPanel, "TOPLEFT", x, y }, key, onChange, decimals, displayFormat)
        slider.Refresh = function(self)
            local value = tonumber(database[key]) or utilDefaults[key] or minVal
            self:SetValue(value)
        end
        utilRefreshers[#utilRefreshers + 1] = slider
        return { widget = slider, label = valueDisplay }
    end

    -- Seccion: Tooltip
    createDivider(utilPanel, "Tooltip mejorado", -30)
    local tipEnable = addUtilCheckbox("Activar tooltip mejorado", COL1, -45, "tipEnabled", refreshTooltipModule,
        "Nombres en color de clase, nivel coloreado por dificultad, rango de hermandad, objetivo de la unidad, anclaje al cursor y escala.")
    local tipHealth = addUtilCheckbox("Ocultar la barra de salud", COL2, -45, "tipNoHealthBar", refreshTooltipModule)
    local tipRank = addUtilCheckbox("Rangos de tu hermandad", COL1, -75, "tipShowRank")
    local tipOtherRank = addUtilCheckbox("Rangos de otras hermandades", COL2, -75, "tipShowOtherRank")
    local tipTarget = addUtilCheckbox("Mostrar el objetivo de la unidad", COL1, -105, "tipShowTarget")
    local tipFaction = addUtilCheckbox("Fondo segun faccion", COL2, -105, "tipBackFaction", nil,
        "Tiñe el fondo de azul (amistoso) o rojo (faccion enemiga).")
    local tipCombat = addUtilCheckbox("Ocultar en combate (unidades del mundo)", COL1, -135, "tipHideInCombat")
    local tipShift = addUtilCheckbox("Mostrar con Shift en combate", COL2, -135, "tipHideShiftOverride")

    local ANCHOR_NAMES = { "Por defecto", "Cursor", "Cursor izquierda", "Cursor derecha" }
    local anchorButton = CreateFrame("Button", nil, utilPanel, "UIPanelButtonTemplate")
    anchorButton:SetSize(200, 24)
    anchorButton:SetPoint("TOPLEFT", utilPanel, "TOPLEFT", COL1 + 25, -185)
    local anchorLabel = utilPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    anchorLabel:SetPoint("BOTTOM", anchorButton, "TOP", 0, 4)
    anchorLabel:SetText("Anclaje (unidades del mundo)")
    anchorButton.Refresh = function(self)
        local value = tonumber(database.tipAnchor) or 1
        self:SetText(ANCHOR_NAMES[value] or ANCHOR_NAMES[1])
    end
    anchorButton:SetScript("OnClick", function(self)
        local value = (tonumber(database.tipAnchor) or 1) % #ANCHOR_NAMES + 1
        database.tipAnchor = value
        self:Refresh()
        utilPanel.UpdateState()
    end)
    utilRefreshers[#utilRefreshers + 1] = anchorButton
    local tipAnchor = { widget = anchorButton, label = anchorLabel }

    local tipScale = addUtilSlider("LizeUITipScaleSlider", 0.5, 2, 0.05, "tipScale", COL2 + 5, -190, 2, "Escala: %s",
        refreshTooltipModule)
    local tipX = addUtilSlider("LizeUITipCursorXSlider", -128, 128, 1, "tipCursorX", COL1 + 35, -240, 0, "Desplazamiento X: %s")
    local tipY = addUtilSlider("LizeUITipCursorYSlider", -128, 128, 1, "tipCursorY", COL2 + 5, -240, 0, "Desplazamiento Y: %s")

    -- Seccion: Automatizacion
    createDivider(utilPanel, "Automatizacion", -285)
    local autoRepair = addUtilCheckbox("Reparar automaticamente", COL1, -300, "autoRepair", refreshAutomationModule,
        "Repara todo el equipo al abrir un vendedor que pueda reparar. Manten Shift al abrirlo para no reparar.")
    local autoRepairGuild = addUtilCheckbox("Usar fondos de la hermandad", COL2, -300, "autoRepairGuild", nil,
        "Si tienes permiso, la reparacion se paga con el banco de la hermandad (si se agota el limite, con tu oro).")
    local autoSell = addUtilCheckbox("Vender objetos pobres", COL1, -330, "autoSellJunk", refreshAutomationModule,
        "Vende los objetos grises al abrir un vendedor. Manten Shift al abrirlo para no vender.")
    local autoSellGear = addUtilCheckbox("No vender equipo gris no ligado", COL2, -330, "autoSellNoGreyGear", nil,
        "Armas y armaduras grises que no estan ligadas no se venden (por si quieres subastarlas).")
    local autoSummary = addUtilCheckbox("Resumen en el chat (reparar / vender)", COL1, -360, "autoShowSummary")
    local fasterLoot = addUtilCheckbox("Despojar rapido", COL2, -360, "fasterLoot", refreshAutomationModule,
        "Recoge todo el botin al instante cuando el despojo automatico esta activo.")
    local inviteWhisper = addUtilCheckbox("Invitacion por susurro", COL1, -390, "inviteFromWhisper", refreshAutomationModule,
        "Invita al grupo a quien te susurre la palabra clave.")

    local keywordBox = CreateFrame("EditBox", nil, utilPanel, "InputBoxTemplate")
    keywordBox:SetSize(110, 20)
    keywordBox:SetPoint("TOPLEFT", utilPanel, "TOPLEFT", COL2 + 105, -394)
    keywordBox:SetAutoFocus(false)
    keywordBox:SetMaxLetters(30)
    local keywordLabel = utilPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    keywordLabel:SetPoint("RIGHT", keywordBox, "LEFT", -10, 0)
    keywordLabel:SetText("Palabra clave:")
    local function saveKeyword()
        local text = strtrim(keywordBox:GetText() or "")
        database.inviteKeyword = text ~= "" and text or "inv"
    end
    keywordBox:SetScript("OnTextChanged", function(_, userInput)
        if userInput then saveKeyword() end
    end)
    keywordBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    keywordBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    keywordBox:SetScript("OnEditFocusLost", function(self)
        saveKeyword()
        self:SetText(database.inviteKeyword)
    end)
    keywordBox.Refresh = function(self) self:SetText(database.inviteKeyword or "inv") end
    utilRefreshers[#utilRefreshers + 1] = keywordBox
    local inviteKeyword = { widget = keywordBox, label = keywordLabel }

    local inviteFriends = addUtilCheckbox("Invitar solo a amigos", COL1, -420, "inviteFriendsOnly")
    local acceptFriends = addUtilCheckbox("Aceptar grupo de amigos", COL2, -420, "acceptPartyFriends", refreshAutomationModule,
        "Acepta automaticamente las invitaciones de grupo de tus amigos (si no estas en cola de buscador).")
    local friendlyGuild = addUtilCheckbox("Contar la hermandad como amigos", COL1, -450, "friendlyGuild", nil,
        "Los miembros conectados de tu hermandad cuentan como amigos para invitar y aceptar grupo.")
    local lootDelay = addUtilSlider("LizeUIFasterLootDelaySlider", 0.1, 0.3, 0.1, "fasterLootDelay", COL2 + 5, -460, 1,
        "Retardo del despojo: %s s")

    local utilStatusText = utilPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    utilStatusText:SetPoint("TOPLEFT", utilPanel, "TOPLEFT", 20, -500)
    utilStatusText:SetWidth(640)
    utilStatusText:SetJustifyH("LEFT")
    utilStatusText:SetJustifyV("TOP")

    local function updateUtilStatus()
        local conflicts = Utilities and Utilities:GetLeatrixConflicts() or {}
        if #conflicts > 0 then
            utilStatusText:SetText("|cffffaa33Leatrix Plus tiene activas opciones equivalentes:|r " .. table.concat(conflicts, ", ") ..
                ". Desactivalas en Leatrix Plus o aqui para que no se hagan dos veces.")
        else
            utilStatusText:SetText("")
        end
    end

    utilPanel.UpdateState = function()
        local tipOn = database.tipEnabled == true
        for _, control in ipairs({ tipHealth, tipRank, tipOtherRank, tipTarget, tipFaction, tipCombat, tipAnchor, tipScale }) do
            setControlEnabled(control, tipOn)
        end
        setControlEnabled(tipShift, tipOn and database.tipHideInCombat == true)
        local cursorOffset = tipOn and ((tonumber(database.tipAnchor) or 1) >= 3)
        setControlEnabled(tipX, cursorOffset)
        setControlEnabled(tipY, cursorOffset)

        setControlEnabled(autoRepairGuild, database.autoRepair == true)
        setControlEnabled(autoSellGear, database.autoSellJunk == true)
        setControlEnabled(autoSummary, database.autoRepair == true or database.autoSellJunk == true)
        setControlEnabled(inviteKeyword, database.inviteFromWhisper == true)
        setControlEnabled(inviteFriends, database.inviteFromWhisper == true)
        setControlEnabled(friendlyGuild, database.inviteFromWhisper == true or database.acceptPartyFriends == true)
        setControlEnabled(lootDelay, database.fasterLoot == true)
    end

    local function refreshUtilPanel()
        for _, widget in ipairs(utilRefreshers) do
            if widget.Refresh then widget:Refresh() end
        end
        utilPanel.UpdateState()
        updateUtilStatus()
    end
    utilPanel.OnRefresh = refreshUtilPanel
    utilPanel:SetScript("OnShow", refreshUtilPanel)
    refreshUtilPanel()

    local checkPanel = createSettingsPanel("Check Addons", "LizeUI")
    local checkTitle = checkPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    checkTitle:SetPoint("TOPLEFT", checkPanel, "TOPLEFT", 20, -20)
    checkTitle:SetText("Estado de addons")
    local checkText = checkPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    checkText:SetPoint("TOPLEFT", checkTitle, "BOTTOMLEFT", 0, -15)
    checkText:SetJustifyH("LEFT")
    checkText:SetText("BetterBlizzFrames: " .. (isAddonLoaded("BetterBlizzFrames") and "cargado" or "no cargado") .. "\nBetterBlizzPlates: " .. (isAddonLoaded("BetterBlizzPlates") and "cargado" or "no cargado") .. "\nDetails: " .. (isAddonLoaded("Details") and "cargado" or "no cargado") .. "\nRXPGuides: " .. (isAddonLoaded("RXPGuides") and "cargado" or "no cargado"))

    local supportPanel = createSettingsPanel("Support", "LizeUI")
    local supportText = supportPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    supportText:SetPoint("TOPLEFT", supportPanel, "TOPLEFT", 20, -20)
    supportText:SetText("LizeUI - soporte y ayuda")

    local category = Settings.RegisterCanvasLayoutCategory(basePanel, "LizeUI", "LizeUI")
    Settings.RegisterAddOnCategory(category)
    Settings.RegisterCanvasLayoutSubcategory(category, navPanel, "Navegacion RXP", "Navegacion RXP")
    Settings.RegisterCanvasLayoutSubcategory(category, utilPanel, "Utilidades", "Utilidades")
    Settings.RegisterCanvasLayoutSubcategory(category, checkPanel, "Check Addons", "Check Addons")
    Settings.RegisterCanvasLayoutSubcategory(category, supportPanel, "Support", "Support")
end

local function showWindow()
    window:Show()
end

local function updateDevModeVisibility()
    if infoInstanciaButton then
        if database.devMode then
            infoInstanciaButton:Show()
        else
            infoInstanciaButton:Hide()
        end
    end
end

SLASH_LIZEUI1 = "/lui"
SlashCmdList.LIZEUI = function(msg)
    if msg == "dev" then
        database.devMode = not database.devMode
        printMessage("Modo desarrollador: " .. (database.devMode and "activado" or "desactivado"))
        updateDevModeVisibility()
    elseif msg == "ruta" then
        database.navRouteEnabled = not database.navRouteEnabled
        if NavRoute then NavRoute:Refresh() end
        printMessage("Ruta de navegacion: " .. (database.navRouteEnabled and "activada" or "desactivada"))
    elseif msg == "dark" then
        local function describe(obj)
            if obj == nil then return "NIL" end
            local ok, objType = pcall(function() return obj:GetObjectType() end)
            if not ok then return "ERROR" end
            local extra = ""
            if objType == "Texture" and obj.GetVertexColor then
                local r, g, b = obj:GetVertexColor()
                extra = string.format(" color=%.2f,%.2f,%.2f", r or -1, g or -1, b or -1)
            end
            return objType .. extra
        end
        local function report(name, obj)
            printMessage(name .. ": " .. describe(obj))
        end
        local mainActionBar = _G.MainMenuBar or _G.MainActionBar
        report("MainActionBar", mainActionBar)
        report("MainActionBar.EndCaps", mainActionBar and mainActionBar.EndCaps)
        if mainActionBar and mainActionBar.EndCaps then
            local l = mainActionBar.EndCaps.LeftEndCap
            local r = mainActionBar.EndCaps.RightEndCap
            report("EndCaps.LeftEndCap", l)
            report("EndCaps.LeftEndCap.Texture", l and l.Texture)
            report("EndCaps.RightEndCap", r)
            report("EndCaps.RightEndCap.Texture", r and r.Texture)
        end
        report("MainMenuBarLeftEndCap", _G["MainMenuBarLeftEndCap"])
        report("ActionButton1", _G["ActionButton1"])
        report("ActionButton1.NormalTexture", _G["ActionButton1"] and _G["ActionButton1"].NormalTexture)
        report("ActionButton1NormalTexture", _G["ActionButton1NormalTexture"])
        report("MultiBar5Button1", _G["MultiBar5Button1"])
        report("MultiBar5Button1.NormalTexture", _G["MultiBar5Button1"] and _G["MultiBar5Button1"].NormalTexture)
        report("MicroMenu", _G["MicroMenu"])
        report("CharacterMicroButton.Background", _G["CharacterMicroButton"] and _G["CharacterMicroButton"].Background)
        report("BagsBar", _G["BagsBar"])
        report("MainMenuBarBackpackButton", _G["MainMenuBarBackpackButton"])
        if BetterBlizzFramesDB then
            printMessage("BBF darkModeUi=" .. tostring(BetterBlizzFramesDB.darkModeUi) ..
                " darkModeActionBars=" .. tostring(BetterBlizzFramesDB.darkModeActionBars) ..
                " darkModeColor=" .. tostring(BetterBlizzFramesDB.darkModeColor))
        else
            printMessage("BetterBlizzFramesDB no existe")
        end
    else
        showWindow()
    end
end

local auraWatcherRegistered = false
local function registerAuraBorderWatcher()
    if auraWatcherRegistered then return end
    auraWatcherRegistered = true
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_AURA")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    local lastUpdate = 0
    local targetUpdateToken = 0
    local function applyBorders()
        if database.marcosIconosBuffDebuff then
            updateBuffDebuffBorders(true)
            updateTargetAuraBorders(true)
        end
    end
    f:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_AURA" and unit ~= "player" and unit ~= "target" then return end
        if event == "PLAYER_TARGET_CHANGED" then
            applyBorders()
            local token = targetUpdateToken + 1
            targetUpdateToken = token
            C_Timer.After(0.5, function()
                if targetUpdateToken == token then
                    applyBorders()
                end
            end)
            return
        end
        local now = GetTime()
        if now - lastUpdate < 0.5 then return end
        lastUpdate = now
        applyBorders()
    end)
end

local function applyLizeUIBorders()
    if database.marcosIconosBuffDebuff then
        updateBuffDebuffBorders(true)
        updateTargetAuraBorders(true)
    end
end

local bbfHooksInstalled = false

local function hookBBFFrames()
    if not BBF or bbfHooksInstalled then return end
    if BBF.RefreshAllAuraFrames then
        hooksecurefunc(BBF, "RefreshAllAuraFrames", applyLizeUIBorders)
    end
    if BBF.RestyleAuraButtons then
        hooksecurefunc(BBF, "RestyleAuraButtons", applyLizeUIBorders)
    end
    bbfHooksInstalled = true
end

local function scheduleBorderRetries()
    if not C_Timer or not C_Timer.After then return end
    for _, delay in ipairs({0, 2, 5, 10}) do
        C_Timer.After(delay, function()
            if database.marcosIconosBuffDebuff then
                updateBuffDebuffBorders(true)
                updateTargetAuraBorders(true)
            end
        end)
    end
end

local issueReportWatcherStarted = false
local function startIssueReportWatcher()
    if issueReportWatcherStarted or not C_Timer or not C_Timer.After then return end
    issueReportWatcherStarted = true
    local function check()
        updateIssueReportButton(database.eliminarBotonIssueReport == true)
        C_Timer.After(5, check)
    end
    C_Timer.After(1, check)
end

local function applyAllSettings()
    updateIssueReportButton(database.eliminarBotonIssueReport == true)
    updateBuffDebuffBorders(database.marcosIconosBuffDebuff == true)
    updateTargetAuraBorders(database.marcosIconosBuffDebuff == true)
    applyDarkModeSettings()
    hookBBFFrames()
    registerAuraBorderWatcher()
    scheduleBorderRetries()
    startIssueReportWatcher()
end

-- Details crea sus ventanas justo despues de PLAYER_LOGIN y a veces pinta la barra de titulo antes de
-- que la textura "TWW Header" este disponible (queda en blanco). Se vuelve a aplicar tras el login.
local detailsHeaderTextures = { ["TWW Header"] = true, ["TheWarWithinHeader"] = true }

local function refreshDetailsTitleBars()
    local details = _G.Details
    if not details or type(details.ListInstances) ~= "function" then
        return
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    for _, instance in details:ListInstances() do
        if instance.baseframe and detailsHeaderTextures[instance.titlebar_texture] then
            if type(instance.RefreshTitleBar) == "function" then
                pcall(instance.RefreshTitleBar, instance)
            end
            local titleBar = instance.baseframe.titleBar
            local file = LSM and LSM:Fetch("statusbar", instance.titlebar_texture, true)
            if titleBar and titleBar.texture and file then
                titleBar.texture:SetTexture(file)
            end
        end
    end
end

local function scheduleDetailsTitleBarRefresh()
    if not C_Timer then
        return
    end
    C_Timer.After(1, refreshDetailsTitleBars)
    C_Timer.After(3, refreshDetailsTitleBars)
end

addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_LOGIN")
addon:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            initDatabase()
        elseif arg1 == "Blizzard_PTRFeedback" then
            updateIssueReportButton(database.eliminarBotonIssueReport == true)
        elseif arg1 == "BetterBlizzFrames" then
            applyAllSettings()
        end
    elseif event == "PLAYER_LOGIN" then
        initDatabase()
        createSettings()
        updateDevModeVisibility()
        applyAllSettings()
        if NavRoute then NavRoute:Init(database) end
        if Utilities then Utilities:Init(database) end
        scheduleDetailsTitleBarRefresh()
        printMessage("Para abrir la ventana de nuevo, usa /lui.")
        if not database.windowOpened then
            database.windowOpened = true
            showWindow()
        end
    end
end)
