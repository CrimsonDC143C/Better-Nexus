-- Consumer contract only: synthetic HUD text through the real TOC boot,
-- ServerStatus scanner, Main display input, MainViewModel and Panel renderer.
-- This does not implement the foreign Ebonhold producer or prove realm tier.
-- F.Reload round-trips synthetic saved data and reloads modules offline; it
-- does not model the producer's native ReloadUI/default/request behavior.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0
local function check(value,message) assert(value,message);checks=checks+1 end
local function InstallHud(H,text)
 HardmodeFrame=nil;EbonholdIntensityData=nil
 local root=CreateFrame('Frame','ProjectEbonholdPlayerRunFrame',UIParent)
 local header=CreateFrame('Frame',nil,root)
 local button=CreateFrame('Button',nil,header)
 local tier=button:CreateFontString(nil)
 tier:SetText(text)
 local ash=header:CreateFontString(nil);ash:SetText('76,054')
 local gain=header:CreateFontString(nil);gain:SetText('+188%')
 root.hardmodeTierText=tier;root.soulPointsText=ash;root.multiplierText=gain
 H.difficultyHud={root=root,tier=tier}
 -- Only the existing named balance contract is supplied. No tier getter or
 -- foreign update callback is invented, and Hide never changes the text.
 ProjectEbonhold.PlayerRunUI={GetUIElements=function()
  return {soulPointsText=ash}
 end}
end
local function Settle(H) H.Advance(2.5,.05) end
local function ExpectCaption(H,mode,tier,label)
 local summary=Nexus.ServerStatus.GetSummary()
 check(summary.mode==mode and summary.tier==tier,label..': scanner summary')
 check(summary.ash=='76,054' and summary.gain=='+188%',label..': balance and gain')
 local model=assert(Nexus.Panel._lastModel,label..': actual panel model')
 check(model.serverStatus and model.serverStatus.mode==mode
  and model.serverStatus.tier==tier,label..': Main and view model preserve summary')
 check(model.serverStatus~=summary,label..': display model does not alias the scanner cache')
 local box
 for _,frame in ipairs(H.frames) do
  if rawget(frame,'_summary') and frame:GetParent()==NexusPanel then
   check(box==nil,label..': unique rendered difficulty card')
   box=frame
  end
 end
 check(box~=nil and box:IsShown(),label..': actual difficulty card is shown')
 local expected='|cffff6b5f'..(tier or mode or 'Difficulty')..'|r'
 check(box.regions[1]:GetText()==expected,label..': actual rendered caption')
 check(Nexus.Panel.VisibilityFacts().committed==true,label..': panel committed')
 check(HardmodeFrame==nil,label..': no selected-menu override')
 check(#H.actions==0,label..': no game action')
 print('CONSUMER '..label..' mode='..tostring(mode)..' tier='..tostring(tier)
  ..' caption='..box.regions[1]:GetText())
end
local function Before(text) return function(H) InstallHud(H,text) end end

local db=F.Database({});db.soulAshHudMode='nexus'
local H=F.Boot(db,Before('Hardcore 1'));Settle(H)
ExpectCaption(H,'HC1','HC1','fresh boot HC1')
check(not H.difficultyHud.root:IsShown(),'committed Nexus panel suppresses synthetic HUD')
check(H.difficultyHud.tier:GetText()=='Hardcore 1','suppression does not edit HUD tier text')

H.Fire('PLAYER_ENTERING_WORLD');Settle(H)
ExpectCaption(H,'HC1','HC1','world entry unchanged HC1')

-- The scanner must rediscover the replacement frame object after world entry.
InstallHud(H,'Hardcore 1');H.Fire('PLAYER_ENTERING_WORLD');Settle(H)
ExpectCaption(H,'HC1','HC1','world entry replacement HC1')
check(not H.difficultyHud.root:IsShown(),'world entry replacement HC1: new root is discovered and suppressed')

H=F.Reload(Before('Hardcore 1'));Settle(H)
ExpectCaption(H,'HC1','HC1','offline module reload unchanged HC1')

-- A consumer that remembers HC1 as authority would reject these legitimate
-- new input states. Only the supplied text is asserted, never server state.
H.difficultyHud.tier:SetText('Normal');Settle(H)
ExpectCaption(H,'Normal',nil,'explicit Normal after HC1')
H=F.Reload(Before('Normal'));Settle(H)
ExpectCaption(H,'Normal',nil,'offline module reload explicit Normal')

H.difficultyHud.tier:SetText('');Settle(H)
ExpectCaption(H,nil,nil,'absent difficulty text')
H=F.Reload(Before(''));Settle(H)
ExpectCaption(H,nil,nil,'offline module reload absent difficulty')

print('PASS server_status_reload_consumer checks='..checks..'; synthetic producer; native cause UNKNOWN')
