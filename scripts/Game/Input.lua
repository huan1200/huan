-- ============================================================================
-- Game/Input.lua - 玩家输入处理
-- 负责: 键盘、鼠标、触摸、手柄输入
-- ============================================================================

local CONFIG = require("Game.Config")
local State = require("Game.State")
local Utils = require("Game.Utils")

local Input = {}

-- 外部注入
Input.performAttack = nil  -- Combat.performAttack
Input.useItem = nil        -- main.useItem

-- ============================================================================
-- 手柄适配
-- ============================================================================

local GAMEPAD_DEADZONE = 0.2

local function applyDeadzone(value)
    if math.abs(value) < GAMEPAD_DEADZONE then return 0 end
    local sign = value > 0 and 1 or -1
    return sign * (math.abs(value) - GAMEPAD_DEADZONE) / (1.0 - GAMEPAD_DEADZONE)
end

function Input.getGamepad()
    for i = 0, input.numJoysticks - 1 do
        local js = input:GetJoystickByIndex(i)
        if js and js:IsController() then
            return js
        end
    end
    return nil
end

-- ============================================================================
-- 触控系统状态
-- ============================================================================

Input.touchButtons = {
    attack = { pressed = false, touchId = -1 },
    item = { pressed = false, touchId = -1 },
    sprint = { pressed = false, touchId = -1 },
    interact = { pressed = false, touchId = -1 },
    reject = { pressed = false, touchId = -1 },
}

Input.touchJoystick = {
    active = false,
    touchId = -1,
    cx = 0, cy = 0,
    dx = 0, dy = 0,
    radius = 50,
}

Input.isTouchDevice = false
Input.moveInput = { x = 0, y = 0 }

-- ============================================================================
-- 获取触控按钮区域
-- ============================================================================

function Input.getTouchButtonRects(logW, logH)
    local btnSize = 60
    local itemBtnSize = 120
    local margin = 20
    local bottomY = logH - margin - btnSize
    local rightX = logW - margin - btnSize
    local itemRightX = logW - margin - itemBtnSize
    local sprintX = rightX - btnSize - 12
    local sprintY = bottomY
    local interactX = itemRightX - btnSize - 12
    local interactY = bottomY - itemBtnSize - 15
    local rejectX = interactX - btnSize - 8
    local rejectY = interactY
    return {
        attack = { x = rightX, y = bottomY, w = btnSize, h = btnSize },
        item = { x = itemRightX, y = bottomY - itemBtnSize - 15, w = itemBtnSize, h = itemBtnSize },
        sprint = { x = sprintX, y = sprintY, w = btnSize, h = btnSize },
        interact = { x = interactX, y = interactY, w = btnSize, h = btnSize },
        reject = { x = rejectX, y = rejectY, w = btnSize, h = btnSize },
    }
end

local function pointInRect(px, py, rect)
    return px >= rect.x and px <= rect.x + rect.w and py >= rect.y and py <= rect.y + rect.h
end

-- ============================================================================
-- 主输入处理(每帧调用)
-- ============================================================================

