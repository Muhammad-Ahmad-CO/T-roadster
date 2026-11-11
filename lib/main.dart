import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/audio.dart';
import 'game/game.dart';
import 'game/storage.dart';
import 'ui/achievements_screen.dart';
import 'ui/gameover_panel.dart';
import 'ui/garage_screen.dart';
import 'ui/quests_screen.dart';
import 'ui/upgrades_screen.dart';
import 'ui/home_screen.dart';
import 'ui/hud_overlay.dart';
import 'ui/leaderboard_screen.dart';
import 'ui/pause_overlay.dart';
import 'ui/settings_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const TRoadsterApp());
}

class TRoadsterApp extends StatelessWidget {
  const TRoadsterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'T Roadster',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: TTheme.deepPurple,
        fontFamily: 'Nunito',
        colorScheme: const ColorScheme.dark(
          primary: TTheme.gold,
          secondary: TTheme.orange,
        ),
      ),
      home: const Preloader(),
    );
  }
}

/// Preloader (same as Color Cover): logo + T ROADSTER + "made by Ahmed",
/// thin loading bar, < 2 s on a warm start. Tap skips after load.
class Preloader extends StatefulWidget {
  const Preloader({super.key});

  @override
  State<Preloader> createState() => _PreloaderState();
}

class _PreloaderState extends State<Preloader> {
  double _progress = 0.0;
  bool _ready = false;
  GameStorage? _storage;
  GameAudio? _audio;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storage = await GameStorage.load();
    setState(() => _progress = 0.5);
    final audio = GameAudio();
    setState(() {
      _storage = storage;
      _audio = audio;
      _progress = 1.0;
    });
    // Minimum display so the logo actually reads (Color Cover: 2 s).
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready && _storage != null && _audio != null) {
      return GameScreen(storage: _storage!, audio: _audio!);
    }
    return Scaffold(
      backgroundColor: TTheme.deepPurple,
      body: GestureDetector(
        onTap: () {
          if (_storage != null && _audio != null) {
            setState(() => _ready = true);
          }
        },
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/logo.png',
                width: 160,
                height: 160,
                errorBuilder: (context, error, stack) => const Icon(
                  Icons.directions_car,
                  size: 120,
                  color: TTheme.gold,
                ),
              ),
              const SizedBox(height: 20),
              const Text('T ROADSTER', style: TTheme.display),
              const SizedBox(height: 8),
              const Text(
                'made by Ahmed',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  color: TTheme.gold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.white24,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(TTheme.gold),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'LOADING… ${(_progress * 100).round()}%',
                style: TTheme.bodyDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The game screen: Flame GameWidget + Flutter overlays.
/// Auto-pauses when the app goes to the background (SPEC §3.5).
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.storage, required this.audio});

  final GameStorage storage;
  final GameAudio audio;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with WidgetsBindingObserver {
  late final TRoadsterGame _game;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _game = TRoadsterGame(storage: widget.storage, audio: widget.audio);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _game.pauseGame();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GameWidget(
        game: _game,
        initialActiveOverlays: const ['home'],
        overlayBuilderMap: {
          'home': (context, game) =>
              HomeScreen(game: game as TRoadsterGame),
          'garage': (context, game) =>
              GarageScreen(game: game as TRoadsterGame),
          'upgrades': (context, game) =>
              UpgradesScreen(game: game as TRoadsterGame),
          'quests': (context, game) =>
              QuestsScreen(game: game as TRoadsterGame),
          'leaderboard': (context, game) =>
              LeaderboardScreen(game: game as TRoadsterGame),
          'achievements': (context, game) =>
              AchievementsScreen(game: game as TRoadsterGame),
          'settings': (context, game) =>
              SettingsScreen(game: game as TRoadsterGame),
          'pause': (context, game) =>
              PauseOverlay(game: game as TRoadsterGame),
          'gameover': (context, game) =>
              GameOverPanel(game: game as TRoadsterGame),
          'hud': (context, game) =>
              HudOverlay(game: game as TRoadsterGame),
          // Countdown numerals live inside the HUD overlay (hud.countdown).
          'countdown': (context, game) => const SizedBox.shrink(),
        },
      ),
    );
  }
}
