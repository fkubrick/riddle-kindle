local Base = require("ink/alfred/view")
local Stylus = require("ink/stylus")
local Geom = require("ui/geometry")
local UI = require("ui/uimanager")
local Screen = require("device").screen
local Idle = require("riddlelocal/idlecontrols")
local Buttons = require("ui/widget/buttontable")
local Widget = require("ui/widget/container/widgetcontainer")
local BB = require("ffi/blitbuffer")
local OnlineState = require("riddlelocal/online_state")
local Canvas = Base:extend{stop_events_propagation = true}

function Canvas:buildToolbar()
    if self.toolbar then self.toolbar:free() end
    self.toolbar = Widget:new{dimen=Geom:new{w=self.screen_w,h=0}}
    self._toolbar_hidden = true
end

function Canvas:updateStatus()
    local error_text
    if self.storage_error then error_text = "Sauvegarde indisponible · Page conservée"
    elseif self.oversize then error_text = "Page trop longue · Page conservée"
    elseif self.session and self.session.outbox and
            OnlineState.size(self.session) >= OnlineState.capacity then
        error_text = "File pleine · Page conservée"
    end
    if error_text and error_text ~= self._shown_error then
        UI:show(require("ui/widget/infomessage"):new{text=error_text})
    end
    self._shown_error = error_text
end

function Canvas:onShow()
    self.journal_awake = self.journal_awake or require("riddlelocal/awake").new(self.kui)
    self.journal_awake:start()
    self.bottom_controls = Buttons:new{width=self.screen_w,buttons={{
        {text="Fermer",callback=function() self:closeCanvas() end},
    }}}
    self.controls_y = Screen:getHeight()-self.bottom_controls:getSize().h
    self.journal_controls = Idle.new(function(visible)
        self[1] = visible and self.bottom_controls or nil
        self._paint_all = true
        if self:top() then
            UI:setDirty(self, "ui", Geom:new{ x = 0, y = self.controls_y, w = self.screen_w, h = Screen:getHeight()-self.controls_y })
        end
    end)
    self[1] = nil
    return Base.onShow(self)
end

function Canvas:fitBars(w, h)
    self._toolbar_hidden = true
    Base.fitBars(self, w, h)
end

function Canvas:inArea(x,y)
    if self.journal_controls and self.journal_controls.visible and y>=self.controls_y then return false end
    return Base.inArea(self,x,y)
end

function Canvas:paintTo(bb,x,y)
    Base.paintTo(self,bb,x,y)
    if self.journal_controls and self.journal_controls.visible then
        bb:paintRect(x,y+self.controls_y,self.screen_w,Screen:getHeight()-self.controls_y,BB.COLOR_WHITE)
        self.bottom_controls:paintTo(bb,x,y+self.controls_y)
    end
end

-- Prevent Ink Away's fallback from handing writing gestures to KOReader.
function Canvas:handBack() return true end

function Canvas:onSetDimensions()
    local result = Base.onSetDimensions(self)
    if self._toolbar_hidden then self[1] = nil end
    return result
end

function Canvas:handleEvent(event)
    local controls = self.journal_controls
    if controls and controls.visible and Idle.isTap(event) then
        controls:show() -- before a child button handles the tap
    end
    return Base.handleEvent(self, event)
end

function Canvas:onIaTap(arg, ges)
    if self._pen_feeding or not self.journal_controls then return Base.onIaTap(self, arg, ges) end
    if self:fingerRejected(ges and ges.pos) then return true end
    -- Gesture fallback if raw input isn't available: cancel a lone touch before it commits.
    if self._finger_dot and not self.pending_lift then self:penDropFingerOps() end
    self.journal_controls:show()
    return true
end

local function tapSlop() return math.max(1, Screen:scaleBySize(4)) end

function Canvas:rawStart()
    local raw = self._raw
    -- Ink Away's short timer can fire while a tap is still down. Wait for movement.
    if raw and raw.wait and raw.len > tapSlop() then
        -- Do not merge the previous letter into a possible navigation gesture.
        if self.session and (self.session.reply or self.session.last_reply) and
                raw.x0 >= self.screen_w * .82 and self.pending_lift then self:flushPending() end
        Base.rawStart(self)
    end
end

function Canvas:rawRelease(handoff, tev)
    local raw = self._raw
    if raw and raw.slot ~= nil and not handoff and tev and tev.id and tev.id < 0 and
            self.session and (self.session.reply or self.session.last_reply) then
        local lifted = Stylus.timevMs(tev.timev)
        local duration = lifted and raw.t0 and lifted - raw.t0
        local dx, dy = raw.x - raw.x0, raw.y - raw.y0
        -- Start at the right edge, to avoid interpreting an ordinary handwritten
        -- horizontal stroke as a gesture and accidentally discarding it.
        if duration and duration >= 0 and duration <= 1600 and raw.x0 >= self.screen_w * .82 and
                dx <= -self.screen_w * .25 and math.abs(dy) <= math.abs(dx) * .5 then
            if raw.wait then self:rawDropWaiting() else self:penDropFingerOps() end
            raw.slot, raw.id, raw.lift_t, raw.ignore_slot, raw.ignore_id = nil,nil,nil,nil,nil
            UI:scheduleIn(0, function()
                if not self.closing and not self.suspended and self:top() then
                    self:flushPending()
                    if self:saveDraft() then self:showReply(true) end
                end
            end)
            return
        end
    end
    if raw and raw.slot ~= nil and raw.wait and not handoff then
        local lifted = tev and Stylus.timevMs(tev.timev)
        local is_tap = raw.len <= tapSlop() and tev and tev.id and tev.id < 0 and
            (not lifted or not raw.t0 or lifted - raw.t0 < 350)
        if not tev or is_tap then
            self:rawDropWaiting()
            raw.slot, raw.id, raw.lift_t = nil, nil, nil
            if is_tap and self.journal_controls and self:top() then self.journal_controls:show() end
            return
        end
        -- Keep deliberate dots possible with a slightly longer press.
        Base.rawStart(self)
    end
    return Base.rawRelease(self, handoff, tev)
end

function Canvas:onSuspend()
    if self.journal_awake then self.journal_awake:stop(true) end
    if self.journal_controls then self.journal_controls:hide() end
    return Base.onSuspend(self)
end

function Canvas:onResume()
    local result = Base.onResume(self)
    if self.journal_awake then self.journal_awake:start() end
    return result
end

function Canvas:onCloseWidget()
    if self.journal_awake then self.journal_awake:stop(false) end
    if self.journal_controls then self.journal_controls:hide() end
    if self.bottom_controls then self.bottom_controls:free(); self.bottom_controls=nil end
    return Base.onCloseWidget(self)
end

return Canvas
