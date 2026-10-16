import json, os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets', 'Scenes', 'main.pescene')
templates = []
for i in range(8):
    templates += [(f'T_mush_stem_{i}', 'mush_stem'), (f'T_mush_cap_{i}', 'mush_cap'), (f'T_mush_glow_{i}', 'mush_glow')]
for i in range(4):
    templates += [(f'T_centi_body_{i}', 'centi_body'), (f'T_centi_head_{i}', 'centi_head')]
templates += [
    ('T_blaster', 'blaster'), ('T_blaster_glow', 'blaster'),
    ('T_bullet', 'bullet'), ('T_bullet_glow', 'bullet'),
    ('T_spider', 'spider'), ('T_flea', 'flea'), ('T_scorpion', 'scorpion'),
    ('T_floor', 'floor_tile'), ('T_floor_glow', 'floor_tile'),
    ('T_moss', 'moss_clump'), ('T_leaf', 'leaf'), ('T_spore', 'spore'),
    ('T_shard', 'centi_body'),
]
for i in range(6): templates.append((f'T_leg_{i}', 'centi_leg'))
I = [1.0,0,0,0, 0,1.0,0,0, 0,0,1.0,0, 0,-1000.0,0,1.0]
sc = {'sources': [], 'meshes': [], 'nodes': []}
sc['nodes'].append({'name': 'Camera_0', 'parent': -1, 'local_matrix': [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,8,42,1],
    'component_flags': 8, 'camera': {'projection': 'perspective', 'fovx': 0.85, 'near_plane': 0.5, 'far_plane': 400.0, 'speed': 3.5, 'euler': [0.35, 3.14159, 0.0]}})
for name, s in templates:
    sc['sources'].append({'path': f'../Objects/{s}.pemesh'})
    sc['meshes'].append({'source': len(sc['sources']) - 1, 'source_mesh': 0})
    sc['nodes'].append({'name': name, 'parent': -1, 'local_matrix': I, 'component_flags': 0, 'mesh_refs': [len(sc['meshes']) - 1]})
sc['lights'] = []
sc['cameras'] = [{'name': 'Camera_0', 'position': [0, 8, 42], 'euler': [0.35, 3.14159, 0.0], 'fovx': 0.85, 'projection': 'perspective', 'near_plane': 0.5, 'far_plane': 400.0, 'speed': 3.5, 'node_index': 0}]
sc['active_camera'] = 0
sc['scene_scripts'] = {'on_play': ['Assets/Scripts/game.lua']}
json.dump(sc, open(D, 'w'), indent=1)
print(len(templates), 'templates')
