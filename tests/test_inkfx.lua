local FX=require('riddlelocal/inkfx')
local function coverage(image)
    local x0,y0,x1,y1=120,180,-1,-1
    for y=0,179 do for x=0,119 do if image.data[y][x]<255 then
        x0,y0,x1,y1=math.min(x0,x),math.min(y0,y),math.max(x1,x),math.max(y1,y)
    end end end
    return x1-x0+1,y1-y0+1
end
local ink=makeImage(120,180)
ink:paintRect(56,60,3,45,0)
local original_w,original_h=coverage(ink)
local plan=FX.prepare(ink,120,180)
local palette={[0]=0,[255]=255}
FX.render(ink,plan,0,palette)
assert(ink.data[70][56]==0 and coverage(ink)==original_w,'phase zero must preserve sharp black ink')
FX.render(ink,plan,.05,palette)
assert(ink:inkCount()>100,'the original stroke should remain mostly intact at the start')
FX.render(ink,plan,.4,palette)
local wet_w,wet_h=coverage(ink)
assert(wet_w>original_w and wet_h>original_h,'ink should spread outside its original strokes')
local core_count=0
for y=60,104 do
    for x=56,58 do
        if ink.data[y][x]==0 then core_count=core_count+1 end
    end
end
assert(core_count>0 and core_count<135,'the original stroke should thin while ink spreads')
local twin=makeImage(120,180); twin:paintRect(56,60,3,45,0)
FX.render(twin,FX.prepare(twin,120,180),.4,palette)
for y=0,179 do for x=0,119 do
    local value=ink.data[y][x]
    assert(value==0 or value==255,'the fast waveform requires black or white pixels')
    assert(twin.data[y][x]==value,'particle field must be deterministic')
end end
FX.render(ink,plan,1,palette)
assert(ink:inkCount()==0)
FX.render(ink,plan,.7,palette)
assert(ink:inkCount()>0,'inverse diffusion should emerge from white')
FX.render(ink,plan,0,palette)
assert(ink.data[70][57]==0 and coverage(ink)==original_w,'inverse diffusion must end on the original sharp ink')

local drops=makeImage(120,180); local drop_state={}
local dirty=FX.waitDrops(drops,120,180,.25,drop_state,palette)
assert(#dirty==#drop_state and #drop_state>=3,'each waiting drop should update its own small region')
assert(drops:inkCount()>0 and drops:inkCount()<120,'waiting drops should remain sparse')
local origins={}
for i,drop in ipairs(drop_state) do
    origins[i]={x=drop.x,y=drop.y,w=drop.w,h=drop.h,gray=drop.gray}
end
local duplicate=makeImage(120,180); local duplicate_state={}
FX.waitDrops(duplicate,120,180,.25,duplicate_state,palette)
assert(#duplicate_state==#origins,'drop count should be deterministic')
for i,drop in ipairs(drop_state) do
    assert(drop.x==duplicate_state[i].x and drop.y==duplicate_state[i].y and drop.gray==duplicate_state[i].gray)
end
for y=0,179 do for x=0,119 do assert(drops.data[y][x]==duplicate.data[y][x],'waiting frame should be deterministic') end end
local paths={{{15,20},{30,35},{45,50}},{{70,80},{90,100},{105,120}}}
local state_copy={}; for i,drop in ipairs(drop_state) do
    state_copy[i]={x=drop.x,y=drop.y,w=drop.w,h=drop.h,gray=drop.gray}
end
assert(FX.gatherDrops(drops,120,180,origins,0,drop_state,palette,paths),'gather start should draw its bounds')
assert(#drop_state==#origins,'gather must preserve the active drop state')
for i,drop in ipairs(drop_state) do assert(drop.x==origins[i].x and drop.y==origins[i].y) end
FX.gatherDrops(drops,120,180,origins,.5,drop_state,palette,paths)
local moved=false
for i,drop in ipairs(drop_state) do
    assert(drop.gray<=origins[i].gray,'gathered drops should darken')
    if drop.x~=origins[i].x or drop.y~=origins[i].y then moved=true end
end
assert(moved,'gather should move drops toward the reply paths')
FX.gatherDrops(drops,120,180,origins,1,drop_state,palette,paths)
assert(#drop_state==#origins,'phase one must leave final drops available to the reveal')
for _,drop in ipairs(drop_state) do assert(drop.gray==0,'phase one drops should arrive as black ink') end
local cleaned=FX.clearDrops(drops,drop_state,palette)
assert(#cleaned==#origins and #drop_state==0 and drops:inkCount()==0,'clearDrops should erase each drop')
