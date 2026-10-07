import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/services.dart';

/// App-wide state: the adult's settings, the sound bank, and the voice.
class AppProvider extends ChangeNotifier {
  AppProvider({
    StorageService? storage,
    WordBankService? wordBank,
    AudioService? audio,
    AnalyticsService? analytics,
  }) : _storage = storage ?? StorageService(),
       _wordBank = wordBank ?? WordBankService(),
       _audio = audio ?? AudioService(),
       _analytics = analytics ?? AnalyticsService();

  final StorageService _storage;
  final WordBankService _wordBank;
  final AudioService _audio;
  final AnalyticsService _analytics;

  ChefVoice _chefVoice = const ChefVoice();

  bool _isInitialised = false;
  String? _error;
  AppSettings _settings = AppSettings.defaults;

  bool get isInitialised => _isInitialised;
  String? get error => _error;
  AppSettings get settings => _settings;
  SoundBank get bank => _wordBank.bank;
  AudioService get audio => _audio;
  AnalyticsService get analytics => _analytics;

  /// What the chef says, and which recordings say it. Empty until
  /// [initialise] has read the script and the audio manifest, at which point
  /// the chef stops depending on the device's own voice.
  ChefVoice get chefVoice => _chefVoice;

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
      _chefVoice = ChefVoice(
        script: _wordBank.script,
        catalogue: _wordBank.catalogue,
      );
    } catch (error) {
      _error = 'Could not load the soup ingredients: $error';
      _analytics.logStartupFailed();
    } finally {
      _isInitialised = true;
      if (_error == null) {
        _analytics.logAppStarted(_settings, soundCount: availableSounds.length);
      }
      notifyListeners();
    }
  }

  Future<void> updateSettings(AppSettings settings) async {
    final previous = _settings;
    _settings = settings;
    _audio.volume = settings.volume;
    _analytics.logSettingsChanged(previous, settings);
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
