local InkAway = require("ink/view")
local State = require("ink/alfred/state")
local Net = require("ink/alfred/transport")
local Reply = require("ink/alfred/reply")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local TextWidget = require("ui/widget/textwidget")
local UI = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local time = require("ui/time")
local Device = require("device")
local Screen = Device.screen

local View = InkAway:extend{}
local QUIET, POLL, RETRY = 6, 5, 15

local function noop() end
local function consume() return true end

-- No access to Ink Away's documents, overlays, tool settings, or update check.
View.saveDocument, View.writeLastPage, View.shelfSnapshot = noop, noop, noop
View.setSetting, View.paintBarMarks, View.paintBarIcons = noop, noop, noop
View.fabHit, View.drawFabs = noop, noop
View.onIaPinch, View.onIaSpread, View.onIaTwoPan, View.onIaTwoPanRel = consume, consume, consume, consume
View.onIaTwoTap, View.onIaTwoSwipe, View.keyAction = consume, consume, consume

function View:applyStartupOrientation()
    if self:orientationSupported() and self:orientationClass() ~= "portrait" then
        Screen:setRotationMode(self:rotationForClass("portrait"))
    end
    self.orientation = self:orientationClass()
end

function View:openStartDocument()
    self.pen_style, self.pen_alpha, self.pen_color = "solid", 255, {0, 0, 0}
    self.pen_width = math.max(3, Screen:scaleBySize(3))
    self.hold_straighten, self.pen_pressure, self.palm_reject = false, false, false
    self.grid_on, self.snap_grid, self.snap_angle, self.symmetry = false, false, false, "off"
    self.canvas:setOps(State.restore(self.session.draft, self.canvas.w, self.canvas.h, self.pen_width))
    self.last_rev = self.canvas.rev
    self.quiet_after = time.now() + time.s(QUIET)
    self._library_on_show, self._overview_on_show = nil, nil
    self._tick = function() self:tick() end
end

function View:buildToolbar()
    if self.toolbar then self.toolbar:free() end
    local w = self.screen_w
    self.status_label = TextWidget:new{
        text = self:statusText(), face = Font:getFace("smallinfofont", 17),
        max_width = w - Screen:scaleBySize(16),
    }
    self.controls = ButtonTable:new{
        width = w,
        buttons = { {
            { text = "Fermer", callback = function() self:closeCanvas() end },
            { text = "Annuler", id = "undo", callback = function() self:undo() end },
            { text = "Réponse", id = "reply", enabled = self.session.reply ~= nil,
              callback = function() self:showReply(true) end },
        } },
    }
    self.toolbar = VerticalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{ w = w, h = Screen:scaleBySize(30) },
            self.status_label,
        },
        self.controls,
    }
end

function View:statusText()
    if self.storage_error then return "Alfred · Sauvegarde indisponible" end
    if self.session.reply then return "Alfred · Réponse disponible" end
    if self.oversize then return "Alfred · Page trop longue" end
    if self.network_error then return "Alfred · Connexion en attente" end
    if self.session.pending then
        return self.session.pending.accepted and "Alfred · En attente de réponse" or "Alfred · Envoi de la page"
    end
    return "Alfred · Écris ici"
end

function View:updateStatus()
    local text = self:statusText()
    local ready = self.session.reply ~= nil
    if not self.status_label or (text == self.status_label.text and ready == self._reply_ready) then return end
    self.status_label:setText(text)
    self._reply_ready = ready
    -- The whole header repaint also resets the ink view's chrome-only flag.
    self.controls.button_by_id.reply:enableDisable(ready)
    self._paint_all = true
    UI:setDirty(self, "ui", Geom:new{ x = 0, y = 0, w = self.screen_w, h = self.view.area_y })
end

function View:onShow()
    self:installRawFinger()
    self:startEinkDrive()
    UI:setDirty(self, "full")
    self:wake(0.5)
    return true
end

function View:onCloseWidget()
    self.closing = true
    self:stopConnector()
    if self.reply_view then
        local dialog = self.reply_view
        self.reply_view = nil
        UI:close(dialog)
    end
    InkAway.onCloseWidget(self)
    if self.toolbar then self.toolbar:free(); self.toolbar = nil end
end

function View:onSuspend()
    self.suspended = true
    self:flushPending()
    self:stopConnector()
    InkAway.onSuspend(self)
end

function View:onResume()
    InkAway.onResume(self)
    self.suspended = false
    self.quiet_after = time.now() + time.s(QUIET)
    self:wake(0.5)
end

function View:stopConnector()
    UI:unschedule(self._tick)
    if self.cancel_request then
        self.cancel_request()
        self.cancel_request = nil
    end
end

function View:top()
    return UI:getTopmostVisibleWidget() == self
end

function View:busy()
    local detector = Device.input and Device.input.gesture_detector
    return self.capturing or (self._raw and self._raw.slot ~= nil) or
        (detector and (detector.contact_count or 0) > 0)
end

function View:wake(delay)
    UI:unschedule(self._tick)
    if not self.closing and not self.suspended then UI:scheduleIn(delay or 0, self._tick) end
end

function View:save(next_state)
    if not State.valid(next_state) or not State.write(self.state_path, next_state) then
        self.storage_error = true
        self:updateStatus()
        return false
    end
    self.storage_error = false
    self.session = next_state
    self:updateStatus()
    return true
