-- ============================================================================
-- Game/Interact.lua
-- 交互系统(请求/接受/给予/打断)
-- ============================================================================

local CONFIG = require("Game.Config")
local State = require("Game.State")
local Utils = require("Game.Utils")
local Audio = require("Game.Audio")

local Interact = {}

--- 中断交互(被攻击时调用)
function Interact.interrupt(player)
    if player.interactState == "idle" then return false end
    local partnerIdx = player.interactPartner
    player.interactState = "idle"
    player.interactPartner = nil
    player.interactTimer = 0
    player.interactGiveType = nil
    player.interactReceived = nil
    player.interactFlyAnim = nil
    if partnerIdx then
        local partner = State.players[partnerIdx]
        if partner then
            partner.interactState = "idle"
            partner.interactPartner = nil
            partner.interactTimer = 0
            partner.interactGiveType = nil
            partner.interactReceived = nil
            partner.interactFlyAnim = nil
        end
    end
    table.insert(State.floatingTexts, {
        x = player.x, y = player.y - 40,
        text = "交互中断!", color = {255, 150, 50},
        timer = 1.0, maxTimer = 1.0,
    })
    print("玩家 " .. player.idx .. " 交互被中断!")
    return true
end

--- 发起交互请求
function Interact.request(requester, targetIdx)
    if State.gamePhase ~= "day" then return false end
    if not requester.alive then return false end
    if requester.interactState ~= "idle" then return false end
    if requester.drinkingState ~= "idle" then return false end
    if requester.attackState ~= "idle" then return false end
    if requester.energy < CONFIG.InteractCostEnergy then return false end

    local target = State.players[targetIdx]
    if not target or not target.alive then return false end
    if target.interactState ~= "idle" then return false end
    if target.drinkingState ~= "idle" then return false end
    if target.attackState ~= "idle" then return false end

    local d = Utils.dist(requester.x, requester.y, target.x, target.y)
    if d > CONFIG.InteractRange then return false end

    requester.energy = requester.energy - CONFIG.InteractCostEnergy
    requester.interactState = "requesting"
    requester.interactPartner = targetIdx
    requester.interactTimer = CONFIG.InteractAcceptTimeout

    target.interactState = "pending"
    target.interactPartner = requester.idx
    target.interactTimer = CONFIG.InteractAcceptTimeout

    table.insert(State.floatingTexts, {
        x = requester.x, y = requester.y - 40,
        text = "请求交互...", color = {200, 200, 100},
        timer = 1.5, maxTimer = 1.5,
    })
    print("玩家 " .. requester.idx .. " 向玩家 " .. targetIdx .. " 发起交互请求")
    return true
end

--- 接受交互
function Interact.accept(player)
    if player.interactState ~= "pending" then return false end
    local partnerIdx = player.interactPartner
    local partner = State.players[partnerIdx]
    if not partner or partner.interactState ~= "requesting" then
        player.interactState = "idle"
        player.interactPartner = nil
        return false
    end

    player.interactState = "interacting"
    player.interactTimer = CONFIG.InteractDuration
    player.interactGiveType = nil
    partner.interactState = "interacting"
    partner.interactTimer = CONFIG.InteractDuration
    partner.interactGiveType = nil
    player.vx = 0
    player.vy = 0
    partner.vx = 0
    partner.vy = 0

    table.insert(State.floatingTexts, {
        x = player.x, y = player.y - 40,
        text = "交互开始!", color = {100, 255, 200},
        timer = 1.0, maxTimer = 1.0,
    })
    print("玩家 " .. player.idx .. " 接受了玩家 " .. partnerIdx .. " 的交互")
    return true
end

--- 取消交互
function Interact.cancel(player)
    if player.interactState == "idle" then return end
    local partnerIdx = player.interactPartner
    player.interactState = "idle"
    player.interactPartner = nil
    player.interactTimer = 0
    player.interactGiveType = nil
    player.interactReceived = nil
    player.interactFlyAnim = nil
    if partnerIdx then
        local partner = State.players[partnerIdx]
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

