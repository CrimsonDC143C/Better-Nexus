-- Warning constructor with a scoped, independently authored template model.
-- Historical contract: original 3.3.5/build 12213, not the modified client.
-- https://github.com/tekkub/wow-ui-source/blob/c4e0255fc574598428ee1c25f160ab949798bc98/FrameXML/UIPanelTemplates.lua#L242-L260
-- Its XML creates named scrollbar/arrow children before synchronous OnLoad.
-- Model only this warning's scroll template; the shared harness is unchanged.
local checks=0
local function check(value,message)assert(value,message);checks=checks+1 end
local SCROLL='NexusOverwriteWarningScroll'
local function ClearWarning()
 for _,suffix in ipairs({'','ScrollBar','ScrollBarScrollUpButton','ScrollBarScrollDownButton'})do
  _G[SCROLL..suffix]=nil
 end
 NexusOverwriteWarning=nil
end

local function TemplateModel(H)
 local create=CreateFrame
 local model={created=0,loads=0,faults=0}
 CreateFrame=function(kind,name,parent,template)
  local f=create(kind,name,parent)
  if kind~='ScrollFrame' or template~='UIPanelScrollFrameTemplate'
   or not parent or parent:GetName()~='NexusOverwriteWarning' then return f end
  model.created=model.created+1
  -- A missing scroll name stays missing. Never invent a name to pass OnLoad.
  local barName=name and name..'ScrollBar'
  local bar=create('Slider',barName,f)
  local up=create('Button',barName and barName..'ScrollUpButton',bar)
  local down=create('Button',barName and barName..'ScrollDownButton',bar)
  model.scroll,model.bar,model.up,model.down=f,bar,up,down
  f:SetScript('OnLoad',function(self)
   model.loads=model.loads+1
   -- Resolve real inherited child names. An anonymous frame fails at this
   -- genuine nil concatenation, before CreateFrame returns to the addon.
   local prefix=self:GetName()..'ScrollBar'
   _G[prefix..'ScrollDownButton']:Disable()
   _G[prefix..'ScrollUpButton']:Disable()
   local slider=_G[prefix]
   slider:SetMinMaxValues(0,0);slider:SetValue(0);self.offset=0
   if self.scrollBarHideable then
    slider:Hide();_G[prefix..'ScrollDownButton']:Hide();_G[prefix..'ScrollUpButton']:Hide()
   else
    _G[prefix..'ScrollDownButton']:Show();_G[prefix..'ScrollUpButton']:Show()
   end
  end)
  local ok,err=pcall(f:GetScript('OnLoad'),f)
  if not ok then model.faults=model.faults+1;error(err,0)end
  return f
 end
 return model
end

local function Fresh(db,boot)
 ClearWarning()
 local H=dofile('tests/prototype/harness.lua')
 UIParent:SetSize(1280,720)
 local model=TemplateModel(H)
 NexusDB=db
 if boot then
  Nexus=nil;WishlistRealizerDB=nil;H.keepOverwriteWarningPrompts=true;H.Boot()
  return H,Nexus.OverwriteWarning,model
 end
 Nexus={Store={StateWriteStatus=function()return {mode='durable'}end},
  StartupStatus=function()return {coreReady=true}end}
 return H,dofile('ui/OverwriteWarning.lua'),model
end

local function Initialized(model)
 local f=NexusOverwriteWarning
 check(f and f.body and f.scroll and f.suppress and f.yes and f.no and f.close and f.countdown,
  'warning constructor completes all controls after inherited OnLoad')
 check(model.created==1 and model.loads==1 and model.faults==0,
  'one complete synchronous template initialization without a swallowed factory error')
 check(f.scroll==model.scroll and f.scroll:GetName()==SCROLL,
  'actual warning scroll has its own stable name')
 check(_G[SCROLL..'ScrollBar']==model.bar
  and _G[SCROLL..'ScrollBarScrollUpButton']==model.up
  and _G[SCROLL..'ScrollBarScrollDownButton']==model.down,
  'OnLoad resolves the children created for this exact named scroll')
 local minimum,maximum=model.bar:GetMinMaxValues()
 check(minimum==0 and maximum==0 and model.bar:GetValue()==0 and f.scroll.offset==0,
  'inherited OnLoad initializes scrollbar range, value and scroll offset')
 check(not model.up:IsEnabled() and not model.down:IsEnabled()
  and model.up:IsShown() and model.down:IsShown(),'initial arrows are disabled and shown')
 return f
end

local H,W,model=Fresh({hasSeenQuickStart=true})
-- This first real constructor is the RED assertion on the unchanged module:
-- its anonymous scroll raises the template's nil-name concatenation.
check(W.EnsureOnboarding()=='pending','first onboarding opens the real warning')
local f=Initialized(model)
check(f:IsShown() and not f.yes:IsEnabled() and not f.no:IsEnabled()
 and not f.suppress:IsEnabled(),'onboarding starts with the five-second reading gate')
f.yes:GetScript('OnClick')(f.yes)
f.suppress:SetChecked(true);f.suppress:GetScript('OnClick')(f.suppress)
check(not f.suppress:GetChecked() and NexusDB.overwriteWarnings==nil,
 'early handlers cannot grant consent or save suppression')
