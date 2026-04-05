--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local utils = {}

local imageCache = {}
local fontCache
local DASHBOARD_RESOLUTION_TOLERANCE = 12
local DASHBOARD_SUPPORTED_RESOLUTIONS = {
    {784, 294}, {784, 316}, {800, 458}, {800, 480},
    {472, 191}, {472, 210}, {480, 301}, {480, 320},
    {630, 236}, {630, 258}, {640, 338}, {640, 360}
}
local DASHBOARD_THEME_WIDTHS = {800, 784, 640, 630, 480, 472}

local function resolveDashboardSize(W, H)
    local version = system.getVersion and system.getVersion() or {}
    W = tonumber(W) or tonumber(version.lcdWidth) or 800
    H = tonumber(H) or tonumber(version.lcdHeight) or 480
    return W, H
end

local function findClosestDashboardResolution(W, H, supportedResolutions)
    W, H = resolveDashboardSize(W, H)
    local bestRes, bestDistance
    local resolutions = supportedResolutions or DASHBOARD_SUPPORTED_RESOLUTIONS

    for _, res in ipairs(resolutions) do
        local distance = math.abs(W - res[1]) + math.abs(H - res[2])
        if bestDistance == nil or distance < bestDistance then
            bestRes = res
            bestDistance = distance
        end
    end

    return bestRes, bestDistance
end

local function getClosestDashboardWidth(W)
    W = select(1, resolveDashboardSize(W, nil))
    local bestWidth, bestDistance

    for i = 1, #DASHBOARD_THEME_WIDTHS do
        local width = DASHBOARD_THEME_WIDTHS[i]
        local distance = math.abs(W - width)
        if bestDistance == nil or distance < bestDistance then
            bestWidth = width
            bestDistance = distance
        end
    end

    return bestWidth
end

function utils.matchSupportedResolution(W, H, supportedResolutions, maxDistance)
    W, H = resolveDashboardSize(W, H)
    local bestRes, bestDistance = findClosestDashboardResolution(W, H, supportedResolutions)
    local tolerance = maxDistance or DASHBOARD_RESOLUTION_TOLERANCE

    if bestRes and bestDistance ~= nil and bestDistance <= tolerance then
        return bestRes[1], bestRes[2], bestDistance
    end

    return nil
end

function utils.isFullScreen(w, h)
    w, h = resolveDashboardSize(w, h)
    local matchedW = utils.matchSupportedResolution(w, h)

    if matchedW == 800 or matchedW == 480 or matchedW == 640 then return true end
    if matchedW == 784 or matchedW == 472 or matchedW == 630 then return false end

    return nil
end

function utils.isModelPrefsReady() return ofs3 and ofs3.session and ofs3.session.modelPreferences end

function utils.resetBoxCache(box) if box._cache then for k in pairs(box._cache) do box._cache[k] = nil end end end

function utils.supportedResolution(W, H, supportedResolutions)
    return utils.matchSupportedResolution(W, H, supportedResolutions) ~= nil
end

function utils.drawBarNeedle(cx, cy, length, thickness, angleDeg, color)
    local angleRad = math.rad(angleDeg)
    local step = 1
    local rad_thick = thickness / 2
    lcd.color(color)
    for i = 0, length, step do
        local px = cx + i * math.cos(angleRad)
        local py = cy + i * math.sin(angleRad)
        lcd.drawFilledCircle(px, py, rad_thick)
    end
end

