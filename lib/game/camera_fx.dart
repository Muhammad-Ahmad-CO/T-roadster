import 'dart:math' as math;
import 'dart:ui';

/// Game-feel camera layer (SPEC §14, game-feel skill).
/// Trauma-based shake (quadratic trauma², decaying, camera-only — never the
/// car body), hit-stop with a real-time timer (newest call owns the restore),
/// FOV kick on nitro, desaturate tween for the crash, white flash.
/// The simulation never reads any of this — it is pure visual feedback.
class CameraFx {
  CameraFx({this.reduceShake = false, this.reduceFlash = false});

  bool reduceShake;
  bool reduceFlash;

  // ---- Trauma shake -------------------------------------------------------
  double trauma = 0.0;
  double _time = 0.0;
  static const double _decay = 1.2;
  static const double _maxOffsetX = 14.0;
  static const double _maxOffsetY = 10.0;
  static const double _maxRoll = 0.06; // radians

  void addTrauma(double amount) {
    trauma = (trauma + amount).clamp(0.0, 1.0);
  }

  /// Smooth pseudo-random offset from sampled sin (never per-frame rand —
  /// that buzzes). Returns the pixel offset to apply to the whole scene.
  Offset shakeOffset(double dt) {
    if (trauma <= 0) return Offset.zero;
    trauma = math.max(0.0, trauma - _decay * dt);
    _time += dt * 30.0;
    final shake = trauma * trauma;
    final scale = reduceShake ? 0.35 : 1.0;
    return Offset(
      _maxOffsetX * shake * scale * math.sin(_time * 1.7),
      _maxOffsetY * shake * scale * math.sin(_time * 2.3),
    );
  }

  double shakeRoll(double dt) {
    if (trauma <= 0) return 0.0;
    final shake = trauma * trauma;
    return _maxRoll * shake * (reduceShake ? 0.35 : 1.0) * math.sin(_time * 1.1);
  }

  // ---- Hit-stop / slow-mo (real-time, not scaled time) --------------------
  DateTime _hitStopUntil = DateTime.fromMillisecondsSinceEpoch(0);
  double _hitStopScale = 1.0;
  DateTime _slowMoUntil = DateTime.fromMillisecondsSinceEpoch(0);
  double _slowMoScale = 1.0;

  /// Freeze the sim for [duration] real seconds at time scale [slow].
  /// Newest call wins: an older timer never cuts a newer freeze short.
  void hitStop({double duration = 0.08, double slow = 0.05}) {
    _hitStopScale = slow;
    _hitStopUntil = DateTime.now().add(
      Duration(milliseconds: (duration * 1000).round()),
    );
  }

  void slowMo({double scale = 0.35, double duration = 0.8}) {
    _slowMoScale = scale;
    _slowMoUntil = DateTime.now().add(
      Duration(milliseconds: (duration * 1000).round()),
    );
  }

  /// The time scale the sim loop must use this frame.
  double get timeScale {
    final now = DateTime.now();
    var scale = 1.0;
    if (now.isBefore(_hitStopUntil)) scale = math.min(scale, _hitStopScale);
    if (now.isBefore(_slowMoUntil)) scale = math.min(scale, _slowMoScale);
    return scale;
  }

  // ---- FOV kick ------------------------------------------------------------
  double fov = 62.0;
  static const double baseFov = 62.0;
  static const double nitroFov = 70.0;

  double _kick = 0.0; // 0..1 envelope for the FOV kick (Round 59)

  void kickFov() => _kick = 1.0;

  void updateFov(double dt) {
    // Boost FOV kick polish (Round 59): the kick overshoots to 72 then
    // settles at 70 with a smoothstep ease, and eases back to 62 the
    // same way — no more linear snap. The widening FOV stretches the
    // road edges outward (fovScale in the projections), which is the
    // edge-stretch feel.
    if (_kick > 0) {
      _kick = math.max(0.0, _kick - dt * 1.8);
    }
    final e = _kick * _kick * (3 - 2 * _kick); // smoothstep
    final overshoot = _kick > 0.85 ? (_kick - 0.85) / 0.15 * 2.0 : 0.0;
    fov = baseFov + (nitroFov - baseFov) * e + overshoot;
  }

  // ---- Desaturation (crash → grayscale, SPEC §9) ---------------------------
  double saturation = 1.0; // 1.0 = full colour, 0.15 = reel grayscale
  double _satTarget = 1.0;

  void startDesaturate() => _satTarget = 0.15;
  void restoreColour() {
    _satTarget = 1.0;
    saturation = 1.0;
  }

  void updateSaturation(double dt) {
    saturation += (_satTarget - saturation) * math.min(1.0, dt * 3.0);
  }

  /// Saturation matrix for a saveLayer ColorFilter (identity at 1.0).
  List<double> get saturationMatrix {
    final s = saturation;
    final inv = 1.0 - s;
    const r = 0.299, g = 0.587, b = 0.114;
    return <double>[
      inv * r + s, inv * g, inv * b, 0, 0,
      inv * r, inv * g + s, inv * b, 0, 0,
      inv * r, inv * g, inv * b + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  // ---- White flash ----------------------------------------------------------
  double flash = 0.0; // 0..1 alpha

  void flashWhite(double amount) {
    if (reduceFlash) amount *= 0.4;
    flash = math.max(flash, amount.clamp(0.0, 1.0));
  }

  void updateFlash(double dt) {
    if (flash > 0) flash = math.max(0.0, flash - dt * 6.0);
  }

  void reset() {
    _kick = 0.0;
    trauma = 0.0;
    saturation = 1.0;
    _satTarget = 1.0;
    flash = 0.0;
    fov = baseFov;
    _hitStopUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _slowMoUntil = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
