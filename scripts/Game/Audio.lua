local Audio = {}

local sfxNode = nil
local sfxCache = {}
local bgmSource = nil
local bgmPlaylist = {
    "audio/游戏音乐/疯猪追月.ogg",
    "audio/游戏音乐/倒计时乱跑.ogg",
    "audio/游戏音乐/毒圈童话.ogg",
}
local bgmCurrentIdx = 0

function Audio.init(scene)
    sfxNode = scene:CreateChild("SFX")
    bgmSource = sfxNode:CreateComponent("SoundSource")
    bgmSource:SetSoundType("Music")
    bgmSource:SetGain(0.4)
end

function Audio.playSound(name, gain, panning)
    if not sfxNode then return end
    local path = "audio/sfx/" .. name .. ".ogg"
    local sound = sfxCache[path]
    if not sound then
        sound = cache:GetResource("Sound", path)
        if not sound then return end
        sfxCache[path] = sound
    end
    local source = sfxNode:CreateComponent("SoundSource")
    source:SetSoundType("Effect")
    source:SetAutoRemoveMode(REMOVE_COMPONENT)
    source:SetGain(gain or 0.6)
    if panning then source:SetPanning(panning) end
    source:Play(sound)
end

-- 播放背景音乐指定曲目(最后一首循环)
function Audio.playBgmTrack(idx)
    if not bgmSource then return end
    if idx < 1 or idx > #bgmPlaylist then return end
    bgmCurrentIdx = idx
    local path = bgmPlaylist[idx]
    local sound = cache:GetResource("Sound", path)
    if sound then
        -- 最后一首循环播放,其余播放一次
        sound.looped = (idx == #bgmPlaylist)
        bgmSource:Play(sound)
        print("[BGM] 播放第" .. idx .. "首: " .. path .. (sound.looped and " (循环)" or ""))
    else
        print("[BGM] WARNING: 无法加载: " .. path)
    end
end

-- 检测当前曲目播完并切换下一首
function Audio.updateBgm()
    if not bgmSource then return end
    if not bgmSource:IsPlaying() then
        if bgmCurrentIdx == 0 then
            -- 特殊曲目(黑夜倒计时)播完,恢复播放列表第1首
            Audio.playBgmTrack(1)
        elseif bgmCurrentIdx < #bgmPlaylist then
            -- 播放列表中下一首
            Audio.playBgmTrack(bgmCurrentIdx + 1)
        end
    end
end

return Audio
