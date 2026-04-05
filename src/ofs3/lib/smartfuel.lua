--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local batteryConfigCache = nil
local fuelStartingPercent = nil
local fuelStartingConsumption = nil

local lastVoltages = {}
local maxVoltageSamples = 5
local voltageStabilised = false
local stabilizeNotBefore = nil
local voltageThreshold = 0.15
local preStabiliseDelay = 1.5

local function resetVoltageTracking()
    lastVoltages = {}
    voltageStabilised = false
end

local function isVoltageStable()
    if #lastVoltages < maxVoltageSamples then
        return false
    end

    local minVoltage = lastVoltages[1]
    local maxVoltage = lastVoltages[1]

    for _, value in ipairs(lastVoltages) do
        if value < minVoltage then
            minVoltage = value
        end
        if value > maxVoltage then
            maxVoltage = value
        end
    end

    return (maxVoltage - minVoltage) <= voltageThreshold
end

local function calculate()
    local telemetry = ofs3.tasks.telemetry

    if not ofs3.session.isConnected or not ofs3.session.batteryConfig then
        resetVoltageTracking()
        return nil
    end

    local config = ofs3.session.batteryConfig
    local configSignature = table.concat({
        config.batteryCellCount,
        config.batteryCapacity,
        config.consumptionWarningPercentage,
        config.vbatmaxcellvoltage,
        config.vbatmincellvoltage,
        config.vbatfullcellvoltage
    }, ":")

    if configSignature ~= batteryConfigCache then
        batteryConfigCache = configSignature
        fuelStartingPercent = nil
        fuelStartingConsumption = nil
        resetVoltageTracking()
        stabilizeNotBefore = os.clock() + preStabiliseDelay
    end

    local voltage = telemetry and telemetry.getSensor and telemetry.getSensor("voltage") or nil
    if not voltage or voltage < 2 then
        resetVoltageTracking()
        stabilizeNotBefore = nil
        return nil
    end

    if stabilizeNotBefore and os.clock() < stabilizeNotBefore then
        return nil
    end

    table.insert(lastVoltages, voltage)
    if #lastVoltages > maxVoltageSamples then
        table.remove(lastVoltages, 1)
    end

    if not voltageStabilised then
        if not isVoltageStable() then
            return nil
        end
        voltageStabilised = true
    end

    local cellCount = config.batteryCellCount
    local packCapacity = config.batteryCapacity
    local reserve = config.consumptionWarningPercentage
    local maxCellVoltage = config.vbatmaxcellvoltage
    local minCellVoltage = config.vbatmincellvoltage
    local fullCellVoltage = config.vbatfullcellvoltage

    if reserve > 80 or reserve < 0 then
        reserve = 20
    end

    if packCapacity < 10 or cellCount == 0 or maxCellVoltage <= minCellVoltage or fullCellVoltage <= 0 then
        fuelStartingPercent = nil
        fuelStartingConsumption = nil
        return nil
    end

    local usableCapacity = packCapacity * (1 - reserve / 100)
    if usableCapacity < 10 then
        usableCapacity = packCapacity
    end

    local consumption = telemetry and telemetry.getSensor and telemetry.getSensor("consumption") or nil

    if not fuelStartingPercent then
        local perCell = voltage / cellCount
        if perCell >= fullCellVoltage then
            fuelStartingPercent = 100
        elseif perCell <= minCellVoltage then
            fuelStartingPercent = 0
        else
            local percent = ((perCell - minCellVoltage) / (maxCellVoltage - minCellVoltage)) * 100
            if reserve > 0 and percent <= reserve then
                fuelStartingPercent = 0
            else
                fuelStartingPercent = math.floor(math.max(0, math.min(100, percent)))
            end
        end

        local estimatedUsed = usableCapacity * (1 - fuelStartingPercent / 100)
        fuelStartingConsumption = (consumption or 0) - estimatedUsed
    end

    if consumption and fuelStartingConsumption then
        local used = consumption - fuelStartingConsumption
        local percentUsed = used / usableCapacity * 100
        local remaining = math.max(0, fuelStartingPercent - percentUsed)
        return math.floor(math.min(100, remaining) + 0.5)
    end

    return fuelStartingPercent
end

return {
    calculate = calculate
}
