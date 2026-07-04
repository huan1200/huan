-- ============================================================
-- IDE/Config.lua
-- IDE 全局配置与工具函数
-- ============================================================
local M = {}

M.GRID_SIZE = 32
M.SNAP_TO_GRID = true
M.MAX_LAYERS = 8
M.VERSION = "2.0.0"
M.CANVAS_W = 1280
M.CANVAS_H = 720

-- 颜色主题(VS Code 暗色)
M.COLORS = {
    bg = {30, 30, 30, 255},
    toolbar = {50, 50, 51, 255},
    panel = {37, 37, 38, 255},
    panelHeader = {60, 60, 65, 255},
    canvas = {45, 45, 48, 255},
    text = {204, 204, 204, 255},
    textDim = {128, 128, 128, 255},
    accent = {14, 99, 156, 255},
    accentHover = {17, 119, 187, 255},
    success = {76, 175, 80, 255},
    danger = {231, 76, 60, 255},
    warning = {243, 156, 18, 255},
    border = {68, 68, 68, 255},
    selected = {9, 71, 113, 255},
    grid = {60, 60, 65, 100},
    gridMajor = {80, 80, 85, 150},
}

-- 节点编辑器颜色
M.NODE_COLORS = {
    event = {231, 76, 60, 255},
    action = {52, 152, 219, 255},
    condition = {243, 156, 18, 255},
    math = {155, 89, 182, 255},
    variable = {26, 188, 156, 255},
    input = {52, 73, 94, 255},
    flow = {41, 128, 185, 255},
    object = {39, 174, 96, 255},
    string = {142, 68, 173, 255},
    comment = {100, 100, 100, 255},
}

-- 深度拷贝
function M.deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[M.deepcopy(orig_key)] = M.deepcopy(orig_value)
        end
        setmetatable(copy, getmetatable(orig))
    else
        copy = orig
    end
    return copy
end

-- 生成唯一ID
local id_counter = 0
function M.generateId(prefix)
    id_counter = id_counter + 1
    return (prefix or "obj") .. "_" .. id_counter
end

-- 网格对齐
function M.snapToGrid(x, y)
    if not M.SNAP_TO_GRID then return x, y end
    local gs = M.GRID_SIZE
    return math.floor(x / gs + 0.5) * gs, math.floor(y / gs + 0.5) * gs
end

-- 点是否在矩形内
function M.pointInRect(px, py, rx, ry, rw, rh)
    return px >= rx and px <= rx + rw and py >= ry and py <= ry + rh
end

-- 点是否在圆内
function M.pointInCircle(px, py, cx, cy, radius)
    local dx = px - cx
    local dy = py - cy
    return dx * dx + dy * dy <= radius * radius
end

-- 序列化为Lua字符串(简化版)
function M.serialize(obj, indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent)
    if type(obj) == "table" then
        local s = "{\n"
        for k, v in pairs(obj) do
            local key
            if type(k) == "number" then
                key = "[" .. k .. "]"
            else
                key = '["' .. tostring(k) .. '"]'
            end
            s = s .. prefix .. "  " .. key .. " = " .. M.serialize(v, indent + 1) .. ",\n"
        end
        return s .. prefix .. "}"
    elseif type(obj) == "string" then
        return '"' .. obj .. '"'
    elseif type(obj) == "boolean" then
        return obj and "true" or "false"
    elseif obj == nil then
        return "nil"
    else
        return tostring(obj)
    end
end

return M
