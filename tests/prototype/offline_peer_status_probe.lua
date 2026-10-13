-- Explicit diagnostic whispers respect existing offline guards. The slash
-- parser lowercases targets; full-name comparison must preserve realm scope.
local F=dofile('tests/prototype/offline_peer_dps_support.lua')
local checks,failed=0,{}
local function check(value,message)
 checks=checks+1;print((value and 'PASS ' or 'FAIL ')..message)
 if not value then failed[#failed+1]=message end
end
local function Direct(f,target,allowed,label)
 local cursor=#f.H.sent
 local callOk,sent,why=f.S.SendStatusTo(target)
 if allowed then
  local packet=f.H.sent[#f.H.sent]
  check(callOk==true and sent==true and #f.H.sent==cursor+1,label..': allowed once')
  check(packet.kind=='WHISPER' and packet.target==target,label..': intended chat whisper target')
 else
  check(#f.H.sent==cursor,label..': no wire submission')
  check(callOk==true and sent==false and why=='peer offline',label..': truthful blocked-peer result')
 end
end
local function Command(f,target,allowed,label)
 local cursor,chat=#f.H.sent,#f.H.chat
 SlashCmdList.NEXUS('probe '..target)
 check(#f.H.sent==cursor+(allowed and 1 or 0),label..': actual slash output')
 if not allowed then
  local reason=false
  for i=chat+1,#f.H.chat do if f.H.chat[i]:find('peer offline',1,true)then reason=true end end
  check(reason,label..': actual command reports refusal')
 end
end

for _,mode in ipairs({'automatic','manual'})do
 local f=F.Boot(false);f.Negotiate('Blocked-RealmA');f.Block('Blocked-RealmA')
 NexusDB.settingsVersion=5;NexusDB.settings.syncMode=mode
 f.W.Housekeep(true)
 Direct(f,'Blocked-RealmA',false,mode..' exact target')
 Direct(f,'blocked-realma',false,mode..' full-name ASCII case')
 Command(f,'Blocked-RealmA',false,mode..' mixed-case slash target')
 Direct(f,'Blocked-RealmB',true,mode..' different qualified realm')
 Direct(f,'Blocked',true,mode..' bare name is a separate scope')
 Command(f,'OtherPeer-RealmA',true,mode..' unrelated slash target')
 check(f.W.IsPeerBlocked('Blocked-RealmA'),mode..': probe cannot clear cooldown')
 f.H.now=f.H.now+60;f.W.Housekeep(true)
 Direct(f,'blocked-realma',false,mode..' deadline without new observation')
 local cursor=#f.H.sent
 for _=1,30 do f.Pump()end
 check(#f.H.sent==cursor,mode..': no deferred status retry')
 check(#f.H.actions==0,mode..': no gameplay action')
end

-- Sync-channel membership is separate from a normal diagnostic whisper.
-- Keep blocked existing peers suppressed, but allow unrelated/online probes.
for _,mode in ipairs({'automatic','manual'})do
 local f=F.Boot(false);f.Negotiate('Blocked-RealmA');f.Block('Blocked-RealmA')
 f.Negotiate('Online-RealmA')
 NexusDB.settingsVersion=5;NexusDB.settings.syncMode=mode
 GetChannelList=function()return end
 GetChannelName=function()return 0 end
 f.W.Housekeep(true)
 assert(f.W.IsPeerBlocked('Unrelated'),'fixture: addon wire is disconnected')
 Direct(f,'Unrelated',true,mode..' disconnected unrelated target')
 Direct(f,'Online-RealmA',true,mode..' disconnected previously online target')
 Command(f,'OtherPeer-RealmA',true,mode..' disconnected unrelated slash target')
 Direct(f,'blocked-realma',false,mode..' disconnected known offline target')
 check(#f.H.actions==0,mode..' disconnected: no gameplay action')
end

do
 local f=F.Boot(false)
 NexusDB.settingsVersion=5;NexusDB.settings.syncMode='off'
 local cursor=#f.H.sent
 local accepted,why=f.S.SendStatusTo('OtherPeer')
 check(accepted==false and type(why)=='string' and why:find('Off',1,true),'Off: original mode refusal preserved')
 SlashCmdList.NEXUS('probe OtherPeer')
 check(#f.H.sent==cursor,'Off: direct and command remain silent')
end

do
 local f=F.Boot(false)
 Direct(f,'StatusOnly',true,'normal status-only whisper')
 local notice=string.format(ERR_CHAT_PLAYER_NOT_FOUND_S,'StatusOnly')
 check(not f.W.NoteOfflineNotice(notice) and not f.W.IsPeerBlocked('StatusOnly'),'normal chat whisper adds no addon attribution')
end

assert(#failed==0,table.concat(failed,'; '))
print('PASS offline_peer_status_probe checks='..checks)
