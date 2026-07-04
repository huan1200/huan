-- Game/Render/Overlay.lua
-- 覆盖层渲染模块: 暗角/毒屏/倒计时钟/阶段提示/屏幕外指示/淘汰页/交互UI

local CONFIG = require("Game.Config")
local State = require("Game.State")

local M = {}

-- Forward references (injected by init.lua)
M.findNearestInteractable = nil
M.getAliveCount = nil
M.dist = nil
M.lerp = nil
M.clamp = nil

-- ============================================================================
-- 暗角效果(Vignette)
-- ============================================================================
function M.drawVignette(logW, logH)
    local ctx = State.nvgContext
    local gamePhase = State.gamePhase
    local isDay = (gamePhase == "prepare" or gamePhase == "day" or gamePhase == "shrinking")

    local vignetteAlpha = isDay and 120 or 200

    -- 顶部暗角
    local topGrad = nvgLinearGradient(ctx, 0, 0, 0, logH * 0.25,
        nvgRGBA(0, 0, 0, vignetteAlpha), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, logW, logH * 0.25)
    nvgFillPaint(ctx, topGrad)
    nvgFill(ctx)

    -- 底部暗角
    local botGrad = nvgLinearGradient(ctx, 0, logH * 0.75, 0, logH,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, vignetteAlpha))
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, logH * 0.75, logW, logH * 0.25)
    nvgFillPaint(ctx, botGrad)
    nvgFill(ctx)

    -- 左侧暗角
    local leftGrad = nvgLinearGradient(ctx, 0, 0, logW * 0.2, 0,
        nvgRGBA(0, 0, 0, vignetteAlpha), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, logW * 0.2, logH)
    nvgFillPaint(ctx, leftGrad)
    nvgFill(ctx)

    -- 右侧暗角
    local rightGrad = nvgLinearGradient(ctx, logW * 0.8, 0, logW, 0,
        nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, vignetteAlpha))
    nvgBeginPath(ctx)
    nvgRect(ctx, logW * 0.8, 0, logW * 0.2, logH)
    nvgFillPaint(ctx, rightGrad)
    nvgFill(ctx)

    -- 四角额外加深
    local cornerSize = logW * 0.3
    local cornerAlpha = isDay and 80 or 140

    local cGrad1 = nvgRadialGradient(ctx, 0, 0, 0, cornerSize,
        nvgRGBA(0, 0, 0, cornerAlpha), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, cornerSize, cornerSize)
    nvgFillPaint(ctx, cGrad1)
    nvgFill(ctx)

    local cGrad2 = nvgRadialGradient(ctx, logW, 0, 0, cornerSize,
        nvgRGBA(0, 0, 0, cornerAlpha), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(ctx)
    nvgRect(ctx, logW - cornerSize, 0, cornerSize, cornerSize)
    nvgFillPaint(ctx, cGrad2)
    nvgFill(ctx)

    local cGrad3 = nvgRadialGradient(ctx, 0, logH, 0, cornerSize,
        nvgRGBA(0, 0, 0, cornerAlpha), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, logH - cornerSize, cornerSize, cornerSize)
    nvgFillPaint(ctx, cGrad3)
    nvgFill(ctx)

    local cGrad4 = nvgRadialGradient(ctx, logW, logH, 0, cornerSize,
        nvgRGBA(0, 0, 0, cornerAlpha), nvgRGBA(0, 0, 0, 0))
    nvgBeginPath(ctx)
    nvgRect(ctx, logW - cornerSize, logH - cornerSize, cornerSize, cornerSize)
    nvgFillPaint(ctx, cGrad4)
    nvgFill(ctx)
end

-- ============================================================================
-- 毒药值屏幕边缘绿色液体覆盖
-- ============================================================================
function M.drawPoisonScreenOverlay(logW, logH)
    local players = State.players
    local localPlayerIdx = State.localPlayerIdx
    local p = players[localPlayerIdx]
    if not p or not p.alive then return end

    local poisonRatio = p.poison / CONFIG.PoisonMax
    if poisonRatio <= 0.01 then return end

    local ctx = State.nvgContext
    local time = GetTime():GetElapsedTime()

    local edgeRatio = 0.15 + poisonRatio * 0.35
    local baseAlpha = math.floor(40 + poisonRatio * 160)

    -- 顶部液体
    local topH = logH * edgeRatio
    for seg = 0, 7 do
        local segX = seg * logW / 8
        local segW = logW / 8 + 2
        local wave = math.sin(time * 1.2 + seg * 1.7) * topH * 0.15
        local drip = math.sin(time * 0.8 + seg * 2.3) * topH * 0.1
        local segH = topH + wave + drip
        local grad = nvgLinearGradient(ctx, segX, 0, segX, segH,
            nvgRGBA(20, 60, 30, baseAlpha), nvgRGBA(30, 80, 40, 0))
        nvgBeginPath(ctx)
        nvgRect(ctx, segX, 0, segW, segH)
        nvgFillPaint(ctx, grad)
        nvgFill(ctx)
    end

    -- 底部液体
    local botH = logH * edgeRatio * 0.8
    for seg = 0, 7 do
        local segX = seg * logW / 8
        local segW = logW / 8 + 2
        local wave = math.sin(time * 1.0 + seg * 1.3 + 5.0) * botH * 0.12
        local segH = botH + wave
        local grad = nvgLinearGradient(ctx, segX, logH, segX, logH - segH,
            nvgRGBA(15, 55, 25, baseAlpha), nvgRGBA(25, 70, 35, 0))
        nvgBeginPath(ctx)
        nvgRect(ctx, segX, logH - segH, segW, segH)
        nvgFillPaint(ctx, grad)
        nvgFill(ctx)
    end

    -- 左侧液体
    local leftW = logW * edgeRatio * 0.7
    for seg = 0, 5 do
        local segY = seg * logH / 6
        local segHH = logH / 6 + 2
        local wave = math.sin(time * 0.9 + seg * 2.0 + 3.0) * leftW * 0.18
        local segW = leftW + wave
        local grad = nvgLinearGradient(ctx, 0, segY, segW, segY,
            nvgRGBA(18, 58, 28, baseAlpha), nvgRGBA(28, 75, 38, 0))
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, segY, segW, segHH)
        nvgFillPaint(ctx, grad)
        nvgFill(ctx)
    end

    -- 右侧液体
    local rightW = logW * edgeRatio * 0.7
    for seg = 0, 5 do
        local segY = seg * logH / 6
        local segHH = logH / 6 + 2
        local wave = math.sin(time * 1.1 + seg * 1.8 + 7.0) * rightW * 0.15
        local segW = rightW + wave
        local grad = nvgLinearGradient(ctx, logW, segY, logW - segW, segY,
            nvgRGBA(18, 58, 28, baseAlpha), nvgRGBA(28, 75, 38, 0))
        nvgBeginPath(ctx)
        nvgRect(ctx, logW - segW, segY, segW, segHH)
        nvgFillPaint(ctx, grad)
        nvgFill(ctx)
    end

    -- 四角加深液体
    local cornerR = math.min(logW, logH) * edgeRatio * 0.6
    local cornerAlpha = math.floor(baseAlpha * 0.8)

    local cg1 = nvgRadialGradient(ctx, 0, 0, 0, cornerR,
        nvgRGBA(12, 50, 20, cornerAlpha), nvgRGBA(20, 60, 30, 0))
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, cornerR, cornerR)
    nvgFillPaint(ctx, cg1)
    nvgFill(ctx)

    local cg2 = nvgRadialGradient(ctx, logW, 0, 0, cornerR,
        nvgRGBA(12, 50, 20, cornerAlpha), nvgRGBA(20, 60, 30, 0))
    nvgBeginPath(ctx)
    nvgRect(ctx, logW - cornerR, 0, cornerR, cornerR)
    nvgFillPaint(ctx, cg2)
    nvgFill(ctx)

    local cg3 = nvgRadialGradient(ctx, 0, logH, 0, cornerR,
        nvgRGBA(12, 50, 20, cornerAlpha), nvgRGBA(20, 60, 30, 0))
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, logH - cornerR, cornerR, cornerR)
    nvgFillPaint(ctx, cg3)
    nvgFill(ctx)

    local cg4 = nvgRadialGradient(ctx, logW, logH, 0, cornerR,
        nvgRGBA(12, 50, 20, cornerAlpha), nvgRGBA(20, 60, 30, 0))
    nvgBeginPath(ctx)
    nvgRect(ctx, logW - cornerR, logH - cornerR, cornerR, cornerR)
    nvgFillPaint(ctx, cg4)
    nvgFill(ctx)

    -- 高毒素时添加小气泡粒子
    if poisonRatio > 0.3 then
        local bubbleCount = math.floor(poisonRatio * 6)
        for b = 1, bubbleCount do
            local bx = math.fmod(time * 15 + b * 137.5, logW)
            local by = logH - math.fmod(time * 20 + b * 89.3, logH * edgeRatio * 1.5)
            local br = 2 + math.sin(time * 3 + b) * 1.5
            local ba = math.floor(poisonRatio * 100 * (0.5 + math.sin(time * 2 + b * 1.1) * 0.5))
            nvgBeginPath(ctx)
            nvgCircle(ctx, bx, by, br)
            nvgFillColor(ctx, nvgRGBA(60, 180, 80, ba))
            nvgFill(ctx)
        end
    end
