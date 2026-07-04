-- ============================================================
-- IDE/IDEMain.lua
-- 2D 可视化游戏编译器 IDE - 主界面模块
-- 基于 NanoVG 渲染三栏布局 + 工具栏 + 画布
-- ============================================================
local Config = require("IDE.Config")
local EventBus = require("IDE.EventBus")
local UndoManager = require("IDE.UndoManager")
local SceneManager = require("IDE.SceneManager")
local NodeEditor = require("IDE.NodeEditor")
local Console = require("IDE.Console")
local AssetBrowser = require("IDE.AssetBrowser")
local ComponentSystem = require("IDE.ComponentSystem")
local LevelEditor = require("TileMap.LevelEditor")

local M = {}

-- ============================================================
-- 内部状态
-- ============================================================
local vg = nil           -- NanoVG 上下文(外部传入)
local active = false     -- IDE 是否激活
local fontId = -1        -- 字体句柄

-- 画布尺寸(每帧更新)
local screenW, screenH = 1280, 720
local dpr = 1.0

-- 布局常量
local TOOLBAR_H = 36
local LEFT_PANEL_W = 200
local RIGHT_PANEL_W = 250
local BOTTOM_PALETTE_H = 300  -- LevelEditor 底部调色板高度

-- 模式: "level" / "node"
local currentMode = "level"

-- 关卡编辑器实例(外部注入或内部创建)
local levelEditor = nil

-- 画布视图(平移和缩放)
local canvasView = {
    offsetX = 0, offsetY = 0,
    zoom = 1.0,
    dragging = false,
    dragStartX = 0, dragStartY = 0,
    dragStartOX = 0, dragStartOY = 0,
}

-- 鼠标状态
local mouse = { x = 0, y = 0, down = false, button = 0 }

-- 拖拽状态
local dragState = {
    active = false,
    type = nil,       -- "object" | "node" | "connection"
    targetId = nil,
    startX = 0, startY = 0,
    offsetX = 0, offsetY = 0,
}

-- 连线绘制状态
local connectionDraw = {
    active = false,
    fromNodeId = nil,
    fromPortIdx = nil,
    fromIsOutput = true,
    endX = 0, endY = 0,
}

-- 工具栏按钮定义
local toolbarButtons = {
    { id = "new",     label = "新建",  icon = "+" },
    { id = "save",    label = "保存",  icon = "S" },
    { id = "load",    label = "加载",  icon = "L" },
    { id = "compile", label = "编译",  icon = "▶" },
    { id = "sep1",    label = "",      icon = "" },
    { id = "undo",    label = "撤销",  icon = "←" },
    { id = "redo",    label = "重做",  icon = "→" },
    { id = "sep2",    label = "",      icon = "" },
    { id = "level",   label = "关卡",  icon = "🗺" },
    { id = "node",    label = "节点",  icon = "🔗" },
    { id = "sep3",    label = "",      icon = "" },
    { id = "import",  label = "导入",  icon = "📥" },
    { id = "export",  label = "导出",  icon = "📤" },
}

-- 右面板标签页: "properties" | "components" | "console" | "assets"
local rightPanelTab = "properties"
local RIGHT_TAB_H = 26  -- 标签头高度
local rightPanelTabs = {
    { id = "properties",  label = "属性" },
    { id = "components",  label = "组件" },
    { id = "console",     label = "日志" },
    { id = "assets",      label = "资源" },
}

-- 控制台覆盖层
local showConsoleOverlay = false
local consoleOverlayH = 180

-- 编译输出信息
local compileMsg = { text = "", timer = 0, success = true }

-- 属性编辑状态
local propEdit = {
    active = false,       -- 是否正在编辑某属性
    field = nil,          -- 正在编辑的属性字段名 ("name"/"x"/"y"/"w"/"h"/"rotation")
    text = "",            -- 编辑中的文本内容
    cursorPos = 0,        -- 光标位置
    cursorBlink = 0,      -- 光标闪烁计时器
    targetId = nil,       -- 正在编辑的对象ID
}

-- 图层面板交互状态
local layerPanel = {
    scrollOffset = 0,       -- 滚动偏移
    hoveredLayer = -1,      -- 鼠标悬停的图层索引
    hoveredIcon = nil,      -- 鼠标悬停的图标类型 ("eye"/"lock")
    objectListExpanded = true, -- 对象列表是否展开
    hoveredObject = nil,    -- 悬停的对象ID
}

-- 属性面板交互状态
local propPanel = {
    scrollOffset = 0,
    hoveredField = nil,     -- 悬停的属性字段
}

-- 前向声明
local getLevelEditorSelectedObj

-- ============================================================
-- 初始化 / 销毁
-- ============================================================
---@param nvgCtx userdata NanoVG context
---@param opts? table { levelEditor = LevelEditor instance }
function M.Init(nvgCtx, opts)
    vg = nvgCtx
    fontId = nvgCreateFont(vg, "ide-sans", "Fonts/MiSans-Regular.ttf")
    SceneManager:init()
    NodeEditor:init()
    UndoManager:init()
    Console:init()
    AssetBrowser:init()
    -- 接收外部关卡编辑器实例
    if opts and opts.levelEditor then
        levelEditor = opts.levelEditor
    end
    -- 注册控制台回调
    Console:SetFPSCallback(function()
        return string.format("对象: %d | 节点: %d", SceneManager:getObjectCount(), NodeEditor:getNodeCount())
    end)
    print("[IDE] 可视化编译器 IDE Pro 已初始化 (含关卡编辑器+控制台+资源+组件)")
end

--- 设置关卡编辑器实例(可在 Init 后注入)
function M.SetLevelEditor(editor)
    levelEditor = editor
end

--- 获取当前模式
function M.GetMode()
    return currentMode
end

--- 切换到关卡编辑模式
function M.SwitchToLevel()
    currentMode = "level"
    if levelEditor then
        if not levelEditor.active then
            levelEditor:InitImages()
            levelEditor.active = true
        end
    end
end

--- 切换到场景/关卡编辑模式(已合并)
function M.SwitchToScene()
    currentMode = "level"
    if levelEditor then
        if not levelEditor.active then
            levelEditor:InitImages()
            levelEditor.active = true
        end
    end
end

--- 切换到节点编辑模式
function M.SwitchToNode()
    currentMode = "node"
    if levelEditor then levelEditor.active = false end
end

function M.IsActive()
    return active
end

function M.Toggle()
    active = not active
    if active then
        -- 如果当前是关卡模式, 激活关卡编辑器
        if currentMode == "level" and levelEditor then
            levelEditor:InitImages()
            levelEditor.active = true
        end
        print("[IDE] 已打开 - 关卡/节点编辑器")
    else
        -- 关闭IDE时同时关闭关卡编辑器
        if levelEditor and levelEditor.active then
            levelEditor.active = false
        end
        print("[IDE] 已关闭")
    end
    return active
end

-- ============================================================
-- 坐标转换
-- ============================================================
local function screenToCanvas(sx, sy)
    local canvasX = LEFT_PANEL_W
    local canvasY = TOOLBAR_H
    local canvasW = screenW - LEFT_PANEL_W - RIGHT_PANEL_W
    local canvasH = screenH - TOOLBAR_H
    local localX = (sx - canvasX - canvasView.offsetX) / canvasView.zoom
    local localY = (sy - canvasY - canvasView.offsetY) / canvasView.zoom
    return localX, localY
end

local function isInCanvas(sx, sy)
    return sx >= LEFT_PANEL_W and sx < screenW - RIGHT_PANEL_W
       and sy >= TOOLBAR_H and sy < screenH
end

local function isInToolbar(sx, sy)
    return sy >= 0 and sy < TOOLBAR_H
end

local function isInLeftPanel(sx, sy)
    return sx >= 0 and sx < LEFT_PANEL_W and sy >= TOOLBAR_H
end

local function isInRightPanel(sx, sy)
    return sx >= screenW - RIGHT_PANEL_W and sy >= TOOLBAR_H
end

-- ============================================================
-- 工具栏处理
-- ============================================================
local function handleToolbarClick(sx, sy)
    local btnW = 56
    local btnH = 28
    local startX = 8
    local btnY = (TOOLBAR_H - btnH) / 2
    local cx = startX
    for _, btn in ipairs(toolbarButtons) do
        if btn.id:sub(1,3) == "sep" then
            cx = cx + 12
        else
            if sx >= cx and sx < cx + btnW and sy >= btnY and sy < btnY + btnH then
                -- 执行按钮动作
                if btn.id == "new" then
                    SceneManager:init()
                    NodeEditor:init()
                    UndoManager:clear()
                    compileMsg = { text = "新项目已创建", timer = 3, success = true }
                elseif btn.id == "save" then
                    local data = {
                        scene = SceneManager:serialize(),
                        nodes = NodeEditor:serialize(),
                    }
                    local json = Config.serialize(data)
                    -- 保存到文件
                    local f = File:new("IDE_project.json", FILE_WRITE)
                    if f then
                        f:WriteString(json)
                        f:Close()
                        f:Dispose()
                        compileMsg = { text = "项目已保存", timer = 3, success = true }
                    else
                        compileMsg = { text = "保存失败", timer = 3, success = false }
                    end
                elseif btn.id == "load" then
                    if not fileSystem:FileExists("IDE_project.json") then
                        compileMsg = { text = "无保存文件", timer = 3, success = false }
                    else
                    local f = File:new("IDE_project.json", FILE_READ)
                    if f and f:IsOpen() then
                        local content = f:ReadString()
                        f:Close()
                        f:Dispose()
                        -- 简单解析(需cjson支持)
                        local ok, data = pcall(function()
                            local cjson = require("cjson")
                            return cjson.decode(content)
                        end)
                        if ok and data then
                            SceneManager:deserialize(data.scene or {})
                            NodeEditor:deserialize(data.nodes or {})
                            compileMsg = { text = "项目已加载", timer = 3, success = true }
                        else
                            compileMsg = { text = "加载失败:格式错误", timer = 3, success = false }
                        end
                    else
                        compileMsg = { text = "加载失败:无法读取文件", timer = 3, success = false }
                    end
                    end -- fileSystem:FileExists else block
                elseif btn.id == "compile" then
                    local sceneCode = SceneManager:exportToLua()
                    local logicCode = NodeEditor:compileToLua()
                    local output = "-- 自动生成代码 (Visual2D IDE)\n"
                    output = output .. "-- 生成时间: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n"
                    output = output .. "-- ======== 场景创建 ========\n"
                    output = output .. "function CreateScene()\n"
                    output = output .. sceneCode .. "\n"
                    output = output .. "end\n\n"
                    output = output .. "-- ======== 游戏逻辑 ========\n"
                    output = output .. logicCode .. "\n"
                    -- 写出文件
                    local f = File:new("IDE_output.lua", FILE_WRITE)
                    if f then
                        f:WriteString(output)
                        f:Close()
                        f:Dispose()
                        compileMsg = { text = "编译成功! → IDE_output.lua", timer = 5, success = true }
                        print("[IDE] 编译输出:\n" .. output)
                    else
                        compileMsg = { text = "编译失败:无法写入文件", timer = 3, success = false }
                    end
                elseif btn.id == "undo" then
                    UndoManager:undo()
                elseif btn.id == "redo" then
                    UndoManager:redo()
                elseif btn.id == "node" then
                    currentMode = "node"
                    if levelEditor then levelEditor.active = false end
                elseif btn.id == "level" then
                    currentMode = "level"
                    if levelEditor then
                        if not levelEditor.active then
                            levelEditor:InitImages()
                            levelEditor.active = true
                        end
                    end
                elseif btn.id == "import" then
                    if levelEditor and levelEditor.active then
                        levelEditor.showImportDialog = true
                        levelEditor.showExportDialog = false
                        levelEditor.importInput = ""
                        levelEditor.importCursor = 0
                        compileMsg = { text = "输入13位种子代码", timer = 3, success = true }
                    else
                        compileMsg = { text = "请先切换到关卡模式", timer = 3, success = false }
                    end
                elseif btn.id == "export" then
                    if levelEditor and levelEditor.active then
                        levelEditor:ExportSeedCode()
                    else
                        compileMsg = { text = "请先切换到关卡模式", timer = 3, success = false }
                    end
                end
                return true
            end
            cx = cx + btnW + 4
        end
    end
    return false
