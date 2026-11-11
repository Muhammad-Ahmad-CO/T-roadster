import 'package:flutter/material.dart';

import '../game/achievements.dart';
import '../game/daily_challenge.dart';
import '../game/game.dart';
import '../game/storage.dart';
import 'theme.dart';

/// Achievements + daily challenge (tuning pass 2026-11-11, local only).
/// Opened from Home (tappable panel) and from the Leaderboard screen.
/// Back returns to whichever screen opened it — the overlay is simply
/// removed, the screen underneath stays in place.
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key, required this.game});

  final TRoadsterGame game;

  @override
  Widget build(BuildContext context) {
    final storage = game.storage;
    final unlocked = storage.unlockedAchievements;
    final daily = DailyChallenge.today();
    final dailyDone = storage.dailyDoneFor(daily.dateKey);

    return SafeArea(
      child: Container(
        color: TTheme.deepPurple,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      game.audio.click();
                      game.overlays.remove('achievements');
                    },
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      '🏆  ACHIEVEMENTS  ${unlocked.length}/${Achievement.all.length}',
                      textAlign: TextAlign.center,
                      style: TTheme.title.copyWith(fontSize: 20),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 12),
              // ---- Daily challenge card -------------------------------------
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: dailyDone
                      ? TTheme.gold.withOpacity(0.18)
                      : TTheme.panel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: dailyDone ? TTheme.gold : TTheme.panelBorder,
                    width: 2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('📅  DAILY CHALLENGE',
                            style: TTheme.goldLabel),
                        const Spacer(),
                        Text(
                          dailyDone ? 'DONE  ✓' : '+500 🪙',
                          style: TextStyle(
                            fontFamily: 'RussoOne',
                            fontSize: 14,
                            color: dailyDone
                                ? Colors.greenAccent
                                : TTheme.gold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${daily.title} — ${daily.description}',
                      style: TTheme.body.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dailyDone
                          ? 'Completed today — come back tomorrow for a new one!'
                          : 'Finish it in one run to claim the reward.',
                      style: TTheme.bodyDim.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: Achievement.all.length,
                  itemBuilder: (context, i) {
                    final a = Achievement.all[i];
                    final isUnlocked = unlocked.contains(a.id);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isUnlocked
                            ? TTheme.gold.withOpacity(0.18)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isUnlocked
                              ? TTheme.gold
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            a.icon,
                            style: TextStyle(
                              fontSize: 26,
                              color: isUnlocked
                                  ? null
                                  : Colors.white.withOpacity(0.4),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a.title,
                                  style: TTheme.title.copyWith(fontSize: 16),
                                ),
                                Text(
                                  a.description,
                                  style: TTheme.bodyDim
                                      .copyWith(fontSize: 13),
                                ),
                                if (!isUnlocked)
                                  Text(
                                    _progressHint(a.id, storage),
                                    style: const TextStyle(
                                      fontFamily: 'Nunito',
                                      color: Colors.white38,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Icon(
                            isUnlocked
                                ? Icons.check_circle
                                : Icons.lock_outline,
                            color: isUnlocked
                                ? TTheme.gold
                                : Colors.white38,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Lifetime progress for the two counter-based achievements; empty
  /// otherwise (first-time achievements show no progress line).
  String _progressHint(String id, GameStorage storage) {
    if (id == 'near_miss_10') {
      return 'Progress: ${storage.lifetimeNearMisses} / 10 near misses';
    }
    if (id == 'rockets_5') {
      return 'Progress: ${storage.lifetimeRockets} / 5 rockets';
    }
    return '';
  }
}
