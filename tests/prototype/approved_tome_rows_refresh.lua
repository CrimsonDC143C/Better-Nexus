local ARGV = rawget(_G, 'arg')
-- Approved tome/Wishlist coverage lane, stage 02: cases RR-1..RR-3 through the
-- real TOC JournalTab renderer. A count-mode catalog trap stays armed for each
-- whole case (approved_tome_coverage_support S.CatalogTrap): renderer reads are
-- the reads inside Nexus.JournalTab.Refresh minus the reads inside the provider.
-- Each case boots its own fixture. Synthetic harness data only; offline results
-- support no native UI, font, icon, performance or stutter claim.
-- Run from the source root: luajit tests/prototype/approved_tome_rows_refresh.lua [RR-1,RR-2]
local S = dofile('tests/prototype/approved_tome_coverage_support.lua')
local K = S.Checker('approved_tome_rows_refresh')
local D = S.Lever(1, 'Shelved Echo', true, true)   -- known, mirror disabled
local E = S.Lever(2, 'Active Echo', true, false)   -- known, mirror enabled
local U = S.Lever(3, 'Unseen Echo', false, false)  -- undiscovered

-- Level-1 boot, real Journal frames (tome_state_rows.lua:20-27), the captured
-- real JournalData provider, tooltip capture and the armed trap.
local function Rig(holdMirror)
    local H, A = S.Fixture({levers={D, E, U}, level=1, icons=true, holdMirror=holdMirror})
    local journal = CreateFrame('Frame', 'ProjectEbonholdEchoJournal', UIParent)
    journal:SetSize(570, 450)
    CreateFrame('ScrollFrame', 'ProjectEbonholdEchoJournalScroll', journal)
    CreateFrame('Button', 'ProjectEbonholdEchoJournalTab1', journal)
    local provider = S.CaptureProvider(H)
    local scroll = rawget(_G, 'NexusJournalScroll')
    local tab = rawget(_G, 'NexusJournalTab')
    assert(scroll and scroll.scrollChild and tab, 'helper: the real Journal tab installed')
    scroll:SetSize(520, 360)
    S.TooltipCapture()
    return {H=H, A=A, provider=provider, page=scroll.scrollChild, tab=tab, T=S.CatalogTrap(H)}
end

local function Tome(name, id, observed, extra)
    local t = {name=name, leverId=id, observed=observed, known=true,
        status=observed == 'disabled' and 'Disabled' or (observed == 'enabled' and 'Enabled' or 'Mixed'),
        icon='Interface\\Icons\\Synthetic_'..id, iconSource='tome spell', echoNames={name..' member'}}
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end
local function Sec(title, rows, lines)
    return {title=title, lines=lines or {'Synthetic dense text for '..title..'.'}, tomeRows=rows}
