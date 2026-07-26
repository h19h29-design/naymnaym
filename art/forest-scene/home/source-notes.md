# Living Forest Scene — source and production notes

## Approved visual sources

| Role | Original path | Dimensions | SHA-256 |
| --- | --- | ---: | --- |
| Portrait light, atmosphere, palette | `NaymNaymLevelUp/Resources/Assets.xcassets/Squirrel_Intro_Background.imageset/Squirrel_Intro_Background.png` | 853×1844 RGB | `954f62cb4c5989d0acb24e63f731025746d9bac09266a9905def32dabd4dc365` |
| Home composition, foliage language | `NaymNaymLevelUp/Resources/Assets.xcassets/Squirrel_Home_Background.imageset/Squirrel_Home_Background.png` | 1672×941 RGB | `94566b4593a99918d79c5f2cac1927714474c47afeadb842ade48e66e80d0ee7` |

Immutable copies live at `references/intro.png` and `references/home.png`.
The byte-identical `docs/design-concepts/2026-07-25-major-renewal/forest-home.png`
copy was not treated as an additional source.

## Generation path

The production backplate and four overlay cutouts were created with the built-in
ImageGen tool. No CLI/API fallback was used.

| Layer source | Built-in output | Source dimensions | Source SHA-256 |
| --- | --- | ---: | --- |
| `sky` | `call_JiGrWj9VZa7VZGrhemGUcocJ.png` | 852×1846 RGB | `2271c37bf1fd7f84d8a5da4168a5cf6b999a9f59ca27c501d17da8d883bacafa` |
| `distantTrees` | `call_xR0YoTPmnNMog6sV5EMLCIRq.png` | 851×1847 RGB chroma source | `afdc05a7bb853d2106385a4a709d857416edf92c9cf90116f0586501c275b1ae` |
| `midgroundTrees` | `call_0bfaYee38wxMRp6Px5MGkLQl.png` | 853×1844 RGB chroma source | `48da2cc9d757b9754b40d30fcbfd8cdf5073896c52d2ec1004a995ea7a8f773d` |
| `foregroundLeaves` | `call_PKjh0RJedNhODH4Kpj8wMA3i.png` | 851×1847 RGB chroma source | `b22f9007a11cb92347e2f165ef3bbff8cff5bcda06c446d6f911d370b99dcfe0` |
| `ground` | `call_SLF1RmCdVaicdIA1v8lnJzfe.png` | 852×1847 RGB chroma source | `e31ec351d92daec7aac25b40783ecf7ea45b9aadf7e25676d6bad96acde954cd` |

The retained generated sources live under `generated-sources`. The four
overlays used a `#ff00ff` key because green is a production subject color. The
default chroma helper was evaluated first, but its result was rejected after
visual review found edge matte. The approved deterministic build is
`scripts/build-forest-scene-assets.py`: it removes only key-colored background
connected to the canvas edge, reconstructs the narrow antialias band from
neighboring subject color, and preserves opaque painted detail. The more complex
midground and ground layers use an edge-only repair path so no texture is
propagated into their interiors. No source illustration geometry was redrawn.

Every final master layer was Lanczos-fitted to exactly 1290×2796. `sky.png` is
RGB and fully opaque. The other four files are RGBA. The production compositor
uses a static 1.04 overscan scale for `foregroundLeaves` before applying its
translation; this is the minimum overscan that hides a 6 pt/dp horizontal move
on a 320 pt/dp-wide compact viewport. `acceptance-rest.png` and
`acceptance-max-motion.png` include that production overscan.

## Final master hashes

| File | Mode | SHA-256 |
| --- | --- | --- |
| `sky.png` | RGB | `0637af27204976fae7063dad80bbeceea6ac469a4d65ed6659f146ecc33b12d0` |
| `distantTrees.png` | RGBA | `48e7598f0aa73b459ce4e0861e150945bbf08e464dfe4182a892ed91b407b576` |
| `midgroundTrees.png` | RGBA | `7c04b3032c359feed724fbbd4b102b315de67ca226bd274144c5d0a5168485c2` |
| `foregroundLeaves.png` | RGBA | `04429a2b8b69e59847cf69b8ed5d0b52342e9587143d113bf68a78bb529d587a` |
| `ground.png` | RGBA | `9d103ed0ec164fba18478a1f2d287541db2d7b48ac3ace0224dc42b19cefb5d1` |
| `master-1290x2796.png` | RGB | `bdcac1d944964362177f4a081cb97a22333ee08c8e4ab7029564e134dcf4cc42` |
| `acceptance-rest.png` | RGB | `d0824aa43fe7a16c5273094b45395a031d8da65473757c4490ea611287217983` |
| `acceptance-max-motion.png` | RGB | `bc2d8a6640558884e3bfaad8456f3d8528db02bfc0f27d0db56e7adcbdf57251` |
| `reference-comparison.png` | RGB | `b3f57aec2f6336fb02fee5db330d1d186e7dbe8f35a51a647f7cefea55dbeb8d` |

