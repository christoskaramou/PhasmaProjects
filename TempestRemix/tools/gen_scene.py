# Writes main.pescene with camera + template nodes (one mesh source per template)
import json, os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets', 'Scenes')
os.makedirs(D, exist_ok=True)
OUT = os.path.join(D, 'main.pescene')
T = []
# player claw parts
for p in ('body', 'prong', 'prongR', 'glow', 'metal'):
    T.append((f'T_claw_{p}', f'claw_{p}'))
# enemies
for kind, parts in (
    ('flipper', ('body', 'edge')),
    ('tanker', ('body', 'armor')),
    ('spiker', ('body', 'ring')),
    ('fuseball', ('core', 'tendril')),
    ('pulsar', ('body', 'glow')),
):
    for p in parts:
        T.append((f'T_{kind}_{p}', f'{kind}_{p}'))
# props / FX (multiple templates so each owns a material)
T += [('T_spike', 'spike'), ('T_bolt', 'bolt'), ('T_hub', 'hub'), ('T_hub2', 'hub')]
for i in range(180):
    T.append((f'T_rail_{i}', 'rail'))
for i in range(180):
    T.append((f'T_railg_{i}', 'rail_glow'))
for i in range(96):
    T.append((f'T_node_{i}', 'node'))
for i in range(12):
    T.append((f'T_shard_{i}', 'shard'))
for i in range(10):
    T.append((f'T_ring_{i}', 'ring'))
for i in range(8):
    T.append((f'T_orb_{i}', 'orb'))
# enemy pool templates (extra copies for material variants if needed)
for i in range(8):
    T.append((f'T_bolt_{i}', 'bolt'))
for i in range(16):
    T.append((f'T_spike_{i}', 'spike'))

I = [1.0,0,0,0, 0,1.0,0,0, 0,0,1.0,0, 0,-1000.0,0,1.0]
sc = {'sources': [], 'meshes': [], 'nodes': []}
sc['nodes'].append({
    'name': 'Camera_0', 'parent': -1,
    'local_matrix': [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,18,1],
    'component_flags': 8,
    'camera': {'projection': 'perspective', 'fovx': 0.95, 'near_plane': 0.2, 'far_plane': 400.0,
               'speed': 3.5, 'euler': [0.0, 3.14159, 0.0]}
})
for name, s in T:
    sc['sources'].append({'path': f'../Objects/{s}.pemesh'})
    sc['meshes'].append({'source': len(sc['sources']) - 1, 'source_mesh': 0})
    sc['nodes'].append({'name': name, 'parent': -1, 'local_matrix': I, 'component_flags': 0,
                        'mesh_refs': [len(sc['meshes']) - 1]})
sc['lights'] = []
sc['cameras'] = [{'name': 'Camera_0', 'position': [0, 0, 18], 'euler': [0.0, 3.14159, 0.0],
                  'fovx': 0.95, 'projection': 'perspective', 'near_plane': 0.2, 'far_plane': 400.0,
                  'speed': 3.5, 'node_index': 0}]
sc['active_camera'] = 0
sc['scene_scripts'] = {'on_play': ['Assets/Scripts/game.lua']}
json.dump(sc, open(OUT, 'w'), indent=1)
print(len(T), 'templates')
