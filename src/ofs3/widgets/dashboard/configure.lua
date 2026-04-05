--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local configui = {}

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function addLine(parent, label)
    if parent and parent.addLine then
        return parent:addLine(label)
    end
    return form.addLine(label)
end

local function addPanel(title)
    if form.addExpansionPanel then
        local panel = form.addExpansionPanel(title)
        if panel and panel.open then
            panel:open(true)
        end
        return panel
    end
    form.addLine(title)
    return nil
end

local function ensureWidgetDefaults(widget)
    ofs3.runtime.readWidgetSettings(widget)
end

function configui.read(widget)
    ensureWidgetDefaults(widget)
    return true
end

function configui.write(widget)
    return ofs3.runtime.writeWidgetSettings(widget)
end

function configui.configure(widget)
    ensureWidgetDefaults(widget)

    local packPanel = addPanel("Battery Pack")

    local cellsLine = addLine(packPanel, "Cell Count")
    local cellsField = form.addNumberField(cellsLine, nil, 1, 14, function()
        return math.floor(tonumber(widget.batteryCellCount) or 3)
    end, function(value)
        widget.batteryCellCount = clamp(math.floor(tonumber(value) or 3), 1, 14)
    end)
    if cellsField and cellsField.suffix then
        cellsField:suffix("S")
    end

    local capacityLine = addLine(packPanel, "Capacity")
    local capacityField = form.addNumberField(capacityLine, nil, 100, 20000, function()
        return math.floor(tonumber(widget.batteryCapacity) or 750)
    end, function(value)
        widget.batteryCapacity = clamp(math.floor(tonumber(value) or 750), 100, 20000)
    end)
    if capacityField and capacityField.suffix then
        capacityField:suffix("mAh")
    end

    local voltagePanel = addPanel("Per-Cell Voltage")

    local minLine = addLine(voltagePanel, "Minimum")
    local minField = form.addNumberField(minLine, nil, 25, 45, function()
        return math.floor(((tonumber(widget.vbatmincellvoltage) or 3.3) * 10) + 0.5)
    end, function(value)
        local minValue = clamp((tonumber(value) or 33) / 10, 2.5, 4.2)
        widget.vbatmincellvoltage = minValue
        if tonumber(widget.vbatwarningcellvoltage) <= minValue then
            widget.vbatwarningcellvoltage = minValue + 0.1
        end
    end)
    if minField and minField.decimals then
        minField:decimals(1)
        minField:suffix("V")
    end

    local warnLine = addLine(voltagePanel, "Warning")
    local warnField = form.addNumberField(warnLine, nil, 25, 45, function()
        return math.floor(((tonumber(widget.vbatwarningcellvoltage) or 3.5) * 10) + 0.5)
    end, function(value)
        local minValue = tonumber(widget.vbatmincellvoltage) or 3.3
        local warnValue = clamp((tonumber(value) or 35) / 10, minValue + 0.1, 4.35)
        widget.vbatwarningcellvoltage = warnValue
        if tonumber(widget.vbatfullcellvoltage) < warnValue then
            widget.vbatfullcellvoltage = warnValue
        end
    end)
    if warnField and warnField.decimals then
        warnField:decimals(1)
        warnField:suffix("V")
    end

    local fullLine = addLine(voltagePanel, "Full")
    local fullField = form.addNumberField(fullLine, nil, 30, 45, function()
        return math.floor(((tonumber(widget.vbatfullcellvoltage) or 4.1) * 10) + 0.5)
    end, function(value)
        local warnValue = tonumber(widget.vbatwarningcellvoltage) or 3.5
        local fullValue = clamp((tonumber(value) or 41) / 10, warnValue, 4.35)
        widget.vbatfullcellvoltage = fullValue
        if tonumber(widget.vbatmaxcellvoltage) < fullValue then
            widget.vbatmaxcellvoltage = fullValue
        end
    end)
    if fullField and fullField.decimals then
        fullField:decimals(1)
        fullField:suffix("V")
    end

    local maxLine = addLine(voltagePanel, "Maximum")
    local maxField = form.addNumberField(maxLine, nil, 35, 46, function()
        return math.floor(((tonumber(widget.vbatmaxcellvoltage) or 4.3) * 10) + 0.5)
    end, function(value)
        local fullValue = tonumber(widget.vbatfullcellvoltage) or 4.1
        widget.vbatmaxcellvoltage = clamp((tonumber(value) or 43) / 10, fullValue, 4.5)
    end)
    if maxField and maxField.decimals then
        maxField:decimals(1)
        maxField:suffix("V")
    end

    local reservePanel = addPanel("Warnings")

    local lvcLine = addLine(reservePanel, "LVC Reserve")
    local lvcField = form.addNumberField(lvcLine, nil, 0, 80, function()
        return math.floor(tonumber(widget.lvcPercentage) or 30)
    end, function(value)
        widget.lvcPercentage = clamp(math.floor(tonumber(value) or 30), 0, 80)
    end)
    if lvcField and lvcField.suffix then
        lvcField:suffix("%")
    end

    local fuelLine = addLine(reservePanel, "Fuel Warning")
    local fuelField = form.addNumberField(fuelLine, nil, 0, 80, function()
        return math.floor(tonumber(widget.consumptionWarningPercentage) or 30)
    end, function(value)
        widget.consumptionWarningPercentage = clamp(math.floor(tonumber(value) or 30), 0, 80)
    end)
    if fuelField and fuelField.suffix then
        fuelField:suffix("%")
    end
end

return configui
