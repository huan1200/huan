-- ============================================================================
-- Game/Player.lua
-- 玩家创建、配色、初始化
-- ============================================================================

local CONFIG = require("Game.Config")
local State = require("Game.State")

local Player = {}

-- 角色配色
Player.COLORS = {
    {160, 160, 160},  -- 灰白(玩家)
    {140, 110, 90},   -- 暗褐
    {120, 125, 130},  -- 冷灰
    {150, 140, 120},  -- 暖灰
    {130, 120, 135},  -- 灰紫
}

--- 创建单个玩家数据
function Player.create(idx, x, y, isLocal)
    return {
        idx = idx,
        x = x,
        y = y,
        vx = 0,
        vy = 0,
        facing = 0,
        poison = 0,
        energy = CONFIG.EnergyMax,
        alive = true,
        isLocal = isLocal,
        isGhost = false,
        attackCooldown = 0,
        attacking = false,
        attackTimer = 0,
        attackState = "idle",
        attackStateTimer = 0,
        flipDir = 1,
        -- AI
        aiTimer = 0,
        aiTargetX = x,
        aiTargetY = y,
        aiWantsAttack = false,
        -- 药剂
        potionState = nil,
        -- 喝药
        drinkingState = "idle",
        drinkingTimer = 0,
        drinkingType = nil,
        -- 奔跑
        sprinting = false,
        -- 交互
        interactState = "idle",
        interactPartner = nil,
        interactTimer = 0,
        interactGiveType = nil,
        interactReceived = nil,
        interactFlyAnim = nil,
        -- 舒适区
        comfortStandTimer = 0,
        usingComfortZone = false,
        isCapturingZone = false,
        comfortClaims = {},
        -- 视觉
        color = {0, 0, 0},
        hitFlash = 0,
        avatarIdx = 1,
        -- 毒满暴走buff
        poisonMaxBuff = false,
        -- 骷髅特效
        poisonSkullTimer = 0,
        lastPoisonTick = 0,
    }
end

--- 初始化所有玩家
function Player.initAll()
    State.players = {}
    local cx, cy, spawnRadius
    if State.editorSpawnConfig then
        cx = State.editorSpawnConfig.cx
        cy = State.editorSpawnConfig.cy
        spawnRadius = State.editorSpawnConfig.radius
    else
        cx = CONFIG.MapSize / 2
        cy = CONFIG.MapSize / 2
        spawnRadius = CONFIG.MapSize * 0.35
    end

    -- 随机打乱角色图片分配(Fisher-Yates shuffle)
    local avatarOrder = {}
    for i = 1, CONFIG.PlayerCount do
        avatarOrder[i] = i
    end
    for i = CONFIG.PlayerCount, 2, -1 do
        local j = math.random(1, i)
        avatarOrder[i], avatarOrder[j] = avatarOrder[j], avatarOrder[i]
    end

    for i = 1, CONFIG.PlayerCount do
        local angle = (i - 1) * (2 * math.pi / CONFIG.PlayerCount) - math.pi / 2
        local px = cx + math.cos(angle) * spawnRadius
        local py = cy + math.sin(angle) * spawnRadius
        local p = Player.create(i, px, py, i == State.localPlayerIdx)
        p.color = Player.COLORS[i]
        p.avatarIdx = avatarOrder[i]
        State.players[i] = p
    end
end

--- 获取存活玩家数量
function Player.getAliveCount()
    local count = 0
    for i = 1, #State.players do
        if State.players[i].alive then count = count + 1 end
    end
    return count
end

--- 生成死亡纸片+污渍效果
function Player.spawnDeathEffect(playerIdx)
    local p = State.players[playerIdx]
    if not p then return end
    local pieceCount = 5 + math.random(0, 3)
    local pColor = p.color
    for j = 1, pieceCount do
        local angle = (j / pieceCount) * math.pi * 2 + (math.random() - 0.5) * 0.5
        local speed = 60 + math.random() * 80
        table.insert(State.deathPieces, {
            x = p.x + (math.random() - 0.5) * 10,
            y = p.y - 20 + (math.random() - 0.5) * 15,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed - 30,
            rot = math.random() * math.pi * 2,
            rotV = (math.random() - 0.5) * 8,
            w = 8 + math.random() * 6,
            h = 6 + math.random() * 5,
            life = 2.0,
            color = {pColor[1], pColor[2], pColor[3]},
        })
    end
    table.insert(State.deathStains, {
        x = p.x,
        y = p.y,
        alpha = 180,
    })
end

return Player
