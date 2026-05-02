--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local math_abs = math.abs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local tonumber = tonumber
local tostring = tostring
local ipairs = ipairs
local pairs = pairs
local pcall = pcall
local os_date = os.date
local os_time = os.time
local string_format = string.format

local PEN_SOLID = rawget(_G, "SOLID")
local PEN_DOTTED = rawget(_G, "DOTTED")
local COLOR_BLACK_SAFE = rawget(_G, "COLOR_BLACK") or lcd.RGB(0, 0, 0)
local COLOR_WHITE_SAFE = rawget(_G, "COLOR_WHITE") or lcd.RGB(255, 255, 255)
local COLOR_GREY_SAFE = rawget(_G, "COLOR_GREY") or lcd.RGB(160, 160, 160)
local HEADER_NAV_HEIGHT_REDUCTION = 4
local HEADER_NAV_Y_SHIFT = 6
local NOOP_PAINT = function() end

local SUPPORTED_RADIOS = {
    ["784x406"] = {
        buttonWidth = 120,
        buttonHeight = 120,
        buttonPadding = 10,
        buttonWidthSmall = 105,
        buttonHeightSmall = 110,
        buttonPaddingSmall = 6,
        buttonsPerRow = 6,
        buttonsPerRowSmall = 7,
        linePaddingTop = 8,
        menuButtonWidth = 100,
        navbuttonHeight = 40,
        logGraphHeightOffset = -15,
        logGraphMenuOffset = 70,
        logGraphWidthPercentage = 0.79,
        logKeyFont = FONT_S,
        logKeyFontSmall = FONT_XS,
        logShowAvg = true,
        logSliderPaddingLeft = 42
    },
    ["472x288"] = {
        buttonWidth = 110,
        buttonHeight = 110,
        buttonPadding = 8,
        buttonWidthSmall = 89,
        buttonHeightSmall = 95,
        buttonPaddingSmall = 5,
        buttonsPerRow = 4,
        buttonsPerRowSmall = 5,
        linePaddingTop = 6,
        menuButtonWidth = 60,
        navbuttonHeight = 30,
        logGraphHeightOffset = 10,
        logGraphMenuOffset = 55,
        logGraphWidthPercentage = 0.72,
        logKeyFont = FONT_XS,
        logKeyFontSmall = FONT_XXS,
        logShowAvg = false,
        logSliderPaddingLeft = 30
    },
    ["632x314"] = {
        buttonWidth = 118,
        buttonHeight = 120,
        buttonPadding = 7,
        buttonWidthSmall = 97,
        buttonHeightSmall = 115,
        buttonPaddingSmall = 8,
        buttonsPerRow = 5,
        buttonsPerRowSmall = 6,
        linePaddingTop = 6,
        menuButtonWidth = 80,
        navbuttonHeight = 35,
        logGraphHeightOffset = 0,
        logGraphMenuOffset = 60,
        logGraphWidthPercentage = 0.76,
        logKeyFont = FONT_XXS,
        logKeyFontSmall = FONT_XXS,
        logShowAvg = false,
        logSliderPaddingLeft = 30
    }
}

local ZOOM_LEVEL_TO_TIME = {[1] = 600, [2] = 300, [3] = 120, [4] = 60, [5] = 30}
local ZOOM_LEVEL_TO_DECIMATION = {[1] = 5, [2] = 4, [3] = 2, [4] = 1, [5] = 1}
local LOAD_READ_CHUNK = 120
local LOG_PADDING = 5
local SAMPLE_RATE = 1

local function newState()
    return {
        entries = {},
        lastListSelection = nil,
        selectedFile = nil,
        rawHeader = {},
        logData = {},
        logLineCount = 0,
        loadJob = nil,
        loadError = nil,
        processedLogData = false,
        sliderPosition = 1,
        sliderPositionOld = 1,
        zoomLevel = 1,
        zoomCount = 1
    }
end

local function newPaintCache()
    return {
        points = {},
        stepSize = 0,
        position = 1,
        graphCount = 0,
        laneHeight = 0,
        currentLane = 0,
        decimationFactor = 1,
        needsUpdate = true
    }
end

local tool = {
    page = "logs",
    exitRequested = false,
    formFields = {},
    icons = {},
    paintCache = newPaintCache(),
    state = newState(),
    progressDialog = nil
}

local function openProgressDialog(title, message)
    if form.openWaitDialog and ofs3.utils.ethosVersionAtLeast({26, 1, 0}) then
        return form.openWaitDialog({title = title, message = message, progress = true})
    end
    return form.openProgressDialog(title, message)
end

local function closeProgressDialog()
    if tool.progressDialog then
        tool.progressDialog:close()
        tool.progressDialog = nil
    end
end

local function buildColorTable()
    if lcd.darkMode() then
        return {
            voltage = lcd.RGB(220, 92, 92),
            current = lcd.RGB(255, 168, 58),
            rpm = lcd.RGB(102, 214, 129),
            temp_esc = lcd.RGB(90, 180, 255),
            throttle_percent = lcd.RGB(248, 215, 90)
        }
    end

    return {
        voltage = lcd.RGB(200, 0, 0),
        current = lcd.RGB(220, 100, 0),
        rpm = lcd.RGB(0, 140, 0),
        temp_esc = lcd.RGB(0, 80, 200),
        throttle_percent = lcd.RGB(180, 160, 0)
    }
