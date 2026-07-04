-- ============================================================================
-- Game/Render/World.lua
-- 世界元素渲染: 环境物+玩家排序绘制 + 地面药剂 + 枯树
-- ============================================================================
local CONFIG = require("Game.Config")
local State = require("Game.State")

local M = {}

-- 前向引用(由 init.lua 注入)
M.hashPos = nil
M.drawPlayerDST = nil  -- 来自 Render/Player
M.drawComfortZones = nil  -- 来自 Render/ComfortZone

-- ============================================================================
-- 获取物件的贴图变体号
-- ============================================================================
local function getObjVariant(obj)
    if obj.variant then return obj.variant end
    -- tree/rock 通过 seed 推算: variant = floor(seed / 50000) + 1
    if obj.seed then
        return math.floor(obj.seed / 50000) + 1
    end
    return 1
end

-- ============================================================================
-- 绘制带贴图的物件(树/石头/花/植物)
-- ============================================================================
function M.drawDecoSprite(ctx, obj, ox, oy)
    local objAssetImages = State.objAssetImages
    if not objAssetImages then return end

    local variant = getObjVariant(obj)
    local typeImages = objAssetImages[obj.type]
    if not typeImages then return end
    local imgHandle = typeImages[variant]
    if not imgHandle or imgHandle == 0 then return end

    local sx = obj.x + ox
    local sy = obj.y + oy

    -- 根据物件类型确定绘制尺寸
    local drawSize
    if obj.type == "tree" then
        drawSize = (obj.height or 100) * 1.0
    else
        drawSize = (obj.size or 30) * 2.0
    end

    -- 绘制贴图(居中, 底部对齐)
    local drawW = drawSize
    local drawH = drawSize
    local drawX = sx - drawW / 2
    local drawY = sy - drawH  -- 底部对齐到 y 坐标

    -- 支持水平翻转
    if obj.flipX then
        nvgSave(ctx)
        -- 以物件中心X为轴翻转: 先平移到中心, 再scale(-1,1), 再平移回去
        nvgTranslate(ctx, sx, 0)
        nvgScale(ctx, -1, 1)
        nvgTranslate(ctx, -sx, 0)
    end

    local imgPat = nvgImagePattern(ctx, drawX, drawY, drawW, drawH, 0, imgHandle, 1.0)
    nvgBeginPath(ctx)
    nvgRect(ctx, drawX, drawY, drawW, drawH)
    nvgFillPaint(ctx, imgPat)
    nvgFill(ctx)

    if obj.flipX then
        nvgRestore(ctx)
    end
end

-- ============================================================================
-- 绘制地面药剂(发光瓶子)
-- ============================================================================
function M.drawGroundPotion(ctx, gp, ox, oy)
    local sx = gp.x + ox
    local sy = gp.y + oy
    local time = GetTime():GetElapsedTime()

    local isAntidote = gp.type == "antidote"
    local glowR, glowG, glowB = 80, 180, 255  -- 蓝色(解药)
    if not isAntidote then
        glowR, glowG, glowB = 60, 180, 80     -- 绿色(毒药)
    end

    -- 脉动光晕
    local pulse = 0.7 + math.sin(time * 3 + gp.x * 0.1) * 0.3
    local glowRadius = 12 + math.sin(time * 2) * 3

    -- 外层光晕
    local grad = nvgRadialGradient(ctx, sx, sy - 4, 2, glowRadius,
        nvgRGBA(glowR, glowG, glowB, math.floor(80 * pulse)),
        nvgRGBA(glowR, glowG, glowB, 0))
    nvgBeginPath(ctx)
    nvgCircle(ctx, sx, sy - 4, glowRadius)
    nvgFillPaint(ctx, grad)
    nvgFill(ctx)

    -- 瓶子形状(简单的小瓶轮廓)
    local bw = 10  -- 瓶宽
    local bh = 20 -- 瓶高
    -- 瓶身
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, sx - bw, sy - bh, bw * 2, bh, 3)
    nvgFillColor(ctx, nvgRGBA(glowR, glowG, glowB, math.floor(180 * pulse)))
    nvgFill(ctx)
    -- 瓶颈
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, sx - 2, sy - bh - 4, 4, 5, 1)
    nvgFillColor(ctx, nvgRGBA(glowR, glowG, glowB, math.floor(200 * pulse)))
    nvgFill(ctx)
    -- 高光
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, sx - bw + 2, sy - bh + 2, 3, bh - 4, 1)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, math.floor(60 * pulse)))
    nvgFill(ctx)