function Input.handlePlayerInput(dt)
    local p = State.players[State.localPlayerIdx]
    if not p then return end
    if not p.alive and not p.isGhost then return end

    -- 喝药/硬直期间禁止移动和攻击
    if not p.isGhost and (p.drinkingState == "drinking" or p.drinkingState == "stunned") then
        p.vx = 0
        p.vy = 0
        return
    end

    -- 交互期间禁止移动和攻击
    if not p.isGhost and p.interactState ~= "idle" then
        p.vx = 0
        p.vy = 0
        return
    end

    local gamepad = Input.getGamepad()

    -- 奔跑
    local sprintPressed = input:GetKeyDown(KEY_LSHIFT) or input:GetKeyDown(KEY_RSHIFT) or Input.touchButtons.sprint.pressed
    if not sprintPressed and gamepad then
        sprintPressed = gamepad:GetButtonDown(CONTROLLER_BUTTON_LEFTSHOULDER)
    end
    if sprintPressed then
        if p.energy > 0 then
            p.sprinting = true
        else
            p.sprinting = false
        end
    else
        p.sprinting = false
    end

    -- WASD移动
    Input.moveInput.x = 0
    Input.moveInput.y = 0
    if input:GetKeyDown(KEY_W) then Input.moveInput.y = -1 end
    if input:GetKeyDown(KEY_S) then Input.moveInput.y = 1 end
    if input:GetKeyDown(KEY_A) then Input.moveInput.x = -1 end
    if input:GetKeyDown(KEY_D) then Input.moveInput.x = 1 end

    -- 手柄左摇杆
    if gamepad then
        local gpX = applyDeadzone(gamepad:GetAxisPosition(CONTROLLER_AXIS_LEFTX))
        local gpY = applyDeadzone(gamepad:GetAxisPosition(CONTROLLER_AXIS_LEFTY))
        if gpX ~= 0 or gpY ~= 0 then
            Input.moveInput.x = gpX
            Input.moveInput.y = gpY
        end
    end

    -- 触控摇杆
    if Input.touchJoystick.active then
        local jLen = math.sqrt(Input.touchJoystick.dx * Input.touchJoystick.dx + Input.touchJoystick.dy * Input.touchJoystick.dy)
        if jLen > 5 then
            Input.moveInput.x = Input.touchJoystick.dx / Input.touchJoystick.radius
            Input.moveInput.y = Input.touchJoystick.dy / Input.touchJoystick.radius
        end
    end

    -- 翻转方向
    if Input.moveInput.x > 0.1 then
        p.flipDir = 1
    elseif Input.moveInput.x < -0.1 then
        p.flipDir = -1
    end

    local len = math.sqrt(Input.moveInput.x * Input.moveInput.x + Input.moveInput.y * Input.moveInput.y)
    if len == 0 then
        p.sprinting = false
    end

    -- 归一化并计算速度
    if len > 0 then
        local speed = CONFIG.MoveSpeed
        if p.isGhost then
            speed = speed * 1.3
        elseif p.sprinting then
            speed = CONFIG.MoveSpeed * CONFIG.SprintSpeedMultiplier
            if State.gamePhase ~= "prepare" then
                p.energy = Utils.clamp(p.energy - CONFIG.SprintCostRate * dt, CONFIG.EnergyMin, CONFIG.EnergyMax)
                if p.energy <= 0 then
                    p.sprinting = false
                    speed = CONFIG.MoveSpeed
                end
            end
        end
        p.vx = (Input.moveInput.x / len) * speed
        p.vy = (Input.moveInput.y / len) * speed
    else
        p.vx = 0
        p.vy = 0
    end

    -- 鬼魂不能朝向/攻击
    if p.isGhost then return end

    -- 朝向控制
    local facingSet = false

    -- 手柄右摇杆
    if gamepad then
        local rx = applyDeadzone(gamepad:GetAxisPosition(CONTROLLER_AXIS_RIGHTX))
        local ry = applyDeadzone(gamepad:GetAxisPosition(CONTROLLER_AXIS_RIGHTY))
        if rx ~= 0 or ry ~= 0 then
            p.facing = math.atan(ry, rx)
            facingSet = true
        end
    end

    -- 鼠标朝向
    if not facingSet and not Input.isTouchDevice then
        local graphics = GetGraphics()
        local screenW = graphics:GetWidth()
        local screenH = graphics:GetHeight()
        local dpr = graphics:GetDPR()
        local logW = screenW / dpr
        local logH = screenH / dpr

        local mousePos = input:GetMousePosition()
        local mx = mousePos.x / dpr
        local my = mousePos.y / dpr

        local dx = mx - logW / 2
        local dy = my - logH / 2
        if dx ~= 0 or dy ~= 0 then
            p.facing = math.atan(dy, dx)
            facingSet = true
        end
    end

    -- 左摇杆方向作为朝向
    if not facingSet and (Input.moveInput.x ~= 0 or Input.moveInput.y ~= 0) then
        local mLen = math.sqrt(Input.moveInput.x * Input.moveInput.x + Input.moveInput.y * Input.moveInput.y)
        if mLen > 0.3 then
            p.facing = math.atan(Input.moveInput.y, Input.moveInput.x)
        end
    end

    -- 手柄攻击
    if gamepad then
        if gamepad:GetButtonPress(CONTROLLER_BUTTON_A) then
            if State.gamePhase == "day" and not State.inventoryOpen and Input.performAttack then
                Input.performAttack(p)
            end
        end
        local rt = gamepad:GetAxisPosition(CONTROLLER_AXIS_TRIGGERRIGHT)
        if rt > 0.5 and p.attackCooldown <= 0 and p.attackState == "idle" then
            if State.gamePhase == "day" and not State.inventoryOpen and Input.performAttack then
                Input.performAttack(p)
            end
        end
    end
