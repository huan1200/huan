-- ============================================================================
-- server_main.lua
-- 《道友请留步》多人版 - 服务端入口
-- 权威服务器: 运行游戏逻辑, AI, 状态同步
-- ============================================================================

require "LuaScripts/Utilities/Sample"

---@type integer 引擎注入的全局变量: 已注册玩家数
SERVER_REGISTERED_PLAYERS = SERVER_REGISTERED_PLAYERS or 0

local Shared = require("Network.Shared")
local CONFIG = Shared.CONFIG

-- ============================================================================
-- 服务器状态
-- ============================================================================
local scene_ = nil
local playerConnections_ = {}   -- { [connKey] = { connection, playerId, ready } }
local players_ = {}             -- { [playerId] = playerData }
local nextPlayerId_ = 1

-- 游戏阶段
local gamePhase_ = "waiting"    -- waiting/day/settle/shrinking/gameover
local currentRound_ = 0
local phaseTimer_ = 0
local settleSubPhase_ = "countdown"
local victoryWinnerIdx_ = nil
local gameStarted_ = false

-- 毒圈
local circleInitRadius_ = math.sqrt(CONFIG.MapSize * CONFIG.MapSize * 2) * CONFIG.CircleInitRadiusFactor
local circle_ = {
    cx = CONFIG.MapSize / 2,
    cy = CONFIG.MapSize / 2,
    radius = circleInitRadius_,
    targetRadius = circleInitRadius_,
    shrinkSpeed = 0,
}

-- 舒适区
local comfortZones_ = {}
-- 地面药剂
local groundPotions_ = {}

-- 状态同步计时器
local syncTimer_ = 0
local SYNC_INTERVAL = 0.05  -- 20Hz

-- ============================================================================
-- 玩家数据
-- ============================================================================
local function createPlayerData(playerId, isAI)
    return {
        id = playerId,
        isAI = isAI,
        x = 0, y = 0,
        vx = 0, vy = 0,
        facing = 0,
        poison = 0,
        energy = CONFIG.EnergyMax,
        alive = true,
        isGhost = false,
        -- 攻击
        attackCooldown = 0,
        attackState = "idle",
        attackStateTimer = 0,
        -- 喝药
        potionState = nil,
        drinkingState = "idle",
        drinkingTimer = 0,
        drinkingType = nil,
        -- 奔跑
        sprinting = false,
        -- 交互
        interactState = "idle",
        interactPartner = nil,
        interactTimer = 0,
        interactGiveType = nil,
        -- 舒适区占领
        comfortClaims = {},
        isCapturingZone = false,
        comfortStandTimer = 0,
        currentComfortZoneIdx = nil,
        -- AI
        aiTimer = 0,
        aiTargetX = 0,
        aiTargetY = 0,
        aiWantsAttack = false,
        -- 输入
        inputYaw = 0,
        inputButtons = 0,
        inputPitch = 0,
        -- 网络节点
        node = nil,
        -- 角色形象
        avatarIdx = 1,
        nickname = "",
    }
end

-- ============================================================================
-- 工具函数
-- ============================================================================
local dist = Shared.dist
local angleBetween = Shared.angleBetween
local normalizeAngle = Shared.normalizeAngle
local clamp = Shared.clamp
local lerp = Shared.lerp

-- ============================================================================
-- 入口
-- ============================================================================
function Start()
    math.randomseed(os.time())
    print("[Server] Starting... MaxPlayers=" .. CONFIG.MaxPlayers)

    SampleStart()

    -- 创建场景(网络复制必需)
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    -- 注册远程事件
    Shared.RegisterServerEvents()

    -- 订阅事件
    SubscribeToEvent("ClientConnected", "HandleClientConnected")
    SubscribeToEvent("ClientDisconnected", "HandleClientDisconnected")
    SubscribeToEvent("ClientIdentity", "HandleClientIdentity")
    SubscribeToEvent(Shared.EVENTS.CLIENT_READY, "HandleClientReady")
    SubscribeToEvent(Shared.EVENTS.PLAYER_ACTION, "HandlePlayerAction")
    SubscribeToEvent("Update", "HandleUpdate")

    gamePhase_ = "waiting"
    print("[Server] Waiting for players...")
end

function Stop()
    print("[Server] Stopping...")
end

-- ============================================================================
-- 连接管理
-- ============================================================================
function HandleClientConnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    print("[Server] Client connected: " .. connKey)

    -- 配置脉冲按键(攻击等一次性操作)
    connection:SetPulseButtonMask(Shared.PULSE_MASK)

    playerConnections_[connKey] = {
        connection = connection,
        playerId = nil,
        ready = false,
    }
end

