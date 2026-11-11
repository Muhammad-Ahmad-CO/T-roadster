import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// ONE input-action layer (SPEC §7, input-systems skill).
/// Keyboard + swipe + tilt + on-screen buttons all feed the same actions —
/// never hardcoded keys in the sim. Gamepad is Phase 2 and plugs in here.
///
/// Steering channel: keyboard (if a key is held) wins outright; otherwise
/// swipe and tilt feed one channel. In "Both" mode swipe wins for 0.5 s
/// after a swipe starts, so a deliberate swipe is never fought by a tilted
/// hand (SPEC §7.3).
enum ControlMode { swipe, tilt, both }

class InputController {
  ControlMode mode = ControlMode.both;

  /// 'low' | 'medium' | 'high' — degrees of tilt for full steer: 35 / 25 / 15.
  String tiltSensitivity = 'medium';
  bool tiltGasBrake = false; // OFF by default — too easy to trigger.
  bool tiltAvailable = false;

  // ---- Steering ------------------------------------------------------------
  double _swipeSteer = 0.0; // −1..1, decays after the finger lifts
  double _tiltSteer = 0.0; // −1..1, low-pass filtered
  double _tiltFiltered = 0.0;
  double _calibrationZeroDeg = 0.0;
  DateTime _swipeOverrideUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _swipeActive = false;

  // Keyboard steering: −1, 0, +1.
  double _keySteer = 0.0;
  bool keyHopHeld = false;
  bool keyBoostHeld = false;

  StreamSubscription<AccelerometerEvent>? _accelSub;

  double get _fullSteerDeg {
    switch (tiltSensitivity) {
      case 'low':
        return 35.0;
      case 'high':
        return 15.0;
      default:
        return 25.0;
    }
  }

  static const double deadZoneDeg = 4.0; // SPEC §7.3

  /// The steering value the sim reads each tick: −1 (full left) .. +1.
  double get steering {
    if (_keySteer != 0) return _keySteer;
    switch (mode) {
      case ControlMode.swipe:
        return _swipeSteer;
      case ControlMode.tilt:
        return _tiltSteer;
      case ControlMode.both:
        if (DateTime.now().isBefore(_swipeOverrideUntil)) return _swipeSteer;
        return (_tiltSteer + _swipeSteer).clamp(-1.0, 1.0);
    }
  }

  bool get isSteering => steering.abs() > 0.05;

  // ---- Queued one-shot actions (game consumes them once per tick) ----------
  bool hopQueued = false;
  bool flipQueued = false;
  bool rollQueued = false;
  bool boostQueued = false;
  bool slamQueued = false;
  bool hopHeld = false; // HOP button / Space held → thruster fly

  void queueHop() => hopQueued = true;
  void queueFlip() => flipQueued = true;
  void queueRoll() => rollQueued = true;
  void queueBoost() => boostQueued = true;
  void queueSlam() => slamQueued = true;

  void consumeQueues() {
    hopQueued = false;
    flipQueued = false;
    rollQueued = false;
    boostQueued = false;
    slamQueued = false;
  }

  // ---- Swipe / drag ----------------------------------------------------------
  /// Relative drag (not absolute position): 40 px ≈ 1 lane of steering
  /// authority; the control appears where the finger lands.
  void onDragDelta(double dx, double dy, double screenWidth) {
    _swipeActive = true;
    _swipeOverrideUntil =
        DateTime.now().add(const Duration(milliseconds: 500));
    _swipeSteer = (_swipeSteer + dx / (screenWidth * 0.12)).clamp(-1.0, 1.0);
    // Fast vertical flicks: up = hop, down = slam.
    if (dy < -28) queueHop();
    if (dy > 28) queueSlam();
  }

  void onDragEnd() {
    _swipeActive = false;
  }

  void update(double dt) {
    // Swipe steering decays to centre once the finger lifts.
    if (!_swipeActive) {
      _swipeSteer = _moveToward(_swipeSteer, 0.0, dt * 1.8);
    }
    // Tilt gas/brake is off by default; see tiltGasBrake.
  }

  // ---- Tilt -------------------------------------------------------------------
  Future<void> startTilt() async {
    try {
      _accelSub = accelerometerEvents.listen(
        _onAccelerometer,
        onError: (_) {
          // No sensor: silently fall back to Swipe-only (SPEC §7.3).
          tiltAvailable = false;
        },
      );
      tiltAvailable = true;
    } catch (_) {
      tiltAvailable = false;
    }
  }

  void stopTilt() {
    _accelSub?.cancel();
    _accelSub = null;
  }

  void calibrateTilt() {
    // Zeroes the current resting angle; called on run start and from
    // Settings → CALIBRATE. The next accelerometer sample re-zeroes it.
    _calibratePending = true;
  }

  bool _calibratePending = false;

  void _onAccelerometer(AccelerometerEvent e) {
    // Portrait phone, tilted around its long axis: x ≈ sin(tilt) * g.
    final rawDeg =
        math.asin((e.x / 9.81).clamp(-1.0, 1.0)) * 180.0 / math.pi;
    if (_calibratePending) {
      _calibrationZeroDeg = rawDeg;
      _calibratePending = false;
    }
    var deg = rawDeg - _calibrationZeroDeg;
    // Dead zone ±4° kills micro-jitter from hand tremor / walking.
    if (deg.abs() < deadZoneDeg) deg = 0.0;
    final target = (deg / _fullSteerDeg).clamp(-1.0, 1.0);
    // Low-pass filter α = 0.25 — smooth, never twitchy.
    _tiltFiltered += (target - _tiltFiltered) * 0.25;
    _tiltSteer = _tiltFiltered;
  }

  // ---- Keyboard (web / test builds, SPEC §7.1) ------------------------------
  /// Returns true when the key was consumed.
  bool onKeyDown(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyA) {
      _keySteer = -1.0;
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD) {
      _keySteer = 1.0;
      return true;
    }
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.arrowUp) {
      // Tap = hop; press again in air = barrel roll (game decides by state).
      if (!keyHopHeld) queueHop();
      keyHopHeld = true;
      hopHeld = true;
      return true;
    }
    if (key == LogicalKeyboardKey.keyW) {
      // In air: front flip (game decides); on road: boost, same as Shift.
      queueFlip();
      keyBoostHeld = true;
      return true;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyS) {
      queueSlam();
      return true;
    }
    if (key == LogicalKeyboardKey.keyR) {
      queueRoll();
      return true;
    }
    if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) {
      queueBoost();
      keyBoostHeld = true;
      return true;
    }
    return false;
  }

  void onKeyUp(LogicalKeyboardKey key) {
    if ((key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.keyA) &&
        _keySteer < 0) {
      _keySteer = 0.0;
    }
    if ((key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.keyD) &&
        _keySteer > 0) {
      _keySteer = 0.0;
    }
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.arrowUp) {
      keyHopHeld = false;
      hopHeld = false;
    }
    if (key == LogicalKeyboardKey.keyW) keyBoostHeld = false;
    if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) {
      keyBoostHeld = false;
    }
  }

  bool get boostHeld => keyBoostHeld;

  void reset() {
    _swipeSteer = 0.0;
    _tiltSteer = 0.0;
    _tiltFiltered = 0.0;
    _keySteer = 0.0;
    keyHopHeld = false;
    keyBoostHeld = false;
    hopHeld = false;
    consumeQueues();
  }

  static double _moveToward(double value, double target, double maxDelta) {
    if ((target - value).abs() <= maxDelta) return target;
    return value + (target > value ? maxDelta : -maxDelta);
  }
}
