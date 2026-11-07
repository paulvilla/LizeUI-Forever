-- LizeUI - Utilidades (basado en funciones de Leatrix Plus)
--
--  * Tooltip mejorado: anclaje al cursor, escala, rangos de hermandad,
--    objetivo de la unidad, fondo por faccion, ocultar en combate, etc.
--  * Automatizacion: reparar, vender objetos pobres, invitar por susurro,
--    aceptar grupo de amigos y despojar rapido.
--
-- Todo se puede activar/desactivar sin recargar: los hooks se instalan una
-- sola vez y cada uno comprueba su ajuste en el momento de ejecutarse.

local _, ns = ...

local L = ns.L

local Utilities = CreateFrame("Frame")
ns.Utilities = Utilities

Utilities.defaults = {
    -- Tooltip
    tipEnabled = true,
    tipShowRank = true,
    tipShowOtherRank = false,
    tipShowTarget = true,
    tipBackFaction = false,
    tipHideInCombat = false,
    tipHideShiftOverride = true,
    tipNoHealthBar = false,
    tipAnchor = 1, -- 1 = por defecto, 2 = cursor, 3 = cursor izquierda, 4 = cursor derecha
    tipCursorX = 0,
    tipCursorY = 0,
    tipScale = 1.00,
    tipAuctionNet = true, -- linea "Neto" bajo el precio de Auctionator (resta el deposito)
    -- Chat mejorado
    chatHideGuildLogin = false,
    chatMuteGuildLogin = false, -- desactiva el sonido propio del juego al conectarse alguien de la hermandad
    chatGuildChatSound = false,
    chatGuildChatSoundName = "LizeUI Simple",
    chatWhisperSound = true,
    chatWhisperSoundName = "LizeUI Whisper",
    chatKeywordAlert = false,
    chatKeywords = "",
    chatKeywordSound = "LizeUI Success",
    -- Automatizacion
    autoRepair = false,
    autoRepairGuild = false,
    autoSellJunk = false,
    autoSellNoGreyGear = false,
    autoShowSummary = true,
    inviteFromWhisper = false,
    inviteFriendsOnly = false,
    inviteKeyword = "inv",
    acceptPartyFriends = false,
    friendlyGuild = true,
    fasterLoot = false,
    fasterLootDelay = 0.3,
}

local db

local function setting(key)
    local value = db and db[key]
    if value == nil then return Utilities.defaults[key] end
    return value
end

