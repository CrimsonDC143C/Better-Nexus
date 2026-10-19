-- Keyed deterministic uniforms. No shared global RNG or clock input.
-- FNV-style tuple hash followed by the Murmur3 32-bit finalizer. Multiplication
-- is split into 16-bit limbs so Lua 5.1 doubles and LuaJIT agree exactly.
local R={version='keyed-u32/v1'}
local ok,bitlib=pcall(require,'bit')
local function Xor(a,b)
    if ok then return bitlib.bxor(a,b)%4294967296 end
    local value,power=0,1
    for _=1,32 do
        if a%2~=b%2 then value=value+power end
        a=math.floor(a/2);b=math.floor(b/2);power=power*2
    end
    return value
end
local function Mul(a,b)
    local al,bl=a%65536,b%65536
    return (al*bl+((math.floor(a/65536)*bl+math.floor(b/65536)*al)%65536)*65536)%4294967296
end
function R.Uniform(seed,stream,ordinal,slot)
    local key=table.concat({seed,stream,ordinal,slot},':')
    local h=2166136261
    for i=1,#key do h=Mul(Xor(h,key:byte(i)),16777619) end
    h=Mul(Xor(h,math.floor(h/65536)),2246822507)
    h=Mul(Xor(h,math.floor(h/8192)),3266489909)
    h=Xor(h,math.floor(h/65536))
    return h/4294967296
end
return R
