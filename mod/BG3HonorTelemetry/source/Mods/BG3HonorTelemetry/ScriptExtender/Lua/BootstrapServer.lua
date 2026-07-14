-- Optional, read-only event bridge for BG3 Honor Mode Assistant.
-- This script only subscribes to events and overwrites one local JSON snapshot.
-- It never calls Osiris mutation functions, reads saves, or completes guide state.

local PRODUCER_ID = "bg3-honor-telemetry"
local PRODUCER_VERSION = "0.1.0"
local SCHEMA_VERSION = 1
local MAX_EVENTS = 64

local sequence = 0
local events = {}
local sessionId = "session-" .. tostring(Ext.Timer.MonotonicTime())

local function getenv(name)
    if os == nil or os.getenv == nil then return nil end
    local ok, value = pcall(os.getenv, name)
    if ok then return value end
    return nil
end

local function outputPath()
    local configured = getenv("BG3_TELEMETRY_FILE")
    if configured ~= nil and configured ~= "" then return configured end
    local home = getenv("HOME")
    if home ~= nil and home ~= "" then
        return home .. "/Library/Application Support/BG3HonorAssistant/telemetry/events.json"
    end
    local localAppData = getenv("LOCALAPPDATA")
    if localAppData ~= nil and localAppData ~= "" then
        return localAppData .. "\\BG3HonorAssistant\\telemetry\\events.json"
    end
    return nil
end

local function text(value)
    if value == nil then return nil end
    return tostring(value)
end

local function stringPayload(values)
    -- Keep the table object-shaped even when the event has no extra fields;
    -- an empty Lua table is otherwise ambiguous to JSON serializers.
    local result = { source = "osiris" }
    for key, value in pairs(values or {}) do
        if value ~= nil then result[tostring(key)] = tostring(value) end
    end
    return result
end

local function writeSnapshot()
    local path = outputPath()
    if path == nil then return false end
    local snapshot = {
        schema_version = SCHEMA_VERSION,
        producer_id = PRODUCER_ID,
        producer_version = PRODUCER_VERSION,
        session_id = sessionId,
        written_at = Ext.Timer.MonotonicTime() / 1000,
        sequence = sequence,
        events = events,
    }
    local ok, json = pcall(Ext.Json.Stringify, snapshot)
    if not ok then return false end
    local saved, result = pcall(Ext.IO.SaveFile, path, json)
    return saved and result == true
end

local function emit(kind, values)
    sequence = sequence + 1
    values = values or {}
    table.insert(events, {
        sequence = sequence,
        kind = kind,
        emitted_at = Ext.Timer.MonotonicTime() / 1000,
        actor = text(values.actor),
        target = text(values.target),
        combat_id = text(values.combat_id),
        payload = stringPayload(values.payload),
    })
    while #events > MAX_EVENTS do table.remove(events, 1) end
    writeSnapshot()
end

local function listen(name, arity, callback)
    local ok = pcall(Ext.Osiris.RegisterListener, name, arity, "after", callback)
    if not ok then
        Ext.Print("[BG3HonorTelemetry] Listener unavailable: " .. name)
    end
end

listen("EnteredCombat", 2, function(actor, combat)
    emit("combat_entered", { actor = actor, combat_id = combat })
end)
listen("LeftCombat", 2, function(actor, combat)
    emit("combat_left", { actor = actor, combat_id = combat })
end)
listen("CombatEnded", 1, function(combat)
    emit("combat_ended", { combat_id = combat })
end)
listen("CombatRoundStarted", 2, function(combat, round)
    emit("combat_round", { combat_id = combat, payload = { round = round } })
end)
listen("TurnStarted", 1, function(actor)
    emit("turn_started", { actor = actor })
end)
listen("TurnEnded", 1, function(actor)
    emit("turn_ended", { actor = actor })
end)
listen("DownedChanged", 2, function(actor, downed)
    if downed == 1 then emit("downed", { actor = actor }) end
end)
listen("Died", 1, function(actor)
    emit("died", { actor = actor })
end)
listen("Resurrected", 1, function(actor)
    emit("resurrected", { actor = actor })
end)
listen("RollResult", 6, function(eventName, roller, rollSubject, resultType, isActiveRoll, criticality)
    emit("roll_result", {
        actor = roller,
        payload = {
            event = eventName,
            subject = rollSubject,
            result = resultType,
            success = resultType,
            active = isActiveRoll,
            criticality = criticality,
        },
    })
end)
listen("DialogRollResult", 5, function(actor, success, dialog, isDetectThoughts, criticality)
    emit("dialog_roll", {
        actor = actor,
        payload = {
            dialog = dialog,
            success = success,
            detect_thoughts = isDetectThoughts,
            criticality = criticality,
        },
    })
end)
listen("LeveledUp", 1, function(actor)
    emit("leveled_up", { actor = actor })
end)
listen("Equipped", 2, function(item, actor)
    emit("equipped", { actor = actor, target = item })
end)
listen("Unequipped", 2, function(item, actor)
    emit("unequipped", { actor = actor, target = item })
end)
listen("LongRestStarted", 0, function()
    emit("long_rest_started")
end)
listen("LongRestFinished", 0, function()
    emit("long_rest_finished")
end)
listen("ShortRested", 1, function(actor)
    emit("short_rested", { actor = actor })
end)

Ext.Events.SessionLoaded:Subscribe(function()
    sessionId = "session-" .. tostring(Ext.Timer.MonotonicTime())
    sequence = 0
    events = {}
    emit("session_loaded")
end)

emit("bridge_started")
Ext.Timer.WaitFor(2000, function()
    writeSnapshot()
end, 2000)
