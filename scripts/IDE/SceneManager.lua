-- ============================================================
-- IDE/SceneManager.lua
-- 场景管理器：对象CRUD、图层管理、导出为Lua代码
-- ============================================================
local Config = require("IDE.Config")
local EventBus = require("IDE.EventBus")
local UndoManager = require("IDE.UndoManager")

local SceneManager = {}

SceneManager._data = {
    objects = {},
    layers = {},
    selectedId = nil,
    nextId = 1,
}

function SceneManager:init()
    self._data = {
        objects = {},
        layers = {
            {id = "bg", name = "背景层", visible = true, locked = false, objects = {}},
            {id = "game", name = "游戏层", visible = true, locked = false, objects = {}},
            {id = "ui", name = "UI层", visible = true, locked = false, objects = {}},
        },
        selectedId = nil,
        nextId = 1,
        activeLayerIdx = 2,  -- 默认游戏层
    }
end

function SceneManager:createObject(objType, name, x, y, extra)
    local id = Config.generateId("obj")
    local sx, sy = Config.snapToGrid(x, y)
    local obj = {
        id = id,
        type = objType or "sprite",
        name = name or ("对象_" .. self._data.nextId),
        x = sx, y = sy,
        w = (extra and extra.w) or 64,
        h = (extra and extra.h) or 64,
        rotation = 0,
        layer = (extra and extra.layer) or "game",
        visible = true,
        locked = false,
        components = (extra and extra.components) or {},
        meta = (extra and extra.meta) or {},
    }
    self._data.nextId = self._data.nextId + 1
    self._data.objects[id] = obj
    UndoManager:record("create_object", {object = Config.deepcopy(obj)})
    EventBus:emit("scene.object_created", obj)
    return obj
end

function SceneManager:deleteObject(id)
    local obj = self._data.objects[id]
    if not obj then return false end
    UndoManager:record("delete_object", {object = Config.deepcopy(obj)})
    self._data.objects[id] = nil
    if self._data.selectedId == id then
        self._data.selectedId = nil
    end
    EventBus:emit("scene.object_deleted", id)
    return true
end

function SceneManager:updateObject(id, props)
    local obj = self._data.objects[id]
    if not obj then return false end
    local oldProps = {}
    for k, v in pairs(props) do
        oldProps[k] = obj[k]
        obj[k] = v
    end
    UndoManager:record("update_object", {id = id, oldProps = oldProps, newProps = props})
    EventBus:emit("scene.object_updated", id, props)
    return true
end

function SceneManager:moveObject(id, dx, dy)
    local obj = self._data.objects[id]
    if not obj or obj.locked then return false end
    local newX = obj.x + dx
    local newY = obj.y + dy
    if Config.SNAP_TO_GRID then
        newX, newY = Config.snapToGrid(newX, newY)
    end
    obj.x = newX
    obj.y = newY
    EventBus:emit("scene.object_moved", id, newX, newY)
    return true
end

function SceneManager:selectObject(id)
    self._data.selectedId = id
    EventBus:emit("scene.selection_changed", id)
end

function SceneManager:getSelected()
    if self._data.selectedId then
        return self._data.objects[self._data.selectedId]
    end
    return nil
end

function SceneManager:getAllObjects()
    local list = {}
    for _, obj in pairs(self._data.objects) do
        table.insert(list, obj)
    end
    -- 按图层排序
    table.sort(list, function(a, b)
        if a.layer == b.layer then return (a.id < b.id) end
        return a.layer < b.layer
    end)
    return list
end

function SceneManager:getObjectCount()
    local count = 0
    for _ in pairs(self._data.objects) do count = count + 1 end
    return count
end

function SceneManager:getLayers()
    return self._data.layers
end

function SceneManager:addLayer(name)
    if #self._data.layers >= Config.MAX_LAYERS then return nil end
    local layer = {
        id = Config.generateId("layer"),
        name = name or "新图层",
        visible = true,
        locked = false,
    }
    table.insert(self._data.layers, layer)
    EventBus:emit("scene.layer_added", layer)
    return layer
end

-- 点击测试:查找包含(px,py)的对象(x,y为中心点)
function SceneManager:hitTest(px, py)
    local objects = self:getAllObjects()
    -- 逆序遍历(上层优先)
    for i = #objects, 1, -1 do
        local obj = objects[i]
        if obj.visible and not obj.locked then
            local hw = (obj.w or 64) / 2
            local hh = (obj.h or 64) / 2
            if px >= obj.x - hw and px <= obj.x + hw and py >= obj.y - hh and py <= obj.y + hh then
                return obj
            end
        end
    end
    return nil
end

