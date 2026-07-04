-- ============================================================================
-- Game/Render/Effects.lua
-- 特效渲染: 攻击弧光 + 粒子 + 浮动文字 + 死亡碎片
-- ============================================================================
local CONFIG = require("Game.Config")
local State = require("Game.State")

local M = {}

-- ============================================================================
-- 攻击特效(饥荒风 - 暗色弧形挥砍)
-- ============================================================================
function M.drawAttackEffectsDST(ox, oy)
    local ctx = State.nvgContext
    local attackEffects = State.attackEffects

    for i = 1, #attackEffects do
        local e = attackEffects[i]
        local sx = e.x + ox
        local sy = e.y + oy
        local halfAngle = math.rad(CONFIG.AttackAngle / 2)

        if e.phase == "windup" then
            -- 前摇: 墨水拖尾(手臂举起, 淡墨弧线)
            local totalDur = CONFIG.AttackWindup + CONFIG.AttackRecovery
            local progress = 1.0 - (e.timer / totalDur)
            local alpha = math.floor((1.0 - progress) * 120)
            local range = CONFIG.AttackRange * 0.4 * (0.5 + progress * 0.5)

            nvgBeginPath(ctx)
            nvgArc(ctx, sx, sy, range, e.angle - halfAngle * 0.5, e.angle + halfAngle * 0.5, 1)
            nvgStrokeWidth(ctx, 2 + progress * 2)
            nvgStrokeColor(ctx, nvgRGBA(20, 20, 30, alpha))
            nvgStroke(ctx)

        elseif e.phase == "slash" then
            -- 挥击: 黑色墨水扇形弧(主攻击视觉)
            local progress = 1.0 - (e.timer / CONFIG.AttackRecovery)
            local alpha = math.floor((1.0 - progress) * 220)
            local range = CONFIG.AttackRange * (0.6 + progress * 0.4)

            -- 扇形填充(深黑墨水)
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, sx, sy)
            nvgArc(ctx, sx, sy, range, e.angle - halfAngle, e.angle + halfAngle, 1)
            nvgClosePath(ctx)
            nvgFillColor(ctx, nvgRGBA(10, 10, 20, math.floor(alpha * 0.5)))
            nvgFill(ctx)

            -- 弧线描边(黑色墨水边缘)
            nvgBeginPath(ctx)
            nvgArc(ctx, sx, sy, range, e.angle - halfAngle, e.angle + halfAngle, 1)
            nvgStrokeWidth(ctx, 3 + (1.0 - progress) * 2)
            nvgStrokeColor(ctx, nvgRGBA(20, 20, 40, alpha))
            nvgStroke(ctx)

            -- 墨水飞溅线条
            for j = 1, 3 do
                local a = e.angle - halfAngle + (j / 4) * (halfAngle * 2)
                local startR = range * 0.8
                local endR = range * (1.0 + progress * 0.3)
                nvgBeginPath(ctx)
                nvgMoveTo(ctx, sx + math.cos(a) * startR, sy + math.sin(a) * startR)
                nvgLineTo(ctx, sx + math.cos(a) * endR, sy + math.sin(a) * endR)
                nvgStrokeWidth(ctx, 2)
                nvgStrokeColor(ctx, nvgRGBA(30, 30, 40, math.floor(alpha * 0.7)))
                nvgStroke(ctx)
            end

        else
            -- 兼容旧格式
            local progress = 1.0 - (e.timer / 0.3)
            local alpha = math.floor((1.0 - progress) * 200)
            local range = CONFIG.AttackRange * (0.5 + progress * 0.5)

            nvgBeginPath(ctx)
            nvgMoveTo(ctx, sx, sy)
            nvgArc(ctx, sx, sy, range, e.angle - halfAngle, e.angle + halfAngle, 1)
            nvgClosePath(ctx)
            nvgFillColor(ctx, nvgRGBA(20, 20, 30, math.floor(alpha * 0.4)))
            nvgFill(ctx)
        end
    end
end

