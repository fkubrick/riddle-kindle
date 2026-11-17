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
        self.started = self.started+time.now()-self.covered_at
        self.covered_at = nil
    end
    local elapsed = time.to_s(time.now()-self.started)
    local x0,y0,x1,y1 = self.w,self.h,-1,-1
    local function dirty(x,y,r)
        x0,y0 = math.min(x0,x-r),math.min(y0,y-r)
        x1,y1 = math.max(x1,x+r),math.max(y1,y+r)
    end
    local stage = math.min(ERASE_STAGES-1,math.floor(elapsed/ERASE_SECONDS*ERASE_STAGES))
    for index=self.stage+1,stage do
        for _,pixel in ipairs(self.erase_pixels[index+1]) do
            local x,y = pixel%self.w,math.floor(pixel/self.w)
            self.image:setPixel(x,y,BB.COLOR_WHITE)
            dirty(x,y,0)
        end
    end
    self.stage = stage
    if elapsed >= ERASE_SECONDS then
        if not self.reply_started then
            self.reply_started = true
        end
        local progress = math.min(1,(elapsed-ERASE_SECONDS)/WRITE_SECONDS)
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
    if self.drawn<self.total or elapsed<ERASE_SECONDS then UI:scheduleIn(FRAME_SECONDS,self.advance) end
end
function Animation:setReply(paths,id)
    if self.message_id==id then return end
    self.message_id=id
    self.paths,self.total,self.radius=Model.fit(paths,self.w,self.h,Screen:scaleBySize(26))
    self.pen_plan,self.pen_distance=Model.penPlan(self.paths,self.radius)
    self.drawn,self.segment_drawn=0,nil
    if time.to_s(time.now()-self.started)>=ERASE_SECONDS then
        self.erase_pixels=Model.dissolve(self.image,self.w,self.h,0,ERASE_STAGES)
        self.started,self.stage,self.reply_started=time.now(),-1,nil
    end
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
    if self.suspended then self.started=self.started+time.now()-self.suspended end
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