end

-- ============================================================
-- 输入处理
-- ============================================================
function M.Update(dt, inputSys, deviceDpr)
    if not active then return end
    dpr = deviceDpr or 1.0
    screenW = graphics:GetWidth() / dpr
    screenH = graphics:GetHeight() / dpr

    -- 更新鼠标位置
    mouse.x = inputSys.mousePosition.x / dpr
    mouse.y = inputSys.mousePosition.y / dpr

    -- 编译消息计时
    if compileMsg.timer > 0 then
        compileMsg.timer = compileMsg.timer - dt
    end

    -- 属性编辑光标闪烁
    if propEdit.active then
        propEdit.cursorBlink = propEdit.cursorBlink + dt
    end

    -- 更新悬停状态(左面板 - 图层)
    layerPanel.hoveredLayer = -1
    layerPanel.hoveredIcon = nil
    layerPanel.hoveredObject = nil
    if isInLeftPanel(mouse.x, mouse.y) and (currentMode == "level" or currentMode == "scene") then
        local layers = SceneManager:getLayers()
        local ly = TOOLBAR_H + 28
        local LAYER_ITEM_H = 26
        local EYE_X = LEFT_PANEL_W - 42
        local LOCK_X = LEFT_PANEL_W - 22
        local ICON_SIZE = 14

        for i, layer in ipairs(layers) do
            local itemY = ly + (i - 1) * LAYER_ITEM_H
            if mouse.y >= itemY and mouse.y < itemY + LAYER_ITEM_H then
                layerPanel.hoveredLayer = i
                if mouse.x >= EYE_X and mouse.x < EYE_X + ICON_SIZE then
                    layerPanel.hoveredIcon = "eye"
                elseif mouse.x >= LOCK_X and mouse.x < LOCK_X + ICON_SIZE then
                    layerPanel.hoveredIcon = "lock"
                end
                break
            end
        end

        -- 对象列表悬停
        if layerPanel.objectListExpanded then
            local objListY = ly + #layers * LAYER_ITEM_H + 8 + 24
            local objects = SceneManager:getAllObjects()
            local OBJ_ITEM_H = 20
            for i, obj in ipairs(objects) do
                local oly = objListY + (i - 1) * OBJ_ITEM_H
                if mouse.y >= oly and mouse.y < oly + OBJ_ITEM_H then
                    layerPanel.hoveredObject = obj.id
                    break
                end
            end
        end
    end

    -- 更新悬停状态(右面板 - 属性)
    propPanel.hoveredField = nil
    if isInRightPanel(mouse.x, mouse.y) and (currentMode == "level" or currentMode == "scene") then
        local sel = SceneManager:getSelected()
        if sel then
            local fields = { "name", "type", "x", "y", "w", "h", "rotation", "layer" }
            local editableMap = { name = true, x = true, y = true, w = true, h = true, rotation = true }
            local ly = TOOLBAR_H + 34
            local PROP_H = 26
            local rx = screenW - RIGHT_PANEL_W
            for i, f in ipairs(fields) do
                local itemY = ly + (i - 1) * PROP_H
                if mouse.y >= itemY and mouse.y < itemY + PROP_H and editableMap[f] then
                    if mouse.x >= rx + RIGHT_PANEL_W * 0.4 then
                        propPanel.hoveredField = f
                    end
                    break
                end
            end
        else
            -- LevelEditor 物件悬停检测
            local leObj, leFields = getLevelEditorSelectedObj()
            if leObj and leFields then
                local ly = TOOLBAR_H + 34
                local PROP_H = 26
                local GROUP_H = 20
                local rx = screenW - RIGHT_PANEL_W
                local offsetY = 0
                for i, prop in ipairs(leFields) do
                    if prop.group then
                        offsetY = offsetY + GROUP_H
                    end
                    local itemY = ly + offsetY
                    if mouse.y >= itemY and mouse.y < itemY + PROP_H and prop.editable then
                        if mouse.x >= rx + RIGHT_PANEL_W * 0.4 then
                            propPanel.hoveredField = prop.field
                        end
                        break
                    end
                    offsetY = offsetY + PROP_H
                end
            end
        end
    end

    -- 关卡模式: 委托给 LevelEditor 处理(工具栏区域除外)
    if currentMode == "level" and levelEditor and levelEditor.active then
        levelEditor:Update(dt, inputSys, dpr)
        return
    end

    -- 画布平移(中键拖拽)
    if canvasView.dragging then
        canvasView.offsetX = canvasView.dragStartOX + (mouse.x - canvasView.dragStartX)
        canvasView.offsetY = canvasView.dragStartOY + (mouse.y - canvasView.dragStartY)
    end

    -- 对象/节点拖拽
    if dragState.active and isInCanvas(mouse.x, mouse.y) then
        local cx, cy = screenToCanvas(mouse.x, mouse.y)
        if currentMode == "scene" and dragState.type == "object" then
            local dx = cx - dragState.startX
            local dy = cy - dragState.startY
            local obj = SceneManager:getObjectById(dragState.targetId)
            if obj then
                obj.x = dragState.offsetX + dx
                obj.y = dragState.offsetY + dy
                if Config.SNAP_TO_GRID then
                    obj.x = Config.snapToGrid(obj.x)
                    obj.y = Config.snapToGrid(obj.y)
                end
            end
        elseif currentMode == "node" and dragState.type == "node" then
            local dx = cx - dragState.startX
            local dy = cy - dragState.startY
            local node = NodeEditor:getNodeById(dragState.targetId)
            if node then
                node.x = dragState.offsetX + dx
                node.y = dragState.offsetY + dy
            end
        end
    end

    -- 连线绘制跟随鼠标
    if connectionDraw.active then
        connectionDraw.endX, connectionDraw.endY = screenToCanvas(mouse.x, mouse.y)
    end
end

function M.HandleMouseDown(button)
    if not active then return false end
    mouse.down = true
    mouse.button = button

    local sx, sy = mouse.x, mouse.y

    -- 工具栏点击(所有模式共用)
    if isInToolbar(sx, sy) then
        return handleToolbarClick(sx, sy)
    end

    -- 关卡模式: 右面板/左面板点击优先，但底部工具栏区域交给 LevelEditor
    if currentMode == "level" and levelEditor and levelEditor.active then
        local dpr = graphics:GetDPR()
        local logH = graphics:GetHeight() / dpr
        local inBottomBar = (sy >= logH - 300)  -- LevelEditor TOOLBAR_H = 300
        if not inBottomBar and isInRightPanel(sx, sy) then
            handleRightPanelClick(sx, sy)
            return true
        end
        if not inBottomBar and isInLeftPanel(sx, sy) then
            if propEdit.active then confirmPropertyEdit() end
            handleLeftPanelClick(sx, sy)
            return true
        end
        levelEditor:HandleMouseDown(button)
        -- 选中物件后自动切换到属性Tab
        if button == MOUSEB_LEFT then
            local hasSelection = false
            if levelEditor.selectedType == "object" and levelEditor.selectedIdx then
                hasSelection = true
            elseif levelEditor.editSelected and levelEditor.editSelected.type == "object" and levelEditor.editSelected.idx then
                hasSelection = true
            end
            if hasSelection then
                rightPanelTab = "properties"
            end
        end
        return true
    end

    -- 画布区域
    if isInCanvas(sx, sy) then
        -- 如果正在编辑属性,先确认
        if propEdit.active then confirmPropertyEdit() end

        local cx, cy = screenToCanvas(sx, sy)

        -- 中键: 开始平移画布
        if button == MOUSEB_MIDDLE then
            canvasView.dragging = true
            canvasView.dragStartX = sx
            canvasView.dragStartY = sy
            canvasView.dragStartOX = canvasView.offsetX
            canvasView.dragStartOY = canvasView.offsetY
            return true
        end

        -- 左键
        if button == MOUSEB_LEFT then
            if currentMode == "scene" then
                local hitObj = SceneManager:hitTest(cx, cy)
                if hitObj then
                    SceneManager:selectObject(hitObj.id)
                    dragState = {
                        active = true,
                        type = "object",
                        targetId = hitObj.id,
                        startX = cx, startY = cy,
                        offsetX = hitObj.x, offsetY = hitObj.y,
                    }
                else
                    SceneManager:selectObject(nil)
                end
            elseif currentMode == "node" then
                -- 检测端口点击(开始连线)
                local portHit = NodeEditor:hitTestPort(cx, cy)
                if portHit then
                    connectionDraw = {
                        active = true,
                        fromNodeId = portHit.nodeId,
                        fromPortIdx = portHit.portIdx,
                        fromIsOutput = portHit.isOutput,
                        endX = cx, endY = cy,
                    }
                else
                    local hitNode = NodeEditor:hitTestNode(cx, cy)
                    if hitNode then
                        NodeEditor:selectNode(hitNode.id)
                        dragState = {
                            active = true,
                            type = "node",
                            targetId = hitNode.id,
                            startX = cx, startY = cy,
                            offsetX = hitNode.x, offsetY = hitNode.y,
                        }
                    else
                        NodeEditor:selectNode(nil)
                    end
                end
            end
            return true
        end

        -- 右键: 场景模式添加对象 / 节点模式弹出菜单(简化为添加节点)
        if button == MOUSEB_RIGHT then
            if currentMode == "scene" then
                SceneManager:createObject("sprite", nil, cx, cy)
            end
            -- 节点模式右键暂不实现弹出菜单
            return true
        end
    end

    -- 左面板点击
    if isInLeftPanel(sx, sy) then
        -- 如果正在编辑属性,先确认
        if propEdit.active then confirmPropertyEdit() end
        handleLeftPanelClick(sx, sy)
        return true
    end

    -- 右面板点击
    if isInRightPanel(sx, sy) then
        handleRightPanelClick(sx, sy)
        return true
    end

    return true  -- IDE激活时消耗所有鼠标事件
end

