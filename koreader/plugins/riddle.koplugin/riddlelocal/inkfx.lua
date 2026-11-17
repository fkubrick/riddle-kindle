-- Spatial dithering keeps animation frames black and white for the fast waveform.
local Model = require("riddlelocal/model")
local FX = {}
local bayer = {
     0,  8,  2, 10,
    12,  4, 14,  6,
     3, 11,  1,  9,
    15,  7, 13,  5,
}

local function threshold(x,y)
    return (bayer[1+(y%4)*4+x%4]+.5)/16
end

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
    local fade=math.min(1,(1-p)/.32)
    local points=plan.points
    for i=1,#points,6 do
        local x0,y0,strength,dx,dy,delay=points[i],points[i+1],points[i+2],points[i+3],points[i+4],points[i+5]
        -- Anchor each particle's threshold to its source so it does not blink as it moves.
        local grain=threshold(x0,y0)
        if strength*remaining>grain then image:setPixel(x0,y0,colors[0]) end
        local emergence=math.max(0,math.min(1,(p-delay)/.12))
        if strength*.28*emergence*fade>grain then
            local x=math.max(0,math.min(plan.w-1,math.floor(x0+dx*move+.5)))
            local y=math.max(0,math.min(plan.h-1,math.floor(y0+dy*move+.5)))
            image:setPixel(x,y,colors[0])
        end
    end
    return rect
end

local function paintDrop(image,drop,colors)
    local head=math.max(1,math.floor(drop.w/2))
    local inset=math.floor((drop.w-head)/2)
    local opacity=(255-drop.gray)/255
    for y=0,drop.h-1 do
        local first,last=0,drop.w-1
        if y==0 then first,last=inset,inset+head-1 end
        for x=first,last do
            if opacity>threshold(x-inset,y) then
                image:setPixel(drop.x+x,drop.y+y,colors[0])
            end
        end
    end
end

function FX.clearDrops(image,previous,colors)
    local regions={}
    for index=#previous,1,-1 do
        local drop=previous[index]
        image:paintRect(drop.x,drop.y,drop.w,drop.h,colors[255])
        regions[index]=drop
        previous[index]=nil
    end
    return regions
end

local function recordDrop(regions,index,drop)
    local old=regions[index]
    -- A short move needs one small update. A wrap or longer jump needs two.
    if old and old.x==drop.x and math.abs(drop.y-old.y)<=2*drop.h then
        regions[index]={x=drop.x,y=math.min(old.y,drop.y),w=drop.w,h=drop.h+math.abs(old.y-drop.y)}
    else
        regions[#regions+1]=drop
    end
end

function FX.waitDrops(image,w,h,phase,previous,colors)
    local regions=FX.clearDrops(image,previous,colors)
    local p=math.max(0,math.min(1,phase))
    local size=math.max(2,math.floor(math.min(w,h)/320))
    local dw,dh=math.min(size,w),math.min(size*2,h)
    local count=math.min(8,math.floor(w*h/180000)+3)
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
        previous[index]=drop
        recordDrop(regions,index,drop)
    end
    return regions
end

function FX.gatherDrops(image,w,h,origins,phase,previous,colors,paths)
    local regions=FX.clearDrops(image,previous,colors)
    local targets={}
    for _,stroke in ipairs(paths or {}) do
        for _,point in ipairs(stroke) do
            targets[#targets+1]=point
        end
    end
    if #targets==0 then return regions end
    local p=math.max(0,math.min(1,phase))
    local ease=p*p*(3-2*p)
    for index,origin in ipairs(origins) do
        local target_index=math.min(#targets,math.floor((index-.5)*#targets/#origins)+1)
        local target=targets[target_index]
        local dw,dh=origin.w,origin.h
        local tx=math.max(0,math.min(w-dw,math.floor(target[1]-(dw-1)/2+.5)))
        local ty=math.max(0,math.min(h-dh,math.floor(target[2]-(dh-1)/2+.5)))
        local x=math.max(0,math.min(w-dw,math.floor(origin.x+(tx-origin.x)*ease+.5)))
        local y=math.max(0,math.min(h-dh,math.floor(origin.y+(ty-origin.y)*ease+.5)))
        local gray=origin.gray*(1-p)
        local drop={x=x,y=y,w=dw,h=dh,gray=gray}
        paintDrop(image,drop,colors)
        previous[index]=drop
        recordDrop(regions,index,drop)
    end
    return regions
end
return FX
