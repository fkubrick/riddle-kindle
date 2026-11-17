local UI = require("ui/uimanager")
local Idle = {}
Idle.__index = Idle

function Idle.new(change)
    local controls = setmetatable({ visible = false, change = change }, Idle)
    controls.expire = function() controls:hide() end
    return controls
end

function Idle:show()
    if not self.visible then
        self.visible = true
        self.change(true)
    end
    UI:unschedule(self.expire)
    UI:scheduleIn(5, self.expire)
end

function Idle:hide()
    UI:unschedule(self.expire)
    if self.visible then
        self.visible = false
        self.change(false)
    end
end

function Idle.isTap(event)
    return event.handler == "onGesture" and event.args and event.args[1] and event.args[1].ges == "tap"
end

function Idle.menuSwipe(owner,event,height,open_menu)
    local gesture = event.handler=="onGesture" and event.args and event.args[1]
    if not gesture or not open_menu then return false end
    local start = gesture.start_pos or gesture.pos
    local opens = gesture.ges=="swipe" and gesture.direction=="south" and
        start and start.y<=height*.08 and (gesture.distance or 0)>=height*.12
    if gesture.ges=="pan" then
        owner._menu_start = owner._menu_start or gesture.start_pos
    elseif gesture.ges=="pan_release" then
        start = owner._menu_start
        local finish = gesture.pos
        opens = start and finish and start.y<=height*.08 and finish.y-start.y>=height*.12
            and math.abs(finish.x-start.x)<(finish.y-start.y)*.5
    end
    if gesture.ges=="pan_release" or gesture.ges=="swipe" then owner._menu_start=nil end
    if opens then
        owner.journal_controls:hide()
        open_menu()
        return true
    end
    return false
end

-- KOReader emits a swipe for a quick gesture and pan + pan_release for a slow one.
function Idle.swipe(owner, event, direction, width)
    local gesture = event.handler == "onGesture" and event.args and event.args[1]
    if not gesture then return false end
    if gesture.ges == "swipe" then
        owner._slide_start = nil
        return gesture.direction == direction and (gesture.distance or 0) >= width * .25
    elseif gesture.ges == "pan" then
        owner._slide_start = owner._slide_start or gesture.start_pos
    elseif gesture.ges == "pan_release" then
        local start, finish = owner._slide_start, gesture.pos
        owner._slide_start = nil
        if start and finish then
            local dx, dy = finish.x - start.x, finish.y - start.y
            return ((direction == "east" and dx > 0) or (direction == "west" and dx < 0))
                and math.abs(dx) >= width * .25 and math.abs(dy) <= math.abs(dx) * .5
        end
    end
    return false
end

return Idle
