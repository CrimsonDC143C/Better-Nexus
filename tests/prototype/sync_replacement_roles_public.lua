-- Public RequestLockedRoles applicability control; real TOC and real Session.
local T=dofile('tests/prototype/startup_support.lua')
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(1,0)
local seed=NexusDB.communityBuilds['synthetic-startup-1']
seed.author='Owner-Ebonhold';seed.ownerKey='owner@ebonhold';seed.ownerVerified=true
seed.lockedEchoes=nil;seed.lockedComplete=nil;seed.lockedAuthorityProven=nil
local session
for line in io.lines('Nexus.toc') do
 line=line:gsub('\r','')
 if line~='' and not line:match('^#') then
  local path=line:gsub('\\','/')
  assert(loadfile(path))('Nexus',{})
  if path=='core/SyncSession.lua' then
   local F=Nexus.SyncInternals.Session;local new=F.New
   F.New=function(o)session=new(o);return session end
  end
 end
end
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready'end)
T.Until(H,function()return Nexus.BuildCatalog.ManualPreparationStatus().ready end)
local id='synthetic-startup-1'
local row=Nexus.BuildCatalog.Get(id)
assert(row and row.ownerVerified and #row.echoes==79,'genuine synthetic verified remote complete fixture')
assert(Nexus.Sync.IsConnected(),'ordinary channel fixture is connected')
assert(session.QueueReplacement(id,{buildId=id,lastModified=2,fingerprintHash='a'},'c1-public-review'))
session.PumpRecovery(1.5)
assert(session.PendingReplacement(id),'replacement was sent and retained')
local ok,state,why=Nexus.Sync.RequestLockedRoles(id)
print('PUBLIC_RESULT requestAccepted='..tostring(ok)..' state='..tostring(state)..' reason='..tostring(why)
 ..' pendingReplacement='..tostring(session.PendingReplacement(id)~=nil)..' count='..session.WorkSnapshot().pendingReplacements)
assert(session.PendingReplacement(id),'public roles request discarded exact sent replacement identity')
assert(#H.actions==0,'no gameplay mutation')
print('PASS public roles request preserves existing replacement owner')
