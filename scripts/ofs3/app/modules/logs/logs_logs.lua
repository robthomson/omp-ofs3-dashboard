local utils = assert(ofs3.compiler.loadfile("SCRIPTS:/" .. ofs3.config.baseDir .. "/app/modules/logs/lib/utils.lua"))()
local i18n = ofs3.i18n.get
local triggerOverRide = false
local triggerOverRideAll = false
local lastServoCountTime = os.clock()
local enableWakeup = false
local wakeupScheduler = os.clock()
local currentDisplayMode

local function getCleanModelName()
    local logdir
    logdir = string.gsub(model.name(), "%s+", "_")
    logdir = string.gsub(logdir, "%W", "_")
    return logdir
end


local function extractHourMinute(filename)
    -- Capture hour and minute from the time-portion (HH-MM-SS) after the underscore
    local hour, minute = filename:match(".-%d%d%d%d%-%d%d%-%d%d_(%d%d)%-(%d%d)%-%d%d")
    if hour and minute then
        return hour .. ":" .. minute
    end
    return nil
end

local function format_date(iso_date)
  local y, m, d = iso_date:match("^(%d+)%-(%d+)%-(%d+)$")
  return os.date("%d %B %Y", os.time{
    year  = tonumber(y),
    month = tonumber(m),
    day   = tonumber(d),
  })
end