local function printMessage(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffLizeUI|r: " .. message)
end

-- En Forever algunos valores pueden ser "secretos" (no accesibles desde addons)
local function Safe(value)
    if canaccessvalue then
        if canaccessvalue(value) then return value end
        return nil
    end
    return value
end

local function coinText(amount)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinText then
        return C_CurrencyInfo.GetCoinText(amount)
    end
    return GetCoinTextureString and GetCoinTextureString(amount) or tostring(amount)
end

local function isInLFGQueue()
    if not GetLFGMode then return false end
    for _, category in ipairs({ LE_LFG_CATEGORY_LFD, LE_LFG_CATEGORY_LFR, LE_LFG_CATEGORY_RF,
        LE_LFG_CATEGORY_SCENARIO, LE_LFG_CATEGORY_FLEXRAID }) do
        if category and GetLFGMode(category) then return true end
    end
    return false
end

-- Devuelve true si el jugador es amigo (personaje o Battle.net) o, si esta
-- activado, miembro conectado de la hermandad.
local function isFriend(name, guid)
    name = Safe(name)
    if not name or name == "" then return false end
    guid = Safe(guid)
    name = strsplit("-", name, 2)

    if C_FriendList then
        for i = 1, C_FriendList.GetNumFriends() do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.name then
                local friendName = strsplit("-", info.name, 2)
                if friendName == name and (not guid or not info.guid or guid == info.guid) then
                    return true
                end
            end
        end
    end

    if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendNumGameAccounts then
        for i = 1, BNGetNumFriends() do
            for j = 1, C_BattleNet.GetFriendNumGameAccounts(i) do
                local account = C_BattleNet.GetFriendGameAccountInfo(i, j)
                if account and account.clientProgram == "WoW" and account.characterName == name then
                    return true
                end
            end
        end
    end

    if setting("friendlyGuild") and IsInGuild() then
        for i = 1, GetNumGuildMembers() do
            local gName, _, _, _, _, _, _, _, gOnline, _, _, _, _, gMobile, _, _, gGUID = GetGuildRosterInfo(i)
            if gName and gOnline and not gMobile then
                gName = strsplit("-", gName, 2)
                if gName == name and (not guid or not gGUID or guid == gGUID) then
                    return true
                end
            end
        end
    end

    return false
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

local function isWorldHover()
    if WorldFrame.IsMouseMotionFocus then
        return WorldFrame:IsMouseMotionFocus()
    end
    if GetMouseFocus then
        return GetMouseFocus() == WorldFrame
    end
    return false
end

local function classColor(class)
    if not class then return nil end
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    return colors and colors[class]
end

local function colorCode(col)
    return string.format("|cff%02x%02x%02x", col.r * 255, col.g * 255, col.b * 255)
end

local SCALED_TOOLTIPS = {
    "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "EmbeddedItemTooltip",
    "NamePlateTooltip", "FriendsTooltip", "AutoCompleteBox", "ReputationParagonTooltip",
    "LibDBIconTooltip", "QueueStatusFrame",
}

function Utilities:ApplyTooltipScale()
    local scale = setting("tipEnabled") and (tonumber(setting("tipScale")) or 1) or 1
    if scale < 0.5 then scale = 0.5 elseif scale > 2 then scale = 2 end
    for _, name in ipairs(SCALED_TOOLTIPS) do
        local frame = _G[name]
        if frame and frame.SetScale then frame:SetScale(scale) end
    end
end

function Utilities:ApplyHealthBar()
    local bar = _G.GameTooltipStatusBar
    if bar then
        bar:SetAlpha((setting("tipEnabled") and setting("tipNoHealthBar")) and 0 or 1)
    end
end

-- Cadenas por idioma (mismo criterio que Leatrix Plus)
local GameLocale = GetLocale()
local ttYou, ttLevel, ttBoss, ttElite, ttRare, ttRareElite, ttRareBoss, ttTarget
if GameLocale == "esES" or GameLocale == "esMX" then
    ttYou, ttLevel, ttBoss, ttElite, ttRare, ttRareElite, ttRareBoss, ttTarget = "TÚ", "Nivel", "Jefe", "Élite", "Raro", "Raro Élite", "Raro Jefe", "Objetivo"
elseif GameLocale == "deDE" then
    ttYou, ttLevel, ttBoss, ttElite, ttRare, ttRareElite, ttRareBoss, ttTarget = "SIE", "Stufe", "Boss", "Elite", "Selten", "Selten Elite", "Selten Boss", "Ziel"
elseif GameLocale == "frFR" then
    ttYou, ttLevel, ttBoss, ttElite, ttRare, ttRareElite, ttRareBoss, ttTarget = "TOI", "Niveau", "Boss", "Élite", "Rare", "Rare Élite", "Rare Boss", "Cible"
elseif GameLocale == "itIT" then
    ttYou, ttLevel, ttBoss, ttElite, ttRare, ttRareElite, ttRareBoss, ttTarget = "TU", "Livello", "Boss", "Élite", "Raro", "Raro Élite", "Raro Boss", "Bersaglio"
elseif GameLocale == "ptBR" then
    ttYou, ttLevel, ttBoss, ttElite, ttRare, ttRareElite, ttRareBoss, ttTarget = "VOCÊ", "Nível", "Chefe", "Elite", "Raro", "Raro Elite", "Raro Chefe", "Alvo"
elseif GameLocale == "ruRU" then
    ttYou, ttLevel, ttBoss, ttElite, ttRare, ttRareElite, ttRareBoss, ttTarget = "ВЫ", "Уровень", "босс", "элита", "Редкое", "Редкое элита", "Редкое босс", "Цель"
else
    ttYou, ttLevel, ttBoss, ttElite, ttRare, ttRareElite, ttRareBoss, ttTarget = "YOU", "Level", "Boss", "Elite", "Rare", "Rare Elite", "Rare Boss", "Target"
end

local LevelLocale = strtrim(string.gsub(TOOLTIP_UNIT_LEVEL or "Level %s", "%%s", ""))
local LevelPattern = string.lower((TOOLTIP_UNIT_LEVEL or "Level %s"):gsub("%%s", ".+"))
local LevelPattern2 = GameLocale == "ruRU" and "уровень" or nil
if GameLocale == "ruRU" then
    LevelLocale = "-ro уровня"
    LevelPattern = "уровня"
end

local function findLevelLine(first)
    for i = first, math.min(GameTooltip:NumLines(), first + 3) do
        local fs = _G["GameTooltipTextLeft" .. i]
        local text = fs and Safe(fs:GetText())
        if text then
            local lower = string.lower(text)
            if lower:find(LevelPattern) or (LevelPattern2 and lower:find(LevelPattern2)) then
                return i, text
            end
        end
    end
end

local function difficultyColor(unit, level)
    if GetDifficultyColor and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyCreatureForPlayer then
        local ok, col = pcall(function()
            return GetDifficultyColor(C_PlayerInfo.GetContentDifficultyCreatureForPlayer(unit))
        end)
        if ok and col then return col end
    end
    if GetQuestDifficultyColor and level then
        return GetQuestDifficultyColor(level)
    end
end

local function getLevelText(unit, level, realLevel, useColor)
    if level == -1 then
        if GameLocale == "ruRU" then
            return "|cffff3333??-ro " .. ttLevel .. "|r"
        end
        return "|cffff3333" .. ttLevel .. " ??|r"
    end
    local realText = ""
    if not useColor and realLevel and realLevel ~= level then
        realText = " (" .. realLevel .. ")"
    end
    local levelText
    if GameLocale == "ruRU" then
        levelText = level .. realText .. LevelLocale
    else
        levelText = LevelLocale .. " " .. level .. realText
    end
    if useColor then
        local col = difficultyColor(unit, level)
        if col then levelText = colorCode(col) .. levelText .. "|r" end
    end
    return levelText
end

local function onTooltipUnit(self)
    if self ~= GameTooltip or not setting("tipEnabled") then return end
    if IsControlKeyDown() and IsAltKeyDown() and IsShiftKeyDown() then return end

    local worldHover = isWorldHover()

    -- Ocultar tooltips de unidades del mundo en combate
    if worldHover and setting("tipHideInCombat") and UnitAffectingCombat("player") then
        if not IsShiftKeyDown() or not setting("tipHideShiftOverride") then
            GameTooltip:Hide()
            return
        end
    end

    local unit
    if worldHover then
        unit = "mouseover"
    else
        unit = Safe(select(2, GameTooltip:GetUnit()))
        if not unit then
            local owner = GameTooltip:GetOwner()
            unit = owner and not owner:IsForbidden() and Safe(owner.unit)
        end
    end
    if type(unit) ~= "string" or not UnitExists(unit) then return end
    if UnitIsWildBattlePet and UnitIsWildBattlePet(unit) then return end

    local name, realm = UnitName(unit)
    local isPlayer = UnitIsPlayer(unit)
    local playerControl = UnitPlayerControlled(unit)
    local reaction = UnitReaction(unit, "player") or 5
    local level = UnitEffectiveLevel and UnitEffectiveLevel(unit) or UnitLevel(unit)
    local realLevel = UnitLevel(unit)
    local isDead = UnitIsDeadOrGhost(unit)
    local className, class = UnitClass(unit)
    className, class = Safe(className), Safe(class)
    local classCol = classColor(class)

    -- Linea del nombre
    local r, g, b
    if isPlayer then
        local nameText = UnitPVPName(unit)
        if not nameText or (Safe(nameText) and nameText == "") then nameText = name end
        if nameText then GameTooltipTextLeft1:SetText(nameText) end
        if classCol then r, g, b = classCol.r, classCol.g, classCol.b end
    elseif playerControl or reaction > 4 then
        if Safe(UnitIsPVP(unit)) then
            r, g, b = 0, 1, 0
        else
            r, g, b = 0, 0.67, 1
        end
    elseif reaction < 4 then
        if UnitIsTapDenied(unit) then
            r, g, b = 0.53, 0.73, 0.73
        else
            r, g, b = 1, 0.2, 0.2
        end
    end
    if isDead then r, g, b = 0.53, 0.53, 0.53 end
    if r then GameTooltipTextLeft1:SetTextColor(r, g, b) end

    -- Hermandad e informacion del jugador
    if isPlayer then
        local guildName, guildRank = GetGuildInfo(unit)
        if guildName then
            local showRank
            if UnitIsInMyGuild(unit) then
                showRank = setting("tipShowRank")
            else
                showRank = setting("tipShowOtherRank")
            end
            if showRank and guildRank then
                GameTooltipTextLeft2:SetText(guildName .. " - " .. guildRank)
            else
                GameTooltipTextLeft2:SetText(guildName)
            end
            GameTooltipTextLeft2:SetTextColor(0.67, 0.67, 1)
        end

        local infoLine, infoOld
        if className and level then infoLine, infoOld = findLevelLine(guildName and 3 or 2) end
        if infoLine then
            local race = Safe(UnitRace(unit))
            local keepLine = race and not infoOld:find(race, 1, true)
            local infoText = getLevelText(unit, level, realLevel, reaction < 5)
            if race then
                if GameLocale == "ruRU" then
                    infoText = race .. ", " .. infoText
                else
                    infoText = infoText .. " " .. race
                end
            end
            local specLine = infoLine < GameTooltip:NumLines() and _G["GameTooltipTextLeft" .. (infoLine + 1)]
            local specText = specLine and Safe(specLine:GetText())
            if specText and specText:find(className, 1, true) then
                if classCol then specLine:SetTextColor(classCol.r, classCol.g, classCol.b) end
            elseif classCol then
                infoText = infoText .. " " .. colorCode(classCol) .. className .. "|r"
            else
                infoText = infoText .. " " .. className
            end
            if not keepLine then _G["GameTooltipTextLeft" .. infoLine]:SetText(infoText) end
        end
    end

    -- Nivel de criaturas coloreado por dificultad
    if not isPlayer and not playerControl and reaction < 5 and level and UnitCanAttack(unit, "player") then
        local mobLine, mobText = findLevelLine(2)
        if mobLine then
            local isBoss = mobText:find(ttBoss, 1, true)
            local special = UnitClassification(unit)
            if special == "elite" then
                special = isBoss and "(" .. ttBoss .. ")" or "(" .. ttElite .. ")"
            elseif special == "rare" then
                special = "|c00e066ff(" .. ttRare .. ")"
            elseif special == "rareelite" then
                special = isBoss and "|c00e066ff(" .. ttRareBoss .. ")" or "|c00e066ff(" .. ttRareElite .. ")"
            elseif special == "worldboss" or (special == "normal" and level == -1 and isBoss) then
                special = "(" .. ttBoss .. ")"
            else
                special = ""
            end
            _G["GameTooltipTextLeft" .. mobLine]:SetText(getLevelText(unit, level, nil, true) .. " " .. special)
        end
    end

    -- Fondo segun faccion
    if setting("tipBackFaction") and GameTooltip.NineSlice then
        local faction = UnitFactionGroup(unit)
        if faction and faction ~= UnitFactionGroup("player") and UnitCanAttack("player", unit) and not isDead then
            GameTooltip.NineSlice:SetCenterColor(0.5, 0.0, 0.0)
        else
            GameTooltip.NineSlice:SetCenterColor(0.0, 0.0, 0.5)
        end
    end

    -- Objetivo de la unidad
    if setting("tipShowTarget") then
        local targetUnit = unit .. "target"
        if UnitExists(targetUnit) then
            local target = UnitName(targetUnit)
            local canCompare = not C_Secrets or not C_Secrets.CanCompareUnitTokens
                or C_Secrets.CanCompareUnitTokens(targetUnit, "player")
            if canCompare and Safe(UnitIsUnit(targetUnit, "player")) then
                target = "|c12ff4400" .. ttYou
            elseif UnitIsPlayer(targetUnit) then
                local targetCol = classColor(Safe(UnitClassBase and UnitClassBase(targetUnit) or select(2, UnitClass(targetUnit))))
                if targetCol and target then target = colorCode(targetCol) .. target end
            end
            if target then
                GameTooltip:AddLine(" ")
                _G["GameTooltipTextLeft" .. GameTooltip:NumLines()]:SetText(ttTarget .. ": " .. target)
            end
        end
    end
end

local tooltipHooked = false
local function setupTooltip()
    if tooltipHooked then return end
    tooltipHooked = true

    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        if not setting("tipEnabled") then return end
        local anchor = tonumber(setting("tipAnchor")) or 1
        if anchor == 1 or not tooltip or not parent then return end
        if not isWorldHover() then return end
        local x, y = tonumber(setting("tipCursorX")) or 0, tonumber(setting("tipCursorY")) or 0
        if anchor == 2 then
            tooltip:SetOwner(parent, "ANCHOR_CURSOR")
        elseif anchor == 3 then
            tooltip:SetOwner(parent, "ANCHOR_CURSOR_LEFT", x, y)
        elseif anchor == 4 then
            tooltip:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", x, y)
        end
    end)

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, onTooltipUnit)
    else
        GameTooltip:HookScript("OnTooltipSetUnit", onTooltipUnit)
    end
