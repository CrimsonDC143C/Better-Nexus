-- A native Wishlist change must not take the Nexus Saved Build selection with it.
--
-- Reported (test.2026101503-2211b2ac1f88, level 1, fresh reload, fully loaded):
-- a new native Wishlist holding one tome was created; the Journal then read
-- "No Saved Build selected"; its dropdown opened but choosing a row did
-- nothing, also after the native Wishlist was switched back; chat showed
-- "Nexus: invalid loadout" and, after a later save, "Wishlist uploaded and
-- targets saved, but assignment failed (invalid loadout)". The status read
-- ACTIVE slot 101 and "Restoring assigned Wishlist...", with every Saved Build
-- and plan still readable. Expected: the native Wishlist changes on its own;
-- the Nexus selection and all saved data stay.
--
-- The native selection is only what the synthetic server answers: the active
-- slot moves into the Wishlist range above the declared Saved Builds (103,
-- then 101). Everything Nexus does is real: the Journal refresh, the
-- selector, the picker row and gear callbacks, the editor and its save.
-- Spies call through and record what the adapter was asked and answered.
--
-- Groups: USER (the reporter's stated expectation), SYMPTOM (the refusal and
-- its ownership), DATA (saved rows stay byte-equal; independent of selection),
-- CONTROL (one-variable controls, including that native activation's level
-- gate is a separate action from choosing a target). Every stage boots fresh
-- and runs; the verdict lists every expectation not met.
local here=(arg and arg[0] or ''):match('^(.*[/\\])') or 'tests/prototype/'
local S=dofile(here..'saved_build_wishlist_transition_support.lua')
local realPrint=print
local results,shared={},{}
local function record(group,id,ok,message)
 results[#results+1]={group=group,id=id,ok=ok==true}
 realPrint((ok==true and 'OK   ' or 'MISS ')..group..' '..id..': '..tostring(message))
end
local function observe(id,message) realPrint('OBSERVE '..id..': '..tostring(message)) end
local function stage(name,fn)
 local ok,err=pcall(fn)
 if not ok then record('STAGE',name,false,'did not complete: '..tostring(err)) end
end

-- The picker click at the reported state: after the native transition, the
-- real selector, a row's tooltip target, then the row click under spies.
local function MirrorClick(W)
 S.NativeTransition(W)
 local picker,label=S.OpenPicker()
 assert(picker,'SETUP: the real Journal selector opens its picker at active slot '
  ..tostring(W.A.Slots().activeSlot)..' (reported: the dropdown opens)')
 local row=assert(S.PickerRow(S.PLAN_S),'SETUP: the picker lists '..S.PLAN_S..': '..S.PickerNames())
 local target
 for _,line in ipairs(S.Hover(W,row.nameButton)) do
  local named=S.Plain(line):match('^Target: (.*)$')
  if named then target=named end
 end
 assert(target,'SETUP: the row tooltip names its target')
 local r={label=label,target=target,rows=S.PickerNames(),before=S.Destinations(),
  server0=S.ServerSavedBuilds(W),writes0=S.Writes(W),actions0=#W.H.actions}
 local calls,restore=S.Spy(W.A,{'SetLoadoutWishlist','SetFirstRunWishlist','Activate'})
 local heard,ok,err=S.Heard(W,function() row.nameButton:Click() end)
 restore()
 assert(ok,'SETUP: the picker click raised: '..tostring(err))
 r.calls,r.heard=calls,heard
 r.assigned,r.assignedDesc=S.Assigned(W)
 r.pickerOpen=NexusWishlistOnlyPicker:IsShown()
 r.after=S.Destinations()
 r.changed=S.Changed(r.before,r.after)
 local slots=W.A.Slots()
 r.maxSlots=tonumber(slots.maxSlots) or 5
 r.active=tonumber(slots.activeSlot)
 return r
end

-- 1. The transition alone, level 1: what the Journal names, what Nexus
-- targets, and that saved data is untouched (a label is not a deletion).
stage('transition',function()
 local W=S.BindInitial(S.World({level=1}))
 local saved0,server0,plans0=S.Saved(),S.ServerSavedBuilds(W),S.Plans(W)
 local writes0=S.Writes(W)
 observe('start','startup='..W.startup..' level=1 active='..tostring(W.A.Slots().activeSlot)
  ..' label="'..W.labelBefore..'" assignment='..select(2,S.Assigned(W))..' plans='..plans0)
 local steps={
  {'T1',S.NativeNewWishlist,'native creates an empty Wishlist; it becomes the active slot'},
  {'T2',S.NativeAddTome,'native adds one tome to it'},
  {'T3',S.NativeSwitchBack,'native switches back to the plan-D Wishlist'},
 }
 for _,step in ipairs(steps) do
  step[2](W)
  local label=S.OpenJournal()
  observe(step[1],step[3]..': active='..tostring(W.A.Slots().activeSlot)
   ..' label="'..label..'" assignment='..select(2,S.Assigned(W)))
  record('USER','SEL-LABEL-'..step[1],label:find(S.BUILD_A,1,true)~=nil,
   'the Journal still names the Nexus-selected "'..S.BUILD_A..'"; got "'..label..'"')
 end
 local a,desc=S.Assigned(W)
 record('USER','SEL-TARGET-T3',a.name==W.bound.name and a.state==W.bound.state,
  'the Nexus target is still '..W.bound.state..'/'..W.bound.name..'; got '..desc)
 local same,diff=S.SameSaved(saved0,S.Saved())
 record('DATA','T3-SAVED-FIELDS',same,'saved plan/association fields are byte-equal'
  ..(same and '' or ('; changed: '..diff)))
 local plans=S.Plans(W)
 record('DATA','T3-RETAINED-PLANS',plans==plans0,'retained plans unchanged: '..plans)
 record('DATA','T3-SERVER-SAVED-BUILDS',S.ServerSavedBuilds(W)==server0,'server Saved Build rows 1-3 unchanged')
 record('DATA','T3-NO-WRITES',S.Writes(W)==writes0,'no upload, save or activation: '..(S.Writes(W)-writes0))
end)

-- 2. The reported click, level 1: after switching back, choose plan S in the
-- real picker. The adapter call and its answer are the captured refusal.
stage('mirror-click',function()
 local W=S.BindInitial(S.World({level=1}))
 local r=MirrorClick(W)
 shared.level1=S.Describe(r.calls)
 observe('click','active='..tostring(r.active)..' label="'..r.label..'" tooltip target="'
  ..r.target..'" rows=['..r.rows..'] adapter: '..shared.level1)
 for _,line in ipairs(r.heard) do observe('notice',S.Plain(line)) end
 local bad={}
 for _,c in ipairs(r.calls) do
  local slot=tonumber(c.args[1])
  if c.fn=='SetLoadoutWishlist' and (not slot or slot<1 or slot>r.maxSlots) then bad[#bad+1]=c end
 end
 record('SYMPTOM','CLICK-OWNERSHIP',#bad==0,'no index outside Saved Builds 1-'..r.maxSlots
  ..' is addressed as a Saved Build; offending: '..S.Describe(bad))
 local want=r.target:find('No Saved Build',1,true) and 'first'
  or (S.SLOT_BY_NAME[r.target] and ('loadout:'..S.SLOT_BY_NAME[r.target]))
  or ('unknown:'..r.target)
 local addressed={}
 for _,c in ipairs(r.calls) do
  if c.fn=='SetLoadoutWishlist' then addressed[#addressed+1]='loadout:'..tostring(c.args[1])
  elseif c.fn=='SetFirstRunWishlist' then addressed[#addressed+1]='first' end
 end
 local agrees=#addressed>0
 for _,d in ipairs(addressed) do if d~=want then agrees=false end end
 record('SYMPTOM','CLICK-TARGET-AGREES',agrees,'the click writes where its tooltip says ("Target: '
  ..r.target..'" = '..want..'); addressed: '..(#addressed>0 and table.concat(addressed,',') or 'nothing'))
 local refusal=S.Said(r.heard,'invalid loadout')
 record('SYMPTOM','CLICK-NO-REFUSAL',refusal==nil,'no invalid-loadout refusal; got: '
  ..tostring(refusal and S.Plain(refusal)))
 record('SYMPTOM','CLICK-EFFECT',not r.pickerOpen and r.assigned.name==S.PLAN_S,
  'the picker closes and the Nexus target becomes '..S.PLAN_S..'; picker open='
  ..tostring(r.pickerOpen)..' assignment='..r.assignedDesc)
 record('SYMPTOM','CLICK-ONE-DESTINATION',#r.changed==1 and r.changed[1]==want,
  'exactly the tooltip destination changes ('..want..'); changed: '
  ..(#r.changed>0 and table.concat(r.changed,',') or 'none'))
 local others=true
 for k,v in pairs(r.before) do if k~=want and r.after[k]~=v then others=false end end
 for k in pairs(r.after) do if k~=want and r.before[k]==nil then others=false end end
 record('DATA','CLICK-OTHER-ASSOCIATIONS',others,'every other association is byte-equal after the click')
 record('DATA','CLICK-PLAN-D-REACHABLE',S.Reachable(W,W.keyD),'the earlier plan is still offered by exact identity')
 record('DATA','CLICK-SERVER-SAVED-BUILDS',S.ServerSavedBuilds(W)==r.server0,'server Saved Build rows 1-3 unchanged')
 record('DATA','CLICK-NO-WRITES',S.Writes(W)==r.writes0,'the selection uploads, saves or activates nothing: '
  ..(S.Writes(W)-r.writes0))
 observe('incidents','after the Journal click: '..S.Incidents())
end)

-- 3. Control, one variable (level 40): association needs no activation, the
-- click at the same native state behaves exactly as at level 1, and native
-- activation is the level-gated action.
stage('level-40-control',function()
 local W=S.BindInitial(S.World({level=40}))
 record('CONTROL','ASSOCIATE-WITHOUT-ACTIVATION',S.Count(W,'activate')==0,
  'binding a plan at level 40 activated nothing: '..S.Count(W,'activate'))
 local r=MirrorClick(W)
 local described=S.Describe(r.calls)
 observe('click-level-40',described)
 record('CONTROL','CLICK-LEVEL-INDEPENDENT',shared.level1~=nil and described==shared.level1,
  'the click gives the same adapter call and answer at level 40 as at level 1 ('..tostring(shared.level1)..')')
 local activations=S.Count(W,'activate')
 local ok,why=W.A.Activate(2)
 record('CONTROL','ACTIVATE-REFUSED-LEVEL-40',ok==false and why=='not level 1/80'
  and S.Count(W,'activate')==activations,'native activation is level-gated: '..tostring(ok)..','..tostring(why))
end)

-- 4. Control, one variable (the active slot stays a Saved Build): a new
-- one-tome Wishlist is published but not made active. Same label, same click.
stage('in-range-control',function()
 local W=S.BindInitial(S.World({level=1}))
 W.H.perks.serverBuildSlots[S.MIRROR_NEW]={name=S.TOME_LIST,verified=false,
  echoes={{spellId=S.TOME,quality=0,stacks=1}}}
 S.Refresh(W)
 local picker,label=S.OpenPicker()
 record('CONTROL','IN-RANGE-LABEL',label:find(S.BUILD_A,1,true)~=nil,
  'a new Wishlist that is not active leaves the label: "'..label..'"')
 assert(picker,'SETUP: the picker opens')
 local row=assert(S.PickerRow(S.PLAN_S),'SETUP: the picker lists '..S.PLAN_S)
 local calls,restore=S.Spy(W.A,{'SetLoadoutWishlist','SetFirstRunWishlist','Activate'})
 local heard,ok,err=S.Heard(W,function() row.nameButton:Click() end)
 restore()
 assert(ok,'SETUP: the click raised: '..tostring(err))
 local a,desc=S.Assigned(W)
 local c=calls[1]
 record('CONTROL','IN-RANGE-CLICK',#calls==1 and c.fn=='SetLoadoutWishlist' and tonumber(c.args[1])==1
  and c.ret~=nil and c.ret[1]==true and a.name==S.PLAN_S and not NexusWishlistOnlyPicker:IsShown(),
  'the same click with Saved Build 1 active assigns: '..S.Describe(calls)..' assignment='..desc
  ..' '..table.concat(heard,' / '))
 record('CONTROL','IN-RANGE-NO-ACTIVATION',S.Count(W,'activate')==0,'choosing a target activated nothing')
 local ok2,why=W.A.Activate(2)
 local last=S.Last(W,'activate')
 record('CONTROL','ACTIVATE-ALLOWED-LEVEL-1',ok2==true and last~=nil and last[2]==2,
  'native activation is allowed at level 1 as its own action: '..tostring(ok2)..','..tostring(why))
end)

-- 5. The later report, level 1: the Journal edit control opens the editor at
-- the same native state; its binding, then a real Save and the server mirror.
-- When the selector names plan D the picker does not list it again; its edit
-- control is then the design button, bound to the same Saved Build as a row gear.
stage('editor-save',function()
 local W=S.BindInitial(S.World({level=1}))
 S.NativeTransition(W)
 local picker,label=S.OpenPicker()
 assert(picker,'SETUP: the picker opens')
 local row=S.PickerRow(S.PLAN_D)
 local edit=row and row.gear or NexusAssociatedWishlistDesignButton
 observe('editor-picker','selector="'..S.Plain(NexusActiveWishlistSelector.text:GetText())..'" rows=['
  ..S.PickerNames()..'] control='..(row and 'row gear' or 'design button'))
 assert(row or (S.Plain(NexusActiveWishlistSelector.text:GetText()):find(S.PLAN_D,1,true)
  and NexusAssociatedWishlistDesignButton:IsEnabled()),'SETUP: '..S.PLAN_D..' has a Journal edit control')
 local opened,okOpen,errOpen=S.Heard(W,function() edit:Click() end)
 assert(okOpen,'SETUP: the Journal edit control raised: '..tostring(errOpen))
 assert(NexusEditorFrame and NexusEditorFrame:IsShown(),'SETUP: the Journal edit control opens the editor: '
  ..table.concat(opened,' / '))
 local ctx,create=S.EditorContext()
 local bound=tonumber(ctx.loadoutSlot or create.loadoutSlot)
 local maxSlots=tonumber(W.A.Slots().maxSlots) or 5
 observe('editor-binding','label="'..label..'" editing loadoutSlot='..tostring(ctx.loadoutSlot)
  ..' create loadoutSlot='..tostring(create.loadoutSlot)..' destination='..tostring(ctx.destination))
 record('SYMPTOM','EDITOR-BINDING',bound==nil or (bound>=1 and bound<=maxSlots),
  'the editor opened from the picker binds no index outside Saved Builds 1-'..maxSlots..'; bound='..tostring(bound))
 local before,server0=S.Destinations(),S.ServerSavedBuilds(W)
 local uploads0=S.Count(W,'upload')
 local calls,restore=S.Spy(W.A,{'UpdateWishlistAssociationAfterSave','SetLoadoutWishlistIdentity',
  'SetFirstLoadoutWishlistIdentity','SetLoadoutWishlist','SetFirstRunWishlist','Activate'})
 local mirrored
 local heard,ok,err=S.Heard(W,function()
  S.Selected(W,S.ECHO_1).plus:Click()
  S.Button(W,'Save Wishlist'):Click()
  assert(W.H.popup and W.H.popup.which=='WISHLISTREALIZER_UPDATE_WISHLIST',
   'SETUP: Save asks for confirmation: '..tostring(W.H.popup and W.H.popup.which))
  W.H.AcceptPopup()
  local last=S.Last(W,'upload')
  assert(last and S.Count(W,'upload')==uploads0+1,'SETUP: the Save uploads once')
  mirrored=S.Mirror(W,last[2],last[3],last[4])
 end)
 restore()
 for _,line in ipairs(heard) do observe('notice',S.Plain(line)) end
 observe('editor-adapter',S.Describe(calls)..'; uploaded to native slot '..tostring(mirrored))
 assert(ok,'SETUP: the editor save did not complete: '..tostring(err))
 local failed=S.Said(heard,'assignment failed')
 record('SYMPTOM','EDITOR-NOTICE',failed==nil,'the save does not end in an assignment failure; got: '
  ..tostring(failed and S.Plain(failed)))
 local after=S.Destinations()
 record('DATA','EDITOR-OTHER-SAVED-BUILD',after['loadout:2']==before['loadout:2'],
  'the Saved Build B association is byte-equal after the save')
 record('DATA','EDITOR-SERVER-SAVED-BUILDS',S.ServerSavedBuilds(W)==server0,'server Saved Build rows 1-3 unchanged')
 record('DATA','EDITOR-NO-SAVE-OR-ACTIVATE',S.Count(W,'save')==0 and S.Count(W,'activate')==0,
  'the Wishlist save saved or activated no Saved Build')
 observe('incidents','after the editor save: '..S.Incidents())
end)

local missed,byGroup,summary={}, {}, {}
for _,r in ipairs(results) do
 local g=byGroup[r.group] or {ok=0,miss=0};byGroup[r.group]=g
 if r.ok then g.ok=g.ok+1 else g.miss=g.miss+1;missed[#missed+1]=r.group..':'..r.id end
end
for _,name in ipairs({'USER','SYMPTOM','DATA','CONTROL','STAGE'}) do
 local g=byGroup[name]
 if g then summary[#summary+1]=name..' ok='..g.ok..' miss='..g.miss end
end
realPrint('SUMMARY '..table.concat(summary,'; '))
if #missed>0 then
 error('FAIL saved_build_wishlist_transition: '..#missed..' expectation(s) not met: '
  ..table.concat(missed,', '),0)
end
realPrint('PASS saved_build_wishlist_transition: the Nexus selection survives native Wishlist changes; '
 ..'the picker and editor never address a Wishlist index as a Saved Build; saved data intact; checks='..#results)
