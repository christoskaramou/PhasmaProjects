"""The engine's tone map (PhasmaEngine Runtime/RuntimeAssets/Shaders/Tonemap/Tonemap.hlsl ACESFitted, TonemapPS.hlsl)
and its inverse, so baked (display-referred) pictures can be fed to the engine as emissive and come out unchanged.
HLSL mul(color, M) with M written row by row = numpy color @ M."""
import numpy as np

IN = np.array([[0.59719, 0.07600, 0.02840], [0.35458, 0.90834, 0.13383], [0.04823, 0.01566, 0.83777]])
OUT = np.array([[1.60475, -0.10208, -0.00327], [-0.53108, 1.10813, -0.07276], [-0.07367, -0.00605, 1.07602]])
IN_INV, OUT_INV = np.linalg.inv(IN), np.linalg.inv(OUT)


def srgb_to_lin(c):
    c = np.asarray(c, float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.maximum(np.asarray(c, float), 0)
    return np.where(c < 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def aces(x):
    v = np.asarray(x, float) @ IN
    a = v * (v + 0.0245786) - 0.000090537
    b = v * (0.983729 * v + 0.4329510) + 0.238081
    return np.clip((a / b) @ OUT, 0, 1)


def inv_aces(y):
    """Linear scene value x with aces(x) = y (y linear display, 0..~0.99)."""
    w = np.clip(np.asarray(y, float) @ OUT_INV, 0, 1.0)
    w = np.minimum(w, 1.0)
    A = 0.983729 * w - 1.0
    B = 0.4329510 * w - 0.0245786
    C = 0.238081 * w + 0.000090537
    disc = np.maximum(B * B - 4 * A * C, 0)
    v = (-B - np.sqrt(disc)) / (2 * A)
    return np.maximum(v @ IN_INV, 0)


def emissive_factor(display_srgb):
    """Flat material emissive (the engine decodes factors as sRGB, SrgbToLinearHdr) that lands on display_srgb after ACES."""
    x = inv_aces(srgb_to_lin(display_srgb))
    peak = max(1.0, float(np.max(x)))
    return [round(float(c), 4) for c in lin_to_srgb(x / peak) * peak]


if __name__ == "__main__":
    for d in ([0.282, 0.18, 0.086], [0.5, 0.4, 0.3], [0.9, 0.7, 0.4]):
        x = inv_aces(srgb_to_lin(d))
        print(d, "->", x.round(4), "-> back", lin_to_srgb(aces(x)).round(4))
