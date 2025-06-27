local settings = {}
local i18n = ofs3.i18n.get
local function openPage(pageIdx, title, script)
    enableWakeup = true
    ofs3.app.triggers.closeProgressLoader = true
    form.clear()

    ofs3.app.lastIdx    = pageIdx
    ofs3.app.lastTitle  = title
    ofs3.app.lastScript = script

    ofs3.app.ui.fieldHeader(
        i18n("app.modules.settings.name") .. " / " .. i18n("app.modules.settings.dashboard") .. " / " .. i18n("app.modules.settings.localizations")
    )
    ofs3.session.formLineCnt = 0

    local formFieldCount = 0

    settings = ofs3.preferences.localizations

    formFieldCount = formFieldCount + 1
    ofs3.session.formLineCnt = ofs3.session.formLineCnt + 1
    ofs3.app.formLines[ofs3.session.formLineCnt] = form.addLine(i18n("app.modules.settings.temperature_unit"))
    ofs3.app.formFields[formFieldCount] = form.addChoiceField(ofs3.app.formLines[ofs3.session.formLineCnt], nil, 
                                                        {{i18n("app.modules.settings.celcius"), 0}, {i18n("app.modules.settings.fahrenheit"), 1}}, 
                                                        function() 
                                                            if ofs3.preferences and ofs3.preferences.localizations then
                                                                return settings.temperature_unit or 0
                                                            end
                                                        end, 
                                                        function(newValue) 
                                                            if ofs3.preferences and ofs3.preferences.localizations then
                                                                settings.temperature_unit = newValue
                                                            end    
                                                        end) 
            
    formFieldCount = formFieldCount + 1
    ofs3.session.formLineCnt = ofs3.session.formLineCnt + 1
    ofs3.app.formLines[ofs3.session.formLineCnt] = form.addLine(i18n("app.modules.settings.altitude_unit"))
    ofs3.app.formFields[formFieldCount] = form.addChoiceField(ofs3.app.formLines[ofs3.session.formLineCnt], nil, 
                                                        {{i18n("app.modules.settings.meters"), 0}, {i18n("app.modules.settings.feet"), 1}}, 
                                                        function() 
                                                            if ofs3.preferences and ofs3.preferences.localizations then
                                                                return settings.altitude_unit or 0
                                                            end
                                                        end, 
                                                        function(newValue) 
                                                            if ofs3.preferences and ofs3.preferences.localizations then
                                                                settings.altitude_unit = newValue
                                                            end    
                                                        end) 
              
                                                  
end

local function onNavMenu()
    ofs3.app.ui.progressDisplay()
        ofs3.app.ui.openPage(
            pageIdx,
            i18n("app.modules.settings.name"),
            "settings/settings.lua"
        )
        return true
end

local function onSaveMenu()
    local buttons = {
        {
            label  = i18n("app.btn_ok_long"),
            action = function()
                local msg = i18n("app.modules.profile_select.save_prompt_local")
                ofs3.app.ui.progressDisplaySave(msg:gsub("%?$", "."))
                for key, value in pairs(settings) do
                    ofs3.preferences.dashboard[key] = value
                end
                ofs3.ini.save_ini_file(
                    "SCRIPTS:/" .. ofs3.config.preferences .. "/preferences.ini",
                    ofs3.preferences
                )
                -- update dashboard theme
                ofs3.widgets.dashboard.reload_themes()
                -- close save progress
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
            "settings/settings.lua"
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
