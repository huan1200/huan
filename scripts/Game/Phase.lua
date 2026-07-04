-- ============================================================================
-- Game/Phase.lua - 游戏阶段管理
-- 负责: 准备阶段、白天阶段、结算阶段、缩圈过渡
-- ============================================================================

local CONFIG = require("Game.Config")
local State = require("Game.State")
local Utils = require("Game.Utils")
local Audio = require("Game.Audio")

local Phase = {}

-- 外部注入的函数引用（避免循环依赖）
Phase.spawnDeathEffect = nil     -- Player.spawnDeathEffect
Phase.generateComfortZones = nil -- ComfortZone.generate

-- ============================================================================
-- 辅助
-- ============================================================================

local function getAliveCount()
    local count = 0
    for i = 1, #State.players do
        if State.players[i].alive then count = count + 1 end
    end
    return count
end

-- ============================================================================
-- 3.1 准备阶段(仅开局一次, 10s, 只能移动)
-- ============================================================================

function Phase.enterPrepare()
    State.gamePhase = "prepare"
    State.phaseTimer = CONFIG.PrepareDuration
    State.isFirstRound = true
    State.currentRound = 0
    print("=== 准备阶段! 黑夜即将降临... " .. CONFIG.PrepareDuration .. "s ===")
end

-- ============================================================================
-- 白天阶段(60s, 主要战斗时间)
-- ============================================================================

