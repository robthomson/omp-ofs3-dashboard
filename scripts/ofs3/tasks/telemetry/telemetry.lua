--[[ 
 * Copyright (C) ofs3 Project
 *
 *
 * License GPLv3: https://www.gnu.org/licenses/gpl-3.0.en.html
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 3 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 
 * Note.  Some icons have been sourced from https://www.flaticon.com/
 * 
]] --
local arg = {...}
local config = arg[1]
local i18n = ofs3.i18n.get
local telemetry = {}
local protocol, telemetrySOURCE, crsfSOURCE

-- sensor cache: weak values so GC can drop cold sources
local sensors   = setmetatable({}, { __mode = "v" })

-- debug counters
local cache_hits, cache_misses = 0, 0

-- LRU for hot sources
local HOT_SIZE  = 25
local hot_list, hot_index = {}, {}

local function mark_hot(key)
  local idx = hot_index[key]
  if idx then
    table.remove(hot_list, idx)
  elseif #hot_list >= HOT_SIZE then
    local old = table.remove(hot_list, 1)
    hot_index[old] = nil
    -- evict the old sensor so cache size ≤ HOT_SIZE
    sensors[old] = nil    
  end
  table.insert(hot_list, key)
  hot_index[key] = #hot_list
end

function telemetry._debugStats()
  local hot_count = #hot_list
  return {
    hits        = cache_hits,
    misses      = cache_misses,
    hot_size    = hot_count,
    hot_list    = hot_list,
  }
end

-- Rate‐limiting for wakeup()
local sensorRateLimit = os.clock()
local ONCHANGE_RATE = 0.5        -- 1 second between onchange scans

-- Store the last validated sensors and timestamp
local lastValidationResult = nil
local lastValidationTime   = 0
local VALIDATION_RATE_LIMIT = 2  -- seconds

local lastCacheFlushTime   = 0
local CACHE_FLUSH_INTERVAL = 5  -- seconds

local telemetryState = false

-- Store last seen values for each sensor (by key)
local lastSensorValues = {}


telemetry.sensorStats = {}

-- For “reduced table” of onchange‐capable sensors:
local filteredOnchangeSensors = nil
local onchangeInitialized     = false

-- Predefined sensor mappings
--[[
sensorTable: A table containing various telemetry sensor configurations for different protocols (sport, crsf, crsf).

Each sensor configuration includes:
- name: The name of the sensor.
- mandatory: A boolean indicating if the sensor is mandatory.
- sport: A table of sensor configurations for the sport protocol.
- crsf: A table of sensor configurations for the crsf protocol.
- crsf: A table of sensor configurations for the crsf protocol.
- stats: A function to determine if min/max tracking should be active.
- localizations: A function to transform the sensor value.

Sensors included:
- RSSI Sensors (rssi)
- Arm Flags (armflags)
- Arm Disabled (arm_disabled)
- Voltage Sensors (voltage)
- RPM Sensors (rpm)
- Current Sensors (current)
- Temperature Sensors (temp_esc, temp_mcu)
- Fuel and Capacity Sensors (fuel, capacity)
- Flight Mode Sensors (governor)
- Adjustment Sensors (adj_f, adj_v)
- PID and Rate Profiles (pid_profile, rate_profile)
- Throttle Sensors (throttle_percent)

Check this url for some useful ID numbers when associating these sensors to the correct telemetry sensors "set telemetry_sensors"
https://github.com/rotorflight/rotorflight-firmware/blob/c7cad2c86fd833fe4bce76728f4914602614058d/src/main/telemetry/sensors.h#L34C15-L34C24
]]--

