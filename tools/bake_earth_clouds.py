"""Convert the SSS Earth cloud map (white-on-black JPG, no alpha) into an RGBA PNG
the alpha_blend material can use: RGB = white, alpha = cloud luminance."""
import os

import numpy as np
from PIL import Image

TEX = os.path.join(os.path.dirname(__file__), "..", "Assets", "Textures", "Solar")
lum = np.array(Image.open(os.path.join(TEX, "2k_earth_clouds.jpg")).convert("L"))

out = np.empty((*lum.shape, 4), dtype=np.uint8)
out[..., :3] = 255
out[..., 3] = lum

Image.fromarray(out, "RGBA").save(os.path.join(TEX, "earth_clouds.png"))
print("wrote earth_clouds.png", out.shape)