function M.HandleMouseUp(button)
    if not active then return false end
    mouse.down = false

    -- 关卡模式: 委托给 LevelEditor
    if currentMode == "level" and levelEditor and levelEditor.active then
        levelEditor:HandleMouseUp(button)
        return true
    end

    -- 结束画布平移
    if button == MOUSEB_MIDDLE then
        canvasView.dragging = false
    end

    -- 结束拖拽(记录undo)
    if button == MOUSEB_LEFT and dragState.active then
        if dragState.type == "object" then
            local obj = SceneManager:getObjectById(dragState.targetId)
            if obj and (obj.x ~= dragState.offsetX or obj.y ~= dragState.offsetY) then
                UndoManager:record("move_object", {
                    id = obj.id,
                    fromX = dragState.offsetX, fromY = dragState.offsetY,
                    toX = obj.x, toY = obj.y,
                })
            end
        end
        dragState = { active = false, type = nil, targetId = nil, startX = 0, startY = 0, offsetX = 0, offsetY = 0 }
    end

    -- 结束连线
    if button == MOUSEB_LEFT and connectionDraw.active then
        local cx, cy = screenToCanvas(mouse.x, mouse.y)
        local portHit = NodeEditor:hitTestPort(cx, cy)
        if portHit and portHit.nodeId ~= connectionDraw.fromNodeId then
            -- 创建连接
            if connectionDraw.fromIsOutput then
                NodeEditor:connect(
                    connectionDraw.fromNodeId, connectionDraw.fromPortIdx,
                    portHit.nodeId, portHit.portIdx
                )
            else
                NodeEditor:connect(
                    portHit.nodeId, portHit.portIdx,
                    connectionDraw.fromNodeId, connectionDraw.fromPortIdx
                )
            end
        end
        connectionDraw = { active = false, fromNodeId = nil, fromPortIdx = nil, fromIsOutput = true, endX = 0, endY = 0 }
    end

    return true
end

