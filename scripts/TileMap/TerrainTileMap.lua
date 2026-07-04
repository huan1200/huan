-- ============================================================================
-- TerrainTileMap.lua - 饥荒风格地形瓦片地图系统
-- 功能: 地形数据管理、自动过渡选择、NanoVG 瓦片渲染
-- ============================================================================

local TerrainTileMap = {}
TerrainTileMap.__index = TerrainTileMap

-- ============================================================================
-- 地形类型枚举
-- ============================================================================
TerrainTileMap.TERRAIN = {
    GRASS       = 1,  -- 草地
    MUD         = 2,  -- 泥地
    SWAMP       = 3,  -- 沼泽
    ROCKY       = 4,  -- 碎石
    VOLCANIC    = 5,  -- 火山岩
    SAND        = 6,  -- 沙地
    SNOW        = 7,  -- 雪地
    DEAD_GRASS  = 8,  -- 枯草地
    FOREST      = 9,  -- 森林地面
    COBBLESTONE = 10, -- 鹅卵石路
    -- 过渡贴图(左右) LR：左=A 右=B
    GRASS_SAND_LR       = 11,
    GRASS_DEADGRASS_LR  = 12,
    GRASS_ROCKY_LR      = 13,
    GRASS_SWAMP_LR      = 14,
    MUD_ROCKY_LR        = 15,
    MUD_SWAMP_LR        = 16,
    -- 过渡贴图(上下) TB：上=A 下=B
    GRASS_SNOW_TB       = 17,
    GRASS_ROCKY_TB      = 18,
    GRASS_MUD_TB        = 19,
    MUD_SWAMP_TB        = 20,
    ROCKY_VOLCANIC_TB   = 21,
    -- 补充方向过渡（正向）
    GRASS_MUD_LR        = 22,  -- 左草右泥
    GRASS_SWAMP_TB      = 23,  -- 上草下沼
    MUD_ROCKY_TB        = 24,  -- 上泥下石
    ROCKY_VOLCANIC_LR   = 25,  -- 左石右火
    -- 翻转方向过渡（反向）
    MUD_GRASS_LR        = 33,  -- 左泥右草
    MUD_GRASS_TB        = 34,  -- 上泥下草
    ROCKY_GRASS_LR      = 35,  -- 左石右草
    ROCKY_GRASS_TB      = 36,  -- 上石下草
    SWAMP_GRASS_LR      = 37,  -- 左沼右草
    SWAMP_GRASS_TB      = 38,  -- 上沼下草
    SAND_GRASS_LR       = 39,  -- 左沙右草
    SNOW_GRASS_TB       = 40,  -- 上雪下草
    DEADGRASS_GRASS_LR  = 41,  -- 左枯右草
    SWAMP_MUD_LR        = 42,  -- 左沼右泥
    SWAMP_MUD_TB        = 43,  -- 上沼下泥
    ROCKY_MUD_LR        = 44,  -- 左石右泥
    ROCKY_MUD_TB        = 45,  -- 上石下泥
    VOLCANIC_ROCKY_LR   = 46,  -- 左火右石
    VOLCANIC_ROCKY_TB   = 47,  -- 上火下石
    -- 渐变贴图（旧素材保留）
    GRASS_TO_MUD        = 30,
    GRASS_TO_SWAMP      = 31,
    ROCKY_TO_VOLCANIC   = 32,
}

-- 地形名称映射（用于调试）
TerrainTileMap.TERRAIN_NAMES = {
    [1] = "草地", [2] = "泥地", [3] = "沼泽", [4] = "碎石", [5] = "火山岩",
    [6] = "沙地", [7] = "雪地", [8] = "枯草地", [9] = "森林", [10] = "鹅卵石",
    [11] = "草沙LR", [12] = "草枯LR", [13] = "草石LR", [14] = "草沼LR",
    [15] = "泥石LR", [16] = "泥沼LR",
    [17] = "草雪TB", [18] = "草石TB", [19] = "草泥TB", [20] = "泥沼TB",
    [21] = "石火TB",
    [22] = "草泥LR", [23] = "草沼TB", [24] = "泥石TB", [25] = "石火LR",
    [33] = "泥草LR", [34] = "泥草TB", [35] = "石草LR", [36] = "石草TB",
    [37] = "沼草LR", [38] = "沼草TB", [39] = "沙草LR", [40] = "雪草TB",
    [41] = "枯草LR", [42] = "沼泥LR", [43] = "沼泥TB", [44] = "石泥LR",
    [45] = "石泥TB", [46] = "火石LR", [47] = "火石TB",
    [30] = "草渐泥", [31] = "草渐沼", [32] = "石渐火",
}

