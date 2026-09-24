import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Which recordings are in the bundle, known before anything is played.
///
/// "Is this clip here?" cannot be answered by trying to play it. On the web a
/// missing asset is an HTTP request, and the host that serves this app answers
/// anything it does not recognise with `200` and `index.html` — so every
/// missing clip looks present until the player is handed a web page.
///
/// That matters more than it used to. The chef now says a whole sentence as a
/// run of clips, and the choice between "play the clips" and "speak the line"
/// has to be made before the first word, not discovered half way through it.
class ClipCatalogue {
  const ClipCatalogue(this.paths);

  /// Nothing recorded: everything falls back to the device voice.
  static const ClipCatalogue empty = ClipCatalogue(<String>{});

  static const String manifestAssetPath = 'assets/data/audio_manifest.json';

  /// Full asset paths, e.g. `assets/audio/words/banana.mp3`.
  final Set<String> paths;

  bool has(String assetPath) => paths.contains(assetPath);

  /// True when every clip in [assetPaths] is present, and there is at least
  /// one. An empty list is not something the chef can say.
  bool hasAll(Iterable<String> assetPaths) {
    var any = false;
    for (final path in assetPaths) {
      if (!has(path)) return false;
      any = true;
    }
    return any;
  }

  static ClipCatalogue fromJson(Map<String, dynamic> json) {
    final clips = json['clips'] as Map<String, dynamic>? ?? const {};
    return ClipCatalogue({
      for (final relative in clips.keys) 'assets/audio/$relative',
    });
  }

  /// Read the manifest `tool/generate_audio.py` writes. A missing or broken
  /// manifest is not fatal: the chef speaks instead, which is how the app
  /// behaved before any clip existed.
  static Future<ClipCatalogue> load({AssetBundle? bundle}) async {
    try {
      final raw = await (bundle ?? rootBundle).loadString(manifestAssetPath);
      return fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (error) {
      debugPrint('Silly Soup: no audio manifest ($error), speaking instead');
      return empty;
    }
  }
}
