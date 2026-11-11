import 'dart:math' as math;
import 'dart:ui';

import 'input.dart';
import 'road.dart';

/// The hero car (SPEC §5.2): original low-poly angular white pickup.
/// Hitbox is deliberately smaller than the visual (1.7 × 4.2 m) so
/// near-misses feel achievable. Physics runs on the fixed 60 Hz tick
/// (physics-tuning skill): gravity 22 m/s², lateral speed 9 m/s, lane
/// magnet 2.5 m/s², squash on landing with overshoot (game-feel skill).
class HeroCar {
  // ---- World state (sim) ---------------------------------------------------
  double x = 0.0; // lateral, metres; lane centres −4.5..+4.5
  double y = 0.0; // height above the road
  double z = 0.0; // distance travelled == road position
  double vy = 0.0;
  double vx = 0.0;
  double speed = 26.0; // m/s at GO, rises to 52 (SPEC §5.3)
  double roll = 0.0; // visual body roll into steers (radians, ≤ 6°)
  double pitch = 0.0; // visual pitch on accel/brake

  // Render interpolation (physics-tuning skill): prev state per tick.
  double prevX = 0.0, prevY = 0.0, prevZ = 0.0;

  // ---- AIR thrusters (SPEC §5.4) -------------------------------------------
  double air = 600.0;
  static const double airMax = 600.0; // base tank; upgrades raise capacity
  static const double hopCost = 40.0;
  static const double flyBurn = 120.0; // L/s
  static const double roadRefill = 60.0; // L/s, wheels on tarmac (base)
  static const double glideRefill = 25.0; // L/s, airborne, no thrust

  // ---- Upgrade-applied values (Round 2) — set by the game at run start ----
  double airCapacity = airMax;
  double rocketDuration = 6.0;
  double refillRate = roadRefill;
  double magnetRadius = 1.2;

  /// Lane-magnet grip (Round 5): 1.0 normally, 0.6 on Snow — the car
  /// drifts back to the lane centre more lazily (slippery feel). Steering
  /// authority itself never changes, so it is never unfair.
  double grip = 1.0;

  // ---- Nitro -----------------------------------------------------------------
  double nitroTime = 0.0; // seconds remaining
  double nitroCooldown = 0.0;
  static const double nitroDuration = 3.0;
  static const double nitroCooldownTime = 8.0;

  // ---- Invincibility ---------------------------------------------------------
  double rocketTime = 0.0; // 6 s, smash through traffic
  double starmanTime = 0.0; // 8 s, smash + double score
  bool get invincible => rocketTime > 0 || starmanTime > 0;

  // ---- Feel --------------------------------------------------------------------
  double squash = 0.0; // 0 = rest, 1 = fully squashed; springs back
  double wobbleTime = 0.0; // 0.4 s after a "good" (≤55°) landing, steering halved
  double shoulderTime = 0.0; // time spent on the hard shoulder
  bool onGround = true;

  static const double gravity = 22.0;
  static const double hopVelocity = 9.5; // apex 2.05 m: clears a sedan (1.75 m needed) with margin; a tap still cannot clear a truck (3.3 m) — that needs a held fly
  static const double lateralSpeed = 9.0;
  static const double laneMagnet = 2.5;

  String skin = 'pickup'; // 'pickup' | 'sports' | 'neon'
  String paint = 'white';

  void reset() {
    x = 0.0;
    y = 0.0;
    z = 0.0;
    vy = 0.0;
    vx = 0.0;
    speed = 26.0;
    roll = 0.0;
    pitch = 0.0;
    air = airMax;
    airCapacity = airMax;
    rocketDuration = 6.0;
    refillRate = roadRefill;
    magnetRadius = 1.2;
    grip = 1.0;
    nitroTime = 0.0;
    nitroCooldown = 0.0;
    rocketTime = 0.0;
    starmanTime = 0.0;
    squash = 0.0;
    wobbleTime = 0.0;
    shoulderTime = 0.0;
    onGround = true;
    prevX = prevY = prevZ = 0.0;
  }

  void snapshot() {
    prevX = x;
    prevY = y;
    prevZ = z;
  }

  double interpX(double alpha) => prevX + (x - prevX) * alpha;
  double interpY(double alpha) => prevY + (y - prevY) * alpha;

  /// Speed curve (SPEC §5.3): 26 m/s + 1 m/s per 100 m, cap 52 m/s.
  /// Nitro adds +35% for 3 s.
  double targetSpeed() {
    final base = (26.0 + z / 100.0).clamp(26.0, 52.0);
    if (nitroTime > 0) return base * 1.35;
    return base;
  }