H.Advance(4.99)
check(not f.yes:IsEnabled() and not f.no:IsEnabled(),'choices stay blocked before five seconds')
H.Advance(.02)
check(f.yes:IsEnabled() and f.no:IsEnabled() and f.suppress:IsEnabled()
 and f:GetScript('OnUpdate')==nil,'reading gate enables controls and stops countdown work')
f.suppress:SetChecked(true);f.no:Click()
check(not f:IsShown() and W.EnsureOnboarding()=='declined' and NexusDB.overwriteWarnings==nil,
 'No declines onboarding without saving suppression')
check(#H.actions==0,'opening, reading and declining perform no game/save action')

local owner,accepted={},0
local function Accept()accepted=accepted+1;return true end
for _,dismiss in ipairs({'no','close','escape'})do
 W.RequestAuto(owner,Accept)
 check(NexusOverwriteWarning==f and model.created==1 and model.loads==1,
  'later Auto prompts reuse the initialized dialog')
 check(f:IsShown() and f.yes:IsEnabled() and not f.suppress:GetChecked(),
  'each reused Auto prompt resets suppression and has no reading delay')
 f.suppress:SetChecked(true)
 if dismiss=='escape' then f:GetScript('OnKeyDown')(f,'ESCAPE') else f[dismiss]:Click()end
 check(not f:IsShown() and accepted==0 and NexusDB.overwriteWarnings==nil,
  dismiss..' cancels Auto without consent or preference writes')
end
W.RequestAuto(owner,Accept);f.suppress:SetChecked(true);f.yes:Click()
check(accepted==1 and NexusDB.overwriteWarnings.auto.suppressed,
 'affirmed checked Auto persists only its own suppression')
check(NexusDB.overwriteWarnings.onboarding==nil,'Auto suppression does not suppress onboarding')
W.RequestAuto(owner,Accept)
check(accepted==2 and not f:IsShown() and model.created==1,
 'saved Auto suppression is used only after another explicit request')
NexusDB.overwriteWarnings.auto=nil
W.RequestAuto(owner,Accept)
check(f:IsShown() and not f.suppress:GetChecked(),'removing suppression reopens an unchecked dialog')
f.close:Click();check(#H.actions==0,'all direct warning routes submit no game/save action')

for _,dismiss in ipairs({'close','escape'})do
 H,W,model=Fresh({hasSeenQuickStart=true})
 W.EnsureOnboarding();f=Initialized(model);f.suppress:SetChecked(true)
 if dismiss=='escape' then f:GetScript('OnKeyDown')(f,'ESCAPE') else f.close:Click()end
 check(W.EnsureOnboarding()=='declined' and not f:IsShown() and NexusDB.overwriteWarnings==nil,
  dismiss..' can cancel onboarding during the reading delay')
 check(f:GetScript('OnUpdate')==nil and #H.actions==0,'early dismissal stops the timer without an action')
end

-- Real TOC, Panel callback and MainLifecycle/automation owner. Panel pcall
-- swallows callback faults, so also inspect full controls and model fault count.
H,W,model=Fresh({hasSeenQuickStart=true,
 overwriteWarnings={onboarding={version=1,suppressed=true}}},true)
local function AutoOn()return Nexus.RecomputeStats().autoEnabled end
check(not AutoOn(),'real runtime starts with Auto OFF')
Nexus.Panel.Show()
check(model.created==0 and NexusOverwriteWarning==nil,
 'suppressed onboarding leaves construction to the first HUD Auto click')
local warningPrefs=NexusDB.overwriteWarnings
local onboardingPref=warningPrefs.onboarding
local actions=#H.actions
NexusPanel._autoBtn:Click()
f=Initialized(model)
check(f:IsShown() and f.yes:IsEnabled() and f:GetScript('OnUpdate')==nil and not AutoOn(),
 'actual HUD Auto route constructs an immediately usable pending Auto warning')
NexusPanel._autoBtn:Click()
check(model.created==1 and model.faults==0 and not AutoOn(),'repeated HUD clicks cannot bypass approval')
f.no:Click()
check(not AutoOn() and not f:IsShown(),'HUD Auto No keeps Auto OFF')
for _,dismiss in ipairs({'no','close','escape'})do
 NexusPanel._autoBtn:Click()
 check(f:IsShown() and f.yes:IsEnabled() and not f.suppress:GetChecked(),
  'HUD uses the completed dialog and resets suppression')
 f.suppress:SetChecked(true)
 if dismiss=='escape' then f:GetScript('OnKeyDown')(f,'ESCAPE') else f[dismiss]:Click()end
 check(not AutoOn() and not f:IsShown() and NexusDB.overwriteWarnings==warningPrefs
  and warningPrefs.onboarding==onboardingPref and onboardingPref.version==1
  and onboardingPref.suppressed==true and warningPrefs.auto==nil,
  'HUD '..dismiss..' leaves Auto OFF and preserves only the existing onboarding suppression')
end
check(model.created==1 and model.loads==1 and model.faults==0,
 'HUD reuses a single successfully initialized scroll template')
check(#H.actions==actions,'all HUD pending/declined warnings submit no game/save action')
print('PASS overwrite_warning_template_init checks='..checks..'; historical template model; native client NOT_RUN')
