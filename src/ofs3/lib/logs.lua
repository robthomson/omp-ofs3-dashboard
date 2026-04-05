--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local logs = {}

local ROOT_DIR = "LOGS:"
local BASE_DIR = "LOGS:/ofs3"
local TELEMETRY_DIR = "LOGS:/ofs3/telemetry"

local function ensureDirectories()
    os.mkdir(ROOT_DIR)
    os.mkdir(BASE_DIR)
    os.mkdir(TELEMETRY_DIR)
end

local function extractSortKey(name)
    if type(name) ~= "string" then
        return ""
    end

    local date, time, unique = name:match("^(%d%d%d%d%-%d%d%-%d%d)_(%d%d%-%d%d%-%d%d)_?(%d*)%.csv$")
    if date and time then
        return string.format("%sT%s_%s", date, time, unique or "")
    end

    return name
end

function logs.getDirectory()
    ensureDirectories()
    return TELEMETRY_DIR
end

function logs.getRecentEntries(limit)
    ensureDirectories()

    local files = system.listFiles(TELEMETRY_DIR) or {}
    local entries = {}

    for _, name in ipairs(files) do
        if type(name) == "string" and name:match("%.csv$") then
            entries[#entries + 1] = {
                name = name,
                sortKey = extractSortKey(name)
            }
        end
    end

    table.sort(entries, function(a, b)
        return (a.sortKey or "") > (b.sortKey or "")
    end)

    if limit and #entries > limit then
        for index = #entries, limit + 1, -1 do
            entries[index] = nil
        end
    end

    return entries
end

function logs.formatDuration(seconds)
    local total = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(total / 3600)
    local minutes = math.floor((total % 3600) / 60)
    local secs = total % 60

    if hours > 0 then
        return string.format("%dh %02dm %02ds", hours, minutes, secs)
    end

    return string.format("%dm %02ds", minutes, secs)
end

function logs.getSummary()
    local prefs = ofs3.session and ofs3.session.modelPreferences or nil

    return {
        craftName = (ofs3.session and ofs3.session.craftName) or (model.name and model.name()) or "Model",
        flightCount = tonumber(ofs3.ini.getvalue(prefs, "general", "flightcount")) or 0,
        lastFlightTime = tonumber(ofs3.ini.getvalue(prefs, "general", "lastflighttime")) or 0,
        totalFlightTime = tonumber(ofs3.ini.getvalue(prefs, "general", "totalflighttime")) or 0
    }
end

return logs
