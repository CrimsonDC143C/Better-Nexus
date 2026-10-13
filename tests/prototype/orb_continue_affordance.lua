-- The run-page opener describes a completed/refused check as a review.
-- No Check or Continue action is invoked; native UI delivery is not tested.
local H=dofile('tests/prototype/orbs_support.lua')
local UI,R=Nexus.OrbPanel,Nexus.OrbRuntime
UI.Show();local frame=assert(NexusOrbPanel)
local real=R.ContinueView
local spent=frame.snapshot.spent
local cases={
 {stage='checking',eligible=false,label='Check progress...'},
 {stage='ready',eligible=false,label='Continue...'},
 {stage='refused',eligible=false,label='Review check...'},
 {stage='done',eligible=false,label='Review outcome...'},
 {stage='idle',eligible=true,label='Continue...'},
}
local failures,checks={},0
for _,case in ipairs(cases)do
 R.ContinueView=function()return case end
 UI.Refresh();checks=checks+1
 if not(frame.cont:IsShown() and frame.cont:GetText()==case.label)then
  failures[#failures+1]=case.stage..': '..tostring(frame.cont:GetText())
 end
end
R.ContinueView=function()return {stage='idle',eligible=false}end
UI.Refresh();checks=checks+1;assert(not frame.cont:IsShown(),'no eligible outcome means no opener')
R.ContinueView=real;UI.Refresh()
checks=checks+1;assert(frame.snapshot.spent==spent,'rendering labels spends nothing')
for _,message in ipairs(failures)do print('FAIL '..message)end
assert(#failures==0,table.concat(failures,'; '))
print('PASS orb_continue_affordance checks='..checks..'; stage labels only, confirmation gates unchanged')
