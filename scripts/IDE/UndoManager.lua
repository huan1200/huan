-- ============================================================
-- IDE/UndoManager.lua
-- 撤销/重做栈（支持场景和节点操作）
-- ============================================================
local Config = require("IDE.Config")
local UndoManager = {}

UndoManager._undo_stack = {}
UndoManager._redo_stack = {}
UndoManager._max_size = 50
UndoManager._grouping = false
UndoManager._group_buffer = {}

function UndoManager:init()
    self._undo_stack = {}
    self._redo_stack = {}
    self._grouping = false
    self._group_buffer = {}
end

function UndoManager:record(action_type, data)
    local action = {
        type = action_type,
        data = Config.deepcopy(data),
    }
    if self._grouping then
        table.insert(self._group_buffer, action)
        return
    end
    table.insert(self._undo_stack, action)
    if #self._undo_stack > self._max_size then
        table.remove(self._undo_stack, 1)
    end
    self._redo_stack = {}
end

function UndoManager:undo()
    if #self._undo_stack == 0 then return nil end
    local action = table.remove(self._undo_stack)
    table.insert(self._redo_stack, action)
    return action
end

function UndoManager:redo()
    if #self._redo_stack == 0 then return nil end
    local action = table.remove(self._redo_stack)
    table.insert(self._undo_stack, action)
    return action
end

function UndoManager:canUndo()
    return #self._undo_stack > 0
end

function UndoManager:canRedo()
    return #self._redo_stack > 0
end

function UndoManager:clear()
    self._undo_stack = {}
    self._redo_stack = {}
end

return UndoManager
