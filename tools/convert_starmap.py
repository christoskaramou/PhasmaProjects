"""EXR -> Radiance .hdr for the engine skybox loader (it loads .hdr, not .exr).

The star map is dim relative to a daylight HDR sky, so pre-boost it here instead of
touching engine exposure. Tune BOOST if stars read too faint or too bright.
"""
import os

os.environ["OPENCV_IO_ENABLE_OPENEXR"] = "1"
import cv2

BOOST = 20.0

TEX = os.path.join(os.path.dirname(__file__), "..", "Assets", "Textures", "Solar")
src = os.path.join(TEX, "starmap_2020_4k.exr")
dst = os.path.join(TEX, "starmap_2020_4k.hdr")

img = cv2.imread(src, cv2.IMREAD_UNCHANGED)
assert img is not None, f"failed to read {src}"
ok = cv2.imwrite(dst, img[:, :, :3].astype("float32") * BOOST)
assert ok, f"failed to write {dst}"
print("wrote", dst, img.shape)
