-- ============================================================================
-- Game/Animation.lua
-- 动画帧路径定义与NVG资源加载
-- ============================================================================

local Animation = {}

-- 猪角色图片路径(5个角色)
Animation.PIG_IMAGE_PATHS = {
    "image/Image 16.png",        -- 小丑猪
    "image/pig_warrior.png",     -- 战士猪
    "image/pig_scientist.png",   -- 科学家猪
    "image/pig_miner.png",       -- 矿工猪
    "image/pig_thief.png",       -- 盗贼猪
}

Animation.GHOST_IMAGE_PATH = "image/Image 17.png"
Animation.CURSOR_IMAGE_PATH = "image/ui/鼠标.png"

Animation.POTION_IMAGE_PATHS = {
    victory = "image/游戏道具/胜利药水.png",
    antidote = "image/游戏道具/解药.png",
    poison = "image/游戏道具/毒药.png",
}

-- 小丑猪(avatarIdx=1)动画
Animation.JESTER_WALK_FPS = 12
Animation.JESTER_IDLE_FPS = 8
Animation.JESTER_RUN_FPS = 14
Animation.JESTER_DRINK_FPS = 10
Animation.JESTER_ATTACK_FPS = 16
Animation.JESTER_HURT_FPS = 16

-- 战士猪(avatarIdx=2)动画
Animation.WARRIOR_WALK_FPS = 10
Animation.WARRIOR_IDLE_FPS = 6

-- 科学家猪(avatarIdx=3)动画
Animation.SCIENTIST_WALK_FPS = 10

-- 矿工猪(avatarIdx=4)动画
Animation.MINER_WALK_FPS = 12
Animation.MINER_ATTACK_FPS = 16
Animation.MINER_IDLE_FPS = 8

-- 盗贼猪(avatarIdx=5)动画
Animation.THIEF_WALK_FPS = 10

-- 帧路径表(在loadAll中填充)
Animation.framePaths = {}

local function generatePaths()
    local paths = {}

    -- 小丑猪走路(16帧)
    paths.jesterWalk = {}
    for i = 1, 16 do
        paths.jesterWalk[i] = string.format("image/jester_pig_anim/walk/walk_%02d.png", i)
    end
    -- 小丑猪待机(6帧)
    paths.jesterIdle = {}
    for i = 1, 6 do
        paths.jesterIdle[i] = string.format("image/jester_pig_anim/idle/idle_%02d.png", i)
    end
    -- 小丑猪奔跑(8帧)
    paths.jesterRun = {}
    for i = 1, 8 do
        paths.jesterRun[i] = string.format("image/jester_pig_anim/run/run_%02d.png", i)
    end
    -- 小丑猪喝药(16帧)
    paths.jesterDrink = {}
    for i = 1, 16 do
        paths.jesterDrink[i] = string.format("image/jester_pig_anim/drink/drink_%02d.png", i)
    end
    -- 小丑猪攻击(8帧)
    paths.jesterAttack = {}
    for i = 1, 8 do
        paths.jesterAttack[i] = string.format("image/jester_pig_anim/attack/attack_%02d.png", i)
    end
    -- 小丑猪受击(8帧)
    paths.jesterHurt = {}
    for i = 1, 8 do
        paths.jesterHurt[i] = string.format("image/jester_pig_anim/hurt/hurt_%02d.png", i)
    end
    -- 战士猪走路(8帧)
    paths.warriorWalk = {}
    for i = 1, 8 do
        paths.warriorWalk[i] = string.format("image/warrior_pig_anim/walk/walk_%02d.png", i)
    end
    -- 战士猪待机(4帧)
    paths.warriorIdle = {}
    for i = 1, 4 do
        paths.warriorIdle[i] = string.format("image/warrior_pig_anim/idle/idle_%02d.png", i)
    end
    -- 科学家猪走路(8帧)
    paths.scientistWalk = {}
    for i = 1, 8 do
        paths.scientistWalk[i] = string.format("image/scientist_pig_anim/walk/walk_%02d.png", i)
    end
    -- 矿工猪走路(16帧)
    paths.minerWalk = {}
    for i = 1, 16 do
        paths.minerWalk[i] = string.format("image/miner_pig_anim/walk/walk_%02d.png", i)
    end
    -- 矿工猪攻击(8帧)
    paths.minerAttack = {}
    for i = 1, 8 do
        paths.minerAttack[i] = string.format("image/miner_pig_anim/attack/attack_%02d.png", i)
    end
    -- 矿工猪待机(8帧)
    paths.minerIdle = {}
    for i = 1, 8 do
        paths.minerIdle[i] = string.format("image/miner_pig_anim/idle/idle_%02d.png", i)
    end
    -- 盗贼猪走路(8帧)
    paths.thiefWalk = {}
    for i = 1, 8 do
        paths.thiefWalk[i] = string.format("image/thief_pig_anim/walk/walk_%02d.png", i)
    end

    return paths
end

Animation.framePaths = generatePaths()

--- 加载所有动画NVG图片资源
---@param vg any NanoVG上下文
---@param state table GameState表(图片句柄存入此处)
function Animation.loadAll(vg, state)
    -- 角色静态图片
    state.pigImages = {}
    for i, path in ipairs(Animation.PIG_IMAGE_PATHS) do
        state.pigImages[i] = nvgCreateImage(vg, path, 0)
    end
    state.ghostImage = nvgCreateImage(vg, Animation.GHOST_IMAGE_PATH, 0)
    state.cursorImage = nvgCreateImage(vg, Animation.CURSOR_IMAGE_PATH, 0)

    -- 药剂图片
    state.potionNvgImages = {}
    for k, path in pairs(Animation.POTION_IMAGE_PATHS) do
        state.potionNvgImages[k] = nvgCreateImage(vg, path, 0)
    end

    -- 帧动画
    local paths = Animation.framePaths

    local function loadFrames(pathList)
        local frames = {}
        for i, path in ipairs(pathList) do
            frames[i] = nvgCreateImage(vg, path, 0)
        end
        return frames
    end

    state.jesterWalkFrames = loadFrames(paths.jesterWalk)
    state.jesterIdleFrames = loadFrames(paths.jesterIdle)
    state.jesterRunFrames = loadFrames(paths.jesterRun)
    state.jesterDrinkFrames = loadFrames(paths.jesterDrink)
    state.jesterAttackFrames = loadFrames(paths.jesterAttack)
    state.jesterHurtFrames = loadFrames(paths.jesterHurt)
    state.warriorWalkFrames = loadFrames(paths.warriorWalk)
    state.warriorIdleFrames = loadFrames(paths.warriorIdle)
    state.scientistWalkFrames = loadFrames(paths.scientistWalk)
    state.minerWalkFrames = loadFrames(paths.minerWalk)
    state.minerAttackFrames = loadFrames(paths.minerAttack)
    state.minerIdleFrames = loadFrames(paths.minerIdle)
    state.thiefWalkFrames = loadFrames(paths.thiefWalk)
end

return Animation
