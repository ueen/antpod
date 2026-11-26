// lib/podcast_service.dart
//
// Podcast directories and feeds.
//
//   PodcastIndex /search/byterm        → podcast search
//   PodcastIndex /podcasts/trending    → trending fallback (30-day window)
//   PodcastIndex /episodes/byfeedurl   → real RSS GUIDs for episode search hits
//   Apple charts + lookup              → trending by country
//   Apple search (podcastEpisode)      → episode search
//   RSS (podcast_search)               → feeds themselves, parsed off-isolate
//                                        (plus their Podlove chapters)

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:podcast_search/podcast_search.dart' as ps;
import 'app_database.dart';
import 'chapters.dart';

// ── Zugangsdaten ──────────────────────────────────────────────────────────────

const _apiKey    = 'WVABNRFZXMR56UKS7488';
const _apiSecret = 'Yrb2fXKRtwFRkzcj4XNZBKmBhVbg8Uz5ZvMj5Prd';

const _baseUrl = 'https://api.podcastindex.org/api/1.0';
const _userAgent = 'AntPod/1.0';

// ── Auth-Header ───────────────────────────────────────────────────────────────

Map<String, String> _authHeaders() {
  final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  final hash = sha1
      .convert(utf8.encode('$_apiKey$_apiSecret$ts'))
      .toString();
  return {
    'User-Agent': _userAgent,
    'X-Auth-Key': _apiKey,
    'X-Auth-Date': ts,
    'Authorization': hash,
  };
}

// ── Search result model ───────────────────────────────────────────────────────

class PodcastResult {
  final String id;
  final String title;
  final String author;
  final String description;
  final String imageUrl;
  final String feedUrl;
  final List<String> categories;

  const PodcastResult({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.imageUrl,
    required this.feedUrl,
    this.categories = const [],
  });

  /// A feed known by its URL and whatever a link or an episode tells about it.
  const PodcastResult.feed(this.feedUrl, {this.title = '', this.imageUrl = ''})
      : id = feedUrl, author = '', description = '', categories = const [];

  PodcastResult.fromPodcast(Podcast p)
      : this(id: p.feedUrl, title: p.title, author: p.author,
            description: p.description, imageUrl: p.imageUrl, feedUrl: p.feedUrl);

  /// The podcast an episode belongs to (its podcastId is the feed URL).
  PodcastResult.fromEpisode(Episode e)
      : this.feed(e.podcastId, title: e.podcastTitle, imageUrl: e.podcastImageUrl);

  PodcastResult copyWith({
    String? id, String? title, String? description, String? imageUrl, String? feedUrl,
  }) =>
      PodcastResult(
        id: id ?? this.id,
        title: title ?? this.title,
        author: author,
        description: description ?? this.description,
        imageUrl: imageUrl ?? this.imageUrl,
        feedUrl: feedUrl ?? this.feedUrl,
        categories: categories,
      );

  factory PodcastResult.fromAppleJson(Map<String, dynamic> j) {
    final genre = j['primaryGenreName'] as String?;
    return PodcastResult(
      id: j['collectionId']?.toString() ?? '',
      title: j['collectionName'] ?? '',
      author: j['artistName'] ?? '',
      description: '',
      imageUrl: j['artworkUrl600'] ?? j['artworkUrl100'] ?? '',
      feedUrl: j['feedUrl'] ?? '',
      categories: genre != null ? [genre] : [],
    );
  }