end

function Utilities:RefreshTooltip()
    if setting("tipEnabled") then
        setupTooltip()
        -- Necesario para detectar el raton sobre el mundo (anclaje al cursor, ocultar en combate)
        if WorldFrame.EnableMouseMotion then WorldFrame:EnableMouseMotion(true) end
    end
    self:ApplyTooltipScale()
    self:ApplyHealthBar()
end

---------------------------------------------------------------------------
-- Reparar automaticamente
---------------------------------------------------------------------------

local function repairGear()
    if not setting("autoRepair") or IsShiftKeyDown() then return end
    if not CanMerchantRepair or not CanMerchantRepair() then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return end
    if setting("autoRepairGuild") and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair() then
        -- Intenta con fondos de hermandad y, si se agota el limite diario, con los propios
        RepairAllItems(true)
        RepairAllItems()
    else
        RepairAllItems()
    end
    if setting("autoShowSummary") then
        printMessage(L.FMT_REPAIRED:format(coinText(cost)))
    end
end

---------------------------------------------------------------------------
-- Vender objetos pobres
---------------------------------------------------------------------------

local sellTicker
local sellIterations = 0
local sellTotal = 0
local MAX_SELL_ITERATIONS = 500
local sellFrame = CreateFrame("Frame")

local function stopSelling(showSummary)
    if sellTicker then
        sellTicker:Cancel()
        sellTicker = nil
    end
    sellFrame:UnregisterEvent("UI_ERROR_MESSAGE")
    if showSummary and sellTotal > 0 and setting("autoShowSummary") then
        printMessage(L.FMT_JUNK_SOLD:format(coinText(sellTotal)))
    end
    sellTotal = 0
