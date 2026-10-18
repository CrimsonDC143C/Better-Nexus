-- Reviewer synthetic public-service/raw-mirror divergence; no native claim.
local H=dofile('tests/prototype/orbs_support.lua');local M,A=H.M,H.A
local mode=arg[1] or 'first'
-- The service reports the supported first-run slot 0; raw mirror is absent.
H.service.GetServerActiveSlot=function()return 0 end
if mode=='first' then H.perks.serverActiveSlot=nil end
H.OrbPlan({{spellId=410002,quality=2,stacks=3}})
assert(A.AssignedWishlist().state=='ready','real first-run assignment is ready')
assert(M.Start(3) and M.Pause(),'real public action starts and pauses')
if mode=='settled' then
 H.Offer();H.service.SelectPerk(410002);H.Result(410002,2)
 assert(not M.Status().pending and M.Status().spent==1,'actual original operation settled')
 H.perks.serverActiveSlot=nil
end
local full,compact=M.Status(),M.CompactStatus();local actions=#H.actions
local resumed,why=M.Resume()
print('NIL_SLOT',mode,'full='..tostring(full.canResume),'compact='..tostring(compact.canResume),'action='..tostring(resumed),'why='..tostring(why),'spendsBefore='..actions,'spendsAfter='..#H.actions)
assert(full.canResume and compact.canResume and resumed,'legitimate public first-run Resume must be offered by both views')
