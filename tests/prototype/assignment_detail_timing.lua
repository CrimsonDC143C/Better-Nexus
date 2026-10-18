-- Synthetic-clock mechanics for opt-in, session-only assignment detail.
-- No game access and no wall-clock performance assertions.
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local function pack(...) return {n=select('#', ...), ...} end
_G.Nexus = {}
_G.GetTime = function() return 100 end
dofile('core/Performance.lua')
local P = Nexus.Performance
local now, reads = 0, 0
local function clock() reads = reads + 1; return now end
local function setup()
    P.SetClock(clock)
    P.SetEnabled(true)
    check(P.ResetAssignmentDetail(), 'reset outside active detail')
    check(P.SetAssignmentDetailEnabled(true), 'enable outside active detail')
    now, reads = 0, 0
end
local function row(snapshot, name, collection)
    for _, item in ipairs(snapshot[collection or 'rows']) do
        if item.name == name then return item end
    end
end
local function edge(snapshot, parent, child)
    for _, item in ipairs(snapshot.edges) do
        if item.parent == parent and item.child == child then return item.count end
    end
end
local function branchWork(snapshot, branchName, countName)
    local branch = row(snapshot, branchName, 'branches')
    for _, count in ipairs(branch.work) do
        if count.name == countName then return count.value end
    end
end

-- Default off: preserve every callback value, including trailing nil, and no
-- diagnostic clock/context/counter work. Ordinary timing remains enabled.
check(P.DetailAssignmentEnabled() == false, 'detail defaults off')
P.SetClock(clock)
local expected = {}
local values = pack(P.MeasureAssignmentDetail('assignment.read', function(a, b)
    check(a == expected and b == 7, 'arguments retain identity')
    now = now + 4
    check(P.NoteAssignmentBranch('legacy') == false, 'disabled branch has no context')
    check(P.NoteAssignmentCount('slots_reads') == false, 'disabled counter has no context')
    return expected, nil, false, nil
end, expected, 7))
check(values.n == 4 and values[1] == expected and values[2] == nil
    and values[3] == false and values[4] == nil, 'all returns preserved')
check(reads == 0 and P.SnapshotAssignmentDetail().activeDepth == 0,
    'default-off does not read clock or leave context')
check(row(P.SnapshotAssignmentDetail(), 'assignment.read').invocations == 0,
    'default-off zero row is not measured work')
check(not row(P.SnapshotAssignmentDetail(), 'assignment.read').available
    and not row(P.SnapshotAssignmentDetail(), 'assignment.read').exclusiveAvailable,
    'empty aggregates explicitly unavailable rather than measured zero')

-- Exact same-invocation subtraction and branch association. Candidate is
-- nested in wishlist; it must not be subtracted again from the root.
setup()
P.MeasureAssignmentDetail('assignment.read', function()
    P.NoteAssignmentBranch('legacy')
    P.NoteAssignmentCount('slots_reads')
    now = 1
    P.MeasureAssignmentDetail('assignment.slots', function() now = 4 end)
    now = 5
    P.MeasureAssignmentDetail('assignment.wishlist', function()
        now = 6
        P.MeasureAssignmentDetail('assignment.candidates', function()
            P.NoteAssignmentCount('candidate_builds')
            P.NoteAssignmentCount('candidate_rows', 12)
            now = 9
        end)
        now = 12
    end)
    now = 15
end)
local s = P.SnapshotAssignmentDetail()
local root = row(s, 'assignment.read')
check(root.count == 1 and root.totalMs == 15 and root.exclusiveCount == 1
    and root.exclusiveTotalMs == 5, 'root subtracts only 3+7 direct-child ms')
local wishlist = row(s, 'assignment.wishlist')
check(wishlist.totalMs == 7 and wishlist.exclusiveTotalMs == 4,
    'wishlist subtracts its own 3 ms child')
check(row(s, 'assignment.candidates').totalMs == 3, 'leaf inclusive elapsed')
check(row(s, 'legacy', 'branches').totalMs == 15
    and row(s, 'legacy', 'branches').exclusiveTotalMs == 5,
    'branch records the same completed root invocation')
check(edge(s, 'assignment.read', 'assignment.wishlist') == 1
    and edge(s, 'assignment.wishlist', 'assignment.candidates') == 1,
    'actual fixed parent edges observed')
check(row(s, 'candidate_rows', 'counts').value == 12 and reads == 8,
    'fixed work counters and two clock reads per completed span')
