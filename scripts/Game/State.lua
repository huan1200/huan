-- ============================================================================
-- Game/State.lua
-- 共享可变游戏状态(所有模块通过此表访问和修改状态)
-- ============================================================================

local CONFIG = require("Game.Config")

local circleInitRadius = math.sqrt(CONFIG.MapSize * CONFIG.MapSize * 2) * CONFIG.CircleInitRadiusFactor

---@class GameState
local State = {
    -- NanoVG 上下文
    nvgContext = nil,
    fontId = -1,

    -- 游戏阶段: "menu", "prepare", "day", "settle", "shrinking", "victory", "defeat"
    gamePhase = "menu",
    currentRound = 0,
    phaseTimer = 0,
    eliminatedIdx = -1,
    settleDeaths = {},
    settleSubPhase = "countdown",
    countdownLastSecond = -1,
    backToMenuBtnRect = { x = 0, y = 0, w = 0, h = 0 },
    isFirstRound = true,
    victoryWinnerIdx = nil,
    victoryPotionGiven = false,

    -- 状态特效
    statusEffects = {},
    pickupGlows = {},

    -- 毒圈初始半径(公开字段供外部模块访问)
    circleInitRadius = circleInitRadius,

    -- 毒圈
    circle = {
        cx = CONFIG.MapSize / 2,
        cy = CONFIG.MapSize / 2,
        radius = circleInitRadius,
        targetRadius = circleInitRadius,
        shrinkSpeed = 0,
    },

    -- 相机
    camera = {
        x = CONFIG.MapSize / 2,
        y = CONFIG.MapSize / 2,
    },

    -- 玩家
    players = {},
    localPlayerIdx = 1,

    -- 背包
    inventoryOpen = false,

    -- 粒子效果
    particles = {},

    -- 死亡效果
    deathPieces = {},
    deathStains = {},

    -- 舒适区
    comfortZones = {},
    comfortFloats = {},

    -- UI引用
    uiRoot_ = nil,

    -- 攻击动画
    attackEffects = {},

    -- 浮动文字
    floatingTexts = {},

    -- 地面药剂
    groundPotions = {},

    -- 屏幕震动
    screenShake = { timer = 0, intensity = 0 },

    -- 毒值警告音cooldown
    poisonWarnCooldown = 0,

    -- NVG 图片句柄
    pigImages = {},
    ghostImage = nil,
    cursorImage = nil,
    potionNvgImages = {},
    terrainImages = {},

    -- 动画帧句柄
    jesterWalkFrames = {},
    jesterIdleFrames = {},
    jesterRunFrames = {},
    jesterDrinkFrames = {},
    jesterAttackFrames = {},
    jesterHurtFrames = {},
    warriorWalkFrames = {},
    warriorIdleFrames = {},
    scientistWalkFrames = {},
    minerWalkFrames = {},
    minerAttackFrames = {},
    minerIdleFrames = {},
    thiefWalkFrames = {},

    -- 关卡编辑器
    levelEditor = nil,
    editorSpawnConfig = nil,

    -- 地图装饰(由MapGen生成)
    mapDecorations = nil,
    groundPatches = nil,
    decorationsGenerated = false,
    _decoDrawDebugOnce = false,

    -- Touch/Gamepad 输入
    touchJoystick = {
        active = false,
        touchId = -1,
        cx = 0, cy = 0,
        dx = 0, dy = 0,
        radius = 60,
    },
    touchButtons = {},
    gamepadLeftX = 0,
    gamepadLeftY = 0,
    gamepadRightX = 0,
    gamepadRightY = 0,
}

--- 重置游戏状态(开始新游戏时调用)
function State.reset()
    State.gamePhase = "menu"
    State.currentRound = 0
    State.phaseTimer = 0
    State.eliminatedIdx = -1
    State.settleDeaths = {}
    State.settleSubPhase = "countdown"
    State.countdownLastSecond = -1
    State.isFirstRound = true
    State.victoryWinnerIdx = nil
    State.victoryPotionGiven = false
    State.statusEffects = {}
    State.pickupGlows = {}
    State.circle.radius = circleInitRadius
    State.circle.targetRadius = circleInitRadius
    State.circle.shrinkSpeed = 0
    State.circle.cx = CONFIG.MapSize / 2
    State.circle.cy = CONFIG.MapSize / 2
    State.camera.x = CONFIG.MapSize / 2
    State.camera.y = CONFIG.MapSize / 2
    State.players = {}
    State.inventoryOpen = false
    State.particles = {}
    State.deathPieces = {}
    State.deathStains = {}
    State.comfortZones = {}
    State.comfortFloats = {}
    State.attackEffects = {}
    State.floatingTexts = {}
    State.groundPotions = {}
    State.screenShake = { timer = 0, intensity = 0 }
    State.poisonWarnCooldown = 0
    State.decorationsGenerated = false
    State._decoDrawDebugOnce = false
    State.mapDecorations = nil
    State.groundPatches = nil
end

return State
