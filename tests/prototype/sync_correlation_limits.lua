-- Exact bounded scalar diagnostic data; no payload/record retention or SV use.
local H=dofile('tests/prototype/harness.lua');H.Boot()
local D=Nexus.PeerDebug
local checks=0
local function check(ok,why) assert(ok,why);checks=checks+1 end
local id=string.rep('a',96)
local transfer=string.rep('b',160)
local requester='Valentiné-rogue-lite(live)'
check(D.Start()==true,'session started')
local before=#H.sent
D.Record('dps_commit',{requestId=id,requester=requester,transferId=transfer,
 dataKind='D',bucket=8,relay=false,outcome='accepted',payload='PRIVATE_PAYLOAD',
 record={dps=999},playerRecord={owner='PRIVATE'},unknown='PRIVATE',
 reason='safe|pipe\nnewline',bytes=math.huge,rows=0/0})
local event=D.Events()[2]
local f=event.fields
check(f.requestId==id and f.transferId==transfer and f.requester==requester,
 'wire-sized IDs and true U+00E9 identity remain exact')
check(f.dataKind=='D' and f.bucket==8 and f.relay==false,'typed correlation scalars retained')
check(f.payload==nil and f.record==nil and f.playerRecord==nil and f.unknown==nil,
 'payload/record/unknown fields never retained')
check(f.bytes==nil and f.rows==nil and f.reason=='safe pipe newline',
 'nonfinite values refused and ordinary outcome text sanitized')
f.requestId='mutated';event.fields.extra={}
check(D.Events()[2].fields.requestId==id and D.Events()[2].fields.extra==nil,
 'detached snapshots cannot mutate retained evidence')
local report=D.Report()
check(report:find('requestId='..id,1,true)
 and report:find('omitted=transferId',1,true)
 and not report:find('transferId=bbbb',1,true),
 'bounded report keeps complete request ID and explicitly omits long transfer context')
for line in report:gmatch('[^\n]+') do
 if line:find('dps_commit',1,true) then
  local formatted=line:match('dps_commit%s+(.*)')
  check(formatted and #formatted<=220,'per-event formatted field cap remains 220')
 end
end
D.Record('bad',{requestId=string.rep('x',97),transferId=string.rep('x',161),
 requester='bad|name',dataKind='payload',bucket=math.huge,relay='false',
 peer='Recipient',record={dps=1}})
local bad=D.Events()[3].fields
check(bad.requestId==nil and bad.transferId==nil and bad.requester==nil
 and bad.dataKind==nil and bad.bucket==nil and bad.relay==nil,
 'oversized/invalid correlation refused without collisions or type coercion')
D.Record('bad',{requestId='c1-|evil\n',transferId='invalid\255',bucket=1.5})
bad=D.Events()[4].fields
check(bad.requestId==nil and bad.transferId==nil and bad.bucket==nil,
 'unsafe correlation bytes and fractional bucket refused')
D.Record('owner_boundary',{requestId='c1-secret',requester=requester,
 transferId=transfer,dataKind='D',bucket=1,relay=true,directOwner=true})
local boundary=D.Events()[5].fields
check(boundary.directOwner==true and boundary.requestId==nil
 and boundary.requester==nil and boundary.transferId==nil,
 'owner-boundary event keeps identifier-free contract')
for i=1,200 do D.Record('bounded',{requestId='c1-'..i,bucket=1}) end
local stats=D.Stats();local events=D.Events()
check(stats.retained==160 and #events==160 and stats.dropped>=45,
 'finite 160-event ring replaces oldest entries')
check(events[1].fields.requestId=='c1-41' and events[160].fields.requestId=='c1-200',
 'ring order retained through wrap')
check(#D.Report()<160*800+16000,'finite report size')
D.Stop();check(D.Record('disabled',{requestId='c1-disabled'})==false,
 'stopped tracing refuses new collection')
H.now=H.now+901
check(#D.Events()==0 and D.Stats().enabled==false,'age clears ring and disables collection')
check(#H.sent==before and #H.actions==0,'diagnostics cause zero sends or gameplay actions')
print('PASS sync_correlation_limits checks='..checks)
