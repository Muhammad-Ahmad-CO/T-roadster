import 'package:flutter/material.dart';

import '../game/game.dart';
import '../game/input.dart';
import 'theme.dart';

/// Settings (SPEC §7.4): control mode (Swipe / Tilt / Both), tilt
/// sensitivity + calibration, tilt gas/brake, reduce shake/flash,
/// sound/music/engine sliders, mute.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.game});

  final TRoadsterGame game;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final storage = widget.game.storage;
    final tiltAvailable = widget.game.input.tiltAvailable;
    return SafeArea(
      child: Container(
        color: TTheme.deepPurple,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        widget.game.audio.click();
                        widget.game.overlays.remove('settings');
                      },
                      icon:
                          const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const Expanded(
                      child: Text('SETTINGS',
                          textAlign: TextAlign.center, style: TTheme.title),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('CONTROLS', style: TTheme.goldLabel),
                const SizedBox(height: 8),
                _controlModeRow(storage.controlMode),
                const SizedBox(height: 16),
                const Text('TILT', style: TTheme.goldLabel),
                const SizedBox(height: 8),
                if (!tiltAvailable)
                  const Text(
                    'Tilt is not available on this device — swipe only.',
                    style: TTheme.bodyDim,
                  )
                else ...[
                  _sensitivityRow(storage.tiltSensitivity),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TTheme.ghostButton(
                          label: '🎯  CALIBRATE TILT',
                          height: 48,
                          onPressed: () {
                            widget.game.input.calibrateTilt();
                            widget.game.audio.click();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Tilt calibrated — hold the phone as you drive.'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    title: const Text('Tilt gas / brake',
                        style: TTheme.body),
                    subtitle: const Text(
                      'Tip phone forward to boost, back to brake. Off by default.',
                      style: TTheme.bodyDim),
                    value: storage.tiltGasBrake,
                    activeColor: TTheme.gold,
                    onChanged: (v) async {
                      await storage.setTiltGasBrake(v);
                      widget.game.input.tiltGasBrake = v;
                      setState(() {});
                    },
                  ),
                ],
                const SizedBox(height: 8),
                const Text('ACCESSIBILITY', style: TTheme.goldLabel),
                SwitchListTile(
                  title: const Text('Reduce screen shake',
                      style: TTheme.body),
                  value: storage.reduceShake,
                  activeColor: TTheme.gold,
                  onChanged: (v) async {
                    await storage.setReduceShake(v);
                    widget.game.cameraFx.reduceShake = v;
                    setState(() {});
                  },
                ),
                SwitchListTile(
                  title: const Text('Reduce flashing',
                      style: TTheme.body),
                  value: storage.reduceFlash,
                  activeColor: TTheme.gold,
                  onChanged: (v) async {
                    await storage.setReduceFlash(v);
                    widget.game.cameraFx.reduceFlash = v;
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),
                const Text('SOUND', style: TTheme.goldLabel),
                _sliderRow(
                  'Music',
                  storage.musicVolume,
                  (v) => _setVolumes(music: v),
                ),
                _sliderRow(
                  'Effects',
                  storage.sfxVolume,
                  (v) => _setVolumes(sfx: v),
                ),
                _sliderRow(
                  'Engine',
                  storage.engineVolume,
                  (v) => _setVolumes(engine: v),
                ),
                SwitchListTile(
                  title:
                      const Text('Mute all', style: TTheme.body),
                  value: storage.muted,
                  activeColor: TTheme.gold,
                  onChanged: (v) async {
                    await storage.setMuted(v);
                    widget.game.audio.setMuted(v);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setVolumes({double? music, double? sfx, double? engine}) async {
    final storage = widget.game.storage;
    if (music != null) await storage.setMusicVolume(music);
    if (sfx != null) await storage.setSfxVolume(sfx);
    if (engine != null) await storage.setEngineVolume(engine);
    widget.game.audio.setVolumes(
      music: storage.musicVolume,
      sfx: storage.sfxVolume,
      engine: storage.engineVolume,
    );
    setState(() {});
  }

  Widget _controlModeRow(String current) {
    Widget chip(String id, String label) {
      final selected = current == id;
      return Expanded(
        child: GestureDetector(
          onTap: () async {
            widget.game.audio.click();
            await widget.game.storage.setControlMode(id);
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

  Widget _sensitivityRow(String current) {
    Widget chip(String id, String label) {
      final selected = current == id;
      return Expanded(
        child: GestureDetector(
          onTap: () async {
            widget.game.audio.click();
            await widget.game.storage.setTiltSensitivity(id);
            widget.game.input.tiltSensitivity = id;
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
        chip('low', 'LOW'),
        const SizedBox(width: 8),
        chip('medium', 'MEDIUM'),
        const SizedBox(width: 8),
        chip('high', 'HIGH'),
      ],
    );
  }

  Widget _sliderRow(
      String label, double value, ValueChanged<double> onChanged) {
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
