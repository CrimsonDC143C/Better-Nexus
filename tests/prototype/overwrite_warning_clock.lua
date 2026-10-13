-- Real warning owner; injected clocks, frames and database, no native client.
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local function Fresh(clock, suppressed)
    local H = dofile('tests/prototype/harness.lua')
    NexusOverwriteWarning = nil
    local resumed, accepted = 0, 0
    Nexus = {Store = {CurrentOwnerKey = function() return 'synthetic-owner' end,
        StateWriteStatus = function() return {mode='durable'} end},
        StartupStatus = function() return {coreReady=true} end,
        QuickStart = {ShowIfFirstTime = function() resumed = resumed + 1 end}}
    NexusDB = {marker='preserve'}
    if suppressed then NexusDB.overwriteWarnings = {onboarding={version=1,suppressed=true}} end
    GetTime = clock
    local W = dofile('ui/OverwriteWarning.lua')
    return H, W, function() return resumed, accepted end,
        function() accepted = accepted + 1; return true end
end
local function Blocked(f, label)
    check(f:IsShown() and not f.yes:IsEnabled() and not f.no:IsEnabled()
        and not f.suppress:IsEnabled(), label..': all consent controls remain disabled')
    check(type(f:GetScript('OnUpdate'))=='function', label..': timer can recover')
end
local function Tick(f)
    local update = assert(f:GetScript('OnUpdate'), 'active countdown listener')
    update(f, 999999) -- elapsed argument is not reading evidence
end

local now = 1000
local H, W, counts = Fresh(function() return now end)
check(W.EnsureOnboarding()=='pending', 'fresh normal warning opens')
local f = NexusOverwriteWarning
now = math.huge; Tick(f)
Blocked(f, 'positive-infinite clock')
check(f.yes:GetScript('OnClick')(f.yes)==false and counts()==0,
    'infinite clock cannot acknowledge onboarding')
now = 1004; Tick(f); Blocked(f, 'finite recovery starts full reading interval')
now = 1008.99; Tick(f); Blocked(f, 'recovery still needs five seconds')
now = 1009; Tick(f)
check(f.yes:IsEnabled() and f.no:IsEnabled() and f.suppress:IsEnabled()
    and f:GetScript('OnUpdate')==nil, 'five valid recovered seconds enable choices and remove timer')
f.no:Click()
check(W.EnsureOnboarding()=='declined' and NexusDB.overwriteWarnings==nil and counts()==0,
    'decline after recovered countdown neither saves nor resumes welcome')

-- Bad initial samples must neither throw nor fabricate a zero-based start.
local badClocks = {
    {label='absent', clock=nil},
    {label='nil', clock=function() return nil end},
    {label='nan', clock=function() return 0/0 end},
    {label='positive infinity', clock=function() return math.huge end},
    {label='negative infinity', clock=function() return -math.huge end},
    {label='negative time', clock=function() return -1 end},
    {label='string', clock=function() return '1000' end},
    {label='throwing', clock=function() error('synthetic clock failure') end},
}
for _, item in ipairs(badClocks) do
    H, W, counts = Fresh(item.clock)
    local ok, outcome = pcall(W.EnsureOnboarding)
    check(ok and outcome=='pending', item.label..': unavailable initial time does not throw')
    f = NexusOverwriteWarning; Blocked(f, item.label..' initial')
    check(f.countdown:GetText()=='Read the warning: 5 seconds', item.label..': hold caption')
    local stamp = 2000
    GetTime = function() return stamp end
    Tick(f); Blocked(f, item.label..' first valid sample')
    stamp = 2004.999; Tick(f); Blocked(f, item.label..' before valid deadline')
    stamp = 2005; Tick(f)
    check(f.yes:IsEnabled() and f:GetScript('OnUpdate')==nil, item.label..': valid five seconds finish')
    f.close:Click()
    check(counts()==0 and NexusDB.overwriteWarnings==nil and #H.actions==0,
        item.label..': close submits nothing and saves no consent')
end

-- Time zero is valid; extreme finite samples cannot round away the delay.
for _, initial in ipairs({0, math.huge / 2}) do
    now = initial; H, W = Fresh(function() return now end)
    check(W.EnsureOnboarding()=='pending', 'finite initial clock opens')
    f=NexusOverwriteWarning; Tick(f); Blocked(f, 'unchanged finite initial time')
    if initial==0 then
        now=4.999; Tick(f); Blocked(f, 'time-zero interval before expiry')
        now=5; Tick(f); check(f.yes:IsEnabled(), 'time-zero interval completes at five')
    end
    f.close:Click()
end

