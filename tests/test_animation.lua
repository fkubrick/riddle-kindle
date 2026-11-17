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
    function image:paintCircle(cx,cy,r,color)
        for y=math.max(0,cy-r),math.min(h-1,cy+r) do for x=math.max(0,cx-r),math.min(w-1,cx+r) do
            if (x-cx)^2+(y-cy)^2<=r*r then self:setPixel(x,y,color) end
        end end
    end
    function image:inkCount() local n=0; for y=0,h-1 do for x=0,w-1 do if self.data[y][x]<255 then n=n+1 end end end; return n end
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
assert(frame(a,9)>0 and a.completed==0 and image:inkCount()>0)
frame(a,11); assert(a.completed==1)
frame(a,14); assert(a.phase=='reading' and a.hide_due==44)
now=43; a:step(); assert(automatic==0)
now=44; a:step(); assert(automatic==1 and write_swipes==1)
local menus=0; a.open_menu=function() menus=menus+1 end
assert(a:handleEvent({handler='onGesture',args={{ges='swipe',direction='south',pos={x=40,y=3},distance=50}}}))
assert(menus==1 and a:handleEvent(swipe) and write_swipes==2)
a:onSuspend(); assert(not scheduled[a.advance]); now=100; a:onResume(); assert(scheduled[a.advance])
a:onCloseWidget(); assert(image.freed and not scheduled[a.advance])

-- A late answer gathers the visible waiting drops before its first word.
now=0; image=makeImage(120,180); image:paintRect(50,50,3,20,0)
local empty=Animation:new{image=image,submission=true,leave=function() end}
top=empty; now=7; empty:step()
assert(empty.phase=='waiting' and image:inkCount()==0 and not empty.message_id)
assert(frame(empty,17)>=3 and image:inkCount()>0)
assert(refreshes[#refreshes].region.w<=4 and refreshes[#refreshes].region.h<=8,
    'waiting should refresh only the small regions around each drop')
local waitingCount=image:inkCount()
now=37; empty:step(); assert(image:inkCount()==waitingCount)
empty:setReply(paths,'after-wait',nil,{1,2}); assert(empty.phase=='gather')
assert(frame(empty,38)>0)
frame(empty,39); assert(empty.phase=='reveal')
empty:onCloseWidget()

now=0
local burned=Animation:new{image=makeImage(120,180),paper_burn=true,leave=function() error('spontaneous expired') end}
top=burned
burned:setReply(paths,'spontaneous','burn',{1,2},true)
assert(burned.phase=='burn')
now=8; burned:step(); now=15; burned:step(); now=160; burned:step()
assert(burned.phase=='reading' and not burned.hide_due)
burned:setReply(paths,'newer',nil,{2}); now=161; burned:step(); now=168; burned:step()
assert(burned.hide_due==198)
burned:onCloseWidget()
local disabled=Animation:new{image=makeImage(120,180),paper_burn=false,leave=function() end}
disabled:setReply(paths,'no-burn','burn',{2}); assert(disabled.phase=='reveal'); disabled:onCloseWidget()

for _,update in ipairs(refreshes) do
    assert(update.mode~='full' and update.mode~='flashui' and update.mode~='flashpartial')
end