local sensorTable = {


    -- RSSI Sensors
    rssi = {
        name = i18n("telemetry.sensors.rssi"),
        mandatory = true,
        stats = true,
        switch_alerts = true,
        unit = UNIT_DB,
        unit_string = "dB",
        sensors = {
            sim = {
                { appId = 0xF101, subId = 0 },
            },
            crsf = {
                "Rx RSSI 1",  
                "Rx RSSI 2",
                "Rx Quality",
            },
        },
    },

    -- RSSI Sensors
    armed = {
        name = i18n("telemetry.sensors.arming_flags"),
        mandatory = true,
        stats = false,
        switch_alerts = false,
        unit = UNIT_RAW,
        unit_string = "",
        sensors = {
            sim = {
                { uid = 0x5FE0, unit = UNIT_RAW, dec = 0,
                  value = function() return ofs3.utils.simSensors('armed') end,
                  min = 0, max = 1 },
            },
            crsf = {
                { appId = 0x5FE0, subId = 0 },
            },
        },
    },        

    -- RSSI Sensors
    profile = {
        name = i18n("telemetry.sensors.profile"),
        mandatory = true,
        stats = false,
        switch_alerts = false,
        unit = UNIT_RAW,
        unit_string = "",
        sensors = {
            sim = {
                { uid = 0x5FE1, unit = UNIT_VOLT, dec = 0,
                  value = function() return ofs3.utils.simSensors('armed') end,
                  min = 0, max = 1600 },
            },
            crsf = {
                { appId = 0x5FE1, subId = 0 },
            },
        },
    },    


    -- Voltage Sensors
    voltage = {
        name = i18n("telemetry.sensors.voltage"),
        mandatory = true,
        stats = true,
        set_telemetry_sensors = 3,
        switch_alerts = true,
        unit = UNIT_VOLT,
        unit_string = "V",
        sensors = {
            sim = {
                { uid = 0x5002, unit = UNIT_VOLT, dec = 2,
                  value = function() return ofs3.utils.simSensors('voltage') end,
                  min = 0, max = 3000 },
            },
            crsf = { "Rx Batt" },
        },    
    },

    -- RPM Sensors
    rpm = {
        name = i18n("telemetry.sensors.headspeed"),
        mandatory = true,
        stats = true,
        set_telemetry_sensors = 60,
        switch_alerts = true,
        unit = UNIT_RPM,
        unit_string = "rpm",
        sensors = {
            sim = {
                { uid = 0x5003, unit = UNIT_RPM, dec = nil,
                  value = function() return ofs3.utils.simSensors('rpm') end,
                  min = 0, max = 4000 },
            },
            crsf = { "GPS alt" },
        },
    },

    -- Fuel and Capacity Sensors
    smartfuel = {
        name = i18n("telemetry.sensors.smartfuel"),
        mandatory = false,
        stats = true,
        set_telemetry_sensors = nil,
        switch_alerts = true,
        unit = UNIT_PERCENT,
        unit_string = "%",
        sensors = {
            sim = {
                { category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FDF },
            },
            crsf = {
                { category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FDF },
            },
        },
    },

    -- Current Sensors
    current = {
        name = i18n("telemetry.sensors.current"),
        mandatory = false,
        stats = true,
        set_telemetry_sensors = 18,
        switch_alerts = true,
        unit = UNIT_AMPERE,
        unit_string = "A",
        sensors = {
            sim = {
                { uid = 0x5004, unit = UNIT_AMPERE, dec = 0,
                  value = function() return ofs3.utils.simSensors('current') end,
                  min = 0, max = 300 },
            },
            crsf = { "Rx Current" },
        },
    },

    -- ESC Temperature Sensors
    temp_esc = {
        name = i18n("telemetry.sensors.esc_temp"),
        mandatory = false,
        stats = true,
        set_telemetry_sensors = 23,
        switch_alerts = true,
        unit = UNIT_DEGREE,
        sensors = {
            sim = {
                { uid = 0x5005, unit = UNIT_DEGREE, dec = 0,
                  value = function() return ofs3.utils.simSensors('temp_esc') end,
                  min = 0, max = 100 },
            },
            crsf = { "GPS speed" },
        },
        localizations = function(value)
            local major = UNIT_DEGREE
            if value == nil then return nil, major, nil end

            -- Shortcut to the user’s temperature‐unit preference (may be nil)
            local prefs = ofs3.preferences.localizations
            local isFahrenheit = prefs and prefs.temperature_unit == 1

            if isFahrenheit then
                -- Convert from Celsius to Fahrenheit
                return value * 1.8 + 32, major, "°F"
            end

            -- Default: return Celsius
            return value, major, "°C"
        end,
    },

    -- MCU Temperature Sensors
    temp_mcu = {
        name = i18n("telemetry.sensors.mcu_temp"),
        mandatory = false,
        stats = true,
        set_telemetry_sensors = 52,
        switch_alerts = true,
        unit = UNIT_DEGREE,
        sensors = {
            sim = {
                { uid = 0x5006, unit = UNIT_DEGREE, dec = 0,
                  value = function() return ofs3.utils.simSensors('temp_mcu') end,
                  min = 0, max = 100 },
            },
            crsf = { "GPS Sats" },
        },
        localizations = function(value)
            local major = UNIT_DEGREE
            if value == nil then return nil, major, nil end

            -- Shortcut to the user’s temperature‐unit preference (may be nil)
            local prefs = ofs3.preferences.localizations
            local isFahrenheit = prefs and prefs.temperature_unit == 1

            if isFahrenheit then
                -- Convert from Celsius to Fahrenheit
                return value * 1.8 + 32, major, "°F"
            end

            -- Default: return Celsius
            return value, major, "°C"
        end,
    },

    -- Fuel and Capacity Sensors
    fuel = {
        name = i18n("telemetry.sensors.fuel"),
        mandatory = false,
        stats = true,
        set_telemetry_sensors = 6,
        switch_alerts = true,
        unit = UNIT_PERCENT,
        unit_string = "%",
        sensors = {
            sim = {
                { 
                    uid = 0x5007, unit = UNIT_PERCENT, dec = 0,
                    value = function() return ofs3.utils.simSensors('fuel') end,                   
                    min = 0, max = 100
                },
            },
            crsf = { "Rx Batt%" },
        },
    },

    consumption = {
        name = i18n("telemetry.sensors.consumption"),
        mandatory = true,
        stats = true,
        set_telemetry_sensors = 5,
        switch_alerts = true,
        unit = UNIT_MILLIAMPERE_HOUR,
        unit_string = "mAh",
        sensors = {
            sim = {
                { uid = 0x5008, unit = UNIT_MILLIAMPERE_HOUR, dec = 0,
                  value = function() return ofs3.utils.simSensors('consumption') end,
                  min = 0, max = 5000 },
            },
            crsf = { "Rx Cons" },
        },
    },


    
}