end

-- ============================================================================
-- 淘汰页面绘制
-- ============================================================================
function M.drawEliminationPage(logW, logH)
    local ctx = State.nvgContext
    if not ctx then return end
    local settleDeaths = State.settleDeaths
    if #settleDeaths == 0 then return end

    local players = State.players
    local localPlayerIdx = State.localPlayerIdx
    local pigImages = State.pigImages
    local time = GetTime():GetElapsedTime()

    -- 标题
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 28)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(220, 60, 60, 240))
    nvgText(ctx, logW / 2, logH * 0.25, "本轮淘汰")

    -- 死亡玩家列表
    local count = #settleDeaths
    local cardW = 140
    local cardH = 180
    local gap = 20
    local totalW = count * cardW + (count - 1) * gap
    local startX = (logW - totalW) / 2
    local startY = logH * 0.35

    for idx = 1, count do
        local pIdx = settleDeaths[idx]
        local p = players[pIdx]
        if p then
            local cx = startX + (idx - 1) * (cardW + gap) + cardW / 2
            local cy = startY + cardH / 2

            -- 卡片背景
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, cx - cardW / 2, cy - cardH / 2, cardW, cardH, 8)
            nvgFillColor(ctx, nvgRGBA(30, 20, 20, 180))
            nvgFill(ctx)
            nvgStrokeColor(ctx, nvgRGBA(180, 50, 50, 200))
            nvgStrokeWidth(ctx, 2)
            nvgStroke(ctx)

            -- 猪角色头像
            local avatarSize = 108
            local avatarX = cx - avatarSize / 2
            local avatarY = cy - 50
            local pImgHandle = pigImages[p.avatarIdx]
            if pImgHandle and pImgHandle ~= 0 and pImgHandle ~= -1 then
                local paint = nvgImagePattern(ctx, avatarX, avatarY, avatarSize, avatarSize, 0, pImgHandle, 0.8)
                nvgBeginPath(ctx)
                nvgRoundedRect(ctx, avatarX, avatarY, avatarSize, avatarSize, 6)
                nvgFillPaint(ctx, paint)
                nvgFill(ctx)
            end

            -- 死亡标记(红色X)
            local headY = avatarY + avatarSize / 2
            local xSize = 24
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, cx - xSize, headY - xSize)
            nvgLineTo(ctx, cx + xSize, headY + xSize)
            nvgMoveTo(ctx, cx + xSize, headY - xSize)
            nvgLineTo(ctx, cx - xSize, headY + xSize)
            nvgStrokeColor(ctx, nvgRGBA(240, 40, 40, 240))
            nvgStrokeWidth(ctx, 3)
            nvgStroke(ctx)

            -- 玩家编号
            nvgFontFace(ctx, "sans")
            nvgFontSize(ctx, 20)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(200, 200, 200, 220))
            local label = (pIdx == localPlayerIdx) and "你" or ("P" .. pIdx)
            nvgText(ctx, cx, cy + 70, label)

            -- 死因标注
            nvgFontSize(ctx, 11)
            nvgFillColor(ctx, nvgRGBA(100, 200, 100, 180))
            nvgText(ctx, cx, cy + 42, "中毒")
        end
    end

    -- 存活人数提示
    local aliveCount = M.getAliveCount and M.getAliveCount() or 0
    nvgFontSize(ctx, 16)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(180, 180, 180, 200))
    nvgText(ctx, logW / 2, logH * 0.72, "剩余存活: " .. aliveCount .. " 人")
