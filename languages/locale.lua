-- LizeUI - Selector de idioma
--
-- ns.L.CLAVE devuelve el texto en el idioma activo:
--   1. el elegido con /lui load_en o /lui load_es (LizeUIDB.language)
--   2. si no hay ninguno, el idioma del cliente (es* = espanol, resto = ingles)
-- Si una clave no existe en el idioma activo se usa la del otro idioma y, en
-- ultimo caso, el nombre de la clave (asi se ve enseguida que falta).
--
-- El idioma se lee en cada consulta, pero los textos de la interfaz se fijan al
-- crearla: para cambiar de idioma hay que recargar la interfaz (/reload).

local _, ns = ...
ns.Locales = ns.Locales or {}

local SUPPORTED = { es = true, en = true }

function ns.GetLanguage()
    local db = LizeUIDB
    if type(db) == "table" and SUPPORTED[db.language] then
        return db.language
    end
    local clientLocale = GetLocale and GetLocale() or "enUS"
    return clientLocale:sub(1, 2) == "es" and "es" or "en"
end

function ns.SetLanguage(language)
    if not SUPPORTED[language] then return false end
    if type(LizeUIDB) ~= "table" then LizeUIDB = {} end
    LizeUIDB.language = language
    return true
end

ns.L = setmetatable({}, {
    __index = function(_, key)
        local language = ns.GetLanguage()
        local primary = ns.Locales[language]
        local value = primary and primary[key]
        if value == nil then
            local fallback = ns.Locales[language == "es" and "en" or "es"]
            value = fallback and fallback[key]
        end
        return value or key
    end,
    __newindex = function() end,
})

-- ---------------------------------------------------------------------------
-- Marca: nombre visible del addon con el degradado de LizeUI (azul -> morado)
-- ---------------------------------------------------------------------------
ns.BRAND_NAME = "LizeUI Forever"
ns.BRAND_COLORS = { 0, 192, 250, 130, 85, 255 }
ns.ACCENT_HEX = "00c0fa" -- color inicial del degradado, para resaltar textos
-- Logos disponibles:
--   LOGO_ROUND  -> recorte redondo sin borde (huecos redondos: retrato de las ventanas, chat)
--   LOGO_FULL   -> imagen original sin tocar (panel de Soporte)
--   LOGO_BORDER -> recorte con el aro dorado (lista de addons y menu de Opciones)
ns.LOGO_ROUND = [[Interface\AddOns\LizeUI\media\textures\icons\lizeui_portrait.tga]]
ns.LOGO_FULL = [[Interface\AddOns\LizeUI\media\textures\icons\lizeui_logo.tga]]
ns.LOGO_BORDER = [[Interface\AddOns\LizeUI\media\textures\icons\lizeui_addonlist.tga]]
ns.LOGO_ICON = ns.LOGO_ROUND

-- Texto con degradado de color letra a letra
function ns.GradientText(text, r1, g1, b1, r2, g2, b2)
    if not r1 then r1, g1, b1, r2, g2, b2 = unpack(ns.BRAND_COLORS) end
    local len = #text
    if len <= 1 then
        return ("|cff%02x%02x%02x%s|r"):format(r1, g1, b1, text)
    end
    local out = {}
    for i = 1, len do
        local ch = text:sub(i, i)
        if ch == " " then
            out[#out + 1] = ch
        else
            local t = (i - 1) / (len - 1)
            out[#out + 1] = ("|cff%02x%02x%02x%s|r"):format(
                math.floor(r1 + (r2 - r1) * t + 0.5),
                math.floor(g1 + (g2 - g1) * t + 0.5),
                math.floor(b1 + (b2 - b1) * t + 0.5), ch)
        end
    end
    return table.concat(out)
end

-- "Lize" con el color normal del texto y "UI Forever" con el degradado.
-- withIcon: añade el logo; iconRight: lo pone a la derecha; icon: textura (por defecto LOGO_ICON)
function ns.BrandText(withIcon, iconSize, iconRight, icon)
    local text = "Lize" .. ns.GradientText("UI Forever")
    if withIcon then
        local size = iconSize or 14
        local tex = ("|T%s:%d:%d:0:0|t"):format(icon or ns.LOGO_ICON, size, size)
        text = iconRight and (text .. " " .. tex) or (tex .. " " .. text)
    end
    return text
end
