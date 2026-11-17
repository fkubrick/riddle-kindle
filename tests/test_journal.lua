package.path=riddle_root.."/?.lua;"..package.path
package.loaded["ui/widget/container/widgetcontainer"]={new=function(_,o) return o end}
package.loaded["ui/widget/infomessage"]={new=function(_,o) o.journal_error=true; return o end}
local show_widget=UI.show
UI.show=function(self,widget)
    if widget.journal_error then return end -- acknowledge the error in this controller test
    return show_widget(self,widget)
end
local LiveNet=require("riddlelocal/transport")
local OnlineState=require("riddlelocal/online_state")
local data={status="ready",id=id,message_id=msg,text="Écris à côté",paths={{{36,36},{38,40}}}}
assert(LiveNet.interpret(id,200,Json.encode(data)).reply.paths)
assert(not LiveNet.interpret(spont,200,Json.encode(data)))
data.paths={{{0/0,1}}}; assert(not LiveNet.interpret(id,200,Json.encode(data)))
data.paths={{{1500,1}}}; assert(not LiveNet.interpret(id,200,Json.encode(data)))
data.paths=nil; assert(LiveNet.interpret(id,200,Json.encode(data)).reply.text==data.text)
data.id, data.reply_to = msg, id
assert(LiveNet.interpret(nil,200,Json.encode(data)).waiting)
data.reply_to = nil
assert(LiveNet.interpret(nil,200,Json.encode(data)).reply.message_id==msg)

-- The old draft, queued UUID, acceptance flag and unread paths survive migration.
local legacy = State.new()
legacy.draft = strokes
legacy.pending = { page = State.page(id, strokes), accepted = true }
legacy.seen = spont
legacy.reply = { id = id, message_id = msg, text = "Suite", paths = {{{36,36},{38,40}}} }
local migrated = assert(OnlineState.load(legacy))
assert(migrated.draft == legacy.draft and migrated.reply == legacy.reply and migrated.seen == spont)
assert(migrated.outbox[1] == legacy.pending)
local state_file = os.tmpname()
assert(OnlineState.write(state_file,migrated))
local saved_migration = assert(OnlineState.load(State.read(state_file,OnlineState.max_bytes)))
assert(saved_migration.version == 2 and saved_migration.outbox[1].accepted and
    saved_migration.outbox[1].page.id == id and saved_migration.reply.paths[1][2][2] == 40)
os.remove(state_file)
legacy.reply.paths = Json.null
local text_migration = assert(OnlineState.load(legacy))
assert(text_migration.reply.text == "Suite" and text_migration.reply.paths == nil)

View.extend=function(self,o) return setmetatable(o,{__index=self}) end
Reply.extend=View.extend
LiveNet.start=Net.start
local Online=require("riddlelocal/online")
local buffer={fill=function() end,paintRect=function() end,free=function(self) self.freed=true end}
local BB=package.loaded['ffi/blitbuffer']; BB.new=function() return buffer end
local fail_write = false
OnlineState.write = function(path,state)
    if fail_write then return false end
    return State.write(path,state)
end