function M.HandleKeyDown(key)
    if not active then return false end

    -- 属性编辑模式: 优先处理编辑按键
    if propEdit.active then
        if key == KEY_RETURN or key == KEY_KP_ENTER then
            confirmPropertyEdit()
            return true
        elseif key == KEY_ESCAPE then
            cancelPropertyEdit()
            return true
        elseif key == KEY_BACKSPACE then
            if propEdit.cursorPos > 0 then
                local before = propEdit.text:sub(1, propEdit.cursorPos - 1)
                local after = propEdit.text:sub(propEdit.cursorPos + 1)
                propEdit.text = before .. after
                propEdit.cursorPos = propEdit.cursorPos - 1
                propEdit.cursorBlink = 0
            end
            return true
        elseif key == KEY_DELETE then
            if propEdit.cursorPos < #propEdit.text then
                local before = propEdit.text:sub(1, propEdit.cursorPos)
                local after = propEdit.text:sub(propEdit.cursorPos + 2)
                propEdit.text = before .. after
                propEdit.cursorBlink = 0
            end
            return true
        elseif key == KEY_LEFT then
            if propEdit.cursorPos > 0 then
                propEdit.cursorPos = propEdit.cursorPos - 1
                propEdit.cursorBlink = 0
            end
            return true
        elseif key == KEY_RIGHT then
            if propEdit.cursorPos < #propEdit.text then
                propEdit.cursorPos = propEdit.cursorPos + 1
                propEdit.cursorBlink = 0
            end
            return true
        elseif key == KEY_HOME then
            propEdit.cursorPos = 0
            propEdit.cursorBlink = 0
            return true
        elseif key == KEY_END then
            propEdit.cursorPos = #propEdit.text
            propEdit.cursorBlink = 0
            return true
        end
        -- 其他按键在编辑模式下直接消费
        return true
    end

    -- 控制台输入模式
    if showConsoleOverlay and Console:IsVisible() then
        if key == KEY_RETURN or key == KEY_KP_ENTER then
            Console:ExecuteCommand(Console._input_text)
            Console._input_text = ""
            return true
        elseif key == KEY_ESCAPE then
            showConsoleOverlay = false
            Console._visible = false
            return true
        elseif key == KEY_BACKSPACE then
            Console._input_text = Console._input_text:sub(1, -2)
            return true
        elseif key == KEY_UP then
            local hist = Console:HistoryUp()
            if hist then Console._input_text = hist end
            return true
        elseif key == KEY_DOWN then
            local hist = Console:HistoryDown()
            if hist ~= nil then Console._input_text = hist end
            return true
        end
        return true
    end

    -- F7: 切换控制台覆盖层
    if key == KEY_F7 then
        showConsoleOverlay = not showConsoleOverlay
        Console._visible = showConsoleOverlay
        return true
    end

    -- F5: 切换右面板标签
    if key == KEY_F5 then
        local tabs = {"properties", "components", "console", "assets"}
        for i, t in ipairs(tabs) do
            if rightPanelTab == t then
                rightPanelTab = tabs[(i % #tabs) + 1]
                break
            end
        end
        return true
    end

    -- 关卡模式: 委托给 LevelEditor (但Tab切模式由IDE处理)
    if currentMode == "level" and levelEditor and levelEditor.active then
        -- Tab切模式由IDE自己处理
        if key == KEY_TAB then
            currentMode = "node"
            levelEditor.active = false
            return true
        end
        return levelEditor:HandleKeyDown(key)
    end

    -- Delete: 删除选中
    if key == KEY_DELETE or key == KEY_BACKSPACE then
        if currentMode == "scene" then
            local sel = SceneManager:getSelected()
            if sel then SceneManager:deleteObject(sel.id) end
        elseif currentMode == "node" then
            local sel = NodeEditor:getSelectedNode()
            if sel then NodeEditor:deleteNode(sel.id) end
        end
        return true
    end

    -- Ctrl+Z: 撤销
    if key == KEY_Z and input:GetQualifierDown(QUAL_CTRL) then
        if input:GetQualifierDown(QUAL_SHIFT) then
            UndoManager:redo()
        else
            UndoManager:undo()
        end
        return true
    end

    -- Tab: 切换模式 (level ↔ node)
    if key == KEY_TAB then
        if currentMode == "node" then
            currentMode = "level"
            if levelEditor then
                levelEditor:InitImages()
                levelEditor.active = true
            end
        else
            currentMode = "node"
            if levelEditor then levelEditor.active = false end
        end
        return true
    end

    -- 1-6: 在节点模式下快速创建节点
    if currentMode == "node" then
        local nodeTypes = { "Event_Start", "Event_Tick", "Action_Log", "Condition_If", "Math_Add", "Variable_Get" }
        local idx = key - KEY_1 + 1
        if idx >= 1 and idx <= #nodeTypes then
            local cx, cy = screenToCanvas(screenW / 2, screenH / 2)
            NodeEditor:createNode(nodeTypes[idx], cx, cy)
            return true
        end
    end

    return false
end

function M.HandleMouseWheel(wheel)
    if not active then return false end

    -- 关卡模式: LevelEditor 内部通过 inputRef.mouseMoveWheel 处理缩放
    if currentMode == "level" and levelEditor and levelEditor.active then
        -- LevelEditor 在 Update 中读取 mouseMoveWheel, 这里无需额外处理
        return true
    end

    if isInCanvas(mouse.x, mouse.y) then
        local oldZoom = canvasView.zoom
        local zoomFactor = (wheel > 0) and 1.1 or (1.0 / 1.1)
        canvasView.zoom = math.max(0.25, math.min(4.0, canvasView.zoom * zoomFactor))
        -- 缩放到鼠标位置
        local realFactor = canvasView.zoom / oldZoom
        local cx = mouse.x - LEFT_PANEL_W
        local cy = mouse.y - TOOLBAR_H
        canvasView.offsetX = cx - (cx - canvasView.offsetX) * realFactor
        canvasView.offsetY = cy - (cy - canvasView.offsetY) * realFactor
        return true
    end
    return false
end

function M.HandleTextInput(text)
    if not active then return false end

    -- 控制台输入模式: 接收文本输入
    if showConsoleOverlay and Console:IsVisible() then
        Console._input_text = (Console._input_text or "") .. text
        return true
    end

    -- 属性编辑模式: 接收文本输入
    if propEdit.active then
        -- 数值字段过滤: 只允许数字、小数点、负号
        local numericFields = { x=true, y=true, z=true, w=true, h=true, rotation=true,
            size=true, height=true, branches=true, twist=true, seed=true, variant=true, angle=true }
        if numericFields[propEdit.field] then
            -- 只保留合法字符
            local filtered = text:gsub("[^%d%.%-]", "")
            if #filtered == 0 then return true end
            text = filtered
        end
        -- 插入字符到光标位置
        local before = propEdit.text:sub(1, propEdit.cursorPos)
        local after = propEdit.text:sub(propEdit.cursorPos + 1)
        propEdit.text = before .. text .. after
        propEdit.cursorPos = propEdit.cursorPos + #text
        propEdit.cursorBlink = 0
        return true
    end

    -- 关卡模式: 委托给 LevelEditor (导入对话框数字输入)
    if currentMode == "level" and levelEditor and levelEditor.active then
        return levelEditor:HandleTextInput(text)
    end
    return false
end

-- ============================================================
-- 左面板交互
-- ============================================================
function handleLeftPanelClick(sx, sy)
    local x, baseY = 0, TOOLBAR_H
    local w = LEFT_PANEL_W

    if currentMode == "level" or currentMode == "scene" then
        -- 图层列表区域
        local layers = SceneManager:getLayers()
        local ly = baseY + 28
        local LAYER_ITEM_H = 26
        local ICON_SIZE = 14
        local EYE_X = x + w - 42
        local LOCK_X = x + w - 22

        for i, layer in ipairs(layers) do
            local itemY = ly + (i - 1) * LAYER_ITEM_H
            if sy >= itemY and sy < itemY + LAYER_ITEM_H then
                -- 判断点击区域
                if sx >= EYE_X and sx < EYE_X + ICON_SIZE then
                    -- 点击眼睛图标: 切换可见性
                    SceneManager:toggleLayerVisible(i)
                elseif sx >= LOCK_X and sx < LOCK_X + ICON_SIZE then
                    -- 点击锁图标: 切换锁定
                    SceneManager:toggleLayerLocked(i)
                else
                    -- 点击其他区域: 选中图层
                    SceneManager:setActiveLayer(i)
                end
                return
            end
        end

        -- 对象列表标题点击(展开/折叠)
        local objListY = ly + #layers * LAYER_ITEM_H + 8
        if sy >= objListY and sy < objListY + 22 then
            layerPanel.objectListExpanded = not layerPanel.objectListExpanded
            return
        end

        -- 对象列表项点击(选中对象)
        if layerPanel.objectListExpanded then
            local oly = objListY + 24
            local objects = SceneManager:getAllObjects()
            local OBJ_ITEM_H = 20
            for i, obj in ipairs(objects) do
                if sy >= oly and sy < oly + OBJ_ITEM_H then
                    SceneManager:selectObject(obj.id)
                    return
                end
                oly = oly + OBJ_ITEM_H
            end
        end
    elseif currentMode == "node" then
        -- 节点类型面板: 点击创建
        local y = baseY + 30
        local categories = NodeEditor:getCategories()
        for catName, types in pairs(categories) do
            y = y + 22  -- 分类标题
            for _, typeName in ipairs(types) do
                if sy >= y and sy < y + 20 then
                    local cx, cy2 = screenToCanvas(screenW / 2, screenH / 2)
                    NodeEditor:createNode(typeName, cx, cy2)
                    return
                end
                y = y + 20
            end
        end
    end
end

-- ============================================================
-- 右面板交互
-- ============================================================
function handleRightPanelClick(sx, sy)
    -- 点击右面板任何位置先确认当前编辑
    if propEdit.active then confirmPropertyEdit() end

    local x = screenW - RIGHT_PANEL_W
    local w = RIGHT_PANEL_W

    -- 标签页头点击检测
    local tabY = TOOLBAR_H
    if sy >= tabY and sy < tabY + RIGHT_TAB_H then
        local tabW = w / #rightPanelTabs
        for i, tab in ipairs(rightPanelTabs) do
            local tx = x + (i - 1) * tabW
            if sx >= tx and sx < tx + tabW then
                rightPanelTab = tab.id
                return
            end
        end
        return
    end

    -- 内容区起始位置(标签头后)
    local ly = TOOLBAR_H + RIGHT_TAB_H + 8

    -- 组件标签页: 点击添加组件
    if rightPanelTab == "components" then
        local sel = SceneManager:getSelected()
        if sel then
            -- 简化: 点击 "+" 行触发 AddComponent
            local categories = ComponentSystem:GetTypesByCategory()
            local ITEM_H = 22
            local checkY = ly + 22  -- 跳过已挂载标题
            local existingComps = sel.components or {}
            checkY = checkY + #existingComps * ITEM_H + 6 + 22 -- 跳过已有+添加标题

            for catName, types in pairs(categories) do
                checkY = checkY + 18  -- 分类标题
                for _, typeName in ipairs(types) do
                    if sy >= checkY and sy < checkY + ITEM_H then
                        ComponentSystem:AddComponent(sel, typeName)
                        return
                    end
                    checkY = checkY + ITEM_H
                end
            end
        end
        return
    end

    -- 属性标签页原逻辑
    if rightPanelTab ~= "properties" then return end

    if currentMode == "level" or currentMode == "scene" then
        local sel = SceneManager:getSelected()
        if sel then
            -- SceneManager 对象属性编辑
            local fields = {
                { field = "name",     label = "名称",   editable = true },
                { field = "type",     label = "类型",   editable = false },
                { field = "x",        label = "X",      editable = true },
                { field = "y",        label = "Y",      editable = true },
                { field = "w",        label = "宽度",   editable = true },
                { field = "h",        label = "高度",   editable = true },
                { field = "rotation", label = "旋转",   editable = true },
                { field = "layer",    label = "图层",   editable = false },
            }
            local PROP_H = 26
            for i, prop in ipairs(fields) do
                local itemY = ly + (i - 1) * PROP_H
                if sy >= itemY and sy < itemY + PROP_H and prop.editable then
                    if sx >= x + w * 0.4 then
                        startPropertyEdit(sel, prop.field)
                        return
                    end
                end
            end
        else
            -- LevelEditor 物件属性编辑
            local leObj, leFields = getLevelEditorSelectedObj()
            if leObj and leFields then
                local PROP_H = 26
                local GROUP_H = 20
                local offsetY = 0
                for i, prop in ipairs(leFields) do
                    if prop.group then
                        offsetY = offsetY + GROUP_H
                    end
                    local itemY = ly + offsetY
                    if sy >= itemY and sy < itemY + PROP_H and prop.editable then
                        if sx >= x + w * 0.4 then
                            startPropertyEdit(leObj, prop.field)
                            return
                        end
                    end
                    offsetY = offsetY + PROP_H
                end
            end
            return
        end
    elseif currentMode == "node" then
        local sel = NodeEditor:getSelectedNode()
        if not sel then return end
        -- 节点属性暂不支持编辑
    end
end

--- 开始编辑属性
function startPropertyEdit(obj, field)
    local value = obj[field]
    if value == nil then value = "" end
    propEdit.active = true
    propEdit.field = field
    -- LevelEditor 物件没有 id，使用特殊标记
    propEdit.targetId = obj.id or "le_obj"
    propEdit.cursorBlink = 0

    -- 将值转为字符串
    if type(value) == "number" then
        propEdit.text = string.format("%.2f", value)
        -- 去除多余的尾零
        propEdit.text = propEdit.text:gsub("%.?0+$", "")
    else
        propEdit.text = tostring(value)
    end
    propEdit.cursorPos = #propEdit.text
end

--- 确认属性编辑
function confirmPropertyEdit()
    if not propEdit.active then return end

    -- LevelEditor 物件编辑
    if propEdit.targetId == "le_obj" then
        local leObj = getLevelEditorSelectedObj()
        if not leObj then
            propEdit.active = false
            return
        end
        local field = propEdit.field
        local text = propEdit.text
        local num = tonumber(text)
        if num then
            leObj[field] = num
        end
        propEdit.active = false
        propEdit.field = nil
        return
    end

    -- SceneManager 对象编辑
    local obj = SceneManager:getObjectById(propEdit.targetId)
    if not obj then
        propEdit.active = false
        return
    end

    local field = propEdit.field
    local text = propEdit.text

    -- 数值字段解析
    local numericFields = { x = true, y = true, w = true, h = true, rotation = true }
    if numericFields[field] then
        local num = tonumber(text)
        if num then
            SceneManager:updateObject(obj.id, { [field] = num })
        end
    else
        -- 字符串字段
        if #text > 0 then
            SceneManager:updateObject(obj.id, { [field] = text })
        end
    end

    propEdit.active = false
    propEdit.field = nil
end

--- 取消属性编辑
function cancelPropertyEdit()
    propEdit.active = false
    propEdit.field = nil
end

-- ============================================================
-- NanoVG 渲染
-- ============================================================
function M.Render(logW, logH, deviceDpr)
    if not active or not vg then return end
    screenW = logW
    screenH = logH
    dpr = deviceDpr

    -- 关卡模式: 游戏世界已由 main.lua 渲染, 这里叠加编辑器覆盖层+面板
    if currentMode == "level" and levelEditor and levelEditor.active then
        -- LevelEditor 覆盖层(网格/光标/底部工具栏)
        levelEditor:Render(logW, logH, dpr)
        -- IDE 顶部工具栏
        renderToolbar()
        -- 左侧图层面板
        renderLeftPanel()
        -- 右侧属性面板
        renderRightPanel()
        -- 控制台覆盖层
        renderConsoleOverlay()
        -- 叠加编译消息
        renderCompileMessage()
        return
    end

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillColor(vg, nvgRGBA(Config.COLORS.bg[1], Config.COLORS.bg[2], Config.COLORS.bg[3], 255))
    nvgFill(vg)

    -- 各区域渲染
    renderToolbar()
    renderLeftPanel()
    renderCanvas()
    renderRightPanel()
    -- 控制台覆盖层
    renderConsoleOverlay()
    renderCompileMessage()
end

-- ============================================================
-- 工具栏渲染
-- ============================================================
function renderToolbar()
    -- 工具栏背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, TOOLBAR_H)
    nvgFillColor(vg, nvgRGBA(Config.COLORS.toolbar[1], Config.COLORS.toolbar[2], Config.COLORS.toolbar[3], 255))
    nvgFill(vg)

    -- 按钮
    nvgFontFace(vg, "ide-sans")
    nvgFontSize(vg, 13)
    local btnW = 56
    local btnH = 28
    local startX = 8
    local btnY = (TOOLBAR_H - btnH) / 2
    local cx = startX

    for _, btn in ipairs(toolbarButtons) do
        if btn.id:sub(1,3) == "sep" then
            -- 分隔线
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx + 4, btnY + 2)
            nvgLineTo(vg, cx + 4, btnY + btnH - 2)
            nvgStrokeColor(vg, nvgRGBA(Config.COLORS.border[1], Config.COLORS.border[2], Config.COLORS.border[3], 255))
            nvgStroke(vg)
            cx = cx + 12
        else
            -- 按钮高亮(当前模式)
            local isActive = (btn.id == currentMode)
            local isHovered = mouse.x >= cx and mouse.x < cx + btnW and mouse.y >= btnY and mouse.y < btnY + btnH
            local bgColor
            if isActive then
                bgColor = Config.COLORS.accent
            elseif isHovered then
                bgColor = Config.COLORS.accentHover
            else
                bgColor = {60, 60, 65, 255}
            end

            nvgBeginPath(vg)
            nvgRoundedRect(vg, cx, btnY, btnW, btnH, 4)
            nvgFillColor(vg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
            nvgFill(vg)

            -- 按钮文字
            nvgFillColor(vg, nvgRGBA(Config.COLORS.text[1], Config.COLORS.text[2], Config.COLORS.text[3], 255))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(vg, cx + btnW / 2, btnY + btnH / 2, btn.label)

            cx = cx + btnW + 4
        end
    end

    -- 缩放数值显示
    local zoomValue = canvasView.zoom
    if currentMode == "level" and levelEditor then
        zoomValue = levelEditor.editorZoom or 1.0
    end
    local zoomStr = string.format("缩放: %.0f%%", zoomValue * 100)

    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(180, 220, 255, 255))
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgText(vg, screenW - 140, TOOLBAR_H / 2, zoomStr)

    -- 标题
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(Config.COLORS.text[1], Config.COLORS.text[2], Config.COLORS.text[3], 255))
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgText(vg, screenW - 12, TOOLBAR_H / 2, "Visual2D IDE v" .. Config.VERSION)

    -- 底部边线
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, TOOLBAR_H)
    nvgLineTo(vg, screenW, TOOLBAR_H)
    nvgStrokeColor(vg, nvgRGBA(Config.COLORS.border[1], Config.COLORS.border[2], Config.COLORS.border[3], 255))
    nvgStroke(vg)
end

