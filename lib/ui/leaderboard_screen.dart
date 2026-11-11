import 'package:flutter/material.dart';

import '../game/game.dart';
import 'theme.dart';

/// Leaderboard (SPEC §3.8): GLOBAL TOP 500 header (matches the original),
/// v1 = local top-20 + 30 seeded ghost entries so the list feels alive.
/// The player's rank is labelled LOCAL RANK honestly — never faked as live.
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key, required this.game});

  final TRoadsterGame game;

  @override
  Widget build(BuildContext context) {
    final storage = game.storage;
    final local = storage.localScores;
    final best = storage.bestScore;

    // Merge local scores with the seeded ghosts, best first.
    final entries = <({int score, bool mine})>[];
    for (final s in local) {
      entries.add((score: s, mine: true));
    }
    for (final s in kGhostScores) {
      entries.add((score: s, mine: false));
    }
    entries.sort((a, b) => b.score.compareTo(a.score));
    final shown = entries.take(20).toList();

    var localRank = 1;
    for (final s in local) {
      if (s > best && best > 0) localRank++;
    }
    // Rank among ghosts + locals for the header line.
    var globalRank = 1;
    for (final e in entries) {
      if (e.score > best && best > 0) globalRank++;
    }

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
                      game.audio.click();
                      game.overlays.remove('leaderboard');
                    },
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text('GLOBAL TOP 500',
                        textAlign: TextAlign.center, style: TTheme.title),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                best > 0
                    ? 'YOUR RANK  #$globalRank  ·  LOCAL RANK  #$localRank'
                    : 'No runs yet — press DRIVE and set a score!',
                textAlign: TextAlign.center,
                style: TTheme.bodyDim,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  game.audio.click();
                  game.overlays.add('achievements');
                },
                icon: const Text('🏆', style: TextStyle(fontSize: 18)),
                label: Text(
                  'ACHIEVEMENTS  ${game.storage.unlockedAchievements.length}/10',
                  style: const TextStyle(
                    fontFamily: 'RussoOne',
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: TTheme.gold, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final e = shown[i];
                    final isBest = e.mine && e.score == best && best > 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: e.mine
                            ? TTheme.gold.withOpacity(0.2)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: e.mine
                              ? TTheme.gold
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 40,
                            child: Text(
                              '#${i + 1}',
                              style: TTheme.title.copyWith(fontSize: 16),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              e.mine
                                  ? '${storage.callsign}${isBest ? '  ★ YOU' : ''}'
                                  : 'PILOT-${1000 + i * 37}',
                              style: TTheme.body,
                            ),
                          ),
                          Text(
                            '${e.score}',
                            style: TTheme.title.copyWith(fontSize: 16),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Text(
                'v1 leaderboard is local + seeded ghosts.\nReal online boards arrive in Phase 2.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Nunito',
                    color: Colors.white38,
                    fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
