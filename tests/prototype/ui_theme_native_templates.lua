-- Native screenshots: stock red button slices remain visible, the
-- Orb max EditBox is unthemed, and the HUD stays on its original backdrop.
-- Real TOC/panels/settings owner; model the native template semantics the
-- general harness omits. Based on read-only 3.3.5 client FrameXML and its
-- SharedUIPanelTemplates override. No pixels/FPS/server effects certified.
local F=dofile('tests/prototype/format5_support.lua')
local failures,checks={},0
local function check(v,m)checks=checks+1;if not v then failures[#failures+1]=m end end
local function Boot()
 return F.Boot(F.Database(),function(H)
  F.OrbService(H)
  local create=CreateFrame
  CreateFrame=function(kind,name,parent,template)
   local f=create(kind,name,parent,template)
   f.SetBackdrop=function(self,v)
    self.nativeBackdrop=v
    -- Model backdrop artwork exposed as root Texture regions before page
    -- ownership is captured. This is not native pixel/alpha certification.
    if name=='NexusOrbPanel' and not self.nativeBackdropRegions then
     self.nativeBackdropRegions={self:CreateTexture(nil,'BACKGROUND'),self:CreateTexture(nil,'BORDER')}
    end
   end
   f.SetBackdropColor=function(self,...)self.nativeFill={...}end
   f.SetBackdropBorderColor=function(self,...)self.nativeBorder={...}end
   f.IsEnabled=function(self)return self.enabled and 1 or 0 end
   if kind=='Button' and template and template:find('UIPanelButton',1,true) then
    local fs=f:CreateFontString(nil,'OVERLAY','GameFontNormal')
    f.GetFontString=function()return fs end
    fs.SetTextColor=function(self,...)f.nativeTextColor={...}end
    -- Actual shared template keeps Left/Middle/Right as ordinary regions;
    -- SetNormalTexture(nil) cannot remove them. State scripts swap their file.
    f.nativeArt={}
    f.nativeIcon=f:CreateTexture(nil,'ARTWORK');f.nativeIcon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
    f.nativeIcon.alpha=1;f.nativeIcon.GetAlpha=function(self)return self.alpha end
    f.nativeIcon.SetAlpha=function(self,a)self.alpha=a end
    for _,key in ipairs({'Left','Middle','Right'})do
     local r=f:CreateTexture(nil,'BACKGROUND');r:SetTexture('Interface\\Buttons\\UI-Panel-Button-Up')
     r.alpha=1;r.SetAlpha=function(self,a)self.alpha=a end
     r.GetAlpha=function(self)return self.alpha end
     f[key]=r;f.nativeArt[#f.nativeArt+1]=r
    end
    local function state(self,suffix)
     for _,r in ipairs(self.nativeArt)do r:SetTexture('Interface\\Buttons\\UI-Panel-Button-'..suffix)end
    end
    f:SetScript('OnMouseDown',function(self)if self.enabled then state(self,'Down')end end)
    f:SetScript('OnMouseUp',function(self)if self.enabled then state(self,'Up')end end)
    f:SetScript('OnShow',function(self)if self.enabled then state(self,'Up')end end)
    f:SetScript('OnDisable',function(self)state(self,'Disabled')end)
    f:SetScript('OnEnable',function(self)state(self,'Up')end)
    f.Disable=function(self)self.enabled=false;local h=self:GetScript('OnDisable');if h then h(self)end end
    f.Enable=function(self)self.enabled=true;local h=self:GetScript('OnEnable');if h then h(self)end end
   elseif kind=='EditBox' and template=='InputBoxTemplate' then
    f.nativeInsets={0,0,0,0}
    f.SetTextInsets=function(self,...)self.nativeInsets={...}end
    f.nativeArt={}
    for _,key in ipairs({'Left','Middle','Right'})do
     local r=f:CreateTexture(nil,'BORDER');r:SetTexture('Interface\\Common\\Common-Input-Border')
     r.alpha=1;r.SetAlpha=function(self,a)self.alpha=a end;r.GetAlpha=function(self)return self.alpha end
     f[key]=r;f.nativeArt[#f.nativeArt+1]=r
    end
   end
   return f
  end
 end)
end
local H=Boot();local T=Nexus.Theme
local orb=Nexus.OrbPanel.Show();Nexus.Panel.Show();H.Advance(.5)
local hud=NexusPanel
check(hud and hud._nexusWindowStyled,'HUD window joins the selected appearance, excluding its ash card')
check(orb.limit and orb.limit.nativeBackdrop,'Orb approved maximum input has a shared-theme backdrop')
local inset=orb.limit and orb.limit.nativeInsets
check(inset and inset[1]>=6 and inset[2]>=6 and orb.limit:GetWidth()-inset[1]-inset[2]>=50,
 'styled maximum input reserves border clearance and at least50units for its five digits')
local myBuilds
for _,c in ipairs(orb.children)do if c.GetText and c:GetText()=='My Builds' then myBuilds=c end end
check(myBuilds and myBuilds._nexusDarkStyled,'actual My Builds control is styled with a native FontString')
check(myBuilds and myBuilds.nativeIcon:IsShown() and myBuilds.nativeIcon:GetAlpha()==1,
 'custom button icons are preserved when suppressing template artwork')
local function hiddenArt(f,context)
 for _,r in ipairs(f.nativeArt or {})do
  check(not r:IsShown() or r:GetAlpha()==0,context..': native stock artwork is suppressed')
 end
end
hiddenArt(myBuilds,'initial');hiddenArt(orb.limit,'input')
if myBuilds then
 for _,event in ipairs({'OnMouseDown','OnMouseUp','OnShow'})do
  local fn=myBuilds:GetScript(event);if fn then fn(myBuilds)end;hiddenArt(myBuilds,event)
 end
 myBuilds:Disable();hiddenArt(myBuilds,'disabled');T.SetPalette('ember');hiddenArt(myBuilds,'orange disabled')
 local color=myBuilds.nativeTextColor
 check(color and color[1]==T.STYLES.vista.disabledText[1],'native IsEnabled() == 0 stays visibly disabled after a palette change')
 myBuilds:Enable();hiddenArt(myBuilds,'re-enabled')
end
check(hud and hud.nativeBorder and hud.nativeBorder[1]==T.PALETTES.ember.windowBorder[1],
 'HUD and Orb window use the same orange edge')
local originalFill=F.Serialize(orb.nativeFill)
check(orb.nativeFill[4]==.96,'the parent keeps its requested backdrop alpha')
local function backdropShown(context)
 for _,r in ipairs(orb.nativeBackdropRegions)do
  check(r:IsShown(),context..': root backdrop artwork remains shown')
 end
 check(F.Serialize(orb.nativeFill)==originalFill,context..': backdrop colour/alpha are unchanged')
end
backdropShown('initial run')
for i=1,3 do
 local history=Nexus.OrbPanel.ShowLog()
 check(history:GetParent()==orb,'history uses the same root Orb window')
 check(history:IsShown() and not orb.start:IsShown() and not orb.plan:IsShown(),
  'history shows its content and hides run controls/text')
 backdropShown('history '..i)
 T.Reapply();backdropShown('history theme reapply '..i)
 Nexus.OrbPanel.Show()
 check(orb.start:IsShown() and orb.plan:IsShown() and not history:IsShown(),
  'returning to run restores controls/text and hides history')
 backdropShown('return to run '..i)
 Nexus.OrbPanel.Hide();Nexus.OrbPanel.ShowLog()
 backdropShown('history close/reopen '..i)
end
Nexus.OrbPanel.Show()
local card
for _,f in ipairs(H.frames)do if f._nexusThemeExempt and f:GetParent()==hud then card=f end end
check(card~=nil,'protected difficulty/ash card exists')
local original=F.Serialize(card and {card.nativeBackdrop,card.nativeFill,card.nativeBorder} or {})
T.SetStyle('slate');T.SetPalette('emerald');T.Reapply()
check(F.Serialize(card and {card.nativeBackdrop,card.nativeFill,card.nativeBorder} or {})==original,
 'theme changes preserve the complete protected card backdrop')
local s=T.Stats();local frames=#H.frames
for _=1,40 do Nexus.OrbPanel.Refresh();T.Refresh()end
local after=T.Stats()
check(after.textures==s.textures and after.hooks==s.hooks and after.treeWalks==s.treeWalks and #H.frames==frames,
 'steady refresh has no new native artwork scan/tree/texture/hook/frame allocation')
check(#H.actions==0,'appearance cannot execute gameplay')
for _,m in ipairs(failures)do print('FAIL native theme: '..m)end
assert(#failures==0,'native-template theme failures='..#failures)
print('PASS ui_theme_native_templates checks='..checks..'; source/template model only, native pixels NOT_RUN')
