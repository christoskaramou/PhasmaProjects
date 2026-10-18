------------------------------------------------------------------ character rigs (part pivots match tools/gen_meshes.py)
local function grp(parent, pos, meshes)
    local g = empty("grp", parent, pos)
    for _, m in ipairs(meshes) do clone(m, vec3(0, 0, 0), nil, g) end
    return g
end
local function build_mario()
    local root = empty("Mario", nil, HIDE)
    local r = { root = root }
    r.torso = grp(root, vec3(0, 0.78, 0), { "m_overalls", "m_shirt", "m_button" })
    r.head = grp(root, vec3(0, 1.42, 0), { "m_skin", "m_hair", "m_eye", "m_cap" })
    r.arm_l = grp(root, vec3(0, 1.32, 0.3), { "m_sleeve", "m_hand" })
    r.arm_r = grp(root, vec3(0, 1.32, -0.3), { "m_sleeve", "m_hand" })
    r.leg_l = grp(root, vec3(0, 0.62, 0.14), { "m_leg", "m_shoe" })
    r.leg_r = grp(root, vec3(0, 0.62, -0.14), { "m_leg", "m_shoe" })
    r.hammer = grp(root, vec3(0.12, 1.25, 0.36), { "hm_handle", "hm_head" })
    r.hammer:set_position(HIDE)
    return r
end
local function build_dk(name)
    local root = empty(name or "Kong", nil, HIDE)
    local r = { root = root }
    r.torso = empty("dk_torso", root, vec3(0, 1.0, 0))
    clone("dk_fur", vec3(0, -1.0, 0), nil, r.torso); clone("dk_chest", vec3(0, -1.0, 0), nil, r.torso)
    r.head = grp(r.torso, vec3(0, 1.7, 0.25), { "dk_headfur", "dk_face", "dk_eyew", "dk_pupil", "dk_mouth", "dk_teeth" })
    r.arm_l = grp(r.torso, vec3(-1.05, 1.35, 0), { "dk_arm_l", "dk_hand_l" })
    r.arm_r = grp(r.torso, vec3(1.05, 1.35, 0), { "dk_arm_r", "dk_hand_r" })
    r.leg_l = grp(root, vec3(-0.55, 1.0, 0), { "dk_leg_l", "dk_foot_l" })
    r.leg_r = grp(root, vec3(0.55, 1.0, 0), { "dk_leg_r", "dk_foot_r" })
    return r
end
local function build_pauline()
    local root = empty("Pauline", nil, HIDE)
    local r = { root = root }
    clone("p_dress", vec3(0, 0, 0), nil, root); clone("p_skin", vec3(0, 0, 0), nil, root); clone("p_shoe", vec3(0, 0, 0), nil, root)
    r.head = grp(root, vec3(0, 1.78, 0), { "p_face", "p_hair", "p_eye", "p_lips" })
    r.arm_l = grp(root, vec3(-0.28, 1.6, 0), { "p_arm" })
    r.arm_r = grp(root, vec3(0.28, 1.6, 0), { "p_arm" })
    return r
end
local function rig_pool(n, meshes)
    local p = {}
    for i = 1, n do
        local root = empty("ent", nil, HIDE)
        for _, m in ipairs(meshes) do clone(m, vec3(0, 0, 0), nil, root) end
        p[i] = { root = root, used = false }
    end
    return p
end
local function rig_take(pool)
    for _, r in ipairs(pool) do if not r.used then r.used = true; return r end end
end
local function rig_free(r) if r then r.used = false; r.root:set_position(HIDE) end end
local RIGS = {}
local function build_rigs()
    RIGS.mario = build_mario()
    RIGS.dk = build_dk("Kong")
    RIGS.pauline = build_pauline()
    RIGS.barrel = rig_pool(14, { "b_wood", "b_hoop" })
    RIGS.bbarrel = rig_pool(8, { "bb_wood", "bb_hoop" })
    RIGS.stack = rig_pool(4, { "b_wood", "b_hoop" })
    RIGS.fire = rig_pool(6, { "fb_body", "fb_eye", "fb_pupil" })
    RIGS.fox = rig_pool(6, { "ff_body", "fb_eye", "fb_pupil" })
    RIGS.pie = rig_pool(8, { "pie_tray", "pie_cement" })
    RIGS.spring = rig_pool(6, { "spring" })
    RIGS.heart = clone("heart"); RIGS.heart_l = clone("heart_l"); RIGS.heart_r = clone("heart_r")
    RIGS.hh = {}
    for i = 1, 4 do RIGS.hh[i] = build_dk("KongHH" .. i) end
end
local function V(x, y, z) return vec3(x, y, z) end
-- pose helpers (angles in degrees)
local function pose_mario(r, o)
    r.root:set_position(o.pos); r.root:set_rotation(V(o.rx or 0, o.yaw or 0, o.rz or 0)); r.root:set_scale(V(o.s or 1, o.s or 1, o.s or 1))
    r.leg_l:set_rotation(V(o.lx or 0, 0, o.ll or 0)); r.leg_r:set_rotation(V(-(o.lx or 0), 0, o.lr or 0))
    r.arm_l:set_rotation(V(o.ax or 0, 0, o.al or 0)); r.arm_r:set_rotation(V(-(o.ax or 0), 0, o.ar or 0))
    r.head:set_rotation(V(0, o.hy or 0, o.hz or 0))
    r.torso:set_rotation(V(0, 0, o.tz or 0))
    if o.ham then r.hammer:set_position(V(0.12, 1.25, 0.36)); r.hammer:set_rotation(V(0, 0, o.ham)) else r.hammer:set_position(HIDE) end
end
local function pose_dk(r, o)
    r.root:set_position(o.pos); r.root:set_rotation(V(o.rx or 0, o.yaw or 0, o.rz or 0)); r.root:set_scale(V(o.s or 1, (o.s or 1) * (o.sy or 1), o.s or 1))
    r.torso:set_position(V(0, 1.0 + (o.bob or 0), 0)); r.torso:set_rotation(V(o.lean or 0, o.ty or 0, 0))
    r.arm_l:set_rotation(V(o.alx or 0, 0, o.alz or 0)); r.arm_r:set_rotation(V(o.arx or 0, 0, o.arz or 0))
    r.leg_l:set_rotation(V(o.llx or 0, 0, o.llz or 0)); r.leg_r:set_rotation(V(o.lrx or 0, 0, o.lrz or 0))
    r.head:set_rotation(V(o.hx or 0, o.hy or 0, o.hz or 0))
end
local function pose_pauline(r, o)
    local s = 1.12
    r.root:set_position(o.pos); r.root:set_rotation(V(o.rx or 0, o.yaw or 0, o.rz or 0)); r.root:set_scale(V(s, s, s))
    r.arm_l:set_rotation(V(o.alx or 0, 0, o.alz or 0)); r.arm_r:set_rotation(V(o.arx or 0, 0, o.arz or 0))
    r.head:set_rotation(V(0, o.hy or 0, o.hz or 0))
end
