-- ============================================================
-- IDE/ComponentSystem.lua - 组件系统
-- 功能: 为场景对象挂载逻辑组件、属性绑定、生命周期管理
-- ============================================================
local Config = require("IDE.Config")
local EventBus = require("IDE.EventBus")

local ComponentSystem = {}

-- 组件类型定义
ComponentSystem.COMPONENT_TYPES = {
  SpriteRenderer = {
    name = "精灵渲染器",
    category = "渲染",
    icon = "🎨",
    properties = {
      { name = "imagePath", display = "图片路径", type = "asset", default = "", assetType = "image" },
      { name = "color", display = "颜色", type = "color", default = {255, 255, 255, 255} },
      { name = "flipX", display = "水平翻转", type = "boolean", default = false },
      { name = "flipY", display = "垂直翻转", type = "boolean", default = false },
      { name = "sortingOrder", display = "排序层级", type = "number", default = 0 },
    },
  },
  Animator = {
    name = "动画器",
    category = "动画",
    icon = "🎬",
    properties = {
      { name = "animationName", display = "当前动画", type = "string", default = "idle" },
      { name = "speed", display = "播放速度", type = "number", default = 1.0 },
      { name = "loop", display = "循环播放", type = "boolean", default = true },
      { name = "playOnStart", display = "启动时播放", type = "boolean", default = true },
    },
  },
  Rigidbody = {
    name = "刚体",
    category = "物理",
    icon = "⚙",
    properties = {
      { name = "mass", display = "质量", type = "number", default = 1.0 },
      { name = "gravity", display = "重力", type = "number", default = 980 },
      { name = "friction", display = "摩擦力", type = "number", default = 0.3 },
      { name = "bounce", display = "弹性", type = "number", default = 0.0 },
      { name = "isStatic", display = "静态", type = "boolean", default = false },
      { name = "isTrigger", display = "触发器", type = "boolean", default = false },
    },
  },
  Collider = {
    name = "碰撞器",
    category = "物理",
    icon = "🔲",
    properties = {
      { name = "shape", display = "形状", type = "enum", default = "box", options = {"box", "circle", "polygon"} },
      { name = "offsetX", display = "偏移X", type = "number", default = 0 },
      { name = "offsetY", display = "偏移Y", type = "number", default = 0 },
      { name = "width", display = "宽度", type = "number", default = 64 },
      { name = "height", display = "高度", type = "number", default = 64 },
      { name = "radius", display = "半径", type = "number", default = 32 },
    },
  },
  Script = {
    name = "脚本",
    category = "逻辑",
    icon = "📜",
    properties = {
      { name = "scriptPath", display = "脚本路径", type = "asset", default = "", assetType = "script" },
      { name = "enabled", display = "启用", type = "boolean", default = true },
    },
  },
  AudioSource = {
    name = "音频源",
    category = "音频",
    icon = "🔊",
    properties = {
      { name = "clip", display = "音频剪辑", type = "asset", default = "", assetType = "audio" },
      { name = "volume", display = "音量", type = "number", default = 1.0, min = 0, max = 1 },
      { name = "pitch", display = "音调", type = "number", default = 1.0, min = 0.1, max = 3 },
      { name = "loop", display = "循环", type = "boolean", default = false },
      { name = "playOnStart", display = "启动时播放", type = "boolean", default = false },
      { name = "spatial", display = "空间音效", type = "boolean", default = false },
    },
  },
  ParticleSystem = {
    name = "粒子系统",
    category = "特效",
    icon = "✨",
    properties = {
      { name = "maxParticles", display = "最大粒子数", type = "number", default = 100 },
      { name = "emissionRate", display = "发射速率", type = "number", default = 10 },
      { name = "lifetime", display = "生命周期", type = "number", default = 1.0 },
      { name = "startColor", display = "起始颜色", type = "color", default = {255, 255, 255, 255} },
      { name = "endColor", display = "结束颜色", type = "color", default = {255, 255, 255, 0} },
      { name = "startSize", display = "起始大小", type = "number", default = 10 },
      { name = "endSize", display = "结束大小", type = "number", default = 0 },
      { name = "speed", display = "速度", type = "number", default = 50 },
      { name = "gravity", display = "重力", type = "number", default = -100 },
    },
  },
  Camera = {
    name = "相机",
    category = "渲染",
    icon = "📷",
    properties = {
      { name = "zoom", display = "缩放", type = "number", default = 1.0 },
      { name = "followTarget", display = "跟随目标", type = "string", default = "" },
      { name = "smoothSpeed", display = "平滑速度", type = "number", default = 5.0 },
      { name = "bounds", display = "边界限制", type = "boolean", default = false },
      { name = "minX", display = "最小X", type = "number", default = 0 },
      { name = "maxX", display = "最大X", type = "number", default = 10000 },
      { name = "minY", display = "最小Y", type = "number", default = 0 },
      { name = "maxY", display = "最大Y", type = "number", default = 10000 },
    },
  },
  UIElement = {
    name = "UI元素",
    category = "UI",
    icon = "🖱",
    properties = {
      { name = "text", display = "文本", type = "string", default = "" },
      { name = "fontSize", display = "字体大小", type = "number", default = 16 },
      { name = "fontColor", display = "字体颜色", type = "color", default = {255, 255, 255, 255} },
      { name = "backgroundColor", display = "背景颜色", type = "color", default = {0, 0, 0, 0} },
      { name = "borderWidth", display = "边框宽度", type = "number", default = 0 },
      { name = "borderColor", display = "边框颜色", type = "color", default = {255, 255, 255, 255} },
      { name = "cornerRadius", display = "圆角半径", type = "number", default = 0 },
      { name = "interactive", display = "可交互", type = "boolean", default = true },
    },
  },
  TileMapRenderer = {
    name = "瓦片地图渲染器",
    category = "渲染",
    icon = "🗺",
    properties = {
      { name = "tileSet", display = "瓦片集", type = "asset", default = "", assetType = "image" },
      { name = "tileWidth", display = "瓦片宽度", type = "number", default = 32 },
      { name = "tileHeight", display = "瓦片高度", type = "number", default = 32 },
      { name = "mapData", display = "地图数据", type = "string", default = "" },
      { name = "collision", display = "启用碰撞", type = "boolean", default = true },
    },
  },
}

