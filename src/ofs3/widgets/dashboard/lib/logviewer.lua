--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local logviewer = {}

local GRAPH_COLUMNS = {
    {name = "voltage", keyname = "@i18n(widgets.dashboard.logs_voltage)@", keyunit = "V", colorDark = lcd.RGB(220, 92, 92), colorLight = lcd.RGB(190, 0, 0), graph = true},
    {name = "current", keyname = "@i18n(widgets.dashboard.logs_current)@", keyunit = "A", colorDark = lcd.RGB(255, 168, 58), colorLight = lcd.RGB(210, 112, 0), graph = true},
    {name = "rpm", keyname = "@i18n(widgets.dashboard.logs_headspeed)@", keyunit = "rpm", colorDark = lcd.RGB(102, 214, 129), colorLight = lcd.RGB(0, 136, 0), graph = true},
    {name = "temp_esc", keyname = "@i18n(widgets.dashboard.logs_esc_temp)@", keyunit = "C", colorDark = lcd.RGB(90, 180, 255), colorLight = lcd.RGB(0, 80, 200), graph = true},
    {name = "throttle_percent", keyname = "@i18n(widgets.dashboard.logs_throttle)@", keyunit = "%", colorDark = lcd.RGB(248, 215, 90), colorLight = lcd.RGB(180, 160, 0), graph = false}
}

local ZOOM_WINDOWS = {600, 300, 120, 60, 30}
local LOAD_READ_CHUNK = 120
local LOAD_PARSE_CHUNK = 80

local state = {
    active = false,
    mode = "list",
    entries = {},
    selectedListIndex = 1,
    listScroll = 0,
    selectedFile = nil,
    sliderPosition = 1,
    zoomLevel = 3,
    zoomCount = 5,
    rawHeader = {},
    logData = {},
    logLineCount = 0,
    graphPadding = 5,
    hitboxes = {},
    pressedTarget = nil,
    selectedViewControl = 1,
    loadJob = nil,
    loadError = nil
}

local VIEW_CONTROLS = {"back", "minus", "plus", "left", "right"}

local function matchesKey(value, keyName)
    local keyValue = _G[keyName]
    return keyValue ~= nil and value == keyValue
end

local function isTouchStart(category, value)
    return (category == EVT_TOUCH and value == TOUCH_START)
        or (category == 1 and value == 16640)
end

local function isTouchEnd(category, value)
    return (category == EVT_TOUCH and value == TOUCH_END)
        or (category == 1 and value == 16641)
end

local function isAnyTouch(category)
    return category == EVT_TOUCH or category == 1
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
end

local function isNextKey(value)
    return matchesKey(value, "KEY_DOWN_BREAK")
        or matchesKey(value, "KEY_ROTARY_RIGHT")
        or matchesKey(value, "ROTARY_RIGHT")
        or matchesKey(value, "KEY_PAGE_BREAK")
end

local function isPrevKey(value)
    return matchesKey(value, "KEY_UP_BREAK")
        or matchesKey(value, "ROTARY_LEFT")
        or matchesKey(value, "KEY_ROTARY_LEFT")
end

local function getTheme()
    if lcd.darkMode() then
        return {
            background = lcd.RGB(10, 14, 18),
            panel = lcd.RGB(22, 28, 34),
            panelAlt = lcd.RGB(17, 22, 27),
            button = lcd.RGB(36, 36, 39),
            buttonDisabled = lcd.RGB(24, 24, 27),
            text = lcd.RGB(245, 246, 247),
            muted = lcd.RGB(166, 174, 182),
            accent = lcd.RGB(231, 116, 58),
            accentSoft = lcd.RGB(72, 44, 30),
            border = lcd.RGB(86, 96, 106)
        }
    end

    return {
        background = lcd.RGB(246, 247, 249),
        panel = lcd.RGB(255, 255, 255),
        panelAlt = lcd.RGB(240, 242, 245),
        button = lcd.RGB(232, 234, 237),
        buttonDisabled = lcd.RGB(242, 244, 246),
        text = lcd.RGB(28, 34, 40),
        muted = lcd.RGB(108, 116, 124),
        accent = lcd.RGB(215, 98, 38),
        accentSoft = lcd.RGB(255, 226, 210),
        border = lcd.RGB(196, 202, 208)
    }
end

local function resetGraphState()
    state.selectedFile = nil
    state.rawHeader = {}
    state.logData = {}
    state.logLineCount = 0
    state.sliderPosition = 1
    state.zoomLevel = 3
    state.zoomCount = 5
    state.selectedViewControl = 1
    state.loadJob = nil
    state.loadError = nil
