import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/achievements.dart';
import '../game/car.dart';
import '../game/daily_challenge.dart';
import '../game/game.dart';
import '../game/streaks.dart';
import 'theme.dart';

/// Main menu (SPEC §3.2). The highway idles behind it — the menu IS the
/// highway (the game drifts the road in the home state).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.game});

  final TRoadsterGame game;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final storage = widget.game.storage;
    final best = storage.bestScore;
    final bestDist = storage.bestDistance;
    final unlocked = storage.unlockedAchievements.length;
    final daily = DailyChallenge.today();
    final dailyDone = storage.dailyDoneFor(daily.dateKey);
    return Stack(
      children: [
        // Home background parallax clouds (Round 49): two layers of
        // soft clouds drifting at different speeds behind the menu.
        const Positioned.fill(child: _DriftClouds()),
        SafeArea(
          child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: TTheme.panel,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: TTheme.panelBorder),
                  ),
                  child: Row(
                    children: [
                      const Text('🪙', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      Text(
                        '${storage.coins}',
                        style: TTheme.title.copyWith(fontSize: 18),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        widget.game.audio.click();
                        final muted = !storage.muted;
                        storage.setMuted(muted);
                        widget.game.audio.setMuted(muted);
                        setState(() {});
                      },
                      icon: Icon(
                        storage.muted ? Icons.volume_off : Icons.volume_up,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        widget.game.audio.click();
                        widget.game.overlays.add('settings');
                      },
                      icon: const Icon(Icons.settings,
                          color: Colors.white, size: 28),
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            _HeroShowcase(game: widget.game),
            const SizedBox(height: 8),
            const Text(
              'T ROADSTER',
              textAlign: TextAlign.center,
              style: TTheme.display,
            ),
            const SizedBox(height: 4),
            const Text(
              'SUBWAY SURFERS, BUT YOU ARE THE CAR',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Nunito',
                color: TTheme.gold,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'BEST  ${best > 0 ? best : '—'}    ·    DIST  ${bestDist > 0 ? '$bestDist m' : '—'}',
              textAlign: TextAlign.center,
              style: TTheme.bodyDim,
            ),
            const SizedBox(height: 20),
            TTheme.goldButton(
              label: '▶  DRIVE',
              height: 72,
              fontSize: 28,
              onPressed: () {
                widget.game.audio.click();
                widget.game.startRun();
              },
            ),
            const SizedBox(height: 12),
            // Wrong-Way mode toggle (Round 4): traffic comes AT you.
            // Unlocked after the first 1,000 m run.
            _wrongWayTile(),
            const SizedBox(height: 12),
            // Time Trial toggle (Round 6): 60-second clock, best distance.
            _timeTrialTile(),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _menuTile(
                    'GARAGE',
                    Icons.directions_car,
                    () {
                      widget.game.audio.click();
                      widget.game.overlays.add('garage');
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _menuTile(
                    'LEADERBOARD',
                    Icons.leaderboard,
                    () {
                      widget.game.audio.click();
                      widget.game.overlays.add('leaderboard');
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _menuTile(
                    'QUESTS',
                    Icons.flag,
                    () {
                      widget.game.audio.click();
                      widget.game.overlays.add('quests');
                    },
                  ),
                ),
              ],
            ),
            const Spacer(),
            // ---- Achievements + daily challenge (tappable) -----------------
            InkWell(
              onTap: () {
                widget.game.audio.click();
                widget.game.overlays.add('achievements');
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: TTheme.panel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: TTheme.panelBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '🏆  ACHIEVEMENTS  $unlocked/${Achievement.all.length}',
                          style: TTheme.body.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          dailyDone ? 'DAILY  ✓' : 'DAILY  +500 🪙',
                          style: TextStyle(
                            fontFamily: 'RussoOne',
                            fontSize: 12,
                            color: dailyDone
                                ? Colors.greenAccent
                                : TTheme.gold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '📅 ${daily.title} — ${daily.description}',
                      style: TTheme.bodyDim.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _streakPanel(),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _editCallsign(context),
              child: Text(
                'PILOT  ${storage.callsign}  ✎',
                textAlign: TextAlign.center,
                style: TTheme.bodyDim,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'T Roadster v1.0.0',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Nunito', color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
        ),
        ),
      ],
    );
  }

  /// Streak + weekly target panel (Round 8). The flame glows brighter
  /// with longer streaks — gold at 7+ days, orange at 3+, plain below.
  Widget _streakPanel() {
    final streaks = widget.game.streaks;
    final streak = streaks.count;
    final claimable = streaks.weeklyClaimable;
    final frac = streaks.weeklyFrac;
    final flameColor = streak >= 7
        ? TTheme.gold
        : (streak >= 3 ? TTheme.orange : Colors.white54);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: TTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TTheme.panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Streak flame glow (Round 8 graphics).
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: streak >= 3
                      ? [
                          BoxShadow(
                            color: flameColor.withOpacity(0.6),
                            blurRadius: streak >= 7 ? 16 : 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  '🔥',
                  style: TextStyle(
                    fontSize: 22,
                    color: flameColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  streak > 0
                      ? 'STREAK  $streak ${streak == 1 ? 'DAY' : 'DAYS'}'
                      : 'STREAK — play today to start one!',
                  style: TTheme.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (claimable)
                ElevatedButton(
                  onPressed: () async {
                    final ok = await streaks.claimWeekly();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok
                            ? 'Weekly reward claimed: +2,000 🪙!'
                            : 'Not claimable yet.'),
                      ),
                    );
                    if (ok) setState(() {});
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TTheme.gold,
                    foregroundColor: TTheme.deepPurple,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  child: const Text(
                    'CLAIM +2,000 🪙',
                    style: TextStyle(
                        fontFamily: 'RussoOne', fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 10,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(
                claimable ? TTheme.gold : TTheme.orange,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'WEEKLY  ${streaks.weeklyScored} / ${Streaks.weeklyTarget} score — +2,000 🪙',
            style: TTheme.bodyDim.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// Time Trial toggle (Round 6). 60 s clock, best distance in 60 s.
  /// Stacks with Wrong-Way — both can be on at once.
  Widget _timeTrialTile() {
    final storage = widget.game.storage;
    final on = widget.game.timeTrial;
    final ttBest = storage.bestTimeTrial;
    return InkWell(
      onTap: () {
        widget.game.audio.click();
        setState(() {
          widget.game.timeTrial = !widget.game.timeTrial;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: on ? TTheme.orange : TTheme.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: on ? Colors.white : TTheme.panelBorder,
            width: on ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            const Text('⏱', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TIME TRIAL — 60 S',
                    style: TTheme.goldLabel.copyWith(
                      color: on ? Colors.white : TTheme.gold,
                    ),
                  ),
                  Text(
                    on
                        ? 'ON — how far in 60 seconds?'
                        : 'Best distance in 60 seconds. Tap to turn on.',
                    style: TTheme.bodyDim.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            if (ttBest > 0)
              Text(
                'BEST ${ttBest}m',
                style: TTheme.body.copyWith(fontWeight: FontWeight.w900),
              ),
            if (ttBest > 0) const SizedBox(width: 8),
            Text(
              on ? 'ON' : 'OFF',
              style: TTheme.body.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  /// Wrong-Way mode toggle (Round 4). Locked until the first 1,000 m run
  /// (storage.bestDistance). Shows the mode's own best when unlocked.
  Widget _wrongWayTile() {
    final storage = widget.game.storage;
    final unlocked = storage.bestDistance >= 1000;
    final on = widget.game.wrongWay;
    final wwBest = storage.bestWrongWay;
    return InkWell(
      onTap: () {
        widget.game.audio.click();
        if (!unlocked) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Wrong-Way unlocks at 1,000 m — your best is ${storage.bestDistance} m. Keep driving!',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
        setState(() {
          widget.game.wrongWay = !widget.game.wrongWay;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: on ? TTheme.magenta : TTheme.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: on ? Colors.white : TTheme.panelBorder,
            width: on ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(
              unlocked ? '🔄' : '🔒',
              style: const TextStyle(fontSize: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WRONG-WAY MODE',
                    style: TTheme.goldLabel.copyWith(
                      color: on ? Colors.white : TTheme.gold,
                    ),
                  ),
                  Text(
                    unlocked
                        ? (on
                            ? 'ON — traffic comes AT you!'
                            : 'Traffic comes at you. Tap to turn on.')
                        : 'Drive 1,000 m to unlock (best ${storage.bestDistance} m)',
                    style: TTheme.bodyDim.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            if (unlocked && wwBest > 0)
              Text(
                'BEST $wwBest',
                style: TTheme.body.copyWith(fontWeight: FontWeight.w900),
              ),
            if (unlocked)
              Text(
                on ? 'ON' : 'OFF',
                style: TTheme.body.copyWith(fontWeight: FontWeight.w900),
              ),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 76,
        decoration: BoxDecoration(
          color: TTheme.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: TTheme.panelBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: TTheme.gold, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'RussoOne',
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editCallsign(BuildContext context) async {
    final controller =
        TextEditingController(text: widget.game.storage.callsign);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TTheme.purple,
        title: const Text('PILOT CALLSIGN', style: TTheme.title),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          maxLength: 12,
          style: TTheme.body,
          decoration: const InputDecoration(
            hintText: 'DRIVER-01',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('SAVE', style: TextStyle(color: TTheme.gold)),
          ),
        ],
      ),
    );
    if (result != null) {
      await widget.game.storage.setCallsign(result);
      setState(() {});
    }
  }
}

/// Menu hero car showcase (Round 46): the equipped car slowly turns on
/// a turntable — a gentle rotateY sway + bob + gold under-glow.
class _HeroShowcase extends StatefulWidget {
  const _HeroShowcase({required this.game});
  final TRoadsterGame game;
  @override
  State<_HeroShowcase> createState() => _HeroShowcaseState();
}

class _HeroShowcaseState extends State<_HeroShowcase>
    with SingleTickerProviderStateMixin {
  static const _paintColors = {
    'white': Color(0xFFF5F5F5),
    'black': Color(0xFF1A1A1F),
    'red': Color(0xFFD32F2F),
    'blue': Color(0xFF1565C0),
    'gold': Color(0xFFFFC531),
    'pink': Color(0xFFEC407A),
    'teal': Color(0xFF00897B),
    'purple': Color(0xFF7E57C2),
    'orange': Color(0xFFFF7043),
    'lime': Color(0xFF9CCC65),
    'silver': Color(0xFFB0BEC5),
    'navy': Color(0xFF1A237E),
  };

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paintColor =
        _paintColors[widget.game.hero.paint] ?? const Color(0xFFF5F5F5);
    return SizedBox(
      height: 140,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value * math.pi * 2;
          final sway = math.cos(t);
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(sway * 0.55),
            child: CustomPaint(
              size: const Size(280, 120),
              painter: _HeroPainter(
                widget.game.hero,
                paintColor: paintColor,
                bob: math.sin(t) * 3,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Home background parallax clouds (Round 49): two layers of soft
/// clouds drifting at different speeds behind the menu content.
class _DriftClouds extends StatefulWidget {
  const _DriftClouds();
  @override
  State<_DriftClouds> createState() => _DriftCloudsState();
}

class _DriftCloudsState extends State<_DriftClouds>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => CustomPaint(
        painter: _CloudPainter(_ctrl.value),
      ),
    );
  }
}

class _CloudPainter extends CustomPainter {
  _CloudPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // Back layer: slow, faint, high up. Front layer: faster, brighter.
    for (var layer = 0; layer < 2; layer++) {
      final speed = layer == 0 ? 0.008 : 0.02;
      final alpha = layer == 0 ? 0.06 : 0.12;
      final paint = Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: alpha)
        ..style = PaintingStyle.fill;
      for (var i = 0; i < 3; i++) {
        final span = size.width * 1.4;
        final cx = ((i * 0.41 * size.width + t * span * speed * 40) % span) -
            size.width * 0.2;
        final cy = size.height * (0.06 + layer * 0.12 + i * 0.05);
        final cw = size.width * (0.22 + (i % 2) * 0.08);
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset(cx, cy), width: cw, height: cw * 0.26),
            paint);
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset(cx + cw * 0.25, cy - cw * 0.05),
                width: cw * 0.6,
                height: cw * 0.22),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CloudPainter old) => old.t != t;
}

class _HeroPainter extends CustomPainter {
  _HeroPainter(this.hero, {required this.paintColor, required this.bob});
  final HeroCar hero;
  final Color paintColor;
  final double bob;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final baseY = size.height * 0.86 + bob;
    // Gold under-glow + soft shadow on the turntable floor.
    final glow = Paint()
      ..color = const Color(0xFFFFC531).withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx, baseY + 4),
            width: size.width * 0.8,
            height: 18),
        glow);
    hero.draw(
      canvas,
      cx,
      baseY,
      240,
      0.0,
      0.0,
      night: false,
      paintColor: paintColor,
    );
  }

  @override
  bool shouldRepaint(_HeroPainter old) => old.bob != bob;
}
