-- NEON INVADERS : a modern remake of Space Invaders for PhasmaEngine
local P = 0.14                  -- invader pixel size
local FIELD_W = 13.0            -- half width of playfield
local TOP_Y, PLAYER_Y = 7.6, -8.6
local COLS, ROWS = 11, 5
local COL_SP, ROW_SP = 1.85, 1.45
local SHIELD_Y = -5.6

local ART = {
  squid = { w=8, color={1.0,0.15,0.85}, pts=30,
    a={"...##...","..####..",".######.","##.##.##","########","..#..#..",".#.##.#.","#.#..#.#"},
    b={"...##...","..####..",".######.","##.##.##","########",".#.##.#.","#......#",".#....#."} },
  crab = { w=11, color={0.1,0.95,1.0}, pts=20,
    a={"..#.....#..","...#...#...","..#######..",".##.###.##.","###########","#.#######.#","#.#.....#.#","...##.##..."},
    b={"..#.....#..","#..#...#..#","#.#######.#","###.###.###","###########",".#########.","..#.....#..",".#.......#."} },
  octo = { w=12, color={0.35,1.0,0.25}, pts=10,
    a={"....####....",".##########.","############","###..##..###","############","...##..##...","..##.##.##..","##........##"},
    b={"....####....",".##########.","############","###..##..###","############","..###..###..",".##..##..##.","..##....##.."} },
}
local ROW_KIND = {"squid","crab","crab","octo","octo"}

-- ---------------------------------------------------------------- helpers
local function v3(x,y,z) return vec3(x,y,z or 0) end
local function glow(n, c, e, metal)
  material.set(n, "base_color", vec4(c[1]*0.25, c[2]*0.25, c[3]*0.25, 1))
  material.set(n, "emissive", vec3(c[1]*e, c[2]*e, c[3]*e))
  material.set(n, "metallic", metal or 0.6)
  material.set(n, "roughness", 0.3)
end
local function box(parent, x, y, z, sx, sy, sz, c, e)
  local n = primitives.cube(1)
  if parent then n:set_parent(parent) end
  n:set_position(v3(x,y,z)); n:set_scale(v3(sx,sy,sz))
  glow(n, c, e)
  return n
end
local function sfx(name) if audio and audio.play then pcall(audio.play, name..".wav") end end
-- shared settings menu (Assets/Scripts/Lib/settings_menu.lua; see /workspace/games/common/SETTINGS_API.md)
local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
  title = "SETTINGS", subtitle = "NEON  INVADERS", click = function() sfx("hit") end,
  theme = { accent = {0.2, 1, 1, 1}, accent2 = {1, 0.3, 0.9, 1} } })

-- build a pixel-art sprite out of run-length cubes; returns root, frameA, frameB
local function build_sprite(name, art, color, emis)
  local root = scene.add_empty_node(name)
  local fa = scene.add_empty_node(name.."_a"); fa:set_parent(root)
  local fb = scene.add_empty_node(name.."_b"); fb:set_parent(root)
  local rows = #art.a
  for r = 1, rows do
    local same = art.a[r] == art.b[r]
    for which, frame in ipairs({art.a, art.b}) do
      if which == 1 or not same then
        local par = same and root or (which == 1 and fa or fb)
        local row = frame[r]; local c = 1
        while c <= #row do
          if row:sub(c,c) == "#" then
            local s = c
            while c+1 <= #row and row:sub(c+1,c+1) == "#" do c = c + 1 end
            local len = c - s + 1
            local cx = ((s - 1) + len/2 - art.w/2) * P
            local cy = (rows/2 - (r - 0.5)) * P
            box(par, cx, cy, 0, len*P*0.98, P*0.92, P*1.6, color, emis)
          end
          c = c + 1
        end
      end
    end
  end
  fb:set_enabled(false)
  return root, fa, fb
end

-- ---------------------------------------------------------------- state
local G = { state="menu", score=0, hi=0, lives=3, wave=1, t=0 }
local invaders, shields, pbul, ebul, stars = {}, {}, nil, {}, {}
local formation = { x=0, y=0, dir=1, step_t=0, frame=1, march=1 }
local player, ufo = {}, {}
local cam, shake = nil, 0
local LT, THRUST = nil, nil
local flash = { e=0, c={1,1,1}, x=0, y=0, ui=0, uc={1,1,1} }
local keys_prev = {}
local vkeys = {}
local jev
local hud_dirty = true
local SW, SH = 1920, 1080

local keydown = input.is_key_down_raw or input.is_key_down   -- raw: not swallowed while runtime UI is up
local function pressed(k)
  local d = keydown(k)
  local was = keys_prev[k]; keys_prev[k] = d
  return d and not was
end

local function boom(x, y, c, n, spd)
  flash.e = math.max(flash.e, (n or 70) / 25); flash.c = c; flash.x = x; flash.y = y
  particles.emit_burst({ position=v3(x,y,0.3), velocity=v3(0,0,0),
    color_start=vec4(c[1]*2.2+0.3,c[2]*2.2+0.3,c[3]*2.2+0.3,1), color_end=vec4(c[1],c[2]*0.3,c[3],0),
    gravity=v3(0,-2,0), count=math.max(1, math.floor((n or 70) * SET:particle_scale())), size_min=0.05, size_max=0.2, life_min=0.6, life_max=1.4,
    spawn_radius=0.7, noise_strength=spd or 6, drag=1.2 })
  -- hot white core flash
  particles.emit_burst({ position=v3(x,y,0.4), velocity=v3(0,0,0), color_start=vec4(3,3,3,1), color_end=vec4(c[1],c[2],c[3],0),
    gravity=v3(0,0,0), count=math.max(1, math.floor(25 * SET:particle_scale())), size_min=0.15, size_max=0.35, life_min=0.15, life_max=0.35, spawn_radius=0.25, noise_strength=2, drag=3 })
  -- expanding shockwave ring (tweened)
  local ring = primitives.torus(0.5, 0.04)
  ring:set_position(v3(x, y, 0.2)); ring:set_rotation(v3(90,0,0))
  glow(ring, c, 2.5, 0)
  tween.to(v3(0.3,0.3,0.3), v3(2.6,2.6,2.6), 0.35, function(sv) ring:set_scale(sv) end, { on_done = function() ring:remove() end })
