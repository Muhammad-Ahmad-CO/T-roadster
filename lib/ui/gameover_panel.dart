import 'package:flutter/material.dart';

import '../game/game.dart';
import 'share_card.dart';
import 'theme.dart';

/// Game-over panel (SPEC §9): slides up at 1.2 s after impact.
/// NEW RECORD (gold, animated shine) or CRASHED; score / distance / time /
/// max combo / rank / coins; DRIVE AGAIN (focused — Enter restarts) + MENU.
/// Round 9: a shareable results card (RepaintBoundary) + SHARE button that
/// saves it as a PNG on the device.
class GameOverPanel extends StatefulWidget {
  const GameOverPanel({super.key, required this.game});

  final TRoadsterGame game;

  @override
  State<GameOverPanel> createState() => _GameOverPanelState();
}

class _GameOverPanelState extends State<GameOverPanel> {
  final GlobalKey _cardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final data = game.lastGameOver;
    if (data == null) return const SizedBox.shrink();
    return Container(
      color: Colors.black45,
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: TTheme.panelBox(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Game-over gold shine sweep (Round 48): the NEW
                  // RECORD header shimmers with a moving light band.
                  if (data.isRecord &&
                      data.crashKind != 'police' &&
                      data.crashKind != 'timeup')
                    _ShineText(
                      text: '★  NEW RECORD  ★',
                      style: TTheme.title.copyWith(
                        fontSize: 30,
                        color: TTheme.gold,
                      ),
                    )
                  else
                    Text(
                      data.crashKind == 'police'
                          ? '🚔  BUSTED!'
                          : (data.crashKind == 'timeup'
                              ? '⏱  TIME UP!'
                              : (data.isRecord
                                  ? '★  NEW RECORD  ★'
                                  : 'CRASHED')),
                      textAlign: TextAlign.center,
                      style: TTheme.title.copyWith(
                        fontSize: 30,
                        color: data.isRecord ? TTheme.gold : Colors.white,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    '${data.score}',
                    textAlign: TextAlign.center,
                    style: TTheme.display.copyWith(fontSize: 56),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'BEST  ${data.bestScore}',
                    textAlign: TextAlign.center,
                    style: TTheme.bodyDim,
                  ),
                  const SizedBox(height: 16),
                  _statGrid(data),
                  const SizedBox(height: 12),
                  if (data.newAchievements.isNotEmpty)
                    Text(
                      '🏆 NEW: ${data.newAchievements.join(', ')}',
                      textAlign: TextAlign.center,
                      style: TTheme.body.copyWith(
                        fontSize: 14,
                        color: TTheme.gold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (data.newAchievements.isNotEmpty)
                    const SizedBox(height: 6),
                  if (data.newQuests.isNotEmpty)
                    Text(
                      '🎯 QUEST DONE: ${data.newQuests.join(', ')}',
                      textAlign: TextAlign.center,
                      style: TTheme.body.copyWith(
                        fontSize: 14,
                        color: TTheme.magenta,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (data.newQuests.isNotEmpty)
                    const SizedBox(height: 6),
                  if (data.isWrongWay)
                    const Text(
                      '🔄 WRONG-WAY MODE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'RussoOne',
                        fontSize: 14,
                        color: Color(0xFFD32F2F),
                      ),
                    ),
                  if (data.isWrongWay) const SizedBox(height: 6),
                  if (data.isTimeTrial)
                    Text(
                      '⏱ TIME TRIAL — BEST DISTANCE ${data.bestScore} m IN 60 S',
                      textAlign: TextAlign.center,
                      style: TTheme.body.copyWith(
                        fontSize: 14,
                        color: TTheme.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (data.isTimeTrial) const SizedBox(height: 6),
                  if (data.dailyDone)
                    const Text(
                      '📅 DAILY CHALLENGE DONE  +500 🪙',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'RussoOne',
                        fontSize: 14,
                        color: TTheme.gold,
                      ),
                    ),
                  if (data.dailyDone) const SizedBox(height: 6),
                  Text(
                    'Score ${data.score}  ·  Picked up ${data.coinsEarned} coins  ·  Total banked',
                    textAlign: TextAlign.center,
                    style: TTheme.bodyDim.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  // Share card (Round 9): the results card, captured to PNG
                  // by the SHARE button below.
                  RepaintBoundary(
                    key: _cardKey,
                    child: ShareCard(
                      data: data,
                      callsign: game.storage.callsign,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TTheme.ghostButton(
                    label: '📤  SHARE RESULT CARD',
                    onPressed: () async {
                      game.audio.click();
                      final path =
                          await saveShareCard(_cardKey, data.score);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(path == null
                              ? 'Couldn\'t save the card — try again.'
                              : 'Saved! $path'),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  TTheme.goldButton(
                    label: '↻  DRIVE AGAIN',
                    autofocus: true,
                    onPressed: () {
                      game.audio.click();
                      game.startRun();
                    },
                  ),
                  const SizedBox(height: 10),
                  TTheme.ghostButton(
                    label: 'MENU',
                    onPressed: () {
                      game.audio.click();
                      game.quitToMenu();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  Widget _statGrid(GameOverData data) {
    Widget cell(String label, String value) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: TTheme.title.copyWith(fontSize: 20)),
            const SizedBox(height: 2),
            Text(label, style: TTheme.bodyDim.copyWith(fontSize: 12)),
          ],
        ),
      );
    }

    final mm = (data.timeS ~/ 60).toString();
    final ss = (data.timeS % 60).toString().padLeft(2, '0');
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.35,
      children: [
        cell('DISTANCE', '${data.distance} m'),
        cell('TIME', '$mm:$ss'),
        cell('MAX COMBO', '×${data.maxCombo}'),
        cell('RANK', '#${data.rank}'),
        cell('COINS', '+${data.coinsEarned}'),
        cell('BEST', '${data.bestScore}'),
      ],
    );
  }
}

/// Game-over gold shine sweep (Round 48): a moving light band across the
/// NEW RECORD header, driven by its own 2.8 s loop.
class _ShineText extends StatefulWidget {
  const _ShineText({required this.text, required this.style});
  final String text;
  final TextStyle style;
  @override
  State<_ShineText> createState() => _ShineTextState();
}

class _ShineTextState extends State<_ShineText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
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
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [
              Color(0xFFFFC531),
              Color(0xFFFFFFFF),
              Color(0xFFFFC531),
            ],
            stops: [
              (v - 0.25).clamp(0.0, 1.0),
              v,
              (v + 0.25).clamp(0.0, 1.0),
            ],
          ).createShader(bounds),
          child: Text(
            widget.text,
            textAlign: TextAlign.center,
            style: widget.style,
          ),
        );
      },
    );
  }
}
