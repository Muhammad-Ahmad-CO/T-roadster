import 'dart:math' as math;
import 'dart:ui';

/// The endless road (SPEC §5.1, §10) — Flame + custom pseudo-3D renderer.
/// OutRun-style projection: the road is drawn as projected segment
/// trapezoids, cars/props/coins are billboarded vector shapes scaled by
/// depth. No runtime 3D engine, no downloaded art — everything is drawn
/// in code, so the APK stays small and the F9 stays at 60 fps.
///
/// World units are metres. Lanes: 4, centres x = −4.5, −1.5, +1.5, +4.5.
/// Camera sits ~7.5 m behind the hero, ~3.2 m up, FOV 62°.
enum Biome { coastal, neon, canyon, desert, snow, rain }

class BiomePalette {
  const BiomePalette({
    required this.name,
    required this.skyTop,
    required this.skyMid,
    required this.skyHorizon,
    required this.sun,
    required this.ground,
    required this.groundFar,
    required this.roadDark,
    required this.roadLight,
    required this.line,
    required this.fog,
    required this.ocean,
    required this.night,
    required this.prop,
    this.wet = false, // Rain biome: the road shines (wet-road gloss)
  });

  final String name;
  final Color skyTop;
  final Color skyMid;
  final Color skyHorizon;
  final Color sun;
  final Color ground;
  final Color groundFar;
  final Color roadDark;
  final Color roadLight;
  final Color line;
  final Color fog;
  final bool ocean;
  final bool night;
  final String prop; // 'palms' | 'city' | 'canyon' | 'desert' | 'snow' | 'rain'
  final bool wet; // true = wet road (Rain biome gloss)

  static const coastal = BiomePalette(
    name: 'Coastal Sunset',
    skyTop: Color(0xFF1E0B4B),
    skyMid: Color(0xFFC2337F),
    skyHorizon: Color(0xFFFF8A3D),
    sun: Color(0xFFFFE08A),
    ground: Color(0xFF6E3F63),
    groundFar: Color(0xFF33244A),
    roadDark: Color(0xFF2E2A33),
    roadLight: Color(0xFF38343D),
    line: Color(0xFFFFD166),
    fog: Color(0xFFC2337F),
    ocean: true,
    night: false,
    prop: 'palms',
  );

  static const neon = BiomePalette(
    name: 'Neon Night',
    skyTop: Color(0xFF050514),
    skyMid: Color(0xFF120A2E),
    skyHorizon: Color(0xFF4A2373),
    sun: Color(0xFF8CF5FF),
    ground: Color(0xFF0D0D1A),
    groundFar: Color(0xFF0A0A20),
    roadDark: Color(0xFF17171F),
    roadLight: Color(0xFF1E1E28),
    line: Color(0xFF00F0FF),
    fog: Color(0xFF120A2E),
    ocean: false,
    night: true,
    prop: 'city',
  );

  static const canyon = BiomePalette(
    name: 'Red Canyon',
    skyTop: Color(0xFF4A0E0E),
    skyMid: Color(0xFFC2431F),
    skyHorizon: Color(0xFFFF9A4D),
    sun: Color(0xFFFFE3A3),
    ground: Color(0xFF93502F),
    groundFar: Color(0xFF5E2A1A),
    roadDark: Color(0xFF33231F),
    roadLight: Color(0xFF3D2A24),
    line: Color(0xFFFFD166),
    fog: Color(0xFFB83A1D),
    ocean: false,
    night: false,
    prop: 'canyon',
  );

  static const desert = BiomePalette(
    name: 'Desert Sunset',
    skyTop: Color(0xFF35204A),
    skyMid: Color(0xFFE08A5A),
    skyHorizon: Color(0xFFFFC46B),
    sun: Color(0xFFFFF3C4),
    ground: Color(0xFFC98A4B),
    groundFar: Color(0xFF9C6B3F),
    roadDark: Color(0xFF2E2A33),
    roadLight: Color(0xFF38343D),
    line: Color(0xFFFFD166),
    fog: Color(0xFFD97B4F),
    ocean: false,
    night: false,
    prop: 'desert',
  );

