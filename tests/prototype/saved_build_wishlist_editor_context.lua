-- The Wishlist Editor's own entry points must follow the Saved Build Nexus
-- selects, and must never address or name a native Wishlist index as a Saved
-- Build (review 03 N1-N3, N5). Companion of saved_build_wishlist_transition.
--
-- The Journal panel already follows GameAdapter.SelectedSavedBuild. Three
-- editor routes still read the native active slot directly:
--   H4 (N1) M.Show: a legacy association stored under Wishlist index 101 that
--      is evidence-pending opens the role picker / editor bound to loadout 101.
--   H5 (N2) Journal 'New Wishlist': the panel names the kept Saved Build, but
--      BeginNewWishlist / FirstRunOwnsSave / SaveDestination send the new
--      plan to the first-run destination.
--   H6 (N3) M.Show -> BeginShow opens a first-run/new draft instead of the kept
--      Saved Build, and the editor's 'Saved Build:' selector names the native
--      Wishlist row 101 as a Saved Build (it falls back to the native active
--      slot when no context is bound).
--
-- Groups: SYMPTOM (the route addresses or names the wrong destination),
-- CONTEXT (presentation of the selection), DATA (stored associations,
-- legacy records and server rows stay byte-equal; nothing is written under a
-- Wishlist index), CONTROL (first-run, cold boot without a selection, explicit
-- Saved Build choice, Unassign/design and FirstRunHandoff behaviour, writer
-- refusals, activation gate). STAGE lines are setup failures, not behaviour.
--
-- Production code is loaded from the cwd (Nexus.toc, harness), so the same
-- file runs against any source cut; only the shared support file is read
-- from this file's directory. Synthetic data only; nothing native or saved.
local here=(arg and arg[0] or ''):match('^(.*[/\\])') or 'tests/prototype/'
local S=dofile(here..'saved_build_wishlist_transition_support.lua')
-- M3: the editor's actions are named by their effect; a legacy label also
-- finds the action with that default intent (new label first, then legacy).
-- As S.Button otherwise.
local ACTION={['Create Wishlist']={'Create & assign','Create unassigned','Create Wishlist'},
 ['Save Wishlist']={'Save & assign','Save changes','Save Wishlist'}}
local function ActionButton(W,text)
 for _,label in ipairs(ACTION[text] or {text}) do
  for _,f in ipairs(W.H.frames) do
   if f.kind=='Button' and f:IsVisible() and f:GetText()==label then return f end
  end
 end
 error('SETUP: visible button absent: '..text)
