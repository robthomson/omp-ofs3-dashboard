local i18n = ofs3.i18n.get

local themesBasePath = "SCRIPTS:/" .. ofs3.config.baseDir .. "/widgets/dashboard/themes/"
local themesUserPath = "SCRIPTS:/" .. ofs3.config.preferences .. "/dashboard/"

local function openPage(pidx, title, script)
    -- Get the installed themes
    local themeList = ofs3.widgets.dashboard.listThemes()

    ofs3.session.dashboardEditingTheme = nil
    enableWakeup = true
    ofs3.app.triggers.closeProgressLoader = true
    form.clear()


    ofs3.app.lastIdx    = pageIdx
    ofs3.app.lastTitle  = title
    ofs3.app.lastScript = script

    ofs3.app.ui.fieldHeader(
        i18n("app.modules.settings.name") .. " / " .. i18n("app.modules.settings.dashboard") .. " / " .. i18n("app.modules.settings.dashboard_settings")
    )

    -- Icon/button layout settings
    local buttonW, buttonH, padding, numPerRow
    if ofs3.preferences.general.iconsize == 0 then
        padding = ofs3.app.radio.buttonPaddingSmall
        buttonW = (ofs3.session.lcdWidth - padding) / ofs3.app.radio.buttonsPerRow - padding
        buttonH = ofs3.app.radio.navbuttonHeight
        numPerRow = ofs3.app.radio.buttonsPerRow
    elseif ofs3.preferences.general.iconsize == 1 then
        padding = ofs3.app.radio.buttonPaddingSmall
        buttonW = ofs3.app.radio.buttonWidthSmall
        buttonH = ofs3.app.radio.buttonHeightSmall
        numPerRow = ofs3.app.radio.buttonsPerRowSmall
    else
        padding = ofs3.app.radio.buttonPadding
        buttonW = ofs3.app.radio.buttonWidth
        buttonH = ofs3.app.radio.buttonHeight
        numPerRow = ofs3.app.radio.buttonsPerRow
    end

    -- Image cache table for theme icons
    if ofs3.app.gfx_buttons["settings_dashboard_themes"] == nil then
        ofs3.app.gfx_buttons["settings_dashboard_themes"] = {}
    end
    if ofs3.preferences.menulastselected["settings_dashboard_themes"] == nil then
        ofs3.preferences.menulastselected["settings_dashboard_themes"] = 1
    end

    local lc, bx, y = 0, 0, 0
    
    for idx, theme in ipairs(themeList) do

        if theme.configure then

            if lc == 0 then
                if ofs3.preferences.general.iconsize == 0 then y = form.height() + ofs3.app.radio.buttonPaddingSmall end
                if ofs3.preferences.general.iconsize == 1 then y = form.height() + ofs3.app.radio.buttonPaddingSmall end
                if ofs3.preferences.general.iconsize == 2 then y = form.height() + ofs3.app.radio.buttonPadding end
            end
            if lc >= 0 then bx = (buttonW + padding) * lc end

            -- Only load image once per theme index
            if ofs3.app.gfx_buttons["settings_dashboard_themes"][idx] == nil then

                local icon  
                if theme.source == "system" then
                    icon = themesBasePath .. theme.folder .. "/icon.png"
                else 
                    icon = themesUserPath .. theme.folder .. "/icon.png"
                end    
                ofs3.app.gfx_buttons["settings_dashboard_themes"][idx] = lcd.loadMask(icon)
            end

            ofs3.app.formFields[idx] = form.addButton(nil, {x = bx, y = y, w = buttonW, h = buttonH}, {
                text = theme.name,
                icon = ofs3.app.gfx_buttons["settings_dashboard_themes"][idx],
                options = FONT_S,
                paint = function() end,
                press = function()
                    -- Optional: your action when pressing a theme
                    -- Example: ofs3.app.ui.loadTheme(theme.folder)
                    ofs3.preferences.menulastselected["settings_dashboard_themes"] = idx
                ofs3.app.ui.progressDisplay()
                    local configure = theme.configure
                    local source = theme.source
                    local folder = theme.folder

                    local themeScript
                    if theme.source == "system" then
                        themeScript = themesBasePath .. folder .. "/" .. configure 
                    else 
                        themeScript = themesUserPath .. folder .. "/" .. configure 
                    end    

                    ofs3.app.ui.openPageDashboard(idx, theme.name,themeScript, source, folder)               
                end
            })

            if not theme.configure then
                ofs3.app.formFields[idx]:enable(false)
            end

            if ofs3.preferences.menulastselected["settings_dashboard_themes"] == idx then
                ofs3.app.formFields[idx]:focus()
            end

            lc = lc + 1
            if lc == numPerRow then lc = 0 end
        end   
    end

    if lc == 0 then
        local w, h = ofs3.utils.getWindowSize()
        local msg = i18n("app.modules.settings.no_themes_available_to_configure")
        local tw, th = lcd.getTextSize(msg)
        local x = w / 2 - tw / 2
        local y = h / 2 - th / 2
        local btnH = ofs3.app.radio.navbuttonHeight
        form.addStaticText(nil, { x = x, y = y, w = tw, h = btnH }, msg)
    end

    ofs3.app.triggers.closeProgressLoader = true
    collectgarbage()
    return
end


ofs3.app.uiState = ofs3.app.uiStatus.pages

local function event(widget, category, value, x, y)
    -- if close event detected go to section home page
    if category == EVT_CLOSE and value == 0 or value == 35 then
        ofs3.app.ui.openPage(
            pageIdx,
            i18n("app.modules.settings.dashboard"),
            "settings/tools/dashboard.lua"
        )
        return true
    end
end

local function onNavMenu()
    ofs3.app.ui.progressDisplay()
        ofs3.app.ui.openPage(
            pageIdx,
            i18n("app.modules.settings.dashboard"),
            "settings/tools/dashboard.lua"
        )
        return true
end

return {
    pages = pages, 
    openPage = openPage,
    API = {},
    navButtons = {
        menu   = true,
        save   = false,
        reload = false,
        tool   = false,
        help   = false,
    }, 
    event = event,
    onNavMenu = onNavMenu,
}