function utils.getFontListsForResolution()
    local version = system.getVersion()
    local LCD_W = version.lcdWidth
    local LCD_H = version.lcdHeight
    local resolution = LCD_W .. "x" .. LCD_H

    local radios = {

        ["800x480"] = {value_default = {FONT_XXS, FONT_XS, FONT_S, FONT_STD, FONT_L, FONT_XL, FONT_XXL, FONT_XXXXL}, value_reduced = {FONT_XXS, FONT_XS, FONT_S, FONT_STD, FONT_L}, value_title = {FONT_XXS, FONT_XS, FONT_S, FONT_STD}},

        ["480x320"] = {value_default = {FONT_XXS, FONT_XS, FONT_S, FONT_STD, FONT_L, FONT_XL}, value_reduced = {FONT_XXS, FONT_XS, FONT_S, FONT_STD, FONT_L}, value_title = {FONT_XXS, FONT_XS, FONT_S}},

        ["480x272"] = {value_default = {FONT_XXS, FONT_XS, FONT_S, FONT_STD}, value_reduced = {FONT_XXS, FONT_XS, FONT_S}, value_title = {FONT_XXS, FONT_XS, FONT_S}},

        ["640x360"] = {value_default = {FONT_XXS, FONT_XS, FONT_S, FONT_STD, FONT_L, FONT_XL}, value_reduced = {FONT_XXS, FONT_XS, FONT_S, FONT_STD, FONT_L}, value_title = {FONT_XXS, FONT_XS, FONT_S}}
    }
    if not radios[resolution] then
        ofs3.utils.log("Unsupported resolution: " .. resolution .. ". Using default fonts.", "info")
        return radios["800x480"]
    end
    return radios[resolution]

end

function utils.getHeaderOptions()
    local W, H = lcd.getWindowSize()
    W, H = resolveDashboardSize(W, H)
    local matchedW = getClosestDashboardWidth(W)

    if matchedW == 800 or matchedW == 784 then
        return {
            height = 36,
            font = "FONT_L",
            batterysegmentpaddingtop = 4,
            batterysegmentpaddingbottom = 4,
            batterysegmentpaddingleft = 4,
            batterysegmentpaddingright = 4,
            gaugepaddingleft = 25,
            gaugepaddingright = 26,
            gaugepaddingbottom = 2,
            gaugepaddingtop = 2,
            barpaddingleft = 25,
            barpaddingright = 28,
            barpaddingbottom = 2,
            barpaddingtop = 4,
            valuepaddingleft = 20,
            valuepaddingbottom = 20
        }

    elseif matchedW == 480 or matchedW == 472 then
        return {
            height = 30,
            font = "FONT_L",
            batterysegmentpaddingtop = 4,
            batterysegmentpaddingbottom = 4,
            batterysegmentpaddingleft = 4,
            batterysegmentpaddingright = 4,
            gaugepaddingleft = 8,
            gaugepaddingright = 9,
            gaugepaddingbottom = 2,
            gaugepaddingtop = 2,
            barpaddingleft = 15,
            barpaddingright = 18,
            barpaddingbottom = 2,
            barpaddingtop = 2,
            valuepaddingbottom = 20
        }

    elseif matchedW == 640 or matchedW == 630 then
        return {
            height = 30,
            font = "FONT_L",
            batterysegmentpaddingtop = 4,
            batterysegmentpaddingbottom = 4,
            batterysegmentpaddingleft = 4,
            batterysegmentpaddingright = 4,
            gaugepaddingleft = 21,
            gaugepaddingright = 23,
            gaugepaddingbottom = 2,
            gaugepaddingtop = 2,
            barpaddingleft = 19,
            barpaddingright = 21,
            barpaddingbottom = 2,
            barpaddingtop = 2,
            valuepaddingbottom = 20
        }
    end

    return {
        height = 36,
        font = "FONT_L",
        batterysegmentpaddingtop = 4,
        batterysegmentpaddingbottom = 4,
        batterysegmentpaddingleft = 4,
        batterysegmentpaddingright = 4,
        gaugepaddingleft = 25,
        gaugepaddingright = 26,
        gaugepaddingbottom = 2,
        gaugepaddingtop = 2,
        barpaddingleft = 25,
        barpaddingright = 28,
        barpaddingbottom = 2,
        barpaddingtop = 4,
        valuepaddingleft = 20,
        valuepaddingbottom = 20
    }
end

function utils.resetImageCache() for k in pairs(imageCache) do imageCache[k] = nil end end

