-- Same diagnostic assertions run against baseline and successor; no native proof.
local F=dofile(os.getenv('NEXUS_TOME_TEST_SUPPORT') or 'tests/prototype/tome_observation_support.lua')
local checks,failures=0,{}
local function expect(v,m)checks=checks+1;if not v then failures[#failures+1]=m;print('MISS '..m)end end
for _,mode in ipairs({'known','missing'})do
 local W=F.Boot(mode)
 for step,key in ipairs({'A','B','A'})do
  F.Pick(W,key)
  local selected=F.Facts(W)
  if selected then
   expect(selected.assignment.observed==true and selected.assignment.sequence>0,mode..' successful association serial observed '..step)
   expect(selected.arm.assignmentSequence~=selected.assignment.sequence,mode..' no completed ordinary StepArm yet for new association '..step)
  end
  W.H.Advance(12,.05)
  local raw=F.Vector(W)
  local wanted=key=='A' and {false,true} or {true,false}
  expect(F.Same(raw,wanted)==(mode=='known'),mode..' raw mirror verdict '..step)
  expect(mode~='missing' or #W.O.calls==0,mode..' missing discovery safely sends nothing')
  local facts=F.Facts(W)
  expect(type(facts)=='table',mode..' diagnostic facts exist '..step)
  if facts then
   expect(facts.armObserved==true and facts.arm.gate=='eligible',mode..' ordinary StepArm observed eligible '..step)
   expect(facts.arm.assignmentSequence==facts.assignment.sequence,mode..' completed ordinary StepArm carries current association serial '..step)
   expect(mode~='missing' or (facts.arm.noKnown>0 and facts.arm.knownKind=='nil'),mode..' missing getter fact distinct '..step)
   expect(mode~='known' or facts.accepted>0,mode..' admitted setter history distinct '..step)
  end
  local report=F.Report(W)
  expect(report:find('Auto: selected=yes effective=ready',1,true),mode..' Auto capture stays unchanged '..step)
  expect(report:find('Tome management at capture: permission=yes',1,true),mode..' permission capture stays unchanged '..step)
  expect(report:find('Tome observations:',1,true),mode..' report has diagnostic section '..step)
  expect(report:find('Tome arm: gate=eligible',1,true),mode..' report preserves actual visited gate '..step)
  if mode=='missing' then
   expect(report:find('known_kind=nil',1,true) and report:find('accepted=0',1,true),mode..' report distinguishes safe no-call '..step)
  else
   expect(report:find('outcome=mirror_match',1,true),mode..' report distinguishes observed mirror settlement '..step)
  end
 end
 expect(W.O.boots==1,mode..' original world retained')
end
print('SUMMARY tome_observation_workflow checks='..checks..' failures='..#failures)
assert(#failures==0,table.concat(failures,'\n'))
print('PASS tome_observation_workflow: report distinguishes synthetic known/missing without changing raw behavior')