-- ============================================================================
-- 贴图路径配置
-- ============================================================================

-- 基础地形贴图
local BASE_TEXTURES = {
    [1]  = "image/地皮/terrain_grass_20260530170030.png",
    [2]  = "image/地皮/terrain_mud_20260530165944.png",
    [3]  = "image/地皮/terrain_swamp_20260530165947.png",
    [4]  = "image/地皮/terrain_rocky_20260530165943.png",
    [5]  = "image/地皮/terrain_volcanic_20260530165940.png",
    [6]  = "image/地皮/terrain_sand_20260530170620.png",
    [7]  = "image/地皮/terrain_snow_20260530170624.png",
    [8]  = "image/地皮/terrain_dead_grass_20260530170619.png",
    [9]  = "image/地皮/terrain_forest_floor_20260530170620.png",
    [10] = "image/地皮/terrain_cobblestone_20260530170621.png",
    -- 过渡贴图（LR 正向）- 左=A 右=B
    [11] = "image/地皮/terrain_grass_sand_lr_20260604.png",
    [12] = "image/地皮/terrain_grass_deadgrass_lr_20260604.png",
    [13] = "image/地皮/terrain_grass_rocky_lr_20260604.png",
    [14] = "image/地皮/terrain_grass_swamp_lr_20260604.png",
    [15] = "image/地皮/terrain_mud_rocky_lr_20260604.png",
    [16] = "image/地皮/terrain_mud_swamp_lr_20260604.png",
    -- 过渡贴图（TB 正向）- 上=A 下=B
    [17] = "image/地皮/terrain_grass_snow_tb_20260604.png",
    [18] = "image/地皮/terrain_grass_rocky_tb_20260604.png",
    [19] = "image/地皮/terrain_grass_mud_tb_20260604.png",
    [20] = "image/地皮/terrain_mud_swamp_tb_20260604.png",
    [21] = "image/地皮/terrain_rocky_volcanic_tb_20260604.png",
    -- 补充正向过渡
    [22] = "image/地皮/terrain_grass_mud_lr_20260604.png",
    [23] = "image/地皮/terrain_grass_swamp_tb_20260604.png",
    [24] = "image/地皮/terrain_mud_rocky_tb_20260604.png",
    [25] = "image/地皮/terrain_rocky_volcanic_lr_20260604.png",
    -- 翻转过渡贴图（反向）- 左=B 右=A / 上=B 下=A
    [33] = "image/地皮/terrain_mud_grass_lr_20260604.png",
    [34] = "image/地皮/terrain_mud_grass_tb_20260604.png",
    [35] = "image/地皮/terrain_rocky_grass_lr_20260604.png",
    [36] = "image/地皮/terrain_rocky_grass_tb_20260604.png",
    [37] = "image/地皮/terrain_swamp_grass_lr_20260604.png",
    [38] = "image/地皮/terrain_swamp_grass_tb_20260604.png",
    [39] = "image/地皮/terrain_sand_grass_lr_20260604.png",
    [40] = "image/地皮/terrain_snow_grass_tb_20260604.png",
    [41] = "image/地皮/terrain_deadgrass_grass_lr_20260604.png",
    [42] = "image/地皮/terrain_swamp_mud_lr_20260604.png",
    [43] = "image/地皮/terrain_swamp_mud_tb_20260604.png",
    [44] = "image/地皮/terrain_rocky_mud_lr_20260604.png",
    [45] = "image/地皮/terrain_rocky_mud_tb_20260604.png",
    [46] = "image/地皮/terrain_volcanic_rocky_lr_20260604.png",
    [47] = "image/地皮/terrain_volcanic_rocky_tb_20260604.png",
    -- 保留旧渐变贴图作为备用
    [30] = "image/地皮/terrain_grass_to_mud_20260530165951.png",
    [31] = "image/地皮/terrain_grass_to_swamp_20260530165942.png",
    [32] = "image/地皮/terrain_rocky_to_volcanic_20260530165943.png",
}