check(branchWork(s, 'legacy', 'slots_reads') == 1
    and branchWork(s, 'legacy', 'candidate_builds') == 1
    and branchWork(s, 'legacy', 'candidate_rows') == 12,
    'root source branch owns its child work counters')
check(s.windowAvailable and s.windowStartMs == 0 and s.windowEndMs == 15,
    'detail window uses this clock and root boundaries')
check(#P.RecentOperations(0, 200, 100) == 0 and P.Stats('hud.phase.assignment').count == 0,
    'detail does not enter ordinary ring or aggregate paths')

-- Snapshot is detached, including nested aggregate/counter/edge tables.
s.rows[1].totalMs = 999; s.branches[1].count = 999
s.counts[1].value = 999; s.edges[1].count = 999
local copy = P.SnapshotAssignmentDetail()
check(copy.rows[1].totalMs == 15 and copy.branches[1].count == 1
    and copy.counts[1].value == 1 and copy.edges[1].count ~= 999,
    'snapshot aliases no retained tables')
check(#copy.rows == 7 and #copy.branches == 7 and #copy.counts == 5 and #copy.edges == 49,
    'retained label and edge shapes fixed')

-- Ordinary HUD breadcrumb still names the established inclusive outer phase.
setup()
P.Reset()
P.Measure('hud.prepare', function()
    P.Measure('hud.phase.assignment', function()
        P.MeasureAssignmentDetail('assignment.read', function()
            P.NoteAssignmentBranch('table')
            now = 2
            P.MeasureAssignmentDetail('assignment.projection', function() now = 7 end)
            now = 9
        end)
    end)
    now = 10
end)
local ops = P.RecentOperations(0, 200, 100)
check(#ops == 1 and ops[1].name == 'hud.prepare', 'one established HUD ring entry')
local fields = {}; for _, field in ipairs(ops[1].fields) do fields[field.key] = field.value end
check(fields.mode == 'hud.phase.assignment' and fields.outcome == 9,
    'detail does not replace outer dominant assignment breadcrumb')

-- Child measurements outside a root and rejected labels do not acquire a
-- context. Dynamic labels are never stored; counts and branches are allowlisted.
setup()
P.MeasureAssignmentDetail('assignment.slots', function() now = 5 end)
check(reads == 0 and row(P.SnapshotAssignmentDetail(), 'assignment.slots').count == 0,
    'standalone child is not attributed to an assignment')
P.MeasureAssignmentDetail('private dynamic name', function() now = 8 end)
check(reads == 0 and P.SnapshotAssignmentDetail().rejectedLabels == 1,
    'unknown path bypassed without clock or retention')
P.MeasureAssignmentDetail('assignment.read', function()
    check(not P.NoteAssignmentBranch('player secret'), 'unknown branch rejected')
    check(not P.NoteAssignmentCount('payload'), 'unknown count rejected')
    check(not P.NoteAssignmentCount('candidate_rows', -1), 'negative work rejected')
    check(not P.NoteAssignmentCount('candidate_rows', 1.5), 'fractional work rejected')
    check(not P.NoteAssignmentCount('candidate_rows', math.huge), 'nonfinite work rejected')
    P.NoteAssignmentCount('candidate_rows', 9007199254740991)
    P.NoteAssignmentCount('candidate_rows', 1)
    now = 10
end)
check(row(P.SnapshotAssignmentDetail(), 'candidate_rows', 'counts').value == 9007199254740991,
    'work totals saturate at the exact-integer bound')
check(row(P.SnapshotAssignmentDetail(), 'unclassified', 'branches').count == 1,
    'missing branch explicitly unclassified')

-- Product errors and objects propagate unchanged; active contexts unwind.
setup()
local failure = {}
local ok, err = pcall(function()
    P.MeasureAssignmentDetail('assignment.read', function()
        P.NoteAssignmentBranch('first_run')
        P.MeasureAssignmentDetail('assignment.wishlist', function() error(failure) end)
    end)
end)
s = P.SnapshotAssignmentDetail()
check(not ok and err == failure, 'error object identity preserved')
check(s.activeDepth == 0 and row(s, 'assignment.read').failed == 1
    and row(s, 'assignment.wishlist').failed == 1, 'all errored frames unwind')
check(row(s, 'first_run', 'branches').failed == 1 and row(s, 'assignment.read').count == 0,
    'errored branch has no invented completed sample')
local function stringFailure() error('same product error', 0) end
local _, rawError = pcall(stringFailure)
local _, timedError = pcall(function() P.MeasureAssignmentDetail('assignment.read', stringFailure) end)
check(rawError == timedError, 'exact product error string propagated')
P.MeasureAssignmentDetail('assignment.read', function()
    P.NoteAssignmentBranch('ready') -- Unknown outcome must not become a branch.
    local caught = pcall(function()
        P.MeasureAssignmentDetail('assignment.slots', function() error(failure) end)
    end)
    check(caught == false, 'caller can catch a child product error')
    now = 5
end)
s = P.SnapshotAssignmentDetail()
check(row(s, 'assignment.read').count == 1 and row(s, 'assignment.read').exclusiveCount == 0,
    'caught failed child invalidates only exclusive coverage')
check(s.activeDepth == 0, 'no parent leaks to later calls')

-- Work belongs to the nearest root, even when a different source branch is
-- nested inside another read. Global totals record each note exactly once.
setup()
P.MeasureAssignmentDetail('assignment.read', function()
    P.NoteAssignmentCount('slots_reads') -- Branch may be identified after slots.
    P.NoteAssignmentBranch('legacy')
    P.NoteAssignmentCount('candidate_rows', 11)
    P.MeasureAssignmentDetail('assignment.read', function()
        P.NoteAssignmentBranch('table')
        P.NoteAssignmentCount('slots_reads', 2)
        P.MeasureAssignmentDetail('assignment.candidates', function()
            P.NoteAssignmentCount('candidate_rows', 7)
        end)
        P.MeasureAssignmentDetail('assignment.read', function()
            P.NoteAssignmentBranch('discovery')
            P.NoteAssignmentCount('discovery_rows', 3)
            P.NoteAssignmentCount('candidate_rows', 5)
            P.NoteAssignmentCount('projection_rows', 4)
        end)
        P.NoteAssignmentCount('candidate_rows', 2)
    end)
    P.NoteAssignmentCount('candidate_rows', 13)
    now = 10
end)
s = P.SnapshotAssignmentDetail()
check(branchWork(s, 'legacy', 'candidate_rows') == 24
    and branchWork(s, 'table', 'candidate_rows') == 9
    and branchWork(s, 'discovery', 'candidate_rows') == 5,
    'mixed nested root rows stay attributable to their own branch')
check(branchWork(s, 'legacy', 'slots_reads') == 1
    and branchWork(s, 'table', 'slots_reads') == 2
    and branchWork(s, 'discovery', 'slots_reads') == 0,
    'a slot count before branch classification follows that same root')
check(branchWork(s, 'discovery', 'discovery_rows') == 3
    and branchWork(s, 'discovery', 'projection_rows') == 4
    and branchWork(s, 'legacy', 'projection_rows') == 0,
    'fixed discovery/projection work not inherited by parent roots')
check(row(s, 'candidate_rows', 'counts').value == 38
    and row(s, 'slots_reads', 'counts').value == 3,
    'global totals do not double-count nested root completion')
local legacy = row(s, 'legacy', 'branches')
check(#legacy.work == 5 and legacy.workCompleteInvocations == 1
    and legacy.workPartialInvocations == 0 and legacy.workUntimedInvocations == 0,
    'fixed branch work shape and completed status')
legacy.work[1].value = 999
check(branchWork(P.SnapshotAssignmentDetail(), 'legacy', 'slots_reads') == 1,
    'branch work snapshots are detached')
local workFailure = {}
pcall(function()
    P.MeasureAssignmentDetail('assignment.read', function()
        P.NoteAssignmentBranch('legacy')
        P.NoteAssignmentCount('candidate_rows', 6)
        error(workFailure)
    end)
end)
s = P.SnapshotAssignmentDetail()
legacy = row(s, 'legacy', 'branches')
check(branchWork(s, 'legacy', 'candidate_rows') == 30
    and row(s, 'candidate_rows', 'counts').value == 44,
    'failed root retains recorded partial work exactly once')
check(legacy.workCompleteInvocations == 1 and legacy.workPartialInvocations == 1
    and legacy.workUntimedInvocations == 1 and legacy.failed == 1,
    'failed callback work explicitly partial and untimed')
P.MeasureAssignmentDetail('assignment.read', function()
    P.NoteAssignmentBranch('table')
    P.NoteAssignmentCount('candidate_rows', 2)
    pcall(function()
        P.MeasureAssignmentDetail('assignment.candidates', function()
            P.NoteAssignmentCount('candidate_rows', 3)
            error(workFailure)
        end)
    end)
    now = 15
end)
s = P.SnapshotAssignmentDetail()
check(branchWork(s, 'table', 'candidate_rows') == 14
    and row(s, 'table', 'branches').workPartialInvocations == 1,
    'caught child failure marks the containing root work partial')
check(s.activeDepth == 0, 'branch work association retains no call context')

-- Clock failures are tried once, then constant bypass until SetClock; Reset
-- does not claim availability or revive the clock.
setup()
local failedReads = 0
P.SetClock(function() failedReads = failedReads + 1; error('clock failure') end)
for _=1,3 do
    check(P.MeasureAssignmentDetail('assignment.read', function() return 17 end) == 17,
        'failed-clock callback still runs')
end
check(failedReads == 1 and P.SnapshotAssignmentDetail().unavailableReads == 3,
    'unavailable clock is not retried and has explicit bypass count')
P.ResetAssignmentDetail()
P.MeasureAssignmentDetail('assignment.read', function() return true end)
check(failedReads == 1 and not P.DetailAssignmentEnabled(), 'reset does not revive failed clock')
for _, unavailable in ipairs({false, math.huge, -math.huge}) do
    local n = 0
    P.SetClock(function() n = n + 1; return unavailable end)
    P.MeasureAssignmentDetail('assignment.read', function() return false end)
    P.MeasureAssignmentDetail('assignment.read', function() return false end)
    check(n == 1 and P.SnapshotAssignmentDetail().activeDepth == 0,
        'nonfinite/non-numeric clock bypassed once')
end
local n = 0
P.SetClock(function() n = n + 1; return 0/0 end)
P.MeasureAssignmentDetail('assignment.read', function() end)
check(n == 1 and P.SnapshotAssignmentDetail().clockState == 'unavailable', 'NaN clock unavailable')
setup()
local finishReads = 0
P.SetClock(function()
    finishReads = finishReads + 1
    if finishReads == 1 then return 0 end
    return nil
end)
values = pack(P.MeasureAssignmentDetail('assignment.read', function() return expected, nil end))
s = P.SnapshotAssignmentDetail()
check(values.n == 2 and values[1] == expected and values[2] == nil,
    'finish-clock failure preserves callback returns')
check(finishReads == 2 and row(s, 'assignment.read').unavailable == 1
    and not row(s, 'assignment.read').available and s.activeDepth == 0,
    'unavailable finish has no completed timing and unwinds')
setup()
now = -1e308
P.MeasureAssignmentDetail('assignment.read', function() now = 1e308 end)
check(row(P.SnapshotAssignmentDetail(), 'assignment.read').unavailable == 1,
    'finite endpoints with nonfinite elapsed do not produce a sample')
setup()
for _=1,3 do
    now = 0
    P.MeasureAssignmentDetail('assignment.read', function() now = 8e307 end)
end
local huge = row(P.SnapshotAssignmentDetail(), 'assignment.read')
check(huge.count == 3 and huge.totalAvailable == false and huge.totalMs == nil
    and huge.exclusiveTotalAvailable == false and huge.exclusiveTotalMs == nil,
    'aggregate overflow is unavailable, not infinity or a truncated measured total')
setup()
P.MeasureAssignmentDetail('assignment.read', function() end)
local zero = row(P.SnapshotAssignmentDetail(), 'assignment.read')
check(zero.available and zero.exclusiveAvailable and zero.totalMs == 0,
    'a completed valid zero-duration sample is distinguished from unavailable')

-- Backward/overlapping intervals can retain a valid parent's inclusive elapsed
-- while withholding its residual. No subtraction of independent maxima.
setup()
P.MeasureAssignmentDetail('assignment.read', function()
    now = 5
    P.MeasureAssignmentDetail('assignment.slots', function() now = 3 end)
    now = 10
end)
s = P.SnapshotAssignmentDetail()
check(row(s, 'assignment.slots').count == 0 and row(s, 'assignment.slots').unavailable == 1,
    'backward child has no elapsed sample')
check(row(s, 'assignment.read').totalMs == 10 and row(s, 'assignment.read').exclusiveCount == 0,
    'backward child prevents invented root residual')
setup()
P.MeasureAssignmentDetail('assignment.read', function()
    now = 1
    P.MeasureAssignmentDetail('assignment.slots', function() now = 4 end)
    now = 3
    P.MeasureAssignmentDetail('assignment.state', function() now = 6 end)
    now = 10
end)
check(row(P.SnapshotAssignmentDetail(), 'assignment.read').exclusiveCount == 0,
    'overlapping direct children refuse exclusive coverage')
setup()
P.MeasureAssignmentDetail('assignment.read', function()
    now = 2
    P.MeasureAssignmentDetail('assignment.slots', function() now = 8 end)
    now = 6
end)
check(row(P.SnapshotAssignmentDetail(), 'assignment.read').exclusiveCount == 0,
    'child ends beyond root: residual unavailable')

-- Active Reset/Enable changes fail closed. SetClock is an existing API and may
-- change during product work; its generation prevents mixed-clock subtraction.
setup()
P.MeasureAssignmentDetail('assignment.read', function()
    local reset, resetReason = P.ResetAssignmentDetail()
    local changed, changeReason = P.SetAssignmentDetailEnabled(false)
    check(reset == false and resetReason == 'assignment detail is active', 'active reset rejected')
    check(changed == false and changeReason == 'assignment detail is active', 'active enable change rejected')
    check(P.DetailAssignmentEnabled(), 'rejected control leaves detail enabled')
    now = 4
end)
check(row(P.SnapshotAssignmentDetail(), 'assignment.read').count == 1, 'active controls retain invocation')
P.MeasureAssignmentDetail('assignment.read', function()
    P.SetClock(function() return 20 end)
end)
check(row(P.SnapshotAssignmentDetail(), 'assignment.read').unavailable == 1,
    'clock generation change invalidates current invocation')
P.MeasureAssignmentDetail('assignment.read', function() end)
check(not P.SnapshotAssignmentDetail().windowAvailable,
    'aggregate window refuses a combined origin across clocks')

-- Recursion receives a separate nearest-root branch and is depth bounded.
setup()
P.MeasureAssignmentDetail('assignment.read', function()
    P.NoteAssignmentBranch('table'); now = 1
    P.MeasureAssignmentDetail('assignment.read', function()
        P.NoteAssignmentBranch('discovery'); now = 3
    end)
    now = 5
end)
s = P.SnapshotAssignmentDetail()
check(row(s, 'table', 'branches').exclusiveTotalMs == 3
    and row(s, 'discovery', 'branches').totalMs == 2, 'recursive roots retain separate branches')
check(s.windowStartMs == 0 and s.windowEndMs == 5, 'nested roots keep true window envelope')
setup()
local function recurse(n)
    if n > 0 then return P.MeasureAssignmentDetail('assignment.read', recurse, n-1) end
    check(P.NoteAssignmentBranch('legacy') == false, 'overflow root cannot label its parent')
    check(P.NoteAssignmentCount('projection_rows') == false, 'overflow root cannot count its parent')
    now = 20
    return 'done', nil
end
values = pack(P.MeasureAssignmentDetail('assignment.read', recurse, 20))
s = P.SnapshotAssignmentDetail()
check(values.n == 2 and values[1] == 'done' and values[2] == nil, 'bounded recursion keeps returns')
check(s.maximumDepth == 16 and s.activeDepth == 0 and s.depthBypasses == 5,
    'stack fixed at 16 and overflow bypasses unwind')
check(row(s, 'assignment.read').invocations == 16, 'only bounded stack frames retained')

-- General timing off gates detail too, without clock/counter work; explicit
-- detail reset does not affect ordinary aggregates or ring entries.
setup()
P.SetEnabled(false)
P.MeasureAssignmentDetail('assignment.read', function() now = 5 end)
check(reads == 0 and not P.DetailAssignmentEnabled(), 'general timing off cheap bypass')
P.SetEnabled(true)
P.Reset()
P.Measure('panel.render', function() now = 10 end)
local ordinary = P.Stats('panel.render').count
P.ResetAssignmentDetail()
check(P.Stats('panel.render').count == ordinary and #P.RecentOperations(0,200,100) == 1,
    'detail reset does not clear established ordinary evidence')
check(P.SetAssignmentDetailEnabled(false) and not P.DetailAssignmentEnabled(), 'explicit detail disable')
print('PASS assignment detail timing: '..checks..' synthetic-clock checks; no live measurements')
