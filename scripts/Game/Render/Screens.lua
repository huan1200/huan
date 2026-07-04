-- ============================================================================
-- Game/Render/Screens.lua
-- 全屏界面渲染: 胜利画面 + 失败画面 + 返回主页按钮
-- ============================================================================
local State = require("Game.State")

local M = {}

-- ============================================================================
-- 返回主页按钮(胜利/失败画面共用)
-- ============================================================================
function M.drawBackToMenuButton(ctx, cx, cy, color)
    local btnW = 140
    local btnH = 36
    local btnX = cx - btnW / 2
    local btnY = cy - btnH / 2

    -- 记录按钮区域
    State.backToMenuBtnRect.x = btnX
    State.backToMenuBtnRect.y = btnY
    State.backToMenuBtnRect.w = btnW
    State.backToMenuBtnRect.h = btnH

    -- 按钮背景
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, btnX, btnY, btnW, btnH, 18)
    nvgFillColor(ctx, nvgRGBA(color[1], color[2], color[3], 200))
    nvgFill(ctx)
    -- 边框
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, btnX, btnY, btnW, btnH, 18)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 120))
    nvgStrokeWidth(ctx, 2)
    nvgStroke(ctx)
    -- 文字
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 16)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
    nvgText(ctx, cx, cy, "返回主页", nil)
end

-- ============================================================================
-- 返回主页逻辑
-- ============================================================================
function M.backToMenu()
    State.gamePhase = "menu"
    -- 显示菜单，隐藏HUD
    local menu = State.uiRoot_ and State.uiRoot_:FindById("menuPanel")
    if menu then menu:SetVisible(true) end
    local hud = State.uiRoot_ and State.uiRoot_:FindById("hudPanel")
    if hud then hud:SetVisible(false) end
    -- 隐藏背包
    State.inventoryOpen = false
    local invPanel = State.uiRoot_ and State.uiRoot_:FindById("inventoryPanel")
    if invPanel then invPanel:SetVisible(false) end
end

