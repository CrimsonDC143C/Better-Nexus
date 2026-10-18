-- Bounded, session-only aggregate timings for known Nexus hot paths, plus a
-- separate default-OFF scalar span/heap diagnostic view below.
--
-- Ordinary timings are observational. They never enter SavedVariables or
-- influence gameplay. The default clock reports milliseconds; tests may
-- inject another millisecond clock. A failed/unavailable clock is tried once,
-- then the measured callback takes a constant cheap bypass until SetClock.

Nexus = Nexus or {}

local Performance = {}
Nexus.Performance = Performance

local PATH_ORDER = {
    "automation.step",
    "automation.fallback.check",
    "automation.fallback.repair",
    "automation.phase.static",
    "automation.phase.catalog",
    "automation.phase.wishlist",
    "automation.phase.wishlist-fingerprint",
    "automation.phase.plan",
    "automation.phase.slots",
    "automation.phase.owned",
    "automation.phase.levers",
    "automation.phase.board",
    "automation.phase.board-prepare",
    "automation.phase.policy",
    "automation.phase.autolock",
    "automation.phase.preauthorize",
    "automation.phase.overlay-prepare",
    "automation.phase.overlay-render",
    "decision.policy",
    -- Automatic local roll recorder (core/RollRecorder.lua), observation only.
    "rolltrace.decision",
    "rolltrace.intent",
    "rolltrace.after",
    "sync.update",
    "sync.incoming",
    "dps.update",
    "views.refresh",
    "hud.prepare",
    "community.show",
    "community.saved-import",
    "community.related-lookup",
    "community.frame.ensure",
    "community.projection",
    "community.render",
    "community.refresh",
    "leaderboard.refresh",
    "panel.render",
    "overlay.refresh",
    "lifecycle.update",
    "automation.update",
    "gameadapter.poll",
    -- Sub-steps of lifecycle.update (inclusive; each runs inside it).
    "lifecycle.phase.rebind",
    "lifecycle.phase.store",
    "lifecycle.phase.community",
    "lifecycle.phase.maintenance",
    "lifecycle.phase.catalog",
    "lifecycle.phase.hashes",
    "lifecycle.phase.share",
    "lifecycle.phase.transport",
    -- After lifecycle.update, in the same frame script (not inside it).
    "lifecycle.loading-status",
    -- Sub-steps of hud.prepare (inclusive; each runs inside it).
    "hud.phase.assignment",
    "hud.phase.projection",
    "hud.phase.view-model",
}
local PATHS = {}
for _, name in ipairs(PATH_ORDER) do PATHS[name] = true end
local AGGREGATE_ONLY = {}
-- Only automation.phase.* compete for the dominant phase of automation.step.
local STEP_PHASES = {}
for _, name in ipairs(PATH_ORDER) do
    if name:find("automation.phase.", 1, true) == 1 then STEP_PHASES[name] = true end
    if name:find("automation.phase.", 1, true) == 1
        or name:find("lifecycle.phase.", 1, true) == 1
        or name:find("hud.phase.", 1, true) == 1
        or name == "lifecycle.loading-status" then
        AGGREGATE_ONLY[name] = true
    end
end
-- The measured parent each direct sub-step runs inside. While a parent with a
-- tracker runs, its largest finished sub-step (inclusive time) is kept, and
-- the parent's recent-operation entry names it in its mode/outcome fields.
-- automation.step keeps its own tracker below (automation.phase.*).
local SUBSTEP_PARENT = {
    ["automation.update"] = "lifecycle.update",
    ["sync.update"] = "lifecycle.update",
    ["dps.update"] = "lifecycle.update",
    ["gameadapter.poll"] = "automation.update",
}
for _, name in ipairs(PATH_ORDER) do
    if name:find("lifecycle.phase.", 1, true) == 1 then
        SUBSTEP_PARENT[name] = "lifecycle.update"
    elseif name:find("hud.phase.", 1, true) == 1 then
        SUBSTEP_PARENT[name] = "hud.prepare"
    end
end
local trackers = {
    ["lifecycle.update"] = {active=false,name="none",ms=0,fields={mode="none",outcome=0}},
    ["hud.prepare"] = {active=false,name="none",ms=0,fields={mode="none",outcome=0}},
}

local enabled = true
local injectedClock = nil
local clockState = "unknown"
local clockFailures = 0
local assignmentDetailClockGeneration = 0
local diagnosticClockGeneration = 0
local diagnosticClockState = "unknown"
local aggregates = {}
local instrumented = setmetatable({}, {__mode="k"})
local operations = {}

local OPERATION_CAPACITY = 32
local OPERATION_MAX_AGE_SECONDS = 15
local OPERATION_MINIMUM_MS = 1
local SLOW_STEP_MINIMUM_MS = 16
local OPERATION_FIELD_ORDER = {"trigger", "mismatch", "mode", "outcome"}
local activeAutomationStep = false
local activeStepDominantName = "none"
local activeStepDominantMs = 0
local stepClassifications = {mode="none",outcome=0}
local lastSlowStep = {
    present=false,durationMs=0,dominantPhase="none",
    dominantPhaseMs=0,endTime=0,retainedScalarFields=5,
}

