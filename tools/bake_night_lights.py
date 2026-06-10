"""Threshold the SSS Earth nightmap so only city lights survive as emissive.

The raw 2k_earth_nightmap.jpg has dark-blue oceans/land (~RGB 8-20); at emissive
factor 5 that floor tints the whole night side blue. Zero everything below the
city-light threshold and ease the rest in, so the dark side stays black.
"""
import os

import numpy as np
from PIL import Image

TEX = os.path.join(os.path.dirname(__file__), "..", "Assets", "Textures", "Solar")
img = np.array(Image.open(os.path.join(TEX, "2k_earth_nightmap.jpg")).convert("RGB")).astype(np.float32)

lum = img.mean(axis=2)
THRESHOLD = 35.0     # below: not a city light, zero it
SOFT = 25.0          # ease-in band above the threshold
mask = np.clip((lum - THRESHOLD) / SOFT, 0.0, 1.0)

out = (img * mask[..., None]).clip(0, 255).astype(np.uint8)
Image.fromarray(out, "RGB").save(os.path.join(TEX, "night_lights.png"))
print("wrote night_lights.png; kept", round(float((mask > 0).mean()) * 100.0, 1), "% of pixels")
