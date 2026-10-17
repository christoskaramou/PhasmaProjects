# Writes project/Assets/Scenes/main.pescene: camera + template nodes (one mesh source per template so every
# template owns its material). The game clones templates with add_mesh_ref.
import json, os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets', 'Scenes', 'main.pescene')
T = []
FP = ['body', 'metal', 'accent', 'glass', 'glow']
for v in ('fighter', 'cap'):                      # player fighter + red captured fighter
    for p in FP: T.append((f'T_{v}_{p}', f'fighter_{p}'))
ENEMY = {'bee': ['body', 'accent', 'eye', 'wing', 'wingR'],
         'bfly': ['body', 'accent', 'eye', 'wing', 'wingR', 'wingtrim', 'wingtrimR'],
         'boss': ['body', 'accent', 'eye', 'wing', 'wingR']}
for v, src in (('bee', 'bee'), ('bfly', 'bfly'), ('boss', 'boss'), ('boss2', 'boss')):
    for p in ENEMY[src]: T.append((f'T_{v}_{p}', f'{src}_{p}'))
T += [('T_bolt', 'bolt'), ('T_ebolt', 'ebolt'), ('T_beam', 'beam'), ('T_beam2', 'beam2'), ('T_planet', 'planet'), ('T_planetring', 'planetring'),
      ('T_badge_pole', 'badge_pole')]
for i in range(6): T += [(f'T_beamring_{i}', 'beamring')]
for i in range(3): T += [(f'T_star_{i}', 'star')]
for i in range(6): T += [(f'T_shard_{i}', 'shard')]
for i in range(8): T += [(f'T_ring_{i}', 'ring')]
for i in range(6): T += [(f'T_orb_{i}', 'orb')]
for i in range(6): T += [(f'T_flag_{i}', 'badge_flag'), (f'T_stripe_{i}', 'badge_stripe')]
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