function utils.screenError(msg, border, pct, padX, padY)

    if not pct then pct = 0.5 end
    if border == nil then border = true end
    if not padX then padX = 8 end
    if not padY then padY = 4 end

    local w, h = lcd.getWindowSize()
    local isDarkMode = lcd.darkMode()

    local fonts = {FONT_XXS, FONT_XS, FONT_S, FONT_STD, FONT_L, FONT_XL, FONT_XXL, FONT_XXXXL}

    local maxW, maxH = w * pct, h * pct
    local bestFont, bestW, bestH = FONT_XXS, 0, 0

    for _, font in ipairs(fonts) do
        lcd.font(font)
        local tsizeW, tsizeH = lcd.getTextSize(msg)
        if tsizeW <= maxW and tsizeH <= maxH then
            bestFont = font
            bestW, bestH = tsizeW, tsizeH
        else
            break
        end
    end

    lcd.font(bestFont)

    local textColor = isDarkMode and lcd.RGB(255, 255, 255, 1) or lcd.RGB(90, 90, 90)
    lcd.color(textColor)

    local x = (w - bestW) / 2
    local y = (h - bestH) / 2

    if border then lcd.drawRectangle(x - padX, y - padY, bestW + padX * 2, bestH + padY * 2) end

    lcd.drawText(x, y, msg)
end

function utils.resolveColor(value, variantFactor)

    local namedColors = {
        red = {255, 0, 0},
        green = {0, 188, 4},
        blue = {0, 122, 255},
        white = {255, 255, 255},
        black = {0, 0, 0},
        gray = {185, 185, 185},
        grey = {185, 185, 185},
        orange = {255, 165, 0},
        yellow = {255, 255, 0},
        cyan = {0, 255, 255},
        magenta = {255, 0, 255},
        pink = {255, 105, 180},
        purple = {128, 0, 128},
        violet = {143, 0, 255},
        brown = {139, 69, 19},
        lime = {0, 255, 0},
        olive = {128, 128, 0},
        gold = {255, 215, 0},
        silver = {192, 192, 192},
        teal = {0, 128, 128},
        navy = {0, 0, 128},
        maroon = {128, 0, 0},
        beige = {245, 245, 220},
        turquoise = {64, 224, 208},
        indigo = {75, 0, 130},
        coral = {255, 127, 80},
        salmon = {250, 128, 114},
        mint = {62, 180, 137},
        lightgreen = {144, 238, 144},
        darkgreen = {0, 100, 0},
        lightred = {255, 102, 102},
        darkred = {139, 0, 0},
        lightorange = {255, 200, 100},
        lightblue = {173, 216, 230},
        darkblue = {0, 0, 139},
        lightpurple = {216, 191, 216},
        darkpurple = {48, 25, 52},
        lightyellow = {255, 255, 224},
        darkyellow = {204, 204, 0},
        lightgrey = {211, 211, 211},
        lightgray = {211, 211, 211},
        darkgrey = {90, 90, 90},
        darkgray = {90, 90, 90},
        lmgrey = {80, 80, 80},
        darkwhite = {245, 245, 245}
    }

    local VARIANT_FACTOR = type(variantFactor) == "number" and math.max(0, math.min(1, variantFactor)) or 0.3

    local function clamp(v) return math.max(0, math.min(255, math.floor(v + 0.5))) end

    local function lighten(rgb) return {clamp(rgb[1] + (255 - rgb[1]) * VARIANT_FACTOR), clamp(rgb[2] + (255 - rgb[2]) * VARIANT_FACTOR), clamp(rgb[3] + (255 - rgb[3]) * VARIANT_FACTOR)} end

    local function darken(rgb) return {clamp(rgb[1] * (1 - VARIANT_FACTOR)), clamp(rgb[2] * (1 - VARIANT_FACTOR)), clamp(rgb[3] * (1 - VARIANT_FACTOR))} end

    if type(value) == "string" then
        local lower = value:lower()

        local prefix, baseName = lower:match("^(bright)(.+)"), lower:match("^bright(.+)")
        if not prefix then prefix, baseName = lower:match("^(light)(.+)"), lower:match("^light(.+)") end
        if not prefix then prefix, baseName = lower:match("^(dark)(.+)"), lower:match("^dark(.+)") end

        if prefix and baseName then
            local baseColor = namedColors[baseName]
            if baseColor then
                local rgb = (prefix == "dark") and darken(baseColor) or lighten(baseColor)
                return lcd.RGB(rgb[1], rgb[2], rgb[3], 1)
            end

        elseif namedColors[lower] then

            local c = namedColors[lower]
            return lcd.RGB(c[1], c[2], c[3], 1)
        end

    elseif type(value) == "table" and #value >= 3 then

        return lcd.RGB(value[1], value[2], value[3], 1)
    end

    return nil
