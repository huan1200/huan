-- ============================================================================
-- 饥荒风格地形瓦片地图 Demo (独立演示文件，不影响主游戏)
-- 如需单独运行此 demo，将 build entry 改为 "TileMap/demo.lua"
-- ============================================================================

require "LuaScripts/Utilities/Sample"
local UI = require("urhox-libs/UI")

---@type userdata
local vg = nil
local fontId = -1

---@type table
local tileMap = nil

local screenWidth = 0
local screenHeight = 0
local dpr = 1.0

local showGrid = false
local currentBrush = 1
local brushSize = 1
local isPainting = false
local CAMERA_SPEED = 300

function Start()
    SampleStart()
    graphics.windowTitle = "饥荒风格地形瓦片地图"

    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    dpr = graphics:GetDPR()
    screenWidth = physW / dpr
    screenHeight = physH / dpr

    vg = nvgCreate(1)
    if not vg then
        print("ERROR: Failed to create NanoVG context")
        return
    end

    fontId = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")

    local TerrainTileMap = require("TileMap.TerrainTileMap")
    tileMap = TerrainTileMap.New(vg, {
        mapWidth = 40,
        mapHeight = 30,
        tileSize = 64,
    })

    GenerateWorld()
    InitUI()

    SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")

    print("=== 饥荒风格地形瓦片地图 已启动 ===")
    print("WASD/方向键: 移动相机 | 鼠标左键: 绘制 | 1-0: 切换画笔 | G: 网格 | R: 重生成")
end

function Stop()
    UI.Shutdown()
    if tileMap then tileMap:Destroy() end
    if vg then nvgDelete(vg); vg = nil end
end

function GenerateWorld()
    local T = tileMap.TERRAIN
    -- 使用优化后的 Voronoi 大区块算法 + 方向性过渡带（LR/TB/Corner）
    tileMap:GenerateWithBiomes(os.time(), {
        [T.GRASS] = 5, [T.MUD] = 2, [T.SWAMP] = 2,
        [T.FOREST] = 2, [T.SAND] = 1, [T.SNOW] = 1,
    }, {
        regionCount = 18,       -- 18个大区块（覆盖更多地形组合）
        transitionWidth = 2.5,  -- 过渡带宽度
        jitter = 0.7,           -- 边缘扰动
    })

    -- 鹅卵石路（装饰性道路）
    for x = 10, 30 do
        tileMap:SetTile(x, 10, T.COBBLESTONE)
        tileMap:SetTile(x, 11, T.COBBLESTONE)
    end
end

function InitUI()
    UI.Init({
        fonts = { { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } } },
        scale = UI.Scale.DEFAULT,
    })

    local brushButtons = {}
    for i = 1, 10 do
        local name = tileMap.TERRAIN_NAMES[i] or ("地形" .. i)
        brushButtons[#brushButtons + 1] = UI.Button {
            id = "brush_" .. i,
            text = i .. "." .. name,
            fontSize = 11,
            paddingLeft = 6, paddingRight = 6, paddingTop = 3, paddingBottom = 3,
            variant = (i == 1) and "primary" or "default",
            onClick = function(self) SetBrush(i) end,
        }
    end

    UI.SetRoot(UI.Panel {
        id = "uiRoot", width = "100%", height = "100%", pointerEvents = "box-none",
        children = {
            UI.Panel {
                position = "absolute", top = 8, left = 8, right = 8,
                flexDirection = "row", flexWrap = "wrap", gap = 4, padding = 8,
                backgroundColor = { 20, 20, 30, 200 }, borderRadius = 8, pointerEvents = "auto",
                children = brushButtons,
            },
            UI.Panel {
                id = "infoPanel", position = "absolute", bottom = 8, left = 8,
                padding = 10, backgroundColor = { 20, 20, 30, 200 }, borderRadius = 8, gap = 4,
                pointerEvents = "none",
                children = {
                    UI.Label { id = "infoLabel", text = "WASD移动 | 鼠标绘制 | G网格 | R重生成", fontSize = 12, fontColor = {200,200,200,255} },
                    UI.Label { id = "brushLabel", text = "画笔: 草地 | 大小: 1", fontSize = 12, fontColor = {100,255,100,255} },
                    UI.Label { id = "posLabel", text = "位置: (0,0)", fontSize = 12, fontColor = {180,180,255,255} },
                },
            },
        }
    })
