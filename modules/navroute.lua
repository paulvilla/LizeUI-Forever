-- LizeUI - Ruta de navegacion para RXPGuides
--
-- Dibuja en el minimapa y en el mapa del mundo la ruta que marca RXPGuides
-- (jugador -> objetivo actual -> waypoints restantes del paso -> pasos
-- siguientes), en gris, con flechas de direccion opcionales.
--
-- Basado en la idea de RXP_Navigator pero reescrito para evitar sus fallos:
--  * NO modifica ajustes de RXPGuides (RXP_Navigator forzaba disableArrow y
--    reemplazaba RXPG_ARROW:Show para ocultar la flecha original).
--  * Usa HereBeDragons (la misma libreria que usa RXPGuides para sus pines),
--    asi que las lineas coinciden exactamente con los pines de RXP y la
--    distancia/direccion se calcula en yardas reales (RXP_Navigator usaba
--    coordenadas de mapa normalizadas, que deforman el angulo en zonas no
--    cuadradas, y escalaba mal la distancia en el minimapa).
--  * No llama a SetMapToCurrentZone ni recorre la jerarquia de mapas en cada
--    frame (RXP_Navigator lo hacia 20 veces por segundo).
--  * Reutiliza tablas y lineas: sin basura por frame. El OnUpdate se apaga
--    cuando la funcion esta desactivada.

local _, ns = ...

local NavRoute = CreateFrame("Frame")
ns.NavRoute = NavRoute

NavRoute.defaults = {
    navRouteEnabled = true,
    navRouteMinimap = true,
    navRouteWorldMap = true,
    navRouteArrows = true,
    navRouteFutureSteps = 2,
    navRouteThickness = 3,
    navRouteAlpha = 0.85,
    navRouteGray = 0.70,
}

local math_sqrt, math_ceil, math_min, math_max = math.sqrt, math.ceil, math.min, math.max
local math_sin, math_cos = math.sin, math.cos

local MAX_NODES = 80
local MAX_LINES = 400
local MAX_CHEVRONS = 60
local REBUILD_INTERVAL = 0.25
local MINIMAP_INTERVAL = 0.03
local WORLDMAP_INTERVAL = 0.04
local SMOOTH_STRENGTH = 0.20
local FUTURE_ALPHA_FACTOR = 0.55
local MINIMAP_CLIP = 0.92

-- Diametro visible del minimapa en yardas segun zoom (mismos valores que
-- HereBeDragons-Pins), solo como respaldo si no existe C_Minimap.GetViewRadius.
local MINIMAP_SIZE = {
    indoor = { [0] = 300, [1] = 240, [2] = 180, [3] = 120, [4] = 80, [5] = 50 },
    outdoor = { [0] = 466 + 2 / 3, [1] = 400, [2] = 333 + 1 / 3, [3] = 266 + 2 / 6, [4] = 200, [5] = 133 + 1 / 3 },
}

local db
local HBD

-- Nodos de la ruta (coordenadas de mundo HBD, en yardas)
local nodeX, nodeY, nodeFuture = {}, {}, {}
local nodeCount = 0
-- Ruta suavizada
local pathX, pathY, pathFuture = {}, {}, {}
local pathCount = 0
local pathInstance

local minimapLayer, worldLayer
local rebuildElapsed, minimapElapsed, worldElapsed = 0, 0, 0
local running = false

---------------------------------------------------------------------------
-- Ajustes
---------------------------------------------------------------------------

local function setting(key)
    local value = db and db[key]
    if value == nil then return NavRoute.defaults[key] end
    return value
end

local function numberSetting(key, minVal, maxVal)
    local value = tonumber(setting(key)) or NavRoute.defaults[key]
    if value < minVal then value = minVal elseif value > maxVal then value = maxVal end
    return value
end

---------------------------------------------------------------------------
-- Acceso a RXPGuides (solo lectura)
---------------------------------------------------------------------------

