-- M1 (UX-03): the Wishlist editor keeps a persistent, truthful result of its
-- last save, taken from what the save actually did, and offers Assign now
-- only for a genuinely saved plan that no destination uses.
-- Acceptance rows (inputs/FIRST_STAGE.md): M1-A01 Create for the captured
-- Saved Build; A03 bound Save of an inactive Saved Build; A04 unbound save
-- (yellow notice then the generic green line); A05 upload accepted then the
-- assignment refused (one upload, partial result, Assign now never uploads);
-- A06 refused upload; A07 cancel; A08 Assign now through the existing Journal
-- picker (open/close assigns nothing, only the explicit row choice does);
-- A10 delayed spaced retry, a destination changed during the host call, the
-- editor changed during the host call, and a Store owner/root change; A11
-- invalidation by real edits and new drafts, not by passive refresh or a
-- refused edit; A12 no actor, Saved Build, Orb, Sync or Auto call from any
-- presentation, open or cancel path.
-- EXPECT: the M1 behaviour (fails on the 1704 baseline, which has no result
-- row and no Assign now). GUARD: unchanged save/assignment semantics that
-- already hold on the baseline. SETUP: the fixture reached its state.
-- Real TOC boot, adapter, controller, editor and Journal controls; the host
-- services are the synthetic harness. A race is modelled only at the host
-- boundary (the upload call); no product state is set directly.
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('ux_save_assignment_result')
local H,A,writes,spends
local E1={{spellId=201172,quality=0,stacks=1}}
local E2={{spellId=201175,quality=0,stacks=1}}
local E6={{spellId=201173,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}
local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity',
 'SetFirstLoadoutWishlistIdentity','UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist',
 'ClearFirstRunWishlist','SetFirstRunWishlistIdentity'}

local function Boot(o)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil;EchoJournalMicroButton=nil
 -- Named frames of an earlier boot in this process are not this boot's.
 NexusEditorFrame=nil;NexusWishlistNameInput=nil;NexusWishlistEditorSwitchButton=nil
 NexusActiveWishlistSelector=nil;NexusWishlistOnlyPicker=nil;NexusWishlistAssignNowButton=nil
 H=dofile('tests/prototype/harness.lua')
 H.playerLevel=80
 wipe(H.db)
 H.AddEcho(201172,'Echo One',0,5);H.AddEcho(201173,'Echo Six',0,5);H.AddEcho(201174,'Echo Free',0,5)
 H.AddEcho(201175,'Echo Fire',0,5);H.AddEcho(200767,'Echo Lock',0,5)
 H.service.GetServerMaxSlots=function() return 6 end
 H.perks.serverBuildSlots=o.slots
 H.perks.serverActiveSlot=o.active
 spends=0
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,GetCharges=function()return 0 end,
  IsOfferPending=function()return false end,RequestCharges=function()end,
  ConfirmSpend=function() spends=spends+1;return false end}
 H.Boot();A=Nexus.GameAdapter
 H.Notify();A.Poll();H.Advance(1)
 -- Count every assignment writer call (the controller and the Journal use
 -- this same adapter table).
 writes={}
 for _,k in ipairs(WRITERS) do
  local real=A[k]
  if type(real)=='function' then
   writes[k]=0
   A[k]=function(...) writes[k]=writes[k]+1;return real(...) end
  end
 end
end
local function Worlds(kind)
 local slots={[1]={name='One',verified=true,echoes=E1},[2]={name='Fire PvE',verified=true,echoes=E2},
  [6]={name='Six',verified=true,echoes=E6},
  [106]={name='W-Six',verified=false,echoes=E6},[107]={name='W-Free',verified=false,echoes=EF}}
 return slots
end
local function Assign(slot,name,echoes) local ok,why=A.SetLoadoutWishlistIdentity(slot,name,H.Clone(echoes));assert(ok,why);writes.SetLoadoutWishlistIdentity=0 end
-- The editor's own controller (no public handle).
local function Ctrl()
 local show=Nexus.WishlistEditor.Show
 for i=1,255 do local n,v=debug.getupvalue(show,i);if not n then break end
  if n=='wishlistController' then return v end end
 error('editor controller not found')
