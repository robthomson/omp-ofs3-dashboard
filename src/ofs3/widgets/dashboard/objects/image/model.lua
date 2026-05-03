--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local render = {}

local utils = ofs3.widgets.dashboard.utils
local getParam = utils.getParam
local resolveThemeColor = utils.resolveThemeColor
local loadImage = ofs3.utils.loadImage

function render.invalidate(box) box._cfg = nil end

function render.dirty(box)
    if box._lastDisplayValue == nil then
        box._lastDisplayValue = box._currentDisplayValue
        return true
    end
    if box._lastDisplayValue ~= box._currentDisplayValue then
        box._lastDisplayValue = box._currentDisplayValue
        return true
    end
    return false
end

local _imgCache = {}

local function tryLoadImage(path)
    if type(path) ~= "string" or path == "" or not loadImage then return nil end
    if path:match("%.png$") or path:match("%.bmp$") then
        return loadImage(path)
    end
    return loadImage(path .. ".png") or loadImage(path .. ".bmp") or loadImage(path)
end

local function getBitmapCandidates(bitmap)
    if type(bitmap) ~= "string" or bitmap == "" then return {} end
    local candidates = {bitmap}
    if bitmap:match("^/bitmaps/") then
        candidates[#candidates + 1] = bitmap:gsub("^/bitmaps", "BITMAPS:", 1)
    elseif bitmap:match("^/scripts/") then
        candidates[#candidates + 1] = bitmap:gsub("^/scripts", "SCRIPTS:", 1)
    elseif bitmap:match("^/system/") then
        candidates[#candidates + 1] = bitmap:gsub("^/system", "SYSTEM:", 1)
    elseif not bitmap:match("^[A-Z]+:") and not bitmap:match("^/") then
        candidates[#candidates + 1] = "BITMAPS:/models/" .. bitmap
    end
    return candidates
end

local function resolveModelImage(cfg)

    local craftName = ofs3 and ofs3.session and ofs3.session.craftName
    if craftName and craftName ~= "" then
        local cached = _imgCache[craftName]
        if cached == nil then
            cached = tryLoadImage("BITMAPS:/models/" .. craftName)
            _imgCache[craftName] = cached or false
        end
        if cached then return cached end
    end

    if model and model.bitmap then
        local bm = model.bitmap()
        if bm then
            if type(bm) == "userdata" then return bm end
            if type(bm) == "string" and bm ~= "" and not string.find(bm, "default_") then
                local candidates = getBitmapCandidates(bm)
                for i = 1, #candidates do
                    local loaded = tryLoadImage(candidates[i])
                    if loaded then return loaded end
                end
            end
        end
    end

    local paramImage = getParam(cfg.box, "image")
    if paramImage and paramImage ~= "" then
        local loaded = tryLoadImage(paramImage)
        if loaded then return loaded end
        return paramImage
    end

    return "widgets/dashboard/gfx/logo.png"
end

local function ensureCfg(box)
    local theme_version = (ofs3 and ofs3.theme and ofs3.theme.version) or 0
    local param_version = box._param_version or 0
    local cfg = box._cfg
    if (not cfg) or (cfg._theme_version ~= theme_version) or (cfg._param_version ~= param_version) then
        cfg = {}
        cfg._theme_version = theme_version
        cfg._param_version = param_version
        cfg.box = box

        cfg.title = getParam(box, "title")
        cfg.titlepos = getParam(box, "titlepos")
        cfg.titlealign = getParam(box, "titlealign")
        cfg.titlefont = getParam(box, "titlefont")
        cfg.titlespacing = getParam(box, "titlespacing")
        cfg.titlecolor = resolveThemeColor("titlecolor", getParam(box, "titlecolor"))
        cfg.titlepadding = getParam(box, "titlepadding")
        cfg.titlepaddingleft = getParam(box, "titlepaddingleft")
        cfg.titlepaddingright = getParam(box, "titlepaddingright")
        cfg.titlepaddingtop = getParam(box, "titlepaddingtop")
        cfg.titlepaddingbottom = getParam(box, "titlepaddingbottom")

        cfg.valuepadding = getParam(box, "valuepadding")
        cfg.valuepaddingleft = getParam(box, "valuepaddingleft")
        cfg.valuepaddingright = getParam(box, "valuepaddingright")
        cfg.valuepaddingtop = getParam(box, "valuepaddingtop")
        cfg.valuepaddingbottom = getParam(box, "valuepaddingbottom")

        cfg.bgcolor = resolveThemeColor("bgcolor", getParam(box, "bgcolor"))

        cfg.imagewidth = getParam(box, "imagewidth")
        cfg.imageheight = getParam(box, "imageheight")
        cfg.imagealign = getParam(box, "imagealign")

        cfg.image = resolveModelImage(cfg)

        box._cfg = cfg
    end
    return box._cfg
end

function render.wakeup(box)
    local cfg = ensureCfg(box)

    local craftName = ofs3 and ofs3.session and ofs3.session.craftName
    if cfg._lastCraftName ~= craftName then
        cfg.image = resolveModelImage(cfg)
        cfg._lastCraftName = craftName
    end

    box._currentDisplayValue = cfg.image
end

function render.paint(x, y, w, h, box)
    x, y = utils.applyOffset(x, y, box)
    local c = box._cfg or {}

    utils.box(x, y, w, h, c.title, c.titlepos, c.titlealign, c.titlefont, c.titlespacing, c.titlecolor, c.titlepadding, c.titlepaddingleft, c.titlepaddingright, c.titlepaddingtop, c.titlepaddingbottom, nil, nil, nil, nil, nil, c.valuepadding, c.valuepaddingleft, c.valuepaddingright,
        c.valuepaddingtop, c.valuepaddingbottom, c.bgcolor, c.image, c.imagewidth, c.imageheight, c.imagealign)
end

render.scheduler = 2.0

return render