end

local function sellJunkStep()
    if not MerchantFrame or not MerchantFrame:IsShown() then
        stopSelling(true)
        return
    end
    sellIterations = sellIterations + 1
    local soldCount = 0
    local weapon = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
    local armor = Enum and Enum.ItemClass and Enum.ItemClass.Armor or 4
    local lastBag = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and not info.isLocked and info.hyperlink then
                local _, _, quality, _, _, _, _, _, _, _, price, classID = C_Item.GetItemInfo(info.hyperlink)
                quality = quality or info.quality
                local sell = quality == 0 and price and price > 0 and not info.hasNoValue
                if sell and setting("autoSellNoGreyGear") and (classID == weapon or classID == armor) then
                    local bound = C_Item.IsBound and ItemLocation and C_Item.IsBound(ItemLocation:CreateFromBagAndSlot(bag, slot))
                    if not bound then sell = false end
                end
                if sell then
                    soldCount = soldCount + 1
                    sellTotal = sellTotal + price * (info.stackCount or 1)
                    C_Container.UseContainerItem(bag, slot)
                end
            end
        end
    end
    if soldCount == 0 or sellIterations >= MAX_SELL_ITERATIONS then
        stopSelling(true)
    end
end

local function startSelling()
    if not setting("autoSellJunk") or IsShiftKeyDown() then return end
    stopSelling(false)
    sellIterations = 0
    sellTotal = 0
    sellFrame:RegisterEvent("UI_ERROR_MESSAGE")
    sellTicker = C_Timer.NewTicker(0.2, sellJunkStep)