-- ============================================================================
-- 胜利画面
-- ============================================================================
function M.drawVictoryScreen(logW, logH)
    local ctx = State.nvgContext
    if not ctx then return end

    local players = State.players
    local localPlayerIdx = State.localPlayerIdx
    local pigImages = State.pigImages
    local victoryWinnerIdx = State.victoryWinnerIdx

    -- 背景: 深色渐变
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, logW, logH)
    local bgPaint = nvgLinearGradient(ctx, 0, 0, 0, logH,
        nvgRGBA(10, 15, 30, 255), nvgRGBA(5, 8, 15, 255))
    nvgFillPaint(ctx, bgPaint)
    nvgFill(ctx)

    -- 获胜玩家
    local winner = victoryWinnerIdx and players[victoryWinnerIdx] or nil
    if not winner then return end

    local time = GetTime():GetElapsedTime()
    local cx = logW / 2
    local cy = logH / 2

    -- 光芒放射效果(背景)
    local rayCount = 12
    for i = 1, rayCount do
        local angle = (i / rayCount) * math.pi * 2 + time * 0.3
        local rayLen = 200 + math.sin(time * 2 + i) * 30
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, cx, cy + 20)
        nvgLineTo(ctx, cx + math.cos(angle) * rayLen, cy + 20 + math.sin(angle) * rayLen)
        nvgStrokeColor(ctx, nvgRGBA(255, 215, 80, 25))
        nvgStrokeWidth(ctx, 8)
        nvgStroke(ctx)
    end

    -- 光圈(脉动)
    local pulseR = 100 + math.sin(time * 3) * 10
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy + 20, pulseR)
    local glowPaint = nvgRadialGradient(ctx, cx, cy + 20, pulseR * 0.3, pulseR,
        nvgRGBA(255, 200, 50, 60), nvgRGBA(255, 200, 50, 0))
    nvgFillPaint(ctx, glowPaint)
    nvgFill(ctx)

    -- 全身角色展示(猪角色图片放大)
    local victoryImgW = 160
    local victoryImgH = 160
    local victoryImgX = cx - victoryImgW / 2
    local victoryImgY = cy - victoryImgH / 2 + 10

    -- 阴影
    nvgBeginPath(ctx)
    nvgEllipse(ctx, cx, victoryImgY + victoryImgH + 5, 50, 12)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 80))
    nvgFill(ctx)

    -- 胜利弹跳动画
    local bounce = math.abs(math.sin(time * 3)) * 8
    victoryImgY = victoryImgY - bounce

    -- 绘制猪角色图片(放大)
    local winImgHandle = pigImages[winner.avatarIdx]
    if winImgHandle and winImgHandle ~= 0 and winImgHandle ~= -1 then
        local paint = nvgImagePattern(ctx, victoryImgX, victoryImgY, victoryImgW, victoryImgH, 0, winImgHandle, 1.0)
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, victoryImgX, victoryImgY, victoryImgW, victoryImgH, 12)
        nvgFillPaint(ctx, paint)
        nvgFill(ctx)
        -- 金色边框
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, victoryImgX, victoryImgY, victoryImgW, victoryImgH, 12)
        nvgStrokeColor(ctx, nvgRGBA(255, 215, 50, 200))
        nvgStrokeWidth(ctx, 4)
        nvgStroke(ctx)
    end

    -- 标题文字
    nvgFontFace(ctx, "sans")
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    nvgFontSize(ctx, 48)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 200))
    nvgText(ctx, cx + 3, logH * 0.1 + 3, "胜利!", nil)
    nvgFillColor(ctx, nvgRGBA(255, 215, 50, 255))
    nvgText(ctx, cx, logH * 0.1, "胜利!", nil)

    -- 玩家标识
    local isLocal = (victoryWinnerIdx == localPlayerIdx)
    local nameText = isLocal and "你获得了最终胜利!" or ("玩家 P" .. victoryWinnerIdx .. " 获胜")
    nvgFontSize(ctx, 22)
    nvgFillColor(ctx, nvgRGBA(220, 220, 220, 230))
    nvgText(ctx, cx, logH * 0.88, nameText, nil)

    -- 金色粒子装饰
    for i = 1, 20 do
        local px = cx + math.sin(time * 1.2 + i * 1.7) * (80 + i * 8)
        local py = logH * 0.2 + math.fmod(time * 40 + i * 35, logH * 0.7)
        local pAlpha = math.floor(180 - (py / logH) * 120)
        local pSize = 2 + math.sin(time + i) * 1.5
        nvgBeginPath(ctx)
        nvgCircle(ctx, px, py, pSize)
        nvgFillColor(ctx, nvgRGBA(255, 200, 50, pAlpha))
        nvgFill(ctx)
    end

    -- 返回主页按钮
    M.drawBackToMenuButton(ctx, cx, logH * 0.95, {255, 215, 50})
end

