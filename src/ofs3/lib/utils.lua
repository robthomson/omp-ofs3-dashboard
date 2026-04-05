--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local utils = {}

local arg = {...}
local config = arg[1]

function utils.log(message)
    if message == nil then
        return
    end

    print("[ofs3] " .. tostring(message))
end

function utils.round(value, decimals)
    if type(value) ~= "number" then
        return value
    end

    local places = decimals or 0
    local mult = 10 ^ places
    return math.floor(value * mult + 0.5) / mult
end

function utils.file_exists(path)
    local file = io.open(path, "r")
    if not file then
        return false
    end

    file:close()
    return true
end

function utils.playFile(pkg, file)
    local audioVoice = system.getAudioVoice and system.getAudioVoice() or "AUDIO:/en/default"
    local voicePath = tostring(audioVoice)
        :gsub("SD:", "")
        :gsub("RADIO:", "")
        :gsub("AUDIO:", "")
        :gsub("VOICE[1-4]:", "")
        :gsub("audio/", "")

    if voicePath:sub(1, 1) == "/" then
        voicePath = voicePath:sub(2)
    end

    local userAudioBase = "SCRIPTS:/" .. ofs3.config.preferences .. "/audio"
    local wavUser = userAudioBase .. "/user/" .. pkg .. "/" .. file
    local wavLocale = userAudioBase .. "/" .. voicePath .. "/" .. pkg .. "/" .. file
    local wavDefault = "SCRIPTS:/" .. ofs3.config.baseDir .. "/audio/en/default/" .. pkg .. "/" .. file

    local path = wavDefault
    if utils.file_exists(wavUser) then
        path = wavUser
    elseif utils.file_exists(wavLocale) then
        path = wavLocale
    end

    system.playFile(path)
end

utils._imagePathCache = {}
utils._imageBitmapCache = {}

function utils.loadImage(image1, image2, image3)
    local function candidates(image)
        if type(image) ~= "string" then
            return {}
        end

        local out = {image, "BITMAPS:" .. image, "SYSTEM:" .. image}

        if image:match("%.png$") then
            out[#out + 1] = image:gsub("%.png$", ".bmp")
        elseif image:match("%.bmp$") then
            out[#out + 1] = image:gsub("%.bmp$", ".png")
        end

        return out
    end

    local function getCachedBitmap(key, tryPaths)
        if not key then
            return nil
        end

        if utils._imageBitmapCache[key] then
            return utils._imageBitmapCache[key]
        end

        local path = utils._imagePathCache[key]
        if not path then
            for _, candidate in ipairs(tryPaths) do
                if utils.file_exists(candidate) then
                    path = candidate
                    break
                end
            end
            utils._imagePathCache[key] = path
        end

        if not path then
            return nil
        end

        local bitmap = lcd.loadBitmap(path)
        utils._imageBitmapCache[key] = bitmap
        return bitmap
    end

    return getCachedBitmap(image1, candidates(image1))
        or getCachedBitmap(image2, candidates(image2))
        or getCachedBitmap(image3, candidates(image3))
end

function utils.sanitize_filename(value)
    if not value or value == "" then
        return "default"
    end

    local cleaned = tostring(value):gsub("[\\/:%*%?\"<>|]+", "_"):gsub("%s+", "_")
    cleaned = cleaned:gsub("_+", "_"):gsub("^_+", ""):gsub("_+$", "")
    if cleaned == "" then
        cleaned = "default"
    end
    return cleaned
end

function utils.simSensors(id)
    if id == nil then
        return 0
    end

    local primaryPath = "sim/sensors/" .. id .. ".lua"
    local fallbackPath = "SCRIPTS:/" .. ofs3.config.baseDir .. "/sim/sensors/" .. id .. ".lua"

    local chunk = loadfile(primaryPath)
    if not chunk and primaryPath ~= fallbackPath then
        chunk = loadfile(fallbackPath)
    end

    if not chunk then
        return 0
    end

    local ok, result = pcall(chunk)
    if not ok then
        return 0
    end

    return result
end

function utils.ethosVersionAtLeast(targetVersion)
    local env = system.getVersion and system.getVersion() or {}
    local currentVersion = {tonumber(env.major) or 0, tonumber(env.minor) or 0, tonumber(env.revision) or 0}

    targetVersion = targetVersion or {0, 0, 0}
    if type(targetVersion) ~= "table" then
        return false
    end

    for i = 1, 3 do
        local target = tonumber(targetVersion[i]) or 0
        if currentVersion[i] > target then
            return true
        elseif currentVersion[i] < target then
            return false
        end
    end

    return true
end

function utils.session()
    ofs3.session = {
        telemetryState = false,
        telemetryType = nil,
        telemetrySensor = nil,
        isConnected = false,
        isConnectedHigh = false,
        isConnectedLow = false,
        isArmed = false,
        mcu_id = nil,
        craftName = model.name and model.name() or nil,
        batteryConfig = nil,
        modelPreferences = nil,
        modelPreferencesFile = nil,
        timer = {
            start = nil,
            live = 0,
            lifetime = 0,
            session = 0,
            baseLifetime = 0
        },
        flightCounted = false,
        rx = {
            map = {},
            values = {}
        }
    }
end

function utils.rxmapReady()
    local rx = ofs3.session and ofs3.session.rx
    local map = rx and rx.map or nil
    if map and (map.collective or map.elevator or map.throttle or map.rudder or map.arm or map.headspeed) then
        return true
    end
    return false
end

return utils
