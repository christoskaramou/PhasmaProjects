-- Automated persistence validation for ColumnChunkStore + VoxelWorld save path.
-- Logs VOXELCRAFT_PERSISTENCE_SMOKE_OK on success; engine.quit() on pass/fail.

local SAVE_DIR = "VoxelWorlds/persistence_smoke_test"
local GROUND_Y = 4

local frame = 0
local phase = "boot"
local earlyEditQueued = false

local function fail(msg)
    pe_log("[voxelcraft_persistence_smoke] FAIL " .. tostring(msg))
    engine.quit()
end

local function wait_ground()
    local ground = voxel.get_block(0, GROUND_Y - 1, 0)
    if ground == 0 then
        if frame > 360 then
            fail("timed out waiting for generated ground")
        end
        return false
    end
    if ground ~= 3 then
        fail("expected grass id 3 at 0," .. tostring(GROUND_Y - 1) .. ",0; got " .. tostring(ground))
    end
    return true
end

local function boot_world()
    voxel.create({
        load_radius = 1,
        unload_margin = 1,
        ground_y = GROUND_Y,
        upload_budget = 32,
        save_dir = SAVE_DIR,
    })
    voxel.set_anchor(0.5, 6.0, 0.5)
    if not earlyEditQueued then
        voxel.set_block(0, 8, 0, 1)
        earlyEditQueued = true
    end
end

function init()
    pe_log("[voxelcraft_persistence_smoke] START")
    boot_world()
end

function update()
    frame = frame + 1
    voxel.set_anchor(0.5, 6.0, 0.5)

    if phase == "boot" then
        if not wait_ground() then
            return
        end
        if voxel.get_block(0, 8, 0) ~= 1 then
            fail("generation-time queued edit missing at 0,8,0")
        end
        voxel.set_block(0, 4, 0, 1)
        if voxel.get_block(0, 4, 0) ~= 1 then
            fail("section-0 edit did not apply at 0,4,0")
        end
        if not voxel.save_all() then
            fail("save_all failed after section-0 edit")
        end
        voxel.destroy()
        phase = "reload_after_section0"
        frame = 0
        boot_world()
        return
    end

    if phase == "reload_after_section0" then
        if not wait_ground() then
            return
        end
        if voxel.get_block(0, 4, 0) ~= 1 then
            fail("section-0 edit lost after reload")
        end
        if voxel.get_block(0, 8, 0) ~= 1 then
            fail("generation-time edit lost after reload")
        end
        voxel.set_block(0, 20, 0, 2)
        if voxel.get_block(0, 20, 0) ~= 2 then
            fail("section-1 edit did not apply at 0,20,0")
        end
        if not voxel.save_all() then
            fail("save_all failed after section-1 edit")
        end
        voxel.destroy()
        phase = "reload_after_section1"
        frame = 0
        boot_world()
        return
    end

    if phase == "reload_after_section1" then
        if not wait_ground() then
            return
        end
        if voxel.get_block(0, 4, 0) ~= 1 then
            fail("section-0 lost after section-1 save (truncation regression)")
        end
        if voxel.get_block(0, 8, 0) ~= 1 then
            fail("generation-time edit lost after section-1 save")
        end
        if voxel.get_block(0, 20, 0) ~= 2 then
            fail("section-1 edit lost after final reload")
        end
        phase = "done"
        return
    end

    if phase == "done" and frame > 30 then
        pe_log("[voxelcraft_persistence_smoke] VOXELCRAFT_PERSISTENCE_SMOKE_OK")
        engine.quit()
    end
end
