import 'package:shared_preferences/shared_preferences.dart';

/// Persistent state: bests, coins, skins, settings.
/// Saved immediately on crash — never only on quit (a force-killed app
/// must not lose the record). Keys are prefixed `tr_` so they never clash
/// with Color Cover on the same phone.
class GameStorage {
  GameStorage._(this._prefs);

  final SharedPreferences _prefs;

  static Future<GameStorage> load() async {
    return GameStorage._(await SharedPreferences.getInstance());
  }

  // ---- Records ------------------------------------------------------------
  int get bestScore => _prefs.getInt('tr_best_score') ?? 0;
  int get bestDistance => _prefs.getInt('tr_best_distance') ?? 0;

  /// Wrong-Way mode best score (Round 4) — kept apart from the normal best.
  int get bestWrongWay => _prefs.getInt('tr_best_wrongway') ?? 0;

  /// Returns true when a new Wrong-Way best was set.
  Future<bool> saveWrongWayBest(int score) async {
    if (score > bestWrongWay) {
      await _prefs.setInt('tr_best_wrongway', score);
      return true;
    }
    return false;
  }

  /// Time Trial best DISTANCE in 60 s (Round 6) — a distance, not a score.
  int get bestTimeTrial => _prefs.getInt('tr_best_timetrial') ?? 0;

  /// Returns true when a new Time Trial best distance was set.
  Future<bool> saveTimeTrialBest(int distance) async {
    if (distance > bestTimeTrial) {
      await _prefs.setInt('tr_best_timetrial', distance);
      return true;
    }
    return false;
  }
  int get bestCombo => _prefs.getInt('tr_best_combo') ?? 0;
  int get coins => _prefs.getInt('tr_coins') ?? 0;
  int get totalRuns => _prefs.getInt('tr_total_runs') ?? 0;

  /// Returns true when a new best score was set.
  Future<bool> saveRun({
    required int score,
    required int distance,
    required int maxCombo,
    required int coinsEarned,
  }) async {
    var isRecord = false;
    if (score > bestScore) {
      await _prefs.setInt('tr_best_score', score);
      isRecord = true;
    }
    if (distance > bestDistance) {
      await _prefs.setInt('tr_best_distance', distance);
    }
    if (maxCombo > bestCombo) {
      await _prefs.setInt('tr_best_combo', maxCombo);
    }
    await _prefs.setInt('tr_coins', coins + coinsEarned);
    await _prefs.setInt('tr_total_runs', totalRuns + 1);
    await _prefs.setBool('tr_has_played', true);
    return isRecord;
  }

  Future<void> addCoins(int n) async =>
      _prefs.setInt('tr_coins', coins + n);

  Future<void> spendCoins(int n) async =>
      _prefs.setInt('tr_coins', (coins - n).clamp(0, 1 << 30));

  bool get hasPlayed => _prefs.getBool('tr_has_played') ?? false;

  // ---- Achievements (local only, added 2026-11-11 tuning pass) ------------
  /// Unlocked achievement ids (e.g. 'first_flip'). Key prefix `tr_ach_`.
  Set<String> get unlockedAchievements {
    final raw = _prefs.getStringList('tr_ach_unlocked');
    return raw == null ? <String>{} : {...raw};
  }

  bool isAchievementUnlocked(String id) =>
      unlockedAchievements.contains(id);

  /// Returns true when this call newly unlocked the achievement.
  Future<bool> unlockAchievement(String id) async {
    if (isAchievementUnlocked(id)) return false;
    final unlocked = unlockedAchievements..add(id);
    await _prefs.setStringList('tr_ach_unlocked', unlocked.toList());
    return true;
  }

  // Lifetime counters feeding achievements (never reset per run).
  int get lifetimeNearMisses => _prefs.getInt('tr_lt_near_miss') ?? 0;
  Future<void> addLifetimeNearMisses(int n) async =>
      _prefs.setInt('tr_lt_near_miss', lifetimeNearMisses + n);