end

sellFrame:SetScript("OnEvent", function(_, event, _, message)
    if event == "UI_ERROR_MESSAGE" then
        if message and (message == ERR_VENDOR_DOESNT_BUY or message == ERR_TOO_MUCH_GOLD) then
            stopSelling(true)
        end
    end
end)

---------------------------------------------------------------------------
-- Invitar por susurro
---------------------------------------------------------------------------

local function onWhisper(event, text, sender, ...)
    if not setting("inviteFromWhisper") then return end
    text, sender = Safe(text), Safe(sender)
    if not text or not sender then return end
    local keyword = strlower(strtrim(tostring(setting("inviteKeyword") or "inv")))
    if keyword == "" then keyword = "inv" end
    if strlower(strtrim(text)) ~= keyword then return end
    if UnitExists("party1") and not UnitIsGroupLeader("player") and not UnitIsGroupAssistant("player") then return end
    if isInLFGQueue() then return end

    if event == "CHAT_MSG_WHISPER" then
        local guid = select(10, ...)
        if setting("inviteFriendsOnly") and not isFriend(sender, guid) then return end
        local whisperName, whisperRealm = strsplit("-", sender, 2)
        if whisperRealm then
            local _, myRealm = UnitFullName("player")
            if myRealm and whisperRealm == myRealm then sender = whisperName end
        end
        if C_PartyInfo and C_PartyInfo.InviteUnit then
            C_PartyInfo.InviteUnit(sender)
        elseif InviteUnit then
            InviteUnit(sender)
        end
    elseif event == "CHAT_MSG_BN_WHISPER" then
        local presenceID = Safe(select(11, ...))
        if presenceID and BNIsFriend and BNIsFriend(presenceID) and C_BattleNet then
            local index = BNGetFriendIndex(presenceID)
            local accountInfo = index and C_BattleNet.GetFriendAccountInfo(index)
            local gameAccountID = accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.gameAccountID
            if gameAccountID then C_BattleNet.InviteFriend(gameAccountID) end
        end
    end
end

---------------------------------------------------------------------------
-- Aceptar grupo de amigos
---------------------------------------------------------------------------

local function acceptInvite(sender, ...)
    if not setting("acceptPartyFriends") then return end
    -- Argumentos: nombre, isTank, isHealer, isDamage, isNativeRealm, allowMultipleRoles, inviterGUID
    local guid = select(6, ...)
    if not isFriend(sender, guid) or isInLFGQueue() then return end
    AcceptGroup()
    -- Marcar el dialogo como aceptado: al ocultarlo, Blizzard rechaza la invitacion si no lo esta
    for _, which in ipairs({ "PARTY_INVITE", "PARTY_INVITE_XREALM" }) do
        local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible(which)
        if dialog then
            dialog.inviteAccepted = 1
            StaticPopup_Hide(which)
        end
    end
    local qsm = _G.QuestSessionManager
    local confirm = qsm and qsm.ConfirmInviteToGroupReceivedDialog
        and qsm.ConfirmInviteToGroupReceivedDialog.ButtonContainer
        and qsm.ConfirmInviteToGroupReceivedDialog.ButtonContainer.Confirm
    if confirm and confirm:IsShown() then confirm:Click() end
end

---------------------------------------------------------------------------
-- Despojar rapido
---------------------------------------------------------------------------

local lastLoot = 0
local function fastLoot()
    if not setting("fasterLoot") then return end
    local delay = tonumber(setting("fasterLootDelay")) or 0.3
    if GetTime() - lastLoot < delay then return end
    lastLoot = GetTime()
    if GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") then
        for i = GetNumLootItems(), 1, -1 do
            LootSlot(i)
        end
        lastLoot = GetTime()
    end
end

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------

local function setEvent(event, enabled)
    if enabled then
        Utilities:RegisterEvent(event)
    else
        Utilities:UnregisterEvent(event)
    end
end

function Utilities:RefreshAutomation()
    setEvent("MERCHANT_SHOW", setting("autoRepair") or setting("autoSellJunk"))
    setEvent("MERCHANT_CLOSED", setting("autoSellJunk"))
    setEvent("CHAT_MSG_WHISPER", setting("inviteFromWhisper"))
    setEvent("CHAT_MSG_BN_WHISPER", setting("inviteFromWhisper"))
    setEvent("PARTY_INVITE_REQUEST", setting("acceptPartyFriends"))
    setEvent("LOOT_READY", setting("fasterLoot"))
    if not setting("autoSellJunk") then stopSelling(false) end
end

Utilities:SetScript("OnEvent", function(_, event, ...)
    if event == "MERCHANT_SHOW" then
        repairGear()
        startSelling()
    elseif event == "MERCHANT_CLOSED" then
        stopSelling(true)
    elseif event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then
        onWhisper(event, ...)
    elseif event == "PARTY_INVITE_REQUEST" then
        acceptInvite(...)
    elseif event == "LOOT_READY" then
        fastLoot()
    end
end)