end
local function Ctx() return Ctrl().EditingContext() or {} end
local function button(text)
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f:GetText()==text then return f end end
 error('visible button absent: '..text)
end
local function selected(id)
 for _,f in ipairs(H.frames)do if f:IsVisible() and f.plus and f.data and f.data.spellId==id then return f end end
 error('visible selected row absent: '..id)
end
local function ClickCatalog(id)
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f.status and f.data and f.data.spellId==id then f:Click();return true end end
 error('visible catalog row absent: '..id)
end
local function menuRow(label)
 for _,f in ipairs(H.frames)do
  if f.kind=='Button' and f:IsVisible() and f._label and tostring(f._label:GetText() or ''):find(label,1,true) then return f end
 end
 error('visible switch-menu row absent: '..label)
end
local function Uploads() local n,last=0,nil;for _,a in ipairs(H.actions)do if a[1]=='upload' then n=n+1;last=a end end;return n,last end
local function Others() local n=0;for _,a in ipairs(H.actions)do if a[1]~='upload' then n=n+1 end end;return n end
local function Writes() local n=0;for _,c in pairs(writes) do n=n+c end;return n end
local function Auto() return Nexus.RecomputeStats().autoEnabled==true end
local function Stored(where)
 local s=Nexus.Store.State()
 if where=='first' then return s.firstRunWishlist end
 return s.loadoutWishlists and s.loadoutWishlists[where]
