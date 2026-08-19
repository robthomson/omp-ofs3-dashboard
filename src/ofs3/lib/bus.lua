-- Minimal publish/subscribe message bus.
--
-- Ported near-verbatim from rotorflight-lua-ethos-suite's own lib/bus.lua
-- (same pattern used by wingflight-lua-ethos-suite) -- this is the channel
-- tasks/background.lua and the shared `dashboard` package's own standalone
-- widget (SCRIPTS:/dashboard) use to talk to each other, now that this
-- suite has a real background task. See tasks/background.lua's own header
-- for why ofs3 has one now (it didn't before -- this repo used to compute
-- everything inline in the dashboard widget's own wakeup()).
--
-- Every subsystem loads this file the same way:
--   local bus = assert(loadfile("lib/bus.lua"))()
-- `loadfile` alone would produce a *new*, independent chunk (and therefore a
-- new, disconnected bus) on every call, since each subsystem is loaded from
-- its own separate file. To keep a single shared instance without resorting
-- to an ad hoc global, this module caches itself once under a namespaced key
-- in Lua's own module registry (`package.loaded`) -- the same mechanism
-- `require()` uses internally. That key holds exactly one thing: this bus
-- table. It is not a place to accumulate unrelated shared state.
--
-- Only selected topics are retained and replayed to new subscribers.
-- "session.update" is retained because a widget subscribing after boot
-- (e.g. the shared dashboard package's own standalone widget) needs the
-- current snapshot immediately, even if nothing has changed since. "task.
-- status" is retained for the same reason -- a late subscriber can tell
-- whether the background task has ever run. "dashboard.toolbar" is retained
-- so a late subscriber gets the current toolbar spec immediately too.
-- Transient command topics ("dashboard.action", "dashboard.action.progress",
-- "flightmode.reset") must NOT be retained -- replaying a stale one to a
-- future subscriber would be actively wrong, not merely redundant.

local BUS_VERSION = 1

local cached = package.loaded["ofs3.bus"]
if cached and cached._version == BUS_VERSION then
  return cached
end

local subscribers = {}
local lastPublished = {}
local retainedTopics = {
  ["session.update"] = true,
  ["task.status"] = true,
  ["dashboard.toolbar"] = true,
}

local function subscribe(topic, handler)
  local list = subscribers[topic]
  if not list then
    list = {}
    subscribers[topic] = list
  end
  list[#list + 1] = handler

  local last = retainedTopics[topic] and lastPublished[topic] or nil
  if last ~= nil then
    local ok, err = pcall(handler, last)
    if not ok then
      print("[bus] handler error replaying last '" .. topic .. "' to new subscriber: " .. tostring(err))
    end
  end

  return handler
end

local function unsubscribe(topic, handler)
  local list = subscribers[topic]
  if not list then
    return
  end
  for i = #list, 1, -1 do
    if list[i] == handler then
      table.remove(list, i)
    end
  end
end

local function publish(topic, payload)
  if retainedTopics[topic] then
    lastPublished[topic] = payload
  else
    lastPublished[topic] = nil
  end

  local list = subscribers[topic]
  if not list then
    return
  end
  -- Iterate a copy so a handler unsubscribing mid-publish can't skip entries.
  local snapshot = {}
  for i = 1, #list do
    snapshot[i] = list[i]
  end
  for i = 1, #snapshot do
    local ok, err = pcall(snapshot[i], payload)
    if not ok then
      print("[bus] handler error on '" .. topic .. "': " .. tostring(err))
    end
  end
end

local bus = {
  _version = BUS_VERSION,
  subscribe = subscribe,
  unsubscribe = unsubscribe,
  publish = publish,
}

package.loaded["ofs3.bus"] = bus

return bus
