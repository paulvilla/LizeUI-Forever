local addonName = "LizeUI"
local _, ns = ...
local addon = CreateFrame("Frame")
local NavRoute = ns and ns.NavRoute
local Utilities = ns and ns.Utilities
local L = ns.L

local function initDatabase()
    if type(LizeUIDB) ~= "table" then
        if type(LoadProfilesDB) == "table" then
            LizeUIDB = LoadProfilesDB
        else
            LizeUIDB = {}
        end
    end
    LoadProfilesDB = LizeUIDB
    -- Opciones de DialogueUI eliminadas
    LizeUIDB.modifyDialogueUICameraOffset = nil
    LizeUIDB.dialogueUICameraOffset = nil
    if LizeUIDB.eliminarBotonIssueReport == nil then
        LizeUIDB.eliminarBotonIssueReport = true
    end
    if LizeUIDB.marcosIconosBuffDebuff == nil then
        LizeUIDB.marcosIconosBuffDebuff = true
    end
    if LizeUIDB.devMode == nil then
        LizeUIDB.devMode = false
    end
    LizeUIDB.chatGuildLoginSound = nil
    LizeUIDB.chatGuildLoginGameSound = nil
    LizeUIDB.chatGuildLoginSoundName = nil
    -- 2.0.0: el precio neto de subasta pasa a estar activo por defecto. Se
    -- activa una sola vez (tambien a quien ya lo tenia guardado como apagado).
    if not LizeUIDB.tipAuctionNetDefaultApplied then
        LizeUIDB.tipAuctionNet = true
        LizeUIDB.tipAuctionNetDefaultApplied = true
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
    DEFAULT_CHAT_FRAME:AddMessage(ns.BrandText(true, 12) .. ": " .. message)
end

