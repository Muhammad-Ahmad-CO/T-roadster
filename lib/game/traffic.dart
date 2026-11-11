import 'dart:math' as math;
import 'dart:ui';

import 'road.dart';

/// Traffic AI (SPEC §5.5, game-ai skill).
/// Each car is a tiny FSM — Cruise → Brake → LaneChange → Queue.
/// Decision is separated from steering: the FSM outputs an intent
/// (target lane / target speed) and the steering layer moves the car
/// toward it with an "arrive" profile. Recompute on a 0.25 s timer,
/// never every frame. Traffic never collides with traffic — cars use
/// the FSM gaps, not physics (collision layers, §13.4).
enum TrafficState { cruise, brake, laneChange, queue }

enum TrafficType { sedan, hatchback, van, truck, semi }

class TrafficCar {
  TrafficCar({
    required this.type,
    required this.lane,
    required this.z,
    required this.speed,
    required this.color,
    this.oncoming = false,
  })  : x = Road.laneCentres[lane],
        length = _lengthOf(type),
        width = _widthOf(type),
        height = _heightOf(type),
        targetX = Road.laneCentres[lane];

  final TrafficType type;
  int lane;
  double x;
  double z;
  double speed;

  /// Wrong-Way mode (Round 4): true = the car drives AT the hero
  /// (moves in −z). Oncoming cars never change lanes — they hold their
  /// lane at spawn speed, so the director's guaranteed open lane stays open.
  final bool oncoming;
  final double length;
  final double width;
  final double height;
  final Color color;

  TrafficState state = TrafficState.cruise;
  double targetX;
  double targetSpeed = 20.0;
  double _decideTimer = 0.0;
  double _signalTimer = 0.0; // indicator blink before a lane change
  int _signalDir = 0; // −1 left, +1 right, 0 none
  double _laneChangeCooldown = 0.0;
  double _laneChangeTime = 0.0;
  bool brakeLights = false;
  bool indicatorLeft = false;
  bool indicatorRight = false;
  bool passed = false; // hero has gone past (near-miss / hop-over scoring)
  bool hopCounted = false;
  double nearMissCooldown = 0.0;

  // Render interpolation.
  double prevX = 0.0, prevZ = 0.0;

  static double _lengthOf(TrafficType t) {
    switch (t) {
      case TrafficType.sedan:
        return 4.2;
      case TrafficType.hatchback:
        return 3.9;
      case TrafficType.van:
        return 5.0;
      case TrafficType.truck:
        return 7.5;
      case TrafficType.semi:
        return 11.0;
    }
  }

  static double _widthOf(TrafficType t) =>
      t == TrafficType.semi ? 2.5 : 2.0;

  static double _heightOf(TrafficType t) {
    switch (t) {
      case TrafficType.sedan:
        return 1.45;
      case TrafficType.hatchback:
        return 1.5;
      case TrafficType.van:
        return 2.1;
      case TrafficType.truck:
        return 3.0;
      case TrafficType.semi:
        return 3.6;
    }
  }

  void snapshot() {
    prevX = x;
    prevZ = z;
  }

  double interpX(double alpha) => prevX + (x - prevX) * alpha;
  double interpZ(double alpha) => prevZ + (z - prevZ) * alpha;

  /// One fixed-timestep tick. [others] are the other traffic cars (for the
  /// gap checks). The car moves in world z at its own speed; the hero
  /// closes the gap because the hero is faster.
  void update(double dt, List<TrafficCar> others) {
    _decideTimer -= dt;
    if (_laneChangeCooldown > 0) _laneChangeCooldown -= dt;
    if (nearMissCooldown > 0) nearMissCooldown -= dt;

    // Oncoming cars (Round 4): drive straight at the hero in −z, hold
    // their lane and speed. No FSM, no lane changes — the open lane the
    // director left is the survivable line.
    if (oncoming) {
      z -= speed * dt;
      brakeLights = false;
      return;
    }

    if (_decideTimer <= 0) {
      _decideTimer = 0.25; // recompute gaps on a timer, not every frame
      _decide(others);
    }

    // Indicator: blink 0.5 s before the lane change starts (fair warning).
    if (_signalTimer > 0) {
      _signalTimer -= dt;
      final blink = (_signalTimer * 10).floor() % 2 == 0;
      indicatorLeft = _signalDir < 0 && blink;
      indicatorRight = _signalDir > 0 && blink;
      if (_signalTimer <= 0) {
        _laneChangeTime = 1.2;
        state = TrafficState.laneChange;
        lane += _signalDir;
        targetX = Road.laneCentres[lane.clamp(0, 3)];
      }
    }

    if (state == TrafficState.laneChange) {
      _laneChangeTime -= dt;
      // "Arrive" steering: ease into the next lane centre.
      x += (targetX - x) * math.min(1.0, dt * 2.2);
      if (_laneChangeTime <= 0 || (targetX - x).abs() < 0.05) {
        x = targetX;
        state = TrafficState.cruise;
        indicatorLeft = false;
        indicatorRight = false;
      }
    } else {
      x += (targetX - x) * math.min(1.0, dt * 1.5);
    }

    // Speed: ease toward the target speed for the current state.
    speed += (targetSpeed - speed) * math.min(1.0, dt * 1.2);
    z += speed * dt;
    brakeLights = state == TrafficState.brake || state == TrafficState.queue;
  }

