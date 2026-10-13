-- #26: the Community card shows ONE real Dummy + Lich King pair. A build
-- qualifies only when one character has both records on the same loadout,
-- and the numbers the card shows must be that character's numbers. Before
-- this fix the card showed the highest Dummy and the highest Lich King over
-- all characters, from two different people, and averaged them.
--
-- Alpha and Bravo run the SAME loadout. Alpha has the best Dummy record and
-- a low Lich King record; Bravo has the best Lich King record and a low Dummy
-- record. Their per-category maxima (60000 / 50000, average 55000) belong to
-- nobody. The best pair (highest single record, then identity) is Alpha's:
-- 60000 / 20000, average 40000.
--
-- Charlie runs that loadout too and holds the strongest records (90000 /
-- 80000), but the Dummy record was captured on one locked set and the Lich
-- King record on another (six copies each, spread over different Echoes):
-- they are not a pair, so the best pair stays Alpha's. Delta has the same
-- split alone on a second loadout, which therefore has no pair. Foxtrot
-- (55000 / 50000) has a higher average than Alpha and a lower best record.
-- The local character (PrototypeTester, 38000 / 39000) captured its pair on
-- the locked set it holds at start, and later holds another one.
--
-- Real TOC boot, catalog, DpsCapture eligibility, the real Community
-- projection and controller, and the real Leaderboard projection; synthetic
-- data.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local fx=L.New({players={
 {name='PrototypeTester',class='MAGE',isLocal=true,variant=30,ordinary=60,dps={lk=39000,dummy=38000}},
 {name='Alpha',class='MAGE',variant=7,dps={dummy=60000,lk=20000}},
 {name='Bravo',class='MAGE',variant=7,build='missing',dps={dummy=30000,lk=50000}},
 {name='Charlie',class='MAGE',variant=7,build='missing',dps={dummy=90000,lk=80000}},
 {name='Delta',class='MAGE',variant=11,dps={dummy=70000,lk=65000}},
 {name='Foxtrot',class='MAGE',variant=13,dps={dummy=55000,lk=50000}},
}})
local tester,alpha,bravo=fx.players[1],fx.players[2],fx.players[3]
local charlie,delta,foxtrot=fx.players[4],fx.players[5],fx.players[6]
-- Charlie's and Delta's Lich King records keep a second locked set: six
-- Echoes with one copy each, where their Dummy records (odd variant) hold two
-- copies of the first and none of the sixth. Score, owner, class and ordinary
-- evidence stay as the fixture wrote them; the locked content key is
-- recomputed with the product's LoadoutEvidence, as the fixture does.
local db=fx:Install(F.Database({version=2}))
local secondSet=L.DpsRows(L.LockedRows(8))
for _,p in ipairs({charlie,delta}) do
 local row=db.dpsCapture.characterBest.lk[p.owner]
 row.lockedEchoes=L.Copy(secondSet)
 row.lockedEvidenceKey=L.Evidence().Fingerprint(row.lockedEchoes,{forceLocked=true})
end
-- The native locked mirror in the exported SS18 shape (ProjectEbonhold
-- perks_service.lua 308-315): one record per locked Echo, keeping its own
-- stack, maxStack and quality. At start the local character holds the set
-- its records were captured with.
local function Native(h,rows)
 local out={}
 for i,r in ipairs(rows) do out[i]={spellId=r.spellId,stack=r.stacks,maxStack=h.db[r.spellId].maxStack,quality=r.quality} end
 return out
end
local H=F.Boot(db,function(h) h.playerLevel=60;h.locked=Native(h,tester.locked) end)
for _=1,400 do H.Advance(.05,.05) end
check(Nexus.StartupStatus().state=='ready','fixture: start-up completed: '..tostring(Nexus.StartupStatus().state))
check(alpha.fingerprint==bravo.fingerprint,'fixture: Alpha and Bravo run the same loadout')
check(alpha.lockedFingerprint==bravo.lockedFingerprint,'fixture: with the same locked set')
local D,CE,A=Nexus.DpsCapture,Nexus.CandidateEvidence,Nexus.GameAdapter
local function BoardRow(category,owner)
 for _,r in ipairs(D.GetDpsBoard(category)) do if r.ownerKey==owner then return r end end
end
check(charlie.fingerprint==alpha.fingerprint and delta.fingerprint~=alpha.fingerprint,
 'fixture: Charlie runs Alpha\'s loadout, Delta another one')