-- ============================================================================
-- 构造函数
-- ============================================================================

--- 创建新的地形瓦片地图
---@param vg userdata NanoVG 上下文
---@param config table 配置: { mapWidth, mapHeight, tileSize }
---@return table TerrainTileMap 实例
function TerrainTileMap.New(vg, config)
    local self = setmetatable({}, TerrainTileMap)

    self.vg = vg
    self.mapWidth = config.mapWidth or 20      -- 初始地图宽度（瓦片数）
    self.mapHeight = config.mapHeight or 15    -- 初始地图高度（瓦片数）
    self.tileSize = config.tileSize or 64      -- 每个瓦片渲染尺寸（像素）
    self.infinite = config.infinite or false    -- 是否无边界模式

    -- 相机偏移（用于滚动）
    self.cameraX = 0
    self.cameraY = 0

    -- 地图数据 [y][x] = terrainType
    self.data = {}
    for y = 1, self.mapHeight do
        self.data[y] = {}
        for x = 1, self.mapWidth do
            self.data[y][x] = TerrainTileMap.TERRAIN.GRASS  -- 默认草地
        end
    end

    -- NanoVG 图片缓存 { path = imageId }
    self.imageCache = {}

    -- 预加载基础贴图
    self:PreloadTextures()

    return self
end

--- 无边界模式下动态扩展地图到指定坐标
function TerrainTileMap:EnsureTile(x, y)
    if not self.infinite then return end
    if x < 1 or y < 1 then return end
    -- 扩展宽度
    if x > self.mapWidth then
        for row = 1, self.mapHeight do
            if not self.data[row] then self.data[row] = {} end
            for col = self.mapWidth + 1, x do
                self.data[row][col] = TerrainTileMap.TERRAIN.GRASS
            end
        end
        self.mapWidth = x
    end
    -- 扩展高度
    if y > self.mapHeight then
        for row = self.mapHeight + 1, y do
            self.data[row] = {}
            for col = 1, self.mapWidth do
                self.data[row][col] = TerrainTileMap.TERRAIN.GRASS
            end
        end
        self.mapHeight = y
    end
end

-- ============================================================================
-- 贴图管理
-- ============================================================================

--- 获取或加载贴图的 NanoVG imageId
function TerrainTileMap:GetImage(path)
    if not path then return nil end
    if self.imageCache[path] then
        return self.imageCache[path]
    end

    local imgId = nvgCreateImage(self.vg, path, 0)
    if imgId and imgId >= 0 then
        self.imageCache[path] = imgId
        return imgId
    end

    return nil
end

--- 预加载所有基础地形贴图
function TerrainTileMap:PreloadTextures()
    for _, path in pairs(BASE_TEXTURES) do
        self:GetImage(path)
    end
    print("[TerrainTileMap] 预加载完成, 缓存贴图数: " .. self:GetCachedCount())
end

--- 获取缓存贴图数量
function TerrainTileMap:GetCachedCount()
    local count = 0
    for _ in pairs(self.imageCache) do count = count + 1 end
    return count
end

-- ============================================================================
-- 地图数据操作
-- ============================================================================

--- 设置单个瓦片地形
function TerrainTileMap:SetTile(x, y, terrainType)
    if self.infinite then
        -- 无限模式: 允许任意坐标(包括负数和0)
        if not self.data[y] then self.data[y] = {} end
        self.data[y][x] = terrainType
        -- 更新边界追踪
        if x > self.mapWidth then self.mapWidth = x end
        if y > self.mapHeight then self.mapHeight = y end
    else
        if x < 1 or y < 1 or x > self.mapWidth or y > self.mapHeight then return end
        if not self.data[y] then self.data[y] = {} end
        self.data[y][x] = terrainType
    end
end

