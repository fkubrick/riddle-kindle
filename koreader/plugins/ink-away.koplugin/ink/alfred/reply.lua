local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UI = require("ui/uimanager")
local Screen = Device.screen

local Reply = InputContainer:extend{ modal = true, covers_fullscreen = true }
-- Font:getFace looks in ./fonts first; address the bundled face from there.
local KALAM = "../plugins/ink-away.koplugin/ink/alfred/fonts/Kalam-Regular.ttf"

function Reply.groups(text)
    local end_at, stages = {}, {}
    for at in text:gmatch("%S+()") do end_at[#end_at + 1] = at - 1 end
    local size = math.max(1, math.ceil(#end_at / 4))
    for i = size, #end_at - 1, size do stages[#stages + 1] = text:sub(1, end_at[i]) end
    stages[#stages + 1] = text
    return stages
end

function Reply:init()
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
    self.button = Button:new{
        text = "Écrire", width = Screen:scaleBySize(96),
        callback = function() self.write(self.message_id) end,
    }
    self[1] = self.button
    self:layout()
    self:replace(self.message_id, self.text)
end

function Reply:layout()
    local w, h = Screen:getWidth(), Screen:getHeight()
    local inset = Screen:scaleBySize(18)
    local bs = self.button:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = w, h = h }
    self.text_rect = Geom:new{ x = inset, y = inset, w = w - 2*inset, h = h - 3*inset - bs.h }
    self.button_x, self.button_y = w - inset - bs.w, h - inset - bs.h
end

function Reply:textBox(text, face)
    return TextBoxWidget:new{
        face = face, text = text, width = self.text_rect.w,
        height = self.text_rect.h, height_adjust = true, alignment = "left",
        line_height = 0.48,
    }
end

function Reply:fit(text)
    local w, h = self.text_rect.w, self.text_rect.h
    local lo, hi, best = 2, math.max(2, math.floor(math.min(w, h) / Screen:scaleBySize(16) * 16))
    while lo <= hi do
        local size = math.floor((lo + hi) / 2)
        local face = Font:getFace(KALAM, size) or Font:getFace("infofont", size)
        local box = self:textBox(text, face)
        local fits = box:getAllLineCount() <= box:getVisLineCount() and box:getSize().h <= h
        box:free()
        if fits then best, lo = face, size + 1 else hi = size - 1 end
    end
    return best or Font:getFace("infofont", 2)
end

function Reply:replace(id, text)
    if self.advance then UI:unschedule(self.advance) end
    if self.box then self.box:free(); self.box = nil end
    self.message_id, self.text = id, text
    local rendered = text:gsub("\r\n?", "\n"):gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n\n\n+", "\n\n")
    self.face = self:fit(rendered)
    local stages = Reply.groups(rendered)
    local step = 0
    self.advance = function()
        step = step + 1
        if self.box then self.box:free() end
        self.box = self:textBox(stages[step], self.face)
        UI:setDirty(self, "ui", self.text_rect)
        if step < #stages then UI:scheduleIn(0.6, self.advance) end
    end
    UI:scheduleIn(0.6, self.advance)
    UI:setDirty(self, "full")
end

function Reply:onShow()
    UI:setDirty(self, "full")
    return true
end

function Reply:onClose()
    self.dismiss()
    return true
end

function Reply:onCloseWidget()
    UI:unschedule(self.advance)
    if self.box then self.box:free(); self.box = nil end
    self.button:free()
end

function Reply:onSetDimensions()
    self:layout()
    self:replace(self.message_id, self.text)
end

function Reply:paintTo(bb, x, y)
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    if self.box then self.box:paintTo(bb, x + self.text_rect.x, y + self.text_rect.y) end
    self.button:paintTo(bb, x + self.button_x, y + self.button_y)
end

return Reply
