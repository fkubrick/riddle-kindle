local Base = require("ink/alfred/reply")
local BB = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local UI = require("ui/uimanager")
local time = require("ui/time")
local FX = require("riddlelocal/inkfx")
local Idle = require("riddlelocal/idlecontrols")
local Screen = require("device").screen
local Reply = Base:extend{ disable_double_tap = true }
local FRAME = .6
local colors = {[0]=BB.COLOR_BLACK,[255]=BB.COLOR_WHITE}

function Reply.scene(text)
    local body=text:match("^%[%[scene%]%]%s+(.+)$")
    if not body then return end
    local fragments={}
    for fragment in (body.."||"):gmatch("(.-)||") do
        fragment=fragment:match("^%s*(.-)%s*$")
        if fragment=="" then return end
        fragments[#fragments+1]=fragment
    end
    if #fragments>1 then return fragments end
end

function Reply.drawSceneFragment(image,w,h,text)
    local inset=Screen:scaleBySize(18)
    local rect={x=inset,y=inset,w=w-2*inset,h=h-2*inset}
    local layout={text_rect=rect,textBox=Base.textBox}
    local box=layout:textBox(text,Base.fit(layout,text))
    local y=rect.y+math.max(0,math.floor((rect.h-box:getSize().h)/2))
    box:paintTo(image,rect.x,y)
    box:free()
    return rect
end

function Reply:init()
    Base.init(self)
    self[1] = nil
    self.journal_controls = Idle.new(function(visible)
        self[1] = visible and self.button or nil
        if UI:getTopmostVisibleWidget() == self then
            local size = self.button:getSize()
            UI:setDirty(self, "ui", Geom:new{ x = self.button_x, y = self.button_y, w = size.w, h = size.h })
        end
    end)
end

function Reply:handleEvent(event)
    if Idle.menuSwipe(self,event,self.dimen.h,self.open_menu) then return true end
    if Idle.swipe(self, event, "east", self.dimen.w) then
        self.write(self.message_id)
        return true
    end
    if Idle.isTap(event) then
        local was_visible = self.journal_controls.visible
        self.journal_controls:show()
        if not was_visible then return true end
    end
    return Base.handleEvent(self, event)
end

function Reply:paintTo(bb, x, y)
    if self.fade_image then
        bb:blitFrom(self.fade_image, x, y, 0, 0, self.dimen.w, self.dimen.h)
    else
        bb:paintRect(x, y, self.dimen.w, self.dimen.h, BB.COLOR_WHITE)
        if self.box then self.box:paintTo(bb, x + self.text_rect.x, y + self.text_rect.y) end
    end
    if self.journal_controls.visible then self.button:paintTo(bb, x + self.button_x, y + self.button_y) end
end

function Reply:resetExpiry()
    if self.expire then UI:unschedule(self.expire) end
    if self.fade_image then self.fade_image:free() end
    self.expire,self.hide_due,self.fade_image,self.fade_plan,self.covered_at=nil,nil,nil,nil,nil
end

function Reply:stepExpiry()
    local now=time.now()
    if UI:getTopmostVisibleWidget()~=self then
        if self.fade_image then self.covered_at=self.covered_at or now end
        UI:scheduleIn(FRAME,self.expire)
        return
    end
    if self.covered_at then
        self.hide_due=self.hide_due+now-self.covered_at
        self.covered_at=nil
    end
    if not self.fade_image then
        if not self.box then
            self.expire,self.hide_due=nil,nil
            self.write(true)
            return
        end
        local w,h=self.dimen.w,self.dimen.h
        self.fade_image=BB.new(w,h,BB.TYPE_BB8)
        self.fade_image:fill(BB.COLOR_WHITE)
        self.box:paintTo(self.fade_image,self.text_rect.x,self.text_rect.y)
        self.fade_plan=FX.prepare(self.fade_image,w,h,self.text_rect)
        now=time.now()
        self.hide_due=now+time.s(FX.REPLY_FADE_SECONDS)
    end
    local progress=math.min(1,1-time.to_s(self.hide_due-now)/FX.REPLY_FADE_SECONDS)
    local rect=FX.render(self.fade_image,self.fade_plan,progress,colors)
    local bottom=self.journal_controls.visible and self.button_y or self.dimen.h
    local region=FX.fastRefreshRegion(rect,self.dimen.w,bottom)
    if region then UI:setDirty(self,"fast",Geom:new(region)) end
    if progress==1 then
        self.expire,self.hide_due,self.fade_plan=nil,nil,nil
        self.write(true)
    else
        local remaining=time.to_s(self.hide_due-time.now())
        UI:scheduleIn(math.max(0,math.min(FRAME,remaining)),self.expire)
    end
end

function Reply:replace(id,text)
    self:resetExpiry()
    Base.replace(self,id,text)
    if self.persistent then return end
    self.hide_due=time.now()+time.s(.6*#Base.groups(text)+30)
    self.expire=function() self:stepExpiry() end
    UI:scheduleIn(time.to_s(self.hide_due-time.now()),self.expire)
end

function Reply:onSuspend()
    self.journal_controls:hide()
    self.pause_at=time.now()
    if self.expire then UI:unschedule(self.expire) end
end

function Reply:onResume()
    if self.pause_at and self.hide_due then
        local pause=time.now()-self.pause_at
        self.hide_due=self.hide_due+pause
        if self.covered_at then self.covered_at=self.covered_at+pause end
    end
    self.pause_at=nil
    if self.expire then
        local delay=self.fade_image and 0 or math.max(0,time.to_s(self.hide_due-time.now()))
        UI:scheduleIn(delay,self.expire)
    end
end

function Reply:onCloseWidget()
    self.journal_controls:hide()
    self:resetExpiry()
    Base.onCloseWidget(self)
end

return Reply
