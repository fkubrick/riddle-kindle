package.path = plugin_root .. "/?.lua;" .. package.path
for _, file in ipairs({ "ink/alfred/state.lua", "ink/alfred/transport.lua",
    "ink/alfred/view.lua", "ink/alfred/reply.lua" }) do
    assert(loadfile(plugin_root .. "/" .. file))
end

local State = require("ink/alfred/state")
local Net = require("ink/alfred/transport")
local Json = require("ink/sync/json")
local id = "46c7dc2d-a7f9-442d-9e49-74d4caa1e1bb"
local msg = "c16d5f16-0e78-488a-ac6b-c15e19575b25"
local spont = "2f8fad38-c3e4-4686-bd35-dc391868b80b"

assert(State.uuid(id) and not State.uuid(id:sub(2)) and not State.uuid(id:gsub("442d", "142d")))
assert(not Net.validToken("abc") and not Net.validToken(string.rep("x", 32) .. "\n"))
local strokes = State.capture({ { pts = { -8, -5, 10, 20, 10, 20, 2000, 2000 } } }, 1072, 1448)
assert(State.fits(strokes) and #strokes[1] == 3)
assert(strokes[1][1][1] == 0 and strokes[1][1][2] == 0)
assert(strokes[1][3][1] == 1071 and strokes[1][3][2] == 1447)
assert(State.restore(strokes, 1072, 1448, 3)[1].pts[5] == 1071)
captured_page = Json.encode(State.page(id, strokes))
local draft = State.new()
draft.draft = strokes
local path = os.tmpname()
package.preload["ffi/util"] = function()
    return { fsyncOpenedFile = function() return true end, fsyncDirectory = function() return true end }
end
assert(State.write(path, draft))
assert(State.valid(State.read(path, State.max_state)))
os.remove(path)
assert(not State.valid({version = 1, draft = {}}))

local function interpret(op, expected, code, payload)
    return Net.interpret(op, expected, code, Json.encode(payload))
end
assert(interpret("send", id, 201, { id = id, saved = true }).accepted)
assert(interpret("send", id, 200, { id = id, saved = true }).accepted)
assert(not interpret("send", id, 202, { id = id, saved = true }))
assert(not interpret("send", id, 200, { id = msg, saved = true }))
assert(not interpret("send", id, 200, { id = id, saved = false }))
assert(not Net.interpret("send", id, 200, "invalid JSON"))
assert(interpret("poll", id, 200, { id = id, status = "pending" }).waiting)
assert(not interpret("poll", id, 200, { id = msg, status = "pending" }))
assert(not interpret("poll", id, 200, { id = msg, message_id = msg, status = "ready", text = "Non" }))
assert(not interpret("poll", id, 401, { id = id, message_id = msg, status = "ready", text = "Non" }))
assert(not interpret("poll", id, 200, { id = id, message_id = msg, status = "ready", text = "\0" }))
assert(not interpret("poll", id, 200, { id = id, message_id = msg, status = "ready", text = string.rep("a", 641) }))
assert(interpret("poll", id, 200, { id = id, message_id = msg, status = "ready", text = "À bientôt !" }).reply.text == "À bientôt !")
assert(interpret("poll", nil, 200, { status = "pending" }).waiting)
assert(interpret("poll", nil, 200, { id = msg, message_id = msg, status = "ready", text = "Bonjour" }).reply.id == msg)

-- Run the real session and scheduling code with a controllable clock, canvas,
-- disk, and transport. No Kindle device or outbound requests are simulated.
local now, scheduled, foreground, requests, disk = 0, {}, nil, {}, nil
local UI = {
    scheduleIn = function(_, delay, cb) scheduled[cb] = now + delay end,
    unschedule = function(_, cb) scheduled[cb] = nil end,
    getTopmostVisibleWidget = function() return foreground end,
    show = function(_, widget) widget.previous = foreground; foreground = widget end,
    close = function(_, widget) foreground = widget.previous; widget:onCloseWidget() end,
    setDirty = function() end,
}
local dev = { input = { gesture_detector = { contact_count = 0 } },
    screen = { getWidth = function() return 1072 end, getHeight = function() return 1448 end,
        scaleBySize = function(_, size) return size end }, hasKeys = function() return false end }
local function stub(name, module)
    package.preload[name] = function() return module end
end
stub("ink/view", { extend = function(_, widget) return widget end })
stub("ui/uimanager", UI)
stub("ui/time", { now = function() return now end, s = function(v) return v end, to_s = function(v) return v end })
stub("device", dev)
stub("ui/widget/container/inputcontainer", { extend = function(_, widget)
    function widget:new(o)
        setmetatable(o, { __index = self })
        o:init()
        return o
    end
    return widget
end })
stub("ui/geometry", { new = function(_, o) return o end })
stub("ui/font", { getFace = function(_, _, size) return { size = size } end })
stub("ui/widget/button", { new = function(_, o)
    o.getSize = function() return { w = 96, h = 42 } end
    o.free = function() end
    return o
end })
stub("ui/widget/textboxwidget", { new = function(_, o)
    local line_h = math.floor(o.face.size * (1 + o.line_height))
    local chars_per_line = math.max(1, math.floor(o.width / (o.face.size * 0.5)))
    local all, visible = math.ceil(#o.text / chars_per_line), math.floor(o.height / line_h)
    o.getAllLineCount = function() return all end
    o.getVisLineCount = function() return visible end
    o.getSize = function() return {h = math.min(all, visible) * line_h} end
    o.free = function() end
    return o
end })
for _, dep in ipairs({ "ui/widget/buttontable", "ui/widget/container/centercontainer", "ffi/blitbuffer",
    "ui/widget/infomessage", "ui/widget/textwidget", "ui/widget/verticalgroup" }) do
    stub(dep, {})
end

local View = require("ink/alfred/view")
local Reply = require("ink/alfred/reply")
local groups = Reply.groups("un deux trois quatre cinq six sept huit")
assert(#groups == 4 and groups[1] == "un deux" and groups[3] == "un deux trois quatre cinq six")
local function view(session)
    local v = setmetatable({
        state_path = "mock-disk", token = string.rep("x", 32),
        session = session, canvas = { w = 1072, h = 1448, rev = 0, ops = {},
            setOps = function(self, ops) self.ops, self.rev = ops, self.rev + 1 end },
        recompose = function() end,
    }, { __index = View })
    v:openStartDocument()
    foreground = v
    return v
end
local function advance(t)
    now = t
    local callbacks = {}
    for f, due in pairs(scheduled) do
        if due <= now then callbacks[#callbacks + 1] = f end
    end
    for _, cb in ipairs(callbacks) do
        if scheduled[cb] and scheduled[cb] <= now then scheduled[cb] = nil; cb() end
    end
end
local function addStroke(v)
    v.canvas.ops[#v.canvas.ops + 1] = { kind = "ink", pts = { 20, 130, 35, 145 } }
    v.canvas.rev = v.canvas.rev + 1
    v:markDirty()
end

State.newId = function() return id end
State.write = function(_, data)
    disk = Json.decode(Json.encode(data))
    return true
end
Net.start = function(_, op, arg, cb)
    requests[#requests + 1] = { op = op, arg = arg, cb = cb }
    return function() requests[#requests].cancelled = true end
end

local v = view(State.new())
addStroke(v)
advance(5.9)
assert(#requests == 0 and #disk.draft == 1)
v._raw = { slot = 0 }
advance(6)
assert(#requests == 0)
v._raw.slot = nil
advance(6.1)
addStroke(v)
advance(12.09)
assert(#requests == 0 and #disk.draft == 2)
advance(12.11)
assert(#requests == 1 and requests[1].op == "send" and requests[1].arg.id == id)
assert(disk.pending and not disk.pending.accepted and #disk.pending.page.strokes == 2)
assert(#disk.draft == 0 and #v.canvas.ops == 0)

-- Loss of an HTTP acknowledgement, followed by a restart, repeats the same
-- immutable request with the same UUID instead of creating a duplicate.
requests[1].cb(nil)
v:stopConnector()
v = view(disk)
v:tick()
assert(#requests == 2 and requests[2].op == "send")
assert(Json.encode(requests[2].arg) == Json.encode(requests[1].arg))
requests[2].cb({ accepted = true })
v:stopConnector()
v = view(disk)
v:tick()
assert(#requests == 3 and requests[3].op == "poll" and requests[3].arg == id)

-- A reply arrives during contact, then a different draft is finished. It is
-- never replaced; the response can be opened on demand and writing resumes.
v._raw = { slot = 0 }
requests[3].cb({ reply = { id = id, message_id = msg, text = "Bonjour !" } })
advance(12.11)
assert(foreground == v and disk.reply.message_id == msg and not disk.pending)
v._raw.slot = nil
addStroke(v)
advance(12.12)
assert(foreground == v and #v.canvas.ops == 1 and #disk.draft == 1)
v:showReply(true)
assert(foreground ~= v and foreground.dimen.w == 1072 and foreground.dimen.h == 1448)
assert(foreground.covers_fullscreen and foreground.text == "Bonjour !" and foreground.button.text == "Écrire")
assert(foreground.button_x > 900 and foreground.button_y > 1300 and not foreground.box)
advance(12.73)
assert(foreground.box.text == "Bonjour")
advance(13.34)
assert(foreground.box.text == "Bonjour !")
foreground.button.callback()
assert(foreground == v and #v.canvas.ops == 1 and #disk.draft == 1)
assert(disk.seen == msg and not disk.reply)
v:stopConnector()

-- Leaving an older spontaneous message unread doesn't block the new drawing.
local unread = State.new()
unread.draft = strokes
unread.reply = { id = spont, message_id = spont, text = "Bonjour depuis Alfred" }
v = view(unread)
v:tick()
advance(19.35)
assert(foreground == v and v.session.reply and v.session.pending and #v.canvas.ops == 0)
assert(requests[#requests].op == "send")
v:stopConnector()

v = view(State.new())
v:tick()
local poll = requests[#requests]
assert(poll.op == "poll" and poll.arg == nil)
poll.cb({ reply = { id = spont, message_id = spont, text = "Bonjour depuis Alfred" } })
advance(19.35)
assert(foreground ~= v and foreground.text == "Bonjour depuis Alfred")
advance(24.36)
assert(requests[#requests] ~= poll and requests[#requests].op == "poll")
requests[#requests].cb({ reply = { id = msg, message_id = msg, text = "Autre message Alfred" } })
advance(24.36)
assert(foreground ~= v and foreground.text == "Autre message Alfred")
foreground.button.callback()
assert(foreground == v and #v.canvas.ops == 0 and disk.seen == msg)
advance(29.37)
requests[#requests].cb({ reply = { id = msg, message_id = msg, text = "Autre message Alfred" } })
advance(29.37)
assert(foreground == v and not disk.reply)
v:stopConnector()

print("Alfred LuaJIT checks passed: protocol, files, draft, quiet time, retries, reply and spontaneous inbox")
