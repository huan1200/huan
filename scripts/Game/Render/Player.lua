-- Game/Render/Player.lua
-- 玩家渲染模块: 角色精灵(5种动画) + 状态特效 + 药水光效 + 能量心脏 + 毒条

local CONFIG = require("Game.Config")
local State = require("Game.State")

local M = {}

-- Forward references (injected by init.lua)
M.dist = nil

--- 绘制单个玩家(饥荒风纸偶角色)
---@param ctx any NanoVG context
---@param p table 玩家数据
---@param ox number 偏移X
---@param oy number 偏移Y
---@param isDay boolean 是否白天
function M.drawPlayerDST(ctx, p, ox, oy, isDay)
    local sx = p.x + ox
    local sy = p.y + oy
    local dist = M.dist
    local circle = State.circle
    local fontId = State.fontId
    local ghostImage = State.ghostImage
    local pigImages = State.pigImages
    local potionNvgImages = State.potionNvgImages
    local statusEffects = State.statusEffects
    local pickupGlows = State.pickupGlows

    -- 鬼魂渲染
    local isGhost = p.isGhost
    if isGhost then
        local ghostW = 64
        local ghostH = 64
        local ghostX = sx - ghostW / 2
        local ghostY = sy - ghostH + 4

        local time = GetTime():GetElapsedTime()
        local floatOffset = math.sin(time * 2.5 + p.idx * 1.2) * 4
        ghostY = ghostY + floatOffset

        nvgSave(ctx)
        nvgGlobalAlpha(ctx, 0.55)

        if ghostImage then
            local flipX = (p.flipDir < 0)
            if flipX then
                nvgTranslate(ctx, ghostX + ghostW / 2, 0)
                nvgScale(ctx, -1, 1)
                nvgTranslate(ctx, -(ghostX + ghostW / 2), 0)
            end
            local paint = nvgImagePattern(ctx, ghostX, ghostY, ghostW, ghostH, 0, ghostImage, 1.0)
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, ghostX, ghostY, ghostW, ghostH, 4)
            nvgFillPaint(ctx, paint)
            nvgFill(ctx)
        else
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy - ghostH / 2, 20)
            nvgFillColor(ctx, nvgRGBA(200, 200, 255, 120))
            nvgFill(ctx)
        end

        nvgRestore(ctx)

        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 12)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(200, 200, 255, 140))
        nvgText(ctx, sx, ghostY - 8, p.name)
        return
    end

    -- ===== 尺寸定义 =====
    local headR = 16
    local bodyW = 9
    local bodyH = 20
    local legLen = 12
    local totalH = headR * 2 + bodyH + legLen

    local baseY = sy
    local bodyTop = baseY - legLen - bodyH
    local headY = bodyTop - headR

    -- ===== 颜色系统 =====
    local color = p.color
    local poisonRatio = p.poison / CONFIG.PoisonMax
    local energyRatio = p.energy / CONFIG.EnergyMax

    local cr, cg, cb = color[1], color[2], color[3]
    if p.energy <= 0 then
        cr, cg, cb = 80, 80, 80
    end

    -- 描边颜色
    local outR, outG, outB = 10, 8, 6
    if not isDay then outR, outG, outB = 5, 4, 3 end
    local outlineW = 4

    -- ===== 阴影 =====
    local shadowOffX = math.cos(p.facing) * 2
    local shadowScaleX = 14 + math.abs(math.cos(p.facing)) * 3
    local shadowScaleY = 5 + math.abs(math.sin(p.facing)) * 2
    nvgBeginPath(ctx)
    nvgEllipse(ctx, sx + shadowOffX, baseY + 3, shadowScaleX, shadowScaleY)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, isDay and 70 or 40))
    nvgFill(ctx)

    -- ===== 毒圈外效果 =====
    local distToCircle = dist(p.x, p.y, circle.cx, circle.cy)
    if distToCircle > circle.radius and not isGhost then
        local time = GetTime():GetElapsedTime()
        local ripple1 = math.fmod(time * 0.8 + p.idx * 0.3, 1.0)
        local ripple2 = math.fmod(time * 0.8 + p.idx * 0.3 + 0.5, 1.0)
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, baseY + 2, 8 + ripple1 * 12)
        nvgStrokeColor(ctx, nvgRGBA(100, 40, 120, math.floor((1.0 - ripple1) * 60)))
        nvgStrokeWidth(ctx, 1.5)
        nvgStroke(ctx)
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, baseY + 2, 5 + ripple2 * 10)
        nvgStrokeColor(ctx, nvgRGBA(74, 50, 80, math.floor((1.0 - ripple2) * 40)))
        nvgStrokeWidth(ctx, 1)
        nvgStroke(ctx)
        for bubble = 1, 3 do
            local bubbleT = math.fmod(time * 0.6 + bubble * 0.9 + p.idx * 0.4, 1.5)
            local bx = sx + math.sin(time * 1.5 + bubble * 2.1 + p.idx) * 6
            local by = baseY - bubbleT * 15
            local bAlpha = math.floor((1.0 - bubbleT / 1.5) * 120)
            local bSize = 1.5 + (1.0 - bubbleT / 1.5) * 1.5
            nvgBeginPath(ctx)
            nvgCircle(ctx, bx, by, bSize)
            nvgFillColor(ctx, nvgRGBA(60, 180, 40, bAlpha))
            nvgFill(ctx)
        end
    end

    -- ===== 能量枯竭弯腰 =====
    local bendOffset = 0
    if p.energy <= 0 then bendOffset = 4 end

    -- ===== 角色图片动画帧选择 =====
    local isMoving = (p.vx ~= 0 or p.vy ~= 0)
    local imgHandle = pigImages[p.avatarIdx]
    local useAnimFrame = false

    if p.avatarIdx == 1 then
        local time = GetTime():GetElapsedTime()
        if p.drinkingState == "drinking" and #State.jesterDrinkFrames > 0 then
            local drinkProgress = p.drinkingTimer / CONFIG.DrinkDuration
            local frameIdx = math.min(math.floor(drinkProgress * #State.jesterDrinkFrames) + 1, #State.jesterDrinkFrames)
            local h = State.jesterDrinkFrames[frameIdx]
            if h and h ~= 0 and h ~= -1 then imgHandle = h; useAnimFrame = true end
        elseif p.drinkingState == "stunned" and #State.jesterHurtFrames > 0 then
            local hurtProgress = 1.0 - (p.drinkingTimer / CONFIG.DrinkStunDuration)
            hurtProgress = math.max(0, math.min(hurtProgress, 1.0))
            local frameIdx = math.min(math.floor(hurtProgress * #State.jesterHurtFrames) + 1, #State.jesterHurtFrames)
            local h = State.jesterHurtFrames[frameIdx]
            if h and h ~= 0 and h ~= -1 then imgHandle = h; useAnimFrame = true end
        elseif p.attacking and #State.jesterAttackFrames > 0 then
            local totalDur = CONFIG.AttackWindup + CONFIG.AttackRecovery
            local elapsed = totalDur - p.attackTimer
            local progress = math.min(elapsed / totalDur, 1.0)
            local frameIdx = math.min(math.floor(progress * #State.jesterAttackFrames) + 1, #State.jesterAttackFrames)
            local h = State.jesterAttackFrames[frameIdx]
            if h and h ~= 0 and h ~= -1 then imgHandle = h; useAnimFrame = true end
        elseif isMoving and p.sprinting and #State.jesterRunFrames > 0 then
            local frameIdx = math.floor(time * CONFIG.JESTER_RUN_FPS) % #State.jesterRunFrames + 1
            local h = State.jesterRunFrames[frameIdx]
            if h and h ~= 0 and h ~= -1 then imgHandle = h; useAnimFrame = true end
        elseif isMoving and #State.jesterWalkFrames > 0 then
            local frameIdx = math.floor(time * CONFIG.JESTER_WALK_FPS) % #State.jesterWalkFrames + 1
            local h = State.jesterWalkFrames[frameIdx]
            if h and h ~= 0 and h ~= -1 then imgHandle = h; useAnimFrame = true end
        elseif #State.jesterIdleFrames > 0 then
            local frameIdx = math.floor(time * CONFIG.JESTER_IDLE_FPS) % #State.jesterIdleFrames + 1
            local h = State.jesterIdleFrames[frameIdx]
            if h and h ~= 0 and h ~= -1 then imgHandle = h; useAnimFrame = true end
        end
    elseif p.avatarIdx == 2 then
        local time = GetTime():GetElapsedTime()
        if isMoving and #State.warriorWalkFrames > 0 then
            local frameIdx = math.floor(time * CONFIG.WARRIOR_WALK_FPS) % #State.warriorWalkFrames + 1
            local h = State.warriorWalkFrames[frameIdx]
            if h and h ~= 0 and h ~= -1 then imgHandle = h; useAnimFrame = true end
        elseif not isMoving then
            imgHandle = pigImages[p.avatarIdx]
            useAnimFrame = false
        end
    elseif p.avatarIdx == 3 then
        local time = GetTime():GetElapsedTime()
        if isMoving and #State.scientistWalkFrames > 0 then
            local frameIdx = math.floor(time * CONFIG.SCIENTIST_WALK_FPS) % #State.scientistWalkFrames + 1
            local h = State.scientistWalkFrames[frameIdx]
            if h and h ~= 0 and h ~= -1 then imgHandle = h; useAnimFrame = true end
        end
    elseif p.avatarIdx == 4 then
        local time = GetTime():GetElapsedTime()
        if p.attacking and #State.minerAttackFrames > 0 then
            local totalDur = CONFIG.AttackWindup + CONFIG.AttackRecovery
            local elapsed = totalDur - p.attackTimer
            local progress = math.min(elapsed / totalDur, 1.0)
            local frameIdx = math.min(math.floor(progress * #State.minerAttackFrames) + 1, #State.minerAttackFrames)
            local h = State.minerAttackFrames[frameIdx]
            if h and h ~= 0 and h ~= -1 then imgHandle = h; useAnimFrame = true end
        elseif isMoving and #State.minerWalkFrames > 0 then
            local frameIdx = math.floor(time * CONFIG.MINER_WALK_FPS) % #State.minerWalkFrames + 1
            local h = State.minerWalkFrames[frameIdx]
            if h and h ~= 0 and h ~= -1 then imgHandle = h; useAnimFrame = true end
        elseif #State.minerIdleFrames > 0 then
            local frameIdx = math.floor(time * CONFIG.MINER_IDLE_FPS) % #State.minerIdleFrames + 1
            local h = State.minerIdleFrames[frameIdx]
            if h and h ~= 0 and h ~= -1 then imgHandle = h; useAnimFrame = true end
        end
    elseif p.avatarIdx == 5 then
        local time = GetTime():GetElapsedTime()
        if isMoving and #State.thiefWalkFrames > 0 then
            local frameIdx = math.floor(time * CONFIG.THIEF_WALK_FPS) % #State.thiefWalkFrames + 1
            local h = State.thiefWalkFrames[frameIdx]
            if h and h ~= 0 and h ~= -1 then imgHandle = h; useAnimFrame = true end
        end
    end

    -- 角色图片尺寸
    local imgW = 72
    local imgH = 72
    if p.avatarIdx == 2 then
        if useAnimFrame then
            imgW = 54; imgH = 92
        else
            imgW = 64; imgH = 80
        end
    end
    local imgX = sx - imgW / 2
    local imgY = baseY - imgH + bendOffset

    -- 行走弹跳
    local walkBounce = 0
    if isMoving then
        local speed = (p.energy <= 0) and 5 or 8
        walkBounce = math.abs(math.sin(GetTime():GetElapsedTime() * speed + p.idx)) * 3
    end
    imgY = imgY - walkBounce

    -- 攻击前冲
    local attackLunge = 0
    if p.attacking then attackLunge = 4 end
    imgX = imgX + math.cos(p.facing) * attackLunge
    imgY = imgY + math.sin(p.facing) * attackLunge

    -- 能量枯竭变暗
    local imgAlpha = 1.0
    if p.energy <= 0 then imgAlpha = 0.6 end

    -- 绘制角色图片
    local flipX = (p.flipDir < 0)
    if imgHandle and imgHandle ~= 0 and imgHandle ~= -1 then
        nvgSave(ctx)
        if flipX then
            nvgTranslate(ctx, imgX + imgW / 2, 0)
            nvgScale(ctx, -1, 1)
            nvgTranslate(ctx, -(imgX + imgW / 2), 0)
        end
        local paint = nvgImagePattern(ctx, imgX, imgY, imgW, imgH, 0, imgHandle, imgAlpha)
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, imgX, imgY, imgW, imgH, 4)
        nvgFillPaint(ctx, paint)
        nvgFill(ctx)
        nvgRestore(ctx)
    else
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, baseY - imgH / 2 + bendOffset, 20)
        nvgFillColor(ctx, nvgRGBA(cr, cg, cb, 230))
        nvgFill(ctx)
    end

    -- 中毒绿色斑纹
    if poisonRatio > 0.2 then
        local spotA = math.floor(poisonRatio * 80)
        for sp = 1, 4 do
            local spX = sx + math.sin(sp * 2.3 + p.idx) * 12
            local spY = baseY - imgH * (0.3 + sp * 0.15) + bendOffset
            nvgBeginPath(ctx)
            nvgCircle(ctx, spX, spY, 3 + poisonRatio * 2)
            nvgFillColor(ctx, nvgRGBA(46, 74, 62, spotA))
            nvgFill(ctx)
        end
    end

    local headDrawY = imgY + 4

    -- 中毒绿色粒子
    if poisonRatio > 0.1 then
        local time = GetTime():GetElapsedTime()
        for k = 1, 3 do
            local pLife = math.fmod(time * 0.8 + k * 0.33, 1.0)
            local px = sx + math.sin(time * 2 + k * 2.1) * 6
            local py = headDrawY - headR - pLife * 18
            local pa = math.floor((1.0 - pLife) * poisonRatio * 180)
            nvgBeginPath(ctx)
            nvgCircle(ctx, px, py, 1.5 + (1.0 - pLife) * 1.5)
            nvgFillColor(ctx, nvgRGBA(46, 74, 62, pa))
            nvgFill(ctx)
        end
    end

    -- 本地玩家光圈
    if p.isLocal then
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, baseY - totalH * 0.5, totalH * 0.55)
        nvgStrokeColor(ctx, nvgRGBA(139, 105, 20, 50))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)
    end

    -- ===== 能量心脏(脚下常驻) =====
    do
        local heartCX = sx - 18
        local heartCY = baseY + 16
        local heartSize = 7

        local function drawHeartPath(hcx, hcy, hs)
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, hcx, hcy + hs * 0.4)
            nvgBezierTo(ctx, hcx - hs * 0.05, hcy + hs * 0.1, hcx - hs * 0.7, hcy - hs * 0.2, hcx - hs * 0.7, hcy - hs * 0.55)
            nvgBezierTo(ctx, hcx - hs * 0.7, hcy - hs * 0.9, hcx - hs * 0.1, hcy - hs * 1.0, hcx, hcy - hs * 0.6)
            nvgBezierTo(ctx, hcx + hs * 0.1, hcy - hs * 1.0, hcx + hs * 0.7, hcy - hs * 0.9, hcx + hs * 0.7, hcy - hs * 0.55)
            nvgBezierTo(ctx, hcx + hs * 0.7, hcy - hs * 0.2, hcx + hs * 0.05, hcy + hs * 0.1, hcx, hcy + hs * 0.4)
            nvgClosePath(ctx)
        end

        local heartR, heartG, heartB, heartA = 180, 30, 30, 220
        if p.energy <= 0 then
            heartR, heartG, heartB = 90, 80, 80
            local flicker = math.sin(GetTime():GetElapsedTime() * 4) > 0 and 1 or 0.5
            heartA = math.floor(200 * flicker)
        elseif p.energy < 30 then
            local flicker = math.sin(GetTime():GetElapsedTime() * 10) > 0 and 1 or 0.4
            heartA = math.floor(220 * flicker)
        end

        drawHeartPath(heartCX, heartCY, heartSize)
        nvgStrokeColor(ctx, nvgRGBA(outR, outG, outB, 200))
        nvgStrokeWidth(ctx, 2.5)
        nvgStroke(ctx)

        drawHeartPath(heartCX, heartCY, heartSize)
        nvgFillColor(ctx, nvgRGBA(60, 55, 50, 180))
        nvgFill(ctx)

        if energyRatio > 0 then
            nvgSave(ctx)
            local heartTop = heartCY - heartSize * 1.0
            local heartBot = heartCY + heartSize * 0.4
            local heartH = heartBot - heartTop
            local fillTop = heartBot - heartH * energyRatio
            nvgScissor(ctx, heartCX - heartSize, fillTop, heartSize * 2, heartBot - fillTop + 1)
            drawHeartPath(heartCX, heartCY, heartSize)
            nvgFillColor(ctx, nvgRGBA(heartR, heartG, heartB, heartA))
            nvgFill(ctx)
            nvgResetScissor(ctx)
            nvgRestore(ctx)
        end

        if p.energy <= 0 then
            local exX = heartCX + heartSize + 4
            local exY = heartCY + 2
            nvgFontFace(ctx, "sans")
            nvgFontSize(ctx, 14)
            nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local flicker = math.sin(GetTime():GetElapsedTime() * 4) > 0 and 220 or 110
            nvgFillColor(ctx, nvgRGBA(240, 200, 50, flicker))
            nvgText(ctx, exX, exY, "!")
        end
    end

    -- ===== 毒药条(脚下) =====
    if p.poison > 0 then
        local barW = 26
        local barH = 4
        local barX = sx - 2
        local barY = baseY + 13

        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, barX - 1, barY - 1, barW + 2, barH + 2, 3)
        nvgFillColor(ctx, nvgRGBA(10, 8, 6, 180))
        nvgFill(ctx)

        local fillW = (p.poison / CONFIG.PoisonMax) * barW
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, barX, barY, fillW, barH, 2)
        nvgFillColor(ctx, nvgRGBA(
            math.floor(46 + poisonRatio * 28),
            math.floor(74 + poisonRatio * 50),
            math.floor(62 + poisonRatio * 27), 230))
        nvgFill(ctx)
    end

    -- ===== 毒满暴走buff =====
    if p.poisonMaxBuff then
        local time = GetTime():GetElapsedTime()
        local pulse = 0.6 + 0.4 * math.sin(time * 8)
        local alpha = math.floor(180 * pulse)
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, headDrawY - headR - 6, headR + 6)
        nvgStrokeColor(ctx, nvgRGBA(255, 0, 180, alpha))
        nvgStrokeWidth(ctx, 2.5)
        nvgStroke(ctx)
        nvgFontSize(ctx, 9)
        nvgFontFace(ctx, "sans")
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(ctx, nvgRGBA(255, 80, 200, alpha))
        nvgText(ctx, sx, headDrawY - headR - 14, "暴走", nil)
    end

    -- ===== 喝药读条 =====
    if p.drinkingState == "drinking" then
        local barW = 32
        local barH = 5
        local barX = sx - barW / 2
        local barY = headDrawY - headR - 32
        local progress = 1.0 - (p.drinkingTimer / CONFIG.DrinkDuration)

        local isAntidote = p.drinkingType == "antidote"
        local fillR, fillG, fillB = 80, 200, 255
        if not isAntidote then fillR, fillG, fillB = 180, 60, 200 end

        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, barX - 1, barY - 1, barW + 2, barH + 2, 3)
        nvgFillColor(ctx, nvgRGBA(10, 8, 6, 200))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, barX, barY, barW * progress, barH, 2)
        nvgFillColor(ctx, nvgRGBA(fillR, fillG, fillB, 230))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, barX, barY, barW, barH, 2)
        nvgStrokeColor(ctx, nvgRGBA(fillR, fillG, fillB, 150))
        nvgStrokeWidth(ctx, 1)
        nvgStroke(ctx)
        if fontId ~= -1 then
            nvgFontFaceId(ctx, fontId)
            nvgFontSize(ctx, 8)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, 200))
            nvgText(ctx, sx, barY + barH / 2, isAntidote and "解毒中" or "饮毒中", nil)
        end
    end

    -- ===== 药剂状态视觉指示 =====
    if p.potionState and p.drinkingState == "idle" then
        local time = GetTime():GetElapsedTime()
        local pulse = 0.6 + math.sin(time * 4 + p.idx * 1.7) * 0.4
        local auraR, auraG, auraB, auraA

        if p.isLocal then
            if p.potionState == "antidote" then
                auraR, auraG, auraB, auraA = 100, 200, 255, math.floor(45 * pulse)
            else
                auraR, auraG, auraB, auraA = 80, 180, 80, math.floor(45 * pulse)
            end
        else
            if p.potionState == "antidote" then
                auraR, auraG, auraB, auraA = 100, 190, 200, math.floor(30 * pulse)
            else
                auraR, auraG, auraB, auraA = 90, 200, 170, math.floor(30 * pulse)
            end
        end

        local auraGrad = nvgRadialGradient(ctx, sx, bodyTop + bodyH * 0.5 + bendOffset,
            bodyW, totalH * 0.5,
            nvgRGBA(auraR, auraG, auraB, auraA),
            nvgRGBA(auraR, auraG, auraB, 0))
        nvgBeginPath(ctx)
        nvgEllipse(ctx, sx, bodyTop + bodyH * 0.5 + bendOffset, totalH * 0.4, totalH * 0.5)
        nvgFillPaint(ctx, auraGrad)
        nvgFill(ctx)
    end

    -- ===== 编号标签 =====
    if fontId ~= -1 then
        nvgFontFaceId(ctx, fontId)
        nvgFontSize(ctx, 10)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(ctx, nvgRGBA(220, 210, 190, 180))
        nvgText(ctx, sx, headDrawY - 2, "P" .. tostring(p.idx), nil)
    end

    -- ===== 占领进度条 =====
    if p.isCapturingZone and p.comfortStandTimer and p.comfortStandTimer > 0 then
        local barW = 40
        local barH = 5
        local barX = sx - barW / 2
        local barY = headDrawY - 14
        local progress = math.min(p.comfortStandTimer / CONFIG.ComfortZoneWaitTime, 1.0)

        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, barX - 1, barY - 1, barW + 2, barH + 2, 3)
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, 140))
        nvgFill(ctx)

        if progress > 0 then
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, barX, barY, barW * progress, barH, 2.5)
            local gR = math.floor(200 + 55 * progress)
            local gG = math.floor(160 + 60 * progress)
            nvgFillColor(ctx, nvgRGBA(gR, gG, 40, 230))
            nvgFill(ctx)
        end

        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, barX, barY, barW, barH, 2.5)
        nvgStrokeColor(ctx, nvgRGBA(200, 180, 80, 180))
        nvgStrokeWidth(ctx, 0.8)
        nvgStroke(ctx)

        if fontId ~= -1 then
            nvgFontFaceId(ctx, fontId)
            nvgFontSize(ctx, 9)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgFillColor(ctx, nvgRGBA(255, 220, 80, 220))
            nvgText(ctx, sx, barY - 2, "占领中", nil)
        end
    end

    -- ===== 状态特效 =====
    for _, eff in ipairs(statusEffects) do
        if eff.playerIdx == p.idx then
            local alpha = math.floor(180 * (eff.timer / 1.0))
            if eff.type == "poison" then
                local pulse = math.sin(GetTime():GetElapsedTime() * 10) * 3
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx, baseY - totalH * 0.4, totalH * 0.6 + pulse)
                nvgStrokeColor(ctx, nvgRGBA(46, 74, 62, alpha))
                nvgStrokeWidth(ctx, 2.5)
                nvgStroke(ctx)
                for k = 1, 3 do
                    local angle = GetTime():GetElapsedTime() * 3 + k * 2.1
                    local r = totalH * 0.45 + math.sin(angle * 2) * 5
                    local pkx = sx + math.cos(angle) * r
                    local pky = (baseY - totalH * 0.4) + math.sin(angle) * r * 0.5
                    nvgBeginPath(ctx)
                    nvgCircle(ctx, pkx, pky, 3)
                    nvgFillColor(ctx, nvgRGBA(74, 124, 89, math.floor(alpha * 0.7)))
                    nvgFill(ctx)
                end
            elseif eff.type == "detox" then
                local progress = 1.0 - (eff.timer / 0.8)
                local radius = totalH * 0.4 + progress * 15
                local a = math.floor(200 * (1.0 - progress))
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx, baseY - totalH * 0.4, radius)
                nvgStrokeColor(ctx, nvgRGBA(139, 105, 20, a))
                nvgStrokeWidth(ctx, 3)
                nvgStroke(ctx)
                for k = 1, 4 do
                    local yOff = progress * 20 * k * 0.5
                    local xOff = math.sin(k * 1.5 + progress * 6) * 8
                    nvgBeginPath(ctx)
                    nvgCircle(ctx, sx + xOff, baseY - totalH * 0.3 - yOff, 2.5 - progress * 1.5)
                    nvgFillColor(ctx, nvgRGBA(160, 130, 40, a))
                    nvgFill(ctx)
                end
            elseif eff.type == "transform" then
                local progress = 1.0 - (eff.timer / 1.5)
                local ring1R = totalH * 0.3 + progress * 35
                local ring2R = totalH * 0.3 + progress * 55
                local a1 = math.floor(220 * (1.0 - progress))
                local a2 = math.floor(140 * math.max(0, 1.0 - progress * 1.5))
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx, baseY - totalH * 0.4, ring1R)
                nvgStrokeColor(ctx, nvgRGBA(180, 60, 200, a1))
                nvgStrokeWidth(ctx, 2.5)
                nvgStroke(ctx)
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx, baseY - totalH * 0.4, ring2R)
                nvgStrokeColor(ctx, nvgRGBA(120, 40, 160, a2))
                nvgStrokeWidth(ctx, 1.5)
                nvgStroke(ctx)
                for k = 1, 5 do
                    local angle = progress * 6 + k * 1.26
                    local pDist = ring1R * 0.6 + progress * 20
                    local pkx = sx + math.cos(angle) * pDist
                    local pky = (baseY - totalH * 0.4) + math.sin(angle) * pDist * 0.6
                    nvgBeginPath(ctx)
                    nvgCircle(ctx, pkx, pky, 2.5 - progress * 1.5)
                    nvgFillColor(ctx, nvgRGBA(160, 80, 220, a1))
                    nvgFill(ctx)
                end
            end
        end
    end

    -- ===== 解药/毒药获取光效 =====
    for _, glow in ipairs(pickupGlows) do
        if glow.playerIdx == p.idx then
            local progress = 1.0 - (glow.timer / glow.maxTimer)
            local glowAlpha = math.floor(200 * (1.0 - progress))

            if glow.type == "antidote" then
                local radius1 = 12 + progress * 20
                local radius2 = 8 + progress * 15
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx, headDrawY - headR - 5, radius1)
                nvgStrokeColor(ctx, nvgRGBA(180, 220, 255, glowAlpha))
                nvgStrokeWidth(ctx, 2.5)
                nvgStroke(ctx)
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx, headDrawY - headR - 5, radius2)
                nvgStrokeColor(ctx, nvgRGBA(240, 250, 255, math.floor(glowAlpha * 0.7)))
                nvgStrokeWidth(ctx, 1.5)
                nvgStroke(ctx)
                for k = 1, 5 do
                    local kProgress = math.fmod(progress * 2 + k * 0.2, 1.0)
                    local kx = sx + math.sin(k * 1.8 + progress * 8) * 10
                    local ky = headDrawY - headR - 10 - kProgress * 25
                    local ka = math.floor(glowAlpha * (1.0 - kProgress))
                    nvgBeginPath(ctx)
                    nvgCircle(ctx, kx, ky, 2.5 - kProgress * 1.5)
                    nvgFillColor(ctx, nvgRGBA(200, 235, 255, ka))
                    nvgFill(ctx)
                end
            elseif glow.type == "poison" then
                local radius1 = 10 + progress * 18
                local pulse = math.sin(GetTime():GetElapsedTime() * 15) * 3
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx, headDrawY - headR - 5, radius1 + pulse)
                nvgStrokeColor(ctx, nvgRGBA(30, 80, 40, glowAlpha))
                nvgStrokeWidth(ctx, 3)
                nvgStroke(ctx)
                local innerGrad = nvgRadialGradient(ctx, sx, headDrawY - headR - 5,
                    0, radius1 * 0.6,
                    nvgRGBA(20, 60, 30, math.floor(glowAlpha * 0.4)),
                    nvgRGBA(30, 80, 40, 0))
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx, headDrawY - headR - 5, radius1 * 0.6)
                nvgFillPaint(ctx, innerGrad)
                nvgFill(ctx)
                for k = 1, 4 do
                    local kProgress = math.fmod(progress * 2 + k * 0.25, 1.0)
                    local kx = sx + math.cos(k * 2.1 + progress * 6) * 8
                    local ky = headDrawY - headR + kProgress * 15
                    local ka = math.floor(glowAlpha * (1.0 - kProgress) * 0.8)
                    nvgBeginPath(ctx)
                    nvgCircle(ctx, kx, ky, 2 + kProgress)
                    nvgFillColor(ctx, nvgRGBA(40, 100, 50, ka))
                    nvgFill(ctx)
                end
            end
        end
    end

    -- ===== 持药光效 =====
    if not isGhost and p.potionState then
        local time = GetTime():GetElapsedTime()
        local pulse = 0.5 + 0.5 * math.sin(time * 4)
        local auraR = 22 + pulse * 6
        local auraAlpha = math.floor(60 + pulse * 40)
        if p.potionState == "antidote" then
            local grad = nvgRadialGradient(ctx, sx, sy, auraR * 0.3, auraR,
                nvgRGBA(100, 180, 255, auraAlpha), nvgRGBA(80, 150, 255, 0))
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy, auraR)
            nvgFillPaint(ctx, grad)
            nvgFill(ctx)
        else
            local grad = nvgRadialGradient(ctx, sx, sy, auraR * 0.3, auraR,
                nvgRGBA(60, 200, 80, auraAlpha), nvgRGBA(40, 160, 60, 0))
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy, auraR)
            nvgFillPaint(ctx, grad)
            nvgFill(ctx)
        end
    end

    -- ===== 中毒加深骷髅图标 =====
    if not isGhost and p.poisonSkullTimer and p.poisonSkullTimer > 0 then
        local skullAlpha = math.floor(255 * (p.poisonSkullTimer / 0.8))
        local skullScale = 1.0 + (1.0 - p.poisonSkullTimer / 0.8) * 0.3
        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 18 * skullScale)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(200, 50, 255, skullAlpha))
        nvgText(ctx, sx + 20, headDrawY - headR - 15, "💀")
    end

    -- ===== 满毒预警 =====
    if not isGhost and p.alive and p.poison >= 80 then
        local time = GetTime():GetElapsedTime()
        local warnPulse = 0.5 + 0.5 * math.sin(time * 8)
        local warnAlpha = math.floor(80 + warnPulse * 100)
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, 28 + warnPulse * 4)
        nvgStrokeColor(ctx, nvgRGBA(255, 30, 30, warnAlpha))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)
    end

    -- ===== 携带药水头顶图标 =====
    if not isGhost and p.alive and p.potionState then
        local potionImg = potionNvgImages[p.potionState]
        if potionImg then
            local time = GetTime():GetElapsedTime()
            local pulse = 0.7 + 0.3 * math.sin(time * 5)
            local bobY = math.sin(time * 3) * 3
            local indicatorY = headDrawY - headR - 35 + bobY

            local glowR, glowG, glowB = 80, 180, 255
            if p.potionState == "poison" then
                glowR, glowG, glowB = 80, 200, 60
            elseif p.potionState == "victory" then
                glowR, glowG, glowB = 220, 180, 50
            end

            local ringR = 18 + pulse * 4
            local ringAlpha = math.floor(100 + pulse * 80)
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, indicatorY, ringR)
            nvgStrokeColor(ctx, nvgRGBA(glowR, glowG, glowB, ringAlpha))
            nvgStrokeWidth(ctx, 2)
            nvgStroke(ctx)

            local iconSize = 24
            local potionIX = sx - iconSize / 2
            local potionIY = indicatorY - iconSize / 2
            local imgPaint = nvgImagePattern(ctx, potionIX, potionIY, iconSize, iconSize, 0, potionImg, pulse)
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, potionIX, potionIY, iconSize, iconSize, 4)
            nvgFillPaint(ctx, imgPaint)
            nvgFill(ctx)

            -- 向下小箭头
            local arrowY = indicatorY + iconSize / 2 + 4
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, sx, arrowY + 6)
            nvgLineTo(ctx, sx - 4, arrowY)
            nvgLineTo(ctx, sx + 4, arrowY)
            nvgClosePath(ctx)
            nvgFillColor(ctx, nvgRGBA(glowR, glowG, glowB, math.floor(200 * pulse)))
            nvgFill(ctx)

            -- 光粒子环绕
            for k = 1, 4 do
                local angle = time * 3 + k * (math.pi / 2)
                local particleR = ringR * 0.85
                local pkx = sx + math.cos(angle) * particleR
                local pky = indicatorY + math.sin(angle) * particleR * 0.6
                nvgBeginPath(ctx)
                nvgCircle(ctx, pkx, pky, 2 * pulse)
                nvgFillColor(ctx, nvgRGBA(glowR, glowG, glowB, math.floor(150 * pulse)))
                nvgFill(ctx)
            end
        end
    end
end

return M