  factory PodcastResult.fromJson(Map<String, dynamic> j) {
    // categories: Map<String,String> {"1":"Arts","2":"Music"} or null
    final cats = <String>[];
    final rawCats = j['categories'];
    if (rawCats is Map) {
      cats.addAll(rawCats.values.map((v) => v.toString()));
    }
    return PodcastResult(
      id: j['id']?.toString() ?? '',
      title: j['title'] ?? '',
      author: j['author'] ?? '',
      description: j['description'] ?? '',
      imageUrl: j['artwork'] ?? j['image'] ?? '',
      feedUrl: j['url'] ?? '',
      categories: cats,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'description': description,
    'artwork': imageUrl,
    'url': feedUrl,
    'categories': {for (int i = 0; i < categories.length; i++) '$i': categories[i]},
  };

  PodcastsCompanion toCompanion() => PodcastsCompanion(
        id: Value(feedUrl),
        title: Value(title),
        description: Value(description),
        imageUrl: Value(imageUrl),
        feedUrl: Value(feedUrl),
        author: Value(author),
        isSubscribed: const Value(true),
      );
}

// ── Service ───────────────────────────────────────────────────────────────────

/// A parsed RSS feed: podcast metadata plus its episodes as DB companions.
typedef FeedData = ({ps.Podcast podcast, List<EpisodesCompanion> episodes});

class PodcastService {
  static const _apiTimeout = Duration(seconds: 15);

  /// GET with a timeout: a stalled connection (captive portal, dead mobile
  /// link) would otherwise hold a spinner until the OS gives up, minutes on.
  static Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) =>
      http.get(uri, headers: headers).timeout(_apiTimeout);

