-- ============================================================
-- IDE/EventBus.lua
-- 内部事件总线（发布-订阅模式）
-- ============================================================
local EventBus = {}
EventBus._listeners = {}

function EventBus:on(event, callback)
    self._listeners[event] = self._listeners[event] or {}
    table.insert(self._listeners[event], callback)
    return function()
        self:off(event, callback)
    end
end

function EventBus:off(event, callback)
    if not self._listeners[event] then return end
    for i, cb in ipairs(self._listeners[event]) do
        if cb == callback then
            table.remove(self._listeners[event], i)
            return
        end
    end
end

function EventBus:emit(event, ...)
    if not self._listeners[event] then return end
    for _, cb in ipairs(self._listeners[event]) do
        local ok, err = pcall(cb, ...)
        if not ok then
            print(string.format("[EventBus] 事件 %s 处理错误: %s", event, tostring(err)))
        end
    end
end

function EventBus:clear()
    self._listeners = {}
end

return EventBus
