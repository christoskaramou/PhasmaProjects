# Writes project/Assets/Scenes/main.pescene: camera + template nodes (one mesh source per template so each owns
# its material). The game clones templates with add_mesh_ref.
import json, os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets', 'Scenes', 'main.pescene')
T = [('T_cube_body', 'cube_body'), ('T_cube_rim', 'cube_rim'), ('T_top_0', 'cube_top'), ('T_top_1', 'cube_top'), ('T_top_2', 'cube_top'),
     ('T_deco_body', 'cube_body'), ('T_deco_top', 'cube_top'),
     ('T_qb_body', 'qb_body'), ('T_qb_eye', 'qb_eye'), ('T_qb_dark', 'qb_dark'), ('T_qb_feet', 'qb_feet'),
     ('T_ball_red', 'ball'), ('T_ball_green', 'ball_small'), ('T_egg', 'egg'),
     ('T_coily_spring', 'coily_spring'), ('T_coily_head', 'coily_head'), ('T_coily_eye', 'coily_eye'), ('T_coily_dark', 'coily_dark'),
     ('T_slick_body', 'sam_body'), ('T_sam_body', 'sam_body'), ('T_shades', 'sam_shades'),
     ('T_disc_ring', 'disc_ring'), ('T_disc_core', 'disc_core')]
for i in range(8): T.append((f'T_shock_{i}', 'shock'))
for i in range(5): T.append((f'T_shard_{i}', 'shard'))
for i in range(3): T.append((f'T_star_{i}', 'star'))
I = [1.0,0,0,0, 0,1.0,0,0, 0,0,1.0,0, 0,-1000.0,0,1.0]
sc = {'sources': [], 'meshes': [], 'nodes': []}
sc['nodes'].append({'name': 'Camera_0', 'parent': -1, 'local_matrix': [1,0,0,0, 0,1,0,0, 0,0,1,0, 20,20,20,1],
    'component_flags': 8, 'camera': {'projection': 'perspective', 'fovx': 0.6, 'near_plane': 0.5, 'far_plane': 900.0, 'speed': 3.5, 'euler': [0.0, 3.14159, 0.0]}})
for name, s in T:
    sc['sources'].append({'path': f'../Objects/{s}.pemesh'})
    sc['meshes'].append({'source': len(sc['sources']) - 1, 'source_mesh': 0})
    sc['nodes'].append({'name': name, 'parent': -1, 'local_matrix': I, 'component_flags': 0, 'mesh_refs': [len(sc['meshes']) - 1]})
sc['lights'] = []
sc['cameras'] = [{'name': 'Camera_0', 'position': [20, 20, 20], 'euler': [0.0, 3.14159, 0.0], 'fovx': 0.6, 'projection': 'perspective',
                  'near_plane': 0.5, 'far_plane': 900.0, 'speed': 3.5, 'node_index': 0}]
sc['active_camera'] = 0
sc['scene_scripts'] = {'on_play': ['Assets/Scripts/game.lua']}
json.dump(sc, open(D, 'w'), indent=1)
print(len(T), 'templates')
