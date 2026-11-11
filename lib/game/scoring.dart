import 'package:flutter/foundation.dart';

/// Scoring per SPEC §8, calibrated to the reel run (tuned 2026-11-11,
/// user-authorized: Muse decides the tuning):
/// skilled ~39 s run ≈ 1,420 m ≈ 25,000 pts.
///   score = distance × 10  +  (stunts + bonuses) × multiplier
///   distance points are FLAT — never multiplied.
///   ONLY stunt/bonus points get the combo multiplier.
///   multiplier = 1 + floor(combo / 3), capped ×10.
///   combo timer 4 s; expiry resets combo to 0 (no score lost).
///   Starman doubles ALL points while active (a pickup effect, not the
///   combo multiplier — SPEC §2.6).
/// Calibration: 1,420 m × 10 = 14,200 flat + ~8,000 base stunts/bonuses
/// × ~×1.35 average combo ≈ 10,800 → ≈ 25,000 total ✓ matches 25,681.
/// A cautious no-stunt run of the same distance scores ~14,200 + coins.
class Scoring {
  /// Called by the HUD for every scoring popup (max 3 shown at once).
  void Function(String text, int points)? onPopup;

  final ValueNotifier<int> score = ValueNotifier<int>(0);
  final ValueNotifier<int> distanceM = ValueNotifier<int>(0);
  final ValueNotifier<int> timeS = ValueNotifier<int>(0);
  final ValueNotifier<int> multiplier = ValueNotifier<int>(1);
  final ValueNotifier<int> combo = ValueNotifier<int>(0);
  final ValueNotifier<double> comboFrac = ValueNotifier<double>(0.0);
  final ValueNotifier<int> coins = ValueNotifier<int>(0);

  double distance = 0.0; // metres, fractional
  double _scoreAcc = 0.0;
  double _comboTimer = 0.0;
  double _timeAcc = 0.0;
  int maxCombo = 0;
  int coinsEarned = 0;
  int coinsPicked = 0; // coin pickups this run (for achievements/daily)

  /// Starman doubles all points while active (SPEC §2.6).
  bool starmanActive = false;

  int get currentMultiplier {
    final m = 1 + (combo.value ~/ 3);
    return m > 10 ? 10 : m;
  }

  void reset() {
    distance = 0.0;
    _scoreAcc = 0.0;
    _comboTimer = 0.0;
    _timeAcc = 0.0;
    maxCombo = 0;
    coinsEarned = 0;
    coinsPicked = 0;
    starmanActive = false;
    score.value = 0;
    distanceM.value = 0;
    timeS.value = 0;
    multiplier.value = 1;
    combo.value = 0;
    comboFrac.value = 0.0;
    coins.value = 0;
  }

  void update(double dt) {
    if (_comboTimer > 0) {
      _comboTimer -= dt;
      comboFrac.value = (_comboTimer / 4.0).clamp(0.0, 1.0);
      if (_comboTimer <= 0) {
        combo.value = 0;
        multiplier.value = 1;
        comboFrac.value = 0.0;
      }
    }
    _timeAcc += dt;
    final t = _timeAcc.floor();
    if (t != timeS.value) timeS.value = t;
  }

  /// Distance points: 10 per metre, FLAT — never multiplied by the combo
  /// multiplier (tuning decision 2026-11-11). Starman still doubles
  /// everything while active (pickup effect, SPEC §2.6). Called every tick.
  void addDistance(double metres) {
    distance += metres;
    distanceM.value = distance.floor();
    _scoreAcc += metres * 10.0 * (starmanActive ? 2 : 1);
    score.value = _scoreAcc.floor();
  }

  /// A scoring action: bumps combo, refreshes the 4 s timer, applies the
  /// multiplier, shows a popup. Returns the points actually gained.
  int addAction(int basePoints, String label) {
    combo.value += 1;
    if (combo.value > maxCombo) maxCombo = combo.value;
    _comboTimer = 4.0;
    comboFrac.value = 1.0;
    multiplier.value = currentMultiplier;
    final gained =
        (basePoints * currentMultiplier * (starmanActive ? 2 : 1)).round();
    _scoreAcc += gained;
    score.value = _scoreAcc.floor();
    onPopup?.call(label, gained);
    return gained;
  }

  /// Flat points: added to the score with NO combo multiplier, NO popup,
  /// NO combo bump (police survival +25/s, escape +500 — Round 1).
  /// Starman still doubles (pickup effect, SPEC §2.6).
  void addFlat(int points) {
    _scoreAcc += points * (starmanActive ? 2 : 1);
    score.value = _scoreAcc.floor();
  }

  void addCoins(int n) {
    coinsEarned += n;
    coins.value = coinsEarned;
  }

  // ---- Named actions (SPEC §8.2) -----------------------------------------
  int coin({required bool air}) {
    coinsPicked++;
    addCoins(25);
    return addAction(50, air ? 'AIR COIN +50' : 'COIN +50');
  }

  int nearMiss() => addAction(100, 'NEAR MISS +100');
  int hopOverCar() => addAction(150, 'CLEARED +150');
  int frontFlip() => addAction(400, 'FRONT FLIP +400');
  int barrelRoll() => addAction(500, 'BARREL ROLL +500');
  int doubleStunt() => addAction(1200, 'DOUBLE STUNT +1200');
  int perfectLanding() => addAction(150, 'PERFECT LANDING +150');
  int smash(int chain) => addAction(300, 'SMASH x$chain +300');
  int rampLaunch() => addAction(200, 'RAMP +200');
}