-- ============================================================
-- 左面板渲染(图层面板)
-- ============================================================
function renderLeftPanel()
    local bottomOffset = (currentMode == "level") and BOTTOM_PALETTE_H or 0
    local x, y, w, h = 0, TOOLBAR_H, LEFT_PANEL_W, screenH - TOOLBAR_H - bottomOffset
    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillColor(vg, nvgRGBA(Config.COLORS.panel[1], Config.COLORS.panel[2], Config.COLORS.panel[3], 255))
    nvgFill(vg)

    -- 标题栏
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, 24)
    nvgFillColor(vg, nvgRGBA(Config.COLORS.panelHeader[1], Config.COLORS.panelHeader[2], Config.COLORS.panelHeader[3], 255))
    nvgFill(vg)

    nvgFontFace(vg, "ide-sans")
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(Config.COLORS.text[1], Config.COLORS.text[2], Config.COLORS.text[3], 255))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    if currentMode == "level" or currentMode == "scene" then
        nvgText(vg, x + 8, y + 12, "图层")

        -- 图层列表
        local layers = SceneManager:getLayers()
        local ly = y + 28
        local LAYER_ITEM_H = 26
        local ICON_SIZE = 14
        local EYE_X = x + w - 42   -- 眼睛图标 X
        local LOCK_X = x + w - 22  -- 锁定图标 X

        for i, layer in ipairs(layers) do
            local isActive = (i == SceneManager:getActiveLayerIndex())
            local isHovered = (layerPanel.hoveredLayer == i)
            local itemY = ly + (i - 1) * LAYER_ITEM_H

            -- 行背景(选中/悬停)
            if isActive then
                nvgBeginPath(vg)
                nvgRect(vg, x + 2, itemY, w - 4, LAYER_ITEM_H - 2)
                nvgFillColor(vg, nvgRGBA(Config.COLORS.selected[1], Config.COLORS.selected[2], Config.COLORS.selected[3], 220))
                nvgFill(vg)
            elseif isHovered then
                nvgBeginPath(vg)
                nvgRect(vg, x + 2, itemY, w - 4, LAYER_ITEM_H - 2)
                nvgFillColor(vg, nvgRGBA(60, 60, 65, 150))
                nvgFill(vg)
            end

            -- 图层名称
            local nameAlpha = layer.visible and 255 or 120
            nvgFillColor(vg, nvgRGBA(Config.COLORS.text[1], Config.COLORS.text[2], Config.COLORS.text[3], nameAlpha))
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgText(vg, x + 10, itemY + LAYER_ITEM_H / 2, layer.name)

            -- 对象数量
            local count = SceneManager:getLayerObjectCount(i)
            nvgFillColor(vg, nvgRGBA(Config.COLORS.textDim[1], Config.COLORS.textDim[2], Config.COLORS.textDim[3], 200))
            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgText(vg, x + 10 + 60, itemY + LAYER_ITEM_H / 2, "(" .. count .. ")")

            -- 可见性图标(眼睛)
            local eyeIconY = itemY + (LAYER_ITEM_H - ICON_SIZE) / 2
            local eyeHovered = (isHovered and layerPanel.hoveredIcon == "eye")
            if layer.visible then
                -- 睁眼图标
                nvgBeginPath(vg)
                nvgEllipse(vg, EYE_X + ICON_SIZE / 2, eyeIconY + ICON_SIZE / 2, 5, 3)
                nvgStrokeColor(vg, nvgRGBA(180, 220, 180, eyeHovered and 255 or 200))
                nvgStrokeWidth(vg, 1.2)
                nvgStroke(vg)
                nvgBeginPath(vg)
                nvgCircle(vg, EYE_X + ICON_SIZE / 2, eyeIconY + ICON_SIZE / 2, 1.5)
                nvgFillColor(vg, nvgRGBA(180, 220, 180, eyeHovered and 255 or 200))
                nvgFill(vg)
            else
                -- 闭眼(横线)
                nvgBeginPath(vg)
                nvgMoveTo(vg, EYE_X + 2, eyeIconY + ICON_SIZE / 2)
                nvgLineTo(vg, EYE_X + ICON_SIZE - 2, eyeIconY + ICON_SIZE / 2)
                nvgStrokeColor(vg, nvgRGBA(128, 128, 128, eyeHovered and 200 or 150))
                nvgStrokeWidth(vg, 1.2)
                nvgStroke(vg)
            end

            -- 锁定图标
            local lockIconY = itemY + (LAYER_ITEM_H - ICON_SIZE) / 2
            local lockHovered = (isHovered and layerPanel.hoveredIcon == "lock")
            if layer.locked then
                -- 锁定: 实心锁
                nvgBeginPath(vg)
                nvgRoundedRect(vg, LOCK_X + 3, lockIconY + 6, 8, 6, 1)
                nvgFillColor(vg, nvgRGBA(220, 160, 60, lockHovered and 255 or 200))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgArc(vg, LOCK_X + ICON_SIZE / 2, lockIconY + 6, 3, math.pi, 0, NVG_CW)
                nvgStrokeColor(vg, nvgRGBA(220, 160, 60, lockHovered and 255 or 200))
                nvgStrokeWidth(vg, 1.5)
                nvgStroke(vg)
            else
                -- 未锁定: 空心锁
                nvgBeginPath(vg)
                nvgRoundedRect(vg, LOCK_X + 3, lockIconY + 6, 8, 6, 1)
                nvgStrokeColor(vg, nvgRGBA(128, 128, 128, lockHovered and 200 or 120))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
                nvgBeginPath(vg)
                nvgArc(vg, LOCK_X + ICON_SIZE / 2, lockIconY + 6, 3, math.pi, 0, NVG_CW)
                nvgStrokeColor(vg, nvgRGBA(128, 128, 128, lockHovered and 200 or 120))
                nvgStrokeWidth(vg, 1)
                nvgStroke(vg)
            end

            -- 底部分隔线
            nvgBeginPath(vg)
            nvgMoveTo(vg, x + 6, itemY + LAYER_ITEM_H - 1)
            nvgLineTo(vg, x + w - 6, itemY + LAYER_ITEM_H - 1)
            nvgStrokeColor(vg, nvgRGBA(Config.COLORS.border[1], Config.COLORS.border[2], Config.COLORS.border[3], 80))
            nvgStrokeWidth(vg, 0.5)
            nvgStroke(vg)
        end

        -- 对象列表标题
        local objListY = ly + #layers * LAYER_ITEM_H + 8
        nvgBeginPath(vg)
        nvgRect(vg, x, objListY, w, 22)
        nvgFillColor(vg, nvgRGBA(Config.COLORS.panelHeader[1], Config.COLORS.panelHeader[2], Config.COLORS.panelHeader[3], 200))
        nvgFill(vg)

        -- 展开/折叠箭头
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(Config.COLORS.text[1], Config.COLORS.text[2], Config.COLORS.text[3], 255))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local arrow = layerPanel.objectListExpanded and "▾" or "▸"
        nvgText(vg, x + 8, objListY + 11, arrow .. " 对象列表")

        -- 对象列表
        if layerPanel.objectListExpanded then
            local oly = objListY + 24
            local objects = SceneManager:getAllObjects()
            local selected = SceneManager:getSelected()
            local OBJ_ITEM_H = 20

            if #objects == 0 then
                nvgFontSize(vg, 10)
                nvgFillColor(vg, nvgRGBA(Config.COLORS.textDim[1], Config.COLORS.textDim[2], Config.COLORS.textDim[3], 200))
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgText(vg, x + 14, oly + 10, "(空)")
            else
                for i, obj in ipairs(objects) do
                    if oly > y + h - 10 then break end
                    local isSel = selected and selected.id == obj.id
                    local isHov = layerPanel.hoveredObject == obj.id

                    -- 行背景
                    if isSel then
                        nvgBeginPath(vg)
                        nvgRect(vg, x + 4, oly, w - 8, OBJ_ITEM_H - 2)
                        nvgFillColor(vg, nvgRGBA(Config.COLORS.accent[1], Config.COLORS.accent[2], Config.COLORS.accent[3], 200))
                        nvgFill(vg)
                    elseif isHov then
                        nvgBeginPath(vg)
                        nvgRect(vg, x + 4, oly, w - 8, OBJ_ITEM_H - 2)
                        nvgFillColor(vg, nvgRGBA(60, 65, 70, 180))
                        nvgFill(vg)
                    end

                    -- 对象类型图标(小圆点指示图层颜色)
                    local layerColors = {
                        bg = {100, 160, 100},
                        game = {100, 150, 220},
                        ui = {200, 150, 100},
                    }
                    local dotColor = layerColors[obj.layer] or {150, 150, 150}
                    nvgBeginPath(vg)
                    nvgCircle(vg, x + 14, oly + OBJ_ITEM_H / 2, 3)
                    nvgFillColor(vg, nvgRGBA(dotColor[1], dotColor[2], dotColor[3], 220))
                    nvgFill(vg)

                    -- 对象名称
                    nvgFillColor(vg, nvgRGBA(Config.COLORS.text[1], Config.COLORS.text[2], Config.COLORS.text[3], isSel and 255 or 200))
                    nvgFontSize(vg, 10)
                    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                    nvgText(vg, x + 22, oly + OBJ_ITEM_H / 2, obj.name or obj.type)

                    oly = oly + OBJ_ITEM_H
                end
            end
        end
    else
        nvgText(vg, x + 8, y + 12, "节点类型")
        -- 节点类型面板
        local categories = NodeEditor:getCategories()
        local ly = y + 30
        for catName, types in pairs(categories) do
            -- 分类标题
            local catColor = Config.NODE_COLORS[catName] or Config.COLORS.text
            nvgFillColor(vg, nvgRGBA(catColor[1], catColor[2], catColor[3], 255))
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgText(vg, x + 8, ly + 10, "▸ " .. catName)
            ly = ly + 22
            for _, typeName in ipairs(types) do
                if ly > screenH - 10 then break end
                nvgFillColor(vg, nvgRGBA(Config.COLORS.text[1], Config.COLORS.text[2], Config.COLORS.text[3], 255))
                nvgFontSize(vg, 10)
                nvgText(vg, x + 20, ly + 9, typeName)
                ly = ly + 20
            end
        end
    end

    -- 右边框线
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + w, y)
    nvgLineTo(vg, x + w, y + h)
    nvgStrokeColor(vg, nvgRGBA(Config.COLORS.border[1], Config.COLORS.border[2], Config.COLORS.border[3], 255))
    nvgStroke(vg)
end

-- ============================================================
-- 画布渲染
-- ============================================================
function renderCanvas()
    local x = LEFT_PANEL_W
    local y = TOOLBAR_H
    local w = screenW - LEFT_PANEL_W - RIGHT_PANEL_W
    local h = screenH - TOOLBAR_H

    -- 画布背景
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillColor(vg, nvgRGBA(Config.COLORS.canvas[1], Config.COLORS.canvas[2], Config.COLORS.canvas[3], 255))
    nvgFill(vg)

    -- 裁剪区域
    nvgSave(vg)
    nvgScissor(vg, x, y, w, h)

    -- 应用视图变换
    nvgTranslate(vg, x + canvasView.offsetX, y + canvasView.offsetY)
    nvgScale(vg, canvasView.zoom, canvasView.zoom)

    if currentMode == "scene" then
        renderSceneCanvas(w, h)
    else
        renderNodeCanvas(w, h)
    end

    nvgRestore(vg)

    -- 画布模式指示器
    nvgFontFace(vg, "ide-sans")
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(Config.COLORS.textDim[1], Config.COLORS.textDim[2], Config.COLORS.textDim[3], 255))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    local modeText = "节点编辑 (左面板选类型)"
    nvgText(vg, x + 8, y + 6, modeText .. string.format("  缩放:%.0f%%", canvasView.zoom * 100))
end

