import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import 'custom_content_store.dart';

/// Loads the built-in sound bank and merges the adult's own content on top.
class WordBankService {
  WordBankService({CustomContentStore? customContentStore, AssetBundle? bundle})
    : _customContent = customContentStore ?? InMemoryCustomContentStore(),
      _bundle = bundle ?? rootBundle;

  static const String bankAssetPath = 'assets/data/sound_bank.json';

  final CustomContentStore _customContent;
  final AssetBundle _bundle;

  SoundBank _bank = SoundBank.empty;
  ValidationResult _validation = const ValidationResult.ok();

  /// The bank the app plays from: built-in content with the adult's overlay
  /// applied.
  SoundBank get bank => _bank;

  /// What validation said about the merged bank. Warnings here are what the
  /// adult area shows ("this sound has only 4 words").
  ValidationResult get validation => _validation;

  Future<SoundBank> load() async {
    final raw = await _bundle.loadString(bankAssetPath);
    final builtIn = SoundBank.fromJson(
      json.decode(raw) as Map<String, dynamic>,
    );

    final overlay = await _customContent.loadOverlay();
    _bank = overlay.sounds.isEmpty && overlay.words.isEmpty
        ? builtIn
        : builtIn.mergedWith(overlay);

    _validation = SoundBank.validate(_bank.toJson());
    for (final issue in _validation.issues) {
      debugPrint('Silly Soup sound bank: $issue');
    }
    return _bank;
  }

  /// Replace the adult's overlay — used by the adult area in Stage 2 and by
  /// sound pack import.
  Future<SoundBank> applyOverlay(SoundBank overlay) async {
    await _customContent.saveOverlay(overlay);
    return load();
  }

  /// Everything an adult would export: their overlay only, so a pack stays
  /// small and does not ship a second copy of the built-in words.
  Future<SoundBank> exportableOverlay() => _customContent.loadOverlay();
}
