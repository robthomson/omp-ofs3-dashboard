--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local dashboard = {}

local supportedResolutions = {
    {784, 294}, {784, 316}, {800, 458}, {800, 480},
    {472, 191}, {472, 210}, {480, 301}, {480, 320},
    {630, 236}, {630, 258}, {640, 338}, {640, 360}
}

local themeBasePath = "SCRIPTS:/" .. ofs3.config.baseDir .. "/widgets/dashboard/themes/@rt-rc/"
local currentState = nil
local loadedStates = {}
local lastSizeKey = nil
local darkModeState = lcd.darkMode()
local unsupportedResolution = false
local forceFullRepaint = true
local lastInvalidateAt = 0
local invalidateInterval = 0.1
local lastHiddenWakeAt = 0
local hiddenWakeInterval = 1.0
local gestureActive = false
local gestureStartX = 0
local gestureStartY = 0
local gestureTriggered = false
local gestureConsumeUntilTouchEnd = false
local GESTURE_MIN_DY = 20
local GESTURE_MAX_DX = 40
local TOOLBAR_TIMEOUT = 5.0

dashboard.title = false
dashboard.renders = {}
dashboard.objectsByType = {}
dashboard.boxRects = {}
dashboard._moduleCache = {}
dashboard.toolbarVisible = dashboard.toolbarVisible or false
dashboard.selectedToolbarIndex = dashboard.selectedToolbarIndex or nil
dashboard.toolbarLastActivityAt = dashboard.toolbarLastActivityAt or 0

function dashboard.touchToolbar()
    dashboard.toolbarLastActivityAt = os.clock()
end

function dashboard.openToolbar()
    dashboard.toolbarVisible = true
    dashboard.selectedToolbarIndex = dashboard.selectedToolbarIndex or 1
    dashboard.touchToolbar()
end

function dashboard.closeToolbar()
    dashboard.toolbarVisible = false
    dashboard.selectedToolbarIndex = nil
    dashboard.toolbarLastActivityAt = 0
end

local function ensureDashboardLibraries()
    dashboard.utils = dashboard.utils or assert(loadfile("SCRIPTS:/" .. ofs3.config.baseDir .. "/widgets/dashboard/lib/utils.lua"))()
    dashboard.loaders = dashboard.loaders or assert(loadfile("SCRIPTS:/" .. ofs3.config.baseDir .. "/widgets/dashboard/lib/loaders.lua"))()
    dashboard.toolbar = dashboard.toolbar or assert(loadfile("SCRIPTS:/" .. ofs3.config.baseDir .. "/widgets/dashboard/lib/toolbar.lua"))()
end

local function logWidgetMenu(action)
    local summary = ofs3.logs and ofs3.logs.getSummary and ofs3.logs.getSummary() or {}
    local craftName = summary.craftName or "Model"
    local flightCount = tonumber(summary.flightCount) or 0
    local totalFlightTime = tonumber(summary.totalFlightTime) or 0
    local totalFlightText = ofs3.logs and ofs3.logs.formatDuration and ofs3.logs.formatDuration(totalFlightTime) or tostring(totalFlightTime)
    local telemetryState = ofs3.session and ofs3.session.telemetryState and "ready" or "waiting"
    local flightMode = ofs3.flightmode and ofs3.flightmode.current or "preflight"

    ofs3.utils.log(string.format("Widget menu %s: craft=%s flightmode=%s telemetry=%s flights=%d total=%s", tostring(action), tostring(craftName), tostring(flightMode), telemetryState, flightCount, totalFlightText))
end

local function consumeTouchSequence(value)
    if not system.killEvents then
        return
    end

    if value ~= nil then
        system.killEvents(value)
    end

    if TOUCH_START then
        system.killEvents(TOUCH_START)
    end

    if value == TOUCH_END and TOUCH_END then
        system.killEvents(TOUCH_END)
    end
end