-- ---------------------------------------------------------------------------
-- Precio neto de subasta (Auctionator)
-- Anade una linea pequena justo debajo de "Subasta" con lo que realmente se
-- gana: precio de subasta * unidades del stack - deposito (1 de plata).
-- Para objetos no apilables el stack es siempre 1.
-- ---------------------------------------------------------------------------
local AUCTION_DEPOSIT = 100 -- 1 de plata, en cobre
local auctionHooked = false
local auctionContext -- { link, count } del objeto que Auctionator esta pintando

local function auctionMoneyString(amount)
    if Auctionator and Auctionator.Utilities and Auctionator.Utilities.CreatePaddedMoneyString then
        return Auctionator.Utilities.CreatePaddedMoneyString(amount)
    end
    return coinText(amount)
end

local function itemMaxStack(link)
    if C_Item and C_Item.GetItemMaxStackSizeByID then
        local itemID = C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(link)
        local size = itemID and C_Item.GetItemMaxStackSizeByID(itemID)
        if size then return size end
    end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    return getInfo and select(8, getInfo(link)) or 1
end

-- Las lineas del tooltip se reutilizan: devolver la fuente normal al limpiar
local function resetSmallLines(tooltip)
    local lines = tooltip.lizeSmallLines
    if not lines then return end
    local name = tooltip:GetName()
    for index in pairs(lines) do
        local left, right = _G[name .. "TextLeft" .. index], _G[name .. "TextRight" .. index]
        if left then left:SetFontObject(GameTooltipText) end
        if right then right:SetFontObject(GameTooltipText) end
    end
    tooltip.lizeSmallLines = nil
end

local function addAuctionNetLine(tooltip, auctionPrice, _, cannotAuction)
    local context = auctionContext
    if not setting("tipAuctionNet") or not context or cannotAuction or auctionPrice == nil then return end
    if not (tooltip and tooltip.AddDoubleLine) then return end

    local unitPrice = Auctionator.Database and Auctionator.Database:GetFirstPrice(context.dbKeys)
    if not unitPrice then return end

    local count = 1
    if (tonumber(itemMaxStack(context.link)) or 1) > 1 then
        count = math.max(1, tonumber(context.count) or 1)
    end

    local net = math.floor(unitPrice * count) - AUCTION_DEPOSIT
    local label = "  " .. L.AUCTION_NET
    if count > 1 then label = label .. " |cff7fbfffx" .. count .. "|r" end
    if net > 0 then
        tooltip:AddDoubleLine(label, auctionMoneyString(net), 0.6, 0.6, 0.6, 0.5, 1, 0.5)
    else
        -- Dinero perdido (en rojo, con signo menos)
        local lost = auctionMoneyString(-net)
        if net < 0 then lost = "-" .. lost end
        tooltip:AddDoubleLine(label, lost, 0.6, 0.6, 0.6, 1, 0.35, 0.35)
    end

    -- Letra pequena para no ensanchar el tooltip
    local name = tooltip.GetName and tooltip:GetName()
    local index = tooltip:NumLines()
    local left = name and _G[name .. "TextLeft" .. index]
    local right = name and _G[name .. "TextRight" .. index]
    if left and right and GameTooltipTextSmall then
        left:SetFontObject(GameTooltipTextSmall)
        right:SetFontObject(GameTooltipTextSmall)
        tooltip.lizeSmallLines = tooltip.lizeSmallLines or {}
        tooltip.lizeSmallLines[index] = true
        if not tooltip.lizeSmallResetHooked and tooltip.HookScript then
            tooltip.lizeSmallResetHooked = true
            tooltip:HookScript("OnTooltipCleared", resetSmallLines)
        end
    end
end

function Utilities:IsAuctionatorAvailable()
    return type(Auctionator) == "table" and type(Auctionator.Tooltip) == "table"
        and type(Auctionator.Tooltip.AddAuctionTip) == "function"
        and type(Auctionator.Tooltip.ShowTipWithPricingDBKey) == "function"
end

function Utilities:HookAuctionator()
    if auctionHooked or not self:IsAuctionatorAvailable() then return end
    auctionHooked = true

    -- Guardar el objeto/cantidad que se esta pintando (Auctionator llama a esta
    -- funcion a traves de la tabla, asi que el envoltorio se usa siempre).
    local original = Auctionator.Tooltip.ShowTipWithPricingDBKey
    Auctionator.Tooltip.ShowTipWithPricingDBKey = function(tooltipFrame, dbKeys, itemLink, itemCount, ...)
        auctionContext = { dbKeys = dbKeys, link = itemLink, count = itemCount }
        local ok, err = pcall(original, tooltipFrame, dbKeys, itemLink, itemCount, ...)
        auctionContext = nil
        if not ok then error(err, 0) end
    end

    hooksecurefunc(Auctionator.Tooltip, "AddAuctionTip", addAuctionNetLine)
end

