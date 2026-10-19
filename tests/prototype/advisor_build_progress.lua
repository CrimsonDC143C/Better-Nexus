-- The Journal tab that was "Nexus Advisor" states its purpose: "Nexus
-- Progress", headed Build Progress, with a short read-only intro whose full
-- purpose and notes stay in its tooltip and in the details. What is still
-- missing comes first, then display-only Echo rows (icon tile, family text,
-- short status) for the supplied missing and off-Wishlist families. Every
-- provider section (target, pending, extras, Tome levers, notes, estimate,
-- version) stays unchanged behind Show details. Missing, malformed or
-- contradictory data stays unknown; family coverage is never copy
-- completeness; an empty off-Wishlist list is "none listed", never 0; a
-- Wishlist with no requested family claims no coverage. The page and its
-- tooltips use plain words, not implementation terms. With no Wishlist, the
-- page says so and offers the Journal's own assignment controls. The tab keeps
-- its attachment frames. No interaction rolls, spends, locks, saves or
-- activates anything. Real boot and Journal tab code, synthetic journal frames
-- and provider data (advisor_build_progress_runtime reads the real provider).
local H=dofile('tests/prototype/orbs_support.lua');local M=H.M
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function texts()
 local out={}
 for _,f in ipairs(H.frames)do
  if f.IsVisible and f:IsVisible()then
   local value=f:GetText();if type(value)=='string'then out[#out+1]=value end
   for _,r in ipairs(f.regions or {})do if r:IsShown()then
    value=r:GetText();if type(value)=='string'then out[#out+1]=value end
   end end
  end
 end
 return table.concat(out,'\n')
end
local function plain(s)return(s:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''))end
local function button(label)
 for _,b in ipairs(H.frames)do if b.kind=='Button' and b:GetText()==label and b:IsVisible()then return b end end
end
local function quiet()
 local s=M.Status()
 return table.concat({#H.actions,tostring(s.state),tostring(s.spent),tostring(Nexus.RecomputeStats().autoEnabled)},'|')
end
-- Tooltip lines, captured for the checks; the harness tooltip draws nothing.
local tip={}
GameTooltip.SetOwner=function()tip={}end
GameTooltip.AddLine=function(_,text)tip[#tip+1]=tostring(text)end
GameTooltip.SetText=function(_,text)tip[#tip+1]=tostring(text)end
local function hover(f)f.scripts.OnEnter(f);local out=table.concat(tip,'\n');f.scripts.OnLeave(f);return out end
-- The harness GetSpellInfo returns a name only; give every spell a texture so
-- the checks see which identity the row resolved.
local realInfo=GetSpellInfo
GetSpellInfo=function(id)return realInfo(id),'','Interface\\Icons\\Test_'..tostring(id)end
local QUESTION='Interface\\Icons\\INV_Misc_QuestionMark'
local NOTES_FIRST='Compares the assigned Wishlist with the active Saved Build; planned locked targets are not proof of ownership.'
local data
local journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
CreateFrame('ScrollFrame','ProjectEbonholdEchoJournalScroll',journal)
CreateFrame('Button','ProjectEbonholdEchoJournalTab1',journal)
check(Nexus.JournalTab.TryInstall(function()return data end),'the Journal tab installs')
local tab=assert(NexusJournalTab,'the tab keeps its frame name')
check(tab:GetText()=='Nexus Progress','the tab names its purpose: '..tostring(tab:GetText()))
check(NexusJournalPanel and NexusJournalPanel:GetParent()==journal,'the page stays inside the Journal')
local page=assert(NexusJournalScroll.scrollChild,'the page has its scrolled content')
local function rows()
 local out={}
 for _,f in ipairs(H.frames)do if f.parent==page and f.label and f.status and f:IsVisible()then out[#out+1]=f end end
 return out
end
local function row(label)for _,r in ipairs(rows())do if r.label:GetText()==label then return r end end end
local function introHover()
 for _,f in ipairs(H.frames)do if f.parent==page and f.kind=='Frame' and not f.label and f.scripts.OnEnter then return f end end
end
-- The visible line that starts with `prefix`, and the hover area over it.
local function lineOf(prefix)
 for _,r in ipairs(page.regions)do
  if r:IsShown() and type(r:GetText())=='string' and plain(r:GetText()):find(prefix,1,true)==1 then return r end
 end
end
local function hoverOver(fs)
 for _,f in ipairs(H.frames)do
  if f.parent==page and f:IsShown() and f.points[1] and f.points[1][2]==fs and f.scripts.OnEnter then return f end
 end
end
-- Everything the player can read on the page and in its tooltips, details
-- folded: no implementation terms.
local JARGON={'provider','catalog','malformed','recogni','grammar','advisor'}
local function pageWords()
 local out={}
 local function under(f)while f do if f==NexusJournalPanel then return true end f=f.parent end end
 for _,f in ipairs(H.frames)do
  if under(f) and f:IsVisible()then
   out[#out+1]=type(f:GetText())=='string' and f:GetText() or ''
   for _,r in ipairs(f.regions or {})do if r:IsShown() and type(r:GetText())=='string' then out[#out+1]=r:GetText() end end
   if f.scripts.OnEnter then out[#out+1]=hover(f) end
  end
 end
 return plain(table.concat(out,'\n')):lower()
end
local function plainWords(label)
 local words=pageWords()
 for _,term in ipairs(JARGON)do check(not words:find(term,1,true),label..': no "'..term..'" on the page or in its tooltips') end
end

-- 1. An assigned Wishlist with missing families: the takeaway first.
data={sections={
 {title='Target',lines={"Wishlist 'Raid plan' (Echo Wishlist build): 6 Echo families -- 2 represented, 4 missing, 1 off-Wishlist families in the saved build"}},
 {title='Pending (4)',lines={'Arcane Echo','Fire Echo','Frost Echo','Shadow Echo'}},
 {title='Extra copies compared with the plan',lines={'Holy Echo  (a later run may reduce these extras)'}},
 {title='Tome levers',lines={'lever 7: disable (done)'}},
 {title='Notes',lines={NOTES_FIRST,'about 3 runs'}},
},version='Nexus test.9094'}
local before=quiet()
tab:Click();Nexus.JournalTab.Refresh()
local shown=texts()
check(NexusJournalPanel:IsVisible(),'the page opens from the tab')
check(shown:find('Build Progress',1,true),'the page is headed Build Progress')
check(shown:find('Assigned Wishlist vs active Saved Build. Read-only.',1,true),'a short intro says what is compared and that the page only reads')
check(not shown:find('This page only shows information',1,true),'the long purpose is not on the page itself')
local about=hover(assert(introHover(),'the intro has a tooltip'))
check(about:find('This page only shows information',1,true) and about:find('does not roll, spend Orbs, lock Echoes',1,true)
 and about:find('Compares the assigned Wishlist with the ACTIVE Saved Build.',1,true) and about:find('Set associations in My Builds',1,true),
 'the full purpose and notes stay in the intro tooltip')
local missing=shown:find('Still missing 4 Echo families: Arcane Echo, Fire Echo, Frost Echo and 1 more.',1,true)
check(missing,'what is still missing comes first: '..shown)
check(shown:find('Family coverage, not copies',1,true),'family coverage is not presented as copy completeness')
check(shown:find("Wishlist 'Raid plan' (Echo Wishlist build)",1,true),'with the provider\'s own target')
check(plain(shown):find('Represented 2 of 6   Missing 4   Off Wishlist 1',1,true),'and its counts as short status labels')
check(#rows()==5 and row('Arcane Echo').status:GetText()=='Missing' and row('Holy Echo').status:GetText()=='Off Wishlist',
 'one row per supplied missing and off-Wishlist family, each with a short status word')
check(row('Arcane Echo').icon:GetTexture()==QUESTION,'a name the catalog does not hold gets the neutral icon')
check(shown:find('Estimate, not a prediction: about 3 runs',1,true),'the estimate is labelled as an estimate')
check(not shown:find('Pending (4)',1,true) and not shown:find('Echo availability controls',1,true) and not shown:find('test.9094',1,true),
 'the detailed sections wait behind Show details')
local countsTip=hover(assert(hoverOver(assert(lineOf('Represented 2 of 6'),'the counts line')),'the counts line has a tooltip'))
check(countsTip:find('Family coverage, not copies',1,true)
 and countsTip:find('families in the active Saved Build that the assigned Wishlist does not request',1,true),
 'the counts tooltip explains family coverage and a listed off-Wishlist count: '..countsTip)
plainWords('an assigned Wishlist')
check(quiet()==before,'opening the page acts on nothing')

-- 2. Show details keeps every original section; Hide details folds them again.
local toggle=assert(button('Show details'),'the page offers Show details')
toggle:Click();shown=texts()
for _,wanted in ipairs({'Compares the assigned Wishlist with the ACTIVE Saved Build.','This page only shows information',
 'Pending (4)','Shadow Echo','Extra copies compared with the plan','Holy Echo  (a later run may reduce these extras)',
 'Notes','about 3 runs','test.9094'})do
 check(shown:find(wanted,1,true),'the details keep: '..wanted)
end
check(shown:find('Echo availability controls',1,true),'the Tome levers section keeps its public wording')
check(shown:find('Still missing 4',1,true)<shown:find('Pending (4)',1,true),'the takeaway stays above the details')
check(button('Hide details'),'the button now says Hide details')
button('Hide details'):Click()
check(not texts():find('Pending (4)',1,true) and button('Show details'),'Hide details folds the sections again')
check(#rows()==5,'the rows stay on the page with the details folded')
check(not button('Assign in My Builds'),'an assigned Wishlist needs no assignment shortcut')
check(quiet()==before,'showing and hiding details acts on nothing')

-- 3. Everything represented. An extras list that contradicts the target's
-- count keeps progress unknown; a consistent Pending (0) supports family
-- coverage only, never copy completeness. The extras list is filled only from
-- a confirmed active Saved Build and arrives empty when none was compared, so
-- an empty list is "none listed", never a known 0.
data.sections[1].lines[1]="Wishlist 'Raid plan': 2 Echo families -- 2 represented, 0 missing, 0 off-Wishlist families in the saved build"
data.sections[2]={title='Pending (0)',lines={}}
Nexus.JournalTab.Refresh();shown=texts()
check(shown:find('Family progress is unknown: the supplied counts and lists do not agree.',1,true)
 and not shown:find('No requested Echo family is missing',1,true),'a contradicting extras list keeps progress unknown')
local function shownHovers()
 local n=0
 for _,f in ipairs(H.frames)do if f.parent==page and f.kind=='Frame' and not f.label and f.scripts.OnEnter and f:IsShown()then n=n+1 end end
 return n
end
check(not lineOf('Represented') and shownHovers()==1,'unknown progress: no counts line, and only the intro keeps a hover area')
data.sections[3]={title='Extra copies compared with the plan',lines={}}
Nexus.JournalTab.Refresh();shown=texts()
check(shown:find('No requested Echo family is missing: each has at least one known copy.',1,true),'a complete family target says so')
check(shown:find('That is family coverage, not copy completeness; requested copies may still be missing.',1,true),
 'and says that copies may still be missing')
check(plain(shown):find('Represented 2 of 2   Missing 0   Off Wishlist: none listed',1,true) and #rows()==0,
 'an empty off-Wishlist list is none listed, and no rows are shown')
check(not plain(shown):find('Off Wishlist 0',1,true),'an empty list is never shown as a known 0')
countsTip=hover(assert(hoverOver(assert(lineOf('Represented 2 of 2'),'the counts line')),'the counts line has a tooltip'))
check(countsTip:find('Off Wishlist: none listed.',1,true) and countsTip:find("listed only when the active Saved Build's contents are confirmed",1,true)
 and countsTip:find('It does not show that there are none.',1,true),'its tooltip says why none listed is not zero: '..countsTip)
plainWords('none listed')

-- 3b. A Wishlist that requests no Echo family claims no coverage, and the
-- estimate's no-target wording becomes a plain unavailable estimate.
data.sections[1].lines[1]="Wishlist 'Empty plan' (Echo Wishlist build): 0 Echo families -- 0 represented, 0 missing, 1 off-Wishlist families in the saved build"
data.sections[3]={title='Extra copies compared with the plan',lines={'Holy Echo  (a later run may reduce these extras)'}}
data.sections[5]={title='Notes',lines={NOTES_FIRST,'no wishlist target - advisor mode'}}
Nexus.JournalTab.Refresh();shown=plain(texts())
check(shown:find('This Wishlist requests no Echo families, so there is no family progress to show.',1,true),
 'zero requested families: an honest takeaway: '..shown)
check(not shown:find('each has at least one known copy',1,true) and not shown:find('No requested Echo family is missing',1,true),
 'and no vacuous coverage claim')
check(shown:find('Represented 0 of 0   Missing 0   Off Wishlist 1',1,true) and #rows()==1 and row('Holy Echo'),
 'its counts and supplied off-Wishlist family stay')
check(shown:find('Estimate: unavailable.',1,true) and not shown:find('Estimate, not a prediction',1,true),
 'the no-target estimate is a plain unavailable estimate')
plainWords('zero requested families')
button('Show details'):Click()
check(texts():find('no wishlist target - advisor mode',1,true),'the original estimate line stays in the details')
button('Hide details'):Click()

-- 4. No Wishlist: a short fallback and the Journal's own assignment controls.
data={sections={
 {title='Target',lines={'No wishlist set -- advisor only.',"Design a build with 'New Wishlist' (the Echo Wishlist section)."}},
 {title='Tome levers',lines={}},
 {title='Notes',lines={NOTES_FIRST,'no estimate (advisor mode)'}},
},version='Nexus test.9094'}
Nexus.JournalTab.Refresh();shown=texts()
check(shown:find('No Wishlist is assigned. Assign one in My Builds to see its progress.',1,true),'no Wishlist: a plain fallback')
check(#rows()==0 and not shown:find('Estimate, not a prediction',1,true) and not shown:find('Estimate: unavailable',1,true),
 'no rows and no estimate without a Wishlist')
local assign=assert(button('Assign in My Builds'),'and a way to the assignment controls')
button('Show details'):Click()
check(texts():find('New Wishlist',1,true),'the original guidance stays in the details')
assign:Click()
check(not NexusJournalPanel:IsShown() and tab:IsVisible(),'the shortcut closes this page onto the Journal, the tab stays')
check(quiet()==before,'and assigns, saves or activates nothing by itself')

-- 5. No data at all.
data=nil;tab:Click();Nexus.JournalTab.Refresh()
check(NexusJournalPanel:IsVisible() and texts():find('no data yet',1,true),'without data the page says so')
check(texts():find('No sections were received.',1,true),'and the details say that nothing was received')
tab:Click();check(not NexusJournalPanel:IsShown(),'a second tab click still closes the page')

-- 6. Echo rows: a catalog icon only for an exact, unique family name; the
-- provider's off-Wishlist explanation is not part of the name; long labels
-- keep their complete text in the tooltip.
local LONG='A very long synthetic Echo family label that cannot fit on one Build Progress row and keeps going to its end'
local function rowData()
 return {sections={
  {title='Target',lines={"Wishlist 'Echo rows' (active loadout): 5 Echo families -- 1 represented, 4 missing, 3 off-Wishlist families in the saved build"}},
  {title='Pending (4)',lines={'Desired A','Excess high','Protected low',LONG}},
  {title='Extra copies compared with the plan',lines={'Desired B  (a later run may reduce these extras)',
   'Disposable A  (not on the target plan; compare after the next run)','Echo 7 [new wording]'}},
  {title='Tome levers',lines={'lever 7: disable'}},
  {title='Notes',lines={NOTES_FIRST,'about 2 runs'}},
 },version='Nexus test.9094'}
end
data=rowData()
tab:Click();if button('Hide details')then button('Hide details'):Click()end
shown=texts()
local list=rows()
check(#list==7,'seven display rows: four missing, three off Wishlist ('..#list..')')
for i,label in ipairs({'Desired A','Excess high','Protected low',LONG,'Desired B','Disposable A','Echo 7 [new wording]'})do
 check(list[i] and list[i].label:GetText()==label,'row '..i..' shows '..label)
end
for i=1,4 do check(list[i].status:GetText()=='Missing','missing rows say Missing') end
for i=5,7 do check(list[i].status:GetText()=='Off Wishlist','off-Wishlist rows say Off Wishlist') end
check(row('Desired A').icon:GetTexture()=='Interface\\Icons\\Test_410002','an exact unique family name gets its member icon')
check(row('Protected low').icon:GetTexture()=='Interface\\Icons\\Test_410005','a grouped family resolves through its family name and members')
check(row('Excess high').icon:GetTexture()==QUESTION,'a member name that is not the family name identifies nothing')
check(row(LONG).icon:GetTexture()==QUESTION and row('Echo 7 [new wording]').icon:GetTexture()==QUESTION,
 'text that is not exactly a family name gets the neutral icon')
check(row('Desired B').icon:GetTexture()=='Interface\\Icons\\Test_410004' and row('Disposable A').icon:GetTexture()=='Interface\\Icons\\Test_410001',
 'the known off-Wishlist explanations are not part of the family name')
local t=hover(row(LONG))
check(t:find(LONG,1,true) and t:find('Missing: no known copy of this requested Echo family.',1,true) and t:find('neutral icon',1,true),
 'a long label keeps its complete text in the tooltip')
t=hover(row('Desired B'))
check(t:find('Off Wishlist: in the active Saved Build',1,true) and t:find('Source text: Desired B  (a later run may reduce these extras)',1,true),
 'an off-Wishlist row keeps its source text and explanation')
t=hover(row('Echo 7 [new wording]'))
check(t:find('Echo 7 [new wording]',1,true) and not t:find('Source text',1,true),'an unrecognized ending stays in the label, untouched')
plainWords('Echo rows')
check(plain(shown):find('Represented 1 of 5   Missing 4   Off Wishlist 3',1,true),'represented is a count only')
check(not plain(shown):find('Represented (',1,true),'no represented-family list is invented')
check(shown:find('Still missing 4 Echo families: Desired A, Excess high, Protected low and 1 more.',1,true),'the takeaway names the first three')
check(shown:find('Estimate, not a prediction: about 2 runs',1,true),'the estimate is labelled')

-- 7. Details: the raw provider lines stay complete and unchanged.
button('Show details'):Click();shown=texts()
for _,wanted in ipairs({'Pending (4)','Desired B  (a later run may reduce these extras)','Echo 7 [new wording]',LONG,
 'Echo availability controls','about 2 runs','This page only shows information','Family coverage, not copies','test.9094'})do
 check(shown:find(wanted,1,true),'the details keep: '..wanted)
end
check(#rows()==7,'the rows stay with the details open')
button('Hide details'):Click()
check(not texts():find('Pending (4)',1,true) and #rows()==7,'Hide details folds only the details')

-- 8. Passive refresh: the same rows and scripts are reused, nothing is
-- created, requested or changed; fewer families hide the obsolete rows.
local frameCount,first=#H.frames,rows()[1]
local enter,sent=first.scripts.OnEnter,#H.sent
for _=1,3 do Nexus.JournalTab.Refresh() end
check(#H.frames==frameCount and rows()[1]==first and first.scripts.OnEnter==enter and #rows()==7,
 'repeated refreshes reuse every row frame and script')
data.sections[1].lines[1]="Wishlist 'Echo rows' (active loadout): 2 Echo families -- 1 represented, 1 missing, 0 off-Wishlist families in the saved build"
data.sections[2]={title='Pending (1)',lines={'Desired A'}}
data.sections[3]={title='Extra copies compared with the plan',lines={}}
Nexus.JournalTab.Refresh()
check(#rows()==1 and rows()[1]==first and #H.frames==frameCount,'fewer families hide the obsolete rows without new frames')
data=rowData();Nexus.JournalTab.Refresh()
check(#rows()==7 and #H.frames==frameCount,'more families reuse the pooled rows')
check(quiet()==before and #H.sent==sent,'refreshing acts on nothing and sends nothing')

-- 9. Unknown stays unknown: a missing, malformed or contradicted Pending list,
-- contradictory counts or a changed target grammar never reads as complete.
local GOOD="Wishlist 'Raid plan' (Echo Wishlist build): 2 Echo families -- 2 represented, 0 missing, 0 off-Wishlist families in the saved build"
local function extras(lines)return{title='Extra copies compared with the plan',lines=lines or {}}end
local function unknown(sections,reason,label)
 data={sections=sections,version='Nexus test.9094'};Nexus.JournalTab.Refresh()
 local s=plain(texts())
 check(s:find('Family progress is unknown: '..reason,1,true),label..': '..s)
 check(not s:find('No requested Echo family is missing',1,true) and not s:find('each has at least one known copy',1,true)
  and not s:find('Represented 2 of',1,true) and not s:find('Still missing',1,true) and #rows()==0,label..': nothing is claimed')
 return s
end
local s=unknown({{title='Target',lines={GOOD}},extras(),{title='Notes',lines={NOTES_FIRST,'about 1 run'}}},
 'the list of missing families was not received.','target present, Pending absent')
check(s:find(GOOD,1,true),'the raw target line stays visible when its counts cannot be used')
check(s:find('the original lines are under Show details.',1,true),'and the original lines stay reachable')
plainWords('unknown progress')
local BAD_PENDING='the list of missing families could not be read or does not match its count.'
unknown({{title='Target',lines={GOOD}},{title='Pending (1)',lines={}},extras()},BAD_PENDING,'a Pending count without its names')
unknown({{title='Target',lines={GOOD}},{title='Pending',lines={}},extras()},BAD_PENDING,'a Pending title without a count')
unknown({{title='Target',lines={GOOD}},{title='Pending (0)',lines='none'},extras()},BAD_PENDING,'Pending lines that are not a list')
unknown({{title='Target',lines={"Wishlist 'Raid plan': 2 Echo families -- 1 represented, 1 missing, 0 off-Wishlist families in the saved build"}},
 {title='Pending (1)',lines={7}},extras()},BAD_PENDING,'a Pending entry that is not a name')
unknown({{title='Target',lines={GOOD}},{title='Pending (1)',lines={'Arcane Echo'}},extras()},
 'the supplied counts and lists do not agree.','Pending contradicts the target count')
unknown({{title='Target',lines={"Wishlist 'Raid plan': 6 Echo families -- 2 represented, 3 missing, 0 off-Wishlist families in the saved build"}},
 {title='Pending (3)',lines={'A','B','C'}},extras()},'the supplied counts and lists do not agree.','target counts that do not add up')
unknown({{title='Target',lines={GOOD}},{title='Pending (0)',lines={}},{title='Pending (0)',lines={}},extras()},
 'the supplied counts and lists do not agree.','two Pending lists')
s=unknown({{title='Target',lines={'Raid plan: every family 2/2'}},{title='Pending (0)',lines={}},extras()},
 'the Wishlist summary line could not be read.','a changed target grammar')
check(s:find('Raid plan: every family 2/2',1,true),'the unrecognized target line is shown as supplied')
plainWords('an unreadable summary line')
unknown({{title='Target',lines={"Wishlist 'Raid plan' (new tag): 2 Echo families -- 2 represented, 0 missing, 0 off-Wishlist families in the saved build"}},
 {title='Pending (0)',lines={}},extras()},'the Wishlist summary line could not be read.','an unknown source tag')
-- A Wishlist name is never read as counts: only the anchored end of the line is.
data={sections={{title='Target',lines={"Wishlist 'x: 9 Echo families -- 9 represented, 0 missing, 0 off-Wishlist families in the saved build'"
 .." (Echo Wishlist build): 6 Echo families -- 2 represented, 4 missing, 0 off-Wishlist families in the saved build"}},
 {title='Pending (4)',lines={'A1','B1','C1','D1'}},extras()}}
Nexus.JournalTab.Refresh();s=plain(texts())
check(s:find('Represented 2 of 6   Missing 4   Off Wishlist: none listed',1,true) and not s:find('Represented 9',1,true),
 'counts come from the end of the provider line, not from the Wishlist name')
data={sections={{title='Target',lines={GOOD}},{title='Pending (0)',lines={}}}}
Nexus.JournalTab.Refresh();s=plain(texts())
check(s:find('Off Wishlist: unavailable',1,true) and s:find('No requested Echo family is missing',1,true),
 'a missing extras list is unavailable, not zero')
countsTip=hover(assert(hoverOver(assert(lineOf('Represented 2 of 2'),'the counts line')),'the counts line has a tooltip'))
check(countsTip:find('Off Wishlist: unavailable. The list of these families could not be read',1,true),
 'and its tooltip says so plainly: '..countsTip)
data={sections={{title='Notes',lines={NOTES_FIRST,'about 1 run'}}}}
Nexus.JournalTab.Refresh();s=plain(texts())
check(s:find('Build Progress is unavailable: the Wishlist summary line is missing.',1,true)
 and not s:find('Estimate, not a prediction',1,true),
 'no target line: unavailable, and no estimate out of context')
plainWords('no summary line')
Nexus.JournalTab.TryInstall(function()error('synthetic provider failure')end)
Nexus.JournalTab.Refresh();s=plain(texts())
check(s:find('Build Progress data could not be read. Nothing is assumed.',1,true) and #rows()==0,
 'a failing provider is reported as a failure, not as progress')
plainWords('a failure')
Nexus.JournalTab.TryInstall(function()return data end)

-- 10. Icons come only from an exact, unique family identity, indexed once per
-- catalog table: a name two families share or a member not linked back to
-- its family stays neutral, and a rebuilt catalog is read again.
local A=Nexus.GameAdapter;local realCatalog=A.Catalog
local function catalogOf(map)
 local c={rows={},familyName={},familyMembers={},familyOf={}}
 for key,v in pairs(map)do
  c.familyName[key]=v[1];c.familyMembers[key]=v[2]
  for _,id in ipairs(v[2])do c.rows[id]={spellId=id,name=v[1],quality=1};c.familyOf[id]=v[3] or key end
 end
 return c
end
local current=catalogOf({g1={'Twin Echo',{990001}},g2={'Twin Echo',{990002}},g3={'Solo Echo',{990003}},g4={'Broken Echo',{990004},'g9'}})
A.Catalog=function()return current end
data={sections={{title='Target',lines={"Wishlist 'Icons': 3 Echo families -- 0 represented, 3 missing, 0 off-Wishlist families in the saved build"}},
 {title='Pending (3)',lines={'Broken Echo','Solo Echo','Twin Echo'}},extras()}}
Nexus.JournalTab.Refresh()
check(row('Solo Echo').icon:GetTexture()=='Interface\\Icons\\Test_990003','a unique family name resolves')
check(row('Twin Echo').icon:GetTexture()==QUESTION,'a name two families share stays neutral')
check(row('Broken Echo').icon:GetTexture()==QUESTION,'a member not linked back to its family stays neutral')
current=catalogOf({g3={'Solo Echo',{990005}}})
Nexus.JournalTab.Refresh()
check(row('Solo Echo').icon:GetTexture()=='Interface\\Icons\\Test_990005','a rebuilt catalog is indexed again')
check(row('Twin Echo').icon:GetTexture()==QUESTION,'a family the catalog no longer holds is neutral')
A.Catalog=realCatalog;GetSpellInfo=realInfo
check(quiet()==before and #H.sent==sent,'icon lookups request and change nothing')
tab:Click();check(not NexusJournalPanel:IsShown(),'the tab still closes the page')
print('PASS advisor_build_progress: short read-only intro, takeaway first, Echo rows, family vs copy, none listed is not 0, zero requested families, plain words, unknown data, details preserved, pooled rows, no-Wishlist fallback checks='..checks)