function HandleClientIdentity(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local info = playerConnections_[connKey]
    if not info then return end

    local identity = connection.identity
    if identity then
        local userId = identity["user_id"]:GetInt64()
        info.userId = userId
        print("[Server] ClientIdentity: " .. connKey .. " userId=" .. tostring(userId))
    end
end

function HandleClientReady(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local info = playerConnections_[connKey]
    if not info or info.ready then return end

    -- 设置场景(触发全量同步)
    connection.scene = scene_
    info.ready = true

    -- 分配玩家ID
    local playerId = nextPlayerId_
    nextPlayerId_ = nextPlayerId_ + 1
    info.playerId = playerId

    -- 创建玩家数据
    local pData = createPlayerData(playerId, false)
    pData.nickname = "玩家" .. playerId
    pData.avatarIdx = playerId  -- 对应角色形象(1-5)
    players_[playerId] = pData

    -- 查询昵称
    if info.userId then
        GetUserNickname({
            userIds = { info.userId },
            onSuccess = function(nicknames)
                if nicknames[1] then
                    pData.nickname = nicknames[1].nickname
                    if pData.node then
                        pData.node:SetVar(Shared.VARS.NICKNAME, Variant(pData.nickname))
                    end
                end
            end
        })
    end

    -- 通知客户端分配信息
    local assignData = VariantMap()
    assignData["PlayerId"] = Variant(playerId)
    assignData["AvatarIdx"] = Variant(pData.avatarIdx)
    connection:SendRemoteEvent(Shared.EVENTS.ASSIGN_PLAYER, true, assignData)

    print("[Server] Player " .. playerId .. " joined (avatar " .. pData.avatarIdx .. ")")

    -- 检查是否可以开始游戏
    CheckGameStart()
end

function HandleClientDisconnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local info = playerConnections_[connKey]

    if info and info.playerId then
        local pData = players_[info.playerId]
        if pData then
            pData.alive = false
            pData.isGhost = true
            if pData.node then
                pData.node:SetVar(Shared.VARS.ALIVE, Variant(false))
            end
        end
        print("[Server] Player " .. info.playerId .. " disconnected")
    end

    playerConnections_[connKey] = nil
end

-- ============================================================================
-- 游戏开始
-- ============================================================================
function CheckGameStart()
    if gameStarted_ then return end

    local readyCount = 0
    for _, info in pairs(playerConnections_) do
        if info.ready then readyCount = readyCount + 1 end
    end

    -- 所有注册玩家就绪后开始(SERVER_REGISTERED_PLAYERS由引擎注入)
    if readyCount >= SERVER_REGISTERED_PLAYERS then
        StartGame()
    end
end

function StartGame()
    if gameStarted_ then return end
    gameStarted_ = true
    print("[Server] All players ready, starting game!")

    -- 填充AI玩家到5人
    local realPlayerCount = 0
    for _ in pairs(players_) do realPlayerCount = realPlayerCount + 1 end
    local aiCount = CONFIG.MaxPlayers - realPlayerCount
    if aiCount < 0 then aiCount = 0 end

    print("[Server] Adding " .. aiCount .. " AI players")

    -- 角色形象池(打乱分配)
    local avatarPool = {1, 2, 3, 4, 5}
    -- 先移除已被真实玩家使用的
    local usedAvatars = {}
    for _, p in pairs(players_) do usedAvatars[p.avatarIdx] = true end
    local availableAvatars = {}
    for _, a in ipairs(avatarPool) do
        if not usedAvatars[a] then table.insert(availableAvatars, a) end
    end
    -- Fisher-Yates shuffle
    for i = #availableAvatars, 2, -1 do
        local j = math.random(1, i)
        availableAvatars[i], availableAvatars[j] = availableAvatars[j], availableAvatars[i]
    end

    local AI_NAMES = {"小丑", "战士", "科学家", "矿工", "盗贼"}
    for i = 1, aiCount do
        local aiId = nextPlayerId_
        nextPlayerId_ = nextPlayerId_ + 1
        local aiData = createPlayerData(aiId, true)
        local avatarIdx = availableAvatars[i] or ((aiId - 1) % 5 + 1)
        aiData.avatarIdx = avatarIdx
        aiData.nickname = AI_NAMES[avatarIdx] or ("AI" .. aiId)
        players_[aiId] = aiData
    end

    -- 生成出生点(环形分布)
    local cx = CONFIG.MapSize / 2
    local cy = CONFIG.MapSize / 2
    local spawnRadius = CONFIG.MapSize * 0.35
    local totalPlayers = 0
    for _ in pairs(players_) do totalPlayers = totalPlayers + 1 end

    local idx = 0
    for pid, pData in pairs(players_) do
        local angle = idx * (2 * math.pi / totalPlayers) - math.pi / 2
        pData.x = cx + math.cos(angle) * spawnRadius
        pData.y = cy + math.sin(angle) * spawnRadius
        pData.facing = angleBetween(pData.x, pData.y, cx, cy)

        -- 创建网络复制节点
        local node = scene_:CreateChild("Player_" .. pid, REPLICATED)
        node.position = Vector3(pData.x, 0, pData.y)
        node:SetVar(Shared.VARS.PLAYER_ID, Variant(pid))
        node:SetVar(Shared.VARS.ALIVE, Variant(true))
        node:SetVar(Shared.VARS.POISON, Variant(0.0))
        node:SetVar(Shared.VARS.ENERGY, Variant(CONFIG.EnergyMax * 1.0))
        node:SetVar(Shared.VARS.POTION_STATE, Variant(0))
        node:SetVar(Shared.VARS.ATTACK_STATE, Variant(0))
        node:SetVar(Shared.VARS.DRINK_STATE, Variant(0))
        node:SetVar(Shared.VARS.INTERACT_STATE, Variant(0))
        node:SetVar(Shared.VARS.FACING, Variant(pData.facing))
        node:SetVar(Shared.VARS.IS_AI, Variant(pData.isAI))
        node:SetVar(Shared.VARS.SPRINTING, Variant(false))
        node:SetVar(Shared.VARS.NICKNAME, Variant(pData.nickname))
        node:SetVar(Shared.VARS.AVATAR_IDX, Variant(pData.avatarIdx))
        pData.node = node

        idx = idx + 1
    end

    -- 生成舒适区
    GenerateComfortZones(cx, cy, circleInitRadius_, CONFIG.TotalRounds)

    -- 广播舒适区和毒圈
    BroadcastComfortZones()
    BroadcastCircle()

    -- 直接进入白天阶段(去除准备阶段)
    EnterPhase("day")
end

-- ============================================================================
-- 阶段管理
-- ============================================================================
function EnterPhase(phase)
    gamePhase_ = phase
    print("[Server] Phase: " .. phase .. " Round: " .. currentRound_)

    if phase == "day" then
        phaseTimer_ = CONFIG.DayDuration
        currentRound_ = currentRound_ + 1
        OnDayStart()
    elseif phase == "settle" then
        phaseTimer_ = CONFIG.NightfallDuration
        settleSubPhase_ = "countdown"
    elseif phase == "shrinking" then
        phaseTimer_ = CONFIG.CircleShrinkDuration
        OnShrinkStart()
    elseif phase == "gameover" then
        phaseTimer_ = 10
    end

    -- 广播阶段变化
    local data = VariantMap()
    data["Phase"] = Variant(phase)
    data["Round"] = Variant(currentRound_)
    data["Timer"] = Variant(phaseTimer_)
    network:BroadcastRemoteEvent(Shared.EVENTS.PHASE_CHANGE, true, data)
end

function OnDayStart()
    local aliveList = {}
    for pid, p in pairs(players_) do
        if p.alive then
            -- 旧解药变毒药
            if p.potionState == "antidote" then
                p.potionState = "poison"
                p.poison = clamp(p.poison + CONFIG.PoisonPerRound, CONFIG.PoisonMin, CONFIG.PoisonMax)
                SendFloatingText(p.x, p.y, "+30毒(变质)", 180, 60, 200)
            end
            -- 固定+30毒
            p.poison = clamp(p.poison + CONFIG.PoisonPerRound, CONFIG.PoisonMin, CONFIG.PoisonMax)
            p.drinkingState = "idle"
            p.drinkingTimer = 0
            p.drinkingType = nil
            table.insert(aliveList, pid)
        end
    end

    -- 地面解药变毒药
    for i = 1, #groundPotions_ do
        if groundPotions_[i].type == "antidote" then
            groundPotions_[i].type = "poison"
        end
    end

    -- 50%存活玩家获得解药
    for i = #aliveList, 2, -1 do
        local j = math.random(1, i)
        aliveList[i], aliveList[j] = aliveList[j], aliveList[i]
    end
    local giveCount = math.ceil(#aliveList * CONFIG.AntidoteRatio)
    for k = 1, giveCount do
        local pid = aliveList[k]
        players_[pid].potionState = "antidote"
        UpdatePlayerNode(pid)
        SendFloatingText(players_[pid].x, players_[pid].y, "获得解药!", 100, 200, 255)
    end

    groundPotions_ = {}
    BroadcastGroundPotions()
end

function OnShrinkStart()
    local nextTargetRadius = circle_.radius * CONFIG.CircleShrinkRatio

    -- 刷新舒适区: 按剩余天数
    local remainDays = CONFIG.TotalRounds - currentRound_
    if remainDays < 1 then remainDays = 1 end

    -- 清除旧舒适区
    comfortZones_ = {}
    -- 重置玩家占领数据
    for _, p in pairs(players_) do
        p.comfortClaims = {}
        p.isCapturingZone = false
        p.comfortStandTimer = 0
    end

    -- 生成新舒适区
    GenerateComfortZones(circle_.cx, circle_.cy, nextTargetRadius, remainDays)

    circle_.targetRadius = nextTargetRadius
    circle_.shrinkSpeed = (circle_.radius - circle_.targetRadius) / CONFIG.DayDuration

    BroadcastCircle()
    BroadcastComfortZones()
end

-- ============================================================================
-- 结算(淘汰)
-- ============================================================================
function OnSettleElimination()
    settleSubPhase_ = "elimination"
    phaseTimer_ = CONFIG.SettleDuration

    for pid, p in pairs(players_) do
        if p.alive and p.poison > 0 then
            p.alive = false
            p.isGhost = true
            p.vx = 0
            p.vy = 0
            for _, zone in ipairs(comfortZones_) do
                if zone.occupiedBy == pid then zone.occupiedBy = nil end
            end
            UpdatePlayerNode(pid)

            local deathData = VariantMap()
            deathData["PlayerId"] = Variant(pid)
            deathData["Reason"] = Variant("poison_settle")
            network:BroadcastRemoteEvent(Shared.EVENTS.PLAYER_DIED, true, deathData)
        end
    end

    CheckGameEnd()
end

-- ============================================================================
-- 胜利/结束
-- ============================================================================
function CheckGameEnd()
    local aliveCount = 0
    local lastAlive = nil
    for pid, p in pairs(players_) do
        if p.alive then
            aliveCount = aliveCount + 1
            lastAlive = pid
        end
    end

    if aliveCount == 0 then
        EndGame(nil)
    elseif aliveCount == 1 then
        -- 最后存活者胜利
        victoryWinnerIdx_ = lastAlive
        EndGame(lastAlive)
    end
end

function EndGame(winnerId)
    local data = VariantMap()
    data["WinnerId"] = Variant(winnerId or 0)
    network:BroadcastRemoteEvent(Shared.EVENTS.GAME_OVER, true, data)
    EnterPhase("gameover")
end

-- ============================================================================
-- 主更新
-- ============================================================================
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    if not gameStarted_ then return end

    phaseTimer_ = phaseTimer_ - dt

    if gamePhase_ == "day" then
        ReadAllInputs()
        UpdateAllPlayers(dt)
        UpdateGroundPotions(dt)
        UpdateCircleShrink(dt)
        if phaseTimer_ <= 0 then
            EnterPhase("settle")
        end
    elseif gamePhase_ == "settle" then
        if settleSubPhase_ == "countdown" then
            if phaseTimer_ <= 0 then
                OnSettleElimination()
            end
        elseif settleSubPhase_ == "elimination" then
            if phaseTimer_ <= 0 then
                if gamePhase_ ~= "gameover" then
                    EnterPhase("shrinking")
                end
            end
        end
    elseif gamePhase_ == "shrinking" then
        if phaseTimer_ <= 0 then
            EnterPhase("day")
        end
    end

    -- 状态同步(20Hz)
    syncTimer_ = syncTimer_ + dt
    if syncTimer_ >= SYNC_INTERVAL then
        syncTimer_ = 0
        SyncPlayerStates()
    end
end

-- ============================================================================
-- 输入读取
-- ============================================================================
function ReadAllInputs()
    for _, info in pairs(playerConnections_) do
        if info.ready and info.playerId then
            local pData = players_[info.playerId]
            if pData and pData.alive and not pData.isAI then
                local conn = info.connection
                pData.inputYaw = conn.controls.yaw
                pData.inputPitch = conn.controls.pitch
                pData.inputButtons = conn.controls.buttons
            end
        end
    end
end

-- ============================================================================
-- 玩家更新
-- ============================================================================
function UpdateAllPlayers(dt)
    for pid, p in pairs(players_) do
        if not p.alive and not p.isGhost then goto continue end

        -- 鬼魂只能移动, 跳过攻击/喝药/毒圈等逻辑
        if p.isGhost then
            if not p.isAI then
                ApplyPlayerInput(p, dt)
            end
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            goto continue
        end

        p.attackCooldown = math.max(0, p.attackCooldown - dt)
        UpdateAttackState(p, dt)
        UpdateDrinkingState(p, dt)

        if p.isAI then
            UpdateAI(p, dt)
        else
            ApplyPlayerInput(p, dt)
        end

        -- 移动(开放世界, 无边界限制)
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt

        -- 毒圈外加毒
        local dToCenter = dist(p.x, p.y, circle_.cx, circle_.cy)
        if dToCenter > circle_.radius and (gamePhase_ == "day" or gamePhase_ == "shrinking") then
            local poisonRate = CONFIG.CirclePoisonRate + (currentRound_ - 1) * 5
            p.poison = clamp(p.poison + poisonRate * dt, CONFIG.PoisonMin, CONFIG.PoisonMax)
        end

        -- 舒适区占领
        UpdateComfortZone(p, pid, dt)

        -- 即时死亡: 毒值>=100
        if p.poison >= CONFIG.PoisonMax then
            p.alive = false
            p.isGhost = true
            p.vx = 0
            p.vy = 0
            for _, zone in ipairs(comfortZones_) do
                if zone.occupiedBy == pid then zone.occupiedBy = nil end
            end
            UpdatePlayerNode(pid)

            local deathData = VariantMap()
            deathData["PlayerId"] = Variant(pid)
            deathData["Reason"] = Variant("poison_max")
            network:BroadcastRemoteEvent(Shared.EVENTS.PLAYER_DIED, true, deathData)
            CheckGameEnd()
        end

        -- 更新节点位置
        if p.node then
            p.node.position = Vector3(p.x, 0, p.y)
        end

        ::continue::
    end
end

function UpdateComfortZone(p, pid, dt)
    if not p.comfortClaims then p.comfortClaims = {} end
    local inZone = false
    for zi, zone in ipairs(comfortZones_) do
        if zone.corrupted then goto nextZone end
        if dist(p.x, p.y, zone.x, zone.y) > CONFIG.ComfortZoneRadius then goto nextZone end
        if zone.occupiedBy and zone.occupiedBy ~= pid then break end

        inZone = true
        if not p.comfortClaims[zi] then
            p.comfortClaims[zi] = { claimed = false, claimTimer = 0, energyLeft = 0 }
        end
        local claim = p.comfortClaims[zi]
        local isStanding = (math.abs(p.vx) < 0.1 and math.abs(p.vy) < 0.1)

        if claim.claimed and claim.energyLeft > 0 then
            zone.occupiedBy = pid
            p.isCapturingZone = false
            local regenAmount = CONFIG.ComfortZoneRegenRate * dt
            local actualRegen = math.min(regenAmount, claim.energyLeft)
            p.energy = clamp(p.energy + actualRegen, CONFIG.EnergyMin, CONFIG.EnergyMax)
            claim.energyLeft = claim.energyLeft - actualRegen
            if claim.energyLeft <= 0 then
                claim.claimed = false
                claim.energyLeft = 0
                zone.occupiedBy = nil
            end
        elseif not claim.claimed then
            zone.occupiedBy = pid
            p.isCapturingZone = true
            p.currentComfortZoneIdx = zi
            if isStanding then
                claim.claimTimer = claim.claimTimer + dt
                p.comfortStandTimer = claim.claimTimer
                if claim.claimTimer >= CONFIG.ComfortZoneWaitTime then
                    claim.claimed = true
                    claim.energyLeft = CONFIG.ComfortZoneClaimEnergy
                    p.isCapturingZone = false
                end
            else
                claim.claimTimer = 0
                p.comfortStandTimer = 0
                p.isCapturingZone = false
            end
        end
        break
        ::nextZone::
    end
    if not inZone then
        p.isCapturingZone = false
        p.comfortStandTimer = 0
        for _, zone in ipairs(comfortZones_) do
            if zone.occupiedBy == pid then zone.occupiedBy = nil end
        end
    end
end

function ApplyPlayerInput(p, dt)
    if p.drinkingState ~= "idle" or p.interactState ~= "idle" then
        p.vx = 0
        p.vy = 0
        return
    end
    if p.attackState == "recovery" then
        p.vx = 0
        p.vy = 0
        return
    end

    local buttons = p.inputButtons
    local moveAngle = math.rad(p.inputYaw)
    local moveMag = p.inputPitch

    p.sprinting = (buttons & Shared.BUTTONS.SPRINT) ~= 0
    local speed = CONFIG.MoveSpeed
    if p.sprinting and p.energy > 0 then
        speed = speed * CONFIG.SprintSpeedMultiplier
        p.energy = clamp(p.energy - CONFIG.SprintCostRate * dt, CONFIG.EnergyMin, CONFIG.EnergyMax)
    end
    if p.energy <= 0 then
        speed = CONFIG.MoveSpeedMin
    end

    if moveMag > 0.1 then
        p.vx = math.cos(moveAngle) * speed * clamp(moveMag, 0, 1)
        p.vy = math.sin(moveAngle) * speed * clamp(moveMag, 0, 1)
        p.facing = moveAngle
    else
        p.vx = 0
        p.vy = 0
    end

    -- 脉冲按键: 攻击
    if (buttons & Shared.BUTTONS.ATTACK) ~= 0 then
        PerformAttack(p)
    end
    -- 脉冲按键: 喝药
    if (buttons & Shared.BUTTONS.DRINK) ~= 0 then
        if p.potionState then
            StartDrinking(p, p.potionState)
        end
    end
end

-- ============================================================================
-- 攻击系统
-- ============================================================================
function PerformAttack(attacker)
    if gamePhase_ ~= "day" then return end
    if attacker.drinkingState ~= "idle" then return end
    if attacker.energy < CONFIG.AttackCostEnergy then return end
    if attacker.attackCooldown > 0 then return end
    if attacker.attackState ~= "idle" then return end

    attacker.energy = attacker.energy - CONFIG.AttackCostEnergy
    attacker.attackCooldown = CONFIG.AttackCooldown
    attacker.attackState = "windup"
    attacker.attackStateTimer = CONFIG.AttackWindup
end

function UpdateAttackState(p, dt)
    if p.attackState == "windup" then
        p.attackStateTimer = p.attackStateTimer - dt
        if p.attackStateTimer <= 0 then
            ResolveAttackHit(p)
            p.attackState = "recovery"
            p.attackStateTimer = CONFIG.AttackRecovery
        end
    elseif p.attackState == "recovery" then
        p.attackStateTimer = p.attackStateTimer - dt
        p.vx = 0
        p.vy = 0
        if p.attackStateTimer <= 0 then
            p.attackState = "idle"
        end
    end
end

function ResolveAttackHit(attacker)
    local halfAngle = math.rad(CONFIG.AttackAngle / 2)
    for pid, target in pairs(players_) do
        if pid ~= attacker.id and target.alive then
            local d = dist(attacker.x, attacker.y, target.x, target.y)
            if d <= CONFIG.AttackRange then
                local angleToTarget = angleBetween(attacker.x, attacker.y, target.x, target.y)
                local angleDiff = normalizeAngle(angleToTarget - attacker.facing)
                if math.abs(angleDiff) <= halfAngle then
                    -- 命中
                    attacker.poison = clamp(attacker.poison - CONFIG.AttackPoisonReduce, CONFIG.PoisonMin, CONFIG.PoisonMax)
                    target.poison = clamp(target.poison + CONFIG.AttackPoisonAdd, CONFIG.PoisonMin, CONFIG.PoisonMax)

                    local stealAmount = math.min(CONFIG.EnergyStealOnHit, target.energy)
                    target.energy = clamp(target.energy - stealAmount, CONFIG.EnergyMin, CONFIG.EnergyMax)
                    attacker.energy = clamp(attacker.energy + stealAmount, CONFIG.EnergyMin, CONFIG.EnergyMax)

                    -- 打断喝药
                    InterruptDrinking(target, attacker.id)
                    -- 打断舒适区占领
                    if target.isCapturingZone then
                        target.isCapturingZone = false
                        local zi = target.currentComfortZoneIdx
                        if zi and target.comfortClaims and target.comfortClaims[zi] then
                            target.comfortClaims[zi].claimTimer = 0
                        end
                        for _, zone in ipairs(comfortZones_) do
                            if zone.occupiedBy == pid then zone.occupiedBy = nil end
                        end
                    end

                    -- 广播命中
                    local hitData = VariantMap()
                    hitData["AttackerId"] = Variant(attacker.id)
                    hitData["TargetId"] = Variant(pid)
                    network:BroadcastRemoteEvent(Shared.EVENTS.PLAYER_HIT, true, hitData)
                end
            end
        end
    end
end

-- ============================================================================
-- 喝药系统
-- ============================================================================
function StartDrinking(p, potionType)
    -- 胜利药水只能在最后一天(最终轮)才能喝
    if potionType == "victory" and currentRound_ < CONFIG.TotalRounds then return false end
    -- 普通药水只能白天喝; 胜利药水任何阶段都行
    if potionType ~= "victory" and gamePhase_ ~= "day" then return false end
    if not p.alive then return false end
    if p.drinkingState ~= "idle" then return false end
    if p.attackState ~= "idle" then return false end
    if p.potionState ~= potionType then return false end
    if p.energy < CONFIG.DrinkCostEnergy then return false end

    p.energy = p.energy - CONFIG.DrinkCostEnergy
    p.drinkingState = "drinking"
    p.drinkingTimer = CONFIG.DrinkDuration
    p.drinkingType = potionType
    p.vx = 0
    p.vy = 0

    local data = VariantMap()
    data["PlayerId"] = Variant(p.id)
    data["Type"] = Variant(potionType)
    data["Action"] = Variant("start")
    network:BroadcastRemoteEvent(Shared.EVENTS.DRINK_EVENT, true, data)
    return true
end

function UpdateDrinkingState(p, dt)
    if p.drinkingState == "drinking" then
        p.drinkingTimer = p.drinkingTimer - dt
        p.vx = 0
        p.vy = 0
        if p.drinkingTimer <= 0 then
            CompleteDrinking(p)
        end
    elseif p.drinkingState == "stunned" then
        p.drinkingTimer = p.drinkingTimer - dt
        p.vx = 0
        p.vy = 0
        if p.drinkingTimer <= 0 then
            p.drinkingState = "idle"
        end
    end
end

function CompleteDrinking(p)
    local wasType = p.drinkingType
    if p.drinkingType == "antidote" then
        p.poison = CONFIG.PoisonMin
        p.potionState = nil
        SendFloatingText(p.x, p.y, "解毒成功!", 80, 220, 255)
    elseif p.drinkingType == "poison" then
        p.poison = clamp(p.poison + CONFIG.PoisonDrinkAmount, CONFIG.PoisonMin, CONFIG.PoisonMax)
        p.potionState = nil
    end
    p.drinkingState = "idle"
    p.drinkingTimer = 0
    p.drinkingType = nil
    UpdatePlayerNode(p.id)

    -- 广播喝药完成事件给客户端(用于音效和特效)
    local data = VariantMap()
    data["PlayerId"] = Variant(p.id)
    data["Action"] = Variant("complete")
    data["Type"] = Variant(wasType or "")
    network:BroadcastRemoteEvent(Shared.EVENTS.DRINK_EVENT, true, data)
end

function InterruptDrinking(target, attackerId)
    if target.drinkingState ~= "drinking" then return end
    local wasType = target.drinkingType

    target.drinkingState = "stunned"
    target.drinkingTimer = CONFIG.DrinkStunDuration
    target.drinkingType = nil

    if wasType == "antidote" then
        target.potionState = nil
        table.insert(groundPotions_, {
            x = target.x + (math.random() - 0.5) * 30,
            y = target.y + (math.random() - 0.5) * 20,
            type = "antidote",
        })
        BroadcastGroundPotions()
    elseif wasType == "poison" then
        target.potionState = nil
        local attacker = players_[attackerId]
        if attacker and attacker.alive then
            attacker.poison = clamp(attacker.poison + CONFIG.DrinkInterruptPoisonTransfer, CONFIG.PoisonMin, CONFIG.PoisonMax)
            UpdatePlayerNode(attackerId)
        end
    end

    local data = VariantMap()
    data["PlayerId"] = Variant(target.id)
    data["Action"] = Variant("interrupt")
    network:BroadcastRemoteEvent(Shared.EVENTS.DRINK_EVENT, true, data)
end

-- ============================================================================
-- AI
-- ============================================================================
function UpdateAI(p, dt)
    if p.drinkingState ~= "idle" then p.vx = 0; p.vy = 0; return end

    -- AI喝解药
    if p.potionState == "antidote" and p.poison > 30 and gamePhase_ == "day" then
        local nearestDist = math.huge
        for pid2, p2 in pairs(players_) do
            if pid2 ~= p.id and p2.alive then
                local d = dist(p.x, p.y, p2.x, p2.y)
                if d < nearestDist then nearestDist = d end
            end
        end
        if nearestDist > 100 and math.random() < 0.02 then
            StartDrinking(p, "antidote")
            return
        end
    end

    p.aiTimer = p.aiTimer - dt
    if p.aiTimer > 0 then
        local dx = p.aiTargetX - p.x
        local dy = p.aiTargetY - p.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d > 5 then
            p.vx = (dx / d) * CONFIG.MoveSpeed
            p.vy = (dy / d) * CONFIG.MoveSpeed
            p.facing = math.atan(dy, dx)
        else
            p.vx = 0
            p.vy = 0
        end
        if p.aiWantsAttack then PerformAttack(p) end
        return
    end

    p.aiTimer = CONFIG.AIUpdateInterval + math.random() * 0.2

    local nearestDist = math.huge
    local nearestTarget = nil
    for pid2, p2 in pairs(players_) do
        if pid2 ~= p.id and p2.alive then
            local d = dist(p.x, p.y, p2.x, p2.y)
            if d < nearestDist then
                nearestDist = d
                nearestTarget = p2
            end
        end
    end

    if nearestTarget then
        if p.poison > 20 and p.energy > 30 then
            p.aiTargetX = nearestTarget.x + (math.random() - 0.5) * 50
            p.aiTargetY = nearestTarget.y + (math.random() - 0.5) * 50
            p.aiWantsAttack = nearestDist < CONFIG.AttackRange * 1.2
        elseif p.poison <= 0 then
            local awayAngle = angleBetween(nearestTarget.x, nearestTarget.y, p.x, p.y)
            p.aiTargetX = p.x + math.cos(awayAngle) * 200
            p.aiTargetY = p.y + math.sin(awayAngle) * 200
            p.aiWantsAttack = false
        else
            p.aiTargetX = p.x + (math.random() - 0.5) * 300
            p.aiTargetY = p.y + (math.random() - 0.5) * 300
            p.aiWantsAttack = nearestDist < CONFIG.AttackRange
        end
    else
        p.aiTargetX = CONFIG.MapSize / 2 + (math.random() - 0.5) * 400
        p.aiTargetY = CONFIG.MapSize / 2 + (math.random() - 0.5) * 400
        p.aiWantsAttack = false
    end

    -- 保持在毒圈内
    local dToCenter = dist(p.aiTargetX, p.aiTargetY, circle_.cx, circle_.cy)
    if dToCenter > circle_.radius * 0.8 then
        p.aiTargetX = lerp(p.aiTargetX, circle_.cx, 0.5)
        p.aiTargetY = lerp(p.aiTargetY, circle_.cy, 0.5)
    end
end

-- ============================================================================
-- 地面药剂 & 毒圈
-- ============================================================================
function UpdateGroundPotions(dt)
    local i = 1
    while i <= #groundPotions_ do
        local gp = groundPotions_[i]
        local picked = false
        for pid, p in pairs(players_) do
            if p.alive and p.potionState == nil and p.drinkingState == "idle" then
                local d = dist(p.x, p.y, gp.x, gp.y)
                if d <= CONFIG.GroundPotionPickupRange then
                    p.potionState = gp.type
                    UpdatePlayerNode(pid)
                    picked = true
                    break
                end
            end
        end
        if picked then
            table.remove(groundPotions_, i)
            BroadcastGroundPotions()
        else
            i = i + 1
        end
    end
end

function UpdateCircleShrink(dt)
    if circle_.radius > circle_.targetRadius then
        circle_.radius = math.max(circle_.targetRadius, circle_.radius - circle_.shrinkSpeed * dt)
    end
end

-- ============================================================================
-- 舒适区生成
-- ============================================================================
function GenerateComfortZones(cx, cy, safeRadius, count)
    local zoneTypes = {"campfire", "spring", "altar"}
    for i = 1, count do
        local placed = false
        for attempt = 1, 50 do
            local angle = math.random() * math.pi * 2
            local r = math.random() * safeRadius * 0.7
            local zx = cx + math.cos(angle) * r
            local zy = cy + math.sin(angle) * r

            local tooClose = false
            for _, existing in ipairs(comfortZones_) do
                if not existing.corrupted and dist(zx, zy, existing.x, existing.y) < CONFIG.ComfortZoneSeparation then
                    tooClose = true
                    break
                end
            end
            if not tooClose then
                table.insert(comfortZones_, {
                    x = zx, y = zy,
                    type = zoneTypes[math.random(1, 3)],
                    corrupted = false,
                    occupiedBy = nil,
                })
                placed = true
                break
            end
        end
        if not placed then
            local angle = math.random() * math.pi * 2
            local r = math.random() * safeRadius * 0.5
            table.insert(comfortZones_, {
                x = cx + math.cos(angle) * r,
                y = cy + math.sin(angle) * r,
                type = zoneTypes[math.random(1, 3)],
                corrupted = false,
                occupiedBy = nil,
            })
        end
    end
end

-- ============================================================================
-- 操作事件
-- ============================================================================
function HandlePlayerAction(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local info = playerConnections_[connKey]
    if not info or not info.playerId then return end

    local pData = players_[info.playerId]
    if not pData or not pData.alive then return end

    local actionVar = eventData["Action"]
    if not actionVar or actionVar:IsEmpty() then return end
    local action = actionVar:GetString()

    if action == "drink" then
        if pData.potionState then
            StartDrinking(pData, pData.potionState)
        end
    elseif action == "interact" then
        -- 发起交互: 寻找最近可交互的玩家
        ServerStartInteract(pData)
    elseif action == "cancel_interact" then
        ServerCancelInteract(pData)
    elseif action == "give_antidote" then
        ServerGiveItem(pData, "antidote")
    elseif action == "give_poison" then
        ServerGiveItem(pData, "poison")
    end
end

-- ============================================================================
-- 交互系统(服务端)
-- ============================================================================
function ServerStartInteract(requester)
    if gamePhase_ ~= "day" then return end
    if requester.interactState ~= "idle" then return end
    if requester.drinkingState ~= "idle" then return end
    if requester.energy < CONFIG.InteractCostEnergy then return end

    -- 寻找最近可交互玩家
    local bestDist = CONFIG.InteractRange
    local bestTarget = nil
    for pid, p in pairs(players_) do
        if pid ~= requester.id and p.alive and p.interactState == "idle" and p.drinkingState == "idle" then
            local d = Shared.dist(requester.x, requester.y, p.x, p.y)
            if d < bestDist then
                bestDist = d
                bestTarget = p
            end
        end
    end

    if not bestTarget then return end

    -- 设置状态
    requester.interactState = "requesting"
    requester.interactPartner = bestTarget.id
    requester.interactTimer = CONFIG.InteractAcceptTimeout

    -- AI自动接受交互
    if bestTarget.isAI then
        bestTarget.interactState = "interacting"
        bestTarget.interactPartner = requester.id
        requester.interactState = "interacting"
        requester.interactTimer = CONFIG.InteractDuration

        -- 广播accept事件
        local data = VariantMap()
        data["Action"] = Variant("accept")
        data["PlayerId"] = Variant(requester.id)
        data["TargetId"] = Variant(bestTarget.id)
        network:BroadcastRemoteEvent(Shared.EVENTS.INTERACT_EVENT, true, data)
    else
        -- 广播request事件
        local data = VariantMap()
        data["Action"] = Variant("request")
        data["PlayerId"] = Variant(requester.id)
        data["TargetId"] = Variant(bestTarget.id)
        network:BroadcastRemoteEvent(Shared.EVENTS.INTERACT_EVENT, true, data)
    end
end

function ServerCancelInteract(player)
    if player.interactState == "idle" then return end
    local partnerId = player.interactPartner
    local partner = partnerId and players_[partnerId]

    player.interactState = "idle"
    player.interactPartner = nil
    player.interactTimer = 0
    player.interactGiveType = nil

    if partner then
        partner.interactState = "idle"
        partner.interactPartner = nil
        partner.interactTimer = 0
        partner.interactGiveType = nil
    end

    local data = VariantMap()
    data["Action"] = Variant("cancel")
    data["PlayerId"] = Variant(player.id)
    data["TargetId"] = Variant(partnerId or 0)
    network:BroadcastRemoteEvent(Shared.EVENTS.INTERACT_EVENT, true, data)
end

function ServerGiveItem(player, giveType)
    if player.interactState ~= "interacting" then return end
    local partnerId = player.interactPartner
    local partner = partnerId and players_[partnerId]
    if not partner then
        ServerCancelInteract(player)
        return
    end

    -- 扣能量
    player.energy = Shared.clamp(player.energy - CONFIG.InteractCostEnergy, CONFIG.EnergyMin, CONFIG.EnergyMax)

    -- 执行物品给予效果
    if giveType == "antidote" then
        partner.poison = Shared.clamp(partner.poison - CONFIG.AttackPoisonReduce, CONFIG.PoisonMin, CONFIG.PoisonMax)
        SendFloatingText(partner.x, partner.y - 30, "获得解药!", 80, 220, 80)
    elseif giveType == "poison" then
        partner.poison = Shared.clamp(partner.poison + CONFIG.AttackPoisonAdd, CONFIG.PoisonMin, CONFIG.PoisonMax)
        SendFloatingText(partner.x, partner.y - 30, "被下毒!", 220, 80, 80)
    end

    -- 广播give事件
    local data = VariantMap()
    data["Action"] = Variant("give")
    data["PlayerId"] = Variant(player.id)
    data["TargetId"] = Variant(partnerId)
    data["GiveType"] = Variant(giveType)
    network:BroadcastRemoteEvent(Shared.EVENTS.INTERACT_EVENT, true, data)

    -- 交互结束
    player.interactState = "idle"
    player.interactPartner = nil
    player.interactTimer = 0
    partner.interactState = "idle"
    partner.interactPartner = nil
    partner.interactTimer = 0

    local endData = VariantMap()
    endData["Action"] = Variant("complete")
    endData["PlayerId"] = Variant(player.id)
    endData["TargetId"] = Variant(partnerId)
    network:BroadcastRemoteEvent(Shared.EVENTS.INTERACT_EVENT, true, endData)
end

-- ============================================================================
-- 状态同步
-- ============================================================================
function SyncPlayerStates()
    for pid, p in pairs(players_) do
        if p.node then
            p.node.position = Vector3(p.x, 0, p.y)
            p.node:SetVar(Shared.VARS.FACING, Variant(p.facing))
            p.node:SetVar(Shared.VARS.POISON, Variant(p.poison))
            p.node:SetVar(Shared.VARS.ENERGY, Variant(p.energy))
            p.node:SetVar(Shared.VARS.ALIVE, Variant(p.alive))
            p.node:SetVar(Shared.VARS.SPRINTING, Variant(p.sprinting))

            local atkState = p.attackState == "windup" and 1 or (p.attackState == "recovery" and 2 or 0)
            p.node:SetVar(Shared.VARS.ATTACK_STATE, Variant(atkState))

            local drkState = p.drinkingState == "drinking" and 1 or (p.drinkingState == "stunned" and 2 or 0)
            p.node:SetVar(Shared.VARS.DRINK_STATE, Variant(drkState))

            local potState = 0
            if p.potionState == "antidote" then potState = 1
            elseif p.potionState == "poison" then potState = 2 end
            p.node:SetVar(Shared.VARS.POTION_STATE, Variant(potState))

            -- 占领进度同步
            p.node:SetVar(Shared.VARS.CAPTURING, Variant(p.isCapturingZone or false))
            p.node:SetVar(Shared.VARS.CLAIM_TIMER, Variant(p.comfortStandTimer or 0.0))
        end
    end
end

function UpdatePlayerNode(pid)
    local p = players_[pid]
    if p and p.node then
        p.node:SetVar(Shared.VARS.ALIVE, Variant(p.alive))
        local potState = 0
        if p.potionState == "antidote" then potState = 1
        elseif p.potionState == "poison" then potState = 2 end
        p.node:SetVar(Shared.VARS.POTION_STATE, Variant(potState))
    end
end

-- ============================================================================
-- 广播工具
-- ============================================================================
function SendFloatingText(x, y, text, r, g, b)
    local data = VariantMap()
    data["X"] = Variant(x)
    data["Y"] = Variant(y)
    data["Text"] = Variant(text)
    data["R"] = Variant(r)
    data["G"] = Variant(g)
    data["B"] = Variant(b)
    network:BroadcastRemoteEvent(Shared.EVENTS.FLOATING_TEXT, true, data)
end

function BroadcastCircle()
    local data = VariantMap()
    data["CX"] = Variant(circle_.cx)
    data["CY"] = Variant(circle_.cy)
    data["Radius"] = Variant(circle_.radius)
    data["TargetRadius"] = Variant(circle_.targetRadius)
    data["ShrinkSpeed"] = Variant(circle_.shrinkSpeed)
    network:BroadcastRemoteEvent(Shared.EVENTS.CIRCLE_UPDATE, true, data)
end

function BroadcastComfortZones()
    local data = VariantMap()
    local idx = 0
    for _, zone in ipairs(comfortZones_) do
        if not zone.corrupted then
            data["ZX" .. idx] = Variant(zone.x)
            data["ZY" .. idx] = Variant(zone.y)
            data["ZT" .. idx] = Variant(zone.type)
            data["ZU" .. idx] = Variant(zone.zoneUsesLeft or 5)
            data["ZE" .. idx] = Variant(zone.zoneEnergy or 100.0)
            data["ZO" .. idx] = Variant(zone.occupiedBy or 0)
            data["ZC" .. idx] = Variant(zone.zoneCooldown or 0.0)
            idx = idx + 1
        end
    end
    data["Count"] = Variant(idx)
    network:BroadcastRemoteEvent(Shared.EVENTS.COMFORT_ZONE_SYNC, true, data)
end

function BroadcastGroundPotions()
    local data = VariantMap()
    for i, gp in ipairs(groundPotions_) do
        data["GX" .. (i-1)] = Variant(gp.x)
        data["GY" .. (i-1)] = Variant(gp.y)
        data["GT" .. (i-1)] = Variant(gp.type)
    end
    data["Count"] = Variant(#groundPotions_)
    network:BroadcastRemoteEvent(Shared.EVENTS.GROUND_POTION_SYNC, true, data)
end
