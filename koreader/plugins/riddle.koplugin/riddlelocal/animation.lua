local BB = require("ffi/blitbuffer")
local Device = require("device")
local Screen = Device.screen
local UI = require("ui/uimanager")
local time = require("ui/time")
local Geom = require("ui/geometry")
local Buttons = require("ui/widget/buttontable")
local Input = require("ui/widget/container/inputcontainer")
local Model = require("riddlelocal/model")
local FX = require("riddlelocal/inkfx")
local Idle = require("riddlelocal/idlecontrols")
require("random")
local FRAME, ABSORB_SECONDS, READ_SECONDS = .6,40,30
local Animation = Input:extend{
    modal=true,covers_fullscreen=true,stop_events_propagation=true,disable_double_tap=true,
}
local colors={}
for value=0,255,17 do colors[value]=BB.Color8(value) end

function Animation:init()
    self.w,self.h=Screen:getWidth(),Screen:getHeight()
    self.dimen=Geom:new{x=0,y=0,w=self.w,h=self.h}
    self.controls=Buttons:new{width=self.w,buttons={{
        {text="Fermer",callback=function() self.leave(false) end},
        {text=self.write_label or "Écrire",callback=function() self.leave(true) end},
    }}}
    self.bottom=self.h-self.controls:getSize().h
    self.journal_controls=Idle.new(function(visible)
        self[1]=visible and self.controls or nil
        if UI:getTopmostVisibleWidget()==self then
            UI:setDirty(self,"ui",Geom:new{x=0,y=self.bottom,w=self.w,h=self.h-self.bottom})
        end
    end)
    if Device:hasKeys() then self.key_events={Close={{Device.input.group.Back}}} end
    self.advance=function() self:step() end
    self.started=time.now()
    self.phase="waiting"
    if self.submission then
        self.submission_active=true
        self.duration=ABSORB_SECONDS
        self.phase="absorb"
        self.prepare_absorption=true
    elseif self.paths then
        self:setReply(self.paths,"local-preview",nil,self.block_ends)
    end
end

function Animation:handleEvent(event)
    if Idle.menuSwipe(self,event,self.h,self.open_menu) then return true end
    if Idle.swipe(self,event,"east",self.w) then self.leave(true); return true end
    if Idle.isTap(event) then
        local visible=self.journal_controls.visible
        self.journal_controls:show()
        if not visible then return true end
    end
    return Input.handleEvent(self,event)
end
function Animation:onShow()
    UI:setDirty(self,"ui")
    UI:scheduleIn(FRAME,self.advance)
    return true
end

