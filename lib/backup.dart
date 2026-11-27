// lib/backup.dart
//
// Moving to a new phone. Two kinds of file:
//
//   Backup  JSON: the subscriptions, every episode with a play state (a
//           position, played, a favourite) and the settings. Importing merges
//           it into what's there: of two play states, the one played last
//           wins; a favourite on either side stays one.
//   OPML    the subscriptions alone, the list every podcast app reads.
//
// Downloads stay behind; they're quick to get again.
//
// Podcasts are named by feed URL and episodes by feed and audio URL next to
// their guid, the way podcast sync services name them (gpodder.net, and
// Nextcloud's GPodder Sync, episode actions), so a later sync can send the
// same records.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import 'app_database.dart';
import 'feed_sync.dart';
import 'podcast_service.dart';

/// What an import did: feeds newly subscribed, how many of them didn't load
/// (subscribed all the same, the next refresh tries again), and episodes
/// whose play state or favourite was taken over.
typedef ImportReport = ({int subscribed, int failed, int episodes});

/// Subscribes to one feed, true when it loaded: [FeedSync.subscribeUrl]
/// unless a test passes its own.
typedef Subscriber = Future<bool> Function(PodcastResult feed);

class Backup {
  Backup._();

  static const format = 'antpod-backup';
  static const version = 1;

  static String fileName(DateTime now) => 'antpod-backup-${_day(now)}.json';

  /// The backup of [db], with the values of [settingKeys] that are set.
  static Future<String> export(
    AppDatabase db,
    SharedPreferences prefs, {
    required List<String> settingKeys,
  }) async {
    final episodes = await db.getEpisodesWithState();
    final podcasts = {for (final p in await db.getAllPodcasts()) p.id: p};
    // The temp feeds behind played episodes (search, shared links) too.
    for (final id in {for (final e in episodes) e.podcastId}) {
      if (podcasts.containsKey(id)) continue;
      if (await db.getPodcast(id) case final p?) podcasts[id] = p;
    }
    return const JsonEncoder.withIndent(' ').convert({
      'format': format,
      'version': version,
      'exportedAt': _time(DateTime.now()),
      'podcasts': [
        for (final p in podcasts.values)
          {
            'feedUrl': p.feedUrl,
            'title': p.title,
            'author': p.author,
            'description': p.description,
            'imageUrl': p.imageUrl,
            'subscribed': p.isSubscribed,
            'syncPaused': p.syncPaused,
          },
      ],
      'episodes': [
        for (final e in episodes)
          {
            'id': AppDatabase.guidOf(e.id),
            'feedUrl': podcasts[e.podcastId]?.feedUrl ?? e.podcastId,
            'audioUrl': e.audioUrl,
            'title': e.title,
            'podcastTitle': e.podcastTitle,
            'podcastImageUrl': e.podcastImageUrl,
            if (e.imageUrl != null) 'imageUrl': e.imageUrl,
            'publishDate': _time(e.publishDate),
            'durationSeconds': e.durationSeconds,
            'positionMs': e.lastPositionMs,
            'played': e.isFinished,
            'favorite': e.isFavorite,
            if (e.lastPlayed != null) 'lastPlayed': _time(e.lastPlayed!),
            'description': e.description,
          },
      ],
      'settings': {
        for (final k in settingKeys)
          if (prefs.get(k) case final v?) k: v,
      },
    });
  }

  /// Merges the backup in [text] into [db] and takes on its settings (those
  /// of [settingKeys]). Throws a [FormatException] when [text] isn't a
  /// backup, or one of a newer version.
  static Future<ImportReport> import(
    AppDatabase db,
    SharedPreferences prefs,
    String text, {
    required List<String> settingKeys,
    Subscriber? subscribe,
    void Function(int done, int total)? onProgress,
  }) async {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const FormatException('not a backup');
    }
    if (json is! Map || json['format'] != format) {
      throw const FormatException('not a backup');
    }
    if (_int(json['version']) > version) {
      throw const FormatException('a newer version');
    }