end

local function buildLogColumns()
    local colors = buildColorTable()

    return {
        {name = "voltage", keyindex = 1, keyname = "@i18n(widgets.dashboard.logs_voltage)@", keyunit = "V", keyminmax = 1, color = colors.voltage, pen = PEN_SOLID, graph = true},
        {name = "current", keyindex = 2, keyname = "@i18n(widgets.dashboard.logs_current)@", keyunit = "A", keyminmax = 1, color = colors.current, pen = PEN_SOLID, graph = true},
        {name = "rpm", keyindex = 3, keyname = "@i18n(widgets.dashboard.logs_headspeed)@", keyunit = "rpm", keyminmax = 1, keyfloor = true, color = colors.rpm, pen = PEN_SOLID, graph = true},
        {name = "temp_esc", keyindex = 4, keyname = "@i18n(widgets.dashboard.logs_esc_temp)@", keyunit = "C", keyminmax = 1, color = colors.temp_esc, pen = PEN_SOLID, graph = true},
        {name = "throttle_percent", keyindex = 5, keyname = "@i18n(widgets.dashboard.logs_throttle)@", keyunit = "%", keyminmax = 1, color = colors.throttle_percent, pen = PEN_SOLID, graph = true}
    }
end

local function invalidate(widget)
    if not lcd.invalidate then
        return
    end

    if widget ~= nil then
        lcd.invalidate(widget)
    else
        lcd.invalidate()
    end
end

local function clearForm()
    tool.formFields = {}
    if form and form.clear then
        form.clear()
    end
end

local function requestExit()
    tool.exitRequested = true
end

local function flushExit()
    if not tool.exitRequested then
        return false
    end

    tool.exitRequested = false
    if system.exit then
        system.exit()
    end
    return true
end

local function matchesKey(value, keyName)
    local keyValue = _G[keyName]
    return keyValue ~= nil and value == keyValue
end

local function isExitKey(value)
    return matchesKey(value, "KEY_RTN_BREAK")
        or matchesKey(value, "KEY_RTN_LONG")
        or matchesKey(value, "KEY_SYS_BREAK")
        or matchesKey(value, "KEY_SYS_LONG")
        or matchesKey(value, "KEY_SYSTEM_BREAK")
        or matchesKey(value, "KEY_SYSTEM_LONG")
        or matchesKey(value, "KEY_MODEL_BREAK")
        or matchesKey(value, "KEY_MODEL_LONG")
        or matchesKey(value, "KEY_DOWN_BREAK")
end

local function parseResolution(key)
    local width, height = tostring(key or ""):match("^(%d+)x(%d+)$")
    return tonumber(width), tonumber(height)
end

local function getClosestSupportedResolution(targetW, targetH)
    local bestKey
    local bestDistance

    for key in pairs(SUPPORTED_RADIOS) do
        local width, height = parseResolution(key)
        local distance = math_abs((width or 0) - targetW) + math_abs((height or 0) - targetH)
        if bestDistance == nil or distance < bestDistance then
            bestKey = key
            bestDistance = distance
        end
    end

    return bestKey
end

local function getRadio()
    local width, height = lcd.getWindowSize()
    local resolution = width .. "x" .. height
    local key = SUPPORTED_RADIOS[resolution] and resolution or getClosestSupportedResolution(width, height)
    return SUPPORTED_RADIOS[key] or SUPPORTED_RADIOS["472x288"], width, height
end

local function getIconSize()
    local prefs = ofs3.preferences and ofs3.preferences.general or nil
    return tonumber(prefs and prefs.iconsize) or 2
end

local function getButtonLayout()
    local radio, width = getRadio()
    local icons = getIconSize()

    if icons == 0 then
        return {
            padding = radio.buttonPaddingSmall,
            buttonW = math_floor((width - radio.buttonPaddingSmall) / radio.buttonsPerRow - radio.buttonPaddingSmall),
            buttonH = radio.navbuttonHeight,
            perRow = radio.buttonsPerRow
        }
    end

    if icons == 1 then
        return {
            padding = radio.buttonPaddingSmall,
            buttonW = radio.buttonWidthSmall,
            buttonH = radio.buttonHeightSmall,
            perRow = radio.buttonsPerRowSmall
        }
    end

    return {
        padding = radio.buttonPadding,
        buttonW = radio.buttonWidth,
        buttonH = radio.buttonHeight,
        perRow = radio.buttonsPerRow
    }
end