function Animation:beginReveal()
    self.phase,self.started="reveal",time.now()
    self.completed=0
    self.group_plan=nil
    self.reveal_seconds=math.max(8,#self.groups*2.4)
    if self.gather_finished then
        self.started=self.started-time.s(self.reveal_seconds/#self.groups*.2)
    end
end
function Animation:startResponse()
    if not self.message_id then self.phase,self.started="waiting",time.now(); self.wait_drops={}; return end
    if self.play_burn then
        if self.wait_drops then
            local area=FX.clearDrops(self.image,self.w,self.h,self.wait_drops,colors)
            if area then UI:setDirty(self,"ui",Geom:new(area)) end
        end
        self.wait_drops,self.drop_origins,self.gather_finished=nil,nil,nil
        self.play_burn=false
        self.phase,self.started,self.duration="burn",time.now(),8
        self.burn_plan=Model.burnPlan(self.w,self.h,math.random(10000))
        self.burn_progress=0
    elseif self.wait_drops and next(self.wait_drops) then
        self.phase,self.started="gather",time.now()
        self.drop_origins={}
        for index,drop in ipairs(self.wait_drops) do
            self.drop_origins[index]={x=drop.x,y=drop.y,w=drop.w,h=drop.h,gray=drop.gray}
        end
    else self:beginReveal() end
end

function Animation:setReply(paths,id,effect,block_ends,persistent)
    if self.message_id==id then return end
    self.message_id=id
    self.persistent=persistent==true
    self.hide_due=nil
    self.paths,self.total,self.radius=Model.fit(paths,self.w,self.h,Screen:scaleBySize(26))
    self.groups={}
    local first=1
    for _,last in ipairs(block_ends or {#self.paths}) do
        local group={}
        for index=first,last do group[#group+1]=self.paths[index] end
        self.groups[#self.groups+1]={paths=group,rect=FX.bounds(group,self.w,self.h,self.radius)}
        first=last+1
    end
    self.play_burn=self.paper_burn==true and effect=="burn"
    self.group_plan=nil
    -- Receive in parallel; present the newest reply after the submitted ink is absorbed.
    if not self.submission_active then
        if self.phase=="waiting" then self:startResponse()
        else
            self.phase,self.started,self.duration="erase",time.now(),.6
            self.erase_pixels=Model.dissolve(self.image,self.w,self.h,0,14)
            self.wait_drops,self.drop_origins,self.gather_finished=nil,nil,nil
            self.erase_stage=-1
            self.ink_plan,self.burn_plan=nil,nil
        end
    end
    UI:unschedule(self.advance)
    UI:scheduleIn(FRAME,self.advance)
end

local function intersects(a,b)
    return a.x<b.x+b.w and b.x<a.x+a.w and a.y<b.y+b.h and b.y<a.y+a.h
end
function Animation:restoreCompleted(rect)
    for index=1,self.completed do
        local group=self.groups[index]
        if intersects(rect,group.rect) then FX.drawPaths(self.image,group.paths,self.radius,BB.COLOR_BLACK) end
    end
end

function Animation:step()
    if self.closed or self.suspended then return end
    local now=time.now()
    if UI:getTopmostVisibleWidget()~=self then
        self.covered_at=self.covered_at or now
        UI:scheduleIn(FRAME,self.advance)
        return
    end
    if self.covered_at then
        local pause=now-self.covered_at
        self.started=self.started+pause
        if self.hide_due then self.hide_due=self.hide_due+pause end
        self.covered_at=nil
    end
    local elapsed=time.to_s(now-self.started)
    local rect,refresh=nil,"ui"
    local function dirty(region)
        if not region then return end
        if not rect then rect={x=region.x,y=region.y,w=region.w,h=region.h}; return end
        local x,y=math.min(rect.x,region.x),math.min(rect.y,region.y)
        rect={x=x,y=y,w=math.max(rect.x+rect.w,region.x+region.w)-x,
            h=math.max(rect.y+rect.h,region.y+region.h)-y}
    end
    if self.phase=="absorb" or self.phase=="burn" or self.phase=="erase" then
        local phase=self.phase
        local progress=math.min(1,elapsed/self.duration)
        if phase=="absorb" then
            if self.prepare_absorption then
                self.ink_plan=FX.prepare(self.image,self.w,self.h,
                    {x=0,y=self.ink_y or 0,w=self.w,h=self.h-(self.ink_y or 0)})
                self.prepare_absorption=nil
            end
            dirty(FX.render(self.image,self.ink_plan,progress,colors))
        elseif phase=="burn" then
            refresh="fast"
            dirty(Model.burn(self.image,self.burn_plan,progress,self.burn_progress,BB.COLOR_WHITE,BB.COLOR_BLACK))
            self.burn_progress=progress
        else
            local stage=math.min(13,math.floor(progress*14))
            for index=self.erase_stage+1,stage do for _,pixel in ipairs(self.erase_pixels[index+1]) do
                local x,y=pixel%self.w,math.floor(pixel/self.w)
                self.image:setPixel(x,y,BB.COLOR_WHITE); dirty({x=x,y=y,w=1,h=1})
            end end
            self.erase_stage=stage
        end
        if progress==1 then
            self.ink_plan,self.burn_plan,self.erase_pixels=nil,nil,nil
            if self.submission_active then
                self.submission_active=false
                self.phase="waiting"
                self:startResponse()
            elseif phase=="burn" then self:beginReveal()
            else self:startResponse() end
        end
    elseif self.phase=="waiting" and self.wait_drops then
        dirty(FX.waitDrops(self.image,self.w,self.h,(elapsed%20)/20,self.wait_drops,colors))
    elseif self.phase=="gather" then
        local progress=math.min(1,elapsed/2)
        dirty(FX.gatherDrops(self.image,self.w,self.h,self.drop_origins,progress,self.wait_drops,colors,self.groups[1].paths))
        if progress==1 then
            self.gather_finished=true
            self:beginReveal()
        end
    elseif self.phase=="reveal" then
        if self.gather_finished then
            dirty(FX.clearDrops(self.image,self.w,self.h,self.wait_drops,colors))
            self.gather_finished=nil
            self.drop_origins,self.wait_drops=nil,nil
        end
        local per_group=self.reveal_seconds/#self.groups
        local complete=math.min(#self.groups,math.floor(elapsed/per_group))
        while self.completed<complete do
            if self.group_plan and self.group_plan.rect then
                local area=self.group_plan.rect
                self.image:paintRect(area.x,area.y,area.w,area.h,BB.COLOR_WHITE)
                self:restoreCompleted(area); dirty(area)
            end
            self.completed=self.completed+1
            local group=self.groups[self.completed]
            FX.drawPaths(self.image,group.paths,self.radius,BB.COLOR_BLACK)
            dirty(group.rect); self.group_plan=nil
        end
        if self.completed==#self.groups then
            self.phase="reading"
            if not self.persistent then self.hide_due=now+time.s(READ_SECONDS) end
        else
            local group=self.groups[self.completed+1]
            if not self.group_plan then
                local scratch=BB.new(self.w,self.h,BB.TYPE_BB8)
                scratch:fill(BB.COLOR_WHITE)
                FX.drawPaths(scratch,group.paths,self.radius,BB.COLOR_BLACK)
                self.group_plan=FX.prepare(scratch,self.w,self.h,group.rect)
                scratch:free()
            end
            local progress=(elapsed-self.completed*per_group)/per_group
            local area=FX.render(self.image,self.group_plan,1-progress,colors)
            if area then self:restoreCompleted(area); dirty(area) end
        end
    elseif self.phase=="reading" and self.hide_due and now>=self.hide_due then
        self.leave(true,true)
        return
    end
    if rect then UI:setDirty(self,refresh,Geom:new(rect)) end
    if self.phase=="reading" then
        if self.hide_due then UI:scheduleIn(math.max(FRAME,time.to_s(self.hide_due-now)),self.advance) end
    elseif self.phase~="waiting" or self.wait_drops then UI:scheduleIn(FRAME,self.advance) end
end

function Animation:paintTo(bb,x,y)
    bb:blitFrom(self.image,x,y,0,0,self.w,self.h)
    if self.journal_controls.visible then
        bb:paintRect(x,y+self.bottom,self.w,self.h-self.bottom,BB.COLOR_WHITE)
        self.controls:paintTo(bb,x,y+self.bottom)
    end
end
function Animation:onSuspend()
    self.suspended=time.now(); UI:unschedule(self.advance); self.journal_controls:hide()
end
function Animation:onResume()
    if self.suspended then
        local pause=time.now()-self.suspended
        self.started=self.started+pause
        if self.hide_due then self.hide_due=self.hide_due+pause end
        if self.covered_at then self.covered_at=self.covered_at+pause end
    end
    self.suspended=nil; UI:setDirty(self,"ui"); UI:scheduleIn(FRAME,self.advance)
end
function Animation:onClose() self.leave(false); return true end
function Animation:onSetDimensions() self.leave(false); return true end
function Animation:onCloseWidget()
    self.closed=true; UI:unschedule(self.advance); self.journal_controls:hide()
    self.ink_plan,self.group_plan,self.burn_plan=nil,nil,nil
    self.image:free(); self.controls:free()
end
return Animation
