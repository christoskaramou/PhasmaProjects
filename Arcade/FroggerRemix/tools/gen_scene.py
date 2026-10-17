# Writes project/Assets/Scenes/main.pescene: camera + template nodes referencing cooked meshes.
# Every template gets its OWN source+mesh entry (materials are per mesh); game.lua clones them with add_mesh_ref.
import json, os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets', 'Scenes', 'main.pescene')
T = []  # (template name, mesh file)
for p in ('body', 'belly', 'eye', 'pupil', 'spots', 'legb', 'legf'): T.append((f'T_frog_{p}', f'frog_{p}'))
LANES = {1: 'sedan', 2: 'dozer', 3: 'sedan', 4: 'racer', 5: 'truck'}
for lane, kind in LANES.items():
    parts = ['body', 'glass', 'dark', 'chrome', 'head', 'tail'] + (['trailer'] if kind == 'truck' else [])
    for p in parts: T.append((f'T_L{lane}_{p}', f'{kind}_{p}'))
for s in ('s', 'm', 'l'): T += [(f'T_log_{s}', f'log_{s}'), (f'T_log_{s}_end', f'log_{s}_end')]
for p in ('shell', 'rim', 'body', 'eye'): T.append((f'T_turtle_{p}', f'turtle_{p}'))
T += [('T_lily_pad', 'lily_pad'), ('T_lotus', 'lotus'), ('T_lotus_core', 'lotus_core'), ('T_fly_body', 'fly_body'), ('T_fly_wing', 'fly_wing')]
for e in ('road', 'walk', 'water', 'riverbed', 'grass', 'curb', 'bank_wall', 'hedge', 'bay_stone', 'lamp_pole', 'lamp_bulb', 'tuft'): T.append((f'T_{e}', e))
for b in ('a', 'b', 'c'): T.append((f'T_bldg_{b}', 'bldg'))
T += [('T_refl_lamp', 'refl_lamp'), ('T_refl_moon', 'refl_moon')]
I = [1.0,0,0,0, 0,1.0,0,0, 0,0,1.0,0, 0,-1000.0,0,1.0]
sc = {'sources': [], 'meshes': [], 'nodes': []}
cam = {'projection': 'perspective', 'fovx': 1.0, 'near_plane': 0.3, 'far_plane': 300.0, 'speed': 3.5, 'euler': [0.0, 3.14159, 0.0]}
sc['nodes'].append({'name': 'Camera_0', 'parent': -1, 'local_matrix': [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,14,8,1], 'component_flags': 8, 'camera': cam})
for name, f in T:
    sc['sources'].append({'path': f'../Objects/{f}.pemesh'})
    sc['meshes'].append({'source': len(sc['sources']) - 1, 'source_mesh': 0})
    sc['nodes'].append({'name': name, 'parent': -1, 'local_matrix': I, 'component_flags': 0, 'mesh_refs': [len(sc['meshes']) - 1]})
sc['lights'] = []
sc['cameras'] = [dict(name='Camera_0', position=[0, 14, 8], node_index=0, **cam)]
sc['active_camera'] = 0
sc['scene_scripts'] = {'on_play': ['Assets/Scripts/game.lua']}
json.dump(sc, open(D, 'w'), indent=1)
print(len(T), 'templates')
