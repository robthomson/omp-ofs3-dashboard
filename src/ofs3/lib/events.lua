--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local events = {}

local lastEventTimes = {}
local lastValues = {}

local eventTable = {
    {
        sensor = "voltage",
        interval = 10,
        event = function(value)
            local session = ofs3.session or {}
            local battery = session.batteryConfig or {}
            local cellCount = battery.batteryCellCount
            local warnVoltage = battery.vbatwarningcellvoltage
            local minVoltage = battery.vbatmincellvoltage

            if not (cellCount and warnVoltage and minVoltage) then
                return
            end

            local cellVoltage = value / cellCount
            if cellVoltage >= 0 and cellVoltage < (minVoltage / 2) then
                return
            end

            if cellVoltage < warnVoltage then
                ofs3.utils.playFile("events", "alerts/lowvoltage.wav")
            end
        end
    },
    {
        sensor = "smartfuel",
        interval = 10,
        event = function(value)
            if value and value <= 10 then
                ofs3.utils.playFile("events", "alerts/lowfuel.wav")
            end
        end
    },
    {
        sensor = "profile",
        debounce = 0.25,
        event = function(value)
            ofs3.utils.playFile("events", "alerts/profile.wav")
            system.playNumber(math.floor(value))
        end
    },
    {
        sensor = "armed",
        debounce = 0.25,
        event = function(value)
            if value == 0 then
                ofs3.utils.playFile("events", "alerts/armed.wav")
            elseif value == 1 then
                ofs3.utils.playFile("events", "alerts/disarmed.wav")
            end
        end
    }
}

function events.reset()
    lastEventTimes = {}
    lastValues = {}
end

function events.wakeup()
    local enabledEvents = ofs3.preferences and ofs3.preferences.events or {}
    local now = os.clock()

    for _, item in ipairs(eventTable) do
        local key = item.sensor
        if not enabledEvents[key] then
            goto continue
        end

        local source = ofs3.tasks.telemetry.getSensorSource(key)
        if not source or not source.value then
            goto continue
        end

        local value = source:value()
        if value == nil then
            goto continue
        end

        local lastVal = lastValues[key]
        if lastVal ~= nil and value == lastVal then
            goto continue
        end

        local lastTime = lastEventTimes[key] or 0
        local debounce = item.debounce or 0
        local interval = item.interval or 0

        if debounce > 0 and (now - lastTime) < debounce then
            goto continue
        end

        if interval > 0 and (now - lastTime) < interval then
            goto continue
        end

        item.event(value)
        lastValues[key] = value
        lastEventTimes[key] = now

        ::continue::
    end
end

events.eventTable = eventTable

return events