-- ============================================================================
-- 粒子(饥荒风 - 暗色毒雾碎片)
-- ============================================================================
function M.drawParticlesDST(ox, oy)
    local ctx = State.nvgContext
    local particles = State.particles

    for i = 1, #particles do
        local p = particles[i]
        local sx = p.x + ox
        local sy = p.y + oy
        local alpha = math.floor(p.life * 200)
        local size = p.life * 6

        -- 不规则形状(旋转的菱形)
        nvgSave(ctx)
        nvgTranslate(ctx, sx, sy)
        nvgRotate(ctx, p.life * 3.14)

        nvgBeginPath(ctx)
        nvgMoveTo(ctx, 0, -size)
        nvgLineTo(ctx, size * 0.6, 0)
        nvgLineTo(ctx, 0, size)
        nvgLineTo(ctx, -size * 0.6, 0)
        nvgClosePath(ctx)
        nvgFillColor(ctx, nvgRGBA(p.color[1], p.color[2], p.color[3], alpha))
        nvgFill(ctx)

        nvgRestore(ctx)
    end
end

-- ============================================================================
-- 浮动文字绘制(命中反馈: "+10毒"/"-15毒" 等)
-- ============================================================================
function M.drawFloatingTexts(ox, oy)
    local ctx = State.nvgContext
    local floatingTexts = State.floatingTexts
    if #floatingTexts == 0 then return end

    nvgFontFace(ctx, "sans")
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    for i = 1, #floatingTexts do
        local ft = floatingTexts[i]
        local sx = ft.x + ox
        local sy = ft.y + oy
        local alpha = math.floor((ft.timer / ft.maxTimer) * 255)
        local scale = 0.8 + 0.4 * (1.0 - ft.timer / ft.maxTimer)

        nvgFontSize(ctx, 14 * scale)
        -- 阴影
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(alpha * 0.6)))
        nvgText(ctx, sx + 1, sy + 1, ft.text)
        -- 正文
        nvgFillColor(ctx, nvgRGBA(ft.color[1], ft.color[2], ft.color[3], alpha))
        nvgText(ctx, sx, sy, ft.text)
    end
end

-- ============================================================================
-- 死亡纸片碎裂 + 黑色污渍
-- ============================================================================
function M.drawDeathEffects(ox, oy)
    local ctx = State.nvgContext
    local deathStains = State.deathStains
    local deathPieces = State.deathPieces

    -- 绘制黑色污渍(死亡原地留下)
    for i = 1, #deathStains do
        local s = deathStains[i]
        local sx = s.x + ox
        local sy = s.y + oy
        local a = math.floor(s.alpha)
        nvgBeginPath(ctx)
        nvgEllipse(ctx, sx, sy, 18, 8)
        nvgFillColor(ctx, nvgRGBA(15, 10, 8, a))
        nvgFill(ctx)
        nvgBeginPath(ctx)
        nvgEllipse(ctx, sx + 3, sy + 1, 10, 5)
        nvgFillColor(ctx, nvgRGBA(5, 3, 2, math.floor(a * 0.6)))
        nvgFill(ctx)
    end

    -- 绘制飘散纸片
    for i = 1, #deathPieces do
        local p = deathPieces[i]
        local sx = p.x + ox
        local sy = p.y + oy
        local alpha = math.floor((p.life / 2.0) * 220)

        nvgSave(ctx)
        nvgTranslate(ctx, sx, sy)
        nvgRotate(ctx, p.rot)

        nvgBeginPath(ctx)
        nvgMoveTo(ctx, -p.w * 0.5, -p.h * 0.4)
        nvgLineTo(ctx, p.w * 0.4, -p.h * 0.5)
        nvgLineTo(ctx, p.w * 0.5, p.h * 0.3)
        nvgLineTo(ctx, -p.w * 0.3, p.h * 0.5)
        nvgClosePath(ctx)
        local fade = p.life / 2.0
        nvgFillColor(ctx, nvgRGBA(
            math.floor(p.color[1] * fade),
            math.floor(p.color[2] * fade),
            math.floor(p.color[3] * fade), alpha))
        nvgFill(ctx)
        nvgStrokeColor(ctx, nvgRGBA(10, 8, 6, alpha))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)

        nvgRestore(ctx)
    end
end

return M
