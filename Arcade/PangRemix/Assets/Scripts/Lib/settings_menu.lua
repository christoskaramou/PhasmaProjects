-- settings_menu.lua : reusable in-game settings menu for Phasma Engine Lua games.
-- Canonical copy: /workspace/games/common/settings_menu.lua (see SETTINGS_API.md).
-- Each project ships a copy at Assets/Scripts/Lib/settings_menu.lua and loads it with:
--   local SettingsMenu = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")()
--   local SET = SettingsMenu.new({ title = "SETTINGS", click = function() sfx("click") end })
--   SET:apply()            -- once, AFTER the game set its own post-fx (captures them as the HIGH baseline)
--   if SET:update(dt) then --[[menu is open: skip your own menu input]] end   -- EVERY frame
--   SET:open(function() --[[closed]] end)
-- Volume uses the engine's audio buses (audio.set_master_volume / set_sfx_volume / set_music_volume).
local M = {}
M.__index = M
M.VERSION = 1

local QUALITY = { "LOW", "MEDIUM", "HIGH", "ULTRA" }
local PARTICLES = { "LOW", "MEDIUM", "HIGH" }
local PARTICLE_SCALE = { 0.35, 0.7, 1.0 }
-- preset -> bloom, ssao, particles level ; plus engine keys applied by apply_graphics
local PRESET = {
  { bloom = false, ssao = false, particles = 1 },  -- LOW
  { bloom = nil,   ssao = false, particles = 2 },  -- MEDIUM
  { bloom = nil,   ssao = nil,   particles = 3 },  -- HIGH  (nil = the game's own choice)
  { bloom = nil,   ssao = true,  particles = 3 },  -- ULTRA
}
local DEFAULTS = {
  master = 0.5, sfx = 1.0, music = 0.8, mute = false,
  quality = 3, bloom = true, ssao = false, particles = 3,
  shake = true, show_fps = false,
}

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function copy(t) local r = {} for k, v in pairs(t) do r[k] = v end return r end
local function keydown(k)
  local f = input.is_key_down_raw or input.is_key_down
  local ok, r = pcall(f, k); return ok and r or false
end
local function sget(k) local ok, v = pcall(settings.get, k); if ok then return v end end
local function sset(k, v) pcall(settings.set, k, v) end
local function surf()
  local ok, s = pcall(runtime_ui.get_surface_size)
  if ok and s and (s.w or 0) > 0 then return s.w, s.h end
  return 1280, 720
end

-- ------------------------------------------------------------------ persistence
local function serialize(cfg)
  local keys = {}
  for k in pairs(cfg) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = { "# Phasma settings_menu v" .. M.VERSION }
  for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. tostring(cfg[k]) end
  return table.concat(out, "\n") .. "\n"
end
local function parse(text, cfg)
  for line in tostring(text):gmatch("[^\r\n]+") do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k and cfg[k] ~= nil then
      if type(cfg[k]) == "boolean" then cfg[k] = (v == "true")
      elseif type(cfg[k]) == "number" then cfg[k] = tonumber(v) or cfg[k] end
    end
  end
  return cfg
end

-- ------------------------------------------------------------------ construction
function M.new(opts)
  opts = opts or {}
  local self = setmetatable({}, M)
  self.opts = opts
  self.screen = opts.screen or "settings_menu"
  self.fps_screen = self.screen .. "_fps"
  self.file = opts.file or "Save/settings.cfg"
  self.music = opts.music == true            -- show the music slider only if the game plays music
  self.defaults = copy(DEFAULTS)
  for k, v in pairs(opts.defaults or {}) do self.defaults[k] = v end
  self.cfg = copy(self.defaults)
  self.open_ = false
  self.sel = 1
  self.prev = {}
  self.rep = 0
  self.fps, self.fps_t, self.fps_n, self.fps_acc = 0, 0, 0, 0
  self.t = 0
  local th = opts.theme or {}
  self.theme = {
    accent = th.accent or { 0.2, 0.9, 1.0, 1 },
    accent2 = th.accent2 or { 1.0, 0.3, 0.85, 1 },
    panel = th.panel or { 0.02, 0.03, 0.09, 0.94 },
    row = th.row or { 0.07, 0.09, 0.2, 0.75 },
    text = th.text or { 0.88, 0.93, 1.0, 1 },
    dim = th.dim or { 0.55, 0.62, 0.8, 1 },
    selected_text = th.selected_text or { 1, 1, 1, 1 },
  }
  self:build_rows()
  self:load()
  return self
end

function M:build_rows()
  local r = {}
  local function add(t) r[#r + 1] = t end
  add({ id = "master", label = "MASTER VOLUME", kind = "slider", section = "AUDIO" })
  add({ id = "sfx", label = "SFX VOLUME", kind = "slider" })
  if self.music then add({ id = "music", label = "MUSIC VOLUME", kind = "slider" }) end
  add({ id = "mute", label = "MUTE ALL", kind = "toggle" })
  add({ id = "quality", label = "GRAPHICS QUALITY", kind = "cycle", values = QUALITY, section = "GRAPHICS" })
  add({ id = "bloom", label = "BLOOM", kind = "toggle" })
  add({ id = "ssao", label = "AMBIENT OCCLUSION", kind = "toggle" })
  add({ id = "particles", label = "PARTICLES", kind = "cycle", values = PARTICLES })
  add({ id = "shake", label = "SCREEN SHAKE", kind = "toggle", section = "GAMEPLAY" })
  add({ id = "show_fps", label = "SHOW FPS", kind = "toggle" })
  for _, row in ipairs(self.opts.extra or {}) do add(row) end
  add({ id = "reset", label = "RESET TO DEFAULTS", kind = "button" })
  add({ id = "back", label = "BACK", kind = "button" })
  self.rows = r
end

function M:load()
  local ok, text = pcall(fs.read, self.file)
  if ok and text and #text > 0 then parse(text, self.cfg) end
  self.cfg.master = clamp(self.cfg.master, 0, 1)
  self.cfg.sfx = clamp(self.cfg.sfx, 0, 1)
  self.cfg.music = clamp(self.cfg.music, 0, 1)
  self.cfg.quality = clamp(math.floor(self.cfg.quality), 1, #QUALITY)
  self.cfg.particles = clamp(math.floor(self.cfg.particles), 1, #PARTICLES)
end

function M:save()
  pcall(fs.write, self.file, serialize(self.cfg))
end

-- ------------------------------------------------------------------ applying
function M:apply_audio()
  local c = self.cfg
  if audio then
    if audio.set_master_volume then pcall(audio.set_master_volume, c.mute and 0 or c.master) end
    if audio.set_sfx_volume then pcall(audio.set_sfx_volume, c.sfx) end
    if audio.set_ambient_volume then pcall(audio.set_ambient_volume, c.sfx) end
    if audio.set_music_volume then pcall(audio.set_music_volume, c.music) end
  end
  if self.opts.on_audio then pcall(self.opts.on_audio, c) end
end

function M:capture_baseline()
  self.base = {}
  for _, k in ipairs({ "bloom", "ssao", "ssr", "shadows", "fxaa", "render_scale" }) do self.base[k] = sget(k) end
  if self.base.render_scale == nil then self.base.render_scale = 1.0 end
end

function M:apply_graphics()
  if not self.base then self:capture_baseline() end
  local c, b, q = self.cfg, self.base, self.cfg.quality
  if b.ssr ~= nil then sset("ssr", q >= 3 and b.ssr or false) end
  if b.shadows ~= nil then sset("shadows", q >= 2 and b.shadows or (q == 4)) end
  if q == 1 then sset("fxaa", true) elseif b.fxaa ~= nil then sset("fxaa", b.fxaa) end
  sset("render_scale", q == 1 and math.max(0.5, (b.render_scale or 1.0) * 0.75) or (b.render_scale or 1.0))
  sset("bloom", c.bloom and true or false)
  sset("ssao", c.ssao and true or false)
  if self.opts.on_graphics then pcall(self.opts.on_graphics, c) end
end

-- Apply everything. Call once after the game has configured its own look.
function M:apply()
  if not self.base then self:capture_baseline() end
  if not self.applied_once then
    self.applied_once = true
    -- defaults that follow the game's own look unless the player saved something
    local ok, text = pcall(fs.read, self.file)
    if not (ok and text and #text > 0) then
      self.cfg.bloom = self.base.bloom ~= false
      self.cfg.ssao = self.base.ssao == true
      self.defaults.bloom, self.defaults.ssao = self.cfg.bloom, self.cfg.ssao
    end
  end
  self:apply_audio()
  self:apply_graphics()
  self:show_fps_overlay(self.cfg.show_fps)
end

function M:set_preset(q)
  self.cfg.quality = q
  local p = PRESET[q]
  if p.bloom == nil then self.cfg.bloom = not self.base or self.base.bloom ~= false else self.cfg.bloom = p.bloom end
  if p.ssao == nil then self.cfg.ssao = self.base and self.base.ssao == true or false else self.cfg.ssao = p.ssao end
  self.cfg.particles = p.particles
end

-- ------------------------------------------------------------------ queries for the game
function M:is_open() return self.open_ end
function M:shake_scale() return self.cfg.shake and 1 or 0 end
function M:particle_scale() return PARTICLE_SCALE[self.cfg.particles] or 1 end
function M:get(k) return self.cfg[k] end
function M:volume() return self.cfg.mute and 0 or self.cfg.master end

function M:toggle_mute()
  self.cfg.mute = not self.cfg.mute
  self:apply_audio(); self:save()
  return self.cfg.mute
end

-- ------------------------------------------------------------------ open / close
function M:open(on_close)
  self.on_close = on_close
  self.open_ = true
  self.sel = 1
  self.t = 0
  self.drag, self.press_row, self.press_in_panel, self.was_down, self.mx, self.my, self.layout = nil, nil, nil, false, nil, nil, nil
  self.prev = {}
  for _, k in ipairs({ "Escape", "Return", "Space", "Backspace", "Up", "Down", "Left", "Right", "W", "S", "A", "D" }) do
    self.prev[k] = keydown(k)   -- swallow the key that opened us
  end
  self.drag = nil
  self.mx = nil
  pcall(runtime_ui.set_screen_overlay, self.screen, true)
  pcall(runtime_ui.show, self.screen)
end

function M:close()
  if not self.open_ then return end
  self.open_ = false
  self:save()
  pcall(runtime_ui.hide, self.screen)
  local cb = self.on_close
  self.on_close = nil
  if cb then pcall(cb, self.cfg) end
end

-- ------------------------------------------------------------------ input
function M:pressed(k)
  local d = keydown(k)
  local was = self.prev[k]
  self.prev[k] = d
  return d and not was
end

function M:click()
  if self.opts.click then pcall(self.opts.click) end
end

function M:adjust(row, dir, fine)
  local c = self.cfg
  if row.kind == "slider" then
    local step = fine and 0.01 or 0.05
    c[row.id] = clamp(math.floor((c[row.id] + dir * step) * 100 + 0.5) / 100, 0, 1)
    if row.id == "master" and c.mute and dir > 0 then c.mute = false end
    self:apply_audio()
  elseif row.kind == "toggle" then
    c[row.id] = not c[row.id]
    self:after_change(row.id)
  elseif row.kind == "cycle" then
    local n = #row.values
    local v = ((c[row.id] - 1 + dir) % n) + 1
    if row.id == "quality" then self:set_preset(v) else c[row.id] = v end
    self:after_change(row.id)
  end
  self:click()
end

function M:after_change(id)
  if id == "mute" then self:apply_audio()
  elseif id == "show_fps" then self:show_fps_overlay(self.cfg.show_fps)
  elseif id == "quality" or id == "bloom" or id == "ssao" or id == "particles" then self:apply_graphics()
  end
  -- shake and game rows (Jev) are read by the match. They must not reload the renderer.
  if self.opts.on_change then pcall(self.opts.on_change, id, self.cfg[id], self.cfg) end
end

function M:activate(row)
  if row.kind == "button" then
    self:click()
    if row.id == "back" then self:close()
    elseif row.id == "reset" then
      self.cfg = copy(self.defaults)
      self:apply()
    end
  else
    self:adjust(row, 1)
  end
end

function M:handle_keys(dt)
  local n = #self.rows
  if self:pressed("Escape") or self:pressed("Backspace") then self:click(); self:close(); return end
  if self:pressed("Up") or self:pressed("W") then self.sel = (self.sel - 2) % n + 1; self:click() end
  if self:pressed("Down") or self:pressed("S") then self.sel = self.sel % n + 1; self:click() end
  local row = self.rows[self.sel]
  local l = self:pressed("Left") or self:pressed("A")
  local r = self:pressed("Right") or self:pressed("D")
  -- hold-to-repeat for sliders
  local hl = keydown("Left") or keydown("A")
  local hr = keydown("Right") or keydown("D")
  if (hl or hr) and row.kind == "slider" then
    self.rep = self.rep + dt
    if self.rep > 0.35 then self.rep = self.rep - 0.06; if hl then l = true else r = true end end
  else self.rep = 0 end
  if row.kind ~= "button" then
    if l then self:adjust(row, -1) elseif r then self:adjust(row, 1) end
  end
  if self:pressed("Return") or self:pressed("Space") then self:activate(row) end
  self:pressed("M")
end

local function state(screen, id)
  local ok, s = pcall(runtime_ui.get_state, screen, id)
  if ok then return s end
end

local function inside(r, x, y, pad)
  pad = pad or 0
  return r and x >= r.x - pad and x <= r.x + r.w + pad and y >= r.y - pad and y <= r.y + r.h + pad
end

-- Mouse: ONE transparent full-screen hit target ("backdrop", drawn last so it is the topmost window of
-- this screen) and all hit-testing done here against the rects recorded by draw(). This does not depend
-- on ImGui's per-window hover/focus ordering of many overlapping quads (which is what broke clicks).
function M:handle_mouse()
  local L = self.layout
  if not L then return end
  local s = state(self.screen, "backdrop")
  if not (s and s.mouse_x) then return end
  local mx, my = s.mouse_x, s.mouse_y
  local wheel = 0
  local okw, w = pcall(runtime_ui.get_wheel); if okw and w then wheel = w end
  local moved = self.mx ~= nil and (math.abs(mx - self.mx) + math.abs(my - self.my) > 2)
  self.mx, self.my = mx, my
  local hit
  for i, r in pairs(L.rows) do if inside(r, mx, my) then hit = i end end
  if hit and moved then self.sel = hit end
  local down = s.down and true or false

  local function set_slider(i)
    local tr = L.track[i]; local row = self.rows[i]
    if not (tr and row) then return end
    local v = math.floor(clamp((mx - tr.x) / tr.w, 0, 1) * 100 + 0.5) / 100
    if v ~= self.cfg[row.id] then
      self.cfg[row.id] = v
      if row.id == "master" and v > 0 then self.cfg.mute = false end
      self:apply_audio()
    end
  end

  -- press edge
  if down and not self.was_down then
    self.press_row = hit
    self.press_in_panel = inside(L.panel, mx, my)
    if hit and self.rows[hit].kind == "slider" and inside(L.track[hit] and { x = L.track[hit].x, y = L.rows[hit].y, w = L.track[hit].w, h = L.rows[hit].h }, mx, my, 16) then
      self.drag = hit; self.sel = hit
    end
  end
  if self.drag and down then set_slider(self.drag) end
  local was_drag = self.drag
  if not down and self.drag then self.drag = nil; self:click() end
  self.was_down = down

  if s.clicked then
    local pr = self.press_row
    if hit and (pr == nil or pr == hit) then
      local row = self.rows[hit]
      self.sel = hit
      if row.kind == "slider" then
        if not was_drag and inside(L.track[hit] and { x = L.track[hit].x, y = L.rows[hit].y, w = L.track[hit].w, h = L.rows[hit].h }, mx, my, 16) then
          set_slider(hit); self:click()
        end
      elseif row.kind == "cycle" then
        local al = L.arrow_l[hit]
        self:adjust(row, inside(al, mx, my, 10) and -1 or 1)
      else
        self:activate(row)
        if not self.open_ then return end
      end
    elseif not hit and not self.press_in_panel and not inside(L.panel, mx, my) then
      self:click(); self:close(); return
    end
  end
  if s.right_clicked and hit then
    local row = self.rows[hit]
    if row.kind == "cycle" then self:adjust(row, -1)
    elseif row.kind == "slider" then self:adjust(row, -1) end
  end
  if hit and wheel ~= 0 and self.rows[hit].kind ~= "button" then self:adjust(self.rows[hit], wheel > 0 and 1 or -1) end
end

-- ------------------------------------------------------------------ drawing
local CLEAR = { 0, 0, 0, 0 }
local function quad(screen, id, o)
  o.style = o.style or "text"
  o.align_v = o.align_v or "center"
  -- no_input overlay quads are batched on the background draw list (under every interactive window and
  -- possibly under the game's HUD screen); bring_to_front keeps them on the windowed path, above the HUD.
  if o.no_input then o.bring_to_front = true end
  pcall(runtime_ui.set_quad, screen, id, o)
end

function M:draw()
  local sw, sh = surf()
  local th = self.theme
  local k = math.min(sw / 1600, sh / 900)
  k = math.max(k, 0.45)
  local fs = k * 1.6                               -- base font scale
  local rowh = math.floor(52 * k)
  local gap = math.floor(8 * k)
  local sections = 0
  for _, r in ipairs(self.rows) do if r.section then sections = sections + 1 end end
  local head = math.floor(120 * k)
  local foot = math.floor(70 * k)
  local sech = math.floor(34 * k)
  local pw = math.floor(math.min(sw * 0.92, 860 * k))
  local ph = head + foot + #self.rows * (rowh + gap) + sections * sech
  if ph > sh * 0.96 then -- squeeze for short windows
    local f = (sh * 0.96 - head - foot - sections * sech) / (#self.rows * (rowh + gap))
    rowh = math.floor(rowh * f); gap = math.floor(gap * f)
    ph = head + foot + #self.rows * (rowh + gap) + sections * sech
  end
  local px, py = math.floor((sw - pw) / 2), math.floor((sh - ph) / 2)
  local Z = 120
  local S = self.screen
  local pulse = 0.75 + 0.25 * math.sin(self.t * 3)
  local a = th.accent
  self.layout = { track = {}, rows = {}, arrow_l = {}, arrow_r = {}, panel = { x = px, y = py, w = pw, h = ph } }

  -- NOTE: in overlay screens no_input quads are batched BELOW interactive ones, so every visual is
  -- no_input; the only mouse target is the transparent full-screen "backdrop" submitted last.
  quad(S, "dim", { x = 0, y = 0, w = sw, h = sh, label = "", fill = { 0, 0, 0.02, 0.62 }, border = { 0, 0, 0, 0 }, no_input = true, z = Z })
  quad(S, "glow", { x = px - 6, y = py - 6, w = pw + 12, h = ph + 12, label = "", corner_radius = 22 * k,
    fill = { a[1] * 0.25, a[2] * 0.25, a[3] * 0.25, 0.35 * pulse }, border = { 0, 0, 0, 0 }, no_input = true, z = Z + 1 })
  quad(S, "panel", { x = px, y = py, w = pw, h = ph, label = "", corner_radius = 18 * k,
    fill = th.panel, border = { a[1], a[2], a[3], 0.9 }, no_input = true, z = Z + 2 })
  quad(S, "stripe", { x = px + 24 * k, y = py + head - 22 * k, w = pw - 48 * k, h = math.max(2, 3 * k), label = "",
    fill = { th.accent2[1], th.accent2[2], th.accent2[3], 0.85 }, border = { 0, 0, 0, 0 }, no_input = true, z = Z + 3 })
  quad(S, "title", { x = px, y = py + 14 * k, w = pw, h = 64 * k, label = self.opts.title or "SETTINGS",
    font_scale = fs * 2.6, text_color = { a[1], a[2], a[3], 1 }, fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 },
    align_h = "center", no_input = true, z = Z + 4 })
  quad(S, "subtitle", { x = px, y = py + 70 * k, w = pw, h = 26 * k, label = self.opts.subtitle or "audio  /  graphics  /  gameplay",
    font_scale = fs * 0.8, text_color = th.dim, fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 },
    align_h = "center", no_input = true, z = Z + 4 })

  local y = py + head
  local lx = px + 36 * k
  local cw = pw - 72 * k
  local vx = lx + cw * 0.52               -- value column
  local vw = cw * 0.48
  for i, row in ipairs(self.rows) do
    if row.section then
      quad(S, "sec" .. i, { x = lx, y = y, w = cw, h = sech, label = row.section, font_scale = fs * 0.75,
        text_color = { th.accent2[1], th.accent2[2], th.accent2[3], 0.95 }, fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 },
        align_h = "left", no_input = true, z = Z + 4 })
      y = y + sech
    end
    local on = (i == self.sel)
    local isbtn = row.kind == "button"
    local fill = on and { a[1] * 0.28, a[2] * 0.28, a[3] * 0.3, 0.95 } or th.row
    local border = on and { a[1], a[2], a[3], 1 } or { 0.2, 0.25, 0.45, 0.6 }
    quad(S, "rowbg" .. i, { x = lx, y = y, w = cw, h = rowh, label = "", corner_radius = 10 * k,
      fill = fill, border = border, no_input = true, z = Z + 4 })
    self.layout.rows[i] = { x = lx, y = y, w = cw, h = rowh }
    quad(S, "lbl" .. i, { x = lx + 18 * k, y = y, w = isbtn and (cw - 36 * k) or cw * 0.5, h = rowh,
      label = (on and "> " or "") .. row.label, font_scale = fs * 0.95,
      text_color = on and th.selected_text or th.text, fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 },
      align_h = isbtn and "center" or "left", no_input = true, z = Z + 5 })
    if row.kind == "slider" then
      local v = self.cfg[row.id]
      local muted = self.cfg.mute and row.id == "master"
      local tx, tw, th_ = vx, vw - 90 * k, math.max(6, 10 * k)
      local ty = y + (rowh - th_) / 2
      self.layout.track[i] = { x = tx, w = tw }
      quad(S, "trk" .. i, { x = tx, y = ty, w = tw, h = th_, label = "", corner_radius = th_ / 2,
        fill = { 0.12, 0.14, 0.28, 1 }, border = { 0.3, 0.35, 0.6, 0.8 }, no_input = true, z = Z + 5 })
      local fc = muted and { 0.45, 0.45, 0.5, 1 } or { a[1], a[2], a[3], 1 }
      quad(S, "fil" .. i, { x = tx, y = ty, w = math.max(th_, tw * v), h = th_, label = "", corner_radius = th_ / 2,
        fill = fc, border = { 0, 0, 0, 0 }, no_input = true, z = Z + 6 })
      local kn = math.max(14, 24 * k)
      quad(S, "knb" .. i, { x = tx + tw * v - kn / 2, y = y + (rowh - kn) / 2, w = kn, h = kn, label = "", corner_radius = kn / 2,
        fill = on and { 1, 1, 1, 1 } or { 0.85, 0.9, 1, 1 }, border = { a[1], a[2], a[3], 1 }, no_input = true, z = Z + 7 })
      quad(S, "val" .. i, { x = tx + tw + 12 * k, y = y, w = 78 * k, h = rowh,
        label = muted and "MUTED" or (math.floor(v * 100 + 0.5) .. "%"), font_scale = fs * 0.9,
        text_color = muted and { 1, 0.45, 0.5, 1 } or th.text, fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 },
        align_h = "right", no_input = true, z = Z + 6 })
    elseif row.kind == "toggle" then
      local v = self.cfg[row.id]
      local pw2 = 120 * k
      quad(S, "pill" .. i, { x = vx + vw - pw2, y = y + rowh * 0.16, w = pw2, h = rowh * 0.68, label = v and "ON" or "OFF",
        corner_radius = rowh * 0.34, font_scale = fs * 0.85,
        fill = v and { a[1] * 0.85, a[2] * 0.85, a[3] * 0.85, 1 } or { 0.16, 0.16, 0.24, 1 },
        border = v and { 1, 1, 1, 0.9 } or { 0.35, 0.35, 0.5, 0.9 },
        text_color = v and { 0.02, 0.04, 0.1, 1 } or { 0.7, 0.72, 0.85, 1 },
        align_h = "center", no_input = true, z = Z + 6 })
    elseif row.kind == "cycle" then
      local v = self.cfg[row.id]
      local label = row.values[v] or "?"
      if row.id == "quality" and self:is_custom() then label = label .. "*" end
      local col = on and { th.accent2[1], th.accent2[2] * 1.4, th.accent2[3], 1 } or th.text
      local aw, cwv = 44 * k, 200 * k
      local ax_r = vx + vw - aw
      local ax_l = ax_r - cwv - aw
      self.layout.arrow_l[i] = { x = ax_l, y = y, w = aw, h = rowh }
      self.layout.arrow_r[i] = { x = ax_r, y = y, w = aw, h = rowh }
      local hl = self.mx and inside(self.layout.arrow_l[i], self.mx, self.my, 10)
      local hr = self.mx and not hl and inside(self.layout.rows[i], self.mx, self.my)
      quad(S, "arl" .. i, { x = ax_l, y = y + rowh * 0.14, w = aw, h = rowh * 0.72, label = "<", font_scale = fs * 1.05, corner_radius = 8 * k,
        text_color = col, fill = hl and { a[1] * 0.4, a[2] * 0.4, a[3] * 0.4, 0.9 } or { 0, 0, 0, 0 },
        border = hl and { a[1], a[2], a[3], 0.9 } or { 0, 0, 0, 0 }, align_h = "center", no_input = true, z = Z + 6 })
      quad(S, "val" .. i, { x = ax_l + aw, y = y, w = cwv, h = rowh, label = label, font_scale = fs * 0.95,
        text_color = col, fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 }, align_h = "center", no_input = true, z = Z + 6 })
      quad(S, "arr" .. i, { x = ax_r, y = y + rowh * 0.14, w = aw, h = rowh * 0.72, label = ">", font_scale = fs * 1.05, corner_radius = 8 * k,
        text_color = col, fill = hr and { a[1] * 0.4, a[2] * 0.4, a[3] * 0.4, 0.9 } or { 0, 0, 0, 0 },
        border = hr and { a[1], a[2], a[3], 0.9 } or { 0, 0, 0, 0 }, align_h = "center", no_input = true, z = Z + 6 })
    end
    y = y + rowh + gap
  end
  quad(S, "foot", { x = px, y = py + ph - foot + 10 * k, w = pw, h = foot - 20 * k,
    label = "UP/DOWN select   LEFT/RIGHT change   ENTER toggle   ESC back   |   mouse: click, drag, wheel",
    font_scale = fs * 0.62, text_color = th.dim, fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 },
    align_h = "center", no_input = true, z = Z + 4 })
  -- the single mouse target, submitted last (topmost in this screen); fully transparent
  quad(S, "backdrop", { x = 0, y = 0, w = sw, h = sh, label = "", fill = CLEAR, border = CLEAR, z = Z + 20, bring_to_front = true })
