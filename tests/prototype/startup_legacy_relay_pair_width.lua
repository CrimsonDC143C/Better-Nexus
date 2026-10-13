-- Synthetic legacy 1.19.1 character relay pair. No tester SavedVariables.
-- The historical producer wrote st.relayPairs[tostring(wishlistKey)] =
-- {slotA=sourceSlot,slotB=targetSlot} after a verified inactive save.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0
local function check(ok,reason) assert(ok,reason); checks=checks+1 end

local parts={}
for i=1,69 do
    parts[#parts+1]=tostring(300000+i)..':'..(i==69 and '10' or '1')
end
local key=table.concat(parts,',')
check(#key==621,'synthetic legacy wishlist identity has observed width')

local function Boot(field,value,expect,entryKey,depth)
    entryKey=entryKey or key
    local db=F.Database({mutate=function(candidate)
        if depth=='settings' then
            candidate.settings[field]={[entryKey]=value}
        elseif depth=='nested' then
            candidate.chars[F.NAME].syntheticSibling={
                [field]={[entryKey]=value}}
        else
            candidate.chars[F.NAME][field]={[entryKey]=value}
        end
    end})
    local H=F.Boot(db)
    local status=Nexus.StartupStatus()
    if expect=='ready' then
        check(status.coreReady==true and status.state~='failed',
            'owned legacy relay pair starts: '..tostring(status.reason))
    else
        check(status.state=='failed' and status.reason=='SOURCE_KEY_WIDTH_EXCEEDED',
            'wrong shape or sibling remains refused')
    end
    check(#H.actions==0,'startup submits no game action')
    return H,status
end

Boot('relayPairs',{slotA=1,slotB=2},'ready')
local before=F.Serialize(NexusDB.chars[F.NAME].relayPairs)
local H=F.Reload()
check(Nexus.StartupStatus().coreReady==true,'reload is ready')
check(F.Serialize(NexusDB.chars[F.NAME].relayPairs)==before,
    'legacy pair remains byte-identical under canonical fixture serializer')
check(#H.actions==0,'reload submits no game action')

Boot('syntheticSibling',{slotA=1,slotB=2},'failed')
Boot('relayPairs',{slotA=1,slotB=2},'failed',key,'settings')
Boot('relayPairs',{slotA=1,slotB=2},'failed',key,'nested')
Boot('relayPairs','wrong value shape','failed')
Boot('relayPairs',{slotA=1,slotB=2,extra=true},'failed')
Boot('relayPairs',{slotA=0,slotB=2},'failed')
Boot('relayPairs',{slotA=1,slotB='2'},'failed')
Boot('relayPairs',{slotA=1,slotB=2},'ready',string.rep('w',2048))
local _,tooWide=Boot('relayPairs',{slotA=1,slotB=2},'failed',string.rep('w',2049))
local facts=assert(tooWide.failure and tooWide.failure.keyWidth)
check(facts.path=='character.relayPairs' and facts.depth==2
    and facts.keyBytes==2049 and facts.limit==2048
    and facts.exception=='legacy-relay',
    'oversized owned key reports sanitized path and bound')
check(not tostring(tooWide.reason):find('wwww',1,true),
    'refusal does not expose the synthetic key')

do
    local db=F.Database({mutate=function(candidate)
        candidate.chars[F.NAME].relayPairs={
            [string.rep('a',2048)]={slotA=1,slotB=2},
            [string.rep('b',2048)]={slotA=1,slotB=3},
            [string.rep('c',2048)]={slotA=2,slotB=3},
        }
    end})
    local H=F.Boot(db)
    check(Nexus.StartupStatus().coreReady==true,
        'multiple slice-wide legacy keys resume and complete')
    check(#H.actions==0,'resumable admission submits no actions')
end
print('PASS '..checks..' synthetic legacy relay-pair checks')
