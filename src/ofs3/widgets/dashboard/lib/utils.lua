--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

-- Thin compatibility shim -- widgets/dashboard/lib/utils.lua.
--
-- The real rendering/theme-support context now lives in the shared
-- `dashboard` package (a hard dependency -- see that repo's own
-- docs/dashboard-spec.md; this suite doesn't register a dashboard widget of
-- its own any more, see tasks/background.lua's own header). This file still
-- has to exist at exactly this path because the @rt-rc theme's own
-- preflight.lua/inflight.lua/postflight.lua and tools/logs.lua both load it
-- via this suite's own established absolute-path convention
-- ("SCRIPTS:/" .. ofs3.config.baseDir .. "/widgets/dashboard/lib/utils.lua")
-- -- unlike rotorflight/wingflight's own themes, these were never bare
-- relative loadfile() calls, so this shim exists purely so something still
-- lives at the path they already expect, not to route around Ethos's
-- relative-path resolution rules (see the sibling `dashboard` repo's own
-- lib/require.lua for that whole story, which doesn't apply here).
--
-- Cached on the `ofs3` namespace table itself (matching this suite's own
-- idiom -- e.g. ofs3.utils, ofs3.tasks.telemetry -- rather than
-- package.loaded[...] keys, which nothing else in this suite uses) so this
-- file's own absolute loadfile() only happens once per session; every
-- caller after the first (the log tool, and each theme reload) gets the
-- same cached table back.
--
-- Returns context.widgets.dashboard.utils, NOT the context object itself:
-- this suite's own (pre-shim) lib/utils.lua returned the rendering-utils
-- table directly (themeColors/resolveFont/getThemeState/etc, no wrapping),
-- and every existing caller -- the theme files, tools/logs.lua's own
-- getDashboardUtils() -- was written against that flat shape. The shared
-- package's context.lua nests that same table at .widgets.dashboard.utils
-- (it also carries session/tasks.telemetry/etc at the top level, none of
-- which this suite ever routed through this file -- ofs3.session/
-- ofs3.tasks.telemetry are separate, populated by ofs3.runtime directly).
-- Returning the bare context here silently handed callers a table with no
-- themeColors/getThemeState/etc of its own, since those live one level
-- down -- confirmed on device (preflight.lua's own `utils.themeColors()`
-- failing as "not callable").
--
-- If SCRIPTS:/dashboard isn't installed, the assert() below throws -- there
-- is no guard in this suite to catch that gracefully (that responsibility
-- moved entirely to the shared package's own widget, which simply won't
-- register itself).

local ofs3 = require("ofs3")

if ofs3._dashboardContextShim then
  return ofs3._dashboardContextShim
end

local context = assert(loadfile("SCRIPTS:/dashboard/widgets/dashboard/context.lua"))()
local utils = context.widgets.dashboard.utils
ofs3._dashboardContextShim = utils
return utils
