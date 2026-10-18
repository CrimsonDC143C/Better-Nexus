-- Optional, failure-isolated StutterAlert diagnostic-provider integration.

Nexus = Nexus or {}

local Integration = {}
Nexus.StutterAlertIntegration = Integration

local ADDON_NAME = "Nexus"
local API_VERSION = 1
local MAX_OPERATIONS = 5
local PRIORITY = {
    ["automation.fallback.repair"] = 4,
    ["automation.step"] = 3,
    ["gameadapter.poll"] = 2,
    ["automation.update"] = 1,
}

local registeredApi = nil

local function FiniteNumber(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge
        or number == -math.huge then return nil end
    return number
end

local function CorrelationWindow(context)
    if type(context) ~= "table" then return nil end
    if context.addonName ~= nil and context.addonName ~= ADDON_NAME then return nil end
    local windowStart = FiniteNumber(context.hitchStartTime)
    local windowEnd = FiniteNumber(context.hitchEndTime)
    if not windowStart or not windowEnd or windowEnd < windowStart then return nil end

    local profilingAt = FiniteNumber(context.profilingTimestamp)
    local profileWindowMs = FiniteNumber(context.profileWindowMs)
    if profilingAt and profileWindowMs and profileWindowMs >= 0 then
        windowStart = math.min(windowStart, profilingAt - (profileWindowMs / 1000))
        windowEnd = math.max(windowEnd, profilingAt)
    end
    return windowStart, windowEnd,
        FiniteNumber(context.hitchStartTime), FiniteNumber(context.hitchEndTime),
        profilingAt and profileWindowMs and profileWindowMs >= 0
            and profilingAt - (profileWindowMs / 1000) or nil,
        profilingAt
end

local function CopyProviderFields(fields)
    local copied = {}
    for index = 1, math.min(4, type(fields) == "table" and #fields or 0) do
        local field = fields[index]
        if type(field) == "table" and type(field.key) == "string"
            and (type(field.value) == "string" or type(field.value) == "number"
                or type(field.value) == "boolean") then
            copied[#copied + 1] = {key=field.key, value=field.value}
        end
    end
    return copied
end

local DIAGNOSTIC_NAMES = {}
for _, name in ipairs({"orb.status","orb.read","orb.panel","echo.reconcile",
    "hud.prepare","lifecycle.update","sync.update","gameadapter.poll",
    "dps.update","lifecycle.phase.catalog"}) do DIAGNOSTIC_NAMES[name] = true end
local DIAGNOSTIC_NUMBERS = {"id","parentId","depth","resetGeneration","clockGeneration",
    "startedMs","endedMs","elapsedMs","childElapsedMs","residualMs","sessionStart",
    "sessionEnd","sessionClockGeneration","heapBeforeKB","heapAfterKB","heapNetKB"}
local DIAGNOSTIC_FLAGS = {"elapsedAvailable","childCoverageAvailable","residualAvailable",
    "sessionWindowAvailable","heapAvailable","succeeded"}
local DIAGNOSTIC_REASONS = {available=true,frozen_or_zero_window=true,
    unavailable_or_changed=true,failed=true}
local function DiagnosticOverlapUnsafe(performance, windowStart, windowEnd)
    -- Optional extension lookup and data projection must never invalidate the
    -- established v1 operations. rawget avoids optional-method metamethods;
    -- the caller isolates the entire optional call with pcall.
    local enabledMethod = type(performance)=="table" and rawget(performance,"DiagnosticEnabled") or nil
    if type(enabledMethod)=="function" and enabledMethod()~=true then
        return {version=1,enabled=false,spans={},unmatchedSpanCount=0}, {}
    end
    local method = type(performance)=="table" and rawget(performance,"SnapshotDiagnostics") or nil
    if type(method)~="function" then return nil, {} end
    local diagnostic = method()
    if type(diagnostic)~="table" or rawget(diagnostic,"version")~=1 then return nil, {} end
    local selected, unmatched = {}, 0
    local enabled = rawget(diagnostic,"enabled")==true
    local retained = rawget(diagnostic,"spans")
    if enabled and type(retained)=="table" then
        -- The product snapshot has a 32-row ring; optional replacement data
        -- cannot widen collection or inject arbitrary span fields/names.
        for index=1,32 do
            local span = rawget(retained,index)
            if span==nil then break end
            local copy
            if type(span)=="table" then
                local name = rawget(span,"name")
                if type(name)=="string" and DIAGNOSTIC_NAMES[name] then
                    copy = {name=name}
                    for _, key in ipairs(DIAGNOSTIC_NUMBERS) do copy[key]=FiniteNumber(rawget(span,key)) end
                    for _, key in ipairs(DIAGNOSTIC_FLAGS) do copy[key]=rawget(span,key)==true end
                    local reason = rawget(span,"sessionWindowReason")
                    copy.sessionWindowReason = type(reason)=="string" and DIAGNOSTIC_REASONS[reason] and reason or nil
                end
            end
            -- Actual session observations only. Frozen GetTime bounds cannot
            -- be stretched using another clock's elapsed milliseconds.
            if copy and copy.sessionWindowAvailable and copy.sessionStart and copy.sessionEnd
                and copy.sessionEnd>copy.sessionStart and copy.elapsedAvailable
                and copy.elapsedMs and copy.elapsedMs>=0 then
                if copy.sessionEnd>=windowStart and copy.sessionStart<=windowEnd then
                    selected[#selected+1]=copy
                end
            else unmatched=unmatched+1 end
        end
        table.sort(selected,function(a,b)
            if a.elapsedMs~=b.elapsedMs then return a.elapsedMs>b.elapsedMs end
            return (a.id or 0)>(b.id or 0)
        end)
        for index=#selected,MAX_OPERATIONS+1,-1 do selected[index]=nil end
    end
    return {version=1,enabled=enabled,clockGeneration=FiniteNumber(rawget(diagnostic,"clockGeneration")),
        resetGeneration=FiniteNumber(rawget(diagnostic,"resetGeneration")),spans=selected,
        unmatchedSpanCount=unmatched,
        elapsedClock=rawget(diagnostic,"elapsedClock")=="injected millisecond clock" and "injected millisecond clock"
            or rawget(diagnostic,"elapsedClock")=="debugprofilestop" and "debugprofilestop"
            or rawget(diagnostic,"elapsedClock")=="GetTime milliseconds" and "GetTime milliseconds" or nil,
        sessionClock=rawget(diagnostic,"sessionClock")=="injected session clock" and "injected session clock"
            or rawget(diagnostic,"sessionClock")=="GetTime" and "GetTime" or nil,
        heapMetric=rawget(diagnostic,"heapMetric")=="injected global Lua heap reader" and "injected global Lua heap reader"
            or rawget(diagnostic,"heapMetric")=="collectgarbage count; global Lua heap" and "collectgarbage count; global Lua heap" or nil,
        heapIncludesInstrumentation=true,
        heapMeaning="global net Lua heap change; not allocated bytes or GC time",
        residualMeaning="elapsed residual after valid direct-child coverage; not addon CPU"}, selected
end

local function CollectUnsafe(context)
    local windowStart, windowEnd, frameStart, frameEnd, profileStart, profileEnd = CorrelationWindow(context)
    if not windowStart then return nil end
    local performance = Nexus and Nexus.Performance
    if not (performance and type(performance.RecentOperations) == "function") then
        return nil
    end
    local recent = performance.RecentOperations(windowStart, windowEnd, windowEnd)
    if type(recent) ~= "table" then recent = {} end
    local relationship = not profileStart and "unmatched"
        or frameStart == profileStart and frameEnd == profileEnd and "exact" or "partial"
    local diagnosticOk, diagnostic, diagnosticSpans = pcall(DiagnosticOverlapUnsafe,performance,windowStart,windowEnd)
    if not diagnosticOk then diagnostic,diagnosticSpans=nil,{} end
    if #recent == 0 and #diagnosticSpans == 0 then return nil end

    local ranked = {}
    for index, operation in ipairs(recent) do
        if type(operation) == "table" and type(operation.name) == "string"
            and FiniteNumber(operation.durationMs) then
            ranked[#ranked + 1] = {operation=operation, order=index}
        end
    end
    table.sort(ranked, function(left, right)
        local a, b = left.operation, right.operation
        local aPriority, bPriority = PRIORITY[a.name] or 0, PRIORITY[b.name] or 0
        if aPriority ~= bPriority then return aPriority > bPriority end
        if a.endTime ~= b.endTime then return (a.endTime or 0) > (b.endTime or 0) end
        if a.startTime ~= b.startTime then return (a.startTime or 0) > (b.startTime or 0) end
        if a.name ~= b.name then return a.name < b.name end
        return left.order < right.order
    end)

    local operations = {}
    for index = 1, math.min(MAX_OPERATIONS, #ranked) do
        local operation = ranked[index].operation
        operations[index] = {
            name=operation.name,
            durationMs=operation.durationMs,
            fields=CopyProviderFields(operation.fields),
            startTime=operation.startTime, endTime=operation.endTime,
            geometry="derived session end minus elapsed; not exact invocation bounds",
        }
    end
    if #operations == 0 then
        for index, span in ipairs(diagnosticSpans) do
            operations[index] = {name=span.name,durationMs=span.elapsedMs,fields={},
                startTime=span.sessionStart,endTime=span.sessionEnd,
                geometry="observed session bounds",sequence=span.id,parent=span.parentId,
                depth=span.depth,heapBeforeKB=span.heapBeforeKB,heapAfterKB=span.heapAfterKB,
                heapDeltaKB=span.heapNetKB,heapAvailable=span.heapAvailable}
        end
    end
    local summary = operations[1].name == "automation.fallback.repair"
        and "A recent Nexus automation repair overlaps the attributed hitch."
        or "Recent bounded Nexus operations overlap the attributed hitch."
    if diagnostic then diagnostic.overlapStatus=#diagnosticSpans>0 and relationship or "unmatched" end
    return {summary=summary, operations=operations,windowRelationship=relationship,
        frameStartTime=frameStart,frameEndTime=frameEnd,
        profileStartTime=profileStart,profileEndTime=profileEnd,
        searchedWindowStart=windowStart,searchedWindowEnd=windowEnd,
        correlationMeaning="temporal overlap only; not same-window addon CPU or causation",
        diagnostics=diagnostic}
end

local function Collect(context)
    local ok, result = pcall(CollectUnsafe, context)
    -- StutterAlert's provider contract distinguishes a valid empty table from
    -- malformed non-table output. Internal failures remain isolated, but must
    -- still report the valid empty shape so the consumer records "empty".
    return ok and type(result) == "table" and result or {}
end

-- Optional timing summary, version 1. StutterAlert asks for it only while it
-- builds a report (a user action), never per frame or per hitch. It holds the
-- session aggregates of a fixed list of Performance paths: count, total and
-- maximum milliseconds. Every duration is inclusive. A row with `parent`
-- always runs inside that parent row, so the two must not be added; a row
-- without a parent can be called from several places. No samples, player or
-- character names, community builds or saved data; the only identity is the
-- Nexus version and build label. The counters are existing session totals.
local TIMING_SUMMARY_VERSION = 1
local TIMING_ROWS = {
    "lifecycle.update",
    "lifecycle.phase.rebind", "lifecycle.phase.store",
    "lifecycle.phase.community", "lifecycle.phase.maintenance",
    "lifecycle.phase.catalog", "lifecycle.phase.hashes",
    "lifecycle.phase.share", "lifecycle.phase.transport",
    "sync.update", "dps.update", "automation.update", "gameadapter.poll",
    "automation.step", "hud.prepare", "hud.phase.assignment",
    "hud.phase.projection", "hud.phase.view-model", "panel.render",
    "lifecycle.loading-status", "sync.incoming",
}

local function SessionCounters()
    local counters = {}
    local hud = type(Nexus.HudSnapshotStats) == "function" and Nexus.HudSnapshotStats() or nil
    if type(hud) == "table" then
        counters[#counters + 1] = {name="hud.view-model.builds", value=FiniteNumber(hud.builds) or 0}
        counters[#counters + 1] = {name="hud.view-model.reuses", value=FiniteNumber(hud.skipped) or 0}
        counters[#counters + 1] = {name="hud.view-model.copied-tables", value=FiniteNumber(hud.copiedTables) or 0}
    end
    local adapter = Nexus.GameAdapter
    local echo = adapter and type(adapter.EchoReconcileStats) == "function"
        and adapter.EchoReconcileStats() or nil
    local projections = type(echo) == "table" and type(echo.projections) == "table"
        and echo.projections or nil
    if projections then
        local slots, wishlist = projections.slots, projections.wishlist
        counters[#counters + 1] = {name="adapter.slot-projections",
            value=type(slots) == "table" and FiniteNumber(slots.calls) or 0}
        counters[#counters + 1] = {name="adapter.wishlist-reads",
            value=type(wishlist) == "table" and FiniteNumber(wishlist.calls) or 0}
    end
    return counters
end

local function TimingSummaryUnsafe()
    local performance = Nexus and Nexus.Performance
    if not (performance and type(performance.Stats) == "function"
        and type(performance.Snapshot) == "function") then return nil end
    local snapshot = performance.Snapshot()
    local window = type(performance.Window) == "function" and performance.Window() or {}
    local now = type(GetTime) == "function" and FiniteNumber(GetTime()) or nil
    local rows = {}
    for _, name in ipairs(TIMING_ROWS) do
        local stats = performance.Stats(name)
        if type(stats) == "table" then
            rows[#rows + 1] = {
                name=name,
                parent=type(performance.ParentOf) == "function" and performance.ParentOf(name) or nil,
                count=FiniteNumber(stats.count) or 0,
                totalMs=FiniteNumber(stats.total) or 0,
                maxMs=FiniteNumber(stats.maximum) or 0,
            }
        end
    end
    local label = type(Nexus.RuntimeBuildLabel) == "function" and Nexus.RuntimeBuildLabel() or nil
    return {
        timingSummaryVersion=TIMING_SUMMARY_VERSION,
        units="ms", nesting="inclusive", windowClock="GetTime",
        version=type(Nexus.Release) == "table" and Nexus.Release.version or nil,
        buildLabel=type(label) == "string" and label or nil,
        enabled=snapshot.enabled == true, clockAvailable=snapshot.clockAvailable == true,
        windowStart=FiniteNumber(window.startedAt), windowEnd=now,
        lastUpdate=FiniteNumber(window.lastLifecycleAt),
        rows=rows, counters=SessionCounters(),
    }
end

local function CollectTimingSummary()
    local ok, result = pcall(TimingSummaryUnsafe)
    return ok and type(result) == "table" and result or nil
end

-- User-requested report work only; never called from the hot path. These
-- snapshots are detached and bounded and do not read clocks or Lua heap.
local function CollectDiagnosticSnapshot()
    local ok, result = pcall(function()
        local performance = Nexus and Nexus.Performance
        if not (performance and type(performance.SnapshotDiagnostics)=="function") then return nil end
        return {version=1,diagnostics=performance.SnapshotDiagnostics(),
            assignmentDetail=type(performance.SnapshotAssignmentDetail)=="function"
                and performance.SnapshotAssignmentDetail() or nil}
    end)
    return ok and type(result)=="table" and result or nil
end

-- Registered table: StutterAlert calls Collect(self, context) for attributed
-- hitches (the v1 contract, unchanged) and, when it supports it,
-- CollectTimingSummary(self) while building a report.
local Provider = {
    TIMING_SUMMARY_VERSION = TIMING_SUMMARY_VERSION,
    Collect = function(_, context) return Collect(context) end,
    CollectTimingSummary = function() return CollectTimingSummary() end,
    CollectDiagnosticSnapshot = function() return CollectDiagnosticSnapshot() end,
}

function Integration.Unregister()
    local api = registeredApi
    registeredApi = nil
    if not (api and type(api.UnregisterDiagnosticProvider) == "function") then
        return false
    end
    local ok, removed = pcall(api.UnregisterDiagnosticProvider, ADDON_NAME)
    return ok and removed == true
end

function Integration.Register()
    local api = _G and _G.StutterAlert
    if type(api) ~= "table" or api.DIAGNOSTIC_PROVIDER_API ~= API_VERSION
        or type(api.RegisterDiagnosticProvider) ~= "function" then
        if registeredApi then Integration.Unregister() end
        return false, "unsupported or unavailable API"
    end
    if registeredApi == api then return true end
    if registeredApi then Integration.Unregister() end
    local ok, registered, reason = pcall(api.RegisterDiagnosticProvider,
        ADDON_NAME, Provider)
    if not ok or registered ~= true then
        return false, ok and reason or "registration failed"
    end
    registeredApi = api
    return true
end

function Integration.IsRegistered()
    return registeredApi ~= nil
end

Integration.Collect = Collect
Integration.CollectTimingSummary = CollectTimingSummary
Integration.CollectDiagnosticSnapshot = CollectDiagnosticSnapshot
Integration.Provider = Provider
