-- ============================================================
-- IDE/Console.lua - 控制台系统
-- 功能: 日志捕获、命令执行、历史记录、自动补全
-- ============================================================
local Config = require("IDE.Config")
local EventBus = require("IDE.EventBus")

local Console = {}

Console._logs = {}
Console._max_logs = 500
Console._commands = {}
Console._history = {}
Console._history_index = 0
Console._input_text = ""
Console._scroll_y = 0
Console._auto_scroll = true
Console._filter = "all" -- all | error | warn | info | log
Console._visible = false

-- 日志级别
Console.LEVELS = {
  error = { name = "ERR", color = {255, 100, 100, 255}, priority = 4 },
  warn  = { name = "WRN", color = {255, 200, 100, 255}, priority = 3 },
  info  = { name = "INF", color = {100, 180, 255, 255}, priority = 2 },
  log   = { name = "LOG", color = {200, 200, 200, 255}, priority = 1 },
  debug = { name = "DBG", color = {150, 150, 150, 255}, priority = 0 },
}

-- 初始化：劫持全局 print
function Console:init()
  self._logs = {}
  self._history = {}
  self._history_index = 0
  self._input_text = ""
  self._scroll_y = 0
  self._auto_scroll = true

  -- 劫持 print
  self._original_print = print
  _G.print = function(...)
    local args = {...}
    local parts = {}
    for i = 1, #args do
      parts[i] = tostring(args[i])
    end
    local msg = table.concat(parts, "\t")
    Console:_addLog(msg, "log")
    if Console._original_print then
      Console._original_print(...)
    end
  end

  -- 注册命令
  self:_registerCommands()

  print("[Console] 控制台已初始化")
end

