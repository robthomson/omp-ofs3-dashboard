--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local toolbar = {}
local utils = ofs3.widgets.dashboard.utils

local function getThemeColors()
    return utils.getToolbarTheme()
end

local function getToolbarItems(dashboard)
    if type(dashboard.toolbarItems) == "table" then
        return dashboard.toolbarItems
    end

    return {
        {
            name = "@i18n(widgets.dashboard.toolbar_reset)@",
            subtitle = "@i18n(widgets.dashboard.toolbar_clear_session)@",
            onClick = function(state)
                if type(state.resetFlightModeAsk) == "function" then
                    state.resetFlightModeAsk()
                end
            end
        }
    }
end

local function getToolbarBounds()
    local width, height = lcd.getWindowSize()
    local barHeight = math.max(72, math.min(math.floor(height * 0.24), 118))
    return 0, height - barHeight, width, barHeight
end

local function drawToolbar(dashboard)
    if not dashboard.toolbarVisible then
        dashboard._toolbarRects = {}
        return
    end

    local colors = getThemeColors()
    local x, y, width, height = getToolbarBounds()
    local items = getToolbarItems(dashboard)
    local slotWidth = width / math.max(#items, 1)
    local rects = {}

    lcd.color(colors.background)
    lcd.drawFilledRectangle(x, y, width, height)
    lcd.color(colors.accent)
    lcd.drawFilledRectangle(x, y, width, 4)

    lcd.font(FONT_XS)

    for index, item in ipairs(items) do
        local itemX = math.floor(x + ((index - 1) * slotWidth) + 10)
        local itemW = math.floor(slotWidth - 20)
        local itemY = y + 14
        local itemH = height - 24
        local selected = dashboard.selectedToolbarIndex == index

        rects[index] = {x = itemX, y = itemY, w = itemW, h = itemH, item = item}

        lcd.color(selected and colors.accent or colors.panel)
        lcd.drawFilledRectangle(itemX, itemY, itemW, itemH)
        lcd.color(colors.border)
        lcd.drawRectangle(itemX, itemY, itemW, itemH, 2)

        lcd.color(selected and (colors.accentText or colors.text) or colors.text)
        lcd.drawText(itemX + math.floor(itemW / 2), itemY + 14, item.name or "@i18n(widgets.dashboard.toolbar_item)@", CENTERED)

        lcd.font(FONT_XXS)
        lcd.color(selected and (colors.accentText or colors.text) or colors.muted)
        lcd.drawText(itemX + math.floor(itemW / 2), itemY + itemH - 18, item.subtitle or "", CENTERED)
        lcd.font(FONT_XS)
    end

    dashboard._toolbarRects = rects
end

function toolbar.draw(dashboard)
    drawToolbar(dashboard)
end

function toolbar.handleEvent(dashboard, widget, category, value, x, y)
    if not dashboard.toolbarVisible then
        return false
    end

    local rects = dashboard._toolbarRects or {}
    local count = #rects
    if count == 0 then
        return false
    end

    if category == EVT_KEY and lcd.hasFocus() then
        if dashboard.touchToolbar then
            dashboard.touchToolbar()
        end
        local selected = dashboard.selectedToolbarIndex or 1

        if value == ROTARY_LEFT then
            selected = selected - 1
            if selected < 1 then
                selected = count
            end
            dashboard.selectedToolbarIndex = selected
            lcd.invalidate(widget)
            return true
        end

        if value == KEY_ROTARY_RIGHT then
            selected = selected + 1
            if selected > count then
                selected = 1
            end
            dashboard.selectedToolbarIndex = selected
            lcd.invalidate(widget)
            return true
        end

        if value == KEY_ENTER_BREAK then
            local rect = rects[selected]
            if rect and rect.item and type(rect.item.onClick) == "function" then
                rect.item.onClick(dashboard)
                lcd.invalidate(widget)
                return true
            end
        end

        if value == KEY_DOWN_BREAK or value == KEY_RTN_BREAK then
            if dashboard.closeToolbar then
                dashboard.closeToolbar()
            else
                dashboard.toolbarVisible = false
                dashboard.selectedToolbarIndex = nil
            end
            lcd.invalidate(widget)
            return true
        end
    end

    if category == EVT_TOUCH and (value == TOUCH_END or value == TOUCH_START) and x and y then
        if dashboard.touchToolbar then
            dashboard.touchToolbar()
        end
        for index, rect in ipairs(rects) do
            if x >= rect.x and x < (rect.x + rect.w) and y >= rect.y and y < (rect.y + rect.h) then
                dashboard.selectedToolbarIndex = index
                if rect.item and type(rect.item.onClick) == "function" then
                    rect.item.onClick(dashboard)
                end
                lcd.invalidate(widget)
                return true
            end
        end
    end

    return false
end

return toolbar
