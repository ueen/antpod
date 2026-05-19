// lib/podcast_service.dart
//
// Ausschließlich PodcastIndex.org – kein iTunes.
//
// Endpoints genutzt:
//   /api/1.0/search/byterm        → Suche
//   /api/1.0/podcasts/trending    → Trending (7-day window, fetch 2× and take top-n)
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
        id: Value(feedUrl.isNotEmpty ? feedUrl : id),
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

  static Future<List<PodcastResult>> search(String query) async {
    try {
      final uri = Uri.parse('$_baseUrl/search/byterm')
          .replace(queryParameters: {'q': query, 'max': '20'});
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

  // ── Trending ───────────────────────────────────────────────────────────────
  // Uses a 7-day window so results reflect what's actually hot right now rather
  // than month-old activity. Fetches 2× the requested count then takes the top-n
  // by trendScore so we have room to filter without losing popular shows.

  static Future<List<PodcastResult>> trending({
    int max = 10,
    String lang = 'en',
    String? cat,
  }) async {
    final params = <String, String>{
      'max': '${max * 2}',
      'lang': lang,
      'since': '-604800', // 7 days — captures genuinely current viral content
    };
    if (cat != null && cat.isNotEmpty) params['cat'] = cat;

    final uri = Uri.parse('$_baseUrl/podcasts/trending').replace(queryParameters: params);
    final res = await http.get(uri, headers: _authHeaders());
    if (res.statusCode != 200) {
      throw Exception('API ${res.statusCode}: ${res.reasonPhrase}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final feeds = json['feeds'] as List? ?? [];
    // API returns results ranked by trendScore; just take the requested count
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
