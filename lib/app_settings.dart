// lib/app_settings.dart
import 'package:flutter/material.dart' show ThemeMode;
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
  static const keyTheme = 'settings_theme';
  static const keyRewindOnResume = 'settings_rewind_on_resume';
  static const keyTrendsCountry = 'settings_trends_country';
  static const keyAppleApi = 'settings_apple_api';

  /// Every key, for the backup.
  static const keys = [
    keyMaterialYou, keyMarkPlayedNearEnd, keyDeletePlayedDownloads,
    keyTheme, keyRewindOnResume, keyTrendsCountry, keyAppleApi,
  ];

  /// System, light or dark; stored by name ('system', 'light', 'dark').
  ThemeMode get themeMode => ThemeMode.values.asNameMap()[_prefs.getString(keyTheme)] ??
      ThemeMode.system;
  set themeMode(ThemeMode v) {
    _prefs.setString(keyTheme, v.name);
    notifyListeners();
  }

  /// Colors from the wallpaper (Android 12+) instead of AntPod's brown.
  bool get materialYou => _prefs.getBool(keyMaterialYou) ?? false;
  set materialYou(bool v) => _set(keyMaterialYou, v);

  /// A pause in an episode's last [nearEnd] marks it as played (outros,
  /// trailers).
  bool get markPlayedNearEnd => _prefs.getBool(keyMarkPlayedNearEnd) ?? true;
  set markPlayedNearEnd(bool v) => _set(keyMarkPlayedNearEnd, v);

  /// Downloads of played episodes are deleted 2 days later.
  bool get deletePlayedDownloads =>
      _prefs.getBool(keyDeletePlayedDownloads) ?? true;
  set deletePlayedDownloads(bool v) => _set(keyDeletePlayedDownloads, v);

  /// Resuming after a long pause starts a little earlier, to pick the
  /// thread up again. The settings sheet's text names these two numbers.
  bool get rewindOnResume => _prefs.getBool(keyRewindOnResume) ?? true;
  set rewindOnResume(bool v) => _set(keyRewindOnResume, v);

  static const resumeRewindAfter = Duration(minutes: 5);
  static const resumeRewindBy = Duration(seconds: 3);

  /// An episode's last stretch: a pause in it can mark the episode played,
  /// and a save in it leaves a played episode played.
  static const nearEnd = Duration(seconds: 100);

  /// How far back playback resumes after a pause of [pausedFor].
  Duration resumeRewind(Duration pausedFor) =>
      rewindOnResume && pausedFor >= resumeRewindAfter
          ? resumeRewindBy
          : Duration.zero;

  /// The country Apple's charts come from (ISO code, lowercase); null until
  /// one is picked, then the app locale's.
  String? get trendsCountry => _prefs.getString(keyTrendsCountry);
  set trendsCountry(String? v) {
    v == null ? _prefs.remove(keyTrendsCountry) : _prefs.setString(keyTrendsCountry, v);
    notifyListeners();
  }

  /// Apple Podcasts for the Discover page's trends and episode search. Off,
  /// no trends and search asks PodcastIndex only (podcasts, no episodes).
  bool get appleApi => _prefs.getBool(keyAppleApi) ?? true;
  set appleApi(bool v) => _set(keyAppleApi, v);

  void _set(String key, bool v) {
    // The in-memory value changes at once; the write to disk follows.
    _prefs.setBool(key, v);
    notifyListeners();
  }

  /// After a backup import wrote the keys directly.
  void reload() => notifyListeners();
}
