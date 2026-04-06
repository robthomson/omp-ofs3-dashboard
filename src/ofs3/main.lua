--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = {
    session = {},
    widgets = {},
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

ofs3.ini = assert(loadfile("lib/ini.lua"))()
ofs3.utils = assert(loadfile("lib/utils.lua"))(ofs3.config)

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
        logobjprof = false
    }
}

ofs3.utils.session()

ofs3.tasks = {
    telemetry = assert(loadfile("lib/telemetry.lua"))(ofs3.config)
}

ofs3.logs = assert(loadfile("lib/logs.lua"))(ofs3.config)
ofs3.sensors = assert(loadfile("lib/sensors.lua"))(ofs3.config)
ofs3.events = assert(loadfile("lib/events.lua"))(ofs3.config)
ofs3.runtime = assert(loadfile("lib/runtime.lua"))(ofs3.config)
ofs3.widgets.dashboard = assert(loadfile("widgets/dashboard/dashboard.lua"))(ofs3.config)
ofs3.widgets.dashboardConfigure = assert(loadfile("widgets/dashboard/configure.lua"))(ofs3.config)

local function init()
    local dashboard = ofs3.widgets.dashboard
    local dashboardConfigure = ofs3.widgets.dashboardConfigure

    system.registerWidget({
        key = "ofs3dsh",
        name = "OFS3 Dashboard",
        create = dashboard.create,
        configure = dashboardConfigure.configure,
        paint = dashboard.paint,
        event = dashboard.event,
        menu = dashboard.menu,
        wakeup = dashboard.wakeup,
        read = dashboardConfigure.read,
        write = dashboardConfigure.write,
        title = false,
        persistent = false
    })
end

return {init = init}