local function importProfile(addonTableName, importFunction, profile, label)
    if not profile then
        printMessage(L.FMT_PROFILE_NOT_FOUND:format(label))
        return
    end

    local addonTable = _G[addonTableName]
    if not addonTable or type(addonTable.OldImportProfile) ~= "function" then
        printMessage(L.FMT_NO_IMPORTER:format(label))
        return
    end

    local success, imported, errorMessage = pcall(function()
        local profileData, importError = addonTable.OldImportProfile(profile, "fullProfile")
        if importError then
            return false, importError
        end
        if type(profileData) ~= "table" then
            return false, L.NO_VALID_CONFIG
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
        printMessage(L.FMT_IMPORT_ERROR:format(label, tostring(imported)))
    elseif imported == false then
        printMessage(L.FMT_IMPORT_ERROR:format(label, tostring(errorMessage or L.INVALID_STRING)))
    else
        printMessage(L.FMT_IMPORT_OK:format(label))
    end
end

local detailsProfileName = "LizeUI"

local function importDetailsProfile()
    local profile = LoadProfilesDetails
    if not profile then
        printMessage(L.FMT_PROFILE_NOT_FOUND:format("Details"))
        return
    end

    local details = _G.Details or _G._detalhes
    if not details or type(details.ImportProfile) ~= "function" then
        printMessage(L.FMT_NO_IMPORTER:format("Details"))
        return
    end

    -- ImportProfile(cadena, nombre, importarAutoRun, desdePrompt, sobrescribir)
    local success, result = pcall(details.ImportProfile, details, profile, detailsProfileName, false, false, true)
    if not success then
        printMessage(L.FMT_IMPORT_ERROR:format("Details", tostring(result)))
    elseif not result then
        printMessage(L.FMT_IMPORT_ERROR:format("Details", L.INVALID_STRING))
    else
        printMessage(L.FMT_IMPORT_OK:format("Details (" .. detailsProfileName .. ")"))
    end
end

-- ---------------------------------------------------------------------------
-- Estado de addons (compartido por la ventana de bienvenida y el panel principal)
-- ---------------------------------------------------------------------------
local ICON_PATH = [[Interface\AddOns\LizeUI\media\textures\icons\]]
local STATUS_INFO = {
    ok       = { icon = ICON_PATH .. "ok.tga",        textKey = "STATUS_OK" },
    reload   = { icon = ICON_PATH .. "no-active.tga", textKey = "STATUS_RELOAD" },
    inactive = { icon = ICON_PATH .. "no-active.tga", textKey = "STATUS_INACTIVE" },
    missing  = { icon = ICON_PATH .. "error.tga",     textKey = "STATUS_MISSING" },
    blocked  = { icon = ICON_PATH .. "no-active.tga", textKey = "FMT_STATUS_BLOCKED" },
}

local function getAddonInfoSafe(folder)
    local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if type(getInfo) ~= "function" then return nil end
    local ok, name, _, _, loadable, reason = pcall(getInfo, folder)
    if not ok then return nil end
    if type(name) == "table" then
        local t = name
        return t.name or t.Name or folder, t.loadable, t.reason
    end
    return name, loadable, reason
end

-- Addons activados durante esta sesion con el boton "Activar" (cargan tras /reload)
local enabledThisSession = {}
local pendingReload = false

-- Estado de un addon para ESTE personaje:
--   ok       = cargado
--   reload   = activado en esta sesion, se cargara al recargar la interfaz
--   blocked  = activado pero el juego no lo puede cargar (desactualizado, falta una dependencia...)
--   inactive = instalado pero desactivado
--   missing  = no instalado
-- La API de activacion devuelve valores ambiguos cuando el addon esta activado en
-- otros personajes, asi que un addon no cargado que no se ha activado en esta
-- sesion se considera desactivado.
local function getAddonStatus(folder)
    if isAddonLoaded(folder) then return "ok" end
    local name, loadable, reason = getAddonInfoSafe(folder)
    if reason == "MISSING" or type(name) ~= "string" or name == "" then return "missing" end
    if enabledThisSession[folder] then return "reload" end
    if type(reason) == "string" and reason ~= "" and reason ~= "DISABLED" and not loadable then
        return "blocked", reason
    end
    return "inactive"
end

-- Lista de addons (requeridos / opcionales) con icono, uso, estado y botones
-- Activar / Descargar. La usan la ventana de bienvenida y el panel principal.
local ADDON_LIST = {
    { folder = "BetterBlizzFrames", label = "BetterBlizzFrames",
      useKey = "USE_BBF",
      url = "https://www.curseforge.com/wow/addons/better-blizz-frames" },
    { folder = "BetterBlizzPlates", label = "BetterBlizzPlates",
      useKey = "USE_BBP",
      url = "https://www.curseforge.com/wow/addons/better-blizz-plates" },
    { folder = "Auctionator", label = "Auctionator",
      useKey = "USE_AUCTIONATOR",
      url = "https://www.curseforge.com/wow/addons/auctionator" },
    { folder = "Details", label = "Details!",
      useKey = "USE_DETAILS",
      url = "https://www.curseforge.com/wow/addons/details" },
    { folder = "RXPGuides", label = "RXPGuides",
      useKey = "USE_RXP",
      url = "https://github.com/RestedXP/RXPGuides" },
}

StaticPopupDialogs["LIZEUI_COPY_URL"] = {
    text = "%s",
    button1 = CLOSE or "Close",
    hasEditBox = true,
    editBoxWidth = 320,
    OnShow = function(self, data)
        local editBox = self.editBox or self.EditBox
        if editBox then
            editBox:SetText(data or "")
            editBox:HighlightText()
            editBox:SetFocus()
        end
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    EditBoxOnTextChanged = function(self, data)
        if data and self:GetText() ~= data then
            self:SetText(data)
            self:HighlightText()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["LIZEUI_RELOAD_UI"] = {
    text = "",
    button1 = OKAY or "OK",
    button2 = CANCEL or "Cancel",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local addonStatusLists = {}

local function showReloadReminder()
    if not pendingReload then return end
    pendingReload = false
    StaticPopupDialogs["LIZEUI_RELOAD_UI"].text = L.POPUP_RELOAD
    StaticPopupDialogs["LIZEUI_RELOAD_UI"].button1 = L.RELOAD_UI
    StaticPopupDialogs["LIZEUI_RELOAD_UI"].button2 = L.LATER
    StaticPopup_Show("LIZEUI_RELOAD_UI")
end

-- parent: frame donde se dibuja; topY: posicion vertical de la primera cabecera;
-- inset: margen izquierdo y derecho. Devuelve { Update = fn, bottomY = numero }.
local function createAddonStatusList(parent, topY, inset)
    local list = {}
    local ROW_HEIGHT = 26
    local rows = {}
    local lastSection
    local rowIndex = 0
    local sectionOffset = 0

    local summary = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(inset + 5), topY)

    for _, entry in ipairs(ADDON_LIST) do
        local section = entry.required and L.SECTION_REQUIRED or L.SECTION_OPTIONAL
        if section ~= lastSection then
            local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            header:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, topY - rowIndex * ROW_HEIGHT - sectionOffset)
            header:SetText(section)
            sectionOffset = sectionOffset + 16
            lastSection = section
        end
        local y = topY - rowIndex * ROW_HEIGHT - sectionOffset
        rowIndex = rowIndex + 1

        local row = CreateFrame("Frame", nil, parent)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, y)
        row:SetPoint("RIGHT", parent, "RIGHT", -inset, 0)
        row:SetHeight(ROW_HEIGHT - 2)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, rowIndex % 2 == 0 and 0.03 or 0.06)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetText(entry.label)

        row.use = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.use:SetPoint("LEFT", row, "LEFT", 175, 0)
        row.use:SetText(L[entry.useKey])

        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.status:SetPoint("LEFT", row, "LEFT", 320, 0)

        row.link = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.link:SetSize(76, 20)
        row.link:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.link:SetText(L.BTN_DOWNLOAD)
        row.link:SetScript("OnClick", function()
            StaticPopupDialogs["LIZEUI_COPY_URL"].text = L.POPUP_COPY_URL
            StaticPopupDialogs["LIZEUI_COPY_URL"].button1 = L.CLOSE
            StaticPopup_Show("LIZEUI_COPY_URL", entry.label, nil, entry.url)
        end)

        row.enable = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.enable:SetSize(64, 20)
        row.enable:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.enable:SetText(L.BTN_ENABLE)
        row.enable:SetScript("OnClick", function()
            -- Se activa para este personaje (el cliente identifica al personaje por su
            -- GUID) y se guarda; el aviso de recargar sale al cerrar la ventana
            local enableAddOn = (C_AddOns and C_AddOns.EnableAddOn) or EnableAddOn
            if not enableAddOn then return end
            local ok = pcall(enableAddOn, entry.folder, UnitGUID("player"))
            if not ok then
                ok = pcall(enableAddOn, entry.folder, UnitName("player"))
            end
            if not ok then return end
            local saveAddOns = (C_AddOns and C_AddOns.SaveAddOns) or SaveAddOns
            if saveAddOns then pcall(saveAddOns) end
            enabledThisSession[entry.folder] = true
            pendingReload = true
            for _, other in ipairs(addonStatusLists) do other.Update() end
        end)

        row.entry = entry
        rows[#rows + 1] = row
    end

    list.bottomY = topY - rowIndex * ROW_HEIGHT - sectionOffset

    local reloadButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    reloadButton:SetSize(120, 20)
    reloadButton:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(inset + 4), list.bottomY - 4)
    reloadButton:SetText(L.RELOAD_UI)
    reloadButton:SetScript("OnClick", function() ReloadUI() end)

    list.Update = function()
        local loaded, needReload, missingRequired = 0, false, false
        for _, row in ipairs(rows) do
            local status, reason = getAddonStatus(row.entry.folder)
            local info = STATUS_INFO[status]
            row.icon:SetTexture(info.icon)
            if status == "blocked" then
                row.status:SetText(L.FMT_STATUS_BLOCKED:format(_G["ADDON_" .. reason] or reason))
            else
                row.status:SetText(L[info.textKey])
            end
            if status == "inactive" then row.enable:Show() else row.enable:Hide() end
            if status == "missing" then row.link:Show() else row.link:Hide() end
            if status == "ok" then loaded = loaded + 1 end
            if status == "reload" then needReload = true end
            if row.entry.required and status ~= "ok" then missingRequired = true end
        end
        summary:SetText((missingRequired and "|cffff5555" or "|cff55ff55") .. L.FMT_LOADED_COUNT:format(loaded, #rows) .. "|r")
        if needReload then reloadButton:Show() else reloadButton:Hide() end
    end

    addonStatusLists[#addonStatusLists + 1] = list
    return list
end

-- ---------------------------------------------------------------------------
-- Registro de cambios (languages/changelog) y ventana de novedades
-- ---------------------------------------------------------------------------
local function getChangelog()
    return (ns.Changelogs and (ns.Changelogs[ns.GetLanguage()] or ns.Changelogs.es)) or {}
end

local function formatChangelogLines(lines)
    local out = {}
    for _, line in ipairs(lines or {}) do
        if line:sub(1, 2) == "# " then
            out[#out + 1] = "|cffffd200" .. line:sub(3) .. "|r"
        elseif line:sub(1, 2) == "- " then
            out[#out + 1] = "|cff" .. ns.ACCENT_HEX .. "•|r " .. line:sub(3)
        else
            out[#out + 1] = line
        end
    end
    return table.concat(out, "\n")
end

-- Compara versiones "x.y.z" por partes numericas: -1 si a < b, 0 si iguales, 1 si a > b
local function compareVersions(a, b)
    local pa, pb = {}, {}
    for n in tostring(a or ""):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in tostring(b or ""):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

local function getAddonVersion()
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return getMetadata and getMetadata(addonName, "Version") or "0"
end

local whatsNew -- ventana; se crea la primera vez que hace falta
local openChangesPanel -- se asigna al crear el menu de Ajustes

local function createWhatsNewWindow()
    local f = CreateFrame("Frame", "LizeUIWhatsNewWindow", UIParent, "PortraitFrameTemplate")
    f:SetSize(620, 470)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetTitleOffsets(0, 0)
    f:SetBorder("HeldBagLayout")
    f:SetPortraitTextureSizeAndOffset(38, -5, 0)
    f:SetPortraitTextureRaw(ICON_PATH .. "lizeui_portrait.tga")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, "LizeUIWhatsNewWindow")
    f.CloseButton:SetScript("OnClick", function() f:Hide() end)

    f.title = f.TitleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("LEFT", f.TitleContainer, "LEFT", 40, 0)
    f.title:SetText(ns.BrandText() .. " - " .. L.WHATSNEW_TITLE)

    f.heading = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.heading:SetPoint("TOP", f, "TOP", 0, -58)
    f.heading:SetText(L.WHATSNEW_HEADING)

    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.5, 0.5, 0.5, 0.6)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", f, "TOPLEFT", 25, -82)
    line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -25, -82)

    local scrollOk, scroll = pcall(CreateFrame, "ScrollFrame", nil, f, "ScrollFrameTemplate")
    if not scrollOk or not scroll then
        scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    end
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -92)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 95)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(540, 300)
    scroll:SetScrollChild(content)
    f.text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    f.text:SetWidth(530)
    f.text:SetJustifyH("LEFT")
    f.text:SetJustifyV("TOP")
    f.text:SetSpacing(3)
    f.Resize = function()
        local width = scroll:GetWidth()
        if width and width > 0 then
            content:SetWidth(width)
            f.text:SetWidth(width - 10)
        end
        content:SetHeight(math.max(f.text:GetStringHeight() + 10, 10))
        scroll:SetVerticalScroll(0)
    end
    scroll:SetScript("OnSizeChanged", f.Resize)

    local bottomLine = f:CreateTexture(nil, "ARTWORK")
    bottomLine:SetColorTexture(0.5, 0.5, 0.5, 0.6)
    bottomLine:SetHeight(1)
    bottomLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 25, 85)
    bottomLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -25, 85)

    -- Activable: no volver a mostrar esta ventana al actualizar
    f.hideCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.hideCheck:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 25, 50)
    local hideLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hideLabel:SetPoint("LEFT", f.hideCheck, "RIGHT", 6, 0)
    hideLabel:SetText(L.WHATSNEW_DONT_SHOW)
    f.hideCheck:SetScript("OnClick", function(self)
        database.hideChangelogPopup = self:GetChecked() and true or false
    end)

    local closeButton = CreateFrame("Button", nil, f, "SharedButtonTemplate")
    closeButton:SetSize(150, 36)
    closeButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -25, 45)
    closeButton:SetText(L.CLOSE)
    closeButton:SetScript("OnClick", function() f:Hide() end)

    local changesButton = CreateFrame("Button", nil, f, "SharedButtonTemplate")
    changesButton:SetSize(150, 36)
    changesButton:SetPoint("RIGHT", closeButton, "LEFT", -10, 0)
    changesButton:SetText(L.WHATSNEW_ALL_CHANGES)
    changesButton:SetScript("OnClick", function()
        f:Hide()
        if openChangesPanel then openChangesPanel() end
    end)

    return f
end

-- Muestra los cambios de las versiones posteriores a "sinceVersion" (o solo la actual)
local function showWhatsNew(sinceVersion)
    whatsNew = whatsNew or createWhatsNewWindow()
    local current = getAddonVersion()
    local parts = {}
    for _, entry in ipairs(getChangelog()) do
        local newer = sinceVersion and compareVersions(entry.version, sinceVersion) > 0
        local isCurrent = compareVersions(entry.version, current) == 0
        if (newer and compareVersions(entry.version, current) <= 0) or (not sinceVersion and isCurrent) then
            parts[#parts + 1] = ("|cff" .. ns.ACCENT_HEX .. "%s|r\n|cffffffff%s|r\n\n%s"):format(
                L.FMT_CHANGELOG_META:format(entry.version, entry.date or ""), entry.title or "",
                formatChangelogLines(entry.lines))
        end
    end
    if #parts == 0 then return false end
    whatsNew.heading:SetText(L.FMT_WHATSNEW_HEADING:format(ns.BrandText(), current))
    whatsNew.text:SetText(table.concat(parts, "\n\n\n"))
    whatsNew.hideCheck:SetChecked(database.hideChangelogPopup == true)
    whatsNew:Show()
    whatsNew.Resize()
    return true
end

