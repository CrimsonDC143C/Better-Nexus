-- Returning to the untouched original Saved Build preserves its exact identity.
ORB_SUPPORT_ECHOES={}
for id=500101,500112 do ORB_SUPPORT_ECHOES[#ORB_SUPPORT_ECHOES+1]={id,2} end
local H=dofile('tests/prototype/orbs_support.lua');local M,A=H.M,H.A
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.perks.serverBuildSlots={
 [1]={name='Original slot',verified=true,echoes={{spellId=410001,quality=1,stacks=1},{spellId=410003,quality=0,stacks=1}}},
 [2]={name='Other slot',verified=true,echoes={{spellId=410001,quality=1,stacks=1},{spellId=410003,quality=0,stacks=1}}}}
H.perks.serverActiveSlot=1;H.Notify();A.Poll()
local original={{spellId=410002,quality=2,stacks=3}}
check(A.SetLoadoutWishlistIdentity(1,'Untouched original',original),'real original Saved Build assignment')
local changed={{spellId=410002,quality=2,stacks=2}};local sidecar={}
for id=500101,500106 do changed[#changed+1]={spellId=id,quality=2,stacks=1,locked=true} end
for id=500107,500112 do sidecar[id]=true end
check(A.SetLoadoutWishlistIdentity(2,'Other invalid projection',changed,sidecar),'real independently-valid other assignment')
local identity=A.AssignedWishlist().identity
check(M.Start(3) and M.Pause(),'pause actual original operation')
local receipt=F.Serialize(Nexus.Store.State().orbRefinement.pending);local actions=#H.actions
H.perks.serverActiveSlot=2
local other=A.AssignedWishlist();check(other.state=='ready' and Nexus.OrbPolicy.Normalize(other.entries)==nil,'other slot has the real invalid projection')
check(not M.Status().canResume and not M.CompactStatus().canResume and not M.Resume(),'other current assignment/context cannot resume original pending receipt')
H.perks.serverActiveSlot=1
check(A.AssignedWishlist().identity==identity,'original Saved Build assignment identity was never rewritten')
check(M.Status().canResume and M.CompactStatus().canResume,'return to exact original context/assignment restores eligible Resume')
check(#H.actions==actions and F.Serialize(Nexus.Store.State().orbRefinement.pending)==receipt,'switching displayed slots neither submits nor settles original operation')
check(M.Resume(),'fresh action accepts exact original assignment/context')
check(H.Count('orb-spend')==1,'accepted Resume retains the one original request')
print('PASS orb_resume_original_assignment_restore checks='..checks)