function Phase.enterDay()
    State.gamePhase = "day"
    State.phaseTimer = CONFIG.DayDuration

    -- 胜利药水已发放时不进入新一轮(等待玩家喝药)
    if State.victoryPotionGiven then
        print("=== 胜利药水阶段, 等待喝下... ===")
        State.phaseTimer = 30
        return
    end

    State.currentRound = State.currentRound + 1
    if State.currentRound > CONFIG.TotalRounds then
        local aliveCount = getAliveCount()
        if aliveCount > 0 and not State.victoryPotionGiven then
            -- 最大轮数到达, 给所有存活者中最后一人发胜利药水
            for i = 1, #State.players do
                if State.players[i].alive then
                    State.victoryWinnerIdx = i
                    State.players[i].potionState = "victory"
                    State.players[i].poison = 0
                    State.victoryPotionGiven = true
                    table.insert(State.statusEffects, { playerIdx = i, type = "detox", timer = 3.0 })
                    print("=== 最终轮! 玩家 " .. i .. " 获得胜利药水! ===")
                    break
                end
            end
            State.phaseTimer = 30
        elseif aliveCount == 0 then
            State.gamePhase = "defeat"
        end
        return
    end

    -- 每轮白天开始: 全员+30毒, 旧解药变毒, 50%发解药
    for i = 1, #State.players do
        if State.players[i].alive then
            if State.players[i].potionState == "antidote" then
                State.players[i].potionState = "poison"
                State.players[i].poison = Utils.clamp(State.players[i].poison + CONFIG.PoisonPerRound, CONFIG.PoisonMin, CONFIG.PoisonMax)
                print("玩家 " .. i .. " 解药变为毒药! +30毒")
                if State.players[i].isLocal then Audio.playSound("sfx_antidote_to_poison", 0.7) end
                table.insert(State.statusEffects, { playerIdx = i, type = "transform", timer = 1.5 })
                table.insert(State.floatingTexts, {
                    x = State.players[i].x, y = State.players[i].y - 30,
                    text = "+30毒(变质)", color = {180, 60, 200},
                    timer = 1.2, maxTimer = 1.2,
                })
            end
            State.players[i].poison = Utils.clamp(State.players[i].poison + CONFIG.PoisonPerRound, CONFIG.PoisonMin, CONFIG.PoisonMax)
            State.players[i].drinkingState = "idle"
            State.players[i].drinkingTimer = 0
            State.players[i].drinkingType = nil
        end
    end

    -- 地面未拾取的解药变为地面毒药
    for i = 1, #State.groundPotions do
        if State.groundPotions[i].type == "antidote" then
            State.groundPotions[i].type = "poison"
            print("地面解药变为毒药!")
        end
    end

    -- 50%存活玩家获得解药(向上取整)
    local aliveList = {}
    for i = 1, #State.players do
        if State.players[i].alive then table.insert(aliveList, i) end
    end
    for i = #aliveList, 2, -1 do
        local j = math.random(1, i)
        aliveList[i], aliveList[j] = aliveList[j], aliveList[i]
    end
    local giveCount = math.ceil(#aliveList * CONFIG.AntidoteRatio)
    for k = 1, giveCount do
        local idx = aliveList[k]
        State.players[idx].potionState = "antidote"
        table.insert(State.pickupGlows, { playerIdx = idx, type = "antidote", timer = 1.5, maxTimer = 1.5 })
        if State.players[idx].isLocal then Audio.playSound("sfx_antidote_get", 0.7) end
        print("玩家 " .. idx .. " 获得解药!")
    end

    -- 清除本轮地面药剂
    State.groundPotions = {}

    print("=== 第 " .. State.currentRound .. " 轮 白天开始! 全员+30毒, " .. giveCount .. "人获得解药, " .. CONFIG.DayDuration .. "s 战斗 ===")
end

-- ============================================================================
-- 3.4 黑夜结算(先5s黑屏倒计时, 再3s淘汰展示)
-- ============================================================================

function Phase.enterSettle()
    State.gamePhase = "settle"
    State.settleSubPhase = "countdown"
    State.phaseTimer = CONFIG.NightfallDuration  -- 5s倒计时
    State.countdownLastSecond = -1
    State.settleDeaths = {}
    State.isFirstRound = false

    -- 强制停止所有玩家
    for i = 1, #State.players do
        State.players[i].vx = 0
        State.players[i].vy = 0
    end

    Audio.playSound("sfx_night_transition", 0.9)
    Audio.playSound("sfx_nightfall", 0.8)

    -- 黑夜倒计时专属音乐
    if State.bgmSource then
        local nightBgm = cache:GetResource("Sound", "audio/游戏音乐/黑夜倒计时.ogg")
        if nightBgm then
            nightBgm.looped = false
            State.bgmSource:Play(nightBgm)
            State.bgmCurrentIdx = 0
        end
    end

    print("=== 黑夜降临! " .. CONFIG.NightfallDuration .. "s 黑屏倒计时 ===")
end

-- ============================================================================
-- 倒计时结束后执行淘汰逻辑
-- ============================================================================

function Phase.enterSettleElimination()
    State.settleSubPhase = "elimination"
    State.phaseTimer = CONFIG.SettleDuration  -- 3s淘汰展示

    Audio.playSound("sfx_settle_kill", 0.7)

    -- 淘汰毒素最高的玩家（仅淘汰一人）
    local maxPoison = 0
    local maxIdx = nil
    for i = 1, #State.players do
        if State.players[i].alive and State.players[i].poison > maxPoison then
            maxPoison = State.players[i].poison
            maxIdx = i
        end
    end
    if maxIdx then
        State.players[maxIdx].alive = false
        State.players[maxIdx].isGhost = true
        State.players[maxIdx].vx = 0
        State.players[maxIdx].vy = 0
        table.insert(State.settleDeaths, maxIdx)
        if Phase.spawnDeathEffect then
            Phase.spawnDeathEffect(maxIdx)
        end
        print("玩家 " .. maxIdx .. " 毒素最高(" .. math.floor(State.players[maxIdx].poison) .. "), 被淘汰!")
    end

    -- 存活者提示"存活"
    if #State.settleDeaths > 0 then
        for i = 1, #State.players do
            if State.players[i].alive then
                table.insert(State.statusEffects, { playerIdx = i, type = "detox", timer = 2.0 })
            end
        end
    end

    -- 检查胜利/失败条件
    local aliveCount = getAliveCount()
    if aliveCount == 0 then
        State.gamePhase = "defeat"
        print("=== 全员阵亡! 游戏失败! ===")
        return
    elseif aliveCount == 1 and not State.victoryPotionGiven then
        for i = 1, #State.players do
            if State.players[i].alive then
                State.victoryWinnerIdx = i
                State.players[i].potionState = "victory"
                State.players[i].poison = 0
                State.victoryPotionGiven = true
                table.insert(State.statusEffects, { playerIdx = i, type = "detox", timer = 3.0 })
                print("=== 玩家 " .. i .. " 获得胜利药水! ===")
                break
            end
        end
    end

    print("=== 黑夜结算! " .. #State.settleDeaths .. "人死亡, " .. aliveCount .. "人存活 ===")
end

-- ============================================================================
-- 9.1 缩圈过渡
-- ============================================================================

function Phase.enterShrinking()
    State.gamePhase = "shrinking"
    State.phaseTimer = CONFIG.CircleShrinkDuration
    Audio.playSound("sfx_circle_shrink", 0.6)

    -- 计算下一轮目标半径
    local nextTargetRadius = State.circle.radius * CONFIG.CircleShrinkRatio

    -- 舒适区腐化判定: 圈外的舒适区标记为corrupted
    for _, zone in ipairs(State.comfortZones) do
        if not zone.corrupted then
            local d = Utils.dist(zone.x, zone.y, State.circle.cx, State.circle.cy)
            if d > nextTargetRadius - CONFIG.ComfortZoneRadius * 0.5 then
                zone.corrupted = true
                zone.occupiedBy = nil
                print("[舒适区] 舒适区被毒圈吞噬!")
            end
        end
    end

    -- 设置缩圈目标(在下一轮 day 阶段渐进完成)
    State.circle.targetRadius = nextTargetRadius
    State.circle.shrinkSpeed = (State.circle.radius - nextTargetRadius) / CONFIG.DayDuration

    -- 按剩余天数重新生成舒适区
    local remainDays = CONFIG.TotalRounds - State.currentRound
    if remainDays > 0 and Phase.generateComfortZones then
        State.comfortZones = {}
        State.comfortFloats = {}
        Phase.generateComfortZones(State.circle.cx, State.circle.cy, nextTargetRadius, remainDays)
    end

    print("=== 缩圈过渡! 目标半径: " .. math.floor(nextTargetRadius) .. " ===")
end

-- ============================================================================
-- 阶段更新辅助
-- ============================================================================

function Phase.getAliveCount()
    return getAliveCount()
end

return Phase