end

local function clearHitboxes()
    state.hitboxes = {
        list = {},
        view = {}
    }
    state.pressedTarget = nil
end

local function closeViewer()
    state.active = false
    state.mode = "list"
    clearHitboxes()
    resetGraphState()
end

local function returnToList()
    state.mode = "list"
    clearHitboxes()
    resetGraphState()
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
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
            minimum = math.min(minimum, value)
            maximum = math.max(maximum, value)
            sum = sum + value
            count = count + 1
        end
    end

    if count == 0 then
        return nil, nil, nil
    end

    return minimum, maximum, sum / count
end

local function extractShortTimestamp(filename)
    local date, time = tostring(filename or ""):match(".-(%d%d%d%d%-%d%d%-%d%d)_(%d%d%-%d%d%-%d%d)")
    if date and time then
        return date:gsub("%-", "/") .. " " .. time:gsub("%-", ":")
    end
    return filename or "@i18n(widgets.dashboard.logs_default_name)@"
end

local function extractTimeLabel(filename)
    local hour, minute = tostring(filename or ""):match(".-%d%d%d%d%-%d%d%-%d%d_(%d%d)%-(%d%d)%-%d%d")
    if hour and minute then
        return hour .. ":" .. minute
    end
    return "@i18n(widgets.dashboard.logs_default_name)@"
end

local function extractDateLabel(filename)
    local date = tostring(filename or ""):match("(%d%d%d%d%-%d%d%-%d%d)_")
    if not date then
        return "@i18n(widgets.dashboard.logs_unknown_date)@"
    end

    local year, month, day = date:match("^(%d+)%-(%d+)%-(%d+)$")
    if not year or not month or not day then
        return date
    end

    return os.date("%d %B %Y", os.time({year = tonumber(year), month = tonumber(month), day = tonumber(day)}))
end

local function extractCompactDateLabel(filename)
    local date = tostring(filename or ""):match("(%d%d%d%d%-%d%d%-%d%d)_")
    if not date then
        return "-- ---"
    end

    local year, month, day = date:match("^(%d+)%-(%d+)%-(%d+)$")
    if not year or not month or not day then
        return date
    end

    return os.date("%d %b", os.time({year = tonumber(year), month = tonumber(month), day = tonumber(day)}))
end

local function consumeTouchEvent(category, value)
    if not system.killEvents then
        return
    end

    if category == 1 then
        system.killEvents(value)
        if value == 16641 then
            system.killEvents(16640)
        end
        return
    end

    system.killEvents(value)
    if value == TOUCH_END then
        system.killEvents(TOUCH_START)
    end
end

