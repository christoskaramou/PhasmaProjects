#!/usr/bin/env python3
# Download the Natural Earth layers the map generators need (public domain, ~82 MB unpacked) into <game>/data
# (or the folder given as the first argument / $BB_DATA). Cross-platform: python3 tools/fetch_natural_earth.py
import os, sys, zipfile, urllib.request
LAYERS = ['10m/cultural/ne_10m_admin_0_countries', '10m/cultural/ne_10m_admin_1_states_provinces',
          '10m/physical/ne_10m_lakes', '50m/cultural/ne_50m_admin_0_countries', '50m/physical/ne_50m_land']
BASE = 'https://naciscdn.org/naturalearth/'
here = os.path.dirname(os.path.abspath(__file__))
dest = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.environ.get('BB_DATA') or os.path.join(here, '..', 'data'))
os.makedirs(dest, exist_ok=True)
for lay in LAYERS:
    name = lay.split('/')[-1]; out = os.path.join(dest, name)
    if os.path.isfile(os.path.join(out, name + '.shp')): print('have', name); continue
    z = out + '.zip'; print('get ', BASE + lay + '.zip')
    req = urllib.request.Request(BASE + lay + '.zip', headers={'User-Agent': 'banners-borders-fetch'})
    with urllib.request.urlopen(req) as r, open(z, 'wb') as f: f.write(r.read())
    with zipfile.ZipFile(z) as zf: zf.extractall(out)
    os.remove(z)
print('Natural Earth data ready in', dest)
