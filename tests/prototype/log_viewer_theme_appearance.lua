-- Actual TOC/LogViewer/Theme with synthetic 3.3.5 UIPanelButton regions/events.
-- Current UI8ea shows stock red controls under its themed window. This test
-- exercises presentation/navigation only; action footer/peer clicks are not run.
local F=dofile('tests/prototype/format5_support.lua')
local checks,failures=0,{}
local function check(v,m) checks=checks+1;if not v then failures[#failures+1]=m end end
local H=F.Boot(F.Database(),function(h)
 F.OrbService(h)
 local create=CreateFrame
 CreateFrame=function(kind,name,parent,template)
  local f=create(kind,name,parent,template)
  f.SetBackdropColor=function(self,...)self.observedFill={...}end
  f.SetBackdropBorderColor=function(self,...)self.observedBorder={...}end
  f.originalScripts={}
  local setScript=f.SetScript
  f.SetScript=function(self,event,fn)self.originalScripts[event]=fn;setScript(self,event,fn)end
  if kind=='Button' and template=='UIPanelButtonTemplate' then
   f.stockArt={}
   local fs=f:CreateFontString(nil,'OVERLAY','GameFontNormal')
   f.GetFontString=function()return fs end
   fs.SetTextColor=function(self,...)f.observedTextColor={...}end
   local setText=f.SetText
   f.SetText=function(self,value)setText(self,value);fs:SetText(value)end
   f.IsEnabled=function(self)return self.enabled and 1 or 0 end
   for _,key in ipairs({'Left','Middle','Right'})do
    local r=f:CreateTexture(nil,'BACKGROUND');r:SetTexture('Interface\\Buttons\\UI-Panel-Button-Up')
    r.alpha=1;r.SetAlpha=function(self,a)self.alpha=a end;r.GetAlpha=function(self)return self.alpha end
    f[key]=r;f.stockArt[#f.stockArt+1]=r
   end
   local function state(self,suffix)
    for _,r in ipairs(self.stockArt)do r:SetTexture('Interface\\Buttons\\UI-Panel-Button-'..suffix);r:Show()end
   end
   f:SetScript('OnMouseDown',function(self)if self.enabled then state(self,'Down')end end)
   f:SetScript('OnMouseUp',function(self)if self.enabled then state(self,'Up')end end)
   f:SetScript('OnShow',function(self)if self.enabled then state(self,'Up')end end)
   f:SetScript('OnDisable',function(self)state(self,'Disabled')end)
   f:SetScript('OnEnable',function(self)state(self,'Up')end)
   f.Disable=function(self)self.enabled=false;self:GetScript('OnDisable')(self)end
   f.Enable=function(self)self.enabled=true;self:GetScript('OnEnable')(self)end
   f.LockHighlight=function(self)self.lockedHighlight=true end
   f.UnlockHighlight=function(self)self.lockedHighlight=false end
  elseif kind=='Button' and template=='UIPanelCloseButton' then
   f:SetScript('OnClick',function()parent:Hide()end)
  elseif kind=='EditBox' then
   f.HighlightText=function(self,...)self.highlighted={...}end
  end
  return f
 end
end)
local T,LV=Nexus.Theme,Nexus.LogViewer
T.SetStyle('vista');T.SetPalette('sapphire')
local providerCalls,clearCalls=0,0
local reports={state=string.rep('Status line\n',4000),wishlist='Synthetic wishlist'}
LV.Init(function(tab)providerCalls=providerCalls+1;return reports[tab] or ('Synthetic '..tab)end,
 function()clearCalls=clearCalls+1;error('clear callback must not run')end)
LV.Show();H.Advance(.15)
local frame,scroll=NexusLogViewer,NexusLogScroll
local box=scroll.scrollChild
check(frame._nexusWindowStyled==true,'Log window retains shared window styling')
check(frame._nexusDarkTreeStyled==true,'Completed owned tree is enrolled')
local buttons,tabs,close={},{}
for _,child in ipairs({frame:GetChildren()})do
 if child.stockArt then buttons[child:GetText()]=child end
 if child.tabKey then tabs[child.tabKey]=child end
 if child:GetObjectType()=='Button' and not child.stockArt then close=child end
end
local expected={'Recent choices','Manual overrides','Wishlist','Locked Echoes','Status','Sync','DPS','Slot actions','Performance','Roll trace','Errors','Advanced peer',
 'Select this page','Refresh','< Page','Page >','Start','Stop','Clear Log','Prepare full diagnostic report'}
for _,label in ipairs(expected)do
 local b=buttons[label]
 check(b~=nil,'Owned control exists: '..label)
 check(b and b._nexusDarkStyled==true,'Owned control enrolled: '..label)
 if b then
  check(b:GetScript('OnClick')==b.originalScripts.OnClick,'Click callback preserved: '..label)
  check(b:GetScript('OnEnter')==b.originalScripts.OnEnter and b:GetScript('OnLeave')==b.originalScripts.OnLeave,'Tooltip callbacks preserved: '..label)
  for _,event in ipairs({'OnMouseDown','OnMouseUp','OnShow'})do
   b:GetScript(event)(b)
   for _,r in ipairs(b.stockArt)do check(r:GetAlpha()==0,'Stock art suppressed after '..event..': '..label)end
  end
  local enabled=b.enabled
  b:Disable()
  local color,disabled=b.observedTextColor,T.STYLES.vista.disabledText
  check(color and color[1]==disabled[1] and color[2]==disabled[2] and color[3]==disabled[3],'Disabled label style: '..label)
  b:Enable()
  for _,r in ipairs(b.stockArt)do check(r:GetAlpha()==0,'Stock art suppressed after disable/enable: '..label)end
  if not enabled then b:Disable()end
 end
end
check(tabs.state.lockedHighlight==true and box:GetText()==reports.state:sub(1,16000),'Default Status tab/text retained')
check(LV.PageInfo().pages==3 and LV.PageInfo().page==1,'Complete report remains paged')
buttons['Page >']:Click();check(LV.PageInfo().page==2,'Next page callback retained')
buttons['< Page']:Click();check(LV.PageInfo().page==1,'Previous page callback retained')
buttons['Select this page']:Click();check(box:HasFocus() and box.highlighted~=nil,'Select/focus callback retained')
box:GetScript('OnEscapePressed')(box);check(not box:HasFocus(),'Escape clears copy focus')
scroll:SetVerticalScroll(45);check(scroll:GetVerticalScroll()==45 and scroll.scrollChild==box,'Scroll child/position retained')
tabs.wishlist:Click();H.Advance(.15)
check(tabs.wishlist.lockedHighlight==true and box:GetText()==reports.wishlist,'Tab selection callback retained')
tabs.state:Click();H.Advance(.15)
check(tabs.state.lockedHighlight==true and box:GetText()==reports.state:sub(1,16000),'Status tab callback retained')
local before=providerCalls;buttons.Refresh:Click();H.Advance(.15)
check(providerCalls==before+1 and LV.PageInfo().page==1,'Refresh callback retains deferred repaint')
check(close and close:GetScript('OnClick')==close.originalScripts.OnClick,'Native close callback retained')
close:Click();check(not frame:IsShown(),'Visible close control hides the viewer')
LV.Show('state');H.Advance(.15)
check(NexusLogViewer==frame and frame:IsShown(),'Reopen reuses the same window')
local oldWindow,oldButtons=F.Serialize(frame.observedBorder),{}
for label,b in pairs(buttons)do oldButtons[label]=F.Serialize(b.observedBorder)end
T.SetPalette('amethyst')
check(F.Serialize(frame.observedBorder)~=oldWindow,'Open window follows Sapphire to Amethyst')
for label,b in pairs(buttons)do
 check(F.Serialize(b.observedBorder)~=oldButtons[label],'Open control follows Sapphire to Amethyst: '..label)
 for _,r in ipairs(b.stockArt)do check(r:GetAlpha()==0,'Palette change preserves suppression: '..label)end
end
local stats,count=T.Stats(),#H.frames
for _=1,30 do frame:Hide();LV.Show('state');H.Advance(.15);T.Refresh()end
local after=T.Stats()
check(after.textures==stats.textures and after.hooks==stats.hooks and after.treeWalks==stats.treeWalks and after.skippedTrees==stats.skippedTrees and #H.frames==count,
 'Repeated opens add no frame, texture, hook, tree walk or redundant tree call')
check(clearCalls==0 and not Nexus.PeerDebug.IsEnabled(),'Action/peer controls were never invoked')
check(#H.actions==0,'Appearance/navigation never executes gameplay')
for _,m in ipairs(failures)do print('FAIL log viewer theme: '..m)end
assert(#failures==0,'Log viewer theme failures='..#failures)
print('PASS log_viewer_theme_appearance checks='..checks..'; source/template model only, native repaired pixels NOT_RUN')
