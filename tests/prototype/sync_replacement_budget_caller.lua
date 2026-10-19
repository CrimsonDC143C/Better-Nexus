-- Real TOC, inbound summary, StoreSummary and Session. Only the Session option
-- cap is reduced to eight; synthetic records and no transport/game input.
local T=dofile('tests/prototype/startup_support.lua')
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(1,0)
local old=NexusDB.communityBuilds['synthetic-startup-1']
old.author='Owner-Ebonhold';old.ownerKey='owner@ebonhold';old.ownerVerified=true
local session
for line in io.lines('Nexus.toc') do
    line=line:gsub('\r','')
    if line~='' and not line:match('^#') then
        local path=line:gsub('\\','/')
        assert(loadfile(path))('Nexus',{})
        if path=='core/SyncSession.lua' then
            local factory=Nexus.SyncInternals.Session
            local original=factory.New
            factory.New=function(options)
                options.maxRecoveryQueue=8
                session=original(options)
                return session
            end
        end
    end
end
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function() return Nexus.StartupStatus().state=='ready' end)
T.Until(H,function() return Nexus.BuildCatalog.ManualPreparationStatus().ready end)
local checks=0
local function check(ok,message) checks=checks+1;assert(ok,message) end
for i=1,8 do
    local id='budget-'..i
    check(session.QueueReplacement(id,{buildId=id,lastModified=2,
        fingerprintHash='a1'},'c1-caller'),'fill real Session '..i)
end
local data={id='synthetic-startup-1',t='New owner summary',
    a='Owner-Ebonhold',o='owner@ebonhold',c='MAGE',
    m=time()+1,h='a1',n=79}
local wire='WLBI|Owner-Ebonhold|'..Nexus.Codec.Base64Encode(Nexus.Codec.JSONEncode(data))
local before=Nexus.BuildCatalog.Get(data.id)
check(before and #before.echoes==79,'fixture has last-good complete record')
Nexus.Sync.HandleIncoming(wire,'Owner-Ebonhold')
local found=false
for _,row in ipairs(Nexus.Sync.EventLog()) do
    if row.text:find("REJECT summary 'New owner summary': replacement budget exhausted",1,true) then found=true end
end
check(found,'caller preserves exact replacement-budget refusal reason')
check((Nexus.Sync.Stats().queueOverflowRejected or 0)==0,'not transmit queue overflow')
check(session.WorkSnapshot().replacementBudgetRejected==1,'real Session counts once')
local after=Nexus.BuildCatalog.Get(data.id)
check(after.title==before.title and after.lastModified==before.lastModified
    and T.Equal(after.echoes,before.echoes),'refusal preserves last-good record')

-- Old collaborators that return no second value retain their exact fallback.
session.QueueReplacement=function() return false end
data.t='Fallback summary'
wire='WLBI|Owner-Ebonhold|'..Nexus.Codec.Base64Encode(Nexus.Codec.JSONEncode(data))
Nexus.Sync.HandleIncoming(wire,'Owner-Ebonhold')
found=false
for _,row in ipairs(Nexus.Sync.EventLog()) do
    if row.text:find("REJECT summary 'Fallback summary': recovery queue full",1,true) then found=true end
end
check(found,'nil refusal reason retains existing queue-full fallback')
check(#H.actions==0,'zero gameplay mutation')
print(string.format('PASS sync_replacement_budget_caller: %d checks',checks))
