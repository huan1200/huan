-- ============================================================================
-- Game/ComfortZone.lua - 舒适区系统
-- 负责: 生成舒适区、占领机制、能量回复、冷却管理
-- ============================================================================

local CONFIG = require("Game.Config")
local State = require("Game.State")
local Utils = require("Game.Utils")
local Audio = require("Game.Audio")

local ComfortZone = {}

-- ============================================================================
-- 7.1 舒适区生成(距离约束: 300px离玩家出生点, 400px彼此分离)
-- ============================================================================

function ComfortZone.generate(cx, cy, safeRadius, count)
    local zoneTypes = {"campfire", "spring", "altar"}
    local zoneCount = count or 5
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
            for _, p in ipairs(State.players) do
                if not p.isGhost then
                    local spawnCX = CONFIG.MapSize / 2
                    local spawnCY = CONFIG.MapSize / 2
                    local spawnR = CONFIG.MapSize * 0.35
                    local spawnAngle = (p.idx - 1) * (2 * math.pi / CONFIG.PlayerCount) - math.pi / 2
                    local spX = spawnCX + math.cos(spawnAngle) * spawnR
                    local spY = spawnCY + math.sin(spawnAngle) * spawnR
                    if Utils.dist(zx, zy, spX, spY) < CONFIG.ComfortZoneMinSpawnDist then
                        tooCloseToSpawn = true
                        break
                    end
                end
            end
            if tooCloseToSpawn then goto continue end

            -- 约束2: 距离已生成的舒适区>=400px
            local tooCloseToOther = false
            for _, existing in ipairs(State.comfortZones) do
                if Utils.dist(zx, zy, existing.x, existing.y) < CONFIG.ComfortZoneSeparation then
                    tooCloseToOther = true
                    break
                end
            end
            if tooCloseToOther then goto continue end

            -- 约束3: 在安全区内
            if Utils.dist(zx, zy, cx, cy) > safeRadius - CONFIG.ComfortZoneRadius * 0.5 then
                goto continue
            end

            -- 通过所有约束, 放置舒适区
            table.insert(State.comfortZones, {
                x = zx, y = zy,
                type = zoneTypes[math.random(1, 3)],
                playersInside = {},
                zoneEnergy = 100,
                zoneCooldown = 0,
                zoneUsesLeft = 5,
            })
            placed = true
            break

            ::continue::
        end
        -- 如果50次尝试都失败, 放宽条件随机放置
        if not placed then
            local angle = math.random() * math.pi * 2
            local r = math.random() * safeRadius * 0.5
            table.insert(State.comfortZones, {
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
    print("[舒适区] 生成 " .. #State.comfortZones .. " 个舒适区")
end

-- ============================================================================
-- 舒适区冷却计时器更新
-- ============================================================================

function ComfortZone.updateCooldowns(dt)
    for _, zone in ipairs(State.comfortZones) do
        if (zone.zoneCooldown or 0) > 0 then
            zone.zoneCooldown = zone.zoneCooldown - dt
            if zone.zoneCooldown <= 0 then
                zone.zoneCooldown = 0
                if (zone.zoneUsesLeft or 0) > 0 then
                    zone.zoneEnergy = 100
                end
            end
        end
    end
end

-- ============================================================================
-- 7.2 舒适区占领与能量回复（每帧对单个玩家调用）
-- ============================================================================

function ComfortZone.updatePlayerZone(p, dt)
    local wasInComfort = p.inComfortZone
    p.inComfortZone = false
    if p.usedZoneHintCD and p.usedZoneHintCD > 0 then p.usedZoneHintCD = p.usedZoneHintCD - dt end
    local isStanding = (p.vx == 0 and p.vy == 0)
    if not p.comfortClaims then p.comfortClaims = {} end
    p.isCapturingZone = false
    p.currentComfortZoneIdx = nil

    for zi, zone in ipairs(State.comfortZones) do
        local zoneAvailable = not zone.corrupted
            and (zone.zoneUsesLeft or 5) > 0
            and (zone.zoneCooldown or 0) <= 0
            and (zone.zoneEnergy or 100) > 0
        if not zoneAvailable then goto nextZone end

        if not p.comfortClaims[zi] then
            p.comfortClaims[zi] = { claimed = false, claimTimer = 0, energyLeft = 0 }
        end
        local claim = p.comfortClaims[zi]

        -- 已占领并耗尽
        if claim.claimed and claim.energyLeft <= 0 then
            if p.isLocal and Utils.dist(p.x, p.y, zone.x, zone.y) <= CONFIG.ComfortZoneRadius then
                if not p.usedZoneHintCD or p.usedZoneHintCD <= 0 then
                    p.usedZoneHintCD = 3.0
                    table.insert(State.floatingTexts, {
                        x = p.x, y = p.y - 40,
                        text = "此舒适区能量已耗尽,请前往其他舒适区",
                        color = {200, 150, 80},
                        timer = 1.5, maxTimer = 1.5,
                    })
                end
            end
            goto nextZone
        end

        if Utils.dist(p.x, p.y, zone.x, zone.y) <= CONFIG.ComfortZoneRadius then
            -- 独占检查
            if zone.occupiedBy and zone.occupiedBy ~= p.idx then
                if p.isLocal then
                    if not p.usedZoneHintCD or p.usedZoneHintCD <= 0 then
                        p.usedZoneHintCD = 3.0
                        table.insert(State.floatingTexts, {
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
            if not wasInComfort and p.isLocal then Audio.playSound("sfx_comfort_zone_enter", 0.4) end

            -- 已占领且有剩余能量 → 直接使用
            if claim.claimed and claim.energyLeft > 0 then
                zone.occupiedBy = p.idx
                p.usingComfortZone = true
                if p.energy < CONFIG.EnergyMax then
                    local regenAmount = CONFIG.ComfortZoneRegenRate * dt
                    local actualRegen = math.min(regenAmount, claim.energyLeft)
                    actualRegen = math.min(actualRegen, zone.zoneEnergy)

                    local prevEnergy = p.energy
                    p.energy = Utils.clamp(p.energy + actualRegen, CONFIG.EnergyMin, CONFIG.EnergyMax)
                    claim.energyLeft = claim.energyLeft - actualRegen
                    zone.zoneEnergy = zone.zoneEnergy - actualRegen

                    -- 能量配额耗尽
                    if claim.energyLeft <= 0 then
                        claim.energyLeft = 0
                        claim.claimed = false
                        claim.claimTimer = 0
                        zone.occupiedBy = nil
                        p.usingComfortZone = false
                        if p.isLocal then
                            table.insert(State.floatingTexts, {
                                x = p.x, y = p.y - 50,
                                text = "能量配额已用完,需重新占领!",
                                color = {255, 200, 100},
                                timer = 1.5, maxTimer = 1.5,
                            })
                        end
                    end

                    -- 舒适区总能量耗尽
                    if zone.zoneEnergy <= 0 then
                        zone.zoneEnergy = 0
                        zone.zoneCooldown = 5.0
                        zone.zoneUsesLeft = zone.zoneUsesLeft - 1
                    end

                    -- 浮动+5数字
                    local prevTick = math.floor(prevEnergy / 5)
                    local curTick = math.floor(p.energy / 5)
                    if curTick > prevTick then
                        table.insert(State.comfortFloats, {
                            x = p.x + (math.random() - 0.5) * 10,
                            y = p.y - 40,
                            text = "+5",
                            life = 1.0,
                            maxLife = 1.0,
                            color = {80, 200, 80},
                        })
                    end
                end
            -- 未占领 → 站立等待3秒占领
            elseif not claim.claimed then
                if isStanding then
                    claim.claimTimer = claim.claimTimer + dt
                    p.isCapturingZone = true
                    p.comfortStandTimer = claim.claimTimer

                    if claim.claimTimer >= CONFIG.ComfortZoneWaitTime then
                        claim.claimed = true
                        claim.energyLeft = CONFIG.ComfortZoneClaimEnergy
                        claim.claimTimer = 0
                        zone.occupiedBy = p.idx
                        p.usingComfortZone = true
                        p.isCapturingZone = false
                        if p.isLocal then
                            Audio.playSound("sfx_comfort_zone_enter", 0.6)
                            table.insert(State.floatingTexts, {
                                x = p.x, y = p.y - 50,
                                text = "占领成功! +100能量配额",
                                color = {80, 255, 80},
                                timer = 1.5, maxTimer = 1.5,
                            })
                        end
                    end
                else
                    claim.claimTimer = 0
                    p.comfortStandTimer = 0
                    p.isCapturingZone = false
                end
            end
            break
        end
        ::nextZone::
    end

    -- 不在舒适区时重置状态
    if not p.inComfortZone then
        p.comfortStandTimer = 0
        p.isCapturingZone = false
        if p.usingComfortZone then
            for _, z in ipairs(State.comfortZones) do
                if z.occupiedBy == p.idx then z.occupiedBy = nil end
            end
            p.usingComfortZone = false
        end
    end
end

return ComfortZone
