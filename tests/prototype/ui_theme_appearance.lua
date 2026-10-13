-- Appearance is two presentation-only choices: a style (Nexus Vista, the
-- default, or Nexus Slate, the test.9094 look) and a colour. A player who
-- never chose gets Nexus Vista; an explicit saved choice is kept; a value this
-- build does not know is shown as kept and is never rewritten; only an
-- explicit selection writes, through the Store settings owner, and a refusal
-- applies to this session only. Repainting reuses what exists, a selection
-- reads without colour, and the difficulty / Soul Ash card keeps its own look.
-- Real TOC boot, Store and panels; synthetic data; no gameplay.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Boot(mutate)return F.Boot(F.Database({mutate=mutate}),F.OrbService)end
local function Settings()return F.Serialize(NexusDB.settings)end
local function Without(keys)
 local copy={};for k,v in pairs(NexusDB.settings)do if not keys[k]then copy[k]=v end end
 return F.Serialize(copy)
end

-- 1. The pure mapping.
local H=Boot()
local T=assert(Nexus.Theme,'the appearance module is loaded')
local r=T.Resolve(nil,nil)
check(r.style.id=='vista' and r.palette.id=='amethyst' and not r.explicitStyle and not r.explicitPalette,
 'no saved choice: Nexus Vista with Nexus Amethyst purple')
r=T.Resolve('slate',nil)
check(r.style.id=='slate' and r.palette.id=='graphite' and r.explicitStyle,
 'an explicit Nexus Slate keeps the test.9094 colours')
-- Slate keeps the test.9094 literals, but the Orb windows that test.9094 left
-- plain now use it too: its description says so instead of "unchanged".
local slateTip
for _,item in ipairs(T.MenuItems())do if item.text=='Nexus Slate' then slateTip=item.tooltipText end end
check(slateTip and slateTip:find('test.9094',1,true) and slateTip:find('Orb windows',1,true)
 and not slateTip:find('unchanged',1,true) and T.HELP:find('Orb windows',1,true) and not T.HELP:find('unchanged',1,true),
 'Slate is described as the test.9094 look that now also styles the Orb windows: '..tostring(slateTip))
r=T.Resolve('chronicle',{})
check(r.style.id=='vista' and r.palette.id=='amethyst' and r.unknownStyle and r.unknownPalette and r.savedStyle=='chronicle',
 'an unknown or malformed value falls back for display and is reported as unknown')

-- 2. No choice: Nexus Vista, and reading, the menu and styling write nothing.
local before=Settings()
check(T.Current().style=='vista' and T.Current().palette=='amethyst' and not T.Current().explicitStyle and not T.Current().explicitPalette,'the default is Nexus Vista with Nexus Amethyst')
T.Refresh();T.MenuItems();Nexus.OrbPanel.Show();Nexus.OrbPanel.ShowLog();Nexus.OrbPanel.Hide()
check(Settings()==before and NexusDB.settings.uiStyle==nil and NexusDB.settings.uiPalette==nil,
 'reading and showing the appearance writes nothing')

-- 3. Every colour has its exact name and a plain hue word; a check mark, not
-- a colour, marks the active entry.
local NAMES={sapphire={'Nexus Sapphire','blue'},emerald={'Nexus Emerald','green'},
 amethyst={'Nexus Amethyst','purple'},ember={'Nexus Ember','orange'}}
local items=T.MenuItems()
for _,palette in ipairs(T.Palettes())do
 check(palette.label:match('^Nexus %u%l+$')~=nil,'a palette name is spaced properly: '..palette.label)
 check(type(palette.hue)=='string' and palette.hue~='','the palette has a hue word: '..palette.label)
 local expected=NAMES[palette.id]
 if expected then
  check(palette.label==expected[1] and palette.hue==expected[2],'the palette is named '..expected[1]..' ('..expected[2]..')')
 end
 local found=false
 for _,item in ipairs(items)do
  if item.text==palette.label..' ('..palette.hue..')' then found=true end
 end
 check(found,'the menu shows the name with its hue: '..palette.label)
end
local styleChecked=0
for _,item in ipairs(items)do if item.checked and item.func then styleChecked=styleChecked+1 end end
check(styleChecked==2,'one style and one colour entry carry the check mark: '..styleChecked)

