-- ============================================================
-- IDE/NodeEditor.lua - 增强版可视化节点编辑器
-- 40+ 节点类型、数据流编译、变量作用域、分组、注释节点
-- ============================================================
local Config = require("IDE.Config")
local EventBus = require("IDE.EventBus")
local UndoManager = require("IDE.UndoManager")

local NodeEditor = {}

-- 节点类型定义 (完整版 40+ 类型)
NodeEditor.NODE_TYPES = {
    -- === 事件节点 ===
    Event_Start = {
        category = "event", color = Config.NODE_COLORS.event,
        inputs = {},
        outputs = {{name = "执行", type = "exec"}},
        props = {},
        desc = "游戏开始时触发",
    },
    Event_Tick = {
        category = "event", color = Config.NODE_COLORS.event,
        inputs = {},
        outputs = {{name = "执行", type = "exec"}, {name = "dt", type = "number"}},
        props = {},
        desc = "每帧更新时触发",
    },
    Event_KeyPress = {
        category = "event", color = Config.NODE_COLORS.event,
        inputs = {},
        outputs = {{name = "执行", type = "exec"}},
        props = {{name = "按键", type = "string", default = "Space"}},
        desc = "按键按下时触发",
    },
    Event_KeyRelease = {
        category = "event", color = Config.NODE_COLORS.event,
        inputs = {},
        outputs = {{name = "执行", type = "exec"}},
        props = {{name = "按键", type = "string", default = "Space"}},
        desc = "按键释放时触发",
    },
    Event_Collision = {
        category = "event", color = Config.NODE_COLORS.event,
        inputs = {},
        outputs = {{name = "执行", type = "exec"}, {name = "other", type = "object"}},
        props = {{name = "标签", type = "string", default = ""}},
        desc = "碰撞发生时触发",
    },
    Event_Timer = {
        category = "event", color = Config.NODE_COLORS.event,
        inputs = {},
        outputs = {{name = "执行", type = "exec"}},
        props = {{name = "间隔", type = "number", default = 1.0}, {name = "循环", type = "boolean", default = true}},
        desc = "定时器触发",
    },
    Event_MouseClick = {
        category = "event", color = Config.NODE_COLORS.event,
        inputs = {},
        outputs = {{name = "执行", type = "exec"}, {name = "X", type = "number"}, {name = "Y", type = "number"}},
        props = {{name = "按钮", type = "string", default = "left"}},
        desc = "鼠标点击时触发",
    },

    -- === 动作节点 ===
    Action_Log = {
        category = "action", color = Config.NODE_COLORS.action,
        inputs = {{name = "执行", type = "exec"}, {name = "内容", type = "string"}},
        outputs = {{name = "执行", type = "exec"}},
        props = {{name = "文本", type = "string", default = "Hello"}},
        desc = "输出日志",
    },
    Action_CreateUnit = {
        category = "action", color = Config.NODE_COLORS.action,
        inputs = {{name = "执行", type = "exec"}, {name = "类型", type = "string"}, {name = "X", type = "number"}, {name = "Y", type = "number"}},
        outputs = {{name = "执行", type = "exec"}, {name = "单位", type = "object"}},
        props = {},
        desc = "创建游戏对象",
    },
    Action_DestroyUnit = {
        category = "action", color = Config.NODE_COLORS.action,
        inputs = {{name = "执行", type = "exec"}, {name = "对象", type = "object"}},
        outputs = {{name = "执行", type = "exec"}},
        props = {},
        desc = "销毁对象",
    },
    Action_SetPos = {
        category = "action", color = Config.NODE_COLORS.action,
        inputs = {{name = "执行", type = "exec"}, {name = "对象", type = "object"}, {name = "X", type = "number"}, {name = "Y", type = "number"}},
        outputs = {{name = "执行", type = "exec"}},
        props = {},
        desc = "设置对象位置",
    },
    Action_SetScale = {
        category = "action", color = Config.NODE_COLORS.action,
        inputs = {{name = "执行", type = "exec"}, {name = "对象", type = "object"}, {name = "X", type = "number"}, {name = "Y", type = "number"}},
        outputs = {{name = "执行", type = "exec"}},
        props = {},
        desc = "设置对象缩放",
    },
    Action_SetRotation = {
        category = "action", color = Config.NODE_COLORS.action,
        inputs = {{name = "执行", type = "exec"}, {name = "对象", type = "object"}, {name = "角度", type = "number"}},
        outputs = {{name = "执行", type = "exec"}},
        props = {},
        desc = "设置对象旋转",
    },
    Action_PlaySound = {
        category = "action", color = Config.NODE_COLORS.action,
        inputs = {{name = "执行", type = "exec"}, {name = "路径", type = "string"}},
        outputs = {{name = "执行", type = "exec"}},
        props = {{name = "音效", type = "string", default = "sfx.ogg"}, {name = "音量", type = "number", default = 1.0}},
        desc = "播放音效",
    },
    Action_PlayAnimation = {
        category = "action", color = Config.NODE_COLORS.action,
        inputs = {{name = "执行", type = "exec"}, {name = "对象", type = "object"}, {name = "动画名", type = "string"}},
        outputs = {{name = "执行", type = "exec"}},
        props = {},
        desc = "播放动画",
    },
    Action_SpawnParticle = {
        category = "action", color = Config.NODE_COLORS.action,
        inputs = {{name = "执行", type = "exec"}, {name = "X", type = "number"}, {name = "Y", type = "number"}},
        outputs = {{name = "执行", type = "exec"}},
        props = {{name = "预设", type = "string", default = "explosion"}},
        desc = "生成粒子特效",
    },
    Action_LoadScene = {
        category = "action", color = Config.NODE_COLORS.action,
        inputs = {{name = "执行", type = "exec"}, {name = "场景名", type = "string"}},
        outputs = {{name = "执行", type = "exec"}},
        props = {},
        desc = "加载场景",
    },
    Action_Delay = {
        category = "action", color = Config.NODE_COLORS.action,
        inputs = {{name = "执行", type = "exec"}, {name = "秒数", type = "number"}},
        outputs = {{name = "执行", type = "exec"}},
        props = {{name = "延迟", type = "number", default = 1.0}},
        desc = "延迟执行",
    },
    Action_FadeScreen = {
        category = "action", color = Config.NODE_COLORS.action,
        inputs = {{name = "执行", type = "exec"}, {name = "透明度", type = "number"}, {name = "时长", type = "number"}},
        outputs = {{name = "执行", type = "exec"}},
        props = {{name = "颜色", type = "color", default = {0, 0, 0, 255}}},
        desc = "屏幕淡入淡出",
    },
    Action_SetVelocity = {
        category = "action", color = Config.NODE_COLORS.action,
        inputs = {{name = "执行", type = "exec"}, {name = "对象", type = "object"}, {name = "VX", type = "number"}, {name = "VY", type = "number"}},
        outputs = {{name = "执行", type = "exec"}},
        props = {},
        desc = "设置速度",
    },
    Action_ApplyForce = {
        category = "action", color = Config.NODE_COLORS.action,
        inputs = {{name = "执行", type = "exec"}, {name = "对象", type = "object"}, {name = "FX", type = "number"}, {name = "FY", type = "number"}},
        outputs = {{name = "执行", type = "exec"}},
        props = {},
        desc = "施加力",
    },

    -- === 条件节点 ===
    Condition_If = {
        category = "condition", color = Config.NODE_COLORS.condition,
        inputs = {{name = "执行", type = "exec"}, {name = "条件", type = "boolean"}},
        outputs = {{name = "True", type = "exec"}, {name = "False", type = "exec"}},
        props = {},
        desc = "条件分支",
    },
    Condition_Compare = {
        category = "condition", color = Config.NODE_COLORS.condition,
        inputs = {{name = "A", type = "number"}, {name = "B", type = "number"}},
        outputs = {{name = "结果", type = "boolean"}},
        props = {{name = "比较", type = "enum", default = "==", options = {"==", "!=", "<", ">", "<=", ">="}}},
        desc = "数值比较",
    },
    Condition_StringCompare = {
        category = "condition", color = Config.NODE_COLORS.condition,
        inputs = {{name = "A", type = "string"}, {name = "B", type = "string"}},
        outputs = {{name = "结果", type = "boolean"}},
        props = {{name = "比较", type = "enum", default = "==", options = {"==", "!=", "contains", "starts_with"}}},
        desc = "字符串比较",
    },
    Condition_And = {
        category = "condition", color = Config.NODE_COLORS.condition,
        inputs = {{name = "A", type = "boolean"}, {name = "B", type = "boolean"}},
        outputs = {{name = "结果", type = "boolean"}},
        props = {},
        desc = "逻辑与",
    },
    Condition_Or = {
        category = "condition", color = Config.NODE_COLORS.condition,
        inputs = {{name = "A", type = "boolean"}, {name = "B", type = "boolean"}},
        outputs = {{name = "结果", type = "boolean"}},
        props = {},
        desc = "逻辑或",
    },
    Condition_Not = {
        category = "condition", color = Config.NODE_COLORS.condition,
        inputs = {{name = "输入", type = "boolean"}},
        outputs = {{name = "结果", type = "boolean"}},
        props = {},
        desc = "逻辑非",
    },
    Condition_RandomChance = {
        category = "condition", color = Config.NODE_COLORS.condition,
        inputs = {{name = "概率", type = "number"}},
        outputs = {{name = "结果", type = "boolean"}},
        props = {{name = "百分比", type = "number", default = 50}},
        desc = "随机概率",
    },

    -- === 数学节点 ===
    Math_Add = {
        category = "math", color = Config.NODE_COLORS.math,
        inputs = {{name = "A", type = "number"}, {name = "B", type = "number"}},
        outputs = {{name = "结果", type = "number"}},
        props = {},
        desc = "加法",
    },
    Math_Sub = {
        category = "math", color = Config.NODE_COLORS.math,
        inputs = {{name = "A", type = "number"}, {name = "B", type = "number"}},
        outputs = {{name = "结果", type = "number"}},
        props = {},
        desc = "减法",
    },
    Math_Mul = {
        category = "math", color = Config.NODE_COLORS.math,
        inputs = {{name = "A", type = "number"}, {name = "B", type = "number"}},
        outputs = {{name = "结果", type = "number"}},
        props = {},
        desc = "乘法",
    },
    Math_Div = {
        category = "math", color = Config.NODE_COLORS.math,
        inputs = {{name = "A", type = "number"}, {name = "B", type = "number"}},
        outputs = {{name = "结果", type = "number"}},
        props = {},
        desc = "除法",
    },
    Math_Mod = {
        category = "math", color = Config.NODE_COLORS.math,
        inputs = {{name = "A", type = "number"}, {name = "B", type = "number"}},
        outputs = {{name = "结果", type = "number"}},
        props = {},
        desc = "取模",
    },
    Math_Pow = {
        category = "math", color = Config.NODE_COLORS.math,
        inputs = {{name = "底数", type = "number"}, {name = "指数", type = "number"}},
        outputs = {{name = "结果", type = "number"}},
        props = {},
        desc = "幂运算",
    },
    Math_Random = {
        category = "math", color = Config.NODE_COLORS.math,
        inputs = {{name = "最小", type = "number"}, {name = "最大", type = "number"}},
        outputs = {{name = "结果", type = "number"}},
        props = {},
        desc = "随机数",
    },
    Math_Clamp = {
        category = "math", color = Config.NODE_COLORS.math,
        inputs = {{name = "值", type = "number"}, {name = "最小", type = "number"}, {name = "最大", type = "number"}},
        outputs = {{name = "结果", type = "number"}},
        props = {},
        desc = "限制范围",
    },
    Math_Lerp = {
        category = "math", color = Config.NODE_COLORS.math,
        inputs = {{name = "A", type = "number"}, {name = "B", type = "number"}, {name = "T", type = "number"}},
        outputs = {{name = "结果", type = "number"}},
        props = {},
        desc = "线性插值",
    },
    Math_Distance = {
        category = "math", color = Config.NODE_COLORS.math,
        inputs = {{name = "X1", type = "number"}, {name = "Y1", type = "number"}, {name = "X2", type = "number"}, {name = "Y2", type = "number"}},
        outputs = {{name = "距离", type = "number"}},
        props = {},
        desc = "两点距离",
    },
    Math_Angle = {
        category = "math", color = Config.NODE_COLORS.math,
        inputs = {{name = "X1", type = "number"}, {name = "Y1", type = "number"}, {name = "X2", type = "number"}, {name = "Y2", type = "number"}},
        outputs = {{name = "角度", type = "number"}},
        props = {},
        desc = "两点角度",
    },
    Math_Sin = {
        category = "math", color = Config.NODE_COLORS.math,
        inputs = {{name = "角度", type = "number"}},
        outputs = {{name = "结果", type = "number"}},
        props = {},
        desc = "正弦",
    },
    Math_Cos = {
        category = "math", color = Config.NODE_COLORS.math,
        inputs = {{name = "角度", type = "number"}},
        outputs = {{name = "结果", type = "number"}},
        props = {},
        desc = "余弦",
    },
    Math_Abs = {
        category = "math", color = Config.NODE_COLORS.math,
        inputs = {{name = "值", type = "number"}},
        outputs = {{name = "结果", type = "number"}},
        props = {},
        desc = "绝对值",
    },
    Math_Floor = {
        category = "math", color = Config.NODE_COLORS.math,
        inputs = {{name = "值", type = "number"}},
        outputs = {{name = "结果", type = "number"}},
        props = {},
        desc = "向下取整",
    },

    -- === 变量节点 ===
    Variable_Get = {
        category = "variable", color = Config.NODE_COLORS.variable,
        inputs = {},
        outputs = {{name = "值", type = "any"}},
        props = {{name = "变量名", type = "string", default = "score"}},
        desc = "获取变量值",
    },
    Variable_Set = {
        category = "variable", color = Config.NODE_COLORS.variable,
        inputs = {{name = "执行", type = "exec"}, {name = "值", type = "any"}},
        outputs = {{name = "执行", type = "exec"}},
        props = {{name = "变量名", type = "string", default = "score"}},
        desc = "设置变量值",
    },
    Variable_Increment = {
        category = "variable", color = Config.NODE_COLORS.variable,
        inputs = {{name = "执行", type = "exec"}, {name = "增量", type = "number"}},
        outputs = {{name = "执行", type = "exec"}, {name = "新值", type = "number"}},
        props = {{name = "变量名", type = "string", default = "score"}},
        desc = "变量自增",
    },

    -- === 输入节点 ===
    Input_GetAxis = {
        category = "input", color = Config.NODE_COLORS.input,
        inputs = {},
        outputs = {{name = "X", type = "number"}, {name = "Y", type = "number"}},
        props = {},
        desc = "获取方向轴",
    },
    Input_GetMousePos = {
        category = "input", color = Config.NODE_COLORS.input,
        inputs = {},
        outputs = {{name = "X", type = "number"}, {name = "Y", type = "number"}},
        props = {},
        desc = "获取鼠标位置",
    },
    Input_IsKeyDown = {
        category = "input", color = Config.NODE_COLORS.input,
        inputs = {{name = "按键", type = "string"}},
        outputs = {{name = "按下", type = "boolean"}},
        props = {{name = "按键", type = "string", default = "Space"}},
        desc = "检测按键按下",
    },
    Input_IsMouseDown = {
        category = "input", color = Config.NODE_COLORS.input,
        inputs = {},
        outputs = {{name = "按下", type = "boolean"}},
        props = {{name = "按钮", type = "enum", default = "left", options = {"left", "right", "middle"}}},
        desc = "检测鼠标按下",
    },

    -- === 流程控制 ===
    Flow_Sequence = {
        category = "flow", color = Config.NODE_COLORS.flow,
        inputs = {{name = "执行", type = "exec"}},
        outputs = {{name = "Then", type = "exec"}, {name = "Then2", type = "exec"}, {name = "Then3", type = "exec"}},
        props = {},
        desc = "顺序执行",
    },
    Flow_ForLoop = {
        category = "flow", color = Config.NODE_COLORS.flow,
        inputs = {{name = "执行", type = "exec"}, {name = "起始", type = "number"}, {name = "结束", type = "number"}},
        outputs = {{name = "循环体", type = "exec"}, {name = "完成", type = "exec"}, {name = "索引", type = "number"}},
        props = {},
        desc = "For循环",
    },
    Flow_WhileLoop = {
        category = "flow", color = Config.NODE_COLORS.flow,
        inputs = {{name = "执行", type = "exec"}, {name = "条件", type = "boolean"}},
        outputs = {{name = "循环体", type = "exec"}, {name = "完成", type = "exec"}},
        props = {},
        desc = "While循环",
    },
    Flow_Break = {
        category = "flow", color = Config.NODE_COLORS.flow,
        inputs = {{name = "执行", type = "exec"}},
        outputs = {},
        props = {},
        desc = "跳出循环",
    },

    -- === 对象操作 ===
    Object_GetPosition = {
        category = "object", color = Config.NODE_COLORS.object,
        inputs = {{name = "对象", type = "object"}},
        outputs = {{name = "X", type = "number"}, {name = "Y", type = "number"}},
        props = {},
        desc = "获取对象位置",
    },
    Object_GetDistance = {
        category = "object", color = Config.NODE_COLORS.object,
        inputs = {{name = "对象A", type = "object"}, {name = "对象B", type = "object"}},
        outputs = {{name = "距离", type = "number"}},
        props = {},
        desc = "获取对象距离",
    },
    Object_FindByTag = {
        category = "object", color = Config.NODE_COLORS.object,
        inputs = {{name = "标签", type = "string"}},
        outputs = {{name = "对象", type = "object"}},
        props = {},
        desc = "按标签查找对象",
    },
    Object_SetVisible = {
        category = "object", color = Config.NODE_COLORS.object,
        inputs = {{name = "执行", type = "exec"}, {name = "对象", type = "object"}, {name = "可见", type = "boolean"}},
        outputs = {{name = "执行", type = "exec"}},
        props = {},
        desc = "设置对象可见性",
    },
    Object_SetTag = {
        category = "object", color = Config.NODE_COLORS.object,
        inputs = {{name = "执行", type = "exec"}, {name = "对象", type = "object"}, {name = "标签", type = "string"}},
        outputs = {{name = "执行", type = "exec"}},
        props = {},
        desc = "设置对象标签",
    },

    -- === 字符串操作 ===
    String_Concat = {
        category = "string", color = Config.NODE_COLORS.string,
        inputs = {{name = "A", type = "string"}, {name = "B", type = "string"}},
        outputs = {{name = "结果", type = "string"}},
        props = {},
        desc = "字符串拼接",
    },
    String_Format = {
        category = "string", color = Config.NODE_COLORS.string,
        inputs = {{name = "格式", type = "string"}, {name = "值", type = "any"}},
        outputs = {{name = "结果", type = "string"}},
        props = {{name = "格式", type = "string", default = "%d"}},
        desc = "字符串格式化",
    },
    String_Length = {
        category = "string", color = Config.NODE_COLORS.string,
        inputs = {{name = "字符串", type = "string"}},
        outputs = {{name = "长度", type = "number"}},
        props = {},
        desc = "字符串长度",
    },
    String_ToNumber = {
        category = "string", color = Config.NODE_COLORS.string,
        inputs = {{name = "字符串", type = "string"}},
        outputs = {{name = "数值", type = "number"}},
        props = {},
        desc = "字符串转数字",
    },

    -- === 注释节点 ===
    Comment = {
        category = "comment", color = Config.NODE_COLORS.comment,
        inputs = {},
        outputs = {},
        props = {{name = "文本", type = "string", default = "注释"}, {name = "宽度", type = "number", default = 200}, {name = "高度", type = "number", default = 60}},
        desc = "注释说明",
        isComment = true,
    },
}