local function getRXP()
    if not LibStub then return nil end
    local ace = LibStub("AceAddon-3.0", true)
    if not ace then return nil end
    local ok, rxp = pcall(ace.GetAddon, ace, "RXPGuides", true)
    if ok and type(rxp) == "table" then return rxp end
    return nil
end

-- El boton toggle de RestedXP (icono del minimapa / "/rxp toggle") desactiva
-- profile.showEnabled y oculta todos sus marcos: la ruta tambien se oculta.
local function isRXPActive()
    local rxp = getRXP()
    local settings = rxp and rxp.settings
    local profile = type(settings) == "table" and settings.profile
    if type(profile) == "table" and profile.showEnabled == false then return false end
    return true
end

local function hasWorldPosition(element)
    return type(element) == "table"
        and type(element.wx) == "number"
        and type(element.wy) == "number"
        and element.instance ~= nil
end

-- RXPGuides rellena RXPG_ARROW.element aunque su flecha este desactivada, asi
-- que no hace falta tocar sus ajustes. Pero el campo puede quedar obsoleto al
-- terminar un paso, por eso se valida.
local function getCurrentElement()
    local arrow = _G.RXPG_ARROW
    local element = arrow and arrow.element
    if not hasWorldPosition(element) or element.skip or element.hidden then return nil end
    local step = element.step
    if type(step) == "table" then
        if not step.active or step.completed then return nil end
    elseif not (UnitIsGhost and UnitIsGhost("player")) then
        -- Waypoints generados sin paso (cadaver / curandero espiritual)
        return nil
    end
    return element
end

local function isRoutePoint(element)
    return hasWorldPosition(element)
        and element.arrow
        and not element.skip
        and not element.completed
        and not element.hidden
        and not element.generated
end

local function addNode(x, y, future)
    if nodeCount > 0 then
        local dx, dy = x - nodeX[nodeCount], y - nodeY[nodeCount]
        if dx * dx + dy * dy < 1 then return end
    end
    nodeCount = nodeCount + 1
    nodeX[nodeCount], nodeY[nodeCount], nodeFuture[nodeCount] = x, y, future
end

-- Devuelve la instancia (continente) de la ruta o nil si no hay ruta.
local function collectNodes(futureSteps)
    nodeCount = 0
    if not isRXPActive() then return nil end
    local current = getCurrentElement()
    if not current then return nil end

    local instance = current.instance
    addNode(current.wx, current.wy, false)

    local step = current.step
    if type(step) ~= "table" then return instance end

    -- Waypoints restantes del paso actual, en orden. Los pasos #loop son
    -- zonas de farmeo, no un recorrido lineal: solo se sigue el punto actual.
    if not step.loop and type(step.elements) == "table" then
        local found = false
        for _, element in ipairs(step.elements) do
            if element == current then
                found = true
            elseif found and isRoutePoint(element) and not element.lowPrio then
                if element.instance ~= instance then return instance end
                addNode(element.wx, element.wy, false)
                if nodeCount >= MAX_NODES then return instance end
            end
        end
    end

    -- Pasos siguientes de la guia
    if futureSteps <= 0 then return instance end
    local rxp = getRXP()
    local guide = rxp and rxp.currentGuide
    local steps = type(guide) == "table" and guide.steps
    local index = tonumber(step.index)
    if type(steps) ~= "table" or not index then return instance end

    local added = 0
    for i = index + 1, #steps do
        local futureStep = steps[i]
        if type(futureStep) == "table" and not futureStep.completed and not futureStep.skip
            and not futureStep.loop and type(futureStep.elements) == "table" then
            local hasPoints = false
            for _, element in ipairs(futureStep.elements) do
                if isRoutePoint(element) and not element.dynamic then
                    if element.instance ~= instance then return instance end
                    addNode(element.wx, element.wy, true)
                    hasPoints = true
                    if nodeCount >= MAX_NODES then return instance end
                end
            end
            if hasPoints then
                added = added + 1
                if added >= futureSteps then break end
            end
        end
    end
    return instance
