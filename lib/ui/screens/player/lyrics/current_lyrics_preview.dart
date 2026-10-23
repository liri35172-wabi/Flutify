import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/l10n.dart';
import '../../../../models/lyrics.dart';
import '../../../../models/lyrics_query.dart';
import '../../../../models/track.dart';
import '../../../../providers/connect_provider.dart';
import '../../../../providers/playback_provider.dart';
import '../../../../providers/spotify_provider.dart';

/// A small, tappable lyric excerpt shown beneath the large player artwork.
/// It reads the same lyric cache and playback position as the full lyrics view.
class CurrentLyricsPreview extends StatefulWidget {
  const CurrentLyricsPreview({
    super.key,
    required this.track,
    required this.remote,
    required this.onTap,
  });

  final SpotifyTrack track;
  final bool remote;
  final VoidCallback onTap;

  @override
  State<CurrentLyricsPreview> createState() => _CurrentLyricsPreviewState();
}

class _CurrentLyricsPreviewState extends State<CurrentLyricsPreview> {
  SpotifyLyrics? _lyrics;
  late final ValueListenable<Duration> _position;
  bool _initialized = false;
  int _loadRevision = 0;
  int _lyricsGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _position = widget.remote
        ? context.read<ConnectProvider>().position
        : context.read<PlaybackProvider>().positionNotifier;
    _loadLyrics();
  }

  void _loadLyrics() {
    final revision = ++_loadRevision;
    final spotify = context.read<SpotifyProvider>();
    _lyricsGeneration = spotify.lyricsGeneration;
    final cached = spotify.cachedLyrics(widget.track.id);
    if (cached != null) {
      _lyrics = cached;
      return;
    }
    final generation = _lyricsGeneration;
    unawaited(_fetchLyrics(spotify, revision, generation));
  }

  Future<void> _fetchLyrics(
    SpotifyProvider spotify,
    int revision,
    int generation,
  ) async {
    try {
      final lyrics = await spotify.fetchLyrics(
        LyricsQuery.fromTrack(widget.track),
      );
      if (!mounted ||
          generation != _lyricsGeneration ||
          revision != _loadRevision) {
        return;
      }
      setState(() => _lyrics = lyrics);
    } catch (_) {
      // The preview is optional; a failed lyric lookup must not destabilize
      // artwork paging or surface an unhandled asynchronous error.
      if (!mounted || revision != _loadRevision) return;
      setState(() => _lyrics = null);
    }
  }

  int _activeIndex(SpotifyLyrics lyrics, Duration position) {
    if (!lyrics.isSynced) return 0;
    final target = position.inMilliseconds;
    var low = 0;
    var high = lyrics.lines.length - 1;
    var result = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (lyrics.lines[mid].startTimeMs <= target) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return math.max(0, result);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: _position,
      builder: (context, position, _) {
        final lyrics = _lyrics;
        final lines = lyrics?.lines ?? const <LyricLine>[];
        if (lines.isEmpty) {
          return _PreviewSurface(
            onTap: widget.onTap,
            label: context.l10n.lyricsUnavailableTitle,
            children: [
              Text(
                context.l10n.lyricsUnavailableTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );
        }
        final active = _activeIndex(lyrics!, position);
        return _PreviewSurface(
          onTap: widget.onTap,
          label: lines[active].words,
          children: [
            for (final offset in const [-1, 0, 1])
              if (active + offset >= 0 && active + offset < lines.length)
                _LyricPreviewLine(
                  key: ValueKey((active, offset, widget.track.id)),
                  line: lines[active + offset],
                  primary: offset == 0,
                )
              else
                const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _PreviewSurface extends StatelessWidget {
  const _PreviewSurface({
    required this.onTap,
    required this.label,
    required this.children,
  });

  final VoidCallback onTap;
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    hint: context.l10n.lyricsTitle,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        // The scene reserves an 82 px slot; four-pixel insets leave enough room
        // for all three 24 px lyric rows without clipping.
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

class _LyricPreviewLine extends StatelessWidget {
  const _LyricPreviewLine({
    super.key,
    required this.line,
    required this.primary,
  });

  final LyricLine line;
  final bool primary;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: primary ? 1 : 0.48,
    duration: const Duration(milliseconds: 180),
    child: SizedBox(
      height: 24,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          line.words,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: primary ? 14 : 12,
            fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
            shadows: const [
              Shadow(
                color: Colors.black45,
                blurRadius: 5,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
