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