-- ---------------------------------------------------------------------------
-- Chat mejorado
--  * Ocultar los avisos de conexion/desconexion de la hermandad
--  * Desactivar el aviso (sonido del juego) al conectarse alguien de la hermandad
--  * Sonido cuando alguien escribe en el chat de hermandad
--  * Aviso sonoro cuando aparecen en el chat ciertas palabras
-- Los sonidos se eligen de LibSharedMedia (LizeUI registra los suyos en
-- media/sharedmedia.lua; tambien salen los de otros addons).
-- ---------------------------------------------------------------------------
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- Reproduce un sonido de SharedMedia; si el guardado ya no existe (por
-- ejemplo, un sonido eliminado), usa el sonido por defecto de esa opcion.
function Utilities:PlaySoundByName(name, fallback)
    if not LSM or name == "None" then return end
    local file = name and LSM:Fetch("sound", name, true)
    if not file and fallback then file = LSM:Fetch("sound", fallback, true) end
    if file then PlaySoundFile(file, "Master") end
end

-- "Desactivar aviso de hermandad": apaga la opcion del juego "Aviso de miembros
-- de la hermandad" (CVar guildMemberNotify), que es la que avisa y hace sonar la
-- conexion de los miembros de la hermandad. Al desmarcar se vuelve a encender
-- solo si la apago LizeUI. Ademas se silencia el archivo de sonido de conexion.
local GUILD_LOGIN_GAME_SOUNDS = {
    "Sound\\Interface\\FriendJoin.ogg",
}
local guildLoginMuted = false

