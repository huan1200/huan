-- ============================================================================
-- Game/Potion.lua
-- 药水系统(喝药/打断/地面拾取)
-- ============================================================================

local CONFIG = require("Game.Config")
local State = require("Game.State")
local Utils = require("Game.Utils")
local Audio = require("Game.Audio")

local Potion = {}

--- 开始喝药(进入读条状态)
function Potion.startDrinking(p, potionType)
    if potionType ~= "victory" and State.gamePhase ~= "day" then return false end
    if not p.alive then return false end
    if p.drinkingState ~= "idle" then return false end
    if p.attackState ~= "idle" then return false end
    if p.potionState ~= potionType then return false end
    if potionType ~= "victory" and p.energy < CONFIG.DrinkCostEnergy then return false end

    if potionType ~= "victory" then
        p.energy = p.energy - CONFIG.DrinkCostEnergy
    end
    p.drinkingState = "drinking"
    p.drinkingTimer = potionType == "victory" and 1.0 or CONFIG.DrinkDuration
    p.drinkingType = potionType
    p.vx = 0
    p.vy = 0
    if p.isLocal then Audio.playSound("sfx_drink_start", 0.5) end
    local typeName = potionType == "antidote" and "解药" or (potionType == "victory" and "胜利药水" or "毒药")
    print("玩家 " .. p.idx .. " 开始喝" .. typeName .. "!")
    return true
end

--- 打断喝药(被攻击命中时调用)
function Potion.interruptDrinking(target, attackerIdx)
    if target.drinkingState ~= "drinking" then return false end
    local wasType = target.drinkingType

    target.drinkingState = "stunned"
    target.drinkingTimer = CONFIG.DrinkStunDuration
    target.drinkingType = nil

    if target.isLocal then Audio.playSound("sfx_drink_interrupt", 0.6) end

    if wasType == "antidote" then
        target.potionState = nil
        table.insert(State.groundPotions, {
            x = target.x + (math.random() - 0.5) * 30,
            y = target.y + (math.random() - 0.5) * 20,
            type = "antidote",
            timer = 999,
        })
        table.insert(State.floatingTexts, {
            x = target.x, y = target.y - 40,
            text = "打断! 解药掉落!", color = {100, 180, 255},
            timer = 1.2, maxTimer = 1.2,
        })
        print("玩家 " .. target.idx .. " 喝解药被打断! 解药掉落地面!")
    elseif wasType == "poison" then
        target.potionState = nil
        local attacker = State.players[attackerIdx]
        if attacker and attacker.alive then
            attacker.potionState = "poison"
            attacker.poison = Utils.clamp(attacker.poison + CONFIG.DrinkInterruptPoisonTransfer, CONFIG.PoisonMin, CONFIG.PoisonMax)
            table.insert(State.floatingTexts, {
                x = attacker.x, y = attacker.y - 40,
                text = "+30毒(转移)!", color = {180, 60, 200},
                timer = 1.2, maxTimer = 1.2,
            })
            if attacker.isLocal then Audio.playSound("sfx_poison_transfer", 0.7) end
            print("玩家 " .. target.idx .. " 喝毒药被打断! 毒药转移给玩家 " .. attackerIdx .. "!")
        end
        table.insert(State.floatingTexts, {
            x = target.x, y = target.y - 40,
            text = "毒药转移!", color = {120, 255, 120},
            timer = 1.2, maxTimer = 1.2,
        })
    end

    State.screenShake.timer = 0.15
    State.screenShake.intensity = 5
    return true
end

--- 喝药状态每帧更新
function Potion.updateDrinkingState(p, dt)
    if p.drinkingState == "drinking" then
        p.drinkingTimer = p.drinkingTimer - dt
        p.vx = 0
        p.vy = 0
        if p.drinkingTimer <= 0 then
            if p.drinkingType == "antidote" then
                p.poison = CONFIG.PoisonMin
                p.potionState = nil
                table.insert(State.floatingTexts, {
                    x = p.x, y = p.y - 30,
                    text = "解毒成功!", color = {80, 220, 255},
                    timer = 1.0, maxTimer = 1.0,
                })
                table.insert(State.pickupGlows, { playerIdx = p.idx, type = "antidote", timer = 1.5, maxTimer = 1.5 })
                if p.isLocal then Audio.playSound("sfx_drink_complete", 0.7) end
                print("玩家 " .. p.idx .. " 成功喝下解药! 毒素清零!")
            elseif p.drinkingType == "poison" then
                p.poison = Utils.clamp(p.poison + CONFIG.PoisonDrinkAmount, CONFIG.PoisonMin, CONFIG.PoisonMax)
                p.potionState = nil
                table.insert(State.floatingTexts, {
                    x = p.x, y = p.y - 30,
                    text = "+100毒! 毒发!", color = {255, 0, 0},
                    timer = 1.2, maxTimer = 1.2,
                })
                print("玩家 " .. p.idx .. " 成功喝下毒药! 毒发身亡!")
            elseif p.drinkingType == "victory" then
                p.potionState = nil
                State.victoryWinnerIdx = p.idx
                State.gamePhase = "victory"
                Audio.playSound("sfx_nightfall", 1.0)
                local hud = State.uiRoot_ and State.uiRoot_:FindById("hudPanel")
                if hud then hud:SetVisible(false) end
                table.insert(State.floatingTexts, {
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
        p.vx = 0
        p.vy = 0
        if p.drinkingTimer <= 0 then
            p.drinkingState = "idle"
            p.drinkingTimer = 0
        end
    end
end

--- 更新地面药剂(拾取检测)
function Potion.updateGroundPotions(dt)
    local players = State.players
    local groundPotions = State.groundPotions
    local i = 1
    while i <= #groundPotions do
        local gp = groundPotions[i]
        local picked = false
        for pi = 1, #players do
            local p = players[pi]
            if p.alive and p.potionState == nil and p.drinkingState == "idle" then
                local d = Utils.dist(p.x, p.y, gp.x, gp.y)
                if d <= CONFIG.GroundPotionPickupRange then
                    p.potionState = gp.type
                    table.insert(State.pickupGlows, {
                        playerIdx = pi,
                        type = gp.type,
                        timer = 1.2, maxTimer = 1.2,
                    })
                    table.insert(State.floatingTexts, {
                        x = p.x, y = p.y - 30,
                        text = gp.type == "antidote" and "拾取解药" or "拾取毒药",
                        color = gp.type == "antidote" and {100, 200, 255} or {180, 60, 200},
                        timer = 1.0, maxTimer = 1.0,
                    })
                    if p.isLocal then Audio.playSound("sfx_antidote_get", 0.6) end
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

return Potion
