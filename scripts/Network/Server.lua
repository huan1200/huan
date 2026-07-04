-- ============================================================================
-- Network/Server.lua
-- 《道友请留步》多人版 - 权威服务器
-- 运行全部游戏逻辑：移动、攻击、喝药、交互、毒圈、AI、回合、组队
-- ============================================================================

---@diagnostic disable: undefined-global

local Shared = require("Network.Shared")
local CONFIG = Shared.CONFIG
local dist = Shared.dist
local angleBetween = Shared.angleBetween
local normalizeAngle = Shared.normalizeAngle
local clamp = Shared.clamp
local lerp = Shared.lerp

local Server = {}

-- ============================================================================
-- 服务器状态
-- ============================================================================
local scene_ = nil
local playerConnections_ = {}   -- { [connKey] = { connection, playerId, teamId } }
local players_ = {}             -- { [playerId] = playerData }
local teams_ = {}               -- { [teamId] = { playerIds = {}, alive = true } }
local nextPlayerId_ = 1
local nextTeamId_ = 1

-- 游戏阶段
local gamePhase_ = "waiting"    -- waiting/prepare/day/settle/shrinking/gameover
local currentRound_ = 0
local phaseTimer_ = 0
local settleSubPhase_ = "countdown"
local victoryTeamId_ = nil
local victoryPotionGiven_ = false
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
local SYNC_INTERVAL = 0.05  -- 20Hz 状态同步

-- ============================================================================
-- 玩家数据结构
-- ============================================================================
local function createPlayerData(playerId, teamId, isAI)
    return {
        id = playerId,
        teamId = teamId,
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
        -- AI
        aiTimer = 0,
        aiTargetX = 0,
        aiTargetY = 0,
        aiWantsAttack = false,
        -- 输入(从connection.controls读取)
        inputYaw = 0,
        inputButtons = 0,
        inputPitch = 0,  -- 用作移动方向角度(弧度)
        -- 网络节点
        node = nil,
        -- 昵称
        nickname = "",
    }
end

-- ============================================================================
-- 初始化
-- ============================================================================
function Server.Start()
    print("[Server] Starting... MaxPlayers=" .. SERVER_MAX_PLAYERS
        .. " RegisteredPlayers=" .. SERVER_REGISTERED_PLAYERS)

    -- 创建场景(网络同步必需)
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

    -- 等待玩家连接后开始游戏
    gamePhase_ = "waiting"
    print("[Server] Waiting for players...")
end

function Server.Stop()
    print("[Server] Stopping...")
end

-- ============================================================================
-- 连接管理
-- ============================================================================
function HandleClientConnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    print("[Server] Client connected: " .. connKey)

    -- 配置脉冲按键
    connection:SetPulseButtonMask(Shared.PULSE_MASK)

    -- 暂存连接，等待 ClientReady
    playerConnections_[connKey] = {
        connection = connection,
        playerId = nil,
        teamId = nil,
        ready = false,
    }
end