end

---------------------------------------------------------------------------
-- Suavizado (curvas Bezier que pasan por todos los waypoints)
---------------------------------------------------------------------------

local function pushPath(x, y, future)
    pathCount = pathCount + 1
    pathX[pathCount], pathY[pathCount], pathFuture[pathCount] = x, y, future
end

local function unit(dx, dy, fx, fy)
    local len = math_sqrt(dx * dx + dy * dy)
    if len < 0.001 then return fx, fy end
    return dx / len, dy / len
end

local function buildSmoothPath()
    pathCount = 0
    if nodeCount == 0 then return end
    pushPath(nodeX[1], nodeY[1], nodeFuture[1])
    for i = 1, nodeCount - 1 do
        local x1, y1, x2, y2 = nodeX[i], nodeY[i], nodeX[i + 1], nodeY[i + 1]
        local future = nodeFuture[i + 1]
        local dx, dy = x2 - x1, y2 - y1
        local segLen = math_sqrt(dx * dx + dy * dy)
        if segLen < 3 then
            pushPath(x2, y2, future)
        else
            local x0, y0 = x1, y1
            if i > 1 then x0, y0 = nodeX[i - 1], nodeY[i - 1] end
            local x3, y3 = x2, y2
            if i + 2 <= nodeCount then x3, y3 = nodeX[i + 2], nodeY[i + 2] end

            local sx, sy = dx / segLen, dy / segLen
            local t1x, t1y = unit(x2 - x0, y2 - y0, sx, sy)
            local t2x, t2y = unit(x3 - x1, y3 - y1, sx, sy)
            -- Evita que las asas apunten hacia atras en giros cerrados (bucles)
            if t1x * sx + t1y * sy < 0.18 then t1x, t1y = sx, sy end
            if t2x * sx + t2y * sy < 0.18 then t2x, t2y = sx, sy end

            local handle = segLen * SMOOTH_STRENGTH
            local c1x, c1y = x1 + t1x * handle, y1 + t1y * handle
            local c2x, c2y = x2 - t2x * handle, y2 - t2y * handle
            local subdivisions = (segLen < 60 and 3) or (segLen < 200 and 5) or 8
            for j = 1, subdivisions do
                local t = j / subdivisions
                local u = 1 - t
                local a, b, c, d = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
                pushPath(a * x1 + b * c1x + c * c2x + d * x2, a * y1 + b * c1y + c * c2y + d * y2, future)
            end
        end
    end
end

local function rebuildPath()
    local futureSteps = math.floor(numberSetting("navRouteFutureSteps", 0, 5) + 0.5)
    pathInstance = collectNodes(futureSteps)
    if not pathInstance or nodeCount == 0 then
        pathCount = 0
        pathInstance = nil
        return
    end
    buildSmoothPath()
end

---------------------------------------------------------------------------
-- Capas de dibujo (pool de lineas reutilizables)
---------------------------------------------------------------------------

local function createLayer(parent, anchor)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:EnableMouse(false)
    return {
        frame = frame, anchor = anchor,
        lines = {}, outlines = {}, chevA = {}, chevB = {},
        nLines = 0, nChev = 0,
        sx = {}, sy = {}, sf = {}, sg = {},
        r = 0.7, g = 0.7, b = 0.7,
    }
end

