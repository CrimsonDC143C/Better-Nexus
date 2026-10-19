-- Build Progress: the expanded Pending list is not shown twice when the page
-- has already validated it (approved display cleanup).
--
-- The Nexus Progress page (ui/JournalTab.lua) validates the provider's Target
-- line, its one "Pending (n)" list and the off-Wishlist list (Summarize).
-- Only when they agree does it draw one "Missing" row per family. Show details
-- then draws every provider section as received, so a validated Pending list
-- appears a second time as raw lines under its heading.
--
-- Approved: hide that expanded duplicate list ONLY when the same validated
-- summary already shows exactly those families. Kept: the raw Pending lines
-- whenever the summary is missing, unknown, malformed or contradicted (they
-- are the diagnostics); the provider data itself (never edited); every other
-- section; and the separate tome enable/disable requests.
--
-- Groups: BEHAVIOR (the approved suppression; expected to miss before the
-- display change), CONTROL (reachability, folded and zero states, unknown
-- summaries keep their raw lines, other sections and tome requests stay),
-- DATA (provider data, saved data, actions and the native slot unchanged).
-- STAGE = a page, button or heading was not reached (setup), never behaviour.
--
-- Real TOC boot, the real Journal tab install, its tab button, the page's own
-- Show/Hide details button and the real renderer; only the provider's
-- section data is synthetic (as in advisor_build_progress and tome_state_rows).
-- Expected visible text is computed through the production
-- Nexus.UserText.Message, as the page applies it. Loads everything from the
-- cwd, so the same bytes run against any source cut.
local H=dofile('tests/prototype/harness.lua')
H.Boot()
local results={}
local function record(group,id,ok,message)
 results[#results+1]={group=group,id=id,ok=ok==true}
 print((ok==true and 'OK   ' or 'MISS ')..group..' '..id..': '..tostring(message))
end
local function observe(id,message) print('OBSERVE '..id..': '..tostring(message)) end
local function stage(name,fn)
 local ok,err=pcall(fn)
 if not ok then record('STAGE',name,false,'did not complete: '..tostring(err)) end
end

local function Plain(s) return (tostring(s or ''):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')) end
-- What the page shows for `text` (it passes non-plain lines through UserText).
local function Visible(text)
 local U=Nexus.UserText
 if U and type(U.Message)=='function' then return Plain(U.Message(text)) end
 return Plain(text)
end
local function Serialize(v,seen)
 local t=type(v)
 if t=='string' then return string.format('%q',v) end
 if t~='table' then return t..':'..tostring(v) end
 seen=seen or {}
 if seen[v] then return '<cycle>' end
 seen[v]=true
 local keys={}
 for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return type(a)..tostring(a)<type(b)..tostring(b) end)
 local out={'{'}
 for _,k in ipairs(keys) do out[#out+1]='['..Serialize(k,seen)..']='..Serialize(v[k],seen)..',' end
 seen[v]=nil
 out[#out+1]='}'
 return table.concat(out)
end

-- Synthetic provider sections in the exact forms the page validates.
local NOTES_FIRST='Compares the assigned Wishlist with the active Saved Build; planned locked targets are not proof of ownership.'
local FAMILIES={'Arcane Echo','Fire Echo','Frost Echo','Shadow Echo'}
local OFF_LINE='Holy Echo  (a later run may reduce these extras)'
local TOME_REQUESTS='Tome requests awaiting confirmation'
local OTHER='Other notes'
local function Copy(list) local out={} for i,v in ipairs(list) do out[i]=v end return out end
local function Target(tag,total,rep,miss,off)
 return ("Wishlist 'Dedup plan'%s: %d Echo families -- %d represented, %d missing, %d off-Wishlist families in the saved build")
  :format(tag,total,rep,miss,off)
end
local function Tome(name,id,state,pending)
 return {name=name,leverId=id,observed=state,known=true,status=state=='disabled' and 'Disabled' or 'Enabled',
  icon='Interface\\Icons\\Tome_'..id,iconSource='tome spell',echoNames={name..' Echo'},pending=pending}
end
local REQUEST_ENABLE,REQUEST_DISABLE='Tome of the requested enable','Tome of the requested disable'
local function Requests()
 return {title=TOME_REQUESTS,lines={'Tome request text fallback'},
  tomeRows={Tome(REQUEST_ENABLE,880201,'disabled','enable'),Tome(REQUEST_DISABLE,880202,'enabled','disable')}}
end
local function Notes() return {title='Notes',lines={NOTES_FIRST,'about 3 runs'}} end
local GOOD=Target(' (Echo Wishlist build)',6,2,4,1)
-- A validated summary: four missing families, one off-Wishlist family.
local function Valid(extra)
 local s={{title='Target',lines={GOOD}},{title='Pending (4)',lines=Copy(FAMILIES)},
  {title='Extra copies compared with the plan',lines={OFF_LINE}},Requests()}
 for _,sec in ipairs(extra or {}) do s[#s+1]=sec end
 s[#s+1]=Notes()
 return {sections=s}
end
-- Summaries the page must not validate; their Pending lines stay raw.
local UNKNOWN={
 {id='COUNTS',why='Pending (3) contradicts the target count 4',
  sections={{title='Target',lines={GOOD}},{title='Pending (3)',lines={'Arcane Echo','Fire Echo','Frost Echo'}},
   {title='Extra copies compared with the plan',lines={OFF_LINE}},Notes()}},
 {id='NO-COUNT',why='a Pending title without its count',
  sections={{title='Target',lines={GOOD}},{title='Pending',lines=Copy(FAMILIES)},
   {title='Extra copies compared with the plan',lines={OFF_LINE}},Notes()}},
 {id='NOT-NAMES',why='a Pending entry that is not a name',
  sections={{title='Target',lines={Target(' (Echo Wishlist build)',4,2,2,0)}},{title='Pending (2)',lines={'Arcane Echo',7}},
   {title='Extra copies compared with the plan',lines={}},Notes()}},
 {id='UNKNOWN-TAG',why='a target line in an unknown form',
  sections={{title='Target',lines={Target(' (new tag)',6,2,4,1)}},{title='Pending (4)',lines=Copy(FAMILIES)},
   {title='Extra copies compared with the plan',lines={OFF_LINE}},Notes()}},
 {id='TWO-LISTS',why='two Pending lists',
  sections={{title='Target',lines={GOOD}},{title='Pending (4)',lines=Copy(FAMILIES)},{title='Pending (4)',lines=Copy(FAMILIES)},
   {title='Extra copies compared with the plan',lines={OFF_LINE}},Notes()}},
 {id='NO-TARGET',why='no target line at all',
  sections={{title='Pending (4)',lines=Copy(FAMILIES)},{title='Extra copies compared with the plan',lines={OFF_LINE}},Notes()}},
}

-- The Journal frames the tab attaches to, and the real install.
local journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
journal:SetSize(570,450)
CreateFrame('ScrollFrame','ProjectEbonholdEchoJournalScroll',journal)
CreateFrame('Button','ProjectEbonholdEchoJournalTab1',journal)
local calls,data=0,nil
local installedOk,installed=pcall(Nexus.JournalTab.TryInstall,function() calls=calls+1;return data end)
local page=NexusJournalScroll and NexusJournalScroll.scrollChild
if NexusJournalScroll then NexusJournalScroll:SetSize(520,360) end
local A=Nexus.GameAdapter
local before={store=Serialize(Nexus.Store.State()),actions=#H.actions,sent=#H.sent,
 active=tostring(A.Slots() and A.Slots().activeSlot)}

local function Button(label)
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and f:GetText()==label then return f end
 end
end
-- Visible page lines (the renderer's own line pool), top to bottom.
local function Lines()
 local out={}
 for _,r in ipairs(page.regions or {}) do
  local p=r.points and r.points[1]
  if r:IsShown() and p and type(r:GetText())=='string' then out[#out+1]={text=Plain(r:GetText()),y=tonumber(p[5]) or 0} end
 end
 table.sort(out,function(a,b) return a.y>b.y end)
 return out
end
-- Visible display rows on the page: family rows and tome rows.
local function Rows()
 local out={}
 for _,f in ipairs(H.frames) do
  if f.parent==page and f.label and f.status and f:IsVisible() then
   out[#out+1]={label=Plain(f.label:GetText()),status=Plain(f.status:GetText()),tome=f.tome~=nil}
  end
 end
 return out
end
local function MissingRows()
 local out={}
 for _,r in ipairs(Rows()) do if not r.tome and r.status=='Missing' then out[#out+1]=r.label end end
 return out
end
local function TomeRequestRows()
 local out={}
 for _,r in ipairs(Rows()) do if r.tome then out[r.label]=r.status end end
 return out
end
-- How often `name` is visible on the page as a whole line or a family row.
local function Occurrences(name)
 local want,n=Visible(name),0
 for _,l in ipairs(Lines()) do if l.text==want then n=n+1 end end
 for _,r in ipairs(Rows()) do if not r.tome and r.label==name then n=n+1 end end
 return n
end
local function Has(prefix)
 for _,l in ipairs(Lines()) do if l.text:find(prefix,1,true)==1 then return l.text end end
end
-- The lines under each provider section heading in the details, in the
-- provider's order. A heading keeps the provider's title text at its start.
local function Details(sections)
 local lines,start=Lines(),nil
 local about=Visible('About this page')
 for i,l in ipairs(lines) do if l.text==about then start=i;break end end
 assert(start,'SETUP (route): the details are drawn ("About this page" is visible)')
 local index,cursor={},start
 for k,sec in ipairs(sections) do
  local want=Visible(tostring(sec.title or ''))
  local found
  for i=cursor+1,#lines do
   local t=lines[i].text
   if t==want or t:sub(1,#want+1)==want..' ' then found=i;break end
  end
  assert(found,'SETUP (route): the details show the section heading "'..want..'"')
  index[k],cursor=found,found
 end
 local out={}
 for k=1,#sections do
  local body={}
  for i=index[k]+1,(index[k+1] or (#lines+1))-1 do body[#body+1]=lines[i].text end
  out[k]={title=sections[k].title,body=body}
 end
 return out
end
local function Body(details,title,nth)
 local seen=0
 for _,d in ipairs(details) do
  if d.title==title then
   seen=seen+1
   if seen==(nth or 1) then return d.body end
  end
 end
end
local function Contains(body,text)
 local want,n=Visible(text),0
 for _,l in ipairs(body or {}) do if l==want then n=n+1 end end
 return n
end
local function RawFamilyLines(body)
 local n=0
 for _,name in ipairs(FAMILIES) do n=n+Contains(body,name) end
 return n
end

local function Open()
 assert(installedOk and installed,'SETUP (route): the real Journal tab installs: '..tostring(installed))
 assert(page,'SETUP (route): the page has its scrolled content')
 if not (NexusJournalPanel and NexusJournalPanel:IsVisible()) then
  assert(NexusJournalTab,'SETUP (route): the Nexus Progress tab exists')
  NexusJournalTab:Click()
 end
 assert(NexusJournalPanel and NexusJournalPanel:IsVisible(),'SETUP (route): the Nexus Progress page is open')
end
local function SetDetails(expanded)
 local want=expanded and 'Hide details' or 'Show details'
 if not Button(want) then
  local b=Button(expanded and 'Show details' or 'Hide details')
  assert(b,'SETUP (route): the page offers its Show/Hide details button')
  b:Click()
 end
 assert(Button(want),'SETUP (route): the details are '..(expanded and 'shown' or 'folded'))
end
-- Render `d` through the provider and the page's own refresh.
local function Render(d,expanded)
 data=d
 Open()
 Nexus.JournalTab.Refresh()
 SetDetails(expanded)
 return Serialize(d)
end
local function Unchanged(id,snapshot)
 record('DATA',id..'-PROVIDER-DATA-UNCHANGED',Serialize(data)==snapshot,'the renderer did not edit the provider data')
end
local function ObserveBody(id,body) observe(id,'['..table.concat(body or {},' | ')..']') end

-- ===================================================================
-- A validated summary, details folded: reachability and the one-row view.
stage('valid-folded',function()
 local snap=Render(Valid(),false)
 local rows=MissingRows()
 record('CONTROL','VALID-FOLDED-MISSING-ROWS',#rows==4 and rows[1]==FAMILIES[1] and rows[4]==FAMILIES[4],
  'one Missing row per validated family: '..table.concat(rows,', '))
 local once=true
 for _,name in ipairs(FAMILIES) do if Occurrences(name)~=1 then once=false end end
 record('CONTROL','VALID-FOLDED-NO-DETAILS',not Has(Visible('About this page')) and not Has(Visible('Pending (4)')) and once,
  'folded details show no section and each family once')
 Unchanged('VALID-FOLDED',snap)
end)

-- A validated summary, details shown: the duplicate list and what stays.
stage('valid-expanded',function()
 local d=Valid()
 local snap=Render(d,true)
 local details=Details(d.sections)
 local pending=Body(details,'Pending (4)')
 ObserveBody('valid-expanded Pending (4)',pending)
 record('BEHAVIOR','DEDUP-NO-RAW-FAMILY-LIST',RawFamilyLines(pending)==0,
  'the validated Pending list is not drawn again under its heading: '..RawFamilyLines(pending)..' raw family line(s)')
 local counts={}
 local once=true
 for _,name in ipairs(FAMILIES) do
  local n=Occurrences(name);counts[#counts+1]=name..'='..n
  if n~=1 then once=false end
 end
 record('BEHAVIOR','DEDUP-ONE-COPY-PER-FAMILY',once,'each validated family is visible once (its Missing row): '..table.concat(counts,', '))
 record('CONTROL','VALID-EXPANDED-MISSING-ROWS',#MissingRows()==4,'the four Missing rows stay: '..#MissingRows())
 record('CONTROL','VALID-EXPANDED-PENDING-HEADING',pending~=nil,'the Pending (4) section heading stays in the details')
 local extras=Body(details,'Extra copies compared with the plan')
 record('CONTROL','VALID-EXPANDED-OFF-RAW-KEPT',Contains(extras,OFF_LINE)==1,
  'the off-Wishlist section keeps its raw line (not in scope)')
 local requests=TomeRequestRows()
 record('CONTROL','VALID-EXPANDED-TOME-REQUESTS',requests[REQUEST_ENABLE]=='Enable pending'
  and requests[REQUEST_DISABLE]=='Disable pending' and Body(details,TOME_REQUESTS)~=nil and #MissingRows()==4,
  'the tome enable/disable requests stay separate rows under their own heading')
 record('CONTROL','VALID-EXPANDED-NOTES-KEPT',Contains(Body(details,'Notes'),NOTES_FIRST)==1,'the notes section keeps its lines')
 Unchanged('VALID-EXPANDED',snap)
end)

-- A family name also supplied in another section: only the validated Pending
-- list is the duplicate; the same text elsewhere is not hidden by name.
stage('precise',function()
 local d=Valid({{title=OTHER,lines={'Arcane Echo'}}})
 local snap=Render(d,true)
 local details=Details(d.sections)
 local pending,other=Body(details,'Pending (4)'),Body(details,OTHER)
 ObserveBody('precise Pending (4)',pending);ObserveBody('precise '..OTHER,other)
 record('BEHAVIOR','DEDUP-PRECISE',RawFamilyLines(pending)==0 and Contains(other,'Arcane Echo')==1 and #other==1,
  'only the validated list is hidden; "Arcane Echo" under '..OTHER..' stays: pending='..RawFamilyLines(pending)
  ..' other='..Contains(other,'Arcane Echo'))
 Unchanged('PRECISE',snap)
end)

-- Fold and show again: the pooled lines are reused without a stale list.
stage('reexpand',function()
 local d=Valid()
 local snap=Render(d,true)
 SetDetails(false)
 record('CONTROL','REEXPAND-FOLDED',not Has(Visible('About this page')) and #MissingRows()==4,'folding hides every section again')
 SetDetails(true)
 local pending=Body(Details(d.sections),'Pending (4)')
 record('BEHAVIOR','DEDUP-REEXPAND',RawFamilyLines(pending)==0,'showing the details again still draws no duplicate list: '
  ..RawFamilyLines(pending))
 Unchanged('REEXPAND',snap)
end)

-- A validated summary with no missing family: nothing to hide or invent.
stage('zero',function()
 local d={sections={{title='Target',lines={Target(' (Echo Wishlist build)',2,2,0,0)}},{title='Pending (0)',lines={}},
  {title='Extra copies compared with the plan',lines={}},Notes()}}
 local snap=Render(d,true)
 local pending=Body(Details(d.sections),'Pending (0)')
 local none=true
 for _,name in ipairs(FAMILIES) do if Occurrences(name)~=0 then none=false end end
 record('CONTROL','ZERO-NOTHING-INVENTED',pending~=nil and #MissingRows()==0 and none and not Has('Family progress is unknown'),
  'Pending (0) keeps its heading, no Missing row or family is invented, and the summary is not unknown')
 Unchanged('ZERO',snap)
end)

-- Summaries the page does not validate keep every raw Pending line.
for _,case in ipairs(UNKNOWN) do
 stage('unknown-'..case.id,function()
  local d={sections=case.sections}
  local snap=Render(d,true)
  local details=Details(d.sections)
  local unknown=Has('Family progress is unknown') or Has('Build Progress is unavailable')
  record('CONTROL','UNKNOWN-'..case.id..'-NOT-VALIDATED',#MissingRows()==0 and unknown~=nil,
   case.why..': no Missing row and the summary says so: '..tostring(unknown))
  local kept,total,missing=0,0,{}
  local nth=0
  for _,sec in ipairs(d.sections) do
   if tostring(sec.title):sub(1,7)=='Pending' then
    nth=nth+1
    local body=Body(details,sec.title,nth)
    ObserveBody('unknown-'..case.id..' '..sec.title..' #'..nth,body)
    for _,entry in ipairs(sec.lines) do
     total=total+1
     if Contains(body,tostring(entry))==1 then kept=kept+1 else missing[#missing+1]=tostring(entry) end
    end
   end
  end
  record('CONTROL','UNKNOWN-'..case.id..'-RAW-PENDING-KEPT',total>0 and kept==total,
   'every raw Pending entry stays under its heading: '..kept..'/'..total..' missing ['..table.concat(missing,', ')..']')
  Unchanged('UNKNOWN-'..case.id,snap)
 end)
end

-- The same open page when the data changes between refreshes.
stage('valid-to-unknown',function()
 Render(Valid(),true)
 local d={sections=UNKNOWN[1].sections}
 local snap=Render(d,true)
 local body=Body(Details(d.sections),'Pending (3)')
 record('CONTROL','VALID-TO-UNKNOWN-RAW-BACK',Contains(body,'Arcane Echo')==1 and Contains(body,'Fire Echo')==1
  and Contains(body,'Frost Echo')==1 and #MissingRows()==0,'after the summary stops validating, the raw list is shown again')
 Unchanged('VALID-TO-UNKNOWN',snap)
end)
stage('unknown-to-valid',function()
 Render({sections=UNKNOWN[1].sections},true)
 local d=Valid()
 local snap=Render(d,true)
 local pending=Body(Details(d.sections),'Pending (4)')
 record('BEHAVIOR','DEDUP-UNKNOWN-TO-VALID',RawFamilyLines(pending)==0 and #MissingRows()==4,
  'once the summary validates, its list is not drawn twice: '..RawFamilyLines(pending))
 Unchanged('UNKNOWN-TO-VALID',snap)
end)

-- Rendering, folding and refreshing change no saved data, plan, selection or
-- native fact and send nothing.
stage('no-side-effects',function()
 local now={store=Serialize(Nexus.Store.State()),actions=#H.actions,sent=#H.sent,
  active=tostring(A.Slots() and A.Slots().activeSlot)}
 record('DATA','NO-SIDE-EFFECTS',now.store==before.store and now.actions==before.actions and now.sent==before.sent
  and now.active==before.active,'saved data, actions, messages and the native active slot are unchanged')
 observe('provider-calls',calls)
end)

local missed,byGroup,summary={},{},{}
for _,r in ipairs(results) do
 local g=byGroup[r.group] or {ok=0,miss=0};byGroup[r.group]=g
 if r.ok then g.ok=g.ok+1 else g.miss=g.miss+1;missed[#missed+1]=r.group..':'..r.id end
end
for _,name in ipairs({'BEHAVIOR','CONTROL','DATA','STAGE'}) do
 local g=byGroup[name]
 if g then summary[#summary+1]=name..' ok='..g.ok..' miss='..g.miss end
end
print('SUMMARY '..table.concat(summary,'; '))
if #missed>0 then
 error('FAIL journal_pending_summary_dedup: '..#missed..' expectation(s) not met: '..table.concat(missed,', '),0)
end
print('PASS journal_pending_summary_dedup: a validated Pending list is shown once; unknown summaries, other sections, '
 ..'tome requests and provider data are kept; checks='..#results)
