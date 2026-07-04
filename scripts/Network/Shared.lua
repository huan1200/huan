-- ============================================================================
-- Network/Shared.lua
-- 《道友请留步》多人版 - 共享常量、事件名、CONFIG
-- 服务端和客户端共用
-- ============================================================================

local Shared = {}

-- ============================================================================
-- 游戏配置(60人大逃杀 + 组队)
-- ============================================================================
Shared.CONFIG = {
    Title = "道友请留步",
    -- 地图(60人需要更大地图)
    MapSize = 4096,
    -- 相机
    ViewRadius = 800,
    -- 玩家
    MaxPlayers = 60,
    TeamSize = 3,              -- 每队3人(最多20队)
    PlayerRadius = 20,
    MoveSpeed = 200,
    MoveSpeedMin = 50,
    -- 属性
    PoisonMax = 100,
    PoisonMin = 0,
    EnergyMax = 100,
    EnergyMin = 0,
    -- 能量消耗
    MoveCostRate = 1,
    SprintCostRate = 3,
    SprintSpeedMultiplier = 1.8,
    AttackCostEnergy = 10,
    DrinkCostEnergy = 10,
    InteractCostEnergy = 5,
    -- 能量回复
    EnergyStealOnHit = 35,
    ComfortZoneRegenRate = 50,
    ComfortZoneWaitTime = 3,     -- 占领舒适区需站立不动等待3秒
    ComfortZoneRadius = 75,      -- 舒适区判定半径(px)(缩小为原来的一半)
    ComfortZoneClaimEnergy = 100, -- 每次占领获得的能量配额
    ComfortZoneMinSpawnDist = 300,
    ComfortZoneSeparation = 400,
    -- 攻击
    AttackRange = 120,
    AttackAngle = 60,
    AttackWindup = 0.2,
    AttackRecovery = 0.3,
    AttackCooldown = 0.6,
    AttackPoisonReduce = 15,
    AttackPoisonAdd = 10,
    -- 喝药系统
    DrinkDuration = 1.5,
    DrinkStunDuration = 0.5,
    DrinkInterruptPoisonTransfer = 30,
    GroundPotionPickupRange = 50,
    PoisonDrinkAmount = 100,
    -- 交互系统
    InteractRange = 80,
    InteractDuration = 3.0,
    InteractAcceptTimeout = 2.0,
    -- 回合
    TotalRounds = 20,
    PrepareDuration = 10,
    DayDuration = 60,
    NightfallDuration = 5,
    SettleDuration = 3,
    PoisonPerRound = 30,
    AntidoteRatio = 0.5,
    -- 毒圈
    CircleInitRadiusFactor = 0.8,
    CircleShrinkRatio = 4/5,
    CircleShrinkDuration = 1,
    CirclePoisonRate = 10,
    CircleFogWidth = 50,
    -- AI
    AIUpdateInterval = 0.3,
    -- 组队
    TeamDamageReduction = 0.5,    -- 队友间伤害减半
    TeamHealBonus = 1.5,          -- 队友间给药效果1.5倍
}

-- ============================================================================
-- 远程事件名
-- ============================================================================
Shared.EVENTS = {
    -- 连接握手
    CLIENT_READY = "ClientReady",
    -- 服务器 → 客户端: 游戏状态同步
    GAME_STATE_SYNC = "GameStateSync",         -- 完整游戏状态快照
    PLAYER_STATE_BATCH = "PlayerStateBatch",   -- 批量玩家状态更新
    PHASE_CHANGE = "PhaseChange",              -- 阶段切换
    PLAYER_DIED = "PlayerDied",                -- 玩家死亡
    PLAYER_HIT = "PlayerHit",                  -- 命中通知(播放特效)
    DRINK_EVENT = "DrinkEvent",                -- 喝药事件
    INTERACT_EVENT = "InteractEvent",          -- 交互事件
    CIRCLE_UPDATE = "CircleUpdate",            -- 毒圈更新
    TEAM_INFO = "TeamInfo",                    -- 队伍信息
    ASSIGN_PLAYER = "AssignPlayer",            -- 分配玩家ID
    FLOATING_TEXT = "FloatingText",            -- 浮动文字
    COMFORT_ZONE_SYNC = "ComfortZoneSync",     -- 舒适区同步
    GROUND_POTION_SYNC = "GroundPotionSync",   -- 地面药剂同步
    GAME_OVER = "GameOver",                    -- 游戏结束
    -- 客户端 → 服务器: 玩家操作
    PLAYER_ACTION = "PlayerAction",            -- 玩家特殊操作(喝药/交互等)
}

