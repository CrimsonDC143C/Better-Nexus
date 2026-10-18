-- RC-1: actual assignment projection during a held Orb operation, no getter stub.
-- The ordinary assignment and locked-design sidecar are independently valid.
-- Their combined projection must remain displayable and cannot authorize spending.
ORB_SUPPORT_ECHOES={}
for id=500101,500112 do ORB_SUPPORT_ECHOES[#ORB_SUPPORT_ECHOES+1]={id,2} end
local H=dofile('tests/prototype/orbs_support.lua')
local A,M=H.A,H.M
local checks=0
local function check(v,msg) assert(v,msg);checks=checks+1 end
local original={{spellId=410002,quality=2,stacks=3}}
H.OrbPlan(original)
check(M.Start(3),'valid original target starts one synthetic Orb operation')
local before=M.Status()
check(before.pending and before.reserved==1,'submitted operation retains one exposure')
check(H.Count('orb-spend')==1,'exactly one synthetic spend submitted')

-- Both supported authoring inputs fit their separate six-locked-copy bounds.
-- The sidecar names a different permanent target, so projection adds six more.
local changed={{spellId=410002,quality=2,stacks=2}}
local sidecar={}
for id=500101,500106 do changed[#changed+1]={spellId=id,quality=2,stacks=1,locked=true} end
for id=500107,500112 do sidecar[id]=true end
check(A.SetFirstLoadoutWishlistIdentity('Independent locked targets',changed,sidecar),
 'supported assignment writer accepts independently valid plan and sidecar')
local a=A.AssignedWishlist()
check(a.state=='ready','real assignment projection is ready')
local normalized,why=Nexus.OrbPolicy.Normalize(a.entries)
check(not normalized and why:find('6 locked',1,true),'combined ready projection fails Orb normalization')

local actions=#H.actions
local serialize=dofile('tests/prototype/format5_support.lua').Serialize
local receipt=serialize(Nexus.Store.State().orbRefinement.pending)
local ok,status=pcall(M.Status)
check(ok,'Status must not throw when the changed ready assignment is invalid: '..tostring(status))
check(status.pending and status.reserved==1 and status.limit==3,
 'Status preserves the original pending receipt and spending exposure')
check(status.error and status.error:find('6 locked',1,true),
 'invalid projected targets have an actionable display reason')
check(status.progress==nil and not status.canStart and not status.canResume,
 'invalid current target withholds progress and new actions')
check(#H.actions==actions,'display read sends no synthetic gameplay action')
check(serialize(Nexus.Store.State().orbRefinement.pending)==receipt,
 'failed display normalization leaves the durable pending receipt exact')
check(pcall(Nexus.OrbPanel.Show),'the real full Orb panel opens for the held run')
check(NexusOrbPanel.stop:IsEnabled(),'full-window Stop remains available')
NexusOrbPanel.stop:Click()
local stopped=M.Status()
check(stopped.pending and not stopped.running and stopped.reserved==1,
 'Stop remains available and preserves unresolved exposure')
check(H.Count('orb-spend')==1,'Stop and all display reads submit no additional spend')
check(A.SetFirstLoadoutWishlistIdentity('Restored valid target',original),
 'ordinary supported writer restores a valid current plan')
local restored=M.Status()
check(restored.progress and restored.progress.rolledMissing==3 and not restored.canStart,
 'valid-target progress recovers without releasing pending exposure')
print('PASS orb_assignment_invalid_status checks='..checks)
