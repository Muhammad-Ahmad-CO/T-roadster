import 'package:flutter/material.dart';

import '../game/game.dart';
import '../game/input.dart';
import 'theme.dart';

/// Pause panel (SPEC §3.6): dim + blur the road behind; Resume / Restart /
/// Quit, sound + music sliders, controls setting, how-to recap.
/// Resume = quick 3-2-1 countdown (1 s total).
class PauseOverlay extends StatefulWidget {
  const PauseOverlay({super.key, required this.game});

  final TRoadsterGame game;

  @override
  State<PauseOverlay> createState() => _PauseOverlayState();
}

class _PauseOverlayState extends State<PauseOverlay> {
  @override
  Widget build(BuildContext context) {
    final storage = widget.game.storage;
    // Cinema mode (Round 10): a transparent frame over the frozen scene —
    // no dim, no menu — with orbit/zoom controls along the bottom.
    if (widget.game.cinema) return _cinemaView();
    return Container(
      color: Colors.black54,
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: TTheme.panelBox(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('PAUSED',
                      textAlign: TextAlign.center, style: TTheme.title),
                  const SizedBox(height: 16),
                  TTheme.goldButton(
                    label: '▶  RESUME',
                    onPressed: () {
                      widget.game.audio.click();
                      widget.game.resumeGame();
                    },
                  ),
                  const SizedBox(height: 10),
                  TTheme.ghostButton(
                    label: '↻  RESTART',
                    onPressed: () {
                      widget.game.audio.click();
                      widget.game.startRun();
                    },
                  ),
                  const SizedBox(height: 10),
                  TTheme.ghostButton(
                    label: '🎬  CINEMA MODE',
                    onPressed: () {
                      widget.game.audio.click();
                      widget.game.enterCinema();
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 10),
                  TTheme.ghostButton(
                    label: 'MENU',
                    onPressed: () {
                      widget.game.audio.click();
                      widget.game.quitToMenu();
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text('CONTROLS', style: TTheme.goldLabel),
                  const SizedBox(height: 8),
                  _controlModeRow(storage.controlMode),
                  const SizedBox(height: 16),
                  const Text('SOUND', style: TTheme.goldLabel),
                  _sliderRow(
                    'Music',
                    storage.musicVolume,
                    (v) {
                      storage.setMusicVolume(v);
                      widget.game.audio.setVolumes(
                        music: v,
                        sfx: storage.sfxVolume,
                        engine: storage.engineVolume,
                      );
                      setState(() {});
                    },
                  ),
                  _sliderRow(
                    'Effects',
                    storage.sfxVolume,
                    (v) {
                      storage.setSfxVolume(v);
                      widget.game.audio.setVolumes(
                        music: storage.musicVolume,
                        sfx: v,
                        engine: storage.engineVolume,
                      );
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'HOW TO PLAY\n'
                    'Swipe or tilt to steer · Hold HOP to fly\n'
                    'FLIP / ROLL in the air for points · BOOST for nitro\n'
                    'Dodge traffic — one crash ends the run!',
                    textAlign: TextAlign.center,
                    style: TTheme.bodyDim,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Cinema view (Round 10): drag anywhere to orbit the camera around the
  /// frozen car (±75°), zoom buttons, and the phone's own screenshot keys
  /// to save the shot (the live game view is a Flame canvas, not a widget,
  /// so no in-app capture is possible here — stated honestly on screen).
  Widget _cinemaView() {
    final game = widget.game;
    final deg = (game.cinemaAngle * 180 / 3.14159).round();
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        game.cinemaAngle =
            (game.cinemaAngle + details.delta.dx * 0.005).clamp(-1.3, 1.3);
        setState(() {});
      },
      child: Container(
        color: Colors.transparent,
        child: Column(
          children: [
            const Spacer(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '🎬 CINEMA MODE — drag to orbit the car',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'RussoOne',
                  fontSize: 14,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _zoomButton('−', () {
                    game.cinemaRadius =
                        (game.cinemaRadius + 1.5).clamp(5.0, 12.0);
                    setState(() {});
                  }),
                  const SizedBox(width: 16),
                  Text(
                    '$deg°  ·  ${game.cinemaRadius.toStringAsFixed(1)} m',
                    style: const TextStyle(
                      fontFamily: 'RussoOne',
                      fontSize: 14,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                    ),
                  ),
                  const SizedBox(width: 16),
                  _zoomButton('+', () {
                    game.cinemaRadius =
                        (game.cinemaRadius - 1.5).clamp(5.0, 12.0);
                    setState(() {});
                  }),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TTheme.ghostButton(
                label: '✕  EXIT CINEMA',
                onPressed: () {
                  game.audio.click();
                  game.exitCinema();
                  setState(() {});
                },
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'To save the shot: press Volume Down + Power',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12,
                color: Color(0xFFD8CBE8),
                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _zoomButton(String label, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: TTheme.gold, width: 1.5),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'RussoOne',
            fontSize: 22,
            color: TTheme.gold,
          ),
        ),
      ),
    );
  }

  Widget _controlModeRow(String current) {
    Widget chip(String id, String label) {
      final selected = current == id;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            widget.game.audio.click();
            widget.game.storage.setControlMode(id);
            widget.game.input.mode = switch (id) {
              'swipe' => ControlMode.swipe,
              'tilt' => ControlMode.tilt,
              _ => ControlMode.both,
            };
            setState(() {});
          },
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? TTheme.gold : Colors.white12,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'RussoOne',
                fontSize: 13,
                color: selected ? TTheme.deepPurple : Colors.white,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('swipe', 'SWIPE'),
        const SizedBox(width: 8),
        chip('tilt', 'TILT'),
        const SizedBox(width: 8),
        chip('both', 'BOTH'),
      ],
    );
  }

  Widget _sliderRow(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 64, child: Text(label, style: TTheme.bodyDim)),
        Expanded(
          child: Slider(
            value: value,
            onChanged: onChanged,
            activeColor: TTheme.gold,
            inactiveColor: Colors.white24,
          ),
        ),
      ],
    );
  }
}
