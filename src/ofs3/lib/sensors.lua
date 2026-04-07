--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local sensors = {}

local smartfuel = assert(loadfile("lib/smartfuel.lua"))()
local useRawValue = ofs3.utils.ethosVersionAtLeast({26, 1, 0})

local cachedSensors = {}
local createRetryAt = {}
local cacheExpireTime = 30
local lastCacheFlushTime = os.clock()
local wakeupInterval = 1
local lastWakeupTime = 0
local simSensorList = nil
local CRSF_RPM_MAXIMUM = 65000
local CRSF_PROVISION_INTERVAL = 1
local crsfStartupProvision = {
    protocol = nil,
    lipoHandled = false,
    rpmHandled = false,
    lastAttempt = 0
}

local derivedDefinitions = {
    armed = {name = "Armed", appId = 0x5FE0, unit = UNIT_RAW, minimum = 0, maximum = 1},
    profile = {name = "Profile", appId = 0x5FE1, unit = UNIT_RAW, minimum = 0, maximum = 3},
    smartfuel = {name = "Smart Fuel", appId = 0x5FDF, unit = UNIT_PERCENT, minimum = 0, maximum = 100}
}

local function sourceExists(source)
    return source ~= nil
end

local function getModuleId(rootSource)
    if rootSource and rootSource.module then
        return rootSource:module()
    end
    if system.getVersion().simulation then
        return 0
    end
    if ofs3.session.telemetrySensor and ofs3.session.telemetrySensor.module then
        return ofs3.session.telemetrySensor:module()
    end
    return nil
end

local function getSimulationSensorList()
    if not simSensorList then
        simSensorList = ofs3.tasks.telemetry.simSensors()
    end
    return simSensorList
end

local function resetCrsfStartupProvision(protocol)
    crsfStartupProvision.protocol = protocol
    crsfStartupProvision.lipoHandled = false
    crsfStartupProvision.rpmHandled = false
    crsfStartupProvision.lastAttempt = 0
end

local function callSensorMethod(sensor, methodName, ...)
    if not sensor then
        return false, "missing"
    end

    local method = sensor[methodName]
    if type(method) ~= "function" then
        return false, "unsupported"
    end

    local ok, result = pcall(method, sensor, ...)
    if not ok then
        return false, result
    end

    return true, result
end

local function provisionCrsfStartupSensors(protocol)
    if protocol ~= crsfStartupProvision.protocol then
        resetCrsfStartupProvision(protocol)
    end

    if protocol ~= "crsf" then
        return
    end

    if crsfStartupProvision.lipoHandled and crsfStartupProvision.rpmHandled then
        return
    end

    local now = os.clock()
    if now - crsfStartupProvision.lastAttempt < CRSF_PROVISION_INTERVAL then
        return
    end
    crsfStartupProvision.lastAttempt = now

    if not crsfStartupProvision.lipoHandled and system.getSource then
        local lipoSource = system.getSource("LiPo")
        if lipoSource then
            local ok, err = callSensorMethod(lipoSource, "drop")
            if ok then
                ofs3.utils.log("[sensors] Dropped CRSF sensor 'LiPo'")
            else
                ofs3.utils.log("[sensors] Failed to drop CRSF sensor 'LiPo': " .. tostring(err))
            end
            crsfStartupProvision.lipoHandled = true
        end
    end

    if not crsfStartupProvision.rpmHandled and system.getSource then
        local rpmSource =
            (ofs3.tasks and ofs3.tasks.telemetry and ofs3.tasks.telemetry.getSensorSource and ofs3.tasks.telemetry.getSensorSource("rpm")) or
            system.getSource({crsfId = 0x02, subId = 3}) or
            system.getSource("RPM")
        if rpmSource then
            local ok, err = callSensorMethod(rpmSource, "maximum", CRSF_RPM_MAXIMUM)
            if ok then
                ofs3.utils.log("[sensors] Set CRSF RPM sensor maximum to " .. tostring(CRSF_RPM_MAXIMUM))
            else
                ofs3.utils.log("[sensors] Failed to set CRSF RPM sensor maximum: " .. tostring(err))
            end
            crsfStartupProvision.rpmHandled = true
        end
    end
end

