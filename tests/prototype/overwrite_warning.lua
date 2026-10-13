-- Public warning UI / central permission seams; synthetic WoW and saved data.
local H=dofile('tests/prototype/harness.lua')
UIParent:SetSize(1280,720)
Nexus={Store={StateWriteStatus=function()return {mode='durable'}end},StartupStatus=function()return {coreReady=true}end}
NexusDB={hasSeenQuickStart=true}
local ok,W=pcall(dofile,'ui/OverwriteWarning.lua')
assert(ok and W,'new versioned overwrite warning owner exists')
assert(W.EnsureOnboarding()=='pending','old welcome flag cannot suppress new warning')
local f=NexusOverwriteWarning
assert(f and f:IsShown() and not f.yes:IsEnabled() and not f.no:IsEnabled())
assert(not f.suppress:IsEnabled() and not f.suppress:GetChecked())
f.yes:GetScript('OnClick')(f.yes)
f.no:GetScript('OnClick')(f.no)
f.suppress:SetChecked(true);f.suppress:GetScript('OnClick')(f.suppress)
assert(f:IsShown() and not f.suppress:GetChecked() and NexusDB.overwriteWarnings==nil,'early handlers cannot bypass countdown')
H.Advance(4.9)
assert(not f.yes:IsEnabled() and not f.no:IsEnabled(),'both choices remain delayed')
H.Advance(.1001) -- first scheduler sample strictly past the five-second deadline
assert(f.yes:IsEnabled() and f.no:IsEnabled() and f.suppress:IsEnabled())
assert(f:GetScript('OnUpdate')==nil,'countdown stops all frame work after five seconds')
f.suppress:SetChecked(true);f.no:Click()
assert(W.EnsureOnboarding()=='declined' and NexusDB.overwriteWarnings==nil,'No never acknowledges or saves suppression')
assert(#H.actions==0,'no gameplay action from opening or declining')
print('PASS overwrite warning first-open countdown and refusal')
