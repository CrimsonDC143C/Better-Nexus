-- Fail-capable legacy duplication regression; synthetic genuine module paths.
local F=dofile('tests/prototype/assignment_context_benchmark_support.lua')
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end
for _,branch in ipairs({'legacy','string','discovery','table'}) do
 for _,d in ipairs({0,1,4}) do
  local f=F.New{branch=branch,designs=d,mirrors=6,echoes=12}
  local r0,w0,a0=f.Counts()
  local builds,result=F.CountBuilds(f.Read)
  local r1,w1,a1=f.Counts()
  check(r1-r0==1,branch..' D='..d..': one available slot projection; got '..(r1-r0))
  check(builds==1,branch..' D='..d..': one complete live candidate build; got '..builds)
  check(w1==w0 and a1==a0,'read adds no fixture mutation/action')
  if branch~='discovery' then
   check(result.state=='ready' and result.name=='Live 1','full current assignment')
   check(#result.entries==12 and result.entries[1].stacks==1,'rich entries preserved')
  else
   local retained=0
   for _,row in ipairs(result) do
    if row.assignmentId then
     retained=retained+1
     check(row.stored and row.designTargets~=nil,'retained design present')
     check(row.associationIndex>=2 and row.associationIndex<=5 and row.associationUsable==true,'association stamp')
    end
   end
   check(retained==d,'all distinct retained designs merged')
  end
  local stable=f.H.Clone(result)
  local again=f.Read()
  check(F.Equal(stable,again),'same inputs, same complete output')
  if result.entries then result.entries[1].stacks=99
  elseif result[1] and result[1].echoes then result[1].echoes[1].stacks=99 end
  check(F.Equal(stable,f.Read()),'return mutation cannot contaminate next read')
  check(type(Nexus.Store.State().loadoutWishlists[1])==(branch=='table' and 'table' or branch=='string' and 'string' or 'number'),'no hidden scalar upgrade')
 end
end
local f=F.New{branch='legacy',designs=4,mirrors=4,echoes=8}
local before=f.Read()
f.P.serverBuildSlots[101].name='Fresh name'
check(f.Read().name=='Fresh name','in-place name change fresh without Poll')
f.P.serverBuildSlots[101].echoes[1].stacks=2
check(f.Read().entries[1].stacks==2,'in-place copies change fresh without Poll')
f.P.serverBuildSlots[101]=nil
check(f.Read().state~='ready','missing legacy mirror not replaced by a namesake')
f.P.serverBuildSlots[101]={name='Restored',verified=false,echoes=f.H.Clone(f.plan)}
check(f.Read().state=='ready' and f.Read().name=='Restored','new current mirror is read')
f.P.serverActiveSlot=nil
check(f.Read().state=='restoring','nil active state is unknown')
f.P.serverActiveSlot=0
check(f.Read().state~='ready','zero active state differs from nil and no first plan')
f.P.serverActiveSlot=1
check(f.Read().state=='ready','active restored immediately')
local slots=f.P.serverBuildSlots
f.P.serverBuildSlots=nil
local r0,w0=f.Counts()
check(f.Read().state=='restoring','nil mirror retains existing unavailable path')
local r1,w1=f.Counts()
check(r1-r0<=2 and w1==w0,'nil projection retry/write parity')
f.P.serverBuildSlots=slots
local original=f.A.GetWishlistCandidates
local injectedCalls=0
f.A.GetWishlistCandidates=function() injectedCalls=injectedCalls+1;return {{slot=101,name='Injected',echoes=f.H.Clone(f.plan),key=f.A.WishlistKey(f.plan)}} end
check(f.Read().name=='Injected' and injectedCalls==1,'legacy public facade override remains respected')
f.A.GetWishlistCandidates=original
check(f.Read().name=='Restored','override removed, original fresh path')

-- Both retained designs share the live name/content. Output replacement and
-- association stamps must not become the next design's false live mirror.
local g=F.New{branch='discovery',designs=2,mirrors=3,echoes=8}
check(g.owner.UpdateStateV1(function(state)
 for i=2,3 do state.loadoutWishlists[i].name='Live 1';state.loadoutWishlists[i].futureMeta={nested={value=i}} end
end),'matching design fixture')
local durable=g.H.Clone(NexusDB)
local expected={}
for i=2,3 do expected[Nexus.Store.State().loadoutWishlists[i].assignmentId]=i end
local rows=g.Read();local found=0
for _,row in ipairs(rows) do
 if row.assignmentId and expected[row.assignmentId] then
  found=found+1
  check(row.slot==101 and not row.mirrorUnavailable,'matching design retains exact mirror')
  check(row.associationIndex==expected[row.assignmentId] and row.associationUsable==true,'matching design stamp')
  check(row.designTargets~=nil,'distinct permanent design retained')
 end
end
-- The first design replaces the plain live row. A later distinct design is
-- appended rather than replacing that retained design, even at the same slot.
check(found==2,'both exact same-content designs survive the merge')
check(F.Equal(durable,NexusDB),'reads preserve nested unknown durable metadata')

-- No supplied context: GetLoadoutCandidates must use public discovery and its
-- real maxSlots, never a helper default of five.
local h=F.New{branch='legacy',designs=0,mirrors=3,echoes=8}
h.S.GetServerMaxSlots=function()return 2 end
check(h.owner.UpdateStateV1(function(state)
 state.loadoutWishlists[4]={slot=101,name='Live 1',echoes=h.H.Clone(h.plan),key=h.A.WishlistKey(h.plan)}
end),'unusable retained association fixture')
local loads=h.A.GetLoadoutCandidates()
check(loads[1].wishlist.associationIndex==4 and loads[1].wishlist.associationUsable==false,'nil-context route preserves current maximum')

-- Initial nil, retry nil, then a matching mirror for one retained design.
local n=F.New{branch='discovery',designs=1,mirrors=3,echoes=8}
check(n.owner.UpdateStateV1(function(state)state.loadoutWishlists[2].name='Live 1'end),'nil retry design')
local raw=n.S.GetServerBuildSlots;local calls=0
n.S.GetServerBuildSlots=function()
 calls=calls+1;if calls<3 then return nil end;return raw()
end
local recovered=n.Read()
check(calls==3,'preserved per-design nil retry count')
check(#recovered==1 and recovered[1].slot==101 and not recovered[1].mirrorUnavailable,'later mirror recovers retained design')

-- Direct Wishlist: an available active view, two missing discovery views,
-- then the retained first-run design's matching mirror on the fourth read.
local q=F.New{branch='legacy',designs=1,mirrors=3,echoes=8}
check(q.owner.UpdateStateV1(function(state)
 state.firstRunWishlist=q.H.Clone(state.loadoutWishlists[2]);state.firstRunWishlist.name='Live 1'
 state.loadoutWishlists={[1]=101}
end),'direct Wishlist nil retry')
raw=q.S.GetServerBuildSlots;calls=0
q.S.GetServerBuildSlots=function()
 calls=calls+1;if calls==2 or calls==3 then return nil end;return raw()
end
local current=q.A.Wishlist()
check(calls==4 and current~=nil and current.name=='Live 1','standalone legacy discovery retains fourth read recovery')

local t=F.New{branch='table',designs=1,mirrors=3,echoes=8}
local identity=t.Read().identity
check(t.owner.UpdateStateV1(function(state)
 local saved=state.loadoutWishlists[1]
 saved.name='Changed same identity';saved.echoes[1].stacks=2
 saved.key=t.A.WishlistKey(saved.echoes)
end),'same-ID mutation fixture')
local changed=t.Read()
check(changed.identity==identity and changed.name=='Changed same identity' and changed.entries[1].stacks==2,'same-ID content is fresh on next read')
print('PASS assignment context legacy/full merge/freshness '..checks..' checks')
