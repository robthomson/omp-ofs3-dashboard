--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local telemetry = {}

local sensors = {}
local currentProtocol = nil
local debugLastTraceAt = 0
local DEBUG_TRACE_INTERVAL = 2.0
local sensorTraceOrder = {"profile", "voltage", "current", "consumption", "rpm", "temp_esc"}

local sensorTable = {
    rssi = {
        stats = true,
        unit_string = "%",
        sensors = {
            sim = {{appId = 0xF010, subId = 0}, "RSSI"},
            crsf = {{crsfId = 0x14, subId = 2}},
            sport = {{appId = 0xF010, subId = 0}, "RSSI"}
        }
    },
    armed = {
        name = "Armed",
        stats = false,
        unit_string = "",
        sensors = {
            sim = {{
                uid = 0x5FE0,
                unit = UNIT_RAW,
                dec = 0,
                value = function()
                    return ofs3.utils.simSensors("armed")
                end,
                min = 0,
                max = 1
            }},
            crsf = {{appId = 0x5FE0, subId = 0}},
            sport = {{appId = 0x5FE0}, "Armed"}
        }
    },
    profile = {
        name = "Profile",
        stats = false,
        unit_string = "",
        sensors = {
            sim = {{
                uid = 0x5FE1,
                unit = UNIT_RAW,
                dec = 0,
                value = function()
                    return ofs3.utils.simSensors("profile")
                end,
                min = 0,
                max = 3
            }},
            crsf = {{appId = 0x5FE1, subId = 0}},
            sport = {{appId = 0x5FE1}, "Profile"}
        }
    },
    voltage = {
        name = "Voltage",
        stats = true,
        unit_string = "V",
        sensors = {
            sim = {{
                uid = 0x5002,
                unit = UNIT_VOLT,
                dec = 2,
                value = function()
                    return ofs3.utils.simSensors("voltage")
                end,
                min = 0,
                max = 3000
            }},
            crsf = {{crsfId = 0x08, subId = 0}},
            sport = {{appId = 0x0B50, subId = 0}, "ESC Voltage"}
        }
    },
    rpm = {
        name = "Headspeed",
        stats = true,
        unit_string = "rpm",
        sensors = {
            sim = {{
                uid = 0x5003,
                unit = UNIT_RPM,
                dec = nil,
                value = function()
                    return ofs3.utils.simSensors("rpm")
                end,
                min = 0,
                max = 4000
            }},
            crsf = {{crsfId = 0x02, subId = 3}},
            sport = {{appId = 0x0500, subId = 0}, "RPM"}
        }
    },
    smartfuel = {
        stats = true,
        unit_string = "%",
        sensors = {
            sim = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FDF}},
            crsf = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FDF}},
            sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FDF}}
        }
    },
    current = {
        name = "Current",
        stats = true,
        unit_string = "A",
        sensors = {
            sim = {{
                uid = 0x5004,
                unit = UNIT_AMPERE,
                dec = 0,
                value = function()
                    return ofs3.utils.simSensors("current")
                end,
                min = 0,
                max = 300
            }},
            crsf = {{crsfId = 0x08, subId = 1}},
            sport = {{appId = 0x0B50, subId = 1}, "ESC current"}
        }
    },
    temp_esc = {
        name = "ESC Temp",
        stats = true,
        unit_string = "°C",
        sensors = {
            sim = {{
                uid = 0x5005,
                unit = UNIT_DEGREE,
                dec = 0,
                value = function()
                    return ofs3.utils.simSensors("temp_esc")
                end,
                min = 0,
                max = 100
            }},
            crsf = {{crsfId = 0x02, subId = 2}},
            sport = {{appId = 0x0B70, subId = 0}, "ESC temp"}
        },
        localizations = function(value)
            if value == nil then
                return nil, nil, nil
            end

            local prefs = ofs3.preferences.localizations or {}
            if prefs.temperature_unit == 1 then
                return value * 1.8 + 32, nil, "°F"
            end

            return value, nil, "°C"
        end
    },
    consumption = {
        name = "Consumption",
        stats = true,
        unit_string = "mAh",
        sensors = {
            sim = {{
                uid = 0x5008,
                unit = UNIT_MILLIAMPERE_HOUR,
                dec = 0,
                value = function()
                    return ofs3.utils.simSensors("consumption")
                end,
                min = 0,
                max = 5000
            }},
            crsf = {{crsfId = 0x08, subId = 2}},
            sport = {{appId = 0x0B60, subId = 1}, "ESC consumption"}
        }
    }
}

