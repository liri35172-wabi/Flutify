import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/l10n.dart';
import '../../../../providers/preferences_provider.dart';
import '../../../../services/taskbar_lyrics/taskbar_lyrics_channel.dart';
import '../../../../services/taskbar_lyrics/taskbar_lyrics_controls.dart';
import '../widgets/settings_section.dart';

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
    final prefs = context.select<PreferencesProvider, bool>(
      (provider) => provider.prefs.floatingLyrics,
    );
    final l10n = context.l10n;
    return SettingsSection(
      title: l10n.settingsFloatingLyrics,
      children: [
        SettingsSwitchTile(
          title: l10n.settingsFloatingLyrics,
          subtitle: l10n.settingsFloatingLyricsSubtitle,
          value: prefs,
          onChanged: (enabled) {
            if (enabled) {
              unawaited(_enable(context));
            } else {
              context.read<PreferencesProvider>().update(
                context.read<PreferencesProvider>().prefs.copyWith(
                  floatingLyrics: false,
                ),
              );
            }
          },
        ),
      ],
    );
  }
}