function renderSceneCanvas(w, h)
    -- 网格
    local gridSize = Config.GRID_SIZE
    local startX = math.floor(-canvasView.offsetX / canvasView.zoom / gridSize) * gridSize - gridSize
    local startY = math.floor(-canvasView.offsetY / canvasView.zoom / gridSize) * gridSize - gridSize
    local endX = startX + w / canvasView.zoom + gridSize * 2
    local endY = startY + h / canvasView.zoom + gridSize * 2

    nvgStrokeWidth(vg, 0.5)
    nvgStrokeColor(vg, nvgRGBA(Config.COLORS.grid[1], Config.COLORS.grid[2], Config.COLORS.grid[3], Config.COLORS.grid[4]))
    for gx = startX, endX, gridSize do
        nvgBeginPath(vg)
        nvgMoveTo(vg, gx, startY)
        nvgLineTo(vg, gx, endY)
        nvgStroke(vg)
    end
    for gy = startY, endY, gridSize do
        nvgBeginPath(vg)
        nvgMoveTo(vg, startX, gy)
        nvgLineTo(vg, endX, gy)
        nvgStroke(vg)
    end

    -- 坐标原点标记
    nvgStrokeWidth(vg, 2)
    nvgStrokeColor(vg, nvgRGBA(255, 80, 80, 200))
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -20)
    nvgLineTo(vg, 0, 20)
    nvgStroke(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 255, 80, 200))
    nvgBeginPath(vg)
    nvgMoveTo(vg, -20, 0)
    nvgLineTo(vg, 20, 0)
    nvgStroke(vg)

    -- 渲染场景对象
    local objects = SceneManager:getAllObjects()
    local selected = SceneManager:getSelected()
    for _, obj in ipairs(objects) do
        local isSel = selected and selected.id == obj.id
        local objW = obj.w or 48
        local objH = obj.h or 48

        -- 对象矩形
        nvgBeginPath(vg)
        nvgRect(vg, obj.x - objW / 2, obj.y - objH / 2, objW, objH)
        if isSel then
            nvgFillColor(vg, nvgRGBA(Config.COLORS.accent[1], Config.COLORS.accent[2], Config.COLORS.accent[3], 150))
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgStrokeWidth(vg, 2)
        else
            nvgFillColor(vg, nvgRGBA(100, 150, 200, 120))
            nvgStrokeColor(vg, nvgRGBA(Config.COLORS.border[1], Config.COLORS.border[2], Config.COLORS.border[3], 200))
            nvgStrokeWidth(vg, 1)
        end
        nvgFill(vg)
        nvgStroke(vg)

        -- 对象名称
        nvgFontFace(vg, "ide-sans")
        nvgFontSize(vg, 10)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(vg, obj.x, obj.y, obj.name or obj.type)
    end
end

function renderNodeCanvas(w, h)
    -- 节点编辑器网格(点状)
    local gridSize = 20
    local startX = math.floor(-canvasView.offsetX / canvasView.zoom / gridSize) * gridSize
    local startY = math.floor(-canvasView.offsetY / canvasView.zoom / gridSize) * gridSize
    local endX = startX + w / canvasView.zoom + gridSize
    local endY = startY + h / canvasView.zoom + gridSize

    nvgFillColor(vg, nvgRGBA(Config.COLORS.grid[1], Config.COLORS.grid[2], Config.COLORS.grid[3], 80))
    for gx = startX, endX, gridSize do
        for gy = startY, endY, gridSize do
            nvgBeginPath(vg)
            nvgCircle(vg, gx, gy, 1)
            nvgFill(vg)
        end
    end

    -- 渲染连接线(贝塞尔曲线)
    local connections = NodeEditor:getConnections()
    for _, conn in ipairs(connections) do
        local fromNode = NodeEditor:getNodeById(conn.fromNode)
        local toNode = NodeEditor:getNodeById(conn.toNode)
        if fromNode and toNode then
            local fromX, fromY = getPortPosition(fromNode, conn.fromPort, true)
            local toX, toY = getPortPosition(toNode, conn.toPort, false)
            drawBezierConnection(fromX, fromY, toX, toY, {200, 200, 200, 200})
        end
    end

    -- 正在绘制的连线
    if connectionDraw.active then
        local fromNode = NodeEditor:getNodeById(connectionDraw.fromNodeId)
        if fromNode then
            local fromX, fromY = getPortPosition(fromNode, connectionDraw.fromPortIdx, connectionDraw.fromIsOutput)
            drawBezierConnection(fromX, fromY, connectionDraw.endX, connectionDraw.endY, {255, 200, 50, 255})
        end
    end

    -- 渲染节点
    local nodes = NodeEditor:getAllNodes()
    local selectedNode = NodeEditor:getSelectedNode()
    for _, node in ipairs(nodes) do
        renderNode(node, selectedNode and selectedNode.id == node.id)
    end
end

-- ============================================================
-- 节点渲染辅助
-- ============================================================
local NODE_W = 160
local NODE_H_BASE = 40
local PORT_RADIUS = 6
local PORT_SPACING = 20

function getNodeHeight(node)
    local inputCount = node.inputs and #node.inputs or 0
    local outputCount = node.outputs and #node.outputs or 0
    local maxPorts = math.max(inputCount, outputCount)
    return NODE_H_BASE + maxPorts * PORT_SPACING
end

function getPortPosition(node, portIdx, isOutput)
    local h = getNodeHeight(node)
    local portY = node.y + 30 + (portIdx - 1) * PORT_SPACING
    if isOutput then
        return node.x + NODE_W, portY
    else
        return node.x, portY
    end
end

function drawBezierConnection(x1, y1, x2, y2, color)
    local dx = math.abs(x2 - x1) * 0.5
    nvgBeginPath(vg)
    nvgMoveTo(vg, x1, y1)
    nvgBezierTo(vg, x1 + dx, y1, x2 - dx, y2, x2, y2)
    nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
end

function renderNode(node, isSelected)
    local h = getNodeHeight(node)
    local category = node.category or "action"
    local catColor = Config.NODE_COLORS[category] or Config.COLORS.accent

    -- 节点阴影
    nvgBeginPath(vg)
    nvgRoundedRect(vg, node.x + 2, node.y + 2, NODE_W, h, 6)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
    nvgFill(vg)

    -- 节点背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, node.x, node.y, NODE_W, h, 6)
    nvgFillColor(vg, nvgRGBA(50, 50, 55, 240))
    nvgFill(vg)

    -- 标题栏
    nvgBeginPath(vg)
    nvgRoundedRect(vg, node.x, node.y, NODE_W, 24, 6)
    -- 只圆顶部(用矩形覆盖底部圆角)
    nvgRect(vg, node.x, node.y + 12, NODE_W, 12)
    nvgFillColor(vg, nvgRGBA(catColor[1], catColor[2], catColor[3], 220))
    nvgFill(vg)

    -- 选中边框
    if isSelected then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, node.x - 1, node.y - 1, NODE_W + 2, h + 2, 7)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end

    -- 标题文字
    nvgFontFace(vg, "ide-sans")
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(vg, node.x + 8, node.y + 12, node.name or node.type)

    -- 输入端口
    if node.inputs then
        for i, port in ipairs(node.inputs) do
            local px, py = getPortPosition(node, i, false)
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, PORT_RADIUS)
            nvgFillColor(vg, nvgRGBA(80, 180, 80, 255))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(40, 100, 40, 255))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            -- 端口名
            nvgFontSize(vg, 9)
            nvgFillColor(vg, nvgRGBA(Config.COLORS.text[1], Config.COLORS.text[2], Config.COLORS.text[3], 200))
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgText(vg, px + PORT_RADIUS + 4, py, port.name or ("in" .. i))
        end
    end

    -- 输出端口
    if node.outputs then
        for i, port in ipairs(node.outputs) do
            local px, py = getPortPosition(node, i, true)
            nvgBeginPath(vg)
            nvgCircle(vg, px, py, PORT_RADIUS)
            nvgFillColor(vg, nvgRGBA(200, 120, 50, 255))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(120, 60, 20, 255))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            -- 端口名
            nvgFontSize(vg, 9)
            nvgFillColor(vg, nvgRGBA(Config.COLORS.text[1], Config.COLORS.text[2], Config.COLORS.text[3], 200))
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgText(vg, px - PORT_RADIUS - 4, py, port.name or ("out" .. i))
        end
    end
end

-- ============================================================
-- 右面板渲染(标签页: 属性/组件/控制台/资源)
-- ============================================================
function renderRightPanelTabHeader(x, y, w)
    -- 标签栏背景
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, RIGHT_TAB_H)
    nvgFillColor(vg, nvgRGBA(Config.COLORS.panelHeader[1], Config.COLORS.panelHeader[2], Config.COLORS.panelHeader[3], 255))
    nvgFill(vg)

    -- 绘制每个标签
    local tabW = w / #rightPanelTabs
    nvgFontFace(vg, "ide-sans")
    nvgFontSize(vg, 11)
    for i, tab in ipairs(rightPanelTabs) do
        local tx = x + (i - 1) * tabW
        local isActive = (rightPanelTab == tab.id)
        local isHovered = mouse.x >= tx and mouse.x < tx + tabW and mouse.y >= y and mouse.y < y + RIGHT_TAB_H

        if isActive then
            nvgBeginPath(vg)
            nvgRect(vg, tx, y + RIGHT_TAB_H - 2, tabW, 2)
            nvgFillColor(vg, nvgRGBA(Config.COLORS.accent[1], Config.COLORS.accent[2], Config.COLORS.accent[3], 255))
            nvgFill(vg)
        end

        if isHovered and not isActive then
            nvgFillColor(vg, nvgRGBA(Config.COLORS.text[1], Config.COLORS.text[2], Config.COLORS.text[3], 255))
        elseif isActive then
            nvgFillColor(vg, nvgRGBA(Config.COLORS.accent[1], Config.COLORS.accent[2], Config.COLORS.accent[3], 255))
        else
            nvgFillColor(vg, nvgRGBA(Config.COLORS.textDim[1], Config.COLORS.textDim[2], Config.COLORS.textDim[3], 255))
        end
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(vg, tx + tabW / 2, y + RIGHT_TAB_H / 2, tab.label)
    end
end

function renderRightPanel()
    local bottomOffset = (currentMode == "level") and BOTTOM_PALETTE_H or 0
    local x = screenW - RIGHT_PANEL_W
    local y = TOOLBAR_H
    local w = RIGHT_PANEL_W
    local h = screenH - TOOLBAR_H - bottomOffset

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    nvgFillColor(vg, nvgRGBA(Config.COLORS.panel[1], Config.COLORS.panel[2], Config.COLORS.panel[3], 255))
    nvgFill(vg)

    -- 标签页头
    renderRightPanelTabHeader(x, y, w)

    -- 内容区域起始Y
    local contentY = y + RIGHT_TAB_H + 4
    local contentH = h - RIGHT_TAB_H - 4

    -- 根据当前标签渲染对应面板
    if rightPanelTab == "properties" then
        renderPropertiesContent(x, contentY, w, contentH)
    elseif rightPanelTab == "components" then
        renderComponentsContent(x, contentY, w, contentH)
    elseif rightPanelTab == "console" then
        renderConsoleContent(x, contentY, w, contentH)
    elseif rightPanelTab == "assets" then
        renderAssetsContent(x, contentY, w, contentH)
    end

    -- 左边框线
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y)
    nvgLineTo(vg, x, y + h)
    nvgStrokeColor(vg, nvgRGBA(Config.COLORS.border[1], Config.COLORS.border[2], Config.COLORS.border[3], 255))
    nvgStroke(vg)
