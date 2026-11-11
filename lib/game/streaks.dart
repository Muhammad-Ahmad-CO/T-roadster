import 'dart:async';

import 'daily_challenge.dart';
import 'quests.dart';
import 'storage.dart';

/// Weekly challenge + streaks (Round 8 improvement). Builds on the daily
/// challenge without replacing it: the daily is one day, this is the week.
///
/// - Streak: consecutive days with at least one finished run. Playing
///   again on the same day does not extend it; missing a day resets it
///   to 1 on the next played day.
/// - Weekly target: bank 100,000 total score in the week (Monday–Sunday).
///   Hit it and a +2,000 coin reward becomes claimable on Home.
class Streaks {
  Streaks(this.storage);

  final GameStorage storage;

  static const int weeklyTarget = 100000;
  static const int weeklyReward = 2000;

  int get count => storage.streakCount;

  int get weeklyScored => storage.weeklyScored;

  bool get weeklyClaimable {
    unawaited(_rollWeek());
    return storage.weeklyScored >= weeklyTarget && !storage.weeklyClaimed;
  }

  double get weeklyFrac {
    unawaited(_rollWeek());
    if (weeklyTarget <= 0) return 0.0;
    return (storage.weeklyScored / weeklyTarget).clamp(0.0, 1.0);
  }

  /// A new week (Monday) resets the weekly total + claim flag.
  Future<void> _rollWeek() async {
    final key = Quests.weekKeyFor(DateTime.now());
    if (storage.weeklyWeek != key) {
      await storage.setWeeklyWeek(key);
      await storage.setWeeklyScored(0);
      await storage.setWeeklyClaimed(false);
    }
  }

  /// Called once per finished run (from _finishCrash). Updates the streak
  /// and banks the run's score into the weekly total.
  Future<void> noteRun(int score) async {
    final today = DailyChallenge.dateKeyFor(DateTime.now());
    final last = storage.streakLastDate;
    if (last != today) {
      final yesterday =
          DailyChallenge.dateKeyFor(DateTime.now().subtract(
        const Duration(days: 1),
      ));
      final next = last == yesterday ? storage.streakCount + 1 : 1;
      await storage.setStreakCount(next);
      await storage.setStreakLastDate(today);
    }
    await _rollWeek();
    await storage.setWeeklyScored(storage.weeklyScored + score);
  }

  /// Claim the +2,000 weekly reward. Returns false when not claimable.
  Future<bool> claimWeekly() async {
    await _rollWeek();
    if (storage.weeklyScored < weeklyTarget || storage.weeklyClaimed) {
      return false;
    }
    await storage.setWeeklyClaimed(true);
    await storage.addCoins(weeklyReward);
    return true;
  }
}
