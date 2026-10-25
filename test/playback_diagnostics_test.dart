import 'package:flutter_test/flutter_test.dart';
import 'package:flutify_app/services/media_controls/playback_diagnostics.dart';

void main() {
  test('disabled diagnostics write nothing', () async {
    final records = <String>[];
    final diagnostics = PlaybackDiagnostics.forTesting(
      enabled: false,
      androidPlatformOverride: true,
      sink: records.add,
    );

    diagnostics.recordDartPlayerState(
      engine: PlaybackDiagnosticEngine.local,
      playing: true,
      playbackActive: true,
      buffering: false,
      processingState: PlaybackDiagnosticProcessing.ready,
      positionMs: 1234,
    );
    diagnostics.recordMediaSessionSubmit(
      engine: PlaybackDiagnosticEngine.local,
      playing: true,
      buffering: false,
      positionMs: 1234,
    );
    diagnostics.recordConnectStatus(PlaybackDiagnosticConnectStatus.online);
    diagnostics.recordConnectReceiver(
      event: PlaybackDiagnosticConnectEvent.receiverStateApplied,
      active: true,
      paused: false,
      positionMs: 1234,
    );

    expect(records, isEmpty);
    await diagnostics.dispose();
  });

  test(
    'enabled diagnostics emit fixed state labels and deduplicate transitions',
    () async {
      final records = <String>[];
      final diagnostics = PlaybackDiagnostics.forTesting(
        enabled: true,
        androidPlatformOverride: true,
        sink: records.add,
      );

      void recordPlayerState() => diagnostics.recordDartPlayerState(
        engine: PlaybackDiagnosticEngine.drm,
        playing: false,
        playbackActive: true,
        buffering: true,
        processingState: PlaybackDiagnosticProcessing.buffering,
        positionMs: 4567,
      );

      recordPlayerState();
      recordPlayerState();
      diagnostics.recordMediaSessionSubmit(
        engine: PlaybackDiagnosticEngine.drm,
        playing: true,
        buffering: false,
        positionMs: 4567,
      );

      expect(records, hasLength(2));
      expect(records.first, contains('event=dart_player_state'));
      expect(records.first, contains('engine=drm_exoplayer'));
      expect(records.first, contains('playback_active=true'));
      expect(records.first, contains('buffering=true'));
      expect(records.last, contains('event=media_session_submit'));
      expect(records.last, contains('speed=1'));
      expect(records.join('\n'), isNot(contains('title=')));
      await diagnostics.dispose();
    },
  );

  test(
    'Connect records are opt-in, state-only, and correlated by timestamp',
    () async {
      final records = <String>[];
      final diagnostics = PlaybackDiagnostics.forTesting(
        enabled: true,
        sink: records.add,
      );

      diagnostics.recordConnectStatus(PlaybackDiagnosticConnectStatus.online);
      diagnostics.recordConnectCluster(
        event: PlaybackDiagnosticConnectEvent.clusterSnapshot,
        status: PlaybackDiagnosticConnectStatus.online,
        activeDevicePresent: true,
        activeDeviceIsReceiver: false,
        remoteSession: true,
        hasTrack: true,
        playing: true,
        paused: false,
        positionMs: 12000,
        trackRevision: 1,
      );
      diagnostics.recordConnectReceiver(
        event: PlaybackDiagnosticConnectEvent.receiverStateApplied,
        active: true,
        paused: false,
        positionMs: 12000,
      );

      expect(records, hasLength(3));
      expect(records.every((record) => record.contains('wall_ms=')), isTrue);
      expect(records.join('\n'), contains('mode=connect_remote'));
      expect(records.join('\n'), contains('mode=connect_receiver'));
      expect(records.join('\n'), contains('track_revision=1'));
      expect(records.join('\n'), isNot(contains('spotify:')));
      expect(records.join('\n'), isNot(contains('title=')));
      expect(records.join('\n'), isNot(contains('device_id')));
      await diagnostics.dispose();
    },
  );

  test(
    'submitted paused/buffering state records zero playback speed',
    () async {
      final records = <String>[];
      final diagnostics = PlaybackDiagnostics.forTesting(
        enabled: true,
        androidPlatformOverride: true,
        sink: records.add,
      );

      diagnostics.recordMediaSessionSubmit(
        engine: PlaybackDiagnosticEngine.local,
        playing: true,
        buffering: true,
        positionMs: 0,
      );
      diagnostics.recordMediaSessionSubmit(
        engine: PlaybackDiagnosticEngine.local,
        playing: false,
        buffering: false,
        positionMs: 5000,
      );

      expect(records, hasLength(2));
      expect(records.first, contains('speed=0'));
      expect(records.last, contains('playing=false'));
      expect(records.last, contains('speed=0'));
      await diagnostics.dispose();
    },
  );
}