local function FiniteNumber(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge
        or number == -math.huge then return nil end
    return number
end

local function DefaultClock()
    if type(debugprofilestop) == "function" then
        return debugprofilestop()
    end
    if type(GetTime) == "function" then
        return GetTime() * 1000
    end
    return nil
end

local function ReadClock()
    if clockState == "unavailable" then return nil end
    local clock = injectedClock or DefaultClock
    local ok, value = pcall(clock)
    value = ok and FiniteNumber(value) or nil
    if not value then
        clockState = "unavailable"
        clockFailures = clockFailures + 1
        return nil
    end
    clockState = "available"
    return value
end

local function ReadSessionTime()
    if type(GetTime) ~= "function" then return nil end
    local ok, value = pcall(GetTime)
    return ok and FiniteNumber(value) or nil
end

-- Observation window of the aggregates, in session seconds (GetTime): from
-- module load or the last full Reset to the last completed lifecycle.update.
local windowStartedAt = ReadSessionTime()
local lastLifecycleAt = nil

local function ControlledScalar(value)
    local kind = type(value)
    if kind == "number" then return FiniteNumber(value) end
    if kind == "boolean" then return value end
    if kind ~= "string" then return nil end
    value = value:gsub("[%z\1-\31\127]", " "):gsub("|", "")
    if #value > 48 then value = value:sub(1, 48) end
    return value ~= "" and value or nil
end

local function CopyControlledFields(classifications)
    local fields = {}
    if type(classifications) ~= "table" then return fields end
    for _, key in ipairs(OPERATION_FIELD_ORDER) do
        local value = ControlledScalar(classifications[key])
        if value ~= nil then
            fields[#fields + 1] = {key=key, value=value}
        end
    end
    return fields
end

local function PruneOperations(now)
    local cutoff = now - OPERATION_MAX_AGE_SECONDS
    local writeAt = 1
    for readAt = 1, #operations do
        local operation = operations[readAt]
        if operation.endTime >= cutoff then
            operations[writeAt] = operation
            writeAt = writeAt + 1
        end
    end
    for index = writeAt, #operations do operations[index] = nil end
end

local function RecordOperation(name, elapsed, classifications)
    if elapsed < OPERATION_MINIMUM_MS then return false end
    local endedAt = ReadSessionTime()
    if not endedAt then return false end
    PruneOperations(endedAt)
    operations[#operations + 1] = {
        name=name,
        startTime=math.max(0, endedAt - (elapsed / 1000)),
        endTime=endedAt,
        durationMs=elapsed,
        fields=CopyControlledFields(classifications),
    }
    if #operations > OPERATION_CAPACITY then table.remove(operations, 1) end
    return true
end

local function CopyOperation(operation)
    local fields = {}
    for index, field in ipairs(operation.fields or {}) do
        fields[index] = {key=field.key, value=field.value}
    end
    return {
        name=operation.name,
        startTime=operation.startTime,
        endTime=operation.endTime,
        durationMs=operation.durationMs,
        fields=fields,
    }
end

local function CopyAggregate(name)
    local value = aggregates[name] or {}
    return {
        name=name,
        count=tonumber(value.count) or 0,
        total=tonumber(value.total) or 0,
        maximum=tonumber(value.maximum) or 0,
        last=tonumber(value.last) or 0,
    }
end

function Performance.SetEnabled(value)
    enabled = value ~= false
    return enabled
end

function Performance.IsEnabled()
    return enabled
end

function Performance.SetClock(clock)
    if clock ~= nil and type(clock) ~= "function" then
        return false, "clock must be a function or nil"
    end
    injectedClock = clock
    clockState = "unknown"
    assignmentDetailClockGeneration = assignmentDetailClockGeneration + 1
    diagnosticClockGeneration = diagnosticClockGeneration + 1
    diagnosticClockState = "unknown"
    return true
end

-- Assignment detail is a separate opt-in view. It does not register ordinary
-- performance paths or displace the existing hud.prepare breadcrumb. Only
-- fixed scalar aggregates are retained; interval geometry lives on this
-- bounded synchronous stack until the measured callback returns.
local ASSIGNMENT_DETAIL_NAMES = {
    "assignment.read", "assignment.slots", "assignment.discovery",
    "assignment.candidates", "assignment.state", "assignment.wishlist",
    "assignment.projection",
}
local ASSIGNMENT_BRANCH_NAMES = {
    "legacy", "table", "first_run", "unassigned", "loading", "discovery",
    "unclassified",
}
local ASSIGNMENT_COUNT_NAMES = {
    "slots_reads", "candidate_builds", "candidate_rows", "discovery_rows",
    "projection_rows",
}
local ASSIGNMENT_DETAIL_DEPTH = 16
local MAX_DETAIL_COUNTER = 9007199254740991
local detailNames, detailBranches, detailCounts = {}, {}, {}
for _, name in ipairs(ASSIGNMENT_DETAIL_NAMES) do detailNames[name] = true end
for _, name in ipairs(ASSIGNMENT_BRANCH_NAMES) do detailBranches[name] = true end
for _, name in ipairs(ASSIGNMENT_COUNT_NAMES) do detailCounts[name] = true end
local detailEnabled = false
local detailRows, detailBranchRows, detailWork, detailEdges = {}, {}, {}, {}
local detailStack, detailDepth = {}, 0
local detailSuspended, detailSuspensionReason = false, nil
local detailWindowStart, detailWindowEnd = nil, nil
local detailWindowClockGeneration, detailWindowAvailable = nil, true
local detailUnavailableReads, detailDepthBypasses, detailRejectedLabels = 0, 0, 0

local function DetailIncrement(value, increment)
    return math.min(MAX_DETAIL_COUNTER, (value or 0) + (increment or 1))
end

local function NewDetailAggregate()
    return {invocations=0, count=0, totalMs=0, totalAvailable=true,
        maximumMs=0, lastMs=0, exclusiveCount=0, exclusiveTotalMs=0,
        exclusiveTotalAvailable=true, exclusiveMaximumMs=0, exclusiveLastMs=0,
        failed=0, unavailable=0}
end

local function DetailAggregate(target, name)
    local value = target[name]
    if not value then value = NewDetailAggregate(); target[name] = value end
    return value
end

local function DetailAddElapsed(value, elapsed, exclusive)
    value.count = DetailIncrement(value.count)
    if value.totalAvailable then
        value.totalMs = FiniteNumber(value.totalMs + elapsed)
        value.totalAvailable = value.totalMs ~= nil
    end
    value.maximumMs, value.lastMs = math.max(value.maximumMs, elapsed), elapsed
    if exclusive ~= nil then
        value.exclusiveCount = DetailIncrement(value.exclusiveCount)
        if value.exclusiveTotalAvailable then
            value.exclusiveTotalMs = FiniteNumber(value.exclusiveTotalMs + exclusive)
            value.exclusiveTotalAvailable = value.exclusiveTotalMs ~= nil
        end
        value.exclusiveMaximumMs = math.max(value.exclusiveMaximumMs, exclusive)
        value.exclusiveLastMs = exclusive
    end
end

local function DetailCopyAggregate(name, value)
    value = value or NewDetailAggregate()
    return {name=name, invocations=value.invocations, count=value.count,
        available=value.count > 0, exclusiveAvailable=value.exclusiveCount > 0,
        totalMs=value.totalMs, totalAvailable=value.totalAvailable,
        maximumMs=value.maximumMs, lastMs=value.lastMs,
        exclusiveCount=value.exclusiveCount, exclusiveTotalMs=value.exclusiveTotalMs,
        exclusiveTotalAvailable=value.exclusiveTotalAvailable,
        exclusiveMaximumMs=value.exclusiveMaximumMs,
        exclusiveLastMs=value.exclusiveLastMs, failed=value.failed,
        unavailable=value.unavailable}
end

function Performance.SetAssignmentDetailEnabled(value)
    if detailDepth > 0 then return false, "assignment detail is active" end
    detailEnabled = value == true
    return true
end

function Performance.DetailAssignmentEnabled()
    return detailEnabled and enabled and clockState ~= "unavailable"
end

function Performance.ResetAssignmentDetail()
    if detailDepth > 0 then return false, "assignment detail is active" end
    detailRows, detailBranchRows, detailWork, detailEdges = {}, {}, {}, {}
    detailWindowStart, detailWindowEnd = nil, nil
    detailWindowClockGeneration, detailWindowAvailable = nil, true
    detailUnavailableReads, detailDepthBypasses, detailRejectedLabels = 0, 0, 0
    -- Like ordinary Reset, this does not revive an unavailable clock.
    return true
end

function Performance.NoteAssignmentBranch(name)
    if detailSuspended then return false end
    local frame = detailStack[detailDepth]
    local root = frame and frame.root
    if not root or not detailBranches[name] then return false end
    if root.branch ~= nil and root.branch ~= name then return false end
    root.branch = name
    return true
end

function Performance.NoteAssignmentCount(name, increment)
    if detailSuspended then return false end
    local frame = detailStack[detailDepth]
    if not frame or not frame.root or not detailCounts[name] then return false end
    increment = increment == nil and 1 or FiniteNumber(increment)
    if not increment or increment < 0 or increment ~= math.floor(increment) then return false end
    frame.root.work[name] = DetailIncrement(frame.root.work[name], increment)
    detailWork[name] = DetailIncrement(detailWork[name], increment)
    return true
end

local function DetailPack(...)
    return {n=select("#", ...), ...}
end

-- A bypassed recursive root must not inherit its caller's branch or counters.
-- This enabled-only protection also restores context if that callback errors.
local function DetailSuspendedCall(reason, callback, ...)
    detailSuspended, detailSuspensionReason = true, reason
    local values = DetailPack(pcall(callback, ...))
    detailSuspended, detailSuspensionReason = false, nil
    if not values[1] then error(values[2], 0) end
    return unpack(values, 2, values.n)
end

local function DetailFinish(frame, succeeded)
    local finishedAt = succeeded and ReadClock() or nil
    detailStack[detailDepth], detailDepth = nil, detailDepth - 1
    local parent = detailStack[detailDepth]
    local aggregate = DetailAggregate(detailRows, frame.name)
    aggregate.invocations = DetailIncrement(aggregate.invocations)
    local branch
    if frame.name == "assignment.read" then
        branch = DetailAggregate(detailBranchRows, frame.branch or "unclassified")
        branch.invocations = DetailIncrement(branch.invocations)
        branch.work = branch.work or {}
        for _, name in ipairs(ASSIGNMENT_COUNT_NAMES) do
            branch.work[name] = DetailIncrement(branch.work[name], frame.work[name] or 0)
        end
        local workField = succeeded and not frame.workIncomplete
            and "workCompleteInvocations" or "workPartialInvocations"
        branch[workField] = DetailIncrement(branch[workField])
    end
    if not succeeded then frame.root.workIncomplete = true end
    local elapsed = finishedAt and FiniteNumber(finishedAt - frame.startedAt)
    local valid = succeeded and elapsed ~= nil and elapsed >= 0
        and frame.clockGeneration == assignmentDetailClockGeneration
    local exclusive
    if valid and frame.coverageValid and frame.childMs <= elapsed
        and (not frame.lastChildEnd or frame.lastChildEnd <= finishedAt) then
        exclusive = elapsed - frame.childMs
    end
    if valid then
        DetailAddElapsed(aggregate, elapsed, exclusive)
        if branch then DetailAddElapsed(branch, elapsed, exclusive) end
        if frame.name == "assignment.read" then
            if detailWindowClockGeneration == nil then
                detailWindowClockGeneration = frame.clockGeneration
            elseif detailWindowClockGeneration ~= frame.clockGeneration then
                detailWindowAvailable = false
                detailWindowStart, detailWindowEnd = nil, nil
            end
            if detailWindowAvailable then
                detailWindowStart = detailWindowStart and math.min(detailWindowStart, frame.startedAt)
                    or frame.startedAt
                detailWindowEnd = detailWindowEnd and math.max(detailWindowEnd, finishedAt) or finishedAt
            end
        end
    else
        local field = succeeded and "unavailable" or "failed"
        aggregate[field] = DetailIncrement(aggregate[field])
        if branch then branch[field] = DetailIncrement(branch[field]) end
    end
    if parent then
        -- Subtract only the completed direct child's exact interval. A child's
        -- own missing grandchildren do not invalidate its inclusive coverage.
        if valid and frame.startedAt >= parent.startedAt
            and (not parent.lastChildEnd or frame.startedAt >= parent.lastChildEnd) then
            local sum = FiniteNumber(parent.childMs + elapsed)
            if sum then parent.childMs = sum else parent.coverageValid = false end
            parent.lastChildEnd = finishedAt
            local edges = detailEdges[parent.name]
            if not edges then edges = {}; detailEdges[parent.name] = edges end
            edges[frame.name] = DetailIncrement(edges[frame.name])
        else
            parent.coverageValid = false
        end
    end
end

function Performance.MeasureAssignmentDetail(name, callback, ...)
    if type(callback) ~= "function" then error("callback must be a function", 2) end
    -- The ordinary production path allocates no detail context and reads no
    -- detail clock. Children cannot acquire an assignment context on their own.
    if not detailEnabled or not enabled then return callback(...) end
    if not detailNames[name] then
        detailRejectedLabels = DetailIncrement(detailRejectedLabels)
        return callback(...)
    end
    if detailSuspended then
        if detailSuspensionReason == "depth" then
            detailDepthBypasses = DetailIncrement(detailDepthBypasses)
        elseif name == "assignment.read" then
            detailUnavailableReads = DetailIncrement(detailUnavailableReads)
        end
        return callback(...)
    end
    if name ~= "assignment.read" and detailDepth == 0 then return callback(...) end
    if detailDepth >= ASSIGNMENT_DETAIL_DEPTH then
        detailDepthBypasses = DetailIncrement(detailDepthBypasses)
        detailStack[detailDepth].coverageValid = false
        detailStack[detailDepth].root.workIncomplete = true
        return DetailSuspendedCall("depth", callback, ...)
    end
    local startedAt = ReadClock()
    if not startedAt then
        if name == "assignment.read" then
            detailUnavailableReads = DetailIncrement(detailUnavailableReads)
        end
        if detailDepth > 0 then
            detailStack[detailDepth].coverageValid = false
            detailStack[detailDepth].root.workIncomplete = true
            return DetailSuspendedCall("clock", callback, ...)
        end
        return callback(...)
    end
    local frame = {name=name, startedAt=startedAt, childMs=0, coverageValid=true,
        clockGeneration=assignmentDetailClockGeneration}
    local parent = detailStack[detailDepth]
    frame.root = name == "assignment.read" and frame or parent.root
    if name == "assignment.read" then frame.work = {} end
    detailDepth = detailDepth + 1
    detailStack[detailDepth] = frame
    local values = DetailPack(pcall(callback, ...))
    DetailFinish(frame, values[1])
    if not values[1] then error(values[2], 0) end
    return unpack(values, 2, values.n)
end

function Performance.SnapshotAssignmentDetail()
    local rows, branches, counts, edges = {}, {}, {}, {}
    for index, name in ipairs(ASSIGNMENT_DETAIL_NAMES) do
        rows[index] = DetailCopyAggregate(name, detailRows[name])
    end
    for index, name in ipairs(ASSIGNMENT_BRANCH_NAMES) do
        local retained = detailBranchRows[name]
        local branch = DetailCopyAggregate(name, retained)
        branch.work, branch.workCompleteInvocations, branch.workPartialInvocations = {},
            retained and retained.workCompleteInvocations or 0,
            retained and retained.workPartialInvocations or 0
        branch.workUntimedInvocations = branch.invocations - branch.count
        for countIndex, countName in ipairs(ASSIGNMENT_COUNT_NAMES) do
            branch.work[countIndex] = {name=countName,
                value=retained and retained.work and retained.work[countName] or 0}
        end
        branches[index] = branch
    end
    for index, name in ipairs(ASSIGNMENT_COUNT_NAMES) do
        counts[index] = {name=name, value=detailWork[name] or 0}
    end
    -- Fixed 7x7 shape, actual observed parent edges; no assumed hierarchy.
    for _, parent in ipairs(ASSIGNMENT_DETAIL_NAMES) do
        for _, child in ipairs(ASSIGNMENT_DETAIL_NAMES) do
            edges[#edges + 1] = {parent=parent, child=child,
                count=detailEdges[parent] and detailEdges[parent][child] or 0}
        end
    end
    return {version=1, enabled=detailEnabled, ordinaryEnabled=enabled,
        clockState=clockState, clockFailures=clockFailures, units="ms",
        clock="Performance millisecond clock", nesting="same-invocation direct children",
        exclusiveMeaning="elapsed residual after valid direct-child coverage; not addon CPU",
        windowAvailable=detailWindowAvailable and detailWindowStart ~= nil,
        windowStartMs=detailWindowStart, windowEndMs=detailWindowEnd,
        activeDepth=detailDepth, maximumDepth=ASSIGNMENT_DETAIL_DEPTH,
        observedReadInvocations=detailRows["assignment.read"]
            and detailRows["assignment.read"].invocations or 0,
        unavailableReads=detailUnavailableReads, depthBypasses=detailDepthBypasses,
        rejectedLabels=detailRejectedLabels, rows=rows, branches=branches,
        counts=counts, edges=edges}
end

-- A separate opt-in diagnostic view. Fixed rows, reusable stack/ring slots and
-- scalar observations only: no player data, gameplay decisions or durable
-- writes. Heap samples are the GLOBAL Lua heap, not per-addon allocations.
local DIAGNOSTIC_NAMES = {
    "orb.status", "orb.read", "orb.panel", "echo.reconcile", "hud.prepare",
    "lifecycle.update", "sync.update", "gameadapter.poll", "dps.update",
    "lifecycle.phase.catalog",
}
local DIAGNOSTIC_CAPACITY, DIAGNOSTIC_DEPTH = 32, 16
local diagnosticNames, diagnosticRows, diagnosticStack, diagnosticSpans = {}, {}, {}, {}
local diagnosticEnabled, diagnosticDepth = false, 0
local diagnosticRingNext, diagnosticRingCount, diagnosticSequence = 1, 0, 0
local diagnosticResetGeneration, diagnosticSessionGeneration = 0, 0
local diagnosticSessionState, diagnosticMemoryState = "unknown", "unknown"
local diagnosticClockFailures, diagnosticSessionFailures, diagnosticMemoryFailures = 0, 0, 0
local diagnosticDepthBypasses, diagnosticIdBypasses, diagnosticRejectedLabels = 0, 0, 0
local diagnosticMemoryReader, diagnosticSessionClock = nil, nil
local diagnosticSuspended = false
local function DiagnosticRow()
    return {invocations=0,count=0,failed=0,unavailable=0,totalMs=0,totalAvailable=true,
        maximumMs=0,lastMs=nil,residualCount=0,residualTotalMs=0,
        residualTotalAvailable=true,residualMaximumMs=0,lastResidualMs=nil,
        heapCount=0,heapNetKB=0,heapNetAvailable=true}
end
for _, name in ipairs(DIAGNOSTIC_NAMES) do
    diagnosticNames[name], diagnosticRows[name] = true, DiagnosticRow()
end
for index=1, DIAGNOSTIC_DEPTH do diagnosticStack[index] = {} end
for index=1, DIAGNOSTIC_CAPACITY do diagnosticSpans[index] = {} end

-- Reader code is observer work, even when an injected/host reader re-enters
-- an instrumented API. Suppress only diagnostic entry during that call and
-- restore the previous suspension state on both success and failure. Readers
-- use only their first scalar result; no result-packing allocation is needed.
local function DiagnosticObserve(reader, ...)
    local previous = diagnosticSuspended
    diagnosticSuspended = true
    local ok, value = pcall(reader, ...)
    diagnosticSuspended = previous
    return ok, value
end
local function DiagnosticReadClock()
    if diagnosticClockState == "unavailable" then return nil end
    local ok, value = DiagnosticObserve(injectedClock or DefaultClock)
    value = ok and FiniteNumber(value) or nil
    if value == nil then
        diagnosticClockState = "unavailable"
        diagnosticClockFailures = DetailIncrement(diagnosticClockFailures)
        return nil
    end
    diagnosticClockState = "available"
    return value
end
local function DiagnosticReadSession()
    if diagnosticSessionState == "unavailable" then return nil end
    local reader = diagnosticSessionClock or GetTime
    local ok, value = false, nil
    if type(reader) == "function" then ok, value = DiagnosticObserve(reader) end
    value = ok and FiniteNumber(value) or nil
    if value == nil then
        diagnosticSessionState = "unavailable"
        diagnosticSessionFailures = DetailIncrement(diagnosticSessionFailures)
        return nil
    end
    diagnosticSessionState = "available"
    return value
end
local function DiagnosticReadMemory()
    if diagnosticMemoryState == "unavailable" then return nil end
    local ok, value
    if diagnosticMemoryReader then
        ok, value = DiagnosticObserve(diagnosticMemoryReader)
    elseif type(collectgarbage) == "function" then
        -- count is observational; never collect, stop or configure the GC.
        ok, value = DiagnosticObserve(collectgarbage, "count")
    end
    value = ok and FiniteNumber(value) or nil
    if value == nil or value < 0 then
        diagnosticMemoryState = "unavailable"
        diagnosticMemoryFailures = DetailIncrement(diagnosticMemoryFailures)
        return nil
    end
    diagnosticMemoryState = "available"
    return value
end
local function DiagnosticAdd(row, field, available, value)
    if not row[available] then return end
    local sum = FiniteNumber(row[field] + value)
    row[field], row[available] = sum, sum ~= nil
end
function Performance.SetDiagnosticEnabled(value)
    if diagnosticDepth > 0 then return false, "diagnostic span is active" end
    diagnosticEnabled = value == true
    return true
end
function Performance.DiagnosticEnabled() return diagnosticEnabled end
function Performance.SetDiagnosticMemoryReader(reader)
    if diagnosticDepth > 0 then return false, "diagnostic span is active" end
    if reader ~= nil and type(reader) ~= "function" then return false, "reader must be a function or nil" end
    diagnosticMemoryReader, diagnosticMemoryState = reader, "unknown"
    return true
end
function Performance.SetDiagnosticSessionClock(clock)
    if diagnosticDepth > 0 then return false, "diagnostic span is active" end
    if clock ~= nil and type(clock) ~= "function" then return false, "clock must be a function or nil" end
    if diagnosticSessionGeneration >= MAX_DETAIL_COUNTER then return false, "session clock generation exhausted" end
    diagnosticSessionClock, diagnosticSessionState = clock, "unknown"
    diagnosticSessionGeneration = DetailIncrement(diagnosticSessionGeneration)
    return true
end
function Performance.ResetDiagnostics()
    if diagnosticDepth > 0 then return false, "diagnostic span is active" end
    if diagnosticResetGeneration >= MAX_DETAIL_COUNTER then return false, "diagnostic generation exhausted" end
    for _, name in ipairs(DIAGNOSTIC_NAMES) do diagnosticRows[name] = DiagnosticRow() end
    diagnosticRingNext, diagnosticRingCount, diagnosticSequence = 1, 0, 0
    diagnosticResetGeneration = DetailIncrement(diagnosticResetGeneration)
    diagnosticDepthBypasses, diagnosticIdBypasses, diagnosticRejectedLabels = 0, 0, 0
    -- Does not retry a failed reader. SetClock/SetDiagnostic* restore readers.
    return true
end
local DIAGNOSTIC_SPAN_FIELDS = {
    "id", "parentId", "name", "depth", "resetGeneration", "clockGeneration",
    "startedMs", "endedMs", "elapsedAvailable", "elapsedMs", "childElapsedMs",
    "childCoverageAvailable", "residualAvailable", "residualMs", "sessionStart",
    "sessionEnd", "sessionWindowAvailable", "sessionWindowReason",
    "sessionClockGeneration", "heapBeforeKB", "heapAfterKB", "heapNetKB",
    "heapAvailable", "succeeded",
}
local function DiagnosticFinish(frame, succeeded)
    local endedMs, sessionEnd, heapAfter = DiagnosticReadClock(), DiagnosticReadSession(), DiagnosticReadMemory()
    local elapsed = frame.startedMs and endedMs and FiniteNumber(endedMs - frame.startedMs)
    local valid = succeeded and elapsed ~= nil and elapsed >= 0
        and frame.clockGeneration == diagnosticClockGeneration
    local residual = valid and frame.coverageValid and frame.childMs <= elapsed
        and (not frame.lastChildEnd or frame.lastChildEnd <= endedMs)
        and FiniteNumber(elapsed - frame.childMs) or nil
    local sessionAvailable = succeeded and frame.sessionStart ~= nil and sessionEnd ~= nil
        and sessionEnd > frame.sessionStart
        and frame.sessionGeneration == diagnosticSessionGeneration
    local sessionReason = sessionAvailable and "available" or not succeeded and "failed"
        or (frame.sessionStart ~= nil and sessionEnd == frame.sessionStart
            and frame.sessionGeneration == diagnosticSessionGeneration and "frozen_or_zero_window")
        or "unavailable_or_changed"
    local heapNet = succeeded and frame.heapBefore ~= nil and heapAfter ~= nil
        and FiniteNumber(heapAfter - frame.heapBefore) or nil
    local row = diagnosticRows[frame.name]
    row.invocations = DetailIncrement(row.invocations)
    if valid then
        row.count = DetailIncrement(row.count)
        DiagnosticAdd(row, "totalMs", "totalAvailable", elapsed)
        row.maximumMs, row.lastMs = math.max(row.maximumMs, elapsed), elapsed
        if residual ~= nil then
            row.residualCount = DetailIncrement(row.residualCount)
            DiagnosticAdd(row, "residualTotalMs", "residualTotalAvailable", residual)
            row.residualMaximumMs, row.lastResidualMs = math.max(row.residualMaximumMs, residual), residual
        end
    else
        local field = succeeded and "unavailable" or "failed"
        row[field] = DetailIncrement(row[field])
    end
    if heapNet ~= nil then
        row.heapCount = DetailIncrement(row.heapCount)
        DiagnosticAdd(row, "heapNetKB", "heapNetAvailable", heapNet)
    end
    local span = diagnosticSpans[diagnosticRingNext]
    span.id, span.parentId, span.name, span.depth = frame.id, frame.parentId, frame.name, diagnosticDepth
    span.resetGeneration, span.clockGeneration = diagnosticResetGeneration, frame.clockGeneration
    span.startedMs, span.endedMs, span.elapsedAvailable, span.elapsedMs = frame.startedMs, endedMs, valid, valid and elapsed or nil
    span.childElapsedMs, span.childCoverageAvailable = frame.childMs, frame.coverageValid
    span.residualAvailable, span.residualMs = residual ~= nil, residual
    span.sessionStart, span.sessionEnd = frame.sessionStart, sessionEnd
    span.sessionWindowAvailable, span.sessionWindowReason = sessionAvailable, sessionReason
    span.sessionClockGeneration = frame.sessionGeneration
    span.heapBeforeKB, span.heapAfterKB, span.heapNetKB = frame.heapBefore, heapAfter, heapNet
    span.heapAvailable, span.succeeded = heapNet ~= nil, succeeded
    diagnosticRingNext = diagnosticRingNext % DIAGNOSTIC_CAPACITY + 1
    diagnosticRingCount = math.min(DIAGNOSTIC_CAPACITY, diagnosticRingCount + 1)
    diagnosticDepth = diagnosticDepth - 1
    local parent = diagnosticDepth > 0 and diagnosticStack[diagnosticDepth] or nil
    if parent then
        if valid and parent.startedMs ~= nil and frame.startedMs >= parent.startedMs
            and parent.clockGeneration == frame.clockGeneration
            and (not parent.lastChildEnd or frame.startedMs >= parent.lastChildEnd) then
            local sum = FiniteNumber(parent.childMs + elapsed)
            if sum ~= nil then parent.childMs = sum else parent.coverageValid = false end
            parent.lastChildEnd = endedMs
        else parent.coverageValid = false end
    end
end
function Performance.MeasureDiagnostic(name, callback, ...)
    if type(callback) ~= "function" then error("callback must be a function", 2) end
    if not diagnosticEnabled or diagnosticSuspended then return callback(...) end
    if not diagnosticNames[name] then
        diagnosticRejectedLabels = DetailIncrement(diagnosticRejectedLabels)
        return callback(...)
    end
    if diagnosticDepth >= DIAGNOSTIC_DEPTH or diagnosticSequence >= MAX_DETAIL_COUNTER then
        local field = diagnosticDepth >= DIAGNOSTIC_DEPTH and "depth" or "id"
        if field == "depth" then diagnosticDepthBypasses = DetailIncrement(diagnosticDepthBypasses)
        else diagnosticIdBypasses = DetailIncrement(diagnosticIdBypasses) end
        if diagnosticDepth > 0 then diagnosticStack[diagnosticDepth].coverageValid = false end
        diagnosticSuspended = true
        local values = DetailPack(pcall(callback, ...))
        diagnosticSuspended = false
        if not values[1] then error(values[2], 0) end
        return unpack(values, 2, values.n)
    end
    local parent = diagnosticDepth > 0 and diagnosticStack[diagnosticDepth] or nil
    diagnosticDepth, diagnosticSequence = diagnosticDepth + 1, diagnosticSequence + 1
    local frame = diagnosticStack[diagnosticDepth]
    frame.id, frame.parentId, frame.name = diagnosticSequence, parent and parent.id or nil, name
    frame.childMs, frame.coverageValid, frame.lastChildEnd = 0, true, nil
    frame.clockGeneration, frame.sessionGeneration = diagnosticClockGeneration, diagnosticSessionGeneration
    frame.sessionStart, frame.startedMs, frame.heapBefore = DiagnosticReadSession(), DiagnosticReadClock(), DiagnosticReadMemory()
    local values = DetailPack(pcall(callback, ...))
    DiagnosticFinish(frame, values[1])
    if not values[1] then error(values[2], 0) end
    return unpack(values, 2, values.n)
end
function Performance.SnapshotDiagnostics()
    local rows, spans = {}, {}
    for index, name in ipairs(DIAGNOSTIC_NAMES) do
        local row, copy = diagnosticRows[name], {name=name}
        for key, value in pairs(row) do copy[key] = value end
        copy.available, copy.residualAvailable, copy.heapAvailable = row.count > 0, row.residualCount > 0, row.heapCount > 0
        rows[index] = copy
    end
    local oldest = (diagnosticRingNext - diagnosticRingCount - 1) % DIAGNOSTIC_CAPACITY + 1
    for offset=0, diagnosticRingCount-1 do
        local retained, copy = diagnosticSpans[(oldest + offset - 1) % DIAGNOSTIC_CAPACITY + 1], {}
        for _, key in ipairs(DIAGNOSTIC_SPAN_FIELDS) do copy[key] = retained[key] end
        spans[#spans + 1] = copy
    end
    return {version=1,enabled=diagnosticEnabled,activeDepth=diagnosticDepth,
        maximumDepth=DIAGNOSTIC_DEPTH,capacity=DIAGNOSTIC_CAPACITY,
        clockState=diagnosticClockState,clockFailures=diagnosticClockFailures,
        clockGeneration=diagnosticClockGeneration,
        sessionClockState=diagnosticSessionState,sessionClockFailures=diagnosticSessionFailures,
        sessionClockGeneration=diagnosticSessionGeneration,
        memoryState=diagnosticMemoryState,memoryFailures=diagnosticMemoryFailures,
        resetGeneration=diagnosticResetGeneration,lastSpanId=diagnosticSequence,
        depthBypasses=diagnosticDepthBypasses,idBypasses=diagnosticIdBypasses,
        rejectedLabels=diagnosticRejectedLabels,units="ms",heapUnits="KB",
        elapsedClock=injectedClock and "injected millisecond clock"
            or type(debugprofilestop)=="function" and "debugprofilestop" or "GetTime milliseconds",
        sessionClock=diagnosticSessionClock and "injected session clock" or "GetTime",
        heapMetric=diagnosticMemoryReader and "injected global Lua heap reader"
            or "collectgarbage count; global Lua heap",
        heapIncludesInstrumentation=true,
        heapMeaning="global net Lua heap change; not allocated bytes or GC time",
        residualMeaning="elapsed residual after valid direct-child coverage; not addon CPU",
        rows=rows,spans=spans}
end

function Performance.Begin(name)
    if not enabled or not PATHS[name] or clockState == "unavailable" then
        return nil
    end
    return ReadClock()
end

function Performance.Finish(name, startedAt, classifications)
    if not enabled or not PATHS[name] then return false end
    startedAt = FiniteNumber(startedAt)
    if not startedAt then return false end
    local finishedAt = ReadClock()
    if not finishedAt then return false end
    local elapsed = finishedAt - startedAt
    if elapsed < 0 then return false end
    if activeAutomationStep and STEP_PHASES[name]
        and elapsed > activeStepDominantMs then
        activeStepDominantName = name
        activeStepDominantMs = elapsed
    end
    if name == "automation.step" and activeAutomationStep then
        stepClassifications.mode = activeStepDominantName
        stepClassifications.outcome = activeStepDominantMs
        classifications = stepClassifications
        if elapsed >= SLOW_STEP_MINIMUM_MS then
            lastSlowStep.present = true
            lastSlowStep.durationMs = elapsed
            lastSlowStep.dominantPhase = activeStepDominantName
            lastSlowStep.dominantPhaseMs = activeStepDominantMs
            lastSlowStep.endTime = ReadSessionTime() or 0
        end
    end
    local parent = trackers[SUBSTEP_PARENT[name]]
    if parent and parent.active and elapsed > parent.ms then
        parent.name, parent.ms = name, elapsed
    end
    local own = trackers[name]
    if own and own.active then
        own.fields.mode, own.fields.outcome = own.name, own.ms
        classifications = own.fields
    end
    if name == "lifecycle.update" then lastLifecycleAt = ReadSessionTime() end
    local aggregate = aggregates[name]
    if not aggregate then
        aggregate = {count=0, total=0, maximum=0, last=0}
        aggregates[name] = aggregate
    end
    aggregate.count = aggregate.count + 1
    aggregate.total = aggregate.total + elapsed
    aggregate.maximum = math.max(aggregate.maximum, elapsed)
    aggregate.last = elapsed
    -- Fine-grained automation phases are exported as bounded aggregates but
    -- never enter the 32-entry recent-operation ring. A single outer Step must
    -- remain the useful StutterAlert correlation breadcrumb instead of being
    -- displaced by its own internal children.
    if elapsed >= OPERATION_MINIMUM_MS and not AGGREGATE_ONLY[name] then
        pcall(RecordOperation, name, elapsed, classifications)
    end
    return true
end

local function Complete(name, startedAt, ...)
    Performance.Finish(name, startedAt)
    if name == "automation.step" then activeAutomationStep = false end
    local tracker = trackers[name]
    if tracker then tracker.active = false end
    return ...
end

function Performance.Measure(name, callback, ...)
    if type(callback) ~= "function" then error("callback must be a function", 2) end
    if not enabled or not PATHS[name] or clockState == "unavailable" then
        if diagnosticEnabled and diagnosticNames[name] then
            return Performance.MeasureDiagnostic(name, callback, ...)
        end
        return callback(...)
    end
    local startedAt = ReadClock()
    if not startedAt then
        if diagnosticEnabled and diagnosticNames[name] then
            return Performance.MeasureDiagnostic(name, callback, ...)
        end
        return callback(...)
    end
    if name == "automation.step" then
        activeAutomationStep = true
        activeStepDominantName = "none"
        activeStepDominantMs = 0
    end
    local tracker = trackers[name]
    if tracker then tracker.active, tracker.name, tracker.ms = true, "none", 0 end
    -- Callback errors intentionally propagate unchanged. In that case there is
    -- no completed sample to aggregate, and no result-packing allocation.
    if diagnosticEnabled and diagnosticNames[name] then
        return Complete(name, startedAt, Performance.MeasureDiagnostic(name, callback, ...))
    end
    return Complete(name, startedAt, callback(...))
end

function Performance.Stats(name)
    if not PATHS[name] then return nil end
    return CopyAggregate(name)
end

function Performance.Snapshot()
    local rows = {}
    for index, name in ipairs(PATH_ORDER) do rows[index] = CopyAggregate(name) end
    return {
        enabled=enabled,
        clockAvailable=clockState ~= "unavailable",
        clockFailures=clockFailures,
        units="ms",
        rows=rows,
    }
end

function Performance.Reset(name)
    if name ~= nil then
        if not PATHS[name] then return false end
        aggregates[name] = nil
        local writeAt = 1
        for readAt = 1, #operations do
            local operation = operations[readAt]
            if operation.name ~= name then
                operations[writeAt] = operation
                writeAt = writeAt + 1
            end
        end
        for index = writeAt, #operations do operations[index] = nil end
        if name == "automation.step" then
            activeAutomationStep = false
            activeStepDominantName = "none"
            activeStepDominantMs = 0
            lastSlowStep.present = false
            lastSlowStep.durationMs = 0
            lastSlowStep.dominantPhase = "none"
            lastSlowStep.dominantPhaseMs = 0
            lastSlowStep.endTime = 0
        end
        return true
    end
    aggregates = {}
    operations = {}
    clockFailures = 0
    windowStartedAt, lastLifecycleAt = ReadSessionTime(), nil
    for _, tracker in pairs(trackers) do
        tracker.active, tracker.name, tracker.ms = false, "none", 0
    end
    activeAutomationStep = false
    activeStepDominantName = "none"
    activeStepDominantMs = 0
    lastSlowStep.present = false
    lastSlowStep.durationMs = 0
    lastSlowStep.dominantPhase = "none"
    lastSlowStep.dominantPhaseMs = 0
    lastSlowStep.endTime = 0
    return true
end

function Performance.CancelAutomationStep()
    activeAutomationStep = false
    activeStepDominantName = "none"
    activeStepDominantMs = 0
    return true
end

function Performance.LastSlowStep()
    return {
        present=lastSlowStep.present,durationMs=lastSlowStep.durationMs,
        dominantPhase=lastSlowStep.dominantPhase,
        dominantPhaseMs=lastSlowStep.dominantPhaseMs,
        endTime=lastSlowStep.endTime,
        retainedScalarFields=lastSlowStep.retainedScalarFields,
    }
end

function Performance.RecentOperations(windowStart, windowEnd, now)
    windowStart = FiniteNumber(windowStart)
    windowEnd = FiniteNumber(windowEnd)
    if not windowStart or not windowEnd or windowEnd < windowStart then return {} end
    now = FiniteNumber(now) or ReadSessionTime() or windowEnd
    PruneOperations(now)
    local recent = {}
    for index = #operations, 1, -1 do
        local operation = operations[index]
        if operation.endTime >= windowStart and operation.startTime <= windowEnd then
            recent[#recent + 1] = CopyOperation(operation)
        end
    end
    return recent
end

function Performance.OperationLimits()
    return {
        capacity=OPERATION_CAPACITY,
        maxAgeSeconds=OPERATION_MAX_AGE_SECONDS,
        minimumDurationMs=OPERATION_MINIMUM_MS,
        slowStepMinimumMs=SLOW_STEP_MINIMUM_MS,
        maxFields=#OPERATION_FIELD_ORDER,
    }
end

function Performance.Definitions()
    local names = {}
    for index, name in ipairs(PATH_ORDER) do names[index] = name end
    return names
end

-- Session seconds (GetTime) of the aggregates' observation window: from module
-- load or the last full Reset to the last completed lifecycle.update (nil
-- until one completes).
function Performance.Window()
    return {startedAt=windowStartedAt, lastLifecycleAt=lastLifecycleAt}
end

-- The measured parent a sub-step path always runs inside, or nil.
function Performance.ParentOf(name)
    return SUBSTEP_PARENT[name]
        or (type(name) == "string" and name:find("automation.phase.", 1, true) == 1
            and PATHS[name] and "automation.step") or nil
end

function Performance.Instrument(name, owner, key)
    if not PATHS[name] then return false, "unknown performance path" end
    if type(owner) ~= "table" or type(key) ~= "string" then
        return false, "instrumentation target must be a table field"
    end
    local callback = owner[key]
    if type(callback) ~= "function" then return false, "target is not callable" end
    local targets = instrumented[owner]
    if not targets then targets = {}; instrumented[owner] = targets end
    local current = targets[key]
    if current and current.name == name and owner[key] == current.wrapper then
        return true
    end
    if current and callback == current.wrapper then callback = current.original end
    local wrapper = function(...)
        return Performance.Measure(name, callback, ...)
    end
    targets[key] = {name=name, original=callback, wrapper=wrapper}
    owner[key] = wrapper
    return true
end

function Performance.InstallDefaults()
    local targets = {
        {"decision.policy", Nexus.Policy, "Decide"},
        {"sync.update", Nexus.Sync, "OnUpdate"},
        {"sync.incoming", Nexus.Sync, "HandleIncoming"},
        {"dps.update", Nexus.DpsCapture, "OnUpdate"},
        {"community.refresh", Nexus.CommunityBuilds, "Refresh"},
        {"leaderboard.refresh", Nexus.Leaderboard, "RefreshData"},
        {"panel.render", Nexus.Panel, "Render"},
        {"overlay.refresh", Nexus.WishlistOverlay, "Refresh"},
    }
    local installed = 0
    for _, target in ipairs(targets) do
        if type(target[2]) == "table" and type(target[2][target[3]]) == "function" then
            local ok = Performance.Instrument(target[1], target[2], target[3])
            if ok then installed = installed + 1 end
        end
    end
    return installed
end
