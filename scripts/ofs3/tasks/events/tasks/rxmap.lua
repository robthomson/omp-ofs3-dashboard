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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * Note: Some icons have been sourced from https://www.flaticon.com/
]]--

local arg = { ... }
local config = arg[1]

local rxmap = {}

local channelNames = {
    "aileron",
    "elevator",
    "collective",
    "rudder",
    "arm",    
    "throttle",
    "headspeed",
    "mode"
}

local channelSources = {}
local initialized = false

local function initChannelSources()
    local rxMap = ofs3.session.rx.map
    for _, name in ipairs(channelNames) do
        local member = rxMap[name]
        if member then
            local src = system.getSource({ category = CATEGORY_CHANNEL, member = member, options = 0 })
            if src then
                channelSources[name] = src
            end
        end
    end
    initialized = true
end

function rxmap.wakeup()
    if not ofs3.utils.rxmapReady() then return end

    if not initialized then
        initChannelSources()
    end

    for name, src in pairs(channelSources) do
        if src then
            local val = src:value()
            if val ~= nil then
                ofs3.session.rx.values[name] = val
            end
        end
    end
end

function rxmap.reset()
    channelSources = {}
    initialized = false
end

return rxmap
