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
local palette={}; for value=0,255,17 do palette[value]=value end
FX.render(ink,plan,.4,palette)
local wet_w,wet_h=coverage(ink)
assert(wet_w>original_w and wet_h>original_h,'ink should spread outside its original strokes')
assert(ink.data[70][57]>0 and ink.data[70][57]<255,'original ink must fade while spreading')
FX.render(ink,plan,1,palette)
assert(ink:inkCount()==0)
FX.render(ink,plan,.7,palette)
assert(ink:inkCount()>0,'inverse diffusion should emerge from white')
FX.render(ink,plan,0,palette)
assert(ink.data[70][57]==0 and coverage(ink)==original_w,'inverse diffusion must end on the original sharp ink')