  /// One fixed-timestep tick. Returns true on the frame the car lands.
  bool update(double dt, InputController input, {required bool flying}) {
    // --- Steering -----------------------------------------------------------
    final steer = input.steering;
    final steerScale = wobbleTime > 0 ? 0.5 : 1.0;
    final targetVx = steer * lateralSpeed * steerScale;
    vx += (targetVx - vx) * math.min(1.0, dt * 10.0);
    x += vx * dt;
    // Lane magnet: gentle pull to the nearest lane centre with no input.
    if (steer.abs() < 0.05) {
      final centre = Road.nearestLaneCentre(x);
      x += (centre - x) * math.min(1.0, dt * laneMagnet * 0.4 * grip);
    }
    // Hard shoulder: allowed 1.5 s, then rumble + auto-steer back (SPEC §5.1).
    if (x.abs() > 6.0) {
      shoulderTime += dt;
      x = x.clamp(-7.5, 7.5);
      if (shoulderTime > 1.5) {
        x += (0.0 - x) * math.min(1.0, dt * 3.0);
      }
    } else {
      shoulderTime = 0.0;
    }

    // --- Vertical: hop / fly / gravity / slam -------------------------------
    if (flying && air > 0) {
      // Thruster lift while HOP is held (SPEC §5.4).
      vy += 26.0 * dt;
      air = math.max(0.0, air - flyBurn * dt);
    } else {
      vy -= gravity * dt;
      air = math.min(
          airCapacity, air + (onGround ? refillRate : glideRefill) * dt);
    }
    y += vy * dt;

    // --- Speed ----------------------------------------------------------------
    speed += (targetSpeed() - speed) * math.min(1.0, dt * 0.8);
    z += speed * dt;

    // --- Timers ---------------------------------------------------------------
    if (nitroTime > 0) nitroTime -= dt;
    if (nitroCooldown > 0) nitroCooldown -= dt;
    if (rocketTime > 0) rocketTime -= dt;
    if (starmanTime > 0) starmanTime -= dt;
    if (wobbleTime > 0) wobbleTime -= dt;
    if (squash > 0) squash = math.max(0.0, squash - dt * 5.0);

    // --- Body roll / pitch (juice only, never the sim) -------------------------
    roll += ((steer * -0.10) - roll) * math.min(1.0, dt * 8.0);
    pitch += (((speed - 26) / 26 * 0.03) - pitch) * math.min(1.0, dt * 4.0);

    // --- Landing ---------------------------------------------------------------
    if (y <= 0.0) {
      final landed = !onGround;
      y = 0.0;
      vy = 0.0;
      onGround = true;
      if (landed) {
        squash = 1.0; // squash & stretch: scale y 0.92 for 120 ms
        return true;
      }
    } else {
      onGround = false;
    }
    return false;
  }

  void hop() {
    if (!onGround) return;
    vy = hopVelocity;
    air = math.max(0.0, air - hopCost);
    onGround = false;
  }

  void slam() {
    // 2× gravity dive — the gap below is now, not in a second (SPEC §5.4).
    if (!onGround) vy -= 22.0;
  }

  void boost() {
    if (nitroCooldown <= 0 && nitroTime <= 0) {
      nitroTime = nitroDuration;
      nitroCooldown = nitroCooldownTime;
    }
  }

  void collectRocket() => rocketTime = rocketDuration;
  void collectStarman() => starmanTime = 8.0;