end
local realPrint=print
local results={}
local function record(group,id,ok,message)
 results[#results+1]={group=group,id=id,ok=ok==true}
 realPrint((ok==true and 'OK   ' or 'MISS ')..group..' '..id..': '..tostring(message))
end
local function observe(id,message) realPrint('OBSERVE '..id..': '..tostring(message)) end
local function stage(name,fn)
 local ok,err=pcall(fn)
 if not ok then record('STAGE',name,false,'did not complete: '..tostring(err)) end
end

local NEW_PLAN='Synthetic New Plan'
local MAX=5

-- Adapter calls without table arguments (stable text across boots).
local function Calls(calls)
 local out={}
 for _,c in ipairs(calls) do
  out[#out+1]=c.fn..'('..tostring(c.args[1])..')->'
   ..(c.ret and (tostring(c.ret[1])..','..tostring(c.ret[2])) or 'raised')
 end
 return #out>0 and table.concat(out,'; ') or 'none'
end
local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity',
 'SetFirstLoadoutWishlistIdentity','UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist',
 'ClearFirstRunWishlist','Activate'}

-- Association destinations whose index is above the declared Saved Builds and
-- that changed (added, removed or rewritten) between two snapshots.
local function WishlistIndexWrites(before,after)
 local out={}
 for _,key in ipairs(S.Changed(before,after)) do
  local index=tonumber(key:match('^loadout:(%-?[%d%.]+)$'))
  if index and (index<1 or index>MAX) then out[#out+1]=key end
 end
 return table.concat(out,',')
end

-- A fresh boot of the real TOC with the given native state and saved data;
-- nothing is observed before it. `synthetic` uses the regression's catalog.
local function Boot(o)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil;NexusWishlistOnlyPicker=nil
 NexusLoadoutAssociationPanel=nil;NexusActiveWishlistSelector=nil
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
 H.playerLevel=o.level or 1
 if o.synthetic then
  wipe(H.db)
  for _,id in ipairs({S.ECHO_1,S.ECHO_2,S.ECHO_3,S.ECHO_4}) do H.AddEcho(id,'Synthetic Echo '..id,0,5) end
  H.AddEcho(S.TOME,'Synthetic Tome Echo',0,1)
  H.db[S.TOME].requiredSpell=S.TOME_LEVER
  H.names[S.TOME_LEVER]='Tome of Synthetic Tome Echo'
 end
 if o.locked then H.locked=H.Clone(o.locked) end
 H.perks.serverActiveSlot=o.active
 H.perks.serverBuildSlots=H.Clone(o.rows)
 NexusDB=o.db
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,
  GetCharges=function()return 0 end,IsOfferPending=function()return false end,
  RequestCharges=function()end,
  ConfirmSpend=function()error('an editor action must not spend')end}
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

-- The regression world with Saved Build A kept while native Wishlist 101 is active.
local function KeptWorld(level)
 local W=S.BindInitial(S.World({level=level or 1}))
 S.NativeTransition(W)
 local label=S.OpenJournal()
 assert(label:find(S.BUILD_A,1,true),'SETUP: the Journal names the kept Saved Build A: "'..label..'"')
 return W,label
end

-- The same saved data, rebooted with native Wishlist 101 already active.
local function ColdWorld(fromW)
 local W=Boot({synthetic=true,active=S.MIRROR_D,
  rows=fromW.H.Clone(fromW.H.perks.serverBuildSlots),db=fromW.H.Clone(NexusDB)})
 local label=S.OpenJournal()
 assert(label:find('No Saved Build',1,true),'SETUP: after a cold boot at 101 nothing is selected: "'..label..'"')
 return W,label
end

local function SelectorButton(W)
 for _,f in ipairs(W.H.frames) do
  if f.kind=='Button' and f:IsVisible() and S.Plain(f:GetText()):find('Saved Build: ',1,true)==1 then return f end
 end
end
local function SelectorRows(W)
 local m=NexusWishlistEditorLoadoutMenu
 if m and m:IsShown() then SelectorButton(W):Click() end
 SelectorButton(W):Click()
 m=NexusWishlistEditorLoadoutMenu
 assert(m and m:IsShown(),'SETUP: the editor Saved Build selector opens')
 local out={}
 for _,r in ipairs(m.rows) do if r:IsVisible() then out[#out+1]=r end end
 return out
end
local function EditorLine()
 for _,f in ipairs(NexusEditorFrame and {NexusEditorFrame} or {}) do
  for _,r in ipairs(f.regions or {}) do
   local t=r.kind=='FontString' and r:IsVisible() and S.Plain(r:GetText()) or ''
   if t:find('destination',1,true) or t:find('Wishlist: ',1,true)==1 then return t end
  end
 end
 return 'n/a'
end
local function Bound()
 local ctx,create=S.EditorContext()
 return tonumber(ctx.loadoutSlot or create.loadoutSlot),ctx,create
end
-- The editor's own close control: the UIPanelCloseButton child, given the
-- template's hide-parent behaviour by the boot's CreateFrame wrapper. While the
-- editor is shown, WishlistEditor's HideServerEchoUI keeps the native Echo
-- Journal hidden (its OnShow hook hides it again), as it does for a player.
-- So the Journal is reopened only after the editor is closed this way.
local function CloseEditor()
 local editor=NexusEditorFrame
 if not (editor and editor:IsShown()) then return end
 for _,f in ipairs(editor.children) do
  if f._testTemplateClose then f:Click();break end
 end
 assert(not editor:IsShown(),'SETUP: the editor\'s close control closes the editor')
end
local function CatalogRow(W,id)
 for _,f in ipairs(W.H.frames) do
  if f.kind=='Button' and f:IsVisible() and f.status and f.data and f.data.spellId==id then return f end
 end
end

-- The real Journal 'New Wishlist' button, one catalog Echo, a name, Create,
-- the confirmation, and the server mirror of the upload. `between` runs after
-- the draft began and before Create.
local function NewPlanFromJournal(W,between)
 S.OpenJournal()
 NexusLoadoutAssociationPanel.newWishlist:Click()
 assert(NexusEditorFrame and NexusEditorFrame:IsShown(),'SETUP: the Journal New Wishlist button opens the editor')
 local _,create=S.EditorContext()
 local begun={create=create.loadoutSlot,line=EditorLine()}
 if between then between() end
 local before,server0=S.Destinations(),S.ServerSavedBuilds(W)
 local calls,restore=S.Spy(W.A,WRITERS)
 local heard,ok,err=S.Heard(W,function()
  local row=assert(CatalogRow(W,S.ECHO_3),'SETUP: the editor lists catalog Echo '..S.ECHO_3)
  row:Click()
  NexusWishlistNameInput:SetText(NEW_PLAN)
  ActionButton(W,'Create Wishlist'):Click()
  assert(W.H.popup and W.H.popup.which=='WISHLISTREALIZER_CREATE_WISHLIST',
   'SETUP: Create asks for confirmation: '..tostring(W.H.popup and W.H.popup.which))
  W.H.AcceptPopup()
  local last=assert(S.Last(W,'upload'),'SETUP: Create uploads')
  S.Mirror(W,last[2],last[3],last[4])
 end)
 restore()
 assert(ok,'SETUP: the new plan was not created: '..tostring(err)..' '..table.concat(heard,' / '))
 local after=S.Destinations()
 return {begun=begun,before=before,after=after,changed=table.concat(S.Changed(before,after),','),
  calls=Calls(calls),heard=S.Plain(table.concat(heard,' / ')),server0=server0}
end

-- ===================================================================
-- H6: the main editor entry while Saved Build A is kept at native 101.
stage('show-kept',function()
 local W=KeptWorld(1)
 local before,server0,writes0=S.Destinations(),S.ServerSavedBuilds(W),S.Writes(W)
 Nexus.WishlistEditor.Show()
 assert(NexusEditorFrame and NexusEditorFrame:IsShown(),'SETUP: the main entry opens the editor')
 local bound,ctx,create=Bound()
 local button=SelectorButton(W)
 local text=button and S.Plain(button:GetText()) or 'absent'
 observe('show-kept','editing='..tostring(ctx.loadoutSlot)..'/'..tostring(ctx.name)..' create='
  ..tostring(create.loadoutSlot)..' selector="'..text..'" line="'..EditorLine()..'"')
 record('SYMPTOM','SHOW-KEPT-BINDING',bound==1,
  'the main editor entry opens the Saved Build the Journal names (Saved Build 1); bound='..tostring(bound))
 record('SYMPTOM','SELECTOR-KEPT-NOT-WISHLIST',button~=nil and not text:find(S.PLAN_D,1,true),
  'the editor\'s Saved Build selector does not name native Wishlist 101 as a Saved Build: "'..text..'"')
 local rows=SelectorRows(W)
 local row1
 for _,r in ipairs(rows) do if S.Plain(r._label:GetText()):find(S.BUILD_A,1,true)==1 then row1=r end end
 assert(row1,'SETUP: the selector lists Saved Build A')
 record('CONTEXT','SELECTOR-HIGHLIGHT-KEPT',row1._label:GetText():sub(1,10)=='|cffffd200',
  'the selector highlights the kept Saved Build A: '..tostring(row1._label:GetText()))
 local listed={}
 for _,r in ipairs(rows) do
  local t=S.Plain(r._label:GetText())
  if t:find(S.PLAN_D,1,true)==1 or t:find(S.TOME_LIST,1,true)==1 then listed[#listed+1]=t end
 end
 record('CONTROL','SELECTOR-NO-WISHLIST-ROWS',#listed==0 and #rows==MAX,
  'the selector lists the '..MAX..' declared Saved Builds and no Wishlist row: '..#rows..' rows '..table.concat(listed,' | '))
 assert(row1.scripts.OnMouseDown,'SETUP: the Saved Build A row is selectable')
 row1.scripts.OnMouseDown(row1,'LeftButton')
 local chosen,ctx2=Bound()
 record('CONTROL','EXPLICIT-ROW-BINDS',chosen==1 and ctx2.name==S.PLAN_D and S.Count(W,'activate')==0,
  'choosing Saved Build A in the selector binds its plan without activation: '..tostring(chosen)..'/'..tostring(ctx2.name))
 record('DATA','SHOW-KEPT-NO-WRITES',S.Changed(before,S.Destinations())[1]==nil
  and S.ServerSavedBuilds(W)==server0 and S.Writes(W)==writes0,
  'opening and choosing write no association, server row or service action')
 local ok1,why1=W.A.SetLoadoutWishlist(S.MIRROR_D,S.MIRROR_S,nil)
 record('CONTROL','WRITER-REFUSES-WISHLIST-INDEX',ok1==false and why1=='invalid loadout',
  'the association writer still refuses 101 as a Saved Build: '..tostring(why1))
end)

-- H6 control: a cold boot at 101 selects nothing; the main entry must not invent one.
stage('show-cold',function()
 local W=ColdWorld(S.BindInitial(S.World({level=1})))
 local before,writes0=S.Destinations(),S.Writes(W)
 Nexus.WishlistEditor.Show()
 assert(NexusEditorFrame and NexusEditorFrame:IsShown(),'SETUP: the main entry opens the editor')
 local bound,ctx,create=Bound()
 local button=SelectorButton(W)
 local text=button and S.Plain(button:GetText()) or 'absent'
 observe('show-cold','editing='..tostring(ctx.loadoutSlot)..' create='..tostring(create.loadoutSlot)
  ..' selector="'..text..'" line="'..EditorLine()..'"')
 record('CONTROL','SHOW-COLD-NO-SELECTION',bound==nil,'no Saved Build is invented after a cold boot at 101; bound='..tostring(bound))
 record('SYMPTOM','SELECTOR-COLD-NOT-WISHLIST',button~=nil and not text:find(S.PLAN_D,1,true),
  'the selector does not name native Wishlist 101 as a Saved Build: "'..text..'"')
 -- The editor's own candidate buttons (Controller.AssociateCandidate) appear
 -- only while nothing is tracked. Their refusal at a Wishlist index is the
 -- existing contract (wishlist_switch_recovery 15); it must stay a refusal.
 local clicked
 for _,f in ipairs(W.H.frames) do
  local t=f.kind=='Button' and f:IsVisible() and S.Plain(f:GetText()) or ''
  if not clicked and t:find(S.PLAN_S,1,true)==1 and f.scripts.OnClick and not f.nameButton then
   local calls,restore=S.Spy(W.A,WRITERS)
   local heard=S.Heard(W,function() f:Click() end)
   restore()
   clicked=Calls(calls)..' '..S.Plain(table.concat(heard,' / '))
  end
 end
 observe('associate-candidate-cold',clicked or 'no editor candidate button visible')
 record('DATA','SHOW-COLD-NO-WISHLIST-INDEX-WRITE',WishlistIndexWrites(before,S.Destinations())=='',
  'nothing is written under a Wishlist index: '..WishlistIndexWrites(before,S.Destinations()))
 record('CONTROL','SHOW-COLD-NO-ACTIVATION',S.Count(W,'activate')==0,'nothing was activated')
end)

-- ===================================================================
-- H5: a new plan from the Journal's own New Wishlist button.
stage('new-plan-kept',function()
 local W,label=KeptWorld(1)
 local r=NewPlanFromJournal(W)
 local a,desc=S.Assigned(W)
 observe('new-plan-kept','label="'..label..'" draft create='..tostring(r.begun.create)..' line="'..r.begun.line
  ..'" calls='..r.calls..' changed='..r.changed..' notice='..r.heard)
 record('SYMPTOM','NEW-PLAN-DESTINATION',r.changed=='loadout:1',
  'the new plan is assigned where the Journal says (Saved Build A = loadout:1); changed: '..r.changed)
 record('SYMPTOM','NEW-PLAN-TARGET',a.name==NEW_PLAN,'the new plan becomes the target of the kept Saved Build: '..desc)
 record('DATA','NEW-PLAN-OTHER-SAVED-BUILD',r.after['loadout:2']==r.before['loadout:2'],'Saved Build B\'s association is byte-equal')
 record('DATA','NEW-PLAN-NO-WISHLIST-INDEX-WRITE',WishlistIndexWrites(r.before,r.after)=='',
  'nothing is written under a Wishlist index')
 record('DATA','NEW-PLAN-SERVER-ROWS',S.ServerSavedBuilds(W)==r.server0 and S.Count(W,'save')==0
  and S.Count(W,'activate')==0,'no Saved Build row was saved or activated')
end)

-- Control: the destination bound when the draft began is not retargeted to a
-- Saved Build that becomes natively active later.
stage('new-plan-no-retarget',function()
 local W=KeptWorld(1)
 local r=NewPlanFromJournal(W,function()
  W.H.perks.serverActiveSlot=2
  S.Refresh(W)
 end)
 observe('new-plan-no-retarget','calls='..r.calls..' changed='..r.changed..' notice='..r.heard)
 record('CONTROL','NEW-PLAN-NOT-RETARGETED',r.after['loadout:2']==r.before['loadout:2']
  and not r.calls:find('Identity(2)',1,true),
  'a later native Saved Build 2 does not receive the plan begun for another target: '..r.calls)
 record('DATA','NO-RETARGET-NO-WISHLIST-INDEX-WRITE',WishlistIndexWrites(r.before,r.after)=='',
  'nothing is written under a Wishlist index')
end)

-- Control: legitimate first-run behaviour when nothing is selected.
stage('new-plan-cold',function()
 local W,label=ColdWorld(S.BindInitial(S.World({level=1})))
 local r=NewPlanFromJournal(W)
 observe('new-plan-cold','label="'..label..'" calls='..r.calls..' changed='..r.changed..' notice='..r.heard)
 record('CONTROL','NEW-PLAN-COLD-FIRST-RUN',r.changed=='first',
  'with no Saved Build selected the new plan is the first-run plan the Journal names: changed '..r.changed)
end)

-- ===================================================================
-- H4: a legacy association stored under Wishlist index 101, evidence-pending
-- (85 copies with no lock roles), as older builds could persist.
local LEGACY='Synthetic Legacy Plan'
local function LegacyRows()
 local total,locks={},{}
 for i=1,85 do total[#total+1]={spellId=200000+i,quality=i%4,stacks=1,locked=false} end
 for i=80,85 do locks[#locks+1]={spellId=200000+i,stack=1} end
 local rows={
  [1]={name=S.BUILD_A,verified=true,echoes={{spellId=200086,quality=2,stacks=1}}},
  [2]={name=S.BUILD_B,verified=true,echoes={{spellId=200087,quality=3,stacks=1}}},
  [101]={name=LEGACY,verified=false,echoes=total},
  [102]={name=S.PLAN_S,verified=false,echoes={{spellId=200088,quality=0,stacks=1},{spellId=200089,quality=1,stacks=1}}},
 }
 return rows,total,locks
end
local function RolePickerState()
 local open=Nexus.WishlistEditor.OpenForWishlist
 for i=1,255 do
  local name,value=debug.getupvalue(open,i)
  if not name then break end
  if name=='RolePicker' then return value and value.state end
 end
end
local function LegacyShow(W,tag)
 local _,status=W.A.GetLoadoutWishlistState(S.MIRROR_D)
 observe(tag..'-evidence','GetLoadoutWishlistState(101)='..tostring(status))
 assert(status=='evidence-pending','SETUP (seam): the legacy record under 101 is evidence-pending: '..tostring(status))
 local before=S.Destinations()
 local heard,okShow,errShow=S.Heard(W,function() Nexus.WishlistEditor.Show() end)
 assert(okShow,'SETUP: the main entry raised: '..tostring(errShow))
 local picker=RolePickerState()
 local edited,ctx,create=Bound()
 local shown=NexusEditorFrame and NexusEditorFrame:IsShown()
 local route=(picker and 'role-picker') or (shown and 'editor') or 'none'
 local bound=edited or (picker and tonumber(picker.loadoutSlot))
 observe(tag,'route='..route..' bound='..tostring(bound)..' picker='..tostring(picker and picker.loadoutSlot)
  ..' editing='..tostring(ctx.loadoutSlot)..' create='..tostring(create.loadoutSlot)
  ..' notice='..S.Plain(table.concat(heard,' / ')))
 assert(route~='none','SETUP (seam): the main entry reached neither the role picker nor the editor')
 return bound,before,S.Destinations()
end

stage('legacy-kept',function()
 local rows,total,locks=LegacyRows()
 local W=Boot({active=1,rows=rows,locked=locks})
 local ok,why=W.A.SetLoadoutWishlist(1,102,nil)
 assert(ok==true,'SETUP: Saved Build A holds plan S: '..tostring(why))
 assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(state)
  state.loadoutWishlists=state.loadoutWishlists or {}
  state.loadoutWishlists[101]={slot=101,name=LEGACY,key=W.A.WishlistKey(total),echoes=W.H.Clone(total)}
 end),'SETUP: the legacy record is written through the store owner')
 W.H.perks.serverActiveSlot=S.MIRROR_D
 S.Refresh(W)
 local label=S.OpenJournal()
 assert(label:find(S.BUILD_A,1,true),'SETUP: the Journal names the kept Saved Build A: "'..label..'"')
 local bound,before,after=LegacyShow(W,'legacy-kept')
 record('SYMPTOM','LEGACY-KEPT-BINDING',bound==nil or (bound>=1 and bound<=MAX),
  'the main entry binds no Wishlist index as a loadout (kept Saved Build A); bound='..tostring(bound))
 record('DATA','LEGACY-KEPT-RECORD-PRESERVED',after['loadout:101']~=nil and after['loadout:101']==before['loadout:101'],
  'the legacy record under 101 is kept byte-equal')
 record('DATA','LEGACY-KEPT-SAVED-BUILDS',after['loadout:1']==before['loadout:1'] and after['loadout:2']==before['loadout:2'],
  'the Saved Build associations are byte-equal')
end)

stage('legacy-cold',function()
 local rows,total,locks=LegacyRows()
 local seed=Boot({active=1,rows=rows,locked=locks})
 assert(seed.A.SetLoadoutWishlist(1,102,nil)==true,'SETUP: Saved Build A holds plan S')
 assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(state)
  state.loadoutWishlists[101]={slot=101,name=LEGACY,key=seed.A.WishlistKey(total),echoes=seed.H.Clone(total)}
 end),'SETUP: the legacy record is written through the store owner')
 local W=Boot({active=S.MIRROR_D,rows=rows,locked=locks,db=seed.H.Clone(NexusDB)})
 local label=S.OpenJournal()
 assert(label:find('No Saved Build',1,true),'SETUP: after a cold boot at 101 nothing is selected: "'..label..'"')
 local bound,before,after=LegacyShow(W,'legacy-cold')
 record('SYMPTOM','LEGACY-COLD-BINDING',bound==nil or (bound>=1 and bound<=MAX),
  'with nothing selected the main entry binds no Wishlist index as a loadout; bound='..tostring(bound))
 record('DATA','LEGACY-COLD-RECORD-PRESERVED',after['loadout:101']~=nil and after['loadout:101']==before['loadout:101'],
  'the legacy record under 101 is kept byte-equal')
end)

-- ===================================================================
-- N5 controls: the Journal's Unassign and design buttons follow the label.
stage('journal-controls-kept',function()
 local W=KeptWorld(1)
 S.OpenJournal()
 NexusAssociatedWishlistDesignButton:Click()
 local bound=Bound()
 record('CONTROL','DESIGN-KEPT',bound==1,'the design button opens the kept Saved Build A\'s plan bound to 1: '..tostring(bound))
 CloseEditor()
 local picker=S.OpenPicker()
 assert(picker and picker.clearRow and picker.clearRow:IsVisible(),'SETUP: Unassign is offered')
 local before=S.Destinations()
 local calls,restore=S.Spy(W.A,WRITERS)
 picker.clearRow:Click()
 restore()
 local changed=table.concat(S.Changed(before,S.Destinations()),',')
 record('CONTROL','UNASSIGN-KEPT',changed=='loadout:1' and #calls==1
  and Calls(calls):find('ClearLoadoutWishlist(1)->true',1,true)==1,
  'Unassign clears Saved Build A only: '..Calls(calls)..' changed '..changed)
end)

stage('journal-controls-cold',function()
 local W=ColdWorld(S.BindInitial(S.World({level=1})))
 assert(S.OpenPicker(),'SETUP: the picker opens')
 S.PickerRow(S.PLAN_S).nameButton:Click()
 assert(type(Nexus.Store.State().firstRunWishlist)=='table','SETUP: the picker set the first-run plan')
 S.OpenJournal()
 NexusAssociatedWishlistDesignButton:Click()
 local bound=Bound()
 record('CONTROL','DESIGN-COLD',bound==nil,'with nothing selected the design button binds no loadout: '..tostring(bound))
 CloseEditor()
 local picker=S.OpenPicker()
 assert(picker and picker.clearRow and picker.clearRow:IsVisible(),'SETUP: Unassign is offered')
 local before=S.Destinations()
 picker.clearRow:Click()
 local changed=table.concat(S.Changed(before,S.Destinations()),',')
 record('CONTROL','UNASSIGN-COLD',changed=='first','Unassign clears the first-run plan only: changed '..changed)
end)

-- N5 control: a FirstRunHandoff-stamped Saved Build 1 keeps its documented
-- handoff when nothing is selected at 101 (pick and Unassign rewrite slot 1
-- together with the first-run plan, and nothing else).
stage('handoff-cold',function()
 local W0=S.World({level=1})
 local echoes={{spellId=S.ECHO_3,quality=0,stacks=1,locked=false},{spellId=S.ECHO_4,quality=0,stacks=1,locked=false}}
 assert(W0.A.SetFirstLoadoutWishlistIdentity(S.PLAN_S,echoes,{})==true,'SETUP: a first-run plan with its slot-1 handoff')
 local st=Nexus.Store.State()
 assert(type(st.firstRunWishlist)=='table' and st.loadoutWishlists[1]
  and st.loadoutWishlists[1].assignmentId==st.firstRunWishlist.assignmentId,'SETUP: slot 1 carries the handoff stamp')
 local W=ColdWorld(W0)
 local picker=S.OpenPicker()
 assert(picker,'SETUP: the picker opens')
 local before=S.Destinations()
 S.PickerRow(S.PLAN_D).nameButton:Click()
 local after=S.Destinations()
 local now=Nexus.Store.State()
 local changed=table.concat(S.Changed(before,after),',')
 record('CONTROL','HANDOFF-PICK',changed=='first,loadout:1' and now.loadoutWishlists[1]
  and now.loadoutWishlists[1].assignmentId==now.firstRunWishlist.assignmentId,
  'the pick replaces the first-run plan and its stamped handoff together: changed '..changed)
 picker=S.OpenPicker()
 assert(picker and picker.clearRow and picker.clearRow:IsVisible(),'SETUP: Unassign is offered')
 before=S.Destinations()
 picker.clearRow:Click()
 changed=table.concat(S.Changed(before,S.Destinations()),',')
 record('CONTROL','HANDOFF-UNASSIGN',changed=='first,loadout:1','Unassign clears the first-run plan and its handoff: changed '..changed)
 record('DATA','HANDOFF-NO-WISHLIST-INDEX-WRITE',WishlistIndexWrites(before,S.Destinations())=='','nothing under a Wishlist index')
end)

-- Control: activation keeps its level gate; choosing is not activating.
stage('activation-gate',function()
 local W=KeptWorld(40)
 local ok,why=W.A.Activate(1)
 record('CONTROL','ACTIVATE-LEVEL-GATED',ok==false and why=='not level 1/80' and S.Count(W,'activate')==0,
  'native activation stays level-gated at 40: '..tostring(ok)..','..tostring(why))
end)

local missed,byGroup,summary={},{},{}
for _,r in ipairs(results) do
 local g=byGroup[r.group] or {ok=0,miss=0};byGroup[r.group]=g
 if r.ok then g.ok=g.ok+1 else g.miss=g.miss+1;missed[#missed+1]=r.group..':'..r.id end
end
for _,name in ipairs({'SYMPTOM','CONTEXT','DATA','CONTROL','STAGE'}) do
 local g=byGroup[name]
 if g then summary[#summary+1]=name..' ok='..g.ok..' miss='..g.miss end
end
realPrint('SUMMARY '..table.concat(summary,'; '))
if #missed>0 then
 error('FAIL saved_build_wishlist_editor_context: '..#missed..' expectation(s) not met: '..table.concat(missed,', '),0)
end
realPrint('PASS saved_build_wishlist_editor_context: editor entries follow the Nexus Saved Build selection and never '
 ..'address or name a Wishlist index as a Saved Build; first-run, handoff and gates unchanged; checks='..#results)