--[[ 
    Retrieves the current sensor protocol.
    @return protocol - The protocol used by the sensor.
]]
function telemetry.getSensorProtocol()
    return protocol
end

--[[ 
    Function: telemetry.listSensors
    Description: Generates a list of sensors from the sensorTable.
    Returns: A table containing sensor details (key, name, and mandatory status).
]]
function telemetry.listSensors()
    local sensorList = {}
    for key, sensor in pairs(sensorTable) do 
        table.insert(sensorList, {
            key = key,
            name = sensor.name,
            mandatory = sensor.mandatory,
            set_telemetry_sensors = sensor.set_telemetry_sensors
        })
    end
    return sensorList
end

--[[ 
    Function: telemetry.listSensorAudioUnits
    Returns a mapping of sensorKey → unit type, if defined.
]]
function telemetry.listSensorAudioUnits()
    local sensorMap = {}
    for key, sensor in pairs(sensorTable) do 
        if sensor.unit then
            sensorMap[key] = sensor.unit
        end    
    end
    return sensorMap
end

--[[ 
    Function: telemetry.listSwitchSensors
    Returns a list of sensors flagged for switch alerts.
]]
function telemetry.listSwitchSensors()
    local sensorList = {}
    for key, sensor in pairs(sensorTable) do 
        if sensor.switch_alerts then
            table.insert(sensorList, {
                key = key,
                name = sensor.name,
                mandatory = sensor.mandatory,
                set_telemetry_sensors = sensor.set_telemetry_sensors
            })
        end    
    end
    return sensorList
end

