local BB = require("ffi/blitbuffer")
local Device = require("device")
local Screen = Device.screen
local UI = require("ui/uimanager")
local time = require("ui/time")
local Geom = require("ui/geometry")
local Buttons = require("ui/widget/buttontable")
local Input = require("ui/widget/container/inputcontainer")
local Model = require("riddlelocal/model")
local Idle = require("riddlelocal/idlecontrols")
local Animation = Input:extend{
    modal = true, covers_fullscreen = true, stop_events_propagation = true, disable_double_tap = true,
}
local ERASE_SECONDS, WRITE_SECONDS, FRAME_SECONDS = 3.8, 18, .18
local ERASE_STAGES = 14
require("random") -- KOReader seeds math.random once per process.
local waiting_order, waiting_count, last_waiting = {},0,nil

local function nextWaiting(count)
    if #waiting_order==0 or waiting_count~=count then
        waiting_order,waiting_count={},count
        for index=1,count do waiting_order[index]=index end
        for index=count,2,-1 do
            local other=math.random(index)
            waiting_order[index],waiting_order[other]=waiting_order[other],waiting_order[index]
        end
        if count>1 and waiting_order[count]==last_waiting then
            waiting_order[1],waiting_order[count]=waiting_order[count],waiting_order[1]
        end
    end
    last_waiting=table.remove(waiting_order)
    return last_waiting
end

function Animation:init()
    self.w,self.h = Screen:getWidth(),Screen:getHeight()
    self.dimen = Geom:new{ x=0,y=0,w=self.w,h=self.h }
    self.controls = Buttons:new{ width=self.w, buttons={{
        {text="Fermer",callback=function() self.leave(false) end},
        {text=self.write_label or "Recommencer",callback=function() self.leave(true) end},
    }} }
    self.bottom = self.h-self.controls:getSize().h
    self.journal_controls = Idle.new(function(visible)
        self[1] = visible and self.controls or nil
        if UI:getTopmostVisibleWidget() == self then
            UI:setDirty(self,"ui",Geom:new{x=0,y=self.bottom,w=self.w,h=self.h-self.bottom})
        end
    end)
    if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
    if self.paths then
        self.paths,self.total,self.radius = Model.fit(self.paths,self.w,self.h,Screen:scaleBySize(26))
    else self.paths,self.total,self.radius = {},0,2 end
    self.pen_plan,self.pen_distance = Model.penPlan(self.paths,self.radius)
    self.erase_pixels = Model.dissolve(self.image,self.w,self.h,self.ink_y,ERASE_STAGES)
    self.started = time.now()
    if self.waiting_paths then self.waiting_due=self.started+time.s(ERASE_SECONDS+8) end
    self.stage,self.drawn = -1,0
    self.advance = function() self:step() end
end
function Animation:handleEvent(event)
    if Idle.menuSwipe(self,event,self.h,self.open_menu) then return true end
    if Idle.swipe(self, event, "east", self.w) then
        self.leave(true)
        return true
    end
    if Idle.isTap(event) then
        local was_visible = self.journal_controls.visible
        self.journal_controls:show()
        if not was_visible then return true end
    end
    return Input.handleEvent(self,event)
end
function Animation:onShow()
    UI:setDirty(self,"ui")
    UI:scheduleIn(FRAME_SECONDS,self.advance)
    return true
