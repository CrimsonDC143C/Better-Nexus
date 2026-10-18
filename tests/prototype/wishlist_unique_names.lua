-- A NEW Wishlist never takes a name a Wishlist the player can already see has
-- (requested by the player alongside the repeated-Create report): it gets the
-- first free "Name (Copy 1)", "Name (Copy 2)", ... and the confirmation names
-- exactly what will be created. Names compare as a player tells them apart in a
-- list: the existing name sanitation (TrimName: no "|", trimmed), whitespace
-- runs as one space, ASCII A-Z without case (no Unicode case folding is
-- claimed). Existing suffixes, gaps, sanitised names, the name-field length,
-- retained plans, an unloaded server list, and a Create the server does not
-- list yet are accounted for; a name taken after the confirmation is refused,
-- never silently renamed. Existing Wishlists, duplicate names included, and
-- every assignment are untouched; Save to an opened Wishlist keeps its name.
-- Categories (tests/prototype/view_regression_support.lua): EXPECT fails on the
-- unpatched delivered1704 and current product (it uploads the typed name);
-- GUARD already holds there and must keep holding; SETUP is the fixture.
-- Real TOC boot, adapter, controller, editor button, Copy and Import entry
-- points and the editor's own StaticPopup handlers; the host services are the
-- synthetic harness. The oracle is the confirmation title and the name the host
-- upload call receives. No result row is needed (delivered1704 has none); the
-- one result-row check runs only where the product has one.
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('wishlist_unique_names')
local H,A,writes
local E1={{spellId=201172,quality=0,stacks=1}}
local E2={{spellId=201175,quality=0,stacks=1}}
local E6={{spellId=201173,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}
local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity',
 'SetFirstLoadoutWishlistIdentity','UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist',
 'ClearFirstRunWishlist','SetFirstRunWishlistIdentity'}
local LONG=string.rep('L',96)

local function World(extra)
 local rows={[1]={name='One',verified=true,echoes=E1},[2]={name='Fire PvE',verified=true,echoes=E2},
  [6]={name='Six',verified=true,echoes=E6},
  [106]={name='W-Six',verified=false,echoes=E6},[107]={name='W-Free',verified=false,echoes=EF}}
 for slot,name in pairs(extra or {}) do rows[slot]={name=name,verified=false,echoes=EF} end
 return rows
end

local function Boot(o)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil;EchoJournalMicroButton=nil
 NexusEditorFrame=nil;NexusWishlistNameInput=nil;NexusWishlistEditorSwitchButton=nil
 NexusActiveWishlistSelector=nil;NexusWishlistOnlyPicker=nil;NexusWishlistAssignNowButton=nil
 NexusLoadoutAssociationPanel=nil;NexusWishlistRolePicker=nil;NexusWishlistRoleConfirm=nil
 NexusWishlistRoleUseOwned=nil;NexusWishlistRoleCancel=nil
 H=dofile('tests/prototype/harness.lua')
 H.playerLevel=80
 wipe(H.db)
 H.AddEcho(201172,'Echo One',0,5);H.AddEcho(201173,'Echo Six',0,5);H.AddEcho(201174,'Echo Free',0,5)
 H.AddEcho(201175,'Echo Fire',0,5)
 H.service.GetServerMaxSlots=function() return 6 end
 H.perks.serverBuildSlots=H.Clone(o.slots)
 H.perks.serverActiveSlot=o.active
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,GetCharges=function()return 0 end,
  IsOfferPending=function()return false end,RequestCharges=function()end,ConfirmSpend=function()return false end}
 H.Boot();A=Nexus.GameAdapter
 H.Notify();A.Poll();H.Advance(1)
 writes={}
 for _,k in ipairs(WRITERS) do
  local real=A[k]
  if type(real)=='function' then
   writes[k]=0
   A[k]=function(...) writes[k]=writes[k]+1;return real(...) end
  end
 end
end

local function Ctrl()
 local show=Nexus.WishlistEditor and Nexus.WishlistEditor.Show
 for i=1,255 do local n,v=debug.getupvalue(show,i);if not n then break end
  if n=='wishlistController' then return v end end
 return nil
end
local function Creates()
 local n=0;for _,a in ipairs(H.actions) do if a[1]=='upload' and a[2]==0 then n=n+1 end end;return n
end
local function LastUpload()
 local last;for _,a in ipairs(H.actions) do if a[1]=='upload' then last=a end end;return last
