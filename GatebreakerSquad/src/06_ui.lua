------------------------------------------------------------------ UI kit: runtime_ui quads, one mouse backdrop, keyboard focus
local UI = { name = "gb" }
G.UI = UI
do
local NAME = UI.name
runtime_ui.show(NAME); pcall(runtime_ui.set_screen_overlay, NAME, true)
local US = SH / 1080
UI.US = US
local CLEAR = { 0, 0, 0, 0 }
local cache, last, used, shown = {}, {}, {}, {}
local function Q(id, o)
    used[id] = true
    o.visible = true
    if o.style == nil then o.style = "text" end
    if o.fill == nil then o.fill = CLEAR end
    if o.border == nil then o.border = CLEAR end
    if o.no_input == nil then o.no_input = true end
    local f, tc, b = o.fill, o.text_color or CLEAR, o.border
    local key = string.format("%.1f|%.1f|%.1f|%.1f|%s|%.2f|%.3f%.3f%.3f%.3f|%.3f%.3f%.3f%.3f|%.2f%.2f%.2f%.2f|%s|%s|", o.x, o.y, o.w, o.h, o.label or "",
        o.font_scale or 1, f[1], f[2], f[3], f[4], tc[1], tc[2], tc[3], tc[4], b[1], b[2], b[3], b[4], tostring(o.z), (o.align_h or "") .. (o.image or "") .. (o.image_tint and string.format("%.2f", o.image_tint[4]) or ""))
    if cache[id] == key then return end
    cache[id] = key; last[id] = o
    pcall(runtime_ui.set_quad, NAME, id, o)
end
UI.Q = Q
function UI.begin_frame() used = {} end
function UI.end_frame()
    for id in pairs(shown) do
        if not used[id] and last[id] then local o = last[id]; o.visible = false; pcall(runtime_ui.set_quad, NAME, id, o); cache[id] = nil end
    end
    shown = used
end
-- shapes
function UI.rect(id, x, y, w, h, fill, r, z, border)
    Q(id, { x = x, y = y, w = w, h = h, z = z or 5, label = "", fill = fill, border = border, corner_radius = (r or 0) * US })
end
function UI.text(id, label, x, y, w, h, fs, col, align, z, shadow)
    if shadow ~= false then
        Q(id .. "~", { x = x + 3 * US, y = y + 4 * US, w = w, h = h, z = (z or 10) - 0.5, label = label, text_color = { 0.05, 0.08, 0.2, (col and col[4] or 1) * 0.45 },
            font_scale = fs * US, align_h = align or "center", align_v = "middle" })
    end
    Q(id, { x = x, y = y, w = w, h = h, z = z or 10, label = label, text_color = col or { 1, 1, 1, 1 }, font_scale = fs * US, align_h = align or "center", align_v = "middle" })
end
-- outlined big text (four dark copies around) - the chunky mobile look for counters and gate values
function UI.big(id, label, cx, cy, fs, col, out, z)
    local w, h = 900 * US, fs * 26 * US
    local x, y = cx - w / 2, cy - h / 2
    local o = (out or 3) * US
    local oc = { 0.06, 0.1, 0.25, (col and col[4] or 1) * 0.85 }
    local k = 0
    for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { 0.8, 1.6 } }) do
        k = k + 1
        Q(id .. "~" .. k, { x = x + d[1] * o, y = y + d[2] * o, w = w, h = h, z = (z or 10) - 0.5, label = label, text_color = oc, font_scale = fs * US, align_h = "center", align_v = "middle" })
    end
    Q(id, { x = x, y = y, w = w, h = h, z = z or 10, label = label, text_color = col or { 1, 1, 1, 1 }, font_scale = fs * US, align_h = "center", align_v = "middle" })
end
-- palettes for buttons {top, lip, text}
local BTN = {
    green = { { .30, .80, .32, 1 }, { .15, .52, .2, 1 } }, blue = { { .25, .58, 1, 1 }, { .12, .34, .75, 1 } },
    orange = { { 1, .62, .16, 1 }, { .78, .38, .06, 1 } }, red = { { .95, .32, .3, 1 }, { .66, .14, .14, 1 } },
    purple = { { .6, .4, 1, 1 }, { .38, .22, .74, 1 } }, white = { { .97, .97, 1, 1 }, { .72, .76, .86, 1 } },
    grey = { { .62, .65, .72, 1 }, { .42, .45, .52, 1 } }, gold = { { 1, .8, .25, 1 }, { .8, .55, .1, 1 } },
}
UI.BTN = BTN
-- mouse via one transparent backdrop (all visuals are no_input) + keyboard focus over this frame's buttons
local MS = { x = -1, y = -1, down = false, prev = false, click = false, got = false, release = false }
UI.MS = MS
local list, focus, fscreen = {}, 1, nil
UI.list = list
function UI.poll(screen)
    if screen ~= fscreen then fscreen = screen; focus = 1; UI.kbd = false end
    Q("backdrop", { x = 0, y = 0, w = SW, h = SH, z = 900, label = "", no_input = false, bring_to_front = true })
    local ok, s = pcall(runtime_ui.get_state, NAME, "backdrop")
    local down = false
    local clicked = false
    if ok and type(s) == "table" then
        if s.mouse_x then MS.moved = abs((s.mouse_x or 0) - MS.x) + abs((s.mouse_y or 0) - MS.y) > 2; MS.x, MS.y = s.mouse_x, s.mouse_y end
        down = s.down and true or false
        clicked = s.clicked and true or false
    end
    poll_mouse()
    if G.vmouse then MS.moved = abs(MOUSE.x - MS.x) + abs(MOUSE.y - MS.y) > 2; MS.x, MS.y = MOUSE.x, MOUSE.y; down = G.vmouse.down or false; clicked = G.vmouse.click or false; G.vmouse.click = false end
    if not down and MOUSE.down and not G.vmouse then down = true end
    MS.click = false
    if down and not MS.prev then MS.click = true; MS.got = true; MS.px, MS.py = MS.x, MS.y end
    if clicked and not MS.got then MS.click = true; MS.px, MS.py = MS.x, MS.y end
    MS.release = (not down and MS.prev) or (clicked and not MS.prev)
    if not down then MS.got = false end
    MS.prev = down; MS.down = down
    -- keys
    local K = {}
    K.up = anyedge("Up", "W"); K.down = anyedge("Down", "S"); K.left = anyedge("Left", "A"); K.right = anyedge("Right", "D")
    K.ok = anyedge("Return", "Space"); K.back = anyedge("Escape")
    UI.K = K
    -- focus moves on this frame using last frame's button list
    local n = #list
    if n > 0 then
        if K.down or K.right then focus = focus % n + 1; UI.kbd = true; sfx("hover") end
        if K.up or K.left then focus = (focus - 2) % n + 1; UI.kbd = true; sfx("hover") end
    end
    UI.prev_list = list
    UI.activate = (K.ok and n > 0) and list[focus] or nil
    list = {}
    UI.list = list
