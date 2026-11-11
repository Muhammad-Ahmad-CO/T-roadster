import 'package:flutter/material.dart';

import '../game/game.dart';
import '../game/streaks.dart';
import 'theme.dart';

/// Weekly quests screen (Round 3 improvement). Shows this week's 3 quests
/// with live progress bars and coin rewards. Opens from the Home QUESTS
/// tile as a Flame overlay. Progress counts across runs all week; rewards
/// bank automatically the moment a quest completes.
class QuestsScreen extends StatefulWidget {
  const QuestsScreen({super.key, required this.game});

  final TRoadsterGame game;

  @override
  State<QuestsScreen> createState() => _QuestsScreenState();
}

class _QuestsScreenState extends State<QuestsScreen> {
  @override
  void initState() {
    super.initState();
    // Roll the week (no-op when already current) then repaint.
    widget.game.quests.ensureWeek().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final quests = widget.game.quests;
    final list = quests.current;
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
                      widget.game.overlays.remove('quests');
                    },
                  ),
                  const Expanded(
                    child: Text('QUESTS',
                        textAlign: TextAlign.center, style: TTheme.title),
                  ),
                  Text('🪙 ${widget.game.storage.coins}',
                      style: TTheme.title.copyWith(fontSize: 16)),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Three quests every week. Progress counts across runs — finish one and the coins are yours.',
                style: TTheme.bodyDim,
              ),
              const SizedBox(height: 6),
              Text(
                '🔥 ${widget.game.streaks.count}-day streak · Weekly ${widget.game.streaks.weeklyScored} / ${Streaks.weeklyTarget} score',
                style: TTheme.bodyDim,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final def = list[i];
                    final prog = quests.progress(i);
                    final done = quests.done(i);
                    final frac = quests.progressFrac(i);
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: TTheme.panel,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: done ? TTheme.gold : TTheme.panelBorder,
                          width: done ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('🎯',
                                  style: TextStyle(fontSize: 26)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(def.title,
                                    style: TTheme.goldLabel),
                              ),
                              Text(
                                done ? 'DONE ✓' : '+${def.rewardCoins} 🪙',
                                style: TTheme.body.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: done ? TTheme.gold : Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(def.description, style: TTheme.bodyDim),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: frac,
                              minHeight: 10,
                              backgroundColor: Colors.white24,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                done ? TTheme.gold : TTheme.orange,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$prog / ${def.target}',
                            style: TTheme.bodyDim.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Text(
                'New quests every Monday.',
                textAlign: TextAlign.center,
                style: TTheme.bodyDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
