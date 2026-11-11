import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';

/// Audio (SPEC §11, audio-design skill).
/// Bus tree: Master ← {Music, SFX, Engine, UI} — implemented as volume
/// groups on pooled AudioPlayers (audioplayers has no mixer buses on
/// mobile; the grouping is by player set, sliders map 0..1 → gain² in dB).
/// Every repeated SFX gets ±6% pitch and ±2 dB randomisation.
/// Music: two original synthwave loops (Cruise / Redline), crossfaded —
/// never a hard cut. No licensed track, no copy of any reel audio.
class GameAudio {
  GameAudio();

  final _rand = math.Random();

  AudioPlayer? _musicCruise;
  AudioPlayer? _musicRedline;
  AudioPlayer? _engine;
  final List<AudioPlayer> _sfxPool = [];
  int _poolIndex = 0;

  double _musicVol = 0.7;
  double _sfxVol = 0.9;
  double _engineVol = 0.8;
  bool _muted = false;
  bool _musicDucked = false;
  bool _ready = false;
  // Remember what was playing across a mute, so un-muting resumes it
  // instead of leaving the game silent until the next run.
  bool _cruiseWasPlaying = false;
  bool _redlineWasPlaying = false;
  bool _engineWasPlaying = false;

  double get _musicGain => _muted ? 0.0 : _musicVol * _musicVol;
  double get _sfxGain => _muted ? 0.0 : _sfxVol * _sfxVol;
  double get _engineGain => _muted ? 0.0 : _engineVol * _engineVol;

  Future<void> init({
    required double musicVolume,
    required double sfxVolume,
    required double engineVolume,
    required bool muted,
  }) async {
    _musicVol = musicVolume;
    _sfxVol = sfxVolume;
    _engineVol = engineVolume;
    _muted = muted;
    for (var i = 0; i < 6; i++) {
      _sfxPool.add(AudioPlayer());
    }
    _engine = AudioPlayer();
    await _engine!.setReleaseMode(ReleaseMode.loop);
    await _engine!.setVolume(_engineGain);
    _musicCruise = AudioPlayer();
    await _musicCruise!.setReleaseMode(ReleaseMode.loop);
    _musicRedline = AudioPlayer();
    await _musicRedline!.setReleaseMode(ReleaseMode.loop);
    _ready = true;
  }

  void setVolumes({
    required double music,
    required double sfx,
    required double engine,
  }) {
    _musicVol = music;
    _sfxVol = sfx;
    _engineVol = engine;
    _applyMusicVolumes();
    _engine?.setVolume(_engineGain * (_musicDucked ? 0.7 : 1.0));
  }

  void setMuted(bool muted) {
    _muted = muted;
    _applyMusicVolumes();
    _engine?.setVolume(_engineGain);
    if (muted) {
      _cruiseWasPlaying = _musicCruise?.state == PlayerState.playing;
      _redlineWasPlaying = _musicRedline?.state == PlayerState.playing;
      _engineWasPlaying = _engine?.state == PlayerState.playing;
      _musicCruise?.pause();
      _musicRedline?.pause();
      _engine?.pause();
    } else {
      if (_cruiseWasPlaying) _musicCruise?.resume();
      if (_redlineWasPlaying) _musicRedline?.resume();
      if (_engineWasPlaying) _engine?.resume();
    }
  }

  void _applyMusicVolumes() {
    final duck = _musicDucked ? 0.25 : 1.0; // −12 dB on crash / new record
    _musicCruise?.setVolume(_musicGain * duck * 0.8);
    _musicRedline?.setVolume(_musicGain * duck * 0.8);
  }

  /// Duck music −12 dB for 0.4 s (crash / NEW RECORD). SFX never ducked.
  void duckMusic() {
    _musicDucked = true;
    _applyMusicVolumes();
    Future.delayed(const Duration(milliseconds: 400), () {
      _musicDucked = false;
      _applyMusicVolumes();
    });
  }

