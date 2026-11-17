-- Dissolution adapted from MaximeRivest/riddle (MIT); see LICENSE-riddle.txt.
local bit = require("bit")
local M = {}
local function mul(a, b)
    local lo, hi = bit.band(a, 65535), bit.rshift(a, 16)
    return bit.tobit(lo*b + bit.lshift(bit.band(hi*b, 65535), 16))
end
function M.bucket(x, y, stages)
    local h = bit.bxor(mul(x, 0x9E3779B1), mul(y, 0x85EBCA6B))
    h = bit.bxor(h, bit.rshift(h, 13))
    h = mul(h, 0xC2B2AE35)
    h = bit.bxor(h, bit.rshift(h, 16))
    if h < 0 then h = h + 4294967296 end
    return h % (stages or 6)
end

-- Index only ink once. Each pixel is visited once again during dissolution.
-- Two-pixel grains break the strokes apart without horizontal scan lines.
function M.dissolve(image, w, h, top, stages)
    local buckets = {}
    for stage=1,stages do buckets[stage] = {} end
    for y=top,h-1 do
        for x=0,w-1 do
            if image:getPixel(x,y):getColor8().a < 250 then
                local stage = M.bucket(math.floor(x/2),math.floor(y/2),stages)+1
                local bucket = buckets[stage]
                bucket[#bucket+1] = y*w+x
            end
        end
    end
    return buckets
end

-- Time follows pen travel, including short lifts between disconnected strokes.
function M.penPlan(paths, radius)
    local plan, distance = {}, 0
    for _,path in ipairs(paths) do
        local previous
        for _,point in ipairs(path) do
            local from = previous or point
            local length = math.max(1,math.sqrt((point[1]-from[1])^2+(point[2]-from[2])^2))
            if not previous then distance = distance + radius*5 end
            plan[#plan+1] = {from=from, to=point, start=distance, length=length}
            distance = distance + length
            previous = point
        end
    end
    return plan, distance
end
function M.fit(paths, w, h, margin)
    local x0,y0,x1,y1 = math.huge,math.huge,-math.huge,-math.huge
    for _,p in ipairs(paths) do for _,q in ipairs(p) do
        x0,y0,x1,y1 = math.min(x0,q[1]),math.min(y0,q[2]),math.max(x1,q[1]),math.max(y1,q[2])
    end end
    assert(x1>x0 and y1>y0)
    local scale = math.min((w-2*margin)/(x1-x0),(h-2*margin)/(y1-y0))
    local dx,dy = (w-(x1-x0)*scale)/2,(h-(y1-y0)*scale)/2
    local out,total = {},0
    for _,p in ipairs(paths) do
        local line = {}
        for _,q in ipairs(p) do
            local point = {math.floor(dx+(q[1]-x0)*scale+.5),math.floor(dy+(q[2]-y0)*scale+.5)}
            line[#line+1] = point
            total = total+1
        end
        out[#out+1] = line
    end
    return out,total,math.max(2, math.floor(2*scale+.5))
end
return M
