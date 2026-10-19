-- Support for saved_build_wishlist_transition.lua. One synthetic world: three
-- populated Saved Builds (server slots 1-3), two native Wishlists in the
-- designed range above them (101, 102), Saved Build 1 active, and one Nexus plan
-- bound to that Saved Build through the real Journal picker click. The native
-- transitions only change what the synthetic server answers
-- (GetServerBuildSlots / GetServerActiveSlot); no native code is modelled.
-- Every capture here is read-only: a spy calls through to the real adapter
-- function and only records its arguments and results. Synthetic names and
-- Echo ids only; the support file of the report is never read or executed.
local F=dofile('tests/prototype/format5_support.lua')
local S={}
S.BUILD_A,S.BUILD_B,S.BUILD_C='Saved Build A','Saved Build B','Saved Build C'
S.SLOT_BY_NAME={[S.BUILD_A]=1,[S.BUILD_B]=2,[S.BUILD_C]=3}
S.PLAN_D,S.PLAN_S,S.TOME_LIST='Synthetic Plan D','Synthetic Plan S','Synthetic One Tome'
S.MIRROR_D,S.MIRROR_S,S.MIRROR_NEW=101,102,103
S.ECHO_1,S.ECHO_2,S.ECHO_3,S.ECHO_4=201172,200767,201173,201174
-- A tome-gated Echo, modelled as tome_wishlist_priority does (requiredSpell).
S.TOME,S.TOME_LEVER=201175,777175
-- The saved plan/association fields compared byte-for-byte (deterministic
-- serialization of the production Store.State() detached copy).
S.SAVED_FIELDS={'loadoutWishlists','firstRunWishlist','forgottenWishlists',
 'forgottenWishlist','lockDesignTargetsBySlot'}

local function pack(...) return {n=select('#',...),...} end
S.pack=pack

function S.Plain(text)
 return (tostring(text or ''):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''))
end

function S.Refresh(W) W.H.Notify();W.A.Poll();W.H.Advance(1) end

-- A fresh boot of the real TOC at `o.level`, with Saved Build 1 active.
function S.World(o)
 o=o or {}
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
 wipe(H.db)
 H.AddEcho(S.ECHO_1,'Synthetic Echo One',0,5)
 H.AddEcho(S.ECHO_2,'Synthetic Echo Two',0,5)
 H.AddEcho(S.ECHO_3,'Synthetic Echo Three',0,5)
 H.AddEcho(S.ECHO_4,'Synthetic Echo Four',0,5)
 H.AddEcho(S.TOME,'Synthetic Tome Echo',0,1)
 H.db[S.TOME].requiredSpell=S.TOME_LEVER
 H.names[S.TOME_LEVER]='Tome of Synthetic Tome Echo'
 H.perks.serverActiveSlot=1
 H.perks.serverBuildSlots={
  [1]={name=S.BUILD_A,verified=true,echoes={{spellId=S.ECHO_1,quality=0,stacks=1}}},
  [2]={name=S.BUILD_B,verified=true,echoes={{spellId=S.ECHO_2,quality=0,stacks=1}}},
  [3]={name=S.BUILD_C,verified=true,echoes={{spellId=S.ECHO_3,quality=0,stacks=1}}},
  [S.MIRROR_D]={name=S.PLAN_D,verified=false,echoes={
   {spellId=S.ECHO_1,quality=0,stacks=2},{spellId=S.ECHO_2,quality=0,stacks=1}}},
  [S.MIRROR_S]={name=S.PLAN_S,verified=false,echoes={
   {spellId=S.ECHO_3,quality=0,stacks=1},{spellId=S.ECHO_4,quality=0,stacks=1}}},
 }
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
 local status=Nexus.StartupStatus()
 assert(status.coreReady==true,'SETUP: start-up completed (coreReady): '..tostring(status.state))
 W.startup=tostring(status.state)
 return W
end

-- The real Journal refresh. RefreshAssociations is pcall-guarded, so the label
-- is cleared first: a refresh that failed cannot leave an older label behind.
function S.OpenJournal()
 if not ProjectEbonholdEchoJournal then CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent) end
 ProjectEbonholdEchoJournal:Show()
 if NexusLoadoutAssociationPanel and NexusLoadoutAssociationPanel.label then
  NexusLoadoutAssociationPanel.label:SetText('')
 end
 Nexus.JournalTab.RefreshAssociations()
 local panel=NexusLoadoutAssociationPanel
 assert(panel and panel:IsShown(),'SETUP: the Journal association panel is shown')
 local label=S.Plain(panel.label:GetText())
 assert(label~='','SETUP: the Journal refresh wrote its label')
 return label
end

-- The real selector button; returns the open picker (or nil) and the label.
function S.OpenPicker()
 local label=S.OpenJournal()
 if NexusWishlistOnlyPicker and NexusWishlistOnlyPicker:IsShown() then NexusActiveWishlistSelector:Click() end
 NexusActiveWishlistSelector:Click()
 local picker=NexusWishlistOnlyPicker
 return (picker and picker:IsShown()) and picker or nil,label