local function layerSegment(layer, x1, y1, x2, y2, thickness, outlineThickness, alpha)
    local i = layer.nLines + 1
    if i > MAX_LINES then return end
    layer.nLines = i
    local frame, anchor = layer.frame, layer.anchor
    local line, outline = layer.lines[i], layer.outlines[i]
    if not line then
        outline = frame:CreateLine(nil, "ARTWORK", nil, 1)
        line = frame:CreateLine(nil, "ARTWORK", nil, 2)
        layer.outlines[i], layer.lines[i] = outline, line
    end
    outline:SetStartPoint(anchor, frame, x1, y1)
    outline:SetEndPoint(anchor, frame, x2, y2)
    outline:SetThickness(outlineThickness)
    outline:SetColorTexture(0.04, 0.04, 0.04, alpha * 0.70)
    outline:Show()
    line:SetStartPoint(anchor, frame, x1, y1)
    line:SetEndPoint(anchor, frame, x2, y2)
    line:SetThickness(thickness)
    line:SetColorTexture(layer.r, layer.g, layer.b, alpha)
    line:Show()
end

local function layerChevron(layer, cx, cy, ux, uy, size, thickness, alpha)
    local i = layer.nChev + 1
    if i > MAX_CHEVRONS then return end
    layer.nChev = i
    local frame, anchor = layer.frame, layer.anchor
    local a, b = layer.chevA[i], layer.chevB[i]
    if not a then
        a = frame:CreateLine(nil, "OVERLAY", nil, 3)
        b = frame:CreateLine(nil, "OVERLAY", nil, 3)
        layer.chevA[i], layer.chevB[i] = a, b
    end
    local px, py = -uy, ux
    local half = size * 0.45
    local wing = size * 0.52
    local tipX, tipY = cx + ux * half, cy + uy * half
    local backX, backY = cx - ux * half, cy - uy * half
    local cr = math_min(1, layer.r + 0.22)
    local cg = math_min(1, layer.g + 0.22)
    local cb = math_min(1, layer.b + 0.22)
    a:SetStartPoint(anchor, frame, backX + px * wing, backY + py * wing)
    a:SetEndPoint(anchor, frame, tipX, tipY)
    b:SetStartPoint(anchor, frame, backX - px * wing, backY - py * wing)
    b:SetEndPoint(anchor, frame, tipX, tipY)
    a:SetThickness(thickness); b:SetThickness(thickness)
    a:SetColorTexture(cr, cg, cb, alpha); b:SetColorTexture(cr, cg, cb, alpha)
    a:Show(); b:Show()
end

local function layerFinish(layer)
    for i = layer.nLines + 1, #layer.lines do
        layer.lines[i]:Hide()
        layer.outlines[i]:Hide()
    end
    for i = layer.nChev + 1, #layer.chevA do
        layer.chevA[i]:Hide()
        layer.chevB[i]:Hide()
    end
end

local function layerClear(layer)
    if not layer then return end
    layer.nLines, layer.nChev = 0, 0
    layerFinish(layer)
end

local function layerSetColor(layer)
    local gray = numberSetting("navRouteGray", 0.2, 1)
    layer.r, layer.g, layer.b = gray, gray, gray
end

---------------------------------------------------------------------------
-- Recorte de segmentos
---------------------------------------------------------------------------

local function clipCircle(x1, y1, x2, y2, radius)
    local dx, dy = x2 - x1, y2 - y1
    local a = dx * dx + dy * dy
    if a < 1e-9 then return nil end
    local b = 2 * (x1 * dx + y1 * dy)
    local c = x1 * x1 + y1 * y1 - radius * radius
    local disc = b * b - 4 * a * c
    if disc <= 0 then return nil end
    local sq = math_sqrt(disc)
    local t0 = (-b - sq) / (2 * a)
    local t1 = (-b + sq) / (2 * a)
    if t0 < 0 then t0 = 0 end
    if t1 > 1 then t1 = 1 end
    if t0 >= t1 then return nil end
    return t0, t1
end

local function clipEdge(p, q, t0, t1)
    if p == 0 then
        if q < 0 then return nil end
        return t0, t1
    end
    local r = q / p
    if p < 0 then
        if r > t1 then return nil end
        if r > t0 then t0 = r end
    else
        if r < t0 then return nil end
        if r < t1 then t1 = r end
    end
    return t0, t1
