-- Full run panel fails closed and reports one error per failure episode.
-- Synthetic display reads only: no run is started and no resource is spent.
local H=dofile('tests/prototype/orbs_support.lua')
local UI=Nexus.OrbPanel
UI.Show();local frame=assert(NexusOrbPanel)
local realStatus=Nexus.OrbRuntime.Status
local spent=frame.snapshot.spent
assert(type(spent)=='number','actual runtime spend counter available')
local failures,checks={},0
local function check(value,message)
 checks=checks+1;if not value then failures[#failures+1]=message end
end
local function episode()
 Nexus.OrbRuntime.Status=function()error('synthetic repeated display failure')end
 local raised=0
 for i=1,20 do
  local ok=pcall(UI.Refresh);if not ok then raised=raised+1 end
  check(not frame.start:IsEnabled() and not frame.stop:IsEnabled(),'failed display keeps mutation controls disabled '..i)
  check(frame.status:GetText():find('Controls are unavailable',1,true)~=nil,'failed display stays visibly unavailable '..i)
 end
 check(raised==1,'one error report per failure episode, observed '..raised)
 -- Neither the history page nor startup's loading display read run status.
 -- They must not rearm the report for the same still-failing source.
 UI.ShowLog();check(pcall(UI.Refresh),'history refresh remains readable')
 check(pcall(UI.Show),'returning from history does not report the same failure again')
 local startup=Nexus.StartupStatus
 Nexus.StartupStatus=function()return {coreReady=false}end
 check(pcall(UI.Refresh),'loading display remains readable')
 Nexus.StartupStatus=startup
 check(pcall(UI.Refresh),'returning from loading does not report the same failure again')
 Nexus.OrbRuntime.Status=realStatus
 local ok=pcall(UI.Refresh)
 check(ok,'successful display read recovers without error')
end
episode();episode()
check(frame.snapshot.spent==spent,'display failures leave the actual runtime spend counter unchanged')
for _,message in ipairs(failures)do print('FAIL '..message)end
assert(#failures==0,table.concat(failures,'; '))
print('PASS orb_panel_refresh_failure checks='..checks..'; synthetic repeated failure and recovery')
