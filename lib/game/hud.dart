import 'package:flutter/foundation.dart';

import 'police.dart';

/// Event-driven HUD state (SPEC §6, game-ui-ux skill).
/// The HUD subscribes to these notifiers and updates only when they fire —
/// it never polls game state every frame. Speed is throttled to 4 updates
/// per second by the game.
class HudPopup {
  HudPopup(this.text, this.points);

  final String text;
  final int points;
  double age = 0.0; // seconds since shown; fades over 0.9 s
}

class HudState {
  final ValueNotifier<double> airFrac = ValueNotifier<double>(1.0);
  final ValueNotifier<int> speedKmh = ValueNotifier<int>(0);
  final ValueNotifier<String> countdown = ValueNotifier<String>('');
  final ValueNotifier<List<HudPopup>> popups =
      ValueNotifier<List<HudPopup>>(<HudPopup>[]);
  final ValueNotifier<bool> rocketActive = ValueNotifier<bool>(false);
  final ValueNotifier<bool> starmanActive = ValueNotifier<bool>(false);
  final ValueNotifier<double> nitroFrac = ValueNotifier<double>(0.0);
  /// FLIP/ROLL buttons light up only while airborne (updated 4×/s).
  final ValueNotifier<bool> airborne = ValueNotifier<bool>(false);

  /// Police chase warning (Round 1): true while a chase is active.
  final ValueNotifier<bool> policeActive = ValueNotifier<bool>(false);

  /// Police distance behind the hero in metres (Round 1 HUD).
  final ValueNotifier<double> policeDistance =
      ValueNotifier<double>(PoliceChase.startBehind);

  /// Current AIR tank capacity in litres (Round 2: upgrades raise it).
  final ValueNotifier<double> airMaxLitres = ValueNotifier<double>(600.0);

  /// Seconds left on the Time Trial clock (Round 6). 60 at run start.
  final ValueNotifier<int> timeLeft = ValueNotifier<int>(60);

  /// Achievement unlock toast (gold banner, shown ~2.5 s). Empty = hidden.
  final ValueNotifier<String> achievementToast = ValueNotifier<String>('');
  double _achievementTimer = 0.0;

  /// Quest-complete toast (Round 3): same gold banner, its own timer.
  final ValueNotifier<String> questToast = ValueNotifier<String>('');
  double _questTimer = 0.0;

  void showAchievementToast(String text) {
    achievementToast.value = text;
    _achievementTimer = 2.5;
  }

  void showQuestToast(String text) {
    questToast.value = text;
    _questTimer = 3.0;
  }

  void showPopup(String text, int points) {
    final list = List<HudPopup>.from(popups.value)
      ..add(HudPopup(text, points));
    // Stacked max 3 (SPEC §6).
    while (list.length > 3) {
      list.removeAt(0);
    }
    popups.value = list;
  }

  void updatePopups(double dt) {
    if (_achievementTimer > 0) {
      _achievementTimer -= dt;
      if (_achievementTimer <= 0) achievementToast.value = '';
    }
    if (_questTimer > 0) {
      _questTimer -= dt;
      if (_questTimer <= 0) questToast.value = '';
    }
    if (popups.value.isEmpty) return;
    var changed = false;
    for (final p in popups.value) {
      p.age += dt;
    }
    final list = popups.value.where((p) => p.age < 0.9).toList();
    if (list.length != popups.value.length) changed = true;
    if (changed || list.isNotEmpty) popups.value = list;
  }

  void reset() {
    airFrac.value = 1.0;
    speedKmh.value = 0;
    countdown.value = '';
    popups.value = <HudPopup>[];
    rocketActive.value = false;
    starmanActive.value = false;
    nitroFrac.value = 0.0;
    airborne.value = false;
    policeActive.value = false;
    policeDistance.value = PoliceChase.startBehind;
    airMaxLitres.value = 600.0;
    timeLeft.value = 60;
    achievementToast.value = '';
    _achievementTimer = 0.0;
    questToast.value = '';
    _questTimer = 0.0;
  }
}
