import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/l10n.dart';
import '../../../../providers/preferences_provider.dart';
import '../../../../services/taskbar_lyrics/taskbar_lyrics_channel.dart';
import '../../../../services/taskbar_lyrics/taskbar_lyrics_controls.dart';

/// A compact player shortcut for the existing floating-lyrics preference.
/// Android's overlay permission flow mirrors the settings switch; Windows does
/// not need a permission prompt. The native binding remains the sole owner of
/// starting/stopping the overlay, so this button cannot create a second path.
class FloatingLyricsQuickToggle extends StatefulWidget {
  const FloatingLyricsQuickToggle({
    super.key,
    this.buttonSize = 44,
    this.iconSize = 22,
    this.buttonStyle,
    this.activeColor,
    this.inactiveColor,
  });

  final double buttonSize;
  final double iconSize;
  final ButtonStyle? buttonStyle;
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  State<FloatingLyricsQuickToggle> createState() =>
      _FloatingLyricsQuickToggleState();
}

class _FloatingLyricsQuickToggleState extends State<FloatingLyricsQuickToggle>
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

  void _setEnabled(bool value) {
    final preferences = context.read<PreferencesProvider>();
    preferences.update(preferences.prefs.copyWith(floatingLyrics: value));
  }

  Future<void> _toggle(bool enabled, TaskbarLyricsControls controls) async {
    if (enabled) {
      _setEnabled(false);
      return;
    }
    if (!controls.isAndroid ||
        await MethodChannelTaskbarLyrics.hasOverlayPermission()) {
      if (mounted) _setEnabled(true);
      return;
    }
    if (!mounted || _waitingForPermission) return;
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
      _setEnabled(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settingsFloatingLyricsSubtitle)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controls = context.watch<TaskbarLyricsControls?>();
    if (controls == null || (!controls.isAndroid && !controls.isWindows)) {
      return const SizedBox.shrink();
    }
    final enabled = context.select<PreferencesProvider, bool>(
      (preferences) => preferences.prefs.floatingLyrics,
    );
    final primary = Theme.of(context).colorScheme.primary;
    return IconButton(
      tooltip: context.l10n.settingsFloatingLyrics,
      isSelected: enabled,
      visualDensity: VisualDensity.compact,
      constraints: BoxConstraints.tightFor(
        width: widget.buttonSize,
        height: widget.buttonSize,
      ),
      style: widget.buttonStyle,
      onPressed: _waitingForPermission
          ? null
          : () => unawaited(_toggle(enabled, controls)),
      icon: Icon(
        enabled ? Icons.subtitles_rounded : Icons.subtitles_outlined,
        size: widget.iconSize,
        color: enabled
            ? (widget.activeColor ?? primary)
            : (widget.inactiveColor ?? Colors.white70),
      ),
    );
  }
}
