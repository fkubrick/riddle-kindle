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
    local grain=math.max(2,math.floor(w/360))
    local spread=math.max(8,math.floor(math.min(w,h)*.032))
    local cols=math.ceil(w/grain)
    local points,occupied={},{}
    local x0,y0,x1,y1=w,h,-1,-1
    for y=bounds.y,bounds.y+bounds.h-1 do
        for x=bounds.x,bounds.x+bounds.w-1 do
            local value=image:getPixel(x,y):getColor8().a
            if value<250 then
                points[#points+1]={x,y,(255-value)/255}
                occupied[math.floor(y/grain)*cols+math.floor(x/grain)]=true
                x0,y0,x1,y1=math.min(x0,x),math.min(y0,y),math.max(x1,x),math.max(y1,y)
            end
        end
    end
    if #points==0 then return {points=points,cells={}} end
    local offsets={}
    local reach=math.ceil(spread/grain)
    for dy=-reach,reach do for dx=-reach,reach do
        local distance=math.sqrt(dx*dx+dy*dy)*grain
        if distance<=spread then offsets[#offsets+1]={dx,dy,distance} end
    end end
    local distances={}
    for cell in pairs(occupied) do
        local cx,cy=cell%cols,math.floor(cell/cols)
        for _,offset in ipairs(offsets) do
            local x,y=(cx+offset[1])*grain,(cy+offset[2])*grain
            if x>=0 and y>=0 and x<w and y<h then
                local key=math.floor(y/grain)*cols+math.floor(x/grain)
                if not distances[key] or offset[3]<distances[key] then distances[key]=offset[3] end
            end
        end
    end
    local cells={}
    for cell,distance in pairs(distances) do
        local x,y=cell%cols*grain,math.floor(cell/cols)*grain
        cells[#cells+1]={x,y,distance,.85+Model.bucket(x,y,31)/100,
            math.min(grain,w-x),math.min(grain,h-y)}
    end
    x0,y0=math.max(0,x0-spread-grain),math.max(0,y0-spread-grain)
    x1,y1=math.min(w-1,x1+spread+grain),math.min(h-1,y1+spread+grain)
    return {points=points,cells=cells,spread=spread,rect={x=x0,y=y0,w=x1-x0+1,h=y1-y0+1}}
end

function FX.render(image,plan,progress,colors)
    local rect=plan.rect
    if not rect then return end
    local p=math.max(0,math.min(1,progress))
    image:paintRect(rect.x,rect.y,rect.w,rect.h,colors[255])
    local radius=plan.spread*math.sqrt(p)
    local density=.5*math.sqrt(p)*(1-p)^1.2
    if radius>0 then
        for _,cell in ipairs(plan.cells) do
            if cell[3]<radius then
                local alpha=density*(1-cell[3]/radius)*cell[4]
                local gray=math.floor((255-255*alpha)/17+.5)*17
                if gray<255 then image:paintRect(cell[1],cell[2],cell[5],cell[6],colors[gray]) end
            end
        end
    end
    local remaining=(1-p)^1.3
    for _,point in ipairs(plan.points) do
        local gray=math.floor((255-255*point[3]*remaining)/17+.5)*17
        if gray<255 then image:setPixel(point[1],point[2],colors[gray]) end
    end
    return rect
end
return FX
