# T Roadster

**Subway Surfers, but you are the car.** A 3D endless-runner stunt driver:
a white angular pickup speeds down an endless coastal highway at sunset —
weave between traffic, jump / fly on cold-gas thrusters, chain barrel rolls
and front flips for points, until one crash ends the run.

Built to match the reel: https://www.instagram.com/reel/DexAQsQh1WS/
(original game: Roadster Dash at roadsterdash.com — our car, name, art,
sounds and music are all original; no Tesla badges, no Cybertruck name,
no copied music or art).

## What is in v1

- 3-2-1-GO countdown (TEST SITE ramp launch on the very first run)
- 4-lane endless highway, 4 biomes (Coastal Sunset 40%, Neon Night 25%,
  Red Canyon 20%, Desert 15%) — one biome per run
- Traffic FSM: Cruise / Brake / LaneChange (with indicators) / Queue,
  5 vehicle types, spawn director that NEVER seals all 4 lanes
- Hop / fly (AIR 600 L tank) / slam / nitro boost
- Barrel roll +500, front flip +400, double stunt +1,200,
  perfect landing +150, near miss +100, coins, combo ×1–×10
- Rocket Mode (invincible smash) + Starman (double score)
- Crash sequence: 90 ms hit-stop → slow-mo tumble → desaturate to
  grayscale → NEW RECORD panel (score / distance / time / max combo /
  rank / coins) at 1.2 s
- Home / Garage (3 skins + 6 paints) / Leaderboard (local + seeded
  ghosts, honestly labelled) / Pause / Settings
- Controls: swipe AND tilt (Settings: Swipe / Tilt / Both, tilt dead
  zone ±4°, calibration, sensitivity), on-screen HOP / FLIP / ROLL /
  BOOST buttons, full keyboard map for test builds
- Game feel: trauma screen shake, hit-stop, squash & stretch, FOV kick,
  speed lines, number pops, engine pitch tied to speed, adaptive
  synthwave music (Cruise / Redline layers), SFX variation
- Preloader with logo + "made by Ahmed" (same as Color Cover)
- Fixed 60 Hz timestep + render interpolation, object pools, 60 fps
  target on the Oppo F9 (Android 8.1, API 27)

## Scoring calibration (SPEC §8)

A skilled ~40 s run should land near the reel: ~1,420 m ≈ 25,000 pts
(distance 10/m FLAT, never multiplied; ONLY stunts/bonuses get the
combo multiplier ×1–×10). Verify on the phone.

## Build (Color Cover route)

1. Create the public repo `Muhammad-Ahmad-CO/t-roadster` in the browser.
2. Push this project (all files in this folder).
3. Create `.github/workflows/build-apk.yml` in the browser — paste
   `build-apk.yml.txt` (the GitHub App cannot write that folder — 403).
   Flutter is pinned to **3.47.9** (the version that built Color Cover
   v3.5–v3.8; do NOT use the `stable` channel, it failed twice).
4. GitHub Actions builds → artifact `t-roadster-apk` → verify sha256 →
   create a GitHub Release (tag `v1.0.0`) and attach the APK for a
   permanent download link.

## Project shape

```
lib/
  main.dart            App, preloader, GameWidget + overlays
  game/
    game.dart          FlameGame, fixed timestep, crash sequence,
                       pseudo-3D renderer, input layer
    road.dart          biomes, projection, segments, props, coins
    car.dart           hero car physics + vector drawing
    traffic.dart       traffic FSM + spawn director
    stunts.dart        flip/roll state machine, landing judgement
    scoring.dart       §8 formula, combo, coins
    camera_fx.dart     trauma shake, hit-stop, FOV kick, desaturate
    input.dart         ONE action layer: keyboard + swipe + tilt + buttons
    audio.dart         buses, engine, adaptive music, SFX pools
    hud.dart           event-driven HUD state
    storage.dart       bests, coins, skins, settings
  ui/                  home, garage, leaderboard, pause, gameover,
                       settings, hud overlay, theme
assets/
  logo.png  fonts/ (Russo One, Archivo Black, Nunito — OFL)
  sounds/   all original synthesized WAVs (tools/generate_assets.py)
```

## Honest limits

- flutter/dart are NOT installed on the build VM, so `flutter analyze`
  / `flutter build` could NOT be run here. The code went through a
  3-pass manual recheck (zero errors found by review), but the first
  real compile is GitHub Actions — treat its first failure as normal
  and fix from the log.
- The "3D" is a pseudo-3D projection (OutRun-style) with vector art,
  per SPEC §13.1. If the phone test says "yeh 3D nahi lag raha", the
  fallback is a Godot build — v1 is Flutter first, per the user.
- Lane count (4), stunt point values and speeds are spec decisions
  from the reel (exact originals could not be verified from public
  sources) — they are tuning targets for the phone test.
