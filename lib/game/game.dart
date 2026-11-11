import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'; // KeyEventResult + gradients/Alignment

import 'achievements.dart';
import 'audio.dart';
import 'camera_fx.dart';
import 'car.dart';
import 'daily_challenge.dart';
import 'hud.dart';
import 'input.dart';
import 'police.dart';
import 'quests.dart';
import 'road.dart';
import 'streaks.dart';
import 'upgrades.dart';
import 'scoring.dart';
import 'storage.dart';
import 'stunts.dart';
import 'traffic.dart';

enum RunState { home, countdown, playing, paused, crashing, gameOver }

/// Seeded "global" ghost scores so the leaderboard feels alive in v1.
/// The player's rank is honestly labelled LOCAL RANK until a real backend
/// exists (SPEC §3.8).
const List<int> kGhostScores = <int>[
  48210, 41500, 38900, 35400, 33100, 31200, 29800, 28400, 27100, 25681,
  24900, 23400, 22100, 20800, 19600, 18300, 17100, 15900, 14700, 13600,
  12400, 11300, 10200, 9100, 8200, 7300, 6400, 5500, 4600, 3700,
];

class GameOverData {
  GameOverData({
    required this.score,
    required this.distance,
    required this.timeS,
    required this.maxCombo,
    required this.rank,
    required this.coinsEarned,
    required this.isRecord,
    required this.bestScore,
    this.newAchievements = const <String>[],
    this.newQuests = const <String>[],
    this.dailyDone = false,
    this.crashKind = 'crash',
    this.isWrongWay = false,
    this.isTimeTrial = false,
  });

  final int score;
  final int distance;
  final int timeS;
  final int maxCombo;
  final int rank;
  final int coinsEarned;
  final bool isRecord;
  final int bestScore;

  /// Achievement titles newly unlocked by this run (shown on the panel).
  final List<String> newAchievements;

  /// Quest titles completed by this run's totals (shown on the panel).
  final List<String> newQuests;

  /// True when this run completed (and claimed) today's daily challenge.
  final bool dailyDone;

  /// 'crash' (traffic) or 'police' (busted by the chase — Round 1).
  final String crashKind;

  /// True when this run was in Wrong-Way mode (Round 4).
  final bool isWrongWay;

  /// True when this run was a Time Trial (Round 6). bestScore then holds
  /// the best DISTANCE in 60 s, not a score.
  final bool isTimeTrial;
}

class Particle {
  Particle({
    required this.x,
    required this.y,
    required this.z,
    required this.vx,
    required this.vy,
    required this.vz,
    required this.life,
    required this.color,
    required this.size,
    this.gravity = 12.0,
    this.shape = 0,
    this.flutter = 0.0,
  }) : maxLife = life;

  double x, y, z, vx, vy, vz, life, size, gravity, flutter;
  final int shape; // 0 circle, 1 rectangle, 2 triangle
  final double maxLife;
  final Color color;
}

/// A skid mark on the road (Round 52): one tyre's trail, fading over 2 s.
class _SkidMark {
  _SkidMark({required this.x, required this.z, required this.life});

  double x, z, life;
}

class _Pickup {
  _Pickup({required this.x, required this.z, required this.kind});

  double x, z;
  String kind; // 'rocket' | 'starman'
  bool taken = false;
  double bob = 0.0;
}

class _Ramp {
  _Ramp({required this.x, required this.z});

  double x, z;
  bool used = false;
}

/// T Roadster — FlameGame with a fixed 60 Hz timestep and a custom
/// pseudo-3D renderer (SPEC §13). The sim never reads the camera FX;
/// juice is visual-only (game-feel skill).
class TRoadsterGame extends FlameGame with KeyboardEvents {
  TRoadsterGame({required this.storage, required this.audio}) {
    achievements = AchievementTracker(storage);
    quests = Quests(storage);
    streaks = Streaks(storage);
  }

  final GameStorage storage;
  final GameAudio audio;
  late final AchievementTracker achievements;
  late final Quests quests;
  late final Streaks streaks;

  /// Per-run counters feeding achievements + the daily challenge.
  int runRolls = 0;
  int runNearMisses = 0;

  final InputController input = InputController();
  final Scoring scoring = Scoring();
  final HudState hud = HudState();
  final CameraFx cameraFx = CameraFx();
  final Road road = Road();
  final HeroCar hero = HeroCar();
  final StuntController stunts = StuntController();
  final SpawnDirector director = SpawnDirector();
  final PoliceChase police = PoliceChase();
  String crashKind = 'crash';

  /// Wrong-Way mode (Round 4): set from Home before DRIVE. Traffic comes
  /// at the hero instead of flowing the same way. Persists across runs
  /// until the player toggles it off — startRun never resets it.
  bool wrongWay = false;

  /// Time Trial mode (Round 6): set from Home before DRIVE. A 60 s clock;
  /// the run ends at 0:00. Stacks with Wrong-Way. Persists until toggled off.
  bool timeTrial = false;

  /// Seconds left on the Time Trial clock (Round 6). 60.0 at run start.
  double timeLeft = 60.0;

  /// Cinema mode (Round 10): free camera orbit around the frozen car.
  /// Pure visual — the sim stays paused. Angle ±75° (the renderer only
  /// looks forward, so a full 360° would put the hero behind the camera).
  bool cinema = false;
  double cinemaAngle = 0.0; // radians, −1.3..+1.3
  double cinemaRadius = 7.5; // metres, 5.0..12.0 (zoom)

  RunState runState = RunState.home;
  Biome biome = Biome.coastal;
  GameOverData? lastGameOver;

  // Fixed timestep (physics-tuning skill): 60 Hz sim, render interpolates.
  static const double _step = 1.0 / 60.0;
  double _acc = 0.0;
  double _alpha = 1.0;
  double frameDt = 0.0;

  double _countdownT = 0.0;
  double _countdownTotal = 2.4;
  String _lastCountdown = '';
  double _goTimer = 0.0; // clears the GO text + countdown overlay
  double _crashT = 0.0;
  double _tumbleRoll = 0.0;
  double _hudTimer = 0.0;
  double _exhaustTimer = 0.0;
  double _policePointTimer = 0.0;
  double _sirenTimer = 0.0;
  bool _firstRunRamp = false;
  bool _slowMoStarted = false;

  final List<Particle> particles = [];

