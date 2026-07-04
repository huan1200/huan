-- ============================================================================
-- Game/Config.lua
-- 游戏常量配置表
-- ============================================================================

local CONFIG = {
    Title = "道友请留步",
    -- 地图
    MapSize = 1024,
    -- 相机
    ViewRadius = 800,
    -- 玩家
    PlayerCount = 5,
    PlayerRadius = 20,
    MoveSpeed = 200,         -- 像素/秒
    MoveSpeedMin = 50,       -- 能量耗尽时
    -- 属性
    PoisonMax = 100,
    PoisonMin = 0,
    EnergyMax = 100,
    EnergyMin = 0,
    -- 6.1 能量消耗
    MoveCostRate = 1,            -- 正常移动消耗: 1/秒
    SprintCostRate = 3,          -- 奔跑消耗: 3/秒
    SprintSpeedMultiplier = 1.8, -- 奔跑速度倍率(200*1.8=360)
    AttackCostEnergy = 5,        -- 攻击消耗能量
    DrinkCostEnergy = 10,        -- 喝药消耗能量(6.1)
    InteractCostEnergy = 5,      -- 交互消耗能量(6.1)
    -- 6.3 能量回复
    EnergyStealOnHit = 10,       -- 命中掠夺能量(从对方扣除)
    ComfortZoneRegenRate = 50,   -- 舒适区占领后回复速率: 50/秒
    ComfortZoneWaitTime = 3,     -- 需站立不动等待3秒才能占领成功
    ComfortZoneRadius = 75,      -- 舒适区判定半径(px) - 缩小为原来的一半
    ComfortZoneClaimEnergy = 100, -- 每次占领获得的能量配额
    ComfortZoneMinSpawnDist = 200, -- 距任何玩家出生点最小距离
    ComfortZoneSeparation = 250,   -- 多个舒适区之间最小距离(确保分散)
    -- 攻击(4.3)
    AttackRange = 120,       -- 像素(扇形半径)
    AttackAngle = 60,        -- 度(扇形角度)
    AttackWindup = 0.2,      -- 前摇(举臂)
    AttackRecovery = 0.3,    -- 后摇(收臂, 无法移动)
    AttackCooldown = 0.6,    -- 总冷却(前摇+后摇+余量)
    AttackPoisonReduce = 15, -- 命中自身减毒
    AttackPoisonAdd = 10,    -- 命中目标加毒
    AttackEnergyGain = 35,   -- [废弃,保留兼容] 改用EnergyStealOnHit
    PoisonDrinkAmount = 100, -- 误饮毒药增加量(直接满)
    -- 5.2 喝药系统
    DrinkDuration = 1.5,     -- 喝药读条时间(秒)
    DrinkStunDuration = 0.5, -- 被打断后硬直时间(秒)
    DrinkInterruptPoisonTransfer = 30, -- 5.5 毒药转移给攻击者的毒量
    GroundPotionPickupRange = 50,      -- 地面药剂拾取距离(像素)
    -- 8.1 交互系统
    InteractRange = 80,          -- 交互触发距离(像素)
    InteractDuration = 3.0,      -- 交互状态持续时间(秒)
    InteractAcceptTimeout = 2.0, -- 接受超时(秒, 默认接受)
    -- 回合(3.3 核心参数)
    TotalRounds = 5,             -- 总天数(5天)
    PrepareDuration = 10,        -- 准备阶段(仅开局一次)
    DayDuration = 60,            -- 白天阶段(主要战斗时间)
    NightfallDuration = 5,       -- 黑夜降临(黑屏+5秒倒计时)
    NightDuration = 0,           -- [废弃] 黑夜进行阶段已合并到nightfall
    SettleDuration = 3,          -- 黑夜结算(淘汰页面展示)
    PoisonPerRound = 30,         -- 每轮黑夜降临加毒
    AntidoteRatio = 0.5,         -- 黑夜降临时获得解药的存活玩家比例
    -- 9.1 毒圈
    CircleInitRadiusFactor = 0.8,  -- 初始半径=地图对角线*0.8(约2300px)
    CircleShrinkRatio = 3/5,       -- 每轮收缩至当前3/5(缩小2/5)
    CircleShrinkDuration = 1,      -- shrinking过渡阶段1秒(实际缩圈在day阶段60秒内完成)
    CirclePoisonRate = 10,         -- 9.2 毒圈外加毒速度: 10/秒
    CircleFogWidth = 50,           -- 9.3 雾霭带宽度(像素)
    -- AI
    AIUpdateInterval = 0.3,  -- AI决策间隔
    -- 动画帧率
    JESTER_WALK_FPS = 12,
    JESTER_IDLE_FPS = 8,
    JESTER_RUN_FPS = 14,
    JESTER_DRINK_FPS = 10,
    JESTER_ATTACK_FPS = 16,
    JESTER_HURT_FPS = 16,
    WARRIOR_WALK_FPS = 10,
    WARRIOR_IDLE_FPS = 6,
    SCIENTIST_WALK_FPS = 10,
    MINER_WALK_FPS = 12,
    MINER_ATTACK_FPS = 16,
    MINER_IDLE_FPS = 8,
    THIEF_WALK_FPS = 10,
}

return CONFIG