end

-- Liang-Barsky
local function clipRect(x1, y1, x2, y2, minX, minY, maxX, maxY)
    local dx, dy = x2 - x1, y2 - y1
    local t0, t1 = clipEdge(-dx, x1 - minX, 0, 1)
    if not t0 then return nil end
    t0, t1 = clipEdge(dx, maxX - x1, t0, t1)
    if not t0 then return nil end
    t0, t1 = clipEdge(-dy, y1 - minY, t0, t1)
    if not t0 then return nil end
    t0, t1 = clipEdge(dy, maxY - y1, t0, t1)
    if not t0 or t0 >= t1 then return nil end
    return t0, t1
end

---------------------------------------------------------------------------
-- Dibujo de la polilinea proyectada (layer.sx/sy, indices 1..count)
---------------------------------------------------------------------------

local function drawProjected(layer, count, clipMode, c1, c2, c3, c4, style)
    local sx, sy, sf, sg = layer.sx, layer.sy, layer.sf, layer.sg
    local thickness, outlineThickness = style.thickness, style.outline
    local alphaNow, alphaFuture = style.alpha, style.alpha * FUTURE_ALPHA_FACTOR
    local spacing = style.spacing
    local phase = style.phase or 0
    local minStart = style.minStart or 0
    local accumulated = 0

    for k = 2, count do
        local x1, y1, x2, y2 = sx[k - 1], sy[k - 1], sx[k], sy[k]
        local dx, dy = x2 - x1, y2 - y1
        local len = math_sqrt(dx * dx + dy * dy)
        if not sg[k] and len > 0.5 then
            local t0, t1
            if clipMode == "circle" then
                t0, t1 = clipCircle(x1, y1, x2, y2, c1)
            else
                t0, t1 = clipRect(x1, y1, x2, y2, c1, c2, c3, c4)
            end
            if t0 then
                local alpha = sf[k] and alphaFuture or alphaNow
                layerSegment(layer, x1 + dx * t0, y1 + dy * t0, x1 + dx * t1, y1 + dy * t1,
                    thickness, outlineThickness, alpha)
                if spacing then
                    local ux, uy = dx / len, dy / len
                    local from, to = accumulated + t0 * len, accumulated + t1 * len
                    local s = phase + spacing * math_ceil((from - phase) / spacing)
                    while s <= to do
                        if s >= minStart then
                            local t = (s - accumulated) / len
                            layerChevron(layer, x1 + dx * t, y1 + dy * t, ux, uy,
                                style.chevronSize, style.chevronThickness, math_min(1, alpha + 0.1))
                        end
                        s = s + spacing
                    end
                end
            end
        end
        accumulated = accumulated + len
    end
end

---------------------------------------------------------------------------
-- Minimapa
---------------------------------------------------------------------------

local minimapStyle = {}

local function getMinimapRadius()
    if C_Minimap and C_Minimap.GetViewRadius then
        local ok, radius = pcall(C_Minimap.GetViewRadius)
        if ok and type(radius) == "number" and radius > 0 then return radius end
    end
    local zoom = Minimap:GetZoom() or 0
    local mode = "outdoor"
    local outside = tonumber(GetCVar("minimapZoom"))
    local inside = tonumber(GetCVar("minimapInsideZoom"))
    if outside and inside and outside ~= inside then
        if zoom == inside then mode = "indoor" end
    elseif IsIndoors and IsIndoors() then
        mode = "indoor"
    end
    local size = MINIMAP_SIZE[mode][zoom] or 200
    return size / 2
end

