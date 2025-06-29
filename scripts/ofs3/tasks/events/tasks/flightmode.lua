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

local flightmode = {}
local lastFlightMode = nil
local hasBeenInFlight = false

--- Determines if the flight mode is considered "in flight".
-- This function checks two main conditions to decide if the model is in flight:
-- 1. If the governor sensor is active (highest priority).
-- 2. If the throttle has been above zero for a sustained period.
-- The function also ensures telemetry is active and the session is armed before proceeding.
-- @return boolean True if the model is considered in flight, false otherwise.
function flightmode.inFlight()
    local telemetry = ofs3.tasks.telemetry

    if not telemetry.active() then
        return false
    end

    local rpm = telemetry.getSensor("rpm")
    local armed = telemetry.getSensor("armed")
    if armed == 0 then
        if rpm and rpm > 1000 then
            return true
        end
    end
    return false
end

--- Resets the flight mode state.
-- This function clears the last flight mode, resets the flight status,
-- and clears the throttle start time. It is typically used to reinitialize
-- the flight mode tracking variables to their default states.
function flightmode.reset()
    lastFlightMode = nil
    hasBeenInFlight = false
end

--- Determines the current flight mode based on session state and flight status.
-- This function checks the current session's flight mode and connection status,
-- as well as the result of `flightmode.inFlight()`, to decide whether the mode
-- should be "preflight", "inflight", or "postflight".
-- It also manages the `hasBeenInFlight` flag to track if the system has ever been in flight.
-- @return string The determined flight mode: "preflight", "inflight", or "postflight".
local function determineMode()
    if ofs3.flightmode.current == "inflight" and not ofs3.session.isConnected then
        hasBeenInFlight = false
        return "postflight"
    end
    if flightmode.inFlight() then
        hasBeenInFlight = true
        return "inflight"
    end

    return hasBeenInFlight and "postflight" or "preflight"
end

--- Wakes up the flight mode task and updates the current flight mode if it has changed.
-- Determines the current flight mode using `determineMode()`. If the mode has changed since the last check,
-- logs the new flight mode, updates the session's flight mode, and stores the new mode as the last known mode.
function flightmode.wakeup()
    local mode = determineMode()

    if lastFlightMode ~= mode then
        ofs3.utils.log("Flight mode: " .. mode, "info")
        ofs3.flightmode.current = mode
        lastFlightMode = mode
    end
end

return flightmode
