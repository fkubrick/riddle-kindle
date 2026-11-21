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
local FRAME, ABSORB_SECONDS, REVEAL_SECONDS, READ_SECONDS = .6,7,6,30
local SCENE_REVEAL_SECONDS, SCENE_HOLD_SECONDS, SCENE_FADE_SECONDS = 1.2,3,3
local Animation = Input:extend{
    modal=true,covers_fullscreen=true,stop_events_propagation=true,disable_double_tap=true,
}
local colors={[0]=BB.COLOR_BLACK,[255]=BB.COLOR_WHITE}

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
        self:setReply(self.paths,"local-preview")
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

function Animation:drawContent(target)
    local raster=self.raster
    if raster then
        local bytes=raster.pixels:gsub(".",function(hex) return string.char(tonumber(hex,16)*17) end)
        local source=BB.fromstring(raster.width,raster.height,BB.TYPE_BB8,bytes,raster.width)
        local scale=math.min(self.w/raster.width,self.h/raster.height)
        local w,h=math.max(1,math.floor(raster.width*scale)),math.max(1,math.floor(raster.height*scale))
        local fitted=source:scale(w,h)
        target:blitFrom(fitted,math.floor((self.w-w)/2),math.floor((self.h-h)/2),0,0,w,h)
        fitted:free()
        source:free()
        return
    end
    if self.scene then
        self.reply_bounds=require("riddlelocal/reply").drawSceneFragment(
            target,self.w,self.h,self.scene[self.fragment])
    else
        FX.drawPaths(target,self.paths,self.radius,BB.COLOR_BLACK)
        self.reply_bounds=FX.bounds(self.paths,self.w,self.h,self.radius)
    end
end

function Animation:readContent(now)
    self.phase="reading"
    self.image_shown=self.raster~=nil
    if self:hasMoreFragments() then
        self.hide_due=now+time.s(SCENE_HOLD_SECONDS)
    elseif not self.persistent then
        self.hide_due=now+time.s(READ_SECONDS)
    end
end

function Animation:beginReveal()
    if self.raster then
        self.image:fill(BB.COLOR_WHITE)
        self:drawContent(self.image)
        self:readContent(time.now())
        UI:setDirty(self,"ui",self.dimen)
        return
    end
    self.phase,self.started="reveal",time.now()
end

function Animation:freeBurnContent()
    if self.burn_content then
        self.burn_content:free()
        self.burn_content=nil
    end
end

function Animation:hasMoreFragments()
    return self.scene and self.fragment<#self.scene
end

function Animation:refreshFrame(rect)
    local bottom=self.journal_controls.visible and self.bottom or self.h
    local region=FX.fastRefreshRegion(rect,self.w,bottom)
    if region then UI:setDirty(self,"fast",Geom:new(region)) end
end

function Animation:startResponse()
    if not self.message_id then self.phase="waiting"; return end
    if self.play_burn then
        self.play_burn=false
        self.burn_content=BB.new(self.w,self.h,BB.TYPE_BB8)
        self.burn_content:fill(BB.COLOR_WHITE)
        self:drawContent(self.burn_content)
        self.burn_plan=Model.burnPlan(self.w,self.h,math.random(10000))
        self.burn_progress=0
        self.phase,self.started,self.duration="burn",time.now(),8
    else self:beginReveal() end
end

