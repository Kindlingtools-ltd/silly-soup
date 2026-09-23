import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/services.dart';

/// App-wide state: the adult's settings, the sound bank, and the voice.
class AppProvider extends ChangeNotifier {
  AppProvider({
    StorageService? storage,
    WordBankService? wordBank,
    AudioService? audio,
  }) : _storage = storage ?? StorageService(),
       _wordBank = wordBank ?? WordBankService(),
       _audio = audio ?? AudioService();

  final StorageService _storage;
  final WordBankService _wordBank;
  final AudioService _audio;

  bool _isInitialised = false;
  String? _error;
  AppSettings _settings = AppSettings.defaults;

  bool get isInitialised => _isInitialised;
  String? get error => _error;
  AppSettings get settings => _settings;
  SoundBank get bank => _wordBank.bank;
  AudioService get audio => _audio;

  /// Warnings about the merged bank, shown to adults only.
  ValidationResult get bankValidation => _wordBank.validation;

  /// Clips the app has asked for and not found.
  List<String> get missingClips => _audio.missingClips;

  /// The sounds offered in the picker, in the adult's chosen order.
  List<PhonemeSound> get availableSounds =>
      SoupService.availableSounds(bank: bank, settings: _settings);

  Future<void> initialise() async {
    try {
      _settings = await _storage.getSettings();
      _audio.volume = _settings.volume;
      await _wordBank.load();
    } catch (error) {
      _error = 'Could not load the soup ingredients: $error';
    } finally {
      _isInitialised = true;
      notifyListeners();
    }
  }

  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
    _audio.volume = settings.volume;
    notifyListeners();
    await _storage.saveSettings(settings);
  }

  /// True when animation should be held back: either the device asks for it
  /// or the adult has turned motion down in the adult area.
  bool prefersReducedMotion(BuildContext context) =>
      _settings.reducedMotion || MediaQuery.of(context).disableAnimations;

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }
}
