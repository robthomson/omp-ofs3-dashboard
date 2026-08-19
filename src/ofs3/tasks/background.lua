--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

-- Background task -- new in this repo. ofs3 previously had no task/bus
-- layer at all: lib/runtime.lua's own wakeup() ran directly inside the
-- dashboard widget's own wakeup(), which was fine since there's no MSP
-- handshake here to keep alive independent of the widget (ofs3 is a pure
-- telemetry decoder for the OFS3 FBL's own custom sensor stream -- no
-- bidirectional link, nothing that needs to keep running when no screen is
-- showing it).
--
-- This suite now registers a real background task instead, publishing a
-- Dashboard-Spec-shaped "session.update" snapshot via lib/bus.lua, so this
-- suite's own dashboard widget can be retired in favour of the shared
-- `dashboard` package's own standalone widget (the same integration
-- rotorflight/wingflight already use) rather than maintaining a second,
-- separate rendering/theme engine here -- see the sibling `dashboard`
-- repo's own docs/dashboard-spec.md.
--
-- lib/runtime.lua's own wakeup()/resetFlight() logic is UNCHANGED by this,
-- called exactly as the widget used to call it -- still the single source
-- of truth for telemetry/flightmode/timer/stats/rx-channel derivation,
-- INCLUDING the S.Port-vs-CRSF channel-index divergence in its own
-- initializeRxMap() (arm at channel 7 on S.Port, channel 4 otherwise;
-- throttle/collective/headspeed differ too) -- this file never touches that
-- logic, only calls into it. This file's own job is purely translation:
-- ofs3.session/ofs3.tasks.telemetry's already-computed state, read the same
-- way the old widget/theme read it, packaged into the Dashboard Spec's own
-- field names and published.

local ofs3 = require("ofs3")

local function ensureBackgroundModules()
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
  if not ofs3.bus then
    ofs3.bus = assert(loadfile("lib/bus.lua"))()
  end

  ofs3.tasks = ofs3.tasks or {}
  -- Load order matters: lib/runtime.lua's own top-level body captures
  -- `ofs3.tasks.telemetry` into a local at load time, so telemetry (and
  -- sensors/events, which runtime.wakeup() also reaches for) must already
  -- exist before runtime.lua is first loaded -- matches the exact order
  -- the old widgets/dashboard/dashboard.lua's own ensureWidgetModules() used.
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
end

-- Dashboard Spec's own batteryConfig shape (cellCount/vbatMinCell/
-- vbatMaxCell/vbatFullCell) differs from ofs3's own model-preferences field
-- names (batteryCellCount/vbatmincellvoltage/vbatmaxcellvoltage/
-- vbatfullcellvoltage) -- translated here, not renamed at the source, since
-- ofs3's own ini file / configure UI keep their existing field names
-- regardless of this integration.
local function buildBatteryConfig()
  local cfg = ofs3.session.batteryConfig
  if type(cfg) ~= "table" then return nil end
  return {
    cellCount = cfg.batteryCellCount,
    vbatMinCell = cfg.vbatmincellvoltage,
    vbatMaxCell = cfg.vbatmaxcellvoltage,
    vbatFullCell = cfg.vbatfullcellvoltage,
  }
end

-- armed sensor polarity: 0 means armed, matching lib/runtime.lua's own
-- determineFlightMode() ("local inFlight = armed == 0 and rpm > 1000") --
-- preserved exactly, not reinterpreted.
local function isArmed()
  local telemetry = ofs3.tasks.telemetry
  local value = telemetry and telemetry.getSensor and telemetry.getSensor("armed")
  if value == nil then return nil end
  return value == 0
end

