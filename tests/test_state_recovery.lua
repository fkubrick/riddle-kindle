local Json = require("ink/sync/json")
local Ink = require("ink/alfred/state")
local State = require("riddlelocal/online_state")
local files, rename_ok, sync_ok, syncs = {},true,true,0
local original_open,original_rename = io.open,os.rename
local prior_lfs,prior_fs = package.loaded["libs/libkoreader-lfs"],package.loaded["ffi/util"]
io.open = function(path,mode)
    assert(mode=="rb", "recovery must not truncate any file")
    local raw=files[path]
    if raw==nil then return nil end
    return {read=function(_,limit) return raw:sub(1,limit) end, close=function() return true end}
end
os.rename = function(from,to)
    if not rename_ok then return nil end
    assert(files[from]~=nil)
    files[to],files[from]=files[from],nil
    return true
end
package.loaded["libs/libkoreader-lfs"]={attributes=function(path)
    return files[path]~=nil and {size=#files[path],mode="file"} or nil
end}
package.loaded["ffi/util"]={fsyncDirectory=function()
    syncs=syncs+1; return sync_ok
end}
local path="journal.json"
local strokes=Json.decode('[[[10,20],[12,24]]]')
local page_id="00000000-0000-4000-8000-000000000001"
local message_id="00000000-0000-4000-8000-000000000002"
local session=State.new()
session.draft=strokes
session.outbox[1]={page=Ink.page(page_id,strokes),accepted=true}
session.last_reply={id=page_id,message_id=message_id,text="A saved reply",paths={{{1,1},{3,4}}}}
local raw=Json.encode(session)

-- Empty primary + complete pending state: restore all data, byte for byte.
files={[path]="",[path..".part"]=raw}
local loaded,migrated=State.read(path)
assert(loaded and not migrated and files[path]==raw and not files[path..".part"] and syncs==1)
assert(#loaded.draft==1 and loaded.draft[1][2][2]==24)
assert(loaded.outbox[1].page.id==page_id and loaded.outbox[1].accepted)
assert(loaded.last_reply.message_id==message_id and loaded.last_reply.paths[1][2][2]==4)
assert(State.read(path).last_reply.message_id==message_id and syncs==1)

-- A committed state takes precedence over an uncommitted pending write.
local newer=State.new(); newer.draft=strokes
files={[path]=Json.encode(newer),[path..".part"]=raw}
assert(#State.read(path).outbox==0 and files[path..".part"]==raw and syncs==1)

-- Missing primary + legacy pending state retains the normal migration flag.
local legacy=Ink.new(); legacy.draft=strokes
legacy.pending={page=Ink.page(page_id,strokes),accepted=false}
files={[path..".part"]=Json.encode(legacy)}
loaded,migrated=State.read(path)
assert(loaded.version==2 and migrated and loaded.outbox[1].page.id==page_id)

-- Never replace nonempty invalid content, or create a fresh state over a partial write.
files={[path]="damaged",[path..".part"]=raw}
assert(not State.read(path) and files[path]=="damaged" and files[path..".part"]==raw)
files={[path]="",[path..".part"]="{"}
assert(not State.read(path) and files[path]=="" and files[path..".part"]=="{")
files={[path..".part"]="{"}; assert(not State.read(path))
files={}; assert(#State.read(path).draft==0 and next(files)==nil)

-- Failed promotion retains the recovery file. Failed sync is not reported as success.
files={[path]="",[path..".part"]=raw}; rename_ok=false
assert(not State.read(path) and files[path]=="" and files[path..".part"]==raw)
rename_ok=true; sync_ok=false
assert(not State.read(path) and files[path]==raw)
sync_ok=true; assert(State.read(path).last_reply.message_id==message_id)
io.open,os.rename=original_open,original_rename
package.loaded["libs/libkoreader-lfs"],package.loaded["ffi/util"]=prior_lfs,prior_fs
