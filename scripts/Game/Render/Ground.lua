-- ============================================================================
-- Game/Render/Ground.lua
-- 地面渲染: 地形贴图铺设 + 草丛纹理
-- ============================================================================

local CONFIG = require("Game.Config")
local State = require("Game.State")

local M = {}

-- 前向引用(由 init.lua 注入)
M.hashPos = nil

--- 绘制地面(饥荒风 - 深色泥土地面 + 地形贴图)
function M.drawGroundDST(logW, logH, ox, oy)
    local ctx = State.nvgContext
    local isDay = (State.gamePhase == "prepare" or State.gamePhase == "day" or State.gamePhase == "shrinking")

    -- 基础地面色
    local bgR, bgG, bgB
    if isDay then
        bgR, bgG, bgB = 38, 34, 26
    else
        bgR, bgG, bgB = 14, 12, 10
    end
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, logW, logH)
    nvgFillColor(ctx, nvgRGBA(bgR, bgG, bgB, 255))
    nvgFill(ctx)

    -- 地形贴图铺地(64px chunk, 与编辑器网格对齐)
    local tileSize = 64
    local levelEditor = State.levelEditor
    local terrainOX = levelEditor and levelEditor.mapOriginX or 0
    local terrainOY = levelEditor and levelEditor.mapOriginY or 0
    local viewLeft = State.camera.x - logW / 2 - tileSize
    local viewRight = State.camera.x + logW / 2 + tileSize
    local viewTop = State.camera.y - logH / 2 - tileSize
    local viewBottom = State.camera.y + logH / 2 + tileSize

    local startCX = math.floor((viewLeft - terrainOX) / tileSize) * tileSize + terrainOX
    local startCY = math.floor((viewTop - terrainOY) / tileSize) * tileSize + terrainOY

    local hashPos = M.hashPos

    -- 根据位置确定地形类型(优先使用编辑器数据)
    local function getTerrainType(wx, wy)
        if levelEditor and levelEditor:IsTerrainExported() then
            local editorKey = levelEditor:GetTerrainImageKey(wx, wy)
            if editorKey then return editorKey end
        end
        local h = hashPos(wx, wy, 33)
        if h > 0.55 then
            return "mud"
        else
            return "grass"
        end
    end

    local terrainImages = State.terrainImages
    for cx = startCX, viewRight, tileSize do
        for cy = startCY, viewBottom, tileSize do
            local terrainType = getTerrainType(cx, cy)
            local img = terrainImages[terrainType]
            if img then
                local sx = cx + ox
                local sy = cy + oy

                local paint = nvgImagePattern(ctx, sx, sy, tileSize, tileSize, 0, img, 1.0)
                nvgBeginPath(ctx)
                nvgRect(ctx, sx, sy, tileSize, tileSize)
                nvgFillPaint(ctx, paint)
                nvgFill(ctx)

                -- 夜间降低亮度
                if not isDay then
                    nvgBeginPath(ctx)
                    nvgRect(ctx, sx, sy, tileSize, tileSize)
                    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 160))
                    nvgFill(ctx)
                end
            end
        end
    end

    -- 毒圈外冒绿色气泡(动态)
    if isDay then
        local time = GetTime():GetElapsedTime()
        local bubbleCount = 12
        local circle = State.circle
        for i = 1, bubbleCount do
            local angle = (i / bubbleCount) * math.pi * 2 + time * 0.3
            local bDist = circle.radius + 40 + hashPos(i, 0, 7777) * 200
            local bx = circle.cx + math.cos(angle) * bDist + ox
            local by = circle.cy + math.sin(angle) * bDist + oy
            if bx > -20 and bx < logW + 20 and by > -20 and by < logH + 20 then
                local bubbleR = 3 + math.sin(time * 2 + i) * 1.5
                local bubbleA = math.floor(80 + math.sin(time * 3 + i * 1.7) * 40)
                nvgBeginPath(ctx)
                nvgCircle(ctx, bx, by, bubbleR)
                nvgFillColor(ctx, nvgRGBA(46, 74, 62, bubbleA))
                nvgFill(ctx)
            end
        end
    end