-- 为对象添加组件
function ComponentSystem:AddComponent(obj, componentType)
  if not self.COMPONENT_TYPES[componentType] then
    print("[ComponentSystem] 未知组件类型: " .. tostring(componentType))
    return nil
  end

  obj.components = obj.components or {}

  -- 检查是否已存在同类型组件
  for _, comp in ipairs(obj.components) do
    if comp.type == componentType then
      print("[ComponentSystem] 对象已包含 " .. componentType)
      return comp
    end
  end

  local def = self.COMPONENT_TYPES[componentType]
  local comp = {
    id = Config.generateId("comp"),
    type = componentType,
    name = def.name,
    category = def.category,
    enabled = true,
    properties = {},
  }

  -- 初始化默认值
  for _, prop in ipairs(def.properties) do
    comp.properties[prop.name] = Config.deepcopy(prop.default)
  end

  table.insert(obj.components, comp)
  EventBus:emit("component.added", obj.id, comp)
  return comp
end

-- 移除组件
function ComponentSystem:RemoveComponent(obj, componentId)
  if not obj.components then return false end
  for i, comp in ipairs(obj.components) do
    if comp.id == componentId then
      table.remove(obj.components, i)
      EventBus:emit("component.removed", obj.id, comp)
      return true
    end
  end
  return false
end

-- 获取组件
function ComponentSystem:GetComponent(obj, componentType)
  if not obj.components then return nil end
  for _, comp in ipairs(obj.components) do
    if comp.type == componentType then return comp end
  end
  return nil
end

-- 获取所有组件
function ComponentSystem:GetAllComponents(obj)
  return obj.components or {}
end

-- 设置组件属性
function ComponentSystem:SetProperty(obj, componentId, propName, value)
  if not obj.components then return false end
  for _, comp in ipairs(obj.components) do
    if comp.id == componentId then
      local oldValue = comp.properties[propName]
      comp.properties[propName] = value
      EventBus:emit("component.property_changed", obj.id, componentId, propName, oldValue, value)
      return true
    end
  end
  return false
end

-- 获取组件属性定义
function ComponentSystem:GetPropertyDef(componentType, propName)
  local def = self.COMPONENT_TYPES[componentType]
  if not def then return nil end
  for _, prop in ipairs(def.properties) do
    if prop.name == propName then return prop end
  end
  return nil
end

-- 获取组件类型列表（按分类）
function ComponentSystem:GetTypesByCategory()
  local cats = {}
  for typeName, def in pairs(self.COMPONENT_TYPES) do
    local cat = def.category or "其他"
    if not cats[cat] then cats[cat] = {} end
    table.insert(cats[cat], { type = typeName, name = def.name, icon = def.icon })
  end
  return cats
end

-- 导出组件为 Lua 代码
function ComponentSystem:ExportComponent(comp)
  local def = self.COMPONENT_TYPES[comp.type]
  if not def then return "" end

  local lines = {}
  table.insert(lines, string.format("  -- %s", def.name))
  table.insert(lines, string.format('  local %s = node:AddComponent("%s")', comp.type, comp.type))

  for _, propDef in ipairs(def.properties) do
    local val = comp.properties[propDef.name]
    if val ~= nil and val ~= propDef.default then
      local valStr
      if type(val) == "string" then
        valStr = '"' .. val .. '"'
      elseif type(val) == "boolean" then
        valStr = val and "true" or "false"
      elseif type(val) == "table" then
        valStr = "{" .. table.concat(val, ", ") .. "}"
      else
        valStr = tostring(val)
      end
      table.insert(lines, string.format("  %s.%s = %s", comp.type, propDef.name, valStr))
    end
  end

  return table.concat(lines, "\n")
end

-- 序列化
function ComponentSystem:Serialize(obj)
  if not obj.components then return {} end
  return Config.deepcopy(obj.components)
end

function ComponentSystem:Deserialize(obj, data)
  obj.components = {}
  for _, compData in ipairs(data or {}) do
    local comp = {
      id = compData.id or Config.generateId("comp"),
      type = compData.type,
      name = compData.name,
      category = compData.category,
      enabled = compData.enabled ~= false,
      properties = Config.deepcopy(compData.properties or {}),
    }
    table.insert(obj.components, comp)
  end
end

return ComponentSystem
