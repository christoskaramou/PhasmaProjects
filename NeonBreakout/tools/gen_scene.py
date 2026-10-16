# Writes project/Assets/Scenes/main.pescene: camera + template nodes that reference cooked meshes.
# Each template gets its OWN mesh entry (materials are per mesh), the game clones them with add_mesh_ref.
import json, os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets', 'Scenes', 'main.pescene')
srcs = ['brick', 'brick_face', 'paddle_mid', 'paddle_cap', 'rail', 'ball']
VARIANTS = 12   # brick colour slots
templates = []  # (node name, source name)
for i in range(VARIANTS):
    templates += [(f'T_brick_{i}', 'brick'), (f'T_face_{i}', 'brick_face')]
templates += [('T_paddle_mid', 'paddle_mid'), ('T_paddle_cap', 'paddle_cap'), ('T_paddle_strip', 'paddle_mid'),
              ('T_rail', 'rail'), ('T_rail_glow', 'rail'), ('T_ball', 'ball'), ('T_ghost', 'ball'),
              ('T_pu_body', 'paddle_cap'), ('T_shard_0', 'brick'), ('T_floor', 'rail')]
for i in range(1, 8): templates.append((f'T_shard_{i}', 'brick'))
for i in range(6): templates.append((f'T_pu_{i}', 'paddle_cap'))
I = [1.0,0,0,0, 0,1.0,0,0, 0,0,1.0,0, 0,-1000.0,0,1.0]
sc = {'sources': [], 'meshes': [], 'nodes': []}
sc['nodes'].append({'name': 'Camera_0', 'parent': -1, 'local_matrix': [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,-2,40,1],
    'component_flags': 8, 'camera': {'projection': 'perspective', 'fovx': 0.9, 'near_plane': 0.5, 'far_plane': 400.0, 'speed': 3.5, 'euler': [0.0, 3.14159, 0.0]}})
for name, s in templates:
    sc['sources'].append({'path': f'../Objects/{s}.pemesh'})  # one source per template => own mesh + material
    sc['meshes'].append({'source': len(sc['sources']) - 1, 'source_mesh': 0})
    sc['nodes'].append({'name': name, 'parent': -1, 'local_matrix': I, 'component_flags': 0, 'mesh_refs': [len(sc['meshes']) - 1]})
sc['lights'] = []
sc['cameras'] = [{'name': 'Camera_0', 'position': [0, -2, 40], 'euler': [0.0, 3.14159, 0.0], 'fovx': 0.9, 'projection': 'perspective',
                  'near_plane': 0.5, 'far_plane': 400.0, 'speed': 3.5, 'node_index': 0}]
sc['active_camera'] = 0
sc['scene_scripts'] = {'on_play': ['Assets/Scripts/game.lua']}
json.dump(sc, open(D, 'w'), indent=1)
print(len(templates), 'templates')
