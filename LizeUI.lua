local addonName = "LizeUI"
local addon = CreateFrame("Frame")

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

local window = CreateFrame("Frame", "LoadProfilesWindow", UIParent, "PortraitFrameTemplate")
window:SetSize(500, 285)
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

local function createSettingsSlider(panel, name, minVal, maxVal, step, defaultVal, point, databaseKey, onValueChanged)
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
        highText:SetText("+" .. tostring(maxVal))
        highText:ClearAllPoints()
        highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", -2, -4)
    end

    local valueDisplay = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueDisplay:SetPoint("BOTTOM", slider, "TOP", 0, 4)

    local function formatValue(val)
        if val > 0 then
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
        valueDisplay:SetText("Desplazamiento: " .. formatValue(currentVal))
    end
    refresh()

    if titleText then
        titleText:SetText("")
    end

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        if not isUpdatingValue then
            database[databaseKey] = value
        end
        valueDisplay:SetText("Desplazamiento: " .. formatValue(value))
        if onValueChanged and not isUpdatingValue then
            onValueChanged(value)
        end
    end)

    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(self, delta)
        if not self:IsEnabled() then return end
        local cur = self:GetValue()
        local minV, maxV = self:GetMinMaxValues()
        local newV = math.max(minV, math.min(maxV, cur + delta))
        self:SetValue(newV)
    end)

    slider.Refresh = refresh
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

    local function applyBorderToButton(button, isDebuff)
        if not button then return end
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
            button.lizeUIBorder:SetVertexColor(1, 0.15, 0.15)
        else
            -- Buffs: gris neutro
            button.lizeUIBorder:SetDesaturated(false)
            button.lizeUIBorder:SetVertexColor(0.75, 0.75, 0.75)
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
            if btn and btn.ClearDispelTypeTextures then
                btn:ClearDispelTypeTextures()
            end
        end
        if BuffFrame and BuffFrame.auraFrames then
            for _, btn in ipairs(BuffFrame.auraFrames) do
                if btn and btn.ClearDispelTypeTextures then
                    btn:ClearDispelTypeTextures()
                end
            end
        end
        if DebuffFrame and DebuffFrame.auraFrames then
            for _, btn in ipairs(DebuffFrame.auraFrames) do
                if btn and btn.ClearDispelTypeTextures then
                    btn:ClearDispelTypeTextures()
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
                            if button and button.ClearDispelTypeTextures then
                                button:ClearDispelTypeTextures()
                            end
                        end
                    end
                end
            end
        end
    end
end

local function updateTargetAuraBorders(enabled)
    local function applyTargetBorder(button, isDebuff)
        if not button then return end
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

        -- Gris neutro siempre; si BBF tiene su propio borde (OVERLAY) lo vera encima
        button.lizeUITargetBorder:SetDesaturated(false)
        button.lizeUITargetBorder:SetVertexColor(0.75, 0.75, 0.75)

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
                if btn:IsObjectType("Frame") or btn:IsObjectType("Button") then
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
                if btn and btn.ClearDispelTypeTextures then
                    btn:ClearDispelTypeTextures()
                end
            end
        end
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

    infoInstanciaButton = createSettingsButton(basePanel, "Info Instancia", 214, { "TOP", basePanel, "TOP", 0, -420 }, function()
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

    createDivider(basePanel, "DialogueUI", -110)

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
        { "TOPLEFT", basePanel, "TOPLEFT", 35, -140 },
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
        { "TOPLEFT", basePanel, "TOPLEFT", 360, -145 },
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
        if dialogueUICheckbox and dialogueUICheckbox.Refresh then
            dialogueUICheckbox:Refresh()
        end
        if dialogueUISlider and dialogueUISlider.Refresh then
            dialogueUISlider:Refresh()
        end
        updateSliderState(database.modifyDialogueUICameraOffset == true)
    end

    createDivider(basePanel, "Importaciones", -190)

    local description = basePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    description:SetPoint("TOPLEFT", basePanel, "TOPLEFT", 20, -220)
    description:SetWidth(640)
    description:SetHeight(64)
    description:SetJustifyH("LEFT")
    description:SetJustifyV("TOP")
    description:SetText("LizeUI usa los addons BetterBlizzPlates y BetterBlizzFrames para conseguir una apariencia mejorada, sin cambiar la esencia de WoW Forever.\n\nAquí tienes unos botones para importar directamente las configuraciones que hemos preconfigurado, para que el juego se vea notablemente mejor.")

    createSettingsButton(basePanel, "BetterBlizzFrames", 214, { "TOP", basePanel, "TOP", -110, -305 }, function()
        importProfile("BBF", "ImportProfile", LoadProfilesBetterBlizzFrames, "BetterBlizzFrames")
    end)
    createSettingsButton(basePanel, "BetterBlizzPlates", 214, { "TOP", basePanel, "TOP", 110, -305 }, function()
        importProfile("BBP", "ImportProfile", LoadProfilesBetterBlizzPlater, "BetterBlizzPlates")
    end)
    createSettingsButton(basePanel, "Reload", 214, { "TOP", basePanel, "TOP", 0, -365 }, function()
        database.windowOpened = true
        ReloadUI()
    end)

    if infoInstanciaButton and not database.devMode then
        infoInstanciaButton:Hide()
    end

    local checkPanel = createSettingsPanel("Check Addons", "LizeUI")
    local checkTitle = checkPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    checkTitle:SetPoint("TOPLEFT", checkPanel, "TOPLEFT", 20, -20)
    checkTitle:SetText("Estado de addons")
    local checkText = checkPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    checkText:SetPoint("TOPLEFT", checkTitle, "BOTTOMLEFT", 0, -15)
    checkText:SetJustifyH("LEFT")
    checkText:SetText("BetterBlizzFrames: " .. (isAddonLoaded("BetterBlizzFrames") and "cargado" or "no cargado") .. "\nBetterBlizzPlates: " .. (isAddonLoaded("BetterBlizzPlates") and "cargado" or "no cargado"))

    local supportPanel = createSettingsPanel("Support", "LizeUI")
    local supportText = supportPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    supportText:SetPoint("TOPLEFT", supportPanel, "TOPLEFT", 20, -20)
    supportText:SetText("LizeUI - soporte y ayuda")

    local category = Settings.RegisterCanvasLayoutCategory(basePanel, "LizeUI", "LizeUI")
    Settings.RegisterAddOnCategory(category)
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
    hookBBFFrames()
    registerAuraBorderWatcher()
    scheduleBorderRetries()
    startIssueReportWatcher()
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
        printMessage("Para abrir la ventana de nuevo, usa /lui.")
        if not database.windowOpened then
            database.windowOpened = true
            showWindow()
        end
    end
end)
