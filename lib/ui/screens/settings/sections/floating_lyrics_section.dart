import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/l10n.dart';
import '../../../../models/app_preferences.dart';
import '../../../../providers/preferences_provider.dart';
import '../../../../providers/appearance_provider.dart';
import '../../../../services/taskbar_lyrics/taskbar_lyrics_channel.dart';
import '../../../../services/taskbar_lyrics/taskbar_lyrics_controls.dart';
import '../widgets/custom_color_dialog.dart';
import '../widgets/floating_lyrics_preview_text.dart';
import '../widgets/settings_section.dart';
import '../widgets/settings_segmented.dart';
import '../widgets/settings_slider_tile.dart';

class FloatingLyricsSection extends StatefulWidget {
  const FloatingLyricsSection({super.key});

  @override
  State<FloatingLyricsSection> createState() => _FloatingLyricsSectionState();
}

class _FloatingLyricsSectionState extends State<FloatingLyricsSection>
    with WidgetsBindingObserver {
  bool _waitingForPermission = false;
  bool _checkingPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _available(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isWindows) return false;
    try {
      final controls = context.read<TaskbarLyricsControls?>();
      return Platform.isAndroid
          ? controls?.isAndroid == true
          : controls?.isWindows == true;
    } on ProviderNotFoundException {
      return false;
    }
  }

  Future<void> _enable(BuildContext context) async {
    final preferences = context.read<PreferencesProvider>();
    if (Platform.isWindows ||
        await MethodChannelTaskbarLyrics.hasOverlayPermission()) {
      preferences.update(preferences.prefs.copyWith(floatingLyrics: true));
      return;
    }
    if (!mounted) return;
    setState(() => _waitingForPermission = true);
    await MethodChannelTaskbarLyrics.requestOverlayPermission();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !_waitingForPermission ||
        _checkingPermission) {
      return;
    }
    _checkingPermission = true;
    unawaited(_finishPermissionCheck());
  }

  Future<void> _finishPermissionCheck() async {
    final granted = await MethodChannelTaskbarLyrics.hasOverlayPermission();
    if (!mounted) return;
    setState(() {
      _waitingForPermission = false;
      _checkingPermission = false;
    });
    if (granted) {
      context.read<PreferencesProvider>().update(
        context.read<PreferencesProvider>().prefs.copyWith(
          floatingLyrics: true,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settingsFloatingLyricsSubtitle)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_available(context)) return const SizedBox.shrink();
    final prefs = context.select<PreferencesProvider, AppPreferences>(
      (provider) => provider.prefs,
    );
    final enabled = prefs.floatingLyrics;
    final l10n = context.l10n;
    final provider = context.read<PreferencesProvider>();
    void update(AppPreferences Function(AppPreferences p) change) =>
        provider.update(change(provider.prefs));
    final accent = context.select<AppearanceProvider, Color>((a) => a.accent);
    final lyricColor = switch (prefs.floatingLyricsColor) {
      TaskbarLyricsColor.auto || TaskbarLyricsColor.white => Colors.white,
      TaskbarLyricsColor.black => const Color(0xFF16181D),
      TaskbarLyricsColor.accent => accent,
      TaskbarLyricsColor.custom => Color(prefs.floatingLyricsCustomColor),
    };
    return SettingsSection(
      title: l10n.settingsFloatingLyrics,
      children: [
        SettingsSwitchTile(
          title: l10n.settingsFloatingLyrics,
          subtitle: l10n.settingsFloatingLyricsSubtitle,
          value: enabled,
          onChanged: (enabled) {
            if (enabled) {
              unawaited(_enable(context));
            } else {
              update((p) => p.copyWith(floatingLyrics: false));
            }
          },
        ),
        if (enabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Container(
              height: 68,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: prefs.floatingLyricsTransparent
                    ? Colors.transparent
                    : const Color(0x99212630),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingLyricsPreviewText(
                    text: '无名的人啊  我敬你一杯酒',
                    color: lyricColor,
                    fontSize: 16 * prefs.floatingLyricsFontScale / 100,
                    fontWeight: FontWeight.w600,
                  ),
                  const SizedBox(height: 2),
                  FloatingLyricsPreviewText(
                    text: '敬你的沉默 和每一聲怒吼',
                    color: lyricColor.withValues(alpha: 0.62),
                    fontSize: 10 * prefs.floatingLyricsFontScale / 100,
                    fontWeight: FontWeight.w400,
                  ),
                ],
              ),
            ),
          ),
          SettingsTile(
            title: l10n.settingsFloatingLyricsColor,
            subtitle: l10n.settingsFloatingLyricsAutoColorSubtitle,
            below: SettingsSegmented<TaskbarLyricsColor>(
              values: TaskbarLyricsColor.values,
              labelOf: (value) => switch (value) {
                TaskbarLyricsColor.auto => l10n.taskbarLyricsColorAuto,
                TaskbarLyricsColor.white => l10n.taskbarLyricsColorWhite,
                TaskbarLyricsColor.black => l10n.taskbarLyricsColorBlack,
                TaskbarLyricsColor.accent => l10n.taskbarLyricsColorAccent,
                TaskbarLyricsColor.custom => l10n.taskbarLyricsColorCustom,
              },
              selected: prefs.floatingLyricsColor,
              onChanged: (value) =>
                  update((p) => p.copyWith(floatingLyricsColor: value)),
            ),
          ),
          if (prefs.floatingLyricsColor == TaskbarLyricsColor.custom)
            SettingsTile(
              title: l10n.settingsFloatingLyricsCustomColor,
              trailing: _FloatingLyricsColorButton(
                color: Color(prefs.floatingLyricsCustomColor),
                label: l10n.settingsTaskbarLyricsChangeColor,
                onTap: () async {
                  final picked = await CustomColorDialog.show(
                    context,
                    initial: Color(prefs.floatingLyricsCustomColor),
                  );
                  if (picked != null) {
                    update(
                      (p) => p.copyWith(
                        floatingLyricsCustomColor: picked.toARGB32(),
                      ),
                    );
                  }
                },
              ),
            ),
          SettingsSliderTile(
            title: l10n.settingsFloatingLyricsFontSize,
            value: prefs.floatingLyricsFontScale.toDouble(),
            min: AppPreferences.minFloatingLyricsFontScale.toDouble(),
            max: AppPreferences.maxFloatingLyricsFontScale.toDouble(),
            divisions: 14,
            minIcon: Icons.text_decrease_rounded,
            maxIcon: Icons.text_increase_rounded,
            labelOf: (value) => '${value.round()}%',
            onChanged: (value) => update(
              (p) => p.copyWith(floatingLyricsFontScale: value.round()),
            ),
          ),
        ],
        if (Platform.isAndroid)
          SettingsSwitchTile(
            title: l10n.settingsFloatingLyricsClickThrough,
            subtitle: l10n.settingsFloatingLyricsClickThroughSubtitle,
            value: prefs.floatingLyricsClickThrough,
            onChanged: (value) =>
                update((p) => p.copyWith(floatingLyricsClickThrough: value)),
          ),
        if (Platform.isAndroid || Platform.isWindows)
          SettingsSwitchTile(
            title: l10n.settingsFloatingLyricsTransparent,
            subtitle: l10n.settingsFloatingLyricsTransparentSubtitle,
            value: prefs.floatingLyricsTransparent,
            onChanged: (value) =>
                update((p) => p.copyWith(floatingLyricsTransparent: value)),
          ),
      ],
    );
  }
}

class _FloatingLyricsColorButton extends StatelessWidget {
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _FloatingLyricsColorButton({
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: onTap,
      icon: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outlineVariant, width: 1.5),
        ),
      ),
      label: Text(label),
    );
  }
}
