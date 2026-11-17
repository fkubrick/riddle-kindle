-- Local grayscale diffusion: a broad wet halo grows while the original ink fades.
-- Reversing the same progress makes a word block emerge and become sharp.
local Model = require("riddlelocal/model")
local FX = {}

function FX.drawPaths(image,paths,radius,black)
    for _,stroke in ipairs(paths) do
        local previous
        for _,point in ipairs(stroke) do
            local from=previous or point
            local dx,dy=point[1]-from[1],point[2]-from[2]
            local count=math.max(1,math.ceil(math.sqrt(dx*dx+dy*dy)/math.max(1,radius/2)))
            for index=0,count do
                image:paintCircle(math.floor(from[1]+dx*index/count+.5),
                    math.floor(from[2]+dy*index/count+.5),radius,black)
            end
            previous=point
        end
    end
end

function FX.bounds(paths,w,h,radius)
    local x0,y0,x1,y1=w,h,0,0
    for _,stroke in ipairs(paths) do for _,p in ipairs(stroke) do
        x0,y0,x1,y1=math.min(x0,p[1]),math.min(y0,p[2]),math.max(x1,p[1]),math.max(y1,p[2])
    end end
    x0,y0=math.max(0,x0-radius),math.max(0,y0-radius)
    x1,y1=math.min(w-1,x1+radius),math.min(h-1,y1+radius)
    return {x=x0,y=y0,w=x1-x0+1,h=y1-y0+1}
end

function FX.prepare(image,w,h,bounds)
    bounds=bounds or {x=0,y=0,w=w,h=h}
    local spread=math.max(8,math.floor(math.min(w,h)*.032))
    local points,count={},0
    local x0,y0,x1,y1=w,h,-1,-1
    for y=bounds.y,bounds.y+bounds.h-1 do
        for x=bounds.x,bounds.x+bounds.w-1 do
            local value=image:getPixel(x,y):getColor8().a
            if value<250 then
                local angle=Model.bucket(x+17,y+31,360)*math.pi*2/360
                local reach=spread*(.25+.75*Model.bucket(x+43,y+71,100)/100)
                local delay=Model.bucket(x+97,y+13,100)/100*.04
                local index=#points
                count=count+1
                points[index+1]=x
                points[index+2]=y
                points[index+3]=(255-value)/255
                points[index+4]=math.cos(angle)*reach
                points[index+5]=math.sin(angle)*reach
                points[index+6]=delay
                x0,y0,x1,y1=math.min(x0,x),math.min(y0,y),math.max(x1,x),math.max(y1,y)
            end
        end
    end
    if count==0 then return {points=points,count=count,spread=spread,w=w,h=h} end
    local pad=spread+math.max(2,math.floor(w/360))
    x0,y0=math.max(0,x0-pad),math.max(0,y0-pad)
    x1,y1=math.min(w-1,x1+pad),math.min(h-1,y1+pad)
    return {points=points,count=count,spread=spread,w=w,h=h,rect={x=x0,y=y0,w=x1-x0+1,h=y1-y0+1}}
end

function FX.render(image,plan,progress,colors)
    local rect=plan.rect
    if not rect then return end
    local p=math.max(0,math.min(1,progress))
    image:paintRect(rect.x,rect.y,rect.w,rect.h,colors[255])
    local remaining=(1-p)^1.35
    local move=p*p*(3-2*p)
    local points=plan.points
    for i=1,#points,6 do
        local x0,y0,strength,dx,dy,delay=points[i],points[i+1],points[i+2],points[i+3],points[i+4],points[i+5]
        local emergence=math.max(0,math.min(1,(p-delay)/.12))
        local fade=math.max(0,math.min(1,(1-p)/.32))
        local alpha=strength*.28*emergence*fade
        if alpha>=.04 then
            local x=math.max(0,math.min(plan.w-1,math.floor(x0+dx*move+.5)))
            local y=math.max(0,math.min(plan.h-1,math.floor(y0+dy*move+.5)))
            local particleGray=math.floor((255-255*alpha)/17+.5)*17
            if particleGray<255 then image:setPixel(x,y,colors[particleGray]) end
        end
    end
    for i=1,#points,6 do
        local x,y,strength=points[i],points[i+1],points[i+2]
        local gray=math.floor((255-255*strength*remaining)/17+.5)*17
        if gray<255 then image:setPixel(x,y,colors[gray]) end
    end
    return rect
end