local function getBoxSize(box, boxWidth, boxHeight, padding, widgetW, widgetH)
    if box.w_pct and box.h_pct then
        local wp = box.w_pct > 1 and (box.w_pct / 100) or box.w_pct
        local hp = box.h_pct > 1 and (box.h_pct / 100) or box.h_pct
        return math.floor(wp * widgetW), math.floor(hp * widgetH)
    end

    if box.w and box.h then
        return tonumber(box.w) or boxWidth, tonumber(box.h) or boxHeight
    end

    if box.colspan or box.rowspan then
        local width = math.floor((box.colspan or 1) * boxWidth + ((box.colspan or 1) - 1) * padding)
        local height = math.floor((box.rowspan or 1) * boxHeight + ((box.rowspan or 1) - 1) * padding)
        return width, height
    end

    return boxWidth, boxHeight
end

local function getBoxPosition(box, width, height, boxWidth, boxHeight, padding, widgetW, widgetH)
    if box.x_pct and box.y_pct then
        local xp = box.x_pct > 1 and (box.x_pct / 100) or box.x_pct
        local yp = box.y_pct > 1 and (box.y_pct / 100) or box.y_pct
        return math.floor(xp * (widgetW - width)), math.floor(yp * (widgetH - height))
    end

    if box.x and box.y then
        return tonumber(box.x) or 0, tonumber(box.y) or 0
    end

    if box.col and box.row then
        local x = math.floor((box.col - 1) * (boxWidth + padding)) + (box.xOffset or 0)
        local y = math.floor(padding + (box.row - 1) * (boxHeight + padding))
        return x, y
    end

    return 0, 0
end

local function adjustDimension(dimension, cells, padCount, padding)
    return dimension - ((dimension - padCount * padding) % cells)
end

local function loadObjectType(box)
    local objectType = box and box.type
    if not objectType then
        return
    end

    if dashboard._moduleCache[objectType] == nil then
        local objectPath = "SCRIPTS:/" .. ofs3.config.baseDir .. "/widgets/dashboard/objects/" .. objectType .. ".lua"
        local loader = loadfile(objectPath)
        if loader then
            local ok, module = pcall(loader)
            dashboard._moduleCache[objectType] = ok and module or false
        else
            dashboard._moduleCache[objectType] = false
        end
    end

    if dashboard._moduleCache[objectType] then
        dashboard.objectsByType[objectType] = dashboard._moduleCache[objectType]
    end
end

local function loadObjects(module)
    dashboard.objectsByType = {}

    local boxes = type(module.boxes) == "function" and module.boxes() or (module.boxes or {})
    local headerBoxes = module.header_boxes or {}

    for _, box in ipairs(boxes) do
        loadObjectType(box)
    end

    for _, box in ipairs(headerBoxes) do
        loadObjectType(box)
    end
end

local function reloadTheme()
    loadedStates = {
        preflight = assert(loadfile(themeBasePath .. "preflight.lua"))(),
        inflight = assert(loadfile(themeBasePath .. "inflight.lua"))(),
        postflight = assert(loadfile(themeBasePath .. "postflight.lua"))()
    }

    dashboard.utils.resetImageCache()
    dashboard.boxRects = {}
    currentState = nil
    ofs3.theme.version = (ofs3.theme.version or 0) + 1
    forceFullRepaint = true
end