-- ---------------------------------------------------------------------------
-- Ventana de bienvenida / importacion (/lui). Se abre sola la primera vez que
-- cada PERSONAJE entra con LizeUI (LizeUICharDB es SavedVariablesPerCharacter).
-- ---------------------------------------------------------------------------

local function getCharDB()
    if type(LizeUICharDB) ~= "table" then LizeUICharDB = {} end
    return LizeUICharDB
end

local window = CreateFrame("Frame", "LoadProfilesWindow", UIParent, "PortraitFrameTemplate")
window:SetSize(660, 430)
window:SetPoint("CENTER")
window:SetFrameStrata("HIGH") -- por debajo de los StaticPopup (Descargar / Recargar)
window:SetTitleOffsets(0, 0)
window:SetBorder("HeldBagLayout")
window:SetPortraitTextureSizeAndOffset(38, -5, 0)
window:SetPortraitTextureRaw(ICON_PATH .. "lizeui_portrait.tga")
window:SetMovable(true)
window:EnableMouse(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", window.StartMoving)
window:SetScript("OnDragStop", window.StopMovingOrSizing)
window:Hide()
tinsert(UISpecialFrames, "LoadProfilesWindow") -- se cierra con Escape

window.title = window.TitleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
window.title:SetPoint("LEFT", window.TitleContainer, "LEFT", 40, 0)
window.title:SetText(ns.BrandText())
window.CloseButton:SetScript("OnClick", function()
    window:Hide()
end)
-- Se marca como vista en cuanto se muestra (al cerrar, con /lui o sola)
window:HookScript("OnShow", function()
    getCharDB().windowOpened = true
end)

-- El contenido se crea la primera vez que se muestra la ventana: asi los
-- textos usan el idioma guardado (al cargar el archivo aun no se ha leido).
local WINDOW_ADDONS, windowAddonList
local windowBuilt = false

local function buildWindowContent()
    if windowBuilt then return end
    windowBuilt = true

    local description = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    description:SetPoint("TOP", window, "TOP", 0, -58)
    description:SetText(L.WINDOW_DESCRIPTION)

    WINDOW_ADDONS = {
        { folder = "BetterBlizzFrames", label = "BetterBlizzFrames", x = -160,
          onClick = function() importProfile("BBF", "ImportProfile", LoadProfilesBetterBlizzFrames, "BetterBlizzFrames") end },
        { folder = "BetterBlizzPlates", label = "BetterBlizzPlates", x = 0,
          onClick = function() importProfile("BBP", "ImportProfile", LoadProfilesBetterBlizzPlater, "BetterBlizzPlates") end },
        { folder = "Details", label = "Details", x = 160,
          onClick = importDetailsProfile },
    }

    -- Misma lista de addons que en el panel principal
    windowAddonList = createAddonStatusList(window, -88, 20)

    local function createWindowButton(text, x, y, onClick)
        local button = CreateFrame("Button", nil, window, "SharedButtonTemplate")
        button:SetSize(150, 36)
        button:SetPoint("BOTTOM", window, "BOTTOM", x, y)
        button:SetText(text)
        button:SetScript("OnClick", onClick)
        return button
    end

    for _, entry in ipairs(WINDOW_ADDONS) do
        entry.button = createWindowButton(entry.label, entry.x, 80, entry.onClick)

        entry.button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(entry.label, 1, 1, 1)
            if self:IsEnabled() then
                GameTooltip:AddLine(L.FMT_TIP_IMPORT:format(entry.label), nil, nil, nil, true)
            else
                GameTooltip:AddLine(L.TIP_IMPORT_DISABLED, 1, 0.35, 0.35, true)
            end
            GameTooltip:Show()
        end)
        entry.button:SetScript("OnLeave", GameTooltip_Hide)
        entry.button:SetMotionScriptsWhileDisabled(true)
    end

    createWindowButton(L.BTN_RELOAD, 0, 30, function()
        getCharDB().windowOpened = true
        ReloadUI()
    end)
end

local function updateWindowStatus()
    buildWindowContent()
    windowAddonList.Update()
    -- Los botones de importacion solo funcionan si su addon esta cargado
    for _, entry in ipairs(WINDOW_ADDONS) do
        local loaded = getAddonStatus(entry.folder) == "ok"
        if loaded then entry.button:Enable() else entry.button:Disable() end
        entry.button:SetAlpha(loaded and 1 or 0.5)
    end
end
window:HookScript("OnShow", updateWindowStatus)
window:HookScript("OnHide", function() C_Timer.After(0.1, showReloadReminder) end)

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
    if enabled and not isAddonLoaded("BetterBlizzFrames") then enabled = false end
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
    if enabled and not isAddonLoaded("BetterBlizzFrames") then enabled = false end
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
    -- activo por defecto). Si "Marcos iconos buff / Debuff" de LizeUI esta activo,
    -- esos marcos ya los dibuja LizeUI: se desactiva la opcion de BBF para no
    -- duplicarlos. Si los marcos de LizeUI estan apagados, decide el usuario.
    local auraBordersRemoved = false
    if database.marcosIconosBuffDebuff and BetterBlizzFramesDB.darkModeUiAura ~= false then
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

local settingsCategory -- categoria "LizeUI" del menu de Ajustes (para /lui)

