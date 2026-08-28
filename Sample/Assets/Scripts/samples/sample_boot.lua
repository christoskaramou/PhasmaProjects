-- Shared boot helpers for opt-in Scripts/samples/*.lua. load() is inert.

sample_boot = sample_boot or {}

function sample_boot.log(tag, message)
    if pe_log then
        pe_log(tag .. " " .. message)
    end
end

function sample_boot.dt()
    if not engine or not engine.get_metrics then
        return 0.016
    end
    local metrics = engine.get_metrics()
    return math.min(metrics.delta_ms / 1000.0, 0.05)
end

function sample_boot.apply_raster(state)
    if not settings or not settings.get_render_mode or not settings.set_render_mode then
        return false
    end

    state.previous_render_mode = settings.get_render_mode()
    if state.previous_render_mode == "raster" then
        return false
    end
    settings.set_render_mode("raster")
    return true
end

function sample_boot.restore_raster(state)
    if settings and settings.set_render_mode and state.previous_render_mode then
        settings.set_render_mode(state.previous_render_mode)
    end
    state.previous_render_mode = nil
end

function sample_boot.ortho_camera(opts)
    opts = opts or {}
    local cam = scene.get_active_camera()
    if not cam then
        cam = scene.add_camera()
        scene.set_active_camera(cam)
    end

    cam:set_projection_mode("orthographic")
    cam:set_orthographic_size(opts.size or 9.5)
    cam:set_near(0.01)
    cam:set_far(1000.0)
    cam:set_position(vec3(0.0, 0.0, opts.distance or 36.0))
    cam:look_at(vec3(0.0, 0.0, 0.0))

    if scene.add_directional_light then
        scene.add_directional_light()
    end
    return cam
end
