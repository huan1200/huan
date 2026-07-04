-- ============================================================================
-- Game/Render/init.lua
-- 渲染编排: HandleRender入口 + hashPos + generateMapDecorations + 前向引用织连
-- ============================================================================

---@type boolean
local isTouchDevice = isTouchDevice  ---@diagnostic disable-line: undefined-global

local CONFIG = require("Game.Config")
local State = require("Game.State")
local Utils = require("Game.Utils")
local Input = require("Game.Input")
local Phase = require("Game.Phase")
local IDEMain = require("IDE.IDEMain")

-- 渲染子模块
local Ground = require("Game.Render.Ground")
local Circle = require("Game.Render.Circle")
local World = require("Game.Render.World")
local Effects = require("Game.Render.Effects")
local Touch = require("Game.Render.Touch")
local Screens = require("Game.Render.Screens")
local RenderComfortZone = require("Game.Render.ComfortZone")
local RenderPlayer = require("Game.Render.Player")
local Overlay = require("Game.Render.Overlay")

local M = {}

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 简单hash函数用于程序化生成(确定性随机)
local function hashPos(x, y, seed)
    local h = (x * 374761393 + y * 668265263 + seed * 1274126177) % 2147483647
    return (h % 1000) / 1000.0
end

M.hashPos = hashPos

--- 查找最近可交互玩家(用于渲染交互UI + 游戏逻辑)
local function findNearestInteractable(player)
    if not player.alive then return nil end
    if player.interactState ~= "idle" then return nil end
    if player.drinkingState ~= "idle" then return nil end
    if player.attackState ~= "idle" then return nil end

    local players = State.players
    local bestIdx = nil
    local bestDist = CONFIG.InteractRange
    for i = 1, #players do
        local other = players[i]
        if other.idx ~= player.idx and other.alive
            and other.interactState == "idle"
            and other.drinkingState == "idle"
            and other.attackState == "idle" then
            local d = Utils.dist(player.x, player.y, other.x, other.y)
            if d <= bestDist then
                bestDist = d
                bestIdx = i
            end
        end
    end
    return bestIdx
end

M.findNearestInteractable = findNearestInteractable

-- ============================================================================
-- 前向引用织连(解决子模块间循环依赖)
-- ============================================================================

-- Ground 需要: hashPos
Ground.hashPos = hashPos

-- Circle 需要: dist, lerp, clamp
Circle.dist = Utils.dist
Circle.lerp = Utils.lerp
Circle.clamp = Utils.clamp

-- World 需要: hashPos, drawPlayerDST, drawComfortZones
World.hashPos = hashPos
World.drawPlayerDST = RenderPlayer.drawPlayerDST
World.drawComfortZones = RenderComfortZone.drawComfortZones

-- ComfortZone 需要: dist
RenderComfortZone.dist = Utils.dist

-- Player 需要: dist
RenderPlayer.dist = Utils.dist

-- Overlay 需要: findNearestInteractable, getAliveCount, dist, lerp, clamp
Overlay.findNearestInteractable = findNearestInteractable
Overlay.getAliveCount = Phase.getAliveCount
Overlay.dist = Utils.dist
Overlay.lerp = Utils.lerp
Overlay.clamp = Utils.clamp

-- Touch 需要: getTouchButtonRects, dist
Touch.getTouchButtonRects = Input.getTouchButtonRects
Touch.dist = Utils.dist

