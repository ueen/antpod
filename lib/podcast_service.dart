// lib/podcast_service.dart
//
// Ausschließlich PodcastIndex.org – kein iTunes.
// API-Key: WVABNRFZXMR56UKS7488
// Secret: wird über dart-define übergeben (PODCAST_INDEX_SECRET)
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

const _apiKey = 'WVABNRFZXMR56UKS7488';
// Secret über dart-define:  flutter run --dart-define=PODCAST_INDEX_SECRET=xxx
// Oder direkt eintragen:
const _apiSecret =
    String.fromEnvironment('PODCAST_INDEX_SECRET', defaultValue: '');

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
  // Endpoint: GET /podcasts/trending?max=10&lang=de,en&since=-604800
  // since=-604800 = letzte 7 Tage

  static Future<List<PodcastResult>> trending({
    int max = 10,
    String lang = 'de,en',
  }) async {
    final uri = Uri.parse('$_baseUrl/podcasts/trending').replace(
      queryParameters: {'max': '$max', 'lang': lang},
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

  // ── Empfehlungen ──────────────────────────────────────────────────────────
  // Strategie: extrahiere die häufigsten Kategorien der abonnierten Podcasts,
  // suche dann /podcasts/trending gefiltert nach diesen Kategorien,
  // filtere bekannte Podcasts heraus.

  static Future<List<PodcastResult>> recommendations({
    required List<Podcast> subscribed,
    int max = 10,
  }) async {
    if (subscribed.isEmpty) return trending(max: max);

    // Häufigste Kategorie aus Podcast-Titeln/Beschreibungen ableiten
    // (PodcastIndex gibt uns in /podcasts/trending auch cat-Filter)
    // Wir wählen die erste Kategorie, die wir aus dem Trending-Feed
    // und den abonnierten Titeln matchen können.
    // Einfachere Heuristik: suche nach Termen aus Titeln der Abos
    final terms = subscribed
        .map((p) => p.title.split(' ').first) // erstes Wort als Begriff
        .toSet()
        .take(3)
        .join(' ');

    try {
      // Trending + nach Kategorie-Keyword filtern
      final trendResults = await trending(max: 50);
      final subscribedFeedUrls =
          subscribed.map((p) => p.feedUrl).toSet();

      // Filtre Abos heraus
      final filtered = trendResults
          .where((r) => !subscribedFeedUrls.contains(r.feedUrl))
          .toList();

      if (filtered.isNotEmpty) {
        return filtered.take(max).toList();
      }

      // Fallback: Suche nach Termen
      final searchResults = await search(terms);
      return searchResults
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
        );
      }).toList();
      return (podcast: podcast, episodes: episodes);
    } catch (_) {
      return null;
    }
  }
}