end
local function inside(x, y, w, h) return MS.x >= x and MS.x <= x + w and MS.y >= y and MS.y <= y + h end
UI.inside = inside
-- button: returns true when clicked (mouse) or activated (keyboard focus + Enter/Space)
function UI.button(id, label, cx, cy, w, h, kind, opt)
    opt = opt or {}
    w, h = w * US, h * US
    local x, y = cx - w / 2, cy - h / 2
    local idx = -1
    if not opt.nokbd then idx = #list + 1; list[idx] = id end
    local hov = inside(x, y, w, h)
    if hov and MS.moved and idx > 0 then focus = idx; UI.kbd = false end
    local foc = (focus == idx) or (opt.nokbd and hov)
    local pal = BTN[opt.disabled and "grey" or (kind or "blue")]
    local press = (hov and MS.down) and 4 * US or 0
    local grow = (foc and not opt.disabled) and 1.04 or 1
    local gw, gh = w * grow, h * grow
    local gx, gy = cx - gw / 2, cy - gh / 2
    local lip = 7 * US
    local r = opt.r or min(h / US / 2, 26)
    if foc then UI.rect(id .. "_f", gx - 5 * US, gy - 5 * US + press, gw + 10 * US, gh + lip + 10 * US, { 1, 1, 1, 0.95 }, r + 5, (opt.z or 20) - 1) end
    UI.rect(id .. "_l", gx, gy + lip, gw, gh, pal[2], r, (opt.z or 20))
    UI.rect(id .. "_t", gx, gy + press, gw, gh, pal[1], r, (opt.z or 20) + 0.1)
    UI.rect(id .. "_h", gx + 8 * US, gy + press + 5 * US, gw - 16 * US, gh * 0.38, { 1, 1, 1, foc and 0.28 or 0.18 }, r * 0.7, (opt.z or 20) + 0.2)
    if label ~= "" then
        local tc = (kind == "white") and { .15, .22, .4, 1 } or { 1, 1, 1, 1 }
        UI.text(id .. "_x", label, gx, gy + press + (opt.ty or 0) * US, gw, gh, opt.fs or (h / US / 22), tc, "center", (opt.z or 20) + 0.3, kind ~= "white")
    end
    if opt.disabled then return false end
    local hit = (MS.click and inside(x, y, w, h)) or UI.activate == id
    if hit then sfx("click") end
    return hit
end
function UI.focus_index() return focus end
function UI.set_focus(i) focus = i end
-- panel card with a soft drop shadow
function UI.card(id, x, y, w, h, fill, z)
    UI.rect(id .. "_s", x + 6 * US, y + 10 * US, w, h, { 0.05, 0.1, 0.25, 0.25 }, 30, (z or 5) - 0.2)
    UI.rect(id, x, y, w, h, fill or { .98, .98, 1, 0.97 }, 30, z or 5)
end
-- icons are generated PNGs (tools/gen_ui.py)
function UI.img(id, name, cx, cy, size, z, tint)
    local s = size * US
    Q(id, { style = "image", image = "Textures/ui/" .. name .. ".png", image_tint = tint or { 1, 1, 1, 1 }, x = cx - s / 2, y = cy - s / 2, w = s, h = s, z = z or 12, label = "" })
end
function UI.coin_icon(id, cx, cy, s, z) UI.img(id, "coin", cx, cy, s, z) end
function UI.gem_icon(id, cx, cy, s, z) UI.img(id, "medal", cx, cy, s, z) end
function UI.star(id, cx, cy, s, on, z) UI.img(id, on and "star" or "star_off", cx, cy, s, z) end
-- currency pill
function UI.pill(id, x, y, w, icon, value, z)
    local h = 58 * US
    UI.rect(id, x, y, w * US, h, { .08, .14, .32, 0.55 }, 29, z or 30)
    if icon == "coin" then UI.coin_icon(id .. "i", x + 30 * US, y + h / 2, 40, (z or 30) + 1) else UI.gem_icon(id .. "i", x + 30 * US, y + h / 2, 36, (z or 30) + 1) end
    UI.text(id .. "v", value, x + 60 * US, y, w * US - 66 * US, h, 1.9, { 1, 1, 1, 1 }, "left", (z or 30) + 1)
end
end
