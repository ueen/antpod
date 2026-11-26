// lib/app_settings.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The switches in the settings sheet, kept in SharedPreferences.
/// (Speed and skip intervals live with the player: PlayerProvider.)
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs);
  final SharedPreferences _prefs;

  static const keyMaterialYou = 'settings_material_you';
  static const keyMarkPlayedNearEnd = 'settings_mark_played_near_end';
  static const keyDeletePlayedDownloads = 'settings_delete_played_downloads';

  /// Every key, for the backup.
  static const keys = [
    keyMaterialYou, keyMarkPlayedNearEnd, keyDeletePlayedDownloads,
  ];

  /// Colors from the wallpaper (Android 12+) instead of AntPod's brown.
  bool get materialYou => _prefs.getBool(keyMaterialYou) ?? false;
  set materialYou(bool v) => _set(keyMaterialYou, v);

  /// A pause in an episode's last minute marks it as played (outros, trailers).
  bool get markPlayedNearEnd => _prefs.getBool(keyMarkPlayedNearEnd) ?? true;
  set markPlayedNearEnd(bool v) => _set(keyMarkPlayedNearEnd, v);

  /// Downloads of played episodes are deleted 2 days later.
  bool get deletePlayedDownloads =>
      _prefs.getBool(keyDeletePlayedDownloads) ?? true;
  set deletePlayedDownloads(bool v) => _set(keyDeletePlayedDownloads, v);

  void _set(String key, bool v) {
    // The in-memory value changes at once; the write to disk follows.
    _prefs.setBool(key, v);
    notifyListeners();
  }

  /// After a backup import wrote the keys directly.
  void reload() => notifyListeners();
}
