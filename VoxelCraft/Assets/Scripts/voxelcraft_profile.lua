-- voxelcraft_profile.lua — self-driving streaming + edit stress to attribute voxel main-thread
-- spikes. Two phases so the log timeline separates the two spike sources:
--   Phase A (stationary, edits): isolates the remesh/snapshot path.
--   Phase B (sweeping anchor):   isolates streaming (gen/mesh/upload).
-- Engine logs "[voxel] Update <ms>: gen= mesh= grow= arena= upload= remesh=" on any frame whose
-- main-thread voxel work crosses 0.5ms. Quits itself so the run is headless.
local frame = 0
local ax, az = 8.0, 8.0
local GROUND_Y = 64
local ANCHOR_Y = GROUND_Y + 4.0
local stats = {
    A = { frames = 0, sum_ms = 0.0, max_ms = 0.0, spikes_5ms = 0, spikes_10ms = 0 },
    B = { frames = 0, sum_ms = 0.0, max_ms = 0.0, spikes_5ms = 0, spikes_10ms = 0 },
}

local function sample_stats(phase, dt)
    if not dt or dt <= 0.0 or dt > 0.25 then return end
    local ms = dt * 1000.0
    local s = stats[phase]
    s.frames = s.frames + 1
    s.sum_ms = s.sum_ms + ms
    if ms > s.max_ms then s.max_ms = ms end
    if ms > 5.0 then s.spikes_5ms = s.spikes_5ms + 1 end
    if ms > 10.0 then s.spikes_10ms = s.spikes_10ms + 1 end
end

local function log_stats(phase)
    local s = stats[phase]
    local avg = (s.frames > 0) and (s.sum_ms / s.frames) or 0.0
    pe_log(string.format("[voxelcraft_profile] PHASE_%s avg=%.3fms max=%.3fms spikes5=%d spikes10=%d frames=%d",
        phase, avg, s.max_ms, s.spikes_5ms, s.spikes_10ms, s.frames))
end

local function edit_top(bx, bz, blk)
    for y = GROUND_Y + 32, 4, -1 do
        if voxel.get_block(bx, y, bz) ~= 0 then
            voxel.set_block(bx, y + 1, bz, blk)
            return true
        end
    end
    return false
end

function init()
    voxel.create({ load_radius = 8, unload_margin = 2, ground_y = GROUND_Y, upload_budget = 16 })
    voxel.set_anchor(ax, ANCHOR_Y, az)
    local cam = get_camera()
    if cam then
        cam:set_position(vec3(ax, ANCHOR_Y + 8.0, az))
        cam:set_euler(vec3(0.9, 3.14159, 0.0))
    end
    pe_log("[voxelcraft_profile] START load_radius=8")
end

function update(dt)
    frame = frame + 1
    sample_stats(frame <= 150 and "A" or "B", dt)

    if frame <= 150 then
        -- Phase A: stationary; edit a surface block every 3 frames once origin terrain exists.
        if frame > 30 and frame % 3 == 0 then
            local bx = 8 + (frame % 7)
            local bz = 8 + (frame % 5)
            edit_top(bx, bz, (frame % 2 == 0) and 1 or 0)
        end
        if frame == 150 then pe_log("[voxelcraft_profile] PHASE_B_SWEEP_BEGIN") end
    else
        -- Phase B: sweep the anchor so new columns stream in/out every frame.
        ax = ax + 0.5
        az = az + 0.25
        voxel.set_anchor(ax, ANCHOR_Y, az)
        local cam = get_camera()
        if cam then cam:set_position(vec3(ax, ANCHOR_Y + 8.0, az)) end
    end

    if frame >= 600 then
        log_stats("A")
        log_stats("B")
        pe_log("[voxelcraft_profile] DONE")
        engine.quit()
    end
end