local function renderMinimap(now)
    if not minimapLayer then return end
    if pathCount == 0 or not setting("navRouteMinimap") then
        layerClear(minimapLayer)
        return
    end

    local px, py, instance = HBD:GetPlayerWorldPosition()
    if not px or instance ~= pathInstance then
        layerClear(minimapLayer)
        return
    end

    local rotate = GetCVar("rotateMinimap") == "1"
    local sinF, cosF = 0, 1
    if rotate then
        local facing = GetPlayerFacing and GetPlayerFacing()
        if not facing then
            layerClear(minimapLayer)
            return
        end
        sinF, cosF = math_sin(facing), math_cos(facing)
    end

    local radius = getMinimapRadius()
    local halfW, halfH = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
    if radius <= 0 or halfW <= 0 or halfH <= 0 then
        layerClear(minimapLayer)
        return
    end
    local kx, ky = halfW / radius, halfH / radius

    -- Proyeccion identica a HereBeDragons-Pins (la usada por los pines de RXP)
    local sx, sy, sf, sg = minimapLayer.sx, minimapLayer.sy, minimapLayer.sf, minimapLayer.sg
    sx[1], sy[1], sf[1], sg[1] = 0, 0, false, false
    for i = 1, pathCount do
        local dx, dy = px - pathX[i], py - pathY[i]
        if rotate then
            dx, dy = dx * cosF - dy * sinF, dx * sinF + dy * cosF
        end
        local k = i + 1
        sx[k], sy[k], sf[k], sg[k] = dx * kx, -dy * ky, pathFuture[i], false
    end

    local thickness = numberSetting("navRouteThickness", 1, 6)
    minimapStyle.thickness = thickness
    minimapStyle.outline = thickness + 2
    minimapStyle.alpha = numberSetting("navRouteAlpha", 0.1, 1)
    if setting("navRouteArrows") then
        minimapStyle.spacing = 22
        minimapStyle.phase = (now * 12) % 22
        minimapStyle.minStart = 9
        minimapStyle.chevronSize = 4 + thickness * 0.5
        minimapStyle.chevronThickness = math_max(1, thickness * 0.5)
    else
        minimapStyle.spacing = nil
    end

    layerSetColor(minimapLayer)
    minimapLayer.nLines, minimapLayer.nChev = 0, 0
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        local cw, ch = halfW * MINIMAP_CLIP, halfH * MINIMAP_CLIP
        drawProjected(minimapLayer, pathCount + 1, "rect", -cw, -ch, cw, ch, minimapStyle)
    else
        drawProjected(minimapLayer, pathCount + 1, "circle", math_min(halfW, halfH) * MINIMAP_CLIP, nil, nil, nil, minimapStyle)
    end
    layerFinish(minimapLayer)
end

---------------------------------------------------------------------------
-- Mapa del mundo
---------------------------------------------------------------------------

local worldStyle = {}

local function getWorldMapCanvas()
    local scroll = WorldMapFrame and WorldMapFrame.ScrollContainer
    if not scroll then return nil end
    return scroll.Child or (scroll.GetScrollChild and scroll:GetScrollChild()) or nil
end

local function ensureWorldLayer()
    if worldLayer then return true end
    local canvas = getWorldMapCanvas()
    if not canvas then return false end
    worldLayer = createLayer(canvas, "TOPLEFT")
    worldLayer.frame:SetFrameStrata(canvas:GetFrameStrata())
    return true
end

-- Compatibilidad con OpenMap (mapa del mundo "cosido"):
--  * Pinta su arte en el lienzo hasta el nivel OpenMapAPI.ArtTopLevel(), que
--    tapa cualquier capa a nivel fijo (la nuestra iba a 2005).
--  * El mapa base (GetMapID) cambia mientras se desplaza la vista y se ve
--    terreno fuera de su rectangulo, asi que no se puede recortar a el.
--  * Para proyectar usamos su API publica CanvasFromWorldPos, que coloca los
--    puntos sobre su mapa cosido (no el de Blizzard).
local function getOpenMapStitched()
    local api = _G.OpenMapAPI
    if type(api) ~= "table" or type(api.IsStitched) ~= "function" then return nil end
    local ok, stitched = pcall(api.IsStitched)
    if ok and stitched then return api end
    return nil