  /// The body as a JSON object. JSON is UTF-8 whatever the content type says.
  static Map<String, dynamic> _json(http.Response res) =>
      jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true))
          as Map<String, dynamic>;

  // ── Search ─────────────────────────────────────────────────────────────────

  static Future<List<PodcastResult>> search(String query, {int offset = 0}) async {
    try {
      final uri = Uri.parse('$_baseUrl/search/byterm')
          .replace(queryParameters: {'q': query, 'max': '20', 'offset': '$offset'});
      final res = await _get(uri, headers: _authHeaders());
      if (res.statusCode != 200) return [];
      final feeds = _json(res)['feeds'] as List? ?? [];
      return feeds
          .map((f) => PodcastResult.fromJson(f as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[podcast] search error: $e');
      return [];
    }
  }

  /// Episode search: Apple finds by keyword, PI resolves real RSS GUIDs.
  /// If a feed is not indexed by PI the Apple episode is kept as a fallback
  /// (id: 'apple-{trackId}'); migrateAppleEpisodeStubs cleans those up when
  /// the feed is opened.
  static Future<List<Episode>> searchEpisodes(String query, {String country = 'us'}) async {
    final appleEps = await appleEpisodeSearch(query, country: country);
    if (appleEps.isEmpty) return [];

    // Fetch PI episodes for every unique feedUrl in parallel to resolve GUIDs.
    final uniqueFeeds = appleEps.map((e) => e.podcastId).toSet();
    final piByFeed = <String, List<Map<String, dynamic>>>{};
    await Future.wait(uniqueFeeds.map((feedUrl) async {
      try {
        final uri = Uri.parse('$_baseUrl/episodes/byfeedurl')
            .replace(queryParameters: {'url': feedUrl, 'max': '30'});
        final res = await _get(uri, headers: _authHeaders());
        if (res.statusCode == 200) {
          final items = _json(res)['items'] as List? ?? [];
          piByFeed[feedUrl] = items.cast();
        }
      } catch (e) { debugPrint('[podcast] PI episodes error: $e'); }
    }));

    // For each Apple episode, swap in the PI GUID + enclosureUrl if matched.
    return appleEps.map((ep) {
      final piItems = piByFeed[ep.podcastId] ?? [];
      final appleTitle = ep.title.trim().toLowerCase();
      final match = piItems.where(
        (m) => (m['title'] as String? ?? '').trim().toLowerCase() == appleTitle,
      ).firstOrNull;
      if (match == null) return ep; // iTunes-only podcast, keep Apple data
      final guid  = (match['guid']         as String? ?? '').trim();
      final audio = (match['enclosureUrl'] as String? ?? '').trim();
      if (guid.isEmpty || audio.isEmpty) return ep;
      return ep.copyWith(id: guid, audioUrl: audio,
          chaptersUrl: Value(match['chaptersUrl'] as String?));
    }).toList();
  }

  static Future<List<Episode>> appleEpisodeSearch(String query, {String country = 'us'}) async {
    try {
      final uri = Uri.parse('https://itunes.apple.com/search').replace(
        queryParameters: {'term': query, 'media': 'podcast', 'entity': 'podcastEpisode',
                          'limit': '10', 'country': country},
      );
      final res = await _get(uri);
      if (res.statusCode != 200) return [];
      final results = _json(res)['results'] as List? ?? [];
      final episodes = <Episode>[];
      for (final r in results) {
        final audioUrl = r['previewUrl'] as String? ?? '';
        final feedUrl  = r['feedUrl']    as String? ?? '';
        if (audioUrl.isEmpty || feedUrl.isEmpty) continue;
        final millis = r['trackTimeMillis'] as int? ?? 0;
        DateTime publishDate;
        try {
          publishDate = DateTime.parse(r['releaseDate'] as String? ?? '');
        } catch (_) {
          publishDate = DateTime.now();
        }
        episodes.add(Episode(
          id:                    'apple-${r['trackId']}',
          podcastId:             feedUrl,
          podcastTitle:          r['collectionName'] ?? '',
          podcastImageUrl:       r['artworkUrl600'] ?? r['artworkUrl160'] ?? '',
          title:                 r['trackName'] ?? '',
          description:           r['description'] ?? r['shortDescription'] ?? '',
          audioUrl:              audioUrl,
          durationSeconds:       millis ~/ 1000,
          publishDate:           publishDate,
          isDownloaded:          false,
          localPath:             null,
          downloadTaskId:        null,
          lastPositionMs:        0,
          playbackPositionSeconds: 0,
          isFinished:            false,
          isSubscribed:          false,
          chaptersUrl:           null,
          lastPlayed:            null,
          markedForDownload:     false,
        ));
      }
      return episodes;
    } catch (e) {
      debugPrint('[podcast] episode search error: $e');
      return [];
    }
  }

  // Apple Charts top podcasts for a country, resolved to feedUrl via iTunes lookup.
  static Future<List<PodcastResult>> appleCharts(String country, {int limit = 20}) async {
    try {
      // Use the canonical URL directly (the marketing tools URL issues a 301 redirect)
      final chartsUri = Uri.parse(
        'https://rss.marketingtools.apple.com/api/v2/${country.toLowerCase()}/podcasts/top/$limit/podcasts.json',
      );
      final chartsRes = await _get(chartsUri);
      if (chartsRes.statusCode != 200) return [];
      final feed = _json(chartsRes)['feed'] as Map<String, dynamic>?;
      final results = feed?['results'] as List? ?? [];
      if (results.isEmpty) return [];
      final ids = results.map((r) => r['id'].toString()).join(',');
      final lookupUri = Uri.parse('https://itunes.apple.com/lookup')
          .replace(queryParameters: {'id': ids, 'entity': 'podcast'});
      final lookupRes = await _get(lookupUri);
      if (lookupRes.statusCode != 200) return [];
      final lookupResults = _json(lookupRes)['results'] as List? ?? [];
      // Preserve chart order: build a map from id → lookup result, then re-order.
      final byId = <String, Map<String, dynamic>>{};
      for (final r in lookupResults) {
        final id = r['collectionId']?.toString() ?? '';
        if (id.isNotEmpty) byId[id] = r as Map<String, dynamic>;
      }
      return results
          .map((r) => byId[r['id'].toString()])
          .whereType<Map<String, dynamic>>()
          .map(PodcastResult.fromAppleJson)
          .where((p) => p.feedUrl.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[podcast] Apple charts error: $e');
      return [];
    }
  }

  // ── Trending ───────────────────────────────────────────────────────────────
  // PodcastIndex /podcasts/trending — 30-day window for consistent popularity
  // (not viral spikes). Regionalized via `lang`: passing "de,en" returns
  // primarily German podcasts with English ones filling the remainder.

  static Future<List<PodcastResult>> trending({
    int max = 10,
    String lang = 'en',
  }) async {
    final since = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 2592000;
    final params = <String, String>{
      'max': '$max',
      'lang': lang,
      'since': '$since', // 30-day window
    };

    final uri =
        Uri.parse('$_baseUrl/podcasts/trending').replace(queryParameters: params);
    final res = await _get(uri, headers: _authHeaders());
    if (res.statusCode != 200) {
      throw Exception('API ${res.statusCode}: ${res.reasonPhrase}');
    }
    final feeds = _json(res)['feeds'] as List? ?? [];
    return feeds
        .take(max)
        .map((f) => PodcastResult.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  // ── RSS feeds ─────────────────────────────────────────────────────────────

  /// The feed at [feedUrl], parsed by podcast_search, which leaves out
  /// Podlove Simple Chapters: so the XML is fetched here and those read from
  /// it too (chapters.dart).
  static Future<FeedData?> loadFeed(
    String feedUrl,
  ) async {
    try {
      final tempDir = await getTemporaryDirectory()
          .then((d) => d.path, onError: (_) => Directory.systemTemp.path);
      // Run HTTP fetch + XML parse on a background isolate so the main thread
      // is never blocked by RssFeed.parse() on large feeds.
      return await Isolate.run(() async {
        final xml = await _fetchFeed(feedUrl);
        if (xml == null) return null;
        // podcast_search parses from a string only via a file.
        final file = File('$tempDir/feed-${feedUrl.hashCode}-'
            '${DateTime.now().microsecondsSinceEpoch}.xml');
        final ps.Podcast podcast;
        try {
          await file.writeAsString(xml);
          podcast = await ps.Feed.loadFeedFile(file: file.path);
        } finally {
          file.delete().ignore();
        }
        // One episode per item, in order, so they pair up by position.
        List<String?>? podlove;
        if (xml.contains('<psc:chapter')) {
          final items = _item.allMatches(xml).toList();
          if (items.length == podcast.episodes.length) {
            podlove = [for (final m in items) podloveChaptersUri(m.group(0)!)];
          }
        }
        var index = 0;
        final episodes = podcast.episodes.map((ep) {
          final i = index++;
          final pcUrl = ep.chapters?.url;
          final chapUrl =
              pcUrl != null && pcUrl.isNotEmpty ? pcUrl : podlove?[i];
          return EpisodesCompanion(
            id: Value(ep.guid.isNotEmpty ? ep.guid : '${feedUrl}_${ep.title}'),
            podcastId: Value(feedUrl),
            podcastTitle: Value(podcast.title ?? ''),
            podcastImageUrl: Value(podcast.image ?? ''),
            title: Value(ep.title),
            description: Value(ep.description),
            audioUrl: Value(ep.contentUrl ?? ''),
            durationSeconds: Value((ep.duration ?? Duration.zero).inSeconds),
            publishDate: Value(ep.publicationDate ?? DateTime.now()),
            chaptersUrl: Value(chapUrl),
          );
        }).toList();
        return (podcast: podcast, episodes: episodes);
      });
    } catch (e) {
      debugPrint('[podcast] feed load error: $e');
      return null;
    }
  }

  static final _item = RegExp(r'<item[\s>][\s\S]*?</item>');

  /// The feed's XML, or null if the server didn't send it.
  static Future<String?> _fetchFeed(String url) async {
    const timeout = Duration(seconds: 20);
    final client = http.Client();
    try {
      final res = await client
          .send(http.Request('GET', Uri.parse(url))
            ..headers['User-Agent'] = _userAgent)
          .timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        res.stream.listen(null).cancel().ignore();
        return null;
      }
      final bytes = await http.ByteStream(res.stream.timeout(timeout)).toBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      client.close();
    }
  }
}
