# Writes project/Assets/Scenes/main.pescene: camera + sun + one template node per cooked part (T_<name>).
# Every template has its own source/mesh entries (materials are per mesh); game.lua clones them with add_mesh_ref.
import json, os, re
H = os.path.dirname(os.path.abspath(__file__))
D = os.path.join(H, '..', 'project', 'Assets', 'Scenes', 'main.pescene')
counts = {}
for ln in open(os.path.join(H, 'cook.log')):
    m = re.search(r'Cooked (\d+) meshes.*Objects/(\w+)\.pemesh', ln)
    if m: counts[m.group(2)] = int(m.group(1))
I = [1.0,0,0,0, 0,1.0,0,0, 0,0,1.0,0, 0,-1000.0,0,1.0]
sc = {'sources': [], 'meshes': [], 'nodes': []}
cam = {'projection': 'perspective', 'fovx': 1.1, 'near_plane': 0.3, 'far_plane': 400.0, 'speed': 0.0, 'euler': [0.9, 3.14159, 0.0]}
sc['nodes'].append({'name': 'Camera_0', 'parent': -1, 'local_matrix': [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,14,10,1], 'component_flags': 8, 'camera': cam})
for name in sorted(counts):
    sc['sources'].append({'path': f'../Objects/{name}.pemesh'})
    refs = []
    for k in range(counts[name]):
        refs.append(len(sc['meshes'])); sc['meshes'].append({'source': len(sc['sources']) - 1, 'source_mesh': k})
    sc['nodes'].append({'name': 'T_' + name, 'parent': -1, 'local_matrix': I, 'component_flags': 0, 'mesh_refs': refs})
sc['lights'] = []
sc['cameras'] = [dict(name='Camera_0', position=[0, 14, 10], node_index=0, **cam)]
sc['active_camera'] = 0
sc['scene_scripts'] = {'on_play': ['Assets/Scripts/game.lua']}
json.dump(sc, open(D, 'w'), indent=1)
print(len(counts), 'templates', len(sc['meshes']), 'meshes')
