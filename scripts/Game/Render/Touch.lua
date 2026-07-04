-- ============================================================================
-- Game/Render/Touch.lua
-- 触控UI渲染: 虚拟摇杆 + 操作按钮(手机适配)
-- ============================================================================
local CONFIG = require("Game.Config")
local State = require("Game.State")

local M = {}

-- 前向引用(由 init.lua 注入)
M.getTouchButtonRects = nil  -- 来自 Input 模块
M.dist = nil

-- ============================================================================
-- 触控按钮绘制(手机适配)
-- ============================================================================
function M.drawTouchControls(logW, logH)
    local ctx = State.nvgContext
    if not ctx then return end

    local rects = M.getTouchButtonRects(logW, logH)
    local players = State.players
    local localPlayerIdx = State.localPlayerIdx
    local p = players[localPlayerIdx]
    local touchButtons = State.touchButtons
    local touchJoystick = State.touchJoystick
    local gamePhase = State.gamePhase
    local potionNvgImages = State.potionNvgImages
    local dist = M.dist

    -- ===== 右侧按钮 =====

    -- 攻击按钮
    local atkRect = rects.attack
    local atkCx = atkRect.x + atkRect.w / 2
    local atkCy = atkRect.y + atkRect.h / 2
    local atkAlpha = touchButtons.attack.pressed and 200 or 120

    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, atkRect.x, atkRect.y, atkRect.w, atkRect.h, 12)
    nvgFillColor(ctx, nvgRGBA(180, 50, 50, atkAlpha))
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(240, 80, 80, 180))
    nvgStrokeWidth(ctx, 2)
    nvgStroke(ctx)

    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 16)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 230))
    nvgText(ctx, atkCx, atkCy, "攻击")

    -- 道具按钮(药水图标, 放大两倍)
    local itemRect = rects.item
    local itemCx = itemRect.x + itemRect.w / 2
    local itemCy = itemRect.y + itemRect.h / 2
    local itemAlpha = touchButtons.item.pressed and 220 or 140

    -- 确定药水类型和对应图片
    local potionR, potionG, potionB = 120, 120, 160
    local potionLabel = "道具"
    local itemPotionImg = nil
    if p and p.alive and p.potionState then
        if p.potionState == "antidote" then
            potionR, potionG, potionB = 80, 180, 255
            potionLabel = "解药"
        elseif p.potionState == "poison" then
            potionR, potionG, potionB = 120, 200, 60
            potionLabel = "毒药"
        elseif p.potionState == "victory" then
            potionR, potionG, potionB = 220, 180, 50
            potionLabel = "胜利"
        end
        itemPotionImg = potionNvgImages[p.potionState]
    end

    -- 圆形背景
    nvgBeginPath(ctx)
    nvgCircle(ctx, itemCx, itemCy, itemRect.w / 2)
    nvgFillColor(ctx, nvgRGBA(20, 20, 30, itemAlpha))
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(potionR, potionG, potionB, 200))
    nvgStrokeWidth(ctx, 3)
    nvgStroke(ctx)

    -- 绘制药水图片或文字
    if itemPotionImg then
        local iconSize = math.min(itemRect.w, itemRect.h) * 0.7
        local iconX = itemCx - iconSize / 2
        local iconY = itemCy - iconSize / 2
        local imgPaint = nvgImagePattern(ctx, iconX, iconY, iconSize, iconSize, 0, itemPotionImg, 1.0)
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, iconX, iconY, iconSize, iconSize, 4)
        nvgFillPaint(ctx, imgPaint)
        nvgFill(ctx)
    else
        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 20)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(150, 150, 150, 180))
        nvgText(ctx, itemCx, itemCy, potionLabel)
    end

    -- 底部文字标签
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 200))
    nvgText(ctx, itemCx, itemCy + itemRect.h / 2 - 18, potionLabel)

    -- ===== 奔跑按钮 =====
    local sprintRect = rects.sprint
    local sprintCx = sprintRect.x + sprintRect.w / 2
    local sprintCy = sprintRect.y + sprintRect.h / 2
    local sprintAlpha = touchButtons.sprint.pressed and 200 or 110
    local sprintActive = p and p.alive and p.sprinting

    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, sprintRect.x, sprintRect.y, sprintRect.w, sprintRect.h, 12)
    if sprintActive then
        nvgFillColor(ctx, nvgRGBA(220, 160, 30, sprintAlpha))
    else
        nvgFillColor(ctx, nvgRGBA(100, 100, 60, sprintAlpha))
    end
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(220, 180, 60, sprintActive and 220 or 140))
    nvgStrokeWidth(ctx, 2)
    nvgStroke(ctx)

    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 230))
    nvgText(ctx, sprintCx, sprintCy, "奔跑")

    -- ===== 交换药水按钮 =====
    local showInteract = false
    local interactLabel = "交换"
    if p and p.alive and not p.isGhost and gamePhase == "day" then
        if p.interactState == "pending" then
            showInteract = true
            interactLabel = "接受"
        elseif p.interactState == "idle" then
            for i = 1, #players do
                local other = players[i]
                if other.idx ~= p.idx and other.alive and other.interactState == "idle"
                    and other.drinkingState == "idle" then
                    local d = dist(p.x, p.y, other.x, other.y)
                    if d <= CONFIG.InteractRange then
                        showInteract = true
                        break
                    end
                end
            end
        end
    end

    if showInteract then
        local intRect = rects.interact
        local intCx = intRect.x + intRect.w / 2
        local intCy = intRect.y + intRect.h / 2
        local intAlpha = touchButtons.interact.pressed and 200 or 120

        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, intRect.x, intRect.y, intRect.w, intRect.h, 12)
        nvgFillColor(ctx, nvgRGBA(60, 120, 180, intAlpha))
        nvgFill(ctx)
        nvgStrokeColor(ctx, nvgRGBA(100, 180, 240, 180))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)

        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 14)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 230))
        nvgText(ctx, intCx, intCy, interactLabel)
    end

    -- ===== 拒绝交换按钮 =====
    local showReject = p and p.alive and not p.isGhost and gamePhase == "day"
        and (p.interactState == "pending" or p.interactState == "requesting" or p.interactState == "interacting")
    if showReject then
        local rejRect = rects.reject
        local rejCx = rejRect.x + rejRect.w / 2
        local rejCy = rejRect.y + rejRect.h / 2
        local rejAlpha = touchButtons.reject.pressed and 200 or 120

        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, rejRect.x, rejRect.y, rejRect.w, rejRect.h, 12)
        nvgFillColor(ctx, nvgRGBA(160, 50, 50, rejAlpha))
        nvgFill(ctx)
        nvgStrokeColor(ctx, nvgRGBA(220, 80, 80, 180))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)

        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 14)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 230))
        nvgText(ctx, rejCx, rejCy, "拒绝")
    end

    -- ===== 左侧虚拟摇杆 =====
    if touchJoystick.active then
        -- 外圈
        nvgBeginPath(ctx)
        nvgCircle(ctx, touchJoystick.cx, touchJoystick.cy, touchJoystick.radius)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 30))
        nvgFill(ctx)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 80))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)

        -- 内圈(摇杆位置)
        local knobX = touchJoystick.cx + touchJoystick.dx
        local knobY = touchJoystick.cy + touchJoystick.dy
        nvgBeginPath(ctx)
        nvgCircle(ctx, knobX, knobY, 18)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 100))
        nvgFill(ctx)
    end
end

return M