function Console:_addLog(msg, level)
  level = level or "log"
  local entry = {
    message = tostring(msg),
    level = level,
    timestamp = os.time(),
    timeStr = os.date("%H:%M:%S"),
    frame = 0,
  }
  table.insert(self._logs, entry)
  if #self._logs > self._max_logs then
    table.remove(self._logs, 1)
  end
  if self._auto_scroll then
    self._scroll_y = math.max(0, (#self._logs - 20) * 18)
  end
  EventBus:emit("console.new_log", entry)
end

-- 公共API：添加日志
function Console:log(msg, level)
  self:_addLog(msg, level or "log")
end

function Console:error(msg) self:_addLog(msg, "error") end
function Console:warn(msg) self:_addLog(msg, "warn") end
function Console:info(msg) self:_addLog(msg, "info") end
function Console:debug(msg) self:_addLog(msg, "debug") end

-- 注册内置命令
function Console:_registerCommands()
  self._commands = {}

  self:RegisterCommand("help", "显示所有命令", function(args)
    local lines = {"=== 可用命令 ==="}
    for name, cmd in pairs(self._commands) do
      table.insert(lines, string.format("  %s - %s", name, cmd.desc))
    end
    return table.concat(lines, "\n")
  end)

  self:RegisterCommand("clear", "清空控制台", function(args)
    self._logs = {}
    self._scroll_y = 0
    return "控制台已清空"
  end)

  self:RegisterCommand("filter", "过滤日志级别 [error|warn|info|log|all]", function(args)
    local f = args[1] or "all"
    if self.LEVELS[f] or f == "all" then
      self._filter = f
      return "日志过滤: " .. f
    end
    return "未知过滤级别: " .. f
  end)

  self:RegisterCommand("gc", "强制垃圾回收", function(args)
    collectgarbage("collect")
    local mem = collectgarbage("count")
    return string.format("垃圾回收完成，内存使用: %.2f KB", mem)
  end)

  self:RegisterCommand("mem", "显示内存使用", function(args)
    local mem = collectgarbage("count")
    return string.format("Lua 内存使用: %.2f KB (%.2f MB)", mem, mem / 1024)
  end)

  self:RegisterCommand("fps", "显示帧率信息", function(args)
    if self._fps_callback then
      return self._fps_callback()
    end
    return "FPS 信息不可用"
  end)

  self:RegisterCommand("nodes", "显示节点编辑器统计", function(args)
    if self._node_stats_callback then
      return self._node_stats_callback()
    end
    return "节点统计不可用"
  end)

  self:RegisterCommand("scene", "显示场景统计", function(args)
    if self._scene_stats_callback then
      return self._scene_stats_callback()
    end
    return "场景统计不可用"
  end)

  self:RegisterCommand("eval", "执行 Lua 代码", function(args)
    local code = table.concat(args, " ")
    if code == "" then return "用法: eval <lua代码>" end
    local fn, err = load("return " .. code)
    if not fn then
      fn, err = load(code)
    end
    if not fn then
      return "编译错误: " .. tostring(err)
    end
    local ok, result = pcall(fn)
    if not ok then
      return "执行错误: " .. tostring(result)
    end
    return "结果: " .. tostring(result)
  end)

  self:RegisterCommand("theme", "切换主题 [dark|light]", function(args)
    local theme = args[1] or "dark"
    if Config.SetTheme(theme) then
      return "主题已切换为: " .. theme
    end
    return "未知主题: " .. theme
  end)

  self:RegisterCommand("time", "显示当前时间", function(args)
    return os.date("%Y-%m-%d %H:%M:%S")
  end)
end

-- 注册自定义命令
function Console:RegisterCommand(name, desc, handler)
  self._commands[name] = { desc = desc, handler = handler }
end

-- 执行命令
function Console:ExecuteCommand(input)
  if input == "" or input == nil then return end

  -- 添加到历史
  table.insert(self._history, input)
  if #self._history > 50 then table.remove(self._history, 1) end
  self._history_index = #self._history + 1

  -- 显示输入
  self:_addLog("> " .. input, "info")

  -- 解析命令
  local parts = {}
  for part in input:gmatch("%S+") do
    table.insert(parts, part)
  end

  local cmdName = parts[1]
  table.remove(parts, 1)

  local cmd = self._commands[cmdName]
  if cmd then
    local ok, result = pcall(cmd.handler, parts)
    if ok then
      if result then self:_addLog(result, "info") end
    else
      self:_addLog("命令执行错误: " .. tostring(result), "error")
    end
  else
    self:_addLog("未知命令: " .. cmdName .. "，输入 help 查看可用命令", "warn")
  end
end

-- 获取过滤后的日志
function Console:GetFilteredLogs()
  if self._filter == "all" then return self._logs end
  local filtered = {}
  for _, log in ipairs(self._logs) do
    if log.level == self._filter then
      table.insert(filtered, log)
    end
  end
  return filtered
end

-- 历史导航
function Console:HistoryUp()
  if self._history_index > 1 then
    self._history_index = self._history_index - 1
    return self._history[self._history_index]
  end
  return nil
end

function Console:HistoryDown()
  if self._history_index < #self._history then
    self._history_index = self._history_index + 1
    return self._history[self._history_index]
  elseif self._history_index == #self._history then
    self._history_index = #self._history + 1
    return ""
  end
  return nil
end

-- 自动补全
function Console:GetCompletions(prefix)
  local matches = {}
  for name, _ in pairs(self._commands) do
    if name:sub(1, #prefix) == prefix then
      table.insert(matches, name)
    end
  end
  return matches
end

-- 设置回调
function Console:SetFPSCallback(cb) self._fps_callback = cb end
function Console:SetNodeStatsCallback(cb) self._node_stats_callback = cb end
function Console:SetSceneStatsCallback(cb) self._scene_stats_callback = cb end

-- 可见性
function Console:Toggle() self._visible = not self._visible; return self._visible end
function Console:IsVisible() return self._visible end
function Console:Show() self._visible = true end
function Console:Hide() self._visible = false end

-- 更新 (占位，供外部调用)
function Console:update(dt)
end

-- 清理
function Console:Destroy()
  if self._original_print then
    _G.print = self._original_print
  end
end

return Console
