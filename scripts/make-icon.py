#!/usr/bin/env python3
"""Generates Resources/Curtain.icon ("light seam"): the whole icon is a closed dark curtain and an
S-shaped seam of light runs through it — the screen is covered, the agent behind it keeps working.

Geometry:
  seam centre   x_c(t) = 512 + S·sin(π(2t − ½)),  y = −40 + 1104·t
  seam width    w(t)   = W·sin(πt)^0.8            (lens: pointed ends, widest in the middle)
  folds         offset curves x_c(t) ± d whose sway shrinks with distance: S·(1 − d/D)
Light: multi-band halo with falling opacity (a blur without filters), warm rims along the seam,
folds nearest the seam tinted warm.
"""
import json, math, pathlib, sys

ICON = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "Resources/Curtain.icon")
S, W, D = 64, 28, 640          # seam sway, seam half-width, distance at which folds are straight
FOLDS = (96, 196, 306, 424)    # fold offsets from the seam centre

def y_of(t): return -40 + 1104 * t
def sway(t, amp): return amp * math.sin(math.pi * (2 * t - 0.5))
def lens(t, w): return w * math.sin(math.pi * t) ** 0.8
def poly(pts): return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"
def band(offset, half, amp, taper=True, n=120):
    """Closed band around the curve x = 512 + offset + sway(t, amp)."""
    left, right = [], []
    for k in range(n + 1):
        t = k / n; x = 512 + offset + sway(t, amp); w = lens(t, half) if taper else half
        left.append((x - w, y_of(t))); right.append((x + w, y_of(t)))
    return poly(left + right[::-1])
def svg(body, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs>{defs}</defs>{body}</svg>\n')

LIGHT = ('<linearGradient id="light" x1="0" y1="0" x2="0" y2="1">'
         '<stop offset="0" stop-color="#FFD978"/><stop offset="0.5" stop-color="#FF8A5B"/>'
         '<stop offset="1" stop-color="#FF3F86"/></linearGradient>')

# Folds: soft cylindrical bands (transparent → lighter → transparent across the band).
fold_defs = ""
folds = ""
for i, d in enumerate(FOLDS):
    amp = S * (1 - d / D)
    warmth = max(0.0, 1 - d / 330)                      # folds near the seam catch the light
    r = round(0x2B + (0x5A - 0x2B) * warmth); g = round(0x27 + (0x2C - 0x27) * warmth); b = round(0x3A + (0x3E - 0x3A) * warmth)
    color = f"#{r:02X}{g:02X}{b:02X}"
    fold_defs += (f'<linearGradient id="f{i}" x1="0" y1="0" x2="1" y2="0">'
                  f'<stop offset="0" stop-color="{color}" stop-opacity="0"/><stop offset="0.55" stop-color="{color}" stop-opacity="0.95"/>'
                  f'<stop offset="1" stop-color="{color}" stop-opacity="0"/></linearGradient>')
    for sign in (-1, 1):
        folds += f'<path d="{band(sign * d, 40, amp, taper=False)}" fill="url(#f{i})"/>'

halo = "".join(f'<path d="{band(0, w, S)}" fill="url(#light)" opacity="{o}"/>'
               for w, o in ((210, 0.06), (150, 0.09), (104, 0.13), (70, 0.2), (48, 0.3)))
rims = "".join(f'<path d="{band(sign * (W + 9), 4, S)}" fill="url(#light)" opacity="0.75"/>' for sign in (-1, 1))
seam = f'<path d="{band(0, W, S)}" fill="url(#light)"/><path d="{band(0, W * 0.32, S)}" fill="#FFF3DA" opacity="0.85"/>'

assets = ICON / "Assets"; assets.mkdir(parents=True, exist_ok=True)
for old in assets.glob("*.svg"): old.unlink()
(assets / "folds.svg").write_text(svg(folds, fold_defs))
(assets / "halo.svg").write_text(svg(halo + rims, LIGHT))
(assets / "seam.svg").write_text(svg(seam, LIGHT))

def p3(h):
    h = h.lstrip("#"); r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"display-p3:{r:.5f},{g:.5f},{b:.5f},1.00000"
def group(name, shadow="none", opacity=0.0):
    return {"name": name, "layers": [{"name": name, "image-name": f"{name}.svg", "glass": False}],
            "shadow": {"kind": shadow, "opacity": opacity}, "specular": False}
icon = {"fill": {"linear-gradient": [p3("#1C1828"), p3("#060509")]},
        "groups": [group("seam", "layer-color", 0.4), group("halo"), group("folds")],
        "supported-platforms": {"squares": ["macOS"]}}
(ICON / "icon.json").write_text(json.dumps(icon, indent=2) + "\n")
print(f"wrote {ICON}")
