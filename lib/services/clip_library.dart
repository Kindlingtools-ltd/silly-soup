import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Which recordings were built, so the app can tell before it starts playing.
///
/// A line made of several clips cannot be discovered to be incomplete
/// half-way through: the child would hear "In goes a" and then silence, and
/// re-speaking the line from the top would say the first half twice. So the
/// build writes the list of what it produced and the app reads it once.
///
/// It is also the honest answer to "which clips are still missing?" — the
/// adult area reports it, and it is what `--audit` checks against.
class ClipLibrary {
  const ClipLibrary(this._paths);

  /// Nothing recorded. Every line falls back to the device voice, which is
  /// how the app behaves before the clips are built.
  const ClipLibrary.empty() : _paths = const <String>{};

  @visibleForTesting
  factory ClipLibrary.withClips(Iterable<String> paths) =>
      ClipLibrary(paths.toSet());

  final Set<String> _paths;

  static const String manifestAsset = 'assets/audio/manifest.json';

  int get length => _paths.length;

  bool has(String assetPath) => _paths.contains(assetPath);

  /// True only when every clip in the line is there.
  bool hasAll(Iterable<String> assetPaths) {
    for (final path in assetPaths) {
      if (!_paths.contains(path)) return false;
    }
    return true;
  }

  /// Read the manifest the audio build wrote.
  ///
  /// A missing or unreadable manifest is not an error worth stopping for: the
  /// app still works, it just speaks every line instead of playing it.
  static Future<ClipLibrary> load({AssetBundle? bundle}) async {
    try {
      final raw = await (bundle ?? rootBundle).loadString(manifestAsset);
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final clips = (decoded['clips'] as List? ?? const [])
          .cast<String>()
          .map((path) => 'assets/audio/$path')
          .toSet();
      return ClipLibrary(clips);
    } catch (error) {
      debugPrint(
        'Silly Soup: no audio manifest ($error). The chef will speak rather '
        'than play its recordings.',
      );
      return const ClipLibrary.empty();
    }
  }
}
