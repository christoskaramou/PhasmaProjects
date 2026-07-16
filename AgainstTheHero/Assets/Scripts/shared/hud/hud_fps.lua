-- Attached to the authored "HUD FPS" panel node (the purple-bordered clock
-- FRAME you place/size in the editor). At runtime this draws the live FPS as
-- 7-segment digits + the purple "FPS" label inside the frame -- the same digital
-- look as the arena's built-in clock -- so the frame is authored/editor-tweakable
-- while only the readout is script-driven. Everything is drawn on the
-- "__scene_ui" overlay (same screen as the authored nodes) at this node's rect.

local COMMON_PATH = "Scripts/shared/ath_common.lua"
local Art
local FPS_Z = 9000.0
local SEG_NAMES = { "a", "b", "c", "d", "e", "f", "g" }

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

local function clear_overlay(A)
    if not (A and A.remove) then return end
    A.remove("__scene_ui", "hud_fps_label")
    for i = 1, 4 do
        for _, seg in ipairs(SEG_NAMES) do
            A.remove("__scene_ui", "hud_fps_d" .. i .. "_" .. seg)
        end
    end
end

hooks {
    update = function()
        local A = ensure_art()
        if not (A and A.draw_fps_digits and A.quad) then return end
        local I = _G.ATH_I18N
        local show = not I or I.show_fps ~= false
        if self.set_ui then self:set_ui({ visible = show }) end
        if not show then
            clear_overlay(A)
            return
        end
        -- Use the RENDERED rect (anchor+pivot+surface applied). The node translation
        -- is only the anchor offset now, so get_world_position would be wrong.
        local r = self.get_ui_rect and self:get_ui_rect()
        if not r then return end
        local x, y, w, h = r.x, r.y, r.w, r.h
        local pad = h * 0.16
        local labw = w * 0.30
        -- Stay above gear-hub chrome (Pause Title is bring_to_front).
        local front = { no_input = true, bring_to_front = true, z = FPS_Z }
        -- Purple "FPS" label on the left — half size, vertically centred.
        -- Backend top-anchors label text at (top + 15*scale); shift the quad so
        -- the glyph lands mid-frame (same trick as Art.bar / ath_art fps_label).
        local fs = 0.5
        local ly = y + h * 0.5 - A.s("text") * fs * 21.0
        A.quad("__scene_ui", "hud_fps_label", x + pad, ly, labw, h, { 0, 0, 0, 0 },
            { label = "FPS", font_scale = fs, text_color = { 0.55, 0.45, 0.82, 1.0 },
              no_input = true, bring_to_front = true, z = FPS_Z })
        -- 7-segment digits fill the rest.
        local dax = x + labw + pad
        local day = y + pad
        local daw = w - labw - 2.0 * pad
        local dah = h - 2.0 * pad
        if daw > 0 and dah > 0 then
            A.draw_fps_digits("__scene_ui", "hud_fps", dax, day, daw, dah, front)
        end
    end,
}