end

function M:is_custom()
  local p = PRESET[self.cfg.quality]
  if not p then return false end
  local ssao = p.ssao; if ssao == nil then ssao = self.base and self.base.ssao == true or false end
  local bloom = p.bloom; if bloom == nil then bloom = not self.base or self.base.bloom ~= false end
  return self.cfg.bloom ~= bloom or self.cfg.ssao ~= ssao or self.cfg.particles ~= p.particles
end

-- ------------------------------------------------------------------ FPS overlay
function M:show_fps_overlay(on)
  self.fps_on = on
  if on then
    pcall(runtime_ui.set_screen_overlay, self.fps_screen, true)
    pcall(runtime_ui.show, self.fps_screen)
  else
    pcall(runtime_ui.hide, self.fps_screen)
  end
end

function M:update_fps(dt)
  if not self.fps_on then return end
  self.fps_acc = self.fps_acc + dt; self.fps_n = self.fps_n + 1
  if self.fps_acc >= 0.25 then
    self.fps = self.fps_n / self.fps_acc
    self.fps_acc, self.fps_n = 0, 0
  end
  local sw, sh = surf()
  local k = math.max(0.45, math.min(sw / 1600, sh / 900))
  local f = self.fps
  local col = f >= 55 and { 0.4, 1, 0.55, 1 } or (f >= 30 and { 1, 0.85, 0.3, 1 } or { 1, 0.35, 0.35, 1 })
  local pos = self.opts.fps_pos or "top_right"
  local w, h = 150 * k, 34 * k
  local x = pos:find("left") and 12 * k or (sw - w - 12 * k)
  local y = pos:find("bottom") and (sh - h - 12 * k) or 12 * k
  quad(self.fps_screen, "fps", { x = x, y = y, w = w, h = h, label = string.format("%d FPS", math.floor(f + 0.5)),
    font_scale = 1.1 * k * 1.6 * 0.7, corner_radius = 8 * k, fill = { 0, 0, 0, 0.55 }, border = { col[1], col[2], col[3], 0.6 },
    text_color = col, align_h = "center", no_input = true, z = 200 })
end

-- ------------------------------------------------------------------ per-frame entry point
-- Call every frame. Returns true while the menu is open (the game should ignore its own menu input).
function M:update(dt)
  dt = dt or 0.016
  self:update_fps(dt)
  if not self.open_ then return false end
  self.t = self.t + dt
  self:handle_keys(dt)
  if self.open_ then self:handle_mouse() end
  if self.open_ then self:draw() end
  return true
end

return M
