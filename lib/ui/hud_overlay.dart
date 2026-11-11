import 'package:flutter/material.dart';

import '../game/game.dart';
import '../game/hud.dart';
import 'theme.dart';

/// In-run HUD (SPEC §6). Event-driven: every element is a
/// ValueListenableBuilder on the game state — nothing is polled per frame.
/// Reference resolution 1080×1920 portrait, anchored, safe-area aware.
class HudOverlay extends StatelessWidget {
  const HudOverlay({super.key, required this.game});

  final TRoadsterGame game;

  @override
  Widget build(BuildContext context) {
    final scoring = game.scoring;
    final hud = game.hud;
    return SafeArea(
      child: Stack(
        children: [
            // ---- Top: score + sub-stats ------------------------------------
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  ValueListenableBuilder<int>(
                    valueListenable: scoring.score,
                    builder: (context, score, _) {
                      return Text(
                        '$score',
                        style: TTheme.display.copyWith(
                          fontSize: 46,
                          shadows: const [
                            Shadow(
                              color: Colors.black87,
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ValueListenableBuilder<int>(
                        valueListenable: scoring.distanceM,
                        builder: (context, d, _) =>
                            Text('DIST $d m', style: TTheme.bodyDim),
                      ),
                      const Text('  ·  ', style: TTheme.bodyDim),
                      ValueListenableBuilder<int>(
                        valueListenable: scoring.timeS,
                        builder: (context, t, _) {
                          final mm = (t ~/ 60).toString();
                          final ss = (t % 60).toString().padLeft(2, '0');
                          return Text('TIME $mm:$ss', style: TTheme.bodyDim);
                        },
                      ),
                      const SizedBox(width: 10),
                      ValueListenableBuilder<int>(
                        valueListenable: scoring.multiplier,
                        builder: (context, m, _) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: m >= 5 ? TTheme.gold : Colors.white24,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              // "STUNT ×m": the combo multiplier applies to
                              // stunt/bonus points only — distance points
                              // are flat (SPEC §8, tuned 2026-11-11).
                              'STUNT ×$m',
                              style: TextStyle(
                                fontFamily: 'RussoOne',
                                fontSize: 13,
                                color: m >= 5
                                    ? TTheme.deepPurple
                                    : Colors.white,
                              ),
                            ),
                          );
                        },
                      ),
                      // Time Trial clock (Round 6): seconds left, red under 10.
                      if (game.timeTrial) const SizedBox(width: 10),
                      if (game.timeTrial)
                        ValueListenableBuilder<int>(
                          valueListenable: hud.timeLeft,
                          builder: (context, left, _) {
                            final mm = (left ~/ 60).toString();
                            final ss =
                                (left % 60).toString().padLeft(2, '0');
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: left <= 10
                                    ? const Color(0xFFD32F2F)
                                    : Colors.white24,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '⏱ $mm:$ss',
                                style: const TextStyle(
                                  fontFamily: 'RussoOne',
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  // Combo drain bar (gold, 4 s).
                  const SizedBox(height: 6),
                  ValueListenableBuilder<double>(
                    valueListenable: scoring.comboFrac,
                    builder: (context, frac, _) {
                      // Combo flame edge (Round 45): the drain bar burns
                      // gold -> orange -> red with a flame at the leading
                      // edge.
                      final f =
                          frac < 0 ? 0.0 : (frac > 1 ? 1.0 : frac);
                      return SizedBox(
                        width: 180,
                        height: 14,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              height: 5,
                              margin: const EdgeInsets.only(top: 4),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: f,
                              alignment: Alignment.centerLeft,
                              child: Container(
                                height: 5,
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(3),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFFFD166),
                                      Color(0xFFFF7E3D),
                                      Color(0xFFFF1744),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: (180 * f) - 8,
                              top: -2,
                              child: const Text('🔥',
                                  style: TextStyle(fontSize: 14)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            // ---- Top-left: AIR bar ------------------------------------------
            Positioned(
              top: 10,
              left: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AIR', style: TTheme.goldLabel),
                  ValueListenableBuilder<double>(
                    valueListenable: hud.airFrac,
                    builder: (context, frac, _) {
                      return SizedBox(
                        width: 84,
                        height: 10,
                        child: LinearProgressIndicator(
                          value: frac,
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            frac < 0.2 ? Colors.red : const Color(0xFF4FC3F7),
                          ),
                        ),
                      );
                    },
                  ),
                  ValueListenableBuilder<double>(
                    valueListenable: hud.airFrac,
                    builder: (context, frac, _) {
                      return Text(
                        '${(frac * game.hud.airMaxLitres.value).round()} L',
                        style: TTheme.bodyDim.copyWith(fontSize: 12),
                      );
                    },
                  ),
                ],
              ),
            ),
            // ---- Top-right: pause + coins ------------------------------------
            Positioned(
              top: 10,
              right: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      ValueListenableBuilder<int>(
                        valueListenable: scoring.coins,
                        builder: (context, c, _) => Text(
                          '🪙 $c',
                          style: TTheme.body.copyWith(fontSize: 15),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          game.audio.click();
                          game.pauseGame();
                        },
                        icon: const Icon(Icons.pause,
                            color: Colors.white, size: 30),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: hud.rocketActive,
                    builder: (context, rocket, _) {
                      if (!rocket) return const SizedBox.shrink();
                      return const Text('🚀 ROCKET MODE',
                          style: TTheme.goldLabel);
                    },
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: hud.starmanActive,
                    builder: (context, star, _) {
                      if (!star) return const SizedBox.shrink();
                      return const Text('⭐ STARMAN ×2',
                          style: TTheme.goldLabel);
                    },
                  ),
                ],
              ),
            ),
            // ---- Police chase warning (Round 1) -------------------------
            Positioned(
              top: 118,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<bool>(
                valueListenable: hud.policeActive,
                builder: (context, active, _) {
                  if (!active) return const SizedBox.shrink();
                  return Center(
                    child: ValueListenableBuilder<double>(
                      valueListenable: hud.policeDistance,
                      builder: (context, behind, _) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white54),
                          ),
                          child: Text(
                            '🚔 POLICE  ${behind.round()} m — NEAR MISS TO SHAKE THEM OFF!',
                            style: const TextStyle(
                              fontFamily: 'RussoOne',
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            // ---- Achievement unlock toast (gold banner, ~2.5 s) -----------
            Positioned(
              top: 150,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<String>(
                valueListenable: hud.achievementToast,
                builder: (context, text, _) {
                  if (text.isEmpty) return const SizedBox.shrink();
                  return Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: TTheme.gold,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black45,
                              blurRadius: 8,
                              offset: Offset(0, 3)),
                        ],
                      ),
                      child: Text(
                        text,
                        style: const TextStyle(
                          fontFamily: 'RussoOne',
                          fontSize: 16,
                          color: TTheme.deepPurple,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // ---- Wrong-Way chip (Round 4) -------------------------------
            // Sits at top 86: under the score, above the police banner
            // (118) — the two never overlap even in a Wrong-Way chase.
            if (game.wrongWay)
              Positioned(
                top: 86,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD32F2F).withOpacity(0.85),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      '⚠️  WRONG WAY — TRAFFIC COMING AT YOU',
                      style: TextStyle(
                        fontFamily: 'RussoOne',
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 180,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<String>(
                valueListenable: hud.questToast,
                builder: (context, text, _) {
                  if (text.isEmpty) return const SizedBox.shrink();
                  return Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: TTheme.magenta,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black45,
                              blurRadius: 8,
                              offset: Offset(0, 3)),
                        ],
                      ),
                      child: Text(
                        text,
                        style: const TextStyle(
                          fontFamily: 'RussoOne',
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // ---- Centre: stunt callouts (rise + fade, max 3) -----------------
            Positioned(
              top: 220,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<List<HudPopup>>(
                valueListenable: hud.popups,
                builder: (context, popups, _) {
                  return Column(
                    children: popups.map((p) {
                      final opacity =
                          (1.0 - (p.age / 0.9)).clamp(0.0, 1.0);
                      // Score popup polish (Round 44): rise + fade + gold
                      // edge — the callout floats up out of a gold pill.
                      return Transform.translate(
                        offset: Offset(0, -24 * (1 - opacity)),
                        child: Opacity(
                          opacity: opacity,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: TTheme.gold, width: 1.5),
                            ),
                            child: Text(
                              p.text,
                              style: TTheme.title.copyWith(
                                fontSize: 22,
                                color: TTheme.gold,
                                shadows: const [
                                  Shadow(
                                      color: Colors.black87,
                                      blurRadius: 4,
                                      offset: Offset(0, 2)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
            // ---- Countdown big numerals (3-2-1-GO) ---------------------------
            Positioned(
              left: 0,
              right: 0,
              top: 300,
              child: ValueListenableBuilder<String>(
                valueListenable: hud.countdown,
                builder: (context, label, _) {
                  if (label.isEmpty) return const SizedBox.shrink();
                  // Countdown glow + scale pop (Round 43): each numeral
                  // pops in from 1.4x with a coloured glow.
                  return TweenAnimationBuilder<double>(
                    key: ValueKey(label),
                    tween: Tween(begin: 1.4, end: 1.0),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    builder: (context, scale, child) => Transform.scale(
                      scale: scale,
                      child: child,
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'RussoOne',
                        fontSize: 110,
                        color: label == 'GO'
                            ? Colors.greenAccent
                            : Colors.white,
                        shadows: [
                          Shadow(
                              color: label == 'GO'
                                  ? Colors.greenAccent.withValues(alpha: 0.8)
                                  : Colors.orangeAccent.withValues(alpha: 0.8),
                              blurRadius: 24,
                              offset: const Offset(0, 0)),
                          const Shadow(
                              color: Colors.black87,
                              blurRadius: 10,
                              offset: Offset(0, 4)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // ---- Bottom-left: speed ------------------------------------------
            Positioned(
              left: 16,
              bottom: 24,
              child: ValueListenableBuilder<int>(
                valueListenable: hud.speedKmh,
                builder: (context, kmh, _) => Text(
                  '$kmh km/h',
                  style: TTheme.title.copyWith(fontSize: 20),
                ),
              ),
            ),
            // ---- Bottom-right: touch buttons ---------------------------------
            Positioned(
              right: 14,
              bottom: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _stuntButton(
                        label: 'FLIP',
                        enabled: hud.airborne,
                        onTap: () => game.input.queueFlip(),
                      ),
                      const SizedBox(width: 10),
                      _stuntButton(
                        label: 'ROLL',
                        enabled: hud.airborne,
                        onTap: () => game.input.queueRoll(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _boostButton(),
                      const SizedBox(width: 10),
                      _hopButton(),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }

  /// FLIP / ROLL: tap while airborne. Greyed out on the road (SPEC §7.2).
  Widget _stuntButton({
    required String label,
    required ValueNotifier<bool> enabled,
    required VoidCallback onTap,
  }) {
    return ValueListenableBuilder<bool>(
      valueListenable: enabled,
      builder: (context, isEnabled, _) {
        return Opacity(
          opacity: isEnabled ? 1.0 : 0.45,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 76,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isEnabled
                    ? TTheme.gold.withOpacity(0.85)
                    : Colors.white24,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.white54, width: 1.5),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'RussoOne',
                  fontSize: 16,
                  color: isEnabled ? TTheme.deepPurple : Colors.white,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _boostButton() {
    return ValueListenableBuilder<double>(
      valueListenable: game.hud.nitroFrac,
      builder: (context, frac, _) {
        final ready = frac >= 1.0;
        return GestureDetector(
          onTap: () => game.input.queueBoost(),
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ready
                  ? TTheme.orange.withOpacity(0.85)
                  : Colors.white24,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white54, width: 1.5),
            ),
            child: Text(
              ready ? 'BOOST' : '${(frac * 100).round()}%',
              style: const TextStyle(
                fontFamily: 'RussoOne',
                fontSize: 13,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

  /// HOP: tap = hop, HOLD = thruster fly (SPEC §7.2).
  Widget _hopButton() {
    return Listener(
      onPointerDown: (_) {
        game.input.hopHeld = true;
        game.input.queueHop();
      },
      onPointerUp: (_) {
        game.input.hopHeld = false;
      },
      onPointerCancel: (_) {
        game.input.hopHeld = false;
      },
      child: Container(
        width: 96,
        height: 96,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: TTheme.gold.withOpacity(0.85),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: const Text(
          'HOP',
          style: TextStyle(
            fontFamily: 'RussoOne',
            fontSize: 22,
            color: TTheme.deepPurple,
          ),
        ),
      ),
    );
  }
}