end

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

function View:markDirty()
    if self.canvas.rev == self.last_rev then return end
    self.quiet_after = time.now() + time.s(QUIET)
    self.oversize = false
    self:saveDraft()
    self:wake(QUIET)
end

function View:saveDraft()
    if self.canvas.rev == self.last_rev then return true end
    local next_state = copy(self.session)
    next_state.draft = State.capture(self.canvas.ops, self.canvas.w, self.canvas.h)
    if not self:save(next_state) then return false end
    self.last_rev = self.canvas.rev
    return true
end

function View:queue()
    local strokes = self.session.draft
    if not State.fits(strokes) then
        self.oversize = true
        self:updateStatus()
        return false
    end
    local id = State.newId()
    if not id then return false end
    local next_state = copy(self.session)
    next_state.pending = { page = State.page(id, strokes), accepted = false }
    next_state.draft = State.emptyStrokes()
    if not self:save(next_state) then return false end
    self.canvas:setOps({})
    self.last_rev = self.canvas.rev
    self:recompose()
    return true
end

function View:startRequest(operation, arg)
    self.cancel_request = Net.start(self.token, operation, arg, function(result)
        self.cancel_request = nil
        local next_state = copy(self.session)
        self.network_error = not result
        if result and result.accepted then
            next_state.pending = { page = arg, accepted = true }
            self:save(next_state)
        elseif result and result.reply and result.reply.message_id ~= next_state.seen and
                (not next_state.reply or result.reply.message_id ~= next_state.reply.message_id) then
            -- A general message could arrive while the user starts a page.
            -- Keep it locally and leave the active canvas visible.
            if arg then next_state.pending = nil end
            next_state.reply = result.reply
            self:save(next_state)
        end
        self:updateStatus()
        local delay = result and POLL or RETRY
        self.network_due = time.now() + time.s(delay)
        if result and result.reply then self:wake(0) else self:wake(delay) end
    end)
    if not self.cancel_request then
        self.network_error = true
        self:updateStatus()
        self.network_due = time.now() + time.s(RETRY)
        self:wake(RETRY)
    end
end

function View:tick()
    if self.closing or self.suspended then return end
    local top = UI:getTopmostVisibleWidget()
    if top ~= self and top ~= self.reply_view then
        self:wake(1)
        return
    end
    if self:busy() then self:wake(0.25); return end
    if not self:saveDraft() then self:wake(RETRY); return end
    if self.session.reply then
        if self.reply_view then
            local r = self.session.reply
            if self.reply_view.message_id ~= r.message_id then self.reply_view:replace(r.message_id, r.text) end
        else
            self:showReply(false)
        end
    end
    if self.cancel_request then return end
    local pending = self.session.pending
    local now = time.now()
    if not self.reply_view and not pending and #self.session.draft > 0 then
        if self.oversize then return end
        if now < self.quiet_after then self:wake(time.to_s(self.quiet_after - now)); return end
        if not self:queue() then
            if not self.oversize then self:wake(RETRY) end
            return
        end
        pending = self.session.pending
        self.network_due = nil
    end
    if self.network_due and now < self.network_due then
        self:wake(time.to_s(self.network_due - now))
        return
    end
    if pending and not pending.accepted then
        self:startRequest("send", pending.page)
    else
        self:startRequest("poll", pending and pending.page.id or nil)
    end
end

function View:showReply(manual)
    local r = self.session.reply
    if not r or self.reply_view or not self:top() or self:busy() then
        if r and self:busy() then self:wake(0.25) end
        return
    end
    if not manual and (self.dismissed == r.message_id or self.session.pending or #self.session.draft > 0 or
            self.canvas.rev ~= self.last_rev) then return end
    local function dismiss()
        local dialog = self.reply_view
        self.reply_view = nil
        self.dismissed = dialog.message_id
        UI:close(dialog)
        self._paint_all = true
        UI:setDirty(self, "full")
        self:wake(0)
    end
    self.reply_view = Reply:new{
        message_id = r.message_id, text = r.text, dismiss = dismiss,
        write = function(message_id)
            local next_state = copy(self.session)
            if not next_state.reply or next_state.reply.message_id ~= message_id then return end
            next_state.seen, next_state.reply = message_id, nil
            if self:save(next_state) then
                dismiss()
                self.quiet_after = time.now() + time.s(QUIET)
            else
                UI:show(InfoMessage:new{ text = "La réponse n’a pas été archivée. Réessaie." })
            end
        end,
    }
    UI:show(self.reply_view)
end

function View.open(kui)
    local dir = require("datastorage"):getSettingsDir()
    local config = State.read(dir .. "/alfred-ink.json", 4096)
    if type(config) ~= "table" or not require("ink/alfred/transport").configure(config.relay_url) or not Net.validToken(config.token) then
        UI:show(InfoMessage:new{ text = "Alfred n’est pas configuré sur cette liseuse." })
        return
    end
    local path = dir .. "/alfred-ink-state.json"
    local session = State.read(path, State.max_state)
    if not session and not require("libs/libkoreader-lfs").attributes(path) then session = State.new() end
    if not State.valid(session) then
        UI:show(InfoMessage:new{ text = "Le brouillon Alfred ne peut pas être ouvert." })
        return
    end
    local view = View:new{ kui = kui, session = session, state_path = path, token = config.token }
    UI:show(view)
    return view
end

return View
