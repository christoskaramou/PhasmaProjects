-- PAC-MAN : Phasma Remix
-- Faithful arcade rules (scatter/chase AI, frightened mode, ghost house, tunnel, fruit,
-- extra life) rendered with emissive PBR, bloom, point lights, GPU particles and runtime UI.

local AUDIO = ""  -- bare names resolve from Assets/Audio (was /workspace/... Linux path)
local MAZE = {
"############################",
"#............##............#",
"#.####.#####.##.#####.####.#",
"#o####.#####.##.#####.####o#",
"#.####.#####.##.#####.####.#",
"#..........................#",
"#.####.##.########.##.####.#",
"#.####.##.########.##.####.#",
"#......##....##....##......#",
"######.##### ## #####.######",
"     #.##### ## #####.#     ",
"     #.##          ##.#     ",
"     #.## ###--### ##.#     ",
"######.## #      # ##.######",
"      .   #      #   .      ",
"######.## #      # ##.######",
"     #.## ######## ##.#     ",
"     #.##          ##.#     ",
"     #.## ######## ##.#     ",
"######.## ######## ##.######",
"#............##............#",
"#.####.#####.##.#####.####.#",
"#.####.#####.##.#####.####.#",
"#o..##.......  .......##..o#",
"###.##.##.########.##.##.###",
"###.##.##.########.##.##.###",
"#......##....##....##......#",
"#.##########.##.##########.#",
"#.##########.##.##########.#",
"#..........................#",
"############################",
}
local W, H = 28, 31
local grid = {}
for r = 1, H do
  grid[r - 1] = {}
  local row = MAZE[r]
  for c = 1, W do grid[r - 1][c - 1] = row:sub(c, c) end
end
local function cell(c, r)
  if r < 0 or r >= H then return "#" end
  c = c % W
  return grid[r][c]
end
local function wx(c) return c - 13.5 end
local function wz(r) return r - 15.0 end

-- ---------------------------------------------------------------- helpers
local function mat(n, base, emis, metal, rough)
  material.set(n, "base_color", base)
  if emis then material.set(n, "emissive", emis) end
  if metal then material.set(n, "metallic", metal) end
  if rough then material.set(n, "roughness", rough) end
end
local function sfx(name) pcall(audio.play, AUDIO .. name .. ".wav") end
-- shared settings menu (Assets/Scripts/Lib/settings_menu.lua; see /workspace/games/common/SETTINGS_API.md)
local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
  title = "SETTINGS", subtitle = "~ PHASMA REMIX ~", click = function() sfx("click") end,
  theme = { accent = {1, 0.82, 0.1, 1}, accent2 = {0.3, 0.55, 1, 1} } })
local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function lerp(a, b, t) return a + (b - a) * t end
local function burst(x, y, z, col, col2, count, speed, size, life)
  pcall(particles.emit_burst, {
    position = vec3(x, y, z), velocity = vec3(0, speed or 3, 0),
    color_start = col, color_end = col2 or vec4(col.x, col.y, col.z, 0),
    gravity = vec3(0, -3, 0), count = math.max(1, math.floor((count or 48) * SET:particle_scale())), size_min = (size or 0.12) * 0.4,
    size_max = size or 0.12, life_min = (life or 0.6) * 0.5, life_max = life or 0.6,
    spawn_radius = 0.35, noise_strength = 6.0, drag = 1.4 })
end

-- ---------------------------------------------------------------- state
local S = {
  state = "boot", t = 0, score = 0, hi = 0, lives = 3, level = 1, dots = 0, totalDots = 0,
  extra = false, modeIdx = 1, modeT = 0, fright = 0, ghostCombo = 0, pelletCount = 0,
  fruit = nil, fruitT = 0, fruitSpawned = 0, popups = {}, flash = 0, shake = 0,
  wakaT = 0, sirenT = 0, menuSel = 1, pauseSel = 1, lastDotT = 0, firstStart = true,
}
pcall(function()
  local s = fs.read("Save/hiscore.txt")
  if s then S.hi = tonumber(s) or 0 end
end)
local function saveHi()
  pcall(function() fs.write("Save/hiscore.txt", tostring(S.hi)) end)
end

local nodes = { walls = {}, caps = {}, pellets = {} }
local pac = {}
local powerLights = {}
local ghosts = {}
local lightIdx = {}

local camera
local DIRS = { {0, -1}, {-1, 0}, {0, 1}, {1, 0} } -- up, left, down, right (arcade tie order)

-- ---------------------------------------------------------------- build
local function addLight(pos, col, inten, rad)
  lights.add_point()
  local n = #lights.get_point_lights() - 1
  lights.set_point_light(n, pos, col, inten, rad)
  return n
end

