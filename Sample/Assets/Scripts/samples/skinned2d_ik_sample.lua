-- Run with: local code = assert(fs.read("Scripts/samples/skinned2d_ik_sample.lua")); assert(load(code))(); skinned2d_ik_sample.reset()

if not sample_boot then
    assert(load(assert(fs.read("Scripts/samples/sample_boot.lua"))))()
end

skinned2d_ik_sample = skinned2d_ik_sample or {}

local M = skinned2d_ik_sample
local UPDATE_ID = "skinned2d_ik_sample"
local TAG = "[Skinned2D IK Sample]"

local state = {
    strip = nil,
    target = nil,
    joint_influences = nil,
    width_scales = nil,
    time = 0.0,
    previous_render_mode = nil,
    ik_target = vec2(0.0, 0.0),
    marker_pos = vec3(0.0, 0.0, 0.08),
}

local function update()
    if not state.strip or not state.strip:is_valid() then
        return
    end

    state.time = state.time + sample_boot.dt()

    local target = state.ik_target
    target.x = 2.60 + math.sin(state.time * 1.4) * 2.10
    target.y = math.sin(state.time * 2.1) * 1.55

    if state.target and state.target:is_valid() then
        local pos = state.marker_pos
        pos.x = target.x
        pos.y = target.y
        state.target:set_position(pos)
    end

    animation.solve_strip_ik_2d(state.strip, target, 10, 60.0, 1.45, state.joint_influences, state.width_scales)
end

function M.stop()
    if script then
        script.remove_update(UPDATE_ID)
    end
    sample_boot.restore_raster(state)
    state.strip = nil
    state.target = nil
    state.joint_influences = nil
    state.width_scales = nil
    state.time = 0.0
end

function M.reset()
    if not primitives or not primitives.skinned_strip_2d then
        sample_boot.log(TAG, "primitives.skinned_strip_2d is unavailable")
        return false
    end
    if not animation or not animation.solve_strip_ik_2d then
        sample_boot.log(TAG, "2D strip IK binding is unavailable")
        return false
    end

    M.stop()
    scene.clear()
    if sample_boot.apply_raster(state) then
        sample_boot.log(TAG, "render mode set to raster")
    end
    sample_boot.ortho_camera()

    state.strip = primitives.skinned_strip_2d(7.0, 0.75, 64, 32)
    state.strip:set_name("Skinned2D IK Strip")
    state.strip:set_position(vec3(0.0, 0.0, 0.0))
    state.joint_influences = {}
    state.width_scales = {}
    local joint_count = animation.get_joint_count(state.strip)
    for i = 1, joint_count do
        local t = (i - 1) / math.max(joint_count - 1, 1)
        state.joint_influences[i] = 0.35 + math.sin(t * math.pi) * 1.15
        state.width_scales[i] = 1.2 - t * 0.75
    end

    state.target = primitives.circle(0.16, 32)
    state.target:set_name("Skinned2D IK Target")
    state.marker_pos.x = 2.35
    state.marker_pos.y = 0.0
    state.target:set_position(state.marker_pos)

    if material then
        material.set(state.strip, "base_color", vec4(0.12, 0.68, 0.86, 1.0))
        material.set(state.target, "base_color", vec4(1.0, 0.76, 0.18, 1.0))
    end

    script.on_update(UPDATE_ID, update, "always")
    update()
    sample_boot.log(TAG, "ready")
    return true
end
