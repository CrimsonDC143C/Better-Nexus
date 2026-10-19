-- NX-01 lifecycle controls for the scheduled Echo-catalog check (stutter
-- review, 2026-10-14). Companion of stutter_catalog_budget.lua: that test
-- bounds the per-frame work of the scheduled check; this one holds the
-- behaviour a fix must keep. It passes on the delivered build
-- test.2026101502-3d52b0ed7044 with the NX-03/NX-02 fixes and must still pass
-- after the NX-01 fix.
--
-- Required, through the real boot, the real scheduler frame (harness clock)
-- and public GameAdapter reads, with foreign inputs only (PerkDatabase rows
-- and reference, GetSpellInfo answers, UnitClass):
--  E1/E2 explicit CheckCatalogSource results and strings for class loss and a
--        failing source read; the published catalog is kept.
--  W1-W3 the scheduled check is the retry for spell names that the client
--        answers late (Echo name, tome name and lever conformance, CONTRACTS.md
--        "Tome of <member name>" rule) and for a changed name.
--  E3    an explicit check during a pending scheduled pass publishes at once,
--        and no pending pass publishes an older view after it.
--  W4    an unchanged source is verified, not rebuilt.
--  W5    a source that changes in every frame is never published torn.
--  W6    family drift blocks the whole candidate: a non-family edit made with
--        it is not accepted until the drift is gone.
--  W7/W8 a failing materialization and source loss keep the published catalog.
--  W9    a reference swap is seen at once by the ordinary read, also while a
--        scheduled pass is pending.
--  U     the unknown-Echo family fallback.
-- Each scheduled detection must come within ALLOW = 40 s: the 30 s cadence
-- plus 10 s for a sliced pass. Expected values are literals worked from the
-- fixture rows and the contract rules; no production helper is an oracle.
-- Spell icons are not catalog data (read fresh from GetSpellInfo by each view);
-- the tome_state_* tests hold them.
local T=dofile('tests/prototype/startup_support.lua')
T.SingleSlicePacing()
local H=dofile('tests/prototype/harness.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

local FIRST=610001
for i=1,1200 do H.AddEcho(FIRST-1+i,'Nx01Filler Echo '..i,i%4,3) end
-- An Echo whose spell name and tome name the client does not answer yet.
H.AddEcho(620001,'Placeholder One',2,4)
H.names[620001]=nil
H.db[620001].requiredSpell=620900
-- The highest spell ID: a pass in ascending order reaches it last.
H.AddEcho(629999,'Nx01 Sentinel High',1,5)
local TRANSIENT={comment='Nx01 Transient - Uncommon',quality=1,classMask=1535,maxStack=2,minLevel=1,
 groupId=0,requiredSpell=0,families={}}
H.names[629998]='Nx01 Transient'
local BASE=90+1200+2

H.Boot()
local A=Nexus.GameAdapter
for _=1,2000 do if A.CatalogStatus().scheduled==true then break end;H.Advance(.05,.05) end
check(A.CatalogStatus().scheduled==true,'SETUP: the catalog source check is scheduled')
local DB=ProjectEbonhold.PerkDatabase
check(DB==H.db,'SETUP: the harness PerkDatabase is the source')

local function Rows(c) local n=0;for _ in pairs(c.rows) do n=n+1 end;return n end
local c=A.Catalog()
check(type(c)=='table' and Rows(c)==BASE,'SETUP: the boot catalog has '..BASE..' rows: '..tostring(type(c)=='table' and Rows(c)))
check(c.rows[620001].name=='Placeholder One' and c.familyName.s620001=='Placeholder One',
 'SETUP: an unanswered Echo name falls back to the comment: '..tostring(c.rows[620001].name))
local lever=c.levers[620900]
check(type(lever)=='table' and lever.tomeName==nil and lever.conformant==false and #lever.members==1 and lever.members[1]==620001,
 'SETUP: an unanswered tome name leaves the lever non-conformant')
check(c.rows[629999].maxStack==5 and c.rows[610005].name=='Nx01Filler Echo 5' and c.rows[629998]==nil,
 'SETUP: literal rows')

local STEP,ALLOW=.1,40
local function Frame() H.Advance(STEP,STEP) end
local latency={}
local function Within(label,seconds,done,each)
 local start=H.now
 for i=1,math.floor(seconds/STEP+.5) do
  Frame()
  if each then each(i) end
  if done() then latency[#latency+1]=label..'='..string.format('%.1f',H.now-start);return H.now-start end
 end
 check(false,label..': not seen within '..seconds..' s of frames')
end
local function Hold(seconds,each) for i=1,math.floor(seconds/STEP+.5) do Frame();each(i) end end

-- E1. Class loss: the explicit check waits and keeps the catalog.
local c0=A.Catalog()
local realClass=UnitClass
UnitClass=function() return 'Mage' end
local ok,result,changed=A.CheckCatalogSource()
check(ok==false and result=='waiting-for-class' and changed==false,
 'E1: class loss waits: '..tostring(ok)..' '..tostring(result)..' '..tostring(changed))
check(A.Catalog()==c0,'E1: the published catalog is kept')
UnitClass=realClass
ok,result,changed=A.CheckCatalogSource()
check(ok==true and result=='unchanged' and changed==false and A.Catalog()==c0,
 'E1: class known again: '..tostring(ok)..' '..tostring(result)..' '..tostring(changed))

-- E2. The source read raises: the explicit check reports the text.
ProjectEbonhold.PerkDatabase=nil
setmetatable(ProjectEbonhold,{__index=function(_,key) if key=='PerkDatabase' then error('nx01 capture refused',0) end end})
ok,result,changed=A.CheckCatalogSource()
check(ok==false and result=='nx01 capture refused' and changed==nil,
 'E2: a failing source read: '..tostring(ok)..' '..tostring(result)..' '..tostring(changed))
check(A.Catalog()==c0,'E2: the ordinary read keeps the published catalog')
local st=A.CatalogStatus()
check(st.lastResult=='failed' and st.lastError=='nx01 capture refused',
 'E2: status: '..tostring(st.lastResult)..' '..tostring(st.lastError))
setmetatable(ProjectEbonhold,nil);ProjectEbonhold.PerkDatabase=DB
ok,result,changed=A.CheckCatalogSource()
check(ok==true and result=='unchanged' and changed==false and A.Catalog()==c0 and A.CatalogStatus().lastError==nil,
 'E2: restored: '..tostring(ok)..' '..tostring(result)..' '..tostring(changed))

-- W1. The client answers the Echo name late; the last row changes in place at
-- the same time. One publication carries both.
local before=A.CatalogStatus()
H.names[620001]='Delayed Echo One'
DB[629999].maxStack=8
local function NameSeen(cat) return cat.rows[620001].name=='Delayed Echo One' end
local function EditSeen(cat) return cat.rows[629999].maxStack==8 end
Within('W1',ALLOW,function() local cat=A.Catalog();return NameSeen(cat) and EditSeen(cat) end,function(i)
 local cat=A.Catalog()
 check(NameSeen(cat)==EditSeen(cat),'W1 frame '..i..': the late name and the last-row edit are published together')
end)
c=A.Catalog();st=A.CatalogStatus()
check(st.lastResult=='rebuilt' and st.rebuilds==before.rebuilds+1,
 'W1: one rebuild: '..tostring(st.lastResult)..' '..before.rebuilds..' -> '..st.rebuilds)
check(c.familyName.s620001=='Delayed Echo One' and c.levers[620900].tomeName==nil and c.levers[620900].conformant==false,
 'W1: the family name follows; the tome is still unanswered')

-- W2. The client answers the tome name late: the lever becomes conformant.
before=A.CatalogStatus()
H.names[620900]='Tome of Delayed Echo One'
Within('W2',ALLOW,function() return A.Catalog().levers[620900].conformant==true end,function(i)
 local lv=A.Catalog().levers[620900]
 check((lv.tomeName=='Tome of Delayed Echo One')==(lv.conformant==true),'W2 frame '..i..': tome name and conformance together')
end)
st=A.CatalogStatus()
check(A.Catalog().levers[620900].tomeName=='Tome of Delayed Echo One' and st.lastResult=='rebuilt'
 and st.rebuilds==before.rebuilds+1,'W2: the tome name is published once: '..tostring(st.lastResult))

-- W3. A resolved name changes (current behaviour: the canonical holds it).
H.names[610005]='Nx01 Renamed Echo Five'
Within('W3',ALLOW,function() return A.Catalog().rows[610005].name=='Nx01 Renamed Echo Five' end)
check(A.Catalog().familyName.s610005=='Nx01 Renamed Echo Five' and A.CatalogStatus().lastResult=='rebuilt',
 'W3: the family name follows')
local seenAt=H.now

-- E3. Around the next scheduled due (25..36 s after W3), every frame edits a
-- row in place and checks explicitly. The explicit check publishes at once and
-- no pending scheduled pass publishes an older view after it.
while H.now<seenAt+25-1e-6 do Frame() end
local k=0
while H.now<seenAt+36-1e-6 do
 k=k+1;local value=100+k
 DB[610020].maxStack=value
 ok,result,changed=A.CheckCatalogSource()
 check(ok==true and result=='rebuilt' and changed==true and A.Catalog().rows[610020].maxStack==value,
  'E3 edit '..k..': the explicit check publishes at once: '..tostring(ok)..' '..tostring(result)..' '..tostring(changed))
 Frame()
 check(A.Catalog().rows[610020].maxStack==value,
  'E3 edit '..k..': after a frame the newest value is still published: '..tostring(A.Catalog().rows[610020].maxStack))
end
check(k>=100,'E3: about 110 frames: '..k)

-- W4. An unchanged source is verified, not rebuilt.
local s0=A.CatalogStatus();c0=A.Catalog()
Hold(35,function() end)
local s1=A.CatalogStatus()
check(s1.equivalent>=s0.equivalent+1 and s1.rebuilds==s0.rebuilds and s1.lastResult=='unchanged' and s1.lastError==nil
 and A.Catalog()==c0 and s1.publishedHash==s0.publishedHash,
 'W4: verified unchanged: checks '..s0.equivalent..' -> '..s1.equivalent..' rebuilds '..s0.rebuilds..' -> '..s1.rebuilds
 ..' last='..tostring(s1.lastResult))
check(type(s1.publishedHash)=='string' and #s1.publishedHash==8 and s1.publishedHash:find('^[0-9a-f]+$')~=nil,
 'W4: the published hash keeps its 8 hex digits: '..tostring(s1.publishedHash))

-- W5. The source changes in every frame for 30 s between two complete states.
-- After every frame the published catalog is exactly one complete state.
local LOW,HIGH,TR=200001,629999,629998
local STATES={A={5,8,false},B={6,9,true},F={7,10,true}}
local function SetState(s) DB[LOW].maxStack=s[1];DB[HIGH].maxStack=s[2];DB[TR]=s[3] and TRANSIENT or nil end
local function Published(cat)
 local lo,hi,tr=cat.rows[LOW],cat.rows[HIGH],cat.rows[TR]
 for name,s in pairs(STATES) do
  if lo and hi and lo.maxStack==s[1] and hi.maxStack==s[2] and (tr~=nil)==s[3]
   and (cat.familyOf[TR]=='s629998')==s[3] and (cat.familyMembers.s629998~=nil)==s[3]
   and Rows(cat)==BASE+(s[3] and 1 or 0) then return name end
 end
end
check(Published(A.Catalog())=='A','W5 SETUP: state A is published')
local seen={}
for i=1,300 do
 SetState(i%2==1 and STATES.B or STATES.A)
 Frame()
 local name=Published(A.Catalog())
 check(name=='A' or name=='B','W5 frame '..i..': the published catalog is one complete source state: '..tostring(name))
 seen[name]=true
end
SetState(STATES.F)
Within('W5 final',ALLOW,function() return Published(A.Catalog())=='F' end,function(i)
 check(Published(A.Catalog())~=nil,'W5 final frame '..i..': complete state')
end)

-- W6. In-place family drift with a non-family edit: the whole candidate is
-- blocked; the edit is not accepted while the drift stays.
c0=A.Catalog();before=A.CatalogStatus()
DB[610002].groupId=7777;DB[610003].groupId=7777;DB[610004].maxStack=4
local function Kept()
 local cat=A.Catalog()
 return cat==c0 and cat.rows[610004].maxStack==3 and cat.familyOf[610002]=='s610002' and cat.familyOf[610003]=='s610003'
end
Within('W6 blocked',ALLOW,function() return A.CatalogStatus().lastResult=='family-blocked' end,function(i)
 check(Kept(),'W6 frame '..i..': the published catalog is kept')
end)
st=A.CatalogStatus()
check(st.lastError=='family migration required for spell 610002 (s610002 -> g7777)' and st.familyBlocks>=before.familyBlocks+1
 and st.rebuilds==before.rebuilds and Kept(),'W6: blocked: '..tostring(st.lastError))
Hold(31,function(i) check(Kept(),'W6 hold frame '..i..': the unverified edit is not accepted') end)
st=A.CatalogStatus()
check(st.lastResult=='family-blocked' and st.rebuilds==before.rebuilds,'W6: still blocked after a further check: '..tostring(st.lastResult))
DB[610002].groupId=0;DB[610003].groupId=0
Within('W6 reverted',ALLOW,function() return A.Catalog().rows[610004].maxStack==4 end,function(i)
 local cat=A.Catalog()
 check(cat==c0 or (cat.rows[610004].maxStack==4 and cat.familyOf[610002]=='s610002'),'W6 revert frame '..i..': complete state')
end)
st=A.CatalogStatus();c=A.Catalog()
check(st.lastResult=='rebuilt' and st.rebuilds==before.rebuilds+1 and c.familyOf[610002]=='s610002' and c.familyOf[610003]=='s610003',
 'W6: drift gone, the edit is published once: '..tostring(st.lastResult))

-- W7. A failing materialization (the client answers a number) keeps the catalog.
c0=A.Catalog()
H.names[610006]=610006
Within('W7 failed',ALLOW,function() return A.CatalogStatus().lastResult=='failed' end,function(i)
 check(A.Catalog()==c0,'W7 frame '..i..': the published catalog is kept')
end)
st=A.CatalogStatus()
check(type(st.lastError)=='string' and st.lastError:find('spell-name resolver returned a non-string value',1,true)~=nil
 and A.Catalog()==c0 and c0.rows[610006].name=='Nx01Filler Echo 6','W7: failure text: '..tostring(st.lastError))
H.names[610006]='Nx01Filler Echo 6'
Within('W7 restored',ALLOW,function() return A.CatalogStatus().lastResult=='unchanged' end,function(i)
 check(A.Catalog()==c0,'W7 restore frame '..i..': the published catalog is kept')
end)
check(A.CatalogStatus().lastError==nil and A.Catalog()==c0,'W7: restored is unchanged')

-- W8. Source loss keeps the published catalog through scheduled checks.
c0=A.Catalog();before=A.CatalogStatus()
ProjectEbonhold.PerkDatabase=nil
check(A.Catalog()==c0,'W8: the ordinary read keeps the published catalog')
st=A.CatalogStatus()
check(st.lastResult=='failed' and st.lastError=='Project Ebonhold catalog source unavailable',
 'W8: source loss: '..tostring(st.lastResult)..' '..tostring(st.lastError))
Hold(35,function(i) check(A.Catalog()==c0,'W8 frame '..i..': the published catalog is kept') end)
st=A.CatalogStatus()
check(st.lastResult=='failed' and st.lastError=='Project Ebonhold catalog source unavailable' and st.rebuilds==before.rebuilds,
 'W8: still lost after scheduled checks: '..tostring(st.lastResult))
ProjectEbonhold.PerkDatabase=DB
check(A.Catalog()==c0 and A.CatalogStatus().lastResult=='unchanged','W8: the restored source is unchanged: '..tostring(A.CatalogStatus().lastResult))

-- W9. Reference swaps every 1 s for 40 s: the ordinary read shows the current
-- reference at once and after every frame.
local T2=H.Clone(DB);T2[610010].maxStack=4
local current=DB
local function Want() return current==T2 and 4 or 3 end
for i=1,400 do
 if i%10==1 then
  current=current==DB and T2 or DB;ProjectEbonhold.PerkDatabase=current
  check(A.Catalog().rows[610010].maxStack==Want(),'W9 swap at frame '..i..': the ordinary read uses the new reference at once')
 end
 Frame()
 check(A.Catalog().rows[610010].maxStack==Want(),'W9 frame '..i..': the current reference is published: '..tostring(A.Catalog().rows[610010].maxStack))
end
ProjectEbonhold.PerkDatabase=DB
check(A.Catalog().rows[610010].maxStack==3,'W9: the original reference again')

-- U. The unknown-Echo family fallback.
H.perks.serverBuildSlots={[1]={name='Nx01',verified=true,echoes={
 {spellId=639999,quality=1,stacks=1},{spellId=610001,quality=1,stacks=2}}}}
local slots=A.Slots()
local echoes=slots and slots.bySlot and slots.bySlot[1] and slots.bySlot[1].echoes
check(type(echoes)=='table' and echoes[1].family=='s639999' and echoes[2].family=='s610001',
 'U: unknown Echo s639999 and known s610001')

print('NX01_LIFECYCLE detection_seconds '..table.concat(latency,' '))
print('PASS scheduled Echo catalog lifecycle: late names, explicit and pending checks, unchanged, torn-free, drift, failure, loss, swaps; '..checks..' checks')
