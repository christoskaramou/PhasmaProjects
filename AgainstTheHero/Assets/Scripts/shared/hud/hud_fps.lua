-- Attached to the authored "HUD FPS" panel node (the purple-bordered clock
-- FRAME you place/size in the editor). At runtime this draws the live FPS as
-- 7-segment digits + the purple "FPS" label inside the frame -- the same digital
-- look as the arena's built-in clock -- so the frame is authored/editor-tweakable
-- while only the readout is script-driven. Everything is drawn on the
-- "__scene_ui" overlay (same screen as the authored nodes) at this node's rect.

local COMMON_PATH = "Scripts/shared/ath_common.lua"
local Art

local function ensure_art()
    if Art then return Art end
    local src = fs and fs.read and fs.read(COMMON_PATH) or nil
    if not src then return nil end
    local chunk = load(src, "@" .. COMMON_PATH, "t", _ENV)
    if not chunk then return nil end
    local Common = chunk()
    if Common and Common.load_script then
        Art = Common.load_script("Scripts/shared/ath_art.lua", "art", _ENV)
    end
    return Art
end

hooks {
    update = function()
        local A = ensure_art()
        if not (A and A.draw_fps_digits and A.quad) then return end
        -- Use the RENDERED rect (anchor+pivot+surface applied). The node translation
        -- is only the anchor offset now, so get_world_position would be wrong.
        local r = self.get_ui_rect and self:get_ui_rect()
        if not r then return end
        local x, y, w, h = r.x, r.y, r.w, r.h
        local pad = h * 0.16
        local labw = w * 0.30
        -- Purple "FPS" label on the left (matches the arena clock's label color).
        A.quad("__scene_ui", "hud_fps_label", x + pad, y + pad, labw, h - 2.0 * pad, { 0, 0, 0, 0 },
            { label = "FPS", text_color = { 0.55, 0.45, 0.82, 1.0 }, no_input = true })
        -- 7-segment digits fill the rest.
        local dax = x + labw + pad
        local day = y + pad
        local daw = w - labw - 2.0 * pad
        local dah = h - 2.0 * pad
        if daw > 0 and dah > 0 then
            A.draw_fps_digits("__scene_ui", "hud_fps", dax, day, daw, dah)
        end
    end,
}