end

local DEFAULT_WORLD_LEVEL = 2005 -- justo por debajo de las lineas (2010) y pines de RXPGuides

local function updateWorldLayerLevel(openMap)
    local canvas = worldLayer.frame:GetParent()
    local level = math_max((canvas:GetFrameLevel() or 1) + 1, DEFAULT_WORLD_LEVEL)
    if openMap and type(openMap.ArtTopLevel) == "function" then
        local ok, top = pcall(openMap.ArtTopLevel)
        -- top + 1: encima del arte, por debajo de los iconos que OpenMap eleva (top + 2)
        if ok and type(top) == "number" and top + 1 > level then level = top + 1 end
    end
    if worldLayer.level ~= level then
        worldLayer.level = level
        worldLayer.frame:SetFrameLevel(level)
    end
end

local projectionAPI -- OpenMapAPI mientras el mapa esta cosido, o nil

local function projectToMap(wx, wy, instance, mapID)
    if projectionAPI then
        -- OpenMap espera el orden de UnitPosition (HBD intercambia x/y)
        local ok, mx, my = pcall(projectionAPI.CanvasFromWorldPos, instance, wy, wx)
        if ok and mx and my then return mx, my end
    end
    if HBD.GetZoneCoordinatesFromWorldInstance then
        return HBD:GetZoneCoordinatesFromWorldInstance(wx, wy, instance, mapID, true)
    end
    return HBD:GetZoneCoordinatesFromWorld(wx, wy, mapID, true)
end

local function renderWorldMap(now)
    if not worldLayer then return end
    projectionAPI = getOpenMapStitched()
    updateWorldLayerLevel(projectionAPI)
    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local canvas = worldLayer.frame:GetParent()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    if pathCount == 0 or not mapID or not w or not h or w < 10 or h < 10 then
        layerClear(worldLayer)
        return
    end

    local sx, sy, sf, sg = worldLayer.sx, worldLayer.sy, worldLayer.sf, worldLayer.sg
    local count = 0
    local px, py, instance = HBD:GetPlayerWorldPosition()
    if px and instance == pathInstance then
        local mx, my = projectToMap(px, py, instance, mapID)
        if mx and my then
            count = 1
            sx[1], sy[1], sf[1], sg[1] = mx * w, -my * h, false, true
        end
    end
    local gap = count == 0
    for i = 1, pathCount do
        local mx, my = projectToMap(pathX[i], pathY[i], pathInstance, mapID)
        if mx and my then
            count = count + 1
            sx[count], sy[count], sf[count], sg[count] = mx * w, -my * h, pathFuture[i], gap
            gap = false
        else
            gap = true
        end
    end
    if count < 2 then
        layerClear(worldLayer)
        return
    end

    -- Grosor constante en pantalla independientemente del zoom del mapa
    local scale = canvas:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if not scale or scale <= 0 then scale = 1 end
    local thickness = numberSetting("navRouteThickness", 1, 6)
    worldStyle.thickness = (thickness + 0.5) / scale
    worldStyle.outline = (thickness + 2.5) / scale
    worldStyle.alpha = numberSetting("navRouteAlpha", 0.1, 1)
    if setting("navRouteArrows") then
        local spacing = 38 / scale
        worldStyle.spacing = spacing
        worldStyle.phase = (now * 18 / scale) % spacing
        worldStyle.minStart = 6 / scale
        worldStyle.chevronSize = (6 + thickness * 0.6) / scale
        worldStyle.chevronThickness = math_max(1, thickness * 0.55) / scale
    else
        worldStyle.spacing = nil
    end

    -- Recorte a la zona visible de la vista (en coordenadas del lienzo, con
    -- margen). Con el mapa de Blizzard ademas se limita al rectangulo del mapa;
    -- con OpenMap no, porque su vista muestra terreno fuera del mapa base.
    local minX, minY, maxX, maxY = 0, -h, w, 0
    if projectionAPI then
        minX, minY, maxX, maxY = -w, -2 * h, 2 * w, h
    end
    local view = WorldMapFrame.ScrollContainer
    local cLeft, cTop = canvas:GetLeft(), canvas:GetTop()
    local vLeft, vRight, vTop, vBottom = view:GetLeft(), view:GetRight(), view:GetTop(), view:GetBottom()
    if cLeft and cTop and vLeft and vRight and vTop and vBottom then
        local cScale, vScale = canvas:GetEffectiveScale(), view:GetEffectiveScale()
        local margin = 20 / scale
        local x1 = (vLeft * vScale - cLeft * cScale) / cScale - margin
        local x2 = (vRight * vScale - cLeft * cScale) / cScale + margin
        local y1 = (vBottom * vScale - cTop * cScale) / cScale - margin
        local y2 = (vTop * vScale - cTop * cScale) / cScale + margin
        if projectionAPI then
            minX, minY, maxX, maxY = x1, y1, x2, y2
        else
            minX, minY, maxX, maxY = math_max(0, x1), math_max(-h, y1), math_min(w, x2), math_min(0, y2)
        end
    end
    if minX >= maxX or minY >= maxY then
        layerClear(worldLayer)
        return
    end

    layerSetColor(worldLayer)
    worldLayer.nLines, worldLayer.nChev = 0, 0
    drawProjected(worldLayer, count, "rect", minX, minY, maxX, maxY, worldStyle)
    layerFinish(worldLayer)
