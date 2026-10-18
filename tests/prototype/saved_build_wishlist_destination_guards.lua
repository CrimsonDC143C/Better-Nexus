-- Boundaries of the Saved Build selection Nexus keeps while a Wishlist is
-- natively active (GameAdapter.SelectedSavedBuild), and of the Journal panel
-- destinations that follow it. Companion of saved_build_wishlist_transition.
--
-- The kept selection is session memory set only by reading a populated Saved
-- Build as the native active slot. It must never be invented (fresh boot),
-- survive slot 0, an empty Saved Build or a deleted one, outlive the declared
-- range, or change a native fact; an unreadable slot changes nothing. Where no
-- Saved Build is selected, the panel's callbacks use the first-run context its
-- label names, never a Wishlist number as a loadout. Association is not
-- activation: activation keeps its own level gate.
--
-- Real boot, real Journal selector, picker and gear callbacks, real adapter
-- writers under call-through spies; the native side is the synthetic server.
local here=(arg and arg[0] or ''):match('^(.*[/\\])') or 'tests/prototype/'
local S=dofile(here..'saved_build_wishlist_transition_support.lua')
local realPrint=print
local results={}
local function record(id,ok,message)
 results[#results+1]={id=id,ok=ok==true}
 realPrint((ok==true and 'OK   ' or 'MISS ')..id..': '..tostring(message))
end
local function stage(name,fn)
 local ok,err=pcall(fn)
 if not ok then record('STAGE:'..name,false,'did not complete: '..tostring(err)) end
end

-- Adapter calls without table arguments (stable text across boots).
local function Calls(calls)
 local out={}
 for _,c in ipairs(calls) do
  out[#out+1]=c.fn..'('..tostring(c.args[1])..')->'
   ..(c.ret and (tostring(c.ret[1])..','..tostring(c.ret[2])) or 'raised')
 end
 return #out>0 and table.concat(out,'; ') or 'none'
end

-- The real picker row click for `name`, with what the row's tooltip names,
-- the adapter calls it made and every association destination around it.
local function Click(W,name)
 local picker,label=S.OpenPicker()
 assert(picker,'SETUP: the real Journal selector opens its picker')
 local row=assert(S.PickerRow(name),'SETUP: the picker lists '..name..': '..S.PickerNames())
 local target
 for _,line in ipairs(S.Hover(W,row.nameButton)) do
  local named=S.Plain(line):match('^Target: (.*)$')
  if named then target=named end
 end
 local before=S.Destinations()
 local calls,restore=S.Spy(W.A,{'SetLoadoutWishlist','SetFirstRunWishlist','Activate'})
 local heard,ok,err=S.Heard(W,function() row.nameButton:Click() end)
 restore()
 assert(ok,'SETUP: the click raised: '..tostring(err))
 local after=S.Destinations()
 return {label=label,target=target,calls=Calls(calls),heard=table.concat(heard,' / '),
  before=before,after=after,changed=table.concat(S.Changed(before,after),','),
  pickerOpen=NexusWishlistOnlyPicker:IsShown()}
end

local function Selected(W)
 local slot,kept=W.A.SelectedSavedBuild()
 return tostring(slot)..'/'..tostring(kept)
end

local function Native(W,active)
 W.H.perks.serverActiveSlot=active
 S.Refresh(W)
end

-- The same synthetic world as the regression, booted with the given saved
-- data and the native active slot already set: nothing observed before boot.
local function BootAt(db,rows,active)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil;NexusWishlistOnlyPicker=nil
 NexusLoadoutAssociationPanel=nil;NexusActiveWishlistSelector=nil
 local H=dofile('tests/prototype/harness.lua')
 H.playerLevel=1
 wipe(H.db)
 for _,id in ipairs({S.ECHO_1,S.ECHO_2,S.ECHO_3,S.ECHO_4}) do H.AddEcho(id,'Synthetic Echo '..id,0,5) end
 H.AddEcho(S.TOME,'Synthetic Tome Echo',0,1)
 H.db[S.TOME].requiredSpell=S.TOME_LEVER
 H.names[S.TOME_LEVER]='Tome of Synthetic Tome Echo'
 H.perks.serverActiveSlot=active
 H.perks.serverBuildSlots=rows
 NexusDB=db
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,
  GetCharges=function()return 0 end,IsOfferPending=function()return false end,
  RequestCharges=function()end,
  ConfirmSpend=function()error('a selection must not spend')end}
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
 assert(Nexus.StartupStatus().coreReady==true,'SETUP: start-up completed after the reboot')
 return W
end

-- G1. The top of a declared range (6). The kept Saved Build is 6 and the
-- click assigns to 6 alone; when the declared range shrinks below it, it is
-- no longer a Saved Build and nothing is kept, while its stored association
-- stays as it was.
stage('top-slot',function()
 local W=S.BindInitial(S.World({level=1}))
 W.max=6
 W.H.service.GetServerMaxSlots=function() return W.max end
 W.H.perks.serverBuildSlots[6]={name='Saved Build F',verified=true,
  echoes={{spellId=S.ECHO_4,quality=0,stacks=1}}}
 Native(W,6)
 assert(S.OpenJournal():find('Saved Build F',1,true),'SETUP: Saved Build 6 is natively active')
 W.H.perks.serverBuildSlots[107]={name=S.TOME_LIST,verified=false,
  echoes={{spellId=S.TOME,quality=0,stacks=1}}}
 Native(W,107)
 local label=S.OpenJournal()
 record('G1-TOP-LABEL',label:find('Saved Build F',1,true)~=nil,'Wishlist 107 active keeps Saved Build 6: "'..label..'"')
 record('G1-TOP-SELECTED',Selected(W)=='6/true','SelectedSavedBuild is the kept 6: '..Selected(W))
 local r=Click(W,S.PLAN_S)
 record('G1-TOP-CLICK',r.target=='Saved Build F' and r.calls=='SetLoadoutWishlist(6)->true,nil'
  and r.changed=='loadout:6' and not r.pickerOpen,
  'the click assigns to Saved Build 6 only: target='..tostring(r.target)..' calls='..r.calls..' changed='..r.changed)
 local stored=S.Destinations()
 W.max=5
 S.Refresh(W)
 label=S.OpenJournal()
 record('G1-RANGE-SHRINK',label:find('No Saved Build',1,true)~=nil and Selected(W)=='nil/false',
  'slot 6 above a declared five is no Saved Build: "'..label..'" '..Selected(W))
 record('G1-RANGE-SHRINK-DATA',S.Destinations()['loadout:6']==stored['loadout:6'],
  'the stored Saved Build 6 association is unchanged')
end)

-- G2. A fresh boot while a Wishlist is natively active: nothing is invented.
-- The panel names no Saved Build, the assignment stays as before, and the
-- click goes to the first-run destination its tooltip names, never to a
-- Saved Build, and changes no Saved Build association.
stage('fresh-boot-at-wishlist',function()
 local first=S.BindInitial(S.World({level=1}))
 local db=first.H.Clone(NexusDB)
 local rows=first.H.Clone(first.H.perks.serverBuildSlots)
 local W=BootAt(db,rows,S.MIRROR_D)
 local label=S.OpenJournal()
 record('G2-NO-INVENTED-SELECTION',label:find('No Saved Build',1,true)~=nil and Selected(W)=='nil/false',
  'after a reload at Wishlist 101 no Saved Build is selected: "'..label..'" '..Selected(W))
 local a,desc=S.Assigned(W)
 record('G2-ASSIGNMENT-UNCHANGED',a.state=='restoring','the assignment reads as before the fix: '..desc)
 local r=Click(W,S.PLAN_S)
 record('G2-FIRST-RUN-DESTINATION',r.target=='No Saved Build selected'
  and r.calls=='SetFirstRunWishlist(102)->true,nil' and r.changed=='first',
  'the click writes the first-run destination its tooltip names: target='..tostring(r.target)
  ..' calls='..r.calls..' changed='..r.changed..' '..r.heard)
 record('G2-SAVED-BUILDS-UNCHANGED',r.after['loadout:1']==r.before['loadout:1']
  and r.after['loadout:2']==r.before['loadout:2'],'no Saved Build association changed')
 local picker=S.OpenPicker()
 assert(picker,'SETUP: the picker opens again')
 local row=assert(S.PickerRow(S.PLAN_D),'SETUP: the picker lists '..S.PLAN_D)
 local _,okGear,errGear=S.Heard(W,function() row.gear:Click() end)
 assert(okGear,'SETUP: the gear raised: '..tostring(errGear))
 local ctx,create=S.EditorContext()
 record('G2-EDITOR-NO-LOADOUT',ctx.loadoutSlot==nil and create.loadoutSlot==nil,
  'the gear binds the editor to no loadout: '..tostring(ctx.loadoutSlot)..'/'..tostring(create.loadoutSlot))
end)

-- G3. Slot 0 natively active drops the kept Saved Build; a later Wishlist
-- does not bring it back.
stage('slot-zero-drops',function()
 local W=S.BindInitial(S.World({level=1}))
 Native(W,0)
 local zero=S.OpenJournal()
 Native(W,S.MIRROR_D)
 local label=S.OpenJournal()
 local a,desc=S.Assigned(W)
 record('G3-SLOT-ZERO',zero:find('No Saved Build',1,true)~=nil and label:find('No Saved Build',1,true)~=nil
  and Selected(W)=='nil/false' and a.state=='restoring',
  'slot 0 then Wishlist 101: "'..zero..'" then "'..label..'" '..Selected(W)..' '..desc)
end)

-- G4. An empty Saved Build natively active is that Saved Build (its existing
-- empty-slot wording) and drops the kept one.
stage('empty-saved-build-drops',function()
 local W=S.BindInitial(S.World({level=1}))
 W.H.perks.serverBuildSlots[4]={name='',verified=false,echoes={}}
 Native(W,4)
 local empty=S.OpenJournal()
 Native(W,S.MIRROR_D)
 local label=S.OpenJournal()
 record('G4-EMPTY-SAVED-BUILD',empty:find('Empty Saved Build',1,true)~=nil
  and label:find('No Saved Build',1,true)~=nil and Selected(W)=='nil/false',
  'empty Saved Build 4 then Wishlist 101: "'..empty..'" then "'..label..'" '..Selected(W))
end)

-- G5. The kept Saved Build is deleted while a Wishlist is active: no Saved
-- Build is selected, its stored association is kept, the click does not write
-- to it, and it is not selected again when the slot is repopulated.
stage('deleted-saved-build',function()
 local W=S.BindInitial(S.World({level=1}))
 Native(W,S.MIRROR_D)
 assert(S.OpenJournal():find(S.BUILD_A,1,true),'SETUP: Saved Build A is kept while Wishlist 101 is active')
 local stored=S.Destinations()
 local row1=W.H.perks.serverBuildSlots[1]
 W.H.perks.serverBuildSlots[1]=nil
 S.Refresh(W)
 local label=S.OpenJournal()
 record('G5-DELETED-NOT-SELECTED',label:find('No Saved Build',1,true)~=nil and Selected(W)=='nil/false',
  'a deleted Saved Build is not selected: "'..label..'" '..Selected(W))
 record('G5-DELETED-ASSOCIATION-KEPT',S.Destinations()['loadout:1']==stored['loadout:1'],
  'its stored association is not deleted')
 local r=Click(W,S.PLAN_S)
 record('G5-NO-WRITE-TO-DELETED',r.calls=='SetFirstRunWishlist(102)->true,nil'
  and r.after['loadout:1']==stored['loadout:1'] and r.after['loadout:2']==stored['loadout:2'],
  'the click does not address the deleted Saved Build: calls='..r.calls..' changed='..r.changed)
 W.H.perks.serverBuildSlots[1]=row1
 S.Refresh(W)
 label=S.OpenJournal()
 record('G5-NOT-RESURRECTED',label:find('No Saved Build',1,true)~=nil and Selected(W)=='nil/false',
  'repopulated while the Wishlist stays active, it is not selected again: "'..label..'"')
end)

-- G6. An unreadable native active slot (fractional) is not an observation:
-- nothing is selected while it is unreadable, and the kept Saved Build is
-- still kept when a Wishlist is read again.
stage('unreadable-active',function()
 local W=S.BindInitial(S.World({level=1}))
 Native(W,2.5)
 local slots=W.A.Slots()
 local unread=S.OpenJournal()
 record('G6-UNREADABLE',slots.activeKnown==false and unread:find('No Saved Build',1,true)~=nil
  and Selected(W)=='nil/false','a fractional slot is unknown and selects nothing: "'..unread..'"')
 Native(W,S.MIRROR_D)
 local label=S.OpenJournal()
 local a,desc=S.Assigned(W)
 record('G6-KEPT-THROUGH-UNREADABLE',label:find(S.BUILD_A,1,true)~=nil and a.name==S.PLAN_D
  and a.state==W.bound.state,'Wishlist 101 after it keeps Saved Build A: "'..label..'" '..desc)
end)

-- G7. Native facts stay native, and the adapter still refuses a Wishlist
-- number as a Saved Build.
stage('native-facts',function()
 local W=S.BindInitial(S.World({level=1}))
 S.NativeTransition(W)
 local slots=W.A.Slots()
 local a,desc=S.Assigned(W)
 record('G7-NATIVE-ACTIVE-SLOT',slots.activeSlot==S.MIRROR_D and a.activeSlot==S.MIRROR_D,
  'A.Slots() and the assignment report native slot 101: '..tostring(slots.activeSlot)..'/'..tostring(a.activeSlot))
 record('G7-NEXUS-TARGET',a.name==S.PLAN_D and a.state==W.bound.state and Selected(W)=='1/true',
  'while Nexus targets kept Saved Build 1: '..desc..' '..Selected(W))
 local before=S.Destinations()
 local ok1,why1=W.A.SetLoadoutWishlist(S.MIRROR_D,S.MIRROR_S,nil)
 local ok2,why2=W.A.UpdateWishlistAssociationAfterSave(S.MIRROR_D,S.MIRROR_S,S.PLAN_S,
  {{spellId=S.ECHO_3,quality=0,stacks=1,locked=false},{spellId=S.ECHO_4,quality=0,stacks=1,locked=false}},{})
 record('G7-WISHLIST-INDEX-REFUSED',ok1==false and why1=='invalid loadout' and ok2==false and why2=='invalid loadout'
  and S.Changed(before,S.Destinations())[1]==nil,
  'the writers still refuse 101 as a Saved Build and write nothing: '..tostring(why1)..'/'..tostring(why2))
end)

-- G8. Level 40: choosing the target is metadata and works; activation is the
-- level-gated native action and stays refused.
stage('level-40',function()
 local W=S.BindInitial(S.World({level=40}))
 S.NativeTransition(W)
 local r=Click(W,S.PLAN_S)
 record('G8-ASSOCIATION',r.calls=='SetLoadoutWishlist(1)->true,nil' and r.changed=='loadout:1'
  and S.Count(W,'activate')==0,'level 40 assigns to the kept Saved Build without activation: '..r.calls)
 local ok,why=W.A.Activate(1)
 record('G8-ACTIVATION-GATED',ok==false and why=='not level 1/80' and S.Count(W,'activate')==0,
  'activation stays level-gated: '..tostring(ok)..','..tostring(why))
end)

local missed={}
for _,r in ipairs(results) do if not r.ok then missed[#missed+1]=r.id end end
realPrint('SUMMARY ok='..(#results-#missed)..' miss='..#missed)
if #missed>0 then
 error('FAIL saved_build_wishlist_destination_guards: '..#missed..' not met: '..table.concat(missed,', '),0)
end
realPrint('PASS saved_build_wishlist_destination_guards: the kept Saved Build is observed, never invented, '
 ..'dropped on slot 0, empty, deleted or undeclared, kept through unreadable reads; native facts unchanged; checks='..#results)
