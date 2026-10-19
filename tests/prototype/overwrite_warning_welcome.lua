-- Preserve the original one-time welcome after new warning acknowledgment.
-- Real TOC/reload literal round-trip, synthetic saved data and game only.
local H=dofile('tests/prototype/harness.lua')
H.keepOverwriteWarningPrompts=true
H.Boot()
local f=NexusOverwriteWarning
assert(f and f:IsShown(),'first startup shows new warning')
assert(not NexusQuickStart or not NexusQuickStart:IsShown(),'welcome waits for reading')
local actions=#H.actions
H.Advance(5.01);f.yes:Click()
assert(NexusQuickStart and NexusQuickStart:IsShown(),'affirmation resumes existing first-time welcome')
assert(not Nexus.RecomputeStats().autoEnabled and #H.actions==actions,'reading enables no automation/action')
assert(NexusDB.overwriteWarnings==nil and not NexusDB.hasSeenQuickStart,'unchecked warning is not either saved acknowledgment')
for _,button in ipairs(NexusQuickStart.children)do
 if button.GetText and button:GetText()=='Later' then button:Click();break end
end
assert(NexusDB.hasSeenQuickStart and not NexusQuickStart:IsShown(),'existing welcome Later behavior is retained')
local F=dofile('tests/prototype/format5_support.lua')
H=F.Reload(function(h)h.keepOverwriteWarningPrompts=true end)
H.Advance(1,.05) -- allow the first decision/welcome check after startup readiness
f=NexusOverwriteWarning
assert(f:IsShown(),'old welcome acknowledgment cannot suppress warning after real module reload')
H.Advance(5.01);f.suppress:SetChecked(true);f.yes:Click()
assert(NexusDB.overwriteWarnings.onboarding.suppressed and not NexusDB.overwriteWarnings.auto,'only checked onboarding opt-out survives')
assert(not NexusQuickStart:IsShown() and not Nexus.RecomputeStats().autoEnabled,'old welcome stays seen and Auto stays OFF')
H=F.Reload(function(h)h.keepOverwriteWarningPrompts=true end)
H.Advance(1,.05)
assert(not NexusOverwriteWarning:IsShown(),'matching saved onboarding opt-out skips warning after reload')
SlashCmdList.NEXUS('auto');f=NexusOverwriteWarning
assert(f:IsShown() and f.yes:IsEnabled() and not f.suppress:GetChecked(),'Auto still has its own immediate unchecked warning')
f.no:Click()
assert(not Nexus.RecomputeStats().autoEnabled and #H.actions==0,'declining reload Auto submits nothing')
print('PASS real startup welcome continuation and independent reload suppression')
