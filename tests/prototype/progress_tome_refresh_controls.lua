-- Standalone renderer/scheduler acceptance controls. Synthetic counting data;
-- real JournalTab and existing scanner. Requires proposed JournalTab.Invalidate.
Nexus,NexusDB,WishlistRealizerDB=nil,nil,nil
local H=dofile('tests/prototype/harness.lua')
H.playerLevel=80
local journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
journal:SetSize(570,450)
CreateFrame('ScrollFrame','ProjectEbonholdEchoJournalScroll',journal)
CreateFrame('Button','ProjectEbonholdEchoJournalTab1',journal)
H.Boot()
local J=assert(Nexus.JournalTab)
assert(type(J.Invalidate)=='function','SETUP: proposed JournalTab.Invalidate is installed')
local checks,failures=0,{}
local function check(v,msg)
 checks=checks+1
 if not v then failures[#failures+1]=msg;print('MISS '..msg) end
end
local calls,times,raiseInside=0,{},false
local data={sections={
 {title='Target',lines={'No wishlist set -- advisor only.'}},
 {title='Tome state coverage',lines={'Synthetic counting-provider fixture only.'}},
 {title='Enabled tomes (client mirror)',lines={},tomeRows={
  {name='Counting Tome',leverId=900001,observed='enabled',known=true,status='Enabled',
   icon=false,echoNames={'Counting Echo'}}}},
}}
local function countingProvider()
 calls=calls+1;times[#times+1]=H.now
 if raiseInside then
  raiseInside=false
  J.Invalidate()
 end
 return data
end
assert(J.TryInstall(countingProvider),'SETUP: real Journal renderer installed')
local actions0,sent0=#H.actions,#H.sent
local function button(text)
 for _,r in ipairs(H.frames) do
  if r.kind=='Button' and r:IsVisible() and r:GetText()==text then return r end
 end
end
local function ui(label,fn)
 local actions,sent=#H.actions,#H.sent
 fn()
 check(#H.actions==actions and #H.sent==sent,label..' sends no gameplay/network action')
end
local function invalidateBurst(label)
 local before=calls
 for _=1,20 do J.Invalidate() end
 check(calls==before,label..' invalidation performs no synchronous provider call')
end
local function nextFlush(label,before)
 local started=H.now
 for _=1,20 do
  if calls>before then break end
  H.Advance(.05,.05)
 end
 check(calls==before+1,label..' performs exactly one provider call on first scanner flush')
 check(H.now-started<=.800001,label..' flushes within existing0.75s scanner cadence')
 print('FLUSH '..label..' calls='..calls..' delta='..(calls-before)..' wait='..string.format('%.2f',H.now-started))
end
-- No provider read while the Progress panel is hidden.
invalidateBurst('hidden-tab')
H.Advance(1.6,.05)
check(calls==0,'hidden Progress receives zero provider calls')
ui('select Progress',function()journal:Show();assert(NexusJournalTab):Click()end)
check(calls==1 and NexusJournalPanel:IsVisible(),'selecting real Progress renders once')
-- Collapsed details remain lazy even though the summary page is visible.
local before=calls
invalidateBurst('collapsed')
H.Advance(1.6,.05)
check(calls==before,'collapsed invalidation receives zero provider calls')
ui('expand details',function()assert(button('Show details'),'SETUP: Show details'):Click()end)
check(calls==before+1,'expanding details renders the current provider once')
-- A real direct refresh consumes an already-dirty bit; no later duplicate.
before=calls;invalidateBurst('direct-refresh')
ui('direct Refresh',function()J.Refresh()end)
check(calls==before+1,'direct visible refresh renders once')
H.Advance(1.6,.05)
check(calls==before+1,'direct refresh consumes invalidation bit')
-- Bursts coalesce into one existing scanner flush, then steady idle does none.
before=calls;invalidateBurst('expanded-burst')
nextFlush('expanded-burst',before)
H.Advance(1.6,.05)
check(calls==before+1,'coalesced burst has no second or periodic idle render')
-- An invalidation raised inside a provider must survive the current render.
before=calls;raiseInside=true;J.Invalidate()
check(calls==before,'provider-reentry invalidation is asynchronous')
nextFlush('provider-reentry-leading',before)
local firstAt=times[#times]
nextFlush('provider-reentry-trailing',before+1)
local secondAt=times[#times]
check(secondAt-firstAt>=.70,'provider-raised dirty bit trails on a later scanner tick')
H.Advance(1.6,.05)
check(calls==before+2,'provider-raised invalidation produces one trailing flush and stops')
-- Parent-hidden panel may retain IsShown true: effective visibility gates work.
ui('hide journal parent',function()journal:Hide()end)
before=calls;invalidateBurst('hidden-parent')
H.Advance(1.6,.05)
check(calls==before,'parent-hidden details receive zero provider calls')
print('HIDDEN panelShown='..tostring(NexusJournalPanel:IsShown())..' panelVisible='..tostring(NexusJournalPanel:IsVisible()))
ui('reopen Progress',function()journal:Show();NexusJournalTab:Click()end)
check(calls==before+1,'reopening real Progress renders current data once')
H.Advance(1.6,.05)
check(calls==before+1,'reopening consumes retained dirty bit')
check(#H.actions==actions0 and #H.sent==sent0,'counting invalidation controls send no gameplay/network action')
print('RESULT checks='..checks..' failures='..#failures..' providerCalls='..calls)
assert(#failures==0,table.concat(failures,'\n'))
print('PASS Progress invalidation coalesces; visibility/lazy/direct/reentrant controls')
