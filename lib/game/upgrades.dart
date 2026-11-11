import 'storage.dart';

/// Upgrades shop (Round 2 improvement). Spend coins on 4 upgrades, 3 levels
/// each, local only. All effects are read by the game at run start — the
/// hero car never reads storage itself (one direction of dependency).
class UpgradeDef {
  const UpgradeDef({
    required this.id,
    required this.title,
    required this.description,
    required this.costs,
    required this.unit,
  });

  final String id;
  final String title;
  final String description;

  /// Cost per level: costs[0] buys level 1, costs[2] buys level 3.
  final List<int> costs;
  final String unit;
}

class Upgrades {
  Upgrades(this.storage);

  final GameStorage storage;

  static const List<UpgradeDef> all = <UpgradeDef>[
    UpgradeDef(
      id: 'air',
      title: 'AIR TANK',
      description: 'Bigger thruster tank: 600 → 750 → 900 L.',
      costs: <int>[800, 2000, 4500],
      unit: 'L',
    ),
    UpgradeDef(
      id: 'rocket',
      title: 'ROCKET TIME',
      description: 'Rocket Mode lasts longer: 6 → 7.5 → 9 s.',
      costs: <int>[1000, 2500, 5000],
      unit: 's',
    ),
    UpgradeDef(
      id: 'refill',
      title: 'AIR REFILL',
      description: 'Faster AIR refill on the road: 60 → 75 → 90 L/s.',
      costs: <int>[600, 1500, 3000],
      unit: 'L/s',
    ),
    UpgradeDef(
      id: 'magnet',
      title: 'COIN MAGNET',
      description: 'Coins pulled from further away: 1.2 → 1.8 → 2.4 m.',
      costs: <int>[500, 1200, 2500],
      unit: 'm',
    ),
  ];

  static UpgradeDef byId(String id) =>
      all.firstWhere((u) => u.id == id);

  String _key(String id) => 'tr_up_$id';

  int level(String id) => storage.upgradeLevel(_key(id));

  int costFor(String id, int level) {
    final def = byId(id);
    if (level >= def.costs.length) return -1; // maxed
    return def.costs[level];
  }

  /// Buy the next level. Returns false when maxed or not enough coins.
  Future<bool> buy(String id) async {
    final lv = level(id);
    final cost = costFor(id, lv);
    if (cost < 0 || storage.coins < cost) return false;
    await storage.spendCoins(cost);
    await storage.setUpgradeLevel(_key(id), lv + 1);
    return true;
  }

  // ---- Effective values (read by the game at run start) -------------------
  double get airCapacity => 600.0 + 150.0 * level('air');
  double get rocketDuration => 6.0 + 1.5 * level('rocket');
  double get refillRate => 60.0 + 15.0 * level('refill');
  double get magnetRadius => 1.2 + 0.6 * level('magnet');

  String valueText(String id) {
    switch (id) {
      case 'air':
        return '${airCapacity.round()} L';
      case 'rocket':
        return '${rocketDuration.toStringAsFixed(1)} s';
      case 'refill':
        return '${refillRate.round()} L/s';
      case 'magnet':
        return '${magnetRadius.toStringAsFixed(1)} m';
      default:
        return '';
    }
  }
}
