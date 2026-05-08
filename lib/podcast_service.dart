// lib/podcast_service.dart
//
// Ausschließlich PodcastIndex.org – kein iTunes.
//
// Endpoints genutzt:
//   /api/1.0/search/byterm        → Suche
//   /api/1.0/podcasts/trending    → Trending Top-10
//   /api/1.0/search/byterm        → Empfehlungen (nach Kategorie der Abos)

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

  // ── Trending Top-10 ────────────────────────────────────────────────────────
  // Endpoint: GET /podcasts/trending?max=10&lang=de,en&since=-2592000
  // since=-2592000 = last 30 days

  static Future<List<PodcastResult>> trending({
    int max = 10,
    String lang = 'en',
  }) async {
    final uri = Uri.parse('$_baseUrl/podcasts/trending').replace(
      queryParameters: {'max': '$max', 'lang': lang, 'since': '-2592000'},
    );
    final res = await http.get(uri, headers: _authHeaders());
    if (res.statusCode != 200) {
      throw Exception('API ${res.statusCode}: ${res.reasonPhrase}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final feeds = json['feeds'] as List? ?? [];
    return feeds
        .map((f) => PodcastResult.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  // ── Recommendations ───────────────────────────────────────────────────────
  // Strategy: look up subscribed podcasts on PodcastIndex to get their actual
  // categories, then fetch trending filtered by those categories. Falls back to
  // language-aware trending minus already-subscribed podcasts.

  static Future<List<PodcastResult>> recommendations({
    required List<Podcast> subscribed,
    int max = 10,
    String lang = 'en',
  }) async {
    if (subscribed.isEmpty) return trending(max: max, lang: lang);

    final subscribedFeedUrls = subscribed.map((p) => p.feedUrl).toSet();

    // Step 1: fetch PodcastIndex metadata for up to 5 subscribed podcasts
    // to collect their real categories.
    final categoryCount = <String, int>{};
    await Future.wait(subscribed.take(5).map((podcast) async {
      try {
        final uri = Uri.parse('$_baseUrl/podcasts/byfeedurl').replace(
          queryParameters: {'url': podcast.feedUrl},
        );
        final res = await http.get(uri, headers: _authHeaders());
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          final feed = body['feed'] as Map<String, dynamic>?;
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

    // Step 2: pick the top 2 categories and fetch trending filtered by them.
    final topCats = (categoryCount.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(2)
        .map((e) => e.key)
        .toList();

    if (topCats.isNotEmpty) {
      try {
        final uri = Uri.parse('$_baseUrl/podcasts/trending').replace(
          queryParameters: {
            'max': '${max * 4}',
            'lang': lang,
            'cat': topCats.join(','),
            'since': '-2592000',
          },
        );
        final res = await http.get(uri, headers: _authHeaders());
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          final feeds = body['feeds'] as List? ?? [];
          final results = feeds
              .map((f) => PodcastResult.fromJson(f as Map<String, dynamic>))
              .where((r) => !subscribedFeedUrls.contains(r.feedUrl))
              .take(max)
              .toList();
          if (results.length >= 3) return results;
        }
      } catch (_) {}
    }

    // Fallback: broad trending in the user's language, excluding subscriptions.
    try {
      final trendResults = await trending(max: 50, lang: lang);
      return trendResults
          .where((r) => !subscribedFeedUrls.contains(r.feedUrl))
          .take(max)
          .toList();
    } catch (_) {
      return [];
    }
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
