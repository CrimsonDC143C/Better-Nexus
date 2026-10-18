-- Evidence-pending Wishlists chosen while a native Wishlist is active
-- (review 07 R1, R2). Test-only reproduction; nothing here is a fix.
--
-- A Wishlist that needs locked targets (85 copies, no lock roles) is chosen in
-- the real Echo Journal picker. The click goes through
-- WishlistEditor.ResolveAndAssignWishlist to the role picker dialog
-- (RolePicker.Begin / Accept), and only after that to an association writer.
--   R1: RolePicker.Accept compares the raw native active slot with the slot
--       captured at Begin. Since the selection fix the Journal captures the
--       Nexus selection (kept Saved Build 1, or 0), so while native Wishlist
--       101 is active the two never match and the commit is refused with
--       "The active loadout changed", every time.
--   R2: the editor's candidate buttons pass the raw native slot (101). They are
--       observed through the real editor refresh and clicked only if a player
--       could click them (visible). An unreachable button is reported as a
--       ROUTE observation, never as a pass or a failure.
--
-- Groups: BEHAVIOR (what the player asked for: kept Saved Build 1 is the
-- target despite native 101; with nothing selected and a known native read,
-- the existing first-run behaviour), GUARD (refusals that must stay: the
-- selection changed after Begin, the Wishlist's locked evidence changed, the
-- native read became unknown), CONTROL (positive routes at native Saved Build 1
-- and native 0, the target the row names, captured ownership, native facts,
-- Cancel), DATA (nothing under a Wishlist index, other Saved Builds, the legacy
-- record and server rows unchanged). STAGE = a precondition or route step was
-- not reached (setup), never a behaviour result. ROUTE = reachability only.
--
-- Production, harness and format5 are loaded from the cwd, so this file runs
-- unchanged against any source cut; the unchanged transition support is read
-- from this file's own directory. Synthetic data only; nothing native or saved.
local here=(arg and arg[0] or ''):match('^(.*[/\\])') or 'tests/prototype/'
local S=dofile(here..'saved_build_wishlist_transition_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local realPrint=print
local results,routes={},{}
local function record(group,id,ok,message)
 results[#results+1]={group=group,id=id,ok=ok==true}
 realPrint((ok==true and 'OK   ' or 'MISS ')..group..' '..id..': '..tostring(message))
end
local function observe(id,message) realPrint('OBSERVE '..id..': '..tostring(message)) end
local function route(id,reached,message)
 routes[#routes+1]=id..'='..(reached and 'REACHED' or 'UNREACHED')
 realPrint('ROUTE '..(reached and 'REACHED ' or 'UNREACHED ')..id..': '..tostring(message))
end
local function stage(name,fn)
 local ok,err=pcall(fn)
 if not ok then record('STAGE',name,false,'did not complete: '..tostring(err)) end
end

local MAX=5
local BUILD_A,BUILD_B,BUILD_C='Saved Build A','Saved Build B','Saved Build C'
local EVIDENCE,PLAN_S,PLAN_T,LEGACY='Synthetic Evidence Plan','Synthetic Plan S','Synthetic Plan T','Synthetic Legacy Plan'
local EVIDENCE_SLOT,S_SLOT,T_SLOT,LEGACY_INDEX=101,102,103,107
local CHANGED='The active loadout changed'
-- Harness catalog: 200000+i has quality i%4.
local function EvidenceEchoes(lockedFrom)
 local rows={}
 for i=1,85 do
  local locked=lockedFrom~=nil and i>=lockedFrom and i<lockedFrom+6
  rows[#rows+1]={spellId=200000+i,quality=i%4,stacks=1,locked=locked}
 end
 return rows
end
local LOCKS={}
for i=80,85 do LOCKS[#LOCKS+1]={spellId=200000+i,stack=1} end
local function Rows()
 return {
  [1]={name=BUILD_A,verified=true,echoes={{spellId=200086,quality=2,stacks=1}}},
  [2]={name=BUILD_B,verified=true,echoes={{spellId=200087,quality=3,stacks=1}}},
  [3]={name=BUILD_C,verified=true,echoes={{spellId=200088,quality=0,stacks=1}}},
  [EVIDENCE_SLOT]={name=EVIDENCE,verified=false,echoes=EvidenceEchoes()},
  [S_SLOT]={name=PLAN_S,verified=false,echoes={{spellId=200089,quality=1,stacks=1},{spellId=200090,quality=2,stacks=1}}},
  [T_SLOT]={name=PLAN_T,verified=false,echoes={{spellId=200001,quality=1,stacks=1},{spellId=200002,quality=2,stacks=1}}},
 }
end
local SAVED={'loadoutWishlists','firstRunWishlist','forgottenWishlists','forgottenWishlist',
 'lockDesignTargetsBySlot','wishlistRoleChoices'}
local function Saved()
 local st=Nexus.Store.State() or {}
 local out={}
 for _,k in ipairs(SAVED) do out[#out+1]=k..'='..F.Serialize(st[k]) end
 return table.concat(out,'\n')
end
local WATCH={'ConfirmWishlistRoles','SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity',
 'SetFirstLoadoutWishlistIdentity','UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist',
 'ClearFirstRunWishlist','Activate'}
local function Arg(v)
 if type(v)=='number' then return tostring(v) end
 return type(v)=='table' and 'table' or tostring(v)
end
local function Calls(calls)
 local out={}
 for _,c in ipairs(calls) do
  out[#out+1]=c.fn..'('..Arg(c.args[1])..')->'..(c.ret and (Arg(c.ret[1])..','..Arg(c.ret[2])) or 'raised')
 end
 return #out>0 and table.concat(out,'; ') or 'none'
end

-- A fresh boot of the real TOC: level 1, three Saved Builds, the evidence
-- Wishlist at 101, plans S and T at 102/103, six current locks (200080-85).
local function Boot(active,db)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil;NexusWishlistOnlyPicker=nil;NexusEditorFrame=nil
 NexusLoadoutAssociationPanel=nil;NexusActiveWishlistSelector=nil
 NexusWishlistRolePicker=nil;NexusWishlistRoleConfirm=nil
 NexusWishlistRoleUseOwned=nil;NexusWishlistRoleCancel=nil
 local H=dofile('tests/prototype/harness.lua')
 local create=CreateFrame
 CreateFrame=function(kind,name,parent,template)
  local f=create(kind,name,parent,template)
  if template=='UIPanelCloseButton' then
   f._testTemplateClose=true
   f:SetScript('OnClick',function(self)self:GetParent():Hide()end)
  end
  return f
 end
 H.playerLevel=1
 H.locked=H.Clone(LOCKS)
 H.perks.serverActiveSlot=active
 H.perks.serverBuildSlots=Rows()
 NexusDB=db
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,
  GetCharges=function()return 0 end,IsOfferPending=function()return false end,
  RequestCharges=function()end,
  ConfirmSpend=function()error('a role confirmation must not spend')end}
 H.Boot()
 for _=1,2000 do
  local status=Nexus.StartupStatus and Nexus.StartupStatus()
  if not status or status.state~='pending' then break end
  H.Advance(.05,.05)
 end
 local W={H=H,A=Nexus.GameAdapter,tip={}}
 function GameTooltip:SetOwner(owner) self.owner=owner;W.tip={} end
 function GameTooltip:ClearLines() W.tip={} end
 function GameTooltip:AddLine(text) W.tip[#W.tip+1]=tostring(text) end
 S.Refresh(W)
 assert(Nexus.StartupStatus().coreReady==true,'SETUP: start-up completed')
 return W
end

-- Saved Build A holds plan S, B holds plan T, and a legacy association is
-- stored under Wishlist index 107 (older builds could persist one). Native 1.
local function Seed()
 local W=Boot(1,nil)
 local ok,why=W.A.SetLoadoutWishlist(1,S_SLOT,nil)
 assert(ok==true,'SETUP: Saved Build A holds plan S: '..tostring(why))
 ok,why=W.A.SetLoadoutWishlist(2,T_SLOT,nil)
 assert(ok==true,'SETUP: Saved Build B holds plan T: '..tostring(why))
 assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(state)
  local echoes={{spellId=200003,quality=3,stacks=1,locked=false}}
  state.loadoutWishlists=state.loadoutWishlists or {}
  state.loadoutWishlists[LEGACY_INDEX]={slot=LEGACY_INDEX,name=LEGACY,key=W.A.WishlistKey(echoes),echoes=echoes}
 end),'SETUP: the legacy association is written through the store owner')
 local st=Nexus.Store.State()
 assert(st.firstRunWishlist==nil and type(st.loadoutWishlists[LEGACY_INDEX])=='table',
  'SETUP: no first-run plan; the legacy association under 107 is stored')
 return W
end
local function Manual(manual)
 if not manual then return end
 Nexus.Store.Settings().useCurrentLocksForUntagged=false
 assert(Nexus.Store.Settings().useCurrentLocksForUntagged==false,'SETUP: manual role mode (no automatic current-lock use) is set')
end
-- Native Saved Build 1 active (the designed in-range case).
local function NativeWorld(manual)
 local W=Seed()
 Manual(manual)
 local label=S.OpenJournal()
 assert(label:find(BUILD_A,1,true),'SETUP: native Saved Build A is active and named: "'..label..'"')
 return W
end
-- Saved Build 1 observed natively, then native Wishlist 101 active: kept.
local function KeptWorld(manual)
 local W=Seed()
 W.H.perks.serverActiveSlot=EVIDENCE_SLOT
 S.Refresh(W)
 Manual(manual)
 local label=S.OpenJournal()
 assert(label:find(BUILD_A,1,true),'SETUP (precondition): the Journal names the kept Saved Build A while native '
  ..'Wishlist 101 is active (no kept selection exists before the first selection fix): "'..label..'"')
 return W
end
-- The same saved data, booted at `active` (101 or 0): nothing observed.
local function ColdWorld(manual,active)
 local seed=Seed()
 local W=Boot(active or EVIDENCE_SLOT,seed.H.Clone(NexusDB))
 Manual(manual)
 local label=S.OpenJournal()
 assert(label:find('No Saved Build',1,true),'SETUP: after a cold boot at native '..tostring(active or EVIDENCE_SLOT)
  ..' nothing is selected: "'..label..'"')
 return W
end

local function Selected(W)
 if not W.A.SelectedSavedBuild then return 'n/a' end
 return tostring((W.A.SelectedSavedBuild()))
end
local function Native(W)
 local s=W.A.Slots()
 return tostring(s and s.activeSlot)..((s and s.activeKnown==false) and '(unknown)' or '')
end
local function SetNative(W,active)
 W.H.perks.serverActiveSlot=active
 S.Refresh(W)
end
local function RolePickerTable()
 local open=Nexus.WishlistEditor.OpenForWishlist
 for i=1,255 do
  local name,value=debug.getupvalue(open,i)
  if not name then break end
  if name=='RolePicker' then return value end
 end
end
local function Dialog()
 local f=NexusWishlistRolePicker
 if not f then return false,'' end
 return f:IsShown() and true or false,(f.message and S.Plain(f.message:GetText())) or ''
end
local function Bound()
 local ctx,create=S.EditorContext()
 return tonumber(ctx.loadoutSlot or create.loadoutSlot)
end

-- The real route: Journal selector, the evidence-pending row (its tooltip
-- names the target), its click; call-through spies record what the Journal
-- captured, that the role picker began, and every writer call and answer.
local function Begin(W)
 local r={messages={},heard={}}
 r.before,r.saved=S.Destinations(),Saved()
 r.server,r.writes=S.ServerSavedBuilds(W),S.Writes(W)
 local picker=S.OpenPicker()
 assert(picker,'SETUP (route): the real Journal selector opens its picker')
 local row=S.PickerRow(EVIDENCE)
 assert(row,'SETUP (route): the Journal picker lists '..EVIDENCE..': '..S.PickerNames())
 local text=S.Plain(row.nameButton.text:GetText())
 assert(text:find('use current locks',1,true) or text:find('choose locked targets',1,true),
  'SETUP (route): the row is offered as needing locked targets (evidence-pending): "'..text..'"')
 for _,line in ipairs(S.Hover(W,row.nameButton)) do
  local named=S.Plain(line):match('^Target: (.*)$')
  if named then r.target=named end
 end
 local RP=RolePickerTable()
 assert(RP and type(RP.Begin)=='function','SETUP: the role picker is reachable for observation')
 local restores={}
 r.calls,restores[1]=S.Spy(W.A,WATCH)
 r.resolve,restores[2]=S.Spy(Nexus.WishlistEditor,{'ResolveAndAssignWishlist'})
 r.begin,restores[3]=S.Spy(RP,{'Begin'})
 r.restore=function() for i=#restores,1,-1 do restores[i]() end end
 local heard,ok,err=S.Heard(W,function() row.nameButton:Click() end)
 for _,l in ipairs(heard) do r.heard[#r.heard+1]=l end
 assert(ok,'SETUP: the row click raised: '..tostring(err))
 assert(r.resolve[1],'SETUP (route): the evidence-pending row did not reach ResolveAndAssignWishlist: '..table.concat(r.heard,' / '))
 r.captured=r.resolve[1].args[2]
 assert(r.begin[1],'SETUP (route): the role picker (RolePicker.Begin) was not reached: '..table.concat(r.heard,' / '))
 local context=r.begin[1].args[2]
 r.beginActive=type(context)=='table' and context.activeSlot or nil
 local shown,msg=Dialog()
 if shown and msg~='' then r.messages[#r.messages+1]=msg end
 return r
end
-- The dialog's real "Suggest matching locked targets" control (manual mode).
local function Suggest(W,r)
 assert((Dialog()) and NexusWishlistRoleUseOwned and NexusWishlistRoleConfirm,
  'SETUP (route): the role picker dialog is open (manual role mode)')
 assert(not NexusWishlistRoleConfirm:IsEnabled(),'SETUP: Confirm starts disabled while 85 copies are rolled')
 NexusWishlistRoleUseOwned:Click()
 local _,msg=Dialog()
 assert(NexusWishlistRoleConfirm:IsEnabled(),
  'SETUP (route): "Suggest matching locked targets" chose six targets and enabled Confirm: '..msg)
end
-- The dialog's real Confirm control, only while a player could press it.
local function Confirm(W,r)
 assert((Dialog()) and NexusWishlistRoleConfirm and NexusWishlistRoleConfirm:IsEnabled(),
  'SETUP (route): the role picker is still open with Confirm enabled when the player confirms')
 local heard,ok,err=S.Heard(W,function() NexusWishlistRoleConfirm:Click() end)
 for _,l in ipairs(heard) do r.heard[#r.heard+1]=l end
 assert(ok,'SETUP: Confirm raised: '..tostring(err))
 local shown,msg=Dialog()
 if shown and msg~='' then r.messages[#r.messages+1]=msg end
end
-- The automatic path: if Begin left the dialog open with Confirm enabled, the
-- player presses Confirm once more (the reported repeat).
local function RepeatIfOpen(W,r)
 local shown=Dialog()
 if shown and NexusWishlistRoleConfirm and NexusWishlistRoleConfirm:IsEnabled() then Confirm(W,r) end
end
local function Finish(W,r)
 r.restore()
 r.after,r.savedAfter=S.Destinations(),Saved()
 r.changed=table.concat(S.Changed(r.before,r.after),',')
 r.shownFinal=(Dialog())
 r.desc=Calls(r.calls)
 return r
end
local function Writers(r)
 local out={}
 for _,c in ipairs(r.calls) do if c.fn~='ConfirmWishlistRoles' then out[#out+1]=c end end
 return out
end
local function Assigned(r,destination)
 for _,c in ipairs(r.calls) do
  local ok=c.ret~=nil and c.ret[1]==true
  if ok and destination=='first' and c.fn=='SetFirstRunWishlist' then return true end
  if ok and destination~='first' and c.fn=='SetLoadoutWishlist' and tonumber(c.args[1])==destination then return true end
 end
 return false
end
local function Said(r,fragment)
 for _,m in ipairs(r.messages) do if m:find(fragment,1,true) then return m end end
 for _,l in ipairs(r.heard) do
  local p=S.Plain(l)
  if p:find(fragment,1,true) then return p end
 end
end
-- A guard refusal: no association writer was called, no saved field (role
-- choices included) changed, and the dialog stays open for the player.
local function Refused(r)
 return #Writers(r)==0 and r.savedAfter==r.saved and r.changed=='' and r.shownFinal==true
end
local function Report(tag,W,r)
 local notices={}
 for _,l in ipairs(r.heard) do notices[#notices+1]=S.Plain(l) end
 observe(tag,'native='..Native(W)..' selected='..Selected(W)..' target="'..tostring(r.target)
  ..'" captured='..tostring(r.captured)..' begin='..tostring(r.beginActive)..' calls='..r.desc
  ..' changed='..(r.changed~='' and r.changed or 'none')..' dialog='..tostring(r.shownFinal)
  ..' messages=['..table.concat(r.messages,' | ')..'] notices=['..table.concat(notices,' | ')..']')
end
local function WishlistIndexWrites(before,after)
 local out={}
 for _,key in ipairs(S.Changed(before,after)) do
  local index=tonumber(key:match('^loadout:(%-?[%d%.]+)$'))
  if index and (index<1 or index>MAX) then out[#out+1]=key end
 end
 return table.concat(out,',')
end
local function DataChecks(W,r,tag)
 local wrote=WishlistIndexWrites(r.before,r.after)
 record('DATA',tag..'-NO-WISHLIST-INDEX-WRITE',wrote=='','nothing is written under a Wishlist index: '..wrote)
 record('DATA',tag..'-OTHER-SAVED-BUILDS',r.after['loadout:2']~=nil and r.after['loadout:2']==r.before['loadout:2']
  and r.after['loadout:3']==r.before['loadout:3'],'Saved Builds B and C keep their associations byte-equal')
 record('DATA',tag..'-LEGACY-RECORD',r.after['loadout:'..LEGACY_INDEX]~=nil
  and r.after['loadout:'..LEGACY_INDEX]==r.before['loadout:'..LEGACY_INDEX],'the legacy association under 107 is kept byte-equal')
 record('DATA',tag..'-SERVER-ROWS',S.ServerSavedBuilds(W)==r.server and S.Writes(W)==r.writes,
  'server Saved Build rows 1-3 unchanged; nothing uploaded, saved or activated')
end

-- ===================================================================
-- CONTROL P: native Saved Build 1 active. The designed route reaches roles and
-- the assignment. A MISS here makes the R1 results inconclusive.
stage('P-native-saved-build',function()
 local W=NativeWorld(false)
 local r=Begin(W)
 RepeatIfOpen(W,r)
 Finish(W,r)
 Report('P',W,r)
 record('CONTROL','P-TARGET-NAMED',r.target==BUILD_A,'the row names its target: '..tostring(r.target))
 record('CONTROL','P-CAPTURED-SAVED-BUILD-1',tonumber(r.captured)==1 and tonumber(r.beginActive)==1,
  'the Journal captures Saved Build 1 for the role picker: '..tostring(r.captured)..'/'..tostring(r.beginActive))
 record('CONTROL','P-ASSIGNS-SAVED-BUILD-1',Assigned(r,1) and r.changed=='loadout:1' and not r.shownFinal,
  'roles are confirmed and the plan is assigned to Saved Build 1: '..r.desc..' changed '..r.changed)
 record('CONTROL','P-EDITOR-BOUND-1',Bound()==1,'the editor opens bound to Saved Build 1: '..tostring(Bound()))
 DataChecks(W,r,'P')
end)

-- CONTROL P0: native 0 (a genuine first run, known read).
stage('P0-native-first-run',function()
 local W=ColdWorld(false,0)
 local r=Begin(W)
 RepeatIfOpen(W,r)
 Finish(W,r)
 Report('P0',W,r)
 record('CONTROL','P0-TARGET-NAMED',r.target=='No Saved Build selected','the row names its target: '..tostring(r.target))
 record('CONTROL','P0-FIRST-RUN',Assigned(r,'first') and r.changed=='first' and not r.shownFinal,
  'roles are confirmed and the plan becomes the first-run plan: '..r.desc..' changed '..r.changed)
 DataChecks(W,r,'P0')
end)

-- ===================================================================
-- BEHAVIOR R1, kept: Saved Build 1 kept while native Wishlist 101 is active.
stage('R1-kept',function()
 local W=KeptWorld(false)
 local r=Begin(W)
 RepeatIfOpen(W,r)
 Finish(W,r)
 Report('R1-kept',W,r)
 local slots=W.A.Slots()
 local assigned=W.A.AssignedWishlist()
 record('CONTROL','KEPT-TARGET-NAMED',r.target==BUILD_A,'the row names the kept Saved Build A: '..tostring(r.target))
 record('CONTROL','KEPT-CAPTURED-SAVED-BUILD-1',tonumber(r.captured)==1 and tonumber(r.beginActive)==1,
  'the Journal captures kept Saved Build 1: '..tostring(r.captured)..'/'..tostring(r.beginActive))
 record('CONTROL','KEPT-NATIVE-FACT',slots.activeSlot==EVIDENCE_SLOT and assigned.activeSlot==EVIDENCE_SLOT,
  'the native active slot stays 101 in A.Slots() and the assignment: '..tostring(slots.activeSlot)..'/'..tostring(assigned.activeSlot))
 record('BEHAVIOR','R1-KEPT-ASSIGNS-SAVED-BUILD-1',Assigned(r,1) and r.changed=='loadout:1' and not r.shownFinal,
  'roles are confirmed and the plan is assigned to the kept Saved Build 1: '..r.desc..' changed '..(r.changed~='' and r.changed or 'none'))
 record('BEHAVIOR','R1-KEPT-NO-FALSE-CHANGED-REASON',Said(r,CHANGED)==nil,
  'no "active loadout changed" refusal while nothing changed: '..tostring((Said(r,CHANGED))))
 DataChecks(W,r,'R1-KEPT')
end)

-- BEHAVIOR R1, cold: nothing selected, native 101 known and ready.
stage('R1-cold',function()
 local W=ColdWorld(false)
 local r=Begin(W)
 RepeatIfOpen(W,r)
 Finish(W,r)
 Report('R1-cold',W,r)
 local captured=tonumber(r.captured)
 record('CONTROL','COLD-TARGET-NAMED',r.target=='No Saved Build selected','the row names its target: '..tostring(r.target))
 record('BEHAVIOR','R1-COLD-CAPTURED-NOT-WISHLIST-INDEX',captured==nil or captured==0 or (captured>=1 and captured<=MAX),
  'the Journal captures no Wishlist index as the loadout: '..tostring(r.captured))
 record('BEHAVIOR','R1-COLD-FIRST-RUN',Assigned(r,'first') and r.changed=='first' and not r.shownFinal,
  'roles are confirmed and the plan becomes the first-run plan the row names: '..r.desc..' changed '..(r.changed~='' and r.changed or 'none'))
 record('BEHAVIOR','R1-COLD-NO-FALSE-CHANGED-REASON',Said(r,CHANGED)==nil,
  'no "active loadout changed" refusal while nothing changed: '..tostring((Said(r,CHANGED))))
 DataChecks(W,r,'R1-COLD')
end)

-- BEHAVIOR R1, native switch while the dialog is open: begun at native
-- Saved Build 1, native then switches to Wishlist 101 (Saved Build 1 kept).
-- The logical target did not change, so Confirm must not be refused.
stage('R1-switch-after-begin',function()
 local W=NativeWorld(true)
 local r=Begin(W)
 Suggest(W,r)
 SetNative(W,EVIDENCE_SLOT)
 if W.A.SelectedSavedBuild then
  assert(W.A.SelectedSavedBuild()==1,'SETUP (precondition): Saved Build 1 stays selected after the native switch: '..Selected(W))
 end
 Confirm(W,r)
 Finish(W,r)
 Report('R1-switch',W,r)
 record('BEHAVIOR','R1-SWITCH-ASSIGNS-SAVED-BUILD-1',Assigned(r,1) and r.changed=='loadout:1' and not r.shownFinal,
  'the unchanged logical target Saved Build 1 receives the plan: '..r.desc..' changed '..(r.changed~='' and r.changed or 'none'))
 record('BEHAVIOR','R1-SWITCH-NO-FALSE-CHANGED-REASON',Said(r,CHANGED)==nil,
  'no "active loadout changed" refusal for a native Wishlist switch: '..tostring((Said(r,CHANGED))))
 DataChecks(W,r,'R1-SWITCH')
end)

-- ===================================================================
-- GUARD: the logical selection changed after Begin (kept 1 -> native Saved
-- Build 2). Confirm must be refused with no data write.
stage('G-changed-after-begin-kept',function()
 local W=KeptWorld(true)
 local r=Begin(W)
 Suggest(W,r)
 SetNative(W,2)
 assert(W.A.Slots().activeSlot==2,'SETUP: native Saved Build 2 is active: '..Native(W))
 Confirm(W,r)
 Finish(W,r)
 Report('G-changed-kept',W,r)
 record('GUARD','G-CHANGED-AFTER-BEGIN-KEPT',Refused(r),'begun for Saved Build 1, selection now 2: refused, nothing written: '
  ..r.desc..' changed '..(r.changed~='' and r.changed or 'none'))
 DataChecks(W,r,'G-CHANGED-KEPT')
end)

stage('G-changed-after-begin-native',function()
 local W=NativeWorld(true)
 local r=Begin(W)
 Suggest(W,r)
 SetNative(W,2)
 assert(W.A.Slots().activeSlot==2,'SETUP: native Saved Build 2 is active: '..Native(W))
 Confirm(W,r)
 Finish(W,r)
 Report('G-changed-native',W,r)
 record('GUARD','G-CHANGED-AFTER-BEGIN-NATIVE',Refused(r),'begun for native Saved Build 1, now native 2: refused, nothing written: '
  ..r.desc..' changed '..(r.changed~='' and r.changed or 'none'))
 DataChecks(W,r,'G-CHANGED-NATIVE')
end)

-- GUARD: the Wishlist's locked evidence changed while the dialog was open
-- (the server row now carries explicit, different lock roles). The existing
-- ConfirmWishlistRoles refusal ("... reopen ...") must stay; nothing written.
stage('G-evidence-changed',function()
 local W=NativeWorld(true)
 local r=Begin(W)
 Suggest(W,r)
 W.H.perks.serverBuildSlots[EVIDENCE_SLOT]={name=EVIDENCE,verified=false,echoes=EvidenceEchoes(74)}
 S.Refresh(W)
 Confirm(W,r)
 Finish(W,r)
 Report('G-evidence',W,r)
 local confirmed
 for _,c in ipairs(r.calls) do if c.fn=='ConfirmWishlistRoles' then confirmed=c end end
 record('GUARD','G-EVIDENCE-CHANGED-REFUSED',Refused(r) and confirmed~=nil and confirmed.ret~=nil
  and confirmed.ret[1]==nil and Said(r,'reopen')~=nil,
  'the evidence check refuses and nothing is written: '..r.desc..' message '..tostring(Said(r,'reopen')))
 DataChecks(W,r,'G-EVIDENCE')
end)

-- GUARD: the native read becomes unknown (not ready) after Begin.
local function UnknownStage(tag,id,world,description)
 stage(tag,function()
  local W=world()
  local r=Begin(W)
  Suggest(W,r)
  SetNative(W,nil)
  assert(W.A.Slots() and W.A.Slots().activeKnown==false,'SETUP: the native active slot read is unknown: '..Native(W))
  Confirm(W,r)
  Finish(W,r)
  Report(tag,W,r)
  record('GUARD',id,Refused(r),description..': refused, nothing written (no first-run is invented): '
   ..r.desc..' changed '..(r.changed~='' and r.changed or 'none'))
  DataChecks(W,r,id)
  if (Dialog()) and NexusWishlistRoleCancel then
   local saved,dest=Saved(),S.Destinations()
   NexusWishlistRoleCancel:Click()
   record('CONTROL',id..'-CANCEL-NO-WRITE',not (Dialog()) and Saved()==saved and S.Changed(dest,S.Destinations())[1]==nil,
    'Cancel closes the dialog and writes nothing')
  else
   observe(id..'-cancel','Cancel not applicable: the dialog is closed')
  end
 end)
end
UnknownStage('G-unknown-read-saved-build','G-UNKNOWN-READ-SAVED-BUILD',function() return NativeWorld(true) end,
 'begun for native Saved Build 1, native read now unknown')
UnknownStage('G-unknown-read-cold','G-UNKNOWN-READ-COLD',function() return ColdWorld(true) end,
 'begun with nothing selected at native 101, native read now unknown')
UnknownStage('G-unknown-read-first-run','G-UNKNOWN-READ-FIRST-RUN',function() return ColdWorld(true,0) end,
 'begun in a genuine first run (native 0), native read now unknown')

-- ===================================================================
-- ROUTE R2: the editor's candidate buttons in the no-resolved-plan state
-- (cold, native 101, "Restoring assigned Wishlist..."). Observed through the
-- real main entry and refresh; clicked only if visible to a player.
stage('R2-candidate-buttons',function()
 local W=ColdWorld(false)
 local wishlist=W.A.Wishlist()
 assert(wishlist==nil,'SETUP (precondition): no resolved plan in the cold world at 101: '
  ..tostring(wishlist and wishlist.source)..' '..tostring(W.A.WishlistNote()))
 local before,saved=S.Destinations(),Saved()
 Nexus.WishlistEditor.Show()
 assert(NexusEditorFrame and NexusEditorFrame:IsShown(),'SETUP: the main editor entry opens the editor')
 Nexus.WishlistEditor.Refresh()
 local buttons={}
 for _,f in ipairs(NexusEditorFrame.children) do
  local p=f.points and f.points[1]
  if f.kind=='Button' and f.width==115 and f.height==20 and p and p[5]==-112 then buttons[#buttons+1]=f end
 end
 assert(#buttons==4,'SETUP (route): the editor built its four candidate buttons: '..#buttons)
 local named,visible={},{}
 for _,b in ipairs(buttons) do
  local t=S.Plain(b:GetText())
  if t~='' then named[#named+1]=t end
  if b:IsVisible() then visible[#visible+1]=b end
 end
 assert(#named>=1,'SETUP (route): the tracking block filled the candidate buttons (no-resolved-plan state)')
 observe('R2-buttons','note='..tostring(W.A.WishlistNote())..' named=['..table.concat(named,' | ')..'] visible='..#visible)
 if #visible==0 then
  route('R2-CANDIDATE-BUTTON',false,'the tracking block filled '..#named..' candidate button(s), and the same editor refresh '
   ..'hid every one (name-field block); a player cannot click them, so R2 is not exercised')
  record('DATA','R2-OBSERVATION-NO-WRITE',Saved()==saved and S.Changed(before,S.Destinations())[1]==nil,
   'opening and refreshing the editor wrote nothing')
  return
 end
 local target
 for _,b in ipairs(visible) do if S.Plain(b:GetText()):find(EVIDENCE,1,true) then target=b end end
 if not target then
  route('R2-CANDIDATE-BUTTON',false,#visible..' visible button(s), none for the evidence plan')
  return
 end
 route('R2-CANDIDATE-BUTTON',true,'a visible evidence candidate button: '..S.Plain(target:GetText()))
 local r={messages={},heard={},before=before,saved=saved,server=S.ServerSavedBuilds(W),writes=S.Writes(W),
  target='editor candidate button'}
 local restore
 r.calls,restore=S.Spy(W.A,WATCH)
 r.restore=restore
 local heard,okClick,errClick=S.Heard(W,function() target:Click() end)
 for _,l in ipairs(heard) do r.heard[#r.heard+1]=l end
 assert(okClick,'SETUP: the candidate button click raised: '..tostring(errClick))
 RepeatIfOpen(W,r)
 Finish(W,r)
 Report('R2',W,r)
 local bad={}
 for _,c in ipairs(r.calls) do
  local slot=tonumber(c.args[1])
  if c.fn=='SetLoadoutWishlist' and (not slot or slot<1 or slot>MAX) then bad[#bad+1]=c end
 end
 record('BEHAVIOR','R2-NO-WISHLIST-INDEX-TARGET',#bad==0,'no Wishlist index is addressed as a Saved Build: '..Calls(bad))
 record('BEHAVIOR','R2-COLD-FIRST-RUN',Assigned(r,'first') and r.changed=='first',
  'with nothing selected the plan becomes the first-run plan: '..r.desc..' changed '..(r.changed~='' and r.changed or 'none'))
 DataChecks(W,r,'R2')
end)

local missed,byGroup,summary={},{},{}
for _,r in ipairs(results) do
 local g=byGroup[r.group] or {ok=0,miss=0};byGroup[r.group]=g
 if r.ok then g.ok=g.ok+1 else g.miss=g.miss+1;missed[#missed+1]=r.group..':'..r.id end
end
for _,name in ipairs({'BEHAVIOR','GUARD','DATA','CONTROL','STAGE'}) do
 local g=byGroup[name]
 if g then summary[#summary+1]=name..' ok='..g.ok..' miss='..g.miss end
end
local routeText=#routes>0 and table.concat(routes,',') or 'none'
realPrint('SUMMARY '..table.concat(summary,'; ')..'; ROUTE '..routeText)
if #missed>0 then
 error('FAIL saved_build_wishlist_evidence_picker: '..#missed..' expectation(s) not met: '
  ..table.concat(missed,', ')..' (ROUTE '..routeText..')',0)
end
realPrint('PASS saved_build_wishlist_evidence_picker: evidence-pending choices follow the Nexus selection; guards '
 ..'refuse without writes; ROUTE '..routeText..' (an UNREACHED route is neither a pass nor a failure); checks='..#results)
