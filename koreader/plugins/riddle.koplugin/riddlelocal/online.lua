local Base = require("riddlelocal/canvas")
local Ink = require("ink/alfred/state")
local State = require("riddlelocal/online_state")
local Net = require("riddlelocal/transport")
local Reply = require("riddlelocal/reply")
local InfoMessage = require("ui/widget/infomessage")
local UI = require("ui/uimanager")
local time = require("ui/time")
local BB = require("ffi/blitbuffer")
local Screen = require("device").screen
local View = Base:extend{}
local QUIET, POLL, RETRY = 5, 5, 15
local MAILBOX = "mailbox"

local function copy(items)
    local result = {}
    for key, value in pairs(items) do result[key] = value end
    return result
end

function View:openStartDocument()
    Base.openStartDocument(self)
    self.hold_draft = #self.session.draft > 0
end

function View:statusText()
    if self.storage_error then return "Sauvegarde indisponible" end
    if self.oversize then return "Page trop longue" end
    if State.size(self.session) >= State.capacity and #self.session.draft > 0 then
        return "File pleine · Page conservée"
    end
    if self.session.reply then return "Réponse disponible" end
    if self.network_error then return "Connexion en attente" end
    for _, item in ipairs(self.session.outbox) do
        if not item.accepted then return "Envoi en attente" end
    end
    if #self.session.outbox > 0 then return "Réponse en attente" end
    return "Écris ici"
end

function View:save(next_state)
    if (next_state.draft ~= self.session.draft and
            not Ink.valid({ version = 1, draft = next_state.draft })) or
            not State.write(self.state_path, next_state) then
        self.storage_error = true
        self:updateStatus()
        return false
    end
    self.storage_error, self.session = false, next_state
    self:updateStatus()
    return true
end

function View:acknowledge(message_id)
    local reply = self.session.reply
    if not reply or reply.message_id ~= message_id then return true end
    local next_state = copy(self.session)
    next_state.last_reply = reply
    next_state.replies = State.array(next_state.replies)
    next_state.reply = table.remove(next_state.replies, 1)
    if reply.id == message_id then next_state.seen = message_id end
    if self:save(next_state) then return true end
    UI:show(InfoMessage:new{ text = "La réponse n’a pas été archivée. Réessaie." })
    return false
end

function View:leaveReply(dialog, write, close_canvas, automatic)
    if write and not self:acknowledge(dialog.message_id) then return end
    if not write then self.dismissed = dialog.message_id end
    self.reply_view = nil
    UI:close(dialog)
    if close_canvas and self:closeCanvas() ~= false then return end
    if self.journal_controls then self.journal_controls:hide() end
    self:installRawFinger()
    self:startEinkDrive()
    self:recompose()
    if write then
        self.quiet_after = time.now() + time.s(QUIET)
        self.reply_after = self.quiet_after
        self.hold_draft = #self.session.draft > 0 and (self.hold_draft or automatic == true)
    end
    self:wake(0)
end

function View:closeCanvas()
    self:flushPending()
    if not self:saveDraft() then return false end
    UI:close(self)
end

function View:animation(snapshot, page_id)
    self:uninstallRawFinger()
    self:stopEinkDrive()
    local dialog
    dialog = require("riddlelocal/animation"):new{
        image = snapshot, ink_y = self.view.area_y, write_label = "Écrire",
        paper_burn = self.paper_burn,
        submission = page_id ~= nil,
        open_menu = function() self.kui.menu:onShowMenu() end,
        leave = function(write, automatic) self:leaveReply(dialog, write, not write, automatic) end,
    }
    dialog.page_id = page_id
    self.reply_view = dialog
    UI:show(dialog)
    return dialog
end

