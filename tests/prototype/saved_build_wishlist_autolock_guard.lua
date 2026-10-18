-- AutoLock must not treat a native Wishlist row as owned Echoes (review 03 B1).
--
-- Promoted from outputs/03-review/proposed_autolock_native_wishlist_gate.lua
-- (sha256 5d954fb3...). The world, the P, N0 and X steps and their check ids
-- and wording are unchanged. Recorded results of that proposal, unchanged:
-- the first selection-fix cut sent one replacement unlock at native Wishlist
-- 101 (X MISS, checks/07), while the original baseline sent none (X OK,
-- checks/08). N2, X2 and P2 are added.
--
-- While a native Wishlist (101, above the declared Saved Builds) is active and
-- Nexus keeps Saved Build 1 selected, the kept plan reaches TryAutoLock as a
-- 'loadout-association'. The native active row is then a Wishlist row: it
-- lists desired Echoes, not owned ones. It must give neither ownership (no
-- LockPerk on desired-only evidence) nor a destructive unlock context (no
-- UnlockPerk). The same automation against a populated Saved Build that is
-- natively active stays as designed (P unlocks, P2 locks).
--
-- P  positive control: Saved Build 1 active and holding T; capacity 1 full,
--    T replaces O. Expected UNLOCK of O. A MISS makes the run inconclusive.
-- N0 negative control: Saved Build 1 active, T neither saved nor granted.
--    Expected no unlock.
-- X  guard: same world as N0, then native active -> Wishlist 101 (holds T).
--    Expected no unlock, because T is not owned.
-- N2 negative control: capacity 2 (one free), T a target with no replacement
--    pairing, Saved Build 1 active without T, T not granted. Expected no lock.
-- X2 guard: same world as N2, then native active -> Wishlist 101 (holds T).
--    Expected no LockPerk(T) and no unlock.
-- P2 positive control: the N2 world, but Saved Build 1 holds T. Expected
--    LockPerk(T) and no unlock. A MISS makes X2 inconclusive.
--
-- Synthetic harness services only: no SavedVariables, no game, no disk writes.
local results={}
local function record(id,ok,msg)
 results[#results+1]={id=id,ok=ok==true}
 print((ok==true and 'OK   ' or 'MISS ')..id..': '..tostring(msg))
end
local function stage(name,fn)
 local ok,err=pcall(fn)
 if not ok then record('STAGE:'..name,false,'did not complete: '..tostring(err)) end
end

-- Harness catalog qualities: 200000+i has quality i%4.
local KEEP,T,O=200001,200050,200060
local H,A
local function Count(kind)
 local n=0
 for _,a in ipairs(H.actions) do if a[1]==kind then n=n+1 end end
 return n
end
local function Step(seconds) Nexus.RequestRecompute();H.Advance(seconds or 1.5) end
local function Selected()
 if not A.SelectedSavedBuild then return 'n/a' end
 local s,k=A.SelectedSavedBuild()
 return tostring(s)..'/'..tostring(k)
end
local function Observe(tag)
 local slots=A.Slots()
 print('OBSERVE '..tag..': native active='..tostring(slots and slots.activeSlot)..' selected='..Selected()
  ..' wishlist='..tostring(A.Wishlist() and A.Wishlist().source)..' note='..tostring(A.WishlistNote()))
end

-- `o.capacity` (default 1) is the permanent-Echo capacity; `o.target` (default
-- O) is T's lock-target value: O pairs T to replace O, true is a plain target.
local function Boot(savedHoldsT,o)
 o=o or {}
 local capacity,targetValue=o.capacity or 1,o.target==nil and O or o.target
 Nexus=nil;SlashCmdList=nil;NexusDB=nil;WishlistRealizerDB=nil
 H=dofile('tests/prototype/harness.lua');H.pendingRolls=40;H.playerLevel=30
 H.locked={{spellId=O,stack=1}}                 -- one record
 local saved={{spellId=KEEP,quality=1,stacks=1}}
 if savedHoldsT then saved[#saved+1]={spellId=T,quality=2,stacks=1} end
 H.perks.serverBuildSlots={
  [1]={name='Synthetic Saved Build A',verified=true,echoes=saved},
  [101]={name='Synthetic Plan D',verified=false,echoes={
   {spellId=KEEP,quality=1,stacks=1},{spellId=T,quality=2,stacks=1}}},
 }
 H.perks.serverActiveSlot=1
 H.Boot()
 for _=1,2000 do
  local status=Nexus.StartupStatus and Nexus.StartupStatus()
  if not status or status.state~='pending' then break end
  H.Advance(.05,.05)
 end
 A=Nexus.GameAdapter
 ProjectEbonhold.PerkService.GetMaximumPermanentEchoes=function() return capacity end
 H.Notify();A.Poll();H.Advance(1)
 local ok,why=A.SetLoadoutWishlist(1,101,nil)
 assert(ok==true,'SETUP: plan D (mirror 101) is assigned to Saved Build 1: '..tostring(why))
 local w=A.Wishlist()
 assert(w and w.source=='loadout-association','SETUP: Saved Build 1 resolves plan D: '
  ..tostring(w and w.source)..' '..tostring(A.WishlistNote()))
 local K=A.WishlistKey(w.entries)
 Nexus.Store.Settings().autoLockEchoes=true
 assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(state)
  state.lockDesignTargetsBySlot=state.lockDesignTargetsBySlot or {}
  state.lockDesignTargetsBySlot[K]={[T]=targetValue}
 end),'SETUP: the locked-target bucket is written through the store owner')
 SlashCmdList.NEXUS('reroll off');SlashCmdList.NEXUS('freeze off');SlashCmdList.NEXUS('banish off')
 H.Notify();H.Advance(1)
 SlashCmdList.NEXUS('auto');H.Advance(2)
