

local i18n = ofs3.i18n.get

local S_PAGES = {
    {name = i18n("app.modules.settings.txt_audio_events"), script = "audio_events.lua", image = "audio_events.png"},
    {name = i18n("app.modules.settings.txt_audio_switches"), script = "audio_switches.lua", image = "audio_switches.png"},
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



    buttonW = 100
    local x = windowWidth - buttonW - 10

    ofs3.app.ui.fieldHeader(
        i18n(i18n("app.modules.settings.name") .. " / " .. i18n("app.modules.settings.audio"))
    )

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


    if ofs3.app.gfx_buttons["settings_dashboard"] == nil then ofs3.app.gfx_buttons["settings_dashboard"] = {} end
    if ofs3.preferences.menulastselected["settings_dashboard"] == nil then ofs3.preferences.menulastselected["settings_dashboard"] = 1 end


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
            if ofs3.app.gfx_buttons["settings_dashboard"][pidx] == nil then ofs3.app.gfx_buttons["settings_dashboard"][pidx] = lcd.loadMask("app/modules/settings/gfx/" .. pvalue.image) end
        else
            ofs3.app.gfx_buttons["settings_dashboard"][pidx] = nil
        end

        ofs3.app.formFields[pidx] = form.addButton(line, {x = bx, y = y, w = buttonW, h = buttonH}, {
            text = pvalue.name,
            icon = ofs3.app.gfx_buttons["settings_dashboard"][pidx],
            options = FONT_S,
            paint = function()
            end,
            press = function()
                ofs3.preferences.menulastselected["settings_dashboard"] = pidx
                ofs3.app.ui.progressDisplay()
                ofs3.app.ui.openPage(pidx, pvalue.folder, "settings/tools/" .. pvalue.script)
            end
        })

        if pvalue.disabled == true then ofs3.app.formFields[pidx]:enable(false) end

        if ofs3.preferences.menulastselected["settings_dashboard"] == pidx then ofs3.app.formFields[pidx]:focus() end

        lc = lc + 1

        if lc == numPerRow then lc = 0 end

    end

    ofs3.app.triggers.closeProgressLoader = true
    collectgarbage()
    return
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


local function onNavMenu()
    ofs3.app.ui.progressDisplay()
        ofs3.app.ui.openPage(
            pageIdx,
            i18n("app.modules.settings.name"),
            "settings/settings.lua"
        )
        return true
end

ofs3.app.uiState = ofs3.app.uiStatus.pages

return {
    pages = pages, 
    openPage = openPage,
    onNavMenu = onNavMenu,
    API = {},
    event = event,
    navButtons = {
        menu   = true,
        save   = false,
        reload = false,
        tool   = false,
        help   = false,
    },    
}