end

-- ============================================================
-- 右面板: LevelEditor 物件属性辅助
-- ============================================================

--- 获取 LevelEditor 当前选中的物件对象
---@return table|nil obj, table|nil fields
function getLevelEditorSelectedObj()
    if not levelEditor or not levelEditor.active then
        -- print("[DEBUG] getLevelEditorSelectedObj: levelEditor nil or not active")
        return nil, nil
    end
    -- 支持绘制模式(selectedType/selectedIdx)和编辑模式(editSelected)两种选择系统
    local selType = levelEditor.selectedType
    local selIdx = levelEditor.selectedIdx
    -- 编辑模式使用 editSelected
    if (not selType or selType ~= "object" or not selIdx) and levelEditor.editSelected then
        if levelEditor.editSelected.type == "object" and levelEditor.editSelected.idx then
            selType = "object"
            selIdx = levelEditor.editSelected.idx
        end
    end
    if selType ~= "object" or not selIdx then return nil, nil end
    local decos = levelEditor:GetMapDecorations()
    if not decos then return nil, nil end
    local obj = decos[selIdx]
    if not obj then return nil, nil end

    -- 为没有 z/rotation/size 的物件提供默认值
    if obj.z == nil then obj.z = 0 end
    if obj.rotation == nil then obj.rotation = 0 end
    if obj.size == nil and obj.type ~= "tree" then obj.size = 15 end

    -- 通用变换属性: 位置(xyz)、大小、旋转 + 类型特有属性
    local fields = {
        { field = "type",     label = "类型",   editable = false },
        { field = "x",        label = "X",      editable = true,  group = "位置" },
        { field = "y",        label = "Y",      editable = true },
        { field = "z",        label = "Z",      editable = true },
        { field = "rotation", label = "旋转",   editable = true,  group = "变换" },
    }
    -- 大小属性
    if obj.type == "tree" then
        table.insert(fields, { field = "height", label = "大小", editable = true })
    else
        table.insert(fields, { field = "size",   label = "大小", editable = true })
    end
    -- 类型特有属性
    if obj.type == "tree" then
        table.insert(fields, { field = "branches", label = "枝干数", editable = true,  group = "属性" })
        table.insert(fields, { field = "twist",    label = "扭曲",   editable = true })
        table.insert(fields, { field = "seed",     label = "种子",   editable = true })
    elseif obj.type == "rock" then
        table.insert(fields, { field = "seed",    label = "种子",   editable = true, group = "属性" })
    elseif obj.type == "flower" or obj.type == "plant" then
        table.insert(fields, { field = "variant", label = "变体",   editable = true, group = "属性" })
        table.insert(fields, { field = "seed",    label = "种子",   editable = true })
    end
    return obj, fields
end

-- ============================================================
-- 右面板: 属性内容
-- ============================================================
function renderPropertiesContent(x, y, w, h)
    local ly = y + 4
    if currentMode == "level" or currentMode == "scene" then
        local sel = SceneManager:getSelected()
        if sel then
            local fields = {
                { field = "name",     label = "名称",   editable = true },
                { field = "type",     label = "类型",   editable = false },
                { field = "x",        label = "X",      editable = true },
                { field = "y",        label = "Y",      editable = true },
                { field = "w",        label = "宽度",   editable = true },
                { field = "h",        label = "高度",   editable = true },
                { field = "rotation", label = "旋转",   editable = true },
                { field = "layer",    label = "图层",   editable = false },
            }
            local PROP_H = 26
            for i, prop in ipairs(fields) do
                local itemY = ly + (i - 1) * PROP_H
                local isEditing = propEdit.active and propEdit.field == prop.field and propEdit.targetId == sel.id
                local isHovered = (propPanel.hoveredField == prop.field)
                renderPropertyField(x, itemY, w, prop.label, sel[prop.field], prop.editable, isEditing, isHovered, prop.field)
            end
        else
            -- 检查 LevelEditor 是否有选中物件
            local leObj, leFields = getLevelEditorSelectedObj()
            if leObj and leFields then
                local PROP_H = 26
                local GROUP_H = 20
                local offsetY = 0
                for i, prop in ipairs(leFields) do
                    -- 分组标题
                    if prop.group then
                        nvgFontFace(vg, "ide-sans")
                        nvgFontSize(vg, 9)
                        nvgFillColor(vg, nvgRGBA(Config.COLORS.textDim[1], Config.COLORS.textDim[2], Config.COLORS.textDim[3], 180))
                        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                        nvgText(vg, x + 8, ly + offsetY + GROUP_H / 2, prop.group)
                        offsetY = offsetY + GROUP_H
                    end
                    local itemY = ly + offsetY
                    local isEditing = propEdit.active and propEdit.field == prop.field and propEdit.targetId == "le_obj"
                    local isHovered = (propPanel.hoveredField == prop.field)
                    local val = leObj[prop.field]
                    if prop.field == "type" then
                        local typeNames = { tree = "树木", rock = "岩石", flower = "花朵", plant = "植物", deadtree = "枯树" }
                        val = typeNames[val] or val
                    elseif type(val) == "number" then
                        val = math.floor(val * 100) / 100  -- 保留2位小数
                    end
                    renderPropertyField(x, itemY, w, prop.label, val, prop.editable, isEditing, isHovered, prop.field)
                    offsetY = offsetY + PROP_H
                end
            else
                nvgFontFace(vg, "ide-sans")
                nvgFontSize(vg, 11)
                nvgFillColor(vg, nvgRGBA(Config.COLORS.textDim[1], Config.COLORS.textDim[2], Config.COLORS.textDim[3], 255))
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgText(vg, x + 8, ly + 10, "未选中对象")
                nvgFontSize(vg, 10)
                nvgText(vg, x + 8, ly + 28, "在画布中点击选择对象")
            end
        end
    else
        local sel = NodeEditor:getSelectedNode()
        if sel then
            local PROP_H = 26
            local nodeFields = {
                { field = "name",     label = "节点",   editable = false },
                { field = "type",     label = "类型",   editable = false },
                { field = "category", label = "类别",   editable = false },
                { field = "x",        label = "X",      editable = false },
                { field = "y",        label = "Y",      editable = false },
            }
            for i, prop in ipairs(nodeFields) do
                local itemY = ly + (i - 1) * PROP_H
                renderPropertyField(x, itemY, w, prop.label, sel[prop.field], prop.editable, false, false, prop.field)
            end

            -- 输入端口
            local portY = ly + #nodeFields * PROP_H + 8
            if sel.inputs and #sel.inputs > 0 then
                nvgFontFace(vg, "ide-sans")
                nvgFontSize(vg, 11)
                nvgFillColor(vg, nvgRGBA(Config.COLORS.text[1], Config.COLORS.text[2], Config.COLORS.text[3], 200))
                nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
                nvgText(vg, x + 8, portY, "▸ 输入端口")
                portY = portY + 18
                for i, port in ipairs(sel.inputs) do
                    renderPropertyField(x, portY, w, port.name or ("in"..i), port.value or "", false, false, false, nil)
                    portY = portY + 22
                end
            end
        else
            nvgFontFace(vg, "ide-sans")
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(Config.COLORS.textDim[1], Config.COLORS.textDim[2], Config.COLORS.textDim[3], 255))
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgText(vg, x + 8, ly + 10, "未选中节点")
        end
    end
end

-- ============================================================
-- 右面板: 组件内容
-- ============================================================
function renderComponentsContent(x, y, w, h)
    nvgFontFace(vg, "ide-sans")
    local ly = y + 4
    local sel = SceneManager:getSelected()

    if not sel then
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(Config.COLORS.textDim[1], Config.COLORS.textDim[2], Config.COLORS.textDim[3], 255))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgText(vg, x + 8, ly + 10, "选中对象后查看组件")
        return
    end

    -- 组件类型按类别分组
    local categories = ComponentSystem:GetTypesByCategory()
    local ITEM_H = 22

    -- 已有组件列表
    local existingComps = sel.components or {}
    if #existingComps > 0 then
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(Config.COLORS.text[1], Config.COLORS.text[2], Config.COLORS.text[3], 255))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgText(vg, x + 8, ly + 10, "▸ 已挂载 (" .. #existingComps .. ")")
        ly = ly + 22

        for _, comp in ipairs(existingComps) do
            local isHov = mouse.x >= x and mouse.x < x + w and mouse.y >= ly and mouse.y < ly + ITEM_H
            if isHov then
                nvgBeginPath(vg)
                nvgRect(vg, x + 4, ly, w - 8, ITEM_H)
                nvgFillColor(vg, nvgRGBA(60, 65, 75, 150))
                nvgFill(vg)
            end
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBA(Config.COLORS.text[1], Config.COLORS.text[2], Config.COLORS.text[3], 220))
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgText(vg, x + 12, ly + ITEM_H / 2, comp.type or "Unknown")
            ly = ly + ITEM_H
        end
        ly = ly + 6
    end

    -- 可添加组件列表
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(Config.COLORS.textDim[1], Config.COLORS.textDim[2], Config.COLORS.textDim[3], 255))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(vg, x + 8, ly + 10, "▸ 添加组件")
    ly = ly + 22

    for catName, types in pairs(categories) do
        -- 分类标题
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(Config.COLORS.accent[1], Config.COLORS.accent[2], Config.COLORS.accent[3], 180))
        nvgText(vg, x + 10, ly + ITEM_H / 2, string.upper(catName))
        ly = ly + 18
        for _, typeName in ipairs(types) do
            if ly + ITEM_H > y + h then break end
            local isHov = mouse.x >= x and mouse.x < x + w and mouse.y >= ly and mouse.y < ly + ITEM_H
            if isHov then
                nvgBeginPath(vg)
                nvgRect(vg, x + 4, ly, w - 8, ITEM_H)
                nvgFillColor(vg, nvgRGBA(50, 55, 65, 150))
                nvgFill(vg)
            end
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBA(Config.COLORS.text[1], Config.COLORS.text[2], Config.COLORS.text[3], 180))
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgText(vg, x + 16, ly + ITEM_H / 2, "+ " .. typeName)
            ly = ly + ITEM_H
        end
    end
end

-- ============================================================
-- 右面板: 控制台/日志内容
-- ============================================================
function renderConsoleContent(x, y, w, h)
    nvgFontFace(vg, "ide-sans")
    local logs = Console:GetFilteredLogs()
    local LOG_LINE_H = 16
    local maxLines = math.floor((h - 10) / LOG_LINE_H)
    local startIdx = math.max(1, #logs - maxLines + 1)

    -- 日志列表
    local ly = y + 4
    for i = startIdx, #logs do
        if ly + LOG_LINE_H > y + h then break end
        local entry = logs[i]
        local levelColor = Console.LEVELS[entry.level] or {180, 180, 180}
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(levelColor[1], levelColor[2], levelColor[3], 220))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

        -- 截断过长文本
        local text = entry.text or ""
        if #text > 35 then text = text:sub(1, 35) .. "…" end
        nvgText(vg, x + 6, ly + LOG_LINE_H / 2, text)
        ly = ly + LOG_LINE_H
    end

    if #logs == 0 then
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(Config.COLORS.textDim[1], Config.COLORS.textDim[2], Config.COLORS.textDim[3], 255))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgText(vg, x + 8, y + 14, "暂无日志")
        nvgFontSize(vg, 9)
        nvgText(vg, x + 8, y + 30, "F7 打开控制台输入")
    end
