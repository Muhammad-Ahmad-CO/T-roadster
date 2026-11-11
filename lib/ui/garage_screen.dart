import 'package:flutter/material.dart';

import '../game/game.dart';
import 'theme.dart';

/// Garage / Locker (SPEC §3.3; Round 7: 6 skins + 12 paints).
/// Skins — White Pickup (default), Sunset Sports (5,000), Night Neon
/// (15,000), Aero Coupe (8,000), Desert Rally (12,000), Arctic Truck
/// (complete any weekly quest). All cosmetic: speed/handling identical.
/// 12 paints for every skin. Skins actually change the car's silhouette
/// now (car.dart draw branches on skin — v1 stored the skin but drew the
/// same pickup for all three).
class GarageScreen extends StatefulWidget {
  const GarageScreen({super.key, required this.game});

  final TRoadsterGame game;

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  static const _skins = <Map<String, dynamic>>[
    {
      'id': 'pickup',
      'name': 'WHITE PICKUP',
      'desc': 'The reel car. Angular, white, light bar.',
      'price': 0,
      'color': Color(0xFFF5F5F5),
    },
    {
      'id': 'sports',
      'name': 'SUNSET SPORTS',
      'desc': 'The low sports car from the other clips.',
      'price': 5000,
      'color': Color(0xFFFF7E3D),
    },
    {
      'id': 'neon',
      'name': 'NIGHT NEON',
      'desc': 'Under-glow + neon trim for midnight runs.',
      'price': 15000,
      'color': Color(0xFF00F0FF),
    },
    {
      'id': 'coupe',
      'name': 'AERO COUPE',
      'desc': 'Low, wide, big spoiler. The sleek one.',
      'price': 8000,
      'color': Color(0xFFFF7043),
    },
    {
      'id': 'rally',
      'name': 'DESERT RALLY',
      'desc': 'Roof rack + spare wheel. Built for the dunes.',
      'price': 12000,
      'color': Color(0xFFC98A4B),
    },
    {
      'id': 'arctic',
      'name': 'ARCTIC TRUCK',
      'desc': 'Roof light bar + off-road wheels. Quest reward.',
      'price': 0,
      'color': Color(0xFFE8EEF2),
      'unlock': 'quest',
    },
  ];

  static const _paints = <Map<String, dynamic>>[
    {'id': 'white', 'name': 'White', 'color': Color(0xFFF5F5F5)},
    {'id': 'black', 'name': 'Black', 'color': Color(0xFF1A1A1F)},
    {'id': 'red', 'name': 'Red', 'color': Color(0xFFD32F2F)},
    {'id': 'blue', 'name': 'Blue', 'color': Color(0xFF1565C0)},
    {'id': 'gold', 'name': 'Gold', 'color': Color(0xFFFFC531)},
    {'id': 'pink', 'name': 'Pink', 'color': Color(0xFFEC407A)},
    {'id': 'teal', 'name': 'Teal', 'color': Color(0xFF00897B)},
    {'id': 'purple', 'name': 'Purple', 'color': Color(0xFF7E57C2)},
    {'id': 'orange', 'name': 'Orange', 'color': Color(0xFFFF7043)},
    {'id': 'lime', 'name': 'Lime', 'color': Color(0xFF9CCC65)},
    {'id': 'silver', 'name': 'Silver', 'color': Color(0xFFB0BEC5)},
    {'id': 'navy', 'name': 'Navy', 'color': Color(0xFF1A237E)},
  ];

