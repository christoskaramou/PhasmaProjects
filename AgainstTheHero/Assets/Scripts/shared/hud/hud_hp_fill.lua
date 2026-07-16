-- Attached to the authored "HUD HP Fill" panel (the colored bar drawn over its
-- dark "HUD HP BG" sibling). Width always tracks the BG sibling so full HP fills
-- the bar at any authored size / surface scale; X shrinks toward the left edge.

hooks {
    update = function()
        local bg = scene and scene.find_model and scene.find_model("HUD HP BG")
        local full_w, full_h = 920.0, 64.0
        if bg and bg.get_scale then
            local s = bg:get_scale()
            if s and s.x and s.x > 0 then full_w = s.x end
            if s and s.y and s.y > 0 then full_h = s.y end
        end

        local D = _G.ATH_ACTIVE_DUEL
        local hero = D and D.hero
        local ratio = 1.0
        if hero and hero.hp_max and hero.hp_max > 0 then
            ratio = math.max(0.0, math.min(1.0, (hero.hp or 0) / hero.hp_max))
        end

        -- Fill width = BG width * HP%. Keep left edge glued to BG's left
        -- (BG is center-anchored at tx=0; fill is left-pivoted).
        self:set_scale(vec3(full_w * ratio, full_h, 1.0))
        if self.set_position and self.get_position then
            local p = self:get_position()
            self:set_position(vec3(-full_w * 0.5, p.y, p.z))
        end
    end,
}
