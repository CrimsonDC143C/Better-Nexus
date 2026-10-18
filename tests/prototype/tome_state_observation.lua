-- The UI observation reads every member without using pool-math projection.
-- Refused/malformed reads, partial and mixed levers cannot become enabled.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local H=dofile('tests/prototype/harness.lua')
for i,name in ipairs({'Alpha Echo','Alpha Echo','Beta Echo','Gamma Echo','Delta Echo','Nameless Echo'})do
 H.AddEcho(300000+i,name,1,1,0)
 H.db[300000+i].requiredSpell=i<=2 and 777001 or 777000+i
 H.discovered[300000+i]=true
end
H.names[777001]='Tome of Alpha Echo';H.names[777003]='Tome of Beta Echo'
H.names[777004]='Tome of Gamma Echo';H.names[777005]='Tome of Delta Echo'
H.perks.discoveredEchoes=H.discovered;H.Boot()
local A=Nexus.GameAdapter
check(type(A.TomeStateObservation)=='function','read-only tome state observation exists')
local function row(obs,id)for _,r in ipairs(obs.rows)do if r.lever==id then return r end end;error('missing lever '..id)end
local function read()return A.TomeStateObservation()end
local obs=read()
check(#obs.rows==5,'all catalog tome gates are listed, including nonconformant/unnamed')
check(obs.serverFreshness=='unverified','mirror readings do not prove fresh server state')
check(row(obs,777001).observed=='enabled','all explicit false answers are enabled in the mirror')
check(row(obs,777006).name:find('name unavailable',1,true)
 and not row(obs,777006).name:find('777006',1,true),'missing tome name is honest; raw control ID stays out of the label')
check(table.concat(row(obs,777006).echoNames,','):find('Nameless Echo',1,true),'fallback retains readable member names')
H.disabled[300001]=true
check(row(read(),777001).observed=='mixed','mixed true/false members are not collapsed into disabled')
H.disabled[300002]=true
check(row(read(),777001).observed=='disabled','all true members are observed disabled')
-- Icons are the client's GetSpellInfo textures, the read the Journal's family
-- rows already use; the harness answers spell names only.
local infoRead=GetSpellInfo
check(row(read(),777001).icon==nil and row(read(),777001).iconSource==nil,'without a client icon no source is claimed')
GetSpellInfo=function(id)local name=infoRead(id);if name and (tonumber(id) or 0)<777000 then return name,'','member-icon' end;return name end
local fallback=row(read(),777001)
check(fallback.icon=='member-icon' and fallback.iconSource=='representative Echo spell','member icon fallback has explicit provenance')
GetSpellInfo=function(id)local name=infoRead(id);if name then return name,'',(tonumber(id) or 0)>=777000 and 'tome-icon' or 'member-icon' end end
check(row(read(),777001).icon=='tome-icon' and row(read(),777001).iconSource=='tome spell','the tome spell icon is preferred')
GetSpellInfo=infoRead
local raw=H.service.IsTomeEchoDisabled
H.service.IsTomeEchoDisabled=function(id)if id==300002 then return nil end;return raw(id)end
check(row(read(),777001).observed=='unknown','true plus nil is incomplete, not fully disabled')
H.service.IsTomeEchoDisabled=function(id)if id==300002 then error('synthetic refusal')end;return raw(id)end
check(row(read(),777001).observed=='unknown','true plus error remains unknown')
H.service.IsTomeEchoDisabled=function()return 0 end
check(row(read(),777003).observed=='unknown','nonboolean false-like answer is not enabled')
H.service.IsTomeEchoDisabled=nil
check(row(read(),777003).observed=='unknown','missing API is unknown')
H.service.IsTomeEchoDisabled=raw
local owner=Nexus.MainInternals.StoreAuthorityOwner
owner.UpdateStateV1(function(st)
 st.tomeTogglePending[777001]={t=GetTime(),want=false}
 st.tomeTogglePending[777003]=GetTime()
 st.tomeTogglePending[777004]={t=GetTime(),want='invalid'}
end)
obs=read()
check(row(obs,777001).pending=='enable' and row(obs,777001).observed=='disabled','pending enable does not overwrite observed disabled')
check(row(obs,777003).pending=='disable' and row(obs,777003).observed=='enabled','legacy pending disable does not overwrite observed enabled')
check(row(obs,777004).pending=='unknown','malformed pending direction is not guessed')
obs.rows[1].name='changed by reader';row(obs,777001).pending='changed'
check(row(read(),777001).pending=='enable','returned data cannot mutate the pending source')
H.perks.discoveredEchoes=nil
check(read().stale==true,'unsynced discovery explicitly marks stale/unverified state')
H.perks.discoveredEchoes=H.discovered
H.Notify()
check(read().stale==true,'unreconciled notification explicitly marks stale state')
H.Advance(.3,.05)
local realName=UnitName;UnitName=function()return 'Unknown' end
check(read().stale==true and row(read(),777003).observed=='unknown','not-ready character cannot produce an enabled observation')
UnitName=realName
local database=ProjectEbonhold.PerkDatabase
ProjectEbonhold.PerkDatabase=false
local retained=read()
check(retained.stale==true and #retained.rows==5
 and table.concat(retained.reasons,';'):find('catalog may be stale',1,true),'retained catalog after source failure is explicitly stale')
ProjectEbonhold.PerkDatabase=database
check(#read().rows==5,'catalog observations recover after the source returns')
local writes=0;local update=owner.UpdateStateV1;owner.UpdateStateV1=function(...)writes=writes+1;return update(...)end
local before=#H.actions;read();read()
check(writes==0 and #H.actions==before,'observation reads never write durable state or send actions')
print('PASS tome observation inventory, strict member states and pending isolation checks='..checks)
