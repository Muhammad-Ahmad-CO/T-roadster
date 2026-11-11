import 'dart:math' as math;

/// Stunt state machine (SPEC §5.7, §8.2): barrel roll (+500) and front
/// flip (+400) while airborne; chaining both in one flight = +1,200.
/// Landing judgement: ≤15° off level = PERFECT (+150), ≤55° = good
/// (0.4 s wobble, steering halved), >55° = crash.
enum StuntKind { none, roll, flip }

class StuntController {
  StuntKind kind = StuntKind.none;
  double progress = 0.0; // 0..1 of the 360° rotation
  bool didRoll = false;
  bool didFlip = false;
  bool doubleStuntAwarded = false;

  static const double rollDuration = 0.9; // seconds for a full 360°
  static const double flipDuration = 1.0;

  bool get active => kind != StuntKind.none;
  bool get inFlight => didRoll || didFlip || active;

  /// Current rotation in radians (roll about the long axis, pitch about
  /// the lateral axis). The renderer uses this for the car visual.
  double get rollAngle =>
      kind == StuntKind.roll ? progress * 2 * math.pi : 0.0;
  double get pitchAngle =>
      kind == StuntKind.flip ? progress * 2 * math.pi : 0.0;

  bool startRoll() {
    if (active) return false;
    kind = StuntKind.roll;
    progress = 0.0;
    didRoll = true;
    return true;
  }

  bool startFlip() {
    if (active) return false;
    kind = StuntKind.flip;
    progress = 0.0;
    didFlip = true;
    return true;
  }

  /// Returns true when a stunt finished this tick.
  bool update(double dt) {
    if (!active) return false;
    final duration = kind == StuntKind.roll ? rollDuration : flipDuration;
    progress += dt / duration;
    if (progress >= 1.0) {
      progress = 1.0;
      kind = StuntKind.none;
      return true;
    }
    return false;
  }

  /// Angular error at landing, in degrees from level (0..180).
  /// A finished stunt is exactly 360° = level; an interrupted one is not.
  double landingErrorDeg() {
    if (progress >= 1.0 || !active) return 0.0;
    final deg = progress * 360.0;
    final err = deg % 360.0;
    return err > 180 ? 360.0 - err : err;
  }

  void onLanded() {
    didRoll = false;
    didFlip = false;
    doubleStuntAwarded = false;
    kind = StuntKind.none;
    progress = 0.0;
  }

  void reset() => onLanded();
}
