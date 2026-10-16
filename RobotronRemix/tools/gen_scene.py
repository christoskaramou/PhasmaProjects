# Writes project/Assets/Scenes/main.pescene: camera + template nodes (one mesh source per template so each owns its material).
import json, os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets', 'Scenes', 'main.pescene')
T = []
P = {'hero': ['body', 'metal', 'glow'], 'grunt': ['body', 'accent', 'eye'], 'hulk': ['body', 'accent', 'eye'],
     'spheroid': ['core', 'ring'], 'enforcer': ['body', 'fins', 'eye'], 'electrode': ['star', 'core'], 'brain': ['body', 'lobes', 'eye']}
for k, parts in P.items():
    for p in parts: T.append((f'T_{k}_{p}', f'{k}_{p}'))
for v in ('mom', 'dad', 'kid'):
    for p in ('body', 'skin', 'hair'): T.append((f'T_{v}_{p}', f'human_{p}'))
T += [('T_bolt', 'bolt'), ('T_orb', 'orb'), ('T_floor', 'tile'), ('T_floor2', 'tile'), ('T_rail', 'rail'), ('T_rail2', 'rail')]
for i in range(6): T += [(f'T_shard_{i}', 'shard')]
for i in range(8): T += [(f'T_ring_{i}', 'ring')]
I = [1.0,0,0,0, 0,1.0,0,0, 0,0,1.0,0, 0,-1000.0,0,1.0]
sc = {'sources': [], 'meshes': [], 'nodes': []}
sc['nodes'].append({'name': 'Camera_0', 'parent': -1, 'local_matrix': [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,70,1],
    'component_flags': 8, 'camera': {'projection': 'perspective', 'fovx': 0.9, 'near_plane': 0.5, 'far_plane': 900.0, 'speed': 3.5, 'euler': [0.0, 3.14159, 0.0]}})
for name, s in T:
    sc['sources'].append({'path': f'../Objects/{s}.pemesh'})
    sc['meshes'].append({'source': len(sc['sources']) - 1, 'source_mesh': 0})
    sc['nodes'].append({'name': name, 'parent': -1, 'local_matrix': I, 'component_flags': 0, 'mesh_refs': [len(sc['meshes']) - 1]})
sc['lights'] = []
sc['cameras'] = [{'name': 'Camera_0', 'position': [0, 0, 70], 'euler': [0.0, 3.14159, 0.0], 'fovx': 0.9, 'projection': 'perspective',
                  'near_plane': 0.5, 'far_plane': 900.0, 'speed': 3.5, 'node_index': 0}]
sc['active_camera'] = 0
sc['scene_scripts'] = {'on_play': ['Assets/Scripts/game.lua']}
json.dump(sc, open(D, 'w'), indent=1)
print(len(T), 'templates')
