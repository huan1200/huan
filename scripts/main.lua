-- ============================================================================
-- 《道友请留步》
-- 2.5D 俯视角生存对战游戏 MVP
-- 玩法: 6人开局中毒, 攻击他人解毒, 每轮淘汰中毒者, 最后1人存活胜利
-- ============================================================================

require "LuaScripts/Utilities/Sample"
local UI = require("urhox-libs/UI")
local IDEMain = require("IDE.IDEMain")
local State = require("Game.State")
local Render = require("Game.Render")

-- ============================================================================
-- 全局常量
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
}

-- ============================================================================
-- 游戏状态
-- ============================================================================
local nvgContext = nil
local fontId = -1

-- 游戏阶段: "menu", "prepare", "day", "settle", "shrinking", "victory", "defeat"
local gamePhase = "menu"
local currentRound = 0
local phaseTimer = 0        -- 当前阶段计时器
local eliminatedIdx = -1    -- 本轮被淘汰的玩家索引
local settleDeaths = {}     -- 结算阶段死亡的玩家索引列表
local settleSubPhase = "countdown"  -- "countdown"(5s黑屏倒计时) / "elimination"(3s淘汰展示)
local countdownLastSecond = -1      -- 倒计时音效追踪(每秒播放一次)
local backToMenuBtnRect = { x = 0, y = 0, w = 0, h = 0 }  -- 返回主页按钮点击区域
local isFirstRound = true   -- 是否第一轮(准备阶段标记)
local victoryWinnerIdx = nil -- 胜利玩家索引(最后存活者)
local victoryPotionGiven = false -- 是否已发放胜利药水

-- 状态特效
local statusEffects = {}    -- {playerIdx, type="poison"/"detox", timer}

-- 物品获取光效(2.5 UI)
local pickupGlows = {}      -- {playerIdx, type="antidote"/"poison", timer, maxTimer}

-- 9.1 毒圈(初始半径=地图对角线*80%≈2300px, 中心=地图几何中心)
local circleInitRadius = math.sqrt(CONFIG.MapSize * CONFIG.MapSize * 2) * CONFIG.CircleInitRadiusFactor
local circle = {
    cx = CONFIG.MapSize / 2,   -- 中心点: 1024
    cy = CONFIG.MapSize / 2,   -- 中心点: 1024
    radius = circleInitRadius,
    targetRadius = circleInitRadius,
    shrinkSpeed = 0,           -- 当前收缩速度(每次缩圈时计算)
}

-- 相机
local camera = {
    x = CONFIG.MapSize / 2,
    y = CONFIG.MapSize / 2,
}

-- 玩家数组
local players = {}
-- 玩家索引(自己)
local localPlayerIdx = 1

-- 背包系统
local inventoryOpen = false
-- 物品: nil, "poison", "antidote"
-- 每个玩家有一个背包格

-- 粒子效果
local particles = {}

-- 死亡纸片碎裂效果
local deathPieces = {}   -- {x, y, vx, vy, rot, rotV, w, h, life, color}
local deathStains = {}   -- {x, y, alpha} 死亡黑色污渍

-- 舒适区(圈内安全点, 有篝火/清泉/圣坛)
local comfortZones = {}  -- {x, y, type="campfire"/"spring"/"altar", playersInside={}}
-- 舒适区浮动数字
local comfortFloats = {}  -- {x, y, text, life, maxLife, color}

-- UI引用
local uiRoot_ = nil

-- 攻击动画
local attackEffects = {}

-- 浮动文字(4.3 命中反馈)
local floatingTexts = {}  -- {x, y, text, color={r,g,b}, timer, maxTimer}

-- 5.3 地面药剂(掉落的解药/毒药)
local groundPotions = {}  -- {x, y, type="antidote"/"poison", timer}

-- 屏幕震动(4.3 命中反馈)
local screenShake = { timer = 0, intensity = 0 }

-- ============================================================================
-- 辅助函数
-- ============================================================================