function View:queue()
    local strokes = self.session.draft
    if not Ink.fits(strokes) then
        self.oversize = true
        self:updateStatus()
        return false
    end
    local id = Ink.newId()
    if not id then return false end
    if self.journal_controls then self.journal_controls:hide() end
    local snapshot = BB.new(Screen:getWidth(), Screen:getHeight(), BB.TYPE_BB8)
    snapshot:fill(BB.COLOR_WHITE)
    self._paint_all = true
    self:paintTo(snapshot, 0, 0)
    snapshot:paintRect(0, 0, Screen:getWidth(), self.view.area_y, BB.COLOR_WHITE)

    local next_state = copy(self.session)
    next_state.outbox = State.array(next_state.outbox)
    next_state.outbox[#next_state.outbox + 1] = { page = Ink.page(id, strokes), accepted = false }
    next_state.draft = Ink.emptyStrokes()
    if not self:save(next_state) then
        snapshot:free()
        return false
    end
    self.canvas:setOps({})
    self.last_rev = self.canvas.rev
    self:recompose()
    self:animation(snapshot, id)
    return true
end

function View:showReply(manual)
    local reply = self.session.reply or (manual and self.session.last_reply)
    if not reply or self:busy() then return end
    local dialog = self.reply_view
    if dialog then
        -- A blank waiting screen belongs to the journal, not exclusively to the
        -- last page sent. Older received replies must remain reachable here.
        if dialog.message_id == reply.message_id then return end
    elseif not self:top() or (not manual and (self.dismissed == reply.message_id or
            #self.session.draft > 0 or (self.reply_after and time.now() < self.reply_after))) then
        return
    end
    if manual and not dialog then
        self:flushPending()
        if not self:saveDraft() then return end
    end
    local persistent = reply.id == reply.message_id
    local scene = Reply.scene(reply.text)
    if reply.paths or scene then
        if dialog and not dialog.setReply then
            UI:close(dialog)
            self.reply_view, dialog = nil, nil
        end
        if not dialog then
            local blank = BB.new(Screen:getWidth(), Screen:getHeight(), BB.TYPE_BB8)
            blank:fill(BB.COLOR_WHITE)
            dialog = self:animation(blank)
        end
        dialog:setReply(reply.paths, reply.message_id, reply.effect, reply.block_ends, persistent, scene)
    else
        if dialog and dialog.submission_active then return true end
        if dialog then
            UI:close(dialog)
        else
            self:uninstallRawFinger()
            self:stopEinkDrive()
        end
        dialog = Reply:new{
            message_id = reply.message_id, text = reply.text,
            persistent = persistent,
            open_menu = function() self.kui.menu:onShowMenu() end,
            dismiss = function() self:leaveReply(dialog, false, false) end,
            write = function(automatic) self:leaveReply(dialog, true, false, automatic) end,
        }
        self.reply_view = dialog
        UI:show(dialog)
    end
end

function View:onResume()
    Base.onResume(self)
    if self.reply_view then
        self:uninstallRawFinger()
        self:stopEinkDrive()
    end
end

function View:stopConnector()
    self.request = nil
    Base.stopConnector(self)
end

function View:saveReply(arg, reply)
    if arg and reply.id ~= arg then return false end
    local next_state = copy(self.session)
    if arg then
        next_state.outbox = State.array(next_state.outbox)
        for index, item in ipairs(next_state.outbox) do
            if item.page.id == arg then
                table.remove(next_state.outbox, index)
                break
            end
        end
    end
    local known = next_state.seen == reply.message_id or
        (next_state.last_reply and next_state.last_reply.message_id == reply.message_id) or
        (next_state.reply and next_state.reply.message_id == reply.message_id)
    for _, waiting in ipairs(next_state.replies) do
        if waiting.message_id == reply.message_id then known = true; break end
    end
    if known then return not arg or self:save(next_state) end
    local previous = next_state.reply or next_state.last_reply
    -- A late poll for an older page must not replace a newer server response.
    if previous and previous.timestamp and reply.timestamp and reply.timestamp < previous.timestamp then
        return self:save(next_state)
    end
    if not next_state.reply and State.size(next_state) >= State.capacity then return false end
    if previous and previous.id == previous.message_id then next_state.seen = previous.message_id end
    next_state.reply = reply
    next_state.replies = State.array()
    return self:save(next_state)
end

function View:startRequest(operation, arg)
    local key = operation == "send" and arg.id or (arg or MAILBOX)
    local request = { mailbox = key == MAILBOX }
    self.request_due = self.request_due or {}
    self.request = request
    local function complete(result)
        if self.request ~= request then return end
        self.request, self.cancel_request = nil, nil
        self.network_error = not result
        local saved = true
        if result and result.accepted then
            local next_state = copy(self.session)
            next_state.outbox = State.array(next_state.outbox)
            for index, item in ipairs(next_state.outbox) do
                if item.page.id == key then
                    next_state.outbox[index] = { page = item.page, accepted = true }
                    saved = self:save(next_state)
                    break
                end
            end
        elseif result and result.reply then
            saved = self:saveReply(arg, result.reply)
        end
        if result and saved and result.reply and arg then
            self.request_due[key] = nil
        else
            self.request_due[key] = time.now() + time.s(result and saved and POLL or RETRY)
        end
        self:updateStatus()
        self:wake(0)
    end
    local cancel = Net.start(self.token, operation, arg, complete)
    if self.request ~= request then return end
    if cancel then self.cancel_request = cancel else complete(nil) end
end

function View:markDirty()
    if self.canvas.rev == self.last_rev then return end
    self.hold_draft=false
    self.quiet_after=time.now()+time.s(QUIET)
    self.oversize=false
    self:saveDraft()
    self:wake(QUIET)
end

function View:tick()
    if self.closing or self.suspended then return end
    local top = UI:getTopmostVisibleWidget()
    if top ~= self and top ~= self.reply_view then self:wake(1); return end
    if self:busy() then self:wake(.25); return end
    if not self:saveDraft() then self:wake(RETRY); return end

    local now, next_due = time.now(), nil
    local function schedule(due)
        if not next_due or due < next_due then next_due = due end
    end
    local reserved = self.request and self.request.mailbox and 1 or 0
    if not self.reply_view and not self.hold_draft and #self.session.draft > 0 and not self.oversize and
            State.size(self.session) + reserved < State.capacity then
        local due = self.quiet_after
        if self.queue_due and self.queue_due > due then due = self.queue_due end
        if self.journal_controls and self.journal_controls.visible then
            due = math.max(due, now + time.s(.5))
        end
        if due > now then
            schedule(due)
        elseif not self:queue() and not self.oversize then
            self.queue_due = now + time.s(RETRY)
            schedule(self.queue_due)
        end
    end
    if self:showReply(false) then schedule(now + time.s(.5)) end
    if not self.reply_view and self.session.reply and self.reply_after and self.reply_after > now then
        schedule(self.reply_after)
    end
    if not self.request then
        self.request_due = self.request_due or {}
        local send, poll
        for _, item in ipairs(self.session.outbox) do
            local due = self.request_due[item.page.id] or now
            if due > now then
                schedule(due)
            elseif item.accepted then
                poll = poll or item.page.id
            else
                send = send or item.page
            end
        end
        if send then
            self:startRequest("send", send)
            if not self.request then return end
        elseif poll then
            self:startRequest("poll", poll)
            if not self.request then return end
        elseif #self.session.outbox == 0 and State.size(self.session) < State.capacity then
            local due = self.request_due[MAILBOX] or now
            if due > now then
                schedule(due)
            else
                self:startRequest("poll")
                if not self.request then return end
            end
        end
    end
    if next_due and next_due > now then self:wake(time.to_s(next_due - now)) end
end

function View.open(kui)
    local dir = require("datastorage"):getSettingsDir()
    local config = Ink.read(dir .. "/alfred-ink.json", 4096)
    if type(config) ~= "table" or not require("ink/alfred/transport").configure(config.relay_url) or not require("ink/alfred/transport").validToken(config.token) then
        UI:show(InfoMessage:new{ text = "Alfred n’est pas configuré sur cette liseuse." })
        return
    end
    local path = dir .. "/riddle-online-state.json"
    local session, migrated = State.read(path)
    if not session then
        UI:show(InfoMessage:new{ text = "Le brouillon du journal ne peut pas être ouvert." })
        return
    end
    -- Upgrade the old unread-response queue to the latest-response display.
    if #session.replies > 0 then
        for _, reply in ipairs(session.replies) do
            if not session.reply or not session.reply.timestamp or not reply.timestamp or
                    reply.timestamp >= session.reply.timestamp then session.reply = reply end
        end
        session.replies = State.array()
        if not State.write(path, session) then
            UI:show(InfoMessage:new{ text = "La réponse ne peut pas être sauvegardée. Réessaie." })
            return
        end
    end
    local migration_failed = migrated and not State.write(path, session)
    local view = View:new{
        kui = kui, session = session, state_path = path, token = config.token, storage_error = migration_failed,
        paper_burn = config.paper_burn == true,
    }
    UI:show(view)
    return view
end

return View