  void _decide(List<TrafficCar> others) {
    // Car ahead in my lane?
    TrafficCar? ahead;
    var aheadGap = double.infinity;
    for (final o in others) {
      if (o == this || o.lane != lane) continue;
      final gap = o.z - z - (o.length + length) / 2;
      if (gap > 0 && gap < aheadGap) {
        aheadGap = gap;
        ahead = o;
      }
    }

    if (ahead != null && aheadGap < 25.0) {
      // Blocked ahead: brake, and try a lane change if a ≥18 m gap exists.
      if (_laneChangeCooldown <= 0 && state != TrafficState.laneChange) {
        for (final dir in [1, -1]) {
          final nextLane = lane + dir;
          if (nextLane < 0 || nextLane > 3) continue;
          var gapOk = true;
          for (final o in others) {
            if (o == this || o.lane != nextLane) continue;
            if ((o.z - z).abs() < 18.0) gapOk = false;
          }
          if (gapOk) {
            _signalDir = dir;
            _signalTimer = 0.5;
            _laneChangeCooldown = 4.0; // max 1 lane change per 4 s
            state = TrafficState.brake;
            targetSpeed = math.max(5.0, ahead.speed);
            return;
          }
        }
      }
      state = TrafficState.brake;
      targetSpeed = math.max(5.0, ahead.speed);
      return;
    }

    // Jam: crawl at 5–8 m/s when bunched (set by the spawn director via
    // targetSpeed on queue members).
    if (state == TrafficState.queue) {
      targetSpeed = 6.0;
      return;
    }

    state = TrafficState.cruise;
    targetSpeed = speed; // hold current speed; set at spawn
  }
}

/// Spawn director (SPEC §5.5–§5.6): density rises with distance, patterns
/// never seal all 4 lanes — there is ALWAYS at least one survivable line
/// (a free lane, or a flyable gap). A spawn that seals all lanes with no
/// air window is a bug, so a final fairness guard removes one car.
class SpawnDirector {
  final math.Random _rand = math.Random();
  final List<TrafficCar> cars = [];
  double _nextSpawnZ = 120.0;

  /// Wrong-Way mode (Round 4): when true every spawned car is oncoming.
  bool wrongWay = false;

  static const _mutedPalette = <Color>[
    Color(0xFF9AA0A6),
    Color(0xFF5F6368),
    Color(0xFF1F2430),
    Color(0xFF2E4A6B),
    Color(0xFFC9B18C),
    Color(0xFF8C2F39),
    Color(0xFFD7D7D7),
  ];

  /// Cars per metre at this distance (SPEC §5.6 ramp table).
  double _density(double distance) {
    if (distance < 300) return 1 / 60;
    if (distance < 800) return 1 / 42;
    if (distance < 1500) return 1 / 30;
    if (distance < 2500) return 1 / 22;
    return 1 / 17;
  }

  void update(double heroZ, double heroDistance) {
    cars.removeWhere((c) => c.z < heroZ - 30);
    // Wrong-Way: 30% sparser spawns — closing speeds are much higher, so
    // the same density would be unfair.
    final spacing =
        (1 / _density(heroDistance)) * (wrongWay ? 1.3 : 1.0);
    while (_nextSpawnZ < heroZ + 220) {
      _spawnPattern(_nextSpawnZ, heroDistance);
      _nextSpawnZ += spacing * (0.8 + _rand.nextDouble() * 0.5);
    }
    _fairnessGuard(heroZ);
  }

