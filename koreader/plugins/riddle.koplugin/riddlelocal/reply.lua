local Base = require("ink/alfred/reply")
local BB = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local UI = require("ui/uimanager")
local time = require("ui/time")
local Idle = require("riddlelocal/idlecontrols")
local Reply = Base:extend{ disable_double_tap = true }

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
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, BB.COLOR_WHITE)
    if self.box then self.box:paintTo(bb, x + self.text_rect.x, y + self.text_rect.y) end
    if self.journal_controls.visible then self.button:paintTo(bb, x + self.button_x, y + self.button_y) end
end

function Reply:replace(id,text)
    Base.replace(self,id,text)
    if self.expire then UI:unschedule(self.expire) end
    self.expire,self.hide_due=nil,nil
    if self.persistent then return end
    self.hide_due=time.now()+time.s(.6*#Base.groups(text)+30)
    self.expire=function()
        if UI:getTopmostVisibleWidget()~=self then UI:scheduleIn(1,self.expire); return end
        self.write(true)
    end
    UI:scheduleIn(time.to_s(self.hide_due-time.now()),self.expire)
end

function Reply:onSuspend()
    self.journal_controls:hide()
    self.pause_at=time.now()
    if self.expire then UI:unschedule(self.expire) end
end

function Reply:onResume()
    if self.pause_at and self.hide_due then self.hide_due=self.hide_due+time.now()-self.pause_at end
    self.pause_at=nil
    if self.expire then UI:scheduleIn(math.max(0,time.to_s(self.hide_due-time.now())),self.expire) end
end

function Reply:onCloseWidget()
    self.journal_controls:hide()
    if self.expire then UI:unschedule(self.expire) end
    Base.onCloseWidget(self)
end

return Reply