--- 获取单个瓦片地形
function TerrainTileMap:GetTile(x, y)
    if not self.infinite then
        if x < 1 or y < 1 or x > self.mapWidth or y > self.mapHeight then
            return nil
        end
    end
    if self.data[y] then
        return self.data[y][x]
    end
    return nil
end

--- 用矩形区域填充地形
function TerrainTileMap:FillRect(x1, y1, x2, y2, terrainType)
    if self.infinite then
        -- 无限模式: 不限制坐标范围
        for y = y1, y2 do
            if not self.data[y] then self.data[y] = {} end
            for x = x1, x2 do
                self.data[y][x] = terrainType
            end
        end
    else
        local maxY = math.min(self.mapHeight, y2)
        local maxX = math.min(self.mapWidth, x2)
        for y = math.max(1, y1), maxY do
            if not self.data[y] then self.data[y] = {} end
            for x = math.max(1, x1), maxX do
                self.data[y][x] = terrainType
            end
        end
    end
end

--- 用圆形区域填充地形
function TerrainTileMap:FillCircle(cx, cy, radius, terrainType)
    local r2 = radius * radius
    local startY = math.floor(cy - radius)
    local startX = math.floor(cx - radius)
    local maxY = math.ceil(cy + radius)
    local maxX = math.ceil(cx + radius)
    if not self.infinite then
        startY = math.max(1, startY)
        startX = math.max(1, startX)
        maxY = math.min(self.mapHeight, maxY)
        maxX = math.min(self.mapWidth, maxX)
    end
    for y = startY, maxY do
        if not self.data[y] then self.data[y] = {} end
        for x = startX, maxX do
            local dx = x - cx
            local dy = y - cy
            if dx * dx + dy * dy <= r2 then
                self.data[y][x] = terrainType
            end
        end
    end
end

