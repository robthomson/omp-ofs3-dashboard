--[[

 * Copyright (C) Rotorflight Project
 * License GPLv3: https://www.gnu.org/licenses/gpl-3.0.en.html

 * MSP Sensor Table Structure
 *
 * msp_sensors: A table defining APIs to be polled via MSP and how to map their values to telemetry sensors.
 * Each top-level key is the MSP API name (e.g., "DATAFLASH_SUMMARY").
 * Each entry must include polling intervals and a 'fields' table containing telemetry sensor configs.
 *
 * Structure:
 * {
 *   API_NAME = {
 *     interval_armed: <number>         -- Interval (in seconds) to poll this API when the model is armed (-1 for no polling)
 *     interval_disarmed: <number>      -- Interval (in seconds) when disarmed (-1 for no polling)
 *     interval_admin: <number>         -- Interval (in seconds) when admin module loaded (-1 for no polling)
 *
 *     fields = {
 *       field_key = {
 *         sensorname: <string>         -- Label shown in radio telemetry menu
 *         sessionname: <string>        -- Optional session variable name to update
 *         appId: <number>              -- Unique sensor ID (must be unique across all sensors)
 *         unit: <constant>             -- Telemetry unit (e.g., UNIT_RAW, UNIT_VOLT, etc.)
 *         minimum: <number>            -- Optional minimum value (default: -1e9)
 *         maximum: <number>            -- Optional maximum value (default: 1e9)
 *         transform: <function>        -- Optional value processing function before display
 *       },
 *       ...
 *     }
 *   },
 *   ...
 * }

 * Possible sensor ids we can use are.
 * 0x5FE1   - smartfuel
 * 0x5FE0
 * 0x5FDF
 * 0x5FDE
 * 0x5FDD
 * 0x5FDC
 * 0x5FDB
 * 0x5FDA
 * 0x5FD9
 * 0x5FD8
 * 0x5FD7
 * 0x5FD6
 * 0x5FD5
 * 0x5FD4
 * 0x5FD3
 * 0x5FD2
 * 0x5FD1
 * 0x5FD0
 * 0x5FCF
 * 0x5FCE

]]

local smart = {}

local smartfuel = assert(ofs3.compiler.loadfile("tasks/sensors/lib/smartfuel.lua"))()

-- container vars
local log
local tasks 

local interval = 1 
local lastWake = ofs3.clock

local firstWakeup = true

local smart_sensors = {
    armed = {
        name = "Armed",
        appId = 0x5FE0, -- Unique sensor ID
        unit = UNIT_RAW, -- Telemetry unit
        minimum = -2000,
        maximum = 2000,
        value = function()

            if system:getVersion().simulation then
                local simValue = ofs3.utils.simSensors('armed')
                if simValue == nil then
                    return nil
                end
                return simValue == 0 and 1 or 0
            end

            local value = ofs3.session.rx.values['arm'] 
            if value then
                if value >= 500 then
                    return 0
                else
                    return 1 
                end
            end
        end,
    },
    profile = {
        name = "Profile",
        appId = 0x5FE1, -- Unique sensor ID
        unit = UNIT_RAW, -- Telemetry unit
        minimum = -2000,
        maximum = 2000,
        value = function()

            if system:getVersion().simulation then
                local simValue = ofs3.utils.simSensors('profile')
                return simValue or 1
            end


            local value = ofs3.session.rx.values['headspeed']  -- seems odd but is valid
            if value then
                if value < -500 then
                    return 1
                elseif value > 500 then
                    return 3
                else
                    return 2 
                end
            end
        end,
    },
    smartfuel = {
        name = "Smart Fuel",
        appId = 0x5FDF, -- Unique sensor ID
        unit = UNIT_PERCENT, -- Telemetry unit
        minimum = 0,
        maximum = 100,
        value = smartfuel.calculate,
    },    
}

smart.sensors = msp_sensors
local sensorCache = {}

local function createOrUpdateSensor(appId, fieldMeta, value)
    if not sensorCache[appId] then
        local existingSensor = system.getSource({ category = CATEGORY_TELEMETRY_SENSOR, appId = appId })

        if existingSensor then
            sensorCache[appId] = existingSensor
        else
            local sensor = model.createSensor({type=SENSOR_TYPE_DIY})
            sensor:name(fieldMeta.name)
            sensor:appId(appId)
            sensor:physId(0)
            sensor:module(ofs3.session.telemetrySensor:module())

            if fieldMeta.unit then
                sensor:unit(fieldMeta.unit)
                sensor:protocolUnit(fieldMeta.unit)
            end
            sensor:minimum(fieldMeta.minimum or -1000000000)
            sensor:maximum(fieldMeta.maximum or 1000000000)

            sensorCache[appId] = sensor
        end
    end

    if value then
        sensorCache[appId]:value(value)
    else
        sensorCache[appId]:reset()    
    end
end


local lastWakeupTime = 0
function smart.wakeup()

    if firstWakeup then
        log = ofs3.utils.log
        tasks = ofs3.tasks
        firstWakeup = false
    end

    -- rate-limit: bail out until interval has elapsed
    if (os.clock() - lastWake) < interval then
        return
    end
    lastWake = ofs3.clock

    for name, meta in pairs(smart_sensors) do
        local value
        if type(meta.value) == "function" then
            value = meta.value()
        else
            value = meta.value  -- Assume value is already calculated
        end    
        createOrUpdateSensor(meta.appId, meta, value)

    end
end

function smart.reset()
    sensorCache = {}
end

return smart
