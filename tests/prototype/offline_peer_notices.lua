-- Localized native notice matching and finite recovery use exact peer names.
local H=dofile('tests/prototype/harness.lua');H.Boot()
local W,C=Nexus.SyncWire,Nexus.ChatThrottleLib
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local removed={}
local function refill() C.bQueueing=false;C.avail=4000;C.LastAvailUpdate=H.now end
local function init() W.Init(function()return true end,{onPeerRemoved=function(name)removed[#removed+1]=name end});refill()end
local function negotiate(name)
 H.now=H.now+1.1;refill();W.ObservePeer(name);W.PumpHandshake()
 check(H.sent[#H.sent].target==name and H.sent[#H.sent].text=='HELLO1','actual current HELLO '..name)
 check(W.Receive(W.PREFIX,'ACK1','WHISPER',name),'actual current ACK '..name)
end
ERR_CHAT_PLAYER_NOT_FOUND_S="No player named '%s' is currently playing."
local function notice(name)return string.format(ERR_CHAT_PLAYER_NOT_FOUND_S,name)end
init();negotiate('Exact-Realm');negotiate('Online');refill()
check(W.SendPacket('X',{requester='Exact-Realm'},1),'actual directed data')
check(not W.NoteOfflineNotice(notice('Exact')),'ambiguous unqualified name fails closed')
check(not W.NoteOfflineNotice(notice('Other')),'unrelated human/addon target fails closed')
check(not W.NoteOfflineNotice('prefix '..notice('Exact-Realm')),'unanchored text fails closed')
H.now=H.now+4.01;check(not W.NoteOfflineNotice(notice('Exact-Realm')),'delayed notice fails closed')
refill();check(W.SendPacket('X',{requester='Exact-Realm'},1),'fresh actual directed attempt')
check(W.NoteOfflineNotice(notice('Exact-Realm')),'exact recent actual whisper is attributable')
check(not W.NoteOfflineNotice(notice('Exact-Realm')),'duplicate notice cannot extend cooldown')
check(W.IsPeerBlocked('Exact-Realm') and not W.IsPeerBlocked('Online'),'exact scoped cooldown')
local start=#H.sent;W.ObservePeer('Exact-Realm');W.PumpHandshake()
check(not W.SendPacket(string.rep('X',243),{requester='Exact-Realm'},1) and #H.sent==start,'offline cooldown suppresses addon and legacy fallback')
refill();local ok,route=W.SendPacket('X',{requester='Online'},1);check(ok and route=='addon','unrelated online route progresses')
local offlineAt=H.now
for i=1,200 do H.now=H.now+.001;W.ObservePeer('Online');W.ObservePeer('Churn'..i) end
check(W.Stats().peers<=128 and W.Stats().pendingHandshakes<=16,'bounded peer/pending churn')
check(W.IsPeerBlocked('Exact-Realm'),'active cooldown survives cap eviction churn')
H.now=offlineAt+60;refill();check(W.IsPeerBlocked('Exact-Realm'),'deadline alone cannot recreate work')
check(not W.Receive(W.PREFIX,'ACK1','WHISPER','Exact-Realm'),'old ACK cannot recover offline route')
-- Expire unrelated pending discovery before the recovery HELLO's real send.
W.Housekeep(true);W.ObservePeer('Exact-Realm');W.PumpHandshake()
check(H.sent[#H.sent].text=='HELLO1' and H.sent[#H.sent].target=='Exact-Realm','fresh accepted observation recovers after finite cooldown')
check(W.Receive(W.PREFIX,'ACK1','WHISPER','Exact-Realm'),'new current recovery ACK')
refill();ok,route=W.SendPacket('X',{requester='Exact-Realm'},1);check(ok and route=='addon','online recovery resumes')
init();negotiate('Localise');refill();W.SendPacket('X',{requester='Localise'},1)
ERR_CHAT_PLAYER_NOT_FOUND_S='[Joueur] "%s" absent (maintenant).'
check(W.NoteOfflineNotice(notice('Localise')),'localized template punctuation is literal')
init();negotiate('NoTemplate');ERR_CHAT_PLAYER_NOT_FOUND_S=nil
check(not W.NoteOfflineNotice("No player named 'NoTemplate' is currently playing."),'missing locale contract fails closed')
init();negotiate('BadTemplate');ERR_CHAT_PLAYER_NOT_FOUND_S='%s %s'
check(not W.NoteOfflineNotice('BadTemplate BadTemplate'),'ambiguous locale format fails closed')
init();negotiate('Expired');H.now=H.now+900;W.Housekeep(true)
check(removed[#removed]=='Expired' and W.Stats().peers==0,'peer TTL cleans owners and negotiation')
check(#H.actions==0,'no gameplay mutation')
print('PASS offline_peer_notices checks='..checks)
