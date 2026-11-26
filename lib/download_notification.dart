// lib/download_notification.dart
//
// The one and only download notification (Android). flutter_downloader runs
// with showNotification:false, so it posts nothing itself: no per-task
// notifications and no "complete"/"failed" ones. Instead DownloadProvider
// pushes the list of active downloads here on every poll, and this shows a
// single ongoing notification backed by a foreground service, which keeps
// the process (and its WorkManager download workers) alive when the app is
// closed. When the list is empty the service stops and the notification
// goes away, whatever the outcome of the downloads was.
//
// iOS: no-op. Downloads already continue in the background there via
// URLSession, and iOS has no ongoing progress notifications.
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'l10n/app_localizations.dart';

class DownloadNotificationItem {
  final String title;
  final double progress; // 0.0 – 1.0
  const DownloadNotificationItem(this.title, this.progress);
}

class DownloadNotification {
  static const _id = 48120;
  static const _channelId = 'de.ueen.antpod.channel.downloads';
  static const _maxLines = 6;

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _shown = false;
  static String? _lastSignature;
  // Serializes plugin calls so a late update can never land after clear()
  // and resurrect the (ongoing, non-dismissable) notification.
  static Future<void> _queue = Future.value();

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static Future<void> _enqueue(Future<void> Function() op) {
    return _queue = _queue.then((_) => op()).catchError((Object e) {
      debugPrint('[DownloadNotification] $e');
    });
  }

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );
    _initialized = true;
  }

  /// Show or update the notification for [items]; clears it when empty.
  static Future<void> update(List<DownloadNotificationItem> items) {
    if (!_supported) return Future.value();
    if (items.isEmpty) return clear();
    return _enqueue(() async {
      await _ensureInitialized();
      final l10n = await _l10n();
      final pct = NumberFormat.percentPattern(l10n.localeName);
      String fmt(double p) => pct.format(p.clamp(0.0, 1.0));

      final avg = items.fold<double>(0, (s, i) => s + i.progress) / items.length;
      final progress = (avg.clamp(0.0, 1.0) * 100).round();
      final indeterminate = items.every((i) => i.progress <= 0);

      final String title;
      final String body;
      StyleInformation? style;
      if (items.length == 1) {
        title = items.first.title;
        body = fmt(items.first.progress);
      } else {
        title = l10n.downloadingEpisodes(items.length);
        final lines = [for (final i in items) '${fmt(i.progress)}  ${i.title}'];
        body = lines.join(' · ');
        final extra = lines.length - _maxLines;
        style = InboxStyleInformation(
          lines.take(_maxLines).toList(),
          contentTitle: title,
          summaryText: extra > 0 ? '+$extra' : null,
        );
      }

      // Skip identical updates (the provider polls every second).
      final signature = '$title|$body|$progress|$indeterminate';
      if (_shown && signature == _lastSignature) return;
      _lastSignature = signature;

      final details = AndroidNotificationDetails(
        _channelId,
        l10n.downloadNotificationChannel,
        importance: Importance.low,
        priority: Priority.low,
        icon: 'ic_download',
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        silent: true,
        showWhen: false,
        channelShowBadge: false,
        showProgress: true,
        maxProgress: 100,
        progress: progress,
        indeterminate: indeterminate,
        category: AndroidNotificationCategory.progress,
        styleInformation: style,
      );

      if (!_shown) {
        _shown = true;
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        try {
          await android?.startForegroundService(
            id: _id,
            title: title,
            body: body,
            notificationDetails: details,
            // Not sticky: a restarted service would have no Dart side to
            // update or stop it, and the plugin can't handle a null intent.
            startType: AndroidServiceStartType.startNotSticky,
            foregroundServiceTypes: {AndroidServiceForegroundType.foregroundServiceTypeDataSync},
          );
          return;
        } catch (e) {
          // Android 12+ refuses to start a foreground service while the app
          // is in the background (e.g. WiFi-queue downloads on reconnect).
          // Downloads still run via WorkManager; fall back to a plain
          // ongoing notification so progress stays visible.
          debugPrint('[DownloadNotification] foreground service refused: $e');
        }
      }
      // Same id: updates the foreground service's notification in place.
      await _plugin.show(id: _id, title: title, body: body,
          notificationDetails: NotificationDetails(android: details));
    });
  }

  /// Remove the notification and stop the foreground service.
  static Future<void> clear() {
    if (!_supported) return Future.value();
    return _enqueue(() async {
      if (!_shown) return;
      _shown = false;
      _lastSignature = null;
      await _ensureInitialized();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      try { await android?.stopForegroundService(); } catch (_) {}
      await _plugin.cancel(id: _id);
    });
  }

  /// The language picked in the settings, else the phone's, else English.
  static Future<AppLocalizations> _l10n() async {
    final prefs = await SharedPreferences.getInstance();
    final language = prefs.getString(AppSettings.keyLanguage) ??
        PlatformDispatcher.instance.locale.languageCode;
    final supported = AppLocalizations.supportedLocales
        .any((l) => l.languageCode == language);
    return lookupAppLocalizations(
        supported ? Locale(language) : const Locale('en'));
  }
}
