-- Once the original operation settles, Resume may adopt a different valid assignment.
-- Display progress/binding differences are not action restrictions.
local H=dofile('tests/prototype/orbs_support.lua');local M,A=H.M,H.A
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.OrbPlan({{spellId=410002,quality=2,stacks=3}});check(M.Start(3) and M.Pause(),'paused original request')
H.Offer();H.service.SelectPerk(410002);H.Result(410002,2)
check(M.Status().state=='PAUSED' and not M.Status().pending and M.Status().spent==1,'real exact synthetic result settled while paused')
check(A.SetFirstLoadoutWishlistIdentity('New legitimate target',{{spellId=410004,quality=3,stacks=2}}),'real writer selects a different valid plan after settlement')
local actions=#H.actions;local before=F.Serialize(Nexus.Store.State().orbRefinement)
check(M.Status().canResume and M.CompactStatus().canResume,'new valid assignment remains a legitimate Resume despite different display target')
check(#H.actions==actions and F.Serialize(Nexus.Store.State().orbRefinement)==before,'affordance reads neither adopt nor spend nor persist approval')
check(M.Resume(),'existing explicit Resume may adopt the new valid assignment')
local s=M.Status();check(s.spent==1 and s.limit==3 and s.pending and s.reserved==1,'original finite usage survives legitimate adoption')
check(H.Count('orb-spend')==2,'only explicit accepted Resume submitted its next synthetic Orb')
print('PASS orb_resume_assignment_adoption checks='..checks)
