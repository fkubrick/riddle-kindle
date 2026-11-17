local State=require("ink/alfred/state")
local Json=require("ink/sync/json")
local Original=require("ink/alfred/transport")
local OnlineState=require("riddlelocal/online_state")
local Net={}
function Net.interpret(id,code,body)
    if type(body)~="string" or #body>262144 or code~=200 then return nil end
    local ok,r=pcall(Json.decode,body)
    if not ok or type(r)~="table" or (id and r.id~=id) then return nil end
    if r.status=="pending" then return {waiting=true} end
    if r.status~="ready" or not State.validReply(r) or (not id and r.id~=r.message_id) then return nil end
    if not id and r.reply_to~=nil then
        return State.uuid(r.reply_to) and {waiting=true} or nil
    end
    local paths=r.paths
    if paths==Json.null then paths=nil end
    if paths~=nil and not OnlineState.validPaths(paths) then return nil end
    if r.effect~=nil and r.effect~="burn" and r.effect~="dissolve" then return nil end
    if r.block_ends~=nil and not OnlineState.validBlocks(paths,r.block_ends) then return nil end
    if r.timestamp~=nil and (type(r.timestamp)~="number" or r.timestamp~=r.timestamp or
            r.timestamp<=0 or r.timestamp==math.huge or r.timestamp%1~=0) then return nil end
    return {reply={id=r.id,message_id=r.message_id,text=r.text,paths=paths,timestamp=r.timestamp,
        effect=r.effect or (not id and "burn" or nil),block_ends=r.block_ends}}
end
function Net.start(token,op,arg,done)
    local origin,host=Original.endpoint()
    if not origin then return nil end
    if op=="send" then return Original.start(token,op,arg,done) end
    if not Original.validToken(token) or (arg and not State.uuid(arg)) then return nil end
    -- Ink Away's bounded, private file worker avoids a pipe deadlock on polylines.
    return require("ink/ocr/job").start(function()
        local Http=require("ink/sync/http")
        Http.TIMEOUT_BLOCK,Http.TIMEOUT_TOTAL=4,8
        Http.MAX_BODY=262144
        local r=Http.request{
            url=origin.."/native/reply-paths"..(arg and ("?id="..arg) or ""),
            hosts={host},method="GET",
            headers={Authorization="Bearer "..token,Accept="application/json"},
        }
        local result=r and Net.interpret(arg,r.code,r.body)
        return result and Json.encode(result) or nil
    end,function(body)
        local ok,result=pcall(Json.decode,body or "")
        done(ok and result or nil)
    end)
end
return Net
