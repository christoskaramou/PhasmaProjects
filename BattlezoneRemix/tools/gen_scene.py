# main.pescene: camera + template nodes (one mesh source per template)
import json, os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets', 'Scenes', 'main.pescene')
os.makedirs(os.path.dirname(D), exist_ok=True)
T = []
# player tank
for p in ('hull','tread','turret','barrel','hatch','glow'):
    T.append((f'T_player_{p}', f'player_{p}'))
# left/right tread clones share source but separate templates so materials independent if needed
T.append(('T_player_treadR', 'player_tread'))
# enemy
for p in ('hull','tread','turret','barrel','glow'):
    T.append((f'T_enemy_{p}', f'enemy_{p}'))
T.append(('T_enemy_treadR', 'enemy_tread'))
# super
for p in ('hull','tread','turret','barrel','glow'):
    T.append((f'T_super_{p}', f'super_{p}'))
T.append(('T_super_treadR', 'super_tread'))
# saucer / missile / shell
for p in ('body','rim','glow'): T.append((f'T_saucer_{p}', f'saucer_{p}'))
for p in ('body','glow'): T.append((f'T_missile_{p}', f'missile_{p}'))
for p in ('body','glow'): T.append((f'T_shell_{p}', f'shell_{p}'))
# environment
for i in range(4): T.append((f'T_mountain_{i}', f'mountain_{i}'))
for i in range(8): T.append((f'T_ground_{i}', 'ground'))
for i in range(10): T.append((f'T_crater_{i}', 'crater'))
for i in range(12): T.append((f'T_rock_{i}', 'rock'))
for i in range(6): T.append((f'T_pyramid_{i}', 'pyramid'))
for i in range(6): T.append((f'T_block_{i}', 'block'))
for i in range(6): T.append((f'T_shard_{i}', f'shard_{i}'))
for i in range(4): T.append((f'T_ring_{i}', f'ring_{i}'))
for i in range(4): T.append((f'T_orb_{i}', f'orb_{i}'))
T.append(('T_radar', 'radar'))

I = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,-1000,0,1]
sc = {'sources': [], 'meshes': [], 'nodes': []}
# camera elevated looking along +Z initially (game repositions)
sc['nodes'].append({
    'name': 'Camera_0', 'parent': -1,
    'local_matrix': [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,2.2,0,1],
    'component_flags': 8,
    'camera': {'projection': 'perspective', 'fovx': 1.05, 'near_plane': 0.2, 'far_plane': 800.0,
               'speed': 3.5, 'euler': [0.0, 0.0, 0.0]}
})
for name, s in T:
    sc['sources'].append({'path': f'../Objects/{s}.pemesh'})
    sc['meshes'].append({'source': len(sc['sources'])-1, 'source_mesh': 0})
    sc['nodes'].append({'name': name, 'parent': -1, 'local_matrix': I, 'component_flags': 0,
                        'mesh_refs': [len(sc['meshes'])-1]})
sc['lights'] = []
sc['cameras'] = [{'name': 'Camera_0', 'position': [0, 2.2, 0], 'euler': [0,0,0], 'fovx': 1.05,
                  'projection': 'perspective', 'near_plane': 0.2, 'far_plane': 800.0, 'speed': 3.5, 'node_index': 0}]
sc['active_camera'] = 0
sc['scene_scripts'] = {'on_play': ['Assets/Scripts/game.lua']}
json.dump(sc, open(D, 'w'), indent=1)
print(len(T), 'templates')
