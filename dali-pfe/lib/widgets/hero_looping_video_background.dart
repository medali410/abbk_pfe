import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// Carrousel infini : vidéo 1 → 2 → 3 → … → dernière → 1 → 2 → …
class HeroLoopingVideoBackground extends StatefulWidget {
  const HeroLoopingVideoBackground({
    super.key,
    required this.fallbackImageUrl,
  });

  final String fallbackImageUrl;

  @override
  State<HeroLoopingVideoBackground> createState() =>
      _HeroLoopingVideoBackgroundState();
}

class _HeroLoopingVideoBackgroundState extends State<HeroLoopingVideoBackground> {
  static const _endThreshold = Duration(milliseconds: 350);

  static const _networkFallbacks = [
    'https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
    'https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
  ];

  final List<_VideoSource> _sources = [];
  int _index = 0;
  VideoPlayerController? _controller;
  Timer? _endTimer;
  bool _loading = true;
  int _failedAttempts = 0;
  bool _advancing = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final assetPaths = await _loadAssetVideoPaths();
    final sources = <_VideoSource>[
      for (final p in assetPaths) _VideoSource.asset(p),
    ];
    if (sources.isEmpty) {
      for (final u in _networkFallbacks) {
        sources.add(_VideoSource.network(u));
      }
    }

    if (!mounted) return;
    if (sources.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    setState(() {
      _sources
        ..clear()
        ..addAll(sources);
      _loading = true;
      _failedAttempts = 0;
    });
    await _playIndex(0);
  }

  Future<List<String>> _loadAssetVideoPaths() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      const okExt = ['.mp4', '.webm', '.mov'];
      return manifest
          .listAssets()
          .where((k) => k.startsWith('assets/videos/'))
          .where((k) => okExt.any((e) => k.toLowerCase().endsWith(e)))
          .where((k) => !k.contains('README'))
          .toList()
        ..sort();
    } catch (e) {
      debugPrint('[hero-video] manifest: $e');
      return const [];
    }
  }

  void _cancelEndTimer() {
    _endTimer?.cancel();
    _endTimer = null;
  }

  /// Secours Web : passage à la suivante quand la durée est connue.
  void _scheduleEndTimer(VideoPlayerController controller) {
    _cancelEndTimer();
    if (_sources.length <= 1) return;

    final d = controller.value.duration;
    if (d <= Duration.zero) return;

    _endTimer = Timer(d + const Duration(milliseconds: 120), () {
      if (!mounted || _advancing) return;
      final c = _controller;
      if (c == null || !c.value.isInitialized) return;
      _goToNextInCircle();
    });
  }

  void _onVideoTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _advancing) return;

    if (_sources.length <= 1) return;

    final d = c.value.duration;
    final p = c.value.position;

    final atEnd = d > Duration.zero && d - p <= _endThreshold;
    final pausedAtEnd =
        d > Duration.zero && !c.value.isPlaying && p >= d - _endThreshold;

    if (atEnd || pausedAtEnd) {
      _goToNextInCircle();
    }
  }

  /// Cercle infini : après la dernière, retour à la première (index 0).
  void _goToNextInCircle() {
    if (_advancing || _sources.isEmpty) return;
    if (_sources.length <= 1) return;

    _advancing = true;
    _cancelEndTimer();

    final nextIndex = (_index + 1) % _sources.length;
    final wrap = nextIndex == 0 && _index == _sources.length - 1;
    if (wrap) {
      debugPrint('[hero-video] fin du cycle → retour vidéo 1/${_sources.length}');
    }

    _playIndex(nextIndex).whenComplete(() => _advancing = false);
  }

  Future<void> _playIndex(int idx) async {
    if (_sources.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (_failedAttempts >= _sources.length) {
      _cancelEndTimer();
      _controller?.removeListener(_onVideoTick);
      await _controller?.dispose();
      _controller = null;
      if (mounted) setState(() => _loading = false);
      return;
    }

    _index = idx % _sources.length;
    final source = _sources[_index];
    final label = source.assetPath ?? source.networkUrl ?? '?';
    final humanIndex = _index + 1;

    _cancelEndTimer();
    _controller?.removeListener(_onVideoTick);
    await _controller?.dispose();
    _controller = null;

    final controller = source.createController();
    try {
      await controller.initialize().timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw TimeoutException('init timeout: $label'),
      );
      if (controller.value.hasError) {
        throw Exception(controller.value.errorDescription ?? 'hasError');
      }
      await controller.setVolume(0);
      await controller.setLooping(_sources.length <= 1);
      controller.addListener(_onVideoTick);
      await controller.play();
      _scheduleEndTimer(controller);

      if (!mounted) {
        _cancelEndTimer();
        controller.removeListener(_onVideoTick);
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
        _failedAttempts = 0;
      });
      debugPrint(
        '[hero-video] $humanIndex/${_sources.length} (cercle infini): $label',
      );
    } catch (e) {
      debugPrint('[hero-video] échec $label → $e');
      _cancelEndTimer();
      controller.removeListener(_onVideoTick);
      await controller.dispose();
      _failedAttempts++;
      await _playIndex((_index + 1) % _sources.length);
    }
  }

  @override
  void dispose() {
    _cancelEndTimer();
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c != null && c.value.isInitialized && !c.value.hasError) {
      final w = c.value.size.width;
      final h = c.value.size.height;
      if (w > 0 && h > 0) {
        return FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          child: SizedBox(
            width: w,
            height: h,
            child: VideoPlayer(c),
          ),
        );
      }
    }

    if (_loading) {
      return Container(
        color: const Color(0xFF141D34),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Image.network(
      widget.fallbackImageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(color: const Color(0xFF141D34)),
    );
  }
}

class _VideoSource {
  const _VideoSource._({this.assetPath, this.networkUrl});

  factory _VideoSource.asset(String path) => _VideoSource._(assetPath: path);

  factory _VideoSource.network(String url) => _VideoSource._(networkUrl: url);

  final String? assetPath;
  final String? networkUrl;

  VideoPlayerController createController() {
    if (assetPath != null) {
      if (kIsWeb) {
        final url = Uri.base.resolve('assets/$assetPath').toString();
        return VideoPlayerController.networkUrl(Uri.parse(url));
      }
      return VideoPlayerController.asset(assetPath!);
    }
    return VideoPlayerController.networkUrl(Uri.parse(networkUrl!));
  }
}
