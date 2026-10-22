import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../models/lyrics.dart';
import '../../models/lyrics_query.dart';
import '../media_controls/system_media_controls.dart';
import '../lyrics/lyrics_language.dart';
import 'taskbar_lyrics_channel.dart';

/// 任务栏歌词：作为又一个「系统媒体控制端」挂在 MediaControlsSync 上。
///
/// 这样它天然跟随「正在播放」的来源（本机 / Connect 远程设备，与系统媒体卡片一致），
/// 任务栏上的上一首 / 播放暂停 / 下一首也走同一条按键路由。
///
/// 职责：
/// - 收到曲目后按 [lyricsLoader] 取歌词（与 App 内歌词同一来源，含 LRCLIB 补全），只把逐行同步歌词推给原生；
///   纯文本或没有歌词时原生显示控制条（封面 + 歌名 + 按钮）；没取到时按 [retryDelays] 重试，
///   App 内先取到时由 [lyricsCached] 立即补上；
/// - 打开双语歌词时重新取当前曲目的歌词（关闭期间取到的没有网易云译文），关上时剥掉译文重推；
/// - 下载封面字节交给原生解码（只保留最近一张）；
/// - 关闭时不向原生推任何曲目数据，开启时补推当前状态。
/// 「打开 Flutify」「关闭任务栏歌词」由界面层（TaskbarLyricsBinding）通过回调处理。
class TaskbarLyricsControls implements SystemMediaControls {
  final TaskbarLyricsPlatform _platform;
  final http.Client _http;

  final StreamController<MediaControlEvent> _events =
      StreamController.broadcast();
  StreamSubscription<TaskbarLyricsEvent>? _platformEvents;

  /// 取歌词 / 强制重新取歌词（由界面层接到 SpotifyProvider）。
  Future<SpotifyLyrics> Function(LyricsQuery query)? lyricsLoader;
  Future<SpotifyLyrics> Function(LyricsQuery query)? lyricsReloader;

  void Function()? onOpen;
  void Function()? onDisable;

  bool _enabled = false;
  bool _overlayEnabled = false;
  bool _overlayClickThrough = false;
  bool _overlayTransparentBackground = false;
  TaskbarLyricsStyle? _style;
  TaskbarLyricsStyle? _overlayStyle;
  MediaTrackInfo? _track;
  MediaPlaybackInfo? _playback;
  DateTime _playbackAt = DateTime.now();

  /// 双语歌词开关（设置页「歌词 → 双语歌词」）：关闭时剥掉译文，只推原文给原生。
  bool _bilingual = true;
  String _locale = 'zh-Hans';

  /// 最近一次推给原生的歌词行（带译文），关上双语开关时剥掉译文重推，不用重新联网。
  List<LyricLine>? _lastLines;

  // 每换一次曲目递增，丢弃过期的异步结果（歌词 / 封面）
  int _generation = 0;
  String? _artUrl;
  Uint8List? _art;

  /// 没拿到同步歌词（请求失败 / 限流 / 网络抖动）时的重试间隔；确定「没有歌词」的结果有缓存，重试不会再联网。
  final List<Duration> retryDelays;

  // 当前曲目是否已推送同步歌词，以及已重试的次数
  bool _hasLyrics = false;
  int _retries = 0;
  Timer? _retryTimer;

  final bool isFlyme;
  final bool isAndroid;
  final bool isWindows;

  bool get _active => _enabled || _overlayEnabled;

  TaskbarLyricsControls(
    this._platform, {
    this.isFlyme = false,
    this.isAndroid = false,
    this.isWindows = false,
    http.Client? client,
    this.retryDelays = const [
      Duration(seconds: 10),
      Duration(seconds: 30),
      Duration(seconds: 90),
    ],
  }) : _http = client ?? http.Client() {
    _platformEvents = _platform.events.listen(_onPlatformEvent);
  }

  bool get enabled => _active;