end

-- ============================================================
-- 右面板: 资源浏览内容
-- ============================================================
function renderAssetsContent(x, y, w, h)
    nvgFontFace(vg, "ide-sans")
    local assets = AssetBrowser:GetFilteredAssets()
    local ITEM_H = 24
    local ly = y + 4

    -- 类别过滤条
    local cats = AssetBrowser._categories or {"all"}
    local catW = w / math.max(#cats, 1)
    nvgFontSize(vg, 9)
    for ci, cat in ipairs(cats) do
        local cx = x + (ci - 1) * catW
        local isActive = (AssetBrowser._currentCategory == cat)
        if isActive then
            nvgFillColor(vg, nvgRGBA(Config.COLORS.accent[1], Config.COLORS.accent[2], Config.COLORS.accent[3], 255))
        else
            nvgFillColor(vg, nvgRGBA(Config.COLORS.textDim[1], Config.COLORS.textDim[2], Config.COLORS.textDim[3], 200))
        end
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(vg, cx + catW / 2, ly + 8, cat)
    end
    ly = ly + 20

    -- 资源列表
    if #assets == 0 then
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(Config.COLORS.textDim[1], Config.COLORS.textDim[2], Config.COLORS.textDim[3], 255))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgText(vg, x + 8, ly + 10, "无资源")
        nvgFontSize(vg, 9)
        nvgText(vg, x + 8, ly + 26, "将文件放入 assets/ 目录")
        return
    end

    for idx, asset in ipairs(assets) do
        if ly + ITEM_H > y + h then break end
        local isHov = mouse.x >= x and mouse.x < x + w and mouse.y >= ly and mouse.y < ly + ITEM_H
        local isSel = (AssetBrowser._selectedAsset == asset.path)

        if isSel then
            nvgBeginPath(vg)
            nvgRect(vg, x + 2, ly, w - 4, ITEM_H)
            nvgFillColor(vg, nvgRGBA(Config.COLORS.accent[1], Config.COLORS.accent[2], Config.COLORS.accent[3], 60))
            nvgFill(vg)
        elseif isHov then
            nvgBeginPath(vg)
            nvgRect(vg, x + 2, ly, w - 4, ITEM_H)
            nvgFillColor(vg, nvgRGBA(60, 65, 75, 120))
            nvgFill(vg)
        end

        -- 图标
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(Config.COLORS.text[1], Config.COLORS.text[2], Config.COLORS.text[3], 200))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local icon = "📄"
        if asset.category == "image" then icon = "🖼"
        elseif asset.category == "sound" then icon = "🔊"
        elseif asset.category == "script" then icon = "📜"
        elseif asset.category == "model" then icon = "📦"
        end
        nvgText(vg, x + 6, ly + ITEM_H / 2, icon)

        -- 文件名
        nvgFontSize(vg, 10)
        nvgFillColor(vg, nvgRGBA(Config.COLORS.text[1], Config.COLORS.text[2], Config.COLORS.text[3], 220))
        local name = asset.name or asset.path or "unknown"
        if #name > 25 then name = name:sub(1, 25) .. "…" end
        nvgText(vg, x + 24, ly + ITEM_H / 2, name)

        ly = ly + ITEM_H
    end
end

-- ============================================================
-- 控制台覆盖层 (画布底部弹出)
-- ============================================================
function renderConsoleOverlay()
    if not showConsoleOverlay then return end

    local canvasX = LEFT_PANEL_W
    local canvasW = screenW - LEFT_PANEL_W - RIGHT_PANEL_W
    local overlayY = screenH - consoleOverlayH
    local overlayW = canvasW
    local overlayH = consoleOverlayH

    -- 如果关卡模式有底部调色板, 往上偏移
    if currentMode == "level" then
        overlayY = screenH - BOTTOM_PALETTE_H - consoleOverlayH
    end

    -- 半透明背景
    nvgBeginPath(vg)
    nvgRect(vg, canvasX, overlayY, overlayW, overlayH)
    nvgFillColor(vg, nvgRGBA(25, 28, 32, 235))
    nvgFill(vg)

    -- 顶部边线
    nvgBeginPath(vg)
    nvgMoveTo(vg, canvasX, overlayY)
    nvgLineTo(vg, canvasX + overlayW, overlayY)
    nvgStrokeColor(vg, nvgRGBA(Config.COLORS.accent[1], Config.COLORS.accent[2], Config.COLORS.accent[3], 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 标题栏
    nvgFontFace(vg, "ide-sans")
    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(Config.COLORS.accent[1], Config.COLORS.accent[2], Config.COLORS.accent[3], 255))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(vg, canvasX + 8, overlayY + 10, "控制台 (F7关闭 | Enter执行)")

    -- 日志区
    local logs = Console:GetFilteredLogs()
    local LOG_LINE_H = 14
    local logAreaY = overlayY + 22
    local logAreaH = overlayH - 44
    local maxLines = math.floor(logAreaH / LOG_LINE_H)
    local startIdx = math.max(1, #logs - maxLines + 1)

    local ly = logAreaY
    for i = startIdx, #logs do
        if ly + LOG_LINE_H > logAreaY + logAreaH then break end
        local entry = logs[i]
        local levelColor = Console.LEVELS[entry.level] or {180, 180, 180}
        nvgFontSize(vg, 9)
        nvgFillColor(vg, nvgRGBA(levelColor[1], levelColor[2], levelColor[3], 200))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local text = entry.text or ""
        if #text > 80 then text = text:sub(1, 80) .. "…" end
        nvgText(vg, canvasX + 8, ly + LOG_LINE_H / 2, text)
        ly = ly + LOG_LINE_H
    end

    -- 输入框
    local inputY = overlayY + overlayH - 22
    nvgBeginPath(vg)
    nvgRect(vg, canvasX + 4, inputY, overlayW - 8, 18)
    nvgFillColor(vg, nvgRGBA(35, 38, 45, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(Config.COLORS.accent[1], Config.COLORS.accent[2], Config.COLORS.accent[3], 150))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 输入文本
    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local inputText = Console._input_text or ""
    nvgText(vg, canvasX + 10, inputY + 9, "> " .. inputText)

    -- 光标闪烁
    if math.floor(os.clock() * 2) % 2 == 0 then
        local cursorX = canvasX + 10 + nvgTextBounds(vg, 0, 0, "> " .. inputText)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cursorX + 1, inputY + 3)
        nvgLineTo(vg, cursorX + 1, inputY + 15)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    end
end

--- 渲染单行属性字段(label: value 格式, 可编辑/悬停/编辑态)
function renderPropertyField(x, y, w, label, value, editable, isEditing, isHovered, field)
    local PROP_H = 26
    local labelW = w * 0.35
    local valueX = x + labelW
    local valueW = w - labelW - 8

    nvgFontFace(vg, "ide-sans")

    -- 行背景(悬停可编辑时高亮)
    if editable and isHovered and not isEditing then
        nvgBeginPath(vg)
        nvgRect(vg, valueX - 2, y + 2, valueW + 4, PROP_H - 4)
        nvgFillColor(vg, nvgRGBA(60, 65, 75, 180))
        nvgFill(vg)
    end

    -- 标签
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(Config.COLORS.textDim[1], Config.COLORS.textDim[2], Config.COLORS.textDim[3], 255))
    nvgText(vg, x + 8, y + PROP_H / 2, label)

    -- 值显示
    if isEditing then
        -- 编辑态: 绘制输入框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, valueX - 2, y + 3, valueW + 4, PROP_H - 6, 3)
        nvgFillColor(vg, nvgRGBA(35, 38, 45, 255))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(Config.COLORS.accent[1], Config.COLORS.accent[2], Config.COLORS.accent[3], 255))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 文本
        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgText(vg, valueX + 4, y + PROP_H / 2, propEdit.text)

        -- 光标闪烁
        if math.floor(propEdit.cursorBlink * 2) % 2 == 0 then
            -- 估算光标位置
            local bounds = {}
            local textWidth = nvgTextBounds(vg, 0, 0, propEdit.text:sub(1, propEdit.cursorPos))
            local cursorX = valueX + 4 + textWidth
            nvgBeginPath(vg)
            nvgMoveTo(vg, cursorX, y + 6)
            nvgLineTo(vg, cursorX, y + PROP_H - 6)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 220))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end
    else
        -- 格式化值显示
        local displayValue
        if value == nil then
            displayValue = ""
        elseif type(value) == "number" then
            if field == "rotation" then
                displayValue = string.format("%.1f°", value)
            else
                displayValue = string.format("%.1f", value)
            end
        else
            displayValue = tostring(value)
        end

        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        if editable then
            nvgFillColor(vg, nvgRGBA(Config.COLORS.text[1], Config.COLORS.text[2], Config.COLORS.text[3], 255))
        else
            nvgFillColor(vg, nvgRGBA(Config.COLORS.textDim[1], Config.COLORS.textDim[2], Config.COLORS.textDim[3], 200))
        end
        nvgText(vg, x + w - 8, y + PROP_H / 2, displayValue)

        -- 可编辑标记(小下划线)
        if editable then
            nvgBeginPath(vg)
            local tw = nvgTextBounds(vg, 0, 0, displayValue)
            nvgMoveTo(vg, x + w - 8 - tw, y + PROP_H / 2 + 7)
            nvgLineTo(vg, x + w - 8, y + PROP_H / 2 + 7)
            nvgStrokeColor(vg, nvgRGBA(Config.COLORS.accent[1], Config.COLORS.accent[2], Config.COLORS.accent[3], 80))
            nvgStrokeWidth(vg, 0.5)
            nvgStroke(vg)
        end
    end

    -- 底部分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + 6, y + PROP_H - 1)
    nvgLineTo(vg, x + w - 6, y + PROP_H - 1)
    nvgStrokeColor(vg, nvgRGBA(Config.COLORS.border[1], Config.COLORS.border[2], Config.COLORS.border[3], 60))
    nvgStrokeWidth(vg, 0.5)
    nvgStroke(vg)
end

-- ============================================================
-- 编译消息渲染
-- ============================================================
function renderCompileMessage()
    if compileMsg.timer <= 0 then return end

    local msgW = 300
    local msgH = 36
    local msgX = (screenW - msgW) / 2
    local msgY = screenH - 60

    local alpha = math.min(255, math.floor(compileMsg.timer * 200))
    local bgColor = compileMsg.success and Config.COLORS.success or Config.COLORS.danger

    nvgBeginPath(vg)
    nvgRoundedRect(vg, msgX, msgY, msgW, msgH, 6)
    nvgFillColor(vg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], alpha))
    nvgFill(vg)

    nvgFontFace(vg, "ide-sans")
    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, msgX + msgW / 2, msgY + msgH / 2, compileMsg.text)
end

return M