local function sourceIsUsable(source)
    if not source then
        return false
    end

    if source.state and source:state() == false then
        return false
    end

    return true
end

local function telemetryTraceEnabled()
    local developer = ofs3.preferences and ofs3.preferences.developer or nil
    return developer and developer.telemetrytrace == true
end

local function formatProbe(entry)
    if type(entry) == "string" then
        return 'name="' .. entry .. '"'
    end

    if type(entry) ~= "table" then
        return tostring(entry)
    end

    local parts = {}

    if entry.category ~= nil then
        parts[#parts + 1] = "category=" .. tostring(entry.category)
    end
    if entry.appId ~= nil then
        parts[#parts + 1] = string.format("appId=0x%X", tonumber(entry.appId) or 0)
    end
    if entry.uid ~= nil then
        parts[#parts + 1] = string.format("uid=0x%X", tonumber(entry.uid) or 0)
    end
    if entry.crsfId ~= nil then
        parts[#parts + 1] = string.format("crsfId=0x%X", tonumber(entry.crsfId) or 0)
    end
    if entry.subId ~= nil then
        parts[#parts + 1] = "subId=" .. tostring(entry.subId)
    end
    if entry.subIdStart ~= nil then
        parts[#parts + 1] = "subIdStart=" .. tostring(entry.subIdStart)
    end
    if entry.subIdEnd ~= nil then
        parts[#parts + 1] = "subIdEnd=" .. tostring(entry.subIdEnd)
    end
    if entry.unit ~= nil then
        parts[#parts + 1] = "unit=" .. tostring(entry.unit)
    end
    if entry.dec ~= nil then
        parts[#parts + 1] = "dec=" .. tostring(entry.dec)
    end

    if #parts == 0 then
        return "{}"
    end

    return table.concat(parts, ",")
end

local function readSourceState(source)
    if not source or not source.state then
        return "n/a"
    end

    local ok, state = pcall(function()
        return source:state()
    end)

    if not ok then
        return "err"
    end

    return tostring(state)
end

local function readSourceValue(source)
    if not source or not source.value then
        return "n/a"
    end

    local ok, value = pcall(function()
        return source:value()
    end)

    if not ok then
        return "err"
    end

    if type(value) == "number" then
        return string.format("%.3f", value)
    end

    return tostring(value)
end

local function clearCachedSources()
    sensors = {}
end

local function resolveSource(entry)
    if type(entry) == "string" then
        return system.getSource(entry)
    end

    if type(entry) ~= "table" then
        return nil
    end

    return system.getSource(entry)
end

local function getDebugProtocol()
    local protocol = currentProtocol or ofs3.session.telemetryType
    if system.getVersion().simulation then
        protocol = protocol or "sim"
    end
    return protocol
end

local function traceTelemetrySources()
    if not telemetryTraceEnabled() then
        return
    end

    local now = os.clock()
    if (now - debugLastTraceAt) < DEBUG_TRACE_INTERVAL then
        return
    end
    debugLastTraceAt = now

    local protocol = getDebugProtocol()
    if not protocol then
        return
    end

    ofs3.utils.log("[telemetry-trace] protocol=" .. tostring(protocol))

    for _, sensorKey in ipairs(sensorTraceOrder) do
        local def = sensorTable[sensorKey]
        local entries = def and def.sensors and def.sensors[protocol] or nil
        if entries and #entries > 0 then
            for index, entry in ipairs(entries) do
                local source = resolveSource(entry)
                ofs3.utils.log(string.format(
                    "[telemetry-trace] sensor=%s probe[%d]=%s exists=%s state=%s value=%s",
                    tostring(sensorKey),
                    index,
                    formatProbe(entry),
                    tostring(source ~= nil),
                    readSourceState(source),
                    readSourceValue(source)
                ))
            end
        end
    end
end

local function findUsableSource(entries)
    for _, entry in ipairs(entries or {}) do
        local source = resolveSource(entry)
        if sourceIsUsable(source) then
            return source
        end
    end

    return nil
end

local function findExistingSource(entries)
    for _, entry in ipairs(entries or {}) do
        local source = resolveSource(entry)
        if source ~= nil then
            return source
        end
    end

    return nil
end

local function detectSimulationSource()
    local probes = {
        {appId = 0xF101, subId = 0},
        {appId = 0xF101},
        "RSSI"
    }

    return findUsableSource(probes)
end

function telemetry.setProtocol(protocol)
    if currentProtocol == protocol then
        return
    end

    currentProtocol = protocol
    clearCachedSources()
end

function telemetry.getSensorProtocol()
    return currentProtocol or ofs3.session.telemetryType or "unknown"
end

function telemetry.detectProtocol()
    if system.getVersion().simulation then
        local internalModule = model.getModule and model.getModule(0) or nil
        return "sim", detectSimulationSource(), internalModule
    end

    local internalModule = model.getModule and model.getModule(0) or nil
    local externalModule = model.getModule and model.getModule(1) or nil

    if internalModule and internalModule.enable and internalModule:enable() then
        local sportSource = findExistingSource({{appId = 0xF101}})
        if sportSource ~= nil then
            return "sport", sportSource, internalModule
        end
    end

    if externalModule and externalModule.enable and externalModule:enable() then
        local crsfSource = findExistingSource({{crsfId = 0x14, subIdStart = 0, subIdEnd = 1}})
        if crsfSource ~= nil then
            return "crsf", crsfSource, externalModule
        end

        local sportSource = findExistingSource({{appId = 0xF101}})
        if sportSource ~= nil then
            return "sport", sportSource, externalModule
        end
    end

    return nil, nil, nil
end

function telemetry.getSensorSource(sensorKey)
    local protocol = currentProtocol or ofs3.session.telemetryType
    if system.getVersion().simulation then
        protocol = protocol or "sim"
    end

    local cached = sensors[sensorKey]
    if cached ~= nil then
        return cached
    end

    sensors[sensorKey] = nil

    local def = sensorTable[sensorKey]
    if not def then
        return nil
    end

    local groups = nil

    if protocol == "sim" then
        for _, entry in ipairs(def.sensors.sim or {}) do
            if type(entry) == "table" and entry.uid then
                local source = system.getSource({category = CATEGORY_TELEMETRY_SENSOR, appId = entry.uid})
                if source ~= nil then
                    sensors[sensorKey] = source
                    return source
                end
            else
                local source = findExistingSource({entry})
                if source ~= nil then
                    sensors[sensorKey] = source
                    return source
                end
            end
        end
        return nil
    elseif protocol == "crsf" then
        groups = {"crsf"}
    elseif protocol == "sport" then
        groups = {"sport"}
    else
        return nil
    end

    for _, group in ipairs(groups) do
        local source = findExistingSource(def.sensors[group])
        if source then
            sensors[sensorKey] = source
            return source
        end
    end

    return nil
end

function telemetry.getSensor(sensorKey)
    local def = sensorTable[sensorKey]
    local source = telemetry.getSensorSource(sensorKey)
    if not def or not source then
        return nil
    end

    local value = source:value()
    local major = nil
    local minor = def.unit_string

    if def.localizations and type(def.localizations) == "function" then
        value, major, minor = def.localizations(value)
    end

    return value, major, minor
end

function telemetry.simSensors()
    local result = {}
    for key, sensor in pairs(sensorTable) do
        local firstSimSensor = sensor.sensors.sim and sensor.sensors.sim[1]
        if firstSimSensor then
            table.insert(result, {key = key, name = sensor.name or key, sensor = firstSimSensor})
        end
    end
    return result
end

function telemetry.active()
    return ofs3.session.telemetryState or false
end

function telemetry.reset()
    clearCachedSources()
    currentProtocol = nil
    debugLastTraceAt = 0
    telemetry.sensorStats = {}
end

function telemetry.wakeup()
    traceTelemetrySources()
    return
end

function telemetry.getSensorStats(sensorKey)
    return telemetry.sensorStats[sensorKey] or {min = nil, max = nil}
end

telemetry.sensorStats = {}
telemetry.sensorTable = sensorTable

return telemetry
