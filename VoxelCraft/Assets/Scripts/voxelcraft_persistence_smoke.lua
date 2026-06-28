-- Automated persistence validation for ColumnChunkStore + VoxelWorld save path.
-- Logs VOXELCRAFT_PERSISTENCE_SMOKE_OK on success; engine.quit() on pass/fail.

local SAVE_DIR = "VoxelWorlds/persistence_smoke_test"
local GROUND_Y = 16
local HOME = { x = 0.5, y = 20.0, z = 0.5 }
local FAR = { x = 48.5, y = 6.0, z = 0.5 } -- unload_radius=2 for load_radius=1 unload_margin=1

local frame = 0
local phase = "boot"
local earlyEditQueued = false
local anchor = { x = HOME.x, y = HOME.y, z = HOME.z }

local function fail(msg)
    pe_log("[voxelcraft_persistence_smoke] FAIL " .. tostring(msg))
    engine.quit()
end

local function set_anchor_here()
    voxel.set_anchor(anchor.x, anchor.y, anchor.z)
end

local function wait_ground()
    local surfaceY = nil
    for y = 0, 48 do
        if voxel.get_block(0, y, 0) == 3 then
            surfaceY = y
            break
        end
    end
    if not surfaceY then
        if frame > 360 then
            fail("timed out waiting for generated ground")
        end
        return false
    end
    return true
end

local function assert_home_edits()
    if voxel.get_block(0, 4, 0) ~= 1 then
        fail("section-0 edit missing at 0,4,0")
    end
    if voxel.get_block(0, 8, 0) ~= 1 then
        fail("generation-time edit missing at 0,8,0")
    end
    if voxel.get_block(0, 20, 0) ~= 2 then
        fail("section-1 edit missing at 0,20,0")
    end
end

local function boot_world()
    voxel.create({
        load_radius = 1,
        unload_margin = 1,
        ground_y = GROUND_Y,
        upload_budget = 32,
        save_dir = SAVE_DIR,
    })
    anchor.x, anchor.y, anchor.z = HOME.x, HOME.y, HOME.z
    set_anchor_here()
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
    set_anchor_here()

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
        assert_home_edits()
        phase = "unload_away"
        frame = 0
        anchor.x, anchor.y, anchor.z = FAR.x, FAR.y, FAR.z
        return
    end

    if phase == "unload_away" then
        if frame < 90 then
            return
        end
        phase = "unload_return"
        frame = 0
        anchor.x, anchor.y, anchor.z = HOME.x, HOME.y, HOME.z
        return
    end

    if phase == "unload_return" then
        if not wait_ground() then
            return
        end
        assert_home_edits()
        phase = "done"
        return
    end

    if phase == "done" and frame > 30 then
        pe_log("[voxelcraft_persistence_smoke] VOXELCRAFT_PERSISTENCE_SMOKE_OK")
        engine.quit()
    end
end
