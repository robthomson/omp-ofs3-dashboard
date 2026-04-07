--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = {
    session = {},
    widgets = {},
    tools = {},
    theme = {version = 0},
    flightmode = {current = "preflight"},
    app = {guiIsRunning = false}
}

package.loaded.ofs3 = ofs3

ofs3.config = {
    toolName = "OFS3 Dashboard",
    baseDir = "ofs3",
    preferences = "ofs3.user",
    version = {major = 0, minor = 1, revision = 0, suffix = "DEV"}
}

ofs3.preferences = {
    general = {
        gimbalsupression = 0.85
    },
    events = {
        armed = true,
        voltage = true,
        smartfuel = true,
        profile = true
    },
    localizations = {
        temperature_unit = 0,
        altitude_unit = 0
    },
    developer = {
        overlaygrid = false,
        overlaystats = false,
        logobjprof = false,
        telemetrytrace = false
    }
}

local function ensureSharedModules()
    if not ofs3.ini then
        ofs3.ini = assert(loadfile("lib/ini.lua"))()
    end

    if not ofs3.utils then
        ofs3.utils = assert(loadfile("lib/utils.lua"))(ofs3.config)
    end

    if not ofs3._sessionInitialized then
        ofs3.utils.session()
        ofs3._sessionInitialized = true
    end

    if not ofs3.logs then
        ofs3.logs = assert(loadfile("lib/logs.lua"))(ofs3.config)
    end
end

local function ensureWidgetModules()
    ensureSharedModules()

    ofs3.tasks = ofs3.tasks or {}

    if not ofs3.tasks.telemetry then
        ofs3.tasks.telemetry = assert(loadfile("lib/telemetry.lua"))(ofs3.config)
    end

    if not ofs3.sensors then
        ofs3.sensors = assert(loadfile("lib/sensors.lua"))(ofs3.config)
    end

    if not ofs3.events then
        ofs3.events = assert(loadfile("lib/events.lua"))(ofs3.config)
    end

    if not ofs3.runtime then
        ofs3.runtime = assert(loadfile("lib/runtime.lua"))(ofs3.config)
    end

    if not ofs3.widgets.dashboard then
        ofs3.widgets.dashboard = assert(loadfile("widgets/dashboard/dashboard.lua"))(ofs3.config)
    end

    if not ofs3.widgets.dashboardConfigure then
        ofs3.widgets.dashboardConfigure = assert(loadfile("widgets/dashboard/configure.lua"))(ofs3.config)
    end
end

local function ensureLogsTool()
    ensureSharedModules()

    if not ofs3.tools.logs then
        ofs3.tools.logs = assert(loadfile("tools/logs.lua"))(ofs3.config)
    end
end

local function callWidget(method, ...)
    ensureWidgetModules()
    return ofs3.widgets.dashboard[method](...)
end

local function callWidgetConfigure(method, ...)
    ensureWidgetModules()
    return ofs3.widgets.dashboardConfigure[method](...)
end

local function callLogsTool(method, ...)
    ensureLogsTool()
    local tool = ofs3.tools.logs
    local handler = tool and tool[method]
    if handler then
        return handler(...)
    end
end

local function closeLogsTool(...)
    local tool = ofs3.tools and ofs3.tools.logs
    if tool and tool.close then
        return tool.close(...)
    end
end

local function loadToolIcon(path)
    if not lcd or not path then
        return nil
    end

    local candidates = {
        path,
        "SCRIPTS:/" .. ofs3.config.baseDir .. "/" .. path
    }

    for _, candidate in ipairs(candidates) do
        if lcd.loadMask then
            local ok, loaded = pcall(lcd.loadMask, candidate)
            if ok and loaded then
                return loaded
            end
        end

        if lcd.loadBitmap then
            local ok, loaded = pcall(lcd.loadBitmap, candidate)
            if ok and loaded then
                return loaded
            end
        end
    end

    return nil
end

local function registerWidget()
    system.registerWidget({
        key = "ofs3dsh",
        name = "OFS3 Dashboard",
        create = function(...)
            return callWidget("create", ...)
        end,
        configure = function(...)
            return callWidgetConfigure("configure", ...)
        end,
        paint = function(...)
            return callWidget("paint", ...)
        end,
        event = function(...)
            return callWidget("event", ...)
        end,
        menu = function(...)
            return callWidget("menu", ...)
        end,
        wakeup = function(...)
            return callWidget("wakeup", ...)
        end,
        read = function(...)
            return callWidgetConfigure("read", ...)
        end,
        write = function(...)
            return callWidgetConfigure("write", ...)
        end,
        title = false,
        persistent = false
    })
end

local function registerLogsTool()
    if not system.registerSystemTool then
        return
    end

    system.registerSystemTool({
        name = "OFS3 Logs",
        icon = loadToolIcon("widgets/dashboard/gfx/icon.png"),
        create = function(...)
            return callLogsTool("create", ...)
        end,
        wakeup = function(...)
            return callLogsTool("wakeup", ...)
        end,
        paint = function(...)
            return callLogsTool("paint", ...)
        end,
        event = function(...)
            return callLogsTool("event", ...)
        end,
        close = function(...)
            return closeLogsTool(...)
        end
    })
end

local function init()
    registerWidget()
    registerLogsTool()
end

return {init = init}