end

-- ============================================================================
-- 触摸事件
-- ============================================================================

function Input.handleTouchBegin(touchId, rawX, rawY)
    Input.isTouchDevice = true
    local graphics = GetGraphics()
    local dpr = graphics:GetDPR()
    local logW = graphics:GetWidth() / dpr
    local logH = graphics:GetHeight() / dpr
    local tx = rawX / dpr
    local ty = rawY / dpr

    local rects = Input.getTouchButtonRects(logW, logH)

    if pointInRect(tx, ty, rects.attack) then
        Input.touchButtons.attack.pressed = true
        Input.touchButtons.attack.touchId = touchId
        if State.gamePhase == "day" and Input.performAttack then
            local p = State.players[State.localPlayerIdx]
            if p and p.alive and not p.isGhost then
                Input.performAttack(p)
            end
        end
        return true
    end

    if pointInRect(tx, ty, rects.item) then
        Input.touchButtons.item.pressed = true
        Input.touchButtons.item.touchId = touchId
        if State.gamePhase == "day" and Input.useItem then
            local p = State.players[State.localPlayerIdx]
            if p and p.alive and not p.isGhost then
                Input.useItem()
            end
        end
        return true
    end

    if pointInRect(tx, ty, rects.sprint) then
        Input.touchButtons.sprint.pressed = true
        Input.touchButtons.sprint.touchId = touchId
        return true
    end

    if pointInRect(tx, ty, rects.interact) then
        Input.touchButtons.interact.pressed = true
        Input.touchButtons.interact.touchId = touchId
        return true  -- 交互逻辑由主模块处理
    end

    if pointInRect(tx, ty, rects.reject) then
        Input.touchButtons.reject.pressed = true
        Input.touchButtons.reject.touchId = touchId
        return true  -- 拒绝逻辑由主模块处理
    end

    -- 左半屏: 虚拟摇杆
    if tx < logW * 0.5 and not Input.touchJoystick.active then
        Input.touchJoystick.active = true
        Input.touchJoystick.touchId = touchId
        Input.touchJoystick.cx = tx
        Input.touchJoystick.cy = ty
        Input.touchJoystick.dx = 0
        Input.touchJoystick.dy = 0
        return true
    end

    return false
end

function Input.handleTouchMove(touchId, rawX, rawY)
    local graphics = GetGraphics()
    local dpr = graphics:GetDPR()
    local tx = rawX / dpr
    local ty = rawY / dpr

    if Input.touchJoystick.active and Input.touchJoystick.touchId == touchId then
        Input.touchJoystick.dx = tx - Input.touchJoystick.cx
        Input.touchJoystick.dy = ty - Input.touchJoystick.cy
        local jLen = math.sqrt(Input.touchJoystick.dx * Input.touchJoystick.dx + Input.touchJoystick.dy * Input.touchJoystick.dy)
        if jLen > Input.touchJoystick.radius then
            Input.touchJoystick.dx = Input.touchJoystick.dx / jLen * Input.touchJoystick.radius
            Input.touchJoystick.dy = Input.touchJoystick.dy / jLen * Input.touchJoystick.radius
        end
    end
end

function Input.handleTouchEnd(touchId)
    if Input.touchButtons.attack.touchId == touchId then
        Input.touchButtons.attack.pressed = false
        Input.touchButtons.attack.touchId = -1
    end
    if Input.touchButtons.item.touchId == touchId then
        Input.touchButtons.item.pressed = false
        Input.touchButtons.item.touchId = -1
    end
    if Input.touchButtons.sprint.touchId == touchId then
        Input.touchButtons.sprint.pressed = false
        Input.touchButtons.sprint.touchId = -1
    end
    if Input.touchButtons.interact.touchId == touchId then
        Input.touchButtons.interact.pressed = false
        Input.touchButtons.interact.touchId = -1
    end
    if Input.touchButtons.reject.touchId == touchId then
        Input.touchButtons.reject.pressed = false
        Input.touchButtons.reject.touchId = -1
    end

    if Input.touchJoystick.touchId == touchId then
        Input.touchJoystick.active = false
        Input.touchJoystick.touchId = -1
        Input.touchJoystick.dx = 0
        Input.touchJoystick.dy = 0
    end
end

return Input