--- 给予物品
function Interact.giveItem(giver, itemType)
    if giver.interactState ~= "interacting" then return false end
    if not giver.potionState then return false end
    local partnerIdx = giver.interactPartner
    local receiver = State.players[partnerIdx]
    if not receiver then return false end

    giver.interactGiveType = itemType
    giver.interactState = "giving"
    giver.interactFlyAnim = {
        t = 0,
        duration = 0.6,
        fromX = giver.x,
        fromY = giver.y - 20,
        toX = receiver.x,
        toY = receiver.y - 20,
        type = itemType,
    }
    giver.potionState = nil
    if giver.isLocal then Audio.playSound("sfx_interact_give", 0.5) end
    print("玩家 " .. giver.idx .. " 给予玩家 " .. partnerIdx .. " " .. (itemType == "antidote" and "解药" or "毒药"))
    return true
end

--- 完成给予(抛物线动画结束后)
function Interact.completeGive(giver, receiverIdx, itemType)
    local receiver = State.players[receiverIdx]
    if not receiver or not receiver.alive then return end

    if itemType == "antidote" then
        receiver.poison = Utils.clamp(receiver.poison - 15, CONFIG.PoisonMin, CONFIG.PoisonMax)
        receiver.interactReceived = "antidote"
        table.insert(State.floatingTexts, {
            x = receiver.x, y = receiver.y - 40,
            text = "-15毒(解药)", color = {80, 220, 255},
            timer = 1.2, maxTimer = 1.2,
        })
        table.insert(State.statusEffects, { playerIdx = receiverIdx, type = "detox", timer = 0.8 })
    elseif itemType == "poison" then
        receiver.poison = Utils.clamp(receiver.poison + 25, CONFIG.PoisonMin, CONFIG.PoisonMax)
        receiver.interactReceived = "poison"
        table.insert(State.floatingTexts, {
            x = receiver.x, y = receiver.y - 40,
            text = "+25毒(被骗!)", color = {255, 60, 60},
            timer = 1.5, maxTimer = 1.5,
        })
        table.insert(State.statusEffects, { playerIdx = receiverIdx, type = "poison", timer = 1.0 })
        State.screenShake.timer = 0.15
        State.screenShake.intensity = 3
    end

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

--- 交互状态每帧更新
function Interact.updateState(p, dt)
    if p.interactState == "idle" then return end

    if p.interactState == "requesting" then
        p.interactTimer = p.interactTimer - dt
        p.vx = 0
        p.vy = 0
        if p.interactTimer <= 0 then
            local partner = State.players[p.interactPartner]
            if partner and partner.interactState == "pending" then
                Interact.accept(partner)
            else
                Interact.cancel(p)
            end
        end
        if p.interactPartner then
            local partner = State.players[p.interactPartner]
            if partner then
                local d = Utils.dist(p.x, p.y, partner.x, partner.y)
                if d > CONFIG.InteractRange * 1.5 then
                    Interact.cancel(p)
                end
            end
        end
    elseif p.interactState == "pending" then
        p.interactTimer = p.interactTimer - dt
        p.vx = 0
        p.vy = 0
        if p.interactTimer <= 0 then
            Interact.accept(p)
        end
    elseif p.interactState == "interacting" then
        p.interactTimer = p.interactTimer - dt
        p.vx = 0
        p.vy = 0
        if p.interactTimer <= 0 then
            Interact.cancel(p)
        end
    elseif p.interactState == "giving" then
        p.vx = 0
        p.vy = 0
        if p.interactFlyAnim then
            p.interactFlyAnim.t = p.interactFlyAnim.t + dt
            if p.interactFlyAnim.t >= p.interactFlyAnim.duration then
                Interact.completeGive(p, p.interactPartner, p.interactGiveType)
            end
        else
            Interact.cancel(p)
        end
    end
end

--- 找到最近可交互玩家
function Interact.findNearest(player)
    if not player.alive then return nil end
    if player.interactState ~= "idle" then return nil end
    if player.drinkingState ~= "idle" then return nil end
    if player.attackState ~= "idle" then return nil end

    local bestIdx = nil
    local bestDist = CONFIG.InteractRange
    for i = 1, #State.players do
        local other = State.players[i]
        if other.idx ~= player.idx and other.alive
            and other.interactState == "idle"
            and other.drinkingState == "idle"
            and other.attackState == "idle" then
            local d = Utils.dist(player.x, player.y, other.x, other.y)
            if d <= bestDist then
                bestDist = d
                bestIdx = i
            end
        end
    end
    return bestIdx
end

return Interact
