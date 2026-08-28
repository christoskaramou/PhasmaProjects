-- Run with: local code = assert(fs.read("Scripts/samples/skinned2d_wave_sample.lua")); assert(load(code))(); skinned2d_wave_sample.reset()

if not sample_boot then
    assert(load(assert(fs.read("Scripts/samples/sample_boot.lua"))))()
end

skinned2d_wave_sample = skinned2d_wave_sample or {}

local M = skinned2d_wave_sample
local UPDATE_ID = "skinned2d_wave_sample"
local WAVE_AMP = math.rad(18.0)
local TAG = "[Skinned2D Sample]"

local state = {
    strip = nil,
    time = 0.0,
    previous_render_mode = nil,
    joint_count = 0,
    rotations = {},
}

local function update()
    if not state.strip or not state.strip:is_valid() then
        return
    end

    state.time = state.time + sample_boot.dt()

    local joint_count = state.joint_count
    if joint_count <= 0 then
        return
    end

    local rotations = state.rotations
    local denom = math.max(joint_count - 1, 1)
    for i = 1, joint_count do
        local u = (i - 1) / denom
        rotations[i] = math.sin(state.time * 4.0 + u * 4.2) * WAVE_AMP * u
    end
    animation.set_joint_rotations_z(state.strip, rotations)
end

function M.stop()
    if script then
        script.remove_update(UPDATE_ID)
    end
    sample_boot.restore_raster(state)
    state.strip = nil
    state.time = 0.0
    state.joint_count = 0
    state.rotations = {}
end

function M.reset()
    if not primitives or not primitives.skinned_strip_2d then
        sample_boot.log(TAG, "primitives.skinned_strip_2d is unavailable")
        return false
    end
    if not animation or not animation.set_joint_rotations_z then
        sample_boot.log(TAG, "procedural animation bindings are unavailable")
        return false
    end

    M.stop()
    scene.clear()
    if sample_boot.apply_raster(state) then
        sample_boot.log(TAG, "render mode set to raster")
    end
    sample_boot.ortho_camera()

    state.strip = primitives.skinned_strip_2d(8.0, 1.25, 64, 24)
    state.strip:set_name("Skinned2D Procedural Strip")
    state.strip:set_position(vec3(0.0, 0.0, 0.0))
    state.joint_count = animation.get_joint_count(state.strip)
    state.rotations = {}
    if material then
        material.set(state.strip, "base_color", vec4(0.16, 0.72, 0.86, 1.0))
    end

    script.on_update(UPDATE_ID, update, "always")
    update()
    sample_boot.log(TAG, "ready")
    return true
end
