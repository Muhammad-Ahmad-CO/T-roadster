import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import '../game/game.dart';
import 'theme.dart';

/// Score-share card (Round 9 improvement). A sunset-gradient results card
/// with a gold border, drawn in-app — no server, no social login. The
/// game-over panel shows it inside a RepaintBoundary; SHARE captures that
/// boundary to a PNG and saves it on the device.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.data, required this.callsign});

  final GameOverData data;
  final String callsign;

  @override
  Widget build(BuildContext context) {
    final mm = (data.timeS ~/ 60).toString();
    final ss = (data.timeS % 60).toString().padLeft(2, '0');
    final mode = data.isTimeTrial
        ? '⏱ TIME TRIAL — 60 S'
        : (data.isWrongWay ? '🔄 WRONG-WAY MODE' : 'COASTAL RUN');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // Sunset gradient (the reel's golden hour) + gold border.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2B1055),
            Color(0xFFB83280),
            Color(0xFFFF7E3D),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TTheme.gold, width: 3),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'T  R O A D S T E R',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'RussoOne',
              color: Colors.white,
              fontSize: 22,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            mode,
            textAlign: TextAlign.center,
            style: TTheme.bodyDim.copyWith(fontSize: 12),
          ),
          if (data.isRecord)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '★  NEW RECORD  ★',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'RussoOne',
                  color: TTheme.gold,
                  fontSize: 16,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            '${data.score}',
            textAlign: TextAlign.center,
            style: TTheme.display.copyWith(fontSize: 52),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _miniStat('DISTANCE', '${data.distance} m'),
              _miniStat('TIME', '$mm:$ss'),
              _miniStat('COMBO', '×${data.maxCombo}'),
              _miniStat('RANK', '#${data.rank}'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'PILOT $callsign  ·  BEST ${data.bestScore}',
            textAlign: TextAlign.center,
            style: TTheme.bodyDim.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'RussoOne',
            color: Colors.white,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Nunito',
            color: Color(0xFFD8CBE8),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

/// Capture the card behind [cardKey] to a PNG and save it in the app's
/// external files dir. Returns the saved file path, or null on failure.
Future<String?> saveShareCard(GlobalKey cardKey, int score) async {
  try {
    final context = cardKey.currentContext;
    if (context == null) return null;
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData?.buffer.asUint8List();
    if (bytes == null) return null;
    final dir = await getExternalStorageDirectory();
    if (dir == null) return null;
    final now = DateTime.now();
    final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    final file = File('${dir.path}/T-Roadster-$score-$stamp.png');
    await file.writeAsBytes(bytes);
    return file.path;
  } catch (_) {
    return null;
  }
}
