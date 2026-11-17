local State = require("ink/alfred/state")
local Json = require("ink/sync/json")
local Net = {}

local HOST, ORIGIN

function Net.configure(origin)
    HOST, ORIGIN = nil, nil
    if type(origin) ~= "string" then return false end
    local host = origin:match("^https://([%w%.%-]+)$")
    if not host or host:sub(1,1)=="." or host:sub(-1)=="." then return false end
    HOST, ORIGIN = host, origin
    return true
end

function Net.endpoint() return ORIGIN, HOST end
local DEADLINE = 12

-- Only normalized, bounded values leave the child; raw HTTP errors and the
-- credential never enter KOReader's UI or logs.
function Net.interpret(operation, id, code, body)
    if type(body) ~= "string" or #body > 16000 then return nil end
    local ok, r = pcall(Json.decode, body)
    if not ok or type(r) ~= "table" then return nil end
    if operation == "send" then
        if (code == 200 or code == 201) and r.id == id and r.saved == true then
            return { accepted = true }
        end
        return nil
    end
    if code ~= 200 or (id and r.id ~= id) then return nil end
    if r.status == "pending" then return { waiting = true } end
    if r.status ~= "ready" or not State.validReply(r) or (not id and r.id ~= r.message_id) then return nil end
    return { reply = { id = r.id, message_id = r.message_id, text = r.text } }
end

local function request(token, operation, arg)
    local Http = require("ink/sync/http")
    -- These defaults are changed in the fork only.
    Http.TIMEOUT_BLOCK, Http.TIMEOUT_TOTAL = 4, 8
    local sending = operation == "send"
    local id = sending and arg.id or arg
    local body = sending and Json.encode(arg) or nil
    if body and #body > State.max_body then return nil end
    local reply = Http.request{
        url = ORIGIN .. (sending and "/native/ink" or "/native/reply" .. (id and ("?id=" .. id) or "")),
        hosts = { HOST }, method = sending and "POST" or "GET", body = body,
        headers = {
            ["Authorization"] = "Bearer " .. token,
            ["Accept"] = "application/json",
            ["Content-Type"] = sending and "application/json" or nil,
        },
    }
    if reply then return Net.interpret(operation, id, reply.code, reply.body) end
end

function Net.validToken(t)
    return type(t) == "string" and #t >= 32 and #t <= 256 and t:match("^[%w_%-%.~/+=]+$") ~= nil
end

function Net.start(token, operation, arg, callback)
    if not ORIGIN or not Net.validToken(token) or (operation == "send" and not State.uuid(arg.id)) or
        (operation == "poll" and arg ~= nil and not State.uuid(arg)) then return nil end
    local fs = require("ffi/util")
    local UI = require("ui/uimanager")
    local time = require("ui/time")
    local ok, pid, fd = pcall(fs.runInSubProcess, function(_, write_fd)
        local worked, result = pcall(request, token, operation, arg)
        local encoded = worked and result and Json.encode(result) or ""
        -- Fit the entire answer in one Linux PIPE_BUF so waiting for exit
        -- before reading cannot deadlock on a full pipe.
        if #encoded <= 4096 then fs.writeToFD(write_fd, encoded, true) end
    end, true, false)
    if not ok or not pid or not fd then return nil end
    local deadline = time.now() + time.s(DEADLINE)
    local cancelled, stopped
    local function poll()
        if fs.isSubProcessDone(pid) then
            local data = fs.readAllFromFD(fd)
            if not cancelled then
                local valid, result = pcall(Json.decode, data)
                callback(valid and result or nil)
            end
        else
            if not stopped and (cancelled or time.now() >= deadline) then
                stopped = true
                fs.terminateSubProcess(pid)
            end
            UI:scheduleIn(0.2, poll)
        end
    end
    UI:scheduleIn(0.2, poll)
    return function() cancelled = true end
end

return Net
