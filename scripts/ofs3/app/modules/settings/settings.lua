local i18n = ofs3.i18n.get

local S_PAGES = {
    {name = i18n("app.modules.settings.txt_general"), script = "general.lua", image = "general.png"},
    {name = i18n("app.modules.settings.dashboard"), script = "dashboard.lua", image = "dashboard.png"},
    {name = i18n("app.modules.settings.localizations"), script = "localizations.lua", image = "localizations.png"},
    {name = i18n("app.modules.settings.audio"), script = "audio.lua", image = "audio.png"},
    {name = i18n("app.modules.settings.txt_development"), script = "development.lua", image = "development.png"},
}

local function openPage(pidx, title, script)



    ofs3.app.triggers.isReady = false
    ofs3.app.uiState = ofs3.app.uiStatus.mainMenu

    form.clear()

    ofs3.app.lastIdx = idx
    ofs3.app.lastTitle = title
    ofs3.app.lastScript = script

    ESC = {}

    -- size of buttons
    if ofs3.preferences.general.iconsize == nil or ofs3.preferences.general.iconsize == "" then
        ofs3.preferences.general.iconsize = 1
    else
        ofs3.preferences.general.iconsize = tonumber(ofs3.preferences.general.iconsize)
    end

    local w, h = ofs3.utils.getWindowSize()
    local windowWidth = w
    local windowHeight = h
    local padding = ofs3.app.radio.buttonPadding

    local sc
    local panel

    form.addLine(title)

    buttonW = 100
    local x = windowWidth - buttonW - 10

    ofs3.app.formNavigationFields['menu'] = form.addButton(line, {x = x, y = ofs3.app.radio.linePaddingTop, w = buttonW, h = ofs3.app.radio.navbuttonHeight}, {
        text = "MENU",
        icon = nil,
        options = FONT_S,
        paint = function()
        end,
        press = function()
            ofs3.app.lastIdx = nil
            ofs3.session.lastPage = nil

            if ofs3.app.Page and ofs3.app.Page.onNavMenu then ofs3.app.Page.onNavMenu(ofs3.app.Page) end

            ofs3.app.ui.openMainMenu()
        end
    })
    ofs3.app.formNavigationFields['menu']:focus()

    local buttonW
    local buttonH
    local padding
    local numPerRow

    -- TEXT ICONS
    -- TEXT ICONS
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


    if ofs3.app.gfx_buttons["settings"] == nil then ofs3.app.gfx_buttons["settings"] = {} end
    if ofs3.preferences.menulastselected["settings"] == nil then ofs3.preferences.menulastselected["settings"] = 1 end


    local Menu = assert(ofs3.compiler.loadfile("app/modules/" .. script))()
    local pages = S_PAGES
    local lc = 0
    local bx = 0



    for pidx, pvalue in ipairs(S_PAGES) do

        if lc == 0 then
            if ofs3.preferences.general.iconsize == 0 then y = form.height() + ofs3.app.radio.buttonPaddingSmall end
            if ofs3.preferences.general.iconsize == 1 then y = form.height() + ofs3.app.radio.buttonPaddingSmall end
            if ofs3.preferences.general.iconsize == 2 then y = form.height() + ofs3.app.radio.buttonPadding end
        end

        if lc >= 0 then bx = (buttonW + padding) * lc end

        if ofs3.preferences.general.iconsize ~= 0 then
            if ofs3.app.gfx_buttons["settings"][pidx] == nil then ofs3.app.gfx_buttons["settings"][pidx] = lcd.loadMask("app/modules/settings/gfx/" .. pvalue.image) end
        else
            ofs3.app.gfx_buttons["settings"][pidx] = nil
        end

        ofs3.app.formFields[pidx] = form.addButton(line, {x = bx, y = y, w = buttonW, h = buttonH}, {
            text = pvalue.name,
            icon = ofs3.app.gfx_buttons["settings"][pidx],
            options = FONT_S,
            paint = function()
            end,
            press = function()
                ofs3.preferences.menulastselected["settings"] = pidx
                ofs3.app.ui.progressDisplay()
                ofs3.app.ui.openPage(pidx, pvalue.folder, "settings/tools/" .. pvalue.script)
            end
        })

        if pvalue.disabled == true then ofs3.app.formFields[pidx]:enable(false) end

        if ofs3.preferences.menulastselected["settings"] == pidx then ofs3.app.formFields[pidx]:focus() end

        lc = lc + 1

        if lc == numPerRow then lc = 0 end

    end

    ofs3.app.triggers.closeProgressLoader = true
    collectgarbage()
    return
end

ofs3.app.uiState = ofs3.app.uiStatus.pages

return {
    pages = pages, 
    openPage = openPage,
    API = {},
}