local function buildRects(module)
    local utils = dashboard.utils
    local layout = module.layout or {}
    local headerLayout = module.header_layout or {}
    local boxes = type(module.boxes) == "function" and module.boxes() or (module.boxes or {})
    local headerBoxes = module.header_boxes or {}

    local windowW, windowH = lcd.getWindowSize()
    local isFullScreen = utils.isFullScreen(windowW, windowH)

    local cols = layout.cols or 1
    local rows = layout.rows or 1
    local padding = layout.padding or 0

    local contentHeight = windowH
    if isFullScreen and headerLayout.height then
        contentHeight = contentHeight - headerLayout.height
    end

    local adjustedW = adjustDimension(windowW, cols, cols - 1, padding)
    local adjustedH = adjustDimension(contentHeight, rows, rows + 1, padding)
    local xOffset = math.floor((windowW - adjustedW) / 2)

    local contentW = adjustedW - ((cols - 1) * padding)
    local contentH = adjustedH - ((rows + 1) * padding)
    local boxW = contentW / cols
    local boxH = contentH / rows

    dashboard.boxRects = {}

    for _, box in ipairs(boxes) do
        local width, height = getBoxSize(box, boxW, boxH, padding, adjustedW, adjustedH)
        box.xOffset = xOffset
        local x, y = getBoxPosition(box, width, height, boxW, boxH, padding, adjustedW, adjustedH)
        if isFullScreen and headerLayout.height then
            y = y + headerLayout.height
        end
        dashboard.boxRects[#dashboard.boxRects + 1] = {x = x, y = y, w = width, h = height, box = box}
    end

    if isFullScreen and #headerBoxes > 0 then
        local headerCols = headerLayout.cols or 1
        local headerRows = headerLayout.rows or 1
        local headerPadding = headerLayout.padding or 0
        local headerHeight = headerLayout.height or 0

        local adjustedHeaderW = adjustDimension(windowW, headerCols, headerCols - 1, headerPadding)
        local adjustedHeaderH = adjustDimension(headerHeight, headerRows, headerRows - 1, headerPadding)
        local headerContentW = adjustedHeaderW - ((headerCols - 1) * headerPadding)
        local headerContentH = adjustedHeaderH - ((headerRows - 1) * headerPadding)
        local headerBoxW = headerContentW / headerCols
        local headerBoxH = headerContentH / headerRows

        local rightmostIndex = 1
        local rightmostX = 0
        local headerGeometries = {}

        for index, box in ipairs(headerBoxes) do
            local width, height = getBoxSize(box, headerBoxW, headerBoxH, headerPadding, adjustedHeaderW, adjustedHeaderH)
            local x, y = getBoxPosition(box, width, height, headerBoxW, headerBoxH, headerPadding, adjustedHeaderW, adjustedHeaderH)
            headerGeometries[index] = {x = x, y = y, w = width, h = height, box = box}
            if x > rightmostX then
                rightmostIndex = index
                rightmostX = x
            end
        end

        for index, geom in ipairs(headerGeometries) do
            local width = geom.w
            if index == rightmostIndex then
                width = windowW - geom.x
            end
            dashboard.boxRects[#dashboard.boxRects + 1] = {x = geom.x, y = geom.y, w = width, h = geom.h, box = geom.box}
        end
    end
end

local function ensureState()
    local nextState = ofs3.flightmode.current or "preflight"
    if nextState ~= currentState then
        currentState = nextState
        local module = loadedStates[currentState]
        loadObjects(module)
        forceFullRepaint = true
    end

    local width, height = lcd.getWindowSize()
    local sizeKey = string.format("%dx%d", width, height)
    if sizeKey ~= lastSizeKey then
        lastSizeKey = sizeKey
        forceFullRepaint = true
    end

    buildRects(loadedStates[currentState])
    return loadedStates[currentState]
end

local function wakeObjects()
    local dirty = forceFullRepaint

    for _, rect in ipairs(dashboard.boxRects) do
        local object = dashboard.objectsByType[rect.box.type]
        if object and object.wakeup then
            object.wakeup(rect.box)
        end
        if not dirty and object and object.dirty and object.dirty(rect.box) then
            dirty = true
        end
    end

    return dirty
end

local function paintObjects()
    local module = loadedStates[currentState]
    dashboard.utils.setBackgroundColourBasedOnTheme()

    for _, rect in ipairs(dashboard.boxRects) do
        local object = dashboard.objectsByType[rect.box.type]
        if object and object.paint then
            object.paint(rect.x, rect.y, rect.w, rect.h, rect.box)
        end
    end

    if not ofs3.session.telemetryState and currentState ~= "postflight" then
        local windowW, windowH = lcd.getWindowSize()
        local offsetY = 0
        if module.header_layout and dashboard.utils.isFullScreen(windowW, windowH) then
            offsetY = module.header_layout.height or 0
        end
        dashboard.overlaymessage(0, offsetY, windowW, windowH - offsetY, "@i18n(widgets.dashboard.telemetry_waiting)@")
    end
end

function dashboard.loader(x, y, w, h)
    dashboard.loaders.staticLoader(dashboard, x, y, w, h)
end

function dashboard.overlaymessage(x, y, w, h, text)
    dashboard.loaders.staticOverlayMessage(dashboard, x, y, w, h, text)
end

function dashboard.create()
    ensureDashboardLibraries()
    reloadTheme()
    return {}
end

function dashboard.menu(widget)
    ensureDashboardLibraries()
    logWidgetMenu("opened")

    return {
        {
            "@i18n(widgets.dashboard.reset_flight)@",
            function()
                logWidgetMenu("selected Reset Flight")
                if type(dashboard.resetFlightModeAsk) == "function" then
                    dashboard.resetFlightModeAsk()
                end
                if lcd.invalidate then
                    lcd.invalidate(widget)
                end
            end
        }
    }
end

function dashboard.resetFlightModeAsk()
    local buttons = {
        {
            label = "@i18n(widgets.dashboard.ok)@",
            action = function()
                if ofs3.runtime and ofs3.runtime.resetFlight then
                    ofs3.runtime.resetFlight()
                end
                if model and type(model.resetFlight) == "function" then
                    pcall(model.resetFlight)
                end
                dashboard.closeToolbar()
                if lcd.invalidate then
                    lcd.invalidate()
                end
                return true
            end
        },
        {
            label = "@i18n(widgets.dashboard.cancel)@",
            action = function()
                return true
            end
        }
    }

    form.openDialog({
        title = "@i18n(widgets.dashboard.reset_flight)@",
        message = "@i18n(widgets.dashboard.reset_flight_message)@",
        buttons = buttons,
        options = TEXT_LEFT
    })
end

function dashboard.paint()
    if unsupportedResolution then
        dashboard.utils.screenError("@i18n(widgets.dashboard.unsupported_widget_size)@", true, 0.5)
        return
    end

    ensureState()
    paintObjects()
    if dashboard.toolbar and dashboard.toolbar.draw then
        dashboard.toolbar.draw(dashboard)
    end
end

function dashboard.wakeup(widget)
    local visible = lcd.isVisible(widget)
    local now = os.clock()

    if not visible then
        if (now - lastHiddenWakeAt) < hiddenWakeInterval then
            return
        end
        lastHiddenWakeAt = now
        ofs3.runtime.wakeup()
        return
    end

    local runtimeState = ofs3.runtime.wakeup()

    local width, height = lcd.getWindowSize()
    unsupportedResolution = not dashboard.utils.supportedResolution(width, height, supportedResolutions)
    if unsupportedResolution then
        lcd.invalidate(widget)
        return
    end

    if runtimeState.model_changed or lcd.darkMode() ~= darkModeState then
        darkModeState = lcd.darkMode()
        reloadTheme()
    end

    ensureState()

    if dashboard.toolbarVisible and dashboard.toolbarLastActivityAt > 0 and (now - dashboard.toolbarLastActivityAt) >= TOOLBAR_TIMEOUT then
        dashboard.closeToolbar()
        lcd.invalidate(widget)
    end

    if wakeObjects() or runtimeState.flightmode_changed or (now - lastInvalidateAt) >= invalidateInterval then
        forceFullRepaint = false
        lastInvalidateAt = now
        lcd.invalidate(widget)
    end
end

function dashboard.event(widget, category, value, x, y)
    if gestureConsumeUntilTouchEnd and category == EVT_TOUCH then
        consumeTouchSequence(value)
        if value == TOUCH_END then
            gestureConsumeUntilTouchEnd = false
            gestureActive = false
            gestureTriggered = false
        end
        return true
    end

    if dashboard.toolbar and dashboard.toolbar.handleEvent and dashboard.toolbar.handleEvent(dashboard, widget, category, value, x, y) then
        return true
    end

    if category == EVT_KEY and value == KEY_PAGE_LONG and lcd.hasFocus() then
        dashboard.openToolbar()
        lcd.invalidate(widget)
        if system.killEvents then
            system.killEvents(value)
            if KEY_PAGE_UP and KEY_PAGE_UP ~= value then
                system.killEvents(KEY_PAGE_UP)
            end
        end
        return true
    end

    if category == EVT_TOUCH and (value == TOUCH_START or value == TOUCH_END) and x and y then
        gestureActive = true
        gestureStartX = x
        gestureStartY = y
        gestureTriggered = false
    end

    if category == EVT_TOUCH and value == TOUCH_MOVE then
        if not gestureActive and x and y then
            gestureActive = true
            gestureStartX = x
            gestureStartY = y
            gestureTriggered = false
        end

        if gestureActive and not gestureTriggered and x and y then
            local dx = x - gestureStartX
            local dy = y - gestureStartY
            if math.abs(dx) <= GESTURE_MAX_DX then
                if dy <= -GESTURE_MIN_DY then
                    gestureTriggered = true
                    gestureConsumeUntilTouchEnd = true
                    consumeTouchSequence(TOUCH_START)
                    dashboard.openToolbar()
                    lcd.invalidate(widget)
                    return true
                elseif dy >= GESTURE_MIN_DY then
                    gestureTriggered = true
                    gestureConsumeUntilTouchEnd = true
                    consumeTouchSequence(TOUCH_START)
                    dashboard.closeToolbar()
                    lcd.invalidate(widget)
                    return true
                end
            end
        end
    end

    if dashboard.toolbarVisible then
        return false
    end

    local indices = {}
    for index, rect in ipairs(dashboard.boxRects or {}) do
        if rect and rect.box and rect.box.onpress then
            indices[#indices + 1] = index
        end
    end

    if category == EVT_KEY and lcd.hasFocus() then
        local count = #indices
        if count == 0 then
            dashboard.selectedBoxIndex = nil
            return false
        end

        local current = dashboard.selectedBoxIndex or indices[1]
        local pos = 1
        for index, rectIndex in ipairs(indices) do
            if rectIndex == current then
                pos = index
                break
            end
        end

        if value == ROTARY_LEFT then
            pos = pos - 1
            if pos < 1 then
                pos = count
            end
            dashboard.selectedBoxIndex = indices[pos]
            lcd.invalidate(widget)
            return true
        elseif value == KEY_ROTARY_RIGHT then
            pos = pos + 1
            if pos > count then
                pos = 1
            end
            dashboard.selectedBoxIndex = indices[pos]
            lcd.invalidate(widget)
            return true
        elseif value == KEY_ENTER_BREAK then
            local selectedIndex = dashboard.selectedBoxIndex
            local rect = selectedIndex and dashboard.boxRects[selectedIndex] or nil
            if not rect then
                dashboard.selectedBoxIndex = indices[1]
                lcd.invalidate(widget)
                return true
            end
            if rect.box and rect.box.onpress then
                rect.box.onpress(widget, rect.box, rect.x, rect.y, category, value)
                if system.killEvents and KEY_ENTER_FIRST then
                    system.killEvents(KEY_ENTER_FIRST)
                end
                return true
            end
        end
    end

    if value == KEY_DOWN_BREAK and dashboard.selectedBoxIndex then
        dashboard.selectedBoxIndex = nil
        lcd.invalidate(widget)
        return true
    end

    if category == EVT_TOUCH and value == TOUCH_END and lcd.hasFocus() and x and y then
        for index, rect in ipairs(dashboard.boxRects or {}) do
            if x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h then
                if rect.box and rect.box.onpress then
                    dashboard.selectedBoxIndex = index
                    lcd.invalidate(widget)
                    rect.box.onpress(widget, rect.box, x, y, category, value)
                    if system.killEvents then
                        system.killEvents(TOUCH_START)
                    end
                    return true
                end
            end
        end
    end

    return false
end

return dashboard
