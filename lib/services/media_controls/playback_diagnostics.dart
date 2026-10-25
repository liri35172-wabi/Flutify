import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// Fixed labels only: this logger deliberately has no free-form string/payload API.
enum PlaybackDiagnosticEngine { local, drm, connectRemote, none, unknown }

enum PlaybackDiagnosticConnectStatus { idle, connecting, online, offline }

enum PlaybackDiagnosticConnectEvent {
  receiverCommand,
  receiverStateApplied,
  receiverStateCleared,
  receiverLocalPauseChanged,
  receiverLocalSeek,
  receiverLocalTrackChanged,
  clusterSnapshot,
  clusterStatusChanged,
}

enum PlaybackDiagnosticProcessing {
  idle,
  loading,
  buffering,
  ready,
  completed,
  unknown,
}

/// Opt-in, local-only playback diagnostics. Disabled in every normal build.
///
/// Enable only for a dedicated diagnostic build with
/// `--dart-define=FLUTIFY_PLAYBACK_DIAGNOSTICS=true`. Records contain state and
/// timing scalars only; never pass media metadata or device identifiers here.
class PlaybackDiagnostics {
  static const bool _buildOptIn =
      bool.fromEnvironment('FLUTIFY_PLAYBACK_DIAGNOSTICS');
  static final PlaybackDiagnostics instance = PlaybackDiagnostics._();

  final bool _enabled;
  final bool _androidPlatformOverride;
  final void Function(String) _sink;
  final Stopwatch _clock = Stopwatch()..start();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  PlaybackDiagnosticEngine Function()? _engine;
  String? _lastDartState;
  String? _lastMediaSessionState;
  int? _lastMediaSessionPositionMs;
  bool _observerDisposed = false;
  int _lastDartPositionAtMs = 0;
  int _lastMediaSourceAtMs = 0;
  String? _lastConnectSnapshot;
  String? _lastConnectStatus;
  int? _lastConnectPositionMs;

  PlaybackDiagnostics._()
    : _enabled = _buildOptIn,
      _androidPlatformOverride = false,
      _sink = debugPrint;

  @visibleForTesting
  PlaybackDiagnostics.forTesting({
    required bool enabled,
    required void Function(String) sink,
    bool androidPlatformOverride = false,
  }) : _enabled = enabled,
       _androidPlatformOverride = androidPlatformOverride,
       _sink = sink;

  bool get enabled =>
      _enabled && !kIsWeb && (_androidPlatformOverride || Platform.isAndroid);

  /// Opt-in Connect diagnostics can also run on desktop; player diagnostics remain Android-only.
  bool get connectEnabled => _enabled && !kIsWeb;

  static String _engineName(PlaybackDiagnosticEngine engine) =>
      switch (engine) {
        PlaybackDiagnosticEngine.local => 'local_just_audio',
        PlaybackDiagnosticEngine.drm => 'drm_exoplayer',
        PlaybackDiagnosticEngine.connectRemote => 'connect_remote',
        PlaybackDiagnosticEngine.none => 'none',
        PlaybackDiagnosticEngine.unknown => 'unknown',
      };

  static String _processingName(PlaybackDiagnosticProcessing state) =>
      switch (state) {
        PlaybackDiagnosticProcessing.idle => 'idle',
        PlaybackDiagnosticProcessing.loading => 'loading',
        PlaybackDiagnosticProcessing.buffering => 'buffering',
        PlaybackDiagnosticProcessing.ready => 'ready',
        PlaybackDiagnosticProcessing.completed => 'completed',
        PlaybackDiagnosticProcessing.unknown => 'unknown',
      };

  void _write(String fields) {
    if (!enabled) return;
    _sink(
      '[playback-diagnostic] wall_ms=${DateTime.now().toUtc().millisecondsSinceEpoch} '
      'elapsed_ms=${_clock.elapsedMilliseconds} $fields',
    );
  }

