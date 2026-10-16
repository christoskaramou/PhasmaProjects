# Writes main.pescene: camera + template nodes (one mesh source per template = own material).
import json, os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets', 'Scenes', 'main.pescene')
os.makedirs(os.path.dirname(D), exist_ok=True)
templates = []
# paddles: L/R colour slots + spare glow variants
for side in ('L', 'R'):
    templates += [(f'T_paddle_{side}', 'paddle_body'), (f'T_pface_{side}', 'paddle_face'), (f'T_pedge_{side}', 'paddle_edge')]
templates += [('T_ball', 'ball'), ('T_ball_core', 'ball_core'), ('T_ghost', 'ball')]
templates += [('T_rail', 'rail'), ('T_rail_glow', 'rail_glow'), ('T_floor', 'floor')]
for i in range(12): templates.append((f'T_marker_{i}', 'marker'))
for i in range(8): templates.append((f'T_ring_{i}', 'ring'))
for i in range(10): templates.append((f'T_shard_{i}', 'shard'))
for i in range(6): templates.append((f'T_pip_{i}', 'pip'))
I = [1.0,0,0,0, 0,1.0,0,0, 0,0,1.0,0, 0,-1000.0,0,1.0]
sc = {'sources': [], 'meshes': [], 'nodes': []}
sc['nodes'].append({'name': 'Camera_0', 'parent': -1, 'local_matrix': [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,48,1],
    'component_flags': 8, 'camera': {'projection': 'perspective', 'fovx': 0.95, 'near_plane': 0.5, 'far_plane': 400.0, 'speed': 3.5, 'euler': [0.0, 3.14159, 0.0]}})
for name, s in templates:
    sc['sources'].append({'path': f'../Objects/{s}.pemesh'})
    sc['meshes'].append({'source': len(sc['sources']) - 1, 'source_mesh': 0})
    sc['nodes'].append({'name': name, 'parent': -1, 'local_matrix': I, 'component_flags': 0, 'mesh_refs': [len(sc['meshes']) - 1]})
sc['lights'] = []
sc['cameras'] = [{'name': 'Camera_0', 'position': [0, 0, 48], 'euler': [0.0, 3.14159, 0.0], 'fovx': 0.95, 'projection': 'perspective',
                  'near_plane': 0.5, 'far_plane': 400.0, 'speed': 3.5, 'node_index': 0}]
sc['active_camera'] = 0
sc['scene_scripts'] = {'on_play': ['Assets/Scripts/game.lua']}
json.dump(sc, open(D, 'w'), indent=1)
print(len(templates), 'templates')