end

-- ============================================================================
-- 倒计时钟表绘制(老式钟表样式)
-- ============================================================================
function M.drawClockCountdown(logW, logH)
    local ctx = State.nvgContext
    local gamePhase = State.gamePhase
    local settleSubPhase = State.settleSubPhase
    local phaseTimer = State.phaseTimer
    local fontId = State.fontId
    local time = GetTime():GetElapsedTime()

    if not (gamePhase == "settle" and settleSubPhase == "countdown") then
        return
    end

    local countdown = phaseTimer
    if countdown <= 0 then return end

    local seconds = math.ceil(countdown)
    local cx = logW / 2
    local cy = logH / 2

    -- 最后2秒放大+震动
    local scale = 1.0
    local shakeX, shakeY = 0, 0
    if countdown <= 2.0 then
        scale = 1.0 + (1.0 - countdown / 2.0) * 0.5
        shakeX = math.sin(time * 30) * 3 * (1.0 - countdown / 2.0)
        shakeY = math.cos(time * 25) * 2 * (1.0 - countdown / 2.0)
    end

    nvgSave(ctx)
    nvgTranslate(ctx, cx + shakeX, cy + shakeY)
    nvgScale(ctx, scale, scale)

    local clockR = 44

    -- 钟表外壳
    nvgBeginPath(ctx)
    nvgCircle(ctx, 0, 0, clockR + 5)
    nvgStrokeColor(ctx, nvgRGBA(120, 85, 40, 220))
    nvgStrokeWidth(ctx, 4.5)
    nvgStroke(ctx)

    nvgBeginPath(ctx)
    nvgCircle(ctx, 0, 0, clockR)
    nvgStrokeColor(ctx, nvgRGBA(90, 65, 30, 200))
    nvgStrokeWidth(ctx, 2.5)
    nvgStroke(ctx)

    -- 表盘背景
    local facePaint = nvgRadialGradient(ctx, 0, 0, 0, clockR,
        nvgRGBA(240, 225, 190, 220), nvgRGBA(210, 195, 155, 200))
    nvgBeginPath(ctx)
    nvgCircle(ctx, 0, 0, clockR - 1)
    nvgFillPaint(ctx, facePaint)
    nvgFill(ctx)

    -- 刻度线
    for tick = 1, 12 do
        local angle = (tick / 12) * math.pi * 2 - math.pi / 2
        local inner = clockR - 6
        local outer = clockR - 2
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, math.cos(angle) * inner, math.sin(angle) * inner)
        nvgLineTo(ctx, math.cos(angle) * outer, math.sin(angle) * outer)
        nvgStrokeColor(ctx, nvgRGBA(60, 45, 20, 200))
        nvgStrokeWidth(ctx, tick % 3 == 0 and 2 or 1)
        nvgStroke(ctx)
    end

    -- 秒针
    local secFrac = 1.0 - (countdown - math.floor(countdown))
    local secAngle = secFrac * math.pi * 2 - math.pi / 2
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, 0, 0)
    nvgLineTo(ctx, math.cos(secAngle) * (clockR - 8), math.sin(secAngle) * (clockR - 8))
    nvgStrokeColor(ctx, nvgRGBA(180, 30, 20, 230))
    nvgStrokeWidth(ctx, 1.5)
    nvgStroke(ctx)

    -- 中心铆钉
    nvgBeginPath(ctx)
    nvgCircle(ctx, 0, 0, 4)
    nvgFillColor(ctx, nvgRGBA(80, 60, 30, 240))
    nvgFill(ctx)

    -- 顶部小环
    nvgBeginPath(ctx)
    nvgCircle(ctx, 0, -(clockR + 10), 7)
    nvgStrokeColor(ctx, nvgRGBA(120, 85, 40, 200))
    nvgStrokeWidth(ctx, 2.5)
    nvgStroke(ctx)

    nvgRestore(ctx)

    -- 倒计时数字
    if fontId ~= -1 then
        nvgSave(ctx)
        nvgTranslate(ctx, cx + shakeX, cy + shakeY)
        nvgScale(ctx, scale, scale)

        nvgFontFaceId(ctx, fontId)
        nvgFontSize(ctx, 32)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

        nvgFillColor(ctx, nvgRGBA(40, 30, 15, 150))
        nvgText(ctx, 1, clockR + 10 + 1, tostring(seconds) .. "s", nil)
        local urgency = countdown <= 2.0 and 255 or 200
        nvgFillColor(ctx, nvgRGBA(urgency, math.floor(urgency * 0.4), 20, 240))
        nvgText(ctx, 0, clockR + 10, tostring(seconds) .. "s", nil)

        nvgRestore(ctx)
    end
