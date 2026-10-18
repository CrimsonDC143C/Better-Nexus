-- Reuse the exact real Journal reproduction, then follow its adjacent actual controls.
local originalDofile=dofile
local H
dofile=function(path)
 local result=originalDofile(path)
 if path=='tests/prototype/orbs_support.lua' then H=result end
 return result
end
dofile('tests/prototype/assignment_journal_picker.lua')
dofile=originalDofile
assert(H)
-- `planA`: the edit control opened Plan A's complete design instead of Plan B's.
local function checkExport(planA)
 local box=CreateFrame('EditBox',nil,UIParent)
 StaticPopupDialogs.NEXUS_EXPORT_WISHLIST.OnShow({editBox=box})
 local parsed=assert(Nexus.Codec.DecodeEBH1(box._nexusExplicitExportText))
 local a,b=false,false
 for _,row in ipairs(parsed.entries)do if row.locked then
  a=a or row.spellId==200080;b=b or row.spellId==200081
 end end
 if planA then assert(a and not b,'actual row gear opens that row\'s complete design')
 else assert(b and not a,'actual Journal edit control opens the selected complete design') end
end
Nexus.JournalTab.RefreshAssociations()
assert(NexusAssociatedWishlistDesignButton:IsEnabled());NexusAssociatedWishlistDesignButton:Click();checkExport()
NexusEditorFrame:Hide();ProjectEbonholdEchoJournal:Show();Nexus.JournalTab.RefreshAssociations()
NexusActiveWishlistSelector:Click()
-- The selector names the exact assignment (Plan B), so the list leaves it out;
-- the equal-content Plan A is another Wishlist and stays, unmarked.
local gear
for _,row in ipairs(NexusWishlistOnlyPicker.children)do if row.nameButton and row:IsVisible() then
 local label=row.nameButton.text:GetText()
 if label:find('Plan A',1,true)then assert(not label:find('[Selected]',1,true),'equal rolled contents cannot mark Plan A as selected');gear=row.gear end
 assert(not label:find('Plan B',1,true),'the exact assignment is named on the selector, not listed again')
end end
assert(NexusActiveWishlistSelector.text:GetText():find('Plan B',1,true),'the selector names the exact assignment')
assert(gear);gear:Click();checkExport(true)
-- Back to the selected design through its Journal edit control.
NexusEditorFrame:Hide();ProjectEbonholdEchoJournal:Show();Nexus.JournalTab.RefreshAssociations()
NexusAssociatedWishlistDesignButton:Click();checkExport()
H.granted={['Echo 81']={{spellId=200081,quality=1}}};H.Notify();H.A.Poll()
assert(not Nexus.OrbRuntime.Start(1),'required copy after visible Journal assignment must remain reserved')
assert(H.Count('orb-spend')==0 and H.Count('take')==0,'visible controls never bypass source protection')
print('PASS Journal associated Edit, row gear, exact selection named not listed, export and required-copy guard')
