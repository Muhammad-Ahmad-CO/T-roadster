import 'storage.dart';

/// Local-only achievements (tuning pass 2026-11-11, user-authorized).
/// 10 achievements, all unlocked from local play — no server, no login.
/// Progress is saved in [GameStorage] under `tr_ach_*` / `tr_lt_*` keys,
/// so it survives app restarts and force-kills.
class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String id;
  final String title;
  final String description;
  final String icon; // emoji — matches the 🪙 style used across the UI

  static const List<Achievement> all = <Achievement>[
    Achievement(
      id: 'first_drive',
      title: 'First Drive',
      description: 'Finish your first run.',
      icon: '🚗',
    ),
    Achievement(
      id: 'first_flip',
      title: 'First Flip',
      description: 'Land your first front flip.',
      icon: '🔄',
    ),
    Achievement(
      id: 'first_roll',
      title: 'First Roll',
      description: 'Land your first barrel roll.',
      icon: '🌀',
    ),
    Achievement(
      id: 'near_miss_10',
      title: 'Close Calls',
      description: 'Rack up 10 near misses (lifetime).',
      icon: '💨',
    ),
    Achievement(
      id: 'score_25k',
      title: '25K Club',
      description: 'Score 25,000+ in a single run.',
      icon: '⭐',
    ),
    Achievement(
      id: 'distance_2k',
      title: 'Long Haul',
      description: 'Drive 2,000 m in a single run.',
      icon: '🛣️',
    ),
    Achievement(
      id: 'rockets_5',
      title: 'Rocket Man',
      description: 'Collect 5 Rocket pickups (lifetime).',
      icon: '🚀',
    ),
    Achievement(
      id: 'coins_100',
      title: 'Coin Rush',
      description: 'Bank 100 coins in a single run.',
      icon: '🪙',
    ),
    Achievement(
      id: 'runs_10',
      title: 'Regular Driver',
      description: 'Finish 10 runs.',
      icon: '🏁',
    ),
    Achievement(
      id: 'first_record',
      title: 'Record Breaker',
      description: 'Set your first NEW RECORD.',
      icon: '🏆',
    ),
  ];

  static Achievement? byId(String id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }
}

/// Tracks achievement events during play and unlocks them in storage.
/// The game wires [onUnlock] to the HUD toast + chime; the tracker never
/// touches the UI itself.
class AchievementTracker {
  AchievementTracker(this.storage);

  final GameStorage storage;

  /// Called with each newly unlocked achievement title (gold toast + chime).
  void Function(String title)? onUnlock;

  /// Unlocks [id] if it is new; fires [onUnlock] and returns true.
  Future<bool> _unlock(String id) async {
    final isNew = await storage.unlockAchievement(id);
    if (isNew) {
      final def = Achievement.byId(id);
      if (def != null) onUnlock?.call(def.title);
    }
    return isNew;
  }

  /// Call after a front flip completes (stunt finished in the air).
  Future<bool> onFlip() => _unlock('first_flip');

  /// Call after a barrel roll completes (stunt finished in the air).
  Future<bool> onRoll() => _unlock('first_roll');

  /// Call on every near miss; unlocks at 10 lifetime near misses.
  Future<bool> onNearMiss() async {
    await storage.addLifetimeNearMisses(1);
    if (storage.lifetimeNearMisses >= 10) {
      return _unlock('near_miss_10');
    }
    return false;
  }

  /// Call on every Rocket pickup; unlocks at 5 lifetime rockets.
  Future<bool> onRocket() async {
    await storage.addLifetimeRockets(1);
    if (storage.lifetimeRockets >= 5) {
      return _unlock('rockets_5');
    }
    return false;
  }

  /// Call once per finished run. Returns the ids newly unlocked this run.
  /// [totalRuns] is the stored total AFTER this run was saved.
  Future<List<String>> onRunEnd({
    required int score,
    required int distance,
    required int coinsEarned,
    required bool isRecord,
    required int totalRuns,
  }) async {
    final unlocked = <String>[];
    Future<bool> tryUnlock(String id) async {
      final isNew = await _unlock(id);
      if (isNew) unlocked.add(id);
      return isNew;
    }

    await tryUnlock('first_drive');
    if (score >= 25000) await tryUnlock('score_25k');
    if (distance >= 2000) await tryUnlock('distance_2k');
    if (coinsEarned >= 100) await tryUnlock('coins_100');
    if (totalRuns >= 10) await tryUnlock('runs_10');
    if (isRecord) await tryUnlock('first_record');
    return unlocked;
  }

  int get unlockedCount => storage.unlockedAchievements.length;
  int get totalCount => Achievement.all.length;
}
