import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../audio/audio_engine.dart';
import '../media_controls/playback_diagnostics.dart';
import 'eme_player.dart' show EmePlayerState;

/// Android 原生 DRM 播放器：MethodChannel/EventChannel 封装 Kotlin 侧 ExoPlayer(Media3)+Widevine。
///
/// 为什么存在：部分 Android WebView 的 EME 在 createMediaKeys 阶段永不 settle（真机实测），
/// WebView 链路不可用；原生 ExoPlayer 用设备 MediaDrm，不受 WebView 限制。
/// 原生侧只吃「回环 HLS 清单 URL + license 反代 URL」两个地址，
/// 下载/鉴权/清单本地化全部留在 Dart 复用；API 与 [EmePlayer] 同形。
class NativeDrmPlayer {
  static const MethodChannel _method = MethodChannel('flutify/native_drm');
  static const EventChannel _events = EventChannel('flutify/native_drm/events');

  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _stateController = StreamController<EmePlayerState>.broadcast();

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<EmePlayerState> get stateStream => _stateController.stream;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration get position => _position;
  Duration get duration => _duration;

  /// 最近一次原生播放错误（随 [stateStream] 的 error 事件更新）。
  EmePlaybackException? lastError;

  StreamSubscription<dynamic>? _eventSub;

  NativeDrmPlayer() {
    _eventSub = _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object e) => debugPrint('[ndrm] 事件流异常: $e'),
    );
    if (PlaybackDiagnostics.instance.enabled) {
      unawaited(_enableNativeDiagnostics());
    }
  }

  Future<void> _enableNativeDiagnostics() async {
    try {
      await _method.invokeMethod<void>('setDiagnosticsEnabled', {
        'enabled': true,
      });
    } catch (_) {
      // Diagnostic opt-in must never affect player startup or behavior.
    }
  }

  /// 播一首：本地回环 HLS 清单 + license/provision 反代地址
  ///（切歌时原生侧复用实例重新 setMediaItem）。
  Future<void> play({
    required String hlsUrl,
    required String licenseUrl,
    required String provisionUrl,
    bool autoplay = true,
    Duration initialPosition = Duration.zero,
  }) async {
    lastError = null;
    debugPrint('[ndrm] play: $hlsUrl');
    await _safe('play', {
      'hlsUrl': hlsUrl,
      'licenseUrl': licenseUrl,
      'provisionUrl': provisionUrl,
      'autoplay': autoplay,
      'positionMs': initialPosition.inMilliseconds,
    });
  }

  Future<void> pause() => _safe('pause');
  Future<void> resume() => _safe('resume');
  Future<void> seek(Duration pos) =>
      _safe('seek', {'positionMs': pos.inMilliseconds});
  Future<void> setVolume(double v) =>
      _safe('setVolume', {'volume': v.clamp(0.0, 1.0)});
  Future<void> stop() => _safe('stop');

  Future<void> _safe(String method, [Map<String, dynamic>? args]) async {
    try {
      await _method.invokeMethod<void>(method, args);
    } catch (e) {
      debugPrint('[ndrm] $method 调用失败: $e');
      rethrow;
    }
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    switch (raw['type']) {
      case 'position':
        _position = Duration(
          milliseconds: (raw['position'] as num?)?.toInt() ?? 0,
        );
        final dur = (raw['duration'] as num?)?.toInt() ?? 0;
        if (dur > 0) {
          final d = Duration(milliseconds: dur);
          if (d != _duration) {
            _duration = d;
            _durationController.add(d);
          }
        }
        _positionController.add(_position);
      case 'state':
        // 系统音频焦点、拔耳机也能触发暂停，不能只依赖 Dart 的 pause 命令。
        switch (raw['state']) {
          case 'buffering':
            _stateController.add(EmePlayerState.buffering);
          case 'ready':
            if (raw['playing'] == true) {
              _stateController.add(EmePlayerState.playing);
            } else {
              _stateController.add(EmePlayerState.paused);
            }
          case 'ended':
            _stateController.add(EmePlayerState.ended);
        }
      case 'error':
        final msg = '${raw['code']}: ${raw['message']}';
        debugPrint('[ndrm] 播放错误: $msg');
        // Native errors also cover media and provisioning. Authentication is
        // classified by the Dart relay, not by digits in this generic message.
        lastError = EmePlaybackException(msg);
        _stateController.add(EmePlayerState.error);
    }
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
    await _safe('dispose');
  }
}