local function online(session)
    local o = view(session or OnlineState.new())
    setmetatable(o,{__index=Online})
    o.view = {area_y=80}
    o.paintTo = function() end
    o.installRawFinger,o.uninstallRawFinger = function() end,function() end
    o.startEinkDrive,o.stopEinkDrive = function() end,function() end
    o.flushPending = function() end
    o.animation = function(self,image,page_id)
        if page_id then
            assert(#disk.draft == 0 and disk.outbox[#disk.outbox].page.id == page_id, "saved before absorption")
        end
        local dialog
        dialog = {
            page_id = page_id,
            setReply = function(d,paths,mid) d.message_id,d.paths = mid,paths end,
            onCloseWidget = function() end,
            write = function() self:leaveReply(dialog,true,false) end,
        }
        self.reply_view = dialog
        UI:show(dialog)
        return dialog
    end
    return o
end

local id2 = "0b119788-192f-4de3-a6f6-fcaae082aff3"
local msg2 = "ec5d7523-93d8-49bd-97b2-ff894db95ea7"
local function lastRequest() return requests[#requests] end
local function answer(page, message)
    return {reply={id=page,message_id=message,text="Réponse pour "..page,paths={{{36,36},{38,40}}}}}
end
local o = online()
addStroke(o)
advance(36)
assert(lastRequest().op == "send" and lastRequest().arg.id == id and o.reply_view)
lastRequest().cb({accepted=true})
advance(41)
assert(lastRequest().op == "poll" and lastRequest().arg == id)
local poll_a = lastRequest()
o.reply_view.write() -- Écrire works before a reply and acknowledges nothing.
State.newId = function() return id2 end
addStroke(o)
poll_a.cb({waiting=true})
advance(47)
assert(lastRequest().op == "send" and lastRequest().arg.id == id2 and #disk.outbox == 2)
assert(disk.outbox[1].accepted and not disk.outbox[2].accepted)
local send_b = lastRequest()
send_b.cb(nil)
o:stopConnector()

-- Restart after a lost acknowledgement. The second POST is byte-for-byte equal.
o = online(assert(OnlineState.load(disk)))
o:tick()
assert(lastRequest().op == "send" and Json.encode(lastRequest().arg) == Json.encode(send_b.arg))
lastRequest().cb({accepted=true})
advance(47)
assert(lastRequest().op == "poll" and lastRequest().arg == id)
lastRequest().cb({waiting=true})
advance(52)
assert(lastRequest().op == "poll" and lastRequest().arg == id)
lastRequest().cb({waiting=true})
advance(52)
assert(lastRequest().op == "poll" and lastRequest().arg == id2)
addStroke(o)
lastRequest().cb(answer(id2,msg2))
advance(52)
assert(foreground == o and #disk.draft == 1 and disk.reply.message_id == msg2 and #disk.outbox == 1)

-- A newly received answer replaces the display without an acknowledgement.
o:showReply(true)
assert(o.reply_view.message_id == msg2 and o.reply_view.paths)
advance(57)
assert(lastRequest().op == "poll" and lastRequest().arg == id)
local match_a = lastRequest()
match_a.cb(answer(id2,msg2))
advance(57)
assert(#disk.outbox == 1 and #disk.replies == 0 and o.reply_view.message_id == msg2)
advance(72)
assert(lastRequest().op == "poll" and lastRequest().arg == id)
lastRequest().cb(answer(id,msg))
advance(72)
assert(#disk.outbox == 0 and disk.reply.message_id == msg and #disk.replies == 0)
assert(o.reply_view.message_id == msg and #disk.draft == 1)
o.reply_view.write()
assert(not disk.reply and #disk.replies == 0 and #o.canvas.ops == 1 and #disk.draft == 1)
assert(disk.last_reply.message_id == msg, "the last answer must survive the return to writing")
local restored = assert(OnlineState.load(Json.decode(Json.encode(disk))))
assert(restored.last_reply.message_id == msg and #restored.draft == 1)
o:showReply(true)
assert(o.reply_view and o.reply_view.message_id == msg and #disk.draft == 1)
o.reply_view.write()
assert(disk.last_reply.message_id == msg and #disk.draft == 1 and #o.canvas.ops == 1)
o:stopConnector()

-- A failed save retains the visible draft. A full queue does the same.
o = online()
addStroke(o)
fail_write = true
advance(78)
assert(not o.reply_view and #o.session.draft == 1 and #o.canvas.ops == 1 and o.storage_error)
fail_write = false
o:stopConnector()
local full = OnlineState.new()
for i = 1, OnlineState.capacity do
    full.outbox[i] = { page = State.page(string.format("00000000-0000-4000-8000-%012d",i),strokes), accepted = true }
end
o = online(full)
addStroke(o)
advance(84)
assert(not o.reply_view and #disk.outbox == OnlineState.capacity and #disk.draft == 1 and #o.canvas.ops == 1)
assert(o:statusText() == "File pleine · Page conservée")
o:stopConnector()

local pending = OnlineState.new()
pending.outbox[1] = { page = State.page(id,strokes), accepted=true }
o = online(pending)
o:tick()
local cancelled = lastRequest()
o:stopConnector()
cancelled.cb(answer(id,msg))
assert(o.session == pending and not o.session.reply)
o:tick()
fail_write = true
lastRequest().cb(answer(id,msg))
assert(o.storage_error and o.session == pending and #o.session.outbox == 1)
fail_write = false
advance(99)
assert(lastRequest().op == "poll" and lastRequest().arg == id)
lastRequest().cb(answer(id,msg))
assert(not o.storage_error and #disk.outbox == 0 and disk.reply.message_id == msg)
o:stopConnector()

-- A waiting blank page must not hide an earlier page's received reply.
local waiting = OnlineState.new()
waiting.outbox[1] = { page = State.page(id2,strokes), accepted=true }
waiting.reply = answer(id,msg).reply
o = online(waiting)
assert(o:save(waiting))
local blank = o:animation({},id2)
o:tick()
assert(blank.message_id == msg, "received reply blocked by another page's waiting screen")
assert(#o.session.outbox == 1 and o.session.outbox[1].page.id == id2)
assert(o.session.reply.message_id == msg, "display must not acknowledge the reply")
o:stopConnector()

-- Reading suspends auto-send of the existing draft. A newer answer may replace
-- the displayed answer without altering that draft, and quiet time restarts on return.
o = online()
o.session.last_reply = answer(id,msg).reply
addStroke(o)
o:showReply(true)
assert(o.reply_view.message_id == msg and #disk.draft == 1)
local started = now
advance(started + 7)
assert(#disk.outbox == 0 and #disk.draft == 1 and o.reply_view, "draft sent while reading")
assert(o:saveReply(nil, answer(msg2,msg2).reply))
o:showReply(false)
assert(o.reply_view.message_id == msg2 and #disk.draft == 1 and #o.canvas.ops == 1)
o.reply_view.write()
advance(started + 12)
assert(#disk.outbox == 0 and #disk.draft == 1, "quiet time did not restart after reading")
o:stopConnector()
