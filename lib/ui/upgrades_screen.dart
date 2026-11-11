import 'package:flutter/material.dart';

import '../game/game.dart';
import '../game/upgrades.dart';
import 'theme.dart';

/// Upgrades shop (Round 2 improvement). Spend coins on 4 upgrades × 3
/// levels. Opens from the Garage as a Flame overlay. Local only — no
/// account, no server.
class UpgradesScreen extends StatefulWidget {
  const UpgradesScreen({super.key, required this.game});

  final TRoadsterGame game;

  @override
  State<UpgradesScreen> createState() => _UpgradesScreenState();
}

class _UpgradesScreenState extends State<UpgradesScreen> {
  late final Upgrades _ups = Upgrades(widget.game.storage);

  String _iconFor(String id) {
    switch (id) {
      case 'air':
        return '💨';
      case 'rocket':
        return '🚀';
      case 'refill':
        return '⛽';
      case 'magnet':
        return '🧲';
      default:
        return '⬆️';
    }
  }

  Future<void> _buy(UpgradeDef def) async {
    final ok = await _ups.buy(def.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '${def.title} → level ${_ups.level(def.id)}!'
              : 'Not enough coins!',
        ),
        duration: const Duration(milliseconds: 1400),
      ),
    );
    if (ok) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final storage = widget.game.storage;
    return Container(
      color: TTheme.deepPurple,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      widget.game.audio.click();
                      widget.game.overlays.remove('upgrades');
                    },
                  ),
                  const Expanded(
                    child: Text('UPGRADES',
                        textAlign: TextAlign.center, style: TTheme.title),
                  ),
                  Text('🪙 ${storage.coins}',
                      style: TTheme.title.copyWith(fontSize: 16)),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Spend coins. Every level stays yours forever.',
                style: TTheme.bodyDim,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: Upgrades.all.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final def = Upgrades.all[i];
                    final lv = _ups.level(def.id);
                    final cost = _ups.costFor(def.id, lv);
                    final maxed = cost < 0;
                    final afford = !maxed && storage.coins >= cost;
                    return Container(
                      padding: const EdgeInsets.all(14),
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
                              Text(_iconFor(def.id),
                                  style: const TextStyle(fontSize: 26)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(def.title, style: TTheme.goldLabel),
                                    Text(
                                      '${def.description} Now: ${_ups.valueText(def.id)}',
                                      style: TTheme.bodyDim
                                          .copyWith(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              // Level pips.
                              for (int p = 0; p < 3; p++)
                                Container(
                                  width: 26,
                                  height: 8,
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: p < lv
                                        ? TTheme.gold
                                        : Colors.white24,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              const Spacer(),
                              ElevatedButton(
                                onPressed: maxed || !afford
                                    ? null
                                    : () => _buy(def),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      afford ? TTheme.gold : Colors.white24,
                                  foregroundColor: TTheme.deepPurple,
                                ),
                                child: Text(
                                  maxed ? 'MAXED ✓' : 'BUY  🪙 $cost',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
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
}