-- 导出为Lua代码
function SceneManager:exportToLua()
    local lines = {}
    table.insert(lines, "-- ============================================")
    table.insert(lines, "-- 场景代码 (由 Visual2D IDE 自动生成)")
    table.insert(lines, "-- ============================================")
    table.insert(lines, "local Scene = {}")
    table.insert(lines, "")
    table.insert(lines, "function Scene:load()")
    local objects = self:getAllObjects()
    for _, obj in ipairs(objects) do
        local varName = obj.name:gsub("[^%w_]", "_")
        table.insert(lines, string.format(
            '    local %s = createNode("%s", %.1f, %.1f, %.1f, %.1f)',
            varName, obj.type, obj.x, obj.y, obj.w, obj.h
        ))
        if obj.rotation ~= 0 then
            table.insert(lines, string.format('    %s:setRotation(%.1f)', varName, obj.rotation))
        end
    end
    table.insert(lines, "end")
    table.insert(lines, "")
    table.insert(lines, "return Scene")
    return table.concat(lines, "\n")
end

-- 序列化(保存用)
function SceneManager:serialize()
    return {
        version = Config.VERSION,
        objects = Config.deepcopy(self._data.objects),
        layers = Config.deepcopy(self._data.layers),
        nextId = self._data.nextId,
    }
end

-- 反序列化(加载用)
function SceneManager:deserialize(data)
    if not data then return false end
    self._data.objects = data.objects or {}
    self._data.layers = data.layers or self._data.layers
    self._data.nextId = data.nextId or 1
    self._data.selectedId = nil
    EventBus:emit("scene.loaded")
    return true
end

-- 通过id获取对象
function SceneManager:getObjectById(id)
    return self._data.objects[id]
end

-- 获取当前活跃图层索引
function SceneManager:getActiveLayerIndex()
    return self._data.activeLayerIdx or 1
end

-- 设置活跃图层
function SceneManager:setActiveLayer(idx)
    if idx >= 1 and idx <= #self._data.layers then
        self._data.activeLayerIdx = idx
        EventBus:emit("scene.active_layer_changed", idx)
    end
end

-- 切换图层可见性
function SceneManager:toggleLayerVisible(idx)
    local layer = self._data.layers[idx]
    if layer then
        layer.visible = not layer.visible
        EventBus:emit("scene.layer_visibility_changed", idx, layer.visible)
        return layer.visible
    end
    return nil
end

-- 切换图层锁定
function SceneManager:toggleLayerLocked(idx)
    local layer = self._data.layers[idx]
    if layer then
        layer.locked = not layer.locked
        EventBus:emit("scene.layer_lock_changed", idx, layer.locked)
        return layer.locked
    end
    return nil
end

-- 重命名图层
function SceneManager:renameLayer(idx, newName)
    local layer = self._data.layers[idx]
    if layer and newName and #newName > 0 then
        layer.name = newName
        EventBus:emit("scene.layer_renamed", idx, newName)
        return true
    end
    return false
end

-- 删除图层(至少保留一个)
function SceneManager:deleteLayer(idx)
    if #self._data.layers <= 1 then return false end
    local layer = self._data.layers[idx]
    if not layer then return false end
    -- 删除该图层上的所有对象
    local toDelete = {}
    for id, obj in pairs(self._data.objects) do
        if obj.layer == layer.id then
            table.insert(toDelete, id)
        end
    end
    for _, id in ipairs(toDelete) do
        self._data.objects[id] = nil
    end
    table.remove(self._data.layers, idx)
    -- 调整活跃图层索引
    if self._data.activeLayerIdx > #self._data.layers then
        self._data.activeLayerIdx = #self._data.layers
    end
    EventBus:emit("scene.layer_deleted", idx)
    return true
end

-- 获取指定图层上的对象数量
function SceneManager:getLayerObjectCount(layerIdx)
    local layer = self._data.layers[layerIdx]
    if not layer then return 0 end
    local count = 0
    for _, obj in pairs(self._data.objects) do
        if obj.layer == layer.id then
            count = count + 1
        end
    end
    return count
end

-- 获取指定图层上的所有对象
function SceneManager:getObjectsByLayer(layerIdx)
    local layer = self._data.layers[layerIdx]
    if not layer then return {} end
    local list = {}
    for _, obj in pairs(self._data.objects) do
        if obj.layer == layer.id then
            table.insert(list, obj)
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

-- 获取图层信息(含对象数)
function SceneManager:getLayerInfo(idx)
    local layer = self._data.layers[idx]
    if not layer then return nil end
    return {
        id = layer.id,
        name = layer.name,
        visible = layer.visible,
        locked = layer.locked,
        objectCount = self:getLayerObjectCount(idx),
    }
end

return SceneManager