end

-- ============================================================================
-- 屏幕边缘方向指示标
-- ============================================================================
function M.drawOffscreenIndicators(logW, logH, offsetX, offsetY, zoom)
    local ctx = State.nvgContext
    local gamePhase = State.gamePhase
    local camera = State.camera
    local comfortZones = State.comfortZones
    local players = State.players
    local localPlayerIdx = State.localPlayerIdx
    local fontId = State.fontId

    zoom = zoom or 1.0
    if gamePhase == "menu" or gamePhase == "victory" or gamePhase == "defeat" then return end
    if gamePhase == "settle" then return end

    local time = GetTime():GetElapsedTime()
    local padding = 40
    local arrowSize = 14
    local iconSize = 22

    local centerX = logW / 2
    local centerY = logH / 2

    local targets = {}

    -- 1. 非腐化舒适区
    for _, zone in ipairs(comfortZones) do
        if not zone.corrupted then
            local sx = (zone.x - camera.x) * zoom + logW / 2
            local sy = (zone.y - camera.y) * zoom + logH / 2
            if sx < -20 or sx > logW + 20 or sy < -20 or sy > logH + 20 then
                local r, g, b = 255, 200, 60
                if zone.type == "spring" then
                    r, g, b = 80, 200, 255
                elseif zone.type == "altar" then
                    r, g, b = 180, 100, 255
                end
                table.insert(targets, {sx = sx, sy = sy, kind = "zone", r = r, g = g, b = b, label = "☀"})
            end
        end
    end

    -- 2. 携带解药的存活玩家(排除自己)
    for i, p in ipairs(players) do
        if i ~= localPlayerIdx and p.alive and p.potionState == "antidote" then
            local sx = (p.x - camera.x) * zoom + logW / 2
            local sy = (p.y - camera.y) * zoom + logH / 2
            if sx < -20 or sx > logW + 20 or sy < -20 or sy > logH + 20 then
                table.insert(targets, {sx = sx, sy = sy, kind = "antidote", r = 60, g = 200, b = 255, label = "✚"})
            end
        end
    end

    if #targets == 0 then return end

    for _, t in ipairs(targets) do
        local dx = t.sx - centerX
        local dy = t.sy - centerY
        local angle = math.atan(dy, dx)

        local edgeX, edgeY
        local halfW = centerX - padding
        local halfH = centerY - padding

        local cosA = math.cos(angle)
        local sinA = math.sin(angle)
        local scaleX = (cosA ~= 0) and math.abs(halfW / cosA) or 99999
        local scaleY = (sinA ~= 0) and math.abs(halfH / sinA) or 99999
        local sc = math.min(scaleX, scaleY)

        edgeX = centerX + cosA * sc
        edgeY = centerY + sinA * sc

        edgeX = math.max(padding, math.min(logW - padding, edgeX))
        edgeY = math.max(padding, math.min(logH - padding, edgeY))

        local distToTarget = math.sqrt(dx * dx + dy * dy)
        local pulse = 0.7 + 0.3 * math.sin(time * 3 + angle * 2)
        local alpha = math.floor(220 * pulse)

        nvgSave(ctx)
        nvgTranslate(ctx, edgeX, edgeY)
        nvgRotate(ctx, angle)

        -- 外发光
        nvgBeginPath(ctx)
        nvgCircle(ctx, 0, 0, iconSize + 4)
        nvgFillColor(ctx, nvgRGBA(t.r, t.g, t.b, math.floor(alpha * 0.3)))
        nvgFill(ctx)

        -- 圆形背景
        nvgBeginPath(ctx)
        nvgCircle(ctx, 0, 0, iconSize)
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(alpha * 0.7)))
        nvgFill(ctx)
        nvgStrokeColor(ctx, nvgRGBA(t.r, t.g, t.b, alpha))
        nvgStrokeWidth(ctx, 2.0)
        nvgStroke(ctx)

        -- 箭头尖端
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, iconSize + arrowSize, 0)
        nvgLineTo(ctx, iconSize - 2, -arrowSize * 0.6)
        nvgLineTo(ctx, iconSize - 2, arrowSize * 0.6)
        nvgClosePath(ctx)
        nvgFillColor(ctx, nvgRGBA(t.r, t.g, t.b, alpha))
        nvgFill(ctx)

        -- 内部图标(旋转回正)
        nvgRotate(ctx, -angle)
        if fontId ~= -1 then
            nvgFontFaceId(ctx, fontId)
            nvgFontSize(ctx, 14)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(t.r, t.g, t.b, alpha))
            nvgText(ctx, 0, 0, t.label)
        end

        nvgRestore(ctx)

        -- 距离文字
        local distMeters = math.floor(distToTarget / 10)
        if distMeters > 0 and fontId ~= -1 then
            nvgFontFaceId(ctx, fontId)
            nvgFontSize(ctx, 11)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(ctx, nvgRGBA(t.r, t.g, t.b, math.floor(alpha * 0.8)))
            nvgText(ctx, edgeX, edgeY + iconSize + 4, tostring(distMeters) .. "m")
        end
    end
