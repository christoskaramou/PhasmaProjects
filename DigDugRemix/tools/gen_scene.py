# main.pescene: camera + template nodes (one mesh source per template -> own material). Game clones them.
import json, os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets', 'Scenes', 'main.pescene')
T = []
for p in ('suit', 'trim', 'visor', 'gun'): T.append((f'T_dig_{p}', f'dig_{p}'))
for p in ('body', 'lens', 'rim', 'feet'): T.append((f'T_pooka_{p}', f'pooka_{p}'))
for p in ('body', 'belly', 'wing', 'eye', 'pupil', 'feet'): T.append((f'T_fygar_{p}', f'fygar_{p}'))
for s in range(4):
    for v in range(3): T.append((f'T_dirt_{s}_{v}', f'dirt{v}'))
    T.append((f'T_pebble_{s}', 'pebble'))
for n in ('rock', 'rock_crack', 'hose', 'harpoon', 'flame', 'flame_core', 'fl_stem', 'fl_petal', 'fl_center', 'grass',
          'carrot', 'carrot_top', 'mush_cap', 'mush_stem', 'orb'): T.append((f'T_{n}', n))
for i in range(7): T.append((f'T_shard_{i}', 'shard'))
for i in range(3): T.append((f'T_gem_{i}', 'gem'))
for i in range(8): T.append((f'T_ring_{i}', 'ring'))
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