local function openPage(pidx, title, script, displaymode)

    -- hard exit on error
    if not ofs3.utils.ethosVersionAtLeast() then
        return
    end


    currentDisplayMode = displaymode


    ofs3.app.triggers.isReady = false
    ofs3.app.uiState = ofs3.app.uiStatus.pages

    form.clear()

    ofs3.app.lastIdx = idx
    ofs3.app.lastTitle = title
    ofs3.app.lastScript = script

    local w, h = ofs3.utils.getWindowSize()
    local windowWidth = w
    local windowHeight = h
    local padding = ofs3.app.radio.buttonPadding

    local sc
    local panel

     local logDir = utils.getLogPath()

    local logs = utils.getLogs(logDir)   

    print(logDir)


    local name = utils.resolveModelName(ofs3.session.mcu_id or ofs3.session.activeLogDir)
    ofs3.app.ui.fieldHeader("Logs" )

    local buttonW
    local buttonH
    local padding
    local numPerRow

   if ofs3.preferences.general.iconsize == 0 then
        padding = ofs3.app.radio.buttonPaddingSmall
        buttonW = (ofs3.session.lcdWidth - padding) / ofs3.app.radio.buttonsPerRow - padding
        buttonH = ofs3.app.radio.navbuttonHeight
        numPerRow = ofs3.app.radio.buttonsPerRow
    end
    -- SMALL ICONS
    if ofs3.preferences.general.iconsize == 1 then

        padding = ofs3.app.radio.buttonPaddingSmall
        buttonW = ofs3.app.radio.buttonWidthSmall
        buttonH = ofs3.app.radio.buttonHeightSmall
        numPerRow = ofs3.app.radio.buttonsPerRowSmall
    end
    -- LARGE ICONS
    if ofs3.preferences.general.iconsize == 2 then

        padding = ofs3.app.radio.buttonPadding
        buttonW = ofs3.app.radio.buttonWidth
        buttonH = ofs3.app.radio.buttonHeight
        numPerRow = ofs3.app.radio.buttonsPerRow
    end


    local x = windowWidth - buttonW + 10

    local lc = 0
    local bx = 0

    if ofs3.app.gfx_buttons["logs_logs"] == nil then ofs3.app.gfx_buttons["logs_logs"] = {} end
    if ofs3.preferences.menulastselected["logs"] == nil then ofs3.preferences.menulastselected["logs_logs"] = 1 end

    if ofs3.app.gfx_buttons["logs"] == nil then ofs3.app.gfx_buttons["logs"] = {} end
    if ofs3.preferences.menulastselected["logs_logs"] == nil then ofs3.preferences.menulastselected["logs_logs"] = 1 end

    -- Group logs by date
    local groupedLogs = {}
    for _, filename in ipairs(logs) do
        local datePart = filename:match("(%d%d%d%d%-%d%d%-%d%d)_")
        if datePart then
            groupedLogs[datePart] = groupedLogs[datePart] or {}
            table.insert(groupedLogs[datePart], filename)
        end
    end

    -- Sort dates descending
    local dates = {}
    for date,_ in pairs(groupedLogs) do table.insert(dates, date) end
    table.sort(dates, function(a,b) return a > b end)


    if #dates == 0 then

        LCD_W, LCD_H = ofs3.utils.getWindowSize()
        local str = i18n("app.modules.logs.msg_no_logs_found")
        local ew = LCD_W
        local eh = LCD_H
        local etsizeW, etsizeH = lcd.getTextSize(str)
        local eposX = ew / 2 - etsizeW / 2
        local eposY = eh / 2 - etsizeH / 2

        local posErr = {w = etsizeW, h = ofs3.app.radio.navbuttonHeight, x = eposX, y = ePosY}

        line = form.addLine("", nil, false)
        form.addStaticText(line, posErr, str)

    else
        ofs3.app.gfx_buttons["logs_logs"] = ofs3.app.gfx_buttons["logs_logs"] or {}
        ofs3.preferences.menulastselected["logs_logs"] = ofs3.preferences.menulastselected["logs_logs"] or 1

        for idx, section in ipairs(dates) do

                form.addLine(format_date(section))
                local lc, y = 0, 0

                for pidx, page in ipairs(groupedLogs[section]) do

                            if lc == 0 then
                                y = form.height() + (ofs3.preferences.general.iconsize == 2 and ofs3.app.radio.buttonPadding or ofs3.app.radio.buttonPaddingSmall)
                            end

                            local x = (buttonW + padding) * lc
                            if ofs3.preferences.general.iconsize ~= 0 then
                                if ofs3.app.gfx_buttons["logs_logs"][pidx] == nil then ofs3.app.gfx_buttons["logs_logs"][pidx] = lcd.loadMask("app/modules/logs/gfx/logs.png") end
                            else
                                ofs3.app.gfx_buttons["logs_logs"][pidx] = nil
                            end

                            ofs3.app.formFields[pidx] = form.addButton(line, {x = x, y = y, w = buttonW, h = buttonH}, {
                                text = extractHourMinute(page),
                                icon = ofs3.app.gfx_buttons["logs_logs"][pidx],
                                options = FONT_S,
                                paint = function() end,
                                press = function()
                                    ofs3.preferences.menulastselected["logs_logs"] = tostring(idx) .. "_" .. tostring(pidx)
                                    ofs3.app.ui.progressDisplay()
                                    ofs3.app.ui.openPage(pidx, "Logs", "logs/logs_view.lua", page)                       
                                end
                            })

                            if ofs3.preferences.menulastselected["logs_logs"] == tostring(idx) .. "_" .. tostring(pidx) then
                                ofs3.app.formFields[pidx]:focus()
                            end

                            lc = (lc + 1) % numPerRow

                end

        end   

            
    end


    ofs3.app.triggers.closeProgressLoader = true

    enableWakeup = true

    return
end

local function event(widget, category, value, x, y)
    if  value == 35 then
        ofs3.app.ui.openMainMenu()
        return true
    end
    return false
end

local function wakeup()

    if enableWakeup == true then

    end

end

local function onNavMenu()

      --ofs3.app.ui.openPage(ofs3.app.lastIdx, ofs3.app.lastTitle, "logs/logs_dir.lua")
    ofs3.app.ui.openMainMenu()

end

return {
    event = event,
    openPage = openPage,
    wakeup = wakeup,
    onNavMenu = onNavMenu,
    navButtons = {
        menu = true,
        save = false,
        reload = false,
        tool = false,
        help = true
    },
    API = {},
}