end

-- ============================================================================
-- 阶段提示文字
-- ============================================================================
function M.drawPhaseHint(logW, logH)
    local ctx = State.nvgContext
    local fontId = State.fontId
    local gamePhase = State.gamePhase
    local settleSubPhase = State.settleSubPhase
    local phaseTimer = State.phaseTimer
    local settleDeaths = State.settleDeaths

    if fontId == -1 then return end

    local time = GetTime():GetElapsedTime()
    local hint = nil
    local timerText = nil
    local hintColor = {200, 200, 200, 220}
    local fontSize = 22

    if gamePhase == "prepare" then
        hint = "战斗即将开始..."
        timerText = tostring(math.ceil(phaseTimer))
        hintColor = {200, 140, 30, 220}
    elseif gamePhase == "settle" and settleSubPhase == "countdown" then
        hint = "黑夜降临!"
        hintColor = {200, 20, 20, 255}
        fontSize = 28
    elseif gamePhase == "day" then
        if phaseTimer <= 5.0 then
            hint = "黑夜即将来临!"
            local pulse = math.sin(time * 8)
            local a = math.floor(180 + 75 * pulse)
            hintColor = {220, 40, 40, a}
        end
    elseif gamePhase == "settle" and settleSubPhase == "elimination" then
        if #settleDeaths > 0 then
            hint = #settleDeaths .. " 人被毒素吞噬..."
        else
            hint = "全员存活!"
        end
        hintColor = {180, 60, 60, 220}
    elseif gamePhase == "shrinking" then
        hint = "下一轮准备..."
        timerText = tostring(math.ceil(phaseTimer))
        hintColor = {150, 150, 180, 200}
    end

    if not hint then return end

    local cx = logW / 2
    local cy = (gamePhase == "settle" and settleSubPhase == "countdown") and (logH * 0.33) or (logH * 0.15)

    nvgFontFaceId(ctx, fontId)
    nvgFontSize(ctx, fontSize)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 文字阴影
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(hintColor[4] * 0.6)))
    nvgText(ctx, cx + 2, cy + 2, hint, nil)
    -- 文字本体
    nvgFillColor(ctx, nvgRGBA(hintColor[1], hintColor[2], hintColor[3], hintColor[4]))
    nvgText(ctx, cx, cy, hint, nil)

    -- 阶段计时器数字
    if timerText then
        nvgFontSize(ctx, 36)
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, 150))
        nvgText(ctx, cx + 2, cy + 32, timerText, nil)
        nvgFillColor(ctx, nvgRGBA(hintColor[1], hintColor[2], hintColor[3], hintColor[4]))
        nvgText(ctx, cx, cy + 30, timerText, nil)
    end