  /// Starts passive observation of available-device changes only.
  /// This does not configure the session or request/abandon audio focus.
  /// Android does not expose focus changes to a passive observer here: audio
  /// focus callbacks are delivered to the component that requested focus.
  Future<void> startAudioSessionObservers({
    required PlaybackDiagnosticEngine Function() engine,
  }) async {
    if (!enabled || _observerDisposed || _subscriptions.isNotEmpty) return;
    _engine = engine;
    try {
      final session = await AudioSession.instance;
      if (_observerDisposed) return;
      _subscriptions.add(
        session.devicesChangedEventStream.listen((event) {
          final added =
              event.devicesAdded
                  .map((device) => device.type.name)
                  .toSet()
                  .toList()
                ..sort();
          final removed =
              event.devicesRemoved
                  .map((device) => device.type.name)
                  .toSet()
                  .toList()
                ..sort();
          _write(
            'event=available_audio_devices_changed '
            'engine=${_engineName(_engine?.call() ?? PlaybackDiagnosticEngine.unknown)} '
            'added_types=${added.join(',')} removed_types=${removed.join(',')}',
          );
        }, onError: (_) => _write('event=audio_devices_stream_error')),
      );
    } catch (_) {
      // Do not emit exception text: platform errors may contain implementation
      // details. Absence of these events is a limitation, not a playback change.
      _write('event=audio_session_observer_unavailable');
    }
  }

  /// Dart's received player-state transition, not a claim that sound is audible.
  void recordDartPlayerState({
    required PlaybackDiagnosticEngine engine,
    required bool playing,
    required bool playbackActive,
    required bool buffering,
    required PlaybackDiagnosticProcessing processingState,
    required int positionMs,
  }) {
    final processing = _processingName(processingState);
    final safeState =
        '${_engineName(engine)}|$playing|$playbackActive|$buffering|$processing';
    if (!enabled || safeState == _lastDartState) return;
    _lastDartState = safeState;
    _lastDartPositionAtMs = _clock.elapsedMilliseconds;
    _write(
      'event=dart_player_state engine=${_engineName(engine)} playing=$playing '
      'playback_active=$playbackActive buffering=$buffering '
      'processing=$processing position_ms=${positionMs < 0 ? 0 : positionMs}',
    );
  }

  /// Periodic Dart-side position sample, throttled to one per five seconds.
  /// Captures the app's current state even when its position stream keeps
  /// ticking without a player-state transition.
  void recordDartPosition({
    required PlaybackDiagnosticEngine engine,
    required bool playing,
    required bool playbackActive,
    required bool buffering,
    required int positionMs,
  }) {
    if (!enabled) return;
    final now = _clock.elapsedMilliseconds;
    if (now - _lastDartPositionAtMs < 5000) return;
    _lastDartPositionAtMs = now;
    _write(
      'event=dart_position_sample engine=${_engineName(engine)} playing=$playing '
      'playback_active=$playbackActive buffering=$buffering '
      'position_ms=${positionMs < 0 ? 0 : positionMs}',
    );
  }

  /// Periodic input sample at the point where the app derives MediaSession
  /// playback state. This is not OS-side readback of the rendered notification.
  void recordMediaSessionSource({
    required PlaybackDiagnosticEngine engine,
    required bool playing,
    required bool buffering,
    required int positionMs,
  }) {
    if (!enabled) return;
    final now = _clock.elapsedMilliseconds;
    if (now - _lastMediaSourceAtMs < 5000) return;
    _lastMediaSourceAtMs = now;
    _write(
      'event=media_session_source_sample engine=${_engineName(engine)} '
      'playing=$playing buffering=$buffering '
      'position_ms=${positionMs < 0 ? 0 : positionMs}',
    );
  }

  /// State submitted by the app to AudioService's MediaSession handler. This
  /// is not OS-side readback of what the notification rendered. A record is
  /// emitted on a state transition or a material position discontinuity.
  void recordMediaSessionSubmit({
    required PlaybackDiagnosticEngine engine,
    required bool playing,
    required bool buffering,
    required int positionMs,
  }) {
    if (!enabled) return;
    final position = positionMs < 0 ? 0 : positionMs;
    final safeState = '${_engineName(engine)}|$playing|$buffering';
    final lastPosition = _lastMediaSessionPositionMs;
    if (safeState == _lastMediaSessionState &&
        lastPosition != null &&
        (position - lastPosition).abs() < 5000) {
      return;
    }
    _lastMediaSessionState = safeState;
    _lastMediaSessionPositionMs = position;
    _write(
      'event=media_session_submit engine=${_engineName(engine)} playing=$playing '
      'buffering=$buffering speed=${playing && !buffering ? 1 : 0} '
      'position_ms=$position',
    );
  }