-- The relay still supplies block boundaries for older clients.
function Animation:setReply(paths,id,effect,_block_ends,persistent,scene,raster)
    if self.message_id==id then return end
    self:freeBurnContent()
    self.message_id=id
    self.persistent=persistent==true
    self.hide_due=nil
    self.scene,self.fragment=scene,1
    self.raster=raster
    self.paths,self.radius=nil,nil
    if not scene and not raster then
        local fitted, _, radius=Model.fit(paths,self.w,self.h,Screen:scaleBySize(26))
        self.paths,self.radius=fitted,radius
    end
    self.play_burn=self.paper_burn==true and effect=="burn"
    -- Receive in parallel; present the newest reply after the submitted ink is absorbed.
    if not self.submission_active then
        if self.image_shown or self.phase=="burn" then
            self.image_shown=false
            self.burn_plan=nil
            self.image:fill(BB.COLOR_WHITE)
            UI:setDirty(self,"ui",self.dimen)
            self:startResponse()
        elseif self.phase=="waiting" then self:startResponse()
        else
            self.phase,self.started,self.duration="erase",time.now(),.6
            self.erase_pixels=Model.dissolve(self.image,self.w,self.h,0,14)
            self.erase_stage=-1
            self.ink_plan,self.burn_plan=nil,nil
        end
    end
    UI:unschedule(self.advance)
    UI:scheduleIn(FRAME,self.advance)
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
    local rect
    local function dirty(region)
        if not region then return end
        if not rect then rect={x=region.x,y=region.y,w=region.w,h=region.h}; return end
        local x,y=math.min(rect.x,region.x),math.min(rect.y,region.y)
        rect={x=x,y=y,w=math.max(rect.x+rect.w,region.x+region.w)-x,
            h=math.max(rect.y+rect.h,region.y+region.h)-y}
    end
    if self.phase=="absorb" or self.phase=="fade" or self.phase=="burn" or self.phase=="erase" then
        local phase=self.phase
        local progress=math.min(1,elapsed/self.duration)
        if phase=="absorb" or phase=="fade" then
            if self.prepare_absorption then
                self.ink_plan=FX.prepare(self.image,self.w,self.h,
                    {x=0,y=self.ink_y or 0,w=self.w,h=self.h-(self.ink_y or 0)})
                self.prepare_absorption=nil
            end
            dirty(FX.render(self.image,self.ink_plan,progress,colors))
        elseif phase=="burn" then
            dirty(Model.burn(self.image,self.burn_plan,progress,self.burn_progress,self.burn_content,BB.COLOR_BLACK))
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
            if phase=="fade" then
                if self:hasMoreFragments() then
                    self.fragment=self.fragment+1
                    self:beginReveal()
                else
                    self.phase="reading"
                    if rect then self:refreshFrame(rect) end
                    self.leave(true,true)
                    return
                end
            elseif self.submission_active then
                self.submission_active=false
                self.phase="waiting"
                self:startResponse()
            elseif phase=="burn" then
                self:freeBurnContent()
                self:readContent(now)
            else self:startResponse() end
        end
    elseif self.phase=="reveal" then
        if not self.ink_plan then
            local scratch=BB.new(self.w,self.h,BB.TYPE_BB8)
            scratch:fill(BB.COLOR_WHITE)
            self:drawContent(scratch)
            self.ink_plan=FX.prepare(scratch,self.w,self.h,self.reply_bounds)
            scratch:free()
        end
        local duration=self:hasMoreFragments() and SCENE_REVEAL_SECONDS or REVEAL_SECONDS
        local progress=math.min(1,elapsed/duration)
        dirty(FX.render(self.image,self.ink_plan,1-progress,colors))
        if progress==1 then
            self.ink_plan=nil
            self:readContent(now)
        end
    elseif self.phase=="reading" and self.hide_due and now>=self.hide_due then
        self.ink_plan=FX.prepare(self.image,self.w,self.h,self.reply_bounds)
        self.phase,self.started="fade",time.now()
        self.duration=self:hasMoreFragments() and SCENE_FADE_SECONDS or FX.REPLY_FADE_SECONDS
        self.hide_due=nil
    end
    if rect then self:refreshFrame(rect) end
    if self.phase=="reading" then
        if self.hide_due then UI:scheduleIn(math.max(FRAME,time.to_s(self.hide_due-now)),self.advance) end
    elseif self.phase=="fade" then
        local remaining=time.to_s(self.started+time.s(self.duration)-time.now())
        UI:scheduleIn(math.max(0,math.min(FRAME,remaining)),self.advance)
    elseif self.phase~="waiting" then UI:scheduleIn(FRAME,self.advance) end
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
    self.ink_plan,self.burn_plan=nil,nil
    self:freeBurnContent()
    self.image:free(); self.controls:free()
end
return Animation