-- 4. A selected tab or view has a bar and a held highlight, not only a colour.
local tab=CreateFrame('Button',nil,UIParent);tab:SetText('Tab')
tab.GetFontString=function()return tab end
local locks=0;tab.LockHighlight=function()locks=locks+1 end;tab.UnlockHighlight=function()locks=locks-1 end
T.StyleButton(tab);T.SetSelected(tab,true)
check(tab._nexusSelectedBar and tab._nexusSelectedBar:IsShown() and locks==1,'a selection shows a bar and a held highlight')
T.SetSelected(tab,false)
check(not tab._nexusSelectedBar:IsShown() and locks==0,'and both go away together')

-- 5. Repainting reuses what exists: no texture, hook or tree walk is added,
-- and refreshes with no change re-resolve nothing.
local s0=T.Stats()
for _=1,10 do Nexus.OrbPanel.Show();Nexus.OrbPanel.Refresh();T.Refresh() end
local s1=T.Stats()
check(s1.resolves==s0.resolves,'unchanged refreshes resolve nothing: '..s0.resolves..' -> '..s1.resolves)
check(s1.treeWalks==s0.treeWalks and s1.nodesVisited==s0.nodesVisited,'and walk no frame tree')
local outcome,message=T.SetStyle('slate')
check(outcome=='durable' and message:find('Saved.',1,true),'an explicit choice is saved through the settings owner: '..tostring(message))
check(NexusDB.settings.uiStyle=='slate' and T.Current().style=='slate','the saved choice is in effect')
T.SetPalette('ember');T.Reapply();T.SetPalette(nil)
local s2=T.Stats()
check(s2.textures==s1.textures and s2.hooks==s1.hooks,'repainting adds no texture or hook: '
 ..s1.textures..'/'..s1.hooks..' -> '..s2.textures..'/'..s2.hooks)
check(s2.treeWalks==s1.treeWalks and s2.buttonsStyled==s1.buttonsStyled,'and restyles nothing from scratch')
check(s2.reapplies>s1.reapplies,'a change repaints the registry')
check(NexusDB.settings.uiPalette==nil,'returning to the style colours clears only the colour choice')
check(T.SetStyle('chronicle')==nil and NexusDB.settings.uiStyle=='slate','an unavailable style changes nothing')

-- 6. The difficulty / Soul Ash card is never painted.
Nexus.Panel.Show();H.Advance(.5)
local panel=assert(NexusPanel,'the HUD exists')
local card
for _,f in ipairs(H.frames)do if f._nexusThemeExempt and f:GetParent()==panel then card=f end end
check(card~=nil,'the protected card is marked exempt')
local painted=0
for _,m in ipairs({'SetBackdrop','SetBackdropColor','SetBackdropBorderColor'})do
 card[m]=function()painted=painted+1 end
end
T.StyleTree(panel);T.StyleTree(card);T.SetStyle('vista');T.SetPalette('amethyst');T.Reapply();T.SetPalette(nil)
check(painted==0,'no style or colour choice repaints the card: '..painted)
local function styledBelow(f)
 if f._nexusDarkStyled or f._nexusWindowStyled or f._nexusVirtualRowStyled then return true end
 for _,c in ipairs(f.children or {})do if styledBelow(c)then return true end end
 return false
end
check(not styledBelow(card),'and nothing inside it is restyled')

-- 7. A saved Nexus Slate is kept on a new session.
Boot(function(d)d.settings.uiStyle='slate'end);T=Nexus.Theme
before=Settings()
check(T.Current().style=='slate' and T.Current().explicitStyle,'an explicit saved Slate stays Slate')
Nexus.OrbPanel.Show();T.MenuItems();T.Refresh()
check(Settings()==before,'and is not rewritten by reading it')

-- 8. A value this build does not know is kept, named, and never rewritten,
-- also when the player changes the other choice.
Boot(function(d)d.settings.uiStyle='nexus-chronicle-2';d.settings.uiPalette='aurora'end);T=Nexus.Theme
local c=T.Current()
check(c.style=='vista' and c.palette=='amethyst' and c.unknownStyle and c.unknownPalette,'an unknown saved value falls back to Vista/Amethyst for display')
local kept=0
for _,item in ipairs(T.MenuItems())do if item.text and item.text:find('it stays saved',1,true)then kept=kept+1 end end
check(kept==2,'the menu names both unknown values as kept: '..kept)
local unrelated=Without({uiPalette=true})
T.SetPalette('emerald')
check(NexusDB.settings.uiStyle=='nexus-chronicle-2','the unknown style is still saved')
check(NexusDB.settings.uiPalette=='emerald' and Without({uiPalette=true})==unrelated,
 'only the chosen key changed; every other setting is unchanged')