  /// 界面层每次构建时调用；只在开关 / 样式真正变化时通知原生。
  void configure({
    required bool enabled,
    bool overlayEnabled = false,
    bool overlayClickThrough = false,
    bool overlayTransparentBackground = false,
    required TaskbarLyricsStyle style,
    TaskbarLyricsStyle overlayStyle = const TaskbarLyricsStyle(),
    bool bilingual = true,
    String locale = 'zh-Hans',
  }) {
    final languageChanged = _locale != locale;
    _locale = locale;
    if (languageChanged && _active && _lastLines != null) {
      unawaited(_platform.setLyrics(_linesForPlatform(_lastLines!)));
    }
    if (bilingual != _bilingual) {
      _bilingual = bilingual;
      final track = _track;
      if (_active && track != null) {
        if (bilingual) {
          // 打开：关闭期间取到的歌词没查过网易云译文。SpotifyProvider 在偏好变化时已同步作废内存里的歌词
          //（见 main.dart），这里重新取到的是带译文的结果；取到之前原生照常显示原文
          _resetLyricsState();
          unawaited(_pushLyrics(track, _generation));
        } else if (_hasLyrics) {
          // 关上：剥掉译文重推已取到的歌词即可
          final lines = _lastLines;
          if (lines != null)
            unawaited(_platform.setLyrics(_linesForPlatform(lines)));
        }
      }
    }
    if (style != _style) {
      _style = style;
      if (_active) unawaited(_platform.setStyle(style));
    }
    final overlayStyleChanged = overlayStyle != _overlayStyle;
    if (overlayStyleChanged) _overlayStyle = overlayStyle;
    final wasActive = _active;
    final taskbarChanged = enabled != _enabled;
    final overlayChanged = overlayEnabled != _overlayEnabled;
    final overlayOptionsChanged =
        overlayClickThrough != _overlayClickThrough ||
        overlayTransparentBackground != _overlayTransparentBackground;
    if (!taskbarChanged &&
        !overlayChanged &&
        !overlayOptionsChanged &&
        !overlayStyleChanged) {
      return;
    }
    _enabled = enabled;
    _overlayEnabled = overlayEnabled;
    _overlayClickThrough = overlayClickThrough;
    _overlayTransparentBackground = overlayTransparentBackground;
    if (taskbarChanged) unawaited(_platform.setEnabled(enabled));
    if (overlayChanged && (isAndroid || isWindows)) {
      unawaited(_platform.setOverlayEnabled(overlayEnabled));
    }
    if (overlayStyleChanged && _active) {
      unawaited(_platform.setOverlayStyle(overlayStyle));
    }
    if ((isAndroid || isWindows) && (overlayChanged || overlayOptionsChanged)) {
      unawaited(
        _platform.setOverlayOptions(
          clickThrough: overlayClickThrough,
          transparentBackground: overlayTransparentBackground,
        ),
      );
    }
    if (!wasActive && _active) {
      unawaited(_pushAll());
      if (isAndroid || isWindows) {
        unawaited(_platform.setOverlayStyle(overlayStyle));
      }
    } else if (wasActive && !_active) {
      _resetLyricsState();
    }
  }

  // ---------------------------------------------------------------------------
  // SystemMediaControls
  // ---------------------------------------------------------------------------

  @override
  Stream<MediaControlEvent> get events => _events.stream;

  /// 原生按锚点自行推算进度；周期性补发用于校正漂移。
  @override
  bool get needsPeriodicTimeline => true;

  @override
  Future<void> setTrack(MediaTrackInfo? track) async {
    _track = track;
    _generation++;
    _resetLyricsState();
    if (_active) await _pushTrack();
  }