local function getGraphPos()
    local radio = getRadio()
    local width, height

    if system and system.getVersion then
        local version = system.getVersion()
        width = tonumber(version and version.lcdWidth) or nil
        height = tonumber(version and version.lcdHeight) or nil
    end

    if not width or not height then
        local fallbackRadio, fallbackWidth, fallbackHeight = getRadio()
        radio = fallbackRadio
        width = fallbackWidth
        height = fallbackHeight
    end

    return {
        menu_offset = radio.logGraphMenuOffset,
        height_offset = radio.logGraphHeightOffset or 0,
        x_start = 0,
        y_start = radio.logGraphMenuOffset,
        width = math_floor(width * radio.logGraphWidthPercentage),
        key_width = width - math_floor(width * radio.logGraphWidthPercentage),
        height = height - radio.logGraphMenuOffset - radio.logGraphMenuOffset - 40 + (radio.logGraphHeightOffset or 0),
        slider_y = height - (radio.logGraphMenuOffset + 30) + (radio.logGraphHeightOffset or 0),
        lcdWidth = width,
        lcdHeight = height
    }
end

local function getHeaderNavButtonHeight()
    local radio = getRadio()
    local base = (radio and radio.navbuttonHeight) or 0
    if base <= 0 then
        return base
    end
    return math_max(20, base - HEADER_NAV_HEIGHT_REDUCTION)
end

local function getHeaderNavButtonY(baseY)
    local y = tonumber(baseY) or 0
    return math_max(0, y - HEADER_NAV_Y_SHIFT)
end

local function getHeaderTitleY(baseY)
    return getHeaderNavButtonY(baseY)
end

local function getHeaderMetrics()
    local radio, width = getRadio()
    local padding = 5
    local buttonW = radio.menuButtonWidth or 100
    local buttonH = getHeaderNavButtonHeight()
    local navX = width - 5
    local reserved = buttonW + padding
    local titleRightEdge = navX - reserved
    local titleWidth = math_max(40, titleRightEdge - 8)

    return {
        windowWidth = width,
        buttonW = buttonW,
        buttonH = buttonH,
        titleWidth = titleWidth,
        padding = padding
    }
end

local function loadIconAsset(path)
    if not lcd or not path then
        return nil
    end

    local candidates = {
        path,
        "SCRIPTS:/" .. ofs3.config.baseDir .. "/" .. path
    }

    for _, candidate in ipairs(candidates) do
        if lcd.loadMask then
            local ok, loaded = pcall(lcd.loadMask, candidate)
            if ok and loaded then
                return loaded
            end
        end

        if lcd.loadBitmap then
            local ok, loaded = pcall(lcd.loadBitmap, candidate)
            if ok and loaded then
                return loaded
            end
        end
    end

    return nil
end

local function ensureIcons()
    if tool.icons.folder == nil then
        tool.icons.folder = loadIconAsset("widgets/dashboard/gfx/folder.png") or false
    end

    if tool.icons.logs == nil then
        tool.icons.logs = loadIconAsset("widgets/dashboard/gfx/logs.png") or false
    end
end

local function addHeaderRow(title, menuHandler, menuIcon)
    local radio = getRadio()
    local metrics = getHeaderMetrics()
    local line = form.addLine("")

    tool.formFields.headerLine = line
    tool.formFields.headerTitle = form.addStaticText(line, {
        x = 0,
        y = getHeaderTitleY(radio.linePaddingTop or 0),
        w = metrics.titleWidth,
        h = radio.navbuttonHeight
    }, title)

    tool.formFields.menu = form.addButton(nil, {
        x = metrics.windowWidth - metrics.buttonW - 10,
        y = getHeaderNavButtonY(radio.linePaddingTop or 0),
        w = metrics.buttonW,
        h = metrics.buttonH
    }, {
        text = "Menu",
        icon = menuIcon,
        options = FONT_S,
        paint = NOOP_PAINT,
        press = menuHandler
    })
end

local function closeOpenJobHandle()
    local job = tool.state.loadJob
    if job and job.handle then
        pcall(function()
            job.handle:close()
        end)
        job.handle = nil
    end
end

local function resetViewState()
    closeProgressDialog()
    closeOpenJobHandle()
    tool.state.selectedFile = nil
    tool.state.rawHeader = {}
    tool.state.logData = {}
    tool.state.logLineCount = 0
    tool.state.loadJob = nil
    tool.state.loadError = nil
    tool.state.processedLogData = false
    tool.state.sliderPosition = 1
    tool.state.sliderPositionOld = 1
    tool.state.zoomLevel = 1
    tool.state.zoomCount = 1
    tool.paintCache = newPaintCache()
end

local function refreshEntries()
    tool.state.entries = ofs3.logs.getRecentEntries() or {}
end

local function extractHourMinute(filename)
    local hour, minute = tostring(filename or ""):match(".-%d%d%d%d%-%d%d%-%d%d_(%d%d)%-(%d%d)%-%d%d")
    if hour and minute then
        return hour .. ":" .. minute
    end

    return tostring(filename or "@i18n(widgets.dashboard.logs_default_name)@")
end

local function extractShortTimestamp(filename)
    local date, time = tostring(filename or ""):match(".-(%d%d%d%d%-%d%d%-%d%d)_(%d%d%-%d%d%-%d%d)")
    if date and time then
        return date:gsub("%-", "/") .. " " .. time:gsub("%-", ":")
    end

    return tostring(filename or "@i18n(widgets.dashboard.logs_default_name)@")
end