end

-- ============================================================================
-- 交互UI(按钮提示+选项面板+抛物线动画+连接线)
-- ============================================================================
function M.drawInteractionUI(logW, logH, ox, oy)
    local ctx = State.nvgContext
    local players = State.players
    local localPlayerIdx = State.localPlayerIdx
    local gamePhase = State.gamePhase
    local fontId = State.fontId
    local lerp = M.lerp
    local clamp = M.clamp

    local p = players[localPlayerIdx]
    if not p or not p.alive then return end
    if gamePhase ~= "day" then return end

    local time = GetTime():GetElapsedTime()

    -- 8.2a 交互按钮提示: 靠近可交互玩家时显示 [E] 图标
    if p.interactState == "idle" then
        local findNearestInteractable = M.findNearestInteractable
        local targetIdx = findNearestInteractable and findNearestInteractable(p) or nil
        if targetIdx then
            local target = players[targetIdx]
            local sx = target.x + ox
            local sy = target.y + oy - 60
            local pulse = 0.7 + math.sin(time * 4) * 0.3

            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy, 12)
            nvgFillColor(ctx, nvgRGBA(200, 180, 50, math.floor(160 * pulse)))
            nvgFill(ctx)
            nvgStrokeColor(ctx, nvgRGBA(255, 220, 80, math.floor(220 * pulse)))
            nvgStrokeWidth(ctx, 2)
            nvgStroke(ctx)

            nvgFontFace(ctx, "sans")
            nvgFontSize(ctx, 14)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(20, 15, 10, 255))
            nvgText(ctx, sx, sy, "E")
        end
    end

    -- 8.2b 等待接受提示(pending状态)
    if p.interactState == "pending" then
        local panelW = 160
        local panelH = 40
        local px = logW / 2 - panelW / 2
        local py = logH * 0.3

        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, px, py, panelW, panelH, 6)
        nvgFillColor(ctx, nvgRGBA(20, 18, 15, 200))
        nvgFill(ctx)
        nvgStrokeColor(ctx, nvgRGBA(200, 180, 50, 180))
        nvgStrokeWidth(ctx, 1.5)
        nvgStroke(ctx)

        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 12)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(240, 220, 100, 240))
        nvgText(ctx, logW / 2, py + 14, "收到交互请求!")
        nvgFontSize(ctx, 10)
        nvgFillColor(ctx, nvgRGBA(180, 180, 160, 200))
        local remain = math.max(0, p.interactTimer)
        nvgText(ctx, logW / 2, py + 28, string.format("[E]接受  [Q]拒绝  %.1fs", remain))
    end

    -- 8.2c 交互选项面板(interacting状态)
    if p.interactState == "interacting" then
        local panelW = 180
        local panelH = 60
        local px = logW / 2 - panelW / 2
        local py = logH * 0.25

        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, px, py, panelW, panelH, 8)
        nvgFillColor(ctx, nvgRGBA(15, 12, 10, 220))
        nvgFill(ctx)
        nvgStrokeColor(ctx, nvgRGBA(100, 200, 150, 150))
        nvgStrokeWidth(ctx, 1.5)
        nvgStroke(ctx)

        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 12)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(100, 255, 200, 240))
        local remain = math.max(0, p.interactTimer)
        nvgText(ctx, logW / 2, py + 14, string.format("交互中 (%.1fs)", remain))

        nvgFontSize(ctx, 11)
        if p.potionState then
            nvgFillColor(ctx, nvgRGBA(200, 200, 180, 220))
            nvgText(ctx, logW / 2, py + 32, "[1]给予解药  [2]给予毒药")
            nvgFontSize(ctx, 9)
            nvgFillColor(ctx, nvgRGBA(150, 150, 130, 160))
            nvgText(ctx, logW / 2, py + 48, "[Q]取消  对方看不到你给的是什么")
        else
            nvgFillColor(ctx, nvgRGBA(180, 120, 80, 200))
            nvgText(ctx, logW / 2, py + 32, "无药可给  等待对方...")
            nvgFontSize(ctx, 9)
            nvgFillColor(ctx, nvgRGBA(150, 150, 130, 160))
            nvgText(ctx, logW / 2, py + 48, "[Q]取消")
        end
    end

    -- 8.2d 抛物线动画(所有玩家的giving状态)
    for i = 1, #players do
        local giver = players[i]
        if giver.interactState == "giving" and giver.interactFlyAnim then
            local anim = giver.interactFlyAnim
            local progress = clamp(anim.t / anim.duration, 0, 1)

            local fx = lerp(anim.fromX, anim.toX, progress)
            local fy = lerp(anim.fromY, anim.toY, progress)
            local arcHeight = -40 * (4 * progress * (1 - progress))
            fy = fy + arcHeight

            local sx = fx + ox
            local sy = fy + oy

            local glowR, glowG, glowB = 200, 200, 150
            if giver.isLocal then
                if anim.type == "antidote" then
                    glowR, glowG, glowB = 80, 200, 255
                else
                    glowR, glowG, glowB = 180, 60, 200
                end
            end

            local grad = nvgRadialGradient(ctx, sx, sy, 2, 12,
                nvgRGBA(glowR, glowG, glowB, 200),
                nvgRGBA(glowR, glowG, glowB, 0))
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy, 12)
            nvgFillPaint(ctx, grad)
            nvgFill(ctx)

            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy, 4)
            nvgFillColor(ctx, nvgRGBA(glowR, glowG, glowB, 240))
            nvgFill(ctx)

            -- 拖尾
            for k = 1, 3 do
                local tp = clamp(progress - k * 0.08, 0, 1)
                local tx = lerp(anim.fromX, anim.toX, tp) + ox
                local ty = lerp(anim.fromY, anim.toY, tp) + (-40 * (4 * tp * (1 - tp))) + oy
                local ta = math.floor(120 - k * 35)
                nvgBeginPath(ctx)
                nvgCircle(ctx, tx, ty, 3 - k * 0.7)
                nvgFillColor(ctx, nvgRGBA(glowR, glowG, glowB, ta))
                nvgFill(ctx)
            end
        end
    end

    -- 8.2e 交互连接线
    if p.interactState ~= "idle" and p.interactPartner then
        local partner = players[p.interactPartner]
        if partner then
            local sx1 = p.x + ox
            local sy1 = p.y + oy - 20
            local sx2 = partner.x + ox
            local sy2 = partner.y + oy - 20

            local pulse = 0.5 + math.sin(time * 6) * 0.5
            nvgStrokeColor(ctx, nvgRGBA(200, 180, 80, math.floor(100 * pulse)))
            nvgStrokeWidth(ctx, 1.5)
            nvgLineCap(ctx, NVG_ROUND)

            local dx = sx2 - sx1
            local dy = sy2 - sy1
            local length = math.sqrt(dx * dx + dy * dy)
            if length > 1 then
                local segments = math.floor(length / 8)
                for seg = 0, segments - 1, 2 do
                    local t1 = seg / segments
                    local t2 = math.min((seg + 1) / segments, 1.0)
                    nvgBeginPath(ctx)
                    nvgMoveTo(ctx, sx1 + dx * t1, sy1 + dy * t1)
                    nvgLineTo(ctx, sx1 + dx * t2, sy1 + dy * t2)
                    nvgStroke(ctx)
                end
            end
        end
    end
end

return M
