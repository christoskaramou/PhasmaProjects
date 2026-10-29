# main.pescene: camera + one template node per cooked mesh (one source each -> own material). Game clones via add_mesh_ref.
import json, os, glob
H = os.path.dirname(os.path.abspath(__file__))
D = os.path.join(H, '..', 'project', 'Assets', 'Scenes', 'main.pescene')
names = sorted(os.path.basename(p)[:-4] for p in glob.glob(os.path.join(H, '..', 'meshsrc', '*.obj')))
I = [1.0,0,0,0, 0,1.0,0,0, 0,0,1.0,0, 0,-1000.0,0,1.0]
sc = {'sources': [], 'meshes': [], 'nodes': []}
sc['nodes'].append({'name': 'Camera_0', 'parent': -1, 'local_matrix': [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,60,1],
    'component_flags': 8, 'camera': {'projection': 'perspective', 'fovx': 0.9, 'near_plane': 0.5, 'far_plane': 4000.0, 'speed': 3.5, 'euler': [0.0, 3.14159, 0.0]}})
for s in names:
    sc['sources'].append({'path': f'../Objects/{s}.pemesh'})
    sc['meshes'].append({'source': len(sc['sources']) - 1, 'source_mesh': 0})
    sc['nodes'].append({'name': 'T_' + s, 'parent': -1, 'local_matrix': I, 'component_flags': 0, 'mesh_refs': [len(sc['meshes']) - 1]})
sc['lights'] = []
sc['cameras'] = [{'name': 'Camera_0', 'position': [0, 0, 60], 'euler': [0.0, 3.14159, 0.0], 'fovx': 0.9, 'projection': 'perspective',
                  'near_plane': 0.5, 'far_plane': 4000.0, 'speed': 3.5, 'node_index': 0}]
sc['active_camera'] = 0
sc['scene_scripts'] = {'on_play': ['Assets/Scripts/game.lua']}
json.dump(sc, open(D, 'w'), indent=1)
print(len(names), 'templates')
