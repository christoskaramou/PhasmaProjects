# main.pescene: camera + template nodes (own source entry per template -> own material). Game clones with add_mesh_ref.
import json, os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets', 'Scenes', 'main.pescene')
T = []
for p in ['body', 'belly', 'spikes', 'eye', 'pupil', 'foot']: T.append((f'T_dragon_{p}', f'dragon_{p}'))
for k in ('zen', 'zenA'):
    for p in ['body', 'visor', 'eye', 'feet', 'key']: T.append((f'T_{k}_{p}', f'zen_{p}'))
for k in ('monsta', 'monstaA'):
    for p in ['body', 'eye', 'fin']: T.append((f'T_{k}_{p}', f'monsta_{p}'))
for p in ['body', 'eye', 'brow']: T.append((f'T_baron_{p}', f'baron_{p}'))
for p in ['ring', 'band', 'shell', 'hl']: T.append((f'T_bub_{p}', f'bubble_{p}'))
for i in range(6):
    for p in ['ring', 'shell']: T.append((f'T_lb{i}_{p}', f'bubble_{p}'))
for s in ['cherry', 'cherry_stem', 'peach', 'leaf', 'gem', 'banana', 'backwall']: T.append((f'T_{s}', s))
for i in range(5): T += [(f'T_level{i}', f'level{i}'), (f'T_trim{i}', f'trim{i}')]
for i in range(5): T.append((f'T_star_{i}', 'star'))
for i in range(3): T.append((f'T_orb_{i}', 'orb'))
I = [1.0,0,0,0, 0,1.0,0,0, 0,0,1.0,0, 0,-1000.0,0,1.0]
sc = {'sources': [], 'meshes': [], 'nodes': []}
sc['nodes'].append({'name': 'Camera_0', 'parent': -1, 'local_matrix': [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,13,40,1],
    'component_flags': 8, 'camera': {'projection': 'perspective', 'fovx': 0.9, 'near_plane': 0.5, 'far_plane': 1500.0, 'speed': 3.5, 'euler': [0.0, 3.14159, 0.0]}})
for name, s in T:
    sc['sources'].append({'path': f'../Objects/{s}.pemesh'})
    sc['meshes'].append({'source': len(sc['sources']) - 1, 'source_mesh': 0})
    sc['nodes'].append({'name': name, 'parent': -1, 'local_matrix': I, 'component_flags': 0, 'mesh_refs': [len(sc['meshes']) - 1]})
sc['lights'] = []
sc['cameras'] = [{'name': 'Camera_0', 'position': [0, 13, 40], 'euler': [0.0, 3.14159, 0.0], 'fovx': 0.9, 'projection': 'perspective',
                  'near_plane': 0.5, 'far_plane': 1500.0, 'speed': 3.5, 'node_index': 0}]
sc['active_camera'] = 0
sc['scene_scripts'] = {'on_play': ['Assets/Scripts/game.lua']}
json.dump(sc, open(D, 'w'), indent=1)
print(len(T), 'templates')