end
local function Writes() local n=0;for _,c in pairs(writes) do n=n+c end;return n end
local function Facts()
 local s=Nexus.Store.State() or {};local links=type(s.loadoutWishlists)=='table' and s.loadoutWishlists or {}
 local out={}
 for slot=1,6 do local r=links[slot]
  out[#out+1]=slot..'='..(type(r)=='table' and (tostring(r.name)..'/'..tostring(r.assignmentId)) or tostring(r)) end
 local f=s.firstRunWishlist
 out[#out+1]='first='..(type(f)=='table' and (tostring(f.name)..'/'..tostring(f.assignmentId)) or tostring(f))
 return table.concat(out,' ')
end
-- Every server row's name, in slot order (what the server lists).
local function ServerNames()
 local slots,out={},{}
 for slot in pairs(H.perks.serverBuildSlots or {}) do slots[#slots+1]=slot end
 table.sort(slots)
 for _,slot in ipairs(slots) do out[#out+1]=slot..'='..tostring(H.perks.serverBuildSlots[slot].name) end
 return table.concat(out,' ')
end
local function Name(text) NexusWishlistNameInput:SetText(text) end
local function ClickCatalog(id)
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f.status and f.data and f.data.spellId==id then f:Click();return true end end
 error('visible catalog row absent: '..id)
end
local function selected(id)
 for _,f in ipairs(H.frames)do if f:IsVisible() and f.plus and f.data and f.data.spellId==id then return f end end
 error('visible selected row absent: '..id)
end
-- M3: the editor's apply button names its effect (Create & assign, Create
-- unassigned, Save & assign, Save changes; legacy Create Wishlist / Save
-- Wishlist). It is created before the Save changes alternative beside it,
-- so it is the first match.
local APPLY_LABELS={['Create Wishlist']=true,['Save Wishlist']=true,['Saved']=true,['Saving...']=true,
 ['Create & assign']=true,['Create unassigned']=true,['Save & assign']=true,['Save changes']=true}
local function ApplyButton()
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and f:GetParent()==NexusEditorFrame then
   local t=V.Plain(f:GetText() or '')
   if APPLY_LABELS[t] then return f end
  end
 end
 error('the editor Create/Save button is absent')
end
local function Click()
 local before=H.popup
 ApplyButton():Click()
 if H.popup~=nil and H.popup~=before then return H.popup end
 return nil
end
local function Accept(p)
 if not p then return nil end
 if H.popup==p then H.popup=nil end
 return StaticPopupDialogs[p.which].OnAccept(p.frame,p.data)
end
local function Heard(fn)
 local heard,realPrint={},print
 print=function(...) heard[#heard+1]=tostring((...));realPrint(...) end
 local ok,err=pcall(fn)
 print=realPrint
 assert(ok,err)
 return V.Plain(table.concat(heard,' / '))
end
-- The confirmation's second line(s), as shown (delivered1704 passes a count).
local function Asked(p) return p and V.Plain(tostring(p.arg2 or '')) or '' end
-- The editor's visible result line, where the product has one.
local function ResultRow()
 if not NexusEditorFrame then return nil end
 for _,r in ipairs(NexusEditorFrame.regions) do
  if r.kind=='FontString' and r:IsVisible() then
   local t=V.Plain(r:GetText() or '')
   if t:find('^Saved') or t:find('^Uploaded') or t:find('^Not saved') then return t end
  end
 end
 return nil
end
-- Type `typed` into a fresh draft (New Wishlist) holding `id`, press Create;
-- the confirmation, or nil.
local function NewDraft(typed,id)
 Nexus.WishlistEditor.NewWishlist()
 Name(typed);ClickCatalog(id or 201175)
 return Click()
end
-- Press Create on a draft typed `typed` and check that the confirmation and
-- the upload both carry `want` (a GUARD when that is the typed name itself).
local function CreatesAs(tag,typed,want,id)
 local before=Creates()
 local p=NewDraft(typed,id)
 C.setup(p~=nil and p.which=='WISHLISTREALIZER_CREATE_WISHLIST',tag..': fixture: Create asks for confirmation')
 local title=p and p.arg1
 print('OBSERVED',tag..' typed="'..typed..'" title="'..tostring(title)..'"')
 local check=typed==want and C.guard or C.expect
 check(title==want,tag..': the confirmation names "'..want..'"',title)
 Accept(p)
 local last=LastUpload()
 C.setup(Creates()==before+1,tag..': fixture: the Create uploads once',Creates())
 check(last and last[3]==want,tag..': the new Wishlist is uploaded as "'..want..'"',last and last[3])
 C.guard(last and title~=nil and last[3]==title,tag..': what is uploaded is what the confirmation named',last and last[3])
 H.Advance(4)
 return p
end

C.scenario('U1 taken names, existing suffixes, gaps, case, whitespace, sanitation, length, retained plans',function()
 Boot({active=2,slots=World({[108]='Dup',[109]='dup (copy 1)',[110]='Dup (Copy 3)',[111]='Big  Plan',
  [112]='Pipe',[113]=LONG,[114]='Gap',[115]='Gap (Copy 2)',[116]='Twin',[117]='Twin'})})
 local ok,why=A.SetLoadoutWishlistIdentity(1,'Kept plan',H.Clone(E1))
 C.setup(ok,'U1: fixture: a retained plan Kept plan that the server does not list',why)
 local kept=(Nexus.Store.State().loadoutWishlists or {})[1]
 local keptId=kept and kept.assignmentId
 SlashCmdList.NEXUS('editor')
 local servers=ServerNames()
 -- A free name is kept exactly.
 CreatesAs('U1 free','Brand new','Brand new')
 -- Dup and dup (copy 1) are taken (case), Dup (Copy 3) too: the first free is 2.
 local p=CreatesAs('U1 taken','Dup','Dup (Copy 2)')
 local asked=Asked(p)
 local line=asked:match('[^\n]*already exists[^\n]*') or ''
 C.expect(line:find("A Wishlist named 'Dup' already exists",1,true)~=nil
  and line:find("'Dup (Copy 2)'",1,true)~=nil and line:find('keep their names',1,true)~=nil
  and not line:find('slot',1,true) and not line:lower():find('first-run',1,true),
  'U1: the confirmation says why the new Wishlist gets a copy name (and guesses no slot)',asked)
 -- The typed name stays in the field; the editor's result still describes the save.
 if Ctrl() and Ctrl().SaveResult then
  local row=ResultRow()
  C.expect(row~=nil and row:find('^Saved')~=nil and row:find("'Dup (Copy 2)'",1,true)~=nil,
   'U1: the result names the Wishlist that was created',row)
 else
  print('OBSERVED','U1 result row: not in this product (delivered1704); not checked')
 end
 -- A typed copy name counts from its base, never nesting a suffix; the Create
 -- above (not listed by the server yet) is counted too.
 CreatesAs('U1 suffix','Dup (Copy 1)','Dup (Copy 4)')
 -- Whitespace runs and case: "  big plan " is "Big  Plan".
 CreatesAs('U1 spacing','  big plan ','big plan (Copy 1)')
 -- The removed "|" is part of the existing sanitation: "Pi|pe" is "Pipe".
 CreatesAs('U1 sanitised','Pi|pe','Pipe (Copy 1)')
 -- A gap is reused.
 CreatesAs('U1 gap','Gap','Gap (Copy 1)')
 -- A retained plan's name counts although the server does not list it.
 CreatesAs('U1 retained','Kept plan','Kept plan (Copy 1)')
 -- A full-length name: the generated name still fits the 96-letter field.
 local q=CreatesAs('U1 length',LONG,string.rep('L',87)..' (Copy 1)')
 C.guard(q and #tostring(q.arg1)<=96,'U1: the offered name fits the name field',q and #tostring(q.arg1))
 -- Existing Wishlists keep their names, duplicates included; assignments are
 -- changed only by the Creates' own captured destination (Saved Build 2).
 C.guard(ServerNames()==servers,'U1: no server Wishlist is renamed, merged or removed',ServerNames())
 local s=Nexus.Store.State().loadoutWishlists or {}
 C.guard(s[1] and s[1].name=='Kept plan' and s[1].assignmentId==keptId,
  'U1: the retained plan Kept plan keeps its name and identity',Facts())
end)

C.scenario('U2 a Create the server does not list yet, and a name taken after the confirmation',function()
 Boot({active=2,slots=World()})
 SlashCmdList.NEXUS('editor')
 CreatesAs('U2 first','Fresh','Fresh')
 -- The server has not listed Fresh yet; a New draft of the same name.
 CreatesAs('U2 unlisted','Fresh','Fresh (Copy 1)')
 -- The confirmation names Late; the server then lists a Late from elsewhere.
 local before=Creates()
 local p=NewDraft('Late')
 C.setup(p~=nil and p.arg1=='Late','U2: fixture: the confirmation names Late',p and p.arg1)
 local rows=H.Clone(H.perks.serverBuildSlots);rows[120]={name='Late',verified=false,echoes=H.Clone(EF)}
 H.perks.serverBuildSlots=rows;H.Notify();A.Poll()
 local said=Heard(function() Accept(p) end)
 print('OBSERVED','U2 late accept said='..said..' creates='..(Creates()-before))
 C.expect(Creates()==before,'U2: a name taken after the confirmation is not uploaded',LastUpload() and LastUpload()[3])
 C.expect(said:find('now exists',1,true)~=nil,'U2: the refusal says the name is taken now',said)
 C.guard(not Nexus.WishlistEditor.IsApplyPending(),'U2: nothing is queued')
 local again=Click()
 C.expect(again~=nil and again.arg1=='Late (Copy 1)','U2: the next Create names the copy it will create',again and again.arg1)
 Accept(again)
 C.expect(Creates()==before+1 and LastUpload()[3]=='Late (Copy 1)','U2: and creates it',LastUpload() and LastUpload()[3])
 H.Advance(4)
 -- The same draft pressed again generates no further copy name.
 local third=Click();if third then Accept(third) end
 H.Advance(4)
 C.expect(Creates()==before+1,'U2: pressing Create again makes no second copy of the same draft',Creates()-before)
end)

C.scenario('U3 the server list is not loaded: the name is kept and the confirmation says it was not checked',function()
 Boot({active=2,slots=World({[108]='Unloaded plan'})})
 H.perks.serverBuildSlots=nil;H.Notify();A.Poll();H.Advance(1)
 SlashCmdList.NEXUS('editor')
 local p=NewDraft('Unloaded plan')
 C.setup(p~=nil,'U3: fixture: Create asks for confirmation')
 local asked=Asked(p)
 print('OBSERVED','U3 confirmation='..asked)
 C.guard(p and p.arg1=='Unloaded plan','U3: with nothing to compare, the typed name is kept',p and p.arg1)
 C.expect(asked:find('could not be checked',1,true)~=nil,'U3: the confirmation says existing names could not be checked',asked)
 C.guard(not asked:find('slot',1,true) and not asked:lower():find('first-run',1,true),
  'U3: and guesses no slot and no first-run target',asked)
 Accept(p)
 C.guard(Creates()==1 and LastUpload()[3]=='Unloaded plan','U3: the Create is not blocked by the unloaded list',LastUpload() and LastUpload()[3])
end)

C.scenario('U4 Copy and Import of a taken name; resolution writes nothing; Save keeps an opened name',function()
 Boot({active=6,slots=World({[108]='Twin',[109]='Twin',[110]='Dup',[111]='w-six'})})
 local ok,why=A.SetLoadoutWishlistIdentity(6,'W-Six',H.Clone(E6))
 C.setup(ok,'U4: fixture: Saved Build 6 is assigned W-Six',why)
 H.Notify();A.Poll();H.Advance(1)
 local servers=ServerNames()
 -- Save of the opened W-Six (another row is named w-six): its own name, its own slot.
 for _,c in ipairs(A.GetWishlistCandidates()) do if c.slot==106 then Nexus.WishlistEditor.OpenForWishlist(c,6) end end
 local c=Ctrl()
 local ctx=c and c.EditingContext and c.EditingContext() or {}
 C.setup(ctx.name=='W-Six' and ctx.slot==106,'U4: fixture: W-Six is open',ctx.name)
 selected(201173).plus:Click()
 local p=Click()
 C.setup(p~=nil and p.which=='WISHLISTREALIZER_UPDATE_WISHLIST','U4: fixture: Save asks for confirmation')
 -- The confirmation's own payload (what OnAccept submits) and the text the
 -- client shows (the dialog text with its show arguments), so this holds for
 -- either layout: delivered1704 passes the copy count first and the name
 -- second, the M1 dialog the name first.
 local shown=''
 if p then
  local d=StaticPopupDialogs[p.which] or {}
  local formatted,text=pcall(string.format,tostring(d.text or ''),p.arg1,p.arg2)
  shown=formatted and V.Plain(text) or ''
 end
 C.guard(p and type(p.data)=='table' and p.data.name=='W-Six' and tonumber(p.data.slot)==106
  and shown:find("'W-Six'",1,true)~=nil,'U4: Save names the opened Wishlist as it is',
  p and type(p.data)=='table' and (tostring(p.data.name)..'/'..tostring(p.data.slot)..' | '..shown) or nil)
 Accept(p)
 local last=LastUpload()
 C.guard(last and last[2]==106 and last[3]=='W-Six','U4: Save uploads W-Six to its own server slot, never renamed',
  last and (tostring(last[2])..'/'..tostring(last[3])))
 H.Advance(4)
 -- Copy of a record named Twin.
 C.setup(Nexus.WishlistEditor.OpenForCandidate({title='Twin',echoes=H.Clone(E2)})==true,'U4: fixture: Copy opens a draft')
 local w,f=Writes(),Facts()
 p=Click()
 C.setup(p~=nil,'U4: fixture: the Copy asks for confirmation')
 C.guard(Writes()==w and Facts()==f and Creates()==0,'U4: resolving the name assigns and uploads nothing',Facts())
 print('OBSERVED','U4 copy title='..tostring(p and p.arg1))
 C.expect(p and p.arg1=='Twin (Copy 1)','U4: the Copy of Twin is offered as Twin (Copy 1)',p and p.arg1)
 Accept(p)
 C.expect(LastUpload() and LastUpload()[3]=='Twin (Copy 1)','U4: and uploaded under that name',LastUpload() and LastUpload()[3])
 H.Advance(4)
 -- Import of a code, named Dup.
 local code=Nexus.Codec.EncodeEBH1({{spellId=201175,quality=0,stacks=1,locked=false}},'MAGE','Dup')
 C.setup(type(code)=='string' and code:sub(1,6)~='EBH1::','U4: fixture: an import code')
 Nexus.WishlistEditor.ImportEBH1String(code,'Dup')
 p=Click()
 C.setup(p~=nil,'U4: fixture: the import asks for confirmation')
 print('OBSERVED','U4 import title='..tostring(p and p.arg1))
 C.expect(p and p.arg1=='Dup (Copy 1)','U4: the imported Dup is offered as Dup (Copy 1)',p and p.arg1)
 Accept(p)
 C.expect(LastUpload() and LastUpload()[3]=='Dup (Copy 1)','U4: and uploaded under that name',LastUpload() and LastUpload()[3])
 H.Advance(4)
 C.guard(ServerNames()==servers,'U4: the duplicate Twins and every other server Wishlist are untouched',ServerNames())
end)

C.scenario('U5 the copy-name rule itself: bounded, deterministic, whole UTF-8 characters',function()
 Boot({active=2,slots=World()})
 local factory=Nexus.WishlistModel
 local model=factory and factory.New and factory.New()
 local unique=model and model.UniqueName
 local key=model and model.NameKey
 C.expect(type(unique)=='function' and type(key)=='function','U5: the model publishes its name rule')
 if type(unique)~='function' or type(key)~='function' then return end
 local taken={}
 taken[key('Many')]=true
 for n=1,200 do taken[key('many (COPY '..n..')')]=true end
 C.expect(unique('Many',taken)=='Many (Copy 201)','U5: 200 taken copies: the next is Copy 201',unique('Many',taken))
 taken[key('Many (Copy 57)')]=nil
 C.expect(unique('Many',taken)=='Many (Copy 57)','U5: a gap is reused',unique('Many',taken))
 C.expect(unique('Free',taken)=='Free','U5: a free name is unchanged')
 C.expect(key(' A\tb  C ')=='a b c' and key('Pi|pe')=='pipe','U5: one documented comparison',key(' A\tb  C '))
 C.expect(key('\195\137t\195\169')~=key('\195\169t\195\169'),'U5: no Unicode case folding is claimed (only A-Z)')
 local wide=string.rep('\195\137',60) -- 60 letters, 120 bytes
 local got=unique(wide,{[key(wide)]=true})
 C.expect(type(got)=='string' and #got<=120 and got:sub(-9)==' (Copy 1)'
  and got:sub(1,-10)==string.rep('\195\137',55),'U5: a generated name is cut at whole characters to 120 bytes',got and #got)
end)

C.finish('(new Wishlists get deterministic copy names; existing records untouched)')
