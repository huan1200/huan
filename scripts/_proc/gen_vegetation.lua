-- 程序化生成饥荒风格绿植和资产贴图
-- 输出到 /workspace/assets/image/资产绿植/

local OUTPUT_DIR = "/workspace/assets/image/资产绿植/"

-- ============================================================================
-- 工具函数
-- ============================================================================

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function smoothstep(edge0, edge1, x)
    local t = clamp((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)
end

-- 简单哈希噪声
local function hash(x, y, seed)
    local n = x * 374761393 + y * 668265263 + (seed or 0) * 1013904223
    n = (n ~ (n >> 13)) * 1274126177
    n = n ~ (n >> 16)
    return (n % 10000) / 10000.0
end

-- 值噪声(双线性插值)
local function valueNoise(x, y, seed)
    local ix = math.floor(x)
    local iy = math.floor(y)
    local fx = x - ix
    local fy = y - iy
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    local a = hash(ix, iy, seed)
    local b = hash(ix + 1, iy, seed)
    local c = hash(ix, iy + 1, seed)
    local d = hash(ix + 1, iy + 1, seed)
    return lerp(lerp(a, b, fx), lerp(c, d, fx), fy)
end

-- 分形噪声
local function fbm(x, y, octaves, seed)
    local val = 0
    local amp = 1.0
    local freq = 1.0
    local total = 0
    for i = 1, octaves do
        val = val + valueNoise(x * freq, y * freq, seed + i * 100) * amp
        total = total + amp
        amp = amp * 0.5
        freq = freq * 2.0
    end
    return val / total
end

-- 椭圆距离(归一化0~1, 0=中心, 1=边缘)
local function ellipseDist(x, y, cx, cy, rx, ry)
    local dx = (x - cx) / rx
    local dy = (y - cy) / ry
    return math.sqrt(dx * dx + dy * dy)
end

-- 圆形距离
local function circleDist(x, y, cx, cy, r)
    local dx = x - cx
    local dy = y - cy
    return math.sqrt(dx * dx + dy * dy) / r
end

-- 设置像素(带边界检查)
local function safeSetPixel(img, x, y, w, h, r, g, b, a)
    if x >= 0 and x < w and y >= 0 and y < h then
        img:SetPixel(x, y, Color(r, g, b, a))
    end
end

-- 绘制填充椭圆(带噪声边缘和纹理)
local function drawFilledEllipse(img, w, h, cx, cy, rx, ry, baseR, baseG, baseB, alpha, seed, outlineWidth)
    outlineWidth = outlineWidth or 2.0
    for py = math.max(0, math.floor(cy - ry - outlineWidth - 2)), math.min(h - 1, math.ceil(cy + ry + outlineWidth + 2)) do
        for px = math.max(0, math.floor(cx - rx - outlineWidth - 2)), math.min(w - 1, math.ceil(cx + rx + outlineWidth + 2)) do
            local dist = ellipseDist(px, py, cx, cy, rx, ry)
            -- 添加噪声到边缘
            local edgeNoise = (valueNoise(px * 0.15, py * 0.15, seed) - 0.5) * 0.15
            local noisyDist = dist + edgeNoise

            if noisyDist < 1.0 then
                -- 内部填充(带纹理)
                local texNoise = fbm(px * 0.08, py * 0.08, 3, seed + 50) * 0.15
                local shade = 1.0 - dist * 0.3 -- 中心亮边缘暗
                local r = clamp(baseR * (shade + texNoise), 0, 1)
                local g = clamp(baseG * (shade + texNoise), 0, 1)
                local b = clamp(baseB * (shade + texNoise), 0, 1)
                safeSetPixel(img, px, py, w, h, r, g, b, alpha)
            elseif noisyDist < 1.0 + outlineWidth / math.max(rx, ry) then
                -- 描边
                local outAlpha = alpha * (1.0 - (noisyDist - 1.0) / (outlineWidth / math.max(rx, ry)))
                safeSetPixel(img, px, py, w, h, 0.04, 0.03, 0.02, outAlpha)
            end
        end
    end
end

-- ============================================================================
-- 树木生成
-- ============================================================================

local function generateTree1(img, w, h)
    -- 树1: 粗壮的饥荒风大树(圆形树冠, 粗树干)
    img:SetSize(w, h, 4)
    img:Clear(Color(0, 0, 0, 0))

    local seed = 1001
    local trunkCX = w * 0.5
    local trunkBottom = h * 0.92
    local trunkTop = h * 0.45
    local trunkW = w * 0.08

    -- 树干(从底向上, 略微弯曲)
    for py = math.floor(trunkTop), math.floor(trunkBottom) do
        local t = (py - trunkTop) / (trunkBottom - trunkTop)
        local curveX = math.sin(t * 2.5) * w * 0.02
        local widthHere = trunkW * (0.7 + t * 0.3)
        for px = math.floor(trunkCX - widthHere + curveX), math.ceil(trunkCX + widthHere + curveX) do
            local distFromCenter = math.abs(px - trunkCX - curveX) / widthHere
            local noise = valueNoise(px * 0.2, py * 0.1, seed) * 0.12
            if distFromCenter + noise < 1.0 then
                local bark = 0.18 + valueNoise(px * 0.15, py * 0.08, seed + 10) * 0.08
                local shade = 1.0 - distFromCenter * 0.4
                safeSetPixel(img, px, py, w, h, bark * shade, bark * shade * 0.7, bark * shade * 0.4, 1.0)
            elseif distFromCenter + noise < 1.15 then
                safeSetPixel(img, px, py, w, h, 0.05, 0.03, 0.02, 1.0)
            end
        end
    end

    -- 树冠(多个重叠椭圆 = 丰满树冠)
    local crownCY = h * 0.32
    local crownRX = w * 0.38
    local crownRY = h * 0.28

    -- 深色底层树叶
    drawFilledEllipse(img, w, h, w * 0.5, crownCY + h * 0.04, crownRX * 1.05, crownRY * 0.9,
        0.12, 0.25, 0.08, 1.0, seed + 1, 2.5)

    -- 主树冠
    drawFilledEllipse(img, w, h, w * 0.48, crownCY, crownRX, crownRY,
        0.18, 0.38, 0.12, 1.0, seed + 2, 2.5)

    -- 亮色高光区
    drawFilledEllipse(img, w, h, w * 0.44, crownCY - h * 0.06, crownRX * 0.6, crownRY * 0.55,
        0.25, 0.50, 0.18, 0.85, seed + 3, 0)

    -- 右侧小突起
    drawFilledEllipse(img, w, h, w * 0.68, crownCY + h * 0.02, crownRX * 0.4, crownRY * 0.5,
        0.15, 0.33, 0.10, 1.0, seed + 4, 2.0)
end

local function generateTree2(img, w, h)
    -- 树2: 枯树(光秃树干 + 稀疏枝条 + 底部红色花丛)
    img:SetSize(w, h, 4)
    img:Clear(Color(0, 0, 0, 0))

    local seed = 2001
    local trunkCX = w * 0.5
    local trunkBottom = h * 0.93
    local trunkTop = h * 0.15
    local trunkW = w * 0.055

    -- 主树干(微弯)
    for py = math.floor(trunkTop), math.floor(trunkBottom) do
        local t = (py - trunkTop) / (trunkBottom - trunkTop)
        local curveX = math.sin(t * 3.0 + 0.5) * w * 0.03
        local widthHere = trunkW * (0.4 + t * 0.6)
        for px = math.floor(trunkCX - widthHere + curveX), math.ceil(trunkCX + widthHere + curveX) do
            local distFromCenter = math.abs(px - trunkCX - curveX) / widthHere
            local noise = valueNoise(px * 0.2, py * 0.08, seed) * 0.1
            if distFromCenter + noise < 1.0 then
                local bark = 0.12 + valueNoise(px * 0.12, py * 0.06, seed + 5) * 0.06
                safeSetPixel(img, px, py, w, h, bark, bark * 0.75, bark * 0.5, 1.0)
            elseif distFromCenter + noise < 1.2 then
                safeSetPixel(img, px, py, w, h, 0.04, 0.03, 0.02, 0.9)
            end
        end
    end

    -- 枝条(向上斜伸, 2~3根)
    local branches = {
        {startY = 0.35, angle = -0.6, len = 0.25},
        {startY = 0.45, angle = 0.5, len = 0.2},
        {startY = 0.25, angle = -0.3, len = 0.18},
    }
    for _, br in ipairs(branches) do
        local sy = h * br.startY
        local sx = trunkCX + math.sin(br.startY * 5) * w * 0.02
        local brLen = h * br.len
        for step = 0, math.floor(brLen) do
            local t = step / brLen
            local bx = sx + math.sin(br.angle) * step + math.sin(t * 4) * 2
            local by = sy - math.cos(br.angle) * step
            local bw = trunkW * (1.0 - t) * 0.5
            for dx = -math.ceil(bw), math.ceil(bw) do
                local px = math.floor(bx + dx)
                local py = math.floor(by)
                if math.abs(dx) / math.max(bw, 0.5) < 1.0 then
                    safeSetPixel(img, px, py, w, h, 0.10, 0.07, 0.05, 1.0)
                end
            end
        end
    end

    -- 底部红色花丛(彼岸花风格)
    local flowerCY = h * 0.85
    for i = 1, 8 do
        local fx = w * 0.5 + (hash(i, 0, seed) - 0.5) * w * 0.5
        local fy = flowerCY + (hash(i, 1, seed) - 0.5) * h * 0.12
        local fr = w * 0.04 + hash(i, 2, seed) * w * 0.03
        drawFilledEllipse(img, w, h, fx, fy, fr, fr * 0.8,
            0.70, 0.08, 0.05, 0.9, seed + i * 10, 1.5)
    end
end

-- ============================================================================
-- 岩石生成
-- ============================================================================

local function generateRock(img, w, h, seed, style)
    img:SetSize(w, h, 4)
    img:Clear(Color(0, 0, 0, 0))

    if style == 1 then
        -- 散落碎石(多个小石头)
        local stones = {
            {x = 0.35, y = 0.55, rx = 0.12, ry = 0.10},
            {x = 0.55, y = 0.50, rx = 0.15, ry = 0.12},
            {x = 0.65, y = 0.62, rx = 0.10, ry = 0.08},
            {x = 0.40, y = 0.68, rx = 0.08, ry = 0.07},
            {x = 0.58, y = 0.70, rx = 0.09, ry = 0.06},
        }
        for i, s in ipairs(stones) do
            local baseGray = 0.35 + hash(i, 0, seed) * 0.15
            drawFilledEllipse(img, w, h, w * s.x, h * s.y, w * s.rx, h * s.ry,
                baseGray, baseGray * 0.92, baseGray * 0.85, 1.0, seed + i * 7, 2.0)
        end

    elseif style == 2 then
        -- 大圆石
        local cx, cy = w * 0.5, h * 0.55
        local rx, ry = w * 0.35, h * 0.32
        drawFilledEllipse(img, w, h, cx, cy, rx, ry, 0.38, 0.36, 0.32, 1.0, seed, 3.0)
        -- 高光
        drawFilledEllipse(img, w, h, cx - rx * 0.2, cy - ry * 0.3, rx * 0.4, ry * 0.3,
            0.52, 0.50, 0.46, 0.5, seed + 20, 0)

    elseif style == 3 then
        -- 高角岩(竖长形)
        local cx, cy = w * 0.5, h * 0.5
        -- 用多个椭圆组合成尖石头
        drawFilledEllipse(img, w, h, cx, cy + h * 0.1, w * 0.28, h * 0.35, 0.32, 0.30, 0.27, 1.0, seed, 2.5)
        drawFilledEllipse(img, w, h, cx - w * 0.05, cy - h * 0.08, w * 0.20, h * 0.30, 0.36, 0.34, 0.30, 1.0, seed + 5, 2.5)
        -- 尖顶高光
        drawFilledEllipse(img, w, h, cx - w * 0.08, cy - h * 0.15, w * 0.10, h * 0.15,
            0.48, 0.45, 0.40, 0.6, seed + 15, 0)

    elseif style == 4 then
        -- 扁平石板
        local cx, cy = w * 0.5, h * 0.6
        local rx, ry = w * 0.38, h * 0.18
        drawFilledEllipse(img, w, h, cx, cy, rx, ry, 0.40, 0.38, 0.34, 1.0, seed, 2.5)
        -- 表面纹理线
        drawFilledEllipse(img, w, h, cx + w * 0.05, cy - ry * 0.2, rx * 0.6, ry * 0.3,
            0.48, 0.45, 0.40, 0.4, seed + 30, 0)

    elseif style == 5 then
        -- 棱角碎石堆
        local pieces = {
            {x = 0.45, y = 0.45, rx = 0.20, ry = 0.18},
            {x = 0.60, y = 0.55, rx = 0.18, ry = 0.20},
            {x = 0.38, y = 0.63, rx = 0.15, ry = 0.14},
        }
        for i, p in ipairs(pieces) do
            local gray = 0.30 + hash(i, 5, seed) * 0.12
            drawFilledEllipse(img, w, h, w * p.x, h * p.y, w * p.rx, h * p.ry,
                gray, gray * 0.93, gray * 0.87, 1.0, seed + i * 13, 2.5)
        end
    end
end

-- ============================================================================
-- 花朵生成
-- ============================================================================

local function generateFlower(img, w, h, seed, style)
    img:SetSize(w, h, 4)
    img:Clear(Color(0, 0, 0, 0))

    local stemBottom = h * 0.9
    local stemTop = h * 0.4
    local stemX = w * 0.5

    -- 茎(细长, 略弯)
    for py = math.floor(stemTop), math.floor(stemBottom) do
        local t = (py - stemTop) / (stemBottom - stemTop)
        local curve = math.sin(t * 2.0) * w * 0.02
        local sw = 1.5 + t * 0.5
        for dx = -math.ceil(sw), math.ceil(sw) do
            local px = math.floor(stemX + curve + dx)
            if math.abs(dx) <= sw then
                safeSetPixel(img, px, py, w, h, 0.15, 0.35, 0.10, 1.0)
            end
        end
    end

    -- 叶子(1~2片小叶)
    local leafY = h * 0.65
    drawFilledEllipse(img, w, h, stemX + w * 0.08, leafY, w * 0.07, h * 0.04,
        0.18, 0.42, 0.12, 0.9, seed + 50, 1.0)

    if style == 1 then
        -- 玫瑰(红色, 多层花瓣)
        local flowerCY = h * 0.32
        drawFilledEllipse(img, w, h, stemX, flowerCY, w * 0.22, h * 0.18,
            0.65, 0.05, 0.08, 1.0, seed + 1, 2.0)
        drawFilledEllipse(img, w, h, stemX - w * 0.03, flowerCY - h * 0.02, w * 0.14, h * 0.12,
            0.80, 0.12, 0.10, 0.85, seed + 2, 0)
        -- 中心深色
        drawFilledEllipse(img, w, h, stemX, flowerCY + h * 0.02, w * 0.06, h * 0.05,
            0.40, 0.02, 0.03, 0.7, seed + 3, 0)

    elseif style == 2 then
        -- 郁金香(紫粉色, 杯状)
        local flowerCY = h * 0.30
        drawFilledEllipse(img, w, h, stemX, flowerCY, w * 0.16, h * 0.20,
            0.60, 0.15, 0.55, 1.0, seed + 1, 2.0)
        drawFilledEllipse(img, w, h, stemX, flowerCY - h * 0.04, w * 0.12, h * 0.12,
            0.72, 0.25, 0.65, 0.7, seed + 2, 0)

    elseif style == 3 then
        -- 蓟花(紫色, 刺状)
        local flowerCY = h * 0.28
        drawFilledEllipse(img, w, h, stemX, flowerCY + h * 0.04, w * 0.12, h * 0.10,
            0.20, 0.35, 0.15, 1.0, seed + 1, 1.5)
        -- 紫色花头
        drawFilledEllipse(img, w, h, stemX, flowerCY - h * 0.02, w * 0.14, h * 0.14,
            0.50, 0.15, 0.55, 1.0, seed + 2, 2.0)
        -- 刺状顶部
        for i = 1, 5 do
            local angle = (i / 5) * math.pi - math.pi * 0.1
            local tipX = stemX + math.cos(angle) * w * 0.12
            local tipY = flowerCY - h * 0.02 - math.sin(angle) * h * 0.12
            drawFilledEllipse(img, w, h, tipX, tipY, w * 0.02, h * 0.04,
                0.55, 0.20, 0.60, 0.8, seed + 10 + i, 0)
        end

    elseif style == 4 then
        -- 向日葵(黄色大花盘)
        local flowerCY = h * 0.30
        -- 花瓣(黄色)
        for i = 1, 10 do
            local angle = (i / 10) * math.pi * 2
            local petalX = stemX + math.cos(angle) * w * 0.15
            local petalY = flowerCY + math.sin(angle) * h * 0.12
            drawFilledEllipse(img, w, h, petalX, petalY, w * 0.07, h * 0.05,
                0.85, 0.70, 0.05, 0.9, seed + i, 1.0)
        end
        -- 中心盘(深棕色)
        drawFilledEllipse(img, w, h, stemX, flowerCY, w * 0.12, h * 0.10,
            0.25, 0.15, 0.05, 1.0, seed + 20, 2.0)
    end
end

-- ============================================================================
-- 草丛/植物生成
-- ============================================================================

local function generatePlant(img, w, h, seed, style)
    img:SetSize(w, h, 4)
    img:Clear(Color(0, 0, 0, 0))

    if style == 1 then
        -- 高草丛(多根细长草叶向外散开)
        local baseY = h * 0.88
        local grassCount = 7
        for i = 1, grassCount do
            local baseX = w * 0.5 + (i - (grassCount + 1) / 2) * w * 0.06
            local angle = (i - (grassCount + 1) / 2) * 0.15
            local grassH = h * (0.45 + hash(i, 0, seed) * 0.2)
            local tipCurve = (hash(i, 1, seed) - 0.5) * 0.4

            for py = math.floor(baseY - grassH), math.floor(baseY) do
                local t = (baseY - py) / grassH  -- 0=底 1=顶
                local curve = angle * t * t + tipCurve * t * t * t
                local px = math.floor(baseX + curve * w * 0.3)
                local gw = 2.0 * (1.0 - t * 0.6)
                local green = 0.30 + t * 0.15 + hash(i, 3, seed) * 0.08
                for dx = -math.ceil(gw), math.ceil(gw) do
                    if math.abs(dx) <= gw then
                        safeSetPixel(img, px + dx, py, w, h, green * 0.6, green, green * 0.3, 1.0)
                    end
                end
            end
        end

    elseif style == 2 then
        -- 浆果藤蔓(弯曲枝条 + 红色小圆点浆果)
        local baseY = h * 0.85
        local branches = 3
        for b = 1, branches do
            local startX = w * (0.3 + b * 0.15)
            local branchH = h * (0.35 + hash(b, 0, seed) * 0.15)
            local curve = (hash(b, 1, seed) - 0.5) * 1.5

            for py = math.floor(baseY - branchH), math.floor(baseY) do
                local t = (baseY - py) / branchH
                local cx = startX + math.sin(t * 3.0 + b) * w * 0.08 + curve * t * w * 0.1
                local bw = 1.5 * (1.0 - t * 0.4)
                for dx = -math.ceil(bw), math.ceil(bw) do
                    if math.abs(dx) <= bw then
                        safeSetPixel(img, math.floor(cx) + dx, py, w, h, 0.20, 0.30, 0.10, 1.0)
                    end
                end

                -- 叶子(沿途随机)
                if hash(b * 100 + py, 0, seed) > 0.85 then
                    local lx = cx + (hash(py, b, seed) - 0.5) * 6
                    drawFilledEllipse(img, w, h, lx, py, w * 0.04, h * 0.025,
                        0.20, 0.42, 0.12, 0.85, seed + py, 0.8)
                end
            end

            -- 浆果(红色小点)
            for i = 1, 3 do
                local bt = 0.3 + hash(b, i + 10, seed) * 0.5
                local by = baseY - branchH * bt
                local bx = startX + math.sin(bt * 3.0 + b) * w * 0.08 + curve * bt * w * 0.1
                bx = bx + (hash(b, i + 20, seed) - 0.5) * 8
                drawFilledEllipse(img, w, h, bx, by, w * 0.03, h * 0.025,
                    0.70, 0.10, 0.08, 1.0, seed + b * 10 + i, 1.0)
            end
        end

    elseif style == 3 then
        -- 枯灌木(棕色矮灌木, 枯萎感)
        local baseY = h * 0.85
        local bushCount = 5
        for i = 1, bushCount do
            local startX = w * (0.25 + hash(i, 0, seed) * 0.5)
            local brLen = h * (0.25 + hash(i, 1, seed) * 0.15)
            local angle = (hash(i, 2, seed) - 0.5) * 1.8

            for step = 0, math.floor(brLen) do
                local t = step / brLen
                local px = startX + angle * step * 0.5 + math.sin(t * 5 + i) * 2
                local py = baseY - step
                local bw = 1.8 * (1.0 - t * 0.7)
                for dx = -math.ceil(bw), math.ceil(bw) do
                    if math.abs(dx) <= bw then
                        local brown = 0.22 + hash(step, i, seed) * 0.06
                        safeSetPixel(img, math.floor(px) + dx, math.floor(py), w, h,
                            brown, brown * 0.7, brown * 0.35, 1.0)
                    end
                end
            end
        end
        -- 稀疏枯叶
        for i = 1, 6 do
            local lx = w * (0.2 + hash(i, 50, seed) * 0.6)
            local ly = h * (0.55 + hash(i, 51, seed) * 0.25)
            drawFilledEllipse(img, w, h, lx, ly, w * 0.04, h * 0.03,
                0.35, 0.25, 0.10, 0.7, seed + 60 + i, 0.8)
        end
    end
end

-- ============================================================================
-- 主入口
-- ============================================================================

function Start()
    local ok, err = pcall(function()
        print("[gen_vegetation] Starting procedural vegetation generation...")

        local img = Image()

        -- 树木(128x160)
        print("[gen_vegetation] Generating trees...")
        generateTree1(img, 128, 160)
        assert(img:SavePNG(OUTPUT_DIR .. "edited_xs1_20260530165514.png"), "SavePNG failed: tree1")
        print("[gen_vegetation]   tree1 OK")

        generateTree2(img, 128, 160)
        assert(img:SavePNG(OUTPUT_DIR .. "edited_xs2_20260530165406.png"), "SavePNG failed: tree2")
        print("[gen_vegetation]   tree2 OK")

        -- 岩石(128x128)
        print("[gen_vegetation] Generating rocks...")
        local rockSeeds = {3001, 3002, 3003, 3004, 3005}
        local rockNames = {"s2.png", "s3.png", "s4.png", "s5.png", "s6.png"}
        for i = 1, 5 do
            generateRock(img, 128, 128, rockSeeds[i], i)
            assert(img:SavePNG(OUTPUT_DIR .. rockNames[i]), "SavePNG failed: rock" .. i)
            print("[gen_vegetation]   rock" .. i .. " OK")
        end

        -- 花朵(128x160)
        print("[gen_vegetation] Generating flowers...")
        local flowerNames = {"h1.png", "h2.png", "h3.png", "h4.png"}
        for i = 1, 4 do
            generateFlower(img, 128, 160, 4000 + i * 100, i)
            assert(img:SavePNG(OUTPUT_DIR .. flowerNames[i]), "SavePNG failed: flower" .. i)
            print("[gen_vegetation]   flower" .. i .. " OK")
        end

        -- 草丛/植物(128x160)
        print("[gen_vegetation] Generating plants...")
        local plantNames = {"1.png", "2.png", "3.png"}
        for i = 1, 3 do
            generatePlant(img, 128, 160, 5000 + i * 100, i)
            assert(img:SavePNG(OUTPUT_DIR .. plantNames[i]), "SavePNG failed: plant" .. i)
            print("[gen_vegetation]   plant" .. i .. " OK")
        end

        print("[gen_vegetation] All 14 images generated successfully!")
    end)
    if not ok then
        print("[gen_vegetation] ERROR: " .. tostring(err))
        log:Write(LOG_ERROR, "[gen_vegetation] " .. tostring(err))
    end
    engine:Exit()
end
