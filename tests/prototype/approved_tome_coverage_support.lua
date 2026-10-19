-- Shared helpers for the approved tome/Wishlist coverage lane (stage 02).
-- A dofile helper, not a registered test: it asserts only its own setup
-- preconditions and nothing about product behaviour. Real TOC boots through
-- tests/prototype/harness.lua; every value is synthetic harness data (no
-- native client, no player data). Paths are relative to cwd = source root.
-- Lua 5.1 / LuaJIT syntax only.
local S = {}
S.F = dofile('tests/prototype/format5_support.lua')

-- One synthetic tome lever: member Echo 300000+i gated by lever 777000+i,
-- named "Tome of <name>" (the catalog's name-exact conformance rule).
function S.Lever(i, name, known, disabled)
    return {echo=300000+i, lever=777000+i, name=name, tome='Tome of '..name,
        known=known and true or false, disabled=disabled and true or false}
end

function S.Seed(H, levers)
    for _, l in ipairs(levers or {}) do
        H.names[l.lever] = l.tome
        H.AddEcho(l.echo, l.name, 1, 1, 0)
        H.db[l.echo].requiredSpell = l.lever
        if l.known then H.discovered[l.echo] = true end
        H.disabled[l.echo] = l.disabled
    end
    H.perks.discoveredEchoes = H.discovered
end

-- Named frames of an earlier harness stay in _G (harness.lua:11). Clear the
-- ones that still point at that harness so a fresh boot cannot bind to them
-- (JournalTab Install looks the journal frames up by name).
local function ClearStale(prev)
    if type(prev) ~= 'table' or type(prev.frames) ~= 'table' then return end
    for _, f in ipairs(prev.frames) do
        local name = rawget(f, 'name')
        if type(name) == 'string' and rawget(_G, name) == f then _G[name] = nil end
    end
end

-- Pre-boot setup on a fresh harness: levers, level, Orb stub
-- (tome_wishlist_priority.lua:30-31), optional spell textures
-- (tome_state_journal.lua:9-10) and the synthetic server mirror. The mirror
-- flips and notifies at once unless H.holdMirror is set
-- (tome_wishlist_revisit.lua:40-47); H.trace records every toggle request.
function S.Prepare(H, o)
    o = o or {}
    H.keepOverwriteWarningPrompts = o.keepPrompts and true or nil
    S.Seed(H, o.levers)
    for id, v in pairs(o.disabled or {}) do H.disabled[id] = v end
    H.playerLevel = o.level or 80
    H.orbKnown = true
    ProjectEbonhold.OrbService = {IsStateKnown=function() return H.orbKnown end,
        IsOfferPending=function() return false end}
    if o.icons then
        local info = GetSpellInfo
        GetSpellInfo = function(id)
            local name = info(id)
            if name then return name, '', 'Interface\\Icons\\Test_'..tostring(id) end
        end
    end
    H.trace, H.holdMirror, H.heldMirror = {}, o.holdMirror and true or false, {}
    local raw = H.service.ToggleTomeEcho
    H.service.ToggleTomeEcho = function(id)
        local result = raw(id)
        H.trace[#H.trace + 1] = {id=id, at=H.now}
        if H.holdMirror then H.heldMirror[id] = not H.disabled[id]
        else H.disabled[id] = not H.disabled[id]; H.Notify() end
        return result
    end
end

-- Fresh fixture per case, as in tome_wishlist_priority.lua:13-14.
function S.Fixture(o)
    ClearStale(S.lastH)
    Nexus, NexusDB, WishlistRealizerDB = nil, nil, nil
    local H = dofile('tests/prototype/harness.lua')
    S.lastH = H
    S.Prepare(H, o)
    H.Boot()
    assert(type(Nexus) == 'table' and type(Nexus.GameAdapter) == 'table', 'helper: the real TOC booted')
    return H, Nexus.GameAdapter
end

-- Offline module reload with round-tripped literal saved data
-- (format5_support.lua:83-86). Not a client /reload or relogin.
function S.Reload(o)
    local prev = S.lastH
    local H = S.F.Reload(function(h) ClearStale(prev); S.lastH = h; S.Prepare(h, o) end)
    assert(type(Nexus) == 'table' and type(Nexus.GameAdapter) == 'table', 'helper: the reloaded TOC booted')
    return H, Nexus.GameAdapter
end

function S.Assign(H, A, name, levers, design)
    local echoes = {}
    for i, l in ipairs(levers) do echoes[i] = {spellId=l.echo, quality=1, stacks=1} end
    local ok, why = A.SetFirstLoadoutWishlistIdentity(name, echoes, design)
    H.Notify()
    return ok == true, why
end

function S.AutoOn(H)
    SlashCmdList.NEXUS('auto'); H.Advance(.4, .05)
    return Nexus.RecomputeStats().autoEnabled == true and Nexus.Store.Settings().autoDisable == true
end

-- Run reset as in tome_wishlist_priority.lua:59.
function S.ResetToLevel1(H)
    H.resetAt = H.now; H.playerLevel = 1; H.Fire('PLAYER_LEVEL_UP', 1); H.Notify()
end

-- A new level-1 visit: level 80 observed, then a lower live level
-- (GameAdapter.lua:4662-4677 run boundary).
function S.NewVisit(H)
    H.playerLevel = 80; H.Fire('PLAYER_LEVEL_UP', 80); H.Notify(); H.Advance(1, .05)
    S.ResetToLevel1(H)
end

function S.Toggles(H, id)
    local n = 0
    for _, a in ipairs(H.actions) do
        if a[1] == 'toggle' and (id == nil or a[2] == id) then n = n + 1 end
    end
    return n
end

function S.Pending()
    local st = Nexus.Store.State()
    return type(st) == 'table' and type(st.tomeTogglePending) == 'table' and st.tomeTogglePending or {}
end

-- As progress_refresh_support.lua:119-127: seconds until pred() holds, or nil.
function S.Within(H, limit, pred)
    local start = H.now
    if pred() then return 0 end
    while H.now - start < limit - 1e-9 do
        H.Advance(.05, .05)
        if pred() then return H.now - start end
    end
    return nil
end

-- The real JournalData provider, captured as tome_state_journal.lua:25-28 does.
-- The world entry has no observed leave: call it before Auto is ON.
function S.CaptureProvider(H)
    local J = Nexus.JournalTab
    local install, captured = J.TryInstall, nil
    J.TryInstall = function(fn, ...) captured = fn; return install(fn, ...) end
    local ok, err = pcall(function() H.Fire('PLAYER_ENTERING_WORLD'); H.Advance(1, .05) end)
    J.TryInstall = install
    if not ok then error(err, 0) end
    assert(type(captured) == 'function', 'helper: the real JournalData provider was captured')
    return captured
end

-- Every structured entry with this name, in section order.
function S.Entries(data, name)
    local out = {}
    for _, sec in ipairs(type(data) == 'table' and data.sections or {}) do
        for _, e in ipairs(type(sec) == 'table' and type(sec.tomeRows) == 'table' and sec.tomeRows or {}) do
            if type(e) == 'table' and e.name == name then out[#out + 1] = e end
        end
    end
    return out
end

function S.Lines(data)
    local out = {}
    for _, sec in ipairs(type(data) == 'table' and data.sections or {}) do
        for _, line in ipairs(type(sec) == 'table' and type(sec.lines) == 'table' and sec.lines or {}) do
            out[#out + 1] = tostring(line)
        end
    end
    return out
end

-- Rendered rows of the real Journal page (tome_state_rows.lua:29-49). Tome
-- rows are the striped pool (JournalTab.lua:397-401); family rows are not.
function S.Rows(H, page, kind)
    local out = {}
    for _, f in ipairs(H.frames) do
        if f.parent == page and f.label and f.status and f:IsVisible()
            and (kind == nil or (kind == 'tome') == (f.background ~= nil)) then
            out[#out + 1] = f
        end
    end
    return out
end

function S.Row(H, page, name, status)
    for _, r in ipairs(S.Rows(H, page)) do
        if r.label:GetText() == name and (status == nil or r.status:GetText() == status) then return r end
    end
end

function S.Button(H, text)
    for _, f in ipairs(H.frames) do
        if f.kind == 'Button' and f:IsVisible() and f:GetText() == text then return f end
    end
    error('helper: visible button not found: '..tostring(text), 0)
end

function S.PageText(page)
    local out = {}
    for _, r in ipairs(page.regions or {}) do
        if r:IsShown() then out[#out + 1] = tostring(r:GetText() or '') end
    end
    return table.concat(out, '\n')
end

function S.TooltipCapture()
    S.tip = {}
    GameTooltip.SetOwner = function() S.tip = {} end
    GameTooltip.AddLine = function(_, text) S.tip[#S.tip + 1] = tostring(text) end
end

function S.Hover(r)
    S.tip = {}
    if r and r.scripts and r.scripts.OnEnter then r.scripts.OnEnter(r) end
    local text = table.concat(S.tip, '\n')
    if r and r.scripts and r.scripts.OnLeave then r.scripts.OnLeave(r) end
    return text
end

-- Count-mode catalog trap: a pass-through counter on Nexus.GameAdapter.Catalog
-- that never raises and is never removed. Reads are attributed by wrapping
-- Nexus.JournalTab.Refresh (the details toggle and SelectOurTab reach it as
-- M.Refresh, JournalTab.lua:24-25,514,1415) and each provider passed to
-- TryInstall: renderer reads = reads inside Refresh minus reads inside the
-- provider. Reads outside Refresh (idle runtime, association rows) are not
-- attributed. A world entry re-installs the raw provider (MainLifecycle.lua:880),
-- so T.Install must be called again after every PLAYER_ENTERING_WORLD.
function S.CatalogTrap(H)
    local A, J = Nexus.GameAdapter, Nexus.JournalTab
    local real, realRefresh = A.Catalog, J.Refresh
    assert(type(real) == 'function' and type(realRefresh) == 'function', 'helper: trap seams exist')
    local T = {n=0, refreshReads=0, providerReads=0, refreshes=0, providerCalls=0}
    T.fn = function(...) T.n = T.n + 1; return real(...) end
    A.Catalog = T.fn
    J.Refresh = function(...)
        local before = T.n
        T.refreshes = T.refreshes + 1
        local ok, err = pcall(realRefresh, ...)
        T.refreshReads = T.refreshReads + (T.n - before)
        if not ok then error(err, 0) end
    end
    function T.Wrap(fn, keep)
        return function(...)
            local before = T.n
            T.providerCalls = T.providerCalls + 1
            local ok, res = pcall(fn, ...)
            T.providerReads = T.providerReads + (T.n - before)
            if not ok then error(res, 0) end
            if keep then T.last, T.lastClone = res, H.Clone(res) end
            return res
        end
    end
    function T.Install(fn, keep) return J.TryInstall(T.Wrap(fn, keep)) end
    function T.Phase(fn)
        local r0, p0, c0, q0 = T.refreshReads, T.providerReads, T.refreshes, T.providerCalls
        local a0, s0 = #H.actions, #H.sent
        fn()
        return {renderer=(T.refreshReads - r0) - (T.providerReads - p0), provider=T.providerReads - p0,
            refreshes=T.refreshes - c0, providerCalls=T.providerCalls - q0,
            actions=#H.actions - a0, sent=#H.sent - s0}
    end
    return T
end

-- Non-aborting checker. "<CASE> reached:" / "<CASE> control:" messages are
-- REACHED (setup or seam preconditions); every other message is CONTRACT.
-- Each case runs under pcall; a Lua error is a SETUP_ERROR, not a check.
function S.Checker(fixture)
    local K = {total=0, passed=0, reached=0, contract=0, setup=0, ran={}}
    local current = '?'
    local function check(ok, message)
        message = tostring(message)
        K.total = K.total + 1
        local kind = 'CONTRACT'
        if message:find(current..' reached:', 1, true) == 1 or message:find(current..' control:', 1, true) == 1 then
            kind = 'REACHED'
        end
        if ok then K.passed = K.passed + 1
        else
            if kind == 'REACHED' then K.reached = K.reached + 1 else K.contract = K.contract + 1 end
            print(string.format('FAIL [%s] %s %s', current, kind, message))
        end
        return ok
    end
    -- argv[1], when present, is a comma-separated list of case ids.
    function K.Run(cases, argv)
        local wanted, order = nil, {}
        local spec = type(argv) == 'table' and argv[1] or nil
        if type(spec) == 'string' and spec ~= '' then
            wanted = {}
            for id in spec:gmatch('[^,%s]+') do wanted[id] = true; order[#order + 1] = id end
        end
        local known = {}
        for _, case in ipairs(cases) do
            known[case.id] = true
            if not wanted or wanted[case.id] then
                current = case.id
                K.ran[#K.ran + 1] = case.id
                local ok, err = pcall(case.fn, check)
                if not ok then
                    K.setup = K.setup + 1
                    print(string.format('SETUP_ERROR [%s] %s', case.id, tostring(err)))
                end
            end
        end
        for _, id in ipairs(order) do
            if not known[id] then
                K.setup = K.setup + 1
                print(string.format('SETUP_ERROR [%s] unknown case id in the filter', id))
            end
        end
        local ran = table.concat(K.ran, ',')
        print('cases run: '..(ran ~= '' and ran or 'none'))
        print(string.format('%s: %d/%d checks passed, %d reached failures, %d contract failures, %d setup errors, cases=%s',
            fixture, K.passed, K.total, K.reached, K.contract, K.setup, ran))
        if K.reached + K.contract + K.setup > 0 or #K.ran == 0 then
            error(string.format('%s: %d failed checks, %d setup errors, %d cases run', fixture,
                K.reached + K.contract, K.setup, #K.ran), 0)
        end
        print(string.format('PASS %s (%d checks)', fixture, K.total))
    end
    return K
end

return S
