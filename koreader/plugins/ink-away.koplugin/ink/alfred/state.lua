local Json = require("ink/sync/json")

local State = {
    width = 1072, height = 1448, max_strokes = 256, max_points = 20000,
    max_body = 262144, max_text = 640, max_state = 800000,
    max_draft_strokes = 512, max_draft_points = 40000,
}

function State.uuid(id)
    return type(id) == "string" and #id == 36 and
        id:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89aAbB]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

function State.newId()
    local f = io.open("/dev/urandom", "rb")
    if not f then return nil end
    local bytes = f:read(16)
    f:close()
    if not bytes or #bytes ~= 16 then return nil end
    local uuid = {}
    for i = 1, 16 do
        local b = bytes:byte(i)
        if i == 7 then b = 64 + b % 16 end
        if i == 9 then b = 128 + b % 64 end
        if i == 5 or i == 7 or i == 9 or i == 11 then uuid[#uuid + 1] = "-" end
        uuid[#uuid + 1] = string.format("%02x", b)
    end
    return table.concat(uuid)
end

function State.emptyStrokes()
    return setmetatable({}, Json.ARRAY)
end

function State.new()
    return { version = 1, draft = State.emptyStrokes() }
end

function State.page(id, strokes)
    return { version = 1, id = id, width = State.width, height = State.height, strokes = strokes }
end

local function coord(n, size)
    return type(n) == "number" and n >= 0 and n < size and n == math.floor(n)
end

local function validStrokes(strokes, draft)
    if type(strokes) ~= "table" or getmetatable(strokes) ~= Json.ARRAY or
        (#strokes == 0 and not draft) or
        #strokes > (draft and State.max_draft_strokes or State.max_strokes) then return false end
    local points = 0
    for _, stroke in ipairs(strokes) do
        if type(stroke) ~= "table" or #stroke == 0 then return false end
        points = points + #stroke
        if points > (draft and State.max_draft_points or State.max_points) then return false end
        for _, xy in ipairs(stroke) do
            if type(xy) ~= "table" or #xy ~= 2 or
                not coord(xy[1], State.width) or not coord(xy[2], State.height) then return false end
        end
    end
    return true
end

function State.validReply(r)
    return type(r) == "table" and State.uuid(r.id) and State.uuid(r.message_id) and
        type(r.text) == "string" and #r.text <= State.max_text and r.text:find("%S") and
        not r.text:find("[%z\001-\008\011\012\014-\031\127]")
end

function State.valid(s)
    if type(s) ~= "table" or s.version ~= 1 or not validStrokes(s.draft, true) then return false end
    if s.seen ~= nil and not State.uuid(s.seen) then return false end
    if s.reply ~= nil and not State.validReply(s.reply) then return false end
    if s.pending ~= nil then
        if type(s.pending) ~= "table" or type(s.pending.accepted) ~= "boolean" then return false end
        local p = s.pending.page
        if type(p) ~= "table" or p.version ~= 1 or not State.uuid(p.id) or
            p.width ~= State.width or p.height ~= State.height or not validStrokes(p.strokes, false) then return false end
    end
    return true
end

-- Normalized portrait coordinates, independent of the reader's screen scaling.
function State.capture(ops, width, height)
    local strokes = State.emptyStrokes()
    for _, op in ipairs(ops) do
        local stroke = {}
        for i = 1, #op.pts, 2 do
            local x = math.max(0, math.min(State.width - 1, math.floor(op.pts[i] * State.width / width + 0.5)))
            local y = math.max(0, math.min(State.height - 1, math.floor(op.pts[i + 1] * State.height / height + 0.5)))
            local prev = stroke[#stroke]
            if not prev or prev[1] ~= x or prev[2] ~= y then stroke[#stroke + 1] = { x, y } end
        end
        strokes[#strokes + 1] = stroke
    end
    return strokes
end

function State.fits(strokes)
    return validStrokes(strokes, false)
end

function State.restore(strokes, width, height, pen_width)
    local ops = {}
    for _, stroke in ipairs(strokes) do
        local pts = {}
        for _, xy in ipairs(stroke) do
            pts[#pts + 1] = xy[1] * width / State.width
            pts[#pts + 1] = xy[2] * height / State.height
        end
        ops[#ops + 1] = { kind = "ink", style = "solid", alpha = 255, width = pen_width, pts = pts }
    end
    return ops
end

function State.read(path, limit)
    local f = io.open(path, "rb")
    if not f then return nil end
    local raw = f:read(limit + 1)
    f:close()
    if not raw or #raw > limit then return nil end
    local ok, data = pcall(Json.decode, raw)
    return ok and data or nil
end

function State.write(path, data)
    local fs = require("ffi/util")
    local raw = Json.encode(data)
    if #raw > State.max_state then return false end
    local part = path .. ".part"
    local f = io.open(part, "wb")
    if not f then return false end
    local saved = f:write(raw) and f:flush() and fs.fsyncOpenedFile(f)
    local closed = f:close()
    if not (saved and closed and os.rename(part, path)) then
        os.remove(part)
        return false
    end
    fs.fsyncDirectory(path)
    return true
end

return State
