-- Real lifecycle JournalData provider and adapter reads, synthetic game only.
-- A disabled required tome is outside plan.disable; a pending request is not
-- proof of completion. Details must describe both independently of the plan.
local checks, failures = 0, {}
local function check(v,m) checks=checks+1;if not v then failures[#failures+1]=m end end
local H=dofile('tests/prototype/harness.lua')
-- The client answers a spell's icon through GetSpellInfo; the harness answers
-- names only, so known spells also get a synthetic texture here.
local realInfo=GetSpellInfo
GetSpellInfo=function(id)local name=realInfo(id);if name then return name,'','Interface\\Icons\\Test_'..tostring(id)end end
local REQUIRED, ENABLE, DISABLE, MISSING = 777001,777002,777003,777004
for i,name in ipairs({'Required Echo','Enable Echo','Disable Echo','Missing Echo'}) do
 H.names[777000+i]='Tome of '..name
 H.AddEcho(300000+i,name,1,1,0);H.db[300000+i].requiredSpell=777000+i
 if i~=4 then H.discovered[300000+i]=true end
end
H.perks.discoveredEchoes=H.discovered
H.disabled[300001]=true;H.disabled[300002]=true
H.Boot()
local A=Nexus.GameAdapter
assert(A.SetFirstLoadoutWishlistIdentity('Required tome',{{spellId=300001,quality=1,stacks=1}}))
local journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
CreateFrame('ScrollFrame','ProjectEbonholdEchoJournalScroll',journal)
CreateFrame('Button','ProjectEbonholdEchoJournalTab1',journal)
local provider;local install=Nexus.JournalTab.TryInstall
Nexus.JournalTab.TryInstall=function(fn,...)provider=fn;return install(fn,...)end
H.Fire('PLAYER_ENTERING_WORLD');H.Advance(1,.05)
Nexus.JournalTab.TryInstall=install
assert(type(provider)=='function','real runtime provider installed')
local owner=Nexus.MainInternals.StoreAuthorityOwner
owner.UpdateStateV1(function(st)
 st.tomeTogglePending[ENABLE]={t=GetTime(),want=false}
 st.tomeTogglePending[DISABLE]={t=GetTime(),want=true}
end)
local writes=0;local update=owner.UpdateStateV1
owner.UpdateStateV1=function(...)writes=writes+1;return update(...)end
local beforeActions=#H.actions
local function section(data,title)
 for _,s in ipairs(data.sections or {})do if s.title==title then return table.concat(s.lines or {},'\n')end end
 return ''
end
local data=provider()
local disabled=section(data,'Disabled tomes (client mirror)')
local pending=section(data,'Tome requests awaiting confirmation')
local unknown=section(data,'Unknown or mixed tome state')
local coverage=section(data,'Tome state coverage')
local disabledRows,pendingRows
for _,s in ipairs(data.sections or {})do
 if s.title=='Disabled tomes (client mirror)' then disabledRows=s.tomeRows end
 if s.title=='Tome requests awaiting confirmation' then pendingRows=s.tomeRows end
end
-- A title beginning "Pending" is the Journal's missing-family list; a second
-- one would turn the Build Progress family summary into unknown.
for _,s in ipairs(data.sections or {})do
 if s.tomeRows then check(s.title:sub(1,7)~='Pending','tome section stays outside the family Pending namespace: '..s.title)end
end
local function entry(rows,name)for _,r in ipairs(rows or {})do if r.name==name then return r end end;return {}end
check(type(disabledRows)=='table' and #disabledRows==2,'real provider supplies structured disabled rows for the icon layout')
check(disabledRows and disabledRows[1].icon~=nil and disabledRows[1].leverId~=nil,'structured rows carry actual icon and tooltip control identity')
check(pendingRows and #pendingRows==2 and pendingRows[1].pending~=nil,'structured pending rows preserve request direction')
check(entry(disabledRows,'Tome of Required Echo').icon=='Interface\\Icons\\Test_'..REQUIRED
 and entry(disabledRows,'Tome of Required Echo').iconSource=='tome spell','the row icon is the tome spell icon the client answers')
check(entry(pendingRows,'Tome of Enable Echo').pending=='enable'
 and tostring(entry(pendingRows,'Tome of Enable Echo').status):find('^Disabled')
 and entry(pendingRows,'Tome of Disable Echo').pending=='disable'
 and tostring(entry(pendingRows,'Tome of Disable Echo').status):find('^Enabled'),
 'a request entry keeps its last observation as status and its direction as pending')
check(disabled:find('Tome of Required Echo',1,true),'disabled Wishlist-required tome must be listed outside plan.disable')
check(disabled:find('Tome of Enable Echo',1,true),'mirror-disabled tome remains listed while enable is pending')
check(not disabled:find('Tome of Disable Echo',1,true),'pending disable is not a mirror-observed disable')
check(pending:find('Tome of Enable Echo: enable requested',1,true),'pending enable direction is visible')
check(pending:find('Tome of Disable Echo: disable requested',1,true),'pending disable direction is visible')
check(pending:find('awaiting confirmation',1,true),'pending requests explicitly await confirmation')
check(unknown:find('Tome of Missing Echo',1,true) and unknown:find('undiscovered',1,true),'undiscovered tome is not presented as enabled')
check(coverage:find('client catalog',1,true) and coverage:find('whole game',1,true),'coverage limits are explicit')
check(coverage:find('freshness',1,true) and coverage:find('unverified',1,true),'observation does not claim fresh server state')
for _,s in ipairs(data.sections or {})do
 if s.title:find('Tome',1,true) or s.title:find('tome',1,true) then
  for _,line in ipairs(s.lines or {})do check(not line:find('(done)',1,true),'tome requests never labelled done: '..line)end
 end
end
check(writes==0 and #H.actions==beforeActions,'reading real JournalData sends no mutation and enters no Store write')
check(Nexus.Store.State().tomeTogglePending[ENABLE].want==false
 and Nexus.Store.State().tomeTogglePending[DISABLE].want==true,'details preserve pending records')

-- No assignment is still an inventory view, including disabled tomes outside
-- any disable plan. Use the real assignment action, not a replaced reader.
assert(A.ClearFirstRunWishlist())
local noWishlist=provider()
check(section(noWishlist,'Disabled tomes (client mirror)'):find('Tome of Required Echo',1,true),'no Wishlist still lists the observed disabled inventory')

-- The runtime's existing world hold is read without advancing or clearing it.
-- It must suppress new per-character tome API reads while loading/settling.
local reads=0;local disabledRead=H.service.IsTomeEchoDisabled
H.service.IsTomeEchoDisabled=function(...)reads=reads+1;return disabledRead(...)end
H.Fire('PLAYER_LEAVING_WORLD');reads=0
local leaving=provider()
check(reads==0 and section(leaving,'Tome state coverage'):find('world transition',1,true),'world leaving returns stale unknown rows without tome API reads')
H.Fire('PLAYER_ENTERING_WORLD');reads=0
local settling=provider()
check(reads==0 and section(settling,'Tome state coverage'):find('settling',1,true),'world settling preserves the existing hold without tome API reads')
H.Advance(3.2,.05);reads=0
local resumed=provider()
check(reads>0 and section(resumed,'Disabled tomes (client mirror)'):find('Tome of Required Echo',1,true),'ordinary detail refresh resumes observation after the existing hold')
assert(#failures==0,table.concat(failures,'\n'))
print('PASS real JournalData tome inventory, pending directions and honest coverage checks='..checks)
