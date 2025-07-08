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
--
local arg = {...}
local config = arg[1]

local sensors = {}
local loadedSensorModule = nil

local delayDuration = 2  -- seconds
local delayStartTime = nil
local delayPending = false

local smart = assert(ofs3.compiler.loadfile("tasks/sensors/smart.lua"))(config)

local log = ofs3.utils.log
local tasks = ofs3.tasks

--[[
    loadSensorModule - Loads the appropriate sensor module based on the current protocol and preferences.

    This function checks if the ofs3 tasks are active and if the API version is available. 
    Depending on the protocol (either "crsf" or "sport") and the user's preferences, it loads the corresponding sensor module.
    - For "crsf" protocol, it loads the "elrs" sensor module if internalElrsSensors preference is enabled.
    - For "sport" protocol, it loads either the "frsky" or "frsky_legacy" sensor module based on the API version and internalSportSensors preference.
    If no matching sensor is found, it clears the loadedSensorModule to save memory.

    Returns:
        nil - If the tasks are not active or the API version is not available.
]]
local function loadSensorModule()
    if not tasks.active() then return nil end
    if not ofs3.session.apiVersion then return nil end

    local protocol = "crsf"

    if system:getVersion().simulation == true then
        if not loadedSensorModule or loadedSensorModule.name ~= "sim" then
            --log("Loading Simulator sensor module","info")
            loadedSensorModule = {name = "sim", module = assert(ofs3.compiler.loadfile("tasks/sensors/sim.lua"))(config)}
        end   
    else
        loadedSensorModule = nil  -- No matching sensor, clear to save memory
    end
end

function sensors.wakeup()

    if ofs3.session.resetSensors and not delayPending then
        delayStartTime = os.clock()
        delayPending = true
        ofs3.session.resetSensors = false  -- Reset immediately
        log("Delaying sensor wakeup for " .. delayDuration .. " seconds","info")
        return  -- Exit early; wait starts now
    end

    if delayPending then
        if os.clock() - delayStartTime >= delayDuration then
            log("Delay complete; resuming sensor wakeup","info")
            delayPending = false
        else
            local module = model.getModule(ofs3.session.telemetrySensor:module())
            if module ~= nil and module.muteSensorLost ~= nil then module:muteSensorLost(5.0) end
            return  -- Still waiting; do nothing
        end
    end

    loadSensorModule()
    if loadedSensorModule and loadedSensorModule.module.wakeup then
        loadedSensorModule.module.wakeup()
    end

    -- run smart sensors
    if smart and smart.wakeup then
        smart.wakeup()
    end   


end

function sensors.reset()

    if loadedSensorModule and loadedSensorModule.module and loadedSensorModule.module.reset then
        loadedSensorModule.module.reset()
    end

    loadedSensorModule = nil  -- Clear loaded sensor module

end

return sensors