-- ============================================================================
-- 操作类型(通过 PLAYER_ACTION 事件发送)
-- ============================================================================
Shared.ACTIONS = {
    DRINK = 1,          -- 喝药
    INTERACT = 2,       -- 发起交互
    ACCEPT_INTERACT = 3,-- 接受交互
    GIVE_ITEM = 4,      -- 给予物品
    CANCEL_INTERACT = 5,-- 取消交互
}

-- ============================================================================
-- 输入按钮位定义(controls.buttons)
-- ============================================================================
Shared.BUTTONS = {
    ATTACK = 1,      -- bit 0: 攻击
    SPRINT = 2,      -- bit 1: 奔跑
    DRINK = 4,       -- bit 2: 喝药(脉冲)
    INTERACT = 8,    -- bit 3: 交互(脉冲)
}

-- 脉冲按键掩码(需要可靠传输的一次性按键)
Shared.PULSE_MASK = Shared.BUTTONS.ATTACK | Shared.BUTTONS.DRINK | Shared.BUTTONS.INTERACT

-- ============================================================================
-- 节点变量名
-- ============================================================================
Shared.VARS = {
    PLAYER_ID = "PId",
    TEAM_ID = "TId",
    POISON = "Psn",
    ENERGY = "Eng",
    ALIVE = "Alv",
    POTION_STATE = "Pot",      -- 0=无, 1=解药, 2=毒药, 3=胜利药水
    ATTACK_STATE = "Atk",      -- 0=idle, 1=windup, 2=recovery
    DRINK_STATE = "Drk",       -- 0=idle, 1=drinking, 2=stunned
    INTERACT_STATE = "Int",    -- 0=idle, 1=requesting, 2=pending, 3=interacting, 4=giving
    FACING = "Fac",
    IS_AI = "IsAI",
    SPRINTING = "Spr",
    NICKNAME = "Nick",
}

-- ============================================================================
-- 注册远程事件
-- ============================================================================

-- 服务器需要接收的事件
Shared.SERVER_EVENTS = {
    Shared.EVENTS.CLIENT_READY,
    Shared.EVENTS.PLAYER_ACTION,
}

-- 客户端需要接收的事件
Shared.CLIENT_EVENTS = {
    Shared.EVENTS.GAME_STATE_SYNC,
    Shared.EVENTS.PLAYER_STATE_BATCH,
    Shared.EVENTS.PHASE_CHANGE,
    Shared.EVENTS.PLAYER_DIED,
    Shared.EVENTS.PLAYER_HIT,
    Shared.EVENTS.DRINK_EVENT,
    Shared.EVENTS.INTERACT_EVENT,
    Shared.EVENTS.CIRCLE_UPDATE,
    Shared.EVENTS.TEAM_INFO,
    Shared.EVENTS.ASSIGN_PLAYER,
    Shared.EVENTS.FLOATING_TEXT,
    Shared.EVENTS.COMFORT_ZONE_SYNC,
    Shared.EVENTS.GROUND_POTION_SYNC,
    Shared.EVENTS.GAME_OVER,
}

function Shared.RegisterServerEvents()
    for _, eventName in ipairs(Shared.SERVER_EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
end

function Shared.RegisterClientEvents()
    for _, eventName in ipairs(Shared.CLIENT_EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
end

-- ============================================================================
-- 工具函数
-- ============================================================================

function Shared.dist(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

function Shared.angleBetween(x1, y1, x2, y2)
    return math.atan(y2 - y1, x2 - x1)
end

function Shared.normalizeAngle(a)
    while a > math.pi do a = a - 2 * math.pi end
    while a < -math.pi do a = a + 2 * math.pi end
    return a
end

function Shared.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function Shared.lerp(a, b, t)
    return a + (b - a) * t
end

-- 连接唯一键
function Shared.GetConnectionKey(connection)
    if connection then
        return tostring(connection:GetAddress()) .. ":" .. tostring(connection:GetPort())
    end
    return nil
end

return Shared
