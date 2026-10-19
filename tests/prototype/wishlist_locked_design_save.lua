-- C-001 / RC-2: actual controller -> upload -> GameAdapter association writers.
-- Synthetic TOC-boot data only. No native client, player data or network.
-- Invalid locked evidence must refuse before upload, preserve the editor and
-- every existing valid association, and say why. Empty valid designs still save.
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('wishlist_locked_design_save')
local function Setup(branch)
 Nexus=nil;SlashCmdList=nil;NexusDB=nil;WishlistRealizerDB=nil
 local H=dofile('tests/prototype/harness.lua')
 H.locked={{spellId=200080,stacks=1},{spellId=200081,stacks=1}}
 H.perks.serverBuildSlots[1]={name='Synthetic build',verified=true,
  echoes={{spellId=200010,quality=2,stacks=1}}}
 H.perks.serverActiveSlot=branch=='first' and 0 or 1
 H.Boot()
 local A=Nexus.GameAdapter
 local ordinary={{spellId=200001,quality=1,stacks=1,locked=false}}
 local targets={[200081]={version=1,copies=1,rows={
  {spellId=200081,quality=1,stacks=1,locked=true,sourceRole='locked'}}}}
 C.setup(A.SetLoadoutWishlistIdentity(1,'Original synthetic',H.Clone(ordinary),H.Clone(targets)),
  branch..': original valid durable design is installed by actual adapter')
 H.perks.serverBuildSlots[101]={name='Original synthetic',verified=false,echoes=H.Clone(ordinary)}
 H.perks.serverBuildSlots[102]={name='Unassigned synthetic',verified=false,echoes=H.Clone(ordinary)}
 H.Notify();A.Poll()
 local calls,notes={},{}
 for _,key in ipairs({'SetLoadoutWishlistIdentity','UpdateWishlistAssociationAfterSave','SetFirstLoadoutWishlistIdentity'}) do
  local real=A[key]
  A[key]=function(...) calls[#calls+1]=key;return real(...) end
 end
 local controller=Nexus.WishlistInternals.Controller.New({model=Nexus.WishlistModel.New(),store=Nexus.Store,
  accountRoot=function() return {} end,notify=function(s) notes[#notes+1]=s end})
 controller.Initialize(A)
 if branch=='edit' then
  local opened=A.GetLoadoutWishlist(1)
  C.setup(opened~=nil and controller.BeginWishlist(opened,1),branch..': actual bound existing editor opens')
 elseif branch=='none' then
  local chosen
  for _,w in ipairs(A.GetWishlistCandidates()) do if w.slot==102 then chosen=w end end
  C.setup(chosen~=nil and controller.BeginWishlist(chosen),branch..': existing unassigned Wishlist opens')
 else controller.BeginNewWishlist() end
 local f={H=H,A=A,W=controller,calls=calls,notes=notes,branch=branch}
 f.before=B.Dump(Nexus.Store.State().loadoutWishlists)
 f.firstBefore=B.Dump(Nexus.Store.State().firstRunWishlist)
 f.bucket=B.Dump(Nexus.Store.State().lockDesignTargetsBySlot)
 return f
end
local function Rows(f,id,quality)
 return {{spellId=200001,quality=1,stacks=1,locked=false},
  {spellId=200081,quality=1,stacks=1,locked=true},
  {spellId=id,quality=quality,stacks=1,locked=true}}
end
local function HasTarget(record,id)
 for _,row in ipairs(record and record.designRows or {}) do if row.spellId==id then return true end end
 return false
end
local function Draft(f)
 return B.Dump({pending=f.W.PendingRows(),locked=f.W.PendingLockRows(),fulfilled=f.W.FulfilledDraftTargets()})
end
local function Refused(f,label,afterPrepare)
 local before=Draft(f)
 local fulfilledBefore=f.W.DebugDraftState().fulfilled
 local count=B.Count(f.H,'upload')
 local data,why=f.W.PrepareApply('Edited synthetic')
 if afterPrepare then C.setup(data~=nil,label..': healthy confirmation prepared before catalog changes');afterPrepare() end
 local ok,reason
 if data then ok,reason=f.W.AcceptApply(data) else reason=why end
 local saved=Nexus.Store.State().loadoutWishlists
 local target=saved and saved[1]
 print('OBSERVED',label,'refused='..tostring(ok~=true),'reason='..tostring(reason),
  'writers='..table.concat(f.calls,','),'uploads='..(B.Count(f.H,'upload')-count),
  'fulfilled='..fulfilledBefore..'->'..f.W.DebugDraftState().fulfilled,
  'storedTarget81='..tostring(HasTarget(target,200081)))
 C.expect(ok~=true and reason=='invalid_locked_design',label..': invalid design explicitly refused',reason)
 C.expect(B.Count(f.H,'upload')==count,label..': refuses before upload')
 C.expect(#f.calls==0,label..': no association writer called',table.concat(f.calls,','))
 C.expect(Draft(f)==before,label..': pending and fulfilled draft kept exactly')
 C.expect(B.Dump(saved)==f.before,label..': prior valid associations kept exactly')
 C.expect(B.Dump(Nexus.Store.State().firstRunWishlist)==f.firstBefore,label..': first-run association kept exactly')
 C.expect(B.Dump(Nexus.Store.State().lockDesignTargetsBySlot)==f.bucket,label..': legacy design bucket kept exactly')
 local said=B.Plain(table.concat(f.notes,' / '))
 C.expect(said:find('Not saved:',1,true)~=nil and said:find('locked',1,true)~=nil
  and not said:find('Wishlist saved',1,true),label..': explanatory refusal, no success notice',said)
 C.guard(not f.W.IsApplyPending(),label..': no upload retry retained')
 for _,kind in ipairs({'lock','unlock','take','orb-spend','reroll'}) do
  C.guard(B.Count(f.H,kind)==0,label..': no '..kind..' action')
 end
end
for _,branch in ipairs({'create','edit'}) do
 for _,reconcile in ipairs({false,true}) do
 C.scenario('self-replacement '..branch..' '..tostring(reconcile),function()
  local f=Setup(branch)
  C.setup(f.W.LoadPendingEchoes({{spellId=200001,quality=1,stacks=1,locked=false},
   {spellId=200081,quality=1,stacks=1,locked=true}}),'self: ordinary+fulfilled valid rows loaded')
  C.setup(f.W.ToggleReplacementAssignment(200080),'self: actual replacement mode opens')
  C.setup(f.W.AssignLockSlot({spellId=200080,quality=0,name='Echo 80'})=='queued',
   'self: actual controller admits self-replacement (RC-2)')
  if reconcile then f.W.ReconcileLocked({[200080]=1,[200081]=1}) end
  Refused(f,'self '..branch..' '..tostring(reconcile))
 end)
 end
end
for _,branch in ipairs({'create','edit','first','none'}) do
 C.scenario('quality mismatch '..branch,function()
  local f=Setup(branch)
  C.setup(f.W.LoadPendingEchoes(Rows(f,200082,3)),branch..': explicit-role quality-mismatched draft admitted')
  Refused(f,'quality '..branch)
 end)
end
C.scenario('catalog drift after confirmation',function()
 local f=Setup('create')
 C.setup(f.W.LoadPendingEchoes(Rows(f,200082,2)),'catalog: valid locked draft admitted')
 Refused(f,'catalog after confirmation',function()
  local snapshot=f.H.Clone(f.A.Catalog());snapshot.rows[200082]=nil;snapshot.familyOf[200082]=nil
  f.A.Catalog=function() return snapshot end
 end)
end)
C.scenario('invalid retained design sentinel',function()
 local f=Setup('create')
 -- DecodeDesign returns false for malformed stored rows. Loading preserves
 -- this distinction from an intentional nil/empty design until Save.
 C.setup(f.W.LoadPendingEchoes({{spellId=200001,quality=1,stacks=1,locked=false}},true,false),
  'retained: ordinary draft loads with invalid retained design sentinel')
 Refused(f,'retained invalid sentinel')
end)
C.scenario('valid design and empty design controls',function()
 for _,branch in ipairs({'create','edit','first','none'}) do
  local f=Setup(branch)
  C.setup(f.W.LoadPendingEchoes(Rows(f,200082,2)),branch..': valid draft loaded')
  local data=f.W.PrepareApply('Valid synthetic')
  C.setup(data~=nil and f.W.AcceptApply(data)==true,branch..': valid design saves')
  local expected=({create='SetLoadoutWishlistIdentity',edit='UpdateWishlistAssociationAfterSave',first='SetFirstLoadoutWishlistIdentity'})[branch]
  C.guard(#f.calls==(expected and 1 or 0) and (not expected or f.calls[1]==expected),branch..': exact expected writer branch',table.concat(f.calls,','))
  C.guard(B.Count(f.H,'upload')==1,branch..': one valid upload')
  local rec=branch=='first' and Nexus.Store.State().firstRunWishlist or (Nexus.Store.State().loadoutWishlists or {})[1]
  if expected then C.guard(HasTarget(rec,200081) and HasTarget(rec,200082),branch..': valid locked targets survive durable writer') end
 end
 local f=Setup('create')
 C.setup(f.W.LoadPendingEchoes({{spellId=200002,quality=2,stacks=1,locked=false}},true,{}),'empty: ordinary-only draft loaded')
 local data=f.W.PrepareApply('Empty locked design')
 C.guard(data~=nil and f.W.AcceptApply(data)==true and #f.calls==1,'empty: intentionally empty design still saves')
end)
C.finish()