local function ensureSensor(definition, rootSource)
    local appId = definition.appId
    local existing = cachedSensors[appId]
    if sourceExists(existing) then
        return existing
    end

    existing = system.getSource({category = CATEGORY_TELEMETRY_SENSOR, appId = appId})
    if sourceExists(existing) then
        cachedSensors[appId] = existing
        return existing
    end

    local moduleId = getModuleId(rootSource)
    if moduleId == nil then
        return nil
    end

    local now = os.clock()
    if createRetryAt[appId] and now < createRetryAt[appId] then
        return nil
    end

    if not model.createSensor then
        createRetryAt[appId] = now + 5
        return nil
    end

    local sensor = model.createSensor({type = SENSOR_TYPE_DIY})
    if not sensor then
        createRetryAt[appId] = now + 5
        ofs3.utils.log("createSensor returned nil for appId 0x" .. string.format("%X", appId))
        return nil
    end

    sensor:name(definition.name)
    sensor:appId(appId)
    sensor:physId(0)
    sensor:module(moduleId)
    sensor:minimum(definition.minimum or -1000000000)
    sensor:maximum(definition.maximum or 1000000000)

    if definition.decimals and definition.decimals >= 1 then
        sensor:decimals(definition.decimals)
        sensor:protocolDecimals(definition.decimals)
    end

    if definition.unit then
        sensor:unit(definition.unit)
        sensor:protocolUnit(definition.unit)
    end

    cachedSensors[appId] = sensor
    createRetryAt[appId] = nil
    return sensor
end

local function setSensorValue(definition, value, rootSource)
    local sensor = ensureSensor(definition, rootSource)
    if not sensor then
        return
    end

    if value == nil then
        if sensor.reset then
            sensor:reset()
        end
        return
    end
    if useRawValue and sensor.rawValue then
        sensor:rawValue(value)
    else
        sensor:value(value)
    end
end

local function updateSimulationSensors(rootSource)
    for _, entry in ipairs(getSimulationSensorList()) do
        local simSensor = entry.sensor
        local uid = simSensor and simSensor.uid
        local value = simSensor and simSensor.value

        if uid and simSensor.min and simSensor.max and value then
            if type(value) == "function" then
                value = value()
            end

            setSensorValue({
                name = entry.name,
                appId = uid,
                unit = simSensor.unit,
                decimals = simSensor.dec,
                minimum = simSensor.min,
                maximum = simSensor.max
            }, value, rootSource)
        end
    end
end

local function deriveArmedValue()
    local rx = ofs3.session and ofs3.session.rx and ofs3.session.rx.values or nil
    local value = rx and rx.arm or nil
    if value ~= nil then
        if value >= 500 then
            return 0
        end
        return 1
    end

    local rpm = ofs3.tasks.telemetry.getSensor("rpm") or 0
    if rpm > 1000 then
        return 0
    end
    return 1
end

local function deriveProfileValue()
    local rx = ofs3.session and ofs3.session.rx and ofs3.session.rx.values or nil
    local value = rx and rx.headspeed or nil
    if value ~= nil then
        if value < -500 then
            return 1
        elseif value > 500 then
            return 3
        else
            return 2
        end
    end

    return 1
end

local function updateDerivedSensors(protocol, rootSource)
    if protocol ~= "sim" then
        setSensorValue(derivedDefinitions.armed, deriveArmedValue(), rootSource)
        setSensorValue(derivedDefinitions.profile, deriveProfileValue(), rootSource)
    end
    setSensorValue(derivedDefinitions.smartfuel, smartfuel.calculate(), rootSource)
end

function sensors.reset()
    cachedSensors = {}
    createRetryAt = {}
    lastCacheFlushTime = os.clock()
    lastWakeupTime = 0
    simSensorList = nil
    resetCrsfStartupProvision(nil)
end

function sensors.wakeup(protocol, rootSource)
    if not protocol then
        return
    end

    local now = os.clock()
    if now - lastWakeupTime < wakeupInterval then
        return
    end
    lastWakeupTime = now

    if now - lastCacheFlushTime >= cacheExpireTime then
        cachedSensors = {}
        lastCacheFlushTime = now
    end

    if protocol == "sim" then
        updateSimulationSensors(rootSource)
    end

    provisionCrsfStartupSensors(protocol)
    updateDerivedSensors(protocol, rootSource)
end

return sensors
