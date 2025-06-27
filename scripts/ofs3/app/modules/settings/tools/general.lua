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
        i18n("app.modules.settings.name") .. " / " .. i18n("app.modules.settings.txt_general")
    )
    ofs3.session.formLineCnt = 0

    local formFieldCount = 0

    settings = ofs3.preferences.general

    -- Icon size choice field
    formFieldCount = formFieldCount + 1
    ofs3.session.formLineCnt = ofs3.session.formLineCnt + 1
    ofs3.app.formLines[ofs3.session.formLineCnt] = form.addLine(
        i18n("app.modules.settings.txt_iconsize")
    )
    ofs3.app.formFields[formFieldCount] = form.addChoiceField(
        ofs3.app.formLines[ofs3.session.formLineCnt],
        nil,
        {
            { i18n("app.modules.settings.txt_text"),  0 },
            { i18n("app.modules.settings.txt_small"), 1 },
            { i18n("app.modules.settings.txt_large"), 2 },
        },
        function()
            if ofs3.preferences and ofs3.preferences.general and ofs3.preferences.general.iconsize then
                return settings.iconsize
            else
                return 1
            end
        end,
        function(newValue)
            if ofs3.preferences and ofs3.preferences.general then
                settings.iconsize = newValue
            end
        end
    )


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
                    ofs3.preferences.general[key] = value
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