  void _spawnPattern(double z, double distance) {
    final roll = _rand.nextDouble();
    final openLane = _rand.nextInt(4); // the guaranteed survivable lane
    if (distance < 300) {
      // Tutorial: single cars, wide gaps.
      _spawnCar(_rand.nextInt(4), z, TrafficType.sedan);
      return;
    }
    if (roll < 0.45) {
      // Pair in two lanes.
      final lanes = [0, 1, 2, 3]..shuffle(_rand);
      _spawnCar(lanes[0], z, _randomType(distance));
      _spawnCar(lanes[1], z + 6 + _rand.nextDouble() * 10, _randomType(distance));
    } else if (roll < 0.75) {
      // Triple — never in the open lane.
      for (var lane = 0; lane < 4; lane++) {
        if (lane == openLane) continue;
        _spawnCar(lane, z + _rand.nextDouble() * 8, _randomType(distance));
      }
    } else if (roll < 0.9) {
      // Queue: 3-car jam, bunched, one lane open — fly over or thread it.
      for (var lane = 0; lane < 4; lane++) {
        if (lane == openLane) continue;
        final car = _spawnCar(lane, z, _randomType(distance));
        car.state = TrafficState.queue;
        car.targetSpeed = 6.0;
      }
    } else {
      // Long truck / semi wall with a gap lane.
      for (var lane = 0; lane < 4; lane++) {
        if (lane == openLane) continue;
        _spawnCar(lane, z, distance > 800 ? TrafficType.semi : TrafficType.truck);
      }
    }
  }

  TrafficType _randomType(double distance) {
    final roll = _rand.nextDouble();
    if (roll < 0.40) return TrafficType.sedan;
    if (roll < 0.60) return TrafficType.hatchback;
    if (roll < 0.75) return TrafficType.van;
    if (roll < 0.90) return TrafficType.truck;
    if (distance > 800) return TrafficType.semi;
    return TrafficType.sedan;
  }

  TrafficCar _spawnCar(int lane, double z, TrafficType type) {
    final baseSpeed = switch (type) {
      TrafficType.sedan => 16.0 + _rand.nextDouble() * 6.0,
      TrafficType.hatchback => 18.0 + _rand.nextDouble() * 6.0,
      TrafficType.van => 15.0 + _rand.nextDouble() * 5.0,
      TrafficType.truck => 13.0 + _rand.nextDouble() * 5.0,
      TrafficType.semi => 12.0 + _rand.nextDouble() * 4.0,
    };
    // Never spawn two adjacent cars in the same colour.
    Color color = _mutedPalette[_rand.nextInt(_mutedPalette.length)];
    final nearby = cars.where((c) => (c.z - z).abs() < 12).toList();
    var guard = 0;
    while (nearby.any((c) => c.color == color) && guard < 6) {
      color = _mutedPalette[_rand.nextInt(_mutedPalette.length)];
      guard++;
    }
    final car = TrafficCar(
      type: type,
      lane: lane,
      z: z,
      // Oncoming cars (Round 4) drive at the hero at 14–20 m/s, so the
      // closing speed is hero speed + this — fast, but the spawn is 220 m
      // ahead and the density is sparser.
      speed: wrongWay ? 14.0 + _rand.nextDouble() * 6.0 : baseSpeed,
      color: color,
      oncoming: wrongWay,
    );
    car.targetSpeed = baseSpeed;
    cars.add(car);
    return car;
  }

  /// Final guard: scan the next 80 m; if every lane is blocked inside one
  /// 12 m slice, remove the car in the lane with the fewest cars.
  void _fairnessGuard(double heroZ) {
    for (var sliceStart = heroZ + 30; sliceStart < heroZ + 80; sliceStart += 12) {
      final blocked = <int, TrafficCar>{};
      for (final c in cars) {
        if (c.z >= sliceStart && c.z < sliceStart + 12) {
          blocked.putIfAbsent(c.lane, () => c);
        }
      }
      if (blocked.length == 4) {
        final laneCounts = <int, int>{};
        for (final c in cars) {
          laneCounts[c.lane] = (laneCounts[c.lane] ?? 0) + 1;
        }
        var weakestLane = 0;
        var weakestCount = 1 << 30;
        for (final lane in blocked.keys) {
          final n = laneCounts[lane] ?? 0;
          if (n < weakestCount) {
            weakestCount = n;
            weakestLane = lane;
          }
        }
        cars.remove(blocked[weakestLane]);
      }
    }
  }

  void reset() {
    cars.clear();
    _nextSpawnZ = 120.0;
  }
}