  @override
  Widget build(BuildContext context) {
    final storage = widget.game.storage;
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
                      widget.game.audio.click();
                      widget.game.overlays.remove('garage');
                    },
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text('GARAGE',
                        textAlign: TextAlign.center, style: TTheme.title),
                  ),
                  Text('🪙 ${storage.coins}', style: TTheme.title.copyWith(fontSize: 16)),
                ],
              ),
              const SizedBox(height: 12),
              const Text('SKINS — cosmetic only, same speed',
                  style: TTheme.bodyDim),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    ..._skins.map((skin) => _skinCard(skin)),
                    const SizedBox(height: 16),
                    const Text('PAINT — all skins', style: TTheme.bodyDim),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _paints.map((paint) {
                        final selected =
                            storage.equippedPaint == paint['id'];
                        return GestureDetector(
                          onTap: () {
                            widget.game.audio.click();
                            storage.setPaint(paint['id'] as String);
                            setState(() {});
                          },
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: paint['color'] as Color,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? TTheme.gold
                                    : Colors.white30,
                                width: selected ? 3 : 1.5,
                              ),
                              // Gold glow on the equipped paint (Round 7).
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: TTheme.gold.withOpacity(0.5),
                                        blurRadius: 10,
                                      ),
                                    ]
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: selected
                                ? const Icon(Icons.check,
                                    color: Colors.black54)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    TTheme.goldButton(
                      label: '⚡ UPGRADES SHOP',
                      height: 56,
                      fontSize: 20,
                      onPressed: () {
                        widget.game.audio.click();
                        widget.game.overlays.add('upgrades');
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _skinCard(Map<String, dynamic> skin) {
    final storage = widget.game.storage;
    final id = skin['id'] as String;
    final price = skin['price'] as int;
    final owned = storage.ownedSkins.contains(id);
    final equipped = storage.equippedSkin == id;
    // Arctic Truck (Round 7): unlocks by completing ANY weekly quest
    // this week — no coins needed, just play.
    final questLocked = skin['unlock'] == 'quest' &&
        !storage.questDone(0) &&
        !storage.questDone(1) &&
        !storage.questDone(2);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: equipped ? TTheme.gold : TTheme.panelBorder,
          width: equipped ? 2.5 : 1.5,
        ),
        // Gold equipped glow (Round 7 graphics).
        boxShadow: equipped
            ? [
                BoxShadow(
                  color: TTheme.gold.withOpacity(0.45),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          // Gloss showcase swatch (Round 7 graphics): shiny highlight
          // over the top half of the colour chip.
          Stack(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: skin['color'] as Color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.directions_car,
                    color: Colors.black54, size: 32),
              ),
              Container(
                width: 56,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.45),
                      Colors.white.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
              // Turntable spotlight sweep (Round 47): a showroom light
              // beam sweeps across each skin swatch.
              const _SweepOverlay(),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(skin['name'] as String,
                    style: TTheme.title.copyWith(fontSize: 17)),
                Text(skin['desc'] as String, style: TTheme.bodyDim),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            height: 44,
            child: ElevatedButton(
              onPressed: () async {
                widget.game.audio.click();
                if (equipped) return;
                if (questLocked) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Complete any weekly quest to unlock the Arctic Truck!'),
                      ),
                    );
                  }
                  return;
                }
                if (owned) {
                  await storage.equipSkin(id);
                } else {
                  final ok = await storage.buySkin(id, price);
                  if (ok) await storage.equipSkin(id);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Not enough coins yet — keep driving!'),
                      ),
                    );
                  }
                }
                setState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    equipped ? TTheme.gold : TTheme.orange,
                foregroundColor: TTheme.deepPurple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                equipped
                    ? 'EQUIPPED'
                    : (owned
                        ? 'EQUIP'
                        : (questLocked ? '🔒 QUEST' : '🪙 $price')),
                style: const TextStyle(
                  fontFamily: 'RussoOne',
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Garage turntable lighting (Round 47): a spotlight beam sweeps across
/// each skin swatch, like a showroom turntable light.
class _SweepOverlay extends StatefulWidget {
  const _SweepOverlay();
  @override
  State<_SweepOverlay> createState() => _SweepOverlayState();
}

class _SweepOverlayState extends State<_SweepOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final v = _ctrl.value;
        return Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + v * 2.5, -1.0),
              end: Alignment(1.0 + v * 2.5, 1.0),
              colors: [
                Colors.white.withValues(alpha: 0.0),
                Colors.white.withValues(alpha: 0.45),
                Colors.white.withValues(alpha: 0.0),
              ],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}
