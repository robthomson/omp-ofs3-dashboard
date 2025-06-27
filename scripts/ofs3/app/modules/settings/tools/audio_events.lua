local settings = {}
local i18n = ofs3.i18n.get

local function sensorNameMap(sensorList)
    local nameMap = {}
    for _, sensor in ipairs(sensorList) do
        nameMap[sensor.key] = sensor.name
    end
    return nameMap
end

local function openPage(pageIdx, title, script)
    enableWakeup = true
    ofs3.app.triggers.closeProgressLoader = true
    form.clear()

    ofs3.app.lastIdx    = pageIdx
    ofs3.app.lastTitle  = title
    ofs3.app.lastScript = script

    ofs3.app.ui.fieldHeader(
        i18n("app.modules.settings.name") .. " / " .. i18n("app.modules.settings.audio") .. " / " .. i18n("app.modules.settings.txt_audio_events")
    )
    ofs3.session.formLineCnt = 0

    local formFieldCount = 0

    local eventList = ofs3.tasks.events.telemetry.eventTable
    local eventNames = sensorNameMap(ofs3.tasks.telemetry.listSensors())

    settings = ofs3.preferences.events

    for i, v in ipairs(eventList) do
    formFieldCount = formFieldCount + 1
    ofs3.session.formLineCnt = ofs3.session.formLineCnt + 1
    ofs3.app.formLines[ofs3.session.formLineCnt] = form.addLine(eventNames[v.sensor] or "unknown")
    ofs3.app.formFields[formFieldCount] = form.addBooleanField(ofs3.app.formLines[ofs3.session.formLineCnt], 
                                                        nil, 
                                                        function() 
                                                            if ofs3.preferences and ofs3.preferences.events then
                                                                return settings[v.sensor] 
                                                            end
                                                        end, 
                                                        function(newValue) 
                                                            if ofs3.preferences and ofs3.preferences.events then
                                                                settings[v.sensor] = newValue 
                                                            end    
                                                        end)
    end
  
end

local function onNavMenu()
    ofs3.app.ui.progressDisplay()
    ofs3.app.ui.openPage(
        pageIdx,
        i18n("app.modules.settings.name"),
        "settings/tools/audio.lua"
    )
end

local function onSaveMenu()
    local buttons = {
        {
            label  = i18n("app.btn_ok_long"),
            action = function()
                local msg = i18n("app.modules.profile_select.save_prompt_local")
                ofs3.app.ui.progressDisplaySave(msg:gsub("%?$", "."))
                for key, value in pairs(settings) do
                    ofs3.preferences.events[key] = value
                end
                ofs3.ini.save_ini_file(
                    "SCRIPTS:/" .. ofs3.config.preferences .. "/preferences.ini",
                    ofs3.preferences
                )
                ofs3.app.triggers.closeSave = true
                return true
            end,
        },
        {
            label  = i18n("app.modules.profile_select.cancel"),
            action = function()
                return true
            end,
        },
    }

    form.openDialog({
        width   = nil,
        title   = i18n("app.modules.profile_select.save_settings"),
        message = i18n("app.modules.profile_select.save_prompt_local"),
        buttons = buttons,
        wakeup  = function() end,
        paint   = function() end,
        options = TEXT_LEFT,
    })
end

local function event(widget, category, value, x, y)
    -- if close event detected go to section home page
    if category == EVT_CLOSE and value == 0 or value == 35 then
        ofs3.app.ui.openPage(
            pageIdx,
        i18n("app.modules.settings.name"),
        "settings/tools/audio.lua"
        )
        return true
    end
end

return {
    event      = event,
    openPage   = openPage,
    wakeup     = wakeup,
    onNavMenu  = onNavMenu,
    onSaveMenu = onSaveMenu,
    navButtons = {
        menu   = true,
        save   = true,
        reload = false,
        tool   = false,
        help   = false,
    },
    API = {},
}