  int get lifetimeRockets => _prefs.getInt('tr_lt_rockets') ?? 0;
  Future<void> addLifetimeRockets(int n) async =>
      _prefs.setInt('tr_lt_rockets', lifetimeRockets + n);

  // ---- Police chase (Round 1) -------------------------------------------
  int get lifetimePoliceEscapes => _prefs.getInt('tr_lt_police_escapes') ?? 0;
  Future<void> addLifetimePoliceEscapes(int n) async =>
      _prefs.setInt('tr_lt_police_escapes', lifetimePoliceEscapes + n);

  int get lifetimePoliceBusted => _prefs.getInt('tr_lt_police_busted') ?? 0;
  Future<void> addLifetimePoliceBusted(int n) async =>
      _prefs.setInt('tr_lt_police_busted', lifetimePoliceBusted + n);

  // ---- Upgrades (Round 2) ------------------------------------------------
  /// Upgrade levels 0..3, stored per upgrade id (`tr_up_air` etc.).
  int upgradeLevel(String key) => _prefs.getInt(key) ?? 0;
  Future<void> setUpgradeLevel(String key, int level) async =>
      _prefs.setInt(key, level.clamp(0, 3));

  // ---- Quests (Round 3) ----------------------------------------------------
  /// Week key ('yyyy-MM-dd' of the Monday) the stored quests belong to.
  String? get questWeek => _prefs.getString('tr_quest_week');
  Future<void> setQuestWeek(String v) async =>
      _prefs.setString('tr_quest_week', v);

  /// The 3 quest ids active this week.
  List<String> get questIds =>
      _prefs.getStringList('tr_quest_ids') ?? <String>[];
  Future<void> setQuestIds(List<String> ids) async =>
      _prefs.setStringList('tr_quest_ids', ids);

  int questProgress(int slot) => _prefs.getInt('tr_quest_p$slot') ?? 0;
  Future<void> setQuestProgress(int slot, int v) async =>
      _prefs.setInt('tr_quest_p$slot', v);

  bool questDone(int slot) => _prefs.getBool('tr_quest_d$slot') ?? false;
  Future<void> setQuestDone(int slot, bool v) async =>
      _prefs.setBool('tr_quest_d$slot', v);

  // ---- Streaks + weekly challenge (Round 8) -------------------------------
  int get streakCount => _prefs.getInt('tr_streak_count') ?? 0;
  Future<void> setStreakCount(int v) async =>
      _prefs.setInt('tr_streak_count', v);

  /// 'yyyy-MM-dd' of the last day with a finished run.
  String? get streakLastDate => _prefs.getString('tr_streak_last');
  Future<void> setStreakLastDate(String v) async =>
      _prefs.setString('tr_streak_last', v);

  /// Monday key ('yyyy-MM-dd') the weekly total belongs to.
  String? get weeklyWeek => _prefs.getString('tr_weekly_week');
  Future<void> setWeeklyWeek(String v) async =>
      _prefs.setString('tr_weekly_week', v);

  /// Total score banked this week.
  int get weeklyScored => _prefs.getInt('tr_weekly_scored') ?? 0;
  Future<void> setWeeklyScored(int v) async =>
      _prefs.setInt('tr_weekly_scored', v);

  /// True once this week's +2,000 reward has been claimed.
  bool get weeklyClaimed => _prefs.getBool('tr_weekly_claimed') ?? false;
  Future<void> setWeeklyClaimed(bool v) async =>
      _prefs.setBool('tr_weekly_claimed', v);

  // ---- Daily challenge (local only, date-seeded) ---------------------------
  /// Date the daily challenge was last completed, 'yyyy-MM-dd' or ''.
  String get dailyDoneDate => _prefs.getString('tr_daily_date') ?? '';
  bool dailyDoneFor(String dateKey) => dailyDoneDate == dateKey;

  Future<void> markDailyDone(String dateKey) async {
    await _prefs.setString('tr_daily_date', dateKey);
  }

