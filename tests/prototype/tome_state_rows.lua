-- Real TOC and Journal renderer; synthetic read-only section data. These
-- checks exercise the player-facing frame tree, not a renderer helper.
local H=dofile('tests/prototype/harness.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local methods=G.RegionMethods()
function methods:SetVertexColor(...)self.vertexColor={...}end
function methods:SetTextColor(...)self.textColor={...}end
function methods:SetJustifyH(v)self.justifyH=v end
function methods:SetAlpha(v)self.alpha=v end
function methods:SetWordWrap(v)self.wordWrap=v end
G.UseFont(G.MODELS.default)
H.Boot()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local tip={}
GameTooltip.SetOwner=function()tip={}end
GameTooltip.AddLine=function(_,text)tip[#tip+1]=tostring(text)end
local function hover(r)
 r.scripts.OnEnter(r);local text=table.concat(tip,'\n');r.scripts.OnLeave(r);return text
end
local journal=CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
journal:SetSize(570,450)
CreateFrame('ScrollFrame','ProjectEbonholdEchoJournalScroll',journal)
CreateFrame('Button','ProjectEbonholdEchoJournalTab1',journal)
local calls,data=0
check(Nexus.JournalTab.TryInstall(function()calls=calls+1;return data end),'real Journal tab installs')
local scroll=NexusJournalScroll;scroll:SetSize(520,360)
local page=assert(scroll.scrollChild)
local QUESTION='Interface\\Icons\\INV_Misc_QuestionMark'
local function rows()
 local out={}
 for _,f in ipairs(H.frames)do
  if f.parent==page and f.label and f.status and f:IsVisible()then out[#out+1]=f end
 end
 return out
end
local function row(name,status)
 for _,r in ipairs(rows())do
  if r.label:GetText()==name and (not status or r.status:GetText()==status)then return r end
 end
end
local function button(text)
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f:GetText()==text then return f end end
end
local function words()
 local out={}
 for _,r in ipairs(page.regions)do if r:IsShown()then out[#out+1]=r:GetText()or''end end
 for _,r in ipairs(rows())do out[#out+1]=r.label:GetText();out[#out+1]=r.status:GetText()end
 return G.Visible(table.concat(out,'\n'))
end
local function tome(name,id,state,extra)
 local r={name=name,leverId=id,observed=state,known=true,status=state=='disabled' and 'Disabled' or 'Enabled',
  icon='Interface\\Icons\\Tome_'..id,iconSource='tome spell',echoNames={name..' Echo'}}
 for k,v in pairs(extra or {})do r[k]=v end
 return r
end
local disabled=tome('Tome of the known disabled Echo',880001,'disabled',{plan='plan: keep enabled'})
local pending=tome('Tome of the pending enable',880002,'disabled',{pending='enable'})
local enabled=tome('Tome of the enabled Echo',880003,'enabled')
local mixed=tome('Tome of the mixed Echo',880004,'mixed',{status='Mixed',reason='members disagree'})
local unknown=tome('Tome of the unknown Echo',880005,'unknown',{known=false,status='Unknown',reason='read unavailable',icon=false})
local undiscovered=tome('Tome of the undiscovered Echo',880006,'unknown',{known=false,status='Undiscovered',reason='undiscovered'})
local pendingDisable=tome('Tome of the pending disable',880007,'enabled',{pending='disable'})
local pendingUnknown=tome('Tome of the unknown request',880008,'unknown',{known=false,status='Unknown',pending='unknown'})
data={sections={
 {title='Target',lines={'No wishlist set'}},
 {title='Tome state coverage',lines={'Known client catalog only; whole game coverage is not verified.',
  'Server freshness is unverified; pending requests await confirmation.'}},
 {title='Disabled tomes (client mirror)',lines={'DENSE FALLBACK MUST NOT DUPLICATE ROWS'},tomeRows={disabled,pending}},
 {title='Enabled tomes (client mirror)',lines={'DENSE ENABLED FALLBACK'},tomeRows={enabled}},
 {title='Tome requests awaiting confirmation',lines={'DENSE PENDING FALLBACK'},tomeRows={pending,pendingDisable,pendingUnknown}},
 {title='Unknown or mixed tome state',lines={'DENSE UNKNOWN FALLBACK'},tomeRows={mixed,unknown,undiscovered}},
}}
NexusJournalTab:Click()
check(#rows()==0,'Tome details stay folded until requested')
assert(button('Show details')):Click()
check(row(disabled.name)~=nil,'disabled tome has a named icon row, including outside a disable plan')
check(#rows()==9,'all structured inventory, pending and unknown rows are shown')
check(row(disabled.name).icon:GetTexture()==disabled.icon,'the provided actual tome texture is used')
check(row(unknown.name).icon:GetTexture()==QUESTION,'an unavailable icon uses a neutral tile')
check(row(enabled.name).status:GetText()=='Enabled','observed enabled is explicit text')
check(row(mixed.name).status:GetText()=='Mixed' and row(unknown.name).status:GetText()=='Unknown',
 'mixed and unavailable observations stay distinct')
check(row(undiscovered.name).status:GetText()=='Undiscovered','undiscovered is not shown as enabled')
check(row(pending.name,'Enable pending') and row(pendingDisable.name,'Disable pending')
 and row(pendingUnknown.name,'Request pending'),'pending directions have short distinct badges')
local text=words()
check(not text:find('DENSE ',1,true),'structured rows replace dense fallback text')
check(text:find('whole game coverage is not verified',1,true) and text:find('freshness is unverified',1,true),
 'coverage and freshness notes remain readable')
check(not text:find('880001',1,true) and not text:find('(done)',1,true),'IDs stay out of visible labels and pending is never done')
local detail=hover(row(pending.name))
check(detail:find('880002',1,true) and detail:find('Disabled',1,true) and detail:find('awaiting confirmation',1,true),
 'pending tooltip carries ID, current observation and confirmation limit')
check(hover(row(disabled.name)):find('plan: keep enabled',1,true),'tooltip retains independent plan context')
check(hover(row(unknown.name)):find('read unavailable',1,true),'unknown tooltip explains the observation gap')
check(hover(row(mixed.name)):find('members disagree',1,true),'mixed tooltip retains the reason')
local request=hover(row(pendingDisable.name,'Disable pending'))
check(request:find('Disable requested; awaiting confirmation',1,true)
 and request:find('Last observed in the client mirror: Enabled',1,true),'a request row keeps its last observation apart from the request')
local r=row(disabled.name)
check(r.status.justifyH=='RIGHT' and r.label.justifyH=='LEFT','names and status badges use consistent alignment')
check(r.label.wordWrap==false and r.status.wordWrap==false,'long labels do not spill into the next row')
local rr,lr,sr=G.Rect(r,page),G.Rect(r.label,page),G.Rect(r.status,page)
check(G.Inside(lr,rr) and G.Inside(sr,rr) and G.Apart(lr,sr),'name and badge geometry stays inside separate columns')
local nextRow=row(pending.name)
check(r.background and nextRow.background and r.background.vertexColor[4]~=nextRow.background.vertexColor[4],
 'alternating subtle row backgrounds separate neighbours')
check(r.separator and r.separator:GetHeight()==1,'rows have a subtle divider')
local function same(a,b)return a and b and a[1]==b[1]and a[2]==b[2]and a[3]==b[3]end
for _,choice in ipairs({{'vista','amethyst'},{'slate','graphite'},{'vista','ember'}})do
 Nexus.Theme.SetStyle(choice[1]);Nexus.Theme.SetPalette(choice[2]);Nexus.Theme.Reapply()
 check(same(r.label.textColor,Nexus.Theme.STYLES[choice[1]].text),'row name follows readable '..choice[1]..' text')
 check(same(r.status.textColor,Nexus.Theme.PALETTES[choice[2]].accent),'badge follows selected '..choice[2]..' palette')
end
-- A complete large inventory remains in the existing scroll child. No row
-- count cap, per-row catalog/service lookup or refresh timer is needed.
local many={}
for i=1,180 do many[i]=tome(('Tome %03d with a long readable Echo name'):format(i),890000+i,'disabled')end
data.sections={data.sections[1],{title='Disabled tomes (client mirror)',lines={'LARGE FALLBACK'},tomeRows=many}}
local catalogCalls=0;local catalog=Nexus.GameAdapter.Catalog
Nexus.GameAdapter.Catalog=function()catalogCalls=catalogCalls+1;error('renderer must use supplied row metadata')end
local actions,sent=#H.actions,#H.sent
Nexus.JournalTab.Refresh()
check(#rows()==180 and row(many[180].name),'large inventories show every known supplied tome')
check(catalogCalls==0,'structured rows perform no catalog preparation or per-row resolution')
check(page:GetHeight()>scroll:GetHeight() and scroll:GetVerticalScrollRange()>0,'large list extends the existing scroll range')
local last=row(many[180].name);local lastRect=G.Rect(last,page)
check(lastRect[4]<=page:GetHeight(),'the last row fits in the scroll child')
scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
local scrolled=G.Rect(last,scroll)
check(scrolled[4]<=scroll:GetHeight() and scrolled[4]>0,'last row can be reached through the existing scrollbar')
check(hover(last):find(many[180].name,1,true),'a long row name is available in full on hover')
local frames=#H.frames
Nexus.JournalTab.Refresh()
check(#H.frames==frames,'refresh reuses all row frames')
check(catalogCalls==0,'a repeated refresh still reads no catalog')
check(#H.actions==actions and #H.sent==sent,'render, hover, theme and scroll interactions send no gameplay/network mutation')
-- Idle time runs the real runtime, whose own reads use its catalog: only the
-- renderer is trapped. Mutations are counted again after the idle second.
Nexus.GameAdapter.Catalog=catalog
local observedCalls=calls;H.Advance(1,.05)
check(calls==observedCalls,'tome rows add no background refresh scheduler')
actions,sent=#H.actions,#H.sent
-- A shrinking section and folded details hide unused pooled rows, including
-- stale tooltips and statuses from a previous pending request.
data.sections[2].tomeRows={enabled};Nexus.JournalTab.Refresh()
check(#rows()==1 and row(enabled.name).status:GetText()=='Enabled','pool reuse clears prior pending badges')
check(not hover(row(enabled.name)):find('880002',1,true),'pool reuse clears the prior tooltip identity')
-- An empty or unreadable structured list keeps its section's text lines.
data.sections[3]={title='Enabled tomes (client mirror)',lines={'None observed in this client catalog.'},tomeRows={}}
data.sections[4]={title='Unknown or mixed tome state',lines={'TEXT FALLBACK KEPT'},tomeRows={{leverId=880009}}}
Nexus.JournalTab.Refresh();text=words()
check(#rows()==1 and text:find('None observed in this client catalog.',1,true)
 and text:find('TEXT FALLBACK KEPT',1,true),'empty or unreadable structured rows fall back to the complete text lines')
assert(button('Hide details')):Click();check(#rows()==0,'folded details hide the entire tome row pool')
assert(button('Show details')):Click();check(#rows()==1,'reopening reuses only active tome rows')
NexusJournalTab:Click();observedCalls=calls;Nexus.JournalTab.Refresh()
check(#rows()==0 and calls==observedCalls,'inactive tab neither renders nor refreshes rows')
check(#H.actions==actions and #H.sent==sent,'pool, fallback, fold and tab interactions send no gameplay/network mutation')
print('PASS tome_state_rows: real TOC Journal icon rows, pending badges, tooltip IDs, theme, complete scroll list and pooled lifecycle checks='..checks)