  // ---- Drawing -----------------------------------------------------------------
  /// Rear 3/4 vector view of the angular pickup. Drawn in code (original
  /// geometry, no logos, no Tesla/Cybertruck marks). [cx] is the screen
  /// x of the car centre, [baseY] the road contact line, [w] the car width
  /// in px. The car is drawn centred on (cx, baseY − h/2) so a barrel roll
  /// spins around its own centre; a front flip reads as the car foreshortening
  /// (scale-y = 0.45 + 0.55·|cos pitch|) because the camera never rolls.
  void draw(
    Canvas canvas,
    double cx,
    double baseY,
    double w,
    double stuntRoll,
    double stuntPitch, {
    required bool night,
    required Color paintColor,
  }) {
    final h = w * 0.62;
    final squashY = 1.0 - 0.08 * squash;
    final flipFactor = 0.45 + 0.55 * math.cos(stuntPitch).abs();
    canvas.save();
    canvas.translate(cx, baseY - h * 0.5);
    canvas.rotate(stuntRoll);
    canvas.scale(1.0 + 0.06 * squash, squashY * flipFactor);

    // Wide flat tailgate: the camera sits behind the car, so the reel
    // reads as a pickup's flat rear deck — not a tapering sedan roof.
    // Round 7: skins change the silhouette — sports/coupe sit low with a
    // lower roofline; trucks keep the tall pickup roof.
    final lowRoof = skin == 'sports' || skin == 'coupe';
    final roofY = lowRoof ? -h * 0.20 : -h * 0.32;
    final shoulderY = lowRoof ? -h * 0.18 : -h * 0.28;
    final body = Path()
      ..moveTo(-w * 0.5, h * 0.5)
      ..lineTo(-w * 0.49, h * 0.05)
      ..lineTo(-w * 0.44, shoulderY)
      ..lineTo(-w * 0.40, roofY)
      ..lineTo(w * 0.40, roofY)
      ..lineTo(w * 0.44, shoulderY)
      ..lineTo(w * 0.49, h * 0.05)
      ..lineTo(w * 0.5, h * 0.5)
      ..close();
    final bodyPaint = Paint()..color = paintColor;
    canvas.drawPath(body, bodyPaint);
    // Flat-panel edge highlight (angular pickup language).
    final edgePaint = Paint()
      ..color = const Color(0xFFFFFFFF).withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, w * 0.012);
    canvas.drawPath(body, edgePaint);
    // Bed rail: the dark line just below the tailgate top edge, so the
    // flat rear reads as a pickup bed, not a blank slab. Trucks only —
    // the low sports/coupe bodies have no bed.
    if (!lowRoof) {
      final railPaint = Paint()
        ..color = const Color(0xFF000000).withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, w * 0.012);
      canvas.drawLine(
        Offset(-w * 0.38, -h * 0.24),
        Offset(w * 0.38, -h * 0.24),
        railPaint,
      );
    }
    // Warm sunset rim light along the roofline + sun side (SPEC §10:
    // "strong warm rim light on the car" — the reel's golden hour).
    final rimPaint = Paint()
      ..color = const Color(0xFFFFB347).withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, w * 0.016);
    final rim = Path()
      ..moveTo(-w * 0.40, roofY)
      ..lineTo(w * 0.40, roofY)
      ..lineTo(w * 0.44, shoulderY)
      ..lineTo(w * 0.49, h * 0.05);
    canvas.drawPath(rim, rimPaint);
    // Black glass band.
    final glass = Path()
      ..moveTo(-w * 0.36, h * 0.06)
      ..lineTo(-w * 0.30, -h * 0.18)
      ..lineTo(w * 0.30, -h * 0.18)
      ..lineTo(w * 0.36, h * 0.06)
      ..close();
    canvas.drawPath(glass, Paint()..color = const Color(0xFF101018));
    // Windshield glare sweep (Round 53): a diagonal light streak across
    // the glass that drifts with body roll — the glass reads as glass.
    final glare = Path()
      ..moveTo(-w * 0.30 + stuntRoll * w * 0.5, h * 0.06)
      ..lineTo(-w * 0.18 + stuntRoll * w * 0.5, -h * 0.18)
      ..lineTo(-w * 0.10 + stuntRoll * w * 0.5, -h * 0.18)
      ..lineTo(-w * 0.22 + stuntRoll * w * 0.5, h * 0.06)
      ..close();
    canvas.drawPath(
        glare, Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.28));
    // Full-width rear light bar (red).
    final bar = Rect.fromLTWH(-w * 0.44, h * 0.20, w * 0.88, h * 0.07);
    final barPaint = Paint()
      ..color = const Color(0xFFFF2D55)
      ..maskFilter = night
          ? const MaskFilter.blur(BlurStyle.normal, 6)
          : const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawRect(bar, barPaint);
    // Wheels.
    final wheelPaint = Paint()..color = const Color(0xFF0D0D12);
    canvas.drawRect(
        Rect.fromLTWH(-w * 0.46, h * 0.34, w * 0.14, h * 0.16), wheelPaint);
    canvas.drawRect(
        Rect.fromLTWH(w * 0.32, h * 0.34, w * 0.14, h * 0.16), wheelPaint);
    // Wheel spin blur (Round 54): a translucent smear trailing each
    // wheel, growing with speed — at speed the tyres read as spinning.
    final spin = (speed / 52).clamp(0.0, 1.0);
    final blurPaint = Paint()
      ..color = const Color(0xFF0D0D12).withValues(alpha: 0.15 + spin * 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRect(
        Rect.fromLTWH(-w * 0.46 - spin * w * 0.06, h * 0.36,
            w * (0.14 + spin * 0.12), h * 0.12),
        blurPaint);
    canvas.drawRect(
        Rect.fromLTWH(w * 0.32 - spin * w * 0.06, h * 0.36,
            w * (0.14 + spin * 0.12), h * 0.12),
        blurPaint);
    // Skin extras (Round 7): each skin reads differently at a glance.
    switch (skin) {
      case 'sports':
        // Rear spoiler wing above the low roofline.
        canvas.drawRect(
            Rect.fromLTWH(-w * 0.42, roofY - h * 0.07, w * 0.84, h * 0.045),
            Paint()..color = const Color(0xFF0D0D12));
        canvas.drawRect(
            Rect.fromLTWH(-w * 0.30, roofY - h * 0.03, w * 0.05, h * 0.05),
            Paint()..color = const Color(0xFF0D0D12));
        canvas.drawRect(
            Rect.fromLTWH(w * 0.25, roofY - h * 0.03, w * 0.05, h * 0.05),
            Paint()..color = const Color(0xFF0D0D12));
        break;
      case 'coupe':
        // Big spoiler + side skirts.
        canvas.drawRect(
            Rect.fromLTWH(-w * 0.48, roofY - h * 0.08, w * 0.96, h * 0.05),
            Paint()..color = const Color(0xFF0D0D12));
        canvas.drawRect(
            Rect.fromLTWH(-w * 0.50, h * 0.30, w * 0.06, h * 0.10),
            Paint()..color = const Color(0xFF0D0D12));
        canvas.drawRect(
            Rect.fromLTWH(w * 0.44, h * 0.30, w * 0.06, h * 0.10),
            Paint()..color = const Color(0xFF0D0D12));
        break;
      case 'neon':
        // Cyan neon trim + always-on cyan under-glow (not just at night).
        canvas.drawPath(
            body,
            Paint()
              ..color = const Color(0xFF00F0FF)
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(2.0, w * 0.018));
        final neonGlow = Paint()
          ..color = const Color(0xFF00F0FF).withOpacity(0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        canvas.drawRect(
            Rect.fromLTWH(-w * 0.4, h * 0.46, w * 0.8, h * 0.08), neonGlow);
        break;
      case 'rally':
        // Roof rack + spare wheel on the tailgate.
        canvas.drawRect(
            Rect.fromLTWH(-w * 0.30, roofY - h * 0.04, w * 0.60, h * 0.03),
            Paint()..color = const Color(0xFF0D0D12));
        canvas.drawRect(
            Rect.fromLTWH(-w * 0.30, roofY - h * 0.10, w * 0.60, h * 0.03),
            Paint()..color = const Color(0xFF0D0D12));
        canvas.drawCircle(
            Offset(0, h * 0.10),
            w * 0.11,
            Paint()..color = const Color(0xFF0D0D12));
        canvas.drawCircle(
            Offset(0, h * 0.10),
            w * 0.05,
            Paint()..color = const Color(0xFF9AA0A6));
        break;
      case 'arctic':
        // Roof light bar (3 amber lamps) + chunky off-road wheels + spare.
        for (var i = -1; i <= 1; i++) {
          canvas.drawCircle(
              Offset(i * w * 0.14, roofY - h * 0.03),
              math.max(2.0, w * 0.025),
              Paint()..color = const Color(0xFFFFC531));
        }
        canvas.drawRect(
            Rect.fromLTWH(-w * 0.48, h * 0.32, w * 0.17, h * 0.19),
            Paint()..color = const Color(0xFF0D0D12));
        canvas.drawRect(
            Rect.fromLTWH(w * 0.31, h * 0.32, w * 0.17, h * 0.19),
            Paint()..color = const Color(0xFF0D0D12));
        canvas.drawCircle(
            Offset(0, h * 0.10),
            w * 0.11,
            Paint()..color = const Color(0xFF0D0D12));
        canvas.drawCircle(
            Offset(0, h * 0.10),
            w * 0.05,
            Paint()..color = const Color(0xFFE8EEF2));
        break;
      default:
        break;
    }
    // Under-glow at night.
    if (night) {
      final glow = Paint()
        ..color = const Color(0xFF7DF9FF).withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawRect(Rect.fromLTWH(-w * 0.4, h * 0.46, w * 0.8, h * 0.08), glow);
    }
    // Rocket / Starman aura.
    if (invincible) {
      final aura = Paint()
        ..color = (starmanTime > 0
                ? const Color(0xFFFFD166)
                : const Color(0xFFFF7E3D))
            .withOpacity(0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, w * 0.02);
      canvas.drawPath(body, aura);
    }
    canvas.restore();
  }

  /// Soft shadow ellipse on the road under the car. Shadow softness by
  /// height (Round 55): the higher the jump, the smaller, fainter and
  /// blurrier the shadow — it lands softly instead of snapping.
  void drawShadow(Canvas canvas, double cx, double baseY, double w, double heightAboveRoad) {
    final height01 = (heightAboveRoad / 12.0).clamp(0.0, 1.0);
    final shrink = (1.0 - height01 * 0.7);
    final paint = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: 0.35 * shrink)
      ..maskFilter =
          MaskFilter.blur(BlurStyle.normal, 2.0 + height01 * 10.0);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, baseY + 2),
        width: w * 0.9 * shrink + w * 0.1,
        height: w * 0.10,
      ),
      paint,
    );
  }
}