  /// Snow Drive (Round 5): pale steel-blue sky, white ground, light road.
  static const snow = BiomePalette(
    name: 'Snow Drive',
    skyTop: Color(0xFF7E9BB8),
    skyMid: Color(0xFFB8C8D8),
    skyHorizon: Color(0xFFF2F6F9),
    sun: Color(0xFFFFFFFF),
    ground: Color(0xFFF0F4F7),
    groundFar: Color(0xFFC8D4DE),
    roadDark: Color(0xFF4A5560),
    roadLight: Color(0xFF556270),
    line: Color(0xFFFFD166),
    fog: Color(0xFFB8C8D8),
    ocean: false,
    night: false,
    prop: 'snow',
  );

  /// Rain Highway (Round 5): dark slate sky, grey ground, wet dark road.
  static const rain = BiomePalette(
    name: 'Rain Highway',
    skyTop: Color(0xFF1A2433),
    skyMid: Color(0xFF33414F),
    skyHorizon: Color(0xFF5F7080),
    sun: Color(0xFFC9D6DE),
    ground: Color(0xFF4A5560),
    groundFar: Color(0xFF2E3844),
    roadDark: Color(0xFF1C222B),
    roadLight: Color(0xFF232B36),
    line: Color(0xFFFFD166),
    fog: Color(0xFF3A4A5E),
    ocean: false,
    night: false,
    prop: 'rain',
    wet: true,
  );

  static BiomePalette of(Biome b) {
    switch (b) {
      case Biome.coastal:
        return coastal;
      case Biome.neon:
        return neon;
      case Biome.canyon:
        return canyon;
      case Biome.desert:
        return desert;
      case Biome.snow:
        return snow;
      case Biome.rain:
        return rain;
    }
  }
}

/// Weighted random biome for a run (SPEC §2.5; Round 5 adds Snow + Rain):
/// coastal 30%, neon 20%, canyon 15%, desert 10%, snow 15%, rain 10%.
Biome pickBiome(math.Random rand) {
  final roll = rand.nextDouble();
  if (roll < 0.30) return Biome.coastal;
  if (roll < 0.50) return Biome.neon;
  if (roll < 0.65) return Biome.canyon;
  if (roll < 0.75) return Biome.desert;
  if (roll < 0.90) return Biome.snow;
  return Biome.rain;
}

/// A projected point on screen.
class Projected {
  double x = 0, y = 0, scale = 0, w = 0;
}

/// Roadside decoration. Props are decoration only — never colliders.
class Prop {
  Prop({
    required this.side,
    required this.z,
    required this.kind,
    required this.offset,
    required this.height,
  });

  int side; // −1 left, +1 right
  double z;
  String kind; // 'palm' | 'cactus' | 'rock' | 'billboard' | 'building' | 'mesa' | 'pole' | 'pine'
  double offset; // metres from road edge
  double height; // metres
  double phase = 0.0; // per-prop variation
}

/// A coin on the road (gold) or in the air (blue = +150 L AIR).
class Coin {
  Coin({required this.x, required this.y, required this.z, required this.air});

  double x, y, z;
  bool air;
  bool taken = false;
  double spin = 0.0;
  double prevZ = 0.0;
}

/// The road itself: segment math + projection + prop/coin pools.
class Road {
  static const double laneWidth = 3.0;
  static const double roadWidth = 12.0; // 4 lanes
  static const double segmentLength = 20.0;
  static const int drawSegments = 42; // ~840 m of visible road
  static const double cameraHeight = 3.2;
  static const double cameraDepth = 1.67; // 1 / tan(31°) for FOV 62°

  static const List<double> laneCentres = [-4.5, -1.5, 1.5, 4.5];

  final math.Random _rand = math.Random();
  final List<Prop> props = [];
  final List<Coin> coins = [];
  double _propCursor = 0.0;
  double _coinCursor = 0.0;

  /// Project a world point into screen space.
  /// Returns false when the point is behind the camera.
  static bool project(
    Projected out, {
    required double worldX,
    required double worldY,
    required double worldZ,
    required double camX,
    required double camZ,
    required double width,
    required double height,
    required double fovScale,
  }) {
    final dz = worldZ - camZ;
    if (dz < 0.5) return false;
    final scale = cameraDepth * fovScale / dz;
    out.x = width / 2 + scale * (worldX - camX) * (width / 2);
    out.y = height * 0.42 - scale * (worldY - cameraHeight) * (height / 2);
    out.scale = scale;
    out.w = scale * roadWidth * (width / 2);
    return true;
  }