end

function utils.resolveThemeColor(colorkey, value)

    if type(value) == "number" then return value end

    if type(value) == "string" and value == "transparent" then return nil end

    if type(value) == "string" then
        local resolved = utils.resolveColor(value)
        if resolved then return resolved end
    end

    if colorkey == "fillcolor" then
        return lcd.darkMode() and lcd.RGB(40, 40, 40) or lcd.RGB(240, 240, 240)
    elseif colorkey == "fillbgcolor" then
        return lcd.darkMode() and lcd.RGB(40, 40, 40) or lcd.RGB(240, 240, 240)
    elseif colorkey == "framecolor" then
        return lcd.darkMode() and lcd.RGB(40, 40, 40) or lcd.RGB(240, 240, 240)
    elseif colorkey == "textcolor" then
        return lcd.RGB(255, 255, 255)
    elseif colorkey == "titlecolor" then
        return lcd.RGB(255, 255, 255)
    elseif colorkey == "accentcolor" then
        return lcd.RGB(255, 255, 255)
    end

    return lcd.darkMode() and lcd.RGB(40, 40, 40) or lcd.RGB(240, 240, 240)
end

function utils.resolveThemeColorArray(colorkey, arr)
    local resolved = {}
    if type(arr) == "table" then for i = 1, #arr do resolved[i] = utils.resolveThemeColor(colorkey, arr[i]) end end
    return resolved
end