local function createSettings()
    if not Settings or not Settings.RegisterCanvasLayoutCategory then
        return
    end

    -- Panel principal: estado de addons (mas abajo) + importaciones
    local basePanel = createSettingsPanel("LizeUI")

    -- Panel DarkMode: edicion WoW Forever (marcos de auras y Dark Mode de BetterBlizzFrames)
    local darkPanel = createSettingsPanel(L.MENU_DARKMODE, "LizeUI")
    createDivider(darkPanel, L.DIV_WOW_FOREVER, -30)
    local buffCheckbox, buffCheckboxLabel = createSettingsCheckboxCustom(
        darkPanel,
        L.OPT_AURA_BORDERS,
        { "TOPLEFT", darkPanel, "TOPLEFT", 35, -45 },
        "marcosIconosBuffDebuff",
        function(isChecked)
            updateBuffDebuffBorders(isChecked)
            updateTargetAuraBorders(isChecked)
            applyDarkModeSettings()
            if darkPanel.UpdateSections then darkPanel.UpdateSections() end
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
        if darkPanel.UpdateSections then darkPanel.UpdateSections() end
    end

    local darkModeCheckbox = CreateFrame("CheckButton", nil, darkPanel, "UICheckButtonTemplate")
    darkModeCheckbox:SetPoint("TOPLEFT", darkPanel, "TOPLEFT", 35, -80)
    local darkModeCheckboxLabel = darkPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    darkModeCheckboxLabel:SetPoint("LEFT", darkModeCheckbox, "RIGHT", 8, 0)
    darkModeCheckboxLabel:SetText(L.OPT_DARK_MODE)
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

    darkModeSlider = CreateFrame("Slider", "LizeUIDarkModeIntensitySlider", darkPanel, "OptionsSliderTemplate")
    darkModeSlider:SetPoint("TOPLEFT", darkPanel, "TOPLEFT", 360, -80)
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
    local darkModeSliderValueDisplay = darkPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    darkModeSliderValueDisplay:SetPoint("BOTTOM", darkModeSlider, "TOP", 0, 4)
    local darkModeSliderUpdating = false
    darkModeSlider.Refresh = function(self)
        local currentVal = (BetterBlizzFramesDB and tonumber(BetterBlizzFramesDB.darkModeColor)) or 0.20
        darkModeSliderUpdating = true
        self:SetValue(currentVal)
        darkModeSliderUpdating = false
        darkModeSliderValueDisplay:SetText(L.FMT_DARK_INTENSITY:format(currentVal))
    end
    darkModeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 100 + 0.5) / 100
        darkModeSliderValueDisplay:SetText(L.FMT_DARK_INTENSITY:format(value))
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

    -- Secciones del Dark Mode: son las mismas opciones del desplegable
    -- "Opciones de Dark Mode" de BetterBlizzFrames (se guardan en su base de datos)
    createDivider(darkPanel, L.DIV_DARK_SECTIONS, -135)
    local DARK_SECTIONS = {
        { key = "darkModeUnitFrames",        label = L.DM_UNITFRAMES },
        { key = "darkModeActionBars",        label = L.DM_ACTIONBARS },
        { key = "darkModeCastbars",          label = L.DM_CASTBARS },
        { key = "darkModeUiAura",            label = L.DM_AURAS, auras = true },
        { key = "darkModeMinimap",           label = L.DM_MINIMAP },
        { key = "darkModeGameTooltip",       label = L.DM_TOOLTIP },
        { key = "darkModeEliteTexture",      label = L.DM_ELITE },
        { key = "darkModeObjectiveFrame",    label = L.DM_OBJECTIVES },
        { key = "darkModeNameplateResource", label = L.DM_NAMEPLATE_RESOURCE },
    }
    local darkSectionChecks = {}
    for index, section in ipairs(DARK_SECTIONS) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local check = CreateFrame("CheckButton", nil, darkPanel, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", darkPanel, "TOPLEFT", 35 + column * 320, -150 - row * 30)
        local label = darkPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", check, "RIGHT", 8, 0)
        label:SetText(section.label)
        check.label = label
        check.section = section
        check:SetScript("OnClick", function(self)
            if not BetterBlizzFramesDB then return end
            BetterBlizzFramesDB[section.key] = self:GetChecked() and true or false
            cancelDarkModeApply()
            applyDarkModeSettings()
            if section.auras and BBF and BBF.RefreshAllAuraFrames then
                BBF.RefreshAllAuraFrames()
            end
        end)
        if section.auras then
            check:SetMotionScriptsWhileDisabled(true)
            check:SetScript("OnEnter", function(self)
                if self:IsEnabled() then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(section.label, 1, 1, 1)
                GameTooltip:AddLine(L.DM_AURAS_LOCKED, nil, nil, nil, true)
                GameTooltip:Show()
            end)
            check:SetScript("OnLeave", GameTooltip_Hide)
        end
        darkSectionChecks[#darkSectionChecks + 1] = check
    end

    darkPanel.UpdateSections = function()
        local db = BetterBlizzFramesDB
        local darkOn = db and db.darkModeUi == true
        for _, check in ipairs(darkSectionChecks) do
            check:SetChecked(db and db[check.section.key] and true or false)
            local enabled = darkOn
            if check.section.auras and database.marcosIconosBuffDebuff then
                enabled = false -- los marcos de auras los dibuja LizeUI
            end
            if enabled then check:Enable() else check:Disable() end
            check:SetAlpha(enabled and 1 or 0.5)
            check.label:SetAlpha(enabled and 1 or 0.5)
        end
    end

    -- Sin BetterBlizzFrames: todo bloqueado y un aviso en el centro del panel
    local darkMissingFrame = CreateFrame("Frame", nil, darkPanel)
    darkMissingFrame:SetPoint("LEFT", darkPanel, "LEFT", 20, 0)
    darkMissingFrame:SetPoint("RIGHT", darkPanel, "RIGHT", -20, 0)
    darkMissingFrame:SetPoint("TOP", darkPanel, "TOP", 0, -150)
    darkMissingFrame:SetHeight(44)
    darkMissingFrame:SetFrameLevel(darkPanel:GetFrameLevel() + 20)
    local darkMissingBg = darkMissingFrame:CreateTexture(nil, "BACKGROUND")
    darkMissingBg:SetAllPoints()
    darkMissingBg:SetColorTexture(0, 0, 0, 0.75)
    local darkMissingText = darkMissingFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    darkMissingText:SetPoint("CENTER")
    darkMissingText:SetText(L.NAV_ADDON_MISSING)
    darkMissingFrame:Hide()

    local function setDarkWidget(widget, label, enabled)
        if not widget then return end
        if enabled then widget:Enable() else widget:Disable() end
        widget:SetAlpha(enabled and 1 or 0.3)
        if label then label:SetAlpha(enabled and 1 or 0.3) end
    end

    darkPanel.OnRefresh = function()
        if buffCheckbox and buffCheckbox.Refresh then
            buffCheckbox:Refresh()
        end
        if darkModeCheckbox and darkModeCheckbox.Refresh then
            darkModeCheckbox:Refresh()
        end
        if darkModeSlider and darkModeSlider.Refresh then
            darkModeSlider:Refresh()
        end
        updateDarkModeSliderState(BetterBlizzFramesDB and BetterBlizzFramesDB.darkModeUi == true)

        local hasBBF = isAddonLoaded("BetterBlizzFrames") and BetterBlizzFramesDB ~= nil
        if hasBBF then
            darkMissingFrame:Hide()
            setDarkWidget(buffCheckbox, buffCheckboxLabel, true)
            setDarkWidget(darkModeCheckbox, darkModeCheckboxLabel, true)
        else
            darkMissingFrame:Show()
            setDarkWidget(buffCheckbox, buffCheckboxLabel, false)
            setDarkWidget(darkModeCheckbox, darkModeCheckboxLabel, false)
            setDarkWidget(darkModeSlider, darkModeSliderValueDisplay, false)
            for _, check in ipairs(darkSectionChecks) do
                setDarkWidget(check, check.label, false)
            end
        end
    end
    darkPanel:SetScript("OnShow", darkPanel.OnRefresh)

    infoInstanciaButton = createSettingsButton(basePanel, "Info Instancia", 214, { "TOP", basePanel, "TOP", 0, -440 }, function()
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

    createDivider(basePanel, L.DIV_IMPORTS, -275)

    local importText = basePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    importText:SetPoint("TOPLEFT", basePanel, "TOPLEFT", 25, -290)
    importText:SetPoint("RIGHT", basePanel, "RIGHT", -25, 0)
    importText:SetJustifyH("LEFT")
    importText:SetJustifyV("TOP")
    importText:SetText(L.IMPORT_TEXT)

    local function createImportButton(text, xOffset, yOffset, onClick)
        local button = CreateFrame("Button", nil, basePanel, "SharedButtonTemplate")
        button:SetSize(150, 36)
        button:SetPoint("TOP", basePanel, "TOP", xOffset, yOffset)
        button:SetText(text)
        button:SetScript("OnClick", onClick)
        return button
    end
    -- Fila de importaciones (centrada) y Reload debajo, en el centro
    createImportButton("BetterBlizzFrames", -160, -330, function()
        importProfile("BBF", "ImportProfile", LoadProfilesBetterBlizzFrames, "BetterBlizzFrames")
    end)
    createImportButton("BetterBlizzPlates", 0, -330, function()
        importProfile("BBP", "ImportProfile", LoadProfilesBetterBlizzPlater, "BetterBlizzPlates")
    end)
    createImportButton("Details", 160, -330, importDetailsProfile)
    createImportButton(L.BTN_RELOAD, 0, -376, function()
        getCharDB().windowOpened = true
        ReloadUI()
    end)

    if infoInstanciaButton and not database.devMode then
        infoInstanciaButton:Hide()
    end

    -- Panel de navegacion: ruta de RXPGuides en minimapa y mapa del mundo
    local navPanel = createSettingsPanel(L.MENU_NAVIGATION, "LizeUI")
    local function refreshNavRoute()
        if NavRoute then NavRoute:Refresh() end
    end
    createDivider(navPanel, L.DIV_NAV_ROUTE, -30)

    local navControls = {}
    local navEnabledCheckbox, navEnabledLabel = createSettingsCheckboxCustom(
        navPanel, L.OPT_NAV_ENABLE,
        { "TOPLEFT", navPanel, "TOPLEFT", 35, -50 },
        "navRouteEnabled",
        function()
            navPanel.UpdateState()
            refreshNavRoute()
        end
    )
    navEnabledCheckbox.lizeLabel = navEnabledLabel
    local function addNavCheckbox(text, point, key)
        local checkbox, label = createSettingsCheckboxCustom(navPanel, text, point, key, refreshNavRoute)
        navControls[#navControls + 1] = { widget = checkbox, label = label }
        return checkbox
    end
    local navArrowsCheckbox = addNavCheckbox(L.OPT_NAV_ARROWS, { "TOPLEFT", navPanel, "TOPLEFT", 355, -50 }, "navRouteArrows")
    local navMinimapCheckbox = addNavCheckbox(L.OPT_NAV_MINIMAP, { "TOPLEFT", navPanel, "TOPLEFT", 35, -85 }, "navRouteMinimap")
    local navWorldMapCheckbox = addNavCheckbox(L.OPT_NAV_WORLDMAP, { "TOPLEFT", navPanel, "TOPLEFT", 355, -85 }, "navRouteWorldMap")

    createDivider(navPanel, L.DIV_APPEARANCE, -135)

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
        { "TOPLEFT", navPanel, "TOPLEFT", 60, -180 }, 1, L.FMT_NAV_THICKNESS)
    local navAlphaSlider = addNavSlider("LizeUINavRouteAlphaSlider", 0.2, 1, 0.05, "navRouteAlpha",
        { "TOPLEFT", navPanel, "TOPLEFT", 360, -180 }, 2, L.FMT_NAV_ALPHA)
    local navGraySlider = addNavSlider("LizeUINavRouteGraySlider", 0.3, 1, 0.05, "navRouteGray",
        { "TOPLEFT", navPanel, "TOPLEFT", 60, -245 }, 2, L.FMT_NAV_GRAY)
    local navFutureSlider = addNavSlider("LizeUINavRouteFutureSlider", 0, 5, 1, "navRouteFutureSteps",
        { "TOPLEFT", navPanel, "TOPLEFT", 360, -245 }, 0, L.FMT_NAV_FUTURE)

    local navStatusText = navPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    navStatusText:SetPoint("TOPLEFT", navPanel, "TOPLEFT", 20, -300)
    navStatusText:SetWidth(640)
    navStatusText:SetJustifyH("LEFT")
    navStatusText:SetJustifyV("TOP")

    local function updateNavStatus()
        local lines = {}
        if isAddonLoaded("RXPGuides") and NavRoute and NavRoute:IsAvailable() then
            lines[#lines + 1] = L.NAV_STATUS_OK
        else
            lines[#lines + 1] = L.NAV_STATUS_MISSING
        end
        if isAddonLoaded("RXP_Navigator") then
            lines[#lines + 1] = L.NAV_STATUS_NAVIGATOR
        end
        navStatusText:SetText(table.concat(lines, "\n\n"))
    end

    -- Sin RXPGuides: todo bloqueado y un aviso en el centro del panel
    local navMissingFrame = CreateFrame("Frame", nil, navPanel)
    navMissingFrame:SetPoint("LEFT", navPanel, "LEFT", 20, 0)
    navMissingFrame:SetPoint("RIGHT", navPanel, "RIGHT", -20, 0)
    navMissingFrame:SetPoint("TOP", navPanel, "TOP", 0, -150)
    navMissingFrame:SetHeight(44)
    navMissingFrame:SetFrameLevel(navPanel:GetFrameLevel() + 20)
    local navMissingBg = navMissingFrame:CreateTexture(nil, "BACKGROUND")
    navMissingBg:SetAllPoints()
    navMissingBg:SetColorTexture(0, 0, 0, 0.75)
    local navMissingText = navMissingFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    navMissingText:SetPoint("CENTER")
    navMissingText:SetText(L.NAV_ADDON_MISSING)
    navMissingFrame:Hide()

    local navResetButton
    local function navAddonAvailable()
        return isAddonLoaded("RXPGuides") and NavRoute and NavRoute:IsAvailable() and true or false
    end

    local function setNavWidget(widget, label, enabled, dimAlpha)
        if enabled then widget:Enable() else widget:Disable() end
        widget:SetAlpha(enabled and 1 or dimAlpha)
        if label then label:SetAlpha(enabled and 1 or dimAlpha) end
    end

    navPanel.UpdateState = function()
        local available = navAddonAvailable()
        local enabled = available and database.navRouteEnabled == true
        local dim = available and 0.5 or 0.3
        setNavWidget(navEnabledCheckbox, navEnabledCheckbox.lizeLabel, available, dim)
        for _, control in ipairs(navControls) do
            setNavWidget(control.widget, control.label, enabled, dim)
        end
        if navResetButton then setNavWidget(navResetButton, nil, available, dim) end
        if available then navMissingFrame:Hide() else navMissingFrame:Show() end
    end

    local function refreshNavPanel()
        for _, widget in ipairs({ navEnabledCheckbox, navArrowsCheckbox, navMinimapCheckbox, navWorldMapCheckbox,
            navThicknessSlider, navAlphaSlider, navGraySlider, navFutureSlider }) do
            if widget and widget.Refresh then widget:Refresh() end
        end
        navPanel.UpdateState()
        updateNavStatus()
    end

    navResetButton = createSettingsButton(navPanel, L.BTN_RESET, 214, { "TOP", navPanel, "TOP", 0, -380 }, function()
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
    -- El contenido no cabe en el lienzo de Ajustes: va dentro de un ScrollFrame
    local utilFrame = createSettingsPanel(L.MENU_UTILITIES, "LizeUI")
    local scrollOk, utilScroll = pcall(CreateFrame, "ScrollFrame", nil, utilFrame, "ScrollFrameTemplate")
    if not scrollOk or not utilScroll then
        utilScroll = CreateFrame("ScrollFrame", nil, utilFrame, "UIPanelScrollFrameTemplate")
    end
    utilScroll:SetPoint("TOPLEFT", utilFrame, "TOPLEFT", 0, -2)
    utilScroll:SetPoint("BOTTOMRIGHT", utilFrame, "BOTTOMRIGHT", -26, 2)
    local utilPanel = CreateFrame("Frame", nil, utilScroll)
    utilPanel:SetSize(640, 925)
    utilScroll:SetScrollChild(utilPanel)
    utilScroll:SetScript("OnSizeChanged", function(_, width)
        if width and width > 0 then utilPanel:SetWidth(width) end
    end)
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

    -- Seccion: Chat mejorado
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local function createSoundPicker(key, x, y)
        local dropdown = CreateFrame("DropdownButton", nil, utilPanel, "WowStyle1DropdownTemplate")
        dropdown:SetPoint("TOPLEFT", utilPanel, "TOPLEFT", x, y)
        dropdown:SetWidth(180)
        -- Icono de escuchar a la derecha de cada sonido. Es solo una textura: el
        -- clic lo recibe la linea del menu y, si el raton esta sobre el icono, se
        -- reproduce el sonido sin seleccionarlo y sin cerrar el menu.
        local playIcons = {}
        local function attachPlayIcon(button, name)
            local icon
            if button.AttachTexture then
                icon = button:AttachTexture()
            else
                icon = button.lizePlayIcon or button:CreateTexture(nil, "OVERLAY")
                button.lizePlayIcon = icon
            end
            icon:SetSize(16, 16)
            icon:ClearAllPoints()
            icon:SetPoint("RIGHT", button, "RIGHT", -2, 0)
            icon:SetTexture("Interface\\Common\\VoiceChat-Speaker")
            icon:Show()
            playIcons[name] = icon
        end
        local function isOverPlayIcon(name)
            local icon = playIcons[name]
            return icon and icon:IsVisible() and icon:IsMouseOver()
        end
        local keepOpen = MenuResponse and MenuResponse.Open

        dropdown:SetupMenu(function(_, rootDescription)
            rootDescription:SetScrollMode(320)
            -- Primero los sonidos de LizeUI y despues el resto, cada grupo en orden alfabetico
            local own, others = {}, {}
            for _, name in ipairs(LSM and LSM:List("sound") or {}) do
                if name:find("^LizeUI ") then own[#own + 1] = name else others[#others + 1] = name end
            end
            table.sort(own)
            table.sort(others)
            local function addSound(name)
                -- Los espacios finales dejan sitio al boton de escuchar
                local radio = rootDescription:CreateRadio(name .. "      ",
                    function() return database[key] == name end,
                    function()
                        if isOverPlayIcon(name) then
                            -- Solo escuchar: no cambia la seleccion y el menu sigue abierto
                            if Utilities then Utilities:PlaySoundByName(name) end
                            return keepOpen
                        end
                        database[key] = name
                        if Utilities then Utilities:PlaySoundByName(name) end
                    end)
                if radio.AddInitializer then
                    radio:AddInitializer(function(button) pcall(attachPlayIcon, button, name) end)
                end
                if radio.AddResetter then
                    radio:AddResetter(function(button)
                        if button.lizePlayIcon then button.lizePlayIcon:Hide() end
                    end)
                end
            end
            for _, name in ipairs(own) do addSound(name) end
            if #own > 0 and #others > 0 and rootDescription.CreateDivider then
                rootDescription:CreateDivider()
            end
            for _, name in ipairs(others) do addSound(name) end
        end)
        dropdown.Refresh = function(self) if self.GenerateMenu then self:GenerateMenu() end end
        utilRefreshers[#utilRefreshers + 1] = dropdown

        local preview = CreateFrame("Button", nil, utilPanel, "UIPanelButtonTemplate")
        preview:SetSize(80, 22)
        preview:SetPoint("LEFT", dropdown, "RIGHT", 6, 0)
        preview:SetText(L.BTN_PREVIEW)
        preview:SetScript("OnClick", function()
            if Utilities then Utilities:PlaySoundByName(database[key]) end
        end)
        return { widget = dropdown, preview = preview }
    end
    local function setPickerEnabled(picker, enabled)
        for _, w in ipairs({ picker.widget, picker.preview }) do
            if enabled then w:Enable() else w:Disable() end
            w:SetAlpha(enabled and 1 or 0.5)
        end
    end
    local function refreshChatModule()
        if Utilities then Utilities:RefreshChat() end
    end

    createDivider(utilPanel, L.DIV_CHAT, -30)
    local chatHideGuild = addUtilCheckbox(L.OPT_CHAT_HIDE_GUILD, COL1, -45, "chatHideGuildLogin", refreshChatModule,
        L.OPT_CHAT_HIDE_GUILD_DESC)
    local chatGuildSound = addUtilCheckbox(L.OPT_CHAT_GUILD_SOUND, COL2, -45, "chatMuteGuildLogin", refreshChatModule,
        L.OPT_CHAT_GUILD_SOUND_DESC)

    local chatGuildChat = addUtilCheckbox(L.OPT_CHAT_GUILD_CHAT, COL1, -80, "chatGuildChatSound", refreshChatModule,
        L.OPT_CHAT_GUILD_CHAT_DESC)
    local guildChatSoundPicker = createSoundPicker("chatGuildChatSoundName", COL2 + 20, -82)

    local chatWhisper = addUtilCheckbox(L.OPT_CHAT_WHISPER, COL1, -115, "chatWhisperSound", refreshChatModule,
        L.OPT_CHAT_WHISPER_DESC)
    local whisperSoundPicker = createSoundPicker("chatWhisperSoundName", COL2 + 20, -117)

    local chatKeywords = addUtilCheckbox(L.OPT_CHAT_KEYWORDS, COL1, -150, "chatKeywordAlert", refreshChatModule,
        L.OPT_CHAT_KEYWORDS_DESC)
    local keywordSoundPicker = createSoundPicker("chatKeywordSound", COL2 + 20, -152)

    local chatWordsBox = CreateFrame("EditBox", nil, utilPanel, "InputBoxTemplate")
    chatWordsBox:SetSize(330, 20)
    chatWordsBox:SetPoint("TOPLEFT", utilPanel, "TOPLEFT", COL1 + 240, -187)
    chatWordsBox:SetAutoFocus(false)
    chatWordsBox:SetMaxLetters(250)
    local chatWordsLabel = utilPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chatWordsLabel:SetPoint("RIGHT", chatWordsBox, "LEFT", -10, 0)
    chatWordsLabel:SetText(L.CHAT_KEYWORDS_LABEL)
    local function saveChatWords()
        database.chatKeywords = strtrim(chatWordsBox:GetText() or "")
    end
    chatWordsBox:SetScript("OnTextChanged", function(_, userInput)
        if userInput then saveChatWords() end
    end)
    chatWordsBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    chatWordsBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    chatWordsBox:SetScript("OnEditFocusLost", saveChatWords)
    chatWordsBox.Refresh = function(self) self:SetText(database.chatKeywords or "") end
    utilRefreshers[#utilRefreshers + 1] = chatWordsBox
    local chatWords = { widget = chatWordsBox, label = chatWordsLabel }

    -- Seccion: Tooltip
    createDivider(utilPanel, L.DIV_TOOLTIP, -235)
    local tipEnable = addUtilCheckbox(L.OPT_TIP_ENABLE, COL1, -250, "tipEnabled", refreshTooltipModule,
        L.OPT_TIP_ENABLE_DESC)
    local tipHealth = addUtilCheckbox(L.OPT_TIP_NOHEALTH, COL2, -250, "tipNoHealthBar", refreshTooltipModule)
    local tipRank = addUtilCheckbox(L.OPT_TIP_RANK, COL1, -280, "tipShowRank")
    local tipOtherRank = addUtilCheckbox(L.OPT_TIP_OTHERRANK, COL2, -280, "tipShowOtherRank")
    local tipTarget = addUtilCheckbox(L.OPT_TIP_TARGET, COL1, -310, "tipShowTarget")
    local tipFaction = addUtilCheckbox(L.OPT_TIP_FACTION, COL2, -310, "tipBackFaction", nil,
        L.OPT_TIP_FACTION_DESC)
    local tipCombat = addUtilCheckbox(L.OPT_TIP_COMBAT, COL1, -340, "tipHideInCombat")
    local tipShift = addUtilCheckbox(L.OPT_TIP_SHIFT, COL2, -340, "tipHideShiftOverride")

    local ANCHOR_NAMES = { L.ANCHOR_DEFAULT, L.ANCHOR_CURSOR, L.ANCHOR_CURSOR_LEFT, L.ANCHOR_CURSOR_RIGHT }
    local anchorButton = CreateFrame("Button", nil, utilPanel, "UIPanelButtonTemplate")
    anchorButton:SetSize(200, 24)
    anchorButton:SetPoint("TOPLEFT", utilPanel, "TOPLEFT", COL1 + 25, -390)
    local anchorLabel = utilPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    anchorLabel:SetPoint("BOTTOM", anchorButton, "TOP", 0, 4)
    anchorLabel:SetText(L.TIP_ANCHOR_LABEL)
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

    local tipScale = addUtilSlider("LizeUITipScaleSlider", 0.5, 2, 0.05, "tipScale", COL2 + 5, -395, 2, L.FMT_TIP_SCALE,
        refreshTooltipModule)
    local tipX = addUtilSlider("LizeUITipCursorXSlider", -128, 128, 1, "tipCursorX", COL1 + 35, -445, 0, L.FMT_TIP_X)
    local tipY = addUtilSlider("LizeUITipCursorYSlider", -128, 128, 1, "tipCursorY", COL2 + 5, -445, 0, L.FMT_TIP_Y)

    local tipAuction = addUtilCheckbox(L.OPT_TIP_AUCTION, COL1, -475, "tipAuctionNet", nil,
        L.OPT_TIP_AUCTION_DESC)
    local tipAuctionMissing = utilPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tipAuctionMissing:SetPoint("TOPLEFT", utilPanel, "TOPLEFT", COL2, -483)
    tipAuctionMissing:SetText(L.TIP_AUCTION_MISSING)

    -- Seccion: Automatizacion
    createDivider(utilPanel, L.DIV_AUTOMATION, -525)
    do
        local groupLabel = utilPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        groupLabel:SetPoint("TOPLEFT", utilPanel, "TOPLEFT", COL1 + 4, -535)
        groupLabel:SetText(L.GROUP_VENDOR)
    end
    local autoRepair = addUtilCheckbox(L.OPT_REPAIR, COL1, -550, "autoRepair", refreshAutomationModule,
        L.OPT_REPAIR_DESC)
    local autoRepairGuild = addUtilCheckbox(L.OPT_REPAIR_GUILD, COL2, -550, "autoRepairGuild", nil,
        L.OPT_REPAIR_GUILD_DESC)
    local autoSell = addUtilCheckbox(L.OPT_SELL_JUNK, COL1, -580, "autoSellJunk", refreshAutomationModule,
        L.OPT_SELL_JUNK_DESC)
    local autoSellGear = addUtilCheckbox(L.OPT_SELL_NOGEAR, COL2, -580, "autoSellNoGreyGear", nil,
        L.OPT_SELL_NOGEAR_DESC)
    local autoSummary = addUtilCheckbox(L.OPT_SUMMARY, COL1, -610, "autoShowSummary")
    do
        local groupLabel = utilPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        groupLabel:SetPoint("TOPLEFT", utilPanel, "TOPLEFT", COL1 + 4, -650)
        groupLabel:SetText(L.GROUP_LOOT)
    end
    local fasterLoot = addUtilCheckbox(L.OPT_FASTER_LOOT, COL1, -665, "fasterLoot", refreshAutomationModule,
        L.OPT_FASTER_LOOT_DESC)
    do
        local groupLabel = utilPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        groupLabel:SetPoint("TOPLEFT", utilPanel, "TOPLEFT", COL1 + 4, -705)
        groupLabel:SetText(L.GROUP_PARTY)
    end
    local inviteWhisper = addUtilCheckbox(L.OPT_INVITE_WHISPER, COL1, -720, "inviteFromWhisper", refreshAutomationModule,
        L.OPT_INVITE_WHISPER_DESC)

    local keywordBox = CreateFrame("EditBox", nil, utilPanel, "InputBoxTemplate")
    keywordBox:SetSize(110, 20)
    keywordBox:SetPoint("TOPLEFT", utilPanel, "TOPLEFT", COL2 + 105, -724)
    keywordBox:SetAutoFocus(false)
    keywordBox:SetMaxLetters(30)
    local keywordLabel = utilPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    keywordLabel:SetPoint("RIGHT", keywordBox, "LEFT", -10, 0)
    keywordLabel:SetText(L.KEYWORD_LABEL)
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

    local inviteFriends = addUtilCheckbox(L.OPT_INVITE_FRIENDS, COL1, -750, "inviteFriendsOnly")
    local acceptFriends = addUtilCheckbox(L.OPT_ACCEPT_FRIENDS, COL2, -750, "acceptPartyFriends", refreshAutomationModule,
        L.OPT_ACCEPT_FRIENDS_DESC)
    local friendlyGuild = addUtilCheckbox(L.OPT_FRIENDLY_GUILD, COL1, -780, "friendlyGuild", nil,
        L.OPT_FRIENDLY_GUILD_DESC)
    local lootDelay = addUtilSlider("LizeUIFasterLootDelaySlider", 0.1, 0.3, 0.1, "fasterLootDelay", COL2 + 5, -672, 1,
        L.FMT_LOOT_DELAY)

    -- Seccion: Interfaz
    createDivider(utilPanel, L.DIV_INTERFACE, -830)
    local issueReport = addUtilCheckbox(L.OPT_ISSUE_REPORT, COL1, -845, "eliminarBotonIssueReport",
        function() updateIssueReportButton(database.eliminarBotonIssueReport == true) end,
        L.OPT_ISSUE_REPORT_DESC)

    local utilStatusText = utilPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    utilStatusText:SetPoint("TOPLEFT", utilPanel, "TOPLEFT", 20, -890)
    utilStatusText:SetWidth(640)
    utilStatusText:SetJustifyH("LEFT")
    utilStatusText:SetJustifyV("TOP")

    local function updateUtilStatus()
        local conflicts = Utilities and Utilities:GetLeatrixConflicts() or {}
        if #conflicts > 0 then
            utilStatusText:SetText(L.LEATRIX_CONFLICT:format(table.concat(conflicts, ", ")))
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

        setPickerEnabled(guildChatSoundPicker, database.chatGuildChatSound == true)
        setPickerEnabled(whisperSoundPicker, database.chatWhisperSound == true)
        setPickerEnabled(keywordSoundPicker, database.chatKeywordAlert == true)
        setControlEnabled(chatWords, database.chatKeywordAlert == true)

        local hasAuctionator = isAddonLoaded("Auctionator") and Utilities and Utilities:IsAuctionatorAvailable()
        setControlEnabled(tipAuction, hasAuctionator and true or false)
        if hasAuctionator then tipAuctionMissing:Hide() else tipAuctionMissing:Show() end
    end

    local function refreshUtilPanel()
        for _, widget in ipairs(utilRefreshers) do
            if widget.Refresh then widget:Refresh() end
        end
        utilPanel.UpdateState()
        updateUtilStatus()
    end
    utilFrame.OnRefresh = refreshUtilPanel
    utilFrame:SetScript("OnShow", refreshUtilPanel)
    refreshUtilPanel()

    -- Panel principal, parte superior: estado de addons
    createDivider(basePanel, L.DIV_ADDON_STATUS, -30)
    local baseAddonList = createAddonStatusList(basePanel, -45, 25)
    basePanel.UpdateStatus = baseAddonList.Update
    basePanel.OnRefresh = basePanel.UpdateStatus
    basePanel:SetScript("OnShow", basePanel.UpdateStatus)
    basePanel.UpdateStatus()

    -- Panel de cambios: lista de versiones a la izquierda y detalle a la derecha
    -- (los textos estan en languages/changelog/esES.lua y enUS.lua)
    local changesPanel = createSettingsPanel(L.MENU_CHANGES, "LizeUI")
    local changelog = getChangelog()

    local versionsLabel = changesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionsLabel:SetPoint("TOPLEFT", changesPanel, "TOPLEFT", 25, -25)
    versionsLabel:SetText(L.CHANGELOG_VERSIONS)

    local changesTitle = changesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    changesTitle:SetPoint("TOPLEFT", changesPanel, "TOPLEFT", 175, -22)
    changesTitle:SetPoint("RIGHT", changesPanel, "RIGHT", -25, 0)
    changesTitle:SetJustifyH("LEFT")

    local changesMeta = changesPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    changesMeta:SetPoint("TOPLEFT", changesTitle, "BOTTOMLEFT", 0, -6)

    local changesLine = changesPanel:CreateTexture(nil, "ARTWORK")
    changesLine:SetColorTexture(0.5, 0.5, 0.5, 0.6)
    changesLine:SetHeight(1)
    changesLine:SetPoint("TOPLEFT", changesPanel, "TOPLEFT", 175, -64)
    changesLine:SetPoint("RIGHT", changesPanel, "RIGHT", -25, 0)

    local columnLine = changesPanel:CreateTexture(nil, "ARTWORK")
    columnLine:SetColorTexture(0.5, 0.5, 0.5, 0.4)
    columnLine:SetWidth(1)
    columnLine:SetPoint("TOPLEFT", changesPanel, "TOPLEFT", 160, -22)
    columnLine:SetPoint("BOTTOMLEFT", changesPanel, "BOTTOMLEFT", 160, 20)

    -- Texto del detalle dentro de un ScrollFrame
    local changesScrollOk, changesScroll = pcall(CreateFrame, "ScrollFrame", nil, changesPanel, "ScrollFrameTemplate")
    if not changesScrollOk or not changesScroll then
        changesScroll = CreateFrame("ScrollFrame", nil, changesPanel, "UIPanelScrollFrameTemplate")
    end
    changesScroll:SetPoint("TOPLEFT", changesPanel, "TOPLEFT", 175, -74)
    changesScroll:SetPoint("BOTTOMRIGHT", changesPanel, "BOTTOMRIGHT", -30, 20)
    local changesContent = CreateFrame("Frame", nil, changesScroll)
    changesContent:SetSize(400, 400)
    changesScroll:SetScrollChild(changesContent)
    local changesText = changesContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    changesText:SetPoint("TOPLEFT", changesContent, "TOPLEFT", 0, 0)
    changesText:SetWidth(400)
    changesText:SetJustifyH("LEFT")
    changesText:SetJustifyV("TOP")
    changesText:SetSpacing(3)
    local function resizeChangesText()
        local width = changesScroll:GetWidth()
        if not width or width <= 0 then return end
        changesContent:SetWidth(width)
        changesText:SetWidth(width - 10)
        changesContent:SetHeight(math.max(changesText:GetStringHeight() + 10, 10))
    end
    changesScroll:SetScript("OnSizeChanged", resizeChangesText)

    local versionRows = {}
    local function selectVersion(index)
        local entry = changelog[index]
        for i, row in ipairs(versionRows) do
            local selected = i == index
            row.bg:SetColorTexture(selected and 0 or 1, selected and 0.75 or 1, selected and 0.98 or 1,
                selected and 0.35 or (i % 2 == 0 and 0.03 or 0.06))
            row.text:SetFontObject(selected and "GameFontHighlight" or "GameFontNormal")
        end
        if not entry then
            changesTitle:SetText(L.CHANGELOG_EMPTY)
            changesMeta:SetText("")
            changesText:SetText("")
        else
            changesTitle:SetText(entry.title or entry.version)
            changesMeta:SetText(L.FMT_CHANGELOG_META:format(entry.version, entry.date or ""))
            changesText:SetText(formatChangelogLines(entry.lines))
        end
        changesScroll:SetVerticalScroll(0)
        resizeChangesText()
    end

    for index, entry in ipairs(changelog) do
        local row = CreateFrame("Button", nil, changesPanel)
        row:SetSize(125, 24)
        row:SetPoint("TOPLEFT", changesPanel, "TOPLEFT", 22, -42 - (index - 1) * 26)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetPoint("LEFT", row, "LEFT", 10, 0)
        row.text:SetText((index == 1 and "|TInterface\\COMMON\\Indicator-Green:12:12:0:0|t " or "") .. entry.version)
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.08)
        row:SetScript("OnClick", function() selectVersion(index) end)
        versionRows[index] = row
    end
    selectVersion(1)

    -- Activable: mostrar la ventana de novedades al actualizar (el mismo ajuste que su casilla)
    local showPopupCheck = CreateFrame("CheckButton", nil, changesPanel, "UICheckButtonTemplate")
    showPopupCheck:SetPoint("BOTTOMLEFT", changesPanel, "BOTTOMLEFT", 20, 15)
    local showPopupLabel = changesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    showPopupLabel:SetPoint("TOPLEFT", showPopupCheck, "TOPRIGHT", 0, -6)
    showPopupLabel:SetWidth(110)
    showPopupLabel:SetJustifyH("LEFT")
    showPopupLabel:SetText(L.OPT_SHOW_WHATSNEW)
    showPopupCheck:SetScript("OnClick", function(self)
        database.hideChangelogPopup = not self:GetChecked()
    end)
    changesPanel:SetScript("OnShow", function()
        showPopupCheck:SetChecked(database.hideChangelogPopup ~= true)
        resizeChangesText()
    end)

    -- Panel de soporte: cabecera con logo, donaciones y enlaces
    -- (mismos datos que la seccion Informacion de ElvUI_LizeUI)
    local supportPanel = createSettingsPanel(L.MENU_SUPPORT, "LizeUI")
    local LIZEUI_GRADIENT = ns.BrandText()
    local PATREON_URL = "https://www.patreon.com/cw/Lizerius"
    local CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/lizeui-forever"

    local supportLogo = supportPanel:CreateTexture(nil, "ARTWORK")
    supportLogo:SetSize(64, 64)
    supportLogo:SetPoint("TOPLEFT", supportPanel, "TOPLEFT", 25, -20)
    supportLogo:SetTexture(ns.LOGO_FULL)

    local supportTitle = supportPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    supportTitle:SetPoint("TOPLEFT", supportLogo, "TOPRIGHT", 14, -8)
    supportTitle:SetText(LIZEUI_GRADIENT)

    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local addonVersion = getMetadata and getMetadata(addonName, "Version") or "?"
    local supportSubtitle = supportPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    supportSubtitle:SetPoint("TOPLEFT", supportTitle, "BOTTOMLEFT", 0, -6)
    supportSubtitle:SetText(L.SUPPORT_SUBTITLE .. "  |cff888888" .. L.FMT_VERSION:format(addonVersion) .. "|r")

    local function showCopyUrl(title, url)
        StaticPopupDialogs["LIZEUI_COPY_URL"].text = "%s"
        StaticPopupDialogs["LIZEUI_COPY_URL"].button1 = L.CLOSE
        StaticPopup_Show("LIZEUI_COPY_URL", title, nil, url)
    end

    -- Donaciones
    createDivider(supportPanel, L.DIV_DONATIONS, -110)
    local donateText = supportPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    donateText:SetPoint("TOPLEFT", supportPanel, "TOPLEFT", 25, -128)
    donateText:SetPoint("RIGHT", supportPanel, "RIGHT", -25, 0)
    donateText:SetJustifyH("LEFT")
    donateText:SetSpacing(3)
    donateText:SetText(L.DONATE_LINE1_FMT:format(LIZEUI_GRADIENT) .. "\n\n" .. L.DONATE_LINE2 .. "\n" .. L.DONATE_LINE3)

    local patreonButton = CreateFrame("Button", nil, supportPanel, "SharedButtonTemplate")
    patreonButton:SetSize(190, 36)
    patreonButton:SetPoint("TOP", supportPanel, "TOP", 0, -215)
    patreonButton:SetText(("|T%scafe.tga:16:16:0:0|t %s"):format(ICON_PATH, L.BTN_PATREON))
    patreonButton:SetScript("OnClick", function()
        showCopyUrl(L.BTN_PATREON, PATREON_URL)
    end)

    -- Enlaces
    createDivider(supportPanel, L.DIV_LINKS, -280)
    local linksText = supportPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    linksText:SetPoint("TOPLEFT", supportPanel, "TOPLEFT", 25, -298)
    linksText:SetText(L.LINKS_DESC)

    local function createLinkRow(label, url, y)
        local name = supportPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        name:SetPoint("TOPLEFT", supportPanel, "TOPLEFT", 30, y)
        name:SetText(label)

        local box = CreateFrame("EditBox", nil, supportPanel, "InputBoxTemplate")
        box:SetSize(420, 20)
        box:SetPoint("LEFT", name, "LEFT", 110, 0)
        box:SetAutoFocus(false)
        box:SetText(url)
        box:SetCursorPosition(0)
        -- Solo lectura: siempre vuelve a la URL y la selecciona para copiar
        box:SetScript("OnTextChanged", function(self, userInput)
            if userInput then self:SetText(url); self:HighlightText() end
        end)
        box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        box:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0); self:SetCursorPosition(0) end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        return box
    end
    createLinkRow(L.LINK_CURSEFORGE, CURSEFORGE_URL, -325)
    createLinkRow(L.LINK_PATREON, PATREON_URL, -355)

    local category = Settings.RegisterCanvasLayoutCategory(basePanel, ns.BrandText(), "LizeUI")
    Settings.RegisterAddOnCategory(category)
    Settings.RegisterCanvasLayoutSubcategory(category, utilFrame, L.MENU_UTILITIES, L.MENU_UTILITIES)
    Settings.RegisterCanvasLayoutSubcategory(category, darkPanel, L.MENU_DARKMODE, L.MENU_DARKMODE)
    Settings.RegisterCanvasLayoutSubcategory(category, navPanel, L.MENU_NAVIGATION, L.MENU_NAVIGATION)
    local changesCategory = Settings.RegisterCanvasLayoutSubcategory(category, changesPanel, L.MENU_CHANGES, L.MENU_CHANGES)
    openChangesPanel = function()
        category.expanded = true
        local id = changesCategory and (changesCategory.ID or (changesCategory.GetID and changesCategory:GetID()))
        if id and Settings.OpenToCategory then Settings.OpenToCategory(id) end
    end
    Settings.RegisterCanvasLayoutSubcategory(category, supportPanel, L.MENU_SUPPORT, L.MENU_SUPPORT)
    settingsCategory = category

    -- Al seleccionar "LizeUI" en la lista se despliegan sus subcategorias,
    -- igual que al pulsar la flecha, para que se vea que hay mas opciones.
    -- Al cerrar el menu de Ajustes, recordar recargar si se activo algun addon
    if SettingsPanel then
        SettingsPanel:HookScript("OnHide", function() C_Timer.After(0.1, showReloadReminder) end)
    end

    category.expanded = true
    basePanel:HookScript("OnShow", function()
        if category.expanded then return end
        if category.SetExpanded then
            pcall(category.SetExpanded, category, true)
        end
        category.expanded = true
        C_Timer.After(0, function()
            local list = SettingsPanel and SettingsPanel.GetCategoryList and SettingsPanel:GetCategoryList()
            if list and list.CreateCategories then
                pcall(list.CreateCategories, list)
            elseif Settings.OpenToCategory then
                pcall(Settings.OpenToCategory, category.ID or (category.GetID and category:GetID()))
            end
        end)
    end)
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

-- Al entrar: si la version instalada es mas nueva que la ultima vista, se
-- muestran sus cambios (salvo que el usuario lo haya desactivado).
-- La ultima version vista se guarda para toda la cuenta.
local function checkForUpdate()
    local current = getAddonVersion()
    local lastSeen = database.lastSeenVersion
    if lastSeen == nil then
        -- Sin registro: instalacion nueva (no hay nada que contar) o una version
        -- anterior a 2.0.0, que aun no guardaba la version (tenia windowOpened en la cuenta).
        if database.windowOpened then
            lastSeen = "1.5.0"
            database.windowOpened = nil
        else
            database.lastSeenVersion = current
            return
        end
    end
    if compareVersions(current, lastSeen) <= 0 then
        database.lastSeenVersion = current
        return
    end
    database.lastSeenVersion = current
    -- Aviso en el chat siempre; la ventana solo si no se ha desactivado
    printMessage(L.FMT_NEW_VERSION:format(current, lastSeen))
    if database.hideChangelogPopup then return end

    local function show() showWhatsNew(lastSeen) end
    if window:IsShown() then
        -- Primero la ventana de instalacion; al cerrarla, las novedades
        local pending = true
        window:HookScript("OnHide", function()
            if pending then pending = false; C_Timer.After(0.2, show) end
        end)
    else
        C_Timer.After(1, show)
    end
end

-- Abre el menu de Ajustes del juego con LizeUI seleccionado (y desplegado)
local function openSettings()
    if not settingsCategory or not Settings or not Settings.OpenToCategory then return end
    settingsCategory.expanded = true
    local id = settingsCategory.ID or (settingsCategory.GetID and settingsCategory:GetID())
    Settings.OpenToCategory(id)
end

-- ---------------------------------------------------------------------------
-- Boton del minimapa (LibDBIcon) y entrada del Compartimento de addons
-- ---------------------------------------------------------------------------
local function addLauncherTooltip(tooltip)
    tooltip:AddLine(ns.BrandText())
    tooltip:AddLine(L.MINIMAP_LEFT, 1, 1, 1)
    tooltip:AddLine(L.MINIMAP_RIGHT, 1, 1, 1)
end

local function onLauncherClick(button)
    if button == "RightButton" then
        showWindow()
    else
        openSettings()
    end
end

local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

local function initMinimapButton()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    if not LDB or not LDBIcon then return end
    database.minimap = database.minimap or { hide = false }
    local launcher = LDB:NewDataObject("LizeUI", {
        type = "launcher",
        text = "LizeUI Forever",
        icon = ns.LOGO_ROUND,
        OnClick = function(_, button) onLauncherClick(button) end,
        OnTooltipShow = function(tooltip)
            addLauncherTooltip(tooltip)
            tooltip:AddLine(L.MINIMAP_DRAG, 1, 1, 1)
        end,
    })
    LDBIcon:Register("LizeUI", launcher, database.minimap)
end

local function toggleMinimapButton()
    if not LDBIcon or not database.minimap then return end
    database.minimap.hide = not database.minimap.hide
    if database.minimap.hide then LDBIcon:Hide("LizeUI") else LDBIcon:Show("LizeUI") end
    printMessage(L.FMT_MINIMAP_TOGGLE:format(database.minimap.hide and L.DISABLED or L.ENABLED))
end

-- Funciones globales que llama el Compartimento de addons (definidas en el .toc)
function LizeUI_OnAddonCompartmentClick(_, button)
    onLauncherClick(button)
end

function LizeUI_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    addLauncherTooltip(GameTooltip)
    GameTooltip:Show()
end

function LizeUI_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

local function printHelp()
    printMessage(L.HELP_TITLE)
    for _, key in ipairs({ "HELP_LUI", "HELP_HELP", "HELP_INSTALL", "HELP_LOAD_EN", "HELP_LOAD_ES", "HELP_ROUTE", "HELP_MINIMAP" }) do
        DEFAULT_CHAT_FRAME:AddMessage("   " .. L[key])
    end
end

local function switchLanguage(language)
    if ns.GetLanguage() == language and database.language == language then
        printMessage(L.LANG_ALREADY)
        return
    end
    ns.SetLanguage(language)
    printMessage(language == "en" and L.LANG_SET_EN or L.LANG_SET_ES)
    ReloadUI()
end

SLASH_LIZEUI1 = "/lui"
SlashCmdList.LIZEUI = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "" then
        openSettings()
    elseif msg == "help" then
        printHelp()
    elseif msg == "install" then
        showWindow()
    elseif msg == "load_en" then
        switchLanguage("en")
    elseif msg == "load_es" then
        switchLanguage("es")
    elseif msg == "dev" then
        database.devMode = not database.devMode
        printMessage(L.FMT_DEV_MODE:format(database.devMode and L.ENABLED or L.DISABLED))
        updateDevModeVisibility()
    elseif msg == "minimapa" or msg == "minimap" then
        toggleMinimapButton()
    elseif msg == "ruta" then
        database.navRouteEnabled = not database.navRouteEnabled
        if NavRoute then NavRoute:Refresh() end
        printMessage(L.FMT_NAV_TOGGLE:format(database.navRouteEnabled and L.ENABLED or L.DISABLED))
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
        printMessage(L.UNKNOWN_COMMAND)
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
        initMinimapButton()
        updateDevModeVisibility()
        applyAllSettings()
        if NavRoute then NavRoute:Init(database) end
        if Utilities then Utilities:Init(database) end
        scheduleDetailsTitleBarRefresh()
        printMessage(L.LOGIN_HINT:format(ns.BrandText(), getAddonVersion()))
        -- Primera vez de ESTE personaje con LizeUI: abrir la ventana
        if not getCharDB().windowOpened then
            showWindow()
        end
        checkForUpdate()
    end
end)
