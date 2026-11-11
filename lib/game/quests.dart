import 'dart:math' as math;

import 'storage.dart';

/// Weekly quests (Round 3 improvement). Three quests rotate every Monday,
/// progress is saved locally and counts across runs all week; completing one
/// banks its coin reward immediately (same rule as the daily challenge).
/// Kinds are the same counters the game already tracks — nothing new is
/// counted, only accumulated weekly.
class QuestDef {
  const QuestDef({
    required this.id,
    required this.title,
    required this.description,
    required this.target,
    required this.kind,
    required this.rewardCoins,
  });

  final String id;
  final String title;
  final String description;
  final int target;

  /// What is counted: 'rolls' | 'flips' | 'nearMiss' | 'distance' |
  /// 'coins' | 'smash' | 'rockets' | 'score'.
  final String kind;
  final int rewardCoins;
}

class Quests {
  Quests(this.storage);

  final GameStorage storage;

  static const List<QuestDef> pool = <QuestDef>[
    QuestDef(
      id: 'rolls',
      title: 'ROLL STAR',
      description: 'Do 20 barrel rolls this week',
      target: 20,
      kind: 'rolls',
      rewardCoins: 800,
    ),
    QuestDef(
      id: 'flips',
      title: 'FLIP FRENZY',
      description: 'Do 15 front flips this week',
      target: 15,
      kind: 'flips',
      rewardCoins: 800,
    ),
    QuestDef(
      id: 'near_miss',
      title: 'CLOSE CALLS',
      description: 'Get 30 near misses this week',
      target: 30,
      kind: 'nearMiss',
      rewardCoins: 1000,
    ),
    QuestDef(
      id: 'distance',
      title: 'LONG HAUL',
      description: 'Drive 10,000 m this week',
      target: 10000,
      kind: 'distance',
      rewardCoins: 1200,
    ),
    QuestDef(
      id: 'coins',
      title: 'COIN RUSH',
      description: 'Bank 500 coins this week',
      target: 500,
      kind: 'coins',
      rewardCoins: 1000,
    ),
    QuestDef(
      id: 'smash',
      title: 'WRECKING CREW',
      description: 'Smash 10 cars (Rocket / Starman) this week',
      target: 10,
      kind: 'smash',
      rewardCoins: 1000,
    ),
    QuestDef(
      id: 'rockets',
      title: 'ROCKET RIDER',
      description: 'Grab 8 Rocket pickups this week',
      target: 8,
      kind: 'rockets',
      rewardCoins: 800,
    ),
    QuestDef(
      id: 'score',
      title: 'HIGH SCORER',
      description: 'Score 50,000 total this week',
      target: 50000,
      kind: 'score',
      rewardCoins: 1500,
    ),
  ];

  /// Week key = the Monday of this week ('yyyy-MM-dd'). Stable, rotates
  /// every Monday at midnight local time.
  static String weekKeyFor(DateTime date) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    final m = monday.month.toString().padLeft(2, '0');
    final d = monday.day.toString().padLeft(2, '0');
    return '${monday.year}-$m-$d';
  }

  /// Rolls the week's 3 quests when the stored week is stale (or empty).
  /// The pick is seeded by the week key, so every player gets the same
  /// three quests in the same week.
  Future<void> ensureWeek() async {
    final key = weekKeyFor(DateTime.now());
    if (storage.questWeek == key && storage.questIds.length == 3) return;
    var hash = 0;
    for (var i = 0; i < key.length; i++) {
      hash = (hash * 31 + key.codeUnitAt(i)) & 0x7fffffff;
    }
    final start = hash % pool.length;
    final ids = <String>[
      for (var k = 0; k < 3; k++) pool[(start + k) % pool.length].id,
    ];
    await storage.setQuestWeek(key);
    await storage.setQuestIds(ids);
    for (var s = 0; s < 3; s++) {
      await storage.setQuestProgress(s, 0);
      await storage.setQuestDone(s, false);
    }
  }

  /// This week's 3 quests (falls back to the first 3 before the first
  /// ensureWeek has run — e.g. the Home screen on a cold start).
  List<QuestDef> get current {
    final ids = storage.questIds;
    if (ids.length != 3) return pool.sublist(0, 3);
    return ids
        .map((id) => pool.firstWhere((d) => d.id == id, orElse: () => pool[0]))
        .toList();
  }

  int progress(int slot) => storage.questProgress(slot);

  bool done(int slot) => storage.questDone(slot);

  double progressFrac(int slot) {
    final def = current[slot];
    if (def.target <= 0) return 0.0;
    return (progress(slot) / def.target).clamp(0.0, 1.0);
  }

  /// Add [amount] to every active quest of [kind]. Returns the quests
  /// completed by this call (reward already banked).
  Future<List<QuestDef>> addProgress(String kind, int amount) async {
    await ensureWeek();
    final completed = <QuestDef>[];
    final qs = current;
    for (var s = 0; s < qs.length; s++) {
      final def = qs[s];
      if (def.kind != kind || storage.questDone(s)) continue;
      final next =
          math.min(def.target, storage.questProgress(s) + amount);
      await storage.setQuestProgress(s, next);
      if (next >= def.target) {
        await storage.setQuestDone(s, true);
        await storage.addCoins(def.rewardCoins);
        completed.add(def);
      }
    }
    return completed;
  }
}
