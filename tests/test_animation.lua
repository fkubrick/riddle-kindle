local now,top,scheduled = 0,nil,{}
local refreshes = {}
local UI = {setDirty=function(_,_,mode) refreshes[#refreshes+1]=mode end,
    scheduleIn=function(_,d,f) scheduled[f]=now+d end,
    unschedule=function(_,f) scheduled[f]=nil end,
    getTopmostVisibleWidget=function() return top end}
local function stub(n,v) package.loaded[n]=v end
stub("ui/uimanager",UI)
stub("random",{})
math.randomseed(123)
stub("ui/time",{now=function() return now end,to_s=function(v) return v end,s=function(v) return v end})
local gd={ feedEvent=function() end, getContact=function() end }
stub("device",{hasKeys=function() return true end,input={group={Back="Back"},gesture_detector=gd},
    screen={getWidth=function() return 120 end,getHeight=function() return 180 end,scaleBySize=function(_,n) return n end}})
stub("ui/geometry",{new=function(_,o) return o end})
local function extend(parent, child) child.extend=extend; return setmetatable(child,{__index=parent}) end
stub("ui/widget/container/inputcontainer",{extend=extend,new=function(self,t)
    setmetatable(t,{__index=self}); t.key_events={}; t:init(); return t
end,handleEvent=function(widget, event)
    local child=widget[1]
    if child and event.args[1].hit then
        (child.callback or child.buttons[1][1].callback)()
        return true
    end
end})
stub("ui/widget/buttontable",{new=function(_,o)
    o.getSize=function() return {h=20} end
    o.free=function() end
    return o
end})
stub("ui/widget/container/widgetcontainer",{new=function(_,o) o.free=function() end; return o end})
stub("ffi/blitbuffer",{COLOR_WHITE=255,COLOR_BLACK=0})
local pixels,stamps={},0
for y=0,179 do pixels[y]={}; for x=0,119 do pixels[y][x]=(y>20 and y<60 or y>160) and x>30 and x<80 and 0 or 255 end end
local image={
    paintRect=function(_,x,y,w,h,c) for j=y,y+h-1 do for i=x,x+w-1 do pixels[j][i]=c end end end,
    getPixel=function(_,x,y) return {getColor8=function() return {a=pixels[y][x]} end} end,
    setPixel=function(_,x,y,c) pixels[y][x]=c end,
    fill=function(_,c) for y=0,179 do for x=0,119 do pixels[y][x]=c end end end,
    paintCircle=function() stamps=stamps+1 end,
    free=function(self) self.freed=true end,
}
local function black()
    local n=0; for y=0,179 do for x=0,119 do if pixels[y][x]==0 then n=n+1 end end end; return n
end
local Animation=require("riddlelocal/animation")
local closed,write_swipes=0,0
local a=Animation:new{image=image,ink_y=0,paths={{{1,1},{2,2},{3,3}},{{6,1},{7,2}}},leave=function(write)
    closed=closed+1; if write then write_swipes=write_swipes+1 end
end}
top=a; a:onShow()
local tap={handler="onGesture",args={{ges="tap",hit=true}}}
local idle=a.journal_controls
assert(not a[1] and a.key_events.Close[1][1]=="Back")
assert(a:handleEvent(tap) and a[1] and closed==0 and scheduled[idle.expire]==5)
now=.2; assert(a:handleEvent(tap) and closed==1 and scheduled[idle.expire]==5.2)
local count=black()
now=.3; a:step()
assert(black()>0 and black()<count)
local row_black,row_white=false,false
for x=31,79 do row_black=row_black or pixels[30][x]==0; row_white=row_white or pixels[30][x]==255 end
assert(row_black and row_white,"dissolution must fragment strokes, not erase whole rows")
for i=1,14 do now=i*3.8/14+.001; a:step(); assert(black()<count or count==0); count=black() end
assert(black()==0 and stamps==0)
now=5.2; idle.expire(); assert(not a[1] and not scheduled[idle.expire])
local swipe={handler="onGesture",args={{ges="swipe",direction="east",distance=60}}}
assert(a:handleEvent(swipe) and write_swipes==1 and not a[1])
assert(not a:handleEvent({handler="onGesture",args={{ges="swipe",direction="east",distance=5}}}))
a:handleEvent({handler="onGesture",args={{ges="pan",start_pos={x=5,y=80}}}})
assert(a:handleEvent({handler="onGesture",args={{ges="pan_release",pos={x=80,y=85}}}}) and write_swipes==2)
now=15; a:step(); assert(stamps>0 and a.drawn<a.total)
now=17; a:step(); assert(a.drawn<a.total)
a:handleEvent(tap)
a:onSuspend(); assert(not scheduled[a.advance]); local before=a.drawn
assert(not a[1] and not scheduled[idle.expire])
now=100; a:step(); assert(a.drawn==before)
a:onResume(); assert(scheduled[a.advance]); now=130; a:step()
assert(a.drawn==a.total)
local menus=0
a.open_menu=function() menus=menus+1 end
assert(a:handleEvent({handler="onGesture",args={{ges="swipe",direction="south",pos={x=40,y=3},distance=50}}}))
assert(menus==1 and not a[1])
assert(not a:handleEvent({handler="onGesture",args={{ges="swipe",direction="south",pos={x=40,y=70},distance=50}}}))
assert(menus==1)
for _,mode in ipairs(refreshes) do assert(mode~="full", "animation requested a flashing full refresh") end
a:onCloseWidget(); assert(image.freed and not scheduled[a.advance])

-- Local waiting phrases stay outside message state and stop when a real reply arrives.
now=0
image:fill(255)
local waiting=Animation:new{image=image,ink_y=0,
    waiting_paths={{{{1,1},{3,4},{6,2}}},{{{1,2},{4,5},{7,1}}}},leave=function() end}
top=waiting; waiting:onShow()
local first_phrase=waiting.waiting_index
local before_waiting=stamps
now=3.6; waiting:step(); assert(stamps==before_waiting and not waiting.message_id)
now=18; waiting:step(); assert(stamps>before_waiting and waiting.drawn<waiting.total)
now=22; waiting:step(); assert(waiting.drawn==waiting.total and not waiting.burning)
assert(waiting.waiting_due==30)
local due=waiting.waiting_due
waiting:onSuspend(); now=50; waiting:onResume()
assert(waiting.waiting_due==due+28)
now=waiting.waiting_due+.1; waiting:step(); assert(waiting.waiting_index~=first_phrase and waiting.burning)
image:fill(0)
now=waiting.started+15; waiting:step()
assert(black()>0 and black()<120*180, 'burn must consume part of the page')
waiting:setReply({{{1,1},{3,5},{9,2}}},"actual-reply")
assert(not waiting.waiting_due and not waiting.waiting_paths and not waiting.burning and not waiting.burn_plan and waiting.message_id=="actual-reply")
now=now+25; waiting:step()
assert(waiting.drawn==waiting.total)
waiting:onCloseWidget()

-- Reopening the journal continues the shuffled deck in this KOReader process.
local catalogue={{{{1,1},{3,4}}},{{{1,2},{3,5}}},{{{1,3},{3,6}}},{{{1,4},{3,7}}}}
local seen,previous={},nil
for index=1,12 do
    if (index-1)%4==0 then seen={} end
    image:fill(255)
    local dialog=Animation:new{image=image,ink_y=0,waiting_paths=catalogue,leave=function() end}
    top=dialog; now=dialog.started+22; dialog:step()
    assert(dialog.drawn==dialog.total)
    assert(not seen[dialog.waiting_index] and dialog.waiting_index~=previous)
    seen[dialog.waiting_index],previous=true,dialog.waiting_index
    dialog:onCloseWidget()
end

-- A full sequence completes one phrase and burn in a minute, then repeats.
now=0; image:fill(255)
local cycle=Animation:new{image=image,ink_y=0,waiting_paths=catalogue,leave=function() end}
top=cycle
now=22; cycle:step(); assert(cycle.drawn==cycle.total and not cycle.burning)
now=30; cycle:step(); assert(cycle.burning and cycle.burn_plan and cycle.waiting_due==90)
now=59; cycle:step(); assert(cycle.burn_progress<1 and cycle.drawn==0)
now=60; cycle:step(); assert(cycle.burn_progress==1 and not cycle.burn_plan and black()==0)
now=78; cycle:step(); assert(cycle.drawn==cycle.total)
now=90; cycle:step(); assert(cycle.burn_plan and cycle.waiting_due==150)
now=120; cycle:step(); assert(cycle.burn_progress==1 and black()==0)
cycle:onCloseWidget()

-- Several separate holes form, then merge and clear completely, even on skips.
local Model=require('riddlelocal/model')
local burn_plan=Model.burnPlan(120,180,3)
image:fill(0)
local progress=0
local function whiteIslands()
    local seen,count={},0
    for y=0,179 do for x=0,119 do
        local key=y*120+x
        if pixels[y][x]==255 and not seen[key] then
            count=count+1
            local queue={key}; seen[key]=true
            while #queue>0 do
                local item=table.remove(queue)
                local cx,cy=item%120,math.floor(item/120)
                for _,delta in ipairs{{1,0},{-1,0},{0,1},{0,-1}} do
                    local nx,ny=cx+delta[1],cy+delta[2]
                    local next_key=ny*120+nx
                    if nx>=0 and nx<120 and ny>=0 and ny<180 and pixels[ny][nx]==255 and not seen[next_key] then
                        seen[next_key]=true; queue[#queue+1]=next_key
                    end
                end
            end
        end
    end end
    return count
end
for _,next_progress in ipairs{.15,.25,.5,.72,1} do
    local region=Model.burn(image,burn_plan,next_progress,progress,255,0)
    assert(region.y>=0 and region.y+region.h<=180)
    if next_progress==.15 then assert(whiteIslands()>=3,'burn should open several independent holes') end
    progress=next_progress
end
assert(black()==0,'burn left ash on the final blank page')
for _,mode in ipairs(refreshes) do assert(mode~="full", "waiting effect requested a flashing full refresh") end

