# Level 01 mascot rig source

- Immutable source: `NaymNaymLevelUp/Resources/Assets.xcassets/Squirrel_Growth_Level_1.imageset/Squirrel_Growth_Level_1.png`
- SHA-256: `e5469a7652dc91989ddbf6c11ccb6355724fb831b4dac90ee66f249939882cfa`
- Canvas: 1254 × 1254 RGBA
- Identity lock: rest preserves the exact face, proportions, orange/cream fur, green scarf, and sprout pixels.
- Method: `build_rig.py` assigns every non-transparent source pixel to one semantic part exactly once. Covered shoulder pixels receive deterministic underpainting only where an opaque source part covers them at rest.
- Approved eye underpaint: `eyes-underpaint-approved.png`, SHA-256 `d3223845fa09a517b07cce2a4354ad8335458297f4cea32d22f21c66a25fbcd8`. This immutable, checksum-verified RGBA patch preserves the controller-approved hidden eye pixels without an OpenCV runtime dependency.
- Expression source: built-in ImageGen edit `eyes-closed-imagegen-source.png`, SHA-256 `834f4187d55dc02b707e548692759018a470bc33989780a0ffd08e077ea35c08`.
- ImageGen prompt: preserve the exact mascot identity, proportions, pose, palette, scarf, sprout, cheeks, eyebrows, and transparent canvas; change only both eyes to polished gently closed eyelids and the open mouth to a small closed neutral smile; no teeth, tongue, cavity, blur, wedges, bands, seams, or rectangles.
- Expression localization: both closed-eye layers and the central nose/muzzle/mouth layer come from that single coherent generated source with one shared RGB adjustment. Only two feathered eye ellipses and one overlapping feathered central-face polygon are accepted; every generated pixel outside those ROIs is discarded.
- Expressions: rest uses exact original open eyes and smile; blink uses the localized coherent closed-eye, generated nose, and neutral-mouth ROIs. Original eyebrow pixels remain unchanged.
- Celebration pose: left/right arms rotate +12°/−12°, tail rotates +8°, and body scales to 1.04×/0.96×. The acceptance preview applies those exact transforms through 24 px feathered skinning weights so rigid crop edges never become visible.
- Rebuild dependencies: Python 3 plus the exact Pillow and NumPy versions pinned in `requirements.txt`. No OpenCV runtime is required. A missing or mismatched dependency stops before any output is written and prints the installation command; the build never downloads or installs packages itself.
- Rebuild setup:
  `python3 -m venv /tmp/nyamnyam-mascot-rig && /tmp/nyamnyam-mascot-rig/bin/python -m pip install -r art/mascot-rig/level-01/requirements.txt`
- Rebuild command: `/tmp/nyamnyam-mascot-rig/bin/python art/mascot-rig/level-01/build_rig.py`
- ImageGen background and non-ROI identity drift are never accepted into the rig. Dark, light, and checker 1:1 face crops verify the localized transparency boundaries.