--[[ 
    Helper: Get the raw Source object for a given sensorKey, caching as we go.
]]
function telemetry.getSensorSource(name)
    if not sensorTable[name] then return nil end

    -- Return cached if available, bump it as hot:
    if sensors[name] then
        cache_hits = cache_hits + 1           -- debug: we hit the cache :contentReference[oaicite:0]{index=0}
        mark_hot(name)
        return sensors[name]
    end

    local function checkCondition(sensorEntry)
        if not (ofs3.session and ofs3.session.apiVersion) then
            return true
        end
        local roundedApiVersion = ofs3.utils.round(ofs3.session.apiVersion, 2)
        if sensorEntry.mspgt then
            return roundedApiVersion >= ofs3.utils.round(sensorEntry.mspgt, 2)
        elseif sensorEntry.msplt then
            return roundedApiVersion <= ofs3.utils.round(sensorEntry.msplt, 2)
        end
        return true
    end
    
    if system.getVersion().simulation == true then
        protocol = "sport"
        for _, sensor in ipairs(sensorTable[name].sensors.sim or {}) do
            -- handle sensors in regular formt
            if sensor.uid then
                if sensor and type(sensor) == "table" then
                    local sensorQ = { appId = sensor.uid, category = CATEGORY_TELEMETRY_SENSOR }
                    local source = system.getSource(sensorQ)
                    if source then
                        cache_misses = cache_misses + 1       -- debug: loaded from system.getSource :contentReference[oaicite:1]{index=1}
                        sensors[name] = source
                        mark_hot(name)
                        return source
                    end
                end
            else
                -- handle smart sensors / regular lookups    
                if checkCondition(sensor) and type(sensor) == "table" then
                    sensor.mspgt = nil
                    sensor.msplt = nil
                    local source = system.getSource(sensor)
                    if source then
                        cache_misses = cache_misses + 1       -- debug: loaded from system.getSource :contentReference[oaicite:1]{index=1}
                        sensors[name] = source
                        mark_hot(name)
                        return source
                    end
                end                
            end    
        end

    elseif ofs3.session.telemetryType == "crsf" then
            protocol = "crsf"
            for _, sensor in ipairs(sensorTable[name].sensors.crsf or {}) do
                local source = system.getSource(sensor)
                if source then
                    cache_misses = cache_misses + 1       -- debug: loaded from system.getSource :contentReference[oaicite:1]{index=1}
                    sensors[name] = source
                    mark_hot(name)
                    return source
                end
            end
    else
        protocol = "unknown"
    end

    return nil
end

--- Retrieves the value of a telemetry sensor by its key.
-- This function now supports both physical sensors (linked to telemetry sources)
-- and virtual/computed sensors (which define a `.source` function in sensorTable).
--
-- 1. If the sensorTable entry includes a `source` function (virtual/computed sensor),
--    this function is called and its `.value()` result is returned.
-- 2. Otherwise, attempts to resolve the sensor as a physical/real telemetry source.
--    If found, returns its value; otherwise, returns nil.
-- 3. If a `localizations` function is defined for the sensor, it is applied to
--    transform the raw value and resolve units as needed.
--
-- @param sensorKey The key identifying the telemetry sensor.
-- @return The sensor value (possibly transformed), primary unit (major), and secondary unit (minor) if available.
function telemetry.getSensor(sensorKey)
    local entry = sensorTable[sensorKey]

    if entry and type(entry.source) == "function" then
        local src = entry.source()
        if src and type(src.value) == "function" then
            local value, major, minor = src.value()
            major = major or entry.unit
            -- Optionally apply localization, if needed:
            if entry.localizations and type(entry.localizations) == "function" then
                value, major, minor = entry.localizations(value)
            end
            return value, major, minor
        end
    end

    -- Physical/real telemetry source
    local source = telemetry.getSensorSource(sensorKey)
    if not source then
        return nil
    end

    -- get initial defaults
    local value = source:value()
    local major = entry and entry.unit or nil
    local minor = nil

    -- if the sensor has a transform function, apply it to the value:
    if entry and entry.localizations and type(entry.localizations) == "function" then
        value, major, minor = entry.localizations(value)
    end

    return value, major, minor
end