-- ============================================================================
-- 生成环境装饰数据
-- ============================================================================
function M.generateMapDecorations()
    if State.decorationsGenerated then return end
    State.decorationsGenerated = true
    print("[DEBUG-DECO] generateMapDecorations() 被调用! mapDecorations清空前=" .. #State.mapDecorations)

    local groundPatches = State.groundPatches
    local mapDecorations = State.mapDecorations

    -- 生成草丛碎片(密集, 用于地面纹理感)
    local patchSpacing = 48
    for gx = 0, CONFIG.MapSize, patchSpacing do
        for gy = 0, CONFIG.MapSize, patchSpacing do
            local h = hashPos(gx, gy, 42)
            if h > 0.25 then
                local px = gx + (hashPos(gx, gy, 100) - 0.5) * patchSpacing
                local py = gy + (hashPos(gx, gy, 200) - 0.5) * patchSpacing
                local size = 12 + hashPos(gx, gy, 300) * 28
                local variant = math.floor(hashPos(gx, gy, 400) * 4)
                local shade = hashPos(gx, gy, 500)
                table.insert(groundPatches, {
                    x = px, y = py, size = size, variant = variant, shade = shade,
                })
            end
        end
    end

    -- 生成初始舒适区(在初始安全区内, 满足距离约束)
    State.comfortZones = {}
    State.comfortFloats = {}
    local ComfortZone = require("Game.ComfortZone")
    ComfortZone.generate(CONFIG.MapSize / 2, CONFIG.MapSize / 2, State.circleInitRadius)

    -- 编辑器出生点配置同步
    local levelEditor = State.levelEditor
    if levelEditor then
        local spawnCfg = levelEditor:GetSpawnConfig()
        if spawnCfg then
            State.editorSpawnConfig = spawnCfg
        end
    end

    -- 按Y坐标排序(简单深度排序)
    table.sort(mapDecorations, function(a, b) return a.y < b.y end)

    -- 统计各类型物件数量
    local typeCounts = {}
    for _, dec in ipairs(mapDecorations) do
        typeCounts[dec.type] = (typeCounts[dec.type] or 0) + 1
    end
    local countStr = ""
    for t, c in pairs(typeCounts) do
        countStr = countStr .. t .. "=" .. c .. " "
    end
    print("[饥荒渲染] 生成装饰: 草丛=" .. #groundPatches .. " 物件总数=" .. #mapDecorations
        .. " (" .. countStr .. ") 舒适区=" .. #State.comfortZones)
end

-- ============================================================================
-- NanoVG 渲染主入口
-- ============================================================================
function M.HandleRender(eventType, eventData)
    local nvgContext = State.nvgContext
    if nvgContext == nil then return end

    -- IDE激活时: 节点模式只渲染IDE界面; 关卡/场景模式先渲染游戏世界再叠加IDE
    if IDEMain.IsActive() then
        local ideMode = IDEMain.GetMode()
        if ideMode == "node" then
            local graphics = GetGraphics()
            local screenW = graphics:GetWidth()
            local screenH = graphics:GetHeight()
            local dpr = graphics:GetDPR()
            local logW = screenW / dpr
            local logH = screenH / dpr
            nvgBeginFrame(nvgContext, logW, logH, dpr)
            IDEMain.Render(logW, logH, dpr)
            nvgEndFrame(nvgContext)
            return
        end
    end

    local gamePhase = State.gamePhase
    if gamePhase == "menu" and not IDEMain.IsActive() then return end

    -- 胜利/失败全屏画面
    if not IDEMain.IsActive() and (gamePhase == "victory" or gamePhase == "defeat") then
        local graphics = GetGraphics()
        local screenW = graphics:GetWidth()
        local screenH = graphics:GetHeight()
        local dpr = graphics:GetDPR()
        local logW = screenW / dpr
        local logH = screenH / dpr
        nvgBeginFrame(nvgContext, logW, logH, dpr)
        if gamePhase == "victory" then
            Screens.drawVictoryScreen(logW, logH)
        else
            Screens.drawDefeatScreen(logW, logH)
        end
        nvgEndFrame(nvgContext)
        return
    end

    -- 确保装饰数据已生成
    M.generateMapDecorations()

    local graphics = GetGraphics()
    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local logW = screenW / dpr
    local logH = screenH / dpr

    nvgBeginFrame(nvgContext, logW, logH, dpr)

    -- 坐标变换: 世界坐标 → 屏幕坐标(含屏幕震动偏移)
    local screenShake = State.screenShake
    local shakeOX = 0
    local shakeOY = 0
    if screenShake.timer > 0 then
        shakeOX = (math.random() - 0.5) * 2 * screenShake.intensity
        shakeOY = (math.random() - 0.5) * 2 * screenShake.intensity
    end

    -- 相机缩放(编辑器激活时使用编辑器缩放, 否则2x)
    local CAM_ZOOM = 2.0
    local camera = State.camera
    local camX, camY = camera.x, camera.y
    local levelEditor = State.levelEditor
    if IDEMain.IsActive() and levelEditor then
        CAM_ZOOM = 2.0 * levelEditor.editorZoom
        camX = levelEditor.editorCamX
        camY = levelEditor.editorCamY
    elseif levelEditor and levelEditor:IsActive() then
        CAM_ZOOM = 2.0 * levelEditor.editorZoom
        camX = levelEditor.editorCamX
        camY = levelEditor.editorCamY
    end
    local offsetX = logW / 2 / CAM_ZOOM - camX + shakeOX
    local offsetY = logH / 2 / CAM_ZOOM - camY + shakeOY

    -- 应用缩放变换(世界渲染区域)
    nvgSave(nvgContext)
    nvgTranslate(nvgContext, logW / 2, logH / 2)
    nvgScale(nvgContext, CAM_ZOOM, CAM_ZOOM)
    nvgTranslate(nvgContext, -logW / 2 / CAM_ZOOM, -logH / 2 / CAM_ZOOM)

    -- 世界空间渲染(按深度顺序)
    local worldW = logW / CAM_ZOOM
    local worldH = logH / CAM_ZOOM

    -- 1. 地面
    Ground.drawGroundDST(worldW, worldH, offsetX, offsetY)

    -- 2. 地面草丛纹理
    Ground.drawGroundPatches(worldW, worldH, offsetX, offsetY)

    -- 3. 毒圈
    Circle.drawPoisonCircleDST(offsetX, offsetY)

    -- 3.5 舒适区光圈
    RenderComfortZone.drawComfortZones(offsetX, offsetY)

    -- 3.6 死亡污渍和纸片
    Effects.drawDeathEffects(offsetX, offsetY)

    -- 4. 环境装饰+玩家(按深度交错)
    World.drawEnvironmentAndPlayers(worldW, worldH, offsetX, offsetY)

    -- 5. 攻击特效
    Effects.drawAttackEffectsDST(offsetX, offsetY)

    -- 6. 粒子
    Effects.drawParticlesDST(offsetX, offsetY)

    -- 6.5 浮动文字
    Effects.drawFloatingTexts(offsetX, offsetY)

    -- 8.2 交互UI(按钮提示+选项面板+抛物线动画)
    Overlay.drawInteractionUI(worldW, worldH, offsetX, offsetY)

    -- 恢复缩放变换(后续HUD在屏幕空间绘制)
    nvgRestore(nvgContext)

    -- IDE/编辑器激活时: 跳过所有游戏UI, 渲染编辑器覆盖
    if IDEMain.IsActive() then
        IDEMain.Render(logW, logH, dpr)
    elseif levelEditor and levelEditor:IsActive() then
        levelEditor:Render(logW, logH, dpr)
    else
        -- 7. 暗角效果
        Overlay.drawVignette(logW, logH)

        -- 7.5 黑夜亮度(settle阶段全黑)
        if gamePhase == "settle" then
            nvgBeginPath(nvgContext)
            nvgRect(nvgContext, 0, 0, logW, logH)
            nvgFillColor(nvgContext, nvgRGBA(0, 0, 0, 255))
            nvgFill(nvgContext)
        end

        -- settle阶段分支
        local settleSubPhase = State.settleSubPhase
        if gamePhase == "settle" and settleSubPhase == "countdown" then
            Overlay.drawClockCountdown(logW, logH)
            Overlay.drawPhaseHint(logW, logH)
        elseif gamePhase == "settle" and settleSubPhase == "elimination" then
            Overlay.drawEliminationPage(logW, logH)
            Overlay.drawPhaseHint(logW, logH)
        elseif gamePhase ~= "settle" then
            -- 正常阶段渲染
            Overlay.drawPoisonScreenOverlay(logW, logH)
            Overlay.drawClockCountdown(logW, logH)
            Overlay.drawPhaseHint(logW, logH)
            Overlay.drawOffscreenIndicators(logW, logH, offsetX, offsetY, CAM_ZOOM)
        end

        -- 11. 触控按钮(手机适配)
        if isTouchDevice and gamePhase ~= "menu" and gamePhase ~= "victory" and gamePhase ~= "defeat" then
            Touch.drawTouchControls(logW, logH)
        end
    end

    -- 自定义鼠标光标(最顶层绘制)
    local cursorImage = State.cursorImage
    if cursorImage and not isTouchDevice then
        local mousePos = input:GetMousePosition()
        local mx = mousePos.x / dpr
        local my = mousePos.y / dpr
        local cursorSize = 32
        nvgSave(nvgContext)
        nvgResetTransform(nvgContext)
        local imgPaint = nvgImagePattern(nvgContext, mx - 2, my - 2, cursorSize, cursorSize, 0, cursorImage, 1.0)
        nvgBeginPath(nvgContext)
        nvgRect(nvgContext, mx - 2, my - 2, cursorSize, cursorSize)
        nvgFillPaint(nvgContext, imgPaint)
        nvgFill(nvgContext)
        nvgRestore(nvgContext)
    end

    nvgEndFrame(nvgContext)
end

return M