function HandleClientIdentity(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local info = playerConnections_[connKey]
    if not info then return end

    -- 获取用户ID用于昵称查询
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

    -- 分配玩家ID和队伍
    local playerId = nextPlayerId_
    nextPlayerId_ = nextPlayerId_ + 1
    info.playerId = playerId

    -- 自动组队(每3人一队)
    local teamId = math.ceil(playerId / CONFIG.TeamSize)
    info.teamId = teamId

    if not teams_[teamId] then
        teams_[teamId] = { playerIds = {}, alive = true }
    end
    table.insert(teams_[teamId].playerIds, playerId)

    -- 创建玩家数据
    local pData = createPlayerData(playerId, teamId, false)
    pData.nickname = "玩家" .. playerId
    players_[playerId] = pData

    -- 查询昵称
    if info.userId then
        GetUserNickname({
            userIds = { info.userId },
            onSuccess = function(nicknames)
                if nicknames[1] then
                    pData.nickname = nicknames[1].nickname
                    -- 更新节点变量
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
    assignData["TeamId"] = Variant(teamId)
    connection:SendRemoteEvent(Shared.EVENTS.ASSIGN_PLAYER, true, assignData)

    print("[Server] Player " .. playerId .. " assigned to team " .. teamId)

    -- 检查是否可以开始游戏
    Server.CheckGameStart()
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
-- 游戏开始逻辑
-- ============================================================================
function Server.CheckGameStart()
    if gameStarted_ then return end

    local readyCount = 0
    for _, info in pairs(playerConnections_) do
        if info.ready then readyCount = readyCount + 1 end
    end

    -- 所有注册玩家都就绪后开始
    if readyCount >= SERVER_REGISTERED_PLAYERS then
        Server.StartGame()
    end
end

function Server.StartGame()
    if gameStarted_ then return end
    gameStarted_ = true
    print("[Server] All players ready, starting game!")

    -- 填充AI玩家
    local realPlayerCount = 0
    for _ in pairs(players_) do realPlayerCount = realPlayerCount + 1 end
    local aiCount = CONFIG.MaxPlayers - realPlayerCount
    if aiCount < 0 then aiCount = 0 end

    print("[Server] Adding " .. aiCount .. " AI players")
    for i = 1, aiCount do
        local aiId = nextPlayerId_
        nextPlayerId_ = nextPlayerId_ + 1

        local teamId = math.ceil(aiId / CONFIG.TeamSize)
        if not teams_[teamId] then
            teams_[teamId] = { playerIds = {}, alive = true }
        end
        table.insert(teams_[teamId].playerIds, aiId)

        local aiData = createPlayerData(aiId, teamId, true)
        aiData.nickname = "修仙者" .. aiId
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

        -- 创建网络节点
        local node = scene_:CreateChild("Player_" .. pid, REPLICATED)
        node.position = Vector3(pData.x, 0, pData.y)
        node:SetVar(Shared.VARS.PLAYER_ID, Variant(pid))
        node:SetVar(Shared.VARS.TEAM_ID, Variant(pData.teamId))
        node:SetVar(Shared.VARS.ALIVE, Variant(true))
        node:SetVar(Shared.VARS.POISON, Variant(0.0))
        node:SetVar(Shared.VARS.ENERGY, Variant(CONFIG.EnergyMax))
        node:SetVar(Shared.VARS.POTION_STATE, Variant(0))
        node:SetVar(Shared.VARS.ATTACK_STATE, Variant(0))
        node:SetVar(Shared.VARS.DRINK_STATE, Variant(0))
        node:SetVar(Shared.VARS.INTERACT_STATE, Variant(0))
        node:SetVar(Shared.VARS.FACING, Variant(pData.facing))
        node:SetVar(Shared.VARS.IS_AI, Variant(pData.isAI))
        node:SetVar(Shared.VARS.SPRINTING, Variant(false))
        node:SetVar(Shared.VARS.NICKNAME, Variant(pData.nickname))
        pData.node = node

        idx = idx + 1
    end

    -- 生成初始舒适区
    Server.GenerateComfortZones(cx, cy, circleInitRadius_)

    -- 发送队伍信息给所有客户端
    Server.BroadcastTeamInfo()

    -- 同步舒适区
    Server.BroadcastComfortZones()

    -- 进入准备阶段
    Server.EnterPhase("prepare")
end

-- ============================================================================
-- 阶段管理
-- ============================================================================
function Server.EnterPhase(phase)
    gamePhase_ = phase
    print("[Server] Phase: " .. phase .. " Round: " .. currentRound_)

    if phase == "prepare" then
        phaseTimer_ = CONFIG.PrepareDuration
        currentRound_ = 0
    elseif phase == "day" then
        phaseTimer_ = CONFIG.DayDuration
        currentRound_ = currentRound_ + 1
        Server.OnDayStart()
    elseif phase == "settle" then
        phaseTimer_ = CONFIG.NightfallDuration
        settleSubPhase_ = "countdown"
        Server.OnSettleStart()
    elseif phase == "shrinking" then
        phaseTimer_ = CONFIG.CircleShrinkDuration
        Server.OnShrinkStart()
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

function Server.OnDayStart()
    -- 每轮白天: 全员+30毒, 旧解药变毒, 50%发解药
    local aliveList = {}
    for pid, p in pairs(players_) do
        if p.alive then
            -- 旧解药变毒药
            if p.potionState == "antidote" then
                p.potionState = "poison"
                p.poison = clamp(p.poison + CONFIG.PoisonPerRound, CONFIG.PoisonMin, CONFIG.PoisonMax)
                Server.SendFloatingText(p.x, p.y, "+30毒(变质)", 180, 60, 200)
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
        Server.UpdatePlayerNode(pid)
        Server.SendFloatingText(players_[pid].x, players_[pid].y, "获得解药!", 100, 200, 255)
    end

    -- 清除地面药剂
    groundPotions_ = {}
    Server.BroadcastGroundPotions()
end

function Server.OnSettleStart()
    -- 强制停止所有玩家
    for _, p in pairs(players_) do
        p.vx = 0
        p.vy = 0
    end
end

function Server.OnSettleElimination()
    settleSubPhase_ = "elimination"
    phaseTimer_ = CONFIG.SettleDuration

    -- 所有 poison > 0 的存活玩家死亡
    local deaths = {}
    for pid, p in pairs(players_) do
        if p.alive and p.poison > 0 then
            p.alive = false
            p.isGhost = true
            p.vx = 0
            p.vy = 0
            -- 释放舒适区占用
            for _, zone in ipairs(comfortZones_) do
                if zone.occupiedBy == pid then zone.occupiedBy = nil end
            end
            table.insert(deaths, pid)
            Server.UpdatePlayerNode(pid)

            -- 广播死亡
            local deathData = VariantMap()
            deathData["PlayerId"] = Variant(pid)
            deathData["Reason"] = Variant("poison_settle")
            network:BroadcastRemoteEvent(Shared.EVENTS.PLAYER_DIED, true, deathData)
        end
    end

    -- 检查游戏结束条件
    Server.CheckGameEnd()
end

function Server.OnShrinkStart()
    local nextTargetRadius = circle_.radius * CONFIG.CircleShrinkRatio

    -- 标记毒圈外舒适区为腐败
    for _, zone in ipairs(comfortZones_) do
        local d = dist(zone.x, zone.y, circle_.cx, circle_.cy)
        if d > nextTargetRadius then
            zone.corrupted = true
        end
    end

    -- 补充新舒适区
    local activeCount = 0
    for _, zone in ipairs(comfortZones_) do
        if not zone.corrupted then activeCount = activeCount + 1 end
    end
    if activeCount < 3 then
        Server.GenerateComfortZones(circle_.cx, circle_.cy, nextTargetRadius)
    end

    circle_.targetRadius = nextTargetRadius
    circle_.shrinkSpeed = (circle_.radius - circle_.targetRadius) / CONFIG.DayDuration

    -- 广播毒圈更新
    Server.BroadcastCircle()
    Server.BroadcastComfortZones()
end

-- ============================================================================
-- 游戏结束检查
-- ============================================================================
function Server.CheckGameEnd()
    -- 统计存活队伍
    local aliveTeams = {}
    for teamId, team in pairs(teams_) do
        local hasAlive = false
        for _, pid in ipairs(team.playerIds) do
            if players_[pid] and players_[pid].alive then
                hasAlive = true
                break
            end
        end
        team.alive = hasAlive
        if hasAlive then
            table.insert(aliveTeams, teamId)
        end
    end

    if #aliveTeams == 0 then
        -- 全灭
        Server.EndGame(nil)
    elseif #aliveTeams == 1 and not victoryPotionGiven_ then
        -- 最后一队存活 → 发放胜利药水
        victoryTeamId_ = aliveTeams[1]
        victoryPotionGiven_ = true
        for _, pid in ipairs(teams_[victoryTeamId_].playerIds) do
            local p = players_[pid]
            if p and p.alive then
                p.potionState = "victory"
                p.poison = 0
                Server.UpdatePlayerNode(pid)
                Server.SendFloatingText(p.x, p.y, "胜利药水!", 255, 215, 0)
            end
        end
    end
end

function Server.EndGame(winTeamId)
    local data = VariantMap()
    data["WinTeamId"] = Variant(winTeamId or 0)
    network:BroadcastRemoteEvent(Shared.EVENTS.GAME_OVER, true, data)
    Server.EnterPhase("gameover")
end

-- ============================================================================
-- 主更新循环
-- ============================================================================
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    if not gameStarted_ then return end

    -- 阶段计时器
    phaseTimer_ = phaseTimer_ - dt

    -- 阶段逻辑
    if gamePhase_ == "prepare" then
        Server.ReadAllInputs()
        Server.UpdateAllPlayers(dt)
        if phaseTimer_ <= 0 then
            Server.EnterPhase("day")
        end
    elseif gamePhase_ == "day" then
        Server.ReadAllInputs()
        Server.UpdateAllPlayers(dt)
        Server.UpdateGroundPotions(dt)
        Server.UpdateCircleShrink(dt)
        if phaseTimer_ <= 0 then
            Server.EnterPhase("settle")
        end
    elseif gamePhase_ == "settle" then
        if settleSubPhase_ == "countdown" then
            if phaseTimer_ <= 0 then
                Server.OnSettleElimination()
            end
        elseif settleSubPhase_ == "elimination" then
            if phaseTimer_ <= 0 then
                if gamePhase_ ~= "gameover" then
                    Server.EnterPhase("shrinking")
                end
            end
        end
    elseif gamePhase_ == "shrinking" then
        if phaseTimer_ <= 0 then
            Server.EnterPhase("day")
        end
    elseif gamePhase_ == "gameover" then
        -- 等待
    end

    -- 状态同步
    syncTimer_ = syncTimer_ + dt
    if syncTimer_ >= SYNC_INTERVAL then
        syncTimer_ = 0
        Server.SyncPlayerStates()
    end
end

-- ============================================================================
-- 输入读取
-- ============================================================================
function Server.ReadAllInputs()
    for connKey, info in pairs(playerConnections_) do
        if info.ready and info.playerId then
            local pData = players_[info.playerId]
            if pData and pData.alive and not pData.isAI then
                local conn = info.connection
                pData.inputYaw = conn.controls.yaw        -- 移动方向角度(度)
                pData.inputPitch = conn.controls.pitch    -- 移动力度(0-1)
                pData.inputButtons = conn.controls.buttons
            end
        end
    end
end

-- ============================================================================
-- 玩家更新
-- ============================================================================
function Server.UpdateAllPlayers(dt)
    for pid, p in pairs(players_) do
        if not p.alive then goto continue end

        -- 更新冷却
        p.attackCooldown = math.max(0, p.attackCooldown - dt)

        -- 攻击状态机
        Server.UpdateAttackState(p, dt)

        -- 喝药状态
        Server.UpdateDrinkingState(p, dt)

        -- 交互状态
        Server.UpdateInteractionState(p, dt)

        -- AI或真人输入
        if p.isAI then
            Server.UpdateAI(p, dt)
        else
            Server.ApplyPlayerInput(p, dt)
        end

        -- 移动
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt

        -- 边界限制
        p.x = clamp(p.x, 0, CONFIG.MapSize)
        p.y = clamp(p.y, 0, CONFIG.MapSize)

        -- 毒圈外加毒
        local dToCenter = dist(p.x, p.y, circle_.cx, circle_.cy)
        if dToCenter > circle_.radius and (gamePhase_ == "day" or gamePhase_ == "shrinking") then
            local poisonRate = CONFIG.CirclePoisonRate + (currentRound_ - 1) * 5
            p.poison = clamp(p.poison + poisonRate * dt, CONFIG.PoisonMin, CONFIG.PoisonMax)
        end

        -- 舒适区站点占领机制(站立3秒占领 → 获得100能量点 → 用完需重新占领)
        if not p.comfortClaims then p.comfortClaims = {} end
        local inZone = false
        for zi, zone in ipairs(comfortZones_) do
            if zone.corrupted then goto nextZoneSrv end
            if dist(p.x, p.y, zone.x, zone.y) > CONFIG.ComfortZoneRadius then goto nextZoneSrv end
            -- 独占检查: 已被其他玩家占用则不能进入
            if zone.occupiedBy and zone.occupiedBy ~= pid then break end

            inZone = true
            if not p.comfortClaims[zi] then
                p.comfortClaims[zi] = { claimed = false, claimTimer = 0, energyLeft = 0 }
            end
            local claim = p.comfortClaims[zi]

            -- 判断是否站着不动
            local isStanding = (math.abs(p.vx) < 0.1 and math.abs(p.vy) < 0.1)

            if claim.claimed and claim.energyLeft > 0 then
                -- 已占领且有剩余能量 → 持续回复
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
                -- 未占领 → 需要站立3秒占领
                zone.occupiedBy = pid
                p.isCapturingZone = true
                p.currentComfortZoneIdx = zi
                if isStanding then
                    claim.claimTimer = claim.claimTimer + dt
                    if claim.claimTimer >= CONFIG.ComfortZoneWaitTime then
                        claim.claimed = true
                        claim.energyLeft = CONFIG.ComfortZoneClaimEnergy
                        p.isCapturingZone = false
                    end
                else
                    claim.claimTimer = 0
                    p.isCapturingZone = false
                end
            end
            break
            ::nextZoneSrv::
        end
        -- 离开舒适区时释放占用
        if not inZone then
            p.isCapturingZone = false
            for _, zone in ipairs(comfortZones_) do
                if zone.occupiedBy == pid then zone.occupiedBy = nil end
            end
        end

        -- 即时死亡: 毒值>=100
        if p.poison >= CONFIG.PoisonMax then
            p.alive = false
            p.isGhost = true
            p.vx = 0
            p.vy = 0
            -- 释放舒适区占用
            for _, zone in ipairs(comfortZones_) do
                if zone.occupiedBy == pid then zone.occupiedBy = nil end
            end
            Server.UpdatePlayerNode(pid)

            local deathData = VariantMap()
            deathData["PlayerId"] = Variant(pid)
            deathData["Reason"] = Variant("poison_max")
            network:BroadcastRemoteEvent(Shared.EVENTS.PLAYER_DIED, true, deathData)

            Server.CheckGameEnd()
        end

        -- 更新节点位置
        if p.node then
            p.node.position = Vector3(p.x, 0, p.y)
        end

        ::continue::
    end
end

function Server.ApplyPlayerInput(p, dt)
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
    local moveAngle = math.rad(p.inputYaw)    -- 移动方向
    local moveMag = p.inputPitch              -- 移动力度 (0~1)

    -- 奔跑
    p.sprinting = (buttons & Shared.BUTTONS.SPRINT) ~= 0
    local speed = CONFIG.MoveSpeed
    if p.sprinting and p.energy > 0 then
        speed = speed * CONFIG.SprintSpeedMultiplier
        p.energy = clamp(p.energy - CONFIG.SprintCostRate * dt, CONFIG.EnergyMin, CONFIG.EnergyMax)
    end

    -- 能量耗尽减速
    if p.energy <= 0 then
        speed = CONFIG.MoveSpeedMin
    end

    -- 应用移动
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
        Server.PerformAttack(p)
    end

    -- 脉冲按键: 喝药
    if (buttons & Shared.BUTTONS.DRINK) ~= 0 then
        if p.potionState then
            Server.StartDrinking(p, p.potionState)
        end
    end
end

-- ============================================================================
-- 攻击系统
-- ============================================================================
function Server.PerformAttack(attacker)
    if gamePhase_ ~= "day" then return end
    if attacker.drinkingState ~= "idle" then return end
    if attacker.interactState ~= "idle" then return end
    if attacker.energy < CONFIG.AttackCostEnergy then return end
    if attacker.attackCooldown > 0 then return end
    if attacker.attackState ~= "idle" then return end

    attacker.energy = attacker.energy - CONFIG.AttackCostEnergy
    attacker.attackCooldown = CONFIG.AttackCooldown
    attacker.attackState = "windup"
    attacker.attackStateTimer = CONFIG.AttackWindup
end

function Server.UpdateAttackState(p, dt)
    if p.attackState == "windup" then
        p.attackStateTimer = p.attackStateTimer - dt
        if p.attackStateTimer <= 0 then
            Server.ResolveAttackHit(p)
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

function Server.ResolveAttackHit(attacker)
    local halfAngle = math.rad(CONFIG.AttackAngle / 2)

    for pid, target in pairs(players_) do
        if pid ~= attacker.id and target.alive then
            local d = dist(attacker.x, attacker.y, target.x, target.y)
            if d <= CONFIG.AttackRange then
                local angleToTarget = angleBetween(attacker.x, attacker.y, target.x, target.y)
                local angleDiff = normalizeAngle(angleToTarget - attacker.facing)
                if math.abs(angleDiff) <= halfAngle then
                    -- 队友伤害减半
                    local dmgMult = 1.0
                    if attacker.teamId == target.teamId then
                        dmgMult = CONFIG.TeamDamageReduction
                    end

                    -- 命中
                    attacker.poison = clamp(attacker.poison - CONFIG.AttackPoisonReduce, CONFIG.PoisonMin, CONFIG.PoisonMax)
                    target.poison = clamp(target.poison + CONFIG.AttackPoisonAdd * dmgMult, CONFIG.PoisonMin, CONFIG.PoisonMax)

                    local stealAmount = math.min(CONFIG.EnergyStealOnHit, target.energy)
                    target.energy = clamp(target.energy - stealAmount, CONFIG.EnergyMin, CONFIG.EnergyMax)
                    attacker.energy = clamp(attacker.energy + stealAmount, CONFIG.EnergyMin, CONFIG.EnergyMax)

                    -- 打断喝药
                    Server.InterruptDrinking(target, attacker.id)
                    -- 打断交互
                    Server.InterruptInteract(target)
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

                    -- 广播命中事件
                    local hitData = VariantMap()
                    hitData["AttackerId"] = Variant(attacker.id)
                    hitData["TargetId"] = Variant(pid)
                    hitData["Damage"] = Variant(CONFIG.AttackPoisonAdd * dmgMult)
                    network:BroadcastRemoteEvent(Shared.EVENTS.PLAYER_HIT, true, hitData)
                end
            end
        end
    end
end

-- ============================================================================
-- 喝药系统
-- ============================================================================
function Server.StartDrinking(p, potionType)
    if potionType ~= "victory" and gamePhase_ ~= "day" then return false end
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

    -- 广播喝药事件
    local data = VariantMap()
    data["PlayerId"] = Variant(p.id)
    data["Type"] = Variant(potionType)
    data["Action"] = Variant("start")
    network:BroadcastRemoteEvent(Shared.EVENTS.DRINK_EVENT, true, data)
    return true
end

function Server.UpdateDrinkingState(p, dt)
    if p.drinkingState == "drinking" then
        p.drinkingTimer = p.drinkingTimer - dt
        p.vx = 0
        p.vy = 0
        if p.drinkingTimer <= 0 then
            Server.CompleteDrinking(p)
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

function Server.CompleteDrinking(p)
    if p.drinkingType == "antidote" then
        p.poison = CONFIG.PoisonMin
        p.potionState = nil
        Server.SendFloatingText(p.x, p.y, "解毒成功!", 80, 220, 255)
    elseif p.drinkingType == "poison" then
        p.poison = clamp(p.poison + CONFIG.PoisonDrinkAmount, CONFIG.PoisonMin, CONFIG.PoisonMax)
        p.potionState = nil
    elseif p.drinkingType == "victory" then
        p.potionState = nil
        -- 全队胜利
        victoryTeamId_ = p.teamId
        Server.EndGame(p.teamId)
    end
    p.drinkingState = "idle"
    p.drinkingTimer = 0
    p.drinkingType = nil
    Server.UpdatePlayerNode(p.id)

    local data = VariantMap()
    data["PlayerId"] = Variant(p.id)
    data["Type"] = Variant(p.drinkingType or "")
    data["Action"] = Variant("complete")
    network:BroadcastRemoteEvent(Shared.EVENTS.DRINK_EVENT, true, data)
end

function Server.InterruptDrinking(target, attackerId)
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
        Server.BroadcastGroundPotions()
    elseif wasType == "poison" then
        target.potionState = nil
        local attacker = players_[attackerId]
        if attacker and attacker.alive then
            attacker.potionState = "poison"
            attacker.poison = clamp(attacker.poison + CONFIG.DrinkInterruptPoisonTransfer, CONFIG.PoisonMin, CONFIG.PoisonMax)
            Server.UpdatePlayerNode(attackerId)
        end
    end

    local data = VariantMap()
    data["PlayerId"] = Variant(target.id)
    data["Action"] = Variant("interrupt")
    data["AttackerId"] = Variant(attackerId)
    network:BroadcastRemoteEvent(Shared.EVENTS.DRINK_EVENT, true, data)
end

-- ============================================================================
-- 交互系统
-- ============================================================================
function Server.UpdateInteractionState(p, dt)
    if p.interactState == "idle" then return end

    if p.interactState == "requesting" then
        p.interactTimer = p.interactTimer - dt
        p.vx = 0
        p.vy = 0
        if p.interactTimer <= 0 then
            local partner = players_[p.interactPartner]
            if partner and partner.interactState == "pending" then
                Server.AcceptInteract(partner)
            else
                Server.CancelInteract(p)
            end
        end
    elseif p.interactState == "pending" then
        p.interactTimer = p.interactTimer - dt
        p.vx = 0
        p.vy = 0
        if p.interactTimer <= 0 then
            Server.AcceptInteract(p)
        end
    elseif p.interactState == "interacting" then
        p.interactTimer = p.interactTimer - dt
        p.vx = 0
        p.vy = 0
        if p.interactTimer <= 0 then
            Server.CancelInteract(p)
        end
    elseif p.interactState == "giving" then
        p.vx = 0
        p.vy = 0
        p.interactTimer = p.interactTimer - dt
        if p.interactTimer <= 0 then
            Server.CompleteGive(p)
        end
    end
end

function Server.RequestInteract(requester, targetId)
    if gamePhase_ ~= "day" then return false end
    if not requester.alive then return false end
    if requester.interactState ~= "idle" then return false end
    if requester.drinkingState ~= "idle" then return false end
    if requester.attackState ~= "idle" then return false end
    if requester.energy < CONFIG.InteractCostEnergy then return false end

    local target = players_[targetId]
    if not target or not target.alive then return false end
    if target.interactState ~= "idle" then return false end

    local d = dist(requester.x, requester.y, target.x, target.y)
    if d > CONFIG.InteractRange then return false end

    requester.energy = requester.energy - CONFIG.InteractCostEnergy
    requester.interactState = "requesting"
    requester.interactPartner = targetId
    requester.interactTimer = CONFIG.InteractAcceptTimeout

    target.interactState = "pending"
    target.interactPartner = requester.id
    target.interactTimer = CONFIG.InteractAcceptTimeout

    local data = VariantMap()
    data["RequesterId"] = Variant(requester.id)
    data["TargetId"] = Variant(targetId)
    data["Action"] = Variant("request")
    network:BroadcastRemoteEvent(Shared.EVENTS.INTERACT_EVENT, true, data)
    return true
end

function Server.AcceptInteract(player)
    if player.interactState ~= "pending" then return end
    local partner = players_[player.interactPartner]
    if not partner or partner.interactState ~= "requesting" then
        Server.CancelInteract(player)
        return
    end

    player.interactState = "interacting"
    player.interactTimer = CONFIG.InteractDuration
    partner.interactState = "interacting"
    partner.interactTimer = CONFIG.InteractDuration
    player.vx = 0
    player.vy = 0
    partner.vx = 0
    partner.vy = 0

    local data = VariantMap()
    data["PlayerId"] = Variant(player.id)
    data["PartnerId"] = Variant(partner.id)
    data["Action"] = Variant("accept")
    network:BroadcastRemoteEvent(Shared.EVENTS.INTERACT_EVENT, true, data)
end

function Server.CancelInteract(player)
    if player.interactState == "idle" then return end
    local partnerId = player.interactPartner
    player.interactState = "idle"
    player.interactPartner = nil
    player.interactTimer = 0
    player.interactGiveType = nil

    if partnerId then
        local partner = players_[partnerId]
        if partner then
            partner.interactState = "idle"
            partner.interactPartner = nil
            partner.interactTimer = 0
            partner.interactGiveType = nil
        end
    end
end

function Server.GiveItem(giver, itemType)
    if giver.interactState ~= "interacting" then return false end
    if not giver.potionState then return false end
    local receiver = players_[giver.interactPartner]
    if not receiver then return false end

    giver.interactGiveType = itemType
    giver.interactState = "giving"
    giver.interactTimer = 0.6  -- 抛物线动画时间
    giver.potionState = nil
    Server.UpdatePlayerNode(giver.id)

    local data = VariantMap()
    data["GiverId"] = Variant(giver.id)
    data["ReceiverId"] = Variant(giver.interactPartner)
    data["ItemType"] = Variant(itemType)
    data["Action"] = Variant("give")
    network:BroadcastRemoteEvent(Shared.EVENTS.INTERACT_EVENT, true, data)
    return true
end

function Server.CompleteGive(giver)
    local receiverId = giver.interactPartner
    local receiver = players_[receiverId]
    local itemType = giver.interactGiveType

    if receiver and receiver.alive and itemType then
        local isTeammate = giver.teamId == receiver.teamId
        if itemType == "antidote" then
            local healAmount = 15 * (isTeammate and CONFIG.TeamHealBonus or 1.0)
            receiver.poison = clamp(receiver.poison - healAmount, CONFIG.PoisonMin, CONFIG.PoisonMax)
        elseif itemType == "poison" then
            receiver.poison = clamp(receiver.poison + 25, CONFIG.PoisonMin, CONFIG.PoisonMax)
        end
        Server.UpdatePlayerNode(receiverId)
    end

    -- 重置双方
    giver.interactState = "idle"
    giver.interactPartner = nil
    giver.interactTimer = 0
    giver.interactGiveType = nil
    if receiver then
        receiver.interactState = "idle"
        receiver.interactPartner = nil
        receiver.interactTimer = 0
        receiver.interactGiveType = nil
    end
end

function Server.InterruptInteract(player)
    if player.interactState == "idle" then return end
    Server.CancelInteract(player)
end

-- ============================================================================
-- AI 逻辑
-- ============================================================================
function Server.UpdateAI(p, dt)
    if p.drinkingState ~= "idle" then p.vx = 0; p.vy = 0; return end
    if p.interactState ~= "idle" then
        p.vx = 0; p.vy = 0
        -- AI在interacting状态给药
        if p.interactState == "interacting" and p.potionState then
            if p.interactTimer < CONFIG.InteractDuration - 0.5 then
                if math.random() < 0.02 then
                    local partner = players_[p.interactPartner]
                    local isTeammate = partner and partner.teamId == p.teamId
                    if p.potionState == "poison" and not isTeammate then
                        Server.GiveItem(p, "poison")
                    elseif p.potionState == "antidote" then
                        Server.GiveItem(p, "antidote")
                    end
                end
            end
        end
        if p.interactState == "pending" and p.interactTimer < CONFIG.InteractAcceptTimeout - 0.5 then
            if math.random() < 0.1 then Server.AcceptInteract(p) end
        end
        return
    end

    -- AI胜利药水: 立刻喝
    if p.potionState == "victory" then
        Server.StartDrinking(p, "victory")
        return
    end

    -- AI喝解药
    if p.potionState == "antidote" and p.poison > 30 and gamePhase_ == "day" then
        local nearestDist = math.huge
        for pid2, p2 in pairs(players_) do
            if pid2 ~= p.id and p2.alive and p2.teamId ~= p.teamId then
                local d = dist(p.x, p.y, p2.x, p2.y)
                if d < nearestDist then nearestDist = d end
            end
        end
        if nearestDist > 100 and math.random() < 0.02 then
            Server.StartDrinking(p, "antidote")
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
        if p.aiWantsAttack then Server.PerformAttack(p) end
        return
    end

    -- 重新决策
    p.aiTimer = CONFIG.AIUpdateInterval + math.random() * 0.2

    local nearestDist = math.huge
    local nearestTarget = nil
    for pid2, p2 in pairs(players_) do
        if pid2 ~= p.id and p2.alive and p2.teamId ~= p.teamId then
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
-- 地面药剂
-- ============================================================================
function Server.UpdateGroundPotions(dt)
    local i = 1
    while i <= #groundPotions_ do
        local gp = groundPotions_[i]
        local picked = false
        for pid, p in pairs(players_) do
            if p.alive and p.potionState == nil and p.drinkingState == "idle" then
                local d = dist(p.x, p.y, gp.x, gp.y)
                if d <= CONFIG.GroundPotionPickupRange then
                    p.potionState = gp.type
                    Server.UpdatePlayerNode(pid)
                    Server.SendFloatingText(p.x, p.y, gp.type == "antidote" and "拾取解药" or "拾取毒药", 100, 200, 255)
                    picked = true
                    break
                end
            end
        end
        if picked then
            table.remove(groundPotions_, i)
            Server.BroadcastGroundPotions()
        else
            i = i + 1
        end
    end
end

-- ============================================================================
-- 毒圈收缩
-- ============================================================================
function Server.UpdateCircleShrink(dt)
    if circle_.radius > circle_.targetRadius then
        circle_.radius = math.max(circle_.targetRadius, circle_.radius - circle_.shrinkSpeed * dt)
    end
end

-- ============================================================================
-- 舒适区生成
-- ============================================================================
function Server.GenerateComfortZones(cx, cy, safeRadius)
    local zoneTypes = {"campfire", "spring", "altar"}
    local zoneCount = math.random(2, 4)
    for i = 1, zoneCount do
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
            })
        end
    end
end

-- ============================================================================
-- 操作事件处理
-- ============================================================================
function HandlePlayerAction(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = Shared.GetConnectionKey(connection)
    local info = playerConnections_[connKey]
    if not info or not info.playerId then return end

    local pData = players_[info.playerId]
    if not pData or not pData.alive then return end

    local action = eventData["Action"]:GetInt()

    if action == Shared.ACTIONS.DRINK then
        if pData.potionState then
            Server.StartDrinking(pData, pData.potionState)
        end
    elseif action == Shared.ACTIONS.INTERACT then
        local targetId = eventData["TargetId"]:GetInt()
        Server.RequestInteract(pData, targetId)
    elseif action == Shared.ACTIONS.ACCEPT_INTERACT then
        Server.AcceptInteract(pData)
    elseif action == Shared.ACTIONS.GIVE_ITEM then
        local itemType = eventData["ItemType"]:GetString()
        Server.GiveItem(pData, itemType)
    elseif action == Shared.ACTIONS.CANCEL_INTERACT then
        Server.CancelInteract(pData)
    end
end

-- ============================================================================
-- 状态同步
-- ============================================================================
function Server.SyncPlayerStates()
    -- 批量同步所有玩家位置和关键状态到客户端
    -- 使用节点变量自动同步 + 远程事件补充
    for pid, p in pairs(players_) do
        if p.node then
            p.node.position = Vector3(p.x, 0, p.y)
            p.node:SetVar(Shared.VARS.FACING, Variant(p.facing))
            p.node:SetVar(Shared.VARS.POISON, Variant(p.poison))
            p.node:SetVar(Shared.VARS.ENERGY, Variant(p.energy))
            p.node:SetVar(Shared.VARS.ALIVE, Variant(p.alive))
            p.node:SetVar(Shared.VARS.SPRINTING, Variant(p.sprinting))

            -- 编码状态为整数
            local atkState = p.attackState == "windup" and 1 or (p.attackState == "recovery" and 2 or 0)
            p.node:SetVar(Shared.VARS.ATTACK_STATE, Variant(atkState))

            local drkState = p.drinkingState == "drinking" and 1 or (p.drinkingState == "stunned" and 2 or 0)
            p.node:SetVar(Shared.VARS.DRINK_STATE, Variant(drkState))

            local intState = 0
            if p.interactState == "requesting" then intState = 1
            elseif p.interactState == "pending" then intState = 2
            elseif p.interactState == "interacting" then intState = 3
            elseif p.interactState == "giving" then intState = 4 end
            p.node:SetVar(Shared.VARS.INTERACT_STATE, Variant(intState))

            local potState = 0
            if p.potionState == "antidote" then potState = 1
            elseif p.potionState == "poison" then potState = 2
            elseif p.potionState == "victory" then potState = 3 end
            p.node:SetVar(Shared.VARS.POTION_STATE, Variant(potState))
        end
    end
end

function Server.UpdatePlayerNode(pid)
    local p = players_[pid]
    if p and p.node then
        p.node:SetVar(Shared.VARS.ALIVE, Variant(p.alive))
        local potState = 0
        if p.potionState == "antidote" then potState = 1
        elseif p.potionState == "poison" then potState = 2
        elseif p.potionState == "victory" then potState = 3 end
        p.node:SetVar(Shared.VARS.POTION_STATE, Variant(potState))
    end
end

-- ============================================================================
-- 广播工具
-- ============================================================================
function Server.SendFloatingText(x, y, text, r, g, b)
    local data = VariantMap()
    data["X"] = Variant(x)
    data["Y"] = Variant(y)
    data["Text"] = Variant(text)
    data["R"] = Variant(r)
    data["G"] = Variant(g)
    data["B"] = Variant(b)
    network:BroadcastRemoteEvent(Shared.EVENTS.FLOATING_TEXT, true, data)
end

function Server.BroadcastTeamInfo()
    local data = VariantMap()
    local idx = 0
    for teamId, team in pairs(teams_) do
        for _, pid in ipairs(team.playerIds) do
            data["T" .. idx] = Variant(teamId)
            data["P" .. idx] = Variant(pid)
            data["N" .. idx] = Variant(players_[pid] and players_[pid].nickname or "")
            data["AI" .. idx] = Variant(players_[pid] and players_[pid].isAI or false)
            idx = idx + 1
        end
    end
    data["Count"] = Variant(idx)
    network:BroadcastRemoteEvent(Shared.EVENTS.TEAM_INFO, true, data)
end

function Server.BroadcastCircle()
    local data = VariantMap()
    data["CX"] = Variant(circle_.cx)
    data["CY"] = Variant(circle_.cy)
    data["Radius"] = Variant(circle_.radius)
    data["TargetRadius"] = Variant(circle_.targetRadius)
    data["ShrinkSpeed"] = Variant(circle_.shrinkSpeed)
    network:BroadcastRemoteEvent(Shared.EVENTS.CIRCLE_UPDATE, true, data)
end

function Server.BroadcastComfortZones()
    local data = VariantMap()
    local idx = 0
    for _, zone in ipairs(comfortZones_) do
        if not zone.corrupted then
            data["ZX" .. idx] = Variant(zone.x)
            data["ZY" .. idx] = Variant(zone.y)
            data["ZT" .. idx] = Variant(zone.type)
            idx = idx + 1
        end
    end
    data["Count"] = Variant(idx)
    network:BroadcastRemoteEvent(Shared.EVENTS.COMFORT_ZONE_SYNC, true, data)
end

function Server.BroadcastGroundPotions()
    local data = VariantMap()
    local idx = 0
    for _, gp in ipairs(groundPotions_) do
        data["GX" .. idx] = Variant(gp.x)
        data["GY" .. idx] = Variant(gp.y)
        data["GT" .. idx] = Variant(gp.type)
        idx = idx + 1
    end
    data["Count"] = Variant(idx)
    network:BroadcastRemoteEvent(Shared.EVENTS.GROUND_POTION_SYNC, true, data)
end

return Server