    final toSubscribe = <PodcastResult>[];
    final paused = <String>[];
    for (final p in _maps(json['podcasts'])) {
      final feedUrl = _str(p['feedUrl']);
      if (feedUrl.isEmpty || await db.findSubscribed(feedUrl) != null) continue;
      final result = PodcastResult(
        id: feedUrl,
        title: _str(p['title']),
        author: _str(p['author']),
        description: _str(p['description']),
        imageUrl: _str(p['imageUrl']),
        feedUrl: feedUrl,
      );
      if (p['subscribed'] == false) {
        await db.insertTempPodcast(result.toCompanion());
      } else {
        toSubscribe.add(result);
        if (p['syncPaused'] == true) paused.add(feedUrl);
      }
    }
    final failed = await FeedSync.subscribeAll(db, toSubscribe,
        subscribe: subscribe, onProgress: onProgress);
    for (final feedUrl in paused) {
      if (await db.findSubscribed(feedUrl) case final pod?) {
        await db.setPodcastSyncPaused(pod.id, true);
      }
    }

    var merged = 0;
    for (final e in _maps(json['episodes'])) {
      if (await _mergeEpisode(db, e)) merged++;
    }

    if (json['settings'] case final Map settings) {
      for (final k in settingKeys) {
        switch (settings[k]) {
          case final bool v: await prefs.setBool(k, v);
          case final int v: await prefs.setInt(k, v);
          case final double v: await prefs.setDouble(k, v);
          case final String v: await prefs.setString(k, v);
        }
      }
    }
    return (subscribed: toSubscribe.length, failed: failed, episodes: merged);
  }

  /// Takes on [e]'s play state when it's the newer one, and its favourite.
  /// An episode gone from its feed is put back from what the backup says.
  /// True when something changed.
  static Future<bool> _mergeEpisode(AppDatabase db, Map e) async {
    final id = _str(e['id']);
    if (id.isEmpty) return false;
    final feedUrl = _str(e['feedUrl']);
    final audioUrl = _str(e['audioUrl']);
    final pod = await db.findSubscribed(feedUrl) ?? await db.getPodcast(feedUrl);
    final podcastId = pod?.id ?? feedUrl;

    var match = await db.episodeOf(podcastId, id);
    if (match == null && audioUrl.isNotEmpty) {
      match = await db.findEpisodeByAudio(podcastId, audioUrl);
    }
    if (match == null) {
      final row = EpisodesCompanion(
        id: Value(id),
        podcastId: Value(podcastId),
        podcastTitle: Value(_str(e['podcastTitle'], or: pod?.title ?? '')),
        podcastImageUrl: Value(_str(e['podcastImageUrl'], or: pod?.imageUrl ?? '')),
        imageUrl: Value(_str(e['imageUrl']).isEmpty ? null : _str(e['imageUrl'])),
        title: Value(_str(e['title'])),
        description: Value(_str(e['description'])),
        audioUrl: Value(audioUrl),
        durationSeconds: Value(_int(e['durationSeconds'])),
        publishDate: Value(_date(e['publishDate']) ?? DateTime.now()),
      );
      final ids = pod?.isSubscribed ?? false
          ? await db.insertEpisodes([row.copyWith(isSubscribed: const Value(true))])
          : await db.insertTempEpisodes([row]);
      match = await db.getEpisode(ids.single);
      if (match == null) return false;
    }

    final positionMs = _int(e['positionMs']);
    final played = e['played'] == true;
    final lastPlayed = _date(e['lastPlayed']);
    final untouched = match.lastPositionMs == 0 && !match.isFinished;
    final newer = (positionMs > 0 || played) &&
        (lastPlayed == null
            ? untouched
            : match.lastPlayed == null || lastPlayed.isAfter(match.lastPlayed!));
    if (newer) {
      await db.restorePlayState(match.id,
          positionMs: positionMs,
          finished: played,
          lastPlayed: lastPlayed ?? match.lastPlayed,
          durationSeconds: _int(e['durationSeconds']));
    }
    final favorite = e['favorite'] == true && !match.isFavorite;
    if (favorite) await db.setFavorite(match.id, true);
    return newer || favorite;
  }
}

