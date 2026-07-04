-- ============================================================================
-- Game/Combat.lua
-- 攻击系统(前摇/后摇/判定/特效)
-- ============================================================================

local CONFIG = require("Game.Config")
local State = require("Game.State")
local Utils = require("Game.Utils")
local Audio = require("Game.Audio")

local Combat = {}

-- 前向引用(由main注入)
Combat.interruptDrinking = nil
Combat.interruptInteract = nil

--- 攻击判定(前摇结束后调用)
function Combat.resolveHit(attacker)
    local halfAngle = math.rad(CONFIG.AttackAngle / 2)
    local hitAny = false
    local players = State.players

    for i = 1, #players do
        local target = players[i]
        if target.idx ~= attacker.idx and target.alive and not target.usingComfortZone then
            local d = Utils.dist(attacker.x, attacker.y, target.x, target.y)
            if d <= CONFIG.AttackRange then
                local angleToTarget = Utils.angleBetween(attacker.x, attacker.y, target.x, target.y)
                local angleDiff = Utils.normalizeAngle(angleToTarget - attacker.facing)
                if math.abs(angleDiff) <= halfAngle then
                    -- 命中!
                    local buffMult = attacker.poisonMaxBuff and 2 or 1
                    local poisonAdd = CONFIG.AttackPoisonAdd * buffMult
                    local energySteal = CONFIG.EnergyStealOnHit * buffMult

                    attacker.poison = Utils.clamp(attacker.poison - CONFIG.AttackPoisonReduce, CONFIG.PoisonMin, CONFIG.PoisonMax)
                    target.poison = Utils.clamp(target.poison + poisonAdd, CONFIG.PoisonMin, CONFIG.PoisonMax)
                    local stealAmount = math.min(energySteal, target.energy)
                    target.energy = Utils.clamp(target.energy - stealAmount, CONFIG.EnergyMin, CONFIG.EnergyMax)
                    attacker.energy = Utils.clamp(attacker.energy + stealAmount, CONFIG.EnergyMin, CONFIG.EnergyMax)
                    target.hitFlash = 0.3
                    hitAny = true
                    if attacker.isLocal or target.isLocal then Audio.playSound("sfx_attack_hit", 0.6) end

                    -- 打断喝药
                    if Combat.interruptDrinking then
                        Combat.interruptDrinking(target, attacker.idx)
                    end
                    -- 打断交互
                    if Combat.interruptInteract then
                        Combat.interruptInteract(target)
                    end

                    -- 打断舒适区占领
                    if target.isCapturingZone then
                        target.isCapturingZone = false
                        target.comfortStandTimer = 0
                        local zi = target.currentComfortZoneIdx
                        if zi and target.comfortClaims and target.comfortClaims[zi] then
                            target.comfortClaims[zi].claimTimer = 0
                        end
                        if target.isLocal then
                            table.insert(State.floatingTexts, {
                                x = target.x, y = target.y - 50,
                                text = "占领被打断!",
                                color = {255, 100, 100},
                                timer = 1.0, maxTimer = 1.0,
                            })
                        end
                    end

                    -- 状态特效
                    table.insert(State.statusEffects, { playerIdx = target.idx, type = "poison", timer = 1.0 })
                    table.insert(State.statusEffects, { playerIdx = attacker.idx, type = "detox", timer = 0.8 })

                    -- 浮动文字
                    local poisonText = "+" .. poisonAdd .. "毒"
                    if attacker.poisonMaxBuff then poisonText = poisonText .. "(暴走!)" end
                    table.insert(State.floatingTexts, {
                        x = target.x, y = target.y - 30,
                        text = poisonText, color = {220, 50, 50},
                        timer = 1.0, maxTimer = 1.0,
                    })
                    table.insert(State.floatingTexts, {
                        x = attacker.x, y = attacker.y - 30,
                        text = "-15毒", color = {50, 200, 80},
                        timer = 1.0, maxTimer = 1.0,
                    })

                    -- 屏幕震动
                    State.screenShake.timer = 0.1
                    State.screenShake.intensity = 4

                    -- 命中粒子
                    for j = 1, 8 do
                        table.insert(State.particles, {
                            x = target.x,
                            y = target.y,
                            vx = (math.random() - 0.5) * 200,
                            vy = (math.random() - 0.5) * 200,
                            life = 0.6,
                            color = {20, 20, 30},
                        })
                    end
                    print("玩家 " .. attacker.idx .. " 命中玩家 " .. target.idx)
                end
            end
        end
    end
    return hitAny
end

--- 发起攻击(进入前摇)
function Combat.performAttack(attacker)
    if State.gamePhase ~= "day" then return end
    if attacker.drinkingState ~= "idle" then return end
    if attacker.interactState ~= "idle" then return end
    if attacker.energy < CONFIG.AttackCostEnergy then return end
    if attacker.attackCooldown > 0 then return end
    if attacker.attackState ~= "idle" then return end

    attacker.energy = attacker.energy - CONFIG.AttackCostEnergy
    attacker.attackCooldown = CONFIG.AttackCooldown
    attacker.attacking = true
    attacker.attackState = "windup"
    attacker.attackStateTimer = CONFIG.AttackWindup
    attacker.attackTimer = CONFIG.AttackWindup
    if attacker.isLocal then Audio.playSound("sfx_attack_swing", 0.5) end

    table.insert(State.attackEffects, {
        x = attacker.x,
        y = attacker.y,
        angle = attacker.facing,
        timer = CONFIG.AttackWindup + CONFIG.AttackRecovery,
        phase = "windup",
    })
end

--- 攻击状态更新(每帧调用)
function Combat.updateAttackState(p, dt)
    if p.attackState == "windup" then
        p.attackStateTimer = p.attackStateTimer - dt
        if p.attackStateTimer <= 0 then
            Combat.resolveHit(p)
            p.attackState = "recovery"
            p.attackStateTimer = CONFIG.AttackRecovery
            table.insert(State.attackEffects, {
                x = p.x,
                y = p.y,
                angle = p.facing,
                timer = CONFIG.AttackRecovery,
                phase = "slash",
            })
        end
    elseif p.attackState == "recovery" then
        p.attackStateTimer = p.attackStateTimer - dt
        p.vx = 0
        p.vy = 0
        if p.attackStateTimer <= 0 then
            p.attackState = "idle"
            p.attacking = false
        end
    end
end

return Combat
