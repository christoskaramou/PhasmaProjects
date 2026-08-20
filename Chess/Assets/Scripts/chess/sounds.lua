-- sounds.lua -- chess sound effects. WAVs live in Assets/Audio/chess/; audio.play
-- resolves paths under Assets/Audio/. `audio` may be nil (editor configs), so every
-- touch is guarded.

local S = {}

-- 0..1, pushed straight to the engine's SFX bus. There is no separate mute: the menu offers
-- one "Sound Volume 0-100" control and 0 IS off, which is one control instead of two.
local volume = 0.15

local function apply()
    if audio and audio.set_sfx_volume then audio.set_sfx_volume(volume) end
end

function S.init(v)
    if v then volume = math.max(0.0, math.min(1.0, v)) end
    apply()
end

-- 0..1. There is no getter on the engine side, so this module is the only owner of the
-- value and the menu reads it back from here.
function S.set_volume(v)
    volume = math.max(0.0, math.min(1.0, v or 0))
    apply()
    return volume
end

function S.volume()
    return volume
end

function S.play(name)
    if volume > 0 and audio and audio.play then
        audio.play("chess/" .. name .. ".wav")
    end
end

return S