end

function SetBrush(terrainType)
    currentBrush = terrainType
    local root = UI.GetRoot()
    if root then
        for i = 1, 10 do
            local btn = root:FindById("brush_" .. i)
            if btn then btn:SetVariant(i == terrainType and "primary" or "default") end
        end
        local bl = root:FindById("brushLabel")
        if bl then bl:SetText("画笔: " .. (tileMap.TERRAIN_NAMES[terrainType] or "?") .. " | 大小: " .. brushSize) end
    end
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    local dx, dy = 0, 0
    if input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) then dy = -1 end
    if input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN) then dy = 1 end
    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then dx = -1 end
    if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then dx = 1 end
    if dx ~= 0 or dy ~= 0 then tileMap:MoveCamera(dx * CAMERA_SPEED * dt, dy * CAMERA_SPEED * dt) end

    if isPainting then
        local mx = input.mousePosition.x / dpr
        local my = input.mousePosition.y / dpr
        local tx, ty = tileMap:ScreenToTile(mx, my)
        if brushSize <= 1 then tileMap:SetTile(tx, ty, currentBrush)
        else tileMap:FillCircle(tx, ty, brushSize, currentBrush) end
    end

    local root = UI.GetRoot()
    if root then
        local posLabel = root:FindById("posLabel")
        if posLabel then
            local mx = input.mousePosition.x / dpr
            local my = input.mousePosition.y / dpr
            local tx, ty = tileMap:ScreenToTile(mx, my)
            local t = tileMap:GetTile(tx, ty)
            posLabel:SetText(string.format("瓦片(%d,%d) %s | 相机(%.0f,%.0f)", tx, ty, t and tileMap.TERRAIN_NAMES[t] or "外", tileMap.cameraX, tileMap.cameraY))
        end
    end
end

function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key >= KEY_1 and key <= KEY_9 then SetBrush(key - KEY_1 + 1)
    elseif key == KEY_0 then SetBrush(10) end
    if key == KEY_G then showGrid = not showGrid end
    if key == KEY_R then GenerateWorld() end
    if key == KEY_LEFTBRACKET then brushSize = math.max(1, brushSize - 1); SetBrush(currentBrush) end
    if key == KEY_RIGHTBRACKET then brushSize = math.min(5, brushSize + 1); SetBrush(currentBrush) end
end

function HandleMouseDown(eventType, eventData)
    if eventData["Button"]:GetInt() == MOUSEB_LEFT then isPainting = true end
end

function HandleMouseUp(eventType, eventData)
    if eventData["Button"]:GetInt() == MOUSEB_LEFT then isPainting = false end
end

function HandleNanoVGRender(eventType, eventData)
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    dpr = graphics:GetDPR()
    screenWidth = physW / dpr
    screenHeight = physH / dpr

    nvgBeginFrame(vg, physW, physH, dpr)
    tileMap:Render(screenWidth, screenHeight)
    if showGrid then tileMap:RenderGrid(screenWidth, screenHeight) end

    -- 画笔预览
    local mx = input.mousePosition.x / dpr
    local my = input.mousePosition.y / dpr
    local ts = tileMap.tileSize
    local tx, ty = tileMap:ScreenToTile(mx, my)
    local px = (tx - 1) * ts - tileMap.cameraX
    local py = (ty - 1) * ts - tileMap.cameraY
    nvgBeginPath(vg)
    if brushSize <= 1 then
        nvgRect(vg, px, py, ts, ts)
    else
        nvgCircle(vg, px + ts*0.5, py + ts*0.5, brushSize * ts)
    end
    nvgStrokeColor(vg, nvgRGBA(255, 255, 0, 180))
    nvgStrokeWidth(vg, 2.0)
    nvgStroke(vg)

    nvgEndFrame(vg)
end
