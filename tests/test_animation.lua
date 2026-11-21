local now,top,scheduled=0,nil,{}
local refreshes={}
local UI={setDirty=function(_,_,mode,region) refreshes[#refreshes+1]={mode=mode,region=region} end,
    scheduleIn=function(_,delay,fn) scheduled[fn]=now+delay end,
    unschedule=function(_,fn) scheduled[fn]=nil end,getTopmostVisibleWidget=function() return top end}
local function stub(name,value) package.loaded[name]=value end
stub('ui/uimanager',UI); stub('random',{})
stub('ui/time',{now=function() return now end,s=function(v) return v end,to_s=function(v) return v end})
local gd={feedEvent=function() end,getContact=function() end}
stub('device',{hasKeys=function() return true end,input={group={Back='Back'},gesture_detector=gd},
    screen={getWidth=function() return 120 end,getHeight=function() return 180 end,scaleBySize=function(_,n) return n end}})
stub('ui/geometry',{new=function(_,o) return o end})
local function extend(parent,child) child.extend=extend; return setmetatable(child,{__index=parent}) end
stub('ui/widget/container/inputcontainer',{extend=extend,new=function(self,o)
    setmetatable(o,{__index=self}); o.key_events={}; o:init(); return o
end,handleEvent=function(widget,event)
    local child=widget[1]
    if child and event.args[1].hit then (child.callback or child.buttons[1][1].callback)(); return true end
end})
stub('ui/widget/buttontable',{new=function(_,o) o.getSize=function() return {h=20} end; o.free=function() end; return o end})
stub('ui/widget/container/widgetcontainer',{new=function(_,o) o.free=function() end; return o end})
function makeImage(w,h)
    local image={data={}}
    function image:fill(color) for y=0,h-1 do self.data[y]={}; for x=0,w-1 do self.data[y][x]=color end end end
    function image:setPixel(x,y,color)
        assert(x>=0 and x<w and y>=0 and y<h and color>=0 and color<=255)
        self.data[y][x]=color
    end
    function image:getPixel(x,y) return {getColor8=function() return {a=self.data[y][x]} end} end
    function image:paintRect(x,y,rw,rh,color)
        for j=y,y+rh-1 do for i=x,x+rw-1 do self:setPixel(i,j,color) end end
    end
    function image:blitFrom(source,x,y,sx,sy,rw,rh)
        for j=0,rh-1 do
            for i=0,rw-1 do self:setPixel(x+i,y+j,source.data[sy+j][sx+i]) end
        end
    end
    function image:paintCircle(cx,cy,r,color)
        for y=math.max(0,cy-r),math.min(h-1,cy+r) do for x=math.max(0,cx-r),math.min(w-1,cx+r) do
            if (x-cx)^2+(y-cy)^2<=r*r then self:setPixel(x,y,color) end
        end end
    end
    function image:inkCount(left,right)
        local count=0
        for y=0,h-1 do
            for x=left or 0,right or w-1 do
                if self.data[y][x]<255 then count=count+1 end
            end
        end
        return count
    end
    function image:free() self.freed=true end
    image:fill(255); return image
end
stub('ffi/blitbuffer',{COLOR_WHITE=255,COLOR_BLACK=0,Color8=function(v) return v end,new=makeImage})
local Animation=require('riddlelocal/animation')

local function frame(animation,at)
    now=at
    local before=#refreshes
    animation:step()
    for index=before+1,#refreshes do
        local update=refreshes[index]
        local region=update.region
        assert(update.mode=='fast' and region,'every animation frame should use a regional fast refresh')
        assert(region.x>=0 and region.y>=0 and region.w>=2 and region.h>=2)
        assert(region.x+region.w<=animation.w and region.y+region.h<=animation.h)
    end
    return #refreshes-before
end

local image=makeImage(120,180); image:paintRect(55,55,3,35,0)
local closed,write_swipes,automatic=0,0,0
local a=Animation:new{image=image,ink_y=0,submission=true,leave=function(write,auto)
    closed=closed+1; if write then write_swipes=write_swipes+1 end; if auto then automatic=automatic+1 end
end}
top=a; a:onShow()
assert(a.phase=='absorb' and a.duration==7)
local tap={handler='onGesture',args={{ges='tap',hit=true}}}
local swipe={handler='onGesture',args={{ges='swipe',direction='east',distance=60}}}
local idle=a.journal_controls
assert(not a[1]); assert(a:handleEvent(tap) and a[1] and closed==0)
now=5; idle.expire(); assert(not a[1])
assert(frame(a,5.5)>0 and image:inkCount()>0)
local paths={{{1,1},{2,3},{3,2}},{{7,6},{8,8},{9,6}}}
a:setReply(paths,'reply-1',nil,{1,2})
assert(a.phase=='absorb' and a.submission_active,'early reception must not discard submitted ink')
now=6; a:step(); assert(a.phase=='absorb')
now=7; a:step(); assert(a.phase=='reveal' and image:inkCount()==0)
assert(frame(a,9)>0 and a.phase=='reveal')
assert(image:inkCount(0,59)>0 and image:inkCount(60,119)>0,
    'both words must emerge in the same frame even when block boundaries are supplied')
frame(a,12.9); assert(a.phase=='reveal' and not a.hide_due)
frame(a,13); assert(a.phase=='reading' and a.hide_due==43)
local readingInk=image:inkCount()
now=42; a:step(); assert(automatic==0)
frame(a,43); assert(a.phase=='fade' and automatic==0 and image:inkCount()==readingInk)
frame(a,45); assert(automatic==0 and image:inkCount()>0 and image:inkCount()<readingInk)
frame(a,46.8); assert(scheduled[a.advance]==47 and automatic==0)
frame(a,47); assert(automatic==1 and write_swipes==1 and image:inkCount()==0)
local menus=0; a.open_menu=function() menus=menus+1 end
assert(a:handleEvent({handler='onGesture',args={{ges='swipe',direction='south',pos={x=40,y=3},distance=50}}}))
assert(menus==1 and a:handleEvent(swipe) and write_swipes==2)
a:onSuspend(); assert(not scheduled[a.advance]); now=100; a:onResume(); assert(scheduled[a.advance])
a:onCloseWidget(); assert(image.freed and not scheduled[a.advance])

-- The waiting screen has no animation and a reply restarts rendering.
now=0; image=makeImage(120,180); image:paintRect(50,50,3,20,0)
local empty=Animation:new{image=image,submission=true,leave=function() end}
top=empty; now=7; empty:step()
assert(empty.phase=='waiting' and image:inkCount()==0 and not empty.message_id)
assert(not scheduled[empty.advance])
assert(frame(empty,37)==0 and not scheduled[empty.advance] and image:inkCount()==0)
empty:setReply(paths,'after-wait',nil,{1,2}); assert(empty.phase=='reveal' and scheduled[empty.advance])
frame(empty,39); assert(image:inkCount(0,59)>0 and image:inkCount(60,119)>0)
frame(empty,43); assert(empty.phase=='reading' and empty.hide_due==73)
empty:onCloseWidget()

now=0
local burned=Animation:new{image=makeImage(120,180),paper_burn=true,leave=function() error('spontaneous expired') end}
top=burned
burned:setReply(paths,'spontaneous','burn',{1,2},true)
assert(burned.phase=='burn')
local content=burned.burn_content
now=4; burned:step()
local revealed,hidden=0,0
for y=0,179 do for x=0,119 do
    if content.data[y][x]==0 then
        if burned.image.data[y][x]==0 then revealed=revealed+1 else hidden=hidden+1 end
    end
end end
assert(revealed>0 and hidden>0,'the burn exposes part of the actual text before the end')
now=8; burned:step()
assert(burned.phase=='reading' and content.freed and not burned.burn_content)
for y=0,179 do for x=0,119 do assert(burned.image.data[y][x]==content.data[y][x]) end end
now=160; burned:step()
assert(burned.phase=='reading' and not burned.hide_due)
burned:setReply(paths,'newer',nil,{2}); now=161; burned:step(); now=167; burned:step()
assert(burned.hide_due==197)
burned:onCloseWidget()
local disabled=Animation:new{image=makeImage(120,180),paper_burn=false,leave=function() end}
disabled:setReply(paths,'no-burn','burn',{2}); assert(disabled.phase=='reveal'); disabled:onCloseWidget()

local BB=require('ffi/blitbuffer')
BB.fromstring=function(w,h,_,bytes)
    assert(w==2 and h==3 and #bytes==6)
    return {
        scale=function(_,rw,rh)
            local result=makeImage(rw,rh)
            result:fill(bytes:byte(1))
            return result
        end,
        free=function() end,
    }
end
now=0
local picture=Animation:new{image=makeImage(120,180),paper_burn=true,leave=function() end}
top=picture
local raster={width=2,height=3,pixels='777777'}
picture:setReply(nil,'picture','burn',nil,true,nil,raster)
now=4; picture:step()
local grays,whites,edges=0,0,0
for y=0,179 do for x=0,119 do
    local pixel=picture.image.data[y][x]
    if pixel==119 then grays=grays+1
    elseif pixel==255 then whites=whites+1
    elseif pixel==0 then edges=edges+1 end
end end
assert(grays>0 and whites>0 and edges>0,'image, paper and rim coexist during the burn')
now=8; picture:step()
assert(picture.image_shown and picture.phase=='reading' and not picture.hide_due)
for y=0,179 do for x=0,119 do assert(picture.image.data[y][x]==119) end end
picture:setReply(nil,'picture-2','burn',nil,true,nil,raster)
local replaced=picture.burn_content
picture:setReply(paths,'next-text','burn',nil,true)
assert(replaced.freed and picture.phase=='burn')
local interrupted=picture.burn_content
picture:onCloseWidget()
assert(interrupted.freed)

-- A scene holds its first text and lets it disperse before rendering the next.
local fragments={"Non,","mais je peux te montrer"}
stub("riddlelocal/reply",{drawSceneFragment=function(target,w,h,fragment)
    local x=fragment==fragments[1] and 20 or 75
    target:paintRect(x,60,15,20,0)
    return {x=0,y=0,w=w,h=h}
end})
now=0; image=makeImage(120,180)
local scene=Animation:new{image=image,leave=function() error("scene dismissed prematurely") end}
top=scene
scene:setReply(nil,'scene',nil,nil,false,fragments)
frame(scene,2); assert(scene.hide_due==5 and image:inkCount(0,59)>0)
frame(scene,5); assert(scene.phase=='fade' and scene.duration==3)
frame(scene,6.5); assert(image:inkCount(0,59)>0 and image:inkCount(60,119)==0)
frame(scene,8); assert(scene.fragment==2 and scene.phase=='reveal' and image:inkCount()==0)
frame(scene,10); assert(image:inkCount(0,59)==0 and image:inkCount(60,119)>0)
frame(scene,14); assert(scene.hide_due==44)
scene:onCloseWidget()
package.loaded["riddlelocal/reply"]=nil

for _,update in ipairs(refreshes) do
    assert(update.mode~='full' and update.mode~='flashui' and update.mode~='flashpartial')
end
