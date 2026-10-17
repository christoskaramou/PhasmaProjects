# Writes main.pescene: camera + template nodes (one mesh source per template -> own material). Game clones with add_mesh_ref.
import json, os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets', 'Scenes', 'main.pescene')
T = []
PARTS = {'ship': ['body', 'metal', 'accent', 'glass', 'glow'], 'lander': ['body', 'accent', 'eye', 'glow'], 'mutant': ['body', 'accent', 'eye'],
         'bomber': ['body', 'accent', 'glow'], 'baiter': ['body', 'accent', 'glow'], 'pod': ['body', 'accent'], 'swarmer': ['body', 'glow'],
         'human': ['body', 'visor', 'glow']}
for k, ps in PARTS.items():
    for p in ps: T.append((f'T_{k}_{p}', f'{k}_{p}'))
for s in ['mountain', 'mountain_far', 'crest', 'ground', 'city', 'citywin', 'bullet', 'mine', 'orb', 'planet', 'beam']: T.append((f'T_{s}', s))
for i in range(4): T.append((f'T_laser_{i}', 'laser'))
for i in range(6): T.append((f'T_shard_{i}', 'shard'))
for i in range(8): T.append((f'T_ring_{i}', 'ring'))
for i in range(3): T.append((f'T_star_{i}', 'star'))
I = [1.0,0,0,0, 0,1.0,0,0, 0,0,1.0,0, 0,-1000.0,0,1.0]
sc = {'sources': [], 'meshes': [], 'nodes': []}
sc['nodes'].append({'name': 'Camera_0', 'parent': -1, 'local_matrix': [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,70,1],
    'component_flags': 8, 'camera': {'projection': 'perspective', 'fovx': 0.9, 'near_plane': 0.5, 'far_plane': 1200.0, 'speed': 3.5, 'euler': [0.0, 3.14159, 0.0]}})
for name, s in T:
    sc['sources'].append({'path': f'../Objects/{s}.pemesh'})
    sc['meshes'].append({'source': len(sc['sources']) - 1, 'source_mesh': 0})
    sc['nodes'].append({'name': name, 'parent': -1, 'local_matrix': I, 'component_flags': 0, 'mesh_refs': [len(sc['meshes']) - 1]})
sc['lights'] = []
sc['cameras'] = [{'name': 'Camera_0', 'position': [0, 0, 70], 'euler': [0.0, 3.14159, 0.0], 'fovx': 0.9, 'projection': 'perspective',
                  'near_plane': 0.5, 'far_plane': 1200.0, 'speed': 3.5, 'node_index': 0}]
sc['active_camera'] = 0
sc['scene_scripts'] = {'on_play': ['Assets/Scripts/game.lua']}
json.dump(sc, open(D, 'w'), indent=1)
print(len(T), 'templates')
