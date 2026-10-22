import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/app_preferences.dart';
import '../../providers/appearance_provider.dart';
import '../../providers/preferences_provider.dart';
import '../../providers/spotify_provider.dart';
import '../../services/taskbar_lyrics/taskbar_lyrics_channel.dart';
import '../../services/taskbar_lyrics/taskbar_lyrics_controls.dart';
import '../shell/desktop/desktop_window.dart';

/// 把任务栏歌词接到界面状态上（放在 MaterialApp.builder 里，需要本地化文案）：
/// - 设置「歌词 → 任务栏歌词」的开关、颜色、不透明度；
/// - 跟随强调色时取当前主题强调色的深 / 浅两档（随封面取色变化）；
/// - 歌词来源 = SpotifyProvider（与 App 内歌词共享缓存与 LRCLIB 补全）；App 内取到歌词时同步给任务栏；
/// - 右键菜单「打开 Flutify」把窗口带到前台，「关闭任务栏歌词」写回设置。
/// 没有注入 [TaskbarLyricsControls]（非 Windows、测试）时原样返回 [child]。
class TaskbarLyricsBinding extends StatefulWidget {
  final Widget child;

  const TaskbarLyricsBinding({super.key, required this.child});

  @override
  State<TaskbarLyricsBinding> createState() => _TaskbarLyricsBindingState();
}

class _TaskbarLyricsBindingState extends State<TaskbarLyricsBinding> {
  TaskbarLyricsControls? _controls;
  StreamSubscription<String>? _lyricsCached;

  // 强调色的两档只在强调色变化时重算（需要生成整套主题）
  Color? _accent;
  (int, int) _accentTones = (0xFF1ED760, 0xFF1DB954);

  @override
  void initState() {
    super.initState();
    final controls = context.read<TaskbarLyricsControls?>();
    _controls = controls;
    if (controls == null) return;
    final spotify = context.read<SpotifyProvider>();
    final preferences = context.read<PreferencesProvider>();
    controls
      ..lyricsLoader = spotify.fetchLyrics
      ..lyricsReloader = spotify.refetchLyrics
      ..onOpen = () {
        unawaited(DesktopWindow.bringToFront());
      }
      ..onDisable = () {
        preferences.update(preferences.prefs.copyWith(taskbarLyrics: false));
      }
      ..lyricsSourceReady();
    _lyricsCached = spotify.lyricsCached.listen(controls.lyricsCached);
  }

  @override
  void dispose() {
    unawaited(_lyricsCached?.cancel());
    _controls
      ?..lyricsLoader = null
      ..lyricsReloader = null
      ..onOpen = null
      ..onDisable = null;
    super.dispose();
  }

  (int, int) _tones(AppearanceProvider appearance, Color accent) {
    if (accent != _accent) {
      _accent = accent;
      _accentTones = (
        appearance.theme(Brightness.dark).colorScheme.primary.toARGB32(),
        appearance.theme(Brightness.light).colorScheme.primary.toARGB32(),
      );
    }
    return _accentTones;
  }

  @override
  Widget build(BuildContext context) {
    final controls = _controls;
    if (controls == null) return widget.child;
    final prefs = context.select<PreferencesProvider, AppPreferences>(
      (p) => p.prefs,
    );
    final appearance = context.read<AppearanceProvider>();
    final accent = context.select<AppearanceProvider, Color>((a) => a.accent);
    final (onDark, onLight) =
        (prefs.taskbarLyricsColor == TaskbarLyricsColor.accent ||
            prefs.floatingLyricsColor == TaskbarLyricsColor.accent)
        ? _tones(appearance, accent)
        : _accentTones;
    final l10n = context.l10n;
    controls.configure(
      enabled: prefs.taskbarLyrics && (controls.isFlyme || !controls.isAndroid),
      overlayEnabled:
          prefs.floatingLyrics && (controls.isAndroid || controls.isWindows),
      overlayClickThrough: prefs.floatingLyricsClickThrough,
      overlayTransparentBackground: prefs.floatingLyricsTransparent,
      bilingual: prefs.lyricsBilingual,
      locale: Localizations.localeOf(context).toLanguageTag(),
      overlayStyle: TaskbarLyricsStyle(
        mode: prefs.floatingLyricsColor,
        customColor: prefs.floatingLyricsCustomColor,
        accentOnDark: onDark,
        accentOnLight: onLight,
        fontScale: prefs.floatingLyricsFontScale,
      ),
      style: TaskbarLyricsStyle(
        mode: prefs.taskbarLyricsColor,
        customColor: prefs.taskbarLyricsCustomColor,
        accentOnDark: onDark,
        accentOnLight: onLight,
        opacity: prefs.taskbarLyricsOpacity,
        fontScale: prefs.taskbarLyricsFontScale,
        openLabel: l10n.taskbarLyricsMenuOpen,
        refetchLabel: l10n.taskbarLyricsMenuRefetch,
        disableLabel: l10n.taskbarLyricsMenuDisable,
      ),
    );
    return widget.child;
  }
}
