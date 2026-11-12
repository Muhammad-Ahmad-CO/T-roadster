# SOURCES.md — external assets in T Roadster (Godot)

Every external asset file actually imported into this project, file-exact.
All are CC0 1.0 Universal. No other external asset files are in the
project: no other files from the Asphalt031 zip (NormalGL/NormalDX,
AmbientOcclusion, Displacement, `.tres`, `.blend`, preview PNG), no
Asphalt 02, no Leaf001, no GLB models, no zips. No Tesla/Cybertruck/
roadsterdash.com assets, ever. No new download may be added without a
new ACCEPTED row (source URL + licence statement read on the source
page) — no exceptions. Single writer: Lane B (cinematic rebuild).

Licences were verified on the source pages on 2026-11-12.

## Imported files

### 1. `assets/asphalt031_color_1024.jpg` — road albedo texture

- Source asset: Asphalt031 (1K JPG set), ambientCG, by Lennart Demes.
- Source page: https://ambientcg.com/view?id=Asphalt031
- Download: https://ambientcg.com/get?file=Asphalt031_1K-JPG.zip
- Source file inside the zip: `Asphalt031_1K-JPG_Color.jpg`
  (1024x1024, 855584 bytes).
- This file: byte-identical copy of the source file, unmodified
  ("as-is", 1024x1024).
- sha256 (imported file = source file):
  `d8301ee35f486ba073bdd5fda3ea9ed7e40f768aa1def75c420bcc5c055e3534`
- sha256 of the downloaded zip (provenance only; the zip itself is
  NOT in the project):
  `f98114b8fb083fc65925c3b4568b131e37c9a23357d432a16e59676dbc69f964`
- Licence: CC0 1.0 Universal. Exact statements on the licence page
  (https://docs.ambientcg.com/license/): "All ambientCG assets are
  provided under the Creative Commons CC0 1.0 Universal License." /
  "You can include the raw files in your project, for example a video
  game."

### 2. `assets/asphalt031_rough_512.jpg` — road roughness texture

- Source asset: Asphalt031 (1K JPG set), ambientCG, by Lennart Demes.
- Source page: https://ambientcg.com/view?id=Asphalt031
- Download: https://ambientcg.com/get?file=Asphalt031_1K-JPG.zip
- Source file inside the zip: `Asphalt031_1K-JPG_Roughness.jpg`
  (1024x1024, 838751 bytes).
- This file: DERIVED by resizing the source file from 1024x1024 to
  512x512 BEFORE import (no `.import` resize setting exists).
  Method: Python PIL `Image.resize((512, 512), Image.LANCZOS)`,
  saved as JPEG quality=95, subsampling=0. Output: 512x512,
  141821 bytes.
- sha256 of the source file:
  `b6211415277cad253d6d41330ac1b4b8b3edf631ac56561f7193670935e3d200`
- sha256 of the imported (resized) file:
  `37556f1e5ed7c850b12070f70e11f627313a37dcc7e9a530484b9c180580ec6b`
- Licence: CC0 1.0 Universal, same ambientCG licence page and
  statements as row 1.

### 3. `assets/palm_bark_512.jpg` — palm trunk texture

- Source asset: Palm Bark (1K Diffuse), Poly Haven, by Charlotte
  Baglioni.
- Source page: https://polyhaven.com/a/palm_bark
- API: https://api.polyhaven.com/files/palm_bark
- Source file: `palm_bark_diff_1k.jpg` (1024x1024, 707281 bytes).
- This file: DERIVED by resizing the source file from 1024x1024 to
  512x512 BEFORE import (no `.import` resize setting exists).
  Method: Python PIL `Image.resize((512, 512), Image.LANCZOS)`,
  saved as JPEG quality=95, subsampling=0. Output: 512x512,
  105978 bytes.
- sha256 of the source file:
  `80cbe5ee11af799db082cdb342601a70b81a5f54b98eb587e87dcb5bf5e1f395`
- sha256 of the imported (resized) file:
  `9176e7700aca3262ed42de7b19cc6c370bbafc360454b72738723fe0f1457257`
- Licence: CC0 1.0 Universal. Exact statements on the licence page
  (https://polyhaven.com/license): "Our assets are all licensed as
  CC0" / "You can use our assets for any purpose, including
  commercial work."

## Import settings (`.import` files committed alongside the textures)

- `compress/mode=2` (VRAM Compressed), `mipmaps/generate=true` on all
  three files. Filter (linear + mipmap) and repeat are set at the use
  site, not in the `.import` file: the road shader declares its
  samplers with `filter_linear_mipmap` + `repeat` hints, and the palm
  trunk material sets its texture filter in code. The project setting
  `textures/vram_compression/import_etc2_astc=true` applies.

## Procedural / original assets (no file, no licence risk)

- Palm frond mask: runtime-generated `Image` in `scripts/vehicles.gd`
  (pinnate silhouette drawn in code, same pattern as the existing
  radial-texture helpers). No file is imported for it. If it is ever
  saved as a PNG, that file must be marked ORIGINAL here and must go
  through the single asset owner (Lane B).
- All other visuals (hero, traffic, palms, skyline, clouds, sun disc,
  halos, shaders) are procedural/original code in this project.