local function refreshEntries()
    state.entries = ofs3.logs.getRecentEntries()
    state.selectedListIndex = clamp(state.selectedListIndex or 1, 0, math.max(1, #state.entries))
    state.listScroll = clamp(state.listScroll or 0, 0, math.max(0, #state.entries - 1))
end

local function getFolderBitmap()
    if not ofs3.utils or not ofs3.utils.loadImage then
        return nil
    end

    return ofs3.utils.loadImage("SCRIPTS:/" .. ofs3.config.baseDir .. "/widgets/dashboard/gfx/folder.png")
end

local function calculateZoomSteps(lineCount)
    local duration = math.max(0, tonumber(lineCount) or 0)

    for level = #ZOOM_WINDOWS, 1, -1 do
        if duration >= (ZOOM_WINDOWS[level] * 1.5) then
            return level
        end
    end

    return 1
end

local function lineColor(column)
    if lcd.darkMode() then
        return column.colorDark
    end
    return column.colorLight
end

local function loadLogFile(filename)
    resetGraphState()

    local path = ofs3.logs.getDirectory() .. "/" .. tostring(filename)
    local handle = io.open(path, "r")
    if not handle then
        return false
    end

    local headerLine = handle:read("*l")
    local rows = {}
    while true do
        local line = handle:read("*l")
        if line == nil then
            break
        end
        rows[#rows + 1] = line
    end
    handle:close()

    local header = splitCsvLine(headerLine)
    if #header == 0 then
        return false
    end

    local columnIndex = {}
    for index, name in ipairs(header) do
        columnIndex[name] = index
    end

    local parsed = {}
    for _, column in ipairs(GRAPH_COLUMNS) do
        local idx = columnIndex[column.name]
        if idx then
            local values = {}
            for _, row in ipairs(rows) do
                local parts = splitCsvLine(row)
                values[#values + 1] = tonumber(parts[idx]) or 0
            end

            values = padTable(values, state.graphPadding)
            local minimum, maximum, average = calculateStats(values)
            parsed[#parsed + 1] = {
                name = column.name,
                keyname = column.keyname,
                keyunit = column.keyunit,
                color = lineColor(column),
                graph = column.graph,
                data = values,
                minimum = minimum or 0,
                maximum = maximum or 0,
                average = average or 0
            }
        end
    end

    state.mode = "view"
    state.selectedFile = filename
    state.rawHeader = header
    state.logData = parsed
    state.logLineCount = #rows + (state.graphPadding * 2)
    state.zoomCount = calculateZoomSteps(state.logLineCount)
    state.zoomLevel = math.min(state.zoomLevel, state.zoomCount)
    state.sliderPosition = 1
    state.selectedViewControl = 1
    clearHitboxes()

    return true
end

local function queueLogLoad(filename)
    if not filename or filename == "" then
        return false
    end

    state.loadJob = {
        filename = filename,
        phase = "open",
        rows = {},
        parsed = {},
        columnIndex = {},
        finalizeIndex = 1,
        rowIndex = 1
    }
    state.loadError = nil
    return true
end

local function processLoadJob()
    local job = state.loadJob
    if not job then
        return false
    end

    if job.phase == "open" then
        local path = ofs3.logs.getDirectory() .. "/" .. tostring(job.filename)
        job.handle = io.open(path, "r")
        if not job.handle then
            state.loadError = "@i18n(widgets.dashboard.logs_open_failed)@"
            state.loadJob = nil
            return true
        end

        job.headerLine = job.handle:read("*l")
        job.phase = "read"
        return true
    end

    if job.phase == "read" then
        local count = 0
        while count < LOAD_READ_CHUNK do
            local line = job.handle:read("*l")
            if line == nil then
                job.handle:close()
                job.handle = nil

                local header = splitCsvLine(job.headerLine)
                if #header == 0 then
                    state.loadError = "@i18n(widgets.dashboard.logs_invalid_header)@"
                    state.loadJob = nil
                    return true
                end

                job.header = header
                for index, name in ipairs(header) do
                    job.columnIndex[name] = index
                end

                for _, column in ipairs(GRAPH_COLUMNS) do
                    local idx = job.columnIndex[column.name]
                    if idx then
                        job.parsed[#job.parsed + 1] = {
                            name = column.name,
                            keyname = column.keyname,
                            keyunit = column.keyunit,
                            color = lineColor(column),
                            graph = column.graph,
                            idx = idx,
                            data = {}
                        }
                    end
                end

                job.phase = "parse"
                return true
            end

            job.rows[#job.rows + 1] = line
            count = count + 1
        end

        return true
    end

    if job.phase == "parse" then
        local processed = 0
        while job.rowIndex <= #job.rows and processed < LOAD_PARSE_CHUNK do
            local parts = splitCsvLine(job.rows[job.rowIndex])
            for _, column in ipairs(job.parsed) do
                column.data[#column.data + 1] = tonumber(parts[column.idx]) or 0
            end
            job.rowIndex = job.rowIndex + 1
            processed = processed + 1
        end

        if job.rowIndex > #job.rows then
            job.phase = "finalize"
        end

        return true
    end

    if job.phase == "finalize" then
        local column = job.parsed[job.finalizeIndex]
        if column then
            column.data = padTable(column.data, state.graphPadding)
            local minimum, maximum, average = calculateStats(column.data)
            column.minimum = minimum or 0
            column.maximum = maximum or 0
            column.average = average or 0
            job.finalizeIndex = job.finalizeIndex + 1
            return true
        end

        state.mode = "view"
        state.selectedFile = job.filename
        state.rawHeader = job.header or {}
        state.logData = job.parsed
        state.logLineCount = #job.rows + (state.graphPadding * 2)
        state.zoomCount = calculateZoomSteps(state.logLineCount)
        state.zoomLevel = math.min(state.zoomLevel, state.zoomCount)
        state.sliderPosition = 1
        state.selectedViewControl = 1
        state.loadJob = nil
        clearHitboxes()
        return true
    end

    return false
end

local function drawGraph(points, xStart, yStart, width, height, minimum, maximum, color)
    if #points < 2 then
        return
    end

    local safeMin = minimum
    local safeMax = maximum
    if safeMin == safeMax then
        safeMin = safeMin - 1
        safeMax = safeMax + 1
    end

    local xScale = width / math.max(1, (#points - 1))
    local yScale = height / math.max(1, (safeMax - safeMin))

    lcd.color(color)

    for index = 1, (#points - 1) do
        local x1 = xStart + ((index - 1) * xScale)
        local y1 = yStart + height - ((points[index] - safeMin) * yScale)
        local x2 = xStart + (index * xScale)
        local y2 = yStart + height - ((points[index + 1] - safeMin) * yScale)
        lcd.drawLine(x1, y1, x2, y2)
    end
end

local function getGraphWindow()
    local graphColumns = {}
    for _, column in ipairs(state.logData) do
        if column.graph then
            graphColumns[#graphColumns + 1] = column
        end
    end

    local desiredWindow = ZOOM_WINDOWS[state.zoomLevel] or ZOOM_WINDOWS[1]
    local windowSize = math.min(desiredWindow, math.max(1, state.logLineCount))
    local maxPosition = math.max(1, state.logLineCount - windowSize + 1)
    local startIndex = math.floor((((state.sliderPosition or 1) - 1) / 99) * (maxPosition - 1)) + 1

    return graphColumns, startIndex, windowSize
end

local function getListMetrics(width, height)
    local margin = width >= 700 and 16 or 10
    local topBarHeight = width >= 700 and 34 or 30
    local tileGap = width >= 700 and 12 or 10
    local tileW = width >= 700 and 118 or (width >= 600 and 108 or 96)
    local tileH = width >= 700 and 104 or (width >= 600 and 96 or 84)
    local listTop = margin + topBarHeight + 8
    local footerHeight = 4
    local listH = math.max(tileH, height - listTop - margin - footerHeight)
    local listW = width - (margin * 2)
    local columns = math.max(1, math.floor((listW + tileGap) / (tileW + tileGap)))
    local rows = math.max(1, math.floor((listH + tileGap) / (tileH + tileGap)))

    return {
        margin = margin,
        topBarHeight = topBarHeight,
        tileGap = tileGap,
        tileW = tileW,
        tileH = tileH,
        listX = margin,
        listY = listTop,
        listW = listW,
        listH = listH,
        columns = columns,
        rows = rows,
        visibleRows = columns * rows
    }
end

local function ensureSelectionVisible(visibleRows)
    local maxScroll = math.max(0, #state.entries - visibleRows)
    state.listScroll = clamp(state.listScroll or 0, 0, maxScroll)

    local selected = clamp(state.selectedListIndex or 1, 0, math.max(1, #state.entries))
    state.selectedListIndex = selected

    if selected == 0 then
        state.listScroll = 0
    elseif selected <= state.listScroll then
        state.listScroll = selected - 1
    elseif selected > (state.listScroll + visibleRows) then
        state.listScroll = selected - visibleRows
    end

    state.listScroll = clamp(state.listScroll, 0, maxScroll)
end

local function moveSelection(delta, visibleRows)
    if #state.entries == 0 then
        state.selectedListIndex = 0
        state.listScroll = 0
        return
    end

    state.selectedListIndex = clamp((state.selectedListIndex or 1) + delta, 0, #state.entries)
    ensureSelectionVisible(visibleRows)
end

local function openSelectedEntry()
    if (state.selectedListIndex or 0) == 0 then
        closeViewer()
        return
    end

    local entry = state.entries[state.selectedListIndex or 1]
    if entry then
        queueLogLoad(entry.name)
    end
end

local function adjustSlider(delta)
    state.sliderPosition = clamp((state.sliderPosition or 1) + delta, 1, 100)
end

local function buttonHit(hitbox, x, y)
    return hitbox and x >= hitbox.x and x < (hitbox.x + hitbox.w) and y >= hitbox.y and y < (hitbox.y + hitbox.h)
end

local function getListTouchTarget(x, y)
    if buttonHit(state.hitboxes.list.back, x, y) then
        return {kind = "back"}
    end

    for index, hitbox in pairs(state.hitboxes.list) do
        if type(index) == "number" and buttonHit(hitbox, x, y) then
            return {kind = "entry", entryIndex = hitbox.entryIndex}
        end
    end

    return nil
end

local function getViewTouchTarget(x, y)
    if buttonHit(state.hitboxes.view.back, x, y) then
        return {kind = "back"}
    end
    if buttonHit(state.hitboxes.view.minus, x, y) then
        return {kind = "minus"}
    end
    if buttonHit(state.hitboxes.view.plus, x, y) then
        return {kind = "plus"}
    end
    if buttonHit(state.hitboxes.view.left, x, y) then
        return {kind = "left"}
    end
    if buttonHit(state.hitboxes.view.right, x, y) then
        return {kind = "right"}
    end

    return nil
end

local function drawButton(x, y, w, h, label, selected, theme, font, enabled, centered)
    local isEnabled = enabled ~= false
    local fill = selected and theme.accentSoft or (isEnabled and theme.button or theme.buttonDisabled)
    local border = selected and theme.accent or theme.border
    local textColor = selected and theme.text or (isEnabled and theme.text or theme.muted)

    lcd.color(fill)
    lcd.drawFilledRectangle(x, y, w, h)
    lcd.color(border)
    lcd.drawRectangle(x, y, w, h, 1)
    lcd.font(font or FONT_XS)
    lcd.color(textColor)

    local textY = y + math.max(4, math.floor((h - 18) / 2))
    if centered then
        lcd.drawText(x + math.floor(w / 2), textY, label, CENTERED)
    else
        lcd.drawText(x + 10, textY, label)
    end
end

local function drawTile(x, y, w, h, entry, selected, theme, bitmap)
    lcd.color(selected and theme.accentSoft or theme.button)
    lcd.drawFilledRectangle(x, y, w, h)
    lcd.color(selected and theme.accent or theme.border)
    lcd.drawRectangle(x, y, w, h, 1)

    if bitmap then
        local iconSize = math.min(52, h - 34)
        local iconX = x + math.floor((w - iconSize) / 2)
        local iconY = y + 20
        lcd.drawBitmap(iconX, iconY, bitmap, iconSize, iconSize)
    end

    lcd.font(FONT_XS)
    lcd.color(theme.text)
    lcd.drawText(x + math.floor(w / 2), y + 8, extractTimeLabel(entry.name), CENTERED)

    lcd.font(FONT_XXS)
    lcd.color(theme.muted)
    lcd.drawText(x + math.floor(w / 2), y + h - 16, extractCompactDateLabel(entry.name), CENTERED)
end

local function currentViewControlName()
    return VIEW_CONTROLS[state.selectedViewControl or 1] or VIEW_CONTROLS[1]
end

local function moveViewControl(delta)
    local count = #VIEW_CONTROLS
    local selected = (state.selectedViewControl or 1) + delta

    if selected < 1 then
        selected = count
    elseif selected > count then
        selected = 1
    end

    state.selectedViewControl = selected
end

local function activateViewControl(name)
    if name == "back" then
        returnToList()
        return true
    end

    if name == "minus" then
        state.zoomLevel = math.max(1, state.zoomLevel - 1)
        return true
    end

    if name == "plus" then
        state.zoomLevel = math.min(state.zoomCount, state.zoomLevel + 1)
        return true
    end

    if name == "left" then
        adjustSlider(-10)
        return true
    end

    if name == "right" then
        adjustSlider(10)
        return true
    end

    return false
end

local function formatMetricValue(value, unit)
    local metric = tonumber(value) or 0
    local suffix = unit and (" " .. unit) or ""

    if unit == "rpm" then
        return string.format("%.0f%s", metric, suffix)
    end

    return string.format("%.1f%s", metric, suffix)
end

local function paintList(theme, width, height)
    clearHitboxes()
    refreshEntries()

    local metrics = getListMetrics(width, height)
    ensureSelectionVisible(metrics.visibleRows)
    local folderBitmap = getFolderBitmap()

    local topBarY = metrics.margin
    local topBarW = width - (metrics.margin * 2)
    local titleX = metrics.margin + 88

    lcd.color(theme.panelAlt)
    lcd.drawFilledRectangle(metrics.margin, topBarY, topBarW, metrics.topBarHeight)
    lcd.color(theme.border)
    lcd.drawRectangle(metrics.margin, topBarY, topBarW, metrics.topBarHeight, 1)
    lcd.color(theme.accent)
    lcd.drawFilledRectangle(metrics.margin, topBarY, 4, metrics.topBarHeight)

    state.hitboxes.list.back = {x = metrics.margin + 8, y = topBarY + 4, w = 74, h = metrics.topBarHeight - 8}
    drawButton(state.hitboxes.list.back.x, state.hitboxes.list.back.y, state.hitboxes.list.back.w, state.hitboxes.list.back.h, "@i18n(widgets.dashboard.logs_back)@", (state.selectedListIndex or 1) == 0, theme, FONT_XXS, true, false)

    lcd.font(FONT_XS)
    lcd.color(theme.text)
    lcd.drawText(titleX, topBarY + 5, "@i18n(widgets.dashboard.logs_title)@")

    lcd.font(FONT_XXS)
    lcd.color(theme.muted)
    lcd.drawText(titleX, topBarY + 18, string.format("@i18n(widgets.dashboard.logs_count)@", #state.entries))

    if #state.entries == 0 then
        lcd.font(FONT_STD)
        lcd.color(theme.text)
        lcd.drawText(metrics.listX + 4, metrics.listY + 10, "@i18n(widgets.dashboard.logs_empty_title)@")
        lcd.font(FONT_XXS)
        lcd.color(theme.muted)
        lcd.drawText(metrics.listX + 4, metrics.listY + 34, "@i18n(widgets.dashboard.logs_empty_message)@")
        return
    end

    local lastIndex = math.min(#state.entries, state.listScroll + metrics.visibleRows)
    local tileIndex = 0

    for entryIndex = state.listScroll + 1, lastIndex do
        local entry = state.entries[entryIndex]
        local selected = entryIndex == state.selectedListIndex
        local col = tileIndex % metrics.columns
        local row = math.floor(tileIndex / metrics.columns)
        local tileX = metrics.listX + (col * (metrics.tileW + metrics.tileGap))
        local tileY = metrics.listY + (row * (metrics.tileH + metrics.tileGap))

        state.hitboxes.list[entryIndex] = {x = tileX, y = tileY, w = metrics.tileW, h = metrics.tileH, entryIndex = entryIndex}
        drawTile(tileX, tileY, metrics.tileW, metrics.tileH, entry, selected, theme, folderBitmap)
        tileIndex = tileIndex + 1
    end

end

local function paintView(theme, width, height)
    clearHitboxes()

    local margin = width >= 700 and 12 or 8
    local topBarHeight = width >= 700 and 40 or 34
    local buttonW = width >= 700 and 74 or 58
    local buttonGap = 6
    local buttonY = margin + 4
    local buttonH = topBarHeight - 8

    lcd.color(theme.panelAlt)
    lcd.drawFilledRectangle(margin, margin, width - (margin * 2), topBarHeight)
    lcd.color(theme.border)
    lcd.drawRectangle(margin, margin, width - (margin * 2), topBarHeight, 1)
    lcd.color(theme.accent)
    lcd.drawFilledRectangle(margin, margin, 4, topBarHeight)

    state.hitboxes.view.back = {x = margin + 8, y = buttonY, w = buttonW, h = buttonH}
    state.hitboxes.view.minus = {x = width - margin - ((buttonW + buttonGap) * 4), y = buttonY, w = buttonW, h = buttonH}
    state.hitboxes.view.plus = {x = width - margin - ((buttonW + buttonGap) * 3), y = buttonY, w = buttonW, h = buttonH}
    state.hitboxes.view.left = {x = width - margin - ((buttonW + buttonGap) * 2), y = buttonY, w = buttonW, h = buttonH}
    state.hitboxes.view.right = {x = width - margin - (buttonW + buttonGap), y = buttonY, w = buttonW, h = buttonH}

    local selectedControl = currentViewControlName()
    drawButton(state.hitboxes.view.back.x, state.hitboxes.view.back.y, state.hitboxes.view.back.w, state.hitboxes.view.back.h, "@i18n(widgets.dashboard.logs_back)@", selectedControl == "back", theme, FONT_XXS, true, false)
    drawButton(state.hitboxes.view.minus.x, state.hitboxes.view.minus.y, state.hitboxes.view.minus.w, state.hitboxes.view.minus.h, "-", selectedControl == "minus", theme, FONT_XS, true, true)
    drawButton(state.hitboxes.view.plus.x, state.hitboxes.view.plus.y, state.hitboxes.view.plus.w, state.hitboxes.view.plus.h, "+", selectedControl == "plus", theme, FONT_XS, true, true)
    drawButton(state.hitboxes.view.left.x, state.hitboxes.view.left.y, state.hitboxes.view.left.w, state.hitboxes.view.left.h, "<", selectedControl == "left", theme, FONT_XS, true, true)
    drawButton(state.hitboxes.view.right.x, state.hitboxes.view.right.y, state.hitboxes.view.right.w, state.hitboxes.view.right.h, ">", selectedControl == "right", theme, FONT_XS, true, true)

    lcd.font(FONT_XS)
    lcd.color(theme.text)
    lcd.drawText(margin + buttonW + 20, margin + 6, extractShortTimestamp(state.selectedFile))
    lcd.font(FONT_XXS)
    lcd.color(theme.muted)
    lcd.drawText(margin + buttonW + 20, margin + 22, string.format("@i18n(widgets.dashboard.logs_zoom_status)@", state.zoomLevel, state.zoomCount, state.sliderPosition))

    local graphColumns, startIndex, windowSize = getGraphWindow()
    local graphTop = margin + topBarHeight + 10
    local graphLeft = margin
    local graphWidth = math.max(180, math.floor(width * 0.63))
    local graphHeight = height - graphTop - margin
    local laneHeight = #graphColumns > 0 and (graphHeight / #graphColumns) or graphHeight
    local statsX = graphLeft + graphWidth + 14
    local statsW = width - statsX - margin
    local statsRowHeight = #graphColumns > 0 and math.max(30, math.floor(graphHeight / #graphColumns)) or 32

    lcd.color(theme.panel)
    lcd.drawFilledRectangle(graphLeft, graphTop, graphWidth, graphHeight)

    for lane, column in ipairs(graphColumns) do
        local y = graphTop + ((lane - 1) * laneHeight)
        local points = {}
        for index = startIndex, math.min(startIndex + windowSize - 1, #column.data) do
            points[#points + 1] = column.data[index]
        end

        if lane > 1 then
            lcd.color(theme.border)
            lcd.drawLine(graphLeft, y - 4, graphLeft + graphWidth, y - 4)
        end

        drawGraph(points, graphLeft + 4, y + 4, graphWidth - 8, laneHeight - 12, column.minimum, column.maximum, column.color)

        local statsY = graphTop + ((lane - 1) * statsRowHeight)
        local currentValue = points[#points] or 0

        lcd.font(FONT_XS)
        lcd.color(theme.text)
        lcd.drawText(statsX, statsY + 2, column.keyname)
        lcd.font(FONT_XXS)
        lcd.color(theme.muted)
        lcd.drawText(statsX, statsY + 18, string.format("@i18n(widgets.dashboard.logs_metric_min)@", formatMetricValue(column.minimum, column.keyunit)))
        lcd.drawText(statsX + math.floor(statsW * 0.42), statsY + 18, string.format("@i18n(widgets.dashboard.logs_metric_max)@", formatMetricValue(column.maximum, column.keyunit)))
        lcd.color(theme.text)
        lcd.drawText(statsX, statsY + 32, string.format("@i18n(widgets.dashboard.logs_metric_now)@", formatMetricValue(currentValue, column.keyunit)))
    end
end

function logviewer.open()
    state.active = true
    state.mode = "list"
    clearHitboxes()
    resetGraphState()
    refreshEntries()
end

function logviewer.close()
    closeViewer()
end

function logviewer.isActive()
    return state.active
end

function logviewer.event(widget, category, value, x, y)
    if not state.active then
        return false
    end

    if category == EVT_KEY and isExitKey(value) then
        if state.mode == "view" then
            returnToList()
        else
            closeViewer()
        end
        if system.killEvents then
            system.killEvents(value)
        end
        if lcd.invalidate then
            lcd.invalidate(widget)
        end
        return true
    end

    if state.mode == "list" then
        local metrics = getListMetrics(lcd.getWindowSize())
        ensureSelectionVisible(metrics.visibleRows)

        if category == EVT_KEY and isNextKey(value) then
            moveSelection(1, metrics.visibleRows)
            lcd.invalidate(widget)
            return true
        end

        if category == EVT_KEY and isPrevKey(value) then
            moveSelection(-1, metrics.visibleRows)
            lcd.invalidate(widget)
            return true
        end

        if category == EVT_KEY and matchesKey(value, "KEY_ENTER_BREAK") then
            openSelectedEntry()
            lcd.invalidate(widget)
            return true
        end

        if isTouchStart(category, value) and x and y then
            state.pressedTarget = getListTouchTarget(x, y)
            if state.pressedTarget and state.pressedTarget.kind == "entry" then
                state.selectedListIndex = state.pressedTarget.entryIndex
                lcd.invalidate(widget)
            end
            if state.pressedTarget then
                consumeTouchEvent(category, value)
            end
            return state.pressedTarget ~= nil
        end

        if isTouchEnd(category, value) and x and y then
            local target = getListTouchTarget(x, y)
            local pressed = state.pressedTarget
            state.pressedTarget = nil

            if not target then
                consumeTouchEvent(category, value)
                return true
            end

            if pressed and (target.kind ~= pressed.kind or target.entryIndex ~= pressed.entryIndex) then
                consumeTouchEvent(category, value)
                return true
            end

            if target.kind == "back" then
                consumeTouchEvent(category, value)
                closeViewer()
                lcd.invalidate(widget)
                return true
            end

            if target.kind == "entry" then
                state.selectedListIndex = target.entryIndex
                openSelectedEntry()
                consumeTouchEvent(category, value)
                lcd.invalidate(widget)
                return true
            end
        end

        if isAnyTouch(category) then
            consumeTouchEvent(category, value)
            return true
        end
    end

    if state.mode == "view" then
        if category == EVT_KEY and matchesKey(value, "KEY_ENTER_BREAK") then
            activateViewControl(currentViewControlName())
            lcd.invalidate(widget)
            return true
        end

        if category == EVT_KEY and isPrevKey(value) then
            moveViewControl(-1)
            lcd.invalidate(widget)
            return true
        end

        if category == EVT_KEY and isNextKey(value) then
            moveViewControl(1)
            lcd.invalidate(widget)
            return true
        end

        if isTouchStart(category, value) and x and y then
            state.pressedTarget = getViewTouchTarget(x, y)
            if state.pressedTarget then
                consumeTouchEvent(category, value)
            end
            return state.pressedTarget ~= nil
        end

        if isTouchEnd(category, value) and x and y then
            local target = getViewTouchTarget(x, y)
            local pressed = state.pressedTarget
            state.pressedTarget = nil

            if not target then
                consumeTouchEvent(category, value)
                return true
            end

            if pressed and target.kind ~= pressed.kind then
                consumeTouchEvent(category, value)
                return true
            end

            if target.kind == "back" then
                consumeTouchEvent(category, value)
                state.selectedViewControl = 1
                activateViewControl("back")
                lcd.invalidate(widget)
                return true
            end

            if target.kind == "minus" then
                consumeTouchEvent(category, value)
                state.selectedViewControl = 2
                activateViewControl("minus")
                lcd.invalidate(widget)
                return true
            end

            if target.kind == "plus" then
                consumeTouchEvent(category, value)
                state.selectedViewControl = 3
                activateViewControl("plus")
                lcd.invalidate(widget)
                return true
            end

            if target.kind == "left" then
                consumeTouchEvent(category, value)
                state.selectedViewControl = 4
                activateViewControl("left")
                lcd.invalidate(widget)
                return true
            end

            if target.kind == "right" then
                consumeTouchEvent(category, value)
                state.selectedViewControl = 5
                activateViewControl("right")
                lcd.invalidate(widget)
                return true
            end
        end

        if isAnyTouch(category) then
            consumeTouchEvent(category, value)
            return true
        end
    end

    return false
end

function logviewer.wakeup(widget)
    if not state.active then
        return
    end

    if state.loadJob then
        processLoadJob()
    end

    if lcd.invalidate then
        lcd.invalidate(widget)
    end
end

function logviewer.paint()
    if not state.active then
        return
    end

    local theme = getTheme()
    local width, height = lcd.getWindowSize()
    lcd.color(theme.background)
    lcd.drawFilledRectangle(0, 0, width, height)

    if state.loadJob then
        lcd.color(theme.panelAlt)
        lcd.drawFilledRectangle(20, math.floor(height * 0.35), width - 40, 70)
        lcd.color(theme.border)
        lcd.drawRectangle(20, math.floor(height * 0.35), width - 40, 70, 1)
        lcd.color(theme.accent)
        lcd.drawFilledRectangle(20, math.floor(height * 0.35), 4, 70)
        lcd.font(FONT_STD)
        lcd.color(theme.text)
        lcd.drawText(math.floor(width / 2), math.floor(height * 0.35) + 14, "@i18n(widgets.dashboard.logs_loading)@", CENTERED)
        lcd.font(FONT_XXS)
        lcd.color(theme.muted)
        lcd.drawText(math.floor(width / 2), math.floor(height * 0.35) + 38, tostring(state.loadJob.filename or ""), CENTERED)
        return
    end

    if state.loadError then
        lcd.color(theme.panelAlt)
        lcd.drawFilledRectangle(20, math.floor(height * 0.35), width - 40, 70)
        lcd.color(theme.border)
        lcd.drawRectangle(20, math.floor(height * 0.35), width - 40, 70, 1)
        lcd.color(theme.accent)
        lcd.drawFilledRectangle(20, math.floor(height * 0.35), 4, 70)
        lcd.font(FONT_STD)
        lcd.color(theme.text)
        lcd.drawText(math.floor(width / 2), math.floor(height * 0.35) + 14, "@i18n(widgets.dashboard.logs_load_failed)@", CENTERED)
        lcd.font(FONT_XXS)
        lcd.color(theme.muted)
        lcd.drawText(math.floor(width / 2), math.floor(height * 0.35) + 38, tostring(state.loadError), CENTERED)
        return
    end

    if state.mode == "view" and state.selectedFile then
        paintView(theme, width, height)
        return
    end

    paintList(theme, width, height)
end

return logviewer
