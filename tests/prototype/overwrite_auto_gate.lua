-- Real TOC; users operate the real slash/HUD permission path. No live game.
local H=dofile('tests/prototype/harness.lua')
UIParent:SetSize(1280,720)
H.keepOverwriteWarningPrompts=true
H.Boot()
local function On()return Nexus.RecomputeStats().autoEnabled end
assert(not On(),'Auto starts OFF')
local actions=#H.actions
SlashCmdList.NEXUS('auto')
assert(not On(),'every enable waits for explicit warning approval')
local f=NexusOverwriteWarning
assert(f and f:IsShown(),'real enable route opens warning')
H.Advance(5)
f.no:Click();assert(not On() and #H.actions==actions,'No leaves Auto OFF and submits nothing')
SlashCmdList.NEXUS('auto')
assert(f:IsShown() and f.yes:IsEnabled() and f.no:IsEnabled(),'Auto warning has no countdown')
assert(not f.suppress:GetChecked(),'Auto suppression starts unchecked')
f.no:Click();assert(not On(),'declining Auto cannot enable it')
-- Legacy CheckButton clients may return 1/nil instead of true/false.
f.suppress.GetChecked=function(self)return self.checked and 1 or nil end
SlashCmdList.NEXUS('auto');f.suppress:SetChecked(true);f.yes:Click()
assert(On(),'affirmative Auto Yes enables the explicit request')
assert(NexusDB.overwriteWarnings.auto.version==1 and NexusDB.overwriteWarnings.auto.suppressed,'only affirmed checked Auto persists')
assert(NexusDB.overwriteWarnings.onboarding==nil,'Auto consent does not suppress onboarding')
assert(#H.actions==actions,'warning choices themselves perform no game/save operation')
SlashCmdList.NEXUS('auto');assert(not On(),'disable is immediate')
SlashCmdList.NEXUS('auto');assert(On() and not f:IsShown(),'explicit enable honors saved suppression')
SlashCmdList.NEXUS('auto');NexusDB.overwriteWarnings.auto=nil
Nexus.Panel.Show();NexusPanel._autoBtn:Click()
assert(not On() and f:IsShown(),'HUD enable uses the same pending gate')
NexusPanel._autoBtn:Click();SlashCmdList.NEXUS('auto')
assert(not On() and f:IsShown(),'repeated HUD/slash requests cannot bypass approval')
assert(Nexus.DisableOrdinaryAutomation(),'explicit disable succeeds while warning is pending')
f.yes:GetScript('OnClick')(f.yes)
assert(not On() and not f:IsShown(),'disable cancels the pending callback')
for _,event in ipairs({'PLAYER_LEAVING_WORLD','PLAYER_ENTERING_WORLD','PLAYER_LOGOUT'})do
 SlashCmdList.NEXUS('auto');assert(f:IsShown(),'warning reopens for a new request')
 H.Fire(event);f.yes:GetScript('OnClick')(f.yes)
 assert(not On() and not f:IsShown(),'world interruption cancels '..event)
end
SlashCmdList.NEXUS('auto')
local blocks=Nexus.OrbRuntime.BlocksOrdinary
Nexus.OrbRuntime.BlocksOrdinary=function()return true end
f.yes:Click();assert(not On(),'Orb exclusion is rechecked at approval')
Nexus.OrbRuntime.BlocksOrdinary=blocks
SlashCmdList.NEXUS('auto');f.yes:Click()
assert(On(),'a new explicit request can enable after the interruption')
f.yes:GetScript('OnClick')(f.yes)
assert(On(),'repeated approval cannot toggle the accepted permission OFF')
SlashCmdList.NEXUS('auto');assert(not On(),'approved permission still disables immediately')
assert(#H.actions==actions,'all pending/cancelled checks submit no game/save action')
print('PASS central Auto warning gate and independent consent')