--- 用噪声生成随机地形（保留兼容，内部方法）
---@param seed number 随机种子
---@param terrainWeights table 各地形权重，例如 { [1]=5, [2]=2, [3]=1 }
function TerrainTileMap:GenerateRandom(seed, terrainWeights)
    math.randomseed(seed or os.time())

    -- 构建权重表
    local totalWeight = 0
    local weightList = {}
    for terrain, weight in pairs(terrainWeights) do
        totalWeight = totalWeight + weight
        weightList[#weightList + 1] = { terrain = terrain, threshold = totalWeight }
    end

    -- 填充地图
    for y = 1, self.mapHeight do
        for x = 1, self.mapWidth do
            local roll = math.random() * totalWeight
            for _, entry in ipairs(weightList) do
                if roll <= entry.threshold then
                    self.data[y][x] = entry.terrain
                    break
                end
            end
        end
    end
end

-- ============================================================================
-- 优化的地皮生成算法（Voronoi 大区块 + 过渡带）
-- ============================================================================

--- 简单哈希噪声（用于边缘扰动）
local function hashNoise(x, y, seed)
    local n = x * 374761393 + y * 668265263 + seed * 1274126177
    n = (n ~ (n >> 13)) * 1274126177
    n = n ~ (n >> 16)
    return (n % 1000) / 1000.0  -- 返回 0~1
end

--- Voronoi 分区生成大区块地形
---@param seed number 随机种子
---@param biomes table 地形权重表 { [terrainType] = weight }
---@param config table|nil 可选配置 { regionCount, transitionWidth, jitter }
function TerrainTileMap:GenerateWithBiomes(seed, biomes, config)
    math.randomseed(seed or os.time())

    -- 解析配置（兼容旧 API：第3个参数如果是数字则忽略，使用默认配置）
    if type(config) == "number" or config == nil then
        config = {}
    end
    local regionCount = config.regionCount or math.max(5, math.floor(self.mapWidth * self.mapHeight / 40))
    local transitionWidth = config.transitionWidth or 2  -- 过渡带宽度（瓦片数）
    local jitter = config.jitter or 0.6  -- 边缘扰动强度 0~1

    -- ===== 第1步：生成 Voronoi 种子点 =====
    local seeds = {}
    local totalWeight = 0
    for _, weight in pairs(biomes) do
        totalWeight = totalWeight + weight
    end
    -- 构建累积分布
    local cdf = {}
    local cumulative = 0
    for terrain, weight in pairs(biomes) do
        cumulative = cumulative + weight
        cdf[#cdf + 1] = { terrain = terrain, threshold = cumulative / totalWeight }
    end

    -- 放置种子点（带最小间距约束，避免两个种子点过于接近）
    local minDist = math.min(self.mapWidth, self.mapHeight) / math.sqrt(regionCount) * 0.5
    for i = 1, regionCount do
        local sx, sy
        local attempts = 0
        repeat
            sx = math.random(1, self.mapWidth)
            sy = math.random(1, self.mapHeight)
            -- 检查与已有种子点的距离
            local tooClose = false
            for _, s in ipairs(seeds) do
                local dx = sx - s.x
                local dy = sy - s.y
                if math.sqrt(dx * dx + dy * dy) < minDist then
                    tooClose = true
                    break
                end
            end
            attempts = attempts + 1
            if not tooClose or attempts > 20 then break end
        until false

        -- 按权重分配地形类型
        local roll = math.random()
        local terrain = cdf[1].terrain
        for _, entry in ipairs(cdf) do
            if roll <= entry.threshold then
                terrain = entry.terrain
                break
            end
        end

        seeds[#seeds + 1] = { x = sx, y = sy, terrain = terrain }
    end

    -- ===== 第2步：Voronoi 分区（每个瓦片归属最近的种子点）=====
    for y = 1, self.mapHeight do
        if not self.data[y] then self.data[y] = {} end
        for x = 1, self.mapWidth do
            local minD1 = math.huge
            local terrain1 = nil

            for _, s in ipairs(seeds) do
                -- 加入扰动使边界不规则
                local noise = hashNoise(x, y, seed + s.x * 100 + s.y) * jitter * 3
                local dx = x - s.x
                local dy = y - s.y
                local d = math.sqrt(dx * dx + dy * dy) + noise

                if d < minD1 then
                    minD1 = d
                    terrain1 = s.terrain
                end
            end

            self.data[y][x] = terrain1
        end
    end

    -- ===== 第3步：多次边缘平滑（消除碎片和噪点）=====
    -- 使用 3 次迭代，确保区块边界干净整洁
    for iteration = 1, 3 do
        local newData = {}
        for y = 1, self.mapHeight do
            newData[y] = {}
            for x = 1, self.mapWidth do
                -- 只统计上下左右四个邻居（不含对角线），更干净
                local counts = {}
                local current = self.data[y][x]
                counts[current] = 1  -- 自身算 1 票

                local neighbors = {
                    (y > 1) and self.data[y-1][x] or current,
                    (y < self.mapHeight) and self.data[y+1][x] or current,
                    (x > 1) and self.data[y][x-1] or current,
                    (x < self.mapWidth) and self.data[y][x+1] or current,
                }
                for _, t in ipairs(neighbors) do
                    counts[t] = (counts[t] or 0) + 1
                end

                -- 如果自身地形不占多数（至少3/5），替换为多数地形
                local maxCount = 0
                local dominant = current
                for t, c in pairs(counts) do
                    if c > maxCount then
                        maxCount = c
                        dominant = t
                    end
                end
                newData[y][x] = dominant
            end
        end
        self.data = newData
    end

    -- ===== 第4步：在边界放置过渡贴图（每条边界只放1个瓦片宽）=====
    -- 规则简单清晰：
    --   遍历每个瓦片，检查它的右邻和下邻
    --   如果不同 → 在当前瓦片位置放一个 LR 或 TB 过渡
    --   不放角落，不放渐变，保持简洁

    local transitionData = {}
    for y = 1, self.mapHeight do
        transitionData[y] = {}
    end

    for y = 1, self.mapHeight do
        for x = 1, self.mapWidth do
            local current = self.data[y][x]
            if current > 10 then goto continue_trans end

            local right  = (x < self.mapWidth) and self.data[y][x+1] or current
            local bottom = (y < self.mapHeight) and self.data[y+1][x] or current

            local hDiff = (right ~= current and right <= 10)
            local vDiff = (bottom ~= current and bottom <= 10)

            if hDiff then
                -- 水平边界：放LR过渡（当前瓦片位置，左=current 右=right）
                local lrType = self:FindDirectionalEdge(current, right, "lr")
                if lrType then
                    transitionData[y][x] = lrType
                    goto continue_trans
                end
            end

            if vDiff then
                -- 垂直边界：放TB过渡（当前瓦片位置，上=current 下=bottom）
                local tbType = self:FindDirectionalEdge(current, bottom, "tb")
                if tbType then
                    transitionData[y][x] = tbType
                    goto continue_trans
                end
            end

            ::continue_trans::
        end
    end

    -- 将过渡数据合并到主地图
    for y = 1, self.mapHeight do
        for x = 1, self.mapWidth do
            if transitionData[y][x] then
                self.data[y][x] = transitionData[y][x]
            end
        end
    end

    print("[TerrainTileMap] Voronoi 生成完成: " .. regionCount .. " 个区块")
end

--- 查找两种地形之间的方向性边缘过渡（保留方向信息，不标准化）
--- LR贴图约定：左边是terrainA的颜色，右边是terrainB的颜色
--- TB贴图约定：上面是terrainA的颜色，下面是terrainB的颜色
---@param terrainA number 左侧/上方的地形（方向的起始端）
---@param terrainB number 右侧/下方的地形（方向的目标端）
---@param direction string "lr" 或 "tb"
---@return number|nil 过渡地形类型
function TerrainTileMap:FindDirectionalEdge(terrainA, terrainB, direction)
    local T = TerrainTileMap.TERRAIN

    -- 带方向的边缘映射：[fromTerrain][toTerrain][direction] = terrainType
    -- 每对地形都有 LR 和 TB 两个方向的专用过渡贴图
    -- 反向查找也支持（如 MUD→GRASS 使用 GRASS_MUD 的贴图）
    local DIRECTIONAL_MAP = {
        [T.GRASS] = {
            [T.MUD]       = { lr = T.GRASS_MUD_LR,       tb = T.GRASS_MUD_TB },
            [T.SWAMP]     = { lr = T.GRASS_SWAMP_LR,     tb = T.GRASS_SWAMP_TB },
            [T.ROCKY]     = { lr = T.GRASS_ROCKY_LR,     tb = T.GRASS_ROCKY_TB },
            [T.SAND]      = { lr = T.GRASS_SAND_LR,      tb = T.GRASS_SAND_LR },
            [T.SNOW]      = { lr = T.GRASS_SNOW_TB,      tb = T.GRASS_SNOW_TB },
            [T.DEAD_GRASS]= { lr = T.GRASS_DEADGRASS_LR, tb = T.GRASS_DEADGRASS_LR },
        },
        [T.MUD] = {
            [T.SWAMP]     = { lr = T.MUD_SWAMP_LR,      tb = T.MUD_SWAMP_TB },
            [T.ROCKY]     = { lr = T.MUD_ROCKY_LR,      tb = T.MUD_ROCKY_TB },
            [T.GRASS]     = { lr = T.MUD_GRASS_LR,      tb = T.MUD_GRASS_TB },
        },
        [T.ROCKY] = {
            [T.VOLCANIC]  = { lr = T.ROCKY_VOLCANIC_LR,  tb = T.ROCKY_VOLCANIC_TB },
            [T.MUD]       = { lr = T.ROCKY_MUD_LR,      tb = T.ROCKY_MUD_TB },
            [T.GRASS]     = { lr = T.ROCKY_GRASS_LR,    tb = T.ROCKY_GRASS_TB },
        },
        [T.SWAMP] = {
            [T.GRASS]     = { lr = T.SWAMP_GRASS_LR,    tb = T.SWAMP_GRASS_TB },
            [T.MUD]       = { lr = T.SWAMP_MUD_LR,      tb = T.SWAMP_MUD_TB },
        },
        [T.SAND] = {
            [T.GRASS]     = { lr = T.SAND_GRASS_LR,     tb = T.SAND_GRASS_LR },
        },
        [T.SNOW] = {
            [T.GRASS]     = { lr = T.SNOW_GRASS_TB,     tb = T.SNOW_GRASS_TB },
        },
        [T.DEAD_GRASS] = {
            [T.GRASS]     = { lr = T.DEADGRASS_GRASS_LR, tb = T.DEADGRASS_GRASS_LR },
        },
        [T.VOLCANIC] = {
            [T.ROCKY]     = { lr = T.VOLCANIC_ROCKY_LR,  tb = T.VOLCANIC_ROCKY_TB },
        },
    }

    -- 正向查找
    if DIRECTIONAL_MAP[terrainA] and DIRECTIONAL_MAP[terrainA][terrainB] then
        local entry = DIRECTIONAL_MAP[terrainA][terrainB]
        if entry[direction] then
            return entry[direction]
        end
    end

    -- 如果没有精确的方向性贴图，尝试用渐变贴图作为替代
    local gradType = self:FindGradientTerrain(terrainA, terrainB)
    if gradType then
        return gradType
    end

    return nil
end

--- 查找两种地形之间的渐变/混合地形类型（用于对角线边界或无方向性的混合区域）
---@param t1 number 地形类型1（较小值）
---@param t2 number 地形类型2（较大值）
---@return number|nil 过渡地形类型，无则返回 nil
function TerrainTileMap:FindGradientTerrain(t1, t2)
    local T = TerrainTileMap.TERRAIN

    -- 渐变/混合贴图映射（只包含真正的渐变贴图 ID 30-32）
    local GRADIENT_MAP = {
        [T.GRASS] = {
            [T.MUD]      = T.GRASS_TO_MUD,
            [T.SWAMP]    = T.GRASS_TO_SWAMP,
        },
        [T.ROCKY] = {
            [T.VOLCANIC] = T.ROCKY_TO_VOLCANIC,
        },
    }

    -- 正向查找
    if GRADIENT_MAP[t1] and GRADIENT_MAP[t1][t2] then
        return GRADIENT_MAP[t1][t2]
    end
    -- 反向查找
    if GRADIENT_MAP[t2] and GRADIENT_MAP[t2][t1] then
        return GRADIENT_MAP[t2][t1]
    end

    return nil
end

--- 获取邻域中出现最多的地形类型
function TerrainTileMap:GetDominantNeighbor(x, y)
    local counts = {}
    for dy = -1, 1 do
        for dx = -1, 1 do
            local nx, ny = x + dx, y + dy
            local t = self:GetTile(nx, ny)
            if t then
                counts[t] = (counts[t] or 0) + 1
            end
        end
    end

    local maxCount = 0
    local dominant = self.data[y][x]
    for t, c in pairs(counts) do
        if c > maxCount then
            maxCount = c
            dominant = t
        end
    end
    return dominant
end

-- ============================================================================
-- 自动过渡选择
-- ============================================================================

--- 获取瓦片应使用的贴图路径（考虑过渡）
--- 过渡信息全部来自数据层（GenerateWithBiomes 或编辑器写入），渲染时不再做邻居检测
---@return string? 贴图路径
---@return string 过渡类型: "base" | "edge_lr" | "edge_tb" | "corner" | "gradient"
function TerrainTileMap:GetTileTexture(x, y)
    local current = self:GetTile(x, y)
    if not current then return nil, "base" end

    -- 如果瓦片已经是过渡类型（数据层已处理），直接返回对应贴图
    if current > 10 then
        local texPath = BASE_TEXTURES[current]
        if texPath then
            -- LR 类型: 11-16(正向LR), 22(草泥LR), 25(石火LR),
            --          33(泥草LR), 35(石草LR), 37(沼草LR), 39(沙草LR),
            --          41(枯草LR), 42(沼泥LR), 44(石泥LR), 46(火石LR)
            local LR_IDS = {
                [11]=true, [12]=true, [13]=true, [14]=true, [15]=true, [16]=true,
                [22]=true, [25]=true,
                [33]=true, [35]=true, [37]=true, [39]=true, [41]=true,
                [42]=true, [44]=true, [46]=true,
            }
            -- TB 类型: 17-21(正向TB), 23(草沼TB), 24(泥石TB),
            --          34(泥草TB), 36(石草TB), 38(沼草TB), 40(雪草TB),
            --          43(沼泥TB), 45(石泥TB), 47(火石TB)
            local TB_IDS = {
                [17]=true, [18]=true, [19]=true, [20]=true, [21]=true,
                [23]=true, [24]=true,
                [34]=true, [36]=true, [38]=true, [40]=true,
                [43]=true, [45]=true, [47]=true,
            }
            if LR_IDS[current] then
                return texPath, "edge_lr"
            elseif TB_IDS[current] then
                return texPath, "edge_tb"
            else
                return texPath, "gradient"
            end
        end
        -- 如果没有对应贴图（不应发生），fallback 到草地
        return BASE_TEXTURES[1], "base"
    end

    -- 基础地形：直接返回基础贴图，不做运行时邻居检测
    return BASE_TEXTURES[current], "base"
end

-- ============================================================================
-- 渲染
-- ============================================================================

--- 渲染可见区域的瓦片地图
---@param screenWidth number 屏幕宽度
---@param screenHeight number 屏幕高度
function TerrainTileMap:Render(screenWidth, screenHeight)
    local vg = self.vg
    local ts = self.tileSize

    -- 计算可见范围
    local startX = math.max(1, math.floor(self.cameraX / ts) + 1)
    local startY = math.max(1, math.floor(self.cameraY / ts) + 1)
    local endX = math.ceil((self.cameraX + screenWidth) / ts) + 1
    local endY = math.ceil((self.cameraY + screenHeight) / ts) + 1
    if not self.infinite then
        endX = math.min(self.mapWidth, endX)
        endY = math.min(self.mapHeight, endY)
    else
        endX = math.min(self.mapWidth, endX)
        endY = math.min(self.mapHeight, endY)
    end

    -- 渲染可见瓦片
    for y = startY, endY do
        for x = startX, endX do
            local texPath, _ = self:GetTileTexture(x, y)
            if texPath then
                local imgId = self:GetImage(texPath)
                if imgId then
                    local px = (x - 1) * ts - self.cameraX
                    local py = (y - 1) * ts - self.cameraY

                    local paint = nvgImagePattern(vg, px, py, ts, ts, 0, imgId, 1.0)
                    nvgBeginPath(vg)
                    nvgRect(vg, px, py, ts, ts)
                    nvgFillPaint(vg, paint)
                    nvgFill(vg)
                end
            end
        end
    end
end

--- 渲染网格线（调试用）
function TerrainTileMap:RenderGrid(screenWidth, screenHeight)
    local vg = self.vg
    local ts = self.tileSize

    local startX = math.max(1, math.floor(self.cameraX / ts) + 1)
    local startY = math.max(1, math.floor(self.cameraY / ts) + 1)
    local endX = math.min(self.mapWidth, math.ceil((self.cameraX + screenWidth) / ts) + 1)
    local endY = math.min(self.mapHeight, math.ceil((self.cameraY + screenHeight) / ts) + 1)

    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 40))
    nvgStrokeWidth(vg, 1.0)

    for y = startY, endY do
        for x = startX, endX do
            local px = (x - 1) * ts - self.cameraX
            local py = (y - 1) * ts - self.cameraY
            nvgBeginPath(vg)
            nvgRect(vg, px, py, ts, ts)
            nvgStroke(vg)
        end
    end
end

--- 设置相机位置
function TerrainTileMap:SetCamera(x, y)
    self.cameraX = math.max(0, x)
    self.cameraY = math.max(0, y)
end

--- 移动相机
function TerrainTileMap:MoveCamera(dx, dy)
    self.cameraX = math.max(0, self.cameraX + dx)
    self.cameraY = math.max(0, self.cameraY + dy)
end

--- 屏幕坐标转地图坐标
function TerrainTileMap:ScreenToTile(screenX, screenY)
    local tileX = math.floor((screenX + self.cameraX) / self.tileSize) + 1
    local tileY = math.floor((screenY + self.cameraY) / self.tileSize) + 1
    return tileX, tileY
end

--- 清理所有 NanoVG 图片资源
function TerrainTileMap:Destroy()
    for path, imgId in pairs(self.imageCache) do
        nvgDeleteImage(self.vg, imgId)
    end
    self.imageCache = {}
    print("[TerrainTileMap] 资源已清理")
end

return TerrainTileMap