end

---------------------------------------------------------------------------
-- Bucle y API
---------------------------------------------------------------------------

local function hideAll()
    layerClear(minimapLayer)
    layerClear(worldLayer)
end

local function onUpdate(_, elapsed)
    local now = GetTime()
    rebuildElapsed = rebuildElapsed + elapsed
    if rebuildElapsed >= REBUILD_INTERVAL then
        rebuildElapsed = 0
        rebuildPath()
    end

    minimapElapsed = minimapElapsed + elapsed
    if minimapElapsed >= MINIMAP_INTERVAL then
        minimapElapsed = 0
        renderMinimap(now)
    end

    if WorldMapFrame and WorldMapFrame:IsShown() and setting("navRouteWorldMap") then
        worldElapsed = worldElapsed + elapsed
        if worldElapsed >= WORLDMAP_INTERVAL then
            worldElapsed = 0
            if ensureWorldLayer() then renderWorldMap(now) end
        end
    elseif worldLayer and worldLayer.nLines > 0 then
        layerClear(worldLayer)
    end
end

function NavRoute:IsAvailable()
    if not HBD and LibStub then HBD = LibStub("HereBeDragons-2.0", true) end
    return HBD ~= nil and getRXP() ~= nil
end

function NavRoute:Refresh()
    local enabled = setting("navRouteEnabled") and self:IsAvailable()
    if not enabled then
        if running then
            running = false
            self:SetScript("OnUpdate", nil)
        end
        hideAll()
        return
    end
    if not minimapLayer and Minimap then
        minimapLayer = createLayer(Minimap, "CENTER")
        minimapLayer.frame:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 1)
    end
    rebuildPath()
    local now = GetTime()
    renderMinimap(now)
    if WorldMapFrame and WorldMapFrame:IsShown() and setting("navRouteWorldMap") and ensureWorldLayer() then
        renderWorldMap(now)
    else
        layerClear(worldLayer)
    end
    if not running then
        running = true
        rebuildElapsed, minimapElapsed, worldElapsed = 0, 0, 0
        self:SetScript("OnUpdate", onUpdate)
    end
end

function NavRoute:Init(database)
    db = database
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:SetScript("OnEvent", function()
        rebuildElapsed = REBUILD_INTERVAL
    end)
    self:Refresh()
end
