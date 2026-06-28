local frame = 0
local passed = false
local surfaceY = nil

local function fail(msg)
    pe_log("[voxelcraft_smoke] FAIL " .. tostring(msg))
    engine.quit()
end

local function find_grass_surface()
    for y = 0, 48 do
        if voxel.get_block(0, y, 0) == 3 then
            return y
        end
    end
    return nil
end

function init()
    voxel.create({ load_radius = 1, unload_margin = 1, ground_y = 16, upload_budget = 32 })
    voxel.set_anchor(0.5, 20.0, 0.5)

    local cam = get_camera()
    if cam then
        cam:set_position(vec3(0.5, 24.0, 6.0))
        cam:set_euler(vec3(0.7, 3.14159, 0.0))
    end

    pe_log("[voxelcraft_smoke] START")
end

function update()
    frame = frame + 1
    voxel.set_anchor(0.5, 20.0, 0.5)

    if passed then
        if frame > 90 then
            pe_log("[voxelcraft_smoke] VOXELCRAFT_SMOKE_OK")
            engine.quit()
        end
        return
    end

    if not surfaceY then
        surfaceY = find_grass_surface()
        if not surfaceY then
            if frame > 240 then
                fail("timed out waiting for generated ground")
            end
            return
        end
    end

    local hit = voxel.raycast(0.5, surfaceY + 5.0, 0.5, 0.0, -1.0, 0.0, 16.0)
    if not hit.hit then
        fail("raycast missed generated ground")
        return
    end
    if hit.cell.x ~= 0 or hit.cell.y ~= surfaceY or hit.cell.z ~= 0 then
        fail("raycast hit wrong cell")
        return
    end
    if hit.adjacent.x ~= 0 or hit.adjacent.y ~= surfaceY + 1 or hit.adjacent.z ~= 0 then
        fail("raycast returned wrong adjacent cell")
        return
    end

    voxel.set_block(hit.cell.x, hit.cell.y, hit.cell.z, 0)
    if voxel.get_block(0, surfaceY, 0) ~= 0 then
        fail("break did not clear hit cell")
        return
    end

    voxel.set_block(hit.adjacent.x, hit.adjacent.y, hit.adjacent.z, 1)
    if voxel.get_block(0, surfaceY + 1, 0) ~= 1 then
        fail("place did not write adjacent cell")
        return
    end

    local p = voxel.move_aabb(0.5, surfaceY + 3.0, 0.5, 0.3, 0.9, 0.3, 0.0, -8.0, 0.0)
    if p.y < surfaceY + 1.8 then
        fail("move_aabb did not land on placed block")
        return
    end

    passed = true
end