-- ============================================================
-- 数据管理
-- ============================================================
NodeEditor._data = {nodes = {}, connections = {}, variables = {}, nextId = 1, selectedNodeId = nil, groups = {}}

function NodeEditor:init()
    self._data = {nodes = {}, connections = {}, variables = {}, nextId = 1, selectedNodeId = nil, groups = {}}
end

function NodeEditor:createNode(typeName, x, y)
    local def = self.NODE_TYPES[typeName]
    if not def then
        print("[NodeEditor] 未知节点类型: " .. tostring(typeName))
        return nil
    end
    local id = self._data.nextId
    self._data.nextId = id + 1
    local node = {
        id = id,
        type = typeName,
        x = x or 100,
        y = y or 100,
        w = def.isComment and (def.props[2] and def.props[2].default or 200) or 160,
        h = def.isComment and (def.props[3] and def.props[3].default or 60) or (40 + math.max(#def.inputs, #def.outputs) * 24),
        inputs = {},
        outputs = {},
        props = {},
        comment = def.isComment or false,
        desc = def.desc or "",
        category = def.category or "action",
    }
    for i, inp in ipairs(def.inputs) do
        node.inputs[i] = {name = inp.name, type = inp.type, value = nil, connected = false}
    end
    for i, out in ipairs(def.outputs) do
        node.outputs[i] = {name = out.name, type = out.type}
    end
    for _, p in ipairs(def.props) do
        node.props[p.name] = Config.deepcopy(p.default)
    end
    self._data.nodes[id] = node
    UndoManager:record("create_node", {node = Config.deepcopy(node)})
    EventBus:emit("node.created", node)
    return node
end

function NodeEditor:deleteNode(id)
    if not self._data.nodes[id] then return false end
    UndoManager:record("delete_node", {node = Config.deepcopy(self._data.nodes[id])})
    local newConns = {}
    for _, c in ipairs(self._data.connections) do
        if c.fromId ~= id and c.toId ~= id then
            table.insert(newConns, c)
        end
    end
    self._data.connections = newConns
    self._data.nodes[id] = nil
    if self._data.selectedNodeId == id then
        self._data.selectedNodeId = nil
    end
    EventBus:emit("node.deleted", id)
    return true
end

function NodeEditor:connect(fromId, fromPort, toId, toPort)
    local fromNode = self._data.nodes[fromId]
    local toNode = self._data.nodes[toId]
    if not fromNode or not toNode then return false end
    if not fromNode.outputs[fromPort] or not toNode.inputs[toPort] then return false end
    local fromType = fromNode.outputs[fromPort].type
    local toType = toNode.inputs[toPort].type
    if fromType ~= toType and fromType ~= "any" and toType ~= "any" and fromType ~= "exec" then
        return false
    end
    -- 移除目标端口已有连接（单输入端口）
    local newConns = {}
    for _, c in ipairs(self._data.connections) do
        if not (c.toId == toId and c.toPort == toPort) then
            table.insert(newConns, c)
        end
    end
    table.insert(newConns, {fromId = fromId, fromPort = fromPort, toId = toId, toPort = toPort})
    self._data.connections = newConns
    toNode.inputs[toPort].connected = true
    UndoManager:record("connect", {fromId = fromId, fromPort = fromPort, toId = toId, toPort = toPort})
    EventBus:emit("node.connected", fromId, toId)
    return true
end

function NodeEditor:disconnect(toId, toPort)
    local newConns = {}
    local removed = nil
    for _, c in ipairs(self._data.connections) do
        if c.toId == toId and c.toPort == toPort then
            removed = Config.deepcopy(c)
        else
            table.insert(newConns, c)
        end
    end
    if removed then
        self._data.connections = newConns
        local toNode = self._data.nodes[toId]
        if toNode and toNode.inputs[toPort] then
            toNode.inputs[toPort].connected = false
        end
        UndoManager:record("disconnect", {conn = removed})
        return true
    end
    return false
end

function NodeEditor:selectNode(id)
    self._data.selectedNodeId = id
end

function NodeEditor:getSelectedNode()
    if self._data.selectedNodeId then
        return self._data.nodes[self._data.selectedNodeId]
    end
    return nil
end

function NodeEditor:getAllNodes()
    local list = {}
    for _, node in pairs(self._data.nodes) do
        table.insert(list, node)
    end
    return list
end

function NodeEditor:getConnections()
    return self._data.connections
end

function NodeEditor:getNodeCount()
    local count = 0
    for _ in pairs(self._data.nodes) do count = count + 1 end
    return count
end

function NodeEditor:hitTestNode(px, py)
    for _, node in pairs(self._data.nodes) do
        if Config.pointInRect(px, py, node.x, node.y, node.w, node.h) then
            return node
        end
    end
    return nil
end

function NodeEditor:getNodeById(id)
    return self._data.nodes[id]
end

function NodeEditor:hitTestPort(px, py)
    local PORT_RADIUS = 8
    local PORT_SPACING = 24
    for _, node in pairs(self._data.nodes) do
        if node.inputs then
            for i, _ in ipairs(node.inputs) do
                local portX = node.x
                local portY = node.y + 30 + (i - 1) * PORT_SPACING
                if Config.pointInCircle(px, py, portX, portY, PORT_RADIUS) then
                    return { nodeId = node.id, portIdx = i, isOutput = false }
                end
            end
        end
        if node.outputs then
            for i, _ in ipairs(node.outputs) do
                local portX = node.x + (node.w or 160)
                local portY = node.y + 30 + (i - 1) * PORT_SPACING
                if Config.pointInCircle(px, py, portX, portY, PORT_RADIUS) then
                    return { nodeId = node.id, portIdx = i, isOutput = true }
                end
            end
        end
    end
    return nil
end

function NodeEditor:getCategories()
    local cats = {}
    local order = {"event", "action", "condition", "math", "variable", "input", "flow", "object", "string", "comment"}
    for typeName, def in pairs(self.NODE_TYPES) do
        local cat = def.category or "其他"
        if not cats[cat] then cats[cat] = {} end
        table.insert(cats[cat], typeName)
    end
    -- 返回有序的类别
    local result = {}
    for _, cat in ipairs(order) do
        if cats[cat] then
            result[cat] = cats[cat]
        end
    end
    for cat, list in pairs(cats) do
        if not result[cat] then
            result[cat] = list
        end
    end
    return result
end

-- 获取类别名称映射
function NodeEditor:getCategoryNames()
    return {
        event = "事件",
        action = "动作",
        condition = "条件",
        math = "数学",
        variable = "变量",
        input = "输入",
        flow = "流程",
        object = "对象",
        string = "字符串",
        comment = "注释",
    }
end

-- ============================================================
-- 序列化
-- ============================================================
function NodeEditor:serialize()
    return {
        version = Config.VERSION,
        nodes = Config.deepcopy(self._data.nodes),
        connections = Config.deepcopy(self._data.connections),
        variables = Config.deepcopy(self._data.variables),
        nextId = self._data.nextId,
        groups = Config.deepcopy(self._data.groups),
    }
end

function NodeEditor:deserialize(data)
    if not data then return false end
    self._data.nodes = data.nodes or {}
    self._data.connections = data.connections or {}
    self._data.variables = data.variables or {}
    self._data.nextId = data.nextId or 1
    self._data.groups = data.groups or {}
    self._data.selectedNodeId = nil
    EventBus:emit("node.loaded")
    return true
end

-- ============================================================
-- 增强编译器：节点图 -> Lua代码（支持数据流）
-- ============================================================
function NodeEditor:compileToLua()
    local code = {}
    table.insert(code, "-- ============================================")
    table.insert(code, "-- 由 Visual2D IDE 节点编辑器自动生成 v" .. Config.VERSION)
    table.insert(code, "-- 生成时间: " .. os.date("%Y-%m-%d %H:%M:%S"))
    table.insert(code, "-- ============================================")
    table.insert(code, "")
    table.insert(code, "local NodeGraph = {}")
    table.insert(code, "NodeGraph._vars = {}")
    table.insert(code, "NodeGraph._timers = {}")
    table.insert(code, "")

    -- 收集所有变量
    local vars = {}
    for _, node in pairs(self._data.nodes) do
        if node.type == "Variable_Set" or node.type == "Variable_Get" or node.type == "Variable_Increment" then
            local varName = node.props["变量名"] or "temp"
            vars[varName] = true
        end
    end
    if next(vars) then
        table.insert(code, "-- 变量初始化")
        for name, _ in pairs(vars) do
            table.insert(code, string.format("NodeGraph._vars[%q] = 0", name))
        end
        table.insert(code, "")
    end

    -- 收集事件节点并编译
    local eventNodes = {}
    for _, node in pairs(self._data.nodes) do
        if node.type:sub(1, 6) == "Event_" then
            table.insert(eventNodes, node)
        end
    end

    for _, eventNode in ipairs(eventNodes) do
        self:_compileEventHandler(eventNode, code)
    end

    table.insert(code, "")
    table.insert(code, "return NodeGraph")

    return table.concat(code, "\n")
end

function NodeEditor:_compileEventHandler(node, code)
    if node.type == "Event_Start" then
        table.insert(code, "-- 游戏开始")
        table.insert(code, "function NodeGraph.OnGameStart()")
        self:_compileNodeChain(node, 1, code, 1)
        table.insert(code, "end")
    elseif node.type == "Event_Tick" then
        table.insert(code, "-- 每帧更新")
        table.insert(code, "function NodeGraph.OnUpdate(dt)")
        table.insert(code, "  NodeGraph._vars._dt = dt")
        self:_compileNodeChain(node, 1, code, 1)
        table.insert(code, "end")
    elseif node.type == "Event_KeyPress" then
        local key = node.props["按键"] or "Space"
        table.insert(code, string.format("-- 按键: %s", key))
        table.insert(code, string.format("function NodeGraph.OnKeyPress_%s()", key))
        self:_compileNodeChain(node, 1, code, 1)
        table.insert(code, "end")
    elseif node.type == "Event_KeyRelease" then
        local key = node.props["按键"] or "Space"
        table.insert(code, string.format("-- 按键释放: %s", key))
        table.insert(code, string.format("function NodeGraph.OnKeyRelease_%s()", key))
        self:_compileNodeChain(node, 1, code, 1)
        table.insert(code, "end")
    elseif node.type == "Event_Timer" then
        local interval = node.props["间隔"] or 1.0
        local loop = node.props["循环"] ~= false
        table.insert(code, string.format("-- 定时器 (间隔 %.1fs, 循环=%s)", interval, tostring(loop)))
        table.insert(code, string.format("function NodeGraph.OnTimer_%d()", node.id))
        self:_compileNodeChain(node, 1, code, 1)
        table.insert(code, "end")
        table.insert(code, string.format("table.insert(NodeGraph._timers, {interval=%.2f, loop=%s, elapsed=0, fn=NodeGraph.OnTimer_%d})", interval, tostring(loop), node.id))
    elseif node.type == "Event_Collision" then
        local tag = node.props["标签"] or ""
        table.insert(code, string.format('-- 碰撞事件 (标签: "%s")', tag))
        table.insert(code, string.format("function NodeGraph.OnCollision_%d(other)", node.id))
        self:_compileNodeChain(node, 1, code, 1)
        table.insert(code, "end")
    elseif node.type == "Event_MouseClick" then
        local btn = node.props["按钮"] or "left"
        table.insert(code, string.format('-- 鼠标点击 (%s)', btn))
        table.insert(code, string.format("function NodeGraph.OnMouseClick_%s(x, y)", btn))
        self:_compileNodeChain(node, 1, code, 1)
        table.insert(code, "end")
    end
    table.insert(code, "")
end

function NodeEditor:_compileNodeChain(fromNode, fromPort, code, indent)
    for _, conn in ipairs(self._data.connections) do
        if conn.fromId == fromNode.id and conn.fromPort == fromPort then
            local nextNode = self._data.nodes[conn.toId]
            if nextNode then
                self:_compileNodeBody(nextNode, code, indent)
            end
        end
    end
end

function NodeEditor:_compileDataFlow(node, outputPort)
    local T = node.type
    if T == "Variable_Get" then
        local varName = node.props["变量名"] or "temp"
        return string.format('(NodeGraph._vars[%q] or 0)', varName)
    elseif T == "Math_Add" then
        local a = self:_getInputExpression(node, 1, "0")
        local b = self:_getInputExpression(node, 2, "0")
        return string.format("(%s + %s)", a, b)
    elseif T == "Math_Sub" then
        local a = self:_getInputExpression(node, 1, "0")
        local b = self:_getInputExpression(node, 2, "0")
        return string.format("(%s - %s)", a, b)
    elseif T == "Math_Mul" then
        local a = self:_getInputExpression(node, 1, "0")
        local b = self:_getInputExpression(node, 2, "0")
        return string.format("(%s * %s)", a, b)
    elseif T == "Math_Div" then
        local a = self:_getInputExpression(node, 1, "0")
        local b = self:_getInputExpression(node, 2, "1")
        return string.format("(%s / %s)", a, b)
    elseif T == "Math_Mod" then
        local a = self:_getInputExpression(node, 1, "0")
        local b = self:_getInputExpression(node, 2, "1")
        return string.format("(%s %% %s)", a, b)
    elseif T == "Math_Random" then
        local min = self:_getInputExpression(node, 1, "0")
        local max = self:_getInputExpression(node, 2, "100")
        return string.format("math.random(%s, %s)", min, max)
    elseif T == "Math_Clamp" then
        local v = self:_getInputExpression(node, 1, "0")
        local mn = self:_getInputExpression(node, 2, "0")
        local mx = self:_getInputExpression(node, 3, "1")
        return string.format("math.max(%s, math.min(%s, %s))", mn, mx, v)
    elseif T == "Math_Lerp" then
        local a = self:_getInputExpression(node, 1, "0")
        local b = self:_getInputExpression(node, 2, "1")
        local t = self:_getInputExpression(node, 3, "0.5")
        return string.format("(%s + (%s - %s) * %s)", a, b, a, t)
    elseif T == "Math_Distance" then
        local x1 = self:_getInputExpression(node, 1, "0")
        local y1 = self:_getInputExpression(node, 2, "0")
        local x2 = self:_getInputExpression(node, 3, "0")
        local y2 = self:_getInputExpression(node, 4, "0")
        return string.format("math.sqrt((%s-%s)^2 + (%s-%s)^2)", x2, x1, y2, y1)
    elseif T == "Math_Sin" then
        local a = self:_getInputExpression(node, 1, "0")
        return string.format("math.sin(math.rad(%s))", a)
    elseif T == "Math_Cos" then
        local a = self:_getInputExpression(node, 1, "0")
        return string.format("math.cos(math.rad(%s))", a)
    elseif T == "Math_Abs" then
        local v = self:_getInputExpression(node, 1, "0")
        return string.format("math.abs(%s)", v)
    elseif T == "Math_Floor" then
        local v = self:_getInputExpression(node, 1, "0")
        return string.format("math.floor(%s)", v)
    elseif T == "Math_Angle" then
        local x1 = self:_getInputExpression(node, 1, "0")
        local y1 = self:_getInputExpression(node, 2, "0")
        local x2 = self:_getInputExpression(node, 3, "0")
        local y2 = self:_getInputExpression(node, 4, "0")
        return string.format("math.deg(math.atan(%s-%s, %s-%s))", y2, y1, x2, x1)
    elseif T == "Condition_Compare" then
        local a = self:_getInputExpression(node, 1, "0")
        local b = self:_getInputExpression(node, 2, "0")
        local op = node.props["比较"] or "=="
        if op == "!=" then op = "~=" end
        return string.format("(%s %s %s)", a, op, b)
    elseif T == "Condition_And" then
        local a = self:_getInputExpression(node, 1, "true")
        local b = self:_getInputExpression(node, 2, "true")
        return string.format("(%s and %s)", a, b)
    elseif T == "Condition_Or" then
        local a = self:_getInputExpression(node, 1, "false")
        local b = self:_getInputExpression(node, 2, "false")
        return string.format("(%s or %s)", a, b)
    elseif T == "Condition_Not" then
        local a = self:_getInputExpression(node, 1, "true")
        return string.format("(not %s)", a)
    elseif T == "Condition_RandomChance" then
        local pct = self:_getInputExpression(node, 1, tostring(node.props["百分比"] or 50))
        return string.format("(math.random(100) <= %s)", pct)
    elseif T == "Input_GetAxis" then
        if outputPort == 1 then return "getAxisX()" end
        return "getAxisY()"
    elseif T == "Input_GetMousePos" then
        if outputPort == 1 then return "getMouseX()" end
        return "getMouseY()"
    elseif T == "Input_IsKeyDown" then
        local key = node.props["按键"] or "Space"
        return string.format('isKeyDown("%s")', key)
    elseif T == "String_Concat" then
        local a = self:_getInputExpression(node, 1, '""')
        local b = self:_getInputExpression(node, 2, '""')
        return string.format("(%s .. %s)", a, b)
    elseif T == "String_Length" then
        local s = self:_getInputExpression(node, 1, '""')
        return string.format("#(%s)", s)
    elseif T == "String_ToNumber" then
        local s = self:_getInputExpression(node, 1, '"0"')
        return string.format("tonumber(%s) or 0", s)
    elseif T == "Object_GetPosition" then
        if outputPort == 1 then return "getObjX(obj)" end
        return "getObjY(obj)"
    end
    return "0"
end

function NodeEditor:_getInputExpression(node, portIdx, defaultVal)
    for _, conn in ipairs(self._data.connections) do
        if conn.toId == node.id and conn.toPort == portIdx then
            local srcNode = self._data.nodes[conn.fromId]
            if srcNode then
                return self:_compileDataFlow(srcNode, conn.fromPort)
            end
        end
    end
    return defaultVal or "0"
end

function NodeEditor:_compileNodeBody(node, code, indent)
    local prefix = string.rep("  ", indent)
    local T = node.type

    local function getInputValue(portIdx, defaultVal)
        return self:_getInputExpression(node, portIdx, defaultVal)
    end

    if T == "Action_Log" then
        local text = getInputValue(2, '"' .. (node.props["文本"] or "Hello") .. '"')
        table.insert(code, prefix .. string.format('print(%s)', text))
        self:_compileNodeChain(node, 1, code, indent)
    elseif T == "Action_CreateUnit" then
        local unitType = getInputValue(2, '"sprite"')
        local x = getInputValue(3, "0")
        local y = getInputValue(4, "0")
        table.insert(code, prefix .. string.format('local unit_%d = createUnit(%s, %s, %s)', node.id, unitType, x, y))
        self:_compileNodeChain(node, 1, code, indent)
    elseif T == "Action_DestroyUnit" then
        local obj = getInputValue(2, "nil")
        table.insert(code, prefix .. string.format('if %s then %s:Destroy() end', obj, obj))
        self:_compileNodeChain(node, 1, code, indent)
    elseif T == "Action_SetPos" then
        local obj = getInputValue(2, "nil")
        local x = getInputValue(3, "0")
        local y = getInputValue(4, "0")
        table.insert(code, prefix .. string.format('if %s then %s:SetPosition(%s, %s) end', obj, obj, x, y))
        self:_compileNodeChain(node, 1, code, indent)
    elseif T == "Action_SetScale" then
        local obj = getInputValue(2, "nil")
        local x = getInputValue(3, "1")
        local y = getInputValue(4, "1")
        table.insert(code, prefix .. string.format('if %s then %s:SetScale(%s, %s) end', obj, obj, x, y))
        self:_compileNodeChain(node, 1, code, indent)
    elseif T == "Action_SetRotation" then
        local obj = getInputValue(2, "nil")
        local angle = getInputValue(3, "0")
        table.insert(code, prefix .. string.format('if %s then %s:SetRotation(%s) end', obj, obj, angle))
        self:_compileNodeChain(node, 1, code, indent)
    elseif T == "Action_PlaySound" then
        local path = getInputValue(2, '"' .. (node.props["音效"] or "sfx.ogg") .. '"')
        local vol = node.props["音量"] or 1.0
        table.insert(code, prefix .. string.format('playSound(%s, %.1f)', path, vol))
        self:_compileNodeChain(node, 1, code, indent)
    elseif T == "Action_PlayAnimation" then
        local obj = getInputValue(2, "nil")
        local anim = getInputValue(3, '"idle"')
        table.insert(code, prefix .. string.format('if %s then %s:PlayAnimation(%s) end', obj, obj, anim))
        self:_compileNodeChain(node, 1, code, indent)
    elseif T == "Action_SpawnParticle" then
        local x = getInputValue(2, "0")
        local y = getInputValue(3, "0")
        local preset = node.props["预设"] or "explosion"
        table.insert(code, prefix .. string.format('spawnParticle("%s", %s, %s)', preset, x, y))
        self:_compileNodeChain(node, 1, code, indent)
    elseif T == "Action_LoadScene" then
        local sceneName = getInputValue(2, '"main"')
        table.insert(code, prefix .. string.format('loadScene(%s)', sceneName))
        self:_compileNodeChain(node, 1, code, indent)
    elseif T == "Action_Delay" then
        local seconds = getInputValue(2, tostring(node.props["延迟"] or 1.0))
        table.insert(code, prefix .. 'coroutine.wrap(function()')
        table.insert(code, prefix .. string.format('  wait(%s)', seconds))
        self:_compileNodeChain(node, 1, code, indent + 1)
        table.insert(code, prefix .. 'end)()')
    elseif T == "Action_FadeScreen" then
        local alpha = getInputValue(2, "1")
        local dur = getInputValue(3, "1")
        table.insert(code, prefix .. string.format('fadeScreen(%s, %s)', alpha, dur))
        self:_compileNodeChain(node, 1, code, indent)
    elseif T == "Action_SetVelocity" then
        local obj = getInputValue(2, "nil")
        local vx = getInputValue(3, "0")
        local vy = getInputValue(4, "0")
        table.insert(code, prefix .. string.format('if %s then %s:SetVelocity(%s, %s) end', obj, obj, vx, vy))
        self:_compileNodeChain(node, 1, code, indent)
    elseif T == "Action_ApplyForce" then
        local obj = getInputValue(2, "nil")
        local fx = getInputValue(3, "0")
        local fy = getInputValue(4, "0")
        table.insert(code, prefix .. string.format('if %s then %s:ApplyForce(%s, %s) end', obj, obj, fx, fy))
        self:_compileNodeChain(node, 1, code, indent)
    elseif T == "Condition_If" then
        local cond = getInputValue(2, "false")
        table.insert(code, prefix .. string.format('if %s then', cond))
        self:_compileNodeChain(node, 1, code, indent + 1)
        table.insert(code, prefix .. 'else')
        self:_compileNodeChain(node, 2, code, indent + 1)
        table.insert(code, prefix .. 'end')
    elseif T == "Variable_Set" then
        local varName = node.props["变量名"] or "temp"
        local val = getInputValue(2, "0")
        table.insert(code, prefix .. string.format('NodeGraph._vars[%q] = %s', varName, val))
        self:_compileNodeChain(node, 1, code, indent)
    elseif T == "Variable_Increment" then
        local varName = node.props["变量名"] or "temp"
        local delta = getInputValue(2, "1")
        table.insert(code, prefix .. string.format('NodeGraph._vars[%q] = (NodeGraph._vars[%q] or 0) + %s', varName, varName, delta))
        self:_compileNodeChain(node, 1, code, indent)
    elseif T == "Flow_Sequence" then
        self:_compileNodeChain(node, 1, code, indent)
        self:_compileNodeChain(node, 2, code, indent)
        self:_compileNodeChain(node, 3, code, indent)
    elseif T == "Flow_ForLoop" then
        local start = getInputValue(2, "1")
        local finish = getInputValue(3, "10")
        table.insert(code, prefix .. string.format('for i_%d = %s, %s do', node.id, start, finish))
        self:_compileNodeChain(node, 1, code, indent + 1)
        table.insert(code, prefix .. 'end')
        self:_compileNodeChain(node, 2, code, indent)
    elseif T == "Flow_WhileLoop" then
        local cond = getInputValue(2, "false")
        table.insert(code, prefix .. string.format('while %s do', cond))
        self:_compileNodeChain(node, 1, code, indent + 1)
        table.insert(code, prefix .. 'end')
        self:_compileNodeChain(node, 2, code, indent)
    elseif T == "Flow_Break" then
        table.insert(code, prefix .. 'break')
    elseif T == "Object_SetVisible" then
        local obj = getInputValue(2, "nil")
        local vis = getInputValue(3, "true")
        table.insert(code, prefix .. string.format('if %s then %s:SetVisible(%s) end', obj, obj, vis))
        self:_compileNodeChain(node, 1, code, indent)
    elseif T == "Object_SetTag" then
        local obj = getInputValue(2, "nil")
        local tag = getInputValue(3, '""')
        table.insert(code, prefix .. string.format('if %s then %s:SetTag(%s) end', obj, obj, tag))
        self:_compileNodeChain(node, 1, code, indent)
    end
end

return NodeEditor