for _,p in ipairs({charlie,delta}) do
 local d,k=BoardRow('dummy',p.owner),BoardRow('lk',p.owner)
 check(d~=nil and k~=nil and d.dps==p.dps.dummy and k.dps==p.dps.lk,
  'fixture: '..p.name..'\'s Dummy and Lich King records are on the boards')
 check(d.fingerprint==p.fingerprint and k.fingerprint==p.fingerprint
  and d.lockedFingerprint==p.lockedFingerprint and k.lockedFingerprint==L.Fingerprint(secondSet)
  and L.Copies(d.lockedEchoes)==6 and L.Copies(k.lockedEchoes)==6,
  'fixture: '..p.name..'\'s records differ only in the locked set, six copies each: '
  ..tostring(d.lockedFingerprint)..' / '..tostring(k.lockedFingerprint))
 check(CE.DpsPairIdentity(d)~=nil and CE.DpsPairIdentity(k)~=nil,
  'fixture: each of '..p.name..'\'s records is a valid pair identity by itself')
end
-- The current locked authority (GameAdapter.LockedOwned over the native
-- mirror) holds exactly `rows`.
local function Holds(rows)
 local now=A.LockedOwned()
 if not (type(now)=='table' and now.synced==true and now.occupied==#rows) then return false end
 for _,r in ipairs(rows) do if now.bySpell[r.spellId]~=r.stacks then return false end end
 return true
end
check(Holds(tester.locked),'fixture: at start the local character holds the locked set its records were captured with')

-- 1. The qualification summary that every card and detail reader uses.
local q=D.GetCommunityQualification(alpha.fingerprint)
check(type(q)=='table','the loadout qualifies (Alpha and Bravo each have a real pair)')
check(q.dummy~=charlie.dps.dummy and q.lk~=charlie.dps.lk,
 'Charlie\'s records on two locked sets are not the pair shown: dummy='..tostring(q.dummy)..' lk='..tostring(q.lk))
check(q.dummy==60000 and q.lk==20000,
 'the summary shows one character\'s pair, not per-category maxima: dummy='..tostring(q.dummy)..' lk='..tostring(q.lk))
check(q.average==40000,'and that pair\'s average: '..tostring(q.average))
check(q.best==60000,'and that pair\'s best record: '..tostring(q.best))

-- 2. The Community card (the real projection row) shows the same numbers.
local P=Nexus.ViewProjections
local rows
local filters={currentClassOnly=false,qualifiedOnly=false,scope='all',sortMode='title',page=1}
for _=1,4000 do
 rows=P.RequestBuilds(filters)
 if rows then break end
 P.PumpBuilds();H.Advance(.05,.05)
end
check(rows~=nil,'fixture: the Community projection published')
local card
for _,b in ipairs(rows) do if b.id==alpha.buildId then card=b end end
check(card~=nil,'fixture: Alpha\'s build is listed')
local shown=card._nexusDps or {}
check(shown.dummy==60000 and shown.lk==20000,
 'the card shows Alpha\'s Dummy and Lich King records: dummy='..tostring(shown.dummy)..' lk='..tostring(shown.lk))
check(shown.average==40000,'and their average, not a mix of two characters: '..tostring(shown.average))
check(card._nexusQualified==true,'and the build still qualifies')

-- 3. The build detail reader agrees with the card. main publishes the
-- Community controller only as Nexus.CommunityInternals.Controller (nothing
-- assigns Nexus.CommunityController, so this section used to be skipped),
-- and DpsSummary lives on a controller instance. The detail panel's record
-- lines are a different reader (category bests with their holders,
-- CommunityProjection RecordText) and are not asserted here.
local Controller=Nexus.CommunityInternals and Nexus.CommunityInternals.Controller
check(type(Controller)=='table' and type(Controller.New)=='function',
 'fixture: the Community controller is published as Nexus.CommunityInternals.Controller')
local controller=Controller.New({})
check(type(controller)=='table' and type(controller.DpsSummary)=='function',
 'fixture: a real Community controller exposes DpsSummary')
local detail=controller.DpsSummary(card)
check(detail.dummy==60000 and detail.lk==20000,
 'the detail summary shows the same pair: dummy='..tostring(detail.dummy)..' lk='..tostring(detail.lk))
check(detail.average==shown.average and detail.best==shown.best,
 'and the card\'s average and best record: '..tostring(detail.average)..' / '..tostring(detail.best))

-- Every card of the real Community projection, all pages, in its order.
local function Cards(sortMode)
 local out,page,pages={},1,1
 repeat
  local f={currentClassOnly=false,qualifiedOnly=false,scope='all',sortMode=sortMode,page=page}
  local list,summary
  for _=1,4000 do
   list,summary=P.RequestBuilds(f)
   if list then break end
   P.PumpBuilds();H.Advance(.05,.05)
  end
  check(list~=nil,'fixture: the Community projection published ('..sortMode..')')
  for _,b in ipairs(list) do out[#out+1]=b end
  pages=summary.pageCount or 1
  page=page+1
 until page>pages
 return out
end
local function CardOf(list,id) for _,b in ipairs(list) do if b.id==id then return b end end end

-- 4. Records on two locked sets never pair (#26 fixture 3). Charlie's left
-- Alpha's pair in place (section 1). Delta's loadout has no other records,
-- so it has no pair and does not qualify, and its card shows no DPS instead
-- of numbers from two locked sets.
local paired={}
for _,pair in ipairs(CE.RealDpsPairs(D.GetDpsBoard('dummy'),D.GetDpsBoard('lk'))) do paired[pair.lk.ownerKey]=true end
check(paired[tester.owner] and paired[alpha.owner] and paired[bravo.owner] and paired[foxtrot.owner],
 'fixture: the characters with both records on one locked set each have their pair')
check(not paired[charlie.owner] and not paired[delta.owner],'Charlie and Delta have no pair')
check(D.GetCommunityQualification(delta.fingerprint)==nil,'Delta\'s loadout does not qualify')
local cards=Cards('title')
local deltaCard=CardOf(cards,delta.buildId)
check(deltaCard~=nil,'fixture: Delta\'s build is listed')
local dd=deltaCard._nexusDps or {}
check(deltaCard._nexusQualified==false and dd.count==0 and dd.best==0 and dd.average==0,
 'Delta\'s card does not qualify and shows no DPS: best='..tostring(dd.best)..' average='..tostring(dd.average))

-- 5. The card, the detail reader and the Leaderboard name the same pair
-- (#26 fixture 7). Both records ranks real pairs by their strongest single
-- record. For every card the detail reader gives the card's numbers, and the
-- top Both records row of the card's loadout is the card's pair; a card
-- without a pair has no such row.
local both=P.Leaderboard('combined',{search='',classFilter='ALL'})
check(type(both)=='table','fixture: the Leaderboard Both records projection published')
local owners={}
for i,r in ipairs(both) do owners[i]=tostring(r.ownerKey) end
check(table.concat(owners,' ')==table.concat({alpha.owner,foxtrot.owner,bravo.owner,tester.owner},' '),
 'Both records lists the four real pairs, strongest single record first: '..table.concat(owners,' '))
local function TopBoth(fingerprint)
 for _,r in ipairs(both) do if r.fingerprint==fingerprint then return r end end
end
local top=TopBoth(alpha.fingerprint)
check(top~=nil and top.ownerKey==alpha.owner,'the top Both records row of Alpha\'s loadout is Alpha\'s own: '..tostring(top and top.ownerKey))
for _,b in ipairs(cards) do
 local d=b._nexusDps or {}
 local reader=controller.DpsSummary(b)
 check(reader.dummy==d.dummy and reader.lk==d.lk and reader.average==d.average and reader.best==d.best,
  'the detail reader gives the card\'s numbers: '..tostring(b.title))
 local row=TopBoth(b.fingerprint)
 if d.count==2 then
  check(row~=nil and row.dummyDps==d.dummy and row.lkDps==d.lk and row.average==d.average and row.dps==d.best,
   'the top Both records row of the loadout is the card\'s pair: '..tostring(b.title))
 else
  check(row==nil,'a card without a pair has no Both records row: '..tostring(b.title))
 end
end

-- 6. Sorting by DPS follows the number the card headline shows (#26 fixture
-- 8). A card with a pair shows its best record as the headline and the
-- average only in the breakdown; a card without one shows "No DPS record"
-- (ui/CommunityRenderer.lua 3332-3351). Foxtrot has the higher average and
-- the lower headline, so ordering by the average would differ.
local function Headline(d) return d.count==2 and d.best or 0 end
local byDps=Cards('dps')
check(#byDps==#fx.buildOrder,'fixture: the projection lists the '..#fx.buildOrder..' fixture builds: '..#byDps)
local fc,ac=CardOf(byDps,foxtrot.buildId),CardOf(byDps,alpha.buildId)
check(fc~=nil and ac~=nil and fc._nexusDps.best==55000 and fc._nexusDps.average==52500
 and ac._nexusDps.best==60000 and ac._nexusDps.average==40000,
 'fixture: Foxtrot (best 55000, average 52500) and Alpha (best 60000, average 40000) are listed')
local order={}
for i,b in ipairs(byDps) do
 local d=b._nexusDps or {}
 check(d.count==2 or d.count==0,'fixture: each card has a pair or no DPS: '..tostring(b.title))
 if i>1 then check(Headline(byDps[i-1]._nexusDps)>=Headline(d),'no card follows one with a lower headline: '..tostring(b.title)) end
 order[i]=b.id
end
check(table.concat(order,' ')==table.concat({alpha.buildId,foxtrot.buildId,tester.buildId,delta.buildId},' '),
 'DPS order is Alpha 60000, Foxtrot 55000, PrototypeTester 39000, Delta (no pair): '..table.concat(order,' '))

-- 7. A later change of the CURRENT locked authority keeps the captured pair
-- (#26 fixture 6). The local character's records were captured on its six
-- locked copies; it now holds five, two of them on one record. As an SS18
-- push does, the native mirror is replaced by a new table and the journal is
-- notified. The mirror carries no generation or time (reference errata
-- EBH-E04), so nothing orders the two sets: the stored records keep the set
-- they were captured with, and so does every pair built from them.
check(type(NexusDB.authorityBundle)=='table' and type(rawget(NexusDB.authorityBundle,'dpsCapture'))=='table',
 'fixture: the DPS records are in the authority bundle')
-- Every stored record: category, owner, score, ordinary and locked evidence.
local function Stored()
 local out={}
 local store=rawget(NexusDB.authorityBundle,'dpsCapture').characterBest
 for _,category in ipairs({'dummy','lk'}) do
  for key,row in pairs(store[category] or {}) do
   local r=D.MaterializeRecord(row)
   out[#out+1]=table.concat({category,tostring(key),tostring(r.dps),tostring(r.fingerprint),
    L.Fingerprint(r.echoes),L.Fingerprint(r.lockedEchoes)},'|')
  end
 end
 table.sort(out)
 return table.concat(out,'\n'),#out
end
-- The real pairs rebuilt from fresh reads of the stored records.
local function PairList()
 local out={}
 for _,pair in ipairs(CE.RealDpsPairs(D.GetDpsBoard('dummy'),D.GetDpsBoard('lk'))) do
  out[#out+1]=tostring(pair.lk.ownerKey)..' '..tostring(pair.dummyDps)..'/'..tostring(pair.lkDps)
   ..' '..tostring(pair.dummy.lockedFingerprint)..' + '..tostring(pair.lk.lockedFingerprint)
 end
 return table.concat(out,'; ')
end
-- The local pair as each reader shows it: a fresh pairing, the qualification
-- summary and the card.
local function LocalPair()
 local pair
 for _,p in ipairs(CE.RealDpsPairs(D.GetDpsBoard('dummy'),D.GetDpsBoard('lk'))) do
  if p.lk.ownerKey==tester.owner then pair=p end
 end
 local s=D.GetCommunityQualification(tester.fingerprint) or {}
 local c=CardOf(Cards('title'),tester.buildId) or {}
 local d=c._nexusDps or {}
 local ok=pair~=nil and pair.dummyDps==38000 and pair.lkDps==39000 and pair.average==38500
  and pair.dummy.lockedFingerprint==tester.lockedFingerprint and pair.lk.lockedFingerprint==tester.lockedFingerprint
  and s.dummy==38000 and s.lk==39000 and s.average==38500
  and d.dummy==38000 and d.lk==39000 and d.average==38500 and c._nexusQualified==true
 return ok,'pair '..(pair and (pair.dummyDps..'/'..pair.lkDps..' on '..tostring(pair.dummy.lockedFingerprint)
  ..' + '..tostring(pair.lk.lockedFingerprint)) or 'none')..'; summary '..tostring(s.dummy)..'/'..tostring(s.lk)
  ..'; card '..tostring(d.dummy)..'/'..tostring(d.lk)..' qualified='..tostring(c._nexusQualified)
end
local ok,seen=LocalPair()
check(ok,'fixture: before the change every reader shows the local pair on its captured set: '..seen)
local storedBefore,storedCount=Stored()
check(storedCount==12,'fixture: twelve stored records: '..storedCount)
local pairsBefore=PairList()
local later=L.LockedRows(31,5)
H.locked=Native(H,later);H.Notify();A.Poll()
for _=1,200 do H.Advance(.05,.05) end
check(Holds(later) and L.Fingerprint(later)~=tester.lockedFingerprint,
 'fixture: the local character now holds another locked set: '..L.Fingerprint(later))
check(Stored()==storedBefore,'the stored records are unchanged: score, ordinary and locked evidence')
check(PairList()==pairsBefore,'the pairs rebuilt from them are unchanged: '..PairList())
ok,seen=LocalPair()
check(ok,'every reader still shows the local pair on its captured set: '..seen)

print('PASS community_card_dps_pair '..checks..' checks')