end
local function Facts()
 local s=Nexus.Store.State() or {};local links=type(s.loadoutWishlists)=='table' and s.loadoutWishlists or {}
 local out={}
 for slot=1,6 do local r=links[slot]
  out[#out+1]=slot..'='..(type(r)=='table' and (tostring(r.name)..'/'..tostring(r.assignmentId)) or tostring(r)) end
 local f=s.firstRunWishlist
 out[#out+1]='first='..(type(f)=='table' and (tostring(f.name)..'/'..tostring(f.assignmentId)) or tostring(f))
 return table.concat(out,' ')
end
local function Copies(rec,id)
 if type(rec)~='table' then return nil end
 local n=0;for _,e in ipairs(rec.echoes or {})do if e.spellId==id then n=n+(e.stacks or 1) end end;return n
end
local function DraftCopies(id) return Copies({echoes=Ctrl().CanonicalEchoes()},id) end
-- The server lists an upload (a Create uploads to sentinel 0; the server
-- shows it in a designed slot above the declared Saved Builds).
local function MirrorAt(slot,last)
 local rows=H.Clone(H.perks.serverBuildSlots or {});rows[slot]={name=last[3],verified=false,echoes=H.Clone(last[4])}
 H.perks.serverBuildSlots=rows;H.Notify();A.Poll();H.Advance(4)
end
local function Heard(fn)
 local heard,realPrint={},print
 print=function(...) heard[#heard+1]=tostring((...));realPrint(...) end
 local ok,err=pcall(fn)
 print=realPrint
 assert(ok,err)
 return table.concat(heard,' / ')
end
-- The editor's visible result line: a shown text of the editor frame itself
-- that reports a save outcome (found by what it says, not by a field name).
local function ResultRow()
 if not NexusEditorFrame then return nil end
 for _,r in ipairs(NexusEditorFrame.regions) do
  if r.kind=='FontString' and r:IsVisible() then
   local t=V.Plain(r:GetText() or '')
   if t:find('^Saved') or t:find('^Uploaded') or t:find('^Not saved') then return t,r end
  end
 end
 return nil
end
-- The hover lines of the result line (the mouse area laid over it).
local function ResultHover()
 local _,r=ResultRow()
 if not r then return nil end
 for _,f in ipairs(NexusEditorFrame.children) do
  local p=f.points and f.points[1]
  if f.kind=='Frame' and p and p[2]==r and f:GetScript('OnEnter') then
   local lines=V.TooltipLines(function() f:GetScript('OnEnter')(f) end)
   return V.Plain(table.concat(lines,'\n'))
  end
 end
 return nil
end
local function AssignNowButton()
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and f:GetParent()==NexusEditorFrame
   and V.Plain(f:GetText() or ''):find('^Assign now') then return f end
 end
 return nil
end
-- The game's Character Progression entry and Echo Journal frame, as the
-- Journal route opens them (synthetic frames; the route itself is real).
local function JournalHost()
 local journal=_G.ProjectEbonholdEchoJournal or CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
 journal:Hide()
 local micro=_G.EchoJournalMicroButton or CreateFrame('Button','EchoJournalMicroButton',UIParent)
 micro:SetScript('OnClick',function() journal:Show() end)
 return journal
end
local function VisibleButton(text)
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f:GetText()==text then return f end end
 return nil
end
local function PickerRow(name)
 local picker=_G.NexusWishlistOnlyPicker
 for _,row in ipairs(picker and picker.children or {}) do
  if row.nameButton and row:IsVisible() and tostring(row.nameButton.text:GetText() or ''):find(name,1,true) then return row end
 end
 return nil
end
local function Close() if NexusEditorFrame and NexusEditorFrame:IsShown() then Nexus.WishlistEditor.Toggle() end end
local function Quiet(tag,before)
 C.guard(Others()==before.others and spends==0 and Auto()==before.auto,
  tag..': no Saved Build activation or save, roll, lock, tome or Orb call; Auto unchanged',
  'others='..Others()..' spends='..spends..' auto='..tostring(Auto()))
end
local function State() return {others=Others(),auto=Auto(),sent=#H.sent,uploads=Uploads(),writes=Writes(),facts=Facts()} end
-- Bound to Saved Build 6 (W-Six) with Saved Build `active` active.
local function BoundWorld(active)
 Boot({active=active,slots=Worlds()})
 Assign(6,'W-Six',E6);H.Notify();A.Poll();H.Advance(1)
 Nexus.WishlistEditor.OpenForWishlist((function()
  for _,c in ipairs(A.GetWishlistCandidates())do if c.slot==106 then return c end end end)(),6)
 C.setup(Ctx().loadoutSlot==6 and Ctx().name=='W-Six','fixture: W-Six is open for Saved Build 6',Ctx().name)
end
local function SaveEdit(id)
 selected(id).plus:Click()
 button('Save Wishlist'):Click()
 C.setup(H.popup and H.popup.which=='WISHLISTREALIZER_UPDATE_WISHLIST','fixture: Save asks for confirmation')
 return H.AcceptPopup()
end

C.scenario('A01/A11/A12 Create for the captured Saved Build',function()
 Boot({active=2,slots=Worlds()})
 SlashCmdList.NEXUS('editor')
 local target=Ctrl().CreateTargetContext()
 C.setup(NexusEditorFrame and NexusEditorFrame:IsShown() and target and target.loadoutSlot==2,
  'A01: fixture: a new draft captured Saved Build 2 (Fire PvE)')
 local before=State()
 NexusWishlistNameInput:SetText('CAster');ClickCatalog(201175)
 button('Create Wishlist'):Click()
 C.setup(H.popup and H.popup.which=='WISHLISTREALIZER_CREATE_WISHLIST','A01: fixture: Create asks for confirmation')
 local said=Heard(function() H.AcceptPopup() end)
 local n,last=Uploads()
 C.guard(n==before.uploads+1,'A01: exactly one upload',n)
 C.guard(writes.SetLoadoutWishlistIdentity==1 and Writes()==1,'A01: one assignment, by the existing Create writer only',Writes())
 C.guard(Stored(2) and Stored(2).name=='CAster','A01: Saved Build 2 holds CAster, as Create already did',Facts())
 C.guard(said:find('Wishlist saved',1,true)~=nil,'A01: the existing chat lines are kept',said)
 local row=ResultRow()
 print('OBSERVED','A01 row='..tostring(row))
 C.expect(row~=nil and row:find('^Saved')~=nil and row:find('Assigned to',1,true)~=nil and V.Names(row,'Fire PvE')
  and row:find('slot 2',1,true)~=nil and not row:find('Not assigned',1,true),
  'A01: a persistent result names the accepted assignment to Saved Build Fire PvE (slot 2)',row)
 C.expect(row~=nil and AssignNowButton()==nil,'A01: no Assign now after an accepted assignment')
 for _=1,3 do Nexus.WishlistEditor.Refresh() end
 H.Advance(2)
 C.expect(row~=nil and ResultRow()==row,'A01: repeated refreshes keep the same result',ResultRow())
 MirrorAt(108,last)
 C.expect(row~=nil and ResultRow()==row,'A01: the server listing the new Wishlist keeps the result',ResultRow())
 C.guard(Uploads()==n and Writes()==1,'A01: no further upload or assignment from refreshing',Writes())
 Quiet('A01',before)
 -- Another Create of the same draft, cancelled: nothing happens (A07).
 local mid=State()
 button('Create Wishlist'):Click()
 C.setup(H.popup~=nil,'A07: fixture: the confirmation is open')
 StaticPopupDialogs[H.popup.which].OnCancel(H.popup.frame,H.popup.data);H.popup=nil
 C.guard(Uploads()==mid.uploads and Writes()==mid.writes and #H.sent==mid.sent and Facts()==mid.facts
  and not Nexus.WishlistEditor.IsApplyPending(),'A07: cancelling Create uploads, assigns, sends and queues nothing')
 Quiet('A07',mid)
 C.expect(row~=nil and ResultRow()==row,'A07: cancelling keeps the current result',ResultRow())
 -- A11: a real edit retires the result; a passive refresh does not restore it.
 selected(201175).plus:Click()
 C.expect(row~=nil and ResultRow()==nil,'A11: a real draft edit retires the result',ResultRow())
 H.Advance(1);Nexus.WishlistEditor.Refresh()
 C.expect(row~=nil and ResultRow()==nil,'A11: a passive refresh does not restore it',ResultRow())
 Close()
end)

C.scenario('A03/A11 bound Save of an inactive Saved Build',function()
 BoundWorld(1)
 local before=State()
 SaveEdit(201173)
 local n,last=Uploads()
 C.guard(n==before.uploads+1 and last[2]==106,'A03: one upload to W-Six\'s own server Wishlist',n)
 C.guard(Stored(6).name=='W-Six' and Copies(Stored(6),201173)==2 and writes.UpdateWishlistAssociationAfterSave==1
  and Writes()==1,'A03: the bound Save updates only Saved Build 6, as before',Facts())
 C.guard(H.perks.serverActiveSlot==1 and A.Slots().activeSlot==1,'A03: the inactive Saved Build stays inactive')
 local row=ResultRow()
 print('OBSERVED','A03 row='..tostring(row))
 C.expect(row~=nil and row:find('^Saved')~=nil and row:find('Assigned to',1,true)~=nil and V.Names(row,'Six')
  and row:find('slot 6',1,true)~=nil and not V.Names(row,'One'),
  'A03: the result names Saved Build Six (slot 6), never the active One',row)
 MirrorAt(106,last)
 C.expect(row~=nil and ResultRow()==row,'A03: the mirrored save keeps the result',ResultRow())
 Quiet('A03',before)
 -- A refused edit (an Echo that is already locked) does not retire it.
 H.locked={{spellId=200767,stacks=1}};H.Notify();A.Poll();H.Advance(1)
 local shown=ResultRow()
 C.setup(Ctrl().LockedProjection() and Ctrl().LockedProjection().bySpell[200767]==1,'A11: fixture: Echo Lock is locked')
 local said=Heard(function() ClickCatalog(200767) end)
 C.setup(said:find('already locked',1,true)~=nil,'A11: fixture: adding the locked Echo is refused',said)
 C.expect(shown~=nil and ResultRow()==shown,'A11: a refused edit keeps the result',ResultRow())
 -- Choosing another Saved Build in the selector replaces the context.
 Close()
end)

C.scenario('A04/A07/A08/A12 unbound save, then Assign now through the Journal picker',function()
 BoundWorld(6)
 NexusWishlistEditorSwitchButton:Click();menuRow('W-Free'):Click()
 C.setup(Ctx().name=='W-Free' and Ctx().loadoutSlot==nil,'A04: fixture: W-Free (no Saved Build) is open')
 local before=State()
 local said=Heard(function() SaveEdit(201174) end)
 local n,last=Uploads()
 local yellow=said:find('not assigned',1,true)
 local green=said:find('Wishlist saved',1,true)
 C.guard(yellow~=nil and green~=nil and yellow<green,'A04: the chat shows the not-assigned notice and then the generic saved line',said)
 C.guard(n==before.uploads+1 and last[2]==107 and Writes()==before.writes and Facts()==before.facts,
  'A04: one upload of W-Free, no assignment fallback, assignments unchanged',Facts())
 local row=ResultRow()
 print('OBSERVED','A04 row='..tostring(row))
 C.expect(row~=nil and row:find('^Saved')~=nil and row:find('Not assigned',1,true)~=nil and V.Names(row,'W-Free')
  and not row:find('Assigned to',1,true),'A04: the result says W-Free was saved but is not assigned',row)
 local hover=ResultHover() or ''
 C.expect(hover:find('rolled copies planned',1,true)~=nil and hover:find('not owned Echoes',1,true)~=nil,
  'A04: the count is qualified as planned, not owned',hover)
 C.expect(row~=nil and AssignNowButton()~=nil,'A04: Assign now is offered for the saved, unassigned plan')
 H.Advance(2);Nexus.WishlistEditor.Refresh()
 C.expect(row~=nil and ResultRow()==row,'A04: the generic green line and refreshes do not replace the unassigned result',ResultRow())
 MirrorAt(107,last)
 local journal=JournalHost()
 local btn=AssignNowButton()
 if not btn then C.expect(false,'A08: Assign now is available to click');return end
 local open=State()
 btn:Click()
 C.expect(not NexusEditorFrame:IsShown() and journal:IsShown() and _G.NexusActiveWishlistSelector~=nil
  and NexusActiveWishlistSelector:IsVisible(),'A08: Assign now opens the Echo Journal with its Wishlist selector')
 C.guard(Uploads()==open.uploads and Writes()==open.writes and #H.sent==open.sent and Facts()==open.facts,
  'A08: opening Assign now uploads, assigns and sends nothing')
 Quiet('A08 open',open)
 if not (_G.NexusActiveWishlistSelector and NexusActiveWishlistSelector:IsVisible()) then return end
 NexusActiveWishlistSelector:Click()
 C.setup(NexusWishlistOnlyPicker and NexusWishlistOnlyPicker:IsShown(),'A08: fixture: the picker opens')
 C.guard(Writes()==open.writes and Facts()==open.facts,'A08: opening the picker assigns nothing')
 NexusActiveWishlistSelector:Click()
 C.guard(not NexusWishlistOnlyPicker:IsShown() and Writes()==open.writes and Facts()==open.facts,
  'A07: closing the picker assigns nothing')
 NexusActiveWishlistSelector:Click()
 local pick=PickerRow('W-Free')
 C.setup(pick~=nil,'A08: fixture: the picker lists W-Free')
 if not pick then return end
 pick.nameButton:Click()
 C.guard(writes.SetLoadoutWishlist==1 and Writes()==open.writes+1 and Stored(6) and Stored(6).name=='W-Free',
  'A08: only the explicit picker choice assigns, through the existing picker writer',Facts())
 C.guard(Uploads()==open.uploads,'A08: Assign now never uploads again')
 Quiet('A08 choose',open)
 SlashCmdList.NEXUS('editor')
 C.expect(ResultRow()==nil,'A11: the reopened editor shows no result of the earlier save',ResultRow())
 Close()
end)

C.scenario('A05/A10 upload accepted, assignment refused; Assign now never uploads',function()
 Boot({active=2,slots=Worlds()})
 SlashCmdList.NEXUS('editor')
 C.setup(Ctrl().CreateTargetContext() and Ctrl().CreateTargetContext().loadoutSlot==2,'A05: fixture: draft captured Saved Build 2')
 local before=State()
 -- Host race: the server reports Saved Build 2 empty while the upload is
 -- in flight, so the assignment after the upload is refused.
 local upload=H.service.UploadServerBuildSlot
 H.service.UploadServerBuildSlot=function(...)
  local ok=upload(...)
  local rows=H.Clone(H.perks.serverBuildSlots);rows[2]={name='Fire PvE',verified=true,echoes={}}
  H.perks.serverBuildSlots=rows
  return ok
 end
 NexusWishlistNameInput:SetText('CAster');ClickCatalog(201175)
 button('Create Wishlist'):Click();C.setup(H.popup~=nil,'A05: fixture: Create asks for confirmation')
 local said=Heard(function() H.AcceptPopup() end)
 H.service.UploadServerBuildSlot=upload
 local n,last=Uploads()
 C.guard(n==before.uploads+1,'A05: exactly one upload',n)
 C.guard(said:find('assignment failed',1,true)~=nil and not said:find('Wishlist saved',1,true),
  'A05: the assignment failure returns before the generic saved line',said)
 C.guard(Stored(2)==nil and Facts()==before.facts,'A05: nothing is assigned anywhere (no slot-1 or first-run fallback)',Facts())
 local row=ResultRow()
 print('OBSERVED','A05 row='..tostring(row))
 C.expect(row~=nil and row:find('^Uploaded')~=nil and row:find('Not assigned',1,true)~=nil and V.Names(row,'CAster')
  and V.Names(row,'Fire PvE') and row:find('empty or not loaded',1,true)~=nil,
  'A05: a persistent partial result names the refused destination in plain words',row)
 C.expect(row~=nil and not row:find('Assigned to',1,true) and not row:find('association_incomplete',1,true)
  and not row:find('_',1,true),'A05: no full-success wording and no reason code',row)
 C.expect(row~=nil and AssignNowButton()~=nil,'A05: Assign now is offered as the safe next step')
 -- The server shows Saved Build 2 with Echoes again and lists the upload.
 local rows=H.Clone(H.perks.serverBuildSlots);rows[2]={name='Fire PvE',verified=true,echoes=E2}
 H.perks.serverBuildSlots=rows;MirrorAt(108,last)
 C.expect(row~=nil and ResultRow()==row,'A05: the partial result persists across refreshes',ResultRow())
 local journal=JournalHost()
 local btn=AssignNowButton()
 if not btn then C.expect(false,'A05: Assign now is available to click');return end
 -- The Journal would now assign to Saved Build 1: refused, never redirected.
 H.perks.serverActiveSlot=1;H.Notify();A.Poll();H.Advance(1)
 local mid=State()
 local refusal=Heard(function() btn:Click() end)
 C.expect(refusal:find('different Saved Build',1,true)~=nil and NexusEditorFrame:IsShown() and not journal:IsShown(),
  'A05: with another Saved Build targeted, Assign now refuses and opens nothing',refusal)
 C.guard(Uploads()==mid.uploads and Writes()==mid.writes and Facts()==mid.facts,'A05: the refusal uploads and assigns nothing')
 H.perks.serverActiveSlot=2;H.Notify();A.Poll();H.Advance(1)
 btn=AssignNowButton()
 C.setup(btn~=nil,'A05: fixture: Assign now is still offered')
 if not btn then return end
 btn:Click()
 C.expect(not NexusEditorFrame:IsShown() and journal:IsShown(),'A05: Assign now opens the Journal for Saved Build 2')
 C.guard(Uploads()==mid.uploads and Writes()==mid.writes,'A05: opening it uploads and assigns nothing')
 if not (_G.NexusActiveWishlistSelector and NexusActiveWishlistSelector:IsVisible()) then return end
 NexusActiveWishlistSelector:Click()
 local pick=PickerRow('CAster')
 C.setup(pick~=nil,'A05: fixture: the picker lists the uploaded CAster')
 if not pick then return end
 pick.nameButton:Click()
 C.guard(Stored(2) and Stored(2).name=='CAster' and writes.SetLoadoutWishlist==1,'A05: the explicit choice assigns CAster to Saved Build 2',Facts())
 C.guard(Uploads()==mid.uploads,'A05: the successful upload is never repeated')
 Quiet('A05',before)
end)

C.scenario('A06 refused upload',function()
 BoundWorld(6)
 local before=State()
 local upload=H.service.UploadServerBuildSlot
 H.service.UploadServerBuildSlot=function() return false end
 local pending=DraftCopies(201173)
 SaveEdit(201173)
 H.service.UploadServerBuildSlot=upload
 C.guard(Uploads()==before.uploads and Facts()==before.facts and Writes()==before.writes,'A06: nothing is uploaded or assigned')
 C.guard(DraftCopies(201173)==pending+1 and not Nexus.WishlistEditor.IsApplyPending(),'A06: the edits stay; nothing is pending')
 local row=ResultRow()
 print('OBSERVED','A06 row='..tostring(row))
 C.expect(row~=nil and row:find('^Not saved')~=nil and row:find('refused',1,true)~=nil
  and not row:find('Uploaded',1,true) and not row:find('Assigned',1,true),'A06: a not-saved result, distinct from a partial one',row)
 C.expect(row~=nil and AssignNowButton()==nil,'A06: no Assign now for a plan that was not saved')
 local hover=ResultHover() or ''
 C.expect(hover:find('edits are kept',1,true)~=nil,'A06: the result says the edits are kept',hover)
 Quiet('A06',before)
 Close()
end)

C.scenario('A10 spaced retry, a destination changed meanwhile, and a draft edited meanwhile',function()
 BoundWorld(6)
 local before=State()
 SaveEdit(201173)
 local first=ResultRow()
 C.expect(first~=nil and first:find('Assigned to',1,true)~=nil,'A10: the first save is assigned',first)
 -- The next save waits for the service spacing guard.
 SaveEdit(201173)
 C.setup(Nexus.WishlistEditor.IsApplyPending(),'A10: fixture: the next save waits for the spacing guard')
 C.expect(ResultRow()==nil,'A10: while it waits, no result claims it saved',ResultRow())
 Nexus.WishlistEditor.Refresh()
 C.guard(VisibleButton('Saving...')~=nil,'A10: the Save button reads Saving...')
 C.expect(first~=nil and ResultRow()==nil,'A10: a refresh while it waits shows no earlier result either',ResultRow())
 H.Advance(4)
 local retried=ResultRow()
 C.guard(Uploads()==before.uploads+2 and Copies(Stored(6),201173)==3,'A10: the retry uploads and assigns as before')
 C.expect(retried~=nil and retried:find('Assigned to',1,true)~=nil and V.Names(retried,'Six'),'A10: the retried save records its own result',retried)
 H.Advance(4)
 -- Spaced again; Saved Build 6 is given W-Free before the retry runs.
 SaveEdit(201173)
 SaveEdit(201173)
 C.setup(Nexus.WishlistEditor.IsApplyPending(),'A10: fixture: a save waits again')
 local u=Uploads()
 C.guard(A.SetLoadoutWishlist(6,107),'A10: Saved Build 6 explicitly given W-Free')
 H.Advance(4)
 local row=ResultRow()
 print('OBSERVED','A10 changed row='..tostring(row))
 C.guard(Uploads()==u and Stored(6).name=='W-Free','A10: the held save uploads nothing and W-Free is kept')
 C.expect(row~=nil and row:find('^Not saved')~=nil and V.Names(row,'Six')
  and row:find('assigned, unassigned or restored',1,true)~=nil and not row:find('Assigned to',1,true),
  'A10: the refused retry is shown as not saved, naming Saved Build Six',row)
 Close()
 -- Spaced, and the draft edited before the retry.
 BoundWorld(6)
 SaveEdit(201173);SaveEdit(201173)
 C.setup(Nexus.WishlistEditor.IsApplyPending(),'A10: fixture: a save waits')
 local held=Uploads()
 selected(201173).plus:Click()
 H.Advance(4)
 local edited=ResultRow()
 C.guard(Uploads()==held and not Nexus.WishlistEditor.IsApplyPending(),'A10: the held save of the older draft is not uploaded')
 C.expect(edited~=nil and edited:find('^Not saved')~=nil and edited:find('draft changed while the save waited',1,true)~=nil,
  'A10: the cancelled retry says so',edited)
 Close()
end)

C.scenario('A10 the destination changed during the host call (kept)',function()
 BoundWorld(6)
 local before=State()
 local upload=H.service.UploadServerBuildSlot
 H.service.UploadServerBuildSlot=function(...)
  local ok=upload(...)
  A.SetLoadoutWishlist(6,107)
  return ok
 end
 local said=Heard(function() SaveEdit(201173) end)
 H.service.UploadServerBuildSlot=upload
 C.guard(Uploads()==before.uploads+1 and Stored(6).name=='W-Free','A10: one upload; the newer choice W-Free is kept',Facts())
 C.guard(said:find('that choice is kept',1,true)~=nil and said:find('Wishlist saved',1,true)~=nil,
  'A10: the existing kept notice and generic line are printed',said)
 local row=ResultRow()
 print('OBSERVED','A10 kept row='..tostring(row))
 C.expect(row~=nil and row:find('^Saved')~=nil and row:find('Not assigned',1,true)~=nil
  and row:find('that choice is kept',1,true)~=nil and not row:find('Assigned to',1,true),
  'A10: the result says saved, not assigned, the newer choice kept',row)
 Close()
end)

C.scenario('A10 the editor changed during the host call (partial)',function()
 BoundWorld(6)
 local before=State()
 local upload=H.service.UploadServerBuildSlot
 H.service.UploadServerBuildSlot=function(...)
  local ok=upload(...)
  Ctrl().AddPending(Ctrl().CatalogProjection().rows[201172])
  return ok
 end
 local said=Heard(function() SaveEdit(201173) end)
 H.service.UploadServerBuildSlot=upload
 C.guard(Uploads()==before.uploads+1 and said:find('editor changed',1,true)~=nil,'A10: one upload; the existing partial notice',said)
 local row=ResultRow()
 print('OBSERVED','A10 editor-changed row='..tostring(row))
 C.expect(row~=nil and row:find('^Uploaded')~=nil and row:find('editor changed during the upload',1,true)~=nil
  and not row:find('Assigned to',1,true),'A10: the partial result says the editor changed during the upload',row)
 C.expect(row~=nil and AssignNowButton()==nil,'A10: no Assign now while the local targets were not updated')
 Close()
end)

C.scenario('A10 Store owner/root change hides an earlier result',function()
 BoundWorld(6)
 SaveEdit(201173)
 local row=ResultRow()
 C.setup(type(NexusDB)=='table','A10: fixture: the saved root exists')
 local db=NexusDB
 NexusDB=H.Clone(db)
 local shown=Ctrl().SaveResult and Ctrl().SaveResult(nil) or nil
 NexusDB=db
 C.expect(row~=nil and shown==nil,'A10: under another saved root the result is not offered')
 Nexus.WishlistEditor.Refresh()
 C.expect(row~=nil and ResultRow()==nil,'A10: and it does not come back',ResultRow())
 Close()
end)

C.finish('(persistent truthful save result; Assign now reuses the Journal picker and never uploads)')