-- Builds the Dashboard Spec's own `widget` snapshot shape from whatever
-- lib/runtime.lua's own wakeup() (called just before this, every tick) has
-- already computed -- reads every field exactly the way the old dashboard
-- widget/theme boxes used to (ofs3.session.*, ofs3.tasks.telemetry.
-- getSensor()), just packaged under the Dashboard Spec's own field names
-- instead of handed straight to a local rendering engine. See
-- docs/dashboard-spec.md in the sibling `dashboard` repo for the full
-- field table this maps onto.
local function buildSnapshot()
  local telemetry = ofs3.tasks.telemetry
  local session = ofs3.session

  return {
    connected = session.isConnected == true,
    isArmed = isArmed(),
    craftName = session.craftName,
    mcuId = session.mcu_id,

    voltage = telemetry.getSensor("voltage"),
    current = telemetry.getSensor("current"),
    consumption = telemetry.getSensor("consumption"),
    rpm = telemetry.getSensor("rpm"),
    rssi = telemetry.getSensor("rssi"),
    tempEsc = telemetry.getSensor("temp_esc"),
    fuelPercent = telemetry.getSensor("smartfuel"),
    -- Generic flight-profile readout -- see context.lua's own sensorValue()
    -- comment in the shared package for why this is its own field.
    profile = telemetry.getSensor("profile"),

    batteryConfig = buildBatteryConfig(),

    timerLive = session.timer and session.timer.live or 0,
    timerSession = session.timer and session.timer.session or 0,
    timerTarget = 300,
    modelStats = session.modelPreferences and session.modelPreferences.general,

    flightmodeState = ofs3.flightmode.current or "preflight",
  }
end

local function publishSnapshot()
  ofs3.bus.publish("session.update", buildSnapshot())
end

-- Mirrors rotorflight-lua-ethos-suite's own tasks/session.lua
-- buildToolbarSpec() -- but ofs3 has no MSP at all, so erase_blackbox/
-- battery_profile are omitted entirely rather than published disabled --
-- there's no firmware feature behind them that could ever become available,
-- unlike rf/wf's own use of enabled=false for "not connected right now".
-- The shared package's own toolbar.lua only draws a slot for an action its
-- host's spec actually includes (see its own comment there).
--
-- Neither action needs an icon override: widgets/dashboard/gfx/
-- toolbar_reset.png and toolbar_app.png are both copied verbatim from
-- rotorflight-lua-ethos-suite's own copies (the same 55px toolbar-icon size
-- class ACTION_META's own defaults expect, unlike this suite's own
-- icon.png/logs.png/settings.png/etc, which are sized for the system
-- tool's own button grid instead -- an earlier pass here used those and
-- they looked visibly the wrong size in the toolbar specifically).
--
-- launch_app DOES need a label override: it opens this suite's own "OFS3"
-- system tool (see main.lua), which now opens on a Logs/Settings hub
-- rather than jumping straight into the log list -- "Setup" (ACTION_META's
-- own default label for launch_app) doesn't describe that, "Settings" does.
local function buildToolbarSpec()
  return {
    {action = "reset_flight", enabled = true},
    {action = "launch_app", enabled = true, label = "Settings"},
  }
end

local function publishToolbarSpec()
  ofs3.bus.publish("dashboard.toolbar", buildToolbarSpec())
end

local logsToolHandle = nil

local function taskInit()
  ensureBackgroundModules()

  ofs3.bus.subscribe("flightmode.reset", function()
    ofs3.runtime.resetFlight()
  end)

  -- "reset_flight" doesn't need systemToolHandle, so it's handled here like
  -- rf/wf's own tasks/session.lua handles erase_blackbox/battery_profile;
  -- "launch_app" needs logsToolHandle (only known once main.lua's own
  -- registerLogsTool() has registered it -- see setLogsToolHandle() below,
  -- called from there) and is handled here too, unlike rf/wf where it has
  -- to live in widgets/dashboard.lua because only that file has the handle.
  ofs3.bus.subscribe("dashboard.action", function(payload)
    if type(payload) ~= "table" then return end
    if payload.action == "reset_flight" then
      ofs3.runtime.resetFlight()
    elseif payload.action == "launch_app" then
      if logsToolHandle ~= nil and system.openPage then
        system.openPage({system = logsToolHandle})
      end
    end
  end)
end

local function taskWakeup()
  ofs3.runtime.wakeup()
  publishSnapshot()
  publishToolbarSpec()
  ofs3.bus.publish("task.status", {running = true})
end

local function taskEvent()
end

local background = {}

-- Called from main.lua's own registerLogsTool(), once system.registerSystemTool
-- has returned a handle -- see this file's own taskInit() for why launch_app
-- needs it here rather than in a separate widget file (there isn't one any
-- more).
function background.setLogsToolHandle(handle)
  logsToolHandle = handle
end

function background.init()
  system.registerTask({
    key = "ofs3bg",
    name = "OFS3 [Background]",
    init = taskInit,
    wakeup = taskWakeup,
    event = taskEvent,
  })
end

return background