  @override
  Future<void> setPlayback(MediaPlaybackInfo info) async {
    _playback = info;
    _playbackAt = DateTime.now();
    if (_active) {
      final activelyPlaying = info.playing && !info.buffering;
      await _platform.setPlayback(
        playing: activelyPlaying,
        position: info.position,
      );
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _platformEvents?.cancel();
    unawaited(_platform.setEnabled(false));
    if (isAndroid || isWindows) unawaited(_platform.setOverlayEnabled(false));
    _events.close();
  }

  // ---------------------------------------------------------------------------
  // 推送
  // ---------------------------------------------------------------------------

  Future<void> _pushAll() async {
    final style = _style;
    if (style != null) await _platform.setStyle(style);
    await _pushTrack();
    final playback = _playback;
    if (playback != null) {
      // 开启时距上次推送已过去一段时间：若正在出声，按经过的时间补上进度
      final activelyPlaying = playback.playing && !playback.buffering;
      final elapsed = activelyPlaying
          ? DateTime.now().difference(_playbackAt)
          : Duration.zero;
      await _platform.setPlayback(
        playing: activelyPlaying,
        position: playback.position + elapsed,
      );
    }
  }

  Future<void> _pushTrack() async {
    final track = _track;
    final generation = _generation;
    if (track == null) {
      await _platform.setTrack(null);
      await _platform.setLyrics(null);
      return;
    }
    await _platform.setTrack((title: track.title, artist: track.artist));
    // 先清掉上一首的歌词，新歌词到之前显示控制条，不会错配
    await _platform.setLyrics(null);
    await Future.wait([
      _pushArt(track, generation),
      _pushLyrics(track, generation),
    ]);
  }

  Future<void> _pushArt(MediaTrackInfo track, int generation) async {
    final url = track.artUrl;
    if (url != _artUrl) {
      _artUrl = url;
      _art = url.isEmpty ? null : await _download(url);
    }
    if (generation == _generation && _active && _enabled)
      await _platform.setArt(_art);
  }

  Future<Uint8List?> _download(String url) async {
    try {
      final res = await _http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200 ? res.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pushLyrics(
    MediaTrackInfo track,
    int generation, {
    bool reload = false,
  }) async {
    final loader = reload ? lyricsReloader : lyricsLoader;
    if (loader == null) return;
    SpotifyLyrics lyrics;
    try {
      lyrics = await loader(_query(track));
    } catch (_) {
      return;
    }
    if (generation != _generation || !_active) return;
    if (lyrics.isSynced) {
      _hasLyrics = true;
      _retryTimer?.cancel();
      _lastLines = lyrics.lines;
      await _platform.setLyrics(_linesForPlatform(lyrics.lines));
    } else {
      await _platform.setLyrics(null);
      _scheduleRetry(track, generation);
    }
  }

  /// 双语开关关闭时剥掉译文，只推原文。
  List<LyricLine> _linesForPlatform(List<LyricLine> lines) {
    final language = LyricsLanguage.of(
      'und',
      lines.map((line) => line.translation).join('\n'),
    );
    final target = LyricsLanguage.normalize(_locale);
    if (_bilingual &&
        LyricsLanguage.matches(language, target == 'zh' ? 'zh-Hans' : target)) {
      return lines;
    }
    return [
      for (final l in lines)
        LyricLine(startTimeMs: l.startTimeMs, words: l.words),
    ];
  }

  void _scheduleRetry(MediaTrackInfo track, int generation) {
    if (_retries >= retryDelays.length || (_retryTimer?.isActive ?? false))
      return;
    _retryTimer = Timer(retryDelays[_retries++], () {
      if (generation == _generation && _active && !_hasLyrics)
        unawaited(_pushLyrics(track, generation));
    });
  }

  void _resetLyricsState() {
    _retryTimer?.cancel();
    _hasLyrics = false;
    _retries = 0;
    _lastLines = null;
  }

  /// App 内（歌词页、右栏）取到了某首歌的歌词：若正是任务栏上这首、且任务栏还没有歌词，立即补上。
  void lyricsCached(String trackId) {
    final track = _track;
    if (!_active || _hasLyrics || track == null || track.id != trackId) return;
    unawaited(_pushLyrics(track, _generation));
  }

  static LyricsQuery _query(MediaTrackInfo track) => LyricsQuery(
    trackId: track.id,
    title: track.title,
    artist: track.artist,
    album: track.album,
    durationMs: track.duration.inMilliseconds,
  );

  /// 歌词加载器就绪（界面层首次绑定）后补推当前曲目的歌词。
  void lyricsSourceReady() {
    final track = _track;
    if (_active && track != null) unawaited(_pushLyrics(track, _generation));
  }

  void _onPlatformEvent(TaskbarLyricsEvent event) {
    switch (event) {
      case TaskbarLyricsEvent.previous:
        _events.add(const MediaButtonEvent(MediaButton.previous));
      case TaskbarLyricsEvent.toggle:
        _events.add(const MediaButtonEvent(MediaButton.toggle));
      case TaskbarLyricsEvent.next:
        _events.add(const MediaButtonEvent(MediaButton.next));
      case TaskbarLyricsEvent.open:
        onOpen?.call();
      case TaskbarLyricsEvent.disable:
        onDisable?.call();
      case TaskbarLyricsEvent.refetch:
        final track = _track;
        if (track != null) {
          _resetLyricsState();
          unawaited(
            _platform
                .setLyrics(null)
                .then((_) => _pushLyrics(track, _generation, reload: true)),
          );
        }
    }
  }
}