end

-- ---------------------------------------------------------------- world
local function build_backdrop()
  local back = primitives.plane(140, 90)
  back:set_position(v3(0,0,-30)); back:set_rotation(v3(90,0,0))
  material.set(back, "base_color", vec4(0.0,0.0,0.01,1))
  material.set(back, "emissive", vec3(0.004,0.006,0.02))
  material.set(back, "roughness", 1.0); material.set(back, "metallic", 0.0)
  math.randomseed(1337)
  for i = 1, 140 do
    local s = primitives.cube(1)
    local z = -8 - math.random()*20
    local sz = 0.05 + math.random()*0.09
    s:set_position(v3((math.random()-0.5)*(70 + -z*2), (math.random()-0.5)*(42 + -z), z))
    s:set_scale(v3(sz,sz,sz))
    local tint = ({{1,1,1},{0.6,0.8,1},{1,0.85,0.6},{0.8,0.6,1}})[math.random(4)]
    local e = 1.5 + math.random()*5
    glow(s, tint, e, 0)
    stars[#stars+1] = { n=s, c=tint, e=e, ph=math.random()*6.28, sp=0.5+math.random()*2.5 }
  end
  -- nebula glows: big dim emissive spheres far back
  for _, nb in ipairs({{-24,12,-29,10,{0.35,0.05,0.5}},{24,-9,-29,12,{0.02,0.2,0.45}},{6,14,-29,7,{0.4,0.05,0.25}}}) do
    local s = primitives.sphere(nb[4]); s:set_position(v3(nb[1],nb[2],nb[3]))
    material.set(s,"base_color",vec4(0,0,0,1)); material.set(s,"emissive",vec3(nb[5][1]*0.12,nb[5][2]*0.12,nb[5][3]*0.12))
  end
  -- drifting space dust (continuous GPU emitter)
  particles.add_emitter({ name="dust", position=v3(0,14,-4), velocity=v3(0,-2.5,0),
    color_start=vec4(0.4,0.6,1.2,0.8), color_end=vec4(0.3,0.2,0.8,0), gravity=v3(0,0,0),
    count=math.floor(300 * SET:particle_scale()), size_min=0.02, size_max=0.06, life_min=6, life_max=10, spawn_rate=30 * SET:particle_scale(),
    spawn_radius=16, noise_strength=0.3, drag=0 })
  -- glossy reflective deck under the player (PBR metal + SSR)
  local deck = primitives.plane(80, 30)
  deck:set_position(v3(0, PLAYER_Y - 0.95, -6))
  material.set(deck, "base_color", vec4(0.02,0.03,0.06,1)); material.set(deck, "metallic", 1.0); material.set(deck, "roughness", 0.12)
  material.set(deck, "emissive", vec3(0.0,0.0,0.0))
  for i = -6, 6 do box(nil, i*4, PLAYER_Y-0.93, -6, 0.04, 0.02, 30, {0.1,0.4,1.0}, 0.8) end
  for k = 0, 6 do box(nil, 0, PLAYER_Y-0.93, 8 - k*4, 80, 0.02, 0.04, {0.1,0.4,1.0}, 0.8) end
  -- ground line
  box(nil, 0, PLAYER_Y-0.9, 0, FIELD_W*2+1.5, 0.06, 0.3, {0.2,1.0,0.5}, 1.5)
end

local function build_player()
  local root = scene.add_empty_node("Player")
  local c = {0.15, 1.0, 0.45}
  box(root, 0, -0.18, 0, 1.5, 0.32, 0.5, c, 1.2)
  box(root, 0,  0.08, 0, 1.0, 0.22, 0.45, c, 1.2)
  box(root, 0,  0.32, 0, 0.22, 0.32, 0.3, c, 2)
  box(root, -0.62, -0.38, 0.1, 0.18, 0.1, 0.3, {1,0.5,0.1}, 8)
  box(root,  0.62, -0.38, 0.1, 0.18, 0.1, 0.3, {1,0.5,0.1}, 8)
  player.root = root; player.x = 0; player.alive = true; player.respawn = 0
  root:set_position(v3(0, PLAYER_Y, 0))
end

local function build_ufo()
  local root = scene.add_empty_node("UFO")
  local disc = primitives.sphere(1); disc:set_parent(root); disc:set_scale(v3(1.2,0.32,0.6))
  glow(disc, {1.0,0.1,0.18}, 1.6, 0.8)
  local dome = primitives.sphere(1); dome:set_parent(root); dome:set_position(v3(0,0.28,0)); dome:set_scale(v3(0.5,0.38,0.45))
  glow(dome, {0.3,0.9,1.0}, 1.8, 0.2)
  for i = -2, 2 do box(root, i*0.42, -0.08, 0.5, 0.12, 0.08, 0.1, {1,1,0.4}, 12) end
  root:set_enabled(false)
  ufo.root = root; ufo.active = false; ufo.timer = 18
end

local function build_shields()
  for _, s in ipairs(shields) do for _, b in ipairs(s.cells) do if b.n then b.n:remove() end end end
  shields = {}
  local shape = {
    "..########..",
    ".##########.",
    "############",
    "############",
    "############",
    "###......###",
    "##........##",
  }
  local cs = 0.26
  for k = 1, 4 do
    local cx = -FIELD_W + (k - 0.5) * (FIELD_W*2/4)
    local sh = { cells = {} }
    for r, row in ipairs(shape) do
      for c = 1, #row do
        if row:sub(c,c) == "#" then
          local x = cx + (c - 6.5) * cs
          local y = SHIELD_Y + (#shape/2 - r + 0.5) * cs
          local n = box(nil, x, y, 0, cs*0.95, cs*0.95, cs*1.4, {1.0,0.38,0.04}, 0.9)
          material.set(n, "metallic", 0.9); material.set(n, "roughness", 0.25)
          sh.cells[#sh.cells+1] = { n=n, x=x, y=y, hp=2 }
        end
      end
    end
    shields[k] = sh
  end
end

local function spawn_wave()
  for _, iv in ipairs(invaders) do if iv.root then iv.root:remove() end end
  invaders = {}
  formation.x = 0; formation.dir = 1; formation.step_t = 0; formation.frame = 1
  formation.y = math.min(G.wave - 1, 5) * -0.5
  for r = 1, ROWS do
    local kind = ROW_KIND[r]; local art = ART[kind]
    for c = 1, COLS do
      local root, fa, fb = build_sprite("Inv", art, art.color, 1.25)
      local iv = { root=root, fa=fa, fb=fb, kind=kind, alive=true,
        ox = (c - (COLS+1)/2) * COL_SP, oy = TOP_Y - (r-1) * ROW_SP,
        hw = art.w * P * 0.5, hh = 4 * P, col=c, row=r, pts=art.pts, color=art.color, wob=math.random()*6 }
      invaders[#invaders+1] = iv
      -- drop-in tween from above
      local d = 0.02 * ((r-1)*COLS + c)
      local ix, iy = iv.ox, iv.oy + formation.y
      root:set_position(v3(ix, iy + 14, 0))
      tween.to(v3(ix, iy + 14 + d*40, 0), v3(ix, iy, 0), 0.9 + d, function(p) if iv.root and not G.marching then iv.root:set_position(p) end end, {})
    end
  end
  G.marching = false
  G.wave_intro = 1.6
end

-- ---------------------------------------------------------------- HUD / menus
local function quad(id, t)
  t.fill = t.fill or {0,0,0,0}; t.border = t.border or {0,0,0,0}
  runtime_ui.set_quad("hud", id, t)
end
local function fmt(n) return string.format("%05d", n) end

local function draw_hud()
  local s = runtime_ui.get_surface_size(); if s and s.valid then SW, SH = s.w, s.h end
  local u = SW / 1920
  quad("score_l", {x=40*u, y=24*u, w=420*u, h=40*u, label="SCORE", font_scale=2.0, text_color={0.5,0.8,1,1}, align_h="left"})
  quad("score",   {x=40*u, y=60*u, w=420*u, h=70*u, label=fmt(G.score), font_scale=3.6, text_color={0.3,1,0.9,1}, align_h="left"})
  quad("hi_l",    {x=SW/2-250*u, y=24*u, w=500*u, h=40*u, label="HI-SCORE", font_scale=2.0, text_color={1,0.5,0.9,1}})
  quad("hi",      {x=SW/2-250*u, y=60*u, w=500*u, h=70*u, label=fmt(G.hi), font_scale=3.6, text_color={1,0.3,0.85,1}})
  quad("wave",    {x=SW-460*u, y=24*u, w=420*u, h=40*u, label="WAVE "..G.wave, font_scale=2.0, text_color={1,0.8,0.3,1}, align_h="right"})
  local l = ""; for i = 1, math.max(G.lives-1,0) do l = l .. "▲ " end
  quad("lives",   {x=SW-460*u, y=60*u, w=420*u, h=70*u, label="LIVES "..G.lives, font_scale=2.4, text_color={0.3,1,0.5,1}, align_h="right"})
  hud_dirty = false
end

local PANEL_IDS = {"p_bg","p_title","p_sub","p_b1","p_b2","p_b3","p_b4"}
local function panel(title, sub, lines, col)
  local u = SW / 1920; col = col or {0.2,1,1,1}
  local x0, w = SW/2 - 560*u, 1120*u; local y0 = SH*0.30
  quad("p_bg", {x=x0, y=y0, w=w, h=SH*0.46, fill={0.02,0.0,0.07,0.78}, border=col, corner_radius=22*u, visible=true})
  quad("p_title", {x=x0, y=y0+20*u, w=w, h=150*u, label=title, font_scale=7.0, text_color=col, visible=true})
  quad("p_sub", {x=x0, y=y0+175*u, w=w, h=70*u, label=sub, font_scale=2.6, text_color={1,0.85,0.3,1}, visible=true})
  for i = 1, 4 do
    local l = lines[i]
    quad("p_b"..i, {x=x0, y=y0+260*u+(i-1)*58*u, w=w, h=56*u, label=l and l[1] or "", font_scale=2.0, text_color=l and l[2] or {1,1,1,1}, visible=l ~= nil})
  end
end
local function hide_panel() for _, id in ipairs(PANEL_IDS) do quad(id, {x=0,y=0,w=1,h=1, visible=false}) end end
local function banner(text, col)
  local u = SW / 1920
  quad("banner", {x=SW/2-500*u, y=SH*0.42, w=1000*u, h=140*u, label=text, font_scale=4.5, text_color=col or {1,1,1,1}, visible=true})
end
local function hide_banner() quad("banner", {x=0,y=0,w=1,h=1, visible=false}) end

-- ---------------------------------------------------------------- flow
local function start_game()
  G.score = 0; G.lives = 3; G.wave = 1
  G.clear_t = nil
  G.invaded = false
  G.req_kill = nil
  G.fire_t = nil
  G.popup = nil
  G.jev_error = nil
  quad("popup", {x=0, y=0, w=1, h=1, visible=false})
  for _, b in ipairs(ebul) do b.n:remove() end; ebul = {}
  if pbul then pbul.n:remove(); pbul = nil end
  build_shields(); spawn_wave()
  player.alive = true; player.x = 0; player.root:set_enabled(true)
  ufo.active = false; ufo.root:set_enabled(false); ufo.timer = 15 + math.random()*10
  G.state = "play"; hide_panel(); banner("WAVE 1", {1,0.8,0.3,1}); hud_dirty = true
  sfx("jingle")
end

local function show_menu()
  G.state = "menu"
  panel("NEON  INVADERS", "PRESS  SPACE  TO  START", {
    {"SQUID  =  30 PTS", {1,0.3,0.9,1}}, {"CRAB  =  20 PTS", {0.2,1,1,1}}, {"OCTOPUS  =  10 PTS     UFO  =  ? ? ?", {0.4,1,0.3,1}},
    {"ARROWS / A-D  MOVE      SPACE  FIRE      P  PAUSE      O  SETTINGS", {0.75,0.75,0.9,1}} })
end

local function game_over()
  G.state = "over"; G.over_t = 0
  if G.score > G.hi and not (jev and jev:assisted()) then G.hi = G.score end
  hud_dirty = true; hide_banner()
  panel("GAME OVER", "SCORE " .. fmt(G.score) .. "     HI " .. fmt(G.hi), { {"WAVE REACHED  "..G.wave, {1,0.8,0.3,1}}, {" ", {1,1,1,1}}, {"PRESS  SPACE  TO  PLAY  AGAIN", {0.3,1,0.9,1}} }, {1,0.25,0.5,1})
end

local function add_score(p)
  G.score = G.score + p
  if G.score > G.hi and not (jev and jev:assisted()) then G.hi = G.score end
  hud_dirty = true
end

-- ---------------------------------------------------------------- combat
local function alive_count() local n = 0; for _, iv in ipairs(invaders) do if iv.alive then n = n + 1 end end; return n end

local function inv_pos(iv) return iv.ox + formation.x, iv.oy + formation.y end

local function hit_shield(x, y, r, from_above)
  for _, sh in ipairs(shields) do
    for _, b in ipairs(sh.cells) do
      if b.n and math.abs(b.x - x) < 0.18 + r and math.abs(b.y - y) < 0.2 + r then
        -- erode: this cell plus random neighbours
        for _, o in ipairs(sh.cells) do
          if o.n and math.abs(o.x - b.x) < 0.45 and math.abs(o.y - b.y) < 0.45 and (o == b or math.random() < 0.35) then
            o.hp = o.hp - 1
            if o.hp <= 0 or o == b then o.n:remove(); o.n = nil
            else material.set(o.n, "emissive", vec3(0.6,0.12,0.0)) end
          end
        end
        particles.emit_burst({ position=v3(b.x,b.y,0.3), velocity=v3(0,from_above and -1 or 1,0),
          color_start=vec4(2.5,1.0,0.2,1), color_end=vec4(1,0.1,0,0), gravity=v3(0,-6,0), count=24,
          size_min=0.04, size_max=0.1, life_min=0.2, life_max=0.6, spawn_radius=0.15, noise_strength=4, drag=1 })
        return true
      end
    end
  end
  return false
end

local function fire_player()
  if pbul or not player.alive then return end
  local n = primitives.cube(1); n:set_scale(v3(0.09,0.55,0.09)); glow(n, {0.4,1,0.85}, 3.5, 0)
  pbul = { n=n, x=player.x, y=PLAYER_Y + 0.6 }
  n:set_position(v3(pbul.x, pbul.y, 0))
  sfx("shoot")
end

local function fire_enemy()
  local alive = alive_count(); if alive == 0 then return end
  -- pick a bottom invader in a random column (prefer column above the player sometimes)
  local bottoms = {}
  for _, iv in ipairs(invaders) do
    if iv.alive then
      local b = bottoms[iv.col]
      if not b or iv.row > b.row then bottoms[iv.col] = iv end
    end
  end
  local list = {}
  for _, iv in pairs(bottoms) do list[#list+1] = iv end
  local pick = list[math.random(#list)]
  if math.random() < 0.4 then
    local best, bd = nil, 1e9
    for _, iv in ipairs(list) do local x = inv_pos(iv); local d = math.abs(x - player.x); if d < bd then best, bd = iv, d end end
    pick = best or pick
  end
  local x, y = inv_pos(pick)
  local n = primitives.cube(1); n:set_scale(v3(0.12,0.4,0.12))
  local zig = math.random() < 0.5
  glow(n, zig and {1,0.25,1} or {1,0.85,0.15}, 3, 0)
  ebul[#ebul+1] = { n=n, x=x, y=y - 0.6, t=0, zig=zig, spd = 6.5 + math.min(G.wave,6)*0.4 }
end

local function kill_player()
  player.alive = false; player.respawn = 2.2
  local x = player.x
  boom(x, PLAYER_Y, {0.3,1,0.5}, 160, 9); boom(x, PLAYER_Y, {1,0.6,0.1}, 80, 5)
  player.root:set_enabled(false)
  shake = 0.6; sfx("death"); flash.ui = 0.55; flash.uc = {1,0.1,0.2}
  for _, b in ipairs(ebul) do b.n:remove() end; ebul = {}
  G.lives = G.lives - 1; hud_dirty = true
end

local function kill_invader(iv)
  iv.alive = false
  local x, y = inv_pos(iv)
  boom(x, y, iv.color, 90, 7)
  add_score(iv.pts); sfx("hit")
  -- quick death pop via tween scale, then remove
  local root = iv.root; iv.root = nil
  tween.to(v3(1,1,1), v3(1.8,0.05,1.8), 0.15, function(s) root:set_scale(s) end, {})
  G.pending_remove = G.pending_remove or {}
  G.pending_remove[#G.pending_remove+1] = { n=root, t=0.2 }
  shake = math.max(shake, 0.12)
end

-- ---------------------------------------------------------------- update
local function update_formation(dt)
  local alive = alive_count()
  if alive == 0 then return end
  -- interval: faster as invaders die and as waves progress (faithful speed-up)
  local interval = math.max(0.035, (0.05 + 0.75 * (alive / 55)) * (1 - math.min(G.wave-1,5)*0.06))
  formation.step_t = formation.step_t + dt
  if formation.step_t < interval then return end
  formation.step_t = 0
  -- edges
  local minx, maxx, miny = 1e9, -1e9, 1e9
  for _, iv in ipairs(invaders) do if iv.alive then
    local x, y = inv_pos(iv)
    minx = math.min(minx, x - iv.hw); maxx = math.max(maxx, x + iv.hw); miny = math.min(miny, y - iv.hh)
  end end
  local stepx = 0.32
  if (formation.dir > 0 and maxx + stepx > FIELD_W) or (formation.dir < 0 and minx - stepx < -FIELD_W) then
    formation.dir = -formation.dir; formation.y = formation.y - 0.45
  else
    formation.x = formation.x + stepx * formation.dir
  end
  formation.frame = 3 - formation.frame
  sfx("march"..formation.march); formation.march = formation.march % 4 + 1
  for _, iv in ipairs(invaders) do if iv.alive then
    local x, y = inv_pos(iv)
    iv.root:set_position(v3(x, y, 0))
    iv.root:set_rotation(v3(formation.frame == 1 and 8 or -8, formation.dir * 14, 0))
    iv.fa:set_enabled(formation.frame == 1); iv.fb:set_enabled(formation.frame == 2)
    if y - iv.hh < SHIELD_Y + 1.0 then hit_shield(x, y - iv.hh, 0.6, true) end
    if y - iv.hh < PLAYER_Y + 0.3 then G.invaded = true end
  end end
end

local function update_play(dt)
  -- player
  if player.alive then
    local mv = 0
    if vkeys.Left or input.is_key_down("Left") or input.is_key_down("A") then mv = mv - 1 end
    if vkeys.Right or input.is_key_down("Right") or input.is_key_down("D") then mv = mv + 1 end
    player.x = math.max(-FIELD_W + 0.8, math.min(FIELD_W - 0.8, player.x + mv * 9.5 * dt))
    player.root:set_position(v3(player.x, PLAYER_Y, 0))
    player.root:set_rotation(v3(0, 0, -mv * 12))
    local fire = vkeys.Space or input.is_key_down("Space")
    fire = fire or input.is_key_down("Up") or input.is_key_down("W")
    if fire then
      fire_player()
    end
  else
    player.respawn = player.respawn - dt
    if player.respawn <= 0 then
      if G.lives <= 0 then game_over(); return end
      player.alive = true; player.x = 0; player.root:set_enabled(true)
    end
  end

  if G.wave_intro and G.wave_intro > 0 then
    G.wave_intro = G.wave_intro - dt
    if G.wave_intro <= 0 then
      G.marching = true
      if G.jev_error then
        local message = G.jev_error
        G.jev_error = nil
        banner(message, {1, 0.25, 0.5, 1})
      else
        hide_banner()
      end
    end
    return
  end

  if G.req_kill then local k = 0
    for i = #invaders, 1, -1 do local iv = invaders[(i*7) % #invaders + 1]; if iv.alive and k < G.req_kill then kill_invader(iv); k = k + 1 end end
    G.req_kill = nil end
  if player.alive then update_formation(dt) end
  if G.invaded then G.invaded = false; G.lives = 1; kill_player(); return end

  -- player bullet
  if pbul then
    pbul.y = pbul.y + 22 * dt
    pbul.n:set_position(v3(pbul.x, pbul.y, 0))
    particles.emit_burst({ position=v3(pbul.x, pbul.y-0.3, 0.1), velocity=v3(0,-1,0), color_start=vec4(0.6,2.2,2.0,1), color_end=vec4(0.1,0.3,1,0),
      gravity=v3(0,0,0), count=6, size_min=0.03, size_max=0.07, life_min=0.15, life_max=0.35, spawn_radius=0.08, noise_strength=0.8, drag=1 })
    local hit = false
    if pbul.y > TOP_Y + 3 then hit = true end
    if not hit and hit_shield(pbul.x, pbul.y, 0.05, false) then hit = true end
    if not hit then
      for _, iv in ipairs(invaders) do if iv.alive then
        local x, y = inv_pos(iv)
        if math.abs(pbul.x - x) < iv.hw and math.abs(pbul.y - y) < iv.hh + 0.2 then kill_invader(iv); hit = true; break end
      end end
    end
    if not hit and ufo.active and math.abs(pbul.x - ufo.x) < 1.2 and math.abs(pbul.y - ufo.y) < 0.5 then
      local pts = ({50,100,150,300})[math.random(4)]
      add_score(pts); boom(ufo.x, ufo.y, {1,0.2,0.3}, 220, 10); boom(ufo.x, ufo.y, {1,0.9,0.3}, 100, 4)
      shake = 0.35; sfx("explode"); flash.ui = 0.3; flash.uc = {1,0.3,0.4}
      ufo.active = false; ufo.root:set_enabled(false); ufo.timer = 20 + math.random()*10
      G.popup = { x=ufo.x, t=1.2, txt=tostring(pts) }
      hit = true
    end
    if not hit then for i, b in ipairs(ebul) do
      if math.abs(b.x - pbul.x) < 0.2 and math.abs(b.y - pbul.y) < 0.5 then
        boom(b.x, b.y, {1,1,1}, 20, 3); b.n:remove(); table.remove(ebul, i); hit = true; break end
    end end
    if hit then pbul.n:remove(); pbul = nil end
  end

  -- enemy fire
  G.fire_t = (G.fire_t or 0) - dt
  if G.fire_t <= 0 and player.alive and #ebul < 3 + math.min(G.wave, 4) then
    fire_enemy(); G.fire_t = math.max(0.25, 1.1 - G.wave*0.1) * (0.5 + math.random())
  end
  for i = #ebul, 1, -1 do
    local b = ebul[i]
    b.t = b.t + dt; b.y = b.y - b.spd * dt
    local x = b.x + (b.zig and math.sin(b.t*18)*0.12 or 0)
    b.n:set_position(v3(x, b.y, 0)); b.n:set_rotation(v3(0, b.t*600, b.zig and math.sin(b.t*18)*30 or 0))
    local gone = false
    if b.y < PLAYER_Y - 1 then gone = true; boom(x, PLAYER_Y-0.9, {0.3,1,0.5}, 12, 2)
    elseif hit_shield(x, b.y, 0.05, true) then gone = true
    elseif player.alive and math.abs(x - player.x) < 0.75 and math.abs(b.y - PLAYER_Y) < 0.45 then gone = true; kill_player() end
    if gone then b.n:remove(); table.remove(ebul, i) end
  end

  -- UFO
  ufo.timer = ufo.timer - dt
  if not ufo.active and ufo.timer <= 0 and alive_count() > 7 then
    ufo.active = true; ufo.dir = (math.random() < 0.5) and 1 or -1
    ufo.x = -ufo.dir * (FIELD_W + 2); ufo.y = TOP_Y + 1.35
    ufo.root:set_enabled(true); ufo.snd = 0
  end
  if ufo.active then
    ufo.x = ufo.x + ufo.dir * 5.5 * dt
    ufo.root:set_position(v3(ufo.x, ufo.y + math.sin(G.t*4)*0.12, 0))
    ufo.root:set_rotation(v3(0, G.t*140, 0))
    ufo.snd = ufo.snd - dt; if ufo.snd <= 0 then sfx("ufo"); ufo.snd = 0.6 end
    if math.abs(ufo.x) > FIELD_W + 3 then ufo.active = false; ufo.root:set_enabled(false); ufo.timer = 20 + math.random()*10 end
  end

  -- wave cleared
  if alive_count() == 0 and not G.clear_t then
    G.clear_t = 2.0; banner("WAVE CLEAR!", {0.3,1,0.9,1}); sfx("jingle")
    if pbul then pbul.n:remove(); pbul = nil end
  end
  if G.clear_t then
    G.clear_t = G.clear_t - dt
    if G.clear_t <= 0 then
      G.clear_t = nil; G.wave = G.wave + 1; hud_dirty = true
      for _, b in ipairs(ebul) do b.n:remove() end; ebul = {}
      build_shields(); spawn_wave(); banner("WAVE "..G.wave, {1,0.8,0.3,1})
    end
  end
end

local function update(dt)
  dt = math.min(dt, 0.1)
  G.t = G.t + dt
  jev:tick(dt)

  -- twinkle a few stars per frame
  for k = 1, 6 do
    local s = stars[math.random(#stars)]
    local e = s.e * (0.35 + 0.65 * (0.5 + 0.5*math.sin(G.t*s.sp + s.ph)))
    material.set(s.n, "emissive", vec3(s.c[1]*e, s.c[2]*e, s.c[3]*e))
  end

  -- deferred removals
  if G.pending_remove then
    for i = #G.pending_remove, 1, -1 do local r = G.pending_remove[i]; r.t = r.t - dt
      if r.t <= 0 then r.n:remove(); table.remove(G.pending_remove, i) end end
  end

  -- settings: O / Tab or the on-screen button, from the title and pause screens
  local can_settings = (G.state == "menu" or G.state == "pause")
  if not SET:is_open() then
    local u = SW / 1920
    if can_settings then
      local set_x = SW/2 - 150*u
      if G.state == "menu" then
        set_x = SW/2 + 160*u
      end
      quad("set_btn", {x=set_x, y=SH*0.79, w=300*u, h=64*u, label="SETTINGS  (O)", font_scale=2.0,
        fill={0.05,0.1,0.25,0.85}, border={0.2,1,1,1}, text_color={0.85,1,1,1}, corner_radius=16*u, visible=true, z=20})
    else
      quad("set_btn", {x=0,y=0,w=1,h=1, visible=false})
    end
  end
  -- clickable title / pause / game-over buttons (keyboard keys still work)
  local function si_btn(id, label, y, vis, x)
    local u = SW / 1920
    if vis then
      quad(id, {x=x or (SW/2-480*u), y=y, w=300*u, h=64*u, label=label, font_scale=2.0,
        fill={0.05,0.1,0.25,0.85}, border={0.2,1,1,1}, text_color={0.85,1,1,1}, corner_radius=16*u, visible=true, z=20})
      return ((runtime_ui.get_state("hud", id) or {}).clicked) and true or false
    end
    quad(id, {x=0,y=0,w=1,h=1, visible=false}); return false
  end
  local free = not SET:is_open()
  local u = SW / 1920
  local on_menu = free and G.state == "menu"
  local c_start = si_btn("start_btn", "START  (SPACE)", SH*0.79, on_menu)
  local c_jev = si_btn("jev_btn", "JEV", SH*0.79, on_menu, SW/2 - 160*u)
  local c_resume = si_btn("resume_btn", "RESUME  (P)", SH*0.79, free and G.state == "pause")
  local c_again = si_btn("again_btn", "PLAY AGAIN", SH*0.79, free and G.state == "over" and G.over_t > 1.0)
  if c_start or c_again then G.req_start = true end
  local open_set = can_settings and not SET:is_open() and
    (pressed("O") or pressed("Tab") or ((runtime_ui.get_state("hud", "set_btn") or {}).clicked))
  if open_set then
    sfx("hit")
    local st = G.state
    quad("set_btn", {x=0,y=0,w=1,h=1, visible=false}); hide_panel(); hide_banner()
    for _, id in ipairs({ "start_btn", "resume_btn", "again_btn", "jev_btn" }) do
      quad(id, {x=0, y=0, w=1, h=1, visible=false})
    end
    SET:open(function() if st == "menu" then show_menu() else banner("PAUSED", {1,1,1,1}) end end)
  end
  if SET:update(dt) then
    -- settings menu owns input while open
  elseif G.state == "menu" then
    -- attract mode: formation gently bobs
    for _, iv in ipairs(invaders) do if iv.alive and iv.root then
      iv.root:set_position(v3(iv.ox + math.sin(G.t*0.8)*1.5, iv.oy + math.sin(G.t*2 + iv.wob)*0.08, 0)) end end
    if math.floor(G.t*2) ~= G.menu_f then G.menu_f = math.floor(G.t*2)
      for _, iv in ipairs(invaders) do if iv.root then iv.fa:set_enabled(G.menu_f%2==0); iv.fb:set_enabled(G.menu_f%2==1) end end end
    if c_jev then
      G.req_start = nil
      local ok = jev:start()
      if not ok then
        local message = jev:error() or "Jev could not start"
        G.jev_error = message
        banner(message, {1, 0.25, 0.5, 1})
        if type(pe_log) == "function" then
          pe_log(message)
        end
      end
    elseif pressed("Space") or pressed("Return") or G.req_start then
      G.req_start = nil
      jev:begin_human()
      start_game()
    end
  elseif G.state == "play" then
    if pressed("P") or pressed("Escape") then G.state = "pause"; banner("PAUSED", {1,1,1,1}) else update_play(dt) end
  elseif G.state == "pause" then
    if pressed("P") or pressed("Escape") or c_resume then G.state = "play"; hide_banner() end
  elseif G.state == "over" then
    G.over_t = G.over_t + dt
    if G.over_t > 1.0 and (pressed("Space") or pressed("Return") or G.req_start) then
      G.req_start = nil
      jev:begin_human()
      start_game()
    end
  end
  for _, k in ipairs({"Space", "Return", "P", "Escape", "O", "Tab"}) do keys_prev[k] = keydown(k) end

  -- UFO score popup
  if G.popup then G.popup.t = G.popup.t - dt
    local u = SW/1920
    if G.popup.t > 0 then quad("popup", {x=SW/2 - 150*u, y=SH*0.12, w=300*u, h=80*u, label="UFO +"..G.popup.txt, font_scale=2.6, text_color={1,0.3,0.4,1}, visible=true})
    else quad("popup", {x=0,y=0,w=1,h=1,visible=false}); G.popup = nil end
  end

  -- camera: slow drift + shake
  shake = math.max(0, shake - dt*1.5)
  local sk = shake * SET:shake_scale()
  local sx = (math.random()-0.5) * sk * 0.8; local sy = (math.random()-0.5) * sk * 0.8
  local px = (player.x or 0) * 0.08
  cam:set_position(v3(px + sx + math.sin(G.t*0.3)*0.4, -5.5 + sy, 31))
  cam:look_at(v3(px*0.5 + sx*0.5, 0.3 + sy*0.5, 0))

  -- dynamic lights & screen flash
  flash.e = math.max(0, flash.e - dt * 12)
  if LT then pcall(function()
    lights.set_point_light(LT.player, v3(player.x or 0, PLAYER_Y + 0.6, 1.5), v3(0.2,1,0.5), player.alive and 6 or 0, 5)
    lights.set_point_light(LT.formation, v3(formation.x, TOP_Y - 3 + formation.y, 3), v3(1,0.3,0.9), 10, 14)
    lights.set_point_light(LT.flash, v3(flash.x, flash.y, 2), v3(flash.c[1],flash.c[2],flash.c[3]), flash.e * 12, 9)
  end) end
  if THRUST then pcall(function()
    particles.set_emitter(THRUST, { position = v3(player.x or 0, PLAYER_Y - 0.45, 0.1), spawn_rate = player.alive and 120 or 0 })
  end) end
  if flash.ui > 0 then
    flash.ui = math.max(0, flash.ui - dt * 1.5)
    quad("flash", {x=0, y=0, w=SW, h=SH, fill={flash.uc[1],flash.uc[2],flash.uc[3],flash.ui}, no_input=true, visible=flash.ui > 0})
  end
  if hud_dirty then draw_hud() end
end

local function init()
  cam = scene.get_active_camera()
  cam:set_fov(62)
  settings.set("bloom", true)
  settings.set("bloom_strength", 4.5)
  settings.set("bloom_range", 1.25)   -- tap spacing; >1.5 stair-steps (see common/RENDER_SETTINGS.md)
  settings.set("taa", true)
  settings.set("cas_sharpening", false) -- CAS overwrote the bloom when TAA was on (the old "wash out")
  settings.set("motion_blur", false)
  settings.set("tonemapping", true)
  settings.set("fxaa", false)
  settings.set("ssao", false)
  settings.set("IBL_intensity", 0.15)
  pcall(function() lights.set_directional_light(0, vec3(0.3,30,25), vec3(0.55,0.65,1.0), 1.2) end)
  settings.set("ssr", true)
  settings.set("color_grading", true)
  settings.set("color_grading_saturation", 1.3)
  settings.set("color_grading_contrast", 1.12)
  pcall(function()
    for k = 1, 3 do lights.add_point() end
    local n = #lights.get_point_lights()
    LT = { player = n - 3, formation = n - 2, flash = n - 1 }
  end)
  pcall(function()
    THRUST = particles.add_emitter({ name="thrust", position=v3(0,PLAYER_Y-0.45,0.1), velocity=v3(0,-2.5,0),
      color_start=vec4(2.5,1.2,0.3,1), color_end=vec4(1,0.1,0.4,0), gravity=v3(0,0,0), count=200,
      size_min=0.08, size_max=0.2, life_min=0.25, life_max=0.6, spawn_rate=160, spawn_radius=0.18, noise_strength=1.5, drag=0.5 })
  end)
  runtime_ui.show("hud"); runtime_ui.set_screen_overlay("hud", true)
  build_backdrop(); build_player(); build_ufo(); build_shields()
  spawn_wave(); G.marching = true
  draw_hud(); show_menu()
  SET:apply()
end

-- ---------------------------------------------------------------- Jev
local PLAY_KEYS = { "Left", "Right", "A", "D", "Space", "Up", "W" }
local human_was = {}

local function raw_down(key)
  if input.is_key_down_raw then
    return input.is_key_down_raw(key) and true or false
  end
  return input.is_key_down(key) and true or false
end

local function clear_hold()
  vkeys.Left = nil
  vkeys.Right = nil
  vkeys.Space = nil
end

local function human_edge()
  local edge = false
  for i = 1, #PLAY_KEYS do
    local key = PLAY_KEYS[i]
    local down = raw_down(key)
    if down and not human_was[key] then
      edge = true
    end
    human_was[key] = down
  end
  return edge
end

local function seed_human_keys()
  for i = 1, #PLAY_KEYS do
    local key = PLAY_KEYS[i]
    human_was[key] = raw_down(key)
  end
end

local function nearest_invaders(limit)
  local list = {}
  local px = player.x or 0
  for _, iv in ipairs(invaders) do
    if iv.alive then
      local x, y = inv_pos(iv)
      local dx = x - px
      local dy = y - PLAYER_Y
      list[#list + 1] = { x = x, y = y, d = dx * dx + dy * dy }
    end
  end
  table.sort(list, function(a, b)
    return a.d < b.d
  end)
  local out = {}
  local n = math.min(limit, #list)
  for i = 1, n do
    out[i] = { x = list[i].x, y = list[i].y }
  end
  return out
end

local function observe_match()
  local obs = {
    player_x = player.x or 0,
    lives = G.lives,
    score = G.score,
    invaders = nearest_invaders(5),
    shot = pbul ~= nil,
  }
  if pbul then
    obs.shot_x = pbul.x
    obs.shot_y = pbul.y
  end
  return obs
end

local function aim_dx()
  if ufo and ufo.active then
    return ufo.x - player.x
  end
  local best = nil
  local ax = player.x
  for i = 1, #invaders do
    local iv = invaders[i]
    if iv.alive then
      local x, y = inv_pos(iv)
      if not best or y < best then
        best = y
        ax = x
      end
    end
  end
  return ax - player.x
end

local function apply_hold(id)
  clear_hold()
  if id == "left" then
    vkeys.Left = true
  elseif id == "right" then
    vkeys.Right = true
  end
  vkeys.Space = true
end

local function jev_actions()
  local dx = aim_dx()
  if dx > 0.6 then
    return { { id = "right", description = "Fly right. The gun keeps firing.", score = dx } }
  end
  if dx < -0.6 then
    return { { id = "left", description = "Fly left. The gun keeps firing.", score = -dx } }
  end
  return { { id = "stop", description = "Lined up. The gun keeps firing.", score = 1 } }
end

local function reset_match(seed)
  if not player.root then
    return
  end
  clear_hold()
  seed_human_keys()
  if type(seed) == "number" then
    math.randomseed(seed)
  end
  start_game()
end

local jev_source = assert(fs.read("Scripts/jev_auto.lua"), "Missing Jev module: Scripts/jev_auto.lua")
local JevAuto = assert(load(jev_source, "@Scripts/jev_auto.lua", "t", _ENV))()
jev = JevAuto.attach({
  port = 9103,
  id = "neon_invaders",
  description = "Neon Invaders. The offered action is the steer, and the gun keeps firing. Prefer the higher action score.",
  playing = function()
    return player.root ~= nil and (G.state == "play" or G.state == "pause")
  end,
  terminal = function()
    return G.state == "over"
  end,
  score = function()
    return G.score
  end,
  human_edge = human_edge,
  observe = observe_match,
  actions = jev_actions,
  apply = apply_hold,
  reset = reset_match,
  on_human = clear_hold,
})

-- debug/automation handle (used by the MCP screenshot harness)
SI = { G=G, player=player, ufo=ufo, start=function() G.req_start = true end, fire=function() fire_player() end,
  kill=function(n) G.req_kill = n end,
  ufo_now=function() ufo.timer = 0 end, die=function() kill_player() end }
engine.__SI = SI
hooks { init = init, update = update }
