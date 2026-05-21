// lib/podcast_service.dart
//
// Ausschließlich PodcastIndex.org – kein iTunes.
//
// Endpoints genutzt:
//   /api/1.0/search/byterm        → Suche
//   /api/1.0/podcasts/trending    → Trending (30-day window)
//   /api/1.0/podcasts/byfeedurl   → Empfehlungen: Kategorien der Abos ermitteln
//   /api/1.0/search/byterm        → Empfehlungen: Suche nach Kategoriebegriffen

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;
import 'package:podcast_search/podcast_search.dart' as ps;
import 'app_database.dart';

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

// ── Hilfsmodell für Suchergebnisse ────────────────────────────────────────────

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
    // categories: Map<String,String> {"1":"Arts","2":"Music"} oder null
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

  PodcastsCompanion toCompanion() => PodcastsCompanion(
        id: Value(feedUrl),
        title: Value(title),
        description: Value(description),
        imageUrl: Value(imageUrl),
        feedUrl: Value(feedUrl),
        author: Value(author),
      );
}

// ── Service ───────────────────────────────────────────────────────────────────

class PodcastService {
  // ── Suche ──────────────────────────────────────────────────────────────────

  static Future<List<PodcastResult>> search(String query, {int offset = 0}) async {
    try {
      final uri = Uri.parse('$_baseUrl/search/byterm')
          .replace(queryParameters: {'q': query, 'max': '20', 'offset': '$offset'});
      final res = await http.get(uri, headers: _authHeaders());
      if (res.statusCode != 200) return [];
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final feeds = json['feeds'] as List? ?? [];
      return feeds
          .map((f) => PodcastResult.fromJson(f as Map<String, dynamic>))
          .toList();
    } catch (_) {
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
        final res = await http.get(uri, headers: _authHeaders());
        if (res.statusCode == 200) {
          final items = (jsonDecode(res.body) as Map<String, dynamic>)['items'] as List? ?? [];
          piByFeed[feedUrl] = items.cast();
        }
      } catch (_) {}
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
      final res = await http.get(uri);
      if (res.statusCode != 200) return [];
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final results = json['results'] as List? ?? [];
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
    } catch (_) {
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
      final chartsRes = await http.get(chartsUri);
      if (chartsRes.statusCode != 200) return [];
      final feed = (jsonDecode(chartsRes.body) as Map<String, dynamic>)['feed']
          as Map<String, dynamic>?;
      final results = feed?['results'] as List? ?? [];
      if (results.isEmpty) return [];
      final ids = results.map((r) => r['id'].toString()).join(',');
      final lookupUri = Uri.parse('https://itunes.apple.com/lookup')
          .replace(queryParameters: {'id': ids, 'entity': 'podcast'});
      final lookupRes = await http.get(lookupUri);
      if (lookupRes.statusCode != 200) return [];
      final lookupResults =
          (jsonDecode(lookupRes.body) as Map<String, dynamic>)['results'] as List? ?? [];
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
    } catch (_) {
      return [];
    }
  }

  static Future<List<PodcastResult>> appleSearch(String query, {String country = 'us'}) async {
    try {
      final uri = Uri.parse('https://itunes.apple.com/search').replace(
        queryParameters: {'term': query, 'media': 'podcast', 'entity': 'podcast',
                          'limit': '20', 'country': country},
      );
      final res = await http.get(uri);
      if (res.statusCode != 200) return [];
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final results = json['results'] as List? ?? [];
      return results
          .map((r) => PodcastResult.fromAppleJson(r as Map<String, dynamic>))
          .where((p) => p.feedUrl.isNotEmpty)
          .toList();
    } catch (_) {
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
    String? cat,
  }) async {
    final since = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 2592000;
    final params = <String, String>{
      'max': '$max',
      'lang': lang,
      'since': '$since', // 30-day window
    };
    if (cat != null && cat.isNotEmpty) params['cat'] = cat;

    final uri =
        Uri.parse('$_baseUrl/podcasts/trending').replace(queryParameters: params);
    final res = await http.get(uri, headers: _authHeaders());
    if (res.statusCode != 200) {
      throw Exception('API ${res.statusCode}: ${res.reasonPhrase}');
    }
    final feeds =
        (jsonDecode(res.body) as Map<String, dynamic>)['feeds'] as List? ?? [];
    return feeds
        .take(max)
        .map((f) => PodcastResult.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  // ── Recommendations ───────────────────────────────────────────────────────
  // Two-pass strategy:
  //   Pass 1 — trending-in-category: look up categories for all subscriptions,
  //             fetch trending filtered by the top 3 matching categories (7-day
  //             window), deduplicate against subscriptions.
  //   Pass 2 — search-by-term: for each top category, search by keyword so
  //             well-known topical podcasts surface even if not trending right now.
  //   Results from both passes are merged, deduped, and trimmed to `max`.
  //   Fallback: broad trending excluding subscriptions.

  static Future<List<PodcastResult>> recommendations({
    required List<Podcast> subscribed,
    int max = 10,
    String lang = 'en',
  }) async {
    if (subscribed.isEmpty) return trending(max: max, lang: lang);

    final subscribedFeedUrls = subscribed.map((p) => p.feedUrl).toSet();
    final seen = <String>{...subscribedFeedUrls};
    final results = <PodcastResult>[];

    void add(PodcastResult r) {
      if (seen.add(r.feedUrl) && r.feedUrl.isNotEmpty) results.add(r);
    }

    // Step 1: collect categories from all subscribed podcasts in parallel.
    final categoryCount = <String, int>{};
    await Future.wait(subscribed.map((podcast) async {
      try {
        final uri = Uri.parse('$_baseUrl/podcasts/byfeedurl')
            .replace(queryParameters: {'url': podcast.feedUrl});
        final res = await http.get(uri, headers: _authHeaders());
        if (res.statusCode == 200) {
          final feed = (jsonDecode(res.body) as Map<String, dynamic>)['feed']
              as Map<String, dynamic>?;
          final cats = feed?['categories'];
          if (cats is Map) {
            for (final v in cats.values) {
              final cat = v.toString();
              categoryCount[cat] = (categoryCount[cat] ?? 0) + 1;
            }
          }
        }
      } catch (_) {}
    }));

    // Top 3 categories by subscription overlap.
    final topCats = (categoryCount.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(3)
        .map((e) => e.key)
        .toList();

    // Step 2a — trending filtered by the top categories (7-day window).
    if (topCats.isNotEmpty) {
      try {
        final trendCat = await trending(max: max * 3, lang: lang, cat: topCats.join(','));
        for (final r in trendCat) { add(r); }
      } catch (_) {}
    }

    // Step 2b — keyword search per category: surfaces well-known shows even if
    // they aren't trending this week but are the go-to for that topic.
    await Future.wait(topCats.take(2).map((cat) async {
      try {
        final uri = Uri.parse('$_baseUrl/search/byterm')
            .replace(queryParameters: {'q': cat, 'max': '10', 'lang': lang});
        final res = await http.get(uri, headers: _authHeaders());
        if (res.statusCode == 200) {
          final feeds = (jsonDecode(res.body) as Map<String, dynamic>)['feeds']
              as List? ?? [];
          for (final f in feeds) {
            add(PodcastResult.fromJson(f as Map<String, dynamic>));
          }
        }
      } catch (_) {}
    }));

    if (results.length >= 3) return results.take(max).toList();

    // Fallback: broad trending, excluding subscriptions.
    try {
      final broad = await trending(max: max * 3, lang: lang);
      for (final r in broad) { add(r); }
    } catch (_) {}
    return results.take(max).toList();
  }

  // ── RSS-Feed laden (bleibt via podcast_search) ────────────────────────────

  static Future<({ps.Podcast podcast, List<EpisodesCompanion> episodes})?> loadFeed(
    String feedUrl,
  ) async {
    try {
      final podcast = await ps.Feed.loadFeed(url: feedUrl);
      final episodes = podcast.episodes.map((ep) {
        final chapUrl = ep.chapters?.url;
        return EpisodesCompanion(
          id: Value(ep.guid.isNotEmpty ? ep.guid : '${feedUrl}_${ep.title}'),
          podcastId: Value(feedUrl),
          podcastTitle: Value(podcast.title ?? ''),
          podcastImageUrl: Value(podcast.image ?? ''),
          title: Value(ep.title),
          description: Value(ep.description),
          audioUrl: Value(ep.contentUrl ?? ''),
          durationSeconds:
              Value((ep.duration ?? Duration.zero).inSeconds),
          publishDate: Value(ep.publicationDate ?? DateTime.now()),
          chaptersUrl: Value(chapUrl != null && chapUrl.isNotEmpty ? chapUrl : null),
        );
      }).toList();
      return (podcast: podcast, episodes: episodes);
    } catch (_) {
      return null;
    }
  }
}
