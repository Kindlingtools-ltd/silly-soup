import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Adult settings, stored on this device and nowhere else.
///
/// No account, no sync, no identifiers. See PRIVACY.md.
class StorageService {
  static const String _settingsKey = 'silly_soup_settings';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<AppSettings> getSettings() async {
    await init();
    final stored = _prefs!.getString(_settingsKey);
    if (stored == null) return AppSettings.defaults;
    try {
      return AppSettings.fromJson(json.decode(stored) as Map<String, dynamic>);
    } catch (_) {
      // Settings written by a future version, or corrupted. Falling back to
      // the defaults keeps the app usable in front of a class.
      return AppSettings.defaults;
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    await init();
    await _prefs!.setString(_settingsKey, json.encode(settings.toJson()));
  }

  Future<void> clear() async {
    await init();
    await _prefs!.remove(_settingsKey);
  }
}
