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

-- Precompute when each small patch chars. Several uneven holes grow and merge;
-- the earliest arrival wins, so overlapping holes never redraw their interiors.
function M.burnPlan(w, h, seed)
    local plan = {w=w,h=h,grain=math.max(2,math.floor(w/268)),stages=120,rim=3}
    local sites = {{.22,.20,0},{.72,.12,.04},{.50,.43,.02},
        {.13,.65,.06},{.84,.58,.08},{.43,.88,.03},{.86,.91,.10}}
    local unit = math.min(w,h)
    for index,site in ipairs(sites) do
        site[1]=(site[1]+(M.bucket(index,seed,101)/100-.5)*.08)*w
        site[2]=(site[2]+(M.bucket(seed,index,101)/100-.5)*.08)*h
        site[4]=.85+M.bucket(index+7,seed,101)/100*.3
    end
    local values,maximum = {},0
    for y=0,h-1,plan.grain do
        for x=0,w-1,plan.grain do
            local nearest=math.huge
            for _,site in ipairs(sites) do
                local dx,dy=(x-site[1])/unit/site[4],(y-site[2])/unit*site[4]
                nearest=math.min(nearest,site[3]+math.sqrt(dx*dx+dy*dy))
            end
            local warp=(math.sin(x/unit*29+seed)+math.sin(y/unit*25)+
                .6*math.sin((x+y)/unit*51))*.009
            local rough=(M.bucket(x,y,101)/100-.5)*.008
            local arrival=math.max(.005,nearest+warp+rough)
            values[#values+1]=arrival
            maximum=math.max(maximum,arrival)
        end
    end
    for stage=1,plan.stages do plan[stage]={} end
    local index=0
    for y=0,h-1,plan.grain do
        for x=0,w-1,plan.grain do
            index=index+1
            local stage=1+math.floor(values[index]/maximum*(plan.stages-plan.rim-1))
            local bucket=plan[stage]
            bucket[#bucket+1]=y*w+x
        end
    end
    return plan
end

-- Each patch is painted at most twice: its black rim, then its white interior.
-- Skipped frames go straight to the current frontier without leaving old rims.
function M.burn(image, plan, progress, previous, white, black)
    local current=math.min(plan.stages,math.floor(progress*plan.stages))
    local old=math.floor(previous*plan.stages)
    if current<=old then return end
    local w,h,grain=plan.w,plan.h,plan.grain
    local x0,y0,x1,y1=w,h,0,0
    local function paint(first,last,color)
        for stage=first,last do
            for _,pixel in ipairs(plan[stage]) do
                local x,y=pixel%w,math.floor(pixel/w)
                local width,height=math.min(grain,w-x),math.min(grain,h-y)
                image:paintRect(x,y,width,height,color)
                x0,y0,x1,y1=math.min(x0,x),math.min(y0,y),math.max(x1,x+width),math.max(y1,y+height)
            end
        end
    end
    paint(math.max(1,old-plan.rim+1),math.max(0,current-plan.rim),white)
    paint(math.max(old+1,current-plan.rim+1),current,black)
    if x1>x0 then return {x=x0,y=y0,w=x1-x0,h=y1-y0} end
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