  /// Skid marks left on the road (Round 52): dark tyre trails that fade
  /// over 2 s. Capped at 60 so a long drift never grows the list.
  final List<_SkidMark> skids = [];
  final List<_Pickup> pickups = [];
  final List<_Ramp> ramps = [];
  double _nextPickupZ = 700.0;
  double _nextRampZ = 700.0;
  int _smashChain = 0;
  bool _hopPromptShown = false;
  final math.Random _rand = math.Random();

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;
    camera.viewfinder.position = Vector2.zero();
    cameraFx.reduceShake = storage.reduceShake;
    cameraFx.reduceFlash = storage.reduceFlash;
    input.mode = switch (storage.controlMode) {
      'swipe' => ControlMode.swipe,
      'tilt' => ControlMode.tilt,
      _ => ControlMode.both,
    };
    input.tiltSensitivity = storage.tiltSensitivity;
    input.tiltGasBrake = storage.tiltGasBrake;
    scoring.onPopup = (text, points) => hud.showPopup(text, points);
    // Achievement unlocks: gold toast mid-run + chime (the HUD overlay is
    // active during play, so the toast is visible; run-end unlocks are
    // shown on the game-over panel instead — see _finishCrash).
    achievements.onUnlock = (title) {
      hud.showAchievementToast('🏆 $title');
      audio.perfectChime();
    };
    await input.startTilt();
    add(RoadRenderer(this));
    add(InputLayer(this));
    await audio.init(
      musicVolume: storage.musicVolume,
      sfxVolume: storage.sfxVolume,
      engineVolume: storage.engineVolume,
      muted: storage.muted,
    );
    await audio.startMenuMusic();
  }

  // ---- Public controls (called by the Flutter overlays) --------------------
  void startRun() {
    cinema = false; // a fresh run is never in Cinema mode (Round 10)
    hero.reset();
    hero.skin = storage.equippedSkin;
    hero.paint = storage.equippedPaint;
    // Upgrades (Round 2): applied from storage before the run starts.
    final ups = Upgrades(storage);
    hero.airCapacity = ups.airCapacity;
    hero.rocketDuration = ups.rocketDuration;
    hero.refillRate = ups.refillRate;
    hero.magnetRadius = ups.magnetRadius;
    hero.air = hero.airCapacity;
    unawaited(quests.ensureWeek());
    stunts.reset();
    scoring.reset();
    hud.reset();
    hud.airMaxLitres.value = hero.airCapacity; // upgraded tank, not 600
    road.reset();
    director.reset();
    director.wrongWay = wrongWay; // set AFTER reset (Round 4)
    particles.clear();
    pickups.clear();
    ramps.clear();
    cameraFx.reset();
    cameraFx.reduceShake = storage.reduceShake;
    cameraFx.reduceFlash = storage.reduceFlash;
    input.reset();
    input.calibrateTilt();
    _nextPickupZ = 700.0;
    _nextRampZ = 650.0 + _rand.nextDouble() * 250.0;
    _smashChain = 0;
    _hopPromptShown = false;
    runRolls = 0;
    runNearMisses = 0;
    _crashT = 0.0;
    _tumbleRoll = 0.0;
    _slowMoStarted = false;
    police.reset();
    crashKind = 'crash';
    _policePointTimer = 0.0;
    _sirenTimer = 0.0;
    lastGameOver = null;

    // First run ever: TEST SITE ramp launch on the coastal sunset
    // (SPEC §2.5 / §3.4). Later runs pick a random biome.
    if (!storage.hasPlayed) {
      biome = Biome.coastal;
      _firstRunRamp = true;
    } else {
      biome = pickBiome(_rand);
      _firstRunRamp = false;
    }
    // Slippery Snow (Round 5): lazier lane-magnet return on snow.
    hero.grip = biome == Biome.snow ? 0.6 : 1.0;
    // Time Trial clock (Round 6): 60 s from GO.
    timeLeft = 60.0;
    hud.timeLeft.value = 60;

    runState = RunState.countdown;
    _countdownTotal = 2.4;
    _countdownT = _countdownTotal;
    _lastCountdown = '';
    // First launch: one-line how-to (SPEC §3.1) — shown as a popup so it
    // needs no extra screen and no SKIP button to dismiss.
    if (!storage.hasPlayed) {
      hud.showPopup('SWIPE / TILT TO STEER', 0);
    }
    overlays.remove('home');
    overlays.remove('gameover');
    overlays.remove('pause');
    overlays.remove('garage');
    overlays.remove('leaderboard');
    overlays.remove('settings');
    overlays.add('hud');
    overlays.add('countdown');
    audio.startRunMusic();
    audio.startEngine();
  }

  void pauseGame() {
    if (runState != RunState.playing && runState != RunState.countdown) return;
    runState = RunState.paused;
    overlays.remove('hud');
    overlays.remove('countdown');
    overlays.add('pause');
    audio.stopEngine();
  }

  /// Enter Cinema mode (Round 10): freeze on the paused frame and orbit
  /// the camera. Only from pause; the sim stays paused throughout.
  void enterCinema() {
    if (runState != RunState.paused) return;
    cinema = true;
    cinemaAngle = 0.0;
    cinemaRadius = 7.5;
  }

  /// Leave Cinema mode (Round 10): back to the pause menu, run still paused.
  void exitCinema() {
    cinema = false;
  }

  void resumeGame() {
    if (runState != RunState.paused) return;
    cinema = false;
    runState = RunState.countdown;
    _countdownTotal = 1.0; // quick 3-2-1 (SPEC §3.6)
    _countdownT = _countdownTotal;
    _lastCountdown = '';
    overlays.remove('pause');
    overlays.add('hud');
    overlays.add('countdown');
    audio.startEngine();
  }

  void quitToMenu() {
    runState = RunState.home;
    cinema = false;
    cameraFx.restoreColour();
    overlays.remove('hud');
    overlays.remove('countdown');
    overlays.remove('pause');
    overlays.remove('gameover');
    overlays.add('home');
    audio.stopEngine();
    audio.startMenuMusic();
  }

  // ---- Fixed-timestep loop ---------------------------------------------------
  @override
  void update(double dt) {
    super.update(dt);
    frameDt = dt.clamp(0.0, 0.1);
    final simDt = frameDt * cameraFx.timeScale;
    cameraFx.updateFov(frameDt);
    cameraFx.updateFlash(frameDt);
    cameraFx.updateSaturation(frameDt);
    hud.updatePopups(frameDt);
    input.update(frameDt);

    // The GO text lives for one quarter after the drive begins, then the
    // countdown overlay is removed (the countdown state itself is already
    // over by then — _updateCountdown no longer runs).
    if (_goTimer > 0) {
      _goTimer -= frameDt;
      if (_goTimer <= 0) {
        hud.countdown.value = '';
        overlays.remove('countdown');
      }
    }

    switch (runState) {
      case RunState.countdown:
        _updateCountdown(frameDt);
        break;
      case RunState.playing:
        _accumulate(simDt);
        break;
      case RunState.crashing:
        _crashTimeline(frameDt);
        _accumulate(simDt); // world tumbles on in slow-mo
        break;
      case RunState.home:
        // Menu backdrop: the highway idles (SPEC §3.2 — the menu IS the
        // highway). Slow drift; startRun() resets the hero.
        hero.z += 6 * frameDt;
        road.updateProps(hero.z, biome);
        break;
      case RunState.paused:
      case RunState.gameOver:
        break;
    }
  }

  void _accumulate(double simDt) {
    _acc += simDt;
    var steps = 0;
    while (_acc >= _step && steps < 5) {
      _stepSim(_step);
      _acc -= _step;
      steps++;
    }
    if (steps == 5) _acc = 0.0; // hitch: drop backlog, never spiral
    _alpha = (_acc / _step).clamp(0.0, 1.0);
  }

  void _updateCountdown(double dt) {
    _countdownT -= dt;
    // Steering is live from "1" so the player can pre-steer (SPEC §3.4);
    // speed stays locked until GO.
    hero.x += input.steering * HeroCar.lateralSpeed * dt;
    hero.x = hero.x.clamp(-6.0, 6.0);
    final quarter = _countdownTotal / 4;
    String label;
    if (_countdownT > quarter * 3) {
      label = '3';
    } else if (_countdownT > quarter * 2) {
      label = '2';
    } else if (_countdownT > quarter) {
      label = '1';
    } else if (_countdownT > 0) {
      label = 'GO';
    } else {
      label = '';
    }
    if (label != _lastCountdown) {
      _lastCountdown = label;
      hud.countdown.value = label;
      if (label == 'GO') {
        audio.goHorn();
        cameraFx.kickFov();
        _goTimer = _countdownTotal / 4;
        // Exhaust burst on GO (Round 21): a cloud of white puffs as
        // the car launches off the line.
        for (var i = 0; i < 6; i++) {
          _spawnPuff(hero.x + (_rand.nextDouble() - 0.5) * 1.6,
              0.2, hero.z - 2.5 - _rand.nextDouble() * 2);
        }
        _beginDrive();
      } else if (label.isNotEmpty) {
        audio.tick();
      }
    }
  }

  void _beginDrive() {
    runState = RunState.playing;
    if (_firstRunRamp) {
      // TEST SITE launch: the car leaves the ramp flipping (SPEC §3.4).
      hero.vy = 12.0;
      hero.onGround = false;
      stunts.startFlip();
      hud.showPopup('HOLD HOP TO FLY', 0);
      _firstRunRamp = false;
    }
  }

  // ---- One fixed tick ---------------------------------------------------------
  void _stepSim(double dt) {
    // During the crash the world only tumbles in slow-mo: particles fall,
    // traffic and the hero do NOT keep driving (the crash sequence owns
    // the hero via _crashTimeline).
    if (runState != RunState.playing) {
      updateParticles(dt);
      return;
    }

    hero.snapshot();
    for (final c in director.cars) {
      c.snapshot();
    }

    // Input queues (consumed once per tick).
    if (input.hopQueued) {
      if (hero.onGround) {
        hero.hop();
        audio.hop();
      } else if (!stunts.active) {
        // Space again in air = barrel roll (SPEC §7.1).
        if (stunts.startRoll()) audio.rollSwish();
      }
    }
    if (input.flipQueued && !hero.onGround) {
      if (stunts.startFlip()) {
        audio.flipSwish();
        audio.duckEngineForStunt();
      }
    }
    if (input.rollQueued && !hero.onGround) {
      if (stunts.startRoll()) audio.rollSwish();
    }
    if (input.slamQueued) hero.slam();
    if (input.boostQueued || input.boostHeld) {
      if (hero.nitroCooldown <= 0 && hero.nitroTime <= 0) {
        hero.boost();
        cameraFx.kickFov();
      }
    }
    input.consumeQueues();

    final flying = input.hopHeld || input.keyHopHeld;
    final landed = hero.update(dt, input, flying: flying);
    final stuntDone = stunts.update(dt);
    if (stuntDone) {
      if (stunts.didRoll) {
        scoring.barrelRoll();
        runRolls++;
        unawaited(_questProgress('rolls', 1));
        police.onStunt();
        unawaited(achievements.onRoll());
      }
      if (stunts.didFlip) {
        scoring.frontFlip();
        unawaited(_questProgress('flips', 1));
        police.onStunt();
        unawaited(achievements.onFlip());
      }
      if (stunts.didRoll && stunts.didFlip && !stunts.doubleStuntAwarded) {
        stunts.doubleStuntAwarded = true;
        scoring.doubleStunt();
      }
    }

    if (landed) _onLanded();

    // Traffic + road + director.
    for (final c in director.cars) {
      c.update(dt, director.cars);
    }
    director.update(hero.z, scoring.distance);
    road.updateProps(hero.z, biome);

    // Pickups & ramps.
    _updatePickups(dt);
    _updateRamps();

    // Coins (magnet 1.2 m, SPEC §8.4).
    for (final coin in road.coins) {
      if (coin.taken) continue;
      final dz = (coin.z - hero.z).abs();
      if (dz > 2.5) continue;
      final dx = (coin.x - hero.x).abs();
      final dy = (coin.y - hero.y).abs();
      if (dx < hero.magnetRadius && dy < 1.6) {
        coin.taken = true;
        scoring.coin(air: coin.air);
        if (coin.air) {
          hero.air = (hero.air + 150).clamp(0.0, hero.airCapacity);
        }
        audio.coin();
        _spawnSparkle(coin.x, coin.y + 0.5, coin.z);
      }
    }

    // Collisions + near misses.
    _checkTraffic();

    // Scoring: distance points every tick (10/m, FLAT — never multiplied;
    // only stunts/bonuses get the combo multiplier, SPEC §8 tuned).
    scoring.addDistance(hero.speed * dt);
    scoring.update(dt);

    // Time Trial clock (Round 6): ticks only while playing (not during
    // the 3-2-1-GO countdown — _beginDrive starts the playing state).
    if (timeTrial) {
      timeLeft -= dt;
      hud.timeLeft.value = math.max(0, timeLeft.ceil());
      if (timeLeft <= 0) {
        timeLeft = 0;
        _endTimeTrial();
        return;
      }
    }

    // Police chase (Round 1): spawns after 1,000 m, closes in, busted or
    // escaped. Survival pays +25 flat points per second.
    final policeEvent = police.update(dt, scoring.distance);
    if (police.active) {
      _policePointTimer += dt;
      if (_policePointTimer >= 1.0) {
        _policePointTimer -= 1.0;
        scoring.addFlat(25);
      }
      _sirenTimer += dt;
      if (_sirenTimer >= 2.0) {
        _sirenTimer = 0.0;
        audio.siren();
      }
    }
    if (policeEvent == PoliceEvent.busted) {
      _startCrash(reason: 'police');
      return;
    }
    if (policeEvent == PoliceEvent.escaped) {
      scoring.addFlat(500);
      hud.showPopup('SHOOK THE POLICE +500', 500);
      unawaited(storage.addLifetimePoliceEscapes(1));
    }

    // Tutorial hop prompt at ~150 m on the first run (SPEC §5.6).
    if (!storage.hasPlayed &&
        !_hopPromptShown &&
        scoring.distance > 150) {
      _hopPromptShown = true;
      hud.showPopup('SWIPE UP OR TAP HOP TO JUMP', 0);
    }

    // Particles (debris / sparks / puffs).
    updateParticles(dt);
    // Skid marks (Round 52): fade out over 2 s.
    for (final s in skids) {
      s.life -= dt;
    }
    skids.removeWhere((s) => s.life <= 0);

    // Exhaust puffs on GO / hard steer at speed.
    _exhaustTimer -= dt;
    if (_exhaustTimer <= 0 && hero.speed > 40 && input.isSteering) {
      _exhaustTimer = 0.12;
      _spawnPuff(hero.x, 0.2, hero.z - 2.5);
      // Skid marks (Round 52): dark tyre trails left on the road.
      if (skids.length < 60) {
        skids.add(_SkidMark(x: hero.x - 0.9, z: hero.z - 2.5, life: 2.0));
        skids.add(_SkidMark(x: hero.x + 0.9, z: hero.z - 2.5, life: 2.0));
      }
      // Tyre smoke (Round 20): grey puffs at both rear wheels.
      _spawnSmoke(hero.x - 0.9, 0.2, hero.z - 2.5);
      _spawnSmoke(hero.x + 0.9, 0.2, hero.z - 2.5);
      // Snow spray (Round 5): white kick-up behind the rear wheels on
      // hard steer in Snow — same trigger as the exhaust puff.
      if (biome == Biome.snow) _spawnSnowSpray();
    }

    // Rocket flame trail (Round 2 graphics): orange flames stream behind
    // the car while Rocket Mode is active — distinct from exhaust puffs.
    if (hero.rocketTime > 0) {
      _spawnFlame(hero.x, 0.4, hero.z - 2.8);
      // Exhaust puffs on nitro (Round 21): white puffs join the flames
      // at a slower cadence so the boost reads as engine + fire.
      if (_rand.nextDouble() < 0.5) {
        _spawnPuff(hero.x + (_rand.nextDouble() - 0.5) * 0.8,
            0.3, hero.z - 2.8);
      }
    }

    // Weather particles (Round 5): rain streaks in Rain, snowflakes in
    // Snow. Spawned in world space ahead of the hero so they drift past.
    if (biome == Biome.rain) {
      _spawnRain();
      _spawnRain();
    } else if (biome == Biome.snow) {
      _spawnSnowflake();
    }

    // Throttled HUD + audio (4×/s, SPEC §6 — never per frame).
    _hudTimer += dt;
    if (_hudTimer >= 0.25) {
      _hudTimer = 0.0;
      hud.speedKmh.value = (hero.speed * 3.6).round();
      hud.rocketActive.value = hero.rocketTime > 0;
      hud.starmanActive.value = hero.starmanTime > 0;
      hud.nitroFrac.value = hero.nitroCooldown > 0
          ? 1.0 - (hero.nitroCooldown / HeroCar.nitroCooldownTime)
          : 1.0;
      hud.airborne.value = !hero.onGround;
      hud.policeActive.value = police.active;
      hud.policeDistance.value = police.behind;
      hud.airFrac.value = hero.air / hero.airCapacity;
      hud.airMaxLitres.value = hero.airCapacity;
      audio.setEngineSpeed(hero.speed);
      audio.setIntensity(
        speedMs: hero.speed,
        multiplier: scoring.currentMultiplier,
      );
    }
  }

  void _onLanded() {
    final err = stunts.landingErrorDeg();
    if (stunts.active || stunts.inFlight) {
      if (err > 55) {
        _startCrash();
        return;
      }
      if (err <= 15 && (stunts.didRoll || stunts.didFlip)) {
        scoring.perfectLanding();
        audio.perfectChime();
      } else {
        // Good landing: 0.4 s wobble, steering halved (SPEC §5.7).
        hero.wobbleTime = 0.4;
      }
    }
    stunts.onLanded();
  }

  void _checkTraffic() {
    for (final c in List<TrafficCar>.from(director.cars)) {
      final dz = c.z - hero.z;
      final halfLen = (c.length + 4.2) / 2;
      if (dz.abs() < halfLen + 1.0) {
        final lateralOverlap =
            (c.x - hero.x).abs() < (c.width + 1.7) / 2;
        if (lateralOverlap) {
          if (hero.y > c.height + 0.3) {
            // Cleared it in the air.
            if (!c.hopCounted) {
              c.hopCounted = true;
              scoring.hopOverCar();
            }
          } else if (hero.invincible) {
            // Smash: traffic is knocked aside, no crash (SPEC §5.7).
            _smashChain++;
            director.cars.remove(c);
            scoring.smash(_smashChain);
            unawaited(_questProgress('smash', 1));
            police.onSmash();
            audio.smash();
            cameraFx.hitStop(duration: 0.05, slow: 0.1);
            cameraFx.addTrauma(0.4);
            _spawnDebris(c.x, 1.0, c.z);
          } else {
            _startCrash();
            return;
          }
        }
      } else if (!c.passed && c.z < hero.z - halfLen) {
        c.passed = true;
        _smashChain = 0;
        // A car the hero hopped over already paid +150 — no near-miss too.
        if (!c.hopCounted && c.nearMissCooldown <= 0) {
          final clearance =
              (c.x - hero.x).abs() - (c.width + 1.7) / 2;
          // Oncoming near misses (Round 4) get a slightly wider window —
          // the closing speed is double, so the same 0.9 m is too strict.
          final nearMissWindow = c.oncoming ? 1.2 : 0.9;
          if (clearance < nearMissWindow && clearance > -0.2) {
            c.nearMissCooldown = 0.5;
            scoring.nearMiss();
            runNearMisses++;
            unawaited(_questProgress('nearMiss', 1));
            police.onNearMiss();
            unawaited(achievements.onNearMiss());
            audio.nearMiss();
            _spawnSparks(hero.x, 0.8, hero.z + 2);
          }
        }
      }
    }
  }

  void _updatePickups(double dt) {
    if (hero.z > _nextPickupZ - 220) {
      final kind = _rand.nextBool() ? 'rocket' : 'starman';
      pickups.add(_Pickup(
        x: Road.laneCentres[_rand.nextInt(4)],
        z: _nextPickupZ,
        kind: kind,
      ));
      _nextPickupZ += 700.0 + _rand.nextDouble() * 400.0;
    }
    pickups.removeWhere((p) => p.z < hero.z - 20 || p.taken);
    for (final p in pickups) {
      p.bob += dt * 3;
      if ((p.z - hero.z).abs() < 3.0 && (p.x - hero.x).abs() < 1.6) {
        p.taken = true;
        if (p.kind == 'rocket') {
          hero.collectRocket();
          unawaited(_questProgress('rockets', 1));
          unawaited(achievements.onRocket());
          hud.showPopup('ROCKET MODE — INVINCIBLE', 0);
        } else {
          hero.collectStarman();
          scoring.starmanActive = true;
          hud.showPopup('STARMAN — DOUBLE SCORE', 0);
        }
        audio.pickup();
      }
    }
    if (hero.starmanTime <= 0) scoring.starmanActive = false;
  }

  void _updateRamps() {
    if (hero.z > _nextRampZ - 220) {
      ramps.add(_Ramp(
        x: Road.laneCentres[_rand.nextInt(4)],
        z: _nextRampZ,
      ));
      _nextRampZ += 600.0 + _rand.nextDouble() * 300.0;
    }
    ramps.removeWhere((r) => r.z < hero.z - 20 || r.used);
    for (final r in ramps) {
      if (!r.used && hero.onGround && (r.z - hero.z).abs() < 2.0 &&
          (r.x - hero.x).abs() < 1.6) {
        r.used = true;
        hero.vy = 12.0;
        hero.onGround = false;
        stunts.startFlip();
        scoring.rampLaunch();
        audio.hop();
      }
    }
  }

  // ---- Crash sequence (SPEC §9, exact) --------------------------------------
  /// Time Trial end (Round 6): the clock hit 0:00 — no crash, no tumble.
  /// The run ends cleanly with crashKind 'timeup' and the game-over panel.
  void _endTimeTrial() {
    crashKind = 'timeup';
    audio.fanfare();
    unawaited(_finishCrash());
  }

  void _startCrash({String reason = 'crash'}) {
    if (runState != RunState.playing) return;
    runState = RunState.crashing;
    crashKind = reason;
    _crashT = 0.0;
    _tumbleRoll = 0.0;
    _slowMoStarted = false;
    cameraFx.hitStop(duration: 0.09, slow: 0.05);
    cameraFx.addTrauma(0.8);
    cameraFx.flashWhite(0.6);
    audio.crash();
    audio.duckMusic();
    audio.stopEngine();
    _spawnDebris(hero.x, 1.0, hero.z);
    _spawnDebris(hero.x + 1, 0.6, hero.z + 2);
  }

  void _crashTimeline(double dt) {
    _crashT += dt;
    if (_crashT > 0.09 && !_slowMoStarted) {
      _slowMoStarted = true;
      cameraFx.slowMo(scale: 0.35, duration: 0.8);
    }
    // Slow-mo tumble: the car spins and slides (visual only).
    if (_crashT < 0.9) {
      _tumbleRoll += dt * 5.0;
      hero.z += hero.speed * 0.35 * dt;
      hero.y = math.max(0.0, hero.y + dt * 1.5);
    }
    if (_crashT > 0.3) cameraFx.startDesaturate();
    if (_crashT >= 1.2) _finishCrash();
  }

  Future<void> _finishCrash() async {
    runState = RunState.gameOver;
    final score = scoring.score.value;
    final distance = scoring.distanceM.value;
    var isRecord = await storage.saveRun(
      score: score,
      distance: distance,
      maxCombo: scoring.maxCombo,
      coinsEarned: scoring.coinsEarned + score ~/ 100,
    );
    // Wrong-Way runs keep a SEPARATE best (Round 4) — the panel's
    // NEW RECORD + BEST line follow the mode's best, not the normal one.
    if (wrongWay) {
      isRecord = await storage.saveWrongWayBest(score);
    }
    // Time Trial runs keep a SEPARATE best DISTANCE (Round 6) — best
    // distance in 60 s, not a score.
    if (timeTrial) {
      isRecord = await storage.saveTimeTrialBest(distance);
    }
    await storage.recordScore(score);
    final bankedCoins = scoring.coinsEarned + score ~/ 100;

    // Streak + weekly target (Round 8): streak day + weekly score bank.
    await streaks.noteRun(score);

    // Achievements + daily challenge (local only). Run-end unlocks are
    // shown on the game-over panel (the HUD overlay is removed below, so
    // a toast here would never be seen).
    final newAchievementIds = await achievements.onRunEnd(
      score: score,
      distance: distance,
      coinsEarned: bankedCoins,
      isRecord: isRecord,
      totalRuns: storage.totalRuns,
    );
    final newAchievementTitles = newAchievementIds
        .map((id) => Achievement.byId(id)?.title ?? id)
        .toList();
    var dailyDone = false;
    final daily = DailyChallenge.today();
    if (daily.isMetBy(
      score: score,
      rolls: runRolls,
      distance: distance,
      nearMiss: runNearMisses,
      coinsEarned: bankedCoins,
    )) {
      if (!storage.dailyDoneFor(daily.dateKey)) {
        await storage.markDailyDone(daily.dateKey);
        await storage.addCoins(daily.rewardCoins);
        dailyDone = true;
      }
    }

    // Quests (Round 3): weekly totals banked once per finished run.
    // These complete at run end, so their titles ride on the game-over
    // panel (the HUD is removed below — a toast here would never be seen).
    final newQuestTitles = <String>[];
    for (final entry in <(String, int)>[
      ('distance', distance),
      ('coins', bankedCoins),
      ('score', score),
    ]) {
      final completed = await quests.addProgress(entry.$1, entry.$2);
      newQuestTitles.addAll(completed.map((d) => d.title));
    }

    var rank = 1;
    for (final s in storage.localScores) {
      if (s > score) rank++;
    }
    for (final s in kGhostScores) {
      if (s > score) rank++;
    }
    lastGameOver = GameOverData(
      score: score,
      distance: distance,
      timeS: scoring.timeS.value,
      maxCombo: scoring.maxCombo,
      rank: rank,
      coinsEarned: scoring.coinsEarned + score ~/ 100,
      isRecord: isRecord,
      newAchievements: newAchievementTitles,
      newQuests: newQuestTitles,
      dailyDone: dailyDone,
      crashKind: crashKind,
      isWrongWay: wrongWay,
      isTimeTrial: timeTrial,
      bestScore: timeTrial
          ? storage.bestTimeTrial
          : (wrongWay ? storage.bestWrongWay : storage.bestScore),
    );
    if (crashKind == 'police') {
      unawaited(storage.addLifetimePoliceBusted(1));
    }
    overlays.remove('hud');
    overlays.remove('countdown');
    overlays.add('gameover');
    if (isRecord) audio.fanfare();
  }

  // ---- Particles (pooled, zero per-frame allocation in the hot loop) ---------
  void _spawnDebris(double x, double y, double z) {
    for (var i = 0; i < 14; i++) {
      particles.add(Particle(
        x: x + (_rand.nextDouble() - 0.5) * 2,
        y: y + _rand.nextDouble() * 1.5,
        z: z + (_rand.nextDouble() - 0.5) * 3,
        vx: (_rand.nextDouble() - 0.5) * 8,
        vy: 2 + _rand.nextDouble() * 6,
        vz: (_rand.nextDouble() - 0.5) * 8,
        life: 0.6 + _rand.nextDouble() * 0.6,
        color: _rand.nextBool()
            ? const Color(0xFFD7D7D7)
            : const Color(0xFFFF7E3D),
        size: 0.25 + _rand.nextDouble() * 0.4,
      ));
    }
    // Glass shards (Round 41): pale blue-white glints mixed into the
    // debris — the crash reads as shattered glass + metal.
    for (var i = 0; i < 8; i++) {
      particles.add(Particle(
        x: x + (_rand.nextDouble() - 0.5) * 2,
        y: y + _rand.nextDouble() * 2.0,
        z: z + (_rand.nextDouble() - 0.5) * 3,
        vx: (_rand.nextDouble() - 0.5) * 10,
        vy: 3 + _rand.nextDouble() * 7,
        vz: (_rand.nextDouble() - 0.5) * 10,
        life: 0.8 + _rand.nextDouble() * 0.5,
        color: _rand.nextBool()
            ? const Color(0xFFB3E5FC)
            : const Color(0xFFFFFFFF),
        size: 0.12 + _rand.nextDouble() * 0.15,
      ));
    }
  }

  // Near-miss spark burst (Round 22): a bigger, brighter burst — gold
  // sparks + a white-hot core + longer life so the near miss pops.
  void _spawnSparks(double x, double y, double z) {
    for (var i = 0; i < 20; i++) {
      final core = i < 6;
      particles.add(Particle(
        x: x,
        y: y,
        z: z,
        vx: (_rand.nextDouble() - 0.5) * 7,
        vy: 1 + _rand.nextDouble() * 4,
        vz: -4 - _rand.nextDouble() * 5,
        life: core ? 0.5 : 0.4,
        color: core
            ? const Color(0xFFFFFFFF)
            : const Color(0xFFFFD166),
        size: core ? 0.22 : 0.15,
        gravity: 2.0,
      ));
    }
  }

  void _spawnSparkle(double x, double y, double z) {
    for (var i = 0; i < 5; i++) {
      particles.add(Particle(
        x: x,
        y: y,
        z: z,
        vx: (_rand.nextDouble() - 0.5) * 2,
        vy: 1 + _rand.nextDouble() * 2,
        vz: (_rand.nextDouble() - 0.5) * 2,
        life: 0.4,
        color: const Color(0xFFFFD166),
        size: 0.12,
        gravity: 0.0,
      ));
    }
  }

  /// Quest progress (Round 3). Live completions toast + fanfare + gold
  /// confetti; run-end totals are banked in _finishCrash instead.
  Future<void> _questProgress(String kind, int amount) async {
    final completed = await quests.addProgress(kind, amount);
    for (final def in completed) {
      hud.showQuestToast('🎯 QUEST DONE: ${def.title}  +${def.rewardCoins} 🪙');
      audio.fanfare();
      _spawnConfetti();
    }
  }

  /// Gold confetti burst (Round 3 graphics) when a quest completes —
  /// gold/pink/cyan pieces, up then falling with gravity, around the car.
  void _spawnConfetti() {
    const colors = <Color>[
      Color(0xFFFFC531),
      Color(0xFFFFD166),
      Color(0xFFEC407A),
      Color(0xFF00F0FF),
    ];
    for (var i = 0; i < 40; i++) {
      particles.add(Particle(
        x: hero.x + (_rand.nextDouble() - 0.5) * 4.0,
        y: 1.0 + _rand.nextDouble() * 2.0,
        z: hero.z + 4.0 + _rand.nextDouble() * 4.0,
        vx: (_rand.nextDouble() - 0.5) * 4.0,
        vy: 3.0 + _rand.nextDouble() * 4.0,
        vz: -2.0 - _rand.nextDouble() * 2.0,
        life: 1.2,
        color: colors[_rand.nextInt(colors.length)],
        size: 0.25 + _rand.nextDouble() * 0.2,
        // Shaped pieces + flutter (Round 42): confetti is a mix of
        // rectangles + triangles that wobble side to side as they fall.
        shape: i % 3,
        flutter: 1.5 + _rand.nextDouble() * 2.0,
      ));
    }
  }

  /// Rain streak (Round 5 graphics): a fast, thin, pale streak falling
  /// ahead of the hero. No gravity — vy is the fall speed itself.
  void _spawnRain() {
    particles.add(Particle(
      x: hero.x + (_rand.nextDouble() - 0.5) * 30.0,
      y: 8.0 + _rand.nextDouble() * 4.0,
      z: hero.z + 10.0 + _rand.nextDouble() * 50.0,
      vx: -1.5,
      vy: -25.0,
      vz: -5.0,
      life: 0.45,
      color: const Color(0xFFBFE3FF),
      size: 0.08,
      gravity: 0.0,
    ));
  }

  /// Snowflake (Round 5 graphics): slow, drifting, white.
  void _spawnSnowflake() {
    particles.add(Particle(
      x: hero.x + (_rand.nextDouble() - 0.5) * 30.0,
      y: 6.0 + _rand.nextDouble() * 4.0,
      z: hero.z + 10.0 + _rand.nextDouble() * 40.0,
      vx: (_rand.nextDouble() - 0.5) * 1.0,
      vy: -2.0,
      vz: -5.0,
      life: 2.0,
      color: const Color(0xFFFFFFFF),
      size: 0.15,
      gravity: 0.0,
    ));
  }

  /// Snow spray (Round 5 graphics): white kick-up behind the rear wheels.
  void _spawnSnowSpray() {
    for (var i = 0; i < 3; i++) {
      particles.add(Particle(
        x: hero.x + (_rand.nextDouble() - 0.5) * 1.6,
        y: 0.2,
        z: hero.z - 2.5,
        vx: (_rand.nextDouble() - 0.5) * 2.0,
        vy: 1.5 + _rand.nextDouble() * 1.5,
        vz: -8.0 - _rand.nextDouble() * 3.0,
        life: 0.5,
        color: const Color(0xFFFFFFFF),
        size: 0.25 + _rand.nextDouble() * 0.2,
        gravity: 0.0,
      ));
    }
  }

  // Rocket flame trail polish (Round 39): bigger flickering flames
  // (orange core, yellow tip) + a dark smoke wisp trailing behind.
  void _spawnFlame(double x, double y, double z) {
    particles.add(Particle(
      x: x + (_rand.nextDouble() - 0.5) * 0.8,
      y: y,
      z: z,
      vx: 0,
      vy: 1.5 + _rand.nextDouble() * 1.5,
      vz: -9 - _rand.nextDouble() * 3,
      life: 0.45,
      color: _rand.nextBool()
          ? const Color(0xFFFF7E3D)
          : const Color(0xFFFFD166),
      size: 0.42 + _rand.nextDouble() * 0.25,
      gravity: 0.0,
    ));
    // Smoke wisp trailing the flame.
    if (_rand.nextDouble() < 0.6) {
      particles.add(Particle(
        x: x + (_rand.nextDouble() - 0.5) * 1.0,
        y: y + 0.4,
        z: z - 1.0,
        vx: 0,
        vy: 1.0 + _rand.nextDouble(),
        vz: -6 - _rand.nextDouble() * 2,
        life: 0.9,
        color: const Color(0xFF5D4037),
        size: 0.5 + _rand.nextDouble() * 0.3,
        gravity: 0.0,
      ));
    }
  }

  void _spawnPuff(double x, double y, double z) {
    particles.add(Particle(
      x: x,
      y: y,
      z: z,
      vx: 0,
      vy: 0.5,
      vz: -6,
      life: 0.5,
      color: const Color(0xFFFFFFFF),
      size: 0.35,
      gravity: 0.0,
    ));
  }

  /// Tyre smoke (Round 20): grey kick-up from the rear wheels on a hard
  /// steer at speed — distinct from the white exhaust puff (centre).
  void _spawnSmoke(double x, double y, double z) {
    particles.add(Particle(
      x: x + (_rand.nextDouble() - 0.5) * 0.4,
      y: y,
      z: z,
      vx: (_rand.nextDouble() - 0.5) * 2.0,
      vy: 1.2 + _rand.nextDouble(),
      vz: -5 - _rand.nextDouble() * 2,
      life: 0.8,
      color: const Color(0xFF9AA0A6),
      size: 0.45,
      gravity: 0.0,
    ));
  }

  void updateParticles(double dt) {
    for (final p in particles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.z += p.vz * dt;
      p.vy -= p.gravity * dt;
      if (p.y < 0) p.y = 0;
      p.life -= dt;
    }
    particles.removeWhere((p) => p.life <= 0);
  }

  // ---- Keyboard (SPEC §7.1) ---------------------------------------------------
  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.keyP ||
          event.logicalKey == LogicalKeyboardKey.escape) {
        if (runState == RunState.playing || runState == RunState.countdown) {
          pauseGame();
        } else if (runState == RunState.paused) {
          resumeGame();
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyM) {
        final muted = !storage.muted;
        storage.setMuted(muted);
        audio.setMuted(muted);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter &&
          runState == RunState.gameOver) {
        startRun();
        return KeyEventResult.handled;
      }
      if (runState == RunState.playing || runState == RunState.countdown) {
        if (input.onKeyDown(event.logicalKey)) return KeyEventResult.handled;
      }
    } else if (event is KeyUpEvent) {
      input.onKeyUp(event.logicalKey);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

/// Full-screen touch layer: drag anywhere on the road steers (the control
/// appears where the finger lands — the Color Cover floating-joystick
/// lesson). Buttons are Flutter overlays above this layer.
class InputLayer extends PositionComponent with DragCallbacks, TapCallbacks {
  InputLayer(this.game);

  final TRoadsterGame game;

  @override
  Future<void> onLoad() async {
    size = game.size;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (game.runState != RunState.playing &&
        game.runState != RunState.countdown) return;
    game.input.onDragDelta(
      event.localDelta.x,
      event.localDelta.y,
      game.size.x,
    );
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    game.input.onDragEnd();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    game.input.onDragEnd();
  }
}

/// The pseudo-3D renderer (SPEC §13.1): sky, ocean, road, props, traffic,
/// coins, hero car, particles — all drawn in code, back to front.
class RoadRenderer extends Component {
  RoadRenderer(this.game);

  final TRoadsterGame game;

  final Projected _p1 = Projected();
  final Projected _p2 = Projected();
  final Projected _p = Projected();
  final Paint _paint = Paint();
  final Paint _linePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  /// Camera z, render-interpolated like the hero/traffic (physics-tuning
  /// skill) — using the raw hero.z here made the road judder against the
  /// interpolated cars. In Cinema mode (Round 10) the camera orbits the
  /// hero at [TRoadsterGame.cinemaRadius] and [cinemaAngle].
  double get _camZ {
    final hero = game.hero;
    if (game.cinema) {
      return hero.z - math.cos(game.cinemaAngle) * game.cinemaRadius;
    }
    return hero.prevZ + (hero.z - hero.prevZ) * game._alpha - 7.5;
  }

  /// Camera x — the chase-cam lateral position, or the Cinema orbit
  /// position (Round 10). Every draw method reads the camera through
  /// [_camX]/[_camZ] so the orbit applies to the whole scene at once.
  double get _camX {
    final hero = game.hero;
    if (game.cinema) {
      return hero.x + math.sin(game.cinemaAngle) * game.cinemaRadius;
    }
    return hero.interpX(game._alpha);
  }

  @override
  void render(Canvas canvas) {
    final size = game.size;
    final w = size.x;
    final h = size.y;
    final fx = game.cameraFx;
    final palette = BiomePalette.of(game.biome);

    // Desaturation wraps the whole scene (crash only — saveLayer is
    // expensive, so it is skipped at full saturation).
    final desat = fx.saturation < 0.99;
    if (desat) {
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, w, h),
        Paint()..colorFilter = ColorFilter.matrix(fx.saturationMatrix),
      );
    }

    canvas.save();
    // Crash camera: pull back 15%, tilt 8° (SPEC §9).
    if (game.runState == RunState.crashing) {
      final t = (game._crashT / 1.2).clamp(0.0, 1.0);
      canvas.translate(w / 2, h / 2);
      canvas.scale(1.0 - 0.13 * t);
      canvas.rotate(0.08 * t);
      canvas.translate(-w / 2, -h / 2);
    }
    // Trauma shake (camera only).
    final shake = fx.shakeOffset(game.frameDt);
    canvas.translate(shake.dx, shake.dy);

    _drawSky(canvas, w, h, palette);
    _drawGroundAndOcean(canvas, w, h, palette);
    _drawRoad(canvas, w, h, palette);
    _drawProps(canvas, w, h, palette);
    _drawCoins(canvas, w, h);
    _drawPickups(canvas, w, h);
    _drawRamps(canvas, w, h);
    _drawTraffic(canvas, w, h, palette);
    _drawPolice(canvas, w, h);
    _drawHero(canvas, w, h, palette);
    _drawParticles(canvas, w, h);
    _drawSpeedLines(canvas, w, h);
    _drawPoliceStrobe(canvas, w, h);
    _drawVignette(canvas, w, h);
    if (game.cinema) _drawCinemaFrame(canvas, w, h);

    canvas.restore();
    if (desat) canvas.restore();

    // White flash (impact frame).
    if (fx.flash > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()..color = Color(0xFFFFFFFF).withOpacity(fx.flash * 0.8),
      );
    }
  }

  double get _horizonY => game.size.y * 0.42;

  /// Deterministic per-segment hash (Round 15): stable road detail that
  /// never repeats a visible pattern and never changes between frames.
  int _segHash(int n) => (n * 2654435761) % 97;

  void _drawSky(Canvas canvas, double w, double h, BiomePalette p) {
    // Dawn/dusk gradient shift (Round 50): as distance grows the sky
    // deepens toward dusk — the run feels like a whole evening passing.
    final shift = ((game.hero.z / 1500) % 1) * 0.5;
    final skyTop = Color.lerp(p.skyTop, const Color(0xFF2A1A4E), shift)!;
    final skyMid = Color.lerp(p.skyMid, const Color(0xFF6B2D5B), shift)!;
    final skyHorizon =
        Color.lerp(p.skyHorizon, const Color(0xFFFF7E5F), shift)!;
    final rect = Rect.fromLTWH(0, 0, w, _horizonY + 2);
    _paint
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [skyTop, skyMid, skyHorizon],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, _paint);
    _paint.shader = null;
    // Drifting cloud shapes (Round 12): soft sunset-tinted puffs that
    // drift slowly with distance — the sky is alive, not a flat gradient.
    final cloudT = game.hero.z;
    for (var i = 0; i < 4; i++) {
      final span = w * 1.3;
      final cx = ((i * 0.31 * w + cloudT * (1.6 + i * 0.35)) % span) - w * 0.15;
      final cy = h * (0.045 + i * 0.038);
      final cw = w * (0.16 + (i % 2) * 0.05);
      _paint
        ..color = p.night
            ? const Color(0xFF8A9BB8).withValues(alpha: 0.10)
            : const Color(0xFFFFFFFF).withValues(alpha: 0.16)
        ..style = PaintingStyle.fill;
      canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, cy), width: cw, height: cw * 0.28),
          _paint);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx + cw * 0.28, cy - cw * 0.06),
              width: cw * 0.6,
              height: cw * 0.24),
          _paint);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx - cw * 0.30, cy + cw * 0.03),
              width: cw * 0.5,
              height: cw * 0.2),
          _paint);
    }
    // Birds crossing the sky (Round 26): small V-shaped silhouettes
    // gliding across the sky, flapping slowly with distance.
    for (var i = 0; i < 3; i++) {
      final span = w * 1.4;
      final bx = ((i * 0.47 * w + cloudT * (2.2 + i * 0.5)) % span) - w * 0.2;
      final by = h * (0.10 + i * 0.05);
      final flap = math.sin(cloudT * 0.25 + i * 2.0) * 4.0;
      final bw = w * 0.02;
      _paint
        ..color = const Color(0xFF1A1A2E).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      final bird = Path()
        ..moveTo(bx - bw, by + flap)
        ..quadraticBezierTo(bx - bw * 0.5, by - 3, bx, by)
        ..quadraticBezierTo(bx + bw * 0.5, by - 3, bx + bw, by + flap);
      canvas.drawPath(bird, _paint);
    }
    // Aurora band (Round 35): a shimmering green curtain across the
    // night sky, gently waving with distance. Night biomes only.
    if (p.night) {
      final auT = game.hero.z;
      _paint.style = PaintingStyle.stroke;
      for (var i = 0; i < 3; i++) {
        final yy = h * (0.06 + i * 0.03);
        _paint
          ..color = const Color(0xFF64FF9E).withValues(alpha: 0.10 - i * 0.02)
          ..strokeWidth = 8.0 - i * 2.0;
        final band = Path()..moveTo(0, yy);
        for (var sx = 0.0; sx <= w; sx += 20.0) {
          band.lineTo(sx,
              yy + math.sin(sx * 0.008 + auT * 0.05 + i * 1.2) * 10.0);
        }
        canvas.drawPath(band, _paint);
      }
    }
    // Lightning flash (Round 34): a rare jagged bolt + sky glow in the
    // Rain biome. Respects Reduce-flash: nothing flashes when it is set.
    if (game.biome == Biome.rain && !game.cameraFx.reduceFlash) {
      final cycle = (game.hero.z * 0.011) % 1;
      if (cycle < 0.03) {
        final flash = 1 - cycle / 0.03;
        final bx = w * (0.55 + (game.hero.z.floor() % 30) * 0.01);
        _paint
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9 * flash)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;
        final bolt = Path()
          ..moveTo(bx, h * 0.02)
          ..lineTo(bx - 12, h * 0.10)
          ..lineTo(bx + 8, h * 0.18)
          ..lineTo(bx - 6, h * 0.26)
          ..lineTo(bx + 4, _horizonY - 4);
        canvas.drawPath(bolt, _paint);
      }
    }
    // Sun disc + haze band. The sun sits LOW OVER THE OCEAN (left) on
    // coastal runs — exactly like the reel, where the sunset glitters on
    // the water; on land biomes it stays right (w * 0.70).
    final sunX = p.ocean ? w * 0.28 : w * 0.70;
    final sunY = _horizonY - h * 0.07;
    final sunR = h * 0.045;
    _paint
      ..color = p.sun.withOpacity(0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    canvas.drawCircle(Offset(sunX, sunY), sunR * 1.8, _paint);
    _paint.maskFilter = null;
    _paint.color = p.sun;
    canvas.drawCircle(Offset(sunX, sunY), sunR, _paint);
    // Volumetric sun rays (Round 11): long translucent shafts fanning
    // out from the sun disc — golden hour reads instantly. Day biomes
    // only; the night "sun" is a moon and gets no rays.
    if (!p.night) {
      final rayT = game.hero.z;
      for (var i = 0; i < 7; i++) {
        final a = -math.pi * (0.08 + i * 0.11) +
            math.sin(rayT * 0.02 + i) * 0.02;
        final len = h * (0.30 + (i % 3) * 0.06);
        final ray = Path()
          ..moveTo(sunX, sunY)
          ..lineTo(sunX + math.cos(a) * len, sunY + math.sin(a) * len)
          ..lineTo(sunX + math.cos(a + 0.035) * len,
              sunY + math.sin(a + 0.035) * len)
          ..close();
        _paint
          ..color = p.sun.withValues(alpha: 0.05 + (i % 2) * 0.02)
          ..style = PaintingStyle.fill;
        canvas.drawPath(ray, _paint);
      }
    }
    // Sun lens flare (Round 57): ghost circles strung along the
    // sun-to-centre axis — a camera lens, not just a disc. Day only.
    if (!p.night) {
      final cx = w * 0.5;
      final cy = _horizonY;
      for (var i = 0; i < 4; i++) {
        final t = 0.25 + i * 0.18;
        final fx = sunX + (cx - sunX) * t;
        final fy = sunY + (cy - sunY) * t;
        _paint
          ..color = p.sun.withValues(alpha: 0.18 - i * 0.03)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawCircle(Offset(fx, fy), sunR * (0.5 - i * 0.08), _paint);
      }
      _paint.maskFilter = null;
    }
    // Haze band: a soft warm strip hugging the horizon (golden hour).
    final hazeRect = Rect.fromLTWH(0, _horizonY - h * 0.03, w, h * 0.03);
    _paint
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          p.skyHorizon.withOpacity(0.0),
          p.skyHorizon.withOpacity(0.55),
        ],
      ).createShader(hazeRect)
      ..style = PaintingStyle.fill;
    canvas.drawRect(hazeRect, _paint);
    _paint.shader = null;
    if (p.night) {
      // Moon + stars (Round 36): the night "sun" becomes a cratered
      // moon with a halo, and the stars now twinkle instead of sitting
      // static.
      _paint
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawCircle(Offset(sunX, sunY), sunR * 1.9, _paint);
      _paint.maskFilter = null;
      _paint.color = const Color(0xFFF5F3CE);
      canvas.drawCircle(Offset(sunX, sunY), sunR * 0.85, _paint);
      _paint.color = const Color(0xFFD8D5B0).withValues(alpha: 0.8);
      canvas.drawCircle(Offset(sunX - sunR * 0.25, sunY - sunR * 0.15),
          sunR * 0.18, _paint);
      canvas.drawCircle(Offset(sunX + sunR * 0.3, sunY + sunR * 0.2),
          sunR * 0.13, _paint);
      // Twinkling stars.
      final starT = game.hero.z;
      for (var i = 0; i < 40; i++) {
        final sx = (i * 137.5) % w;
        final sy = (i * 89.3) % (_horizonY * 0.7);
        final tw = (math.sin(starT * 0.5 + i * 1.9) + 1.0) / 2.0;
        _paint.color =
            const Color(0xFFFFFFFF).withValues(alpha: 0.3 + 0.7 * tw);
        canvas.drawCircle(Offset(sx, sy), 1.0 + tw * 1.0, _paint);
      }
    }
  }

  void _drawGroundAndOcean(Canvas canvas, double w, double h, BiomePalette p) {
    final rect = Rect.fromLTWH(0, _horizonY, w, h - _horizonY);
    _paint
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [p.groundFar, p.ground],
      ).createShader(rect)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, _paint);
    _paint.shader = null;
    // Snow ground sparkle (Round 32): tiny star glints scattered on
    // the snow that twinkle as the car moves.
    if (game.biome == Biome.snow) {
      final sparkT = game.hero.z;
      _paint.style = PaintingStyle.fill;
      for (var i = 0; i < 24; i++) {
        final sx = ((i * 0.173 + sparkT * 0.002) % 1) * w;
        final sy = _horizonY + ((i * 0.311) % 1) * (h - _horizonY);
        final tw = (math.sin(sparkT * 0.9 + i * 1.7) + 1.0) / 2.0;
        _paint.color =
            const Color(0xFFFFFFFF).withValues(alpha: 0.15 + 0.6 * tw);
        canvas.drawCircle(Offset(sx, sy), 1.0 + tw * 1.5, _paint);
      }
    }
    if (p.ocean) {
      // Ocean on the left: animated sun-glitter stripes.
      final oceanPath = Path()
        ..moveTo(0, _horizonY)
        ..lineTo(w * 0.34, _horizonY)
        ..lineTo(w * 0.16, h)
        ..lineTo(0, h)
        ..close();
      _paint
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFF7A4A9E), Color(0xFF2E5F8A)],
        ).createShader(rect)
        ..style = PaintingStyle.fill;
      canvas.drawPath(oceanPath, _paint);
      _paint.shader = null;
      _paint
        ..color = const Color(0xFFFFD166).withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      // Glitter path: a shimmering column directly under the sun
      // (sun sits at w * 0.28 over the ocean — see _drawSky).
      final t = game.hero.z;
      for (var i = 0; i < 5; i++) {
        final yy = _horizonY + 30 + ((t * 3 + i * 90) % (h - _horizonY - 60));
        final xx = w * 0.16 + (i % 3) * w * 0.05;
        canvas.drawLine(
          Offset(xx, yy),
          Offset(xx + 70 + i * 14, yy),
          _paint..strokeWidth = 2.0,
        );
      }
      // Animated ocean waves (Round 13): slow sine swells rolling
      // across the water + twinkling sun sparkles on the swell crests.
      final waveT = game.hero.z;
      _paint
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (var i = 0; i < 3; i++) {
        final yy = _horizonY + 60.0 + i * 70.0;
        final wave = Path()..moveTo(0, yy);
        for (var sx = 0.0; sx <= w * 0.34; sx += 12.0) {
          wave.lineTo(
              sx, yy + math.sin(sx * 0.05 + waveT * 0.15 + i * 1.7) * 4.0);
        }
        canvas.drawPath(wave, _paint);
      }
      // Twinkles: bright flecks riding the glitter column.
      for (var i = 0; i < 6; i++) {
        final tw = (math.sin(waveT * 0.8 + i * 1.3) + 1.0) / 2.0;
        _paint
          ..color =
              const Color(0xFFFFE9A8).withValues(alpha: 0.15 + 0.5 * tw)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(
            Offset(w * (0.10 + (i % 3) * 0.07),
                _horizonY + 50.0 + i * 55.0),
            1.5 + tw * 1.5,
            _paint);
      }
    }
    // Distant silhouettes (mesas / city) on the horizon.
    _paint
      ..color = p.groundFar.withOpacity(0.9)
      ..style = PaintingStyle.fill;
    if (p.prop == 'canyon') {
      for (var i = 0; i < 4; i++) {
        final mx = w * (0.08 + i * 0.24);
        canvas.drawRect(
          Rect.fromLTWH(mx, _horizonY - 26 - (i % 2) * 14, w * 0.14, 30 + (i % 2) * 14),
          _paint,
        );
      }
    } else if (p.prop == 'city') {
      for (var i = 0; i < 7; i++) {
        final bx = w * (0.05 + i * 0.14);
        final bh = 20.0 + ((i * 37) % 46);
        canvas.drawRect(Rect.fromLTWH(bx, _horizonY - bh, w * 0.07, bh), _paint);
        // Skyline window lights (Round 27): warm dots in the night
        // buildings — the city is inhabited, not a black cutout.
        if (p.night) {
          final wx = bx + w * 0.035;
          if ((i * 7 + 3) % 3 != 0) {
            _paint.color = const Color(0xFFFFD166).withValues(alpha: 0.9);
            canvas.drawCircle(Offset(wx, _horizonY - bh * 0.55), 1.5, _paint);
          }
          if (i % 2 == 0) {
            _paint.color = const Color(0xFFFFF8DC).withValues(alpha: 0.7);
            canvas.drawCircle(Offset(wx, _horizonY - bh * 0.85), 1.2, _paint);
          }
          _paint.color = p.groundFar.withValues(alpha: 0.9);
        }
      }
    }
  }

  void _drawRoad(Canvas canvas, double w, double h, BiomePalette p) {
    final camX = _camX;
    final camZ = _camZ;
    final fovScale = game.cameraFx.fov / CameraFx.baseFov;
    final baseSeg = (camZ / Road.segmentLength).floor();
    // Far → near so nearer segments overdraw farther ones.
    for (var i = Road.drawSegments - 1; i >= 0; i--) {
      final z0 = (baseSeg + i) * Road.segmentLength;
      final z1 = z0 + Road.segmentLength;
      final ok1 = Road.project(_p1,
          worldX: -6.0, worldY: 0, worldZ: z0, camX: camX, camZ: camZ,
          width: w, height: h, fovScale: fovScale);
      final ok2 = Road.project(_p2,
          worldX: -6.0, worldY: 0, worldZ: z1, camX: camX, camZ: camZ,
          width: w, height: h, fovScale: fovScale);
      if (!ok1 || !ok2) continue;
      final fade = (i / Road.drawSegments).clamp(0.0, 1.0);
      final dark = (baseSeg + i) % 2 == 0;
      final roadColor = Color.lerp(
          dark ? p.roadDark : p.roadLight, p.fog, fade * 0.75)!;
      final x1l = _p1.x, x1r = _p1.x + _p1.w;
      final x2l = _p2.x, x2r = _p2.x + _p2.w;
      final path = Path()
        ..moveTo(x1l, _p1.y)
        ..lineTo(x2l, _p2.y)
        ..lineTo(x2r, _p2.y)
        ..lineTo(x1r, _p1.y)
        ..close();
      _paint
        ..color = roadColor
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, _paint);
      // Wet-road shine (Round 5 graphics): a glossy centre strip on the
      // nearest segments when the road is wet (Rain biome). Faint white,
      // so the lane dashes still read through it.
      if (p.wet && i < 8) {
        Road.project(_p,
            worldX: -2.0, worldY: 0, worldZ: z0, camX: camX, camZ: camZ,
            width: w, height: h, fovScale: fovScale);
        final s1l = _p.x;
        Road.project(_p,
            worldX: 2.0, worldY: 0, worldZ: z0, camX: camX, camZ: camZ,
            width: w, height: h, fovScale: fovScale);
        final s1r = _p.x;
        Road.project(_p,
            worldX: -2.0, worldY: 0, worldZ: z1, camX: camX, camZ: camZ,
            width: w, height: h, fovScale: fovScale);
        final s2l = _p.x;
        Road.project(_p,
            worldX: 2.0, worldY: 0, worldZ: z1, camX: camX, camZ: camZ,
            width: w, height: h, fovScale: fovScale);
        final s2r = _p.x;
        final shine = Path()
          ..moveTo(s1l, _p1.y)
          ..lineTo(s2l, _p2.y)
          ..lineTo(s2r, _p2.y)
          ..lineTo(s1r, _p1.y)
          ..close();
        _paint
          ..color = const Color(0xFFFFFFFF).withOpacity(0.07)
          ..style = PaintingStyle.fill;
        canvas.drawPath(shine, _paint);
      }
      // Lane dashes at x = −3, 0, +3 (skip the centre line every other
      // segment for the dashed look).
      if ((baseSeg + i) % 2 == 0) {
        for (final lx in [-3.0, 0.0, 3.0]) {
          Road.project(_p,
              worldX: lx, worldY: 0, worldZ: z0, camX: camX, camZ: camZ,
              width: w, height: h, fovScale: fovScale);
          final lx1 = _p.x;
          Road.project(_p,
              worldX: lx, worldY: 0, worldZ: z1, camX: camX, camZ: camZ,
              width: w, height: h, fovScale: fovScale);
          // Glowing lane dashes at night (Round 16): a soft blurred
          // halo under the crisp dash so the lanes read in the dark.
          if (p.night) {
            final glowColor = Color.lerp(p.line, p.fog, fade * 0.7)!;
            canvas.drawLine(
              Offset(lx1, _p1.y),
              Offset(_p.x, _p2.y),
              _linePaint
                ..color = glowColor.withValues(alpha: 0.5)
                ..strokeWidth = 7.0
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
            );
            _linePaint
              ..strokeWidth = 2.0
              ..maskFilter = null;
          }
          canvas.drawLine(
            Offset(lx1, _p1.y),
            Offset(_p.x, _p2.y),
            _linePaint..color = Color.lerp(p.line, p.fog, fade * 0.7)!,
          );
        }
      }
      // Edge lines.
      canvas.drawLine(
        Offset(x1l, _p1.y), Offset(x2l, _p2.y),
        _linePaint..color = const Color(0xFFFFFFFF).withOpacity(0.7),
      );
      canvas.drawLine(
        Offset(x1r, _p1.y), Offset(x2r, _p2.y),
        _linePaint..color = const Color(0xFFFFFFFF).withOpacity(0.7),
      );
      // Road surface detail (Round 15): cracks, patches and tar seams,
      // deterministic per segment so the road never repeats a pattern.
      if (i < 14) {
        final hash = _segHash(baseSeg + i);
        final midX = (x1l + x1r) / 2;
        final midY = (_p1.y + _p2.y) / 2;
        if (hash % 5 == 0) {
          // Crack: a jagged dark line across the lane.
          _linePaint.color = const Color(0xFF000000).withValues(alpha: 0.25);
          canvas.drawLine(Offset(midX - 12, midY - 4),
              Offset(midX + 2, midY + 2), _linePaint);
          canvas.drawLine(Offset(midX + 2, midY + 2),
              Offset(midX + 14, midY - 3), _linePaint);
        }
        if (hash % 7 == 0) {
          // Patch: a darker rectangle, slightly askew.
          _paint
            ..color = const Color(0xFF000000).withValues(alpha: 0.16)
            ..style = PaintingStyle.fill;
          canvas.drawRect(
              Rect.fromLTWH(midX - 20, midY - 3, 40, 6), _paint);
        }
        if (hash % 4 == 0) {
          // Tar seam: a short transverse seam near the left edge.
          _linePaint.color = const Color(0xFF000000).withValues(alpha: 0.30);
          canvas.drawLine(Offset(x1l + 4, midY), Offset(x1l + 26, midY + 2),
              _linePaint);
        }
      }
      // Heat-haze shimmer (Round 25): faint wobbling lines just above
      // the road near the horizon — hot air rising. Day biomes only.
      if (!p.night && i >= 39) {
        final hz = _horizonY + 8.0 + (i - 39) * 14.0;
        _paint
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.07)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        final haze = Path()..moveTo(w * 0.3, hz);
        for (var sx = w * 0.3; sx <= w * 0.7; sx += 16.0) {
          haze.lineTo(
              sx, hz + math.sin(sx * 0.05 + game.hero.z * 0.6 + i) * 2.0);
        }
        canvas.drawPath(haze, _paint);
      }
    }
    // Skid-mark trails (Round 52): dark tyre trails fading over 2 s.
    for (final s in game.skids) {
      final okA = Road.project(_p1,
          worldX: s.x, worldY: 0, worldZ: s.z, camX: camX, camZ: camZ,
          width: w, height: h, fovScale: fovScale);
      final okB = Road.project(_p2,
          worldX: s.x, worldY: 0, worldZ: s.z + 2.5, camX: camX, camZ: camZ,
          width: w, height: h, fovScale: fovScale);
      if (okA && okB) {
        _linePaint
          ..color = const Color(0xFF000000)
              .withValues(alpha: 0.35 * (s.life / 2.0).clamp(0.0, 1.0))
          ..strokeWidth = math.max(2.0, 6.0 * _p1.scale);
        canvas.drawLine(Offset(_p1.x, _p1.y), Offset(_p2.x, _p2.y), _linePaint);
      }
    }
    _linePaint.strokeWidth = 2.0;
    // Guardrail shine (Round 29): a metallic rail along both road
    // edges with posts flashing past — the highway edge reads.
    final nearZ = camZ + Road.segmentLength;
    final farZ = camZ + Road.segmentLength * 10;
    for (final side in [-1.0, 1.0]) {
      final okN = Road.project(_p1,
          worldX: side * 7.2, worldY: 0.8, worldZ: nearZ, camX: camX,
          camZ: camZ, width: w, height: h, fovScale: fovScale);
      final okF = Road.project(_p2,
          worldX: side * 7.2, worldY: 0.8, worldZ: farZ, camX: camX,
          camZ: camZ, width: w, height: h, fovScale: fovScale);
      if (okN && okF) {
        _linePaint
          ..color = const Color(0xFFB0BEC5).withValues(alpha: 0.8)
          ..strokeWidth = 3.0;
        canvas.drawLine(Offset(_p1.x, _p1.y), Offset(_p2.x, _p2.y), _linePaint);
        for (var s = 0; s < 5; s++) {
          final tz = nearZ + (farZ - nearZ) * s / 4;
          final okP = Road.project(_p,
              worldX: side * 7.2, worldY: 0.0, worldZ: tz, camX: camX,
              camZ: camZ, width: w, height: h, fovScale: fovScale);
          if (okP) {
            canvas.drawLine(
                Offset(_p.x, _p.y),
                Offset(_p.x, _p.y - 10 * _p.scale),
                _linePaint
                  ..color = const Color(0xFF78909C).withValues(alpha: 0.8));
          }
        }
      }
    }
    // Rain splash rings (Round 33): expanding ellipses on the road
    // where drops hit — only in the Rain biome (wet road).
    if (p.wet) {
      final splashT = game.hero.z;
      _paint.style = PaintingStyle.stroke;
      for (var i = 0; i < 6; i++) {
        final ph = (splashT * 0.35 + i * 0.17) % 1;
        final sx = w * (0.28 + ((i * 0.11) % 0.44));
        final sy = _horizonY + 40 + (i * 53) % 220;
        _paint
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.35 * (1 - ph))
          ..strokeWidth = 1.5;
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset(sx, sy),
                width: 6 + ph * 26,
                height: (6 + ph * 26) * 0.35),
            _paint);
      }
    }
    // Fog layers by biome depth (Round 56): two translucent bands —
    // a thin one hugging the horizon, a thicker one lower down — the
    // depth reads in fog-heavy biomes (rain/snow strongest).
    final fogStrength =
        p.wet ? 0.20 : (game.biome == Biome.snow ? 0.16 : 0.08);
    _paint
      ..color = p.fog.withValues(alpha: fogStrength)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawRect(Rect.fromLTWH(0, _horizonY - 10, w, 40), _paint);
    _paint.color = p.fog.withValues(alpha: fogStrength * 0.6);
    canvas.drawRect(Rect.fromLTWH(0, _horizonY + 60, w, 60), _paint);
    _paint.maskFilter = null;
    _linePaint.strokeWidth = 2.0;
  }

  void _drawProps(Canvas canvas, double w, double h, BiomePalette p) {
    final camX = _camX;
    final camZ = _camZ;
    final fovScale = game.cameraFx.fov / CameraFx.baseFov;
    final sorted = List<Prop>.from(game.road.props)
      ..sort((a, b) => b.z.compareTo(a.z));
    for (final prop in sorted) {
      final worldX = prop.side * (6.0 + prop.offset);
      final ok = Road.project(_p,
          worldX: worldX, worldY: 0, worldZ: prop.z, camX: camX, camZ: camZ,
          width: w, height: h, fovScale: fovScale);
      if (!ok) continue;
      final pxH = _p.scale * prop.height * (h / 2);
      if (pxH < 2) continue;
      final baseX = _p.x;
      final baseY = _p.y;
      switch (prop.kind) {
        case 'palm':
          _drawPalm(canvas, baseX, baseY, pxH, p.night, prop.phase);
          break;
        case 'cactus':
          _drawCactus(canvas, baseX, baseY, pxH);
          break;
        case 'rock':
          _drawRock(canvas, baseX, baseY, pxH);
          break;
        case 'mesa':
          _drawMesa(canvas, baseX, baseY, pxH, w);
          break;
        case 'building':
          _drawBuilding(canvas, baseX, baseY, pxH, p.night);
          break;
        case 'billboard':
          _drawBillboard(canvas, baseX, baseY, pxH, p.night);
          break;
        case 'pole':
          _drawPole(canvas, baseX, baseY, pxH, p.night);
          break;
        case 'pine': // Round 5: snow pine.
          _drawPine(canvas, baseX, baseY, pxH);
          break;
        case 'flower': // Round 30: coastal roadside flowers.
          _drawFlower(canvas, baseX, baseY, pxH, prop.phase);
          break;
      }
    }
  }

  void _drawPalm(Canvas canvas, double x, double y, double h, bool night,
      [double phase = 0.0]) {
    // Swaying fronds (Round 14): the whole crown leans with a slow
    // breeze that follows distance — palms feel alive, never cardboard.
    final sway = math.sin(game.hero.z * 0.03 + phase) * h * 0.04;
    final trunkW = math.max(1.5, h * 0.03);
    _paint
      ..color = const Color(0xFF5B3A29)
      ..style = PaintingStyle.fill;
    final trunk = Path()
      ..moveTo(x - trunkW / 2, y)
      ..lineTo(x - trunkW / 2 + sway * 0.5, y - h)
      ..lineTo(x + trunkW / 2 + sway * 0.5, y - h)
      ..lineTo(x + trunkW / 2, y)
      ..close();
    canvas.drawPath(trunk, _paint);
    // Backlit silhouette fronds: at golden hour the palms read almost
    // black against the sunset (like the reel) — never bright green.
    _paint
      ..color = night ? const Color(0xFF123527) : const Color(0xFF14352B)
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 5; i++) {
      final a = -math.pi * (0.15 + i * 0.175);
      final len = h * 0.32;
      canvas.drawLine(
        Offset(x + sway * 0.5, y - h),
        Offset(x + sway + math.cos(a) * len,
            y - h + math.sin(a) * len * 0.6),
        _paint..strokeWidth = math.max(1.5, h * 0.03),
      );
    }
  }

  /// Snow pine (Round 5): dark-green stacked triangles with a white
  /// snow cap on the top triangle.
  void _drawPine(Canvas canvas, double x, double y, double h) {
    _paint
      ..color = const Color(0xFF1B4D2E)
      ..style = PaintingStyle.fill;
    final w3 = math.max(2.0, h * 0.30);
    // Three stacked triangles, trunk at the bottom.
    canvas.drawPath(
      Path()
        ..moveTo(x, y - h)
        ..lineTo(x - w3 * 0.45, y - h * 0.62)
        ..lineTo(x + w3 * 0.45, y - h * 0.62)
        ..close(),
      _paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(x, y - h * 0.78)
        ..lineTo(x - w3 * 0.6, y - h * 0.34)
        ..lineTo(x + w3 * 0.6, y - h * 0.34)
        ..close(),
      _paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(x, y - h * 0.55)
        ..lineTo(x - w3 * 0.75, y - h * 0.05)
        ..lineTo(x + w3 * 0.75, y - h * 0.05)
        ..close(),
      _paint,
    );
    // Snow cap on the top triangle.
    _paint.color = const Color(0xFFFFFFFF);
    canvas.drawPath(
      Path()
        ..moveTo(x, y - h)
        ..lineTo(x - w3 * 0.18, y - h * 0.88)
        ..lineTo(x + w3 * 0.18, y - h * 0.88)
        ..close(),
      _paint,
    );
    // Trunk.
    _paint.color = const Color(0xFF4A3226);
    canvas.drawRect(Rect.fromLTWH(x - w3 * 0.06, y - h * 0.08, w3 * 0.12, h * 0.08), _paint);
  }

  void _drawCactus(Canvas canvas, double x, double y, double h) {
    _paint
      ..color = const Color(0xFF2E7D32)
      ..style = PaintingStyle.fill;
    final cw = math.max(2.0, h * 0.12);
    canvas.drawRect(Rect.fromLTWH(x - cw / 2, y - h, cw, h), _paint);
    canvas.drawRect(Rect.fromLTWH(x - cw * 1.1, y - h * 0.6, cw * 0.5, h * 0.25), _paint);
    canvas.drawRect(Rect.fromLTWH(x + cw * 0.6, y - h * 0.7, cw * 0.5, h * 0.3), _paint);
    // Cactus detail (Round 31): spine dots down the stem + a bloom on top.
    _paint.color = const Color(0xFFFFFFFF).withValues(alpha: 0.8);
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(
          Offset(x - cw * 0.25, y - h * (0.2 + i * 0.18)), 1.0, _paint);
      canvas.drawCircle(
          Offset(x + cw * 0.25, y - h * (0.28 + i * 0.18)), 1.0, _paint);
    }
    _paint.color = const Color(0xFFFF5A8A);
    canvas.drawCircle(
        Offset(x, y - h - h * 0.04), math.max(1.5, cw * 0.3), _paint);
  }

  void _drawRock(Canvas canvas, double x, double y, double h) {
    _paint
      ..color = const Color(0xFF6B4A3A)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(x - h * 0.5, y)
      ..lineTo(x - h * 0.15, y - h)
      ..lineTo(x + h * 0.4, y - h * 0.6)
      ..lineTo(x + h * 0.55, y)
      ..close();
    canvas.drawPath(path, _paint);
    // Rock detail (Round 31): a sunlit facet + a crack line.
    _paint.color = const Color(0xFF8D6E63).withValues(alpha: 0.8);
    final facet = Path()
      ..moveTo(x - h * 0.15, y - h)
      ..lineTo(x + h * 0.4, y - h * 0.6)
      ..lineTo(x + h * 0.1, y - h * 0.25)
      ..close();
    canvas.drawPath(facet, _paint);
    _paint
      ..color = const Color(0xFF3E2723).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(x - h * 0.3, y - h * 0.3),
        Offset(x + h * 0.2, y - h * 0.55), _paint);
  }

  void _drawMesa(Canvas canvas, double x, double y, double h, double w) {
    _paint
      ..color = const Color(0xFF7A3B22)
      ..style = PaintingStyle.fill;
    final mw = h * 1.6;
    final path = Path()
      ..moveTo(x - mw / 2, y)
      ..lineTo(x - mw * 0.32, y - h)
      ..lineTo(x + mw * 0.32, y - h)
      ..lineTo(x + mw / 2, y)
      ..close();
    canvas.drawPath(path, _paint);
  }

  void _drawBuilding(Canvas canvas, double x, double y, double h, bool night) {
    final bw = h * 0.45;
    _paint
      ..color = const Color(0xFF0D0D1A)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(x - bw / 2, y - h, bw, h), _paint);
    if (night) {
      _paint.color = const Color(0xFFFFD166).withOpacity(0.85);
      for (var row = 0; row < 6; row++) {
        for (var col = 0; col < 3; col++) {
          if ((row * 3 + col) % 2 == 0) {
            canvas.drawRect(
              Rect.fromLTWH(
                x - bw / 2 + 4 + col * (bw / 3),
                y - h + 6 + row * (h / 7),
                bw / 5,
                h / 12,
              ),
              _paint,
            );
          }
        }
      }
    }
  }

  void _drawBillboard(Canvas canvas, double x, double y, double h, bool night) {
    final bw = h * 0.7;
    final bh = h * 0.4;
    _paint
      ..color = const Color(0xFF1A1A24)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(x - bw / 2, y - h, bw, bh), _paint);
    _paint
      ..color = night ? const Color(0xFF00F0FF) : const Color(0xFFFF7E3D)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
        Rect.fromLTWH(x - bw * 0.4, y - h + bh * 0.25, bw * 0.8, bh * 0.18), _paint);
    canvas.drawRect(
        Rect.fromLTWH(x - bw * 0.4, y - h + bh * 0.55, bw * 0.55, bh * 0.14), _paint);
    // Neon glow (Round 28): at night the billboard hums — a blurred
    // glow behind the panel + a flickering neon border.
    if (night) {
      final flick = 0.75 + 0.25 * math.sin(game.hero.z * 0.4 + x * 0.01);
      _paint
        ..color = const Color(0xFF00F0FF).withValues(alpha: 0.25 * flick)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
        ..style = PaintingStyle.fill;
      canvas.drawRect(
          Rect.fromLTWH(x - bw / 2 - 4, y - h - 4, bw + 8, bh + 8), _paint);
      _paint.maskFilter = null;
      _paint
        ..color = const Color(0xFF00F0FF).withValues(alpha: 0.9 * flick)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawRect(Rect.fromLTWH(x - bw / 2, y - h, bw, bh), _paint);
    }
  }

  /// Roadside flowers (Round 30): a tuft of grass blades + three small
  /// bright blooms that bob gently with distance.
  void _drawFlower(Canvas canvas, double x, double y, double h, double phase) {
    final bob = math.sin(game.hero.z * 0.08 + phase) * h * 0.06;
    _paint
      ..color = const Color(0xFF4CAF50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, h * 0.05);
    for (var i = 0; i < 3; i++) {
      final bx = x + (i - 1) * h * 0.12;
      canvas.drawLine(Offset(bx, y), Offset(bx + bob, y - h * 0.7), _paint);
    }
    final bloomColors = [
      const Color(0xFFFF5A8A),
      const Color(0xFFFFD166),
      const Color(0xFFB388FF),
    ];
    _paint.style = PaintingStyle.fill;
    for (var i = 0; i < 3; i++) {
      final bx = x + (i - 1) * h * 0.12 + bob;
      _paint.color = bloomColors[i];
      canvas.drawCircle(Offset(bx, y - h * 0.7 - h * 0.1), h * 0.08, _paint);
    }
  }

  void _drawPole(Canvas canvas, double x, double y, double h, bool night) {
    _paint
      ..color = const Color(0xFF3A3A44)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(x - 1.5, y - h, 3, h), _paint);
    if (night) {
      _paint
        ..color = const Color(0xFFFFD166).withOpacity(0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(Offset(x, y - h), 4, _paint);
      _paint.maskFilter = null;
    }
  }

  void _drawCoins(Canvas canvas, double w, double h) {
    final camX = _camX;
    final camZ = _camZ;
    final fovScale = game.cameraFx.fov / CameraFx.baseFov;
    for (final coin in game.road.coins) {
      if (coin.taken) continue;
      final ok = Road.project(_p,
          worldX: coin.x, worldY: coin.y, worldZ: coin.z, camX: camX,
          camZ: camZ, width: w, height: h, fovScale: fovScale);
      if (!ok) continue;
      final r = math.max(2.0, _p.scale * 0.45 * (h / 2) * 0.12);
      final squish = math.cos(coin.spin).abs() * 0.7 + 0.3;
      _paint
        ..color = coin.air ? const Color(0xFF4FC3F7) : const Color(0xFFFFD166)
        ..style = PaintingStyle.fill;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(_p.x, _p.y), width: r * 2 * squish, height: r * 2),
        _paint,
      );
      _paint
        ..color = const Color(0xFFFFFFFF).withOpacity(0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(_p.x, _p.y), width: r * 2 * squish, height: r * 2),
        _paint,
      );
      // Spinning coin glint (Round 23): a white star flash as the coin
      // turns face-on — the spin reads as a gleam, not just a squash.
      if (squish > 0.9) {
        final gl = (squish - 0.9) / 0.1;
        final gs = r * 0.8;
        _linePaint
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9 * gl)
          ..strokeWidth = 2.0;
        canvas.drawLine(
            Offset(_p.x - gs, _p.y), Offset(_p.x + gs, _p.y), _linePaint);
        canvas.drawLine(
            Offset(_p.x, _p.y - gs), Offset(_p.x, _p.y + gs), _linePaint);
      }
    }
  }

  void _drawPickups(Canvas canvas, double w, double h) {
    final camX = _camX;
    final camZ = _camZ;
    final fovScale = game.cameraFx.fov / CameraFx.baseFov;
    for (final p in game.pickups) {
      if (p.taken) continue;
      final ok = Road.project(_p,
          worldX: p.x, worldY: 1.2 + math.sin(p.bob) * 0.4, worldZ: p.z,
          camX: camX, camZ: camZ, width: w, height: h, fovScale: fovScale);
      if (!ok) continue;
      final r = math.max(4.0, _p.scale * (h / 2) * 0.09);
      final isRocket = p.kind == 'rocket';
      _paint
        ..color = (isRocket ? const Color(0xFFFF7E3D) : const Color(0xFFFFD166))
            .withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(_p.x, _p.y), r * 1.6, _paint);
      _paint.maskFilter = null;
      _paint.color = isRocket ? const Color(0xFFFF7E3D) : const Color(0xFFFFD166);
      if (isRocket) {
        final path = Path()
          ..moveTo(_p.x, _p.y - r)
          ..lineTo(_p.x + r * 0.7, _p.y + r * 0.6)
          ..lineTo(_p.x, _p.y + r * 0.2)
          ..lineTo(_p.x - r * 0.7, _p.y + r * 0.6)
          ..close();
        canvas.drawPath(path, _paint);
      } else {
        canvas.drawCircle(Offset(_p.x, _p.y), r * 0.7, _paint);
      }
    }
  }

  void _drawRamps(Canvas canvas, double w, double h) {
    final camX = _camX;
    final camZ = _camZ;
    final fovScale = game.cameraFx.fov / CameraFx.baseFov;
    for (final r in game.ramps) {
      if (r.used) continue;
      final ok = Road.project(_p,
          worldX: r.x, worldY: 0, worldZ: r.z, camX: camX, camZ: camZ,
          width: w, height: h, fovScale: fovScale);
      if (!ok) continue;
      final rw = _p.scale * 3.0 * (w / 2);
      final rh = _p.scale * 1.2 * (h / 2);
      if (rw < 4) continue;
      final path = Path()
        ..moveTo(_p.x - rw / 2, _p.y)
        ..lineTo(_p.x + rw / 2, _p.y)
        ..lineTo(_p.x + rw / 2, _p.y - rh * 0.4)
        ..lineTo(_p.x - rw / 2, _p.y - rh)
        ..close();
      _paint
        ..color = const Color(0xFFFF7E3D)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, _paint);
      _paint
        ..color = const Color(0xFFFFD166)
        ..style = PaintingStyle.fill;
      canvas.drawRect(
          Rect.fromLTWH(_p.x - rw / 2, _p.y - rh - 3, rw, 3), _paint);
    }
  }

  void _drawTraffic(Canvas canvas, double w, double h, BiomePalette p) {
    final camX = _camX;
    final camZ = _camZ;
    final fovScale = game.cameraFx.fov / CameraFx.baseFov;
    final sorted = List<TrafficCar>.from(game.director.cars)
      ..sort((a, b) => b.z.compareTo(a.z));
    for (final c in sorted) {
      final ix = c.interpX(game._alpha);
      final iz = c.interpZ(game._alpha);
      final ok = Road.project(_p,
          worldX: ix, worldY: 0, worldZ: iz, camX: camX, camZ: camZ,
          width: w, height: h, fovScale: fovScale);
      if (!ok) continue;
      final carW = _p.scale * c.width * (w / 2);
      final carH = _p.scale * c.height * (h / 2);
      if (carW < 3) continue;
      // Shadow.
      _paint
        ..color = const Color(0xFF000000).withOpacity(0.35)
        ..style = PaintingStyle.fill;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(_p.x, _p.y), width: carW * 1.05, height: carW * 0.12),
        _paint,
      );
      final top = _p.y - carH;
      final body = Rect.fromLTWH(_p.x - carW / 2, top, carW, carH);
      _paint.color = c.color;
      canvas.drawRect(body, _paint);
      // Rear window.
      _paint.color = const Color(0xFF101018);
      canvas.drawRect(
        Rect.fromLTWH(_p.x - carW * 0.36, top + carH * 0.08, carW * 0.72, carH * 0.28),
        _paint,
      );
      // Tail lights (bright when braking) — same-direction cars only.
      // Oncoming cars face the hero: they get headlights instead (below).
      if (!c.oncoming) {
        // Brake-light glow bloom (Round 19): a soft red halo around
        // the tail lights when braking + a red wash on the road.
        if (c.brakeLights) {
          _paint
            ..color = const Color(0xFFFF1744).withValues(alpha: 0.55)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(
              Offset(_p.x - carW * 0.36, top + carH * 0.68), carW * 0.22, _paint);
          canvas.drawCircle(
              Offset(_p.x + carW * 0.36, top + carH * 0.68), carW * 0.22, _paint);
          _paint.maskFilter = null;
          _paint.color = const Color(0xFFFF1744).withValues(alpha: 0.10);
          canvas.drawOval(
            Rect.fromCenter(
                center: Offset(_p.x, _p.y + carH * 0.05),
                width: carW * 1.3,
                height: carH * 0.25),
            _paint);
        }
        _paint.color = c.brakeLights
            ? const Color(0xFFFF1744)
            : const Color(0xFFB71C1C);
        canvas.drawRect(
            Rect.fromLTWH(_p.x - carW * 0.46, top + carH * 0.62, carW * 0.2, carH * 0.12), _paint);
        canvas.drawRect(
            Rect.fromLTWH(_p.x + carW * 0.26, top + carH * 0.62, carW * 0.2, carH * 0.12), _paint);
      }
      // Headlight glare (Round 4 graphics): oncoming cars shine their
      // headlights at the hero — soft glow, a light cone toward the camera,
      // and two bright lamps. Nothing else in the game glows like this.
      if (c.oncoming) {
        _paint
          ..color = const Color(0xFFFFF8DC).withOpacity(0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(
            Offset(_p.x, _p.y - carH * 0.3), carW * 0.9, _paint);
        _paint.maskFilter = null;
        final cone = Path()
          ..moveTo(_p.x - carW * 0.4, _p.y - carH * 0.2)
          ..lineTo(_p.x + carW * 0.4, _p.y - carH * 0.2)
          ..lineTo(_p.x + carW * 1.1, h)
          ..lineTo(_p.x - carW * 1.1, h)
          ..close();
        _paint.color = const Color(0xFFFFF8DC).withOpacity(0.10);
        canvas.drawPath(cone, _paint);
        _paint.color = const Color(0xFFFFFFE0);
        canvas.drawCircle(
            Offset(_p.x - carW * 0.3, _p.y - carH * 0.25), carW * 0.07, _paint);
        canvas.drawCircle(
            Offset(_p.x + carW * 0.3, _p.y - carH * 0.25), carW * 0.07, _paint);
      }
      // Indicators (blink before a lane change — fair warning, SPEC §5.5).
      if (c.indicatorLeft || c.indicatorRight) {
        // Indicator blink glow (Round 37): the amber lamp blinks with
        // distance + a soft glow halo so the warning reads from afar.
        final blink = (math.sin(game.hero.z * 0.6) + 1.0) / 2.0;
        final ix0 = c.indicatorLeft ? _p.x - carW * 0.46 : _p.x + carW * 0.26;
        final icx = ix0 + carW * 0.1;
        final icy = top + carH * 0.5;
        _paint
          ..color = const Color(0xFFFFA000).withValues(alpha: 0.5 * blink)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(icx, icy), carW * 0.2, _paint);
        _paint.maskFilter = null;
        _paint.color =
            const Color(0xFFFFA000).withValues(alpha: 0.35 + 0.65 * blink);
        canvas.drawRect(
            Rect.fromLTWH(ix0, top + carH * 0.45, carW * 0.2, carH * 0.1), _paint);
      }
      // Wheels.
      _paint.color = const Color(0xFF0D0D12);
      canvas.drawRect(
          Rect.fromLTWH(_p.x - carW * 0.48, _p.y - carH * 0.14, carW * 0.12, carH * 0.14), _paint);
      canvas.drawRect(
          Rect.fromLTWH(_p.x + carW * 0.36, _p.y - carH * 0.14, carW * 0.12, carH * 0.14), _paint);
    }
  }

  void _drawHero(Canvas canvas, double w, double h, BiomePalette p) {
    final hero = game.hero;
    final camX = _camX;
    final camZ = _camZ;
    final fovScale = game.cameraFx.fov / CameraFx.baseFov;
    final ix = hero.interpX(game._alpha);
    final iy = hero.interpY(game._alpha);
    final iz = hero.prevZ + (hero.z - hero.prevZ) * game._alpha;
    final ok = Road.project(_p,
        worldX: ix, worldY: 0, worldZ: iz, camX: camX, camZ: camZ,
        width: w, height: h, fovScale: fovScale);
    if (!ok) return;
    final carW = _p.scale * 2.0 * (w / 2);
    final liftPx = iy * _p.scale * (h / 2);
    final baseY = _p.y - liftPx;
    // Tumble during the crash (visual only).
    final stuntRoll = game.stunts.rollAngle + game._tumbleRoll;
    final stuntPitch = game.stunts.pitchAngle;
    hero.drawShadow(canvas, _p.x, _p.y, carW, iy);
    // Reflection on the road (Round 17): a faint mirrored copy of the
    // car on the asphalt, as if the road were freshly rained on. Only
    // while the car is level on the ground — a rolling car has no clean
    // mirror image.
    if (hero.onGround &&
        stuntRoll.abs() < 0.05 &&
        stuntPitch.abs() < 0.05) {
      final reflH = carW * 0.62;
      canvas.saveLayer(
        Rect.fromLTWH(
            _p.x - carW, baseY - reflH * 0.2, carW * 2, reflH * 0.7),
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.13),
      );
      canvas.translate(_p.x, baseY + 2);
      canvas.scale(1.0, -0.45);
      canvas.translate(-_p.x, -(baseY + 2));
      hero.draw(
        canvas,
        _p.x,
        baseY,
        carW,
        0.0,
        0.0,
        night: p.night,
        paintColor: _paintColorFor(hero.skin, hero.paint),
      );
      canvas.restore();
    }
    hero.draw(
      canvas,
      _p.x,
      baseY,
      carW,
      stuntRoll,
      stuntPitch,
      night: p.night,
      paintColor: _paintColorFor(hero.skin, hero.paint),
    );
    // Starman golden aura rings (Round 40): expanding gold rings pulse
    // out from the car while Starman is active.
    if (hero.starmanTime > 0) {
      final auT = game.hero.z;
      for (var i = 0; i < 2; i++) {
        final ph = (auT * 0.4 + i * 0.5) % 1;
        final rr = carW * (0.6 + ph * 0.5);
        _paint
          ..color = const Color(0xFFFFD166).withValues(alpha: 0.6 * (1 - ph))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset(_p.x, baseY - carW * 0.3),
                width: rr * 2,
                height: rr * 1.1),
            _paint);
      }
    }
    // Headlight pools at night (Round 18): the hero's headlights face
    // away from the camera, so they read as two light pools thrown onto
    // the road far ahead + a soft glow where they land.
    if (p.night) {
      final carH = carW * 0.62;
      final okL = Road.project(_p1,
          worldX: ix - 1.2, worldY: 0, worldZ: iz + 30, camX: camX,
          camZ: camZ, width: w, height: h, fovScale: fovScale);
      final okR = Road.project(_p2,
          worldX: ix + 1.2, worldY: 0, worldZ: iz + 30, camX: camX,
          camZ: camZ, width: w, height: h, fovScale: fovScale);
      if (okL && okR) {
        final beam = Path()
          ..moveTo(_p.x - carW * 0.30, baseY - carH * 0.10)
          ..lineTo(_p1.x, _p1.y)
          ..lineTo(_p2.x, _p2.y)
          ..lineTo(_p.x + carW * 0.30, baseY - carH * 0.10)
          ..close();
        _paint
          ..color = const Color(0xFFFFF8DC).withValues(alpha: 0.08)
          ..style = PaintingStyle.fill;
        canvas.drawPath(beam, _paint);
        _paint
          ..color = const Color(0xFFFFF8DC).withValues(alpha: 0.14)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
        canvas.drawCircle(
            Offset((_p1.x + _p2.x) / 2, (_p1.y + _p2.y) / 2),
            carW * 0.35,
            _paint);
        _paint.maskFilter = null;
      }
    }
  }

  Color _paintColorFor(String skin, String paint) {
    switch (paint) {
      case 'black':
        return const Color(0xFF1A1A1F);
      case 'red':
        return const Color(0xFFD32F2F);
      case 'blue':
        return const Color(0xFF1565C0);
      case 'gold':
        return const Color(0xFFFFC531);
      case 'pink':
        return const Color(0xFFEC407A);
      case 'neon':
        return const Color(0xFF00F0FF);
      case 'teal':
        return const Color(0xFF00897B);
      case 'purple':
        return const Color(0xFF7E57C2);
      case 'orange':
        return const Color(0xFFFF7043);
      case 'lime':
        return const Color(0xFF9CCC65);
      case 'silver':
        return const Color(0xFFB0BEC5);
      case 'navy':
        return const Color(0xFF1A237E);
      default:
        return const Color(0xFFF5F5F5);
    }
  }

  /// Police car (Round 1): drawn BEHIND the hero, closing in. Black body,
  /// white doors, light bar flashing red/blue. Phase flips with hero.z so
  /// the strobe reads even on a still frame.
  /// NOTE: the chase camera sits 7.5 m behind the hero, so a police car
  /// 40 m back is BEHIND the camera and the projection culls it. When it
  /// is far, the strobe bars + HUD banner carry the chase; when it closes
  /// inside 15 m it is drawn large at the bottom of the frame, right on
  /// the hero's tail — growing as it gets closer, so the bust is visible.
  void _drawPolice(Canvas canvas, double w, double h) {
    final hero = game.hero;
    final police = game.police;
    if (!police.active) return;
    final camX = _camX;
    final camZ = _camZ;
    final fovScale = game.cameraFx.fov / CameraFx.baseFov;
    final phase = (game.hero.z * 2).floor() % 2 == 0;
    if (police.behind > 15.0) return; // strobe + HUD carry the far chase
    final ok = Road.project(_p,
        worldX: hero.interpX(game._alpha), worldY: 0,
        worldZ: hero.z - police.behind, camX: camX, camZ: camZ,
        width: w, height: h, fovScale: fovScale);
    // Projected when barely ahead of the camera, else drawn at the bottom
    // edge (on the tail) with size growing as `behind` shrinks.
    final double px;
    final double py;
    final double carW;
    final double carH;
    if (ok) {
      px = _p.x;
      py = _p.y;
      carW = _p.scale * 2.0 * (w / 2);
      carH = _p.scale * 1.45 * (h / 2);
    } else {
      final closeness = (1.0 - (police.behind - 2.5) / 12.5).clamp(0.0, 1.0);
      px = w / 2 + (hero.interpX(game._alpha) - camX) * w * 0.06;
      py = h * (0.86 + 0.07 * closeness);
      carW = w * (0.28 + 0.30 * closeness);
      carH = carW * 0.72;
    }
    if (carW < 3) return;
    final top = py - carH;
    // Shadow.
    _paint
      ..color = const Color(0xFF000000).withOpacity(0.35)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(px, py), width: carW * 1.05, height: carW * 0.12),
      _paint,
    );
    // Black body, white doors.
    _paint.color = const Color(0xFF111116);
    canvas.drawRect(Rect.fromLTWH(px - carW / 2, top, carW, carH), _paint);
    _paint.color = const Color(0xFFF5F5F5);
    canvas.drawRect(
        Rect.fromLTWH(px - carW * 0.30, top + carH * 0.30, carW * 0.60, carH * 0.45),
        _paint);
    // Light bar: red on the left, blue on the right, alternating bright.
    _paint.color = phase ? const Color(0xFFFF1744) : const Color(0xFFFF1744).withOpacity(0.35);
    canvas.drawRect(
        Rect.fromLTWH(px - carW * 0.42, top + carH * 0.05, carW * 0.38, carH * 0.14),
        _paint);
    _paint.color = phase ? const Color(0xFF2979FF).withOpacity(0.35) : const Color(0xFF2979FF);
    canvas.drawRect(
        Rect.fromLTWH(px + carW * 0.04, top + carH * 0.05, carW * 0.38, carH * 0.14),
        _paint);
    // "POLICE" text bar on the rear.
    _paint.color = const Color(0xFF111116);
    canvas.drawRect(
        Rect.fromLTWH(px - carW * 0.40, top + carH * 0.78, carW * 0.80, carH * 0.16),
        _paint);
  }

  /// Red/blue strobe bars at the screen edges while a chase is active
  /// (Round 1 graphics). Alternates sides with hero.z so it pulses.
  // Police strobe wash (Round 38): the flashing bars now also throw a
  // pulsing red/blue wash across the road surface ahead of the car.
  void _drawPoliceStrobe(Canvas canvas, double w, double h) {
    if (!game.police.active ||
        game.runState != RunState.playing) return;
    final phase = (game.hero.z * 2).floor() % 2 == 0;
    final left = phase ? const Color(0xFFFF1744) : const Color(0xFF2979FF);
    final right = phase ? const Color(0xFF2979FF) : const Color(0xFFFF1744);
    _paint
      ..color = left.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.03, h), _paint);
    _paint.color = right.withValues(alpha: 0.28);
    canvas.drawRect(Rect.fromLTWH(w * 0.97, 0, w * 0.03, h), _paint);
    // Wash on the road: alternating red/blue radial glow at the bottom.
    final wash = phase ? left : right;
    _paint
      ..color = wash.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    canvas.drawCircle(Offset(w * 0.5, h * 0.95), w * 0.4, _paint);
    _paint.maskFilter = null;
  }

  void _drawParticles(Canvas canvas, double w, double h) {
    final camX = _camX;
    final camZ = _camZ;
    final fovScale = game.cameraFx.fov / CameraFx.baseFov;
    for (final pt in game.particles) {
      final ok = Road.project(_p,
          worldX: pt.x, worldY: pt.y, worldZ: pt.z, camX: camX, camZ: camZ,
          width: w, height: h, fovScale: fovScale);
      if (!ok) continue;
      final r = math.max(1.0, _p.scale * pt.size * (h / 2) * 0.1);
      _paint
        ..color = pt.color.withOpacity((pt.life / pt.maxLife).clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      // Shaped pieces + flutter (Round 42): confetti falls as
      // rectangles + triangles that wobble side to side.
      if (pt.shape == 1) {
        final fx =
            _p.x + math.sin(pt.life * 8 + pt.flutter * 3) * pt.flutter * 3;
        canvas.save();
        canvas.translate(fx, _p.y);
        canvas.rotate(pt.life * 4 + pt.flutter);
        canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: r * 1.6, height: r),
            _paint);
        canvas.restore();
      } else if (pt.shape == 2) {
        final fx =
            _p.x + math.sin(pt.life * 8 + pt.flutter * 3) * pt.flutter * 3;
        final tri = Path()
          ..moveTo(fx, _p.y - r)
          ..lineTo(fx - r, _p.y + r)
          ..lineTo(fx + r, _p.y + r)
          ..close();
        canvas.drawPath(tri, _paint);
      } else {
        canvas.drawCircle(Offset(_p.x, _p.y), r, _paint);
      }
    }
  }

  // Speed lines (Round 24 polish): two layers — faint long trails +
  // bright short streaks — curved and radiating from the vanishing
  // point so speed reads as motion toward the horizon.
  void _drawSpeedLines(Canvas canvas, double w, double h) {
    final speed = game.hero.speed;
    if (speed < 40 || game.runState != RunState.playing) return;
    final strength = ((speed - 40) / 12).clamp(0.0, 1.0);
    final vp = Offset(w * 0.5, _horizonY);
    for (var layer = 0; layer < 2; layer++) {
      final n = (layer == 0 ? 6 : 10) + (strength * 8).round();
      for (var i = 0; i < n; i++) {
        final phase = i * 137.5 + layer * 61.0 + game.hero.z * 3;
        final x = (phase % 1) * w;
        final y = ((i * 0.37 + layer * 0.13) % 1) * h;
        final d = Offset(x - vp.dx, y - vp.dy);
        final dl = d.distance == 0 ? 1.0 : d.distance;
        final unit = d / dl;
        final len = (layer == 0 ? 60.0 : 30.0) + strength * 90;
        final end = Offset(x, y) + unit * len;
        final ctrl = Offset(x, y) + unit * (len * 0.5) +
            Offset(-unit.dy, unit.dx) * (len * 0.08);
        final path = Path()
          ..moveTo(x, y)
          ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
        _paint
          ..color = const Color(0xFFFFFFFF).withValues(
              alpha: (layer == 0 ? 0.10 : 0.30) * strength)
          ..style = PaintingStyle.stroke
          ..strokeWidth = layer == 0 ? 1.5 : 2.5;
        canvas.drawPath(path, _paint);
      }
    }
    // Tunnel of light on nitro (Round 51): bright streaks converge on
    // the vanishing point while nitro burns.
    if (game.hero.nitroTime > 0) {
      _paint.style = PaintingStyle.stroke;
      for (var i = 0; i < 12; i++) {
        final a = (i / 12) * math.pi * 2 + game.hero.z * 0.05;
        final sx = vp.dx + math.cos(a) * w * 0.55;
        final sy = vp.dy + math.sin(a) * h * 0.55;
        _paint
          ..color = const Color(0xFFFFF8DC).withValues(alpha: 0.35)
          ..strokeWidth = 2.0;
        canvas.drawLine(
            Offset(sx, sy),
            Offset(
                vp.dx + (sx - vp.dx) * 0.25, vp.dy + (sy - vp.dy) * 0.25),
            _paint);
      }
    }
  }

  /// Cinema frame (Round 10 graphics): black letterbox bars + a subtle
  /// flickering film grain. Drawn last so the bars sit over everything.
  void _drawCinemaFrame(Canvas canvas, double w, double h) {
    final barH = h * 0.10;
    _paint
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, barH), _paint);
    canvas.drawRect(Rect.fromLTWH(0, h - barH, w, barH), _paint);
    // Film grain: sparse white specks whose positions change every frame,
    // so the grain shimmers like film instead of sitting still.
    final ms = DateTime.now().millisecondsSinceEpoch;
    _paint.color = const Color(0xFFFFFFFF).withOpacity(0.05);
    for (var i = 0; i < 90; i++) {
      final gx = ((i * 7919 + ms * 13) % (w * 100).toInt()) / 100.0;
      final gy = ((i * 104729 + ms * 7) % (h * 100).toInt()) / 100.0;
      canvas.drawCircle(Offset(gx, gy), 1.2, _paint);
    }
  }

  void _drawVignette(Canvas canvas, double w, double h) {
    final rect = Rect.fromLTWH(0, 0, w, h);
    _paint
      ..shader = RadialGradient(
        center: const Alignment(0.5, 0.45),
        radius: 0.85,
        colors: const [Color(0x00000000), Color(0x66000000)],
        stops: const [0.6, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, _paint);
    _paint.shader = null;
    // Colour grade per biome (Round 58): each biome tints the frame —
    // warm gold for coastal dusk, cyan for neon night, ember for
    // canyon, amber for desert, cold blue for snow, slate for rain.
    final grade = switch (game.biome) {
      Biome.neon => const Color(0xFF00F0FF),
      Biome.canyon => const Color(0xFFFF7E3D),
      Biome.desert => const Color(0xFFFFB347),
      Biome.snow => const Color(0xFFB3E5FC),
      Biome.rain => const Color(0xFF607D8B),
      _ => const Color(0xFFFFC531),
    };
    final gradeAlpha = game.biome == Biome.coastal ? 0.10 : 0.12;
    _paint
      ..shader = RadialGradient(
        center: const Alignment(0.5, 0.45),
        radius: 0.9,
        colors: [
          grade.withValues(alpha: 0.0),
          grade.withValues(alpha: gradeAlpha),
        ],
        stops: const [0.55, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, _paint);
    _paint.shader = null;

    // Red pulse (Round 6 graphics): last 10 s of a Time Trial — the
    // screen edges throb red as the clock runs out.
    if (game.timeTrial &&
        game.timeLeft <= 10.0 &&
        game.runState == RunState.playing) {
      final pulse = 0.10 +
          0.08 *
              math.sin(
                  DateTime.now().millisecondsSinceEpoch / 1000.0 * 6.0);
      _paint
        ..shader = RadialGradient(
          center: const Alignment(0.5, 0.45),
          radius: 0.85,
          colors: [
            const Color(0x00000000),
            Color(0xFFFF0000).withOpacity(pulse)
          ],
          stops: const [0.55, 1.0],
        ).createShader(rect)
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, _paint);
      _paint.shader = null;
    }
  }
}