function utils.box(x, y, w, h, title, titlepos, titlealign, titlefont, titlespacing, titlecolor, titlepadding, titlepaddingleft, titlepaddingright, titlepaddingtop, titlepaddingbottom, displayValue, unit, font, valuealign, textcolor, valuepadding, valuepaddingleft, valuepaddingright,
                   valuepaddingtop, valuepaddingbottom, bgcolor, image, imagewidth, imageheight, imagealign)

    local DEFAULT_TITLE_PADDING = 0
    local DEFAULT_VALUE_PADDING = 6
    local DEFAULT_TITLE_SPACING = 6

    titlepaddingleft = titlepaddingleft or titlepadding or DEFAULT_TITLE_PADDING
    titlepaddingright = titlepaddingright or titlepadding or DEFAULT_TITLE_PADDING
    titlepaddingtop = titlepaddingtop or titlepadding or DEFAULT_TITLE_PADDING
    titlepaddingbottom = titlepaddingbottom or titlepadding or DEFAULT_TITLE_PADDING

    valuepaddingleft = valuepaddingleft or valuepadding or DEFAULT_VALUE_PADDING
    valuepaddingright = valuepaddingright or valuepadding or DEFAULT_VALUE_PADDING
    valuepaddingtop = valuepaddingtop or valuepadding or DEFAULT_VALUE_PADDING
    valuepaddingbottom = valuepaddingbottom or valuepadding or DEFAULT_VALUE_PADDING

    titlespacing = titlespacing or DEFAULT_TITLE_SPACING

    if bgcolor then
        lcd.color(bgcolor)
        lcd.drawFilledRectangle(x, y, w, h)
    end

    if not fontCache then fontCache = utils.getFontListsForResolution() end

    local actualTitleFont, tsizeW, tsizeH = nil, 0, 0
    if title then
        local minValueFontH = 9999
        for _, vf in ipairs(fontCache.value_default or {FONT_STD}) do
            lcd.font(vf)
            local _, vh = lcd.getTextSize("8")
            if vh < minValueFontH then minValueFontH = vh end
        end
        if titlefont and _G[titlefont] then
            actualTitleFont = _G[titlefont]
            lcd.font(actualTitleFont)
            tsizeW, tsizeH = lcd.getTextSize(title)
        else
            for _, tryFont in ipairs(fontCache.value_title or {FONT_XS}) do
                lcd.font(tryFont)
                local tW, tH = lcd.getTextSize(title)
                local remH = h - titlepaddingtop - tH - titlepaddingbottom - valuepaddingtop - valuepaddingbottom
                if tW <= w - titlepaddingleft - titlepaddingright and tH > 0 and remH >= minValueFontH then
                    actualTitleFont, tsizeW, tsizeH = tryFont, tW, tH
                    break
                end
            end
            if not actualTitleFont then
                actualTitleFont = (fontCache.value_title or {FONT_XS})[#(fontCache.value_title or {FONT_XS})]
                lcd.font(actualTitleFont)
                tsizeW, tsizeH = lcd.getTextSize(title)
            end
        end
    end

    local region_vx, region_vy, region_vw, region_vh
    if title and (titlepos or "top") == "top" then
        region_vy = y + titlepaddingtop + tsizeH + titlepaddingbottom + titlespacing + valuepaddingtop
        region_vh = h - (region_vy - y) - valuepaddingbottom
    elseif title and titlepos == "bottom" then
        region_vy = y + valuepaddingtop
        region_vh = h - tsizeH - titlepaddingtop - titlepaddingbottom - titlespacing - valuepaddingtop - valuepaddingbottom
    else
        region_vy = y + valuepaddingtop
        region_vh = h - valuepaddingtop - valuepaddingbottom
    end
    region_vx = x + valuepaddingleft
    region_vw = w - valuepaddingleft - valuepaddingright

    if image then
        local bitmapPtr = nil

        if type(image) == "string" and ofs3 and ofs3.utils and ofs3.utils.loadImage then
            imageCache = imageCache or {}
            local cacheKey = image or "default_image"
            bitmapPtr = imageCache[cacheKey]
            if not bitmapPtr then
                bitmapPtr = ofs3.utils.loadImage(image, nil, "widgets/dashboard/gfx/logo.png")
                imageCache[cacheKey] = bitmapPtr
            end
        elseif type(image) == "userdata" then

            bitmapPtr = image
        end

        if bitmapPtr then

            local default_img_w = region_vw
            local default_img_h = region_vh
            local img_w = imagewidth or default_img_w
            local img_h = imageheight or default_img_h
            local align = imagealign or "center"
            local img_x, img_y = region_vx, region_vy
            if align == "center" then
                img_x = region_vx + (region_vw - img_w) / 2
            elseif align == "right" then
                img_x = region_vx + region_vw - img_w
            else
                img_x = region_vx
            end
            if align == "center" then
                img_y = region_vy + (region_vh - img_h) / 2
            elseif align == "bottom" then
                img_y = region_vy + region_vh - img_h
            else
                img_y = region_vy
            end
            lcd.drawBitmap(img_x, img_y, bitmapPtr, img_w, img_h)
        end
    elseif displayValue ~= nil then

        local value_str = tostring(displayValue) .. (unit or "")

        local value_str_calc = string.gsub(value_str, "[%%]", "W")
        value_str_calc = string.gsub(value_str, "[°]", ".")

        local valueFont, bestW, bestH = FONT_XXS, 0, 0
        if font and _G[font] then
            valueFont = _G[font]
            lcd.font(valueFont)

            bestW, bestH = lcd.getTextSize(value_str_calc)
        else
            for _, tryFont in ipairs(fontCache.value_default) do
                lcd.font(tryFont)
                local tW, tH = lcd.getTextSize(value_str_calc)
                if tW <= region_vw and tH <= region_vh then valueFont, bestW, bestH = tryFont, tW, tH end
            end
            lcd.font(valueFont)
        end

        local fudgeTitle = (title and (titlepos or "top") == "top") and -math.floor(bestH * 0.15 + 0.5) or (title and titlepos == "bottom") and math.floor(bestH * 0.15 + 0.5) or 0

        local sy = region_vy + ((region_vh - bestH) / 2) + fudgeTitle
        local align = (valuealign or "center"):lower()
        local sx
        if align == "left" then
            sx = region_vx
        elseif align == "right" then
            sx = region_vx + region_vw - bestW
        else
            sx = region_vx + (region_vw - bestW) / 2
        end
        lcd.color(textcolor)
        lcd.drawText(sx, sy, value_str)
    end

    if title then
        lcd.font(actualTitleFont)
        local region_tw = w - titlepaddingleft - titlepaddingright
        local sy = (titlepos or "top") == "bottom" and (y + h - titlepaddingbottom - tsizeH) or (y + titlepaddingtop)
        local align = (titlealign or "center"):lower()
        local sx
        if align == "left" then
            sx = x + titlepaddingleft
        elseif align == "right" then
            sx = x + titlepaddingleft + region_tw - tsizeW
        else
            sx = x + titlepaddingleft + (region_tw - tsizeW) / 2
        end
        lcd.color(titlecolor)
        lcd.drawText(sx, sy, title)
    end
end

function utils.resolveThresholdColor(value, box, colorKey, fallbackThemeKey, thresholdsOverride)
    local color = utils.resolveThemeColor(fallbackThemeKey, utils.getParam(box, colorKey))
    local thresholds = thresholdsOverride or utils.getParam(box, "thresholds")
    if thresholds and value ~= nil then
        for _, t in ipairs(thresholds) do
            local thresholdValue = t.value
            if type(thresholdValue) == "function" then thresholdValue = thresholdValue(box, value) end

            if type(value) == "string" and thresholdValue == value and t[colorKey] then
                color = utils.resolveThemeColor(colorKey, t[colorKey])
                break
            elseif type(value) == "number" and type(thresholdValue) == "number" and value <= thresholdValue and t[colorKey] then
                color = utils.resolveThemeColor(colorKey, t[colorKey])
                break
            end
        end
    end
    return color
end

function utils.transformValue(value, box)

    local transform = utils.getParam(box, "transform")

    if transform then
        if type(transform) == "function" then
            value = transform(value)
        elseif transform == "floor" then
            value = math.floor(value)
        elseif transform == "ceil" then
            value = math.ceil(value)
        elseif transform == "round" then
            value = math.floor(value + 0.5)
        end
    end
    local decimals = utils.getParam(box, "decimals")

    if decimals ~= nil and value ~= nil then
        value = string.format("%." .. decimals .. "f", value)
    elseif value ~= nil then
        value = tostring(value)
    end
    return value
end

function utils.setBackgroundColourBasedOnTheme()
    local w, h = lcd.getWindowSize()
    if lcd.darkMode() then
        lcd.color(lcd.RGB(16, 16, 16))
    else
        lcd.color(lcd.RGB(209, 208, 208))
    end
    lcd.drawFilledRectangle(0, 0, w, h)
end

function utils.getParam(box, key, ...)
    local SKIP_CALL_KEYS = {transform = true, thresholds = true, value = true}

    local v = box[key]
    if type(v) == "function" and not SKIP_CALL_KEYS[key] then
        return v(box, key, ...)
    else
        return v
    end
end

function utils.applyOffset(x, y, box)
    local ox = utils.getParam(box, "offsetx") or 0
    local oy = utils.getParam(box, "offsety") or 0
    return x + ox, y + oy
end

return utils
