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
        i18n("app.modules.settings.name") .. " / " .. i18n("app.modules.settings.txt_development")
    )
    ofs3.session.formLineCnt = 0

    local formFieldCount = 0

    settings = ofs3.preferences.developer

formFieldCount = formFieldCount + 1
    ofs3.session.formLineCnt = ofs3.session.formLineCnt + 1
    ofs3.app.formLines[ofs3.session.formLineCnt] = form.addLine(i18n("app.modules.settings.txt_devtools"))
    ofs3.app.formFields[formFieldCount] = form.addBooleanField(ofs3.app.formLines[ofs3.session.formLineCnt], 
                                                        nil, 
                                                        function() 
                                                            if ofs3.preferences and ofs3.preferences.developer then
                                                                return settings['devtools'] 
                                                            end
                                                        end, 
                                                        function(newValue) 
                                                            if ofs3.preferences and ofs3.preferences.developer then
                                                                settings.devtools = newValue
                                                            end    
                                                        end)    


    formFieldCount = formFieldCount + 1
    ofs3.session.formLineCnt = ofs3.session.formLineCnt + 1
    ofs3.app.formLines[ofs3.session.formLineCnt] = form.addLine(i18n("app.modules.settings.txt_compilation"))
    ofs3.app.formFields[formFieldCount] = form.addBooleanField(ofs3.app.formLines[ofs3.session.formLineCnt], 
                                                        nil, 
                                                        function() 
                                                            if ofs3.preferences and ofs3.preferences.developer then
                                                                return settings['compile'] 
                                                            end
                                                        end, 
                                                        function(newValue) 
                                                            if ofs3.preferences and ofs3.preferences.developer then
                                                                settings.compile = newValue
                                                            end    
                                                        end)                                                        

    formFieldCount = formFieldCount + 1
    ofs3.session.formLineCnt = ofs3.session.formLineCnt + 1
    ofs3.app.formLines[ofs3.session.formLineCnt] = form.addLine(i18n("app.modules.settings.txt_apiversion"))
    ofs3.app.formFields[formFieldCount] = form.addChoiceField(ofs3.app.formLines[ofs3.session.formLineCnt], nil, 
                                                        ofs3.utils.msp_version_array_to_indexed(),
                                                        function() 
                                                                return settings.apiversion
                                                        end, 
                                                        function(newValue) 
                                                                settings.apiversion = newValue
                                                        end) 



    local logpanel = form.addExpansionPanel(i18n("app.modules.settings.txt_logging"))
    logpanel:open(false) 

    formFieldCount = formFieldCount + 1
    ofs3.session.formLineCnt = ofs3.session.formLineCnt + 1
    ofs3.app.formLines[ofs3.session.formLineCnt] = logpanel:addLine(i18n("app.modules.settings.txt_loglocation"))
    ofs3.app.formFields[formFieldCount] = form.addChoiceField(ofs3.app.formLines[ofs3.session.formLineCnt], nil, 
                                                        {{i18n("app.modules.settings.txt_console"), 0}, {i18n("app.modules.settings.txt_consolefile"), 1}}, 
                                                        function() 
                                                            if ofs3.preferences and ofs3.preferences.developer then
                                                                if ofs3.preferences.developer.logtofile  == false then
                                                                    return 0
                                                                else
                                                                    return 1
                                                                end   
                                                            end
                                                        end, 
                                                        function(newValue) 
                                                            if ofs3.preferences and ofs3.preferences.developer then
                                                                local value
                                                                if newValue == 0 then
                                                                    value = false
                                                                else    
                                                                    value = true
                                                                end    
                                                                settings.logtofile = value
                                                            end    
                                                        end) 

    formFieldCount = formFieldCount + 1
    ofs3.session.formLineCnt = ofs3.session.formLineCnt + 1
    ofs3.app.formLines[ofs3.session.formLineCnt] = logpanel:addLine(i18n("app.modules.settings.txt_loglevel"))
    ofs3.app.formFields[formFieldCount] = form.addChoiceField(ofs3.app.formLines[ofs3.session.formLineCnt], nil, 
                                                        {{i18n("app.modules.settings.txt_off"), 0}, {i18n("app.modules.settings.txt_info"), 1}, {i18n("app.modules.settings.txt_debug"), 2}}, 
                                                        function() 
                                                            if ofs3.preferences and ofs3.preferences.developer then
                                                                if settings['loglevel']  == "off" then
                                                                    return 0
                                                                elseif settings['loglevel']  == "info" then
                                                                    return 1
                                                                else
                                                                    return 2
                                                                end   
                                                            end
                                                        end, 
                                                        function(newValue) 
                                                            if ofs3.preferences and ofs3.preferences.developer then
                                                                local value
                                                                if newValue == 0 then
                                                                    value = "off"
                                                                elseif newValue == 1 then
                                                                    value = "info"
                                                                else
                                                                    value = "debug"
                                                                end    
                                                                settings['loglevel'] = value 
                                                            end    
                                                        end) 
 
    formFieldCount = formFieldCount + 1
    ofs3.session.formLineCnt = ofs3.session.formLineCnt + 1
    ofs3.app.formLines[ofs3.session.formLineCnt] = logpanel:addLine(i18n("app.modules.settings.txt_mspdata"))
    ofs3.app.formFields[formFieldCount] = form.addBooleanField(ofs3.app.formLines[ofs3.session.formLineCnt], 
                                                        nil, 
                                                        function() 
                                                            if ofs3.preferences and ofs3.preferences.developer then
                                                                return settings['logmsp'] 
                                                            end
                                                        end, 
                                                        function(newValue) 
                                                            if ofs3.preferences and ofs3.preferences.developer then
                                                                settings.logmsp = newValue
                                                            end    
                                                        end)     

    formFieldCount = formFieldCount + 1
    ofs3.session.formLineCnt = ofs3.session.formLineCnt + 1
    ofs3.app.formLines[ofs3.session.formLineCnt] = logpanel:addLine(i18n("app.modules.settings.txt_queuesize"))
    ofs3.app.formFields[formFieldCount] = form.addBooleanField(ofs3.app.formLines[ofs3.session.formLineCnt], 
                                                        nil, 
                                                        function() 
                                                            if ofs3.preferences and ofs3.preferences.developer then
                                                                return settings['logmspQueue'] 
                                                            end
                                                        end, 
                                                        function(newValue) 
                                                            if ofs3.preferences and ofs3.preferences.developer then
                                                                settings.logmspQueue = newValue
                                                            end    
                                                        end)                                                             

    formFieldCount = formFieldCount + 1
    ofs3.session.formLineCnt = ofs3.session.formLineCnt + 1
    ofs3.app.formLines[ofs3.session.formLineCnt] = logpanel:addLine(i18n("app.modules.settings.txt_memusage"))
    ofs3.app.formFields[formFieldCount] = form.addBooleanField(ofs3.app.formLines[ofs3.session.formLineCnt], 
                                                        nil, 
                                                        function() 
                                                            if ofs3.preferences and ofs3.preferences.developer then
                                                                return settings['memstats'] 
                                                            end
                                                        end, 
                                                        function(newValue) 
                                                            if ofs3.preferences and ofs3.preferences.developer then
                                                                settings.memstats = newValue
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
end

local function onSaveMenu()
    local buttons = {
        {
            label  = i18n("app.btn_ok_long"),
            action = function()
                local msg = i18n("app.modules.profile_select.save_prompt_local")
                ofs3.app.ui.progressDisplaySave(msg:gsub("%?$", "."))
                for key, value in pairs(settings) do
                    ofs3.preferences.developer[key] = value
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
