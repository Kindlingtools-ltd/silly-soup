import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import 'clip_catalogue.dart';
import 'custom_content_store.dart';

/// Loads the content the app plays: the built-in sound bank with the adult's
/// own content merged on top, the chef's script of fixed lines, and the list
/// of recordings in the bundle.
///
/// All three come through the one [AssetBundle] this is given, so a test that
/// substitutes the bundle substitutes all of it. Reaching past it to
/// `rootBundle` for any of them is what made the widget tests hang.
class WordBankService {
  WordBankService({CustomContentStore? customContentStore, AssetBundle? bundle})
    : _customContent = customContentStore ?? InMemoryCustomContentStore(),
      _bundle = bundle ?? rootBundle;

  static const String bankAssetPath = 'assets/data/sound_bank.json';
  static const String scriptAssetPath = 'assets/data/chef_script.json';

  final CustomContentStore _customContent;
  final AssetBundle _bundle;

  SoundBank _bank = SoundBank.empty;
  ChefScript _script = ChefScript.empty;
  ClipCatalogue _catalogue = ClipCatalogue.empty;
  ValidationResult _validation = const ValidationResult.ok();

  /// The bank the app plays from: built-in content with the adult's overlay
  /// applied.
  SoundBank get bank => _bank;

  /// The chef's fixed lines. Empty when the asset could not be read, which
  /// leaves the chef speaking with the device voice rather than silent.
  ChefScript get script => _script;

  /// Which recordings are in the bundle. Empty when the manifest could not be
  /// read, which leaves the chef speaking with the device voice.
  ClipCatalogue get catalogue => _catalogue;

  /// What validation said about the merged bank. Warnings here are what the
  /// adult area shows ("this sound has only 4 words").
  ValidationResult get validation => _validation;

  Future<SoundBank> load() async {
    _script = await _loadScript();
    _catalogue = await ClipCatalogue.load(bundle: _bundle);
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

  Future<ChefScript> _loadScript() async {
    try {
      final raw = await _bundle.loadString(scriptAssetPath);
      return ChefScript.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (error) {
      debugPrint('Silly Soup: no chef script ($error), speaking instead');
      return ChefScript.empty;
    }
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
