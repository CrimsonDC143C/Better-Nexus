local F=dofile('tests/prototype/tome_observation_support.lua')
local checks=0
local function expect(v,m)checks=checks+1;assert(v,'EXPECT: '..m)end
local W=F.Boot('known',true,false)
local function arm(plan,gate,visited,passed)
 F.Arm(W,plan)
 local a=assert(F.Facts(W)).arm
 expect(a.gate==gate,'gate '..gate..' got '..tostring(a.gate))
 expect(a.visited==visited and a.passed==passed,gate..' actual visited/passed masks')
end
arm(F.Plan(),'auto',1,0)
SlashCmdList.NEXUS('auto')
Nexus.MainInternals.StoreAuthorityOwner.UpdateSettingsV1('autoDisable',false)
arm(F.Plan(),'permission',3,1)
Nexus.MainInternals.StoreAuthorityOwner.UpdateSettingsV1('autoDisable',true)
arm(nil,'plan',7,3)
arm({advisorOnly=true},'advisor',15,7)
local discovery,pause=W.A.DiscoverySynced,W.A.TomeMutationPaused
local dc,pc=0,0
W.A.DiscoverySynced=function()dc=dc+1;return false end
W.A.TomeMutationPaused=function()pc=pc+1;return true end
arm(F.Plan(),'discovery',31,15)
expect(dc==1 and pc==0,'short circuit does not call pause after false discovery')
W.A.DiscoverySynced=discovery
arm(F.Plan(),'pause',63,31)
expect(pc==1,'normal pause gate called once')
W.A.TomeMutationPaused=pause
arm({advisorOnly=false,leverPlan={keep={},disable={}}},'eligible',127,127)
local calls=#W.O.calls
W.O.refuse=true
local ok,why=W.A.ToggleLever(F.LEVER[1],true)
expect(ok==false and why=='refused','existing refused interpretation retained')
local v=F.Facts(W)
expect(v.transaction.admission=='refused' and v.transaction.rawKind=='boolean' and v.accepted==0,'refusal distinct from accepted')
expect(v.tracked.observed==false and v.tracked.pending==nil and v.tracked.acceptedOrdinal==nil,'before any acceptance tracked request remains unobserved/unknown')
W.O.refuse=false;W.O.hold=true
ok=W.A.ToggleLever(F.LEVER[1],true)
expect(ok==true,'adapter accepts synthetic host return')
v=F.Facts(W)
expect(v.accepted==1 and v.tracked.pending==true and v.tracked.member==F.ECHO[1],'accepted call records member/pending only')
expect(v.resolution.observed==false,'accepted is not a mirror result')
W.O.refuse=true
ok,why=W.A.ToggleLever(F.LEVER[2],true)
expect(ok==false and why=='refused','second lever refusal occurs after first acceptance')
v=F.Facts(W)
expect(v.transaction.lever==F.LEVER[2] and v.transaction.admission=='refused' and v.transaction.pending==nil and v.transaction.acceptedOrdinal==nil,'last attempt L2 has no stale pending/accepted ordinal')
expect(v.tracked.lever==F.LEVER[1] and v.tracked.pending==true and v.tracked.acceptedOrdinal==1,'refused L2 does not overwrite tracked accepted L1')
W.O.refuse=false;W.O.hold=false;W.H.Advance(2,.05)
v=F.Facts(W)
expect(v.resolution.outcome=='mirror_match' and v.resolution.rawKind=='boolean' and v.resolution.cur==true,'normal matching mirror observed')
expect(v.tracked.lever==F.LEVER[1] and v.tracked.pending==false and v.tracked.acceptedOrdinal==1,'resolution L1 clears its tracking despite last attempt L2')
expect(v.transaction.lever==F.LEVER[2] and v.transaction.admission=='refused','resolved L1 does not rewrite last refused L2 attempt')
W.H.disabled[F.ECHO[1]]=false;W.O.hold=true
expect(W.A.ToggleLever(F.LEVER[1],true)==true,'new synthetic pending for existing expiry path')
local before=#W.O.calls
ok,why=W.A.ToggleLever(F.LEVER[1],true)
expect(ok==false and why=='pending' and #W.O.calls==before,'pending refusal sends nothing extra')
W.H.Advance(31.5,.05)
v=F.Facts(W)
expect(v.resolution.outcome=='expired' and v.resolution.cur==false and v.tracked.pending==false,'expiry is separate from confirmation/refusal')
W.O.hold=false;W.O.queue={}
W.H.disabled[F.ECHO[1]]=false
arm(F.Plan(),'eligible',127,127)
v=F.Facts(W)
expect(v.arm.knownMember==F.ECHO[1] and v.transaction.member==F.ECHO[1],'existing known member and called member retained independently')
arm(F.Plan(),'spacing',127,63)
v=F.Facts(W)
expect(v.transaction.want==true and v.transaction.cur==false,'false raw prior state is retained, not lost to nil')
local M=F.Boot('missing')
F.Arm(M,{advisorOnly=false,leverPlan={keep={},disable={F.LEVER[1],F.LEVER[2]}}})
local m=F.Facts(M)
expect(m.arm.noKnown==2 and m.arm.knownKind=='nil' and m.arm.known==false,'two missing-member safety decisions distinguished')
expect(#M.O.calls==0,'missing-member observation authorizes no call')
local K=F.Boot('known',true,false)
K.H.discovered[F.ECHO[1]]=nil
local lv=K.A.Catalog().levers[F.LEVER[1]]
lv.members={F.ECHO[1],F.ECHO[2]} -- Synthetic boundary shape only; no product catalog change.
K.A.TomeObservationBegin()
expect(K.A.LeverHasKnownMember(F.LEVER[1])==true,'existing loop sees second synthetic discovered member')
expect(K.A.ToggleLever(F.LEVER[1],true)==true,'existing representative remains first member')
K.A.TomeObservationEnd()
local k=F.Facts(K)
expect(k.arm.knownMember==F.ECHO[2] and k.transaction.member==F.ECHO[1],'diagnostic distinguishes already-seen known member from actual called representative')
print('SUMMARY tome_observation_gates checks='..checks..' failures=0')
print('PASS tome_observation_gates: visited masks, refusal/admission, pending/mirror/expiry remain distinct')