-- A reversal invalidates the interval, rather than accepting an old deadline.
now = 1000; H, W, counts = Fresh(function() return now end)
W.EnsureOnboarding(); f = NexusOverwriteWarning
now = 1003; Tick(f); now = 999; Tick(f); Blocked(f, 'backward time')
now = 1003.99; Tick(f); Blocked(f, 'reversed interval before full reading')
now = 1004; Tick(f)
check(f.yes:IsEnabled(), 'reversed interval recovers after five monotone seconds')
f.close:Click()

-- An interruption at the final click is checked again, even with OnUpdate gone.
now = 1000; H, W, counts = Fresh(function() return now end)
W.EnsureOnboarding(); f = NexusOverwriteWarning; now=1005; Tick(f)
check(f.yes:IsEnabled() and f:GetScript('OnUpdate')==nil, 'normal countdown completed')
GetTime = function() error('synthetic final-click clock failure') end
check(pcall(f.yes:GetScript('OnClick'), f.yes), 'clock failure at click does not throw')
Blocked(f, 'unavailable clock at final click')
check(counts()==0 and NexusDB.overwriteWarnings==nil, 'failed final click grants no consent')
GetTime = function() return now end
now=1006; Tick(f); Blocked(f, 'final-click interruption recovery')
now=1011; Tick(f); f.yes:Click()
check(counts()==1 and W.EnsureOnboarding()=='accepted' and NexusDB.overwriteWarnings==nil,
    'unchecked fresh valid consent resumes welcome once and saves no opt-out')
f.yes:GetScript('OnClick')(f.yes)
check(counts()==1, 'stale click cannot acknowledge twice')

-- A checkbox clock failure after completion must restore the visible timer,
-- without waiting for the user to make another acceptance/refusal attempt.
now=1000; H, W, counts=Fresh(function() return now end)
W.EnsureOnboarding(); f=NexusOverwriteWarning; now=1005; Tick(f)
check(f.yes:IsEnabled() and f.suppress:IsEnabled() and f:GetScript('OnUpdate')==nil,
    'normal countdown completed before checkbox fault')
GetTime=function() error('synthetic checkbox clock failure') end
f.suppress:SetChecked(true)
check(pcall(f.suppress:GetScript('OnClick'), f.suppress), 'checkbox clock failure does not throw')
Blocked(f, 'unavailable clock at suppression checkbox')
check(not f.suppress:GetChecked() and f.countdown:GetText()=='Read the warning: 5 seconds',
    'checkbox fault clears only unchecked consent UI and restores reading caption')
check(counts()==0 and NexusDB.overwriteWarnings==nil and #H.actions==0,
    'checkbox fault neither acknowledges nor writes nor acts')
GetTime=function() return now end
now=1006; Tick(f); Blocked(f, 'checkbox recovery begins a fresh interval')
now=1010.999; Tick(f); Blocked(f, 'checkbox recovery before five valid seconds')
now=1011; Tick(f)
check(f.yes:IsEnabled() and f.no:IsEnabled() and f.suppress:IsEnabled()
    and f:GetScript('OnUpdate')==nil, 'checkbox recovery completes after five fresh seconds')
check(counts()==0 and NexusDB.overwriteWarnings==nil, 'recovery does not grant automatic consent')
f.no:Click()
check(W.EnsureOnboarding()=='declined' and not f:IsShown() and NexusDB.overwriteWarnings==nil,
    'No after checkbox recovery declines without saving')
GetTime=function() error('inactive checkbox must not consult clock') end
f.suppress:SetChecked(true)
check(pcall(f.suppress:GetScript('OnClick'), f.suppress) and not f.suppress:GetChecked()
    and f:GetScript('OnUpdate')==nil, 'inactive checkbox remains an inert unchecked callback')

-- No/X/Escape remain available for dismissal; Auto has no new clock delay.
H, W, counts = Fresh(nil)
W.EnsureOnboarding(); f=NexusOverwriteWarning; f.close:Click()
check(W.EnsureOnboarding()=='declined' and f:GetScript('OnUpdate')==nil,
    'missing clock does not prevent closing without consent')
local accept
H, W, counts, accept = Fresh(function() error('Auto must not consult countdown clock') end, true)
local owner = {}
check(W.RequestAuto(owner, accept)==false, 'explicit Auto request opens its separate warning')
f = NexusOverwriteWarning
check(f:IsShown() and f.yes:IsEnabled() and f.no:IsEnabled(), 'Auto remains immediately usable')
f.suppress:SetChecked(true); f.suppress:Click()
check(f.suppress:GetChecked() and f.yes:IsEnabled() and f:GetScript('OnUpdate')==nil,
    'active Auto checkbox adds no onboarding clock delay')
f.suppress:SetChecked(false)
f.yes:Click()
local _, accepted = counts()
check(accepted==1 and NexusDB.overwriteWarnings.auto==nil, 'explicit unchecked Auto consent runs once')
check(#H.actions==0, 'warning owner has no gameplay operation')
print('PASS overwrite warning unavailable/nonfinite/reversed clock and final consent checks='..checks)