  // ---- Music ---------------------------------------------------------------
  Future<void> startMenuMusic() async {
    if (!_ready || _muted) return;
    await _musicCruise?.play(AssetSource('sounds/music_cruise.wav'));
    await _musicCruise?.setVolume(_musicGain * 0.8);
    await _musicRedline?.setVolume(0.0);
  }

  Future<void> startRunMusic() async {
    if (!_ready || _muted) return;
    if (_musicCruise != null) {
      // Already playing from the menu: keep it, start Redline silent.
      await _musicRedline?.play(AssetSource('sounds/music_redline.wav'));
      await _musicRedline?.setVolume(0.0);
    } else {
      await startMenuMusic();
    }
  }

  /// Adaptive layers: Redline fades in above 40 m/s or multiplier ≥ ×5.
  void setIntensity({required double speedMs, required int multiplier}) {
    if (!_ready || _muted) return;
    final redline = speedMs > 40 || multiplier >= 5;
    final target = redline ? 0.8 : 0.0;
    _musicRedline?.setVolume(_musicGain * target);
    _musicCruise?.setVolume(_musicGain * (redline ? 0.35 : 0.8));
  }

  void stopMusic() {
    _musicCruise?.stop();
    _musicRedline?.stop();
  }

  // ---- Engine ----------------------------------------------------------------
  Future<void> startEngine() async {
    if (!_ready || _muted) return;
    await _engine?.play(AssetSource('sounds/engine.wav'));
    await _engine?.setPlaybackRate(0.8);
  }

  /// Pitch + volume tied to speed: 0.8× at 26 m/s → 1.6× at 52 m/s.
  void setEngineSpeed(double speedMs) {
    if (!_ready || _muted) return;
    final t = ((speedMs - 26) / 26).clamp(0.0, 1.0);
    _engine?.setPlaybackRate(0.8 + 0.8 * t);
    _engine?.setVolume(_engineGain * (0.55 + 0.45 * t));
  }

  void duckEngineForStunt() {
    // −6 dB while a stunt whoosh plays so the whoosh reads.
    _engine?.setVolume(_engineGain * 0.5);
    Future.delayed(const Duration(milliseconds: 350), () {
      _engine?.setVolume(_engineGain);
    });
  }

  void stopEngine() => _engine?.stop();

  // ---- SFX -------------------------------------------------------------------
  Future<void> _play(String file, {double volume = 1.0}) async {
    if (!_ready || _muted) return;
    final player = _sfxPool[_poolIndex];
    _poolIndex = (_poolIndex + 1) % _sfxPool.length;
    // ±6% pitch, ±2 dB — the same clip never sounds robotic twice.
    final pitch = 1.0 + (_rand.nextDouble() - 0.5) * 0.12;
    final gain = (_sfxGain * volume * math.pow(10, (_rand.nextDouble() - 0.5) * 4 / 20))
        .toDouble();
    await player.setPlaybackRate(pitch);
    await player.setVolume(gain.clamp(0.0, 1.0));
    await player.play(AssetSource('sounds/$file'));
  }

  Future<void> click() => _play('click.wav', volume: 0.7);
  Future<void> tick() => _play('tick.wav', volume: 0.8);
  Future<void> goHorn() => _play('go.wav', volume: 1.0);
  Future<void> hop() => _play('hop.wav');
  Future<void> coin() => _play('coin.wav', volume: 0.9);
  Future<void> nearMiss() => _play('whoosh.wav', volume: 0.9);
  Future<void> rollSwish() => _play('roll.wav');
  Future<void> flipSwish() => _play('flip.wav');
  Future<void> perfectChime() => _play('chime.wav', volume: 0.9);
  Future<void> smash() => _play('smash.wav');
  Future<void> crash() => _play('crash.wav', volume: 1.0);
  Future<void> fanfare() => _play('fanfare.wav', volume: 1.0);
  Future<void> pickup() => _play('pickup.wav');
  Future<void> siren() => _play('siren.wav', volume: 0.8);

  Future<void> dispose() async {
    for (final p in _sfxPool) {
      await p.dispose();
    }
    await _musicCruise?.dispose();
    await _musicRedline?.dispose();
    await _engine?.dispose();
  }
}
