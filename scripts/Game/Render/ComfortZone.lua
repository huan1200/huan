-- Game/Render/ComfortZone.lua
-- 舒适区渲染模块: 腐化区域 + 正常区域(篝火/清泉/圣坛) + 信标 + 能量条 + 浮动数字

local CONFIG = require("Game.Config")
local State = require("Game.State")

local M = {}

-- Forward references (injected by init.lua)
M.dist = nil

--- 绘制所有舒适区
---@param ox number 偏移X
---@param oy number 偏移Y
function M.drawComfortZones(ox, oy)
    local ctx = State.nvgContext
    local comfortZones = State.comfortZones
    local comfortFloats = State.comfortFloats
    local players = State.players
    local fontId = State.fontId
    local time = GetTime():GetElapsedTime()
    local dist = M.dist

    for _, zone in ipairs(comfortZones) do
        local sx = zone.x + ox
        local sy = zone.y + oy
        local lightR = CONFIG.ComfortZoneRadius

        -- 7.3 腐化舒适区(暗色废墟 + 诅咒粒子)
        if zone.corrupted then
            -- 暗色废墟圆圈(暗紫色边缘)
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy, lightR * 0.8)
            nvgStrokeColor(ctx, nvgRGBA(40, 20, 50, 60))
            nvgStrokeWidth(ctx, 1.5)
            nvgStroke(ctx)

            -- 暗色地面
            local darkPaint = nvgRadialGradient(ctx, sx, sy, 0, lightR * 0.6,
                nvgRGBA(20, 15, 25, 80), nvgRGBA(20, 15, 25, 0))
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy, lightR * 0.6)
            nvgFillPaint(ctx, darkPaint)
            nvgFill(ctx)

            -- 破碎石块(废墟中心)
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, sx - 8, sy + 2)
            nvgLineTo(ctx, sx - 5, sy - 2)
            nvgLineTo(ctx, sx + 6, sy - 1)
            nvgLineTo(ctx, sx + 8, sy + 3)
            nvgClosePath(ctx)
            nvgFillColor(ctx, nvgRGBA(40, 35, 30, 180))
            nvgFill(ctx)
            -- 暗紫光点
            local flicker = math.sin(time * 2) * 0.3 + 0.5
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy - 5, 2 * flicker)
            nvgFillColor(ctx, nvgRGBA(80, 30, 100, math.floor(80 * flicker)))
            nvgFill(ctx)

            goto continueZone
        end

        -- 检测是否有玩家在此舒适区内
        local hasPlayerInside = false
        for _, p in ipairs(players) do
            if p.alive and not p.isGhost and dist(p.x, p.y, zone.x, zone.y) <= lightR then
                hasPlayerInside = true
                break
            end
        end

        -- 7.4 边缘光圈(默认30%透明度, 有玩家时高亮)
        local baseAlpha = hasPlayerInside and 60 or 25
        local pulse = 1.0 + math.sin(time * 1.5) * 0.05

        -- 边缘圆环(微弱虚线感)
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, lightR * pulse)
        nvgStrokeColor(ctx, nvgRGBA(139, 105, 20, baseAlpha + 15))
        nvgStrokeWidth(ctx, hasPlayerInside and 1.5 or 0.8)
        nvgStroke(ctx)

        -- 径向渐变光圈
        local paint = nvgRadialGradient(ctx,
            sx, sy, lightR * 0.15 * pulse, lightR * pulse,
            nvgRGBA(139, 105, 20, baseAlpha),
            nvgRGBA(139, 105, 20, 0))
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, lightR * pulse)
        nvgFillPaint(ctx, paint)
        nvgFill(ctx)

        -- 有玩家时额外暖光层
        if hasPlayerInside then
            local glowPaint = nvgRadialGradient(ctx,
                sx, sy, 0, lightR * 0.6,
                nvgRGBA(200, 150, 50, 30),
                nvgRGBA(200, 150, 50, 0))
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy, lightR * 0.6)
            nvgFillPaint(ctx, glowPaint)
            nvgFill(ctx)
        end

        -- 中心装饰物
        if zone.type == "campfire" then
            -- 篝火: 木材堆 + 火焰
            nvgStrokeColor(ctx, nvgRGBA(50, 30, 15, 200))
            nvgStrokeWidth(ctx, 3)
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, sx - 8, sy + 3)
            nvgLineTo(ctx, sx + 8, sy - 2)
            nvgStroke(ctx)
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, sx + 6, sy + 4)
            nvgLineTo(ctx, sx - 6, sy - 1)
            nvgStroke(ctx)
            -- 第三根木柴
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, sx - 3, sy + 5)
            nvgLineTo(ctx, sx + 5, sy + 1)
            nvgStroke(ctx)
            -- 火焰(暗黄色, 跳动)
            local flicker2 = math.sin(time * 8) * 2
            nvgBeginPath(ctx)
            nvgEllipse(ctx, sx + flicker2 * 0.3, sy - 6 + flicker2 * 0.2, 4, 7 + flicker2)
            nvgFillColor(ctx, nvgRGBA(180, 110, 20, 160))
            nvgFill(ctx)
            nvgBeginPath(ctx)
            nvgEllipse(ctx, sx, sy - 9, 2.5, 4 + math.sin(time * 12) * 1.5)
            nvgFillColor(ctx, nvgRGBA(220, 160, 30, 180))
            nvgFill(ctx)
            -- 火星粒子
            for spark = 1, 3 do
                local sparkT = math.fmod(time * 2 + spark * 1.3, 2.0)
                if sparkT < 1.0 then
                    local sparkX = sx + math.sin(time * 3 + spark) * 4
                    local sparkY = sy - 12 - sparkT * 15
                    nvgBeginPath(ctx)
                    nvgCircle(ctx, sparkX, sparkY, 1.2 * (1.0 - sparkT))
                    nvgFillColor(ctx, nvgRGBA(240, 180, 40, math.floor((1.0 - sparkT) * 150)))
                    nvgFill(ctx)
                end
            end

        elseif zone.type == "spring" then
            -- 腐败清泉: 绿色水池 + 中央清水 + 白光
            nvgBeginPath(ctx)
            nvgEllipse(ctx, sx, sy, 14, 9)
            nvgFillColor(ctx, nvgRGBA(50, 80, 60, 130))
            nvgFill(ctx)
            nvgBeginPath(ctx)
            nvgEllipse(ctx, sx, sy, 6, 4)
            nvgFillColor(ctx, nvgRGBA(120, 180, 200, 150))
            nvgFill(ctx)
            local glow = 0.6 + math.sin(time * 3) * 0.3
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy - 2, 2.5 * glow)
            nvgFillColor(ctx, nvgRGBA(220, 240, 255, math.floor(180 * glow)))
            nvgFill(ctx)
            -- 涟漪
            local ripple = math.fmod(time * 0.5, 1.0)
            nvgBeginPath(ctx)
            nvgCircle(ctx, sx, sy, 4 + ripple * 12)
            nvgStrokeColor(ctx, nvgRGBA(100, 160, 140, math.floor((1.0 - ripple) * 60)))
            nvgStrokeWidth(ctx, 1)
            nvgStroke(ctx)

        elseif zone.type == "altar" then
            -- 破碎圣坛: 石块堆砌 + 暗红蜡烛
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, sx - 10, sy + 3)
            nvgLineTo(ctx, sx - 7, sy - 2)
            nvgLineTo(ctx, sx + 8, sy - 3)
            nvgLineTo(ctx, sx + 10, sy + 2)
            nvgLineTo(ctx, sx + 5, sy + 5)
            nvgLineTo(ctx, sx - 6, sy + 5)
            nvgClosePath(ctx)
            nvgFillColor(ctx, nvgRGBA(75, 68, 55, 210))
            nvgFill(ctx)
            nvgStrokeColor(ctx, nvgRGBA(30, 25, 20, 180))
            nvgStrokeWidth(ctx, 1.5)
            nvgStroke(ctx)
            -- 碎石块
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, sx - 12, sy + 1, 5, 4, 1)
            nvgFillColor(ctx, nvgRGBA(60, 55, 45, 180))
            nvgFill(ctx)
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, sx + 8, sy, 4, 3, 1)
            nvgFillColor(ctx, nvgRGBA(65, 58, 48, 170))
            nvgFill(ctx)
            -- 蜡烛(暗红色)
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, sx - 2, sy - 12, 4, 10, 1)
            nvgFillColor(ctx, nvgRGBA(100, 30, 25, 200))
            nvgFill(ctx)
            -- 蜡烛火焰
            local candleFlicker = math.sin(time * 6) * 0.8
            nvgBeginPath(ctx)
            nvgEllipse(ctx, sx + candleFlicker * 0.5, sy - 14, 2, 3 + candleFlicker)
            nvgFillColor(ctx, nvgRGBA(180, 80, 30, 180))
            nvgFill(ctx)
            nvgBeginPath(ctx)
            nvgEllipse(ctx, sx, sy - 15, 1, 2)
            nvgFillColor(ctx, nvgRGBA(240, 160, 50, 200))
            nvgFill(ctx)
        end

        -- ===== 舒适区指示标志(浮动菱形信标 + 类型图标) =====
        if not zone.corrupted then
            local bobY = math.sin(time * 2.5 + zone.x * 0.1) * 4
            local beaconY = sy - CONFIG.ComfortZoneRadius - 20 + bobY
            local beaconAlpha = 180 + math.floor(math.sin(time * 3) * 50)

            -- 发光菱形信标
            local bSize = 8
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, sx, beaconY - bSize)
            nvgLineTo(ctx, sx + bSize * 0.6, beaconY)
            nvgLineTo(ctx, sx, beaconY + bSize)
            nvgLineTo(ctx, sx - bSize * 0.6, beaconY)
            nvgClosePath(ctx)

            -- 根据类型上色
            local bR, bG, bB = 255, 180, 50  -- 篝火: 暖黄
            if zone.type == "spring" then
                bR, bG, bB = 100, 200, 240   -- 清泉: 蓝色
            elseif zone.type == "altar" then
                bR, bG, bB = 200, 160, 255   -- 圣坛: 紫色
            end

            nvgFillColor(ctx, nvgRGBA(bR, bG, bB, beaconAlpha))
            nvgFill(ctx)
            nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, math.floor(beaconAlpha * 0.6)))
            nvgStrokeWidth(ctx, 1.5)
            nvgStroke(ctx)

            -- 光柱(从信标向下延伸到舒适区中心)
            local pillarGrad = nvgLinearGradient(ctx, sx, beaconY + bSize, sx, sy,
                nvgRGBA(bR, bG, bB, 60), nvgRGBA(bR, bG, bB, 0))
            nvgBeginPath(ctx)
            nvgRect(ctx, sx - 2, beaconY + bSize, 4, sy - beaconY - bSize)
            nvgFillPaint(ctx, pillarGrad)
            nvgFill(ctx)

            -- 类型图标文字(在信标上方)
            if fontId ~= -1 then
                nvgFontFaceId(ctx, fontId)
                nvgFontSize(ctx, 12)
                nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
                nvgFillColor(ctx, nvgRGBA(bR, bG, bB, beaconAlpha))
                local label = "🔥"
                if zone.type == "spring" then label = "��"
                elseif zone.type == "altar" then label = "⛩" end
                nvgText(ctx, sx, beaconY - bSize - 2, label)
            end
        end

        -- ===== 舒适区能量条 + 冷却/次数显示 =====
        if not zone.corrupted then
            local barW = 60
            local barH = 6
            local barX = sx - barW / 2
            local barY = sy + 20

            local energy = zone.zoneEnergy or 100
            local cooldown = zone.zoneCooldown or 0
            local usesLeft = zone.zoneUsesLeft or 5

            if usesLeft <= 0 then
                -- 已耗尽: 显示"已耗尽"文字
                nvgFontFace(ctx, "sans")
                nvgFontSize(ctx, 10)
                nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx, nvgRGBA(180, 60, 60, 200))
                nvgText(ctx, sx, barY + barH / 2, "已耗尽")
            elseif cooldown > 0 then
                -- 冷却中: 灰色背景条 + 冷却倒计时
                nvgBeginPath(ctx)
                nvgRoundedRect(ctx, barX, barY, barW, barH, 3)
                nvgFillColor(ctx, nvgRGBA(40, 40, 40, 160))
                nvgFill(ctx)
                local cdRatio = cooldown / 5.0
                nvgBeginPath(ctx)
                nvgRoundedRect(ctx, barX, barY, barW * cdRatio, barH, 3)
                nvgFillColor(ctx, nvgRGBA(100, 100, 120, 180))
                nvgFill(ctx)
                nvgFontFace(ctx, "sans")
                nvgFontSize(ctx, 9)
                nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(ctx, nvgRGBA(200, 200, 200, 220))
                nvgText(ctx, sx, barY + barH / 2, string.format("%.1fs", cooldown))
            else
                -- 正常: 能量条
                nvgBeginPath(ctx)
                nvgRoundedRect(ctx, barX, barY, barW, barH, 3)
                nvgFillColor(ctx, nvgRGBA(30, 30, 30, 150))
                nvgFill(ctx)
                local ratio = energy / 100
                local eR = math.floor(80 + (1 - ratio) * 150)
                local eG = math.floor(200 * ratio)
                nvgBeginPath(ctx)
                nvgRoundedRect(ctx, barX, barY, barW * ratio, barH, 3)
                nvgFillColor(ctx, nvgRGBA(eR, eG, 40, 200))
                nvgFill(ctx)
                nvgBeginPath(ctx)
                nvgRoundedRect(ctx, barX, barY, barW, barH, 3)
                nvgStrokeColor(ctx, nvgRGBA(139, 105, 20, 80))
                nvgStrokeWidth(ctx, 0.8)
                nvgStroke(ctx)
            end

            -- 剩余次数(小点)
            if usesLeft > 0 then
                local dotR = 2.5
                local dotGap = 8
                local dotsW = usesLeft * dotGap
                local dotStartX = sx - dotsW / 2 + dotGap / 2
                for di = 1, usesLeft do
                    nvgBeginPath(ctx)
                    nvgCircle(ctx, dotStartX + (di - 1) * dotGap, barY + barH + 7, dotR)
                    nvgFillColor(ctx, nvgRGBA(139, 105, 20, 180))
                    nvgFill(ctx)
                end
            end
        end

        ::continueZone::
    end

    -- 7.4 绘制浮动数字(+5)
    local i = 1
    while i <= #comfortFloats do
        local f = comfortFloats[i]
        f.life = f.life - GetTime():GetTimeStep()
        if f.life <= 0 then
            table.remove(comfortFloats, i)
        else
            local alpha = math.floor((f.life / f.maxLife) * 220)
            local drawX = f.x + ox
            local drawY = f.y + oy - (1.0 - f.life / f.maxLife) * 20  -- 向上飘

            nvgFontFace(ctx, "sans")
            nvgFontSize(ctx, 13)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(f.color[1], f.color[2], f.color[3], alpha))
            nvgText(ctx, drawX, drawY, f.text)
            i = i + 1
        end
    end
end

return M
