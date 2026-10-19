-- Actual Help/Theme/TOC path with synthetic 3.3.5 button template artwork.
-- Locks down the native black Help/red button report; pixels remain native-only.
local F=dofile('tests/prototype/format5_support.lua')
local failures,checks={},0
local function check(v,m)
 checks=checks+1;if not v then failures[#failures+1]=m end
end
local H=F.Boot(F.Database(),function(h)
 F.OrbService(h)
 local create=CreateFrame
 CreateFrame=function(kind,name,parent,template)
  local f=create(kind,name,parent,template)
  f.SetBackdropColor=function(self,...)self.observedFill={...}end
  f.SetBackdropBorderColor=function(self,...)self.observedBorder={...}end
  if kind=='Button' and template=='UIPanelButtonTemplate' then
   local fs=f:CreateFontString(nil,'OVERLAY','GameFontNormal')
   f.GetFontString=function()return fs end
   fs.SetTextColor=function(self,...)f.observedTextColor={...}end
   f.stockArt={}
   for _,key in ipairs({'Left','Middle','Right'})do
    local r=f:CreateTexture(nil,'BACKGROUND')
    r:SetTexture('Interface\\Buttons\\UI-Panel-Button-Up')
    r.alpha=1;r.SetAlpha=function(self,a)self.alpha=a end
    r.GetAlpha=function(self)return self.alpha end
    f[key]=r;f.stockArt[#f.stockArt+1]=r
   end
   local function stockState(self,suffix)
    for _,r in ipairs(self.stockArt)do
     r:SetTexture('Interface\\Buttons\\UI-Panel-Button-'..suffix)
    end
   end
   f:SetScript('OnMouseDown',function(self)stockState(self,'Down')end)
   f:SetScript('OnMouseUp',function(self)stockState(self,'Up')end)
   f:SetScript('OnShow',function(self)stockState(self,'Up')end)
   f:SetScript('OnDisable',function(self)stockState(self,'Disabled')end)
   f:SetScript('OnEnable',function(self)stockState(self,'Up')end)
  end
  return f
 end
end)
local T=Nexus.Theme
T.SetPalette('sapphire')
local help=Nexus.Help.Show('start')
check(help._nexusWindowStyled==true,'Help joins the selected window palette')
local expected={Previous=true,Next=true,['Start page']=true,Close=true}
local buttons={}
for _,child in ipairs({help:GetChildren()})do
 if child.GetObjectType and child:GetObjectType()=='Button' then
  local label=child:GetText()
  if expected[label]then buttons[label]=child end
 end
end
for label in pairs(expected)do
 local b=buttons[label]
 check(b~=nil,'Help owns '..label..' control')
 check(b and b._nexusDarkStyled==true,label..' joins the selected button palette')
 if b then for _,r in ipairs(b.stockArt)do
  check(r:GetAlpha()==0,label..' inherited red artwork is suppressed')
 end end
 if b then for _,event in ipairs({'OnMouseDown','OnMouseUp','OnShow','OnDisable','OnEnable'})do
  b:GetScript(event)(b)
  for _,r in ipairs(b.stockArt)do
   check(r:GetAlpha()==0,label..' stock artwork stays suppressed after '..event)
  end
 end end
end
local title=help.title:GetText()
buttons.Next:GetScript('OnClick')()
check(help.title:GetText()~=title,'Next retains page navigation')
buttons.Previous:GetScript('OnClick')()
check(help.title:GetText()==title,'Previous returns to the start page')
buttons.Next:GetScript('OnClick')()
buttons['Start page']:GetScript('OnClick')()
check(help.title:GetText()==title,'Start page retains its callback')
buttons.Close:GetScript('OnClick')()
check(not help:IsShown(),'Close retains its callback')
check(Nexus.Help.Show()==help and help:IsShown(),'Reopen retains the same Help frame')
local border=F.Serialize(help.observedBorder)
T.SetPalette('emerald')
check(F.Serialize(help.observedBorder)~=border,'Already-open Help follows a palette change')
local stats=T.Stats();local count=#H.frames
for _=1,30 do Nexus.Help.Show('start');Nexus.Help.Hide();T.Refresh()end
local after=T.Stats()
check(after.textures==stats.textures and after.hooks==stats.hooks
 and after.treeWalks==stats.treeWalks and #H.frames==count,
 'Repeated reopen/refresh adds no frame, texture, hook or tree walk')
check(#H.actions==0,'Help appearance/navigation never executes gameplay')
for _,m in ipairs(failures)do print('FAIL help theme: '..m)end
assert(#failures==0,'Help theme failures='..#failures)
print('PASS help_theme_appearance checks='..checks..'; native pixels NOT_RUN')