local function dist(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

local function angleBetween(x1, y1, x2, y2)
    return math.atan(y2 - y1, x2 - x1)
end

local function normalizeAngle(a)
    while a > math.pi do a = a - 2 * math.pi end
    while a < -math.pi do a = a + 2 * math.pi end
    return a
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- ============================================================================
-- 10.2 音效系统
-- ============================================================================
local sfxNode = nil  -- 音效播放节点(在Start中初始化)
local sfxCache = {}  -- 缓存已加载的Sound资源
local bgmSource = nil  -- 背景音乐播放源
local bgmPlaylist = {   -- 背景音乐播放列表
    "audio/游戏音乐/疯猪追月.ogg",
    "audio/游戏音乐/倒计时乱跑.ogg",
    "audio/游戏音乐/毒圈童话.ogg",
}
local bgmCurrentIdx = 0  -- 当前播放索引

local function playSound(name, gain, panning)
    if not sfxNode then return end
    local path = "audio/sfx/" .. name .. ".ogg"
    local sound = sfxCache[path]
    if not sound then
        sound = cache:GetResource("Sound", path)
        if not sound then return end
        sfxCache[path] = sound
    end
    local source = sfxNode:CreateComponent("SoundSource")
    source:SetSoundType("Effect")
    source:SetAutoRemoveMode(REMOVE_COMPONENT)
    source:SetGain(gain or 0.6)
    if panning then source:SetPanning(panning) end
    source:Play(sound)
end

-- 播放背景音乐指定曲目(最后一首循环)
local function playBgmTrack(idx)
    if not bgmSource then return end
    if idx < 1 or idx > #bgmPlaylist then return end
    bgmCurrentIdx = idx
    local path = bgmPlaylist[idx]
    local sound = cache:GetResource("Sound", path)
    if sound then
        -- 最后一首循环播放,其余播放一次
        sound.looped = (idx == #bgmPlaylist)
        bgmSource:Play(sound)
        print("[BGM] 播放第" .. idx .. "首: " .. path .. (sound.looped and " (循环)" or ""))
    else
        print("[BGM] WARNING: 无法加载: " .. path)
    end
end

-- 检测当前曲目播完并切换下一首
local function updateBgm()
    if not bgmSource then return end
    if not bgmSource:IsPlaying() then
        if bgmCurrentIdx == 0 then
            -- 特殊曲目(黑夜倒计时)播完,恢复播放列表第1首
            playBgmTrack(1)
        elseif bgmCurrentIdx < #bgmPlaylist then
            -- 播放列表中下一首
            playBgmTrack(bgmCurrentIdx + 1)
        end
    end
end

-- 毒值警告音cooldown(避免频繁播放)
local poisonWarnCooldown = 0

-- ============================================================================
-- 玩家初始化
-- ============================================================================

local function createPlayer(idx, x, y, isLocal)
    return {
        idx = idx,
        x = x,
        y = y,
        vx = 0,
        vy = 0,
        facing = 0,  -- 朝向角度(弧度)
        poison = 0,
        energy = CONFIG.EnergyMax,
        alive = true,
        isLocal = isLocal,
        isGhost = false,  -- 死亡后变为鬼魂
        attackCooldown = 0,
        attacking = false,
        attackTimer = 0,
        attackState = "idle",    -- "idle"/"windup"/"recovery"
        attackStateTimer = 0,
        flipDir = 1,  -- 角色朝向翻转: 1=朝右, -1=朝左
        -- AI
        aiTimer = 0,
        aiTargetX = x,
        aiTargetY = y,
        aiWantsAttack = false,
        -- 5.1 药剂状态(不占道具栏, 以状态存在)
        potionState = nil,  -- nil / "antidote" / "poison"
        -- 5.2 喝药状态
        drinkingState = "idle",  -- "idle" / "drinking" / "stunned"
        drinkingTimer = 0,
        drinkingType = nil,      -- "antidote" / "poison" (正在喝什么)
        -- 6.1 奔跑(Shift键)
        sprinting = false,
        -- 8.1 交互
        interactState = "idle",   -- "idle"/"requesting"/"pending"/"interacting"/"giving"
        interactPartner = nil,    -- 交互对象idx
        interactTimer = 0,        -- 交互计时器
        interactGiveType = nil,   -- 正在给予的物品类型: "antidote"/"poison"
        interactReceived = nil,   -- 收到的物品: "antidote"/"poison"
        interactFlyAnim = nil,    -- 抛物线动画 {t, duration, fromX, fromY, toX, toY, type}
        -- 舒适区(站点占领机制)
        comfortStandTimer = 0,  -- 在舒适区站立不动的累计时间
        usingComfortZone = false, -- 是否正在使用舒适区(已占领,恢复中)
        isCapturingZone = false,  -- 是否正在占领中(等待3秒)
        comfortClaims = {},  -- {[zoneIdx]={claimed=bool, claimTimer=n, energyLeft=n}} 每个玩家对每个舒适区的占领状态
        -- 视觉
        color = {0, 0, 0},
        hitFlash = 0,
        avatarIdx = 1,  -- 猪角色图片索引(1-5, initPlayers中随机分配)
        -- 毒满暴走buff: 毒素达到100时激活, 毒素归零时解除
        poisonMaxBuff = false,  -- 是否处于暴走状态(毒素转移翻倍+吸取能量翻倍)
        -- 10.3 中毒加深骷髅
        poisonSkullTimer = 0,
        lastPoisonTick = 0,  -- 上次触发骷髅时的毒值(每+10触发)
    }
end

-- 角色配色: 主体灰白/暗褐, 无鲜艳颜色, 靠光效区分状态
local PLAYER_COLORS = {
    {160, 160, 160},  -- 灰白(玩家)
    {140, 110, 90},   -- 暗褐
    {120, 125, 130},  -- 冷灰
    {150, 140, 120},  -- 暖灰
    {130, 120, 135},  -- 灰紫
}

-- 猪角色图片路径(5个角色)
local PIG_IMAGE_PATHS = {
    "image/Image 16.png",        -- 小丑猪
    "image/pig_warrior.png",     -- 战士猪
    "image/pig_scientist.png",   -- 科学家猪
    "image/pig_miner.png",       -- 矿工猪
    "image/pig_thief.png",       -- 盗贼猪
}
local pigImages = {}  -- nvgCreateImage 返回的句柄数组

-- 小丑猪(avatarIdx=1)走路动画帧路径(16帧循环)
local JESTER_WALK_FRAME_PATHS = {}
for i = 1, 16 do
    JESTER_WALK_FRAME_PATHS[i] = string.format("image/jester_pig_anim/walk/walk_%02d.png", i)
end
local jesterWalkFrames = {}  -- nvgCreateImage 句柄数组(16帧)
local JESTER_WALK_FPS = 12   -- 走路动画帧率

-- 小丑猪(avatarIdx=1)待机动画帧路径(6帧循环)
local JESTER_IDLE_FRAME_PATHS = {}
for i = 1, 6 do
    JESTER_IDLE_FRAME_PATHS[i] = string.format("image/jester_pig_anim/idle/idle_%02d.png", i)
end
local jesterIdleFrames = {}  -- nvgCreateImage 句柄数组(6帧)
local JESTER_IDLE_FPS = 8    -- 待机动画帧率

-- 小丑猪(avatarIdx=1)奔跑动画帧路径(8帧循环)
local JESTER_RUN_FRAME_PATHS = {}
for i = 1, 8 do
    JESTER_RUN_FRAME_PATHS[i] = string.format("image/jester_pig_anim/run/run_%02d.png", i)
end
local jesterRunFrames = {}   -- nvgCreateImage 句柄数组(8帧)
local JESTER_RUN_FPS = 14    -- 奔跑动画帧率(比走路快)

-- 小丑猪(avatarIdx=1)喝药动画帧路径(16帧循环)
local JESTER_DRINK_FRAME_PATHS = {}
for i = 1, 16 do
    JESTER_DRINK_FRAME_PATHS[i] = string.format("image/jester_pig_anim/drink/drink_%02d.png", i)
end
local jesterDrinkFrames = {} -- nvgCreateImage 句柄数组(16帧)
local JESTER_DRINK_FPS = 10  -- 喝药动画帧率

-- 小丑猪(avatarIdx=1)打击动画帧路径(8帧)
local JESTER_ATTACK_FRAME_PATHS = {}
for i = 1, 8 do
    JESTER_ATTACK_FRAME_PATHS[i] = string.format("image/jester_pig_anim/attack/attack_%02d.png", i)
end
local jesterAttackFrames = {} -- nvgCreateImage 句柄数组(8帧)
local JESTER_ATTACK_FPS = 16  -- 打击动画帧率(快速播放)

-- 小丑猪(avatarIdx=1)受击动画帧路径(8帧)
local JESTER_HURT_FRAME_PATHS = {}
for i = 1, 8 do
    JESTER_HURT_FRAME_PATHS[i] = string.format("image/jester_pig_anim/hurt/hurt_%02d.png", i)
end
local jesterHurtFrames = {} -- nvgCreateImage 句柄数组(8帧)
local JESTER_HURT_FPS = 16  -- 受击动画帧率(快速播放)
-- 战士猪(avatarIdx=2)走路动画帧路径(8帧循环)
local WARRIOR_WALK_FRAME_PATHS = {}
for i = 1, 8 do
    WARRIOR_WALK_FRAME_PATHS[i] = string.format("image/warrior_pig_anim/walk/walk_%02d.png", i)
end
local warriorWalkFrames = {}  -- nvgCreateImage 句柄数组(8帧)
local WARRIOR_WALK_FPS = 10   -- 走路动画帧率

-- 战士猪(avatarIdx=2)待机动画帧路径(4帧循环)
local WARRIOR_IDLE_FRAME_PATHS = {}
for i = 1, 4 do
    WARRIOR_IDLE_FRAME_PATHS[i] = string.format("image/warrior_pig_anim/idle/idle_%02d.png", i)
end
local warriorIdleFrames = {}  -- nvgCreateImage 句柄数组(4帧)
local WARRIOR_IDLE_FPS = 6    -- 待机动画帧率(较慢，悠闲感)

-- 科学家猪(avatarIdx=3)走路动画帧路径(8帧循环)
local SCIENTIST_WALK_FRAME_PATHS = {}
for i = 1, 8 do
    SCIENTIST_WALK_FRAME_PATHS[i] = string.format("image/scientist_pig_anim/walk/walk_%02d.png", i)
end
local scientistWalkFrames = {}  -- nvgCreateImage 句柄数组(8帧)
local SCIENTIST_WALK_FPS = 10   -- 走路动画帧率

-- 矿工猪(avatarIdx=4)走路动画帧路径(16帧循环)
local MINER_WALK_FRAME_PATHS = {}
for i = 1, 16 do
    MINER_WALK_FRAME_PATHS[i] = string.format("image/miner_pig_anim/walk/walk_%02d.png", i)
end
local minerWalkFrames = {}   -- nvgCreateImage 句柄数组(16帧)
local MINER_WALK_FPS = 12    -- 走路动画帧率

-- 矿工猪(avatarIdx=4)打击动画帧路径(8帧)
local MINER_ATTACK_FRAME_PATHS = {}
for i = 1, 8 do
    MINER_ATTACK_FRAME_PATHS[i] = string.format("image/miner_pig_anim/attack/attack_%02d.png", i)
end
local minerAttackFrames = {} -- nvgCreateImage 句柄数组(8帧)
local MINER_ATTACK_FPS = 16  -- 打击动画帧率(快速播放)

-- 矿工猪(avatarIdx=4)待机动画帧路径(8帧循环)
local MINER_IDLE_FRAME_PATHS = {}
for i = 1, 8 do
    MINER_IDLE_FRAME_PATHS[i] = string.format("image/miner_pig_anim/idle/idle_%02d.png", i)
end
local minerIdleFrames = {}   -- nvgCreateImage 句柄数组(8帧)
local MINER_IDLE_FPS = 8     -- 待机动画帧率(较慢,呼吸感)

-- 盗贼猪(avatarIdx=5)走路动画帧路径(8帧循环)
local THIEF_WALK_FRAME_PATHS = {}
for i = 1, 8 do
    THIEF_WALK_FRAME_PATHS[i] = string.format("image/thief_pig_anim/walk/walk_%02d.png", i)
end
local thiefWalkFrames = {}   -- nvgCreateImage 句柄数组(8帧)
local THIEF_WALK_FPS = 10    -- 走路动画帧率

local GHOST_IMAGE_PATH = "image/Image 17.png"
local CURSOR_IMAGE_PATH = "image/ui/鼠标.png"
local cursorImage = nil  -- 自定义鼠标光标NVG句柄
local ghostImage = nil  -- 鬼魂图片句柄
local potionNvgImages = {}  -- {victory=handle, antidote=handle, poison=handle}
local POTION_IMAGE_PATHS = {
    victory = "image/游戏道具/胜利药水.png",
    antidote = "image/游戏道具/解药.png",
    poison = "image/游戏道具/毒药.png",
}

-- 环境装饰素材图片(饥荒风手绘) - 14种物件贴图
local OBJ_ASSET_PATHS = {
    -- 树木 (2种)
    { type = "tree", variant = 1, path = "image/资产绿植/xs1.png" },
    { type = "tree", variant = 2, path = "image/资产绿植/xs2.png" },
    -- 岩石 (5种)
    { type = "rock", variant = 1, path = "image/资产绿植/s2.png" },
    { type = "rock", variant = 2, path = "image/资产绿植/s3.png" },
    { type = "rock", variant = 3, path = "image/资产绿植/s4.png" },
    { type = "rock", variant = 4, path = "image/资产绿植/s5.png" },
    { type = "rock", variant = 5, path = "image/资产绿植/s6.png" },
    -- 花朵 (4种)
    { type = "flower", variant = 1, path = "image/资产绿植/h1.png" },
    { type = "flower", variant = 2, path = "image/资产绿植/h2.png" },
    { type = "flower", variant = 3, path = "image/资产绿植/h3.png" },
    { type = "flower", variant = 4, path = "image/资产绿植/h4.png" },
    -- 植物 (3种)
    { type = "plant", variant = 1, path = "image/资产绿植/1.png" },
    { type = "plant", variant = 2, path = "image/资产绿植/2.png" },
    { type = "plant", variant = 3, path = "image/资产绿植/3.png" },
}
-- 物件贴图句柄表: objAssetImages[type][variant] = nvgImageHandle
local objAssetImages = {}

-- 关卡编辑器
local LevelEditor = require("TileMap.LevelEditor")
---@type table|nil
local levelEditor = nil  -- 在 Start() 中初始化
local editorSpawnConfig = nil  -- 编辑器出生点配置(应用后生效)

-- 地形贴图(饥荒风格)
local TERRAIN_PATHS = {
    -- 基础地形
    grass       = "image/地皮/terrain_grass_20260530170030.png",
    swamp       = "image/地皮/terrain_swamp_20260530165947.png",
    mud         = "image/地皮/terrain_mud_20260530165944.png",
    rocky       = "image/地皮/terrain_rocky_20260530165943.png",
    volcanic    = "image/地皮/terrain_volcanic_20260530165940.png",
    dead_grass  = "image/地皮/terrain_dead_grass_20260530170619.png",
    forest      = "image/地皮/terrain_forest_floor_20260530170620.png",
    sand        = "image/地皮/terrain_sand_20260530170620.png",
    snow        = "image/地皮/terrain_snow_20260530170624.png",
    cobblestone = "image/地皮/terrain_cobblestone_20260530170621.png",
    -- 过渡贴图(左右)
    grass_sand_lr      = "image/地皮/terrain_grass_sand_lr_20260530170624.png",
    grass_deadgrass_lr = "image/地皮/terrain_grass_deadgrass_lr_20260530170623.png",
    grass_rocky_lr     = "image/地皮/terrain_grass_rocky_lr_20260530170407.png",
    grass_swamp_lr     = "image/地皮/terrain_grass_swamp_lr_20260530170402.png",
    mud_rocky_lr       = "image/地皮/terrain_mud_rocky_lr_20260530170405.png",
    mud_swamp_lr       = "image/地皮/terrain_mud_swamp_lr_20260530170404.png",
    -- 过渡贴图(上下)
    grass_snow_tb      = "image/地皮/terrain_grass_snow_tb_20260530170622.png",
    grass_rocky_tb     = "image/地皮/terrain_grass_rocky_tb_20260530170412.png",
    grass_mud_tb       = "image/地皮/terrain_grass_mud_tb_20260530170406.png",
    mud_swamp_tb       = "image/地皮/terrain_mud_swamp_tb_20260530170405.png",
    rocky_volcanic_tb  = "image/地皮/terrain_rocky_volcanic_tb_20260530170414.png",
    -- 角落贴图
    corner_grass_in_mud_bl      = "image/地皮/terrain_corner_grass_in_mud_bl_20260530170523.png",
    corner_grass_in_mud_br      = "image/地皮/terrain_corner_grass_in_mud_br_20260530170508.png",
    corner_grass_in_mud_tl      = "image/地皮/terrain_corner_grass_in_mud_tl_20260530170508.png",
    corner_grass_in_mud_tr      = "image/地皮/terrain_corner_grass_in_mud_tr_20260530170512.png",
    corner_grass_in_swamp_tl    = "image/地皮/terrain_corner_grass_in_swamp_tl_20260530170508.png",
    corner_grass_in_swamp_tr    = "image/地皮/terrain_corner_grass_in_swamp_tr_20260530170508.png",
    corner_rocky_in_volcanic_tl = "image/地皮/terrain_corner_rocky_in_volcanic_tl_20260530170512.png",
    corner_rocky_in_volcanic_tr = "image/地皮/terrain_corner_rocky_in_volcanic_tr_20260530170512.png",
    -- 混合/渐变贴图
    grass_to_mud       = "image/地皮/terrain_grass_to_mud_20260530165951.png",
    grass_to_swamp     = "image/地皮/terrain_grass_to_swamp_20260530165942.png",
    rocky_to_volcanic  = "image/地皮/terrain_rocky_to_volcanic_20260530165943.png",
}
local terrainImages = {}  -- { name = nvgImageHandle }

local function initPlayers()
    players = {}
    -- 编辑器出生点配置优先
    local cx, cy, spawnRadius
    if editorSpawnConfig then
        cx = editorSpawnConfig.cx
        cy = editorSpawnConfig.cy
        spawnRadius = editorSpawnConfig.radius
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
        local p = createPlayer(i, px, py, i == localPlayerIdx)
        p.color = PLAYER_COLORS[i]
        p.avatarIdx = avatarOrder[i]  -- 随机分配猪角色图片
        players[i] = p
    end
end

-- ============================================================================
-- 游戏逻辑
-- ============================================================================

local function getAliveCount()
    local count = 0
    for i = 1, #players do
        if players[i].alive then count = count + 1 end
    end
    return count
end

-- 辅助: 生成死亡纸片+污渍效果
local function spawnDeathEffect(playerIdx)
    local p = players[playerIdx]
    if not p then return end
    local pieceCount = 5 + math.random(0, 3)
    local pColor = p.color
    for j = 1, pieceCount do
        local angle = (j / pieceCount) * math.pi * 2 + (math.random() - 0.5) * 0.5
        local speed = 60 + math.random() * 80
        table.insert(deathPieces, {
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
    table.insert(deathStains, {
        x = p.x,
        y = p.y,
        alpha = 180,
    })
end

-- 3.1 准备阶段(仅开局一次, 10s, 只能移动)
local function enterPrepare()
    gamePhase = "prepare"
    phaseTimer = CONFIG.PrepareDuration
    isFirstRound = true
    currentRound = 0
    print("=== 准备阶段! 黑夜即将降临... " .. CONFIG.PrepareDuration .. "s ===")
end

-- 白天阶段(60s, 主要战斗时间)
local function enterDay()
    gamePhase = "day"
    phaseTimer = CONFIG.DayDuration

    -- 胜利药水已发放时不进入新一轮(等待玩家喝药)
    if victoryPotionGiven then
        print("=== 胜利药水阶段, 等待喝下... ===")
        phaseTimer = 30
        return
    end

    currentRound = currentRound + 1
    if currentRound > CONFIG.TotalRounds then
        local aliveCount = getAliveCount()
        if aliveCount > 0 and not victoryPotionGiven then
            -- 最大轮数到达, 给所有存活者中最后一人发胜利药水
            for i = 1, #players do
                if players[i].alive then
                    victoryWinnerIdx = i
                    players[i].potionState = "victory"
                    players[i].poison = 0
                    victoryPotionGiven = true
                    table.insert(statusEffects, { playerIdx = i, type = "detox", timer = 3.0 })
                    print("=== 最终轮! 玩家 " .. i .. " 获得胜利药水! ===")
                    break
                end
            end
            phaseTimer = 30
        elseif aliveCount == 0 then
            gamePhase = "defeat"
        end
        return
    end

    -- 每轮白天开始: 全员+30毒, 旧解药变毒, 50%发解药
    -- 5.4 旧解药变毒药 + 固定+30毒
    for i = 1, #players do
        if players[i].alive then
            if players[i].potionState == "antidote" then
                players[i].potionState = "poison"
                players[i].poison = clamp(players[i].poison + CONFIG.PoisonPerRound, CONFIG.PoisonMin, CONFIG.PoisonMax)
                print("玩家 " .. i .. " 解药变为毒药! +30毒")
                if players[i].isLocal then playSound("sfx_antidote_to_poison", 0.7) end
                table.insert(statusEffects, { playerIdx = i, type = "transform", timer = 1.5 })
                table.insert(floatingTexts, {
                    x = players[i].x, y = players[i].y - 30,
                    text = "+30毒(变质)", color = {180, 60, 200},
                    timer = 1.2, maxTimer = 1.2,
                })
            end
            players[i].poison = clamp(players[i].poison + CONFIG.PoisonPerRound, CONFIG.PoisonMin, CONFIG.PoisonMax)
            players[i].drinkingState = "idle"
            players[i].drinkingTimer = 0
            players[i].drinkingType = nil
        end
    end

    -- 5.4 地面未拾取的解药变为地面毒药
    for i = 1, #groundPotions do
        if groundPotions[i].type == "antidote" then
            groundPotions[i].type = "poison"
            print("地面解药变为毒药!")
        end
    end

    -- 5.1 50%存活玩家获得解药(向上取整)
    local aliveList = {}
    for i = 1, #players do
        if players[i].alive then table.insert(aliveList, i) end
    end
    for i = #aliveList, 2, -1 do
        local j = math.random(1, i)
        aliveList[i], aliveList[j] = aliveList[j], aliveList[i]
    end
    local giveCount = math.ceil(#aliveList * CONFIG.AntidoteRatio)
    for k = 1, giveCount do
        local idx = aliveList[k]
        players[idx].potionState = "antidote"
        table.insert(pickupGlows, { playerIdx = idx, type = "antidote", timer = 1.5, maxTimer = 1.5 })
        if players[idx].isLocal then playSound("sfx_antidote_get", 0.7) end
        print("玩家 " .. idx .. " 获得解药!")
    end

    -- 清除本轮地面药剂
    groundPotions = {}

    print("=== 第 " .. currentRound .. " 轮 白天开始! 全员+30毒, " .. giveCount .. "人获得解药, " .. CONFIG.DayDuration .. "s 战斗 ===")
end

-- 3.2/3.3 已废弃: nightfall阶段已合并到enterSettle()的countdown子阶段

-- 3.4 黑夜结算(先5s黑屏倒计时, 再3s淘汰展示)
local function enterSettle()
    gamePhase = "settle"
    settleSubPhase = "countdown"
    phaseTimer = CONFIG.NightfallDuration  -- 5s倒计时
    countdownLastSecond = -1  -- 重置倒计时音效追踪
    settleDeaths = {}
    isFirstRound = false

    -- 强制停止所有玩家
    for i = 1, #players do
        players[i].vx = 0
        players[i].vy = 0
    end

    playSound("sfx_night_transition", 0.9)  -- 画面切换音效
    playSound("sfx_nightfall", 0.8)

    -- 黑夜倒计时专属音乐
    if bgmSource then
        local nightBgm = cache:GetResource("Sound", "audio/游戏音乐/黑夜倒计时.ogg")
        if nightBgm then
            nightBgm.looped = false
            bgmSource:Play(nightBgm)
            bgmCurrentIdx = 0  -- 标记为特殊曲目,播完后恢复播放列表
        end
    end

    print("=== 黑夜降临! " .. CONFIG.NightfallDuration .. "s 黑屏倒计时 ===")
end

-- 倒计时结束后执行淘汰逻辑
local function enterSettleElimination()
    settleSubPhase = "elimination"
    phaseTimer = CONFIG.SettleDuration  -- 3s淘汰展示

    playSound("sfx_settle_kill", 0.7)

    -- 淘汰毒素最高的玩家（仅淘汰一人）
    local maxPoison = 0
    local maxIdx = nil
    for i = 1, #players do
        if players[i].alive and players[i].poison > maxPoison then
            maxPoison = players[i].poison
            maxIdx = i
        end
    end
    if maxIdx then
        players[maxIdx].alive = false
        players[maxIdx].isGhost = true
        players[maxIdx].vx = 0
        players[maxIdx].vy = 0
        table.insert(settleDeaths, maxIdx)
        spawnDeathEffect(maxIdx)
        print("玩家 " .. maxIdx .. " 毒素最高(" .. math.floor(players[maxIdx].poison) .. "), 被淘汰!")
    end

    -- 存活者提示"存活"
    if #settleDeaths > 0 then
        for i = 1, #players do
            if players[i].alive then
                table.insert(statusEffects, { playerIdx = i, type = "detox", timer = 2.0 })
            end
        end
    end

    -- 检查胜利/失败条件
    local aliveCount = getAliveCount()
    if aliveCount == 0 then
        -- 全员死亡 → 失败
        gamePhase = "defeat"
        print("=== 全员阵亡! 游戏失败! ===")
        return
    elseif aliveCount == 1 and not victoryPotionGiven then
        -- 最后1人存活 → 发放胜利药水
        for i = 1, #players do
            if players[i].alive then
                victoryWinnerIdx = i
                players[i].potionState = "victory"
                players[i].poison = 0  -- 清除毒素
                victoryPotionGiven = true
                table.insert(statusEffects, { playerIdx = i, type = "detox", timer = 3.0 })
                print("=== 玩家 " .. i .. " 获得胜利药水! ===")
                break
            end
        end
    end

    print("=== 黑夜结算! " .. #settleDeaths .. "人死亡, " .. aliveCount .. "人存活 ===")
end

-- 7.1 舒适区生成(距离约束: 300px离玩家出生点, 400px彼此分离)
local function generateComfortZones(cx, cy, safeRadius, count)
    local zoneTypes = {"campfire", "spring", "altar"}
    local zoneCount = count or 5  -- 默认5个(剩余天数=生成数量)
    local maxAttempts = 50

    for i = 1, zoneCount do
        local placed = false
        for attempt = 1, maxAttempts do
            local angle = math.random() * math.pi * 2
            local r = math.random() * (safeRadius - CONFIG.ComfortZoneRadius) * 0.8
            local zx = cx + math.cos(angle) * r
            local zy = cy + math.sin(angle) * r

            -- 约束1: 距离所有玩家出生点>=300px
            local tooCloseToSpawn = false
            for _, p in ipairs(players) do
                if not p.isGhost then
                    local spawnCX = CONFIG.MapSize / 2
                    local spawnCY = CONFIG.MapSize / 2
                    local spawnR = CONFIG.MapSize * 0.35
                    local spawnAngle = (p.idx - 1) * (2 * math.pi / CONFIG.PlayerCount) - math.pi / 2
                    local spX = spawnCX + math.cos(spawnAngle) * spawnR
                    local spY = spawnCY + math.sin(spawnAngle) * spawnR
                    if dist(zx, zy, spX, spY) < CONFIG.ComfortZoneMinSpawnDist then
                        tooCloseToSpawn = true
                        break
                    end
                end
            end
            if tooCloseToSpawn then goto continue end

            -- 约束2: 距离已生成的舒适区>=400px
            local tooCloseToOther = false
            for _, existing in ipairs(comfortZones) do
                if dist(zx, zy, existing.x, existing.y) < CONFIG.ComfortZoneSeparation then
                    tooCloseToOther = true
                    break
                end
            end
            if tooCloseToOther then goto continue end

            -- 约束3: 在安全区内
            if dist(zx, zy, cx, cy) > safeRadius - CONFIG.ComfortZoneRadius * 0.5 then
                goto continue
            end

            -- 通过所有约束, 放置舒适区
            table.insert(comfortZones, {
                x = zx, y = zy,
                type = zoneTypes[math.random(1, 3)],
                playersInside = {},
                zoneEnergy = 100,     -- 舒适区能量(最大100)
                zoneCooldown = 0,     -- 冷却倒计时(秒)
                zoneUsesLeft = 5,     -- 剩余可用次数
            })
            placed = true
            break

            ::continue::
        end
        -- 如果50次尝试都失败, 放宽条件随机放置
        if not placed then
            local angle = math.random() * math.pi * 2
            local r = math.random() * safeRadius * 0.5
            table.insert(comfortZones, {
                x = cx + math.cos(angle) * r,
                y = cy + math.sin(angle) * r,
                type = zoneTypes[math.random(1, 3)],
                playersInside = {},
                zoneEnergy = 100,
                zoneCooldown = 0,
                zoneUsesLeft = 5,
            })
        end
    end
    print("[舒适区] 生成 " .. #comfortZones .. " 个舒适区")
end

-- 9.1 缩圈过渡(3s, 毒圈收缩25%, 舒适区失效判定)
local function enterShrinking()
    gamePhase = "shrinking"
    phaseTimer = CONFIG.CircleShrinkDuration  -- 1秒过渡(缩圈在下一轮day阶段渐进完成)
    playSound("sfx_circle_shrink", 0.6)

    -- 计算下一轮目标半径(供舒适区腐化判断用)
    local nextTargetRadius = circle.radius * CONFIG.CircleShrinkRatio

    -- 9.4 标记下一轮毒圈外的舒适区为腐败状态(光效熄灭, 无法回复能量)
    for _, zone in ipairs(comfortZones) do
        local dToCenter = dist(zone.x, zone.y, circle.cx, circle.cy)
        if dToCenter > nextTargetRadius then
            zone.corrupted = true
        end
    end

    -- 舒适区刷新机制: 剩余天数 = 刷新数量(很分散)
    -- 剩余5天→5个, 剩余4天→4个, 剩余3天→3个, 剩余2天→2个, 剩余1天→1个
    local remainDays = CONFIG.TotalRounds - currentRound
    if remainDays < 1 then remainDays = 1 end

    -- 清除所有旧舒适区, 重新生成
    comfortZones = {}
    comfortFloats = {}

    -- 重置所有玩家的舒适区占领状态
    for i = 1, #players do
        players[i].comfortClaims = {}
        players[i].comfortStandTimer = 0
        players[i].usingComfortZone = false
        players[i].isCapturingZone = false
        players[i].currentComfortZoneIdx = nil
    end

    -- 在缩圈后的安全区内生成分散的舒适区
    generateComfortZones(circle.cx, circle.cy, nextTargetRadius, remainDays)

    -- 设置缩圈目标(实际缩圈在下一轮day阶段60秒内渐进完成)
    circle.targetRadius = nextTargetRadius
    circle.shrinkSpeed = (circle.radius - circle.targetRadius) / CONFIG.DayDuration

    print("=== 缩圈过渡! 半径: " .. math.floor(circle.radius) .. " → " .. math.floor(nextTargetRadius) .. " (将在下轮60s内完成) ===")
end

-- 前向声明(供resolveAttackHit引用)
local interruptDrinking
local interruptInteract

-- 4.3 攻击判定(前摇结束后调用)
local function resolveAttackHit(attacker)
    local halfAngle = math.rad(CONFIG.AttackAngle / 2)
    local hitAny = false

    for i = 1, #players do
        local target = players[i]
        -- 已占领并使用中的玩家免疫攻击, 但正在占领中(isCapturingZone)的可以被打
        if target.idx ~= attacker.idx and target.alive and not target.usingComfortZone then
            local d = dist(attacker.x, attacker.y, target.x, target.y)
            if d <= CONFIG.AttackRange then
                local angleToTarget = angleBetween(attacker.x, attacker.y, target.x, target.y)
                local angleDiff = normalizeAngle(angleToTarget - attacker.facing)
                if math.abs(angleDiff) <= halfAngle then
                    -- 命中! 4.3: 自身-15毒, 目标+10毒
                    -- 毒满暴走buff: 毒素转移和能量掠夺翻倍
                    local buffMult = attacker.poisonMaxBuff and 2 or 1
                    local poisonAdd = CONFIG.AttackPoisonAdd * buffMult
                    local energySteal = CONFIG.EnergyStealOnHit * buffMult

                    -- 6.3: 掠夺目标能量(不超过目标剩余)
                    attacker.poison = clamp(attacker.poison - CONFIG.AttackPoisonReduce, CONFIG.PoisonMin, CONFIG.PoisonMax)
                    target.poison = clamp(target.poison + poisonAdd, CONFIG.PoisonMin, CONFIG.PoisonMax)
                    local stealAmount = math.min(energySteal, target.energy)
                    target.energy = clamp(target.energy - stealAmount, CONFIG.EnergyMin, CONFIG.EnergyMax)
                    attacker.energy = clamp(attacker.energy + stealAmount, CONFIG.EnergyMin, CONFIG.EnergyMax)
                    target.hitFlash = 0.3
                    hitAny = true
                    if attacker.isLocal or target.isLocal then playSound("sfx_attack_hit", 0.6) end

                    -- 5.3/5.5 检查是否打断喝药
                    interruptDrinking(target, attacker.idx)

                    -- 8.4 检查是否打断交互
                    interruptInteract(target)

                    -- 打断舒适区占领(正在占领中的玩家被攻击,重置占领进度)
                    if target.isCapturingZone then
                        target.isCapturingZone = false
                        target.comfortStandTimer = 0
                        local zi = target.currentComfortZoneIdx
                        if zi and target.comfortClaims and target.comfortClaims[zi] then
                            target.comfortClaims[zi].claimTimer = 0
                        end
                        if target.isLocal then
                            table.insert(floatingTexts, {
                                x = target.x, y = target.y - 50,
                                text = "占领被打断!",
                                color = {255, 100, 100},
                                timer = 1.0, maxTimer = 1.0,
                            })
                        end
                    end

                    -- 状态特效: 目标中毒, 攻击者减毒
                    table.insert(statusEffects, { playerIdx = target.idx, type = "poison", timer = 1.0 })
                    table.insert(statusEffects, { playerIdx = attacker.idx, type = "detox", timer = 0.8 })

                    -- 4.3 浮动文字: 显示实际数值(暴走时翻倍)
                    local poisonText = "+" .. poisonAdd .. "毒"
                    if attacker.poisonMaxBuff then poisonText = poisonText .. "(暴走!)" end
                    table.insert(floatingTexts, {
                        x = target.x, y = target.y - 30,
                        text = poisonText, color = {220, 50, 50},
                        timer = 1.0, maxTimer = 1.0,
                    })
                    table.insert(floatingTexts, {
                        x = attacker.x, y = attacker.y - 30,
                        text = "-15毒", color = {50, 200, 80},
                        timer = 1.0, maxTimer = 1.0,
                    })

                    -- 4.3 屏幕震动0.1秒
                    screenShake.timer = 0.1
                    screenShake.intensity = 4

                    -- 4.3 命中黑色墨汁粒子(溅射)
                    for j = 1, 8 do
                        table.insert(particles, {
                            x = target.x,
                            y = target.y,
                            vx = (math.random() - 0.5) * 200,
                            vy = (math.random() - 0.5) * 200,
                            life = 0.6,
                            color = {20, 20, 30},  -- 黑色墨汁
                        })
                    end
                    print("玩家 " .. attacker.idx .. " 命中玩家 " .. target.idx)
                end
            end
        end
    end
    return hitAny
end

-- 4.3 发起攻击(进入前摇)
local function performAttack(attacker)
    -- 只能在黑夜进行中阶段攻击
    if gamePhase ~= "day" then return end
    -- 5.2 喝药/硬直期间不能攻击
    if attacker.drinkingState ~= "idle" then return end
    -- 8.1 交互期间不能攻击
    if attacker.interactState ~= "idle" then return end
    if attacker.energy < CONFIG.AttackCostEnergy then return end
    if attacker.attackCooldown > 0 then return end
    if attacker.attackState ~= "idle" then return end

    -- 消耗能量, 进入前摇
    attacker.energy = attacker.energy - CONFIG.AttackCostEnergy
    attacker.attackCooldown = CONFIG.AttackCooldown
    attacker.attacking = true
    attacker.attackState = "windup"
    attacker.attackStateTimer = CONFIG.AttackWindup
    attacker.attackTimer = CONFIG.AttackWindup
    if attacker.isLocal then playSound("sfx_attack_swing", 0.5) end

    -- 前摇开始时的墨水拖尾特效(举臂)
    table.insert(attackEffects, {
        x = attacker.x,
        y = attacker.y,
        angle = attacker.facing,
        timer = CONFIG.AttackWindup + CONFIG.AttackRecovery,
        phase = "windup",
    })
end

-- 4.3 攻击状态更新(每帧在updatePlayers中调用)
local function updateAttackState(p, dt)
    if p.attackState == "windup" then
        p.attackStateTimer = p.attackStateTimer - dt
        if p.attackStateTimer <= 0 then
            -- 前摇结束 → 执行判定 → 进入后摇
            resolveAttackHit(p)
            p.attackState = "recovery"
            p.attackStateTimer = CONFIG.AttackRecovery

            -- 判定时刻的弧线特效
            table.insert(attackEffects, {
                x = p.x,
                y = p.y,
                angle = p.facing,
                timer = CONFIG.AttackRecovery,
                phase = "slash",
            })
        end
    elseif p.attackState == "recovery" then
        p.attackStateTimer = p.attackStateTimer - dt
        -- 后摇期间不能移动
        p.vx = 0
        p.vy = 0
        if p.attackStateTimer <= 0 then
            p.attackState = "idle"
            p.attacking = false
        end
    end
end

-- ============================================================================
-- 5.2-5.5 喝药系统
-- ============================================================================

-- 5.2 开始喝药(进入读条状态)
local function startDrinking(p, potionType)
    -- 胜利药水可在任何阶段喝(day/shrinking等)
    if potionType ~= "victory" and gamePhase ~= "day" then return false end
    if not p.alive then return false end
    if p.drinkingState ~= "idle" then return false end
    if p.attackState ~= "idle" then return false end
    if p.potionState ~= potionType then return false end
    -- 6.1 喝药前提: 能量>=10(胜利药水免费)
    if potionType ~= "victory" and p.energy < CONFIG.DrinkCostEnergy then return false end

    -- 6.1 扣除喝药能量(胜利药水不消耗)
    if potionType ~= "victory" then
        p.energy = p.energy - CONFIG.DrinkCostEnergy
    end
    p.drinkingState = "drinking"
    p.drinkingTimer = potionType == "victory" and 1.0 or CONFIG.DrinkDuration
    p.drinkingType = potionType
    -- 喝药期间不能移动/攻击
    p.vx = 0
    p.vy = 0
    if p.isLocal then playSound("sfx_drink_start", 0.5) end
    local typeName = potionType == "antidote" and "解药" or (potionType == "victory" and "胜利药水" or "毒药")
    print("玩家 " .. p.idx .. " 开始喝" .. typeName .. "!")
    return true
end

-- 5.3 打断喝药(被攻击命中时调用)
interruptDrinking = function(target, attackerIdx)
    if target.drinkingState ~= "drinking" then return false end

    local wasType = target.drinkingType

    -- 中断读条
    target.drinkingState = "stunned"
    target.drinkingTimer = CONFIG.DrinkStunDuration
    target.drinkingType = nil

    if target.isLocal then playSound("sfx_drink_interrupt", 0.6) end

    if wasType == "antidote" then
        -- 5.3 解药掉落至地面
        target.potionState = nil
        table.insert(groundPotions, {
            x = target.x + (math.random() - 0.5) * 30,
            y = target.y + (math.random() - 0.5) * 20,
            type = "antidote",
            timer = 999,  -- 持续到本轮黑夜结束
        })
        table.insert(floatingTexts, {
            x = target.x, y = target.y - 40,
            text = "打断! 解药掉落!", color = {100, 180, 255},
            timer = 1.2, maxTimer = 1.2,
        })
        print("玩家 " .. target.idx .. " 喝解药被打断! 解药掉落地面!")

    elseif wasType == "poison" then
        -- 5.5 毒药转移给攻击者
        target.potionState = nil
        local attacker = players[attackerIdx]
        if attacker and attacker.alive then
            attacker.potionState = "poison"
            attacker.poison = clamp(attacker.poison + CONFIG.DrinkInterruptPoisonTransfer, CONFIG.PoisonMin, CONFIG.PoisonMax)
            table.insert(floatingTexts, {
                x = attacker.x, y = attacker.y - 40,
                text = "+30毒(转移)!", color = {180, 60, 200},
                timer = 1.2, maxTimer = 1.2,
            })
            if attacker.isLocal then playSound("sfx_poison_transfer", 0.7) end
            print("玩家 " .. target.idx .. " 喝毒药被打断! 毒药转移给玩家 " .. attackerIdx .. "!")
        end
        table.insert(floatingTexts, {
            x = target.x, y = target.y - 40,
            text = "毒药转移!", color = {120, 255, 120},
            timer = 1.2, maxTimer = 1.2,
        })
    end

    -- 屏幕震动
    screenShake.timer = 0.15
    screenShake.intensity = 5
    return true
end

-- 5.2 喝药状态每帧更新
local function updateDrinkingState(p, dt)
    if p.drinkingState == "drinking" then
        p.drinkingTimer = p.drinkingTimer - dt
        -- 喝药期间强制不动
        p.vx = 0
        p.vy = 0
        if p.drinkingTimer <= 0 then
            -- 读条完成
            if p.drinkingType == "antidote" then
                -- 5.2 解药: 毒药值清零, 解药状态移除
                p.poison = CONFIG.PoisonMin
                p.potionState = nil
                table.insert(floatingTexts, {
                    x = p.x, y = p.y - 30,
                    text = "解毒成功!", color = {80, 220, 255},
                    timer = 1.0, maxTimer = 1.0,
                })
                table.insert(pickupGlows, { playerIdx = p.idx, type = "antidote", timer = 1.5, maxTimer = 1.5 })
                if p.isLocal then playSound("sfx_drink_complete", 0.7) end
                print("玩家 " .. p.idx .. " 成功喝下解药! 毒素清零!")
            elseif p.drinkingType == "poison" then
                -- 5.5 喝毒药成功: 毒药值+100, 立即死亡
                p.poison = clamp(p.poison + CONFIG.PoisonDrinkAmount, CONFIG.PoisonMin, CONFIG.PoisonMax)
                p.potionState = nil
                table.insert(floatingTexts, {
                    x = p.x, y = p.y - 30,
                    text = "+100毒! 毒发!", color = {255, 0, 0},
                    timer = 1.2, maxTimer = 1.2,
                })
                print("玩家 " .. p.idx .. " 成功喝下毒药! 毒发身亡!")
                -- 即时死亡(在updatePlayers中通过poison>=100检测触发)
            elseif p.drinkingType == "victory" then
                -- 胜利药水: 触发胜利!
                p.potionState = nil
                victoryWinnerIdx = p.idx
                gamePhase = "victory"
                playSound("sfx_nightfall", 1.0)  -- 用现有音效替代
                local hud = uiRoot_:FindById("hudPanel")
                if hud then hud:SetVisible(false) end
                table.insert(floatingTexts, {
                    x = p.x, y = p.y - 30,
                    text = "胜利!", color = {255, 215, 0},
                    timer = 2.0, maxTimer = 2.0,
                })
                print("=== 玩家 " .. p.idx .. " 喝下胜利药水! 游戏胜利! ===")
            end
            p.drinkingState = "idle"
            p.drinkingTimer = 0
            p.drinkingType = nil
        end
    elseif p.drinkingState == "stunned" then
        p.drinkingTimer = p.drinkingTimer - dt
        -- 硬直期间不能移动
        p.vx = 0
        p.vy = 0
        if p.drinkingTimer <= 0 then
            p.drinkingState = "idle"
            p.drinkingTimer = 0
        end
    end
end

-- 5.3 更新地面药剂(拾取检测)
local function updateGroundPotions(dt)
    local i = 1
    while i <= #groundPotions do
        local gp = groundPotions[i]
        local picked = false
        -- 检测存活玩家是否在拾取范围内
        for pi = 1, #players do
            local p = players[pi]
            if p.alive and p.potionState == nil and p.drinkingState == "idle" then
                local d = dist(p.x, p.y, gp.x, gp.y)
                if d <= CONFIG.GroundPotionPickupRange then
                    -- 拾取
                    p.potionState = gp.type
                    table.insert(pickupGlows, {
                        playerIdx = pi,
                        type = gp.type,
                        timer = 1.2, maxTimer = 1.2,
                    })
                    table.insert(floatingTexts, {
                        x = p.x, y = p.y - 30,
                        text = gp.type == "antidote" and "拾取解药" or "拾取毒药",
                        color = gp.type == "antidote" and {100, 200, 255} or {180, 60, 200},
                        timer = 1.0, maxTimer = 1.0,
                    })
                    if p.isLocal then playSound("sfx_antidote_get", 0.6) end
                    print("玩家 " .. pi .. " 拾取了地面" .. (gp.type == "antidote" and "解药" or "毒药"))
                    picked = true
                    break
                end
            end
        end
        if picked then
            table.remove(groundPotions, i)
        else
            i = i + 1
        end
    end
end

-- ============================================================================
-- 8.1-8.4 交互系统
-- ============================================================================

-- 8.4 中断交互(被攻击时调用)
interruptInteract = function(player)
    if player.interactState == "idle" then return false end
    local partnerIdx = player.interactPartner
    -- 重置自身
    player.interactState = "idle"
    player.interactPartner = nil
    player.interactTimer = 0
    player.interactGiveType = nil
    player.interactReceived = nil
    player.interactFlyAnim = nil
    -- 重置对方
    if partnerIdx then
        local partner = players[partnerIdx]
        if partner then
            partner.interactState = "idle"
            partner.interactPartner = nil
            partner.interactTimer = 0
            partner.interactGiveType = nil
            partner.interactReceived = nil
            partner.interactFlyAnim = nil
        end
    end
    table.insert(floatingTexts, {
        x = player.x, y = player.y - 40,
        text = "交互中断!", color = {255, 150, 50},
        timer = 1.0, maxTimer = 1.0,
    })
    print("玩家 " .. player.idx .. " 交互被中断!")
    return true
end

-- 8.1 发起交互请求
local function requestInteract(requester, targetIdx)
    if gamePhase ~= "day" then return false end
    if not requester.alive then return false end
    if requester.interactState ~= "idle" then return false end
    if requester.drinkingState ~= "idle" then return false end
    if requester.attackState ~= "idle" then return false end
    if requester.energy < CONFIG.InteractCostEnergy then return false end

    local target = players[targetIdx]
    if not target or not target.alive then return false end
    if target.interactState ~= "idle" then return false end
    if target.drinkingState ~= "idle" then return false end
    if target.attackState ~= "idle" then return false end

    -- 距离检测
    local d = dist(requester.x, requester.y, target.x, target.y)
    if d > CONFIG.InteractRange then return false end

    -- 8.1 消耗能量
    requester.energy = requester.energy - CONFIG.InteractCostEnergy

    -- 设置双方状态
    requester.interactState = "requesting"
    requester.interactPartner = targetIdx
    requester.interactTimer = CONFIG.InteractAcceptTimeout

    target.interactState = "pending"
    target.interactPartner = requester.idx
    target.interactTimer = CONFIG.InteractAcceptTimeout

    table.insert(floatingTexts, {
        x = requester.x, y = requester.y - 40,
        text = "请求交互...", color = {200, 200, 100},
        timer = 1.5, maxTimer = 1.5,
    })
    print("玩家 " .. requester.idx .. " 向玩家 " .. targetIdx .. " 发起交互请求")
    return true
end

-- 8.1 接受交互(或超时默认接受)
local function acceptInteract(player)
    if player.interactState ~= "pending" then return false end
    local partnerIdx = player.interactPartner
    local partner = players[partnerIdx]
    if not partner or partner.interactState ~= "requesting" then
        -- 对方已取消
        player.interactState = "idle"
        player.interactPartner = nil
        return false
    end

    -- 双方进入交互状态
    player.interactState = "interacting"
    player.interactTimer = CONFIG.InteractDuration
    player.interactGiveType = nil

    partner.interactState = "interacting"
    partner.interactTimer = CONFIG.InteractDuration
    partner.interactGiveType = nil

    -- 双方锁住速度
    player.vx = 0
    player.vy = 0
    partner.vx = 0
    partner.vy = 0

    table.insert(floatingTexts, {
        x = player.x, y = player.y - 40,
        text = "交互开始!", color = {100, 255, 200},
        timer = 1.0, maxTimer = 1.0,
    })
    print("玩家 " .. player.idx .. " 接受了玩家 " .. partnerIdx .. " 的交互")
    return true
end

-- 8.1 取消交互(主动取消/超出距离)
local function cancelInteract(player)
    if player.interactState == "idle" then return end
    local partnerIdx = player.interactPartner
    player.interactState = "idle"
    player.interactPartner = nil
    player.interactTimer = 0
    player.interactGiveType = nil
    player.interactReceived = nil
    player.interactFlyAnim = nil

    if partnerIdx then
        local partner = players[partnerIdx]
        if partner then
            partner.interactState = "idle"
            partner.interactPartner = nil
            partner.interactTimer = 0
            partner.interactGiveType = nil
            partner.interactReceived = nil
            partner.interactFlyAnim = nil
        end
    end
    print("玩家 " .. player.idx .. " 取消了交互")
end

-- 8.2 给予物品(选择给予解药/毒药)
local function giveItem(giver, itemType)
    if giver.interactState ~= "interacting" then return false end
    if not giver.potionState then return false end  -- 必须有药才能给
    local partnerIdx = giver.interactPartner
    local receiver = players[partnerIdx]
    if not receiver then return false end

    -- 8.3 欺骗机制: giver自己知道给什么, receiver看不到
    giver.interactGiveType = itemType
    giver.interactState = "giving"

    -- 抛物线动画
    giver.interactFlyAnim = {
        t = 0,
        duration = 0.6,
        fromX = giver.x,
        fromY = giver.y - 20,
        toX = receiver.x,
        toY = receiver.y - 20,
        type = itemType,
    }

    -- 消耗giver的药
    giver.potionState = nil
    if giver.isLocal then playSound("sfx_interact_give", 0.5) end

    print("玩家 " .. giver.idx .. " 给予玩家 " .. partnerIdx .. " " .. (itemType == "antidote" and "解药" or "毒药"))
    return true
end

-- 8.2 完成给予(抛物线动画结束后调用)
local function completeGive(giver, receiverIdx, itemType)
    local receiver = players[receiverIdx]
    if not receiver or not receiver.alive then return end

    -- 8.2 物品转移: 直接生效
    if itemType == "antidote" then
        -- 给予解药: 减少对方15毒
        receiver.poison = clamp(receiver.poison - 15, CONFIG.PoisonMin, CONFIG.PoisonMax)
        receiver.interactReceived = "antidote"
        table.insert(floatingTexts, {
            x = receiver.x, y = receiver.y - 40,
            text = "-15毒(解药)", color = {80, 220, 255},
            timer = 1.2, maxTimer = 1.2,
        })
        table.insert(statusEffects, { playerIdx = receiverIdx, type = "detox", timer = 0.8 })
    elseif itemType == "poison" then
        -- 8.3 欺骗: 给予毒药(伪装成解药)
        receiver.poison = clamp(receiver.poison + 25, CONFIG.PoisonMin, CONFIG.PoisonMax)
        receiver.interactReceived = "poison"
        table.insert(floatingTexts, {
            x = receiver.x, y = receiver.y - 40,
            text = "+25毒(被骗!)", color = {255, 60, 60},
            timer = 1.5, maxTimer = 1.5,
        })
        table.insert(statusEffects, { playerIdx = receiverIdx, type = "poison", timer = 1.0 })
        screenShake.timer = 0.15
        screenShake.intensity = 3
    end

    -- 重置双方交互状态
    giver.interactState = "idle"
    giver.interactPartner = nil
    giver.interactTimer = 0
    giver.interactGiveType = nil
    giver.interactFlyAnim = nil

    receiver.interactState = "idle"
    receiver.interactPartner = nil
    receiver.interactTimer = 0
    receiver.interactGiveType = nil
    receiver.interactFlyAnim = nil
end

-- 8.1 交互状态每帧更新
local function updateInteractionState(p, dt)
    if p.interactState == "idle" then return end

    if p.interactState == "requesting" then
        p.interactTimer = p.interactTimer - dt
        -- 请求期间不能移动
        p.vx = 0
        p.vy = 0
        -- 超时: 默认接受
        if p.interactTimer <= 0 then
            local partner = players[p.interactPartner]
            if partner and partner.interactState == "pending" then
                acceptInteract(partner)
            else
                cancelInteract(p)
            end
        end
        -- 距离检测: 超出范围取消
        if p.interactPartner then
            local partner = players[p.interactPartner]
            if partner then
                local d = dist(p.x, p.y, partner.x, partner.y)
                if d > CONFIG.InteractRange * 1.5 then
                    cancelInteract(p)
                end
            end
        end

    elseif p.interactState == "pending" then
        p.interactTimer = p.interactTimer - dt
        -- 等待期间不能移动
        p.vx = 0
        p.vy = 0
        -- 超时: 默认接受
        if p.interactTimer <= 0 then
            acceptInteract(p)
        end

    elseif p.interactState == "interacting" then
        p.interactTimer = p.interactTimer - dt
        -- 交互期间不能移动
        p.vx = 0
        p.vy = 0
        -- 超时: 交互失败, 双方恢复
        if p.interactTimer <= 0 then
            cancelInteract(p)
        end

    elseif p.interactState == "giving" then
        -- 播放抛物线动画
        p.vx = 0
        p.vy = 0
        if p.interactFlyAnim then
            p.interactFlyAnim.t = p.interactFlyAnim.t + dt
            if p.interactFlyAnim.t >= p.interactFlyAnim.duration then
                -- 动画完成, 应用效果
                completeGive(p, p.interactPartner, p.interactGiveType)
            end
        else
            -- 没有动画数据, 直接结束
            cancelInteract(p)
        end
    end
end

-- 8.5 找到最近可交互玩家(用于UI提示和交互触发)
local function findNearestInteractable(player)
    if not player.alive then return nil end
    if player.interactState ~= "idle" then return nil end
    if player.drinkingState ~= "idle" then return nil end
    if player.attackState ~= "idle" then return nil end

    local bestIdx = nil
    local bestDist = CONFIG.InteractRange
    for i = 1, #players do
        local other = players[i]
        if other.idx ~= player.idx and other.alive
            and other.interactState == "idle"
            and other.drinkingState == "idle"
            and other.attackState ~= "idle" == false then
            local d = dist(player.x, player.y, other.x, other.y)
            if d <= bestDist then
                bestDist = d
                bestIdx = i
            end
        end
    end
    return bestIdx
end

-- ============================================================================
-- AI 逻辑
-- ============================================================================

-- AI全局: 正在喝解药的玩家列表(所有AI共享优先攻击目标)
local aiPriorityTargets = {}  -- {playerIdx = true}

local function updateAI(p, dt)
    if p.isLocal or not p.alive then return end

    -- 5.2 喝药/硬直期间AI不做任何决策
    if p.drinkingState ~= "idle" then
        p.vx = 0
        p.vy = 0
        return
    end

    -- 8.1 交互期间AI不做其他决策
    if p.interactState ~= "idle" then
        p.vx = 0
        p.vy = 0
        -- 8.2 AI在interacting状态时选择给予
        if p.interactState == "interacting" and p.potionState then
            -- AI决策: 有毒药时50%概率欺骗(给毒药), 有解药时80%概率给解药
            if p.interactTimer < CONFIG.InteractDuration - 0.5 then
                -- 等0.5秒再做决定(模拟思考)
                if math.random() < 0.3 then  -- 每帧30%概率执行(避免瞬间)
                    if p.potionState == "poison" then
                        -- 有毒药: 总是伪装给"解药"(实际给毒药)
                        giveItem(p, "poison")
                    elseif p.potionState == "antidote" then
                        -- 有解药: 80%真给解药, 20%欺骗(不给, 等待超时)
                        if math.random() < 0.8 then
                            giveItem(p, "antidote")
                        end
                    end
                end
            end
        end
        -- 8.1 AI接受交互: pending时自动接受(模拟)
        if p.interactState == "pending" and p.interactTimer < CONFIG.InteractAcceptTimeout - 0.5 then
            -- 等0.5秒后自动接受
            if math.random() < 0.1 then
                acceptInteract(p)
            end
        end
        return
    end

    -- 8.1 AI发起交互决策: 有药且附近有人时考虑交互
    if p.potionState and gamePhase == "day" and p.energy >= CONFIG.InteractCostEnergy then
        -- 找最近的idle玩家
        for i = 1, #players do
            local other = players[i]
            if other.idx ~= p.idx and other.alive and other.interactState == "idle"
                and other.drinkingState == "idle" and other.attackState == "idle" then
                local d = dist(p.x, p.y, other.x, other.y)
                if d <= CONFIG.InteractRange then
                    -- 有毒药时更倾向交互(欺骗), 有解药时偶尔交互(帮助)
                    local chance = p.potionState == "poison" and 0.015 or 0.005
                    if math.random() < chance then
                        requestInteract(p, other.idx)
                        return
                    end
                end
            end
        end
    end

    -- AI胜利药水: 立刻喝
    if p.potionState == "victory" then
        startDrinking(p, "victory")
        return
    end

    -- 5.2 AI喝药决策: 有解药且有毒素时考虑喝
    if p.potionState == "antidote" and p.poison >= 20 and gamePhase == "day" then
        -- 附近没有敌人时才喝(安全距离)
        local nearestEnemyDist = math.huge
        for i = 1, #players do
            if players[i].alive and players[i].idx ~= p.idx then
                local d = dist(p.x, p.y, players[i].x, players[i].y)
                if d < nearestEnemyDist then nearestEnemyDist = d end
            end
        end
        -- 毒素越高越急切喝药, 安全距离随毒素降低
        local urgency = p.poison / CONFIG.PoisonMax  -- 0~1
        local safeDist = 150 * (1 - urgency * 0.7)  -- 毒素高时安全距离降低
        local drinkChance = 0.02 + urgency * 0.08   -- 毒素高时概率提高(2%~10%)
        if nearestEnemyDist > safeDist and math.random() < drinkChance then
            startDrinking(p, "antidote")
            return
        end
    end

    -- 5.5 AI喝毒药决策: 有毒药时小概率"佯装喝药"引诱对手攻击(策略性)
    if p.potionState == "poison" and gamePhase == "day" then
        local nearestEnemyDist = math.huge
        for i = 1, #players do
            if players[i].alive and players[i].idx ~= p.idx then
                local d = dist(p.x, p.y, players[i].x, players[i].y)
                if d < nearestEnemyDist then nearestEnemyDist = d end
            end
        end
        -- 只在有敌人靠近时才佯装喝毒药(吸引打断 → 转移毒素)
        if nearestEnemyDist < 80 and math.random() < 0.01 then
            startDrinking(p, "poison")
            return
        end
    end

    p.aiTimer = p.aiTimer - dt
    if p.aiTimer > 0 then
        -- 继续执行当前决策
        local dx = p.aiTargetX - p.x
        local dy = p.aiTargetY - p.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d > 5 then
            p.vx = (dx / d) * CONFIG.MoveSpeed
            p.vy = (dy / d) * CONFIG.MoveSpeed
            p.facing = math.atan(dy, dx)
            -- AI翻转方向跟随移动
            if p.vx > 0.1 then p.flipDir = 1 elseif p.vx < -0.1 then p.flipDir = -1 end
        else
            p.vx = 0
            p.vy = 0
        end

        -- 实时检测攻击：好战AI，随时攻击范围内目标
        if p.attackState == "idle" and p.attackCooldown <= 0 and p.energy >= CONFIG.AttackCostEnergy then
            -- 优先攻击正在喝解药的玩家(最高优先级)
            local priorityTarget = nil
            local priorityDist = math.huge
            for i = 1, #players do
                local other = players[i]
                if other.alive and other.idx ~= p.idx and aiPriorityTargets[other.idx] then
                    local dToOther = dist(p.x, p.y, other.x, other.y)
                    if dToOther <= CONFIG.AttackRange and dToOther < priorityDist then
                        priorityTarget = other
                        priorityDist = dToOther
                    end
                end
            end
            if priorityTarget then
                p.facing = angleBetween(p.x, p.y, priorityTarget.x, priorityTarget.y)
                performAttack(p)
            else
                -- 普通攻击: 范围内任何目标
                for i = 1, #players do
                    local other = players[i]
                    if other.alive and other.idx ~= p.idx then
                        local dToOther = dist(p.x, p.y, other.x, other.y)
                        if dToOther <= CONFIG.AttackRange then
                            p.facing = angleBetween(p.x, p.y, other.x, other.y)
                            performAttack(p)
                            break
                        end
                    end
                end
            end
        end
        return
    end

    -- 重新决策
    p.aiTimer = CONFIG.AIUpdateInterval + math.random() * 0.2

    -- ========== 好战AI目标选择(优先级从高到低) ==========
    -- 优先级1: 正在喝解药的玩家(最高优先攻击)
    -- 优先级2: 毒素低+能量高的玩家(肥羊目标)
    -- 优先级3: 最近的敌人

    -- 更新优先攻击列表: 正在喝解药的玩家
    aiPriorityTargets = {}
    for i = 1, #players do
        local other = players[i]
        if other.alive and other.idx ~= p.idx then
            if other.drinkingState == "drinking" and other.drinkingType == "antidote" then
                aiPriorityTargets[other.idx] = true
            end
        end
    end

    -- 检查是否有优先攻击目标(正在喝解药的)
    local bestPriorityTarget = nil
    local bestPriorityDist = math.huge
    for i = 1, #players do
        local other = players[i]
        if other.alive and other.idx ~= p.idx and aiPriorityTargets[other.idx] then
            local d = dist(p.x, p.y, other.x, other.y)
            if d < bestPriorityDist then
                bestPriorityDist = d
                bestPriorityTarget = other
            end
        end
    end

    -- 如果有玩家正在喝解药,全力追击!
    if bestPriorityTarget then
        p.aiTargetX = bestPriorityTarget.x + (math.random() - 0.5) * 15
        p.aiTargetY = bestPriorityTarget.y + (math.random() - 0.5) * 15
        p.aiWantsAttack = true
        p.sprinting = p.energy > 20  -- 冲刺追击
        -- 保持在毒圈内
        local dToCenter = dist(p.aiTargetX, p.aiTargetY, circle.cx, circle.cy)
        if dToCenter > circle.radius * 0.8 then
            p.aiTargetX = lerp(p.aiTargetX, circle.cx, 0.5)
            p.aiTargetY = lerp(p.aiTargetY, circle.cy, 0.5)
        end
        return
    end

    -- 找最近的未腐败舒适区(AI也受舒适区使用限制)
    local nearestZoneDist = math.huge
    local nearestZone = nil
    for zi, zone in ipairs(comfortZones) do
        if not zone.corrupted then
            -- 检查AI是否已占领并耗尽该舒适区
            local claim = p.comfortClaims and p.comfortClaims[zi]
            local depleted = claim and claim.claimed and claim.energyLeft <= 0
            if not depleted then
                local d = dist(p.x, p.y, zone.x, zone.y)
                if d < nearestZoneDist then
                    nearestZoneDist = d
                    nearestZone = zone
                end
            end
        end
    end

    -- 能量极低时才去舒适区(好战优先,能量<20才考虑恢复)
    if p.energy < 20 and nearestZone then
        -- 已在舒适区内 → 停下来恢复(但时间缩短,恢复一点就走)
        if nearestZoneDist <= CONFIG.ComfortZoneRadius * 0.5 then
            p.aiTargetX = p.x
            p.aiTargetY = p.y
            p.aiWantsAttack = false
            p.aiTimer = 2.0 + math.random() * 2.0  -- 只停留2~4秒就重新追击
            return
        else
            -- 前往最近舒适区
            p.aiTargetX = nearestZone.x + (math.random() - 0.5) * 20
            p.aiTargetY = nearestZone.y + (math.random() - 0.5) * 20
            p.aiWantsAttack = false
            return
        end
    end

    -- ========== AI毒素为0时逃跑(保命优先) ==========
    if p.poison <= 0 then
        -- 找离自己最近的敌人,反方向逃跑
        local nearestEnemy = nil
        local nearestDist = math.huge
        for i = 1, #players do
            local other = players[i]
            if other.alive and other.idx ~= p.idx then
                local d = dist(p.x, p.y, other.x, other.y)
                if d < nearestDist then
                    nearestDist = d
                    nearestEnemy = other
                end
            end
        end
        if nearestEnemy and nearestDist < 200 then
            -- 远离最近敌人
            local fleeAngle = math.atan(p.y - nearestEnemy.y, p.x - nearestEnemy.x)
            p.aiTargetX = p.x + math.cos(fleeAngle) * 200
            p.aiTargetY = p.y + math.sin(fleeAngle) * 200
            p.sprinting = p.energy > 15  -- 逃跑时冲刺
        else
            -- 没有近处敌人,随机游走保持距离
            p.aiTargetX = p.x + (math.random() - 0.5) * 250
            p.aiTargetY = p.y + (math.random() - 0.5) * 250
            p.sprinting = false
        end
        p.aiWantsAttack = false
        -- 保持在毒圈内
        local dToCenter = dist(p.aiTargetX, p.aiTargetY, circle.cx, circle.cy)
        if dToCenter > circle.radius * 0.8 then
            p.aiTargetX = lerp(p.aiTargetX, circle.cx, 0.5)
            p.aiTargetY = lerp(p.aiTargetY, circle.cy, 0.5)
        end
        return
    end

    -- ========== 好战目标选择(优先级: 喝解药>0毒药>满能量>好状态) ==========
    local bestTarget = nil
    local bestScore = -math.huge
    for i = 1, #players do
        local other = players[i]
        if other.alive and other.idx ~= p.idx and not other.usingComfortZone then
            local d = dist(p.x, p.y, other.x, other.y)
            local score = -d * 0.1  -- 基础: 距离近优先

            -- 优先级1(最高): 正在喝解药 +500
            if other.drinkingState == "drinking" and other.drinkingType == "antidote" then
                score = score + 500
            end
            -- 优先级2: 0毒素的玩家 +300 (打他加毒效果最好)
            if other.poison <= 0 then
                score = score + 300
            end
            -- 优先级3: 满能量的玩家 +150 (掠夺价值高)
            if other.energy >= CONFIG.EnergyMax then
                score = score + 150
            end
            -- 优先级4: 好状态(低毒+高能) +50~100
            local goodState = (CONFIG.PoisonMax - other.poison) / CONFIG.PoisonMax * 50
                            + (other.energy / CONFIG.EnergyMax) * 50
            score = score + goodState

            if score > bestScore then
                bestScore = score
                bestTarget = other
            end
        end
    end

    if bestTarget then
        local d = dist(p.x, p.y, bestTarget.x, bestTarget.y)
        -- 好战AI: 主动追击
        if p.energy >= CONFIG.AttackCostEnergy then
            p.aiTargetX = bestTarget.x + (math.random() - 0.5) * 20
            p.aiTargetY = bestTarget.y + (math.random() - 0.5) * 20
            p.aiWantsAttack = d < CONFIG.AttackRange * 1.5
            -- 目标较远时开启冲刺
            if d > CONFIG.AttackRange * 2 and p.energy > 30 then
                p.sprinting = true
            else
                p.sprinting = false
            end
        else
            -- 能量不足时短暂游走
            p.aiTargetX = p.x + (math.random() - 0.5) * 150
            p.aiTargetY = p.y + (math.random() - 0.5) * 150
            p.aiWantsAttack = false
        end
    else
        -- 没有目标，向地图中心移动
        p.aiTargetX = CONFIG.MapSize / 2 + (math.random() - 0.5) * 200
        p.aiTargetY = CONFIG.MapSize / 2 + (math.random() - 0.5) * 200
        p.aiWantsAttack = false
    end

    -- 保持在毒圈内
    local dToCenter = dist(p.aiTargetX, p.aiTargetY, circle.cx, circle.cy)
    if dToCenter > circle.radius * 0.8 then
        p.aiTargetX = lerp(p.aiTargetX, circle.cx, 0.5)
        p.aiTargetY = lerp(p.aiTargetY, circle.cy, 0.5)
    end

end

-- ============================================================================
-- 更新逻辑
-- ============================================================================

local function updatePlayers(dt)
    for i = 1, #players do
        local p = players[i]
        if not p.alive and not p.isGhost then goto continue end
        -- 鬼魂只能移动, 不能攻击/不受毒
        if p.isGhost then
            local moveX = p.vx * dt
            local moveY = p.vy * dt
            p.x = p.x + moveX
            p.y = p.y + moveY
            goto continue
        end

        -- 更新冷却
        p.attackCooldown = math.max(0, p.attackCooldown - dt)
        p.attackTimer = math.max(0, p.attackTimer - dt)
        p.hitFlash = math.max(0, p.hitFlash - dt)

        -- 4.3 攻击状态机更新(前摇/后摇)
        updateAttackState(p, dt)

        -- 5.2 喝药状态更新
        updateDrinkingState(p, dt)

        -- 8.1 交互状态更新
        updateInteractionState(p, dt)

        -- AI更新
        if not p.isLocal then
            updateAI(p, dt)
        end

        -- 6.1 移动不消耗能量(已移除移动耗能)

        -- 移动(后摇期间由updateAttackState强制归零vx/vy, 这里正常应用)
        local moveX = p.vx * dt
        local moveY = p.vy * dt

        p.x = p.x + moveX
        p.y = p.y + moveY

        -- 9.2 毒圈外加毒: 10点/秒(无额外能量消耗,无直接伤害)
        -- 只在 day 和 shrinking 阶段生效
        local dToCenter = dist(p.x, p.y, circle.cx, circle.cy)
        if dToCenter > circle.radius and (gamePhase == "day" or gamePhase == "shrinking") then
            -- 每轮毒圈更毒: 基础10/秒, 每轮+5/秒
            local poisonRate = CONFIG.CirclePoisonRate + (currentRound - 1) * 5
            p.poison = clamp(p.poison + poisonRate * dt, CONFIG.PoisonMin, CONFIG.PoisonMax)
            p.inPoisonZone = true
        else
            p.inPoisonZone = false
        end

        -- 7.2 舒适区能量回复(10/秒, 10秒回满, 需站立不动3秒后) - 9.4 失效区不回复
        -- 新增: 舒适区有自身能量条(100), 消耗完进入5秒冷却, 每个舒适区只能用5次
        -- 舒适区站点占领机制
        local wasInComfort = p.inComfortZone
        p.inComfortZone = false
        if p.usedZoneHintCD and p.usedZoneHintCD > 0 then p.usedZoneHintCD = p.usedZoneHintCD - dt end
        local isStanding = (p.vx == 0 and p.vy == 0)  -- 必须站着不动
        if not p.comfortClaims then p.comfortClaims = {} end
        p.isCapturingZone = false  -- 每帧重置
        p.currentComfortZoneIdx = nil  -- 当前所在舒适区索引
        for zi, zone in ipairs(comfortZones) do
            -- 跳过腐败/耗尽/冷却中的舒适区
            local zoneAvailable = not zone.corrupted
                and (zone.zoneUsesLeft or 5) > 0
                and (zone.zoneCooldown or 0) <= 0
                and (zone.zoneEnergy or 100) > 0
            if not zoneAvailable then goto nextZone end

            -- 初始化该玩家对此舒适区的占领记录
            if not p.comfortClaims[zi] then
                p.comfortClaims[zi] = { claimed = false, claimTimer = 0, energyLeft = 0 }
            end
            local claim = p.comfortClaims[zi]

            -- 检查该玩家是否已占领并耗尽此舒适区能量
            if claim.claimed and claim.energyLeft <= 0 then
                -- 本地玩家进入已耗尽的舒适区时给出提示
                if p.isLocal and dist(p.x, p.y, zone.x, zone.y) <= CONFIG.ComfortZoneRadius then
                    if not p.usedZoneHintCD or p.usedZoneHintCD <= 0 then
                        p.usedZoneHintCD = 3.0
                        table.insert(floatingTexts, {
                            x = p.x, y = p.y - 40,
                            text = "此舒适区能量已耗尽,请前往其他舒适区",
                            color = {200, 150, 80},
                            timer = 1.5, maxTimer = 1.5,
                        })
                    end
                end
                goto nextZone
            end

            if dist(p.x, p.y, zone.x, zone.y) <= CONFIG.ComfortZoneRadius then
                -- 舒适区独占: 如果已被其他玩家占用,本玩家不能使用
                if zone.occupiedBy and zone.occupiedBy ~= p.idx then
                    if p.isLocal then
                        if not p.usedZoneHintCD or p.usedZoneHintCD <= 0 then
                            p.usedZoneHintCD = 3.0
                            table.insert(floatingTexts, {
                                x = p.x, y = p.y - 40,
                                text = "舒适区被占用中",
                                color = {200, 150, 80},
                                timer = 1.2, maxTimer = 1.2,
                            })
                        end
                    end
                    goto nextZone
                end
                p.inComfortZone = true
                p.currentComfortZoneIdx = zi
                if not wasInComfort and p.isLocal then playSound("sfx_comfort_zone_enter", 0.4) end

                -- 已占领且有剩余能量 → 直接使用(无需等待)
                if claim.claimed and claim.energyLeft > 0 then
                    zone.zoneEnergy = zone.zoneEnergy or 100
                    zone.occupiedBy = p.idx
                    p.usingComfortZone = true
                    if p.energy < CONFIG.EnergyMax then
                        local regenAmount = CONFIG.ComfortZoneRegenRate * dt
                        local actualRegen = math.min(regenAmount, claim.energyLeft)
                        actualRegen = math.min(actualRegen, zone.zoneEnergy)

                        local prevEnergy = p.energy
                        p.energy = clamp(p.energy + actualRegen, CONFIG.EnergyMin, CONFIG.EnergyMax)
                        claim.energyLeft = claim.energyLeft - actualRegen
                        zone.zoneEnergy = zone.zoneEnergy - actualRegen

                        -- 能量配额耗尽 → 需要重新占领
                        if claim.energyLeft <= 0 then
                            claim.energyLeft = 0
                            claim.claimed = false
                            claim.claimTimer = 0
                            zone.occupiedBy = nil
                            p.usingComfortZone = false
                            if p.isLocal then
                                table.insert(floatingTexts, {
                                    x = p.x, y = p.y - 50,
                                    text = "能量配额已用完,需重新占领!",
                                    color = {255, 200, 100},
                                    timer = 1.5, maxTimer = 1.5,
                                })
                            end
                        end

                        -- 舒适区总能量耗尽 → 进入5秒冷却
                        if zone.zoneEnergy <= 0 then
                            zone.zoneEnergy = 0
                            zone.zoneCooldown = 5.0
                            zone.zoneUsesLeft = zone.zoneUsesLeft - 1
                        end

                        -- 浮动+5数字(每积累5点触发一次)
                        local prevTick = math.floor(prevEnergy / 5)
                        local curTick = math.floor(p.energy / 5)
                        if curTick > prevTick then
                            table.insert(comfortFloats, {
                                x = p.x + (math.random() - 0.5) * 10,
                                y = p.y - 40,
                                text = "+5",
                                life = 1.0,
                                maxLife = 1.0,
                                color = {80, 200, 80},
                            })
                        end
                    end
                -- 未占领 → 需要站立等待3秒占领
                elseif not claim.claimed then
                    if isStanding then
                        claim.claimTimer = claim.claimTimer + dt
                        p.isCapturingZone = true  -- 标记正在占领(可被攻击打断)
                        p.comfortStandTimer = claim.claimTimer  -- 同步给UI显示

                        -- 占领成功!
                        if claim.claimTimer >= CONFIG.ComfortZoneWaitTime then
                            claim.claimed = true
                            claim.energyLeft = CONFIG.ComfortZoneClaimEnergy
                            claim.claimTimer = 0
                            zone.occupiedBy = p.idx
                            p.usingComfortZone = true
                            p.isCapturingZone = false
                            if p.isLocal then
                                playSound("sfx_comfort_zone_enter", 0.6)
                                table.insert(floatingTexts, {
                                    x = p.x, y = p.y - 50,
                                    text = "占领成功! +100能量配额",
                                    color = {80, 255, 80},
                                    timer = 1.5, maxTimer = 1.5,
                                })
                            end
                        end
                    else
                        -- 移动了，重置占领计时
                        claim.claimTimer = 0
                        p.comfortStandTimer = 0
                        p.isCapturingZone = false
                    end
                end
                break
            end
            ::nextZone::
        end
        -- 不在舒适区时重置状态并释放占用
        if not p.inComfortZone then
            p.comfortStandTimer = 0
            p.isCapturingZone = false
            if p.usingComfortZone then
                -- 释放之前占用的舒适区
                for _, z in ipairs(comfortZones) do
                    if z.occupiedBy == p.idx then z.occupiedBy = nil end
                end
                p.usingComfortZone = false
            end
        end

        -- 10.2 毒值≥80预警音效(本地玩家, cooldown限制)
        if p.isLocal and p.alive and p.poison >= 80 and poisonWarnCooldown <= 0 then
            playSound("sfx_poison_warning", 0.5)
            poisonWarnCooldown = 3.0  -- 每3秒最多一次
        end

        -- 10.3 中毒加深骷髅(每跨越+10阈值时闪现)
        if p.poisonSkullTimer > 0 then
            p.poisonSkullTimer = p.poisonSkullTimer - dt
        end
        local curTick10 = math.floor(p.poison / 10)
        if curTick10 > p.lastPoisonTick and p.poison > 0 then
            p.poisonSkullTimer = 0.8
            if p.isLocal then playSound("sfx_poison_tick", 0.4) end
        end
        p.lastPoisonTick = curTick10

        -- 4.2 毒素上限钳制（不再即时死亡，统一由结算阶段淘汰）
        if p.poison > CONFIG.PoisonMax then
            p.poison = CONFIG.PoisonMax
        end

        -- 4.3 毒满暴走buff检测
        if p.poison >= CONFIG.PoisonMax then
            if not p.poisonMaxBuff then
                p.poisonMaxBuff = true
                table.insert(floatingTexts, {
                    x = p.x, y = p.y - 60,
                    text = "毒满暴走! 攻击翻倍!",
                    color = {255, 0, 180},
                    timer = 2.0, maxTimer = 2.0,
                })
                if p.isLocal then playSound("sfx_poison_transfer", 0.8) end
            end
        elseif p.poison <= CONFIG.PoisonMin then
            if p.poisonMaxBuff then
                p.poisonMaxBuff = false
                table.insert(floatingTexts, {
                    x = p.x, y = p.y - 60,
                    text = "暴走结束",
                    color = {150, 150, 150},
                    timer = 1.5, maxTimer = 1.5,
                })
            end
        end

        ::continue::
    end
end

local function updateParticles(dt)
    local i = 1
    while i <= #particles do
        local p = particles[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.life = p.life - dt * 2
        if p.life <= 0 then
            table.remove(particles, i)
        else
            i = i + 1
        end
    end
end

-- 更新死亡纸片碎裂
local function updateDeathPieces(dt)
    local i = 1
    while i <= #deathPieces do
        local p = deathPieces[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vy = p.vy + 40 * dt  -- 轻微下坠
        p.vx = p.vx * 0.98     -- 空气阻力
        p.rot = p.rot + p.rotV * dt
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(deathPieces, i)
        else
            i = i + 1
        end
    end
    -- 污渍缓慢淡出(很慢, 保留很久)
    for si = #deathStains, 1, -1 do
        deathStains[si].alpha = deathStains[si].alpha - dt * 3
        if deathStains[si].alpha <= 0 then
            table.remove(deathStains, si)
        end
    end
end

local function updateAttackEffects(dt)
    local i = 1
    while i <= #attackEffects do
        local e = attackEffects[i]
        e.timer = e.timer - dt
        if e.timer <= 0 then
            table.remove(attackEffects, i)
        else
            i = i + 1
        end
    end
end

-- 4.3 浮动文字更新(上飘+淡出)
local function updateFloatingTexts(dt)
    local i = 1
    while i <= #floatingTexts do
        local ft = floatingTexts[i]
        ft.timer = ft.timer - dt
        ft.y = ft.y - 40 * dt  -- 每秒上飘40像素
        if ft.timer <= 0 then
            table.remove(floatingTexts, i)
        else
            i = i + 1
        end
    end
end

-- 4.3 屏幕震动更新
local function updateScreenShake(dt)
    if screenShake.timer > 0 then
        screenShake.timer = screenShake.timer - dt
        if screenShake.timer <= 0 then
            screenShake.timer = 0
            screenShake.intensity = 0
        end
    end
end

local function updateCamera()
    local p = players[localPlayerIdx]
    if p and (p.alive or p.isGhost) then
        camera.x = p.x
        camera.y = p.y
    end
end

-- ============================================================================
-- 玩家输入
-- ============================================================================

-- ===== 触控按钮系统(手机适配) =====
local touchButtons = {
    attack = { pressed = false, touchId = -1 },
    item = { pressed = false, touchId = -1 },
    sprint = { pressed = false, touchId = -1 },
    interact = { pressed = false, touchId = -1 },
    reject = { pressed = false, touchId = -1 },
}
local touchJoystick = {
    active = false,
    touchId = -1,
    cx = 0, cy = 0,       -- 摇杆中心(触摸起始点)
    dx = 0, dy = 0,       -- 摇杆偏移
    radius = 50,          -- 摇杆最大半径
}
local isTouchDevice = false  -- 检测到触摸输入后自动开启

local moveInput = { x = 0, y = 0 }

-- ============================================================================
-- 手柄适配
-- ============================================================================
local GAMEPAD_DEADZONE = 0.2  -- 摇杆死区

local function applyDeadzone(value)
    if math.abs(value) < GAMEPAD_DEADZONE then return 0 end
    -- 平滑映射: 死区外的值归一化到 0~1
    local sign = value > 0 and 1 or -1
    return sign * (math.abs(value) - GAMEPAD_DEADZONE) / (1.0 - GAMEPAD_DEADZONE)
end

--- 获取当前连接的手柄(优先返回第一个 Controller 类型)
local function getGamepad()
    for i = 0, input.numJoysticks - 1 do
        local js = input:GetJoystickByIndex(i)
        if js and js:IsController() then
            return js
        end
    end
    return nil
end

local function handlePlayerInput(dt)
    local p = players[localPlayerIdx]
    if not p then return end
    -- 死亡且非鬼魂: 不可操作
    if not p.alive and not p.isGhost then return end

    -- 5.2 喝药/硬直期间禁止移动和攻击
    if not p.isGhost and (p.drinkingState == "drinking" or p.drinkingState == "stunned") then
        p.vx = 0
        p.vy = 0
        return
    end

    -- 8.1 交互期间禁止移动和攻击
    if not p.isGhost and p.interactState ~= "idle" then
        p.vx = 0
        p.vy = 0
        return
    end

    -- 获取手柄(每帧检测)
    local gamepad = getGamepad()

    -- 6.1 奔跑: 按住Shift键 或 触控奔跑键 或 手柄LB + 有能量时奔跑
    local sprintPressed = input:GetKeyDown(KEY_LSHIFT) or input:GetKeyDown(KEY_RSHIFT) or touchButtons.sprint.pressed
    if not sprintPressed and gamepad then
        sprintPressed = gamepad:GetButtonDown(CONTROLLER_BUTTON_LEFTSHOULDER)
    end
    if sprintPressed then
        if p.energy > 0 then
            p.sprinting = true
        else
            p.sprinting = false
        end
    else
        p.sprinting = false
    end

    -- WASD移动(鬼魂也可以移动)
    moveInput.x = 0
    moveInput.y = 0
    if input:GetKeyDown(KEY_W) then moveInput.y = -1 end
    if input:GetKeyDown(KEY_S) then moveInput.y = 1 end
    if input:GetKeyDown(KEY_A) then moveInput.x = -1 end
    if input:GetKeyDown(KEY_D) then moveInput.x = 1 end

    -- 手柄左摇杆移动输入合并
    if gamepad then
        local gpX = applyDeadzone(gamepad:GetAxisPosition(CONTROLLER_AXIS_LEFTX))
        local gpY = applyDeadzone(gamepad:GetAxisPosition(CONTROLLER_AXIS_LEFTY))
        if gpX ~= 0 or gpY ~= 0 then
            moveInput.x = gpX
            moveInput.y = gpY
        end
    end

    -- 触控摇杆输入合并
    if touchJoystick.active then
        local jLen = math.sqrt(touchJoystick.dx * touchJoystick.dx + touchJoystick.dy * touchJoystick.dy)
        if jLen > 5 then  -- 死区
            moveInput.x = touchJoystick.dx / touchJoystick.radius
            moveInput.y = touchJoystick.dy / touchJoystick.radius
        end
    end

    -- 根据移动输入更新角色翻转方向(PC用AD键, 触控/手柄用moveInput.x)
    if moveInput.x > 0.1 then
        p.flipDir = 1   -- 朝右
    elseif moveInput.x < -0.1 then
        p.flipDir = -1  -- 朝左
    end

    -- 没有移动输入时停止奔跑
    local len = math.sqrt(moveInput.x * moveInput.x + moveInput.y * moveInput.y)
    if len == 0 then
        p.sprinting = false
    end

    -- 归一化并计算速度
    if len > 0 then
        local speed = CONFIG.MoveSpeed
        if p.isGhost then
            speed = speed * 1.3  -- 鬼魂移动稍快
        elseif p.sprinting then
            speed = CONFIG.MoveSpeed * CONFIG.SprintSpeedMultiplier
            -- 6.1 奔跑消耗能量(准备阶段不消耗)
            if gamePhase ~= "prepare" then
                p.energy = clamp(p.energy - CONFIG.SprintCostRate * dt, CONFIG.EnergyMin, CONFIG.EnergyMax)
                if p.energy <= 0 then
                    p.sprinting = false
                    speed = CONFIG.MoveSpeed
                end
            end
        end
        p.vx = (moveInput.x / len) * speed
        p.vy = (moveInput.y / len) * speed
    else
        p.vx = 0
        p.vy = 0
    end

    -- 鬼魂不能朝向/攻击, 只做移动
    if p.isGhost then return end

    -- 朝向控制: 优先右摇杆 > 鼠标 > 左摇杆方向
    local facingSet = false

    -- 手柄右摇杆控制朝向(优先级最高)
    if gamepad then
        local rx = applyDeadzone(gamepad:GetAxisPosition(CONTROLLER_AXIS_RIGHTX))
        local ry = applyDeadzone(gamepad:GetAxisPosition(CONTROLLER_AXIS_RIGHTY))
        if rx ~= 0 or ry ~= 0 then
            p.facing = math.atan(ry, rx)
            facingSet = true
        end
    end

    -- 鼠标朝向(屏幕坐标转世界坐标) - 触控设备跳过,用移动方向控制攻击朝向
    if not facingSet and not isTouchDevice then
        local graphics = GetGraphics()
        local screenW = graphics:GetWidth()
        local screenH = graphics:GetHeight()
        local dpr = graphics:GetDPR()
        local logW = screenW / dpr
        local logH = screenH / dpr

        local mousePos = input:GetMousePosition()
        local mx = mousePos.x / dpr
        local my = mousePos.y / dpr

        -- 屏幕中心到鼠标的方向 = 玩家朝向
        local dx = mx - logW / 2
        local dy = my - logH / 2
        if dx ~= 0 or dy ~= 0 then
            p.facing = math.atan(dy, dx)
            facingSet = true
        end
    end

    -- 如果没有鼠标/右摇杆输入, 用左摇杆移动方向作为朝向
    if not facingSet and moveInput.x ~= 0 or moveInput.y ~= 0 then
        if not facingSet then
            local mLen = math.sqrt(moveInput.x * moveInput.x + moveInput.y * moveInput.y)
            if mLen > 0.3 then
                p.facing = math.atan(moveInput.y, moveInput.x)
            end
        end
    end

    -- 手柄按键: A=攻击, RT(右扳机)也可攻击
    if gamepad then
        if gamepad:GetButtonPress(CONTROLLER_BUTTON_A) then
            if gamePhase == "day" and not inventoryOpen then
                performAttack(p)
            end
        end
        -- RT 扳机攻击(值 > 0.5 视为按下)
        local rt = gamepad:GetAxisPosition(CONTROLLER_AXIS_TRIGGERRIGHT)
        if rt > 0.5 and p.attackCooldown <= 0 and p.attackState == "idle" then
            if gamePhase == "day" and not inventoryOpen then
                performAttack(p)
            end
        end
    end
end

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    -- 初始化随机种子，避免每次启动角色分配相同
    math.randomseed(os.time())

    graphics.windowTitle = CONFIG.Title
    SampleStart()

    -- 创建NanoVG
    nvgContext = nvgCreate(1)
    if nvgContext == nil then
        print("ERROR: Failed to create NanoVG context")
        return
    end

    fontId = nvgCreateFont(nvgContext, "sans", "Fonts/MiSans-Regular.ttf")
    if fontId == -1 then
        print("ERROR: Failed to load font")
    end

    -- 加载猪角色图片
    for i = 1, #PIG_IMAGE_PATHS do
        local img = nvgCreateImage(nvgContext, PIG_IMAGE_PATHS[i], 0)
        if img == 0 or img == -1 then
            print("WARNING: Failed to load pig image: " .. PIG_IMAGE_PATHS[i])
        else
            print("Loaded pig image " .. i .. ": " .. PIG_IMAGE_PATHS[i])
        end
        pigImages[i] = img
    end

    -- 加载小丑猪走路动画帧(16帧)
    for i = 1, #JESTER_WALK_FRAME_PATHS do
        local img = nvgCreateImage(nvgContext, JESTER_WALK_FRAME_PATHS[i], 0)
        if img == 0 or img == -1 then
            print("WARNING: Failed to load walk frame " .. i .. ": " .. JESTER_WALK_FRAME_PATHS[i])
        else
            print("Loaded jester walk frame " .. i)
        end
        jesterWalkFrames[i] = img
    end

    -- 加载小丑猪待机动画帧(8帧)
    for i = 1, #JESTER_IDLE_FRAME_PATHS do
        local img = nvgCreateImage(nvgContext, JESTER_IDLE_FRAME_PATHS[i], 0)
        if img == 0 or img == -1 then
            print("WARNING: Failed to load idle frame " .. i .. ": " .. JESTER_IDLE_FRAME_PATHS[i])
        else
            print("Loaded jester idle frame " .. i)
        end
        jesterIdleFrames[i] = img
    end

    -- 加载小丑猪奔跑动画帧(8帧)
    for i = 1, #JESTER_RUN_FRAME_PATHS do
        local img = nvgCreateImage(nvgContext, JESTER_RUN_FRAME_PATHS[i], 0)
        if img == 0 or img == -1 then
            print("WARNING: Failed to load run frame " .. i .. ": " .. JESTER_RUN_FRAME_PATHS[i])
        else
            print("Loaded jester run frame " .. i)
        end
        jesterRunFrames[i] = img
    end

    -- 加载小丑猪喝药动画帧(16帧)
    for i = 1, #JESTER_DRINK_FRAME_PATHS do
        local img = nvgCreateImage(nvgContext, JESTER_DRINK_FRAME_PATHS[i], 0)
        if img == 0 or img == -1 then
            print("WARNING: Failed to load drink frame " .. i .. ": " .. JESTER_DRINK_FRAME_PATHS[i])
        else
            print("Loaded jester drink frame " .. i)
        end
        jesterDrinkFrames[i] = img
    end

    -- 加载小丑猪打击动画帧(8帧)
    for i = 1, #JESTER_ATTACK_FRAME_PATHS do
        local img = nvgCreateImage(nvgContext, JESTER_ATTACK_FRAME_PATHS[i], 0)
        if img == 0 or img == -1 then
            print("WARNING: Failed to load attack frame " .. i .. ": " .. JESTER_ATTACK_FRAME_PATHS[i])
        else
            print("Loaded jester attack frame " .. i)
        end
        jesterAttackFrames[i] = img
    end

    -- 加载小丑猪受击动画帧(8帧)
    for i = 1, #JESTER_HURT_FRAME_PATHS do
        local img = nvgCreateImage(nvgContext, JESTER_HURT_FRAME_PATHS[i], 0)
        if img == 0 or img == -1 then
            print("WARNING: Failed to load hurt frame " .. i .. ": " .. JESTER_HURT_FRAME_PATHS[i])
        else
            print("Loaded jester hurt frame " .. i)
        end
        jesterHurtFrames[i] = img
    end

    -- 加载战士猪走路动画帧(8帧)
    for i = 1, #WARRIOR_WALK_FRAME_PATHS do
        local img = nvgCreateImage(nvgContext, WARRIOR_WALK_FRAME_PATHS[i], 0)
        if img == 0 or img == -1 then
            print("WARNING: Failed to load warrior walk frame " .. i .. ": " .. WARRIOR_WALK_FRAME_PATHS[i])
        else
            print("Loaded warrior walk frame " .. i)
        end
        warriorWalkFrames[i] = img
    end

    -- 加载战士猪待机动画帧(4帧)
    for i = 1, #WARRIOR_IDLE_FRAME_PATHS do
        local img = nvgCreateImage(nvgContext, WARRIOR_IDLE_FRAME_PATHS[i], 0)
        if img == 0 or img == -1 then
            print("WARNING: Failed to load warrior idle frame " .. i .. ": " .. WARRIOR_IDLE_FRAME_PATHS[i])
        else
            print("Loaded warrior idle frame " .. i)
        end
        warriorIdleFrames[i] = img
    end

    -- 加载科学家猪走路动画帧(8帧)
    for i = 1, #SCIENTIST_WALK_FRAME_PATHS do
        local img = nvgCreateImage(nvgContext, SCIENTIST_WALK_FRAME_PATHS[i], 0)
        if img == 0 or img == -1 then
            print("WARNING: Failed to load scientist walk frame " .. i .. ": " .. SCIENTIST_WALK_FRAME_PATHS[i])
        else
            print("Loaded scientist walk frame " .. i)
        end
        scientistWalkFrames[i] = img
    end

    -- 加载矿工猪走路动画帧(16帧)
    for i = 1, #MINER_WALK_FRAME_PATHS do
        local img = nvgCreateImage(nvgContext, MINER_WALK_FRAME_PATHS[i], 0)
        if img == 0 or img == -1 then
            print("WARNING: Failed to load miner walk frame " .. i .. ": " .. MINER_WALK_FRAME_PATHS[i])
        else
            print("Loaded miner walk frame " .. i)
        end
        minerWalkFrames[i] = img
    end

    -- 加载矿工猪打击动画帧(8帧)
    for i = 1, #MINER_ATTACK_FRAME_PATHS do
        local img = nvgCreateImage(nvgContext, MINER_ATTACK_FRAME_PATHS[i], 0)
        if img == 0 or img == -1 then
            print("WARNING: Failed to load miner attack frame " .. i .. ": " .. MINER_ATTACK_FRAME_PATHS[i])
        else
            print("Loaded miner attack frame " .. i)
        end
        minerAttackFrames[i] = img
    end

    -- 加载矿工猪待机动画帧(8帧)
    for i = 1, #MINER_IDLE_FRAME_PATHS do
        local img = nvgCreateImage(nvgContext, MINER_IDLE_FRAME_PATHS[i], 0)
        if img == 0 or img == -1 then
            print("WARNING: Failed to load miner idle frame " .. i .. ": " .. MINER_IDLE_FRAME_PATHS[i])
        else
            print("Loaded miner idle frame " .. i)
        end
        minerIdleFrames[i] = img
    end

    -- 加载盗贼猪走路动画帧(8帧)
    for i = 1, #THIEF_WALK_FRAME_PATHS do
        local img = nvgCreateImage(nvgContext, THIEF_WALK_FRAME_PATHS[i], 0)
        if img == 0 or img == -1 then
            print("WARNING: Failed to load thief walk frame " .. i .. ": " .. THIEF_WALK_FRAME_PATHS[i])
        else
            print("Loaded thief walk frame " .. i)
        end
        thiefWalkFrames[i] = img
    end

    -- 加载鬼魂图片
    ghostImage = nvgCreateImage(nvgContext, GHOST_IMAGE_PATH, 0)
    if ghostImage == 0 or ghostImage == -1 then
        print("WARNING: Failed to load ghost image: " .. GHOST_IMAGE_PATH)
        ghostImage = nil
    else
        print("Loaded ghost image: " .. GHOST_IMAGE_PATH)
    end

    -- 加载自定义鼠标光标图片
    cursorImage = nvgCreateImage(nvgContext, CURSOR_IMAGE_PATH, 0)
    if cursorImage == 0 or cursorImage == -1 then
        print("WARNING: Failed to load cursor image: " .. CURSOR_IMAGE_PATH)
        cursorImage = nil
    else
        print("Loaded cursor image: " .. CURSOR_IMAGE_PATH)
        input.mouseVisible = false  -- 隐藏系统光标
    end

    -- 加载药水图标图片(用于NanoVG手机端道具按钮和头顶指示器)
    for key, path in pairs(POTION_IMAGE_PATHS) do
        local img = nvgCreateImage(nvgContext, path, 0)
        if img == 0 or img == -1 then
            print("WARNING: Failed to load potion image: " .. path)
            potionNvgImages[key] = nil
        else
            potionNvgImages[key] = img
            print("Loaded potion image: " .. key .. " -> " .. path)
        end
    end

    -- 加载地形贴图(NVG_IMAGE_REPEATX | NVG_IMAGE_REPEATY = 1|2 = 3)
    for name, path in pairs(TERRAIN_PATHS) do
        local img = nvgCreateImage(nvgContext, path, 3)
        if img == 0 or img == -1 then
            print("WARNING: Failed to load terrain: " .. path)
            terrainImages[name] = nil
        else
            terrainImages[name] = img
            print("Loaded terrain: " .. name)
        end
    end

    -- 加载14种装饰物件贴图
    for _, asset in ipairs(OBJ_ASSET_PATHS) do
        local img = nvgCreateImage(nvgContext, asset.path, 0)
        if img == 0 or img == -1 then
            print("WARNING: Failed to load obj asset: " .. asset.path)
        else
            if not objAssetImages[asset.type] then
                objAssetImages[asset.type] = {}
            end
            objAssetImages[asset.type][asset.variant] = img
            print("Loaded obj asset: " .. asset.type .. " v" .. asset.variant)
        end
    end

    -- 初始化关卡编辑器
    levelEditor = LevelEditor.New(nvgContext, {
        mapPixelSize = math.ceil(circleInitRadius * 2),  -- 覆盖整个毒圈活动范围
        mapCenter = { x = CONFIG.MapSize / 2, y = CONFIG.MapSize / 2 },  -- 游戏地图中心
        camera = camera,
        circle = circle,
    })

    -- 初始化2D可视化IDE (F4切换, 含关卡编辑器)
    IDEMain.Init(nvgContext, { levelEditor = levelEditor })

    -- 初始化UI
    InitGameUI()

    -- 鼠标模式
    SampleInitMouseMode(MM_FREE)

    -- 10.2 初始化音效节点(纯2D游戏无scene_,手动创建)
    scene_ = Scene()
    sfxNode = scene_:CreateChild("SFX")

    -- 播放背景音乐(播放列表: 第一首播完后自动播第二首,第二首循环)
    local bgmNode = scene_:CreateChild("BGM")
    bgmSource = bgmNode:CreateComponent("SoundSource")
    bgmSource:SetSoundType("Music")
    bgmSource:SetGain(0.5)
    playBgmTrack(1)

    -- 订阅事件
    SubscribeToEvent(nvgContext, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("MouseWheel", "HandleMouseWheel")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")
    SubscribeToEvent("TouchMove", "HandleTouchMove")

    -- 文本输入事件（导入对话框数字输入）
    SubscribeToEvent("TextInput", "HandleTextInput")

    -- 手柄连接/断开事件
    SubscribeToEvent("JoystickConnected", "HandleJoystickConnected")
    SubscribeToEvent("JoystickDisconnected", "HandleJoystickDisconnected")

    -- 启动时检测已连接的手柄
    for i = 0, input.numJoysticks - 1 do
        local js = input:GetJoystickByIndex(i)
        if js and js:IsController() then
            print("[手柄] 检测到已连接手柄: " .. js.name)
        end
    end

    print("=== 《道友请留步》已启动 ===")
end

function Stop()
    UI.Shutdown()
    if nvgContext then
        nvgDelete(nvgContext)
        nvgContext = nil
    end
end

-- ============================================================================
-- UI 系统
-- ============================================================================

function InitGameUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    uiRoot_ = UI.Panel {
        id = "gameUI",
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            -- 开始菜单
            CreateMenuPanel(),
            -- HUD (游戏中显示)
            CreateHUDPanel(),
            -- 背包面板
            CreateInventoryPanel(),
        }
    }
    UI.SetRoot(uiRoot_)
end

function CreateMenuPanel()
    return UI.Panel {
        id = "menuPanel",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "flex-end",
        alignItems = "center",
        backgroundImage = "image/封面.png",
        backgroundFit = "cover",
        onClick = function(self)
            startGame()
        end,
        children = {}
    }
end

function CreateHUDPanel()
    return UI.Panel {
        id = "hudPanel",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        pointerEvents = "box-none",
        children = {
            -- 左上: 毒药/能量条
            UI.Panel {
                position = "absolute",
                top = 12, left = 12,
                gap = 6,
                padding = 10,
                backgroundColor = { 0, 0, 0, 160 },
                borderRadius = 8,
                pointerEvents = "none",
                children = {
                    UI.Label { id = "poisonLabel", text = "毒药: 0/100", fontSize = 13, fontColor = { 180, 50, 255, 255 } },
                    UI.Label { id = "energyLabel", text = "能量: 100/100", fontSize = 13, fontColor = { 50, 200, 255, 255 } },
                },
            },
            -- 右上: 回合信息
            UI.Panel {
                position = "absolute",
                top = 12, right = 12,
                gap = 4,
                padding = 10,
                backgroundColor = { 0, 0, 0, 160 },
                borderRadius = 8,
                alignItems = "flex-end",
                pointerEvents = "none",
                children = {
                    UI.Label { id = "roundLabel", text = "剩余 5 天", fontSize = 14, fontColor = { 255, 220, 100, 255 } },
                    UI.Label { id = "timerLabel", text = "", fontSize = 20, fontColor = { 255, 80, 80, 255 } },
                    UI.Label { id = "aliveLabel", text = "存活: 6", fontSize = 12, fontColor = { 200, 200, 200, 200 } },
                },
            },
            -- 底部中央: 提示
            UI.Label {
                id = "tipLabel",
                text = "",
                fontSize = 14,
                fontColor = { 255, 255, 200, 220 },
                position = "absolute",
                bottom = 30,
                left = 0, right = 0,
                textAlign = "center",
                pointerEvents = "none",
            },
        }
    }
end

function CreateInventoryPanel()
    return UI.Panel {
        id = "inventoryPanel",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 120 },
        children = {
            -- 背包容器(使用背包图片作为背景)
            UI.Panel {
                width = 260, height = 300,
                alignItems = "center",
                justifyContent = "center",
                backgroundImage = "image/ui/背包.png",
                backgroundFit = "contain",
                children = {
                    -- 内容区域(偏移到背包图片的"口袋"区域)
                    UI.Panel {
                        width = 160, height = 180,
                        marginTop = 30,
                        gap = 8,
                        alignItems = "center",
                        justifyContent = "center",
                        children = {
                            UI.Label {
                                text = "药剂状态",
                                fontSize = 16,
                                fontColor = { 220, 200, 180, 255 },
                            },
                            -- 药剂图标槽
                            UI.Panel {
                                id = "invSlot",
                                width = 72, height = 72,
                                justifyContent = "center",
                                alignItems = "center",
                                backgroundColor = { 30, 25, 20, 160 },
                                borderRadius = 6,
                                borderWidth = 2,
                                borderColor = { 100, 80, 50, 180 },
                                children = {
                                    UI.Panel {
                                        id = "invPotionIcon",
                                        width = 56, height = 56,
                                        visible = false,
                                        backgroundFit = "contain",
                                    },
                                    UI.Label {
                                        id = "invItemLabel",
                                        text = "无药剂",
                                        fontSize = 13,
                                        fontColor = { 160, 140, 120, 200 },
                                    },
                                }
                            },
                            UI.Label {
                                id = "invDesc",
                                text = "黑夜时获得药剂",
                                fontSize = 10,
                                fontColor = { 140, 120, 100, 180 },
                            },
                            UI.Button {
                                id = "drinkAntidoteBtn",
                                text = "喝解药",
                                visible = false,
                                onClick = function(self)
                                    useItem()
                                end,
                            },
                            UI.Button {
                                id = "drinkPoisonBtn",
                                text = "喝毒药",
                                visible = false,
                                onClick = function(self)
                                    useItem()
                                end,
                            },
                            UI.Label {
                                text = "按 TAB 关闭",
                                fontSize = 10,
                                fontColor = { 120, 100, 80, 150 },
                            },
                        }
                    }
                }
            }
        }
    }
end

-- ============================================================================
-- 游戏流程控制
-- ============================================================================

function startGame()
    currentRound = 0
    circle.radius = circleInitRadius
    circle.targetRadius = circleInitRadius
    circle.shrinkSpeed = 0
    settleDeaths = {}
    victoryPotionGiven = false
    victoryWinnerIdx = nil

    initPlayers()

    -- 显示HUD，隐藏菜单
    local menu = uiRoot_:FindById("menuPanel")
    if menu then menu:SetVisible(false) end
    local hud = uiRoot_:FindById("hudPanel")
    if hud then hud:SetVisible(true) end


    -- 直接进入第一轮白天(无准备阶段)
    isFirstRound = false
    enterDay()
end

function restartGame()
    startGame()
end

function useItem(potionType)
    local p = players[localPlayerIdx]
    if not p or not p.alive then return end
    -- 5.2 使用startDrinking开始读条
    local drinkType = potionType or p.potionState
    if not drinkType then return end
    -- 胜利药水可在任何阶段使用, 其他药只能白天
    if drinkType ~= "victory" and gamePhase ~= "day" then return end
    if startDrinking(p, drinkType) then
        updateInventoryUI()
    end
end

function updateInventoryUI()
    local p = players[localPlayerIdx]
    if not p then return end

    local itemLabel = uiRoot_:FindById("invItemLabel")
    local potionIcon = uiRoot_:FindById("invPotionIcon")
    local drinkAntidoteBtn = uiRoot_:FindById("drinkAntidoteBtn")
    local drinkPoisonBtn = uiRoot_:FindById("drinkPoisonBtn")
    local desc = uiRoot_:FindById("invDesc")

    local isDrinking = p.drinkingState == "drinking"
    local isStunned = p.drinkingState == "stunned"
    local isAttacking = p.attackState ~= "idle"
    local noEnergy = p.energy < CONFIG.DrinkCostEnergy
    -- 按钮不可用条件: 正在喝药/硬直/攻击中/能量不足(胜利药水不检查能量)
    local cantDrink = isDrinking or isStunned or isAttacking
    local cantDrinkNormal = cantDrink or noEnergy

    -- 显示/隐藏药水图标
    if p.potionState and POTION_IMAGE_PATHS[p.potionState] then
        if potionIcon then
            potionIcon:SetBackgroundImage(POTION_IMAGE_PATHS[p.potionState])
            potionIcon:SetVisible(true)
        end
        if itemLabel then itemLabel:SetVisible(false) end
    else
        if potionIcon then potionIcon:SetVisible(false) end
        if itemLabel then itemLabel:SetVisible(true) end
    end

    if p.potionState == "victory" then
        if itemLabel then itemLabel:SetText("胜利药水") end
        if drinkAntidoteBtn then
            drinkAntidoteBtn:SetVisible(true)
            drinkAntidoteBtn:SetText("喝下胜利药水")
            drinkAntidoteBtn:SetDisabled(cantDrink)
        end
        if drinkPoisonBtn then drinkPoisonBtn:SetVisible(false) end
        if desc then desc:SetText("喝下即可获胜! 右键/点击道具按钮使用") end
    elseif p.potionState == "antidote" then
        if itemLabel then itemLabel:SetText("解药") end
        if drinkAntidoteBtn then
            drinkAntidoteBtn:SetVisible(true)
            drinkAntidoteBtn:SetDisabled(cantDrinkNormal)
        end
        if drinkPoisonBtn then drinkPoisonBtn:SetVisible(false) end
        if noEnergy and not cantDrink then
            if desc then desc:SetText("能量不足(需要10)!") end
        else
            if desc then desc:SetText("读条1.5秒解毒! 被打断掉落") end
        end
    elseif p.potionState == "poison" then
        if itemLabel then itemLabel:SetText("毒药") end
        if drinkPoisonBtn then
            drinkPoisonBtn:SetVisible(true)
            drinkPoisonBtn:SetDisabled(cantDrinkNormal)
        end
        if drinkAntidoteBtn then drinkAntidoteBtn:SetVisible(false) end
        if noEnergy and not cantDrink then
            if desc then desc:SetText("能量不足(需要10)!") end
        else
            if desc then desc:SetText("喝毒药: 被打断可转移毒素!") end
        end
    else
        if itemLabel then itemLabel:SetText("无药剂") end
        if drinkAntidoteBtn then drinkAntidoteBtn:SetVisible(false) end
        if drinkPoisonBtn then drinkPoisonBtn:SetVisible(false) end
        if desc then
            if isDrinking then
                desc:SetText("读条中...")
            elseif isStunned then
                desc:SetText("硬直中!")
            else
                desc:SetText("黑夜时获得药剂")
            end
        end
    end
end

function updateHUD()
    local p = players[localPlayerIdx]
    if not p then return end

    -- settle阶段隐藏HUD(全黑屏幕只显示NanoVG倒计时/淘汰页面)
    local hudPanel = uiRoot_:FindById("hudPanel")
    if hudPanel then
        local shouldHide = (gamePhase == "settle")
        hudPanel:SetVisible(not shouldHide)
    end
    if gamePhase == "settle" then
        return
    end

    local poisonLabel = uiRoot_:FindById("poisonLabel")
    if poisonLabel then
        poisonLabel:SetText("毒药: " .. math.floor(p.poison) .. "/" .. CONFIG.PoisonMax)
    end
    local energyLabel = uiRoot_:FindById("energyLabel")
    if energyLabel then
        energyLabel:SetText("能量: " .. math.floor(p.energy) .. "/" .. CONFIG.EnergyMax)
    end
    local roundLabel = uiRoot_:FindById("roundLabel")
    if roundLabel then
        local phaseText = ""
        if gamePhase == "prepare" then
            phaseText = " [准备]"
        elseif gamePhase == "day" then
            phaseText = " [白天]"
        elseif gamePhase == "settle" then
            phaseText = " [结算]"
        elseif gamePhase == "shrinking" then
            phaseText = " [缩圈]"
        end
        local remainDays = CONFIG.TotalRounds - currentRound + 1
        roundLabel:SetText("剩余 " .. remainDays .. " 天" .. phaseText)
    end
    local timerLabel = uiRoot_:FindById("timerLabel")
    if timerLabel then
        if gamePhase == "prepare" or gamePhase == "day" or gamePhase == "shrinking" then
            timerLabel:SetText(math.ceil(phaseTimer) .. "s")
        else
            timerLabel:SetText("")
        end
    end
    local aliveLabel = uiRoot_:FindById("aliveLabel")
    if aliveLabel then
        aliveLabel:SetText("存活: " .. getAliveCount() .. "/" .. CONFIG.PlayerCount)
    end
end

-- ============================================================================
-- 事件处理
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- IDE更新(激活时拦截游戏输入, 含关卡编辑器)
    if IDEMain.IsActive() then
        local dpr = graphics:GetDPR()
        IDEMain.Update(dt, input, dpr)
        return  -- IDE激活时暂停游戏逻辑
    end

    -- 关卡编辑器独立模式(IDE未激活时的兼容路径)
    if levelEditor and levelEditor:IsActive() then
        local dpr = graphics:GetDPR()
        levelEditor:Update(dt, input, dpr)
        return
    end

    -- 背景音乐切歌检测(仅游戏运行时)
    updateBgm()

    -- 10.2 毒值警告cooldown
    if poisonWarnCooldown > 0 then poisonWarnCooldown = poisonWarnCooldown - dt end

    -- 舒适区冷却计时器更新
    for _, zone in ipairs(comfortZones) do
        if (zone.zoneCooldown or 0) > 0 then
            zone.zoneCooldown = zone.zoneCooldown - dt
            if zone.zoneCooldown <= 0 then
                zone.zoneCooldown = 0
                -- 冷却结束, 如果还有剩余次数则恢复能量
                if (zone.zoneUsesLeft or 0) > 0 then
                    zone.zoneEnergy = 100
                end
            end
        end
    end

    if gamePhase == "menu" then
        return
    end

    if gamePhase == "victory" or gamePhase == "defeat" then
        return
    end

    -- 结算阶段: 强制停止, 只更新计时器
    if gamePhase == "settle" then
        phaseTimer = phaseTimer - dt
        -- 倒计时音效: 每秒播放一次tick
        if settleSubPhase == "countdown" then
            local curSec = math.ceil(phaseTimer)
            if curSec ~= countdownLastSecond and curSec >= 1 and curSec <= 5 then
                countdownLastSecond = curSec
                playSound("sfx_tick", 0.8)
            end
        end
        if phaseTimer <= 0 then
            if settleSubPhase == "countdown" then
                -- 倒计时结束 → 执行淘汰
                enterSettleElimination()
            else
                -- 淘汰展示结束
                if victoryPotionGiven then
                    -- 胜利药水已发放, 直接进入白天让玩家喝药(不走正常enterDay流程)
                    gamePhase = "day"
                    phaseTimer = 30  -- 给30秒喝药
                    print("=== 胜利药水已发放, 等待喝下... ===")
                else
                    enterShrinking()
                end
            end
        end
        -- settle阶段不接受移动/攻击输入, 但更新视觉
        updateParticles(dt)
        updateDeathPieces(dt)
        updateAttackEffects(dt)
        updateFloatingTexts(dt)
        updateScreenShake(dt)
        for i = #statusEffects, 1, -1 do
            statusEffects[i].timer = statusEffects[i].timer - dt
            if statusEffects[i].timer <= 0 then table.remove(statusEffects, i) end
        end
        for i = #pickupGlows, 1, -1 do
            pickupGlows[i].timer = pickupGlows[i].timer - dt
            if pickupGlows[i].timer <= 0 then table.remove(pickupGlows, i) end
        end
        updateCamera()
        updateHUD()
        return
    end



    -- 玩家输入(prepare/night/shrinking均可移动)
    if not inventoryOpen then
        handlePlayerInput(dt)
    else
        -- 背包打开时每帧刷新按钮disabled状态(攻击后摇结束后立即可点)
        updateInventoryUI()
    end

    -- 手柄按键轮询(非移动操作: 背包/交互/使用物品等)
    local gamepad = getGamepad()
    if gamepad then
        local p = players[localPlayerIdx]
        if p and p.alive then
            -- Y键 = 打开/关闭背包(TAB)
            if gamepad:GetButtonPress(CONTROLLER_BUTTON_Y) then
                if gamePhase ~= "menu" and gamePhase ~= "victory" then
                    inventoryOpen = not inventoryOpen
                    local invPanel = uiRoot_:FindById("inventoryPanel")
                    if invPanel then invPanel:SetVisible(inventoryOpen) end
                    if inventoryOpen then updateInventoryUI() end
                end
            end
            -- X键 = 交互(E键)
            if gamepad:GetButtonPress(CONTROLLER_BUTTON_X) then
                if gamePhase == "day" then
                    if p.interactState == "idle" then
                        local targetIdx = findNearestInteractable(p)
                        if targetIdx then requestInteract(p, targetIdx) end
                    elseif p.interactState == "pending" then
                        acceptInteract(p)
                    end
                end
            end
            -- B键 = 使用物品/取消交互
            if gamepad:GetButtonPress(CONTROLLER_BUTTON_B) then
                if p.interactState ~= "idle" then
                    cancelInteract(p)
                elseif p.potionState and gamePhase == "day" then
                    useItem()
                elseif inventoryOpen then
                    inventoryOpen = false
                    local invPanel = uiRoot_:FindById("inventoryPanel")
                    if invPanel then invPanel:SetVisible(false) end
                end
            end
            -- DPAD UP/DOWN = 交互中选择给予解药/毒药(1/2键)
            if p.interactState == "interacting" and p.potionState then
                if gamepad:GetButtonPress(CONTROLLER_BUTTON_DPAD_UP) then
                    giveItem(p, "antidote")
                elseif gamepad:GetButtonPress(CONTROLLER_BUTTON_DPAD_DOWN) then
                    giveItem(p, "poison")
                end
            end
            -- START键 = 开始游戏(菜单界面)
            if gamepad:GetButtonPress(CONTROLLER_BUTTON_START) then
                if gamePhase == "menu" then
                    startGame()
                end
            end
        elseif gamePhase == "menu" then
            -- 菜单界面任意按键开始
            if gamepad:GetButtonPress(CONTROLLER_BUTTON_A) or gamepad:GetButtonPress(CONTROLLER_BUTTON_START) then
                startGame()
            end
        end
    end

    -- 游戏阶段逻辑
    if gamePhase == "prepare" then
        phaseTimer = phaseTimer - dt
        if phaseTimer <= 0 then
            enterDay()
        end
    elseif gamePhase == "day" then
        phaseTimer = phaseTimer - dt
        -- 9.1 白天期间渐进缩圈(60秒内平滑收缩至目标半径)
        if circle.radius > circle.targetRadius and circle.shrinkSpeed > 0 then
            circle.radius = circle.radius - circle.shrinkSpeed * dt
            if circle.radius <= circle.targetRadius then
                circle.radius = circle.targetRadius
            end
        end
        if phaseTimer <= 0 then
            if victoryPotionGiven then
                -- 胜利药水阶段: 不进settle, 持续等待喝药
                phaseTimer = 30
            else
                enterSettle()
            end
        end
    elseif gamePhase == "shrinking" then
        phaseTimer = phaseTimer - dt
        -- shrinking阶段仅作过渡(1秒), 不再做半径变化
        -- 缩圈过渡结束 → 下一轮白天开始(缩圈在day阶段60s内渐进完成)
        if phaseTimer <= 0 then
            enterDay()
        end
    end

    -- 更新所有玩家
    updatePlayers(dt)
    -- 5.3 更新地面药剂(拾取检测, 仅day阶段)
    if gamePhase == "day" then
        updateGroundPotions(dt)
    end
    updateParticles(dt)
    updateDeathPieces(dt)
    updateAttackEffects(dt)
    updateFloatingTexts(dt)
    updateScreenShake(dt)
    -- 更新状态特效
    for i = #statusEffects, 1, -1 do
        statusEffects[i].timer = statusEffects[i].timer - dt
        if statusEffects[i].timer <= 0 then
            table.remove(statusEffects, i)
        end
    end
    -- 更新物品光效
    for i = #pickupGlows, 1, -1 do
        pickupGlows[i].timer = pickupGlows[i].timer - dt
        if pickupGlows[i].timer <= 0 then
            table.remove(pickupGlows, i)
        end
    end
    updateCamera()

    -- 更新HUD
    updateHUD()

    -- 检查胜利/失败
    if gamePhase ~= "victory" and gamePhase ~= "defeat" then
        local aliveCount = getAliveCount()
        if aliveCount == 0 then
            gamePhase = "defeat"
            local hud = uiRoot_:FindById("hudPanel")
            if hud then hud:SetVisible(false) end
        elseif aliveCount == 1 and not victoryPotionGiven then
            -- 发放胜利药水给最后存活者
            for i = 1, #players do
                if players[i].alive then
                    victoryWinnerIdx = i
                    players[i].potionState = "victory"
                    players[i].poison = 0
                    victoryPotionGiven = true
                    table.insert(statusEffects, { playerIdx = i, type = "detox", timer = 3.0 })
                    print("=== 玩家 " .. i .. " 获得胜利药水! ===")
                    break
                end
            end
        end
    end

    -- 玩家死亡检查
    local lp = players[localPlayerIdx]
    if lp and not lp.alive and gamePhase ~= "victory" and gamePhase ~= "defeat" then
        -- 玩家死了但游戏未结束，可以观战
        local tipLabel = uiRoot_:FindById("tipLabel")
        if tipLabel then tipLabel:SetText("你已被淘汰，观战中...") end
    end
end

---@param eventType string
---@param eventData MouseButtonDownEventData
function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()

    -- IDE激活时拦截鼠标(含关卡编辑器)
    if IDEMain.IsActive() then
        IDEMain.HandleMouseDown(button)
        return
    end

    -- 关卡编辑器独立模式
    if levelEditor and levelEditor:IsActive() then
        levelEditor:HandleMouseDown(button)
        return
    end

    if button == MOUSEB_LEFT then
        -- 胜利/失败画面: 检测返回主页按钮点击
        if gamePhase == "victory" or gamePhase == "defeat" then
            local graphics = GetGraphics()
            local dpr = graphics:GetDPR()
            local mx = input:GetMousePosition().x / dpr
            local my = input:GetMousePosition().y / dpr
            local r = backToMenuBtnRect
            if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                backToMenu()
            end
            return
        end

        if gamePhase == "day" then
            if not inventoryOpen then
                local p = players[localPlayerIdx]
                if p and p.alive then
                    performAttack(p)
                end
            end
        end
    elseif button == MOUSEB_RIGHT then
        -- 背包中右键使用物品
        if inventoryOpen then
            useItem()
        end
    end
end

function HandleMouseUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    -- IDE激活时拦截鼠标(含关卡编辑器)
    if IDEMain.IsActive() then
        IDEMain.HandleMouseUp(button)
        return
    end
    -- 关卡编辑器独立模式
    if levelEditor and levelEditor:IsActive() then
        levelEditor:HandleMouseUp(button)
        return
    end
end

function HandleMouseWheel(eventType, eventData)
    local wheel = eventData["Wheel"]:GetInt()
    if IDEMain.IsActive() then
        IDEMain.HandleMouseWheel(wheel)
        return
    end
end

---@param eventType string
---@param eventData TextInputEventData
function HandleTextInput(eventType, eventData)
    local text = eventData["Text"]:GetString()
    -- IDE 激活时转发文本输入
    if IDEMain.IsActive() then
        IDEMain.HandleTextInput(text)
        return
    end
    if levelEditor and levelEditor:IsActive() then
        levelEditor:HandleTextInput(text)
    end
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    -- F3 键: 打开IDE并直接进入关卡模式(快捷入口)
    if key == KEY_F3 then
        if not IDEMain.IsActive() then
            IDEMain.Toggle()                    -- 打开IDE
            IDEMain.SwitchToLevel()             -- 切到关卡模式
        else
            -- IDE已打开时, F3切到关卡模式或关闭IDE
            if IDEMain.GetMode() == "level" then
                IDEMain.Toggle()                -- 关闭IDE
            else
                IDEMain.SwitchToLevel()         -- 切到关卡模式
            end
        end
        -- 暂停/恢复游戏音乐(通过静音实现)
        if bgmSource then
            if IDEMain.IsActive() then
                bgmSource:SetGain(0)
            else
                bgmSource:SetGain(0.5)
            end
        end
        if uiRoot_ then
            local hud = uiRoot_:FindById("hudPanel")
            if hud then hud:SetVisible(not IDEMain.IsActive()) end
            local inv = uiRoot_:FindById("inventoryPanel")
            if inv then inv:SetVisible(false) end
        end
        return
    end

    -- F4 键: 切换2D可视化IDE
    if key == KEY_F4 then
        IDEMain.Toggle()
        print(IDEMain.IsActive() and "[IDE] 已打开 - Tab切模式, 1-6快速创建节点" or "[IDE] 已关闭")
        -- 暂停/恢复游戏音乐(通过静音实现)
        if bgmSource then
            if IDEMain.IsActive() then
                bgmSource:SetGain(0)
            else
                bgmSource:SetGain(0.5)
            end
        end
        if uiRoot_ then
            local hud = uiRoot_:FindById("hudPanel")
            if hud then hud:SetVisible(not IDEMain.IsActive()) end
        end
        return
    end

    -- IDE激活时拦截按键(含关卡编辑器)
    if IDEMain.IsActive() then
        IDEMain.HandleKeyDown(key)
        return
    end

    -- 关卡编辑器独立模式
    if levelEditor and levelEditor:IsActive() then
        if levelEditor:HandleKeyDown(key) then return end
    end

    if key == KEY_TAB then
        if gamePhase ~= "menu" and gamePhase ~= "victory" then
            inventoryOpen = not inventoryOpen
            local invPanel = uiRoot_:FindById("inventoryPanel")
            if invPanel then invPanel:SetVisible(inventoryOpen) end
            if inventoryOpen then
                updateInventoryUI()
            end
        end
    elseif key == KEY_ESCAPE then
        if inventoryOpen then
            inventoryOpen = false
            local invPanel = uiRoot_:FindById("inventoryPanel")
            if invPanel then invPanel:SetVisible(false) end
        end
    elseif key == KEY_E then
        -- 8.1 交互键: E键发起/接受交互
        if gamePhase == "day" then
            local p = players[localPlayerIdx]
            if p and p.alive then
                if p.interactState == "idle" then
                    -- 寻找最近可交互玩家并发起请求
                    local targetIdx = findNearestInteractable(p)
                    if targetIdx then
                        requestInteract(p, targetIdx)
                    end
                elseif p.interactState == "pending" then
                    -- 接受交互请求
                    acceptInteract(p)
                end
            end
        end
    elseif key == KEY_Q then
        -- 8.1 取消交互
        if gamePhase == "day" then
            local p = players[localPlayerIdx]
            if p and p.alive and p.interactState ~= "idle" then
                cancelInteract(p)
            end
        end
    elseif key == KEY_1 then
        -- 8.2 交互中选择给予解药
        if gamePhase == "day" then
            local p = players[localPlayerIdx]
            if p and p.alive and p.interactState == "interacting" and p.potionState then
                giveItem(p, "antidote")
            end
        end
    elseif key == KEY_2 then
        -- 8.2 交互中选择给予毒药
        if gamePhase == "day" then
            local p = players[localPlayerIdx]
            if p and p.alive and p.interactState == "interacting" and p.potionState then
                giveItem(p, "poison")
            end
        end
    end
end

-- ============================================================================
-- 手柄连接/断开事件
-- ============================================================================

function HandleJoystickConnected(eventType, eventData)
    local id = eventData:GetInt("JoystickID")
    local js = input:GetJoystick(id)
    if js then
        if js:IsController() then
            print("[手柄] 手柄已连接: " .. js.name .. " (ID=" .. id .. ")")
        else
            print("[手柄] 摇杆设备已连接: " .. js.name .. " (非标准手柄)")
        end
    end
end

function HandleJoystickDisconnected(eventType, eventData)
    local id = eventData:GetInt("JoystickID")
    print("[手柄] 设备已断开 (ID=" .. id .. ")")
end

-- ============================================================================
-- 触摸事件处理(手机适配)
-- ============================================================================

-- 获取触控按钮区域(基于屏幕逻辑尺寸)
local function getTouchButtonRects(logW, logH)
    local btnSize = 60
    local itemBtnSize = 120  -- 道具按钮放大两倍
    local margin = 20
    local bottomY = logH - margin - btnSize
    -- 右侧: 攻击按钮(右下) + 道具按钮(攻击上方, 放大两倍)
    local rightX = logW - margin - btnSize
    local itemRightX = logW - margin - itemBtnSize
    -- 奔跑按钮(攻击按钮左侧)
    local sprintX = rightX - btnSize - 12
    local sprintY = bottomY
    -- 交换药水按钮(道具按钮左侧)
    local interactX = itemRightX - btnSize - 12
    local interactY = bottomY - itemBtnSize - 15
    -- 拒绝交换按钮(交换按钮左侧)
    local rejectX = interactX - btnSize - 8
    local rejectY = interactY
    return {
        attack = { x = rightX, y = bottomY, w = btnSize, h = btnSize },
        item = { x = itemRightX, y = bottomY - itemBtnSize - 15, w = itemBtnSize, h = itemBtnSize },
        sprint = { x = sprintX, y = sprintY, w = btnSize, h = btnSize },
        interact = { x = interactX, y = interactY, w = btnSize, h = btnSize },
        reject = { x = rejectX, y = rejectY, w = btnSize, h = btnSize },
    }
end

local function pointInRect(px, py, rect)
    return px >= rect.x and px <= rect.x + rect.w and py >= rect.y and py <= rect.y + rect.h
end

---@param eventType string
---@param eventData TouchBeginEventData
function HandleTouchBegin(eventType, eventData)
    isTouchDevice = true
    local touchId = eventData["TouchID"]:GetInt()
    local rawX = eventData["X"]:GetInt()
    local rawY = eventData["Y"]:GetInt()

    local graphics = GetGraphics()
    local dpr = graphics:GetDPR()
    local logW = graphics:GetWidth() / dpr
    local logH = graphics:GetHeight() / dpr
    local tx = rawX / dpr
    local ty = rawY / dpr

    -- IDE激活时: 将触摸转发为鼠标点击给IDE处理
    if IDEMain.IsActive() then
        IDEMain.HandleMouseDown(MOUSEB_LEFT)
        return
    end

    -- 关卡编辑器独立模式
    if levelEditor and levelEditor:IsActive() then
        levelEditor:HandleMouseDown(MOUSEB_LEFT)
        return
    end

    -- 胜利/失败画面: 检测返回主页按钮点击
    if gamePhase == "victory" or gamePhase == "defeat" then
        local r = backToMenuBtnRect
        if tx >= r.x and tx <= r.x + r.w and ty >= r.y and ty <= r.y + r.h then
            backToMenu()
        end
        return
    end

    -- 检查是否点击了右侧按钮
    local rects = getTouchButtonRects(logW, logH)

    if pointInRect(tx, ty, rects.attack) then
        touchButtons.attack.pressed = true
        touchButtons.attack.touchId = touchId
        -- 执行攻击
        if gamePhase == "day" then
            local p = players[localPlayerIdx]
            if p and p.alive and not p.isGhost then
                performAttack(p)
            end
        end
        return
    end

    if pointInRect(tx, ty, rects.item) then
        touchButtons.item.pressed = true
        touchButtons.item.touchId = touchId
        -- 使用背包道具
        if gamePhase == "day" then
            local p = players[localPlayerIdx]
            if p and p.alive and not p.isGhost then
                useItem()
            end
        end
        return
    end

    if pointInRect(tx, ty, rects.sprint) then
        touchButtons.sprint.pressed = true
        touchButtons.sprint.touchId = touchId
        return
    end

    if pointInRect(tx, ty, rects.interact) then
        touchButtons.interact.pressed = true
        touchButtons.interact.touchId = touchId
        -- 交换药水: 发起请求或接受请求
        if gamePhase == "day" then
            local p = players[localPlayerIdx]
            if p and p.alive and not p.isGhost then
                if p.interactState == "pending" then
                    -- 接受对方的交换请求
                    acceptInteract(p)
                elseif p.interactState == "idle" then
                    -- 发起交换请求(找最近的玩家)
                    local bestIdx = -1
                    local bestDist = CONFIG.InteractRange
                    for i = 1, #players do
                        local other = players[i]
                        if other.idx ~= p.idx and other.alive and other.interactState == "idle"
                            and other.drinkingState == "idle" then
                            local d = dist(p.x, p.y, other.x, other.y)
                            if d < bestDist then
                                bestDist = d
                                bestIdx = i
                            end
                        end
                    end
                    if bestIdx > 0 then
                        requestInteract(p, bestIdx)
                    end
                end
            end
        end
        return
    end

    if pointInRect(tx, ty, rects.reject) then
        touchButtons.reject.pressed = true
        touchButtons.reject.touchId = touchId
        -- 拒绝交换药水
        if gamePhase == "day" then
            local p = players[localPlayerIdx]
            if p and p.alive and p.interactState ~= "idle" then
                cancelInteract(p)
            end
        end
        return
    end

    -- 左半屏: 虚拟摇杆
    if tx < logW * 0.5 and not touchJoystick.active then
        touchJoystick.active = true
        touchJoystick.touchId = touchId
        touchJoystick.cx = tx
        touchJoystick.cy = ty
        touchJoystick.dx = 0
        touchJoystick.dy = 0
    end
end

---@param eventType string
---@diagnostic disable-next-line: undefined-doc-name
---@param eventData TouchMoveEventData
function HandleTouchMove(eventType, eventData)
    local touchId = eventData["TouchID"]:GetInt()
    local rawX = eventData["X"]:GetInt()
    local rawY = eventData["Y"]:GetInt()

    local graphics = GetGraphics()
    local dpr = graphics:GetDPR()
    local tx = rawX / dpr
    local ty = rawY / dpr

    -- 更新摇杆
    if touchJoystick.active and touchJoystick.touchId == touchId then
        touchJoystick.dx = tx - touchJoystick.cx
        touchJoystick.dy = ty - touchJoystick.cy
        -- 限制在最大半径内
        local jLen = math.sqrt(touchJoystick.dx * touchJoystick.dx + touchJoystick.dy * touchJoystick.dy)
        if jLen > touchJoystick.radius then
            touchJoystick.dx = touchJoystick.dx / jLen * touchJoystick.radius
            touchJoystick.dy = touchJoystick.dy / jLen * touchJoystick.radius
        end
    end
end

---@param eventType string
---@diagnostic disable-next-line: undefined-doc-name
---@param eventData TouchEndEventData
function HandleTouchEnd(eventType, eventData)
    local touchId = eventData["TouchID"]:GetInt()

    -- 释放按钮
    if touchButtons.attack.touchId == touchId then
        touchButtons.attack.pressed = false
        touchButtons.attack.touchId = -1
    end
    if touchButtons.item.touchId == touchId then
        touchButtons.item.pressed = false
        touchButtons.item.touchId = -1
    end
    if touchButtons.sprint.touchId == touchId then
        touchButtons.sprint.pressed = false
        touchButtons.sprint.touchId = -1
    end
    if touchButtons.interact.touchId == touchId then
        touchButtons.interact.pressed = false
        touchButtons.interact.touchId = -1
    end
    if touchButtons.reject.touchId == touchId then
        touchButtons.reject.pressed = false
        touchButtons.reject.touchId = -1
    end

    -- 释放摇杆
    if touchJoystick.touchId == touchId then
        touchJoystick.active = false
        touchJoystick.touchId = -1
        touchJoystick.dx = 0
        touchJoystick.dy = 0
    end
end


-- ============================================================================
-- 渲染系统(委托 Game/Render 模块)
-- ============================================================================

-- 程序化地形数据(只在游戏开始时生成一次)
local mapDecorations = {}
local groundPatches = {}
local decorationsGenerated = false
local _decoDrawDebugOnce = false

--- 将 main.lua 局部变量同步到 State 共享表(渲染前调用)
local function syncStateForRender()
    State.nvgContext = nvgContext
    State.fontId = fontId
    State.gamePhase = gamePhase
    State.currentRound = currentRound
    State.phaseTimer = phaseTimer
    State.eliminatedIdx = eliminatedIdx
    State.settleDeaths = settleDeaths
    State.settleSubPhase = settleSubPhase
    State.countdownLastSecond = countdownLastSecond
    State.isFirstRound = isFirstRound
    State.victoryWinnerIdx = victoryWinnerIdx
    State.victoryPotionGiven = victoryPotionGiven
    State.statusEffects = statusEffects
    State.pickupGlows = pickupGlows
    State.circle = circle
    State.camera = camera
    State.players = players
    State.localPlayerIdx = localPlayerIdx
    State.inventoryOpen = inventoryOpen
    State.particles = particles
    State.deathPieces = deathPieces
    State.deathStains = deathStains
    State.comfortZones = comfortZones
    State.comfortFloats = comfortFloats
    State.uiRoot_ = uiRoot_
    State.attackEffects = attackEffects
    State.floatingTexts = floatingTexts
    State.groundPotions = groundPotions
    State.screenShake = screenShake
    State.poisonWarnCooldown = poisonWarnCooldown
    State.pigImages = pigImages
    State.ghostImage = ghostImage
    State.cursorImage = cursorImage
    State.potionNvgImages = potionNvgImages
    State.terrainImages = terrainImages
    State.objAssetImages = objAssetImages
    State.jesterWalkFrames = jesterWalkFrames
    State.jesterIdleFrames = jesterIdleFrames
    State.jesterRunFrames = jesterRunFrames
    State.jesterDrinkFrames = jesterDrinkFrames
    State.jesterAttackFrames = jesterAttackFrames
    State.jesterHurtFrames = jesterHurtFrames
    State.warriorWalkFrames = warriorWalkFrames
    State.warriorIdleFrames = warriorIdleFrames
    State.scientistWalkFrames = scientistWalkFrames
    State.minerWalkFrames = minerWalkFrames
    State.minerAttackFrames = minerAttackFrames
    State.minerIdleFrames = minerIdleFrames
    State.thiefWalkFrames = thiefWalkFrames
    State.levelEditor = levelEditor
    State.editorSpawnConfig = editorSpawnConfig
    State.mapDecorations = mapDecorations
    State.groundPatches = groundPatches
    State.decorationsGenerated = decorationsGenerated
    State._decoDrawDebugOnce = _decoDrawDebugOnce
    State.touchJoystick = touchJoystick
    State.touchButtons = touchButtons
end

--- 从 State 同步回 main.lua 局部变量(渲染后调用,渲染模块可能修改了部分状态)
local function syncStateBack()
    -- 渲染模块可能修改的状态
    mapDecorations = State.mapDecorations
    groundPatches = State.groundPatches
    decorationsGenerated = State.decorationsGenerated
    _decoDrawDebugOnce = State._decoDrawDebugOnce
    comfortZones = State.comfortZones
    comfortFloats = State.comfortFloats
    backToMenuBtnRect = State.backToMenuBtnRect
end

-- 编辑器应用时重置装饰生成标记(允许重新生成)
function ResetDecorations()
    decorationsGenerated = false
    mapDecorations = {}
    groundPatches = {}
    State.decorationsGenerated = false
    State.mapDecorations = {}
    State.groundPatches = {}
end

-- 供编辑器导入种子后重新生成装饰物(只含地形物件,不含舒适区)
function RegenerateMapDecorations()
    print("[DEBUG-DECO] RegenerateMapDecorations() 被调用! 重置decorationsGenerated")
    decorationsGenerated = false
    mapDecorations = {}
    groundPatches = {}
    _decoDrawDebugOnce = false
    State.decorationsGenerated = false
    State.mapDecorations = {}
    State.groundPatches = {}
    State._decoDrawDebugOnce = false
end

-- 全局访问函数(供编辑器直接修改真实游戏数据)
function GetMapDecorations()
    return mapDecorations
end

function GetComfortZones()
    return comfortZones
end

-- NanoVG 渲染主入口(委托 Render 模块)
function HandleRender(eventType, eventData)
    syncStateForRender()
    Render.HandleRender(eventType, eventData)
    syncStateBack()
end

-- 返回主页(从胜利/失败画面返回菜单)
function backToMenu()
    gamePhase = "menu"
    -- 显示菜单，隐藏HUD
    local menu = uiRoot_:FindById("menuPanel")
    if menu then menu:SetVisible(true) end
    local hud = uiRoot_:FindById("hudPanel")
    if hud then hud:SetVisible(false) end
    -- 隐藏背包
    inventoryOpen = false
    local invPanel = uiRoot_:FindById("inventoryPanel")
    if invPanel then invPanel:SetVisible(false) end
end
