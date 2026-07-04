-- ============================================================================
-- Game/Render/Circle.lua
-- 毒圈渲染: 紫雾边界 + 酸雨粒子 + 腐蚀动画
-- ============================================================================

local CONFIG = require("Game.Config")
local State = require("Game.State")

local M = {}

-- 工具函数引用(由 init.lua 注入)
M.dist = nil
M.lerp = nil
M.clamp = nil

--- 绘制毒圈(饥荒风 - 紫雾边界)
function M.drawPoisonCircleDST(ox, oy)
    local ctx = State.nvgContext
    local time = GetTime():GetElapsedTime()
    local circle = State.circle
    local dist = M.dist
    local lerp = M.lerp
    local clamp = M.clamp

    local cx = circle.cx + ox
    local cy = circle.cy + oy
    local r = circle.radius
    local fogW = CONFIG.CircleFogWidth

    -- 外部: 紫黑色沼泽(用大矩形减去圆)
    nvgSave(ctx)
    nvgBeginPath(ctx)
    nvgRect(ctx, cx - 3000, cy - 3000, 6000, 6000)
    nvgPathWinding(ctx, NVG_HOLE)
    nvgCircle(ctx, cx, cy, r + fogW * 0.5)
    nvgFillColor(ctx, nvgRGBA(30, 10, 40, 100))
    nvgFill(ctx)
    nvgRestore(ctx)

    -- 边界: 50像素宽的翻滚暗绿色雾霭带
    for layer = 5, 1, -1 do
        local layerOffset = (layer - 3) * (fogW / 5)
        local layerR = r + layerOffset
        local width = fogW / 4 + layer * 2
        local waveOffset = math.sin(time * 0.8 + layer * 0.7) * 3

        nvgBeginPath(ctx)
        nvgCircle(ctx, cx, cy, layerR + waveOffset)
        nvgStrokeWidth(ctx, width)
        local t = (layer - 1) / 4
        local cr = math.floor(lerp(46, 60, t))
        local cg = math.floor(lerp(74, 30, t))
        local cb = math.floor(lerp(62, 80, t))
        local ca = math.floor(lerp(80, 40, t))
        nvgStrokeColor(ctx, nvgRGBA(cr, cg, cb, ca))
        nvgStroke(ctx)
    end

    -- 主边界线(暗绿脉动)
    local pulse = math.sin(time * 2.0) * 0.2 + 0.8
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, r)
    nvgStrokeWidth(ctx, 3 + pulse)
    nvgStrokeColor(ctx, nvgRGBA(46, 100, 62, math.floor(200 * pulse)))
    nvgStroke(ctx)

    -- 内侧微弱绿光
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, r - 3)
    nvgStrokeWidth(ctx, 1.5)
    nvgStrokeColor(ctx, nvgRGBA(46, 74, 62, 50))
    nvgStroke(ctx)

    -- 收缩动画特效: 腐蚀地面效果
    if circle.radius > circle.targetRadius and circle.shrinkSpeed > 0 then
        local totalShrinkDist = circle.shrinkSpeed * CONFIG.DayDuration
        local shrinkProgress = 1.0 - (circle.radius - circle.targetRadius) / (totalShrinkDist + 0.01)
        shrinkProgress = clamp(shrinkProgress, 0, 1)
        local oldR = circle.radius
        local newR = circle.targetRadius
        local corrosionPaint = nvgRadialGradient(ctx,
            cx, cy, newR, oldR + 10,
            nvgRGBA(80, 40, 90, math.floor(60 * shrinkProgress)),
            nvgRGBA(80, 60, 40, 0))
        nvgBeginPath(ctx)
        nvgCircle(ctx, cx, cy, oldR + 10)
        nvgFillPaint(ctx, corrosionPaint)
        nvgFill(ctx)
    end

    -- 酸雨粒子效果(毒圈外区域)
    local camera = State.camera
    local viewL = camera.x - 500
    local viewR = camera.x + 500
    local viewT = camera.y - 400
    local viewB = camera.y + 400
    for i = 1, 30 do
        local seed = i * 137.5
        local px = viewL + math.fmod(seed * 7.13 + time * 40 * ((i % 3) + 1) * 0.3, viewR - viewL)
        local py = viewT + math.fmod(seed * 11.7 + time * 80 * ((i % 4) + 1) * 0.2, viewB - viewT)
        local pdist = dist(px, py, circle.cx, circle.cy)
        if pdist > r + fogW * 0.3 then
            local screenX = px + ox
            local screenY = py + oy
            local dropLen = 4 + (i % 3) * 2
            local alpha = 40 + (i % 5) * 10
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, screenX, screenY)
            nvgLineTo(ctx, screenX - 1, screenY + dropLen)
            nvgStrokeWidth(ctx, 1.2)
            nvgStrokeColor(ctx, nvgRGBA(80, 180, 60, alpha))
            nvgStroke(ctx)
        end
    end

    -- 屏幕边缘紫色波纹(本地玩家在毒圈外时)
    local players = State.players
    local lp = players[State.localPlayerIdx]
    if lp and lp.alive and lp.inPoisonZone then
        local rippleT = math.fmod(time * 1.2, 1.0)
        local edgeAlpha = math.floor((1.0 - rippleT) * 80)
        local graphics = GetGraphics()
        local screenW = graphics:GetWidth() / graphics:GetDPR()
        local screenH = graphics:GetHeight() / graphics:GetDPR()
        local edgeW = 60

        -- 上
        local paintT = nvgLinearGradient(ctx, 0, 0, 0, edgeW,
            nvgRGBA(100, 30, 120, edgeAlpha), nvgRGBA(100, 30, 120, 0))
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, 0, screenW, edgeW)
        nvgFillPaint(ctx, paintT)
        nvgFill(ctx)
        -- 下
        local paintB = nvgLinearGradient(ctx, 0, screenH - edgeW, 0, screenH,
            nvgRGBA(100, 30, 120, 0), nvgRGBA(100, 30, 120, edgeAlpha))
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, screenH - edgeW, screenW, edgeW)
        nvgFillPaint(ctx, paintB)
        nvgFill(ctx)
        -- 左
        local paintL = nvgLinearGradient(ctx, 0, 0, edgeW, 0,
            nvgRGBA(100, 30, 120, edgeAlpha), nvgRGBA(100, 30, 120, 0))
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, 0, edgeW, screenH)
        nvgFillPaint(ctx, paintL)
        nvgFill(ctx)
        -- 右
        local paintR = nvgLinearGradient(ctx, screenW - edgeW, 0, screenW, 0,
            nvgRGBA(100, 30, 120, 0), nvgRGBA(100, 30, 120, edgeAlpha))
        nvgBeginPath(ctx)
        nvgRect(ctx, screenW - edgeW, 0, edgeW, screenH)
        nvgFillPaint(ctx, paintR)
        nvgFill(ctx)
    end
end

return M