end
-- Tome pages carry no Target counts, so no family row reads the catalog.
local function Page(sections)
    local out = {{title='Target', lines={'No wishlist set'}}}
    for _, s in ipairs(sections) do out[#out + 1] = s end
    return {sections=out}
end

-- RR-1 (D4): later refreshes with a stub provider stay under the armed trap.
local function RR1(c)
    local R = Rig(false)
    local H, T, page, tab = R.H, R.T, R.page, R.tab
    local cur, stubCalls, acts, sent = nil, 0, 0, 0
    T.Install(function() stubCalls = stubCalls + 1; return cur end)
    local function Render(fn)
        local p = T.Phase(fn)
        acts, sent = acts + p.actions, sent + p.sent
        return p
    end
    local function Tomes() return #S.Rows(H, page, 'tome') end
    -- Positive control: a known Wishlist summary in the provider's Target form with
    -- three Missing families; AddRow reads the catalog once per refresh (JournalTab.lua:580).
    cur = {sections={
        {title='Target', lines={"Wishlist 'Control plan': 4 Echo families -- 1 represented, 3 missing, 0 off-Wishlist families in the saved build"}},
        {title='Pending (3)', lines={'Echo 1', 'Echo 2', 'Echo 3'}},
        {title='Extra copies compared with the plan', lines={}},
    }}
    local ctl = Render(function() tab:Click(); Nexus.JournalTab.Refresh() end)
    c(ctl.refreshes == 2 and ctl.provider == 0 and ctl.renderer == 2 and #S.Rows(H, page, 'family') == 3,
        'RR-1 control: Missing family rows read the catalog once per refresh (the trap sees renderer reads)')
    local pageA = Page({
        Sec('Synthetic disabled rows', {Tome('Synthetic tome A1', 880001, 'disabled'), Tome('Synthetic tome A2', 880002, 'disabled')}),
        Sec('Synthetic mixed rows', {Tome('Synthetic tome A3', 880003, 'mixed', {known=false})}),
        Sec('Synthetic enabled rows', {Tome('Synthetic tome A4', 880004, 'enabled'),
            Tome('Synthetic tome A5', 880005, 'enabled'), Tome('Synthetic tome A6', 880006, 'enabled')}),
    })
    tab:Click() -- deselect (no Refresh)
    cur = pageA
    local pa = Render(function() tab:Click(); S.Button(H, 'Show details'):Click() end)
    c(Tomes() == 6, 'RR-1 reached: phase select+details rendered 6 tome rows')
    c(pa.refreshes == 2 and pa.renderer == 0, 'RR-1 phase select+details: renderer read no catalog')
    local many = {}
    for i = 1, 60 do many[i] = Tome(string.format('Synthetic tome %02d', i), 881000 + i, 'disabled') end
    cur = Page({Sec('Synthetic disabled rows', many)})
    local pb = Render(function() Nexus.JournalTab.Refresh() end)
    c(Tomes() == 60, 'RR-1 reached: phase pool growth rendered 60 tome rows')
    c(pb.refreshes == 1 and pb.renderer == 0, 'RR-1 phase pool growth: renderer read no catalog')
    local polls, refreshes, calls = Nexus.RecomputeStats().polls or 0, T.refreshes, stubCalls
    H.Advance(1, .05) -- idle with the trap armed (review F1 lifted it here)
    c((Nexus.RecomputeStats().polls or 0) > polls and T.refreshes == refreshes and stubCalls == calls
        and Nexus.GameAdapter.Catalog == T.fn,
        'RR-1 reached: idle time ran the runtime with no page refresh and the trap stayed installed')
    cur = Page({Sec('Synthetic disabled rows', {Tome('Synthetic tome A1', 880001, 'disabled'),
        Tome('Synthetic tome without an icon', 880020, 'disabled', {icon=false})})})
    local pd = Render(function() Nexus.JournalTab.Refresh() end)
    c(Tomes() == 2, 'RR-1 reached: phase pool shrink rendered 2 tome rows')
    c(pd.refreshes == 1 and pd.renderer == 0, 'RR-1 phase pool shrink after idle: renderer read no catalog')
    cur = Page({Sec('Synthetic disabled rows', {}, {'Synthetic fallback text for the empty list.'}),
        Sec('Synthetic unreadable rows', {{leverId=880009}}, {'Synthetic fallback text for the unreadable entry.'})})
    local pe = Render(function() Nexus.JournalTab.Refresh() end)
    local text = S.PageText(page)
    c(pe.refreshes == 1 and Tomes() == 0 and text:find('Synthetic fallback text for the empty list.', 1, true)
        and text:find('Synthetic fallback text for the unreadable entry.', 1, true),
        'RR-1 reached: phase text fallback rendered the section lines and no tome rows')
    c(pe.renderer == 0, 'RR-1 phase text fallback: renderer read no catalog')
    cur = pageA
    local hidden, shown
    local pf = Render(function()
        S.Button(H, 'Hide details'):Click(); hidden = Tomes()
        S.Button(H, 'Show details'):Click(); shown = Tomes()
    end)
    c(hidden == 0 and shown == 6, 'RR-1 reached: phase fold/unfold hid and restored 6 tome rows')
    c(pf.refreshes == 2 and pf.renderer == 0, 'RR-1 phase fold/unfold: renderer read no catalog')
    local away, back
    local pg = Render(function() tab:Click(); away = Tomes(); tab:Click(); back = Tomes() end)
    c(away == 0 and back == 6, 'RR-1 reached: phase tab reselect hid and restored 6 tome rows')
    c(pg.refreshes == 1 and pg.renderer == 0, 'RR-1 phase tab reselect: renderer read no catalog')
    local reapplies = Nexus.Theme.Stats().reapplies or 0
    local ph = Render(function()
        Nexus.Theme.SetStyle('slate'); Nexus.Theme.SetPalette('graphite'); Nexus.Theme.Reapply()
        Nexus.JournalTab.Refresh()
    end)
    c(Nexus.Theme.Current().style == 'slate' and (Nexus.Theme.Stats().reapplies or 0) > reapplies and Tomes() == 6,
        'RR-1 reached: phase theme reapply changed the style and rendered 6 tome rows')
    c(ph.refreshes == 1 and ph.renderer == 0, 'RR-1 phase theme reapply: renderer read no catalog')
    local hovered, hoverReads = 0, 0
    local pi = Render(function()
        for _ = 1, 3 do Nexus.JournalTab.Refresh() end
        local before = T.n -- hovers run synchronously, so the raw count is theirs
        for _, r in ipairs(S.Rows(H, page, 'tome')) do
            if S.Hover(r):find(r.label:GetText(), 1, true) then hovered = hovered + 1 end
        end
        hoverReads = T.n - before
    end)
    c(pi.refreshes == 3 and hovered == 6, 'RR-1 reached: phase repeated refresh rendered and hovered 6 tome rows')
    c(pi.renderer == 0 and hoverReads == 0, 'RR-1 phase repeated refresh and hover: renderer read no catalog')
    c(acts == 0 and sent == 0, 'RR-1 rendering sent no gameplay or network action')
end

-- The provider's request section, found by its entries, not by its title: the
-- one section that lists both requested tomes (a disabled and an enabled one)
-- and whose every entry carries a request direction.
local function RequestSection(data, a, b)
    for _, sec in ipairs(type(data) == 'table' and data.sections or {}) do
        local rows = type(sec) == 'table' and sec.tomeRows
        if type(rows) == 'table' and #rows > 0 then
            local all, seen = true, {}
            for _, e in ipairs(rows) do
                if e.pending == nil then all = false end
                seen[tostring(e.name)] = true
            end
            if all and seen[a] and seen[b] then return sec end
        end
    end
end

-- RR-2 (D5, D4, D2): real JournalData -> real JournalTab for real pending requests (review F4).
local function RR2(c)
    local R = Rig(true)
    local H, A, T, page, tab = R.H, R.A, R.T, R.page, R.tab
    T.Install(R.provider, true)
    local okD, okE = A.ToggleLever(D.lever, false), A.ToggleLever(E.lever, true)
    local pend = S.Pending()
    local phases, acts, sent = {}, 0, 0
    local function Render(fn)
        local p = T.Phase(fn)
        phases[#phases + 1] = p
        acts, sent = acts + p.actions, sent + p.sent
        return p
    end
    Render(function() tab:Click() end)
    Render(function() S.Button(H, 'Show details'):Click() end)
    Render(function() Nexus.JournalTab.Refresh() end)
    local section = RequestSection(T.last, D.tome, E.tome)
    c(okD == true and okE == true and type(pend[D.lever]) == 'table' and pend[D.lever].want == false
        and type(pend[E.lever]) == 'table' and pend[E.lever].want == true and section ~= nil and #section.tomeRows == 2,
        'RR-2 reached: two real pending requests and the real request section')
    Render(function() S.Button(H, 'Hide details'):Click(); S.Button(H, 'Show details'):Click() end)
    Render(function() tab:Click(); tab:Click() end)
    Render(function()
        Nexus.Theme.SetStyle('slate'); Nexus.Theme.SetPalette('graphite'); Nexus.Theme.Reapply()
        Nexus.JournalTab.Refresh()
    end)
    local eachRead, rendererReads = #phases == 6, 0
    for _, p in ipairs(phases) do
        if p.provider < 1 then eachRead = false end
        rendererReads = rendererReads + p.renderer
    end
    c(eachRead, 'RR-2 reached: the provider read the catalog in each phase')
    c(#S.Rows(H, page, 'tome') == 5, 'RR-2 reached: the details page rendered 5 real tome rows')
    c(S.Row(H, page, D.tome, 'Enable pending') and S.Row(H, page, D.tome, 'Disabled'),
        'RR-2 a real enable request row shows Enable pending and its observation row stays Disabled')
    c(S.Row(H, page, E.tome, 'Disable pending') and S.Row(H, page, E.tome, 'Enabled'),
        'RR-2 a real disable request row shows Disable pending and its observation row stays Enabled')
    local req, obs = S.Row(H, page, D.tome, 'Enable pending'), S.Row(H, page, D.tome, 'Disabled')
    local reqTip, obsTip = req and S.Hover(req) or '', obs and S.Hover(obs) or ''
    c(reqTip:find('Enable requested; awaiting confirmation', 1, true)
        and reqTip:find('Last observed in the client mirror: Disabled', 1, true)
        and obsTip:find('Client mirror: Disabled', 1, true),
        'RR-2 the request tooltip keeps the request apart from the last observation')
    c(obs and obs.icon:GetTexture() == 'Interface\\Icons\\Test_'..D.lever,
        'RR-2 reached: the real tome spell icon reached the row')
    c(obsTip:find("Icon: the tome's spell icon.", 1, true), 'RR-2 the tooltip states the real icon provenance')
    c(S.Row(H, page, U.tome, 'Undiscovered') and not S.Row(H, page, U.tome, 'Enabled'),
        'RR-2 undiscovered real tome is Undiscovered, not Enabled')
    c(T.last ~= nil and S.F.Serialize(T.last) == S.F.Serialize(T.lastClone),
        'RR-2 the renderer leaves the real provider entries unmodified')
    c(rendererReads == 0, 'RR-2 phases select/details/refresh/fold/reselect/theme: renderer read no catalog')
    pend = S.Pending()
    c(type(pend[D.lever]) == 'table' and pend[D.lever].want == false and type(pend[E.lever]) == 'table'
        and pend[E.lever].want == true and acts == 0 and sent == 0,
        'RR-2 rendering keeps the Store pending map and sends nothing')
    -- Synthetic server mirror: only the enable of D is reflected; E stays held.
    H.disabled[D.echo] = false; H.Notify(); H.Advance(1, .05)
    local post = Render(function() Nexus.JournalTab.Refresh() end)
    pend = S.Pending()
    c(pend[D.lever] == nil and type(pend[E.lever]) == 'table', 'RR-2 reached: the mirror confirmation cleared the enable request')
    c(not S.Row(H, page, D.tome, 'Enable pending') and S.Row(H, page, D.tome, 'Enabled')
        and S.Row(H, page, E.tome, 'Disable pending'),
        'RR-2 after mirror confirmation the request row is gone and the tome shows Enabled')
    c(post.provider >= 1 and post.renderer == 0, 'RR-2 post-confirmation refresh: renderer read no catalog')
end

-- RR-3 (D2, D4, D5): stale presentation of the real provider during a world transition.
local function RR3(c)
    local R = Rig(true)
    local H, A, T, page, tab = R.H, R.A, R.T, R.page, R.tab
    T.Install(R.provider, false)
    local okE = A.ToggleLever(E.lever, true)
    tab:Click(); S.Button(H, 'Show details'):Click()
    c(okE == true and S.Row(H, page, D.tome, 'Disabled') and S.Row(H, page, E.tome, 'Enabled')
        and S.Row(H, page, E.tome, 'Disable pending'),
        'RR-3 control: before the transition the observations are clean and the request is pending')
    H.Fire('PLAYER_LEAVING_WORLD')
    local leave = T.Phase(function() Nexus.JournalTab.Refresh() end)
    c(S.PageText(page):find('world transition in progress', 1, true),
        'RR-3 reached: the world-transition coverage line is shown')
    local clean, stale = false, nil
    local rows = S.Rows(H, page, 'tome')
    for _, r in ipairs(rows) do
        local s = r.status:GetText()
        if s == 'Enabled' or s == 'Disabled' then clean = true end
        if s == 'Unknown (stale)' and not stale then stale = r end
    end
    c(#rows >= 3 and stale ~= nil, 'RR-3 reached: stale tome rows are rendered during the hold')
    c(not clean, 'RR-3 during a world transition no tome row shows a clean Enabled or Disabled badge')
    c(S.Row(H, page, E.tome, 'Disable pending'), 'RR-3 request rows keep their direction badges during the hold')
    c(stale ~= nil and S.Hover(stale):find('This reading may be stale', 1, true),
        "RR-3 a stale row's tooltip says it may be stale")
    H.Fire('PLAYER_ENTERING_WORLD')
    T.Install(R.provider, false) -- the world entry re-installed the raw provider (MainLifecycle.lua:880)
    local settling = T.Phase(function() Nexus.JournalTab.Refresh() end)
    H.Advance(3.2, .05)
    local after = T.Phase(function() Nexus.JournalTab.Refresh() end)
    c(settling.providerCalls >= 1 and after.providerCalls >= 1 and after.provider >= 1,
        'RR-3 reached: the counting wrapper is re-installed after the world entry')
    c(leave.renderer == 0 and settling.renderer == 0 and after.renderer == 0,
        'RR-3 stale-phase refresh: renderer read no catalog')
    local staleLeft = false
    for _, r in ipairs(S.Rows(H, page, 'tome')) do
        if tostring(r.status:GetText()):find('(stale)', 1, true) then staleLeft = true end
    end
    c(S.Row(H, page, D.tome, 'Disabled') and S.Row(H, page, E.tome, 'Enabled') and not staleLeft,
        'RR-3 after the settle the clean observations return')
end

K.Run({{id='RR-1', fn=RR1}, {id='RR-2', fn=RR2}, {id='RR-3', fn=RR3}}, ARGV)