-- ============================================================================
-- 失败画面
-- ============================================================================
function M.drawDefeatScreen(logW, logH)
    local ctx = State.nvgContext
    if not ctx then return end

    local players = State.players
    local localPlayerIdx = State.localPlayerIdx
    local pigImages = State.pigImages

    -- 背景: 暗红渐变
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, logW, logH)
    local bgPaint = nvgLinearGradient(ctx, 0, 0, 0, logH,
        nvgRGBA(20, 5, 5, 255), nvgRGBA(8, 2, 2, 255))
    nvgFillPaint(ctx, bgPaint)
    nvgFill(ctx)

    local time = GetTime():GetElapsedTime()
    local cx = logW / 2

    -- 标题: "全军覆没"
    nvgFontFace(ctx, "sans")
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFontSize(ctx, 42)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 180))
    nvgText(ctx, cx + 2, logH * 0.12 + 2, "全军覆没", nil)
    nvgFillColor(ctx, nvgRGBA(200, 50, 50, 255))
    nvgText(ctx, cx, logH * 0.12, "全军覆没", nil)

    -- 副标题
    nvgFontSize(ctx, 18)
    nvgFillColor(ctx, nvgRGBA(160, 140, 140, 200))
    nvgText(ctx, cx, logH * 0.2, "无人生还...", nil)

    -- 所有玩家死亡头像排列
    local count = #players
    local cardW = 70
    local cardH = 100
    local gap = 12
    local cols = math.min(count, 3)
    local rows = math.ceil(count / cols)
    local totalW = cols * cardW + (cols - 1) * gap
    local totalH = rows * cardH + (rows - 1) * gap
    local startX = (logW - totalW) / 2
    local startY = (logH - totalH) / 2 + 10

    for idx = 1, count do
        local p = players[idx]
        if p then
            local col = ((idx - 1) % cols)
            local row = math.floor((idx - 1) / cols)
            local cardCX = startX + col * (cardW + gap) + cardW / 2
            local cardCY = startY + row * (cardH + gap) + cardH / 2

            -- 卡片背景
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, cardCX - cardW / 2, cardCY - cardH / 2, cardW, cardH, 8)
            nvgFillColor(ctx, nvgRGBA(25, 10, 10, 200))
            nvgFill(ctx)
            nvgStrokeColor(ctx, nvgRGBA(120, 30, 30, 180))
            nvgStrokeWidth(ctx, 2)
            nvgStroke(ctx)

            -- 猪角色头像
            local avatarSize = 40
            local avatarX = cardCX - avatarSize / 2
            local avatarY = cardCY - 24
            local pImgHandle = pigImages[p.avatarIdx]
            if pImgHandle and pImgHandle ~= 0 and pImgHandle ~= -1 then
                local paint = nvgImagePattern(ctx, avatarX, avatarY, avatarSize, avatarSize, 0, pImgHandle, 0.5)
                nvgBeginPath(ctx)
                nvgRoundedRect(ctx, avatarX, avatarY, avatarSize, avatarSize, 6)
                nvgFillPaint(ctx, paint)
                nvgFill(ctx)
            end

            -- 死亡X标记
            local xSize = 10
            local headCY = avatarY + avatarSize / 2
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, cardCX - xSize, headCY - xSize)
            nvgLineTo(ctx, cardCX + xSize, headCY + xSize)
            nvgMoveTo(ctx, cardCX + xSize, headCY - xSize)
            nvgLineTo(ctx, cardCX - xSize, headCY + xSize)
            nvgStrokeColor(ctx, nvgRGBA(200, 40, 40, 220))
            nvgStrokeWidth(ctx, 3)
            nvgStroke(ctx)

            -- 玩家编号
            nvgFontFace(ctx, "sans")
            nvgFontSize(ctx, 14)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(180, 160, 160, 200))
            local label = (idx == localPlayerIdx) and "你" or ("P" .. idx)
            nvgText(ctx, cardCX, cardCY + 30, label, nil)
        end
    end

    -- 底部暗红烟雾效果
    for i = 1, 8 do
        local fogX = cx + math.sin(time * 0.5 + i * 2.3) * (logW * 0.4)
        local fogY = logH * 0.85 + math.sin(time * 0.3 + i) * 15
        local fogR = 60 + math.sin(time + i) * 20
        nvgBeginPath(ctx)
        nvgCircle(ctx, fogX, fogY, fogR)
        local fogPaint = nvgRadialGradient(ctx, fogX, fogY, 0, fogR,
            nvgRGBA(80, 10, 10, 30), nvgRGBA(80, 10, 10, 0))
        nvgFillPaint(ctx, fogPaint)
        nvgFill(ctx)
    end

    -- 返回主页按钮
    M.drawBackToMenuButton(ctx, cx, logH * 0.95, {200, 80, 80})
end

return M