/// A feed listed in an OPML file.
typedef OpmlFeed = ({String url, String title});

class Opml {
  Opml._();

  static String fileName(DateTime now) => 'antpod-subscriptions-${_day(now)}.opml';

  /// OPML 2.0 listing [podcasts].
  static String build(List<Podcast> podcasts, {DateTime? now}) {
    final b = XmlBuilder()..processing('xml', 'version="1.0" encoding="UTF-8"');
    b.element('opml', attributes: {'version': '2.0'}, nest: () {
      b.element('head', nest: () {
        b.element('title', nest: 'AntPod subscriptions');
        b.element('dateCreated', nest: _rfc822((now ?? DateTime.now()).toUtc()));
      });
      b.element('body', nest: () {
        for (final p in podcasts) {
          b.element('outline', attributes: {
            'type': 'rss',
            'text': p.title,
            'title': p.title,
            'xmlUrl': p.feedUrl,
            if (p.website?.isNotEmpty ?? false) 'htmlUrl': p.website!,
          });
        }
      });
    });
    return b.buildDocument().toXmlString(pretty: true, indent: '  ');
  }

  /// Every feed in an OPML file, nested in folders or not, once each.
  /// Throws a [FormatException] when [text] isn't OPML.
  static List<OpmlFeed> parse(String text) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(text.trimLeft());
    } on XmlException {
      throw const FormatException('not OPML');
    }
    if (doc.rootElement.name.local.toLowerCase() != 'opml') {
      throw const FormatException('not OPML');
    }
    final seen = <String>{};
    final feeds = <OpmlFeed>[];
    for (final o in doc.findAllElements('outline')) {
      final url = _feedUrl(_attr(o, 'xmlurl') ?? '');
      if (url == null || !seen.add(AppDatabase.normFeed(url))) continue;
      final title = _attr(o, 'title') ?? _attr(o, 'text') ?? '';
      feeds.add((url: url, title: title.isNotEmpty ? title : Uri.parse(url).host));
    }
    return feeds;
  }

  /// Subscribes to the feeds in [text] not subscribed yet. Throws a
  /// [FormatException] when [text] isn't OPML.
  static Future<ImportReport> import(
    AppDatabase db,
    String text, {
    Subscriber? subscribe,
    void Function(int done, int total)? onProgress,
  }) async {
    final fresh = <PodcastResult>[];
    for (final f in parse(text)) {
      if (await db.findSubscribed(f.url) == null) {
        fresh.add(PodcastResult.feed(f.url, title: f.title));
      }
    }
    final failed = await FeedSync.subscribeAll(db, fresh,
        subscribe: subscribe, onProgress: onProgress);
    return (subscribed: fresh.length, failed: failed, episodes: 0);
  }

  static String? _attr(XmlElement e, String lowerName) => e.attributes
      .where((a) => a.name.local.toLowerCase() == lowerName)
      .firstOrNull
      ?.value
      .trim();

  /// [url] as a web address: "feed:", "itpc:" and "pcast:" links lead to
  /// the same feed over https; anything else but http(s) is no feed.
  static String? _feedUrl(String url) {
    final u = url
        .replaceFirst(RegExp(r'^feed:(?=https?://)', caseSensitive: false), '')
        .replaceFirst(
            RegExp(r'^(?:feed|itpc|pcast|podcast)://', caseSensitive: false), 'https://');
    final uri = Uri.tryParse(u);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty
        ? u
        : null;
  }

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _rfc822(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${_days[t.weekday - 1]}, ${two(t.day)} ${_months[t.month - 1]} ${t.year} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)} GMT';
  }
}

String _day(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

String _time(DateTime t) => t.toUtc().toIso8601String();

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

String _str(Object? v, {String or = ''}) =>
    v is String && v.isNotEmpty ? v : or;

int _int(Object? v) => v is num ? v.toInt() : 0;

Iterable<Map> _maps(Object? v) => v is List ? v.whereType<Map>() : const [];
