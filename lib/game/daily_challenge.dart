/// Daily challenge (tuning pass 2026-11-11, user-authorized).
/// Local only: the target for a day is seeded from the calendar date, so
/// every player gets the same challenge on the same day and it changes at
/// midnight. Completion is checked once per finished run; the +500 coin
/// reward is banked immediately and the day is marked done in storage
/// (`tr_daily_date`), so it can only be claimed once per day.
class DailyChallenge {
  const DailyChallenge({
    required this.dateKey,
    required this.title,
    required this.description,
    required this.target,
    required this.kind,
    this.rewardCoins = 500,
  });

  /// 'yyyy-MM-dd' — the seed and the storage key.
  final String dateKey;

  /// Short title shown on Home, e.g. 'STUNT DAY'.
  final String title;

  /// Full target text, e.g. 'Do 8 barrel rolls in one run'.
  final String description;

  /// The number to reach in a single run.
  final int target;

  /// What is counted: 'score' | 'rolls' | 'distance' | 'nearMiss' | 'coins'.
  final String kind;

  final int rewardCoins;

  static String dateKeyFor(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-$d';
  }

  static const List<({String title, String description, int target, String kind})>
      _pool = <({String title, String description, int target, String kind})>[
    (
      title: 'BIG SCORE',
      description: 'Score 15,000 in one run',
      target: 15000,
      kind: 'score',
    ),
    (
      title: 'ROLL OUT',
      description: 'Do 8 barrel rolls in one run',
      target: 8,
      kind: 'rolls',
    ),
    (
      title: 'LONG HAUL',
      description: 'Drive 2,000 m in one run',
      target: 2000,
      kind: 'distance',
    ),
    (
      title: 'CLOSE CALLS',
      description: 'Get 12 near misses in one run',
      target: 12,
      kind: 'nearMiss',
    ),
    (
      title: 'COIN RUSH',
      description: 'Bank 150 coins in one run',
      target: 150,
      kind: 'coins',
    ),
  ];

  /// Today's challenge. The seed is a stable hash of the date string, so
  /// the same date always picks the same challenge.
  static DailyChallenge today([DateTime? now]) {
    final date = now ?? DateTime.now();
    final key = dateKeyFor(date);
    var hash = 0;
    for (var i = 0; i < key.length; i++) {
      hash = (hash * 31 + key.codeUnitAt(i)) & 0x7fffffff;
    }
    final spec = _pool[hash % _pool.length];
    return DailyChallenge(
      dateKey: key,
      title: spec.title,
      description: spec.description,
      target: spec.target,
      kind: spec.kind,
    );
  }

  /// Progress 0.0–1.0 for this run's stats (for the Home progress bar).
  double progressOf({
    required int score,
    required int rolls,
    required int distance,
    required int nearMiss,
    required int coinsEarned,
  }) {
    final value = switch (kind) {
      'score' => score,
      'rolls' => rolls,
      'distance' => distance,
      'nearMiss' => nearMiss,
      'coins' => coinsEarned,
      _ => 0,
    };
    return (value / target).clamp(0.0, 1.0);
  }

  /// True when this run's stats meet the target.
  bool isMetBy({
    required int score,
    required int rolls,
    required int distance,
    required int nearMiss,
    required int coinsEarned,
  }) {
    return progressOf(
      score: score,
      rolls: rolls,
      distance: distance,
      nearMiss: nearMiss,
      coinsEarned: coinsEarned,
    ) >= 1.0;
  }
}
