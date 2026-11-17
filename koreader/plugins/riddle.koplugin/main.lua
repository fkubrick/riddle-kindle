local Widget = require("ui/widget/container/widgetcontainer")
local UI = require("ui/uimanager")
local Plugin = Widget:extend{ name = "riddle", is_doc_only = false }
function Plugin:init() self.ui.menu:registerToMainMenu(self) end
function Plugin:addToMainMenu(items)
    items.riddle_online = { text = "Journal · Alfred", sorting_hint = "tools", keep_menu_open = false,
        callback = function() require("riddlelocal/online").open(self.ui) end }
end
return Plugin
