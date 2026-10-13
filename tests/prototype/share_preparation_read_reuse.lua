-- Operation-local status reuse only; real pending Share/catalog, synthetic APIs.
local S=dofile('tests/prototype/share_test_support.lua')
local failures,checks={},0
local function check(value,message)
 checks=checks+1;if not value then failures[#failures+1]=message end
end
local function pending(nilBinding)
 local H,C=S.Boot()
 if nilBinding then
  local real=C.ManualPreparationStatus
  C.ManualPreparationStatus=function(...)
   local status,identity=real(...)
   local copy={};for k,v in pairs(status)do copy[k]=v end
   copy.binding=nil;return copy,identity
  end
 end
 S.Incoming(H,C);local outcome=S.Post()
 assert(outcome.localStage=='waiting-catalog','actual retained Share fixture')
 return H,C,outcome
end
for _,nilBinding in ipairs({false,true})do
 local H,C,outcome=pending(nilBinding)
 local real,reads=C.ManualPreparationStatus,0
 C.ManualPreparationStatus=function(...)reads=reads+1;return real(...)end
 local retained,submitted=Nexus.CommunityBuilds.PumpPendingShare()
 C.ManualPreparationStatus=real
 check(reads==1,'one status read per pending turn, nil binding='..tostring(nilBinding)..': '..reads)
 check(retained and not submitted,'pending turn remains retained without submission')
 check(not H.putCalls[outcome.id] and #H.shareCalls==0,'pending turn writes and broadcasts nothing')
 check(NexusDB.settings.autoPick==false,'Automation remains OFF')
end
do
 local H,C,outcome=pending(false)
 local real,reads=C.ManualPreparationStatus,0
 C.ManualPreparationStatus=function(...)reads=reads+1;return real(...)end
 NexusDB=S.T.Profile(0,0)
 local retained,submitted=Nexus.CommunityBuilds.PumpPendingShare()
 C.ManualPreparationStatus=real
 check(reads==0,'changed database is refused before status query')
 check(not retained and not submitted,'changed database cannot retain or submit the old intent')
 check(not H.putCalls[outcome.id] and #H.shareCalls==0,'changed database writes and broadcasts nothing')
end
do
 local H,C,outcome=pending(false)
 local real=C.ManualPreparationStatus
 C.ManualPreparationStatus=function(...)
  local status,identity=real(...)
  local copy={};for k,v in pairs(status)do copy[k]=v end
  copy.binding='replacement-binding';copy.ready=true
  return copy,identity
 end
 local retained,submitted=Nexus.CommunityBuilds.PumpPendingShare()
 C.ManualPreparationStatus=real
 check(not retained and not submitted,'different binding refuses even a ready status')
 check(not H.putCalls[outcome.id] and #H.shareCalls==0,'different binding writes and broadcasts nothing')
end
for _,message in ipairs(failures)do print('FAIL '..message)end
assert(#failures==0,table.concat(failures,'; '))
print('PASS share_preparation_read_reuse checks='..checks..'; synthetic pending turns, no native FPS claim')