local function build()
  local sn = scene.add_empty_node("PostFX")
  sn:set_scene_settings(true)
  local function set(k, v) pcall(settings.set, k, v) end
  set("hdr", true); set("bloom", true); set("bloom_strength", 0.55); set("bloom_range", 1.25)  -- see common/RENDER_SETTINGS.md
  set("tonemapping", true); set("fxaa", false); set("cas_sharpening", false); set("ssao", true); set("shadows", true)
  set("color_grading", true); set("color_grading_saturation", 1.15); set("color_grading_contrast", 1.08)
  set("ssr", false); set("motion_blur", false); set("dof", false); set("taa", true)
  pcall(function() lights.set_directional_light(0, vec3(0, 30, 0), vec3(0.6, 0.65, 1.0), 0.6) end)

  camera = scene.get_active_camera()
  pcall(function() camera:set_fov(62) end)

  -- floor: dark glossy metal with a subtle grid of glowing tiles
  local floor = primitives.cube(1)
  floor:set_scale(vec3(400, 0.2, 400)); floor:set_position(vec3(0, -0.45, 0))
  mat(floor, vec3(0.015, 0.015, 0.03), vec3(0, 0, 0), 0.9, 0.25)
  local under = primitives.cube(1)
  under:set_scale(vec3(W + 0.6, 0.06, H + 0.6)); under:set_position(vec3(0, -0.33, 0))
  mat(under, vec3(0.02, 0.02, 0.06), vec3(0.01, 0.012, 0.05), 0.6, 0.4)

  -- faint tron grid under and around the maze
  for i = -22, 22, 2 do
    local a = primitives.cube(1); a:set_scale(vec3(0.04, 0.02, 60)); a:set_position(vec3(i + 0.5, -0.33, 0))
    mat(a, vec3(0, 0, 0), vec3(0.05, 0.02, 0.22), 0, 1)
    local b = primitives.cube(1); b:set_scale(vec3(60, 0.02, 0.04)); b:set_position(vec3(0, -0.33, i + 0.5))
    mat(b, vec3(0, 0, 0), vec3(0.05, 0.02, 0.22), 0, 1)
  end
  -- walls: greedy-merged dark blocks + neon outline tubes traced along every wall/open edge
  local used = {}
  local function isWall(c, r) return r >= 0 and r < H and c >= 0 and c < W and grid[r][c] == "#" end
  local function isOpen(c, r) return r >= 0 and r < H and c >= 0 and c < W and grid[r][c] ~= "#" end
  for r = 0, H - 1 do
    for c = 0, W - 1 do
      if isWall(c, r) and not used[r * W + c] then
        local c2 = c
        while isWall(c2 + 1, r) and not used[r * W + c2 + 1] do c2 = c2 + 1 end
        local r2 = r
        while true do
          local ok = true
          for cc = c, c2 do if not isWall(cc, r2 + 1) or used[(r2 + 1) * W + cc] then ok = false break end end
          if not ok then break end
          r2 = r2 + 1
        end
        for rr = r, r2 do for cc = c, c2 do used[rr * W + cc] = true end end
        local body = primitives.cube(1)
        body:set_scale(vec3(c2 - c + 1, 0.5, r2 - r + 1))
        body:set_position(vec3((wx(c) + wx(c2)) / 2, -0.05, (wz(r) + wz(r2)) / 2))
        mat(body, vec3(0.02, 0.025, 0.09), vec3(0.004, 0.008, 0.045), 0.6, 0.35)
        nodes.walls[#nodes.walls + 1] = body
      end
    end
  end
  local IN, TH, Y = 0.22, 0.09, 0.22
  local function tube(x1, z1, x2, z2)
    local n = primitives.cube(1)
    local sx = math.max(TH, math.abs(x2 - x1) + TH)
    local sz = math.max(TH, math.abs(z2 - z1) + TH)
    n:set_scale(vec3(sx, 0.07, sz)); n:set_position(vec3((x1 + x2) / 2, Y, (z1 + z2) / 2))
    mat(n, vec3(0.15, 0.3, 1.0), vec3(0.15, 0.35, 2.4), 0, 0.3)
    nodes.caps[#nodes.caps + 1] = n
  end
  -- horizontal edges (side = -1 open above, +1 open below)
  for _, side in ipairs({-1, 1}) do
    for r = 0, H - 1 do
      local c = 0
      while c < W do
        if isWall(c, r) and isOpen(c, r + side) then
          local s0 = c
          while isWall(c + 1, r) and isOpen(c + 1, r + side) do c = c + 1 end
          local x1 = wx(s0) - (isWall(s0 - 1, r) and 0.5 + IN or (0.5 - IN))
          local x2 = wx(c) + (isWall(c + 1, r) and 0.5 + IN or (0.5 - IN))
          local z = wz(r) + side * (0.5 - IN)
          tube(x1, z, x2, z)
        end
        c = c + 1
      end
    end
  end
  for _, side in ipairs({-1, 1}) do
    for c = 0, W - 1 do
      local r = 0
      while r < H do
        if isWall(c, r) and isOpen(c + side, r) then
          local s0 = r
          while isWall(c, r + 1) and isOpen(c + side, r + 1) do r = r + 1 end
          local z1 = wz(s0) - (isWall(c, s0 - 1) and 0.5 + IN or (0.5 - IN))
          local z2 = wz(r) + (isWall(c, r + 1) and 0.5 + IN or (0.5 - IN))
          local x = wx(c) + side * (0.5 - IN)
          tube(x, z1, x, z2)
        end
        r = r + 1
      end
    end
  end
  -- ghost door
  local door = primitives.cube(1)
  door:set_scale(vec3(1.9, 0.08, 0.18)); door:set_position(vec3(0, 0.1, wz(12)))
  mat(door, vec3(1, 0.6, 0.8), vec3(2.5, 1.0, 1.8))

  -- pellets
  for r = 0, H - 1 do
    for c = 0, W - 1 do
      local ch = grid[r][c]
      if ch == "." or ch == "o" then
        local p = primitives.sphere(ch == "o" and 0.3 or 0.1)
        p:set_position(vec3(wx(c), 0.05, wz(r)))
        if ch == "o" then mat(p, vec3(1, 0.8, 0.7), vec3(3.0, 2.2, 1.6), 0, 0.2)
        else mat(p, vec3(1, 0.85, 0.75), vec3(1.6, 1.15, 0.85), 0, 0.3) end
        nodes.pellets[r * W + c] = { node = p, power = ch == "o", c = c, r = r }
        if ch == "o" then nodes.pellets[r * W + c].light = addLight(vec3(wx(c), 0.8, wz(r)), vec3(1, 0.8, 0.6), 3, 2.5) end
        S.totalDots = S.totalDots + 1
      end
    end
  end

  -- pac-man: emissive sphere + dark cone mouth
  pac.body = primitives.uv_sphere(0.46, 32, 24)
  mat(pac.body, vec3(1, 0.85, 0.05), vec3(1.3, 1.0, 0.0), 0.0, 0.35)
  pac.pivot = scene.add_empty_node("PacPivot")
  pac.mouth = primitives.cone(0.5, 1.0)
  pac.mouth:set_parent(pac.pivot)
  mat(pac.mouth, vec3(0, 0, 0), vec3(0, 0, 0), 0, 1)
  pac.eye = primitives.sphere(0.07)
  mat(pac.eye, vec3(0, 0, 0), vec3(0, 0, 0), 0, 0.5)
  pac.light = addLight(vec3(0, 1.2, 0), vec3(1, 0.85, 0.3), 6, 5)

  -- ghosts
  local defs = {
    { name = "blinky", col = vec3(1.0, 0.05, 0.05), emis = vec3(1.1, 0.04, 0.04), scatter = {25, -3}, home = {13.5, 11}, start = {13.5, 11}, dot = 0 },
    { name = "pinky",  col = vec3(1.0, 0.45, 0.8),  emis = vec3(1.0, 0.35, 0.7), scatter = {2, -3},  home = {13.5, 14}, start = {13.5, 14}, dot = 0 },
    { name = "inky",   col = vec3(0.0, 0.9, 1.0),   emis = vec3(0.04, 0.8, 1.0), scatter = {27, 31}, home = {11.5, 14}, start = {11.5, 14}, dot = 30 },
    { name = "clyde",  col = vec3(1.0, 0.6, 0.1),   emis = vec3(1.1, 0.5, 0.04), scatter = {0, 31},  home = {15.5, 14}, start = {15.5, 14}, dot = 60 },
  }
  for i, d in ipairs(defs) do
    local g = { def = d, parts = {} }
    g.dome = primitives.uv_sphere(0.5, 24, 16)
    g.skirt = primitives.cylinder(0.5, 0.45)
    g.feet = {}
    for k = 1, 4 do g.feet[k] = primitives.sphere(0.16) end
    g.eyes, g.pupils = {}, {}
    for k = 1, 2 do
      g.eyes[k] = primitives.sphere(0.17); mat(g.eyes[k], vec3(1, 1, 1), vec3(0.9, 0.9, 1.0), 0, 0.3)
      g.pupils[k] = primitives.sphere(0.095); mat(g.pupils[k], vec3(0.05, 0.1, 0.9), vec3(0.05, 0.1, 1.2), 0, 0.3)
    end
    g.light = addLight(vec3(0, 1, 0), d.col, 4, 3.5)
    ghosts[i] = g
  end

  -- fruit (cherry-ish: two red spheres + green stem)
  pac.fruit = { primitives.sphere(0.2), primitives.sphere(0.2), primitives.cylinder(0.03, 0.4) }
  mat(pac.fruit[1], vec3(1, 0.05, 0.1), vec3(2.0, 0.1, 0.2), 0.2, 0.2)
  mat(pac.fruit[2], vec3(1, 0.05, 0.1), vec3(2.0, 0.1, 0.2), 0.2, 0.2)
  mat(pac.fruit[3], vec3(0.2, 0.8, 0.1), vec3(0.3, 1.2, 0.1), 0, 0.5)
  for _, n in ipairs(pac.fruit) do n:set_visible(false) end

  -- ambient motes drifting over the maze
  pcall(particles.add_emitter, {
    name = "motes", position = vec3(0, 1.5, 0), velocity = vec3(0, 0.15, 0),
    color_start = vec4(0.3, 0.5, 1.0, 0.5), color_end = vec4(0.8, 0.3, 1.0, 0.0),
    gravity = vec3(0, 0.02, 0), count = math.floor(400 * SET:particle_scale()), size_min = 0.02, size_max = 0.06,
    life_min = 4, life_max = 8, spawn_rate = 50 * SET:particle_scale(), spawn_radius = 16, noise_strength = 0.4, drag = 0.2 })
end

-- ---------------------------------------------------------------- level/round setup
local function levelSpeeds()
  local L = S.level
  local base = 9.5
  if L == 1 then return { pac = 0.80 * base, pacF = 0.90 * base, ghost = 0.75 * base, ghostF = 0.50 * base, tunnel = 0.40 * base }
  elseif L <= 4 then return { pac = 0.90 * base, pacF = 0.95 * base, ghost = 0.85 * base, ghostF = 0.55 * base, tunnel = 0.45 * base }
  else return { pac = 1.0 * base, pacF = 1.0 * base, ghost = 0.95 * base, ghostF = 0.60 * base, tunnel = 0.50 * base } end
end
local MODES = { {"scatter", 7}, {"chase", 20}, {"scatter", 7}, {"chase", 20}, {"scatter", 5}, {"chase", 20}, {"scatter", 5}, {"chase", 1e9} }
local function frightTime() return math.max(1.0, 7 - S.level) end

local function resetActors()
  pac.x, pac.y, pac.dx, pac.dy, pac.want = 13.5, 23, -1, 0, {-1, 0}
  pac.mouthT, pac.angle, pac.deadT = 0, 180, 0
  for i, g in ipairs(ghosts) do
    g.x, g.y = g.def.start[1], g.def.start[2]
    g.dx, g.dy = (i == 1) and -1 or 0, 0
    g.state = (i == 1) and "normal" or "house"
    if i == 2 then g.state = "leaving" end
    g.fright = false; g.bob = i
    g.rev = false
  end
  S.modeIdx, S.modeT, S.fright = 1, 0, 0
  S.lastDotT = 0
  S.fruit = nil
  for _, n in ipairs(pac.fruit) do n:set_visible(false) end
end

local function resetPellets()
  S.dots = 0
  for _, p in pairs(nodes.pellets) do p.eaten = false; p.node:set_visible(true) end
  S.fruitSpawned = 0
end

-- ---------------------------------------------------------------- movement
local function blocked(c, r, ghost)
  local ch = cell(c, r)
  if ch == "#" then return true end
  if ch == "-" and not ghost then return true end
  return false
end

local function advance(e, d, chooser)
  local guard = 0
  while d > 1e-6 and guard < 8 do
    guard = guard + 1
    if e.dx == 0 and e.dy == 0 then
      chooser(e)
      if e.dx == 0 and e.dy == 0 then return end
    end
    local horiz = e.dx ~= 0
    local cur = horiz and e.x or e.y
    local dir = horiz and e.dx or e.dy
    local nextc
    if dir > 0 then nextc = math.floor(cur + 1e-6) + 1 else nextc = math.ceil(cur - 1e-6) - 1 end
    local dist = math.abs(nextc - cur)
    if dist > d then
      if horiz then e.x = e.x + dir * d else e.y = e.y + dir * d end
      d = 0
    else
      if horiz then e.x = nextc else e.y = nextc end
      d = d - dist
      if e.x < -1 then e.x = e.x + W elseif e.x > W then e.x = e.x - W end
      chooser(e)
    end
  end
end

-- At every tile centre: newest held direction if open, else another held direction that is open
-- (the perpendicular one when two are held), else the buffered last press (pre-turn), else keep
-- going straight if open, else stop. Never stops while any held direction leads somewhere.
local function pacChooser(e)
  local c, r = math.floor(e.x + 0.5), math.floor(e.y + 0.5)
  local function open(d) return d and not blocked(c + d[1], r + d[2]) end
  for _, d in ipairs(e.held or {}) do
    if open(d) then e.dx, e.dy = d[1], d[2]; return end
  end
  if open(e.want) then e.dx, e.dy = e.want[1], e.want[2]; return end
  if (e.dx ~= 0 or e.dy ~= 0) and open({ e.dx, e.dy }) then return end
  e.dx, e.dy = 0, 0
end

local function ghostTarget(g, i)
  if g.state == "eyes" then return 13, 11 end
  local mode = MODES[S.modeIdx][1]
  local pc, pr = math.floor(pac.x + 0.5), math.floor(pac.y + 0.5)
  local pdx, pdy = pac.ldx or -1, pac.ldy or 0
  if mode == "scatter" then return g.def.scatter[1], g.def.scatter[2] end
  if i == 1 then return pc, pr
  elseif i == 2 then return pc + 4 * pdx, pr + 4 * pdy
  elseif i == 3 then
    local b = ghosts[1]
    local ax, ay = pc + 2 * pdx, pr + 2 * pdy
    return 2 * ax - b.x, 2 * ay - b.y
  else
    local dx, dy = g.x - pac.x, g.y - pac.y
    if dx * dx + dy * dy > 64 then return pc, pr end
    return g.def.scatter[1], g.def.scatter[2]
  end
end

local function makeGhostChooser(i)
  return function(g)
    local c, r = math.floor(g.x + 0.5), math.floor(g.y + 0.5)
    if g.rev then g.rev = false; g.dx, g.dy = -g.dx, -g.dy; if not blocked(c + g.dx, r + g.dy, false) then return end end
    if g.state == "eyes" and r == 11 and (c == 13 or c == 14) then
      g.state = "entering"; g.dx, g.dy = 0, 0; return
    end
    local opts = {}
    for _, d in ipairs(DIRS) do
      if not (d[1] == -g.dx and d[2] == -g.dy) and not blocked(c + d[1], r + d[2], false) then
        opts[#opts + 1] = d
      end
    end
    if #opts == 0 then g.dx, g.dy = -g.dx, -g.dy; return end
    local pick
    if g.fright and g.state == "normal" then
      pick = opts[math.random(#opts)]
    else
      local tx, ty = ghostTarget(g, i)
      local best = 1e18
      for _, d in ipairs(opts) do
        local nx, ny = c + d[1], r + d[2]
        local dd = (nx - tx) ^ 2 + (ny - ty) ^ 2
        if dd < best then best = dd; pick = d end
      end
    end
    g.dx, g.dy = pick[1], pick[2]
  end
end
local ghostChoosers = {}
for i = 1, 4 do ghostChoosers[i] = makeGhostChooser(i) end

local function moveToward(g, tx, ty, d)
  if math.abs(g.x - tx) > 1e-3 then
    local s = tx > g.x and 1 or -1
    local step = math.min(d, math.abs(tx - g.x)); g.x = g.x + s * step; g.dx, g.dy = s, 0
    return false
  end
  g.x = tx
  if math.abs(g.y - ty) > 1e-3 then
    local s = ty > g.y and 1 or -1
    local step = math.min(d, math.abs(ty - g.y)); g.y = g.y + s * step; g.dx, g.dy = 0, s
    return false
  end
  g.y = ty
  return true
end

-- ---------------------------------------------------------------- UI
local UI = "hud"
local MENU = "menu"
local function surf()
  local ok, s = pcall(runtime_ui.get_surface_size)
  if ok and s then return (s.w or s.width or 1280), (s.h or s.height or 720) end
  return 1280, 720
end
local function txt(screen, id, x, y, w, h, s, scale, col, alignh, z)
  runtime_ui.set_quad(screen, id, { x = x, y = y, w = w, h = h, style = "text", label = s,
    fill = {0, 0, 0, 0}, border = {0, 0, 0, 0}, text_color = col or {1, 1, 1, 1},
    font_scale = scale or 1, align_h = alignh or "center", align_v = "center", no_input = true, z = z or 5 })
end
local function panel(screen, id, x, y, w, h, fill, border, z)
  runtime_ui.set_quad(screen, id, { x = x, y = y, w = w, h = h, style = "text", label = "",
    fill = fill, border = border or {0, 0, 0, 0}, corner_radius = 14, no_input = true, z = z or 1 })
end

-- world -> screen projection (mirrors the camera we set)
local camPos, camTgt = {0, 30, 15}, {0, 0, 1}
local function project(x, y, z)
  local sw, sh = surf()
  local fx, fy, fz = camTgt[1] - camPos[1], camTgt[2] - camPos[2], camTgt[3] - camPos[3]
  local fl = math.sqrt(fx * fx + fy * fy + fz * fz); fx, fy, fz = fx / fl, fy / fl, fz / fl
  -- right = f x up(0,1,0)
  local rx, ry, rz = -fz, 0, fx
  local rl = math.sqrt(rx * rx + rz * rz); rx, rz = rx / rl, rz / rl
  local ux, uy, uz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx
  local px, py, pz = x - camPos[1], y - camPos[2], z - camPos[3]
  local cx, cy, cz = px * rx + py * ry + pz * rz, px * ux + py * uy + pz * uz, px * fx + py * fy + pz * fz
  local th = math.tan(math.rad(62) / 2)
  local aspect = sw / sh
  local nx = cx / (cz * th)
  local ny = cy / (cz * th / aspect)
  return (nx * 0.5 + 0.5) * sw, (0.5 - ny * 0.5) * sh
end

local YEL = {1, 0.85, 0.1, 1}
local CYAN = {0.4, 0.9, 1, 1}
local PINK = {1, 0.5, 0.85, 1}
local function drawHud()
  local sw, sh = surf()
  local lx = sw * 0.02
  local pw = sw * 0.19
  panel(UI, "lp", lx, sh * 0.08, pw, sh * 0.84, {0.02, 0.03, 0.12, 0.55}, {0.2, 0.4, 1, 0.6})
  txt(UI, "t1", lx, sh * 0.11, pw, 40, "1UP", 1.4, CYAN)
  txt(UI, "score", lx, sh * 0.16, pw, 60, string.format("%d", S.score), 2.4, {1, 1, 1, 1})
  txt(UI, "t2", lx, sh * 0.27, pw, 40, "HIGH SCORE", 1.4, PINK)
  txt(UI, "hi", lx, sh * 0.32, pw, 60, string.format("%d", math.max(S.hi, S.score)), 2.0, {1, 1, 1, 1})
  txt(UI, "t3", lx, sh * 0.45, pw, 40, "LEVEL", 1.4, CYAN)
  txt(UI, "lvl", lx, sh * 0.5, pw, 60, tostring(S.level), 2.4, YEL)
  -- dots progress bar
  local frac = S.totalDots > 0 and S.dots / S.totalDots or 0
  panel(UI, "barbg", lx + pw * 0.1, sh * 0.62, pw * 0.8, 14, {0.1, 0.12, 0.3, 0.9}, nil, 2)
  panel(UI, "bar", lx + pw * 0.1, sh * 0.62, math.max(4, pw * 0.8 * frac), 14, {1, 0.8, 0.15, 1}, nil, 3)
  txt(UI, "t4", lx, sh * 0.645, pw, 30, string.format("%d / %d PELLETS", S.dots, S.totalDots), 1.0, {0.7, 0.75, 1, 1})

  local rx = sw - lx - pw
  panel(UI, "rp", rx, sh * 0.08, pw, sh * 0.84, {0.02, 0.03, 0.12, 0.55}, {0.2, 0.4, 1, 0.6})
  txt(UI, "t5", rx, sh * 0.11, pw, 40, "LIVES", 1.4, CYAN)
  for i = 1, 5 do
    runtime_ui.set_quad(UI, "life" .. i, { x = rx + pw * 0.5 - 95 + (i - 1) * 40, y = sh * 0.17, w = 30, h = 30,
      style = "image", radial_segments = 1, radial_filled = 1, fill = {1, 0.85, 0.1, 1}, no_input = true, z = 4,
      visible = i <= S.lives - (S.state == "play" and 1 or 0) })
  end
  local mode = (S.fright > 0) and "FRIGHTENED" or string.upper(MODES[S.modeIdx][1])
  txt(UI, "t6", rx, sh * 0.27, pw, 40, "GHOST MODE", 1.4, PINK)
  txt(UI, "mode", rx, sh * 0.32, pw, 50, mode, 1.6, S.fright > 0 and {0.4, 0.5, 1, 1} or (mode == "CHASE" and {1, 0.3, 0.3, 1} or {0.5, 1, 0.6, 1}))
  if S.fright > 0 then
    local ft = S.fright / frightTime()
    panel(UI, "fbarbg", rx + pw * 0.1, sh * 0.39, pw * 0.8, 10, {0.1, 0.12, 0.3, 0.9}, nil, 2)
    panel(UI, "fbar", rx + pw * 0.1, sh * 0.39, math.max(4, pw * 0.8 * ft), 10, {0.3, 0.45, 1, 1}, nil, 3)
  else
    runtime_ui.set_many_visible(UI, {"fbarbg", "fbar"}, false)
  end
  txt(UI, "t7", rx, sh * 0.47, pw, 40, "CONTROLS", 1.2, CYAN)
  txt(UI, "c1", rx, sh * 0.52, pw, 30, "ARROWS / WASD  move", 0.95, {0.8, 0.85, 1, 1})
  txt(UI, "c2", rx, sh * 0.56, pw, 30, "P / ESC  pause", 0.95, {0.8, 0.85, 1, 1})
  txt(UI, "c3", rx, sh * 0.60, pw, 30, "ENTER  start", 0.95, {0.8, 0.85, 1, 1})
  txt(UI, "fruit", rx, sh * 0.72, pw, 40, S.fruit and "BONUS FRUIT!" or "", 1.3, {1, 0.3, 0.4, 1})

  -- centre messages
  local msg, col = "", YEL
  if S.state == "ready" then msg = "READY!"
  elseif S.state == "gameover" then msg = "GAME  OVER"; col = {1, 0.15, 0.15, 1}
  elseif S.state == "levelclear" then msg = "LEVEL CLEAR!"; col = CYAN end
  local mx, my = project(0, 0.5, wz(17))
  txt(UI, "msg", mx - 300, my - 30, 600, 60, msg, 2.4, col, "center", 20)

  -- score popups
  for i = 1, 6 do
    local p = S.popups[i]
    if p then
      local px, py = project(p.x, 0.8, p.z)
      local a = clamp(p.t / 0.4, 0, 1)
      txt(UI, "pop" .. i, px - 80, py - 40 - (1.2 - p.t) * 30, 160, 40, p.text, 1.7, {p.col[1], p.col[2], p.col[3], a}, "center", 25)
    else
      runtime_ui.set_many_visible(UI, {"pop" .. i}, false)
    end
  end
end

local menuItems = { "START GAME", "SETTINGS", "QUIT" }
local pauseItems = { "RESUME", "RESTART", "SETTINGS", "MAIN MENU" }
local menuMouseXY = nil
-- mouse on the title / pause list: hover (after the mouse moves) selects, click activates
local function menuMouse(n, sel)
  local hit
  for i = 1, n do
    local ok, st = pcall(runtime_ui.get_state, MENU, "item" .. i)
    if ok and st then
      local moved = st.mouse_x and menuMouseXY and (math.abs(st.mouse_x - menuMouseXY[1]) + math.abs(st.mouse_y - menuMouseXY[2]) > 2)
      if st.mouse_x then menuMouseXY = {st.mouse_x, st.mouse_y} end
      if st.hovered and moved then sel = i end
      if st.clicked then sel = i; hit = i end
    end
  end
  return sel, hit
end
local function drawMenu(title, sub, items, sel, extra)
  local sw, sh = surf()
  panel(MENU, "dim", 0, 0, sw, sh, {0, 0, 0.03, 0.55}, nil, 30)
  local pw, ph = sw * 0.42, sh * 0.7
  local px, py = (sw - pw) / 2, (sh - ph) / 2
  panel(MENU, "box", px, py, pw, ph, {0.02, 0.03, 0.14, 0.88}, {0.25, 0.45, 1, 0.9}, 31)
  local pulse = 0.85 + 0.15 * math.sin(S.t * 3)
  txt(MENU, "title", px, py + ph * 0.06, pw, 90, title, 8.0, {1, 0.85 * pulse, 0.1, 1}, "center", 32)
  txt(MENU, "sub", px, py + ph * 0.21, pw, 40, sub, 1.4, {0.4, 0.85, 1, 1}, "center", 32)
  for i = 1, 4 do
    local it = items[i]
    if it then
      local y = py + ph * 0.36 + (i - 1) * 64
      local on = i == sel
      runtime_ui.set_quad(MENU, "item" .. i, { x = px + pw * 0.2, y = y, w = pw * 0.6, h = 52, style = "text",
        label = (on and "> " or "") .. it .. (on and " <" or ""), font_scale = 1.6, corner_radius = 12,
        fill = on and {1, 0.8, 0.1, 0.95} or {0.08, 0.1, 0.3, 0.8}, border = {0.3, 0.5, 1, 0.8},
        text_color = on and {0.05, 0.03, 0.1, 1} or {0.85, 0.9, 1, 1}, align_h = "center", align_v = "center", z = 33 })
    else
      runtime_ui.set_many_visible(MENU, {"item" .. i}, false)
    end
  end
  txt(MENU, "foot", px, py + ph * 0.84, pw, 40, extra or "", 1.1, {0.75, 0.8, 1, 1}, "center", 32)
end

-- ---------------------------------------------------------------- rendering of actors
local function placePac(dt)
  local x, z = wx(pac.x), wz(pac.y)
  local moving = (pac.dx ~= 0 or pac.dy ~= 0)
  if moving then pac.mouthT = pac.mouthT + dt * 14; pac.ldx, pac.ldy = pac.dx, pac.dy end
  local ldx, ldy = pac.ldx or -1, pac.ldy or 0
  local targetAng = math.deg(math.atan2(-ldy, ldx))
  pac.angle = targetAng
  local open = 0.5 + 0.5 * math.sin(pac.mouthT)
  local scale = 1
  local y = 0.25
  if S.state == "dying" then
    local k = clamp(pac.deadT / 1.4, 0, 1)
    open = 1 + k * 3
    scale = math.max(0.02, 1 - k)
    y = 0.25 + k * 0.6
    targetAng = targetAng + k * 720
  end
  pac.body:set_position(vec3(x, y, z))
  pac.body:set_scale(vec3(scale, scale * 0.8, scale))
  -- mouth: a flattened cone lying on its side, apex at the centre, opening along the heading
  local rad = math.rad(targetAng)
  local hx, hz = math.cos(rad), -math.sin(rad)
  pac.pivot:set_transform(vec3(x, y + 0.02, z), vec3(0, math.deg(math.atan2(hx, hz)), 0), vec3(1, 1, 1))
  local w = math.max(0.002, (0.02 + 0.98 * open) * scale)
  pac.mouth:set_transform(vec3(0, 0, 0.25 * scale), vec3(-90, 0, 0), vec3(w * 1.25, 0.6 * scale, 1.6 * scale))
  pac.mouth:set_visible(scale > 0.05)
  pac.eye:set_position(vec3(x + hx * 0.12 - hz * 0.18, y + 0.36 * scale, z + hz * 0.12 + hx * 0.18))
  pac.eye:set_visible(scale > 0.3)
  lights.set_point_light(pac.light, vec3(x, 1.0, z), vec3(1, 0.8, 0.25), (S.state == "dying") and 6 * scale or 7, 5)
end

local function placeGhost(g, i, dt)
  local x, z = wx(g.x), wz(g.y)
  g.bob = g.bob + dt * 6
  local y = 0.15 + 0.06 * math.sin(g.bob)
  local eyesOnly = g.state == "eyes" or g.state == "entering"
  local hidden = S.state == "dying" and pac.deadT > 0.5 or S.state == "levelclear"
  local col, emis = g.def.col, g.def.emis
  if g.fright and not eyesOnly then
    local flashing = S.fright < 2 and (math.floor(S.fright * 6) % 2 == 0)
    if flashing then col, emis = vec3(1, 1, 1), vec3(1.2, 1.2, 1.3)
    else col, emis = vec3(0.1, 0.15, 1.0), vec3(0.1, 0.15, 1.3) end
  end
  if g.lastCol ~= col then
    material.set(g.dome, "base_color", col); material.set(g.dome, "emissive", emis)
    material.set(g.skirt, "base_color", col); material.set(g.skirt, "emissive", emis)
    for k = 1, 4 do material.set(g.feet[k], "base_color", col); material.set(g.feet[k], "emissive", emis) end
    g.lastCol = col
  end
  local bodyVis = not eyesOnly and not hidden
  g.dome:set_visible(bodyVis); g.skirt:set_visible(bodyVis)
  g.dome:set_position(vec3(x, y + 0.2, z))
  g.skirt:set_position(vec3(x, y - 0.0, z))
  for k = 1, 4 do
    local a = g.bob * 0.5 + k * math.pi / 2
    g.feet[k]:set_visible(bodyVis)
    g.feet[k]:set_position(vec3(x + math.cos(a) * 0.36, y - 0.2 + 0.03 * math.sin(g.bob * 2 + k), z + math.sin(a) * 0.36))
  end
  local dx, dy = g.dx, g.dy
  if dx == 0 and dy == 0 then dy = 1 end
  -- eyes face camera side (+z) and slightly toward heading
  local px, pz = -dy, dx -- perpendicular
  for k = 1, 2 do
    local s = (k == 1) and -1 or 1
    local ex, ez = x + px * 0.16 * s + dx * 0.22, z + pz * 0.16 * s + dy * 0.22
    g.eyes[k]:set_position(vec3(ex, y + 0.5, ez + 0.2))
    g.pupils[k]:set_position(vec3(ex + dx * 0.08, y + 0.6, ez + 0.24 + dy * 0.06))
    local ev = not hidden and not (g.fright and not eyesOnly)
    g.eyes[k]:set_visible(not hidden)
    g.pupils[k]:set_visible(ev)
  end
  local lc = g.fright and not eyesOnly and vec3(0.2, 0.3, 1) or g.def.col
  lights.set_point_light(g.light, vec3(x, 1, z), lc, (bodyVis and 4 or 0.5), 3.5)
end

-- ---------------------------------------------------------------- gameplay
local function addScore(n)
  local before = S.score
  S.score = S.score + n
  if before < 10000 and S.score >= 10000 then S.lives = S.lives + 1; sfx("extralife") end
  if S.score > S.hi then S.hi = S.score end
end
local function popup(text, x, z, col)
  table.insert(S.popups, 1, { text = text, x = x, z = z, t = 1.2, col = col or {1, 1, 1} })
  if #S.popups > 6 then table.remove(S.popups) end
end

local function startRound(fresh)
  resetActors()
  S.state = "ready"
  S.t0 = 0
  S.readyT = fresh and 4.3 or 2.0
  if fresh then sfx("start") end
end

local function newGame()
  S.score, S.lives, S.level = 0, 3, 1
  resetPellets()
  startRound(true)
  runtime_ui.hide(MENU)
end

local function eatAt(c, r)
  local key = r * W + (c % W)
  local p = nodes.pellets[key]
  if p and not p.eaten then
    p.eaten = true
    p.node:set_visible(false)
    if p.light then lights.set_point_light(p.light, vec3(0, -50, 0), vec3(0, 0, 0), 0, 0.1) end
    S.dots = S.dots + 1
    S.lastDotT = 0
    if p.power then
      addScore(50)
      sfx("power")
      S.fright = frightTime(); S.ghostCombo = 0
      for _, g in ipairs(ghosts) do
        if g.state == "normal" or g.state == "house" or g.state == "leaving" then g.fright = true end
        if g.state == "normal" then g.rev = true end
      end
      burst(wx(c), 0.3, wz(r), vec4(1, 0.9, 0.6, 1), vec4(0.3, 0.4, 1, 0), 90, 4, 0.16, 0.9)
      S.flash = 0.25
    else
      addScore(10)
      -- eating: alternating "wa"/"ka" chomp (new procedural sound, tools/gen_audio.py)
      if S.wakaT <= 0 then
        S.wakaFlip = not S.wakaFlip
        sfx(S.wakaFlip and "waka1" or "waka2"); S.wakaT = 0.13; S.moveT = 0.2
      end
      burst(wx(c), 0.15, wz(r), vec4(1, 0.85, 0.5, 1), vec4(1, 0.5, 0.1, 0), 8, 1.2, 0.06, 0.3)
    end
    if (S.dots == 70 or S.dots == 170) and not S.fruit then
      S.fruit = { t = 9.5, value = ({100, 300, 500, 500, 700, 700, 1000, 1000, 2000, 2000, 3000, 3000, 5000})[math.min(S.level, 13)] }
      for _, n in ipairs(pac.fruit) do n:set_visible(true) end
    end
    if S.dots >= S.totalDots then
      S.state = "levelclear"; S.t0 = 0
    end
  end
end

local function killPac()
  S.state = "dying"; pac.deadT = 0
  sfx("death")
  S.shake = 0.5 * SET:shake_scale()
  burst(wx(pac.x), 0.4, wz(pac.y), vec4(1, 0.9, 0.1, 1), vec4(1, 0.2, 0.0, 0), 160, 5, 0.18, 1.2)
end

local function updatePlay(dt)
  local sp = levelSpeeds()
  -- mode timer (paused while frightened)
  if S.fright > 0 then
    S.fright = S.fright - dt
    if S.fright <= 0 then
      S.fright = 0
      for _, g in ipairs(ghosts) do g.fright = false end
    end
  else
    S.modeT = S.modeT + dt
    if S.modeT >= MODES[S.modeIdx][2] then
      S.modeT = 0; S.modeIdx = math.min(#MODES, S.modeIdx + 1)
      for _, g in ipairs(ghosts) do if g.state == "normal" then g.rev = true end end
    end
  end
  -- pac
  local pc, pr = math.floor(pac.x + 0.5), math.floor(pac.y + 0.5)
  local tunnel = pr == 14 and (pc < 6 or pc > 21)
  local pspeed = S.fright > 0 and sp.pacF or sp.pac
  -- instant reverse
  if pac.want and pac.want[1] == -pac.dx and pac.want[2] == -pac.dy and (pac.dx ~= 0 or pac.dy ~= 0) then
    pac.dx, pac.dy = pac.want[1], pac.want[2]
  end
  local ox, oy = pac.x, pac.y
  advance(pac, pspeed * dt, pacChooser)
  if pac.dx == 0 and pac.dy == 0 then pacChooser(pac) end
  pc, pr = math.floor(pac.x + 0.5), math.floor(pac.y + 0.5)
  eatAt(pc, pr)
  -- moving: soft tick loop (the old dot sound); silent when Pac-Man is stopped against a wall
  local moved = math.abs(pac.x - ox) + math.abs(pac.y - oy) > 1e-4
  S.moveT = (S.moveT or 0) - dt
  if moved then
    if S.moveT <= 0 then sfx("move"); S.moveT = 0.26 end
  else
    S.moveT = 0
  end
  if S.state ~= "play" then return end

  -- fruit
  if S.fruit then
    S.fruit.t = S.fruit.t - dt
    if math.abs(pac.x - 13.5) < 0.7 and math.abs(pac.y - 17) < 0.6 then
      addScore(S.fruit.value); sfx("fruit")
      popup(tostring(S.fruit.value), wx(13.5), wz(17), {1, 0.4, 0.5})
      burst(wx(13.5), 0.4, wz(17), vec4(1, 0.2, 0.3, 1), vec4(1, 0.8, 0.2, 0), 80, 4, 0.14, 0.8)
      S.fruit.t = 0
    end
    if S.fruit.t <= 0 then
      S.fruit = nil
      for _, n in ipairs(pac.fruit) do n:set_visible(false) end
    end
  end

  -- ghost release
  S.lastDotT = S.lastDotT + dt
  for i, g in ipairs(ghosts) do
    if g.state == "house" then
      local need = math.max(0, g.def.dot - (S.level - 1) * 30)
      if S.dots >= need or S.lastDotT > 4 then
        g.state = "leaving"; S.lastDotT = 0
      end
    end
  end

  -- ghosts
  for i, g in ipairs(ghosts) do
    local gc, gr = math.floor(g.x + 0.5), math.floor(g.y + 0.5)
    local gs = sp.ghost
    if g.fright then gs = sp.ghostF end
    if gr == 14 and (gc < 6 or gc > 21) then gs = sp.tunnel end
    if g.state == "eyes" then gs = 15 end
    if i == 1 and S.totalDots - S.dots < 20 and not g.fright then gs = gs * 1.05 end -- Cruise Elroy
    if g.state == "house" then
      g.y = 14 + 0.35 * math.sin(S.t * 6 + i); g.dy = (math.cos(S.t * 6 + i) > 0) and 1 or -1
    elseif g.state == "leaving" then
      if moveToward(g, 13.5, 11, gs * 0.6 * dt) then g.state = "normal"; g.dx, g.dy = -1, 0 end
    elseif g.state == "entering" then
      if moveToward(g, 13.5, 14, 8 * dt) then g.state = "leaving"; g.fright = false end
    else
      advance(g, gs * dt, ghostChoosers[i])
      if g.state == "eyes" and g.dx == 0 and g.dy == 0 then g.state = "entering" end
    end
    -- collision
    if g.state == "normal" then
      local ddx, ddy = g.x - pac.x, g.y - pac.y
      if ddx * ddx + ddy * ddy < 0.5 then
        if g.fright then
          g.fright = false; g.state = "eyes"
          S.ghostCombo = S.ghostCombo + 1
          local pts = 200 * 2 ^ (S.ghostCombo - 1)
          addScore(pts); sfx("eatghost")
          popup(tostring(pts), wx(g.x), wz(g.y), {0.4, 0.9, 1})
          local c = g.def.col
          burst(wx(g.x), 0.4, wz(g.y), vec4(0.4, 0.5, 1, 1), vec4(c.x, c.y, c.z, 0), 120, 5, 0.16, 1.0)
          S.freeze = 0.5
        else
          killPac(); return
        end
      end
    end
  end
end

-- ---------------------------------------------------------------- autopilot (attract demo)
local function autopilot()
  local sc, sr = math.floor(pac.x + 0.5), math.floor(pac.y + 0.5)
  local danger = {}
  for _, g in ipairs(ghosts) do
    if g.state == "normal" and not g.fright then
      local gc, gr = math.floor(g.x + 0.5), math.floor(g.y + 0.5)
      for dy = -2, 2 do for dx = -2, 2 do danger[((gr + dy) * W) + ((gc + dx) % W)] = true end end
    end
  end
  local q, head, seen = { {sc % W, sr, nil} }, 1, { [sr * W + sc % W] = true }
  while head <= #q do
    local n = q[head]; head = head + 1
    local key = n[2] * W + n[1]
    local p = nodes.pellets[key]
    if n[3] and ((p and not p.eaten) or false) then pac.want = n[3]; return end
    for _, d in ipairs(DIRS) do
      local nc, nr = (n[1] + d[1]) % W, n[2] + d[2]
      local k2 = nr * W + nc
      if not seen[k2] and not blocked(nc, nr) and not danger[k2] then
        seen[k2] = true
        q[#q + 1] = { nc, nr, n[3] or d }
      end
    end
  end
  -- no safe path: flee
  for _, d in ipairs(DIRS) do if not blocked(sc + d[1], sr + d[2]) and not danger[(sr + d[2]) * W + (sc + d[1]) % W] then pac.want = d return end end
end

-- ---------------------------------------------------------------- input
local prevKeys = {}
local function pressed(k)
  local down = (input.is_key_down_raw or input.is_key_down)(k)
  local was = prevKeys[k]
  prevKeys[k] = down
  return down and not was
end
local function held(k) if _G.PACMAN_VK and _G.PACMAN_VK[k] then return true end return (input.is_key_down_raw or input.is_key_down)(k) end
local KEYS = { "Up", "Down", "Left", "Right", "W", "A", "S", "D", "Return", "Space", "Escape", "P", "Q", "F2" }
local function readInput()
  local e = {}
  for _, k in ipairs(KEYS) do e[k] = pressed(k) end
  return e
end

-- ---------------------------------------------------------------- camera
local function updateCamera(dt)
  local followX = (S.state == 'title') and math.sin(S.t * 0.3) * 1.5 or clamp(wx(pac.x or 13.5), -14, 14) * 0.12
  local followZ = clamp(wz(pac.y or 23), -15, 15) * 0.08
  S.camX = lerp(S.camX or 0, followX, clamp(dt * 2, 0, 1))
  S.camZ = lerp(S.camZ or 0, followZ, clamp(dt * 2, 0, 1))
  local sx, sz = 0, 0
  if S.shake > 0 then
    S.shake = S.shake - dt
    sx, sz = (math.random() - 0.5) * S.shake * 0.8, (math.random() - 0.5) * S.shake * 0.8
  end
  local intro = 0
  if S.state == "title" then intro = 1 end
  local orbit = S.t * 0.15
  if false then
    camPos = { math.sin(orbit) * 12, 30, 26 + math.cos(orbit) * 4 }
    camTgt = { 0, 0, 0.5 }
  else
    local sw, sh = surf()
    local t = math.tan(math.rad(31))
    local dist = math.max(17.2 / (t / (sw / sh)), 14.5 / (t * 0.56))
    local tilt = math.rad(17)
    camPos = { S.camX + sx, dist * math.cos(tilt), 0.9 + dist * math.sin(tilt) + S.camZ + sz }
    camTgt = { S.camX * 0.8 + sx, 0, 0.9 + S.camZ * 0.8 + sz }
  end
  camera:set_position(vec3(camPos[1], camPos[2], camPos[3]))
  camera:look_at(vec3(camTgt[1], camTgt[2], camTgt[3]))
end

-- ---------------------------------------------------------------- main loop
local built = false
local function init()
  pcall(function() local d = fs.read('Save/debug_maxdt.txt'); if d then S.maxDt = tonumber(d) end end)
  math.randomseed(math.floor((engine.get_metrics() or {}).delta_ms or 7) * 7919)
  build()
  SET:apply()
  built = true
  resetPellets()
  resetActors()
  S.state = "title"
  runtime_ui.set_screen_overlay(UI, true)
  runtime_ui.set_screen_overlay(MENU, true)
  runtime_ui.show(UI)
  runtime_ui.show(MENU)
end

local function update(dt)
  if not built then return end
  dt = math.min(dt or 0.016, S.maxDt or 0.05)
  S.t = S.t + dt
  local k = readInput()
  local up = held("Up") or held("W")
  local down = held("Down") or held("S")
  local left = held("Left") or held("A")
  local right = held("Right") or held("D")
  local confirm = k.Return or k.Space
  if k.F2 then S.auto = not S.auto end

  local function openSettings() runtime_ui.hide(MENU); SET:open(function() runtime_ui.show(MENU) end) end
  if SET:update(dt) then
    -- settings menu owns input while open
  elseif S.state == "title" or S.state == "gameover" and (S.t0 or 0) > 3 then
    if S.state == "gameover" then S.state = "title"; runtime_ui.show(MENU) end
    if k.Up or k.W then S.menuSel = math.max(1, S.menuSel - 1); sfx("click") end
    if k.Down or k.S then S.menuSel = math.min(#menuItems, S.menuSel + 1); sfx("click") end
    local mclick; S.menuSel, mclick = menuMouse(#menuItems, S.menuSel)
    if mclick then confirm = true end
    drawMenu("PAC-MAN", "~ PHASMA REMIX ~", menuItems, S.menuSel,
      "HIGH SCORE " .. S.hi .. "   |   ENTER to select")
    if confirm then
      sfx("click")
      if S.menuSel == 1 then newGame() elseif S.menuSel == 2 then openSettings() else engine.quit() end
    end
  elseif S.state == "paused" then
    if k.Up or k.W then S.pauseSel = math.max(1, S.pauseSel - 1); sfx("click") end
    if k.Down or k.S then S.pauseSel = math.min(#pauseItems, S.pauseSel + 1); sfx("click") end
    local pclick; S.pauseSel, pclick = menuMouse(#pauseItems, S.pauseSel)
    if pclick then confirm = true end
    drawMenu("PAUSED", "take a breath", pauseItems, S.pauseSel, "P / ESC to resume  |  mouse: click")
    if k.P or k.Escape then S.state = S.resumeState; runtime_ui.hide(MENU)
    elseif confirm then
      sfx("click")
      if S.pauseSel == 1 then S.state = S.resumeState; runtime_ui.hide(MENU)
      elseif S.pauseSel == 2 then saveHi(); newGame()
      elseif S.pauseSel == 3 then openSettings()
      else saveHi(); resetPellets(); resetActors(); S.state = "title"; S.menuSel = 1; runtime_ui.show(MENU) end
    end
  else
    if (k.P or k.Escape) and (S.state == "play" or S.state == "ready") then
      S.resumeState = S.state; S.state = "paused"; S.pauseSel = 1; runtime_ui.show(MENU)
    end
    -- held directions, newest press first; the newest one is also the buffered "want"
    -- (kept after release so a tap just before a junction still turns there)
    S.pressT = S.pressT or {}
    local hs = { { "up", up, {0, -1} }, { "down", down, {0, 1} }, { "left", left, {-1, 0} }, { "right", right, {1, 0} } }
    local held_list = {}
    for _, h in ipairs(hs) do
      if h[2] then
        if not S.pressT[h[1]] then S.pressT[h[1]] = S.t end
        held_list[#held_list + 1] = { h[3], S.pressT[h[1]] }
      else S.pressT[h[1]] = nil end
    end
    table.sort(held_list, function(a, b) return a[2] > b[2] end)
    pac.held = {}
    for i, h in ipairs(held_list) do pac.held[i] = h[1] end
    if pac.held[1] then pac.want = pac.held[1] end
    if S.auto and S.state == "play" then autopilot() end

    S.t0 = (S.t0 or 0) + dt
    if S.state == "ready" then
      if S.t0 >= S.readyT then S.state = "play" end
    elseif S.state == "play" then
      if S.freeze and S.freeze > 0 then S.freeze = S.freeze - dt
      else updatePlay(dt) end
      S.wakaT = S.wakaT - dt
    elseif S.state == "dying" then
      pac.deadT = pac.deadT + dt
      if pac.deadT > 2.2 then
        S.lives = S.lives - 1
        if S.lives <= 0 then S.state = "gameover"; S.t0 = 0; saveHi()
        else startRound(false) end
      end
    elseif S.state == "levelclear" then
      S.flash = 0
      if S.t0 > 2.6 then
        S.level = S.level + 1
        resetPellets(); startRound(false)
      end
    end
  end

  -- popups
  for i = #S.popups, 1, -1 do
    local p = S.popups[i]; p.t = p.t - dt
    if p.t <= 0 then table.remove(S.popups, i) end
  end

  -- wall glow: pulse, power flash, and level-clear strobe
  local wallE
  if S.state == "levelclear" then
    local on = math.floor(S.t0 * 5) % 2 == 0
    wallE = on and vec3(2.4, 2.4, 2.6) or vec3(0.15, 0.35, 2.4)
  else
    local p = 1 + 0.12 * math.sin(S.t * 2.0)
    if S.fright > 0 then p = p * 1.25 end
    S.flash = math.max(0, (S.flash or 0) - dt)
    local f = S.flash * 4
    wallE = vec3(0.15 * p + f, 0.35 * p + f, 2.4 * p + f)
  end
  if not S.lastWall or math.abs(S.lastWall.z - wallE.z) > 0.02 or math.abs(S.lastWall.x - wallE.x) > 0.02 then
    local t = {}
    for i, n in ipairs(nodes.caps) do
      t[#t + 1] = n; t[#t + 1] = wallE.x; t[#t + 1] = wallE.y; t[#t + 1] = wallE.z
    end
    material.set_emissives(t, #nodes.caps)
    S.lastWall = wallE
  end

  -- power pellets blink
  local blink = (S.state ~= "play") or (math.floor(S.t * 4) % 2 == 0)
  for _, p in pairs(nodes.pellets) do
    if p.power and not p.eaten then
      local s = 0.8 + 0.25 * math.sin(S.t * 8)
      if S.state ~= "play" then s = 1 end
      p.node:set_scale(vec3(s, s, s))
      lights.set_point_light(p.light, vec3(wx(p.c), 0.8, wz(p.r)), vec3(1, 0.75, 0.55), 2 + 2 * s, 2.5)
    end
  end
  -- fruit
  if S.fruit then
    local x, z = wx(13.5), wz(17)
    local b = 0.1 * math.sin(S.t * 4)
    pac.fruit[1]:set_position(vec3(x - 0.15, 0.2 + b, z + 0.1))
    pac.fruit[2]:set_position(vec3(x + 0.17, 0.2 + b, z + 0.05))
    pac.fruit[3]:set_position(vec3(x, 0.5 + b, z - 0.05))
  end

  -- particle trails: pac sparks, frightened ghost wisps, eyes streaks
  S.trailT = (S.trailT or 0) - dt
  if S.trailT <= 0 and S.state == "play" then
    S.trailT = 0.08
    if pac.dx ~= 0 or pac.dy ~= 0 then
      burst(wx(pac.x) - pac.dx * 0.4, 0.25, wz(pac.y) - pac.dy * 0.4, vec4(1, 0.8, 0.2, 0.9), vec4(1, 0.3, 0, 0), 6, 0.4, 0.07, 0.4)
    end
    for _, g in ipairs(ghosts) do
      if g.state == "eyes" then
        burst(wx(g.x), 0.5, wz(g.y), vec4(0.6, 0.8, 1, 0.9), vec4(0.2, 0.3, 1, 0), 5, 0.2, 0.06, 0.35)
      elseif g.fright then
        burst(wx(g.x), 0.2, wz(g.y), vec4(0.3, 0.4, 1, 0.8), vec4(0.6, 0.2, 1, 0), 4, 0.8, 0.08, 0.5)
      elseif g.state == "normal" then
        local c = g.def.col
        burst(wx(g.x) - g.dx * 0.4, 0.1, wz(g.y) - g.dy * 0.4, vec4(c.x, c.y, c.z, 0.6), vec4(c.x, c.y, c.z, 0), 3, 0.3, 0.06, 0.35)
      end
    end
  end
  -- full-screen flash overlay (power pellet = white-blue, death = red vignette)
  local fa, fc = 0, {1, 1, 1}
  if (S.flash or 0) > 0 then fa = S.flash * 1.4; fc = {0.6, 0.7, 1} end
  if S.state == "dying" then fa = math.max(0, 0.35 - pac.deadT * 0.15); fc = {1, 0.1, 0.1} end
  local fsw, fsh = surf()
  runtime_ui.set_quad(UI, "flashfx", { x = 0, y = 0, w = fsw, h = fsh, style = "text", label = "",
    fill = {fc[1], fc[2], fc[3], clamp(fa, 0, 0.5)}, border = {0, 0, 0, 0}, no_input = true, z = 0, visible = fa > 0.01 })
  S.debugT = (S.debugT or 0) + dt
  placePac(dt)
  for i, g in ipairs(ghosts) do placeGhost(g, i, dt) end
  updateCamera(dt)
  drawHud()
  if S.state == "title" then
    runtime_ui.set_many_visible(UI, {"msg"}, false)
  end
end

_G.PACMAN = { S = S, newGame = function() newGame() end, pac = pac, ghosts = ghosts, advance = advance, chooser = pacChooser, blocked = blocked }
hooks { init = init, update = update }
