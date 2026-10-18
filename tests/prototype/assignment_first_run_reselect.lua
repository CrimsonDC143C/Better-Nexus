-- Independent review probe: actual clean Create -> select same source -> Unassign.
-- Real product handlers; retained synthetic harness and services only.
local H=dofile('tests/prototype/harness.lua')
H.playerLevel=1;wipe(H.db)
H.AddEcho(201172,'Arcane Bombardment',0,5)
H.perks.serverActiveSlot=0;H.perks.serverBuildSlots={}
ProjectEbonhold.OrbService={IsStateKnown=function()return true end,
 GetCharges=function()return 0 end,IsOfferPending=function()return false end,
 RequestCharges=function()end,ConfirmSpend=function()error('review cannot spend')end}
H.Boot()
-- M3: the editor's actions are named by their effect; a legacy label also
-- finds the action with that default intent (new label first, then legacy).
local LABELS={['Create Wishlist']={'Create & assign','Create unassigned','Create Wishlist'},
 ['Save Wishlist']={'Save & assign','Save changes','Save Wishlist'}}
local function button(text)
 for _,label in ipairs(LABELS[text] or {text})do
  for _,f in ipairs(H.frames)do
   if f.kind=='Button' and f:IsVisible() and f:GetText()==label then return f end
  end
 end
 error('SETUP: missing visible button '..text)
end
local function journal()
 if not ProjectEbonholdEchoJournal then CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)end
 ProjectEbonholdEchoJournal:Show();Nexus.JournalTab.RefreshAssociations()
end
journal();button('New Wishlist'):Click()
local row
for _,f in ipairs(H.frames)do
 if f.kind=='Button' and f:IsVisible() and f.status and f.data and f.data.spellId==201172 then row=f;break end
end
assert(row,'SETUP: actual catalog row missing');row:Click()
local name='NEXUS-TEST-REVIEW-RESELECT-UNASSIGN'
NexusWishlistNameInput:SetText(name);button('Create Wishlist'):Click()
assert(H.popup and H.popup.which=='WISHLISTREALIZER_CREATE_WISHLIST','SETUP: create confirmation missing');H.AcceptPopup()
assert(#H.actions==1 and H.actions[1][1]=='upload','SETUP: expected one create upload')
H.perks.serverBuildSlots={[102]={name=name,verified=false,echoes=H.Clone(H.actions[1][4])}}
H.Notify();Nexus.GameAdapter.Poll();H.Advance(4);NexusEditorFrame:Hide()
assert(Nexus.GameAdapter.AssignedWishlist().state=='ready','SETUP: clean creation not ready')
local initial=Nexus.Store.State()
assert(initial.firstRunWishlist.assignmentId==initial.loadoutWishlists[1].assignmentId,'SETUP: initial handoff mismatch')
print('INITIAL',initial.firstRunWishlist.assignmentId,initial.loadoutWishlists[1].assignmentId)
journal();NexusActiveWishlistSelector:Click()
local offered
for _,r in ipairs(NexusWishlistOnlyPicker.children)do
 if r.nameButton and r.nameButton:IsVisible() and r.nameButton.text:GetText():find(name,1,true)then offered=r;break end
end
-- The selector names the created source, so the picker does not offer it again.
assert(not offered and NexusActiveWishlistSelector.text:GetText():find(name:sub(1,17),1,true),
 'the selected source is named on the selector, not offered again in the picker')
-- It is the only Wishlist: the picker says so on one line and Unassign follows.
local picker=NexusWishlistOnlyPicker
assert(picker.emptyRow and picker.emptyRow:IsVisible() and picker.emptyRow:GetText()=='No other wishlists found',
 'with only the selection, the picker says no other Wishlist exists: '..tostring(picker.emptyRow and picker.emptyRow:GetText()))
assert(picker:GetHeight()==26+24+24+6 and picker.clearRow:IsVisible() and select(3,picker.clearRow:GetPoint(1))==-48,
 'the note takes one row and Unassign sits below it: height '..tostring(picker:GetHeight()))
NexusActiveWishlistSelector:Click()
-- The same-source selection is still possible through the adapter call a
-- picker row makes; the guard below is about that state.
local same={}
for _,c in ipairs(Nexus.GameAdapter.GetWishlistCandidates())do if c.name==name then same[#same+1]=c end end
assert(#same==1,'SETUP: exactly one created source candidate: '..#same)
assert(Nexus.GameAdapter.SetFirstRunWishlist(same[1].slot,same[1]),'SETUP: same-source selection was refused')
assert(Nexus.GameAdapter.AssignedWishlist().state=='ready','SETUP: selector assignment did not resolve')
local before=Nexus.Store.State()
print('RESELECTED',before.firstRunWishlist.assignmentId,before.loadoutWishlists[1].assignmentId)
journal();NexusActiveWishlistSelector:Click()
assert(NexusWishlistOnlyPicker.clearRow:IsVisible(),'SETUP: actual Unassign row hidden')
NexusWishlistOnlyPicker.clearRow:Click()
local after=Nexus.Store.State()
print('CLEARED',Nexus.GameAdapter.AssignedWishlist().state,tostring(after.firstRunWishlist),after.loadoutWishlists[1] and after.loadoutWishlists[1].assignmentId)
assert(Nexus.GameAdapter.AssignedWishlist().state=='unassigned','first-run Unassign must resolve immediately')
assert(#H.actions==1,'reselect and Unassign must not mutate services')
H.perks.serverBuildSlots[1]={name='First saved build',verified=true,echoes=H.Clone(H.perks.serverBuildSlots[102].echoes)}
H.perks.serverActiveSlot=1;H.Notify();Nexus.GameAdapter.Poll();H.Advance(1)
local later=Nexus.GameAdapter.AssignedWishlist()
print('NUMBERED_TRANSITION',later.state,later.name,later.identity)
assert(later.state=='unassigned','explicit Unassign must not revive this source after a same-source picker selection and first Saved Build transition')
assert(#H.actions==1,'numbered observation must not mutate services')
print('PASS same-source picker selection, actual Unassign and numbered transition')
