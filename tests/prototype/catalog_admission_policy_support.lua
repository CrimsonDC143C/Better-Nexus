-- Synthetic catalog admission fixtures; real TOC, catalog owner and persistence.
local F=dofile('tests/prototype/format5_support.lua')
local T=dofile('tests/prototype/startup_support.lua')
local S={F=F,T=T}
function S.Record(id,extra)
 local r={id=id,title='Synthetic '..tostring(id),author='Owner-Ebonhold',
  ownerKey='owner@ebonhold',class='MAGE',postedAt=1,lastModified=1,
  ordinaryComplete=true,loadoutAvailable=true,lockedEchoes={},lockedComplete=true,
  echoes={{spellId=200001,quality=1,stacks=1}}}
 for k,v in pairs(extra or {}) do r[k]=v end
 return r
end
function S.Boot(count,change)
 local db={settingsVersion=5,accountCharacters={},settings={autoPick=false,
  communityRetentionEnabled=false},chars={},communityBuilds={}}
 for i=1,count or 0 do db.communityBuilds['seed-'..i]=S.Record('seed-'..i) end
 if change then change(db) end
 S.H=F.Boot(db);S.C=Nexus.BuildCatalog
 T.Until(S.H,function()return S.C.ManualPreparationStatus().ready end)
 assert(Nexus.StartupStatus().state=='ready','fixture starts admitted')
 return S.H,S.C
end
function S.Settle(ok,why,ticket)
 if ok==nil and type(ticket)=='table' then
  T.Until(S.H,function()return ticket.state~='pending' end)
  return ticket.committed==true,ticket.reason or why
 end
 return ok,why
end
function S.Put(record,options)
 -- A completed ticket can share its frame with later scheduled maintenance.
 -- Establish the public mutation precondition before this one submission;
 -- never retry a refused put or alter the controlled policy input.
 if not S.C.ManualPreparationStatus().ready then
  T.Until(S.H,function()return S.C.ManualPreparationStatus().ready end)
 end
 return S.Settle(S.C.Put(record,options))
end
function S.Remote(record,sender)
 return S.Put(record,{source='remote',sender=sender or 'Relay-Ebonhold'})
end
function S.Batch(requests)
 if not S.C.ManualPreparationStatus().ready then
  T.Until(S.H,function()return S.C.ManualPreparationStatus().ready end)
 end
 local ok,why,tickets=S.C.PutBatch(requests)
 assert(ok==nil and type(tickets)=='table','batch preparation accepted: '..tostring(why))
 T.Until(S.H,function()
  for _,t in ipairs(tickets) do if t.state=='pending' then return false end end
  return true
 end)
 return tickets
end
function S.Raw(id)return NexusDB.authorityBundle.communityBuilds[id] end
function S.Saved()return F.Serialize(NexusDB.authorityBundle.communityBuilds) end
return S
