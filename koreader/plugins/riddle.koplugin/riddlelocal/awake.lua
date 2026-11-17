-- Hold idle sleep only for the journal lifetime; never disable the power button.
local UI = require("ui/uimanager")
local Device = require("device")
local Share = require("pluginshare")
local Awake = {}

function Awake.new(kui)
    local self = { autosuspend = kui and kui.autosuspend }
    self.pulse = function()
        if not self.active then return end
        local auto = self.autosuspend
        if auto then
            auto:_unschedule()
            auto:_unschedule_kindle()
        end
        local power = Device:getPowerDevice()
        if Device:isKindle() and not Device.screen_saver_mode and not Share.keepalive and
                not (power:isCharging() and not power:isCharged()) then
            power:resetT1Timeout()
        end
        UI:scheduleIn(300, self.pulse)
    end
    function self:start()
        if self.active then return end
        self.active = true
        UI:preventStandby()
        -- Run after the normal resume handlers, which re-arm the idle timers.
        UI:scheduleIn(0.1, self.pulse)
    end
    function self:stop(manual_suspend)
        if not self.active then return end
        self.active = false
        UI:unschedule(self.pulse)
        UI:allowStandby()
        if not manual_suspend and self.autosuspend then
            self.autosuspend:_start()
            self.autosuspend:_start_kindle()
        end
    end
    return self
end
return Awake
