-- ============================================================================
-- Game/MapGen.lua - 地图程序化生成
-- 负责: 地面斑块生成、环境装饰物、哈希函数
-- ============================================================================

local CONFIG = require("Game.Config")
local State = require("Game.State")

local MapGen = {}

-- 外部注入
MapGen.generateComfortZones = nil  -- ComfortZone.generate

-- ============================================================================
-- 简单hash函数用于程序化生成(确定性随机)
-- ============================================================================

function MapGen.hashPos(x, y, seed)
    local h = (x * 374761393 + y * 668265263 + seed * 1274126177) % 2147483647
    return (h % 1000) / 1000.0
end

-- ============================================================================
-- 生成环境装饰数据
-- ============================================================================

function MapGen.generate()
    if State.decorationsGenerated then return end
    State.decorationsGenerated = true
    print("[DEBUG-DECO] generateMapDecorations() 被调用! mapDecorations清空前=" .. #State.mapDecorations)

    -- 生成草丛碎片(密集, 用于地面纹理感)
    local patchSpacing = 48
    for gx = 0, CONFIG.MapSize, patchSpacing do
        for gy = 0, CONFIG.MapSize, patchSpacing do
            local h = MapGen.hashPos(gx, gy, 42)
            if h > 0.25 then
                local px = gx + (MapGen.hashPos(gx, gy, 100) - 0.5) * patchSpacing
                local py = gy + (MapGen.hashPos(gx, gy, 200) - 0.5) * patchSpacing
                local size = 12 + MapGen.hashPos(gx, gy, 300) * 28
                local variant = math.floor(MapGen.hashPos(gx, gy, 400) * 4)
                local shade = MapGen.hashPos(gx, gy, 500)
                table.insert(State.groundPatches, {
                    x = px, y = py, size = size, variant = variant, shade = shade,
                })
            end
        end
    end

    -- 7.1 生成初始舒适区
    State.comfortZones = {}
    State.comfortFloats = {}
    if MapGen.generateComfortZones then
        MapGen.generateComfortZones(CONFIG.MapSize / 2, CONFIG.MapSize / 2, State.circleInitRadius)
    end

    -- 编辑器出生点配置同步
    if State.levelEditor then
        local spawnCfg = State.levelEditor:GetSpawnConfig()
        if spawnCfg then
            State.editorSpawnConfig = spawnCfg
        end
    end

    -- 按Y坐标排序(简单深度排序)
    table.sort(State.mapDecorations, function(a, b) return a.y < b.y end)

    -- 统计各类型物件数量
    local typeCounts = {}
    for _, dec in ipairs(State.mapDecorations) do
        typeCounts[dec.type] = (typeCounts[dec.type] or 0) + 1
    end
    local countStr = ""
    for t, c in pairs(typeCounts) do
        countStr = countStr .. t .. "=" .. c .. " "
    end
    print("[饥荒渲染] 生成装饰: 草丛=" .. #State.groundPatches .. " 物件总数=" .. #State.mapDecorations
        .. " (" .. countStr .. ") 舒适区=" .. #State.comfortZones)
end

-- ============================================================================
-- 重置装饰生成标记
-- ============================================================================

function MapGen.reset()
    State.decorationsGenerated = false
    State.mapDecorations = {}
    State.groundPatches = {}
end

-- ============================================================================
-- 供编辑器导入种子后重新生成
-- ============================================================================

function MapGen.regenerate()
    print("[DEBUG-DECO] RegenerateMapDecorations() 被调用!")
    MapGen.reset()
    State._decoDrawDebugOnce = false
end

-- ============================================================================
-- 全局访问函数(供编辑器)
-- ============================================================================

function MapGen.getDecorations()
    return State.mapDecorations
end

function MapGen.getComfortZones()
    return State.comfortZones
end

-- ============================================================================
-- 地形类型判定(基于位置)
-- ============================================================================

function MapGen.getTerrainType(wx, wy)
    if State.levelEditor and State.levelEditor:IsTerrainExported() then
        local editorKey = State.levelEditor:GetTerrainImageKey(wx, wy)
        if editorKey then return editorKey end
    end
    local h = MapGen.hashPos(wx, wy, 33)
    if h > 0.55 then
        return "mud"
    else
        return "grass"
    end
end

return MapGen