end

--- 绘制草丛纹理(饥荒风 - 短草/枯叶散落)
function M.drawGroundPatches(logW, logH, ox, oy)
    local ctx = State.nvgContext
    local isDay = (State.gamePhase == "prepare" or State.gamePhase == "day" or State.gamePhase == "shrinking")

    local viewLeft = State.camera.x - logW / 2 - 30
    local viewRight = State.camera.x + logW / 2 + 30
    local viewTop = State.camera.y - logH / 2 - 30
    local viewBottom = State.camera.y + logH / 2 + 30

    local groundPatches = State.groundPatches
    local circle = State.circle

    for i = 1, #groundPatches do
        local patch = groundPatches[i]
        if patch.x >= viewLeft and patch.x <= viewRight
           and patch.y >= viewTop and patch.y <= viewBottom then

            local sx = patch.x + ox
            local sy = patch.y + oy
            local size = patch.size

            -- 判断在圈内还是圈外
            local dx = patch.x - circle.cx
            local dy = patch.y - circle.cy
            local dToCenter = math.sqrt(dx * dx + dy * dy)
            local inPoison = dToCenter > circle.radius

            -- 颜色: 暗褐枯叶/碎石
            local gr, gg, gb, ga
            if inPoison then
                if isDay then
                    gr, gg, gb, ga = 35, 28, 42, 90
                else
                    gr, gg, gb, ga = 12, 10, 16, 70
                end
            else
                if isDay then
                    if patch.shade > 0.7 then
                        gr, gg, gb, ga = 55, 48, 30, 100
                    elseif patch.shade > 0.4 then
                        gr, gg, gb, ga = 60, 55, 40, 85
                    else
                        gr, gg, gb, ga = 45, 38, 25, 75
                    end
                else
                    gr, gg, gb, ga = 15, 12, 10, 70
                end
            end

            -- 根据variant绘制不同形状
            if patch.variant == 0 then
                -- 枯叶(弯曲短线)
                nvgStrokeColor(ctx, nvgRGBA(gr, gg, gb, ga))
                nvgStrokeWidth(ctx, 1.5)
                nvgBeginPath(ctx)
                nvgMoveTo(ctx, sx - 2, sy + size * 0.2)
                nvgQuadTo(ctx, sx - 1, sy - size * 0.2, sx + 1, sy - size * 0.35)
                nvgMoveTo(ctx, sx + 1, sy + size * 0.2)
                nvgQuadTo(ctx, sx + 2, sy - size * 0.1, sx + 3, sy - size * 0.3)
                nvgStroke(ctx)
            elseif patch.variant == 1 then
                -- 碎石(小多边形)
                nvgBeginPath(ctx)
                nvgEllipse(ctx, sx, sy, size * 0.35, size * 0.25)
                nvgFillColor(ctx, nvgRGBA(gr + 10, gg + 8, gb + 5, ga - 20))
                nvgFill(ctx)
                nvgStrokeColor(ctx, nvgRGBA(gr - 15, gg - 15, gb - 10, ga - 10))
                nvgStrokeWidth(ctx, 1)
                nvgStroke(ctx)
            elseif patch.variant == 2 then
                -- 裂缝(交叉线)
                nvgStrokeColor(ctx, nvgRGBA(gr - 10, gg - 10, gb - 8, ga - 30))
                nvgStrokeWidth(ctx, 1)
                nvgBeginPath(ctx)
                nvgMoveTo(ctx, sx - size * 0.25, sy - size * 0.1)
                nvgLineTo(ctx, sx + size * 0.2, sy + size * 0.1)
                nvgMoveTo(ctx, sx - size * 0.1, sy - size * 0.2)
                nvgLineTo(ctx, sx + size * 0.15, sy + size * 0.15)
                nvgStroke(ctx)
            else
                -- 碎屑点
                nvgBeginPath(ctx)
                nvgCircle(ctx, sx, sy, size * 0.15)
                nvgFillColor(ctx, nvgRGBA(gr, gg, gb, ga - 30))
                nvgFill(ctx)
            end
        end
    end
end

return M