local function getCVarValue(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    return GetCVar and GetCVar(name)
end
local function setCVarValue(name, value)
    if C_CVar and C_CVar.SetCVar then return pcall(C_CVar.SetCVar, name, value) end
    if SetCVar then return pcall(SetCVar, name, value) end
end

local function applyGuildLoginGameSound()
    local mute = setting("chatMuteGuildLogin") and true or false

    -- Opcion del juego: aviso de conexion de la hermandad
    local current = getCVarValue("guildMemberNotify")
    if current ~= nil and db then
        if mute and current ~= "0" then
            setCVarValue("guildMemberNotify", "0")
            db.guildMemberNotifyChangedByLizeUI = true
        elseif not mute and db.guildMemberNotifyChangedByLizeUI then
            setCVarValue("guildMemberNotify", "1")
            db.guildMemberNotifyChangedByLizeUI = nil
        end
    end

    -- Archivo de sonido de conexion
    if mute == guildLoginMuted or not MuteSoundFile then return end
    for _, sound in ipairs(GUILD_LOGIN_GAME_SOUNDS) do
        if mute then pcall(MuteSoundFile, sound) else pcall(UnmuteSoundFile, sound) end
    end
    guildLoginMuted = mute
end

-- Patrones a partir de los textos del cliente (sirven en cualquier idioma)
local function toPattern(globalString)
    if type(globalString) ~= "string" then return nil end
    local pattern = globalString:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    pattern = pattern:gsub("%%s", "(.-)"):gsub("%%d", "%%d+")
    return "^" .. pattern .. "$"
end
local ONLINE_PATTERN = toPattern(ERR_FRIEND_ONLINE_SS)   -- "|Hplayer:%s|h[%s]|h se ha conectado."
local OFFLINE_PATTERN = toPattern(ERR_FRIEND_OFFLINE_S)  -- "%s se ha desconectado."

local guildMembers = {}

local function shortName(name)
    if not name then return nil end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return (strsplit("-", name))
end

local function rebuildGuildRoster()
    wipe(guildMembers)
    if not IsInGuild() or not GetNumGuildMembers then return end
    local total = GetNumGuildMembers() or 0
    for i = 1, total do
        local name = GetGuildRosterInfo(i)
        name = shortName(name)
        if name then guildMembers[name] = true end
    end
end

local function isCharacterFriend(name)
    if C_FriendList and C_FriendList.IsFriend then
        local ok, result = pcall(C_FriendList.IsFriend, name)
        return ok and result
    end
    return false
end

-- Devuelve "online"/"offline" y el nombre si el mensaje es de un miembro de la
-- hermandad (los amigos de personaje se tratan como amigos, no se tocan)
local function parseGuildLogin(message)
    message = Safe(message)
    if type(message) ~= "string" then return nil end
    local state, name
    if ONLINE_PATTERN then
        local link, display = message:match(ONLINE_PATTERN)
        if link then state, name = "online", display or link end
    end
    if not state and OFFLINE_PATTERN then
        local who = message:match(OFFLINE_PATTERN)
        if who then state, name = "offline", who end
    end
    if not state then return nil end
    name = shortName(name)
    if not name or isCharacterFriend(name) then return nil end
    -- Estos avisos solo los generan amigos de personaje y miembros de la hermandad:
    -- si no es amigo y estamos en hermandad, es de la hermandad (asi funciona
    -- aunque la lista de la hermandad aun no se haya cargado tras un /reload)
    if not guildMembers[name] and not IsInGuild() then return nil end
    return state, name
end

local function guildLoginFilter(_, _, message, ...)
    if setting("chatHideGuildLogin") and parseGuildLogin(message) then
        return true
    end
    return false, message, ...
end

local KEYWORD_EVENTS = {
    "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
}

local keywordCacheSource, keywordCache = nil, {}
local function getKeywords()
    local source = tostring(setting("chatKeywords") or "")
    if source ~= keywordCacheSource then
        keywordCacheSource = source
        wipe(keywordCache)
        for word in source:gmatch("[^,]+") do
            word = strlower(strtrim(word))
            if word ~= "" then keywordCache[#keywordCache + 1] = word end
        end
    end
    return keywordCache
end

local lastKeywordSound, lastGuildChatSound, lastWhisperSound = 0, 0, 0
local chatFrame = CreateFrame("Frame")

chatFrame:SetScript("OnEvent", function(_, event, message, sender)
    if event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
        rebuildGuildRoster()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- Volver a aplicar el silencio del sonido de conexion tras cada carga
        Utilities:ReapplyGuildLoginMute()
        return
    end
    message, sender = Safe(message), Safe(sender)
    if type(message) ~= "string" then return end
    if type(sender) == "string" and shortName(sender) == UnitName("player") then return end

    -- Palabras clave (tienen prioridad: si suena su aviso no suena el de hermandad)
    if setting("chatKeywordAlert") then
        local words = getKeywords()
        local text = strlower(message)
        for _, word in ipairs(words) do
            if text:find(word, 1, true) then
                if GetTime() - lastKeywordSound > 2 then
                    lastKeywordSound = GetTime()
                    Utilities:PlaySoundByName(setting("chatKeywordSound"), Utilities.defaults.chatKeywordSound)
                end
                return
            end
        end
    end

    -- Susurros
    if (event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER") and setting("chatWhisperSound") then
        if GetTime() - lastWhisperSound > 1 then
            lastWhisperSound = GetTime()
            Utilities:PlaySoundByName(setting("chatWhisperSoundName"), Utilities.defaults.chatWhisperSoundName)
        end
        return
    end

    -- Mensajes en el chat de hermandad
    if event == "CHAT_MSG_GUILD" and setting("chatGuildChatSound") and GetTime() - lastGuildChatSound > 1 then
        lastGuildChatSound = GetTime()
        Utilities:PlaySoundByName(setting("chatGuildChatSoundName"), Utilities.defaults.chatGuildChatSoundName)
    end
end)

function Utilities:ReapplyGuildLoginMute()
    guildLoginMuted = false
    if setting("chatMuteGuildLogin") then applyGuildLoginGameSound() end
end
chatFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

local filterInstalled = false
function Utilities:RefreshChat()
    applyGuildLoginGameSound()
    -- La lista de la hermandad solo hace falta para ocultar sus conexiones
    if setting("chatHideGuildLogin") then
        chatFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
        chatFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
        rebuildGuildRoster()
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
    else
        chatFrame:UnregisterEvent("GUILD_ROSTER_UPDATE")
        chatFrame:UnregisterEvent("PLAYER_GUILD_UPDATE")
    end
    -- El filtro se instala una vez y comprueba el ajuste en cada mensaje
    if setting("chatHideGuildLogin") and not filterInstalled then
        local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
        if addFilter then
            addFilter("CHAT_MSG_SYSTEM", guildLoginFilter)
            filterInstalled = true
        end
    end
    for _, event in ipairs(KEYWORD_EVENTS) do
        local wanted = setting("chatKeywordAlert")
            or (event == "CHAT_MSG_GUILD" and setting("chatGuildChatSound"))
            or ((event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER") and setting("chatWhisperSound"))
        if wanted then chatFrame:RegisterEvent(event) else chatFrame:UnregisterEvent(event) end
    end
end

function Utilities:Refresh()
    self:RefreshTooltip()
    self:RefreshAutomation()
    self:RefreshChat()
end

-- Opciones equivalentes de Leatrix Plus: si estan activas a la vez, la accion
-- se hace dos veces (dos invitaciones, dos resumenes, etc.).
local LEATRIX_KEYS = {
    { key = "TipModEnable", label = "Enhance tooltip" },
    { key = "AutoRepairGear", label = "Repair automatically" },
    { key = "AutoSellJunk", label = "Sell junk automatically" },
    { key = "InviteFromWhisper", label = "Invite from whispers" },
    { key = "AcceptPartyFriends", label = "Party from friends" },
    { key = "FasterLooting", label = "Faster auto loot" },
}

function Utilities:GetLeatrixConflicts()
    local list = {}
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if not (isLoaded and isLoaded("Leatrix_Plus")) or type(LeaPlusDB) ~= "table" then return list end
    for _, entry in ipairs(LEATRIX_KEYS) do
        if LeaPlusDB[entry.key] == "On" then list[#list + 1] = entry.label end
    end
    return list
end

function Utilities:Init(database)
    db = database
    self:Refresh()
    self:HookAuctionator()
    if not auctionHooked then
        -- Por si Auctionator carga despues que LizeUI
        local watcher = CreateFrame("Frame")
        watcher:RegisterEvent("ADDON_LOADED")
        watcher:SetScript("OnEvent", function(frame, _, name)
            if name == "Auctionator" then
                Utilities:HookAuctionator()
                frame:UnregisterAllEvents()
            end
        end)
    end
end
