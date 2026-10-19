-- Synthetic fixtures shared by operation-count tests and external matched benchmarks.
-- No player data. Mint retained designs through the existing public assignment API.
local F={}
function F.New(options)
 options=options or {}
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil
 local H=dofile('tests/prototype/harness.lua')
 local P,S=H.perks,H.service
 local mirrors=options.mirrors or 4
 local echoes=options.echoes or 8
 assert(mirrors>=1 and mirrors<=128 and echoes>=1 and echoes<=79)
 P.serverActiveSlot=1
 for slot=1,5 do P.serverBuildSlots[slot]={name='Owned '..slot,verified=true,
  echoes={{spellId=200001,quality=1,stacks=1}}} end
 for i=1,mirrors do
  local rows={}
  for e=1,echoes do rows[e]={spellId=200000+e,quality=e%4,stacks=1,locked=false} end
  P.serverBuildSlots[100+i]={name='Live '..i,verified=false,echoes=rows}
 end
 H.Boot()
 local A=Nexus.GameAdapter
 local owner=Nexus.MainInternals.StoreAuthorityOwner
 local plan={}
 local catalog=A.Catalog()
 for e=1,echoes do plan[e]={spellId=200000+e,quality=catalog.rows[200000+e].quality,stacks=1,locked=false} end
 local records={}
 for i=1,options.designs or 0 do
  local id=200080+(i%4)
  local design={[id]={version=1,copies=1,rows={{spellId=id,
   quality=catalog.rows[id].quality,stacks=1,locked=true,sourceRole='locked'}}}}
  assert(A.SetLoadoutWishlistIdentity(2,'Retained '..i,H.Clone(plan),design))
  records[i]=H.Clone(Nexus.Store.State().loadoutWishlists[2])
 end
 local chosen
 for _,c in ipairs(A.GetWishlistCandidates()) do if c.slot==101 then chosen=c;break end end
 assert(chosen,'valid first mirror')
 assert(A.SetLoadoutWishlist(1,101,chosen))
 local normal=H.Clone(Nexus.Store.State().loadoutWishlists[1])
 assert(owner.UpdateStateV1(function(state)
  state.loadoutWishlists={}
  if options.branch=='table' then state.loadoutWishlists[1]=normal
  elseif options.branch=='string' then state.loadoutWishlists[1]='101'
  else state.loadoutWishlists[1]=101 end
  for i,r in ipairs(records) do state.loadoutWishlists[i+1]=H.Clone(r) end
  state.firstRunWishlist=nil
 end))
 -- No Notify/Poll/lifecycle advancement follows the scalar seed: reconciliation
 -- would upgrade it, turning the intended legacy benchmark into a table case.
 local reads,writes=0,0
 local rawSlots=S.GetServerBuildSlots
 local rawWrite=owner.UpdateStateV1
 if options.track~=false then
  S.GetServerBuildSlots=function(...) reads=reads+1;return rawSlots(...) end
  owner.UpdateStateV1=function(...) writes=writes+1;return rawWrite(...) end
 end
 return {H=H,A=A,P=P,S=S,owner=owner,plan=plan,records=records,normal=normal,
  designs=options.designs or 0,mirrors=mirrors,echoes=echoes,
  Counts=function()return reads,writes,#H.actions end,
  Read=function()
   if options.branch=='discovery' then return A.GetWishlistCandidates() end
   return A.AssignedWishlist()
  end}
end
function F.CountBuilds(callback)
 if jit then jit.off();jit.flush() end
 local defined,line=0,0
 for text in io.lines('core/GameAdapter.lua') do
  line=line+1
  if text:match('^local function LiveWishlistCandidates%(') then defined=line;break end
 end
 assert(defined>0,'real candidate function definition present')
 local n=0
 debug.sethook(function()
  local info=debug.getinfo(2,'S')
  if info and info.linedefined==defined and info.source:find('GameAdapter.lua',1,true) then n=n+1 end
 end,'c')
 local ok,result=pcall(callback)
 debug.sethook()
 if jit then jit.on() end
 assert(ok,result)
 return n,result
end
function F.Equal(a,b,seen)
 if a==b then return true end
 if type(a)~=type(b) or type(a)~='table' then return false end
 seen=seen or {};if seen[a] then return seen[a]==b end;seen[a]=b
 for k,v in pairs(a) do if not F.Equal(v,b[k],seen) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
return F