end

local function NativeWishlist()
 H.perks.serverActiveSlot=101
 H.Notify();A.Poll();H.Advance(1)
 Step();Step(3);Step(3)
end

stage('P-positive-control',function()
 Boot(true)
 Step();Step(3)
 record('P-UNLOCK-REACHED',Count('unlock')>=1,
  'Saved Build 1 active and holding T: the designed replacement unlock is reached (unlocks='
  ..Count('unlock')..'); a MISS here makes this run inconclusive')
end)

stage('N0-X',function()
 Boot(false)
 Step();Step(3)
 record('N0-NO-UNLOCK-IN-RANGE',Count('unlock')==0,
  'Saved Build 1 active, T not owned: no unlock (unlocks='..Count('unlock')..')')
 local before=Count('unlock')
 NativeWishlist()
 Observe('X')
 record('X-NO-UNLOCK-AT-NATIVE-WISHLIST',Count('unlock')==before,
  'native Wishlist 101 active (desired Echoes, not owned): no destructive unlock; unlocks sent='
  ..(Count('unlock')-before))
end)

stage('N2-X2',function()
 Boot(false,{capacity=2,target=true})
 Step();Step(3)
 record('N2-NO-LOCK-IN-RANGE',Count('lock')==0 and Count('unlock')==0,
  'capacity 2, Saved Build 1 active, T not owned: no lock and no unlock (locks='
  ..Count('lock')..' unlocks='..Count('unlock')..')')
 local locks,unlocks=Count('lock'),Count('unlock')
 NativeWishlist()
 Observe('X2')
 record('X2-NO-LOCK-AT-NATIVE-WISHLIST',Count('lock')==locks,
  'native Wishlist 101 active, a free lock slot, T only desired there: no LockPerk(T); locks sent='
  ..(Count('lock')-locks))
 record('X2-NO-UNLOCK-AT-NATIVE-WISHLIST',Count('unlock')==unlocks,
  'and no unlock; unlocks sent='..(Count('unlock')-unlocks))
end)

stage('P2-positive-control',function()
 Boot(true,{capacity=2,target=true})
 Step();Step(3)
 record('P2-LOCK-REACHED',Count('lock')>=1 and Count('unlock')==0,
  'capacity 2, Saved Build 1 active and holding T: the additive lock is reached (locks='
  ..Count('lock')..' unlocks='..Count('unlock')..'); a MISS here makes X2 inconclusive')
end)

local missed={}
for _,r in ipairs(results) do if not r.ok then missed[#missed+1]=r.id end end
print('SUMMARY ok='..(#results-#missed)..' miss='..#missed)
if #missed>0 then
 error('FAIL saved_build_wishlist_autolock_guard: '..table.concat(missed,', '),0)
end
print('PASS saved_build_wishlist_autolock_guard: a native Wishlist row is neither ownership nor an unlock context; '
 ..'Saved Build automation unchanged; checks='..#results)
