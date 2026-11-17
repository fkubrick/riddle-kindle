local Ink = require("ink/alfred/state")
local Json = require("ink/sync/json")
local State = { capacity = 8 }
State.max_bytes = Ink.max_state + (State.capacity + 1) * Ink.max_body

function State.array(items)
    return setmetatable({ unpack(items or {}) }, Json.ARRAY)
end

function State.new()
    return { version = 2, draft = Ink.emptyStrokes(), outbox = State.array(), replies = State.array() }
end

function State.validPaths(paths)
    if type(paths) ~= "table" or #paths == 0 or #paths > 2500 then return false end
    local count = 0
    for _, stroke in ipairs(paths) do
        if type(stroke) ~= "table" or #stroke == 0 then return false end
        for _, point in ipairs(stroke) do
            count = count + 1
            if count > 20000 or type(point) ~= "table" or #point ~= 2 then return false end
            for i = 1, 2 do
                local value = point[i]
                if type(value) ~= "number" or value ~= value or value < 0 or value > 1448 then return false end
            end
        end
    end
    return true
end

function State.size(session)
    return #session.outbox + #session.replies + (session.reply and 1 or 0)
end

local function readReply(reply)
    if not Ink.validReply(reply) then return nil end
    if reply.paths == Json.null then
        return { id = reply.id, message_id = reply.message_id, text = reply.text }
    end
    if reply.paths ~= nil and not State.validPaths(reply.paths) then return nil end
    return reply
end

function State.load(data)
    if type(data) ~= "table" then return nil end
    if data.version == 1 then
        if not Ink.valid(data) then return nil end
        local reply = data.reply and readReply(data.reply)
        if data.reply and not reply then return nil end
        local migrated = State.new()
        migrated.draft, migrated.seen, migrated.reply = data.draft, data.seen, reply
        migrated.outbox[1] = data.pending
        return migrated
    end
    if data.version ~= 2 or getmetatable(data.outbox) ~= Json.ARRAY or
            getmetatable(data.replies) ~= Json.ARRAY or State.size(data) > State.capacity or
            (not data.reply and #data.replies > 0) or
            not Ink.valid({ version = 1, draft = data.draft, seen = data.seen }) then
        return nil
    end
    local ids, messages = {}, {}
    for _, item in ipairs(data.outbox) do
        if not Ink.valid({ version = 1, draft = Ink.emptyStrokes(), pending = item }) or ids[item.page.id] then
            return nil
        end
        ids[item.page.id] = true
    end
    if data.reply ~= nil then
        local reply = readReply(data.reply)
        if not reply then return nil end
        data.reply = reply
        messages[data.reply.message_id] = true
    end
    if data.last_reply ~= nil then
        local reply = readReply(data.last_reply)
        if not reply then return nil end
        data.last_reply = reply
    end
    for index, item in ipairs(data.replies) do
        local reply = readReply(item)
        if not reply or messages[reply.message_id] then return nil end
        data.replies[index] = reply
        messages[reply.message_id] = true
    end
    return data
end

function State.write(path, data)
    local raw = Json.encode(data)
    if #raw > State.max_bytes then return false end
    local fs = require("ffi/util")
    local part = path .. ".part"
    local file = io.open(part, "wb")
    if not file then return false end
    local saved = file:write(raw) and file:flush() and fs.fsyncOpenedFile(file)
    local closed = file:close()
    if not (saved and closed and os.rename(part, path)) then
        os.remove(part)
        return false
    end
    fs.fsyncDirectory(path)
    return true
end

return State
