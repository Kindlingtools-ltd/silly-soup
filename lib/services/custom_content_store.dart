import 'dart:typed_data';

import '../models/models.dart';

/// Where an adult's own sounds, words, pictures and recordings live.
///
/// The overlay is merged on top of the built-in bank, so built-in content is
/// only ever hidden or overridden, never destroyed.
///
/// Stage 2 adds the IndexedDB-backed implementation. The interface is here
/// from day one so the rest of the app never needs to change when it lands.
abstract class CustomContentStore {
  /// The adult's edits, additions and hidden flags.
  Future<SoundBank> loadOverlay();

  Future<void> saveOverlay(SoundBank overlay);

  /// Picture and audio blobs, keyed by the id used in `image: custom:<id>`.
  Future<Uint8List?> loadMedia(String id);

  /// Store a blob and return the id to reference it by.
  Future<String> saveMedia(Uint8List bytes, {required String mimeType});

  Future<void> deleteMedia(String id);

  /// Remove every piece of custom content from this device.
  Future<void> clear();
}

/// Holds custom content for the lifetime of the app only.
///
/// This is what the app uses until the IndexedDB store arrives in Stage 2:
/// the merge path, validation and preview are all exercised, and nothing is
/// written to the device in the meantime.
class InMemoryCustomContentStore implements CustomContentStore {
  SoundBank _overlay = SoundBank.empty;
  final Map<String, Uint8List> _media = {};
  int _nextMediaId = 1;

  @override
  Future<SoundBank> loadOverlay() async => _overlay;

  @override
  Future<void> saveOverlay(SoundBank overlay) async => _overlay = overlay;

  @override
  Future<Uint8List?> loadMedia(String id) async => _media[id];

  @override
  Future<String> saveMedia(Uint8List bytes, {required String mimeType}) async {
    final id = 'media-${_nextMediaId++}';
    _media[id] = bytes;
    return id;
  }

  @override
  Future<void> deleteMedia(String id) async => _media.remove(id);

  @override
  Future<void> clear() async {
    _overlay = SoundBank.empty;
    _media.clear();
  }
}