  /// Nearest lane centre to [x] (for the lane magnet, SPEC §5.2).
  static double nearestLaneCentre(double x) {
    var best = laneCentres[0];
    var bestD = (x - best).abs();
    for (final c in laneCentres) {
      final d = (x - c).abs();
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    return best;
  }

  // ---- Props ---------------------------------------------------------------
  void updateProps(double heroZ, Biome biome) {
    final palette = BiomePalette.of(biome);
    // Spawn ahead as the hero advances; recycle behind.
    while (_propCursor < heroZ + drawSegments * segmentLength) {
      _propCursor += 14.0 + _rand.nextDouble() * 22.0;
      for (final side in [-1, 1]) {
        if (_rand.nextDouble() < 0.72) {
          props.add(_makeProp(side, _propCursor, palette.prop));
        }
      }
    }
    props.removeWhere((p) => p.z < heroZ - 40);
    // Coins: a line every ~90 m, an air arc every ~260 m.
    while (_coinCursor < heroZ + drawSegments * segmentLength) {
      _coinCursor += 90.0 + _rand.nextDouble() * 60.0;
      final lane = _rand.nextInt(4);
      final x = laneCentres[lane];
      if (_rand.nextDouble() < 0.45) {
        // Air arc: 5 blue coins, fly to collect them.
        for (var i = 0; i < 5; i++) {
          coins.add(Coin(
            x: x,
            y: 1.6 + math.sin(i / 4 * math.pi) * 1.4,
            z: _coinCursor + i * 6.0,
            air: true,
          ));
        }
      } else {
        for (var i = 0; i < 4; i++) {
          coins.add(Coin(x: x, y: 0.0, z: _coinCursor + i * 7.0, air: false));
        }
      }
    }
    coins.removeWhere((c) => c.z < heroZ - 20 || c.taken);
    for (final c in coins) {
      c.spin += 0.06;
    }
  }

  Prop _makeProp(int side, double z, String propKind) {
    final r = _rand.nextDouble();
    String kind;
    double height;
    switch (propKind) {
      case 'palms':
        // Round 30: roadside flowers join palms + poles on the coast.
        kind = r < 0.6 ? 'palm' : (r < 0.85 ? 'flower' : 'pole');
        height = kind == 'palm'
            ? 7.0 + _rand.nextDouble() * 3.0
            : (kind == 'flower' ? 1.2 : 8.0);
        break;
      case 'city':
        kind = r < 0.55 ? 'building' : (r < 0.8 ? 'billboard' : 'pole');
        height = kind == 'building' ? 18.0 + _rand.nextDouble() * 22.0 : 9.0;
        break;
      case 'canyon':
        kind = r < 0.5 ? 'mesa' : (r < 0.8 ? 'rock' : 'cactus');
        height = kind == 'mesa' ? 22.0 + _rand.nextDouble() * 14.0 : 2.5;
        break;
      case 'snow': // Round 5: snow pines with white caps + rocks.
        kind = r < 0.6 ? 'pine' : (r < 0.85 ? 'rock' : 'pole');
        height = kind == 'pine' ? 8.0 + _rand.nextDouble() * 4.0 : 2.5;
        break;
      case 'rain': // Round 5: rainy roadside — poles, buildings, billboards.
        kind = r < 0.5 ? 'pole' : (r < 0.8 ? 'building' : 'billboard');
        height = kind == 'building' ? 18.0 + _rand.nextDouble() * 22.0 : 9.0;
        break;
      default: // desert
        kind = r < 0.5 ? 'cactus' : (r < 0.8 ? 'rock' : 'pole');
        height = kind == 'cactus' ? 3.0 + _rand.nextDouble() * 2.0 : 2.0;
    }
    final prop = Prop(
      side: side,
      z: z,
      kind: kind,
      offset: 8.5 + _rand.nextDouble() * 14.0,
      height: height,
    );
    prop.phase = _rand.nextDouble() * math.pi * 2;
    return prop;
  }

  void reset() {
    props.clear();
    coins.clear();
    _propCursor = 0.0;
    _coinCursor = 0.0;
  }
}