local function formatDate(isoDate)
    local year, month, day = tostring(isoDate or ""):match("^(%d+)%-(%d+)%-(%d+)$")
    if year and month and day then
        return os_date("%d %B %Y", os_time({year = tonumber(year), month = tonumber(month), day = tonumber(day)}))
    end

    return isoDate or "@i18n(widgets.dashboard.logs_unknown_date)@"
end

local function groupEntries(entries)
    local grouped = {}
    local dates = {}

    for _, entry in ipairs(entries or {}) do
        local filename = entry and entry.name or entry
        local datePart = tostring(filename or ""):match("(%d%d%d%d%-%d%d%-%d%d)_")
        if datePart then
            if not grouped[datePart] then
                grouped[datePart] = {}
                dates[#dates + 1] = datePart
            end
            grouped[datePart][#grouped[datePart] + 1] = entry
        end
    end

    table.sort(dates, function(a, b)
        return a > b
    end)

    local result = {}
    for _, datePart in ipairs(dates) do
        result[#result + 1] = {
            date = datePart,
            label = formatDate(datePart),
            entries = grouped[datePart]
        }
    end

    return result
end

local function splitCsvLine(line)
    local fields = {}
    line = tostring(line or "")
    for part in (line .. ","):gmatch("([^,]*),") do
        fields[#fields + 1] = part:match("^%s*(.-)%s*$")
    end
    return fields
end

local function padTable(values, padCount)
    if #values == 0 then
        return values
    end

    local padded = {}
    for index = 1, padCount do
        padded[#padded + 1] = values[1]
    end
    for _, value in ipairs(values) do
        padded[#padded + 1] = value
    end
    for index = 1, padCount do
        padded[#padded + 1] = values[#values]
    end

    return padded
end

local function calculateStats(values)
    local minimum = math.huge
    local maximum = -math.huge
    local sum = 0
    local count = 0

    for _, value in ipairs(values) do
        if type(value) == "number" then
            minimum = math_min(minimum, value)
            maximum = math_max(maximum, value)
            sum = sum + value
            count = count + 1
        end
    end

    if count == 0 then
        return 0, 0, 0
    end

    return minimum, maximum, sum / count
end

local function calculateZoomSteps(logLineCount)
    local logDurationSec = math_max(0, tonumber(logLineCount) or 0) / SAMPLE_RATE

    for level = 5, 1, -1 do
        local desiredTime = ZOOM_LEVEL_TO_TIME[level]
        if logDurationSec >= desiredTime * 1.5 then
            return level
        end
    end

    return 1
end

local function queueLogLoad(filename)
    closeProgressDialog()
    tool.progressDialog = openProgressDialog("@i18n(widgets.dashboard.logs_loading)@", extractShortTimestamp(filename))
    tool.progressDialog:closeAllowed(false)
    tool.progressDialog:value(0)

    tool.state.loadJob = {
        filename = filename,
        phase = "open"
    }
    tool.state.loadError = nil
    tool.state.processedLogData = false
end

local function setZoomButtonsEnabled()
    local minus = tool.formFields.zoomOut
    local plus = tool.formFields.zoomIn

    if not minus or not plus or not minus.enable or not plus.enable then
        return
    end

    if tool.state.zoomCount <= 1 then
        minus:enable(false)
        plus:enable(false)
        return
    end

    minus:enable(tool.state.zoomLevel > 1)
    plus:enable(tool.state.zoomLevel < tool.state.zoomCount)
end

local function processLoadJob()
    local job = tool.state.loadJob
    if not job then
        return false
    end

    if job.phase == "open" then
        local path = ofs3.logs.getDirectory() .. "/" .. tostring(job.filename)
        job.handle = io.open(path, "r")
        if not job.handle then
            closeProgressDialog()
            tool.state.loadError = "@i18n(widgets.dashboard.logs_open_failed)@"
            tool.state.loadJob = nil
            return true
        end

        local headerLine = job.handle:read("*l")
        local header = splitCsvLine(headerLine)
        if #header == 0 then
            pcall(function()
                job.handle:close()
            end)
            job.handle = nil
            closeProgressDialog()
            tool.state.loadError = "@i18n(widgets.dashboard.logs_invalid_header)@"
            tool.state.loadJob = nil
            return true
        end

        local columnIndex = {}
        for index, name in ipairs(header) do
            columnIndex[name] = index
        end

        local parsed = {}
        for _, column in ipairs(buildLogColumns()) do
            local csvIndex = columnIndex[column.name]
            if csvIndex then
                parsed[#parsed + 1] = {
                    name = column.name,
                    keyindex = column.keyindex,
                    keyname = column.keyname,
                    keyunit = column.keyunit,
                    keyminmax = column.keyminmax,
                    keyfloor = column.keyfloor,
                    color = column.color,
                    pen = column.pen,
                    graph = column.graph,
                    csvIndex = csvIndex,
                    data = {}
                }
            end
        end

        if #parsed == 0 then
            pcall(function()
                job.handle:close()
            end)
            job.handle = nil
            closeProgressDialog()
            tool.state.loadError = "@i18n(widgets.dashboard.logs_invalid_header)@"
            tool.state.loadJob = nil
            return true
        end

        if tool.progressDialog then tool.progressDialog:value(5) end
        job.header = header
        job.parsed = parsed
        job.phase = "read"
        job.readCount = 0
        return true
    end

    if job.phase == "read" then
        local processed = 0

        while processed < LOAD_READ_CHUNK do
            local line = job.handle:read("*l")
            if line == nil then
                pcall(function()
                    job.handle:close()
                end)
                job.handle = nil
                job.phase = "finalize"
                job.finalizeIndex = 1
                if tool.progressDialog then tool.progressDialog:value(85) end
                return true
            end

            local parts = splitCsvLine(line)
            for _, column in ipairs(job.parsed) do
                column.data[#column.data + 1] = tonumber(parts[column.csvIndex]) or 0
            end

            job.readCount = (job.readCount or 0) + 1
            processed = processed + 1
        end

        -- progress 5→85% based on lines read; 900 lines ≈ 15 min max flight
        if tool.progressDialog then
            tool.progressDialog:value(math_min(85, 5 + math_floor((job.readCount / 900) * 80)))
        end
        return true
    end

    if job.phase == "finalize" then
        local column = job.parsed[job.finalizeIndex]
        if column then
            -- progress 85→97% across 5 columns (each step +3%)
            if tool.progressDialog then
                tool.progressDialog:value(85 + math_floor(((job.finalizeIndex - 1) / 5) * 15))
            end
            column.data = padTable(column.data, LOG_PADDING)
            column.minimum, column.maximum, column.average = calculateStats(column.data)
            job.finalizeIndex = job.finalizeIndex + 1
            return true
        end

        tool.state.rawHeader = job.header or {}
        tool.state.logData = job.parsed or {}
        tool.state.logLineCount = #((job.parsed and job.parsed[1] and job.parsed[1].data) or {})
        tool.state.loadJob = nil
        tool.state.processedLogData = true
        tool.state.sliderPosition = 1
        tool.state.sliderPositionOld = 1
        tool.state.zoomCount = calculateZoomSteps(tool.state.logLineCount)
        tool.state.zoomLevel = math_min(tool.state.zoomLevel or 1, tool.state.zoomCount)
        tool.paintCache = newPaintCache()
        setZoomButtonsEnabled()
        if tool.progressDialog then tool.progressDialog:value(100) end
        closeProgressDialog()
        return true
    end

    return false
end

local openViewPage

local function openLogsPage()
    clearForm()
    tool.page = "logs"
    resetViewState()
    refreshEntries()
    ensureIcons()

    local layout = getButtonLayout()
    local selectedButton = nil

    addHeaderRow("Logs", requestExit, nil)

    if #tool.state.entries == 0 then
        local _, width, height = getRadio()
        local msg = "@i18n(widgets.dashboard.logs_empty_message)@"
        local tw, th = lcd.getTextSize(msg)
        local x = math_floor(width / 2 - tw / 2)
        local y = math_floor(height / 2 - th / 2)
        form.addStaticText(nil, {x = x, y = y, w = tw, h = layout.buttonH}, msg)
        invalidate()
        return
    end

    local buttonIndex = 0
    for _, section in ipairs(groupEntries(tool.state.entries)) do
        form.addLine(section.label)

        local column = 0
        local y = 0

        for _, entry in ipairs(section.entries) do
            buttonIndex = buttonIndex + 1
            if column == 0 then
                y = form.height() + layout.padding
            end

            local x = (layout.buttonW + layout.padding) * column
            local button = form.addButton(nil, {x = x, y = y, w = layout.buttonW, h = layout.buttonH}, {
                text = extractHourMinute(entry.name),
                icon = tool.icons.logs or nil,
                options = FONT_S,
                press = function()
                    tool.state.lastListSelection = entry.name
                    openViewPage(entry.name)
                end
            })

            if tool.state.lastListSelection == entry.name and button and button.focus then
                selectedButton = button
            end

            column = (column + 1) % layout.perRow
        end
    end

    if selectedButton then
        selectedButton:focus()
    end

    invalidate()
end

openViewPage = function(filename)
    resetViewState()
    clearForm()
    ensureIcons()

    tool.page = "view"
    tool.state.selectedFile = filename
    tool.state.lastListSelection = filename
    queueLogLoad(filename)

    addHeaderRow("Logs / " .. extractShortTimestamp(filename), openLogsPage, nil)

    local graphPos = getGraphPos()
    local zoomButtonWidth = math_max(48, math_floor(graphPos.key_width / 2) - 20)

    tool.formFields.slider = form.addSliderField(nil, {
        x = graphPos.x_start,
        y = graphPos.slider_y,
        w = graphPos.width - 10,
        h = 40
    }, 1, 100, function()
        return tool.state.sliderPosition
    end, function(newValue)
        tool.state.sliderPosition = math_max(1, math_min(100, math_floor(tonumber(newValue) or 1)))
        tool.paintCache.needsUpdate = true
        invalidate()
    end)

    if tool.formFields.slider and tool.formFields.slider.step then
        tool.formFields.slider:step(1)
    end

    tool.formFields.zoomOut = form.addButton(nil, {
        x = graphPos.width,
        y = graphPos.slider_y,
        w = zoomButtonWidth,
        h = 40
    }, {
        text = "-",
        options = FONT_STD,
        press = function()
            if tool.state.zoomLevel > 1 then
                tool.state.zoomLevel = tool.state.zoomLevel - 1
                tool.paintCache.needsUpdate = true
                setZoomButtonsEnabled()
                invalidate()
            end
        end
    })

    tool.formFields.zoomIn = form.addButton(nil, {
        x = graphPos.width + zoomButtonWidth + 10,
        y = graphPos.slider_y,
        w = zoomButtonWidth,
        h = 40
    }, {
        text = "+",
        options = FONT_STD,
        press = function()
            if tool.state.zoomLevel < tool.state.zoomCount then
                tool.state.zoomLevel = tool.state.zoomLevel + 1
                tool.paintCache.needsUpdate = true
                setZoomButtonsEnabled()
                invalidate()
            end
        end
    })

    setZoomButtonsEnabled()
    invalidate()
end

local function secondsToSamples(seconds)
    return math_floor(seconds * SAMPLE_RATE)
end

local function map(value, inMin, inMax, outMin, outMax)
    if inMax == inMin then
        return outMin
    end

    return (value - inMin) * (outMax - outMin) / (inMax - inMin) + outMin
end

local function paginateTable(data, stepSize, position, decimationFactor)
    decimationFactor = decimationFactor or 1

    local startIndex = math_max(1, position)
    local endIndex = math_min(startIndex + stepSize - 1, #data)
    local page = {}

    for index = startIndex, endIndex, decimationFactor do
        page[#page + 1] = data[index]
    end

    return page
end

local function updatePaintCache()
    if not tool.state.processedLogData then
        return
    end

    local graphPos = getGraphPos()
    local logDurationSec = math_floor(tool.state.logLineCount / SAMPLE_RATE)
    local desiredWinSec = ZOOM_LEVEL_TO_TIME[tool.state.zoomLevel] or ZOOM_LEVEL_TO_TIME[1]
    local winSec = math_min(desiredWinSec, logDurationSec)

    tool.paintCache.stepSize = math_max(1, secondsToSamples(winSec))

    local maxPosition = math_max(1, tool.state.logLineCount - tool.paintCache.stepSize + 1)
    tool.paintCache.position = math_floor(map(tool.state.sliderPosition, 1, 100, 1, maxPosition))
    if tool.paintCache.position < 1 then
        tool.paintCache.position = 1
    end

    tool.paintCache.graphCount = 0
    for _, column in ipairs(tool.state.logData) do
        if column.graph then
            tool.paintCache.graphCount = tool.paintCache.graphCount + 1
        end
    end

    tool.paintCache.laneHeight = graphPos.height / math_max(1, tool.paintCache.graphCount)
    tool.paintCache.currentLane = 0
    tool.paintCache.decimationFactor = ZOOM_LEVEL_TO_DECIMATION[tool.state.zoomLevel] or 1
    tool.paintCache.points = {}

    if tool.state.zoomCount == 1 then
        tool.paintCache.decimationFactor = 1
    end

    for _, column in ipairs(tool.state.logData) do
        if column.graph then
            tool.paintCache.currentLane = tool.paintCache.currentLane + 1
            tool.paintCache.points[tool.paintCache.currentLane] = {
                points = paginateTable(column.data, tool.paintCache.stepSize, tool.paintCache.position, tool.paintCache.decimationFactor),
                color = column.color,
                pen = column.pen,
                minimum = column.minimum,
                maximum = column.maximum,
                keyname = column.keyname,
                keyunit = column.keyunit,
                keyminmax = column.keyminmax,
                keyfloor = column.keyfloor,
                name = column.name,
                keyindex = column.keyindex
            }
        end
    end

    tool.paintCache.needsUpdate = false
end

local function formatTime(seconds)
    local minutes = math_floor(seconds / 60)
    local secondsRemainder = seconds % 60
    return string_format("%02d:%02d", minutes, secondsRemainder)
end

local function calculateSeconds(totalSeconds, sliderValue)
    local clamped = math_max(1, math_min(100, sliderValue))
    return math_floor(((clamped - 1) / 100) * totalSeconds)
end

local function getValueAtPercentage(array, percentage)
    local clamped = math_max(1, math_min(100, percentage))
    local count = #array
    if count == 0 then
        return 0
    end

    local index = math_max(1, math_min(count, math_floor((clamped / 100) * count + 0.5)))
    return array[index] or 0
end

local function formatDisplayNumber(value, floorValue)
    local number = tonumber(value) or 0
    if floorValue then
        return tostring(math_floor(number))
    end

    if math_abs(number) >= 100 then
        return string_format("%.0f", number)
    end

    if math_abs(number) >= 10 then
        return string_format("%.1f", number)
    end

    return string_format("%.2f", number)
end

local function drawGraph(points, color, pen, xStart, yStart, width, height, minimum, maximum)
    if #points < 2 then
        return
    end

    local padding = math_max(5, math_floor(height * 0.1))
    yStart = yStart + (padding / 2)
    height = height - padding

    if maximum == minimum then
        maximum = maximum + 1
        minimum = minimum - 1
    end

    lcd.color(color or COLOR_GREY_SAFE)
    if pen ~= nil and lcd.pen then
        lcd.pen(pen)
    elseif lcd.pen and PEN_DOTTED ~= nil then
        lcd.pen(PEN_DOTTED)
    end

    local xScale = width / math_max(1, (#points - 1))
    local yScale = height / (maximum - minimum)

    for index = 1, #points - 1 do
        local x1 = xStart + (index - 1) * xScale
        local y1 = yStart + height - (points[index] - minimum) * yScale
        local x2 = xStart + index * xScale
        local y2 = yStart + height - (points[index + 1] - minimum) * yScale
        lcd.drawLine(x1, y1, x2, y2)
    end
end

local function drawKey(name, keyunit, keyminmax, keyfloor, color, minimum, maximum, laneY)
    local radio = getRadio()
    local graphPos = getGraphPos()
    local boxPadding = 3
    local width = graphPos.lcdWidth - graphPos.width - 10

    lcd.font(radio.logKeyFont)
    local _, textH = lcd.getTextSize(name)
    local boxHeight = textH + boxPadding

    local x = graphPos.width
    local y = laneY

    local minText = formatDisplayNumber(minimum, keyfloor)
    local maxText = formatDisplayNumber(maximum, keyfloor)

    lcd.color(color)
    lcd.drawFilledRectangle(x, y, width, boxHeight)

    lcd.color(COLOR_BLACK_SAFE)
    local textY = y + (boxHeight / 2 - textH / 2)
    lcd.drawText(x + 5, textY, name, LEFT)

    lcd.font(radio.logKeyFontSmall)
    lcd.color(lcd.darkMode() and COLOR_WHITE_SAFE or COLOR_BLACK_SAFE)

    if keyunit == "rpm" and ((minimum >= 10000) or (maximum >= 10000)) then
        minText = string_format("%.1fK", minimum / 10000)
        maxText = string_format("%.1fK", maximum / 10000)
    end

    local minimumLabel = keyminmax == 1 and ("↓ " .. minText .. keyunit) or ""
    local maximumLabel = "↑ " .. maxText .. keyunit
    local minmaxY = y + boxHeight + 2

    lcd.drawText(x + 5, minmaxY, minimumLabel, LEFT)

    lcd.drawText(x + width - boxPadding, minmaxY, maximumLabel, RIGHT)

    if radio.logShowAvg then
        local averageLabel = "Ø " .. formatDisplayNumber((minimum + maximum) / 2, keyfloor) .. keyunit
        lcd.drawText(x + 5, minmaxY + textH - 2, averageLabel, LEFT)
    end
end

local function drawCurrentIndex(points, position, totalPoints, keyunit, keyfloor, color, laneY, laneNumber)
    local radio = getRadio()
    local graphPos = getGraphPos()
    local sliderPadding = radio.logSliderPaddingLeft
    local width = graphPos.width - sliderPadding

    local linePos = map(position, 1, 100, 1, width - 10) + sliderPadding
    if linePos < 1 then
        linePos = 0
    end

    local value = getValueAtPercentage(points, position)
    local valueLabel = formatDisplayNumber(value, keyfloor) .. keyunit
    local boxPadding = 3

    lcd.font(radio.logKeyFont)
    local textW, textH = lcd.getTextSize(valueLabel)
    local boxHeight = textH + boxPadding
    local boxY = laneY
    local textY = boxY + (boxHeight / 2 - textH / 2)

    local textAlign
    local textX
    local boxX
    if position > 50 then
        textAlign = RIGHT
        textX = linePos - (boxPadding * 2)
        boxX = linePos - boxPadding - textW - (boxPadding * 2)
    else
        textAlign = LEFT
        textX = linePos + (boxPadding * 2)
        boxX = linePos + boxPadding
    end

    lcd.color(color)
    lcd.drawFilledRectangle(boxX, boxY, textW + (boxPadding * 2), boxHeight)

    lcd.color(lcd.darkMode() and COLOR_BLACK_SAFE or COLOR_WHITE_SAFE)
    lcd.drawText(textX, textY, valueLabel, textAlign)

    if laneNumber == 1 then
        local currentSeconds = calculateSeconds(totalPoints, position)
        local timeLabel = formatTime(math_floor(currentSeconds))

        local logDurationSec = math_floor(tool.state.logLineCount / SAMPLE_RATE)
        local desiredWinSec = ZOOM_LEVEL_TO_TIME[tool.state.zoomLevel] or ZOOM_LEVEL_TO_TIME[1]
        local windowSec = math_min(desiredWinSec, logDurationSec)
        local windowLabel
        if windowSec < 60 then
            windowLabel = string_format("%ds", windowSec)
        else
            windowLabel = string_format("%d:%02d", math_floor(windowSec / 60), windowSec % 60)
        end

        local fullLabel = string_format("%s [+%s]", timeLabel, windowLabel)
        local timeY = graphPos.height + graphPos.menu_offset - 10

        lcd.font(radio.logKeyFont)
        lcd.color(COLOR_WHITE_SAFE)
        lcd.drawText(textX, timeY, fullLabel, textAlign)

        lcd.color(lcd.darkMode() and COLOR_WHITE_SAFE or COLOR_BLACK_SAFE)
        lcd.drawLine(linePos, graphPos.menu_offset - 5, linePos, graphPos.menu_offset + graphPos.height)

        lcd.color(lcd.darkMode() and lcd.RGB(40, 40, 40) or lcd.RGB(240, 240, 240))
        local zoomX = graphPos.lcdWidth - 25
        local zoomY = graphPos.slider_y
        local zoomW = 20
        local zoomH = 40
        local zoomLineH = zoomH / math_max(1, tool.state.zoomCount)
        local lineOffsetY = (tool.state.zoomCount - tool.state.zoomLevel) * zoomLineH

        lcd.drawFilledRectangle(zoomX, zoomY, zoomW, zoomH)
        lcd.color(tool.state.zoomCount > 1 and (lcd.darkMode() and COLOR_WHITE_SAFE or COLOR_BLACK_SAFE) or COLOR_GREY_SAFE)
        lcd.drawFilledRectangle(zoomX, zoomY + lineOffsetY, zoomW, zoomLineH)
    end
end

local function paintLoadingMessage(message, detail)
    local _, width, height = getRadio()

    lcd.color(lcd.darkMode() and lcd.RGB(22, 28, 34) or lcd.RGB(255, 255, 255))
    lcd.drawFilledRectangle(20, math_floor(height * 0.35), width - 40, 70)
    lcd.color(lcd.darkMode() and lcd.RGB(86, 96, 106) or lcd.RGB(196, 202, 208))
    lcd.drawRectangle(20, math_floor(height * 0.35), width - 40, 70, 1)

    lcd.font(FONT_STD)
    lcd.color(lcd.darkMode() and COLOR_WHITE_SAFE or COLOR_BLACK_SAFE)
    lcd.drawText(math_floor(width / 2), math_floor(height * 0.35) + 14, message, CENTERED)

    if detail then
        lcd.font(FONT_XXS)
        lcd.color(COLOR_GREY_SAFE)
        lcd.drawText(math_floor(width / 2), math_floor(height * 0.35) + 38, tostring(detail), CENTERED)
    end
end

local function paintView()
    if tool.state.loadJob then
        return
    end

    if tool.state.loadError then
        paintLoadingMessage("@i18n(widgets.dashboard.logs_load_failed)@", tool.state.loadError)
        return
    end

    if not tool.state.processedLogData then
        return
    end

    if tool.paintCache.needsUpdate or tool.state.sliderPosition ~= tool.state.sliderPositionOld then
        updatePaintCache()
        tool.state.sliderPositionOld = tool.state.sliderPosition
    end

    local graphPos = getGraphPos()
    local width = graphPos.width - 10
    local height = graphPos.height
    local xStart = graphPos.x_start
    local yStart = graphPos.y_start

    if tool.paintCache.points and #tool.paintCache.points > 0 then
        for laneNumber, laneData in ipairs(tool.paintCache.points) do
            local laneY = yStart + (laneNumber - 1) * tool.paintCache.laneHeight
            drawGraph(laneData.points, laneData.color, laneData.pen, xStart, laneY, width, tool.paintCache.laneHeight, laneData.minimum, laneData.maximum)
            drawKey(laneData.keyname, laneData.keyunit, laneData.keyminmax, laneData.keyfloor, laneData.color, laneData.minimum, laneData.maximum, laneY)
            drawCurrentIndex(laneData.points, tool.state.sliderPosition, tool.state.logLineCount + LOG_PADDING, laneData.keyunit, laneData.keyfloor, laneData.color, laneY, laneNumber)
        end
    end
end

function tool.create()
    tool.exitRequested = false
    tool.state = newState()
    tool.icons = {}
    tool.paintCache = newPaintCache()
    openLogsPage()
    return {}
end

function tool.paint()
    if tool.page == "view" then
        paintView()
    end
end

function tool.wakeup(widget)
    if flushExit() then
        return true
    end

    if tool.page == "view" then
        if tool.state.loadJob then
            if processLoadJob() then
                invalidate(widget)
            end
        elseif tool.state.processedLogData and (tool.paintCache.needsUpdate or tool.state.sliderPosition ~= tool.state.sliderPositionOld) then
            updatePaintCache()
            tool.state.sliderPositionOld = tool.state.sliderPosition
            invalidate(widget)
        end
    end

    return false
end

function tool.event(widget, category, value)
    if category == EVT_CLOSE or isExitKey(value) then
        if tool.page == "view" then
            openLogsPage()
        else
            requestExit()
        end

        if value ~= nil and system.killEvents then
            system.killEvents(value)
        end

        invalidate(widget)
        return true
    end

    return false
end

function tool.close()
    tool.exitRequested = false
    closeProgressDialog()
    closeOpenJobHandle()
    clearForm()

    tool.page = "logs"
    tool.state = newState()
    tool.icons = {}
    tool.paintCache = newPaintCache()

    if ofs3.tools then
        ofs3.tools.logs = nil
    end

    ofs3.logs = nil

    return true
end

return tool
