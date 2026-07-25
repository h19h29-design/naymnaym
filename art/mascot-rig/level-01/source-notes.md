# Level 01 mascot rig source

- Immutable source: `NaymNaymLevelUp/Resources/Assets.xcassets/Squirrel_Growth_Level_1.imageset/Squirrel_Growth_Level_1.png`
- SHA-256: `e5469a7652dc91989ddbf6c11ccb6355724fb831b4dac90ee66f249939882cfa`
- Canvas: 1254 × 1254 RGBA
- Identity lock: the face, proportions, orange/cream fur, green scarf, and sprout are copied from source pixels without repainting.
- Method: `build_rig.py` assigns every non-transparent source pixel to one semantic part exactly once. Covered eye, mouth, and shoulder pixels receive deterministic texture-preserving underpainting only where an opaque source part covers them at rest.
- Expressions: rest uses the original open eyes and smile; blink uses closed eyelid strokes and a neutral mouth on the same face anchors.
- Celebration pose: left/right arms rotate +12°/−12°, tail rotates +8°, and body scales to 1.04×/0.96×. The acceptance preview applies those exact transforms through 24 px feathered skinning weights so rigid crop edges never become visible.
- Rebuild dependencies: Python 3, Pillow, NumPy, and OpenCV. Output is deterministic for the immutable source checksum above.
- Image generation: not used. The immutable source contains all visible art needed, so deterministic raster segmentation avoids identity drift.