local function unionRect(rect,x,y,w,h)
    if w<=0 or h<=0 then return rect end
    if not rect then return {x=x,y=y,w=w,h=h} end
    local x0,y0=math.min(rect.x,x),math.min(rect.y,y)
    local x1,y1=math.max(rect.x+rect.w,x+w),math.max(rect.y+rect.h,y+h)
    return {x=x0,y=y0,w=x1-x0,h=y1-y0}
end

local function paintDrop(image,drop,colors)
    local head=math.max(1,math.floor(drop.w/2))
    local head_x=drop.x+math.floor((drop.w-head)/2)
    image:paintRect(head_x,drop.y,head,1,colors[math.max(0,drop.gray-17)])
    if drop.h>1 then image:paintRect(drop.x,drop.y+1,drop.w,drop.h-1,colors[drop.gray]) end
end

function FX.clearDrops(image,w,h,previous,colors)
    if type(previous)~="table" then return end
    local rect
    for index=#previous,1,-1 do
        local drop=previous[index]
        if drop and drop.w and drop.h then
            local x=math.max(0,math.min(w,drop.x))
            local y=math.max(0,math.min(h,drop.y))
            local width=math.max(0,math.min(w-x,drop.w))
            local height=math.max(0,math.min(h-y,drop.h))
            if width>0 and height>0 then
                image:paintRect(x,y,width,height,colors[255])
                rect=unionRect(rect,x,y,width,height)
            end
        end
        previous[index]=nil
    end
    return rect
end

function FX.waitDrops(image,w,h,phase,previous,colors)
    if type(previous)~="table" then return end
    local rect=FX.clearDrops(image,w,h,previous,colors)
    if w<=0 or h<=0 then return rect end
    local p=math.max(0,math.min(1,phase or 0))
    local size=math.max(2,math.floor(math.min(w,h)/400))
    local dw,dh=math.min(size,w),math.min(size*2,h)
    local count=math.max(3,math.min(12,math.floor(w*h/180000)+3))
    local travel=math.max(2,math.floor(h*.12))
    local max_y=math.max(0,h-dh)
    for index=1,count do
        local jitter=(Model.bucket(index+37,w+h+11,101)/100-.5)*math.max(2,size*2)
        local x=math.floor((index-.5)*w/count+jitter-dw/2+.5)
        x=math.max(0,math.min(w-dw,x))
        local offset=Model.bucket(index+71,w+h+19,1000)/1000
        local base_y=Model.bucket(index+13,w+h+29,1000)/1000*max_y
        local y=(math.floor(base_y+.5)+math.floor(((p+offset)%1)*travel+.5))%(max_y+1)
        local gray=Model.bucket(index+5,w+h+41,2)==0 and 204 or 221
        local drop={x=x,y=y,w=dw,h=dh,gray=gray}
        paintDrop(image,drop,colors)
        previous[#previous+1]=drop
        rect=unionRect(rect,x,y,dw,dh)
    end
    return rect
end

function FX.gatherDrops(image,w,h,origins,phase,previous,colors,paths)
    if type(previous)~="table" then return end
    local rect=FX.clearDrops(image,w,h,previous,colors)
    if w<=0 or h<=0 or type(origins)~="table" or #origins==0 then return rect end
    local targets={}
    for _,stroke in ipairs(paths or {}) do
        for _,point in ipairs(stroke) do
            if point[1] and point[2] then targets[#targets+1]=point end
        end
    end
    if #targets==0 then return rect end
    local p=math.max(0,math.min(1,phase or 0))
    local ease=p*p*(3-2*p)
    for index,origin in ipairs(origins) do
        local target_index=math.min(#targets,math.floor((index-.5)*#targets/#origins)+1)
        local target=targets[target_index]
        local dw,dh=math.max(1,origin.w or 1),math.max(1,origin.h or 1)
        local tx=math.max(0,math.min(w-dw,math.floor(target[1]-(dw-1)/2+.5)))
        local ty=math.max(0,math.min(h-dh,math.floor(target[2]-(dh-1)/2+.5)))
        local x=math.max(0,math.min(w-dw,math.floor(origin.x+(tx-origin.x)*ease+.5)))
        local y=math.max(0,math.min(h-dh,math.floor(origin.y+(ty-origin.y)*ease+.5)))
        local gray=math.floor(math.max(0,math.min(255,(origin.gray or 204)*(1-p)))/17+.5)*17
        local drop={x=x,y=y,w=dw,h=dh,gray=gray}
        paintDrop(image,drop,colors)
        previous[#previous+1]=drop
        rect=unionRect(rect,x,y,dw,dh)
    end
    return rect
end
return FX
