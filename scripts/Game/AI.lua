-- ============================================================================
-- Game/AI.lua
-- AI逻辑(好战AI, 优先级目标选择)
-- ============================================================================

local CONFIG = require("Game.Config")
local State = require("Game.State")
local Utils = require("Game.Utils")

local AI = {}

-- 前向引用(由main注入)
AI.performAttack = nil
AI.startDrinking = nil
AI.requestInteract = nil
AI.acceptInteract = nil
AI.giveItem = nil

-- AI全局优先攻击目标列表
local aiPriorityTargets = {}

--- AI每帧更新
function AI.update(p, dt)
    if p.isLocal or not p.alive then return end
    local players = State.players
    local circle = State.circle

    -- 喝药/硬直期间不做决策
    if p.drinkingState ~= "idle" then
        p.vx = 0
        p.vy = 0
        return
    end

    -- 交互期间
    if p.interactState ~= "idle" then
        p.vx = 0
        p.vy = 0
        -- AI在interacting状态时选择给予
        if p.interactState == "interacting" and p.potionState then
            if p.interactTimer < CONFIG.InteractDuration - 0.5 then
                if math.random() < 0.3 then
                    if p.potionState == "poison" then
                        if AI.giveItem then AI.giveItem(p, "poison") end
                    elseif p.potionState == "antidote" then
                        if math.random() < 0.8 then
                            if AI.giveItem then AI.giveItem(p, "antidote") end
                        end
                    end
                end
            end
        end
        -- AI pending时自动接受
        if p.interactState == "pending" and p.interactTimer < CONFIG.InteractAcceptTimeout - 0.5 then
            if math.random() < 0.1 then
                if AI.acceptInteract then AI.acceptInteract(p) end
            end
        end
        return
    end

    -- AI发起交互
    if p.potionState and State.gamePhase == "day" and p.energy >= CONFIG.InteractCostEnergy then
        for i = 1, #players do
            local other = players[i]
            if other.idx ~= p.idx and other.alive and other.interactState == "idle"
                and other.drinkingState == "idle" and other.attackState == "idle" then
                local d = Utils.dist(p.x, p.y, other.x, other.y)
                if d <= CONFIG.InteractRange then
                    local chance = p.potionState == "poison" and 0.015 or 0.005
                    if math.random() < chance then
                        if AI.requestInteract then AI.requestInteract(p, other.idx) end
                        return
                    end
                end
            end
        end
    end

    -- 胜利药水立刻喝
    if p.potionState == "victory" then
        if AI.startDrinking then AI.startDrinking(p, "victory") end
        return
    end

    -- AI喝药决策
    if p.potionState == "antidote" and p.poison >= 20 and State.gamePhase == "day" then
        local nearestEnemyDist = math.huge
        for i = 1, #players do
            if players[i].alive and players[i].idx ~= p.idx then
                local d = Utils.dist(p.x, p.y, players[i].x, players[i].y)
                if d < nearestEnemyDist then nearestEnemyDist = d end
            end
        end
        local urgency = p.poison / CONFIG.PoisonMax
        local safeDist = 150 * (1 - urgency * 0.7)
        local drinkChance = 0.02 + urgency * 0.08
        if nearestEnemyDist > safeDist and math.random() < drinkChance then
            if AI.startDrinking then AI.startDrinking(p, "antidote") end
            return
        end
    end

    -- AI佯装喝毒药
    if p.potionState == "poison" and State.gamePhase == "day" then
        local nearestEnemyDist = math.huge
        for i = 1, #players do
            if players[i].alive and players[i].idx ~= p.idx then
                local d = Utils.dist(p.x, p.y, players[i].x, players[i].y)
                if d < nearestEnemyDist then nearestEnemyDist = d end
            end
        end
        if nearestEnemyDist < 80 and math.random() < 0.01 then
            if AI.startDrinking then AI.startDrinking(p, "poison") end
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
            if p.vx > 0.1 then p.flipDir = 1 elseif p.vx < -0.1 then p.flipDir = -1 end
        else
            p.vx = 0
            p.vy = 0
        end

        -- 实时攻击检测
        if p.attackState == "idle" and p.attackCooldown <= 0 and p.energy >= CONFIG.AttackCostEnergy then
            local priorityTarget = nil
            local priorityDist = math.huge
            for i = 1, #players do
                local other = players[i]
                if other.alive and other.idx ~= p.idx and aiPriorityTargets[other.idx] then
                    local dToOther = Utils.dist(p.x, p.y, other.x, other.y)
                    if dToOther <= CONFIG.AttackRange and dToOther < priorityDist then
                        priorityTarget = other
                        priorityDist = dToOther
                    end
                end
            end
            if priorityTarget then
                p.facing = Utils.angleBetween(p.x, p.y, priorityTarget.x, priorityTarget.y)
                if AI.performAttack then AI.performAttack(p) end
            else
                for i = 1, #players do
                    local other = players[i]
                    if other.alive and other.idx ~= p.idx then
                        local dToOther = Utils.dist(p.x, p.y, other.x, other.y)
                        if dToOther <= CONFIG.AttackRange then
                            p.facing = Utils.angleBetween(p.x, p.y, other.x, other.y)
                            if AI.performAttack then AI.performAttack(p) end
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

    -- 更新优先攻击列表
    aiPriorityTargets = {}
    for i = 1, #players do
        local other = players[i]
        if other.alive and other.idx ~= p.idx then
            if other.drinkingState == "drinking" and other.drinkingType == "antidote" then
                aiPriorityTargets[other.idx] = true
            end
        end
    end

    -- 优先攻击正在喝解药的
    local bestPriorityTarget = nil
    local bestPriorityDist = math.huge
    for i = 1, #players do
        local other = players[i]
        if other.alive and other.idx ~= p.idx and aiPriorityTargets[other.idx] then
            local d = Utils.dist(p.x, p.y, other.x, other.y)
            if d < bestPriorityDist then
                bestPriorityDist = d
                bestPriorityTarget = other
            end
        end
    end

    if bestPriorityTarget then
        p.aiTargetX = bestPriorityTarget.x + (math.random() - 0.5) * 15
        p.aiTargetY = bestPriorityTarget.y + (math.random() - 0.5) * 15
        p.aiWantsAttack = true
        p.sprinting = p.energy > 20
        local dToCenter = Utils.dist(p.aiTargetX, p.aiTargetY, circle.cx, circle.cy)
        if dToCenter > circle.radius * 0.8 then
            p.aiTargetX = Utils.lerp(p.aiTargetX, circle.cx, 0.5)
            p.aiTargetY = Utils.lerp(p.aiTargetY, circle.cy, 0.5)
        end
        return
    end

    -- 舒适区决策(能量极低时)
    local nearestZoneDist = math.huge
    local nearestZone = nil
    for zi, zone in ipairs(State.comfortZones) do
        if not zone.corrupted then
            local claim = p.comfortClaims and p.comfortClaims[zi]
            local depleted = claim and claim.claimed and claim.energyLeft <= 0
            if not depleted then
                local d = Utils.dist(p.x, p.y, zone.x, zone.y)
                if d < nearestZoneDist then
                    nearestZoneDist = d
                    nearestZone = zone
                end
            end
        end
    end

    if p.energy < 20 and nearestZone then
        if nearestZoneDist <= CONFIG.ComfortZoneRadius * 0.5 then
            p.aiTargetX = p.x
            p.aiTargetY = p.y
            p.aiWantsAttack = false
            p.aiTimer = 2.0 + math.random() * 2.0
            return
        else
            p.aiTargetX = nearestZone.x + (math.random() - 0.5) * 20
            p.aiTargetY = nearestZone.y + (math.random() - 0.5) * 20
            p.aiWantsAttack = false
            return
        end
    end

    -- 毒素为0时逃跑
    if p.poison <= 0 then
        local nearestEnemy = nil
        local nearestDist = math.huge
        for i = 1, #players do
            local other = players[i]
            if other.alive and other.idx ~= p.idx then
                local d = Utils.dist(p.x, p.y, other.x, other.y)
                if d < nearestDist then
                    nearestDist = d
                    nearestEnemy = other
                end
            end
        end
        if nearestEnemy and nearestDist < 200 then
            local fleeAngle = math.atan(p.y - nearestEnemy.y, p.x - nearestEnemy.x)
            p.aiTargetX = p.x + math.cos(fleeAngle) * 200
            p.aiTargetY = p.y + math.sin(fleeAngle) * 200
            p.sprinting = p.energy > 15
        else
            p.aiTargetX = p.x + (math.random() - 0.5) * 250
            p.aiTargetY = p.y + (math.random() - 0.5) * 250
            p.sprinting = false
        end
        p.aiWantsAttack = false
        local dToCenter = Utils.dist(p.aiTargetX, p.aiTargetY, circle.cx, circle.cy)
        if dToCenter > circle.radius * 0.8 then
            p.aiTargetX = Utils.lerp(p.aiTargetX, circle.cx, 0.5)
            p.aiTargetY = Utils.lerp(p.aiTargetY, circle.cy, 0.5)
        end
        return
    end

    -- 好战目标选择
    local bestTarget = nil
    local bestScore = -math.huge
    for i = 1, #players do
        local other = players[i]
        if other.alive and other.idx ~= p.idx and not other.usingComfortZone then
            local d = Utils.dist(p.x, p.y, other.x, other.y)
            local score = -d * 0.1
            if other.drinkingState == "drinking" and other.drinkingType == "antidote" then
                score = score + 500
            end
            if other.poison <= 0 then score = score + 300 end
            if other.energy >= CONFIG.EnergyMax then score = score + 150 end
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
        local d = Utils.dist(p.x, p.y, bestTarget.x, bestTarget.y)
        if p.energy >= CONFIG.AttackCostEnergy then
            p.aiTargetX = bestTarget.x + (math.random() - 0.5) * 20
            p.aiTargetY = bestTarget.y + (math.random() - 0.5) * 20
            p.aiWantsAttack = d < CONFIG.AttackRange * 1.5
            if d > CONFIG.AttackRange * 2 and p.energy > 30 then
                p.sprinting = true
            else
                p.sprinting = false
            end
        else
            p.aiTargetX = p.x + (math.random() - 0.5) * 150
            p.aiTargetY = p.y + (math.random() - 0.5) * 150
            p.aiWantsAttack = false
        end
    else
        p.aiTargetX = CONFIG.MapSize / 2 + (math.random() - 0.5) * 200
        p.aiTargetY = CONFIG.MapSize / 2 + (math.random() - 0.5) * 200
        p.aiWantsAttack = false
    end

    -- 保持在毒圈内
    local dToCenter = Utils.dist(p.aiTargetX, p.aiTargetY, circle.cx, circle.cy)
    if dToCenter > circle.radius * 0.8 then
        p.aiTargetX = Utils.lerp(p.aiTargetX, circle.cx, 0.5)
        p.aiTargetY = Utils.lerp(p.aiTargetY, circle.cy, 0.5)
    end
end

return AI