end
function Animation:step()
    if self.closed or self.suspended then return end
    if UI:getTopmostVisibleWidget() ~= self then
        self.covered_at = self.covered_at or time.now()
        UI:scheduleIn(FRAME_SECONDS,self.advance)
        return
    end
    if self.covered_at then
        local pause = time.now()-self.covered_at
        self.started = self.started+pause
        if self.waiting_due then self.waiting_due=self.waiting_due+pause end
        self.covered_at = nil
    end
    if self.waiting_due and time.now()>=self.waiting_due then
        self.burning=self.waiting_index~=nil
        self.burn_progress=0
        self.erase_seconds=self.burning and 6 or ERASE_SECONDS
        self.waiting_index=nextWaiting(#self.waiting_paths)
        self.paths,self.total,self.radius=Model.fit(self.waiting_paths[self.waiting_index],self.w,self.h,Screen:scaleBySize(26))
        self.pen_plan,self.pen_distance=Model.penPlan(self.paths,self.radius)
        if not self.burning then self.erase_pixels=Model.dissolve(self.image,self.w,self.h,0,ERASE_STAGES) end
        self.started,self.stage,self.drawn,self.segment_drawn=time.now(),-1,0,nil
        self.write_seconds=28
        self.waiting_due=self.started+time.s(self.erase_seconds+self.write_seconds+8)
    end
    local elapsed = time.to_s(time.now()-self.started)
    local erase_seconds = self.erase_seconds or ERASE_SECONDS
    local x0,y0,x1,y1 = self.w,self.h,-1,-1
    local function dirty(x,y,r)
        x0,y0 = math.min(x0,x-r),math.min(y0,y-r)
        x1,y1 = math.max(x1,x+r),math.max(y1,y+r)
    end
    if self.burning then
        local progress=math.min(1,elapsed/erase_seconds)
        if progress>self.burn_progress then
            local rect=Model.burn(self.image,self.w,self.h,progress,self.burn_progress,BB.COLOR_WHITE,BB.COLOR_BLACK)
            if rect then
                dirty(rect.x,rect.y,0)
                dirty(rect.x+rect.w-1,rect.y+rect.h-1,0)
            end
            self.burn_progress=progress
        end
    else
        local stage = math.min(ERASE_STAGES-1,math.floor(elapsed/erase_seconds*ERASE_STAGES))
        for index=self.stage+1,stage do
            for _,pixel in ipairs(self.erase_pixels[index+1]) do
                local x,y = pixel%self.w,math.floor(pixel/self.w)
                self.image:setPixel(x,y,BB.COLOR_WHITE)
                dirty(x,y,0)
            end
        end
        self.stage = stage
    end
    if elapsed >= erase_seconds then
        if not self.reply_started then
            self.reply_started = true
        end
        local progress = math.min(1,(elapsed-erase_seconds)/(self.write_seconds or WRITE_SECONDS))
        -- Slight acceleration and hesitation, while preserving monotonic motion.
        local target = self.pen_distance*(progress-math.sin(progress*math.pi*8)*.012)
        while self.drawn < #self.pen_plan do
            local segment = self.pen_plan[self.drawn+1]
            if target < segment.start then break end
            local finish = math.min(segment.length,target-segment.start)
            local start = self.segment_drawn or 0
            local count = math.max(1,math.ceil(finish-start))
            for j=1,count do
                local fraction = (start+(finish-start)*j/count)/segment.length
                local x = math.floor(segment.from[1]+(segment.to[1]-segment.from[1])*fraction+.5)
                local y = math.floor(segment.from[2]+(segment.to[2]-segment.from[2])*fraction+.5)
                self.image:paintCircle(x,y,self.radius,BB.COLOR_BLACK)
                dirty(x,y,self.radius)
            end
            if finish < segment.length then self.segment_drawn=finish; break end
            self.drawn,self.segment_drawn = self.drawn+1,nil
        end
    end
    if x1>=x0 then
        x0,y0,x1,y1 = math.max(0,x0),math.max(0,y0),math.min(self.w-1,x1),math.min(self.h-1,y1)
        UI:setDirty(self,"fast",Geom:new{x=x0,y=y0,w=x1-x0+1,h=y1-y0+1})
    end
    if self.waiting_due and self.drawn==self.total and elapsed>=erase_seconds then
        UI:scheduleIn(math.max(FRAME_SECONDS,time.to_s(self.waiting_due-time.now())),self.advance)
    elseif self.drawn<self.total or elapsed<erase_seconds then
        UI:scheduleIn(FRAME_SECONDS,self.advance)
    end
end
function Animation:setReply(paths,id)
    if self.message_id==id then return end
    self.message_id=id
    self.waiting_paths,self.waiting_due,self.write_seconds=nil,nil,nil
    self.paths,self.total,self.radius=Model.fit(paths,self.w,self.h,Screen:scaleBySize(26))
    self.pen_plan,self.pen_distance=Model.penPlan(self.paths,self.radius)
    self.drawn,self.segment_drawn=0,nil
    if self.burning or time.to_s(time.now()-self.started)>=ERASE_SECONDS then
        self.erase_pixels=Model.dissolve(self.image,self.w,self.h,0,ERASE_STAGES)
        self.started,self.stage,self.reply_started=time.now(),-1,nil
    end
    self.burning,self.erase_seconds=nil,nil
    self.covered_at=nil
    UI:unschedule(self.advance)
    UI:scheduleIn(FRAME_SECONDS,self.advance)
end
function Animation:paintTo(bb,x,y)
    bb:blitFrom(self.image,x,y,0,0,self.w,self.h)
    if self.journal_controls.visible then
        bb:paintRect(x,y+self.bottom,self.w,self.h-self.bottom,BB.COLOR_WHITE)
        self.controls:paintTo(bb,x,y+self.bottom)
    end
end
function Animation:onSuspend()
    self.suspended = time.now()
    UI:unschedule(self.advance)
    self.journal_controls:hide()
end
function Animation:onResume()
    if self.suspended then
        local pause=time.now()-self.suspended
        self.started=self.started+pause
        if self.waiting_due then self.waiting_due=self.waiting_due+pause end
    end
    self.suspended = nil
    UI:setDirty(self,"ui")
    UI:scheduleIn(FRAME_SECONDS,self.advance)
end
function Animation:onClose() self.leave(false); return true end
function Animation:onSetDimensions() self.leave(false); return true end
function Animation:onCloseWidget()
    self.closed = true
    UI:unschedule(self.advance)
    self.journal_controls:hide()
    self.image:free()
    self.controls:free()
end
return Animation