-- 9. A saved root this build keeps read-only: the saved choice is shown, a
-- new choice applies to this session only, and the saved data is unchanged.
Boot(function(d)d.settingsVersion=99;d.settings.uiStyle='slate'end);T=Nexus.Theme
before=Settings()
check(T.Current().style=='slate','a read-only saved root keeps its explicit Slate')
outcome,message=T.SetStyle('vista')
check(outcome=='session' and message:find('this session only',1,true),'the choice is for this session only: '..tostring(message))
check(T.Current().style=='vista' and Settings()==before,'it applies now and the saved data is unchanged')
F.Reload(F.OrbService);T=Nexus.Theme
check(T.Current().style=='slate','after a reload the saved Slate is back')

-- 10. No settings owner: applied for this session, nothing saved.
Boot();T=Nexus.Theme
local owner=Nexus.MainInternals.StoreAuthorityOwner
Nexus.MainInternals.StoreAuthorityOwner=nil
outcome=T.SetPalette('emerald')
Nexus.MainInternals.StoreAuthorityOwner=owner
check(outcome=='unavailable' and NexusDB.settings.uiPalette==nil,'without an owner nothing is saved: '..tostring(outcome))
check(T.Current().palette=='emerald' and T.Current().sessionOnly,'and the colour applies for this session')
-- 11. New/unset choices get Amethyst without writing a saved preference;
-- explicit existing style/colour selections and unknown fields survive reload.
Boot();T=Nexus.Theme
before=Settings()
check(T.Current().palette=='amethyst','an unset preference uses the purple default')
T.Refresh();T.MenuItems();Nexus.Panel.Show();Nexus.OrbPanel.ShowMini();Nexus.OrbPanel.HideMini()
check(Settings()==before and NexusDB.settings.uiPalette==nil,'default display does not persist a new choice')
F.Reload(F.OrbService);T=Nexus.Theme
check(T.Current().palette=='amethyst' and not T.Current().explicitPalette,'unset stays unset and purple after reload')
for _,id in ipairs({'sapphire','emerald','amethyst','ember','auric','graphite'})do
 Boot(function(d)d.settings.uiStyle='vista';d.settings.uiPalette=id;d.settings.purpleDefaultSentinel='keep'end);T=Nexus.Theme
 before=Settings()
 check(T.Current().style=='vista' and T.Current().palette==id and T.Current().explicitPalette,'explicit '..id..' is preserved')
 T.Refresh();T.MenuItems();F.Reload(F.OrbService);T=Nexus.Theme
 check(T.Current().palette==id and Settings()==before and NexusDB.settings.purpleDefaultSentinel=='keep','explicit '..id..' persists without rewriting other fields')
end
Boot(function(d)d.settings.uiStyle='slate'end);T=Nexus.Theme
before=Settings()
check(T.Current().style=='slate' and T.Current().palette=='graphite','an explicit existing Slate keeps its default Graphite colours')
F.Reload(F.OrbService);T=Nexus.Theme
check(T.Current().style=='slate' and T.Current().palette=='graphite' and Settings()==before,'explicit Slate survives reload without migration')
T.SetStyle('vista');T.SetPalette('sapphire');T.SetPalette(nil)
check(T.Current().palette=='amethyst' and NexusDB.settings.uiPalette==nil,'clearing a Vista colour choice returns to purple without storing the fallback')
Boot(function(d)d.settingsVersion=99;d.settings.uiStyle='vista';d.settings.uiPalette='sapphire'end);T=Nexus.Theme
before=Settings()
check(T.Current().palette=='sapphire','a future read-only saved root keeps its explicit non-purple palette')
F.Reload(F.OrbService);T=Nexus.Theme
check(T.Current().palette=='sapphire' and Settings()==before,'the future saved choice persists byte-for-byte through reload')
print('PASS ui_theme_appearance: Vista/Amethyst by default, explicit and unknown choices kept, owner-routed writes, no repaint allocation, exempt card untouched checks='..checks)
