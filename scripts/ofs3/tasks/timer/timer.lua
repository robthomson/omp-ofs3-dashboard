--[[
 * Copyright (C) ofs3 Project
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
 *
 * Note: Some icons have been sourced from https://www.flaticon.com/
]]--

local arg = { ... }
local config = arg[1]

local timer = {}
local lastFlightMode = nil

--- Resets the flight timer session.
-- Logs the reset action, clears the last flight mode, and initializes a new timer session.
-- Sets the base lifetime from model preferences, resets session and lifetime counters,
-- and marks the flight as not counted.
function timer.reset()
    ofs3.utils.log("Resetting flight timers", "info")
    lastFlightMode = nil

    local timerSession = {}
    ofs3.session.timer = timerSession
    ofs3.session.flightCounted = false

    timerSession.baseLifetime = tonumber(
        ofs3.ini.getvalue(ofs3.session.modelPreferences, "general", "totalflighttime")
    ) or 0

    timerSession.session = 0
    timerSession.lifetime = timerSession.baseLifetime
end

--- Saves the current flight timer values to the model preferences INI file.
-- This function retrieves the model preferences and preferences file from the session.
-- If the preferences file is not set, it logs a message and returns.
-- Otherwise, it updates the "totalflighttime" and "lastflighttime" values in the "general" section
-- of the preferences, then saves the updated preferences back to the INI file.
-- Logs actions for debugging and information purposes.
function timer.save()
    local prefs = ofs3.session.modelPreferences
    local prefsFile = ofs3.session.modelPreferencesFile

    if not prefsFile then
        ofs3.utils.log("No model preferences file set, cannot save flight timers", "info")
        return 
    end

    ofs3.utils.log("Saving flight timers to INI: " .. prefsFile, "info")

    if prefs then
        ofs3.ini.setvalue(prefs, "general", "totalflighttime", ofs3.session.timer.baseLifetime or 0)
        ofs3.ini.setvalue(prefs, "general", "lastflighttime", ofs3.session.timer.session or 0)
        ofs3.ini.save_ini_file(prefsFile, prefs)
    end    
end

--- Finalizes the current flight segment by updating session and lifetime timers.
-- Calculates the duration of the current segment, updates the session and lifetime
-- timers accordingly, and saves the updated timer state.
-- @param now number The current time (in seconds or milliseconds, depending on context).
-- @usage
--   finalizeFlightSegment(os.clock())
local function finalizeFlightSegment(now)
    local timerSession = ofs3.session.timer
    local prefs = ofs3.session.modelPreferences

    local segment = now - timerSession.start
    timerSession.session = (timerSession.session or 0) + segment
    timerSession.start = nil

    if timerSession.baseLifetime == nil then
        timerSession.baseLifetime = tonumber(
            ofs3.ini.getvalue(prefs, "general", "totalflighttime")
        ) or 0
    end

    timerSession.baseLifetime = timerSession.baseLifetime + segment
    timerSession.lifetime = timerSession.baseLifetime

    timer.save()
end

--- Handles timer updates based on the current flight mode.
-- 
-- This function should be called periodically to update the timer session state.
-- It manages the start time, live session duration, and lifetime of the timer,
-- and updates persistent model preferences such as total flight time and flight count.
--
-- Behavior:
--   - In "inflight" mode:
--       - Initializes the timer start time if not already set.
--       - Updates the live session time and total lifetime.
--       - Persists the total flight time to model preferences.
--       - Increments and saves the flight count after 25 seconds of flight if not already counted.
--   - In other modes:
--       - Resets the live session time to the last session value.
--   - In "postflight" mode:
--       - Finalizes the flight segment if a flight was started.
--
-- Dependencies:
--   - Relies on `ofs3.session` for session state.
--   - Uses `ofs3.ini` for reading and writing model preferences.
--   - Calls `finalizeFlightSegment(now)` when appropriate.
function timer.wakeup()
    local now = os.time()
    local timerSession = ofs3.session.timer
    local prefs = ofs3.session.modelPreferences
    local flightMode = ofs3.flightmode.current

    lastFlightMode = flightMode

    if flightMode == "inflight" then
        if not timerSession.start then
            timerSession.start = now
        end

        local currentSegment = now - timerSession.start
        timerSession.live = (timerSession.session or 0) + currentSegment

        local computedLifetime = (timerSession.baseLifetime or 0) + currentSegment
        timerSession.lifetime = computedLifetime

        if prefs then
            ofs3.ini.setvalue(prefs, "general", "totalflighttime", computedLifetime)
        end

        if timerSession.live >= 25 and not ofs3.session.flightCounted then
            ofs3.session.flightCounted = true

            if prefs and ofs3.ini.section_exists(prefs, "general") then
                local count = ofs3.ini.getvalue(prefs, "general", "flightcount") or 0
                ofs3.ini.setvalue(prefs, "general", "flightcount", count + 1)
                ofs3.ini.save_ini_file(ofs3.session.modelPreferencesFile, prefs)
            end
        end

    else
        timerSession.live = timerSession.session or 0
    end

    if flightMode == "postflight" and timerSession.start then
        finalizeFlightSegment(now)
    end
end

return timer
