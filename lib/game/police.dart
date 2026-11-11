/// Police chase mode (Round 1 improvement).
/// A police car spawns behind the hero after 1,000 m (then every +1,000 m),
/// sirens on, and closes in. Near misses, stunts and smashes shake it off;
/// if it reaches the hero the run ends BUSTED instead of CRASHED.
/// Escape = +500 flat points and a lifetime escape counter.
/// Pure simulation (no rendering here — the renderer draws it from [behind]
/// and [active]); the game owns the crash/escape consequences.
enum PoliceEvent { none, busted, escaped }

class PoliceChase {
  /// Spawns at these distances (m). Re-arms at the next milestone.
  static const double spawnStep = 1000.0;

  /// Closing speed (m/s) when active.
  static const double closeRate = 1.8;

  /// Busted when the police car is this close (m behind the hero).
  static const double bustDistance = 2.5;

  /// Escaped when pushed this far behind (m).
  static const double escapeDistance = 70.0;

  /// Starting gap when the chase begins.
  static const double startBehind = 40.0;

  bool active = false;
  double behind = startBehind;
  double nextSpawnAt = spawnStep;
  bool _bustedReported = false;
  bool _escapedReported = false;

  void reset() {
    active = false;
    behind = startBehind;
    nextSpawnAt = spawnStep;
    _bustedReported = false;
    _escapedReported = false;
  }

  /// One fixed-timestep tick. Returns the event to act on (once each).
  PoliceEvent update(double dt, double distance) {
    if (!active) {
      if (distance >= nextSpawnAt) {
        active = true;
        behind = startBehind;
        _bustedReported = false;
        _escapedReported = false;
        nextSpawnAt += spawnStep;
        return PoliceEvent.none;
      }
      return PoliceEvent.none;
    }
    behind -= closeRate * dt;
    if (behind <= bustDistance && !_bustedReported) {
      _bustedReported = true;
      active = false;
      return PoliceEvent.busted;
    }
    if (behind >= escapeDistance && !_escapedReported) {
      _escapedReported = true;
      active = false;
      return PoliceEvent.escaped;
    }
    return PoliceEvent.none;
  }

  /// Near miss: the police car falls back 10 m.
  void onNearMiss() {
    if (active) behind += 10.0;
  }

  /// Completed stunt (roll / flip): falls back 6 m.
  void onStunt() {
    if (active) behind += 6.0;
  }

  /// Smash in Rocket/Starman: falls back 15 m.
  void onSmash() {
    if (active) behind += 15.0;
  }

  /// 0..1: how close the chase is to a bust (for the HUD warning).
  double get danger => active
      ? ((escapeDistance - behind) / (escapeDistance - bustDistance))
          .clamp(0.0, 1.0)
      : 0.0;
}