end

-- ============================================================================
-- 绘制边界枯树(扭曲黑色枯树 - 天然围墙)
-- ============================================================================
function M.drawDeadTreeDST(ctx, tree, ox, oy)
    local sx = tree.x + ox
    local sy = tree.y + oy
    local h = tree.height
    local twist = tree.twist
    local hashPos = M.hashPos

    -- 纯黑色树干(无叶, 扭曲, 恐怖感)
    nvgStrokeColor(ctx, nvgRGBA(8, 5, 3, 240))
    nvgStrokeWidth(ctx, 5)
    nvgLineCap(ctx, NVG_ROUND)
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, sx, sy)
    local midX = sx + twist * h * 0.5
    local midY = sy - h * 0.5
    local topX = sx + twist * h * 0.3
    local topY = sy - h
    nvgQuadTo(ctx, midX, midY, topX, topY)
    nvgStroke(ctx)

    -- 扭曲分支(纯黑, 无叶)
    nvgStrokeWidth(ctx, 3)
    local seed = tree.seed or 0
    for b = 1, 3 do
        local bh = 0.3 + (b / 3) * 0.5
        local startX = sx + twist * h * 0.5 * bh
        local startY = sy - h * bh
        local dir = (hashPos(seed, b, 5555) - 0.5) * 2.5
        local branchLen = h * 0.3 + hashPos(seed, b, 6666) * h * 0.2

        nvgBeginPath(ctx)
        nvgMoveTo(ctx, startX, startY)
        local endX = startX + dir * branchLen
        local endY = startY - branchLen * 0.3
        nvgQuadTo(ctx, startX + dir * branchLen * 0.7, startY - branchLen * 0.1, endX, endY)
        nvgStroke(ctx)

        -- 细小末梢
        nvgStrokeWidth(ctx, 1.5)
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, endX, endY)
        nvgLineTo(ctx, endX + dir * 8, endY - 10)
        nvgStroke(ctx)
        nvgStrokeWidth(ctx, 3)
    end
end

-- ============================================================================
-- 环境+玩家混合绘制(Y排序深度渲染)
-- ============================================================================
function M.drawEnvironmentAndPlayers(worldW, worldH, ox, oy)
    local ctx = State.nvgContext
    local players = State.players
    local mapDecorations = State.mapDecorations
    local groundPotions = State.groundPotions
    local camera = State.camera
    local isDay = (State.gamePhase == "day")

    -- 视口裁剪(只绘制可见区域)
    local viewLeft = camera.x - worldW / 2 - 100
    local viewRight = camera.x + worldW / 2 + 100
    local viewTop = camera.y - worldH / 2 - 100
    local viewBottom = camera.y + worldH / 2 + 100

    -- 构建绘制列表(装饰物+药剂+玩家)
    local drawList = {}

    -- 添加可见装饰物
    for i = 1, #mapDecorations do
        local dec = mapDecorations[i]
        if dec.x >= viewLeft and dec.x <= viewRight
           and dec.y >= viewTop and dec.y <= viewBottom then
            table.insert(drawList, { type = "deco", data = dec, y = dec.y })
        end
    end

    -- 添加地面药剂
    for i = 1, #groundPotions do
        local gp = groundPotions[i]
        if gp.x >= viewLeft and gp.x <= viewRight
           and gp.y >= viewTop and gp.y <= viewBottom then
            table.insert(drawList, { type = "groundPotion", data = gp, y = gp.y })
        end
    end

    -- 添加玩家(包括鬼魂)
    for i = 1, #players do
        if players[i].alive or players[i].isGhost then
            table.insert(drawList, { type = "player", data = players[i], y = players[i].y })
        end
    end

    -- 按Y排序(从远到近)
    table.sort(drawList, function(a, b) return a.y < b.y end)

    -- 逐个绘制
    for i = 1, #drawList do
        local item = drawList[i]
        if item.type == "deco" then
            if item.data.type == "deadtree" then
                M.drawDeadTreeDST(ctx, item.data, ox, oy)
            elseif item.data.type == "tree" or item.data.type == "rock"
                or item.data.type == "flower" or item.data.type == "plant" then
                M.drawDecoSprite(ctx, item.data, ox, oy)
            end
        elseif item.type == "groundPotion" then
            M.drawGroundPotion(ctx, item.data, ox, oy)
        elseif item.type == "player" then
            M.drawPlayerDST(ctx, item.data, ox, oy, isDay)
        end
    end
end

return M