--[[ 
    Function: telemetry.validateSensors
    Purpose: Validates the sensors and returns a list of either valid or invalid sensors based on the input parameter.
    Parameters:
        returnValid (boolean) - If true, the function returns only valid sensors. If false, it returns only invalid sensors.
    Returns:
        table - A list of sensors with their keys and names. The list contains either valid or invalid sensors based on the returnValid parameter.
    Notes:
        - The function uses a rate limit to avoid frequent validations.
        - If telemetry is not active, it returns all sensors.
        - The function considers the mandatory flag for invalid sensors.
]]
function telemetry.validateSensors(returnValid)
    local now = os.clock()
    if (now - lastValidationTime) < VALIDATION_RATE_LIMIT then
        return lastValidationResult
    end
    lastValidationTime = now

    if not ofs3.session.telemetryState then
        local allSensors = {}
        for key, sensor in pairs(sensorTable) do
            table.insert(allSensors, { key = key, name = sensor.name })
        end
        lastValidationResult = allSensors
        return allSensors
    end

    local resultSensors = {}
    for key, sensor in pairs(sensorTable) do
        local sensorSource = telemetry.getSensorSource(key)
        local isValid = (sensorSource ~= nil and sensorSource:state() ~= false)
        if returnValid then
            if isValid then
                table.insert(resultSensors, { key = key, name = sensor.name })
            end
        else
            if not isValid and sensor.mandatory ~= false then
                table.insert(resultSensors, { key = key, name = sensor.name })
            end
        end
    end

    lastValidationResult = resultSensors
    return resultSensors
end

--[[ 
    Function: telemetry.simSensors
    Description: Simulates sensors by iterating over a sensor table and returning a list of valid sensors.
    Parameters:
        returnValid (boolean) - A flag indicating whether to return valid sensors.
    Returns:
        result (table) - A table containing the names and first sport sensors of valid sensors.

    This function is used to build a list of sensors that are available in 'simulation mode'
]]
function telemetry.simSensors(returnValid)
    local result = {}
    for key, sensor in pairs(sensorTable) do
        local name = sensor.name
        local firstSportSensor = sensor.sensors.sim and sensor.sensors.sim[1]
        if firstSportSensor then
            table.insert(result, { name = name, sensor = firstSportSensor })
        end
    end
    return result
end

--[[ 
    Function: telemetry.active
    Description: Checks if telemetry is active. Returns true if the system is in simulation mode, otherwise returns the state of telemetry.
    Returns: 
        - boolean: true if in simulation mode or telemetry is active, false otherwise.
]]
function telemetry.active()
    return ofs3.session.telemetryState or false
end

--- Clears all cached sources and state.
function telemetry.reset()
    telemetrySOURCE, crsfSOURCE, protocol = nil, nil, nil
    sensors = {}
    hot_list, hot_index = {}, {}
    --telemetry.sensorStats = {} -- we defer this to onconnect
    -- Also reset onchange tracking so we rebuild next time:
    filteredOnchangeSensors = nil
    lastSensorValues = {}
    onchangeInitialized = false
end

--[[ 
    Primary wakeup() loop:
    - Prioritize MSP traffic
    - Rate-limit onchange scanning (once per second)
    - Periodic cache flush every 5s
    - Reset telemetry if needed
]]
function telemetry.wakeup()
    local now = os.clock()

    -- Rate‐limited “onchange” scanning (every ONCHANGE_RATE seconds)
    if (now - sensorRateLimit) >= ONCHANGE_RATE then
        sensorRateLimit = now

        -- Build reduced table of onchange‐capable sensors exactly once:
        if not filteredOnchangeSensors then
            filteredOnchangeSensors = {}
            for sensorKey, sensorDef in pairs(sensorTable) do
                if type(sensorDef.onchange) == "function" then
                    filteredOnchangeSensors[sensorKey] = sensorDef
                end
            end
            -- Mark that we just built the reduced table; skip invoking onchange this pass
            onchangeInitialized = true
        end

        -- If we just built the table on this pass, skip detection; next time, run normally
        if onchangeInitialized then
            onchangeInitialized = false
        else
            -- Now iterate only over filteredOnchangeSensors
            for sensorKey, sensorDef in pairs(filteredOnchangeSensors) do
                local source = telemetry.getSensorSource(sensorKey)
                if source and source:state() then
                    local val = source:value()
                    if lastSensorValues[sensorKey] ~= val then
                        -- Invoke onchange with the new value
                        sensorDef.onchange(val)
                        lastSensorValues[sensorKey] = val
                    end
                end
            end
        end
    end


    -- Reset if telemetry is inactive or telemetry type changed
    if not ofs3.session.telemetryState or ofs3.session.telemetryTypeChanged then
        telemetry.reset()
    end
end

-- retrieve min/max values for a sensor
function telemetry.getSensorStats(sensorKey)
    return telemetry.sensorStats[sensorKey] or { min = nil, max = nil }
end

-- allow sensor table to be accessed externally
telemetry.sensorTable = sensorTable

return telemetry