  // ---- Leaderboard (local top-20) ----------------------------------------
  List<int> get localScores {
    final raw = _prefs.getStringList('tr_local_scores') ?? <String>[];
    final out = <int>[];
    for (final s in raw) {
      final v = int.tryParse(s);
      if (v != null) out.add(v);
    }
    return out;
  }

  Future<void> recordScore(int score) async {
    final list = localScores..add(score);
    list.sort((a, b) => b.compareTo(a));
    await _prefs.setStringList(
      'tr_local_scores',
      list.take(20).map((e) => e.toString()).toList(),
    );
  }

  // ---- Pilot / garage -----------------------------------------------------
  String get callsign => _prefs.getString('tr_callsign') ?? 'DRIVER-01';
  Future<void> setCallsign(String v) async =>
      _prefs.setString('tr_callsign', v.trim().isEmpty ? 'DRIVER-01' : v.trim().toUpperCase());

  String get equippedSkin => _prefs.getString('tr_skin') ?? 'pickup';
  String get equippedPaint => _prefs.getString('tr_paint') ?? 'white';

  Set<String> get ownedSkins {
    final raw = _prefs.getStringList('tr_owned_skins');
    if (raw == null) return {'pickup'};
    return {...raw, 'pickup'};
  }

  Future<bool> buySkin(String id, int price) async {
    if (ownedSkins.contains(id) || coins < price) return false;
    await spendCoins(price);
    final owned = ownedSkins..add(id);
    await _prefs.setStringList('tr_owned_skins', owned.toList());
    return true;
  }

  Future<void> equipSkin(String id) async {
    if (ownedSkins.contains(id)) await _prefs.setString('tr_skin', id);
  }

  Future<void> setPaint(String paint) async =>
      _prefs.setString('tr_paint', paint);

  // ---- Settings -----------------------------------------------------------
  /// 'swipe' | 'tilt' | 'both' (default)
  String get controlMode => _prefs.getString('tr_control_mode') ?? 'both';
  Future<void> setControlMode(String v) async =>
      _prefs.setString('tr_control_mode', v);

  /// 'low' | 'medium' | 'high'
  String get tiltSensitivity =>
      _prefs.getString('tr_tilt_sensitivity') ?? 'medium';
  Future<void> setTiltSensitivity(String v) async =>
      _prefs.setString('tr_tilt_sensitivity', v);

  bool get tiltGasBrake => _prefs.getBool('tr_tilt_gas_brake') ?? false;
  Future<void> setTiltGasBrake(bool v) async =>
      _prefs.setBool('tr_tilt_gas_brake', v);

  bool get reduceShake => _prefs.getBool('tr_reduce_shake') ?? false;
  Future<void> setReduceShake(bool v) async =>
      _prefs.setBool('tr_reduce_shake', v);

  bool get reduceFlash => _prefs.getBool('tr_reduce_flash') ?? false;
  Future<void> setReduceFlash(bool v) async =>
      _prefs.setBool('tr_reduce_flash', v);

  double get musicVolume => _prefs.getDouble('tr_music_vol') ?? 0.7;
  double get sfxVolume => _prefs.getDouble('tr_sfx_vol') ?? 0.9;
  double get engineVolume => _prefs.getDouble('tr_engine_vol') ?? 0.8;
  bool get muted => _prefs.getBool('tr_muted') ?? false;

  Future<void> setMusicVolume(double v) async =>
      _prefs.setDouble('tr_music_vol', v.clamp(0.0, 1.0));
  Future<void> setSfxVolume(double v) async =>
      _prefs.setDouble('tr_sfx_vol', v.clamp(0.0, 1.0));
  Future<void> setEngineVolume(double v) async =>
      _prefs.setDouble('tr_engine_vol', v.clamp(0.0, 1.0));
  Future<void> setMuted(bool v) async => _prefs.setBool('tr_muted', v);
}