end

function S.PickerRow(name)
 local picker=NexusWishlistOnlyPicker
 if not picker then return nil end
 for _,row in ipairs(picker.children) do
  if row.nameButton and row:IsVisible()
   and S.Plain(row.nameButton.text:GetText()):find(name,1,true) then return row end
 end
end

function S.PickerNames()
 local out={}
 for _,row in ipairs(NexusWishlistOnlyPicker and NexusWishlistOnlyPicker.children or {}) do
  if row.nameButton and row:IsVisible() then out[#out+1]=S.Plain(row.nameButton.text:GetText()) end
 end
 return table.concat(out,' | ')
end

function S.Hover(W,frame)
 local enter=assert(frame:GetScript('OnEnter'),'SETUP: the control has a tooltip')
 enter(frame)
 local lines=W.tip
 local leave=frame:GetScript('OnLeave');if leave then leave(frame) end
 return lines
end

-- Chat notices (print and the chat frame) while fn runs. Never raises.
function S.Heard(W,fn)
 local heard,realPrint,chat0={},print,#W.H.chat
 print=function(...)
  local parts={}
  for i=1,select('#',...) do parts[#parts+1]=tostring((select(i,...))) end
  heard[#heard+1]=table.concat(parts,' ')
 end
 local ok,err=pcall(fn)
 print=realPrint
 for i=chat0+1,#W.H.chat do heard[#heard+1]=W.H.chat[i] end
 return heard,ok,err
end

function S.Said(heard,fragment)
 for _,line in ipairs(heard) do
  if S.Plain(line):find(fragment,1,true) then return line end
 end
end

-- Call-through spies on adapter entry points. A call is recorded before it
-- runs, so one that raises is reported as raised.
function S.Spy(A,names)
 local calls,saved={},{}
 for _,name in ipairs(names) do
  local real=A[name]
  if type(real)=='function' then
   saved[name]=real
   A[name]=function(...)
    local call={fn=name,args=pack(...)}
    calls[#calls+1]=call
    call.ret=pack(real(...))
    return unpack(call.ret,1,call.ret.n)
   end
  end
 end
 return calls,function() for name,real in pairs(saved) do A[name]=real end end
end

function S.Describe(calls)
 local out={}
 for _,c in ipairs(calls) do
  out[#out+1]=c.fn..'('..tostring(c.args[1])..','..tostring(c.args[2])..')->'
   ..(c.ret and (tostring(c.ret[1])..','..tostring(c.ret[2])) or 'raised')
 end
 return #out>0 and table.concat(out,'; ') or 'none'
end

function S.Saved()
 local state=Nexus.Store.State() or {}
 local out={}
 for _,field in ipairs(S.SAVED_FIELDS) do out[field]=F.Serialize(state[field]) end
 return out
end

function S.SameSaved(a,b)
 local diff={}
 for _,field in ipairs(S.SAVED_FIELDS) do if a[field]~=b[field] then diff[#diff+1]=field end end
 return #diff==0,table.concat(diff,',')
end

-- Each association destination, serialized: 'first' and 'loadout:<index>'.
function S.Destinations()
 local state=Nexus.Store.State() or {}
 local out={first=F.Serialize(state.firstRunWishlist)}
 if type(state.loadoutWishlists)=='table' then
  for index,record in pairs(state.loadoutWishlists) do
   out['loadout:'..tostring(index)]=F.Serialize(record)
  end
 end
 return out
end

function S.Changed(before,after)
 local keys,seen={},{}
 for k in pairs(before) do seen[k]=true end
 for k in pairs(after) do seen[k]=true end
 for k in pairs(seen) do if before[k]~=after[k] then keys[#keys+1]=k end end
 table.sort(keys)
 return keys
end

function S.ServerSavedBuilds(W)
 local rows=W.H.perks.serverBuildSlots or {}
 return F.Serialize({rows[1],rows[2],rows[3]})
end

function S.Plans(W)
 local out={}
 for _,plan in ipairs(W.A.RetainedWishlistPlans() or {}) do
  out[#out+1]=tostring(plan.associationIndex)..'='..tostring(plan.key)
 end
 table.sort(out)
 return table.concat(out,';'),#out
end

function S.Reachable(W,key)
 for _,c in ipairs(W.A.GetWishlistCandidates() or {}) do
  if c.key==key then return true end
 end
 return false
end

-- Service actions the selection must never take.
S.WRITE_ACTIONS={upload=true,save=true,activate=true}
function S.Writes(W)
 local n=0
 for _,a in ipairs(W.H.actions) do if S.WRITE_ACTIONS[a[1]] then n=n+1 end end
 return n
end
function S.Count(W,kind)
 local n=0
 for _,a in ipairs(W.H.actions) do if a[1]==kind then n=n+1 end end
 return n
end
function S.Last(W,kind)
 for i=#W.H.actions,1,-1 do if W.H.actions[i][1]==kind then return W.H.actions[i] end end
end

function S.Assigned(W)
 local a=W.A.AssignedWishlist() or {}
 return a,tostring(a.state)..'/'..tostring(a.name)..'/'..tostring(a.note)
end

function S.Incidents()
 local inc=Nexus.SupportIncidents
 local n=inc and inc.Count and inc.Count()
 if type(n)~='number' then return 'unavailable' end
 local latest=n>0 and inc.Latest and inc.Latest() or nil
 return tostring(n)..(latest and (' latest='..tostring(latest.operation)..'/'..tostring(latest.reason)) or '')
end

-- The initial ready binding, made by the real Journal picker click while Saved
-- Build 1 is the active slot. A second plan is associated with Saved Build 2
-- through the adapter (setup only): three Saved Builds, two desired plans.
function S.BindInitial(W)
 local picker,label=S.OpenPicker()
 assert(label:find(S.BUILD_A,1,true),'SETUP: the Journal names the active Saved Build: '..label)
 assert(picker,'SETUP: the real Journal selector opens its picker')
 local row=assert(S.PickerRow(S.PLAN_D),'SETUP: the picker lists '..S.PLAN_D..': '..S.PickerNames())
 local heard,ok,err=S.Heard(W,function() row.nameButton:Click() end)
 assert(ok,'SETUP: the in-range picker click raised: '..tostring(err))
 local a,desc=S.Assigned(W)
 assert(a.name==S.PLAN_D and a.state~='restoring' and a.state~='unassigned' and a.state~='unavailable',
  'SETUP: the in-range Journal click binds '..S.PLAN_D..' to '..S.BUILD_A..': '..desc
  ..' '..table.concat(heard,' / '))
 if NexusWishlistOnlyPicker:IsShown() then NexusActiveWishlistSelector:Click() end
 local ok2,why=W.A.SetLoadoutWishlist(2,S.MIRROR_S,nil)
 assert(ok2==true,'SETUP: '..S.PLAN_S..' is associated with '..S.BUILD_B..': '..tostring(why))
 local plans,count=S.Plans(W)
 assert(count==2,'SETUP: two retained plans: '..plans)
 local state=Nexus.Store.State()
 W.keyD=state.loadoutWishlists[1] and state.loadoutWishlists[1].key
 W.keyS=state.loadoutWishlists[2] and state.loadoutWishlists[2].key
 assert(W.keyD and W.keyS and W.keyD~=W.keyS,'SETUP: the two plans have distinct identities')
 assert(state.firstRunWishlist==nil,'SETUP: no first-run plan is stored')
 W.bound={state=a.state,name=a.name}
 W.labelBefore=label
 if Nexus.SupportIncidents and Nexus.SupportIncidents.Clear then Nexus.SupportIncidents.Clear() end
 return W
end

-- The reported native sequence: a new Wishlist is created and becomes the
-- active slot, one tome is added to it, then the native selection switches
-- back to the plan-D Wishlist. Nexus is told through its normal poll.
function S.NativeNewWishlist(W)
 W.H.perks.serverBuildSlots[S.MIRROR_NEW]={name=S.TOME_LIST,verified=false,echoes={}}
 W.H.perks.serverActiveSlot=S.MIRROR_NEW
 S.Refresh(W)
end
function S.NativeAddTome(W)
 W.H.perks.serverBuildSlots[S.MIRROR_NEW]={name=S.TOME_LIST,verified=false,
  echoes={{spellId=S.TOME,quality=0,stacks=1}}}
 S.Refresh(W)
end
function S.NativeSwitchBack(W)
 W.H.perks.serverActiveSlot=S.MIRROR_D
 S.Refresh(W)
end
function S.NativeTransition(W)
 S.NativeNewWishlist(W);S.NativeAddTome(W);S.NativeSwitchBack(W)
end

-- The open editor's own controller (no public handle).
function S.EditorContext()
 local show=Nexus.WishlistEditor.Show
 for i=1,255 do
  local name,value=debug.getupvalue(show,i)
  if not name then break end
  if name=='wishlistController' then
   return value.EditingContext() or {},value.CreateTargetContext() or {}
  end
 end
 error('SETUP: the editor controller is not reachable')
end

function S.Button(W,text)
 for _,f in ipairs(W.H.frames) do
  if f.kind=='Button' and f:IsVisible() and f:GetText()==text then return f end
 end
 error('SETUP: visible button absent: '..text)
end

function S.Selected(W,id)
 for _,f in ipairs(W.H.frames) do
  if f:IsVisible() and f.plus and f.data and f.data.spellId==id then return f end
 end
 error('SETUP: visible selected editor row absent: '..tostring(id))
end

-- The server's mirror of an upload (a Create's sentinel 0 lands in 104).
function S.Mirror(W,slot,name,entries)
 slot=tonumber(slot)
 if slot==0 then slot=104 end
 W.H.perks.serverBuildSlots[slot]={name=name,verified=false,echoes=W.H.Clone(entries)}
 W.H.Notify();W.A.Poll();W.H.Advance(4)
 return slot
end

return S