  static String _connectEventName(PlaybackDiagnosticConnectEvent event) =>
      switch (event) {
        PlaybackDiagnosticConnectEvent.receiverCommand => 'receiver_command',
        PlaybackDiagnosticConnectEvent.receiverStateApplied =>
          'receiver_state_applied',
        PlaybackDiagnosticConnectEvent.receiverStateCleared =>
          'receiver_state_cleared',
        PlaybackDiagnosticConnectEvent.receiverLocalPauseChanged =>
          'receiver_local_pause_changed',
        PlaybackDiagnosticConnectEvent.receiverLocalSeek =>
          'receiver_local_seek',
        PlaybackDiagnosticConnectEvent.receiverLocalTrackChanged =>
          'receiver_local_track_changed',
        PlaybackDiagnosticConnectEvent.clusterSnapshot => 'cluster_snapshot',
        PlaybackDiagnosticConnectEvent.clusterStatusChanged =>
          'cluster_status_changed',
      };

  void _writeConnect(String fields) {
    if (!connectEnabled) return;
    _sink(
      '[playback-diagnostic] wall_ms=${DateTime.now().toUtc().millisecondsSinceEpoch} '
      'elapsed_ms=${_clock.elapsedMilliseconds} $fields',
    );
  }

  /// Sanitized Connect receiver state; event is an enum and payload contains no media/device IDs.
  void recordConnectReceiver({
    required PlaybackDiagnosticConnectEvent event,
    required bool active,
    required bool paused,
    required int positionMs,
  }) {
    _writeConnect(
      'event=${_connectEventName(event)} mode=connect_receiver active=$active '
      'paused=$paused playing=${active && !paused} '
      'position_ms=${positionMs < 0 ? 0 : positionMs}',
    );
  }

  /// Sanitized desktop Connect observation, correlated by the same wall/elapsed clocks as playback.
  /// trackRevision is a local counter, never a media identifier.
  void recordConnectCluster({
    required PlaybackDiagnosticConnectEvent event,
    required PlaybackDiagnosticConnectStatus status,
    required bool activeDevicePresent,
    required bool activeDeviceIsReceiver,
    required bool remoteSession,
    required bool hasTrack,
    required bool playing,
    required bool paused,
    required int positionMs,
    required int trackRevision,
  }) {
    final position = positionMs < 0 ? 0 : positionMs;
    final statusName = status.name;
    final state =
        '$statusName|$activeDevicePresent|$activeDeviceIsReceiver|'
        '$remoteSession|$hasTrack|$playing|$paused|$trackRevision';
    final previousPosition = _lastConnectPositionMs;
    if (event == PlaybackDiagnosticConnectEvent.clusterSnapshot &&
        state == _lastConnectSnapshot &&
        previousPosition != null &&
        (position - previousPosition).abs() < 5000) {
      return;
    }
    _lastConnectSnapshot = state;
    _lastConnectPositionMs = position;
    _writeConnect(
      'event=${_connectEventName(event)} mode=connect_remote status=$statusName '
      'active_device_present=$activeDevicePresent '
      'active_device_is_receiver=$activeDeviceIsReceiver remote_session=$remoteSession '
      'has_track=$hasTrack playing=$playing paused=$paused position_ms=$position '
      'track_revision=$trackRevision',
    );
  }

  void recordConnectStatus(PlaybackDiagnosticConnectStatus status) {
    final statusName = status.name;
    if (!connectEnabled || statusName == _lastConnectStatus) return;
    _lastConnectStatus = statusName;
    _writeConnect(
      'event=${_connectEventName(PlaybackDiagnosticConnectEvent.clusterStatusChanged)} '
      'mode=connect_remote status=$statusName',
    );
  }

  Future<void> dispose() async {
    _observerDisposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }
}