## Runtime derivative hashes

The app bundles contain only the following deterministic `860×1864`
derivatives. They were produced from the approved masters with the macOS image
resampler (`sips -s format png -z 1864 860`) and copied byte-for-byte to iOS
and Android.

| File | Mode | SHA-256 |
| --- | --- | --- |
| `forest_home_sky.png` | RGB | `31269847c3ea3825cfb0622c642bbf7bf58cd85f49c168a4b77864cb134151c6` |
| `forest_home_distant_trees.png` | RGBA | `9c2e598b7aaad3240a97930a796b499769950a3dcd3569e89fd728319d1e56f1` |
| `forest_home_midground_trees.png` | RGBA | `19cd4380674504a333c31573432562ab3e3cb8730e7f2283c15d0e8c0b3e2dbf` |
| `forest_home_foreground_leaves.png` | RGBA | `66893d6c0913a36962ec2b2855506bb26e47a0024bc65ceb662bf5b0e6759c28` |
| `forest_home_ground.png` | RGBA | `5468374dce57202cec48e94e11015b339f15140b458b183320239f6653e8b23f` |

## Motion and compositing contract

Layer order is `sky`, `distantTrees`, `midgroundTrees`,
`foregroundLeaves`, `ground`. The shared eight-second triangle cycle is:

| Time | Progress | Distant | Midground | Foreground | Ground |
| ---: | ---: | --- | --- | --- | --- |
| 0 s | 0% | y 0 | y 0 | x 0, y 0 | stationary |
| 2 s | 50% | y -1 | y -2 | x +3, y -1.5 | stationary |
| 4 s | 100% | y -2 | y -4 | x +6, y -3 | stationary |
| 6 s | 50% | y -1 | y -2 | x +3, y -1.5 | stationary |
| 8 s | 0% | y 0 | y 0 | x 0, y 0 | stationary |

Reduce Motion fixes every transform at zero and schedules no frame callback.
Sheet, inactive-tab, and inactive-app pause sources freeze elapsed time and
resume without a jump.

## Approved content contrast

The forest is decorative. User-facing copy and primary actions sit on opaque
`cream50` (`#FFF9EC`) surfaces using only these verified pairs:

- `ink900` (`#183127`) / `cream50`: 13.28:1
- `forest700` (`#1F5E43`) / `cream50`: 7.30:1
- `muted600` (`#627168`) / `cream50`: 4.90:1

Do not use `forest500/cream50`, `forest500/cream100`, or
`muted600/cream100` for body copy.

## Normalized prompt set

All prompts classified the request as `stylized-concept`, named the intended
asset and layer, and assigned the two approved references explicit roles.

### Opaque backplate

> Create a polished original 1290:2796 portrait extension of the approved warm
> magical forest world. Match the references' soft high-end 2D rendering,
> bright blue sky, cream-gold clearing, and sunlit green depth. Keep a broad,
> visually quiet central stage and stronger foliage at the side edges. Make it
> fully opaque and full bleed. No character, animal, person, text, logo, UI,
> food, acorn, mushroom, crystal, gem, star, watermark, or large focal prop.

### Distant trees

> On a perfectly uniform `#ff00ff` chroma background, create only pale,
> atmospheric distant tree crowns and slender trunks along the lower horizon
> and outer thirds, aligned to the approved portrait backplate. Keep the broad
> center open, the detail low, and the layer clearly behind the midground. No
> ground, foreground leaves, character, text, UI, food, icon, or watermark.

### Midground trees

> On a perfectly uniform `#ff00ff` chroma background, create only richer
> medium-green side trees, branches, and shrubs aligned to the approved
> portrait backplate. Frame the outer thirds without closing the top or
> covering the center or lower character stage. No ground, foreground leaf
> cluster, character, text, UI, food, icon, or watermark.

The selected midground source is the targeted built-in edit that preserved the
first composition while removing visible key-colored rim light and accidental
key-colored holes before deterministic matte extraction.

### Foreground leaves

> On a perfectly uniform `#ff00ff` chroma background, create only restrained
> near-camera deep-green leaf and twig clusters at the extreme corners and a
> few side edges. Keep the central 60% empty and let edge clusters continue
> beyond the canvas for subtle motion. No trees, ground, character, text, UI,
> food, icon, or watermark.

### Ground

> On a perfectly uniform `#ff00ff` chroma background, create only low grass
> tufts, small rounded stones, tiny white wildflowers, and ground-edge foliage
> along the bottom outer edges. Preserve the central character footprint and
> transparent gaps; do not create an opaque floor. No tree, character, text,
> UI, food, icon, or watermark.
